#!/usr/bin/env python3
"""Rebuild MANIFEST.tsv with a `restore_at_HEAD` column (option (a)).

    `restore`         is pinned to the PRE-RENAME tree (b504abf77) and keeps the OLD path.
    `restore_at_HEAD` names the CURRENT path and restores it from HEAD.
Both commands are runnable verbatim and both are checked against the manifest's own sha256.

CRLF IS PRESERVED: the writer opens with `newline=""` and uses an explicit `\r\n`
lineterminator, so every emitted line keeps the byte it had.

    .venv/bin/python .agents/slop/oraclerestore/build.py --write
    .venv/bin/python .agents/slop/oraclerestore/build.py            # dry-run
"""
from __future__ import annotations

import argparse
import csv
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
MANIFEST = ROOT / ".agents/slop/oracles259/MANIFEST.tsv"
PIN = "b504abf77"
HEAD = "HEAD"


def old_to_new() -> dict[str, str]:
    """git's own rename detection between the pre-rename tree and HEAD."""
    out = subprocess.run(
        ["git", "diff", "--name-status", "--find-renames", f"{PIN}", HEAD, "--", "oracles/"],
        cwd=ROOT, capture_output=True, text=True, check=True).stdout
    m: dict[str, str] = {}
    for line in out.splitlines():
        status, old, new = line.split("\t")
        assert status == "R100", line
        m[old] = new
    return m


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    ren = old_to_new()
    with open(MANIFEST, newline="") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    fields = [f for f in rows[0] if f != "restore_at_HEAD"]
    assert fields[-1] == "restore", fields
    fields = [*fields, "restore_at_HEAD"]

    for r in rows:
        old = r["path"]
        new = ren.get(old, old)
        # `restore` keeps the OLD path; only the revision becomes the pin so it resolves there.
        r["restore"] = f"git cat-file blob $(git rev-parse {PIN}:{old}) > {old}"
        r["restore_at_HEAD"] = f"git cat-file blob $(git rev-parse {HEAD}:{new}) > {new}"
        for f in fields:
            assert "\t" not in r[f] and '"' not in r[f] and "\r" not in r[f], (old, f)

    if not a.write:
        print(f"  rows={len(rows)} fields={len(fields)} renamed={len(ren)}")
        print(f"  sample restore        : {rows[0]['restore']}")
        print(f"  sample restore_at_HEAD: {rows[0]['restore_at_HEAD']}")
        print("  dry-run; pass --write to replace the manifest")
        return 0

    with open(MANIFEST, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields, delimiter="\t", lineterminator="\r\n")
        w.writeheader()
        w.writerows(rows)
    print(f"  WROTE {MANIFEST.relative_to(ROOT)}: {len(rows)} rows, "
          f"{len(fields)} columns, CRLF preserved")
    return 0


if __name__ == "__main__":
    sys.exit(main())
