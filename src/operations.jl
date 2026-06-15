# ─── Operations: declarative filters and column transforms ───────────────────
#
# An `Operation` is a value that declares which columns it needs (`inputs`) and
# which it produces (`outputs`), and knows how to either mask rows (a *filter*,
# `outputs` empty) or overwrite columns (a *transform*, `outputs` non-empty).
#
# Why this exists: the generic `H5Table` reader is decoupled from product
# semantics, so post-processing used to probe columns at runtime
# (`hasproperty`) and silently depend on the user having selected the right
# variables. Operations turn that implicit contract explicit:
#
#   * `inputs(op, granule)` lists required columns as `Variable` specs — used to
#     *auto-pull* missing columns from a lazy `H5Table` (via `resolve_variable`
#     on its source) so the user can't under-select. Auto-pulled columns that
#     the op only needed transiently (e.g. lat/lon for a bbox filter) are
#     dropped from the result.
#   * `inputs` is *granule-dispatched*: generic operations specialise on the
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
# Verbs (mirroring the mutating/non-mutating split used elsewhere):
#   filter(op, t) / filter!(op, t)   — row filters → subset rows
#   apply(op, t)  / apply!(op, t)    — column transforms → overwrite columns
#
# The non-mutating verbs accept lazy `H5Table`/`PartitionedH5Table` (auto-pull +
# materialize) or any materialized table. The mutating verbs require an
# already-materialized, mutable table.

abstract type Operation end

"""
    inputs(op::Operation, granule) -> Vector{Variable}

Columns `op` reads, as full [`Variable`](@ref) specs. Granule-dispatched: the
default method throws, so an operation only applies to granules it has a method
for. Generic operations specialise on `Granule`, product-bound ones on their
concrete granule type. Pass `nothing` for a sourceless table (the op then
returns name-only specs used purely for validation).
"""
inputs(op::Operation, granule) = throw(ArgumentError(
    "$(typeof(op)) is not applicable to " *
    (granule === nothing ? "a sourceless table" : string(typeof(granule))),
))

"""
    outputs(op::Operation) -> Vector{Symbol}

Columns `op` writes. Empty marks `op` as a *filter* (row mask); non-empty marks
it a *transform* (overwrites the listed columns).
"""
outputs(::Operation) = Symbol[]

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

# Mutable column containers an operation works over. A `PartitionedTable`
# exposes one container per partition (so in-place column mutation persists and
# row filtering preserves partition structure); everything else is a single
# container whose columns are mutable vectors.
_containers(t::Table) = (_table(t),)
_containers(t::PartitionedTable) = t.tables
_containers(t::DataFrame) = (t,)

_colnames(t) = Tables.columnnames(Tables.columns(t))

# Names required by `op` for `granule`, used to validate materialized tables.
_input_names(op::Operation, granule) = Symbol[v.name for v in inputs(op, granule)]

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
        name in have || error(_missing_col_msg(name, _opgranule(t)))
    end
    return t
end

# ─── auto-pull: augment a lazy H5Table with missing input columns ─────────────

function _augment(t::H5Tables.H5Table, need::Vector{Variable})
    have = Set(Tables.columnnames(t))
    src = getfield(t, :f)
    newvars = copy(t.vars)
    transient = Symbol[]
    for v in need
        v.name in have && continue
        any(a -> a.name == v.name, t.attrs) && continue
        rv = H5Tables.resolve_variable(src, v)
        rv === nothing && error(_missing_col_msg(v.name, _opgranule(t)))
        push!(newvars, rv)
        push!(transient, v.name)
    end
    H5Tables.H5Table(f = src, vars = newvars, attrs = t.attrs, nrow = t.nrow), transient
end

function _augment(t::H5Tables.PartitionedH5Table, need::Vector{Variable})
    augmented = H5Tables.H5Table[]
    transient = Symbol[]
    for p in t.tables
        ap, transient = _augment(p, need)
        push!(augmented, ap)
    end
    H5Tables.PartitionedH5Table(augmented), transient
end

# Materialize `t` with the columns `need` available, returning the materialized
# table and the names of columns that were pulled in only transiently.
function _materialize_for(t::H5Tables.H5Table, need::Vector{Variable})
    aug, tr = _augment(t, need)
    return collect(aug), tr
end
function _materialize_for(t::H5Tables.PartitionedH5Table, need::Vector{Variable})
    aug, tr = _augment(t, need)
    return collect(aug), tr
end
_materialize_for(t::AbstractTable, need::Vector{Variable}) =
    (_validate(t, (v.name for v in need)); (_copytable(t), Symbol[]))
_materialize_for(t, need::Vector{Variable}) =
    (_validate(t, (v.name for v in need)); (_copytable(t), Symbol[]))

_copytable(t::Table) = Table(map(copy, _table(t)), _granule(t))
_copytable(t::PartitionedTable) = PartitionedTable(map(nt -> map(copy, nt), t.tables), _granule(t))
_copytable(t::DataFrame) = copy(t)

# ─── dropping transient columns ───────────────────────────────────────────────

_drop_transient(t, transient) = isempty(transient) ? t : _dropcols(t, transient)
function _dropcols(t::Table, names)
    Table(Base.structdiff(_table(t), NamedTuple{Tuple(names)}), _granule(t))
end
function _dropcols(t::PartitionedTable, names)
    PartitionedTable(map(nt -> Base.structdiff(nt, NamedTuple{Tuple(names)}), t.tables), _granule(t))
end

# ─── public verbs ─────────────────────────────────────────────────────────────

"""
    apply(op::Operation, t)

Apply a transform `op` to table `t`, returning a new table with `outputs(op)`
overwritten. For a lazy `H5Table`/`PartitionedH5Table`, missing input columns
are auto-pulled from the granule source (and dropped again if only needed
transiently). See [`apply!`](@ref) for the mutating version.
"""
function apply(op::Operation, t::OpTable)
    isempty(outputs(op)) &&
        throw(ArgumentError("$(typeof(op)) is a filter; use `filter(op, t)`."))
    g = _opgranule(t)
    mt, transient = _materialize_for(t, inputs(op, g))
    _transform!(op, mt)
    return _drop_transient(mt, transient)
end

"""
    apply!(op::Operation, t)

In-place version of [`apply`](@ref). Requires `t` to be a materialized, mutable
table (e.g. `DataFrame`, `Table`, `PartitionedTable`, `NamedTuple` of vectors).
"""
function apply!(op::Operation, t::OpTable)
    isempty(outputs(op)) &&
        throw(ArgumentError("$(typeof(op)) is a filter; use `filter!(op, t)`."))
    g = _opgranule(t)
    _validate(t, _input_names(op, g))
    _transform!(op, t)
    return t
end

"""
    filter(op::Operation, t)

Filter rows of `t` with filter `op`, returning a new table with only the rows
where `op`'s predicate holds. For a lazy `H5Table`/`PartitionedH5Table`, missing
input columns are auto-pulled and then dropped. See [`filter!`](@ref).
"""
function Base.filter(op::Operation, t::OpTable)
    isempty(outputs(op)) ||
        throw(ArgumentError("$(typeof(op)) is a transform; use `apply(op, t)`."))
    g = _opgranule(t)
    mt, transient = _materialize_for(t, inputs(op, g))
    out = _filter_rows(op, mt)
    return _drop_transient(out, transient)
end

"""
    filter!(op::Operation, t)

In-place version of [`filter`](@ref). Requires `t` to be a materialized, mutable
table.
"""
function Base.filter!(op::Operation, t::OpTable)
    isempty(outputs(op)) ||
        throw(ArgumentError("$(typeof(op)) is a transform; use `apply!(op, t)`."))
    g = _opgranule(t)
    _validate(t, _input_names(op, g))
    for c in _containers(t)
        m = mask(op, c)
        drop = findall(!, m)
        for name in _colnames(c)
            deleteat!(Tables.getcolumn(c, name), drop)
        end
    end
    return t
end

# Non-mutating row filter that preserves container structure.
function _filter_rows(op::Operation, t::Table)
    nt = _table(t)
    m = mask(op, nt)
    Table(map(c -> c[m], nt), _granule(t))
end
function _filter_rows(op::Operation, t::PartitionedTable)
    parts = map(t.tables) do nt
        m = mask(op, nt)
        map(c -> c[m], nt)
    end
    PartitionedTable(parts, _granule(t))
end
function _filter_rows(op::Operation, t::DataFrame)
    m = mask(op, t)
    t[m, :]
end

# Apply a transform to every mutable container of `t`.
_transform!(op::Operation, t) = (foreach(c -> _run!(op, c), _containers(t)); t)

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
struct InExtent <: Operation
    extent::Extent
end
InExtent(; kwargs...) = InExtent(Extent(; kwargs...))
inputs(::InExtent, granule) = _point_variables(granule)[1:2]
function mask(op::InExtent, cols)
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
