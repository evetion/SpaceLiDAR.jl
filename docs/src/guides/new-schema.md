# Adding a New Product Schema

This guide walks through adding support for a new data product — using
a hypothetical ICESat-2 ATL24 (Bathymetry) as an example.

## 1. Create the product file

Create `src/ICESat-2/ATL24.jl`:

```julia
# Default variables for ATL24
function default_variables(::ICESat2_Granule{:ATL24})
    [
        Variable(:longitude, "profile_segments/longitude", Float64),
        Variable(:latitude, "profile_segments/latitude", Float64),
        Variable(:depth, "profile_segments/depth", Float32),
        Variable(:confidence, "profile_segments/confidence", Int8),
        Variable(:datetime, "profile_segments/delta_time", Float64,
            ToDateTime("/ancillary_data/atlas_sdp_gps_epoch", SpaceLiDAR.gps_offset)),
        Variable(:surface_h, "profile_segments/sea_surface_h", Float32),
    ]
end

# Default attributes (track-level metadata)
function default_attributes(::ICESat2_Granule{:ATL24})
    [
        Attribute(:detector_id, "atlas_spot_number",
            x -> parse(Int8, x)),
        Attribute(:strong_beam, "atlas_beam_type",
            x -> x == "strong"),
    ]
end
```

## 2. Include in the module

Add to `src/ICESat-2/ICESat-2.jl`:

```julia
include("ATL24.jl")
```

The granule type `ICESat2_Granule{:ATL24}` already exists — it's parameterized
on the product symbol, which is parsed from the filename automatically.

## 3. Verify it works

```julia
using SpaceLiDAR

g = granule("ATL24_20230101120000_01234567_006_01.h5")
typeof(g)  # ICESat2_Granule{:ATL24}

t = table(g)
df = DataFrame(t)
```

## 4. Add transforms if needed

If your product has fields that need special handling:

```julia
# Boolean flag (nonzero → true)
Variable(:ocean_flag, "profile_segments/ocean", Int8, ToBool())

# Inverted boolean (0 → true = good quality)
Variable(:quality, "profile_segments/qf", Int8, InvertBool())

# Row from a 2D dataset (e.g., first algorithm)
Variable(:depth_a1, "profile_segments/depth_algo", Float32, SliceRow(1))
```

## 5. Add canopy/alternative variable sets (optional)

If the product has multiple reading modes (like ATL08 ground vs canopy):

```julia
function atl24_shallow_variables()
    [
        Variable(:longitude, "profile_segments/longitude", Float64),
        Variable(:latitude, "profile_segments/latitude", Float64),
        Variable(:depth, "profile_segments/shallow/depth", Float32),
        Variable(:datetime, "profile_segments/delta_time", Float64,
            ToDateTime("/ancillary_data/atlas_sdp_gps_epoch", SpaceLiDAR.gps_offset)),
    ]
end
```

Export from `src/SpaceLiDAR.jl` if users need it directly.

## 6. Add documentation

Create `docs/src/topics/icesat2/ATL24.md` following the pattern of other
product pages (use `@example` blocks to auto-generate the column table).

Add to `docs/mkdocs.yml` under the ICESat-2 section:

```yaml
- ICESat-2:
    - ...
    - "ATL24": "topics/icesat2/ATL24.md"
```

## Summary

Adding a product requires only:

1. A `default_variables` method (required)
2. A `default_attributes` method (optional but recommended)
3. An `include` in the parent module file

Everything else — track replication, nodata handling, dimension flattening,
the `explore()` interface — comes for free from H5Table.
