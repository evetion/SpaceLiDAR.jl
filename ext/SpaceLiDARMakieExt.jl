module SpaceLiDARMakieExt

using Makie
using SpaceLiDAR
using Tables

Makie.preferred_axis_type(plot::Makie.Plot(SpaceLiDAR.Granule)) = Makie.LScene

Makie.plottype(::SpaceLiDAR.Granule) = Makie.Scatter
Makie.used_attributes(::Type{<:Makie.Scatter}, ::SpaceLiDAR.Granule) = (:zscale, :tracks)

function Makie.convert_arguments(p::Type{<:Makie.Scatter}, geom::SpaceLiDAR.Granule; zscale = 1, tracks = nothing, kwargs...)
    table = Tables.columns(points(geom))
    Makie.convert_arguments(p, table.longitude .* 110_000 .* cosd.(table.latitude), table.latitude * 110_000, table.height * zscale, kwargs...)
end

end
