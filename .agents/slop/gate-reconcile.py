#!/usr/bin/env python3
"""gate-reconcile.py -- make the gate's verdict and the selftest's number RECONCILE, per port.

THE BUG THIS EXISTS FOR. Two tools print numbers about the same lane and they have
disagreed without either saying so:

    rebase-gate.py --port tinybendygrad/device.bend
      AGREE-UNRECORDED   rows interpreted=110 native=110 cpython:device-oracle=23
    rebase-gate-selftest.py
      device.bend  device-oracle.py  23 / 0 / 110 / 23
      PASS  device-oracle.py: six states reachable (shared_n=23 MEASURED)

and a whole-tree sweep printed `BROKEN = ... device.bend` in the same session. Two of those
three numbers are about DIFFERENT THINGS and neither tool says which:

  * the gate's state line is the verdict of FOUR GUARDS over FRESH lanes -- reachability,
    emptiness, comparability+disagreement, and absolute count -- so it can be BROKEN for a
    reason that has nothing to do with whether the rows agree;
  * the selftest's four numbers are measure_roster()'s arithmetic: SHARED / DISAGREE /
    port rows / oracle rows, and the `PASS` beside them is about SIX SYNTHETIC STATES driven
    through gate_port() with run_port() STUBBED. It never runs the port.

So "0 disagreements" and "BROKEN" are not contradictory, they are answers to different
questions -- and until a tool prints both together, a reader has to guess which one they are
holding. THIS PRINTS BOTH, PER PORT, WITH THE DENOMINATOR, AND NAMES ANY DIVERGENCE.

IT CALLS BOTH TOOLS' OWN FUNCTIONS. gate_port()/run_port() are rebase-gate.py's;
bend_rows()/oracle_rows() are rebase-scan-oracles.py's, which measure_roster() also calls.
Neither is restated: rebase-gate-selftest.py's verdict_of() docstring already records that
restating the rule under test is how a green selftest shipped a dead GUARD 1. There is
exactly ONE row parser in this tree -- rebase-scan-oracles.py imports rebase-gate.py's
`rows()` -- so this builds no second reader.

IT SKIPS plan_of(), which costs ~6 minutes on this tree and, for an UNRECORDED port,
contributes nothing: gate_port() only consults the plan to re-word the `hunks` clause of an
UNCHANGED, and device.bend has no baseline. It also skips main()'s TARGET CONSTRUCTION,
which rebase-gate-selftest.py's plan_contract() drives separately and instantly.

  usage: .venv/bin/python .agents/slop/gate-reconcile.py [PORT ...]
         .venv/bin/python .agents/slop/gate-reconcile.py --reps 12 tinybendygrad/device.bend
         .venv/bin/python .agents/slop/gate-reconcile.py --roster

READ-ONLY with respect to the repo. It runs bend and the oracle exactly as the gate does,
including the native binary at the path the gate itself uses, and it writes the same
/tmp/rebase-scan cache rebase-scan-oracles.py writes. Nothing here is a private lane.
"""
import argparse, importlib.util, json, os, pathlib, sys, time

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
GATE = HERE / "rebase-gate.py"
BASELINE = HERE / "rebase" / "baseline.json"

# The four BROKEN entries as the 2026-10-04 whole-tree sweep named them, plus device.bend.
# A default list is a DEFAULT, not a finding: every number printed beside one is measured on
# the tree as it stands when this runs.
DEFAULT_PORTS = [
  "tinybendygrad/device.bend",
  "tinybendygrad/dtype.bend",
  "tinybendygrad/codegen/decomp/dtype.bend",
  "tinybendygrad/renderer/cstyle.bend",
]


def load(name, path):
  spec = importlib.util.spec_from_file_location(name, path)
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


# WHY A VERDICT IS NOT A DISAGREEMENT COUNT, AS A CLASSIFICATION.
#
# The sweep prints four states and a BROKEN list, and BROKEN collapses five different things into
# one word. A reader who sees BROKEN cannot tell a port bug from a harness bug, and `cstyle` is the
# clearest case there is: a lane that shares ZERO row names compared NOTHING, which is a COVERAGE
# fact about the wiring -- not a row that disagrees, and not a port defect. Lumping it with a real
# disagreement makes both unreadable: the reader learns to skim the list, and the real entry in it
# gets skimmed too.
#
# ⚠ THE CLASSIFIER LIVES IN rebase-gate.py NOW (`classify()`), NOT HERE. It used to be duplicated
# here, and two copies of a classifier is two answers to "what is this BROKEN": the sweep stamped
# nothing, so a reader holding the sweep's line and this file's class had no way to tell that they
# were looking at the same verdict through two vocabularies. One function, called by both. The
# names are re-exported so this file's own text still reads the same.



def port_vs_cpython(now):
  """(shared, disagree) for the PORT vs CPython pair, from the gate's own fresh rows.

  THE PAIR MATTERS AND ADDING OVER `compared_pairs` IS WRONG. `compared_pairs` holds every
  lane pair, so for a three-lane run a cpython pair appears TWICE (against interpreted and
  against native) and summing it gives 2x the port-vs-CPython intersection -- 46 where the
  selftest says 23, for three ports that agree perfectly well. The selftest's number is
  |port rows INTERSECT oracle rows|, so that is the pair to compare, and it is computed here
  from `now` with the same set arithmetic GUARD 4 uses rather than read out of `why`.

  Returns None when the run has no cpython lane or no port lane, which is a verdict that
  never reached GUARD 4 -- and the caller must say so rather than reconcile against 0."""
  cps = [k for k in now if k.startswith("cpython:")]
  ports = [k for k in now if not k.startswith("cpython:")]
  if not cps or not ports:
    return None
  out = [(len(set(now[c]) & set(now[p])), sum(1 for k in set(now[c]) & set(now[p])
                                             if now[c][k] != now[p][k]))
         for c in cps for p in ports]
  return max(out)  # the port lane with the most shared names: the strongest claim


def reason_of(g, v):
  """(cause, class, reason) for a verdict -- rebase-gate.py's OWN classifier, not a second one.

  It used to be a 40-line copy living in this file while the sweep stamped no cause at all, so a
  reader holding `TALLY BROKEN=6` and this file's class list had two vocabularies for one verdict
  and no way to know they were the same one. `classify()` moved into rebase-gate.py and is now
  called by both; a second classifier is a second answer."""
  return g.classify(v)


def selftest_number(scan, g, port, oracles):
  """measure_roster()'s arithmetic for one port, plus WHERE THE ROWS CAME FROM.

  measure_roster() is not imported: it hard-codes ORACLE_CONFORMANCE, the very roster under
  suspicion, so importing it would answer the question with the thing being questioned. The
  two lane runners it calls ARE used, and whether each came from cache or from a fresh run is
  reported, because a cached reading and a fresh one are different claims about the same
  lane and the selftest prints neither."""
  out = []
  for spec in oracles:
    src = REPO / spec.split()[0]
    d_b, why_b = scan.cached(scan.port_key(port), REPO / port)
    d_o, why_o = scan.cached(scan.oracle_key(spec), src)
    b, o = scan.bend_rows(port), scan.oracle_rows(spec)
    shared = set(b) & set(o)
    bad = sorted(k for k in shared if b[k] != o[k])
    out.append({"spec": spec, "shared": len(shared), "disagree": len(bad), "bad": bad,
                "n_bend": len(b), "n_oracle": len(o),
                "src": f"bend:{why_b} oracle:{why_o}",
                "bend": b, "oracle": o})
  return out


def reconcile_port(g, scan, port, base):
  """(ok, lines) for ONE port: do the gate's verdict and the selftest's number agree?

  THE RECONCILIATION, and the reason it is a CONTROL rather than a report. Two tools print a
  number about the same lane and nothing checked them against each other, so on 2026-10-04 a
  whole-tree sweep said `BROKEN ... device.bend` while the selftest said `23 / 0 / 110 / 23`
  and PASS -- and neither tool was wrong about what it measured. A sweep's state line is the
  verdict of FOUR GUARDS over FRESH lanes, so it can be BROKEN for a reason that has nothing
  to do with whether the rows agree; the selftest's four numbers are an INTERSECTION and a
  DISAGREEMENT COUNT, which cannot be BROKEN at all. They are answers to different questions
  and the reader has to know which one they are holding.

  So each is checked against the other rather than trusted:

    * the gate's verdict must be REPRODUCIBLE over REPS. One run cannot distinguish a real
      defect from a lane that died on a loaded machine, and this tree has produced 7 FAILs
      that were stack-overflow flakes with load at 19.43. A port whose verdict moves between
      reps is reported as UNSTABLE, which is a finding about the INSTRUMENT.
    * the gate's own port-vs-CPython (shared, disagree) must EQUAL the selftest's. Both call
      the same rows() -- rebase-scan-oracles.py imports rebase-gate.py's parser -- so the
      ONLY thing that can separate them is a cache one read and the other did not, and the
      cache provenance is printed beside the comparison for exactly that reason.
    * the verdict must carry a REASON and a CLASS, because `BROKEN` collapses a port bug and
      a wiring fact into one word and a list like that is unreadable when it does.

  Returns (ok, lines). `ok` is False on any divergence, including an unwired port whose
  BROKEN someone might quote -- never_wired() returning NOT-STARTED IS the reconciliation
  passing, and the line says which."""
  oracles = g.BASE_ORACLES.get(port, ())
  rec = (base.get("lanes") or {}).get(port)
  lines = [f"{port}"]
  if not oracles:
    v = g.never_wired(port, REPO / port, oracles)
    lines += [f"  wired    : NOT IN BASE_ORACLES",
              f"  GATE     : {v['state']}  cause={v['cause']} [{v['class']}]",
              f"  reason   : {v['why'][:160]}",
              f"  selftest : NOT MEASURED -- never_wired() returns before any lane runs",
              f"  VERDICT  : RECONCILED -- BROKEN is UNREACHABLE for this port by "
              f"construction, so a BROKEN naming it came from a DIFFERENT wiring"]
    return True, lines

  seen = []
  for _ in range(REPS):
    v, now = g.gate_port(REPO / port, oracles, base, native=True)
    seen.append((v, now))
  states = {v["state"] for v, _ in seen}
  v, now = seen[0]
  cause, cls, reason = reason_of(g, v)
  ok = True
  lines += [f"  wired    : {list(oracles)}",
            f"  baseline : " + ("recorded " + str({k: len(x) for k, x in sorted(rec.items())})
                               if rec else "NOT RECORDED"),
            f"  GATE     : {v['state']}  cause={cause} [{cls}]",
            f"  reason   : {reason[:200]}",
            f"  rows     : {v['row_counts']}",
            f"  lanes    : " + "  ".join(f"{k}=rc{l['rc']}" for k, l in
                                        sorted(v["lanes"].items()))]
  if len(states) > 1:
    ok = False
    lines.append(f"  !! UNSTABLE over {REPS} reps: { {s: sum(1 for x, _ in seen if x['state'] == s) for s in states} }"
                 f" -- the verdict is a property of the machine, not of the port")
  for n in selftest_number(scan, g, port, oracles):
    lines.append(f"  SELFTEST : {n['spec']}  shared={n['shared']} disagree={n['disagree']} "
                 f"port_rows={n['n_bend']} oracle_rows={n['n_oracle']}  [{n['src']}]")
    pair = port_vs_cpython(now)
    if pair is None:
      lines.append("  RECONCILE: NOT APPLICABLE -- the gate never reached GUARD 4 (see reason)")
      continue
    gs, gd = pair
    same = gs == n["shared"] and gd == n["disagree"]
    ok = ok and same
    lines.append(f"  RECONCILE: {'AGREE' if same else 'DIVERGES'}  gate fresh {gs}/{gd} vs "
                 f"selftest {n['shared']}/{n['disagree']}"
                 + ("" if same else f"  -- one of them read a cache: selftest [{n['src']}]"))
    # A lane that DISAGREES is a DEFECT and must be named, never counted.
    if n["bad"]:
      ok = False
      lines.append(f"  !! DEFECT: {len(n['bad'])} shared row(s) disagree: "
                   + ", ".join(repr(x) for x in n["bad"][:6]))
  lines.append(f"  VERDICT  : {'RECONCILED' if ok else 'DIVERGENT'}")
  return ok, lines


# REPS is module-level so the control and the report agree on what "reproducible" means.
REPS = 2


def sweep_reconcile(g, scan, sweep_path, lanes_ok=True):
  """ENTRY BY ENTRY, an EXISTING sweep against the selftest's numbers. Runs no gate lane.

  ⚠ THIS IS THE RECONCILIATION THAT WOULD HAVE CAUGHT THE 2026-10-04 `BROKEN=6` QUOTED AGAINST
  A GREEN cstyle GATE. It costs nothing because the sweep is a file, and it is the only mode that
  compares the two instruments WITHOUT re-running either -- so it is the one a reader can run
  against a tally somebody else published.

  THE TWO INSTRUMENTS MEASURE DIFFERENT THINGS, and that is the whole content of the table:

    sweep     `rebase-gate.py --json`. Per port: a STATE from FOUR GUARDS over FRESH lanes
              (reachability, emptiness, comparability+disagreement, absolute count). It can be
              BROKEN for a reason that has nothing to do with whether the rows agree, and it is
              the only one of the two that can say UNCHANGED or RE-PORTED.
    selftest  `measure_roster()`. Per port: an INTERSECTION and a DISAGREEMENT COUNT, from
              rebase-scan-oracles.py's lane runners and cache. It has five states and no BROKEN,
              and its `PASS` beside the numbers is about SIX SYNTHETIC STATES driven through
              gate_port() with run_port() STUBBED -- it never runs the port.

  So "0 disagreements" and "BROKEN" are not contradictory. What IS a defect is the pair
  disagreeing about the SAME claim, and that is what this asserts, per port:

    selftest disagree == 0   => sweep cause must NOT be DISAGREE. A sweep BROKEN for
                                ZERO-ROWS / INCOMPARABLE / LANE-DEATH / ROWS-LOST is a
                                COVERAGE or INSTRUMENT finding and is EXPECTED to differ.
    selftest disagree  > 0   => sweep cause MUST be DISAGREE. Anything else means one of the
                                two read something the other did not, and the sweep is red for
                                the wrong reason.
    either side UNMEASUREED  => NOT RECONCILABLE, and it says which lane produced 0 rows. A
                                missing measurement is never rounded to agreement.

  Returns (n_reconciled, n_divergent, lines)."""
  doc = json.loads(pathlib.Path(sweep_path).read_text())
  by_port = {v["port"]: v for v in doc["verdicts"]}
  lines = [f"sweep       {sweep_path}",
           f"  interpreter {doc.get('oracle_py')}  python {doc.get('python')}",
           f"  TALLY {doc.get('tally')}",
           f"  CAUSES {doc.get('causes', '(this sweep predates the cause stamp)')}",
           "",
           f"{'port':<40} {'sweep':<17} {'cause':<13} {'selftest shared/disagree of':<28} verdict",
           "-" * 132]
  good = bad = 0
  for port in sorted(by_port):
    v = by_port[port]
    if "cause" not in v:  # a sweep written before the cause stamp: classify it now, with the
      v = g.stamp(dict(v, lanes=v.get("lanes", {}), row_counts=v.get("row_counts", {})))  # same fn
    cause = v["cause"]
    if not g.BASE_ORACLES.get(port):
      # ⚠ AND IF THE SWEEP SAYS BROKEN HERE, THAT IS THE FINDING. never_wired() returns
      # NOT-STARTED before any lane runs, so a BROKEN naming an unwired port is unreachable from
      # this wiring -- it is a verdict pasted from a run whose BASE_ORACLES differed. Counting it
      # as reconciled would be the reconciliation agreeing with the thing it is checking.
      hit = v["state"] == g.BROKEN
      bad += hit
      good += not hit
      lines.append(f"{port.split('/', 1)[-1]:<40} {v['state']:<17} {cause:<13} "
                   f"{'NOT MEASURED (never_wired runs no lane)':<28} "
                   + ("DIVERGES: BROKEN is UNREACHABLE for an unwired port BY CONSTRUCTION, so "
                      "this verdict came from a DIFFERENT wiring" if hit else
                      "RECONCILED: BROKEN is UNREACHABLE here, so a BROKEN naming this port came "
                      "from a DIFFERENT wiring"))
      continue
    if not lanes_ok:
      lines.append(f"{port.split('/', 1)[-1]:<40} {v['state']:<17} {cause:<13} "
                   f"{'FORBIDDEN (--no-lanes)':<28} UNMEASURED -- not a passing reconciliation")
      bad += 1
      continue
    n = selftest_number(scan, g, port, g.BASE_ORACLES[port])[0]
    num = f"{n['shared']}/{n['disagree']} of {n['n_bend']}+{n['n_oracle']}"
    if not n["n_bend"] or not n["n_oracle"]:
      blank = [w for w, c in (("port", n["n_bend"]), ("oracle", n["n_oracle"])) if not c]
      lines.append(f"{port.split('/', 1)[-1]:<40} {v['state']:<17} {cause:<13} "
                   f"{num:<28} UNMEASURED: the {' and '.join(blank)} lane produced 0 rows "
                   f"[{n['src']}]")
      bad += 1
      continue
    if n["disagree"] and cause != g.CAUSE_DISAGREE:
      verdict = (f"DIVERGES: {n['disagree']} of {n['shared']} shared names disagree but the "
                 f"sweep's cause is {cause}, so the sweep is red for the WRONG reason")
      bad += 1
    elif not n["disagree"] and cause == g.CAUSE_DISAGREE:
      verdict = (f"DIVERGES: the sweep says {len(v.get('disagreements', []))} disagree while the "
                 f"selftest measures {n['disagree']} of {n['shared']} -- one read a cache")
      bad += 1
    elif not n["disagree"] and cause != g.CAUSE_NONE:
      verdict = (f"RECONCILED as EXPECTED: selftest 0 disagree vs sweep cause {cause} -- the two "
                 f"instruments measure different things, and this is what that looks like")
      good += 1
    else:
      verdict = f"RECONCILED: 0 of {n['shared']} shared names disagree, and the sweep agrees"
      good += 1
    if n["bad"]:
      verdict += f"  [{', '.join(repr(k) for k in n['bad'][:3])}]"
    lines.append(f"{port.split('/', 1)[-1]:<40} {v['state']:<17} {cause:<13} {num:<28} {verdict}")
  lines.append("-" * 132)
  reds = [(c, doc.get("causes", {}).get(c, 0)) for c in (g.CAUSE_DISAGREE, g.CAUSE_ZERO_ROWS,
                                                         g.CAUSE_INCOMPARABLE, g.CAUSE_LANE_DEATH,
                                                         g.CAUSE_ROWS_LOST)]
  reds = [f"{c}={n}" for c, n in reds if n]
  lines.append(f"{good} reconciled, {bad} divergent, of {len(by_port)} sweep entries. "
               f"BROKEN BY CAUSE {reds or '(none)'} -- of which only DISAGREE is a defect in a "
               f".bend file")
  return good, bad, lines


def _conformance():
  """rebase-gate-selftest.py's ORACLE_CONFORMANCE, imported not restated: it is one of the two
  rosters under reconciliation, and a second copy is a third answer."""
  return load("gate_reconcile_st", HERE / "rebase-gate-selftest.py").ORACLE_CONFORMANCE


def lane_control(g, port, st):
  """THE PER-LANE CONTROL: clean -> AGREE rc=0, ONE PLANTED ROW -> BROKEN rc=1 NAMED, restore
  BYTE-IDENTICAL. Through the REAL run_port, real .bend lanes and real CPython subprocesses.

  The row is CHOSEN by running the pair and taking the first shared name whose two lanes AGREE, so
  the plant cannot land in nothing and a control that degraded into "planted into no row" would
  report a clean pair as clean. The mutant lane is rebase-gate-selftest.py's OWN `mutant_lane` --
  a wrapper that runs the real oracle and rewrites exactly one line -- so the only difference
  between the two lanes is the corruption. Nothing on disk is edited, which is why the restore is
  checked by the ROWS coming back rather than by a hash of a file: there is no file to hash.

  ⚠ AND IT IS ALSO THE CONTROL FOR THE COMPILED LANE'S PATH. `dtype.bend` and
  `codegen/decomp/dtype.bend` are the only two WIRED ports sharing a stem, and run them at the
  same time, so if `native_bin()` were still keyed on the stem one of them would execute the
  other's binary and `interpreted != native` -- which GUARD 4 would report as a manufactured
  BROKEN. A control that only ever runs one port at a time cannot see that bug at all.
  """
  import tempfile
  oracles = g.BASE_ORACLES[port]
  bend = REPO / port
  lanes, clean = g.run_port(bend, list(oracles), True)
  counts = {k: len(v) for k, v in clean.items()}
  out = [f"{port}", f"  lanes  {counts}  " + "  ".join(f"{k}=rc{l['rc']}" for k, l in
                                                          sorted(lanes.items()) if k != 'check')]
  v = gate_with(g, {"lanes": {}, "hunks": {}}, clean)
  out.append(f"  clean  -> {v['state']} cause={v['cause']} [{v['class']}]  {v['cause_reason'][:110]}")
  if _conformance_kind(port) == "dead":
    # Wired ON PURPOSE to a lane that cannot compare. Its control is that it IS red: a lane that
    # stopped being BROKEN is the failure, not a green. There is nothing to plant into, because
    # there is nothing agreeing to plant into.
    return out, v["state"] == g.BROKEN
  ok = v["state"] in (g.AGREE_UNRECORDED, g.UNCHANGED) and bool(clean["interpreted"])
  cps = [k for k in clean if k.startswith("cpython:")]
  shared = sorted(set(clean["interpreted"]) & set(clean[cps[0]])) if cps else []
  row = next((k for k in shared
              if clean["interpreted"][k] == clean[cps[0]][k] and clean["interpreted"][k]), None)
  out.append(f"  clean  -> rc=0 required; shared(interpreted,{cps[0] if cps else '-'})="
             f"{len(shared)} of {len(clean['interpreted'])} port rows, "
             f"{len(clean[cps[0]]) if cps else 0} oracle rows")
  if row is None:
    out.append("  plant  -> FAIL: the pair shared no row whose two lanes AGREE, so the plant had "
               "nothing to corrupt and this control proved nothing")
    return out, False
  with tempfile.TemporaryDirectory() as td:
    _, planted = g.run_port(bend, [st.mutant_lane(oracles[0], row, td)], True)
  p = gate_with(g, {"lanes": {}, "hunks": {}}, planted)
  named = [d for d in p.get("disagreements", []) if d[2] == row]
  out.append(f"  plant  -> {p['state']} cause={p['cause']} rc=1 required, NAMES {row!r}: "
             f"{bool(named)}  {p['cause_reason'][:100]}")
  ok = ok and p["state"] == g.BROKEN and bool(named)
  same = g.run_port(bend, list(oracles), True)[1] == clean
  out.append(f"  restore-> byte-identical to the clean reading: {same} (nothing on disk was "
             "edited, so this compares ROW SETS, not a file digest)")
  return out, ok and same


def _conformance_kind(port):
  return _conformance().get(port, (None, None))[1]


def gate_with(g, doc, rows_by_lane):
  """gate_port() with run_port() REPLACED for the duration of the call, for reading a verdict off
  rows ALREADY COLLECTED here.

  ⚠ IT MUTATES `g` AND PUTS IT BACK, because a function's globals are its DEFINING module's dict:
  a `types.ModuleType` copy with `__dict__.update(g.__dict__)` leaves `gate_port`'s `__globals__`
  pointing at `g`, so the stub is never called and the caller silently measures the LIVE tree.
  rebase-gate-selftest.py's docstring records the same trap ("FOUR MODULES, NOT ONE") and pays for
  it with four module loads; a save/restore is one line and one module, and the restore is in a
  `finally` so a raised verdict cannot leave the gate stubbed for the next port."""
  was = g.run_port
  g.run_port = lambda *a, **k: ({n: {"rc": 0} for n in rows_by_lane}, rows_by_lane)
  try:
    return g.gate_port(REPO / "tinybendygrad/probe.bend", ["o"], doc, native=True)[0]
  finally:
    g.run_port = was


def _selftest():
  return load("gate_reconcile_selftest", HERE / "rebase-gate-selftest.py")


def run_controls(g, ports, workers):
  """Every wired lane, clean / planted / restored, CONCURRENTLY and independently reported.

  Concurrency is here because the control is three real gate runs per port over 39 ports, and
  serially that is an hour nobody will sit through. It is also the honest way to exercise the
  control: the lanes are separate OS processes, so two ports in flight is the condition under
  which a stem-keyed binary path could hand one port another's rows -- and `dtype.bend` and
  `codegen/decomp/dtype.bend`, the only two wired ports sharing a stem, are BOTH in this list.
  `workers` is printed with the load at both ends, because a loaded machine produces red here too
  and an unexplained red on a control is indistinguishable from a control that worked.
  """
  import concurrent.futures as cf
  st = _selftest()
  ok_n, fails = 0, []
  print(f"PER-LANE CONTROL: {len(ports)} wired lane(s), {workers} in flight, "
        f"load {os.getloadavg()[0]:.2f}\n")
  with cf.ThreadPoolExecutor(max_workers=workers) as pool:
    for lines, ok in pool.map(lambda p: lane_control(g, p, st), ports):
      print("\n".join(lines))
      print(f"  {'PASS' if ok else 'FAIL'}  {lines[0]}")
      ok_n += ok
      if not ok:
        fails.append(lines[0])
      print()
  print("=" * 100)
  print(f"{ok_n}/{len(ports)} lanes: clean -> AGREE rc=0, one planted row -> BROKEN rc=1 naming "
        f"it, restore byte-identical.  load {os.getloadavg()[0]:.2f}")
  if fails:
    print(f"{len(fails)} FAILED: {', '.join(fails)}")
  return 1 if fails else 0


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("ports", nargs="*", default=None)
  ap.add_argument("--reps", type=int, default=1,
                  help="run the gate N times over the SAME port. One verdict cannot tell a "
                       "real lane death from a loaded-machine flake; the spread can.")
  ap.add_argument("--roster", action="store_true",
                  help="WIRING ONLY, no lanes: list every port BASE_ORACLES wires and whether "
                       "a baseline is recorded. This is the cheap half and it is enough to "
                       "check a quoted tally against, because NOT-STARTED is pinned by the "
                       "roster and never by a lane. Run this before --reconcile: a whole "
                       "roster reconciliation runs every real lane on every port")
  ap.add_argument("--reconcile", action="store_true",
                  help="the CONTROL: for each port, check the gate's verdict against the "
                       "selftest's number and require both to be reproducible and "
                       "self-consistent. Non-zero exit on any divergence")
  ap.add_argument("--sweep", default=None, metavar="SWEEP_JSON",
                  help="reconcile an EXISTING `rebase-gate.py --json` sweep against the "
                       "selftest's numbers, entry by entry, running no gate lane. This is the "
                       "mode that catches a quoted BROKEN list, because it costs nothing and "
                       "compares the two instruments that disagreed")
  ap.add_argument("--no-lanes", action="store_true",
                  help="in --sweep, refuse to RUN any lane. Every port then reports UNMEASURED, "
                       "which FAILS: a reconciliation that passes by measuring nothing is the "
                       "failure this file exists to prevent")
  ap.add_argument("--control", action="store_true",
                  help="the PER-LANE CONTROL: for each wired port, clean -> AGREE rc=0, then ONE "
                       "planted disagreement -> BROKEN rc=1 naming the row, then restore "
                       "byte-identical. Expensive: three real gate runs per port")
  ap.add_argument("--workers", type=int, default=4,
                  help="ports in flight for --control. 1 is serial; the lanes are independent "
                       "processes, and a loaded machine is itself a source of red (load 19.43 has "
                       "produced 7 stack-overflow flakes in this tree), so this is a knob that "
                       "changes what you measure, not a speed flag")
  a = ap.parse_args()
  global REPS
  REPS = max(1, a.reps)

  g = load("gate_reconcile_gate", GATE)
  scan = load("gate_reconcile_scan", HERE / "rebase-scan-oracles.py")
  base = json.loads(BASELINE.read_text()) if BASELINE.exists() else {}
  if a.roster:
    # WIRING ONLY. NOT-STARTED is decided by never_wired() before any lane runs, so the
    # roster alone pins that bucket -- which is what makes a quoted tally checkable without
    # spending a lane on any port. That is the whole reason this mode exists separately.
    print(f"{'port':<46} {'wired':<6} {'baseline':<9} oracles")
    for p in sorted(set(g.BASE_ORACLES) | set(base.get("lanes") or {})):
      o = g.BASE_ORACLES.get(p)
      print(f"{p:<46} {'yes' if o else 'NO':<6} "
            f"{'recorded' if p in (base.get('lanes') or {}) else '-':<9} "
            f"{list(o) if o else 'NOT IN BASE_ORACLES -> BROKEN UNREACHABLE'}")
    unpinned = 50 - len(set(g.BASE_ORACLES) | set(base.get("lanes") or {}))
    print(f"\nNOT-STARTED is pinned at {unpinned} by the roster alone "
          f"(50 targets - {len(set(g.BASE_ORACLES) | set(base.get('lanes') or {}))} known)")
    return 0

  if a.sweep:
    good, bad, lines = sweep_reconcile(g, scan, a.sweep, not a.no_lanes)
    print("\n".join(lines))
    return 1 if bad else 0

  if a.control:
    return run_controls(g, sorted(g.BASE_ORACLES), a.workers)

  ports = a.ports or DEFAULT_PORTS

  print(f"gate interpreter {g.ORACLE_PY}")
  print(f"scan interpreter {sys.executable}   (rebase-scan-oracles.py uses sys.executable, "
        f"NOT oracle_py -- see the header)")
  print(f"load at start {os.getloadavg()[0]:.2f}  reps per port {REPS}\n")

  if a.reconcile:
    bad = []
    for port in ports:
      ok, lines = reconcile_port(g, scan, port, base)
      print("\n".join(lines))
      print(f"  {'PASS' if ok else 'FAIL'}  {pathlib.Path(port).name}")
      if not ok:
        bad.append(port)
      print()
    print("=" * 100)
    print(f"{len(ports) - len(bad)}/{len(ports)} ports reconcile; load at end "
          f"{os.getloadavg()[0]:.2f}")
    return 1 if bad else 0

  for port in ports:
    oracles = g.BASE_ORACLES.get(port, ())
    rec = (base.get("lanes") or {}).get(port)
    print("=" * 100)
    print(f"{port}")
    print(f"  wired        : {list(oracles) or 'NOT IN BASE_ORACLES'}")
    print(f"  baseline     : " + ("recorded, lanes " +
          str({k: len(v) for k, v in sorted(rec.items())}) if rec else "NOT RECORDED"))
    if not oracles:
      v = g.never_wired(port, REPO / port, oracles)
      print(f"  GATE         : {v['state']}  cause={v['cause']} [{v['class']}]")
      print(f"  reason       : {v['cause_reason']}")
      print(f"  selftest num : NOT MEASURED -- never_wired() returns before any lane runs, so "
            f"there is nothing to reconcile")
      print()
      continue

    verdicts = []
    for rep in range(1, a.reps + 1):
      before = os.getloadavg()[0]
      t0 = time.monotonic()
      v, now = g.gate_port(REPO / port, oracles, base, native=True)
      verdicts.append((before, time.monotonic() - t0, v, now))
    print(f"  load / secs  : " + ", ".join(f"{b:.1f}/{d:.0f}s" for b, d, _, _ in verdicts))
    for before, _, v, now in verdicts:
      cause, cls, reason = reason_of(g, v)
      print(f"  GATE         : {v['state']}  cause={cause} [{cls}]")
      print(f"  reason       : {reason}")
      print(f"  rows         : {v['row_counts']}")
      print(f"  lanes        : " + "  ".join(f"{k}=rc{l['rc']}" for k, l in
                                             sorted(v["lanes"].items())))
      for k, l in sorted(v["lanes"].items()):
        if l["rc"] != 0 and k != "check":
          print(f"      {k} stderr tail: {' '.join(l['err'].split())[-220:]}")
    states = {v["state"] for _, _, v, _ in verdicts}
    if len(states) > 1:
      print(f"  !! {len(verdicts)} REPS DISAGREE on the STATE: "
            f"{ {b: v['state'] for b, _, v, _ in verdicts} } -- this is the flake, and a "
            f"single-rep sweep cannot see it")

    for n in selftest_number(scan, g, port, oracles):
      print(f"  SELFTEST NUM : {n['spec']}  shared={n['shared']} disagree={n['disagree']} "
            f"port_rows={n['n_bend']} oracle_rows={n['n_oracle']}  [{n['src']}]")
      if n["bad"]:
        print(f"      disagreeing: {', '.join(repr(k) for k in n['bad'][:8])}")
      # THE RECONCILIATION. Both numbers are about the same two row sets, so they must agree.
      # If they do not, one of them read a cache and the other ran the lane -- which is the
      # only mechanism that can separate them, because both call the SAME rows().
      for _, _, v, now in verdicts:
        pair = port_vs_cpython(now)
        if pair is None:
          print(f"  RECONCILE    : NOT APPLICABLE -- the gate never reached GUARD 4 (reason "
                f"above), so it made no port-vs-CPython comparison to reconcile")
          continue
        gs, gd = pair
        agree = (gs == n["shared"] and gd == n["disagree"])
        print(f"  RECONCILE    : {'AGREE' if agree else 'DIVERGES'}  "
              f"(gate fresh: {gs} shared / {gd} disagree  vs  "
              f"selftest {n['src']}: {n['shared']} / {n['disagree']})")
        if not agree:
          print(f"      the two numbers are about the same pair and disagree, so one of them "
                f"read a cache the other did not: selftest rows came [{n['src']}]")
    print()

  print("=" * 100)
  print(f"load at end {os.getloadavg()[0]:.2f}")
  return 0


if __name__ == "__main__":
  sys.exit(main())