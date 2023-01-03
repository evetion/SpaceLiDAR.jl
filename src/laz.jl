using LazIO
using DataFrames
using FillArrays

function LazIO.write(fn::AbstractString, granule::ICESat2_Granule)
    meta = info(granule)
    id = "$(meta.type)_$(meta.rgt)_$(meta.cycle)_$(meta.segment)_$(meta.version)_$(meta.revision)"
    t = reduce(vcat, DataFrame.(points(granule)))
    nt = DataFrame(
        X = t.x,
        Y = t.y,
        Z = t.z,
        intensity = round.(UInt16, min.(65535, t.u * 100)),
        gps_time = t.t,
        classification = t.classification,
        number_of_returns = t.number_of_returns,
        return_number = t.return_number,
        scan_angle_rank = map(==("strong"), t.power),
        point_source_ID = Fill(UInt16(meta.rgt), length(t.x)),
        user_data = Fill(UInt16(meta.cycle), length(t.x)),
    )
    return LazIO.write(
        fn,
        nt[.~isnan.(t.z), :],
        bounds(granule),
        scalex = 1e-6,
        scaley = 1e-6,
        scalez = 0.001,
        system_identifier = LazIO.writestring(id, 32),
        point_data_format = 1,
        point_data_record_length = 28,
        global_encoding = 1,
    )
end

function LazIO.write(fn::AbstractString, granule::GEDI_Granule)
    meta = info(granule)
    id = "$(meta.type)_$(meta.orbit)_$(meta.track)_$(meta.version)_$(meta.revision)"
    t = reduce(vcat, DataFrame.(points(granule)))
    nt = DataFrame(
        X = t.x,
        Y = t.y,
        Z = t.z,
        intensity = round.(UInt16, min.(65535, t.u * 100)),
        gps_time = t.t,
        classification = t.classification,
        number_of_returns = t.number_of_returns,
        return_number = t.return_number,
        scan_angle_rank = map(==("strong"), t.power),
        point_source_ID = Fill(UInt16(meta.orbit), length(t.x)),
    )
    return LazIO.write(
        fn,
        nt[.~isnan.(t.z), :],
        bounds(granule),
        scalex = 1e-7,
        scaley = 1e-7,
        scalez = 0.001,
        system_identifier = LazIO.writestring(id, 32),
        point_data_format = 1,
        point_data_record_length = 28,
        global_encoding = 1,
    )
end
