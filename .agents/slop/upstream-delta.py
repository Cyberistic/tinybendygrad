#!/usr/bin/env python3
"""upstream-delta.py -- how far the port has drifted from tinygrad.

WHY THIS EXISTS. tinygrad/ is VENDORED into this repo with no history of its own and,
until this script, no recorded upstream commit. So "how far behind are we" was not merely
unrecorded, it was unanswerable: there was no pin to measure from. This finds the pin by
CONTENT (blob hash of every vendored file against upstream's tree, walking history back
until the match count peaks), then reports what has moved since.

  usage: python3 .agents/slop/upstream-delta.py [--fetch] [--json] [--files] [--worktree]

--fetch      git fetch upstream first
--json       machine-readable, for a gate
--files      list every changed file, not just the port-relevant ones
--worktree   also hash the files on DISK, not only the index (see below)

THE PIN IS DERIVED, NOT STORED. Every run re-finds it and prints it, so there is no second
place to update and no way for the recorded pin and the measured pin to disagree.

FOUR STATES, NOT TWO. The first version of this script compared each of our blobs against
a window of upstream commits and reported "hand edit" for everything that missed. That
folds three different states into one number, and two of the three are not edits:

  A  at pin                  untouched baseline
  B  re-vendored             equals SOME upstream commit -- a batch landed, the goal
  C  HAND EDIT               upstream has this path; our blob is at NO upstream commit
  D  local-only path         upstream has NEVER had this path -- a vendored-in fork

Only C is an alarm. D cannot ever be C: for a path upstream has never had,
`tree.get(path)` is None at every commit, so no content can match and the file is reported
however it was written. Reading D as "edited by hand" is a guaranteed false positive, not
a coincidence -- it is what made this script name a file it was not looking at.

The search for B and C is over each path's FULL upstream history, not a fixed window. A
window makes the alarm's sensitivity a constant nobody chose: a blob equal to an upstream
commit older than the window is indistinguishable from a hand edit.

WHAT THE ALARM STILL CANNOT SEE, STATED RATHER THAN IMPLIED: it classifies CONTENT, so a
hand edit that reproduces a byte-identical upstream file is invisible, and so is a local
addition at an upstream path (D). The 1:1 NAME check is a separate question and lives in
the ports, not here.
"""
import json, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
UPSTREAM = "upstream/master"
UPSTREAM_ANY = "--remotes=upstream"   # every fetched upstream branch, not just master
PIN_DEPTH = 400


def sh(*a, cwd=REPO):
  return subprocess.run(a, cwd=cwd, capture_output=True, text=True).stdout


def shf(*a, cwd=REPO):
  r = subprocess.run(a, cwd=cwd, capture_output=True, text=True)
  return r.stdout if r.returncode == 0 else ""


def our_blobs(from_disk=False):
  """{path: blob}. The INDEX by default; `--worktree` hashes what is actually on disk."""
  out = {}
  if from_disk:
    for p in sorted((REPO / "tinygrad").rglob("*")):
      if p.is_file() and "__pycache__" not in p.parts:
        out[str(p.relative_to(REPO))] = sh("git", "hash-object", str(p)).strip()
    return out
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


def find_pin(depth=PIN_DEPTH):
  """(sha, matched, total, runner_up_matched) -- the upstream commit whose tinygrad/ tree
  best matches our vendored copy. Newest wins a tie, so the pin can only move UP."""
  ours = our_blobs()
  hist = sh("git", "log", "--format=%H", UPSTREAM).splitlines()[:depth]
  # tree_blobs is a subprocess; hoist it OUT of the inner generator or this becomes
  # len(ours) x depth git calls (92,000) instead of depth (400).
  scores = []
  for c in hist:
    tree = tree_blobs(c)
    scores.append((sum(1 for p, s in ours.items() if tree.get(p) == s), c))
  if not scores:
    return None, 0, len(ours), 0
  best = max(scores)
  runners = sorted({m for m, _ in scores if m < best[0]}, reverse=True)
  return best[1], best[0], len(ours), runners[0] if runners else 0


def upstream_blob_history(path):
  """(set_of_blobs, {blob: newest_commit}, commit_count) for one path.

  Every commit in ANY upstream ref that changed the path, so the blob set is COMPLETE: a
  file's content only ever changes at a commit that changed it. One `git log` and ONE
  `git cat-file --batch-check` per path -- batch-check prints the resolved sha in input
  order, so the commit->blob mapping comes back without a `git rev-parse` per commit.
  That per-commit call is not a micro-optimisation: cstyle.py alone has 642."""
  commits = sh("git", "log", UPSTREAM_ANY, "--format=%H", "--", path).splitlines()
  if not commits:
    return set(), {}, 0
  p = subprocess.run(["git", "cat-file", "--batch-check"], cwd=REPO,
                     capture_output=True, text=True,
                     input="\n".join(f"{c}:{path}" for c in commits) + "\n")
  blobs, owners = set(), {}
  for c, line in zip(commits, p.stdout.splitlines()):
    f = line.split()
    if len(f) < 2 or f[1] != "blob":
      continue
    blobs.add(f[0])
    owners.setdefault(f[0], c)      # git log is newest-first, so the first owner is newest
  return blobs, owners, len(commits)


def classify(ours, pin_tree):
  """-> (A, B, C, D). B and C carry the commit that settles them."""
  def one(item):
    p, s = item
    if pin_tree and pin_tree.get(p) == s:
      return p, "A", None
    blobs, owners, _ = upstream_blob_history(p)
    if not blobs:
      return p, "D", None
    if s in blobs:
      return p, "B", owners[s]
    return p, "C", None

  with ThreadPoolExecutor(max_workers=8) as ex:
    rows = list(ex.map(one, sorted(ours.items())))
  out = {"A": [], "B": [], "C": [], "D": []}
  for p, k, c in rows:
    out[k].append((p, c))
  return out["A"], out["B"], out["C"], out["D"]


def port_for(py):
  b = REPO / "tinybendygrad" / (py[len("tinygrad/"):]).replace(".py", ".bend")
  return b if b.exists() else None


def main():
  if "--fetch" in sys.argv:
    print(sh("git", "fetch", "upstream", "--quiet").strip() or "fetched upstream")
  pin, matched, total, runner = find_pin()
  head = sh("git", "rev-parse", UPSTREAM).strip()
  pin_date = sh("git", "log", "-1", "--format=%ad", "--date=short", pin).strip()
  head_date = sh("git", "log", "-1", "--format=%ad", "--date=short", head).strip()
  behind = sh("git", "rev-list", "--count", f"{pin}..{head}").strip() or "?"
  changed = sh("git", "diff", "--name-only", pin, head).splitlines()
  tg = [f for f in changed if f.startswith("tinygrad/")]

  ours = our_blobs()
  at_pin, revend, handedit, localonly = classify(ours, tree_blobs(pin))

  disk = None
  if "--worktree" in sys.argv:
    disk = our_blobs(from_disk=True)
    disk_dirty = sorted(p for p, s in disk.items() if ours.get(p) != s)

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
         "pin_runner_up": runner, "pin_method": f"content match over {PIN_DEPTH} commits "
                     f"of {UPSTREAM}; newest wins a tie",
         "at_pin": [p for p, _ in at_pin],
         "hand_edits": [p for p, _ in handedit],
         "local_only": [p for p, _ in localonly],
         "re_vendored": {p: c for p, c in revend},
         "upstream_head": head, "head_date": head_date,
         "commits_behind": behind, "files_changed": len(changed),
         "tinygrad_files": len(tg), "port_relevant": len(relevant),
         "new_upstream_py": added, "detail": relevant}
  if disk_dirty is not None:
    res["worktree_differs_from_index"] = disk_dirty

  if "--json" in sys.argv:
    print(json.dumps(res, indent=2)); return 0

  print(f"  PIN      {pin[:12]}  {pin_date}   {matched}/{total} vendored blobs match it")
  print(f"           method: {res['pin_method']}. Runner-up {runner}/{total}, so the pin is "
        f"unique by {matched - runner} blob(s).")
  print(f"  UPSTREAM {head[:12]}  {head_date}   BEHIND {behind} commits, {len(changed)} files, "
        f"{len(tg)} under tinygrad/")
  print(f"  AT PIN                 {len(at_pin):>4}")
  print(f"  RE-VENDORED            {len(revend):>4}   equals a real upstream commit -- the "
        f"goal of a batch, not a regression")
  print(f"  ⚠ HAND EDITS           {len(handedit):>4}   upstream HAS this path, our blob is at "
        f"NO upstream commit")
  for p, _ in handedit:
    print(f"      {p}")
  if handedit:
    print("      This is the invariant: content we wrote that no upstream commit contains.")
  print(f"  LOCAL-ONLY PATHS       {len(localonly):>4}   upstream has never had these paths; "
        f"NOT edits, and unmeasurable by content")
  for p, _ in localonly:
    print(f"      {p}   (decided by owner ruling, not by this tool)")
  print(f"  PORT-RELEVANT CHANGED  {len(relevant):>4} of our ports have moved under us")
  if disk_dirty is not None:
    print(f"  ⚠ WORKTREE             {len(disk_dirty):>4}   vendored file(s) on DISK differ "
          f"from the index; this report measured the INDEX")
    for p in disk_dirty: print(f"      {p}")
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