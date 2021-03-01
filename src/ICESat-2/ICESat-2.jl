using Dates

const icesat2_tracks = ("gt1l", "gt1r", "gt2l", "gt2r", "gt3l", "gt3r")
const classification = Dict(0x03 => "low canopy", 0x02 => "ground", 0x04 => "canopy", 0x05 => "unclassified", 0x01 => "noise")
const icesat_date_format = dateformat"yyyymmddHHMMSS"
const gps_offset = 315964800
const fill_value = 3.4028235f38
const blacklist = readlines(joinpath(@__DIR__, "blacklist.txt"))

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
        Dict()
    )
    # Check other version
    if !isfile(g)
        url = replace(g.url, "01.h5" => "02.h5")
        if isfile(url)
            @warn "Used newer version available"
            g = ICESat2_Granule{product}(g.id, g.url, g.bbox, Dict())
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

function icesat2_info(filename)
    id, _ = splitext(filename)
    type, datetime, track, version, revision = split(id, "_")
    (type = Symbol(type), date = DateTime(datetime, icesat_date_format), rgt = parse(Int, track[1:4]), cycle = parse(Int, track[5:6]), segment = parse(Int, track[7:end]), version = parse(Int, version), revision = parse(Int, revision))
end

function is_blacklisted(g::Granule)
    g.id in blacklist
end
