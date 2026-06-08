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

# ─── Per-granule native CRS ────────────────────────────────────────────────────
# These describe the CRS as the data sit *in the file*, so consumers can
# project from there to whatever target they want. Heights are 3D ellipsoidal
# heights — no vertical datum (geoid) is involved on the source side, so all
# three CRSes are 3D longlat.
#
# The fallback `GeoInterface.crs(::Granule) = EPSG(4326)` is kept for
# defensive purposes (unknown future granule types) but every concrete
# granule type below should override it.

# ICESat-2 (ATL03/06/08/12) is referenced to ITRF2014 — see ATBDs (e.g.
# ATL03 §3.3 "Geolocation"). ITRF2014 3D = EPSG:7912.
GeoInterface.crs(::ICESat2_Granule) = GeoFormatTypes.EPSG(7912)

# GEDI L2A is also referenced to ITRF2014 (the host ISS ephemeris is in
# ITRF, and the products inherit it). ITRF2014 3D = EPSG:7912.
GeoInterface.crs(::GEDI_Granule) = GeoFormatTypes.EPSG(7912)

# ICESat (GLAH06/GLAH14) uses the TOPEX/Poseidon ellipsoid (a = 6378136.3 m,
# 1/f = 298.257). There is no EPSG code for it — the closest formal
# representation is a PROJ string, which round-trips through `Proj.CRS` and
# is what `topex_to_wgs84_ellipsoid()` is built from.
const _ICESAT_TOPEX_CRS = GeoFormatTypes.ProjString(
    "+proj=longlat +a=6378136.3 +rf=298.257 +e=0.08181922146 +vunits=m +type=crs",
)
GeoInterface.crs(::ICESat_Granule) = _ICESAT_TOPEX_CRS

# Default fallback — should never trigger for known granule types.
GeoInterface.crs(::Granule) = GeoFormatTypes.EPSG(4326)
