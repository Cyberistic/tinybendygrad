#!/usr/bin/env python3
"""Phase B: the proposed arm's actual cost, MEASURED, over the population it would have to read.

A duplicate tree entry is only visible by reading a tree object's OWN entry list. `git ls-tree`
refuses to tell you: it prints the duplicated paths and exits 0 (MEASURED -- recorded in
review.md). So an arm must read tree objects. This measures what that costs, over the
GENERATOR's population (`head-root-trees.rows`, written by treescope.py -- `git log --format=%T
HEAD`, not a hand list).

READ-ONLY, writes only into `.agents/slop/duparm/`, and the extension is `.rows` because these
are row dumps. Never `.txt`.
"""
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REDIRECTS = ("GIT_INDEX_FILE", "GIT_DIR", "GIT_WORK_TREE", "GIT_OBJECT_DIRECTORY",
             "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_NAMESPACE")
ENV = {k: v for k, v in os.environ.items() if k not in REDIRECTS}


def git_bytes(*args: str, input: bytes = b"") -> bytes:
    return subprocess.run(["git", "--no-optional-locks", *args], input=input,
                          capture_output=True, env=ENV, check=True).stdout


def scan(oids: list[str]) -> tuple[list[tuple[str, list[tuple[bytes, int]]]], float, int]:
    """Feed OIDs to ONE `git cat-file --batch` and flag any tree whose entry names repeat.

    `communicate`, not a hand-rolled write-then-read loop: writing 16024 OIDs (657 KB) into a
    64 KB stdin pipe while nothing is draining stdout DEADLOCKS -- which is what this file's
    first version did, and what a 120 s timeout then misreported as "git is slow".
    """
    payload = ("\n".join(oids) + "\n").encode()
    t0 = time.perf_counter()
    data = git_bytes("cat-file", "--batch", input=payload)
    dt = time.perf_counter() - t0
    bad: list[tuple[str, list[tuple[bytes, int]]]] = []
    i = 0
    n_total = len(data)
    while i < n_total:
        nl = data.index(b"\n", i)
        oid, kind, size = data[i:nl].split()
        i = nl + 1
        n = int(size)
        body = data[i:i + n]
        i += n + 1  # git writes one newline after the object body
        if kind != b"tree":
            continue
        names: dict[bytes, int] = {}
        j = 0
        while j < n:
            sp = body.index(b" ", j)
            nul = body.index(b"\0", sp)
            name = body[sp + 1:nul]
            names[name] = names.get(name, 0) + 1
            j = nul + 1 + 20  # NUL, then the RAW 20-byte object name -- not text
        dups = sorted((k, v) for k, v in names.items() if v > 1)
        if dups:
            bad.append((oid.decode(), dups))
    return bad, dt, n_total


def main() -> int:
    oids = [ln.strip() for ln in (HERE / "head-root-trees.rows").read_text().splitlines() if ln.strip()]
    bad, dt, nbytes = scan(oids)
    # WHICH commits carry each malformed root tree, by the generator, not by a hand list.
    commits_of: dict[str, list[str]] = {}
    for sha, tree in (ln.split() for ln in
                      git_bytes("log", "--format=%H %T", "HEAD").decode().splitlines() if ln.strip()):
        if tree in {oid for oid, _ in bad}:
            commits_of.setdefault(tree, []).append(sha)
    with (HERE / "batchscan.rows").open("w") as f:
        f.write("root_trees_read\tmalformed_trees\tcollisions\tmax_mult\tseconds\tout_bytes\n")
        f.write(f"{len(oids)}\t{len(bad)}\t"
                f"{sum(v - 1 for _, d in bad for _, v in d)}\t"
                f"{max([v for _, d in bad for _, v in d], default=0)}\t{dt:.3f}\t{nbytes}\n")
        for oid, dups in bad:
            names = ",".join(f"{k.decode('utf-8', 'replace')}x{v}" for k, v in dups)
            f.write(f"{oid}\t{','.join(commits_of.get(oid, ['-'])[:5])}\t{names}\n")
    print((HERE / "batchscan.rows").read_text())
    print(f"per-tree cost = {dt / max(len(oids), 1) * 1000:.4f} ms/tree; "
          f"whole-history = {dt:.3f}s over {len(oids)} distinct root trees")
    return 0


if __name__ == "__main__":
    sys.exit(main())