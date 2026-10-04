#!/usr/bin/env python3
"""f2f-fixA.py -- TASK A: the `U32`-returning `f2f.up.tail` / `f2f.fnuz` / `f2f.ocp`.

WHY. Three defs build nodes into an arena and hand back a bare `U32`, which is the
index of a node in an arena THE CALLER DOES NOT HOLD. Measured on the unmodified
file, `.agents/slop/dd-bandarena.bend`:

    # w1 root=24 next=25
    22  MUL/2  MUL  <- OR,C(8388608)      src0 = 23, a LATER slot
    23  OR/2   OR   <- MUL,MUL            src1 = 22, an EARLIER slot

22 and 23 point at EACH OTHER. An append-only arena cannot hold a cycle, so this is
not a wrong answer -- it is a graph that cannot exist, and it reads as plausible.

TWO CAUSES, and both must go or the other's fix re-creates the aliasing:

  (1) THE RETURN. `f2f.up.tail`/`fnuz`/`ocp` return `U32`, so `f2f.up` has no way to
      learn which arena that index belongs to and builds its BITCAST into
      `O.Found.ar(nq)` instead. Fixed by returning `O.Found`, the shape `wr.rebuild`
      uses in codegen/__init__.bend.

  (2) THE ARENA HANDED IN. `f2f.up` passed its OWN `+ar` -- the arena as it was
      BEFORE `f2f.sign` minted anything, i.e. holding only the fixture's PARAM. So
      the tail's whole subtree was built in a DIFFERENT arena from the `ns`/`sg`/`ex`
      /`nm`/`nq` indices it reads. Returning `Found` does not fix that on its own: the
      `Found` would carry the stale arena. `O.Found.ar(nq)` is the one that holds them.

TASK B's `f2f.em1` overwrite is NOT touched here. It is a third builder in the same
argument list and is fixed on its own, after A's cone is measured.

usage: f2f-fixA.py FILE.bend      rewrites in place, prints one line per anchor
"""
import hashlib
import sys

FIX = [
    ("f2f.fnuz returns the pair, not the index",
     "def f2f.fnuz(+ar: O.Arena, +ns: O.Found, +sg: O.Found, +ex: O.Found, +nm: O.Found, +te: U32, +tm: U32) -> U32:",
     "def f2f.fnuz(+ar: O.Arena, +ns: O.Found, +sg: O.Found, +ex: O.Found, +nm: O.Found, +te: U32, +tm: U32) -> O.Found:"),
    ("f2f.fnuz's answer is the Found, unwrapped",
     "  O.Found.i(dd_where(O.Found.ar(s), O.Found.i(fn), O.Found.i(q), O.Found.i(s)))",
     "  dd_where(O.Found.ar(s), O.Found.i(fn), O.Found.i(q), O.Found.i(s))"),
    ("f2f.ocp returns the pair, not the index",
     "def f2f.ocp(e4m3: Bool, +ar: O.Arena, +ns: O.Found, +sg: O.Found, +ex: O.Found, +nm: O.Found, +nn: O.Found, +fe: U32, +fm: U32) -> U32:",
     "def f2f.ocp(e4m3: Bool, +ar: O.Arena, +ns: O.Found, +sg: O.Found, +ex: O.Found, +nm: O.Found, +nn: O.Found, +fe: U32, +fm: U32) -> O.Found:"),
    ("f2f.ocp's answer is the Found, unwrapped",
     "  O.Found.i(dd_or(O.Found.ar(w), O.Found.i(sg), O.Found.i(w)))",
     "  dd_or(O.Found.ar(w), O.Found.i(sg), O.Found.i(w))"),
    ("f2f.up.tail returns the pair, not the index",
     "def f2f.up.tail(fnuz: Bool, e4m3: Bool, +ar: O.Arena, +ns: O.Found, +sg: O.Found, +ex: O.Found, +nm: O.Found, +nn: O.Found, +fe: U32, +fm: U32, +te: U32, +tm: U32) -> U32:",
     "def f2f.up.tail(fnuz: Bool, e4m3: Bool, +ar: O.Arena, +ns: O.Found, +sg: O.Found, +ex: O.Found, +nm: O.Found, +nn: O.Found, +fe: U32, +fm: U32, +te: U32, +tm: U32) -> O.Found:"),
    ("f2f.up hands the tail the arena that HOLDS ns/sg/ex/nm/nq, and bitcasts in the tail's own arena",
     "  +nq = f2f.qnan(O.Found.ar(nm), ns, fm, tm, te)\n"
     "  T.tx_bitcast(O.Found.ar(nq), f2f.up.tail(T.tx_is_fnuz(fr), dd_is_e4m3(fr), ar, ns, sg, ex, nm, nq, fe, fm, te, tm), to)",
     "  +nq = f2f.qnan(O.Found.ar(nm), ns, fm, tm, te)\n"
     "  +w = f2f.up.tail(T.tx_is_fnuz(fr), dd_is_e4m3(fr), O.Found.ar(nq), ns, sg, ex, nm, nq, fe, fm, te, tm)\n"
     "  T.tx_bitcast(O.Found.ar(w), O.Found.i(w), to)"),
]


def main():
    p = sys.argv[1]
    s = open(p).read()
    for name, old, new in FIX:
        n = s.count(old)
        if n != 1:
            raise SystemExit(f"ANCHOR {n}-BAD for {name}: {old[:70]!r}")
        s = s.replace(old, new, 1)
        print(f"applied {name}")
    open(p, "w").write(s)
    print("md5", hashlib.md5(open(p, "rb").read()).hexdigest())


if __name__ == "__main__":
    main()