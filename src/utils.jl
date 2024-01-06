using Printf
using DataFrames

"""
    granule(filename::AbstractString)

Create a mission specific granule from a local .h5 filepath. For folder usage see
[`granules`](@ref).
"""
function granule(filename::AbstractString)
    _, ext = splitext(filename)
    lowercase(ext) != ".h5" && error("Granule must be a .h5 file")

    name = basename(filename)
    if startswith(name, "ATL")
        info = icesat2_info(name)
        return ICESat2_Granule{Symbol(info.type)}(name, filename, info, MultiPolygonType())
    elseif startswith(name, "GEDI")
        info = gedi_info(name)
        return GEDI_Granule{Symbol(info.type)}(name, filename, info, MultiPolygonType())
    elseif startswith(name, "GLAH")
        info = icesat_info(name)
        return ICESat_Granule{Symbol(info.type)}(name, filename, info, MultiPolygonType())
    else
        error("Unknown granule.")
    end
end
@deprecate granule_from_file(filename::AbstractString) granule(filename::AbstractString)

"""
    granules(foldername::AbstractString)

Create mission specific granules from a folder with .h5 files, using [`granule`](@ref).
"""
function granules(foldername::AbstractString)
    return [
        granule(joinpath(foldername, file)) for
        file in readdir(foldername) if lowercase(splitext(file)[end]) == ".h5" && !isfile("$(file).aria2")
    ]
end
@deprecate granules_from_folder(foldername::AbstractString) granules(foldername::AbstractString)

"""
    instantiate(granules::Vector{::Granule}, folder::AbstractString)

For a given list of `granules` from [`find`](@ref), match the granules to the local files
and return a new list of granules with the local filepaths if they exist.
"""
function instantiate(granules::Vector{T}, folder::AbstractString) where {T<:Granule}
    local_granules = Vector{eltype(granules)}()
    for granule in granules
        file = joinpath(folder, granule.id)
        if isfile(file)
            g = copy(granule)
            g.url = file
            push!(local_granules, g)
        end
    end
    @info "Found $(@sprintf("%.0f",(length(local_granules) / length(granules) * 100)))% of $(length(granules)) provided granules."
    local_granules
end


function in_bbox(xyz::DataFrame, bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}})
    subset(
        xyz,
        :longitude => x -> (bbox.min_x .<= x .<= bbox.max_x),
        :latitude => y -> (bbox.min_y .<= y .<= bbox.max_y),
    )
end
function in_bbox!(xyz::DataFrame, bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}})
    subset!(
        xyz,
        :longitude => x -> (bbox.min_x .<= x .<= bbox.max_x),
        :latitude => y -> (bbox.min_y .<= y .<= bbox.max_y),
    )
end

function intersect(
    a::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}},
    b::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}},
)
    !(b.min_x > a.max_x || b.max_x < a.min_x || b.min_y > a.max_y || b.max_y < a.min_y)
end

function in_bbox(g::G, bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}}) where {G<:Granule}
    box = bounds(g)
    intersect((; box.min_x, box.min_y, box.max_x, box.max_y), bbox)
end

function in_bbox(g::Vector{G}, bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}}) where {G<:Granule}
    m = in_bbox.(g, Ref(bbox))
    g[m]
end

url(g::Granule) = g.url
urls(g::Vector{<:Granule}) = getfield.(g, :url)

"""
    write_urls(fn::String, granules::Vector{<:Granule})

Write all granule urls to a file.
"""
function write_urls(fn::String, granules::AbstractVector{<:Granule})
    open(fn, "w") do f
        write_urls(f, granules)
    end
    abspath(fn)
end
@deprecate write_granule_urls! write_urls

function write_urls(granules::AbstractVector{<:Granule})
    fn, io = mktemp()
    write_urls(io, granules)
    close(io)
    fn
end

function write_urls(f::IOStream, granules::AbstractVector{<:Granule})
    for granule in granules
        println(f, url(granule))
    end
end

"""
    isvalid(g::Granule)

Checks if a granule is has a valid, local and non-corrupt .h5 file. Can be combined with
[`rm(::Granule)`](@ref) to remove invalid granules.
"""
function isvalid(granule::Granule)
    try
        HDF5.h5open(url(granule), "r") do file
            keys(file)
        end
        return true
    catch e
        @error "Granule at $(granule.url) failed with $e."
        return false
    end
end

"""
    netrc!(username, password)

Writes/updates a .netrc file for ICESat-2 and GEDI downloads. A .netrc is a plaintext
file containing your username and password for NASA EarthData and DAACs, and can be automatically
used by Julia using `Downloads` and tools like `wget`, `curl` among others.
"""
function netrc!(username, password)
    if Sys.iswindows()
        fn = joinpath(homedir(), "_netrc")
    else
        fn = joinpath(homedir(), ".netrc")
    end

    open(fn, "a") do f
        write(f, "\n")
        write(f, "machine urs.earthdata.nasa.gov login $username password $(password)\n")
    end
    fn
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

function Base.convert(::Type{Extent}, nt::NamedTuple{(:min_x, :min_y, :max_x, :max_y)})
    Extent(X = (nt.min_x, nt.max_x), Y = (nt.min_y, nt.max_y))
end

function Base.convert(
    ::Type{NamedTuple},
    nt::Extent{(:X, :Y)},
)
    (; min_x = nt.X[1], min_y = nt.Y[1], max_x = nt.X[2], max_y = nt.Y[2])
end
