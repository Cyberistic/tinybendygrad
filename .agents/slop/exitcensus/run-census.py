#!/usr/bin/env python3
"""run-census.py -- RUN `.agents/slop/exitcodes/census.py` WITHOUT WRITING OUTSIDE THIS DIRECTORY.

`census.py` writes its row file to `OUT = HERE / "codes.rows"`, and `HERE` is the directory the
census LIVES in -- `.agents/slop/exitcodes/`.  This unit may write only under
`.agents/slop/exitcensus/`, so `OUT` is REDIRECTED to a path inside this directory and the
census file itself is executed byte-for-byte as committed: it is loaded by path and its `main()`
is called, so the code under test is the original, not a copy that can drift from it.
"""
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CENSUS = ROOT / ".agents" / "slop" / "exitcodes" / "census.py"

spec = importlib.util.spec_from_file_location("exitcodes_census", CENSUS)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.OUT = HERE / "codes.rows"
mod.main()
sys.exit(0)
