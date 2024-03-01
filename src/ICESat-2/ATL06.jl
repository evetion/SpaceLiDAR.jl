"""
    points(g::ICESat2_Granule{:ATL06}, tracks=icesat2_tracks, step=1, bbox::Union{Nothing,Extent,NamedTuple} = nothing)

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
    bbox::Union{Nothing,Extent,NamedTuple} = nothing,
)
    if bbox isa NamedTuple
        bbox = convert(Extent, bbox)
        Base.depwarn(
            "The `bbox` keyword argument as a NamedTuple will be deprecated in a future release " *
            "Please use `Extents.Extent` directly or use convert(Extent, bbox::NamedTuple)`.",
            :points,
        )
    end
    nts = HDF5.h5open(granule.url, "r") do file
        t_offset = open_dataset(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset
        ftracks = filter(track -> haskey(file, track) && haskey(open_group(file, track), "land_ice_segments"), tracks)
        map(ftracks) do track
            track_nt = points(granule, file, track, t_offset, step, bbox)
            if !isempty(track_nt.height)
                track_nt.height[track_nt.height.==fill_value] .= NaN
            end
            track_nt
        end
    end
    return PartitionedTable(nts, granule)
end

function points(
    ::ICESat2_Granule{:ATL06},
    file::HDF5.H5DataStore,
    track::AbstractString,
    t_offset::Float64,
    step = 1,
    bbox = bbox::Union{Nothing,Extent} = nothing,
)
    group = open_group(file, track)

    # subset by bbox ?
    if !isnothing(bbox)
        x = read_dataset(group, "land_ice_segments/longitude")::Vector{Float64}
        y = read_dataset(group, "land_ice_segments/latitude")::Vector{Float64}

        # find index of points inside of bbox
        ind = (x .> bbox.X[1]) .& (y .> bbox.Y[1]) .& (x .< bbox.X[2]) .& (y .< bbox.Y[2])
        start = findfirst(ind)
        stop = findlast(ind)

        if isnothing(start)
            @warn "no data found within bbox of track $track in $(file.filename)"

            spot_number = read_attribute(group, "atlas_spot_number")::String
            atlas_beam_type = read_attribute(group, "atlas_beam_type")::String

            nt = (;
                longitude = Float64[],
                latitude = Float64[],
                height = Float32[],
                height_error = Float32[],
                datetime = Dates.DateTime[],
                quality = Bool[],
                track = Fill(track, 0),
                strong_beam = Fill(atlas_beam_type == "strong", 0),
                detector_id = Fill(parse(Int8, spot_number), 0),
                height_reference = Float32[],
            )
            return nt
        end

        # only include x and y data within bbox
        x = x[start:step:stop]
        y = y[start:step:stop]
    else
        start = 1
        stop = length(open_dataset(group, "land_ice_segments/longitude"))
        x = open_dataset(group, "land_ice_segments/longitude")[start:step:stop]::Vector{Float64}
        y = open_dataset(group, "land_ice_segments/latitude")[start:step:stop]::Vector{Float64}
    end

    z = open_dataset(group, "land_ice_segments/h_li")[start:step:stop]::Vector{Float32}
    sigma_geo_h = open_dataset(group, "land_ice_segments/sigma_geo_h")[start:step:stop]::Vector{Float32}
    h_li_sigma = open_dataset(group, "land_ice_segments/h_li_sigma")[start:step:stop]::Vector{Float32}
    t = open_dataset(group, "land_ice_segments/delta_time")[start:step:stop]::Vector{Float64}
    q = open_dataset(group, "land_ice_segments/atl06_quality_summary")[start:step:stop]::Vector{Int8}
    dem = open_dataset(group, "land_ice_segments/dem/dem_h")[start:step:stop]::Vector{Float32}
    spot_number = read_attribute(group, "atlas_spot_number")::String
    atlas_beam_type = read_attribute(group, "atlas_beam_type")::String
    times = unix2datetime.(t .+ t_offset)

    sigma_geo_h[sigma_geo_h.==fill_value] .= NaN
    h_li_sigma[h_li_sigma.==fill_value] .= NaN

    nt = (
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
