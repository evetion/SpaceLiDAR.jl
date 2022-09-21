"""
    points(g::ICESat2_Granule{:ATL03}, tracks=icesat2_tracks, step=1)

Retrieve the points for a given ICESat-2 ATL03 (Global Geolocated Photon Data) granule as a list of namedtuples, one for each beam.
The names of the tuples are based on the following fields:

| Column             | Field                         | Description                                           | Units                        |
|:------------------ |:----------------------------- |:----------------------------------------------------- |:---------------------------- |
| `longitude`        | `heights/lon_ph`              | Longitude of photon, WGS84, East=+                    | decimal degrees              |
| `latitude`         | `heights/lat_ph`              | Latitude of photon, WGS84, North=+                    | decimal degrees              |
| `height`           | `heights/h_ph`                | Photon WGS84 Height                                   | m above the WGS 84 ellipsoid |
| `quality`          | `heights/quality_ph`          | Indicates the quality of the associated photon        | 0 = nominal                  |
| `uncertainty`      | `geolocation/sigma_h`         | Estimated height uncertainty                          | m                            |
| `datetime`         | `heights/delta_time`          | + `ancillary_data/atlas_sdp_gps_epoch` + `gps_offset` | date-time                    |
| `confidence`       | `heights/signal_conf_ph`      | Photon Signal Confidence                              | 2=low; 3=med; 4=high         |
| `segment`          | `geolocation/segment_id`      | Along-track segment ID number                         | -                            |
| `track`            | `gt1l` - `gt3r` groups        | -                                                     | -                            |
| `strong_beam`      | `-`                           | "strong" (true) or "weak" (false) laser power         | -                            |
| `sun_angle`        | `geolocation/solar_elevation` | Sun angle                                             | ° above horizon              |
| `detector_id`      | `atlas_spot_number attribute` | -                                                     | -                            |
| `height_reference` | `heights/dem/dem_h`           | Height of the (best available) DEM                    | m above the WGS 84 ellipsoid |

You can combine the output in a `DataFrame` with `reduce(vcat, DataFrame.(points(g)))` if you
want to change the default arguments or `DataFrame(g)` with the default options.
"""
function points(granule::ICESat2_Granule{:ATL03}; tracks = icesat2_tracks, step = 1)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset

        for track ∈ tracks
            if in(track, keys(file)) && in("heights", keys(file[track]))
                track_df = points(granule, file, track, t_offset, step)
                push!(dfs, track_df)
            end
        end
    end
    for df in dfs
        df.height[df.height.==fill_value] .= NaN
    end
    dfs
end

function lines(granule::ICESat2_Granule{:ATL03}; tracks = icesat2_tracks, step = 100)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset

        for track ∈ tracks
            if in(track, keys(file)) && in("heights", keys(file[track]))
                track_df = points(granule, file, track, t_offset, step)
                line = Line(track_df.longitude, track_df.latitude, Float64.(track_df.height))
                i = div(length(track_df.datetime), 2) + 1
                nt = (
                    geom = line,
                    sun_angle = Float64(track_df.sun_angle[i]),
                    track = track,
                    strong_beam = track_df.strong_beam[i],
                    t = track_df.datetime[i],
                    granule = granule.id,
                )
                push!(dfs, nt)
            end
        end
    end
    dfs
end

function points(
    ::ICESat2_Granule{:ATL03},
    file::HDF5.H5DataStore,
    track::AbstractString,
    t_offset::Float64,
    step = 1,
)
    z = file["$track/heights/h_ph"][1:step:end]::Vector{Float32}
    x = file["$track/heights/lon_ph"][1:step:end]::Vector{Float64}
    y = file["$track/heights/lat_ph"][1:step:end]::Vector{Float64}
    t = file["$track/heights/delta_time"][1:step:end]::Vector{Float64}
    c = file["$track/heights/signal_conf_ph"][1, 1:step:end]::Vector{Int8}
    q = file["$track/heights/quality_ph"][1:step:end]::Vector{Int8}

    # Segment calc
    segment_counts = read(file, "$track/geolocation/segment_ph_cnt")::Vector{Int32}

    segment = read(file, "$track/geolocation/segment_id")::Vector{Int32}
    segments = map_counts(segment, segment_counts)[1:step:end]

    sun_angle = read(file, "$track/geolocation/solar_elevation")::Vector{Float32}
    sun_angles = map_counts(sun_angle, segment_counts)[1:step:end]

    u = read(file, "$track/geolocation/sigma_h")::Vector{Float32}
    uu = map_counts(u, segment_counts)[1:step:end]

    dem = read(file, "$track/geophys_corr/dem_h")::Vector{Float32}
    demd = map_counts(dem, segment_counts)[1:step:end]

    atlas_beam_type = attrs(file["$track"])["atlas_beam_type"]::String
    spot_number = attrs(file["$track"])["atlas_spot_number"]::String

    times = unix2datetime.(t .+ t_offset)

    (
        longitude = x,
        latitude = y,
        height = z,
        quality = q,
        uncertainty = uu,
        datetime = times,
        confidence = c,
        segment = segments,
        track = Fill(track, length(times)),
        strong_beam = Fill(atlas_beam_type == "strong", length(times)),
        sun_angle = sun_angles,
        detector_id = Fill(parse(Int8, spot_number), length(times)),
        height_reference = demd,
    )
end

function map_counts(values, counts)
    c = fill(zero(eltype(values)), sum(counts))
    ref = 1
    for i in eachindex(counts)
        value = values[i]
        count = counts[i]
        c[ref:ref+count-1] .= value
        ref += count
    end
    c
end

"""
    classify(granule::ICESat2_Granule{:ATL03}, atl08::Union{ICESat2_Granule{:ATL08},Nothing} = nothing, tracks = icesat2_tracks)

Like [`points(::ICESat2_Granule{:ATL03})`](@ref) but with the classification from the ATL08 dataset.
If an ATL08 granule is not provided, we try to find it based on the ATL03 name using [`convert`](@ref SpaceLiDAR.Base.convert).
"""
function classify(
    granule::ICESat2_Granule{:ATL03},
    atl08::Union{ICESat2_Granule{:ATL08},Nothing} = nothing;
    tracks = icesat2_tracks,
)
    if isnothing(atl08)
        atl08 = convert(:ATL08, granule)
    end

    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset

        for track ∈ tracks
            if in(track, keys(file)) && in("heights", keys(file[track]))
                track_df = points(granule, file, track, t_offset)

                mapping = atl03_mapping(atl08, track)

                unique_segments = unique(mapping.segment)
                index_map = create_mapping(track_df.segment, unique_segments)

                class = CategoricalArray{String,1,Int8}(fill("unclassified", length(track_df.longitude)))
                for i = 1:length(mapping.segment)
                    index = get(index_map, mapping.segment[i], nothing)
                    isnothing(index) && continue
                    offset = mapping.index[i] - 1
                    class[index+offset] = classification[mapping.classification[i]+1]
                end
                track_dfc = merge(track_df, (classification = class,))
                push!(dfs, track_dfc)
            end
        end
    end
    dfs
end

function create_mapping(dfsegment, unique_segments)
    index_map = Dict{Int64,Int64}()
    for unique_segment in unique_segments
        pos = searchsortedfirst(dfsegment, unique_segment)
        if (pos <= length(dfsegment)) && (dfsegment[pos] == unique_segment)
            index_map[unique_segment] = pos
        end
    end
    index_map
end
