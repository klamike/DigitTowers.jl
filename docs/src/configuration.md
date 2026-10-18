# Configuration

Each [`Config`](@ref) defines one finite search: a decimal length, a set of root
orders, and a fixed expression grammar. Defaults reproduce the original
six-digit square-root puzzle.

| Field | Default | Meaning |
|:--|:--|:--|
| `ndigits` | `6` | Decimal length of the answer; at least two |
| `roots` | `[2]` | Allowed positive integer root orders |
| `allowed_digits` | `collect(0:9)` | Digits allowed throughout the answer, including a consumed root prefix |
| `distinct_digits` | `false` | Require every answer digit to be different |
| `root_digits` | `0` | Number of leading digits consumed as the root order |
| `block_widths` | `nothing` | Widths of the remaining tokens, including the outer base; `nothing` means single digits |
| `operators` | `nothing` | Operators joining blocks; `nothing` means all `:^` |
| `leading_zeros_in_blocks` | `false` | Allow zero-padded grouped tokens |
| `zero_to_zero` | `:forbid` | Use `:one` to permit `0^0=1` |
| `bases` | `nothing` | Optional explicit list of allowed outer bases |
| `max_bases` | `100_000` | Maximum number of bases enumerated in preprocessing |
| `max_table_rows` | `1_000_000` | CP transition-table row budget |
| `time_limit` | `60.0` | CP seconds per solver call; excludes preprocessing |

The search backend is a keyword to [`search`](@ref), rather than a grammar
field: `method=:prefix` is the default, with `:direct`, `:cp`, and optional
`:nemo` alternatives. All four search the same configured expression set.
See [Performance](performance.md) for their algorithms and timings.

## Lengths, digits, and roots

```julia
using DigitTowers

search(Config(ndigits=10))
search(Config(ndigits=8, allowed_digits=collect(1:9))) # no zeros
search(Config(ndigits=8, allowed_digits=collect(2:9))) # no zeros or ones
search(Config(ndigits=8, distinct_digits=true))
search(Config(ndigits=8, roots=collect(2:9)))
```

`roots=[2]` specifies an external square root. Its implied `2` does not
consume a digit from the answer. Root order one is permitted.

`distinct_digits=true` requires all answer digits to differ, including any
consumed root prefix. CP expresses this with `AllDifferent`; arithmetic methods
check it directly. Such an answer can have at most ten digits, or fewer if
`allowed_digits` restricts the available set.

To use answer digits as the root index, set `root_digits`. For example,
`root_digits=1, roots=collect(2:9)` consumes the first digit as the root order;
the outer base begins at the second digit. For a longer root prefix, its
decimal width must match `root_digits`. At least two blocks must remain.

For several lengths in the single-digit grammar, use [`sweep`](@ref):

```julia
result = sweep(2:100; roots=collect(1:9))
```

It evaluates each candidate's suffix once and derives its possible root order.
The same digit restrictions, distinctness requirement, root-prefix rule, and
zero convention are available as keywords. Its candidate count measures
distinct numbers before suffix evaluation, rather than one assignment per
root; `cap` is the largest target-exponent bound used.

For grouped or mixed-operator grammars, use separate configurations:

```julia
results = [search(Config(ndigits=L)) for L in 2:8]
```

## Grouping and addition

Block widths must be positive and sum to `ndigits-root_digits`. Their number
is at least two. There is one operator between each pair of blocks; supported
operators are `:^` and `:+`, and the first must be `:^`.

```julia
Config(ndigits=3, roots=[7], block_widths=[1, 2])
# Blocks 2 | 56 can produce root_7(2^56) = 256.
```

Every operator associates to the right, including mixed operators. Use the
parentheses produced by [`expression`](@ref), rather than Julia's ordinary
precedence rules, to read an answer.

The transcript's final example uses this grammar:

```julia
config = Config(
    ndigits=12,
    roots=[6],
    root_digits=1,
    block_widths=[1, 2, 1, 1, 1, 1, 1, 1, 1, 1],
    operators=[:^, :+, :^, :^, :^, :^, :^, :^, :^],
)
result = search(config)
```

The answer `678223072849` partitions as a root digit `6`, followed by
`7 | 82 | 2 | 3 | 0 | 7 | 2 | 8 | 4 | 9`. Its effective outer exponent is
``82+2=84``:

```math
\sqrt[6]{7^{\,82+2^{3^{0^{7^{2^{8^{4^9}}}}}}}}
=7^{14}=678223072849.
```

Grouping and operator placement are fixed inputs. To search their possible
placements, enumerate those choices outside `search`.

## Zeros

Single zero digits are always permitted when they belong to `allowed_digits`.
The leading-zero option applies to grouped tokens such as `003`, whose value
is three. It also permits a padded outer-base token following a consumed root
prefix. The answer itself never has a leading zero. Printed expressions retain
the configured block widths.

The `zero_to_zero` option applies throughout the expression, including inside
tails whose numerical value would otherwise be hidden by a one. Its default
is `:forbid`; choose `:one` explicitly to adopt the alternate convention.

## Enumeration and resource limits

```julia
result = search(Config(); max_solutions=100)
```

Answers are ordered by increasing number, then root order. The result contains:

| Field | Meaning |
|:--|:--|
| `solutions` | Verified `Candidate` objects |
| `complete` | Whether the backend exhausted this configuration |
| `status` | MathOptInterface termination status; interpreted by backend below |
| `candidates` | Number of necessary-condition candidates before suffix constraints |
| `cap` | Largest candidate outer exponent, or one when there are no candidates |
| `method` | Backend used: `:prefix`, `:direct`, `:cp`, or `:nemo` |

After complete arithmetic enumeration, `status` is `OPTIMAL`, including when
there are no answers. After complete CP enumeration it is `INFEASIBLE`: the
answers found earlier have been excluded, and no others remain.
Hitting `max_solutions` leaves
`complete=false`, even if that limit happens to equal the true answer count.
A CP solver time limit also leaves it false. A time-limited CP incumbent is
not returned because it may break the ordering guarantee.

For `method=:cp`, `time_limit` applies separately to each optimization call, not to the entire
enumeration. Candidate generation and model construction run before those
calls. `max_table_rows` counts potential transition rows conservatively,
including entries subsequently omitted for forbidden `0^0`.
Arithmetic methods build no tables and have no solver timer; neither setting
limits them. `max_bases` applies to all methods.

For large grouped bases, restrict `bases` explicitly:

```julia
config = Config(
    ndigits=20,
    roots=[2],
    bases=[3162278],
    block_widths=[7, 1, 7, 1, 4],
)
# Includes root_2(3162278^(6^(7966335^(0^8952))))
# = 31622786796633508952.
```

To use Nemo's exact integer logarithms, install Nemo in the active environment,
load it with `using Nemo`, and pass `method=:nemo`. Its package extension
activates automatically; Nemo is not a dependency of the default methods.

Bases must fit Julia's `Int` and the first block's width; a shorter base can
be zero-padded when that is permitted. Root orders and candidate exponents
must fit the implementation's checked integer ranges: roots are below
``2^{52}``, arithmetic exponents fit below `typemax(Int)`, and CP exponents
are below ``2^{52}`` so solver coefficients are represented exactly.
Oversized domains or tables cause explicit errors. Raising a limit
increases the permitted work; it does not change the mathematical rules.

All answer digits are stored. This implementation targets practical bounded
searches; very long answers, many grouped bases, or large root orders can make
preprocessing, tables, or exact verification expensive.
