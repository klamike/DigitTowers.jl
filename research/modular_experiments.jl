# Exhaustive modular puzzles and functional graphs. Run from the repository:
# julia --project=. research/modular_experiments.jl
using DigitTowers
using TOML

directory = joinpath(@__DIR__, "results")
mkpath(directory)

records = Dict{String,Any}[]
for policy in (:forbid, :one), radix in (2, 3, 4, 5, 6, 8, 10, 12, 16), width in 2:4
    result = DigitTowers.modular_dynamics(width; radix, zero_to_zero=policy)
    push!(records, Dict(
        "radix" => radix,
        "ndigits" => width,
        "zero_to_zero" => string(policy),
        "states" => result.states,
        "complete" => result.complete,
        "cycles" => [Dict("states" => cycle,
                          "words" => [string(n; base=radix, pad=width) for n in cycle],
                          "basin_size" => basin)
                     for (cycle, basin) in zip(result.cycles, result.basin_sizes)],
        "undefined" => result.undefined,
        "undefined_basin" => result.undefined_basin,
    ))
end
# The decimal five-digit graph is also small enough for complete enumeration.
for policy in (:forbid, :one)
    result = DigitTowers.modular_dynamics(5; zero_to_zero=policy)
    push!(records, Dict(
        "radix" => 10,
        "ndigits" => 5,
        "zero_to_zero" => string(policy),
        "states" => result.states,
        "complete" => result.complete,
        "cycles" => [Dict("states" => cycle,
                          "words" => [string(n; pad=5) for n in cycle],
                          "basin_size" => basin)
                     for (cycle, basin) in zip(result.cycles, result.basin_sizes)],
        "undefined" => result.undefined,
        "undefined_basin" => result.undefined_basin,
    ))
end

path = joinpath(directory, "modular_dynamics.toml")
open(path, "w") do io
    TOML.print(io, Dict("definition" =>
        "F(N) = tower(width-padded base-radix digits of N) mod radix^width; all states 0 <= N < radix^width",
        "graphs" => records); sorted=true)
end

path = joinpath(directory, "modular_fixedpoints.tsv")
list_field(values) = isempty(values) ? "none" : join(values, ",")
open(path, "w") do io
    println(io, "radix\tndigits\texamined\tundefined\tfixedpoints_decimal\tfixedpoints_words")
    for radix in (2, 3, 4, 5, 6, 8, 10, 12, 16), width in 2:4
        result = DigitTowers.modular_fixedpoints(width; radix)
        println(io, join((radix, width, result.examined, result.undefined,
            list_field(result.solutions),
            list_field(string.(result.solutions; base=radix))), '\t'))
    end
    result = DigitTowers.modular_fixedpoints(5)
    println(io, join((10, 5, result.examined, result.undefined,
        list_field(result.solutions), list_field(result.solutions)), '\t'))
end
println("Wrote complete modular fixed-point searches and $(length(records)) functional graphs to $directory")
