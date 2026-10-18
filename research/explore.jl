#=
Reproduce bounded searches with JuMP/HiGHS and an independent integer oracle.

    julia --project=. research/explore.jl
    julia --project=. research/explore.jl --max-digits=20 --root-max-digits=12

Output is written to research/results/. `complete` records exhaustion of the
CP search, and every complete result must agree with the separate oracle.
=#
using DigitTowers
using Dates
using TOML

function option_int(name, default)
    prefix = "--" * name * "="
    matches = filter(arg -> startswith(arg, prefix), ARGS)
    return isempty(matches) ? default : parse(Int, only(matches)[length(prefix)+1:end])
end

# Independently implemented bounded arithmetic: exponentiation by squaring,
# rather than the package's repeated-multiplication transition evaluator.
function multiply_clip(a::BigInt, b::BigInt, limit::BigInt)
    iszero(a) || iszero(b) ? big(0) : a > limit ÷ b ? limit + 1 : a * b
end

function power_clip(a::BigInt, e::BigInt, limit::BigInt)
    iszero(a) && iszero(e) && return nothing
    result = big(1)
    factor = a
    while e > 0
        isodd(e) && (result = multiply_clip(result, factor, limit))
        e >>= 1
        e > 0 && (factor = multiply_clip(factor, factor, limit))
    end
    return result
end

function suffix_oracle(digits, exponent::Int)
    limit = BigInt(exponent)
    value = min(BigInt(last(digits)), limit + 1)
    for base in reverse(digits[1:end-1])
        value = power_clip(BigInt(base), value, limit)
        isnothing(value) && return nothing
    end
    return value
end

function independent_oracle(config::Config)
    # The experiment grammars have single-digit bases. The primitive bases and
    # multiplicities are listed independently instead of using candidate_table.
    primitives = ((2, 2, 1), (3, 3, 1), (4, 2, 2), (5, 5, 1),
                  (6, 6, 1), (7, 7, 1), (8, 2, 3), (9, 3, 2))
    lower = big(10)^(config.ndigits - 1)
    upper = 10lower - 1
    result = Tuple{BigInt,Int,Int}[]
    for (base, primitive, multiplicity) in primitives
        number, h = big(1), 0
        while number <= upper ÷ primitive
            number *= primitive
            h += 1
            number < lower && continue
            ds = [Int(ch - '0') for ch in string(number)]
            all(in(config.allowed_digits), ds) || continue
            index = config.root_digits + 1
            ds[index] == base || continue
            for root in config.roots
                config.root_digits > 0 && ds[1] != root && continue
                numerator = root * h
                numerator % multiplicity == 0 || continue
                exponent = numerator ÷ multiplicity
                suffix_oracle(ds[index+1:end], exponent) == exponent || continue
                @assert number^root == BigInt(base)^exponent
                push!(result, (copy(number), root, exponent))
            end
        end
    end
    return sort!(unique(result))
end

function run_experiments()
    max_digits = option_int("max-digits", 100)
    root_max_digits = option_int("root-max-digits", 20)
    max_digits >= 6 || error("max-digits must be at least 6")
    root_max_digits >= 3 || error("root-max-digits must be at least 3")
    output_dir = joinpath(@__DIR__, "results")
    mkpath(output_dir)
    summaries_path = joinpath(output_dir, "searches.tsv")
    solutions_path = joinpath(output_dir, "solutions.tsv")
    complete_count = 0
    search_count = 0
    open(summaries_path, "w") do summaries
        open(solutions_path, "w") do solutions
            println(summaries, "family\tndigits\troots\troot_digits\tdigit_domain\tcomplete\tstatus\tcandidates\tcap\tsolutions\toracle_solutions\tseconds")
            println(solutions, "family\tndigits\tnumber\troot\texponent\texpression")
            families = [
                ("strict", 2:max_digits, [2], 0, collect(0:9)),
                ("zero_free", 2:max_digits, [2], 0, collect(1:9)),
                ("no_zero_or_one_small", 2:4, [2], 0, collect(2:9)),
                ("root_variations", 2:root_max_digits, collect(1:9), 0, collect(0:9)),
                ("consumed_root", 3:root_max_digits, collect(2:9), 1, collect(0:9)),
            ]
            for (family, lengths, roots, root_digits, domain) in families
                for n in lengths
                    config = Config(ndigits=n, roots=roots, root_digits=root_digits,
                                    allowed_digits=domain, time_limit=10.0)
                    expected = independent_oracle(config)
                    result = nothing
                    seconds = @elapsed result = search(config; method=:cp, max_solutions=1000)
                    found = sort!([(x.number, x.root, x.exponent) for x in result.solutions])
                    @assert all(in(expected), found) "CP returned an assignment absent from the independent oracle"
                    result.complete && @assert found == expected "Complete CP search disagreed with independent oracle"
                    search_count += 1
                    complete_count += result.complete
                    fields = [family, n, join(roots, ","), root_digits, join(domain, ","),
                              result.complete, result.status, result.candidates, result.cap,
                              length(found), length(expected), round(seconds; digits=6)]
                    println(summaries, join(fields, '\t'))
                    flush(summaries)
                    for x in result.solutions
                        println(solutions, join([family, n, x.number, x.root, x.exponent,
                                                expression(x, config)], '\t'))
                    end
                    flush(solutions)
                    (n % 10 == 0 || !isempty(found) || !result.complete) &&
                        println("$family n=$n complete=$(result.complete) found=$(length(found)) time=$(round(seconds;digits=2))s")
                end
            end
        end
    end
    metadata = Dict(
        "julia_version" => string(VERSION),
        "completed_at_utc" => string(now(UTC)),
        "max_digits" => max_digits,
        "root_max_digits" => root_max_digits,
        "searches" => search_count,
        "complete_searches" => complete_count,
        "oracle" => "Independent exact primitive-power enumeration and bounded exponentiation by squaring",
        "zero_to_zero" => "forbid",
        "per_optimize_time_limit_seconds" => 10,
    )
    open(joinpath(output_dir, "metadata.toml"), "w") do io
        TOML.print(io, metadata; sorted=true)
    end
    println("Completed $complete_count / $search_count CP searches. Results: $output_dir")
end

function recover_incomplete_searches(output_dir)
    source = readlines(joinpath(output_dir, "searches.tsv"))
    header = split(first(source), '\t')
    recovered = 0
    incomplete = 0
    open(joinpath(output_dir, "partition_recovery.tsv"), "w") do io
        println(io, "family\tndigits\tbase\tcomplete\tstatus\tcandidates\tsolutions\tseconds")
        for line in source[2:end]
            row = Dict(zip(header, split(line, '\t')))
            row["complete"] == "true" && continue
            incomplete += 1
            config = Config(
                ndigits=parse(Int, row["ndigits"]),
                roots=parse.(Int, split(row["roots"], ',')),
                root_digits=parse(Int, row["root_digits"]),
                allowed_digits=parse.(Int, split(row["digit_domain"], ',')),
                time_limit=20.0,
            )
            widths, _ = DigitTowers.grammar(config)
            necessary = DigitTowers.candidate_table(config, widths)
            bases = sort!(unique(Int(first(x.blocks)) for x in necessary))
            all_complete = true
            all_found = Tuple{BigInt,Int,Int}[]
            for base in bases
                kwargs = (; (key => getfield(config, key) for key in fieldnames(Config))...)
                partition = Config(; kwargs..., bases=[base])
                result = nothing
                seconds = @elapsed result = search(partition; method=:cp, max_solutions=1000)
                all_complete &= result.complete
                append!(all_found, [(x.number, x.root, x.exponent) for x in result.solutions])
                @assert all(verify(x, partition) for x in result.solutions)
                println(io, join([row["family"], config.ndigits, base,
                                  result.complete, result.status, result.candidates,
                                  length(result.solutions), round(seconds; digits=6)], '\t'))
                flush(io)
            end
            expected = independent_oracle(config)
            all_complete && @assert sort!(all_found) == expected
            recovered += all_complete
            println("Recovered $(row["family"]) n=$(config.ndigits): complete=$all_complete using $(length(bases)) base partitions")
        end
    end
    metadata_path = joinpath(output_dir, "metadata.toml")
    metadata = TOML.parsefile(metadata_path)
    metadata["partition_recovered_searches"] = recovered
    metadata["covered_searches"] = metadata["complete_searches"] + recovered
    metadata["remaining_incomplete_searches"] = incomplete - recovered
    open(metadata_path, "w") do io
        TOML.print(io, metadata; sorted=true)
    end
end

function supplementary_searches(output_dir)
    open(joinpath(output_dir, "distinct_searches.tsv"), "w") do io
        println(io, "ndigits\tcomplete\tstatus\tcandidates\tsolutions\tseconds")
        for n in 2:10
            config = Config(ndigits=n, distinct_digits=true, time_limit=10.0)
            result = nothing
            seconds = @elapsed result = search(config; method=:cp)
            @assert result.complete && isempty(result.solutions)
            # Independent filtering of the original oracle, rather than
            # trusting the package's AllDifferent constraint or preprocessing.
            expected = filter(x -> allunique(string(x[1])), independent_oracle(config))
            @assert isempty(expected)
            println(io, join([n, result.complete, result.status, result.candidates,
                              length(result.solutions), round(seconds; digits=6)], '\t'))
        end
    end
    open(joinpath(output_dir, "grouped_examples.tsv"), "w") do io
        println(io, "number\tndigits\tbase\troot\texponent\tblock_widths\tcomplete\tstatus\tseconds")
        for (base, power, root) in ((26, 42, 2), (136, 16, 6))
            number = BigInt(base)^power
            text = string(number)
            prefix_width = length(string(base))
            exponent_width = length(string(root * power))
            widths = [prefix_width, exponent_width,
                      ones(Int, length(text) - prefix_width - exponent_width)...]
            config = Config(ndigits=length(text), roots=[root], bases=[base],
                            block_widths=widths, time_limit=20.0)
            result = nothing
            seconds = @elapsed result = search(config; method=:cp)
            @assert result.complete && length(result.solutions) == 1
            x = only(result.solutions)
            @assert x.number == number && verify(x, config)
            tail = [Int(ch - '0') for ch in text[prefix_width+exponent_width+1:end]]
            @assert suffix_oracle(tail, 1) == 1
            println(io, join([number, length(text), base, root, x.exponent,
                              join(widths, ','), result.complete, result.status,
                              round(seconds; digits=6)], '\t'))
        end
    end
end

# --supplement-only reuses the recorded primary run and repeats every recovery,
# distinct-digit search, and grouped example. Default execution repeats all.
"--supplement-only" in ARGS || run_experiments()
output_dir = joinpath(@__DIR__, "results")
recover_incomplete_searches(output_dir)
supplementary_searches(output_dir)
