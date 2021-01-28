
"""Hacked version of Base.download which adds cookies and (optional) netrc parsing."""
function download_curl(url::AbstractString, filename::AbstractString)
    err = PipeBuffer()
    pipe = pipeline(`curl -s -b cookie.txt -c cookie.txt --netrc-optional -S -g -L -f -o $filename $url`, stderr=err)
    @info pipe
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

"""Filter with bbox."""
function in_bbox(xyz, bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}})
    @view xyz[(bbox.min_x .<= xyz.x .<= bbox.max_x) .& (bbox.min_y .<= xyz.y .<= bbox.max_y), :]
end

function write_granule_urls!(fn::String, granules::Vector{<:Granule})
    open(fn, "w") do f
        for granule in granules
            println(f, granule.url)
        end
    end
    abspath(fn)
end
