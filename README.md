[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://evetion.github.io/SpaceLiDAR.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://evetion.github.io/SpaceLiDAR.jl/dev)
[![CI](https://github.com/evetion/SpaceLiDAR.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/evetion/SpaceLiDAR.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/evetion/SpaceLiDAR.jl/branch/master/graph/badge.svg?token=nztwnGtIcY)](https://codecov.io/gh/evetion/SpaceLiDAR.jl)
[![DOI](https://zenodo.org/badge/241095197.svg)](https://zenodo.org/badge/latestdoi/241095197)
[![Aqua QA](https://juliatesting.github.io/Aqua.jl/dev/assets/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

# SpaceLiDAR

SpaceLiDAR.jl searches, downloads, and reads spaceborne lidar data
from the ICESat, ICESat-2, and GEDI NASA missions. Granules are exposed as lazy
[Tables.jl](https://github.com/JuliaData/Tables.jl)-compatible HDF5 tables, so
you can inspect product data quickly and materialize only when you need to.

| [ICESat](docs/src/topics/ICESat.md) | [ICESat-2](docs/src/topics/ICESat-2.md) | [GEDI](docs/src/topics/GEDI.md) |
|:------------------------------------|:----------------------------------------|:--------------------------------|
| [GLAH06](docs/src/topics/icesat/GLAH06.md) — Land Ice | [ATL03](docs/src/topics/icesat2/ATL03.md) — Photons | [L2A](docs/src/topics/gedi/L2A.md) — Ground & Canopy |
| [GLAH14](docs/src/topics/icesat/GLAH14.md) — Land Surface | [ATL06](docs/src/topics/icesat2/ATL06.md) — Land Ice | |
| | [ATL08](docs/src/topics/icesat2/ATL08.md) — Vegetation | |
| | [ATL12](docs/src/topics/icesat2/ATL12.md) — Ocean | |

## Install

```julia
import Pkg
Pkg.add("SpaceLiDAR")
```

## Search and download

```julia
using Extents
using SpaceLiDAR

vietnam = Extent(X = (102.0, 107.0), Y = (8.0, 12.0))

# Search NASA CMR.
granules = search(:ICESat2, :ATL08; extent = vietnam, version = 7)

# Configure NASA Earthdata credentials once, then download selected granules.
netrc!("username", "password")
download!(granules[1], "data")

# Local files and folders can be opened directly.
g = granule(joinpath("data", granules[1].id))
gs = SpaceLiDAR.granules("data")
```

## Read as a lazy table

```julia
using DataFrames
using SpaceLiDAR

g = granule("ATL08_20201121151145_08920913_006_01.h5")
t = table(g)

# Materialize when you need a DataFrame or another Tables.jl sink.
df = DataFrame(t)
```

`table(g)` returns an `H5Table` for single-track products and a
`PartitionedH5Table` for multi-track products. Both satisfy the Tables.jl
column-access interface and keep the HDF5 file open while lazy; call `close(t)`
when you are done with a long-lived lazy table.

Select tracks or variables at read time:

```julia
t = table(g; tracks = ["gt1l", "gt1r"])

vars = SpaceLiDAR.default_variables(g)
push!(vars, Variable(:slope, "land_segments/terrain/h_te_slope", Float32))
t = table(g; variables = vars)
```

If you do not know the HDF5 layout, use the interactive explorer:

```julia
t = explore(g)
```

## Chain filters and transforms

Operations declare the columns they need from the HDF5 file. When piped from a lazy table, they
stay lazy until the final materializing sink, so SpaceLiDAR can auto-pull all
required HDF5 columns before reading:

```julia
using DataFrames
using Extents
using SpaceLiDAR

g = granule("GLAH14_634_1102_001_0071_0_01_0001.H5")
greenland = Extent(X = (-75.0, -10.0), Y = (58.0, 84.0))

df = table(g) |>
    InExtent(greenland) |>
    ICESatQuality() |>
    SaturationCorrect() |>
    TopexToWGS84() |>
    ToEGM2008() |>
    DataFrame
```

## More documentation

See the [online documentation](https://evetion.github.io/SpaceLiDAR.jl/dev) for
guides on downloads, track selection, custom variables, and product-specific
schemas. If you use SpaceLiDAR.jl in your research, please consider
[citing it](https://zenodo.org/badge/latestdoi/241095197).
