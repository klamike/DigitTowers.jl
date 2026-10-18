# Results

The searches below use decimal digits in their original order, right-associated powers, positive integer root orders, and the default rule that every occurrence of `0^0` is undefined. A root order is external unless the table explicitly says it consumes the leading digit. Bounds count the digits of the resulting number.

## Complete bounded searches

| Rules | Number of digits | Complete solution set |
|:--|:--|:--|
| Single digits, square root | 2–100 | `262144` |
| Single digits, square root, zero forbidden | 2–100 | `262144` |
| Single digits, external root order 1–9 | 2–20 | `262144`, with root order 2 |
| Single digits, leading digit consumed as root order 2–9 | 3–20 | None |
| Single digits, square root, all digits distinct | 2–10 | None |

The unique number in the first three rows satisfies

```math
\sqrt{2^{6^{2^{1^{4^4}}}}}
=\sqrt{2^{36}}
=2^{18}
=262144.
```

These are exhaustive results within the stated bounds. The JuMP/HiGHS searches were also checked against a separate integer oracle that enumerates primitive powers and evaluates the suffix using bounded exponentiation by squaring. The joint 94-digit square-root model reached its 10-second solver limit; five complete searches, one for each possible outer base `2`, `3`, `4`, `8`, and `9`, proved that case empty. The recorded results retain this recovery, rather than treating the timed-out model as complete.

## Broader arithmetic sweep

The public exact `sweep` method extends the single-digit search to **2–1000 digits and external root orders 1–1000**. Its complete solution set is still **`262144`, with root order 2**. The method screens 1,702 possible numbers, evaluating each suffix once and deriving its possible root order. A separately implemented Python integer oracle independently confirms this result. This larger bound uses arithmetic enumeration; the historical CP coverage above remains 100 digits for the square-root puzzle.

Reproduce the complete public search with:

```sh
julia --project=. -e 'using DigitTowers; r = sweep(2:1000; roots=1:1000); @assert r.complete; @show [(x.number, x.root, x.exponent) for x in r.solutions] r.candidates'
```

The public tests assert both the exact solution set and the independently checked candidate count. The matching `lengths_2_to_1000_roots_1_to_1000` row in `benchmark/sweep_results.tsv` records the complete arithmetic run and its measured cost.

## Two global impossibility results

In the **single-digit square-root grammar**, there is **no multidigit solution with all digits distinct**. The complete search excludes lengths 2–10. A longer decimal number necessarily repeats a digit, by the pigeonhole principle.

In that same grammar there is also **no multidigit solution using only digits 2–9**. To see why, let ``L`` be the number of digits and ``E`` the suffix tower after the outer base. Since ``N<10^L`` and the outer base is at least 2,

```math
2^E\le N^2<10^{2L}<2^{7L},\qquad E<7L.
```

For ``L\ge5``, the smallest possible suffix is the tower of ``L-1`` twos. At ``L=5`` this is ``2^{2^{2^2}}=65536>7L``. Adding another digit raises 2 to the previous minimum, so the minimum continues to exceed the linear bound ``7L``. The remaining lengths 2–4 have no solutions by complete search.

## Additional grouped examples

Allowing the first two blocks to contain several digits produces two further examples found during these experiments. Every later block below is a single digit. Let ``\operatorname{tower}(s)`` mean the right-associated tower of the decimal digits in the string ``s``.

| Base | Root order | Number | Digit count | First two blocks |
|:--|:--|:--|:--|:--|
| 26 | 2 | ``26^{42}`` | 60 | `26`, `84` |
| 136 | 6 | ``136^{16}`` | 35 | `136`, `96` |

The full identities are

```math
\begin{aligned}
N_1&=268460636031393932323010374318061912785738337881638804914176,\\
T_1&=\operatorname{tower}(\texttt{60636031393932323010374318061912785738337881638804914176})=1,\\
\sqrt{26^{84^{T_1}}}&=26^{42}=N_1;\\[6pt]
N_2&=13696907849916094763278545543233536,\\
T_2&=\operatorname{tower}(\texttt{907849916094763278545543233536})=1,\\
\sqrt[6]{136^{96^{T_2}}}&=136^{16}=N_2.
\end{aligned}
```

The tail strings contain every remaining digit, in order. They evaluate to 1 with all intermediate powers defined. Both complete CP searches recover exactly the displayed number for the specified base and block widths.

The following reproduces the 60-digit example:

```julia
using DigitTowers

config = Config(
    ndigits = 60,
    roots = [2],
    bases = [26],
    block_widths = [2, 2, ones(Int, 56)...],
)
result = search(config)
@assert result.complete
@assert only(result.solutions).number == big(26)^42
```

These examples arose from an independent exact search with outer bases 2–99,999, total lengths 2–100, root orders 2–9, a first exponent block of width 1–3, and every later block a single digit. Its complete expression set is the two examples above, `256` with seventh root and blocks `[2,56]`, and the original `262144` expression. This is a bounded result for that grammar, not a claim about every possible grouping.

A separate exhaustive check of **all contiguous partitions**, including every possible width of the outer base, finds only the following expressions through ten digits with root orders 2–9:

- `256`, root 7, blocks `[2,56]`;
- `262144`, root 2, blocks `[2,6,2,1,4,4]`;
- `262144`, root 2, blocks `[2,6,2,1,44]`.

## Reproduction and data

From the repository root:

```sh
julia --project=. research/explore.jl
```

This runs the bounded CP experiments and cross-checks each complete result against its independent integer oracle. `research/results/searches.tsv` records completeness, solver status, candidate count, and elapsed time; `solutions.tsv` records the actual assignments. Partitioned recoveries and the two additional grouped examples are recorded alongside them.

The independent Python discovery scripts and their machine-readable results are under `research/`. In particular, `oracle_grouped.py` covers all contiguous partitions through ten digits, and `oracle_prefix_grouped.py` searches the wider prefix grammar. These discovery scripts use exact integers and do not construct the enormous full digit towers.

Their default commands reproduce the recorded bounds directly:

```sh
python3 research/oracle_enumerate.py
python3 research/oracle_grouped.py
python3 research/oracle_prefix_grouped.py
```

The second command exhausts all outer-base widths and contiguous partitions through ten digits. The third exhausts bases 2–99,999, lengths 2–100, root orders 2–9, and first exponent-block widths 1–3. Both commands accept `--help` to inspect configurable bounds and output paths.
