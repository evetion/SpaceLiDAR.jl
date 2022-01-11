const t_offset = 1514764800  # Time delta since Jan 1 00:00 2018.

function bounds(::GEDI_Granule)
    (min_x = -180., max_x = 180., min_y = -63., max_y = 63., min_z = -1000., max_z = 25000.)
end

function points(granule::GEDI_Granule{:GEDI02_A}; tracks=gedi_tracks, step=1, ground=true, canopy=false, quality=1)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file

        for (i, track) ∈ enumerate(tracks)
            power = i > 4 ? "strong" : "weak"
            if in(track, keys(file))
                for track_df ∈ points(granule, file, track, power, step, ground, canopy, quality)
                    push!(dfs, track_df)
                end
            end
        end
    end
    dfs
end


function points(g::GEDI_Granule{:GEDI02_A}, file, track, power, step, ground, canopy, quality::Union{Nothing,Integer}=1, degraded=false)
    zu = file["$track/elevation_bin0_error"][1:step:end]::Vector{Float32}
    dem = file["$track/digital_elevation_model"][1:step:end]::Vector{Float32}
    intensity = file["$track/energy_total"][1:step:end]::Vector{Float32}
    aid = file["$track/selected_algorithm"][1:step:end]::Vector{UInt8}

    if canopy
        xt = file["$track/lon_highestreturn"][1:step:end]::Vector{Float64}
        yt = file["$track/lat_highestreturn"][1:step:end]::Vector{Float64}
        zt = file["$track/elev_highestreturn"][1:step:end]::Vector{Float32}
        zt[(zt .< -1000.0) .& (zt .> 25000.0)] .= NaN
    end
    if ground
        xb = file["$track/lon_lowestmode"][1:step:end]::Vector{Float64}
        yb = file["$track/lat_lowestmode"][1:step:end]::Vector{Float64}
        zb = file["$track/elev_lowestmode"][1:step:end]::Vector{Float32}
        # zzb = similar(aid, Float32)
        # for algorithm in 1:6
            # zzb[aid .== algorithm] = file["$track/geolocation/elev_lowestreturn_a$algorithm"][1:step:end][aid .== algorithm]
        # end
        zb[(zb .< -1000.0) .& (zb .> 25000.0)] .= NaN
        # zzb[(zb .< -1000.0) .& (zb .> 25000.0)] .= NaN
    end
    t = file["$track/delta_time"][1:step:end]::Vector{Float64}

    # Quality
    q = file["$track/quality_flag"][1:step:end]::Vector{UInt8}
    aq = file["$track/rx_assess/quality_flag"][1:step:end]::Vector{UInt8}
    d = file["$track/degrade_flag"][1:step:end]::Vector{UInt8}
    stale = file["$track/geolocation/stale_return_flag"][1:step:end]::Vector{UInt8}
    s = file["$track/surface_flag"][1:step:end]::Vector{UInt8}

    minel, maxel = zeros(size(s)), zeros(size(s))
    for algorithm in 1:6
        z = file["$track/geolocation/elev_lowestmode_a$algorithm"][1:step:end]::Vector{Float32}
        minel .= min.(minel, z)
        maxel .= max.(maxel, z)
    end
    zarange = maxel .- minel

    a = file["$track/rx_assess/rx_maxamp"][1:step:end]::Vector{Float32}
    sd = file["$track/rx_assess/sd_corrected"][1:step:end]::Vector{Float32}
    f = a ./ sd

    # # Algorithm
    zcross = similar(aid, Float32)
    toploc = similar(aid, Float32)
    for algorithm in 1:6
        zcross[aid .== algorithm] = file["$track/rx_processing_a$algorithm/zcross"][1:step:end][aid .== algorithm]
        toploc[aid .== algorithm] = file["$track/rx_processing_a$algorithm/toploc"][1:step:end][aid .== algorithm]
    end

    zs = file["$track/sensitivity"][1:step:end]::Vector{Float32}
    sun_angle = file["$track/solar_elevation"][1:step:end]::Vector{Float32}
    if isnothing(quality)
        m = trues(length(q))
    else
        m = q .== quality
    end

    # Ignore degraded
    m .&= d .== 0
    m .&= aq .!= 0
    m .&= stale .== 0
    m .&= f .>= 4
    m .&= zcross .> 0
    m .&= toploc .> 0
    m .&= zarange .<= 2
    # # Ignore values outside of 300m of reference surface
    m .&= s .!= 0

    times = unix2datetime.(t .+ t_offset)

    if canopy
        nt_canopy = (
            x = xt[m],
            y = yt[m],
            z = zt[m],
            # zl = zt[m],
            u = zu[m],
            intensity = intensity[m],
            sensitivity = zs[m],
            t = times[m],
            surface = Bool.(s[m]),
            quality = Bool.(q[m]),
            track = Fill(track, length(q))[m],
            power = Fill(power, length(q))[m],
            classification = Fill("high_canopy", length(q))[m],
            sun_angle = sun_angle[m],
            return_number = Fill(1, length(sun_angle))[m],
            number_of_returns = Fill(2, length(sun_angle))[m],
            reference = dem[m],
            # range = zarange[m]
        )
    end
    if ground
        nt_ground = (
            x = xb[m],
            y = yb[m],
            z = zb[m],
            # zl = zzb[m],
            u = zu[m],
            intensity = intensity[m],
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
            reference = dem[m],
            # range = zarange[m]
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
                for track_df ∈ points(granule, file, track, power, step, ground, canopy, quality)
                    line = makeline(track_df.x, track_df.y, track_df.z)
                    nt = (geom = line, track = track, power = power, granule = granule.id)
                    push!(dfs, nt)
                end
            end
        end
    end
    dfs
end
