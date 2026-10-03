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
# The sweep prints four states and a BROKEN list, and BROKEN collapses five different things
# into one word. A reader who sees BROKEN cannot tell a port bug from a harness bug, and
# `cstyle` is the clearest case there is: its lane shares ZERO row names, so nothing was
# compared, which is a COVERAGE fact about the wiring -- not a row that disagrees, and not a
# port defect. Lumping it with a real disagreement makes both unreadable: the reader learns
# to skim the list, and the real entry in it gets skimmed too.
#
# So every verdict gets a REASON and a CLASS, and the class is the thing to act on.
#   DEFECT     a claim was compared and came out different. Act on the port.
#   COVERAGE   two lanes that cannot be compared, or an oracle that emits nothing this
#              reader can see. Nothing is wrong with the port; the WIRE is.
#   INSTRUMENT a lane did not run. Could be a real crash or a loaded-machine flake, and the
#              two are told apart by REPS, not by reading the message.
#   RECORDING  compared clean, and nobody wrote it down.
#   ABSENCE    nothing was compared because nothing was wired, or the file is gone.
CLASS_DEFECT, CLASS_COVERAGE, CLASS_INSTRUMENT = "DEFECT", "COVERAGE", "INSTRUMENT"
CLASS_RECORDING, CLASS_ABSENCE = "RECORDING", "ABSENCE"


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


def reason_of(v):
  """(reason, class) for a verdict, read from the verdict's own STRUCTURE.

  Read from the fields verdict() sets rather than by substring-matching its English, because
  a message that changes wording must not silently reclassify a defect -- that is precisely
  how 'it crashes' outlived the crash it described and became a stale reason. `lanes` and
  `row_counts` are consulted for the guards that return without stamping a field."""
  lanes, rows = v["lanes"], v.get("row_counts", {})
  died = sorted(k for k, l in lanes.items() if l["rc"] != 0 and k != "check")
  if died:
    detail = "; ".join(f"{k} rc={lanes[k]['rc']}" for k in died)
    zero = [k for k in died if not rows.get(k)]
    # A lane that both failed AND emitted nothing is the more specific of the two findings,
    # and the distinction matters: `interpreted` rc=1 with SOME PROOFS FAIL and no main is a
    # declared condition of a seam file, while rc=1 with a stack trace is an instrument.
    return (f"GUARD 3 lane death: {detail}"
            + ("  (and the dead lane emitted ZERO rows too)" if zero else ""),
            CLASS_INSTRUMENT)
  empty = sorted(k for k, x in rows.items() if not x)
  if empty:
    return (f"GUARD 2 empty lane: {', '.join(empty)} emitted no name=value row, so it "
            "compared nothing and agrees with nothing", CLASS_COVERAGE)
  if v.get("uncompared_pairs"):
    pairs = ", ".join(f"{a} vs {b} (0 shared)" for a, b, _ in v["uncompared_pairs"])
    return f"GUARD 4 incomparable: {pairs}. A NAMES mismatch is not a disagreement and not " \
           "a port defect -- the wiring cannot compare these two lanes", CLASS_COVERAGE
  if v.get("disagreements"):
    named = ", ".join(f"{d[2]!r}" for d in v["disagreements"][:6])
    return (f"GUARD 4 disagreement: {v['disagreements'].__len__()} row(s), first: {named}",
            CLASS_DEFECT)
  if "LOST ROWS" in v.get("why", ""):
    return f"GUARD 1 absolute count: {v['why']}", CLASS_DEFECT
  if v["state"] == "AGREE-UNRECORDED":
    pairs = v.get("compared_pairs", [])
    tot = sum(n for _, _, n in pairs)
    return (f"compared clean over {len(pairs)} pair(s), {tot} shared row names, all agreeing; "
            "no baseline recorded", CLASS_RECORDING)
  if "NO SUCH FILE" in v.get("why", ""):
    return v["why"], CLASS_ABSENCE
  return v.get("why", ""), CLASS_RECORDING if v["state"] in ("UNCHANGED", "RE-PORTED") \
      else CLASS_ABSENCE


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
              f"  GATE     : {v['state']}  [{CLASS_ABSENCE}]",
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
  reason, cls = reason_of(v)
  ok = True
  lines += [f"  wired    : {list(oracles)}",
            f"  baseline : " + ("recorded " + str({k: len(x) for k, x in sorted(rec.items())})
                               if rec else "NOT RECORDED"),
            f"  GATE     : {v['state']}  [{cls}]",
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
  a = ap.parse_args()
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
      reason, cls = (v["why"], CLASS_ABSENCE if "NO SUCH FILE" in v["why"] else CLASS_ABSENCE)
      print(f"  GATE         : {v['state']}  [{cls}]")
      print(f"  reason       : {reason}")
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
      reason, cls = reason_of(v)
      print(f"  GATE         : {v['state']}  [{cls}]")
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