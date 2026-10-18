# Formulation

## The original problem

Fix a decimal length ``L\ge2``, an allowed digit set ``D``, and a root order
``r\ge1``. In the default grammar, ``r=2`` and every token is a single digit.
The unknown number and suffix tower satisfy

```math
\begin{aligned}
N&=\sum_{i=1}^{L}10^{L-i}d_i,\\
d_1&\in D\cap\{2,\ldots,9\},\qquad d_i\in D\quad(i\ge2),\\
T_L&=d_L,\\
T_i&=d_i^{T_{i+1}}\quad(i=L-1,\ldots,2),\\
d_1^{T_2}&=N^r.
\end{aligned}
```

Powers associate to the right. Thus ``2^{3^4}=2^{81}``. Bases zero and one
cannot produce a positive multidigit answer, so the outer base is at least two.
The last equality removes the outer root without introducing fractions.

This is a feasibility problem. The implementation orders its solutions by
increasing ``N``, then by root order.

With `distinct_digits=true`, add ``\operatorname{AllDifferent}(d_1,\ldots,d_L)``.
The JuMP model expresses this directly as an `MOI.AllDifferent` constraint.

## General expression grammar

A configuration can consume a leading digit prefix as the root order and
partition the remaining digits into fixed blocks ``x_1,\ldots,x_m``. Write
``b=x_1``. The first operator is exponentiation, and each subsequent operator
``\circ_i`` is either exponentiation or addition:

```math
F_m=x_m,\qquad F_i=x_i\circ_i F_{i+1}\quad(i=m-1,\ldots,2),
\qquad E=F_2,\qquad b^E=N^r.
```

The same right association applies when addition is present. For example,
`7 | 82 | 2 | 3` with operators `[:^, :+, :^]` denotes
``7^{82+2^3}``. The grammar fixes block boundaries and operator positions;
searching different grammars requires an outer loop over configurations.

### Zero and undefined powers

By default, ``0^0`` is forbidden at every node. This includes a tail beneath an
outer one: ``1^{(0^0)}`` is invalid because its exponent is undefined. Set
`zero_to_zero=:one` to use ``0^0=1`` consistently instead.

For a defined tail, a one makes its value irrelevant. A zero has a different
effect: when ``u>0``, ``0^u=0``, so the immediately preceding positive token
``x`` becomes ``x^0=1``. Many digits disappear together only when they form
that one grouped token. The solver evaluates these cases explicitly.

## Exact candidate generation

The implementation first constructs a finite table ``\mathcal{P}`` of necessary
conditions. Each row contains a root order, an outer exponent ``E``, and a
decimal digit string satisfying

```math
N^r=b^E.
```

Rows also respect the configured length, allowed digits, root prefix, base,
and block boundaries. At this stage the suffix expression has **not** been
tested; requiring that it evaluates to ``E`` is the constraint model's job.

The table is finite. If ``N\le10^L-1`` and ``r\le R``, then

```math
2^E\le b^E=N^r\le(10^L-1)^R.
```

No floating-point logarithms are needed to enumerate it. Factor each allowed
base as

```math
b=\prod_p p^{\beta_p}=a^g,\qquad
g=\gcd_p\beta_p,\qquad a=\prod_p p^{\beta_p/g}.
```

The integer ``a`` is not itself a perfect power. Enumerate ``N=a^h`` of the
required decimal length and retain exactly those rows for which

```math
gE=rh.
```

**Why this is complete.** From ``N^r=b^E``, prime factorization gives
``r\,v_p(N)=gE\,(\beta_p/g)``. The integers ``\beta_p/g`` have greatest common
divisor one, so their integer linear combinations include one. Consequently
``gE/r`` is an integer ``h`` and ``N=a^h``. Conversely, ``N=a^h`` together with
``gE=rh`` immediately gives ``N^r=b^E``.

Assuming ``N=b^k`` for an integer ``k`` would miss generalized cases when the
base is a perfect power. For example,

```math
\sqrt[50688]{8^{388608}}=8388608=2^{23},\qquad
\frac{388608}{50688}=\frac{23}{3}.
```

The digits partition as `8 | 388608`. Single-digit bases ``4=2^2``,
``8=2^3``, and ``9=3^2`` are handled by the same generation rule.

## Prefix search without a solver

The default `method=:prefix` avoids enumerating every primitive power up to
the requested length. A candidate must begin with a known decimal prefix
``P`` of width ``p``. With an external root this is the outer base ``b``.
When ``q`` root digits are consumed and the base block has width ``w``,
``P=r\,10^w+b`` and ``p=q+w``; this also preserves zero padding within the
base block.

For an answer of length ``L``, put ``k=L-p``. Exactly the numbers with that
prefix lie in the half-open integer interval

```math
A=P\,10^k\le N<B=(P+1)\,10^k.
```

There is at most one power of the primitive base ``a`` in this interval:

```math
\frac BA=\frac{P+1}{P}<2\le a,
```

whereas consecutive powers differ by a factor of ``a``. Compute the least
integer ``h`` with ``a^h\ge A``. If ``a^h<B``, it is the unique candidate
power for this window; otherwise the window is empty. For an external root,
all allowed root orders reuse the same window, after which the exact
divisibility condition ``g\mid rh`` determines ``E=rh/g``.

The core implementation seeds this integer ceiling logarithm with
`ndigits(A-1; base=a)`. It then constructs the power and certifies both
boundaries using exact integer comparisons, correcting the exponent if
necessary. Its correctness does not depend on an unchecked floating-point
estimate. `method=:nemo` uses the same window algorithm with
[`Nemo.clog`](https://nemocas.github.io/Nemo.jl/stable/integer/#Integer-logarithm)
and FLINT integer exponentiation instead.

Both prefix methods generate exactly the necessary-condition rows described
above. They then evaluate each candidate's suffix directly with cap ``E+1``.
The `:direct` backend performs the same suffix check after the original
primitive-power enumeration. These methods do not construct transition tables
or call an optimizer. The capped-arithmetic proof below applies equally to
their direct evaluation.

## Deriving the root across many lengths

For the single-digit grammar, [`sweep`](@ref) enumerates primitive powers over
a whole length range in one pass. Once ``N=a^h`` and its suffix ``E`` are
known, the equality ``gE=rh`` determines the only possible root:

```math
r=\frac{gE}{h}.
```

It is enough to test divisibility by ``h`` and membership in the requested
root set. With largest allowed root ``R``, every valid exponent satisfies
``E\le\lfloor Rh/g\rfloor``. Thus the suffix can be evaluated once using cap
``\lfloor Rh/g\rfloor+1``. A forbidden power or overflow rejects the candidate;
otherwise the exact value determines its root. If root digits are consumed,
the derived root must also match that decimal prefix.

This avoids a separate suffix evaluation for each length/root pair. Grouped
blocks and additions remain available through `search` with a fixed `Config`.

## Capped expression constraints

For `method=:cp`, if the candidate table ``\mathcal{P}`` is empty, the model is
infeasible. Otherwise let

```math
C=\max_{p\in\mathcal{P}}E_p,\qquad S=C+1,\qquad \sigma(v)=\min(v,S).
```

All candidate exponents are positive, so ``S\ge2``. State ``S`` means
**at least** ``S``. Introduce capped block variables ``u_i=\sigma(x_i)`` and
suffix variables ``s_i=\sigma(F_i)``. The model requires

```math
(r,E,d_1,\ldots,d_L)\in\mathcal{P},\qquad
s_m=u_m,\qquad s_2=E,
```

with the following table constraint for each interior suffix node:

```math
(u_i,s_{i+1},s_i)\in Q_i\qquad(i=2,\ldots,m-1).
```

For exponentiation, ``Q_i`` contains the capped transition below. The cases
are applied from top to bottom.

| Capped base ``a`` and exponent ``e`` | Output |
|:--|:--|
| ``a=e=0`` | Forbidden, or 1 under `zero_to_zero=:one` |
| ``e=0`` | 1 |
| ``a=0`` | 0 |
| ``a=1`` | 1 |
| ``a=S`` or ``e=S`` | ``S`` |
| Otherwise | ``\min(a^e,S)`` |

For addition the transition is simply ``\min(a+e,S)``.

**Why the cap is exact.** Values below ``S`` retain their exact value.
A base at least ``S`` raised to a positive exponent stays at least ``S``.
A base at least two raised to an exponent at least ``S`` also stays at least
``S``, since ``2^S\ge S``. Zero and one are the only bases that can collapse
an arbitrarily large exponent; the table handles both separately. An
exponent of zero is likewise retained exactly. These facts prove

```math
\widehat{\operatorname{pow}}(\sigma(a),\sigma(e))
=\sigma(a^e)
```

for every defined nonnegative integer power. Nonnegative addition satisfies
the corresponding identity. Induction from the final block proves every
suffix state is exact under this representation, while forbidden ``0^0``
never gains a valid transition.

Finally, ``s_2=E<S`` forces the true exponent to equal ``E``; an overflow state
cannot masquerade as a valid terminal exponent. Therefore the finite model
has exactly the solutions of the configured expression problem.

## JuMP and solver representation

The candidate relation uses one-hot binary selectors. Digits, root orders,
exponents, and capped blocks equal the selected row's values. Interior
relations use `MOI.Table`; JuMP bridges them to a mixed-integer model for
HiGHS. The objective minimizes the selected row's index, with rows sorted by
number and root order.

Large decimal numbers remain Julia `BigInt` values outside the solver.
The CP implementation checks its solver integer range and refuses oversized
tables rather than discarding candidates. Each reported solution is verified
again using integer arithmetic. See [Configuration](@ref) for the resource
limits, [Performance](performance.md) for backend comparisons, and
[Results](@ref) for the searches that were actually completed.

The JuMP documentation describes the underlying
[table-constraint interface](https://jump.dev/JuMP.jl/stable/tutorials/linear/constraint_programming/).
