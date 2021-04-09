const t_offset = 1514764800  # Time delta since Jan 1 00:00 2018.

function bounds(::GEDI_Granule)
    (min_x = -180., max_x = 180., min_y = -63., max_y = 63., min_z = -1000., max_z = 25000.)
end

function xyz(granule::GEDI_Granule{:GEDI02_A}; tracks=gedi_tracks, step=1, ground=true, canopy=false, quality=nothing)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file

        for (i, track) ∈ enumerate(tracks)
            power = i > 4 ? "strong" : "weak"
            if in(track, keys(file))
                for track_df ∈ xyz(granule, file, track, power, step, ground, canopy, quality)
                    push!(dfs, track_df)
                end
            end
        end
    end
    dfs
end

function points(granule::GEDI_Granule{:GEDI02_A})
    xyz(granule, canopy=true, quality=1)
end

function xyz(g::GEDI_Granule{:GEDI02_A}, file, track, power, step, ground, canopy, quality::Union{Nothing,Integer}=1, degraded=false, )
    zu = file["$track/elevation_bin0_error"][1:step:end]::Array{Float32,1}
    dem = file["$track/digital_elevation_model"][1:step:end]::Array{Float32,1}
    if canopy
        xt = file["$track/lon_highestreturn"][1:step:end]::Array{Float64,1}
        yt = file["$track/lat_highestreturn"][1:step:end]::Array{Float64,1}
        zt = file["$track/elev_highestreturn"][1:step:end]::Array{Float32,1}
        zt[(zt .< -1000.0) .& (zt .> 25000.0)] .= NaN
    end
    if ground
        xb = file["$track/lon_lowestmode"][1:step:end]::Array{Float64,1}
        yb = file["$track/lat_lowestmode"][1:step:end]::Array{Float64,1}
        zb = file["$track/elev_lowestmode"][1:step:end]::Array{Float32,1}
        zb[(zb .< -1000.0) .& (zb .> 25000.0)] .= NaN
    end
    t = file["$track/delta_time"][1:step:end]::Array{Float64,1}
    q = file["$track/quality_flag"][1:step:end]::Array{UInt8,1}
    d = file["$track/degrade_flag"][1:step:end]::Array{UInt8,1}
    s = file["$track/surface_flag"][1:step:end]::Array{UInt8,1}
    zs = file["$track/sensitivity"][1:step:end]::Array{Float32,1}
    sun_angle = file["$track/solar_elevation"][1:step:end]::Array{Float32,1}

    if isnothing(quality)
        m = trues(length(q))
    else
        m = q .== quality
    end

    # Ignore degraded
    m .&= d .== 0

    times = unix2datetime.(t .+ t_offset)

    if canopy
        nt_canopy = (
            x = xt[m],
            y = yt[m],
            z = zt[m],
            u = zu[m],
            sensitivity = zs[m],
            t = times[m],
            surface = Bool.(s[m]),
            quality = Bool.(q[m]),
            track = Fill(track, length(q))[m],
            power = Fill(power, length(q))[m],
            classification = Fill("high_vegetation", length(q))[m],
            sun_angle = sun_angle[m],
            return_number = Fill(1, length(sun_angle))[m],
            number_of_returns = Fill(2, length(sun_angle))[m],
            reference = dem
        )
    end
    if ground
        nt_ground = (
            x = xb[m],
            y = yb[m],
            z = zb[m],
            u = zu[m],
            sensitivity = zs[m],
            t = times[m],
            surface = Bool.(s[m]),
            quality = Bool.(q[m]),
            track = Fill(track, length(q))[m],
            power = Fill(power, length(q))[m],
            classification = Fill("ground", length(q))[m],
            sun_angle = sun_angle[m],
            return_number = Fill(2, length(sun_angle))[m],
            number_of_returns = Fill(2, length(sun_angle))[m],
            reference = dem
        )
    end
    if canopy && ground
        nt_canopy, nt_ground
    elseif canopy
        (nt_canopy,)
    elseif ground
        (nt_ground,)
    else
        ()
    end
end


function lines(granule::GEDI_Granule{:GEDI02_A}; tracks=gedi_tracks, step=1, ground=true, canopy=false, quality=nothing)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        for (i, track) ∈ enumerate(tracks)
            power = i > 4 ? "strong" : "weak"
            if in(track, keys(file))
                for track_df ∈ xyz(granule, file, track, power, step, ground, canopy, quality)
                    line = makeline(track_df.x, track_df.y, track_df.z)
                    nt = (geom = line, track = track, power = power, granule = granule.id)
                    push!(dfs, nt)
                end
            end
        end
    end
    dfs
end
