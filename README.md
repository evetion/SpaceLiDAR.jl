
[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://evetion.github.io/SpaceLiDAR.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://evetion.github.io/SpaceLiDAR.jl/dev)
[![Build Status](https://travis-ci.com/evetion/SpaceLiDAR.jl.svg?branch=master)](https://travis-ci.com/evetion/SpaceLiDAR.jl)
[![Build Status](https://ci.appveyor.com/api/projects/status/github/evetion/SpaceLiDAR.jl?svg=true)](https://ci.appveyor.com/project/evetion/SpaceLiDAR-jl)
[![Codecov](https://codecov.io/gh/evetion/SpaceLiDAR.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/evetion/SpaceLiDAR.jl)
[![Code Style: Blue](https://img.shields.io/badge/code%20style-blue-4495d1.svg)](https://github.com/invenia/BlueStyle)

# SpaceLiDAR
A Julia toolbox for ICESat-2 and GEDI data.


# Install
```julia
] add SpaceLiDAR
```

# Usage
```julia
# Find all ATL08 granules
granules = find(:ICESat2, "ATL08")

# Find only ATL03 granules in a part of Vietnam
vietnam = (min_x = 102., min_y = 8.0, max_x = 107.0, max_y = 12.0)
granules = find(:ICESat2, "ATL03", vietnam, "001")

# Find GEDI granules in the same way
granules = find(:GEDI, "L2A")

# A granule is pretty simple
granule.id  # filename
granule.url  # download url

# Downloading granules requires a setup .netrc with an NASA EarthData account
download(granules[1])
```
