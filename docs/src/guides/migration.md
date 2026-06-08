# Migration Guide: `points()` → `table()`

## Overview

The `table()` function replaces `points()` as the primary data reading interface.
The key difference: **`table()` gives you raw data with `missing` for nodata —
all filtering and transforms are your responsibility.**

## Quick Migration Table

| Old | New |
|:----|:----|
| `points(g)` | `table(g)` |
| `points(g; canopy=true)` | `table(g; variables=atl08_canopy_variables())` |
| `points(g; ground=true, canopy=true)` | Two calls + vcat |
| `points(g; tracks=["gt1l"])` | `table(g; tracks=["gt1l"])` |

## What Changed

### No automatic filtering (GEDI)

```julia
# Old: points() applied L3 quality filter, returned ~150k rows
p = points(g)

# New: table() returns ALL footprints (~600k rows)
t = table(g)
df = DataFrame(t)
# Filter yourself:
filter!(row -> row.quality && row.surface, df)
```

### No automatic reprojection (ICESat)

```julia
# Old: points() reprojected TOPEX → WGS84 automatically
p = points(g)

# New: raw TOPEX coordinates, reproject explicitly
t = table(g)
df = DataFrame(t)
dropmissing!(df, :height)
icesat_saturation_correct!(df)
topex_to_wgs84!(df)
```

### No classification column (ATL08/GEDI)

```julia
# Old: had :classification => "ground" or "high_canopy"
p = points(g; canopy=true)
p[1].classification  # "high_canopy"

# New: no classification column
t = table(g; variables=atl08_canopy_variables())
```

### Track information

```julia
# Old:
p = points(g)
p[1].track  # "gt1l"

# New: use partitions — each partition corresponds to a track
t = table(g)
for part in Tables.partitions(t)
    # part is an H5Table for one track
    DataFrame(part)
end
```

### Filtering tracks

```julia
# Old:
p = points(g; tracks=["gt1l", "gt2l"])

# New:
t = table(g; tracks=["gt1l", "gt2l"])
```

## ICESat Full Pipeline

Replicating the old `points(g)` behavior for ICESat:

```julia
using SpaceLiDAR, DataFrames

g = granule("GLAH06_634_2131_002_0084_4_01_0001.H5")
t = table(g)
df = DataFrame(t)

# 1. Remove fill-value rows
dropmissing!(df, :height)

# 2. Apply saturation correction (old points did this automatically)
icesat_saturation_correct!(df)

# 3. Reproject TOPEX → WGS84 (old points did this automatically)
topex_to_wgs84!(df)

# 4. Compute quality flag and filter
q = icesat_quality(df)
df.quality = q
filter!(:quality => identity, df)
```

## GEDI Full Pipeline

Replicating the old `points(g)` behavior for GEDI:

```julia
g = granule("GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5")
t = table(g)
df = DataFrame(t)

# Apply basic quality filter (old points did this automatically)
filter!(df) do row
    !ismissing(row.quality) && row.quality &&
    !ismissing(row.surface) && row.surface
end
```

## `points()` Still Works

The old `points()` function is still available and unchanged — it still applies
all its built-in filtering and transforms. But new code should use `table()`.
