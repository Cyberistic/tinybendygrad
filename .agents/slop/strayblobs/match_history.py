#!/usr/bin/env python3
"""match_history.py -- which COMMITS' ops.bend (git sha1 blob) equals each staged blob.

The staged copy is `jj --ignore-working-copy file show -r @` = ops.bend as committed
at run time, so a git-blob match names exactly the revision the run read, and that
revision is the restore path.
"""
import hashlib
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PID_SHA1 = {}
for pid in ["36145", "64022", "66397", "97648"]:
    data = (ROOT / "tinybendygrad/uop" / f"ops.staged-blob-{pid}").read_bytes()
    PID_SHA1[pid] = hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()
want = {}
for k, v in PID_SHA1.items():
    want.setdefault(v, []).append(k)

revs = subprocess.run(["git", "rev-list", "--all", "--", "tinybendygrad/uop/ops.bend"],
                      cwd=ROOT, capture_output=True, text=True).stdout.split()
p = subprocess.run(["git", "cat-file", "--batch-check"],
                   input="".join("%s:tinybendygrad/uop/ops.bend\n" % r for r in revs),
                   cwd=ROOT, capture_output=True, text=True)
matches = {pid: [] for pid in PID_SHA1}
for rev, line in zip(revs, p.stdout.splitlines()):
    oid = line.split()[0]
    for pid in want.get(oid, []):
        matches[pid].append(rev)

print("revisions touching ops.bend: %d" % len(revs))
print("blob_pid\tgit_sha1\tmatching_commits\tnewest_commit\tnewest_date\tnewest_subject")
for pid, sha in PID_SHA1.items():
    revs_m = matches[pid]
    if not revs_m:
        print("%s\t%s\t0\t-\t-\tNO COMMITTED ops.bend HAS THESE BYTES" % (pid, sha[:16]))
        continue
    newest = revs_m[0]
    log = subprocess.run(["git", "log", "-1", "--format=%H\t%ad\t%s", "--date=short", newest],
                         cwd=ROOT, capture_output=True, text=True).stdout.strip()
    print("%s\t%s\t%d\t%s" % (pid, sha[:16], len(revs_m), log))
