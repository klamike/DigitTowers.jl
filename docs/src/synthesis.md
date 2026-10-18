# Teach the solver the grammar

`search` answers “does this particular partition work?” `synthesize` answers
“what is the cheapest partition and placement of plus signs that makes these
digits work?” It searches every expression in a finite grammar while merging
parses that have the same semantic value. A 60-digit input does not require
enumerating its exponentially many digit partitions.

```julia
using DigitTowers

result = synthesize(678223072849;
    roots=[6], root_digits=1, allow_addition=true)
x = only(result.certificates)
expression(x)
# root_6((7^(82+(2^(3^(0^(7^(2^(8^(4^9)))))))))) = 678223072849
x.cost, x.concatenations, x.additions
# (2, 1, 1)
verify(x)
# true
```

The transcript's final expression is optimal under this grammar: one deleted
digit boundary (`8|2` becomes `82`) and one plus sign. Its expression is found
automatically, including all the other partition choices. With addition
disabled this input has no representation in the default grammar.

## Some low-cost discoveries

The default cost charges one per deleted digit boundary and one per `+`.
Exponentiation is free. The following minima allow blocks of up to three
digits, including the outer base, forbid leading zeros in blocks, associate
operators to the right, and forbid `0^0`.

| Number | Root | Minimum cost | Changes |
|:--|--:|--:|:--|
| `256` | 7 | 1 | concatenate `56` |
| `262144` | 2 | 0 | original rules |
| `8388608` | 6 | 2 | concatenate `38`, add one `+` |
| `94143178827` | 6 | 2 | add two `+`, keep every digit separate |
| `59604644775390625` | 4 | 2 | concatenate `96`, add one `+` |
| `4611686018427387904` | 2 | 2 | concatenate `61`, add one `+` |

For example, the first new identity is short enough to see in full:

```math
8388608 = \sqrt[6]{8^{\,38+8^{6^{0^8}}}}.
```

The digit-only example is zero-free:

```math
94143178827
=\sqrt[6]{9^{\,4+\left(1+4^{3^{1^{7^{8^{8^{2^7}}}}}}\right)}}.
```

Its exponent is `4+1+64=69`, and the number is `3^23`. A `1` makes the
remaining exponent tower irrelevant to its value, while every operation
remains defined. Synthesizing identities this way makes the puzzle's blockers
visible: many long apparent towers carry little effective arithmetic.

A complete census over **2–30 decimal digits**, external roots **2–9**, and
the three-digit-block grammar finds **52 distinct numbers**, with **191
minimum-cost certificates** across root/base-width pairs. Fourteen numbers
have square-root representations. Only six root/base-width pairs have cost
at most two: exactly those in the table. These are bounded experimental
results, not unrestricted uniqueness claims.

The census starts from just **67 arithmetically possible numbers**, covering
509 root/base-width targets. Its dynamic programs store 57,063 states in
total. Reproduce it with:

```sh
julia --project=. research/synthesis_experiments.jl
```

The machine-readable witnesses and full grammar metadata are saved in
`research/results/synthesis_census.tsv` and `synthesis_metadata.toml`.
`synthesis_examples.tsv` also includes the consumed-root example and the
60-digit square-root example, whose minimum cost is two digit merges.

The solver can also simplify an existing construction. With seven-digit
blocks allowed, the transcript's 20-digit example needs **12 merges**, three
fewer than its supplied partition: the terminal block `8952` can be expanded
to `8|9|5|2` without changing the value.

```julia
x = only(synthesize(big"31622786796633508952";
    max_block_width=7).certificates)
expression(x)
# root_2((3162278^(6^(7966335^(0^(8^(9^(5^2)))))))) = 31622786796633508952
x.cost
# 12
```

## How it works

First, a candidate outer prefix must satisfy `N^r = b^E`. Write `b=a^g`
with primitive base `a`; an exact power comparison checks whether `N=a^h`.
If so, the only possible exponent is `E=r*h/g`, and it must be integral.
This removes the need to guess a tower's astronomical value.

For that exponent, put `S=E+1` and use semantic states `0,1,…,E,S`. The last
state means “at least `S`.” All operations are nonnegative integer addition
and exponentiation, so this quotient preserves their results exactly, with
undefined `0^0` handled separately. In particular it preserves reductions
such as `a^0=1`, `0^positive=0`, and `1^anything=1`, even when another operand
has saturated.

When several root orders are requested, one chart uses `S=maximum(E)+1` and
answers all their exponent targets. It preserves each smaller target exactly
and avoids parsing the same digit suffix again for each root.

The suffix chart stores

```math
D[i,v]=\text{minimum cost of a suffix starting at digit }i
\text{ with saturated value }v.
```

For every allowed block beginning at `i`, combine it with each suffix state
after that block using either `^` or `+`. A terminal block supplies the base
case. Each transition adds its deleted boundaries and optional plus-sign
cost. Retaining only the cheapest parse for `(i,v)` is safe: every possible
prefix sees the same value and adds the same cost. This is dynamic programming
over a weighted grammar, rather than enumeration of every syntactic partition.

There are at most `m*(E+2)` value states for an `m`-digit suffix. Transition
counts scale with that bound, the permitted block width, and the number of
operators; storing and copying concrete witnesses adds overhead. The method
does not materialize gigantic tower integers. `max_states` and `max_exponent`
are explicit guards: exceeding one throws an error instead of returning an
apparently complete search.

## Change the experiment

```julia
# Prefer a few plus signs to expensive digit merges, or vice versa.
synthesize(678223072849; roots=[6], root_digits=1, allow_addition=true,
    cost_weights=(concatenation=4, addition=1))

# Search for a repair that keeps every digit separate.
synthesize(94143178827; roots=[6], max_block_width=1,
    allow_addition=true)

# Allow longer exponent blocks while restricting the outer base.
synthesize(262144; max_block_width=6, max_base_width=1)
```

The grammar preserves digit order, uses contiguous blocks, and requires an
outer power. It permits right-associated `^` and optionally `+` in the
exponent; subtraction, multiplication, arbitrary parentheses, reordered
digits, and roots inside the suffix are separate research problems.
One optimum is returned per feasible `(root, outer-base width)`, rather than
every tied expression or a Pareto frontier. Weighted costs let you explore
different preferences without changing the exactness guarantee.

The full Julia interface is listed in the [API](@ref).
