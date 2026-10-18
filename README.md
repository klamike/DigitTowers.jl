# DigitTowers.jl

Find numbers that reproduce themselves when their digits form a
right-associated power tower and an outer root is taken:

```math
\sqrt{2^{6^{2^{1^{4^4}}}}}=262144.
```

An exact Julia playground for digit puzzles: constraint programming, arithmetic
sieves, expression synthesis, other radices, and modular dynamics. The original
Julia/JuMP constraint model remains available.

## Try it

Requires Julia 1.12 or later. From this repository:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. examples/playground.jl
```

```julia
using DigitTowers

search(Config())                         # exact prefix search: 262144
search(Config(); method=:cp)             # original JuMP/HiGHS model
root_spectrum(2:1000)                    # all positive integer root orders
synthesize(94143178827; roots=[6],
    max_block_width=1, allow_addition=true)
modular_dynamics(3)                      # cycles of digit towers modulo 1000
```

## Things to explore

- **Remove the root bound.** Exactly three decimal solutions through 1000
  digits: `262144`, `4294967296`, and `3433683820292512484657849089281`.
  The latter two need enormous roots, certified symbolically by a
  [prime-valuation sieve](docs/src/spectrum.md).
- **Repair a number cheaply.** `94143178827` works with a sixth root and just
  two plus signs. [Dynamic programming](docs/src/synthesis.md) finds provably
  cheapest expressions in a configurable grammar.
- **Change the numeral system.** The zero-free base-22 numeral `F91A72A3`
  equals its own tower, without a root. There are also
  [infinite families and a radix/root dial](docs/src/radices.md).
- **Iterate the puzzle.** Padded three-digit towers modulo 1000 have the cycle
  `456 → 624 → 456`. [Exact modular evaluation](docs/src/modular.md) reveals
  cycles and their basins without constructing the towers.
- **Count before searching.** Defined towers form a
  [two-state language](docs/src/language.md); only about 0.0102% of
  1000-digit decimal numerals avoid an undefined nested `0^0`.

These results have explicit grammars and bounds. Research scripts and exact
certificates reproduce them; [earlier results and proofs](docs/src/results.md)
include the original square-root puzzle and grouped examples.

## Methods and configuration

`search` provides exact prefix, direct enumeration, JuMP/HiGHS CP, and optional
Nemo/FLINT backends. Primes.jl supplies factorization. A warmed 60-digit grouped
search took **22 μs with prefix search versus 152 ms with CP** on the recorded
machine. See [benchmarks and Julia package choices](docs/src/performance.md).

Digit restrictions, distinct digits, grouping, addition, consumed root prefixes,
and the `0^0` convention are configurable. See each method's grammar in the
[configuration guide](docs/src/configuration.md) and [API](docs/src/api.md).

## Documentation and tests

The Documenter.jl docs contain the [formulation](docs/src/formulation.md),
[configuration guide](docs/src/configuration.md), and [API](docs/src/api.md).

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Open `docs/build/index.html`. The committed manifest pins the runtime
dependencies; documentation, tests, and benchmarks have separate environments.
