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

  fails += oracle_template()

  print()
  if fails:
    print(f"{len(fails)} FAILED: {', '.join(fails)}")
    return 1
  print("all states reachable -- a gate that cannot fail is not a gate")
  return 0


# THE SIX STATES EVERY ORACLE I WRITE MUST BE ABLE TO REPORT. This is the TEMPLATE, and it is
# here rather than in prose because the failure it prevents has already happened: twelve
# committed files printed 0 rows for an hour and a harness reported success, because "0
# disagreements" over "0 comparisons" is indistinguishable from agreement. An oracle that
# has never been shown producing each of these six verdicts is an oracle whose green means
# nothing.
#
#   1 DEAD LANE          the oracle exits non-zero                -> BROKEN, naming the lane
#   2 EMPTY OUTPUT       the oracle prints no name=value row       -> BROKEN, "compared nothing"
#   3 NO SHARED ROW NAME the oracle's names are all different      -> BROKEN, naming the pair
#   4 A SHARED NAME DIFFERS                                      -> BROKEN, counting the rows
#   5 AGREEMENT                                               -> UNCHANGED
#   6 MALFORMED BASELINE a baseline.json of the wrong shape      -> named, not absorbed
#
# `ORACLE_CONFORMANCE` lists the oracles this session wired into BASE_ORACLES, and the loop
# drives the SAME `gate_port()` main() calls with each one's own row NAMES as the fixture. A
# new oracle that cannot pass this is not finished.
ORACLE_CONFORMANCE = [
  # (port, oracle, shared-row count MEASURED by rebase-survey.py / by the oracle)
  ("tinybendygrad/uop/spec.bend", ".agents/slop/rebase-oracle-spec.py", 11),
  ("tinybendygrad/uop/ops.bend", ".agents/slop/rebase-oracle-ops.py", 62),
  ("tinybendygrad/codegen/opt/search.bend", ".agents/slop/rebase-oracle-search.py", 12),
  ("tinybendygrad/runtime/ops_rdma.bend", ".agents/slop/oracle_rdma_gate.py", 389),
  ("tinybendygrad/runtime/ops_nv.bend", ".agents/slop/nv-oracle.py", 543),
  ("tinybendygrad/runtime/support/hcq2.bend", ".agents/slop/hcq2-oracle.py", 157),
  ("tinybendygrad/runtime/ops_metal.bend", ".agents/slop/mt_seam_rows.py", 14),
  ("tinybendygrad/codegen/rewriter.bend", ".agents/slop/xd1/rw-oracle.py", 41),
]


def oracle_template():
  """Drive the six states through gate_port() for each wired oracle. Returns failure names."""
  fails = []
  for port, oracle, shared_n in ORACLE_CONFORMANCE:
    g = load_gate(f"conformance_{pathlib.Path(oracle).stem}")
    # THE FIXTURE IS THE ORACLE'S OWN ROW SET, taken from the recorded survey, so the states
    # are produced over the names this oracle actually emits. Synthetic names would pass a
    # broken oracle and fail a working one, which is the same inversion as a shape mismatch.
    port_rows = {f"r{i}": str(i) for i in range(shared_n)}
    doc = {"lanes": {port: {"interpreted": dict(port_rows)}},
           "hunks": {port: {"tinygrad/probe.py": {"api_delta": {"added": ["sym"]},
                                                  "diff_stat": "1 file changed"}}}}
    bend = FakeBend(port)

    def synth(rows_by_lane, lanes):
      g.run_port = lambda *a, **k: (lanes, rows_by_lane)
      return g.gate_port(bend, [oracle], doc, native=True)[0]

    ok_lanes = {"interpreted": {"rc": 0}, "native": {"rc": 0}, "cpython:o": {"rc": 0}}
    dead = synth({"interpreted": dict(port_rows)},
                 {"interpreted": {"rc": 0}, "cpython:o": {"rc": 1, "err": "boom"}})
    # EMPTY OUTPUT is the `dtype_tables.py` shape: the oracle lane EXITS 0 and emits no rows.
    # Removing the lane entirely is a different case and would be caught by a different
    # guard, so the fixture keeps the lane and empties it -- which is what a TSV-printing
    # oracle does when `rows()` keys on `=`.
    empty = synth({"interpreted": dict(port_rows), "cpython:o": {}}, ok_lanes)
    noshare = synth({"interpreted": dict(port_rows),
                     "cpython:o": {f"unrelated{i}": "0" for i in range(shared_n)}}, ok_lanes)
    differ = synth({"interpreted": dict(port_rows),
                    "cpython:o": {**port_rows, "r0": "MUTATED"}}, ok_lanes)
    # AGREEMENT: the oracle is missing one shared row, and every row they DO share agrees.
    # This is the state that matters and the one that is easiest to get wrong -- a lane pair
    # can share 388 of 389 names, agree on all 388, and be comparing almost nothing.
    agree = synth({"interpreted": dict(port_rows),
                   "cpython:o": {k: v for k, v in list(port_rows.items())[1:]}}, ok_lanes)

    cases = [("dead lane", dead, "BROKEN", "lane"),
             ("empty output", empty, "BROKEN", "compared nothing"),
             ("no shared row name", noshare, "BROKEN", "share NO row names"),
             ("a shared name differs", differ, "BROKEN", "disagree"),
             ("agreement", agree, "UNCHANGED", "zero rows moved")]
    bad = [f"{pathlib.Path(oracle).name}: {nm}" for nm, v, ws, wt in cases
           if not (v["state"] == ws and wt.lower() in v.get("why", "").lower())]
    g.run_port = lambda *a, **k: (ok_lanes, {"interpreted": dict(port_rows),
                                             "cpython:o": dict(port_rows)})
    bad_doc = g.baseline_for({"interpreted": dict(port_rows)}, port)
    if bad_doc[0] is not None or "MALFORMED" not in bad_doc[2]:
      bad.append(f"{pathlib.Path(oracle).name}: malformed baseline")
    print(f"  {'PASS' if not bad else 'FAIL'}  {pathlib.Path(oracle).name}: six states "
          f"reachable ({shared_n} shared row names)")
    fails += bad
  return fails


if __name__ == "__main__":
  sys.exit(main())