using SpaceLiDAR
using Test
using LazIO

@testset "SpaceLiDAR.jl" begin

    @test SpaceLiDAR.track_power(0, "gt1l") == "strong"
    @test SpaceLiDAR.track_power(0, "gt1r") == "weak"
    @test SpaceLiDAR.track_power(1, "gt1l") == "weak"
    @test SpaceLiDAR.track_power(1, "gt1r") == "strong"
    @test SpaceLiDAR.track_power(2, "gt1l") == "transit"
    @test SpaceLiDAR.track_power(2, "gt1r") == "transit"


    @testset "ATL03" begin
        fn3 = "data/ATL03_20191023205923_04120502_003_01.h5"
        g3 = SpaceLiDAR.granule_from_file(fn3)
        points = SpaceLiDAR.xyz(g3, step=1000)
        @test length(points) == 6
        lines = SpaceLiDAR.lines(g3, step=1000)
        @test length(lines) == 6
        SpaceLiDAR.classify(g3)
    end
    @testset "ATL08" begin
        fn8 = "data/ATL08_20191023205923_04120502_003_01.h5"
        g8 = SpaceLiDAR.granule_from_file(fn8)
        points = SpaceLiDAR.xyz(g8, step=1000)
        @test length(points) == 6
        lines = SpaceLiDAR.lines(g8, step=1000)
        @test length(lines) == 6
        LazIO.write("test.laz", g8)
    end
    @testset "L2A" begin
        fng = "data/GEDI02_A_2020048225628_O06706_T04016_02_001_01.h5"
        gg = SpaceLiDAR.granule_from_file(fng)
        points = SpaceLiDAR.xyz(gg, step=1000)
        @test length(points) == 8
        points = SpaceLiDAR.xyz(gg, step=1000, canopy=true)
        @test length(points) == 16
        lines = SpaceLiDAR.lines(gg, step=1000)
        @test length(lines) == 8
        LazIO.write("test.laz", gg)
    end
end
