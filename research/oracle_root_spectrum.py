#!/usr/bin/env python3
"""Independent exact Python reproduction of the unbounded-root classification.

Run: python3 research/oracle_root_spectrum.py
No Julia, optimizer, or third-party Python libraries are required. Enumerate
primitive powers, then test divisibility by prime valuations of the suffix.
Nested undefined powers propagate through zeros and ones eagerly.
"""
import argparse
import json
from math import gcd, prod


def factor(n):
    factors = []
    p = 2
    while p * p <= n:
        if n % p == 0:
            exponent = 0
            while n % p == 0:
                n //= p
                exponent += 1
            factors.append((p, exponent))
        p += 1
    if n > 1:
        factors.append((n, 1))
    return factors


def primitive(base):
    factors = factor(base)
    multiplicity = gcd(*(e for _, e in factors))
    value = prod(p ** (e // multiplicity) for p, e in factors)
    return value, multiplicity


def digits(n, radix):
    result = []
    while n:
        n, digit = divmod(n, radix)
        result.append(digit)
    return result[::-1]


def tower_cap(word, cap, zero_to_zero):
    value = min(word[-1], cap)
    for base in reversed(word[:-1]):
        if base == 0 and value == 0:
            if zero_to_zero == "forbid":
                return None
            value = 1
        elif value == 0 or base == 1:
            value = 1
        elif base == 0:
            value = 0
        elif base >= cap or value >= cap:
            value = cap
        else:
            power = 1
            for _ in range(value):
                power *= base
                if power >= cap:
                    break
            value = min(power, cap)
    return value


def classify(radix=10, min_length=2, max_length=1000,
             zero_to_zero="forbid", display_limit=1000):
    lower, upper = radix ** (min_length - 1), radix ** max_length - 1
    solutions, candidates = [], 0
    for leading in range(2, radix):
        a, g = primitive(leading)
        number, h = 1, 0
        while number <= upper // a:
            number *= a
            h += 1
            if number < lower:
                continue
            word = digits(number, radix)
            if word[0] != leading:
                continue
            candidates += 1
            c = word[1]
            if c < 2:
                continue  # E<=1 and N>b imply r=gE/h<1.
            k = h // gcd(h, g)
            threshold = 0
            for p, exponent in factor(k):
                residue, valuation = c, 0
                while residue % p == 0:
                    residue //= p
                    valuation += 1
                if valuation == 0:
                    break
                threshold = max(threshold, (exponent + valuation - 1) // valuation)
            else:
                tail = 1 if len(word) == 2 else tower_cap(
                    word[2:], max(2, threshold), zero_to_zero)
                if tail is None or tail < threshold:
                    continue
                # Entire suffix evaluation at a finite display threshold also
                # checks undefined descendants, without constructing the root.
                exponent_bound = h * display_limit // g
                suffix = tower_cap(word[1:], max(2, exponent_bound + 1), zero_to_zero)
                if suffix is None:
                    continue
                if suffix <= exponent_bound:
                    assert g * suffix % h == 0
                    small_root = g * suffix // h
                else:
                    small_root = None
                solutions.append({
                    "number": str(number), "digits": word, "primitive": a,
                    "g": g, "h": h, "k": k,
                    "required_tail_threshold": threshold,
                    "root_if_at_most_display_limit": small_root,
                })
    solutions.sort(key=lambda row: int(row["number"]))
    return {
        "radix": radix, "min_length": min_length, "max_length": max_length,
        "root_orders": "all positive integers, no upper bound",
        "zero_to_zero": zero_to_zero, "display_limit": display_limit,
        "complete": True, "candidates": candidates, "solutions": solutions,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--radix", type=int, default=10)
    parser.add_argument("--min-length", type=int, default=2)
    parser.add_argument("--max-length", type=int, default=1000)
    parser.add_argument("--zero-to-zero", choices=("forbid", "one"), default="forbid")
    parser.add_argument("--display-limit", type=int, default=1000)
    args = parser.parse_args()
    if not (args.radix >= 2 and 2 <= args.min_length <= args.max_length
            and args.display_limit >= 1):
        parser.error("require radix>=2, 2<=min_length<=max_length, display_limit>=1")
    result = classify(args.radix, args.min_length, args.max_length,
                      args.zero_to_zero, args.display_limit)
    if (args.radix, args.min_length, args.max_length) == (10, 2, 1000):
        assert result["candidates"] == 1702
        assert [int(row["number"]) for row in result["solutions"]] == [
            262144, 4294967296, 3 ** 64]
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
