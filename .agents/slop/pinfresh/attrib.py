#!/usr/bin/env python3
"""WHICH TREE DID THE 02:51Z RUN SEE? Reconstruct the fold from a COMMIT and compare.

The run left two numbers and no per-member record, so the members it saw cannot be listed. What
CAN be decided: the digest is a fold over `(relpath, sha256(bytes))`, so if a commit's tree folds to
the recorded digest, that commit IS the substrate the run measured -- one witness, not a guess.

`git cat-file --batch` is READ-ONLY and streams every blob in one process; `GIT_INDEX_FILE` is
unset so an armed index cannot answer, and a path absent from the commit folds as `ABSENT`, which
is the same token `differ.substrate_entries()` uses for an absent file.
"""

from __future__ import annotations

import hashlib
import importlib.util
import os
import pathlib
import subprocess
import sys
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[3]
ENV = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}


def git(*args: str, binary: bool = False):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, env=ENV,
                          timeout=20).stdout if binary else subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, env=ENV, timeout=20).stdout


def fold(entries) -> str:
    h = hashlib.sha256()
    for rel, blob in sorted(entries):
        h.update(rel.encode())
        h.update(b"\0")
        h.update(blob.encode())
        h.update(b"\0")
    return h.hexdigest()


def blob_shas(commit: str) -> dict[str, str]:
    out = git("ls-tree", "-r", commit, "-z")
    got = {}
    for rec in out.split("\0"):
        if not rec:
            continue
        meta, _, path = rec.partition("\t")
        parts = meta.split()
        if len(parts) == 3 and parts[1] == "blob":
            got[path] = parts[2]
    return got


def shas_of(want: list[str], shas: dict[str, str]) -> dict[str, str]:
    """sha256 over CONTENT for every path in ONE `git cat-file --batch`, in the order asked for.

    ONE PROCESS FOR ALL MEMBERS: `git cat-file --batch` is line-addressed, so the response of
    request i follows request i and a single stdin stream answers the whole population. A path the
    commit does not carry is not asked for: its caller folds it as `ABSENT`, which is also what a
    declaration that is not on disk contributes, so an untracked input reads as absent rather than
    as a crash. That is a MODEL, and the report says which inputs it cannot reconstruct.
    """
    want = [p for p in want if p in shas]
    if not want:
        return {}
    res = subprocess.run(["git", "cat-file", "--batch"], cwd=ROOT,
                         input="".join(f"{shas[p]}\n" for p in want).encode(),
                         capture_output=True, env=ENV, timeout=20)
    data, i, got = res.stdout, 0, {}
    for _ in want:
        nl = data.index(b"\n", i)
        size = int(data[i:nl].split()[2])
        got[_] = hashlib.sha256(data[nl + 1:nl + 1 + size]).hexdigest()
        i = nl + 1 + size + 1
    return got


def main() -> int:
    spec = importlib.util.spec_from_file_location("differ_writer", ROOT / "checks/differ.py")
    w = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(w)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    live = sorted(w.substrate_entries())
    targets = {"9528bb5e2489ad69fd3b3f99d7bd149e0548bace934560636f40fcf7ffb3191f": "run-02:51Z-start/end",
               "a842e8323cbebc391833efa9c76d15bb3822ec4355f6050fbaeb9f53a691df64": "live-17:28Z"}
    rows = [("live", w.substrate_digest(), len(live))]
    for rev in ("4b42c0ccf7e53bb140680a19bbcdaddad2f02bf4", "1af4ba921", "3001661a7"):
        full = git("rev-parse", rev).strip()
        date = git("log", "-1", "--format=%cI", full).strip()
        shas = blob_shas(full)
        paths = [rel for rel, _ in live]
        content = shas_of(paths, shas)
        entries = [(rel, content.get(rel, "ABSENT")) for rel in paths]
        got = fold(entries)
        hit = targets.get(got, "")
        rows.append((f"{rev[:9]} {date}", got, f"{len(entries)} members {hit}"))

    for name, val, note in rows:
        print(f"{name}\t{val}\t{note}")
    print("# read at", now, "HEAD", git("rev-parse", "HEAD").strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())