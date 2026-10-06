#!/usr/bin/env python3
"""prune3/verify_strays.py -- is a KEEP row in `strays/MANIFEST.tsv` really unreproducible?

For each `working/` and `origin/` KEEP row (a copy of a live `tinybendygrad/<rel>`), hash the
committed blob and ask whether that exact blob content ever sat at the live path in ANY commit.
If yes, the manifest's "no revision matches" is FALSE and the file is redundant.

Every history read is batched through one `git cat-file --batch`, not one process per revision.

    .venv/bin/python .agents/slop/prune3/verify_strays.py
"""
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / ".agents/slop/strays/MANIFEST.tsv"


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True,
                          text=True, check=True).stdout


def batch_oids(specs: list[str]) -> list[str | None]:
    """One `git cat-file --batch` pass: spec -> oid or None."""
    payload = "\n".join(specs) + "\n"
    out = subprocess.run(["git", "cat-file", "--batch"], cwd=ROOT, input=payload,
                         capture_output=True, text=True).stdout
    oids: list[str | None] = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] == "missing":
            oids.append(None)
        elif len(parts) >= 3:
            oids.append(parts[0])
        else:
            oids.append(None)
    return oids


def main() -> int:
    rows = [l.split("\t") for l in MANIFEST.read_text().splitlines()[1:] if l]
    kept = [r for r in rows if r[3] == "KEEP" and r[0] in ("working", "origin")]

    specs: list[str] = []
    per_path: list[tuple[str, str, list[int]]] = []   # arm, rel, spec indices
    for arm, _role, rel, _v, _w, _r in kept:
        commits = git("log", "--all", "--format=%H", "--", rel).split()
        idx = []
        for c in commits:
            idx.append(len(specs))
            specs.append(f"{c}:{rel}")
        per_path.append((arm, rel, idx))

    oids = batch_oids(specs)

    print(f"{'arm':8} {'rel path':54} {'in-history':10} verdict")
    repro_count = 0
    for arm, rel, idx in per_path:
        strays_oid = git("rev-parse", f"HEAD:.agents/slop/strays/{arm}/{rel}").strip()
        seen = {oids[i] for i in idx if oids[i]}
        repro = strays_oid in seen
        repro_count += repro
        print(f"{arm:8} {rel:54} {str(repro):10} "
              f"{'MANIFEST CLAIM FALSE (blob is in history)' if repro else 'manifest HOLDS (unique blob, %d revisions seen)' % len(seen)}")
    print(f"\nreproducible {repro_count} of {len(per_path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
