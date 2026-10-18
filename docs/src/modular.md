# Towers as a dynamical system

Replace equality with agreement in the last ``L`` digits, and drop the outer
root. For a fixed radix ``b`` define

```math
F_{b,L}(N)=\mathrm{tower}(\mathrm{digits}_{b,L}(N))\bmod b^L.
```

Here ``\mathrm{digits}_{b,L}`` returns exactly ``L`` digits, padding with
leading zeros. This makes a finite map on ``0\le N<b^L``; with the default
`0^0` rule, some evaluations are undefined. It turns the original puzzle into
two new questions: which numbers reproduce their last digits, and which
numbers return after several iterations?

## A two-cycle and a five-cycle

Complete decimal searches find no fixed points of lengths 2–5. There are
nontrivial cycles:

```math
456\longrightarrow624\longrightarrow456
```

because ``4^{5^6}\equiv624\pmod{1000}`` and
``6^{2^4}\equiv456\pmod{1000}``. At four digits the complete nontrivial cycle is

```math
3456\longrightarrow8481\longrightarrow6256\longrightarrow3936
\longrightarrow6483\longrightarrow3456.
```

These bounded results come from evaluating **every state and every edge**.
A basin includes the cycle itself and all initial words eventually reaching it.

| Width | States | Nontrivial cycle lengths | States in cycle basins | Eventually undefined |
|:--|--:|:--|--:|--:|
| 2 | 100 | None | 0 | 100 |
| 3 | 1,000 | 2 | 40 | 960 |
| 4 | 10,000 | 5 | 156 | 9,844 |
| 5 | 100,000 | None | 0 | 100,000 |

With `zero_to_zero=:one`, every state has a successor. At width three, the
additional cycles are `000 → 000` and `001 → 001`; at width four, `0000 ↔ 0001`
appears and the five-cycle's basin grows from 156 to 157. The convention changes
the global dynamics, including which cycle a starting word eventually reaches.

```julia
tower_mod([4,5,6], 1000)              # 624
modular_fixedpoints(5).solutions     # Int[]
modular_dynamics(3).cycles           # [[456, 624]]
modular_dynamics(4).basin_sizes      # [156]
modular_dynamics(4; zero_to_zero=:one)
```

## Change the numeral system

Other radices have fixed points that decimal lacks within these bounds:

| Word | Radix | Decimal value | Identity or congruence |
|:--|--:|--:|:--|
| `24` | 6 | 16 | ``2^4=16`` |
| `33` | 8 | 27 | ``3^3=27`` |
| `2431` | 5 | 366 | ``2^{4^{3^1}}=2^{64}\equiv366\pmod{625}`` |
| `3373` | 8 | 1,787 | ``3^{3^{7^3}}\equiv1787\pmod{4096}`` |
| `369` | 12 | 513 | ``3^{6^9}\equiv513\pmod{1728}`` |

```julia
modular_fixedpoints(2; radix=8).solutions # [27], whose octal word is 33
modular_fixedpoints(4; radix=5).solutions # [366], whose base-five word is 2431
```

`modular_fixedpoints` normally excludes leading zeros; set `padded=true` to
include every fixed-width word. `modular_dynamics` always pads, so an iterate
that becomes shorter remains in the same finite state space. Both functions
refuse a domain larger than `max_states=100_000` unless explicitly configured.
The full graph costs linear storage and one modular tower evaluation per state.

## Exact modular evaluation

Plain Euler reduction is insufficient: ``2^{2^3}\bmod8=0``, but replacing its
exponent by ``8\bmod\varphi(8)=0`` incorrectly gives one. The implementation
uses a totient chain and retains an exact small/large flag for every suffix.
For a suffix exponent ``E``:

```math
a^E\bmod m=
\begin{cases}
a^E\bmod m,&E<\varphi(m),\\
a^{\varphi(m)+(E\bmod\varphi(m))}\bmod m,&E\ge\varphi(m).
\end{cases}
```

The first case keeps the exact small exponent. For the second, consider each
prime power ``p^k\mid m``. If ``p\nmid a``, Euler's theorem supplies a period
dividing ``\varphi(m)``. If ``p\mid a``, both exponents are at least ``k`` and
both residues vanish modulo ``p^k``: indeed
``\varphi(m)\ge\varphi(p^k)\ge k``. The Chinese remainder theorem then gives
the equality modulo ``m``. Thus the exponent lift is safe even for noncoprime
bases.

The flags are obtained by capping every suffix at ``\max(2,m)`` with exact
integer operations. All nested powers are checked before returning a residue,
including when an outer base is zero or one or the modulus is one. The final
power uses Julia's [`powermod`](https://docs.julialang.org/en/v1/base/math/#Base.powermod).
The test suite also implements an independent prime-power oracle using
valuations for nonunits and CRT reconstruction; it agrees on long towers.

Large moduli use `BigInt`, with an explicit primality-certification limit.
Every factorization in the totient chain is checked by reconstructing its input;
each prime factor is then verified by Primes.jl's deterministic
machine-integer primality test. Factors exceeding `typemax(Int)` cause an
`ArgumentError`, because the package does not equate a probable-prime test with
a proof. Arbitrarily large smooth moduli such as ``2^{100}`` and ``10^{100}``
are supported; a large prime modulus may require a separate primality-proof
backend. Factoring an otherwise supported modulus can still be expensive.

Run `julia --project=. research/modular_experiments.jl` to reproduce the tables.
Machine-readable results are saved in `research/results/modular_fixedpoints.tsv`
and `research/results/modular_dynamics.toml`. These are complete searches within
the stated bounds, with no claim about all lengths.

The full Julia interface is listed in the [API](@ref).
