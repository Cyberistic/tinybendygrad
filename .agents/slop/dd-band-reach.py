#!/usr/bin/env python3
"""dd-band-reach.py -- STATIC reachability closure over codegen/decomp/dtype.bend's own
defs, from `main`, so "no row can see this site" is a PROOF and not a shrug.

Seven `dd_band` mask sites read SAME under mutation (`.agents/slop/dd-band-mut.py` M01-M07)
and the obvious explanation -- the mask is right by coincidence, or wrong on some input
CPython never produced -- is only ONE of three.  This answers the other two.

THE METHOD.  `def foo.bar(` opens a def and everything up to the next `def ` is its body;
comment lines are dropped so a `# f2f.sign ...` cannot invent an edge.  Bend has no
first-class function values in this file and no method dispatch, so the names a body
mentions are exactly the defs it can call and the closure is EXACT rather than
approximate.  It is deliberately COARSE in the safe direction: a reference to the BARE
tail (`up(`) also counts as a reference to the qualified `f2f.up`, so this is an
OVER-approximation -- and an over-approximation that fails to reach a site PROVES
unreachability, while one that does reach a site proves nothing.

Roots default to `main`.  `main` is the file's only `IO(Unit)` entry and `gate()` is its
whole body, so the closure from `main` IS the set of defs the 182-row gate can execute.

usage: dd-band-reach.py [FILE] [ROOT...]
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEF = re.compile(r"^def\s+([A-Za-z_][A-Za-z0-9_.]*)\s*\(", re.M)
SPLIT = re.compile(r"(?m)^def\s+")


def defs_and_bodies(src):
    code = "\n".join(ln for ln in src.splitlines() if not ln.lstrip().startswith("#"))
    parts = SPLIT.split(code)[1:]
    out = []
    for p in parts:
        name = DEF.match("def " + p).group(1)
        out.append((name, p))
    return out


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        HERE, "..", "..", "tinybendygrad", "codegen", "decomp", "dtype.bend")
    bodies = dict(defs_and_bodies(open(path).read()))
    names = set(bodies)
    tails = {}
    for n in names:
        tails.setdefault(n.split(".", 1)[-1], set()).add(n)

    def refs(body):
        # A QUALIFIED call (`f2f.down.sign(`) resolves to that exact def when one exists,
        # because `f2f.down.sign` and `f2f.sign` are different functions and resolving
        # `down.sign` to the tail `sign` made `f2f.sign` look reachable from every
        # `f2f.down.sign(` call.  A BARE call (`sign(`) has no such luxury -- the tail
        # resolves to every def that owns one, which keeps the closure an
        # OVER-approximation (sound for unreachability, useless for reachability).
        out = set()
        for call in re.findall(r"(?<![\w.])([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*\(", body):
            if call in names:
                out.add(call)
                continue
            for t in tails.get(call.split(".")[-1], ()):
                if t in names:
                    out.add(t)
        return out

    roots = sys.argv[2:] or ["main"]
    seen, stack = set(), [r for r in roots if r in names]
    while stack:
        n = stack.pop()
        if n in seen:
            continue
        seen.add(n)
        stack.extend(refs(bodies[n]) - seen)
    print(f"# {len(names)} defs in {os.path.basename(path)}, roots {roots}: "
          f"{len(seen)} reachable from them\n")
    groups = (
        ("the SEVEN dd_band mask sites",
         ["f2f.sign", "f2f.nosign", "f2f.down.sign", "f2f.down.nosign",
          "f2f.down.uf", "f2f.down.m2", "f2f.down.isnan"]),
        ("the f2f entry points and the whole float region",
         ["f2f", "f2f.up", "f2f.down", "f2f_clamp", "f2f.narrow", "f2f_load",
          "f2f_store", "f2f_rewrite", "rne", "f2f.up.tail", "f2f.down.tail"]),
        ("the gate's own roots, as the closure's own sanity check",
         ["main", "gate", "l2i", "unpack32", "l2i.hi42", "f2f_clamp_max",
          "dd_cmx.rows", "l2i.rows"]))
    for label, probes in groups:
        print(f"== {label}")
        for p in probes:
            mark = "REACHABLE  " if p in seen else "UNREACHABLE"
            print(f"   {mark} {p:<16} referenced by "
                  f"{sum(1 for b in bodies.values() if p in refs(b))} def(s)")
        print()
    unreach = sorted(names - seen)
    print(f"# {len(unreach)} defs UNREACHABLE from main, e.g. {unreach[:14]}")
    print(f"# of the unreachable, {sum(1 for n in unreach if 'f2f' in n)} are named f2f*")


if __name__ == "__main__":
    main()