using Test
using DigitTowers
import Nemo # exercise the optional extension in the package test environment

# These sets were independently obtained both by literal enumeration of every
# integer 10 <= N < 10^6 and by enumerating exact powers of the leading digit.
const STRICT_EXPECTED = Dict(
    2 => BigInt[],
    3 => BigInt[],
    4 => BigInt[],
    5 => BigInt[],
    6 => BigInt[262144],
)

function exact_suffix(blocks, ops, policy)
    value = BigInt(last(blocks))
    for i in length(blocks)-1:-1:2
        base = BigInt(blocks[i])
        if ops[i] == :+
            value = base + value
        elseif iszero(base) && iszero(value) && policy == :forbid
            return nothing
        else
            value = base^Int(value)
        end
    end
    return value
end

include("prefix.jl")

@testset "Strict square-root puzzle: complete searches" begin
    for n in 2:6
        result = search(Config(ndigits=n))
        @test result.complete
        @test [x.number for x in result.solutions] == STRICT_EXPECTED[n]
        @test all(x -> verify(x, Config(ndigits=n)), result.solutions)
    end
    for n in 2:6
        config = Config(ndigits=n, allowed_digits=collect(1:9))
        result = search(config)
        @test result.complete
        @test [x.number for x in result.solutions] == STRICT_EXPECTED[n]
        @test all(x -> 0 ∉ x.digits && verify(x, config), result.solutions)
    end
    original = only(search(Config()).solutions)
    @test original.root == 2
    @test original.exponent == 36
    @test original.number == big(2)^18
end

@testset "Configurable transcript grammars" begin
    grouped = Config(ndigits=3, roots=[7], block_widths=[1, 2])
    result = search(grouped)
    @test result.complete
    @test [x.number for x in result.solutions] == BigInt[256]
    x = only(result.solutions)
    @test x.blocks == BigInt[2, 56]
    @test x.exponent == 56
    @test verify(x, grouped)
    @test x.number^7 == big(2)^56

    blocked = Config(
        ndigits=20,
        roots=[2],
        block_widths=[7, 1, 7, 1, 4],
        bases=[3162278],
    )
    result = search(blocked)
    @test result.complete
    @test [x.number for x in result.solutions] == BigInt[31622786796633508952]
    x = only(result.solutions)
    @test x.blocks == BigInt[3162278, 6, 7966335, 0, 8952]
    @test x.exponent == 6
    @test x.number == big(3162278)^3
    @test verify(x, blocked)

    final = Config(
        ndigits=12,
        roots=[6],
        root_digits=1,
        block_widths=[1, 2, 1, 1, 1, 1, 1, 1, 1, 1],
        operators=[:^, :+, :^, :^, :^, :^, :^, :^, :^],
        bases=[7],
    )
    result = search(final)
    @test result.complete
    @test [x.number for x in result.solutions] == BigInt[678223072849]
    x = only(result.solutions)
    @test x.root == 6
    @test x.exponent == 84
    @test x.blocks == BigInt[7, 82, 2, 3, 0, 7, 2, 8, 4, 9]
    @test x.number == big(7)^14
    @test verify(x, final)
end

@testset "Saturation preserves exact integer semantics" begin
    # Include values above S, so the check tests the actual quotient map
    # a -> min(a,S), not only unsaturated operands.
    for policy in (:forbid, :one), S in 2:18, a in 0:14, e in 0:12
        actual = DigitTowers.capped_power(min(a, S), min(e, S), S, policy)
        if a == 0 && e == 0 && policy == :forbid
            @test actual === nothing
        else
            expected = Int(min(BigInt(S), BigInt(a)^e))
            @test actual == expected
        end
    end

    # Exhaust short right-associated expressions with mixed + and ^ against
    # direct BigInt evaluation. Their largest exact exponent is only 27.
    for policy in (:forbid, :one), S in (2, 5, 12), a in 0:3, b in 0:3, c in 0:3,
        op1 in (:^, :+), op2 in (:^, :+)
        blocks = BigInt[2, a, b, c]
        ops = [:^, op1, op2]
        exact = exact_suffix(blocks, ops, policy)
        actual = DigitTowers.capped_suffix(blocks, ops, S, policy)
        expected = isnothing(exact) ? nothing : Int(min(BigInt(S), exact))
        @test actual == expected
    end
end

@testset "Undefined powers propagate through blockers" begin
    blocks = BigInt[2, 1, 0, 0] # suffix = 1^(0^0)
    ops = [:^, :^, :^]
    @test DigitTowers.capped_suffix(blocks, ops, 10, :forbid) === nothing
    @test DigitTowers.capped_suffix(blocks, ops, 10, :one) == 1
    @test DigitTowers.capped_power(0, 0, 10, :forbid) === nothing
    @test DigitTowers.capped_power(0, 0, 10, :one) == 1
end

@testset "Candidate table admits fractional powers of the outer base" begin
    # N = 2^23 = 8^(23/3), so searching only integer powers of 8 loses it.
    # Inspect exact preprocessing before solving the two-block grammar.
    config = Config(ndigits=7, roots=[50688], bases=[8])
    widths, _ = DigitTowers.grammar(config)
    candidates = DigitTowers.candidate_table(config, widths)
    matching = filter(x -> x.number == 8388608, candidates)
    @test length(matching) == 1
    x = only(matching)
    @test x.root == 50688
    @test x.exponent == 388608
    @test x.number == big(2)^23
    @test x.number^x.root == big(8)^x.exponent
    @test DigitTowers.primitive_base(8) == (big(2), 3)
    grouped = Config(ndigits=7, roots=[50688], bases=[8], block_widths=[1, 6])
    result = search(grouped)
    @test result.complete
    @test [x.number for x in result.solutions] == BigInt[8388608]
    @test verify(only(result.solutions), grouped)
end

@testset "Configured zero padding preserves the digit grammar" begin
    config = Config(ndigits=7, roots=[1], root_digits=1, bases=[4],
        block_widths=[2, 4], leading_zeros_in_blocks=true)
    widths, _ = DigitTowers.grammar(config)
    x = only(DigitTowers.candidate_table(config, widths))
    @test x.number == 1048576
    @test x.blocks == BigInt[4, 8576]
    @test expression(x, config) == "root_1((04^8576)) = 1048576"
    # This is a necessary-condition candidate, not a valid complete expression.
    @test !verify(x, config)
end

@testset "Distinct-digit extension and pigeonhole bound" begin
    for n in 2:10
        result = search(Config(ndigits=n, distinct_digits=true))
        @test result.complete
        @test isempty(result.solutions)
    end
    result = search(Config(ndigits=11, distinct_digits=true))
    @test result.complete
    @test result.candidates == 0
    @test isempty(result.solutions)
end

include("backends.jl")

include("sweep.jl")
