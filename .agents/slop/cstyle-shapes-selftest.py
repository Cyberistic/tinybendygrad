#!/usr/bin/env python3
"""cstyle-shapes-selftest.py -- ONE CONTROL PER ROW SHAPE, and each one shown ARMED and RED.

    python3 .agents/slop/cstyle-shapes-selftest.py

THE THREE SHAPES, and why a control per shape rather than one control:

    F1  name=value                     the plain form. `rebase-gate.py:rows()` splits at the
                                       FIRST `=` and, with no `py=` tail, returns it as both
                                       columns.
    F2  name = [v]   py=[w]            the port's form. `rows()` folds the `py=` tail away and
                                       returns `left` -- the producer's OWN answer.
    F3  name<SP><SP>value              the name-less-`=` form. Only reachable by `rows()`;
                                       `cstyle-gate.py`'s `rows_strict` demands ` = [` and a
                                       closing `]`, so it cannot read F3 at all. MEASURED and
                                       printed below rather than asserted here.

WHY "ARMED" IS HALF OF EACH CONTROL. A control that only shows red proves nothing: it is
indistinguishable from a control that is permanently red for an unrelated reason, and this
project has already paid for three that were DISARMED -- one leaving six lanes green while
disarmed because the plant landed in the `py=` column while the reader compares `left`. So each
shape runs three lanes:

    ARMED   both lanes' COMPARED column identical        -> must be agreement, and the count
                                                          carries its denominator
    RED     the compared column differs by one character -> must be named as a disagreement
    DISARM  only the NON-compared `py=` column differs   -> must be agreement, because `left` is
                                                          what the gate compares. F2 only; F1 and
                                                          F3 have no second column.

A DISARM that comes back RED is not a failure -- it would mean the plant is not landing in the
column the reader compares -- so it is reported as such and counted separately.

ROW NAMES CARRY SPACES AND NO `=` -- EXCEPT ON F3, WHERE SPACES ARE ILLEGAL, and that is not a
special case in this harness, it is the shared reader's rule: `rebase-gate.py:row()`'s F3 arm
returns None unless `len(head.split()) == 1`, because a prose line carries two spaces and would
otherwise manufacture a row name out of its first clause. So there are TWO control names, one
per name-space, and the F3 control uses the single-token one. A control that ignored this
reported `AGREE` on F3 over ZERO shared rows, which is GUARD 1's failure mode wearing a pass.

An ARMED case over ZERO shared rows is NOT A PASS and this harness fails it. "compared nothing"
and "compared 221 things" print identical bytes otherwise.

EVERY CASE RUNS TWICE and the two answers are compared, because a control that is run once is
a control whose determinism is an assumption.
"""
import importlib.util, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent

# THE CONTROL ROW NAMES. Spaces, and no `=`, so both readers key on them identically -- and
# F3's is a single TOKEN because `rows()` refuses a multi-token F3 name outright.
NAME = "ctl OPENCL sz1 k0"
NAME3 = "ctlf3"


def load(name):
  spec = importlib.util.spec_from_file_location(name, str(HERE / f"{name}.py"))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


RG, CG = load("rebase-gate"), load("cstyle-gate")

# (shape, name, port lane line, oracle lane line with the COMPARED column identical,
#  port lane line with the COMPARED column planted, oracle lane line for the DISARM case)
# `PORTED` is the producer's own answer; `WANT` is the oracle's. The plant changes ONE
# character in the producer's own answer, which is the column a gate can falsify.
SHAPES = (
  ("F1  name=value", NAME,
   f"{NAME}=half",
   f"{NAME}=half",
   f"{NAME}=halG",
   None),
  ("F2  name = [v]   py=[w]", NAME,
   f"{NAME} = [half]   py=[half]",
   f"{NAME} = [half]",
   f"{NAME} = [halG]   py=[half]",
   (f"{NAME} = [half]   py=[halG]", f"{NAME} = [half]")),
  ("F3  name<SP><SP>value  (single-token name only)", NAME3,
   f"{NAME3}  half",
   f"{NAME3}  half",
   f"{NAME3}  halG",
   None),
)


def read_pair(port_line, oracle_line):
  """The disagreement SET over the rows the two lanes SHARE, by CALLING the reader. Both the
  name set and the value are taken from `rebase-gate.py:rows()` -- the one reader -- so a
  disagreement here is the reader's, not a harness's."""
  p, o = RG.rows(port_line), RG.rows(oracle_line)
  shared = sorted(set(p) & set(o))
  bad = [n for n in shared if p[n] != o[n]]
  return shared, bad, p, o


def show(label, port_line, oracle_line, want_bad):
  shared, bad, p, o = read_pair(port_line, oracle_line)
  # GUARD 1, LOCALLY. A lane pair that shares NO row name compared nothing, and an ARMED case
  # over nothing is indistinguishable from a pass until the count is required to be non-zero.
  wired = bool(shared)
  ok = bool(bad) == want_bad and (wired or want_bad is None)
  # TWICE. A control run once is a control whose determinism is an assumption.
  shared2, bad2, _, _ = read_pair(port_line, oracle_line)
  stable = (shared, bad) == (shared2, bad2)
  print(f"  {label:<7} shared={shared}  disagree={bad}  "
        f"{'RED ' if bad else 'AGREE'}  expected={'RED' if want_bad else 'AGREE'}  "
        f"{'OK' if ok and stable else '*** CONTROL FAILED ***'}"
        + ("" if stable else "  *** NON-DETERMINISTIC ***")
        + ("" if wired else "  *** LANES SHARE NO ROW NAME: compared NOTHING, not a pass ***"))
  if want_bad and bad:
    n = bad[0]
    print(f"          row `{n}`  port left={p[n]!r}  cpy left={o[n]!r}")
  return ok and stable and wired


def main():
  print(f"control row names: {NAME!r} (spaces, no '=')   {NAME3!r} (F3: single token only)")
  fails = 0

  for shape, name, pline, oline, bad_pline, disarm in SHAPES:
    print(f"\n{shape}")
    print(f"  port lane   {pline!r}")
    print(f"  oracle lane {oline!r}")
    fails += not show("ARMED", pline, oline, want_bad=False)
    fails += not show("RED", bad_pline, oline, want_bad=True)
    if disarm:
      d_pline, d_oline = disarm
      print(f"  DISARM case -- the plant is in the NON-COMPARED `py=` column only:")
      print(f"  port lane   {d_pline!r}")
      fails += not show("DISARM", d_pline, d_oline, want_bad=False)

  # ---- AND THE REAL INSTRUMENT, over the real lanes, on a REAL row. A control that only ever
  # runs on synthetic text proves the reader is alive, not that the gate is.
  port = (REPO / ".agents/slop/blobrows/CURRENT/tinybendygrad__renderer__cstyle.bend.txt").read_text()
  orc = (REPO / ".agents/slop/cstyle-parity/oracle.txt").read_text()
  print("\nREAL LANES, through cstyle-gate.py's own judge(), one real F2 row at a time")
  base = CG.judge(port, orc, None, exclusions=CG.EXCLUDED)
  row = "tmap OPENCL"
  for label, mutate, want in (("clean", lambda t: t, False),
                              ("RED", lambda t: t.replace("uchar", "ucHar", 1), True)):
    txt = mutate(port)
    res = CG.judge(txt, orc, None, exclusions=CG.EXCLUDED)
    hit = [d[0] for d in res["disagree"]]
    ok = (bool(hit) == want) and (not res["bad"] if not want else bool(res["bad"]))
    fails += not ok
    print(f"  {label:<5} gated={len(res['gated'])} agree={len(res['agree'])} "
          f"disagree={len(res['disagree'])} {hit[:4] or 'none'}  "
          f"{'OK' if ok else '*** CONTROL FAILED ***'}")
  print(f"  (the row is `{row}`; the plant swaps ONE character of the port's own answer, and "
        f"the unchanged lane agrees {len(base['agree'])}/{len(base['gated'])} gated rows)")

  # ---- WHAT EACH OF cstyle-gate.py's TWO READERS CAN REACH, measured over all three shapes.
  # Not asserted: `judge()` reads through `rows_strict`, and whether F3 is reachable at all is
  # a fact about this tree, not a promise about it.
  print("\nREADER REACH over the three shapes (rows_strict is judge()'s reader; rows() is the "
        "shared one)")
  for shape, name, pline, oline, _, _ in SHAPES:
    sr = name in CG.rows_strict(pline)[0]
    rr = name in RG.rows(oline)
    print(f"  {shape:<48} cstyle rows_strict sees the row: {str(sr):<5}   "
          f"rebase-gate rows() sees the row: {rr}")
  print("  -> `cstyle-gate.py`'s judge() CANNOT READ F3. It is not degraded on F3; it reads "
        "zero\n     rows there, which its own GUARD 1 would refuse as an empty lane.")

  print(f"\n{'SELFTEST OK' if not fails else f'SELFTEST FAILED: {fails} case(s)'}: one control "
        f"per shape, each shown ARMED and RED, each run twice")
  return 1 if fails else 0


if __name__ == "__main__":
  sys.exit(main())