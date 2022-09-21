using GeoInterface

const earth_radius_m = 6378.137 * 1000

abstract type Geometry end
struct Line{T} <: Geometry where {T<:Real}
    x::Vector{T}
    y::Vector{T}
    z::Vector{T}
end
struct Point{T} <: Geometry where {T<:Real}
    c::Vector{T}
end

GeoInterface.isgeometry(geom::Type{<:Geometry})::Bool = true
GeoInterface.geomtrait(::Line) = LineStringTrait()
GeoInterface.geomtrait(::Point) = PointTrait()

GeoInterface.ncoord(::LineStringTrait, geom::Line) = 3
GeoInterface.ngeom(::LineStringTrait, geom::Line) = length(geom.x)
GeoInterface.getgeom(::LineStringTrait, geom::Line, i) = Point([geom.x[i], geom.y[i], geom.z[i]])

GeoInterface.ncoord(::PointTrait, geom::Point) = 3
GeoInterface.getcoord(::PointTrait, geom::Line, i) = geom.c[i]


"""
    angle!(table)

Sets the `angle` column in `table` as returned from [`points`](@ref). See [`angle`](@ref) for details.
"""
function angle!(t)
    # this assumes the DataFrame is ordered by time (ascending)
    t.angle = angle(t.longitude, t.latitude)
    t
end

"""
    angle(longitude::Vector{Real}, latitude::Vector{Real})

Calculate the angle of direction from previous points in [°] where North is 0°.
Points are given as `longitude` and `latitude` pairs in their own vector.
The angle for the first point is undefined and set to the second.

Returns a `Vector{Real}` of angles
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

Shift `longitude` and `latitude` with `distance` in [m] in direction `angle`, where North is 0°.
Returns a tuple of the shifted coordinates: `(longitude, latitude)`. Useful for offsetting
SpaceLiDAR points to the left or right of the track, in combination with [`angle`](@ref).
"""
function shift(longitude, latitude, angle, distance)
    θ = deg2rad(angle)
    δ = distance / earth_radius_m
    ϕ = deg2rad(latitude)
    λ = deg2rad(longitude)

    # Distances.jl only gives us Haversine, so this is the inverse
    ϕnew = asin(
        sin(ϕ) * cos(δ) + cos(ϕ) * sin(δ) * cos(θ),
    )
    λnew = λ + atan(
        sin(θ) * sin(δ) * cos(ϕ), cos(δ) - sin(ϕ) * sin(ϕnew),
    )
    return rad2deg(λnew), rad2deg(ϕnew)
end
