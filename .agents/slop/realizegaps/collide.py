#!/usr/bin/env python3
"""HOW MANY FIXTURE NODES PRINT ALIKE -- the number the `Arg` payload has to move.

    .venv/bin/python .agents/slop/realizegaps/collide.py            # BEFORE
    .venv/bin/python .agents/slop/realizegaps/collide.py --after    # AFTER

Two DISTINCT nodes of `realize_graph_census-oracle.py`'s own fixture that print the same
token are indistinguishable to every row that carries one, so a reader that returned the
wrong node is invisible exactly there. The pairs are counted here, on the CPython fixture,
because the token is a property of the NODE and both lanes print it from their own arena.

Not a gate: a throwaway probe whose reading goes into the commit and the report. It reads
the oracle BY PATH and imports nothing of the gate.
"""
import importlib.util
import sys
from itertools import combinations
from pathlib import Path

ORACLE = Path(__file__).resolve().parents[3] / "gates" / "realize_graph_census-oracle.py"


def tok(u, after):
    if after:
        return u.s2 if hasattr(u, "s2") else None
    return None


def main():
    spec = importlib.util.spec_from_file_location("orc", ORACLE)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    after = "--after" in sys.argv

    def token(u):
        # THE ORACLE'S OWN `s1`/`s2`, imported by path, so this probe cannot drift from
        # the lane it is measuring.
        return m.s2(u)

    seen = {}
    for n in range(1, 66):
        seen.setdefault(token(m.B[n]), []).append(n)
    collide = {k: v for k, v in seen.items() if len(v) > 1}
    pairs = sum(len(v) * (len(v) - 1) // 2 for v in collide.values())
    print(f"fixture nodes            : 65")
    print(f"distinct tokens          : {len(seen)}")
    print(f"tokens carrying >1 node  : {len(collide)}")
    print(f"indistinguishable pairs  : {pairs}")
    for k, v in sorted(collide.items(), key=lambda kv: -len(kv[1])):
        print(f"  {v}  {k}")
    if not collide:
        print("  (no two fixture nodes print alike)")


if __name__ == "__main__":
    main()