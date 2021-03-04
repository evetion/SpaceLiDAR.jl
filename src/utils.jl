
"""Hacked version of Base.download which adds cookies and (optional) netrc parsing."""
function download_curl(url::AbstractString, filename::AbstractString)
    err = PipeBuffer()
    pipe = pipeline(`curl -s -b cookie.txt -c cookie.txt --netrc-optional -S -g -L -f -o $filename $url`, stderr=err)
    process = run(pipe, wait=false)
    if !success(process)
        error_msg = readline(err)
        @error "Download failed: $error_msg"
        Base.pipeline_error(process)
    end
    return filename
end

"""Generate granule from .h5 file."""
function granule_from_file(filename::AbstractString)
    id, ext = splitext(filename)
    ext != ".h5" && error("Granule must be a .h5 file")

    name = basename(filename)
    # ICESat-2
    if startswith(name, "ATL")
        info = icesat2_info(name)
        return ICESat2_Granule(info.type, name, filename, (x_min = 0.,), info)
    elseif startswith(name, "GEDI")
        info = gedi_info(name)
        return GEDI_Granule(info.type, name, filename, info)
    else
        error("Unknown granule.")
    end
end

"""Generate granules from folder filled with .h5 files."""
function granules_from_folder(foldername::AbstractString)
    return [granule_from_file(joinpath(foldername, file)) for file in readdir(foldername) if splitext(file)[end] == ".h5"]
end

function instantiate(granules::Vector{T}, folder::AbstractString) where T <: Granule
    local_granules = Vector{eltype(granules)}()
    for granule in granules
        file = joinpath(folder, granule.id)
        if isfile(file)
            g = copy(granule)
            g.url = file
            push!(local_granules, g)
        end
    end
    @info "Found $(length(local_granules) / length(granules) * 100)% of provided granules."
    local_granules
end


"""Filter with bbox."""
function in_bbox(xyz, bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}})
    @view xyz[(bbox.min_x .<= xyz.x .<= bbox.max_x) .& (bbox.min_y .<= xyz.y .<= bbox.max_y), :]
end

function in_bbox(g::G, bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}}) where G <: Granule
    box = bounds(g)
    intersect((;box.min_x,box.min_y,box.max_x,box.max_y), bbox)
end

function in_bbox(g::Vector{G}, bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}}) where G <: Granule
    m = in_bbox.(g, Ref(bbox))
    g[m]
end

function bounds(table)
    NamedTuple{(:min_x, :max_x, :min_y, :max_y, :min_z, :max_z)}((extrema(table.x)..., extrema(table.y)..., extrema(table.z)...))
end

function write_granule_urls!(fn::String, granules::Vector{<:Granule})
    open(fn, "w") do f
        for granule in granules
            println(f, granule.url)
        end
    end
    abspath(fn)
end

function test(granule::Granule)
    try
        HDF5.h5open(granule.url, "r") do file
            keys(file)
        end
        return true
    catch e
        @error "Granule at $(granule.url) failed with $e."
        return false
    end
    end

"""Writes/updates netrc file for ICESat-2 and GEDI downloads."""
function netrc!(username, password)
    if Sys.iswindows()
        fn = joinpath(homedir(), "_netrc")
    else
        fn = joinpath(homedir(), ".netrc")
    end

    open(fn, "a") do f
        write(f, "\n")
        write(f, "machine urs.earthdata.nasa.gov login $username password $(password)\n")
        write(f, "machine n5eil01u.ecs.nsidc.org login $username password $(password)\n")
    end
    fn
end

using GeoArrays
using StaticArrays
using ProgressMeter
using NearestNeighbors
using TypedTables

function interpolate!(ga::GeoArray, t::Table, r=1.)
    tt = hcat(t.x, t.y)
    ttt = permutedims(tt)
    tree = BallTree(ttt)
    ui, uj = size(ga)[1:2]
    p = Progress(length(ga), 1, "Interpolating...")
    Threads.@threads for i in 1:ui
        Threads.@threads for j in 1:uj
            coords = centercoords(ga, SVector{2}(i, j))::SArray{Tuple{2},Float64,1,2}
            ga.A[i, j, 1] = idw(coords, tree, r, t.z, t.u, ttt)
            next!(p)
        end
    end
end

function idw(coords, tree, r, values, uncertainty, coordinates, power=2)
    idxs = inrange(tree, coords, r)
    if length(idxs) == 0
        return NaN32
    else
        distances = colwise(Euclidean(), Float32.(coords), coordinates[:,idxs])
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

function filter_rgt(granules::Vector{<:Granule}, rgt::Int, cycle::Int)
    results = Vector{Granule}()
    for granule in granules
        i = info(granule)
        if i.rgt == rgt && i.cycle == cycle
            push!(results, granule)
        end
    end
    results
end
