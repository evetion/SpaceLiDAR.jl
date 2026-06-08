# Selecting Variables

By default, `table(g)` reads a curated set of variables for each product.
You can customize which columns you get.

## Viewing defaults

```julia
using SpaceLiDAR

g = granule("ATL08_20201121151145_08920913_006_01.h5")
vars = SpaceLiDAR.default_variables(g)
```

Each `Variable` has a name, HDF5 path, element type, and optional transform.

## Adding extra columns

Append to the defaults:

```julia
vars = SpaceLiDAR.default_variables(g)
push!(vars, Variable(:slope, "land_segments/terrain/h_te_slope", Float32))
push!(vars, Variable(:canopy_h, "land_segments/canopy/h_mean_canopy", Float32))

t = table(g; variables=vars)
```

## Canopy height variants

ATL08 and GEDI have pre-defined canopy variable sets:

```julia
# ATL08 canopy (reads h_mean_canopy_abs instead of h_te_mean)
t = table(g; variables=SpaceLiDAR.atl08_canopy_variables())

# GEDI canopy (reads elev_highestreturn instead of elev_lowestmode)
t = table(g; variables=SpaceLiDAR.gedi_l2a_canopy_variables())
```

## Custom variable from scratch

A `Variable` needs at minimum a name, path, and type:

```julia
Variable(:my_col, "land_segments/some/dataset", Float32)
```

With a transform (applied at read time):

```julia
Variable(:is_land, "land_segments/surf_type", Int8, ToBool())
Variable(:time, "land_segments/delta_time", Float64,
    ToDateTime("/ancillary_data/atlas_sdp_gps_epoch", SpaceLiDAR.gps_offset))
```

Available transforms:

| Transform | Effect |
|:----------|:-------|
| `ToBool()` | nonzero → `true` |
| `InvertBool()` | zero → `true` |
| `ToDateTime(epoch_path, offset)` | delta_time → DateTime |
| `ToDateTimeConst(offset)` | delta_time → DateTime (fixed epoch) |
| `SliceRow(n)` | take row `n` from 2D dataset |

## Attributes

Attributes are scalar metadata attached to each track (partition):

```julia
attrs = SpaceLiDAR.default_attributes(g)
```

They become constant columns in the resulting table (e.g., `:detector_id`,
`:strong_beam`).

## Explore interactively

Don't know what's in the file? Use `explore`:

```julia
t = explore(g)
```

This opens an interactive browser showing all datasets, their dimensions,
and lets you select variables visually. The result is an `H5Table` ready
for `DataFrame(t)`.
