function makeline(x, y, z)
    line = GDF.AG.creategeom(GDF.AG.GDAL.wkbLineString25D)
    GDF.AG.addpoint!.(Ref(line), x, y, z)
    line
end

function makepoint(x, y, z)
    GDF.AG.createpoint.(x, y, z)
end

# function Base.show(io::IO, geom::GDF.AG.AbstractGeometry)
#     if geom.ptr == C_NULL
#         print(io, "NULL Geometry")
#     else
#         print(io, "$(GDF.AG.getgeomtype(geom)) geometry")
#     end
# end

function envelope_polygon(geom::GDF.AG.AbstractGeometry)
    e = GDF.AG.envelope(geom)
    polygon = GDF.AG.createpolygon()
    ring = GDF.AG.createlinearring([(e.MinX, e.MinY), (e.MaxX, e.MinY), (e.MaxX, e.MaxY), (e.MinX, e.MaxY), (e.MinX, e.MinY)])
    GDF.AG.addgeom!(polygon, ring)
    polygon
end
