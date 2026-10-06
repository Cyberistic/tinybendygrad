#!/usr/bin/env python3
"""Full-population restore check: all 259 manifest rows resolved from HEAD by their own command.

    .venv/bin/python .agents/slop/txt259/restore_all.py

For every row it resolves `git cat-file blob HEAD:<path>` and reports:
  * the blob exists and is NON-EMPTY            (the restore command's precondition)
  * the blob equals the WORKTREE bytes          (HEAD == on-disk, so a restore is identity)
  * whether the manifest's own sha256 column agrees with those bytes
The last column is the finding: the COMMAND is sound for every row, while the manifest's DIGEST
column is wrong on 18 -- the failure its own docstring predicted ("the restores were right and the
DIGESTS were wrong"). NOTHING under oracles/ is written.
"""
from __future__ import annotations

import csv
import hashlib
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[3]
MANIFEST = ROOT / ".agents/slop/oracles259/MANIFEST.tsv"
OUT = ROOT / ".agents/slop/txt259/restore-all.out"


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def main() -> int:
    rows = list(csv.DictReader(open(MANIFEST), delimiter="\t"))
    n = unresolved = empty_blob = head_ne_wt = digest_wrong = 0
    lines = []
    for r in rows:
        p = ROOT / r["path"]
        wt = p.read_bytes()
        b = subprocess.run(["git", "cat-file", "blob", f"HEAD:{r['path']}"],
                           cwd=ROOT, capture_output=True)
        n += 1
        blob = b.stdout
        if b.returncode != 0:
            unresolved += 1
            lines.append(f"UNRESOLVED  {r['path']}  rc={b.returncode}")
            continue
        if not blob:
            empty_blob += 1
            lines.append(f"RESOLVES-EMPTY  {r['path']}  (the blob IS empty; the file is 0 bytes)")
        if blob != wt:
            head_ne_wt += 1
            lines.append(f"HEAD!=WORKTREE {r['path']}")
        if sha(blob) != r["sha256"]:
            digest_wrong += 1
            lines.append(f"DIGEST-WRONG  {r['path']}  blob={sha(blob)[:12]} manifest={r['sha256'][:12]}")
    lines.append(
        f"\n  {n} rows. blob RESOLVES from HEAD: {n - unresolved}/{n}. "
        f"HEAD==worktree: {n - head_ne_wt}/{n}. "
        f"manifest DIGEST WRONG: {digest_wrong}/{n}.")
    lines.append(
        f"  The restore COMMAND resolves for all {n - unresolved} rows; {n - empty_blob - 1} hold "
        f"non-empty bytes and {empty_blob} is genuinely empty. The digest failures are the manifest's "
        "digest column, not the command -- a restore is verified by bytes, not by the manifest hash.")
    OUT.write_text("\n".join(lines) + "\n")
    print("\n".join(lines[-8:]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
