module SpaceLiDAR

using Dates
using CategoricalArrays
using FillArrays
using GeoDataFrames; const GDF = GeoDataFrames
using HDF5

include("granule.jl")
include("utils.jl")
include("search.jl")
include("geom.jl")
include("geom_utils.jl")
include("s3.jl")
include("geoarrays.jl")
include("GEDI/GEDI.jl")
include("GEDI/L2A.jl")
include("ICESat-2/ICESat-2.jl")
include("ICESat-2/ATL03.jl")
include("ICESat-2/ATL08.jl")
include("ICESat-2/ATL12.jl")
include("ICESat/ICESat.jl")
include("ICESat/GLAH14.jl")
include("laz.jl")
include("interpolate.jl")

export find, download!, netrc!, instantiate!
export xyz, lines, points, in_bbox, bounds
export test, granule_from_file, granules_from_folder, write_granule_urls!

precompile(find, (Symbol, String, NamedTuple, String))
precompile(find, (Symbol, String))
precompile(GeoArrays.read, (String,))
precompile(GeoArrays.read, (String, Bool))
precompile(instantiate!, (Vector{ICESat2_Granule}, String))
precompile(instantiate!, (Vector{GEDI_Granule}, String))
precompile(granules_from_folder, (String,))
precompile(granule_from_file, (String,))
precompile(download!, (ICESat2_Granule,))
precompile(download!, (GEDI_Granule,))
precompile(points, (GEDI_Granule,))
precompile(points, (ICESat2_Granule,))
precompile(lines, (GEDI_Granule,))
precompile(lines, (ICESat2_Granule,))
precompile(angle, (Vector{Float32}, Vector{Float32}))
precompile(shift, (Float32, Float32, Float64, Float64))

end # module
