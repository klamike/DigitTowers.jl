using Test
using DigitTowers

sweep_answers(xs) = sort!([(x.number, x.root, x.exponent) for x in xs])

@testset "One-pass root derivation" begin
    roots = collect(1:9)
    result = sweep(2:20; roots)
    @test result.complete
    @test result.method == :sweep
    @test sweep_answers(result.solutions) == [(big(262144), 2, 36)]
    @test result.candidates >= length(result.solutions)
    @test result.cap >= 36
    for method in (:prefix, :cp)
        expected = Candidate[]
        for n in 2:20
            config = Config(ndigits=n, roots=roots)
            one = search(config; method)
            @test one.complete
            append!(expected, one.solutions)
        end
        @test sweep_answers(result.solutions) == sweep_answers(expected)
    end
    @test isempty(sweep(2:5).solutions)
    @test sweep_answers(sweep(6:6).solutions) == [(big(262144), 2, 36)]
    @test sweep_answers(sweep(2:20; roots=[2, 2]).solutions) == [(big(262144), 2, 36)]

    limited = sweep(2:20; max_solutions=1)
    @test !limited.complete
    @test limited.status == DigitTowers.MOI.SOLUTION_LIMIT
    @test length(limited.solutions) == 1
end

@testset "Sweep digit domains and consumed roots" begin
    for domain in (collect(1:9), collect(2:9), [2, 6, 1, 4])
        result = sweep(2:20; roots=collect(1:9), allowed_digits=domain)
        expected = Candidate[]
        for n in 2:20
            config = Config(ndigits=n, roots=collect(1:9), allowed_digits=domain)
            one = search(config; method=:prefix)
            @test one.complete
            append!(expected, one.solutions)
        end
        @test result.complete
        @test sweep_answers(result.solutions) == sweep_answers(expected)
    end
    result = sweep(3:20; roots=collect(1:9), root_digits=1)
    expected = Candidate[]
    for n in 3:20
        config = Config(ndigits=n, roots=collect(1:9), root_digits=1)
        one = search(config; method=:prefix)
        @test one.complete
        append!(expected, one.solutions)
    end
    @test result.complete
    @test sweep_answers(result.solutions) == sweep_answers(expected)
    @test isempty(result.solutions)
    @test isempty(sweep(4:8; roots=[2, 3], root_digits=2).solutions)
    @test isempty(sweep(2:1000; distinct_digits=true).solutions)
    @test sweep(2:1000; distinct_digits=true).complete
end

@testset "Sweep zero policy and independent broader bound" begin
    for policy in (:forbid, :one)
        result = sweep(2:20; roots=collect(1:9), zero_to_zero=policy)
        expected = Candidate[]
        for n in 2:20
            config = Config(ndigits=n, roots=collect(1:9), zero_to_zero=policy)
            one = search(config; method=:prefix)
            @test one.complete
            append!(expected, one.solutions)
        end
        @test result.complete
        @test sweep_answers(result.solutions) == sweep_answers(expected)
    end
    # Eager undefined subexpressions remain undefined even behind a one.
    @test DigitTowers.capped_suffix(BigInt[2, 1, 0, 0], [:^, :^, :^], 10, :forbid) === nothing
    @test DigitTowers.capped_suffix(BigInt[2, 1, 0, 0], [:^, :^, :^], 10, :one) == 1
    # Independently confirmed with the Python prime-power/recursive oracle:
    # 1,702 candidate numbers, roots1..1000, lengths2..1000.
    broad = sweep(2:1000; roots=collect(1:1000))
    @test broad.complete
    @test broad.candidates == 1702
    @test sweep_answers(broad.solutions) == [(big(262144), 2, 36)]
end

@testset "Sweep input validation" begin
    @test_throws ArgumentError sweep(1:10)
    @test_throws ArgumentError sweep(2:1)
    @test_throws ArgumentError sweep(2:10; root_digits=1)
    @test_throws ArgumentError sweep(2:10; root_digits=-1)
    @test_throws ArgumentError sweep(2:10; roots=Int[])
    @test_throws ArgumentError sweep(2:10; roots=[0])
    @test_throws ArgumentError sweep(2:10; allowed_digits=Int[])
    @test_throws ArgumentError sweep(2:10; allowed_digits=[10])
    @test_throws ArgumentError sweep(2:10; zero_to_zero=:other)
    @test_throws ArgumentError sweep(2:10; max_solutions=0)
end
