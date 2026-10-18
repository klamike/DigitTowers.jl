# Almost fixed digit towers

When a bounded fixed-point search finds nothing, the nearest misses make a
different puzzle. For the [modular tower map](modular.md),

```math
F_{b,L}(N)=\mathrm{tower}(\mathrm{digits}_{b,L}(N))\bmod b^L,
```

how close can ``F_{b,L}(N)`` come to ``N``? [`modular_nearpoints`](@ref) solves
two exact optimization problems over a finite input domain:

- **Hamming distance** counts positions where the two width-``L`` digit words differ.
- **Circular distance** is ``\min(|F(N)-N|,b^L-|F(N)-N|)``. It treats the residues
  ``0`` and ``b^L-1`` as neighbors.

The minimum is zero precisely when the domain contains a modular fixed point.
Leading input zeros are excluded by default; output words always retain their
full width. Thus `5625 → 0625` changes one position, although the image is
numerically smaller than a four-digit positive integer.

## The three-digit gap

The closest ordinary decimal three-digit input is **uniquely** `971 → 969`,
at circular distance two. No such input comes within one of its image modulo
1000. This witness is small enough to check literally:

```math
9^{7^1}=9^7=4782969\equiv969\pmod{1000}.
```

```jldoctest; setup=:(using DigitTowers)
julia> result = modular_nearpoints(3; metric=:circular);

julia> only(result.minimizers)
(number = 971, successor = 969, distance = 2)

julia> result.search_complete && result.complete
true
```

Exclude both zero and one from the input and the gap grows to **six**. The
unique minimizer is `975 → 969`, since ``7^5=16807`` and
``9^{16807}\equiv969\pmod{1000}``. The digit restriction applies to the input,
not to subsequent iterates or the image's digits.

```julia
modular_nearpoints(3; metric=:circular, allowed_digits=2:9)
```

These are exhaustive results for these finite domains. Neighboring lengths
behave differently:

| Decimal width | Minimum circular distance | All minimizing edges |
|:--|--:|:--|
| 2 | 1 | `27 → 28` |
| 3 | 2 | `971 → 969` |
| 4 | 1 | `6495 → 6496`, `7650 → 7649` |
| 5 | 1 | `67937 → 67936`, `88735 → 88736` |

All use nonzero leading input digits, arbitrary remaining digits, and the
default forbidden `0^0`. Changing the convention changes the domain of the
map and can change the optimum.

## One-digit repairs and dynamics

Visual closeness is a separate question from numerical closeness. At width
three, the minimum Hamming distance is one, attained by 18 inputs. Eight of
those inputs avoid both zero and one:

```text
337 → 387     426 → 456     525 → 625     666 → 656
826 → 896     866 → 856     898 → 808     979 → 969
```

The edge `426 → 456` repairs one digit and enters the two-cycle
``456\leftrightarrow624``. A near-fixed input can lead to a periodic orbit;
it need not converge to a fixed point. The [orbit search](orbits.md) follows
individual trajectories without building the whole graph.

## A streaming exact search

The search enumerates the eligible input words, evaluates each tower modulo
``b^L``, and retains the current best distance and witnesses. A residue sieve
can reject an input before evaluating its full image. Put
``m=b^{\lfloor L/2\rfloor}``. The circular distance between ``F(N)\bmod m`` and
``N\bmod m`` is a lower bound on their distance modulo ``b^L``: every signed
difference representing the full residue also represents its residue modulo
the divisor ``m``. For Hamming distance, mismatches in the low-order half of
the digits are a lower bound on the full count. A bound strictly above the
incumbent cannot supply a minimizer; equality is retained so every tie counts.

The implementation caches both Euler-totient chains and avoids the extra
residue evaluation while its bound cannot reject anything. At decimal width
five, the Hamming search rejects 56,466 of the 87,480 defined inputs this way;
only 31,014 full-modulus images are needed. The circular search rejects 48,369.
These are counts of avoided full evaluations, not a measured speedup.

The search does not factor a fresh modulus for every word, construct huge
towers, or store all graph edges.
The working storage is ``O(L+\mathrm{limit})``, apart from the allowed-digit
set and totient chains;
the number of modular evaluations remains linear in the input domain.

`max_states=100_000` guards the full fixed-width state space before digit
restrictions. `limit` caps returned witnesses; it does **not** stop the search.
Consequently `minimum_distance` and `minimum_count` remain exact even when
there are too many minimizers to list. `search_complete` certifies exhaustion;
`complete` additionally says that every minimizer is returned. An all-undefined
or empty eligible domain has minimum `nothing` and an empty complete result.

```jldoctest; setup=:(using DigitTowers)
julia> short = modular_nearpoints(3; metric=:hamming, limit=1);

julia> (short.minimum_distance, short.minimum_count, length(short.minimizers))
(1, 18, 1)

julia> (short.search_complete, short.complete)
(true, false)
```

Reproduce the atlas with `julia --project=. research/nearby_experiments.jl`.
It contains 112 exhaustive searches in radices 2, 3, 5, 6, 8, 10, 12, and 16,
at widths 2–5 when ``b^L\le100000``, under both metrics and the two input digit
rules, skipping the empty `2:radix-1` alphabet at radix two. The saved minima
and counts are exact; up to 32 witnesses per search, re-evaluated with
`tower_mod`, appear in `research/results/nearby_examples.tsv`.
The unit tests additionally compare complete small domains against literal
integer towers, without modular exponent reduction.
