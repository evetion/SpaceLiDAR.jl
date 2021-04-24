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
        fn3 = joinpath(@__DIR__, "data/ATL03_20201121151145_08920913_004_01.h5")
        g3 = SpaceLiDAR.granule_from_file(fn3)
        points = SpaceLiDAR.points(g3)
        @test length(points) == 6
        lines = SpaceLiDAR.lines(g3, step=1000)
        @test length(lines) == 6
        SpaceLiDAR.classify(g3)
    end
    @testset "ATL08" begin
        fn8 = joinpath(@__DIR__, "data/ATL08_20201121151145_08920913_004_01.h5")
        g8 = SpaceLiDAR.granule_from_file(fn8)
        points = SpaceLiDAR.points(g8, step=1000)
        @test length(points) == 6
        lines = SpaceLiDAR.lines(g8, step=1000)
        @test length(lines) == 6
        LazIO.write("test.laz", g8)
    end
    @testset "L2A" begin
        fng = joinpath(@__DIR__, "data/GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5")
        gg = SpaceLiDAR.granule_from_file(fng)
        points = SpaceLiDAR.points(gg, step=1000)
        @test length(points) == 8
        points = SpaceLiDAR.points(gg, step=1000, canopy=true)
        @test length(points) == 16
        lines = SpaceLiDAR.lines(gg, step=1000)
        @test length(lines) == 8
        LazIO.write("test.laz", gg)
    end
end
