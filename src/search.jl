using HTTP
using Downloads
using TimeZones
using Dates
using JSON3

const world = (min_x = -180.0, min_y = -90.0, max_x = 180.0, max_y = 90.0)
struct Mission{x}
end
Mission(x) = Mission{x}()

const url = "https://cmr.earthdata.nasa.gov/search/granules.umm_json_v1_6_4"

"""
    search(mission::Mission, bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}})
    search(:GEDI02_A, "002")  # searches *all* GEDI v2 granules

Search granules for a given mission and bounding box.
"""
function search(
    ::Mission{:GEDI},
    product::String = "GEDI02_A";
    bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}} = world,
    version::Int = 2,
    provider::String = "LPDAAC_ECS",
)
    granules = earthdata_search(short_name = product, bounding_box = bbox, version = version, provider = provider)
    map(
        x -> GEDI_Granule(
            Symbol(product),
            x.filename,
            x.https_url,
            x.info,
            gedi_info(x.filename),
        ),
        granules)::Vector{GEDI_Granule{Symbol(product)}}
end

function search(
    ::Mission{:ICESat2},
    product::String = "ATL03";
    bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}} = world,
    version::Int = 5,
    s3::Bool = false,
    provider::String = s3 ? "NSIDC_CPRD" : "NSIDC_ECS",
)
    granules = earthdata_search(short_name = product, bounding_box = bbox, version = version, provider = provider)
    map(
        x -> ICESat2_Granule(
            Symbol(product),
            x.filename,
            s3 ? x.s3_url : x.https_url,
            x.info,
            icesat2_info(x.filename),
        ),
        granules)::Vector{ICESat2_Granule{Symbol(product)}}
end

function search(
    ::Mission{:ICESat},
    product::String = "GLAH14";
    bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}} = world,
    version::Int = 34,
    s3::Bool = false,
    provider::String = s3 ? "NSIDC_CPRD" : "NSIDC_ECS",
)
    # https://cmr.earthdata.nasa.gov/search/granules.json?provider=NSIDC_ECS&page_size=2000&sort_key[]=-start_date&sort_key[]=producer_granule_id&short_name=ATL03&version=2&version=02&version=002&temporal[]=2018-10-13T00:00:00Z,2020-01-13T08:13:50Z&bounding_box=-180,-90,180,90
    granules = earthdata_search(short_name = product, bounding_box = bbox, version = version, provider = provider)
    map(
        x -> ICESat_Granule(
            Symbol(product),
            x.filename,
            s3 ? x.s3_url : x.https_url,
            (;),
            icesat_info(x.filename),
        ),
        granules)::Vector{ICESat_Granule{Symbol(product)}}
end

search(mission::Mission, product::AbstractString, bbox::NamedTuple, version::String) =
    search(mission, product; bbox = bbox, version = parse(Int, version))
search(mission::Mission, product::AbstractString, bbox::NamedTuple) =
    search(mission, product; bbox = bbox)

@deprecate find(mission::Symbol, args...) search(mission, args...)
function search(mission::Symbol, args...; kwargs...)
    search(Mission(mission), args...; kwargs...)
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

    (; filename, https_url, s3_url, info = (;))
end

function parse_cmr_ummjson(r)
    data = JSON3.read(r.body)
    map(granule_info_umm, data.items)
end

function granule_info_umm(item)::NamedTuple
    # Schema is here: https://git.earthdata.nasa.gov/projects/EMFD/repos/unified-metadata-model/browse/granule/v1.6.4/umm-g-json-schema.json
    rurls = item.umm.RelatedUrls
    urls = filter(x -> get(x, "MimeType", "") in ("application/x-hdf5", "application/x-hdfeos"), rurls)

    @info urls
    https = filter(u -> startswith(u.URL, "http"), urls)
    https_url = length(https) > 0 ? https[1].URL : nothing
    s3 = filter(u -> startswith(u.URL, "s3:"), urls)
    s3_url = length(s3) > 0 ? s3[1].URL : nothing

    filename = item.meta["native-id"]

    (; filename, https_url, s3_url, info = (;))
end

function earthdata_search(;
    short_name::String,
    bounding_box::Union{Nothing,NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}}} = nothing,
    version::Union{Nothing,Int} = nothing,
    provider::Union{Nothing,String} = "NSIDC_CPRD",  # NSIDC_ECS
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
    granules = copy(cgranules)
    while length(cgranules) == page_size && all_pages
        @warn "Found more than $page_size granules, requesting another $page_size..."
        q["page_num"] += 1
        r = HTTP.get(url, query = q)
        cgranules = parsef(r)
        append!(granules, cgranules)
    end
    granules
end


function earthdata_cloud_s3(daac = "nsidc")
    body = sprint() do output
        return Downloads.request(
            "https://data.$daac.earthdatacloud.nasa.gov/s3credentials";
            output = output,
        )
    end
    return JSON3.read(body)
end

function earthdata_s3_env!(env = ENV)
    dict = earthdata_cloud_s3()
    time =
        ZonedDateTime(dict.expiration, dateformat"y-m-d H:M:S+z") -
        now(TimeZone("UTC"))
    @warn "AWS tokens expire in $(floor(time, Dates.Minute)) from now."
    env["AWS_ACCESS_KEY_ID"] = dict.accessKeyId
    env["AWS_SECRET_ACCESS_KEY"] = dict.secretAccessKey
    env["AWS_SESSION_TOKEN"] = dict.sessionToken
    env["AWS_SESSION_EXPIRES"] = dict.expiration
    env["AWS_DEFAULT_REGION"] = "us-west-2"
    return env
end
