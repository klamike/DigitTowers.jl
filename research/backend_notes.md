# Search methods and Julia package choices

The largest improvement comes from exploiting the exact number-theoretic candidate set before constructing solver tables. Keep the JuMP model for configurable constraints, then offer exact specialised searches alongside it.

## Exact methods

1. **Direct candidate scan for a fixed grammar.** Generate the same primitive-power candidates as the CP model, evaluate each bounded suffix once, and retain exact matches. This preserves the candidate completeness proof while avoiding the table-to-MIP reformulation entirely.
2. **One pass across lengths and root orders.** Write an outer base as `b=a^g`, with `a` not a perfect power. Enumerate `N=a^h` incrementally. Evaluate the suffix once with a cap covering the largest requested root; if the exact suffix value is `E`, the only possible root is `r=g*E/h`. Test divisibility and membership in the requested root set. This removes both the repeated length loop and the repeated root loop.
3. **Dynamic programming for contiguous groupings.** For each position in the decimal suffix, record reachable values in `{0,…,E,overflow}` and backpointers to block widths. A block followed by an already-solved suffix produces one bounded power, or one bounded sum when addition is enabled. Merge equal states. This replaces enumeration of exponentially many partitions with a state space bounded by the digit length, allowed block widths, and target exponent. Preserve all backpointers if every expression is requested; one representative per state suffices for existence.
4. **Cache primitive decompositions and decimal strings.** Fixed base ranges permit a smallest-prime-factor sieve. Increment powers by multiplication and reuse the resulting decimal string across roots and grouping choices. Parallelise independent bases or primitive powers, then sort the final assignments deterministically.

Undefined `0^0` must propagate through every state. A numerical zero or one blocker does not make an undefined exponent expression valid.

## Package assessment

| Package | Relevant capability | Recommendation |
|:--|:--|:--|
| Base `BigInt` | Exact integer arithmetic, incremental powers, decimal conversion | Use for the first exact backend; the measured algorithm change already removes most overhead. |
| Primes.jl | `eachfactor` and `factor` expose integer prime factors and multiplicities | Useful for larger machine-integer base ranges; replace the hand-written trial division or build a sieve for dense ranges. |
| Nemo.jl | FLINT-backed `ZZ`, exact checked roots, integer truncated roots | Useful when larger exact roots or broader computer-algebra operations become bottlenecks; benchmark against Base on the actual workload before making it mandatory. |
| Arblib.jl | Arbitrary-precision real balls with rigorous error bounds | Suitable for a certified leading-digit filter on very large powers; optional acceleration rather than an equality oracle. |

Primes documents `eachfactor` as a lazy factor/multiplicity iterator and notes its allocation advantage for small-factor inputs. [Primes API](https://juliamath.github.io/Primes.jl/stable/api/)

Nemo's default integer representation uses FLINT; its checked `root` rejects inputs that are not perfect powers, while `iroot` returns a truncated integer root. [Nemo integer API](https://nemocas.github.io/Nemo.jl/stable/integer/)

Arblib's `Arb` encloses exact results in midpoint-radius intervals. Its documented precision model supports refining a computation until a decision is certified. [Arblib types](https://kalmarek.github.io/Arblib.jl/stable/interface-types/), [precision handling](https://kalmarek.github.io/Arblib.jl/stable/precision/)

## Certified prefix filtering

For a candidate power `N=a^h`, compute a ball enclosing `x=h*log10(a)`. Certify `L=floor(x)+1`, then enclose `10^(x-(L-1)+(m-1))` to obtain its first `m` digits. Accept a floor only when the lower and upper endpoint floors agree; otherwise increase precision. A ball containing a unique integer does **not** by itself certify the floor: `[122.9,123.1]` contains exactly one integer but permits two floor values.

Nemo provides both `floor` on real balls and `unique_integer`, while FLINT explains enclosure semantics and repeated refinement. [Nemo real-ball API](https://nemocas.github.io/Nemo.jl/stable/arb/), [FLINT ball arithmetic](https://flintlib.org/doc/arb.html)

A prefix filter can reject mismatching prefixes cheaply. Under the default undefined-`0^0` policy, surviving candidates still need full-tail validation. Do not certify an arbitrary uncomputed suffix solely because an earlier blocker fixes its numerical contribution.

## Reproducible benchmark

Run:

```sh
julia --project=. research/benchmark_algorithms.jl
```

The script warms each method once, verifies equality of the complete solution sets, and records three measured runs plus allocations. `research/results/algorithm_benchmarks.tsv` contains minimum and median times, and `algorithm_benchmark_metadata.toml` identifies the Julia version and CPU. The direct and derived-root routines in this research script are deliberately small prototypes for comparing algorithms; the public package API remains the implementation entry point.
