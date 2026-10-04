#!/usr/bin/env python3
"""f2f-pad-diff.py -- whole-`name=value` differ for the arena-size sweep, on
rebase-gate.py's unified row reader, so every lane format reads the same way.

  f2f-pad-diff.py A.txt B.txt           the disagreeing rows, by name
  f2f-pad-diff.py A.txt B.txt --quiet   just the COUNT

Two properties this file exists to guarantee, both of which agent-core.md records as having
cost real money:

  * rows are keyed on the WHOLE `name=value` line, never on the row INDEX and never on the
    row NAME alone -- a name-comparing harness reported 0 disagreements for all 30 mutations
    in one unit and 0 for all 68 in another;
  * a LANE THAT PRODUCED NOTHING is a HARD ERROR, never `0 disagreements`. bend's machine
    stack overflows on ~1 run in 20 and prints ZERO rows, which is byte-identical to "not
    started".
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rebase-gate.py")
_mod = importlib.util.spec_from_file_location("rebase_gate", _src)
rebase_gate = importlib.util.module_from_spec(_mod)
_mod.loader.exec_module(rebase_gate)
rows = rebase_gate.rows

MIN_ROWS = int(os.environ.get("MIN_ROWS", "50"))


def main():
    a = sys.argv[1:]
    quiet = "--quiet" in a
    a = [x for x in a if not x.startswith("--")]
    p, q = rows(open(a[0]).read()), rows(open(a[1]).read())
    thin = [n for n, r in (("A", p), ("B", q)) if len(r) < MIN_ROWS]
    if thin:
        print(f"THIN LANE {thin}: {[(n, len(r)) for n, r in (('A', p), ('B', q))]} "
              f"-- a lane under {MIN_ROWS} rows is 'not started', not '0 disagreements'",
              file=sys.stderr)
        return 2
    keys = sorted(set(p) & set(q))
    bad = [k for k in keys if p[k] != q[k]]
    if not quiet:
        for k in bad:
            print(f"{k}\n  A {p[k]}\n  B {q[k]}")
    only_p, only_q = sorted(set(p) - set(q)), sorted(set(q) - set(p))
    if only_p or only_q:
        print(f"UNSHARED KEYS A_only={only_p} B_only={only_q}", file=sys.stderr)
    print(f"shared={len(keys)} A_only={len(only_p)} B_only={len(only_q)} DISAGREE={len(bad)}",
          flush=True)
    return 1 if bad or only_p or only_q else 0


if __name__ == "__main__":
    sys.exit(main())