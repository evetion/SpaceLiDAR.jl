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
#   * `inputs(op, granule)` lists required columns — used to *auto-pull* missing
#     columns from a lazy `H5Table` (via `resolve_variable` on its source) so
#     the user can't under-select. Auto-pulled columns that the op only needed
#     transiently (e.g. lat/lon for a bbox filter) are dropped from the result.
#   * `resolve(op, granule)` binds product-specific details (e.g. which attitude
#     column an ICESat quality filter uses for GLAH06 vs GLAH14).
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
    inputs(op::Operation, granule=nothing) -> Vector{Symbol}

Columns `op` reads. May depend on the `granule` for product-specific column
names (e.g. the attitude flag differs between GLAH06 and GLAH14).
"""
inputs(::Operation, granule = nothing) = Symbol[]

"""
    outputs(op::Operation) -> Vector{Symbol}

Columns `op` writes. Empty marks `op` as a *filter* (row mask); non-empty marks
it a *transform* (overwrites the listed columns).
"""
outputs(::Operation) = Symbol[]

"""
    resolve(op::Operation, granule) -> Operation

Bind `op` to a concrete `granule`, resolving product-specific details. Returns
a (possibly new) fully-specified operation. Defaults to `op` unchanged.
"""
resolve(op::Operation, granule) = op

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

function _augment(t::H5Tables.H5Table, need)
    have = Set(Tables.columnnames(t))
    src = getfield(t, :f)
    newvars = copy(t.vars)
    transient = Symbol[]
    for name in need
        name in have && continue
        any(a -> a.name == name, t.attrs) && continue
        v = H5Tables.resolve_variable(src, name)
        v === nothing && error(_missing_col_msg(name, _opgranule(t)))
        push!(newvars, v)
        push!(transient, name)
    end
    H5Tables.H5Table(f = src, vars = newvars, attrs = t.attrs, nrow = t.nrow), transient
end

function _augment(t::H5Tables.PartitionedH5Table, need)
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
function _materialize_for(t::H5Tables.H5Table, need)
    aug, tr = _augment(t, need)
    return collect(aug), tr
end
function _materialize_for(t::H5Tables.PartitionedH5Table, need)
    aug, tr = _augment(t, need)
    return collect(aug), tr
end
_materialize_for(t::AbstractTable, need) = (_validate(t, need); (_copytable(t), Symbol[]))
_materialize_for(t, need) = (_validate(t, need); (_copytable(t), Symbol[]))

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
    rop = resolve(op, g)
    mt, transient = _materialize_for(t, inputs(rop, g))
    _transform!(rop, mt)
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
    rop = resolve(op, g)
    _validate(t, inputs(rop, g))
    _transform!(rop, t)
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
    rop = resolve(op, g)
    mt, transient = _materialize_for(t, inputs(rop, g))
    out = _filter_rows(rop, mt)
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
    rop = resolve(op, g)
    _validate(t, inputs(rop, g))
    for c in _containers(t)
        m = mask(rop, c)
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

# ─── concrete operations ──────────────────────────────────────────────────────

"""
    ToEGM2008()

Transform: convert ellipsoidal `:height` to EGM2008 geoid height (using
`:longitude`, `:latitude`). Equivalent to [`to_egm2008`](@ref).
"""
struct ToEGM2008 <: Operation end
inputs(::ToEGM2008, granule = nothing) = Symbol[:longitude, :latitude, :height]
outputs(::ToEGM2008) = Symbol[:height]
function _run!(::ToEGM2008, cols)
    Proj.enable_network!()
    trans = Proj.Transformation("EPSG:4979", "EPSG:3855")
    to_egm2008!(trans,
        Tables.getcolumn(cols, :latitude),
        Tables.getcolumn(cols, :longitude),
        Tables.getcolumn(cols, :height))
end

"""
    TopexToWGS84()

Transform: convert ICESat (GLAH06/GLAH14) TOPEX/Poseidon ellipsoid `:height`
(and `:height_reference` if present) to WGS84. Equivalent to
[`topex_to_wgs84`](@ref).
"""
struct TopexToWGS84 <: Operation end
inputs(::TopexToWGS84, granule = nothing) = Symbol[:longitude, :latitude, :height]
outputs(::TopexToWGS84) = Symbol[:height]
function _run!(::TopexToWGS84, cols)
    pipe = topex_to_wgs84_ellipsoid()
    lon = Tables.getcolumn(cols, :longitude)
    lat = Tables.getcolumn(cols, :latitude)
    if :height_reference in _colnames(cols)
        topex_to_wgs84!(pipe, lon, lat, Tables.getcolumn(cols, :height_reference))
    end
    topex_to_wgs84!(pipe, lon, lat, Tables.getcolumn(cols, :height))
end

"""
    SaturationCorrect()

Transform: add `:saturation_correction` to `:height` (ICESat). Equivalent to
[`icesat_saturation_correct`](@ref).
"""
struct SaturationCorrect <: Operation end
inputs(::SaturationCorrect, granule = nothing) = Symbol[:height, :saturation_correction]
outputs(::SaturationCorrect) = Symbol[:height]
_run!(::SaturationCorrect, cols) = icesat_saturation_correct!(
    Tables.getcolumn(cols, :height),
    Tables.getcolumn(cols, :saturation_correction),
)

"""
    ICESatQuality()

Filter: keep only high-quality ICESat (GLAH06/GLAH14) returns following Smith
et al. (2020). Resolves the product-specific attitude column automatically
(`:sigma_att_flg` for GLAH06, `:attitude` for GLAH14). See [`icesat_quality`](@ref).
"""
struct ICESatQuality <: Operation
    attitude::Union{Symbol,Nothing}
end
ICESatQuality() = ICESatQuality(nothing)

_attitude_col(g) = (g !== nothing && sproduct(g) === :GLAH14) ? :attitude : :sigma_att_flg

function resolve(op::ICESatQuality, granule)
    op.attitude === nothing || return op
    granule === nothing && return op
    ICESatQuality(_attitude_col(granule))
end

function inputs(op::ICESatQuality, granule = nothing)
    att = op.attitude !== nothing ? op.attitude : _attitude_col(granule)
    Symbol[:elev_use_flg, att, :i_numPk, :saturation_correction]
end

function mask(op::ICESatQuality, cols)
    names = _colnames(cols)
    att_col = op.attitude !== nothing ? op.attitude :
              :attitude in names ? :attitude :
              :sigma_att_flg in names ? :sigma_att_flg : nothing
    elev = Tables.getcolumn(cols, :elev_use_flg)
    att = att_col === nothing ? nothing : Tables.getcolumn(cols, att_col)
    npk = :i_numPk in names ? Tables.getcolumn(cols, :i_numPk) : nothing
    sc = :saturation_correction in names ? Tables.getcolumn(cols, :saturation_correction) : nothing
    return icesat_quality(elev, att, npk, sc)
end

"""
    InExtent(extent::Extent)
    InExtent(; X=(min,max), Y=(min,max))

Filter: keep rows whose `:longitude`/`:latitude` fall within `extent` (an
`Extents.Extent` with `X` and `Y` bounds). Generalizes [`in_bbox`](@ref).
"""
struct InExtent <: Operation
    extent::Extent
end
InExtent(; kwargs...) = InExtent(Extent(; kwargs...))
inputs(::InExtent, granule = nothing) = Symbol[:longitude, :latitude]
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
