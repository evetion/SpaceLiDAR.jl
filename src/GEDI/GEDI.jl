using Dates

const gedi_tracks = ("BEAM0000", "BEAM0001", "BEAM0010", "BEAM0011", "BEAM0101", "BEAM0110", "BEAM1000", "BEAM1011")
const gedi_date_format = dateformat"yyyymmddHHMMSS"
const gedi_inclination = 51.6443

mutable struct GEDI_Granule{product} <: Granule
    id::AbstractString
    url::AbstractString
    info::NamedTuple
end
GEDI_Granule(product, args...) = GEDI_Granule{product}(args...)

function Base.copy(g::GEDI_Granule{product}) where product
    GEDI_Granule(product, g.id, g.url, g.info)
end

function info(g::GEDI_Granule)
    gedi_info(g.id)
end

"""Derive info based on file id.

The id is built up as follows, see section 2.4 in the user guide
GEDI02_A_2019110014613_O01991_T04905_02_001_01.h5
or newer (V2)
GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5
"""
function gedi_info(filename)
    id, _ = splitext(filename)
    if endswith(id, "V002")
        type, name, datetime, orbit, segment, track, ppds, pge_version, revision, version = Base.split(id, "_")
        version = version[2:end]
    else
        type, name, datetime, orbit, track, ppds, version, revision = Base.split(id, "_")
    end
    days = Day(parse(Int, datetime[5:7]) - 1)  # Stored as #days in year
    datetime = datetime[1:4] * "0101" * datetime[8:end]
    (type = Symbol(type * "_" * name), date = DateTime(datetime, gedi_date_format) + days, orbit = parse(Int, orbit[2:end]), track = parse(Int, track[2:end]), ppds = parse(Int, ppds), version = parse(Int, version), revision = parse(Int, revision))
end

"""Rough approximation of the track angle on a Euclidian lon/lat plot."""
function angle(::GEDI_Granule, latitude=0.0)
    d = gedi_inclination / (pi / 2)
    cos(latitude / d) * gedi_inclination
end
