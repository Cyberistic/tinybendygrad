#!/usr/bin/env python3
"""gate-roster-arith.py -- can the QUOTED tally be produced by the file on disk?

A tally is a set of CLAIMS about which port landed in which bucket, and those claims are
checkable against the wiring without running a single lane. A BROKEN count of 4 with a named
list of 4 is only consistent with a roster in which all four are wired; if one of them is not
wired, the tally was produced by a DIFFERENT FILE and every number in it is a number about
that file.

The gate's own functions supply the roster (BASE_ORACLES) and the recorded set
(baseline_for), so nothing here is transcribed:

    .venv/bin/python .agents/slop/gate-roster-arith.py [--gate PATH]

`--gate PATH` reads a gate from somewhere other than the working copy, which is how the
committed version is checked WITHOUT checking it out over another agent's edits.
"""
import argparse, importlib.util, json, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent


def load_gate(path):
  spec = importlib.util.spec_from_file_location("roster_gate", path)
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--gate", default=str(HERE / "rebase-gate.py"))
  a = ap.parse_args()
  g = load_gate(a.gate)
  base = json.loads((HERE / "rebase" / "baseline.json").read_text())

  wired = {p: o for p, o in g.BASE_ORACLES.items() if (REPO / p).exists()}
  wired_missing = [p for p in g.BASE_ORACLES if not (REPO / p).exists()]
  recorded = set((base.get("lanes") or {}))
  print(f"gate read from : {a.gate}")
  print(f"BASE_ORACLES   : {len(g.BASE_ORACLES)} entries, {len(wired)} of them on disk")
  if wired_missing:
    print(f"  wired but NO .bend on disk: {wired_missing}")
  print(f"baseline.json  : {len(recorded)} recorded ports")
  print()

  rec_and_wired = sorted(recorded & set(wired))
  rec_not_wired = sorted(recorded - set(wired))
  wire_not_rec = sorted(set(wired) - recorded)
  print(f"recorded AND wired   ({len(rec_and_wired)}): a healthy lane here reads UNCHANGED "
        f"or RE-PORTED")
  print(f"recorded NOT wired   ({len(rec_not_wired)}): {rec_not_wired}")
  print(f"wired NOT recorded   ({len(wire_not_rec)}): a clean lane here reads AGREE-UNRECORDED")
  for p in wire_not_rec:
    print(f"    {p}  -> {g.BASE_ORACLES[p]}")
  print()

  # The two BROKEN entries this roster makes STRUCTURALLY reachable before any lane runs.
  structural = []
  for p in sorted(g.BASE_ORACLES):
    o = g.BASE_ORACLES[p]
    if not o:
      continue
    if any("dtype_tables" in s or "renderer_oracle" in s for s in o):
      structural.append(p)
  print(f"wired to a lane known to compare nothing (dtype_tables TSV / renderer_oracle cstyle): "
        f"{structural}")
  print()

  QUOTED = {"UNCHANGED": 28, "RE-PORTED": 1, "BROKEN": 4,
            "AGREE-UNRECORDED": 6, "NOT-STARTED": 11}
  print("the tally quoted in .agents/TODO.md:4588, checked against THIS roster")
  print(f"  quoted total = {sum(QUOTED.values())} over 'the same 50 targets'")
  not_started = 50 - len(set(g.BASE_ORACLES) | recorded)
  print(f"  ports this roster knows about = {len(set(g.BASE_ORACLES) | recorded)} "
        f"(wired {len(g.BASE_ORACLES)} + recorded-only {len(rec_not_wired)}, minus overlap)")
  print(f"  so NOT-STARTED is pinned at {not_started} by the roster, whatever the lanes do -- "
        f"quoted {QUOTED['NOT-STARTED']}")
  if not_started != QUOTED["NOT-STARTED"]:
    print(f"  !! MISMATCH: this roster cannot produce NOT-STARTED={QUOTED['NOT-STARTED']}; "
          f"it pins {not_started}. The quoted tally came from a different target list.")
  print()
  print("  the BROKEN names, against this roster's wiring:")
  for p in ["tinybendygrad/dtype.bend", "tinybendygrad/codegen/decomp/dtype.bend",
            "tinybendygrad/renderer/cstyle.bend", "tinybendygrad/device.bend"]:
    wired_p = p in g.BASE_ORACLES
    print(f"    {p:<44} wired={wired_p}"
          + ("" if wired_p else "   -> never_wired() returns NOT-STARTED; BROKEN is UNREACHABLE"))
  return 0


if __name__ == "__main__":
  sys.exit(main())