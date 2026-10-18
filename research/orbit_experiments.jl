# Run: julia --project=. research/orbit_experiments.jl
using DigitTowers
using TOML

function orbit_experiments()
    directory = joinpath(@__DIR__, "results")
    mkpath(directory)
    cases = vec([(big(start), width, radix, policy, 1_000_000)
        for radix in (2, 10), width in 2:16, policy in (:forbid, :one), start in (0, 1)])
    append!(cases, [
        (big(426), 3, 10, :forbid, 1_000_000),
        (big(624), 3, 10, :forbid, 1_000_000),
        (big(3456), 4, 10, :forbid, 1_000_000),
        (big(123), 3, 10, :forbid, 1_000_000),
        (big(426), 3, 10, :forbid, 1),
        (big(2)^999, 1000, 2, :one, 1_000_000),
        (big(2)^999, 1000, 2, :forbid, 1_000_000),
    ])
    field(value) = isnothing(value) ? "none" : string(value)
    complete_cases = 0
    open(joinpath(directory, "orbit_examples.tsv"), "w") do io
        println(io, "start\tndigits\tradix\tzero_to_zero\tmax_evaluations\tcomplete\ttermination\tpreperiod\tperiod\tentry\tundefined_at\tdistance_to_undefined\tevaluations")
        for (start, width, radix, policy, budget) in cases
            result = modular_orbit(start, width; radix, zero_to_zero=policy,
                max_evaluations=budget)
            result.complete && (complete_cases += 1)
            println(io, join(field.((start, width, radix, policy, budget,
                result.complete, result.termination, result.preperiod,
                result.period, result.entry, result.undefined_at,
                result.distance_to_undefined, result.evaluations)), '\t'))
        end
    end
    wide = modular_orbit(big(2)^999, 1000; radix=2, zero_to_zero=:one)
    @assert wide.complete && (wide.preperiod, wide.period, wide.entry) == (1,2,big(1))
    metadata = Dict("julia_version" => string(VERSION), "algorithm" => "Brent cycle detection",
        "cases" => length(cases), "complete_cases" => complete_cases,
        "incomplete_cases" => length(cases)-complete_cases,
        "wide_domain" => "2^1000 states", "wide_start" => "2^999",
        "wide_evaluations" => wide.evaluations,
        "scope" => "Selected single orbits; not an exhaustive census of all domain states")
    open(joinpath(directory, "orbit_metadata.toml"), "w") do io
        TOML.print(io, metadata; sorted=true)
    end
    println(metadata)
end

abspath(PROGRAM_FILE) == (@__FILE__) && orbit_experiments()
