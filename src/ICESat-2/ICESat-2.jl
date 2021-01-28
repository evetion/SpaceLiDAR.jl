const icesat2_tracks = ("gt1l", "gt1r", "gt2l", "gt2r", "gt3l", "gt3r")
const classification = Dict(0x03 => "low canopy", 0x02 => "ground", 0x04 => "canopy", 0x05 => "unclassified", 0x01 => "noise")

const gps_offset = 315964800
mutable struct ICESat2_Granule{product} <: Granule
    id::String
    url::String
    bbox::NamedTuple
    info::Dict
end
ICESat2_Granule(product, args...) = ICESat2_Granule{product}(args...)


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
        replace(replace(g.id, String(T)=>String(product)), lowercase(String(T))=>lowercase(String(product))),
        replace(replace(g.url, String(T)=>String(product)), lowercase(String(T))=>lowercase(String(product))),
        g.bbox,
        Dict()
    )
    # Check other version
    if !isfile(g)
        url = replace(g.url, "01.h5"=>"02.h5")
        if isfile(url)
            @warn "Used newer version available"
            g = ICESat2_Granule{product}(g.id, g.url, g.bbox, Dict())
        end
    end
    g
end
