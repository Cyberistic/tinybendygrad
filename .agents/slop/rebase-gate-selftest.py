#!/usr/bin/env python3
"""rebase-gate-selftest.py -- prove the gate can SEE the state it exists to catch.

WHY THIS IS A FILE AND NOT A CONVENIENCE. The failure this gate exists for is INVISIBLE BY
CONSTRUCTION: twelve committed files printed 0 rows and a harness reported success, because
zero disagreements and zero comparisons look identical. A detector that has never been shown
failing is indistinguishable from a detector that cannot fail. So each state is produced on
purpose and the gate is required to name it.

THE THREE STATES, AND WHAT MAKES EACH ONE REACHABLE:
  UNCHANGED  no row value differs from the baseline, and no row was lost
  RE-PORTED  a row value moved, and the moved rows now agree with CPython
  BROKEN     rows went to ZERO, or a lane died, or rows disagree

The tests run against SYNTHETIC ports and a synthetic baseline in a temp tree. They do not
touch tinygrad/, do not touch any .bend file, and do not touch the real baseline.json.

    python3 .agents/slop/rebase-gate-selftest.py
"""
import json, pathlib, shutil, subprocess, sys, tempfile

HERE = pathlib.Path(__file__).resolve().parent
GATE = HERE / "rebase-gate.py"


def load_gate(name):
  """Import rebase-gate.py under a private name. The gate is loaded, never restated: a
  test that re-implements the rule under test is testing the test."""
  import importlib.util
  spec = importlib.util.spec_from_file_location(name, GATE)
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


class FakeBend:
  """Just enough of a .bend path for verdict(). It is never read -- run_port is replaced."""
  def __init__(self, p): self.p = pathlib.Path(p)
  def __str__(self): return str(self.p)
  @property
  def stem(self): return self.p.stem
  def relative_to(self, other): return self.p


def verdict_of(base_rows, moved_rows, dead=False):
  g = load_gate(f"rebase_gate_{len(base_rows)}_{len(moved_rows)}_{dead}")
  if dead:
    g.run_port = lambda *a, **k: ({"interpreted": {"rc": 1, "err": "boom"}}, {})
  else:
    g.run_port = lambda *a, **k: ({"interpreted": {"rc": 0}, "native": {"rc": 0}},
                                  {"interpreted": dict(moved_rows)})
  g.REPO = pathlib.Path("/tmp")
  base = {"lanes": {"interpreted": base_rows}}
  return g.verdict(FakeBend("/tmp/probe.bend"), ["oracle"], base, native=True)[0]


def main():
  fails = []

  def check(name, got, want_state, want_substr=None):
    ok = got["state"] == want_state
    if ok and want_substr:
      ok = want_substr.lower() in got.get("why", "").lower()
    print(f"  {'PASS' if ok else 'FAIL'}  {name}")
    if not ok:
      print(f"        wanted {want_state}"
            + (f" containing {want_substr!r}" if want_substr else "")
            + f", got {got['state']}: {got.get('why')}")
      fails.append(name)

  print("selftest: the three states are each REACHABLE\n")

  check("no row moved -> UNCHANGED, names the hunks",
        verdict_of({"a": "1", "b": "2"}, {"a": "1", "b": "2"}),
        "UNCHANGED", "zero rows moved")

  check("a row moved and agrees -> RE-PORTED",
        verdict_of({"a": "1", "b": "2"}, {"a": "1", "b": "NEW"}),
        "RE-PORTED", "moved")

  # THE CASE THAT WENT UNNOTICED FOR AN HOUR. Baseline had rows; the run produced none.
  # A purely relative "did any row move?" check reports success here. This one must not.
  check("rows LOST -> BROKEN",
        verdict_of({"a": "1", "b": "2", "c": "3"}, {"a": "1", "b": "2"}),
        "BROKEN", "LOST ROWS")

  # the exact shape of the incident: 210 rows -> 0, with no exception anywhere
  check("210 rows -> 0 -> BROKEN, says TO ZERO",
        verdict_of({f"r{i}": str(i) for i in range(210)}, {}),
        "BROKEN", "TO ZERO")

  # a lane that raises is a failed lane, never a pass
  check("a dead lane -> BROKEN, not an empty success",
        verdict_of({"a": "1"}, {}, dead=True),
        "BROKEN", "lane")

  print()
  if fails:
    print(f"{len(fails)} FAILED: {', '.join(fails)}")
    return 1
  print("all states reachable -- a gate that cannot fail is not a gate")
  return 0


if __name__ == "__main__":
  sys.exit(main())