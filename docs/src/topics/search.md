# Search & Discovery

SpaceLiDAR provides tools to find granules — both locally and from NASA's
Common Metadata Repository (CMR).

## Local Discovery

```julia
# Single file:
g = granule("ATL08_20201121151145_08920913_006_01.h5")

# All granules in a folder (recursive):
gs = granules("/data/icesat2/")
```

The file/folder functions detect the mission and product from the filename
automatically.

## Remote Search (NASA CMR)

```julia
using SpaceLiDAR, Dates, Extents

extent = Extent(X=(-10.0, 10.0), Y=(50.0, 60.0))

gs = search(:ICESat2, :ATL08; extent=extent, after=DateTime(2020, 1, 1))
```

This queries NASA's CMR API and returns a vector of granules with download URLs
and spatial footprints.

### Search parameters

| Parameter | Type | Description |
|:----------|:-----|:------------|
| `extent` | `Extent` | Bounding box to filter spatially |
| `version` | `Int` | Data product version (default varies per mission) |
| `after` | `DateTime` | Only granules acquired after this date |
| `before` | `DateTime` | Only granules acquired before this date |
| `id` | `String` / `Vector{String}` | Specific granule ID(s) |

### Mission-specific defaults

Each mission has different default products and providers:

```julia
search(:ICESat2)          # defaults to ATL03, version 6
search(:ICESat2, :ATL08)  # ATL08, version 6
search(:GEDI)             # defaults to GEDI02_A, version 2
search(:ICESat)           # defaults to GLAH14, version 34
```

## Cross-product search

Find the matching granule of a different product for the same orbit/time:

```julia
# Find the ATL03 granule corresponding to an ATL08 granule
g08 = search(:ICESat2, :ATL08; extent=extent)[1]
g03 = search(g08, :ATL03)  # same orbit, different product
```

## Spatial footprints

Each granule carries a polygon footprint from the CMR metadata, useful for
visualization or precise spatial filtering before downloading large datasets.
