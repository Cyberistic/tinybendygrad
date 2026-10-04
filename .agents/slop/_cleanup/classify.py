#!/usr/bin/env python3
"""Classify every file under .agents/slop and runs, BY EVIDENCE, so deletion is checkable.

The rule this exists to enforce: a file is deleted only when it is junk-class AND no
committed report cites it AND it is not live. "Junk-class" is mechanical wherever it can
be; where it cannot be, the verdict is UNKNOWN and the file is kept.

DELIBERATELY NOT A CLEANUP SCRIPT. It writes a manifest and deletes nothing, so the
decision and the act stay auditable apart.

    usage: .venv/bin/python .agents/slop/_cleanup/classify.py [--live-minutes N] > MANIFEST.tsv

Two things this file has already been wrong about, kept here because the corrections are
the useful part:

1.  The citation index was first built with `git grep -h "" -- '*.md'` over the whole repo.
    That took longer than 20 minutes on 6,041 tracked slop files and was abandoned. The
    index only needs the REPORTS, so it now reads the committed top-level .md by name.

2.  The citation matcher was first a BARE BASENAME match, and reported 3,574 "cited" --
    138 copies of one `__init__.bend`, 96 of `__init__.py`, 74 of `README.md`. One mention
    of a word "cites" every shadow copy of it, and this tree holds 287 mutated copies of 143
    real files. That flaw was written in this file's own docstring and then implemented
    anyway. It is now path-specific, with a distinctiveness bound.

    THE GENERAL LESSON, WHICH IS THE SAME ONE THREE TIMES TODAY: a true observation
    compressed into a rule is not a rule, and the compression is where the error enters.
"""
from __future__ import annotations
import collections
import os
import re
import subprocess
import sys
import time

# .agents/slop/_cleanup/classify.py -> .agents/slop/_cleanup -> .agents/slop -> .agents -> repo
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
SLOP = os.path.join(ROOT, ".agents/slop")
RUNS = os.path.join(ROOT, "runs")

# ---------------------------------------------------------------- the entry points
# Enumerated BY HAND because they cannot be discovered: measured 2026-10-05, ZERO of the
# top-level drivers is named in AGENTS.md, agent-core.md, or any other driver. A discovery
# rule would find nothing, which is the reason this list is literal.
ENTRY = {
    "substrate-check.sh": "per-file instrument routing + size + cross-file name resolution",
    "e2e.sh":             "the 8-stage artifact; PASS/FAIL/SKIP, exit status is the AND",
    "graphcmp-run.sh":    "one verdict line per corpus graph",
    "graphcmp-repro.sh":  "two-run stability + the pinned health gate",
    "graphcmp.py":        "the differ's py side and its own census",
    "graphcmp.bend":      "the differ's bend side",
    "graphcmp-oracle.py": "upstream construction for every corpus graph",
}
# A driver's PARTS are also entry points: the gates they call are what decides.
ENTRY_DIRS = {"abi", "abi4", "jsfix", "jstage", "cshape", "fp8fix", "fp8dec", "jslane2"}

# A basename may be matched on its own only if it is RARE in this tree.
MAX_BASENAME_HITS = 3

TEMP_RE = re.compile(r"(\.staged-mem-|\.staged-blob-|\.mut$|~$|\.bak$|\.orig$|\.rej$|"
                     r"^\.tmp\.|\.workdir$|\.swp$|^\.DS_Store$)")


def committed_reports() -> str:
    """Every COMMITTED report, concatenated once. A file named here is CITED."""
    try:
        names = subprocess.run(["git", "ls-files", "--", ".agents/slop/*.md"],
                               cwd=ROOT, capture_output=True, text=True).stdout.split()
    except Exception:
        return ""
    chunks = []
    for nm in names:
        try:
            r = subprocess.run(["git", "show", f"HEAD:{nm}"], cwd=ROOT,
                               capture_output=True, text=True, errors="replace")
            if r.returncode == 0:
                chunks.append(r.stdout)
        except Exception:
            pass
    return "\n".join(chunks)


def cite_index(blob: str, rels: dict[str, str]) -> set[str]:
    """Candidate paths a report plausibly cites. PATH-SPECIFIC, then RARE-BASENAME."""
    basecount = collections.Counter(b for b in rels.values())
    out: set[str] = set()
    for rel, base in rels.items():
        inner = rel[len("slop/"):] if rel.startswith("slop/") else rel
        if inner and inner in blob:
            out.add(rel)
        elif basecount[base] <= MAX_BASENAME_HITS and base in blob:
            out.add(rel)
    return out


def live_set(minutes: int) -> set[str]:
    cutoff = time.time() - minutes * 60
    live: set[str] = set()
    for base in (SLOP, RUNS, os.path.join(ROOT, "tinybendygrad")):
        for dirpath, _dirs, files in os.walk(base):
            for f in files:
                p = os.path.join(dirpath, f)
                try:
                    if os.path.getmtime(p) >= cutoff:
                        live.add(os.path.relpath(p, ROOT))
                except OSError:
                    pass
    return live


def classify(rel: str, live: set[str], cited: set[str], executable: bool) -> str:
    name = os.path.basename(rel)
    parts = rel.split(os.sep)
    top = parts[2] if len(parts) > 2 else ""

    if rel in live:
        return "LIVE"
    if name in ENTRY and top == "slop":
        return "KEEP-ENTRY"
    if top in ENTRY_DIRS:
        return "KEEP-ENTRY-DIR"
    if top == "slop" and name.endswith((".sh", ".py")) and executable:
        return "KEEP-DRIVER?"

    # mechanical junk, in the order that must win over everything below
    if name.endswith((".pyc", ".pyo")) or "__pycache__" in rel:
        return "JUNK-BYTECODE"
    if TEMP_RE.search(name):
        return "JUNK-TEMP"
    try:
        if os.path.getsize(os.path.join(ROOT, rel)) == 0:
            return "JUNK-ZERO"
    except OSError:
        return "GONE"

    if rel in cited:
        return "KEEP-EVIDENCE" if name.endswith((".err", ".out")) else "KEEP-CITED"
    if name.endswith((".err", ".out")):
        return "JUNK-CAPTURE"
    if name.endswith((".md", ".txt")) and top == "slop":
        return "KEEP-REPORT?"
    if rel.startswith("runs" + os.sep):
        return "RUN-ARTIFACT"
    if top not in ("slop", ""):
        return "SCRATCH?"
    return "UNKNOWN"


def main() -> int:
    live_min = 90
    if "--live-minutes" in sys.argv:
        live_min = int(sys.argv[sys.argv.index("--live-minutes") + 1])

    live = live_set(live_min)
    cands: list[str] = []
    for base in (SLOP, RUNS):
        for dirpath, _dirs, files in os.walk(base):
            for f in files:
                cands.append(os.path.join(dirpath, f))

    rels = {p: os.path.relpath(p, ROOT) for p in cands}
    cited = cite_index(committed_reports(), rels)

    rows, counts, sizes = [], collections.Counter(), collections.Counter()
    for p in sorted(cands):
        rel = rels[p]
        try:
            ex = os.access(p, os.X_OK)
            sz = os.path.getsize(p)
        except OSError:
            ex, sz = False, -1
        v = classify(rel, live, cited, ex)
        counts[v] += 1
        sizes[v] += max(sz, 0)
        rows.append((v, sz, rel))

    print(f"# MANIFEST  live_minutes={live_min}  files={len(rows)}  "
          f"reports_read={len(committed_reports())}chars")
    for v, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"#   {v:16s} {n:6d} files  {sizes[v]/1048576:8.1f} MB")
    print(f"# {'VERDICT':16s} {'BYTES':>12s}  PATH")
    for v, sz, rel in sorted(rows):
        print(f"{v:16s} {sz:12d}  {rel}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
