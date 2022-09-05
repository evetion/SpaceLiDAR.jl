using Proj
using Downloads

function to_egm2008!(table)
    Proj.enable_network!()
    trans = Proj.Transformation("EPSG:4979", "EPSG:3855")
    data = Proj.Coord.(table.y, table.x, table.z)
    return table[:, :z] .= getindex.(trans.(data), 3)
end
