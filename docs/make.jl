using Documenter, SpaceAltimetry
using DocumenterMarkdown

dir = @__DIR__
cp(joinpath(dir, "../CONTRIBUTING.md"), joinpath(dir, "src/CONTRIBUTING.md"); force = true)

makedocs(;
    modules = [
        SpaceAltimetry,
        SpaceAltimetry.ICESat,
        SpaceAltimetry.ICESat2,
        SpaceAltimetry.GEDI,
    ],
    format = Markdown(),
    repo = "https://github.com/evetion/SpaceAltimetry.jl/blob/{commit}{path}#L{line}",
    sitename = "SpaceAltimetry.jl",
    authors = "Maarten Pronk, Deltares",
    doctest = false,
)

deploydocs(;
    repo = "github.com/evetion/SpaceAltimetry.jl",
    deps = Deps.pip("mkdocs-material", "pygments", "python-markdown-math", "mkdocs-autorefs"),
    make = () -> run(`mkdocs build`),
    versions = ["stable" => "v^", "v#.#.#", "dev" => "dev"],
    target = "site",
)
