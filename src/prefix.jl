"""
    ceil_log_power(A::BigInt, a::BigInt) -> (h, number)

Return the smallest nonnegative integer `h` with `number = a^h >= A`.
The positive threshold `A` and base `2 <= a <= typemax(Int)` are exact
integers. `ndigits` supplies an initial exponent; exact power comparisons
certify and, if needed, correct both boundaries.
"""
function ceil_log_power(A::BigInt, a::BigInt)
    A >= 1 || throw(ArgumentError("power threshold must be positive"))
    2 <= a <= typemax(Int) || throw(ArgumentError("power base must be between 2 and typemax(Int)"))
    A == 1 && return 0, big(1)

    # For integer A >= 2, ceil(log_a(A)) = ndigits(A - 1; base=a).
    # Treat that result only as a seed: the comparisons below certify it.
    h = ndigits(A - 1; base=Int(a))
    number = a^h
    while number < A
        number *= a
        h += 1
    end
    while h > 0
        previous = number ÷ a
        previous < A && break
        number = previous
        h -= 1
    end
    return h, number
end

function prefix_blocks(number::BigInt, c::Config, widths)
    text = string(number)
    length(text) == c.ndigits || return nothing
    ds = [Int(ch - '0') for ch in text]
    all(d -> d in c.allowed_digits, ds) || return nothing
    blocks = BigInt[]
    start = c.root_digits + 1
    for w in widths
        !c.leading_zeros_in_blocks && w > 1 && ds[start] == 0 && return nothing
        push!(blocks, parse(BigInt, text[start:start+w-1]))
        start += w
    end
    return ds, blocks
end

function collect_prefix_window!(candidates, c, widths, b, a, g, roots,
        prefix, scale, exponent_ceiling)
    lower = prefix * scale
    upper = (prefix + 1) * scale
    h, number = exponent_ceiling(lower, a)
    lower <= number < upper || return nothing
    parsed = prefix_blocks(number, c, widths)
    isnothing(parsed) && return nothing
    ds, blocks = parsed
    blocks[1] == b || return nothing
    for r in roots
        numerator = BigInt(r) * h
        numerator % g == 0 || continue
        e = numerator ÷ g
        e <= typemax(Int) || throw(ArgumentError("required exponent exceeds Int"))
        push!(candidates, Candidate(copy(number), r, Int(e), ds, blocks))
    end
    return nothing
end

"""
    prefix_candidates(config::Config, widths; exponent_ceiling=ceil_log_power)

Generate the same necessary-condition assignments as `candidate_table` using
exact decimal prefix windows. For base `b = a^g` and required prefix `P`, the
answer must lie in `[P*10^k, (P+1)*10^k)`. Its multiplicative width is less
than two, so it contains at most one power of `a >= 2`. Only that power is
constructed, and external root orders reuse the same window.

The `exponent_ceiling` hook must return `(h, a^h)` for the smallest `h` whose
power reaches the supplied exact lower bound. Suffix evaluation and the
all-different constraint are deliberately left to the search backend; only
the universal distinct-digit pigeonhole bound is applied here.
"""
function prefix_candidates(c::Config, widths; exponent_ceiling=ceil_log_power)
    if c.distinct_digits && c.ndigits > length(unique(c.allowed_digits))
        return Candidate[]
    end
    candidates = Candidate[]
    roots = unique(c.roots)
    prefix_width = c.root_digits + widths[1]
    scale = big(10)^(c.ndigits - prefix_width)
    base_shift = c.root_digits > 0 ? big(10)^widths[1] : big(1)
    for b in base_domain(c, widths[1])
        a, g = primitive_base(b)
        if c.root_digits == 0
            collect_prefix_window!(candidates, c, widths, b, a, g, roots,
                BigInt(b), scale, exponent_ceiling)
        else
            for r in roots
                length(string(r)) == c.root_digits || continue
                prefix = BigInt(r) * base_shift + b
                collect_prefix_window!(candidates, c, widths, b, a, g, (r,),
                    prefix, scale, exponent_ceiling)
            end
        end
    end
    sort!(candidates; by=x -> (x.number, x.root, x.exponent))
    return candidates
end
