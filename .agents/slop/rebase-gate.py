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

⚠ GUARD 1 WAS DEAD AS SHIPPED, AND THE DEADNESS WAS INVISIBLE. baseline.json is
{"lanes": {port: rows}, "hunks": {port: delta}} and the call site read base.get(port).
The port name is a key of the INNER dict, so that read is None for EVERY port, and None
short-circuits verdict() to NOT-STARTED -- which is BEFORE GUARD 1. So the absolute-count
guard, the headline state of this tool, had never executed on a real port, and a file
holding 225/225/33 rows printed "no baseline recorded". Two consequences, both fixed
here rather than in one call site:

  * baseline_for() is the ONLY place baseline.json is read, and it names a malformed
    document instead of returning None for one -- a wrong nesting level is a silent pass,
    so it must be loud.
  * rebase-gate-selftest.py drives gate_port(), the same function main() calls. It used to
    hand verdict() a hand-built {"lanes": {lane: rows}} dict, which is NOT the shape
    baseline.json has, so it went green on a call the tool never makes. A selftest that
    tests a differently-shaped call than production is the same instrument lying, one
    layer down, and it is why this bug survived a selftest that passed.

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


def diff_stat(src):
  """The upstream diff for one file, pin..HEAD, in words. Computed, so a re-verify names the
  hunks it looked at without anyone transcribing them.

  A FAILED git must not read as "no diff": an out-of-tree copy with no `.git` answers the
  same empty stdout as a file upstream never touched, and "no upstream diff" is the one
  answer that would let a re-verify look examined when nothing was asked."""
  plan = json.loads(sh("python3", ".agents/slop/rebase-plan.py", "--json").stdout or "{}")
  pin = plan.get("pin")
  if not pin:
    return "UNAVAILABLE: rebase-plan.py produced no pin"
  d = sh("git", "diff", "--stat", pin, "upstream/master", "--", src)
  if d.returncode:
    return f"UNAVAILABLE: git diff failed ({' '.join(d.stderr.split())[:90]})"
  return " ".join(d.stdout.split()) or f"(upstream has no diff for {src})"


# The plan's port map is derived from a file's STEM, so every file whose port has a
# different stem is missing from it -- and a missing port is a port whose drift is never
# measured, which is worse than a reported non-match. B1 found two of these; the rest are
# read out of each port's own HEADER, which names the upstream file(s) it ports:
#   codegen/__init__.py -> kernel.bend      (codegen/ is a PACKAGE: there is no kernel.py)
#   codegen/gpudims.py   -> rewriter.bend   (+ kernel.bend, which also reads it)
#   renderer/ptx.py     -> tc_ptx.bend      ("tc.py AND ptx.py, in ONE file")
#   renderer/llvmir.py  -> nir_llvmir.bend  ("nir.py AND llvmir.py")
#   runtime/ops_python.py -> executor.bend  (plan mapped it nowhere)
#   runtime/ops_cuda.py  -> ops_cl.bend     ("ops_cl.py + ops_cuda.py + ops_hip.py")
EXTRA_PORTS = {
  "tinygrad/codegen/__init__.py": ["tinybendygrad/codegen/kernel.bend"],
  "tinygrad/codegen/gpudims.py": ["tinybendygrad/codegen/rewriter.bend",
                                  "tinybendygrad/codegen/kernel.bend"],
  "tinygrad/codegen/simplify.py": ["tinybendygrad/codegen/rewriter.bend"],
  "tinygrad/renderer/ptx.py": ["tinybendygrad/renderer/tc_ptx.bend"],
  "tinygrad/renderer/llvmir.py": ["tinybendygrad/renderer/nir_llvmir.bend"],
  "tinygrad/runtime/ops_python.py": ["tinybendygrad/runtime/executor.bend"],
  "tinygrad/runtime/ops_cuda.py": ["tinybendygrad/runtime/ops_cl.bend"],
  "tinygrad/runtime/ops_null.py": ["tinybendygrad/runtime/ops_cpu_null.bend"],
  "tinygrad/runtime/ops_cpu.py": ["tinybendygrad/runtime/ops_cpu_null.bend"],
}


def ports_of(src, plan):
  """Every port that reads this upstream file: the plan's stem map plus EXTRA_PORTS."""
  out = list(EXTRA_PORTS.get(src, []))
  p = plan["port"].get(src)
  return out + ([p] if p and p not in out else [])


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


def hunks_view(rec):
  """baseline.json's hunks exist in two shapes: {file: {api_delta, diff_stat}}, and the
  original --record's bare api_delta, which LOST THE FILENAME. Both normalise to
  {file: delta}, and the nameless one is LABELLED rather than dropped -- a record that
  cannot say which file it examined must not be allowed to read as "nothing changed"."""
  if not isinstance(rec, dict):
    return {}
  if any(k in rec for k in ("added", "removed", "changed")):
    return {"<file not named at record time>": rec}
  return rec


def hunks_summary(hunks):
  """What was examined, in one line. Counted from the record, never asserted by hand: a
  re-verify that examined nothing must print different bytes from one that examined all of
  it, and the count is the only thing here that cannot be typed."""
  syms = sum(len(d.get(k, [])) for h in hunks.values()
             for d in [h.get("api_delta", h) if isinstance(h, dict) else {}]
             for k in ("added", "removed", "changed"))
  if not hunks:
    return "NO HUNKS RECORDED -- this is a re-verify that examined nothing"
  return (f"{syms} symbol(s) changed across {len(hunks)} upstream file(s): "
          + ", ".join(hunks))


def baseline_for(base, port):
  """baseline.json -> (lane_rows, hunks, complaint). The ONLY reader of that file.

  baseline.json is `{"lanes": {port: {lane: {name: value}}}, "hunks": {port: delta}}`.
  Reading the wrong nesting level returns None, and None means "no baseline", so a wrong
  nesting level is a SILENT PASS -- the guard that has now shipped once, because
  `base.get(port)` was None for every port and verdict() returned NOT-STARTED before
  GUARD 1. So: one reader, called by main() and by the selftest, and it distinguishes
  "there is no baseline for this port" from "this baseline is not the shape I read".
  """
  if not base:
    return None, None, "no baseline.json on disk"
  if "lanes" not in base:
    return None, None, (f"baseline.json is MALFORMED: top-level keys {sorted(base)}, "
                        "expected 'lanes' and 'hunks'. A guard that cannot read its own "
                        "baseline must not report a port as unstarted")
  if port not in base["lanes"]:
    return None, None, f"no baseline recorded for {port}"
  return base["lanes"][port] or {}, base.get("hunks", {}).get(port) or {}, None


def port_key(bend):
  """The one spelling of a port's name. baseline.json is keyed by the REPO-RELATIVE path,
  and a key built anywhere else is a second spelling -- which is how a baseline of 225/225/33
  rows read as "no baseline recorded", twice, for two different reasons."""
  try:
    return str(bend.relative_to(REPO))
  except ValueError:
    return str(bend)


def gate_port(bend, oracles, base, native=True, files=None):
  """Slice the baseline for THIS port, then judge. One entry point, so main() and
  rebase-gate-selftest.py cannot drift into judging differently-shaped inputs.

  `files` is {upstream file: api_delta} for this port, which only main() knows. It is used
  when the recorded hunks are a bare api_delta that lost its filename: the diff is then
  recomputed and the verdict says so, because a record that cannot name a file must not be
  reported as "nothing changed"."""
  base_rows, hunks, complaint = baseline_for(base, port_key(bend))
  v, now = verdict(bend, oracles, base_rows, hunks_view(hunks), native)
  if complaint and v["state"] == NOT_STARTED:
    v["why"] = complaint
  if files and "<file not named at record time>" in v.get("hunks_examined", {}):
    v["hunks_examined"] = {f: {"api_delta": d, "diff_stat": diff_stat(f)}
                           for f, d in files.items()}
    v["hunks_status"] = hunks_summary(v["hunks_examined"])
    v["why"] = f"zero rows moved; {v['hunks_status']}"
    v["hunks_note"] = ("the recorded hunks did not name a file, so the diff was recomputed "
                       f"from the plan for {', '.join(files)}")
  return v, now


def verdict(bend, oracle, base, hunks, native=True):
  """The four-state decision, with the row-guard that makes BROKEN reachable.

  `base` is the per-PORT lane dict and `hunks` the per-port examined-delta dict, both
  sliced by baseline_for(). They are separate arguments on purpose: one argument that
  holds both is one argument that can be handed the wrong half.
  """
  lanes, now = run_port(bend, oracle, native)
  v = {"port": port_key(bend), "oracles": oracle,
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
    was = {k: len((base or {}).get(k, {})) for k in empty}
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

  if not base:
    # A recorded-but-empty baseline compares nothing, so every lane above is "new" and
    # GUARD 1 below would find zero moved rows and call it UNCHANGED. That is a pass with
    # no comparison behind it, which is the same lie at one remove.
    v["state"], v["why"] = NOT_STARTED, (
      "baseline recorded ZERO lanes for this port, so nothing can be compared against it. "
      "Re-record with --record on a tree known green; do not treat this as a pass")
    return v, now

  hollow = [k for k, x in base.items() if not x]
  if hollow:
    # Same lie, one lane down: a baseline lane with no rows was recorded off a broken lane,
    # and `if not was: continue` in GUARD 1 would skip it forever, so the lane would be
    # neither counted nor compared. Name it instead.
    v["state"], v["why"] = NOT_STARTED, (
      f"baseline lane(s) {', '.join(hollow)} were recorded with ZERO rows, so they compare "
      "nothing. The recording caught a broken lane; re-record with --record on a tree known green")
    return v, now

  # GUARD 1: absolute count. Relative comparison cannot see a row set that emptied.
  moved, lost, bad = [], [], []
  for lane, was in base.items():
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

  # GUARD 3: a lane PAIR that shares no row name compared NOTHING. `cstyle.bend` prints
  # `name = [...]   py=[...]` while renderer_oracle.py prints `name = [...]` for a
  # different set of claims, so the key intersection is ZERO -- and a loop over an empty
  # intersection reports no disagreements, forever. Measured: 225 bend rows vs 33 oracle
  # rows, 0 shared names. Silence here is the same lie as silence in GUARD 2, one level up,
  # so a pair that cannot be compared is named instead of counted as agreeing.
  compared, uncompared, bad = [], [], []
  for lane in sorted(now):
    for other in sorted(now):
      if lane >= other:
        continue
      shared = set(now[lane]) & set(now[other])
      (compared if shared else uncompared).append((lane, other, len(shared)))
      bad += [(lane, other, k) for k in shared if now[lane][k] != now[other][k]]
  if uncompared:
    v["state"] = BROKEN
    v["why"] = ("lane pair(s) share NO row names, so they compared nothing: "
                + ", ".join(f"`{a}` vs `{b}`" for a, b, _ in uncompared)
                + ". Two lanes that cannot be compared cannot agree")
    v["uncompared_pairs"] = uncompared
    return v, now
  if bad:
    v["state"] = BROKEN
    v["why"] = f"{len(bad)} row(s) disagree with CPython across {len(compared)} lane pair(s)"
    v["disagreements"] = bad[:20]
    return v, now
  v["compared_pairs"] = compared
  v["moved"] = moved[:50]
  v["moved_count"] = len(moved)
  if moved:
    v["state"], v["why"] = REPORTED, f"{len(moved)} row(s) moved and now agree"
  else:
    v["state"] = UNCHANGED
    # WHICH HUNKS. This is the only thing that separates "we looked" from "nobody looked",
    # and it is read per PORT -- reading base.get("hunks") off a per-port lane slice is how
    # it printed [] on every run, i.e. it printed the same bytes whether a human examined
    # the diff or not. An UNCHANGED with no recorded hunks says so in `why`, in the words a
    # reader of the summary will actually see.
    v["hunks_examined"] = hunks
    v["hunks_status"] = hunks_summary(hunks)
    v["why"] = f"zero rows moved; {v['hunks_status']}"
  return v, now


def load_baseline():
  return json.loads(BASELINE.read_text()) if BASELINE.exists() else {}


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--batch", type=int, default=None)
  ap.add_argument("--port", default=None)
  ap.add_argument("--singletons", action="store_true",
                  help="the independent singletons only (plan['independent'])")
  ap.add_argument("--record", action="store_true")
  ap.add_argument("--baseline", default=None,
                  help="a baseline file other than rebase/baseline.json -- for measuring a "
                       "port without touching the recorded one")
  ap.add_argument("--no-native", action="store_true")
  ap.add_argument("--json", action="store_true")
  a = ap.parse_args()

  plan = json.loads(sh("python3", ".agents/slop/rebase-plan.py", "--json").stdout)
  baseline_path = pathlib.Path(a.baseline) if a.baseline else BASELINE
  base = json.loads(baseline_path.read_text()) if baseline_path.exists() else {}
  batch = next((b for b in plan["batches"] if b["id"] == a.batch), None) if a.batch else None

  # --port names a PORT (.bend path); everything else names UPSTREAM FILES, which is what
  # the plan maps. Mixing the two is how a target list comes out empty and the gate prints
  # an empty TALLY, which reads as "nothing to report" rather than "nothing was checked".
  if a.port:
    targets = [(a.port, tuple(BASE_ORACLES.get(a.port, [])))]
  else:
    srcs = (plan["independent"] if a.singletons else
            batch["files"] if batch else
            [f for b in plan["batches"] for f in b["files"]])
    targets = [(p, tuple(BASE_ORACLES.get(p, []))) for f in srcs for p in ports_of(f, plan)]
  targets = list({p: o for p, o in targets}.items())
  if not targets:
    # An empty TALLY is the shape of the bug being fixed: it reads as "nothing to report"
    # when it means "nothing was checked". Name it.
    print(f"NO TARGETS: {' '.join(srcs) if not a.port else a.port} "
          "maps to no port that exists. Nothing was checked.")
    return 1

  if a.record:
    out = {"lanes": {}, "hunks": {}}
    for port, oracles in targets:
      bend = REPO / port
      if not oracles or not bend.exists():
        continue
      _, now = run_port(bend, oracles, not a.no_native)
      out["lanes"][port] = now  # empty lanes are KEPT: a dropped lane cannot be counted as lost
      # The hunks a later UNCHANGED has to name: which upstream file(s) the port reads, the
      # computed API delta of each, and the real diff's line counts. Computed, never typed.
      out["hunks"][port] = {
        f: {"api_delta": plan["api_delta"].get(f, {}), "diff_stat": diff_stat(f)}
        for f in plan["port"] if port in ports_of(f, plan)}
    baseline_path.parent.mkdir(parents=True, exist_ok=True)
    baseline_path.write_text(json.dumps(out, indent=1))
    print(f"recorded baseline for {len(out['lanes'])} ports -> {baseline_path}")
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
    v, _ = gate_port(bend, oracles, base, not a.no_native,
                     files={f: plan["api_delta"].get(f, {}) for f in plan["port"]
                            if port in ports_of(f, plan)})
    verdicts.append(v)
    tally[v["state"]] = tally.get(v["state"], 0) + 1
    if v.get("hunks_status", "").startswith("NO HUNKS"):
      tally["LOOK-UNRECORDED"] = tally.get("LOOK-UNRECORDED", 0) + 1

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
      if "hunks_examined" in v:
        print(f"               hunks_examined: {v['hunks_status']}")
        if v.get("hunks_note"):
          print(f"               NOTE: {v['hunks_note']}")
        for src, h in v["hunks_examined"].items():
          d = h.get("api_delta", h) if isinstance(h, dict) else {}
          print(f"                 {src}: {h.get('diff_stat') or 'diff stat not recorded'}")
          for kind in ("added", "removed", "changed"):
            if d.get(kind):
              print(f"                   {kind}: {', '.join(map(str, d[kind]))}")
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