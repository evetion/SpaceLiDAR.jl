function xyz(granule::ICESat2_Granule{:ATL03}; bbox=nothing, tracks=icesat2_tracks, step=1)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset
        orientation = read(file, "orbit_info/sc_orient")[1]::Int8

        for track ∈ tracks
            power = track_power(orientation, track)
            if in(track, keys(file)) && in("heights", keys(file[track]))
                track_df = xyz(granule, file, track, power, t_offset, step)
                push!(dfs, track_df)
            end
        end
    end
    for df in dfs
        df.z[df.z .== fill_value] .= NaN
    end
    dfs
end

function lines(granule::ICESat2_Granule{:ATL03}; tracks=icesat2_tracks, step=100)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset
        orientation = read(file, "orbit_info/sc_orient")[1]::Int8

        for track ∈ tracks
            power = track_power(orientation, track)
            if in(track, keys(file)) && in("heights", keys(file[track]))
                track_df = xyz(granule, file, track, power, t_offset, step)
                line = makeline(track_df.x, track_df.y, track_df.z)
                i = div(length(track_df.t), 2) + 1
                nt = (geom = line, sun_angle = Float64(track_df.sun_angle[i]), track = track, power = power, t = track_df.t[i], granule = granule.id)
                push!(dfs, nt)
            end
        end
    end
    dfs
end

function xyz(::ICESat2_Granule{:ATL03}, file::HDF5.H5DataStore, track::AbstractString, power::AbstractString, t_offset::Float64, step=1)
    z = file["$track/heights/h_ph"][1:step:end]::Array{Float32,1}
    x = file["$track/heights/lon_ph"][1:step:end]::Array{Float64,1}
    y = file["$track/heights/lat_ph"][1:step:end]::Array{Float64,1}
    t = file["$track/heights/delta_time"][1:step:end]::Array{Float64,1}
    c = file["$track/heights/signal_conf_ph"][1,1:step:end]::Array{Int8,1}

    # Segment calc
    segment = read(file, "$track/geolocation/segment_id")::Array{Int32,1}
    sun_angle = read(file, "$track/geolocation/solar_elevation")::Array{Float32,1}
    u = read(file, "$track/geolocation/sigma_h")::Array{Float32,1}
    segment_counts = read(file, "$track/geolocation/segment_ph_cnt")::Array{Int32,1}
    segments = map_counts(segment, segment_counts)[1:step:end]
    sun_angles = map_counts(sun_angle, segment_counts)[1:step:end]
    uu = map_counts(u, segment_counts)[1:step:end]

    times = unix2datetime.(t .+ t_offset)

    (x = x, y = y, z = z, u = uu, t = times, confidence = c, segment = segments, track = Fill(track, length(sun_angles)), power = Fill(power, length(sun_angles)), sun_angle = sun_angles)
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

function points(granule::ICESat2_Granule{:ATL03})
    classify(granule)
end

"""Retrieve all points as classified as ground in ATL08."""
function classify(granule::ICESat2_Granule{:ATL03}, atl08::Union{ICESat2_Granule{:ATL08},Nothing}=nothing; tracks=icesat2_tracks)
    if isnothing(atl08)
        atl08 = convert(:ATL08, granule)
    end

    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset
        orientation = read(file, "orbit_info/sc_orient")[1]::Int8

        for track ∈ tracks
            power = track_power(orientation, track)
            if in(track, keys(file)) && in("heights", keys(file[track]))
                track_df = xyz(granule, file, track, power, t_offset)

                mapping = atl03_mapping(atl08, track)

                unique_segments = unique(mapping.segment)
                index_map = create_mapping(track_df.segment, unique_segments)

                class = fill("unclassified", length(track_df.x))
                for i in 1:length(mapping.segment)
                    index = get(index_map, mapping.segment[i], nothing)
                    isnothing(index) && continue
                    offset = mapping.index[i] - 1
                    class[index + offset] = classification[mapping.classification[i] + 1]
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
