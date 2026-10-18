# Run: julia --project=. research/anagram_experiments.jl [maximum digits]
using DigitTowers
using TOML

function run_anagram_experiments(max_digits::Int=12)
    max_digits >= 2 || throw(ArgumentError("maximum digits must be at least two"))
    roots = collect(2:9)
    # The outer base is one decimal digit. Its primitive base therefore lies
    # in {2,3,5,6,7}, independent of the order of the number's own digits.
    numbers = Set{BigInt}()
    ceiling = big(10)^max_digits
    for base in (2,3,5,6,7)
        power = BigInt(base)
        while power < ceiling
            power >= 10 && push!(numbers, power)
            power *= base
        end
    end
    output = joinpath(@__DIR__, "results")
    mkpath(output)
    states = targets = certificates = 0
    represented = Set{BigInt}()
    rescued = Set{BigInt}()
    squares = Set{BigInt}()
    distinct = Set{BigInt}()
    zero_one_free = Set{BigInt}()
    start = time()
    open(joinpath(output, "anagram_census.tsv"), "w") do io
        println(io, "number\troot\tbase\texponent\tmoves\tdistinct_digits\tzero_one_free\ttower_digits\texpression")
        for number in sort!(collect(numbers))
            result = DigitTowers.anagram_towers(number; roots)
            @assert result.complete
            states += result.states
            targets += result.targets
            isempty(result.certificates) && continue
            push!(represented, number)
            minimum(x.moves for x in result.certificates) > 0 && push!(rescued, number)
            original = Int[c-'0' for c in string(number)]
            alldifferent = allunique(original)
            no_zero_one = all(>(1), original)
            alldifferent && push!(distinct, number)
            no_zero_one && push!(zero_one_free, number)
            for certificate in result.certificates
                @assert verify(certificate)
                certificates += 1
                certificate.root == 2 && push!(squares, number)
                println(io, join((number, certificate.root, first(certificate.digits),
                    certificate.exponent, certificate.moves, alldifferent, no_zero_one,
                    join(certificate.digits, ','), expression(certificate)), '\t'))
            end
        end
    end
    root_free = Set{BigInt}()
    root_free_distinct = Set{BigInt}()
    root_free_states = 0
    open(joinpath(output, "anagram_rootfree.tsv"), "w") do io
        println(io, "number\tbase\texponent\tmoves\tdistinct_digits\ttower_digits\texpression")
        for number in sort!(collect(numbers))
            result = DigitTowers.anagram_towers(number; roots=[1])
            @assert result.complete
            root_free_states += result.states
            for certificate in result.certificates
                @assert verify(certificate)
                push!(root_free, number)
                alldifferent = allunique(string(number))
                alldifferent && push!(root_free_distinct, number)
                println(io, join((number, first(certificate.digits),
                    certificate.exponent, certificate.moves, alldifferent,
                    join(certificate.digits, ','), expression(certificate)), '\t'))
            end
        end
    end
    metadata = Dict(
        "julia_version" => string(VERSION),
        "lengths" => [2, max_digits],
        "roots" => roots,
        "primitive_bases" => [2,3,5,6,7],
        "association" => "right",
        "zero_to_zero" => "forbid",
        "objective" => "minimum changed digit positions per root and leading base",
        "complete" => true,
        "arithmetic_candidate_numbers" => length(numbers),
        "arithmetic_targets" => targets,
        "chart_states" => states,
        "minimum_move_certificates" => certificates,
        "represented_numbers" => length(represented),
        "rescued_by_reordering_numbers" => length(rescued),
        "square_root_numbers" => length(squares),
        "distinct_digit_numbers" => length(distinct),
        "zero_one_free_numbers" => length(zero_one_free),
        "root_free_numbers" => length(root_free),
        "root_free_distinct_digit_numbers" => sort!(collect(root_free_distinct)),
        "root_free_chart_states" => root_free_states,
        "elapsed_seconds" => time()-start,
    )
    open(joinpath(output, "anagram_metadata.toml"), "w") do io
        TOML.print(io, metadata; sorted=true)
    end
    println(metadata)
    println("distinct-digit numbers: ", sort!(collect(distinct)))
    println("zero/one-free numbers: ", sort!(collect(zero_one_free)))
    println("square-root numbers: ", sort!(collect(squares)))
    println("root-free distinct-digit numbers: ", sort!(collect(root_free_distinct)))
    return metadata
end

if abspath(PROGRAM_FILE) == (@__FILE__)
    run_anagram_experiments(isempty(ARGS) ? 12 : parse(Int, first(ARGS)))
end
