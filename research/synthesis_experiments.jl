# Run from the repository: julia --project=. research/synthesis_experiments.jl
# Optional first argument changes the exhaustive decimal-length ceiling.
using DigitTowers
using TOML

const SYNTHESIS_MAX_DIGITS = isempty(ARGS) ? 30 : parse(Int, first(ARGS))
const SYNTHESIS_ROOTS = collect(2:9)
const SYNTHESIS_OUTPUT = joinpath(@__DIR__, "results")
mkpath(SYNTHESIS_OUTPUT)

# This candidate generation is independent of the synthesis DP. Every possible
# answer under the bounded base grammar satisfies N^r=b^E and therefore occurs
# in one of these exact prefix windows, regardless of its suffix partition.
function run_synthesis_experiments()
    numbers = Set{BigInt}()
    for n in 2:SYNTHESIS_MAX_DIGITS, width in 1:min(3, n-1)
        config = Config(ndigits=n, roots=SYNTHESIS_ROOTS,
            block_widths=[width, n-width])
        for candidate in DigitTowers.prefix_candidates(config, [width, n-width])
            push!(numbers, candidate.number)
        end
    end

    total_states = 0
    total_targets = 0
    solutions = 0
    represented_numbers = Set{BigInt}()
    square_numbers = Set{BigInt}()
    start_time = time()
    open(joinpath(SYNTHESIS_OUTPUT, "synthesis_census.tsv"), "w") do io
        println(io, "number\troot\tbase\texponent\tcost\tconcatenations\tadditions\twidths\toperators\texpression")
        for n in sort!(collect(numbers))
            result = synthesize(n; roots=SYNTHESIS_ROOTS,
                max_block_width=3, max_base_width=3, allow_addition=true)
            @assert result.complete
            total_states += result.states
            total_targets += result.targets
            for certificate in result.certificates
                @assert verify(certificate)
                candidate, config = certificate.candidate, certificate.config
                solutions += 1
                push!(represented_numbers, n)
                candidate.root == 2 && push!(square_numbers, n)
                println(io, join((n, candidate.root, first(candidate.blocks),
                    candidate.exponent, certificate.cost,
                    certificate.concatenations, certificate.additions,
                    join(config.block_widths, ','), join(config.operators, ','),
                    expression(certificate)), '\t'))
            end
        end
    end

    # Include long and consumed-root examples outside the census's finite domain.
    examples = [
        (big(262144), [2], 0, 3),
        (big(256), [7], 0, 3),
        (big(94143178827), [6], 0, 3),
        (big(678223072849), [6], 1, 3),
        (big(4611686018427387904), [2], 0, 3),
        (parse(BigInt,"31622786796633508952"), [2], 0, 7),
        (parse(BigInt,"268460636031393932323010374318061912785738337881638804914176"), [2], 0, 3),
    ]
    open(joinpath(SYNTHESIS_OUTPUT, "synthesis_examples.tsv"), "w") do io
        println(io, "number\troot_digits\troot\tmax_block_width\tallow_addition\tcost\tconcatenations\tadditions\tstates\texpression")
        for (n, roots, root_digits, max_block_width) in examples, addition in (false, true)
            result = synthesize(n; roots, root_digits, max_block_width,
                allow_addition=addition)
            if isempty(result.certificates)
                println(io, join((n, root_digits, only(roots), max_block_width, addition, "none",
                    "none", "none", result.states, "none"), '\t'))
            end
            for certificate in result.certificates
                println(io, join((n, root_digits, certificate.candidate.root, max_block_width,
                    addition, certificate.cost, certificate.concatenations,
                    certificate.additions, result.states,
                    expression(certificate)), '\t'))
            end
        end
    end

    metadata = Dict(
        "julia_version" => string(VERSION),
        "lengths" => [2, SYNTHESIS_MAX_DIGITS],
        "roots" => SYNTHESIS_ROOTS,
        "max_block_width" => 3,
        "max_base_width" => 3,
        "operators" => ["^", "+"],
        "association" => "right",
        "root_digits" => 0,
        "leading_zeros_in_blocks" => false,
        "zero_to_zero" => "forbid",
        "cost_concatenation" => 1,
        "cost_addition" => 1,
        "complete" => true,
        "arithmetic_candidate_numbers" => length(numbers),
        "arithmetic_targets" => total_targets,
        "chart_states" => total_states,
        "minimum_cost_certificates" => solutions,
        "represented_numbers" => length(represented_numbers),
        "square_root_numbers" => length(square_numbers),
        "seconds" => time()-start_time,
    )
    open(joinpath(SYNTHESIS_OUTPUT, "synthesis_metadata.toml"), "w") do io
        TOML.print(io, metadata; sorted=true)
    end
    println("Synthesis census: ", length(numbers), " arithmetic candidates, ",
        length(represented_numbers), " represented numbers, ", solutions,
        " optimal certificates; ", total_states, " chart states.")
end

run_synthesis_experiments()
