const icesat2_tracks = ("gt1l", "gt1r", "gt2l", "gt2r", "gt3l", "gt3r")
const classification =
    Dict(0x03 => "low_canopy", 0x02 => "ground", 0x04 => "high_canopy", 0x05 => "unclassified", 0x01 => "noise")
const icesat_date_format = dateformat"yyyymmddHHMMSS"
const gps_offset = 315964800
const fill_value = 3.4028235f38
const blacklist = readlines(joinpath(@__DIR__, "blacklist.txt"))
const icesat2_inclination = 88.0  # actually 92, so this is 180. - 92.


"""
    ICESat2_Granule{product} <: Granule

A granule of the ICESat-2 product `product`. Normally created automatically from
either [`search`](@ref), [`granule`](@ref) or [`granules`](@ref).
"""
Base.@kwdef mutable struct ICESat2_Granule{product} <: Granule
    const id::String
    url::String
    const info::NamedTuple
    const polygons::MultiPolygonType = MultiPolygonType()
end

sproduct(::ICESat2_Granule{product}) where {product} = product
mission(::ICESat2_Granule) = :ICESat2

default_tracks(::ICESat2_Granule) = icesat2_tracks

function Base.copy(g::ICESat2_Granule{product}) where {product}
    return ICESat2_Granule{product}(g.id, g.url, g.info, copy(g.polygons))
end

"""
    bounds(granule::ICESat2_Granule)

Return the bounding box of the granule as a `NamedTuple` with fields
`(min_x, min_y, max_x, max_y)`.

!!! warning

    This opens the .h5 file, so it is slow.
"""
function bounds(granule::ICESat2_Granule)
    return HDF5.h5open(granule.url, "r") do file
        extent = attributes(file["METADATA/Extent"])
        nt = (; collect(Symbol(x) => read(extent[x]) for x in keys(extent))...)
        ntb = (
            min_x = nt.westBoundLongitude,
            min_y = nt.southBoundLatitude,
            max_x = nt.eastBoundLongitude,
            max_y = nt.northBoundLatitude,
        )
    end
end

"""
    track_angle(::ICESat2_Granule, latitude = 0.0)

Rough approximation of the track angle (0° is North) of ICESat-2 at a given `latitude`.

# Examples

```jlcon
julia> g = ICESat2_Granule(:ATL08, "ATL08_20181120173503_04550102_005_01.h5", "", (;), (;))
julia> track_angle(g, 0.0)
-1.9923955416702257
```
"""
function track_angle(g::ICESat2_Granule, latitude::Real = 0.0, nparts = 100)

    latitudes, _, angles = greatcircle(0.0, 0.0, icesat2_inclination, -95.0, nparts)
    clamp!(angles, -90, 0)
    v, i = findmin(f -> abs(f - min(abs(latitude), icesat2_inclination)), latitudes)
    a = angles[i]

    info = icesat2_info(id(g))
    if info.ascending
        return a
    else
        return -180 - a
    end
end
function track_angle(g::ICESat2_Granule, latitude::Vector{Real}, nparts = 100)
    latitudes, _, angles = greatcircle(0.0, 0.0, icesat2_inclination, -95.0, nparts)
    clamp!(angles, -90, 0)

    latitude2 = abs.(latitude)
    a = zeros(length(latitude2))
    for I in eachindex(latitude2)
        v, i = findmin(f -> abs(f - min(latitude2[I], icesat2_inclination)), latitudes)
        a[I] = angles[i]
    end

    info = icesat2_info(id(g))
    if info.ascending
        return a
    else
        return -180 .- a
    end
end

# Return whether track is a strong or weak beam.
# See Section 7.5 The Spacecraft Orientation Parameter of the ATL03 ATDB.
function track_power(orientation::Integer, track::String)
    # Backward orientation, left beam is strong
    return if orientation == 0
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

"""
    Base.convert(product::Symbol, g::ICESat2_Granule{T})

Converts the granule `g` to the product `product`, by guessing the correct name.
"""
function Base.convert(product::Symbol, g::ICESat2_Granule{T}) where {T}
    g = ICESat2_Granule{product}(
        _convert(id(g), T, product),
        _convert(g.url, T, product),
        g.info,
        g.polygons,
    )
    # Check other version
    if !isfile(g)
        # TODO Also check higher versions
        url = replace(g.url, "01.h5" => "02.h5")
        if isfile(url)
            @warn "Used newer version available"
            g = ICESat2_Granule(product, g.id, url, g.bbox, g.info)
        end
    end
    return g
end

function _convert(s::AbstractString, old::Symbol, new::Symbol)
    return replace(replace(s, String(old) => String(new)), lowercase(String(old)) => lowercase(String(new)))
end

"""
    info(g::ICESat2_Granule)

Derive info based on the filename. The name is built up as follows:
`ATL03_[yyyymmdd][hhmmss]_[ttttccss]_[vvv_rr].h5`. See section 1.2.5 in the user guide.
"""
function info(g::ICESat2_Granule)
    return icesat2_info(id(g))
end

# Granule regions 1-14. Region 4 (North Pole) and region 11 (South Pole) are both ascending descending
const ascending_segments = [true, true, true, true, false, false, false, false, false, false, true, true, true, true]
const descending_segments = [false, false, false, true, true, true, true, true, true, true, true, false, false, false]

function icesat2_info(filename)
    id, _ = splitext(basename(filename))
    type, datetime, track, version, revision = split(id, "_")
    segment = parse(Int, track[7:end])
    return (
        type = Symbol(type),
        date = DateTime(datetime, icesat_date_format),
        rgt = parse(Int, track[1:4]),
        cycle = parse(Int, track[5:6]),
        segment = segment,
        version = parse(Int, version),
        revision = parse(Int, revision),
        ascending = ascending_segments[segment],
        descending = descending_segments[segment],
    )
end

function is_blacklisted(g::Granule)
    return id(g) in blacklist
end

module ICESat2

    using Tables: Tables
    using ..SpaceAltimetry: Filter, ICESat2_Granule, _namevar, _var
    import ..SpaceAltimetry: _inputs, _mask

    export Quality

    """
        Quality()

    Filter ICESat-2 rows using the quality field exposed by the point methods.
    ATL03 keeps nominal photons (`quality_ph == 0`); ATL06 and ATL08 keep rows
    whose product quality summary is true.
    """
    struct Quality <: Filter end

    const QualityGranule = Union{
        ICESat2_Granule{:ATL03},
        ICESat2_Granule{:ATL06},
        ICESat2_Granule{:ATL08},
    }

    _inputs(::Quality, g::QualityGranule) = [_var(g, :quality)]
    _inputs(::Quality, ::Nothing) = [_namevar(:quality)]

    _is_good_quality(::Missing) = false
    _is_good_quality(value::Bool) = value
    _is_good_quality(value::Number) = iszero(value)
    _is_good_quality(value) = value == "nominal"

    function _mask(::Quality, cols)
        quality = Tables.getcolumn(cols, :quality)
        mask = BitVector(undef, length(quality))
        @inbounds for i in eachindex(quality)
            mask[i] = _is_good_quality(quality[i])
        end
        return mask
    end

end # module ICESat2
