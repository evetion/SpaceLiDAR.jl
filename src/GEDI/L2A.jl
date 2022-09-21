const t_offset = 1514764800  # Time delta since Jan 1 00:00 2018.

function bounds(::GEDI_Granule)
    (min_x = -180.0, max_x = 180.0, min_y = -63.0, max_y = 63.0, min_z = -1000.0, max_z = 25000.0)
end

"""
    points(g::GEDI_Granule{:GEDI02_A}; tracks=gedi_tracks, step=1, canopy=false, ground=true, filtered=true)

Retrieve the points for a given GEDI Level 2A (Geolocated Elevation and Height Metrics) granule as a list of namedtuples, one for each beam.
The names of the tuples are based on the following fields:

| Column             | Field                          | Description                                            | Units                        |
|:------------------ |:------------------------------ |:------------------------------------------------------ |:---------------------------- |
| `longitude`        | `lon_lowestmode`               | Longitude of center, WGS84, East=+                     | decimal degrees              |
| `latitude`         | `lat_lowestmode`               | Latitude of center, WGS84, North=+                     | decimal degrees              |
| `height`           | `elev_lowestmode`              | Standard land-ice segment height                       | m above the WGS 84 ellipsoid |
| `height_error`     | `elevation_bin0_error`         | Error in elevation of bin 0                            | m                            |
| `datetime`         | `delta_time`                   | + `ancillary_data/atlas_sdp_gps_epoch` + `gps_offset`  | date-time                    |
| `quality`          | `quality_flag`                 | Flag simpilfying selection of most useful data         | 1 = high quality             |
| `surface`          | `surface_flag`                 | Indicates elev_lowestmode is within 300m of DEM or MSS | 1 = high quality             |
| `nmodes`           | `num_detectedmodes`            | Number of detected modes in rxwaveform                 | -                            |
| `intensity`        | `energy_total`                 | Integrated counts in the return waveform               | -                            |
| `sensitivity`      | `sensitivity`                  | Maxmimum canopy cover that can be penetrated           | -                            |
| `track`            | `BEAM0000` - `BEAM1011` groups | -                                                      | -                            |
| `strong_beam`      | `-`                            | "strong" (true) or "weak" (false) laser power          | -                            |
| `classification`   | `-`                            | "ground", "high_canopy"                                | -                            |
| `sun_angle`        | `solar_elevation`              | Sun angle                                              | ° above horizon              |
| `height_reference` | `digital_elevation_model`      | TanDEM-X elevation at GEDI footprint location          | m above the WGS 84 ellipsoid |

You can combine the output in a `DataFrame` with `reduce(vcat, DataFrame.(points(g)))` if you
want to change the default arguments or `DataFrame(g)` with the default options.

Data is `filtered` by default based on [^l3], except for the sensitivity field, which can be manually filtered to be above 0.9 and below or equal to 1.

[^l3]: Dubayah, R. O., S. B. Luthcke, T. J. Sabaka, J. B. Nicholas, S. Preaux, and M. A. Hofton. 2021. “GEDI L3 Gridded Land Surface Metrics, Version 2.” ORNL DAAC, November. https://doi.org/10.3334/ORNLDAAC/1952.
"""
function points(
    granule::GEDI_Granule{:GEDI02_A};
    tracks = gedi_tracks,
    step = 1,
    ground = true,
    canopy = false,
    filtered = true,
)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file

        for (i, track) ∈ enumerate(tracks)
            if in(track, keys(file))
                for track_dfs ∈ points(granule, file, track, step, ground, canopy, filtered)
                    push!(dfs, track_dfs)
                end
            end
        end
    end
    dfs
end


function points(
    ::GEDI_Granule{:GEDI02_A},
    file,
    track,
    step,
    ground,
    canopy,
    filtered,
)
    zu = file["$track/elevation_bin0_error"][1:step:end]::Vector{Float32}
    dem = file["$track/digital_elevation_model"][1:step:end]::Vector{Float32}
    dem[dem.==-999999.0] .= NaN
    intensity = file["$track/energy_total"][1:step:end]::Vector{Float32}
    aid = file["$track/selected_algorithm"][1:step:end]::Vector{UInt8}

    if canopy
        xt = file["$track/lon_highestreturn"][1:step:end]::Vector{Float64}
        yt = file["$track/lat_highestreturn"][1:step:end]::Vector{Float64}
        zt = file["$track/elev_highestreturn"][1:step:end]::Vector{Float32}
        zt[(zt.<-1000.0).&(zt.>25000.0)] .= NaN
    end
    if ground
        xb = file["$track/lon_lowestmode"][1:step:end]::Vector{Float64}
        yb = file["$track/lat_lowestmode"][1:step:end]::Vector{Float64}
        zb = file["$track/elev_lowestmode"][1:step:end]::Vector{Float32}
        zb[(zb.<-1000.0).&(zb.>25000.0)] .= NaN
        # zzb = similar(aid, Float32)
        # for algorithm in 1:6
        # zzb[aid .== algorithm] = file["$track/geolocation/elev_lowestreturn_a$algorithm"][1:step:end][aid .== algorithm]
        # end
        # zzb[(zb .< -1000.0) .& (zb .> 25000.0)] .= NaN
    end
    t = file["$track/delta_time"][1:step:end]::Vector{Float64}

    # Quality
    q = file["$track/quality_flag"][1:step:end]::Vector{UInt8}
    rx_assess_quality_flag = file["$track/rx_assess/quality_flag"][1:step:end]::Vector{UInt8}
    degrade_flag = file["$track/degrade_flag"][1:step:end]::Vector{UInt8}
    stale_return_flag = file["$track/geolocation/stale_return_flag"][1:step:end]::Vector{UInt8}
    surface_flag = file["$track/surface_flag"][1:step:end]::Vector{UInt8}
    nmodes = file["$track/num_detectedmodes"][1:step:end]::Vector{UInt8}

    # Track differences between different algorithms
    # minel, maxel = zeros(size(s)), zeros(size(s))
    # for algorithm = 1:6
    #     z = file["$track/geolocation/elev_lowestmode_a$algorithm"][1:step:end]::Vector{Float32}
    #     minel .= min.(minel, z)
    #     maxel .= max.(maxel, z)
    # end
    # zarange = maxel .- minel

    rx_maxamp = file["$track/rx_assess/rx_maxamp"][1:step:end]::Vector{Float32}
    sd_corrected = file["$track/rx_assess/sd_corrected"][1:step:end]::Vector{Float32}
    rx_maxamp_f = rx_maxamp ./ sd_corrected

    # # Algorithm
    zcross = similar(aid, Float32)
    toploc = similar(aid, Float32)
    algrun = similar(aid, Bool)
    for algorithm = 1:6
        zcross[aid.==algorithm] = file["$track/rx_processing_a$algorithm/zcross"][1:step:end][aid.==algorithm]
        toploc[aid.==algorithm] = file["$track/rx_processing_a$algorithm/toploc"][1:step:end][aid.==algorithm]
        algrun[aid.==algorithm] = file["$track/rx_processing_a$algorithm/rx_algrunflag"][1:step:end][aid.==algorithm]
    end

    sensitivity = file["$track/sensitivity"][1:step:end]::Vector{Float32}
    sun_angle = file["$track/solar_elevation"][1:step:end]::Vector{Float32}

    power = occursin("Full power", attrs(file["$track"])["description"]::String)

    # Quality flags as defined by [^1]
    m = trues(length(q))
    if filtered
        m .&= rx_assess_quality_flag .!= 0
        m .&= surface_flag .!= 0
        m .&= stale_return_flag .== 0
        m .&= rx_maxamp_f .>= 8
        # m .& (1 .> sensitivity .> 0.9)
        m .& algrun .!= 0
        m .&= zcross .> 0
        m .&= toploc .> 0
        m .&= degrade_flag .== 0
        # m .&= zarange .<= 2
    end
    times = unix2datetime.(t .+ t_offset)

    if canopy
        nt_canopy = (
            longitude = xt[m],
            latitude = yt[m],
            height = zt[m],
            height_error = zu[m],
            datetime = times[m],
            intensity = intensity[m],
            sensitivity = sensitivity[m],
            surface = Bool.(surface_flag[m]),
            quality = Bool.(q[m]),
            nmodes = nmodes[m],
            track = Fill(track, sum(m)),
            strong_beam = Fill(power, sum(m)),
            classification = Fill("high_canopy", sum(m)),
            sun_angle = sun_angle[m],
            height_reference = dem[m],
            # range = zarange[m]
        )
    end
    if ground
        nt_ground = (
            longitude = xb[m],
            latitude = yb[m],
            height = zb[m],
            height_error = zu[m],
            datetime = times[m],
            intensity = intensity[m],
            sensitivity = sensitivity[m],
            surface = Bool.(surface_flag[m]),
            quality = Bool.(q[m]),
            nmodes = nmodes[m],
            track = Fill(track, sum(m)),
            strong_beam = Fill(power, sum(m)),
            classification = Fill("ground", sum(m)),
            sun_angle = sun_angle[m],
            height_reference = dem[m],
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


function lines(
    granule::GEDI_Granule{:GEDI02_A};
    tracks = gedi_tracks,
    step = 1,
    ground = true,
    canopy = false,
    filtered = true,
)
    dfs = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        for track in tracks
            if in(track, keys(file))
                for track_df ∈ points(granule, file, track, step, ground, canopy, filtered)
                    line = Line(track_df.longitude, track_df.latitude, Float64.(track_df.height))
                    nt = (geom = line, track = track, strong_beam = track_df.strong_beam[1], granule = granule.id)
                    push!(dfs, nt)
                end
            end
        end
    end
    dfs
end
