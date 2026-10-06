#!/usr/bin/env python3
"""PROVE the two restore columns, verbatim, on 10 rows.

For each chosen row, in a fresh scratch directory, run BOTH commands exactly as they
appear in the manifest -- `restore` (OLD path @ b504abf77) and `restore_at_HEAD`
(NEW path @ HEAD) -- then sha256 the file each one produced and compare it to the
manifest's own digest. `oracles/` is never written; GIT_DIR points git at this repo
while the shell's cwd is the scratch tree, so the redirection lands in the scratch.

    .venv/bin/python .agents/slop/oraclerestore/prove.py
"""
from __future__ import annotations

import csv
import hashlib
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
MANIFEST = ROOT / ".agents/slop/oracles259/MANIFEST.tsv"


def sha(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def run_verbatim(cmd: str, scratch: pathlib.Path) -> bool:
    out = cmd.split(">", 1)[1].strip()          # the redirect target
    (scratch / out).parent.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "GIT_DIR": str(ROOT / ".git")}
    r = subprocess.run(["bash", "-c", cmd], cwd=scratch, env=env, capture_output=True)
    return r.returncode == 0 and (scratch / out).is_file()


def pick(rows: list[dict], k: int = 10) -> list[dict]:
    """One NON-EMPTY row per distinct OLD->NEW extension, then evenly-spaced fillers."""
    rows = [r for r in rows if int(r["bytes"]) > 0]
    seen, chosen = set(), []
    for r in rows:
        ext = (r["path"].rsplit(".", 1)[-1], r["restore_at_HEAD"].split(">")[1].strip().rsplit(".", 1)[-1])
        if ext not in seen:
            seen.add(ext)
            chosen.append(r)
    step = max(1, len(rows) // (k - len(chosen) + 1))
    for r in rows[::step]:
        if len(chosen) >= k:
            break
        if r not in chosen:
            chosen.append(r)
    return chosen[:k]


def main() -> int:
    with open(MANIFEST, newline="") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    chosen = pick(rows)

    print(f"{'#':>2}  {'OLD @ b504abf77':<46} {'NEW @ HEAD':<46} sha256")
    ok = 0
    for i, r in enumerate(chosen, 1):
        old = r["restore"].split(">")[1].strip()
        new = r["restore_at_HEAD"].split(">")[1].strip()
        with tempfile.TemporaryDirectory() as td:
            t = pathlib.Path(td)
            a = run_verbatim(r["restore"], t)
            got_old = sha(t / old) if a else None
            b = run_verbatim(r["restore_at_HEAD"], t)
            got_new = sha(t / new) if b else None
        match = bool(got_old and got_old == r["sha256"]) and bool(got_new and got_new == r["sha256"])
        ok += match
        detail = "" if match else f"  old={got_old} new={got_new} want={r['sha256']}"
        print(f"{i:>2}  {old:<46} {new:<46} {'MATCH' if match else 'FAIL'}{detail}")

    print(f"\nPROVEN {ok}/{len(chosen)} rows: BOTH forms restore a non-empty blob whose sha256 "
          f"equals the manifest's digest column.")
    return 0 if ok == len(chosen) else 1


if __name__ == "__main__":
    sys.exit(main())
