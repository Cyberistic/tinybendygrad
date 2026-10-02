#!/usr/bin/env python3
"""rebase-gate.py -- MAY I ADVANCE THE PIN YET?  Three states, and one of them is the
state that got away today.

WHY. Re-vendoring changes what every CPython oracle in the tree measures against, so the
question "is this drift closed?" cannot be answered by "the files are at the pin" or by
"the gate exited 0". Twelve committed files printed 0 rows for an hour before anyone
looked, because a harness that reports zero DISAGREEMENTS cannot distinguish "the port
matches" from "nothing was compared". Four states are distinguished here:

    UNCHANGED   zero rows moved, and the file says WHICH HUNKS were examined. Recorded, not
                assumed: "we looked" and "nobody looked" must be different bytes.
    RE-PORTED   rows moved, the port was fixed, and the moved rows now agree with CPython.
    BROKEN      rows went to ZERO, or the oracle died, or a row disagrees. This is the state
                that matters and the reason the tool exists.
    NOT-STARTED no oracle wired for this port, so nothing can be claimed. Explicit, because
                silence here is indistinguishable from success in every other tool.

HOW "ROWS WENT TO ZERO" IS DETECTED, which is the whole point and is three independent
guards, because any one of them alone has already been fooled here:

  1. ABSOLUTE COUNT. A baseline row count is recorded per port. If now < BASELINE, rows
     were LOST -- and a loss to exactly 0 is the failure mode that was invisible for an
     hour. A relative check ("did any row move?") passes on an empty row set.
  2. LANE NON-EMPTINESS. Every lane must produce at least one row. An oracle that exits 0
     having printed nothing is a FAILED ORACLE, not a passing one.
  3. ORACLE REACHABILITY. The oracle script must exist and must have been RUN THIS TIME --
     no cache. drift-gate.py caches lane output in $TMPDIR, and a cached "0 rows" from an
     hour ago is indistinguishable from a fresh 0.

  usage: python3 .agents/slop/rebase-gate.py [--batch N] [--port P] [--record]
         --record   write/refresh the baseline from the CURRENT state (do this at the pin,
                    once, on a tree known green -- never to silence a failure)
"""
import argparse, json, os, pathlib, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parents[2]
SLOP = REPO / ".agents" / "slop"
BASELINE = SLOP / "rebase" / "baseline.json"

UNCHANGED, REPORTED, BROKEN, NOT_STARTED = "UNCHANGED", "RE-PORTED", "BROKEN", "NOT-STARTED"


def sh(*a, timeout=1800):
  return subprocess.run(a, cwd=REPO, capture_output=True, text=True, timeout=timeout)


def rows(text):
  """`name=value` rows. Whole-LINE keyed on name, NEVER on row index: agent-core.md records
  that an index-comparing harness reported 0 for all 30 mutations in one unit."""
  out = {}
  for line in text.splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k.strip()] = v.strip()
  return out


def run_port(bend, oracle, native=True):
  """All lanes, no cache. Returns (state_detail, rows_by_lane).

  `oracle` entries are `path` or `path arg` -- several real oracles take a section name
  (renderer_oracle.py `init` vs `cstyle`), and running one bare gives it no argv[1] and a
  traceback that reads like a broken port rather than a missing argument.
  """
  lanes, r = {}, {}
  chk = sh("./bin/bend", str(bend), "--check-only")
  first = (chk.stdout.strip().splitlines() or [""])[0]
  lanes["check"] = {"rc": chk.returncode, "first": first}

  interp = sh("./bin/bend", str(bend))
  lanes["interpreted"] = {"rc": interp.returncode, "err": interp.stderr[-600:]}
  r["interpreted"] = rows(interp.stdout)

  if native:
    out = pathlib.Path("/tmp/rebase-gate") / f"{bend.stem}.bin"
    out.parent.mkdir(exist_ok=True)
    out.unlink(missing_ok=True)
    b = sh("./bin/bend", str(bend), "-o", str(out))
    if b.returncode or not out.exists():
      lanes["native"] = {"rc": b.returncode or 1, "err": b.stderr[-600:]}
    else:
      out.chmod(0o755)
      n = sh(str(out))
      lanes["native"] = {"rc": n.returncode, "err": n.stderr[-600:]}
      r["native"] = rows(n.stdout)

  for spec in oracle:
    argv = spec.split()
    p = REPO / argv[0]
    if not p.exists():
      lanes[f"cpython:{p.stem}"] = {"rc": 127, "err": "ORACLE SCRIPT MISSING"}
      continue
    e = dict(os.environ, DEV="NULL")
    c = subprocess.run([sys.executable, *argv], cwd=REPO, capture_output=True, text=True,
                       env=e, timeout=1800)
    lanes[f"cpython:{p.stem}"] = {"rc": c.returncode, "err": c.stderr[-600:]}
    r[f"cpython:{p.stem}"] = rows(c.stdout)
  return lanes, r


def verdict(bend, oracle, base, native=True):
  """The three-state decision, with the row-guard that makes BROKEN reachable."""
  lanes, now = run_port(bend, oracle, native)
  v = {"port": str(bend.relative_to(REPO)), "oracles": oracle,
       "row_counts": {k: len(x) for k, x in now.items()}, "lanes": lanes}
  died = [k for k, l in lanes.items() if l["rc"] != 0 and k != "check"]
  if died:
    v["state"], v["why"] = BROKEN, f"lane(s) failed to run: {', '.join(died)}"
    return v, now

  # GUARD 2: an empty lane is a failed oracle, never a pass. This is the hour-long bug.
  empty = [k for k, x in now.items() if not x]
  if empty:
    # GUARD 2 fires before GUARD 1 on purpose: a lane with no rows is wrong whether or not a
    # baseline exists. Naming the baseline count here is what lets the 210 -> 0 case say
    # "TO ZERO" instead of the vague "produced zero rows" -- the number is the evidence.
    was = {k: len(base.get("lanes", {}).get(k, {})) for k in empty}
    v["state"] = BROKEN
    v["why"] = (f"lane(s) produced ZERO rows: "
                f"{', '.join(f'{k} (baseline {n})' for k, n in was.items())}. "
                f"An oracle that emits no `name=value` rows compared nothing and agrees "
                f"with nothing"
                + ("  (TO ZERO -- the failure that went unnoticed for an hour)"
                   if any(was.values()) else ""))
    return v, now

  if base is None:
    v["state"], v["why"] = NOT_STARTED, "no baseline recorded"
    return v, now

  # GUARD 1: absolute count. Relative comparison cannot see a row set that emptied.
  moved, lost, bad = [], [], []
  for lane, was in base.get("lanes", {}).items():
    have = now.get(lane, {})
    if not was:
      continue
    # GUARD 1, absolute. A relative "did any row change?" cannot see an emptied row set:
    # an empty set is trivially equal to nothing, so the check passes on total silence.
    if len(have) < len(was):
      lost.append((lane, len(was), len(have)))
    for k in set(was) & set(have):
      if was[k] != have[k]:
        moved.append((lane, k, was[k], have[k]))
  if lost:
    v["state"] = BROKEN
    v["why"] = "; ".join(
      f"lane `{n}` LOST ROWS: {was} -> {have}"
      + ("  (TO ZERO -- the failure that went unnoticed for an hour)" if not have else "")
      for n, was, have in lost)
    return v, now

  for lane in now:
    for other in now:
      if lane >= other or other not in base.get("lanes", {}):
        continue
      for k in set(now[lane]) & set(now[other]):
        if now[lane][k] != now[other][k]:
          bad.append((lane, other, k))
  if bad:
    v["state"] = BROKEN
    v["why"] = f"{len(bad)} row(s) disagree with CPython"
    v["disagreements"] = bad[:20]
    return v, now
  v["moved"] = moved[:50]
  v["moved_count"] = len(moved)
  if moved:
    v["state"], v["why"] = REPORTED, f"{len(moved)} row(s) moved and now agree"
  else:
    v["state"] = UNCHANGED
    v["why"] = "zero rows moved"
    v["hunks_examined"] = base.get("hunks", [])
  return v, now


def load_baseline():
  return json.loads(BASELINE.read_text()) if BASELINE.exists() else {}


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--batch", type=int, default=None)
  ap.add_argument("--port", default=None)
  ap.add_argument("--record", action="store_true")
  ap.add_argument("--no-native", action="store_true")
  ap.add_argument("--json", action="store_true")
  a = ap.parse_args()

  plan = json.loads(sh("python3", ".agents/slop/rebase-plan.py", "--json").stdout)
  base = load_baseline()
  batch = next((b for b in plan["batches"] if b["id"] == a.batch), None) if a.batch else None

  targets = []
  if a.port:
    targets = [(a.port, BASE_ORACLES.get(a.port, []))]
  elif batch:
    for f in batch["files"]:
      p = plan["port"].get(f)
      if p:
        targets.append((p, BASE_ORACLES.get(p, [])))
  else:
    for b in plan["batches"]:
      for f in b["files"]:
        p = plan["port"].get(f)
        if p and p in BASE_ORACLES:
          targets.append((p, BASE_ORACLES[p]))
  targets = list({p: tuple(o) for p, o in targets}.items())

  if a.record:
    out = {"lanes": {}, "hunks": {}}
    for port, oracles in targets:
      bend = REPO / port
      if not oracles or not bend.exists():
        continue
      _, now = run_port(bend, oracles, not a.no_native)
      out["lanes"][port] = {k: v for k, v in now.items() if v}
      out["hunks"][port] = plan["api_delta"].get(
        next((f for f in plan["port"] if plan["port"][f] == port), ""), {})
    BASELINE.parent.mkdir(parents=True, exist_ok=True)
    BASELINE.write_text(json.dumps(out, indent=1))
    print(f"recorded baseline for {len(out['lanes'])} ports -> {BASELINE.relative_to(REPO)}")
    return 0

  verdicts, tally = [], {}
  for port, oracles in targets:
    bend = REPO / port
    if not bend.exists():
      continue
    if not oracles:
      verdicts.append({"port": port, "state": NOT_STARTED,
                       "why": "no oracle wired in BASE_ORACLES -- nothing can be claimed"})
      tally[NOT_STARTED] = tally.get(NOT_STARTED, 0) + 1
      continue
    v, _ = verdict(bend, oracles, base.get(port), not a.no_native)
    verdicts.append(v)
    tally[v["state"]] = tally.get(v["state"], 0) + 1

  if a.json:
    print(json.dumps({"tally": tally, "verdicts": verdicts}, indent=2))
  else:
    for v in verdicts:
      print(f"{v['state']:<12} {v['port']}")
      print(f"             {v['why']}")
      for k, n in v.get("row_counts", {}).items():
        print(f"               rows {k}={n}")
      for m in v.get("moved", [])[:8]:
        print(f"               MOVED {m[1]}: {m[2]!r} -> {m[3]!r}")
    print("\nTALLY " + "  ".join(f"{k}={v}" for k, v in sorted(tally.items())))
  return 1 if tally.get(BROKEN) else 0


# Oracles are wired per PORT, not per upstream file, because a port's oracle is what
# actually constrains it. A port with no entry here is NOT-STARTED, and the tool says so
# instead of letting silence pass for success. Widen this as oracles land -- and do not
# point an oracle at a different port's question, which is how a file ends up "verified"
# by rows that never touched it.
BASE_ORACLES = {
  "tinybendygrad/runtime/support/hcq2.bend": [".agents/slop/hcq2-oracle.py"],
  "tinybendygrad/dtype.bend": [".agents/slop/oracle/dtype_tables.py"],
  "tinybendygrad/renderer/cstyle.bend": [".agents/slop/renderer_oracle.py cstyle"],
}


if __name__ == "__main__":
  sys.exit(main())