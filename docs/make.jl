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
    format = Documenter.HTML(prettyurls=false, edit_link=nothing, repolink=nothing),
    pages = [
        "Overview" => "index.md",
        "Formulation" => "formulation.md",
        "Configuration" => "configuration.md",
        "Results" => "results.md",
        "Performance" => "performance.md",
        "API" => "api.md",
    ],
)
