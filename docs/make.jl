using Documenter, SpaceLiDAR

makedocs(;
    modules=[SpaceLiDAR],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/evetion/SpaceLiDAR.jl/blob/{commit}{path}#L{line}",
    sitename="SpaceLiDAR.jl",
    authors="Maarten Pronk, Deltares",
    assets=String[],
)

deploydocs(;
    repo="github.com/evetion/SpaceLiDAR.jl",
)
