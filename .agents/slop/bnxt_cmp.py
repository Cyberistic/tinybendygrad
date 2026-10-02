"""bnxtdev.bend -- COMPARE TWO `name=value` LANES, WHOLE LINES.

    python3 .agents/slop/bnxt_cmp.py <file-a> <file-b>

Prints two lists: the names only ONE side has, and the names BOTH have whose
VALUES differ. Whole lines are compared, never row names -- a name-comparing
harness reported 0 moved rows for every mutation in two separate units, because
the names were identical by construction.
"""
import sys


def load(p):
    out = {}
    for line in open(p):
        line = line.rstrip('\n')
        if '=' in line:
            k, v = line.split('=', 1)
            out.setdefault(k, v)
        else:
            out.setdefault('(bare)' + line, '')
    return out


a, b = load(sys.argv[1]), load(sys.argv[2])
only_a = sorted(set(a) - set(b))
only_b = sorted(set(b) - set(a))
diff = sorted(k for k in set(a) & set(b) if a[k] != b[k])
print(f"{sys.argv[1]}: {len(a)} rows, {sys.argv[2]}: {len(b)} rows")
print(f"  only in {sys.argv[1]}: {len(only_a)}")
for k in only_a[:60]:
    print(f"    - {k}={a[k]}")
if len(only_a) > 60:
    print(f"    ... and {len(only_a) - 60} more")
print(f"  only in {sys.argv[2]}: {len(only_b)}")
for k in only_b[:60]:
    print(f"    + {k}={b[k]}")
if len(only_b) > 60:
    print(f"    ... and {len(only_b) - 60} more")
print(f"  BOTH but DIFFERENT: {len(diff)}")
for k in diff[:80]:
    print(f"    ~ {k}: {sys.argv[1]}={a[k]!r}  {sys.argv[2]}={b[k]!r}")
if len(diff) > 80:
    print(f"    ... and {len(diff) - 80} more")
# THE THREE BUCKETS, and they are not the same claim. A row only ONE side has
# is a MISSING CLAIM (bad) on the oracle side and an EXTRA CLAIM (fine, and
# gated by mutation rather than by CPython) on the port side. `only_b` is
# therefore reported but NOT a disagreement, because a U32 port cannot call
# `Tr.has` or `Tr.refuse` and those rows are its own; `only_a` IS a
# disagreement, because the oracle promised a row CPython backs and the port
# does not make it.
print(f"  VERDICT: {'AGREE' if not (only_a or diff) else 'DISAGREE'}"
      f"   ({len(only_b)} port-only rows, gated by mutation not by CPython)")
sys.exit(0 if not (only_a or diff) else 1)