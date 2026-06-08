[![DOI](https://zenodo.org/badge/241095197.svg)](https://zenodo.org/badge/latestdoi/241095197)
# SpaceLiDAR

A Julia toolbox for the spaceborne lidar data from the ICESat, ICESat-2 and GEDI NASA missions. Quickly [search](tutorial/usage.md#1-search-for-granules), download and [load](tutorial/usage.md#4-read-as-a-table) filtered point data with relevant attributes from the `.h5` granules of each data product.

If you use SpaceLiDAR in your research, please consider [citing it](https://zenodo.org/badge/latestdoi/241095197). Feel free to submit issues and PRs to support more products. Note that you can also use SpaceLiDAR.jl for unsupported products.

## Supported data products

| [ICESat](topics/ICESat.md) | [ICESat-2](topics/ICESat-2.md) | [GEDI](topics/GEDI.md) |
|:---------------------------|:-------------------------------|:-----------------------|
| [GLAH06](topics/icesat/GLAH06.md) — Land Ice | [ATL03](topics/icesat2/ATL03.md) — Photons | [L2A](topics/gedi/L2A.md) — Ground & Canopy |
| [GLAH14](topics/icesat/GLAH14.md) — Land Surface | [ATL06](topics/icesat2/ATL06.md) — Land Ice | |
| | [ATL08](topics/icesat2/ATL08.md) — Vegetation | |
| | [ATL12](topics/icesat2/ATL12.md) — Ocean | |


## Documentation
This documentation follows the [Diátaxis](https://diataxis.fr/) framework: [Tutorials](tutorial/usage.md), [Guides](guides/downloads.md), [Topics](topics/HDF5.md), and [Reference](reference/api.md).

## Publications
The code produced for the following paper was the beginning of this package:

> Vernimmen, Ronald, Aljosja Hooijer, and Maarten Pronk. 2020. ‘New ICESat-2 Satellite LiDAR Data Allow First Global Lowland DTM Suitable for Accurate Coastal Flood Risk Assessment’. Remote Sensing 12 (17): 2827. [https://doi.org/10/gg9dg6](https://doi.org/10/gg9dg6).

The DTM produced using ICESat-2 ATL08 data was in turn used for:

> Hooijer, A., and R. Vernimmen. 2021. ‘Global LiDAR Land Elevation Data Reveal Greatest Sea-Level Rise Vulnerability in the Tropics’. Nature Communications 12 (1): 3592. [https://doi.org/10/gkzf49](https://doi.org/10/gkzf49).
