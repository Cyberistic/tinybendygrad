#!/usr/bin/env python3
"""lanedeath-census.py -- HOW MANY OF THIS PROJECT'S RED ENTRIES WERE SUBSTRATE AND NOT PORT?

Every recorded gate verdict on disk is read, every BROKEN entry is classified by asking ONE
question of the evidence rather than by trusting the prose that reported it:

    does the def named in this lane's error live in the port's own import closure, and is it the
    PORT?

`rebase-gate.error_site()` is the reader, so the census and the gate's own new reporting cannot
disagree about what a def name refers to -- a census with its own resolver would be free to be
wrong in the direction that makes the number flattering.

FOUR ANSWERS, not two, because collapsing them is what produced `BROKEN=6`:

    PORT        the error's def is in the port            -> a defect in a .bend file
    SUBSTRATE   the error's def is in an IMPORTED file    -> one edit, N victims, 0 defects
    UNRESOLVED  the def is nowhere in the closure         -> the message is about a revision of
                                                            the tree that no longer exists
    NO-DEF      the error names no def at all             -> classified as such, not guessed at

AND THE DENOMINATOR IS NOT OPTIONAL. Every line prints `n of N`, where N is the number of BROKEN
entries in that artefact and the number of verdicts in it. A census that reports "9 substrate"
without the number of reds it was drawn from is the disagreement-count-without-a-denominator this
project has paid for repeatedly.

ARTEFACTS, and what each one is, because a reader must know whether a number is a measurement or
a quotation:
    *_sweep*.json / *.json under rebase/   gate --json output: real verdicts, with lane stderr
    everything else                       NOT read

RUN:  .venv/bin/python .agents/slop/lanedeath-census.py
      .venv/bin/python .agents/slop/lanedeath-census.py --verbose
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

GATE = HERE / "rebase-gate.py"


def load_gate(name="rg_census"):
  spec = importlib.util.spec_from_file_location(name, GATE)
  mod = importlib.util.module_from_spec(spec)
  sys.modules[name] = mod
  spec.loader.exec_module(mod)
  return mod


def artefacts():
  """Every JSON that carries a `verdicts` list with a `port` on each entry. Named in the output."""
  found = []
  for p in sorted(HERE.rglob("*.json")):
    if p.name in ("baseline.json", "baseline-DEMO.json", "survey-cache.json",
                  "stability-2026-10-03.json", "portrows.json"):
      continue        # baselines hold ROWS, not verdicts; stability holds a measurement, not a tally
    try:
      d = json.loads(p.read_text())
    except (ValueError, OSError):
      continue
    if isinstance(d, dict) and isinstance(d.get("verdicts"), list) and d["verdicts"] \
       and all(isinstance(v, dict) and "port" in v for v in d["verdicts"]):
      found.append((p, d))
  return found


def classify(g, port, err):
  """(bucket, where). `where` is the file the def resolved to, or None."""
  bend = REPO / port
  if not bend.exists():
    return ("NO-DEF", "port not on disk -- nothing to resolve against")
  try:
    closure = g.import_closure(bend)
  except Exception as e:                                   # noqa: BLE001
    return ("NO-DEF", f"closure unreadable: {type(e).__name__}")
  hits = g.error_site(err or "", closure)
  if not hits:
    return ("NO-DEF", "the error names no def")
  port_rel = g.port_key(bend)
  for _n, where, _l in hits:
    if where == port_rel:
      return ("PORT", port_rel)
    if where is not None:
      return ("SUBSTRATE", where)
  return ("UNRESOLVED", "named " + ", ".join(sorted({n for n, _w, _l in hits})) +
          " -- in no file of the closure")


def lane_err(v):
  """The lane's own stderr. GUARD 3's `lanes` dict is the evidence; the verdict's `why` is a
  summary of it and is NOT read here, because a summary is the thing that lost the file name."""
  out = []
  for k, l in (v.get("lanes") or {}).items():
    if k == "check" or l.get("rc") == 0:
      continue
    out.append(l.get("err", ""))
  return "\n".join(out)


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--verbose", action="store_true")
  a = ap.parse_args()
  g = load_gate()
  arts = artefacts()
  print("=" * 100)
  print("LANE-DEATH CENSUS.  One question per BROKEN entry: is the def the error names in the PORT,")
  print("in an IMPORTED file, or in no file at all?  Reader: rebase-gate.error_site, the same one")
  print("the gate now prints, so the census cannot disagree with the tool it is counting.")
  print("=" * 100)
  if not arts:
    print("NO ARTEFACTS: no JSON with a verdicts[] list was found. This is NOT a clean result and "
          "is NOT reported as one -- it means nothing was counted.")
    return 1

  grand = {}
  for p, d in arts:
    v = d["verdicts"]
    brk = [x for x in v if x.get("state") == "BROKEN"]
    buckets = {}
    for x in brk:
      b, where = classify(g, x["port"], lane_err(x))
      buckets.setdefault(b, []).append((x["port"], where))
    print(f"\n{p.relative_to(REPO)}   ({d.get('python', '?')}, {d.get('revision', 'no revision '
          'field -- predates the change')})")
    print(f"  verdicts {len(v)}   BROKEN {len(brk)}   tally {d.get('tally')}")
    if not brk:
      print("  no BROKEN entry; contributes 0 of 0 to every bucket below")
    for b in ("PORT", "SUBSTRATE", "UNRESOLVED", "NO-DEF"):
      for port, where in buckets.get(b, []):
        grand[b] = grand.get(b, 0) + 1
        line = f"  {b:<11} {port}"
        if b == "SUBSTRATE":
          line += f"   <- error is in {where}, NOT the port"
        elif b == "UNRESOLVED":
          line += f"   ({where})"
        print(line)
    for b in ("PORT", "SUBSTRATE", "UNRESOLVED", "NO-DEF"):
      if b in buckets:
        print(f"  {b:<11} {len(buckets[b])} of {len(brk)} BROKEN entry/entries in this artefact")
    if a.verbose:
      for x in brk:
        print(f"    {x['port']}\n      why: {' '.join((x.get('why') or '').split())[:160]}")
        print(f"      err: {' '.join(lane_err(x).split())[:200]}")

  print("\n" + "=" * 100)
  tot = sum(grand.values())
  print(f"TOTAL over {len(arts)} artefact(s): {tot} BROKEN entries classified")
  for b in ("PORT", "SUBSTRATE", "UNRESOLVED", "NO-DEF"):
    print(f"  {b:<11} {grand.get(b, 0)} of {tot}")
  print("-" * 100)
  print("READ THIS AS A COUNT OF ARTEFACTS, NOT OF EVENTS.  One edit to one shared file produces one")
  print("BROKEN entry per victim PER RUN, so a single incident measured twice is counted twice and a")
  print("single incident measured once is counted once.  The incidents behind these entries are")
  print("enumerated with their own evidence in .agents/slop/lanedeath-census.md; this file is the")
  print("machine count and says nothing about incidents it has not seen an artefact for.")
  return 0


if __name__ == "__main__":
  sys.exit(main())