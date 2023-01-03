"""
    points(g::ICESat_Granule{:GLAH06}, step=1, bbox::Union{Nothing,NamedTuple{}} = nothing)

Retrieve the points for a given ICESat GLAH06 (Land Ice) granule as a list of namedtuples
The names of the tuples are based on the following fields:

| Variable           | Original Field                        | Description                                           | Units                   |
|:------------------ |:------------------------------------- |:----------------------------------------------------- |:----------------------- |
| `longitude`        | `Data_40HZ/Geolocation/d_lon`         | Longitude of segment center, WGS84, East=+            | decimal degrees         |
| `latitude`         | `Data_40HZ/Geolocation/d_lat`         | Latitude of segment center, WGS84, North=+            | decimal degrees         |
| `height`           | `Data_40HZ/Elevation_Surfaces/d_elev` | + `Data_40HZ/Elevation_Corrections/d_satElevCorr`     | m above WGS84 ellipsoid |
| `datetime`         | `Data_40HZ/DS_UTCTime_40`             | Precise time of aquisiton                             | date-time               |
| `quality` [^1]     | `Data_40HZ/Quality/elev_use_flg`      | & `Data_40HZ/Quality/sigma_att_flg` = 0               |                         |
|                    | & `Data_40HZ/Waveform/i_numPk` = 1    | & `Data_40HZ/Elevation_Corrections/d_satElevCorr` < 3 | 1 = high quality        |
| `height_reference` | `land_ice_segments/dem/dem_h`         | Height of the (best available) DEM                    | height above WGS84      |

You can get the output in a `DataFrame` with `DataFrame(points(g))`.

[^1]: Smith, B., Fricker, H. A., Gardner, A. S., Medley, B., Nilsson, J., Paolo, F. S., ... & Zwally, H. J. (2020). Pervasive ice sheet mass loss reflects competing ocean and atmosphere processes. Science, 368(6496), 1239-1242.
"""
function points(
    granule::ICESat_Granule{:GLAH06};
    step = 1,
    bbox::Union{Nothing,NamedTuple{}} = nothing,
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
                @warn "no data found within bbox of track $track in $(file.filename)"

                gt = (
                    longitude = Vector{Float64}[],
                    latitude = Vector{Float64}[],
                    height = Vector{Float64}[],
                    datetime = Vector{Dates.DateTime}[],
                    # quality defined according [^1]
                    quality = Vector{Bool}[],
                    height_reference = Vector{Float64}[],
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

        height = file["Data_40HZ/Elevation_Surfaces/d_elev"][start:step:stop]::Vector{Float64}

        # cull non-valid data [DO WE WANT TO KEEP THIS OR RETURN MISSINGS INSTEAD?]
        valid = height .!= icesat_fill
        height = height[valid]
        x = x[valid]
        y = y[valid]

        saturation_correction =
            file["Data_40HZ/Elevation_Corrections/d_satElevCorr"][start:step:stop][valid]::Vector{Float64}
        saturation_correction[(saturation_correction.==icesat_fill)] .= 0.0
        height .+= saturation_correction

        datetime = file["Data_40HZ/DS_UTCTime_40"][start:step:stop][valid]::Vector{Float64}
        quality = file["Data_40HZ/Quality/elev_use_flg"][start:step:stop][valid]::Vector{Int8}
        sigma_att_flg = file["Data_40HZ/Quality/sigma_att_flg"][start:step:stop][valid]::Vector{Int8}
        i_numPk = file["Data_40HZ/Waveform/i_numPk"][start:step:stop][valid]::Vector{Int32}
        height_ref = file["Data_40HZ/Geophysical/d_DEM_elv"][start:step:stop][valid]::Vector{Float64}
        height_ref[height_ref.==icesat_fill] .= NaN

        datetime = unix2datetime.(datetime .+ j2000_offset)

        pipe = topex_to_wgs84_ellipsoid()
        pts = Proj.proj_trans.(pipe, Proj.PJ_FWD, zip(x, y, height_ref))
        height_ref = [x[3] for x in pts]::Vector{Float64}

        pts = Proj.proj_trans.(pipe, Proj.PJ_FWD, zip(x, y, height))
        height = [x[3] for x in pts]::Vector{Float64}

        # no need to update latitude as differences are well below the precision of the instrument (~1.0e-06 degrees)
        # latitude = [x[1] for x in pts]::Vector{Float64}
        gt = (
            longitude = x,
            latitude = y,
            height = height,
            datetime = datetime,
            # quality defined according [^1]
            quality = (quality .== 0) .&
                      (sigma_att_flg .== 0) .&
                      (i_numPk .== 1) .&
                      (saturation_correction .< 3),
            height_reference = height_ref,
        )
        return gt
    end
end
