Tables.istable(::Type{<:SpaceLiDAR.Granule}) = true
Tables.columnaccess(::Type{<:SpaceLiDAR.Granule}) = true
Tables.partitions(g::SpaceLiDAR.Granule) = points(g)
Tables.columns(g::SpaceLiDAR.Granule) = Tables.CopiedColumns(joinpartitions(g))

# ICESat has no beams, so no need for partitions
Tables.istable(::Type{<:SpaceLiDAR.ICESat_Granule}) = true
Tables.columnaccess(::Type{<:SpaceLiDAR.ICESat_Granule}) = true
Tables.columns(g::SpaceLiDAR.ICESat_Granule) = points(g)
