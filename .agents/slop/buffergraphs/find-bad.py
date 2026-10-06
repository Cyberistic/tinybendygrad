#!/usr/bin/env python3
"""PY-ONLY scan (no `bend`): which graph's arg carries a given atom letter, and every graph's
py-side device names. Lets the oracle's `unmapped arg atom letters` bad be attributed without
spawning another bend process."""
from __future__ import annotations

import os
import sys

os.environ["DEV"] = "CPU"
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import graphcmp as G  # noqa: E402
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location(
  "graphcmp_oracle", os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                  "graphcmp-oracle.py"))
O = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(O)

G.load_tinygrad()
G.COMM = G.commutative()

TARGET = sys.argv[1] if len(sys.argv) > 1 else "B"
for g in sorted(G.GRAPHS):
  py = G.emit_py(g, None)
  for ln in py:
    f = G.unchunks(ln)
    if TARGET in O.atoms(f[6]):
      print("# {}: op={} arg={}".format(g, f[1], f[6]))
