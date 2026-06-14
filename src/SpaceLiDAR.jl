"""
    SpaceLiDAR

Read, search, download and process data from spaceborne LiDAR missions —
ICESat (GLAH06/GLAH14), ICESat-2 (ATL03/06/08/12) and GEDI (L2A) — as
Julia tables.

HDF5 granules are exposed through the [`Tables.jl`](https://github.com/JuliaData/Tables.jl)
interface, so they integrate directly with `DataFrame` and the wider
data ecosystem. The package also covers granule search and download from
NASA's CMR, geoid/datum conversions ([`to_egm2008`](@ref),
[`topex_to_wgs84`](@ref)) and a [`GeoInterface`](https://github.com/JuliaGeo/GeoInterface.jl)
adapter.

# Getting started

Create a granule from a local file with [`granule`](@ref) (or a folder
with [`granules`](@ref)), then turn it into points with [`points`](@ref),
line geometries with [`lines`](@ref), or a generic table with
[`table`](@ref). Use [`search`](@ref) and [`download`](@ref) to fetch new
granules from NASA.
"""
module SpaceLiDAR

using Dates: Dates, @dateformat_str, Day, datetime2unix, unix2datetime
using CategoricalArrays: CategoricalArrays, CategoricalArray
using FillArrays: FillArrays, Fill
using GeoFormatTypes
using GeoInterface: GeoInterface, LineStringTrait, MultiPointTrait, PointTrait
using HDF5: HDF5, attributes, open_dataset, open_group, read_attribute, read_dataset
using Tables
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
include("operations.jl")
include("search.jl")
include("geointerface.jl")
include("env.jl")


export search, sync, download!, download, netrc!, instantiate, info, angle, angle!, shift
export lines, points, table, explore, in_bbox, bounds, classify, isvalid, rm
export to_egm2008, to_egm2008!
export topex_to_wgs84, topex_to_wgs84!
export icesat_saturation_correct, icesat_saturation_correct!
export icesat_quality
export Operation, apply, apply!, inputs, outputs
export ToEGM2008, TopexToWGS84, SaturationCorrect, ICESatQuality, InExtent
export ICESat_Granule, ICESat2_Granule, GEDI_Granule, convert
export granule, granules

# include("precompile.jl")

end # module
