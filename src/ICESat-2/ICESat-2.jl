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
        ifelse(occursin("r", track), "_weak", "_strong")
    # Forward orientation, right beam is strong
    elseif orientation == 1
        ifelse(occursin("r", track), "_strong", "_weak")
    # Orientation in transit, degradation could occur
    else
        "_transit"
    end
end
