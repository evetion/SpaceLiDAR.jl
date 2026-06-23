# Granules

A **granule** represents a single data file from a satellite mission. It is the
fundamental unit of data in SpaceLiDAR — every operation starts with one or more
granules.

## What is a Granule?

Each granule maps to one HDF5 file and carries metadata: a unique ID, a URL
(local path or remote), product info, and an optional spatial footprint (polygon).

## Granule Types

SpaceLiDAR defines a granule type per mission:

- `ICESat2_Granule{product}` — parameterized by product (`:ATL03`, `:ATL06`, `:ATL08`, `:ATL12`)
- `GEDI_Granule{product}` — parameterized by product (`:GEDI02_A`)
- `ICESat_Granule{product}` — parameterized by product (`:GLAH06`, `:GLAH14`)

## Getting Granules

```julia
# From a local file:
g = granule("ATL08_20201121151145_08920913_006_01.h5")

# From a folder (recursive):
gs = granules("/data/icesat2/")

# From NASA Earthdata search:
extent = Extent(X=(102.0, 107.0), Y=(8.0, 12.0))
gs = search(:ICESat2, :ATL08; extent=extent, after=DateTime(2020, 1, 1))
```

## Dispatching on Granules

The granule type determines which `default_variables`, `default_attributes`,
and `default_tracks` are used by `table(g)` and `explore(g)`.
