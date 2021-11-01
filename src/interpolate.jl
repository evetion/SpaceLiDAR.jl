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

"""
Adjusted Inverse Distance Weighting (AIDW) algorithm by [^li2018].

Adjusts the normal IDW by process by assigning extra weights
based on the distribution of points, ensuring that points
all around are used normally, but that points in a clustered
distribution are penalized when 'shielded' by a nearby point.

This is useful in interpolation SpaceLiDAR data with very irregular
distributions.

[^li2018] Li, Zhengquan, Kuo Wang, Hao Ma, and Yaoxiang Wu. 2018. ‘An Adjusted Inverse Distance Weighted Spatial Interpolation Method’. In Proceedings of the 2018 3rd International Conference on Communications, Information Management and Network Security (CIMNS 2018). Shenzhen, China: Atlantis Press. https://doi.org/10/gm9kp5.
"""
function aidw(coords, tree, r, values, coordinates, power=2)
    idxs = inrange(tree, coords, r, false)
    if length(idxs) == 0
        return NaN32
    else
        distances = colwise(Euclidean(), Float32.(coords), coordinates[:,idxs])
        s = sortperm(distances)
        k = calc_k(distances[s], coords, coordinates[:,idxs][:, s])
        ws = k ./ distances[s].^power # .* view(uncertainty, idxs)
        Σw = sum(ws)

        if isinf(Σw)
            μ = values[s[1]]
        else
            ws ./= Σw
            vs = view(values, idxs[s])
            μ = sum(ws[i] * vs[i] for i in eachindex(vs))
        end
        return μ
end
end

function calc_angles(coords, coordinates)
    dv = coordinates .- coords
    atand.(dv[2,:], dv[1,:])
end

function calc_k(distances, coords, coordinates, dist=Euclidean())

    # assumes these coordinates and angles are already sorted
    # with respect to their distance to the point to interpolate
    angles = calc_angles(coords, coordinates[:,idxs])
    w = ones(length(angles))
    shield_angle = 360. / length(w)

    # For each point, check if closerby points shield it
    # and if so calculate a lower weight for it
    for i in 2:length(w)
        for j in 1:i - 1
            α = abs(angles[i] % 180 - angles[j] % 180)
            if α < shield_angle

                dij = evaluate(dist, coordinates[:, i], coordinates[:, j])
                if dij == 0 || α == 0  # i is directly behind or on j
                    w[i] = 0
                    break
                end
                θ = asind(distances[i] * sind(α) / dij) - (α / 2)
                @info i, j, coordinates[:, i], coordinates[:, j], distances[i], distances[j], dij, α / 2, θ, distances[i] * sind(α) / dij
                w[i] *= sind(θ)
            end
        end
    end
    return w
end
