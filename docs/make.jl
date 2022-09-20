using Documenter, SpaceLiDAR
using DocumenterMarkdown

makedocs(;
    modules = [SpaceLiDAR],
    format = Markdown(),
    # pages=[
    # "API" => "reference/api.md",
    # ],
    repo = "https://github.com/evetion/SpaceLiDAR.jl/blob/{commit}{path}#L{line}",
    sitename = "SpaceLiDAR.jl",
    authors = "Maarten Pronk, Deltares",
)

deploydocs(;
    repo = "github.com/evetion/SpaceLiDAR.jl",
    deps = Deps.pip("mkdocs-material", "pygments", "python-markdown-math", "mkdocs-autorefs"),
    make = () -> (run(`mkdocs build`),
    versions = ["stable" => "v^", "v#.#.#", "dev" => "dev"],
    target = "site",
)
