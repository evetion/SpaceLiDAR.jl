const world = convert(
    Extent,
    (min_x = -180.0, min_y = -90.0, max_x = 180.0, max_y = 90.0),
)
struct Mission{x}
end
Mission(x) = Mission{x}()

prefix(::Mission{:ICESat}) = "GLAH"
prefix(::Mission{:ICESat2}) = "ATL"
prefix(::Mission{:GEDI}) = "GEDI"
mission(::Mission{T}) where {T} = T

_fix_gedi_id(id::Nothing) = nothing
_fix_gedi_id(id::String) = first(splitext(id))
_fix_gedi_id(id::Vector{String}) = _fix_gedi_id.(id)

_cmr_version(version::Int) = lpad(string(version), 3, '0')

function _cmr_bounding_box(extent::Extent)
    x, y = extent.X, extent.Y
    return join((x[1], y[1], x[2], y[2]), ",")
end

function _cmr_temporal(after, before)
    isnothing(after) && isnothing(before) && return nothing
    return (after, before)
end

function _earthdata_search(;
    short_name::String,
    extent::Extent,
    version::Int,
    provider::String,
    before,
    after,
    id,
)
    return EarthData.granules(
        ;
        short_name,
        bounding_box = _cmr_bounding_box(extent),
        version = _cmr_version(version),
        provider,
        temporal = _cmr_temporal(after, before),
        granule_ur = id,
        page_size = 2000,
        all = true,
    )
end

function _earthdata_filename(granule)
    filename = String(granule.GranuleUR)
    h5 = match(r"(?i)^.*?\.h5", filename)
    return isnothing(h5) ? filename * ".h5" : h5.match
end

function _earthdata_url(granule, s3::Bool)
    type = s3 ? "GET DATA VIA DIRECT ACCESS" : "GET DATA"
    scheme = s3 ? :s3 : :https
    return EarthData.download_url(granule; scheme, type)
end

function _earthdata_ring(boundary)
    return [
        [Float64(point.Longitude), Float64(point.Latitude)] for
        point in boundary.Points
    ]
end

function _earthdata_polygon(polygon)
    rings = [_earthdata_ring(polygon.Boundary)]
    if !isnothing(polygon.ExclusiveZone)
        append!(rings, _earthdata_ring.(polygon.ExclusiveZone.Boundaries))
    end
    return rings
end

function _earthdata_polygons(granule)
    spatial = granule.SpatialExtent
    isnothing(spatial) && return MultiPolygonType()
    horizontal = spatial.HorizontalSpatialDomain
    isnothing(horizontal) && return MultiPolygonType()
    geometry = horizontal.Geometry
    isnothing(geometry) && return MultiPolygonType()
    polygons = geometry.GPolygons
    isnothing(polygons) && return MultiPolygonType()
    return _earthdata_polygon.(polygons)
end

"""
    search(mission::Mission, extent::Extent)
    search(:GEDI02_A, "002")  # searches *all* GEDI v2 granules

Search granules for a given mission and bounding box.
"""
function search(
    m::Mission{:GEDI},
    product::Symbol = :GEDI02_A;
    extent::Extent = world,
    version::Int = 2,
    before::Union{Nothing,DateTime} = nothing,
    after::Union{Nothing,DateTime} = nothing,
    id::Union{Nothing,String,Vector{String}} = nothing,
    provider::String = "LPCLOUD",
)::Vector{GEDI_Granule}
    startswith(string(product), prefix(m)) ||
        throw(ArgumentError("Wrong product $product for $(mission(m)) mission."))

    records = _earthdata_search(
        ;
        short_name = string(product),
        extent,
        version,
        provider,
        before,
        after,
        id = _fix_gedi_id(id),
    )
    isempty(records) &&
        @warn "No granules found, did you specify the correct parameters, such as version?"

    results = GEDI_Granule{product}[]
    for record in records
        url = _earthdata_url(record, false)
        isnothing(url) && continue
        filename = _earthdata_filename(record)
        push!(
            results,
            GEDI_Granule{product}(
                filename,
                url,
                gedi_info(filename),
                _earthdata_polygons(record),
            ),
        )
    end
    return results
end

function search(
    m::Mission{:ICESat2},
    product::Symbol = :ATL03;
    extent::Extent = world,
    version::Int = 7,
    before::Union{Nothing,DateTime} = nothing,
    after::Union{Nothing,DateTime} = nothing,
    id::Union{Nothing,String,Vector{String}} = nothing,
    s3::Bool = false,
    provider::String = "NSIDC_CPRD",
)::Vector{ICESat2_Granule}
    startswith(string(product), prefix(m)) ||
        throw(ArgumentError("Wrong product $product for $(mission(m)) mission."))

    records = _earthdata_search(
        ;
        short_name = string(product),
        extent,
        version,
        provider,
        before,
        after,
        id,
    )
    isempty(records) &&
        @warn "No granules found, did you specify the correct parameters, such as version?"

    results = ICESat2_Granule{product}[]
    for record in records
        url = _earthdata_url(record, s3)
        isnothing(url) && continue
        filename = _earthdata_filename(record)
        push!(
            results,
            ICESat2_Granule{product}(
                filename,
                url,
                icesat2_info(filename),
                _earthdata_polygons(record),
            ),
        )
    end
    return results
end

function search(
    m::Mission{:ICESat},
    product::Symbol = :GLAH14;
    extent::Extent = world,
    version::Int = 34,
    before::Union{Nothing,DateTime} = nothing,
    after::Union{Nothing,DateTime} = nothing,
    id::Union{Nothing,String,Vector{String}} = nothing,
    s3::Bool = false,
    provider::String = "NSIDC_CPRD",
)::Vector{ICESat_Granule}
    startswith(string(product), prefix(m)) ||
        throw(ArgumentError("Wrong product $product for $(mission(m)) mission."))

    records = _earthdata_search(
        ;
        short_name = string(product),
        extent,
        version,
        provider,
        before,
        after,
        id,
    )
    isempty(records) &&
        @warn "No granules found, did you specify the correct parameters, such as version?"

    results = ICESat_Granule{product}[]
    for record in records
        url = _earthdata_url(record, s3)
        isnothing(url) && continue
        filename = _earthdata_filename(record)
        push!(
            results,
            ICESat_Granule{product}(
                filename,
                url,
                icesat_info(filename),
                _earthdata_polygons(record),
            ),
        )
    end
    return results
end

search(::Mission{X}, product, args...; kwargs...) where {X} =
    throw(ArgumentError("Search doesn't support arguments $args. Did you mean to use keywords?"))

search(::Mission{X}, product; kwargs...) where {X} =
    throw(ArgumentError("Combination of Mission $X and Product $product not supported. Please make an issue."))

function search(mission::Symbol, product::Symbol, args...; kwargs...)
    search(Mission(mission), product, args...; kwargs...)
end

function search(g::Granule; kwargs...)
    initial = (; version = info(g).version, id = id(g))
    only(search(mission(g), sproduct(g); merge(initial, kwargs)...))
end

function search(gg::Vector{<:Granule}; kwargs...)
    g = first(gg)
    initial = (; version = info(g).version, id = map(x -> id(x), gg))
    search(mission(g), sproduct(g); merge(initial, kwargs)...)
end

function search(g::Granule, product::Symbol; kwargs...)
    g = convert(product, g)
    search(g, kwargs...)
end

function search(gg::Vector{<:Granule}, product::Symbol; kwargs...)
    gg = convert.(product, gg)
    search(gg, kwargs...)
end
