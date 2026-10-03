"""Find .bend files that are a stale PREFIX of a sibling in the same directory.

A mutation/probe harness that edits a port IN PLACE leaves a copy behind under a
scratch name. The copy is a near-prefix of the real file: identical up to the
line where the harness inserted its mutation, divergent after. That shape is
what distinguishes a DEAD SNAPSHOT (regenerable, and worse, a file the census
counts twice) from real work that merely shares a header.

`find tinybendygrad -name '*.bend'` counts a dead snapshot as a port file, so
every size and count figure inherits it. This names them.

Usage: python3 .agents/slop/stale-snapshot-detect.py [--min-prefix 20]
"""

import argparse
import os
import sys

ROOTS = ("tinybendygrad", "examples")


def bend_files():
    out = []
    for root in ROOTS:
        for dirpath, dirs, files in os.walk(root):
            dirs[:] = sorted(d for d in dirs if d not in (".git", "__pycache__"))
            out += [os.path.join(dirpath, f) for f in sorted(files) if f.endswith(".bend")]
    return sorted(out)


def lines(path):
    with open(path, errors="replace") as fh:
        return [ln.rstrip() for ln in fh]


def shared_prefix(a, b):
    n = 0
    for x, y in zip(a, b):
        if x != y:
            break
        n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-prefix", type=int, default=20)
    ap.add_argument("--min-ratio", type=float, default=0.70,
                    help="fraction of the SHORTER file that must match; csprobe/cstyle is 0.76")
    args = ap.parse_args()

    files = bend_files()
    cache = {f: lines(f) for f in files}
    by_dir = {}
    for f in files:
        by_dir.setdefault(os.path.dirname(f), []).append(f)

    hits = []
    for d, group in sorted(by_dir.items()):
        for i, a in enumerate(group):
            for b in group[i + 1:]:
                pa, pb = cache[a], cache[b]
                # the shorter one must be the near-prefix, and the longer one must be LONGER
                short, long_, sname, lname = (a, b, a, b) if len(pa) <= len(pb) else (b, a, b, a)
                if len(pa) == len(pb):
                    continue
                n = shared_prefix(pa, pb)
                if n < args.min_prefix:
                    continue
                # a dead snapshot agrees for MOST of the shorter file. The ratio
                # is printed, not just passed, because "most" is a judgement and
                # the reader is the one who has to make it.
                ratio = n / len(pa)
                if ratio < args.min_ratio:
                    continue
                tail_diff = sum(1 for x, y in zip(pa[n:], pb[n:]) if x != y)
                hits.append((sname, lname, len(pa), len(pb), n, ratio, tail_diff))

    if not hits:
        print("no near-prefix sibling pairs at ratio >= %.2f" % args.min_ratio)
        return 0
    print("dead-snapshot candidates (shorter file is a stale prefix of the longer):")
    print("%-46s %-40s %6s %6s %6s %6s %6s" % ("SHORTER (suspect)", "LONGER (real)", "nshort", "nlong", "pfx", "ratio", "tdiff"))
    for sname, lname, ns, nl, n, ratio, td in sorted(hits, key=lambda h: -h[2]):
        print("%-46s %-40s %6d %6d %6d %6.2f %6d" % (sname, lname, ns, nl, n, ratio, td))
    return 0


if __name__ == "__main__":
    sys.exit(main())