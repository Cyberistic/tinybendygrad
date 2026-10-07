#!/usr/bin/env python3
"""Sweep every tracked `.agents/slop/*/` directory for the UNDECIDED shape.

A directory is DECIDED if it declares its purpose in a report (`REPORT.md`/`README.md`) OR if a
tracked file OUTSIDE it opens one of its files BY FULL PATH. Everything else is undecided: tracked,
undeclared, and unreferenced.

The reference test uses the FULL PATH, not the basename. A basename join is the fault doctrine 1
names: `.agents/slop/oracles259/census.json` and a dozen other `census.json` files are one string.
Liveness of a directory therefore means an external tracked file contains the string
`.agents/slop/<dir>/<file>` for some file it holds.
"""
from __future__ import annotations

import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
REPORTS = ("report.md", "readme.md", "findings.md")
MANIFESTS = ("manifest.tsv", "manifest.md", "manifest.rows")


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout


def main() -> int:
    tracked = git("ls-files").split()
    dirs: dict[str, list[str]] = {}
    loose: list[str] = []
    for f in tracked:
        parts = f.split("/")
        if len(parts) == 3 and parts[0] == ".agents" and parts[1] == "slop":
            loose.append(f)
        elif len(parts) >= 4 and parts[0] == ".agents" and parts[1] == "slop":
            dirs.setdefault(parts[2], []).append(f)

    # A `.agents/slop/` path is READ by code: PY/SH/BEND/MJS/MD name it; a JSON/rows snapshot that
    # merely LISTS every path is not a reader (doctrine 1). tinygrad/ and references/ are huge.
    SKIP = ("tinygrad/", "references/")
    KEEP = (".py", ".sh", ".bend", ".mjs", ".md", ".ts")
    corpus: dict[str, str] = {}
    for f in tracked:
        if f.startswith(SKIP) or not f.endswith(KEEP):
            continue
        try:
            corpus[f] = (ROOT / f).read_text(errors="ignore")
        except OSError:
            pass

    big = "\n".join(corpus.values())

    undecided = []
    no_report = []
    for name, files in sorted(dirs.items()):
        if name in ("orcdecide",):
            continue
        report = [f for f in files if pathlib.Path(f).name.lower() in REPORTS]
        manifest = [f for f in files if pathlib.Path(f).name.lower() in MANIFESTS]
        token = f".agents/slop/{name}/"
        own = "\n".join(corpus.get(f, "") for f in files)
        external = big.count(token) > own.count(token)
        if not report and not manifest:
            no_report.append(name)
        if not report and not manifest and not external:
            undecided.append(name)

    print(f"tracked `.agents/slop/*/` directories: {len(dirs)}")
    print(f"loose tracked files directly under `.agents/slop/`: {len(loose)}")
    print(f"  with a report (REPORT.md/README.md/FINDINGS.md): {len(dirs) - len(no_report)}")
    print(f"  NO report and NO manifest: {len(no_report)}")
    print(f"  NO report, NO manifest, NO full-path external reference (UNDECIDED): {len(undecided)}")
    for n in undecided:
        print(f"    - {n}  ({len(dirs[n])} files)")
    print("\nno-report dirs (report absence only):")
    for n in no_report:
        mark = "UNDECIDED" if n in undecided else "referenced"
        print(f"    - {n}  [{mark}]  {len(dirs[n])} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
