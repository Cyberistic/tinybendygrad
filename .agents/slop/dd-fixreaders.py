#!/usr/bin/env python3
# dd-fixreaders.py -- REWRITE `.ar`/`.i`/`.lo`/`.hi` READERS FROM THE BINDERS' OWN
# TYPES. A WORKAROUND, and one to be flipped back.
#
# WHY: this file has two two-field records -- `O.Found` (`Arena & U32`) and the
# port's own `W2` -- and bend 2.0.34 refuses a reader applied to the wrong one,
# one error per call site. 263 of them. Every site is mechanical once the
# BINDER'S type is known, and the binder's type is readable from the file:
# `+x = f(...)` has `f`'s return type, and a def head states its own.
#
# WHAT IT KNOWS. This file's own return types are parsed from its heads. For the
# three imported families: `O.UOp.*` and `O.Found.*` return `O.Found`; `T.tx_powi`,
# `T.tx_powi32`, `T.exponent_bias`, `T.tx_finfo_*` return `U32`; every other
# `T.tx_*` and `P.dc_*` returns `O.Found`. A `+x = ...` whose head is not a CALL
# is left alone, which is the safe direction.
#
# THE READER MAP. `ar` is `ar` on both records. `i`, `lo` and `hi` are the same
# U32 on both -- `Found.i`, `W2.lo` and `W2.hi` -- so only `ar` needs a decision.
# IT IS NOT A PORTING TOOL. DELETE IT WHEN THE FILE COMPILES.
import re
import sys

DEF = re.compile(r'^def ([A-Za-z_][\w.]*)\(', re.M)
RET = re.compile(r'\)\s*->\s*([^:]+):\s*$')
BIND = re.compile(r'^\s*\+([a-z][a-z0-9_]*) = ([A-Za-z_][\w.]*)\(')
U32RET = re.compile(r'(powi32|^T\.tx_powi$|exponent_bias|finfo)')


def main():
    path = sys.argv[1]
    lines = open(path).read().split('\n')
    own = {}
    for i, l in enumerate(lines):
        m = DEF.match(l)
        if not m:
            continue
        r = RET.search(l)
        if r:
            own[m.group(1)] = r.group(1).strip()
    changed = 0
    for i, l in enumerate(lines):
        m = BIND.match(l)
        if not m:
            continue
        local, callee = m.group(1), m.group(2)
        if callee in own:
            t = own[callee]
        elif callee.startswith('O.UOp') or callee.startswith('O.Found'):
            t = 'O.Found'
        elif U32RET.search(callee):
            t = 'U32'
        else:
            t = 'O.Found'
        if t not in ('O.Found', 'W2'):
            continue
        for rd in ('ar', 'i', 'lo', 'hi'):
            got = f"O.Found.ar({local})" if rd == 'ar' and t == 'O.Found' else \
                  f"O.Found.i({local})" if t == 'O.Found' else \
                  f"W2.ar({local})" if rd == 'ar' else \
                  f"W2.{rd}({local})"
            for frm in (f"O.Found.{rd}({local})", f"W2.{rd}({local})"):
                if frm in l and frm != got:
                    l = l.replace(frm, got)
                    changed += 1
        lines[i] = l
    open(path, 'w').write('\n'.join(lines))
    print(f"dd-fixreaders: rewrote {changed} call sites in {path}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
