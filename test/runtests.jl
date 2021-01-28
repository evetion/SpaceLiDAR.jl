using SpaceLiDAR
using Test

@testset "SpaceLiDAR.jl" begin
    # Write your own tests here.
    # url = "https://n5eil01u.ecs.nsidc.org/ATLAS/ATL08.002/2019.11.15/ATL08_20191115000216_07500501_002_01.h5"
    id = "ATL08_20191115000216_07500501_002_01.h5"

    @test SpaceLiDAR.track_power(0, "gt1l") == "strong"
    @test SpaceLiDAR.track_power(0, "gt1r") == "weak"
    @test SpaceLiDAR.track_power(1, "gt1l") == "weak"
    @test SpaceLiDAR.track_power(1, "gt1r") == "strong"
    @test SpaceLiDAR.track_power(2, "gt1l") == "transit"
    @test SpaceLiDAR.track_power(2, "gt1r") == "transit"


    @testset "ATL03" begin
        fn3 = "/mnt/ec66e171-5639-4c62-9d2c-08e81c462669/icesat2/ATL03/v03/ATL03_20200714015108_02860801_003_01.h5"
        g3 = SpaceLiDAR.granule_from_file(fn3)
        points = SpaceLiDAR.xyz(g3, step=1000)
        @test length(points) == 6
        lines = SpaceLiDAR.lines(g3, step=1000)
        @test length(lines) == 6
    end
    @testset "ATL08" begin
        fn8 = "/mnt/ec66e171-5639-4c62-9d2c-08e81c462669/icesat2/ATL08/v03/ATL08_20191206075410_10750511_003_01.h5"
        g8 = SpaceLiDAR.granule_from_file(fn8)
        points = SpaceLiDAR.xyz(g8, step=1000)
        @test length(points) == 6
        lines = SpaceLiDAR.lines(g8, step=1000)
        @test length(lines) == 6
    end
    @testset "L2A" begin
        fng = "/mnt/ec66e171-5639-4c62-9d2c-08e81c462669/gedi/L2A/v1/GEDI02_A_2019269184101_O04470_T05507_02_001_01.h5"
        gg = SpaceLiDAR.granule_from_file(fng)
        points = SpaceLiDAR.xyz(gg, step=1000)
        @test length(points) == 16
        lines = SpaceLiDAR.lines(gg, step=1000)
        @test length(lines) == 16
    end
end
