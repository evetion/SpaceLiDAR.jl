function get_dimensions(variable)
    dims = get(attrs(variable), "DIMENSION_LIST", nothing)
    isnothing(dims) && return nothing
    return (variable.file[d[1]] for d in dims)
end

"""
Return dimension paths without opening dataset objects.
"""
function get_dimension_paths(variable)
    dims = get(attrs(variable), "DIMENSION_LIST", nothing)
    isnothing(dims) && return nothing
    return (HDF5.name(variable.file[d[1]]) for d in dims)
end

function get_references(variable, dimension = 0)
    refs = get(attrs(variable), "REFERENCE_LIST", nothing)
    isnothing(refs) && return nothing
    gen = (variable.file[d.dataset] for d in refs if d.dimension == dimension)
    isempty(gen) && return nothing
    gen
end

"""
Return reference paths without keeping dataset objects open.
"""
function get_reference_paths(variable, dimension = 0)
    refs = get(attrs(variable), "REFERENCE_LIST", nothing)
    isnothing(refs) && return nothing
    paths = String[HDF5.name(variable.file[d.dataset]) for d in refs if d.dimension == dimension]
    isempty(paths) && return nothing
    paths
end


"""
    resolve_transform(spec, file, path) → 1-arg function

Resolve a transform spec into a concrete 1-arg function (closing over file data if needed).
The returned function operates on data that may contain `missing` values.
`path` is the full HDF5 path of the variable (used to resolve relative references).
"""
resolve_transform(::typeof(identity), ::HDF5.File, ::AbstractString) = identity
resolve_transform(t::ToDateTime, file::HDF5.File, ::AbstractString) =
    let
        epoch = HDF5.read(file[t.epoch_path])[1]::Float64 + t.offset
        function (data)
            if eltype(data) >: Missing
                [v === missing ? missing : unix2datetime(v + epoch) for v in data]
            else
                unix2datetime.(data .+ epoch)
            end
        end
    end
resolve_transform(t::ToDateTimeConst, ::HDF5.File, ::AbstractString) =
    let offset = t.offset
        function (data)
            if eltype(data) >: Missing
                [v === missing ? missing : unix2datetime(v + offset) for v in data]
            else
                unix2datetime.(data .+ offset)
            end
        end
    end
resolve_transform(::ToBool, ::HDF5.File, ::AbstractString) = function (data)
    if eltype(data) >: Missing
        [v === missing ? missing : !iszero(v) for v in data]
    else
        Bool[!iszero(v) for v in data]
    end
end
resolve_transform(::InvertBool, ::HDF5.File, ::AbstractString) = function (data)
    if eltype(data) >: Missing
        [v === missing ? missing : iszero(v) for v in data]
    else
        Bool[iszero(v) for v in data]
    end
end
resolve_transform(s::SliceRow, ::HDF5.File, ::AbstractString) =
    let row = s.row
        data -> data[row, :]
    end

"""
    apply_transform_dims(transform, vdims) -> Vector{String}

Return the effective dimension list a variable has *after* `transform` is
applied at read time. Used by the [`H5Table`](@ref) builder to make global
dimension resolution transform-aware.

The default for any transform (including `identity`, `ToDateTime`,
`ToDateTimeConst`, `ToBool`, `InvertBool`, `ExpandDims`) is to leave `vdims`
unchanged — these transforms operate elementwise (or 1D→1D) and don't change
the variable's axis identity.

`SliceRow(row)` performs `data[row, :]`, collapsing Julia axis 1 (HDF5 fast
axis) and keeping Julia axis 2 (HDF5 slow axis). The corresponding dim is
dropped from the front of `vdims`. Only meaningful for 2D variables; for 1D
input the read itself would fail, so this is a no-op for that edge case.
"""
apply_transform_dims(::Any, vdims::Vector{String}) = vdims
apply_transform_dims(::SliceRow, vdims::Vector{String}) =
    length(vdims) >= 2 ? vdims[2:end] : vdims

"""
    count2index(counts) → Vector{Int32}

Map segment-level counts to photon-level indices.
Each segment i is repeated counts[i] times.
"""
function count2index(counts)
    c = fill(zero(eltype(counts)), sum(counts))
    ref = 1
    for i in eachindex(counts)
        count = counts[i]
        c[ref:(ref+count-1)] .= i
        ref += count
    end
    c
end

resolve_transform(e::ExpandDims, file::HDF5.File, path::AbstractString) =
    let
        # Resolve counts_path relative to the same track prefix as the variable
        track = first(split(path, "/"))
        counts_path = "$track/$(e.counts_path)"
        counts = HDF5.read(file[counts_path])::Vector{Int32}
        idx = count2index(counts)
        data -> data[idx]
    end

# ─── Source interface ──────────────────────────────────────────────────────────
# An `H5Table` reads from a *source*. The trivial source is an `HDF5.File`, but a
# richer source (e.g. SpaceLiDAR's `GranuleSource`, or a future cloud reference)
# can carry provenance and resolve variables by name. A source must implement:
#
#   h5handle(source)::HDF5.File              — the (cached) open file to read from
#   source_metadata(source)::AbstractDict    — extra metadata merged into DataAPI
#   resolve_variable(source, name)::Union{Variable,Nothing}  — name → Variable spec
#
# `HDF5.File` is the trivial implementation (no extra metadata, no name
# resolution), which keeps this submodule usable as a standalone reader.

"""
Return the open `HDF5.File` to read from for a given source.
"""
h5handle(f::HDF5.File) = f

"""
Extra table-level metadata (`String` keys) contributed by a source, merged
with the HDF5 file attributes. Defaults to empty.
"""
source_metadata(::Any) = Dict{String,Any}()

"""
Resolve a column `name` to a [`Variable`](@ref) spec using source context
(e.g. a granule's `default_variables`). Returns `nothing` when the source has no
knowledge of `name`. Generic sources (a bare `HDF5.File`) cannot resolve names.
"""
resolve_variable(::Any, ::Symbol) = nothing

"""
Resolve a [`Variable`](@ref) spec against a source, returning a build-ready
`Variable` (nodata mask + transform composed via [`make_variable`](@ref)) or
`nothing` if its dataset is absent. The generic method reads `v.path` verbatim;
richer sources (e.g. a granule source carrying a track) may override to rewrite
the path first.
"""
function resolve_variable(source, v::Variable)
    file = h5handle(source)
    haskey(file, v.path) || return nothing
    return make_variable(file, v.name, v.path; transform = v.f)
end


"""
    build_mask(ds::HDF5.Dataset) -> Union{typeof(identity), Nodata, NodataRange}

Build a nodata mask from dataset attributes. Returns `identity` if no nodata metadata exists.

# Examples

```julia
Nodata(3.4028235f38)([1.0f0, 3.4028235f38, 2.0f0])
# → Union{Float32,Missing}[1.0, missing, 2.0]

NodataRange(-90.0f0, 90.0f0)([-100.0f0, 0.0f0, 91.0f0])
# → Union{Float32,Missing}[missing, 0.0, missing]
```
"""
function build_mask(ds::HDF5.Dataset)
    a = HDF5.attrs(ds)

    fill_val = get(a, "_FillValue", nothing)
    if !isnothing(fill_val)
        fill_val = fill_val isa AbstractArray ? first(fill_val) : fill_val
        return Nodata(fill_val)
    end

    valid_range = get(a, "valid_range", nothing)
    if !isnothing(valid_range)
        lo = valid_range isa AbstractArray ? first(valid_range) : valid_range
        hi = valid_range isa AbstractArray ? last(valid_range) : valid_range
        return NodataRange(lo, hi)
    end

    valid_min = get(a, "valid_min", nothing)
    valid_max = get(a, "valid_max", nothing)
    if !isnothing(valid_min) && !isnothing(valid_max)
        valid_min = valid_min isa AbstractArray ? first(valid_min) : valid_min
        valid_max = valid_max isa AbstractArray ? first(valid_max) : valid_max
        return NodataRange(valid_min, valid_max)
    end

    return identity
end

"""
Collect related datasets (dimensions or references) as name=>path pairs.
"""
function include_related!(pairs, included_paths, related)
    isnothing(related) && return
    for ds in related
        path = lstrip(HDF5.name(ds), '/')
        path in included_paths && continue
        push!(included_paths, path)
        name = Symbol(split(path, "/")[end])
        push!(pairs, name => path)
    end
end

"""
Collect related paths (from get_dimension_paths/get_reference_paths) as name=>path pairs.
"""
function include_related_paths!(pairs, included_paths, paths)
    isnothing(paths) && return
    for fullpath in paths
        path = lstrip(fullpath, '/')
        path in included_paths && continue
        push!(included_paths, path)
        name = Symbol(split(path, "/")[end])
        push!(pairs, name => path)
    end
end


"""
    resolve_coord_path(file, var_path, coord_name) -> Union{String, Nothing}

Resolve a CF `coordinates` entry to an HDF5 path relative to the variable's location.

Handles plain names (sibling), relative paths (`../`), and absolute paths.
Returns `nothing` if the coordinate cannot be found in the file.

# Examples

```julia
julia> resolve_coord_path(file, "BEAM0000/geolocation/elevs", "../delta_time")
"BEAM0000/delta_time"

julia> resolve_coord_path(file, "BEAM0000/rh", "lat_lowestmode")
"BEAM0000/lat_lowestmode"
```
"""
function resolve_coord_path(file, var_path, coord_name)
    cstr = String(coord_name)

    # Determine the parent directory of the variable
    parent_dir = rsplit(var_path, "/", limit = 2)
    parent = length(parent_dir) == 2 ? parent_dir[1] : ""

    # Resolve relative path segments (../)
    if startswith(cstr, "..")
        segments = split(parent, "/")
        while startswith(cstr, "../")
            cstr = cstr[4:end]           # strip leading ../
            segments = segments[1:(end-1)]  # go up one level
        end
        cpath = isempty(segments) ? cstr : join(segments, "/") * "/" * cstr
    elseif contains(cstr, "/")
        # Absolute path within the file
        cpath = cstr
    else
        # Plain name → sibling of variable
        cpath = parent == "" ? cstr : parent * "/" * cstr
    end

    haskey(file, cpath) && return cpath
    # Fallback: try as-is (e.g. root-level coordinate)
    haskey(file, String(coord_name)) && return String(coord_name)
    return nothing
end

"""
    resolve_var_dims(file, path) -> (dim_ids::Vector{String}, dim_sizes::Dict{String,Int})

Determine the dimension identifiers for a variable, returned in Julia axis order
(index 1 = fastest varying in memory).

Each dimension is identified by the absolute HDF5 path of its coordinate/scale variable.
Variables sharing the same dimension will have matching IDs, which is how
[`compute_flattening`](@ref) knows which axes align.

# Resolution strategy (first match wins)

 1. **`DIMENSION_LIST` attribute** (HDF5 Dimension Scales spec):
    Explicit references to scale datasets. Reversed to Julia column-major axis order.

 2. **`CLASS = "DIMENSION_SCALE"` or `REFERENCE_LIST`**:
    The variable itself IS a dimension scale. Its own path is its dimension ID.

 3. **CF `coordinates` attribute**:
    Space-separated coordinate names. Resolved via [`resolve_coord_path`](@ref).
    Multiple coordinates of the same length map to the same axis (e.g. lat/lon both
    have length N → same shot dimension). The first coordinate of each unique size
    becomes the canonical ID for that axis.

 4. **No metadata (fallback)**:
    Uses the variable's own HDF5 path as dim ID. This means it can only match itself
    in flattening — appropriate for 1D variables without relationships.
    Errors for multi-dimensional variables since we can't infer dimension sharing.

# Examples

```julia
julia> resolve_var_dims(file, "gt1l/land_segments/latitude")
(["/gt1l/land_segments/delta_time"], Dict("/gt1l/land_segments/delta_time" => 998))

julia> resolve_var_dims(file, "gt1l/land_segments/latitude_20m")  # (5, 998) array
(["/ds_geosegments", "/gt1l/land_segments/delta_time"], Dict(...))
```
"""
function resolve_var_dims(file, path)
    ds = file[path]
    dim_sizes = Dict{String,Int}()

    # Case 1: HDF5 dimension scales — explicit, authoritative
    dims = get_dimensions(ds)
    if !isnothing(dims)
        dpaths = String[]
        for dim in dims
            dp = HDF5.name(dim)
            push!(dpaths, dp)
            dim_sizes[dp] = length(dim)
        end
        # HDF5 lists dims slow→fast; Julia is column-major (axis 1 = fast)
        return reverse(dpaths), dim_sizes
    end

    # Case 2: This IS a dimension scale (e.g. delta_time with REFERENCE_LIST)
    if get(HDF5.attrs(ds), "CLASS", nothing) == "DIMENSION_SCALE" ||
       !isnothing(get(HDF5.attrs(ds), "REFERENCE_LIST", nothing))
        dp = HDF5.name(ds)
        dim_sizes[dp] = length(ds)
        return [dp], dim_sizes
    end

    # Case 3: CF coordinates — resolve coordinate names to axes by matching sizes
    coords_str = get(HDF5.attrs(ds), "coordinates", nothing)
    sz = size(ds)
    if !isnothing(coords_str)
        coord_names = split(coords_str)
        axis_dims = fill("", ndims(ds))
        seen_sizes = Dict{Int,String}()  # size → canonical dim path (first coord wins)
        for cname in coord_names
            cpath = resolve_coord_path(file, path, cname)
            isnothing(cpath) && continue
            cds = file[cpath]
            clen = length(cds)
            canonical = HDF5.name(cds)
            # First coordinate of a given size becomes canonical for that axis
            haskey(seen_sizes, clen) && continue
            seen_sizes[clen] = canonical
            dim_sizes[canonical] = clen
            # Assign to first unassigned axis matching this size
            for (i, s) in enumerate(sz)
                if s == clen && axis_dims[i] == ""
                    axis_dims[i] = canonical
                    break
                end
            end
        end
        # Axes not covered by any coordinate get a synthetic dim ID.
        # This happens for "extra" dimensions like percentile bins in rh (101×N)
        # where coordinates only describe the N (shot) axis.
        # The synthetic ID is unique to this variable, so only variables with the
        # same shape+coordinates can share it (which is correct — they'd be vec'd together).
        for (i, d) in enumerate(axis_dims)
            if d == ""
                synthetic = "$(HDF5.name(ds))__dim$(i)"
                axis_dims[i] = synthetic
                dim_sizes[synthetic] = sz[i]
            end
        end
        return axis_dims, dim_sizes
    end

    # Case 4: No metadata at all — use own path as a 1D dim ID
    if ndims(ds) == 1
        dp = HDF5.name(ds)
        dim_sizes[dp] = sz[1]
        return [dp], dim_sizes
    end
    throw(
        ArgumentError(
            "Cannot determine dimensions of '$(path)' ($(ndims(ds))D, size $sz): " *
            "no DIMENSION_LIST, DIMENSION_SCALE class, or coordinates attribute found."),
    )
end

"""
    resolve_global_dims(file, paths) -> (global_dims::Vector{String}, dim_sizes::Dict{String,Int})

Determine the global dimension order from a set of variable paths.

The variable with the most dimensions defines the global axis order.
Returns the ordered list of dimension IDs and their sizes.

# Examples

```
julia> resolve_global_dims(file, ["gt1l/.../latitude_20m", "gt1l/.../latitude"])
(["/ds_geosegments", "/gt1l/.../delta_time"], Dict("/ds_geosegments" => 5, ...))
```
"""
function resolve_global_dims(file, paths)
    all_dims = Dict{String,Vector{String}}()
    dim_sizes = Dict{String,Int}()
    for path in paths
        vdims, vsizes = resolve_var_dims(file, path)
        all_dims[path] = vdims
        merge!(dim_sizes, vsizes)
    end

    global_dims = _pick_global_dims(all_dims)

    return global_dims, dim_sizes, all_dims
end

"""
    _pick_global_dims(all_dims) -> Vector{String}

Pick the global dimension order from a `path => dims` mapping: the variable
with the most dimensions wins. Validates that every variable's dims appear
in the same relative order as the chosen global order — flattening `(a, b)`
against `(b, a)` is unsupported and throws `ArgumentError`.
"""
function _pick_global_dims(all_dims::AbstractDict{<:AbstractString,Vector{String}})
    global_dims = String[]
    for (_, dpaths) in all_dims
        if length(dpaths) > length(global_dims)
            global_dims = dpaths
        end
    end

    if length(global_dims) > 1
        global_order = Dict(d => i for (i, d) in enumerate(global_dims))
        for (path, dpaths) in all_dims
            positions = [global_order[d] for d in dpaths if haskey(global_order, d)]
            if !issorted(positions)
                throw(
                    ArgumentError(
                        "Variable at '$path' has dimensions in an order inconsistent with " *
                        "the global dimension order. Cannot flatten (a,b) with (b,a)."),
                )
            end
        end
    end

    return global_dims
end

"""
    compute_repeat(global_dims, dim_sizes, var_dims) -> (inner::Int, outer::Int)

Compute the inner/outer repeat factors for a single variable given the global dimension context.

  - `global_dims`: ordered list of all dimensions (from [`resolve_global_dims`](@ref))
  - `dim_sizes`: dimension ID → size mapping
  - `var_dims`: this variable's dimension IDs (from [`resolve_var_dims`](@ref))

# Examples

```
julia> compute_repeat(["/geoseg", "/time"], Dict("/geoseg"=>5, "/time"=>998), ["/time"])
(inner = 5, outer = 1)

julia> compute_repeat(["/geoseg", "/time"], Dict("/geoseg"=>5, "/time"=>998), ["/geoseg", "/time"])
(inner = 1, outer = 1)
```
"""
function compute_repeat(global_dims, dim_sizes, var_dims)
    # Trivial cases
    length(global_dims) <= 1 && return (inner = 1, outer = 1)
    length(var_dims) >= length(global_dims) && return (inner = 1, outer = 1)

    var_dims_set = Set(var_dims)
    positions = [i for (i, gd) in enumerate(global_dims) if gd in var_dims_set]
    isempty(positions) && return (inner = 1, outer = 1)

    min_pos = minimum(positions)
    max_pos = maximum(positions)

    inner = 1
    outer = 1
    for (i, gd) in enumerate(global_dims)
        gd in var_dims_set && continue
        if i < min_pos
            inner *= dim_sizes[gd]
        elseif i > max_pos
            outer *= dim_sizes[gd]
        else
            throw(
                ArgumentError(
                    "Variable has non-contiguous dimensions in the global " *
                    "order (dims at positions $positions, gap at $i). " *
                    "Cannot flatten with inner/outer repeat."),
            )
        end
    end
    return (inner = inner, outer = outer)
end

"""
    is_dim_compatible(file, global_dims, dim_sizes, candidate_path) -> Bool

Check whether a candidate variable can be flattened into a table with the given global dimensions.

Returns `true` if the variable's dimensions are a contiguous, order-consistent subset
of `global_dims`. Use this to filter selectable variables in a UI before adding them.

# Examples

```
julia> gd, ds = resolve_global_dims(file, ["gt1l/.../latitude_20m"])
julia> is_dim_compatible(file, gd, ds, "gt1l/.../latitude")  # shares /time dim
true

julia> is_dim_compatible(file, gd, ds, "some/unrelated/var")  # different dims
false
```
"""
function is_dim_compatible(file, global_dims, dim_sizes, candidate_path)
    vdims = try
        first(resolve_var_dims(file, candidate_path))
    catch
        return false
    end

    # Empty global dims — anything 1D is compatible
    isempty(global_dims) && return length(vdims) <= 1

    var_dims_set = Set(vdims)
    global_order = Dict(d => i for (i, d) in enumerate(global_dims))

    # All of the candidate's dims must exist in global_dims
    positions = Int[]
    for d in vdims
        haskey(global_order, d) || return false
        push!(positions, global_order[d])
    end

    # Must be in same relative order
    issorted(positions) || return false

    # Must be contiguous (no gaps)
    if length(positions) >= 2
        min_pos = minimum(positions)
        max_pos = maximum(positions)
        for i = min_pos:max_pos
            gd = global_dims[i]
            if !(gd in var_dims_set)
                return false
            end
        end
    end

    return true
end

"""
    compute_flattening(file, paths) -> (mapping, nrow)

Convenience wrapper: resolves global dims and computes repeat factors for all paths at once.
"""
function compute_flattening(file, paths)
    global_dims, dim_sizes, all_var_dims = resolve_global_dims(file, paths)
    nrow = isempty(global_dims) ? 1 : prod(dim_sizes[d] for d in global_dims)

    mapping = Dict{String,@NamedTuple{inner::Int,outer::Int}}()
    for path in paths
        vdims = get(all_var_dims, path, String[])
        mapping[path] = compute_repeat(global_dims, dim_sizes, vdims)
    end

    return mapping, nrow
end

"""
Build a Variable struct from a dataset, detecting flag meanings for categorical encoding.
"""
function make_variable(file, name::Symbol, path::AbstractString, flat = (inner = 1, outer = 1); transform = identity)
    ds = HDF5.open_dataset(file, path)
    T = eltype(ds)
    flag_meanings = get(HDF5.attrs(ds), "flag_meanings", nothing)
    flag_values = get(HDF5.attrs(ds), "flag_values", nothing)
    if transform === identity && !isnothing(flag_meanings) && !isnothing(flag_values)
        # Auto-detect categorical only when no explicit transform is requested
        meanings = string.(split(flag_meanings))
        pool = CategoricalArrays.CategoricalPool(meanings)
        value_to_ref = Dict(fv => UInt32(i) for (i, fv) in enumerate(flag_values))
        f = x -> CategoricalArray{String,1}(UInt32[get(value_to_ref, v, UInt32(0)) for v in x], pool)
    else
        mask = build_mask(ds)
        resolved = resolve_transform(transform, file, path)
        # Compose: mask first (raw → missing), then transform (handles missing via passmissing)
        f = if resolved === identity
            mask
        elseif mask === identity
            resolved
        else
            resolved ∘ mask
        end
    end
    close(ds)
    Variable(name = name, path = path, f = f, eltype = T, inner = flat.inner, outer = flat.outer)
end
