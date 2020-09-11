
function xyz(granule::ICESat2_Granule{:ATL03}, bbox=nothing, tracks=icesat2_tracks)
    df = DataFrame()
    dfs = Vector{DataFrame}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1] + gps_offset
        orientation = read(file, "orbit_info/sc_orient")[1]

        for track ∈ tracks
            power = track_power(orientation, track)
            if in(track, names(file)) && in("heights", names(file[track]))
                track_df = xyz(file, track, power, t_offset)
                push!(dfs, track_df)
            end
        end
    end
    vcat(dfs...)
end

function xyz(file::HDF5.HDF5File, track::AbstractString, power::AbstractString, t_offset::Real)
    z = read(file, "$track/heights/h_ph")
    x = read(file, "$track/heights/lon_ph")
    y = read(file, "$track/heights/lat_ph")
    t = read(file, "$track/heights/delta_time")
    c = read(file, "$track/heights/signal_conf_ph")[1,:]

    # Segment calc
    segment = read(file, "$track/geolocation/segment_id")
    sun_angle = read(file, "$track/geolocation/solar_elevation")
    segment_counts = read(file, "$track/geolocation/segment_ph_cnt")
    segments = map_counts(segment, segment_counts)
    sun_angles = map_counts(sun_angle, segment_counts)

    times = unix2datetime.(t .+ t_offset)

    DataFrame(x=x, y=y, z=z, t=times, confidence=c, segment=segments, track=track * power, sun_angle=sun_angles)
end

function map_counts(values, counts)
    c = fill(zero(eltype(values)), sum(counts))
    ref = 1
    for i in eachindex(counts)
        value = values[i]
        count = counts[i]
        c[ref:ref + count - 1] .= value
        ref += count
    end
    c
end


"""Retrieve all points as classified as ground in ATL08."""
function classify(granule::ICESat2_Granule{:ATL03}, granule_b::Union{ICESat2_Granule{:ATL08},Nothing}=nothing, tracks=icesat2_tracks)
    if isnothing(granule_b)
        granule_b = granule_from_file(replace(granule.url, "ATL03_" => "ATL08_"))
    end

    dfs = Vector{DataFrame}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1] + gps_offset
        orientation = read(file, "orbit_info/sc_orient")[1]

        for track ∈ tracks
            power = track_power(orientation, track)
            if in(track, names(file)) && in("heights", names(file[track]))
                track_df = xyz(file, track, power, t_offset)

                mapping = atl03_mapping(granule_b, track)

                DataFrames.insertcols!(track_df, ncol(track_df) + 1, :classification => "unclassified")
                segments = unique(mapping.segment)
                index_map = create_mapping(track_df, segments)
                for segment in segments
                    pos = searchsortedfirst(track_df.segment, segment)
                    if (pos <= length(track_df.segment)) && (track_df.segment[pos] == segment)
                        index_map[segment] = pos
                    else
                        index_map[segment] = nothing
                    end
                end

                for row in eachrow(mapping)
                    index = index_map[row.segment]
                    isnothing(index) && continue
                    offset = row.index - 1
                    track_df[index + offset, :classification] = classification[row.classification + 1]
                    # subdf[index + offset, :classification] = row.classification + 1
                end
                push!(dfs, track_df)
            end
        end
    end
    vcat(dfs...)
end

function create_mapping(df, segments)
    index_map = Dict{Int64,Union{Nothing,Int64}}()
    for segment in segments
        pos = searchsortedfirst(df.segment, segment)
        if (pos <= length(df.segment)) && (df.segment[pos] == segment)
            index_map[segment] = pos
        else
            index_map[segment] = nothing
        end
    end
    index_map
end
