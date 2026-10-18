# This oracle enumerates literal digit partitions and all operator strings.
# Its evaluator uses BigInt exponentiation by squaring and early saturation;
# it does not call the production chart or capped_power implementation.
function synthesis_oracle_power(a, b, cap, policy)
    a == 0 && b == 0 && policy == :forbid && return nothing
    b == 0 && return big(1)
    a == 0 && return big(0)
    a == 1 && return big(1)
    b >= cap && return BigInt(cap)
    result, factor = big(1), BigInt(a)
    exponent = Int(b)
    while exponent > 0
        isodd(exponent) && (result = min(BigInt(cap), result*factor))
        exponent >>= 1
        exponent > 0 && (factor = min(BigInt(cap), factor*factor))
    end
    return min(BigInt(cap), result)
end

function synthesis_partitions(n, width)
    n == 0 && return [Int[]]
    return [[w; tail] for w in 1:min(n, width) for tail in synthesis_partitions(n-w, width)]
end

function synthesis_oracle(number; roots=[2], max_block_width=3,
        max_base_width=max_block_width, allow_addition=false, root_digits=0,
        cost_weights=(concatenation=1, addition=1),
        leading_zeros_in_blocks=false, zero_to_zero=:forbid)
    text = string(number)
    best = Dict{Tuple{Int,Int},Int}()
    for widths in synthesis_partitions(length(text)-root_digits, max_block_width)
        length(widths) >= 2 && first(widths) <= max_base_width || continue
        start = root_digits+1
        blocks = BigInt[]
        valid = true
        for w in widths
            if !leading_zeros_in_blocks && w > 1 && text[start] == '0'
                valid = false
                break
            end
            push!(blocks, parse(BigInt, text[start:start+w-1]))
            start += w
        end
        valid && first(blocks) >= 2 || continue
        suffix_operators = length(blocks)-2
        for root in roots
            root_digits > 0 && string(root) != text[1:root_digits] && continue
            # Compute the exponent target by repeated exact powers of b.
            # This independently handles perfect-power outer bases.
            target = BigInt(number)^root
            value = big(1)
            exponent = 0
            while value < target
                value *= first(blocks)
                exponent += 1
            end
            value == target || continue
            cap = exponent+1
            for mask in 0:(allow_addition ? 2^suffix_operators-1 : 0)
                suffix = min(BigInt(cap), last(blocks))
                defined = true
                for i in length(blocks)-1:-1:2
                    if (mask >> (i-2)) & 1 == 1
                        suffix = min(BigInt(cap), blocks[i]+suffix)
                    else
                        suffix = synthesis_oracle_power(min(BigInt(cap), blocks[i]),
                            suffix, cap, zero_to_zero)
                        if isnothing(suffix)
                            defined = false
                            break
                        end
                    end
                end
                defined && suffix == exponent || continue
                cost = cost_weights.concatenation*(sum(widths)-length(widths)) +
                    cost_weights.addition*count_ones(mask)
                key = (root, first(widths))
                best[key] = min(get(best, key, typemax(Int)), cost)
            end
        end
    end
    return best
end

function synthesis_oracle_chart(text, cap, width, addition, padding, policy)
    result = Dict{Int,Int}()
    for widths in synthesis_partitions(length(text), width)
        blocks = BigInt[]
        start = 1
        valid = true
        for w in widths
            if !padding && w > 1 && text[start] == '0'
                valid = false
                break
            end
            push!(blocks, parse(BigInt, text[start:start+w-1]))
            start += w
        end
        valid || continue
        for mask in 0:(addition ? 2^(length(blocks)-1)-1 : 0)
            value = min(BigInt(cap), last(blocks))
            defined = true
            for i in length(blocks)-1:-1:1
                if (mask >> (i-1)) & 1 == 1
                    value = min(BigInt(cap), blocks[i]+value)
                else
                    value = synthesis_oracle_power(min(BigInt(cap), blocks[i]),
                        value, cap, policy)
                    if isnothing(value)
                        defined = false
                        break
                    end
                end
            end
            defined || continue
            cost = length(text)-length(widths)+count_ones(mask)
            result[Int(value)] = min(get(result, Int(value), typemax(Int)), cost)
        end
    end
    return result
end

@testset "Automatic grammar synthesis" begin
    strict = synthesize(262144)
    @test strict.complete
    @test strict.targets == 1
    @test strict.method == :synthesis
    x = only(strict.certificates)
    @test x.cost == x.concatenations == x.additions == 0
    @test verify(x)
    @test expression(x) == expression(x.candidate, x.config)
    grouped = only(synthesize(256; roots=[7]).certificates)
    @test grouped.cost == grouped.concatenations == 1
    @test grouped.additions == 0
    @test grouped.candidate.blocks == BigInt[2, 56]

    n = big(678223072849)
    @test isempty(synthesize(n; roots=[6], root_digits=1).certificates)
    rewritten = only(synthesize(n; roots=[6], root_digits=1,
        allow_addition=true).certificates)
    @test rewritten.cost == 2
    @test rewritten.concatenations == rewritten.additions == 1
    @test rewritten.candidate.exponent == 84
    @test verify(rewritten)
    expensive_plus = only(synthesize(n; roots=[6], root_digits=1,
        allow_addition=true, cost_weights=(concatenation=1, addition=9)).certificates)
    @test expensive_plus.cost == 10

    # Long suffixes are merged by semantic value rather than enumerating all
    # partitions. This 60-digit witness has 2^57 possible suffix partitions
    # before imposing max_block_width.
    long_number = parse(BigInt,
        "268460636031393932323010374318061912785738337881638804914176")
    long = synthesize(long_number; max_block_width=3)
    @test long.complete
    @test length(long.certificates) == 1
    @test only(long.certificates).cost == 2
    @test verify(only(long.certificates))
    @test long.states < 1000
    simplified = only(synthesize(big"31622786796633508952";
        max_block_width=7).certificates)
    @test simplified.cost == 12
    @test simplified.config.block_widths == [7, 1, 7, 1, 1, 1, 1, 1]
    @test verify(simplified)
end

@testset "Synthesis agrees with exhaustive partition/operator enumeration" begin
    numbers = [16, 25, 27, 81, 256, 512, 729, 1024, 4096, 6561, 262144,
        2097152, 4194304, 8388608, 16777216]
    for n in numbers, addition in (false, true), policy in (:forbid, :one),
            weights in ((concatenation=1, addition=1), (concatenation=0, addition=3))
        options = (; roots=[2, 3, 7], max_block_width=3,
            allow_addition=addition, zero_to_zero=policy, cost_weights=weights)
        result = synthesize(n; options...)
        actual = Dict((c.candidate.root, first(c.config.block_widths)) => c.cost
            for c in result.certificates)
        @test actual == synthesis_oracle(n; options...)
        @test all(verify, result.certificates)
    end
    for padding in (false, true), n in (1048576, 20736, 65536)
        options = (; roots=[1, 2, 6], root_digits=1,
            leading_zeros_in_blocks=padding, allow_addition=true)
        result = synthesize(n; options...)
        @test Dict((c.candidate.root, first(c.config.block_widths)) => c.cost
            for c in result.certificates) == synthesis_oracle(n; options...)
    end
end

@testset "Chart states preserve zeros, ones, overflow, and undefined powers" begin
    for text in ("00", "100", "2001", "0100", "10200", "001101", "10000001"),
            cap in (2, 5, 16), width in (1, 2, 3), addition in (false, true),
            padding in (false, true), policy in (:forbid, :one)
        chart, _ = DigitTowers.synthesis_chart(text, 1, cap, width, addition,
            padding, policy, (concatenation=1, addition=1), 1_000_000)
        @test Dict(v => p.cost for (v,p) in chart) ==
            synthesis_oracle_chart(text, cap, width, addition, padding, policy)
    end
end

@testset "Synthesis rejects invalid grammars and explicit resource overruns" begin
    @test_throws ArgumentError synthesize(1)
    @test_throws ArgumentError synthesize(256; roots=[])
    @test_throws ArgumentError synthesize(256; roots=[0])
    @test_throws ArgumentError synthesize(256; root_digits=2)
    @test_throws ArgumentError synthesize(256; max_block_width=0)
    @test_throws ArgumentError synthesize(256; max_base_width=4)
    @test_throws ArgumentError synthesize(256; cost_weights=(concatenation=-1, addition=1))
    @test_throws ArgumentError synthesize(256; cost_weights=(concatenation=0.5, addition=1))
    @test_throws ArgumentError synthesize(262144; max_states=1)
    @test_throws ArgumentError synthesize(262144; max_exponent=3)
    @test_throws ArgumentError synthesize(256; zero_to_zero=:undefined)
    @test isempty(synthesize(1024; roots=[2], root_digits=1).certificates)
end
