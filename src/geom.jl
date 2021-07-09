using TypedTables

const deg2km = 111.19492664455875
const earth_radius_m = 6378.137 * 1000

function makeline(x, y, z)
    mask = .~isnan.(z)
    if sum(mask) > 1  # skip creating invalid lines with 0 or 1 point
        line = GDF.AG.creategeom(GDF.AG.GDAL.wkbLineString25D)
        GDF.AG.addpoint!.(Ref(line), x[mask], y[mask], z[mask])
        @assert AG.isvalid(line)
    else
        line = AG.createlinestring()
    end
    line
end

function makepoint(x, y, z)
    GDF.AG.createpoint.(x, y, z)
end

# function Base.show(io::IO, geom::GDF.AG.AbstractGeometry)
#     if geom.ptr == C_NULL
#         print(io, "NULL Geometry")
#     else
#         print(io, "$(GDF.AG.getgeomtype(geom)) geometry")
#     end
# end

function envelope_polygon(geom::GDF.AG.AbstractGeometry)
    e = GDF.AG.envelope(geom)
    polygon = GDF.AG.createpolygon()
    ring = GDF.AG.createlinearring([(e.MinX, e.MinY), (e.MaxX, e.MinY), (e.MaxX, e.MaxY), (e.MinX, e.MaxY), (e.MinX, e.MinY)])
    GDF.AG.addgeom!(polygon, ring)
    polygon
end

"""Calculate angle of direction in degrees where North is 0° for a Table."""
function angle!(t::FlexTable)
    # this assumes the table is ordered by time (ascending)
    t.angle = angle(t.x, t.y)
end

"""Calculate angle of direction in degrees where North is 0°."""
function angle(lon, lat)
    length(lon) == length(lat) || error("`lon` and `lat` should have the same length.")
    angle = zeros(length(lon))
    prev = zeros(2)
    for i ∈ 1:length(lon)
        angle[i] = rad2deg(atan(lon[i] - prev[1], lat[i] - prev[2]))
        prev[1] = lon[i]
        prev[2] = lat[i]
    end
    angle[1] = angle[2]
    return angle
end

"""Shift `lon` and `lat` with `distance` m in direction `angle`, where North is 0°."""
function shift(lon, lat, angle, distance)
    length(lon) == length(lat) || error("`lon` and `lat` should have the same length.")

    θ = deg2rad(angle)
    δ = distance / earth_radius_m
    ϕ = deg2rad(lat)
    λ = deg2rad(lon)

    # Distances.jl only gives us Haversine, so this is the inverse
    ϕnew = asin(
            sin(ϕ) * cos(δ) + cos(ϕ) * sin(δ) * cos(θ)
        )
    λnew = λ + atan(
            sin(θ) * sin(δ) * cos(ϕ), cos(δ) - sin(ϕ) * sin(ϕnew)
    )
    return rad2deg(λnew), rad2deg(ϕnew)
end
