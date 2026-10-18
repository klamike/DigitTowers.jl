@testset "Undefined towers form the forbidden-00 language" begin
    function literal_tower(ds)
        value = BigInt(last(ds))
        for digit in reverse(ds[1:end-1])
            digit == 0 && value == 0 && return nothing
            value = BigInt(digit)^Int(value)
        end
        return value
    end
    for n in 1:3, word in Iterators.product(ntuple(_->0:3,n)...)
        ds = collect(word)
        @test tower_isdefined(ds) == !isnothing(literal_tower(ds))
        @test tower_isdefined(ds;zero_to_zero=:one)
    end
    @test !tower_isdefined(BigInt[2,1,0,0])
    @test tower_isdefined(BigInt[0])
    @test tower_isdefined(BigInt[0,1,0,1,0])
    @test_throws ArgumentError tower_isdefined(Int[])
    @test_throws ArgumentError tower_isdefined([2,-1])
    @test_throws ArgumentError tower_isdefined([2,1];zero_to_zero=:unknown)
end

@testset "Transfer matrix counts agree with complete word enumeration" begin
    for q in 2:5, n in 1:6, leading_zero in (false,true)
        words = Iterators.product(ntuple(_->0:q-1,n)...)
        expected = 0
        total = 0
        for word in words
            !leading_zero && first(word)==0 && continue
            total += 1
            # Independent recursive zero/positive/undefined semantics.
            state = last(word)==0 ? 0 : 1
            for a in reverse(word[1:end-1])
                if a==0 && state==0
                    state=-1
                    break
                end
                state = a==0 ? 0 : 1
            end
            expected += state != -1
        end
        result = tower_language_counts(n;radix=q,leading_zero)
        @test result.total == total
        @test result.defined == expected
        @test result.undefined == total-expected
        @test tower_language_counts(n;radix=q,leading_zero,zero_to_zero=:one).defined == total
    end
    large = tower_language_counts(1000)
    @test large.total == 9big(10)^999
    @test large.defined + large.undefined == large.total
    @test 0 < large.defined < large.total
    @test_throws ArgumentError tower_language_counts(0)
    @test_throws ArgumentError tower_language_counts(5;radix=1)
end
