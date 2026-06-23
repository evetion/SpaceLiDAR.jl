# Track Filtering

ICESat-2 and GEDI emit multiple beams simultaneously. By default `table(g)`
reads all beams, returning a `PartitionedH5Table` with one partition per beam.
Use the `tracks` keyword to restrict which beams are loaded.

## ICESat-2 beams

ICESat-2 has 6 beam pairs: `gt1l`, `gt1r`, `gt2l`, `gt2r`, `gt3l`, `gt3r`.
Strong and weak beams alternate based on spacecraft orientation.

```julia
using SpaceLiDAR

g = granule("ATL08_20201121151145_08920913_006_01.h5")

# Only left beams
t = table(g; tracks=["gt1l", "gt2l", "gt3l"])

# Single beam
t = table(g; tracks=["gt1l"])
```

## GEDI beams

GEDI has 8 beams: `BEAM0000`, `BEAM0001`, `BEAM0010`, `BEAM0011`,
`BEAM0101`, `BEAM0110`, `BEAM1000`, `BEAM1011`.

```julia
g = granule("GEDI02_A_2019242104318_O04046_01_T02343_02_003_02_V002.h5")

# Full-power beams only
t = table(g; tracks=["BEAM0101", "BEAM0110", "BEAM1000", "BEAM1011"])
```

## Default tracks

To see what tracks are read by default for a granule:

```julia
SpaceLiDAR.default_tracks(g)
# ("gt1l", "gt1r", "gt2l", "gt2r", "gt3l", "gt3r")  for ICESat-2
# ("BEAM0000", ..., "BEAM1011")                       for GEDI
```

ICESat (GLAH) has no beam structure — `table(g)` always returns a single table.

## Iterating over tracks

Each partition in a `PartitionedH5Table` corresponds to one track:

```julia
using DataFrames, Tables

t = table(g)
for part in Tables.partitions(t)
    df = DataFrame(part)
    # process one beam at a time
end
```
