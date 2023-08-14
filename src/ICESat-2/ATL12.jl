"""
    points(g::ICESat2_Granule{:ATL12}, tracks=icesat2_tracks)

Retrieve the points for a given ICESat-2 ATL12 (Ocean Surface Height) granule as a list of namedtuples, one for each beam.
The names of the tuples are based on the following fields:

| Column        | Field                         | Description                                           | Units                        |
|:------------- |:----------------------------- |:----------------------------------------------------- |:---------------------------- |
| `longitude`   | `ssh_segments/longitude`      | Longitude of segment center, WGS84, East=+            | decimal degrees              |
| `latitude`    | `ssh_segments/latitude`       | Latitude of segment center, WGS84, North=+            | decimal degrees              |
| `height`      | `ssh_segments/heights/h`      | Standard land-ice segment height                      | m above the WGS 84 ellipsoid |
| `datetime`    | `ssh_segments/delta_time`     | + `ancillary_data/atlas_sdp_gps_epoch` + `gps_offset` | date-time                    |
| `track`       | `gt1l` - `gt3r` groups        | -                                                     | -                            |
| `strong_beam` | `-`                           | "strong" (true) or "weak" (false) laser power         | -                            |
| `detector_id` | `atlas_spot_number attribute` | -                                                     | -                            |

You can combine the output in a `DataFrame` with `reduce(vcat, DataFrame.(points(g)))` if you
want to change the default arguments or `DataFrame(g)` with the default options.
"""
function points(granule::ICESat2_Granule{:ATL12}, tracks = icesat2_tracks)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = open_dataset(file, "ancillary_data/atlas_sdp_gps_epoch")[1] + gps_offset

        for track ∈ tracks
            if haskey(file, track) && haskey(open_group(file, track), "ssh_segments") && haskey(open_group(file, "$track/ssh_segments"), "heights")
                track_df = points(granule, file, track, t_offset)
                push!(dfs, track_df)
            end
        end
    end
    dfs
end

function points(
    ::ICESat2_Granule{:ATL12},
    file::HDF5.H5DataStore,
    track::AbstractString,
    t_offset::Real,
)
    group = open_group(file, track)

    height = read_dataset(group, "ssh_segments/heights/h")
    longitude = read_dataset(group, "ssh_segments/longitude")
    latitude = read_dataset(group, "ssh_segments/latitude")
    t = read_dataset(group, "ssh_segments/delta_time")

    atlas_beam_type = read_attribute(group, "atlas_beam_type")::String
    spot_number = read_attribute(group, "atlas_spot_number")::String

    datetime = unix2datetime.(t .+ t_offset)

    (
        longitude = longitude,
        latitude = latitude,
        height = height,
        datetime = datetime,
        track = Fill(track, length(datetime)),
        strong_beam = Fill(atlas_beam_type == "strong", length(datetime)),
        detector_id = Fill(parse(Int8, spot_number), length(datetime)),
    )
end
