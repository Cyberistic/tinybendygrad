#!/usr/bin/env python3
"""multi-controls.py -- THE CONTROLS. A harness that has only ever printed "clean" has not
been shown to work, and the whole point of this lane is that a red lane must be RED.

Five controls, each of which must FAIL or PASS for the stated reason. They drive
multi-correspond.py's OWN report() through StringIO rather than re-implementing the check --
a control that re-implements the check is not a control -- and every fixture is built to
DISAGREE unless the control says otherwise.

  C1 NEGATIVE  one planted value disagreement on a shared fixture -> the harness NAMES it
  C2 NEGATIVE  the same fixture with the plant removed            -> clean again
  C3 READING   rows() still reads 213 rows out of the real F3 oracle text
  C4 READING   a planted F1 disagreement is seen by the same reader
  C5 SELF      a SECOND, structurally different plant is caught -- so C1 is not the only
               shape that can go red

Run: .venv/bin/python .agents/slop/multi-controls.py
"""
import contextlib
import io
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO))
sys.path.insert(0, str(HERE))

import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location("mc", HERE / "multi-correspond.py")
MC = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(MC)

FAILS = []


def check(name, ok, why):
  print(f"  {'PASS' if ok else 'FAIL'}  {name}\n        {why}")
  if not ok:
    FAILS.append(name)


def run_report(oracle, port):
  buf = io.StringIO()
  with contextlib.redirect_stdout(buf):
    _, bad, checked = MC.report("CONTROL", oracle, port)
  return bad, checked, buf.getvalue()


def main():
  bodies = MC.port_bodies()
  print(f"port rows read from multi.bend: {len(bodies)}")

  # ---- C1: plant a value disagreement on a REAL shared fixture. `bx_none` is
  # (2,3)->(2,3), CPython's value is `()`, and the port's own assertion is `bx_n == 0`.
  # The plant makes the port assert `bx_n == 1`, which `()` contradicts.
  print("\nC1  NEGATIVE -- one planted disagreement on a shared fixture")
  orc = {(2, 3): ("bx_none", ())}
  port = {(2, 3): [("bx_none", "eq(bx_n(mu_baxes(s2(2, 3), s2(2, 3))), 1)")]}
  bad, checked, _ = run_report(orc, port)
  check("C1a the harness NAMES the planted row", len(bad) == 1 and bad[0][1] == "bx_none",
        f"INCONSISTENT={bad}")
  check("C1b the denominator is reported alongside", checked == 1, f"checked={checked} of 1")
  check("C1c rc is non-zero", len(bad) > 0, f"len(bad)={len(bad)} -> rc=1")

  # ---- C2: remove the plant. Same fixture, the port's own assertion. Must be clean.
  print("\nC2  NEGATIVE -- the same fixture with the plant removed")
  port_ok = {(2, 3): [("bx_none", "eq(bx_n(mu_baxes(s2(2, 3), s2(2, 3))), 0)")]}
  bad2, checked2, _ = run_report(orc, port_ok)
  check("C2a reports clean", not bad2, f"INCONSISTENT={bad2}")
  check("C2b the row was still CHECKED, not skipped to green", checked2 == 1,
        f"checked={checked2}")

  # ---- C3: the REAL F3 oracle text must still read 213 rows through rows().
  print("\nC3  READING -- the real oracle's 213 rows are readable")
  mr = MC.load("mr_ctl", "multi-rows.py")
  buf = io.StringIO()
  with contextlib.redirect_stdout(buf):
    mr.main()
  got = len(MC.rgm.rows(buf.getvalue()))
  check("C3a rows() reads 213", got == 213, f"got {got} of 213 lines")

  # ---- C4: a planted disagreement IN THE F1 shape, seen by the SAME reader.
  print("\nC4  READING -- a planted F1 disagreement is seen by the same reader")
  rows = MC.rgm.rows("bx_none=(0,)\nbx_pad=(0,)\n")
  check("C4a both planted rows read", set(rows) == {"bx_none", "bx_pad"}, f"got {sorted(rows)}")
  check("C4b the value is the planted one", rows.get("bx_none") == "(0,)",
        f"bx_none -> {rows.get('bx_none')!r}")

  # ---- C5: a SECOND, structurally DIFFERENT plant must also go red. `rs_rev` over
  # arg_acc=[1,4,24] -- the port claims the count is 1 while CPython's is 3. If only C1's
  # shape can fail, C1 is a coincidence and not a check.
  print("\nC5  SELF -- a second, structurally different plant is caught")
  bad3, checked3, _ = run_report({(4, 6): ("t_a", (1, 4, 24))},
                                 {(4, 6): [("t_a", "eq(mu_len(rs_rev(rs_acc([4, 6])), 1)")]})
  check("C5a a count claim over a 3-tuple is INCONSISTENT", len(bad3) == 1,
        f"INCONSISTENT={bad3} (len=3 vs asserted 1)")
  bad4, _, _ = run_report({(4, 6): ("t_a", (1,))},
                          {(4, 6): [("t_a", "eq(mu_len(rs_rev(rs_acc([4, 6])), 1)")]})
  check("C5b the matching fixture with the same claim is consistent", not bad4,
        f"CPython len==1 and the port asserts ==1 -> INCONSISTENT={bad4}")

  print(f"\n{'ALL CONTROLS PASS' if not FAILS else 'CONTROL FAILURES: ' + str(FAILS)}")
  return 1 if FAILS else 0


if __name__ == "__main__":
  raise SystemExit(main())
