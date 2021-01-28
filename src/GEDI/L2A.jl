const t_offset = 1514764800  # Time delta since Jan 1 00:00 2018.


function xyz(granule::GEDI_Granule{:GEDI02A}; tracks=gedi_tracks, step=1)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file

        for (i, track) ∈ enumerate(tracks)
            power = i > 4 ? "strong" : "weak"
            if in(track, keys(file))
                for track_df ∈ xyz(granule, file, track, power, t_offset, step)
                    push!(dfs, track_df)
                end
            end
        end
    end
    dfs
end

function xyz(::GEDI_Granule{:GEDI02A}, file, track, power, t_offset, step)
    zt = file["$track/elev_highestreturn"][1:step:end]::Array{Float32,1}
    zb = file["$track/elev_lowestmode"][1:step:end]::Array{Float32,1}
    xt = file["$track/lon_highestreturn"][1:step:end]::Array{Float64,1}
    xb = file["$track/lon_lowestmode"][1:step:end]::Array{Float64,1}
    yt = file["$track/lat_highestreturn"][1:step:end]::Array{Float64,1}
    yb = file["$track/lat_lowestmode"][1:step:end]::Array{Float64,1}
    t = file["$track/delta_time"][1:step:end]::Array{Float64,1}
    q = file["$track/quality_flag"][1:step:end]::Array{UInt8,1}
    sun_angle = file["$track/solar_elevation"][1:step:end]::Array{Float32,1}

    times = unix2datetime.(t .+ t_offset)

    nt_canopy = (x=xt, y=yt, z=zt, t=times, quality=q, track=Fill(track, length(q)), power=Fill(power, length(q)), classification=Fill("canopy", length(q)), sun_angle=sun_angle, return_number=Fill(1, length(sun_angle)), number_of_returns=Fill(2, length(sun_angle)))
    nt_ground = (x=xb, y=yb, z=zb, t=times, quality=q, track=Fill(track, length(q)), power=Fill(power, length(q)), classification=Fill("ground", length(q)), sun_angle=sun_angle, return_number=Fill(2, length(sun_angle)), number_of_returns=Fill(2, length(sun_angle)))
    nt_canopy, nt_ground
end


function lines(granule::GEDI_Granule{:GEDI02A}; tracks=gedi_tracks, step=1)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file

        for (i, track) ∈ enumerate(tracks)
            power = i > 4 ? "strong" : "weak"
            if in(track, keys(file))
                for track_df ∈ xyz(granule, file, track, power, t_offset, step)
                    line = makeline(track_df.x, track_df.y, track_df.z)
                    halfway = div(length(track_df.t), 2) + 1
                    nt = (geom=line, sun_angle=Float64(track_df.sun_angle[halfway]), track=track, power=power, t=track_df.t[halfway], granule=granule.id)
                    push!(dfs, nt)
                end
            end
        end
    end
    dfs
end
