"""
    SynthesisCertificate

A minimum-cost expression for one fixed `(root, outer-base width)` in a
[`synthesize`](@ref) call. `candidate` and `config` are ordinary DigitTowers
objects, so the result can also be checked or searched with the existing
backends. `cost` is the configured weighted sum of `concatenations` and
`additions`; each deleted digit boundary counts as one concatenation.
"""
struct SynthesisCertificate
    candidate::Candidate
    config::Config
    cost::Int
    concatenations::Int
    additions::Int
end

expression(x::SynthesisCertificate) = expression(x.candidate, x.config)
verify(x::SynthesisCertificate) = verify(x.candidate, x.config)

struct SynthesisParse
    cost::Int
    concatenations::Int
    additions::Int
    widths::Vector{Int}
    operators::Vector{Symbol}
    text::String
end

function synthesis_better(a::SynthesisParse, b::SynthesisParse)
    # A stable tie break makes witnesses reproducible without claiming every
    # optimum is returned. Only the scalar cost is the optimization objective.
    return (a.cost, a.additions, a.concatenations, a.text) <
           (b.cost, b.additions, b.concatenations, b.text)
end

function synthesis_chart(text, first_position, cap, max_width, addition,
        leading_zeros, policy, weights, state_budget)
    last_position = lastindex(text)
    chart = [Dict{Int,SynthesisParse}() for _ in first_position:last_position]
    states = 0
    for i in last_position:-1:first_position
        cell = chart[i-first_position+1]
        value = big(0)
        for width in 1:min(max_width, last_position-i+1)
            !leading_zeros && width > 1 && text[i] == '0' && break
            j = i + width - 1
            value = 10value + Int(text[j]-'0')
            block = Int(min(value, cap))
            block_text = text[i:j]
            concatenations = width-1
            block_cost = Base.checked_mul(weights.concatenation, concatenations)
            proposals = Pair{Int,SynthesisParse}[]
            if j == last_position
                push!(proposals, block => SynthesisParse(block_cost,
                    concatenations, 0, [width], Symbol[], block_text))
            else
                for (tail_value, tail) in chart[j-first_position+2]
                    for op in (addition ? (:^, :+) : (:^,))
                        result = op == :^ ? capped_power(block, tail_value, cap, policy) :
                            (block >= cap-tail_value ? cap : block+tail_value)
                        isnothing(result) && continue
                        extra = op == :+ ? weights.addition : 0
                        cost = Base.checked_add(Base.checked_add(block_cost, tail.cost), extra)
                        parse = SynthesisParse(cost,
                            concatenations+tail.concatenations,
                            (op == :+) + tail.additions,
                            [width; tail.widths], [op; tail.operators],
                            "(" * block_text * string(op) * tail.text * ")")
                        push!(proposals, result => parse)
                    end
                end
            end
            for (result, parse) in proposals
                if !haskey(cell, result)
                    states += 1
                    states <= state_budget || throw(ArgumentError(
                        "synthesis chart exceeds max_states; narrow the grammar or increase the limit"))
                    cell[result] = parse
                elseif synthesis_better(parse, cell[result])
                    cell[result] = parse
                end
            end
        end
    end
    return first(chart), states
end

"""
    synthesize(number; roots=[2], max_block_width=3,
               max_base_width=max_block_width, allow_addition=false,
               root_digits=0, cost_weights=(concatenation=1, addition=1),
               leading_zeros_in_blocks=false, zero_to_zero=:forbid,
               max_states=1_000_000, max_exponent=1_000_000)

Find the cheapest way to turn the decimal digits of a fixed positive integer
into `root_r(b^suffix) == number`, preserving their order. The grammar permits
contiguous blocks of at most `max_block_width` digits and right-associated
`^` (optionally also `+`) inside the exponent. The outer operation is always
`^`. The first `root_digits` digits, if any, specify and consume the root order.
`max_base_width` can separately restrict the outer base; it cannot exceed
`max_block_width` or 18. An outer base must be at least 2.

The objective is `cost_weights.concatenation * (deleted digit boundaries) +
cost_weights.addition * (plus signs)`. Weights must be nonnegative integers.
One certificate is returned per feasible `(root, outer-base width)`, sorted by
cost, root, and base width. Equal-cost expressions use a deterministic tie
break; alternatives with equal cost are not enumerated.

Return `(; certificates, complete=true, targets, states, method=:synthesis)`.
`targets` counts arithmetically possible `(root, base width)` pairs and
`states` counts stored suffix-chart states; root orders share a chart for
each outer-base width. Resource limits
throw an error, so a returned result is complete for the specified finite
grammar. State merging is exact, including powers above a zero or one and
the selected `0^0` policy. This is grammar synthesis, not an unbounded claim
about arbitrary expressions or arbitrary parentheses.

# Examples

```julia
x = first(synthesize(262144).certificates)
@assert x.cost == 0
@assert verify(x)

y = only(synthesize(256; roots=[7], max_base_width=1).certificates)
@assert y.candidate.blocks == [2, 56]
```
"""
function synthesize(number::Integer; roots=[2], max_block_width::Int=3,
        max_base_width::Int=max_block_width, allow_addition::Bool=false,
        root_digits::Int=0, cost_weights=(concatenation=1, addition=1),
        leading_zeros_in_blocks::Bool=false, zero_to_zero::Symbol=:forbid,
        max_states::Int=1_000_000, max_exponent::Int=1_000_000)
    number >= 10 || throw(ArgumentError("number must have at least two decimal digits"))
    text = string(number)
    n = length(text)
    0 <= root_digits <= n-2 || throw(ArgumentError("invalid root_digits"))
    max_block_width >= 1 || throw(ArgumentError("max_block_width must be positive"))
    1 <= max_base_width <= min(max_block_width, 18) || throw(ArgumentError(
        "max_base_width must be positive, at most max_block_width, and at most 18"))
    max_states >= 1 || throw(ArgumentError("max_states must be positive"))
    1 <= max_exponent < typemax(Int) || throw(ArgumentError("invalid max_exponent"))
    zero_to_zero in (:forbid, :one) || throw(ArgumentError("invalid zero_to_zero policy"))
    keys(cost_weights) == (:concatenation, :addition) || throw(ArgumentError(
        "cost_weights must be (concatenation=..., addition=...)"))
    all(x -> x isa Integer && 0 <= x <= typemax(Int), values(cost_weights)) ||
        throw(ArgumentError("cost weights must be nonnegative Int-sized integers"))
    weights = (concatenation=Int(cost_weights.concatenation), addition=Int(cost_weights.addition))
    root_values = sort!(unique(Int[x for x in roots]))
    !isempty(root_values) && all(>(0), root_values) || throw(ArgumentError(
        "roots must be nonempty positive Int-sized integers"))
    maximum(root_values) < 2^52 || throw(ArgumentError("root orders must be below 2^52"))
    if root_digits > 0
        filter!(r -> string(r) == text[1:root_digits], root_values)
    end
    target_number = BigInt(number)
    certificates = SynthesisCertificate[]
    targets = states = 0
    start = root_digits+1
    for width in 1:min(max_base_width, n-root_digits-1)
        !leading_zeros_in_blocks && width > 1 && text[start] == '0' && break
        base = parse(Int, text[start:start+width-1])
        base >= 2 || continue
        primitive, multiplicity = primitive_base(base)
        power_index, power = ceil_log_power(target_number, primitive)
        power == target_number || continue
        root_targets = Tuple{Int,Int}[]
        for root in root_values
            numerator = BigInt(root)*power_index
            numerator % multiplicity == 0 || continue
            exponent_big = numerator ÷ multiplicity
            exponent_big <= max_exponent || throw(ArgumentError(
                "required exponent exceeds max_exponent; increase the limit"))
            push!(root_targets, (root, Int(exponent_big)))
        end
        isempty(root_targets) && continue
        targets += length(root_targets)
        # A single quotient retaining every exponent up to the largest target
        # answers all root orders. No state at a smaller target is saturated.
        cap = maximum(last, root_targets)+1
        chart, count = synthesis_chart(text, start+width, cap,
            max_block_width, allow_addition, leading_zeros_in_blocks,
            zero_to_zero, weights, max_states-states)
        states += count
        for (root, exponent) in root_targets
            haskey(chart, exponent) || continue
            parse = chart[exponent]
            widths = [width; parse.widths]
            config = Config(ndigits=n, roots=[root], root_digits=root_digits,
                block_widths=widths, operators=[:^; parse.operators],
                bases=[base], leading_zeros_in_blocks=leading_zeros_in_blocks,
                zero_to_zero=zero_to_zero)
            digits, blocks = prefix_blocks(target_number, config, widths)
            candidate = Candidate(copy(target_number), root, exponent, digits, blocks)
            concatenations = width-1+parse.concatenations
            cost = Base.checked_add(parse.cost,
                Base.checked_mul(width-1, weights.concatenation))
            certificate = SynthesisCertificate(candidate, config, cost,
                concatenations, parse.additions)
            verify(certificate) || error("synthesized witness failed exact verification")
            push!(certificates, certificate)
        end
    end
    sort!(certificates; by=x -> (x.cost, x.candidate.root, first(x.config.block_widths)))
    return (; certificates, complete=true, targets, states, method=:synthesis)
end
