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
  # And the two ports wired ON PURPOSE to be BROKEN must not be classified as never-wired:
  # their BROKEN verdict is a reachable state, not a missing wiring.
  dead = [p for p in g.BASE_ORACLES if p.endswith(("dtype.bend", "renderer/cstyle.bend"))]
  ok("the deliberately-BROKEN pair is still classified comparable, not never-wired",
     all(g.never_wired(p, REPO / p, g.BASE_ORACLES[p]) is None for p in dead),
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
# what they emit rather than for being convenient:
#
#   schedule/prepare.bend + prepare-oracle.py   THE LANE THE DEFECT IS ABOUT. prepare-oracle.py
#       prints 14 `== SECTION ==` banners; split on the FIRST `=` each has an EMPTY name, so all
#       fourteen landed on ONE key and the oracle reported 2522 rows where it has 2521.
#   renderer/tc_ptx.bend + tcptx-oracle.py      the OTHER print shape, `name = [v]   py=[w]`, so
#       the proof covers an emitter with spaces in the name and a second `=` in the value.
#   uop/fold.bend + mm-lift-gate.py              201 port rows; one of the eight whose ORACLE cache
#       held `{}`, i.e. the item-1 defect seen through a lens.
#   renderer/amd/generate.bend + ga-oracle.py    726 port rows against 779 oracle rows, 0 shared
#       disagreements -- the pair whose stale `84` is item 2.
SUPERSET_LANES = [
  ("tinybendygrad/schedule/prepare.bend", ".agents/slop/prepare-oracle.py"),
  ("tinybendygrad/renderer/tc_ptx.bend", ".agents/slop/tcptx-oracle.py stage2"),
  ("tinybendygrad/uop/fold.bend", ".agents/slop/mm-lift-gate.py"),
  ("tinybendygrad/renderer/amd/generate.bend", ".agents/slop/ga-oracle.py"),
]


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
  """ITEM 3's PROOF: the fixed `rows()` RETURNS EVERY ROW THE OLD ONE RETURNED.

  `rows()` used to key on the empty string when a line began with `=`, which is what all 14 of
  prepare-oracle.py's `== SECTION ==` banners do. So it reported 2522 rows where the oracle has
  2521 -- a count off by one for a STRUCTURAL reason, which is the kind nobody can check by
  looking at the rows. It is fixed. The question this answers is not "is the new count smaller"
  (of course it is, by exactly the phantom) but "IS THE NEW PARSER A SUPERSET OF THE OLD ONE",
  because `rows()` is shared by 38 wired gates and a parser that silently drops or renames a row
  makes some OTHER gate agree by comparing nothing.

  `rows()` is loaded from the gate, never restated. `rows_before_fix` is the only restatement in
  this file and it is labelled as the control's reference.

  TWO PARTS, and the second is the one that matters:

    1. THE PROPERTY, over synthetic text and over four REAL lane pairs: every key the old parser
       produced is present in the new one with the SAME value, and the only keys the new parser
       drops are the empty-named ones.
    2. THE CONSEQUENCE, driven through the real `gate_port()`: GUARD 4 compares lanes over the keys
       they SHARE, so removing a key can only SHRINK that intersection. Dropping a phantom
       therefore cannot turn a real disagreement into a match -- it turns "agreed on a banner"
       into "compared nothing", and "compared nothing" is BROKEN. Both directions are driven:
       a pair whose ONLY shared key was a banner, agreeing AND disagreeing, plus a real named row
       that differs. A one-directional test is half a test.
  """
  g = load_gate("rebase_gate_superset")
  fixed, old = g.rows, rows_before_fix
  fails = []

  def ok(name, cond, detail=""):
    print(f"  {'PASS' if cond else 'FAIL'}  {name}" + (f"\n        {detail}" if detail else ""))
    if not cond:
      fails.append(name)

  def superset_of(text, label):
    """(ok, detail) for one block of text. Every old key present, same value, and every dropped
    key EMPTY -- named, because a superset with a non-empty deletion is a different defect and
    the reader needs to be able to tell them apart."""
    n, o = fixed(text), old(text)
    dropped = [k for k in o if k not in n]
    changed = [k for k in o if k in n and o[k] != n[k]]
    detail = f"{label}: old={len(o)} new={len(n)} dropped={[k for k in dropped]} changed={changed}"
    return not dropped or all(not k for k in dropped), not changed, detail

  # ---- PART 1, synthetic. The three shapes this parser has to survive, in one text.
  SYNTH = ("== A: TABLES ==\n"                       # empty name -> a phantom under the old rule
           "PTX tensor_cores sm_75 = [1, 2]   py=[3]\n"   # SPACES in the name, two `=`
           "load=0\n"                                  # tight, and a value that is not empty
           "empty value row=0\n"                       # EMPTY VALUE, which IS a row
           "= trailing equals in the value\n"          # empty name again
           "load=1\n")                                 # a MOVE, to catch value drift
  keep, same, detail = superset_of(SYNTH, "synthetic")
  ok("synthetic: the fixed parser is a superset, and every dropped key is empty-named", keep, detail)
  ok("synthetic: no surviving key's VALUE changed", same)
  ok("synthetic: exactly the empty-named lines are dropped, and they were ONE key before",
     set(old(SYNTH)) - set(fixed(SYNTH)) == {""} and len(old(SYNTH)) - len(fixed(SYNTH)) == 1,
     f"old keys {sorted(old(SYNTH))}\n        new keys {sorted(fixed(SYNTH))}")

  # ---- PART 1, real lanes. Both parsers on the same stdout, both counts printed.
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
      keep, same, detail = superset_of(text, f"{port} {label}")
      ok(f"{pathlib.Path(port).name} {label}: fixed rows() is a superset of the old one", keep, detail)
      ok(f"{pathlib.Path(port).name} {label}: no surviving key's VALUE changed", same)
  # A sweep in which nothing ran must not be able to report four quiet passes, which is the
  # "0 rows is indistinguishable from not started" trap wearing the costume of a passing check.
  ok(f"the superset proof MEASURED {measured} real lanes, not 0", measured >= 6,
     f"{measured} of {2 * len(SUPERSET_LANES)} lanes measured")

  # ---- PART 2, the consequence, through the real gate_port() AND the real rows().
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
  "tinybendygrad/renderer/cstyle.bend": (".agents/slop/renderer_oracle.py cstyle", "dead"),
}

# NOT WIRES, and named here as well as in BASE_ORACLES because a roster that only records
# what passed cannot answer "why is this one missing?" -- which is the question the next
# reader asks about every port that is NOT-STARTED.
#
# ⚠ IT IS EMPTY, AND AN EMPTY ROSTER IS NOT AN ABSENCE OF THE QUESTION. Every one of the 50
# targets is either wired in BASE_ORACLES or named here; that is what the disjointness
# assertion below checks, and it is checked so that adding a port to one list and not the
# other cannot pass. The roster being empty says the QUESTION is now answered for every
# port, not that no port needs it. As of 2026-10-03, `device.bend` was the only entry; it is
# gone because the row that blocked it was a real port bug and the bug was fixed:
#
#   THE CONTROL, AND WHY THE ROSTER EXISTS AT ALL. The rule this file is built around is
#   that a lane is not wired until it has been SEEN RED. So device.bend's control ran all
#   three readings through the REAL gate (three real bend lanes, a real CPython subprocess,
#   `main()`'s own rc), and the planted disagreement named the row:
#
#     1 clean      rebase-gate.py --port tinybendygrad/device.bend
#                    -> AGREE-UNRECORDED, rc=0. rows interpreted=110 native=110
#                       cpython:device-oracle=23. 0 disagreements.
#     2 PLANTED    the same entry, one path swapped for
#                  .agents/slop/device-oracle-MUTANT.py, which is device-oracle.py with
#                  exactly one line changed -- allow_lower answers 0 instead of 1, proven to
#                  be one line by the mutant itself before it prints a row. Nothing else
#                  touched, and the port not touched at all.
#                    -> BROKEN, rc=1, why = "2 row(s) disagree with CPython across 3 lane
#                       pair(s)", and `disagreements` NAMES the row `allow_lower` for
#                       cpython-vs-interpreted and cpython-vs-native. TWO of the three
#                       pairs, and that is correct rather than a shortfall: the third is
#                       interpreted-vs-native, both lanes being the same port, so it
#                       cannot disagree with itself.
#     3 restored   entry back to device-oracle.py. The gate's stdout is BYTE-IDENTICAL to
#                  reading 1, and both edited files hash to their pre-plant values.
#
#   Reading 2 is the one that matters. A gate that has only ever printed AGREE-UNRECORDED
#   is indistinguishable from a gate that cannot fail, which is the whole reason this file
#   exists; and the planted row is the SAME row the port fix moved, so the control would
#   have caught a regression of the very fix that opened the lane.
#
#   ⚠ THE MECHANISM, because it was looked for and is NOT there: `rebase-gate.py --oracle`
#   LOOKS like the way to do this without editing anything, and it is a NO-OP. main() calls
#   targets_of(), which SNAPSHOTS `tuple(BASE_ORACLES.get(port, []))`, and only then applies
#   `BASE_ORACLES[port] = [a.oracle]`; the gate loop iterates the snapshot. Measured on this
#   tree: `--port tinybendygrad/device.bend --oracle .agents/slop/device-oracle.py` printed
#   `[oracle-override] ... -> device-oracle.py` and then answered `NOT-STARTED ... no oracle
#   wired in BASE_ORACLES`, and for an ALREADY-WIRED port it ran the BASE oracle anyway. The
#   flag whose stated reason for existing is "prove a planted disagreement WITHOUT editing
#   this file" cannot do that for any port. REPORTED, NOT FIXED: rebase-gate.py is another
#   unit's file mid-edit. The control above therefore plants by editing the entry and
#   restoring it, and PROVES the restore with a hash rather than with a `finally`.
ORACLE_NOT_WIRED: dict[str, str] = {}


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