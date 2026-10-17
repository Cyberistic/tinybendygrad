#!/usr/bin/env python3
"""Extend the duplicate-entry check from ROOT trees to EVERY tree reachable
from each of the 49 unpushed commits. Read-only; `git cat-file --batch`.

This closes (rather than merely declares) the root-only limit of audit.py.
Note --full-tree: `git ls-tree` is silently scoped to CWD's subdirectory
without it, which reads 2 rows instead of 8581.
"""
import os
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENTRY = re.compile(r"^(\d{6}) (\w+) ([0-9a-f]{40})\t(.*)$")


def run(args, stdin=None):
    env = dict(os.environ)
    env.pop("GIT_INDEX_FILE", None)
    # bytes: tree bodies carry arbitrary filename bytes, not UTF-8 text.
    return subprocess.run(["git"] + args, capture_output=True, input=stdin,
                          env=env, timeout=300)


shas = [l.strip() for l in (HERE / "range.sha.rows").read_text().splitlines() if l.strip()]

trees = set()
for s in shas:
    # The ROOT tree is never emitted by ls-tree (it lists entries INSIDE a
    # tree), so it must be asked for explicitly or the per-commit root is
    # unchecked -- which is exactly where the known corruption lives.
    trees.add(run(["rev-parse", f"{s}^{{tree}}"]).stdout.decode().strip())
    out = run(["ls-tree", "-r", "-t", "--full-tree", s]).stdout.decode("utf-8", "surrogateescape")
    for line in out.splitlines():
        f = line.split(None, 2)
        if len(f) == 3 and f[1] == "tree":
            trees.add(f[2].split("\t")[0])

trees = sorted(trees)
print(f"unique trees reachable from the {len(shas)} commits: {len(trees)}")

p = run(["cat-file", "--batch"], stdin=("\n".join(trees) + "\n").encode())
buf, pos, nbytes = p.stdout, 0, len(p.stdout)
dupes, badparse = [], 0
# --batch framing is BYTE-sized: "<oid> <type> <size>\n" + body + "\n".
# Slicing by line count silently desynchronises, so slice by bytes.
while pos < nbytes:
    nl = buf.find(b"\n", pos)
    if nl < 0:
        badparse += 1
        break
    m = re.match(rb"^([0-9a-f]{40}) (\w+) (\d+)$", buf[pos:nl])
    if not m:
        badparse += 1
        pos = nl + 1
        continue
    oid, typ, size = m.group(1).decode(), m.group(2).decode(), int(m.group(3))
    body = buf[nl + 1:nl + 1 + size]
    pos = nl + 1 + size + 1
    if typ != "tree" or len(body) != size:
        badparse += 1
        continue
    # RAW tree payload: repeated  "<mode> SP <name> NUL <20-byte oid>".
    # NOT the ls-tree text form, and not the cat-file -p form (which adds a
    # type word and a hex oid). Parsing the wrong one reports zero duplicates.
    names, off = [], 0
    while off < len(body):
        z = body.find(b"\0", off)
        if z < 0 or z + 21 > len(body):
            badparse += 1
            break
        names.append(body[off:z].split(b" ", 1)[1].decode("utf-8", "surrogateescape"))
        off = z + 21
    d = sorted({n for n in names if names.count(n) > 1})
    if d:
        dupes.append((oid, [(n, names.count(n)) for n in d]))

(HERE / "alldups.rows").write_text(
    "".join(f"{o}\t{d}\n" for o, d in dupes))
print(f"trees with DUPLICATE entries: {len(dupes)}")
for o, d in dupes:
    print(f"  DUP {o} {d}")
print(f"batch framing/parse anomalies: {badparse}")
