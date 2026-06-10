# L2A — Ground Elevation & Canopy Height

Version 2 — [User Guide](https://lpdaac.usgs.gov/documents/998/GEDI02_UserGuide_V21.pdf) · [ATBD](https://lpdaac.usgs.gov/documents/581/GEDI_WF_ATBD_v1.0.pdf)

```@setup gedi
using SpaceLiDAR
using SpaceLiDAR.H5Tables: ToDateTime, ToDateTimeConst, ToBool, InvertBool, SliceRow
using Markdown

function resolved_type(v)
    f = v.f
    if f isa ToDateTime || f isa ToDateTimeConst
        "DateTime"
    elseif f isa ToBool || f isa InvertBool
        "Bool"
    else
        string(v.eltype)
    end
end

function vars_table(vars; attrs=nothing)
    header = "| Column | HDF5 Path | Type |\n|:---|:---|:---|\n"
    rows = ["`$(v.name)` | `$(v.path)` | $(resolved_type(v))" for v in vars]
    if attrs !== nothing
        for a in attrs
            rows = push!(rows, "`$(a.name)` | attribute | $(a.eltype == Any ? "—" : string(a.eltype))")
        end
    end
    Markdown.parse(header * join(["| " * r * " |" for r in rows], "\n"))
end

dummy(T) = T("", "", (;), [])
```

## Overview

GEDI L2A provides ground elevation, canopy height metrics, and relative height
(RH) metrics for each GEDI footprint. Data is organized by 8 beams.

## Quick Start

```julia
using SpaceLiDAR, DataFrames

g = granule("GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5")
t = table(g)
df = DataFrame(t)
```

## Default Columns

```@example gedi
g = dummy(GEDI_Granule{:GEDI02_A}) # hide
vars_table(SpaceLiDAR.default_variables(g); attrs=SpaceLiDAR.default_attributes(g)) # hide
```

## Default Tracks

```@example gedi
SpaceLiDAR.default_tracks(g)
```

## Canopy Heights

Use `gedi_l2a_canopy_variables()` to read highest return instead of lowest mode:

```julia
t = table(g; variables=gedi_l2a_canopy_variables())
```

This reads `elev_highestreturn` / `lon_highestreturn` / `lat_highestreturn`.

## Quality Filtering

```julia
df = DataFrame(t)

# Basic quality (matches quality_flag):
filter!(:quality => identity, df)

# L3-style filtering:
filter!(row -> row.quality && row.surface, df)
# For sensitivity filtering (optional):
filter!(row -> 0.9 < row.sensitivity <= 1.0, df)
```

For the full L3 filter (including algorithm-based zcross/toploc checks),
you would need to read additional variables:

```julia
vars = [SpaceLiDAR.default_variables(g)...,
    Variable(:selected_algorithm, "selected_algorithm", UInt8),
    Variable(:rx_assess_quality_flag, "rx_assess/quality_flag", UInt8),
    Variable(:degrade_flag, "degrade_flag", UInt8),
    Variable(:stale_return_flag, "geolocation/stale_return_flag", UInt8),
    Variable(:rx_maxamp, "rx_assess/rx_maxamp", Float32),
    Variable(:sd_corrected, "rx_assess/sd_corrected", Float32),
]
t = table(g; variables=vars)
df = DataFrame(t)

# Apply L3 criteria:
filter!(df) do row
    row.rx_assess_quality_flag != 0 &&
    row.surface &&
    row.stale_return_flag == 0 &&
    row.degrade_flag == 0 &&
    row.rx_maxamp / row.sd_corrected >= 8
end
```
