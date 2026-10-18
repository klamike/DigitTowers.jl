# API

```@meta
CurrentModule = DigitTowers
```

[`search`](@ref) is the usual entry point, taking a [`Config`](@ref) and
`method=:prefix` by default. `:direct`, `:cp`, and optional `:nemo` select the
other search backends. Their results share `solutions`, `complete`, `status`,
`candidates`, `cap`, and `method`; see [Configuration](@ref) for status semantics
and [Performance](performance.md) for backend selection.

[`sweep`](@ref) searches a range of lengths and root orders in the single-digit
grammar with one primitive-power pass. It derives the root from the suffix
instead of evaluating that suffix separately for each allowed root. Its
result uses `method=:sweep`; its docstring explains the candidate-count and
cap fields, which differ from those of a fixed-configuration search.

[`build_model`](@ref) always constructs the original CP formulation. It exposes the
JuMP model, configuration, candidate list, grammar, selector variables, and
cap for inspection or additional constraints. Its empty-candidate result has
no digit, root, exponent, block, or suffix variables.

[`Candidate`](@ref) stores the exact answer as `number::BigInt`, its root order,
the effective outer exponent, decimal digits, and parsed `BigInt` blocks.
Keep the configuration with each answer: it supplies the root-prefix width,
block widths, operators, and zero convention needed by [`verify`](@ref) and
[`expression`](@ref).

## Public docstrings

```@autodocs
Modules = [DigitTowers]
Public = true
Private = false
Order = [:type, :function]
```

## Implementation docstrings

These entries explain internal construction steps; they are not part of the
exported API.

```@autodocs
Modules = [DigitTowers]
Public = false
Private = true
Order = [:type, :function]
```

## Index

```@index
Modules = [DigitTowers]
```
