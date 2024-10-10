
[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://evetion.github.io/SpaceLiDAR.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://evetion.github.io/SpaceLiDAR.jl/dev)
[![CI](https://github.com/evetion/SpaceLiDAR.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/evetion/SpaceLiDAR.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/evetion/SpaceLiDAR.jl/branch/master/graph/badge.svg?token=nztwnGtIcY)](https://codecov.io/gh/evetion/SpaceLiDAR.jl)
[![DOI](https://zenodo.org/badge/241095197.svg)](https://zenodo.org/badge/latestdoi/241095197)

# SpaceLiDAR
A Julia toolbox for ICESat, ICESat-2 and GEDI data. Quickly search, download, and load filtered point data with relevant attributes from the `.h5` granules of each data product.

Currently supports the following data products:

| mission | data product | User Guide (UG) | Algorithm Theoretical Basis Document (ATBD)|
|--- |--- |--- |--- |
|ICESat| GLAH06 v34 | [UG](https://nsidc.org/sites/nsidc.org/files/MULTI-GLAH01-V033-V034-UserGuide.pdf) | [ATBD](https://eospso.nasa.gov/sites/default/files/atbd/ATBD-GLAS-02.pdf) |
|ICESat| GLAH14 v34 | [UG](https://nsidc.org/sites/nsidc.org/files/MULTI-GLAH01-V033-V034-UserGuide.pdf) | [ATBD](https://eospso.nasa.gov/sites/default/files/atbd/ATBD-GLAS-02.pdf) |
|ICESat-2| ATL03 v6 | [UG](https://nsidc.org/sites/default/files/documents/user-guide/atl03-v006-userguide.pdf)  | [ATBD](https://icesat-2.gsfc.nasa.gov/sites/default/files/page_files/ICESat2_ATL03_ATBD_r006.pdf) |
|ICESat-2| ATL06 v5 | [UG](https://nsidc.org/sites/default/files/documents/user-guide/atl06-v006-userguide.pdf)  | [ATBD](https://icesat-2.gsfc.nasa.gov/sites/default/files/page_files/ICESat2_ATL06_ATBD_r006.pdf) |
|ICESat-2| ATL08 v6 | [UG](https://nsidc.org/sites/default/files/documents/user-guide/atl08-v006-userguide.pdf) | [ATBD](https://nsidc.org/sites/default/files/documents/technical-reference/icesat2_atl08_atbd_v006_0.pdf) |
|ICESat-2| ATL12 v5 | [UG](https://nsidc.org/sites/default/files/documents/user-guide/atl12-v006-userguide.pdf) | [ATBD](https://icesat-2.gsfc.nasa.gov/sites/default/files/page_files/ICESat2_ATL12_ATBD_r006.pdf) |
|GEDI| L2A v2 | [UG](https://lpdaac.usgs.gov/documents/998/GEDI02_UserGuide_V21.pdf) | [ATBD](https://lpdaac.usgs.gov/documents/581/GEDI_WF_ATBD_v1.0.pdf) |

For an overview with code examples, see the FOSS4G Pluto notebook [here](https://www.evetion.nl/SpaceLiDAR.jl/dev/tutorial/foss4g_2021.jl.html)

If you use SpaceLiDAR.jl in your research, please consider [citing it](https://zenodo.org/badge/latestdoi/241095197).

# Install
```julia
]add SpaceLiDAR
```

# Usage
Search for data
```julia
using SpaceLiDAR
using Extents
# Find all ATL08 granules ever
granules = search(:ICESat2, :ATL08)

# Find only ATL03 granules in a part of Vietnam
vietnam = Extent(X=(102.0, 107.0), Y=(8.0, 12.0))
granules = search(:ICESat2, :ATL08; extent=vietnam, version=6)

# Find GEDI granules in the same way
granules = search(:GEDI, :GEDI02_A; extent=vietnam)

# A granule is pretty simple
granule = granules[1]
granule.id  # filename
granule.url  # download url
granule.info  # derived information from id

# Downloading granules requires a setup .netrc with an NASA EarthData account
# we provide a helper function, that creates/updates a ~/.netrc or ~/_netrc
SpaceLiDAR.netrc!(username, password)  # replace with your credentials

# Afterward you can download the dataset.
# Note: download! updated granule url to local path
granule = SpaceLiDAR.download!(granule)

# You can also load a granule from disk
path2file = granule.url
granule = SpaceLiDAR.granule(path2file)

# Or from a folder
(folder, fn) = splitdir(path2file)
local_granules = SpaceLiDAR.granules(folder)
```

Derive points
```julia
using DataFrames
fn = "GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5"
granule = SpaceLiDAR.granule(fn)

df = DataFrame(granule)
760156×15 DataFrame
    Row │ longitude  latitude   height   height_error  datetime                 intensity   sensitivity  surface  quality  nmodes  track     strong_beam  classification  sun_angle  height_reference 
        │ Float64    Float64    Float32  Float32       DateTime                 Float32     Float32      Bool     Bool     UInt8   String    Bool         String          Float32    Float32          
────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
      1 │   26.6923  51.823     169.045      0.313182  2019-04-18T10:22:23.996   -857.388      1.38006      true    false       1  BEAM0000        false  ground           49.0315            169.752
      2 │   26.7006  51.823     165.783      0.31319   2019-04-18T10:22:24.078    853.56       0.694586     true    false       1  BEAM0000        false  ground           49.0312            167.354
      3 │   26.7023  51.823     162.871      0.313192  2019-04-18T10:22:24.095    110.071     -0.480232     true    false       1  BEAM0000        false  ground           49.0311            164.785
   ⋮    │     ⋮          ⋮         ⋮          ⋮                   ⋮                 ⋮            ⋮          ⋮        ⋮       ⋮        ⋮           ⋮             ⋮             ⋮             ⋮
 760155 │  110.661   -0.194184  171.157      0.258848  2019-04-18T10:45:33.900   7702.96       0.945006     true     true       2  BEAM1011         true  ground           -1.94442           176.333
 760156 │  110.662   -0.195451  167.176      0.258852  2019-04-18T10:45:33.925   9595.64       0.981322     true     true       2  BEAM1011         true  ground           -1.94564           173.691
```


Derive linestrings
```julia
using DataFrames
fn = "GEDI02_A_2019108093620_O01965_03_T05338_02_003_01_V002.h5"
granule = SpaceLiDAR.granule(fn)
tlines = DataFrame.(SpaceLiDAR.lines(granule; step=10000))

SpaceLiDAR.GDF.write("lines.gpkg", tlines)
```
