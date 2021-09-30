### A Pluto.jl notebook ###
# v0.16.1

using Markdown
using InteractiveUtils

# ╔═╡ b7aa82f4-f38f-4dd2-9d86-984205cf95b9
using SpaceLiDAR

# ╔═╡ 2337d9f8-7615-43cc-9c8d-83176b685b8e
using DataFrames

# ╔═╡ 6a648fcf-0bd5-49ae-9cf8-0cf99867ca47
using GeoDataFrames

# ╔═╡ 7efc9e7e-58be-4fac-9eca-d571f1382b65
using LazIO

# ╔═╡ 850f819c-de8e-4d71-8891-ed6198fcface
using GeoArrays

# ╔═╡ a5acd89a-320b-4cc8-81d3-16fbedb689b0
md"""# SpaceLiDAR.jl @ JuliaCon 2021"""

# ╔═╡ 8c11cb9b-ef88-48f3-a4c3-9dbfee1ccbce
md"""
An example of using SpaceLiDAR to retrieve and process ICESat-2 and GEDI satellite LiDAR data."""

# ╔═╡ 1d8c9cd5-544a-4267-9895-7d41a81146d8
md"""#### Search"""

# ╔═╡ 5c6b7711-5799-4a34-9cfc-14902d30bdd2
md"""Let's find some data in Vietnam. We can define a (very rough) bounding box and search for data. This makes use of [NASA EarthData Search](https://search.earthdata.nasa.gov/)."""

# ╔═╡ 9f611522-1c93-4d77-ac8e-49d7b90b1820
vietnam = (min_x = 102., min_y = 8.0, max_x = 107.0, max_y = 12.0)

# ╔═╡ 1729d09f-fa21-4da5-ac71-e1eb34f0ca11
granules = find(:ICESat2, "ATL08", vietnam, "004")

# ╔═╡ c7ed0663-0dd0-496e-bbcb-61f09e5691c5
md"""These datasets (granules) come in the form of HDF5 (.h5) files, with *a lot* of attributes. Downloading them requires a working NASA EarthData account configured in an `~/.netrc` file."""

# ╔═╡ bf418df8-6923-44f3-a067-367a7c52afdf
begin
	granule = copy(granules[1])
	SpaceLiDAR.download!(granule)
end

# ╔═╡ 6da50bf6-fd03-479b-8d04-d9ccc41415c5
md"""#### Extract"""

# ╔═╡ 4e3e4815-778e-4339-bd9b-256bb4687804
md"""Now that we have one granule locally, let's extract some data. This package is  opiniated and does already apply some filters for you. It also converts dates and unnests where required."""

# ╔═╡ 4c04f1c2-c5d3-4f8e-9ba1-17088eb5ebbf
t = vcat(DataFrame.(points(granule, canopy=true))...)

# ╔═╡ 36d1438b-041a-4ea5-a4c6-e49b0fe9c4ff
md"""ICESat-2 and GEDI have multiple beams, each is provided as its own Table, hence the `vcat`."""

# ╔═╡ 74e7ee28-de25-4393-b778-9766d58c189d
tt = t[(t.sensitivity .>= 2) .& (t.u .<= 5) , :]

# ╔═╡ 195ebb14-64e9-4d60-bada-e23aefb11ee8
md"""#### Export"""

# ╔═╡ 518bcb83-fa7e-42f6-a53e-240f94dd5d19
md"""It's useful to inspect this data in other software such as QGIS, so let's save it as a GeoPackage. For this purpose I made `GeoDataFrames.jl`, built on top of `ArchGDAL.jl` and `GDAL`."""

# ╔═╡ 4e4c0925-a88f-447e-9a01-6847169d8325
tt.geom = createpoint.(tt.x, tt.y, tt.z)

# ╔═╡ a863a0bc-bd7b-421d-85f0-65b0b0572ac2
GeoDataFrames.write("$(granule.id).gpkg", tt)

# ╔═╡ da214c65-3a1b-4691-ae0b-6c00549f5423
md"""For those more familiar with airborne LiDAR, you can also export to the `.laz` format by using `LazIO.jl`. Note that most attributes are lost this way."""

# ╔═╡ 21d2614e-de2a-4ede-bdd6-a3a862acddad
LazIO.write("$(granule.id).laz", granule)

# ╔═╡ bd6b1634-818e-4e04-9164-d69bef37298f
md"""Let's also write a geotiff raster file and interpolate it. We'll make use of `GeoArrays.jl`, also built on top of `ArchGDAL.jl` and `GDAL` to write it."""

# ╔═╡ b200a572-606a-4a7e-b605-6deb16e70ea2
begin
	ga = GeoArray(zeros(1000, 800))
	GeoArrays.bbox!(ga, vietnam)
	epsg!(ga, 4326)
	interpolate!(ga, tt)
	GeoArrays.write!("test.tif", ga)
	ga
end

# ╔═╡ Cell order:
# ╟─a5acd89a-320b-4cc8-81d3-16fbedb689b0
# ╟─8c11cb9b-ef88-48f3-a4c3-9dbfee1ccbce
# ╠═b7aa82f4-f38f-4dd2-9d86-984205cf95b9
# ╟─1d8c9cd5-544a-4267-9895-7d41a81146d8
# ╟─5c6b7711-5799-4a34-9cfc-14902d30bdd2
# ╠═9f611522-1c93-4d77-ac8e-49d7b90b1820
# ╠═1729d09f-fa21-4da5-ac71-e1eb34f0ca11
# ╟─c7ed0663-0dd0-496e-bbcb-61f09e5691c5
# ╠═bf418df8-6923-44f3-a067-367a7c52afdf
# ╟─6da50bf6-fd03-479b-8d04-d9ccc41415c5
# ╟─4e3e4815-778e-4339-bd9b-256bb4687804
# ╠═2337d9f8-7615-43cc-9c8d-83176b685b8e
# ╠═4c04f1c2-c5d3-4f8e-9ba1-17088eb5ebbf
# ╟─36d1438b-041a-4ea5-a4c6-e49b0fe9c4ff
# ╠═74e7ee28-de25-4393-b778-9766d58c189d
# ╟─195ebb14-64e9-4d60-bada-e23aefb11ee8
# ╟─518bcb83-fa7e-42f6-a53e-240f94dd5d19
# ╠═6a648fcf-0bd5-49ae-9cf8-0cf99867ca47
# ╠═4e4c0925-a88f-447e-9a01-6847169d8325
# ╠═a863a0bc-bd7b-421d-85f0-65b0b0572ac2
# ╟─da214c65-3a1b-4691-ae0b-6c00549f5423
# ╠═7efc9e7e-58be-4fac-9eca-d571f1382b65
# ╠═21d2614e-de2a-4ede-bdd6-a3a862acddad
# ╟─bd6b1634-818e-4e04-9164-d69bef37298f
# ╠═850f819c-de8e-4d71-8891-ed6198fcface
# ╠═b200a572-606a-4a7e-b605-6deb16e70ea2
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
