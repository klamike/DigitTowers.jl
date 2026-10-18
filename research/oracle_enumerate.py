#!/usr/bin/env python3
"""Independent integer oracle; no package imports or optimization solver.

Candidates come from prime-factor arithmetic; the recursive oracle computes
nonnegative suffix towers in the exact quotient {0,...,limit-1,>=limit}.
Undefined 0^0 propagates eagerly even through zero/one blockers.
Running this file reproduces every scope in oracle_results.json, including
the square-root sweep through 100 digits and external roots 1--1000.
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

PRIMITIVES = {2: (2, 1), 3: (3, 1), 4: (2, 2), 5: (5, 1),
              6: (6, 1), 7: (7, 1), 8: (2, 3), 9: (3, 2)}


def bounded_mul(a: int, b: int, limit: int) -> int:
    if a == 0 or b == 0:
        return 0
    if a > (limit - 1) // b:
        return limit
    return a * b


def bounded_pow(base: int, exponent: int, limit: int):
    if base == 0 and exponent == 0:
        return None
    ans = 1
    while exponent:
        if exponent & 1:
            ans = bounded_mul(ans, base, limit)
        exponent >>= 1
        if exponent:
            base = bounded_mul(base, base, limit)
    return ans


def suffix_oracle(digits: tuple[int, ...], limit: int):
    # Recursive eager order independently ensures no undefined descendant is
    # masked by a zero/one base above it.
    if len(digits) == 1:
        return min(digits[0], limit)
    child = suffix_oracle(digits[1:], limit)
    if child is None:
        return None
    return bounded_pow(digits[0], child, limit)


def full_oracle(number: int, root: int, consumed: bool):
    ds = tuple(map(int, str(number)))
    if consumed:
        if ds[0] != root:
            return False
        ds = ds[1:]
    base = ds[0]
    if base not in PRIMITIVES:
        return False
    primitive, multiplicity = PRIMITIVES[base]
    t, h = number, 0
    while t % primitive == 0:
        t //= primitive
        h += 1
    if t != 1 or (h * root) % multiplicity:
        return False
    required = h * root // multiplicity
    return suffix_oracle(ds[1:], required + 1) == required


def enumerate_region(max_digits: int, roots: range, consumed: bool):
    lower_len = 3 if consumed else 2
    maximum = 10 ** max_digits - 1
    checked = 0
    found = []
    for base, (a, g) in PRIMITIVES.items():
        n, h = a, 1
        while n <= maximum:
            text = str(n)
            ds = tuple(map(int, text))
            base_position = 1 if consumed else 0
            if len(ds) >= lower_len and ds[base_position] == base:
                for r in roots:
                    if consumed and ds[0] != r:
                        continue
                    if (r * h) % g:
                        continue
                    e = r * h // g
                    checked += 1
                    if suffix_oracle(ds[base_position + 1:], e + 1) == e:
                        assert n ** r == base ** e
                        found.append(dict(number=str(n), root=r, ndigits=len(ds),
                                          required_exponent=e, outer_base=base))
            n *= a
            h += 1
    found.sort(key=lambda item: (int(item['number']), item['root']))
    return dict(min_digits=lower_len, max_digits=max_digits,
                roots=list(roots), consumed_root_digit=consumed,
                candidate_count=checked,
                all_digits=found,
                zero_free=[s for s in found if '0' not in s['number']],
                no_zero_or_one=[s for s in found if not ({'0','1'} & set(s['number']))])


def self_test():
    # Compare all low-height values to direct integers.
    from itertools import product
    for size in range(1, 5):
        for ds in product(range(4 if size < 4 else 3), repeat=size):
            def direct(seq):
                if len(seq) == 1:
                    return seq[0]
                e = direct(seq[1:])
                if e is None or (seq[0] == 0 and e == 0):
                    return None
                return seq[0] ** e
            exact = direct(ds)
            for limit in (2,3,4,5,7,10,20,100):
                assert suffix_oracle(ds, limit) == (None if exact is None else min(exact, limit)), (ds,limit,exact)
    assert suffix_oracle((1,0,0),10) is None
    assert full_oracle(262144,2,False)
    assert full_oracle(22,2,False) is False


def derived_root_region(max_digits: int, max_root: int, min_root: int = 1):
    """Derive r=g*E/h after one capped suffix evaluation per candidate N."""
    maximum = 10 ** max_digits - 1
    checked = 0
    found = []
    for base, (a, g) in PRIMITIVES.items():
        n, h = a, 1
        while n <= maximum:
            ds = tuple(map(int, str(n)))
            if len(ds) >= 2 and ds[0] == base:
                checked += 1
                cap = max_root * h // g + 1
                e = suffix_oracle(ds[1:], cap)
                if e is not None and e < cap and (g * e) % h == 0:
                    r = g * e // h
                    if min_root <= r <= max_root:
                        assert n ** r == base ** e
                        found.append(dict(number=str(n),root=r,ndigits=len(ds),
                                          required_exponent=e,outer_base=base))
            n *= a
            h += 1
    found.sort(key=lambda s: (int(s['number']),s['root']))
    return dict(min_digits=2,max_digits=max_digits,min_root=min_root,max_root=max_root,
                candidate_count=checked,all_digits=found,
                zero_free=[s for s in found if '0' not in s['number']],
                no_zero_or_one=[s for s in found if not ({'0','1'} & set(s['number']))])


if __name__ == '__main__':
    # The independent recursive evaluator must accommodate 1000-digit tails.
    sys.setrecursionlimit(max(sys.getrecursionlimit(), 2500))
    self_test()
    results = {
        'strict_square_root_lengths_2_to_100': enumerate_region(100,range(2,3),False),
        'roots_2_to_9_lengths_2_to_20': enumerate_region(20,range(2,10),False),
        'consumed_roots_2_to_9_lengths_3_to_20': enumerate_region(20,range(2,10),True),
        'roots_1_to_9_lengths_2_to_20': derived_root_region(20,9),
        'roots_1_to_1000_lengths_2_to_100': derived_root_region(100,1000),
        'roots_1_to_1000_lengths_2_to_1000': derived_root_region(1000,1000),
    }
    output = Path(__file__).with_name('oracle_results.json')
    output.write_text(json.dumps(results,indent=2) + '\n')
    for name, item in results.items():
        print(name, 'candidates=',item['candidate_count'])
        for label in ('all_digits','zero_free','no_zero_or_one'):
            print(label,[(s['number'],s['root'],s['required_exponent']) for s in item[label]])
