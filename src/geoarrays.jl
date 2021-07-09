using Statistics
using GeoArrays
using StaticArrays

function indices(ga::GeoArray, p::SVector{2,Float32})
    map(x -> round(Int, x), inv(ga.f)(p)::SVector{2,Float64}) .+ 1
end
function indices(ga::GeoArray, p::SVector{2,Float64})
    map(x -> round(Int, x), inv(ga.f)(p)::SVector{2,Float64}) .+ 1
end
function Base.getindex(ga::GeoArray, I::SVector{2,Float32}, buffer=0)
    (i, j) = indices(ga, I)
    return ga[i - buffer:i + buffer, j - buffer:j + buffer, :]
end
Base.getindex(ga::GeoArray, I::Vararg{Float32,2}) = Base.getindex(ga, SVector{2}(I))

function sample(ga::GeoArray, x::Real, y::Real, buffer=0, reducer=median)
    I = SVector{2}(x, y)
    i, j = indices(ga, I)
    0 < i - buffer <= Base.size(ga.A)[1] || return NaN
    0 < j - buffer <= Base.size(ga.A)[2] || return NaN
    0 < i + buffer <= Base.size(ga.A)[1] || return NaN
    0 < j + buffer <= Base.size(ga.A)[2] || return NaN
    # (all((i, j) .> (0, 0)) && all(Base.size(ga.A)[1:2] >= (i, j))) || return NaN
    data = ga.A[i - buffer:i + buffer, j - buffer:j + buffer, 1]
    mask = isfinite.(data)
    if sum(mask) == 0
        return NaN
    else
        return reducer(data[mask])
    end
end
