#!/usr/bin/env python3
"""Re-derive the WANT/corpus gap BY DISCOVERY, at one stated moment.

Reads three things that are each some other unit's authority:
  - `corpus()`  -- `differ.py`'s own loader of `graphcmp.GRAPHS` (the population, IMPORTED);
  - `WANT`      -- `differ.py`'s table of expectations (the authority on what must print);
  - bend arms   -- the `def g_<name>` names in `.agents/slop/graphcmp.bend` (the dispatcher).

`differ.py` is loaded BY PATH (`spec_from_file_location`), never imported as a module, because
this file lives under `.agents/slop/` and `checks/` is not on `sys.path`. Nothing here writes
`runs/graphcmp/D/`; nothing here runs `bend`.
"""
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def by_path(name, rel):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def head():
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()


def bend_arms():
    body = (ROOT / ".agents/slop/graphcmp.bend").read_text()
    return {m.group(1) for m in re.finditer(r"^def g_([A-Za-z0-9_]+)\(", body, re.M)}


def main():
    differ = by_path("differ_wantwire", "checks/differ.py")
    graphs = differ.corpus()
    want = differ.WANT
    arms = bend_arms()
    gap = [g for g in graphs if g not in want]
    answerable = [g for g in graphs if g in want]
    also = sorted(g for g in want if g not in graphs)
    subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True)

    out = {
        "head": head(),
        "graphs": len(graphs),
        "want": len(want),
        "gap": len(gap),
        "answered": len(answerable),
        "want_names_absent_from_corpus": also,
        "want_rows_not_agree": {g: v for g, v in want.items() if v != "AGREE"},
        "gap_detail": [
            {"name": g, "bend_arm": g in arms,
             "py_def": f"g_{g}" in (ROOT / ".agents/slop/graphcmp.py").read_text()}
            for g in gap
        ],
        "gap_with_arm": [g for g in gap if g in arms],
        "gap_without_arm": [g for g in gap if g not in arms],
        "graph_list": list(graphs),
    }
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    sys.exit(main())
