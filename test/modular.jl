import Primes

function literal_tower(word, policy)
    value = BigInt(last(word))
    for a in Iterators.reverse(word[1:end-1])
        iszero(a) && iszero(value) && policy == :forbid && return nothing
        value = BigInt(a)^Int(value)
    end
    return value
end

# An independent prime-power/CRT oracle: p-adic valuations determine whether
# a nonunit power vanishes; Euler reduction is used only for units.
function crt_tower_mod(word, modulus, policy)
    zero = iszero(last(word))
    for a in Iterators.reverse(word[1:end-1])
        iszero(a) && zero && policy == :forbid && return nothing
        zero = iszero(a) && !zero
    end
    modulus == 1 && return 0
    length(word) == 1 && return mod(only(word), modulus)
    result, combined = big(0), big(1)
    for (p, k) in Primes.factor(modulus)
        primepower = p^k
        a = first(word)
        residue = if a % p != 0
            exponent = crt_tower_mod(word[2:end], Primes.totient(primepower), policy)
            powermod(a, exponent, primepower)
        else
            valuation, rest = 0, a
            while rest != 0 && rest % p == 0
                valuation += 1
                rest ÷= p
            end
            threshold = iszero(a) ? 1 : cld(k, valuation)
            exponent = big(last(word))
            for base in Iterators.reverse(word[2:end-1])
                # Binary powering saturates independently of the production
                # implementation's guarded multiplication loop.
                value, factor, power = big(1), big(base), exponent
                while power > 0
                    isodd(power) && (value = min(big(threshold), value * factor))
                    power >>= 1
                    factor = min(big(threshold), factor * factor)
                end
                exponent = value
            end
            exponent >= threshold ? 0 : powermod(a, exponent, primepower)
        end
        step = mod((residue - result) * invmod(combined, primepower), primepower)
        result += combined * step
        combined *= primepower
    end
    return Int(mod(result, modulus))
end

@testset "Modular towers agree with literal finite powers" begin
    for policy in (:forbid, :one), word in Iterators.product(0:5, 0:5, 0:5)
        values = collect(word)
        exact = literal_tower(values, policy)
        for modulus in (1, 2, 4, 6, 8, 10, 12, 25, 32, 60, 97, 100, 1000)
            expected = isnothing(exact) ? nothing : mod(exact, modulus)
            @test DigitTowers.tower_mod(values, modulus; zero_to_zero=policy) == expected
        end
    end
    for policy in (:forbid, :one), word in Iterators.product(0:2, 0:2, 0:2, 0:2)
        values = collect(word)
        exact = literal_tower(values, policy)
        expected = isnothing(exact) ? nothing : mod(exact, 10000)
        @test DigitTowers.tower_mod(values, 10000; zero_to_zero=policy) == expected
    end
    @test DigitTowers.tower_mod([2, 2, 3], 8) == 0 # naive exponent reduction gives 1
    @test DigitTowers.tower_mod([0, 1, 0, 0], 1) === nothing
    @test DigitTowers.tower_mod([1, 0, 0], 7) === nothing
    @test DigitTowers.tower_mod([1, 0, 0], 7; zero_to_zero=:one) == 1
    @test DigitTowers.tower_mod([big(10)^30, 2], big(2)^80) ==
        powermod(big(10)^30, 2, big(2)^80)
    @test DigitTowers.tower_mod([3, 3, 3, 3], big(2)^80) ==
        powermod(big(3), big(3)^27, big(2)^80)
    @test DigitTowers.tower_mod(fill(2, 100), big(2)^80) == 0
    @test DigitTowers.tower_mod([3, 3, 3, 3], big(10)^50) ==
        powermod(big(3), big(3)^27, big(10)^50)
    @test_throws ArgumentError DigitTowers.tower_mod([2, 3, 4], big(2)^127 - 1)
    @test_throws ArgumentError DigitTowers.tower_mod(Int[], 10)
    @test_throws ArgumentError DigitTowers.tower_mod([2, -1], 10)
    @test_throws ArgumentError DigitTowers.tower_mod([2, 3], 0)
    @test_throws ArgumentError DigitTowers.tower_mod([2, 3], 10; zero_to_zero=:other)
end

@testset "Long modular towers agree with independent prime-power CRT" begin
    words = [[2, 3, 4, 5, 6, 7, 8, 9], fill(2, 100), fill(9, 100),
             [9, 0, 8, 1, 2, 0, 7, 6, 5, 4, 3, 2], [1, 0, 0, 2, 1],
             [0, 0, 0, 0, 0], [4, 2, 6, 3, 8, 2]]
    for policy in (:forbid, :one), word in words, modulus in 1:100
        @test DigitTowers.tower_mod(word, modulus; zero_to_zero=policy) ==
            crt_tower_mod(word, modulus, policy)
    end
end

@testset "Modular fixed points and finite dynamics" begin
    for width in 2:4
        result = DigitTowers.modular_fixedpoints(width)
        @test result.complete
        @test isempty(result.solutions)
        @test result.examined == 9 * 10^(width-1)
    end
    @test DigitTowers.modular_fixedpoints(2; radix=6).solutions == [16] # 24_6
    @test DigitTowers.modular_fixedpoints(2; radix=8).solutions == [27] # 33_8
    @test DigitTowers.modular_fixedpoints(2; radix=8, allowed_digits=[3]).solutions == [27]
    @test DigitTowers.modular_fixedpoints(2; radix=8, allowed_digits=[1,2]).solutions == []
    @test DigitTowers.modular_fixedpoints(1; padded=true).solutions == collect(0:9)
    @test DigitTowers.modular_dynamics(1).basin_sizes == ones(Int, 10)
    three = DigitTowers.modular_dynamics(3)
    @test three.complete
    @test three.cycles == [[456, 624]]
    @test three.basin_sizes == [40]
    @test three.undefined == 19
    @test three.undefined_basin == 960
    four = DigitTowers.modular_dynamics(4)
    @test four.cycles == [[3456, 8481, 6256, 3936, 6483]]
    @test four.basin_sizes == [156]
    @test four.undefined_basin == 9844
    for policy in (:forbid, :one), radix in (2, 6, 10), width in 2:3
        result = DigitTowers.modular_dynamics(width; radix, zero_to_zero=policy)
        @test sum(result.basin_sizes) + result.undefined_basin == radix^width
        for cycle in result.cycles, i in eachindex(cycle)
            word = reverse(digits(cycle[i]; base=radix, pad=width))
            next = cycle[mod1(i+1, length(cycle))]
            @test DigitTowers.tower_mod(word, radix^width; zero_to_zero=policy) == next
        end
    end
    @test_throws ArgumentError DigitTowers.modular_fixedpoints(0)
    @test_throws ArgumentError DigitTowers.modular_fixedpoints(2; radix=1)
    @test_throws ArgumentError DigitTowers.modular_fixedpoints(6)
    @test_throws ArgumentError DigitTowers.modular_fixedpoints(typemax(Int))
    @test_throws ArgumentError DigitTowers.modular_fixedpoints(2; allowed_digits=[10])
    @test_throws ArgumentError DigitTowers.modular_dynamics(2; zero_to_zero=:other)
end
