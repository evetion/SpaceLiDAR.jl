using Dates

const gedi_tracks = ("BEAM0000", "BEAM0001", "BEAM0010", "BEAM0011", "BEAM0101", "BEAM0110", "BEAM1000", "BEAM1011")
const gedi_date_format = dateformat"yyyymmddHHMMSS"
const gedi_inclination = 51.6443

"""
    GEDI_Granule{product} <: Granule

A granule of the GEDI product `product`. Normally created automatically from
either [`find`](@ref), [`granule_from_file`](@ref) or [`granules_from_folder`](@ref).
"""
Base.@kwdef mutable struct GEDI_Granule{product} <: Granule
    id::AbstractString
    url::AbstractString
    info::NamedTuple
    polygons::MultiPolygonType = MultiPolygonType()
end

sproduct(::GEDI_Granule{product}) where {product} = product
mission(::GEDI_Granule) = :GEDI

function Base.copy(g::GEDI_Granule{product}) where {product}
    GEDI_Granule{product}(g.id, g.url, g.info, copy(g.polygons))
end


"""
    info(g::GEDI_Granule)

Derive info based on the filename. This is built up as follows:
`GEDI02_A_2019110014613_O01991_T04905_02_001_01.h5`
or in case of v"2": `GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5`.
See section 2.4 in the user guide.
"""
function info(g::GEDI_Granule)
    gedi_info(g.id)
end

function gedi_info(filename)
    id, _ = splitext(basename(filename))
    if endswith(id, "V002")
        type, name, datetime, orbit, sub_orbit, track, ppds, pge_version, revision, version = Base.split(id, "_")
        version = version[2:end]
    else
        type, name, datetime, orbit, track, ppds, version, revision = Base.split(id, "_")
    end
    days = Day(parse(Int, datetime[5:7]) - 1)  # Stored as #days in year
    datetime = datetime[1:4] * "0101" * datetime[8:end]
    (
        type = Symbol(type * "_" * name),
        date = DateTime(datetime, gedi_date_format) + days,
        orbit = parse(Int32, orbit[2:end]),
        sub_orbit = parse(Int8, sub_orbit),
        track = parse(Int32, track[2:end]),
        ppds = parse(Int8, ppds),
        pge_version = parse(Int8, pge_version),
        version = parse(Int, version),
        revision = parse(Int, revision),
    )
end

"""
    track_angle(::GEDI_Granule, latitude = 0.0)

Rough approximation of the track angle (0° is North) of ICESat-2 at a given `latitude`.

# Examples

```jlcon
julia> g = GEDI_Granule(:GEDI02_A, "GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5", "", (;))
julia> track_angle(g, 0.0)
38.24944944866377
```
"""
function track_angle(g::GEDI_Granule, latitude = 0.0, nparts = 100)

    latitudes, _, angles = SpaceLiDAR.greatcircle(0.0, 0.0, gedi_inclination, 85.0, nparts)
    clamp!(angles, 0, 90)
    v, i = findmin(abs.(latitudes .- min(abs(latitude), gedi_inclination)))
    a = angles[i]

    info = gedi_info(g.id)
    if info.sub_orbit <= 2  # ascending
        return a
    else
        return 180 - a
    end
end
