#!/usr/bin/env python3
"""`.agents/TOOLS.md`'s OWN population, re-measured with the ledger's OWN extraction rule and
ONE change, stated: `git ls-files` (the INDEX) becomes `git ls-tree -r HEAD --name-only` (the
COMMIT). `AGENTS.md` records the index as chronically stale here, and `checks/repro-paths.py:72-78`
records the same substitution as a fix it had to make for itself.

READ-ONLY. `.agents/slop/toolsledger/extract.py:42` WRITES `paths.tsv`, which is outside this
census's write scope, so this file re-implements `:20-41` and prints instead of writing. The
extraction rule is quoted, not paraphrased, so the two can be diffed.

usage: .venv/bin/python .agents/slop/shapecensus/toolsmd.py
"""
from __future__ import annotations

import collections
import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
os.chdir(ROOT)

text = open(".agents/TOOLS.md").read()
index = set(subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.split())
head = set(subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"],
                          capture_output=True, text=True).stdout.split())


def norm(t: str) -> str:
    t = t.strip().strip("*_[]()`").rstrip('.,;:)("')
    return t[2:] if t.startswith("./") else t


toks = sorted({norm(t) for t in re.findall(r"`([^`\n]+)`", text) if "/" in norm(t)})
toks = [t for t in toks if not (t.startswith(("http", "git@", "//")) or "github.com" in t)]
toks = [t for t in toks if re.fullmatch(r"[~A-Za-z0-9_./@+\-]+", t)]


def present(t: str, tracked: set[str]) -> bool:
    if t.startswith("/"):
        return os.path.exists(t)
    if t in tracked or os.path.exists(t):
        return True
    return any(f.startswith(t.rstrip("/") + "/") for f in tracked)


INSTR = re.compile(r"(gate|check|sweep|differ|e2e|repro|corpus|mutate|selftest|pin|census|"
                   r"no-txt|substrate)")


def kind(t: str) -> str:
    base = os.path.basename(t)
    if "oracle" in base or "arena" in base:
        return "ORACLE"
    return "INSTRUMENT" if INSTR.search(base) else "EVIDENCE"


print(f"TOOLS.md lines                : {len(text.splitlines())}")
print(f"distinct paths (the ledger rule): {len(toks)}")
for label, tracked in (("INDEX  git ls-files      ", index), ("HEAD   git ls-tree -r HEAD", head)):
    c = collections.Counter("PRESENT" if present(t, tracked) else "ABSENT" for t in toks)
    ki = collections.Counter(kind(t) for t in toks
                             if not present(t, tracked) and kind(t) == "INSTRUMENT")
    print(f"{label}: entries={len(tracked)}  present={c['PRESENT']}  absent={c['ABSENT']}  "
          f"absent-INSTRUMENT={ki['INSTRUMENT']}  "
          f"absent under .agents/slop/={sum(1 for t in toks if not present(t, tracked) and t.startswith('.agents/slop/'))}")
print(f"index\\HEAD disagreement          : {len(index ^ head)} entries")