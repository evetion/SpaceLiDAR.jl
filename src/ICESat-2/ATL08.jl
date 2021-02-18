function xyz(granule::ICESat2_Granule{:ATL08}; tracks=icesat2_tracks, step=1)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset
        orientation = read(file, "orbit_info/sc_orient")[1]::Int8

        for track ∈ tracks
            power = track_power(orientation, track)
            if in(track, keys(file)) && in("land_segments", keys(file[track]))
                for track_nt ∈ xyz(granule, file, track, power, t_offset, step)
                    push!(dfs, track_nt)
                end
            end
        end
    end
    for df in dfs
        df.z[df.z .== fill_value] .= NaN
    end
    dfs
end

function xyz(::ICESat2_Granule{:ATL08}, file::HDF5.H5DataStore, track::AbstractString, power::AbstractString, t_offset::Real, step=1)
    zt = file["$track/land_segments/terrain/h_te_median"][1:step:end]::Array{Float32,1}
    zc = file["$track/land_segments/canopy/h_median_canopy_abs"][1:step:end]::Array{Float32,1}
    x = file["$track/land_segments/longitude"][1:step:end]::Array{Float32,1}
    y = file["$track/land_segments/latitude"][1:step:end]::Array{Float32,1}
    t = file["$track/land_segments/delta_time"][1:step:end]::Array{Float64,1}
    times = unix2datetime.(t .+ t_offset)

    gt = (x = x, y = y, z = zt, t = times, track = Fill(track, length(times)), power = Fill(power, length(times)), classification = Fill("ground", length(times)), return_number = Fill(2, length(times)), number_of_returns = Fill(2, length(times)))
    ct = (x = x, y = y, z = zt, t = times, track = Fill(track, length(times)), power = Fill(power, length(times)), classification = Fill("high_vegetation", length(times)), return_number = Fill(1, length(times)), number_of_returns = Fill(2, length(times)))
    gt, ct
end

function lines(granule::ICESat2_Granule{:ATL08}; tracks=icesat2_tracks, step=100, quality=1)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset
        orientation = read(file, "orbit_info/sc_orient")[1]::Int8

        for track ∈ tracks
            power = track_power(orientation, track)
            if in(track, keys(file)) && in("land_segments", keys(file[track]))
                z = file["$track/land_segments/terrain/h_te_median"][1:step:end]::Array{Float32,1}
                x = file["$track/land_segments/longitude"][1:step:end]::Array{Float32,1}
                y = file["$track/land_segments/latitude"][1:step:end]::Array{Float32,1}
                t = file["$track/land_segments/delta_time"][1:step:end]::Array{Float64,1}
                times = unix2datetime.(t .+ t_offset)
                line = makeline(x, y, z)
                i = div(length(t), 2) + 1
                nt = (geom = line, track = track, power = power, t = times[i], granule = granule.id)
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
