using DigitTowers
using TOML

function main()
    out = joinpath(@__DIR__,"results")
    mkpath(out)
    open(joinpath(out,"language_counts.tsv"),"w") do io
        println(io,"radix\tlength\tleading_zero\tdefined\tundefined\ttotal\tdefined_fraction")
        for q in (2,10,22), n in (1,2,3,4,10,100,1000), padded in (false,true)
            r=tower_language_counts(n;radix=q,leading_zero=padded)
            println(io,join((q,n,padded,r.defined,r.undefined,r.total,
                            Float64(r.defined//r.total)),'\t'))
        end
    end
    candidates=undefined=0
    longest_defined=0
    upper=big(10)^1000-1
    for base in 2:9
        a,_=DigitTowers.primitive_base(base)
        n=big(1)
        while n<=upper÷a
            n*=a
            n>=10 || continue
            text=string(n)
            Int(first(text)-'0')==base || continue
            ds=[Int(ch-'0') for ch in text]
            candidates+=1
            if tower_isdefined(ds)
                longest_defined=max(longest_defined,length(ds))
            else
                undefined+=1
            end
        end
    end
    @assert candidates==1702
    for q in (2,5,10), n in 1:4
        graph=modular_dynamics(n;radix=q)
        @assert graph.undefined==tower_language_counts(n;radix=q,leading_zero=true).undefined
    end
    metadata=Dict("max_digits"=>1000,"radix"=>10,"candidates"=>candidates,
        "undefined_candidates"=>undefined,"defined_candidates"=>candidates-undefined,
        "longest_defined_candidate"=>longest_defined,
        "word_count_method"=>"Exact two-state transfer matrix; binary exponentiation",
        "zero_to_zero"=>"forbid")
    open(joinpath(out,"language_profile.toml"),"w") do io
        TOML.print(io,metadata;sorted=true)
    end
    println(metadata)
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
