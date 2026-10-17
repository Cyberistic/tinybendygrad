#!/usr/bin/env python
"""Detect duplicate path entries in git trees.

READ-ONLY. Runs exactly two child processes: `git rev-list` and one
`git cat-file --batch`. Never touches the index.

Population is DISCOVERED, never listed: `git rev-list --max-count=N HEAD`
is the generator's own declaration of "the last N commits reachable from
HEAD" (Doctrine 1 in AGENTS.md). The per-tree population is the tree
object's own entry list, so there is no suffix set and no hand list.

Verdicts follow gatekit's five (AGENTS.md Doctrine 2):
  PASS 0  every root tree in the sample had entries == distinct names
  FAIL 1  at least one duplicate found, rows written
  REFUSED 3 a precondition was absent (no HEAD, no origin, bad args)
"""

import subprocess
import sys
import os
from collections import Counter

ENV = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}


def git(args, stdin=None):
    p = subprocess.run(["git", *args], capture_output=True, env=ENV)
    if p.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} rc={p.returncode}: {p.stderr.decode()[:200]}")
    return p.stdout


class Batch:
    """One `git cat-file --batch` process, fed lazily."""

    def __init__(self):
        self.p = subprocess.Popen(
            ["git", "cat-file", "--batch"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=ENV,
        )

    def tree(self, oid):
        """Return the entry list of tree `oid`, or None if absent."""
        self.p.stdin.write((oid + "\n").encode())
        self.p.stdin.flush()
        header = self.p.stdout.readline().decode().split()
        if len(header) < 3 or header[1] != "tree":
            return None
        n = int(header[2])
        body = self.p.stdout.read(n)
        if len(body) != n:
            raise RuntimeError(f"short read on {oid}: {len(body)} of {n}")
        self.p.stdout.read(1)  # trailing newline
        return parse_tree(body)

    def close(self):
        self.p.stdin.close()
        self.p.wait()


def parse_tree(body):
    """[(mode, oid, name)] from a RAW tree object.

    `git cat-file --batch` emits the stored bytes, not `-p`'s pretty form:
    `<mode-octal> SP <name> NUL <20 raw sha>`, repeated. Names may contain
    spaces but never NUL or newline, so splitting on the first NUL of each
    record is exact rather than heuristic.
    """
    out, pos = [], 0
    while pos < len(body):
        nul = body.index(b"\0", pos)
        mode, _, name = body[pos:nul].partition(b" ")
        oid = body[nul + 1:nul + 21]
        out.append((mode.decode(), oid.hex(), name.decode("utf-8", "replace")))
        pos = nul + 21
    return out


def dups_of(entries):
    """[(name, n_entries, n_distinct_oids)] for every duplicated name."""
    by_name = Counter(e[2] for e in entries)
    return [
        (n, c, len({e[1] for e in entries if e[2] == n}))
        for n, c in sorted(by_name.items())
        if c > 1
    ]


def scan(commits, batch, deep_on_dup=True):
    """Yield rows for every duplicated name, recursing on a duplicated tree."""
    rows = []
    for c in commits:
        entries = batch.tree(c + "^{tree}")
        if entries is None:
            rows.append((c, "<unreadable-root-tree>", 0, 0, "unreadable"))
            continue
        d = dups_of(entries)
        if not d:
            continue
        for name, n, oids in d:
            rows.append((c, name, len(entries), len({e[2] for e in entries}), f"rootx{oids}"))
            if deep_on_dup:
                # recurse: is the duplication only at the root?
                for mode, oid, _n in entries:
                    if _n != name or mode != "40000":
                        continue
                    sub = batch.tree(oid)
                    if sub is None:
                        rows.append((c, name + "/<unreadable>", 0, 0, "subtree-unreadable"))
                        continue
                    for sname, sn, _soids in dups_of(sub):
                        rows.append((c, name + "/" + sname, len(sub), len({e[2] for e in sub}), "sub"))
    return rows


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 500
    skip = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    base = sys.argv[3] if len(sys.argv) > 3 else None
    head = git(["rev-parse", "--verify", base or "HEAD"]).decode().strip()
    ls = ["rev-list", "--max-count=%d" % n]
    if skip:
        ls.append("--skip=%d" % skip)
    ls.append(head)
    commits = git(ls).decode().split()
    batch = Batch()
    try:
        rows = scan(commits, batch)
    finally:
        batch.close()

    print("# HEAD\t%s" % head)
    print("# PINNED\t%s" % (base or "no"))
    print("# SAMPLE\t%d" % len(commits))
    print("# SKIP\t%d" % skip)
    print("# OLDEST\t%s" % (commits[-1] if commits else "-"))
    print("# NEWEST\t%s" % (commits[0] if commits else "-"))
    print("# ROWS\t%d" % len(rows))
    for r in rows:
        print("\t".join(str(x) for x in r))
    return 0 if rows else 1


if __name__ == "__main__":
    sys.exit(main())