#!/usr/bin/env python3
"""dd-band-diff.py -- whole-`name=value` differ for the dtype.bend gate, on rebase-gate.py's
unified row reader (`.agents/slop/rebase-gate.py:row`/`:rows`), so the three lane formats all
read the same way.

  dd-band-diff.py PORT.txt ORACLE.txt          the disagreeing rows, by name
  dd-band-diff.py PORT.txt ORACLE.txt --quiet  just the COUNT

Two properties this file exists to guarantee, both of which agent-core.md records as having
cost real money:

  * rows are keyed on the WHOLE `name=value` line, never on the row INDEX and never on the
    row NAME alone -- a name-comparing harness reported 0 disagreements for all 30 mutations in
    one unit and 0 for all 68 in another;
  * a LANE THAT PRODUCED NOTHING is a HARD ERROR, never `0 disagreements`. bend's machine
    stack overflows on ~1 run in 20 and prints ZERO rows, which is byte-identical to "not
    started", and the prior unit's own harness returned 0 rows on a transient and its differ
    happily reported "0 disagreements" over it.

Both sides must have at least MIN_ROWS rows or this exits 2.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
_src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rebase-gate.py")
_mod = importlib.util.spec_from_file_location("rebase_gate", _src)
rebase_gate = importlib.util.module_from_spec(_mod)
_mod.loader.exec_module(rebase_gate)
rows = rebase_gate.rows

MIN_ROWS = int(os.environ.get("MIN_ROWS", "150"))

# ⚠ `rows` IS `rebase-gate.py:rows()`, AND EVERY COUNT THIS FILE PRINTS IS A FLOOR.
# That reader is the shared one and nine tools call it, so this is worth naming at the point
# of use rather than only in its own header. MEASURED on this tree by
# `.agents/slop/formblind-audit.py --corpus`: across the 771 `.txt` lanes that reader DOES
# read as rows, it cannot read 3,194 of their lines --
#
#     SINGLE-SPACE   2989   a lane that prints `name value` (the gap must be TWO spaces)
#     TAB              186   refused on purpose: a TSV table's first column is not a row name
#     EQ-INSIDE-GAP    19   a two-space row whose VALUE carries `=`, which the `=` branch
#                           claims first and RENAMES -- worse than a floor, because a
#                           fabricated key can collide with a real one
#
# and it cannot see a row whose NAME carries a space at all (F3 requires
# `len(head.split()) == 1`), which is the shape `multi-rows.py` writes. So:
#
#     `shared=`, `port_only=`, `oracle_only=` and `DISAGREE=` are LOWER BOUNDS.
#
# MIN_ROWS below is the floor's other half and it is already right: a lane under MIN_ROWS is
# refused as "not started" rather than reported as agreement, because a 0-row result is
# indistinguishable from "not started" and bend stack-overflows about one run in twenty.
# A count that is silently a floor is the defect this whole class keeps re-learning.


def main():
    a = sys.argv[1:]
    quiet = "--quiet" in a
    a = [x for x in a if not x.startswith("--")]
    p, q = rows(open(a[0]).read()), rows(open(a[1]).read())
    thin = [n for n, r in (("PORT", p), ("ORACLE", q)) if len(r) < MIN_ROWS]
    if thin:
        print(f"THIN LANE {thin}: {[(n, len(r)) for n, r in (('PORT', p), ('ORACLE', q))]} "
              f"-- a lane under {MIN_ROWS} rows is 'not started', not '0 disagreements'", file=sys.stderr)
        return 2
    keys = sorted(set(p) & set(q))
    bad = [k for k in keys if p[k] != q[k]]
    if not quiet:
        for k in bad:
            print(f"{k}\n  port   {p[k]}\n  oracle {q[k]}")
    print(f"shared={len(keys)} port_only={len(set(p) - set(q))} oracle_only={len(set(q) - set(p))} "
          f"DISAGREE={len(bad)}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())