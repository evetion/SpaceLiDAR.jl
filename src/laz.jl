using LazIO
using TypedTables
using FillArrays

function LazIO.write(fn::AbstractString, granule::ICESat2_Granule)
    meta = info(granule)
    id = "$(meta.type)_$(meta.rgt)_$(meta.cycle)_$(meta.segment)_$(meta.version)_$(meta.revision)"
    t = vcat(Table.(xyz(granule))...)
    nt = Table(
        X=t.x,
        Y=t.y,
        Z=t.z,
        intensity=round.(UInt16, min.(65535, t.u * 100)),
        gps_time=t.t,
        classification=t.classification,
        number_of_returns=t.number_of_returns,
        return_number=t.return_number,
        point_source_ID=Fill(UInt16(meta.rgt), length(t)),
        user_data=Fill(UInt16(meta.cycle), length(t))
    )
    LazIO.write(fn, nt[.~isnan.(t.z)], bounds(granule), scalex=1e-7, scaley=1e-7, scalez=0.001, system_identifier=LazIO.writestring(id, 32))
end

function LazIO.write(fn::AbstractString, granule::GEDI_Granule)
    meta = info(granule)
    id = "$(meta.type)_$(meta.orbit)_$(meta.track)_$(meta.version)_$(meta.revision)"
    t = vcat(Table.(xyz(granule))...)
    nt = Table(
        X=t.x,
        Y=t.y,
        Z=t.z,
        intensity=round.(UInt16, min.(65535, t.u * 100)),
        gps_time=t.t,
        classification=t.classification,
        number_of_returns=t.number_of_returns,
        return_number=t.return_number,
        point_source_ID=Fill(UInt16(meta.orbit), length(t)),
    )
    LazIO.write(fn, nt[.~isnan.(t.z)], bounds(granule), scalex=1e-7, scaley=1e-7, scalez=0.001, system_identifier=LazIO.writestring(id, 32))
end
