# When one cost is not enough

Merging digits and adding plus signs are different ways to repair a tower.
The cheapest repair depends on how much each operation costs. A Pareto frontier
keeps every tradeoff: an expression survives if no other expression uses no
more of both operations and strictly fewer of at least one.

```julia
using DigitTowers

r = synthesize_frontier(4294967296; roots=[9], max_base_width=1)
[(c.concatenations, c.additions) for c in r.certificates]
# [(2, 6), (3, 5)]
all(verify, r.certificates)
# true
```

Here `4294967296 = 2^32`. Both ninth-root expressions have outer base `4`
and exponent `144`. They offer a real choice:

```math
4294967296
=\sqrt[9]{4^{2+9+49+67+2+9+6}}
=\sqrt[9]{4^{29+4+9+67+29+6}}.
```

The first expression joins two boundaries and adds six plus signs; the second
joins three boundaries and adds five plus signs. Exponentiation and addition
still follow the same right-associated grammar as `synthesize`; sums are
displayed without redundant parentheses because addition is associative.

## A repair that every weighted sum misses

Varying the scalar weights in `synthesize` does **not** necessarily reveal the
whole frontier. Consider `2199023255552 = 2^41`, with root six, outer base two,
blocks of at most three digits, and `^`/`+` in its exponent. Its exact frontier
is:

| Joined boundaries | Plus signs | Exponent expression |
|--:|--:|:--|
| 2 | 8 | `199+0+2+3+2+5+5+5+5^2` |
| 4 | 7 | `1+9+90+2+32+5+55+52` |
| 5 | 6 | `19+90+2+3+25+55+52` |

Each exponent equals `246`, so every expression evaluates to
`root_6(2^246) = 2^41`. The middle repair is nondominated, but it cannot minimize
any nonnegative weighted sum with at least one positive weight. Let `w` be the
cost of a join divided by the cost of a plus sign. To beat the first repair,
the middle one needs `w ≤ 1/2`; to beat the last, it needs `w ≥ 1`. These
conditions conflict. Setting either weight to zero selects an endpoint.

```julia
r = synthesize_frontier(2199023255552; roots=[6], max_base_width=1)
[(c.concatenations, c.additions) for c in r.certificates]
# [(2, 8), (4, 7), (5, 6)]
```

Such an unsupported tradeoff matters when the constraints are budgets rather
than prices. With at most four joins and seven plus signs, only the middle
repair is feasible. A scalar optimizer can miss that choice however its
weights are tuned.

## An exact chart of antichains

The arithmetic step is unchanged: write the outer base as `b=a^g` and require
the represented number to be `N=a^h`. For root `r`, the exponent must equal
`E=r*h/g`, an integer. The semantic suffix chart caps values at
`maximum(E)+1`, sharing its work across requested root orders.

For each suffix position and capped value, the chart stores an antichain of
`(joins, plus signs)` costs, with one deterministic witness per pair. Combining
a block with a suffix adds nonnegative costs coordinate by coordinate. A
dominated suffix can therefore never improve a future prefix: replacing it
with its dominator preserves the exact value and weakly improves both costs.
This proves that discarding dominated labels preserves every final Pareto
cost. Saturation still preserves zero, one, and undefined `0^0` exactly.

The result contains a flat `certificates` vector and `frontiers` grouped by
root and outer-base width. These groups optimize separately. Two different
roots or outer-base widths are not compared against each other. Every
certificate uses the existing `verify` and `expression` interfaces; its
`cost` field is simply `concatenations + additions`.

`states` counts retained Pareto labels across all suffix charts;
`value_states` counts semantic `(position,value)` cells. `max_states` bounds
the labels, which may be more numerous than scalar chart states. An explicit
limit violation throws an error. A returned `complete=true` applies to the
specified finite grammar and all requested roots. Equal-cost syntactic
variants are represented by one witness, rather than enumerated.

## Census

For 2–30 decimal digits, external roots 2–9, blocks of at most three digits,
no leading zeros in blocks, and forbidden `0^0`, the complete census gives:

| Quantity | Count |
|:--|--:|
| Arithmetically possible numbers | 67 |
| Representable numbers | 52 |
| Feasible root/base-width pairs | 191 |
| Pairs with multiple nondominated costs | 112 |
| Nondominated certificates | 442 |
| Unsupported Pareto points | 19 |
| Semantic chart states | 57,063 |
| Pareto labels | 124,838 |

The represented numbers match the scalar synthesis census; the extra output
describes choices that a single cost hides. Unsupported points were checked
with exact rational inequalities, including ties, rather than a finite grid
of trial weights.

```sh
julia --project=. research/pareto_experiments.jl
```

`research/results/pareto_census.tsv` records every witness and whether a
weighted objective can support its cost. `pareto_metadata.toml` gives the
full search domain. Tests independently enumerate digit partitions and
operator strings, evaluate their values, and discard dominated costs only
after that exhaustive enumeration.
