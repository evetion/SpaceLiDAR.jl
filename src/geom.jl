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
Point(x, y, z) = Point([x, y, z])

GeoInterface.isgeometry(geom::Type{<:Geometry})::Bool = true
GeoInterface.geomtrait(::Line) = LineStringTrait()
GeoInterface.geomtrait(::Point) = PointTrait()

GeoInterface.ncoord(::LineStringTrait, geom::Line) = 3
GeoInterface.ngeom(::LineStringTrait, geom::Line) = length(geom.x)
GeoInterface.getgeom(::LineStringTrait, geom::Line, i) = Point([geom.x[i], geom.y[i], geom.z[i]])

GeoInterface.ncoord(::PointTrait, geom::Point) = 3
GeoInterface.getcoord(::PointTrait, geom::Point, i) = geom.c[i]



"""
    angle!(table)

Sets the `angle` column in `table` as returned from [`points`](@ref). See [`angle`](@ref) for details.
"""
function angle!(t)
    # this assumes the DataFrame is ordered by time (ascending)
    t.angle = track_angle(t.longitude, t.latitude)
    t
end

# ICESat-2 half an orbit is ~190°, so half of that is ~95° similar for ICESat-1
# ICESat-2 half an orbit is ~170, so half of that is ~85°
"""
    greatcircle(φ₁, λ₁, φ₂, λ₂, nparts=89)

Implementation of https://en.wikipedia.org/wiki/Great-circle_navigation.
Find all `nparts` intermediate angles between two points on a sphere.

Used to precalculate approximate angles of the groundtrack for the SpaceLiDAR satellites
in [`track_angle(::Granule, lat)`](@ref).
"""
function greatcircle(φ₁, λ₁, φ₂, λ₂, nparts = 88)

    λ₁₂ = λ₂ - λ₁  # longitudes
    φ₁₂ = φ₂ - φ₁  # latitudes
    λ₁₂ > 180 && (λ₁₂ -= 360)
    λ₁₂ < -180 && (λ₁₂ += 360)

    α₁ = atan(cosd(φ₂) * sind(λ₁₂), cosd(φ₁) * sind(φ₂) - sind(φ₁) * cosd(φ₂) * cosd(λ₁₂))
    # α₂ = atan(cosd(φ₁) * sind(λ₁₂), -cosd(φ₂) * sind(φ₁) + sind(φ₂) * cosd(φ₁) * cosd(λ₁₂))

    σ₁₂ =
        atan(
            sqrt((cosd(φ₁) * sind(φ₂) - sind(φ₁) * cosd(φ₂) * cosd(λ₁₂))^2 + (cosd(φ₂) * sind(λ₁₂))^2),
            sind(φ₁) * sind(φ₂) + cosd(φ₁) * cosd(φ₂) * cosd(λ₁₂),
        )

    α₀ = atan(sin(α₁) * cosd(φ₁), sqrt(cos(α₁)^2 + sin(α₁)^2 * sind(φ₁)^2))
    σ₀₁ = atan(tand(φ₁), cos(α₁))
    σ₀₂ = σ₀₁ + σ₁₂

    λ₀₁ = atan(sin(α₀) * sin(σ₀₁), cos(σ₀₁))
    λ₀ = deg2rad(λ₁) - λ₀₁

    angles = zeros(nparts + 1)
    latitudes = zeros(nparts + 1)
    longitudes = zeros(nparts + 1)
    for p = 1:nparts+1
        σ = σ₀₁ + (p - 1) * (σ₀₂ / nparts)

        ϕ = atan(cos(α₀) * sin(σ), sqrt(cos(σ)^2 + sin(α₀)^2 * sin(σ)^2))
        λ = atan(sin(α₀) * sin(σ), cos(σ)) + λ₀
        α = atan(tan(α₀), cos(σ))
        angles[p] = rad2deg(α)
        latitudes[p] = rad2deg(ϕ)
        longitudes[p] = rad2deg(λ)
    end
    return latitudes, longitudes, angles
end


"""
    track_angle(longitude::Vector{Real}, latitude::Vector{Real})

Calculate the angle of direction from previous points in [°] where North is 0°.
Points are given as `longitude` and `latitude` pairs in their own vector.
The angle for the first point is undefined and set to the second.

Because of the inherent noise in the point locations, the angles will be noisy too, especially for
ICESat-2 ATL03. Either smooth the results or use an approximation using [`track_angle(::Granule, ::Int)`](@ref).

Returns a `Vector{Real}` of angles.
"""
function track_angle(longitude, latitude)
    length(longitude) == length(latitude) || error("`longitude` and `latitude` should have the same length.")
    angle = zeros(length(longitude))
    prev = zeros(2)
    for i ∈ 1:length(longitude)
        angle[i] = atand(longitude[i] - prev[1], latitude[i] - prev[2])
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
