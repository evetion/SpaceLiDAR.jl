using SpaceLiDAR
using Test
using LazIO
using Distances
import Downloads

# ensure test data is present
testdir = @__DIR__
datadir = joinpath(testdir, "data")
isdir(datadir) || mkdir(datadir)

function download_artifact(version, source_filename)
    local_path = joinpath(datadir, source_filename)
    url = "https://github.com/evetion/SpaceLiDAR-artifacts/releases/download/v$version/$source_filename"
    isfile(local_path) || Downloads.download(url, local_path)
end

download_artifact(v"0.1", "ATL03_20201121151145_08920913_004_01.h5")
download_artifact(v"0.1", "ATL08_20201121151145_08920913_004_01.h5")
download_artifact(v"0.1", "GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5")
download_artifact(v"0.1", "GLAH14_634_1102_001_0071_0_01_0001.H5")

@testset "SpaceLiDAR.jl" begin

    @testset "utils" begin
        @test SpaceLiDAR.track_power(0, "gt1l") == "strong"
        @test SpaceLiDAR.track_power(0, "gt1r") == "weak"
        @test SpaceLiDAR.track_power(1, "gt1l") == "weak"
        @test SpaceLiDAR.track_power(1, "gt1r") == "strong"
        @test SpaceLiDAR.track_power(2, "gt1l") == "transit"
        @test SpaceLiDAR.track_power(2, "gt1r") == "transit"
    end

    @testset "search" begin
        @test length(find(:ICESat, "GLAH14")) > 0
        @test length(find(:ICESat2, "ATL03", (min_x = 4., min_y = 40., max_x = 5., max_y = 50.))) > 0
        @test length(find(:ICESat2, "ATL08", (min_x = 4., min_y = 40., max_x = 5., max_y = 50.))) > 0
        @test length(find(:GEDI, "GEDI02_A", (min_x = 4., min_y = 40., max_x = 5., max_y = 50.))) > 0
    end

    @testset "GLAH14" begin
        fn = joinpath(@__DIR__, "data/GLAH14_634_1102_001_0071_0_01_0001.H5")
        g = SpaceLiDAR.granule_from_file(fn)
        points = SpaceLiDAR.points(g)
    end
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
    @testset "Geometry" begin
        @testset "shift" begin
            n = 100
            for (d, angle, x, y) ∈ zip(rand(0:1000, n), rand(1:360, n), rand(-180:180, n), rand(-90:90, n))
                o = (x, y)
                p = SpaceLiDAR.shift(o..., angle, d)
                @test isapprox(Haversine()(o, p), d; rtol=0.001 * d)
            end
        end
    end
end
