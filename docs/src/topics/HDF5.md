# H5Table — HDF5 as Tables

H5Table is a generic module for reading HDF5 datasets as tabular data. It handles
dimension flattening, nodata masking, and the Tables.jl interface — without any
knowledge of specific satellite products.

SpaceLiDAR extends H5Table with product-specific schemas via multiple dispatch.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  SpaceLiDAR                                             │
│  table(g::Granule) / explore(g::Granule)                │
│  ├── default_variables(g) → schema with transforms      │
│  ├── default_tracks(g) → track names                    │
│  └── PartitionedH5Table (one H5Table per track)         │
├─────────────────────────────────────────────────────────┤
│  H5Table module (generic)                               │
│  ├── H5Table struct (lazy column access via Tables.jl)  │
│  ├── Dimension resolution & flattening (inner/outer)    │
│  ├── Nodata masking (_FillValue, valid_range → missing) │
│  ├── Transform composition (mask ∘ transform)           │
│  ├── Categorical encoding (flag_meanings)               │
│  └── Interactive explorer (select from tree)            │
└─────────────────────────────────────────────────────────┘
```

## Two Levels of API

### Level 1: Generic HDF5 (any file)

```julia
using SpaceLiDAR.H5Tables, HDF5

file = h5open("any_file.h5", "r")
t = H5Table(file; vars=[:lat => "data/latitude", :lon => "data/longitude"])
```

Returns an `H5Table` implementing Tables.jl — columns are read lazily on access.
Nodata values (`_FillValue`, `valid_range`) are automatically converted to `missing`.
Dimension scales are resolved to determine how multi-dimensional variables flatten.
Because reads are lazy, the underlying HDF5 file handle stays open; call
`close(t)` when you are done with a long-lived table.

### Level 2: Granule-aware (schema via dispatch)

```julia
g = granule("ATL08_20201121151145_08920913_006_01.h5")
t = table(g)   # → PartitionedH5Table (one H5Table per track)
df = DataFrame(t)
```

`table(g)` calls `default_variables(g)` and `default_tracks(g)` internally,
prefixes paths with each track name, and applies transforms (ToBool, ToDateTime, etc.).

## Nodata Handling

H5Table reads `_FillValue` and `valid_range` attributes from each HDF5 dataset
and replaces matching values with `missing`:

```julia
# A dataset with _FillValue = 3.4028235f38:
col = Tables.getcolumn(t, :height)
# → Union{Missing, Float32}[12.6, missing, 8.3, ...]
```

This replaces the old `FillNaN`/`ClampNaN` approach — no NaN pollution in your data.

## Transforms

Transforms convert raw HDF5 data into useful types. They are composed with
the nodata mask at construction time: `f = transform ∘ mask`.

Pass transforms on the `Variable` spec itself:

```julia
t = H5Table(file; vars=[
    Variable(:quality, "data/quality_flag", Int8, InvertBool()),
    Variable(:time, "data/delta_time", Float64, ToDateTimeConst(0.0)),
])
```

| Transform | Purpose | Example |
|:---|:---|:---|
| `ToBool()` | Nonzero → true | Flag fields |
| `InvertBool()` | Zero → true | Quality flags (0 = good) |
| `ToDateTime(path, offset)` | Float → DateTime | delta_time + GPS epoch |
| `ToDateTimeConst(offset)` | Float → DateTime | delta_time + constant |
| `SliceRow(n)` | Extract row from 2D | Multi-confidence arrays |

Transforms operate on raw data; the mask adds `missing` where sentinels existed:

```julia
# terrain_flg (Int32) with InvertBool:
# raw: [0, 1, 0, 2] → mask: identity (no fill) → InvertBool: [true, false, true, false]
```

## Dimension Flattening

When variables have different dimensionality, H5Table automatically repeats
lower-dimensional variables to match the global shape:

```julia
# Variable A has dims (geoseg,)      — 100 elements
# Variable B has dims (geoseg, 20m)  — 100×5 elements
# Result: A is repeated 5× (inner), both become 500-row columns
```

## Interactive Explorer

`explore()` provides a terminal-based tree browser for any HDF5 file:

```julia
# Generic:
t = explore(file)        # → H5Table with selected variables

# Granule-aware (replicates across tracks):
g = granule("ATL08_20201121151145_08920913_006_01.h5")
t = explore(g)           # → PartitionedH5Table
```

Keys: Space (select), d (auto-dimensions), r (auto-references), q (confirm).

## Extending for New Products

Add a method for your product type:

```julia
function default_variables(::ICESat2_Granule{:ATL24})
    [
        Variable(:latitude, "lat_ph", Float64),
        Variable(:longitude, "lon_ph", Float64),
        Variable(:depth, "ortho_h", Float32),
        Variable(:class, "class_ph", Int8),
    ]
end

default_tracks(::ICESat2_Granule{:ATL24}) = SpaceLiDAR.icesat2_tracks
```

Then `table(g)` and `explore(g)` work automatically.
