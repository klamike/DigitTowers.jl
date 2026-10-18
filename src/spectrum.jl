"""
    RootCertificate

An exact certificate that a digit numeral admits a positive integer external
root order, with no upper bound on that order. `number = primitive^h` and its
leading digit is `primitive^g`. The suffix is `c^T`, where `c=digits[2]`;
`k=h/gcd(h,g)` must divide `c^T`. `required_tail_threshold` certifies the
necessary and sufficient lower bound on `T` from prime valuations of `k`.

`root` is an exact `BigInt` when it is at most `root_display_limit`; otherwise
it is `nothing`, certifying that the unique root is larger than that limit.
Use [`expression`](@ref) for its symbolic value. The stored `zero_to_zero`
convention is part of the certificate, and digits are most-significant first.
"""
struct RootCertificate
    number::BigInt
    radix::Int
    digits::Vector{Int}
    primitive::BigInt
    g::Int
    h::Int
    k::Int
    required_tail_threshold::Int
    root::Union{Nothing,BigInt}
    root_display_limit::Int
    zero_to_zero::Symbol
end

function _spectrum_threshold(k::Int, c::Int)
    threshold = 0
    for (p, e) in Primes.factor(k)
        residue, valuation = c, 0
        while residue % p == 0
            residue ÷= p
            valuation += 1
        end
        valuation == 0 && return nothing
        threshold = max(threshold, cld(e, valuation))
    end
    return threshold
end

function _spectrum_tailcap(ds, S::Int, policy::Symbol)
    length(ds) == 2 && return 1 # c itself is c^1.
    value = min(last(ds), S)
    for i in length(ds)-1:-1:3
        value = capped_power(min(ds[i], S), value, S, policy)
        isnothing(value) && return nothing
    end
    return value
end

function _spectrum_small_root(ds, g, h, limit, policy)
    # r <= limit iff c^T <= floor(h*limit/g). Logarithms are exact integer
    # comparisons; at most the tiny threshold exponent is ever materialized.
    bound = BigInt(h) * limit ÷ g
    first_large, _ = ceil_log_power(bound + 1, big(ds[2]))
    S = max(2, first_large)
    tail = _spectrum_tailcap(ds, S, policy)
    isnothing(tail) && return nothing
    tail >= first_large && return nothing
    numerator = BigInt(g) * big(ds[2])^tail
    numerator % h == 0 || error("invalid integral-root certificate")
    return numerator ÷ h
end

"""
    verify_root_certificate(certificate)
    verify(certificate::RootCertificate)

Verify the numeral, primitive-power identity, prime-valuation condition, and
small-root value or strict lower bound of a [`RootCertificate`](@ref). The
algorithm never constructs an unbounded tower or an enormous root order.
Every nested power must be defined according to the stored zero convention.
"""
function verify_root_certificate(x::RootCertificate)
    x.radix >= 2 && x.root_display_limit >= 1 || return false
    x.zero_to_zero in (:forbid, :one) || return false
    length(x.digits) >= 2 && first(x.digits) >= 2 || return false
    all(d -> 0 <= d < x.radix, x.digits) || return false
    x.digits[2] >= 2 || return false
    x.g >= 1 && x.h > x.g || return false
    number = foldl((n, d) -> n * x.radix + d, x.digits; init=big(0))
    number == x.number || return false
    a, g = primitive_base(first(x.digits))
    a == x.primitive && g == x.g && a^x.h == x.number || return false
    x.k == x.h ÷ gcd(x.h, x.g) || return false
    threshold = _spectrum_threshold(x.k, x.digits[2])
    isnothing(threshold) && return false
    threshold == x.required_tail_threshold || return false
    tower_isdefined(x.digits; zero_to_zero=x.zero_to_zero) || return false
    tail = _spectrum_tailcap(x.digits, max(2, threshold), x.zero_to_zero)
    isnothing(tail) && return false
    tail >= threshold || return false
    root = _spectrum_small_root(x.digits, x.g, x.h, x.root_display_limit, x.zero_to_zero)
    return root == x.root
end

verify(x::RootCertificate) = verify_root_certificate(x)

function _spectrum_root_expression(x::RootCertificate)
    !isnothing(x.root) && return string(x.root)
    tail = length(x.digits) == 2 ? "1" : "tower([$(join(x.digits[3:end], ','))])"
    divisor = gcd(x.h, x.g)
    factor = x.g ÷ divisor
    # If the denominator is a power of c, expose a particularly simple root:
    # 4294967296, for example, has r = 2^(tower([9,4,9,6,7,2,9,6])-4).
    residue, power = x.k, 0
    while residue % x.digits[2] == 0
        residue ÷= x.digits[2]
        power += 1
    end
    if residue == 1
        term = "$(x.digits[2])^($tail-$power)"
        return factor == 1 ? term : "$factor*($term)"
    end
    numerator = "$(x.digits[2])^($tail)"
    factor == 1 || (numerator = "$factor*($numerator)")
    return "($numerator)/$(x.k)"
end

"""
    expression(certificate::RootCertificate)

Display a root-spectrum solution, using `tower([d1,d2,...])` for a
right-associated tower with integer-valued digits. Large root orders stay
symbolic and carry the certified strict bound `r > root_display_limit`.
"""
function expression(x::RootCertificate)
    root = _spectrum_root_expression(x)
    lower_bound = isnothing(x.root) ? " > $(x.root_display_limit)" : ""
    return "root_r(tower([$(join(x.digits, ','))])) = [$(join(x.digits, ','))]_$(x.radix) = $(x.number); r = $root$lower_bound"
end

"""
    root_spectrum(lengths; radix=10, allowed_digits=0:radix-1,
                  distinct_digits=false, zero_to_zero=:forbid,
                  root_display_limit=1000, max_solutions=1000)

Find every numeral in the bounded length/radix domain that admits *any*
positive integer external root order in the single-digit, right-associated
power grammar. Root orders have no search bound and may be astronomical.
`root_display_limit` controls formatting/materialization, never membership.
Return exact [`RootCertificate`](@ref)s as `solutions`.

For leading digit `b=a^g`, primitive `a` forces `N=a^h`. Write the suffix as
`c^T`. An integer root exists iff `k=h/gcd(h,g)` divides `c^T`: every prime
of `k` must divide `c`, and `T` must reach the largest required prime-valuation
threshold. Tiny capped evaluations decide this without constructing `T`,
`c^T`, or a large root. All nested powers are checked for definedness.

Return `(; solutions, complete, status, candidates, method=:root_spectrum)`.
The whole numeral domain is searched before sorting and truncation;
`candidates` counts primitive-power numerals passing digit restrictions.
Reaching `max_solutions` conservatively sets `complete=false`. Lengths must
be a nonempty unit range starting at two. The zero convention, allowed digit
values, and distinct-digit restriction have the same meaning as in
[`radix_sweep`](@ref).

# Examples

```julia
result = root_spectrum(2:20)
x = only(filter(x -> x.number == 4294967296, result.solutions))
@assert isnothing(x.root)  # r exceeds 1000; it is retained exactly symbolically.
@assert verify_root_certificate(x)
```
"""
function root_spectrum(lengths::AbstractUnitRange{Int}; radix::Int=10,
                       allowed_digits=0:radix-1, distinct_digits::Bool=false,
                       zero_to_zero::Symbol=:forbid,
                       root_display_limit::Int=1000, max_solutions::Int=1000)
    radix >= 2 || throw(ArgumentError("radix must be at least two"))
    !isempty(lengths) && first(lengths) >= 2 ||
        throw(ArgumentError("lengths must be nonempty and start at least at two"))
    zero_to_zero in (:forbid, :one) || throw(ArgumentError("invalid zero_to_zero policy"))
    root_display_limit >= 1 || throw(ArgumentError("root_display_limit must be positive"))
    max_solutions >= 1 || throw(ArgumentError("max_solutions must be positive"))
    values = sort!(unique(Int[x for x in allowed_digits]))
    !isempty(values) && all(d -> 0 <= d < radix, values) ||
        throw(ArgumentError("allowed_digits must be a nonempty subset of 0:radix-1"))
    domain = Set(values)
    found = RootCertificate[]
    candidates = 0
    upper_length = distinct_digits ? min(last(lengths), length(values)) : last(lengths)
    if upper_length >= first(lengths)
        lower = big(radix)^(first(lengths) - 1)
        upper = big(radix)^upper_length - 1
        for base in 2:radix-1
            base in domain || continue
            a, g = primitive_base(base)
            number, h = big(1), 0
            while number <= upper ÷ a
                number *= a
                h += 1
                number < lower && continue
                ds = reverse!(digits(number; base=radix))
                first(ds) == base || continue
                all(in(domain), ds) || continue
                distinct_digits && !allunique(ds) && continue
                candidates += 1
                ds[2] >= 2 || continue
                tower_isdefined(ds; zero_to_zero) || continue
                k = h ÷ gcd(h, g)
                threshold = _spectrum_threshold(k, ds[2])
                isnothing(threshold) && continue
                tail = _spectrum_tailcap(ds, max(2, threshold), zero_to_zero)
                isnothing(tail) && continue
                tail >= threshold || continue
                root = _spectrum_small_root(ds, g, h, root_display_limit, zero_to_zero)
                x = RootCertificate(copy(number), radix, ds, a, g, h, k,
                                    threshold, root, root_display_limit, zero_to_zero)
                verify_root_certificate(x) || error("root certificate failed exact verification")
                push!(found, x)
            end
        end
    end
    sort!(found; by=x -> x.number)
    complete = length(found) < max_solutions
    length(found) > max_solutions && resize!(found, max_solutions)
    return (; solutions=found, complete,
            status=complete ? MOI.OPTIMAL : MOI.SOLUTION_LIMIT,
            candidates, method=:root_spectrum)
end
