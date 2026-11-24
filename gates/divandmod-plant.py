#!/usr/bin/env python3
"""divandmod-plant.py -- THE PLANT FOR `gates/divandmod-gate.py`.

    .venv/bin/python gates/divandmod-plant.py

A GATE THAT CAN ONLY PRINT GREEN MEASURES NOTHING, AND A PLANT THAT CAN ONLY
PRINT RED PROVES NOTHING.  **SO THIS PLANT HAS BOTH DIRECTIONS**, AND EACH
CASE GOES THROUGH THE **SAME LANE** THE GATE USES -- THE PORT's `.bend` DRIVER
AND THE CPython ORACLE -- SO A PLANT THAT SAID "RED" ON A COPY THE GATE NEVER
RUNS WOULD PROVE NOTHING.

FOUR CASES:

  1. THE UN-MUTATED COPY IS GREEN -- the control.
  2. BREAKING THE ARM's `divides` GUARD REDDENS THE PORT's LANE -- the arm
     stops firing, so the port's answer is `nofold` and the ORACLE's is a
     rewrite, and THE LANES DISAGREE.
  3. BREAKING THE ARM's POSITIVE-DIVISOR GUARD REDDENS THE LANE TOO -- `c`
     becomes `0`-or-negative, so `c > 0` fails and the arm does not fire.
  4. BREAKING THE `usum` ASSOCIATION REDDENS THE LANE -- the sum's TREE
     changes and the ORACLE's tree is the upstream one, so they disagree.

AND THE PLANT'S CLAIM IS ABOUT THE **DIFFERENTIAL** AND NOT ABOUT THE PORT's
ANSWER: A PLANT THAT BROKE THE PORT's ARM AND ONLY CHECKED THAT THE PORT's
ANSWER CHANGED WOULD NOT SHOW THAT THE GATE CAN GO RED.

EXIT: 0 every plant fired · 1 a plant did not · 3 REFUSED (a precondition was
absent).
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "gates"))

BEND = ROOT / "bin" / "bend"
DRIVER = ROOT / "gates" / "divandmod-driver.bend"
ORACLE = ROOT / "gates" / "divandmod-oracle.py"
CASES = ROOT / "gates" / "divandmod-cases.rows"
PORT = ROOT / "tinybendygrad"

PASS, FAIL, REFUSED = 0, 1, 3


def port_lane(root: Path) -> str:
    """THE PORT's LANE, AND IT IS THE DRIVER THE GATE RUNS."""
    r = subprocess.run([str(BEND), str(root / "gates" / "divandmod-driver.bend")],
                       capture_output=True, text=True, cwd=ROOT)
    return r.stdout


def oracle_lane() -> str:
    """THE ORACLE's LANE, AND IT IS THE ORACLE THE GATE RUNS."""
    r = subprocess.run([sys.executable, str(ORACLE)], capture_output=True, text=True, cwd=ROOT)
    return r.stdout


def fresh(dest: Path) -> Path:
    """A COPY OF THE TREE'S `gates/` AND `tinybendygrad/`, AND THE CASE FILE
    IS THE ONE THE GATE READS."""
    shutil.rmtree(dest, ignore_errors=True)
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / "gates", dest / "gates")
    shutil.copytree(PORT, dest / "tinybendygrad")
    shutil.copy2(CASES, dest / "gates" / "divandmod-cases.rows")
    return dest


def agrees(root: Path) -> bool:
    """DO THE TWO LANES AGREE ON THE COPY AT `root`?"""
    return port_lane(root) == oracle_lane()


def main() -> int:
    if not BEND.exists():
        print("REFUSED, NOT A VERDICT: there is no `bin/bend` in this tree")
        return REFUSED
    bad = []
    with tempfile.TemporaryDirectory(prefix="divandmod-plant-") as td:
        # 1 -- the control
        control = fresh(Path(td) / "control")
        ok = agrees(control)
        print(f"  1 control          {'GREEN' if ok else 'NOT GREEN'}  the lanes agree")
        if not ok:
            bad.append("the control copy's lanes do not agree")

        # 2 -- the `divides` GUARD: `dm_rnm.divides` ALWAYS SAYS "DOES NOT
        # DIVIDE", SO THE ARM NEVER FIRES AND THE PORT ANSWERS `nofold` WHERE
        # THE ORACLE REWRITES.
        #
        # AND MEASURED 2026-11-24: THE FIRST DRAFT BROKE THE GUARD TO "ALWAYS
        # DIVIDES" AND THE PLANT DID NOT GO RED -- AND THE REASON IS THAT THE
        # CASES ALREADY DIVIDE, SO THE MUTATION CHANGED NOTHING.  **A PLANT
        # THAT MUTATES A GUARD WHICH IS ALREADY SATISFIED PROVES NOTHING.**
        case2 = fresh(Path(td) / "case2")
        f = case2 / "tinybendygrad" / "uop" / "divandmod.bend"
        text = f.read_text()
        old = '''def dm_rnm.divides(+ar: O.Arena, u: U32, c: H.I64) -> Bool:
  +d = O.UOp.divides(O.Arena.budget(ar), ar, c, O.Arena.src(ar, u, 1))
  O.Dv.ok(d)'''
        new = '''def dm_rnm.divides(+ar: O.Arena, u: U32, c: H.I64) -> Bool:
  False{}'''
        if old not in text:
            bad.append("the `dm_rnm.divides` guard moved")
            print("  2 divides guard    COULD NOT MUTATE")
        else:
            f.write_text(text.replace(old, new, 1))
            ok = not agrees(case2)
            print(f"  2 divides guard    {'RED' if ok else 'NOT RED'}  the arm stops firing")
            if not ok:
                bad.append("breaking the `divides` guard did not redden the lanes")

        # 3 -- THE ZERO-DIVISOR CHECK: `dm_zero` ALWAYS SAYS "FALSE", SO THE
        # PORT DOES NOT RAISE ON A ZERO DIVISOR AND THE `zero` ROW's ANSWER IS
        # A REWRITE WHERE THE ORACLE SAYS `RAISED`.
        #
        # AND MEASURED 2026-11-24: THE FIRST DRAFT BROKE THE **POSITIVE**-
        # DIVISOR GUARD (`c > 0` BECOMES `c >= 0`) AND THE PLANT DID NOT GO
        # RED -- AND THE REASON IS THAT THE `zero` ROW's DIVISOR IS ZERO AND
        # THE ARM's `divides` ON A ZERO DIVISOR NEVER REACHES THAT GUARD, SO
        # THE MUTATION CHANGED NOTHING.  **A PLANT THAT MUTATES A GUARD WHICH
        # IS NEVER REACHED PROVES NOTHING.**
        case3 = fresh(Path(td) / "case3")
        f3 = case3 / "tinybendygrad" / "uop" / "divandmod.bend"
        text3 = f3.read_text()
        old3 = """def dm_zero(+ar: O.Arena, +d: U32) -> Bool:
  dm_zero.op(O.Arena.op(ar, O.Arena.src(ar, d, 1)), O.Arena.arg(ar, O.Arena.src(ar, d, 1)))"""
        new3 = """def dm_zero(+ar: O.Arena, +d: U32) -> Bool:
  False{}"""
        if old3 not in text3:
            bad.append("the zero-divisor check moved")
            print("  3 zero divisor     COULD NOT MUTATE")
        else:
            f3.write_text(text3.replace(old3, new3, 1))
            ok = not agrees(case3)
            print(f"  3 zero divisor     {'RED' if ok else 'NOT RED'}  the port does not raise")
            if not ok:
                bad.append("breaking the zero-divisor check did not redden the lanes")

        # 4 -- the `usum` ASSOCIATION: THE SUM BECOMES RIGHT-NESTED
        case4 = fresh(Path(td) / "case4")
        f4 = case4 / "tinybendygrad" / "uop" / "ops.bend"
        text4 = f4.read_text()
        old4 = '''def UOp.usum.pair(+f: Found, x: U32, +ar: Arena) -> Found:
  UOp.alu(Found.ar(f), OpsADD{}, [Found.i(f), x])'''
        new4 = '''def UOp.usum.pair(+f: Found, x: U32, +ar: Arena) -> Found:
  UOp.alu(Found.ar(f), OpsADD{}, [x, Found.i(f)])'''
        if old4 not in text4:
            bad.append("the `UOp.usum` association moved")
            print("  4 usum assoc       COULD NOT MUTATE")
        else:
            f4.write_text(text4.replace(old4, new4, 1))
            ok = not agrees(case4)
            print(f"  4 usum assoc       {'RED' if ok else 'NOT RED'}  the sum is right-nested")
            if not ok:
                bad.append("breaking the `usum` association did not redden the lanes")

        # 5 -- THE MOD HALF's MULTIPLICATION: `ret*gcd` BECOMES `ret`, SO THE
        # MOD's ANSWER IS THE DIV's ANSWER AND THE LANES DISAGREE.
        #
        # AND MEASURED 2026-11-24: THIS IS THE CASE THAT PROVES THE **MOD HALF**
        # IS **LOAD-BEARING** AND NOT A VARIANT OF THE DIV HALF -- THE TWO
        # ANSWER SHAPES ARE DIFFERENT AND A GATE THAT ONLY PROVED THE DIV HALF
        # WOULD PASS WITH THE MULTIPLICATION DELETED.
        case5 = fresh(Path(td) / "case5")
        f5 = case5 / "tinybendygrad" / "uop" / "divandmod.bend"
        text5 = f5.read_text()
        old5 = """    case True{}: Some{dm_dg_mul(O.Found.ar(ret), ret, g)}
    case False{}: Some{ret}"""
        new5 = """    case True{}: Some{ret}
    case False{}: Some{ret}"""
        if old5 not in text5:
            bad.append("the MOD half's multiplication moved")
            print("  5 mod half         COULD NOT MUTATE")
        else:
            f5.write_text(text5.replace(old5, new5, 1))
            ok = not agrees(case5)
            print(f"  5 mod half         {'RED' if ok else 'NOT RED'}  the MOD half drops ret*gcd")
            if not ok:
                bad.append("dropping the MOD half's multiplication did not redden the lanes")

    print(f"--plant: {'OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return FAIL if bad else PASS


if __name__ == "__main__":
    sys.exit(main())
