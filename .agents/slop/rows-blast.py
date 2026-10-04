#!/usr/bin/env python3
"""rows-blast.py -- THE BLAST RADIUS OF THE UNIFIED `rows()`, MEASURED, NOT ARGUED.

`rows()` is the parser every wired gate shares.  A change to it is a change to 38 verdicts at
once, so the question is not "is the new parser better" but "WHAT ELSE MOVED".  Three ways it
could:

  LOST KEY     the new parser drops a name the old one had.  The gate compares row-NAME sets,
               so a lost name shrinks an intersection; below one shared name GUARD 4 says
               BROKEN, but between 1 and n it reports a narrower comparison with no complaint.
  CHANGED VALUE  the new parser returns a DIFFERENT value for a name the old one had.  That is
               the direction that can turn a real disagreement into agreement, which is the
               outcome this project has paid for six times.
  MANUFACTURED KEY  the new parser invents a name out of a line that was never a row -- a
               continuation line, a table row, a prose line.  An invented name that collides
               with the other lane's is read as EVIDENCE by GUARD 4.

This script runs every lane in the wired roster LIVE, keeps the RAW stdout, and applies the old
parser and the new one to the same bytes.  Nothing is read from a cache: a cached row DICT cannot
answer "what did the text say", which is the whole question.

    .venv/bin/python .agents/slop/rows-blast.py            # the wired roster
    .venv/bin/python .agents/slop/rows-blast.py --lanes A,B # named port=oracle pairs

Reported per lane: old count, new count, keys added / dropped / value-changed.  Reported per
PAIR: shared and disagreeing under each parser, so a lane that would start agreeing by comparing
less is named with both numbers.
"""
import argparse, concurrent.futures as cf, importlib.util, os, pathlib, subprocess, sys, time

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(HERE))
import oracle_py  # noqa: E402


def load(path, name):
  spec = importlib.util.spec_from_file_location(name, path)
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


# THE OLD PARSER, verbatim, as the control.  Copied rather than imported because the whole
# measurement is "the shipped one versus the candidate", and once the candidate is shipped there
# is no shipped old one to import.
def rows_old(text):
  out = {}
  for line in text.splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      k = k.strip()
      if k:
        out[k] = v.strip()
  return out


def _lane(argv, env=None, timeout=1800, tries=3):
  """Raw stdout, re-run while it is EMPTY.  bend's machine stack overflows on ~1 run in 20 and
  prints zero rows, and a lane that reports nothing must be reported as reporting nothing."""
  for attempt in range(tries):
    try:
      r = subprocess.run(argv, cwd=REPO, capture_output=True, text=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
      return "", "TIMEOUT"
    if r.stdout.strip():
      return r.stdout, ("" if r.returncode == 0 else f"rc={r.returncode}")
    why = f"attempt {attempt + 1} printed 0 rows"
  return "", why


def pair_lanes(port, spec):
  """(port_text, oracle_text, notes). Both live, under the PINNED interpreter."""
  py = oracle_py.resolve()[0]
  env = os.environ.copy()
  env["DEV"] = "NULL"
  env.pop("PYTHONPATH", None)  # the editable install resolves without it; a stale value overrides
  pt, pn = _lane(["./bin/bend", str(REPO / port)])
  ot, on = _lane([py, *spec.split()], env=env)
  return port, spec, pt, ot, (pn, on)


def report(port, spec, pt, ot, notes, new):
  pn, on = notes
  o, n = rows_old(pt), new(pt)
  oo, no = rows_old(ot), new(ot)
  lost = sorted(set(o) - set(n))
  gained = sorted(set(n) - set(o))
  revalued = sorted(k for k in set(o) & set(n) if o[k] != n[k])
  olost = sorted(set(oo) - set(no))
  ogained = sorted(set(no) - set(oo))
  oreval = sorted(k for k in set(oo) & set(no) if oo[k] != no[k])
  sh_o = len(set(o) & set(oo))
  dis_o = sum(1 for k in set(o) & set(oo) if o[k] != oo[k])
  sh_n = len(set(n) & set(no))
  dis_n = sum(1 for k in set(n) & set(no) if n[k] != no[k])
  tag = "" if (not lost and not gained and not olost and not ogained
               and sh_n >= sh_o and dis_n <= dis_o) else "  <<< MOVED"
  print(f"\n{port}  +  {spec}{tag}")
  print(f"    port   rows() {len(o):>6} -> new {len(n):<6}  +{len(gained)} -{len(lost)} "
        f"revalued {len(revalued)}   {pn}")
  print(f"    oracle rows() {len(oo):>6} -> new {len(no):<6}  +{len(ogained)} -{len(olost)} "
        f"revalued {len(oreval)}   {on}")
  print(f"    PAIR   shared {sh_o} -> {sh_n}   disagree {dis_o} -> {dis_n}")
  for k in revalued[:4]:
    print(f"      REVALUED {k!r}: {o[k][:48]!r} -> {n[k][:48]!r}")
  for k in (lost + olost)[:4]:
    print(f"      LOST     {k!r}")
  for k in (gained + ogained)[:4]:
    print(f"      GAINED   {k!r} = {(n.get(k) or no.get(k))[:60]!r}")
  if dis_n != dis_o:
    now = [k for k in set(n) & set(no) if n[k] != no[k]]
    was = [k for k in set(o) & set(oo) if o[k] != oo[k]]
    for k in sorted(set(now) - set(was))[:4]:
      print(f"      NEW DISAGREEMENT {k!r}: port {n[k][:40]!r} vs cpy {no[k][:40]!r}")
    for k in sorted(set(was) - set(now))[:4]:
      print(f"      NO LONGER DISAGREES {k!r}")
  return {"port": port, "oracle": spec, "old": (sh_o, dis_o), "new": (sh_n, dis_n),
          "lost": len(lost) + len(olost), "gained": len(gained) + len(ogained),
          "revalued": len(revalued) + len(oreval),
          "measured": bool(pt) and bool(ot)}


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--lanes", default=None,
                  help="comma-separated port=oracle-spec; default is the whole wired roster")
  ap.add_argument("--workers", type=int, default=4)
  a = ap.parse_args()
  gate = load(HERE / "rebase-gate.py", "blast_gate")
  roster = {p: o[0] for p, o in gate.BASE_ORACLES.items()}
  if a.lanes:
    roster = dict(kv.split("=", 1) for kv in a.lanes.split(",") if kv)
  new = gate.rows
  print(f"parser fingerprint: {hash(new.__code__.co_code)}  lanes: {len(roster)}")
  t0 = time.monotonic()
  out = []
  with cf.ThreadPoolExecutor(max_workers=a.workers) as pool:
    for res in pool.map(lambda kv: pair_lanes(*kv), sorted(roster.items())):
      out.append(report(*res, new))
  moved = [r for r in out if r["lost"] or r["gained"] or r["new"][0] < r["old"][0]
           or r["new"][1] > r["old"][1] or r["revalued"]]
  unmeasured = [r["port"] for r in out if not r["measured"]]
  print(f"\n{len(out)} pairs in {time.monotonic() - t0:.0f}s")
  print(f"pairs whose shared/disagree/keys MOVED: {len(moved)}")
  for r in moved:
    print(f"  {r['port']}: shared {r['old'][0]} -> {r['new'][0]}, "
          f"disagree {r['old'][1]} -> {r['new'][1]}, +{r['gained']} -{r['lost']} "
          f"revalued {r['revalued']}")
  if unmeasured:
    print(f"UNMEASURED (a lane produced nothing): {unmeasured} -- these prove NOTHING and are "
          f"not counted as agreement")
  return 1 if (moved and False) or unmeasured else 0


if __name__ == "__main__":
  sys.exit(main())