using Dates

const j2000_offset = datetime2unix(DateTime(2000, 1, 1, 12, 0, 0))
const fill_value = 3.4028235f38
const icesat_inclination = 86.0  # actually 92, so this is 180. - 92.


mutable struct ICESat_Granule{product} <: Granule
    id::String
    url::String
    info::NamedTuple
end
ICESat_Granule(product, args...) = ICESat_Granule{product}(args...)

function Base.copy(g::ICESat_Granule{product}) where product
    ICESat_Granule(product, g.id, g.url, g.info)
end

function bounds(granule::ICESat_Granule)
    HDF5.h5open(granule.url, "r") do file
        nt = attributes(file)
        ntb = (
            min_x = parse(Float64, read(nt["geospatial_lon_min"])),
            max_x = parse(Float64, read(nt["geospatial_lon_max"])),
            min_y = parse(Float64, read(nt["geospatial_lat_min"])),
            max_y = parse(Float64, read(nt["geospatial_lat_max"])),
            min_z = -1000,
            max_z = 8000
         )
        @info ntb
        ntb
    end
end


Base.isfile(g::ICESat_Granule) = Base.isfile(g.url)

"""Derive info based on file id.

The id is built up as follows, see 1.2.5 in the user guide
ATL03_[yyyymmdd][hhmmss]_[ttttccss]_[vvv_rr].h5
"""
function info(g::ICESat_Granule)
    icesat_info(g.id)
end

function icesat_info(filename)
    id, _ = splitext(filename)
    type, revision, orbit, cycle, track, segment, version, filetype = split(id, "_")
    (type = Symbol(type), phase = parse(Int, orbit[1]), rgt = parse(Int, track[2]), instance = parse(Int, track[3:4]), cycle = parse(Int, cycle), segment = parse(Int, segment), version = parse(Int, version), revision = parse(Int, revision))
end
