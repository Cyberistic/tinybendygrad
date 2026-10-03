#!/usr/bin/env python3
"""drift-cstyle-head.py -- is UPSTREAM.md's D2 still true at upstream HEAD?

D2 (`.agents/UPSTREAM.md`, the `## D2 -- renderer/cstyle.py:191` entry, file POSITION 146)
claims two upstream commits acting together:

  A  `dtype.py` changed every `DType.name` from the C spelling to the short form
  B  `cstyle.py` replaced `type_map.get(dtype, dtype.name)` with `type_map[dtype]`

and measured, AT COMMIT `87a4311b3` (file position 185), that 18 of 102
(dtype x renderer) pairs raise `KeyError`.

That was measured at ONE commit. This re-measures the identical sweep at three revisions
so the ledger entry can be checked instead of trusted, and prints the `DType.name` table
at each, because A is the part a rename silently invalidates.

  usage: python3 .agents/slop/drift-cstyle-head.py [--json]

A FRESH PROCESS PER REVISION, always. `helpers.py` caches `getenv` with `functools.cache`
and the dtype table is built at import, so one process cannot hold two revisions' tables.
"""
import json, subprocess, sys, tarfile, tempfile, io
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
REVS = [("pin", "6c3d401cf324"), ("our-baseline", "87a4311b3c3"), ("upstream-head", "upstream/master")]

CHILD = r"""
import json, sys
sys.path.insert(0, sys.argv[1])
import tinygrad.dtype as _dt
from tinygrad.dtype import dtypes
from tinygrad.helpers import Target
from tinygrad.renderer.cstyle import (CStyleLanguage, ClangRenderer, OpenCLRenderer,
                                      MetalRenderer, CUDARenderer, HIPRenderer)
REND = [("CStyleLanguage", CStyleLanguage), ("ClangRenderer", ClangRenderer),
        ("OpenCLRenderer", OpenCLRenderer), ("MetalRenderer", MetalRenderer),
        ("CUDARenderer", CUDARenderer), ("HIPRenderer", HIPRenderer)]
out = {"names": {dt.name: dt.itemsize for dt in dtypes.all}, "cells": [], "missing_attr": [],
       "param_type": None, "type_map_names": []}
for rname, R in REND:
    try:
        lang = R(Target("NULL"))
    except BaseException as e:
        out["missing_attr"].append([rname, f"{type(e).__name__}: {e}"[:120]]); continue
    out["type_map_names"].append([rname, sorted(str(k) for k in getattr(lang, "type_map", {}))])
    out["param_type"] = out["param_type"] or hasattr(lang, "param_type")
    for dt in dtypes.all:
        try:
            v = lang._render_dtype(dt, 1, None)
            out["cells"].append([rname, dt.name, v])
        except BaseException as e:
            out["cells"].append([rname, dt.name, f"!{type(e).__name__}: {e}"[:90]])
print(json.dumps(out))
"""


def at(rev, dest):
  tar = subprocess.run(["git", "archive", rev, "tinygrad"], cwd=REPO,
                       capture_output=True, check=True).stdout
  with tarfile.open(fileobj=io.BytesIO(tar)) as t:
    t.extractall(dest, filter="data")
  return dest


def main():
  as_json = "--json" in sys.argv
  results = {}
  for label, rev in REVS:
    with tempfile.TemporaryDirectory() as d:
      root = at(rev, d)
      p = subprocess.run([sys.executable, "-c", CHILD, root], capture_output=True, text=True)
      if p.returncode != 0:
        print(f"  {label:<14} {rev[:12]}  CHILD DIED rc={p.returncode}: {p.stderr[-400:]}")
        continue
      results[label] = {"rev": rev, **json.loads(p.stdout)}
  if as_json:
    print(json.dumps(results, indent=1)); return 0

  print("  dtype.name table -- A says upstream renamed these to the SHORT form\n")
  keys = ["float", "f32", "int", "i32", "weakint", "float16", "f16", "float8_e4m3", "fp8e4m3"]
  print("    " + "".join(f"{k:<18}" for k in ["revision"] + keys))
  for label, _ in REVS:
    r = results.get(label)
    if not r:
      print(f"    {label:<18}(dead)"); continue
    print("    " + f"{label:<18}" + "".join(
        f"{r['names'].get(k, '-'):<18}" for k in keys))

  print("\n  KeyError cells by (renderer, dtype) -- B is the claim under test\n")
  for label, _ in REVS:
    r = results.get(label)
    if not r:
      continue
    if r["missing_attr"]:
      print(f"    {label}: renderer could not be constructed:")
      for a in r["missing_attr"]:
        print(f"        {a[0]:<20} {a[1]}")
  for label, _ in REVS:
    r = results.get(label)
    if not r:
      continue
    bad = sorted({(c[0], c[1]) for c in r["cells"] if c[2].startswith("!")})
    tot = len(r["cells"])
    print(f"    {label:<14} {r['rev'][:12]}  raising {len(bad):>3} of {tot} cells")
    if bad:
      by = {}
      for rname, dt in bad:
        by.setdefault(rname, []).append(dt)
      for rname in sorted(by):
        print(f"                    {rname:<20} {', '.join(sorted(by[rname]))}")
  print("\n  CStyleLanguage HAS def param_type?  (the 1:1 naming rule's only upstream name")
  print("  our copy is missing) -- measured, not read from a comment\n")
  for label, _ in REVS:
    r = results.get(label)
    print(f"    {label:<18}" + ("(dead)" if not r else str(r["param_type"])))
  return 0


if __name__ == "__main__":
  sys.exit(main())