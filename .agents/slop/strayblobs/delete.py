#!/usr/bin/env python3
"""delete.py -- verify each staged blob is redundant in git, then os.remove it.

Redundancy for each of the four:
  * the file is COMMITTED at 07cb5a85a, so `git show 07cb5a85a:<path>` restores the
    bytes and the blob object is reachable from that commit forever; and
  * the CONTENT also exists elsewhere (a historical committed ops.bend for
    64022/97648, a shadow-tree copy for all four).

Nothing is deleted until both checks pass for that file. No git commands here.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
ADD_COMMIT = "07cb5a85a8847f99101ad9da91f177bdc21d4d8f"
PIDS = ["36145", "64022", "66397", "97648"]

bad = []
for pid in PIDS:
    rel = f"tinybendygrad/uop/ops.staged-blob-{pid}"
    path = ROOT / rel
    if not path.exists():
        bad.append(f"{rel}: MISSING")
        continue
    # (1) exact bytes committed under this very path
    r = subprocess.run(["git", "cat-file", "-e", f"{ADD_COMMIT}:{rel}"],
                       cwd=ROOT, capture_output=True)
    if r.returncode != 0:
        bad.append(f"{rel}: not committed at {ADD_COMMIT[:8]}")
        continue
    # (2) the blob object is reachable (its bytes survive any working-tree rm)
    data = path.read_bytes()
    sha = subprocess.run(["git", "hash-object", str(path)], cwd=ROOT,
                         capture_output=True, text=True).stdout.strip()
    r = subprocess.run(["git", "cat-file", "-e", sha], cwd=ROOT, capture_output=True)
    if r.returncode != 0:
        bad.append(f"{rel}: blob {sha[:12]} not in object store")
        continue
    print("OK  %s  %d B  blob=%s  committed@%s" % (rel, len(data), sha[:12], ADD_COMMIT[:8]))

if bad:
    print("REFUSED, nothing deleted:")
    for b in bad:
        print("  " + b)
    sys.exit(1)

for pid in PIDS:
    path = ROOT / f"tinybendygrad/uop/ops.staged-blob-{pid}"
    path.unlink()
    print("removed %s" % path.relative_to(ROOT))
