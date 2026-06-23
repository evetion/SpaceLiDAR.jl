# ATL08 — Vegetation Height

Version 6 — [User Guide](https://nsidc.org/sites/default/files/documents/user-guide/atl08-v006-userguide.pdf) · [ATBD](https://nsidc.org/sites/default/files/documents/technical-reference/icesat2_atl08_atbd_v006_0.pdf)

```@setup atl08
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

ATL08 provides terrain and canopy heights from photon-counting lidar at 100 m segments.

## Quick Start

```julia
using SpaceLiDAR, DataFrames

g = granule("ATL08_20201121151145_08920913_006_01.h5")
t = table(g)        # terrain (ground) heights by default
df = DataFrame(t)
```

## Default Columns

```@example atl08
g = dummy(ICESat2_Granule{:ATL08}) # hide
vars_table(SpaceLiDAR.default_variables(g); attrs=SpaceLiDAR.default_attributes(g)) # hide
```

## Canopy Heights

Use `atl08_canopy_variables()` to read canopy height instead of terrain:

```julia
t = table(g; variables=atl08_canopy_variables())
```

This reads `land_segments/canopy/h_mean_canopy_abs` as the `:height` column.
