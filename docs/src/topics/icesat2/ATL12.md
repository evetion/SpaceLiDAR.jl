# ATL12 — Ocean Surface Height

Version 5 — [User Guide](https://nsidc.org/sites/default/files/documents/user-guide/atl12-v006-userguide.pdf) · [ATBD](https://icesat-2.gsfc.nasa.gov/sites/default/files/page_files/ICESat2_ATL12_ATBD_r006.pdf)

```@setup atl12
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

ATL12 provides along-track sea surface heights.

## Quick Start

```julia
using SpaceLiDAR, DataFrames

g = granule("ATL12_20220404110409_01891501_006_02.h5")
t = table(g)
df = DataFrame(t)
```

## Default Columns

```@example atl12
g = dummy(ICESat2_Granule{:ATL12}) # hide
vars_table(SpaceLiDAR.default_variables(g); attrs=SpaceLiDAR.default_attributes(g)) # hide
```
