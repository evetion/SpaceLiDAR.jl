"""
    points(g::ICESat2_Granule{:ATL24}; tracks=icesat2_tracks, step=1, canopy=false, ground=true, bbox::Union{Nothing,Extent,NamedTuple} = nothing)

Retrieve the points for a given ICESat-2 ATL24 (Land and Vegetation Height) granule as a list of namedtuples, one for each beam.
With the `tracks` keyword, you can specify which tracks to include. The default is to include all tracks.
With the `step` keyword, you can choose to limit the number of points, the default is 1 (all points).

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
want to change the default arguments or just `DataFrame(g)` with the default options.
"""
function points(
    granule::ICESat2_Granule{:ATL24};
    tracks = icesat2_tracks,
    step = 1,
    bbox::Union{Nothing,Extent} = nothing,
)
    nts = HDF5.h5open(granule.url, "r") do file
        t_offset = read_dataset(file, "ancillary_data/atlas_sdp_gps_epoch") + gps_offset

        # Determine number of loops over tracks
        ftracks = filter(track -> haskey(file, track), tracks)

        map(ftracks) do track
            track_nt = points(granule, file, track, t_offset, step, bbox)
            replace!(x -> x === fill_value ? NaN : x, track_nt.height)
            track_nt
        end
    end
    return PartitionedTable(nts, granule)
end


function points(
    ::ICESat2_Granule{:ATL24},
    file::HDF5.H5DataStore,
    track::AbstractString,
    t_offset::Float64,
    step = 1,
    bbox::Union{Nothing,Extent} = nothing,
)
    group = open_group(file, track)
    # subset by bbox
    if !isnothing(bbox)
        x = open_dataset(group, "lon_ph")[1:step:end]::Vector{Float32}
        y = open_dataset(group, "lat_ph")[1:step:end]::Vector{Float32}

        # find index of points inside of bbox
        ind = (x .> bbox.X[1]) .& (y .> bbox.Y[1]) .& (x .< bbox.X[2]) .& (y .< bbox.Y[2])
        start = findfirst(ind)
        stop = findlast(ind)

        if isnothing(start)
            @warn "no data found within bbox of track $track in $(file.filename)"

            atlas_beam_type = read_attribute(group, "atlas_beam_type")::String
            spot_number = read_attribute(group, "atlas_spot_number")::String

            # class_ph = 40 (bathymetry)
            # confidence > 0.6 (see also low_confidence_flag)
            # sensor_depth_exceeded = 0 (reasonable)
            # delta_time
            # ellipse_h (in m)
            # ortho_h (in m)
            # lat_ph
            # lon_ph
            # sigma_tvu
            # sigma_thu

            nt = (;
                longitude = Float64[],
                latitude = Float64[],
                height = Float32[],
                datetime = Dates.DateTime[],
                track = Fill(track, 0),
                classification = CategoricalArray{String,1,Int8}(fill("unclassified", 0)),
                confidence = Float64[],
                sensor_depth_exceeded = Bool[],
                nigtht_flag = Bool[],
                ellipsoidal_height = Float32[],
                orthometric_height = Float32[],
                sigma_tvu = Float32[],
                sigma_thu = Float32[],
            )
            return nt
        end

        # only include x and y data within bbox
        x = x[start:step:stop]
        y = y[start:step:stop]
    else
        start = 1
        stop = length(open_dataset(group, "lon_ph"))
        x = open_dataset(group, "lon_ph")[start:step:stop]::Vector{Float64}
        y = open_dataset(group, "lat_ph")[start:step:stop]::Vector{Float64}
    end

    h = open_dataset(group, "ellipse_h")[start:step:stop]::Vector{Float32}
    x = open_dataset(group, "lon_ph")[start:step:stop]::Vector{Float64}
    y = open_dataset(group, "lat_ph")[start:step:stop]::Vector{Float64}
    t = open_dataset(group, "delta_time")[start:step:stop]::Vector{Float64}
    class_ph = open_dataset(group, "class_ph")[start:step:stop]::Vector{Int8}
    confidence = open_dataset(group, "confidence")[start:step:stop]::Vector{Float64}
    sensor_depth_exceeded = Bool.(open_dataset(group, "sensor_depth_exceeded")[start:step:stop]::Vector{UInt8})
    night_flag = Bool.(open_dataset(group, "night_flag")[start:step:stop]::Vector{UInt8})
    surface_height = open_dataset(group, "surface_h")[start:step:stop]::Vector{Float32}
    orthometric_height = open_dataset(group, "ortho_h")[start:step:stop]::Vector{Float32}
    sigma_tvu = open_dataset(group, "sigma_tvu")[start:step:stop]::Vector{Float32}
    sigma_thu = open_dataset(group, "sigma_thu")[start:step:stop]::Vector{Float32}

    times = unix2datetime.(t .+ t_offset)

    classification = CategoricalArray{String,1,Int8}(fill("unclassified", length(h)))
    for I in eachindex(class_ph)
        class_ph[I] == 0 && (classification[I] = "unclassified")
        class_ph[I] == 1 && (classification[I] = "other")
        class_ph[I] == 40 && (classification[I] = "bathymetry")
        class_ph[I] == 41 && (classification[I] = "sea surface")
    end

    nt = (;
        longitude = x,
        latitude = y,
        height = h,
        datetime = times,
        track = Fill(track, length(times)),
        classification,
        confidence,
        sensor_depth_exceeded,
        night_flag,
        surface_height,
        orthometric_height,
        sigma_tvu,
        sigma_thu)
    nt

end

function bounds(granule::ICESat2_Granule{:ATL24})
    HDF5.h5open(granule.url, "r") do file

        for track in icesat2_tracks
            haskey(file, track) || continue

            group = open_group(file, track)
            x = open_dataset(group, "lon_ph")[:]
            y = open_dataset(group, "lat_ph")[:]
            return ntb = (
                min_x = minimum(x),
                min_y = minimum(y),
                max_x = maximum(x),
                max_y = maximum(y),
            )
        end
    end
end
