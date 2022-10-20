using HTTP
using JSON

const world = (min_x = -180.0, min_y = -90.0, max_x = 180.0, max_y = 90.0)

struct Mission{x}
end
Mission(x) = Mission{x}()

const url = "https://cmr.earthdata.nasa.gov/search/granules.json"

"""
    find(mission::Mission, bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}})
    find(:GEDI02_A, "002")  # searches *all* GEDI v2 granules

Find granules for a given mission and bounding box.
"""
function find(
    ::Mission{:GEDI},
    product::String = "GEDI02_A",
    bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}} = world,
    version::String = "002",
)
    granules = earthdata_search(product, bbox, version; provider = "LPDAAC_ECS")
    map(
        x -> GEDI_Granule(
            Symbol(product),
            x["producer_granule_id"],
            get(get(x, "links", [Dict()])[1], "href", ""),
            gedi_info(x["producer_granule_id"]),
        ),
        granules)
end

function find(
    ::Mission{:ICESat2},
    product::String = "ATL03",
    bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}} = world,
    version::String = "005",
)
    # https://cmr.earthdata.nasa.gov/search/granules.json?provider=NSIDC_ECS&page_size=2000&sort_key[]=-start_date&sort_key[]=producer_granule_id&short_name=ATL03&version=2&version=02&version=002&temporal[]=2018-10-13T00:00:00Z,2020-01-13T08:13:50Z&bounding_box=-180,-90,180,90
    if product == "ATL06"
        # is seems that only ATL06 is currently hosted on earthdatacloud
        granules = earthdata_search(Mission(:ICESat2), product, bbox, version)
    else
        granules = earthdata_search(product, bbox, version)
    end

    map(
        x -> ICESat2_Granule(
            Symbol(product),
            x["producer_granule_id"],
            get(get(x, "links", [Dict()])[1], "href", ""),
            NamedTuple(),
            icesat2_info(x["producer_granule_id"]),
        ),
        granules)
end

function find(
    ::Mission{:ICESat},
    product::String = "GLAH14",
    bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}} = world,
    version::String = "034",
)
    # https://cmr.earthdata.nasa.gov/search/granules.json?provider=NSIDC_ECS&page_size=2000&sort_key[]=-start_date&sort_key[]=producer_granule_id&short_name=ATL03&version=2&version=02&version=002&temporal[]=2018-10-13T00:00:00Z,2020-01-13T08:13:50Z&bounding_box=-180,-90,180,90
    granules = earthdata_search(product, bbox, version)
    map(
        x -> ICESat_Granule(
            Symbol(product),
            x["producer_granule_id"],
            get(get(x, "links", [Dict()])[1], "href", ""),
            icesat_info(x["producer_granule_id"]),
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

function earthdata_search(
    product::String,
    bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}},
    version::String;
    provider = "NSIDC_ECS",
)
    page_size = 2000
    page_num = 1
    
    q = Dict(
        "provider" => provider,
        "page_num" => page_num,
        "page_size" => page_size,
        "short_name" => product,
        "version" => version,
        "bounding_box" => "$(bbox.min_x),$(bbox.min_y),$(bbox.max_x),$(bbox.max_y)",
    )
    
    r = HTTP.get(url, query = q)
    cgranules = parse_cmr_json(r)
    granules = copy(cgranules)
    while length(cgranules) == page_size
        @warn "Found more than $page_size granules, requesting another $page_size..."
        q["page_num"] += 1
        r = HTTP.get(url, query = q)
        cgranules = parse_cmr_json(r)
        append!(granules, cgranules)
    end
    granules
end

# this provides interm access to ICESat2 data hosted on earthdatacloud
function earthdata_search(
    ::Mission{:ICESat2},
    product::String,
    bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}},
    version::String;
    #provider = "NSIDC_ECS",
    concept_id = "C2153572614-NSIDC_CPRD",
)
    page_size = 2000
    page_num = 1
    
    q = Dict(
        "concept_id" => concept_id,
       # "provider" => provider,
        "page_num" => page_num,
        "page_size" => page_size,
        "short_name" => product,
        "version" => version,
        "bounding_box" => "$(bbox.min_x),$(bbox.min_y),$(bbox.max_x),$(bbox.max_y)",
    )
    
    r = HTTP.get(url, query = q)
    cgranules = parse_cmr_json(r)
    granules = copy(cgranules)
    while length(cgranules) == page_size
        @warn "Found more than $page_size granules, requesting another $page_size..."
        q["page_num"] += 1
        r = HTTP.get(url, query = q)
        cgranules = parse_cmr_json(r)
        append!(granules, cgranules)
    end
    granules
end