#!/usr/bin/env python3
"""The census an arm would ACTUALLY have to do to be complete: every TREE object, not just root trees.

`git fsck` already answers the question (MEASURED: 3 malformed trees in this object database, and
only ONE of them is a root tree). This measures what a hand-rolled arm costs to reach the same
answer, so the comparison against fsck is like for like.

CHUNKED on purpose: 105083 trees in one `communicate` would hold ~100 MB of object bytes in RAM.
10k per chunk keeps this file inside the 150 MB budget the unit runs under.

READ-ONLY. Writes only into `.agents/slop/duparm/`.
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
CHUNK = 10_000


def tree_oids() -> list[str]:
    out = subprocess.run(
        ["git", "--no-optional-locks", "cat-file", "--batch-all-objects",
         "--batch-check=%(objectname) %(objecttype)"],
        capture_output=True, text=True, env=ENV, check=True).stdout
    return [ln.split()[0] for ln in out.splitlines() if ln.endswith(" tree")]


def dup_names(body: bytes) -> list[tuple[bytes, int]]:
    names: dict[bytes, int] = {}
    j = 0
    while j < len(body):
        sp = body.index(b" ", j)
        nul = body.index(b"\0", sp)
        name = body[sp + 1:nul]
        names[name] = names.get(name, 0) + 1
        j = nul + 1 + 20  # NUL, then the RAW 20-byte object name
    return sorted((k, v) for k, v in names.items() if v > 1)


def main() -> int:
    t0 = time.perf_counter()
    oids = tree_oids()
    t_enum = time.perf_counter() - t0
    found: list[tuple[str, list[tuple[bytes, int]]]] = []
    t0 = time.perf_counter()
    for i in range(0, len(oids), CHUNK):
        part = oids[i:i + CHUNK]
        data = subprocess.run(["git", "--no-optional-locks", "cat-file", "--batch"],
                              input=("\n".join(part) + "\n").encode(),
                              capture_output=True, env=ENV, check=True).stdout
        j = 0
        while j < len(data):
            nl = data.index(b"\n", j)
            oid, _kind, size = data[j:nl].split()
            j = nl + 1
            n = int(size)
            body = data[j:j + n]
            j += n + 1
            d = dup_names(body)
            if d:
                found.append((oid.decode(), d))
    dt = time.perf_counter() - t0
    with (HERE / "fullcensus.rows").open("w") as f:
        f.write("trees_scanned\tmalformed\tenumerate_s\tscan_s\tper_tree_ms\n")
        f.write(f"{len(oids)}\t{len(found)}\t{t_enum:.3f}\t{dt:.3f}\t"
                f"{dt / max(len(oids), 1) * 1000:.4f}\n")
        for oid, d in found:
            f.write(oid + "\t" + ",".join(f"{k.decode('utf-8', 'replace')}x{v}" for k, v in d) + "\n")
    print((HERE / "fullcensus.rows").read_text())
    return 0


if __name__ == "__main__":
    sys.exit(main())