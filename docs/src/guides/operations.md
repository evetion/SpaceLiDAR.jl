# Chaining Operations

`table(g)` is lazy: it keeps the HDF5 file and granule context around so
operations can auto-pull the columns they need. To keep that context across
multiple filters and transforms, use Julia's `|>` pipe syntax and materialize
only at the end:

```julia
using DataFrames
using Extents
using SpaceLiDAR

g = granule("GLAH14_634_1102_001_0071_0_01_0001.H5")
ext = Extent(X = (-180.0, 0.0), Y = (60.0, 80.0))

df = table(g) |>
    SaturationCorrect() |>
    InExtent(ext) |>
    ICESatQuality() |>
    DataFrame
```

The intermediate operations above are lazy. SpaceLiDAR first gathers the union
of required columns, reads the HDF5 data once, then applies the operations in
left-to-right pipe order. `DataFrame` can be replaced by `collect` if you want
SpaceLiDAR's lightweight `Table`/`PartitionedTable` wrappers instead.

The two-argument verbs remain eager:

```julia
t = table(g)
t1 = map(SaturationCorrect(), t)      # materializes
t2 = filter(ICESatQuality(), t1)      # cannot auto-pull missing HDF5 columns
```

Use the eager `filter`/`map` form for a single operation, or after you have
already selected/materialized every column needed by later operations.
