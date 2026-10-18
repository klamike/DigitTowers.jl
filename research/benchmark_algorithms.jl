# Compare warmed exact algorithms on identical bounded problems.
# Run: julia --project=. research/benchmark_algorithms.jl
using DigitTowers
using Statistics
using Dates
using TOML

const PRIMITIVES = ((2, 2, 1), (3, 3, 1), (4, 2, 2), (5, 5, 1),
                    (6, 6, 1), (7, 7, 1), (8, 2, 3), (9, 3, 2))

function cp_scan(max_digits, roots)
    found = Tuple{BigInt,Int,Int}[]
    for n in 2:max_digits
        result = search(Config(ndigits=n, roots=roots, time_limit=30.0);
                        method=:cp, max_solutions=1000)
        @assert result.complete
        append!(found, [(x.number, x.root, x.exponent) for x in result.solutions])
    end
    return sort!(found)
end

function candidate_scan(max_digits, roots)
    found = Tuple{BigInt,Int,Int}[]
    for n in 2:max_digits
        config = Config(ndigits=n, roots=roots)
        widths, _ = DigitTowers.grammar(config)
        for x in DigitTowers.candidate_table(config, widths)
            verify(x, config) && push!(found, (x.number, x.root, x.exponent))
        end
    end
    return sort!(found)
end

# Prototype specialised to single-digit towers. Enumerate each primitive power
# once across all lengths; derive root = g*E/h after one suffix evaluation.
# It is research code, not a replacement for the configurable package API.
function derived_root_scan(max_digits, roots)
    upper = big(10)^max_digits - 1
    root_max = maximum(roots)
    found = Tuple{BigInt,Int,Int}[]
    for (base, primitive, multiplicity) in PRIMITIVES
        number, h = big(primitive), 1
        while number <= upper
            text = string(number)
            if length(text) >= 2 && first(text) - '0' == base
                digits = BigInt[Int(ch - '0') for ch in text]
                upper_exponent = root_max * h ÷ multiplicity
                S = max(2, upper_exponent + 1)
                value = DigitTowers.capped_suffix(digits, fill(:^, length(digits)-1), S, :forbid)
                if !isnothing(value) && value < S && (multiplicity * value) % h == 0
                    root = multiplicity * value ÷ h
                    if root in roots
                        @assert number^root == BigInt(base)^value
                        push!(found, (copy(number), root, value))
                    end
                end
            end
            number *= primitive
            h += 1
        end
    end
    return sort!(found)
end

function measure(f, expected; samples=3)
    @assert f() == expected # compile and verify before measuring
    seconds = Float64[]
    allocated = Int[]
    for _ in 1:samples
        GC.gc()
        result = @timed f()
        @assert result.value == expected
        push!(seconds, result.time)
        push!(allocated, result.bytes)
    end
    return (; minimum=minimum(seconds), median=median(seconds),
              bytes=minimum(allocated), samples)
end

function main()
    output_dir = joinpath(@__DIR__, "results")
    mkpath(output_dir)
    scopes = [
        ("strict_2_to_20", 20, [2], (:cp, :candidate_scan, :derived_root)),
        ("roots_1_to_9_lengths_2_to_20", 20, collect(1:9), (:cp, :candidate_scan, :derived_root)),
        ("strict_2_to_100", 100, [2], (:candidate_scan, :derived_root)),
        ("roots_1_to_1000_lengths_2_to_1000", 1000, collect(1:1000), (:derived_root,)),
    ]
    functions = Dict(:cp=>cp_scan, :candidate_scan=>candidate_scan, :derived_root=>derived_root_scan)
    open(joinpath(output_dir, "algorithm_benchmarks.tsv"), "w") do io
        println(io, "scope\talgorithm\tmax_digits\tmin_root\tmax_root\tsamples\tminimum_seconds\tmedian_seconds\tminimum_allocated_bytes\tsolutions")
        for (name, max_digits, roots, algorithms) in scopes
            expected = derived_root_scan(max_digits, roots)
            for algorithm in algorithms
                result = measure(() -> functions[algorithm](max_digits, roots), expected)
                println(io, join([name, algorithm, max_digits, minimum(roots), maximum(roots),
                                  result.samples, result.minimum, result.median,
                                  result.bytes, length(expected)], '\t'))
                flush(io)
                println(name, " ", algorithm, " median=", result.median, " s solutions=", length(expected))
            end
        end
    end
    open(joinpath(output_dir, "algorithm_benchmark_metadata.toml"), "w") do io
        TOML.print(io, Dict("julia_version"=>string(VERSION), "time_utc"=>string(now(UTC)),
                           "threads"=>Threads.nthreads(), "cpu"=>Sys.CPU_NAME,
                           "warmup"=>"one complete verified invocation per measured method",
                           "samples"=>3); sorted=true)
    end
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
