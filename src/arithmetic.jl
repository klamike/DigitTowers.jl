"""
    search(config=Config(); method=:prefix, max_solutions=100)

Enumerate solutions in numerical order with an exact arithmetic backend or
the original JuMP constraint model. Methods:

* `:prefix` (default): exact integer logarithms locate the only possible power
  in each leading-digit interval; no optimizer or full power sweep.
* `:direct`: enumerate primitive powers, then evaluate each candidate suffix
  directly with capped integer arithmetic; no optimizer.
* `:cp`: build and enumerate the JuMP/HiGHS table-constraint model.
* `:nemo`: use the prefix algorithm with Nemo/FLINT's exact integer logarithm;
  requires loading the optional Nemo package before calling `search`.

`complete=true` certifies exhaustion of the configured finite search. A
solution-count limit, or a CP solver time limit, leaves it false. Every
reported result is verified with integer arithmetic. The result's `method`
identifies the backend. Config's `time_limit` and `max_table_rows` apply to CP;
arithmetic methods do not build tables and are not subject to a solver timer.
"""
function search(c::Config=Config(); method::Symbol=:prefix, max_solutions::Int=100)
    max_solutions >= 1 || throw(ArgumentError("max_solutions must be positive"))
    if method == :cp
        result = search_cp(c; max_solutions)
        return (; result..., method)
    end
    method in (:prefix, :direct, :nemo) || throw(ArgumentError(
        "unknown method=$method; use :prefix, :direct, :cp, or :nemo"))
    widths, ops = grammar(c)
    if method == :nemo && !hasmethod(nemo_prefix_candidates, Tuple{Config,typeof(widths)})
        throw(ArgumentError("method=:nemo requires loading Nemo first (using Nemo)"))
    end
    candidates = method == :direct ? candidate_table(c, widths) :
                 method == :nemo ? nemo_prefix_candidates(c, widths) :
                 prefix_candidates(c, widths)
    solutions = Candidate[]
    complete = true
    for x in candidates
        c.distinct_digits && !allunique(x.digits) && continue
        x.exponent < typemax(Int) || throw(ArgumentError("exponent exceeds capped arithmetic range"))
        S = max(2, x.exponent + 1)
        capped_suffix(x.blocks, ops, S, c.zero_to_zero) == x.exponent || continue
        verify(x, c) || error("arithmetic assignment failed the exact integer check")
        push!(solutions, x)
        if length(solutions) == max_solutions
            complete = false
            break
        end
    end
    return (; solutions, complete, status=complete ? MOI.OPTIMAL : MOI.SOLUTION_LIMIT,
            candidates=length(candidates), cap=maximum((x.exponent for x in candidates); init=1), method)
end
