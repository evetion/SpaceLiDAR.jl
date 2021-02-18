using HDF5
# using Downloads

abstract type Granule end

function HDF5.h5open(granule::Granule)
    HDF5.h5open(granule.url, "r")
end

# function HDF5.h5close(granule::Granule)
    # fn = download(granule)
#     HDF5.h5close(fn)
# end

function download(granule::Granule, folder=".")
    fn = joinpath(folder, granule.id)
    isfile(fn) && return fn
    isfile(granule.url) && return granule.url
    download_curl(granule.url, fn)
    # Downloads.download(granule.url, fn)
end

function download(granules::Vector{Granule}, folder::AbstractString)
    for granule in granules
        download(granule, folder)
    end
end
