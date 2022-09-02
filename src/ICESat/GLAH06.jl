"""
    points(g::ICESat_Granule{:GLAH06})

Retrieve the points for a given GLAH06 (Land Ice) granule as a list of namedtuples
The names of the tuples are based on the following fields:

| Variable           | Original Field                           | Description                                           | Units                   |
|--------------------|------------------------------------------|-------------------------------------------------------|-------------------------|
| `longitude`        | `Data_40HZ/Geolocation/d_lon`            | Longitude of segment center, WGS84, East=+            | decimal degrees         |
| `latitude`         | `Data_40HZ/Geolocation/d_lat`            | Latitude of segment center, WGS84, North=+            | decimal degrees         |
| `height`           | `Data_40HZ/Elevation_Surfaces/d_elev`    | + `Data_40HZ/Elevation_Corrections/d_satElevCorr`     | m above WGS84 ellipsoid |
| `datetime`         | `Data_40HZ/DS_UTCTime_40`                | Precise time of aquisiton                             | date-time               |
| `quality` [^1]     | `Data_40HZ/Quality/elev_use_flg`         | & `Data_40HZ/Quality/sigma_att_flg` = 0               |                         |
|                    | & `Data_40HZ/Waveform/i_numPk` = 1       | & `Data_40HZ.Elevation_Corrections/d_satElevCorr` < 3 | 1 = high quality        |
| `height_reference` | `land_ice_segments/dem/dem_h`            | Height of the (best available) DEM                    | height above WGS84      |

You can get the output in a `DataFrame` with `DataFrame(points(g)`.
"""

const icesat_fill = 1.7976931348623157E308

function points(granule::ICESat_Granule{:GLAH06}; step=1)
    HDF5.h5open(granule.url, "r") do file

        height = file["Data_40HZ/Elevation_Surfaces/d_elev"][1:step:end]::Vector{Float64}
        valid = height .!= icesat_fill
        height = height[valid]

        saturation_correction = file["Data_40HZ/Elevation_Corrections/d_satElevCorr"][1:step:end][valid]::Vector{Float64}
        saturation_correction[(saturation_correction .== icesat_fill)] .= 0.0
        height .+= saturation_correction

        longitude = file["Data_40HZ/Geolocation/d_lon"][1:step:end][valid]::Vector{Float64}
        longitude[longitude .> 180] .= longitude[longitude .> 180] .- 360.0  # translate from 0 - 360
        latitude = file["Data_40HZ/Geolocation/d_lat"][1:step:end][valid]::Vector{Float64}

        datetime = file["Data_40HZ/DS_UTCTime_40"][1:step:end][valid]::Vector{Float64}

        quality = file["Data_40HZ/Quality/elev_use_flg"][1:step:end][valid]::Vector{Int8}
        sigma_att_flg = file["Data_40HZ/Quality/sigma_att_flg"][1:step:end][valid]::Vector{Int8}
        i_numPk = file["Data_40HZ/Waveform/i_numPk"][1:step:end][valid]::Vector{Int32}

        height_ref = file["Data_40HZ/Geophysical/d_DEM_elv"][1:step:end][valid]::Vector{Float64}
        height_ref[height_ref .== icesat_fill] .= NaN

        datetime = unix2datetime.(datetime .+ j2000_offset)

        # convert from TOPEX/POSEIDON to WGS84 ellipsoid using Proj.jl
        # This pipeline was validated against MATLAB's geodetic2ecef -> ecef2geodetic
        pipe = Proj.proj_create("+proj=pipeline +step +proj=unitconvert +xy_in=deg +z_in=m +xy_out=rad +z_out=m +step +inv +proj=longlat +a=6378136.3 +rf=298.257 +e=0.08181922146 +step +proj=cart +a=6378136.3 +rf=298.257 +step +inv +proj=cart +ellps=WGS84 +step +proj=unitconvert +xy_in=rad +z_in=m +xy_out=deg +z_out=m +step +proj=axisswap +order=2,1")
        
        pts = Proj.proj_trans.(pipe, Proj.PJ_FWD, zip(longitude, latitude, height_ref))
        height_ref = [x[3] for x in pts]::Vector{Float64}

        pts = Proj.proj_trans.(pipe, Proj.PJ_FWD, zip(longitude, latitude, height))
        longitude = [x[2] for x in pts]::Vector{Float64}
        latitude = [x[1] for x in pts]::Vector{Float64}
        height = [x[3] for x in pts]::Vector{Float64}

        gt = (
            longitude = longitude,
            latitude = latitude,
            height = height,
            datetime = datetime,
            # quality defined according [^1]
            quality = (quality .== 0) .& (sigma_att_flg .== 0) .& (i_numPk == 1) .& (saturation_correction .< 3),
            height_ref = height_ref,
            )
        return gt
    end
end

# footnotes
# [^1]: # Smith, B., Fricker, H. A., Gardner, A. S., Medley, B., Nilsson, J., Paolo, F. S., ... & Zwally, H. J. (2020). Pervasive ice sheet mass loss reflects competing ocean and atmosphere processes. Science, 368(6496), 1239-1242.

