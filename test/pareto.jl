# Independent oracle: enumerate every partition/operator string, evaluate it
# literally as a capped BigInt, then discard dominated cost pairs afterward.
function pareto_oracle_partitions(n, width)
    n == 0 && return [Int[]]
    return [[w; tail] for w in 1:min(n, width)
        for tail in pareto_oracle_partitions(n-w, width)]
end

function pareto_oracle_costs(costs)
    unique_costs = Set(costs)
    return Set(p for p in unique_costs if !any(q -> q != p &&
        q[1] <= p[1] && q[2] <= p[2], unique_costs))
end

function pareto_oracle_chart(text, cap, width, addition, padding, policy)
    result = Dict{Int,Vector{Tuple{Int,Int}}}()
    for widths in pareto_oracle_partitions(length(text), width)
        blocks = BigInt[]
        start, valid = 1, true
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
                block = min(BigInt(cap), blocks[i])
                if (mask >> (i-1)) & 1 == 1
                    value = min(BigInt(cap), block+value)
                elseif block == 0 && value == 0 && policy == :forbid
                    defined = false
                    break
                elseif block >= 2 && value >= cap
                    value = BigInt(cap)
                else
                    value = min(BigInt(cap), block^Int(value))
                end
            end
            defined || continue
            costs = get!(result, Int(value), Tuple{Int,Int}[])
            push!(costs, (length(text)-length(widths), count_ones(mask)))
        end
    end
    return Dict(v => pareto_oracle_costs(costs) for (v, costs) in result)
end

function pareto_oracle(number; roots=[2], max_block_width=3,
        max_base_width=max_block_width, allow_addition=true,
        root_digits=0, leading_zeros_in_blocks=false, zero_to_zero=:forbid)
    text = string(number)
    result = Dict{Tuple{Int,Int},Set{Tuple{Int,Int}}}()
    for width in 1:min(max_base_width, length(text)-root_digits-1)
        start = root_digits+1
        !leading_zeros_in_blocks && width > 1 && text[start] == '0' && continue
        base = parse(BigInt, text[start:start+width-1])
        base >= 2 || continue
        for root in roots
            root_digits > 0 && string(root) != text[1:root_digits] && continue
            target = BigInt(number)^root
            value, exponent = big(1), 0
            while value < target
                value *= base
                exponent += 1
            end
            value == target || continue
            chart = pareto_oracle_chart(text[start+width:end], exponent+1,
                max_block_width, allow_addition, leading_zeros_in_blocks, zero_to_zero)
            haskey(chart, exponent) || continue
            result[(root, width)] = Set((j+width-1, a) for (j, a) in chart[exponent])
        end
    end
    return result
end

@testset "Pareto synthesis agrees with independent literal grammar enumeration" begin
    numbers = (16, 25, 27, 81, 256, 512, 729, 1024, 4096, 6561,
        262144, 2097152, 4194304, 8388608, 16777216)
    for n in numbers, addition in (false, true), policy in (:forbid, :one)
        options = (; roots=[2, 3, 6, 7], max_block_width=3,
            allow_addition=addition, zero_to_zero=policy)
        result = DigitTowers.synthesize_frontier(n; options...)
        actual = Dict((g.root, g.base_width) => Set((c.concatenations, c.additions)
            for c in g.certificates) for g in result.frontiers)
        @test result.complete
        @test result.method == :pareto
        @test actual == pareto_oracle(n; options...)
        @test all(verify, result.certificates)
        @test result.states >= result.value_states
        for weights in ((concatenation=1, addition=1),
                (concatenation=7, addition=1), (concatenation=1, addition=9),
                (concatenation=0, addition=1))
            scalar = synthesize(n; options..., cost_weights=weights)
            for certificate in scalar.certificates
                key = (certificate.candidate.root, first(certificate.config.block_widths))
                @test certificate.cost == minimum(weights.concatenation*j +
                    weights.addition*a for (j,a) in actual[key])
            end
        end
    end
    for padding in (false, true), n in (1048576, 20736, 65536)
        options = (; roots=[1, 2, 6], root_digits=1,
            leading_zeros_in_blocks=padding)
        result = DigitTowers.synthesize_frontier(n; options...)
        @test Dict((g.root, g.base_width) => Set((c.concatenations, c.additions)
            for c in g.certificates) for g in result.frontiers) ==
            pareto_oracle(n; options...)
    end
end

@testset "Pareto charts preserve all nondominated labels under saturation" begin
    for text in ("00", "100", "2001", "0100", "10200", "001101", "10000001"),
            cap in (2, 5, 16), width in (1, 2, 3), addition in (false, true),
            padding in (false, true), policy in (:forbid, :one)
        chart, _, _ = DigitTowers.pareto_chart(text, 1, cap, width, addition,
            padding, policy, 1_000_000)
        @test Dict(v => Set((p.concatenations, p.additions) for p in frontier)
            for (v,frontier) in chart) ==
            pareto_oracle_chart(text, cap, width, addition, padding, policy)
    end
end

@testset "Pareto frontier conventions and explicit resource guards" begin
    r = DigitTowers.synthesize_frontier(262144)
    x = only(r.certificates)
    @test (x.concatenations, x.additions, x.cost) == (0, 0, 0)
    @test expression(x) == expression(x.candidate, x.config)
    @test DigitTowers.synthesize_frontier(1024; root_digits=1).certificates == []
    @test_throws ArgumentError DigitTowers.synthesize_frontier(1)
    @test_throws ArgumentError DigitTowers.synthesize_frontier(256; roots=[])
    @test_throws ArgumentError DigitTowers.synthesize_frontier(256; roots=[0])
    @test_throws ArgumentError DigitTowers.synthesize_frontier(256; root_digits=2)
    @test_throws ArgumentError DigitTowers.synthesize_frontier(256; max_block_width=0)
    @test_throws ArgumentError DigitTowers.synthesize_frontier(256; max_base_width=4)
    @test_throws ArgumentError DigitTowers.synthesize_frontier(262144; max_states=1)
    @test_throws ArgumentError DigitTowers.synthesize_frontier(262144; max_exponent=3)
    @test_throws ArgumentError DigitTowers.synthesize_frontier(256; zero_to_zero=:undefined)
end

@testset "Tradeoffs that scalar weighted objectives cannot discover" begin
    r = DigitTowers.synthesize_frontier(big(2199023255552); roots=[6], max_base_width=1)
    @test [(c.concatenations, c.additions) for c in r.certificates] ==
        [(2, 8), (4, 7), (5, 6)]
    @test all(verify, r.certificates)
    @test all(c -> c.candidate.exponent == 246, r.certificates)
    # For (4,7) to beat (2,8), w_join/w_plus <= 1/2; to beat
    # (5,6), the same ratio must be >= 1. Neither zero weight rescues it.
    @test (8-7)//(4-2) < (7-6)//(5-4)
    for weights in ((concatenation=0, addition=1),
            (concatenation=1, addition=0), (concatenation=1, addition=1),
            (concatenation=1, addition=2), (concatenation=2, addition=1))
        scalar = only(synthesize(big(2199023255552); roots=[6],
            max_base_width=1, allow_addition=true, cost_weights=weights).certificates)
        @test (scalar.concatenations, scalar.additions) != (4, 7)
    end
    first_run = DigitTowers.synthesize_frontier(4294967296; roots=[9], max_base_width=1)
    second_run = DigitTowers.synthesize_frontier(4294967296; roots=[9], max_base_width=1)
    @test [(c.concatenations, c.additions) for c in first_run.certificates] == [(2,6),(3,5)]
    @test expression.(first_run.certificates) == expression.(second_run.certificates)
end
