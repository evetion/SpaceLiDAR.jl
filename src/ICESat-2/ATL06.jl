"""
    points(g::ICESat2_Granule{:ATL06})

Retrieve the points for a given ATL06 (Land Ice) granule as a list of namedtuples, one for each beam.
The names of the tuples are based on the following fields:

| Column           | Field                                   | Description                                       |
|------------------|-----------------------------------------|---------------------------------------------------|
| `longitude`        | `land_ice_segments/longitude`             | Longitude of segment center, WGS84, East=+        |
| `latitude`         | `land_ice_segments/latitude`              | Latitude of segment center, WGS84, North=+        |
| `height`           | `land_ice_segments/h_li`                  | Standard land-ice segment height                  |
| `height_error`     | `land_ice_segments/sigma_geo_h`           | Total vertical geolocation error                  |
| `datetime`         | `land_ice_segments/delta_time`            | + `ancillary_data/atlas_sdp_gps_epoch` + `gps_offset` |
| `quality`          | `land_ice_segments/atl06_quality_summary` | Boolean flag indicating the best-quality subset   |
| `track`            | `gt1l` - `gt3r` groups                    | -                                                 |
| `power`            | `-`                                       | "strong" or "weak" laser power                    |
| `detector_id`      | `atlas_spot_number attribute`             | -                                                 |
| `height_reference` | `land_ice_segments/dem/dem_h`             | Height of the (best available) DEM                |

You can combine the output in a `DataFrame` with `reduce(vcat, DataFrame.(points(g)))`.
"""
function points(
    granule::ICESat2_Granule{:ATL06};
    tracks = icesat2_tracks,
    step = 1,
)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset
        orientation = read(file, "orbit_info/sc_orient")[1]::Int8

        for (i, track) in enumerate(tracks)
            power = track_power(orientation, track)
            if in(track, keys(file)) && in("land_ice_segments", keys(file[track]))
                track_nt = points(granule, file, track, power, t_offset, step)
                track_nt.height[track_nt.height.==fill_value] .= NaN
                track_nt.height_error[track_nt.height_error.==fill_value] .= NaN
                push!(dfs, track_nt)
            end
        end
    end
    return dfs
end


function points(
    ::ICESat2_Granule{:ATL06},
    file::HDF5.H5DataStore,
    track::AbstractString,
    power::AbstractString,
    t_offset::Float64,
    step = 1,
)
    z = file["$track/land_ice_segments/h_li"][1:step:end]::Vector{Float32}
    zu = file["$track/land_ice_segments/sigma_geo_h"][1:step:end]::Vector{Float32}
    x = file["$track/land_ice_segments/longitude"][1:step:end]::Vector{Float64}
    y = file["$track/land_ice_segments/latitude"][1:step:end]::Vector{Float64}
    t = file["$track/land_ice_segments/delta_time"][1:step:end]::Vector{Float64}
    q = file["$track/land_ice_segments/atl06_quality_summary"][1:step:end]::Vector{Int8}
    dem = file["$track/land_ice_segments/dem/dem_h"][1:step:end]::Vector{Float32}
    spot_number = attrs(file["$track"])["atlas_spot_number"]::String
    times = unix2datetime.(t .+ t_offset)

    nt = (;
        longitude = x,
        latitude = y,
        height = z,
        height_error = zu,
        datetime = times,
        quality = .!Bool.(q),
        track = Fill(track, length(times)),
        power = Fill(power, length(times)),
        detector_id = Fill(parse(Int8, spot_number), length(times)),
        height_reference = dem,
    )
    return nt
end
