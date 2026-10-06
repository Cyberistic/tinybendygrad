#!/usr/bin/env python
"""Classify a candidate directory file-by-file against HEAD:
  COMMITTED_EQUAL  working file byte-equal to HEAD at its OWN repo path -> git has the blob, copy is redundant
  COMMITTED_MOD    HEAD has the path but bytes differ                    -> working copy is a local edit
  COPY_OF_OTHER    no HEAD at own path, but a path-suffix matches a HEAD blob byte-for-byte
  NO_HEAD          nothing in HEAD answers it (only record is this file)
Loads HEAD once. Emits .rows. Python only."""
import os, sys, subprocess, hashlib

ROOT = ".agents/slop"
REPO = "."


def load_head():
    r = subprocess.run(["git", "ls-tree", "-r", "-z", "HEAD"], capture_output=True)
    blobs = {}
    for rec in r.stdout.split(b"\0"):
        if not rec:
            continue
        meta, path = rec.split(b"\t", 1)
        mode, typ, sha = meta.split(b" ")
        if typ == b"blob":
            blobs[path.decode()] = sha.hex()
    return blobs


def file_sha(fp):
    h = hashlib.sha256()
    with open(fp, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def analyse(cand, blobs):
    counts = dict(COMMITTED_EQUAL=0, COMMITTED_MOD=0, COPY_OF_OTHER=0, NO_HEAD=0)
    bytes_ce = 0
    bad = []
    for dp, dn, fn in os.walk(cand):
        for f in fn:
            fp = os.path.join(dp, f)
            if os.path.islink(fp):
                continue
            repo = os.path.relpath(fp, REPO)
            if repo in blobs:
                if file_sha(fp) == blobs[repo]:
                    counts["COMMITTED_EQUAL"] += 1
                    bytes_ce += os.path.getsize(fp)
                else:
                    counts["COMMITTED_MOD"] += 1
                    if len(bad) < 3:
                        bad.append(repo)
                continue
            rel = os.path.relpath(fp, cand).split(os.sep)
            hit = next(("/".join(rel[i:]) for i in range(len(rel))
                        if "/".join(rel[i:]) in blobs), None)
            if hit and file_sha(fp) == blobs[hit]:
                counts["COPY_OF_OTHER"] += 1
            else:
                counts["NO_HEAD"] += 1
    return counts, bytes_ce, bad


def main():
    blobs = load_head()
    print(f"# HEAD blobs: {len(blobs)}")
    print("dir\tCOMMITTED_EQUAL\tCOMMITTED_MOD\tCOPY_OF_OTHER\tNO_HEAD\teq_bytes\texamples_mod")
    for cand in sys.argv[1:]:
        p = os.path.join(ROOT, cand)
        if not os.path.isdir(p):
            continue
        c, beq, bad = analyse(p, blobs)
        print(f"{cand}\t{c['COMMITTED_EQUAL']}\t{c['COMMITTED_MOD']}\t{c['COPY_OF_OTHER']}\t{c['NO_HEAD']}\t{beq}\t{';'.join(bad)}")


if __name__ == "__main__":
    main()
