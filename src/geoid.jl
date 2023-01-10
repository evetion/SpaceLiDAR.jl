using Proj

"""
    to_egm2008!(table)

Converts ellipsoid heights to geoid heights using the EGM2008 geoid model.
Assumes a table as generated from [`points`](@ref) with columns `:latitude`, `:longitude`, and `:height`.
Will overwrite the `:height` column with the geoid height.
"""
function to_egm2008!(table)
    Proj.enable_network!()
    trans = Proj.Transformation("EPSG:4979", "EPSG:3855")
    data = Proj.Coord.(table.latitude, table.longitude, table.height)
    return table[:, :height] .= getindex.(trans.(data), 3)
end
