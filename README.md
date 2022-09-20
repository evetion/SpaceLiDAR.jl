
[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://evetion.github.io/SpaceLiDAR.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://evetion.github.io/SpaceLiDAR.jl/dev)
[![CI](https://github.com/evetion/SpaceLiDAR.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/evetion/SpaceLiDAR.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/evetion/SpaceLiDAR.jl/branch/master/graph/badge.svg?token=nztwnGtIcY)](https://codecov.io/gh/evetion/SpaceLiDAR.jl)


# SpaceLiDAR
A Julia toolbox for ICESat-2 and GEDI data.

*This is a research package now, things are quick to change.*

Currently supports the following data products:

| mission | data product | User Guide (UG) | Algorithm Theoretical Basis Document (ATBD)|
|--- |--- |--- |--- |
|ICESat| GLAH06 v34 | [UG](https://nsidc.org/sites/nsidc.org/files/MULTI-GLAH01-V033-V034-UserGuide.pdf) | [ATBD](https://eospso.nasa.gov/sites/default/files/atbd/ATBD-GLAS-02.pdf) |
|ICESat| GLAH14 v34 | [UG](https://nsidc.org/sites/nsidc.org/files/MULTI-GLAH01-V033-V034-UserGuide.pdf) | [ATBD](https://eospso.nasa.gov/sites/default/files/atbd/ATBD-GLAS-02.pdf) |
|ICESat-2| ATL03 v5 | [UG](https://nsidc.org/sites/nsidc.org/files/ATL03-V005-UserGuide.pdf)  | [ATBD](https://icesat-2.gsfc.nasa.gov/sites/default/files/page_files/ICESat2_ATL03_ATBD_r005.pdf) |
|ICESat-2| ATL06 v5 | [UG](https://nsidc.org/sites/nsidc.org/files/ATL03-V005-UserGuide.pdf)  | [ATBD](https://icesat-2.gsfc.nasa.gov/sites/default/files/page_files/ICESat2_ATL06_ATBD_r005.pdf) |
|ICESat-2| ATL08 v5 | [UG](https://nsidc.org/sites/nsidc.org/files/ATL08-V005-UserGuide.pdf) | [ATBD](https://icesat-2.gsfc.nasa.gov/sites/default/files/page_files/ICESat2_ATL08_ATBD_r005.pdf) |
|ICESat-2| ATL12 v5 | [UG](https://nsidc.org/sites/nsidc.org/files/ATL12-V005-UserGuide.pdf) | [ATBD](https://icesat-2.gsfc.nasa.gov/sites/default/files/page_files/ICESat2_ATL12_ATBD_r005.pdf) |
|GEDI| L2A v2 | [UG](https://lpdaac.usgs.gov/documents/998/GEDI02_User_Guide_V2.pdf) | [ATBD](https://lpdaac.usgs.gov/documents/581/GEDI_WF_ATBD_v1.0.pdf) |

For a quick overview, see the FOSS4G Pluto notebook [here](https://www.evetion.nl/SpaceLiDAR.jl/dev/tutorial/foss4g_2021.jl.html)

# Install
```julia
] add SpaceLiDAR
```

# Usage
Search for data
```julia
using SpaceLiDAR
# Find all ATL08 granules
granules = find(:ICESat2, "ATL08")

# Find only ATL03 granules in a part of Vietnam
vietnam = (min_x = 102., min_y = 8.0, max_x = 107.0, max_y = 12.0)
granules = find(:ICESat2, "ATL08", vietnam, "004")

# Find GEDI granules in the same way
granules = find(:GEDI, "GEDI02_A")

# A granule is pretty simple
granule = granules[1]
granule.id  # filename
granule.url  # download url
granule.info  # derived information from id

# Downloading granules requires a setup .netrc with an NASA EarthData account
# we provide a helper function, that creates/updates a ~/.netrc or ~/_netrc
SpaceLiDAR.netrc!(<username>, <password>)  # replace with your credentials

# Afterward you can download (requires curl to be available on PATH)
fn = SpaceLiDAR.download!(granule)

# You can also load a granule from disk
granule = granule_from_file(fn)

# Or from a folder
local_granules = granules_from_folder(<folder>)

# Instantiate search results locally (useful for GEDI location indexing)
local_granules = instantiate(granules, <folder>)
```

Derive linestrings
```julia
using DataFrames
fn = "ATL03_20181110072251_06520101_003_01.h5"
g = SpaceLiDAR.granule_from_file(fn)
tlines = DataFrame(SpaceLiDAR.lines(g, step=10000))
Table with 4 columns and 6 rows:
     geom                       sun_angle  track        t
   ┌───────────────────────────────────────────────────────────────────────────
 1 │ wkbLineString25D geometry  38.3864    gt1l_weak    2018-11-10T07:28:01.688
 2 │ wkbLineString25D geometry  38.375     gt1r_strong  2018-11-10T07:28:02.266
 3 │ wkbLineString25D geometry  38.2487    gt2l_weak    2018-11-10T07:28:04.474
 4 │ wkbLineString25D geometry  38.1424    gt2r_strong  2018-11-10T07:28:07.374
 5 │ wkbLineString25D geometry  38.2016    gt3l_weak    2018-11-10T07:28:05.051
 6 │ wkbLineString25D geometry  38.1611    gt3r_strong  2018-11-10T07:28:06.344
SpaceLiDAR.GDF.write("lines.gpkg", tlines)
```
