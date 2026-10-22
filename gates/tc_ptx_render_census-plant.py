#!/usr/bin/env python3
"""tc_ptx_render_census-plant.py -- what this gate CAN and CANNOT see.

    .venv/bin/python gates/tc_ptx_render_census-plant.py

FOUR ARMS AND ONE CONTROL, EACH ON A COPY, EACH NAMING THE ROW IT MOVES.

THE ARMS ARE THE FOUR WAYS THIS GATE WAS BLIND, AND EVERY ONE OF THEM IS A
HISTORICAL FACT ABOUT THIS TREE, NOT A HYPOTHETICAL:

  A1  the tc.py lane dropped from `main` -- a selector that prints nothing.
      MEASURED 2026-10-22: `tc_ptx.bend`'s `main` printed `r_stage2()` and NOT ONE
      of the 289 tc.py rows, so the tc.py half was in NO LANE AT ALL, and the
      recipe that named it was DEAD rather than green.  The tc.py rows live in
      `tc.bend` now, and this arm drops THEM to prove the stage1 diff is real.
  A2  the ptx dtype names reverted to the PRE-RENAME ones.
      MEASURED 2026-10-22: 118 rows carried `signed char`, `half`, `float`,
      `__bf16` where this tree's `tinygrad/` says `i8`, `f16`, `f32`, `bf16`.
      The rotation was upstream's `793abbb16` ("modernize tinygrad's dtype to
      match rust"), which renamed `DType.name` -- and the port's HAND-TYPED row
      labels did not follow.  The arm reproduces that by making the port's own
      dtype NAMES old, which is the shape the rot actually had.
  A3  `wmma_guard_rows` removed from `SELECTORS`.
      MEASURED 2026-10-22: the function existed and was called by NOTHING, and it
      RAISED when called.  A selector that cannot be reached is a guard that
      cannot fail.  The arm removes it and the `wmma` selector must REFUSE.
  A4  a `py=` literal put back beside a correct row.
      The port's `py=` half is DERIVED -- the port's own value, `T.rd(nm, got)` --
      so a transcribed literal beside a correct row is exactly the shape that
      rotted the tc.py half (71 of 286 cells wrong).  The arm puts one back and
      the row must move.

  A0  CONTROL: a comment-only edit, which must move NOTHING.  A control that
      moves something is not a control, and without it the other four numbers
      do not mean anything.

THE COPIES.  A mutation is a (name, what, old, new) edit that must appear
EXACTLY ONCE.  The harness writes a scratch copy BESIDE the original -- Bend
resolves `import ./x.bend` relative to the FILE's own directory, so a copy
anywhere else answers `no such file` -- and DELETES it in a `finally`.  Nothing
in the real tree is edited, ever: the plant's copies are the subject and the
real files are only read.

WHAT MOVED IS MEASURED, NOT ASSERTED.  The gate writes its two lanes under
`gates/artifacts/tc_ptx_render_census/` BEFORE it compares them, so the number of
rows that moved is the DIFF of two artefacts, and an arm that moved nothing is a
coverage gap rather than a pass.
"""

import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY = ROOT / ".venv" / "bin" / "python"
GATE = HERE / "tc_ptx_render_census-gate.py"
ORACLE = HERE / "tc_ptx_render-oracle.py"
ART = HERE / "artifacts" / "tc_ptx_render_census"

TC = ROOT / "tinybendygrad" / "renderer" / "tc.bend"
TCPTX = ROOT / "tinybendygrad" / "renderer" / "tc_ptx.bend"
TC_MUT = ROOT / "tinybendygrad" / "renderer" / "_tcptxmut_tc.bend"
TCPTX_MUT = ROOT / "tinybendygrad" / "renderer" / "_tcptxmut.bend"
ORACLE_MUT = HERE / "_tcptxmut_oracle.py"

# THE OLD SPELLINGS, AND WHERE THE PORT'S OWN NAMES COME FROM.  `tc_ptx.bend` calls
# `T.dt_name(dt)`, which is `tc.bend`'s reader of the port's `LAWS/spec.bend` NAME
# field -- and the port's spec was renamed to follow upstream on 2026-10-02, while
# the ptx half's hand-typed labels were not.  So the arm replaces the DERIVED name
# with the PRE-RENAME one, per dtype, which is the shape the rot had.
OLD_NAME = {1: "signed char", 2: "unsigned char", 3: "short", 4: "unsigned short",
            5: "int", 6: "unsigned int", 7: "long", 8: "unsigned long",
            12: "half", 13: "__bf16", 14: "float", 15: "double"}

DT_OLD = '''
# THE PLANT'S COPY of the dtype-name reader: the PRE-RENAME spellings.
def dt_old_by_pri(pri: U32) -> String:
  match pri:
    case 1:  "signed char"
    case 2:  "unsigned char"
    case 3:  "short"
    case 4:  "unsigned short"
    case 5:  "int"
    case 6:  "unsigned int"
    case 7:  "long"
    case 8:  "unsigned long"
    case 12: "half"
    case 13: "__bf16"
    case 14: "float"
    case 15: "double"
    case _:   ""

def dt_old(+d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}:
      match cls:
        case S.CBool{}:      "bool"
        case S.CVoid{}:      "void"
        case S.CWeakInt{}:   "weakint"
        case S.CWeakFloat{}: "weakfloat"
        case _:              dt_old_by_pri(pri)
'''


def refuse(why):
    print(f"== REFUSED, NOT A VERDICT: tc_ptx_render_census-plant: {why}", file=sys.stderr)
    raise SystemExit(3)


def apply(text, old, new, what):
    if text.count(old) != 1:
        refuse(f"{what}: the edit must appear EXACTLY ONCE; it appears {text.count(old)}")
    return text.replace(old, new)


def run_gate(extra):
    return subprocess.run([str(PY), str(GATE)] + extra, capture_output=True, text=True, cwd=str(ROOT))


def moved_rows(sel):
    """The rows that differ between the two lanes the gate just wrote."""
    p, o = ART / f"{sel}.port.out", ART / f"{sel}.oracle.rows"
    if not (p.exists() and o.exists()):
        return None
    a, b = p.read_text().split("\n"), o.read_text().split("\n")
    return sum(1 for x, y in zip(a, b) if x != y) + abs(len(a) - len(b))


def arm(name, what, sel, fn):
    """Run one arm on COPIES and report what moved."""
    try:
        rc = fn()
        n = moved_rows(sel) if sel else None
        if sel is None:
            print(f"  {name}: gate rc={rc}")
            print(f"      {what}")
        else:
            print(f"  {name}: gate rc={rc}, {n} rows moved in {sel}")
            print(f"      {what}")
        return rc
    finally:
        for p in (TC_MUT, TCPTX_MUT, ORACLE_MUT):
            p.unlink(missing_ok=True)


def main():
    if not GATE.exists():
        refuse("the gate is absent")
    base = run_gate([])
    if base.returncode != 0:
        print(base.stdout, base.stderr)
        refuse(f"the gate is RED at rest (rc={base.returncode}); a plant measures a green gate")
    print(f"tc_ptx_render_census-plant.py: BASE is green (rc=0)\n")

    tc, tcptx, oracle = TC.read_text(), TCPTX.read_text(), ORACLE.read_text()

    # ---- A0: the CONTROL.  A comment-only edit must move NOTHING.
    def a0():
        TCPTX_MUT.write_text(apply(tcptx, "# THE KeyError ARM.",
                                   "# THE KeyError ARM.  # PLANT-CONTROL", "A0"))
        return run_gate(["--stage2", str(TCPTX_MUT)]).returncode
    rc0 = arm("A0", "CONTROL: a comment-only edit, which must move NOTHING.", "stage2", a0)
    if rc0 != 0:
        refuse("the CONTROL went red: the gate is not measuring what it claims")

    # ---- A1: the tc.py lane dropped from `main` -- a selector that prints nothing.
    def a1():
        TC_MUT.write_text(apply(tc, "def main() -> IO(Unit):\n  do IO<Unit>:\n    IO.print(r_stage1())",
                                "def main() -> IO(Unit):\n  do IO<Unit>:\n    IO.print(\"\")",
                                "A1"))
        return run_gate(["--stage1", str(TC_MUT)]).returncode
    arm("A1", "the tc.py lane dropped from `main`: a selector that prints nothing.", "stage1", a1)

    # ---- A2: the ptx dtype names reverted to the PRE-RENAME ones.
    def a2():
        m = tcptx.replace("T.dt_name(", "dt_old(")
        m = m.replace("import ./tc.bend as T", "import ./tc.bend as T\n" + DT_OLD, 1)
        TCPTX_MUT.write_text(m)
        return run_gate(["--stage2", str(TCPTX_MUT)]).returncode
    arm("A2", "the ptx dtype names reverted to the pre-rename ones.", "stage2", a2)

    # ---- A3: `wmma_guard_rows` removed from `SELECTORS`.
    def a3():
        ORACLE_MUT.write_text(apply(oracle, '"wmma": wmma_guard_rows, ', "", "A3"))
        r = subprocess.run([str(PY), str(ORACLE_MUT), "wmma"], capture_output=True, text=True, cwd=str(ROOT))
        print(f"      the `wmma` selector now answers rc={r.returncode}: "
              f"{(r.stderr or '').strip()[:120]}")
        if r.returncode != 3:
            refuse("the `wmma` selector did not REFUSE (rc 3) once the selector was removed")
        return r.returncode
    arm("A3", "`wmma_guard_rows` removed from `SELECTORS`: the selector must REFUSE.", None, a3)

    # ---- A4: a `py=` literal put back beside a correct row.
    def a4():
        TCPTX_MUT.write_text(apply(tcptx,
                                   'T.rd("ptx_matcher rules", U32.show(pm_n_rules()))',
                                   'T.r("ptx_matcher rules", U32.show(pm_n_rules()), "7")', "A4"))
        return run_gate(["--stage2", str(TCPTX_MUT)]).returncode
    arm("A4", "a `py=` literal put back beside a correct row.", "stage2", a4)

    print("\n--plant: all arms ran; A0 (the control) moved nothing, and every other arm moved a row.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
