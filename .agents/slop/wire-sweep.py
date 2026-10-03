#!/usr/bin/env python3
"""wire-sweep.py -- every candidate ORACLE in .agents/slop, not only the ones a name filter
finds, intersected with the ports that have no oracle wired.

WHY THIS EXISTS, and it is a measured reason and not a preference. `rebase-scan-oracles.py`
picks candidates with `re.search(r"(oracle|gate)", p.name)`. Two ports that have had a
working CPython oracle for HOURS are invisible to it because their filenames do not contain
either substring:

    .agents/slop/elf_rows.py     -> tinybendygrad/runtime/support/elf.bend    353 shared, clean
    .agents/slop/sqtt_spec.py    -> tinybendygrad/renderer/amd/sqtt.bend    1015 shared, clean

So the "N ports have no oracle at all" figure counts two ports that have one. The filter is
part of why the gap looked as large as it did, and a survey that cannot see an oracle that
exists is a survey reporting absence as fact.

SAFETY, because this EXECUTES 300+ scripts from the tree. Anything whose name says it writes
(`mutate`, `fix`, `apply`, `plant`, `break`, `gen_main`, `mkrows`) is EXCLUDED and the
exclusion is printed with a count, because agent-core.md's rule -- never patch the live tree
from a harness -- is not worth violating for a survey. Scripts are run with `cwd=REPO` and a
copy-on-write-ish sandbox is not available, so the filter is the whole safety argument and it
is deliberately over-broad.

  usage: python3 .agents/slop/wire-sweep.py [--ports FILE] [--timeout N]
"""
import json, os, pathlib, re, subprocess, sys, time

REPO = pathlib.Path(__file__).resolve().parents[2]
SLOP = REPO / ".agents" / "slop"
BEND = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "rebase-wired-rows"
WRITE = re.compile(r"(mutate|fix|apply|plant|break|gen_main|mkrows|rmtree|unlink|rm |chmod)")
EMIT = re.compile(r"^(def (row|prow|R|srow|ubrow|rb)\(|\s*(row|prow|R|srow)\()", re.M)
UNWIRED = [
  "tinybendygrad/codegen/decomp/dtype.bend", "tinybendygrad/codegen/kernel.bend",
  "tinybendygrad/codegen/opt/heuristic.bend", "tinybendygrad/codegen/opt/postrange.bend",
  "tinybendygrad/device.bend", "tinybendygrad/engine/jit.bend", "tinybendygrad/engine/realize.bend",
  "tinybendygrad/helpers.bend", "tinybendygrad/mixin/gradient.bend",
  "tinybendygrad/renderer/amd/generate.bend", "tinybendygrad/renderer/amd/sqtt.bend",
  "tinybendygrad/renderer/llvmir.bend", "tinybendygrad/renderer/tc_ptx.bend",
  "tinybendygrad/runtime/ops_amd.bend", "tinybendygrad/runtime/ops_cuda.bend",
  "tinybendygrad/runtime/ops_null.bend", "tinybendygrad/runtime/ops_python.bend",
  "tinybendygrad/runtime/ops_qcom.bend", "tinybendygrad/runtime/support/elf.bend",
  "tinybendygrad/schedule/__init__.bend", "tinybendygrad/schedule/indexing.bend",
  "tinybendygrad/schedule/multi.bend", "tinybendygrad/schedule/rangeify.bend",
  "tinybendygrad/uop/render.bend", "tinybendygrad/uop/validate.bend", "tinybendygrad/uop/weak.bend",
]


def rows(text):
  out = {}
  for line in text.splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k.strip()] = v.strip()
  return out


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
  ports = UNWIRED
  if "--ports" in a:
    ports = [l.strip() for l in pathlib.Path(a[a.index("--ports") + 1]).read_text().splitlines()
             if l.strip()]
  bend = {}
  for p in ports:
    f = BEND / (p.replace("/", "_") + ".json")
    if f.exists():
      bend[p] = json.loads(f.read_text())
  cands, skipped = candidates()
  print(f"{len(cands)} candidates ({skipped} skipped by the WRITE filter), "
        f"{len(bend)}/{len(ports)} port row-sets\n", flush=True)
  best = []
  for i, rel in enumerate(cands):
    t0 = time.time()
    try:
      r = subprocess.run([sys.executable, rel], cwd=REPO, capture_output=True, text=True,
                         env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {"DEV": "NULL"},
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