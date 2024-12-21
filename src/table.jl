abstract type AbstractTable end
struct Table{K,V,G} <: AbstractTable
    table::NamedTuple{K,V}
    granule::G
    function Table(table::NamedTuple{K,V}, g::G) where {K,V,G}
        new{K,typeof(values(table)),G}(table, g)
    end
end
_table(t::Table) = getfield(t, :table)
_granule(t::AbstractTable) = getfield(t, :granule)
Base.size(table::Table) = size(_table(table))
Base.getindex(t::Table, i) = _table(t)[i]
Base.show(io::IO, t::Table) = _show(io, t)
Base.show(io::IO, ::MIME"text/plain", t::Table) = _show(io, t)
Base.haskey(table::Table, x) = haskey(_table(table), x)
Base.keys(table::Table) = keys(_table(table))
Base.values(table::Table) = values(_table(table))
Base.length(table::Table) = length(_table(table))
Base.iterate(table::Table, args...) = iterate(_table(table), args...)
Base.merge(table::Table, others...) = Table(merge(_table(table), others...))
Base.parent(table::Table) = _table(table)

function Base.getproperty(table::Table, key::Symbol)
    getproperty(_table(table), key)
end

function _show(io, t::Table)
    print(io, "Table of $(_granule(t))")
end

struct PartitionedTable{N,K,V,G} <: AbstractTable
    tables::NTuple{N,NamedTuple{K,V}}
    granule::G
end
PartitionedTable(t::NamedTuple) = PartitionedTable((t,))
Base.size(t::PartitionedTable) = (length(t.tables),)
Base.length(t::PartitionedTable{N}) where {N} = N
Base.getindex(t::PartitionedTable, i) = t.tables[i]
Base.lastindex(t::PartitionedTable{N}) where {N} = N
Base.show(io::IO, t::PartitionedTable) = _show(io, t)
Base.show(io::IO, ::MIME"text/plain", t::PartitionedTable) = _show(io, t)
Base.iterate(table::PartitionedTable, args...) = iterate(table.tables, args...)
Base.merge(table::PartitionedTable, others...) = PartitionedTable(merge.(table.tables, Ref(others...)))
Base.parent(table::PartitionedTable) = collect(table.tables)

function _show(io, t::PartitionedTable)
    print(io, "Table with $(length(t.tables)) partitions of $(_granule(t))")
end

function add_info(table::PartitionedTable)
    it = info(table.granule)
    nts = map(table.tables) do t
        nt = NamedTuple(zip(keys(it), Fill.(values(it), length(first(t)))))
        merge(t, nt)
    end
    return PartitionedTable(nts, table.granule)
end

function add_id(table::PartitionedTable)
    nts = map(table.tables) do t
        nt = (; id = Fill(id(table.granule), length(first(t))))
        merge(t, nt)
    end
    return PartitionedTable(nts, table.granule)
end

function add_id(table::Table)
    g = _granule(table)
    t = _table(table)
    nt = (; id = Fill(id(g), length(first(t))))
    nts = merge(t, nt)
    return Table(nts, g)
end

function add_info(table::Table)
    g = _granule(table)
    it = info(g)
    t = _table(table)
    nt = NamedTuple(zip(keys(it), Fill.(values(it), length(first(t)))))
    nts = merge(t, nt)
    return Table(nts, g)
end

_info(g::Granule) = merge((; id = id(g)), info(g))

DataAPI.metadatasupport(::Type{<:AbstractTable}) = (read = true, write = false)
DataAPI.metadatakeys(t::AbstractTable) = map(String, keys(pairs(_info(_granule(t)))))
function DataAPI.metadata(t::AbstractTable, k; style::Bool = false)
    if style
        getfield(_info(_granule(t)), Symbol(k)), :default
    else
        getfield(_info(_granule(t)), Symbol(k))
    end
end

Tables.istable(::Type{<:SpaceLiDAR.Granule}) = true
Tables.columnaccess(::Type{<:SpaceLiDAR.Granule}) = true
Tables.partitions(g::SpaceLiDAR.Granule) = points(g)
Tables.columns(g::SpaceLiDAR.Granule) = Tables.CopiedColumns(joinpartitions(g))

Tables.istable(::Type{<:SpaceLiDAR.PartitionedTable}) = true
Tables.columnaccess(::Type{<:SpaceLiDAR.PartitionedTable}) = true
Tables.partitions(g::SpaceLiDAR.PartitionedTable) = getfield(g, :tables)
Tables.columns(g::SpaceLiDAR.PartitionedTable) = Tables.CopiedColumns(joinpartitions(g))

# ICESat has no beams, so no need for partitions
Tables.istable(::Type{<:SpaceLiDAR.ICESat_Granule}) = true
Tables.columnaccess(::Type{<:SpaceLiDAR.ICESat_Granule}) = true
Tables.columns(g::SpaceLiDAR.ICESat_Granule) = getfield(points(g), :table)

Tables.istable(::Type{<:SpaceLiDAR.Table}) = true
Tables.columnaccess(::Type{<:SpaceLiDAR.Table}) = true
Tables.columns(g::SpaceLiDAR.Table) = getfield(g, :table)


function materialize!(df::DataFrame)
    for (name, col) in zip(names(df), eachcol(df))
        if col isa CategoricalArray || eltype(col) <: CategoricalValue
            df[!, name] = String.(col)
        elseif col isa Fill
            df[!, name] = Vector(col)
        end
    end
    df
end
