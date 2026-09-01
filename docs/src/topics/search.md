# Search & Discovery

SpaceAltimetry provides tools to find granules — both locally and from NASA's
Common Metadata Repository (CMR).

Remote search is implemented by
[EarthData.jl](https://github.com/evetion/EarthData.jl), which was split out of
SpaceAltimetry's original search and download code. SpaceAltimetry keeps the
mission-specific defaults and converts EarthData's typed CMR records into its ICESat,
ICESat-2, and GEDI granule types. Use EarthData.jl directly for generic NASA Earthdata
collections outside these LiDAR missions.

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
using SpaceAltimetry, Dates, Extents

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
search(:ICESat2)          # defaults to ATL03, version 7
search(:ICESat2, :ATL08)  # ATL08, version 7
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
