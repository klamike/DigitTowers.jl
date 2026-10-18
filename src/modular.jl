# Exact modular exponentiation of a tower. Reducing the exponent modulo phi(m)
# alone is wrong for nonunits; suffix caps decide when the extra phi(m) is safe.
_certified_totient(n::Int) = Primes.totient(n)

function _certified_totient(n::BigInt)
    factors = Primes.factor(n)
    reconstructed = prod((p^e for (p, e) in factors); init=big(1))
    reconstructed == n || error("totient factorization failed exact reconstruction")
    for (p, e) in factors
        e >= 1 || error("totient factorization contains an invalid multiplicity")
        p <= typemax(Int) || throw(ArgumentError(
            "cannot certify this totient chain: prime factor $p exceeds typemax(Int); " *
            "large moduli are supported when all prime factors can be certified " *
            "with deterministic machine-integer primality tests"))
        p >= 2 && Primes.isprime(Int(p)) || error(
            "totient factorization contains a factor that is not a certified prime")
    end
    value = copy(n)
    for (p, _) in factors
        value = div(value, p) * (p - 1)
    end
    return value
end

function _totient_chain(modulus::T) where {T<:Integer}
    chain = T[modulus]
    while last(chain) > 1
        push!(chain, _certified_totient(last(chain)))
    end
    return chain
end

function _modular_powercap(a::T, e::T, cap::T) where {T<:Integer}
    iszero(e) && return one(T)
    iszero(a) && return zero(T)
    isone(a) && return one(T)
    value = one(T)
    while e > 0
        value > cap ÷ a && return cap
        value *= a
        e -= 1
    end
    return min(value, cap)
end

function _modular_suffix_caps(word::Vector{T}, cap::T, policy::Symbol) where {T<:Integer}
    caps = similar(word)
    caps[end] = min(word[end], cap)
    for i in length(word)-1:-1:1
        a, e = min(word[i], cap), caps[i+1]
        iszero(a) && iszero(e) && policy == :forbid && return nothing
        caps[i] = _modular_powercap(a, e, cap)
    end
    return caps
end

function _tower_mod(word::Vector{T}, caps::Vector{T}, chain::Vector{T}, i::Int=1) where {T<:Integer}
    modulus = chain[i]
    isone(modulus) && return zero(T)
    i == length(word) && return mod(word[i], modulus)
    phi = chain[i+1]
    exponent = caps[i+1] < phi ? caps[i+1] : _tower_mod(word, caps, chain, i+1) + phi
    return powermod(word[i], exponent, modulus)
end

"""
    tower_mod(word, modulus; zero_to_zero=:forbid)

Evaluate the right-associated power tower of nonnegative integers `word`
modulo a positive integer, without constructing the tower. Return `nothing`
if any nested `0^0` is undefined; `zero_to_zero=:one` defines it as one.
All nested powers are checked even when an outer base is zero or one.

An Euler-totient chain and exact capped suffix values handle noncoprime bases.
For example, `tower_mod([2, 2, 3], 8) == 0`, although naively reducing the
exponent modulo `phi(8)` would give the incorrect answer one. Large moduli use
`BigInt`; factoring their totient chain can be expensive. Every factorization
is reconstructed and each prime factor is certified with deterministic
machine-integer primality tests. A factor above `typemax(Int)` raises an
`ArgumentError`; arbitrarily large powers of small primes remain supported.
"""
function tower_mod(word::AbstractVector{<:Integer}, modulus::Integer; zero_to_zero::Symbol=:forbid)
    !isempty(word) || throw(ArgumentError("word must be nonempty"))
    all(>=(0), word) || throw(ArgumentError("tower entries must be nonnegative"))
    modulus > 0 || throw(ArgumentError("modulus must be positive"))
    zero_to_zero in (:forbid, :one) || throw(ArgumentError("invalid zero_to_zero policy"))
    # A lifted exponent is below 2m. Keep the machine-integer path overflow-safe.
    T = modulus <= typemax(Int) ÷ 2 && all(<=(typemax(Int)), word) ? Int : BigInt
    values, m = T.(word), T(modulus)
    caps = _modular_suffix_caps(values, max(T(2), m), zero_to_zero)
    isnothing(caps) && return nothing
    return _tower_mod(values, caps, _totient_chain(m))
end

function _modular_domain(width::Int, radix::Int, max_states::Int, policy::Symbol)
    width >= 1 || throw(ArgumentError("ndigits must be positive"))
    radix >= 2 || throw(ArgumentError("radix must be at least two"))
    max_states >= 1 || throw(ArgumentError("max_states must be positive"))
    policy in (:forbid, :one) || throw(ArgumentError("invalid zero_to_zero policy"))
    limit, states = min(max_states, typemax(Int) ÷ 2), 1
    for _ in 1:width
        states <= limit ÷ radix || throw(ArgumentError(
            "radix^ndigits exceeds max_states or the machine-integer safety bound"))
        states *= radix
    end
    return states
end

function _modular_word!(word::Vector{Int}, number::Int, radix::Int)
    for i in length(word):-1:1
        number, word[i] = divrem(number, radix)
    end
    return word
end

"""
    modular_fixedpoints(ndigits; radix=10, allowed_digits=0:radix-1,
                        padded=false, zero_to_zero=:forbid, max_states=100_000)

Find every `ndigits`-digit number `N` whose digit tower is congruent to `N`
modulo `radix^ndigits`. This is a root-free congruence puzzle, distinct from
`search`. With `padded=true`, enumerate all fixed-width words including leading
zeros. `complete=true` certifies exhaustion of the explicitly bounded domain.
"""
function modular_fixedpoints(width::Int; radix::Int=10, allowed_digits=0:radix-1,
                             padded::Bool=false, zero_to_zero::Symbol=:forbid,
                             max_states::Int=100_000)
    states = _modular_domain(width, radix, max_states, zero_to_zero)
    allowed = Set(allowed_digits)
    !isempty(allowed) && all(d -> d isa Integer && 0 <= d < radix, allowed) ||
        throw(ArgumentError("allowed_digits must be a nonempty subset of 0:radix-1"))
    chain = _totient_chain(states)
    word = zeros(Int, width)
    solutions = Int[]
    examined, undefined = 0, 0
    for number in (padded ? 0 : states ÷ radix):states-1
        _modular_word!(word, number, radix)
        all(in(allowed), word) || continue
        examined += 1
        caps = _modular_suffix_caps(word, states, zero_to_zero)
        if isnothing(caps)
            undefined += 1
        elseif _tower_mod(word, caps, chain) == number
            push!(solutions, number)
        end
    end
    return (; solutions, complete=true, examined, undefined, radix, ndigits=width,
            padded, zero_to_zero, method=:modular)
end

"""
    modular_dynamics(ndigits; radix=10, zero_to_zero=:forbid, max_states=100_000)

Exhaust the finite map `N -> tower(padded_digits(N)) mod radix^ndigits` on all
fixed-width words, including leading zeros. Return its directed cycles, each
rotated to put its smallest state first; the corresponding `basin_sizes` count
all starting states eventually reaching that cycle. `undefined_basin` counts
states eventually hitting a nested undefined `0^0`; `undefined` counts states
whose very next evaluation is undefined. No edges are inferred or sampled.
"""
function modular_dynamics(width::Int; radix::Int=10, zero_to_zero::Symbol=:forbid,
                          max_states::Int=100_000)
    states = _modular_domain(width, radix, max_states, zero_to_zero)
    chain = _totient_chain(states)
    word = zeros(Int, width)
    successor = fill(-1, states)
    undefined = 0
    for number in 0:states-1
        _modular_word!(word, number, radix)
        caps = _modular_suffix_caps(word, states, zero_to_zero)
        if isnothing(caps)
            undefined += 1
        else
            successor[number+1] = _tower_mod(word, caps, chain)
        end
    end
    # An owner is a positive cycle index, -1 for the undefined sink, or 0
    # before discovery. Per-walk stamps locate a repeated state in linear time.
    owner = zeros(Int, states)
    stamp = zeros(Int, states)
    position = zeros(Int, states)
    cycles = Vector{Int}[]
    for initial in 0:states-1
        owner[initial+1] == 0 || continue
        path = Int[]
        number = initial
        walk = initial + 1
        while number >= 0 && owner[number+1] == 0 && stamp[number+1] != walk
            stamp[number+1] = walk
            position[number+1] = length(path) + 1
            push!(path, number)
            number = successor[number+1]
        end
        target = if number < 0
            -1
        elseif owner[number+1] != 0
            owner[number+1]
        else
            cycle = path[position[number+1]:end]
            pivot = argmin(cycle)
            push!(cycles, vcat(cycle[pivot:end], cycle[1:pivot-1]))
            length(cycles)
        end
        for number in path
            owner[number+1] = target
        end
    end
    basin_sizes = zeros(Int, length(cycles))
    for target in owner
        target > 0 && (basin_sizes[target] += 1)
    end
    order = sortperm(cycles; by = x -> (length(x), first(x)))
    return (; cycles=cycles[order], basin_sizes=basin_sizes[order],
            undefined, undefined_basin=count(==(-1), owner), states,
            complete=true, radix, ndigits=width, zero_to_zero, method=:modular)
end
