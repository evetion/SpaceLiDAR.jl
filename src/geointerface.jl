GeoInterface.isgeometry(::Type{<:Granule}) = true
GeoInterface.geomtrait(::Granule) = MultiPointTrait()
GeoInterface.ncoord(::MultiPointTrait, ::Granule) = 3
GeoInterface.ngeom(::MultiPointTrait, g::Granule) = Tables.rowcount(Tables.columntable(g))
function GeoInterface.getgeom(::MultiPointTrait, g::Granule)
    t = Tables.columntable(g)
    return zip(t.longitude, t.latitude, t.height)
end
function GeoInterface.getgeom(::MultiPointTrait, g::Granule, i)
    t = Tables.columntable(g)
    return (t.longitude[i], t.latitude[i], t.height[i])
end

GeoInterface.extent(g::Granule) = convert(Extent, bounds(g))
GeoInterface.crs(::Granule) = GeoFormatTypes.EPSG(4326)
