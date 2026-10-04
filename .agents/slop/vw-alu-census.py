#!/usr/bin/env python3
"""vw-alu-census.py -- WHICH OPS REACH A `k`-TAG LADDER ARM THEY ARE NOT NAMED IN.

THE DEFECT CLASS, in the port's own words. `ren_9.b2.mk`'s LAST arm is FLOORMOD and
`ren_10.mk`'s LAST arm is CMPEQ, so an unrecognised `k` silently becomes a DIFFERENT operation's
term instead of an error. `Ops.MAX` took exactly that route and was rendered
`a - floordiv(a,b)*b` for two unit-generations; `dv_max` is the row that caught it, and
`ren_t9` -- a MEMBERSHIP test against `z3_alu_ops()` rather than a tag ladder -- is the fix.

So the question is not "did MAX happen" but "CAN any op reach an unnamed arm", and a count of
the ones that did is not an answer. This asks it four ways, and every line carries its
DENOMINATOR, because `11 of 11` and `11 of 12` read alike and mean opposite things:

    Q1  every key of `z3_alu` is NAMED in `ren_9.go`             denominator len(z3_alu) = 11
    Q2  every op rule 10 can claim is NAMED in `ren_10.go`       denominator 8 int `python_alu`
    Q3  rule 10's DEFAULT is a violation and not a term          the honest-default test
    Q4  rule 9's DEFAULT is `ren_9.w3` -- a WHERE -- so it is only safe because `ren_t9` is a
        MEMBERSHIP test. The count of keys `ren_t9` claims and `ren_9.go` does not NAME is the
        count of ops that would silently become a WHERE, and it MUST be empty.

`ren_t9` and `ren_t10` are read out of `uop/validate.bend` BY PARSING, because the ladder is a
`match` and a `match` has no reflection. What is parsed is the ARM NAMES, and the arm COUNT is
printed next to them, so a parse miss shows up as `11 names over 12 arms` rather than as a
silently shorter table.

    DEV=NULL python3 .agents/slop/vw-alu-census.py
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))

from tinygrad.uop.ops import Ops, python_alu  # noqa: E402
from tinygrad.uop.validate import z3_alu  # noqa: E402

PORT = pathlib.Path(__file__).resolve().parents[2] / "tinybendygrad/uop/validate.bend"

# `python_alu`'s INTEGER ops. CPython's rule 10 is `UPat(GroupOp.ALU)` MINUS `tuple(z3_alu)`,
# and `GroupOp.ALU` also holds the float ops -- which `validate.py:83`'s gate makes unreachable
# because it drops every float-dtype node. So "claimable" is the 8, and the float remainder is
# REPORTED rather than assumed away.
CLAIMABLE10 = {"ADD", "SUB", "MUL", "CMPLT", "CMPNE", "CMPEQ", "NEG", "MULACC"}


def body(defname, src):
  """One def's source text, or None. A `match` has no reflection, so this is TEXT -- and the
  failure mode of text is a table that is quietly SHORTER than the file, so `arms` below always
  prints the arm COUNT beside the names it found."""
  m = re.search(rf"^def {re.escape(defname)}\(.*?\n(.*?)\n\ndef ", src, re.M | re.S)
  return None if m is None else m.group(1)


def arms(defname, src):
  b = body(defname, src)
  if b is None:
    return set(), 0
  # `O.OpsAND` -> `AND`: the port spells the op `Ops<NAME>` and CPython `<NAME>`.
  return {a[len("O.Ops"):] for a in re.findall(r"case (O\.Ops\w+)\{\}", b)}, \
         len(re.findall(r"^\s*case ", b, re.M))


def main():
  src = PORT.read_text()
  ren9, ren9_arms = arms("ren_9.go", src)
  ren10, ren10_arms = arms("ren_10.go", src)
  alu = {o.name for o in z3_alu}
  palu = {o.name for o in python_alu}

  print(f"n_Ops={len(list(Ops))} n_z3_alu={len(alu)} n_python_alu={len(palu)}")
  print(f"Q1 ren_9 names={len(ren9)} over {ren9_arms} arms")
  print(f"Q1 missing={','.join(sorted(alu - ren9)) or '-'} extra={','.join(sorted(ren9 - alu)) or '-'}")
  print(f"Q2 ren_10 names={len(ren10)} over {ren10_arms} arms")
  print(f"Q2 missing_claimable={','.join(sorted(CLAIMABLE10 - ren10)) or '-'}")
  # the float ALU ops: unreachable through the gate, and a violation rather than a term here
  print(f"Q2 float_alu_unnamed={','.join(sorted(palu - CLAIMABLE10 - alu - ren10)) or '-'}")
  print(f"Q3 ren_10_default_is_violation={'zat.miss' in (body('ren_10.go', src) or '')}")
  print(f"Q4 ren_9_default_is_wHERE={'case _: ren_9.w3' in (body('ren_9.go', src) or '')}")
  print(f"Q4 silent_where_arms={','.join(sorted(alu - ren9)) or '-'} (must be empty)")
  print(f"Q5 rt_first default tag=10 -> ren_unsup: "
        f"{'case Nil{}: 10' in src} and "
        f"{bool(re.search(r'def ren_dispatch.go.*?case _: ren_unsup', src, re.S))}")

  # THE ONLY LOUD-DEFAULT FAILURE LEFT: a `k` the ladder does not know. Both `.mk` builders end
  # in a TERM arm, so an unknown `k` is a silent mistranslation rather than an error. The fix is
  # structural -- `ren_9.go` and `ren_10.go` name every op their rule can be handed -- and Q1/Q2
  # are that fix's census.
  # Q7, and it is the SHARPEST statement of the residual risk: the last arm of each `k` ladder
  # is not an unreachable default, it is a LIVE arm for a real key -- `Ops.FLOORMOD` arrives as
  # `k = 3` and `ren_9.b2.mk` never tests `3`, it FALLS to the last arm. So an unknown `k` does
  # not produce a visibly wrong term, it produces FLOORMOD's, which is why `Ops.MAX` was
  # invisible. Both sets are read out of the file rather than remembered.
  k9 = {int(x) for x in re.findall(r"U32\.is_eq\(k, (\d)\)", body("ren_9.b2.mk", src) or "")}
  k10 = {int(x) for x in re.findall(r"U32\.is_eq\(k, (\d)\)", body("ren_10.mk", src) or "")}
  p9 = {int(x) for x in re.findall(r"ren_9\.b2\((\d)", body("ren_9.go", src) or "")}
  p10 = {int(x) for x in re.findall(r"ren_10\.b[23]\((\d)", body("ren_10.go", src) or "")}
  print(f"Q7 ren_9.b2.mk tests k={sorted(k9)} over {len(p9)} passed k={sorted(p9)} "
        f"untested_passed={sorted(p9 - k9)} (falls to the FLOORMOD arm)")
  print(f"Q7 ren_10.mk  tests k={sorted(k10)} over {len(p10)} passed k={sorted(p10)} "
        f"untested_passed={sorted(p10 - k10)} (falls to the CMPEQ arm)")
  return 1 if (alu - ren9) or (CLAIMABLE10 - ren10) else 0


if __name__ == "__main__":
  sys.exit(main())