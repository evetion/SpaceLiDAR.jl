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
using GeoArrays
using Statistics
using CSV

limit = 100
# const seasia = (min_x = 92., min_y = -10.0, max_x = 142.0, max_y = 21.0)
const seasia = (min_x = 102., min_y = 8.0, max_x = 107.0, max_y = 12.0)  # vietnam

# Based on SE Asia
bad = [
    "ATL08_20190308110827_10690208_003_01.h5",
    "ATL08_20200514143433_07490708_003_01.h5",
    "ATL08_20181206155406_10540108_003_01.h5",
    "ATL08_20181129035056_09390114_003_01.h5",
    "ATL08_20200705141328_01560807_003_01.h5", # segment 7?
    "ATL08_20200705142030_01560808_003_01.h5", # segment 8?
    "ATL08_20200618151228_12840707_003_01.h5", # segment 7?
    "ATL08_20200618151930_12840708_003_01.h5", # segment 8?
    "ATL08_20200806130651_06440807_003_01.h5", # segment 7?
    "ATL08_20200806131353_06440808_003_01.h5", # segment 8?
    "ATL08_20191219120550_12760514_003_01.h5", # segment 14?
    "ATL08_20191219103835_12760501_003_01.h5", # segment 1?
    "ATL08_20191129010015_09640507_003_01.h5", # segment 7?
    "ATL08_20191129010717_09640508_003_01.h5", # segment 8?
    "ATL08_20191102115253_05590501_003_01.h5", # segment 1?
    "ATL08_20191102132008_05590514_003_01.h5", # segment 14?
    "ATL08_20200313054344_11840601_003_01.h5", # segment 1
    "ATL08_20200313071058_11840614_003_01.h5", # segment 14
    "ATL08_20191102013254_05520507_003_01.h5",
    "ATL08_20191102013956_05520508_003_01.h5",
    "ATL08_20200417062841_03320701_003_01.h5",
]

# These are large, worldwide granules, so limit or search for them
gedi_path = "/mnt/ec66e171-5639-4c62-9d2c-08e81c462669/gedi/L2A/v1"
# gedi_granules = granules_from_folder(gedi_path)[1:limit]

# If you've downloaded everything locally:
gedi_granules = find(:GEDI, "GEDI02_A", seasia)
gedi_granules = SpaceLiDAR.instantiate(gedi_granules, gedi_path)

# These are smaller, already cut out granules
icesat_path = "/mnt/ec66e171-5639-4c62-9d2c-08e81c462669/icesat2/ATL08/v03"
# icesat_granules = granules_from_folder(icesat_path)[1:limit * 50]
# If you've downloaded everything locally:
icesat_granules = find(:ICESat2, "ATL08", seasia)
icesat_granules = SpaceLiDAR.instantiate(icesat_granules, icesat_path)
filter!(!SpaceLiDAR.is_blacklisted, icesat_granules)
filter!(!g -> g.id in bad, icesat_granules)

granules = vcat(icesat_granules, gedi_granules)
granules_v = in_bbox(granules, seasia)  # bbox filtering based on header information, works only for ICESat-2


# Retrieve linestrings from granules, note the decimation by step=10
alllines = Vector{Table}()
@showprogress 1 "Reading..." for granule in granules_v
    if SpaceLiDAR.test(granule)
        try
            lines = Table(SpaceLiDAR.lines(granule, step=1, quality=1))
            push!(alllines, lines)
        catch e
            if e isa InterruptException
                break
            else
                @warn "$(granule.id) failed with $e"
            end
        end
    end
end

t = vcat(alllines...)
SpaceLiDAR.clip!(t, seasia)
t = SpaceLiDAR.splitline(t, 0.1)
tt = t[AG.ngeom.(t.geom) .> 0]  # skip empty linestrings
GDF.write("alllines.gpkg", tt)


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
                # An intersection points of 2 2.5D lines gets a Z halfway between the lines
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

df = Table(intersections)
GDF.write("intersections.gpkg", df)



# Find the granules that should be blacklisted

# n_outlier = 25
mean_threshold = 10  # Only for lowland, we can expect 10m errors in sloped terrain!

# If you already have an intersections gpkg
# fn = "intersections.gpkg"
# df = TypedTables.Table(GDF.read(fn))

# Generate mask with land polygons (I've used Natural Earth)
# gdal_rasterize -l ne_10m_land -burn 1.0 -tr 0.005 0.005 -init 0.0 -te -180.0 -90.0 180.0 90.0 -ot Byte -at -of GTiff -co COMPRESS=DEFLATE -co TILED=yes ne_10m_land.shp
mask_fn = "world_mask.tif"
mask = GeoArrays.read(mask_fn)

function Base.in(point::ArchGDAL.IGeometry, mask::GeoArray)
    x = ArchGDAL.getx(point, 0)
    y = ArchGDAL.gety(point, 0)
    try
        Bool(mask[x,y][1])
    catch BoundsError
        false
    end
end
df = df[in.(df.geom, Ref(mask))]

function unify(t)
    ids = unique(vcat(t.a, t.b))
    list = Dict{String,Vector{Float64}}()
    for row in df
        haskey(list, row.a) || (list[row.a] = Vector{Float64}())
        haskey(list, row.b) || (list[row.b] = Vector{Float64}())
        push!(list[row.a], row.diff)
        push!(list[row.b], -row.diff)
    end
    r = collect(values(list))
    t = GDF.DataFrame(granule=collect(keys(list)), diff=sum.(r), med=Statistics.median.(r), mean=Statistics.mean.(r), count=length.(r))
end
# Dump to csv for manual checks
CSV.write("outlier_granules.csv", unify(df))

outliers = Vector{String}()
xm = 9999
while xm >= mean_threshold
    t = unify(df)
    t.mean .= abs.(t.mean)
    sort!(t, :mean, rev=true)
    xm = t.mean[1]
    x = t.granule[1]
    push!(outliers, x)
    mask = (df.a .!= x) .& (df.b .!= x)
    df = df[mask]
end
@info "We think these outliers are bad:"
@info outliers
