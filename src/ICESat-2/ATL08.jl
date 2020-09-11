

function xyz(granule::ICESat2_Granule{:ATL08}, tracks=icesat2_tracks)
    df = DataFrame()
    HDF5.h5open(granule.url, "r") do file

        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1] + gps_offset

        for track ∈ tracks
            if in(track, names(file)) && in("land_segments", names(file[track]))
                z = read(file, "$track/land_segments/terrain/h_te_median")
                x = read(file, "$track/land_segments/longitude")
                y = read(file, "$track/land_segments/latitude")
                t = read(file, "$track/land_segments/delta_time")
                times = unix2datetime.(t .+ t_offset)

                df = vcat(df, DataFrame(x=x, y=y, z=z, t=times, track=track))
            end
        end
    end
    df
end

function atl03_mapping(granule::ICESat2_Granule{:ATL08})
    dfs = Vector{DataFrame}()
    HDF5.h5open(granule.url, "r") do file
        for track ∈ icesat2_tracks
            if in(track, names(file)) && in("signal_photons", names(file[track]))
                df = atl03_mapping(file, track)
                push!(dfs, df)
            end
        end
    end
    vcat(dfs...)
end

function atl03_mapping(granule::ICESat2_Granule{:ATL08}, track::AbstractString)
    HDF5.h5open(granule.url, "r") do file
        if in(track, names(file)) && in("signal_photons", names(file[track]))
            df = atl03_mapping(file, track)
        end
    end
end

function atl03_mapping(file::HDF5.HDF5File, track::AbstractString)
    c = read(file, "$track/signal_photons/classed_pc_flag")
    i = read(file, "$track/signal_photons/classed_pc_indx")
    s = read(file, "$track/signal_photons/ph_segment_id")
    DataFrame(segment=s, index=i, classification=c, track=track)
end
