[![DOI](https://zenodo.org/badge/241095197.svg)](https://zenodo.org/badge/latestdoi/241095197)
# SpaceLiDAR
A Julia toolbox for ICESat, ICESat-2 and GEDI data. Quickly [search](tutorial/usage.md#search-for-data), download and [load](tutorial/usage.md#derive-points) filtered point data with relevant attributes from the `.h5` granules of each data product. For an overview with code examples, see the FOSS4G Pluto notebook [here](tutorial/foss4g_2021.jl.html).

If you use SpaceLiDAR in your research, please consider [citing it](https://zenodo.org/badge/latestdoi/241095197).

## Supported data products
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


## Documentation
This documentation is set up using the [Divio](https://documentation.divio.com/) documentation system and thus split into [Tutorials](tutorial/usage.md), [Guides](guides/downloads.md), [Topics](topics/GEDI.md) and [References](reference/search.md).

## Publications
The code produced for the following paper was the beginning of this package:

> Vernimmen, Ronald, Aljosja Hooijer, and Maarten Pronk. 2020. ‘New ICESat-2 Satellite LiDAR Data Allow First Global Lowland DTM Suitable for Accurate Coastal Flood Risk Assessment’. Remote Sensing 12 (17): 2827. [https://doi.org/10/gg9dg6](https://doi.org/10/gg9dg6).

The DTM produced using ICESat-2 ATL08 data was in turn used for:

> Hooijer, A., and R. Vernimmen. 2021. ‘Global LiDAR Land Elevation Data Reveal Greatest Sea-Level Rise Vulnerability in the Tropics’. Nature Communications 12 (1): 3592. [https://doi.org/10/gkzf49](https://doi.org/10/gkzf49).
