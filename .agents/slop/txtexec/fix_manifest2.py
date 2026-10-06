#!/usr/bin/env python3
"""Fix ONLY the sha256 column of MANIFEST.tsv, preserving the file's CRLF bytes.

The first attempt read the file in text mode, which translated CRLF->LF, so git saw all
260 lines change. This version starts from the HEAD blob (byte-for-byte) and rewrites only
field 1 of the 18 wrong rows; every other byte, including the 260 CRLF endings, is untouched.
"""
import hashlib
import subprocess

MANIFEST = ".agents/slop/oracles259/MANIFEST.tsv"
PRE = "b504abf77"


def blob_sha(path):
    p = subprocess.run(["git", "cat-file", "blob", f"{PRE}:{path}"], capture_output=True)
    if p.returncode != 0:
        return None
    return hashlib.sha256(p.stdout).hexdigest()


base = subprocess.run(["git", "cat-file", "blob", f"HEAD:{MANIFEST}"],
                      capture_output=True).stdout
lines = base.split(b"\r\n")
changed = []
for i in range(1, len(lines)):
    f = lines[i].split(b"\t")
    if len(f) < 2:
        continue
    good = blob_sha(f[0].decode())
    if good is None:
        continue
    if f[1].decode() != good:
        changed.append(f[0].decode())
        f[1] = good.encode()
        lines[i] = b"\t".join(f)
open(MANIFEST, "wb").write(b"\r\n".join(lines))
print(f"digest column corrected: {len(changed)} row(s)")
for p in changed:
    print(f"  {p}")
