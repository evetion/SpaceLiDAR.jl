# Downloading

## Quick download

For a single granule, `download!` fetches from the URL and stores locally:

```julia
using SpaceAltimetry, Extents

vietnam = Extent(X=(102.0, 107.0), Y=(8.0, 12.0))

g = search(:ICESat2, :ATL08; extent=vietnam)[1]
download!(g, "data/")
g.url  # now points to "data/ATL08_..."
```

## Batch downloads with aria2c

Batch transfers are delegated to
[EarthData.jl](https://github.com/evetion/EarthData.jl), which uses bundled `aria2c`
for parallel, resumable HTTPS downloads:

```julia
granules = search(:ICESat2, :ATL08; extent=vietnam)
download!(granules, "data/")
```

EarthData writes the temporary URL list and calls `aria2c` with resume enabled. No
manual aria2 installation is needed.

## Credentials

NASA Earthdata requires authentication. Set up once:

```julia
SpaceAltimetry.netrc!("your_username", "your_password")
```

This delegates to `EarthData.netrc!`, which replaces any existing Earthdata Login stanza
and restricts the credential file to mode `600`. It writes `~/.netrc`, except on Windows,
where an existing `~/_netrc` is respected.

## Exporting URL lists

If you prefer to download externally (e.g., with wget or a download manager):

```julia
granules = search(:ICESat2, :ATL08; extent=vietnam)
SpaceAltimetry.write_urls("urls.txt", granules)
```

Then use any tool:
```bash
aria2c -c -i urls.txt -d data/
```

## Loading local granules

Once downloaded, load from disk:

```julia
# Single file — auto-detects mission and product from filename
g = granule("data/ATL08_20201121151145_08920913_006_01.h5")

# All .h5 files in a folder (recursive)
gs = granules("data/")
```

Files with `.aria2` suffixes (incomplete downloads) are automatically skipped.

## Syncing a folder

`sync` checks what you already have and downloads only new granules:

```julia
# Sync all products found in folder (downloads newer granules)
sync("data/")

# Sync a specific product
sync(:ATL08, "data/")

# Restrict sync to an extent
sync("data/"; extent=vietnam)
```

How it works:

1. Scans the folder for existing granules
2. Finds the latest date among them
3. Searches NASA CMR for granules *after* that date
4. Downloads only the new ones

To force a full re-check (not just newer):

```julia
sync("data/", true)  # all=true
```

## Incremental update pattern

A common workflow for keeping a local mirror up to date:

```julia
using SpaceAltimetry, Extents

folder = "/data/icesat2/atl08/"
vietnam = Extent(X=(102.0, 107.0), Y=(8.0, 12.0))

# First time: search and download everything
granules = search(:ICESat2, :ATL08; extent=vietnam)
download!(granules, folder)

# Later: just sync — only fetches what's new
sync(folder; extent=vietnam)
```
