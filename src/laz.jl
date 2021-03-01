using LazIO
using TypedTables
using FillArrays
# TODO System identifier (NTuple{32,UInt8}) as id to couple las file to .h5
# TODO point_source_ID (UInt16) for RGT storage. Together with the time, this should enable original lookup

function LazIO.write(fn::AbstractString, granule::Granule)
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
    try
        LazIO.write(fn, nt[.~isnan.(t.z)], bounds(granule), scale=0.00001, system_identifier=LazIO.writestring(id, 32))
    catch e
        println("LazIO failed: $e, called with $(bounds(granule))")
    end
end
