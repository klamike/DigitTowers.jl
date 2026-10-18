solution_keys(result) = [(x.number, x.root, x.exponent, x.blocks) for x in result.solutions]

@testset "Arithmetic and CP backends have the same complete solution sets" begin
    configs = [
        Config(),
        Config(ndigits=3),
        Config(ndigits=6, roots=collect(1:9)),
        Config(ndigits=6, distinct_digits=true),
        Config(ndigits=7, root_digits=1, roots=collect(2:9)),
        Config(ndigits=3, roots=[7], block_widths=[1,2]),
        Config(ndigits=7, roots=[50688], bases=[8], block_widths=[1,6]),
        Config(ndigits=7, roots=[1], root_digits=1, bases=[4],
            block_widths=[2,4], leading_zeros_in_blocks=true),
        Config(ndigits=12, roots=[6], root_digits=1,
            block_widths=[1,2,1,1,1,1,1,1,1,1],
            operators=[:^,:+,:^,:^,:^,:^,:^,:^,:^]),
        Config(ndigits=60, bases=[26], block_widths=vcat([2,2],ones(Int,56))),
        Config(ndigits=35, roots=[6], bases=[136], block_widths=vcat([3,2],ones(Int,30))),
        Config(zero_to_zero=:one),
    ]
    for config in configs
        expected = search(config; method=:cp)
        @test expected.complete
        for method in (:prefix,:direct,:nemo)
            actual = search(config; method)
            @test actual.method == method
            @test actual.complete
            @test solution_keys(actual) == solution_keys(expected)
            @test actual.candidates == expected.candidates
            @test all(x -> verify(x,config),actual.solutions)
        end
    end
end

@testset "Arithmetic avoids CP table limits and preserves enumeration guarantees" begin
    constrained = Config(max_table_rows=1)
    @test_throws ArgumentError search(constrained; method=:cp)
    for method in (:prefix,:direct,:nemo)
        result = search(constrained; method)
        @test result.complete
        @test only(result.solutions).number == 262144
        limited = search(Config(); method, max_solutions=1)
        @test !limited.complete
        @test only(limited.solutions).number == 262144
    end
    @test_throws ArgumentError search(Config(); method=:unknown)
    @test_throws ArgumentError search(Config(); max_solutions=0)
    for (b,a,g) in ((4,2,2),(64,2,6),(81,3,4),(144,12,2))
        @test DigitTowers.primitive_base(b) == (big(a),g)
    end
    S = typemax(Int) - 1
    @test DigitTowers.capped_suffix(BigInt[2,S,S],[:^,:+],S,:forbid) == S
end
