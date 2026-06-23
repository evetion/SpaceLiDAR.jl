using Documenter, SpaceLiDAR
using DocumenterMarkdown

dir = @__DIR__
cp(joinpath(dir, "../CONTRIBUTING.md"), joinpath(dir, "src/CONTRIBUTING.md"); force = true)

makedocs(;
    modules = [SpaceLiDAR],
    format = Markdown(),
    repo = "https://github.com/evetion/SpaceLiDAR.jl/blob/{commit}{path}#L{line}",
    sitename = "SpaceLiDAR.jl",
    authors = "Maarten Pronk, Deltares",
    doctest = false,
)

deploydocs(;
    repo = "github.com/evetion/SpaceLiDAR.jl",
    deps = Deps.pip("mkdocs-material", "pygments", "python-markdown-math", "mkdocs-autorefs"),
    make = () -> run(`mkdocs build`),
    versions = ["stable" => "v^", "v#.#.#", "dev" => "dev"],
    target = "site",
)
