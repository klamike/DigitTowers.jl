using DigitTowers
using Documenter

DocMeta.setdocmeta!(DigitTowers, :DocTestSetup, :(using DigitTowers); recursive=true)

makedocs(
    root = @__DIR__,
    sitename = "DigitTowers.jl",
    modules = [DigitTowers],
    checkdocs = :all,
    doctest = true,
    remotes = nothing,
    format = Documenter.HTML(prettyurls=get(ENV, "CI", "false") == "true", edit_link=nothing),
    pages = [
        "Overview" => "index.md",
        "Formulation" => "formulation.md",
        "Configuration" => "configuration.md",
        "Results" => "results.md",
        "Performance" => "performance.md",
        "Explorations" => [
            "Unbounded root orders" => "spectrum.md",
            "The tower language" => "language.md",
            "Other radices" => "radices.md",
            "Expression synthesis" => "synthesis.md",
            "Repair tradeoffs" => "pareto.md",
            "Reorder the digits" => "anagrams.md",
            "Modular dynamics" => "modular.md",
            "Near fixed points" => "nearby.md",
            "Follow one orbit" => "orbits.md",
        ],
        "API" => "api.md",
    ],
)
deploydocs(
    repo = "github.com/klamike/DigitTowers.jl.git",
)
