# AGENTS.md

Instructions for AI coding agents working on **SpaceLiDAR.jl**. This is a
high-level orientation document — read it before touching the codebase.

## What this package does

SpaceLiDAR.jl ingests HDF5 granules from spaceborne LiDAR missions
(ICESat, ICESat‑2, GEDI) and exposes them as Julia tables (Tables.jl /
DataFrames). It also supports searching/downloading granules from NASA's
CMR + S3 + Aria2, geoid conversion (EGM2008, TOPEX), and a GeoInterface
adapter for `lines` / `points`.

Two pipelines coexist:

1. **Schema-based, fast path** — `table(g::Granule)` uses hand-written
   `default_variables(g)` / `default_attributes(g)` templates per product
   (ATL03, ATL06, ATL08, ATL12, GLAH06, GLAH14, GEDI02_A). Optimised for
   throughput: a `template` `H5Table` is built once for the first track and
   reused across tracks via path remapping.
2. **Generic / interactive path** — `H5Table(file; vars=...)` and
   `explore(file)` work on arbitrary HDF5 layouts: dimensions, references,
   CF coordinates and flag attributes are resolved from metadata.

Both produce `H5Table` (per-track) / `PartitionedH5Table` (multi-track),
which satisfy the Tables.jl column-access interface.

## Repository layout

```
src/
├── SpaceLiDAR.jl          # Top-level module, re-exports H5Table helpers
├── granule.jl             # abstract type Granule + download/AWS plumbing
├── search.jl              # CMR (NASA) granule search
├── geoid.jl               # EGM2008 / TOPEX height conversions
├── geom.jl, geointerface.jl  # lines/points + GeoInterface integration
├── table.jl               # Table / PartitionedTable + `table(g::Granule)` dispatch
├── utils.jl, env.jl, precompile.jl
│
├── H5Table/               # Generic HDF5 → Tables.jl reader (self-contained submodule)
│   ├── H5Table.jl         # Module + exports
│   ├── table.jl           # Core: Variable, Attribute, transforms, dim resolution
│   └── explore.jl         # Interactive TreeMenu-based explorer
│
├── GEDI/                  # GEDI_Granule + per-product schemas
│   ├── GEDI.jl
│   └── L2A.jl
├── ICESat-2/              # ICESat2_Granule + per-product schemas
│   ├── ICESat-2.jl
│   ├── ATL03.jl, ATL06.jl, ATL08.jl, ATL12.jl
└── ICESat/                # ICESat_Granule + GLAH06/GLAH14

test/
├── runtests.jl            # entry; downloads test artifacts from a side repo
├── h5table.jl             # Generic H5Table + explorer tests
└── sl.jl                  # Mission/granule level integration tests

docs/                      # Documenter site (also rendered via mkdocs)
```

## Granule abstraction

`abstract type Granule` lives in `granule.jl`. Concrete granules are
parameterized on a product symbol:

- `ICESat_Granule{:GLAH06}`, `ICESat_Granule{:GLAH14}`
- `ICESat2_Granule{:ATL03}`, `{:ATL06}`, `{:ATL08}`, `{:ATL12}`
- `GEDI_Granule{:GEDI02_A}`

A granule carries `(id, url, info, polygons)`. `table(g)` opens the file
and dispatches to the product-specific `default_variables(g)` schema.

## The H5Table submodule (where most of the action happens)

`H5Table` is a small, self-contained submodule. Treat it as a generic
"HDF5 → Tables.jl" engine. SpaceLiDAR product templates are just
collections of `Variable` / `Attribute` specs handed to it.

### Core types (`src/H5Table/table.jl`)

- `Variable(name, path, eltype, transform=identity)` — one HDF5 dataset
  becomes one column. `inner`/`outer` are repeat factors set during
  flattening.
- `Attribute(name, group, attribute, f, eltype)` — HDF5 attribute
  broadcast across rows via `FillArrays.Fill`.
- `H5Table(f, vars, attrs, nrow)` — built table, satisfies `Tables.jl`.
- `PartitionedH5Table(tables)` — concatenates per-track `H5Table`s.

### Transforms

Transforms are *spec* structs that get resolved at table-build time into
1‑arg closures via `resolve_transform(spec, file, path)`:

| Spec               | Effect at read time                          | Shape change          |
|--------------------|----------------------------------------------|-----------------------|
| `identity`         | passthrough                                  | none                  |
| `ToDateTime(epoch_path, offset)` | `unix2datetime.(x .+ epoch)`     | none                  |
| `ToDateTimeConst(offset)`        | `unix2datetime.(x .+ offset)`    | none                  |
| `ToBool`           | `!iszero.(x)`                                | none                  |
| `InvertBool`       | `iszero.(x)`                                 | none                  |
| `SliceRow(row)`    | `data[row, :]` — collapses Julia axis 1      | 2D → 1D (axis 2 kept) |
| `ExpandDims(counts_path)` | repeats segment[i] `counts[i]` times  | 1D (N_seg) → 1D (N_ph)|

All transforms must handle `Union{T,Missing}` inputs (masking from
`_FillValue` / `valid_range` happens *before* the transform).

When you add a transform that changes a variable's *shape*, also extend
`apply_transform_dims(::YourTransform, vdims)` so the global dimension
resolver (see below) sees the post-transform dim list rather than the
raw HDF5 axes. Default fallthrough is identity, which is correct for any
elementwise transform.

### Dimension resolution

Most HDF5 datasets have multiple axes; tables are flat. The H5Table
builder reconciles this:

1. `resolve_var_dims(file, path)` returns each variable's dim IDs in
   Julia order (`[axis1_fast, axis2_slow, ...]`), trying — in order:
   HDF5 dimension scales (`DIMENSION_LIST`), `CLASS="DIMENSION_SCALE"`
   / `REFERENCE_LIST`, CF `coordinates` attribute, then a path-based
   fallback for 1D datasets.
2. `apply_transform_dims(transform, vdims)` filters that list through
   the variable's transform (e.g. `SliceRow` drops the sliced axis).
3. `_pick_global_dims(all_dims)` picks the longest dim list as global
   order and validates that every variable's dims appear in a
   consistent relative order.
4. `compute_repeat(global_dims, dim_sizes, var_dims)` computes
   `(inner, outer)` repeat factors so each column can be `vec`'d into
   `prod(dim_sizes)` rows.

The whole pipeline is bypassed when the caller supplies an explicit
`nrow` kwarg (the fast schema-template path does this).

### Column-major caveat

HDF5 is row-major (C-order); Julia is column-major. `resolve_var_dims`
reverses HDF5's slow→fast `DIMENSION_LIST` so the first entry in `vdims`
corresponds to Julia's *fast* axis (axis 1). Keep this convention in
mind whenever you touch dim handling — for example, `SliceRow` operates
as `data[row, :]`, collapsing axis 1, which is the *fast* axis (i.e.
the *last* entry of HDF5's own `DIMENSION_LIST`, but the *first* entry
in `vdims`).

### `explore()` interactive UI

`explore(file)` opens a `TerminalMenus.TreeMenu` of the HDF5 hierarchy,
with hotkeys: `space` (select), `a` (toggle attributes), `d`/`r` (auto
include dimensions/references), `c` (clear), `q` (done). Compatibility
checks reuse `is_dim_compatible` so users can't select axes that
wouldn't flatten cleanly together.

## Common pitfalls when modifying H5Table

- **Don't open datasets without closing them**. Every `HDF5.open_dataset`
  needs a matching `close`, otherwise file handles leak.
- **Don't add transforms that change shape without updating
  `apply_transform_dims`** — the table's `nrow` will silently be wrong.
- **`_h5read` and `_h5read_attr` are low-level fast paths**. Always
  prefer them over `HDF5.read` for known primitive types; fall back to
  `HDF5.read` only for strings/compounds.
- **The schema-based fast path passes explicit `nrow`** to skip dim
  resolution. If you add a new template that mixes 1D variables with a
  multi-dim or shape-changing transform, double-check
  `_quick_nrow`/`_has_track_transform` in `src/table.jl`.
- **`PartitionedH5Table` concatenates by column**. Per-track schemas
  must produce identical column sets (names + eltypes) — `Tables.schema`
  reads from the first partition only.

## Tests

- `julia --project=. -e 'using Pkg; Pkg.test()'` runs everything (downloads
  ~200 MB of test granules from the
  `evetion/SpaceLiDAR-artifacts` releases on first run, cached in
  `test/data/`).
- `test/h5table.jl` is the right place to add focused regression tests
  for any dim resolution / transform / explorer change.
- `test/sl.jl` covers end-to-end `table(g)` per product and search/
  download stubs.

## Style

- `.JuliaFormatter.toml` is checked in — but the codebase is *not*
  uniformly formatted. Don't reformat unrelated code; only format what
  you touch.
- Comments: prefer docstrings on public-facing functions, inline
  comments only where intent isn't obvious from the code (e.g. column-
  major reversal, transform-aware dim handling).
- Keep submodule boundaries: `H5Table` should remain usable as a
  standalone generic reader; SpaceLiDAR-specific logic stays in
  `src/{GEDI,ICESat,ICESat-2}/`.

## When in doubt

- Generic HDF5 question? Look at `src/H5Table/table.jl` first.
- Per-product variable names / paths? Look at the product file
  (`src/ICESat-2/ATL03.jl`, etc.) — each has a documentation table at
  the top.
- Architecture / design rationale? Look for the block comments in
  `H5Table(file; ...)` (the builder constructor) and in
  `resolve_var_dims` — they explain the non-obvious choices.
