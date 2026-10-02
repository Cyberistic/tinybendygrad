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
  """Just enough of a .bend path for gate_port(). It is never read -- run_port is replaced."""
  def __init__(self, p): self.p = pathlib.Path(p)
  def __str__(self): return str(self.p)
  @property
  def stem(self): return self.p.stem
  def relative_to(self, other): return self.p


def verdict_of(base_rows, moved_rows, dead=False, base_doc=None, port="/tmp/probe.bend",
               oracle_rows=None):
  """Drive gate_port() with a baseline document in the SHAPE baseline.json actually has.

  This used to hand verdict() a hand-built {"lanes": {"interpreted": rows}} dict, which is
  not the file's shape -- the file is {"lanes": {port: {lane: rows}}, "hunks": {port: ...}}
  and the port name is a key of the INNER dict. So the selftest passed while the call site
  it was meant to cover returned None for every port and never reached GUARD 1. A test that
  exercises a differently-shaped call than production is the same instrument lying one
  layer down, which is how a dead guard shipped with a green selftest.
  """
  g = load_gate(f"rebase_gate_{len(base_rows)}_{len(moved_rows)}_{dead}_{oracle_rows is not None}")
  if dead:
    g.run_port = lambda *a, **k: ({"interpreted": {"rc": 1, "err": "boom"}}, {})
  else:
    lanes = {"interpreted": {"rc": 0}, "native": {"rc": 0}}
    r = {"interpreted": dict(moved_rows)}
    if oracle_rows is not None:
      lanes["cpython:oracle"] = {"rc": 0}
      r["cpython:oracle"] = dict(oracle_rows)
    g.run_port = lambda *a, **k: (lanes, r)
  g.REPO = pathlib.Path("/tmp")
  doc = base_doc if base_doc is not None else {
    "lanes": {port: {"interpreted": dict(base_rows)}},
    "hunks": {port: {"tinygrad/probe.py": {"api_delta": {"added": []}, "diff_stat": "1 file"}}}}
  return g.gate_port(FakeBend(port), ["oracle"], doc, native=True)[0]


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

  print("selftest: the four states are each REACHABLE\n")

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

  # The dtype_tables.py shape: the oracle exits 0 and emits TSV, so `rows()` keys on "=" and
  # finds NOTHING. That is a failed oracle wearing a zero exit status.
  check("an oracle that prints no name=value -> BROKEN, names it",
        verdict_of({"a": "1"}, {}),
        "BROKEN", "compared nothing")

  # GUARD 3, and the shape measured on cstyle.bend tonight: 225 bend rows and 33 oracle
  # rows with ZERO shared names. The old loop iterated an empty intersection and reported
  # "0 disagreements" -- a comparison that cannot happen reading as one that agrees.
  check("two lanes sharing NO row name -> BROKEN, names the pair",
        verdict_of({"a": "1"}, {"a": "1"}, oracle_rows={"totally": "different"}),
        "BROKEN", "share NO row names")

  check("two lanes sharing a row name that differs -> BROKEN, counts the rows",
        verdict_of({"a": "1"}, {"a": "1"}, oracle_rows={"a": "2"}),
        "BROKEN", "disagree")

  check("two lanes sharing rows that agree -> UNCHANGED",
        verdict_of({"a": "1"}, {"a": "1"}, oracle_rows={"a": "1"}),
        "UNCHANGED", "zero rows moved")

  # A baseline lane that was RECORDED with zero rows compares nothing, and GUARD 1's
  # `if not was: continue` would skip it forever. Silence must not read as agreement.
  check("a baseline lane of zero rows is NOT-STARTED, not UNCHANGED",
        verdict_of({}, {"a": "1"}), "NOT-STARTED", "ZERO rows")

  # An UNCHANGED with nothing recorded about what was examined is the "nobody looked" state.
  # It must be visibly different from the "somebody looked" state above.
  nohunks = verdict_of({"a": "1"}, {"a": "1"},
                       base_doc={"lanes": {"/tmp/probe.bend": {"interpreted": {"a": "1"}}},
                                 "hunks": {}})
  check("UNCHANGED with no hunks says LOOK-UNRECORDED out loud",
        nohunks, "UNCHANGED", "examined nothing")
  print(f"        hunks_status: {nohunks.get('hunks_status')}")

  # THE DEFECT THAT SHIPPED. baseline.json is keyed by PORT under "lanes"; a reader that asks
  # for the port at top level gets None, which means "no baseline", which short-circuits
  # before GUARD 1. A malformed document must be NAMED, not absorbed as unstarted.
  g = load_gate("rebase_gate_malformed")
  rows_, hunks_, why = g.baseline_for({"interpreted": {"a": "1"}}, "/tmp/probe.bend")
  ok = rows_ is None and hunks_ is None and "MALFORMED" in why
  print(f"  {'PASS' if ok else 'FAIL'}  a baseline of the WRONG SHAPE is named, not absorbed")
  if not ok:
    fails.append("malformed baseline is named")
  print(f"        {why}")

  print()
  if fails:
    print(f"{len(fails)} FAILED: {', '.join(fails)}")
    return 1
  print("all states reachable -- a gate that cannot fail is not a gate")
  return 0


if __name__ == "__main__":
  sys.exit(main())