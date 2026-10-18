"""
    AnagramCertificate

A digit-reordering witness for [`anagram_towers`](@ref). `number` keeps its
ordinary decimal value; `digits` records a permutation used as the tower.
`root` is external and `exponent` is the suffix value. `moves` counts positions
whose digit differs from the original numeral, rather than transpositions.
The chosen `zero_to_zero` convention belongs to the certificate.
"""
struct AnagramCertificate
    number::BigInt
    root::Int
    exponent::Int
    digits::Vector{Int}
    moves::Int
    zero_to_zero::Symbol
end

function verify(x::AnagramCertificate)
    x.number >= 10 && x.root >= 1 && 1 <= x.exponent < typemax(Int) || return false
    x.zero_to_zero in (:forbid, :one) || return false
    original = Int[c-'0' for c in string(x.number)]
    length(original) == length(x.digits) && first(x.digits) >= 2 || return false
    all(d -> 0 <= d <= 9, x.digits) || return false
    sort(original) == sort(x.digits) || return false
    x.moves == count(i -> original[i] != x.digits[i], eachindex(original)) || return false
    primitive, multiplicity = primitive_base(first(x.digits))
    index, power = ceil_log_power(x.number, primitive)
    power == x.number || return false
    BigInt(multiplicity)*x.exponent == BigInt(x.root)*index || return false
    return capped_suffix(x.digits, fill(:^, length(x.digits)-1),
        x.exponent+1, x.zero_to_zero) == x.exponent
end

function expression(x::AnagramCertificate)
    result = string(last(x.digits))
    for i in length(x.digits)-1:-1:1
        result = "(" * string(x.digits[i]) * "^" * result * ")"
    end
    return "root_$(x.root)($result) = $(x.number)"
end

struct AnagramParse
    moves::Int
    digits::Vector{Int}
end

function anagram_better(a::AnagramParse, b::AnagramParse)
    return a.moves < b.moves || (a.moves == b.moves && isless(a.digits, b.digits))
end

function anagram_chart(counts::NTuple{10,Int}, original, cap, policy, budget)
    charts = Dict{NTuple{10,Int},Dict{Int,AnagramParse}}()
    states = 0
    function visit(counts)
        haskey(charts, counts) && return charts[counts]
        size = sum(counts)
        position = length(original)-size+1
        cell = Dict{Int,AnagramParse}()
        for digit in 0:9
            counts[digit+1] > 0 || continue
            if size == 1
                proposals = (min(digit, cap) => AnagramParse(
                    digit != original[position], [digit]),)
            else
                remaining = Base.setindex(counts, counts[digit+1]-1, digit+1)
                tail = visit(remaining)
                proposals = Pair{Int,AnagramParse}[]
                for (value, parse) in tail
                    result = capped_power(min(digit, cap), value, cap, policy)
                    isnothing(result) && continue
                    push!(proposals, result => AnagramParse(
                        (digit != original[position])+parse.moves, [digit; parse.digits]))
                end
            end
            for (value, parse) in proposals
                if !haskey(cell, value)
                    states += 1
                    states <= budget || throw(ArgumentError(
                        "anagram chart exceeds max_states; increase the limit"))
                    cell[value] = parse
                elseif anagram_better(parse, cell[value])
                    cell[value] = parse
                end
            end
        end
        charts[counts] = cell
        return cell
    end
    result = visit(counts)
    return result, states
end

"""
    anagram_towers(number; roots=[2], zero_to_zero=:forbid,
                   max_states=1_000_000, max_exponent=1_000_000)

Reorder the decimal digits of a fixed integer `number >= 10` into a pure,
right-associated power tower whose external `root` gives that original
number. Each digit is used exactly once, with no concatenation. A leading
base must be at least two. Return one [`AnagramCertificate`](@ref) for each
feasible `(root, leading base)`, minimizing the number of changed digit
positions; lexicographic order breaks ties reproducibly. This counts changed
positions, not the number of swaps.

The exact dynamic program merges equal `(remaining digit counts, capped
suffix value)` states. Repeated digits never create duplicate branches, and
all root orders for one leading base share a chart. The arithmetic identity
`number = a^h`, `base = a^g` forces the target suffix to be `root*h/g`.
Saturation above the largest target preserves zero, one, and undefined
`0^0`, including undefined expressions hidden beneath a one.

Return `(; certificates, complete=true, targets, states, method=:anagrams)`.
`states` counts stored semantic chart states across leading bases; `targets`
counts arithmetically possible `(root, base)` pairs. Exceeding either resource
limit throws an error, so a returned result is complete for the finite digit
multiset and supplied root orders. The algorithm avoids enumerating all
permutations but its count-vector lattice can still grow exponentially.

# Examples

```julia
result = anagram_towers(262144)
@assert all(verify, result.certificates)
@assert minimum(x.moves for x in result.certificates) == 0
```
"""
function anagram_towers(number::Integer; roots=[2], zero_to_zero::Symbol=:forbid,
        max_states::Int=1_000_000, max_exponent::Int=1_000_000)
    number >= 10 || throw(ArgumentError("number must have at least two decimal digits"))
    zero_to_zero in (:forbid, :one) || throw(ArgumentError("invalid zero_to_zero policy"))
    max_states >= 1 || throw(ArgumentError("max_states must be positive"))
    1 <= max_exponent < typemax(Int) || throw(ArgumentError("invalid max_exponent"))
    root_values = sort!(unique(Int[x for x in roots]))
    !isempty(root_values) && all(>(0), root_values) || throw(ArgumentError(
        "roots must be nonempty positive Int-sized integers"))
    target = BigInt(number)
    original = Int[c-'0' for c in string(target)]
    counts = ntuple(d -> count(==(d-1), original), 10)
    certificates = AnagramCertificate[]
    states = targets = 0
    for base in 2:9
        counts[base+1] > 0 || continue
        primitive, multiplicity = primitive_base(base)
        index, power = ceil_log_power(target, primitive)
        power == target || continue
        root_targets = Tuple{Int,Int}[]
        for root in root_values
            numerator = BigInt(root)*index
            numerator % multiplicity == 0 || continue
            exponent = numerator ÷ multiplicity
            exponent <= max_exponent || throw(ArgumentError(
                "required exponent exceeds max_exponent; increase the limit"))
            push!(root_targets, (root, Int(exponent)))
        end
        isempty(root_targets) && continue
        targets += length(root_targets)
        remaining = Base.setindex(counts, counts[base+1]-1, base+1)
        cap = maximum(last, root_targets)+1
        chart, chart_states = anagram_chart(remaining, original, cap,
            zero_to_zero, max_states-states)
        states += chart_states
        for (root, exponent) in root_targets
            haskey(chart, exponent) || continue
            parse = chart[exponent]
            certificate = AnagramCertificate(copy(target), root, exponent,
                [base; parse.digits], (base != first(original))+parse.moves,
                zero_to_zero)
            verify(certificate) || error("anagram witness failed exact verification")
            push!(certificates, certificate)
        end
    end
    sort!(certificates; by=x -> (x.moves, x.root, first(x.digits), x.digits))
    return (; certificates, complete=true, targets, states, method=:anagrams)
end
