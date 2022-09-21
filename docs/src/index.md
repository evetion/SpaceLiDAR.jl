# SpaceLiDAR
A Julia toolbox for ICESat, ICESat-2 and GEDI data.

*This is a research package, things are quick to change.*


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

For a quick overview, see the FOSS4G Pluto notebook [here](tutorial/foss4g_2021.jl.html)


## Papers
Results are used (indirectly) in the following papers:

Vernimmen, Ronald, Aljosja Hooijer, and Maarten Pronk. 2020. ‘New ICESat-2 Satellite LiDAR Data Allow First Global Lowland DTM Suitable for Accurate Coastal Flood Risk Assessment’. Remote Sensing 12 (17): 2827. [https://doi.org/10/gg9dg6](https://doi.org/10/gg9dg6).

Hooijer, A., and R. Vernimmen. 2021. ‘Global LiDAR Land Elevation Data Reveal Greatest Sea-Level Rise Vulnerability in the Tropics’. Nature Communications 12 (1): 3592. [https://doi.org/10/gkzf49](https://doi.org/10/gkzf49).
