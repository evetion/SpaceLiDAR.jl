using Dates

const icesat2_tracks = ("gt1l", "gt1r", "gt2l", "gt2r", "gt3l", "gt3r")
const classification = Dict(0x03 => "low_canopy", 0x02 => "ground", 0x04 => "high_canopy", 0x05 => "unclassified", 0x01 => "noise")
const icesat_date_format = dateformat"yyyymmddHHMMSS"
const gps_offset = 315964800
const fill_value = 3.4028235f38
const blacklist = readlines(joinpath(@__DIR__, "blacklist.txt"))
const icesat2_inclination = 88.0  # actually 92, so this is 180. - 92.


mutable struct ICESat2_Granule{product} <: Granule
    id::String
    url::String
    bbox::NamedTuple
    info::NamedTuple
end
ICESat2_Granule(product, args...) = ICESat2_Granule{product}(args...)

function Base.copy(g::ICESat2_Granule{product}) where product
    ICESat2_Granule(product, g.id, g.url, g.bbox, g.info)
end

function bounds(granule::ICESat2_Granule)
    HDF5.h5open(granule.url, "r") do file
        extent = attributes(file["METADATA/Extent"])
        nt = (;collect(Symbol(x) => read(extent[x]) for x in keys(extent))...)
        ntb = (min_x = nt.westBoundLongitude, max_x = nt.eastBoundLongitude, min_y = nt.southBoundLatitude, max_y = nt.northBoundLatitude, min_z = -1000, max_z = 8000)
        granule.bbox = ntb
        ntb
    end
end

"""Rough approximation of the track angle on a Euclidian lon/lat plot."""
function angle(::ICESat2_Granule, latitude=0.0)
    d = icesat2_inclination / (pi / 2)
    cos(latitude / d) * icesat2_inclination
end

"""Return whether track is a strong or weak beam.
See Section 7.5 The Spacecraft Orientation Parameter of the ATL03 ATDB."""
function track_power(orientation::Integer, track::String)
    # Backward orientation, left beam is strong
    if orientation == 0
        ifelse(occursin("r", track), "weak", "strong")
    # Forward orientation, right beam is strong
    elseif orientation == 1
        ifelse(occursin("r", track), "strong", "weak")
    # Orientation in transit, degradation could occur
    else
        "transit"
    end
end

Base.isfile(g::ICESat2_Granule) = Base.isfile(g.url)

function Base.convert(product::Symbol, g::ICESat2_Granule{T}) where T
    g = ICESat2_Granule{product}(
        replace(replace(g.id, String(T) => String(product)), lowercase(String(T)) => lowercase(String(product))),
        replace(replace(g.url, String(T) => String(product)), lowercase(String(T)) => lowercase(String(product))),
        g.bbox,
        g.info
    )
    # Check other version
    if !isfile(g)
        # TODO Also check higher versions
        url = replace(g.url, "01.h5" => "02.h5")
        if isfile(url)
            @warn "Used newer version available"
            g = ICESat2_Granule{product}(g.id, url, g.bbox, g.info)
        end
    end
    g
end

"""Derive info based on file id.

The id is built up as follows, see 1.2.5 in the user guide
ATL03_[yyyymmdd][hhmmss]_[ttttccss]_[vvv_rr].h5
"""
function info(g::ICESat2_Granule)
    icesat2_info(g.id)
end

# Granule regions 1-14. Region 4 (North Pole) and region 11 (Sout Pole) are both ascending descending
const ascending_segments = [true, true, true, true, false, false, false, false, false, false, true, true, true, true]
const descending_segments = [false, false, false, true, true, true, true, true, true, true, true, false, false, false]

function icesat2_info(filename)
    id, _ = splitext(filename)
    type, datetime, track, version, revision = split(id, "_")
    segment = parse(Int, track[7:end])
    (type = Symbol(type), date = DateTime(datetime, icesat_date_format), rgt = parse(Int, track[1:4]), cycle = parse(Int, track[5:6]), segment = segment, version = parse(Int, version), revision = parse(Int, revision), ascending = ascending_segments[segment], descending = descending_segments[segment])
end

function is_blacklisted(g::Granule)
    g.id in blacklist
end
