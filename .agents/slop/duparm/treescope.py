#!/usr/bin/env python3
"""Scope + cost of the COMMITTED-TREES population the proposed DUPLICATE arm would have to read.

READ-ONLY. Every git call carries `--no-optional-locks` and runs with GIT_INDEX_FILE scrubbed.
Writes only into `.agents/slop/duparm/`. No `.txt` anywhere.

Phase A (this file): how many DISTINCT ROOT TREES does each candidate population have, and how
long does it cost to ask? Phase B: `batchscan.py` reads the list this writes.
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


def git(*args: str) -> str:
    p = subprocess.run(["git", "--no-optional-locks", *args], capture_output=True, text=True,
                       env=ENV, check=True)
    return p.stdout


# Population candidates, named by GENERATOR (a rev-list / a log), never by hand.
SCOPES = (
    ("HEAD", ["log", "--format=%T", "HEAD"]),
    ("HEAD~1000", ["log", "--format=%T", "HEAD~1000"]),
    ("HEAD~100", ["log", "--format=%T", "HEAD~100"]),
    ("HEAD~10", ["log", "--format=%T", "HEAD~10"]),
)


def main() -> int:
    rows = [("scope", "commits", "distinct_trees", "seconds_to_enumerate")]
    for label, argv in SCOPES:
        t0 = time.perf_counter()
        try:
            out = git(*argv)
        except subprocess.CalledProcessError as e:
            print(f"SKIP {label}: {e.stderr.strip()}", file=sys.stderr)
            continue
        dt = time.perf_counter() - t0
        trees = sorted({ln.strip() for ln in out.splitlines() if ln.strip()})
        rows.append((label, str(len(out.splitlines())), str(len(trees)), f"{dt:.4f}"))
        if label == "HEAD":
            (HERE / "head-root-trees.rows").write_text("\n".join(trees) + "\n")
            print(f"HEAD distinct root trees -> {len(trees)} "
                  f"({len(trees) * 41} bytes of OIDs) enumerate in {dt:.3f}s")
    # header + rows, tab separated, and one .rows extension. Never .txt.
    with (HERE / "scopecost.rows").open("w") as f:
        f.write("\t".join(rows[0]) + "\n")
        for r in rows[1:]:
            f.write("\t".join(r) + "\n")
    print((HERE / "scopecost.rows").read_text())
    return 0


if __name__ == "__main__":
    sys.exit(main())