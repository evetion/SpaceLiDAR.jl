import GeoDataFrames.AG  # ArchGDAL
using Distances

function linpol(ax, bx, ay, by, x)
    # ax, bx = sort([ax, bx])
    factor = (x - ax) / (bx - ax)
    ay + (by - ay) * factor
end

function z_along_line(line, point)
    x = AG.getx(point, 0)
    # point left of line, take first z
    fx, fy, fz = AG.getpoint(line, 0)
    lx, ly, lz = AG.getpoint(line, AG.ngeom(line) - 1)
    fx, lx = sort([fx, lx])
    if x <= fx
        @info "Before line"
        return fz
    elseif x >= lx
        @info "Behind line"
        return lz
    else
        for i ∈ 0:AG.ngeom(line)-2
            xa, ay, za = AG.getpoint(line, i)
            xb, by, zb = AG.getpoint(line, i + 1)
            if xa < x < xb || xa > x > xb
                return linpol(xa, xb, za, zb, x)
            end
        end
    end
    @error "Interpolation failed"
    NaN
end

"""
Split a linestring if the next point is further than `distance`.
Not using Haversine here, as we want to split on meridians and such.
"""
function splitline(line::AG.IGeometry, distance = 1.0)
    points = [AG.getpoint(line, i - 1) for i = 1:AG.ngeom(line)]
    splits = Vector{Int}([0])
    for i ∈ 1:length(points)-1
        d = Euclidean()(points[i][1:2], points[i+1][1:2])
        if d > distance
            push!(splits, i)
        end
    end
    if length(splits) == 1
        return line
    else
        lines = Vector{Vector{Tuple{Float64,Float64,Float64}}}()
        push!(splits, length(points))
        for i ∈ 1:length(splits)-1
            line = points[splits[i]+1:splits[i+1]]
            push!(lines, line)
        end
        filter!(x -> length(x) > 1, lines)  # filter out single point linestrings
        return AG.createmultilinestring(lines)
    end
end

function splitline(table, distance = 1.0)
    rows = Vector{NamedTuple}()
    for row in table
        geom = splitline(row.geom, distance)
        if AG.getgeomtype(geom) == AG.GDAL.wkbMultiLineString25D
            for i = 1:AG.ngeom(geom)
                push!(rows, merge(row, (geom = AG.getgeom(geom, i - 1),)))
            end
        else
            push!(rows, merge(row, (geom = geom,)))
        end
    end
    Table(rows)
end

function clip!(table, box::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}})
    polygon = createpolygon([
        [box.min_x, box.min_y],
        [box.max_x, box.min_y],
        [box.max_x, box.max_y],
        [box.min_x, box.max_y],
        [box.min_x, box.min_y],
    ])
    table.geom .= clip.(table.geom, Ref(polygon))
end

function clip(geom::AG.IGeometry, polygon::AG.IGeometry)
    if AG.ngeom(geom) > 0 && AG.intersects(geom, polygon)
        AG.intersection(geom, polygon)
    else
        AG.createlinestring()
    end
end

function intersect(
    a::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}},
    b::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}},
)
    !(b.min_x > a.max_x || b.max_x < a.min_x || b.min_y > a.max_y || b.max_y < a.min_y)
end
