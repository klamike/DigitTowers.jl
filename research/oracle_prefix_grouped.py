#!/usr/bin/env python3
"""Exact search of root_r(b^(exponent_block^(single-digit tail))).

Command-line defaults reproduce the published general-prefix search: outer
bases 2--99,999, exponent block widths 1--3, total lengths 2--100, and root
orders 2--9. Primitive-power candidates include fractional powers of b.
Every nested 0^0 is undefined. Only the Python standard library is required.
The optional exact mode restricts the exponent block to the required E and
checks that its remaining digit tower equals one.
"""
from pathlib import Path
import json
from oracle_enumerate import suffix_oracle
from oracle_grouped import primitive_base


def run(max_digits=100,max_base=9999,max_root=9,include_fractional=True):
    found=[]
    powers_checked=0
    prefix_matches=0
    maximum=10**max_digits-1
    for b in range(2,max_base+1):
        a,g=primitive_base(b) if include_fractional else (b,1)
        bstr=str(b)
        n,h=a,1
        while n<=maximum:
            text=str(n)
            if len(text)>len(bstr) and text.startswith(bstr):
                prefix_matches+=1
                for r in range(2,max_root+1):
                    if r*h%g:
                        continue
                    e=r*h//g
                    estr=str(e)
                    prefix=bstr+estr
                    if not text.startswith(prefix):
                        continue
                    tail=text[len(prefix):]
                    if tail and suffix_oracle(tuple(map(int,tail)),2)!=1:
                        continue
                    assert n**r==b**e
                    found.append(dict(number=text,root=r,outer_base=b,
                                      required_exponent=e,blocks=[b,e]+list(map(int,tail)),
                                      widths=[len(bstr),len(estr)]+[1]*len(tail),
                                      primitive_base=a,power=h,base_power=g))
            powers_checked+=1
            n*=a
            h+=1
    found.sort(key=lambda s:(len(s['number']),s['number'],s['root']))
    return dict(max_digits=max_digits,max_base=max_base,max_root=max_root,
                fractional_powers_included=include_fractional,powers_checked=powers_checked,
                base_prefix_matches=prefix_matches,solutions=found)


def run_general(max_digits=100,max_base=9999,max_root=9,max_exponent_width=3):
    found=[]
    powers_checked=0
    prefix_matches=0
    maximum=10**max_digits-1
    for b in range(2,max_base+1):
        a,g=primitive_base(b)
        bstr=str(b)
        n,h=a,1
        while n<=maximum:
            text=str(n)
            if len(text)>len(bstr) and text.startswith(bstr):
                prefix_matches+=1
                for w in range(1,min(max_exponent_width,len(text)-len(bstr))+1):
                    exptext=text[len(bstr):len(bstr)+w]
                    if w>1 and exptext[0]=='0':
                        continue
                    ebase=int(exptext)
                    tail=text[len(bstr)+w:]
                    blocks=[b,ebase]+list(map(int,tail))
                    for r in range(2,max_root+1):
                        if r*h%g:
                            continue
                        e=r*h//g
                        if suffix_oracle(tuple(blocks[1:]),e+1)!=e:
                            continue
                        assert n**r==b**e
                        found.append(dict(number=text,root=r,outer_base=b,
                                          required_exponent=e,blocks=blocks,
                                          widths=[len(bstr),w]+[1]*len(tail),
                                          primitive_base=a,power=h,base_power=g))
            powers_checked+=1
            n*=a
            h+=1
    found.sort(key=lambda s:(len(s['number']),s['number'],s['root'],s['widths']))
    return dict(max_digits=max_digits,max_base=max_base,max_root=max_root,
                max_exponent_width=max_exponent_width,
                powers_checked=powers_checked,
                base_prefix_matches=prefix_matches,solutions=found)


def main():
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--max-digits',type=int,default=100,
                        help='maximum total decimal digits (default: 100)')
    parser.add_argument('--max-base',type=int,default=99999,
                        help='maximum outer base, inclusive (default: 99999)')
    parser.add_argument('--max-root',type=int,default=9,
                        help='search root orders 2 through this value (default: 9)')
    parser.add_argument('--max-exponent-width',type=int,default=3,
                        help='maximum first exponent block width in general mode (default: 3)')
    parser.add_argument('--mode',choices=('general','exact'),default='general',
                        help='general exponent blocks or the required-E prefix (default: general)')
    parser.add_argument('--output',type=Path,default=None,
                        help='JSON path; defaults to the matching file beside this script')
    args=parser.parse_args()
    if args.max_digits<2 or args.max_base<2 or args.max_root<2:
        parser.error('--max-digits, --max-base and --max-root must each be at least 2')
    if args.max_exponent_width<1:
        parser.error('--max-exponent-width must be positive')
    if args.mode=='general':
        result=run_general(args.max_digits,args.max_base,args.max_root,
                           args.max_exponent_width)
        filename=f'oracle_prefix_general_b{args.max_base}_results.json'
    else:
        result=run(args.max_digits,args.max_base,args.max_root)
        filename='oracle_prefix_grouped_results.json'
    target=args.output or Path(__file__).with_name(filename)
    target.write_text(json.dumps(result,indent=2)+'\n')
    print('Powers:',result['powers_checked'],
          'prefix matches:',result['base_prefix_matches'],
          'solutions:',len(result['solutions']))
    for solution in result['solutions']:
        print(json.dumps(solution))
    print('JSON:',target)


if __name__=='__main__':
    main()
