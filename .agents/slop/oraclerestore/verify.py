#!/usr/bin/env python3
"""RE-VERIFY the sha256 column of MANIFEST.tsv against the PRE-RENAME tree.

Claim under test: `sha256 == sha256(git show b504abf77:<path>)` for every row.

    .venv/bin/python .agents/slop/oraclerestore/verify.py            # human summary
    .venv/bin/python .agents/slop/oraclerestore/verify.py --rows     # per-row verdicts
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
MANIFEST = ROOT / ".agents/slop/oracles259/MANIFEST.tsv"
PIN = "b504abf77"      # pre-rename tree: every old `.txt` path resolves here
HEAD = "HEAD"


def blob(rev: str, rel: str) -> bytes | None:
    r = subprocess.run(["git", "cat-file", "blob", f"{rev}:{rel}"],
                       cwd=ROOT, capture_output=True)
    return r.stdout if r.returncode == 0 else None


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def rows() -> list[dict]:
    with open(MANIFEST, newline="") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", action="store_true")
    a = ap.parse_args()

    rs = rows()
    matches = mismatches = empty = absent = 0
    for r in rs:
        b = blob(PIN, r["path"])
        if b is None:
            absent += 1
            print(f"ABSENT@{PIN}\t{r['path']}")
            continue
        if len(b) == 0:
            empty += 1
            if a.rows:
                print(f"EMPTY\t{r['path']}\tmanifest={r['sha256']}\tblob={sha(b)}")
            continue
        got = sha(b)
        if got == r["sha256"]:
            matches += 1
            if a.rows:
                print(f"MATCH\t{r['path']}")
        else:
            mismatches += 1
            print(f"MISMATCH\t{r['path']}\tmanifest={r['sha256']}\tblob={got}")

    print(f"\nRE-VERIFY sha256 vs sha256(git show {PIN}:<path>)")
    print(f"  rows           : {len(rs)}")
    print(f"  matches        : {matches}")
    print(f"  mismatches     : {mismatches}")
    print(f"  empty-blob skip: {empty}")
    print(f"  absent@{PIN}    : {absent}")
    return 1 if (mismatches or absent) else 0


if __name__ == "__main__":
    sys.exit(main())
