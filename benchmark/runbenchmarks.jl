# Run from the repository root:
#   julia --project=benchmark benchmark/runbenchmarks.jl
# Imports/compilation are reported separately from warmed end-to-end searches.
using Dates
using TOML
using Statistics
const IMPORT_SECONDS = @elapsed eval(:(using DigitTowers, BenchmarkTools, Nemo))

function answers(result)
    sort!([(x.number, x.root, x.exponent) for x in result.solutions])
end

# Reject unsupported CP table sizes before allocating the table-to-MIP model.
# This is the same explicit state-space bound as the CP implementation.
function cp_table_size(config)
    widths, _ = DigitTowers.grammar(config)
    candidates = DigitTowers.candidate_table(config, widths)
    isempty(candidates) && return big(0)
    S = maximum(x.exponent for x in candidates) + 1
    rows = big(0)
    for i in 2:length(widths)-1
        rows += length(unique(min(S, x.blocks[i]) for x in candidates)) * BigInt(S + 1)
    end
    return rows
end

function ranged_search(lengths, roots, method)
    method == :sweep && return sweep(lengths; roots, max_solutions=1000)
    parts = [search(Config(ndigits=n, roots=roots); method, max_solutions=1000) for n in lengths]
    return (; solutions=vcat([part.solutions for part in parts]...),
            complete=all(part.complete for part in parts))
end

function benchmark_sweeps()
    cases = [
        ("lengths_2_to_20_roots_1_to_9", 2:20, collect(1:9), (:direct, :prefix, :nemo, :cp, :sweep)),
        ("lengths_2_to_100_root_2", 2:100, [2], (:direct, :prefix, :nemo, :sweep)),
        ("lengths_2_to_1000_roots_1_to_1000", 2:1000, collect(1:1000), (:sweep,)),
    ]
    open(joinpath(@__DIR__, "sweep_results.tsv"), "w") do io
        println(io, "case\tmethod\tcomplete\tsolutions\tsamples\tfirst_call_seconds\tminimum_seconds\tmedian_seconds\tallocated_bytes\tallocations")
        for (name, lengths, roots, methods) in cases
            baseline = sweep(lengths; roots, max_solutions=1000)
            @assert baseline.complete
            expected = answers(baseline)
            for method in methods
                result = nothing
                first_call = @elapsed result = ranged_search(lengths, roots, method)
                @assert result.complete && answers(result) == expected
                for x in result.solutions
                    @assert verify(x, Config(ndigits=length(x.digits), roots=roots))
                end
                # The CP range already takes several seconds per invocation;
                # cap its sample count so the complete suite stays bounded.
                if method == :cp
                    trial = @benchmark ranged_search($lengths, $roots, $method) samples=2 seconds=8 evals=1
                else
                    trial = @benchmark ranged_search($lengths, $roots, $method) samples=5 seconds=1 evals=1
                end
                best, middle = minimum(trial), median(trial)
                println(io, join([name, method, result.complete, length(expected),
                                  length(trial.times), first_call,
                                  best.time/1e9, middle.time/1e9,
                                  best.memory, best.allocs], '\t'))
                flush(io)
                println("$name $method median=$(middle.time/1e9)s")
            end
        end
    end
end

function main()
    methods = (:direct, :prefix, :nemo, :cp)
    cases = [
        ("original_6", Config(ndigits=6)),
        ("strict_30", Config(ndigits=30)),
        ("grouped_60", Config(ndigits=60, roots=[2], bases=[26],
                              block_widths=[2, 2, ones(Int, 56)...])),
        ("grouped_35", Config(ndigits=35, roots=[6], bases=[136],
                              block_widths=[3, 2, ones(Int, 30)...])),
        ("strict_500", Config(ndigits=500)),
        ("strict_2000", Config(ndigits=2000)),
    ]
    output = joinpath(@__DIR__, "results.tsv")
    open(output, "w") do io
        println(io, "case\tmethod\tstatus\tcomplete\tcandidates\tsolutions\tsamples\tfirst_call_seconds\tminimum_seconds\tmedian_seconds\tallocated_bytes\tallocations\tnotes")
        for (name, config) in cases
            expected = nothing
            for method in methods
                if method == :cp
                    rows = cp_table_size(config)
                    if rows > config.max_table_rows
                        println(io, join([name, method, "unsupported_table_size", false,
                                          "", "", 0, "", "", "", "", "",
                                          "estimated_rows=$rows; max_table_rows=$(config.max_table_rows)"], '\t'))
                        flush(io)
                        println("$name $method unsupported: $rows table rows")
                        continue
                    end
                end
                result = nothing
                first_call = @elapsed result = search(config; method=method, max_solutions=1000)
                @assert result.complete "$name/$method did not exhaust its search"
                @assert all(x -> verify(x, config), result.solutions)
                found = answers(result)
                if isnothing(expected)
                    expected = found
                else
                    @assert found == expected "Search methods disagreed for $name"
                end
                # Each evaluation calls search anew; CP construction is included.
                trial = @benchmark search($config; method=$method, max_solutions=1000) samples=5 seconds=1 evals=1
                best, middle = minimum(trial), median(trial)
                println(io, join([name, method, result.status, result.complete,
                                  result.candidates, length(result.solutions), length(trial.times),
                                  first_call, best.time / 1e9, middle.time / 1e9,
                                  best.memory, best.allocs, "verified_equal_answers"], '\t'))
                flush(io)
                println("$name $method median=$(middle.time/1e9)s solutions=$(length(found))")
            end
        end
    end
    benchmark_sweeps()
    metadata = Dict(
        "julia_version"=>string(VERSION),
        "digit_towers_version"=>string(Base.pkgversion(DigitTowers)),
        "benchmarktools_version"=>string(Base.pkgversion(BenchmarkTools)),
        "nemo_version"=>string(Base.pkgversion(Nemo)),
        "time_utc"=>string(now(UTC)), "cpu"=>Sys.CPU_NAME,
        "threads"=>Threads.nthreads(), "word_size"=>Sys.WORD_SIZE,
        "process_import_seconds"=>IMPORT_SECONDS,
        "timing"=>"Warmed end-to-end search, newly constructed model per CP evaluation",
        "first_call"=>"Includes compilation/setup for this case/method; not a clean-process cold-start measurement",
        "maximum_samples"=>5, "target_seconds_per_trial"=>1,
        "range_cp_maximum_samples"=>2, "range_cp_target_seconds"=>8,
    )
    open(joinpath(@__DIR__, "metadata.toml"), "w") do io
        TOML.print(io, metadata; sorted=true)
    end
    println("Saved $output")
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
