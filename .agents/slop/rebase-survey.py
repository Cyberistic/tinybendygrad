#!/usr/bin/env python3
"""rebase-survey.py -- for every port, MEASURE the row-name overlap with every candidate
oracle. Nothing here is a guess: a port is WIRED only if an oracle was RUN and the name
intersection is non-empty.

WHY THE NAME INTERSECTION IS THE WHOLE QUESTION. `rebase-gate.py`'s GUARD 3 exists because
two lanes sharing no row name compare nothing while reporting zero disagreements. So the
only honest test of "is this oracle wired to this port" is to run both and intersect.

HOW IT IS FAST. An oracle's row NAMES do not depend on which port you pass it (they come
from the oracle's own fixture list), so every candidate is run ONCE and the measurement is
a set intersection. A naive run-per-pair survey would execute 60 oracles 19 times.

THE FOUR WORDS, and only one of them is coverage:

    WIRED        the oracle ran, emitted rows, and shares >=1 name with the port
    DEAD-LANE    the oracle exited non-zero, or emitted zero `name=value` rows
    NO-SHARED    the oracle ran and emitted rows but shares NO name with the port, so the
                 pair can never agree -- it compared nothing
    DISAGREES    shares names and some differ: a real red, over the shared names only

    python3 .agents/slop/rebase-survey.py [--batch N] [--port P] [--cands]
"""
import argparse, json, os, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
GATE = HERE / "rebase-gate.py"
CACHE = HERE / "rebase" / "survey-cache.json"


def load_gate():
  import importlib.util
  spec = importlib.util.spec_from_file_location("rebase_gate", GATE)
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


G = load_gate()

# The candidate set is CURATED, not `rglob("*.py")`. Every mutation harness in slop compiles
# bend binaries, and running all ~200 of them to find ~10 row producers took 50 minutes and
# had not finished. A candidate earns its place here by being a row PRODUCER, and that is
# established by running it, not by its filename.
CANDIDATES = [
  ".agents/slop/hcq2-oracle.py", ".agents/slop/hcq2-oracle2.py",
  ".agents/slop/mt_rows.py", ".agents/slop/mt_constmap.py", ".agents/slop/mt_seam_rows.py",
  ".agents/slop/mt-table.py",
  ".agents/slop/ops-oracle.py",
  ".agents/slop/cl_constmap.py", ".agents/slop/cl_emit_map.py", ".agents/slop/cl_vendor_scan.py",
  ".agents/slop/nv-oracle.py",
  ".agents/slop/amd_oracle.py", ".agents/slop/amd_check.py",
  ".agents/slop/qc_oracle.py", ".agents/slop/qc_stage3_oracle.py", ".agents/slop/qc_check.py",
  ".agents/slop/oracle_rdma.py", ".agents/slop/oracle_rdma_gate.py",
  ".agents/slop/oracle_npy.py", ".agents/slop/oracle_torch.py",
  ".agents/slop/dtype-gate.py", ".agents/slop/oracle/dtype_tables.py",
  ".agents/slop/renderer_oracle.py", ".agents/slop/wip/cstyle_oracle.py",
  ".agents/slop/dk-oracle.py", ".agents/slop/tcptx-oracle.py", ".agents/slop/ip_oracle.py",
  ".agents/slop/nv_ip_oracle.py",
  ".agents/slop/nn-gate.py", ".agents/slop/nn-init-gate.py",
  ".agents/slop/memory_oracle.py",
  ".agents/slop/system_diff.py", ".agents/slop/tc-diff.py",
  ".agents/slop/rf-rows.py", ".agents/slop/rf-arg-oracle.py", ".agents/slop/rf-ct-oracle.py",
  ".agents/slop/notes/rw-truth.py", ".agents/slop/notes/rz-oracle.py",
  ".agents/slop/notes/sized-oracle.py", ".agents/slop/notes/sched-truth.py",
  ".agents/slop/notes/sched-multi-truth.py", ".agents/slop/notes/sched-mem-truth.py",
  ".agents/slop/notes/sched-allreduce-truth.py", ".agents/slop/notes/rz-oracle.py",
  ".agents/slop/notes/kn-truth.py", ".agents/slop/notes/mop-truth.py",
  ".agents/slop/x-stgate.py", ".agents/slop/x-stgate2.py",
  ".agents/slop/mm-lift-gate.py", ".agents/slop/mm-dt-gate.py", ".agents/slop/mm-gate.py",
  ".agents/slop/mm-bl-gate.py", ".agents/slop/mixin-op-gate.py", ".agents/slop/state-gate.py",
  ".agents/slop/dsp_oracle.py", ".agents/slop/ew-gate.py", ".agents/slop/dst-oracle.py",
  ".agents/slop/resh-chain-oracle.py", ".agents/slop/reshape-oracle.py",
  ".agents/slop/late-oracle.py", ".agents/slop/hq-oracle.py",
  ".agents/slop/ag-oracle.py", ".agents/slop/dsl_oracle.py", ".agents/slop/ptx-s3-oracle.py",
  ".agents/slop/tx-oracle.py", ".agents/slop/wgsl-oracle.py", ".agents/slop/x86_probe.py",
  ".agents/slop/beautiful-mnist-gate.py", ".agents/slop/onsnx-gate.py",
  ".agents/slop/tensor-gate.py", ".agents/slop/gate.py",
]

# DISCOVERY, for the ports the curated list did not settle. Every `.py` under these
# subdirectories, except the vendored upstream snapshots and the mutation harnesses, which
# compile bend binaries and would turn the survey into a 50-minute job. Each candidate is
# still RUN and still MEASURED: discovery finds a filename, the intersection decides it.
DISCOVER_DIRS = ("xd1", "notes", "oracle", "oracles", "probe")
DISCOVER_SKIP = re.compile(r"(hdrbase|opstree|tcptx|x86|ptxown|rf2root|/x\d/|mutate|mut-|__pycache__|"
                           r"sz-|probe-|bendfix|bendall|bendlint|dead-defs|const-audit)")
DISCOVERED = sorted(str(p.relative_to(REPO)) for d in DISCOVER_DIRS for p in (HERE / d).glob("*.py")
                    if not DISCOVER_SKIP.search(str(p)) and p.name != "rebase-survey.py")


def stamp(path):
  """(mtime_ns, size) of a file, or None. THE CACHE KEY.

  This survey had the bug `rebase-gate.py`'s GUARD 3 exists to prevent, in its own body: an
  unkeyed cache. `codegen/kernel.bend` measured `port_rows=0 rc=1` for twenty minutes because
  a FAILED run was cached beside 104 healthy oracle results, and re-running the survey
  replayed it -- a cached "zero rows" is indistinguishable from a fresh zero, which is the
  sentence GUARD 3 was written for. Every cache entry now carries the stamp of the file it
  came from, and a stamp change discards the entry.
  """
  try:
    st = (REPO / path).stat()
    return [st.st_mtime_ns, st.st_size]
  except OSError:
    return None


def cached(cache, kind, key):
  """(stamp, value) if the cache entry is still valid for this file's CURRENT bytes."""
  e = cache.get(kind, {}).get(key)
  if not e or e[0] != stamp(key):
    return None
  return e[1], e[2]


def store(cache, kind, key, rows, note):
  cache.setdefault(kind, {})[key] = [stamp(key), rows, note]


def run_oracle(spec):
  """Run one candidate once. Returns (rows, note)."""
  py = str(REPO / ".venv/bin/python")
  env = dict(os.environ, DEV="NULL")
  try:
    c = subprocess.run([py, spec], cwd=REPO, capture_output=True, text=True, env=env,
                       timeout=900)
  except subprocess.TimeoutExpired:
    return {}, "TIMEOUT"
  r = G.rows(c.stdout)
  note = f"rc={c.returncode}"
  if c.returncode != 0:
    note += " " + (c.stderr.strip().splitlines() or ["?"])[-1][:150]
  if not r and c.returncode == 0:
    note += " ZERO name=value ROWS"
  return r, note


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--batch", type=int, default=None)
  ap.add_argument("--port", default=None)
  ap.add_argument("--cands", action="store_true", help="also list the dead candidates")
  ap.add_argument("--nocache", action="store_true")
  ap.add_argument("--discover", action="store_true",
                  help="also run every row producer under xd1/ notes/ oracle/ oracles/")
  a = ap.parse_args()

  cands = list(CANDIDATES) + (DISCOVERED if a.discover else [])
  cache = json.loads(CACHE.read_text()) if CACHE.exists() and not a.nocache else {}
  cache.setdefault("oracles", {})
  cache.setdefault("ports", {})

  plan = json.loads(G.sh("python3", ".agents/slop/rebase-plan.py", "--json").stdout)
  if a.port:
    ports = [a.port]
  else:
    srcs = next((b["files"] for b in plan["batches"] if b["id"] == a.batch), None) or \
           [f for b in plan["batches"] for f in b["files"]]
    ports = sorted({p for f in srcs for p in G.ports_of(f, plan)})

  for port in ports:
    bend = REPO / port
    if not bend.exists():
      continue
    hit = cached(cache, "ports", port)
    if hit is None:
      got = G.sh("./bin/bend", str(bend))
      prows, pnote = G.rows(got.stdout), f"rc={got.returncode}"
      if not prows:
        pnote += " " + (got.stderr or "").strip().splitlines()[-1][:120]
      store(cache, "ports", port, prows, pnote)
    else:
      prows, pnote = hit
    print(f"\n=== {port}   port_rows={len(prows)} [{pnote}]", flush=True)
    if not prows:
      continue
    hits, dead = [], []
    for spec in cands:
      got = cached(cache, "oracles", spec)
      if got is None:
        orows, note = run_oracle(spec)
        store(cache, "oracles", spec, orows, note)
      else:
        orows, note = got
      if not orows:
        dead.append((spec, note))
        continue
      shared = set(prows) & set(orows)
      if not shared:
        dead.append((spec, f"NO-SHARED ({len(orows)} rows)"))
        continue
      bad = sorted(k for k in shared if prows[k] != orows[k])
      hits.append((len(shared), len(bad), spec, len(orows), bad[:5], orows))
    hits.sort(key=lambda h: (-h[0], h[1]))
    for shared, bad, spec, n_or, ex, orows in hits[:4]:
      print(f"    {'DISAGREES' if bad else 'WIRED':<10} shared={shared:<5} "
            f"disagree={bad:<4} oracle_rows={n_or:<5} {spec}")
      for e in ex:
        print(f"        {e}: port={prows[e]!r} oracle={orows[e]!r}")
    if not hits:
      print("    NO CANDIDATE SHARES A ROW NAME WITH THIS PORT")
    if a.cands:
      for spec, note in sorted(dead):
        print(f"    {'DEAD-LANE' if not note.startswith('NO-SHARED') else 'NO-SHARED':<10} {spec}  [{note}]")

  CACHE.parent.mkdir(parents=True, exist_ok=True)
  CACHE.write_text(json.dumps(cache, indent=1))
  print(f"\ncache -> {CACHE}  ({len(cache['oracles'])} oracles, {len(cache['ports'])} ports)")


if __name__ == "__main__":
  sys.exit(main())