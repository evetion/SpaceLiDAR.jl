const j2000_offset = datetime2unix(DateTime(2000, 1, 1, 12, 0, 0))
const icesat_inclination = 86.0  # actually 94, so this is 180. - 94.
const icesat_fill = 1.7976931348623157E308

"""
    ICESat_Granule{product} <: Granule

A granule of the ICESat product `product`. Normally created automatically from
either [`search`](@ref), [`granule`](@ref) or [`granules`](@ref).
"""
Base.@kwdef mutable struct ICESat_Granule{product} <: Granule
    const id::String
    url::String
    const info::NamedTuple
    const polygons::MultiPolygonType = MultiPolygonType()
end

sproduct(::ICESat_Granule{product}) where {product} = product
mission(::ICESat_Granule) = :ICESat

# ICESat has a single track, so `table`/`explore` return a plain `H5Table`
# (no partitions) and the granule itself is a Tables.jl table via `points`.
default_tracks(::ICESat_Granule) = ()

Tables.istable(::Type{<:ICESat_Granule}) = true
Tables.columnaccess(::Type{<:ICESat_Granule}) = true
Tables.columns(g::ICESat_Granule) = getfield(points(g), :table)

function table(g::ICESat_Granule; variables=default_variables(g))
    file = HDF5.h5open(g.url, "r")
    vars = [v.name => v.path for v in variables]
    transforms = Dict{Symbol,Any}(v.name => v.f for v in variables if v.f !== identity)
    attrs = Pair{Symbol,String}[]
    H5Tables.H5Table(GranuleSource(g, file); vars, attrs, transforms)
end

function explore(g::ICESat_Granule)
    file = HDF5.h5open(g.url, "r")
    selected_paths, selected_attrs = H5Tables.select(file)
    vars = [Symbol(split(p, "/")[end]) => p for p in selected_paths]
    H5Tables.H5Table(GranuleSource(g, file); vars, attrs=selected_attrs, include_dimensions=false)
end

function Base.copy(g::ICESat_Granule{product}) where {product}
    return ICESat_Granule{product}(g.id, g.url, g.info, copy(g.polygons))
end

function bounds(granule::ICESat_Granule)
    HDF5.h5open(granule.url, "r") do file
        nt = attributes(file)
        ntb = (
            min_x = parse(Float64, read(nt["geospatial_lon_min"])),
            min_y = parse(Float64, read(nt["geospatial_lat_min"])),
            max_x = parse(Float64, read(nt["geospatial_lon_max"])),
            max_y = parse(Float64, read(nt["geospatial_lat_max"])),
        )
    end
end

Base.isfile(g::ICESat_Granule) = Base.isfile(g.url)

"""
    info(g::ICESat_Granule)

Derive info based on the filename. The name is built up as follows:
`GLAH06_[release]_[orbit]_[cycle]_[track]_[segment]_[revision]_[filetype].H5`.
"""
function info(g::ICESat_Granule)
    return icesat_info(id(g))
end

function icesat_info(filename)
    id, _ = splitext(basename(filename))
    type, release, orbit, cycle, track, segment, revision, filetype =
        split(id, "_")
    return (
        type = Symbol(type),
        phase = parse(Int, orbit[1]),
        rgt = parse(Int, orbit[2]),
        instance = parse(Int, orbit[3:4]),
        cycle = parse(Int, cycle),
        track = parse(Int, track),
        segment = parse(Int, segment),
        revision = parse(Int, revision),
        calibration = parse(Int, release[1]),
        filetype = parse(Int, filetype),
        version = parse(Int, release[2:3]),
    )
end

function topex_to_wgs84_ellipsoid()
    # convert from TOPEX/POSEIDON to WGS84 ellipsoid using Proj.jl
    # This pipeline was validated against MATLAB's geodetic2ecef -> ecef2geodetic
    pipe = Proj.proj_create(
        "+proj=pipeline +step +proj=unitconvert +xy_in=deg +z_in=m +xy_out=rad +z_out=m +step +inv +proj=longlat +a=6378136.3 +rf=298.257 +e=0.08181922146 +step +proj=cart +a=6378136.3 +rf=298.257 +step +inv +proj=cart +ellps=WGS84 +step +proj=unitconvert +xy_in=rad +z_in=m +xy_out=deg +z_out=m +step +proj=axisswap +order=2,1",
    )
end

# ─── ICESat-bound operations ──────────────────────────────────────────────────
# Product-bound: `inputs` dispatches on `ICESat_Granule` (or `Nothing` for a
# sourceless ICESat-derived table). Applying these to a non-ICESat granule hits
# the default `inputs` method, which throws an applicability error. Inputs are
# declared as self-contained `Variable()` specs; GLAH06/GLAH14 share these paths
# (the per-product difference is the attitude *column name*, see
# `_attitude_variable` in GLAH06.jl/GLAH14.jl).

"""
    TopexToWGS84()

Transform: convert ICESat (GLAH06/GLAH14) TOPEX/Poseidon ellipsoid `:height`
(and `:height_reference` if present) to WGS84. Equivalent to
[`topex_to_wgs84`](@ref).
"""
struct TopexToWGS84 <: Operation end
inputs(::TopexToWGS84, ::Union{ICESat_Granule,Nothing}) = [
    Variable(:longitude, "Data_40HZ/Geolocation/d_lon", Float64),
    Variable(:latitude, "Data_40HZ/Geolocation/d_lat", Float64),
    Variable(:height, "Data_40HZ/Elevation_Surfaces/d_elev", Float64),
]
outputs(::TopexToWGS84) = Symbol[:height]
function _run!(::TopexToWGS84, cols)
    pipe = topex_to_wgs84_ellipsoid()
    lon = Tables.getcolumn(cols, :longitude)
    lat = Tables.getcolumn(cols, :latitude)
    # height_reference is transformed opportunistically when selected
    if :height_reference in _colnames(cols)
        topex_to_wgs84!(pipe, lon, lat, Tables.getcolumn(cols, :height_reference))
    end
    topex_to_wgs84!(pipe, lon, lat, Tables.getcolumn(cols, :height))
end

"""
    SaturationCorrect()

Transform: add `:saturation_correction` to `:height` (ICESat). Equivalent to
[`icesat_saturation_correct`](@ref).
"""
struct SaturationCorrect <: Operation end
inputs(::SaturationCorrect, ::Union{ICESat_Granule,Nothing}) = [
    Variable(:height, "Data_40HZ/Elevation_Surfaces/d_elev", Float64),
    Variable(:saturation_correction, "Data_40HZ/Elevation_Corrections/d_satElevCorr", Float64),
]
outputs(::SaturationCorrect) = Symbol[:height]
_run!(::SaturationCorrect, cols) = icesat_saturation_correct!(
    Tables.getcolumn(cols, :height),
    Tables.getcolumn(cols, :saturation_correction),
)

"""
    ICESatQuality()

Filter: keep only high-quality ICESat (GLAH06/GLAH14) returns following Smith
et al. (2020). The product-specific attitude column is selected by dispatch
(`:sigma_att_flg` for GLAH06, `:attitude` for GLAH14). See [`icesat_quality`](@ref).
"""
struct ICESatQuality <: Operation end
function inputs(::ICESatQuality, g::ICESat_Granule)
    [
        Variable(:elev_use_flg, "Data_40HZ/Quality/elev_use_flg", Int8),
        _attitude_variable(g),
        Variable(:i_numPk, "Data_40HZ/Waveform/i_numPk", Int32),
        Variable(:saturation_correction, "Data_40HZ/Elevation_Corrections/d_satElevCorr", Float64),
    ]
end
inputs(::ICESatQuality, ::Nothing) =
    [_namevar(:elev_use_flg), _namevar(:i_numPk), _namevar(:saturation_correction)]
function mask(::ICESatQuality, cols)
    names = _colnames(cols)
    att_col = :attitude in names ? :attitude :
              :sigma_att_flg in names ? :sigma_att_flg : nothing
    elev = Tables.getcolumn(cols, :elev_use_flg)
    att = att_col === nothing ? nothing : Tables.getcolumn(cols, att_col)
    npk = :i_numPk in names ? Tables.getcolumn(cols, :i_numPk) : nothing
    sc = :saturation_correction in names ? Tables.getcolumn(cols, :saturation_correction) : nothing
    return icesat_quality(elev, att, npk, sc)
end
