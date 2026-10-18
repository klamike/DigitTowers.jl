function nearpoint_literal_tower(word, policy)
    exponent = big(last(word))
    for base in Iterators.reverse(word[1:end-1])
        base == exponent == 0 && policy == :forbid && return nothing
        exponent = big(base)^Int(exponent)
    end
    return exponent
end

function nearpoint_literal_oracle(width, radix, metric, padded, policy, allowed)
    states = radix^width
    best, witnesses = nothing, Tuple{Int,Int,Int}[]
    undefined, examined = 0, 0
    for number in (padded ? 0 : radix^(width-1)):states-1
        ds = reverse(digits(number; base=radix, pad=width))
        all(in(allowed), ds) || continue
        examined += 1
        exact = nearpoint_literal_tower(ds, policy)
        if isnothing(exact)
            undefined += 1
            continue
        end
        image = Int(mod(exact, states))
        distance = if metric == :hamming
            count(pair -> first(pair) != last(pair),
                  zip(ds, reverse(digits(image; base=radix, pad=width))))
        else
            min(mod(image-number, states), mod(number-image, states))
        end
        if isnothing(best) || distance < best
            best = distance
            empty!(witnesses)
        end
        distance == best && push!(witnesses, (number, image, distance))
    end
    return (; best, witnesses, undefined, examined)
end

@testset "Modular near points agree with literal integer towers" begin
    for radix in 2:6, width in 1:3, policy in (:forbid, :one),
        padded in (false, true), metric in (:hamming, :circular),
        allowed in (0:radix-1, 1:radix-1)
        oracle = nearpoint_literal_oracle(width, radix, metric, padded, policy, allowed)
        result = DigitTowers.modular_nearpoints(width; radix, metric, padded,
            zero_to_zero=policy, allowed_digits=allowed, limit=1000)
        @test result.minimum_distance == oracle.best
        @test Tuple.(result.minimizers) == oracle.witnesses
        @test result.minimum_count == length(oracle.witnesses)
        @test result.examined == oracle.examined
        @test result.undefined == oracle.undefined
        @test result.defined == result.examined - result.undefined
        @test result.full_evaluations + result.residue_rejections == result.defined
        @test result.search_complete && result.complete
    end
end

@testset "Near point bounds, padding and witnesses" begin
    result = DigitTowers.modular_nearpoints(1; limit=1)
    @test result.minimum_distance == 0
    @test result.minimum_count == 9
    @test result.minimizers == [(number=1, successor=1, distance=0)]
    @test result.search_complete && !result.complete
    @test DigitTowers.modular_nearpoints(1; padded=true).minimum_count == 10
    @test DigitTowers.modular_nearpoints(1; limit=9).complete
    result = DigitTowers.modular_nearpoints(2; allowed_digits=[0], padded=true)
    @test isnothing(result.minimum_distance)
    @test result.undefined == 1
    @test result.minimum_count == 0
    @test result.complete && result.search_complete
    @test isempty(result.minimizers)
    result = DigitTowers.modular_nearpoints(2; allowed_digits=[0])
    @test isnothing(result.minimum_distance)
    @test result.examined == 0 && result.complete
    for width in 2:4, metric in (:hamming, :circular)
        result = DigitTowers.modular_nearpoints(width; metric, limit=100_000)
        @test result.complete && result.search_complete
        @test result.minimum_distance > 0
        for witness in result.minimizers
            ds = reverse(digits(witness.number; base=10, pad=width))
            @test DigitTowers.tower_mod(ds, 10^width) == witness.successor
            @test witness.distance == result.minimum_distance
        end
    end
    expected_circular = [
        (1, [(27, 28)]),
        (2, [(971, 969)]),
        (1, [(6495, 6496), (7650, 7649)]),
        (1, [(67937, 67936), (88735, 88736)]),
    ]
    for (width, (distance, pairs)) in zip(2:5, expected_circular)
        result = DigitTowers.modular_nearpoints(width; metric=:circular)
        @test result.minimum_distance == distance
        @test [(w.number, w.successor) for w in result.minimizers] == pairs
    end
    clean = DigitTowers.modular_nearpoints(3; metric=:circular, allowed_digits=2:9)
    @test clean.minimum_distance == 6
    @test clean.minimizers == [(number=975, successor=969, distance=6)]
    for metric in (:hamming, :circular)
        screened = DigitTowers.modular_nearpoints(5; metric)
        @test screened.residue_rejections > 0
        @test screened.full_evaluations + screened.residue_rejections == screened.defined
        @test screened.residue_rejections <= screened.residue_evaluations <= screened.defined
    end
    @test_throws ArgumentError DigitTowers.modular_nearpoints(0)
    @test_throws ArgumentError DigitTowers.modular_nearpoints(2; radix=1)
    @test_throws ArgumentError DigitTowers.modular_nearpoints(6)
    @test_throws ArgumentError DigitTowers.modular_nearpoints(2; metric=:absolute)
    @test_throws ArgumentError DigitTowers.modular_nearpoints(2; limit=0)
    @test_throws ArgumentError DigitTowers.modular_nearpoints(2; allowed_digits=[])
    @test_throws ArgumentError DigitTowers.modular_nearpoints(2; allowed_digits=[10])
    @test_throws ArgumentError DigitTowers.modular_nearpoints(2; zero_to_zero=:other)
end
