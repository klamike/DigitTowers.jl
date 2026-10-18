# Two parses with the same saturated value are indistinguishable to every
# prefix. Keep their additive costs as an antichain instead of scalarizing.
function pareto_insert!(frontier::Vector{SynthesisParse}, parse::SynthesisParse)
    for (i, old) in pairs(frontier)
        if old.concatenations <= parse.concatenations && old.additions <= parse.additions
            if old.concatenations == parse.concatenations && old.additions == parse.additions &&
                    parse.text < old.text
                frontier[i] = parse
            end
            return 0
        end
    end
    before = length(frontier)
    filter!(old -> !(parse.concatenations <= old.concatenations &&
        parse.additions <= old.additions), frontier)
    push!(frontier, parse)
    sort!(frontier; by=x -> (x.concatenations, x.additions, x.text))
    return length(frontier)-before
end

function pareto_chart(text, first_position, cap, max_width, addition,
        leading_zeros, policy, label_budget)
    last_position = lastindex(text)
    chart = [Dict{Int,Vector{SynthesisParse}}() for _ in first_position:last_position]
    labels = value_states = 0
    for i in last_position:-1:first_position
        cell = chart[i-first_position+1]
        value = big(0)
        for width in 1:min(max_width, last_position-i+1)
            !leading_zeros && width > 1 && text[i] == '0' && break
            j = i+width-1
            value = 10value + Int(text[j]-'0')
            block, block_text = Int(min(value, cap)), text[i:j]
            concatenations = width-1
            proposals = Pair{Int,SynthesisParse}[]
            if j == last_position
                push!(proposals, block => SynthesisParse(concatenations,
                    concatenations, 0, [width], Symbol[], block_text))
            else
                tails = chart[j-first_position+2]
                for tail_value in sort!(collect(keys(tails)))
                    for op in (addition ? (:^, :+) : (:^,))
                        result = op == :^ ? capped_power(block, tail_value, cap, policy) :
                            (block >= cap-tail_value ? cap : block+tail_value)
                        isnothing(result) && continue
                        for tail in tails[tail_value]
                            joins = concatenations+tail.concatenations
                            pluses = (op == :+)+tail.additions
                            parse = SynthesisParse(Base.checked_add(joins, pluses),
                                joins, pluses, [width; tail.widths], [op; tail.operators],
                                "(" * block_text * string(op) * tail.text * ")")
                            push!(proposals, result => parse)
                        end
                    end
                end
            end
            for (result, parse) in proposals
                if !haskey(cell, result)
                    value_states += 1
                    cell[result] = SynthesisParse[]
                end
                labels += pareto_insert!(cell[result], parse)
                labels <= label_budget || throw(ArgumentError(
                    "Pareto synthesis chart exceeds max_states; narrow the grammar or increase the limit"))
            end
        end
    end
    return first(chart), labels, value_states
end

"""
    synthesize_frontier(number; roots=[2], max_block_width=3,
                        max_base_width=max_block_width, allow_addition=true,
                        root_digits=0, leading_zeros_in_blocks=false,
                        zero_to_zero=:forbid, max_states=1_000_000,
                        max_exponent=1_000_000)

Find every nondominated `(concatenations, additions)` cost for each feasible
`(root, outer-base width)` in the finite grammar of [`synthesize`](@ref).
A cost is dominated when another expression uses no more of either operation
and strictly less of at least one. Return one deterministic witness per cost;
expressions with the same cost pair are not exhaustively enumerated.

The result contains `certificates` (a flat vector of [`SynthesisCertificate`](@ref)),
`frontiers` (groups with `root`, `base_width`, and `certificates` fields),
`complete=true`, `targets`, `states`, `value_states`, and `method=:pareto`.
Each certificate's scalar `cost` is the sum of its two coordinates; both
coordinates, rather than their sum, determine frontier membership. Frontiers
are separate for each root/base-width pair, even when one pair's costs would
dominate another pair's costs.

The chart merges equivalent capped suffix values and retains an antichain of
additive cost labels per value. Root orders share a chart for each base width.
`states` counts retained labels, while `value_states` counts semantic
`(position, value)` cells. `max_states` guards label storage across all charts;
exceeding a resource guard throws an error rather than returning a partial
frontier. The returned frontier is complete for the specified grammar.
"""
function synthesize_frontier(number::Integer; roots=[2], max_block_width::Int=3,
        max_base_width::Int=max_block_width, allow_addition::Bool=true,
        root_digits::Int=0, leading_zeros_in_blocks::Bool=false,
        zero_to_zero::Symbol=:forbid, max_states::Int=1_000_000,
        max_exponent::Int=1_000_000)
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
    root_values = sort!(unique(Int[x for x in roots]))
    !isempty(root_values) && all(>(0), root_values) || throw(ArgumentError(
        "roots must be nonempty positive Int-sized integers"))
    maximum(root_values) < 2^52 || throw(ArgumentError("root orders must be below 2^52"))
    root_digits > 0 && filter!(r -> string(r) == text[1:root_digits], root_values)
    target_number = BigInt(number)
    certificates = SynthesisCertificate[]
    frontiers = NamedTuple{(:root, :base_width, :certificates),
        Tuple{Int,Int,Vector{SynthesisCertificate}}}[]
    targets = states = value_states = 0
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
        cap = maximum(last, root_targets)+1
        chart, count, cells = pareto_chart(text, start+width, cap,
            max_block_width, allow_addition, leading_zeros_in_blocks,
            zero_to_zero, max_states-states)
        states += count
        value_states += cells
        for (root, exponent) in root_targets
            haskey(chart, exponent) || continue
            group = SynthesisCertificate[]
            for parse in chart[exponent]
                widths = [width; parse.widths]
                config = Config(ndigits=n, roots=[root], root_digits=root_digits,
                    block_widths=widths, operators=[:^; parse.operators],
                    bases=[base], leading_zeros_in_blocks=leading_zeros_in_blocks,
                    zero_to_zero=zero_to_zero)
                digits, blocks = prefix_blocks(target_number, config, widths)
                candidate = Candidate(copy(target_number), root, exponent, digits, blocks)
                joins = width-1+parse.concatenations
                certificate = SynthesisCertificate(candidate, config,
                    Base.checked_add(joins, parse.additions), joins, parse.additions)
                verify(certificate) || error("Pareto witness failed exact verification")
                push!(group, certificate)
            end
            sort!(group; by=x -> (x.concatenations, x.additions, expression(x)))
            push!(frontiers, (; root, base_width=width, certificates=group))
            append!(certificates, group)
        end
    end
    sort!(frontiers; by=x -> (x.root, x.base_width))
    sort!(certificates; by=x -> (x.candidate.root, first(x.config.block_widths),
        x.concatenations, x.additions, expression(x)))
    return (; certificates, frontiers, complete=true, targets, states, value_states,
        method=:pareto)
end
