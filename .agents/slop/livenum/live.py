#!/usr/bin/env python3
"""Assemble the deliverable: every LIVE named-count occurrence with its re-derivation.

Reads `claims.tsv` (the anchor scan) and joins each claim to its ONE-LINE command.
Writes `live.rows` and a per-surface count to stderr.
"""
from __future__ import annotations

import csv
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
CMD = {
    "no-txt HARD": ".venv/bin/python checks/no-txt.py",
    "no-txt EXCUSED": ".venv/bin/python checks/no-txt.py",
    "differ.declared()": ".venv/bin/python -c \"import importlib.util as u;s=u.spec_from_file_location('d','checks/differ.py');m=u.module_from_spec(s);s.loader.exec_module(m);print(len(m.declared()))\"",
    "gates py": "ls gates/*.py | wc -l",
    "substrate.py": ".venv/bin/python -c \"print(sum(1 for _ in open('checks/substrate.py')))\"",
    "mutate harnesses": "find .agents/slop -name '*-mutate.py' | wc -l",
    "TOOLS paths": ".venv/bin/python .agents/slop/citeresolve/counts.py",
    "TOOLS present": ".venv/bin/python .agents/slop/citeresolve/counts.py",
    "TOOLS gone": ".venv/bin/python .agents/slop/citeresolve/counts.py",
    "TOOLS gone slop": ".venv/bin/python .agents/slop/citeresolve/counts.py",
    "gone instruments": ".venv/bin/python .agents/slop/citeresolve/counts.py",
    "port .bend": "find tinybendygrad -name '*.bend' | wc -l",
    "census .bend": "find tinybendygrad -name '*.bend' | wc -l",
    "tracked REPORT.md": "git ls-files '.agents/slop/*/REPORT.md' | wc -l",
    "checks sh": "ls checks/*.sh | wc -l",
    "corpus graphs": "grep graphs= runs/graphcmp/D/D0-run-summary.txt",
    "oracle-selfcheck": "grep oracle-selfcheck= runs/graphcmp/D/D0-run-summary.txt",
    "e2e skip exit": "sed -n '514p' checks/e2e.py",
    "viz README lines": "wc -l tinygrad/viz/README.md",
    "PCIDevice files": "rg -l 'PCIDevice' tinygrad/ | wc -l",
}


def main() -> int:
    rows = list(csv.DictReader(open(os.path.join(ROOT, ".agents/slop/livenum/claims.tsv"), encoding="utf-8"), delimiter="\t"))
    out = []
    for r in rows:
        if r["kind"] != "LIVE":
            continue
        cmd = CMD.get(r["claim"], "?")
        out.append((r["claim"], r["current"], r["surface"], r["line"], cmd, r["source_line"]))
    with open(os.path.join(ROOT, ".agents/slop/livenum/live.rows"), "w", encoding="utf-8") as fh:
        fh.write("claim\tcurrent\tsurface\tline\trederive\tsource_line\n")
        for o in out:
            fh.write("\t".join(str(x).replace("\t", " ") for x in o) + "\n")
    from collections import Counter
    by = Counter(o[2] for o in out)
    for k, v in sorted(by.items()):
        print(f"{k}: {v} live occurrences", file=sys.stderr)
    print(f"TOTAL live named-count occurrences: {len(out)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
