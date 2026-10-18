function prefix_candidate_keys(candidates)
    return [(x.number, x.root, x.exponent, x.digits, x.blocks) for x in candidates]
end

function test_prefix_equivalence(config)
    widths, _ = DigitTowers.grammar(config)
    expected = DigitTowers.candidate_table(config, widths)
    actual = DigitTowers.prefix_candidates(config, widths)
    @test prefix_candidate_keys(actual) == prefix_candidate_keys(expected)
    return actual
end

@testset "Exact ceiling powers certify both integer boundaries" begin
    for a in (2, 3, 9, 10, 257), h in (0, 1, 2, 10, 100, 1000)
        base = BigInt(a)
        power = base^h
        k, number = DigitTowers.ceil_log_power(power, base)
        @test k == h
        @test number == power
        for A in (max(big(1), power - 1), power + 1)
            k, number = DigitTowers.ceil_log_power(A, base)
            @test number == base^k
            @test number >= A
            @test k == 0 || number ÷ base < A
        end
    end
    @test_throws ArgumentError DigitTowers.ceil_log_power(big(0), big(2))
    @test_throws ArgumentError DigitTowers.ceil_log_power(big(2), big(1))
end

@testset "Prefix windows equal exhaustive primitive-power candidates" begin
    for n in 2:100
        test_prefix_equivalence(Config(ndigits=n))
    end
    for n in 2:20
        test_prefix_equivalence(Config(ndigits=n, roots=collect(1:9)))
        test_prefix_equivalence(Config(ndigits=n, allowed_digits=collect(1:9)))
        test_prefix_equivalence(Config(ndigits=n, allowed_digits=collect(2:9)))
    end
    for n in 3:20
        test_prefix_equivalence(Config(ndigits=n, roots=collect(2:9), root_digits=1))
    end
    test_prefix_equivalence(Config(ndigits=8, roots=[2, 2, 7], bases=[8, 8, 2, 4]))
    test_prefix_equivalence(Config(ndigits=6, roots=[2], root_digits=2))
    test_prefix_equivalence(Config(ndigits=11, distinct_digits=true))
    test_prefix_equivalence(Config(ndigits=4, distinct_digits=true, allowed_digits=[2, 3]))

    # Preprocessing retains repeated-digit candidates; AllDifferent belongs
    # to the subsequent search, except for the universal pigeonhole bound.
    repeated = test_prefix_equivalence(Config(ndigits=6, distinct_digits=true))
    @test any(x -> x.number == 262144 && !allunique(x.digits), repeated)
end

@testset "Grouped and zero-padded prefix windows" begin
    configs = [
        Config(ndigits=3, roots=[7], block_widths=[1, 2]),
        Config(ndigits=20, roots=[2], bases=[3162278], block_widths=[7, 1, 7, 1, 4]),
        Config(ndigits=12, roots=[6], root_digits=1, bases=[7],
            block_widths=[1, 2, 1, 1, 1, 1, 1, 1, 1, 1],
            operators=[:^, :+, :^, :^, :^, :^, :^, :^, :^]),
        Config(ndigits=7, roots=[50688], bases=[8], block_widths=[1, 6]),
        Config(ndigits=7, roots=[1], root_digits=1, bases=[4],
            block_widths=[2, 4], leading_zeros_in_blocks=true),
        Config(ndigits=7, roots=collect(1:9), root_digits=1,
            block_widths=[2, 4], leading_zeros_in_blocks=true),
        Config(ndigits=7, roots=[2], bases=[2], block_widths=[1, 2, 4]),
        Config(ndigits=7, roots=[2], bases=[2], block_widths=[1, 2, 4],
            leading_zeros_in_blocks=true),
    ]
    for config in configs
        test_prefix_equivalence(config)
    end
    padded = test_prefix_equivalence(configs[5])
    @test only(padded).number == 1048576
    fractional = test_prefix_equivalence(configs[4])
    @test only(fractional).number == 8388608
    @test only(fractional).exponent == 388608
end

@testset "External roots share one exact prefix window" begin
    calls = Ref(0)
    counting_ceiling = (A, a) -> begin
        calls[] += 1
        DigitTowers.ceil_log_power(A, a)
    end
    config = Config(ndigits=6, bases=[2], roots=collect(1:9))
    widths, _ = DigitTowers.grammar(config)
    candidates = DigitTowers.prefix_candidates(config, widths;
        exponent_ceiling=counting_ceiling)
    @test calls[] == 1
    @test length(candidates) == 9
    @test prefix_candidate_keys(candidates) ==
        prefix_candidate_keys(DigitTowers.candidate_table(config, widths))
end

if Base.get_extension(DigitTowers, :DigitTowersNemoExt) !== nothing
    @testset "Nemo integer logarithms reproduce core prefix windows" begin
        for config in (Config(), Config(ndigits=3, roots=[7], block_widths=[1, 2]),
                Config(ndigits=12, roots=collect(2:9), root_digits=1))
            widths, _ = DigitTowers.grammar(config)
            @test prefix_candidate_keys(DigitTowers.nemo_prefix_candidates(config, widths)) ==
                prefix_candidate_keys(DigitTowers.prefix_candidates(config, widths))
        end
    end
end
