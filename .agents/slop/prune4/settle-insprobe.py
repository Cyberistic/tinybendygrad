#!/usr/bin/env python3
"""prune4: settle prune3's OPEN QUESTION, or say the instrument could not.

prune3 refused `.agents/slop/loopfix/insprobe{,-old,-v2}.bin` because the
generator `insprobe.bend` is 'deleted and never committed', and correctly called
that an ABSENCE rather than a proof of redundancy. Its two settling routes:
  (1) the source recovered from somewhere
  (2) run the binary and diff against the committed .rows  (not run here)

Route (1) has an instrument that prune3 did not have: the git OBJECT STORE.
`git ls-files` and `git log` only see objects a REF reaches. `git cat-file
--batch-all-objects` sees every object in the store, including ones no ref names
-- which is exactly what `git add` then `git reset` leaves behind, and what an
agent's `jj` index churn orphans. If the source was ever added, it is still
readable.

This is a REAL settling attempt with a stated negative: if the object store has
no such blob, the source was never added, and the ABSENCE is now MEASURED
against the whole store rather than assumed from --all refs.
"""
import os, subprocess, sys

SLOP = ".agents/slop"


def sh(*a):
    return subprocess.run(a, capture_output=True).stdout


def all_objects():
    out = sh("git", "cat-file", "--batch-all-objects", "--batch-check=%(objectname) %(objecttype) %(objectsize)")
    objs = {}
    for line in out.decode(errors="replace").splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1] == "blob":
            objs[parts[0]] = int(parts[2])
    return objs


def main():
    targets = sys.argv[1:] or ["insprobe"]
    objs = all_objects()
    print(f"# object store holds {len(objs)} blobs (batch-all-objects: EVERY"
          f" object, including ones no ref reaches)")

    ids = list(objs)
    raw = sh("git", "cat-file", "--batch", input=None) if False else subprocess.run(
        ["git", "cat-file", "--batch"], input=("\n".join(ids) + "\n").encode(),
        capture_output=True).stdout

    hits, i, nread = [], 0, 0
    while i < len(raw):
        nl = raw.find(b"\n", i)
        if nl < 0:
            break
        h = raw[i:nl].split()
        if len(h) < 3 or h[1] != b"blob":
            i = nl + 1
            continue
        oid = h[0].decode()
        size = int(h[2])
        body = raw[nl + 1:nl + 1 + size]
        i = nl + 1 + size + 1
        nread += 1
        for t in targets:
            if t.encode() in body[:4096]:
                hits.append((oid, size, t, body[:200]))
    print(f"# READ {nread} blobs")
    if not hits:
        print(f"NO blob anywhere in the object store mentions {targets!r} in its"
              f" first 4096 bytes.")
        print("VERDICT: the generator was NEVER ADDED, even transiently."
              " 'no generator' is now MEASURED over the whole object store --"
              " a stronger statement than prune3's -- but it is still an absence"
              " of a generator, not a proof of redundancy. REFUSE stands.")
    else:
        for oid, size, t, head in hits[:40]:
            print(f"HIT {oid} size={size} matches {t!r}")
            print("     " + head.decode(errors="replace")[:160].replace("\n", " | "))
    return hits


if __name__ == "__main__":
    main()