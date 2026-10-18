"""
    modular_orbit(start, ndigits; radix=10, zero_to_zero=:forbid,
                  max_evaluations=1_000_000, max_width=10_000)

Find the eventual behavior of one orbit of the fixed-width map
`N -> tower(padded_digits(N)) mod radix^ndigits`, using Brent's cycle
detection algorithm. Unlike [`modular_dynamics`](@ref), this does not
enumerate the entire state space. It keeps a constant number of orbit states,
in addition to the digits and cached Euler-totient chain used for evaluation.
Large moduli have the certification limits of [`tower_mod`](@ref).

For `termination=:cycle`, `preperiod` is the least number of steps before
entering the cycle, `period` its least positive length, and `entry` the first
cycle state reached from `start`. For `termination=:undefined`,
`undefined_at` is the first word whose next evaluation is undefined and
`distance_to_undefined` counts transitions from `start` to that word.
The unused fields are `nothing`.

`evaluations` counts all map calls, including the second phase that locates
the cycle entry. Exhausting `max_evaluations` returns `complete=false` and
`termination=:limit`; all structural fields are then `nothing`. The width
guard throws an error rather than allocating an accidentally enormous
modulus. Initial values must lie in `0:radix^ndigits-1`; leading zeros are
always padding, not omitted tokens.

Return a named tuple with those fields, `complete`, the domain parameters,
and `method=:brent`. No trajectory or full cycle is retained.

# Examples

```julia
orbit = modular_orbit(426, 3)
@assert (orbit.preperiod, orbit.period, orbit.entry) == (1, 2, big(456))

# A domain with 2^1000 states, without constructing that functional graph.
wide = modular_orbit(big(2)^999, 1000; radix=2, zero_to_zero=:one)
@assert wide.complete && wide.period == 2
```
"""
function modular_orbit(start::Integer, width::Int; radix::Int=10,
        zero_to_zero::Symbol=:forbid, max_evaluations::Int=1_000_000,
        max_width::Int=10_000)
    1 <= width <= max_width || throw(ArgumentError(
        "ndigits must be positive and no greater than max_width"))
    radix >= 2 || throw(ArgumentError("radix must be at least two"))
    zero_to_zero in (:forbid, :one) || throw(ArgumentError("invalid zero_to_zero policy"))
    1 <= max_evaluations <= typemax(Int) ÷ 2 || throw(ArgumentError(
        "max_evaluations must lie between one and typemax(Int) ÷ 2"))
    modulus = big(radix)^width
    0 <= start < modulus || throw(ArgumentError("start must lie in 0:radix^ndigits-1"))
    T = modulus <= typemax(Int) ÷ 2 ? Int : BigInt
    m, initial = T(modulus), T(start)
    word = zeros(T, width)
    # Delay factorization until an initially defined word actually needs it.
    chain = Ref{Union{Nothing,Vector{T}}}(nothing)
    evaluations = 0
    function advance(value)
        evaluations >= max_evaluations && return :limit
        evaluations += 1
        remaining = value
        for i in width:-1:1
            remaining, digit = divrem(remaining, radix)
            word[i] = digit
        end
        caps = _modular_suffix_caps(word, max(T(2), m), zero_to_zero)
        isnothing(caps) && return nothing
        isnothing(chain[]) && (chain[] = _totient_chain(m))
        return _tower_mod(word, caps, chain[])
    end
    function result(termination; preperiod=nothing, period=nothing, entry=nothing,
            undefined_at=nothing, distance_to_undefined=nothing)
        return (; termination, complete=termination != :limit,
            preperiod, period, entry=isnothing(entry) ? nothing : BigInt(entry),
            undefined_at=isnothing(undefined_at) ? nothing : BigInt(undefined_at),
            distance_to_undefined, evaluations, start=BigInt(start), radix,
            ndigits=width, zero_to_zero, method=:brent)
    end

    power = period = 1
    tortoise = initial
    hare = advance(initial)
    hare === :limit && return result(:limit)
    isnothing(hare) && return result(:undefined;
        undefined_at=initial, distance_to_undefined=0)
    position = 1
    while tortoise != hare
        if power == period
            tortoise = hare
            power *= 2
            period = 0
        end
        previous = hare
        hare = advance(hare)
        hare === :limit && return result(:limit)
        isnothing(hare) && return result(:undefined;
            undefined_at=previous, distance_to_undefined=position)
        position += 1
        period += 1
    end

    # Separate two walkers by the period, then advance together to find mu.
    tortoise = hare = initial
    for _ in 1:period
        hare = advance(hare)
        hare === :limit && return result(:limit)
        isnothing(hare) && error("a detected cycle unexpectedly became undefined")
    end
    preperiod = 0
    while tortoise != hare
        tortoise = advance(tortoise)
        tortoise === :limit && return result(:limit)
        isnothing(tortoise) && error("a detected cycle unexpectedly became undefined")
        hare = advance(hare)
        hare === :limit && return result(:limit)
        isnothing(hare) && error("a detected cycle unexpectedly became undefined")
        preperiod += 1
    end
    return result(:cycle; preperiod, period, entry=tortoise)
end
