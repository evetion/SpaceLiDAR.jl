"""
    points(g::ICESat_Granule{:GLAH14}, step=1, bbox::Union{Nothing,NamedTuple{}} = nothing)

Retrieve the points for a given ICESat GLAH14 (Land Surface) granule as a list of namedtuples
The names of the tuples are based on the following fields:

| Variable           | Original Field (in `Data_40HZ`) | Description                                 | Units                        |
|:------------------ |:------------------------------- |:------------------------------------------- |:---------------------------- |
| `longitude`        | `/Geolocation/d_lon`            | Longitude of segment center, WGS84, East=+  | decimal degrees              |
| `latitude`         | `Geolocation/d_lat`             | Latitude of segment center, WGS84, North=+  | decimal degrees              |
| `height`           | `Elevation_Surfaces/d_elev`     | + `Elevation_Corrections/d_satElevCorr`     | valid above WGS84 ellipsoid      |
| `datetime`         | `DS_UTCTime_40`                 | Precise time of aquisiton                   | date-time                    |
| `quality` [^1]     | `Quality/elev_use_flg`          | & `Quality/sigma_att_flg` = 0               |                              |
|                    | & `Waveform/i_numPk` = 1        | & `Elevation_Corrections/d_satElevCorr` < 3 | 1=high quality               |
| `clouds`           | `Elevation_Flags/elv_cloud_flg` | Cloud contamination                         | -                            |
| `height_reference` | `Geophysical/d_DEM_elv`         | Height of the (best available) DEM          | height above WGS84           |
| `gain`             | `Waveform/i_gval_rcv`           | Gain value used for received pulse.         | -                            |
| `reflectivity`     | `Reflectivity/d_reflctUC`       | Reflectivity, not corrected                 | -                            |
| `attitude`         | `Quality/sigma_att_flg`         | Attitude quality indicator                  | 0=good; 50=warning; 100=bad; |
| `saturation`       | `Quality/sat_corr_flg`          | Saturation Correction Flag                  | 0=not_saturated;             |

You can get the output in a `DataFrame` with `DataFrame(points(g))`.

[^1]: Smith, B., Fricker, H. A., Gardner, A. S., Medley, B., Nilsson, J., Paolo, F. S., ... & Zwally, H. J. (2020). Pervasive ice sheet mass loss reflects competing ocean and atmosphere processes. Science, 368(6496), 1239-1242.
"""
function points(
    granule::ICESat_Granule{:GLAH14}; 
    step = 1,
    bbox::Union{Nothing,NamedTuple{}} = nothing
    )

    HDF5.h5open(granule.url, "r") do file
        if !isnothing(bbox)
            x = file["Data_40HZ/Geolocation/d_lon"][:]::Vector{Float64}
            x[x.>180] .= x[x.>180] .- 360.0  # translate from 0 - 360
            y = file["Data_40HZ/Geolocation/d_lat"][:]::Vector{Float64}

            # find index of points inside of bbox
            ind = (x .> bbox.min_x) .& (y .> bbox.min_y) .& (x .< bbox.max_x) .& (y .< bbox.max_y)
            start = findfirst(ind)
            stop = findlast(ind)

            if isnothing(start)
                @warn "no data found within bbox: $(file.filename)"

                gt = (
                    longitude = Vector{Float64}[],
                    latitude = Vector{Float64}[],
                    height = Vector{Float64}[],
                    datetime = Vector{Dates.DateTime}[],
                    quality = Vector{Bool}[],
                    clouds = clouds{Bool}[],
                    height_reference = Vector{Float64}[],
                    gain = Vector{Int32}[],
                    reflectivity = Vector{Float64}[],
                    attitude = Vector{Int8}[],
                    saturation = Vector{Int8}[],
                )
                return gt
            end

            # only include x and y data within bbox
            x = x[start:step:stop]
            y = y[start:step:stop]
        else
            start = 1
            stop = length(file["Data_40HZ/Geolocation/d_lon"])
            x = file["Data_40HZ/Geolocation/d_lon"][start:step:stop]::Vector{Float64}
            y = file["Data_40HZ/Geolocation/d_lat"][start:step:stop]::Vector{Float64}      
        end

        valid = (x .!= icesat_fill) .& (y .!= icesat_fill)
        height = file["Data_40HZ/Elevation_Surfaces/d_elev"][start:step:stop]::Vector{Float64}
        valid .&= height .!= icesat_fill
        height_correction = file["Data_40HZ/Elevation_Corrections/d_satElevCorr"][start:step:stop]::Vector{Float64}
        valid .&= (height_correction .!= icesat_fill)
        height .+= height_correction

        x = x[valid]
        y = y[valid]
        height = height[valid]
        height_correction = height_correction[valid]

        datetime = file["Data_40HZ/DS_UTCTime_40"][start:step:stop][valid]::Vector{Float64}
        quality = file["Data_40HZ/Quality/elev_use_flg"][start:step:stop][valid]::Vector{Int8}
        clouds = file["Data_40HZ/Elevation_Flags/elv_cloud_flg"][start:step:stop][valid]::Vector{Int8}
        sat_corr_flag = file["Data_40HZ/Quality/sat_corr_flg"][start:step:stop][valid]::Vector{Int8}
        sigma_att_flg = file["Data_40HZ/Quality/sigma_att_flg"][start:step:stop][valid]::Vector{Int8}
        ref_flag = file["Data_40HZ/Reflectivity/d_reflctUC"][start:step:stop][valid]::Vector{Float64}
        gain_value = file["Data_40HZ/Waveform/i_gval_rcv"][start:step:stop][valid]::Vector{Int32}
        i_numPk = file["Data_40HZ/Waveform/i_numPk"][start:step:stop][valid]::Vector{Int32}
        height_ref = file["Data_40HZ/Geophysical/d_DEM_elv"][start:step:stop][valid]::Vector{Float64}

        # SHOULD WE FILL WITH NAN OR MISSINGS ?
        height_ref[height_ref .== icesat_fill] .= NaN

        datetime = unix2datetime.(datetime .+ j2000_offset)

        pipe = topex_to_wgs84_ellipsoid()
        pts = Proj.proj_trans.(pipe, Proj.PJ_FWD, zip(x, y, height_ref))
        height_ref = [x[3] for x in pts]::Vector{Float64}

        pts = Proj.proj_trans.(pipe, Proj.PJ_FWD, zip(x, y,height))
        height = [x[3] for x in pts]::Vector{Float64}

        gt = (
            longitude = x,
            latitude = y,
            height = height,
            datetime = datetime,

            # NOT SURE THAT THIS FILTERS IS APPLICABLE NON-ICESHEET ELEVATION
            # quality defined according [^1]
            quality = (quality .== 0) .&
                      (sigma_att_flg .== 0) .&
                      (i_numPk .== 1) .&
                      (height_correction .< 3),
            clouds = Bool.(clouds),

            height_reference = height_ref,
            gain = gain_value,
            reflectivity = ref_flag,
            attitude = sigma_att_flg,
            saturation = sat_corr_flag,
        )
        return gt
    end
end
