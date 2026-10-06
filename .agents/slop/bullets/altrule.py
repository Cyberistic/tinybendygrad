"""Alternative rules for the AGENTS.md bullet population, to explain the earlier 24/10/20."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MD = ROOT / "AGENTS.md"

NARROW = re.compile(r"(?:checks|gates)/[A-Za-z0-9_.-]+\.py")          # task rule (c)
FILELINE = re.compile(r"[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:\d+")
BROAD_PATH = re.compile(r"`[A-Za-z0-9_./-]+\.[A-Za-z0-9]+`")          # any backticked filename
BROAD_SLASH = re.compile(r"`[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+`")        # any backticked path
BACKTICK_CMD = re.compile(r"`[a-z][a-z0-9_-]+(?: [^`]*)?`")            # any backticked command


def blocks(lines):
    starts = [i for i, l in enumerate(lines) if not l.lstrip().startswith("|") and re.match(r"^( *)- ", l)]
    out = []
    for k, s in enumerate(starts):
        end = starts[k + 1] if k + 1 < len(starts) else len(lines)
        blk = [lines[s]]
        for j in range(s + 1, end):
            if lines[j].strip() == "" or lines[j].lstrip().startswith("|"):
                break
            blk.append(lines[j])
        out.append((s + 1, "\n".join(blk)))
    return out


lines = MD.read_text().split("\n")
if lines and lines[-1] == "":
    lines.pop()
bl = blocks(lines)

def cnt(pred):
    return sum(1 for _, t in bl if pred(t))

print(f"bullets                         = {len(bl)}")
print(f"narrow instrument (checks|gates/*.py or file:line) = {cnt(lambda t: NARROW.search(t) or FILELINE.search(t))}")
print(f"broad: backticked filename      = {cnt(lambda t: BROAD_PATH.search(t))}")
print(f"broad: backticked slash-path    = {cnt(lambda t: BROAD_SLASH.search(t))}")
print(f"broad: backticked command       = {cnt(lambda t: BACKTICK_CMD.search(t))}")
print(f"broad union (file OR slash OR cmd) = {cnt(lambda t: BROAD_PATH.search(t) or BROAD_SLASH.search(t) or BACKTICK_CMD.search(t))}")
print(f"MEASURED uppercase only         = {cnt(lambda t: 'MEASURED' in t)}")
print(f"measured case-insensitive       = {cnt(lambda t: 'measured' in t.lower())}")
print(f"neither (narrow, ci-measured)   = {cnt(lambda t: not (NARROW.search(t) or FILELINE.search(t)) and 'measured' not in t.lower())}")
print(f"neither (broad, ci-measured)    = {cnt(lambda t: not (BROAD_PATH.search(t) or BROAD_SLASH.search(t) or BACKTICK_CMD.search(t)) and 'measured' not in t.lower())}")
print()
print("bullets the broad rule sees as instrument but the narrow rule does not:")
for ln, t in bl:
    if (BROAD_PATH.search(t) or BROAD_SLASH.search(t) or BACKTICK_CMD.search(t)) and not (NARROW.search(t) or FILELINE.search(t)):
        print(f"  L{ln}: {t.splitlines()[0][:120]}")
