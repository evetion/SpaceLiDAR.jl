using SpaceLiDAR
using Test
using LazIO
using Dates
using Distances
import Downloads
using Random
using GeoDataFrames

const rng = MersenneTwister(54321)

# ensure test data is present
testdir = @__DIR__
datadir = joinpath(testdir, "data")
isdir(datadir) || mkdir(datadir)

function download_artifact(version, source_filename)
    local_path = joinpath(datadir, source_filename)
    url = "https://github.com/evetion/SpaceLiDAR-artifacts/releases/download/v$version/$source_filename"
    return isfile(local_path) || Downloads.download(url, local_path)
end

download_artifact(v"0.2", "ATL03_20201121151145_08920913_005_01.h5")
download_artifact(v"0.2", "ATL06_20220404104324_01881512_005_01.h5")
download_artifact(v"0.2", "ATL08_20201121151145_08920913_005_01.h5")
download_artifact(v"0.1", "GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5")
download_artifact(v"0.1", "GLAH14_634_1102_001_0071_0_01_0001.H5")
download_artifact(v"0.1", "GLAH06_634_2131_002_0084_4_01_0001.H5")

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
        @test length(find(:ICESat, "GLAH06")) > 0
        @test length(
            find(
                :ICESat2,
                "ATL03",
                (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0),
            ),
        ) > 0
        @test length(
            find(
                :ICESat2,
                "ATL08",
                (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0),
            ),
        ) > 0
        @test length(
            find(
                :ICESat2,
                "ATL06",
                (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0),
            ),
        ) > 0
        @test length(
            find(
                :GEDI,
                "GEDI02_A",
                (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0),
            ),
        ) > 0
    end

    @testset "GLAH14" begin
        fn = joinpath(@__DIR__, "data/GLAH14_634_1102_001_0071_0_01_0001.H5")
        g = SpaceLiDAR.granule_from_file(fn)
        points = SpaceLiDAR.points(g)
    end
    @testset "GLAH06" begin
        fn = joinpath(@__DIR__, "data/GLAH06_634_2131_002_0084_4_01_0001.H5")
        g = SpaceLiDAR.granule_from_file(fn)
        points = SpaceLiDAR.points(g)
    end
    @testset "ATL03" begin
        fn3 = joinpath(@__DIR__, "data/ATL03_20201121151145_08920913_005_01.h5")
        g3 = SpaceLiDAR.granule_from_file(fn3)
        points = SpaceLiDAR.points(g3)
        @test length(points) == 6
        @test points[1].power[1] == "strong"
        @test points[1].track[1] == "gt1l"
        @test points[end].power[1] == "weak"
        @test points[end].track[1] == "gt3r"
        lines = SpaceLiDAR.lines(g3, step = 1000)
        @test length(lines) == 6
        SpaceLiDAR.classify(g3)
    end
    @testset "ATL06" begin
        fn6 = joinpath(@__DIR__, "data/ATL06_20220404104324_01881512_005_01.h5")
        g6 = SpaceLiDAR.granule_from_file(fn6)
        points = SpaceLiDAR.points(g6, step = 1000)
        @test length(points) == 6
        @test length(points[1].height) == 34
        df = reduce(vcat, GeoDataFrames.DataFrame.(points))
        @test minimum(df.datetime) == Dates.DateTime("2022-04-04T10:43:41.629")
        @test all(in.(df.detector_id, Ref(1:6)))
    end
    @testset "ATL08" begin
        fn8 = joinpath(@__DIR__, "data/ATL08_20201121151145_08920913_005_01.h5")
        g8 = SpaceLiDAR.granule_from_file(fn8)
        points = SpaceLiDAR.points(g8, step = 1000)
        @test length(points) == 6
        lines = SpaceLiDAR.lines(g8, step = 1000)
        @test length(lines) == 6
        LazIO.write("test.laz", g8)
    end
    @testset "L2A" begin
        fng = joinpath(
            @__DIR__,
            "data/GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5",
        )
        gg = SpaceLiDAR.granule_from_file(fng)
        points = SpaceLiDAR.points(gg, step = 1000)
        @test length(points) == 8
        @test points[2].power[1] == "weak"
        @test points[4].power[1] == "weak"
        @test points[4].track[1] == "BEAM0011"
        @test points[5].track[1] == "BEAM0101"
        @test points[5].power[1] == "strong"
        @test points[end].power[1] == "strong"
        points = SpaceLiDAR.points(gg, step = 1000, canopy = true)
        @test length(points) == 16
        lines = SpaceLiDAR.lines(gg, step = 1000)
        @test length(lines) == 8
        LazIO.write("test.laz", gg)
    end
    @testset "Geometry" begin
        @testset "shift" begin
            n = 100
            for (d, angle, x, y) in zip(
                rand(rng, 0:1000, n),
                rand(rng, 1:360, n),
                rand(rng, -180:180, n),
                rand(-90:90, n),
            )
                o = (x, y)
                p = SpaceLiDAR.shift(o..., angle, d)
                @test isapprox(Haversine()(o, p), d; rtol = 0.001 * d)
            end
        end
    end
    @testset "Geoid" begin
        df = GeoDataFrames.DataFrame(x = [1.0], y = [2.0], z = [0.0])
        SpaceLiDAR.to_egm2008!(df)
        @test df.z[1] ≈ -17.0154953
    end
end
