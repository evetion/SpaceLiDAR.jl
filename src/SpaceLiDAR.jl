module SpaceLiDAR

using Dates
using CategoricalArrays
using FillArrays
using HDF5
using Tables
using TableOperations: joinpartitions
using DataFrames
using TimeZones

include("granule.jl")
include("utils.jl")
include("geom.jl")
include("GEDI/GEDI.jl")
include("GEDI/L2A.jl")
include("ICESat-2/ICESat-2.jl")
include("ICESat-2/ATL03.jl")
include("ICESat-2/ATL06.jl")
include("ICESat-2/ATL08.jl")
include("ICESat-2/ATL12.jl")
include("ICESat/ICESat.jl")
include("ICESat/GLAH06.jl")
include("ICESat/GLAH14.jl")
include("geoid.jl")
include("table.jl")
include("search.jl")

export find, download!, netrc!, instantiate, info, angle, angle!, shift
export lines, points, in_bbox, bounds, classify, isvalid, rm, to_egm2008!
export ICESat_Granule, ICESat2_Granule, GEDI_Granule, convert
export granule_from_file, granules_from_folder, write_granule_urls!

precompile(find, (Symbol, String, NamedTuple, String))
precompile(find, (Symbol, String))
precompile(instantiate, (Vector{GEDI_Granule}, String))
precompile(instantiate, (Vector{ICESat_Granule}, String))
precompile(instantiate, (Vector{ICESat2_Granule}, String))
precompile(granules_from_folder, (String,))
precompile(granule_from_file, (String,))
precompile(download!, (GEDI_Granule,))
precompile(download!, (ICESat_Granule,))
precompile(download!, (ICESat2_Granule,))
precompile(points, (GEDI_Granule,))
precompile(points, (ICESat_Granule,))
precompile(points, (ICESat2_Granule,))
precompile(lines, (GEDI_Granule,))
precompile(lines, (ICESat_Granule,))
precompile(lines, (ICESat2_Granule,))
precompile(angle, (Vector{Float32}, Vector{Float32}))
precompile(shift, (Float32, Float32, Float64, Float64))

end # module
