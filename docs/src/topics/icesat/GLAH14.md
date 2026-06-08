# GLAH14 — Land Surface Elevation

Version 34 — [User Guide](https://nsidc.org/sites/nsidc.org/files/MULTI-GLAH01-V033-V034-UserGuide.pdf) · [ATBD](https://eospso.nasa.gov/sites/default/files/atbd/ATBD-GLAS-02.pdf)

```@setup glah14
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

GLAH14 provides 40 Hz land surface elevation data with additional
atmospheric and surface characterization fields.

## Quick Start

```julia
using SpaceLiDAR, DataFrames

g = granule("GLAH14_634_1102_001_0071_0_01_0001.H5")
t = table(g)
df = DataFrame(t)
```

## Default Columns

```@example glah14
g = dummy(ICESat_Granule{:GLAH14}) # hide
vars_table(SpaceLiDAR.default_variables(g)) # hide
```

## Additional Fields

GLAH14 includes extra surface characterization compared to GLAH06:
`:clouds`, `:gain`, `:reflectivity`, `:attitude`, and `:saturation`.

Processing is the same as GLAH06 — see [GLAH06](GLAH06.md) for coordinate system
and quality flag details.
