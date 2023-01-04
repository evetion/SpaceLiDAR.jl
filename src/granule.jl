using HDF5
import Downloads
import AWSS3

# This is a method because it will segfault if precompiled.
function _download(kwargs...)
    downloader = Downloads.Downloader()
    easy_hook =
        (easy, _) -> begin
            Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_NETRC, Downloads.Curl.CURL_NETRC_OPTIONAL)
            Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_COOKIEFILE, "")
        end
    downloader.easy_hook = easy_hook
    Downloads.download(kwargs...; downloader = downloader)
end

function _s3_download(url, fn)
    bucket, path = split(last(split(url, "//")), "/"; limit = 2)
    aws = AWSS3.global_aws_config(
        creds = AWSS3.AWSCredentials(
            get(ENV, "AWS_ACCESS_KEY_ID", ""),
            get(ENV, "AWS_SECRET_ACCESS_KEY", ""),
            get(ENV, "AWS_SESSION_TOKEN", ""),
        );
        region = "us-west-2",
    )
    AWSS3.s3_get_file(aws, bucket, path, fn)
end

abstract type Granule end

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
        return fn
    end
    isfile(granule.url) && return granule
    if startswith(granule.url, "http")
        _download(granule.url, fn)
    elseif startswith(granule.url, "s3")
        _s3_download(granule.url, fn)
    else
        error("Can't determine how to download $(granule.url)")
    end
    granule.url = fn
    granule
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

function Base.filesize(granule::T) where {T<:Granule}
    filesize(granule.url)
end
