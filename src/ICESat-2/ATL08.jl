"""
    points(g::ICESat2_Granule{:ATL08}; tracks=icesat2_tracks, step=1, canopy=false, ground=true))

Retrieve the points for a given ICESat-2 ATL08 (Land and Vegetation Height) granule as a list of namedtuples, one for each beam.
The names of the tuples are based on the following fields:

| Column             | Field                                    | Description                                           | Units                        |
|:------------------ |:---------------------------------------- |:----------------------------------------------------- |:---------------------------- |
| `longitude`        | `land_segments/longitude`                | Longitude of segment center, WGS84, East=+            | decimal degrees              |
| `latitude`         | `land_segments/latitude`                 | Latitude of segment center, WGS84, North=+            | decimal degrees              |
| `height`           | `land_segments/terrain/h_te_mean`        | Standard land-ice segment height                      | m above the WGS 84 ellipsoid |
| `height_error`     | `land_segments/terrain/h_te_uncertainty` | Total vertical geolocation error                      | m                            |
| `datetime`         | `land_segments/delta_time`               | + `ancillary_data/atlas_sdp_gps_epoch` + `gps_offset` | date-time                    |
| `quality`          | `land_segments/terrain_flg`              | Boolean flag indicating the best-quality subset       | 1 = high quality             |
| `phr`              | `land_segments/ph_removal_flag`          | More than 50% of photons removed                      | -                            |
| `sensitivity`      | `land_segments/snr`                      | The signal to noise ratio                             | -                            |
| `scattered`        | `land_segments/msw_flag`                 | Multiple Scattering warning flag                      | -1=unknown; 0=none           |
| `saturated`        | `land_segments/sat_flag`                 | Saturation detected                                   | -                            |
| `clouds`           | `land_segments/layer_flag`               | Clouds or blowing snow are likely present             | -                            |
| `track`            | `gt1l` - `gt3r` groups                   | -                                                     | -                            |
| `strong_beam`      | `-`                                      | "strong" (true) or "weak" (false) laser power         | -                            |
| `classification`   | `-`                                      | "ground", "high_canopy"                               | -                            |
| `height_reference` | `land_segments/dem_h`                    | Height of the (best available) DEM                    | m above the WGS 84 ellipsoid |
| `detector_id`      | `atlas_spot_number attribute`            | -                                                     | -                            |

You can combine the output in a `DataFrame` with `reduce(vcat, DataFrame.(points(g)))` if you
want to change the default arguments or `DataFrame(g)` with the default options.
"""
function points(granule::ICESat2_Granule{:ATL08}; tracks = icesat2_tracks, step = 1, canopy = false, ground = true)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset

        for track in tracks
            if in(track, keys(file)) && in("land_segments", keys(file[track]))
                for track_nt in points(granule, file, track, t_offset, step, canopy, ground)
                    track_nt.height[track_nt.height.==fill_value] .= NaN
                    push!(dfs, track_nt)
                end
            end
        end
    end
    dfs
end

function points(
    ::ICESat2_Granule{:ATL08},
    file::HDF5.H5DataStore,
    track::AbstractString,
    t_offset::Float64,
    step = 1,
    canopy = false,
    ground = true,
)
    if ground
        zt = file["$track/land_segments/terrain/h_te_mean"][1:step:end]::Vector{Float32}
        tu = file["$track/land_segments/terrain/h_te_uncertainty"][1:step:end]::Vector{Float32}
    end
    if canopy
        zc = file["$track/land_segments/canopy/h_mean_canopy_abs"][1:step:end]::Vector{Float32}
        cu = file["$track/land_segments/canopy/h_canopy_uncertainty"][1:step:end]::Vector{Float32}
    end
    x = file["$track/land_segments/longitude"][1:step:end]::Vector{Float32}
    y = file["$track/land_segments/latitude"][1:step:end]::Vector{Float32}
    t = file["$track/land_segments/delta_time"][1:step:end]::Vector{Float64}
    sensitivity = file["$track/land_segments/snr"][1:step:end]::Vector{Float32}
    clouds = file["$track/land_segments/layer_flag"][1:step:end]::Vector{Int8}
    scattered = file["$track/land_segments/msw_flag"][1:step:end]::Vector{Int8}
    saturated = file["$track/land_segments/sat_flag"][1:step:end]::Vector{Int8}
    q = file["$track/land_segments/terrain_flg"][1:step:end]::Vector{Int32}
    phr = file["$track/land_segments/ph_removal_flag"][1:step:end]::Vector{Int8}
    dem = file["$track/land_segments/dem_h"][1:step:end]::Vector{Float32}
    times = unix2datetime.(t .+ t_offset)
    atlas_beam_type = attrs(file["$track"])["atlas_beam_type"]::String
    spot_number = attrs(file["$track"])["atlas_spot_number"]::String

    if ground
        gt = (
            longitude = x,
            latitude = y,
            height = zt,
            height_error = tu,
            datetime = times,
            quality = .!Bool.(q),
            phr = Bool.(phr),
            sensitivity = sensitivity,
            scattered = Int16.(scattered),
            saturated = Int16.(saturated),
            clouds = Bool.(clouds),
            track = Fill(track, length(times)),
            strong_beam = Fill(atlas_beam_type == "strong", length(times)),
            classification = Fill("ground", length(times)),
            height_reference = dem,
            detector_id = Fill(parse(Int8, spot_number), length(times)),
        )
    end
    if canopy
        ct = (
            longitude = x,
            latitude = y,
            height = zc,
            height_error = cu,
            datetime = times,
            quality = .!Bool.(q),
            phr = Bool.(phr),
            sensitivity = sensitivity,
            scattered = Int16.(scattered),
            saturated = Int16.(saturated),
            clouds = Bool.(clouds),
            track = Fill(track, length(times)),
            strong_beam = Fill(atlas_beam_type == "strong", length(times)),
            classification = Fill("high_canopy", length(times)),
            return_number = Fill(1, length(times)),
            number_of_returns = Fill(2, length(times)),
            height_reference = dem,
            detector_id = Fill(parse(Int8, spot_number), length(times)),
        )
    end
    if canopy && ground
        ct, gt
    elseif canopy
        (ct,)
    elseif ground
        (gt,)
    else
        ()
    end
end

function lines(granule::ICESat2_Granule{:ATL08}; tracks = icesat2_tracks, step = 100, quality = 1)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        # t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset

        for track ∈ tracks
            if in(track, keys(file)) && in("land_segments", keys(file[track]))
                height = file["$track/land_segments/terrain/h_te_mean"][1:step:end]::Array{Float32,1}
                longitude = file["$track/land_segments/longitude"][1:step:end]::Array{Float32,1}
                latitude = file["$track/land_segments/latitude"][1:step:end]::Array{Float32,1}
                # t = file["$track/land_segments/delta_time"][1:step:end]::Array{Float64,1}
                # times = unix2datetime.(t .+ t_offset)
                atlas_beam_type = attrs(file["$track"])["atlas_beam_type"]::String

                height[height.==fill_value] .= NaN
                line = makeline(longitude, latitude, height)
                # i = div(length(t), 2) + 1
                nt = (geom = line, track = track, strong_beam = atlas_beam_type == "strong", granule = granule.id)
                push!(dfs, nt)
            end
        end
    end
    dfs
end

function atl03_mapping(granule::ICESat2_Granule{:ATL08})
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        for track ∈ icesat2_tracks
            if in(track, keys(file)) && in("signal_photons", keys(file[track]))
                df = atl03_mapping(file, track)
                push!(dfs, df)
            end
        end
    end
    dfs
end

function atl03_mapping(granule::ICESat2_Granule{:ATL08}, track::AbstractString)
    HDF5.h5open(granule.url, "r") do file
        if in(track, keys(file)) && in("signal_photons", keys(file[track]))
            df = atl03_mapping(file, track)
        end
    end
end

function atl03_mapping(file::HDF5.H5DataStore, track::AbstractString)
    c = read(file, "$track/signal_photons/classed_pc_flag")::Array{Int8,1}
    i = read(file, "$track/signal_photons/classed_pc_indx")::Array{Int32,1}
    s = read(file, "$track/signal_photons/ph_segment_id")::Array{Int32,1}
    (segment = s, index = i, classification = c, track = track)
end
