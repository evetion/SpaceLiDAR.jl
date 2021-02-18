"""Try to detect outliers in ICESat-2 & GEDI granules
by cross comparing them."""

using SpaceLiDAR
using Glob
using GeoDataFrames; const GDF = GeoDataFrames
using TypedTables
using ArchGDAL; const AG = ArchGDAL
using Dates
using ProgressMeter
using Combinatorics

limit = 100
vietnam = (min_x = 102., min_y = 8.0, max_x = 107.0, max_y = 12.0)

# These are large, worldwide granules, so limit or search for them
gedi_path = "/mnt/ec66e171-5639-4c62-9d2c-08e81c462669/gedi/L2A/v1"
gedi_granules = granules_from_folder(gedi_path)[1:limit]

# If you've downloaded everything locally:
# gedi_granules = find(:GEDI, "GEDI02_A", vietnam)
# gedi_granules = SpaceLiDAR.instantiate(gedi_granules, gedi_path)

# These are smaller, already cut out granules
icesat_path = "/mnt/ec66e171-5639-4c62-9d2c-08e81c462669/icesat2/ATL08/v03"
icesat_granules = granules_from_folder(icesat_path)[1:limit * 100]

granules = vcat(icesat_granules, gedi_granules)
granules_v = in_bbox(granules, vietnam)

# Retrieve linestrings from granules, note the decimation by step=10
alllines = []
@showprogress 1 "Reading..." for granule in granules_v
    if SpaceLiDAR.test(granule)
        try
            lines = Table(SpaceLiDAR.lines(granule, step=10, quality=1))
            push!(alllines, lines)
        catch e
            @warn "$(granule.id) failed with e"
        end
    end
end
t = vcat(alllines...)
t = SpaceLiDAR.splitline(t)
GDF.write("alllines.gpkg", t)


intersections = Vector{NamedTuple}()
@showprogress 1 "Intersections..." for (a, b) in combinations(t, 2)
    if a.granule == b.granule
        continue
    else
        if (AG.ngeom(a.geom) > 1) && (AG.ngeom(b.geom) > 1) && AG.intersects(a.geom, b.geom)
            points = AG.intersection(a.geom, b.geom)
        else
            continue
        end
        type = AG.getgeomtype(points)
        if type == AG.GDAL.wkbMultiPoint25D
            for i ∈ 1:AG.ngeom(points)
                p = AG.getgeom(points, i - 1)  # starts with 0
                z = SpaceLiDAR.z_along_line(a.geom, p)
                z = (z - AG.getz(p, 0)) * 2
                push!(intersections, (a = a.granule, b = b.granule, diff = z, geom = p))
            end
        elseif type == AG.GDAL.wkbPoint25D
            p = points
            z = SpaceLiDAR.z_along_line(a.geom, p)
            z = (z - AG.getz(p, 0)) * 2
            push!(intersections, (a = a.granule, b = b.granule, diff = z, geom = p))
        elseif type == AG.GDAL.wkbLineString25D
            continue  # no intersection
        end
    end
end

tt = Table(intersections)
GDF.write("intersections.gpkg", tt)
