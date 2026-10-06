#!/usr/bin/env python3
"""Recompute every MANIFEST.tsv digest from the HEAD blob it restores from.

The manifest's `restore` is `git cat-file blob $(git rev-parse HEAD:<path>)`. So the
digest the manifest SHOULD hold is sha256(HEAD:<path>), computed here the same way.
Reports rows wrong, and rows whose restore is verified by bytes.
"""
import csv
import hashlib
import subprocess
import sys

ROOT = "."
MANIFEST = ".agents/slop/oracles259/MANIFEST.tsv"
# The last commit whose tree holds the OLD `.txt` names. The rename landed in
# 4d0a2b258 ("notxt139"), so its parent is where the manifest's `HEAD:<oldpath>`
# restore was written to read. Auditing against HEAD would report 258 false
# failures (the names are gone, not the bytes).
REF = sys.argv[1] if len(sys.argv) > 1 else "HEAD"


def head_blob(path):
    p = subprocess.run(["git", "cat-file", "blob", f"{REF}:{path}"],
                       cwd=ROOT, capture_output=True)
    return p.returncode, p.stdout


def main() -> int:
    rows = list(csv.DictReader(open(MANIFEST), delimiter="\t"))
    print(f"ref: {REF}")
    print(f"manifest rows: {len(rows)}")
    wrong = []
    verified = 0
    unresolved = []
    for r in rows:
        path = r["path"]
        rc, blob = head_blob(path)
        if rc != 0:
            unresolved.append(path)
            continue
        good = hashlib.sha256(blob).hexdigest()
        manifest = r["sha256"]
        if manifest == good:
            verified += 1
        else:
            wrong.append((path, manifest, good, len(blob)))
    print(f"HEAD blob resolves:        {len(rows) - len(unresolved)}/{len(rows)}")
    print(f"digest ALREADY correct:    {verified}/{len(rows)}")
    print(f"digest WRONG:              {len(wrong)}/{len(rows)}")
    print(f"unresolved HEAD path:      {len(unresolved)}")
    print()
    print("WRONG ROWS (path, manifest_sha, head_sha, head_bytes, manifest_bytes):")
    for path, m, g, nb in wrong:
        mb = next((r["bytes"] for r in rows if r["path"] == path), "?")
        print(f"  {path}\n     manifest={m}\n     head    ={g}  (head {nb} B, manifest {mb} B)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
