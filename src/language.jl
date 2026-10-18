"""
    tower_isdefined(tokens; zero_to_zero=:forbid)

Whether a nonempty right-associated power tower of nonnegative integer tokens
is defined. With `0^0` forbidden, this is exactly the condition that no two
adjacent tokens are zero. A one does not hide an undefined descendant.
With `zero_to_zero=:one`, every such tower is defined.
"""
function tower_isdefined(tokens::AbstractVector{<:Integer}; zero_to_zero::Symbol=:forbid)
    isempty(tokens) && throw(ArgumentError("the tower must contain at least one token"))
    zero_to_zero in (:forbid,:one) || throw(ArgumentError("invalid zero_to_zero policy"))
    previous_zero = false
    defined = true
    for token in tokens
        token >= 0 || throw(ArgumentError("tower tokens must be nonnegative"))
        current_zero = iszero(token)
        previous_zero && current_zero && (defined = false)
        previous_zero = current_zero
    end
    return zero_to_zero == :one || defined
end

function language_matrix_product(A, B)
    return (A[1]*B[1]+A[2]*B[3], A[1]*B[2]+A[2]*B[4],
            A[3]*B[1]+A[4]*B[3], A[3]*B[2]+A[4]*B[4])
end

"""
    tower_language_counts(length; radix=10, leading_zero=false, zero_to_zero=:forbid)

Count defined and undefined single-digit power towers exactly, without
enumerating words. Return `(; defined, undefined, total)` as `BigInt` counts.
By default the first digit is nonzero, so the words represent positive
numbers of exactly the requested length. `leading_zero=true` counts all
fixed-width words instead.

The forbidden `00` language has transfer matrix `[q-1 q-1; 1 0]`, whose
states record whether the last digit is nonzero or zero. Binary matrix
exponentiation takes O(log(length)) matrix products. With `0^0=1`, every
word is defined. This function counts validity, not fixed-point solutions.
"""
function tower_language_counts(length::Int; radix::Int=10, leading_zero::Bool=false,
                               zero_to_zero::Symbol=:forbid)
    length >= 1 || throw(ArgumentError("length must be positive"))
    radix >= 2 || throw(ArgumentError("radix must be at least two"))
    zero_to_zero in (:forbid,:one) || throw(ArgumentError("invalid zero_to_zero policy"))
    q = BigInt(radix)
    total = (leading_zero ? q : q-1) * q^(length-1)
    if zero_to_zero == :one
        return (; defined=total, undefined=big(0), total)
    end
    A = (q-1,q-1,big(1),big(0))
    R = (big(1),big(0),big(0),big(1))
    power = length-1
    while power > 0
        isodd(power) && (R = language_matrix_product(R,A))
        power >>= 1
        power > 0 && (A = language_matrix_product(A,A))
    end
    nonzero, zero = q-1, leading_zero ? big(1) : big(0)
    defined = (R[1]+R[3])*nonzero + (R[2]+R[4])*zero
    return (; defined, undefined=total-defined, total)
end
