## v0.3.0

!!! danger
    This is a **breaking** release

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

!!! danger
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
