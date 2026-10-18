#!/usr/bin/env python3
"""`git ls-tree -r HEAD` vs the WORKING COPY, over the digest's own population.

The claim under test is "the digest is a function of the working copy, not of a commit".
The cheapest non-mutating proof is to ask, for every file `substrate_digest()` hashes,
whether the bytes on disk are the bytes HEAD names. Where they are not, the digest at
THIS HEAD already differs from the digest a tree-object reader would compute, with no
edit made by this script.

Blob id is git's own: sha1(b"blob <len>\\0" + content). Read-only; no index is touched.
"""
import hashlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def blob_oid(p: Path) -> str:
    b = p.read_bytes()
    return hashlib.sha1(b"blob %d\0" % len(b) + b).hexdigest()


def head_oids(paths) -> dict[str, str]:
    out = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--"] + sorted(paths),
                         cwd=ROOT, capture_output=True, text=True, check=True).stdout
    d = {}
    for ln in out.splitlines():
        meta, _, path = ln.partition("\t")
        _, _, oid = meta.split()
        d[path] = oid
    return d


walks = ["tinybendygrad", "tinygrad"]
disk = sorted(p.relative_to(ROOT).as_posix()
              for w in walks for p in (ROOT / w).rglob("*")
              if p.is_file() and "__pycache__" not in p.parts)
head = head_oids(disk)
print(f"# population on disk {len(disk)}; present in HEAD {len(head)}; "
      f"on disk and NOT in HEAD {len(disk) - len(head)}")
print(f"# tracked-and-identical {sum(1 for r in disk if r in head and blob_oid(ROOT / r) == head[r])}")
diff = [r for r in disk if r in head and blob_oid(ROOT / r) != head[r]]
print(f"# tracked-and-DIFFERENT {len(diff)}")
for r in diff:
    print(f"differs\t{r}\thead={head[r][:12]}\tworktree={blob_oid(ROOT / r)[:12]}")
absent = [r for r in disk if r not in head]
for r in absent:
    print(f"untracked\t{r}\thead=ABSENT\tworktree={blob_oid(ROOT / r)[:12]}")
sys.exit(0)