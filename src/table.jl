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
        if col isa CategoricalArray
            df[!, name] = String.(col)
        elseif col isa Fill
            df[!, name] = Vector(col)
        end
    end
    df
end
