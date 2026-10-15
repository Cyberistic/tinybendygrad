#!/usr/bin/env python3
"""tc_ptx_types-mutate.py -- what this gate can and cannot see.

    .venv/bin/python gates/tc_ptx_types-mutate.py           # run all

A mutation is a (name, file, old, new) edit that must appear EXACTLY ONCE. The harness
writes a scratch copy BESIDE `tinybendygrad/renderer/tc_ptx.bend` (Bend resolves
`import ./x.bend` relative to the FILE's own directory, so a copy anywhere else answers
`no such file` -- the same constraint `.agents/slop/tcptx-mutate.py` and
`gates/ptx_render_census-mutate.py` both record), repoints the driver's one import at it,
runs the lane, and DIFFS BY WHOLE `name=value` LINE. What moves is the measurement; what
does NOT move is the more useful half and `AGENTS.md` says a zero is a DELIVERABLE.

WHY THE HARNESS MUTATES THE PORT AND NOT THE DRIVER. The fix is in
`renderer/tc_ptx.bend`; the driver only reads three tables. A mutation of the driver
would prove the driver is read, which was never in doubt, and would move nothing that
says anything about the tables.

M5 IS THE ONE THAT MATTERS MOST. It is not a revert: `w_int()` keeps dispatching on the
class and simply reads the WRONG table entry, so `weakint` gets `u32` -- a real PTX type,
a legal `.reg`, and a kernel that compiles and is wrong. That is `renderer/amd/dsl.bend`'s
`U32.shln` and `tc_ptx.bend`'s own `pred` in miniature, and it is the only way to tell a
gate that refuses empties apart from one that refuses CONCRETE WRONG TYPES.
"""

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BEND = ROOT / "bin" / "bend"

PORT = ROOT / "tinybendygrad" / "renderer" / "tc_ptx.bend"
PORT_MUT = ROOT / "tinybendygrad" / "renderer" / "_tcptxmut.bend"
DRV = HERE / "tc_ptx_types.bend"
DRV_MUT = HERE / "_tcptx_types_mut.bend"

MUTATIONS = [
    ("M1", "types_of loses the class dispatch and goes back to the bare pri lookup, so "
           "`void` and `weakint` take `bool`'s `pred` again and `weakfloat` is empty.",
     "def types_of(+dt: S.Dt) -> String:\n  match dt:\n    case S.Dt{pri, bits, cls, nm}:\n"
     "      match cls:\n        case S.CWeakInt{}:   w_int()\n        case S.CWeakFloat{}: w_float()\n"
     "        case S.CVoid{}:      \"\"\n        case _:              types_pri(pri)",
     "def types_of(+dt: S.Dt) -> String:\n  match dt:\n    case S.Dt{pri, bits, cls, nm}: types_pri(pri)"),
    ("M2", "mem_types_of loses the class dispatch. This arm is SEPARATE from M1 because "
           "`mem_types`' own `case 0: \"u8\"` reached `weakint` down a different road, so "
           "fixing only `types_of` would have left `mem_types_weakint` wrong.",
     "def mem_types_of(+dt: S.Dt) -> String:\n  match dt:\n    case S.Dt{pri, bits, cls, nm}:\n"
     "      match cls:\n        case S.CWeakInt{}:   w_int()\n        case S.CWeakFloat{}: w_float()\n"
     "        case S.CVoid{}:      \"\"\n        case _:              mem_types_pri(pri)",
     "def mem_types_of(+dt: S.Dt) -> String:\n  match dt:\n    case S.Dt{pri, bits, cls, nm}: mem_types_pri(pri)"),
    ("M3", "cast_types_of loses the class dispatch.",
     "def cast_types_of(+dt: S.Dt) -> String:\n  match dt:\n    case S.Dt{pri, bits, cls, nm}:\n"
     "      match cls:\n        case S.CWeakInt{}:   w_int()\n        case S.CWeakFloat{}: w_float()\n"
     "        case S.CVoid{}:      \"\"\n        case _:              cast_types_pri(pri)",
     "def cast_types_of(+dt: S.Dt) -> String:\n  match dt:\n    case S.Dt{pri, bits, cls, nm}: cast_types_pri(pri)"),
    ("M4", "`w_int()` reads `uint32`'s entry instead of `int32`'s, so `weakint` answers "
           "`u32` -- A REAL PTX TYPE, a legal `.reg`, and a kernel that compiles and is "
           "wrong. NOT a revert: the dispatch is intact and only the answer is a lie, which "
           "is the whole shape of the class this gate exists for.",
     "def w_int() -> String: types_pri(S.Dt.pri(S.int32()))",
     "def w_int() -> String: types_pri(S.Dt.pri(S.uint32()))"),
    ("M5", "`types_of` drops ONLY the `CVoid` arm. `void` is unreachable through "
           "`ptx.py:219` (a void RANGE has its prefix cleared) and this is the reading that "
           "says so: one row, one dtype, and no other row moves.",
     "        case S.CWeakFloat{}: w_float()\n        case S.CVoid{}:      \"\"\n"
     "        case _:              types_pri(pri)",
     "        case S.CWeakFloat{}: w_float()\n        case _:              types_pri(pri)"),
    ("M6", "CONTROL: a comment-only edit, which must move NOTHING.",
     "# BOOTSTRAP-MUTABLE: this comment is M6's anchor",
     "# BOOTSTRAP-MUTABLE: this comment is M6's anchor  # noqa"),
]


def apply(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"the edit must appear EXACTLY ONCE; it appears {text.count(old)}")
    return text.replace(old, new)


def lanes(driver):
    r = subprocess.run([str(BEND), str(driver)], capture_output=True, text=True, cwd=str(ROOT))
    if r.returncode != 0:
        said = [l.strip() for l in (r.stderr or "").splitlines() if l.strip()][:6]
        print("      bend said: " + " | ".join(said))
    return {l for l in r.stdout.splitlines() if l.strip() and "=" in l}


def main():
    port = PORT.read_text()
    # The control's anchor does not exist yet, so it is ADDED to the BASE and to every
    # mutant alike. A control that edits a comment nobody has written is not a control.
    if port.count(MUTATIONS[5][2]) != 0:
        raise SystemExit("the control's anchor already exists; pick another")
    port = port.replace("# THE KeyError ARM.",
                        MUTATIONS[5][2] + "\n# THE KeyError ARM.")
    base = lanes(DRV)
    print(f"tc_ptx_types-mutate.py: BASE is {len(base)} rows\n")

    for name, what, old, new in MUTATIONS:
        PORT_MUT.write_text(apply(port, old, new))
        DRV_MUT.write_text(DRV.read_text().replace(
            "import ./../tinybendygrad/renderer/tc_ptx.bend as P",
            "import ./../tinybendygrad/renderer/_tcptxmut.bend as P"))
        try:
            got = lanes(DRV_MUT)
            moved = sorted(base ^ got)
            control = what.startswith("CONTROL")
            print(f"  {name}: {len(moved)} rows moved")
            print(f"      {what}")
            for x in moved[:4]:
                print(f"      {x}")
            if not got:
                print("      THE LANE EMITTED NOTHING -- the mutant did not compile.")
            elif not moved and control:
                # A control's zero is the POINT, and calling it a coverage gap would be a
                # wrong reason: a gap means a rule nobody can see, and this rule is the
                # harness's own claim that an edit outside the tables cannot move a row.
                print("      NOTHING, as a control must -- an edit outside the tables cannot "
                      "move a row, which is what makes the other five numbers mean something.")
            elif not moved:
                print("      MOVED NOTHING -- a COVERAGE GAP: this rule has no row.")
        finally:
            PORT_MUT.unlink(missing_ok=True)
            DRV_MUT.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())