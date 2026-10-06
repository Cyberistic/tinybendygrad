#!/usr/bin/env python3
"""The oracle's OWN main(), run with the four new fixtures removed from G.GRAPHS, to get a
`before` coverage/selftest measurement without editing graphcmp.py. Same code path and same
bend invocations as `graphcmp-oracle.py`; only the population differs."""
from __future__ import annotations

import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SLOP = os.path.dirname(HERE)
sys.path.insert(0, SLOP)

_spec = importlib.util.spec_from_file_location("graphcmp_oracle",
                                               os.path.join(SLOP, "graphcmp-oracle.py"))
O = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(O)

import graphcmp as G  # noqa: E402

for k in ("custom_function", "mselect", "mstack", "stage"):
  del G.GRAPHS[k]

sys.exit(O.main())
