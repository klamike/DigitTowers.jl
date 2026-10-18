"""
    RadixSolution

An exact single-digit tower solution in an arbitrary positional radix.
`number::BigInt` is the value in ordinary integer notation; `digits` are
most-significant first, with every digit represented by its integer value.
`root` is an external root order and `exponent` is the suffix tower value.
The defining identity is `digits[1]^exponent == number^root`.
"""
struct RadixSolution
    number::BigInt
    radix::Int
    root::Int
    exponent::Int
    digits::Vector{Int}
end

"""
    verify_radix(solution; zero_to_zero=:forbid)

Independently check the positional numeral, right-associated suffix, and
exact integer power identity of a [`RadixSolution`](@ref). No floating-point
roots or logarithms are used. A digit above nine denotes that integer, not
multiple decimal digits. The zero convention must match the search.
"""
function verify_radix(x::RadixSolution; zero_to_zero::Symbol=:forbid)
    zero_to_zero in (:forbid, :one) || throw(ArgumentError("invalid zero_to_zero policy"))
    x.radix >= 2 && x.root >= 1 && 0 <= x.exponent < typemax(Int) || return false
    length(x.digits) >= 2 || return false
    first(x.digits) >= 2 || return false
    all(d -> 0 <= d < x.radix, x.digits) || return false
    number = foldl((n, d) -> n * x.radix + d, x.digits; init=big(0))
    number == x.number || return false
    blocks = BigInt.(x.digits)
    ops = fill(:^, length(blocks) - 1)
    S = max(2, x.exponent + 1)
    capped_suffix(blocks, ops, S, zero_to_zero) == x.exponent || return false
    return big(first(x.digits))^x.exponent == x.number^x.root
end

"""
    expression_radix(solution)

Format a [`RadixSolution`](@ref) with explicit right association, integer-valued
digit labels, and its bracketed radix numeral. For example, `[2,10]_11`
means `2*11+10`, while `2^10` uses the integer exponent ten.
"""
function expression_radix(x::RadixSolution)
    result = string(last(x.digits))
    for i in length(x.digits)-1:-1:1
        result = "(" * string(x.digits[i]) * "^" * result * ")"
    end
    return "root_$(x.root)($result) = [$(join(x.digits, ','))]_$(x.radix) = $(x.number)"
end

"""
    radix_sweep(radix, lengths; roots=[2], allowed_digits=0:radix-1,
                distinct_digits=false, zero_to_zero=:forbid, max_solutions=100)

Completely search the single-digit, right-associated tower puzzle in a
positional radix `radix >= 2`, over a nonempty unit range of lengths starting
at two. Root orders are external positive integers; `roots=[1]` searches
root-free fixed points. Digits are integers in `0:radix-1`, so a radix above
ten does not change tower semantics. A leading zero or one cannot yield a
nontrivial solution and is excluded.

The exact arithmetic algorithm enumerates primitive powers, not all radix
numerals. Write the leading digit `b=a^g` with primitive `a`. Unique prime
factorization forces `N=a^h`; after evaluating the digit suffix `E`, the only
possible root is `g*E/h`. The largest supplied root bounds `E`, permitting
exact capped evaluation even when the actual tower is astronomical. Every
reported solution is checked with [`verify_radix`](@ref).

Return `(; solutions, complete, status, candidates, cap, method=:radix_sweep)`.
`candidates` counts numeral candidates after digit restrictions but before
suffix evaluation. `cap` is the largest suffix bound used, and `cap+1`
represents overflow. As in [`sweep`](@ref), the entire domain is searched;
`max_solutions` limits returned results, and reaching it conservatively sets
`complete=false`. Memory and runtime grow with the radix and maximum length.

# Examples

```julia
radix_sweep(10, 2:100; roots=1:9)  # includes the original 262144
radix_sweep(22, 3:100; roots=[1])  # a nondecimal, zero-free fixed point
```
"""
function radix_sweep(radix::Int, lengths::AbstractUnitRange{Int}; roots=[2],
                     allowed_digits=0:radix-1, distinct_digits::Bool=false,
                     zero_to_zero::Symbol=:forbid, max_solutions::Int=100)
    radix >= 2 || throw(ArgumentError("radix must be at least two"))
    !isempty(lengths) && first(lengths) >= 2 ||
        throw(ArgumentError("lengths must be nonempty and start at least at two"))
    max_solutions >= 1 || throw(ArgumentError("max_solutions must be positive"))
    zero_to_zero in (:forbid, :one) || throw(ArgumentError("invalid zero_to_zero policy"))
    root_values = sort!(unique(Int[x for x in roots]))
    !isempty(root_values) && all(>(0), root_values) ||
        throw(ArgumentError("roots must be nonempty positive integers"))
    digit_values = sort!(unique(Int[x for x in allowed_digits]))
    !isempty(digit_values) && all(d -> 0 <= d < radix, digit_values) ||
        throw(ArgumentError("allowed_digits must be a nonempty subset of 0:radix-1"))
    root_set = Set(root_values)
    digit_set = Set(digit_values)
    upper_length = distinct_digits ? min(last(lengths), length(digit_values)) : last(lengths)
    found = RadixSolution[]
    candidate_count, largest_bound = 0, 1
    if upper_length >= first(lengths)
        lower_number = big(radix)^(first(lengths) - 1)
        upper_number = big(radix)^upper_length - 1
        maximum_root = maximum(root_values)
        for base in 2:radix-1
            base in digit_set || continue
            primitive, multiplicity = primitive_base(base)
            number, h = big(1), 0
            while number <= upper_number ÷ primitive
                number *= primitive
                h += 1
                number < lower_number && continue
                ds = reverse!(digits(number; base=radix))
                first(ds) == base || continue
                all(in(digit_set), ds) || continue
                distinct_digits && !allunique(ds) && continue
                candidate_count += 1
                bound_big = BigInt(maximum_root) * h ÷ multiplicity
                bound_big < typemax(Int) || throw(ArgumentError(
                    "radix_sweep exponent bound exceeds the capped integer range"))
                bound = Int(bound_big)
                largest_bound = max(largest_bound, bound)
                S = max(2, bound + 1)
                value = capped_suffix(BigInt.(ds), fill(:^, length(ds) - 1), S, zero_to_zero)
                isnothing(value) && continue
                value <= bound || continue
                numerator = BigInt(multiplicity) * value
                numerator % h == 0 || continue
                derived = numerator ÷ h
                derived in root_set || continue
                x = RadixSolution(copy(number), radix, Int(derived), value, ds)
                verify_radix(x; zero_to_zero) || error("radix assignment failed exact verification")
                push!(found, x)
            end
        end
    end
    sort!(found; by=x -> (x.number, x.root, x.exponent))
    complete = length(found) < max_solutions
    length(found) > max_solutions && resize!(found, max_solutions)
    return (; solutions=found, complete,
            status=complete ? MOI.OPTIMAL : MOI.SOLUTION_LIMIT,
            candidates=candidate_count, cap=largest_bound, method=:radix_sweep)
end
