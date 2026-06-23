
# Metadata — delegated to the first partition (its schema is read from there
# too). Partitions share column structure and source metadata, so the first
# partition is representative.
DataAPI.metadatasupport(::Type{<:PartitionedH5Table}) = (read = true, write = false)
function DataAPI.metadatakeys(table::PartitionedH5Table)
    isempty(table.tables) ? () : DataAPI.metadatakeys(table.tables[1])
end
function DataAPI.metadata(table::PartitionedH5Table, key::String; style = false)
    isempty(table.tables) && throw(ArgumentError("PartitionedH5Table has no partitions"))
    DataAPI.metadata(table.tables[1], key; style)
end
DataAPI.colmetadatasupport(::Type{<:PartitionedH5Table}) = (read = true, write = false)
function DataAPI.colmetadatakeys(table::PartitionedH5Table)
    isempty(table.tables) ? () : DataAPI.colmetadatakeys(table.tables[1])
end
function DataAPI.colmetadata(table::PartitionedH5Table, col; style = false)
    isempty(table.tables) && throw(ArgumentError("PartitionedH5Table has no partitions"))
    DataAPI.colmetadata(table.tables[1], col; style)
end
function DataAPI.colmetadata(table::PartitionedH5Table, col, key::String; style = false)
    isempty(table.tables) && throw(ArgumentError("PartitionedH5Table has no partitions"))
    DataAPI.colmetadata(table.tables[1], col, key; style)
end

DataAPI.nrow(x::H5Table) = x.nrow
DataAPI.ncol(x::H5Table) = length(x.vars) + length(x.attrs)

# Metadata
DataAPI.metadatasupport(::Type{<:H5Table}) = (read = true, write = false)
function DataAPI.metadatakeys(table::H5Table)
    file_keys = collect(keys(attrs(h5handle(table.f))))
    src_keys = collect(keys(source_metadata(table.f)))
    return unique!(vcat(src_keys, file_keys))
end
function DataAPI.metadata(table::H5Table, key::String; style = false)
    smeta = source_metadata(table.f)
    val = haskey(smeta, key) ? smeta[key] : read_attribute(h5handle(table.f), key)
    style ? (val, :note) : val
end

# Column metadata
DataAPI.colmetadatasupport(::Type{<:H5Table}) = (read = true, write = false)
_colmetadata_keys(obj) = filter(k -> !(k in _INTERNAL_ATTRS), keys(attrs(obj)))
function DataAPI.colmetadatakeys(table::H5Table)
    file = h5handle(table.f)
    Dict(var.name => _colmetadata_keys(file[var.path]) for var in table.vars)
end
function DataAPI.colmetadata(table::H5Table, col::Symbol; style = false)
    vari = findfirst(v -> v.name == col, table.vars)
    isnothing(vari) && throw(ArgumentError("Column $col not found"))
    DataAPI.colmetadata(table, vari; style)
end
function DataAPI.colmetadata(table::H5Table, col::Symbol, key::String; style = false)
    vari = findfirst(v -> v.name == col, table.vars)
    isnothing(vari) && throw(ArgumentError("Column $col not found"))
    DataAPI.colmetadata(table, vari, key; style)
end
function DataAPI.colmetadata(table::H5Table, col::Int; style = false)
    var = table.vars[col]
    obj = h5handle(table.f)[var.path]
    if style
        Dict(key => (read_attribute(obj, key), :note) for key in _colmetadata_keys(obj))
    else
        Dict(key => read_attribute(obj, key) for key in _colmetadata_keys(obj))
    end
end
function DataAPI.colmetadata(table::H5Table, col::Int, key::String; style = false)
    var = table.vars[col]
    file = h5handle(table.f)
    if style
        (read_attribute(file[var.path], key), :note)
    else
        read_attribute(file[var.path], key)
    end
end
