## Unreleased
- Extents support
- Search using polygons
- ICESat-2 S3 access
- 20m resolution data in ICESat-2 ATL08 v05

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
