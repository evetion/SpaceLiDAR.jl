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
    bbox = (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0)
    ex = convert(Extent, bbox)

    @test length(search(:ICESat, :GLAH06, extent = ex)) > 0
    @test length(search(:ICESat, :GLAH14, extent = ex)) > 0
    @test length(search(:ICESat2, :ATL03, extent = ex)) > 0
    @test length(search(:ICESat2, :ATL06, extent = ex)) > 0
    @test length(search(:ICESat2, :ATL08, extent = ex)) > 0
    granules = search(:GEDI, :GEDI02_A, extent = ex)
    @test length(granules) > 0
    @test length(granules[1].polygons) > 0

    id = "GEDI02_A_2023003040347_O22988_03_T06105_02_003_02_V002.h5"
    @test length(search(:GEDI, :GEDI02_A; version = 2, id = id)) == 1

    @test_throws ArgumentError search(:ICESat2, :GLAH14)
    @test_throws ArgumentError search(:Foo, :GLAH14)

    # Time
    @test length(SpaceLiDAR.search(:ICESat2, :ATL08, after = DateTime(2019, 12, 12), before = DateTime(2019, 12, 13))) == 161
    @test length(SpaceLiDAR.search(:ICESat2, :ATL08, before = DateTime(2017, 12, 12))) == 0
    @test length(SpaceLiDAR.search(:ICESat2, :ATL08, after = now())) == 0
    @test_throws ErrorException SpaceLiDAR.search(:ICESat2, :ATL08, after = now() - Month(47), before = now() - Month(48))
end

@testset "download" begin
    if "EARTHDATA_USER" in keys(ENV)
        @info "Setting up Earthdata credentials for Github Actions"
        SpaceLiDAR.netrc!(
            get(ENV, "EARTHDATA_USER", ""),
            get(ENV, "EARTHDATA_PW", ""),
        )
    end
    granules = search(:ICESat, :GLAH06, extent = convert(Extent, (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0)))
    g = granules[1]

    try
        SL.download!(g)
        @test isfile(g)
    catch e
        if e isa Downloads.RequestError
            @error "Could not download granule due to network error(s)"
        else
            rethrow(e)
        end
    end
    rm(g)

    # Test download! with nested directories that don't exist
    try
        nested_dir = joinpath(tempdir(), "test_spacelidar/nested/path")
        g2 = copy(granules[2])
        SL.download!(g2, nested_dir)
        @test isfile(g2)
        @test isdir(nested_dir)
        rm(g2)
        rm(joinpath(tempdir(), "test_spacelidar"); recursive = true)
    catch e
        if e isa Downloads.RequestError
            @error "Could not download granule due to network error(s)"
        else
            rethrow(e)
        end
    end

    # Test download! with path that needs normalization
    try
        unnormalized_path = joinpath(tempdir(), "test_spacelidar2", ".", "subdir", "..", "final")
        g3 = copy(granules[3])
        SL.download!(g3, unnormalized_path)
        @test isfile(g3)
        # The file should be in the normalized path
        expected_path = normpath(unnormalized_path)
        @test isdir(expected_path)
        @test g3.url == joinpath(expected_path, g3.id)
        rm(g3)
        rm(joinpath(tempdir(), "test_spacelidar2"); recursive = true)
    catch e
        if e isa Downloads.RequestError
            @error "Could not download granule due to network error(s)"
        else
            rethrow(e)
        end
    end

    # Test syncing of granules
    sync(["data/"], after = now(), extent = convert(Extent, (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0)))
    sync(:GLAH14, "data/", after = now(), extent = convert(Extent, (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0)))

    # This only works on us-west-2 region in AWS
    # granules = search(:ICESat2, :ATL08, bbox = convert(Extent, (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0)), s3 = true)
    # g = granules[1]
    # SL.download!(g)
    # @test isfile(g)
    # rm(g)
end

@testset "granules" begin
    og = SL.granule(GLAH06_fn)
    g = SL.granule(GLAH06_fn)
    @test og == g

    ogs = SL.granules("data")
    gs = SL.granules("data")
    @test ogs == gs
    @test length(gs) == 7
    copies = copy.(gs)

    # Set different path, but same id
    og.url = "data"
    @test !(og === g)
    @test isequal(og, g)
    @test hash(og) == hash(g)

    fgs = SL.in_bbox(gs, (min_x = 4.0, min_y = 40.0, max_x = 5.0, max_y = 50.0))
    @test length(fgs) == 2
    SL.bounds.(fgs)
end

@testset "GLAH06" begin
    g = SL.granule(GLAH06_fn)

    bbox = convert(Extent, (min_x = 131.0, min_y = -40, max_x = 132, max_y = -30))
    points = SL.points(g; bbox = bbox)
    @test points isa SL.AbstractTable
    @test length(points.latitude) == 287
    @test points.quality[1] == true

    points = SL.points(g; step = 4, bbox = bbox)
    @test length(points.longitude) == 74

    df = DataFrame(SL.points(g))
    dff = DataFrame(g)
    @test isequal(df, dff)

    points = SL.points(g)
    epoints = SL.points(g, ; bbox = empty_extent)
    @test typeof(points) == typeof(epoints)
end

@testset "GLAH14" begin
    g = SL.granule(GLAH14_fn)

    points = SL.points(g)
    @test points isa SL.AbstractTable
    @test length(points) == 11

    bbox = convert(Extent, (min_x = -20.0, min_y = -85, max_x = -2, max_y = 20))
    fpoints = SL.points(g; bbox = bbox)
    @test length(fpoints.latitude) == 375791
    @test typeof(fpoints.gain[1010]) == Int32

    fpoints = SL.points(g; step = 400, bbox = bbox)
    @test length(fpoints.longitude) == 934

    df = DataFrame(points)
    dff = DataFrame(g)
    @test isequal(df, dff)


    points = SL.points(g)
    epoints = SL.points(g, ; bbox = empty_extent)
    @test typeof(points) == typeof(epoints)
end

@testset "ATL03" begin
    g = SL.granule(ATL03_fn)
    g8 = SL.granule(ATL08_fn)

    points = SL.points(g)
    @test points isa SL.AbstractTable
    @test length(points) == 6
    @test points[1].strong_beam[1] == true
    @test points[1].track[1] == "gt1l"
    @test points[end].strong_beam[1] == false
    @test points[end].track[1] == "gt3r"

    bbox = convert(Extent, (min_x = 174.0, min_y = -50.0, max_x = 176.0, max_y = -30.0))
    fpoints = SL.points(g, step = 1, bbox = bbox)
    @test length(fpoints) == 6
    @test length(fpoints[1].longitude) == 1158412

    df = reduce(vcat, DataFrame.(points))
    dff = DataFrame(g)
    @test isequal(df, dff)

    lines = SL.lines(g, step = 1000)
    @test length(lines) == 6

    c = SL.classify(g)
    df = reduce(vcat, DataFrame.(c))
    @test df.classification isa CategoricalVector{String,Int8}
    SL.materialize!(df)
    @test df.classification isa Vector{String}

    points = SL.points(g)
    epoints = SL.points(g, ; bbox = empty_extent)
    @test typeof(points) == typeof(epoints)
end

@testset "ATL06" begin
    g6 = SL.granule(ATL06_fn)
    points = SL.points(g6)
    @test points isa SL.AbstractTable
    fpoints = SL.points(g6, step = 1000)
    @test length(points) == 6
    @test length(fpoints) == 6
    @test length(points[1].height) == 33725
    @test length(fpoints[1].height) == 34

    df = reduce(vcat, DataFrame.(points))
    @test minimum(df.datetime) == Dates.DateTime("2022-04-04T10:43:41.629")
    @test all(in.(df.detector_id, Ref(1:6)))

    df = reduce(vcat, DataFrame.(points))
    dff = DataFrame(g6)
    @test isequal(df, dff)

    points = SL.points(g6)
    epoints = SL.points(g6, ; bbox = empty_extent)
    @test typeof(points) == typeof(epoints)
end

@testset "ATL08" begin
    g = SL.granule(ATL08_fn)

    fpoints = SL.points(g, step = 1000)
    @test length(fpoints) == 6
    points = SL.points(g, step = 1)
    @test points isa SL.AbstractTable
    @test length(points) == 6
    @test length(points[1].longitude) == 998
    @test points[1].longitude[356] ≈ 175.72562f0

    df = reduce(vcat, DataFrame.(points))  # test that empty tracks can be catted
    dff = DataFrame(g)
    @test isequal(df, dff)

    lines = SL.lines(g, step = 1000)
    @test length(lines) == 6

    # Test partially intersecting bbox, resulting in at least 1 emtpy track
    bbox = convert(Extent, (min_x = 175.0, min_y = -50.0, max_x = 175.5, max_y = -30.0))
    points = SL.points(g, step = 1, bbox = bbox)
    @test length(points) == 6
    @test length(points[2].longitude) == 1
    @test length(points[1].longitude) == 55
    @test points[1].longitude[45] ≈ 175.22807f0

    ps = SL.points(g; highres = true)
    @test length(ps[1].longitude) == (998 * 5)

    points = SL.points(g)
    epoints = SL.points(g, ; bbox = empty_extent)
    @test typeof(points) == typeof(epoints)
end

@testset "ATL12" begin
    g12 = SL.granule(ATL12_fn)

    points = SL.points(g12)
    @test points isa SL.AbstractTable
    @test length(points) == 6

    df = reduce(vcat, DataFrame.(points))
    dff = DataFrame(g12)
    @test isequal(df, dff)
end

@testset "L2A" begin
    gg = SL.granule(GEDI02_fn)

    points = SL.points(gg, step = 1000)
    @test points isa SL.AbstractTable
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

    bbox = convert(Extent, (min_x = 160.0, min_y = -46.0, max_x = 170.0, max_y = -38.0))
    points = SL.points(gg; step = 10, bbox = bbox, canopy = true)
    @test length(points[1].longitude) == 1166
    @test length(points[6].latitude) == 1168
    @test length(points) == 16

    df = reduce(vcat, DataFrame.(SL.points(gg)))
    dff = DataFrame(gg)
    @test isequal(df, dff)

    points = SL.points(gg)
    epoints = SL.points(gg, ; bbox = empty_extent)
    @test typeof(points) == typeof(epoints)
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
        g = SL.granule(ATL08_fn)
        @test isapprox(SL.track_angle(g, 0), -1.992, atol = 1e-3)
        @test isapprox(SL.track_angle(g, 88), -90.0, atol = 1e-3)

        gg = SL.granule(GEDI02_fn)
        @test isapprox(SL.track_angle(gg, 0), 38.249, atol = 1e-3)
        @test isapprox(SL.track_angle(gg, 51.6443), 86.075, atol = 1e-3)
    end
end

@testset "Geoid" begin
    @testset "to_egm2008!" begin
        # DataFrame
        df = DataFrame(longitude = [1.0], latitude = [2.0], height = [0.0])
        SL.to_egm2008!(df)
        @test df.height[1] ≈ -17.0154953
        # CRS metadata stamped after projection
        @test DataAPI.metadata(df, "GEOINTERFACE:crs") == GeoFormatTypes.EPSG(4326, 3855)

        # Re-running on a table already in EGM2008 must be a no-op
        df2 = DataFrame(longitude = [1.0], latitude = [2.0], height = [0.0])
        DataAPI.metadata!(df2, "GEOINTERFACE:crs", GeoFormatTypes.EPSG(4326, 3855); style = :default)
        h_before = df2.height[1]
        SL.to_egm2008!(df2)
        @test df2.height[1] == h_before  # not double-projected

        # NamedTuple (no metadata support → projects unconditionally)
        nt = (; longitude = [1.0], latitude = [2.0], height = [0.0])
        r = SL.to_egm2008!(nt)
        @test r.height[1] ≈ -17.0154953
        @test nt.height[1] ≈ -17.0154953  # mutated in place

        nt2 = (; longitude = [1.0], latitude = [2.0], height = [0.0])
        r2 = SL.to_egm2008(nt2)
        @test r2.height[1] ≈ -17.0154953
        @test nt2.height[1] == 0.0  # non-mutating wrapper must not mutate input

        # SpaceLiDAR.Table
        g = SL.granule(GLAH06_fn)
        t = SL.points(g)
        h_before = t.height[1]
        SL.to_egm2008!(t)
        @test t.height[1] != h_before

        # H5Table (non-mutating: H5Table is read-only, returns fresh Table)
        ht = SL.table(g)
        r = SL.to_egm2008(ht)
        @test r isa SL.Table
        @test hasproperty(r, :height)

        # PartitionedH5Table (non-mutating: returns fresh PartitionedTable)
        g8 = SL.granule(ATL08_fn)
        pt = SL.table(g8)
        r = SL.to_egm2008(pt)
        @test r isa SL.PartitionedTable
        @test hasproperty(r, :height)
    end

    @testset "topex_to_wgs84!" begin
        # DataFrame
        df = DataFrame(longitude = [131.0], latitude = [-35.0], height = [100.0], height_reference = [50.0])
        SL.topex_to_wgs84!(df)
        @test df.height[1] ≈ 99.3 atol = 0.1
        @test df.height_reference[1] ≈ 49.3 atol = 0.1
        # CRS metadata stamped after projection
        @test DataAPI.metadata(df, "GEOINTERFACE:crs") == GeoFormatTypes.EPSG(4979)

        # Re-running on a table already in WGS84 must be a no-op
        df2 = DataFrame(longitude = [131.0], latitude = [-35.0], height = [100.0])
        DataAPI.metadata!(df2, "GEOINTERFACE:crs", GeoFormatTypes.EPSG(4979); style = :default)
        h_before = df2.height[1]
        SL.topex_to_wgs84!(df2)
        @test df2.height[1] == h_before  # not double-projected

        # Already-in-EGM2008 also blocks topex_to_wgs84! (would corrupt heights)
        df3 = DataFrame(longitude = [131.0], latitude = [-35.0], height = [100.0])
        DataAPI.metadata!(df3, "GEOINTERFACE:crs", GeoFormatTypes.EPSG(4326, 3855); style = :default)
        h_before = df3.height[1]
        SL.topex_to_wgs84!(df3)
        @test df3.height[1] == h_before

        # NamedTuple
        nt = (; longitude = [131.0], latitude = [-35.0], height = [100.0])
        r = SL.topex_to_wgs84!(nt)
        @test r.height[1] ≈ 99.3 atol = 0.1

        nt2 = (; longitude = [131.0], latitude = [-35.0], height = [100.0])
        r2 = SL.topex_to_wgs84(nt2)
        @test r2.height[1] ≈ 99.3 atol = 0.1
        @test nt2.height[1] == 100.0  # non-mutating wrapper must not mutate input

        # SpaceLiDAR.Table (from points, has height_reference)
        g = SL.granule(GLAH06_fn)
        t = SL.points(g)
        h_before = copy(t.height[1:3])
        SL.topex_to_wgs84!(t)
        @test all(t.height[1:3] .!= h_before)

        # H5Table (non-mutating)
        ht = SL.table(g)
        r = SL.topex_to_wgs84(ht)
        @test r isa SL.Table
        @test hasproperty(r, :height)
    end

    @testset "icesat_saturation_correct!" begin
        # Contract: input is real or missing (post-table()). NaN is not expected.
        # DataFrame with Union{Missing,Float64} columns
        df = DataFrame(
            height = Union{Missing,Float64}[100.0, 200.0, missing],
            saturation_correction = Union{Missing,Float64}[1.0, missing, 0.5],
        )
        SL.icesat_saturation_correct!(df)
        @test df.height[1] ≈ 101.0
        @test df.height[2] ≈ 200.0          # missing correction → unchanged
        @test ismissing(df.height[3])       # missing height stays missing

        # NamedTuple with Missing (simulates collected H5Table)
        nt = (; height = Union{Missing,Float64}[10.0, missing, 30.0],
                  saturation_correction = Union{Missing,Float64}[0.5, 1.0, missing])
        SL.icesat_saturation_correct!(nt)
        @test nt.height[1] ≈ 10.5
        @test ismissing(nt.height[2])       # missing height stays missing
        @test nt.height[3] ≈ 30.0           # missing correction → unchanged

        nt2 = (; height = Union{Missing,Float64}[10.0, missing, 30.0],
                    saturation_correction = Union{Missing,Float64}[0.5, 1.0, missing])
        r2 = SL.icesat_saturation_correct(nt2)
        @test r2.height[1] ≈ 10.5
        @test nt2.height[1] ≈ 10.0          # non-mutating wrapper must not mutate input

        # H5Table (non-mutating)
        g = SL.granule(GLAH06_fn)
        ht = SL.table(g)
        r = SL.icesat_saturation_correct(ht)
        @test r isa SL.Table
        @test hasproperty(r, :height)
    end

    @testset "icesat_quality" begin
        # DataFrame
        df = DataFrame(
            elev_use_flg = Int8[0, 1, 0, 0],
            sigma_att_flg = Int8[0, 0, 1, 0],
            i_numPk = Int32[1, 1, 1, 2],
            saturation_correction = [0.0, 0.0, 0.0, 0.0],
        )
        q = SL.icesat_quality(df)
        @test q == BitVector([1, 0, 0, 0])

        # NamedTuple
        nt = (;
            elev_use_flg = Int8[0, 0],
            sigma_att_flg = Int8[0, 0],
            i_numPk = Int32[1, 1],
            saturation_correction = [0.0, 4.0],
        )
        q = SL.icesat_quality(nt)
        @test q == BitVector([1, 0])

        # SpaceLiDAR.Table (GLAH06 has the quality columns)
        g = SL.granule(GLAH06_fn)
        t = SL.points(g)
        @test hasproperty(t, :height)
        # points() already computes quality as a column, but we can
        # also call icesat_quality on a Table that has the raw columns
        # Build a Table-like NamedTuple with the raw columns from the file
        ht = SL.table(g)
        # H5Table (collect dispatch)
        q = SL.icesat_quality(ht)
        @test q isa BitVector
        @test length(q) == DataAPI.nrow(ht)
    end

    @testset "collect" begin
        # H5Table → Table
        g = SL.granule(GLAH06_fn)
        ht = SL.table(g)
        t = collect(ht)
        @test t isa SL.Table
        @test hasproperty(t, :height)
        @test hasproperty(t, :latitude)
        @test length(t.height) == DataAPI.nrow(ht)

        # PartitionedH5Table → PartitionedTable
        g8 = SL.granule(ATL08_fn)
        pt = SL.table(g8)
        ct = collect(pt)
        @test ct isa SL.PartitionedTable
        @test hasproperty(ct, :height)
        @test length(ct.height) == DataAPI.nrow(pt)
        @test length(ct) == length(pt.tables)
    end

    @testset "hasproperty on Table" begin
        g = SL.granule(GLAH06_fn)
        t = SL.points(g)
        @test hasproperty(t, :height)
        @test hasproperty(t, :latitude)
        @test !hasproperty(t, :nonexistent_column)
        @test :height in propertynames(t)
    end
end

@testset "Proj" begin
    pipe = SL.topex_to_wgs84_ellipsoid()
    pts = Proj.proj_trans.(pipe, Proj.PJ_FWD, [(0, 0, 0)])
    @test pts[1][3] ≈ -0.700000000
end

@testset "Tables on granule" begin
    g3 = SL.granule(ATL03_fn)
    @test Tables.istable(g3)
    @test Tables.columnaccess(g3)
    t = Tables.columntable(g3)
    @test length(t.longitude) == 4295820

    df = DataFrame(t)
    SL.materialize!(df)
    SL.in_bbox(df, (min_x = 0.0, min_y = 0.0, max_x = 1.0, max_y = 1.0))
    SL.in_bbox!(df, (min_x = 0.0, min_y = 0.0, max_x = 1.0, max_y = 1.0))
    @test length(df.longitude) == 0

    g14 = SL.granule(GLAH14_fn)
    @test Tables.istable(g14)
    t = Tables.columntable(g14)
    @test length(t.longitude) == 729117
end

@testset "DataFrame from table()" begin
    # Verify all granule types produce consistent DataFrames via table()
    # table() returns raw (unfiltered) data from all tracks
    g = SL.granule(ATL03_fn)
    df = DataFrame(SL.table(g))
    @test nrow(df) == 4295820
    @test ncol(df) >= 10
    @test all(length(col) == nrow(df) for col in eachcol(df))
    @test_throws ErrorException SL.table(g; tracks = ["not_a_track"])

    g = SL.granule(ATL06_fn)
    df = DataFrame(SL.table(g))
    @test nrow(df) == 208632
    @test all(length(col) == nrow(df) for col in eachcol(df))

    g = SL.granule(ATL08_fn)
    df = DataFrame(SL.table(g))
    @test nrow(df) == 4981
    @test all(length(col) == nrow(df) for col in eachcol(df))

    g = SL.granule(ATL12_fn)
    df = DataFrame(SL.table(g))
    @test nrow(df) == 773
    @test all(length(col) == nrow(df) for col in eachcol(df))

    g = SL.granule(GEDI02_fn)
    df = DataFrame(SL.table(g))
    @test nrow(df) == 335462
    @test all(length(col) == nrow(df) for col in eachcol(df))

    g = SL.granule(GLAH06_fn)
    df = DataFrame(SL.table(g))
    @test nrow(df) == 5840
    @test all(length(col) == nrow(df) for col in eachcol(df))

    g = SL.granule(GLAH14_fn)
    df = DataFrame(SL.table(g))
    @test nrow(df) == 972280
    @test all(length(col) == nrow(df) for col in eachcol(df))
end

@testset "Table from points" begin
    # PartionedTable
    g = SL.granule(ATL08_fn)
    points = SL.points(g, step = 1)
    @test points isa SL.AbstractTable
    @test points isa SL.PartitionedTable

    t = SL.add_info(points)
    tt = SL.add_id(t)

    df = DataFrame(tt)
    first(df.id) == g.id
    first(df.version) == 6
    @test metadata(df) == metadata(points)
    metadata(df)["id"] == g.id
    metadata(df)["version"] == 6

    # Single table
    g = SL.granule(GLAH14_fn)
    points = SL.points(g, step = 1)
    @test points isa SL.AbstractTable
    @test points isa SL.Table

    t = SL.add_info(points)
    tt = SL.add_id(t)

    df = DataFrame(tt)
    first(df.id) == g.id
    first(df.version) == 32
    @test metadata(df) == metadata(points)
    metadata(df)["id"] == g.id
    metadata(df)["version"] == 32
end

@testset "GeoInterface" begin
    g = SL.granule(ATL08_fn)
    GeoInterface.testgeometry(g)
end

@testset "GeoInterface.crs per granule" begin
    # ICESat-2: ITRF2014 3D
    @test GeoInterface.crs(SL.granule(ATL03_fn)) == GeoFormatTypes.EPSG(7912)
    @test GeoInterface.crs(SL.granule(ATL06_fn)) == GeoFormatTypes.EPSG(7912)
    @test GeoInterface.crs(SL.granule(ATL08_fn)) == GeoFormatTypes.EPSG(7912)
    @test GeoInterface.crs(SL.granule(ATL12_fn)) == GeoFormatTypes.EPSG(7912)

    # GEDI: ITRF2014 3D
    @test GeoInterface.crs(SL.granule(GEDI02_fn)) == GeoFormatTypes.EPSG(7912)

    # ICESat: TOPEX/Poseidon (no EPSG; described as a ProjString).
    # PROJ accepts the string, which is the contract that matters for downstream code.
    crs_glah06 = GeoInterface.crs(SL.granule(GLAH06_fn))
    @test crs_glah06 isa GeoFormatTypes.ProjString
    @test occursin("a=6378136.3", crs_glah06.val)
    @test Proj.CRS(crs_glah06.val) isa Proj.CRS  # round-trips through PROJ
    @test GeoInterface.crs(SL.granule(GLAH14_fn)) == crs_glah06
end

struct UnknownGranule <: SpaceLiDAR.Granule end

@testset "GeoInterface granule accessors" begin
    g = SL.granule(GLAH06_fn)

    @test GeoInterface.geomtrait(g) isa GeoInterface.MultiPointTrait
    @test GeoInterface.ncoord(g) == 3

    n = GeoInterface.ngeom(g)
    @test n > 0

    # getgeom without index returns a lazy iterator of (lon, lat, height)
    geoms = GeoInterface.getgeom(g)
    first_pt = first(geoms)
    @test length(first_pt) == 3

    # getgeom with index returns a single tuple
    pt = GeoInterface.getgeom(g, 1)
    @test length(pt) == 3
    @test pt == first_pt

    # extent matches bounds()
    ext = GeoInterface.extent(g)
    @test ext isa Extent
    @test ext == convert(Extent, SL.bounds(g))

    # crs fallback for an unknown granule type
    @test GeoInterface.crs(UnknownGranule()) == GeoFormatTypes.EPSG(4326)
end

@testset "Line and Point geometries" begin
    l = SL.Line([0.0, 1.0, 2.0], [10.0, 11.0, 12.0], [100.0, 101.0, 102.0])
    p = SL.Point(1.0, 2.0, 3.0)

    @test GeoInterface.isgeometry(SL.Line)
    @test GeoInterface.geomtrait(l) isa GeoInterface.LineStringTrait
    @test GeoInterface.geomtrait(p) isa GeoInterface.PointTrait

    @test GeoInterface.ncoord(l) == 3
    @test GeoInterface.ngeom(l) == 3
    sub = GeoInterface.getgeom(l, 2)
    @test sub isa SL.Point
    @test GeoInterface.getcoord(sub, 1) == 1.0
    @test GeoInterface.getcoord(sub, 2) == 11.0
    @test GeoInterface.getcoord(sub, 3) == 101.0

    @test GeoInterface.ncoord(p) == 3
    @test GeoInterface.getcoord(p, 1) == 1.0
    @test GeoInterface.getcoord(p, 2) == 2.0
    @test GeoInterface.getcoord(p, 3) == 3.0
end

@testset "track_angle vector methods" begin
    # raw longitude/latitude vector method (geom.jl)
    angle = SL.track_angle([0.0, 0.0, 1.0], [0.0, 1.0, 1.0])
    @test length(angle) == 3
    @test angle[1] == angle[2]   # first angle is set to the second
    @test angle[3] ≈ 90.0
    @test_throws "`longitude` and `latitude` should have the same length." SL.track_angle([0.0, 1.0], [0.0])

    # granule + latitude-vector method (ICESat-2.jl)
    g = SL.granule(ATL08_fn)
    lats = Real[0.0, 30.0, 60.0]
    av = SL.track_angle(g, lats)
    @test length(av) == 3
    @test av[1] ≈ SL.track_angle(g, 0.0) atol = 1e-6
end

@testset "utils helpers" begin
    # granule() error paths
    @test_throws "Granule must be a .h5 file" SL.granule("foo.txt")
    @test_throws "Unknown granule." SL.granule("foo.h5")

    gs = SL.granules("data")

    # instantiate matches local files
    inst = SL.instantiate(gs, "data")
    @test length(inst) == length(gs)
    @test all(isfile, SL.url.(inst))

    # write_urls: in-place file, returns-path file, and IOStream variants
    tmp = SL.write_urls(gs)
    @test isfile(tmp)
    @test length(readlines(tmp)) == length(gs)
    rm(tmp)

    named = tempname()
    ret = SL.write_urls(named, gs)
    @test ret == abspath(named)
    @test length(readlines(named)) == length(gs)
    rm(named)

    # isvalid: real granule is valid, missing file is not
    @test SL.isvalid(gs[1])
    bogus = SL.granule(GLAH06_fn)
    bogus.url = "/nonexistent/path.h5"
    @test !SL.isvalid(bogus)

    # filter_rgt keeps only matching rgt/cycle
    g8 = SL.granule(ATL08_fn)
    i = SL.info(g8)
    @test length(SL.filter_rgt([g8], i.rgt, i.cycle)) == 1
    @test length(SL.filter_rgt([g8], i.rgt + 1, i.cycle)) == 0

    # Extent → NamedTuple conversion
    nt = convert(NamedTuple, Extent(X = (1.0, 3.0), Y = (2.0, 4.0)))
    @test nt == (min_x = 1.0, min_y = 2.0, max_x = 3.0, max_y = 4.0)
end

@testset "GEDI info helpers" begin
    gg = SL.granule(GEDI02_fn)
    @test SL.mission(gg) == :GEDI
    @test SL.info(gg).type == :GEDI02_A
    @test SL.sproduct(gg) == :GEDI02_A

    # v1 (non-V002) filename parsing is currently broken: the else-branch in
    # gedi_info does not assign `sub_orbit`/`pge_version`, which the returned
    # NamedTuple references, so it throws UndefVarError.
    @test_broken SL.gedi_info("GEDI02_A_2019110014613_O01991_T04905_02_001_01.h5").type == :GEDI02_A
end
