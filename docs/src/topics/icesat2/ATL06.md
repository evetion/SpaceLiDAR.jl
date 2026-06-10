# ATL06 — Land Ice Height

Version 5 — [User Guide](https://nsidc.org/sites/default/files/documents/user-guide/atl06-v006-userguide.pdf) · [ATBD](https://icesat-2.gsfc.nasa.gov/sites/default/files/page_files/ICESat2_ATL06_ATBD_r006.pdf)

```@setup atl06
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

ATL06 provides along-track land ice surface heights at 40 m segment resolution.

## Quick Start

```julia
using SpaceLiDAR, DataFrames

g = granule("ATL06_20220404104324_01881512_006_02.h5")
t = table(g)
df = DataFrame(t)
```

## Default Columns

```@example atl06
g = dummy(ICESat2_Granule{:ATL06}) # hide
vars_table(SpaceLiDAR.default_variables(g); attrs=SpaceLiDAR.default_attributes(g)) # hide
```

## Common Workflows

### Geoid heights
```julia
t = table(g)
to_egm2008!(DataFrame(t))  # converts ellipsoidal → geoid heights
```

### Add custom variables
```julia
vars = SpaceLiDAR.default_variables(g)
push!(vars, Variable(:slope, "land_ice_segments/fit_statistics/dh_fit_dx", Float32))
t = table(g; variables=vars)
```
