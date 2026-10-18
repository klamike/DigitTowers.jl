# Reproduce the nondecimal atlas from the repository root:
#   julia --project research/radix_experiments.jl
# No package installation or floating-point number theory is required.
using DigitTowers
using TOML

output = joinpath(@__DIR__, "results")
mkpath(output)
rows = RadixSolution[]
searches = NamedTuple[]
for radix in 3:64
    result = radix_sweep(radix, 2:100; roots=1:1000, max_solutions=10_000)
    @assert result.complete
    @assert all(verify_radix, result.solutions)
    append!(rows, result.solutions)
    push!(searches, (; radix, candidates=result.candidates, solutions=length(result.solutions)))
end
open(joinpath(output, "radix_solutions.tsv"), "w") do io
    println(io, "radix\tnumber\troot\texponent\tlength\tdigits\tzero_free\tzero_one_free")
    for x in rows
        println(io, join((x.radix, x.number, x.root, x.exponent, length(x.digits),
                         join(x.digits, ','), 0 ∉ x.digits,
                         all(>=(2), x.digits)), '\t'))
    end
end
open(joinpath(output, "radix_searches.tsv"), "w") do io
    println(io, "radix\tcandidates\tsolutions")
    for x in searches
        println(io, "$(x.radix)\t$(x.candidates)\t$(x.solutions)")
    end
end
# Independently repeat the blocker-free slice with its digit restriction.
# Its all-length certificate is explained in docs/src/radices.md.
for radix in 3:64
    restricted = radix_sweep(radix, 2:4; roots=1:1000,
                             allowed_digits=2:radix-1, max_solutions=10_000)
    @assert restricted.complete
    expected = filter(x -> x.radix == radix && all(>=(2), x.digits), rows)
    @assert [(x.number, x.root) for x in restricted.solutions] ==
            [(x.number, x.root) for x in expected]
    @assert all(x -> length(x.digits) == 2, restricted.solutions)
end
metadata = Dict(
    "radices" => "3:64", "lengths" => "2:100", "roots" => "1:1000",
    "zero_to_zero" => "forbid", "grammar" => "single-digit right-associated powers; external root",
    "julia" => string(VERSION), "complete" => true,
    "solutions" => length(rows), "root_free_solutions" => count(x -> x.root == 1, rows),
    "long_root_free_solutions" => count(x -> x.root == 1 && length(x.digits) > 2, rows),
    "candidates" => sum(x.candidates for x in searches),
)
open(joinpath(output, "radix_metadata.toml"), "w") do io
    TOML.print(io, metadata)
end
println("Verified $(length(rows)) solutions from $(metadata["candidates"]) primitive-power numeral candidates.")
for x in filter(x -> x.root == 1 && length(x.digits) > 2, rows)
    println(expression_radix(x))
end
