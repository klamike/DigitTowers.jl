#!/usr/bin/env python3
"""Independent search over all contiguous decimal partitions.

The command-line defaults exhaust all outer base widths, 2--10 total digits,
and root orders 2--9. Use --max-outer-width to restrict the outer base instead.
No multidigit block starts with zero, and every nested 0^0 is undefined.
Only the Python standard library is required.
"""
from itertools import product
from math import gcd
from pathlib import Path
import json
from oracle_enumerate import suffix_oracle


def primitive_base(b):
    rest=b
    factors=[]
    p=2
    while p*p<=rest:
        e=0
        while rest%p==0:
            rest//=p
            e+=1
        if e:
            factors.append((p,e))
        p+=1
    if rest>1:
        factors.append((rest,1))
    g=0
    for _,e in factors:
        g=gcd(g,e)
    a=1
    for p,e in factors:
        a*=p**(e//g)
    return a,g


def partitions(text):
    for cuts in product((False,True),repeat=len(text)-1):
        chunks=[]
        start=0
        for i,cut in enumerate(cuts,1):
            if cut:
                chunks.append(text[start:i])
                start=i
        chunks.append(text[start:])
        if all(len(c)==1 or c[0]!='0' for c in chunks):
            yield tuple(int(c) for c in chunks),tuple(len(c) for c in chunks)


def run(max_digits=10,max_outer_width=3,max_root=9):
    candidates=0
    tested=0
    found=[]
    top=10**max_digits-1
    for b in range(2,10**max_outer_width):
        a,g=primitive_base(b)
        n,h=a,1
        bstr=str(b)
        while n<=top:
            text=str(n)
            if len(text)>len(bstr) and text.startswith(bstr):
                candidates+=1
                for tail,widths in partitions(text[len(bstr):]):
                    tested+=1
                    for r in range(2,max_root+1):
                        if r*h%g:
                            continue
                        e=r*h//g
                        if suffix_oracle(tail,e+1)==e:
                            assert n**r==b**e
                            bs=(b,)+tail
                            ws=(len(bstr),)+widths
                            found.append(dict(number=str(n),root=r,required_exponent=e,
                                              blocks=bs,widths=ws,
                                              concatenations=sum(w-1 for w in ws),
                                              grouped_blocks=sum(w>1 for w in ws)))
            n*=a
            h+=1
    found.sort(key=lambda s:(int(s['number']),s['root'],s['concatenations'],s['widths']))
    return dict(max_digits=max_digits,max_outer_width=max_outer_width,
                min_root=2,max_root=max_root,candidate_bases_numbers=candidates,
                partitions_checked=tested,solutions=found)


def all_outer_widths(max_digits=10,max_root=9):
    from math import isqrt
    top=10**max_digits-1
    last_a=isqrt(top)
    nonprimitive=set()
    for seed in range(2,isqrt(last_a)+1):
        value=seed*seed
        while value<=last_a:
            nonprimitive.add(value)
            value*=seed
    pairs=[]
    for a in range(2,last_a+1):
        if a in nonprimitive:
            continue
        powers=[1,a]
        while powers[-1]<=top//a:
            powers.append(powers[-1]*a)
        for h in range(2,len(powers)):
            n=powers[h]
            text=str(n)
            for g in range(1,h):
                b=powers[g]
                bstr=str(b)
                if len(bstr)<len(text) and text.startswith(bstr):
                    pairs.append((b,n,h,g))
    tested=0
    found=[]
    for b,n,h,g in pairs:
        text=str(n)
        bstr=str(b)
        for tail,widths in partitions(text[len(bstr):]):
            tested+=1
            for r in range(2,max_root+1):
                if r*h%g:
                    continue
                e=r*h//g
                if suffix_oracle(tail,e+1)==e:
                    assert n**r==b**e
                    ws=(len(bstr),)+widths
                    found.append(dict(number=str(n),root=r,required_exponent=e,
                                      blocks=(b,)+tail,widths=ws,
                                      concatenations=sum(w-1 for w in ws),
                                      grouped_blocks=sum(w>1 for w in ws)))
    found.sort(key=lambda s:(int(s['number']),s['root'],s['concatenations'],s['widths']))
    return dict(max_digits=max_digits,max_outer_width='unrestricted',
                min_root=2,max_root=max_root,candidate_bases_numbers=len(pairs),
                partitions_checked=tested,solutions=found)


def main():
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--max-digits',type=int,default=10,
                        help='maximum total decimal digits (default: 10)')
    parser.add_argument('--max-root',type=int,default=9,
                        help='search root orders 2 through this value (default: 9)')
    parser.add_argument('--max-outer-width',type=int,default=None,
                        help='restrict outer base width; omitted means all widths')
    parser.add_argument('--output',type=Path,default=None,
                        help='JSON path; defaults to the matching file beside this script')
    args=parser.parse_args()
    if args.max_digits<2 or args.max_root<2:
        parser.error('--max-digits and --max-root must each be at least 2')
    if args.max_outer_width is not None and args.max_outer_width<1:
        parser.error('--max-outer-width must be positive')
    if args.max_outer_width is None:
        results=all_outer_widths(args.max_digits,args.max_root)
        filename='oracle_grouped_all_widths_results.json'
    else:
        results=run(args.max_digits,args.max_outer_width,args.max_root)
        filename='oracle_grouped_results.json'
    target=args.output or Path(__file__).with_name(filename)
    target.write_text(json.dumps(results,indent=2)+'\n')
    print('Candidates:',results['candidate_bases_numbers'],
          'partitions:',results['partitions_checked'],
          'solutions:',len(results['solutions']))
    for solution in results['solutions']:
        print(json.dumps(solution))
    print('JSON:',target)


if __name__=='__main__':
    main()
