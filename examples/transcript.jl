using DigitTowers

function show_result(label, c; max_solutions=100)
    result = search(c; max_solutions)
    println("\n", label, " [candidates=", result.candidates, ", cap=", result.cap,
        ", complete=", result.complete, "]")
    !result.complete && println("  Enumeration stopped: ", result.status)
    for x in result.solutions
        println("  ", expression(x, c), "   [outer exponent ", x.exponent, "]")
    end
    return result
end

show_result("Original rules", Config())
show_result("Original rules, zero-free", Config(allowed_digits=collect(1:9)))
show_result("Seventh root and a two-digit exponent block",
    Config(ndigits=3, roots=[7], block_widths=[1, 2]))
show_result("Transcript's grouped 20-digit square-root example",
    Config(ndigits=20, bases=[3162278], block_widths=[7, 1, 7, 1, 4]))

# The 6 is used once as the root order. Remaining blocks are:
# 7 | 82 | 2 | 3 | 0 | 7 | 2 | 8 | 4 | 9.
show_result("Transcript's final example (root digit, grouping, addition)",
    Config(ndigits=12, roots=[6], root_digits=1,
        block_widths=[1, 2, 1, 1, 1, 1, 1, 1, 1, 1],
        operators=[:^, :+, :^, :^, :^, :^, :^, :^, :^]))

# Further configurations:
# search(Config(ndigits=10, roots=collect(2:9)))
# search(Config(ndigits=8, allowed_digits=collect(2:9))) # neither zero nor one
# search(Config(ndigits=12, root_digits=1, roots=collect(2:9)))
# search(Config(zero_to_zero=:one)) # opt into Julia's 0^0=1 convention
