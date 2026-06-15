import Proj
import Tables
import DataAPI
import GeoFormatTypes
using CategoricalArrays: CategoricalValue

# These postprocess methods assume the contract produced by `table()`:
# every column value is either a real number or `missing` — no NaN sentinels.
# Predicates dispatch element-wise so `missing` short-circuits to `false` and
# arithmetic propagates `missing` naturally.
#
# The CategoricalValue methods compare against the flag-meaning *name*
# (e.g. "valid"), not the level code, so they're robust to pool ordering.
# Names are taken from the HDF5 `flag_meanings` attribute on the source
# datasets (see GLAH06/GLAH14 Quality groups).

_is_valid(::Missing) = false
_is_valid(x::Number) = iszero(x)
_is_valid(x::CategoricalValue) = x == "valid"          # elev_use_flg

_is_good(::Missing) = false
_is_good(x::Number) = iszero(x)
_is_good(x::CategoricalValue) = x == "good"            # sigma_att_flg

_one_peak(::Missing) = false
_one_peak(x::Number) = isone(x)                        # i_numPk

_sat_ok(::Missing) = false
_sat_ok(x::Number) = x < 3                             # saturation_correction

# ─── CRS metadata helpers ──────────────────────────────────────────────────────
# Projection methods read/write `"GEOINTERFACE:crs"` (the DataAPI convention
# used by GeoDataFrames, GeoInterface tooling, etc.) so they can:
#   1. Skip work when the table is already in the target CRS (avoids
#      double-projection bugs — applying `to_egm2008!` twice would subtract
#      the geoid undulation twice).
#   2. Stamp the new CRS onto the table after projecting, so downstream code
#      knows what the heights mean.
#
# Both operations are best-effort: tables that don't support metadata read
# (`NamedTuple`) are projected unconditionally; tables that don't support
# write (`SpaceLiDAR.Table`) are projected but the new CRS isn't recorded.

const _CRS_KEY = "GEOINTERFACE:crs"
const _CRS_WGS84_3D = GeoFormatTypes.EPSG(4979)               # WGS 84 ellipsoidal 3D
const _CRS_EGM2008  = GeoFormatTypes.EPSG(4326, 3855)         # WGS 84 + EGM2008 height

"""Read `"GEOINTERFACE:crs"` from `t`'s metadata. Returns `nothing` if the
table doesn't support metadata reads or the key is absent."""
function _get_crs(t)
    DataAPI.metadatasupport(typeof(t)).read || return nothing
    keys = try
        DataAPI.metadatakeys(t)
    catch
        return nothing
    end
    _CRS_KEY in keys || return nothing
    try
        DataAPI.metadata(t, _CRS_KEY)
    catch
        nothing
    end
end

"""Best-effort write of `"GEOINTERFACE:crs"`. No-op for read-only tables."""
function _try_set_crs!(t, crs)
    DataAPI.metadatasupport(typeof(t)).write || return t
    DataAPI.metadata!(t, _CRS_KEY, crs; style = :default)
    return t
end

# Each postprocess operation has three tiers of method:
#   fun!(cols...)    — innermost loop over already-extracted columns
#   fun!(t)          — extract columns from a Tables-compatible table, call fun!(cols...)
#   fun(t)           — non-mutating; returns a fresh table via fun!(copy(t))
#
# The split serves two purposes:
#   1. Coherent API: `fun!` mutates, `fun!` over columns is the kernel,
#      `fun` is non-mutating — same naming, no `_kernel!` jargon.
#   2. Performance: the column-level method is a function barrier so the
#      compiler specialises on concrete column eltypes, even when called
#      through a generically-typed table (~140× speedup observed for
#      `to_egm2008!`).
#
# `H5Table` / `PartitionedH5Table` are read-only, so only the non-mutating
# `fun(t)` is provided for them (it materialises via `collect`).

"""Materialize a fresh column table with copied columns (for non-mutating wrappers)."""
function _copy_columntable(t)
    cols = Tables.columntable(t)
    names = propertynames(cols)
    vals = map(name -> copy(Tables.getcolumn(cols, name)), names)
    return NamedTuple{names}(vals)
end


# ─── to_egm2008 ────────────────────────────────────────────────────────────────

"""
    to_egm2008!(t)
    to_egm2008(t)

Convert ellipsoid heights to EGM2008 geoid heights. Mutates / returns a copy
with `:height` overwritten. Rows where any of `:latitude`, `:longitude`,
`:height` is `missing` are left untouched.

If `t` carries `"GEOINTERFACE:crs"` metadata equal to `EPSG(4326, 3855)`, the
projection is skipped (idempotent — calling twice will not double-subtract
the geoid undulation). After a successful projection, the new CRS is written
to `t`'s metadata if writable.

`t` is any Tables.jl-compatible table whose `:height` column is a mutable
`AbstractVector` (e.g. `DataFrame`, `NamedTuple` of vectors, `SpaceLiDAR.Table`).
For read-only `H5Table` / `PartitionedH5Table`, only the non-mutating
`to_egm2008(t)` is defined.
"""
function to_egm2008!(t)
    src = _get_crs(t)
    if src !== nothing && src == _CRS_EGM2008
        @info "to_egm2008!: table already in $(_CRS_EGM2008), skipping"
        return t
    end
    Proj.enable_network!()
    trans = Proj.Transformation("EPSG:4979", "EPSG:3855")
    to_egm2008!(trans,
        Tables.getcolumn(t, :latitude),
        Tables.getcolumn(t, :longitude),
        Tables.getcolumn(t, :height))
    _try_set_crs!(t, _CRS_EGM2008)
    return t
end

function to_egm2008!(trans, lat, lon, h)
    @inbounds for i in eachindex(lat, lon, h)
        lai, loi, hi = lat[i], lon[i], h[i]
        (ismissing(lai) || ismissing(loi) || ismissing(hi)) && continue
        h[i] = trans(Proj.Coord(lai, loi, hi))[3]
    end
    return h
end

to_egm2008(t) = to_egm2008!(_copy_columntable(t))
to_egm2008(t::H5Tables.H5Table) = to_egm2008!(collect(t))
to_egm2008(t::H5Tables.PartitionedH5Table) = to_egm2008!(collect(t))
@doc (@doc to_egm2008!) to_egm2008


# ─── topex_to_wgs84 ────────────────────────────────────────────────────────────

"""
    topex_to_wgs84!(t)
    topex_to_wgs84(t)

Convert ICESat coordinates from the TOPEX/Poseidon ellipsoid to WGS84.
Transforms `:height` (and `:height_reference` if present). Latitude/longitude
differences are below instrument precision (~1e-6°) and are not modified.

If `t` carries `"GEOINTERFACE:crs"` metadata equal to `EPSG(4979)` (or
already in EGM2008), the projection is skipped — applying it twice would
corrupt heights. After a successful projection, the new CRS is written to
`t`'s metadata if writable.

Only meaningful for ICESat granules (GLAH06/GLAH14). Rows with missing inputs
are left untouched.
"""
function topex_to_wgs84!(t)
    src = _get_crs(t)
    if src !== nothing && (src == _CRS_WGS84_3D || src == _CRS_EGM2008)
        @info "topex_to_wgs84!: table already in $src, skipping"
        return t
    end
    pipe = topex_to_wgs84_ellipsoid()
    lon = Tables.getcolumn(t, :longitude)
    lat = Tables.getcolumn(t, :latitude)
    if hasproperty(t, :height_reference)
        topex_to_wgs84!(pipe, lon, lat, Tables.getcolumn(t, :height_reference))
    end
    topex_to_wgs84!(pipe, lon, lat, Tables.getcolumn(t, :height))
    _try_set_crs!(t, _CRS_WGS84_3D)
    return t
end

function topex_to_wgs84!(pipe, lon, lat, h)
    @inbounds for i in eachindex(lon, lat, h)
        loi, lai, hi = lon[i], lat[i], h[i]
        (ismissing(loi) || ismissing(lai) || ismissing(hi)) && continue
        h[i] = Proj.proj_trans(pipe, Proj.PJ_FWD, (loi, lai, hi))[3]
    end
    return h
end

topex_to_wgs84(t) = topex_to_wgs84!(_copy_columntable(t))
topex_to_wgs84(t::H5Tables.H5Table) = topex_to_wgs84!(collect(t))
topex_to_wgs84(t::H5Tables.PartitionedH5Table) = topex_to_wgs84!(collect(t))
@doc (@doc topex_to_wgs84!) topex_to_wgs84


# ─── icesat_saturation_correct ─────────────────────────────────────────────────

"""
    icesat_saturation_correct!(t)
    icesat_saturation_correct(t)

Add `:saturation_correction` to `:height`. Missing corrections (the original
ICESat fill sentinel, mapped to `missing` by `table()`) leave the height
untouched. Missing heights stay missing because `missing + x === missing`.

Only meaningful for ICESat granules (GLAH06/GLAH14). Call before
`topex_to_wgs84!`.
"""
function icesat_saturation_correct!(t)
    hasproperty(t, :saturation_correction) ||
        error("Table has no :saturation_correction column")
    icesat_saturation_correct!(
        Tables.getcolumn(t, :height),
        Tables.getcolumn(t, :saturation_correction),
    )
    return t
end

function icesat_saturation_correct!(h, sc)
    @inbounds for i in eachindex(h, sc)
        sci = sc[i]
        ismissing(sci) && continue
        h[i] = h[i] + sci
    end
    return h
end

icesat_saturation_correct(t) = icesat_saturation_correct!(_copy_columntable(t))
icesat_saturation_correct(t::H5Tables.H5Table) = icesat_saturation_correct!(collect(t))
icesat_saturation_correct(t::H5Tables.PartitionedH5Table) = icesat_saturation_correct!(collect(t))
@doc (@doc icesat_saturation_correct!) icesat_saturation_correct


# ─── icesat_quality ────────────────────────────────────────────────────────────

"""
    icesat_quality(t) -> BitVector
    icesat_quality(elev_use_flg, sigma_att_flg_or_nothing, i_numPk_or_nothing, saturation_correction_or_nothing) -> BitVector

Compute the ICESat quality mask following Smith et al. (2020)[^1]:

  - `elev_use_flg == "valid"`  (HDF5 flag value 0)
  - `sigma_att_flg == "good"`  (or `:attitude` for GLAH14)
  - `i_numPk == 1`
  - `saturation_correction < 3`

Missing values map to `false`. Returns a fresh `BitVector` suitable for
filtering (e.g. `t.height[icesat_quality(t)]`). Pass `nothing` for any
optional column to skip that predicate.

[^1]: Smith, B., et al. (2020). Pervasive ice sheet mass loss reflects competing
      ocean and atmosphere processes. Science, 368(6496), 1239-1242.
"""
function icesat_quality(t)
    hasproperty(t, :elev_use_flg) || error("Table needs :elev_use_flg column")
    elev = Tables.getcolumn(t, :elev_use_flg)
    att = hasproperty(t, :sigma_att_flg) ? Tables.getcolumn(t, :sigma_att_flg) :
          hasproperty(t, :attitude) ? Tables.getcolumn(t, :attitude) :
          nothing
    npk = hasproperty(t, :i_numPk) ? Tables.getcolumn(t, :i_numPk) : nothing
    sc = hasproperty(t, :saturation_correction) ? Tables.getcolumn(t, :saturation_correction) : nothing
    return icesat_quality(elev, att, npk, sc)
end

function icesat_quality(elev, att, npk, sc)
    n = length(elev)
    q = BitVector(undef, n)
    @inbounds for i in 1:n
        q[i] = _is_valid(elev[i]) &
               (att === nothing || _is_good(att[i])) &
               (npk === nothing || _one_peak(npk[i])) &
               (sc === nothing || _sat_ok(sc[i]))
    end
    return q
end

icesat_quality(t::H5Tables.H5Table) = icesat_quality(collect(t))
icesat_quality(t::H5Tables.PartitionedH5Table) = icesat_quality(collect(t))


# ─── ToEGM2008 operation ───────────────────────────────────────────────────────

"""
    ToEGM2008()

Transform: convert ellipsoidal `:height` to EGM2008 geoid height (using
`:longitude`, `:latitude`). Generic — applies to any granule. Equivalent to
[`to_egm2008`](@ref).
"""
struct ToEGM2008 <: Operation end
inputs(::ToEGM2008, granule) = _point_variables(granule)
outputs(::ToEGM2008) = Symbol[:height]
function _run!(::ToEGM2008, cols)
    Proj.enable_network!()
    trans = Proj.Transformation("EPSG:4979", "EPSG:3855")
    to_egm2008!(trans,
        Tables.getcolumn(cols, :latitude),
        Tables.getcolumn(cols, :longitude),
        Tables.getcolumn(cols, :height))
end
