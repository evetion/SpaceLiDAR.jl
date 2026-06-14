function get_dimensions(variable)
    dims = get(attrs(variable), "DIMENSION_LIST", nothing)
    isnothing(dims) && return nothing
    return (variable.file[d[1]] for d in dims)
end

"""Return dimension paths without opening dataset objects."""
function get_dimension_paths(variable)
    dims = get(attrs(variable), "DIMENSION_LIST", nothing)
    isnothing(dims) && return nothing
    return (HDF5.name(variable.file[d[1]]) for d in dims)
end

function get_references(variable, dimension=0)
    refs = get(attrs(variable), "REFERENCE_LIST", nothing)
    isnothing(refs) && return nothing
    gen = (variable.file[d.dataset] for d in refs if d.dimension == dimension)
    isempty(gen) && return nothing
    gen
end

"""Return reference paths without keeping dataset objects open."""
function get_reference_paths(variable, dimension=0)
    refs = get(attrs(variable), "REFERENCE_LIST", nothing)
    isnothing(refs) && return nothing
    paths = String[HDF5.name(variable.file[d.dataset]) for d in refs if d.dimension == dimension]
    isempty(paths) && return nothing
    paths
end

Base.@kwdef struct Variable
    name::Symbol
    path::String
    f::Any=identity
    eltype::Type=Any
    inner::Int=1
    outer::Int=1
end
Variable(name::Symbol, path::String, T::Type, f=identity) =
    Variable(name=name, path=path, eltype=T, f=f)

Base.@kwdef struct Attribute
    name::Symbol
    group::String
    attribute::String
    f::Function=identity
    eltype::DataType=Any
end
Attribute(name::Symbol, attribute::String, f::Function=identity) =
    Attribute(name=name, group="", attribute=attribute, f=f)

# ─── Transform types (specs resolved at build time into 1-arg closures) ────────

# Convert delta_time to DateTime using an epoch dataset in the file
struct ToDateTime
    epoch_path::String
    offset::Float64
end

# Convert delta_time to DateTime using a constant offset
struct ToDateTimeConst
    offset::Float64
end

# Convert to Bool (nonzero → true)
struct ToBool end

# Invert Bool (0 → true, nonzero → false)
struct InvertBool end

# Slice a specific row from a 2D dataset.
# At read time, performs `data[row, :]`, collapsing Julia axis 1
# (the HDF5 fast axis) and keeping Julia axis 2 (the HDF5 slow axis).
# The result is a 1D vector of length `size(data, 2)`.
#
# For dimension resolution, see `apply_transform_dims(::SliceRow, vdims)`:
# the sliced axis is dropped while the remaining axis still participates
# in the global dimension context.
struct SliceRow
    row::Int
end

# Expand segment-level data to photon-level using a counts dataset (count2index)
struct ExpandDims
    counts_path::String
end

"""
    resolve_transform(spec, file, path) → 1-arg function

Resolve a transform spec into a concrete 1-arg function (closing over file data if needed).
The returned function operates on data that may contain `missing` values.
`path` is the full HDF5 path of the variable (used to resolve relative references).
"""
resolve_transform(::typeof(identity), ::HDF5.File, ::AbstractString) = identity
resolve_transform(t::ToDateTime, file::HDF5.File, ::AbstractString) = let
    epoch = HDF5.read(file[t.epoch_path])[1]::Float64 + t.offset
    function (data)
        if eltype(data) >: Missing
            [v === missing ? missing : unix2datetime(v + epoch) for v in data]
        else
            unix2datetime.(data .+ epoch)
        end
    end
end
resolve_transform(t::ToDateTimeConst, ::HDF5.File, ::AbstractString) = let offset = t.offset
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
resolve_transform(s::SliceRow, ::HDF5.File, ::AbstractString) = let row = s.row
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
        c[ref:ref+count-1] .= i
        ref += count
    end
    c
end

resolve_transform(e::ExpandDims, file::HDF5.File, path::AbstractString) = let
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

"""Return the open `HDF5.File` to read from for a given source."""
h5handle(f::HDF5.File) = f

"""Extra table-level metadata (`String` keys) contributed by a source, merged
with the HDF5 file attributes. Defaults to empty."""
source_metadata(::Any) = Dict{String,Any}()

"""Resolve a column `name` to a [`Variable`](@ref) spec using source context
(e.g. a granule's `default_variables`). Returns `nothing` when the source has no
knowledge of `name`. Generic sources (a bare `HDF5.File`) cannot resolve names."""
resolve_variable(::Any, ::Symbol) = nothing

Base.@kwdef struct H5Table{S}
    f::S
    vars::Vector{Variable}
    attrs::Vector{Attribute}
    nrow::Int=0
end

function Base.show(io::IO, t::H5Table)
    print(io, "H5Table($(basename(HDF5.filename(h5handle(t.f)))), $(length(t.vars)) columns, $(t.nrow) rows)")
end

_show_transform(f) = f === identity ? "" : "  → $f"

function Base.show(io::IO, ::MIME"text/plain", t::H5Table)
    println(io, "H5Table: $(basename(HDF5.filename(h5handle(t.f))))")
    println(io, "  Rows: $(t.nrow)")
    println(io, "  Columns: $(length(t.vars) + length(t.attrs))")
    println(io, "  ─────────────────────────────────")
    # Compute column widths for alignment
    all_names = vcat([string(":", v.name) for v in t.vars], [string(":", a.name) for a in t.attrs])
    all_types = vcat([string(v.eltype) for v in t.vars], [string(a.eltype) for a in t.attrs])
    name_w = maximum(length, all_names; init=0)
    type_w = maximum(length, all_types; init=0)
    for v in t.vars
        n = rpad(string(":", v.name), name_w)
        ty = rpad(string(v.eltype), type_w)
        rep = (v.inner > 1 || v.outer > 1) ? "  (×$(v.inner * v.outer))" : ""
        tf = _show_transform(v.f)
        println(io, "  $n ::$ty$rep$tf")
    end
    for a in t.attrs
        n = rpad(string(":", a.name), name_w)
        ty = rpad(string(a.eltype), type_w)
        println(io, "  $n ::$ty  (attr)")
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
    parent_dir = rsplit(var_path, "/", limit=2)
    parent = length(parent_dir) == 2 ? parent_dir[1] : ""

    # Resolve relative path segments (../)
    if startswith(cstr, "..")
        segments = split(parent, "/")
        while startswith(cstr, "../")
            cstr = cstr[4:end]           # strip leading ../
            segments = segments[1:end-1]  # go up one level
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
    throw(ArgumentError(
        "Cannot determine dimensions of '$(path)' ($(ndims(ds))D, size $sz): " *
        "no DIMENSION_LIST, DIMENSION_SCALE class, or coordinates attribute found."))
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
                throw(ArgumentError(
                    "Variable at '$path' has dimensions in an order inconsistent with " *
                    "the global dimension order. Cannot flatten (a,b) with (b,a)."))
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
    length(global_dims) <= 1 && return (inner=1, outer=1)
    length(var_dims) >= length(global_dims) && return (inner=1, outer=1)

    var_dims_set = Set(var_dims)
    positions = [i for (i, gd) in enumerate(global_dims) if gd in var_dims_set]
    isempty(positions) && return (inner=1, outer=1)

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
            throw(ArgumentError(
                "Variable has non-contiguous dimensions in the global " *
                "order (dims at positions $positions, gap at $i). " *
                "Cannot flatten with inner/outer repeat."))
        end
    end
    return (inner=inner, outer=outer)
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
        for i in min_pos:max_pos
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

    mapping = Dict{String,@NamedTuple{inner::Int, outer::Int}}()
    for path in paths
        vdims = get(all_var_dims, path, String[])
        mapping[path] = compute_repeat(global_dims, dim_sizes, vdims)
    end

    return mapping, nrow
end

"""Build a Variable struct from a dataset, detecting flag meanings for categorical encoding."""
function make_variable(file, name::Symbol, path::AbstractString, flat=(inner=1, outer=1); transform=identity)
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
    Variable(name=name, path=path, f=f, eltype=T, inner=flat.inner, outer=flat.outer)
end

"""Sentinel-based nodata mask. Replaces values equal to `sentinel` with `missing`."""
struct Nodata{T}
    sentinel::T
end
function (nd::Nodata)(data::AbstractArray)
    T = Union{eltype(data),Missing}
    return T[v == nd.sentinel ? missing : v for v in data]
end

"""Range-based nodata mask. Replaces values outside `[lo, hi]` with `missing`."""
struct NodataRange{T}
    lo::T
    hi::T
end
function (nd::NodataRange)(data::AbstractArray)
    T = Union{eltype(data),Missing}
    return T[nd.lo <= v <= nd.hi ? v : missing for v in data]
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

"""Collect related datasets (dimensions or references) as name=>path pairs."""
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

"""Collect related paths (from get_dimension_paths/get_reference_paths) as name=>path pairs."""
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

function H5Table(source; vars::Vector{Pair{Symbol,String}}, attrs::Vector{Pair{Symbol,String}}=Pair{Symbol,String}[], transforms::Dict{Symbol}=Dict{Symbol,Any}(), include_dimensions::Bool=false, include_references::Bool=false, nrow::Union{Int,Nothing}=nothing)
    file = h5handle(source)
    # 1. Collect all name => path pairs (no Variable structs yet)
    pairs = copy(vars)
    included_paths = Set(last.(vars))

    for (_, path) in vars
        ds = HDF5.open_dataset(file, path)
        if include_references
            include_related_paths!(pairs, included_paths, get_reference_paths(ds))
        end
        if include_dimensions
            include_related_paths!(pairs, included_paths, get_dimension_paths(ds))
        end
        close(ds)
    end

    # 2. Resolve global dimension context (skip if nrow provided — all vars are flat)
    #
    # Design: H5Table is the generic table reader. When called from explore() or
    # directly with name=>path pairs, multi-dimensional datasets participate fully
    # in dimension resolution so their axes define the global row count (flattening).
    # Schema-based constructors (SpaceLiDAR templates) bypass this by passing an
    # explicit `nrow`, which skips dimension resolution entirely for speed.
    #
    # Transform-aware: each variable's raw axes are filtered through
    # `apply_transform_dims(transform, vdims)` before resolving the global
    # context. For example `SliceRow(row)` does `data[row, :]` on a 2D dataset,
    # collapsing Julia axis 1 (HDF5 fast axis) while keeping axis 2. The dropped
    # axis must not inflate the global row count, but the remaining axis still
    # needs to participate so the resulting 1D vector is correctly aligned with
    # the global axis (and can even define it if no other variable mentions it).
    # All other built-in transforms (identity, ToDateTime, ToBool, InvertBool,
    # ExpandDims, ...) are dim-preserving and fall through unchanged — see
    # `apply_transform_dims` for the per-transform rules.
    if isnothing(nrow)
        all_var_dims = Dict{String,Vector{String}}()
        dim_sizes = Dict{String,Int}()
        for (name, path) in pairs
            vdims, vsizes = resolve_var_dims(file, path)
            t = get(transforms, name, identity)
            all_var_dims[path] = apply_transform_dims(t, vdims)
            merge!(dim_sizes, vsizes)
        end
        global_dims = _pick_global_dims(all_var_dims)
        nrow = isempty(global_dims) ? 1 : prod(dim_sizes[d] for d in global_dims)
    else
        global_dims = String[]
        dim_sizes = Dict{String,Int}()
        all_var_dims = Dict{String,Vector{String}}()
    end

    # 3. Build Variable structs using cached dims
    variable_structs = Variable[]
    sizehint!(variable_structs, length(pairs))
    trivial_flat = (inner=1, outer=1)
    for (name, path) in pairs
        vdims = get(all_var_dims, path, String[])
        flat = isempty(global_dims) ? trivial_flat : compute_repeat(global_dims, dim_sizes, vdims)
        transform = get(transforms, name, identity)
        push!(variable_structs, make_variable(file, name, path, flat; transform))
    end

    attribute_structs = Attribute[]
    for (name, path) in attrs
        group, attribute = rsplit(path, "/", limit=2)
        obj_id = HDF5.API.h5o_open(file, group, HDF5.API.H5P_DEFAULT)
        attr_id = HDF5.API.h5a_open(obj_id, attribute, HDF5.API.H5P_DEFAULT)
        attr_obj = HDF5.Attribute(attr_id, file)
        attribute = Attribute(name, group, attribute, Base.Fix2(Fill, nrow), eltype(attr_obj))
        close(attr_obj)
        HDF5.API.h5o_close(obj_id)
        push!(attribute_structs, attribute)
    end
    return H5Table(f=source, vars=variable_structs, attrs=attribute_structs, nrow=nrow)
end
H5Table(fn::AbstractString; kwargs...) = H5Table(HDF5.h5open(fn, "r"); kwargs...)

"""
    H5Table(template::H5Table, track::AbstractString, old_track::AbstractString)

Create a new H5Table by remapping paths from `old_track` to `track`, reusing
the Variable/Attribute structures (masks, transforms, nrow) from `template`.
Avoids redundant HDF5 attribute reads for identically-structured tracks.
"""
function H5Table(template::H5Table, track::AbstractString, old_track::AbstractString)
    prefix_old = old_track * "/"
    prefix_new = track * "/"
    variable_structs = map(template.vars) do v
        path = replace(v.path, prefix_old => prefix_new; count=1)
        Variable(name=v.name, path=path, f=v.f, eltype=v.eltype, inner=v.inner, outer=v.outer)
    end
    # Determine nrow from the first variable's dataset length
    nrow = length(h5handle(template.f)[variable_structs[1].path])
    attribute_structs = map(template.attrs) do a
        group = replace(a.group, prefix_old => prefix_new; count=1)
        Attribute(name=a.name, group=group, attribute=a.attribute, f=Base.Fix2(Fill, nrow), eltype=a.eltype)
    end
    return H5Table(f=template.f, vars=variable_structs, attrs=attribute_structs, nrow=nrow)
end


"""
    _h5read(file, path, T) -> Array{T}

Fast dataset read using low-level HDF5 API with known type.
Returns a Vector for 1D datasets, a Matrix for 2D, etc.
Falls back to `HDF5.read` for non-primitive types (strings, compounds).
"""
function _h5read(file::HDF5.File, path::String, ::Type{T}) where T
    if isbitstype(T)
        ds = HDF5.open_dataset(file, path)
        dspace = HDF5.dataspace(ds)
        dims, _ = HDF5.API.h5s_get_simple_extent_dims(dspace)
        close(dspace)
        n = prod(dims)
        buf = Vector{T}(undef, n)
        memtype = HDF5.datatype(T)
        HDF5.API.h5d_read(ds, memtype, HDF5.API.H5S_ALL, HDF5.API.H5S_ALL, HDF5.API.H5P_DEFAULT, buf)
        close(memtype)
        close(ds)
        length(dims) == 1 && return buf
        # HDF5 dims are C-order (row-major); reverse for Julia's column-major
        return reshape(buf, Int.(reverse(dims))...)
    else
        return HDF5.read(HDF5.open_dataset(file, path))
    end
end
# Fallback for Any eltype (e.g. from explore() where type wasn't declared)
_h5read(file::HDF5.File, path::String, ::Type{Any}) =
    HDF5.read(HDF5.open_dataset(file, path))

"""
    _h5read_attr(file, parent_path, attr_name, T) -> value

Fast attribute read using low-level HDF5 API with known type.
Uses h5o_open to open the parent (works for both groups and datasets).
For numeric types (Integer/AbstractFloat), reads directly into a typed buffer.
Falls back to `read(::Attribute)` for strings and other types.
"""
function _h5read_attr(file::HDF5.File, parent_path::String, attr_name::String, ::Type{T}) where T
    obj_id = HDF5.API.h5o_open(file, parent_path, HDF5.API.H5P_DEFAULT)
    attr_id = HDF5.API.h5a_open(obj_id, attr_name, HDF5.API.H5P_DEFAULT)
    if T <: Union{Integer,AbstractFloat}
        memtype = HDF5.datatype(T)
        buf = Ref{T}()
        HDF5.API.h5a_read(attr_id, memtype, buf)
        close(memtype)
        HDF5.API.h5a_close(attr_id)
        HDF5.API.h5o_close(obj_id)
        return buf[]
    else
        attr = HDF5.Attribute(attr_id, file)
        val = read(attr)
        close(attr)
        HDF5.API.h5o_close(obj_id)
        return val
    end
end
_h5read_attr(file::HDF5.File, parent_path::String, attr_name::String) =
    _h5read_attr(file, parent_path, attr_name, Any)

Tables.istable(::Type{<:H5Table}) = true
Tables.columnaccess(::Type{<:H5Table}) = true
Tables.columns(x::H5Table) = x
function Tables.columnnames(x::H5Table)
    names = Symbol[v.name for v in x.vars]
    for a in x.attrs
        a.name in names || push!(names, a.name)
    end
    names
end
function Tables.getcolumn(table::H5Table, name::Symbol)
    vari = findfirst(v -> v.name == name, table.vars)
    if !isnothing(vari)
        var = table.vars[vari]
        raw = _h5read(h5handle(table.f), var.path, var.eltype)
        data = vec(var.f(raw))
        if var.inner > 1 || var.outer > 1
            data = repeat(data, inner=var.inner, outer=var.outer)
        end
        return data
    end
    attri = findfirst(a -> a.name == name, table.attrs)
    if !isnothing(attri)
        attr = table.attrs[attri]
        data = _h5read_attr(h5handle(table.f), attr.group, attr.attribute, attr.eltype)
        return attr.f(data)
    end
    throw(ArgumentError("Column $name not found"))
end
Tables.getcolumn(x::H5Table, i::Int) = Tables.getcolumn(x, Tables.columnnames(x)[i])

# ─── PartitionedH5Table ───────────────────────────────────────────────────────

struct PartitionedH5Table
    tables::Vector{H5Table}
end

Tables.istable(::Type{PartitionedH5Table}) = true
Tables.columnaccess(::Type{PartitionedH5Table}) = true
Tables.columns(x::PartitionedH5Table) = x
Tables.partitions(x::PartitionedH5Table) = x.tables
function Tables.columnnames(x::PartitionedH5Table)
    isempty(x.tables) ? Symbol[] : Tables.columnnames(x.tables[1])
end
function Tables.getcolumn(x::PartitionedH5Table, name::Symbol)
    reduce(vcat, [Tables.getcolumn(t, name) for t in x.tables])
end
Tables.getcolumn(x::PartitionedH5Table, i::Int) = Tables.getcolumn(x, Tables.columnnames(x)[i])
function Tables.schema(x::PartitionedH5Table)
    isempty(x.tables) && return Tables.Schema(Symbol[], Type[])
    Tables.schema(x.tables[1])
end

Base.length(x::PartitionedH5Table) = length(x.tables)
Base.getindex(x::PartitionedH5Table, i) = x.tables[i]
Base.iterate(x::PartitionedH5Table, args...) = iterate(x.tables, args...)

DataAPI.nrow(x::PartitionedH5Table) = sum(t.nrow for t in x.tables)
DataAPI.ncol(x::PartitionedH5Table) = isempty(x.tables) ? 0 : DataAPI.ncol(x.tables[1])

function Base.show(io::IO, ts::PartitionedH5Table)
    total = sum(t.nrow for t in ts.tables)
    print(io, "$(length(ts.tables))×H5Table($(basename(HDF5.filename(h5handle(ts.tables[1].f)))), $(DataAPI.ncol(ts.tables[1])) columns, $total rows)")
end

function Base.show(io::IO, ::MIME"text/plain", ts::PartitionedH5Table)
    total = sum(t.nrow for t in ts.tables)
    println(io, "$(length(ts.tables))×H5Table: $(basename(HDF5.filename(h5handle(ts.tables[1].f))))")
    println(io, "  Partitions: $(length(ts.tables))")
    println(io, "  Total rows: $total")
    println(io, "  Rows per partition: $(join([string(t.nrow) for t in ts.tables], ", "))")
    t = ts.tables[1]
    println(io, "  Columns: $(length(t.vars) + length(t.attrs))")
    println(io, "  ─────────────────────────────────")
    all_names = vcat([string(":", v.name) for v in t.vars], [string(":", a.name) for a in t.attrs])
    all_types = vcat([string(v.eltype) for v in t.vars], [string(a.eltype) for a in t.attrs])
    name_w = maximum(length, all_names; init=0)
    type_w = maximum(length, all_types; init=0)
    for v in t.vars
        n = rpad(string(":", v.name), name_w)
        ty = rpad(string(v.eltype), type_w)
        rep = (v.inner > 1 || v.outer > 1) ? "  (×$(v.inner * v.outer))" : ""
        tf = _show_transform(v.f)
        println(io, "  $n ::$ty$rep$tf")
    end
    for a in t.attrs
        n = rpad(string(":", a.name), name_w)
        ty = rpad(string(a.eltype), type_w)
        println(io, "  $n ::$ty  (attr)")
    end
end

# Metadata — delegated to the first partition (its schema is read from there
# too). Partitions share column structure and source metadata, so the first
# partition is representative.
DataAPI.metadatasupport(::Type{<:PartitionedH5Table}) = (read=true, write=false)
function DataAPI.metadatakeys(table::PartitionedH5Table)
    isempty(table.tables) ? () : DataAPI.metadatakeys(table.tables[1])
end
function DataAPI.metadata(table::PartitionedH5Table, key::String; style=false)
    isempty(table.tables) && throw(ArgumentError("PartitionedH5Table has no partitions"))
    DataAPI.metadata(table.tables[1], key; style)
end
DataAPI.colmetadatasupport(::Type{<:PartitionedH5Table}) = (read=true, write=false)
function DataAPI.colmetadatakeys(table::PartitionedH5Table)
    isempty(table.tables) ? () : DataAPI.colmetadatakeys(table.tables[1])
end
function DataAPI.colmetadata(table::PartitionedH5Table, col; style=false)
    isempty(table.tables) && throw(ArgumentError("PartitionedH5Table has no partitions"))
    DataAPI.colmetadata(table.tables[1], col; style)
end
function DataAPI.colmetadata(table::PartitionedH5Table, col, key::String; style=false)
    isempty(table.tables) && throw(ArgumentError("PartitionedH5Table has no partitions"))
    DataAPI.colmetadata(table.tables[1], col, key; style)
end

DataAPI.nrow(x::H5Table) = x.nrow
DataAPI.ncol(x::H5Table) = length(x.vars) + length(x.attrs)

# Metadata
DataAPI.metadatasupport(::Type{<:H5Table}) = (read=true, write=false)
function DataAPI.metadatakeys(table::H5Table)
    file_keys = collect(keys(attrs(h5handle(table.f))))
    src_keys = collect(keys(source_metadata(table.f)))
    return unique!(vcat(src_keys, file_keys))
end
function DataAPI.metadata(table::H5Table, key::String; style=false)
    smeta = source_metadata(table.f)
    val = haskey(smeta, key) ? smeta[key] : read_attribute(h5handle(table.f), key)
    style ? (val, :note) : val
end

# Column metadata
DataAPI.colmetadatasupport(::Type{<:H5Table}) = (read=true, write=false)
function DataAPI.colmetadatakeys(table::H5Table)
    file = h5handle(table.f)
    Dict(var.name => filter(Base.Fix1(!in, ["DIMENSION_LIST", "REFERENCE_LIST"]), keys(attrs(file[var.path]))) for var in table.vars)
end
function DataAPI.colmetadata(table::H5Table, col::Symbol; style=false)
    vari = findfirst(v -> v.name == col, table.vars)
    isnothing(vari) && throw(ArgumentError("Column $col not found"))
    DataAPI.colmetadata(table, vari; style)
end
function DataAPI.colmetadata(table::H5Table, col::Symbol, key::String; style=false)
    vari = findfirst(v -> v.name == col, table.vars)
    isnothing(vari) && throw(ArgumentError("Column $col not found"))
    DataAPI.colmetadata(table, vari, key; style)
end
function DataAPI.colmetadata(table::H5Table, col::Int; style=false)
    var = table.vars[col]
    file = h5handle(table.f)
    if style
        Dict(key => (value, :note) for (key,value) in attrs(file[var.path]))
    else
        attrs(file[var.path])
    end
end
function DataAPI.colmetadata(table::H5Table, col::Int, key::String; style=false)
    var = table.vars[col]
    file = h5handle(table.f)
    if style
        (read_attribute(file[var.path], key), :note)
    else
        read_attribute(file[var.path], key)
    end
end
