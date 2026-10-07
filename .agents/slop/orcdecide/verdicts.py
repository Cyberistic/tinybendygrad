#!/usr/bin/env python3
"""Per-file verdict for `.agents/slop/oracles259/`.

A file is KEPT iff a tracked code/doc file OUTSIDE the directory names its FULL PATH (a real
reader), or it is the directory's own decision report. Everything else is RETIRE: no reader by
full path, and superseded by a named current instrument.
"""
from __future__ import annotations

import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
D = ".agents/slop/oracles259/"
CODE = (".py", ".sh", ".bend", ".mjs", ".ts", ".js")
KEEP = {
    "MANIFEST.tsv": "the 259-row restore record; opened by oraclerestore/{build,verify,prove,measure}.py, txt259/{restore_all,verify_restore}.py, txtexec/{digest_audit,fix_manifest2,restore_paths}.py",
    "census.json": "the 259-row pre-rename census; imported by .agents/slop/oracletxt/shape_of_stale.py:21",
}
SUPERSEDED = {
    "plants.py": "superseded by .agents/slop/oracletxt/plant.py (same shape claims + corrected reach); crashes on renamed literals at :68-69",
    "classify.py": "superseded by checks/oracle-txt-census.py",
    "manifest.py": "superseded by .agents/slop/oraclerestore/build.py (reads and rewrites MANIFEST.tsv)",
    "cited.py": "one-time reader-set producer; nothing imports it",
    "declared_join.py": "one-time; nothing imports it",
    "ordering.py": "repoint list consumed by txtexec; job done by checks/oracle-txt-census.py",
    "othercopies.py": "one-time duplicate scan; nothing imports it",
}


def git(*a: str) -> str:
    return subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True).stdout


def main() -> int:
    files = [f for f in git("ls-files").split() if f.startswith(D)]
    print("file\tbytes\tcode_readers\treader_names\tverdict\treason")
    for f in sorted(files):
        name = pathlib.Path(f).name
        hits = git("grep", "-l", "--fixed-strings", f).splitlines()
        readers = [r for r in hits
                   if not r.startswith(D) and r != f and r.endswith(CODE)]
        n = len(readers)
        if name in KEEP:
            verdict, why = "KEEP", KEEP[name]
        else:
            verdict = "RETIRE"
            why = SUPERSEDED.get(name, "one-time output/stdout capture; no reader by full path")
        size = (ROOT / f).stat().st_size
        reader_names = ", ".join(sorted({pathlib.Path(r).name for r in readers})) or "—"
        print(f"{name}\t{size}\t{n}\t{reader_names}\t{verdict}\t{why}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
