# ─── Operations: declarative filters and column transforms ───────────────────
#
# An `Operation` declares which columns it needs (`_inputs`) and is either a
# `Filter` (masks rows) or a `Transform` (overwrites columns). The kind is
# encoded in the type hierarchy, not a runtime flag:
#
#   abstract type Filter    <: Operation end   # implements `_mask(op, cols)`
#   abstract type Transform <: Operation end   # implements `_run!(op, cols)`
#
# Why this exists: the generic `H5Table` reader is decoupled from product
# semantics, so post-processing used to probe columns at runtime
# (`hasproperty`) and silently depend on the user having selected the right
# variables. Operations turn that implicit contract explicit:
#
#   * `_inputs(op, granule)` lists required columns as `Variable` specs — used to
#     *auto-pull* missing columns from a lazy `H5Table` (via `resolve_variable`
#     on its source) so the user can't under-select. Auto-pulled columns are
#     kept in the result.
#   * `_inputs` is *granule-dispatched*: generic operations specialise on the
#     abstract `Granule`, product-bound ones on their concrete granule (e.g.
#     `TopexToWGS84` only on `ICESat_Granule`). Inapplicable `(op, granule)`
#     pairs hit the default method, which throws an applicability error.
#
# Operation definitions live next to the code they relate to: generic ones with
# the geoid kernels (`geoid.jl`) or here (`InExtent`); product-bound ones in the
# product files (`ICESat/ICESat.jl`, etc.). This file only owns the abstraction,
# the verbs and the auto-pull machinery; products are included last so this is
# all defined before any product subtypes `Operation`.
#
# Only the operation *types* are public; the interface functions
# (`_inputs`/`_mask`/`_run!`) are package-internal.
#
# Verbs (extending Base, mirroring the mutating/non-mutating split):
#   filter(op, t) / filter!(op, t)   — `Filter` ops → subset rows
#   map(op, t)    / map!(op, t)      — `Transform` ops → overwrite columns
#   t |> op1 |> op2 |> collect       — lazy pipeline, materialized once at sink
# Using the wrong verb for an op's kind is a `MethodError`.
#
# The non-mutating verbs accept lazy `H5Table`/`PartitionedH5Table` (auto-pull +
# materialize) or any materialized table. The mutating verbs require an
# already-materialized, mutable table.

abstract type Operation end

"""
    abstract type Filter <: Operation

An [`Operation`](@ref) that masks rows. Used via [`filter`](@ref)/[`filter!`].
Implements the internal `_mask(op, cols)::BitVector`.
"""
abstract type Filter <: Operation end

"""
    abstract type Transform <: Operation

An [`Operation`](@ref) that overwrites columns. Used via [`map`](@ref)/[`map!`].
Implements the internal `_run!(op, cols)`.
"""
abstract type Transform <: Operation end

"""
    table(g) |> op1 |> op2 |> collect
    table(g) |> op1 |> op2 |> DataFrame

Lazy operation chain. Piped operations on an `H5Table`/`PartitionedH5Table`
record the requested filters/transforms and defer reading until a materializing
sink such as `collect` or `DataFrame`. All required columns are auto-pulled
before materialization, so later operations can still use granule context.
"""
struct OperationPipeline{S,O<:Tuple}
    source::S
    ops::O
end

"""
    _inputs(op::Operation, granule) -> Vector{Variable}

Columns `op` reads, as full [`Variable`](@ref) specs. Granule-dispatched: the
default method throws, so an operation only applies to granules it has a method
for. Generic operations specialise on `Granule`, product-bound ones on their
concrete granule type. Pass `nothing` for a sourceless table (the op then
returns name-only specs used purely for validation).
"""
_inputs(op::Operation, granule) = throw(ArgumentError(
    "$(typeof(op)) is not applicable to " *
    (granule === nothing ? "a sourceless table" : string(typeof(granule))),
))

# ─── input-spec helpers (shared by generic operations) ────────────────────────

"""Look up `name` in the granule's `default_variables` template, returning its
full [`Variable`](@ref) spec (track-less path)."""
function _var(g::Granule, name::Symbol)
    dv = default_variables(g)
    i = findfirst(v -> v.name === name, dv)
    isnothing(i) && error("$(typeof(g)) has no default variable :$name")
    return dv[i]
end

"""A name-only [`Variable`](@ref) (empty path), used for validation of
sourceless tables where paths are irrelevant."""
_namevar(name::Symbol) = Variable(name, "", Any)

"""The longitude/latitude/height triple for `g` (or name-only specs when there
is no granule). Generic geo operations build their `inputs` from this so paths
stay single-sourced in `default_variables` and track handling stays correct."""
_point_variables(g::Granule) = [_var(g, :longitude), _var(g, :latitude), _var(g, :height)]
_point_variables(::Nothing) = [_namevar(:longitude), _namevar(:latitude), _namevar(:height)]

# ─── table introspection helpers ─────────────────────────────────────────────

_opgranule(t::H5Tables.H5Table) = granuleof(t)
_opgranule(t::H5Tables.PartitionedH5Table) = granuleof(t)
_opgranule(t::AbstractTable) = _granule(t)
_opgranule(::Any) = nothing

# Tables the operation verbs accept. Constraining the second argument (rather
# than using `::Any`) keeps `filter`/`filter!` from being ambiguous with Base's
# `filter(f, ::AbstractArray/AbstractDict/...)` methods. `NamedTuple` is
# deliberately excluded: it would collide with `Compat`'s `filter(f, ::NamedTuple)`
# (wrap a column-table in a `Table`/`DataFrame` to use operations on it).
const OpTable = Union{
    H5Tables.H5Table,
    H5Tables.PartitionedH5Table,
    AbstractTable,
    DataFrame,
}
const LazyOpTable = Union{H5Tables.H5Table,H5Tables.PartitionedH5Table}
const MaterializedOpTable = Union{AbstractTable,DataFrame}

# Mutable column containers an operation works over. A `PartitionedTable`
# exposes one container per partition (so in-place column mutation persists and
# row filtering preserves partition structure); everything else is a single
# container whose columns are mutable vectors.
_containers(t::Table) = (_table(t),)
_containers(t::PartitionedTable) = t.tables
_containers(t::DataFrame) = (t,)

_colnames(t) = Tables.columnnames(Tables.columns(t))

# Names required by `op` for `granule`, used to validate materialized tables.
_input_names(op::Operation, granule) = Symbol[v.name for v in _inputs(op, granule)]

function _missing_col_msg(name::Symbol, granule)
    if granule === nothing
        "Operation needs column :$name, which is not present and cannot be " *
        "auto-resolved (the table carries no granule). Re-create the table " *
        "including :$name (e.g. select it in `explore`)."
    else
        "Operation needs column :$name, which is not present and is unknown to " *
        "$(typeof(granule)). Include it via `table(g)`/`explore(g)` " *
        "(e.g. `table(g; variables=[…, Variable(:$name, …)])`)."
    end
end

function _validate(t, need)
    have = Set(_colnames(t))
    for name in need
        name in have || throw(ArgumentError(_missing_col_msg(name, _opgranule(t))))
    end
    return t
end

# ─── auto-pull: augment a lazy H5Table with missing input columns ─────────────

function _augment(t::H5Tables.H5Table, need::Vector{Variable})
    have = Set(Tables.columnnames(t))
    src = getfield(t, :f)
    newvars = copy(t.vars)
    for v in need
        v.name in have && continue
        any(a -> a.name == v.name, t.attrs) && continue
        rv = H5Tables.resolve_variable(src, v)
        rv === nothing && throw(ArgumentError(_missing_col_msg(v.name, _opgranule(t))))
        push!(newvars, rv)
    end
    H5Tables.H5Table(f = src, vars = newvars, attrs = t.attrs, nrow = t.nrow)
end

function _augment(t::H5Tables.PartitionedH5Table, need::Vector{Variable})
    H5Tables.PartitionedH5Table([_augment(p, need) for p in t.tables])
end

# Materialize `t` with the columns `need` available.
_materialize_for(t::H5Tables.H5Table, need::Vector{Variable}) = collect(_augment(t, need))
_materialize_for(t::H5Tables.PartitionedH5Table, need::Vector{Variable}) =
    collect(_augment(t, need))
_materialize_for(t::AbstractTable, need::Vector{Variable}) =
    (_validate(t, (v.name for v in need)); _copytable(t))
_materialize_for(t, need::Vector{Variable}) =
    (_validate(t, (v.name for v in need)); _copytable(t))

_copytable(t::Table) = Table(map(copy, _table(t)), _granule(t))
_copytable(t::PartitionedTable) = PartitionedTable(map(nt -> map(copy, nt), t.tables), _granule(t))
_copytable(t::DataFrame) = copy(t)

# ─── public verbs ─────────────────────────────────────────────────────────────

(op::Operation)(t::LazyOpTable) = OperationPipeline(t, (op,))
(op::Operation)(p::OperationPipeline) = OperationPipeline(p.source, (p.ops..., op))
(op::Filter)(t::MaterializedOpTable) = filter(op, t)
(op::Transform)(t::MaterializedOpTable) = map(op, t)

Tables.istable(::Type{<:OperationPipeline}) = true
Tables.columnaccess(::Type{<:OperationPipeline}) = true
Tables.columns(p::OperationPipeline) = Tables.columns(collect(p))
DataAPI.metadatasupport(::Type{<:OperationPipeline}) = (read = true, write = false)
DataAPI.metadatakeys(p::OperationPipeline) = DataAPI.metadatakeys(p.source)
DataAPI.metadata(p::OperationPipeline, key::String; style = false) =
    DataAPI.metadata(p.source, key; style)
DataAPI.colmetadatasupport(::Type{<:OperationPipeline}) = (read = true, write = false)
_metadata_source(p::OperationPipeline) = _augment(p.source, _inputs(p.ops, _opgranule(p.source)))
DataAPI.colmetadatakeys(p::OperationPipeline) = DataAPI.colmetadatakeys(_metadata_source(p))
DataAPI.colmetadata(p::OperationPipeline, col; style = false) =
    DataAPI.colmetadata(_metadata_source(p), col; style)
DataAPI.colmetadata(p::OperationPipeline, col, key::String; style = false) =
    DataAPI.colmetadata(_metadata_source(p), col, key; style)

function _inputs(ops::Tuple, granule)
    need = Variable[]
    seen = Set{Symbol}()
    for op in ops, v in _inputs(op, granule)
        v.name in seen && continue
        push!(need, v)
        push!(seen, v.name)
    end
    return need
end

_apply(op::Filter, t) = _filter_rows(op, t)
_apply(op::Transform, t) = (_transform!(op, t); t)

function Base.collect(p::OperationPipeline)
    t = _materialize_for(p.source, _inputs(p.ops, _opgranule(p.source)))
    for op in p.ops
        t = _apply(op, t)
    end
    return t
end

"""
    map(op::Transform, t)

Apply a transform `op` to table `t`, returning a new table with the transformed
columns overwritten. For a lazy `H5Table`/`PartitionedH5Table`, missing input
columns are auto-pulled from the granule source and kept in the result. See
[`map!`](@ref) for the mutating version.
"""
function Base.map(op::Transform, t::OpTable)
    mt = _materialize_for(t, _inputs(op, _opgranule(t)))
    _transform!(op, mt)
    return mt
end

"""
    map!(op::Transform, t)

In-place version of [`map`](@ref). Requires `t` to be a materialized, mutable
table (e.g. `DataFrame`, `Table`, `PartitionedTable`, `NamedTuple` of vectors).
Lazy `H5Table`/`PartitionedH5Table` inputs are read-only; use `map(op, t)` or
materialize to a mutable sink such as `DataFrame(t)` first.
"""
function Base.map!(op::Transform, t::OpTable)
    _validate(t, _input_names(op, _opgranule(t)))
    _transform!(op, t)
    return t
end

"""
    filter(op::Filter, t)

Filter rows of `t` with filter `op`, returning a new table with only the rows
where `op`'s predicate holds. For a lazy `H5Table`/`PartitionedH5Table`, missing
input columns are auto-pulled and kept. See [`filter!`](@ref).
"""
function Base.filter(op::Filter, t::OpTable)
    mt = _materialize_for(t, _inputs(op, _opgranule(t)))
    return _filter_rows(op, mt)
end

"""
    filter!(op::Filter, t)

In-place version of [`filter`](@ref). Requires `t` to be a materialized, mutable
table. Lazy `H5Table`/`PartitionedH5Table` inputs are read-only; use
`filter(op, t)` or materialize to a mutable sink such as `DataFrame(t)` first.
"""
function Base.filter!(op::Filter, t::OpTable)
    _validate(t, _input_names(op, _opgranule(t)))
    for c in _containers(t)
        m = _mask(op, c)
        drop = findall(!, m)
        for name in _colnames(c)
            deleteat!(Tables.getcolumn(c, name), drop)
        end
    end
    return t
end

# Non-mutating row filter that preserves container structure.
function _filter_rows(op::Filter, t::Table)
    nt = _table(t)
    m = _mask(op, nt)
    Table(map(c -> c[m], nt), _granule(t))
end
function _filter_rows(op::Filter, t::PartitionedTable)
    parts = map(t.tables) do nt
        m = _mask(op, nt)
        map(c -> c[m], nt)
    end
    PartitionedTable(parts, _granule(t))
end
function _filter_rows(op::Filter, t::DataFrame)
    m = _mask(op, t)
    t[m, :]
end

# Apply a transform to every mutable container of `t`.
_transform!(op::Transform, t) = (foreach(c -> _run!(op, c), _containers(t)); t)

# ─── generic operations ───────────────────────────────────────────────────────
# Product-bound operations (TopexToWGS84, SaturationCorrect, ICESatQuality) live
# in the product files; geoid-themed generic ops (ToEGM2008) live in geoid.jl.

"""
    InExtent(extent::Extent)
    InExtent(; X=(min,max), Y=(min,max))

Filter: keep rows whose `:longitude`/`:latitude` fall within `extent` (an
`Extents.Extent` with `X` and `Y` bounds). Generic — applies to any granule.
Generalizes [`in_bbox`](@ref).
"""
struct InExtent <: Filter
    extent::Extent
end
InExtent(; kwargs...) = InExtent(Extent(; kwargs...))
_inputs(::InExtent, granule) = _point_variables(granule)[1:2]
function _mask(op::InExtent, cols)
    x = Tables.getcolumn(cols, :longitude)
    y = Tables.getcolumn(cols, :latitude)
    xmin, xmax = op.extent.X
    ymin, ymax = op.extent.Y
    n = length(x)
    m = BitVector(undef, n)
    @inbounds for i in 1:n
        xi, yi = x[i], y[i]
        m[i] = !ismissing(xi) && !ismissing(yi) &&
               xmin <= xi <= xmax && ymin <= yi <= ymax
    end
    return m
end
