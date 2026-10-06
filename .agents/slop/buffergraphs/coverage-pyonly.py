#!/usr/bin/env python3
"""The coverage NUMERATOR is py-only (`tal.update(py["per_op"])`), so `before` can be
measured without `bend`: union of py-side ops over GRAPHS minus the four new fixtures,
against the same discovered denominator."""
from __future__ import annotations

import importlib.util
import os
import sys

os.environ["DEV"] = "CPU"
SLOP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, SLOP)
import graphcmp as G  # noqa: E402

_spec = importlib.util.spec_from_file_location("graphcmp_oracle",
                                               os.path.join(SLOP, "graphcmp-oracle.py"))
O = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(O)

G.load_tinygrad()
G.COMM = G.commutative()
import tinygrad.uop.ops as opm  # noqa: E402

NEW = ("custom_function", "mselect", "mstack", "stage")
known = {o.name for o in opm.Ops}
for drop in (False, True):
  tal = set()
  for g in sorted(G.GRAPHS):
    if drop and g in NEW:
      continue
    tal |= {G.unchunks(ln)[1] for ln in G.emit_py(g, None)}
  ops_path = sys.modules[opm.Ops.__module__].__file__
  split = O.program_op_split(O.enum_sections(ops_path), tal)
  print("# {}: {}/{} program ops ({} enum members); unexercised {}".format(
    "WITHOUT four" if drop else "WITH four", len(tal), len(split["program"]), len(known),
    sorted(split["unexercised"])))
