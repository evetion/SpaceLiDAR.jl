using HDF5
import Downloads
import AWSS3

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
"""
function download!(granules::Vector{Granule}, folder::AbstractString = ".")
    for granule in granules
        download!(granule, folder)
    end
end

"""
    download(granules::Vector{<:Granule}, folder=".")

Like [`download`](@ref), but for a vector of `granules`.
"""
function download(granules::Vector{Granule}, folder::AbstractString = ".")
    map(granule -> download(granule, folder), granules)
end

function Base.filesize(granule::T) where {T<:Granule}
    filesize(granule.url)
end

struct Table{K,V}
    table::NamedTuple{K,V}
    function Table(table::NamedTuple{K,V}) where {K,V}
        new{K,typeof(values(table))}(table)
    end
end
_table(t::Table) = getfield(t, :table)
Base.size(table::Table) = size(_table(table))
Base.getindex(t::Table, i) = _table(t)[i]
Base.show(io::IO, t::Table) = _show(io, t)
Base.show(io::IO, ::MIME"text/plain", t::Table) = _show(io, t)
Base.haskey(table::Table, x) = haskey(_table(table), x)
Base.keys(table::Table) = keys(_table(table))
Base.values(table::Table) = values(_table(table))
Base.length(table::Table) = length(_table(table))
Base.iterate(table::Table, args...) = iterate(_table(table), args...)
Base.merge(table::Table, others...) = Table(merge(_table(table), others...))
Base.parent(table::Table) = _table(table)

function Base.getproperty(table::Table, key::Symbol)
    getproperty(_table(table), key)
end

function _show(io, t::Table)
    print(io, "SpaceLiDAR Table")
end

struct PartitionedTable{N,K,V}
    tables::NTuple{N,NamedTuple{K,V}}
end
PartitionedTable(t::NamedTuple) = PartitionedTable((t,))
Base.size(t::PartitionedTable) = (length(t.tables),)
Base.length(t::PartitionedTable{N}) where {N} = N
Base.getindex(t::PartitionedTable, i) = t.tables[i]
Base.lastindex(t::PartitionedTable{N}) where {N} = N
Base.show(io::IO, t::PartitionedTable) = _show(io, t)
Base.show(io::IO, ::MIME"text/plain", t::PartitionedTable) = _show(io, t)
Base.iterate(table::PartitionedTable, args...) = iterate(table.tables, args...)
Base.merge(table::PartitionedTable, others...) = PartitionedTable(merge.(table.tables, Ref(others...)))
Base.parent(table::PartitionedTable) = collect(table.tables)

function _show(io, t::PartitionedTable)
    print(io, "SpaceLiDAR Table with $(length(t.tables)) partitions")
end
