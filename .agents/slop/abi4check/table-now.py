#!/usr/bin/env python3
"""ABI4CHK-5 -- WHAT IS THE `NEEDS/FIXES` TABLE A FUNCTION OF?  MEASURE IT.

Run `checks/abi4_gate.py`'s OWN `main()`, on the live tree, with exactly ONE
thing changed: `emit()`'s bind spelling (`<-` -> `=`), which is the stale
FIXTURE, not the subject under test.  Nothing else in the gate is touched, so
the table this prints is the gate's table, and it can be DIFFED against the
table at `135bf0204` (NEEDS 30/10/40, FIXES 0/10/10).

If the two tables are equal, the numbers are a FUNCTION OF `dtype.bend` and the
gate is not measuring `dtype.js` at all.  If they differ, say by how much.

Nothing live is written: the gate already patches a copy.
"""
from __future__ import annotations

import importlib.util
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[3]
g = importlib.util.module_from_spec(
    importlib.util.spec_from_file_location("abi4gate_table", REPO / "checks" / "abi4_gate.py"))
sys.modules["abi4gate_table"] = g
g.__spec__.loader.exec_module(g)

# THE ONLY CHANGE: the bind character.  `emit` is rebound so `run()` gets `=`.
_orig = g.emit
g.emit = lambda cs: re.sub(r"^(    v\d+ : \w+) <-", r"\1 =", _orig(cs), flags=re.M)
sys.argv = [sys.argv[0]]
g.main()