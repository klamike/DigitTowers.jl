"""
    sweep(lengths::AbstractUnitRange{Int}; roots=[2],
          allowed_digits=collect(0:9), root_digits=0,
          distinct_digits=false, zero_to_zero=:forbid, max_solutions=100)

Search several decimal lengths and root orders in one exact pass. This method
supports the single-digit, right-associated power grammar. To search grouped
blocks or addition, use [`search`](@ref) with a [`Config`](@ref).

If an outer base is `b=a^g` and a possible answer is `N=a^h`, its suffix value
`E` determines the only possible root order: `r=g*E/h`. The algorithm evaluates
that suffix once, tests divisibility, and checks membership in `roots`.
`root_digits` consumes that many leading decimal digits as the root order.
Every intermediate `0^0` obeys `zero_to_zero`, including above a blocker.

Return `(; solutions, complete, status, candidates, cap, method=:sweep)`.
Solutions are sorted by number and root order. `candidates` counts distinct
numbers passing the length, outer-base, consumed-root, and digit restrictions
before suffix evaluation; it does not count one assignment per root. `cap`
is the largest target-exponent bound used, with `cap+1` the overflow state.
Reaching `max_solutions` is conservatively reported as `complete=false`.
The full range is searched before sorting and truncation, so this option
limits returned results rather than the amount of work.

The length range must be nonempty and start at least at
`max(2, root_digits+2)`. As with `Config`, trivial one-digit answers are excluded.

# Examples

```julia
result = sweep(2:100; roots=collect(1:9))
@assert result.complete
@assert only(result.solutions).number == 262144
```
"""
function sweep(lengths::AbstractUnitRange{Int}; roots=[2],
               allowed_digits=collect(0:9), root_digits::Int=0,
               distinct_digits::Bool=false, zero_to_zero::Symbol=:forbid,
               max_solutions::Int=100)
    isempty(lengths) && throw(ArgumentError("lengths must be nonempty"))
    max_solutions >= 1 || throw(ArgumentError("max_solutions must be positive"))
    root_digits >= 0 || throw(ArgumentError("root_digits must be nonnegative"))
    first(lengths) >= max(2, root_digits + 2) || throw(ArgumentError(
        "lengths must start at least at max(2, root_digits+2)"))
    root_values = sort!(unique(Int[x for x in roots]))
    digit_values = sort!(unique(Int[x for x in allowed_digits]))
    template = Config(ndigits=first(lengths), roots=root_values,
                      root_digits=root_digits, allowed_digits=digit_values,
                      distinct_digits=distinct_digits, zero_to_zero=zero_to_zero)
    grammar(template) # Reuse the public grammar's domain validation.
    if root_digits > 0
        filter!(r -> length(string(r)) == root_digits, root_values)
    end
    found = Candidate[]
    candidate_count = 0
    largest_bound = 1
    upper_length = distinct_digits ? min(last(lengths), length(digit_values)) : last(lengths)
    if !isempty(root_values) && upper_length >= first(lengths)
        lower_number = big(10)^(first(lengths) - 1)
        upper_number = big(10)^upper_length - 1
        maximum_root = maximum(root_values)
        base_position = root_digits + 1
        for base in 2:9
            base in digit_values || continue
            primitive, multiplicity = primitive_base(base)
            number, h = big(1), 0
            while number <= upper_number ÷ primitive
                number *= primitive
                h += 1
                number < lower_number && continue
                text = string(number)
                Int(text[base_position] - '0') == base || continue
                ds = [Int(ch - '0') for ch in text]
                all(in(digit_values), ds) || continue
                distinct_digits && !allunique(ds) && continue
                if root_digits > 0
                    parse(Int, text[1:root_digits]) in root_values || continue
                end
                candidate_count += 1
                # BigInt protects the product when a large root domain is used.
                bound_big = BigInt(maximum_root) * h ÷ multiplicity
                bound_big < typemax(Int) || throw(ArgumentError(
                    "sweep exponent bound exceeds the capped integer range"))
                bound = Int(bound_big)
                largest_bound = max(largest_bound, bound)
                S = max(2, bound + 1)
                blocks = BigInt.(ds[base_position:end])
                ops = fill(:^, length(blocks) - 1)
                value = capped_suffix(blocks, ops, S, zero_to_zero)
                isnothing(value) && continue
                value <= bound || continue # The overflow state is not exact.
                numerator = BigInt(multiplicity) * value
                numerator % h == 0 || continue
                derived = numerator ÷ h
                derived in root_values || continue
                root = Int(derived)
                if root_digits > 0
                    text[1:root_digits] == string(root) || continue
                end
                config = Config(ndigits=length(ds), roots=root_values,
                                root_digits=root_digits, allowed_digits=digit_values,
                                distinct_digits=distinct_digits, zero_to_zero=zero_to_zero)
                x = Candidate(copy(number), root, value, ds, blocks)
                verify(x, config) || error("sweep assignment failed the exact integer check")
                push!(found, x)
            end
        end
    end
    sort!(found; by=x -> (x.number, x.root, x.exponent))
    complete = length(found) < max_solutions
    length(found) > max_solutions && resize!(found, max_solutions)
    return (; solutions=found, complete,
            status=complete ? MOI.OPTIMAL : MOI.SOLUTION_LIMIT,
            candidates=candidate_count, cap=largest_bound, method=:sweep)
end
