"""
    points(g::ICESat2_Granule{:ATL06}, tracks=icesat2_tracks, step=1)

Retrieve the points for a given ICESat-2 ATL06 (Land Ice) granule as a list of namedtuples, one for each beam.
The names of the tuples are based on the following fields:

| Column             | Field                                     | Description                                           | Units                        |
|:------------------ |:----------------------------------------- |:----------------------------------------------------- |:---------------------------- |
| `longitude`        | `land_ice_segments/longitude`             | Longitude of segment center, WGS84, East=+            | decimal degrees              |
| `latitude`         | `land_ice_segments/latitude`              | Latitude of segment center, WGS84, North=+            | decimal degrees              |
| `height`           | `land_ice_segments/h_li`                  | Standard land-ice segment height                      | m above the WGS 84 ellipsoid |
| `height_error`     | √(`land_ice_segments/sigma_geo_h`² +      | Total vertical geolocation error                      | m above the WGS 84 ellipsoid |
|                    | `land_ice_segments/h_li_sigma`²)          |                                                       |                              |
| `datetime`         | `land_ice_segments/delta_time`            | + `ancillary_data/atlas_sdp_gps_epoch` + `gps_offset` | date-time                    |
| `quality`          | `land_ice_segments/atl06_quality_summary` | Boolean flag indicating the best-quality subset       | 1 = high quality             |
| `track`            | `gt1l` - `gt3r` groups                    | -                                                     | -                            |
| `strong_beam`      | `-`                                       | "strong" (true) or "weak" (false) laser power         | -                            |
| `detector_id`      | `atlas_spot_number attribute`             | -                                                     | -                            |
| `height_reference` | `land_ice_segments/dem/dem_h`             | Height of the (best available) DEM                    | -                            |

You can combine the output in a `DataFrame` with `reduce(vcat, DataFrame.(points(g)))` if you
want to change the default arguments or `DataFrame(g)` with the default options.
"""
function points(
    granule::ICESat2_Granule{:ATL06};
    tracks = icesat2_tracks,
    step = 1,
)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset
        for (i, track) in enumerate(tracks)
            if in(track, keys(file)) && in("land_ice_segments", keys(file[track]))
                track_nt = points(granule, file, track, t_offset, step)
                track_nt.height[track_nt.height.==fill_value] .= NaN
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
    t_offset::Float64,
    step = 1,
)
    z = file["$track/land_ice_segments/h_li"][1:step:end]::Vector{Float32}
    sigma_geo_h = file["$track/land_ice_segments/sigma_geo_h"][1:step:end]::Vector{Float32}
    h_li_sigma = file["$track/land_ice_segments/h_li_sigma"][1:step:end]::Vector{Float32}
    x = file["$track/land_ice_segments/longitude"][1:step:end]::Vector{Float64}
    y = file["$track/land_ice_segments/latitude"][1:step:end]::Vector{Float64}
    t = file["$track/land_ice_segments/delta_time"][1:step:end]::Vector{Float64}
    q = file["$track/land_ice_segments/atl06_quality_summary"][1:step:end]::Vector{Int8}
    dem = file["$track/land_ice_segments/dem/dem_h"][1:step:end]::Vector{Float32}
    spot_number = attrs(file["$track"])["atlas_spot_number"]::String
    atlas_beam_type = attrs(file["$track"])["atlas_beam_type"]::String
    times = unix2datetime.(t .+ t_offset)

    sigma_geo_h[sigma_geo_h.==fill_value] .= NaN
    h_li_sigma[h_li_sigma.==fill_value] .= NaN

    nt = (;
        longitude = x,
        latitude = y,
        height = z,
        height_error = sqrt.(sigma_geo_h .^ 2 + h_li_sigma .^ 2),
        datetime = times,
        quality = .!Bool.(q),
        track = Fill(track, length(times)),
        strong_beam = Fill(atlas_beam_type == "strong", length(times)),
        detector_id = Fill(parse(Int8, spot_number), length(times)),
        height_reference = dem,
    )
    return nt
end
