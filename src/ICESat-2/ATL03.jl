"""
    points(g::ICESat2_Granule{:ATL03}, tracks=icesat2_tracks; step=1, bbox::Union{Nothing,Extent,NamedTuple} = nothing)

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
function points(
    granule::ICESat2_Granule{:ATL03};
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
        ftracks = filter(track -> haskey(file, track) && haskey(open_group(file, track), "heights"), tracks)
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

function lines(
    granule::ICESat2_Granule{:ATL03},
    tracks = icesat2_tracks;
    step = 100,
    bbox::Union{Nothing,Extent} = nothing,
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

        ftracks = filter(track -> haskey(file, track) && haskey(open_group(file, track), "heights"), tracks)
        map(ftracks) do track
            track_df = points(granule, file, track, t_offset, step, bbox)
            line = Line(track_df.longitude, track_df.latitude, Float64.(track_df.height))
            i = div(length(track_df.datetime), 2) + 1
            (;
                geom = line,
                sun_angle = Float64(track_df.sun_angle[i]),
                track = track,
                strong_beam = track_df.strong_beam[i],
                t = track_df.datetime[i],
                granule = granule.id,
            )
        end
    end
    PartitionedTable(nts, granule)
end

function points(
    ::ICESat2_Granule{:ATL03},
    file::HDF5.H5DataStore,
    track::AbstractString,
    t_offset::Float64,
    step = 1,
    bbox::Union{Nothing,Extent} = nothing,
)

    group = open_group(file, track)
    if !isnothing(bbox)
        x = read_dataset(group, "heights/lon_ph")::Vector{Float64}
        y = read_dataset(group, "heights/lat_ph")::Vector{Float64}

        # find index of points inside of bbox
        ind = (x .> bbox.X[1]) .& (y .> bbox.Y[1]) .& (x .< bbox.X[2]) .& (y .< bbox.Y[2])
        start = findfirst(ind)
        stop = findlast(ind)

        if isnothing(start)
            @warn "no data found within bbox of track $track in $(file.filename)"
            spot_number = read_attribute(group, "atlas_spot_number")::String
            atlas_beam_type = read_attribute(group, "atlas_beam_type")::String

            nt = (
                longitude = Float64[],
                latitude = Float64[],
                height = Float32[],
                quality = Int8[],
                uncertainty = Float32[],
                datetime = Dates.DateTime[],
                confidence = Int8[],
                segment = Int32[],
                track = Fill(track, 0),
                strong_beam = Fill(atlas_beam_type == "strong", 0),
                sun_angle = Float32[],
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
        stop = length(open_dataset(group, "heights/lon_ph"))
        x = open_dataset(group, "heights/lon_ph")[start:step:stop]::Vector{Float64}
        y = open_dataset(group, "heights/lat_ph")[start:step:stop]::Vector{Float64}
    end

    height = open_dataset(group, "heights/h_ph")[start:step:stop]::Vector{Float32}
    datetime = open_dataset(group, "heights/delta_time")[start:step:stop]::Vector{Float64}

    # NOT SURE WHY ONLY THE FIRST CONFIDENCE FLAG WAS CHOSEN.. MIGHT NEED TO REVISIT
    signal_confidence = open_dataset(group, "heights/signal_conf_ph")[1, start:step:stop]::Vector{Int8}
    quality = open_dataset(group, "heights/quality_ph")[start:step:stop]::Vector{Int8}

    # Mapping between segment and photon
    seg_cnt = read(open_dataset(group, "geolocation/segment_ph_cnt"))::Vector{Int32}
    ph_ind = count2index(seg_cnt)
    ph_ind = ph_ind[start:step:stop]

    # extract data posted at segment frequency and map to photon frequency
    segment = read(open_dataset(group, "geolocation/segment_id"))[ph_ind]::Vector{Int32}
    # segment = segment[ph_ind]

    sun_angle = read(open_dataset(group, "geolocation/solar_elevation"))[ph_ind]::Vector{Float32}
    # sun_angle = sun_angle[ph_ind]

    uncertainty = read(open_dataset(group, "geolocation/sigma_h"))[ph_ind]::Vector{Float32}
    # uncertainty = uncertainty[ph_ind]

    height_ref = read(open_dataset(group, "geophys_corr/dem_h"))[ph_ind]::Vector{Float32}
    # height_ref = height_ref[ph_ind]

    # extract attributes
    spot_number = read_attribute(group, "atlas_spot_number")::String
    atlas_beam_type = read_attribute(group, "atlas_beam_type")::String

    # convert from unix time to julia date time
    datetime = unix2datetime.(datetime .+ t_offset)

    nt = (
        longitude = x,
        latitude = y,
        height = height,
        quality = quality,
        uncertainty = uncertainty,
        datetime = datetime,
        confidence = signal_confidence,
        segment = segment,
        track = Fill(track, length(datetime)),
        strong_beam = Fill(atlas_beam_type == "strong", length(datetime)),
        sun_angle = sun_angle,
        detector_id = Fill(parse(Int8, spot_number), length(datetime)),
        height_reference = height_ref,
    )
    return nt
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

    nts = HDF5.h5open(granule.url, "r") do file
        t_offset = open_dataset(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset

        ftracks = filter(track -> haskey(file, track) && haskey(open_group(file, track), "heights"), tracks)

        map(ftracks) do track
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
            merge(track_df, (classification = class,))
        end
    end
    PartitionedTable(nts, granule)
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

"""
    count2index(counts)

Fast map between (segment) counts and (photon) indices.

```jldoctest
SL.count2index(Int32[1, 2, 0, 5])

# output

8-element Vector{Int32}:
 1
 2
 2
 4
 4
 4
 4
 4
```
"""
function count2index(counts)
    c = fill(zero(eltype(counts)), sum(counts))
    ref = 1
    for i in eachindex(counts)
        count = counts[i]
        c[ref:ref+count-1] .= i
        ref += count
    end
    c
end
