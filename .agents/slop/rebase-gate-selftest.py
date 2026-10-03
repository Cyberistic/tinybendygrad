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

The tests run against SYNTHETIC ports and a synthetic baseline, plus THREE REAL lane pairs
named in SUPERSET_LANES. They do not touch tinygrad/, do not write any .bend file, and do
not touch the real baseline.json. They DO run three ports and three oracles, because the
superset check is only worth anything over real lane output: a parser that passes on
synthetic text and drops one row out of prepare-oracle.py is the failure itself, and 38 wired
gates share that parser.

    .venv/bin/python .agents/slop/rebase-gate-selftest.py

Use .venv/bin/python. PATH's python3 cannot import tinygrad at all, and every oracle here
exits 1 under it -- which the selftest then has to report as a FAILED LANE rather than as a
row count.
"""
import pathlib, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
GATE = HERE / "rebase-gate.py"
REPO = HERE.parent.parent

scan = load_module = None  # replaced below; see load_scan()


def load_scan():
  """rebase-scan-oracles.py: the owner of the cache rule, of the cache KEYS, and -- by
  importing it -- of the row parser. Loaded, never restated: a test that re-implements the
  rule under test is testing the test."""
  import importlib.util
  spec = importlib.util.spec_from_file_location(
    "rebase_scan_oracles", HERE / "rebase-scan-oracles.py")
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


def load_gate(name):
  """Import rebase-gate.py under a private name, so one check can hold two of them with
  different `rows` in place. The gate is loaded, never restated."""
  return load_scan().load_module(GATE, name)


def rows_before_fix(text):
  """`rows()` as it stood before the empty-name rule. This is the CONTROL'S REFERENCE, not
  the rule: a superset check has to compare the fixed parser against what the tool used to
  answer with, and re-typing that here is the only way to keep it from drifting back into the
  tool itself."""
  out = {}
  for line in text.splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k.strip()] = v.strip()
  return out


class FakeBend:
  """Just enough of a .bend path for gate_port(). It is never read -- run_port is replaced."""
  def __init__(self, p): self.p = pathlib.Path(p)
  def __str__(self): return str(self.p)
  @property
  def stem(self): return self.p.stem
  def relative_to(self, other): return self.p


def verdict_of(base_rows, moved_rows, dead=False, base_doc=None, port="/tmp/probe.bend",
               oracle_rows=None, no_baseline=False):
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
  if no_baseline:
    # A baseline document with NO entry for this port, which is what every port without a
    # --record looks like to baseline_for(): None, not {}.
    doc = {"lanes": {}, "hunks": {}}
  else:
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

  # ⚠ THE ORDER THAT REPORTED A WRONG VERDICT. GUARD 4 compares two lanes of THIS RUN and
  # reads nothing from baseline.json, so its result does not depend on a recording -- and it
  # used to sit BELOW the "no baseline recorded" shortcut. Measured on ops_nv with one planted
  # disagreement: the port and a corrupted oracle disagreed, and the gate answered
  # "NOT-STARTED: no baseline recorded" with rc=0. Any un-recorded port could hide a live
  # disagreement in exactly that state, and NOT-STARTED is a verdict a reader BELIEVES.
  check("a live disagreement is BROKEN even with NO baseline recorded",
        verdict_of({"a": "1"}, {"a": "1"}, oracle_rows={"a": "2"}, no_baseline=True),
        "BROKEN", "disagree")
  check("a live disagreement is BROKEN even when the baseline is EMPTY",
        verdict_of({}, {"a": "1"}, base_doc={"lanes": {"/tmp/probe.bend": {}},
                                               "hunks": {}}, oracle_rows={"a": "2"}),
        "BROKEN", "disagree")
  # ...while the OTHER direction still holds: lanes that DO agree, with no baseline, are
  # NOT-STARTED and NOT UNCHANGED, because "they agree right now" is not "nothing moved".
  check("lanes that agree with NO baseline -> NOT-STARTED, not UNCHANGED",
        verdict_of({"a": "1"}, {"a": "1"}, oracle_rows={"a": "1"}, no_baseline=True),
        "NOT-STARTED", "no baseline recorded")
  # GUARD 4 must not be a loophole: it is baseline-free, so it must still fire for a port
  # whose baseline lane was recorded with ZERO rows (which is NOT-STARTED, not a pass).
  check("a live disagreement beats a ZERO-ROW baseline lane too",
        verdict_of({}, {"a": "1"}, oracle_rows={"a": "2"}),
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

  fails += plan_contract()
  fails += oracle_template()

  print()
  if fails:
    print(f"{len(fails)} FAILED: {', '.join(fails)}")
    return 1
  print("all states reachable -- a gate that cannot fail is not a gate")
  return 0


def plan_contract():
  """The cross-file contract with rebase-plan.py, which is where this tool CRASHED.

  `plan["port"][src]` was `str | None` and became `[str, ...] | None` in commit d4f647349,
  for a good reason -- one port can be the port of SEVERAL upstream files, which is how
  codegen/rewriter.bend came to be the port of three. rebase-gate.py kept `[p]`, so
  ports_of() returned a list of lists and main() raised `TypeError: unhashable type: 'list'`
  on its DEFAULT invocation, which took every flag and the whole-tree sweep with it.

  The selftest was GREEN the whole time, because it drove gate_port() and the defect was in
  main()'s TARGET CONSTRUCTION. So the coverage it lacked is exactly the coverage added
  here: ports_of() and targets_of(), through BOTH shapes and through the shapes neither
  should be allowed to answer quietly."""
  fails = []

  def ok(name, cond, detail=""):
    print(f"  {'PASS' if cond else 'FAIL'}  {name}" + (f"\n        {detail}" if detail else ""))
    if not cond:
      fails.append(name)

  g = load_gate("rebase_gate_plan")
  LIST, STR = "tinybendygrad/codegen/rewriter.bend", "tinybendygrad/codegen/kernel.bend"
  listy = {"port": {"tinygrad/codegen/__init__.py": [STR],
                    "tinygrad/codegen/simplify.py": [LIST]}}
  strr = {"port": {"tinygrad/codegen/__init__.py": STR,
                   "tinygrad/codegen/simplify.py": LIST}}

  for label, plan, want in (("list", listy, [STR]), ("str", strr, [STR])):
    got = g.ports_of("tinygrad/codegen/__init__.py", plan)
    ok(f"plan['port'] as {label} -> {want[0]}", got == want, f"got {got}")

  # The shape that CRASHED the tool: a list OF lists. It must raise, not flatten and not
  # answer "no ports" -- the latter is 213 ports answering NOT-STARTED, which reads exactly
  # like "nothing drifted".
  nested = {"port": {"tinygrad/codegen/__init__.py": [[STR]]}}
  try:
    g.ports_of("tinygrad/codegen/__init__.py", nested)
    ok("a list OF lists is named, not flattened", False, "ports_of returned instead of raising")
  except g.PlanShapeError as e:
    ok("a list OF lists is named, not flattened", True, str(e)[:100])
  for bad in ({"port": {"x": 7}}, {"port": {"x": {"a": 1}}}):
    try:
      g.ports_of("x", bad)
      ok(f"a {type(list(bad['port'].values())[0]).__name__} value is named", False, "returned")
    except g.PlanShapeError as e:
      ok(f"a {type(list(bad['port'].values())[0]).__name__} value is named", True, str(e)[:80])
  ok("a missing 'port' key answers empty, not crash", g.ports_of("x", {}) == [])

  # targets_of is what main() calls, and the de-duplication there is what raised.
  t = g.targets_of(None, ["tinygrad/codegen/__init__.py", "tinygrad/codegen/simplify.py"], listy)
  ok("targets_of de-duplicates by PORT across upstream files",
     t == [(STR, ()), (LIST, ())], f"got {t}")
  ok("targets_of --port takes the path verbatim",
     g.targets_of(STR, [], listy) == [(STR, ())], f"got {g.targets_of(STR, [], listy)}")

  # EXTRA_PORTS must stay NON-redundant. Eight of nine entries were removed precisely
  # because rebase-plan.py's header map already derived them; nothing would stop a later
  # header edit from making a kept one redundant again, which is how all eight got here.
  hp = header_ports()
  redundant = {src: [p for p in ps if p in hp.get(src, [])] for src, ps in g.EXTRA_PORTS.items()}
  redundant = {k: v for k, v in redundant.items() if v}
  ok("every EXTRA_PORTS entry is one header_ports() CANNOT see", not redundant,
     f"redundant: {redundant}" if redundant else f"{len(g.EXTRA_PORTS)} entry, all needed")
  gone = [p for ps in g.OBSOLETE_EXTRA_PORTS.values() for p in ps
          if not (REPO / p).exists()]
  ok("every removed EXTRA_PORTS target that names a file still exists under its new name",
     not gone, f"dead: {gone}" if gone else "")
  return fails


def header_ports():
  """rebase-plan.py's header map, loaded rather than re-implemented."""
  import importlib.util
  spec = importlib.util.spec_from_file_location("rebase_plan_hp", HERE / "rebase-plan.py")
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m.header_ports()


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
# `ORACLE_CONFORMANCE` is the list of oracles WIRED into BASE_ORACLES, and the loop drives
# the SAME `gate_port()` main() calls with each one's own row NAMES as the fixture. A new
# oracle that cannot pass this is not finished.
#
# ⚠ THIS LIST LIED. It carried a header saying these were "the oracles this session wired
# into BASE_ORACLES" and named EIGHT, while BASE_ORACLES held THREE and only ONE of the
# eight. A conformance roster that over-reports is worse than none: it reads as coverage of
# the thing this file exists to guarantee. So the check below is now EQUALITY between the
# roster and BASE_ORACLES, in both directions, and the shared-row counts are MEASURED by
# rebase-scan-oracles.py against the live tree rather than typed here and left to rot.
# THE ROSTER IS WRITTEN ONCE, HERE, AND BASE_ORACLES IS BUILT FROM IT. It started the other
# way round: BASE_ORACLES held three entries and this list held nine, its header claimed all
# nine were "wired", and the equality check that would have caught the difference did not
# exist. A conformance roster that over-reports is worse than none -- it reads as coverage of
# the thing this file exists to guarantee.
#
# shared = row NAMES the port and the oracle both print, MEASURED by rebase-scan-oracles.py.
# It is the number of claims CPython actually corroborates, and for two pairs it is far below
# what the oracle emits, which is stated in the comment rather than rounded away.
ORACLE_CONFORMANCE = {
  # port: (oracle spec, shared row names, kind)
  # kind "live" -- the six synthetic states are driven against this oracle's own row names
  # kind "dead" -- wired to make BROKEN reachable on the REAL tree, so there is no shared
  #   name to drive (0 BY DESIGN) and the assertion is a real subprocess run of the gate
  "tinybendygrad/uop/spec.bend": (".agents/slop/rebase-oracle-spec.py", 11, "live"),
  "tinybendygrad/uop/ops.bend": (".agents/slop/rebase-oracle-ops.py", 62, "live"),
  "tinybendygrad/codegen/opt/search.bend": (".agents/slop/rebase-oracle-search.py", 10, "live"),
  "tinybendygrad/runtime/ops_rdma.bend": (".agents/slop/oracle_rdma_gate.py", 389, "live"),
  "tinybendygrad/runtime/ops_nv.bend": (".agents/slop/nv-oracle.py", 543, "live"),
  "tinybendygrad/runtime/support/hcq2.bend": (".agents/slop/hcq2-oracle.py", 157, "live"),
  "tinybendygrad/runtime/ops_metal.bend": (".agents/slop/mt_seam_rows.py", 14, "live"),
  "tinybendygrad/runtime/support/usb.bend": (".agents/slop/usb-oracle-run.py", 939, "live"),
  "tinybendygrad/schedule/prepare.bend": (".agents/slop/prepare-oracle.py", 321, "live"),
  "tinybendygrad/renderer/ptx.bend": (".agents/slop/ptx-s3-oracle.py", 281, "live"),
  # 228 of 333. The other 105 are legacy dtype spellings in the row KEY, measured
  # 2026-10-03: aligned values agree, so the intersection is the honest number.
  "tinybendygrad/renderer/tc_ptx.bend": (".agents/slop/tcptx-oracle.py stage2", 228, "live"),
  "tinybendygrad/renderer/nir_llvmir.bend": (".agents/slop/nl/nl-oracle.py", 201, "live"),
  "tinybendygrad/viz/serve.bend": (".agents/slop/vz/viz_oracle.py", 176, "live"),
  "tinybendygrad/runtime/support/c.bend": (".agents/slop/c-oracle.py", 129, "live"),
  "tinybendygrad/uop/fold.bend": (".agents/slop/mm-lift-gate.py", 126, "live"),
  # -- the oracle-WIRING unit's two. The equality check below is what caught them: BASE_ORACLES
  #    gained two entries and this roster did not, and the FAIL names exactly the two. That is
  #    the contract working -- one file changed, the other file said so.
  #    elf: 353 shared of the port's 353 rows, so PORT FULLY COVERED. It is the only "live"
  #    entry with zero uncovered rows. Its oracle emits 689 further rows, 14 of which are
  #    `libstub.dylib` runtime addresses that ASLR changes every launch -- none of them shared,
  #    so GUARD 4 is unaffected and GUARD 1 is why elf must never be recorded.
  "tinybendygrad/runtime/support/elf.bend": (".agents/slop/elf_rows.py", 353, "live"),
  #    sqtt: 1015 of 1033. Probe-recorded and re-gated UNCHANGED, so this one IS recordable.
  "tinybendygrad/renderer/amd/sqtt.bend": (".agents/slop/sqtt_spec.py", 1015, "live"),
  # 84 of 233. The other 149 are generated-Python lines rows() splits on `=`,
  # which the oracle names `tag | line`, so they are not shared. Measured
  # 2026-10-03: 0 disagreements after the print-shape fix.
  "tinybendygrad/renderer/amd/generate.bend": (".agents/slop/ga-oracle.py", 84, "live"),
  "tinybendygrad/nn/onnx.bend": (".agents/slop/onnx-gate.py", 123, "live"),
  "tinybendygrad/mixin/elementwise.bend": (".agents/slop/ew-gate.py", 71, "live"),
  "tinybendygrad/mixin/op.bend": (".agents/slop/mixin-op-gate.py", 32, "live"),
  "tinybendygrad/tensor.bend": (".agents/slop/tensor-gate.py", 30, "live"),
  "tinybendygrad/codegen/simplify.bend": (".agents/slop/xd1/rw-oracle.py", 28, "live"),
  "tinybendygrad/nn/__init__.bend": (".agents/slop/nn-init-gate.py", 24, "live"),
  "tinybendygrad/codegen/gpudims.bend": (".agents/slop/xd1/rw-gate-oracle.py", 24, "live"),
  # 3 of the oracle's 20 rows, and the other 17 are `findlib_*` HOST answers. The strength
  # of a gate is the intersection, so 3 is the number and the comment in BASE_ORACLES says
  # which 3.
  "tinybendygrad/runtime/ops_cpu.bend": (".agents/slop/cpulink_oracle.py", 3, "live"),
  # 59 of 85. The other 26 are port-internal encodings, not CPython outputs.
  # PYTHONPATH unset still imports (editable install); measured, not assumed.
  "tinybendygrad/runtime/ops_python.bend": (".agents/slop/ops-python-render-oracle.py", 59, "live"),
  # 409 of 520. The other 111 are ungated (init trace, differently-keyed names).
  # Not a claim about those 111. Measured 2026-10-03, 0 disagreements.
  "tinybendygrad/runtime/ops_amd.bend": (".agents/slop/amd_oracle.py", 409, "live"),
  # 85 of the port's 86 naive keys. The leftover is `py`, an indented continuation
  # the parser invents; it is port-only and not a claim. HEAD, not the vendored hybrid.
  "tinybendygrad/uop/render.bend": (".agents/slop/xd1/render-gate-oracle.py --gate", 85, "live"),
  # -- the no-candidate unit. Counts are the measured intersection, not the
  #    oracle's row count. llvmir is 323 of the port's 323.
  "tinybendygrad/renderer/llvmir.bend": (".agents/slop/llvmir-oracle.py", 323, "live"),
  "tinybendygrad/runtime/ops_qcom.bend": (".agents/slop/qcom-oracle.py", 312, "live"),
  "tinybendygrad/schedule/indexing.bend": (".agents/slop/indexing-oracle.py", 104, "live"),
  "tinybendygrad/codegen/decomp/dtype.bend": (".agents/slop/dtype-oracle.py", 99, "live"),
  "tinybendygrad/schedule/rangeify.bend": (".agents/slop/rangeify-oracle.py", 31, "live"),
  "tinybendygrad/engine/jit.bend": (".agents/slop/jit-oracle.py", 18, "live"),
  "tinybendygrad/runtime/ops_null.bend": (".agents/slop/null-oracle.py", 7, "live"),
  "tinybendygrad/dtype.bend": (".agents/slop/oracle/dtype_tables.py", 0, "dead"),
  "tinybendygrad/renderer/cstyle.bend": (".agents/slop/renderer_oracle.py cstyle", 0, "dead"),
}

# NOT WIRES, and named here as well as in BASE_ORACLES because a roster that only records
# what passed cannot answer "why is this one missing?" -- which is the question the next
# reader asks about every port that is NOT-STARTED.
#
#   tinybendygrad/device.bend  device-oracle.py  18 of 105 shared, 1 DISAGREES.
#       CPython 1, the port 0, CPython right. device.py:30 canonicalizes BEFORE the assert
#       at :31, and `_canonicalize` upper-cases the stem (device.py:26), so `python:1`
#       passes. Measured by calling `Device['python:1']` under `Context(ALLOW_DEVICE_USAGE=0)`,
#       and the real gate answers BROKEN rc=1 naming `allow_lower`. A permanently-BROKEN
#       lane in every sweep would teach the reader that BROKEN is normal. PORT BUG, REPORTED.
ORACLE_NOT_WIRED = {
  "tinybendygrad/device.bend": ("allow_lower: CPython 1 (device.py:30 canonicalizes before "
                                "the assert at :31), device.bend 0 -- proven port bug"),
}


def dead_lane_is_broken(port, oracle):
  """Run the REAL gate -- real run_port, real bend file, real oracle script -- on a
  deliberately-dead pair and require BROKEN.

  This is the state the whole tool exists for, and the one a synthetic fixture cannot supply:
  GUARD 2 and GUARD 4 both need lanes that were actually produced. `dtype_tables` exits 0
  printing TSV (so `rows()` finds no `=`), and `renderer_oracle.py cstyle` exits 1 with
  `KeyError: dtypes.weakint` inside upstream cstyle. Both were BROKEN-by-construction in the
  briefing, and a wiring change must never quietly turn either into a pass.

  IT CALLS gate_port(), NOT main(). That is deliberate and it is a correction: shelling out to
  the whole gate took 4m25s per port -- measured, and almost entirely `rebase-plan.py` re-walking
  every header -- which made the selftest long enough to be killed by a server restart TWICE.
  gate_port() is the same decision function main() calls; what it does not cover is main()'s
  TARGET CONSTRUCTION, and plan_contract() covers that separately and instantly. Both halves
  are driven, neither is driven twice, and neither is driven through an interpreter."""
  g = load_gate(f"dead_lane_{pathlib.Path(oracle.split()[0]).stem}")
  bend = FakeBend(str(REPO / port))
  v, _ = g.gate_port(bend, [oracle], {"lanes": {}, "hunks": {}}, native=False)
  return v["state"] == "BROKEN", (f"{v['state']}: {v['why'][:150]}\n"
                                 f"        rows {v['row_counts']}")


def oracle_template():
  """Drive the six states through gate_port() for each wired oracle. Returns failure names."""
  g_all = load_gate("rebase_gate_roster")
  wired = {p: o[0] for p, o in g_all.BASE_ORACLES.items()}
  fails = []
  if wired != {p: s for p, (s, _, _) in ORACLE_CONFORMANCE.items()}:
    fails.append("BASE_ORACLES and ORACLE_CONFORMANCE disagree")
    print(f"  FAIL  BASE_ORACLES and ORACLE_CONFORMANCE are the same roster")
    print(f"        only in BASE_ORACLES: { {k: v for k, v in wired.items() if k not in ORACLE_CONFORMANCE} }")
    print(f"        only in conformance: { {k: v for k, v in ORACLE_CONFORMANCE.items() if k not in wired} }")
  else:
    print(f"  PASS  BASE_ORACLES and ORACLE_CONFORMANCE are the same roster "
          f"({len(wired)} oracles)")

  # ORACLE_NOT_WIRED must be DISJOINT from the roster, or "not wired" has stopped meaning
  # anything -- a port can be in both lists and the gate would run it while the file claims
  # it does not. This is the same rot the roster equality check exists for, one list over.
  both = set(ORACLE_NOT_WIRED) & set(wired)
  if both:
    fails.append(f"ORACLE_NOT_WIRED lists a WIRED port: {sorted(both)}")
    print(f"  FAIL  ORACLE_NOT_WIRED is disjoint from the wired roster\n        {sorted(both)}")
  else:
    print(f"  PASS  ORACLE_NOT_WIRED is disjoint from the wired roster "
          f"({len(ORACLE_NOT_WIRED)} named, with reasons)")

  for port, (oracle, shared_n, kind) in ORACLE_CONFORMANCE.items():
    name = pathlib.Path(oracle.split()[0]).name
    if kind == "dead":
      ok, detail = dead_lane_is_broken(port, oracle)
      print(f"  {'PASS' if ok else 'FAIL'}  {name}: wired on purpose, and the REAL gate still "
            f"says BROKEN\n        {detail}")
      if not ok:
        fails.append(f"{name}: dead lane stopped being BROKEN")
      continue
    g = load_gate(f"conformance_{pathlib.Path(oracle.split()[0]).stem}_{shared_n}")
    # THE FIXTURE IS THE ORACLE'S OWN ROW SET, so the states are produced over the names this
    # oracle actually emits. Synthetic names would pass a broken oracle and fail a working
    # one, which is the same inversion as a shape mismatch.
    port_rows = {f"r{i}": str(i) for i in range(max(shared_n, 1))}
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
    bad = [f"{pathlib.Path(oracle.split()[0]).name}: {nm}" for nm, v, ws, wt in cases
           if not (v["state"] == ws and wt.lower() in v.get("why", "").lower())]
    g.run_port = lambda *a, **k: (ok_lanes, {"interpreted": dict(port_rows),
                                             "cpython:o": dict(port_rows)})
    bad_doc = g.baseline_for({"interpreted": dict(port_rows)}, port)
    if bad_doc[0] is not None or "MALFORMED" not in bad_doc[2]:
      bad.append(f"{pathlib.Path(oracle.split()[0]).name}: malformed baseline")
    print(f"  {'PASS' if not bad else 'FAIL'}  {pathlib.Path(oracle.split()[0]).name}: six "
          f"states reachable ({shared_n} shared row names)")
    fails += bad
  return fails


if __name__ == "__main__":
  sys.exit(main())