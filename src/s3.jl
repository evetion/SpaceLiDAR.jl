using AWSCore
using AWSS3

const aws = AWSCore.aws_config(profile="delft3dgt")

"""Change default download location to a S3 bucket."""
function s3!(granule::Granule, bucket::String="so-icesat2", verify=false)
    fn = granule.id
    if verify && ~in(bucket, fn)
        return granule
    else
        granule.url = joinpath(bucket, fn)
        return granule
    end
end
s3!(granules::Vector{<:Granule}, args...) = map!(x -> s3!(x, args...), granules)

function Base.in(granule::Granule, bucket="so-icesat2")
    AWSS3.s3_exists(aws, bucket, granule.id)
end

function sync!(granules::Vector{<:Granule}, bucket="so-icesat2")
    mask = trues(length(granules))
    while sum(mask) > 0
        in_bucket = map(x -> x["Key"], s3_list_objects(aws, bucket))
        mask = map(g -> ~(g.id in in_bucket), granules)
        @info "Still checking $(sum(mask)) to sync granules..."
        for granule in granules[.~mask]
            granule.url = joinpath(bucket, granule.id)
        end
        download_to_s3(granules[mask], bucket)
    end
    granules
end

function download_to_s3(granules::Vector{<:Granule}, bucket="so-icesat2")
    fn_hook = write_upload_hook!("s3_upload_hook.sh", bucket)
    fn_urls = write_granule_urls!("to_download.txt", granules)
    print(read(`aria2c --on-download-complete $fn_hook --file-allocation=none --continue=true --auto-file-renaming=false -j3 -x1 -i $fn_urls`))
end


function write_upload_hook!(fn::String, bucket="so-icesat2", rm=true)
    open(fn, "w") do f
        println(f, "#bin/sh")
        if rm
            println(f, "aws s3 cp \$3 s3://$bucket/ && rm \$3")
        else
            println(f, "aws s3 cp \$3 s3://$bucket/")
        end
    end
    chmod(fn, 0o775)
    abspath(fn)
end
