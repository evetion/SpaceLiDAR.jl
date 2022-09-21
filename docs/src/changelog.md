## Unreleased

## v0.2.0

!!! danger
    This is a **breaking** release

- Many of the column names have changed to be more descriptive.
- Documentation and docstring improvements.
- Tables support, you can now do `DataFrame(granule)`, without having to call `points(granule)`.
- Memory use improvements, by using SentinelArray of FillArray under the hood.
- Dropped S3, GeoArrays and LAS/LAZ support.
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
