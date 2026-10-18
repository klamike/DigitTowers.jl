# DigitTowers.jl

DigitTowers searches for decimal numbers that reproduce themselves when their
digits form a power tower and an outer root is taken. The default problem uses
single digits in their original order, a square root, and a right-associated
tower:

```math
\sqrt{2^{\,6^{\,2^{\,1^{\,4^4}}}}}=262144.
```

The default search uses exact number theory: decimal prefix bounds locate the
only possible power for each base, then capped arithmetic checks its suffix.
The original JuMP constraint programming model remains available as `method=:cp`.
It uses finite transition tables reformulated as a mixed-integer model for
HiGHS. Every backend uses exact candidate arithmetic and checks each returned
answer again with integer arithmetic.

## Run a search

From the package directory, instantiate the environment:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Then start Julia with `julia --project=.`:

```jldoctest; setup = :(using DigitTowers)
julia> config = Config();

julia> result = search(config);

julia> length(result.solutions)
1

julia> string(only(result.solutions).number)
"262144"

julia> result.complete
true

julia> result.method
:prefix

julia> verify(only(result.solutions), config)
true
```

`complete=true` means the backend exhausted the configured finite search. It
applies to this digit length and grammar. A solution limit, or a time limit in
the CP backend, leaves it `false`.

## Select a method

| `method` | Algorithm |
|:--|:--|
| `:prefix` | Default: exact leading-prefix windows, followed by capped suffix evaluation |
| `:direct` | Enumerate primitive powers, then evaluate the candidates directly |
| `:cp` | Original JuMP/HiGHS candidate and transition constraints |
| `:nemo` | Prefix search using Nemo/FLINT integer logarithms and powers |

```julia
search(Config(); method=:cp)
search(Config(); method=:direct)
```

The optional Nemo backend is activated by loading Nemo in an environment where
it is installed:

```julia
using DigitTowers, Nemo
search(Config(); method=:nemo)
```

Nemo is a weak dependency; the default search does not load it. See
[Performance](performance.md) for algorithm comparisons and measured timings.

For a range of lengths and root orders, [`sweep`](@ref) searches the
single-digit grammar in one pass and derives the only possible root from each
candidate's suffix:

```julia
sweep(2:100; roots=collect(1:9))
```

## Change the rules

Root orders, digit restrictions, grouped blocks, and additions inside the outer
exponent are configurable. For example, grouping the suffix as `56` gives:

```jldoctest; setup = :(using DigitTowers)
julia> config = Config(ndigits=3, roots=[7], block_widths=[1, 2]);

julia> result = search(config);

julia> println(expression(only(result.solutions), config))
root_7((2^56)) = 256

julia> result.complete
true
```

Read [Formulation](@ref) for the prefix algorithm, constraints, and completeness proof,
[Configuration](@ref) for the expression grammar, [Results](@ref) for the
bounded searches, and [API](@ref) for the Julia interface.

## Beyond the original puzzle

Several nearby questions lead to quite different exact algorithms:

| Question | Technique | Try |
|:--|:--|:--|
| Does *any* integer root work? | Prime valuations, with symbolic certificates for enormous roots | `root_spectrum(2:1000)` |
| What is the cheapest repair of these digits? | Dynamic programming over equivalent suffix values | `synthesize(94143178827; roots=[6], max_block_width=1, allow_addition=true)` |
| What changes in another numeral system? | Primitive-power enumeration in an arbitrary radix | `radix_sweep(22, 2:100; roots=[1])` |
| What happens when we iterate towers modulo a power of ten? | Totient-chain evaluation and exhaustive functional graphs | `modular_dynamics(3)` |
| How many towers are even defined? | A two-state automaton and exact matrix powers | `tower_language_counts(1000)` |

The exploration chapters contain certificates, proofs, census tables, and
commands to reproduce each result. Run `examples/playground.jl` for a short tour.

## Build these docs

```sh
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Open `docs/build/index.html`. The build runs the doctests and checks that every
package docstring appears in the API reference. It creates local HTML and does
not deploy it.
