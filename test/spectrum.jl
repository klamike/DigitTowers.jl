using Test
using DigitTowers
import Primes

# Literal enumeration and factorization of every tiny numeral. This neither
# uses primitive-power enumeration nor the k | c^T valuation criterion.
function literal_spectrum(radix, lengths, policy)
    found = Dict{BigInt,BigInt}()
    for L in lengths, N in radix^(L-1):radix^L-1
        ds = reverse!(digits(N; base=radix))
        first(ds) >= 2 || continue
        E, defined = big(last(ds)), true
        for i in L-1:-1:2
            if ds[i] == 0 && iszero(E) && policy == :forbid
                defined = false
                break
            end
            E = big(ds[i])^Int(E)
        end
        defined && E > 0 || continue
        bf, nf = Dict(Primes.factor(first(ds))), Dict(Primes.factor(N))
        Set(keys(bf)) == Set(keys(nf)) || continue
        p = first(keys(nf))
        numerator = bf[p] * E
        numerator % nf[p] == 0 || continue
        root = numerator ÷ nf[p]
        root > 0 || continue
        all(q -> bf[q]*E == nf[q]*root, keys(nf)) || continue
        found[big(N)] = root
    end
    return found
end

function modular_spectrum_oracle(radix, lengths, policy)
    found = Set{BigInt}()
    lo, hi = big(radix)^(first(lengths)-1), big(radix)^last(lengths)-1
    for b in 2:radix-1
        a, g = DigitTowers.primitive_base(b)
        N, h = big(1), 0
        while N <= hi ÷ a
            N *= a
            h += 1
            N < lo && continue
            ds = reverse!(digits(N; base=radix))
            first(ds) == b || continue
            # A zero suffix cannot give a positive root; c=1 gives residue1.
            ds[2] == 0 && continue
            k = h ÷ gcd(h, g)
            tower_mod(ds[2:end], k; zero_to_zero=policy) == 0 && push!(found, copy(N))
        end
    end
    return found
end

@testset "Unbounded roots against literal small numerals" begin
    for radix in 2:8, policy in (:forbid, :one)
        lengths = radix <= 5 ? (2:4) : (2:3)
        expected = literal_spectrum(radix, lengths, policy)
        result = root_spectrum(lengths; radix, zero_to_zero=policy, root_display_limit=1_000_000)
        @test result.complete
        @test Set(x.number for x in result.solutions) == Set(keys(expected))
        @test all(x -> x.root == expected[x.number] && verify(x), result.solutions)
    end
end

@testset "Valuation sieve against independent modular towers" begin
    for radix in (3, 7, 10, 17, 22), policy in (:forbid, :one)
        result = root_spectrum(2:100; radix, zero_to_zero=policy, max_solutions=10_000)
        expected = modular_spectrum_oracle(radix, 2:100, policy)
        @test result.complete
        @test Set(x.number for x in result.solutions) == expected
        finite = radix_sweep(radix, 2:100; roots=1:1000, zero_to_zero=policy,
                             max_solutions=10_000)
        @test Set((x.number, x.root) for x in result.solutions if !isnothing(x.root)) ==
              Set((x.number, big(x.root)) for x in finite.solutions)
    end
end

@testset "Decimal classification with no root-order bound" begin
    result = root_spectrum(2:1000)
    @test result.complete
    @test result.candidates == 1702
    @test result.method == :root_spectrum
    @test [x.number for x in result.solutions] ==
          BigInt[262144, 4294967296, big(3)^64]
    @test all(verify_root_certificate, result.solutions)
    original, enormous, third = result.solutions
    @test original.root == 2
    @test (enormous.primitive, enormous.g, enormous.h, enormous.k,
           enormous.required_tail_threshold) == (big(2), 2, 32, 16, 4)
    @test isnothing(enormous.root)
    @test all(>=(2), enormous.digits)
    @test occursin("2^(tower([9,4,9,6,7,2,9,6])-4) > 1000", expression(enormous))
    @test (third.primitive, third.g, third.h, third.k,
           third.required_tail_threshold) == (big(3), 1, 64, 64, 3)
    @test isnothing(third.root)
    @test length(third.digits) == 31
    @test occursin("4^(tower(", expression(third))
    hidden = root_spectrum(2:1000; root_display_limit=1)
    @test [x.number for x in hidden.solutions] == [x.number for x in result.solutions]
    @test all(x -> isnothing(x.root), hidden.solutions)
    restricted = root_spectrum(2:1000; allowed_digits=2:9)
    @test [x.number for x in restricted.solutions] == BigInt[4294967296]
    distinct = root_spectrum(2:1000; distinct_digits=true)
    @test distinct.complete && isempty(distinct.solutions)
    limited = root_spectrum(2:1000; max_solutions=1)
    @test !limited.complete
    @test limited.status == DigitTowers.MOI.SOLUTION_LIMIT
    @test length(limited.solutions) == 1
    bad = RootCertificate(enormous.number, enormous.radix, enormous.digits,
                          enormous.primitive, enormous.g, enormous.h, enormous.k,
                          enormous.required_tail_threshold + 1, enormous.root,
                          enormous.root_display_limit, enormous.zero_to_zero)
    @test !verify(bad)
    bad_root = RootCertificate(original.number, original.radix, original.digits,
                              original.primitive, original.g, original.h, original.k,
                              original.required_tail_threshold, big(3),
                              original.root_display_limit, original.zero_to_zero)
    @test !verify(bad_root)
end

@testset "Root-spectrum zero semantics and input validation" begin
    # A one/zero cannot hide undefined descendants. The helpers are deliberately
    # also exercised on cases rejected before the valuation sieve.
    @test DigitTowers._spectrum_tailcap([2, 2, 1, 0, 0], 4, :forbid) === nothing
    @test DigitTowers._spectrum_tailcap([2, 2, 1, 0, 0], 4, :one) == 1
    @test DigitTowers._spectrum_threshold(12, 2) === nothing
    @test DigitTowers._spectrum_threshold(16, 2) == 4
    @test DigitTowers._spectrum_threshold(64, 4) == 3
    @test_throws ArgumentError root_spectrum(1:10)
    @test_throws ArgumentError root_spectrum(2:1)
    @test_throws ArgumentError root_spectrum(2:10; radix=1)
    @test_throws ArgumentError root_spectrum(2:10; allowed_digits=Int[])
    @test_throws ArgumentError root_spectrum(2:10; allowed_digits=[10])
    @test_throws ArgumentError root_spectrum(2:10; zero_to_zero=:other)
    @test_throws ArgumentError root_spectrum(2:10; root_display_limit=0)
    @test_throws ArgumentError root_spectrum(2:10; max_solutions=0)
end
