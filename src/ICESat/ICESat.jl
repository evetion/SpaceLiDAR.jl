using Dates

const j2000_offset = datetime2unix(DateTime(2000, 1, 1, 12, 0, 0))
const icesat_inclination = 86.0  # actually 94, so this is 180. - 94.
const icesat_fill = 1.7976931348623157E308

"""
    ICESat_Granule{product} <: Granule

A granule of the ICESat product `product`. Normally created automatically from
either [`find`](@ref), [`granule_from_file`](@ref) or [`granules_from_folder`](@ref).
"""
Base.@kwdef mutable struct ICESat_Granule{product} <: Granule
    id::String
    url::String
    info::NamedTuple
    polygons::MultiPolygonType = MultiPolygonType()
end
ICESat_Granule(product, args...) = ICESat_Granule{product}(args...)

function Base.copy(g::ICESat_Granule{product}) where {product}
    return ICESat_Granule(product, g.id, copy(g.url), copy(g.info), copy(g.polygons))
end

function bounds(granule::ICESat_Granule)
    HDF5.h5open(granule.url, "r") do file
        nt = attributes(file)
        ntb = (
            min_x = parse(Float64, read(nt["geospatial_lon_min"])),
            min_y = parse(Float64, read(nt["geospatial_lat_min"])),
            max_x = parse(Float64, read(nt["geospatial_lon_max"])),
            max_y = parse(Float64, read(nt["geospatial_lat_max"])),
        )
        return ntb
    end
end

Base.isfile(g::ICESat_Granule) = Base.isfile(g.url)

"""
    info(g::ICESat_Granule)

Derive info based on the filename. The name is built up as follows:
ATL03_[yyyymmdd][hhmmss]_[ttttccss]_[vvv_rr].h5. See section 1.2.5 in the user guide.
"""
function info(g::ICESat_Granule)
    return icesat_info(g.id)
end

function icesat_info(filename)
    id, _ = splitext(filename)
    type, revision, orbit, cycle, track, segment, version, filetype =
        split(id, "_")
    return (
        type = Symbol(type),
        phase = parse(Int, orbit[1]),
        rgt = parse(Int, track[2]),
        instance = parse(Int, track[3:4]),
        cycle = parse(Int, cycle),
        segment = parse(Int, segment),
        version = parse(Int, version),
        revision = parse(Int, revision),
    )
end

function topex_to_wgs84_ellipsoid()
    # convert from TOPEX/POSEIDON to WGS84 ellipsoid using Proj.jl
    # This pipeline was validated against MATLAB's geodetic2ecef -> ecef2geodetic
    pipe = Proj.proj_create(
        "+proj=pipeline +step +proj=unitconvert +xy_in=deg +z_in=m +xy_out=rad +z_out=m +step +inv +proj=longlat +a=6378136.3 +rf=298.257 +e=0.08181922146 +step +proj=cart +a=6378136.3 +rf=298.257 +step +inv +proj=cart +ellps=WGS84 +step +proj=unitconvert +xy_in=rad +z_in=m +xy_out=deg +z_out=m +step +proj=axisswap +order=2,1",
    )
end
