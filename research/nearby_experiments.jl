# Reproduce exact nearest modular tower states. Run from the repository:
# julia --project=. research/nearby_experiments.jl
using DigitTowers
using TOML

function main()
    directory = joinpath(@__DIR__, "results")
    mkpath(directory)
    examples, records = NamedTuple[], NamedTuple[]
    for radix in (2, 3, 5, 6, 8, 10, 12, 16), width in 2:5,
        metric in (:hamming, :circular), digit_rule in (:all, :no_zero_or_one)
        radix^width <= 100_000 || continue
        digit_rule == :no_zero_or_one && radix == 2 && continue
        allowed = digit_rule == :all ? (0:radix-1) : (2:radix-1)
        result = DigitTowers.modular_nearpoints(width; radix, metric,
            allowed_digits=allowed, limit=32)
        @assert result.search_complete
        push!(records, (; radix, width, metric, digit_rule,
            result.minimum_distance, result.minimum_count,
            returned=length(result.minimizers), result.complete,
            result.examined, result.undefined, result.full_evaluations,
            result.residue_evaluations, result.residue_rejections))
        for witness in result.minimizers
            word = reverse(digits(witness.number; base=radix, pad=width))
            @assert tower_mod(word, radix^width) == witness.successor
            push!(examples, (; radix, width, metric, digit_rule,
                number=witness.number, successor=witness.successor,
                word=string(witness.number; base=radix, pad=width),
                image=string(witness.successor; base=radix, pad=width),
                distance=witness.distance))
        end
    end
    open(joinpath(directory, "nearby_searches.tsv"), "w") do io
        println(io, "radix\twidth\tmetric\tdigit_rule\tminimum_distance\tminimum_count\treturned\tcomplete\texamined\tundefined\tfull_evaluations\tresidue_evaluations\tresidue_rejections")
        foreach(row -> println(io, join(values(row), '\t')), records)
    end
    open(joinpath(directory, "nearby_examples.tsv"), "w") do io
        println(io, "radix\twidth\tmetric\tdigit_rule\tnumber\tsuccessor\tword\timage\tdistance")
        foreach(row -> println(io, join(values(row), '\t')), examples)
    end
    open(joinpath(directory, "nearby_metadata.toml"), "w") do io
        TOML.print(io, Dict(
            "definition" => "F(N)=tower(width-padded radix digits of N) mod radix^width",
            "domain" => "all width-digit inputs with nonzero leading digit, selected digit rule, radix^width <= 100000",
            "zero_to_zero" => "forbid",
            "metrics" => ["hamming", "circular"],
            "radices" => [2,3,5,6,8,10,12,16],
            "widths" => [2,3,4,5],
            "witness_limit_per_search" => 32,
            "searches" => length(records),
            "all_minima_exact" => true,
            "sieve" => "cached modulus radix^floor(width/2) supplies a distance lower bound; reject only above incumbent",
            "witnesses" => length(examples),
            "julia_version" => string(VERSION),
        ); sorted=true)
    end
    println("Wrote $(length(records)) exhaustive nearest-state searches and $(length(examples)) verified witnesses.")
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
