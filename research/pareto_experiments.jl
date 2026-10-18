# Run: julia --project=. research/pareto_experiments.jl [maximum_digits]
using DigitTowers
using TOML

function supported_cost(pair, pairs)
    lower = big(0)//big(1)
    upper = nothing
    for other in pairs
        delta = pair[1]-other[1]
        rhs = other[2]-pair[2]
        if delta > 0
            bound = BigInt(rhs)//BigInt(delta)
            upper = isnothing(upper) ? bound : min(upper, bound)
        elseif delta < 0
            lower = max(lower, BigInt(rhs)//BigInt(delta))
        elseif rhs < 0
            return false
        end
    end
    return isnothing(upper) || lower <= upper
end

function run_pareto_experiments(maximum_digits=30)
    numbers = Set{BigInt}()
    roots = collect(2:9)
    for n in 2:maximum_digits, width in 1:min(3, n-1)
        config = Config(; ndigits=n, roots, block_widths=[width, n-width])
        for candidate in DigitTowers.prefix_candidates(config, [width, n-width])
            push!(numbers, candidate.number)
        end
    end
    output = joinpath(@__DIR__, "results")
    mkpath(output)
    start_time = time()
    labels = states = targets = represented = groups = certificates = tradeoffs = unsupported = 0
    open(joinpath(output, "pareto_census.tsv"), "w") do io
        println(io, "number\troot\tbase\texponent\tconcatenations\tadditions\tfrontier_size\tweighted_supported\twidths\toperators\texpression")
        for n in sort!(collect(numbers))
            result = DigitTowers.synthesize_frontier(n; roots,
                max_block_width=3, max_base_width=3)
            @assert result.complete && all(verify, result.certificates)
            labels += result.states
            states += result.value_states
            targets += result.targets
            represented += !isempty(result.certificates)
            groups += length(result.frontiers)
            certificates += length(result.certificates)
            for group in result.frontiers
                costs = [(c.concatenations, c.additions) for c in group.certificates]
                tradeoffs += length(costs) > 1
                for certificate in group.certificates
                    c, cfg = certificate.candidate, certificate.config
                    supported = supported_cost((certificate.concatenations,
                        certificate.additions), costs)
                    unsupported += !supported
                    println(io, join((n, c.root, first(c.blocks), c.exponent,
                        certificate.concatenations, certificate.additions,
                        length(costs), supported, join(cfg.block_widths, ','),
                        join(cfg.operators, ','), expression(certificate)), '\t'))
                end
            end
        end
    end
    metadata = Dict("julia_version" => string(VERSION),
        "lengths" => [2, maximum_digits], "roots" => roots,
        "max_block_width" => 3, "max_base_width" => 3,
        "operators" => ["^", "+"], "association" => "right",
        "root_digits" => 0, "leading_zeros_in_blocks" => false,
        "zero_to_zero" => "forbid", "complete" => true,
        "arithmetic_candidate_numbers" => length(numbers),
        "arithmetic_targets" => targets, "represented_numbers" => represented,
        "feasible_root_base_pairs" => groups, "nondominated_certificates" => certificates,
        "pareto_labels" => labels, "semantic_value_states" => states,
        "frontiers_with_tradeoffs" => tradeoffs,
        "unsupported_frontier_points" => unsupported, "seconds" => time()-start_time)
    open(joinpath(output, "pareto_metadata.toml"), "w") do io
        TOML.print(io, metadata; sorted=true)
    end
    println("Pareto census: ", represented, " numbers, ", certificates,
        " nondominated certificates, ", tradeoffs, " tradeoff frontiers, ",
        unsupported, " points missed by weighted sums.")
end

if abspath(PROGRAM_FILE) == (@__FILE__)
    run_pareto_experiments(isempty(ARGS) ? 30 : parse(Int, first(ARGS)))
end
