#!/usr/bin/env python3
"""The batch structure that is ACTUALLY left, computed from the working tree.

rebase-plan.py answers "what must move together going PIN -> HEAD". Once batches have
landed that question is stale: 8 of BATCH 1's 23 files are already at HEAD and re-vendoring
them is a no-op. This classifies every vendored blob by WHICH upstream commit it currently
equals, and reports the remaining members of each batch the plan named.

The classification is by BLOB HASH against three upstream revisions, so it is content, not
assumption: pin, the last HEAD a batch was landed at, and the current HEAD.
"""
import json, subprocess as sp, sys
from pathlib import Path
REPO = Path(__file__).resolve().parents[2]
PIN = "6c3d401cf324"


def sh(*a):
  return sp.run(a, cwd=REPO, capture_output=True, text=True).stdout


def tree(c):
  out = {}
  for l in sh("git", "ls-tree", "-r", c, "tinygrad/").splitlines():
    m, p = l.split("\t", 1); out[p] = m.split()[2]
  return out


def ours():
  out = {}
  for l in sh("git", "ls-files", "-s", "tinygrad/").splitlines():
    m, p = l.split("\t", 1); out[p] = m.split()[1]
  return out


def main():
  head = sh("git", "rev-parse", "upstream/master").strip()
  hist = sh("git", "log", "--format=%H", "upstream/master").splitlines()[:120]
  trees = {c: tree(c) for c in hist}
  pin_tree = trees.get(PIN) or tree(PIN)
  ours_b = ours()
  state = {}
  for p, s in ours_b.items():
    if pin_tree.get(p) == s:
      # At the pin. Say nothing about WHICH commit -- a blob that has not changed since
      # the pin is present in the tree of every later commit too, so "the newest commit
      # whose tree holds this blob" is the newest commit, not the pin, and labelling a
      # pin file with it is how a first pass of this script reported 15 of BATCH 1 as
      # "at 19b70a955ca2" when six of them were sitting AT THE PIN the whole time.
      state[p] = "PIN"
    elif trees[head].get(p) == s:
      state[p] = "HEAD"
    else:
      at = next((c for c in hist if trees[c].get(p) == s), None)
      state[p] = "LOCAL" if at is None else f"OLD:{at[:12]}"
  plan = json.loads(sp.run(["python3", str(REPO / ".agents/slop/rebase-plan.py"), "--json"],
                           cwd=REPO, capture_output=True, text=True).stdout)
  print(f"  PIN {PIN[:12]}   HEAD {head[:12]}   working tree classified by blob hash\n")
  buckets = {}
  for p, s in state.items(): buckets.setdefault(s, []).append(p)
  for k in sorted(buckets, key=lambda k: -len(buckets[k])):
    print(f"  {k:<20} {len(buckets[k]):>3} files")
  print()
  for b in plan["batches"]:
    if b["size"] < 2: continue
    rem = [f for f in b["files"] if state.get(f) != "HEAD"]
    print(f"  BATCH {b['id']:<4} {len(rem)}/{b['size']} still to move")
    for f in b["files"]:
      tag = "HEAD" if state.get(f) == "HEAD" else state.get(f, "?")
      mark = "  " if tag == "HEAD" else "->"
      print(f"    {mark} [{tag:<20}] {f}")
    print()
  solo = [f for f in plan["independent"] if state.get(f) != "HEAD"]
  print(f"  INDEPENDENT SINGLETONS still to move: {len(solo)} of {len(plan['independent'])}")
  for f in solo: print(f"    [{state.get(f,'?'):<20}] {f}")
  stray = sorted(p for p, s in state.items() if s in ("LOCAL", "PIN") and p not in
                 set(sum([b["files"] for b in plan["batches"]], [])) | set(plan["independent"]))
  print(f"\n  AT PIN or LOCAL and in NO batch and NOT an independent singleton: {len(stray)}")
  for f in stray: print(f"    [{state.get(f,'?'):<20}] {f}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
