# Getting Started

This tutorial walks you through a typical SpaceLiDAR workflow: search, download,
read data, and visualize. Each step is self-contained — skip to what you need.

## 1. Search for granules

```julia
using SpaceLiDAR

# Find all ATL08 granules worldwide
granules = search(:ICESat2, :ATL08)

# Restrict to a spatial extent and version
vietnam = Extent(X=(102.0, 107.0), Y=(8.0, 12.0))
granules = search(:ICESat2, :ATL08; extent=vietnam, version=6)

# GEDI works the same way
granules = search(:GEDI, :GEDI02_A; extent=vietnam)
```

A granule carries an ID, URL, and metadata:

```julia
g = granules[1]
g.id    # filename
g.url   # download URL
g.info  # parsed metadata (date, track, cycle, etc.)
```

## 2. Download

Set up NASA Earthdata credentials (once):

```julia
SpaceLiDAR.netrc!("username", "password")
```

Download a single granule or a batch (uses aria2c for parallel downloads):

```julia
# Single file
download!(g, "data/")

# Batch — aria2c handles parallelism and resuming
download!(granules, "data/")
```

See the [Downloading guide](../guides/downloads.md) for syncing folders and
incremental updates.

## 3. Load from disk

```julia
# Single file
g = granule("data/ATL08_20201121151145_08920913_006_01.h5")

# All granules in a folder (recursive)
gs = granules("data/")
```

## 4. Read as a table

```julia
using DataFrames

t = table(g)
df = DataFrame(t)
```

`table(g)` returns a lazy Tables.jl-compatible object. Columns are the default
variables for that product — see each product page for details.

Filter as you would any DataFrame:

```julia
# Keep only high-quality data
filter!(:quality => identity, df)
dropmissing!(df, :height)
```

## 5. Save results

```julia
using CSV
CSV.write("output.csv", df)
```

Or as a GeoPackage (requires GeoDataFrames):

```julia
using GeoDataFrames
GeoDataFrames.write("output.gpkg", df)
```

## 6. Quick plot

```julia
using CairoMakie

scatter(df.longitude, df.latitude; color=df.height, markersize=2)
```

## Next steps

- [Downloading guide](../guides/downloads.md) — syncing, resuming, aria2c details
- [Selecting variables](../guides/variables.md) — custom columns, canopy heights
- [Track filtering](../guides/tracks.md) — choosing specific beams
- [Migration guide](../guides/migration.md) — coming from `points()`
