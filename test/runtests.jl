using SpaceLiDAR
using Test
using Dates
using Distances
import Downloads
using Random
using DataFrames
using Tables
using Proj
using Documenter

const rng = MersenneTwister(54321)
const SL = SpaceLiDAR

# ensure test data is present
testdir = @__DIR__
datadir = joinpath(testdir, "data")
isdir(datadir) || mkdir(datadir)

function download_artifact(version, source_filename)
    local_path = joinpath(datadir, source_filename)
    url = "https://github.com/evetion/SpaceLiDAR-artifacts/releases/download/v$version/$source_filename"
    isfile(local_path) || Downloads.download(url, local_path)
    return local_path
end

ATL03_fn = download_artifact(v"0.2", "ATL03_20201121151145_08920913_005_01.h5")
ATL06_fn = download_artifact(v"0.2", "ATL06_20220404104324_01881512_005_01.h5")
ATL08_fn = download_artifact(v"0.2", "ATL08_20201121151145_08920913_005_01.h5")
ATL12_fn = download_artifact(v"0.2", "ATL12_20220404110409_01891501_005_01.h5")
GEDI02_fn = download_artifact(v"0.1", "GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5")
GLAH14_fn = download_artifact(v"0.1", "GLAH14_634_1102_001_0071_0_01_0001.H5")
GLAH06_fn = download_artifact(v"0.1", "GLAH06_634_2131_002_0084_4_01_0001.H5")

@testset "SpaceLiDAR.jl" begin

    @testset "doctests" begin
        DocMeta.setdocmeta!(
            SpaceLiDAR,
            :DocTestSetup,
            :(import SpaceLiDAR as SL);
            recursive = true,
        )
        doctest(SpaceLiDAR)
    end

    @testset "utils" begin
        @test SL.track_power(0, "gt1l") == "strong"
        @test SL.track_power(0, "gt1r") == "weak"
        @test SL.track_power(1, "gt1l") == "weak"
        @test SL.track_power(1, "gt1r") == "strong"
        @test SL.track_power(2, "gt1l") == "transit"
        @test SL.track_power(2, "gt1r") == "transit"
    end

    @testset "search" begin
        @test length(find(:ICESat, "GLAH06", (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0))) > 0
        @test length(find(:ICESat, "GLAH14", (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0))) > 0
        @test length(find(:ICESat2, "ATL03", (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0))) > 0
        @test length(find(:ICESat2, "ATL06", (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0))) > 0
        @test length(find(:ICESat2, "ATL08", (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0))) > 0
        granules = find(:GEDI, "GEDI02_A", (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0))
        @test length(granules) > 0
        @test length(granules[1].polygons) > 0

        @test_throws ArgumentError find(:ICESat2, "GLAH14")
    end

    @testset "download" begin
        if "EARTHDATA_USER" in keys(ENV)
            SpaceLiDAR.netrc!(
                get(ENV, "EARTHDATA_USER", ""),
                get(ENV, "EARTHDATA_PW", ""),
            )
        end
        granules = search(:ICESat, :GLAH06, bbox = (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0))
        g = granules[1]
        download!(g)
        @test isfile(g)
        rm(g)

        granules = search(:ICESat, :GLAH06, bbox = (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0), s3 = true)
        g = granules[1]
        download!(g)
        @test isfile(g)
        rm(g)
    end

    @testset "granules" begin
        gs = SL.granules_from_folder("data")
        @test length(gs) == 7

        fgs = SL.in_bbox(gs, (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0))
        @test length(fgs) == 2
        SL.bounds.(fgs)
    end

    @testset "GLAH06" begin
        g = SL.granule_from_file(GLAH06_fn)

        bbox = (min_x = 131.0, min_y = -40, max_x = 132, max_y = -30)
        points = SL.points(g; bbox = bbox)
        @test length(points.latitude) == 287
        @test points.quality[1] == true

        points = SL.points(g; step = 4, bbox = bbox)
        @test length(points.longitude) == 74
    end

    @testset "GLAH14" begin
        g = SL.granule_from_file(GLAH14_fn)

        points = SL.points(g)
        @test length(points) == 11

        bbox = (min_x = -20.0, min_y = -85, max_x = -2, max_y = 20)
        points = SL.points(g; bbox = bbox)
        @test length(points.latitude) == 375791
        @test typeof(points.gain[1010]) == Int32

        points = SL.points(g; step = 400, bbox = bbox)
        @test length(points.longitude) == 934
    end

    @testset "ATL03" begin
        g = SL.granule_from_file(ATL03_fn)

        points = SL.points(g)
        @test length(points) == 6
        @test points[1].strong_beam[1] == true
        @test points[1].track[1] == "gt1l"
        @test points[end].strong_beam[1] == false
        @test points[end].track[1] == "gt3r"

        bbox = (min_x = 174.0, min_y = -50.0, max_x = 176.0, max_y = -30.0)
        points = SL.points(g, step = 1, bbox = bbox)
        @test length(points) == 6
        @test length(points[1].longitude) == 1158412

        lines = SL.lines(g, step = 1000)
        @test length(lines) == 6

        c = SL.classify(g)
        df = reduce(vcat, DataFrame.(c))

        SL.materialize!(df)
        @test df.classification isa Vector{String}
    end

    @testset "ATL06" begin
        g6 = SL.granule_from_file(ATL06_fn)

        points = SL.points(g6, step = 1000)
        @test length(points) == 6
        @test length(points[1].height) == 34

        df = reduce(vcat, DataFrame.(points))
        @test minimum(df.datetime) == Dates.DateTime("2022-04-04T10:43:41.629")
        @test all(in.(df.detector_id, Ref(1:6)))
    end

    @testset "ATL08" begin
        g = SL.granule_from_file(ATL08_fn)

        points = SL.points(g, step = 1000)
        @test length(points) == 6
        points = SL.points(g, step = 1)
        @test length(points) == 6
        @test length(points[1].longitude) == 933
        @test points[1].longitude[356] ≈ 175.72562f0

        lines = SL.lines(g, step = 1000)
        @test length(lines) == 6

        # Test partially intersecting bbox, resulting in at least 1 emtpy track
        bbox = (min_x = 175.0, min_y = -50.0, max_x = 175.5, max_y = -30.0)
        points = SL.points(g, step = 1, bbox = bbox)
        @test length(points) == 6
        @test length(points[2].longitude) == 0
        @test length(points[1].longitude) == 45
        @test points[1].longitude[45] ≈ 175.22807f0
        df = reduce(vcat, DataFrame.(points))  # test that empty tracks can be catted
    end

    @testset "ATL12" begin
        g12 = SL.granule_from_file(ATL12_fn)

        points = SL.points(g12)
        @test length(points) == 6
    end

    @testset "L2A" begin
        gg = SL.granule_from_file(GEDI02_fn)

        points = SL.points(gg, step = 1000)
        @test length(points) == 8
        @test points[2].strong_beam[1] == false
        @test points[4].strong_beam[1] == false
        @test points[4].track[1] == "BEAM0011"
        @test points[5].track[1] == "BEAM0101"
        @test points[5].strong_beam[1] == true
        @test points[end].strong_beam[1] == true

        points = SL.points(gg, step = 10, canopy = true)
        @test length(points[1].longitude) == 1760
        @test length(points) == 16

        lines = SL.lines(gg, step = 1000)
        @test length(lines) == 8

        bbox = (min_x = 160.0, min_y = -46.0, max_x = 170.0, max_y = -38.0)
        points = SL.points(gg; step = 10, bbox = bbox, canopy = true)
        @test length(points[1].longitude) == 1166
        @test length(points[6].latitude) == 1168
        @test length(points) == 16
        df = reduce(vcat, DataFrame.(points))
    end

    @testset "Geometry" begin
        @testset "Shift" begin
            n = 100
            for (d, angle, x, y) in zip(
                rand(rng, 0:1000, n),
                rand(rng, 1:360, n),
                rand(rng, -180:180, n),
                rand(-90:90, n),
            )
                o = (x, y)
                p = SL.shift(o..., angle, d)
                @test isapprox(Haversine()(o, p), d; rtol = 0.001 * d)
            end
        end

        @testset "Angle" begin
            g = SL.granule_from_file(ATL08_fn)
            @test isapprox(SL.track_angle(g, 0), -1.992, atol = 1e-3)
            @test isapprox(SL.track_angle(g, 88), -90.0, atol = 1e-3)

            gg = SL.granule_from_file(GEDI02_fn)
            @test isapprox(SL.track_angle(gg, 0), 38.249, atol = 1e-3)
            @test isapprox(SL.track_angle(gg, 51.6443), 86.075, atol = 1e-3)
        end
    end

    @testset "Geoid" begin
        df = DataFrame(longitude = [1.0], latitude = [2.0], height = [0.0])
        SL.to_egm2008!(df)
        @test df.height[1] ≈ -17.0154953
    end

    @testset "Proj" begin
        pipe = SL.topex_to_wgs84_ellipsoid()
        pts = Proj.proj_trans.(pipe, Proj.PJ_FWD, [(0, 0, 0)])
        @test pts[1][3] ≈ -0.700000000
    end

    @testset "Tables" begin
        g3 = SL.granule_from_file(ATL03_fn)
        @test Tables.istable(g3)
        @test Tables.columnaccess(g3)
        t = Tables.columntable(g3)
        @test length(t.longitude) == 4295820

        df = DataFrame(t)
        SL.materialize!(df)
        SL.in_bbox(df, (min_x = 0.0, min_y = 0.0, max_x = 1.0, max_y = 1.0))
        SL.in_bbox!(df, (min_x = 0.0, min_y = 0.0, max_x = 1.0, max_y = 1.0))
        @test length(df.longitude) == 0

        g14 = SL.granule_from_file(GLAH14_fn)
        @test Tables.istable(g14)
        t = Tables.columntable(g14)
        @test length(t.longitude) == 729117

    end
end
