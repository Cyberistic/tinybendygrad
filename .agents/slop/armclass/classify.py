#!/usr/bin/env python3
"""classify.py -- ONE ROW PER ARMED PATH: shape x on-disk x in-HEAD x in-index x provably-wrong.

Reads the FROZEN census (idx.stage, head.tree) written at a named HEAD, plus the worktree.
The population is the gate's, not a second list of paths: this file names none.
"""
import subprocess, sys, os, hashlib
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
HERE = ROOT / ".agents/slop/armclass"
SNAP = sys.argv[2] if len(sys.argv) > 2 else ""   # "" -> idx.stage/head.tree, "2" -> the *2 pair
EMPTY = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
ENV = {k: v for k, v in os.environ.items()
       if k not in ("GIT_INDEX_FILE", "GIT_DIR", "GIT_WORK_TREE")}


def load(pfx, col):
    d = {}
    for line in (HERE / pfx).read_text().splitlines():
        meta, _, path = line.partition("\t")
        f = meta.split()
        if len(f) > col:
            d[path] = f[col]
    return d


# `ls-files --stage` -> "<mode> <sha> <stage>\t<path>": the SHA is f[1].
# `ls-tree -r`     -> "<mode> <type> <sha>\t<path>": the SHA is f[2]. Different columns, one mistake
# away from reading the stage number "0" as a blob id -- which is what this script did first.
idx = load(f"idx{SNAP}.stage", 1)
head = load(f"head{SNAP}.tree", 2)
rev = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                     text=True, env=ENV).stdout.strip()

disk = {}


def blob_sha(b: bytes) -> str:
    """git's blob id, computed here: sha1("blob <len>\\0" + content). Spawning `git hash-object`
    once per path is unusable on this tree right now -- another unit is running `git show` over
    HEAD for hundreds of revisions. VERIFIED against `git hash-object` output in main()."""
    return hashlib.sha1(b"blob %d\0" % len(b) + b).hexdigest()


def on_disk(p):
    if p in disk:
        return disk[p]
    f = ROOT / p
    if f.is_symlink() or f.is_dir() or not f.exists():
        disk[p] = (None, None)
    else:
        b = f.read_bytes()
        disk[p] = (len(b), blob_sha(b))
    return disk[p]


def why(shape, i, h, d):
    """Return PROVABLE-WRONG or UNDECIDABLE, with the reason as a command-checkable fact."""
    if shape == "DELETION":
        if d is None:
            return "UNDECIDABLE", "absent from disk too: index agrees with worktree, so no witness contradicts it"
        if i == EMPTY:
            return "UNDECIDABLE", "index holds the empty blob: that is INTENT, not a deletion"
        return "PROVABLE-WRONG", f"HEAD={h[:12]} and disk={d[:12]} both hold the path; index holds nothing"
    # STALE
    if d is None:
        return "UNDECIDABLE", f"absent from disk: HEAD={h[:12]} index={i[:12]}, worktree witnesses neither"
    if i == d:
        return "UNDECIDABLE", f"index==disk=={i[:12]}: a faithful staged change of unknown authorship"
    if i == EMPTY:
        return "PROVABLE-WRONG", f"index is the EMPTY blob; HEAD={h[:12]} disk={d[:12]}"
    return "PROVABLE-WRONG", f"index={i[:12]} exists in NO current witness; HEAD={h[:12]} disk={d[:12]}"


rows = []
for shape, pop in (("deletion", sorted(set(head) - set(idx))),
                   ("stale", sorted(p for p in set(idx) & set(head) if idx[p] != head[p])),
                   ("foreign", sorted(p for p in set(idx) - set(head) if idx[p] != EMPTY))):
    for p in pop:
        i, h = idx.get(p, "-none-"), head.get(p, "-none-")
        sz, d = on_disk(p)
        v, reason = why(shape, i, h, d)
        rows.append((shape, p, "yes" if sz is not None else "NO",
                     str(sz) if sz is not None else "-", h, i, d or "-", v, reason))

# the blob-id function above is the load-bearing assumption; prove it against the real tool
probe = ".agents/TODO.md"
want = subprocess.run(["git", "--no-optional-locks", "hash-object", "--", probe], cwd=ROOT,
                      capture_output=True, text=True, env=ENV).stdout.strip()
got = blob_sha((ROOT / probe).read_bytes())
print(f"# blob_sha selfcheck on {probe}: {got} == {want} -> {got == want}")
print(f"# HEAD {rev[:12]}  TREE {len(head)}  INDEX {len(idx)}  ARMED {len(rows)}")
print(f"# {'SHAPE':9} {'ON-DISK':7} {'SIZE':>7}  {'IN-HEAD':14} {'IN-INDEX':14} {'ON-DISK-BLOB':14} VERDICT")
for shape, p, od, sz, h, i, d, v, reason in sorted(rows, key=lambda r: (r[0], r[7], r[1])):
    print(f"{shape:9} {od:7} {sz:>7}  {h[:12]:14} {i[:12]:14} {d[:12]:14} {v:15} {p}")
print()
for shape, p, od, sz, h, i, d, v, reason in sorted(rows, key=lambda r: (r[0], r[7], r[1])):
    print(f"{v:15} {shape:9} {p}\n{'':17}-> {reason}")