# Run from the repository: julia --project=. examples/playground.jl
using DigitTowers

# Unbounded root orders, bounded numeral lengths. Large roots remain symbolic.
roots = root_spectrum(2:1000)
@assert roots.complete && roots.candidates == 1702
@assert getfield.(roots.solutions, :number) == BigInt[
    262144, 4294967296, big"3433683820292512484657849089281"]
for certificate in roots.solutions
    @assert verify(certificate)
    println(expression(certificate))
end

# Find a cheapest expression while keeping every digit separate.
repair = synthesize(94143178827; roots=[6], max_block_width=1,
                    allow_addition=true)
certificate = only(repair.certificates)
@assert repair.complete && verify(certificate)
@assert certificate.cost == certificate.additions == 2
println(expression(certificate))

# Integer-valued digit labels: F=15, A=10 in radix 22.
atlas = radix_sweep(22, 2:8; roots=[1], allowed_digits=1:21)
@assert atlas.complete
radix_example = only(filter(x -> x.number == big(15)^9, atlas.solutions))
@assert radix_example.digits == [15,9,1,10,7,2,10,3]
@assert verify_radix(radix_example)
println(expression_radix(radix_example))

# Every padded three-digit word is a state, including 000 through 099.
graph = modular_dynamics(3)
@assert graph.complete && graph.cycles == [[456,624]]
@assert graph.basin_sizes == [40] && graph.undefined_basin == 960
println("Modulo 1000: ", graph.cycles, "; basin sizes: ", graph.basin_sizes)

counts = tower_language_counts(1000)
@assert counts.defined + counts.undefined == 9big(10)^999
println("Defined 1000-digit towers: ", Float64(counts.defined // counts.total))

# Reorder every digit once, minimizing changed positions in the displayed word.
anagram = only(anagram_towers(64).certificates)
@assert verify(anagram) && anagram.digits == [4,6] && anagram.moves == 2
println(expression(anagram))

# All tradeoffs, including a middle choice no nonzero weighted sum can select.
frontier = synthesize_frontier(2199023255552; roots=[6], max_base_width=1)
costs = [(x.concatenations, x.additions) for x in frontier.certificates]
@assert frontier.complete && costs == [(2,8),(4,7),(5,6)]
@assert all(verify, frontier.certificates)
println("Join/plus frontier: ", costs)

near = modular_nearpoints(3; metric=:circular)
@assert near.complete && near.minimum_count == 1 && near.minimum_distance == 2
@assert only(near.minimizers) == (number=971, successor=969, distance=2)
println("Closest three-digit circular match: ", only(near.minimizers))

orbit = modular_orbit(big(2)^999, 1000; radix=2, zero_to_zero=:one)
@assert orbit.complete && (orbit.preperiod, orbit.period, orbit.entry) == (1,2,big(1))
println("Orbit in 2^1000 states: preperiod ", orbit.preperiod,
    ", period ", orbit.period, "; ", orbit.evaluations, " map evaluations")
