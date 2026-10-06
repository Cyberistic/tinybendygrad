#!/usr/bin/env python
"""Restore the 13 instruments + their 7 deleted DEPENDENCIES to the paths they lived at.

A dependency is restored, not the claim: `git cat-file blob` must answer non-empty or the
row is REFUSED (doctrine 2). Reads only git; writes only the named paths under .agents/slop/.
"""
import csv
import hashlib
import os
import subprocess

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
os.chdir(ROOT)

DEPS = [
    ".agents/slop/loadwatch.py",
    ".agents/slop/oracle_py.py",
    ".agents/slop/patch_not_apply.py",
    ".agents/slop/revision-ledger.py",
    ".agents/slop/wire_parse.py",
    ".agents/slop/rebase-scan-oracles.py",
    ".agents/slop/rf2root/schedule/rf2_work.bend",
]


def git(*a):
    return subprocess.run(["git", *a], capture_output=True, text=True)


def newest_blob(path):
    """Newest commit ON THIS HISTORY whose tree still contains `path`, and its blob id.

    HEAD-relative, NOT `--all`: a sibling `portexec` branch carried a WIP-mutated
    `rf2_work.bend` (blob 089c10aacf44, where M1's subject was already inverted) and `--all`
    selected it. The subject must come from the history the instruments died in.
    """
    for c in git("log", "--format=%H", "--", path).stdout.split():
        if git("cat-file", "-e", f"{c}:{path}").returncode == 0:
            blob = git("rev-parse", f"{c}:{path}").stdout.strip()
            return blob, c
    return None, None


def restore(path, kind):
    blob, commit = newest_blob(path)
    if not blob:
        return dict(path=path, kind=kind, state="REFUSED-NO-BLOB", blob="", bytes="", commit="")
    data = subprocess.run(["git", "cat-file", "blob", blob], capture_output=True).stdout
    if not data:
        return dict(path=path, kind=kind, state="REFUSED-EMPTY", blob=blob, bytes="0", commit=commit)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return dict(path=path, kind=kind, state="RESTORED", blob=blob[:12],
                bytes=str(len(data)), commit=commit, sha256=hashlib.sha256(data).hexdigest()[:12])


rows = [restore(p, "DEP") for p in DEPS]
for r in csv.DictReader(open(".agents/slop/lostinst/INSTRUMENTS.tsv"), delimiter="\t"):
    if r["state"] == "RECOVERABLE" and os.path.splitext(r["path"])[1] in (".py", ".mjs", ".js", ".sh", ".bend"):
        rows.append(restore(r["path"], "INSTRUMENT"))

with open(".agents/slop/instrepair/RESTORED.tsv", "w") as f:
    f.write("path\tkind\tstate\tbytes\tblob\tcommit\tsha256\n")
    for r in rows:
        f.write("\t".join(r.get(k, "") for k in
                          ("path", "kind", "state", "bytes", "blob", "commit", "sha256")) + "\n")

for r in rows:
    print(f'{r["state"]:>16} {r.get("bytes","?"):>7}B {r.get("blob",""):>12} {r["path"]}')
