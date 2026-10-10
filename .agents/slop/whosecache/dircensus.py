#!/usr/bin/env python
"""DIRECTORY WALK: the cache populations in checks/ gates/ oracles/ runs/.

THE KEY IS (FIRST FIELD, EXTENSION), NOT A TEMPLATE, and this file is the record of why.
Three earlier instruments in it, all in this session, all wrong in the same direction:

  1. CHARACTER alignment -- `rows-flip-py.rows` vs `rows-matmul-py.rows` differ at index 5
     (`f`/`m`) and every index after, so one `*` per pass and a fixpoint both degenerated to
     `rows-************`, which covers a real cache and reports DENOMINATOR 0 for every
     directory walked.  A zero that hides 100 directories is worse than no instrument.
  2. TOKEN alignment -- arity, not length.  `rows-flip-py.rows` is 3 fields and
     `rows-threefry-bend.rows` is 4, so grouping by field count SPLIT ONE POPULATION IN TWO
     at the length of the graph's own name, which is not a cache property at all.
  3. LARGEST GROUP ONLY -- `oracles/` is a flat directory of 329 files; its largest single-arity
     group was `tinybendygrad_...rows`, so the `rows-<graph>-<side>.rows` population -- the
     whole subject -- was dropped as "covers nothing".

`(first field, extension)` is stable under a variable-length key because the key is never at
the front and the extension never moves.  It is COARSE: `checks/rows-*` and `checks/rows/rows-*`
are the same name in two directories, and only the DIRECTORY distinguishes them.  That is
deliberate -- a key's length is not a property of the cache, and an instrument that reads one
is reading the keys.

A `(first field, extension)` GROUP IS A SHAPE, NOT A POPULATION.  It says which files were
named by one rule.  It does not say who wrote them, or when.  `in HEAD` is git, and the
generator is asked in `discover.py`.  Those are separate questions and this file conflates
neither.

`find -type f` does not descend a symlinked directory.  `os.walk(followlinks=False)` matches
that rather than exceeding it; every skipped symlink is printed."""
import os, pathlib, sys, collections, subprocess

ROOT = pathlib.Path(__file__).resolve().parents[3]
TREES = ("checks", "gates", "oracles", "runs")
SEPS = "-_"
MIN = 8


def group(name):
  """(first field, extension).  `rows-flip-py.rows` -> ('rows', '.rows')."""
  stem, _, ext = name.rpartition(".")
  ext = "." + ext if ext else ""
  for s in SEPS:
    if s in stem:
      return stem.split(s, 1)[0], ext
  return stem, ext


def tracked(rel):
  r = subprocess.run(["git", "-C", str(ROOT), "ls-tree", "-r", "HEAD", "--name-only", rel + "/"],
                     capture_output=True, text=True)
  return len([x for x in r.stdout.splitlines() if x.strip()])


def main():
  out, walked, files = [], 0, 0
  for tree in TREES:
    base = ROOT / tree
    if not base.is_dir():
      continue
    for dirpath, dirnames, filenames in os.walk(base, followlinks=False):
      for s in [d for d in dirnames if (pathlib.Path(dirpath) / d).is_symlink()]:
        print(f"  NOTE symlink not descended: {pathlib.Path(dirpath, s).relative_to(ROOT)}")
      dirnames[:] = [x for x in dirnames if x != "__pycache__"]
      walked += 1
      files += len(filenames)
      g = collections.defaultdict(list)
      for f in filenames:
        g[group(f)].append(f)
      rel = str(pathlib.Path(dirpath).relative_to(ROOT))
      for (head, ext), members in g.items():
        if len(members) >= MIN:
          out.append((rel, head + ext, len(members), len(filenames), tracked(rel)))
  out.sort(key=lambda r: -r[2])
  print(f"\nDIRECTORY WALK over {len(TREES)} trees ({', '.join(TREES)}), os.walk(followlinks=False)")
  print(f"walked {walked} directories holding {files} files; groups keyed by (first field, ext) "
        f"with >= {MIN} members:")
  print(f"{'directory':<26} {'name':<34} {'n':>4} {'of':>5} {'in HEAD':>8}")
  for rel, name, n, tot, tr in out:
    print(f"{rel:<26} {name:<34} {n:>4} {tot:>5} {tr:>8}")
  print(f"\nDENOMINATOR: {len(out)} groups of >= {MIN} files, over {walked} directories / "
        f"{files} files in {len(TREES)} trees.")
  print("A group is a SHAPE.  It does not name a generator and it does not date anything.")
  return 0


if __name__ == "__main__":
  sys.exit(main())
