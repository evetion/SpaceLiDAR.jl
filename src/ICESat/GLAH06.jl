"""
    points(g::ICESat_Granule{:GLAH06})

Retrieve the points for a given GLAH06 (Land Ice) granule as a list of namedtuples
The names of the tuples are based on the following fields:

| Column           | Field                                   | Description                                       | Units                         |
|------------------|-----------------------------------------|---------------------------------------------------|-------------------------------|
| `longitude`        | `Data_40HZ/Geolocation/d_lon`              | Longitude of segment center, WGS84, East=+        | decimal degrees              |
| `latitude`         | `Data_40HZ/Geolocation/d_lat`              | Latitude of segment center, WGS84, North=+        | decimal degrees              |
| `height`           | `Data_40HZ/Elevation_Surfaces/d_elev` + `Data_40HZ/Elevation_Corrections/d_satElevCorr` | Standard land-ice segment height                  | height above TOPEX/POSEIDON |
| `datetime`         | `Data_40HZ/DS_UTCTime_40`            | Precise time of aquisiton  | date-time                  |
| `quality`          | `Data_40HZ/Quality/elev_use_flg`          | & `Data_40HZ/Quality/sigma_att_flg` = 0 & `Data_40HZ/Waveform/i_numPk` = 1 & `Data_40HZ.Elevation_Corrections/d_satElevCorr` < 3;   | 1 = high quality              |
| `height_reference` | `land_ice_segments/dem/dem_h`             | Height of the (best available) DEM                | height above TOPEX/POSEIDON |

You can combine the output in a `DataFrame` with `reduce(vcat, DataFrame.(points(g)))`.
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

        # ---- TODO convert from TOPEX/POSEIDON to WGS84 ----
        # TOPEX.LengthUnit = 'm';
        # TOPEX.SemimajorAxis = 6378136.299999999813735;
        # TOPEX.SemiminorAxis = 6356751.600562936626375;
        # TOPEX.InverseFlattening = 298.257;
        # TOPEX.Eccentricity = 0.08181922146;
        # ----------------------------------------------------

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

        gt = (
            longitude = longitude,
            latitude = latitude,
            height = height,
            datetime = datetime,
            # quality defined according to Smith et al, 2020. DOI: 10.1126/science.aaz5845
            quality = (quality .== 0) .& (sigma_att_flg .== 0) .& (i_numPk == 1) .& (saturation_correction .< 3),
            height_ref = height_ref,
            )
        gt
    end
end
