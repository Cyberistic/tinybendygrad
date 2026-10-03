#!/usr/bin/env python3
"""wire-sweep.py -- every candidate ORACLE in .agents/slop, not only the ones a name filter
finds, intersected with the ports that have no oracle wired.

WHY THIS EXISTS, and it is a measured reason and not a preference. `rebase-scan-oracles.py`
picks candidates with `re.search(r"(oracle|gate)", p.name)`. Two ports that have had a
working CPython oracle for HOURS are invisible to it because their filenames do not contain
either substring:

    .agents/slop/elf_rows.py     -> tinybendygrad/runtime/support/elf.bend
    .agents/slop/sqtt_spec.py    -> tinybendygrad/renderer/amd/sqtt.bend

So the "N ports have no oracle at all" figure counted two ports that had one. The filter is
part of why the gap looked as large as it did, and a survey that cannot see an oracle that
exists is a survey reporting absence as fact.

The shared-row counts that used to sit on those two lines (353 and 1015, both "clean") are
retired as a control. They were a snapshot. elf.bend's own file is newer than the cache that
produced 353, and bend has printed 331 rows for that file with no edit in between (see
bend2-constraints.md, the block that ends at position 14440). A count typed into this
comment is not re-checked. Re-measure; do not edit a port to make the comment true.

SAFETY, because this EXECUTES 300+ scripts from the tree. Anything whose name says it writes
(`mutate`, `fix`, `apply`, `plant`, `break`, `gen_main`, `mkrows`) is EXCLUDED and the
exclusion is printed with a count, because agent-core.md's rule -- never patch the live tree
from a harness -- is not worth violating for a survey. Scripts are run with `cwd=REPO` and a
copy-on-write-ish sandbox is not available, so the filter is the whole safety argument and it
is deliberately over-broad.

  usage: python3 .agents/slop/wire-sweep.py [--ports FILE] [--timeout N]
"""
import json, os, pathlib, re, subprocess, sys, time

from wire_parse import read_fresh_cache, rows, stripped_env

REPO = pathlib.Path(__file__).resolve().parents[2]
SLOP = REPO / ".agents" / "slop"
BEND = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "rebase-wired-rows"
WRITE = re.compile(r"(mutate|fix|apply|plant|break|gen_main|mkrows|rmtree|unlink|rm |chmod)")
EMIT = re.compile(r"^(def (row|prow|R|srow|ubrow|rb)\(|\s*(row|prow|R|srow)\()", re.M)


def unwired_ports():
  """Ports with no entry in rebase-gate.py's BASE_ORACLES. Read, not typed: the list
  this function replaced still named elf, sqtt, tc_ptx, generate and render after they
  were wired. A typed 'unwired' list is the same trap as a typed disagreement count."""
  gate = (REPO / ".agents" / "slop" / "rebase-gate.py").read_text()
  i = gate.find("BASE_ORACLES = {")
  if i < 0:
    print("BASE_ORACLES not found in rebase-gate.py; refusing a typed unwired list",
          file=sys.stderr)
    return []
  j = gate.find("\n}\n", i)
  body = gate[i:j if j > i else None]
  wired = set(re.findall(r'^\s+"(tinybendygrad/[^"]+\.bend)":', body, re.M))
  if not wired:
    print("BASE_ORACLES parsed empty; refusing a typed unwired list", file=sys.stderr)
    return []
  return sorted(str(p.relative_to(REPO)) for p in (REPO / "tinybendygrad").rglob("*.bend")
                if str(p.relative_to(REPO)) not in wired)


def candidates():
  out, skipped = [], 0
  for p in sorted(SLOP.rglob("*.py")):
    rel = str(p.relative_to(REPO))
    if "__pycache__" in rel or "/opstree/" in rel or "/dd-mirror/" in rel:
      continue
    if WRITE.search(p.name):
      skipped += 1
      continue
    try:
      src = p.read_text()
    except OSError:
      continue
    if not re.search(r"(import tinygrad|from tinygrad)", src):
      continue
    if not EMIT.search(src):
      continue
    out.append(rel)
  return out, skipped


def main():
  a = sys.argv[1:]
  timeout = int(a[a.index("--timeout") + 1]) if "--timeout" in a else 240
  ports = unwired_ports()
  if "--ports" in a:
    ports = [l.strip() for l in pathlib.Path(a[a.index("--ports") + 1]).read_text().splitlines()
             if l.strip()]
  bend = {}
  for p in ports:
    cached, why = read_fresh_cache(BEND, p, REPO / p)
    if why == "stale":
      print(f"  ({p} cache is older than the source; not a reading)", flush=True)
      continue
    if cached is not None:
      bend[p] = cached
  cands, skipped = candidates()
  print(f"{len(cands)} candidates ({skipped} skipped by the WRITE filter), "
        f"{len(bend)}/{len(ports)} port row-sets\n", flush=True)
  best = []
  for i, rel in enumerate(cands):
    t0 = time.time()
    try:
      r = subprocess.run([sys.executable, rel], cwd=REPO, capture_output=True, text=True,
                         env=stripped_env({"DEV": "NULL"}),
                         timeout=timeout)
    except subprocess.TimeoutExpired:
      print(f"  ({rel} TIMED OUT at {timeout}s, treated as no rows)", flush=True)
      continue
    o = rows(r.stdout)
    if not o:
      continue
    for p, b in bend.items():
      sh = set(o) & set(b)
      if not sh:
        continue
      best.append((len(sh), sum(1 for k in sh if o[k] != b[k]), p, rel, r.returncode))
    print(f"  [{i + 1}/{len(cands)}] {rel} rc={r.returncode} rows={len(o)} {time.time() - t0:.1f}s",
          flush=True)
  best.sort(reverse=True)
  print(f"\n{'shared':>6} {'dis':>5} {'rc':>3}  {'port':<42} oracle")
  for n, d, p, rel, rc in best:
    print(f"{n:>6} {d:>5} {rc:>3}  {p:<42} {rel}")
  (REPO / ".agents/slop/rebase" / "wire-sweep-2026-10-03.json").write_text(json.dumps(best, indent=1))
  print(f"\n{len({p for _, _, p, _, _ in best})} of {len(bend)} ports have a wireable candidate")
  return 0


if __name__ == "__main__":
  sys.exit(main())