#!/usr/bin/env python3
"""wire-survey.py -- intersect ALREADY-RUN oracle row sets with the ports that have no
oracle wired, using rebase-scan-oracles.py's cache so nothing is re-run.

The point of reading the cache rather than re-running is arithmetic, not speed: a fresh sweep
re-measures 379 oracles to answer a question 142 of whose answers are already on disk, and a
re-measurement is a chance to get a different answer. The cache is read as DATA and the
originating tool is named in the output, so the two measurements can be compared rather than
one of them taken on faith.

  usage: python3 .agents/slop/wire-survey.py [PORT ...]
"""
import json, os, pathlib, re, sys

REPO = pathlib.Path(__file__).resolve().parents[2]
SCAN = pathlib.Path("/tmp/rebase-scan")
BEND = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "rebase-wired-rows"
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


def main():
  ports = sys.argv[1:] or UNWIRED
  oracles = {}
  for f in SCAN.glob("o_*.json"):
    name = f.stem[2:]
    for s in f.read_text() and json.loads(f.read_text()).items():
      oracles.setdefault(name, {})[s[0]] = s[1]
  bend = {p: json.loads((BEND / (p.replace("/", "_") + ".json")).read_text())
          for p in ports if (BEND / (p.replace("/", "_") + ".json")).exists()}
  print(f"{len(oracles)} cached oracle row-sets, {len(bend)}/{len(ports)} port row-sets\n")
  print(f"{'shared':>6} {'dis':>5}  {'port':<42} oracle")
  out = []
  for p, b in bend.items():
    for o, orows in oracles.items():
      shared = set(orows) & set(b)
      if not shared:
        continue
      dis = sum(1 for k in shared if orows[k] != b[k])
      out.append((len(shared), dis, p, o))
  out.sort(reverse=True)
  for n, d, p, o in out:
    print(f"{n:>6} {d:>5}  {p:<42} {o}")
  return 0


if __name__ == "__main__":
  sys.exit(main())