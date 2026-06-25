module SpaceLiDAR

using Dates: Dates, @dateformat_str, Day, datetime2unix, unix2datetime
using CategoricalArrays: CategoricalArrays, CategoricalArray
using FillArrays: FillArrays, Fill
using GeoFormatTypes
using GeoInterface: GeoInterface, LineStringTrait, MultiPointTrait, PointTrait
using HDF5: HDF5, attributes, open_dataset, open_group, read_attribute, read_dataset
using Tables: Tables
using TableOperations: joinpartitions
using DataFrames: DataFrames, DataFrame, subset, subset!
using TimeZones: TimeZones, DateTime, UTC
using Extents: Extents, Extent, extent
import DataAPI

include("granule.jl")
include("utils.jl")
include("geom.jl")
include("H5Table/H5Table.jl")
Variable = H5Tables.Variable
Attribute = H5Tables.Attribute
ToDateTime = H5Tables.ToDateTime
ToDateTimeConst = H5Tables.ToDateTimeConst
ToBool = H5Tables.ToBool
InvertBool = H5Tables.InvertBool
SliceRow = H5Tables.SliceRow
ExpandDims = H5Tables.ExpandDims
include("table.jl")
include("operations.jl")
include("geoid.jl")
include("GEDI/GEDI.jl")
include("GEDI/L2A.jl")
include("ICESat-2/ICESat-2.jl")
include("ICESat-2/ATL03.jl")
include("ICESat-2/ATL06.jl")
include("ICESat-2/ATL08.jl")
include("ICESat-2/ATL12.jl")
include("ICESat-2/ATL24.jl")
include("ICESat/ICESat.jl")
include("ICESat/GLAH06.jl")
include("ICESat/GLAH14.jl")
include("search.jl")
include("geointerface.jl")
include("env.jl")


export search, sync, download!, download, netrc!, instantiate, info, angle, angle!, shift
export lines, points, table, explore, in_bbox, bounds, classify, isvalid, rm
export to_egm2008, to_egm2008!
export topex_to_wgs84, topex_to_wgs84!
export icesat_saturation_correct, icesat_saturation_correct!
export icesat_quality
export Operation, Filter, Transform
export ToEGM2008, TopexToWGS84, SaturationCorrect, ICESatQuality, InExtent
export ICESat_Granule, ICESat2_Granule, GEDI_Granule, convert
export granule, granules

# include("precompile.jl")

end # module
