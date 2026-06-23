# GLAH06 — Land Ice Elevation

Version 34 — [User Guide](https://nsidc.org/sites/nsidc.org/files/MULTI-GLAH01-V033-V034-UserGuide.pdf) · [ATBD](https://eospso.nasa.gov/sites/default/files/atbd/ATBD-GLAS-02.pdf)

```@setup glah06
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

GLAH06 provides 40 Hz ice sheet elevation data from the Geoscience Laser
Altimeter System (GLAS) instrument on ICESat.

## Quick Start

```julia
using SpaceLiDAR, DataFrames

g = granule("GLAH06_634_2131_002_0084_4_01_0001.H5")
t = table(g)
df = DataFrame(t)
```

## Default Columns

```@example glah06
g = dummy(ICESat_Granule{:GLAH06}) # hide
vars_table(SpaceLiDAR.default_variables(g)) # hide
```

## Coordinate System

!!! warning "TOPEX/Poseidon ellipsoid"
    ICESat data uses the TOPEX/Poseidon ellipsoid, NOT WGS84.
    Call `topex_to_wgs84!(df)` to convert heights to WGS84.

Heights must be corrected for saturation *before* reprojection:

```julia
t = table(g)
df = DataFrame(t)
dropmissing!(df, :height)
icesat_saturation_correct!(df)  # height += saturation_correction
topex_to_wgs84!(df)             # reproject to WGS84
```

## Quality Flag

The quality flag from Smith et al. (2020) combines multiple criteria:

```julia
q = icesat_quality(df)
# Equivalent to:
# (elev_use_flg == "valid") & (sigma_att_flg == "good") & (i_numPk == 1) & (saturation_correction < 3)
```
