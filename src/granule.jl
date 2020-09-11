using HDF5
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
    download_curl(granule.url, fn)
end
