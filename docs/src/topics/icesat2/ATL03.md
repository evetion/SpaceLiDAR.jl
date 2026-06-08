# ATL03 — Geolocated Photons

Version 6 — [User Guide](https://nsidc.org/sites/default/files/documents/user-guide/atl03-v006-userguide.pdf) ·  [ATBD](https://icesat-2.gsfc.nasa.gov/sites/default/files/page_files/ICESat2_ATL03_ATBD_r006.pdf)

```@setup atl03
using SpaceLiDAR
using SpaceLiDAR.H5Table: ToDateTime, ToDateTimeConst, ToBool, InvertBool, SliceRow
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

ATL03 provides geolocated photon data — every individual photon detected by
the ATLAS instrument. This is the highest-resolution ICESat-2 product.

## Quick Start

```julia
using SpaceLiDAR, DataFrames

g = granule("ATL03_20201121151145_08920913_006_01.h5")
t = table(g)
df = DataFrame(t)
```

## Default Columns

```@example atl03
g = dummy(ICESat2_Granule{:ATL03}) # hide
vars_table(SpaceLiDAR.default_variables(g); attrs=SpaceLiDAR.default_attributes(g)) # hide
```

## Default Tracks

```@example atl03
g = dummy(ICESat2_Granule{:ATL03}) # hide
SpaceLiDAR.default_tracks(g)
```

## Filtering by Confidence

```julia
df = DataFrame(t)
# Keep only high-confidence photons
filter!(:confidence => >=(3), df)
```
