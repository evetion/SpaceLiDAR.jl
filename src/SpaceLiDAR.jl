module SpaceLiDAR

using Dates
using CategoricalArrays
using FillArrays
using GeoFormatTypes
using GeoInterface
using HDF5
using Tables
using TableOperations: joinpartitions
using DataFrames
using TimeZones
using Extents
import DataAPI

include("granule.jl")
include("utils.jl")
include("geom.jl")
include("H5Table/H5Table.jl")
Variable = H5Table.Variable
Attribute = H5Table.Attribute
ToDateTime = H5Table.ToDateTime
ToDateTimeConst = H5Table.ToDateTimeConst
ToBool = H5Table.ToBool
InvertBool = H5Table.InvertBool
SliceRow = H5Table.SliceRow
ExpandDims = H5Table.ExpandDims
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
include("geointerface.jl")
include("env.jl")


export find, search, sync, download!, download, netrc!, instantiate, info, angle, angle!, shift
export lines, points, table, explore, in_bbox, bounds, classify, isvalid, rm
export to_egm2008, to_egm2008!
export topex_to_wgs84, topex_to_wgs84!
export icesat_saturation_correct, icesat_saturation_correct!
export icesat_quality
export ICESat_Granule, ICESat2_Granule, GEDI_Granule, convert
export granule, granules, granule_from_file, granules_from_folder, write_granule_urls!

# include("precompile.jl")

end # module
