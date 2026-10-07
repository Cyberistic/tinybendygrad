#!/usr/bin/env python3
"""Resolve every `<path>:<N>` citation in the four surfaces from the WORKING TREE.

`citeresolve/scan.py` reads AS COMMITTED, so it cannot see an uncommitted edit.
This reads the working tree, so an edit that shifts a line WOULD move a cite and
would show here.  Output is sorted so two runs diff cleanly.

usage: .venv/bin/python .agents/slop/livenum/resolve.py > BEFORE.tsv
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SURFACES = [".agents/slop/*/REPORT.md"]
EXTS = "md|py|sh|bend|json|rows|tsv|out|err|txt|js|mjs|ts|toml|cfg|yml|yaml|jsonl|lock|cmp|log|names|sha256"
CITE = re.compile(r"(?P<path>\.{0,2}/?[A-Za-z0-9_][A-Za-z0-9_./@+-]*\.(?:" + EXTS + r")):(?P<spec>[0-9]+(?:[-,][0-9]+)*)", re.I)
SKIP = {".git", ".jj", ".venv", "node_modules", "__pycache__"}


def surfaces() -> list[str]:
    files = ["AGENTS.md", ".agents/TOOLS.md", ".agents/TODO.md"]
    files += [p for p in subprocess.run(["git", "ls-files", *SURFACES], cwd=ROOT,
                                        capture_output=True, text=True).stdout.splitlines() if p]
    return files


def index() -> set[str]:
    out = set()
    for dp, dn, fn in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in SKIP]
        for f in fn:
            out.add(os.path.relpath(os.path.join(dp, f), ROOT))
    return out


def main() -> int:
    exact = index()
    lines: list[str] = []
    for rel in surfaces():
        p = os.path.join(ROOT, rel)
        try:
            txt = open(p, encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            continue
        for i, line in enumerate(txt, 1):
            for m in CITE.finditer(line):
                path = m.group("path")[2:] if m.group("path").startswith("./") else m.group("path")
                nums = [int(x) for part in m.group("spec").split(",") for x in part.split("-")]
                cands = [c for c in (path, ".agents/" + path, "checks/" + path, "gates/" + path) if c in exact]
                if not cands:
                    base = os.path.basename(path)
                    cands = [c for c in exact if os.path.basename(c) == base]
                if not cands:
                    status = "GONE-FILE"
                else:
                    cands.sort(key=lambda c: (c.startswith((".agents/slop/", "runs/", "references/")), c.count("/"), c))
                    try:
                        n = sum(1 for _ in open(os.path.join(ROOT, cands[0]), encoding="utf-8", errors="replace"))
                    except OSError:
                        n = 0
                    status = "RESOLVES" if all(1 <= x <= n for x in nums) else "OUT-OF-RANGE"
                lines.append(f"{rel}\t{i}\t{path}\t{m.group('spec')}\t{status}")
    for l in sorted(lines):
        print(l)
    print(f"# citations={len(lines)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
