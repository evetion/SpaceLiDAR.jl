const icesat_fill = 1.7976931348623157E308

function points(granule::ICESat_Granule{:GLAH14}; step=1)
    HDF5.h5open(granule.url, "r") do file

        zt = file["Data_40HZ/Elevation_Surfaces/d_elev"][1:step:end]::Array{Float64,1}
        m = zt .!= icesat_fill
        zc = file["Data_40HZ/Elevation_Corrections/d_satElevCorr"][1:step:end]::Array{Float64,1}
        m .&= (zc .!= icesat_fill)
        zt .+= zc

        # tu = file["$track/land_segments/terrain/h_te_uncertainty"][1:step:end]::Array{Float32,1}

        x = file["Data_40HZ/Geolocation/d_lon"][1:step:end]::Array{Float64,1}
        m .&= (x .!= icesat_fill)
        x .-= 180.0  # correct from 0 - 360
        y = file["Data_40HZ/Geolocation/d_lat"][1:step:end]::Array{Float64,1}
        m .&= (y .!= icesat_fill)

        t = file["Data_40HZ/DS_UTCTime_40"][1:step:end][m]::Array{Float64,1}
        q = file["Data_40HZ/Quality/elev_use_flg"][1:step:end][m]::Vector{Int8}

        # sensitivity = file["$track/land_segments/snr"][1:step:end]::Array{Float32,1}
        clouds = file["Data_40HZ/Elevation_Flags/elv_cloud_flg"][1:step:end][m]::Array{Int8,1}

        # sat_corr_flag = file["Data_40HZ/Quality/sat_corr_flg"][1:step:end]::Array{Int8,1}
        # att_flag = file["Data_40HZ/Quality/sigma_att_flg"][1:step:end]::Array{Int8,1}

        dem = file["Data_40HZ/Geophysical/d_DEM_elv"][1:step:end][m]::Array{Float64,1}
        dem[dem .== icesat_fill] .= NaN

        times = unix2datetime.(t .+ j2000_offset)

        gt = (
            x = x[m],
            y = y[m],
            z = zt[m],
            # u = tu,
            t = times,
            q = .~(Bool.(q)),
            # sensitivity = sensitivity,
            cloud = Bool.(clouds),
            # classification = Fill("ground", length(times)),
            # return_number = Fill(2, length(times)),
            # number_of_returns = Fill(2, length(times)),
            reference = dem,
            )
        gt
    end
end
