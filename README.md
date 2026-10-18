# DigitTowers.jl

Find numbers that reproduce themselves when their digits form a
right-associated power tower and an outer root is taken:

\[
\sqrt{2^{6^{2^{1^{4^4}}}}}=262144.
\]

Exact arithmetic methods exploit the number theory; the original Julia/JuMP
constraint programming model remains available for comparison and extensions.

## Try it

Requires Julia 1.12 or later. From this repository:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. examples/transcript.jl
```

```julia
using DigitTowers

search(Config())                           # fast exact prefix search
search(Config(); method=:cp)               # original JuMP/HiGHS model
sweep(2:1000; roots=1:1000)                 # share work across lengths and roots
search(Config(ndigits=8, distinct_digits=true))
search(Config(ndigits=3, roots=[7], block_widths=[1,2])) # root₇(2^56)=256
```

## Methods

| Method | How it searches |
|:--|:--|
| `:prefix` (default) | Locate the only possible primitive power in each decimal prefix interval |
| `:direct` | Enumerate primitive powers and evaluate candidate suffixes directly |
| `:cp` | Solve the finite table constraints with JuMP and HiGHS |
| `:nemo` (optional) | Prefix search using Nemo/FLINT exact integer logarithms |
| `sweep(lengths; ...)` | Scan single-digit towers once and derive each possible root order |

All methods use exact integer checks. Primes.jl handles factorization; loading
Nemo enables `:nemo`. A warmed 60-digit grouped search took **22 μs with prefix
search versus 152 ms with CP** on the recorded machine. See
[benchmarks and Julia package choices](docs/src/performance.md).

Digit restrictions, distinct digits, grouped tokens, addition inside the
exponent, a consumed root prefix, and the `0^0` convention are configurable.
`sweep` supports the single-digit grammar; the other methods also support
fixed grouping and operator positions.

## Results

- Single-digit towers, **2–1000 digits and external root orders 1–1000**:
  **262144 with square root only** within those bounds.
- Original square-root puzzle, with **neither zero nor one**: no multidigit
  solution, by a tower-growth proof.
- Original puzzle, **every digit different**: no multidigit solution,
  by exhaustive search through ten digits and the pigeonhole principle.
- Grouping gives a new **60-digit** square-root example, **26⁴²**, with initial
  blocks `26 | 84` and all remaining tokens single digits.

Read [results, proofs, and reproduction commands](docs/src/results.md).

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
