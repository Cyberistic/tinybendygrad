#!/usr/bin/env python3
"""Re-judge the port's `.bend` citations under a COPY of the tree, so a candidate
comment edit can be judged WITHOUT touching the working tree.

    .venv/bin/python .agents/slop/bendcite/probe.py --rel tinybendygrad/base.bend
"""
import importlib.util, sys, shutil, tempfile
from pathlib import Path

ROOT = Path(".").resolve()
spec = importlib.util.spec_from_file_location("bc", ROOT / "gates/bendcite-gate.py")
bc = importlib.util.module_from_spec(spec); spec.loader.exec_module(bc)

def census(base):
    rows, corpus = bc.census(base)
    return rows

if __name__ == "__main__":
    rel = sys.argv[sys.argv.index("--rel")+1]
    rows = census(ROOT)
    for r in rows:
        if r["rel"] == rel and r["verdict"] in ("WRONG-LINE","DANGLING-LINE","ABSENT-FILE"):
            print(f"{r['at']}\t{r['subject']}:{r['lo']}\t{r['verdict']}\tclaims={r.get('claims')}\ttarget={r.get('target')}\tat_line={r.get('at_line')!r}\tdecl={r.get('decl')}")
            print(f"    {r['line'][:160]}")
