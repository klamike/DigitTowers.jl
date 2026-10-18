using DigitTowers

# A new 60-digit square-root identity: the first two blocks are 26 and 84;
# the tower formed by all remaining individual digits has value one.
square = Config(ndigits=60, bases=[26],
    block_widths=vcat([2, 2], ones(Int, 56)))

# A 35-digit sixth-root identity with the same prefix-grouping rule.
sixth = Config(ndigits=35, roots=[6], bases=[136],
    block_widths=vcat([3, 2], ones(Int, 30)))

for (label, config, expected) in (
    ("Grouped square root", square, big(26)^42),
    ("Grouped sixth root", sixth, big(136)^16),
)
    result = search(config)
    @assert result.complete
    @assert [x.number for x in result.solutions] == [expected]
    x = only(result.solutions)
    println(label, " (", ndigits(x.number), " digits):")
    println(expression(x, config))
    println("Effective outer exponent: ", x.exponent)
    println()
end

# An all-different constraint rules out the original 262144 answer.
result = search(Config(distinct_digits=true))
@assert result.complete && isempty(result.solutions)
println("Six-digit original puzzle with distinct digits: no solutions.")
