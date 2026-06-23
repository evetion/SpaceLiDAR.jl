module H5Tables

using Dates: Dates, unix2datetime
using HDF5: HDF5, attrs, read_attribute
import DataAPI
using FillArrays: FillArrays, Fill
import Tables
using CategoricalArrays: CategoricalArrays, CategoricalArray
using FoldingTrees: FoldingTrees, Node, TreeMenu, count_open_leaves, fold!, isroot, unfold!
using REPL.TerminalMenus: TerminalMenus
using StyledStrings: StyledStrings, @styled_str

export H5Table, Variable, Attribute, explore, select, get_dimensions, get_references
export ToDateTime, ToDateTimeConst, ToBool, InvertBool, SliceRow, ExpandDims
export PartitionedH5Table
export h5handle, source_metadata, resolve_variable

include("table.jl")
include("explore.jl")
include("utils.jl")
include("metadata.jl")

end
