#!/usr/bin/env python3
"""THE CLONE ARITHMETIC, computed rather than argued.

Three digests over the SAME commit, all by the generator's own rule
(`for rel, blob in sorted(entries): h.update(rel); h.update(b"\\0"); h.update(blob); h.update(b"\\0")`):

  worktree   `differ.substrate_digest()` -- bytes read from disk. What the gate writes.
  head       the population of the COMMIT, blob bytes from `git cat-file`. Never written today.
  worktree-1-edit  the worktree population with ONE tracked file's bytes replaced, i.e. what a
             single uncommitted edit does to the digest. Nothing on disk is touched to compute it.

Read-only. One `git cat-file --batch` for the HEAD side.
"""
import hashlib
import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("differ", ROOT / "checks/differ.py")
differ = importlib.util.module_from_spec(spec)
spec.loader.exec_module(differ)


def digest_of(entries) -> str:
    h = hashlib.sha256()
    for rel, blob in sorted(entries):
        h.update(rel.encode()); h.update(b"\0"); h.update(blob.encode()); h.update(b"\0")
    return h.hexdigest()


def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


live = differ.substrate_entries()
live_digest = digest_of(live)

# ---- the commit's own population -------------------------------------------------------
def ls_tree(paths) -> dict[str, str]:
    ls = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--format=%(objectname) %(path)", "--"] + paths,
                        cwd=ROOT, capture_output=True, text=True, check=True).stdout.split("\n")
    d = {}
    for ln in ls:
        if ln.strip():
            oid, _, rel = ln.partition(" ")
            d[rel] = oid
    return d


def blobs(oids) -> dict[str, bytes]:
    """ONE `git cat-file --batch`, because 373 subprocesses is a saturation problem, not a style."""
    p = subprocess.Popen(["git", "cat-file", "--batch"], cwd=ROOT,
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    p.stdin.write(("\n".join(oids) + "\n").encode())
    p.stdin.flush()
    p.stdin.close()
    out = {}
    for oid in oids:
        hdr = p.stdout.readline().split()
        n = int(hdr[2])
        out[oid] = p.stdout.read(n)
        p.stdout.read(1)
    p.stdout.read()
    p.wait()
    return out


walks = list(differ.SUBSTRATE_WALKS)
head = ls_tree(walks)
name_head = ls_tree(list(differ.SUBSTRATE_INPUTS))
want = sorted(set(head.values()) | set(name_head.values()))
raw = blobs(want)
head_entries = [(rel, sha256(raw[head[rel]])) for rel in sorted(head)]
# the named inputs: a clone has the TRACKED ones and ABSENT for the rest, by differ's own rule
for rel in differ.SUBSTRATE_INPUTS:
    head_entries.append((rel, sha256(raw[name_head[rel]]) if rel in name_head else "ABSENT"))
head_digest = digest_of(head_entries)

# ---- one tracked file edited in the worktree -------------------------------------------
victim = "tinybendygrad/LAWS.bend"
alt = [(r, sha256(b"") if r == victim else b) for r, b in live]
edited_digest = digest_of(alt)

live_map = dict(live)
# the COMMIT's paths only: a synthesised "ABSENT" row is not a commit member, it is the clone's
# reading of a path the commit does not have, and conflating the two miscounts the divergence.
head_map = {r: b for r, b in head_entries if b != "ABSENT"}
absent_at_head = sorted(r for r, b in head_entries if b == "ABSENT")
only_live = sorted(set(live_map) - set(head_map))
only_head = sorted(set(head_map) - set(live_map))
changed = sorted(r for r in set(live_map) & set(head_map) if live_map[r] != head_map[r])

print(f"# entries: worktree {len(live)}; head {len(head_entries)}")
print(f"# present-in-worktree-not-in-commit {len(only_live)}; present-in-commit-not-in-worktree {len(only_head)}; "
      f"in both but DIFFERENT bytes {len(changed)}; named inputs the commit does not have "
      f"{len(absent_at_head)} ({', '.join(absent_at_head) or 'none'})")
for r in only_live:
    print(f"worktree-only\t{r}")
for r in changed:
    print(f"different-bytes\t{r}")
print(f"digest\tworktree\t{live_digest}")
print(f"digest\thead\t{head_digest}")
print(f"digest\tworktree-minus-one-edit({victim})\t{edited_digest}")
print(f"# worktree == head ? {live_digest == head_digest}")
print(f"# one edit moves the digest ? {edited_digest != live_digest} (victim present on disk: {(ROOT / victim).is_file()})")
sys.exit(0)