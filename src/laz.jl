using LazIO
using TypedTables

function LazIO.write(fn::AbstractString, granule::Granule)
    t = vcat(Table.(xyz(granule))...)
    nt = Table(X=t.x, Y=t.y, Z=t.z, gps_time=t.t, classification=t.classification, number_of_returns=t.number_of_returns, return_number=t.return_number)
    try
        LazIO.write(fn, nt[.~isnan.(t.z)], bounds(granule), scale=0.00001)
    catch e
        println("LazIO failed: $e, called with $(bounds(granule))")
    end
end
