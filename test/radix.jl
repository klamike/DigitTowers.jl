using Test
using DigitTowers

radix_answers(xs) = sort!([(x.number, x.root, x.exponent) for x in xs])

# Deliberately separate from primitive powers, logarithms, and capped suffixes:
# enumerate every numeral, evaluate its short suffix literally, and repeatedly
# divide N^r by its leading digit. Tiny radices keep exact suffixes manageable.
function brute_radix(radix, lengths, roots; zero_to_zero=:forbid,
                     allowed_digits=0:radix-1, distinct_digits=false)
    found = Tuple{BigInt,Int,Int}[]
    for L in lengths, N in radix^(L-1):radix^L-1
        ds = reverse!(digits(N; base=radix))
        first(ds) >= 2 || continue
        all(in(allowed_digits), ds) || continue
        distinct_digits && !allunique(ds) && continue
        E = big(last(ds))
        defined = true
        for i in L-1:-1:2
            if ds[i] == 0 && E == 0 && zero_to_zero == :forbid
                defined = false
                break
            end
            E = big(ds[i])^Int(E)
        end
        defined || continue
        for r in roots
            q, exponent = big(N)^r, 0
            while q % first(ds) == 0
                q ÷= first(ds)
                exponent += 1
            end
            q == 1 && E == exponent && push!(found, (big(N), r, exponent))
        end
    end
    return sort!(found)
end

@testset "Radix search against independent literal enumeration" begin
    for radix in 2:5, policy in (:forbid, :one),
        domain in (collect(0:radix-1), collect(1:radix-1), collect(2:radix-1)),
        distinct in (false, true)
        isempty(domain) && continue
        result = radix_sweep(radix, 2:4; roots=1:12, allowed_digits=domain,
                             distinct_digits=distinct, zero_to_zero=policy)
        expected = brute_radix(radix, 2:4, 1:12; allowed_digits=domain,
                               distinct_digits=distinct, zero_to_zero=policy)
        @test result.complete
        @test result.method == :radix_sweep
        @test radix_answers(result.solutions) == expected
        @test all(x -> verify_radix(x; zero_to_zero=policy), result.solutions)
    end
end

@testset "Radix ten preserves decimal search" begin
    for policy in (:forbid, :one), domain in (collect(0:9), collect(1:9)),
        distinct in (false, true)
        decimal = sweep(2:100; roots=1:1000, allowed_digits=domain,
                        distinct_digits=distinct, zero_to_zero=policy)
        other = radix_sweep(10, 2:100; roots=1:1000, allowed_digits=domain,
                            distinct_digits=distinct, zero_to_zero=policy)
        @test other.complete
        @test radix_answers(other.solutions) == radix_answers(decimal.solutions)
        @test other.candidates == decimal.candidates
        @test other.cap == decimal.cap
    end
end

@testset "Nondecimal fixed points and infinite two-digit family" begin
    fixed = only(radix_sweep(22, 3:100; roots=[1]).solutions)
    @test fixed.number == big(15)^9 == 38443359375
    @test fixed.digits == [15, 9, 1, 10, 7, 2, 10, 3]
    @test verify_radix(fixed)
    @test expression_radix(fixed) ==
        "root_1((15^(9^(1^(10^(7^(2^(10^3)))))))) = [15,9,1,10,7,2,10,3]_22 = 38443359375"
    fixed17 = only(radix_sweep(17, 3:100; roots=[1]).solutions)
    @test fixed17.number == big(12)^9
    @test fixed17.digits == [12, 9, 13, 0, 4, 1, 4, 5]
    fixed34 = only(radix_sweep(34, 3:100; roots=[1]).solutions)
    @test fixed34.number == big(16)^29
    @test length(fixed34.digits) == 23
    for a in 3:8
        radix = Int(big(a)^(a-1) - 1)
        x = RadixSolution(big(a)^a, radix, 1, a, [a, a])
        @test verify_radix(x)
        # Search small members; larger family members need no huge base scan.
        if radix <= 63
            @test any(y -> y.number == x.number && y.digits == x.digits,
                      radix_sweep(radix, 2:2; roots=[1]).solutions)
        end
    end
    # A run of radices encodes the same integer with consecutive root orders.
    for a in 3:8
        last_root = min(100, (a^(a-1) - 1) ÷ (a+1))
        for root in unique([1, min(7, last_root), last_root])
            radix = a^(a-1) - root
            x = RadixSolution(big(a)^a, radix, root, a*root, [a, a*root])
            @test verify_radix(x)
        end
    end
    @test !verify_radix(RadixSolution(fixed.number + 1, fixed.radix, fixed.root,
                                    fixed.exponent, fixed.digits))
    @test !verify_radix(RadixSolution(fixed.number, fixed.radix, fixed.root,
                                    fixed.exponent + 1, fixed.digits))
    @test !verify_radix(RadixSolution(big(22), 2, 1, 2, [2, 2]))
    @test !verify_radix(RadixSolution(big(1), 10, 1, 1, [1]))
    limited = radix_sweep(7, 2:100; roots=1:1000, max_solutions=1)
    @test !limited.complete
    @test length(limited.solutions) == 1
    @test limited.status == DigitTowers.MOI.SOLUTION_LIMIT
end

@testset "Radix input validation" begin
    @test_throws ArgumentError radix_sweep(1, 2:10)
    @test_throws ArgumentError radix_sweep(10, 1:10)
    @test_throws ArgumentError radix_sweep(10, 2:1)
    @test_throws ArgumentError radix_sweep(10, 2:10; roots=Int[])
    @test_throws ArgumentError radix_sweep(10, 2:10; roots=[0])
    @test_throws ArgumentError radix_sweep(10, 2:10; allowed_digits=Int[])
    @test_throws ArgumentError radix_sweep(10, 2:10; allowed_digits=[10])
    @test_throws ArgumentError radix_sweep(10, 2:10; zero_to_zero=:other)
    @test_throws ArgumentError radix_sweep(10, 2:10; max_solutions=0)
    @test_throws ArgumentError verify_radix(RadixSolution(big(27), 8, 1, 3, [3, 3]);
                                           zero_to_zero=:other)
end
