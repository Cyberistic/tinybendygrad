#!/usr/bin/env python3
"""Mutation table for the `eq_cls.sel` fix in `uop/ops.bend`.

Applies ONE edit, runs the interpreted lane, diffs the rows against a baseline
and RESTORES the file -- always, including on exception, because a mutation that
fails to compile must not leave the file broken. (`dm-oracle`'s author learned
that one the hard way; see the note in `.agents/slop/tools/mutate-dm.py`.)

    .venv/bin/python .agents/slop/tools/mutate-eqcls.py

Prints one line per mutation and the rows that moved. A row that only ONE
mutation moves is a LOCALISED row.
"""
import subprocess, sys, pathlib, tempfile, os

REPO = pathlib.Path(__file__).resolve().parents[3]
TARGET = REPO / "tinybendygrad" / "uop" / "ops.bend"
BEND = REPO / "bin" / "bend"

# (label, old, new) -- each `old` occurs EXACTLY ONCE in the file, asserted below.
MUTATIONS = [
  # M1: the bug as reported -- drop the seventh arm back to six, with the
  # catch-all answering CWeakFloat as CFloat. This is the state the gate was
  # blind to.
  ("M1 eq_cls.sel: CWeakFloat arm removed (6 arms, `case _` -> CFloat)",
   "    case S.CFloat{}: eq_cls.CFloat(x, y)\n    case _: eq_cls.CWeakFloat(x, y)",
   "    case _: eq_cls.CFloat(x, y)"),

  # M2: the TRAP the brief warned about -- append the new arm AFTER the
  # catch-all. Bend 2.0.34 makes such an arm DEAD, so this compiles and is
  # behaviourally identical to M1. It is in the table because "it looks right
  # and is wrong" is the failure mode the fix's comment is about.
  ("M2 eq_cls.sel: CWeakFloat appended AFTER `case _` (unreachable)",
   "    case S.CFloat{}: eq_cls.CFloat(x, y)\n    case _: eq_cls.CWeakFloat(x, y)",
   "    case _: eq_cls.CWeakFloat(x, y)\n    case S.CFloat{}: eq_cls.CFloat(x, y)"),

  # M3: conflate the other way -- the catch-all answers CUint, so the ladder
  # still has seven constructors but two of them collapse.
  ("M3 eq_cls.sel: catch-all answers CUint instead of CWeakFloat",
   "    case _: eq_cls.CWeakFloat(x, y)",
   "    case _: eq_cls.CUint(x, y)"),

  # M4: a six-arm ladder that drops CBool instead, i.e. the bug moved rather
  # than fixed. Catches a row that only pins weakfloat.
  ("M4 eq_cls.sel: CBool arm removed, catch-all -> CWeakFloat",
   "    case S.CBool{}: eq_cls.CBool(x, y)\n    case S.CUint{}: eq_cls.CUint(x, y)",
   "    case S.CUint{}: eq_cls.CUint(x, y)"),

  # M5: the `y` side rather than the `x` side. `eq_cls.CWeakFloat` matches on
  # its second parameter, so breaking it there is the same bug reached from the
  # other direction.
  ("M5 eq_cls.CWeakFloat: matches CFloat on the y side",
   "    case S.CWeakFloat{}: True{}\n    case _: False{}\n\n# `S.Cls` has SEVEN",
   "    case S.CFloat{}: True{}\n    case _: False{}\n\n# `S.Cls` has SEVEN"),
]


def run(path):
  r = subprocess.run([str(BEND), str(path)], capture_output=True, text=True, cwd=REPO)
  return r.stdout + r.stderr


def rows(text):
  out = {}
  for line in text.splitlines():
    if "=" in line:
      k, _, v = line.partition("=")
      out[k.strip()] = v.strip()
  return out


def main():
  original = TARGET.read_text()
  base_text = run(TARGET)
  base = rows(base_text)
  if not base:
    print("baseline printed no rows; refusing to report a mutation table")
    print(base_text[:2000])
    return 1
  print(f"baseline: {len(base)} rows, all "
        f"{'green' if set(base.values()) == {'True'} else 'NOT all green'}")
  print()
  src = original
  for label, old, new in MUTATIONS:
    if src.count(old) != 1:
      print(f"{label}\n  SKIPPED: anchor occurs {src.count(old)}x, not 1")
      continue
    mutated = src.replace(old, new)
    tmp = pathlib.Path(tempfile.mkdtemp()) / "ops_mutant.bend"
    try:
      # the mutation has to sit in the real path for its relative imports, so
      # the file is written in place and restored in `finally`.
      TARGET.write_text(mutated)
      out = run(TARGET)
      got = rows(out)
      moved = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
      failed = not got
      print(f"{'COMPILE-FAIL' if failed else 'ok':>12}  {label}")
      if failed:
        print(f"                {out.splitlines()[0] if out else '(no output)'}")
      else:
        print(f"                rows moved: {len(moved)}"
              + (f"  {moved}" if moved else "  -- NONE, this row set cannot see it"))
    finally:
      TARGET.write_text(src)
      assert TARGET.read_text() == original, "restore failed"
      tmp.unlink(missing_ok=True)
  print()
  print("restored; ops.bend defs =", sum(1 for l in original.splitlines()
                                         if l.startswith(("def ", "type "))))
  return 0


if __name__ == "__main__":
  sys.exit(main())
