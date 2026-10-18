module DigitTowersNemoExt

using DigitTowers
import Nemo

function nemo_ceiling(A::BigInt, a::BigInt)
    base = Nemo.ZZ(a)
    h = Int(Nemo.clog(Nemo.ZZ(A), base))
    return h, BigInt(base^h)
end

function DigitTowers.nemo_prefix_candidates(c::DigitTowers.Config, widths)
    return DigitTowers.prefix_candidates(c, widths; exponent_ceiling=nemo_ceiling)
end

end # module
