#!/usr/bin/env python3
"""divandmod-plant.py -- THE PLANT FOR `gates/divandmod-gate.py`.

    .venv/bin/python gates/divandmod-plant.py

A GATE THAT CAN ONLY PRINT GREEN MEASURES NOTHING, AND A PLANT THAT CAN ONLY
PRINT RED PROVES NOTHING.  **SO THIS PLANT HAS BOTH DIRECTIONS**, AND EACH
CASE GOES THROUGH THE **SAME LANE** THE GATE USES -- THE PORT's `.bend` DRIVER
AND THE CPython ORACLE -- SO A PLANT THAT SAID "RED" ON A COPY THE GATE NEVER
RUNS WOULD PROVE NOTHING.

TWELVE CASES:

  1. THE UN-MUTATED COPY IS GREEN -- the control.
  2. BREAKING THE ARM's `divides` GUARD REDDENS THE PORT's LANE -- the arm
     stops firing, so the port's answer is `nofold` and the ORACLE's is a
     rewrite, and THE LANES DISAGREE.
  3. BREAKING THE ARM's POSITIVE-DIVISOR GUARD REDDENS THE LANE TOO -- `c`
     becomes `0`-or-negative, so `c > 0` fails and the arm does not fire.
  4. BREAKING THE `usum` ASSOCIATION REDDENS THE LANE -- the sum's TREE
     changes and the ORACLE's tree is the upstream one, so they disagree.
  5. BREAKING THE `divide_by_gcd` ARM's MOD HALF REDDENS THE LANE -- the MOD's
     `ret*gcd` becomes `ret`.
  6. BREAKING THE `factor_remainder` ARM's `+sum(quo)` REDDENS THE LANE.
  7. BREAKING THE `factor_remainder` ARM's SUM's LEADING `+0` REDDENS IT.
  8. BREAKING THE `factor_remainder` ARM's `x.const_like(0)` REDDENS IT.
  9. BREAKING THE `factor_remainder` ARM's CONSTANT BRANCH's TEST REDDENS IT.
 10. BREAKING THE `nested_div` ARM's POSITIVE-QUOTIENT GUARD REDDENS IT.
 11. BREAKING THE `factor_remainder` ARM's CONSTANT BRANCH's MULTIPLICATION
     REDDENS IT -- AND THE `MUL` IS A **MULTIPLICATION** AND NOT A DIVISION
     (divandmod.py:84-85), SO THE MUTATION CHANGES THE TREE.
 12. BREAKING THE `factor_remainder` ARM's ARENA THREADING REDDENS IT -- AND
     THE ARENA IS **ONE CHAIN** AND NOT A TREE OF BRANCHES, SO A STALE ARENA
     READS THE ARENA's BOTTOM NOOP NODE.

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

        # 6 -- THE `factor_remainder` ARM's `+sum(quo)`: THE QUOTIENT'S SUM IS
        # DROPPED, SO THE PORT's ANSWER IS `new_x//y` AND THE LANES DISAGREE.
        #
        # AND MEASURED 2026-11-25: THE FIRST DRAFT OF THE ARM DROPPED IT AND
        # THE PORT ANSWERED `DIV(ADD(ADD(c0,b),c0),d)` WHERE UPSTREAM ANSWERS
        # `ADD(DIV(ADD(ADD(c0,b),c0),d),ADD(c0,MUL(c1,a)))`.  **SO THE ROW IS
        # LOAD-BEARING AND NOT A VARIANT.**
        case6 = fresh(Path(td) / "case6")
        f6 = case6 / "tinybendygrad" / "uop" / "divandmod.bend"
        text6 = f6.read_text()
        old6 = """      +q = dm_fr.sum(O.Found.ar(nx), quo)
      +dv = O.UOp.alu(O.Found.ar(q), O.OpsDIV{}, [O.Found.i(nx), y])
      Some{O.UOp.alu(O.Found.ar(dv), O.OpsADD{}, [O.Found.i(dv), O.Found.i(q)])}"""
        new6 = """      +dv = O.UOp.alu(O.Found.ar(nx), O.OpsDIV{}, [O.Found.i(nx), y])
      Some{dv}"""
        if old6 not in text6:
            bad.append("the `factor_remainder` answer's `+sum(quo)` moved")
            print("  6 fr sum(quo)      COULD NOT MUTATE")
        else:
            f6.write_text(text6.replace(old6, new6, 1))
            ok = not agrees(case6)
            print(f"  6 fr sum(quo)      {'RED' if ok else 'NOT RED'}  the quotient's sum is dropped")
            if not ok:
                bad.append("dropping the `factor_remainder` answer's `+sum(quo)` did not redden the lanes")

        # 7 -- THE `factor_remainder` ARM's SUM **STARTS WITH THE INT `0`**:
        # PYTHON's `sum` DOES AND `UOp.usum` DOES NOT, AND THE PORT's
        # `dm_fr.sum` STARTS WITH A `CONST 0` NODE SO THE FIRST TERM IS
        # `ADD(c0, r0)`.
        #
        # AND MEASURED 2026-11-25: A FIRST DRAFT FOLDED FROM THE FIRST
        # ELEMENT AND THE PORT ANSWERED `ADD(c0,MUL(c1,a))` WHERE UPSTREAM
        # ANSWERS `ADD(c0,MUL(c1,a))` -- **AND THE ROWS THAT DIFFER ARE THE
        # ONES WITH MORE THAN ONE TERM**, SO THE PLANT MUTATES THE `+0`.
        case7 = fresh(Path(td) / "case7")
        f7 = case7 / "tinybendygrad" / "uop" / "divandmod.bend"
        text7 = f7.read_text()
        old7 = """def dm_fr.sum.first(+l: List<&2, U32>, +z: O.Found) -> O.Found:
  match l:
    case Nil{}: z
    case h <> t: dm_fr.sum.go(t, O.UOp.alu(O.Found.ar(z), O.OpsADD{}, [O.Found.i(z), h]))"""
        new7 = """def dm_fr.sum.first(+l: List<&2, U32>, +z: O.Found) -> O.Found:
  match l:
    case Nil{}: z
    case h <> t: dm_fr.sum.go(t, h)"""
        if old7 not in text7:
            bad.append("the `factor_remainder` sum's leading `+0` moved")
            print("  7 fr sum's +0      COULD NOT MUTATE")
        else:
            f7.write_text(text7.replace(old7, new7, 1))
            ok = not agrees(case7)
            print(f"  7 fr sum's +0      {'RED' if ok else 'NOT RED'}  the sum drops the leading zero")
            if not ok:
                bad.append("dropping the `factor_remainder` sum's leading zero did not redden the lanes")

        # 8 -- THE `factor_remainder` ARM's `x.const_like(0)`: THE `+0` IS DROPPED
        # FROM `new_x`, SO THE PORT's `new_x` IS `sum(rem)` AND THE LANES
        # DISAGREE.
        case8 = fresh(Path(td) / "case8")
        f8 = case8 / "tinybendygrad" / "uop" / "divandmod.bend"
        text8 = f8.read_text()
        old8 = """  +z = dm_fr.zero(O.Found.ar(s))
  +nx = O.UOp.alu(O.Found.ar(z), O.OpsADD{}, [O.Found.i(s), O.Found.i(z)])"""
        new8 = """  +nx = s"""
        if old8 not in text8:
            bad.append("the `factor_remainder` arm's `const_like(0)` moved")
            print("  8 fr const_like    COULD NOT MUTATE")
        else:
            f8.write_text(text8.replace(old8, new8, 1))
            ok = not agrees(case8)
            print(f"  8 fr const_like    {'RED' if ok else 'NOT RED'}  the `+0` is dropped from new_x")
            if not ok:
                bad.append("dropping the `factor_remainder` arm's `const_like(0)` did not redden the lanes")

        # 9 -- THE `factor_remainder` ARM's CONSTANT BRANCH's TEST:
        # `(c:=u.const_factor())%y.val != c` (divandmod.py:83) -- **THE FACTOR
        # DOES NOT DIVIDE THE DIVISOR** -- AND A FIRST DRAFT TESTED
        # `cf % yv != 0` INSTEAD, WHICH IS A **DIFFERENT** TEST.
        #
        # AND THE TWO DIFFER FOR EVERY TERM WHOSE FACTOR IS **1**, AND A
        # **MOD** NODE's FACTOR IS 1 (upstream's `const_factor` answers 1 for
        # anything that is not a CONST, an ADD or a MUL, ops.py:1013-1018).
        # MEASURED 2026-11-25: WITH THE WRONG TEST THE PORT ANSWERED
        # `DIV(0,4)+0` FOR `(x%6)//4` -- **AND `(x%6)//4` IS NOT 0** (IT IS 1
        # FOR `x` IN `4..5`).  **SO THE MUTATION IS A VALUE-CHANGING REWRITE
        # AND NOT A SHAPE ONE, AND A GATE THAT COMPARES TREES ALONE CANNOT
        # SEE IT -- THE LANE DIFF DOES, BECAUSE THE PORT's ANSWER CHANGES.**
        case9 = fresh(Path(td) / "case9")
        f9 = case9 / "tinybendygrad" / "uop" / "divandmod.bend"
        text9 = f9.read_text()
        old9 = """  dm_fr.term.go5(Cmp.is_eq(H.i64_cmp(H.i64_mod(cf, yv), cf)), ar, u, y, yv, isdiv, acc, cf)"""
        new9 = """  dm_fr.term.go5(H.i64_is_zero(H.i64_mod(cf, yv)), ar, u, y, yv, isdiv, acc, cf)"""
        if old9 not in text9:
            bad.append("the `factor_remainder` constant branch's test moved")
            print("  9 fr const branch   COULD NOT MUTATE")
        else:
            f9.write_text(text9.replace(old9, new9, 1))
            ok = not agrees(case9)
            print(f"  9 fr const branch   {'RED' if ok else 'NOT RED'}  the factor test is `!= 0`")
            if not ok:
                bad.append("the `factor_remainder` constant branch's wrong test did not redden the lanes")

        # 10 -- THE `nested_div` ARM's POSITIVE-QUOTIENT GUARD: `k.vmin > 0`
        # (divandmod.py:23) BECOMES "NEVER POSITIVE", SO THE ARM NEVER FIRES
        # AND THE FIVE `nd_*` ROWS BECOME `nofold` WHERE THE ORACLE REWRITES.
        #
        # AND THE `k=1` ROW (`nd_8_8`) IS THE ONE THAT PROVES THE GUARD IS
        # **NOT** `k != 1`: UPSTREAM's TEST IS `k.vmin > 0` AND `1 > 0` IS
        # TRUE, SO THE ARM STILL FIRES -- MEASURED 2026-11-25: UPSTREAM
        # ANSWERS `MOD(DIV(x,c8),c1)`.  MUTATING THE GUARD TO "ALWAYS POSITIVE"
        # WOULD CHANGE NOTHING ON THAT ROW, SO THE MUTATION IS THE OTHER WAY.
        case10 = fresh(Path(td) / "case10")
        f10 = case10 / "tinybendygrad" / "uop" / "divandmod.bend"
        text10 = f10.read_text()
        old10 = """def dm_nd.pos.go(isconst: Bool, v: H.I64) -> Bool:
  match isconst:
    case True{}: Bool.not(H.i64_is_zero(v))
    case False{}: False{}"""
        new10 = """def dm_nd.pos.go(isconst: Bool, v: H.I64) -> Bool:
  match isconst:
    case True{}: False{}
    case False{}: False{}"""
        if old10 not in text10:
            bad.append("the `nested_div` arm's positive-quotient guard moved")
            print(" 10 nd positive      COULD NOT MUTATE")
        else:
            f10.write_text(text10.replace(old10, new10, 1))
            ok = not agrees(case10)
            print(f" 10 nd positive      {'RED' if ok else 'NOT RED'}  the quotient is never positive")
            if not ok:
                bad.append("breaking the `nested_div` arm's positive-quotient guard did not redden the lanes")

        # 11 -- THE `factor_remainder` ARM's CONSTANT BRANCH's **MULTIPLICATION**
        # (divandmod.py:84-85): `u.divides(c)*(c%y.val)` BECOMES A DIVISION,
        # AND THE `frc_*` ROW's TREE CHANGES.
        #
        # AND MEASURED 2026-11-25: THE FIRST DRAFT BUILT A **DIVISION** AND THE
        # PORT ANSWERED A DEEP `ADD(c0, ADD(c0, ... ADD(c0,Pb),Pb)...)` NEST
        # WHERE UPSTREAM ANSWERS
        # `ADD(DIV(ADD(ADD(ADD(c0,MUL(MUL(a,c1),c2)),b),c0),c4),ADD(c0,MUL(MUL(a,c1),c1)))`.
        case11 = fresh(Path(td) / "case11")
        f11 = case11 / "tinybendygrad" / "uop" / "divandmod.bend"
        text11 = f11.read_text()
        old11 = """      +cc = O.UOp.const(ar, O.CInt{H.i64_div(c, y)})
      O.UOp.alu(O.Found.ar(cc), O.OpsMUL{}, [O.Found.i(O.Dv.f(d)), O.Found.i(cc)])"""
        new11 = """      +cc = O.UOp.const(ar, O.CInt{H.i64_div(c, y)})
      O.UOp.alu(O.Found.ar(cc), O.OpsDIV{}, [O.Found.i(O.Dv.f(d)), O.Found.i(cc)])"""
        if old11 not in text11:
            bad.append("the `factor_remainder` constant branch's multiplication moved")
            print(" 11 fr const mul     COULD NOT MUTATE")
        else:
            f11.write_text(text11.replace(old11, new11, 1))
            ok = not agrees(case11)
            print(f" 11 fr const mul     {'RED' if ok else 'NOT RED'}  the quotient's term is a division")
            if not ok:
                bad.append("breaking the `factor_remainder` constant branch's multiplication did not redden the lanes")

        # 12 -- THE `factor_remainder` ARM's **ARENA THREADING**: THE RECORD's
        # ARENA IS THE **GROWN** ONE AND NOT THE CALLER's, BECAUSE EVERY NODE
        # IS BUILT IN **ONE CHAIN** AND NOT IN A TREE OF BRANCHES.
        #
        # AND MEASURED 2026-11-25: WITH A STALE ARENA THE `quo` LIST's INDEX
        # IS OUT OF RANGE AND READS THE ARENA's **BOTTOM NOOP NODE**, AND THE
        # PORT ANSWERED A DEEP NOOP CHAIN.  **SO THE ARENA IS LOAD-BEARING
        # AND NOT A DETAIL.**
        case12 = fresh(Path(td) / "case12")
        f12 = case12 / "tinybendygrad" / "uop" / "divandmod.bend"
        text12 = f12.read_text()
        old12 = """      Fr{O.Found.ar(r), List.append(&2, U32, Fr.quo(acc), [O.Found.i(q)]),
                       List.append(&2, U32, Fr.rem(acc), [O.Found.i(r)])}"""
        new12 = """      Fr{ar, List.append(&2, U32, Fr.quo(acc), [O.Found.i(q)]),
              List.append(&2, U32, Fr.rem(acc), [O.Found.i(r)])}"""
        if old12 not in text12:
            bad.append("the `factor_remainder` arm's arena threading moved")
            print(" 12 fr arena         COULD NOT MUTATE")
        else:
            f12.write_text(text12.replace(old12, new12, 1))
            ok = not agrees(case12)
            print(f" 12 fr arena         {'RED' if ok else 'NOT RED'}  the record's arena is stale")
            if not ok:
                bad.append("breaking the `factor_remainder` arm's arena threading did not redden the lanes")

        print(f"--plant: {'OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
        return FAIL if bad else PASS


if __name__ == "__main__":
    sys.exit(main())
