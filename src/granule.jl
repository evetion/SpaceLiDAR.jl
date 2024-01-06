using HDF5
import Downloads
import AWSS3
using Aria2_jll

# Custom downloader for Julia 1.6 which doensn't have NETRC + Cookie support
# This is a method because it will segfault if precompiled.
function custom_downloader()
    downloader = Downloads.Downloader()
    easy_hook =
        (easy, _) -> begin
            Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_NETRC, Downloads.Curl.CURL_NETRC_OPTIONAL)
            Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_COOKIEFILE, "")
        end
    downloader.easy_hook = easy_hook
    return downloader
end

function _download(kwargs...)
    downloader = custom_downloader()
    Downloads.download(kwargs...; downloader = downloader)
end

function _request(args...; kwargs...)
    downloader = custom_downloader()
    Downloads.request(args...; kwargs..., downloader = downloader)
end

function create_aws_config(daac = "nsidc", region = "us-west-2")
    expiry = DateTime(get(ENV, "AWS_SESSION_EXPIRES", typemin(DateTime)))
    if expiry < Dates.now(UTC)
        # If credentials are expired or unset, get new ones
        creds = get_s3_credentials(daac)
        set_env!(creds)
    else
        # Otherwise, get them from the environment
        creds = AWSS3.AWSCredentials(
            get(ENV, "AWS_ACCESS_KEY_ID", ""),
            get(ENV, "AWS_SECRET_ACCESS_KEY", ""),
            get(ENV, "AWS_SESSION_TOKEN", ""),
            expiry = DateTime(get(ENV, "AWS_SESSION_EXPIRES", typemax(DateTime))),
        )
    end

    AWSS3.global_aws_config(; creds, region)
end

function _s3_download(url, fn, config = create_aws_config())
    bucket, path = split(last(split(url, "//")), "/"; limit = 2)
    AWSS3.s3_get_file(config, bucket, path, fn)
end

abstract type Granule end
Base.:(==)(a::Granule, b::Granule) = a.id == b.id

Base.show(io::IO, g::Granule) = _show(io, g)
Base.show(io::IO, ::MIME"text/plain", g::Granule) = _show(io, g)
function _show(io, g::T) where {T<:Granule}
    print(io, "$T with id $(g.id)")
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
    fn = joinpath(abspath(folder), granule.id)
    if isfile(fn)
        granule.url = fn
        return granule
    end
    isfile(granule.url) && return granule
    tmp = tempname(abspath(folder))
    if startswith(granule.url, "http")
        _download(granule.url, tmp)
    elseif startswith(granule.url, "s3")
        _s3_download(granule.url, tmp)
    else
        error("Can't determine how to download $(granule.url)")
    end
    mv(tmp, fn)
    granule.url = fn
    granule
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

    # Download serially if s3 links are present
    if any(g -> startswith(g.url, "s3"), granules)
        return map(g -> download!(g, folder), granules)
    end

    f = write_urls(granules)
    cmd = `$(Aria2_jll.aria2c()) -i $f -c -d $folder`
    local io
    try
        io = run(pipeline(cmd, stdout = stdout, stderr = stderr), wait = false)
        while process_running(io)
            sleep(1)
        end
    catch e
        kill(io)
        println()
        throw(e)
    end

    for granule in granules
        granule.url = joinpath(folder, granule.id)
    end
    granules
end

"""
    download(granules::Vector{<:Granule}, folder=".")

Like [`download`](@ref), but for a vector of `granules`.
"""
function download(granules::Vector{<:Granule}, folder::AbstractString = ".")

    # Download serially if s3 links are present
    if any(g -> startswith(g.url, "s3"), granules)
        return map(g -> download(g, folder), granules)
    else
        download!(copy.(granules), folder)
    end
end

function Base.filesize(granule::T) where {T<:Granule}
    filesize(granule.url)
end

Base.isequal(a::Granule, b::Granule) = a.id == b.id
Base.hash(g::Granule, h::UInt) = hash(g.id, h)

"""
    sync(folder::AbstractString, all::Bool=false)
    sync(folders::AbstractVector{<:AbstractString}, all::Bool=false)
    sync(product::Symbol, folder::AbstractString, all::Bool=false)
    sync(product::Symbol, folders::AbstractVector{<:AbstractString}, all::Bool=false)

Syncronize the contents of `folder(s)` with the latest granules available.
Specifically, this will download any granules not yet present in folder(s),
to the *first* folder in the list.

Assumes all folders contain granules of the same product. If not, pass the
product as Symbol: [`sync(::Symbol), folders, all`](@ref) instead.

`all`, false by default, will search only for granules past the date of
the latest granule found in `folders`. If true, will search for all granules.
"""
function sync(folders::AbstractVector{<:AbstractString}, all::Bool = false)
    grans = reduce(vcat, granules.(folders))
    sync!(grans, first(folders), all)
end
sync(folder::AbstractString, all::Bool = false) = sync([folder], all)

function sync(product::Symbol, folders::AbstractVector{<:AbstractString}, all::Bool = false)
    grans = reduce(vcat, granules.(folders))
    filter!(g -> sproduct(g) == product, grans)
    sync!(grans, first(folders), all)
end
sync(product::Symbol, folder::AbstractString, all::Bool = false) = sync(product, [folder], all)

function sync!(granules, folder, all)
    g = first(granules)
    ngranules = if length(granules) == 0 || !haskey(info(granules[end]), :date) || all
        Set(search(g))
    else
        sort!(granules, by = x -> x.id)
        Set(search(g, after = info(granules[end]).date))
    end
    setdiff!(ngranules, Set(granules))
    download!(collect(ngranules), folder)
end
