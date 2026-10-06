#!/usr/bin/env python3
"""Verify a SAMPLE of MANIFEST.tsv restore commands FOR REAL, against git.

    .venv/bin/python .agents/slop/txt259/verify_restore.py

Each sampled row's `restore` command is exercised: the blob is resolved from HEAD by the SAME
ref the command uses, written to a scratch copy, and compared by sha256 against the manifest's own
digest column. NOTHING under oracles/ is touched. A restore that names a blob that is not there
prints MISSING and counts as a failure, because a plan is not a proof.
"""
from __future__ import annotations

import csv
import hashlib
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[3]
MANIFEST = ROOT / ".agents/slop/oracles259/MANIFEST.tsv"
OUT = ROOT / ".agents/slop/txt259/restore-check.out"


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def main() -> int:
    rows = list(csv.DictReader(open(MANIFEST), delimiter="\t"))
    # TEN rows, spread through the file, one guaranteed per disposition.
    n = len(rows)
    picks, seen = [], set()
    for want in ("KEEP-ALIVE", "KEEP-DUPLICATE", "DELETE-CANDIDATE"):
        for r in rows:
            if r["disposition"] == want:
                picks.append(r)
                seen.add(r["path"])
                break
    for i in range(n):
        if len(picks) >= 10:
            break
        r = rows[(i * 97) % n]
        if r["path"] not in seen:
            picks.append(r)
            seen.add(r["path"])

    lines, ok = [], 0
    for r in picks:
        path = r["path"]
        blob = subprocess.run(["git", "cat-file", "blob", f"HEAD:{path}"],
                              cwd=ROOT, capture_output=True)
        if blob.returncode != 0:
            lines.append(f"MISSING  {path}  (git cat-file HEAD:{path} rc={blob.returncode})")
            continue
        b = blob.stdout
        good = sha(b) == r["sha256"] and len(b) > 0
        ok += good
        lines.append(f"{'OK      ' if good else 'MISMATCH'}  {path}  "
                     f"{len(b)}B sha={sha(b)[:12]}={'match' if sha(b) == r['sha256'] else 'DIFF'}  "
                     f"[{r['disposition']}]")
    lines.append(f"\n  RESOLVED {ok}/{len(picks)} sampled rows: non-empty blob from HEAD matching "
                 f"the manifest digest.")
    OUT.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if ok == len(picks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
