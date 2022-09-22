"""
    points(g::ICESat_Granule{:GLAH14})

Retrieve the points for a given ICESat GLAH14 (Land Surface) granule as a list of namedtuples
The names of the tuples are based on the following fields:

| Variable           | Original Field (in `Data_40HZ`) | Description                                 | Units                        |
|:------------------ |:------------------------------- |:------------------------------------------- |:---------------------------- |
| `longitude`        | `/Geolocation/d_lon`            | Longitude of segment center, WGS84, East=+  | decimal degrees              |
| `latitude`         | `Geolocation/d_lat`             | Latitude of segment center, WGS84, North=+  | decimal degrees              |
| `height`           | `Elevation_Surfaces/d_elev`     | + `Elevation_Corrections/d_satElevCorr`     | m above WGS84 ellipsoid      |
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
function points(granule::ICESat_Granule{:GLAH14}; step = 1)
    HDF5.h5open(granule.url, "r") do file

        zt = file["Data_40HZ/Elevation_Surfaces/d_elev"][1:step:end]::Vector{Float64}
        m = zt .!= icesat_fill
        zc = file["Data_40HZ/Elevation_Corrections/d_satElevCorr"][1:step:end]::Vector{Float64}
        m .&= (zc .!= icesat_fill)
        zt .+= zc

        x = file["Data_40HZ/Geolocation/d_lon"][1:step:end]::Vector{Float64}
        m .&= (x .!= icesat_fill)
        x[x.>180] .= x[x.>180] .- 360.0  # translate from 0 - 360

        y = file["Data_40HZ/Geolocation/d_lat"][1:step:end]::Vector{Float64}
        m .&= (y .!= icesat_fill)

        t = file["Data_40HZ/DS_UTCTime_40"][1:step:end][m]::Vector{Float64}

        q = file["Data_40HZ/Quality/elev_use_flg"][1:step:end][m]::Vector{Int8}
        clouds = file["Data_40HZ/Elevation_Flags/elv_cloud_flg"][1:step:end][m]::Vector{Int8}
        sat_corr_flag = file["Data_40HZ/Quality/sat_corr_flg"][1:step:end][m]::Vector{Int8}
        sigma_att_flg = file["Data_40HZ/Quality/sigma_att_flg"][1:step:end][m]::Vector{Int8}
        ref_flag = file["Data_40HZ/Reflectivity/d_reflctUC"][1:step:end][m]::Vector{Float64}
        gain_value = file["Data_40HZ/Waveform/i_gval_rcv"][1:step:end][m]::Vector{Int32}
        i_numPk = file["Data_40HZ/Waveform/i_numPk"][1:step:end][m]::Vector{Int32}

        dem = file["Data_40HZ/Geophysical/d_DEM_elv"][1:step:end][m]::Vector{Float64}
        dem[dem.==icesat_fill] .= NaN

        times = unix2datetime.(t .+ j2000_offset)

        pipe = topex_to_wgs84_ellipsoid()
        pts = Proj.proj_trans.(pipe, Proj.PJ_FWD, zip(x[m], y[m], dem))
        dem = [x[3] for x in pts]::Vector{Float64}

        pts = Proj.proj_trans.(pipe, Proj.PJ_FWD, zip(x[m], y[m], zt[m]))
        height = [x[3] for x in pts]::Vector{Float64}

        gt = (
            longitude = x[m],
            latitude = y[m],
            height = height,
            datetime = times,
            # quality defined according [^1]
            quality = (q .== 0) .&
                      (sigma_att_flg .== 0) .&
                      (i_numPk .== 1) .&
                      (zc[m] .< 3),
            clouds = Bool.(clouds),
            height_reference = dem,
            gain = gain_value,
            reflectivity = ref_flag,
            attitude = sigma_att_flg,
            saturation = sat_corr_flag,
        )
        return gt
    end
end
