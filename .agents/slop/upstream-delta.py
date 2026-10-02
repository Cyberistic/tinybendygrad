#!/usr/bin/env python3
"""upstream-delta.py -- how far the port has drifted from tinygrad.

WHY THIS EXISTS. tinygrad/ is VENDORED into this repo with no history of its own and,
until this script, no recorded upstream commit. So "how far behind are we" was not merely
unrecorded, it was unanswerable: there was no pin to measure from. This finds the pin by
CONTENT (blob hash of every vendored file against upstream's tree, walking history back
until the match count peaks), then reports what has moved since.

  usage: python3 .agents/slop/upstream-delta.py [--fetch] [--json] [--files]

--fetch   git fetch upstream first
--json    machine-readable, for a gate
--files   list every changed file, not just the port-relevant ones

The number that matters is PORT-RELEVANT CHANGED: files upstream moved that we have a
committed port for. A changed file with no .bend costs nothing; a changed file WITH one is
an unexamined drift.
"""
import json, re, subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUR = "ours"          # vendored tree, tracked in this repo
UPSTREAM = "upstream/master"


def sh(*a, cwd=REPO):
  return subprocess.run(a, cwd=cwd, capture_output=True, text=True).stdout


def shf(*a, cwd=REPO):
  r = subprocess.run(a, cwd=cwd, capture_output=True, text=True)
  return r.stdout if r.returncode == 0 else ""


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


def find_pin(depth=400):
  """The upstream commit whose tinygrad/ tree best matches our vendored copy.

  A perfect match is not expected and is not required: we may have carried one local edit,
  so the pin is the BEST match and the count is reported rather than assumed to be 100%.
  """
  ours = our_blobs()
  hist = sh("git", "log", "--format=%H", UPSTREAM).splitlines()[:depth]
  best = (None, 0, None)
  for sha in hist:
    tree = tree_blobs(sha)
    m = sum(1 for p, s in ours.items() if tree.get(p) == s)
    if m > best[1]:
      best = (sha, m, tree)
    if m == len(ours):
      break
  return best[0], best[1], len(ours), best[2]


def port_for(py):
  b = REPO / "tinybendygrad" / (py[len("tinygrad/"):]).replace(".py", ".bend")
  return b if b.exists() else None


def main():
  if "--fetch" in sys.argv:
    print(sh("git", "fetch", "upstream", "--quiet").strip() or "fetched upstream")
  pin, matched, total, pin_tree = find_pin()
  head = sh("git", "rev-parse", UPSTREAM).strip()
  pin_date = sh("git", "log", "-1", "--format=%ad", "--date=short", pin).strip()
  head_date = sh("git", "log", "-1", "--format=%ad", "--date=short", head).strip()
  behind = sh("git", "rev-list", "--count", f"{pin}..{head}").strip() or "?"
  changed = sh("git", "diff", "--name-only", pin, head).splitlines()
  tg = [f for f in changed if f.startswith("tinygrad/")]

  # which vendored files are NOT at the pin -- a local edit, or a stale vendored file
  ours = our_blobs()
  local = [p for p, s in ours.items() if pin_tree and pin_tree.get(p) != s]

  relevant = []
  for f in tg:
    b = port_for(f)
    if b:
      st = sh("git", "diff", "--numstat", pin, head, "--", f).split()
      relevant.append({"py": f, "bend": str(b.relative_to(REPO)),
                       "bend_lines": len(b.read_text().splitlines()),
                       "added": st[0] if st else "?", "removed": st[1] if len(st) > 1 else "?"})
  added = [f for f in sh("git", "diff", "--diff-filter=A", "--name-only", pin, head, "--", "tinygrad/*.py").splitlines()]

  res = {"pin": pin, "pin_date": pin_date, "pin_match": f"{matched}/{total}",
         "local_diffs": local, "upstream_head": head, "head_date": head_date,
         "commits_behind": behind, "files_changed": len(changed),
         "tinygrad_files": len(tg), "port_relevant": len(relevant),
         "new_upstream_py": added, "detail": relevant}

  if "--json" in sys.argv:
    print(json.dumps(res, indent=2)); return 0

  print(f"  PIN      {pin[:12]}  {pin_date}   (our vendored tinygrad matches {matched}/{total} files)")
  print(f"  UPSTREAM {head[:12]}  {head_date}")
  print(f"  BEHIND   {behind} commits, {len(changed)} files changed, {len(tg)} under tinygrad/")
  if local:
    print(f"  LOCAL EDITS not from upstream ({len(local)}): {', '.join(local[:4])}")
  print(f"  PORT-RELEVANT CHANGED: {len(relevant)} of our ports have moved under us")
  if added:
    print(f"  NEW upstream .py files ({len(added)}), each needs a scope decision:")
    for a in added: print(f"    + {a}")
  print()
  for r in sorted(relevant, key=lambda r: -int(r["added"] if r["added"].isdigit() else 0)):
    print(f"  {r['py']:<44} +{r['added']:<5} -{r['removed']:<5} port={r['bend']} ({r['bend_lines']} lines)")
  if "--files" in sys.argv:
    print("\n  ALL changed files:")
    for f in changed: print(f"    {f}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
