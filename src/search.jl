using HTTP
using Downloads
using Dates
using JSON3

const world = (min_x = -180.0, min_y = -90.0, max_x = 180.0, max_y = 90.0)
struct Mission{x}
end
Mission(x) = Mission{x}()

prefix(::Mission{:ICESat}) = "GLAH"
prefix(::Mission{:ICESat2}) = "ATL"
prefix(::Mission{:GEDI}) = "GEDI"
mission(::Mission{T}) where {T} = T

const url = "https://cmr.earthdata.nasa.gov/search/granules.umm_json_v1_6_4"

"""
    search(mission::Mission, bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}})
    search(:GEDI02_A, "002")  # searches *all* GEDI v2 granules

Search granules for a given mission and bounding box.
"""
function search(
    m::Mission{:GEDI},
    product::Symbol = :GEDI02_A;
    bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}} = world,
    version::Int = 2,
    provider::String = "LPDAAC_ECS",
)::Vector{GEDI_Granule}
    startswith(string(product), prefix(m)) || throw(ArgumentError("Wrong product $product for $(mission(m)) mission."))
    granules =
        earthdata_search(short_name = string(product), bounding_box = bbox, version = version, provider = provider)
    length(granules) == 0 && @warn "No granules found, did you specify the correct parameters, such as version?"
    filter!(g -> !isnothing(g.https_url), granules)
    map(
        x -> GEDI_Granule{product}(
            x.filename,
            x.https_url,
            gedi_info(x.filename),
            x.polygons),
        granules,
    )
end

function search(
    m::Mission{:ICESat2},
    product::Symbol = :ATL03;
    bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}} = world,
    version::Int = 5,
    s3::Bool = false,
    provider::String = s3 ? "NSIDC_CPRD" : "NSIDC_ECS",
)::Vector{ICESat2_Granule}
    startswith(string(product), prefix(m)) || throw(ArgumentError("Wrong product $product for $(mission(m)) mission."))
    granules =
        earthdata_search(short_name = string(product), bounding_box = bbox, version = version, provider = provider)
    length(granules) == 0 && @warn "No granules found, did you specify the correct parameters, such as version?"
    s3 ? filter!(g -> !isnothing(g.s3_url), granules) : filter!(g -> !isnothing(g.https_url), granules)
    map(
        x -> ICESat2_Granule{product}(
            x.filename,
            s3 ? x.s3_url : x.https_url,
            icesat2_info(x.filename),
            x.polygons),
        granules,
    )
end

function search(
    m::Mission{:ICESat},
    product::Symbol = :GLAH14;
    bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}} = world,
    version::Int = 34,
    s3::Bool = false,
    provider::String = s3 ? "NSIDC_CPRD" : "NSIDC_ECS",
)::Vector{ICESat_Granule}
    startswith(string(product), prefix(m)) || throw(ArgumentError("Wrong product $product for $(mission(m)) mission."))
    granules =
        earthdata_search(short_name = string(product), bounding_box = bbox, version = version, provider = provider)
    length(granules) == 0 && @warn "No granules found, did you specify the correct parameters, such as version?"
    s3 ? filter!(g -> !isnothing(g.s3_url), granules) : filter!(g -> !isnothing(g.https_url), granules)
    map(
        x -> ICESat_Granule{product}(
            x.filename,
            s3 ? x.s3_url : x.https_url,
            icesat_info(x.filename),
            x.polygons,
        ),
        granules)
end

search(::Mission{X}, product, args...; kwargs...) where {X} =
    throw(ArgumentError("Mission $X not supported. Currently supported are :ICESat, :ICESat2, and :GEDI."))

# search(mission::Symbol, product::AbstractString, bbox::NamedTuple, version::String) =
# search(Mission(mission), Symbol(product); bbox = bbox, version = parse(Int, version))
# search(mission::Symbol, product::AbstractString, bbox::NamedTuple) =
# search(Mission(mission), Symbol(product); bbox = bbox)

@deprecate find(mission::Symbol, product::AbstractString, bbox, version) search(
    mission,
    Symbol(product);
    bbox = bbox,
    version = parse(Int, version),
)
@deprecate find(mission::Symbol, product::AbstractString, bbox) search(
    mission,
    Symbol(product);
    bbox = bbox,
)
@deprecate find(mission::Symbol, product::AbstractString) search(
    mission,
    Symbol(product),
)
function search(mission::Symbol, product::Symbol, args...; kwargs...)
    search(Mission(mission), product, args...; kwargs...)
end

function parse_polygon(polygons, T = Float64)
    o = Vector{Vector{Vector{Vector{T}}}}()
    for polygon in polygons
        po = Vector{Vector{Vector{T}}}()
        for ring in polygon
            ro = Vector{Vector{T}}()
            c = map(Base.Fix1(parse, T), split(ring, " "))
            for i = 1:2:length(c)
                push!(ro, [c[i], c[i+1]])
            end
            push!(po, ro)
        end
        push!(o, po)
    end
    return o
end

function parse_cmr_json(r)
    data = JSON3.read(r.body)
    map(granule_info, get(get(data, "feed", Dict()), "entry", []))
end

function granule_info(item)::NamedTuple
    filename = item.producer_granule_id
    urls = filter(x -> get(x, "type", "") in ("application/x-hdf5", "application/x-hdfeos"), item.links)

    https = filter(u -> startswith(u.href, "http"), urls)
    https_url = length(https) > 0 ? https[1].href : nothing
    s3 = filter(u -> startswith(u.href, "s3:"), urls)
    s3_url = length(s3) > 0 ? s3[1].href : nothing

    mp = get(item, "polygons", [])
    polygons = parse_polygon(mp)

    (; filename, https_url, s3_url, polygons)
end

function parse_cmr_ummjson(r)
    data = JSON3.read(r.body)
    map(granule_info_umm, data.items)
end

function granule_info_umm(item)::NamedTuple
    # Schema is here: https://git.earthdata.nasa.gov/projects/EMFD/repos/unified-metadata-model/browse/granule/v1.6.4/umm-g-json-schema.json
    rurls = item.umm.RelatedUrls
    urls = filter(x -> get(x, "MimeType", "") in ("application/x-hdf5", "application/x-hdfeos"), rurls)

    https = filter(u -> startswith(u.URL, "http"), urls)
    https_url = length(https) > 0 ? https[1].URL : nothing
    s3 = filter(u -> startswith(u.URL, "s3:"), urls)
    s3_url = length(s3) > 0 ? s3[1].URL : nothing

    filename = item.meta["native-id"]

    (; filename, https_url = https_url, s3_url = s3_url)
end

function earthdata_search(;
    short_name::String,
    bounding_box::Union{Nothing,NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}}} = nothing,
    version::Union{Nothing,Int} = nothing,
    provider::Union{Nothing,String} = "NSIDC_CPRD",
    all_pages::Bool = true,
    page_size = 2000,
    page_num = 1,
    umm = false,
    verbose = 0,
)
    q = Dict(
        "page_num" => page_num,
        "page_size" => page_size,
        "short_name" => short_name,
    )
    !isnothing(bounding_box) ?
    q["bounding_box"] = "$(bounding_box.min_x),$(bounding_box.min_y),$(bounding_box.max_x),$(bounding_box.max_y)" :
    nothing
    !isnothing(version) ? q["version"] = lpad(version, 3, "0") : nothing
    !isnothing(provider) ? q["provider"] = provider : nothing

    qurl = umm ? url : replace(url, "umm_json_v1_6_4" => "json")
    r = HTTP.get(qurl, query = q, verbose = verbose)
    parsef = umm ? parse_cmr_ummjson : parse_cmr_json
    cgranules = parsef(r)
    granules = Vector{NamedTuple}()
    append!(granules, cgranules)
    while (length(cgranules) == page_size) && all_pages
        @warn "Found more than $page_size granules, requesting another $page_size..."
        q["page_num"] += 1
        r = HTTP.get(qurl, query = q, verbose = verbose)
        cgranules = parsef(r)
        append!(granules, cgranules)
    end
    granules
end

function get_s3_credentials(daac = "nsidc")
    body = sprint() do output
        return Downloads.request(
            "https://data.$daac.earthdatacloud.nasa.gov/s3credentials";
            output = output,
        )
    end
    body = JSON3.read(body)
    AWSS3.AWSCredentials(
        body.accessKeyId,
        body.secretAccessKey,
        body.sessionToken,
        expiry = DateTime(body.expiration, dateformat"y-m-d H:M:S+z"),
    )
end

function set_env!(creds::AWSS3.AWSCredentials, env = ENV)
    env["AWS_ACCESS_KEY_ID"] = creds.access_key_id
    env["AWS_SECRET_ACCESS_KEY"] = creds.secret_key
    env["AWS_SESSION_TOKEN"] = creds.token
    env["AWS_SESSION_EXPIRES"] = creds.expiry
end
