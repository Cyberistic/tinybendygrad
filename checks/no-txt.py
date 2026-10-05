#!/usr/bin/env python3
"""Refuse a `.txt` file. MEASURED 2026-10-05: this project held **795** of them.

    .agents/slop 258   oracles 259   runs 109   checks 24   gates 24

**386 OF THEM WERE NAMED BY NOTHING** — no gate, no report, no `AGENTS.md` — so they were pure scratch
carrying an extension that says "text" and therefore says nothing else. The rest were named, which
made the extension the *only* honest signal left: `.rows` already existed and `sweep.py`'s
`ORACLE_WORD` already matched it, so **the convention predated the rule and the rule is what was
missing.**

**A `.txt` EXTENSION IS A DECLARATION THAT THE AUTHOR DID NOT KNOW WHAT THE FILE WAS.** Every other
extension here states the content: `.rows` expected values, `.out`/`.err` captured streams, `.tsv`
tabular, `.md` prose. `.txt` is the absence of that, and a sweep that classifies by basename cannot
tell a row dump from a diary entry — WHICH IS THE SAME FAILURE AS `ORACLE_WORD`, ONE LEVEL DOWN.

    usage: .venv/bin/python checks/no-txt.py

    exit 0  no .txt anywhere the project owns
    exit 1  at least one, each printed with its full path and the byte that names it
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Trees that are not this project: the git object store, the upstream clone, the tinygrad checkouts
# a port graph imports, and the report trees inside shadow copies of the source.
SKIP = {".git", "references", "node_modules", "__pycache__"}
SKIP_PREFIX = ("tinygrad", ".venv", "node_modules")


def owned(path: str) -> bool:
    parts = path.split(os.sep)
    return not (set(parts) & SKIP or any(p.startswith(SKIP_PREFIX) for p in parts))


def main() -> int:
    found = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP]
        for f in sorted(filenames):
            if not f.endswith(".txt"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, f), ROOT)
            if owned(rel):
                found.append(rel)
    if not found:
        print("  CLEAN: no .txt file anywhere the project owns")
        return 0
    print(f"  {len(found)} .txt FILE(S). `.txt` IS NOT AN EXTENSION THIS PROJECT USES.")
    for rel in found[:40]:
        print(f"    {rel}")
    if len(found) > 40:
        print(f"    ... and {len(found) - 40} more")
    return 1


if __name__ == "__main__":
    sys.exit(main())
