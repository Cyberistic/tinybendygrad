#!/usr/bin/env python3
"""dd-band-paddiff.py -- diff the two `dd_band` size sweeps, whole `name=value` LINES.

Never on row NAMES and never on row indices: agent-core.md records a name-comparing
harness reporting 0 disagreements for all 30 mutations in one unit and all 68 in another,
which is exactly the failure this whole file is about.

The thing being looked for is a CONST whose VALUE TRACKS `pad`. A mask that is an arena
index is `slot_of(s) + pad`, so the wrong row is `C(<k + slot>)` and it MOVES with k; the
right row is `C(<the mask>)` and it does not. Both sweeps are printed with the movement
marked, because "the sweep moved" is only evidence if "the movement is the index" is also
shown.

usage: dd-band-paddiff.py BEFORE.txt AFTER.txt
"""
import re
import sys


def rows(p):
    d = {}
    for ln in open(p):
        ln = ln.rstrip("\n")
        if not ln or ln.startswith("#") or "=" not in ln:
            continue
        k, _, v = ln.partition("=")
        d[k.strip()] = v
    return d


PAD = re.compile(r"^([wn]\d)\.p(\d+)$")


def consts(v):
    return re.findall(r"[CF]\((-?\d+)\)", v)


def main():
    b, a = rows(sys.argv[1]), rows(sys.argv[2])
    keys = [k for k in b if PAD.match(k)]
    bad = [k for k in keys if k + "k" in b and k + "k" in a and b[k + "k"] != a[k + "k"]]
    print(f"{'row':<9} {'before k=':<46} {'after k=':<46}")
    for k in sorted(keys, key=lambda x: (PAD.match(x).group(1), int(PAD.match(x).group(2)))):
        if k + "k" not in b or k + "k" not in a:
            continue
        mark = "  MOVED" if k in bad else ""
        print(f"{k:<9} {b[k+'k'][:44]:<46} {a[k+'k'][:44]:<46}{mark}")
    print()
    # THE MOVEMENT LAW, stated per family: for each `k`, the CONST that is the LOWER of
    # the two candidates and CHANGES BY EXACTLY pad is the arena index.
    print("== does any CONST's value track `pad`?")
    for k in sorted(keys, key=lambda x: (PAD.match(x).group(1), int(PAD.match(x).group(2)))):
        if k + "k" not in b or k + "k" not in a:
            continue
        n = int(PAD.match(k).group(2))
        bb, aa = consts(b[k + "k"]), consts(a[k + "k"])
        moved = [(x, y) for x, y in zip(bb, aa) if x != y]
        if moved:
            print(f"  {k:<9} " + ", ".join(f"C({x}) -> C({y})  delta {int(y)-int(x):+d} (pad {n})"
                                          for x, y in moved))
    print(f"\nrows whose k= line moved: {len(bad)} of {len(keys)}")


if __name__ == "__main__":
    main()