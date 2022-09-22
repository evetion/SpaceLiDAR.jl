# Downloading

As shown in [Tutorial: Search for data](../tutorial/usage.md#search-for-data), it is easy to find data. Downloading the data might be harder though,
especially when downloading a large amount of granules or even mirroring a complete DAAC.
Indeed, the Julia [`download!`](@ref) won't work in parallel, nor will it resume downloads or show its progress.
In such cases it's useful to export a list of granules to a text file and use an external download tool:

```julia
granules = find(:ICESat2, "ATL08")
SpaceLiDAR.write_granule_urls!("atl08_world.txt", granules)
```

In my case, I use [aria2c](https://aria2.github.io/manual/en/html/aria2c.html).
Note that downloading from the granule urls require a EarthData login,
normally setup in an .netrc file (also see [`netrc!`](@ref)).
```bash
aria2c -c -i atl08_world.txt
```

Once finished, one can again [`instantiate`](@ref) the list of granules with the folder to which all files have been downloaded.
