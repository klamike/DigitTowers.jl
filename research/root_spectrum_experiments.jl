# Reproduce the exact classification over all positive integer root orders:
#   julia --project research/root_spectrum_experiments.jl
using DigitTowers
using TOML

output = joinpath(@__DIR__, "results")
mkpath(output)
result = root_spectrum(2:1000; max_solutions=10_000)
@assert result.complete
@assert result.candidates == 1702
@assert [x.number for x in result.solutions] == BigInt[262144, 4294967296, big(3)^64]
@assert all(verify_root_certificate, result.solutions)
permissive = root_spectrum(2:1000; zero_to_zero=:one, max_solutions=10_000)
@assert permissive.complete
@assert [x.number for x in permissive.solutions] == [x.number for x in result.solutions]
restricted = root_spectrum(2:1000; allowed_digits=2:9, max_solutions=10_000)
@assert restricted.complete
@assert [x.number for x in restricted.solutions] == BigInt[4294967296]

open(joinpath(output, "root_spectrum_solutions.tsv"), "w") do io
    println(io, "number\tlength\tprimitive\tg\th\tk\trequired_tail_threshold\troot\troot_expression\tdigits\tzero_one_free")
    for x in result.solutions
        println(io, join((x.number, length(x.digits), x.primitive, x.g, x.h, x.k,
                         x.required_tail_threshold, isnothing(x.root) ? ">1000" : string(x.root),
                         DigitTowers._spectrum_root_expression(x), join(x.digits, ','),
                         all(>=(2), x.digits)), '\t'))
    end
end
metadata = Dict(
    "julia" => string(VERSION), "radix" => 10, "lengths" => "2:1000",
    "root_orders" => "all positive integers, with no upper bound",
    "root_display_limit" => 1000, "zero_to_zero" => "forbid",
    "grammar" => "single-digit right-associated powers; external root",
    "complete" => result.complete, "candidates" => result.candidates,
    "solutions" => length(result.solutions),
    "same_solutions_with_zero_to_zero_one" => true,
    "zero_one_free_solutions" => 1,
    "verification" => "prime-valuation certificates; test suite also checks independent literal and modular oracles",
)
open(joinpath(output, "root_spectrum_metadata.toml"), "w") do io
    TOML.print(io, metadata)
end
for x in result.solutions
    println(expression(x))
end
