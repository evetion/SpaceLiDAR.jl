using HTTP
using JSON

const world = (min_x = -180., min_y = -90., max_x = 180., max_y = 90.)

struct Mission{x}
end
Mission(x) = Mission{x}()


function find(::Mission{:GEDI}, product::String="GEDI02_A", bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}}=world, version::String="001")
    # https://lpdaacsvc.cr.usgs.gov/services/gedifinder?product=GEDI02_A&version=001&bbox=[28.0,-83,24.0,-79]
    url = "https://lpdaacsvc.cr.usgs.gov/services/gedifinder"
    q = Dict(
        "bbox" => "[$(bbox.max_y), $(bbox.min_x), $(bbox.min_y), $(bbox.max_x)]",
        "version" => version,
        "product" => product
        )
    # uri = HTTP.URI(;scheme="https", host="lpdaacsvc.cr.usgs.gov", path="/services/gedifinder", query=q)
    r = HTTP.get(url, query=q)
    data = JSON.parse(String(r.body))
    @info data["data"]

    map(x -> GEDI_Granule(
        Symbol(product),
        replace(basename(x), ".h5" => ""),
        x,
    ),
    data["data"])
end


function find(::Mission{:ICESat2}, product::String="ATL03", bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}}=world, version::String="003")
    # https://cmr.earthdata.nasa.gov/search/granules.json?provider=NSIDC_ECS&page_size=2000&sort_key[]=-start_date&sort_key[]=producer_granule_id&short_name=ATL03&version=2&version=02&version=002&temporal[]=2018-10-13T00:00:00Z,2020-01-13T08:13:50Z&bounding_box=-180,-90,180,90
    url = "https://cmr.earthdata.nasa.gov/search/granules.json"
    page_size = 2000
    page_num = 1
    q = Dict(
        "provider" => "NSIDC_ECS",
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
    @info granules[1]
    @info granules[end]
    # TODO get more pages
    map(x -> ICESat2_Granule(
            Symbol(product),
            x["producer_granule_id"],
            get(get(x, "links", [Dict()])[1], "href", ""),
            NamedTuple(),
            x
        ),
        granules)
end

function parse_cmr_json(r)
    data = JSON.parse(String(r.body))
    granules = get(get(data, "feed", Dict()), "entry", [])
end

function find(mission::Symbol, args...)
    find(Mission(mission), args...)
end
