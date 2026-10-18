# Follow one orbit through an enormous space

[`modular_dynamics`](@ref) answers a global question by visiting every state.
[`modular_orbit`](@ref) follows just one starting word. It uses Brent's cycle
detection to find the least preperiod and period while keeping a constant
number of orbit states. The digit buffers and cached totient chain still need
space, but there is no table with one entry per possible numeral.

```jldoctest; setup=:(using DigitTowers)
julia> orbit = modular_orbit(426, 3);

julia> (orbit.termination, orbit.preperiod, orbit.period, orbit.entry)
(:cycle, 1, 2, 456)
```

The trajectory starts ``426\to456\to624\to456``. The preperiod is one;
the first cycle state reached from this start is 456. Starting at 624 gives
preperiod zero and entry 624: the entry is relative to the starting word,
rather than the smallest numeral in the cycle.

Undefined orbits have a different termination record:

```jldoctest; setup=:(using DigitTowers)
julia> orbit = modular_orbit(123, 3);

julia> (orbit.termination, orbit.undefined_at, orbit.distance_to_undefined)
(:undefined, 1, 1)
```

Here ``1^{2^3}=1``, then the padded word `001` contains an undefined `0^0`.
The distance counts transitions to the first word that cannot be evaluated.

## A 1000-bit state space

This example has ``2^{1000}`` possible states. Its structure needs only a few
map evaluations:

```julia
orbit = modular_orbit(big(2)^999, 1000; radix=2, zero_to_zero=:one)
@assert orbit.complete
@assert (orbit.preperiod, orbit.period, orbit.entry) == (1, 2, big(1))
@assert orbit.evaluations < 20
```

The 1000-bit starting word is `1` followed by 999 zeros. It maps to one,
then the two padded words zero and one alternate forever. This is an exact
single-orbit result. It does not enumerate ``2^{1000}`` states.

## Universal zero-one cycles

There is also a global theorem behind that example. In **every radix**,
with `0^0=1`, the padded zero and one words obey:

| Width | Behavior |
|:--|:--|
| Odd | Zero and one are separate fixed points |
| Even | Zero and one form a two-cycle |

For a tower of zeros, each added zero toggles its value between zero and
one. Starting the recurrence from a final one reverses the parity. Padding
is essential: the word for one has exactly the configured number of digits.

In **radix two**, this describes every possible attractor, for every width.
Every defined tower of zeros and ones has value zero or one, so every orbit
enters this tiny set after at most one step. With `0^0=1`, odd widths have
only the two fixed points and even widths have only the two-cycle.

With `0^0` forbidden and width at least two, **every binary orbit eventually
becomes undefined**. For width two, `00` is undefined and `01` maps to `00`.
At larger widths, both padded words zero and one contain `00`. Any initially
defined word maps into that set, proving the result for all widths without
enumeration. Width one is the separate identity map.

## Algorithm and limits

Brent's method advances one walker while holding a checkpoint for blocks of
length ``1,2,4,8,\ldots``. A repeated checkpoint identifies the period. Two
walkers separated by that period then meet at the cycle entry. It takes
``O(\mu+\lambda)`` map evaluations for preperiod ``\mu`` and period ``\lambda``;
the arithmetic cost of each evaluation depends on the digit width and modulus.
This is the cycle-finding algorithm in
[Brent's 1980 paper](https://maths-people.anu.edu.au/brent/pub/pub051.html),
applied to the exact modular map rather than integer factorization.

`max_evaluations` includes both phases. Reaching it returns
`complete=false, termination=:limit`, with unknown structural fields left
as `nothing`. A limited orbit proves no absence of cycles. `max_width` is
an explicit allocation guard; raising it does not remove the factorization
and primality-certification limits of [`tower_mod`](@ref).

```sh
julia --project=. research/orbit_experiments.jl
```

The saved examples include universal zero-one cases, known decimal cycles,
the 1000-bit example, and an intentionally limited search. Unit tests compare
Brent's results against independently stored full trajectories for every
small-domain starting state under both zero conventions.
