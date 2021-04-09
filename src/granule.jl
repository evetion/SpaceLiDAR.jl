using HDF5
import Downloads

downloader = Downloads.Downloader()
easy_hook = (easy, info) -> begin
    Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_NETRC, Downloads.Curl.CURL_NETRC_OPTIONAL)
    Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_COOKIEFILE, "")
end
downloader.easy_hook = easy_hook

download(kwargs...) = Downloads.download(kwargs...;downloader=downloader)

abstract type Granule end

function HDF5.h5open(granule::Granule)
    HDF5.h5open(granule.url, "r")
end

function download(granule::Granule, folder=".")
    fn = joinpath(folder, granule.id)
    if isfile(fn)
        granule.url = fn
        return fn
    end
    isfile(granule.url) && return granule
    if startswith(granule.url, "s3://")
        download_s3(granule.url, fn)
    elseif startswith(granule.url, "http")
        download(granule.url, fn)
    else
        error("Can't determine how to download $(granule.url)")
    end
    granule.url = fn
    granule
end

function rm(granule::Granule)
    if isfile(granule.url)
        Base.rm(granule.url)
    else
        @warn("Can't delete $(granule.url)..")
    end
end

function download(granules::Vector{Granule}, folder::AbstractString)
    for granule in granules
        download(granule, folder)
    end
end

function filesize(granule::T) where T <: Granule
    filesize(granule.url)
end
