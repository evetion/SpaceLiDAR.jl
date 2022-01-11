using HTTP
using JSON

const world = (min_x = -180., min_y = -90., max_x = 180., max_y = 90.)

struct Mission{x}
end
Mission(x) = Mission{x}()

const url = "https://cmr.earthdata.nasa.gov/search/granules.json"

# GEDIFinder has not been updated to v2
# function find(::Mission{:GEDI}, product::String="GEDI02_A", bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}}=world, version::String="001")
#     # https://lpdaacsvc.cr.usgs.gov/services/gedifinder?product=GEDI02_A&version=001&bbox=[28.0,-83,24.0,-79]
#     url = "https://lpdaacsvc.cr.usgs.gov/services/gedifinder?"
#     q = Dict(
#         "bbox" => "[$(bbox.max_y),$(bbox.min_x),$(bbox.min_y),$(bbox.max_x)]",
#         "version" => version,
#         "product" => product
#         )
#     # uri = HTTP.URI(;scheme="https", host="lpdaacsvc.cr.usgs.gov", path="/services/gedifinder", query=q)
#     r = HTTP.get(url, query=q, verbose=0)
#     data = JSON.parse(String(r.body))

#     map(x -> GEDI_Granule(
#         Symbol(product),
#         basename(x),
#         x,
#         gedi_info(basename(x))
#     ),
#     data["data"])
# end

function find(::Mission{:GEDI}, product::String="GEDI02_A", bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}}=world, version::String="002")
    granules = earthdata_search(product, bbox, version; provider="LPDAAC_ECS")
    map(x -> GEDI_Granule(
        Symbol(product),
        x["producer_granule_id"],
        get(get(x, "links", [Dict()])[1], "href", ""),
        gedi_info(x["producer_granule_id"])
    ),
    granules)
end

function find(::Mission{:ICESat2}, product::String="ATL03", bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}}=world, version::String="005")
    # https://cmr.earthdata.nasa.gov/search/granules.json?provider=NSIDC_ECS&page_size=2000&sort_key[]=-start_date&sort_key[]=producer_granule_id&short_name=ATL03&version=2&version=02&version=002&temporal[]=2018-10-13T00:00:00Z,2020-01-13T08:13:50Z&bounding_box=-180,-90,180,90
    granules = earthdata_search(product, bbox, version)
    map(x -> ICESat2_Granule(
            Symbol(product),
            x["producer_granule_id"],
            get(get(x, "links", [Dict()])[1], "href", ""),
            NamedTuple(),
            icesat2_info(x["producer_granule_id"])
        ),
        granules)
end

function find(::Mission{:ICESat}, product::String="GLAH14", bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}}=world, version::String="034")
    # https://cmr.earthdata.nasa.gov/search/granules.json?provider=NSIDC_ECS&page_size=2000&sort_key[]=-start_date&sort_key[]=producer_granule_id&short_name=ATL03&version=2&version=02&version=002&temporal[]=2018-10-13T00:00:00Z,2020-01-13T08:13:50Z&bounding_box=-180,-90,180,90
    granules = earthdata_search(product, bbox, version)
    map(x -> ICESat_Granule(
            Symbol(product),
            x["producer_granule_id"],
            get(get(x, "links", [Dict()])[1], "href", ""),
            icesat_info(x["producer_granule_id"])
        ),
        granules)
end

function parse_cmr_json(r)
    data = JSON.parse(String(r.body))
    get(get(data, "feed", Dict()), "entry", [])
end

function find(mission::Symbol, args...)
    find(Mission(mission), args...)
end

function earthdata_search(product::String, bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}}, version::String; provider="NSIDC_ECS")
    page_size = 2000
    page_num = 1
    q = Dict(
        "provider" => provider,
        "page_num" => page_num,
        "page_size" => page_size,
        "short_name" => product,
        "version" => version,
        "bounding_box" => "$(bbox.min_x),$(bbox.min_y),$(bbox.max_x),$(bbox.max_y)"
        )
    r = HTTP.get(url, query=q)
    cgranules = parse_cmr_json(r)
    granules = copy(cgranules)
    while length(cgranules) == page_size
        @warn "Found more than $page_size granules, requesting another $page_size..."
        q["page_num"] += 1
        r = HTTP.get(url, query=q)
        cgranules = parse_cmr_json(r)
        append!(granules, cgranules)
    end
    granules
end
