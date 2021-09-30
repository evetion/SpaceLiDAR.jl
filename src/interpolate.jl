using GeoArrays
using StaticArrays
using ProgressMeter
using NearestNeighbors
using StarTIN
using Distances

function interpolate!(ga::GeoArray, t, r=500.)
    tt = hcat(t.x, t.y)
    ttt = permutedims(tt)
    tree = BallTree(ttt, Haversine())
    ui, uj = Base.size(ga)[1:2]
    p = Progress(length(ga), 1, "Interpolating...")
    Threads.@threads for i in 1:ui
        Threads.@threads for j in 1:uj
            coords = centercoords(ga, SVector{2}(i, j))::SArray{Tuple{2},Float64,1,2}
            ga.A[i, j, 1] = idw(coords, tree, r, t.z, ttt)
            next!(p)
        end
    end
end

function interpolate_nni!(ga::GeoArray, t, r=1., scale=100.0)
    tt = hcat(t.x .* scale, t.y .* scale, t.z)
    ttt = permutedims(tt)
    dt = DT()
    @time insert!(dt, ttt)
    StarTIN.info(dt)
    ui, uj = size(ga)[1:2]
    p = Progress(length(ga), 1, "Interpolating...")
    for i in 1:ui
        for j in 1:uj
            coords = centercoords(ga, SVector{2}(i, j))::SArray{Tuple{2},Float64,1,2}
            @inbounds ga.A[i, j, 1] = interpolate_laplace(dt, coords[1] * scale, coords[2] * scale)
            next!(p)
        end
    end
end

function idw(coords, tree, r, values, coordinates, power=2)
    idxs = inrange(tree, coords, r)
    if length(idxs) == 0
        return NaN32
    else
        distances = colwise(Haversine(), Float32.(coords), coordinates[:,idxs])
        ws = 1.0f0 ./ distances.^power # .* view(uncertainty, idxs)
        Σw = sum(ws)

        if isinf(Σw)
            j = findfirst(iszero, distances)
            μ = values[idxs[j]]
        else
            ws ./= Σw
            vs  = view(values, idxs)
            μ = sum(ws[i] * vs[i] for i in eachindex(vs))
        end
        return μ
    end
end
