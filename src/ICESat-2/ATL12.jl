
function xyz(granule::ICESat2_Granule{:ATL12}, bbox=nothing, tracks=icesat2_tracks)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1] + gps_offset
        orientation = read(file, "orbit_info/sc_orient")[1]

        for track ∈ tracks
            power = track_power(orientation, track)
            if in(track, keys(file)) && in("ssh_segments", keys(file[track])) && in("heights", keys(file[track]["ssh_segments"]))
                track_df = xyz(granule, file, track, power, t_offset)
                push!(dfs, track_df)
            end
        end
    end
    dfs
end

function xyz(::ICESat2_Granule{:ATL12}, file::HDF5.H5DataStore, track::AbstractString, power::AbstractString, t_offset::Real)
    z = read(file, "$track/ssh_segments/heights/h")
    x = read(file, "$track/ssh_segments/longitude")
    y = read(file, "$track/ssh_segments/latitude")
    t = read(file, "$track/ssh_segments/delta_time")

    times = unix2datetime.(t .+ t_offset)

    (x=x, y=y, z=z, t=times, track=Fill(track, length(times)), power=Fill(power, length(times)))
end
