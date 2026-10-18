function visited_orbit_oracle(start, width, radix, policy)
    seen = Dict{BigInt,Int}()
    value, position = big(start), 0
    while !haskey(seen, value)
        seen[value] = position
        word = reverse(digits(value; base=radix, pad=width))
        next = tower_mod(word, big(radix)^width; zero_to_zero=policy)
        if isnothing(next)
            return (; termination=:undefined, preperiod=nothing, period=nothing,
                entry=nothing, undefined_at=value, distance_to_undefined=position)
        end
        value = BigInt(next)
        position += 1
    end
    return (; termination=:cycle, preperiod=seen[value], period=position-seen[value],
        entry=value, undefined_at=nothing, distance_to_undefined=nothing)
end

@testset "Brent orbits agree with independently stored trajectories" begin
    for policy in (:forbid, :one), radix in 2:6, width in 1:3,
            start in 0:radix^width-1
        expected = visited_orbit_oracle(start, width, radix, policy)
        actual = modular_orbit(start, width; radix, zero_to_zero=policy)
        @test actual.complete
        @test all(getproperty(actual, field) == getproperty(expected, field)
            for field in keys(expected))
    end
    orbit = modular_orbit(426, 3)
    @test (orbit.preperiod, orbit.period, orbit.entry) == (1, 2, big(456))
    @test modular_orbit(624, 3).entry == 624
    @test modular_orbit(3456, 4).period == 5
    undefined = modular_orbit(123, 3)
    @test undefined.termination == :undefined
    @test undefined.undefined_at == 1 && undefined.distance_to_undefined == 1
end

@testset "Orbit budgets preserve partial-search semantics" begin
    complete = modular_orbit(426, 3)
    for budget in 1:complete.evaluations-1
        partial = modular_orbit(426, 3; max_evaluations=budget)
        @test !partial.complete && partial.termination == :limit
        @test partial.evaluations == budget
        @test all(isnothing, (partial.preperiod, partial.period, partial.entry,
            partial.undefined_at, partial.distance_to_undefined))
    end
    @test modular_orbit(426, 3; max_evaluations=complete.evaluations).complete
    @test modular_orbit(0, 3; max_evaluations=1).termination == :undefined
    @test_throws ArgumentError modular_orbit(-1, 3)
    @test_throws ArgumentError modular_orbit(1000, 3)
    @test_throws ArgumentError modular_orbit(0, 0)
    @test_throws ArgumentError modular_orbit(0, 3; radix=1)
    @test_throws ArgumentError modular_orbit(0, 3; max_width=2)
    @test_throws ArgumentError modular_orbit(0, 3; max_evaluations=0)
    @test_throws ArgumentError modular_orbit(0, 3; zero_to_zero=:invalid)
end

@testset "Universal zero-one cycles and enormous binary domains" begin
    for radix in (2, 3, 7, 10), width in 2:12
        zero = modular_orbit(0, width; radix, zero_to_zero=:one)
        one = modular_orbit(1, width; radix, zero_to_zero=:one)
        @test zero.complete && one.complete
        @test zero.preperiod == one.preperiod == 0
        @test zero.period == one.period == (iseven(width) ? 2 : 1)
        @test zero.entry == 0 && one.entry == 1
    end
    for policy in (:forbid, :one), width in (100, 1000)
        result = modular_orbit(big(2)^(width-1), width;
            radix=2, zero_to_zero=policy)
        @test result.complete
        if policy == :forbid
            @test result.termination == :undefined
            @test result.distance_to_undefined == 0
        else
            @test (result.preperiod, result.period, result.entry) == (1, 2, big(1))
            @test result.evaluations < 20
        end
    end
end
