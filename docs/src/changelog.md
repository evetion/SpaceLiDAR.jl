## Unreleased

### New features
- New `H5Table` system: generic, lazy HDF5-to-table reader that handles dimension flattening, nodata masking (`missing`), and transforms automatically.
- `explore(granule)` opens an interactive terminal browser for inspecting HDF5 contents and selecting variables.
- `table(g; variables=)` keyword allows reading custom variable sets instead of only the built-in defaults.
- `table(g; tracks=)` keyword for filtering specific beams/tracks.
- Variables now support transforms: `ToDateTime`, `ToBool`, `InvertBool`, `SliceRow`.
- Attributes (track-level metadata like `strong_beam`, `detector_id`) are now included as constant columns.
- Pre-built alternative schemas: `atl08_canopy_variables()`, `gedi_l2a_canopy_variables()`.
- Documentation rewrite following the Diátaxis framework (tutorials, guides, topics, reference).

### Breaking
- `table(granule)` is now the recommended interface; `points()` remains available for compatibility (see migration guide).
- Fill values are now `missing` instead of `NaN`.
- `granule_from_file` → `granule`, `granules_from_folder` → `granules` (deprecated names still work).

### Changed
- Column types resolved at read time via transforms (e.g., `delta_time` becomes `DateTime`).
- All products now use the shared `H5Table` infrastructure instead of per-product hardcoded readers.

## v0.4.2

### Fixed
- Fix `download!` to create directories and normalize paths (#95).
- Update Makie compat to 0.24 (#93).
- Bump CategoricalArrays compat to 1.
- CI dependency bumps (actions/checkout v6, stefanzweifel/git-auto-commit-action v7).

## v0.4.1

### Fixed
- Fix ICESat-2 search after data migration to EarthData Cloud.

## v0.4.0

### New features
- New types `Table` and `PartitionedTable`, which support the Tables.jl interface. This prevents allocating code like `reduce(vcat, DataFrame.(points(granule)))` to get a DataFrame. You can now just call `DataFrame(table)`.
- Reduced allocations in retrieving point data.
- Introduced `before` and `after` keywords in `search`, to search by date(ranges).
- `sync` utility with aria2c for incremental folder updates.
- Makie extension for plotting (`plot(granules)`).
- `search(granule, :OtherProduct)` for cross-product granule lookup.
- `id` keyword in `search` for fetching specific granules.

### Fixed
- Empty (filtered) granules could result in `Vector{BitVector}` columns, which have been changed to `Vector{Bool}`.
- GEDI search after migration to LPCLOUD.

### Breaking
- `points` now return either a `Table` or a `PartitionedTable` instead of `NamedTuple` or `Vector{NamedTuple}`. The old behaviour can be regained by calling `parent` on these tables.
- Removed `number_of_returns` and `return_number` from ICESat-2 ATL08 canopy output.

### Deprecated
- Renamed `granule_from_file` to `granule`
- Renamed `granules_from_file` to `granules`
- Renamed `write_granule_urls!` to `write_urls`

### Changed
- Most of the search functionality has been moved out to the more generic [EarthData.jl](https://github.com/evetion/EarthData.jl).
- Updated ICESat-2 from version 5 to version 6.


## v0.3.0

- GeoInterface, Extents support
- Bounding box using Extent subsetting on all `points` functions
- `find` renamed to `search`
- `search` now takes the `product` as a `Symbol` and accepts a `s3::Bool` parameter.
- Stricter checking of arguments in `search`
- MultiPolygon extents of granules are now returned in the `polygons` field in granules from `search`.
- Removed `bbox` field on granules.
- `download(granule)` now works on AWS S3 urls
- `donwload(granule)` now creates temporary files and renames after successful download
- ICESat-2 ATL08 v5 `points` function now supports 20 m resolution by passing `highres::Bool` parameter.

## v0.2.2
- Fixed ICESat-2 download (please remove `n5eil01u.ecs.nsidc.org` from your `.netrc` file)
- Linked to [Zenodo](https://zenodo.org/badge/latestdoi/241095197) for DOI citations

## v0.2.1
- Unified `bounds` of granules
- Fixed `getcoord` for `Point` and added `Point(x, y, z)` constructor
- Updated utils to make use of DataFrames with correct column names

## v0.2.0

!!! warning
    This is a **breaking** release

- Many of the column names have changed to be more descriptive.
- Documentation and docstring improvements.
- Tables support, you can now do `DataFrame(granule)`, without having to call `points(granule)`.
- Memory use improvements, by using SentinelArray of FillArray under the hood.
- Dropped S3, GeoArrays and LAS/LAZ support.
- Added GeoInterface support for lines/points and dropped GeoDataFrames
- Expanded test coverage.

## v0.1.6
- Support for ICESat GLAH06 by [alex-s-gardner](https://github.com/alex-s-gardner) :+1::tada:

## v0.1.5
- Support for ICESat-2 ATL06
- Update search to use v5 for ICESat-2 by default

## v0.1.4
- Compatibility fixes

## v0.1.3
- Added interpolation for GeoArrays
- Added FOSS4G notebook
