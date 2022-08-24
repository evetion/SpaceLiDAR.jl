using Proj4
using Downloads

function to_egm2008!(table)
    egm08 = "./egm08_25.gtx"
    egm08 =
        isfile(egm08) ? abspath(egm08) :
        Downloads.download(
            "https://github.com/OSGeo/proj-datumgrid/raw/master/world/egm08_25.gtx",
            egm08,
        )
    wgs84 = Projection("+proj=longlat +datum=WGS84 +no_defs")
    egm2008 = Projection("+proj=vgridshift +grids=$egm08")
    data = hcat(Float64.(table.x), Float64.(table.y), Float64.(table.z))
    Proj4.transform!(wgs84, egm2008, data)
    return table[:, :z] .= data[:, 3]
end
