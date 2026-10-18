# Search methods and performance

Use `search(config)` for a fixed length and grammar, and `sweep(lengths; ...)` for a range of lengths in the single-digit power grammar. The original JuMP constraint model remains available with `method=:cp`. Every backend returns exact integer assignments and an explicit completeness flag.

## Implemented methods

| Method | How it searches | Best use |
|:--|:--|:--|
| `:prefix` | Locate primitive powers in the exact leading-digit interval; check surviving suffixes | Default for a fixed `Config`, including grouped blocks and addition |
| `:direct` | Generate primitive powers up to the length bound; evaluate candidate suffixes | Simple independent arithmetic comparison |
| `:cp` | JuMP finite-domain/table model, reformulated as a MIP and solved by HiGHS | Inspecting or extending the constraint formulation |
| `:nemo` | Prefix search using Nemo/FLINT's exact integer ceiling logarithm | Optional arithmetic comparison; load `Nemo` first |
| `sweep` | Enumerate each possible number once and derive its only possible root order | Many lengths or root orders, with single-digit power towers |

The arithmetic methods exploit the problem's number theory before constructing a search space. If `b=a^g` and `N=a^h`, then `N^r=b^E` requires `r=gE/h`. A sweep evaluates the suffix once per possible number and tests that quotient, rather than searching separately for every root order.

```julia
using DigitTowers

fixed = search(Config(); method=:prefix)
modelled = search(Config(); method=:cp)
range_result = sweep(2:1000; roots=collect(1:1000))
@assert range_result.complete
@assert only(range_result.solutions).number == 262144
```

`search` supports the full configured grammar. `sweep` supports individual decimal digits joined by right-associated powers, along with digit restrictions and consumed leading root digits. Grouped blocks and addition continue to use `search`.

## Benchmark protocol

The reproducible suite lives in `benchmark/`. From the repository root:

```sh
julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'
julia --project=benchmark benchmark/runbenchmarks.jl
```

It loads the optional Nemo backend and uses BenchmarkTools. Before timing a case, it requires complete searches, checks the exact returned assignments, and compares the solution sets across methods. Every timed evaluation calls `search` again, including construction of a fresh CP model. It does not reuse a solved optimizer model.

The results distinguish process import time, first-call time, and warmed end-to-end time. First-call measurements can include compilation and setup but are not clean-process cold-start measurements. Trial rows record the actual sample count, median/minimum elapsed time, allocations, and completeness. Small sample counts keep the suite short; the numbers describe these cases on the recorded machine.

Allocation counts describe Julia-managed allocations; native GMP/FLINT memory is not necessarily fully reflected in them.

For long arithmetic cases, the script estimates CP transition-table rows before building a model. A configuration exceeding `max_table_rows` is recorded as unsupported by that configured implementation limit. It is not a timed solver failure and provides no evidence about native CP solvers.

Raw measurements are in `benchmark/results.tsv`, range comparisons in `benchmark/sweep_results.tsv`, and environment details in `benchmark/metadata.toml`. The earlier research prototype and its independent oracle remain under `research/` for reproducibility.

These timings record baseline commit `43a49c3`. The exploration methods below
were added subsequently and are not included in these benchmark tables.

## Measured fixed-length searches

The recorded run used Julia 1.12.3 on `apple-m4`, one Julia thread, BenchmarkTools 1.8.0, and Nemo 0.57.1. Values below are warmed median milliseconds. All measured methods completed and returned identical solution sets.

| Configuration | Direct | Prefix | Nemo | CP |
|:--|--:|--:|--:|--:|
| Original, 6 digits | 0.0276 | 0.00946 | 0.00733 | 8.14 |
| Strict, 30 digits | 0.105 | 0.0118 | 0.0114 | 91.2 |
| Grouped square-root example, 60 digits | 0.0270 | 0.0223 | 0.0212 | 152 |
| Grouped sixth-root example, 35 digits | 0.0161 | 0.0124 | 0.0131 | 98.7 |
| Strict, 500 digits | 2.71 | 0.132 | 0.320 | Table limit |
| Strict, 2000 digits | 29.1 | 0.317 | 0.330 | Table limit |

The two long CP cases require estimated transition tables of 4,495,280 and 50,433,656 rows, exceeding the configured one-million-row bound. The prefix methods avoid those tables. Nemo does not improve every case; both integer implementations remain useful comparisons, and the core prefix method needs no optional arithmetic dependency.

## Measured searches across lengths and roots

The following warmed median times are in milliseconds. Each row compares the
same complete solution set; a dash means that method was not measured for
that scope. CP constructs and solves a separate model for each length.

| Lengths and external roots | Direct | Prefix | Nemo | CP | Sweep |
|:--|--:|--:|--:|--:|--:|
| 2–20 digits, roots 1–9 | 0.893 | 0.275 | 0.265 | 3358 | 0.106 |
| 2–100 digits, root 2 | 22.4 | 1.66 | 1.57 | — | 1.09 |
| 2–1000 digits, roots 1–1000 | — | — | — | — | 95.2 |

The first range's CP measurement has two samples; the other range timings
have five. The full benchmark environment's imports took 2.67 seconds,
separate from these warmed search times. These are case-specific measurements,
not a claim about all grammars or CP implementations.

`sweep` searches the whole range before sorting and truncating its output.
Its `max_solutions` option limits returned results, rather than computation.

## Search by changing the question

The explorations use different mathematical structure rather than a larger
enumeration budget:

| Method | Reduction | What it certifies |
|:--|:--|:--|
| [`root_spectrum`](@ref) | Prime valuations turn divisibility by an enormous suffix into a tiny threshold | Every root order, including ones too large to materialize, over bounded numeral lengths |
| [`synthesize`](@ref) | Merge suffix parses with the same capped value, retaining the cheapest | Minimum expression cost in its finite partition/operator grammar |
| [`tower_mod`](@ref) | A totient chain with exact small/large flags | Exact residues, including noncoprime bases |
| [`modular_dynamics`](@ref) | Exhaust the finite map once, then walk its functional graph | Every cycle and its full basin in the configured domain |
| [`tower_language_counts`](@ref) | Binary powers of a two-state transfer matrix | Exact defined/undefined word counts in logarithmically many matrix products |

For example, the 1000-digit decimal root spectrum starts from only 1,702
primitive-power numerals. The forbidden-`00` language rejects 1,509 immediately;
193 are defined, and the valuation test leaves three solutions. This removes
the need to search over root orders at all. The synthesis census likewise
reuses 57,063 value states instead of enumerating every partition of every
candidate. These counts describe the saved experiments; they are not timing
comparisons with the earlier fixed-grammar benchmarks.

## Julia package assessment

| Package or ecosystem | Role in this project | Assessment |
|:--|:--|:--|
| Primes.jl | Required primitive-base factorization | Its factor/multiplicity API replaces hand-written trial division. |
| JuMP + HiGHS | Implemented constraint backend | Retains a reviewable CP formulation through table-to-MIP bridges; benchmarked here as one implementation. |
| Nemo.jl | Optional implemented prefix backend | Exact integer logarithms through FLINT; no floating-point tolerance is used to decide a candidate. |
| ConstraintSolver.jl | Considered, not benchmarked | Native finite-domain propagation and backtracking are relevant for a future CP backend. |
| JuliaConstraints | Considered, not benchmarked | A broader CP ecosystem with modelling interfaces and solver wrappers; its packages serve different roles. |
| Arblib.jl / IntervalArithmetic.jl | Considered, not implemented | Possible certified prefix screens if profiling shows exact large-integer arithmetic is the bottleneck. |

Primes exposes both factorization and a lazy iterator of factor/multiplicity pairs. Nemo documents exact floor and ceiling integer logarithms (`flog`/`clog`), as well as checked integer roots. These are directly useful for the primitive-power reduction. [Primes API](https://juliamath.github.io/Primes.jl/stable/api/), [Nemo integer API](https://nemocas.github.io/Nemo.jl/stable/integer/)

ConstraintSolver.jl propagates bounded discrete domains before branching and backtracking. We have not benchmarked it against this package. A future native CP implementation should compare a suitable propagator or representation, rather than assume that changing the solver removes the cost of large explicit tables. The measurements here do not establish HiGHS as the best CP solver. [ConstraintSolver explanation](https://wikunia.github.io/ConstraintSolver.jl/stable/explanation/)

Within JuliaConstraints, ConstraintProgrammingExtensions.jl supplies MOI representations for CP constraints; it is not itself a search solver. CBLS/LocalSearchSolvers provides heuristic local-search machinery. A heuristic that does not find an answer cannot, by itself, certify that no answer exists. [ConstraintProgrammingExtensions](https://github.com/JuliaConstraints/ConstraintProgrammingExtensions.jl), [JuliaConstraints ecosystem](https://juliaconstraints.github.io/), [CBLS tutorial](https://juliaconstraints.github.io/dev/cp/30_getting_started)

## Why certified intervals remain optional

Arblib supplies arbitrary-precision balls with rigorous error bounds, while IntervalArithmetic.jl supplies validated interval calculations. Either could support a leading-digit screen for extremely large powers. The current prefix implementation uses exact integer comparisons, so it already avoids rounding uncertainty. Additional numerical dependencies should be justified by profiling. [Arblib types](https://kalmarek.github.io/Arblib.jl/stable/interface-types/), [IntervalArithmetic documentation](https://juliaintervals.github.io/IntervalArithmetic.jl/stable/)

Any future interval screen must refine ambiguous bounds until the endpoint floors agree. A ball containing a unique integer does not alone certify a floor: `[122.9,123.1]` contains one integer but permits two floor values. Surviving candidates still require exact suffix validation, including every nested `0^0` under the default policy.
