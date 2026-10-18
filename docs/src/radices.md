# Other numeral systems

Decimal is only one place to look for a numeral that computes its own value.
[`radix_sweep`](@ref) searches the same single-digit power grammar in any
positional radix, retaining exact integers and external root orders.

```julia
using DigitTowers

original = radix_sweep(10, 2:100; roots=1:1000)
fixed = only(radix_sweep(22, 3:100; roots=[1]).solutions)
@assert fixed.number == big(15)^9 == 38443359375
@assert fixed.digits == [15, 9, 1, 10, 7, 2, 10, 3]
@assert verify_radix(fixed)
```

Digits above nine are integer values: a digit `15` means fifteen in both the
positional numeral and the tower. `roots=[1]` removes the external root.
There are no grouped blocks or consumed root digits in this API; use
[`Config`](@ref) for those decimal grammars.

## Three root-free discoveries

Searching **radices 3–64, lengths 2–100, and roots 1–1000** gives **49 solutions**
from **14,284 numeral candidates**, with the default forbidden `0^0`.
Only seven are root-free, and three of those have more than two digits:

| Radix | Numeral | Integer value | Effective power |
|:--|:--|--:|:--|
| 17 | `C9D04145` | 5,159,780,352 | ``12^9`` |
| 22 | `F91A72A3` | 38,443,359,375 | ``15^9`` |
| 34 | `GTC0A31NJLBXC7V0UPJK9EG` | 83,076,749,736,557,242,056,487,941,267,521,536 | ``16^{29}`` |

Here `A=10`, `B=11`, …, `X=33`. The radix-22 example contains no zero. Its
third digit is one, so the tail after that digit collapses:

```math
[15,9,1,10,7,2,10,3]_{22}
= 15^{9^{1^{10^{7^{2^{10^3}}}}}}
= 15^9.
```

The other two examples use a zero whose positive exponent makes the next
power equal to one. These are exact fixed points, with all digits used once
in their original order; they need no square root.

The remaining root-free solutions are ``[2,4]_6=16``, ``[3,3]_8=27``,
``[2,6]_{29}=64``, and ``[4,4]_{63}=256``. Decimal contributes its original
square-root solution ``262144`` and no root-free solution in this search.
These statements concern the stated finite bounds, not arbitrary lengths
or radices.

Reproduce every row with:

```sh
julia --project research/radix_experiments.jl
```

The checked-in `research/results/radix_solutions.tsv` records digit values,
root orders, and effective exponents; companion files record the search
bounds and candidate counts. The research script verifies each result and
repeats the restricted search below. Unit tests independently enumerate
every small-radix numeral and evaluate short suffixes literally.

## An infinite family you can prove

For every integer ``a\ge3``, choose radix ``\beta=a^{a-1}-1``. Then

```math
[a,a]_\beta=a\beta+a=a^a.
```

Both digits fit the radix, so this produces infinitely many root-free tower
numerals without zeros or ones:

| ``a`` | Radix ``\beta`` | Numeral | Value |
|--:|--:|:--|--:|
| 3 | 8 | `[3,3]` | 27 |
| 4 | 63 | `[4,4]` | 256 |
| 5 | 624 | `[5,5]` | 3,125 |
| 6 | 7,775 | `[6,6]` | 46,656 |

More generally, two-digit root-free examples satisfy
``\beta=(a^b-b)/a``: choose ``b`` divisible by ``a`` and check that
``\beta>\max(a,b)``. For instance, ``a=2,b=4`` gives radix six and
``[2,4]_6=2^4``. This is a construction rather than a bounded search claim.

## Turn the radix into a root-order dial

The same integer can survive in a whole run of numeral systems. Write
``A=a^{a-1}`` and choose any positive integer ``r`` with
``(a+1)r<A``. In radix ``\beta=A-r``, the two-digit numeral is

```math
[a,ar]_{A-r}=a(A-r)+ar=a^a
=\sqrt[r]{a^{ar}}.
```

Thus increasing the radix by one decreases the required root order by one.
For ``a=4``, **every radix 52–63** represents 256 as such a tower:

| Radix | Digits | Root order | Identity |
|--:|:--|--:|:--|
| 52 | `[4,48]` | 12 | ``\sqrt[12]{4^{48}}=256`` |
| 57 | `[4,28]` | 7 | ``\sqrt[7]{4^{28}}=256`` |
| 62 | `[4,8]` | 2 | ``\sqrt{4^8}=256`` |
| 63 | `[4,4]` | 1 | ``4^4=256`` |

The root-free ``[a,a]`` family is the ``r=1`` endpoint of this construction.
No search is needed to establish the whole family.

## A complete result when zeros and ones are forbidden

In **every radix 3–64, with external root order 1–1000**, every solution whose
digits are all at least two has **exactly two digits**. There are 38 such
solutions in the atlas. Unlike the unrestricted atlas, this conclusion
covers **all lengths**.

The finite part is exhaustive search over lengths two through four. The
remaining lengths have a simple growth certificate. If the full tower is
``T=d_1^E=N^r`` and every digit is at least two, then

```math
E < rL\log_2\beta \le 6000L.
```

For five digits, the smallest possible suffix is
``2^{2^{2^2}}=65536>6000\cdot5``. Increasing the length changes that minimum
suffix from ``m`` to ``2^m``; its growth stays ahead of the linear bound.
Thus length five and every longer length are impossible in this radix/root
range. The familiar decimal example depends on its digit one, while the
nondecimal root-free family avoids that dependency by using two digits.

```julia
# This finite search, together with the growth bound, covers every length.
for radix in 3:64
    result = radix_sweep(radix, 2:4; roots=1:1000,
                         allowed_digits=2:radix-1, max_solutions=10_000)
    @assert result.complete
    @assert all(x -> length(x.digits) == 2, result.solutions)
end
```

## Why the search is small

For a leading digit ``b=a^g``, take ``a`` primitive: the greatest common
divisor of its prime-factor exponents is one. The identity ``b^E=N^r``
forces ``N=a^h`` for an integer ``h``. Enumerate those powers, retain the
ones beginning with digit ``b`` in the chosen radix, evaluate their suffix,
and derive the only possible root order:

```math
r=\frac{gE}{h}.
```

A nonintegral result or a root outside the requested domain is rejected.
The maximum requested root bounds the relevant suffix by
``E\le\lfloor r_{\max}h/g\rfloor``. All larger values share an exact overflow
state, so gigantic discarded towers never have to be constructed. Allowed
digits, distinct digits, and the `0^0` convention remain configurable.
