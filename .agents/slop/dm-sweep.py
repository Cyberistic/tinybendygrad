#!/usr/bin/env python3
"""dm-sweep -- the STRUCTURED cross product behind dmfuzz's random sweep.

Not part of the deliverable harness: this is the evidence that the random
generator is not simply LUCKY in finding exactly one wrong shape. It walks a
dense lattice -- every `a` in a ladder times every `b` in a ladder -- so the
sign x magnitude grid is covered rather than sampled, and it reports the SET of
distinct (op, a, b) triples that disagree. Used once, to characterise the
FLOORDIV|-2147483648|-1 finding as the only one in the space.

Usage: python3 .agents/slop/dm-sweep.py [--binary BIN]
"""
import argparse, itertools, os, subprocess, sys, tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
import dmfuzz  # noqa: E402

I32MIN, I32MAX = -2147483648, 2147483647


def ladder():
    core = [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 7, -7, 8, -8, 9, -9,
            16, -16, 17, -17, 31, -31, 32, -32, 100, -100, 127, -127,
            1000, -1000, 1024, -1024, 65535, -65535, 1 << 20, -(1 << 20),
            1 << 30, -(1 << 30), I32MAX, I32MIN, I32MAX - 1, I32MIN + 1]
    return core


def cases():
    L = ladder()
    for op in ("FLOORDIV", "FLOORMOD"):
        for a, b in itertools.product(L, L):
            yield f"{op}|{a}|{b}"
    # the dependent family: a built from b, which is where floor/truncate
    # disagreements concentrate
    for op in ("FLOORDIV", "FLOORMOD"):
        for b in L:
            for a in (0, 1, -1, b, -b, b + 1, b - 1, -b + 1, -b - 1, 2 * b,
                      -2 * b, b * b, b + I32MIN, b - I32MAX, I32MIN, I32MAX):
                yield f"{op}|{max(I32MIN, min(I32MAX, a))}|{b}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--binary", required=True)
    args = ap.parse_args()
    work = tempfile.mkdtemp(prefix="dmsweep-")
    bad, n = {}, 0
    for case in cases():
        n += 1
        path = os.path.join(work, "c.txt")
        with open(path, "w") as f:
            f.write(case + "\n")
        want = dmfuzz.oracle(case)
        got = dmfuzz.bend_line(args.binary, path)
        if want != got:
            bad.setdefault((case, want, got), []).append(case)
    print(f"swept {n} (op, a, b) triples")
    print(f"distinct mismatching shapes: {len(bad)}")
    for (case, want, got), _ in list(bad.items())[:20]:
        print(f"  {case:<34} want {want:<22} got {got}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())