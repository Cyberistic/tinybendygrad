#!/usr/bin/env python3
"""gate-at-rev.py -- run a REVISION of rebase-gate.py without checking it out.

THE QUESTION THIS ANSWERS. Two numbers disagree about `device.bend`, and one of them came
from a whole-tree sweep while the other came from a `--port` run. If the two numbers came
from DIFFERENT VERSIONS of rebase-gate.py then there is no contradiction to explain: the
files have different rosters, so they have different reachable verdicts.

`rebase-gate.py` derives its REPO from `Path(__file__).resolve().parents[2]`, so a copy in a
scratch directory computes a REPO that does not exist and every port reads NO SUCH FILE --
which is NOT-STARTED for all of them and would look like a clean result rather than a broken
measurement. So the revision is MATERIALISED IN PLACE, read-only, and imported:

    the file is written to <repo>/.agents/slop/rebase-gate-<rev>.py, loaded under a private
    module name, and DELETED in a finally block.

  * in place, so `__file__` resolves and parents[2] IS the repo -- the lanes run against the
    real tree with no patching of it;
  * under a private name, so it cannot be confused with the live gate;
  * deleted in `finally`, so a kill cannot leave a second gate wired into the tree. The
    earlier version of this harness used `BASE_ORACLES` in-place mutation for exactly this
    reason and rebase-gate.py's own header records the outcome: "that is patching the live
    tree from a harness -- and a kill inside that window leaves the tree wired to a script
    that has been deleted."

IT CALLS gate_port(), the same decision function main() calls. What it does NOT cover is
main()'s TARGET CONSTRUCTION, which is a fixed roster in BASE_ORACLES rather than a
per-invocation input, and rebase-gate-selftest.py's plan_contract() covers the plan half.

  usage: .venv/bin/python .agents/slop/gate-at-rev.py -r @- [--port P] [--reps N]
"""
import argparse, importlib.util, json, os, pathlib, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
STAGE = HERE / "rebase-gate-REV.py"  # never exists except during a run; asserted below


def export(rev):
  """rebase-gate.py at `rev`, staged in .agents/slop so parents[2] is the repo."""
  assert not STAGE.exists(), f"{STAGE} already exists -- a previous run was killed; remove it"
  raw = subprocess.run(["jj", "file", "show", "-r", rev, ".agents/slop/rebase-gate.py"],
                       cwd=REPO, capture_output=True, text=True, timeout=300)
  if raw.returncode:
    raise SystemExit(f"jj file show -r {rev} failed: {' '.join(raw.stderr.split())[:200]}")
  STAGE.write_text(raw.stdout)
  name = "gate_rev_" + "".join(c for c in rev if c.isalnum())
  spec = importlib.util.spec_from_file_location(name, STAGE)
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m, raw.stdout


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("-r", "--rev", default="@-")
  ap.add_argument("--port", default="tinybendygrad/device.bend")
  ap.add_argument("--reps", type=int, default=1)
  ap.add_argument("--roster", action="store_true",
                  help="list the wiring differences against the working copy and stop")
  a = ap.parse_args()

  g, text = export(a.rev)
  try:
    live_path = HERE / "rebase-gate.py"
    live = live_path.read_text()
    print(f"revision {a.rev}: {len(text)} bytes;  working copy: {len(live)} bytes;  "
          f"identical={text == live}")
    if g.BASE_ORACLES != dict(sorted({p: list(o) for p, o in
                                     [(k, v) for k, v in g.BASE_ORACLES.items()]}.items())):
      print("  (unwired entries stored as tuples)")
    print(f"ORACLE_PY {g.ORACLE_PY}\n")

    if a.roster:
      spec = importlib.util.spec_from_file_location("gate_live_roster", live_path)
      gl = importlib.util.module_from_spec(spec)
      spec.loader.exec_module(gl)
      old, new = set(g.BASE_ORACLES), set(gl.BASE_ORACLES)
      print(f"wired at {a.rev}: {len(old)}   wired in working copy: {len(new)}")
      for p in sorted(old - new):
        print(f"  ONLY at {a.rev}: {p} -> {g.BASE_ORACLES[p]}")
      for p in sorted(new - old):
        print(f"  ONLY in working copy: {p} -> {gl.BASE_ORACLES[p]}")
      return 0

    base = json.loads((HERE / "rebase" / "baseline.json").read_text()) \
      if (HERE / "rebase" / "baseline.json").exists() else {}
    port = a.port
    oracles = g.BASE_ORACLES.get(port, ())
    rec = (base.get("lanes") or {}).get(port)
    print(f"{port} at revision {a.rev}")
    print(f"  wired    : {list(oracles) or 'NOT WIRED'}")
    print(f"  baseline : {'recorded ' + str({k: len(v) for k, v in sorted(rec.items())}) if rec else 'NOT RECORDED'}")
    if not oracles:
      v = g.never_wired(port, REPO / port, oracles)
      print(f"  VERDICT  : {v['state']}\n  reason   : {v['why']}")
      return 0
    for rep in range(1, a.reps + 1):
      t0 = __import__("time").monotonic()
      v, now = g.gate_port(REPO / port, oracles, base, native=True)
      print(f"  rep {rep} VERDICT : {v['state']}   ({__import__('time').monotonic()-t0:.0f}s, "
            f"load {os.getloadavg()[0]:.1f})")
      print(f"      why  : {v['why'][:200]}")
      print(f"      rows : {v['row_counts']}")
      print(f"      lanes: " + "  ".join(f"{k}=rc{l['rc']}" for k, l in sorted(v['lanes'].items())))
      for k, l in sorted(v["lanes"].items()):
        if l["rc"] != 0 and k != "check":
          print(f"        !! {k}: {' '.join(l['err'].split())[-200:]}")
      for d in (v.get("disagreements") or [])[:5]:
        print(f"        !! DISAGREE {d}")
      for u in (v.get("uncompared_pairs") or []):
        print(f"        !! UNCOMPARED {u}")
    return 0
  finally:
    STAGE.unlink(missing_ok=True)
    print(f"\n(staged file removed: {not STAGE.exists()})")


if __name__ == "__main__":
  sys.exit(main())