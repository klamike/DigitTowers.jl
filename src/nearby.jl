# Compare the displayed words without allocating a pair of digit vectors for
# every state. Both the input and image use exactly `width` radix digits.
function _modular_digit_distance(number::Int, image::Int, width::Int, radix::Int)
    distance = 0
    for _ in 1:width
        number, digit = divrem(number, radix)
        image, other = divrem(image, radix)
        distance += digit != other
    end
    return distance
end

"""
    modular_nearpoints(ndigits; radix=10, metric=:hamming, limit=100,
                       allowed_digits=0:radix-1, padded=false,
                       zero_to_zero=:forbid, max_states=100_000)

Find the closest approaches to a fixed point of the finite map
`F(N) = tower(padded_digits(N)) mod radix^ndigits`. `:hamming` counts differing
digit positions between the two fixed-width words. `:circular` measures
`min(abs(F(N)-N), radix^ndigits-abs(F(N)-N))` on the residue circle.
The allowed digits restrict inputs; output digits may be arbitrary.

Every eligible input is examined, with undefined towers counted and skipped.
`minimum_distance` and `minimum_count` are exact even when `limit` truncates
the returned `minimizers`. Each witness has `number`, `successor`, and
`distance`. `search_complete=true` certifies domain exhaustion; `complete`
additionally certifies that every minimizer is returned. With no defined
eligible inputs the minimum is `nothing`, and the empty result is complete.
Leading zeros on input are admitted only by `padded=true`; comparison always
pads the output to the same width. Cached totient chains and a lower bound
from the low-order half of the digits prune full-modulus evaluations.
`full_evaluations` and `residue_rejections` account for every defined input.
Distance zero recovers modular fixed points.
"""
function modular_nearpoints(width::Int; radix::Int=10, metric::Symbol=:hamming,
                            limit::Int=100, allowed_digits=0:radix-1,
                            padded::Bool=false, zero_to_zero::Symbol=:forbid,
                            max_states::Int=100_000)
    states = _modular_domain(width, radix, max_states, zero_to_zero)
    metric in (:hamming, :circular) || throw(ArgumentError(
        "metric must be :hamming or :circular"))
    limit >= 1 || throw(ArgumentError("limit must be positive"))
    allowed = Set(allowed_digits)
    !isempty(allowed) && all(d -> d isa Integer && 0 <= d < radix, allowed) ||
        throw(ArgumentError("allowed_digits must be a nonempty subset of 0:radix-1"))
    chain, word = _totient_chain(states), zeros(Int, width)
    sieve_width = width ÷ 2
    sieve_modulus = radix^sieve_width
    sieve_chain = _totient_chain(sieve_modulus)
    minimizers = NamedTuple{(:number, :successor, :distance),Tuple{Int,Int,Int}}[]
    minimum_distance, minimum_count = nothing, 0
    examined, undefined = 0, 0
    full_evaluations, residue_evaluations, residue_rejections = 0, 0, 0
    for number in (padded ? 0 : states ÷ radix):states-1
        _modular_word!(word, number, radix)
        all(in(allowed), word) || continue
        examined += 1
        caps = _modular_suffix_caps(word, states, zero_to_zero)
        if isnothing(caps)
            undefined += 1
            continue
        end
        # Congruence modulo a divisor gives an admissible bound on circular
        # distance; a suffix's digit mismatches bound the full Hamming distance.
        # Avoid the extra evaluation when that bound cannot beat the incumbent.
        use_sieve = !isnothing(minimum_distance) && sieve_width > 0 &&
            (metric == :hamming ? minimum_distance < sieve_width :
             minimum_distance < sieve_modulus ÷ 2)
        if use_sieve
            residue_evaluations += 1
            low_image = _tower_mod(word, caps, sieve_chain)
            low_number = mod(number, sieve_modulus)
            gap = abs(low_number - low_image)
            lower_bound = metric == :hamming ?
                _modular_digit_distance(low_number, low_image, sieve_width, radix) :
                min(gap, sieve_modulus - gap)
            if lower_bound > minimum_distance
                residue_rejections += 1
                continue
            end
        end
        full_evaluations += 1
        successor = _tower_mod(word, caps, chain)
        separation = abs(number - successor)
        distance = metric == :hamming ?
            _modular_digit_distance(number, successor, width, radix) :
            min(separation, states - separation)
        if isnothing(minimum_distance) || distance < minimum_distance
            minimum_distance, minimum_count = distance, 0
            empty!(minimizers)
        end
        if distance == minimum_distance
            minimum_count += 1
            length(minimizers) < limit && push!(minimizers, (; number, successor, distance))
        end
    end
    return (; minimizers, minimum_distance, minimum_count,
            complete=minimum_count <= limit, search_complete=true,
            examined, defined=examined-undefined, undefined,
            full_evaluations, residue_evaluations, residue_rejections,
            states, radix, ndigits=width, metric, allowed_digits=sort!(collect(allowed)),
            padded, zero_to_zero, method=:modular_nearpoints)
end
