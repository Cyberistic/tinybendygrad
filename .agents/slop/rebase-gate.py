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

HOW "ROWS WENT TO ZERO" IS DETECTED, which is the whole point and is FOUR independent
guards, because any one of them alone has already been fooled here. The numbers are the
guard's NUMBER and the inline `# GUARD n` comments name the same four, in the order the
code runs them:

  1. ABSOLUTE COUNT. A baseline row count is recorded per port. If now < BASELINE, rows
     were LOST -- and a loss to exactly 0 is the failure mode that was invisible for an
     hour. A relative check ("did any row move?") passes on an empty row set.
  2. LANE NON-EMPTINESS. Every lane must produce at least one row. An oracle that exits 0
     having printed nothing is a FAILED ORACLE, not a passing one.
  3. ORACLE REACHABILITY. The oracle script must exist and must have been RUN THIS TIME --
     no cache. drift-gate.py caches lane output in $TMPDIR, and a cached "0 rows" from an
     hour ago is indistinguishable from a fresh 0.
  4. COMPARABILITY AND DISAGREEMENT. Two lanes must share at least one row NAME -- a pair that
     shares none compared nothing -- and any shared row whose values differ is BROKEN. This
     guard reads NOTHING from baseline.json, so it runs BEFORE the baseline shortcut: a live
     disagreement must never be reported as "no baseline recorded", which is a verdict that
     gets believed. Measured: with the order reversed, a port and a corrupted oracle
     disagreed on one row and the gate answered NOT-STARTED with rc=0.

⚠ THE NUMBERING WAS WRONG ON ARRIVAL AND WAS NOT COSMETIC. The header's guard 3 is
ORACLE REACHABILITY, which is the `died` loop -- but the code labelled the *pair*
comparison "# GUARD 3", so the header described a guard the code did not name and the code
numbered one the header did not list. A reader checking the header against the code found
two different GUARD 3s. Renumbered so both say the same thing.

  THE ORDER IS NOT THE NUMBERING. The code runs 3, 2, 4, 1, and that order is the design:
reachability first, because a lane that never ran cannot be non-empty; emptiness second;
comparability third, because it consults no baseline and must therefore not wait for one;
and the count last, because it is the only guard that genuinely needs the recording.

⚠ `plan["port"]`'s VALUE TYPE IS A CROSS-FILE CONTRACT AND IT CHANGED UNDER THIS READER,
which is how this tool came to print a traceback and exit non-zero with no verdict at all.
rebase-plan.py wrote `port[f] = str | None`. Commit d4f647349 changed it to
`port[f] = [str, ...] | None` -- one port may be the port of SEVERAL upstream files, which
is how codegen/rewriter.bend came to be the port of three -- and did not touch this file.
ports_of() still did `[p]`, so it returned a list of lists and main()'s de-duplicating
dict died on `TypeError: unhashable type: 'list'`.

  A crash is the BEST outcome that bug could have had: the shape mismatch was LOUD. The
  reader below accepts both shapes and RAISES on any other, so the next contract change
  is loud too. A reader that answers "no ports" to a value it does not understand is the
  silent pass this file exists to prevent, and it is worse: 213 of 213 ports would have
  answered NOT-STARTED and a rebase would have read as "nothing drifted".

  The gate crashed on its default (no-argument) invocation, so `--port`, `--batch`,
  `--record` and the whole-tree sweep were ALL unreachable -- and a selftest that calls
  gate_port() directly went green the entire time, because the crash was in main()'s
  TARGET CONSTRUCTION, above the part the selftest drives. That gap is closed:
  rebase-gate-selftest.py now drives targets_of(), the same function main() calls.

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
  * rebase-gate-selftest.py drives gate_port() and targets_of(), the same functions main()
    calls. It used to hand verdict() a hand-built {"lanes": {lane: rows}} dict, which is
    NOT the shape baseline.json has, so it went green on a call the tool never makes. A
    selftest that tests a differently-shaped call than production is the same instrument
    lying, one layer down, and it is why this bug survived a selftest that passed.

  usage: python3 .agents/slop/rebase-gate.py [--batch N] [--port P] [--record]
         --record   write/refresh the baseline from the CURRENT state (do this at the pin,
                    once, on a tree known green -- never to silence a failure)

  the gate has been SEEN RED, twice, and both are reproducible:
    .agents/slop/rebase-plant-disagreement.py   a planted disagreement -> BROKEN, named row,
                                                 plus the SAME pair uncorrupted -> not BROKEN
    rebase-gate-selftest.py                     the four states over synthetic lanes, plus
                                                 the two deliberately-dead lanes on the real
                                                 tree, plus the plan contract in BOTH shapes
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


# The plan's port map is READ out of each port's own HEADER by rebase-plan.py's
# header_ports(), so it already covers every port whose header names its own upstream file.
# What it cannot cover is a port with NO header comment: header_ports() requires the first
# token of the header comment to be a path ending in `<stem>.bend`, and a file whose first
# line is `import Base` has no header, so nothing maps it.
#
# AUDITED 2026-10-03 against header_ports() on the live tree, entry by entry. Nine entries,
# and EIGHT of the nine are redundant or wrong. Measured, not assumed:
#
#   codegen/__init__.py   -> kernel.bend        OBSOLETE, identity of the header map
#   runtime/ops_python.py -> executor.bend      OBSOLETE, identity of the header map. It was
#                                              ALSO a dead path by the time it was audited --
#                                              the 1:1 ruling split executor.bend into
#                                              runtime/ops_python.bend, and the selftest's
#                                              "every removed target still exists" check is
#                                              what found that, not a re-read of the comment
#   codegen/simplify.py   -> rewriter.bend      OBSOLETE and WRONG: rewriter.bend has no
#                                              upstream .py of its own; simplify.bend does
#   codegen/gpudims.py    -> rewriter.bend,     OBSOLETE and both WRONG: same 1:1 split,
#                          kernel.bend           gpudims.bend is the real port
#   renderer/ptx.py       -> tc_ptx.bend        SUBSET of the header map, which also has
#                                              ptx.bend; a merge split into two files
#   renderer/llvmir.py    -> nir_llvmir.bend    SUBSET, same shape (llvmir.bend + nir_llvmir)
#   runtime/ops_null.py   -> ops_cpu_null.bend  OBSOLETE and a DEAD PATH -- the file no longer
#                                              exists; the 1:1 split made ops_null.bend
#   runtime/ops_cpu.py    -> ops_cpu_null.bend  OBSOLETE and a DEAD PATH -- same split
#   runtime/ops_cuda.py   -> ops_cl.bend        KEPT, and CORRECTED to ops_cuda.bend. The
#                                              header map says NOTHING for this file, and
#                                              the wrong answer it does give
#                                              (`tinygrad/ops_cuda.py`, a path that does
#                                              not exist upstream) comes from rebase-plan.py's
#                                              _BARE_RE, which prefixes a bare name with
#                                              `tinygrad/` and so cannot resolve a directory.
#                                              REPORTED, not fixed -- not this file.
#
# So the redundant entries go and only the one header_ports() provably cannot see is kept.
# rebase-gate-selftest.py asserts every remaining entry is ABSENT from the header map, so a
# later header edit cannot quietly make one redundant again -- which is how all eight got
# here in the first place. It also asserts every port named below EXISTS, which is how the
# two dead paths were found rather than left to fire as "no oracle" forever.
EXTRA_PORTS = {
  "tinygrad/runtime/ops_cuda.py": ["tinybendygrad/runtime/ops_cuda.bend"],
}

# Kept as DATA so the selftest re-checks the audit against the live tree instead of against a
# comment that can go stale. (upstream, [ports rebase-plan.py's header map already derives])
OBSOLETE_EXTRA_PORTS = {
  "tinygrad/codegen/__init__.py": ["tinybendygrad/codegen/kernel.bend"],
  "tinygrad/codegen/gpudims.py": ["tinybendygrad/codegen/gpudims.bend"],
  "tinygrad/codegen/simplify.py": ["tinybendygrad/codegen/simplify.bend"],
  "tinygrad/renderer/ptx.py": ["tinybendygrad/renderer/ptx.bend",
                               "tinybendygrad/renderer/tc_ptx.bend"],
  "tinygrad/renderer/llvmir.py": ["tinybendygrad/renderer/llvmir.bend",
                                  "tinybendygrad/renderer/nir_llvmir.bend"],
  "tinygrad/runtime/ops_python.py": ["tinybendygrad/runtime/ops_python.bend"],
  "tinygrad/runtime/ops_null.py": ["tinybendygrad/runtime/ops_null.bend"],
  "tinygrad/runtime/ops_cpu.py": ["tinybendygrad/runtime/ops_cpu.bend"],
}


class PlanShapeError(ValueError):
  """rebase-plan.py's JSON is not the shape this tool reads. Raised, never absorbed: a target
  list built from a plan nobody understood is the silent pass this file exists to prevent, and
  it would answer NOT-STARTED for all 213 ports, which reads exactly like "nothing drifted"."""


def ports_of(src, plan):
  """Every port that reads this upstream file: the plan's map plus EXTRA_PORTS.

  THE VALUE TYPE OF plan["port"][src] IS A CONTRACT WITH ANOTHER FILE, and it changed under
  this reader without a word. rebase-plan.py wrote `str | None`; commit d4f647349 wrote
  `[str, ...] | None`, because one port may be the port of SEVERAL upstream files -- which is
  how codegen/rewriter.bend came to be the port of three. This function kept `[p]`, so it
  returned a list of lists and main() died on `TypeError: unhashable type: 'list'` -- on its
  DEFAULT invocation, which took --port, --batch, --record and the whole-tree sweep with it.

  Both shapes are read. Anything else is NAMED, never flattened. The contract is documented
  here and pinned by rebase-gate-selftest.py, which drives this function through BOTH shapes.
  """
  raw = (plan.get("port") or {}).get(src)
  if raw is None:
    out = []
  elif isinstance(raw, str):
    out = [raw]
  elif isinstance(raw, (list, tuple)):
    out = list(raw)
  else:
    raise PlanShapeError(
      f"plan['port'][{src!r}] is a {type(raw).__name__}, expected a port path or a list of "
      f"them: {raw!r}")
  junk = [p for p in out if not isinstance(p, str)]
  if junk:
    raise PlanShapeError(
      f"plan['port'][{src!r}] holds {junk} -- a list OF lists is exactly what this reader "
      "produced by accident, so it is called out rather than silently flattened")
  for p in EXTRA_PORTS.get(src, []):
    if p not in out:
      out.append(p)
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

  # GUARD 3's evidence. A lane is keyed `cpython:<STEM>`, which is NOT unique: two oracles
  # with the same stem collide and the second SILENTLY overwrites the first lane's rows, so a
  # wired oracle could vanish and nothing would say so. The collision is therefore named,
  # before anything is run, rather than resolved by renaming the lane -- renaming would
  # invalidate every recorded baseline, since baseline.json is keyed by lane NAME.
  stems = {}
  for spec in oracle:
    s = pathlib.Path(spec.split()[0]).stem
    stems.setdefault(s, []).append(spec)
  collided = {s: spec for s, spec in stems.items() if len(spec) > 1}

  for spec in oracle:
    argv = spec.split()
    p = REPO / argv[0]
    key = f"cpython:{p.stem}"
    if key in lanes:
      lanes[key] = {"rc": 127, "err": f"LANE NAME COLLISION: {collided.get(p.stem, [spec])}"}
      continue
    if not p.exists():
      lanes[key] = {"rc": 127, "err": "ORACLE SCRIPT MISSING"}
      continue
    e = dict(os.environ, DEV="NULL")
    c = subprocess.run([sys.executable, *argv], cwd=REPO, capture_output=True, text=True,
                       env=e, timeout=1800)
    lanes[key] = {"rc": c.returncode, "err": c.stderr[-600:]}
    r[key] = rows(c.stdout)
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
  # GUARD 3 first: a lane that did not run at all (missing oracle, non-zero exit, collided
  # lane name) cannot be compared with anything, so there is nothing to say about its rows.
  died = [k for k, l in lanes.items() if l["rc"] != 0 and k != "check"]
  if died:
    v["state"], v["why"] = BROKEN, (
      f"lane(s) failed to run: {', '.join(died)}"
      + ("  (" + "; ".join(f"{k}: {lanes[k]['err'][:120]}" for k in died) + ")"
         if any("ORACLE SCRIPT MISSING" in lanes[k]["err"] or "COLLISION" in lanes[k]["err"]
                for k in died) else ""))
    return v, now
  # GUARD 2: an empty lane is a failed oracle, never a pass. This is the hour-long bug.
  # Ordering is 3, 2, 4, 1 -- reachability first (a lane that never ran cannot be non-empty),
  # then emptiness, then comparability (baseline-free, so it must not wait for the baseline),
  # then the count, which is the only guard that genuinely needs the recording.
  empty = [k for k, x in now.items() if not x]
  if empty:
    # Naming the baseline count here is what lets the 210 -> 0 case say
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

  # GUARD 4 BEFORE THE BASELINE SHORTCIRCUIT, and this ordering is the whole reason a live
  # disagreement can never be mistaken for an unrecorded port. GUARD 4 compares two lanes of
  # THIS RUN against each other; it reads nothing from baseline.json, so a baseline is not
  # evidence it needs and its absence cannot excuse it. GUARD 1 below is the opposite: it is
  # entirely about movement since the recording, so without a baseline there is genuinely
  # nothing to say and NOT-STARTED is the truthful answer.
  #
  # ⚠ THE ORDER WAS BACKWARDS AND IT REPORTED A WRONG VERDICT, which is worse than crashing.
  # Measured with a planted disagreement against ops_nv: the port and a CORRUPTED oracle
  # disagreed on one row, and the gate answered "NOT-STARTED: no baseline recorded for
  # tinybendygrad/runtime/ops_nv.bend" with rc=0. A crashing gate is a finding; a gate that
  # says NOT-STARTED while the port and CPython visibly disagree is believed. Every port with
  # no baseline recorded could have been hiding a live disagreement in exactly that state.
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

  if base is None:
    v["state"], v["why"] = NOT_STARTED, (
      "no baseline recorded, so UNCHANGED-vs-RE-PORTED cannot be judged -- but every lane "
      "pair DID compare and agrees, which is a weaker claim than UNCHANGED and is not one. "
      "Record with --record on a tree known green")
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
  moved, lost = [], []
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


def targets_of(port, srcs, plan):
  """[(port, oracles)] for this run, de-duplicated by port. The function main() calls.

  It is extracted and named because THIS IS WHERE THE CRASH WAS, and the selftest drove
  gate_port() instead -- so it went green for the whole session while the tool's DEFAULT
  invocation, and every flag with it, raised `TypeError: unhashable type: 'list'`. A
  selftest that covers the decision and not the target list is a gate that is green and does
  not run.

  `--port` names a PORT (.bend path); everything else names UPSTREAM FILES, which is what the
  plan maps. Mixing the two is how a target list comes out empty and the gate prints an empty
  TALLY, which reads as "nothing to report" rather than "nothing was checked"."""
  if port:
    return [(port, tuple(BASE_ORACLES.get(port, [])))]
  raw = [(p, tuple(BASE_ORACLES.get(p, []))) for f in srcs for p in ports_of(f, plan)]
  return list({p: o for p, o in raw}.items())


def srcs_of(a, plan):
  """The upstream files this run covers. A --port run has none: it names a port directly."""
  if a.port:
    return []
  if a.singletons:
    return plan["independent"]
  batch = next((b for b in plan["batches"] if b["id"] == a.batch), None) if a.batch else None
  return batch["files"] if batch else [f for b in plan["batches"] for f in b["files"]]


def upstream_of(targets, plan):
  """{port: [upstream files it is the port of]}. The reverse of ports_of, built ONCE.

  Both --record and the gate loop need it, and both used to recompute it per port with
  `for f in plan["port"] if port in ports_of(f, plan)` -- 213 ports_of calls per target, over
  a dict read whose value type had already changed once. One reader, one traversal."""
  rev = {p: [] for p, _ in targets}
  for f in (plan.get("port") or {}):
    for p in ports_of(f, plan):
      if p in rev and f not in rev[p]:
        rev[p].append(f)
  return rev


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

  # The plan is another file's output and this tool reads three things out of it. An empty or
  # unparseable plan used to be a bare `json.JSONDecodeError` traceback; it is named instead,
  # because the difference between "the plan says nothing changed" and "the plan did not run"
  # is the whole question this tool exists to answer.
  pr = sh("python3", ".agents/slop/rebase-plan.py", "--json")
  try:
    plan = json.loads(pr.stdout)
  except ValueError as e:
    print(f"PLAN UNAVAILABLE: rebase-plan.py --json did not produce JSON ({e}).\n"
          f"  rc={pr.returncode}  stderr={' '.join(pr.stderr.split())[:200]}\n"
          "Nothing was checked. rebase-gate.py exits 1.")
    return 1
  baseline_path = pathlib.Path(a.baseline) if a.baseline else BASELINE
  base = json.loads(baseline_path.read_text()) if baseline_path.exists() else {}

  try:
    srcs = srcs_of(a, plan)
    targets = targets_of(a.port, srcs, plan)
  except PlanShapeError as e:
    # LOUD, and it stops the run. The alternative -- carrying on with whatever ports did
    # parse -- is how a rebase reads as "nothing drifted" when the plan was not understood.
    print(f"PLAN SHAPE BROKEN: {e}\nNothing was checked. rebase-gate.py exits 1.")
    return 1
  if not targets:
    # An empty TALLY is the shape of the bug being fixed: it reads as "nothing to report"
    # when it means "nothing was checked". Name it.
    print(f"NO TARGETS: {' '.join(srcs) if not a.port else a.port} "
          "maps to no port that exists. Nothing was checked.")
    return 1

  if a.record:
    rev, doc, skipped = upstream_of(targets, plan), {"lanes": {}, "hunks": {}}, 0
    for port, oracles in targets:
      bend = REPO / port
      if not oracles or not bend.exists():
        skipped += 1
        continue
      _, now = run_port(bend, oracles, not a.no_native)
      doc["lanes"][port] = now  # empty lanes are KEPT: a dropped lane cannot be counted as lost
      # The hunks a later UNCHANGED has to name: which upstream file(s) the port reads, the
      # computed API delta of each, and the real diff's line counts. Computed, never typed.
      doc["hunks"][port] = {
        f: {"api_delta": plan["api_delta"].get(f, {}), "diff_stat": diff_stat(f)}
        for f in rev[port]}
    baseline_path.parent.mkdir(parents=True, exist_ok=True)
    baseline_path.write_text(json.dumps(doc, indent=1))
    print(f"recorded baseline for {len(doc['lanes'])} ports -> {baseline_path}"
          + (f"; SKIPPED {skipped} target(s) with no oracle or no .bend file, which is why "
             "they are absent from the file" if skipped else ""))
    return 0

  verdicts, tally, missing = [], {}, []
  rev = upstream_of(targets, plan)
  for port, oracles in targets:
    bend = REPO / port
    if not bend.exists():
      # Named rather than `continue`d: a target that is not a file is not a pass, and a
      # silently dropped port is the exact shape that hid here for an hour.
      missing.append(port)
      verdicts.append({"port": port, "state": NOT_STARTED,
                       "why": f"NO SUCH FILE: {bend}. The plan maps an upstream file to a port "
                              "path that does not exist; nothing was checked"})
      tally[NOT_STARTED] = tally.get(NOT_STARTED, 0) + 1
      continue
    if not oracles:
      verdicts.append({"port": port, "state": NOT_STARTED,
                       "why": "no oracle wired in BASE_ORACLES -- nothing can be claimed"})
      tally[NOT_STARTED] = tally.get(NOT_STARTED, 0) + 1
      continue
    v, _ = gate_port(bend, oracles, base, not a.no_native,
                     files={f: plan["api_delta"].get(f, {}) for f in rev[port]})
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
#
# ONE ORACLE PER PORT, ON PURPOSE. A lane is keyed `cpython:<STEM>` (see run_port), so a
# second oracle on the same port must share the first's STEM to be distinguishable at all,
# and GUARD 4 then demands that the two lanes share a row NAME -- which is only true if they
# are the same question. Two different questions on one port do not compose here, and wiring
# them anyway is how a lane goes missing without a word.
#
# The 3 -> 9 widening below is not typing names into a dict. Every added pair was MEASURED by
# .agents/slop/rebase-scan-oracles.py -- which runs the .bend, runs the oracle, and intersects
# the row-name SETS -- and each is recorded with its shared-row count, because a count is what
# tells a reader whether the pair compares 543 claims or 10:
#
#   uop/spec.bend          11    uop/ops.bend             62
#   codegen/opt/search.bend 10    runtime/ops_rdma.bend  389
#   runtime/ops_nv.bend   543    runtime/ops_metal.bend  14
#   runtime/support/hcq2.bend 157
#
# 3 -> 21 working oracles, and 29 of the 50 gated ports still have no CPython oracle at all.
# That residue is the structural gap, it is a fact about ORACLE AUTHORSHIP rather than about
# this tool, and NOT-STARTED is the only honest thing this tool can say about them.
BASE_ORACLES = {
  # -- working, measured. `shared` is the number of row NAMES the port and the oracle both
  #    print, so it is the number of claims CPython actually corroborates --
  "tinybendygrad/runtime/support/hcq2.bend": [".agents/slop/hcq2-oracle.py"],       # 157
  "tinybendygrad/runtime/ops_rdma.bend": [".agents/slop/oracle_rdma_gate.py"],      # 389
  "tinybendygrad/runtime/ops_nv.bend": [".agents/slop/nv-oracle.py"],               # 543
  "tinybendygrad/runtime/ops_metal.bend": [".agents/slop/mt_seam_rows.py"],         #  14
  "tinybendygrad/uop/ops.bend": [".agents/slop/rebase-oracle-ops.py"],             #  62
  "tinybendygrad/uop/spec.bend": [".agents/slop/rebase-oracle-spec.py"],           #  11
  "tinybendygrad/codegen/opt/search.bend": [".agents/slop/rebase-oracle-search.py"],  # 10
  # -- the 2026-10-03 widening, 3 -> 21. Every one measured by rebase-scan-oracles.py, and
  #    every one chosen because the oracle imports and CALLS tinygrad rather than restating
  #    the port. A row whose expectation is a Python def of the thing under test is not a
  #    test, so the criterion for wiring one was an import of `tinygrad` plus a shared row
  #    name -- not merely that the numbers happen to match.
  "tinybendygrad/runtime/support/usb.bend": [".agents/slop/usb-oracle-run.py"],     # 939
  "tinybendygrad/schedule/prepare.bend": [".agents/slop/prepare-oracle.py"],       # 321
  "tinybendygrad/renderer/ptx.bend": [".agents/slop/ptx-s3-oracle.py"],            # 281
  # stage2 is the ptx.py half this file prints. stage1 is tc.bend's question and
  # shares 0 names, so wiring `rows` would compare the same 228 and nothing more.
  # 105 other port rows use legacy dtype spellings in the ROW KEY (`half` vs
  # `f16`) and so do not intersect; aligned values agree. The six that did
  # intersect and disagree were stale `py=` literals, fixed against a live call.
  "tinybendygrad/renderer/tc_ptx.bend": [".agents/slop/tcptx-oracle.py stage2"],  # 228
  "tinybendygrad/renderer/nir_llvmir.bend": [".agents/slop/nl/nl-oracle.py"],      # 201
  "tinybendygrad/viz/serve.bend": [".agents/slop/vz/viz_oracle.py"],               # 176
  "tinybendygrad/runtime/support/c.bend": [".agents/slop/c-oracle.py"],            # 129
  "tinybendygrad/uop/fold.bend": [".agents/slop/mm-lift-gate.py"],                 # 126
  # -- the oracle-WIRING unit, +2. Both oracles already existed and both import and CALL
  #    tinygrad; neither port had been wired to them. Measured over all THREE lanes
  #    (interpreted, compiled native, CPython) with .agents/slop/wire-lanes.py, never inferred
  #    from a filename:
  #      sqtt.bend 1033 interpreted / 1033 native / 1324 oracle rows, 1015 shared, 0
  #                 disagreements; 18 of its row names lie outside the oracle's set. PROBE-
  #                 RECORDED and re-gated: UNCHANGED, zero rows moved. This one is recordable.
  #      elf.bend   353 interpreted / 353 native / 1042 oracle rows, all three pairs agree,
  #                 and PORT FULLY COVERED: 0 of its 353 row names are ungated, which is a
  #                 stronger claim than any other entry in this dict can make.
  #
  #    BOTH WERE INVISIBLE TO rebase-scan-oracles.py, which finds candidates with
  #    `re.search(r"(oracle|gate)", p.name)`. Neither filename contains either substring, so
  #    the survey structurally COULD NOT list them, and the "no oracle at all" count included
  #    two ports that have had a working CPython oracle for hours. Its candidate filter -- not
  #    the absence of an oracle -- is part of why this gap looked as large as it did.
  # ⚠ elf.bend IS CORRECT AND MUST NOT BE RECORDED IN rebase/baseline.json.
  #   PROBE-RECORDED and re-gated, elf.bend came back RE-PORTED with 8+ rows "moved", and not
  #   ONE of the 353 gated rows moved. The movement is in 14 rows the ORACLE prints and the
  #   PORT DOES NOT -- `elf_built_*`, which embed the runtime addresses of the `libstub.dylib`
  #   the fixtures are linked against, so ASLR changes them on every process launch. Measured:
  #   two consecutive `elf_rows.py` processes differ on exactly those 14 rows and on ZERO of the
  #   353 shared ones. Recording elf would freeze a lane that can never report UNCHANGED and
  #   would train the reader to read RE-PORTED as "something drifted". Same species as
  #   `ops_cpu`'s `findlib_*` rows and 74x smaller: 14 rows of 1042, none of them gated.
  "tinybendygrad/runtime/support/elf.bend": [".agents/slop/elf_rows.py"],            #  353
  "tinybendygrad/renderer/amd/sqtt.bend": [".agents/slop/sqtt_spec.py"],            # 1015
  # 84 of 233, measured 2026-10-03 after the print-shape fix in ga-oracle.py.
  # strip_enc 18 + norm_field 50 + map_flat 16. All three CALL generate.py
  # (_strip_enc:48, _norm_field:56, _map_flat:61) — not a Python reimplementation
  # of the port. 0 disagreements once the oracle emits `[val]   py=[val]`, the
  # shape `g` prints. The other 149 port rows are lines of generated Python that
  # rows() splits on `=`; the oracle names that text `tag | line`, so they do
  # not intersect. Not recorded: GUARD 1 would freeze the oracle's 554 ungated
  # rows (parse_xml of a fetched ISA zip, a pdf-error class).
  "tinybendygrad/renderer/amd/generate.bend": [".agents/slop/ga-oracle.py"],       # 84
  "tinybendygrad/nn/onnx.bend": [".agents/slop/onnx-gate.py"],                     # 123
  "tinybendygrad/mixin/elementwise.bend": [".agents/slop/ew-gate.py"],             #  71
  "tinybendygrad/mixin/op.bend": [".agents/slop/mixin-op-gate.py"],                #  32
  "tinybendygrad/tensor.bend": [".agents/slop/tensor-gate.py"],                   #  30
  "tinybendygrad/codegen/simplify.bend": [".agents/slop/xd1/rw-oracle.py"],        #  28
  "tinybendygrad/nn/__init__.bend": [".agents/slop/nn-init-gate.py"],             #  24
  "tinybendygrad/codegen/gpudims.bend": [".agents/slop/xd1/rw-gate-oracle.py"],    #  24
  "tinybendygrad/runtime/ops_cpu.bend": [".agents/slop/cpulink_oracle.py"],        #   3
  # 59 of the port's 85. The other 26 are the port's own encodings (table ids,
  # constructor tags, a completion sentinel, a hardcoded b64 flag, synthetic
  # core_find fixtures, and one assertion string no real tensor core emits).
  # Measured 2026-10-03 with PYTHONPATH unset: the editable install imports, so
  # the earlier "needs PYTHONPATH=." reason for leaving this unwired was wrong.
  # The 19 string disagreements were the oracle's repr(), not the port: CPython's
  # fields contain no quote characters (ops_python.py:169-177).
  "tinybendygrad/runtime/ops_python.bend": [".agents/slop/ops-python-render-oracle.py"],  # 59
  # 409 of the port's 520, 0 disagree, measured 2026-10-03. The oracle used to
  # eval ops_amd.py:858 by number; that line is now `isinstance(..., USBIface)`
  # and the target decomposition is at :862, selected by text. 111 port rows
  # are ungated (init trace, differently-keyed names). Not --record'ed: the
  # oracle emits 601 further rows, and GUARD 1 would freeze them. MOCKUSBIface
  # is isinstance-USB (`ops_amd.py:858`) and the port's `is_usb` does not say
  # so; no shared row names that fact, so it is not in the 409.
  "tinybendygrad/runtime/ops_amd.bend": [".agents/slop/amd_oracle.py"],          # 409
  # 85 shared, 0 disagree, measured against `--gate` (imports xd1/head, prints the
  # port's bracket shape). The vendored tree is a hybrid — ops.py at HEAD, render.py
  # at the pin — and pyrender there disagrees on 18 rows the port gets right. Wiring
  # that tree would be BROKEN on every run. `--gate` is the HEAD call.
  "tinybendygrad/uop/render.bend": [".agents/slop/xd1/render-gate-oracle.py --gate"],  # 85
  # -- the no-candidate unit, 2026-10-03. Each number is the intersection with
  #    the port's own rows, measured by running the oracle and the cached port
  #    rows, then re-checked by the control. A smaller number is the honest one.
  #    llvmir: 323 of 323. The file was deleted in 668d3194d (`li/li-oracle.py`);
  #    the filename sweep could not see a file that was no longer on disk. Restored
  #    as llvmir-oracle.py. It calls renderer.llvmir. Default argv is `rows`.
  "tinybendygrad/renderer/llvmir.bend": [".agents/slop/llvmir-oracle.py"],       # 323
  # qcom: 312 of 750. Calls Q.ctz/parity/pkt*/flag/_qreg_exec/_read_lib and
  # getattr(mesa/kgsl). Omitted: qc_ctz_zero (CPython -1, port 32, ops_qcom.py:43),
  # the U32 miss sentinels (not a CPython return), and the stage-2 ELF walk
  # qc_check.py re-derives. qc_regfwd_/qcregreg_ are tautological True and unprinted.
  "tinybendygrad/runtime/ops_qcom.bend": [".agents/slop/qcom-oracle.py"],        # 312
  # indexing: 104 of 252. ALWAYS_CONTIGUOUS, data_srcs, broadcast_axes, argsort.
  # mv_* is arena-slot identity; apply_movement_op does not return those ids.
  "tinybendygrad/schedule/indexing.bend": [".agents/slop/indexing-oracle.py"],   # 104
  # dtype: 99 of 164 on the live tree (the 14:33 cache's 147 was stale).
  # The rest are interning-order rows plus lgu, which the port prints
  # `refused:unported` where CPython builds a WHERE. Not gated.
  "tinybendygrad/codegen/decomp/dtype.bend": [".agents/slop/dtype-oracle.py"],   #  99
  # rangeify: 31 of 126. rf-rows.py calls rangeify and has neither oracle nor gate
  # in its name, so the filename sweep could not list it. 3 rows are a different
  # field (AxisType.WEAK vs the axis index) and are not emitted.
  "tinybendygrad/schedule/rangeify.bend": [".agents/slop/rangeify-oracle.py"],   #  31
  # jit: 18 of 137. Four rows disagree: DEV=NULL says 'NULL' where the port baked
  # 'PYTHON', and jit_oracle's cap() returned 'none' for two log lines.
  "tinybendygrad/engine/jit.bend": [".agents/slop/jit-oracle.py"],               #  18
  # device: DELIBERATELY NOT WIRED. Its oracle runs, exits 0, prints 18 rows, and 18 of
  #    them are shared with the port's 105 -- and `allow_lower` disagrees, PERMANENTLY.
  #    CPython says 1, device.bend says 0, and CPython is right. device.py:29-31:
  #      29  def __getitem__(self, ix:str) -> Compiled:
  #      30    ix = self.canonicalize(ix)          # canonicalizes FIRST
  #      31    assert ALLOW_DEVICE_USAGE or ix.split(":")[0] in ["DISK","NPY","PYTHON"]
  #    `_canonicalize` upper-cases the stem (device.py:26), so line 31 already sees
  #    `PYTHON:1` and the assert PASSES. Measured by CALLING `Device['python:1']` under
  #    `Context(ALLOW_DEVICE_USAGE=0)`: PYTHON:1 -> 1, python:1 -> 1, METAL -> 0.
  #    device.bend:329 and :338 assert the opposite twice ("`__getitem__` asserts before it
  #    canonicalizes", "compares the head exactly as it arrived") while citing :30 as the
  #    canonicalize and :31 as the assert -- the order it then denies. Its `allowed` omits
  #    line 30. Same at pin 6c3d401cf324, HEAD and upstream/master, so NOT rebase drift.
  #    MEASURED through the real gate: BROKEN, rc=1, `allow_lower` named in both the
  #    interpreted and the native pair. Wiring it would put a permanently-BROKEN lane in
  #    every tree sweep, which trains the reader to read BROKEN as normal -- the failure
  #    the elf.bend comment above is about. PORT BUG REPORTED, NOT FIXED (device.bend is
  #    not this unit's file). The oracle is left on disk so the next reader does not
  #    rebuild it.
  # null: 7 of 180. The five opcodes and two EMULATE messages NullDevice raises.
  # The other two messages this oracle prints are not rows the port prints.
  "tinybendygrad/runtime/ops_null.bend": [".agents/slop/null-oracle.py"],        #   7
  # `ops_cpu` is wired on THREE shared row names out of the oracle's 20, and that is named
  # rather than dressed up: 17 of its rows are `findlib_*` HOST answers (where libm and
  # libobjc live on THIS machine) which the port cannot be expected to reproduce off-Mac,
  # and the 3 that remain -- cpu_lib_objc, cpu_link_libs_10, cpu_link_libs_n -- are real.
  # A gate's strength is the intersection, so the honest number is 3 and it is in the
  # comment above, not 20.
  # -- deliberately dead, wired so BROKEN is reachable on the REAL tree and not only over
  #    synthetic fixtures. Do NOT "fix" these by removing them; that is what NOT-STARTED and
  #    this comment are for. dtype_tables.py exits 0 printing TSV, so rows() finds no `=`
  #    (GUARD 2, "compared nothing"); renderer_oracle.py `cstyle` exits 1 AND shares 0 of
  #    225 row names (GUARD 3, and its stderr is printed rather than swallowed). --
  "tinybendygrad/dtype.bend": [".agents/slop/oracle/dtype_tables.py"],
  "tinybendygrad/renderer/cstyle.bend": [".agents/slop/renderer_oracle.py cstyle"],
}


if __name__ == "__main__":
  sys.exit(main())