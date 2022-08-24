function points(
    granule::ICESat2_Granule{:ATL06};
    tracks = icesat2_tracks,
    step = 1,
)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        t_offset = read(file, "ancillary_data/atlas_sdp_gps_epoch")[1]::Float64 + gps_offset
        orientation = read(file, "orbit_info/sc_orient")[1]::Int8

        for (i, track) in enumerate(tracks)
            power = track_power(orientation, track)
            if in(track, keys(file)) && in("land_ice_segments", keys(file[track]))
                track_nt = points(granule, file, track, power, t_offset, step)
                track_nt.z[track_nt.z.==fill_value] .= NaN
                push!(dfs, track_nt)
            end
        end
    end
    return dfs
end

function points(
    ::ICESat2_Granule{:ATL06},
    file::HDF5.H5DataStore,
    track::AbstractString,
    power::AbstractString,
    t_offset::Float64,
    step = 1,
)
    z = file["$track/land_ice_segments/h_li"][1:step:end]::Vector{Float32}
    zu = file["$track/land_ice_segments/h_li_sigma"][1:step:end]::Vector{Float32}
    x = file["$track/land_ice_segments/longitude"][1:step:end]::Vector{Float64}
    y = file["$track/land_ice_segments/latitude"][1:step:end]::Vector{Float64}
    t = file["$track/land_ice_segments/delta_time"][1:step:end]::Vector{Float64}
    q = file["$track/land_ice_segments/atl06_quality_summary"][1:step:end]::Vector{Int8}
    dem = file["$track/land_ice_segments/dem/dem_h"][1:step:end]::Vector{Float32}
    times = unix2datetime.(t .+ t_offset)

    nt = (;
        x = x,
        y = y,
        z = z,
        u = zu,
        t = times,
        q = q,
        track = Fill(track, length(times)),
        power = Fill(power, length(times)),
        reference = dem,
    )
    return nt
end
