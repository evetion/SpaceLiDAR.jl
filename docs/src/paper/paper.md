---
title: 'SpaceLiDAR.jl: A Julia package for working with ICESat, ICESat-2, and GEDI data'
tags:
  - Julia
  - lidar
  - ICESat
  - ICESat-2
  - GEDI
  - HDF5
authors:
  - name: Maarten Pronk
    orcid: 0000-0001-8758-3939
    corresponding: true
    affiliation: 1
  - name: Alex Gardner
    orcid: 0000-0002-8394-8889
    affiliation: 2
affiliations:
 - name: Deltares, Delft, The Netherlands
   index: 1
   ror: 01deh9c76
 - name: NASA Jet Propulsion Laboratory
   index: 2
   ror: 027k65916
date: 26 June 2026
bibliography: refs.bib
---

# Summary

`SpaceLiDAR.jl` is a Julia [@bezansonJuliaFreshApproach2017] package for searching, downloading, and reading spaceborne lidar data from NASA's ICESat, ICESat-2, and GEDI missions.
It uses mission-specific granule types and product schemas to expose selected HDF5 variables as lazy [Tables.jl](https://github.com/JuliaData/Tables.jl)-compatible tables that integrate with the Julia ecosystem.

# Statement of need

The lidar satellite altimetry missions by NASA, ICESat (2003-2010) [@schutzOverviewICESatMission2005], ICESat-2 (2019-) [@markusIceCloudLand2017] and GEDI (2019-) [@dubayahGlobalEcosystemDynamics2020] are of great use to the scientific community as primary sources of ice-sheet elevation, as well as land topography and vegetation characteristics, among others.
The data is distributed as product-specific HDF5 granules, with different tracks, variables, quality flags, and coordinate conventions. Research using these datasets commonly requires searching by product, time, and area of interest; downloading authenticated files; selecting variables and tracks; and writing subsets into local tiling schemes.
The Python and R ecosystems have packages for (parts of) these workflows, but the Julia ecosystem does not. 
`SpaceLiDAR.jl` fills that gap, so spaceborne lidar data can be passed directly into Julia's geospatial and numerical workflows.

The package implements the following functionality:

- **Search**: `search` queries NASA CMR by mission, product, temporal range, and other metadata.
- **Download and sync**: `download` handles authenticated Earthdata downloads for individual granules. For larger jobs, bundled `aria2c` support enables parallel downloads, while `sync` maintains a local folder of granules by scanning existing files and downloading only what is missing.
- **Variable, attribute, and track selection**: Product-specific schemas define default variables, attributes, and tracks for common workflows. Users can add or replace variables with explicit HDF5 paths and transforms, restrict ICESat-2 and GEDI beams at read time, or use a terminal explorer for unfamiliar HDF5 layouts.
- **Lazy tables**: `table(g)` returns an `H5Table` for single-track products (ICESat) or a `PartitionedH5Table` for multi-track products (ICESat-2, GEDI), both implementing the Tables.jl column-access interface. Columns are read lazily from HDF5, while `_FillValue` and `valid_range` metadata become Julia `missing` values, flag variables become `CategoricalVectors`, and scalar attributes are broadcast as `FillArrays`.
- **Filtering and transformations**: Spatial and quality filtering, corrections, and geoid transformations can be chained with Julia's pipe syntax and are specialised to each product. Each operation declares the columns it needs, allowing `SpaceLiDAR.jl` to read the required HDF5 datasets once before materialisation.

The intended use case is repeated regional or global processing from local archives, with outputs remaining in Julia table and geospatial interfaces.

# State of the field

Several tools already support parts of the spaceborne lidar workflow. SlideRule [@sheanSlideRuleEnablingRapid2023] provides a server-side framework for rapid cloud processing of ICESat-2 data, and earthaccess [@barrettEarthaccess2026] provides a Python package for searching the NASA Earthdata archive.

For local ICESat-2 analysis, icepyx [@scheickIcepyxQueryingObtaining2023] supports querying, obtaining, and manipulating data in Python. The Photon Research and Engineering Analysis Library (PhoREAL) [@icesat-2utIcesat2UTPhoREAL2026] provides tools and a graphical workflow for ICESat-2 ATL03 and ATL08, while IceSat2R [@mouselimisMlamprosIceSat2R2026] provides ICESat-2 access in R.

For GEDI, gediDB [@besnardGediDBToolboxProcessing2025] provides a Python toolbox for processing and serving GEDI products. The R package rGEDI [@silvaCarlosalbertosilvaRGEDI2026] supports GEDI visualisation and processing.

`SpaceLiDAR.jl` differs by providing a Julia-native interface and by using the same granule, track-selection, table, and operation concepts across ICESat, ICESat-2, and GEDI. This makes mixed-mission workflows possible without separate mission-specific readers in the user's analysis code, something the Python- and R-based tools above cannot offer Julia users.

# Software design

`SpaceLiDAR.jl` is designed around mission abstractions combined with a geospatially aware but generic HDF5 reader. Scientific, mission-specific code remains in product schemas and operations, while the HDF5 table reader is reusable for arbitrary HDF5 files and provides the Julia integration. This design choice was made after early, hardcoded schemas limited extension and adoption.

- **Granules** are the central representation of mission files, storing the identifier, URL, local path, metadata, and footprint where available. Granules are parameterised by product, such as `ICESat2_Granule{:ATL08}` or `GEDI_Granule{:GEDI02_A}`, so Julia's multiple dispatch can use them in table construction and filtering.
- **Variables and attributes** describe how HDF5 datasets become table columns. Product schemas provide curated defaults for paths, element types, scalar attributes, and transforms, while users can inspect, append, replace, or define schemas for new products with a small number of methods.
- **The H5Table module** is a generic HDF5-to-Tables.jl layer. It resolves dimensions, flattens compatible multidimensional datasets, handles `_FillValue` and `valid_range` metadata, and encodes flag meanings where available.
- **Lazy operations** separate product semantics from HDF5 reading. Filters and transforms declare the variables they need, so missing input columns can be resolved from the product schema before the table is materialised.
- **Julia integration** is provided through interfaces such as `Tables.jl` and `GeoInterface.jl`. Tables can therefore be passed to existing Julia sinks and geospatial tools, with no-data values represented as `missing` and repeated or labelled values represented with `Fill` and `Categorical` vectors where appropriate.

# Research impact statement

The package grew out of code developed for the first global lowland digital terrain model derived from ICESat-2 satellite lidar [@vernimmenNewICESat2Satellite2020].
`SpaceLiDAR.jl` was first presented at JuliaCon 2021 [@pronkmSpaceLiDARjlProcessingICESat22021].

The package was further developed to assess ICESat-2 and GEDI as sources for global terrain modelling [@pronkAssessingVerticalAccuracy2024].
It also underpins DeltaDTM, a global coastal digital terrain model [@pronkDeltaDTMGlobalCoastal2024] that used the complete ICESat-2 ATL08 and GEDI L2A archive at the time.
It has since been used for glacier modelling [@gardnerSomethingSomethingSpaceLiDARjl2027].

# AI usage disclosure

AI tools were used during the creation of parts of the software and documentation.
They helped review implementations, identify bugs or inconsistencies, suggest documentation edits, and improve grammar and spelling, but were not used for the package's overall design, architecture, scientific validation, or interpretation of results.

# Acknowledgements

We thank the authors and maintainers of the packages in the [JuliaGeo](https://juliageo.org/) and wider Julia ecosystems on which `SpaceLiDAR.jl` builds.

# References
