abstract type Granule end
Base.:(==)(a::Granule, b::Granule) = id(a) == id(b)
id(g::Granule) = g.id

Base.show(io::IO, g::Granule) = _show(io, g)
Base.show(io::IO, ::MIME"text/plain", g::Granule) = _show(io, g)
function _show(io, g::T) where {T<:Granule}
    print(io, "$T with id $(id(g))")
end

MultiPolygonType = Vector{Vector{Vector{Vector{Float64}}}}

function HDF5.h5open(granule::Granule)
    HDF5.h5open(granule.url, "r")
end

"""
    download!(granule::Granule, folder=".")

Download the file associated with `granule` to the `folder`, from an http(s) location
if it doesn't already exists locally.

Will require credentials (netrc) which can be set with [`netrc!`](@ref).
"""
function download!(granule::Granule, folder = ".")
    # Normalize and ensure the directory exists
    folder = normpath(abspath(folder))
    mkpath(folder)

    fn = joinpath(folder, id(granule))
    if isfile(fn)
        granule.url = fn
        return granule
    end
    isfile(granule.url) && return granule

    tmp = tempname(folder)
    try
        EarthData.download(granule.url, tmp)
        mv(tmp, fn)
    catch
        rm(tmp; force = true)
        rethrow()
    end
    granule.url = fn
    return granule
end

"""
    download(granule::Granule, folder=".")

Download the file associated with `granule` to the `folder`, from an http(s) location
if it doesn't already exists locally. Returns a new granule. See [`download!`](@ref) for
a mutating version.

Will require credentials (netrc) which can be set with [`netrc!`](@ref).
"""
function download(granule::Granule, folder = ".")
    g = copy(granule)
    download!(g, folder)
end

"""
    rm(granule::Granule)

Remove the file associated with `granule` from the local filesystem.
"""
function Base.rm(granule::Granule)
    if isfile(granule.url)
        Base.rm(granule.url)
    else
        @warn("Can't delete $(granule.url)..")
    end
end

"""
    download!(granules::Vector{<:Granule}, folder=".")

Like [`download!`](@ref), but for a vector of `granules`.
Will make use of aria2c (parallel).
"""
function download!(granules::Vector{<:Granule}, folder::AbstractString = ".")
    # Normalize and ensure the directory exists
    folder = normpath(abspath(folder))
    mkpath(folder)
    isempty(granules) && return granules

    paths = EarthData.download(urls(granules), folder)
    for (granule, path) in zip(granules, paths)
        granule.url = path
    end
    return granules
end

"""
    download(granules::Vector{<:Granule}, folder=".")

Like [`download`](@ref), but for a vector of `granules`.
"""
function download(granules::Vector{<:Granule}, folder::AbstractString = ".")
    return download!(copy.(granules), folder)
end

function Base.filesize(granule::T) where {T<:Granule}
    filesize(granule.url)
end

Base.isequal(a::Granule, b::Granule) = id(a) == id(b)
Base.hash(g::Granule, h::UInt) = hash(id(g), h)

"""
    sync(folder::AbstractString, all::Bool=false; kwargs...)
    sync(folders::AbstractVector{<:AbstractString}, all::Bool=false; kwargs...)
    sync(product::Symbol, folder::AbstractString, all::Bool=false; kwargs...)
    sync(product::Symbol, folders::AbstractVector{<:AbstractString}, all::Bool=false; kwargs...)

Syncronize an existing archive of local granules in `folder(s)` with the latest granules available.
Specifically, this will run [`search`](@ref) and [`download`](@ref) for any granules not yet
present in folder(s), to the *first* folder in the list.

!!! warning

    Using sync could result in downloading significant (TB+) amounts of data.

Assumes all folders contain granules of the same product. If not, pass the
product as Symbol: [`sync`](@ref) instead.

When `all` is false (the default), sync will search only for granules past the date of
the latest granule found in `folders`. If true, it will search for all granules.
Note that ICESat granules are not timestamped, so sync will try to download
*all* ICESat granules not yet present, regardless of this setting.

Any `kwargs...` are passed to the [`search`](@ref) function. This enables
sync to only download granules within a certain extent, for example.
"""
function sync(folders::AbstractVector{<:AbstractString}, all::Bool = false; kwargs...)
    grans = reduce(vcat, granules.(folders))
    _sync!(grans, first(folders), all; kwargs...)
end
sync(folder::AbstractString, all::Bool = false; kwargs...) = sync([folder], all; kwargs...)

function sync(product::Symbol, folders::AbstractVector{<:AbstractString}, all::Bool = false; kwargs...)
    grans = reduce(vcat, granules.(folders))
    filter!(g -> sproduct(g) == product, grans)
    _sync!(grans, first(folders), all; kwargs...)
end
sync(product::Symbol, folder::AbstractString, all::Bool = false; kwargs...) = sync(product, [folder], all; kwargs...)

function _sync!(granules, folder, all; kwargs...)
    isempty(granules) && error("No granules found in provided folder(s).")
    g = first(granules)
    ngranules = if length(granules) == 0 || !haskey(info(granules[end]), :date) || all
        Set(search(mission(g), sproduct(g); kwargs...))
    else
        sort!(granules, by = x -> id(x))
        Set(search(mission(g), sproduct(g); after = info(granules[end]).date, kwargs...))
    end
    setdiff!(ngranules, Set(granules))
    download!(collect(ngranules), folder)
end
