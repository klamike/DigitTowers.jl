# Towers form a language

A surprisingly small piece of automata theory explains when a tower is
even defined. For a right-associated tower of nonnegative integer tokens,
with `0^0` forbidden:

```math
\text{the tower is defined}\quad\Longleftrightarrow\quad
\text{no two adjacent tokens are zero}.
```

For an adjacent pair `0,0`, the inner zero either produces zero or is already
undefined. The outer zero therefore encounters `0^0` or an undefined exponent.
Conversely, in a word with no adjacent zeros, every zero is followed by a
positive-base suffix, which has a positive value whenever it is defined.
Induction from the final token proves all powers are defined. A one cannot
hide an undefined descendant.

```jldoctest; setup=:(using DigitTowers)
julia> tower_isdefined([2,1,0,0])
false

julia> tower_isdefined([2,0,1,0,2])
true

julia> tower_language_counts(3)
(defined = 891, undefined = 9, total = 900)
```

This applies to **tokens**, not necessarily characters. Grouping `100` into
one positive token is valid; the three-token tower `1^(0^0)` is undefined.
Addition changes the grammar, so the forbidden-pair criterion alone does
not decide a mixed expression's validity.

## Count enormous search spaces without searching them

For radix ``q``, let ``a_L`` count words ending in a nonzero digit and ``z_L``
count words ending in zero. Extending a valid word gives

```math
\begin{pmatrix}a_{L+1}\\z_{L+1}\end{pmatrix}
=\begin{pmatrix}q-1&q-1\\1&0\end{pmatrix}
\begin{pmatrix}a_L\\z_L\end{pmatrix}.
```

The initial vector is ``(q-1,0)`` when leading zeros are forbidden, and
``(q-1,1)`` for all fixed-width words. Binary matrix exponentiation computes
the exact counts with ``O(\log L)`` matrix products. It does not enumerate
the ``q^L`` strings.

Only about **0.0102%** of 1000-digit decimal numerals have a defined tower
under this convention. This is a count of all numerals, not a probability
model for the structured primitive powers used by our search.

```julia
counts = tower_language_counts(1000)
@assert counts.defined + counts.undefined == 9big(10)^999
Float64(counts.defined // counts.total) # approximately 0.0001018573
```

Defining `0^0=1` makes every nonnegative-token tower defined. That seemingly
local choice therefore changes an entire formal language.

## Link the language to dynamics

The language count predicts how many states of [`modular_dynamics`](@ref)
are undefined on their **next** step. It does not predict the basin of
states that become undefined after several iterations.

At decimal width three, 981 of the 1000 padded words are initially defined.
Nevertheless, 960 states eventually reach undefined; the other 40 flow into
the cycle ``456\leftrightarrow624``. A largely defined one-step map can have
a very small surviving basin.

```julia
graph = modular_dynamics(3)
language = tower_language_counts(3; leading_zero=true)
@assert graph.undefined == language.undefined == 19
@assert graph.undefined_basin == 960
```

The same criterion is also a cheap search sieve. The single-digit `sweep`
rejects undefined words before allocating arbitrary-precision suffix tokens,
while preserving its original candidate counts and completeness semantics.

Reproduce exact word counts and a profile of primitive-power candidates with:

```sh
julia --project=. research/language_experiments.jl
```
