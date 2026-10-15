#!/usr/bin/env python3
"""Dump every FAIL row of cites-census with the needle UNTRUNCATED (the row file
cuts it at 48 chars, and the needle is the only thing that can be judged).

usage: .venv/bin/python .agents/slop/residual/fails.py <out.rows>
"""
import importlib.util
import sys
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cc", ROOT / "checks/cites-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / ".agents/slop/residual/fails.rows"
paths = cc.committed()
with warnings.catch_warnings():
  warnings.simplefilter("ignore")
  claims, _ = cc.census(paths)
  judged = [cc.judge(c) for c in claims]

fails = [c for c in judged if c.get("verdict") == cc.FAIL]
with out.open("w") as f:
  for c in fails:
    needle = (c.get("needle") or "").replace("\n", "\\n").replace("\t", "\\t")
    f.write("\t".join([c["lane"], c["file"] + ":" + str(c.get("at", "")),
                       str(c.get("subject", "")), repr(needle),
                       c.get("evidence", "").replace("\t", " "),
                       str(c.get("needle_kind", ""))]) + "\n")
print(f"{len(fails)} FAIL rows -> {out}")
