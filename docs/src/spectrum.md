# Unbounded root orders

How much does the upper bound on the root order matter? Remove it completely.
[`root_spectrum`](@ref) finds numerals admitting **any positive integer root
order**, even when that order is far too large to construct.

```julia
using DigitTowers
result = root_spectrum(2:1000)
@assert result.complete
@assert [x.number for x in result.solutions] ==
        BigInt[262144, 4294967296, big(3)^64]
@assert all(verify_root_certificate, result.solutions)
```

There are **exactly three decimal solutions of lengths 2–1000**, over **all
positive integer root orders**. The search examines 1,702 numeral candidates:

| Numeral | Length | Primitive power | Unique root order |
|:--|--:|:--|:--|
| `262144` | 6 | ``2^{18}`` | ``2`` |
| `4294967296` | 10 | ``2^{32}`` | ``2^{T-4}`` |
| `3433683820292512484657849089281` | 31 | ``3^{64}`` | ``4^{U-3}`` |

Here ``T`` and ``U`` are right-associated towers:

```text
T = tower([9,4,9,6,7,2,9,6])
U = tower([3,3,6,8,3,8,2,0,2,9,2,5,1,2,4,8,4,6,5,7,8,4,9,0,8,9,2,8,1])
```

The second and third root orders are certified greater than 1,000; their
exact symbolic forms avoid evaluating either enormous integer. Defining
`0^0=1` produces the same three numerals in this length range. These are
bounded-length classifications; nothing here excludes longer numerals.

## A tower with no zero or one

The ten-digit example has no digit zero or one:

```math
4294967296=4\cdot10^9+2\cdot10^8+\cdots+6=2^{32}.
```

Its digit tower is ``4^{2^T}=2^{2^{T+1}}``. Therefore

```math
\sqrt[\displaystyle 2^{T-4}]{4^{2^T}}
=2^{\,2^{T+1}/2^{T-4}}
=2^{32}
=4294967296.
```

The earlier [radix result](radices.md) rules out three-or-more-digit
solutions without zero or one only when the root order is at most 1,000.
This example shows exactly how an astronomical root escapes that bound.

```julia
hard = only(root_spectrum(2:1000; allowed_digits=2:9).solutions)
@assert hard.number == 4294967296
@assert isnothing(hard.root)  # exact symbolic root, certified >1000
println(expression(hard))
```

## A valuation sieve replaces the root bound

For leading digit ``b=a^g`` with primitive ``a``, prime factorization forces
``N=a^h``. Write the digit suffix as ``E=c^T``, with ``T=1`` for a two-digit
numeral. Since ``N>b``, we have ``h>g``. The only possible root order is

```math
r=\frac{gE}{h},\qquad
r\in\mathbb Z_{>0}
\iff k\mid c^T,\qquad
k=\frac{h}{\gcd(h,g)}.
```

For each prime ``p\mid k``, write ``v_p(n)`` for the exponent of ``p`` in
``n``. Divisibility holds precisely when every prime of ``k`` divides ``c``
and

```math
T\ge \max_{p\mid k}
\left\lceil\frac{v_p(k)}{v_p(c)}\right\rceil.
```

The threshold is tiny: the three decimal examples need only ``T\ge2``,
``T\ge4``, and ``T\ge3`` respectively. Exact capped arithmetic tests those
inequalities without constructing the towers. A missing prime rejects the
candidate immediately. Undefined descendants remain disallowed even when
an outer zero or one would otherwise hide their value.

A suffix beginning with zero or one cannot work: ``E\le1`` and ``h>g``
force ``r=gE/h<1``, excluding every positive integer root order. This also covers
the permissive `0^0=1` convention. The primitive-power enumeration and the
valuation condition are both necessary and sufficient, so the method
exhausts every integer root order simultaneously.

## Certificates and reproducibility

A [`RootCertificate`](@ref) records the positional digits, ``a,g,h,k``, the
valuation threshold, and the zero convention. [`verify_root_certificate`](@ref)
reconstructs the numeral and checks that proof. When a root is at most
`root_display_limit`, `certificate.root` contains its exact `BigInt` value;
otherwise it is `nothing` and [`expression`](@ref) displays the exact symbolic
root together with a certified strict lower bound. `verify(certificate)` is
an equivalent convenience method.

`root_display_limit` affects only materialization and display, **never search
membership**. The default is 1,000. `allowed_digits`, `distinct_digits`,
`zero_to_zero`, and `radix` remain configurable. As with the other searches,
`complete=true` certifies exhaustion of the configured numeral domain;
reaching the returned-solution limit conservatively leaves it false.

```sh
julia --project research/root_spectrum_experiments.jl
python3 research/oracle_root_spectrum.py
```

The checked-in `research/results/root_spectrum_solutions.tsv` contains every
digit and both symbolic roots; its metadata records the exact search domain.
The standalone Python oracle independently reproduces all three numerals and
1,702 candidates using only the standard library. Tests also enumerate tiny numeral domains literally, and independently
check the valuation sieve against [`tower_mod`](@ref) using the noncoprime
Euler-chain algorithm. This comparison covers all primitive-power numeral
candidates up to 100 digits in several radices under both zero conventions.
