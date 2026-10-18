module DigitTowers

using JuMP
import HiGHS
import Primes
const MOI = JuMP.MOI

export Config, Candidate, build_model, search, sweep, verify, expression
export tower_isdefined, tower_language_counts
export RadixSolution, radix_sweep, verify_radix, expression_radix
export tower_mod, modular_fixedpoints, modular_dynamics
export synthesize, SynthesisCertificate
export root_spectrum, RootCertificate, verify_root_certificate

"""
A fixed expression grammar. By default: sqrt(d1^(d2^(...^dL))).
`root_digits` consumes that many leading digits of N as the root order.
`block_widths` partitions the remaining digits, including the outer base.
`operators` joins blocks RIGHT-ASSOCIATIVELY; the first must be :^.
The supported operators are :^ and :+ (addition is inside the outer power).
"""
Base.@kwdef struct Config
    ndigits::Int = 6
    roots::Vector{Int} = [2]
    root_digits::Int = 0
    block_widths::Union{Nothing,Vector{Int}} = nothing
    operators::Union{Nothing,Vector{Symbol}} = nothing
    allowed_digits::Vector{Int} = collect(0:9)
    distinct_digits::Bool = false
    leading_zeros_in_blocks::Bool = false
    zero_to_zero::Symbol = :forbid  # alternatively :one
    bases::Union{Nothing,Vector{Int}} = nothing
    max_bases::Int = 100_000        # refuse accidental enormous preprocessing
    max_table_rows::Int = 1_000_000 # explicit, configurable table-size guard
    time_limit::Float64 = 60.0     # seconds per optimize! call
end

"""
    Candidate

A necessary-condition assignment (or a verified solution): `number::BigInt`,
`root`, `exponent`, decimal `digits`, and parsed `blocks`. A precomputed
candidate becomes a solution only after its suffix evaluates to `exponent`.
Use [`verify`](@ref) to check the complete expression.
"""
struct Candidate
    number::BigInt
    root::Int
    exponent::Int
    digits::Vector{Int}
    blocks::Vector{BigInt}
end

function grammar(c::Config)
    c.ndigits >= 2 || throw(ArgumentError("ndigits must be at least 2; trivial N=1 is excluded"))
    0 <= c.root_digits <= c.ndigits - 2 || throw(ArgumentError("invalid root_digits"))
    !isempty(c.roots) && all(>(0), c.roots) || throw(ArgumentError("roots must be positive integers"))
    maximum(c.roots) < 2^52 || throw(ArgumentError("root orders must fit the solver's exact integer range"))
    !isempty(c.allowed_digits) && all(x -> 0 <= x <= 9, c.allowed_digits) ||
        throw(ArgumentError("allowed_digits must be a nonempty subset of 0:9"))
    c.zero_to_zero in (:forbid, :one) || throw(ArgumentError("invalid zero_to_zero policy"))
    c.max_bases > 0 || throw(ArgumentError("max_bases must be positive"))
    c.max_table_rows > 0 || throw(ArgumentError("max_table_rows must be positive"))
    c.time_limit > 0 || throw(ArgumentError("time_limit must be positive"))
    widths = isnothing(c.block_widths) ? ones(Int, c.ndigits - c.root_digits) : copy(c.block_widths)
    length(widths) >= 2 && all(>(0), widths) && sum(widths) == c.ndigits - c.root_digits ||
        throw(ArgumentError("positive block_widths must cover all non-root digits, with at least two blocks"))
    ops = isnothing(c.operators) ? fill(:^, length(widths) - 1) : copy(c.operators)
    length(ops) == length(widths) - 1 && first(ops) == :^ && all(x -> x in (:^, :+), ops) ||
        throw(ArgumentError("operators must join the blocks; first operator must be :^"))
    return widths, ops
end

# b = a^g where a is not itself a perfect power. No floating-point logs.
function primitive_base(b::Int)
    factors = collect(Primes.factor(b))
    g = foldl(gcd, last.(factors))
    a = prod(BigInt(p)^div(e, g) for (p, e) in factors)
    return a, g
end

function base_domain(c::Config, width::Int)
    padded = c.leading_zeros_in_blocks && c.root_digits > 0
    if !isnothing(c.bases)
        values = sort!(unique(c.bases))
        all(b -> b >= 2 && (padded ? length(string(b)) <= width : length(string(b)) == width), values) ||
            throw(ArgumentError("every supplied base must be >=2 and fit the first block's width"))
        length(values) <= c.max_bases || throw(ArgumentError("increase max_bases to enumerate these bases"))
        return values
    end
    lo = padded ? big(2) : max(big(2), big(10)^(width - 1))
    hi = big(10)^width - 1
    hi - lo + 1 <= c.max_bases || throw(ArgumentError(
        "too many bases: provide bases=[...] or explicitly increase max_bases"))
    hi <= typemax(Int) || throw(ArgumentError("bases must fit Int"))
    return Int(lo):Int(hi)
end

"""Exact necessary-condition table, before evaluating the digit expression."""
function candidate_table(c::Config, widths)
    if c.distinct_digits && c.ndigits > length(unique(c.allowed_digits))
        return Candidate[] # pigeonhole principle, independent of the grammar
    end
    lo = big(10)^(c.ndigits - 1)
    hi = 10lo - 1
    candidates = Candidate[]
    for b in base_domain(c, widths[1])
        a, g = primitive_base(b)
        number, h = big(1), 0
        while number <= hi ÷ a
            number *= a
            h += 1
            number < lo && continue
            text = string(number)
            ds = [Int(ch - '0') for ch in text]
            all(d -> d in c.allowed_digits, ds) || continue
            blocks = BigInt[]
            start = c.root_digits + 1
            valid = true
            for w in widths
                if !c.leading_zeros_in_blocks && w > 1 && ds[start] == 0
                    valid = false
                    break
                end
                push!(blocks, parse(BigInt, text[start:start+w-1]))
                start += w
            end
            valid && blocks[1] == b || continue
            for r in unique(c.roots)
                if c.root_digits > 0
                    length(string(r)) == c.root_digits || continue
                    text[1:c.root_digits] == string(r) || continue
                end
                numerator = BigInt(r) * h
                numerator % g == 0 || continue
                e = numerator ÷ g
                e <= typemax(Int) || throw(ArgumentError("required exponent exceeds Int"))
                push!(candidates, Candidate(copy(number), r, Int(e), ds, blocks))
            end
        end
    end
    sort!(candidates; by = x -> (x.number, x.root, x.exponent))
    return candidates
end

# S is the overflow state, representing every integer >= S.
# Only nonnegative integer operations occur, so this abstraction is exact.
function capped_power(a::Int, e::Int, S::Int, zero_to_zero::Symbol)
    a == 0 && e == 0 && return zero_to_zero == :one ? 1 : nothing
    e == 0 && return 1
    a == 0 && return 0
    a == 1 && return 1
    (a == S || e == S) && return S
    y = 1
    for _ in 1:e
        y > (S - 1) ÷ a && return S
        y *= a
    end
    return min(S, y)
end

"""Evaluate the suffix after the outer base, preserving undefined powers."""
function capped_suffix(blocks, ops, S::Int, zero_to_zero::Symbol)
    t = Int(min(S, blocks[end]))
    for i in length(blocks)-1:-1:2
        a = Int(min(S, blocks[i]))
        t = ops[i] == :^ ? capped_power(a, t, S, zero_to_zero) : (a >= S - t ? S : a + t)
        isnothing(t) && return nothing
    end
    return t
end

function as_matrix(rows, columns::Int)
    matrix = Matrix{Int}(undef, length(rows), columns)
    for i in eachindex(rows), j in 1:columns
        matrix[i, j] = rows[i][j]
    end
    return matrix
end

"""
Build a bounded CP model expressed in JuMP. HiGHS solves JuMP's MIP
reformulations of the MOI.Table constraints. The first table is written
explicitly with one-hot selectors so solutions can be enumerated cheaply.
"""
function build_model(c::Config = Config())
    widths, ops = grammar(c)
    candidates = candidate_table(c, widths)
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, c.time_limit)
    # Keep solver integers and table coefficients small. BigInt N never enters it.
    set_optimizer_attribute(model, "mip_feasibility_tolerance", 1e-9)
    m = length(candidates)
    if m == 0
        # HiGHS treats a zero-column model as invalid; keep an explicit
        # contradictory bounded variable so emptiness is reported INFEASIBLE.
        @variable(model, empty_candidate == 0)
        @constraint(model, empty_candidate >= 1)
        return (; model, config=c, candidates, widths, ops, selector=VariableRef[], cap=1)
    end
    C = maximum(x.exponent for x in candidates)
    C < 2^52 || throw(ArgumentError("required exponent is too large for the solver's integer representation"))
    S = C + 1
    @variable(model, selector[1:m], Bin)
    @constraint(model, sum(selector) == 1)
    @variable(model, 0 <= d[1:c.ndigits] <= 9, Int)
    if c.distinct_digits
        @constraint(model, d in MOI.AllDifferent(c.ndigits))
    end
    @variable(model, minimum(c.roots) <= r <= maximum(c.roots), Int)
    @variable(model, 1 <= E <= C, Int)
    # (r,E,digits) belongs to the precomputed exact candidate table.
    @constraint(model, r == sum(candidates[k].root * selector[k] for k in 1:m))
    @constraint(model, E == sum(candidates[k].exponent * selector[k] for k in 1:m))
    @constraint(model, [i=1:c.ndigits], d[i] == sum(candidates[k].digits[i] * selector[k] for k in 1:m))
    nblocks = length(widths)
    @variable(model, 0 <= block[1:nblocks] <= S, Int)
    @constraint(model, [i=1:nblocks], block[i] == sum(
        Int(min(S, candidates[k].blocks[i])) * selector[k] for k in 1:m))
    @variable(model, 0 <= t[2:nblocks] <= S, Int)
    @constraint(model, t[nblocks] == block[nblocks])
    @constraint(model, t[2] == E)

    total_rows = big(0)
    for i in 2:nblocks-1
        # Limit a table's first coordinate to values possible for this block.
        domain = sort!(unique(Int(min(S, x.blocks[i])) for x in candidates))
        total_rows += BigInt(length(domain)) * (S + 1)
        total_rows <= c.max_table_rows || throw(ArgumentError(
            "transition tables exceed max_table_rows; narrow the grammar or increase the limit"))
        rows = NTuple{3,Int}[]
        for a in domain, e in 0:S
            z = ops[i] == :^ ? capped_power(a, e, S, c.zero_to_zero) : min(S, a + e)
            isnothing(z) || push!(rows, (a, e, z))
        end
        # MOI's MIP bridge uses the model's Float64 coefficient type.
        # All these integer values are exactly representable at the checked cap.
        @constraint(model, [block[i], t[i+1], t[i]] in MOI.Table(Float64.(as_matrix(rows, 3))))
    end
    # Sorted candidate indices give smallest N first without large coefficients.
    @objective(model, Min, sum(k * selector[k] for k in 1:m))
    return (; model, config=c, candidates, widths, ops, selector, cap=C, d, r, E, block, t)
end

"""Recheck a returned assignment with integer arithmetic outside the MIP solver."""
function verify(x::Candidate, c::Config)
    widths, ops = grammar(c)
    1 <= x.exponent < typemax(Int) || return false
    length(string(x.number)) == c.ndigits || return false
    ds = [Int(ch - '0') for ch in string(x.number)]
    ds == x.digits && all(d -> d in c.allowed_digits, ds) || return false
    c.distinct_digits && !allunique(ds) && return false
    x.root in c.roots || return false
    if c.root_digits > 0
        string(x.root) == string(x.number)[1:c.root_digits] || return false
    end
    start = c.root_digits + 1
    blocks = BigInt[]
    for w in widths
        !c.leading_zeros_in_blocks && w > 1 && ds[start] == 0 && return false
        push!(blocks, parse(BigInt, string(x.number)[start:start+w-1]))
        start += w
    end
    blocks == x.blocks || return false
    isnothing(c.bases) || (blocks[1] in c.bases) || return false
    x.number^x.root == blocks[1]^x.exponent || return false
    S = max(2, x.exponent + 1)
    t = capped_suffix(blocks, ops, S, c.zero_to_zero)
    return t == x.exponent
end

"""
    expression(x::Candidate, config::Config)

Format an assignment with explicit right-associative parentheses and root
order. Configured block widths, including leading zeros, are preserved.
"""
function expression(x::Candidate, c::Config)
    widths, ops = grammar(c)
    tokens = [lpad(string(x.blocks[i]), widths[i], '0') for i in eachindex(widths)]
    result = tokens[end]
    for i in length(x.blocks)-1:-1:1
        result = "(" * tokens[i] * string(ops[i]) * result * ")"
    end
    return "root_$(x.root)($result) = $(x.number)"
end

"""
Enumerate solutions (smallest N first). `complete` is true only after
infeasibility proves there are no remaining candidates. Hitting a solution
limit or solver time limit leaves complete=false.
"""
function search_cp(c::Config = Config(); max_solutions::Int = 100)
    max_solutions >= 1 || throw(ArgumentError("max_solutions must be positive"))
    problem = build_model(c)
    solutions = Candidate[]
    complete = false
    status = MOI.OPTIMIZE_NOT_CALLED
    for _ in 1:max_solutions
        optimize!(problem.model)
        status = termination_status(problem.model)
        if status == MOI.INFEASIBLE
            complete = true
            break
        elseif status != MOI.OPTIMAL
            # A time-limited incumbent is not necessarily the smallest candidate.
            break
        end
        k = argmax(value.(problem.selector))
        x = problem.candidates[k]
        verify(x, c) || error("solver assignment failed the exact arithmetic check")
        push!(solutions, x)
        @constraint(problem.model, problem.selector[k] == 0)
    end
    return (; solutions, complete, status, candidates=length(problem.candidates), cap=problem.cap)
end

function nemo_prefix_candidates end

include("prefix.jl")
include("language.jl")
include("arithmetic.jl")
include("sweep.jl")
include("radix.jl")
include("modular.jl")
include("synthesis.jl")
include("spectrum.jl")

end # module
