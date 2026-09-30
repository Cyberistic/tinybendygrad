#!/usr/bin/env python3
"""Mutation table for the `floordiv_i32` fix in `helpers.bend`.

Applies ONE edit, runs the div/mod gate, and RESTORES the file -- always,
including on exception, because a mutation that fails to compile must not leave
the file broken. (`.agents/slop/tools/mutate-dm.py`'s author learned that the
hard way and the note is worth keeping.)

    .venv/bin/python .agents/slop/tools/mutate-floor.py

The gate is `.agents/slop/tools/dm-floor-gate.sh`, which diffs `dm.bend` against
`tinygrad.helpers` itself, so a row that "moves" here means the PORT and
CPYTHON disagree -- not that two copies of the port disagree.
"""
import subprocess, sys, pathlib

REPO = pathlib.Path(__file__).resolve().parents[3]
TARGET = REPO / "tinybendygrad" / "helpers.bend"
GATE = REPO / ".agents" / "slop" / "tools" / "dm-floor-gate.sh"

FIXED_NEG = """    case False{}:
      match neg:
        case True{}: floordiv_i32.trunc.put(neg, U32.add(q, 1))
        case False{}: q"""

# (label, old, new)
MUTATIONS = [
  # M1: THE REPORTED BUG. The `neg` test dropped: the step is applied on every
  # inexact division, so every same-sign division is one too big.
  ("M1 the reported bug: `neg` test dropped from the inexact arm",
   FIXED_NEG, "    case False{}: floordiv_i32.trunc.put(neg, U32.add(q, 1))"),

  # M2: the OTHER direction -- the step never applied, i.e. truncating
  # division wearing floordiv's name. This is the mistake an agent makes by
  # "fixing" the sign by deleting the adjustment.
  ("M2 the step removed entirely (truncating division, not floor)",
   FIXED_NEG, """    case False{}:
      match neg:
        case True{}: floordiv_i32.trunc.put(neg, q)
        case False{}: q"""),

  # M3: the exact arm wrong instead, so `exact` and `neg` are swapped in
  # position -- the ladder has both flags but reads the wrong one.
  ("M3 `exact` and `neg` swapped: the step keys off `exact` on both arms",
   """    case True{}: floordiv_i32.trunc.put(neg, q)
    case False{}:
      match neg:
        case True{}: floordiv_i32.trunc.put(neg, U32.add(q, 1))
        case False{}: q""",
   """    case True{}: floordiv_i32.trunc.put(neg, U32.add(q, 1))
    case False{}:
      match neg:
        case True{}: floordiv_i32.trunc.put(neg, q)
        case False{}: q"""),

  # M4: the zero-divisor guard dropped, which tinygrad's helpers.py:76 has and
  # every caller relies on. Not the reported bug; here to show the gate also
  # pins the branch Python has and the report said nothing about.
  ("M4 `floordiv_i32.pick`: the `y == 0` guard dropped (U32.div(.,0)=0 anyway)",
   """def floordiv_i32.pick(zero: Bool, neg: Bool, exact: Bool, ax: U32, ay: U32) -> U32:
  match zero:
    case True{}: 0
    case False{}: floordiv_i32.trunc(neg, exact, U32.div(ax, ay))""",
   """def floordiv_i32.pick(zero: Bool, neg: Bool, exact: Bool, ax: U32, ay: U32) -> U32:
  match zero:
    case True{}: 1
    case False{}: floordiv_i32.trunc(neg, exact, U32.div(ax, ay))"""),
]


def run_gate():
  r = subprocess.run([str(GATE)], capture_output=True, text=True, cwd=REPO)
  return r.returncode, r.stdout + r.stderr


def main():
  original = TARGET.read_text()
  rc, out = run_gate()
  if rc != 0:
    print("baseline gate is RED; refusing to report a mutation table\n")
    print(out[:3000])
    return 1
  print("baseline gate: GREEN\n")
  src = original
  for label, old, new in MUTATIONS:
    if src.count(old) != 1:
      print(f"  SKIPPED  {label}\n           anchor occurs {src.count(old)}x, not 1")
      continue
    try:
      TARGET.write_text(src.replace(old, new))
      rc, out = run_gate()
      moved = [l for l in out.splitlines()
               if l.startswith(("+ok_", "-ok_", "+bad_", "-bad_"))]
      moved = sorted({l[1:].split("=")[0] for l in moved})
      if rc == 0:
        print(f"    ok     {label}\n           rows moved: NONE -- this row set "
              f"cannot see it")
      else:
        first = out.splitlines()[0] if out else ""
        print(f"  {'ok':>7}  {label}\n           {first}  rows moved: {len(moved)}")
        for m in moved:
          print(f"             {m}")
    finally:
      TARGET.write_text(src)
      assert TARGET.read_text() == original, "restore failed"
  print()
  rc, out = run_gate()
  print("restored; baseline gate is", "GREEN" if rc == 0 else "RED")
  print("helpers.bend defs =", sum(1 for l in original.splitlines()
                                   if l.startswith(("def ", "type "))))
  return 0 if rc == 0 else 1


if __name__ == "__main__":
  sys.exit(main())
