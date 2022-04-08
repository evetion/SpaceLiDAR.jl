const earth_radius_m = 6378.137 * 1000

function makeline(x, y, z)
    mask = .~isnan.(z)
    if sum(mask) > 1  # skip creating invalid lines with 0 or 1 point
        line = GDF.AG.creategeom(GDF.AG.wkbLineString25D)
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

function envelope_polygon(geom::GDF.AG.AbstractGeometry)
    e = GDF.AG.envelope(geom)
    polygon = GDF.AG.createpolygon()
    ring = GDF.AG.createlinearring([(e.MinX, e.MinY), (e.MaxX, e.MinY), (e.MaxX, e.MaxY), (e.MinX, e.MaxY), (e.MinX, e.MinY)])
    GDF.AG.addgeom!(polygon, ring)
    polygon
end

"""Calculatitudee angle of direction in degrees where North is 0° for a DataFrame."""
function angle!(t)
    # this assumes the DataFrame is ordered by time (ascending)
    t.angle = angle(t.x, t.y)
    t
end

"""
    angle(longitude::Vector{Number}, latitude::Vector{Number})

Calculate the angle of direction from previous points in degrees where North is 0°.
Points are given as `longitude` and `latitude` pairs in their own vector.
The angle for the first point is undefined and set to the second.

Returns a `Vector{Number}` of angles
"""
function angle(longitude, latitude)
    length(longitude) == length(latitude) || error("`longitude` and `latitude` should have the same length.")
    angle = zeros(length(longitude))
    prev = zeros(2)
    for i ∈ 1:length(longitude)
        angle[i] = rad2deg(atan(longitude[i] - prev[1], latitude[i] - prev[2]))
        prev[1] = longitude[i]
        prev[2] = latitude[i]
    end
    angle[1] = angle[2]
    return angle
end

"""
    shift(longitude, latitude, angle, distance)

Shift `longitude` and `latitude` with `distance` m in direction `angle`, where North is 0°.
Returns a tuple of the shifted coordinates: `(longitude, latitude)`
"""
function shift(longitude, latitude, angle, distance)
    θ = deg2rad(angle)
    δ = distance / earth_radius_m
    ϕ = deg2rad(latitude)
    λ = deg2rad(longitude)

    # Distances.jl only gives us Haversine, so this is the inverse
    ϕnew = asin(
            sin(ϕ) * cos(δ) + cos(ϕ) * sin(δ) * cos(θ)
        )
    λnew = λ + atan(
            sin(θ) * sin(δ) * cos(ϕ), cos(δ) - sin(ϕ) * sin(ϕnew)
    )
    return rad2deg(λnew), rad2deg(ϕnew)
end
