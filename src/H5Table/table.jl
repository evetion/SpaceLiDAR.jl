Base.@kwdef struct Variable
    name::Symbol
    path::String
    f::Any=identity
    eltype::Type=Any
    inner::Int=1
    outer::Int=1
end
Variable(name::Symbol, path::String, T::Type, f = identity) =
    Variable(name = name, path = path, eltype = T, f = f)

Base.@kwdef struct Attribute
    name::Symbol
    group::String
    attribute::String
    f::Function=identity
    eltype::DataType=Any
end
Attribute(name::Symbol, attribute::String, f::Function = identity) =
    Attribute(name = name, group = "", attribute = attribute, f = f)

Base.@kwdef struct H5Table{S}
    f::S
    vars::Vector{Variable}
    attrs::Vector{Attribute}
    nrow::Int=0
end

function Base.close(t::H5Table)
    close(h5handle(t.f))
    return nothing
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
    name_w = maximum(length, all_names; init = 0)
    type_w = maximum(length, all_types; init = 0)
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
Sentinel-based nodata mask. Replaces values equal to `sentinel` with `missing`.
"""
struct Nodata{T}
    sentinel::T
end
function (nd::Nodata)(data::AbstractArray)
    T = Union{eltype(data),Missing}
    return T[v == nd.sentinel ? missing : v for v in data]
end

"""
Range-based nodata mask. Replaces values outside `[lo, hi]` with `missing`.
"""
struct NodataRange{T}
    lo::T
    hi::T
end
function (nd::NodataRange)(data::AbstractArray)
    T = Union{eltype(data),Missing}
    return T[nd.lo <= v <= nd.hi ? v : missing for v in data]
end

_as_variable(v::Variable) = v
_as_variable(p::Pair{Symbol,<:AbstractString}) =
    Variable(name = first(p), path = String(last(p)))

function H5Table(
    source;
    vars::AbstractVector,
    attrs::Vector{Pair{Symbol,String}} = Pair{Symbol,String}[],
    include_dimensions::Bool = false,
    include_references::Bool = false,
    nrow::Union{Int,Nothing} = nothing,
)
    file = h5handle(source)
    # 1. Collect all variable specs. Pair syntax is a convenience for
    # untransformed columns; transformed columns are represented by Variable.f.
    # `variable_specs` is the canonical, ordered list of requested columns.
    variable_specs = Variable[_as_variable(v) for v in vars]
    # Tracks HDF5 datasets already selected so auto-included dims/refs are unique.
    included_paths = Set(v.path for v in variable_specs)

    for v in copy(variable_specs)
        path = v.path
        ds = HDF5.open_dataset(file, path)
        if include_references
            include_related_paths!(variable_specs, included_paths, get_reference_paths(ds))
        end
        if include_dimensions
            include_related_paths!(variable_specs, included_paths, get_dimension_paths(ds))
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
    # Transform-aware: each variable's raw axes are filtered through its
    # `Variable.f` via `apply_transform_dims(transform, vdims)` before resolving
    # the global context. For example `SliceRow(row)` does `data[row, :]` on a
    # 2D dataset,
    # collapsing Julia axis 1 (HDF5 fast axis) while keeping axis 2. The dropped
    # axis must not inflate the global row count, but the remaining axis still
    # needs to participate so the resulting 1D vector is correctly aligned with
    # the global axis (and can even define it if no other variable mentions it).
    # All other built-in transforms (identity, ToDateTime, ToBool, InvertBool,
    # ExpandDims, ...) are dim-preserving and fall through unchanged — see
    # `apply_transform_dims` for the per-transform rules.
    if isnothing(nrow)
        # Dimension scale path/name -> size; shared by all variables.
        dim_sizes = Dict{String,Int}()
        # Raw HDF5 dims by path; duplicate selected columns can share metadata.
        dims_cache = Dict{String,Vector{String}}()
        # Post-transform dims by variable index, reused when computing repeats.
        effective_dims = Vector{Vector{String}}(undef, length(variable_specs))
        for (i, v) in pairs(variable_specs)
            # Raw HDF5 axes before considering shape-changing transforms.
            vdims = _resolve_var_dims_cached!(dims_cache, dim_sizes, file, v.path)
            # Effective table axes after transforms such as SliceRow drop axes.
            effective_dims[i] = apply_transform_dims(v.f, vdims)
        end
        # The longest compatible effective dim list defines the flattened row order.
        global_dims = _pick_global_dims(effective_dims)
        nrow = isempty(global_dims) ? 1 : prod(dim_sizes[d] for d in global_dims)
    else
        # Explicit nrow is the schema fast path: callers promise all variables
        # are already flat/aligned, so skip dimension resolution entirely.
        global_dims = String[]
        dim_sizes = Dict{String,Int}()
        effective_dims = fill(String[], length(variable_specs))
    end

    # 3. Build Variable structs using cached dims
    variable_structs = Variable[]
    sizehint!(variable_structs, length(variable_specs))
    # Used when there is no global dim context, or explicit nrow bypassed it.
    trivial_flat = (inner = 1, outer = 1)
    for (i, v) in pairs(variable_specs)
        vdims = effective_dims[i]
        # inner/outer tell Tables.getcolumn how to repeat lower-dimensional cols.
        flat = isempty(global_dims) ? trivial_flat : compute_repeat(global_dims, dim_sizes, vdims)
        push!(variable_structs, make_variable(file, v.name, v.path, flat; transform = v.f))
    end

    attribute_structs = Attribute[]
    for (name, path) in attrs
        group, attribute = rsplit(path, "/", limit = 2)
        obj_id = HDF5.API.h5o_open(file, group, HDF5.API.H5P_DEFAULT)
        attr_id = HDF5.API.h5a_open(obj_id, attribute, HDF5.API.H5P_DEFAULT)
        attr_obj = HDF5.Attribute(attr_id, file)
        attribute = Attribute(name, group, attribute, Base.Fix2(Fill, nrow), eltype(attr_obj))
        close(attr_obj)
        HDF5.API.h5o_close(obj_id)
        push!(attribute_structs, attribute)
    end
    return H5Table(f = source, vars = variable_structs, attrs = attribute_structs, nrow = nrow)
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
        path = replace(v.path, prefix_old => prefix_new; count = 1)
        Variable(name = v.name, path = path, f = v.f, eltype = v.eltype, inner = v.inner, outer = v.outer)
    end
    # Determine nrow from the first variable's dataset length
    nrow = length(h5handle(template.f)[variable_structs[1].path])
    attribute_structs = map(template.attrs) do a
        group = replace(a.group, prefix_old => prefix_new; count = 1)
        Attribute(name = a.name, group = group, attribute = a.attribute, f = Base.Fix2(Fill, nrow), eltype = a.eltype)
    end
    return H5Table(f = template.f, vars = variable_structs, attrs = attribute_structs, nrow = nrow)
end

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
            data = repeat(data, inner = var.inner, outer = var.outer)
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


"""
    _h5read(file, path, T) -> Array{T}

Fast dataset read using low-level HDF5 API with known type.
Returns a Vector for 1D datasets, a Matrix for 2D, etc.
Falls back to `HDF5.read` for non-primitive types (strings, compounds).
"""
function _h5read(file::HDF5.File, path::String, ::Type{T}) where {T}
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
function _h5read_attr(file::HDF5.File, parent_path::String, attr_name::String, ::Type{T}) where {T}
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


# ─── PartitionedH5Table ───────────────────────────────────────────────────────

struct PartitionedH5Table
    tables::Vector{H5Table}
end

function Base.close(ts::PartitionedH5Table)
    foreach(close, ts.tables)
    return nothing
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
    print(
        io,
        "$(length(ts.tables))×H5Table($(basename(HDF5.filename(h5handle(ts.tables[1].f)))), $(DataAPI.ncol(ts.tables[1])) columns, $total rows)",
    )
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
    name_w = maximum(length, all_names; init = 0)
    type_w = maximum(length, all_types; init = 0)
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
