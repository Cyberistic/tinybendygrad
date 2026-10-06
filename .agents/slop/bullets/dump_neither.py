"""Dump the exact block text of each bullet in the NEITHER set, delimited, for paste-ready edits."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MD = ROOT / "AGENTS.md"
NARROW = re.compile(r"(?:checks|gates)/[A-Za-z0-9_.-]+\.py")
FILELINE = re.compile(r"[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:\d+")

lines = MD.read_text().split("\n")
if lines and lines[-1] == "":
    lines.pop()
starts = [i for i, l in enumerate(lines) if not l.lstrip().startswith("|") and re.match(r"^( *)- ", l)]
for k, s in enumerate(starts):
    end = starts[k + 1] if k + 1 < len(starts) else len(lines)
    blk = [lines[s]]
    for j in range(s + 1, end):
        if lines[j].strip() == "" or lines[j].lstrip().startswith("|"):
            break
        blk.append(lines[j])
    txt = "\n".join(blk)
    if not (NARROW.search(txt) or FILELINE.search(txt)) and "measured" not in txt.lower():
        print(f"===== L{s+1} =====")
        print(txt)
        print()
