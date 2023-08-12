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
| `sun_angle`        | `solar_elevation`              | Sun angle                                              | degrees above horizon              |
| `height_reference` | `digital_elevation_model`      | TanDEM-X elevation at GEDI footprint location          | m above the WGS 84 ellipsoid |

You can combine the output in a `DataFrame` with `reduce(vcat, DataFrame.(points(g)))` if you
want to change the default arguments or `DataFrame(g)` with the default options.

Data is `filtered` by default based on[^l3], except for the sensitivity field, which can be manually filtered to be above 0.9 and below or equal to 1.0 to match[^l3].

[^l3]: Dubayah, R. O., S. B. Luthcke, T. J. Sabaka, J. B. Nicholas, S. Preaux, and M. A. Hofton. 2021. “GEDI L3 Gridded Land Surface Metrics, Version 2.” ORNL DAAC, November. https://doi.org/10.3334/ORNLDAAC/1952.
"""

const t_offset = 1514764800  # Time delta since Jan 1 00:00 2018.

function points(
    granule::GEDI_Granule{:GEDI02_A};
    tracks = gedi_tracks,
    step = 1,
    bbox::Union{Nothing,Extent,NamedTuple} = nothing,
    ground = true,
    canopy = false,
    filtered = true,
)
    if bbox isa NamedTuple
        bbox = convert(Extent, bbox)
        Base.depwarn(
            "The `bbox` keyword argument as a NamedTuple will be deprecated in a future release " *
            "Please use `Extents.Extent` directly or use convert(Extent, bbox::NamedTuple)`.",
            :points,
        )
    end
    nts = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        for track in tracks
            if haskey(file, track)
                for track_nt ∈ points(granule, file, track, step, bbox, ground, canopy, filtered)
                    if !isempty(track_nt.height)
                        track_nt.height[track_nt.height.==fill_value] .= NaN
                    end
                    push!(nts, track_nt)
                end
            end
        end
    end
    nts
end

function points(
    ::GEDI_Granule{:GEDI02_A},
    file::HDF5.H5DataStore,
    track::AbstractString,
    step = 1,
    bbox::Union{Nothing,Extent} = nothing,
    ground = true,
    canopy = false,
    filtered = true,
)
    group = open_group(file, track)

    if !isnothing(bbox)
        # find data that falls withing bbox
        if ground
            x_grd = read_dataset(group, "lon_lowestmode")::Vector{Float64}
            y_grd = read_dataset(group, "lat_lowestmode")::Vector{Float64}

            ind = (x_grd .> bbox.X[1]) .& (y_grd .> bbox.Y[1]) .& (x_grd .< bbox.X[2]) .& (y_grd .< bbox.Y[2])
            start_grd = findfirst(ind)
            stop_grd = findlast(ind)
        end

        if canopy
            x_can = read_dataset(group, "lon_highestreturn")::Vector{Float64}
            y_can = read_dataset(group, "lat_highestreturn")::Vector{Float64}

            ind = (x_can .> bbox.X[1]) .& (y_can .> bbox.Y[1]) .& (x_can .< bbox.X[2]) .& (y_can .< bbox.Y[2])
            start_can = findfirst(ind)
            stop_can = findlast(ind)
        end

        if ground && canopy
            # take maximum extent between ground and canopy
            if isnothing(start_grd) && isnothing(start_can)
                start = start_grd
                stop = stop_grd
            else
                start = minimum([start_grd, start_can])
                stop = maximum([stop_grd, stop_can])
            end

        elseif ground
            start = start_grd
            stop = stop_grd
        elseif canopy
            start = start_can
            stop = stop_can
        end

        if isnothing(start)
            # no data found
            @warn "no data found within bbox of track $track in $(file.filename)"

            power = occursin("Full power", read_attribute(group, "description")::String)

            if canopy
                nt_canopy = (
                    longitude = Float32[],
                    latitude = Float32[],
                    height = Float32[],
                    height_error = Float32[],
                    datetime = Float64[],
                    intensity = Float32[],
                    sensitivity = Float32[],
                    surface = Bool[],
                    quality = Bool[],
                    nmodes = UInt8[],
                    track = Fill(track, 0),
                    strong_beam = Fill(power, 0),
                    classification = Fill("high_canopy", 0),
                    sun_angle = Float32[],
                    height_reference = Float32[],
                )
            end

            if ground
                nt_ground = (
                    longitude = Float32[],
                    latitude = Float32[],
                    height = Float32[],
                    height_error = Float32[],
                    datetime = Float64[],
                    intensity = Float32[],
                    sensitivity = Float32[],
                    surface = Bool[],
                    quality = Bool[],
                    nmodes = UInt8[],
                    track = Fill(track, 0),
                    strong_beam = Fill(power, 0),
                    classification = Fill("ground", 0),
                    sun_angle = Float32[],
                    height_reference = Float32[],
                )
            end

            if canopy && ground
                return nt_canopy, nt_ground
            elseif canopy
                return (nt_canopy,)
            elseif ground
                return (nt_ground,)
            else
                return ()
            end
        end

        # subset x/y_grd and x/y_can
        if ground && canopy
            x_grd = x_grd[start:step:stop]
            y_grd = y_grd[start:step:stop]

            x_can = x_can[start:step:stop]
            y_can = y_can[start:step:stop]

        elseif ground
            x_grd = x_grd[start:step:stop]
            y_grd = y_grd[start:step:stop]

        elseif canopy
            x_can = x_can[start:step:stop]
            y_can = y_can[start:step:stop]
        end
    else
        start = 1
        stop = length(open_dataset(group, "lon_highestreturn"))

        if ground
            x_grd = open_dataset(group, "lon_lowestmode")[start:step:stop]::Vector{Float64}
            y_grd = open_dataset(group, "lat_lowestmode")[start:step:stop]::Vector{Float64}
        end

        if canopy
            x_can = open_dataset(group, "lon_highestreturn")[start:step:stop]::Vector{Float64}
            y_can = open_dataset(group, "lat_highestreturn")[start:step:stop]::Vector{Float64}
        end
    end

    # now that we have the start and stop extents
    height_error = open_dataset(group, "elevation_bin0_error")[start:step:stop]::Vector{Float32}
    height_reference = open_dataset(group, "digital_elevation_model")[start:step:stop]::Vector{Float32}
    height_reference[height_reference.==-999999.0] .= NaN
    intensity = open_dataset(group, "energy_total")[start:step:stop]::Vector{Float32}
    aid = open_dataset(group, "selected_algorithm")[start:step:stop]::Vector{UInt8}

    if canopy
        height_can = open_dataset(group, "elev_highestreturn")[start:step:stop]::Vector{Float32}
        height_can[(height_can.<-1000.0).&(height_can.>25000.0)] .= NaN
    end

    if ground
        height_grd = open_dataset(group, "elev_lowestmode")[start:step:stop]::Vector{Float32}
        height_grd[(height_grd.<-1000.0).&(height_grd.>25000.0)] .= NaN
    end
    datetime = open_dataset(group, "delta_time")[start:step:stop]::Vector{Float64}

    # Quality
    quality = open_dataset(group, "quality_flag")[start:step:stop]::Vector{UInt8}
    rx_assess_quality_flag = open_dataset(group, "rx_assess/quality_flag")[start:step:stop]::Vector{UInt8}
    degrade_flag = open_dataset(group, "degrade_flag")[start:step:stop]::Vector{UInt8}
    stale_return_flag = open_dataset(group, "geolocation/stale_return_flag")[start:step:stop]::Vector{UInt8}
    surface_flag = open_dataset(group, "surface_flag")[start:step:stop]::Vector{UInt8}
    nmodes = open_dataset(group, "num_detectedmodes")[start:step:stop]::Vector{UInt8}

    rx_maxamp = open_dataset(group, "rx_assess/rx_maxamp")[start:step:stop]::Vector{Float32}
    sd_corrected = open_dataset(group, "rx_assess/sd_corrected")[start:step:stop]::Vector{Float32}
    rx_maxamp_f = rx_maxamp ./ sd_corrected

    # Algorithm
    zcross = similar(aid, Float32)
    toploc = similar(aid, Float32)
    algrun = similar(aid, Bool)
    for algorithm = 1:6
        am = aid .== algorithm
        zcross[am] = open_dataset(group, "rx_processing_a$algorithm/zcross")[start:step:stop][am]
        toploc[am] = open_dataset(group, "rx_processing_a$algorithm/toploc")[start:step:stop][am]
        algrun[am] =
            open_dataset(group, "rx_processing_a$algorithm/rx_algrunflag")[start:step:stop][am]
    end

    sensitivity = open_dataset(group, "sensitivity")[start:step:stop]::Vector{Float32}
    sun_angle = open_dataset(group, "solar_elevation")[start:step:stop]::Vector{Float32}
    power = occursin("Full power", read_attribute(group, "description")::String)

    # Quality flags as defined by [^l3]
    m = trues(length(quality))
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
    datetime = unix2datetime.(datetime .+ t_offset)

    if canopy
        nt_canopy = (
            longitude = x_can[m],
            latitude = y_can[m],
            height = height_can[m],
            height_error = height_error[m],
            datetime = datetime[m],
            intensity = intensity[m],
            sensitivity = sensitivity[m],
            surface = Bool.(surface_flag[m]),
            quality = Bool.(quality[m]),
            nmodes = nmodes[m],
            track = Fill(track, sum(m)),
            strong_beam = Fill(power, sum(m)),
            classification = Fill("high_canopy", sum(m)),
            sun_angle = sun_angle[m],
            height_reference = height_reference[m],
            # range = zarange[m]
        )
    end

    if ground
        nt_ground = (
            longitude = x_grd[m],
            latitude = y_grd[m],
            height = height_grd[m],
            height_error = height_error[m],
            datetime = datetime[m],
            intensity = intensity[m],
            sensitivity = sensitivity[m],
            surface = Bool.(surface_flag[m]),
            quality = Bool.(quality[m]),
            nmodes = nmodes[m],
            track = Fill(track, sum(m)),
            strong_beam = Fill(power, sum(m)),
            classification = Fill("ground", sum(m)),
            sun_angle = sun_angle[m],
            height_reference = height_reference[m],
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
    bbox::Union{Nothing,Extent,NamedTuple} = nothing,
    ground = true,
    canopy = false,
    filtered = true,
)
    if bbox isa NamedTuple
        bbox = convert(Extent, bbox)
        Base.depwarn(
            "The `bbox` keyword argument as a NamedTuple will be deprecated in a future release " *
            "Please use `Extents.Extent` directly or use convert(Extent, bbox::NamedTuple)`.",
            :points,
        )
    end
    nts = Vector{NamedTuple}()
    HDF5.h5open(granule.url, "r") do file
        for track in tracks
            if haskey(file, track)
                for track_df ∈ points(granule, file, track, step, bbox, ground, canopy, filtered)
                    line = Line(track_df.longitude, track_df.latitude, Float64.(track_df.height))
                    nt = (geom = line, track = track, strong_beam = track_df.strong_beam[1], granule = granule.id)
                    push!(nts, nt)
                end
            end
        end
    end
    nts
end

"""
    bounds(granule::GEDI_Granule)

Return the bounds of the GEDI granule.

!!! warning

    This opens the .h5 file to read all tracks, so it is very slow.
"""
function bounds(granule::GEDI_Granule)
    min_xs = Inf
    min_ys = Inf
    max_xs = -Inf
    max_ys = -Inf
    HDF5.h5open(granule.url, "r") do file
        for track ∈ gedi_tracks
            if haskey(file, track)
                group = open_dataset(file, track)
                min_x, max_x = extrema(open_dataset(group, "lon_lowestmode"))
                min_y, max_y = extrema(open_dataset(group, "lat_lowestmode"))
                min_xs = min(min_xs, min_x)
                min_ys = min(min_ys, min_y)
                max_xs = max(max_xs, max_x)
                max_ys = max(max_ys, max_y)
            end
        end
        ntb = (
            min_x = min_xs,
            min_y = min_ys,
            max_x = max_xs,
            max_y = max_ys,
        )
    end
end
