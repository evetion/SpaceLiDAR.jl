module H5Table

using Dates
using HDF5
using DataAPI
using FillArrays
using Tables
using CategoricalArrays
using FoldingTrees
using REPL.TerminalMenus
using StyledStrings

export H5Table, Variable, Attribute, explore, select, get_dimensions, get_references
export ToDateTime, ToDateTimeConst, ToBool, InvertBool, SliceRow, ExpandDims
export PartitionedH5Table

include("table.jl")
include("explore.jl")

end