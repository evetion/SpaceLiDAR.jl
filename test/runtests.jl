using SpaceLiDAR
using Test

@testset "SpaceLiDAR.jl" begin
    # Write your own tests here.
    # url = "https://n5eil01u.ecs.nsidc.org/ATLAS/ATL08.002/2019.11.15/ATL08_20191115000216_07500501_002_01.h5"
    id = "ATL08_20191115000216_07500501_002_01.h5"

    @test track_power(0, "gt1l") == "_strong"
    @test track_power(0, "gt1r") == "_weak"
    @test track_power(1, "gt1l") == "_weak"
    @test track_power(1, "gt1r") == "_strong"
    @test track_power(2, "gt1l") == "_transit"
    @test track_power(2, "gt1r") == "_transit"

end
