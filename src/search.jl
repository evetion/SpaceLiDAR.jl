using HTTP
using JSON

const world = (min_x = -180.0, min_y = -90.0, max_x = 180.0, max_y = 90.0)

struct Mission{x}
end
Mission(x) = Mission{x}()

#const url = "https://cmr.earthdata.nasa.gov/search/granules.json"
const url = "https://cmr.earthdata.nasa.gov/search/granules.umm_json"

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
    granules = earthdata_search(product, bbox, version, provider = "LPDAAC_ECS")
    map(
        x -> GEDI_Granule(
            Symbol(product),
            x["filename"],
            x["https"],
            x["s3"],
            gedi_info(x["filename"]),
        ),
        granules)
end

function find(
    ::Mission{:ICESat2},
    product::String = "ATL03",
    bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}} = world,
    version::String = "005",
)
    granules = earthdata_search(product, bbox, version)
    map(
        x -> ICESat2_Granule(
            Symbol(product),
            x["filename"],
            x["https"],
            x["s3"],
            icesat2_info(x["filename"]),
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
            x["filename"],
            x["https"],
            x["s3"],
            icesat_info(x["filename"]),
        ),
        granules)
end

function parse_cmr_json(r)
    data = JSON.parse(String(r.body))

    # each granule is a column in the vector
    f = [granule_info(row[1]) for row in eachrow(get(data, "items", Dict()))]
end

function granule_info(item::Dict{String, Any})
    https = ""
    s3 = ""
    filename = ""
    for row in eachrow(get(get(item,"umm",Dict()),"RelatedUrls",Dict()))
        if get(row[1],"Type",nothing) == "GET DATA" 
            https = get(row[1],"URL","")
        elseif get(row[1],"Type",nothing) == "GET DATA VIA DIRECT ACCESS"
            s3 = get(row[1],"URL","")
        end
    end

    # this is necessary to provide a filename as the url does not always exist
    for row in eachrow(get(get(get(item,"umm",Dict()),"DataGranule",nothing),  "Identifiers", nothing))
        if get(row[1],"IdentifierType",nothing) ==  "ProducerGranuleId"
            filename = get(row[1],"Identifier","")
        end
    end

    Dict("https" => https, "s3" => s3, "filename" => filename)
end

function find(mission::Symbol, args...)
    find(Mission(mission), args...)
end


function earthdata_search(
    product::String,
    bbox::NamedTuple{(:min_x, :min_y, :max_x, :max_y),NTuple{4,Float64}},
    version::String;
    provider = "NSIDC_CPRD",
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