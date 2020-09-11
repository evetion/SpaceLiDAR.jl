t_offset = 1514764800  # Time delta since Jan 1 00:00 2018.


function xyz(granule::GEDI_Granule{:GEDI02A})
    dfs = Vector{DataFrame}()
    HDF5.h5open(granule.url, "r") do file

        for (i, track) ∈ enumerate(gedi_tracks)
            power = i > 4 ? "_strong" : "_weak"
            if in(track, names(file))
                zt = read(file, "$track/elev_highestreturn")
                zb = read(file, "$track/elev_lowestmode")
                xt = read(file, "$track/lon_highestreturn")
                xb = read(file, "$track/lon_lowestmode")
                yt = read(file, "$track/lat_highestreturn")
                yb = read(file, "$track/lat_lowestmode")
                t = read(file, "$track/delta_time")
                q = read(file, "$track/quality_flag")
                sun_angle = read(file, "$track/solar_elevation")

                times = unix2datetime.(t .+ t_offset)
                push!(dfs, DataFrame(x=xt, y=yt, z=zt, t=times, quality=q, track=track * power, classification="canopy", sun_angle=sun_angle))
                push!(dfs, DataFrame(x=xb, y=yb, z=zb, t=times, quality=q, track=track * power, classification="ground", sun_angle=sun_angle))
            end
        end
    end
    vcat(dfs...)
end
