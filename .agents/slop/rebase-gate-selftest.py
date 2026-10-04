#!/usr/bin/env python3
"""rebase-gate-selftest.py -- prove the gate can SEE the state it exists to catch.

WHY THIS IS A FILE AND NOT A CONVENIENCE. The failure this gate exists for is INVISIBLE BY
CONSTRUCTION: twelve committed files printed 0 rows and a harness reported success, because
zero disagreements and zero comparisons look identical. A detector that has never been shown
failing is indistinguishable from a detector that cannot fail. So each state is produced on
purpose and the gate is required to name it.

THE FIVE STATES, AND WHAT MAKES EACH ONE REACHABLE:
  UNCHANGED         no row value differs from the baseline, and no row was lost
  RE-PORTED         a row value moved, and the moved rows now agree with CPython
  BROKEN            rows went to ZERO, or a lane died, or rows disagree
  NOT-STARTED       nothing was COMPARED -- no oracle wired, or no .bend, or a baseline that
                    cannot be read
  AGREE-UNRECORDED  something WAS compared, every shared row agreed, and no baseline exists.
                    ⚠ THIS STATE WAS MISSING AND ITS ABSENCE WAS THE GAP: reporting it as
                    NOT-STARTED merged "compared clean, nobody wrote it down" with "nobody
                    looked", so 46 of 50 targets read as never-examined when every one of
                    them had just compared clean. never_wired_control() below is what keeps it
                    honest -- the same state must NOT be reachable where nothing ran.

They do not touch tinygrad/, do not write any .bend file, and do not touch the real
baseline.json. Three of these checks carry a control that would FAIL if its rule were removed,
and all three exist because a number was confidently wrong:

  * `cache_rule()` -- rebase-scan-oracles.py printed `84 shared, 84 disagree` against a real
    `726 shared, 0 disagree`, off cache written HOURS earlier. The control ages a scratch cache
    file against its source in BOTH directions, and also refuses a cache that records nothing.
  * `superset()` -- `rows()` used to key on an empty name, so 14 `== SECTION ==` banners counted
    as one row and the oracle reported 2522 rows where it has 2521. It drives `rows()` and the
    pre-fix parser over synthetic text AND over the four real lane pairs in SUPERSET_LANES, both
    sides of every pair, and requires the fixed parser to return every row the old one did. A
    parser that passes on synthetic text and drops one row out of prepare-oracle.py IS the
    failure, and 38 wired gates share that parser -- which is also how some OTHER gate can come
    to agree by comparing nothing.
  * `measure_roster()` -- the conformance roster used to CARRY a shared-row count, and carried a
    STALE one: 84 for a pair that measures 726. The count is measured every run now, through
    rebase-scan-oracles.py's cache and its staleness rule, so no number in this file is typed
    where it can outlive its input. It has to run the real lanes to do it, which is why this
    file runs three ports and three oracles rather than only fixtures.

    .venv/bin/python .agents/slop/rebase-gate-selftest.py

Use .venv/bin/python. PATH's python3 cannot import tinygrad at all, and every oracle here
exits 1 under it -- which the selftest then has to report as a FAILED LANE rather than as a
row count.
"""
import concurrent.futures as cf
import json, os, pathlib, subprocess, sys, tempfile, time

HERE = pathlib.Path(__file__).resolve().parent
GATE = HERE / "rebase-gate.py"
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
# The PINNED interpreter, so no control below can measure the LAUNCHER instead of the port. A
# lane run under PATH's python3 imports no tinygrad, exits 1, prints nothing, and lands in the
# scan cache as `{}` -- which is the very file item 1's control exists to catch.
import oracle_py  # noqa: E402

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


def gate_with(g, doc, rows_by_lane, lanes=None):
  """gate_port() with run_port() stubbed to return exactly the lanes handed over, and the
  baseline document handed over verbatim. The general form verdict_of() wraps; this is the one
  that lets a test state the BASELINE DOCUMENT and the LANES independently, which the
  AGREE-UNRECORDED controls need -- they are about what happens when a document is intact but
  has no entry, versus a document that cannot be read at all."""
  g.REPO = pathlib.Path("/tmp")
  g.run_port = lambda *a, **k: (lanes or {k: {"rc": 0} for k in rows_by_lane}, rows_by_lane)
  return g.gate_port(FakeBend("/tmp/probe.bend"), ["oracle"], doc, native=True)[0]


def never_wired_control():
  """THE CONTROL THAT KEEPS AGREE-UNRECORDED HONEST.

  AGREE-UNRECORDED means "this run compared lane pairs and every shared row agreed". The
  target it must NEVER claim that for is the one where NOTHING ran -- no oracle in
  BASE_ORACLES, or no .bend file. So the control drives exactly that, through the same
  never_wired() main() calls, and requires NOT-STARTED.

  The partition is then checked in BOTH directions, because a one-directional test is half a
  test: every port BASE_ORACLES wires and that exists on disk must be comparable (return None),
  and the only wired port whose oracle is deliberately dead must still be returned as
  comparable, so that its BROKEN verdict -- which is the point of wiring it -- survives.
  """
  g = load_gate("rebase_gate_never_wired")
  fails = []

  def ok(name, cond, detail=""):
    print(f"  {'PASS' if cond else 'FAIL'}  {name}" + (f"\n        {detail}" if detail else ""))
    if not cond:
      fails.append(name)

  # THE CONTROL PORT CHANGED, AND THE OLD CHOICE NO LONGER EXISTED. This used to be
  # `tinybendygrad/device.bend`, with the comment "ORACLE_NOT_WIRED names it, and it exists on
  # disk" -- which stopped being true the moment device.bend was WIRED, and the control that
  # guards AGREE-UNRECORDED would then have failed on a port that is legitimately wired. The
  # assertion below is what makes the choice auditable: the port must be absent from
  # BASE_ORACLES and present on disk, so a control that stops testing an unwired port is a
  # FAIL, not a silent pass.
  unwired = "tinybendygrad/helpers.bend"
  ok("the control port is really unwired",
     unwired not in g.BASE_ORACLES and (REPO / unwired).exists(),
     f"{unwired}: in BASE_ORACLES = {unwired in g.BASE_ORACLES}")
  # AND THE ONE IT REPLACED IS NOW WIRED, so the swap cannot rot into "the port I used to
  # name is unwired again" without anything saying so.
  ok("the port this control used to name is WIRED now, and says why",
     "tinybendygrad/device.bend" in g.BASE_ORACLES
     and "tinybendygrad/device.bend" not in ORACLE_NOT_WIRED,
     f"wired={'tinybendygrad/device.bend' in g.BASE_ORACLES} "
     f"in ORACLE_NOT_WIRED={'tinybendygrad/device.bend' in ORACLE_NOT_WIRED}")
  v = g.never_wired(unwired, REPO / unwired, ())
  ok("a port with NO ORACLE is NOT-STARTED and never AGREE-UNRECORDED",
     v is not None and v["state"] == "NOT-STARTED" and "NOTHING WAS COMPARED" in v["why"],
     f"{v['state']}: {v['why']}" if v else "never_wired returned None -- it would be gated")
  gone = g.never_wired(unwired, REPO / "tinybendygrad/no-such-port.bend", ())
  ok("a port with NO SUCH FILE is NOT-STARTED",
     gone is not None and gone["state"] == "NOT-STARTED" and "NO SUCH FILE" in gone["why"],
     f"{gone['state']}: {gone['why']}" if gone else "never_wired returned None")
  # The other direction: a wired port whose file EXISTS must be comparable, or main() would
  # report every wired port as never-wired and AGREE-UNRECORDED would count nothing.
  unwired_ok = [p for p in g.BASE_ORACLES
                if (REPO / p).exists() and g.never_wired(p, REPO / p, g.BASE_ORACLES[p]) is not None]
  ok("every WIRED port on disk is comparable, so never_wired does not swallow the roster",
     not unwired_ok, f"swallowed: {unwired_ok}" if unwired_ok
     else f"{len(g.BASE_ORACLES)} wired ports checked")
  # And the port wired ON PURPOSE to be BROKEN must not be classified as never-wired: its BROKEN
  # verdict is a reachable state, not a missing wiring. `dtype.bend` only -- cstyle.bend used to
  # be named here too and stopped being true the day it was WIRED off `cstyle-rows`, and a
  # control that keeps asserting a lane is dead after it was opened tests nothing.
  dead = [p for p in g.BASE_ORACLES if p == "tinybendygrad/dtype.bend"]
  ok("the deliberately-BROKEN lane is still classified comparable, not never-wired",
     len(dead) == 1 and all(g.never_wired(p, REPO / p, g.BASE_ORACLES[p]) is None for p in dead),
     f"{dead}")
  return fails


def record_stable_control():
  """A RECORDING MUST NOT BE ABLE TO TURN A RED INTO A GREEN.

  This is the one outcome the whole recording half of this unit is forbidden to produce, so it
  is driven directly: an evidence file that claims a port is `recordable` while its stored rows
  DISAGREE, a second that stores interpreted != native, and a third that is honestly marked
  un-recordable. record_stable() must write only the good one, must leave the others out, must
  preserve an entry it was not asked about, and -- the assertion that matters -- the refused red
  must then read AGREE-UNRECORDED through the real gate, NOT UNCHANGED. A recording that made a
  disagreeing lane report UNCHANGED would be worse than no recording: it would convert the
  gate's most valuable output into a green light and hide the port bug behind it.
  """
  g = load_gate("rebase_gate_record_stable")
  plan = {"port": {}, "api_delta": {}}  # empty, so hunks need no git/rebase-plan subprocess
  GOOD, RED, PARTIAL = ("tinybendygrad/tensor.bend", "tinybendygrad/mixin/op.bend",
                        "tinybendygrad/nn/onnx.bend")
  KEPT = "tinybendygrad/renderer/cstyle.bend"
  # The "honestly EXCLUDED" entry used to be device.bend with the reason "no oracle wired",
  # which became false the day device.bend was wired -- a fixture whose stated reason is no
  # longer true still tests the same code path, so nothing would have failed. helpers.bend
  # carries a reason that is true and MEASURED (it prints zero rows, twice, so no oracle can
  # ever share a name with it) rather than merely plausible.
  EXCLUDED = "tinybendygrad/helpers.bend"
  lanes = {"interpreted": {"a": "1", "b": "2"}, "native": {"a": "1", "b": "2"},
           "cpython:o": {"a": "1", "b": "2"}}
  evidence = {
    GOOD: {"recordable": True, "rows": lanes, "reasons": []},
    RED: {"recordable": True, "reasons": [],
          "rows": {"interpreted": {"a": "1"}, "native": {"a": "1"}, "cpython:o": {"a": "2"}}},
    PARTIAL: {"recordable": True, "reasons": [],
              "rows": {"interpreted": {"a": "1", "only_here": "9"}, "native": {"a": "1"},
                       "cpython:o": {"a": "1"}}},
    EXCLUDED: {"recordable": False, "reasons": ["no oracle wired", "port prints zero rows"]},
  }
  fails = []

  def ok(name, cond, detail=""):
    print(f"  {'PASS' if cond else 'FAIL'}  {name}" + (f"\n        {detail}" if detail else ""))
    if not cond:
      fails.append(name)

  with tempfile.TemporaryDirectory() as td:
    ev = pathlib.Path(td) / "stability.json"
    bl = pathlib.Path(td) / "baseline.json"
    ev.write_text(json.dumps(evidence))
    before = {"lanes": {KEPT: {"interpreted": {"kept": "1"}}}, "hunks": {KEPT: {}}}
    bl.write_text(json.dumps(before))
    written, refused, complaints = g.record_stable(str(ev), bl, plan)
    after = json.loads(bl.read_text())
    ok("only the proven-clean port is written", written == 1 and GOOD in after["lanes"]
       and RED not in after["lanes"] and PARTIAL not in after["lanes"],
       f"written={written} lanes={sorted(after['lanes'])}")
    ok("a DISAGREEING 'recordable' claim is REFUSED, naming the rows",
       any("REFUSED" in c and RED in c and "DISAGREE" in c for c in complaints),
       "; ".join(c for c in complaints if RED in c)[:200])
    ok("a PARTIAL (interpreted != native) 'recordable' claim is REFUSED",
       any("REFUSED" in c and PARTIAL in c and "partial" in c for c in complaints),
       "; ".join(c for c in complaints if PARTIAL in c)[:200])
    ok("an honestly EXCLUDED port is named and absent",
       any("EXCLUDED" in c for c in complaints) and EXCLUDED not in after["lanes"])
    ok("an entry the evidence says nothing about is LEFT ALONE, not deleted",
       after["lanes"].get(KEPT) == before["lanes"][KEPT], f"{after['lanes'].get(KEPT)}")
    # THE POINT, and the outcome is STRONGER than the assertion first written for it. Gated
    # against the doc that resulted, the refused red reads BROKEN -- not AGREE-UNRECORDED,
    # because GUARD 4 is baseline-free and runs ahead of the baseline shortcut. So refusing to
    # record does not merely leave the lane un-recorded, it leaves it RED and named. That is
    # the whole requirement: a recording must never be able to convert a disagreeing lane into
    # UNCHANGED, and here the two halves are asserted together -- refused above, still BROKEN
    # below, with the disagreeing row named.
    g2 = load_gate("rebase_gate_after_refusal")
    v = gate_with(g2, after, evidence[RED]["rows"])
    ok("...and the refused RED lane is still BROKEN, never UNCHANGED",
       v["state"] == "BROKEN" and "disagree" in v["why"],
       f"{v['state']}: {v['why'][:120]}")
    # And the other refusal shape -- a lane refused for being PARTIAL, whose rows are not red --
    # must read AGREE-UNRECORDED rather than UNCHANGED. UNCHANGED is the green this whole
    # control exists to keep out of reach of a port we declined to record.
    w = gate_with(load_gate("rebase_gate_after_partial"), after,
                  {"interpreted": {"a": "1"}, "native": {"a": "1"}, "cpython:o": {"a": "1"}})
    ok("...and a lane refused for a NON-red reason reads AGREE-UNRECORDED, never UNCHANGED",
       w["state"] == "AGREE-UNRECORDED", f"{w['state']}: {w['why'][:120]}")
  return fails


# THE LANES THE SUPERSET PROOF RUNS OVER. Four, not the three the brief asked for, and chosen for
# what they EMIT rather than for being convenient -- one per row shape, and the F2 shape twice
# because it is the one the fold changes:
#
#   renderer/cstyle.bend + renderer_oracle.py cstyle-rows    F2, `name = [v]   py=[w]`. The lane
#       the fold exists for: before it this pair reported 222 shared / 222 disagree on a lane
#       cstyle-gate.py measures 221-of-227 clean with 0 disagreeing, so it was left unwired.
#   schedule/multi.bend + multi-rows.py                      F3, `name␣␣value`, NO `=` AT ALL.
#       The oracle lane read as ZERO rows -- 213 rows of real ground truth compared against
#       nothing, which reads identically to an oracle that was never run.
#   schedule/prepare.bend + prepare-oracle.py                F1 with `== SECTION ==` banners:
#       splitting each on its FIRST `=` yields the name `""`, so all fourteen landed on ONE key
#       and the oracle reported 2522 rows where it has 2521.
#   renderer/tc_ptx.bend + tcptx-oracle.py stage2            F2 again, and the pair the fold must
#       NOT change: BOTH sides carry `py=`, so folding must move neither the shared count nor the
#       disagreement count. One F2 pair proving the fold works is not enough; one proving it is
#       inert where both sides carry the tail is.
SUPERSET_LANES = [
  ("tinybendygrad/renderer/cstyle.bend", ".agents/slop/renderer_oracle.py cstyle-rows"),
  ("tinybendygrad/schedule/multi.bend", ".agents/slop/multi-rows.py"),
  ("tinybendygrad/schedule/prepare.bend", ".agents/slop/prepare-oracle.py"),
  ("tinybendygrad/renderer/tc_ptx.bend", ".agents/slop/tcptx-oracle.py stage2"),
]

# THE LANE THAT MUST KEEP READING AS NOTHING, and the reason the F3 gap is SPACES rather than any
# whitespace. `.agents/slop/oracle/dtype_tables.py` prints 14,774 TAB-separated lines and not one
# `=`, and `dtype.bend` is wired to it ON PURPOSE so that GUARD 2 ("compared nothing") is reachable
# on the real tree. Read a tab as a gap and that lane would manufacture 14,774 row names -- of
# which every one whose first column happened to be a dtype name would collide with a real
# cstyle/dtype row and be read by GUARD 4 as evidence. A table is not a row set, and a table's
# first column is not a row name. This is its own check because it needs NO .bend lane: the port
# side prints nothing anyway, and the claim is entirely about the oracle's bytes.
TSV_ORACLE = (".agents/slop/oracle/dtype_tables.py", "tinybendygrad/dtype.bend")


def lane_text(argv, port, env=None, timeout=1800):
  """A lane's RAW stdout, run HERE rather than read from the cache.

  A superset proof over a cache would be checking that a stored dict still parses, which is not
  the claim: `rows_before_fix` and `rows()` differ on the TEXT, so the text is what has to be in
  the room.

  THREE attempts, which is wire-rows.py's `tries=3` and not a number of my own: bend's machine
  stack overflows on roughly 1 run in 20 and prints ZERO rows, and a lane that reports nothing
  must be reported as reporting nothing rather than silently counted as a lane whose old and new
  counts agree at 0. MEASURED on an unmodified port: `schedule/prepare.bend` printed 0 rows on
  both attempts of one run and 321 rows minutes later on the same tree. A port being EDITED does
  the same thing -- `uop/fold.bend` was 30 seconds from a concurrent edit when it printed 0 twice
  -- and that is not a flake to retry away, it is a lane with nothing to say right now, so it
  stays UNMEASURED and stays a FAILURE.
  """
  scan = load_scan()
  for attempt in (1, 2, 3):
    r = scan.run(argv, env=env, timeout=timeout)
    text = r.stdout if r is not None else ""
    if scan.rows(text):
      return text
    print(f"        ({port} printed 0 rows on attempt {attempt})")
  return ""


def superset():
  """THE PROOF: the new `rows()` RETURNS EVERY ROW THE OLD ONE RETURNED, and every value it
  changes is proven to move NO verdict anywhere.

  `rows()` is shared by 38 wired gates, so the question is not "is the new parser better" but
  "WHAT ELSE DID IT MOVE". Three movements, and only one of them is safe:

    LOST KEY       the new parser drops a name.  GUARD 4 compares over the keys two lanes SHARE,
                   so a lost key shrinks the intersection -- below one, BROKEN, but between 1 and
                   n it is a silently NARROWER comparison.
    CHANGED VALUE  the new parser returns a different value for a name it already had.  This is
                   the direction that can turn a real disagreement into AGREEMENT, which is the
                   outcome this project has paid for six times.
    MANUFACTURED KEY  it invents a name out of a line that was never a row.

  The old parser found only `name=value`.  It read ZERO rows from `renderer/cstyle-rows`'s
  `[v]   py=[w]` tail -- no, it read them but could not COMPARE them, 222 shared and 222
  disagreeing on a lane that is 221-of-227 clean -- and it read ZERO of `multi-rows.py`'s 213
  whitespace-separated rows, which is indistinguishable from an oracle that was never run. Both
  fixes change something, so the proof is stated as THREE claims and each is driven:

    1. KEYS.  Every old key survives; the only ones that can go are the empty-named `== SECTION ==`
       phantoms, which were already gone before this change.
    2. VALUES.  Every changed value is NAMED and is a `py=` fold.  Asserting "no value changed"
       would be the easy way to pass and it would be FALSE for the F2 lanes, so the assertion is
       that every change is a fold of the same line -- never a re-parse of a different line.
    3. VERDICTS.  For each pair, the shared count and the disagreement count under BOTH parsers.
       A fold that turned a disagreement into agreement would show up here as disagree falling to
       zero while shared stayed put, and that is the check that matters.

  `rows()` is loaded from the gate, never restated. `rows_before_fix` is the only restatement in
  this file and it is labelled as the control's reference.

  PART 4 is the consequence through the real `gate_port()`: GUARD 4 consults no baseline, so
  dropping a key cannot launder a disagreement into "no baseline recorded". Both directions are
  driven -- a pair whose ONLY shared key was a banner, agreeing AND disagreeing, plus a real
  named row that differs.  A one-directional test is half a test.
  """
  g = load_gate("rebase_gate_superset")
  fixed, old = g.rows, rows_before_fix
  fails = []

  def ok(name, cond, detail=""):
    print(f"  {'PASS' if cond else 'FAIL'}  {name}" + (f"\n        {detail}" if detail else ""))
    if not cond:
      fails.append(name)

  def superset_of(text, label):
    """(keys_kept, only_folded, detail) for one block of text.

    `only_folded` is True when EVERY changed value is the old one with the producer's own `py=`
    boundary removed: `old == new + PY_TAIL + <the transcription>`. A value that changed for any
    other reason -- a different line winning the key, a re-parse, a strip -- fails this, which is
    the point of not asserting the easy thing ("no value changed"), which would be FALSE for every
    F2 lane and would prove nothing about them."""
    n, o = fixed(text), old(text)
    dropped = sorted(k for k in o if k not in n)
    changed = sorted(k for k in o if k in n and o[k] != n[k])
    # `left` already carries the `]` that PY_TAIL opens with, so the boundary as a SUFFIX of it is
    # PY_TAIL minus that bracket. Asserting the wrong one reports 0 folds out of 450 folds, which
    # is a check that fails to check -- and it did, once.
    mark = g.PY_TAIL.removeprefix("]")
    folded = all(o[k].startswith(n[k]) and o[k][len(n[k]):].startswith(mark) for k in changed)
    detail = (f"{label}: old={len(o)} new={len(n)} +{len(set(n) - set(o))} -{len(dropped)} "
              f"revalued={len(changed)} every_revalue_is_a_py_fold={folded} dropped={dropped[:4]}")
    return (not dropped or all(not k for k in dropped)), folded, detail

  # ---- PART 1, synthetic. All THREE shapes, plus the two things that must NOT become rows.
  SYNTH = ("== A: TABLES ==\n"                       # empty name -> a phantom under the old rule
           "PTX tensor_cores sm_75 = [1, 2]   py=[3]\n"   # F2: SPACES in the name, two `=`
           "load=0\n"                                  # F1: tight, and a value that is not empty
           "empty value row=0\n"                       # F1: EMPTY VALUE, which IS a row
           "= trailing equals in the value\n"          # empty name again
           "pm_len          25\n"                 # F3: ONE token, a two-space gap, no `=`
           "fp8e4m3\t10\t8\t1\n"                       # TSV: a table, NOT a row
           "ERROR: two  spaces in prose\n"             # prose, NOT a row
           "load=1\n")                                 # a MOVE, to catch value drift
  keep, folded, detail = superset_of(SYNTH, "synthetic")
  ok("synthetic: every old key survives, and the only drops are empty-named", keep, detail)
  ok("synthetic: every changed value is a `py=` fold and nothing else", folded)
  ok("synthetic: the ONLY key dropped is the one empty-named `== SECTION ==` key, and the ONLY key "
     "gained is the F3 row -- both stated by NAME, because a count here was what hid the "
     "off-by-one for an hour",
     set(old(SYNTH)) - set(fixed(SYNTH)) == {""}
     and set(fixed(SYNTH)) - set(old(SYNTH)) == {"pm_len"},
     f"old keys {sorted(old(SYNTH))}\n        new keys {sorted(fixed(SYNTH))}")
  ok("synthetic: the F3 row is READ (0 -> 1 more), and the TSV and prose lines are not",
     fixed(SYNTH).get("pm_len") == "25" and "fp8e4m3" not in fixed(SYNTH)
     and "ERROR:" not in fixed(SYNTH) and "load" in fixed(SYNTH),
     f"new keys {sorted(fixed(SYNTH))}")
  ok("synthetic: a MULTI-token 'name' with a two-space gap is NOT a row -- otherwise the gap and "
     "the name are the same character and the row has no name",
     "multi" not in {k.split()[0] for k in fixed(SYNTH + "two words  a value\n")},
     f"parsed {sorted(fixed(SYNTH + 'two words  a value\\n'))}")

  # ---- PART 2, real lanes. Both parsers on the same stdout, both counts printed.
  py = oracle_py.resolve()[0]
  env = load_scan().stripped_env({"DEV": "NULL"})  # measured: tcptx-oracle exits 2 without DEV=NULL
  measured = 0
  with cf.ThreadPoolExecutor(max_workers=4) as pool:
    texts = list(pool.map(
      lambda pl: (lane_text(["./bin/bend", str(REPO / pl[0])], pl[0]),
                  lane_text([py, *pl[1].split()], pl[1], env=env, timeout=600)),
      SUPERSET_LANES))
  for (port, oracle), (bend_text, oracle_text) in zip(SUPERSET_LANES, texts):
    for label, text in (("port  ", bend_text), ("oracle", oracle_text)):
      if not text:
        print(f"  FAIL  {label} {port}: UNMEASURED -- the lane produced 0 rows on all 3 attempts, "
              f"so this pair proves nothing and is NOT counted as agreement")
        fails.append(f"superset {label} {pathlib.Path(port).name}: unmeasured")
        continue
      measured += 1
      keep, folded, detail = superset_of(text, f"{port} {label}")
      ok(f"{pathlib.Path(port).name} {label}: every old key survives; only phantoms drop", keep, detail)
      ok(f"{pathlib.Path(port).name} {label}: every changed value is a `py=` fold", folded)

  # ---- PART 3, the VERDICTS, per pair. This is the claim that is actually load-bearing.
  #   Two invariants, and they are NOT the same claim:
  #     shared' >= shared      the fold must never NARROW a comparison -- narrowing is the
  #                            "comparing less and calling it agreement" failure;
  #     disagree' <= disagree  the fold must never INVENT a disagreement either, or the change
  #                            would hand every F2 lane a permanent red, which is worse than an
  #                            unwired one because red on every sweep is what a reader learns to
  #                            ignore.
  #   Where BOTH lanes carry the `py=` tail the fold must be INERT -- tc_ptx is that lane, and
  #   there the assertion is equality, because there is nothing to gain and something to lose.
  for (port, oracle), (bend_text, oracle_text) in zip(SUPERSET_LANES, texts):
    if not (bend_text and oracle_text):
      continue
    b, o, bo, oo = fixed(bend_text), fixed(oracle_text), old(bend_text), old(oracle_text)
    sh_o, sh_n = len(set(bo) & set(oo)), len(set(b) & set(o))
    d_o = sum(1 for k in set(bo) & set(oo) if bo[k] != oo[k])
    d_n = sum(1 for k in set(b) & set(o) if b[k] != o[k])
    both_fold = g.PY_TAIL in bend_text and g.PY_TAIL in oracle_text
    stem = f"{pathlib.Path(port).name} vs {pathlib.Path(oracle.split()[0]).name}"
    ok(f"{stem}: shared {sh_o} -> {sh_n} (never narrows), disagree {d_o} -> {d_n} (never grows)",
       sh_n >= sh_o and d_n <= d_o,
       f"{sh_n} shared of {len(b)} port / {len(o)} oracle rows; {d_n} disagreeing")
    if both_fold:
      ok(f"{stem}: both lanes carry `py=`, so the fold is INERT -- shared and disagree unchanged",
         (sh_n, d_n) == (sh_o, d_o), f"{sh_o}/{d_o} -> {sh_n}/{d_n}")

  # ---- PART 3c, THE CONTROL THE FOLD NEEDS: a lane it fixed must still be able to go RED.
  # Agreeing-once is what a blind gate looks like. So one row of the cstyle PORT text is
  # corrupted and the real gate_port() must name it -- which is also deliverable 5's control for
  # the lane the whole fold exists to wire.
  csty = next((t for (p, _), t in zip(SUPERSET_LANES, texts) if p.endswith("cstyle.bend")), None)
  if csty and csty[0]:
    pm, po = fixed(csty[0]), fixed(csty[1])
    target = next(k for k in sorted(set(pm) & set(po)) if pm[k] == po[k] and pm[k])
    poisoned = dict(pm, **{target: pm[target] + "PLANTED"})
    v = gate_with(load_gate("rebase_gate_fold_control"), {"lanes": {}, "hunks": {}},
                  {"interpreted": poisoned, "native": poisoned, "cpython:o": po})
    ok("a PLANTED disagreement in a folded lane is BROKEN and NAMES the row",
       v["state"] == "BROKEN" and any(target in d for d in v.get("disagreements", [])),
       f"{v['state']}: {v['why'][:110]}")
    clean = gate_with(load_gate("rebase_gate_fold_control_clean"), {"lanes": {}, "hunks": {}},
                      {"interpreted": pm, "native": pm, "cpython:o": po})
    ok("...and the SAME pair unplanted is AGREE-UNRECORDED, so the plant is what moved it",
       clean["state"] == "AGREE-UNRECORDED", f"{clean['state']}: {clean['why'][:110]}")
  else:
    ok("the folded-lane PLANT control measured its lane", False,
       "cstyle.bend produced no rows -- UNMEASURED, so the fold is UNPROVEN, not proven good")

  ok(f"the superset proof MEASURED {measured} real lanes, not 0", measured >= 2 * len(SUPERSET_LANES),
     f"{measured} of {2 * len(SUPERSET_LANES)} lanes measured")

  # ---- PART 3b, THE NEGATIVE: a table is not a row set, and this is the reason F3 wants SPACES.
  # RUN RAW, NOT THROUGH lane_text(). lane_text() RE-RUNS A LANE UNTIL IT PARSES NON-EMPTY and
  # returns "" otherwise -- correct for a lane being measured, and exactly wrong here: the whole
  # claim is that this lane parses to nothing, so lane_text() would discard 14,774 real lines and
  # the check would then pass VACUOUSLY on an empty string, reporting "0 lines" where the truth is
  # 14,774. A check that can pass by measuring nothing is the thing this file exists to prevent.
  tsv_spec, tsv_port = TSV_ORACLE
  raw = load_scan().run([py, *tsv_spec.split()], env=env, timeout=600)
  tsv = raw.stdout if raw is not None else ""
  n_tsv, n_old = len(fixed(tsv)), len(old(tsv))
  ok(f"the {tsv_port.split('/')[-1]} TSV oracle really ran, so its 0 is a MEASUREMENT",
     bool(tsv) and raw.returncode == 0, f"rc={raw.returncode if raw else 'TIMEOUT'}")
  ok(f"a TSV oracle stays at ZERO rows and does not become {len(tsv.splitlines())} claims",
     bool(tsv) and n_tsv == 0 and n_old == 0,
     f"{len(tsv.splitlines())} TSV lines -> {n_tsv} rows (old parser {n_old}); a gap of TABS is a "
     f"table cell, not a row name. Unwitnessed: the lane is wired ON PURPOSE to be dead, and "
     f"dtype.bend's own port prints nothing either")

  # ---- PART 4, the consequence, through the real gate_port() AND the real rows().
  # THE LANE ROWS ARE BUILT BY CALLING rows() ON TEXT. Handing gate_port() a dict with a "" key
  # in it tests nothing: run_port is stubbed, so rows() never sees the banner and the phantom
  # arrives by the back door. The whole claim is about what the parser does with `== X ==`, so the
  # parser has to be in the room.
  doc = {"lanes": {}, "hunks": {}}
  banner = "== D: mop_index ==\n"
  # Two lanes whose ONLY overlap is the banner: each has one real row, and the real rows differ.
  # Under the old parser they shared {"": ...}, compared one row, and agreed. Under this one they
  # share NOTHING and GUARD 4 calls that BROKEN -- which is the safe direction, and the only
  # direction available, since dropping a key can only shrink an intersection.
  p_only, o_only = g.rows(banner + "walk_mop=7\n"), g.rows(banner + "walk_other=7\n")
  both = gate_with(load_gate("rebase_gate_banner_agree"), doc,
                   {"interpreted": p_only, "native": p_only, "cpython:o": o_only})
  ok("a pair whose ONLY shared key was a BANNER is BROKEN, not agreement",
     both["state"] == "BROKEN" and "share NO row names" in both["why"],
     f"{both['state']}: {both['why'][:110]}")
  # ...and the old parser really did call that comparable-and-agreeing, which is the whole
  # reason the fix is worth a control rather than a diff.
  ok("...which the OLD parser would have read as a comparable, agreeing pair",
     set(rows_before_fix(banner + "walk_mop=7\n")) & set(rows_before_fix(banner + "walk_other=7\n"))
     == {""} and p_only == {"walk_mop": "7"} and o_only == {"walk_other": "7"},
     f"old shared {{''}} from a banner; new shared {set(p_only) & set(o_only)}, "
     f"and the new parsers kept {sorted(p_only)} / {sorted(o_only)}")
  # THE DIRECTION THAT MATTERS. A disagreement on the banner alone must stay BROKEN: agreement is
  # the only outcome a dropped key could turn a disagreement into, so the assertion is on the
  # STATE and not on the reason.
  split = gate_with(load_gate("rebase_gate_banner_differ"), doc,
                    {"interpreted": p_only, "native": p_only,
                     "cpython:o": g.rows("== E: something else ==\n" + "walk_other=7\n")})
  ok("...and a DISAGREEMENT on that banner is still BROKEN, never agreement",
     split["state"] == "BROKEN", f"{split['state']}: {split['why'][:110]}")
  named = gate_with(load_gate("rebase_gate_named_differ"), doc,
                    {"interpreted": g.rows(banner + "walk_mop=7\n"),
                     "native": g.rows(banner + "walk_mop=7\n"),
                     "cpython:o": g.rows(banner + "walk_mop=8\n")})
  ok("a real named row that DIFFERS is still BROKEN and still counted",
     named["state"] == "BROKEN" and "disagree" in named["why"],
     f"{named['state']}: {named['why'][:110]}")
  return fails


def cache_rule():
  """THE CACHE IS NOT A READING UNLESS IT IS NEWER THAN ITS SOURCE AND IT RECORDS SOMETHING.

  rebase-scan-oracles.py printed `84 shared, 84 disagree` against a pair whose real gate measures
  `726 shared, 0 disagree`, off cache files written HOURS earlier. Not a rounding, not a stale
  comment: a number about the tree as it stood before three edits, presented as a number about
  the tree. The rule that prevents it already existed -- wire-rows.py's "a cache older than the
  source is not a reading" -- and the scan did not use it.

  Three controls, because the rule has three ways to be wrong and the third is the one that is
  easiest to declare fixed:

    CONTROL    cache OLDER than its source  -> refused, and the message names BOTH files and
                says which is older. `wire-rows.py`'s message says "the cache is older than the
                source" without saying which of the two moved, so the reader has to guess.
    NO-OP      cache NEWER than its source  -> used, and the rows come back UNCHANGED. This is
                the SAME answer on both sides of the boundary, which is what makes the control
                above a control rather than a rule that refuses everything.
    CONTROL    cache that holds NO ROWS, but is newer than its source -> refused. The write side
                refuses to store an empty cache, and 82 legacy `{}` files were still on disk
                after that rule shipped; a fresh file holding `{}` is not stale, so the mtime
                rule alone reads a FAILED lane from hours ago as a fresh measurement of zero.
                Measured consequence of the mtime rule alone: 8 of the 38 wired pairs measured
                0 shared row names and every one of them was skipped in silence.

  Every control drives `rebase-scan-oracles.py`'s OWN `cached()` against a scratch cache
  directory. Re-implementing the rule here would test the re-implementation, which is the
  mistake this file already made once with the six states (see `verdict_of`).
  """
  s = load_scan()
  fails = []

  def ok(name, cond, detail=""):
    print(f"  {'PASS' if cond else 'FAIL'}  {name}" + (f"\n        {detail}" if detail else ""))
    if not cond:
      fails.append(name)

  ROWS = {"PTX tensor_cores sm_75": "[1, 2]", "load": "", "empty value row": "0"}
  KEY, SRC = "tinybendygrad/probe.bend", "port.bend"

  with tempfile.TemporaryDirectory() as td:
    root, real = pathlib.Path(td), s.CACHE
    src, cache = root / SRC, s.cache_file(root, KEY)
    src.write_text("PROBE SOURCE\n")
    s.write_cache(root, KEY, ROWS)
    s.CACHE = root  # the reader resolves CACHE at call time

    def age(seconds):  # the CACHE file's mtime, `seconds` from the source's. + is OLDER.
      st = src.stat().st_mtime
      os.utime(cache, (st - seconds, st - seconds))

    age(-1)  # cache 1s NEWER than its source
    d, why = s.cached(KEY, src)
    ok("NO-OP: a cache NEWER than its source is used, rows unchanged",
       why == "fresh" and d == ROWS, f"{why}, {d}")
    age(60)  # cache 60s OLDER than its source
    d, why = s.cached(KEY, src)
    ok("CONTROL: a cache OLDER than its source is refused, not read",
       why == "stale" and d is None, f"{why}, {d}")
    msg = capture(s.say_not_used, KEY, "stale", src)
    ok("...and the refusal NAMES BOTH FILES and which one is older",
       str(cache) in msg and str(src) in msg and "OLDER" in msg, msg.strip())
    # The empty half. Newer than its source, so ONLY the emptiness can refuse it.
    s.write_cache(root, KEY, {})
    age(-1)
    d, why = s.cached(KEY, src)
    ok("CONTROL: a cache that holds NO ROWS is refused however NEW it is",
       why == "empty" and d is None, f"{why}, {d}")
    msg = capture(s.say_not_used, KEY, "empty", src)
    ok("...and says the file records a FAILED run rather than an empty one",
       str(cache) in msg and "NO ROWS" in msg, msg.strip())
    # And the write half, because the two halves must agree: if store() wrote `{}`, the read
    # refusal above would be a rule with no second half to catch. The file is REMOVED first --
    # it still holds the `{}` written two checks ago, and "size > 2" would then be testing the
    # previous step's file rather than whether store() wrote anything.
    cache.unlink()
    s.store(KEY, {}, "probe")
    ok("...and store() writes NOTHING for an empty result", not cache.exists(),
       f"{cache} {'exists' if cache.exists() else 'absent'}")
    s.CACHE = real
  return fails


def capture(fn, *a):
  """What a diagnostic function PRINTS, as a string. A message is part of the contract here --
  rebase-scan-oracles.py's whole failure was a confident number with nothing beside it -- so it
  is asserted, not assumed."""
  import io
  import contextlib
  buf = io.StringIO()
  with contextlib.redirect_stdout(buf):
    fn(*a)
  return buf.getvalue()


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

  print("selftest: the five states are each REACHABLE\n")

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
  # ⚠ THE STATE THIS ENTIRE UNIT EXISTS TO RESTORE. Lanes that agree, with an INTACT baseline
  # document that simply has no entry for this port, used to answer NOT-STARTED -- the same
  # answer as "no oracle wired in BASE_ORACLES -- nothing can be claimed". So 46 of 50 targets
  # read "nobody ever compared these" when every one of them had just compared clean, and the
  # tally could not say which of the two it was looking at. It is NOT UNCHANGED either: "they
  # agree right now" is strictly weaker than "nothing moved since someone looked", and
  # recording is the only thing that moves a port off this state.
  unrec = verdict_of({"a": "1"}, {"a": "1"}, oracle_rows={"a": "1"}, no_baseline=True)
  check("lanes that agree with NO baseline -> AGREE-UNRECORDED, not NOT-STARTED",
        unrec, "AGREE-UNRECORDED", "compared clean and UNRECORDED")
  print(f"        {unrec['state']}: {unrec['why']}")
  # The state must carry its EVIDENCE -- which lane pairs compared and agreed -- because that
  # is the whole difference between it and NOT-STARTED. A `why` that could be printed for an
  # unwired port is a state that has not really been separated from one.
  ev = unrec.get("compared_pairs") or []
  ok = bool(ev) and all(n >= 1 for _, _, n in ev)
  print(f"  {'PASS' if ok else 'FAIL'}  AGREE-UNRECORDED names the lane pairs that compared "
        f"({ev})")
  if not ok:
    fails.append("AGREE-UNRECORDED carries no comparison evidence")
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
  rows_, hunks_, why, readable = g.baseline_for({"interpreted": {"a": "1"}}, "/tmp/probe.bend")
  ok = rows_ is None and hunks_ is None and "MALFORMED" in why and not readable
  print(f"  {'PASS' if ok else 'FAIL'}  a baseline of the WRONG SHAPE is named, not absorbed")
  if not ok:
    fails.append("malformed baseline is named")
  print(f"        {why}")

  # ⚠ IT MUST ALSO STAY NOT-STARTED ON A RUN THAT COMPARED EVERYTHING CLEANLY. "This file could
  # not be parsed" is not "compared clean, nothing recorded" -- the second is a claim about the
  # port and the first is a claim about the tool, and conflating them would let a corrupt
  # baseline.json read as coverage. `readable` is what separates them.
  #
  # The fixture is a document with NO "lanes" key at all, which is the shape baseline_for()
  # calls MALFORMED. `{"lanes": {}}` would NOT do: that is a perfectly readable document with
  # no entry for this port, which is precisely the AGREE-UNRECORDED case above, and using it
  # here tested the wrong branch while looking like it tested this one.
  v = gate_with(load_gate("rebase_gate_unreadable"), {"interpreted": {"a": "1"}},
                {"interpreted": {"a": "1"}, "cpython:oracle": {"a": "1"}})
  ok = v["state"] == "NOT-STARTED" and "MALFORMED" in v["why"]
  print(f"  {'PASS' if ok else 'FAIL'}  a MALFORMED baseline is NOT-STARTED, never AGREE-UNRECORDED")
  if not ok:
    fails.append("a malformed baseline reads as AGREE-UNRECORDED")
  print(f"        {v['state']}: {v['why']}")

  fails += never_wired_control()
  fails += record_stable_control()
  fails += planted_lane_control()

  print("\nCACHE RULE: a cache is a reading only if it is NEWER than its source and RECORDS "
        "SOMETHING\n")
  fails += cache_rule()

  print("\nROWS() SUPERSET: the fixed parser returns every row the old one returned\n")
  fails += superset()

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


def parser_fingerprint():
  """A hash of `rows()`'s own BYTECODE, plus the shape constants it reads. `rebase-scan-oracles.py`
  caches row DICTS, not stdout, so a cache written by one parser is a set of keys and values that
  the next parser will read as if it had produced them.

  ⚠ THAT IS NOT HYPOTHETICAL AND IT IS THE EXACT FAILURE THIS FILE IS BUILT AGAINST. The cache
  rule is "a cache OLDER than its source is not a reading", and `rows()` is not a source: editing
  rebase-gate.py changes no .bend and no oracle, so every cached dict stayed "fresh" and
  measure_roster() would have reported the new parser's verdicts over the old parser's rows. The
  same argument is why 82 cache files holding `{}` were once believed, and it is the reason a
  confident number has outlived its input three separate times in this project's history.

  So the fingerprint is written BESIDE the cache and a change wipes it. Wiping is cheap (the lanes
  re-run) and it is the safe direction; keeping a cache whose meaning has changed is not a speed,
  it is a lie with a timestamp."""
  import hashlib
  scan = load_scan()
  g = scan.gate
  src = hashlib.sha256(g.rows.__code__.co_code).hexdigest()
  src += repr((g.PY_TAIL, g.GAP))
  return hashlib.sha256(src.encode()).hexdigest()[:16]


def parser_cache_guard():
  """Wipe rebase-scan-oracles.py's row cache when `rows()`'s meaning has changed. Prints what it
  did, because a silent wipe and a silent reuse are indistinguishable from the outside and only one
  of them is honest about the numbers that follow."""
  scan = load_scan()
  marker = scan.CACHE / "PARSER"
  fp = parser_fingerprint()
  try:
    was = marker.read_text().strip()
  except OSError:
    was = None
  if was == fp:
    return f"parser {fp}: rebase-scan's row cache is consistent with it"
  scan.CACHE.mkdir(parents=True, exist_ok=True)
  for f in scan.CACHE.glob("*.json"):
    f.unlink()
  marker.write_text(fp)
  return (f"parser {was or 'none'} -> {fp}: rebase-scan's row cache was measured by a DIFFERENT "
          f"rows() and every cached row dict in it has been deleted, so nothing below can be read "
          f"off the old parser's work")


def mutant_lane(spec, row, tmpdir):
  """A CPython lane that is `spec`'s stdout with ONE row's value corrupted, written into a
  `$TMPDIR`. Not a mutant ORACLE: it runs the real one and rewrites its output, so the only
  difference between the two lanes is the corruption and nothing else -- a mutant that re-spelled
  the values would move many rows and the control would report a disagreement without naming
  which one it planted.

  It lives in a temp directory rather than in `.agents/slop/` on purpose. A CORRUPTED oracle in
  the slop directory is a file that outlives the control that made it, and `.agents/slop/` is
  swept by rebase-scan-oracles.py -- the next sweep would measure it as a candidate and cache it.
  The recipe is here; the artefact is not."""
  mut = pathlib.Path(tmpdir) / "mutant-lane.py"
  mut.write_text(
    "import os, subprocess, sys\n"
    f"ROW = {row!r}\n"
    f"ARGV = {spec.split()!r}\n"
    "r = subprocess.run([sys.executable, *ARGV], env=dict(os.environ, DEV='NULL'),\n"
    "                   capture_output=True, text=True)\n"
    "sys.stderr.write(r.stderr)\n"
    "hit = [0]\n"
    "out = []\n"
    "for line in r.stdout.splitlines():\n"
    "  if line.split('=', 1)[0].strip() == ROW:\n"
    "    line = line + 'PLANTED'\n"
    "    hit[0] += 1\n"
    "  out.append(line)\n"
    "if hit[0] != 1:\n"
    "  sys.stderr.write(f'MUTANT: {ROW} matched {hit[0]} lines, expected exactly 1\\n')\n"
    "  sys.exit(3)\n"
    "print('\\n'.join(out))\n")
  return str(mut)


def planted_lane_control():
  """THE RULE THIS FILE IS BUILT AROUND, DRIVEN ON A REAL PAIR: a lane is not wired until it has
  been SEEN RED.

  `renderer/cstyle.bend` was WIRED on 2026-10-04 and this is its control. The clean pair must be
  AGREE-UNRECORDED, and a single corrupted row must make the same pair BROKEN WITH THE ROW NAMED
  -- through the real `run_port`, so a real .bend lane and a real CPython subprocess, not a dict
  handed to a stub. A gate that has only ever printed agreement is indistinguishable from a gate
  that cannot fail, and the planted row is a `tmap` cell, the row family cstyle-gate.py already
  proved falsifiable.

  The mutant is REFUSED if its row matches anything other than exactly one line, so the control
  cannot silently degrade into "planted into nothing" -- which would report AGREE on the clean
  pair and be read as a passing control having proved nothing.

  ⚠ FOUR MODULES, NOT ONE. `gate_with()` REPLACES `g.run_port` and `g.REPO` with a stub, so the
  real runs and the stubbed verdicts cannot share a module object. Driving the real lanes through
  a module a previous call stubbed is a control that measures the stub."""
  port, spec = "tinybendygrad/renderer/cstyle.bend", ".agents/slop/renderer_oracle.py cstyle-rows"
  fails = []

  def ok(name, cond, detail=""):
    print(f"  {'PASS' if cond else 'FAIL'}  {name}" + (f"\n        {detail}" if detail else ""))
    if not cond:
      fails.append(name)

  # The row is CHOSEN by running the pair, never typed: a typed row name is a name that silently
  # stops existing when the port is re-cut, and the control would then report "planted into
  # nothing" as agreement.
  lanes, now = load_gate("rebase_gate_plant_real").run_port(REPO / port, [spec], True)
  both = set(now["interpreted"]) & set(now["cpython:renderer_oracle"])
  ok("the real cstyle lanes ran and shared a row to plant into", bool(both),
     f"lanes={ {k: v['rc'] for k, v in lanes.items()} } rows={ {k: len(v) for k, v in now.items()} }")
  if not both:
    fails.append("planted-lane control: nothing measured")
    return fails
  row = next(k for k in sorted(both) if now["interpreted"][k] == now["cpython:renderer_oracle"][k])
  clean = gate_with(load_gate("rebase_gate_plant_clean"), {"lanes": {}, "hunks": {}}, now)
  ok(f"clean: cstyle is AGREE-UNRECORDED over {len(both)} shared names, not BROKEN and not "
     f"NOT-STARTED", clean["state"] == "AGREE-UNRECORDED",
     f"{clean['state']}: {clean['why'][:120]}")
  with tempfile.TemporaryDirectory() as td:
    mlanes, planted = load_gate("rebase_gate_plant_mutant").run_port(
      REPO / port, [mutant_lane(spec, row, td)], True)
    ok("the mutant lane exited 0, so it PLANTED rather than died",
       mlanes["cpython:mutant-lane"]["rc"] == 0,
       f"rc={mlanes['cpython:mutant-lane']['rc']} "
       f"{mlanes['cpython:mutant-lane'].get('err', '')[:120]}")
    v = gate_with(load_gate("rebase_gate_plant_control_red"), {"lanes": {}, "hunks": {}}, planted)
    named = [d for d in v.get("disagreements", []) if d[2] == row]
    ok(f"one planted row -> BROKEN, and the message NAMES `{row}`",
       v["state"] == "BROKEN" and bool(named), f"{v['state']}: {v['why'][:120]}")
    ok("...and it is ONE row against two of the three lane pairs",
       len(v.get("disagreements", [])) == 2,
       f"{len(v.get('disagreements', []))} disagreements: the planted row is shared with 2 of "
       f"the 3, because interpreted-vs-native is the port against itself")
    # RESTORE, BY RE-RUN. Nothing on disk was edited, so the restore is proved by the bytes
    # coming back, not by a hash of a file -- there is no file to hash.
    again = load_gate("rebase_gate_plant_restored").run_port(REPO / port, [spec], True)[1]
    ok("the restored pair is BYTE-IDENTICAL to the clean reading", again == now)
  return fails


def measure_roster():
  """({port: (shared, disagree, port_rows, oracle_rows)}, bend_rows, oracle_rows) -- counts AND rows.

  The rows come back because A DISAGREEMENT IS NOT A COUNT: a FAIL that says "1 of 107 shared row
  names disagree" sends the reader off to a diff to find out which one, and naming it here costs
  one reference per port.

  Through rebase-scan-oracles.py, so through its cache AND through its staleness-and-emptiness
  rule: a number appears here only if a lane was actually re-run against its current source. The
  lanes are independent processes, so they are measured CONCURRENTLY -- serially a cold cache
  charges the sum of 36 bend and 36 oracle runs, and `runtime/support/elf.bend` alone needs 159s
  unloaded and exceeded 600s under contention before its budget was raised to wire-rows.py's
  1800s. Serial measurement is why "type the number" and "skip the measurement" both looked
  reasonable, and neither of them is.

  Keys are de-duplicated, so a lane two entries share is run once and read twice -- which also
  means no two threads ever write the same cache file."""
  scan = load_scan()
  live = {p: o for p, (o, k) in ORACLE_CONFORMANCE.items() if k == "live"}
  ports, specs = sorted(live), sorted(set(live.values()))
  with cf.ThreadPoolExecutor(max_workers=8) as pool:
    bend = dict(zip(ports, pool.map(scan.bend_rows, ports)))
    orc = dict(zip(specs, pool.map(scan.oracle_rows, specs)))
  out = {}
  for port, spec in live.items():
    b, o = bend[port], orc[spec]
    shared = set(b) & set(o)
    out[port] = (len(shared), sum(1 for k in shared if b[k] != o[k]), len(b), len(o))
  return out, bend, orc


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
# ⚠ AND IT NO LONGER CARRIES A SHARED-ROW COUNT, BECAUSE A COUNT HERE WAS A SECOND SOURCE OF
# TRUTH WITH NO INVALIDATION RULE. It said 84 for `ga-oracle.py` after the real number became 726,
# and it kept saying 84 through every run, because nothing in this file re-reads it -- the same
# species as the cache that never invalidated, and the same consequence: a plausible number that
# outlived its input and was believed. The 84 only ever SIZED A SYNTHETIC FIXTURE, so no verdict
# was ever wrong; that is the one mercy in this story and it is not a reason to keep the number.
#
# The count is now MEASURED, every run, by measure_roster() below: the same bend and oracle lanes
# rebase-scan-oracles.py runs, through its own staleness-and-emptiness rule, so a number appears
# here only if it was measured against the live tree. What each entry's comment now carries is
# what the UNSHARED remainder is, which is the part that does not rot.
#
# A number that could not be measured is printed UNMEASURED and FAILS. It is never rounded to 0
# and never inherited from a previous run: a fixture sized by a remembered 84 is the defect this
# paragraph exists to remove.
#
# The unshared remainders, measured 2026-10-03, stated because they are the interesting part:
#   tc_ptx    228 of 333 -- the other 105 use legacy dtype spellings in the ROW KEY (`half` vs
#              `f16`) and so do not intersect; aligned values agree.
#   elf       353 of 353 -- PORT FULLY COVERED, the only "live" entry with zero uncovered rows.
#              Its oracle emits 689 further rows, 14 of which are `libstub.dylib` runtime
#              addresses that ASLR changes every launch: none shared, so GUARD 4 is unaffected
#              and GUARD 1 is why elf must never be recorded.
#   sqtt      1015 of 1033 -- probe-recorded and re-gated UNCHANGED, so this one IS recordable.
#   generate  726 of 726 -- WAS 84 of 233 before the producer was re-cut. The 149 "lost" rows
#              were generated-Python lines `gl` printed whole, one per row, and rows() split them
#              on `=`. BASE_ORACLES says why rows() was deliberately NOT touched for this.
#   ops_cpu   3 of the oracle's 20 -- 17 are `findlib_*` HOST answers (where libm and libobjc live
#              on THIS machine). A gate's strength is the intersection, so 3 is the number.
#   ops_python 59 of 85 -- the other 26 are the port's own encodings (table ids, constructor tags,
#              a completion sentinel, a hardcoded b64 flag, synthetic core_find fixtures, and one
#              assertion string no real tensor core emits).
#   ops_amd   409 of 520 -- the other 111 are ungated (init trace, differently-keyed names). Not
#              a claim about those 111.
#   render    85 of the port's 86 naive keys -- the leftover is `py`, an indented continuation the
#              parser invents; port-only and not a claim. HEAD, not the vendored hybrid.
#   llvmir    323 of 323 -- the file was deleted in 668d3194d, so the filename sweep could not see
#              a file that was no longer on disk. Restored as llvmir-oracle.py.
#   qcom      312 of 750 -- omitted: qc_ctz_zero (CPython -1, port 32, ops_qcom.py:43), the U32
#              miss sentinels (not a CPython return), and the stage-2 ELF walk.
#   indexing  104 of 252 -- ALWAYS_CONTIGUOUS, data_srcs, broadcast_axes and argsort are left
#              out; `mv_*` is arena-slot identity, and apply_movement_op does not return those.
#   dtype     99 of 164 -- the rest are interning-order rows plus lgu, which the port prints
#              `refused:unported` where CPython builds a WHERE. Not gated.
#   rangeify  31 of 126 -- 3 rows are a different field (AxisType.WEAK vs the axis index).
#   jit       18 of 137 -- four rows disagree: DEV=NULL says 'NULL' where the port baked 'PYTHON',
#              and jit_oracle's cap() returned 'none' for two log lines.
#   null      7 of 180 -- the five opcodes and two EMULATE messages NullDevice raises.
ORACLE_CONFORMANCE = {
  # port: (oracle spec, kind)
  # kind "live" -- the six synthetic states are driven against this oracle's own row names
  # kind "dead" -- wired to make BROKEN reachable on the REAL tree, so there is no shared
  #   name to drive (0 BY DESIGN) and the assertion is a real subprocess run of the gate
  "tinybendygrad/uop/spec.bend": (".agents/slop/rebase-oracle-spec.py", "live"),
  "tinybendygrad/uop/ops.bend": (".agents/slop/rebase-oracle-ops.py", "live"),
  "tinybendygrad/codegen/opt/search.bend": (".agents/slop/rebase-oracle-search.py", "live"),
  "tinybendygrad/runtime/ops_rdma.bend": (".agents/slop/oracle_rdma_gate.py", "live"),
  "tinybendygrad/runtime/ops_nv.bend": (".agents/slop/nv-oracle.py", "live"),
  "tinybendygrad/runtime/support/hcq2.bend": (".agents/slop/hcq2-oracle.py", "live"),
  "tinybendygrad/runtime/ops_metal.bend": (".agents/slop/mt_seam_rows.py", "live"),
  "tinybendygrad/runtime/support/usb.bend": (".agents/slop/usb-oracle-run.py", "live"),
  "tinybendygrad/schedule/prepare.bend": (".agents/slop/prepare-oracle.py", "live"),
  "tinybendygrad/renderer/ptx.bend": (".agents/slop/ptx-s3-oracle.py", "live"),
  "tinybendygrad/renderer/tc_ptx.bend": (".agents/slop/tcptx-oracle.py stage2", "live"),
  "tinybendygrad/renderer/nir_llvmir.bend": (".agents/slop/nl/nl-oracle.py", "live"),
  "tinybendygrad/viz/serve.bend": (".agents/slop/vz/viz_oracle.py", "live"),
  "tinybendygrad/runtime/support/c.bend": (".agents/slop/c-oracle.py", "live"),
  "tinybendygrad/uop/fold.bend": (".agents/slop/mm-lift-gate.py", "live"),
  "tinybendygrad/runtime/support/elf.bend": (".agents/slop/elf_rows.py", "live"),
  #    sqtt: 1015 of 1033. Probe-recorded and re-gated UNCHANGED, so this one IS recordable.
  "tinybendygrad/renderer/amd/sqtt.bend": (".agents/slop/sqtt_spec.py", "live"),
  "tinybendygrad/renderer/amd/generate.bend": (".agents/slop/ga-oracle.py", "live"),
  "tinybendygrad/nn/onnx.bend": (".agents/slop/onnx-gate.py", "live"),
  "tinybendygrad/mixin/elementwise.bend": (".agents/slop/ew-gate.py", "live"),
  "tinybendygrad/mixin/op.bend": (".agents/slop/mixin-op-gate.py", "live"),
  "tinybendygrad/tensor.bend": (".agents/slop/tensor-gate.py", "live"),
  "tinybendygrad/codegen/simplify.bend": (".agents/slop/xd1/rw-oracle.py", "live"),
  "tinybendygrad/nn/__init__.bend": (".agents/slop/nn-init-gate.py", "live"),
  "tinybendygrad/codegen/gpudims.bend": (".agents/slop/xd1/rw-gate-oracle.py", "live"),
  "tinybendygrad/runtime/ops_cpu.bend": (".agents/slop/cpulink_oracle.py", "live"),
  "tinybendygrad/runtime/ops_python.bend": (".agents/slop/ops-python-render-oracle.py", "live"),
  "tinybendygrad/runtime/ops_amd.bend": (".agents/slop/amd_oracle.py", "live"),
  "tinybendygrad/uop/render.bend": (".agents/slop/xd1/render-gate-oracle.py --gate", "live"),
  # -- the no-candidate unit. Counts are the measured intersection, not the
  #    oracle's row count. llvmir is 323 of the port's 323.
  "tinybendygrad/renderer/llvmir.bend": (".agents/slop/llvmir-oracle.py", "live"),
  "tinybendygrad/runtime/ops_qcom.bend": (".agents/slop/qcom-oracle.py", "live"),
  "tinybendygrad/schedule/indexing.bend": (".agents/slop/indexing-oracle.py", "live"),
  "tinybendygrad/codegen/decomp/dtype.bend": (".agents/slop/dtype-oracle.py", "live"),
  "tinybendygrad/schedule/rangeify.bend": (".agents/slop/rangeify-oracle.py", "live"),
  "tinybendygrad/engine/jit.bend": (".agents/slop/jit-oracle.py", "live"),
  "tinybendygrad/runtime/ops_null.bend": (".agents/slop/null-oracle.py", "live"),
  # device: 23 of the port's 110, 0 disagreements, measured through measure_roster() on
  # every run of this file -- so the number printed here is a number about THIS tree.
  # It was NOT wired until the `allow_lower` port fix landed; the history is in
  # BASE_ORACLES and the control that had to pass first is in ORACLE_NOT_WIRED below.
  "tinybendygrad/device.bend": (".agents/slop/device-oracle.py", "live"),
  "tinybendygrad/dtype.bend": (".agents/slop/oracle/dtype_tables.py", "dead"),
  #    WIRED 2026-10-04, off `renderer_oracle.py cstyle-rows` and NOT off the 15-row `cstyle`
  #    lane this used to name. 222 shared / 0 disagreeing, and the 222 is the DENOMINATOR: 8 of
  #    the port's `kern` rows share 6 names under a first-`=` split, and the 3 port-only names are
  #    cstyle-gate.py's EXCLUDED `buft METAL`, `idx BASE  regadd`, `idx HIP   regadd`. It was
  #    unwired because `rows()` could not COMPARE the port's `NAME = [v]   py=[w]` against the
  #    oracle's `NAME = [v]` -- 222 shared / 222 disagreeing, by construction -- and 9 of those
  #    rows carry the port's marker where CPython raises, which the oracle used to render as a
  #    sentinel no other lane can read. Both were the READER's problem; see BASE_ORACLES.
  "tinybendygrad/renderer/cstyle.bend": (".agents/slop/renderer_oracle.py cstyle-rows", "live"),
}

# NOT WIRES, and named here as well as in BASE_ORACLES because a roster that only records
# what passed cannot answer "why is this one missing?" -- which is the question the next reader
# asks about every port that is NOT-STARTED.
#
# schedule/multi.bend IS THE FIRST ENTRY IN A LONG WHILE, AND IT IS NOT THE SAME KIND OF ENTRY AS
# THE ONE THAT WAS HERE. `device.bend` sat here until it was WIRED, and the entry named a real
# blocker: one row, `allow_lower`, disagreeing for a structural reason a transcription cannot see
# (tinygrad/device.py:30 REBINDS `ix`, so line 31's subject is `PYTHON:1` whatever case arrived).
# That was fixed and the lane opened. multi.bend's blocker is equally structural and equally real:
#
#   port   `schedule/multi.bend`        321 rows, every name `t_`-prefixed (`t_pm_n`, `t_rd_all_red`)
#   oracle `.agents/slop/multi-rows.py` 213 rows, no prefix (`pm_len`, `rd_all_red`)
#   shared, exactly as printed                                     0
#
# ⚠ AND A `t_` PREFIX NORMALISATION IS A SECOND SOURCE OF TRUTH, NOT A FIX. MEASURED, not assumed:
# strip the prefix and the intersection is 26 -- and 21 of those 26 DISAGREE, because the collision
# is an accident of spelling and not a correspondence of claims:
#
#     bx_none    port `1`   vs oracle `()`    port: "is anything broadcast"  oracle: WHICH axes
#     pm_rev     port `1`   vs oracle `0`    port: a COUNT row              oracle: tuple.index
#     fl_mid_n   port `1`   vs oracle `1`    AGREES -- and agrees on the LITERAL `1`
#
# That third line is the expensive one. A normalisation would manufacture 21 reds and 1 agreement
# that is not an agreement, and an agreement is what a reader believes. So the prefix stays where
# the producer put it, and the fix belongs in an oracle that prints the port's own row NAMES with
# CPython's answer under each -- a different oracle from this one, and not this unit's to write.
#
# WHAT WAS THIS UNIT'S, AND IT IS FIXED. `multi-rows.py:265` prints `f"{n.ljust(w)}  {v}"`: a
# name, TWO SPACES, a value, and no `=` anywhere, so `rows()` read ZERO of its 213 rows -- which is
# indistinguishable, from outside, from an oracle that was never run. `row()`'s third shape reads
# all 213 (SUPERSET_LANES measures old=0 new=213 on that stdout). The lane is STILL unwired, for
# the NAME reason above, and the two are separate claims: a readable FORMAT is necessary for a
# wireable lane and not sufficient. An F3 lane that reads 213 rows and shares 0 names reports
# BROKEN "share NO row names", which is the whole point of GUARD 4.
ORACLE_NOT_WIRED: dict[str, str] = {
  "tinybendygrad/schedule/multi.bend": (
    "UNWIRED. 321 port rows against 213 oracle rows, 0 shared names, so GUARD 4 would answer "
    "'share NO row names' and nothing would ever be compared. A `t_` prefix normalisation is a "
    "SECOND SOURCE OF TRUTH rather than a fix: it yields 26 collisions, 21 of which DISAGREE "
    "because the port's `1`-per-op rows and the oracle's axis tuples share a spelling and not a "
    "claim, and the 1 that agrees agrees on the literal `1`. The FORMAT is read now (213 rows, was "
    "0); the blocker is the NAME, and the fix is an oracle that prints the port's row names."),
}


def dead_lane_is_broken(port, oracle):
  """Run the REAL gate -- real run_port, real bend file, real oracle script -- on a
  deliberately-dead pair and require BROKEN.

  This is the state the whole tool exists for, and the one a synthetic fixture cannot supply:
  GUARD 2 and GUARD 4 both need lanes that were actually produced. `dtype_tables` exits 0
  printing TSV (so `rows()` finds no `=`). `renderer_oracle.py cstyle` USED to exit 1 with
  `KeyError: dtypes.weakint` inside upstream cstyle, and NO LONGER DOES: measured 2026-10-03
  it exits 0 and prints 15 real C kernels under the names `k1_load_store`, `k2_alu`,
  `k3_consts`, ... It is still BROKEN, and now for the ONE remaining reason rather than two:
  those 15 names share 0 of cstyle.bend's 225, so GUARD 3 fires. Stating this matters --
  "exits 1" was true when this docstring was written, a reader checking it would now be told
  it is broken code, and the obvious repair -- trusting the exit status -- is the mistake this
  function exists to prevent. Both were BROKEN-by-construction in the briefing, and a wiring
  change must never quietly turn either into a pass.

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
  """Drive the six states through gate_port() for each wired oracle. Returns failure names.

  ⚠ THE FIXTURE IS SIZED BY A MEASUREMENT, NOT BY A NUMBER WRITTEN DOWN HERE. It used to be sized
  by a stored shared-row count, which said 84 for a pair that measures 726, and the stale number
  was printed in the PASS line of every run -- a confident claim about the tree, in the one file
  whose whole purpose is refusing those. So measure_roster() re-measures, every run, and the
  number that appears below is one that was just obtained.

  An entry that could not be measured FAILS and says UNMEASURED, naming which lane produced
  nothing. It does NOT fall back to 1 and it does not inherit the previous run's count: a fixture
  sized by a remembered number IS the defect, and "0 rows" quietly becoming a passed check is the
  same species of thing that hid for an hour here."""
  g_all = load_gate("rebase_gate_roster")
  wired = {p: o[0] for p, o in g_all.BASE_ORACLES.items()}  # BASE_ORACLES holds a LIST of oracles
  fails = []
  if wired != {p: s for p, (s, _) in ORACLE_CONFORMANCE.items()}:
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

  # THE SHARED-ROW COUNTS ARE MEASURED HERE, EVERY RUN, and printed whether or not they agree
  # with anything -- so the number a reader sees is a number about this tree, not a number typed
  # in a file that outlived its input. 1 disagreement on a live pair is a FAILURE: it is the same
  # red the gate would report, and a conformance check that passed over a live disagreement would
  # be reporting on the roster rather than on the ports.
  live_pairs = sum(1 for _, k in ORACLE_CONFORMANCE.values() if k == "live")
  print(f"\nMEASURING {live_pairs} live pairs against the tree "
        f"(shared names / disagreements / port rows / oracle rows)\n")
  print(f"  {parser_cache_guard()}\n")
  t0 = time.monotonic()
  measured, bend_all, orc_all = measure_roster()
  print(f"  measured in {time.monotonic() - t0:.1f}s\n")

  for port, (oracle, kind) in ORACLE_CONFORMANCE.items():
    name = pathlib.Path(oracle.split()[0]).name
    if kind == "dead":
      ok, detail = dead_lane_is_broken(port, oracle)
      print(f"  {'PASS' if ok else 'FAIL'}  {name}: wired on purpose, and the REAL gate still "
            f"says BROKEN\n        {detail}")
      if not ok:
        fails.append(f"{name}: dead lane stopped being BROKEN")
      continue
    shared_n, disagree, n_bend, n_ora = measured[port]
    print(f"  {port.split('/', 1)[-1]:<34} {oracle.split('/')[-1]:<28} "
          f"{shared_n:>5} / {disagree} / {n_bend} / {n_ora}")
    # A live entry with no measurable intersection has no fixture to drive, and the REASON
    # matters: a lane that produced no rows is an ABSENT measurement, which is a different claim
    # from "this oracle shares nothing with its port". Both fail; they must not read alike, or a
    # reader will take "the interpreter fell over" for "the wiring is fine".
    if shared_n == 0:
      blank = [w for w, n in (("port", n_bend), ("oracle", n_ora)) if not n]
      why = (f"UNMEASURED: the {' and '.join(blank)} lane produced 0 rows, so nothing was "
             f"compared and no fixture can be sized from it") if blank else (
            f"0 shared row names: {n_bend} port rows against {n_ora} oracle rows, NOTHING in common")
      fails.append(f"{name}: {why}")
      print(f"  FAIL  {name}: {why}")
      continue
    if disagree:
      bad = [k for k in set(bend_all[port]) & set(orc_all[oracle]) if bend_all[port][k] != orc_all[oracle][k]]
      where = ", ".join(f"{k!r}: port {bend_all[port][k]!r} vs CPython {orc_all[oracle][k]!r}"
                        for k in sorted(bad))
      fails.append(f"{name}: LIVE TREE DISAGREEMENT on {len(bad)} of {shared_n} shared row names "
                   f"-- a PORT finding, not a roster finding: {where}")
      print(f"  FAIL  {name}: {disagree} of {shared_n} shared row names DISAGREE on the live tree"
            f"\n        {where}\n        corroborated by `rebase-gate.py --port {port}` -> BROKEN, rc=1"
            f"\n        NOT FIXED HERE: the port is not this unit's file.")
      continue
    g = load_gate(f"conformance_{pathlib.Path(oracle.split()[0]).stem}_{shared_n}")
    # THE FIXTURE IS THE ORACLE'S OWN ROW SET, so the states are produced over the names this
    # oracle actually emits. Synthetic names would pass a broken oracle and fail a working
    # one, which is the same inversion as a shape mismatch.
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
    bad = [f"{pathlib.Path(oracle.split()[0]).name}: {nm}" for nm, v, ws, wt in cases
           if not (v["state"] == ws and wt.lower() in v.get("why", "").lower())]
    g.run_port = lambda *a, **k: (ok_lanes, {"interpreted": dict(port_rows),
                                             "cpython:o": dict(port_rows)})
    bad_doc = g.baseline_for({"interpreted": dict(port_rows)}, port)
    if bad_doc[0] is not None or "MALFORMED" not in bad_doc[2] or bad_doc[3]:
      bad.append(f"{pathlib.Path(oracle.split()[0]).name}: malformed baseline")
    print(f"  {'PASS' if not bad else 'FAIL'}  {pathlib.Path(oracle.split()[0]).name}: six "
          f"states reachable (shared_n={shared_n} MEASURED)")
    fails += bad
  return fails


if __name__ == "__main__":
  sys.exit(main())