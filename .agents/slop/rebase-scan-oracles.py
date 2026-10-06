#!/usr/bin/env python3
"""rebase-scan-oracles.py -- find (port, oracle) pairs that can actually be GATED.

  GUARD 4 says two lanes must share at least one row NAME, so an oracle is only wireable if
  it prints `name=value` rows whose names COLLIDE with the ones its port prints. This measures
  that collision for every candidate oracle against every gated port, so the wire-up list is
  computed rather than guessed -- and so a pair that cannot be gated is named as unwirable
  rather than wired and left BROKEN.

⚠ IT PRINTED A CONFIDENTLY WRONG ANSWER, BECAUSE ITS CACHE NEVER INVALIDATED.
  It reported `84 shared, 84 disagree` for a pair whose real gate measures `726 shared,
  0 disagree`, off cache files written HOURS earlier, for a port that had since been re-cut
  from 233 rows to 726. The number was not a number about the tree; it was a number about
  what the tree looked like before three edits.

  The fix is not a new rule. It is `wire_parse.read_fresh_cache` -- the rule `wire-rows.py`
  has used all along: A CACHE OLDER THAN ITS SOURCE IS NOT A READING. One implementation, so
  the scan and the wire tools cannot hold two opinions about when a cache may be believed.

⚠ AND A FAILED RUN WAS CACHED AS "ZERO ROWS", WHICH IS A DIFFERENT DISEASE.
  `oracle_rows` wrote `{}` whenever the oracle exited non-zero, and nothing ever re-ran it.
  Measured on this tree: 82 of the 211 cache files held `{}`, and among them were three
  oracles BASE_ORACLES WIRES -- dtype-oracle.py, ops-python-render-oracle.py and
  renderer_oracle.py. The cause is mundane and reproducible: the scan was once invoked with
  PATH's `python3` (3.14, no `.pth`, `ModuleNotFoundError: No module named 'tinygrad'`), every
  oracle that imports tinygrad exited 1, and the failures were recorded as measurements. So:
  NOTHING IS CACHED UNLESS IT PRODUCED ROWS. wire-rows.py only writes on success too.

  ⚠ AND GUARDING THE WRITE WAS NOT ENOUGH, MEASURED. Those 82 `{}` files were still on disk when
  the write-side rule landed, and a reader does not care how old a rule is: `read_fresh_cache`
  answered "fresh" for every one of them, because a fresh file holding `{}` is not stale. EIGHT
  of the 38 wired pairs therefore measured 0 shared row names and `main()` skipped all eight in
  SILENCE -- a lane that failed hours ago, skipped without a word. So the READ side refuses an
  empty cache too, and `cached()` below is where that half lives. One rule, two halves: A CACHE
  THAT RECORDS NOTHING IS NOT A READING.

  And the row parser is the GATE'S (`rebase-gate.py`'s `rows()`), imported, not copied. This
  tool's whole output is `shared`/`disagree` counts that are read as claims about what
  rebase-gate.py will say; two parsers make that a coincidence instead of a measurement.

  usage: PORTS='a/b.bend [c.bend]' PROBES='.agents/slop/x-oracle.py|.agents/slop/y.py ARG' \\
         .venv/bin/python .agents/slop/rebase-scan-oracles.py
         both default to the whole target list / every SLOP file whose NAME holds "oracle" or
         "gate"; PROBES entries are split on `|`, and each entry may carry arguments.
         Use .venv/bin/python: PATH's python3 cannot import tinygrad at all, and every oracle
         that does exits 1 -- which, before the no-cache-on-failure rule above, filed that exit
         as a measurement of zero rows.
"""
import os, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from wire_parse import cache_file, read_fresh_cache, stripped_env, write_cache

REPO = HERE.parent.parent
SLOP = REPO / ".agents" / "slop"
CACHE = pathlib.Path("/tmp/rebase-scan")


def load_module(path, name):
  """Import a harness file whose name is not an identifier -- every one of them has a `-` in
  it. One loader, shared with rebase-gate-selftest.py by being imported FROM this file: two
  copies of a loader is two chances to disagree about what got loaded."""
  import importlib.util
  spec = importlib.util.spec_from_file_location(name, str(path))
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


gate = load_module(HERE / "rebase-gate.py", "rebase_gate_rows")
rows = gate.rows  # THE GATE'S PARSER. See the header.


def port_key(port):
  """The cache key for a .bend lane. Named, because rebase-gate-selftest.py measures through
  this same function: a second spelling of a cache key is a second cache."""
  return port


def oracle_key(spec):
  """The cache key for a CPython lane. It carries the ARGS, because
  `tcptx-oracle.py stage2` is a different question from the bare script and its two answers
  have no business sharing a file."""
  return "o_" + re.sub(r"\W", "_", spec)


def cached(key, src):
  """This tool's ONE cache reader. It is wire-rows.py's -- (rows, 'fresh'|'missing'|'stale') --
  plus one state of this tool's own, 'empty', and it returns None for anything that may not be
  believed, so the caller has to run the lane.

  ⚠ 'empty' IS NOT A SUBTLETY, IT IS THE SAME BUG AS THE STALE RULE, AND THE WRITE-SIDE FIX
  ALONE DID NOT CLOSE IT. store() below refuses to WRITE an empty cache, so every one of the 82
  `{}` files already sitting in /tmp/rebase-scan predates that rule -- and `read_fresh_cache`
  answers "fresh" for all of them, because a fresh file that holds `{}` is not stale. Measured on
  this tree with the write-side rule in place and the read side unfixed: EIGHT of the 38 wired
  pairs measure 0 shared row names, and all eight are an oracle cache holding `{}`. Not one of
  them printed anything. `main()` saw an empty dict and `continue`d, so a lane that FAILED hours
  ago was skipped in SILENCE -- which is the reading the no-cache-on-failure rule exists to
  forbid, arrived at from the other direction.

  So the rule is one sentence and it has two halves: A CACHE THAT RECORDS NOTHING IS NOT A
  READING, exactly as a cache older than its source is not a reading. `read_fresh_cache` owns the
  mtime half for wire-rows.py as well; this half is local because wire-rows.py has no empty files
  to be wrong about -- it never wrote any."""
  d, why = read_fresh_cache(CACHE, key, src)
  return (None, "empty") if why == "fresh" and not d else (d, why)


def say_not_used(key, why, src):
  """Name BOTH files and which of them is older, or name the file that holds nothing.
  `wire-rows.py` says "the cache is older than the source", which leaves the reader to guess which
  of the two moved; and a bare `{}` names neither the file nor the run that produced it."""
  f = cache_file(CACHE, key)
  if why == "empty":
    print(f"  ({key}: cache {f} holds NO ROWS, which records a FAILED run rather than an empty "
          f"one; not using it, and the lane is re-run)")
  else:
    print(f"  ({key}: cache {f} is OLDER than its source {src}; not using it)")


def run(argv, env=None, timeout=240):
  """A probe that hangs is NOT an oracle and must not stop the sweep.

  Measured: `nv_nvdev_gate.py` timed out at 900s and took the whole scan down with it, losing
  every result it had already computed -- a scan that dies on its third probe reports nothing
  about the first two. A probe that exceeds its budget is recorded as no rows and named."""
  try:
    return subprocess.run(argv, cwd=REPO, capture_output=True, text=True, timeout=timeout,
                          env=env)
  except subprocess.TimeoutExpired:
    print(f"  (probe timed out after {timeout}s, treated as emitting no rows: {argv[1]})")
    return None


def bend_rows(port):
  """One .bend lane, from a cache REFUSED when it is older than the .bend it came from, and
  refused when it holds nothing.

  ⚠ THE BUDGET IS `wire-rows.py`'s 1800s, AND IT WAS RAISED BECAUSE A CACHE NEVER INVALIDATED.
  With the stale rule in place for the first time, `runtime/support/elf.bend` was finally re-run
  and TIMED OUT at the 600s this function used -- and a lane that times out is a lane that reports
  no rows, which is the 0-rows-means-nothing trap this file already guards against at 1 run in 20.
  `wire-rows.py` has always spent 1800s on the same file, so 600s was never a measured number
  here; it was a number nobody had needed yet."""
  CACHE.mkdir(exist_ok=True)
  src = REPO / port
  d, why = cached(port_key(port), src)
  if why == "fresh":
    return d
  if why != "missing":
    say_not_used(port, why, src)
  r = run(["./bin/bend", str(src)], timeout=1800)
  # 0 rows is INDISTINGUISHABLE from "this port has no main", and bend's machine stack
  # overflows on roughly 1 run in 20 and sometimes prints ZERO rows. A probe that reports 0
  # rows is therefore re-run once before being believed, and a second 0 is believed.
  d = rows(r.stdout) if r is not None else {}
  if not d and r is not None:
    r2 = run(["./bin/bend", str(src)], timeout=1800)
    d2 = rows(r2.stdout) if r2 is not None else {}
    print(f"  ({port} printed 0 rows, re-ran: {len(d2)})" if d2 else
          f"  ({port} printed 0 rows twice -- trusting it, and caching NOTHING: see store())")
    d = d or d2
  store(port_key(port), d, port)
  return d


def oracle_rows(spec):
  """One CPython lane. The SOURCE is the oracle SCRIPT, so editing the script invalidates its
  cached rows -- which is the whole point: the rows are a fact about the script, not about the
  day it was asked for."""
  CACHE.mkdir(exist_ok=True)
  src = REPO / spec.split()[0]
  d, why = cached(oracle_key(spec), src)
  if why == "fresh":
    return d
  if why != "missing":
    say_not_used(oracle_key(spec), why, src)
  d = oracle_run(spec)
  store(oracle_key(spec), d, spec)
  return d


def oracle_run(spec):
  """The oracle, twice at most. A non-zero exit is EVIDENCE and is reported as itself; it is
  never laundered into a row count. `DEV=NULL` and no PYTHONPATH: a `os.environ` copy taken
  after PYTHONPATH was set measures the treatment rather than the oracle, and an oracle that
  imports the wrong tinygrad exits 1 printing nothing."""
  r = run([sys.executable, *spec.split()], env=stripped_env({"DEV": "NULL"}))
  if r is None:
    return {}
  if r.returncode != 0:
    tail = r.stderr.strip().splitlines()[-1] if r.stderr.strip() else "no stderr"
    print(f"  ({spec} exited {r.returncode}, which is a FAILED ORACLE and not a row count: "
          f"{tail})")
    return {}
  return rows(r.stdout)


def store(key, d, what):
  """Cache rows, and ONLY rows. An empty cache is a failure filed as a measurement, and it is
  the reason 82 of this directory's 211 files were `{}`."""
  if d:
    write_cache(CACHE, key, d)
  else:
    print(f"  ({what} produced ZERO rows: nothing cached, and the next run re-runs it)")


def main():
  targets = [ln.strip() for ln in os.environ.get("PORTS", "").split() if ln.strip()]
  if not targets:
    targets = [ln.strip() for ln in
               (REPO / ".agents" / "slop" / "rebase" / "targets.txt").read_text().splitlines()
               if ln.strip()]
  cand = sorted({str(p.relative_to(REPO)) for p in SLOP.rglob("*.py")
                  if re.search(r"(oracle|gate)", p.name) and "rebase-" not in p.name
                  and "rebase_" not in p.name})
  probes = [ln.strip() for ln in os.environ.get("PROBES", "").split("|") if ln.strip()] or cand

  best = []
  for spec in probes:
    o = oracle_rows(spec)
    if not o:
      continue
    for port in targets:
      b = bend_rows(port)
      if not b:
        continue
      shared = set(o) & set(b)
      if not shared:
        continue
      dis = [k for k in shared if o[k] != b[k]]
      best.append((len(shared), len(dis), port, spec))
  best.sort(reverse=True)
  print(f"{'shared':>6} {'dis':>5}  {'port':<44} oracle")
  for n, d, port, spec in best:
    print(f"{n:>6} {d:>5}  {port:<44} {spec}")
  print(f"\n{len({p for _, _, p, _ in best})} of {len(targets)} target ports have a wireable oracle")
  return 0


if __name__ == "__main__":
  sys.exit(main())
