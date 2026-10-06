#!/usr/bin/env python3
"""Read the graphcmp coverage denominator WITHOUT running `bend`.

`.agents/slop/graphcmp-oracle.py` computes its COVERAGE numerator (`len(tal)`) from the
PY side alone (`tal.update(py["per_op"])`, oracle.py:303) and its DENOMINATOR from the
enum source (`program_op_split`, oracle.py:234). Only the `bd` census calls `bend`
(oracle.py:287). So this wrapper imports the oracle, replaces `emit_bend` with an empty
census, runs the oracle's own `main()`, and keeps only the pure-py numbers. Nothing here
re-derives the split; it re-runs the oracle with its one bend call made vacuous.
"""
import contextlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SLOP = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, SLOP)
import graphcmp as G  # noqa: E402
import importlib.util  # noqa: E402

spec = importlib.util.spec_from_file_location("oracle", os.path.join(SLOP, "graphcmp-oracle.py"))
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)

G.emit_bend = lambda dev, graph, *a, **k: ([],)

buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = oracle.main()
out = buf.getvalue()
for line in out.splitlines():
    if line.startswith(("# DEV=", "# COVERAGE:", "# DENOMINATOR:", "# NOT REACHED",
                        "# TOTAL:", "#   AND ", "#   OF WHICH ")):
        print(line)
print(f"# oracle main() rc={rc} (non-zero ONLY because the bend lane is made vacuous here)")
