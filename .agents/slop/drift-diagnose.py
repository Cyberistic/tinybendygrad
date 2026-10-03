#!/usr/bin/env python3
"""drift-diagnose.py -- WHY does upstream-delta.py report what it reports?

upstream-delta.py answers "is this a hand edit?" with one loop that folds THREE
different states into one number:

  A. equal to the PIN                    -- untouched, the baseline
  B. equal to SOME OTHER upstream commit -- a landed re-vendor (correct, the goal)
  C. equal to NO upstream commit         -- a hand edit (the alarm)
  D. at a path upstream has NEVER had    -- not an edit at all, a vendored-in fork

D is folded into C: `landed_at()` compares `tree.get(p)` against our blob for every
commit in the window, and for a path upstream has never had `tree.get(p)` is None
forever, so the file is reported as a hand edit no matter what it contains. That is a
guaranteed false positive, not a coincidence.

Separately, the search for B and C is bounded to `depth=120` commits of upstream/master.
A blob that equals an upstream commit OLDER than that window is indistinguishable from
a hand edit, so the alarm's sensitivity depends on a constant nobody chose deliberately.

This prints the four buckets separately, per file, with the commit evidence.

  usage: python3 .agents/slop/drift-diagnose.py [--depth N] [--pin SHA]
"""
import subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
UPSTREAM = "upstream/master"
UPSTREAM_REVS = "--remotes=upstream"


def sh(*a):
  return subprocess.run(a, cwd=REPO, capture_output=True, text=True).stdout


def our_blobs():
  out = {}
  for line in sh("git", "ls-files", "-s", "tinygrad/").splitlines():
    meta, path = line.split("\t", 1)
    out[path] = meta.split()[1]
  return out


def tree_blobs(commit):
  out = {}
  for l in sh("git", "ls-tree", "-r", commit, "tinygrad/").splitlines():
    meta, path = l.split("\t", 1)
    out[path] = meta.split()[2]
  return out


def upstream_touched(path):
  """Commits in ANY upstream ref that changed `path`. Empty => upstream never had it."""
  return sh("git", "log", UPSTREAM_REVS, "--format=%H", "--", path).splitlines()


def blob_at(path):
  return sh("git", "rev-parse", f"HEAD:{path}").strip()


def main():
  depth, pin = 120, "6c3d401cf324"
  if "--depth" in sys.argv: depth = int(sys.argv[sys.argv.index("--depth") + 1])
  if "--pin" in sys.argv: pin = sys.argv[sys.argv.index("--pin") + 1]

  ours = our_blobs()
  hist = sh("git", "log", "--format=%H", UPSTREAM).splitlines()
  window = hist[:depth]
  trees = {c: tree_blobs(c) for c in window}
  pintree = tree_blobs(pin)

  at_pin, revend, handedit, localonly = [], [], [], []
  # for each state-C candidate, the FULL upstream history for that path, to decide
  # whether the alarm is real or an artefact of the window
  handedit_but_upstream_ever = []

  for p, s in sorted(ours.items()):
    if not upstream_touched(p):
      localonly.append(p); continue
    if pintree.get(p) == s:
      at_pin.append(p); continue
    seen = [c for c, t in trees.items() if t.get(p) == s]
    if seen:
      revend.append((p, seen[0]))
    else:
      handedit.append(p)
      # outside the window: is our blob at ANY commit in ANY upstream ref?
      hits = []
      for c in upstream_touched(p):
        if sh("git", "rev-parse", f"{c}:{p}").strip() == s: hits.append(c)
      if hits: handedit_but_upstream_ever.append((p, hits[0]))

  print(f"  upstream/master commits total  : {len(hist)}")
  print(f"  commits scanned for state B/C : {len(window)} (depth={depth})")
  print(f"  pin                           : {pin}")
  print(f"  our vendored files            : {len(ours)}")
  print()
  print(f"  A at pin                  {len(at_pin):>4}")
  print(f"  B re-vendored, in window   {len(revend):>4}")
  print(f"  C HAND EDIT, no upstream   {len(handedit):>4}")
  print(f"  D local-only path          {len(localonly):>4}")
  print(f"  C-but-actually-B-outside-window {len(handedit_but_upstream_ever):>4}"
        "   (alarm is a window artefact, not an edit)")
  print()
  if localonly:
    print("  D -- our path, upstream has NEVER had it in any ref: a vendored-in fork, NOT an edit")
    for p in localonly: print(f"    {p}")
    print("    upstream-delta.py counts these under HAND EDITS. It cannot do otherwise:")
    print("    tree.get(path) is None at every commit, so no content can ever match.")
  if handedit:
    print("  C -- upstream HAS the path; our blob equals no upstream commit:")
    for p in handedit: print(f"    {p}")
  if handedit_but_upstream_ever:
    print("  ...of which these DO match an upstream commit, just outside the scan window:")
    for p, c in handedit_but_upstream_ever: print(f"    {p}  <- {c[:12]}")
  return 0


if __name__ == "__main__":
  sys.exit(main())