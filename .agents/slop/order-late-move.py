#!/usr/bin/env python3
"""order-late-move.py -- PROOF THAT `lin_edg` / `linc_edg` MOVE, and that the other
68 `codegen/late/linearizer` rows do not.

D11 in `.agents/slop/unobservable-report.md` is a REQUEST: the census swapped
src[0]/src[1] at both `OpsADD{}` sites in `codegen/late/linearizer.bend`, both
patches applied, both ran, and 0 of 69 rows moved.

This is the other half of that finding. `order-lin-sweep.sh` shows CPython's
answer over the seven src-swapped graphs moves in 2, 0, 20, 6, 9, 3 and 10 rows,
so the information exists; `lin_edg` was added to carry it. Here it is applied to
the PORT and every moved row is reported BY NAME.

DISCIPLINE, all of it borrowed rather than reinvented:
  * a FROZEN, md5-asserted copy of `tinybendygrad/` -- `commute-detect.Frozen`,
    imported, not copied, because a `$TMPDIR` scratch file cannot resolve
    `import ./../../uop/ops.bend` and that produced 22 phantom blind spots in a
    previous unit here;
  * WHOLE `name=value` LINE diffs, never row names;
  * a pre-flight that every port prints rows from the frozen copy BEFORE any
    mutation, so a run that never started cannot read as "0 moved";
  * an end-of-run substrate re-check that prints `SUBSTRATE MOVED` and discards.

    DEV=NULL .venv/bin/python .agents/slop/order-late-move.py
"""
from __future__ import annotations

import hashlib
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def _load(name: str, rel: str):
  spec = importlib.util.spec_from_file_location(name, ROOT / ".agents" / "slop" / rel)
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


CD = _load("commute_detect", "commute-detect.py")

PORT = "codegen/late/linearizer.bend"

# (id, what the mutation breaks, (old, new)) -- the seven fixture src-swaps, plus
# two CONTROLS. A control is a mutation that must move NOTHING outside the EDG
# rows; without one, "everything moved" would be as uninformative as "nothing did".
MUTATIONS = [
  ("A1", "ADD srcs swapped (commutative -- the census's own patch)",
   ('O.OpsADD{}, [O.Found.i(prm), O.Found.i(c1)]',
    'O.OpsADD{}, [O.Found.i(c1), O.Found.i(prm)]')),
  ("A2", "ADD2 srcs swapped",
   ('O.OpsADD{}, [O.Found.i(prm), O.Found.i(c16)]',
    'O.OpsADD{}, [O.Found.i(c16), O.Found.i(prm)]')),
  ("E1", "END srcs swapped -- `e.src[0]` vs `e.src[1:]`",
   ('O.OpsEND{}, [O.Found.i(st), O.Found.i(r_u)]',
    'O.OpsEND{}, [O.Found.i(r_u), O.Found.i(st)]')),
  ("R1", "RANGE srcs swapped -- the second src IS the END, which `CFGContext` reads",
   ('O.OpsRANGE{}, [O.Found.i(c16), O.Found.i(en)]',
    'O.OpsRANGE{}, [O.Found.i(en), O.Found.i(c16)]')),
  ("S1", "SINK srcs swapped (first two)",
   ('[O.Found.i(st), O.Found.i(st2), O.Found.i(en2), O.Found.i(al)]',
    '[O.Found.i(st2), O.Found.i(st), O.Found.i(en2), O.Found.i(al)]')),
  ("S2", "SINK srcs swapped (END and ALLOC)",
   ('[O.Found.i(st), O.Found.i(st2), O.Found.i(en2), O.Found.i(al)]',
    '[O.Found.i(st), O.Found.i(st2), O.Found.i(al), O.Found.i(en2)]')),
  ("S3", "SINK srcs REVERSED -- the DFS seed itself",
   ('[O.Found.i(st), O.Found.i(st2), O.Found.i(en2), O.Found.i(al)]',
    '[O.Found.i(al), O.Found.i(en2), O.Found.i(st2), O.Found.i(st)]')),
  # ---- CONTROLS: these must move the EDG rows and NOTHING ELSE.
  ("C1", "CONTROL: the toposort LITERAL is rotated by one (the graph is untouched)",
   ("  [1, 2, 7, 8, 9, 11, 12, 5, 6, 16, 17, 3, 4, 10, 14, 15, 18, 13, 19]",
    "  [2, 7, 8, 9, 11, 12, 5, 6, 16, 17, 3, 4, 10, 14, 15, 18, 13, 19, 1]")),
  ("C2", "CONTROL: `lt_pos` answers the position it is given, off by one",
   ('def lt_pos(ix: List<&2, U32>, u: U32) -> U32:\n  lt_pos.of(ix, u, 0, 4294967295)',
    'def lt_pos(ix: List<&2, U32>, u: U32) -> U32:\n  lt_pos.of(ix, u, 1, 4294967295)')),
]

# D4 -- `ra0_uops`/`ra1_uops` are `CONST INS*7 CONST INS*3`, blind_swaps 46 each
# and BYTE-IDENTICAL to one another, because they print the allocator's INPUT
# stream and both fixtures are the same fixture under two `is_two_address`
# settings. A permutation of that stream is therefore invisible TO THOSE TWO ROWS.
# The claim that D4 makes is whether ANY row gates the stream's ORDER, so the
# mutation is a permutation of the stream itself and the question is which rows
# answer. These live in `codegen/late/regalloc.bend`, so they get their own port.
REG_PORT = "codegen/late/regalloc.bend"
REG_MUTATIONS = [
  ("D4", "the INSTRUCTION STREAM permuted: the four defining INS at 1..4 swapped in pairs",
   ('''  [RaUop{O.OpsCONST{}, Nil{}, Nil{}},
   RaUop{O.OpsINS{}, [0], [6]}, RaUop{O.OpsINS{}, [0], [7]}, RaUop{O.OpsINS{}, [0], [8]},
   RaUop{O.OpsINS{}, [0], [9]}, RaUop{O.OpsINS{}, [1], Nil{}}, RaUop{O.OpsINS{}, [2], Nil{}},''',
    '''  [RaUop{O.OpsCONST{}, Nil{}, Nil{}},
   RaUop{O.OpsINS{}, [0], [7]}, RaUop{O.OpsINS{}, [0], [6]}, RaUop{O.OpsINS{}, [0], [9]},
   RaUop{O.OpsINS{}, [0], [8]}, RaUop{O.OpsINS{}, [1], Nil{}}, RaUop{O.OpsINS{}, [2], Nil{}},''')),
  ("D4b", "the two CONST pseudo ops swapped with each other -- same op multiset, new order",
   ('''  [RaUop{O.OpsCONST{}, Nil{}, Nil{}},
   RaUop{O.OpsINS{}, [0], [6]},''',
    '''  [RaUop{O.OpsINS{}, [0], [6]},
   RaUop{O.OpsCONST{}, Nil{}, Nil{}},''')),
]


def main() -> int:
  fz = CD.Frozen()
  p = fz.src_of(PORT)
  src = p.read_text()

  # PRE-FLIGHT. Every port must print rows from the FROZEN copy first, so a run
  # that never started cannot read as "0 rows moved" -- the M26 shape.
  base_out = fz.bend(PORT)
  base = CD.rows_of(base_out)
  print(f"BASELINE  {len(base)} rows from the frozen copy")
  oracle = (ROOT / ".agents" / "slop" / "late-oracle.txt").read_text()
  want = len([ln for ln in oracle.splitlines() if "=" in ln])
  print(f"  the committed CPython oracle has {want} rows")
  if len(base) < 10:
    raise SystemExit("FAIL: the frozen copy prints too few rows -- bend did not run")
  # ONLY THE ROWS THIS FILE OWNS. The oracle is the union of THREE ports, so a
  # plain diff against it reports the other 59 rows as disagreements and a count
  # like that reads as a failure. The denominator is stated instead.
  OWNED = ("ix", "po_", "rc_", "lin", "linc", "cfg", "se_")
  theirs = {k: v for k, v in CD.rows_of(oracle).items() if k.startswith(OWNED)}
  bad = CD.diff_rows(base, theirs)
  print(f"  rows this file owns: {len(theirs)} in the oracle, {len(base)} printed; "
        f"{len(bad)} differ {sorted(bad)[:6]}")

  edg = [k for k in base if k.endswith("_edg")]
  print(f"  the EDG rows under test: {edg}")
  if not edg:
    raise SystemExit("FAIL: no *_edg row -- the fix is not in the frozen copy")

  zeros, seen = [], {}
  try:
    for mid, what, (old, new) in MUTATIONS:
      if old not in src:
        print(f"{mid:4} SKIPPED -- target text is gone (the file moved on)")
        zeros.append(mid + " (target text gone)")
        continue
      p.write_text(src.replace(old, new, 1))
      try:
        got = CD.rows_of(fz.bend(PORT))
      except SystemExit as e:
        print(f"{mid:4} DID NOT RUN -- {e}")
        zeros.append(mid + " (did not run)")
        continue
      finally:
        p.write_text(src)
      moved = CD.diff_rows(base, got)
      ok = sorted(k for k in moved if k in edg)
      print(f"{mid:4} {'OK ' if ok else 'ZERO'}  {len(moved):3d} row(s) moved; EDG rows: {ok}")
      print(f"       breaks: {what}")
      if moved and not ok:
        print(f"       !!!! moved rows WITHOUT an edg row: {sorted(set(moved) - set(edg))}")
      if not ok:
        zeros.append(mid + " (" + what + ")")
      for k in moved:
        seen[k] = seen.get(k, 0) + 1
  finally:
    p.write_text(src)

  print()
  print("ROWS MOVED AT ALL: %d over %d mutations" % (sum(seen.values()), len(MUTATIONS)))
  print("rows that EVER moved, with the mutation count:")
  for k in sorted(seen):
    print(f"   {seen[k]:2d}  {k}")
  if zeros:
    print("NO EDG ROW MOVED for:")
    for z in zeros:
      print("  " + z)
  moved_files, in_scope = fz.substrate_stable([PORT, REG_PORT])

  # ---------------------------------------------------------------- D4
  print()
  print("=" * 72)
  print("D4 -- does ANY row gate the register allocator's INSTRUCTION STREAM order?")
  print("=" * 72)
  rp = fz.src_of(REG_PORT)
  rsrc = rp.read_text()
  rbase = CD.rows_of(fz.bend(REG_PORT))
  print(f"BASELINE  {len(rbase)} rows from {REG_PORT}")
  uops_rows = [k for k in rbase if k.endswith("_uops")]
  print(f"  the rows the census flagged: {sorted(uops_rows)}")
  seen_uops = {k: rbase[k] for k in sorted(uops_rows)}
  ident = [v for v in seen_uops.values()]
  print(f"  and ra0_uops == ra1_uops byte for byte: {ident[0] == ident[1] if len(ident) > 1 else 'n/a'}")
  try:
    for mid, what, (old, new) in REG_MUTATIONS:
      if old not in rsrc:
        print(f"{mid:4} SKIPPED -- target text is gone (the file moved on)")
        continue
      rp.write_text(rsrc.replace(old, new, 1))
      try:
        got = CD.rows_of(fz.bend(REG_PORT))
      except SystemExit as e:
        print(f"{mid:4} DID NOT RUN -- {e}")
        continue
      finally:
        rp.write_text(rsrc)
      moved = CD.diff_rows(rbase, got)
      moved_u = [k for k in moved if k in uops_rows]
      print(f"{mid:4} {'OK ' if moved else 'ZERO'}  {len(moved):3d} row(s) moved; "
            f"of which the _uops rows: {moved_u or 'NONE'}")
      print(f"       breaks: {what}")
      print(f"       moved: {sorted(moved)}")
  finally:
    rp.write_text(rsrc)

  if in_scope:
    print("  " + " ".join(in_scope))
  else:
    print("SUBSTRATE STABLE over every in-scope .bend file")
  if moved_files:
    print("  (out of scope, so they cannot change these numbers: %s)" % " ".join(moved_files))
  return 0


if __name__ == "__main__":
  sys.exit(main())
