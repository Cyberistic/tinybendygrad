#!/usr/bin/env python3
"""Cluster every `math.*` mention in the port, by function, with the real blocker.

Why this exists
---------------
`rg -a 'math\\.' tinybendygrad/` returns **91 hits, 0 of which are in code**:

    $ rg -a -n 'math\\.' --glob '*.bend' tinybendygrad/ | grep -v -E ':[0-9]+:\\s*#' | wc -l
    0

So there is no `math.exp` call to unblock anywhere in the port, and
`import math` appears in **0** `.bend` files. `math.*` is CPython source being
quoted inside a `#` comment, and the token is the *name of the constant the port
must be able to write down*, not a missing binding.

This script clusters the 91 by the function named, and for each cluster records
what the marker's own block says is missing -- because that, not `math.X`, is the
wall.

Run:  python3 .agents/slop/mathlib/clusters.py
"""
import collections
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad"

MENTION = re.compile(r"math\.([A-Za-z_][A-Za-z_0-9]*)")

# What KIND of capability the mention names, and therefore what would actually
# have to exist. Not the same as "write math.<f>".
KIND = {
    "pi":       "an f32 CONSTANT literal",
    "e":        "an f32 CONSTANT literal",
    "inf":      "an f32 CONSTANT literal",
    "nan":      "an f32 CONSTANT literal",
    "tau":      "an f32 CONSTANT literal",
    "log":      "an f32 CONSTANT literal  (log 2 as a scale factor)",
    "log2":     "an f32 CONSTANT literal  (log 2 as a scale factor)",
    "log10":    "an f32 CONSTANT literal  (log10 2)",
    "sqrt":     "an f32 CONSTANT literal  (sqrt 2, sqrt(2/pi))",
    "copysign": "a signed-zero f32 operation",
    "trunc":    "an f32 ROUNDING op",
    "floor":    "an f32 ROUNDING op",
    "isnan":    "an f32 CLASSIFICATION (NaN test)",
    "isfinite": "an f32 CLASSIFICATION (inf/NaN test)",
    "isinf":    "an f32 CLASSIFICATION (inf test)",
    "gcd":      "an INTEGER operation on I64",
    "exp":      "a TRANSCENDENTAL",
    "log2_":    "a TRANSCENDENTAL",
}


def main() -> int:
    by_fn = collections.defaultdict(list)
    for f in sorted(PORT.rglob("*.bend")):
        for n, ln in enumerate(f.read_text(errors="replace").splitlines(), 1):
            if not ln.lstrip().startswith("#"):
                continue
            for m in MENTION.finditer(ln):
                by_fn[m.group(1)].append((str(f.relative_to(ROOT)), n))

    kinds = collections.Counter()
    total = 0
    for fn, hits in sorted(by_fn.items(), key=lambda kv: -len(kv[1])):
        kind = KIND.get(fn, "UNKNOWN -- read it")
        kinds[kind] += len(hits)
        total += len(hits)
        where = ", ".join(f"{h[0]}:{h[1]}" for h in hits)
        print(f"math.{fn:<10} n={len(hits):>2}  {kind}")
        print(f"             {where}")
    print()
    print(f"TOTAL mentions in comments: {total}")
    print()
    print("By KIND:")
    for k, v in kinds.most_common():
        print(f"  {v:>3}  {k}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())