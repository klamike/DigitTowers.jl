# Reorder the digits

The original puzzle fixes the digit order. An anagram version keeps the
target integer fixed but lets its digits trade places inside the tower:

```math
\sqrt{4^6}=64, \qquad \sqrt[9]{5^{6^2}}=625.
```

Every digit is still used exactly once. Root orders are external; they do
not consume digits. Digits form individual bases and exponents, with no
concatenation or addition. All powers associate to the right, and every
nested power must be defined.

```julia
result = anagram_towers(625; roots=2:9)
x = only(result.certificates)
@assert x.digits == [5,6,2]
@assert x.moves == 3
@assert verify(x)
println(expression(x)) # root_9((5^(6^2))) = 625
```

`moves` counts changed positions relative to the original numeral. It does
not count swaps. The solver minimizes this distance separately for each
feasible `(root, leading base)`, with a deterministic lexicographic tie
break. For `262144`, the ordinary square-root witness has distance zero;
changing two positions also produces the fourth-root witness
`4^(6^(2^(1^(2^4))))`.

## An exact classification with distinct digits

With roots in `2:9`, the complete list of distinct-digit decimal targets,
allowing arbitrary digit order, is:

| Target | Root | Tower digits | Changed positions |
|:--|--:|:--|--:|
| 64 | 2 | `4,6` | 2 |
| 625 | 9 | `5,6,2` | 3 |
| 78125 | 7 | `5,7,2,1,8` | 5 |
| 390625 | 8 | `5,2,6,3,0,9` | 6 |

This claim covers **every decimal length** under these rules: distinct
digits imply at most ten positions. The exhaustive arithmetic census covers
lengths `2:12`, including all lengths up to ten. The first two examples also
avoid both zero and one. The root order remains essential: `625` uses root
nine, rather than the original square root.

Across all targets with `2:12` digits, the same census finds 15 numbers and
22 minimum-distance certificates for roots `2:9`. Fourteen numbers need
reordering; only `262144` already has a witness in its original order. The
square-root targets are `64`, `262144`, and `152587890625`. The final example
uses the permutation `5,2,5,1,8,7,8,9,0,6,2,5` and changes four positions.

The root-free version is configurable as `roots=[1]`. Its smallest example
is simply `5^2=25`. The complete distinct-digit root-free list, again over
every decimal length, is `25`, `4096`, `19683`, `78125`, `390625`, and
`5764801`. For example, the digits of `4096` give `4^(6^(9^0))=4096`.
The root-free census finds 14 numbers through twelve digits and records
their witnesses in `research/results/anagram_rootfree.tsv`.

Reproduce the census with:

```sh
julia --project=. research/anagram_experiments.jl
```

The saved tables are `research/results/anagram_census.tsv` and
`research/results/anagram_metadata.toml`. They record 102 candidate numbers,
921 arithmetic `(root, base)` targets, and 96,699 semantic chart states. The
two- and three-digit examples are useful reminders that changing the rules
can make a difficult original puzzle much easier.

## Search digit bags, rather than permutations

If the tower begins with digit ``b=a^g``, where ``a`` is not itself a perfect
power, unique factorization forces the target to be ``N=a^h``. For external
root ``r``, the required suffix is exactly

```math
E=\frac{rh}{g}.
```

A fractional ``E`` rejects that `(root, base)` immediately. A base not
present among the digits is also impossible. The one-digit base restriction
leaves only primitive bases `2,3,5,6,7`, so the census enumerates their powers
and does not scan every decimal numeral.

For each remaining digit multiset, the dynamic program stores reachable
suffix values and their cheapest arrangements. A state is

```math
((c_0,c_1,\ldots,c_9),\min(\text{suffix value},S)),
```

where ``c_d`` is the number of copies of digit ``d`` and ``S`` is one more
than the largest target suffix for that leading base. Prepending digit
``d`` replaces value ``v`` by ``\min(d^v,S)``. This operation handles zero,
one, and the chosen `0^0` convention before applying saturation. Undefined
suffixes never become valid merely because a one is prepended.

All orders that reach the same state have the same available digits and the
same effect on any future prefix. Their future costs also agree: the number
of used digits determines the positions already assigned. Keeping only the
lowest-distance arrangement therefore preserves an optimum for every root
target. Root orders for one leading base share a chart.

The count-vector lattice has at most ``\prod_d(c_d+1)`` cells, with at most
``S+1`` semantic values in each. Repeated digits are merged from the start;
there is no factorial permutation loop. The lattice can still grow rapidly.
`max_states` and `max_exponent` are explicit resource guards, and exceeding
either throws an error. A returned result has `complete=true` for its finite
multiset and supplied roots. Independent tests enumerate literal
permutations for small targets and compare both feasibility and the minimum
changed-position witnesses.
