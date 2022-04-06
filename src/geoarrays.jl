using Statistics
using GeoArrays
using StaticArrays

strategy = GeoArrays.Center()

function sample(ga::GeoArray, x::Real, y::Real, buffer = 0, reducer = median)
    I = SVector{2}(x, y)
    i, j = indices(ga, I, strategy)
    0 < i - buffer <= Base.size(ga.A)[1] || return NaN
    0 < j - buffer <= Base.size(ga.A)[2] || return NaN
    0 < i + buffer <= Base.size(ga.A)[1] || return NaN
    0 < j + buffer <= Base.size(ga.A)[2] || return NaN
    data = collect(skipmissing(ga.A[i-buffer:i+buffer, j-buffer:j+buffer, 1]))
    mask = isfinite.(data)
    if sum(mask) == 0
        return Inf
    else
        return reducer(data[mask])
    end
end
