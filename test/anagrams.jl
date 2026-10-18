# Independent permutation oracle: no chart states or production power routine.
function anagram_oracle_words(digits)
    length(digits) == 1 && return [copy(digits)]
    words = Vector{Int}[]
    for i in eachindex(digits)
        i > 1 && digits[i] in digits[1:i-1] && continue
        remaining = [digits[1:i-1]; digits[i+1:end]]
        for tail in anagram_oracle_words(remaining)
            push!(words, [digits[i]; tail])
        end
    end
    return words
end

function anagram_oracle_power(base, exponent, cap, policy)
    base == 0 && exponent == 0 && policy == :forbid && return nothing
    exponent == 0 && return big(1)
    base == 0 && return big(0)
    base == 1 && return big(1)
    # Every base >= 2 raised to cap exceeds cap. All smaller powers use
    # independent BigInt repeated squaring with an exact overflow sentinel.
    exponent >= cap && return BigInt(cap)
    result, factor, residue = big(1), BigInt(base), Int(exponent)
    while residue > 0
        isodd(residue) && (result = min(BigInt(cap), result*factor))
        residue >>= 1
        residue > 0 && (factor = min(BigInt(cap), factor*factor))
    end
    return min(BigInt(cap), result)
end

function anagram_oracle(number, roots, policy)
    original = Int[c-'0' for c in string(number)]
    best = Dict{Tuple{Int,Int},Tuple{Int,Vector{Int}}}()
    for word in anagram_oracle_words(original)
        base = first(word)
        base >= 2 || continue
        for root in roots
            target = BigInt(number)^root
            power, exponent = big(1), 0
            while power < target
                power *= base
                exponent += 1
            end
            power == target || continue
            cap = exponent+1
            value = min(BigInt(cap), last(word))
            for i in length(word)-1:-1:2
                value = anagram_oracle_power(word[i], value, cap, policy)
                isnothing(value) && break
            end
            value == exponent || continue
            moves = count(i -> original[i] != word[i], eachindex(word))
            key = (root, base)
            proposal = (moves, word)
            if !haskey(best, key) || isless(proposal, best[key])
                best[key] = proposal
            end
        end
    end
    return best
end

@testset "Anagram towers versus literal permutations" begin
    for policy in (:forbid, :one), number in [collect(10:170);
            256; 512; 625; 729; 1024; 1296; 2187; 4096; 6561; 15625;
            78125; 262144; 390625; 531441]
        result = DigitTowers.anagram_towers(number; roots=1:9, zero_to_zero=policy)
        actual = Dict((x.root, first(x.digits)) => (x.moves, x.digits)
            for x in result.certificates)
        @test result.complete
        @test actual == anagram_oracle(number, 1:9, policy)
        @test all(verify, result.certificates)
    end
end

@testset "Anagram certificates and resource guards" begin
    result = DigitTowers.anagram_towers(262144)
    @test result.method == :anagrams
    @test result.targets == 2 # The available bases 2 and 4 share primitive base 2.
    @test all(verify, result.certificates)
    @test minimum(x.moves for x in result.certificates) == 0
    original = only(filter(x -> x.moves == 0, result.certificates))
    @test expression(original) == "root_2((2^(6^(2^(1^(4^4)))))) = 262144"
    @test !verify(DigitTowers.AnagramCertificate(original.number, original.root,
        original.exponent, reverse(original.digits), original.moves, :forbid))
    @test !verify(DigitTowers.AnagramCertificate(original.number, original.root,
        original.exponent+1, original.digits, original.moves, :forbid))
    @test !verify(DigitTowers.AnagramCertificate(original.number, original.root,
        original.exponent, original.digits, original.moves+1, :forbid))
    @test isempty(DigitTowers.anagram_towers(123456).certificates)
    @test_throws ArgumentError DigitTowers.anagram_towers(9)
    @test_throws ArgumentError DigitTowers.anagram_towers(256; roots=[])
    @test_throws ArgumentError DigitTowers.anagram_towers(256; roots=[0])
    @test_throws ArgumentError DigitTowers.anagram_towers(256; zero_to_zero=:unknown)
    @test_throws ArgumentError DigitTowers.anagram_towers(256; max_states=0)
    @test_throws ArgumentError DigitTowers.anagram_towers(256; max_exponent=0)
    @test_throws ArgumentError DigitTowers.anagram_towers(262144; max_states=1)
    @test_throws ArgumentError DigitTowers.anagram_towers(262144; max_exponent=1)
    @test DigitTowers.anagram_towers(262144; roots=[2,2]).certificates[1].digits ==
          result.certificates[1].digits
    moved = only(DigitTowers.anagram_towers(64).certificates)
    @test moved.digits == [4,6]
    @test moved.moves == 2
    @test verify(moved)
    distinct = only(DigitTowers.anagram_towers(625; roots=2:9).certificates)
    @test distinct.root == 9 && distinct.digits == [5,6,2]
    @test distinct.moves == 3
    no_root = only(DigitTowers.anagram_towers(4096; roots=[1]).certificates)
    @test no_root.digits == [4,6,9,0]
    @test no_root.exponent == 6 && verify(no_root)
end
