const gedi_tracks = ("BEAM0000", "BEAM0001", "BEAM0010", "BEAM0011", "BEAM0101", "BEAM0110", "BEAM1000", "BEAM1011")

mutable struct GEDI_Granule{product} <: Granule
    id::AbstractString
    url::AbstractString
end
GEDI_Granule(product, args...) = GEDI_Granule{product}(args...)
