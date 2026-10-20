#!/usr/bin/env python3
"""pinned-tree-gate.py -- the two halves of a re-vendor claim, which come apart, and only one of
them rots.

    .venv/bin/python gates/pinned-tree-gate.py
    .venv/bin/python gates/pinned-tree-gate.py --plant
    .venv/bin/python gates/pinned-tree-gate.py --json

MEASURED 2026-10-20, ON A RE-VENDOR OF `tinygrad/` THAT MOVED IT FORWARD. The commit is
`git log -1 --format=%H -- tinygrad/` and the two sides of the identity it makes false are printed by
`tree_identity_holds` below; neither sha is written in this file, because a gate whose own header
carries one is a site its own third claim reports.
A re-vendor makes two kinds of statement true at once and only one of them keeps being true:

  IDENTITY   `HEAD:tinygrad` == `refs/remotes/upstream/master:tinygrad`. True the instant the
             re-vendor lands. TRUE BEFORE IT TOO.
  SHA        "…and both are `<40 hex>`". True until the NEXT re-vendor, with no signal, because
             nothing measures a sentence.

FIVE SITES IN THIS TREE ASSERTED THE SHA AND THE IDENTITY IN ONE BREATH, and the SHA went false at
`77e6c2bec` while the identity stayed true. **A SHA IN PROSE IS A TRANSCRIPTION AND THE NEXT
RE-VENDOR MAKES IT FALSE AGAIN, WHICH IS EXACTLY WHAT HAPPENED.** The remedy is not a fresher SHA; it
is to delete the SHA and keep the comparison in a place that reads it. So this gate holds the
identity WITHOUT a sha in it, and then hunts the transcription itself.

    PASS 0     the tree identity holds, the index population is whole, no gate home transcribes a
               `tinygrad/` tree value
    FAIL 1     a check ran and answered no -- named, with the site or the value that answers no
    REFUSED 3   a precondition was absent. An ARMED INDEX IS NOT A WRONG TREE: the blobs are right
               and the files are on disk, but every instrument that reads `git ls-files` in this
               tree is reading a POPULATION THAT IS NOT THE TREE
    DEAD 5     the gate could not measure at all

READ-ONLY BY CONSTRUCTION. Every git call carries `--no-optional-locks`, which is what stops git
refreshing -- and therefore rewriting -- `.git/index` as a side effect of being read. A gate that arms
the thing it is inspecting is worse than no gate. Nothing here writes a file, fetches a ref, or
touches `tinygrad/`.

CLAIM 2 IS NOT REIMPLEMENTED, IT IS DELEGATED. The census of the index against the tree already
exists and is already correct: `checks/index-arm-gate.py`'s `report()`. A second copy of that census
is a second contract with no generator, which is the exact fault this gate exists to catch in prose.
What is added is the sentence the delegation makes possible: the census is not about commits, it is
about EVERY instrument in the tree that asks `git ls-files` for its population, and
`INDEX_READERS` is that set, derived by a regex over the tree's own git-call sites rather than typed.

WHY THE INDEX IS CLAIM 2 AND NOT A FOOTNOTE. MEASURED, on the same tree, the same minute:
`git rev-parse HEAD:tinygrad` and `refs/remotes/upstream/master:tinygrad` are ONE tree, and
`.agents/slop/upstream-delta.py` -- whose `PIN` line `.agents/UPSTREAM-PIN.md` cites as the
re-derivation of all four of its own rows -- printed `PIN 002630241913`, `AT PIN 229` and
`PORT-RELEVANT CHANGED 26`, because its `our_blobs()` reads `git ls-files -s tinygrad/` and the index
held the PRE-re-vendor blob for 28 paths and no entry at all for the 1 added one. THE DOCUMENT AND
THE INSTRUMENT DISAGREED, AND BOTH WERE HONEST. Re-run under an index built from `HEAD` and the same
command printed `PIN 5c2bf39d6c4b`, `AT PIN 230`, `PORT-RELEVANT CHANGED 0` -- which is what
`.agents/UPSTREAM-PIN.md` says its rows read. **AN INSTRUMENT THAT ASKS THE INDEX FOR ITS POPULATION
INHERITS `GIT_INDEX_FILE`, AND IT INHERITES IT SILENTLY, AND ITS OUTPUT LOOKS EXACTLY LIKE A FINDING.**

WHAT THIS GATE CANNOT SEE, NAMED. (a) Its transcription scan covers the DERIVED GATE HOMES and nothing
else, so a claim in `AGENTS.md`, in `.agents/**` or in a `.bend` file is outside it -- and those are
MEASURED, not assumed: `gates/gates-pop.py`'s `gate_homes()` REJECTS `.agents` at 0 of 6 certified
gates, and this file states the limit rather than widening the walk to hide it. (b) A hex literal is
matched only when it is a PREFIX of a recent `tinygrad/` tree value, so an unrelated 40-hex digest is
correctly not a hit; the plant's `NOT-A-TREE` state is what proves that rather than asserting it.
(c) The tree population is the last `DEPTH` commits that touched `tinygrad/`, which is a window: a
site naming a tree older than the window is not found. Stating the window is the honest half; the
window is why `DEPTH` is a named constant and not a number typed beside a claim.
(d) IT CANNOT TELL A DATED MEASUREMENT RECORD FROM A LIVE CLAIM, and it REPORTS BOTH. Every hit is
printed with the site, the literal and whether it abbreviates the current tree or a retired one, and
THE CLASSIFICATION IS LEFT TO THE READER, because the alternative is matching prose -- asking whether
a line says "is" or "was" -- and that is the same fault as a basename shape: it reads well on the
lines you wrote and silently passes the ones you did not. **MEASURED, AND IT OVER-REPORTS:**
`gates/corpusfresh-gate.py` carries BOTH ends of one re-vendor's arrow on a dated line with its own
re-derivation command beside them, which is the CORRECT shape for a record and is reported here
anyway. So the hit count is an UPPER BOUND on the rot, and a reader who wants the rot and not the
record has to read the line -- which is stated here rather than left as a surprise on the first run.
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

# THE FIVE VERDICTS, IMPORTED BY PATH from the file that OWNS them (`gatekit.py`, same dir), never
# re-spelled: a second copy of the vocabulary is the same fault as a second copy of a population, and
# a runner maps any code outside the five to `DEAD`.
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED  # noqa: E402

# `git --no-optional-locks` is READ-ONLY BY CONSTRUCTION, the same reason
# `checks/index-arm-gate.py` puts it on every call: without it, READING the index rewrites it.
GIT = ("git", "--no-optional-locks")

# GIT'S OWN ABBREVIATION FLOOR FOR A READABLE OBJECT NAME IS 7 HEX. A 40-hex pattern finds none of
# this gate's real population and reads as "no pins exist", which is a silent FALSE NEGATIVE dressed
# as a clean census -- `AGENTS.md`'s own record of the same failure one length up, where a `{40}`
# pattern found 0 of 7 SHA-256 blob pins.
HEX = re.compile(r"(?<![0-9a-f])([0-9a-f]{7,64})(?![0-9a-f])")

# THE WINDOW. `git log -- tinygrad/` walks a path's whole history in this repository, and the tree
# values are one per commit that moved it; 60 commits is where the CURRENT and the immediately
# RETIRED value both sit, which is the pair a re-vendor's own prose cites. The bound is named here
# rather than beside a claim, and (c) above says what it costs.
DEPTH = 60

# THE SET OF INSTRUMENTS THAT ASK THE INDEX FOR THEIR POPULATION, DISCOVERED BY A REGEX OVER THE
# TREE'S OWN GIT-CALL SITES, not typed: `checks/index-arm-gate.py` holds the census and this file
# holds the CONSEQUENCE, and the consequence is only meaningful if the readers are visible. A literal
# tuple here would be a population nobody could check, and this gate's third claim is that those are
# the defect.
INDEX_READERS = re.compile(r"""["']git["']\s*,\s*["'](ls-files|diff-index|diff-files)["']""")


def git(root, *args):
  """`(rc, stdout)` for one read-only git call. `FileNotFoundError` is DEAD, not an exception."""
  try:
    p = subprocess.run(GIT + args, cwd=root, capture_output=True, text=True)
  except FileNotFoundError:
    return DEAD, ""
  return p.returncode, p.stdout


def resolve(root, rev):
  """The tree object `rev:<path>` names, or `""`. ONE call per side, and the value is never written
  into this file -- a constant here is a transcription that a re-vendor falsifies for free."""
  rc, out = git(root, "rev-parse", "--verify", "--quiet", rev)
  return out.strip() if rc == 0 else ""


def tree_values(root, depth=DEPTH):
  """`{tinygrad/ tree object: the commit that put it there}` over the last `depth` commits that
  touched `tinygrad/`. DERIVED, never typed, and it is the only source of "a tree this project has
  actually vendored" the gate is allowed to compare a literal against."""
  _, log = git(root, "log", "--format=%H", f"-n{depth}", "HEAD", "--", "tinygrad/")
  out = {}
  for c in log.split():
    t = resolve(root, f"{c}:tinygrad")
    if t:
      out.setdefault(t, c)
  return out


def homes(root):
  """`[root/<h>]` for each entry of `gates-pop.py`'s MEASURED home set. Bound from the generator
  rather than typed here: `HOMES` was `("checks", "gates")` as a literal in that file and is now
  `gate_homes(ROOT)`, and a second copy of the list is the exact fault the class describes."""
  mod = _load("gates_pop", HERE / "gates-pop.py")
  return [root / h for h in mod.HOMES if (root / h).is_dir()]


def _load(name, path):
  """Import a module BY PATH under `name`, with the importer's own warnings silenced.

  Both delegated instruments are imported, not copied. `warnings.catch_warnings` is here because
  `gates/gates-pop.py` carries a `SyntaxWarning` from a docstring escape of its own, and a gate whose
  stdout is polluted by a warning from a file it does not own cannot be read by someone comparing its
  output to another run's -- the same reason the delegated module is not reimplemented here.
  """
  import importlib.util
  import warnings
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    spec.loader.exec_module(mod)
  return mod


def _site(root, p):
  """`p` as a repo-relative site, or absolute when it is not under the repo AT ALL.

  `--plant` points this function at directories in a temporary tree, and `Path.relative_to` raises
  `ValueError` rather than degrading. A plant that crashes on its own fixture is a plant that has
  measured nothing, which is the failure this file's plant section is written against -- so the
  fallback is explicit and the plant's temp paths are named on stdout instead of hidden.
  """
  try:
    return str(p.relative_to(root))
  except ValueError:
    return str(p)


def transcribed(root, dirs, trees):
  """`[(site, literal, tree)]` -- every hex run under `dirs` that is a PREFIX of a known
  `tinygrad/` tree value, with the tree it abbreviates.

  A DIRECTORY WALK AND `endswith`, never `glob` and never a basename shape: `AGENTS.md` records that
  `glob('*.bend')` returns `[]` on a tree where `.bend` files are on disk and tracked. The prefix
  test is EXACT in both directions -- a literal that is not a prefix of any tree value is not a hit,
  which is what keeps an unrelated digest from being reported as a transcription.
  """
  hits = []
  for d in dirs:
    for base, _, files in os.walk(d):
      for f in files:
        if not f.endswith((".py", ".bend", ".md", ".sh", ".mjs", ".json", ".rows", ".tsv")):
          continue
        p = Path(base) / f
        try:
          text = p.read_text(errors="replace")
        except OSError:
          continue
        for n, line in enumerate(text.splitlines(), 1):
          for m in HEX.findall(line):
            for t in trees:
              if t.startswith(m):
                hits.append((f"{_site(root, p)}:{n}", m, t))
                break
  return hits


def index_readers(root, dirs):
  """`[(site, matched call)]` -- the gate-home call sites that would read the index. The census is
  `checks/index-arm-gate.py`'s; this is the list of places that census is ABOUT."""
  hits = []
  for d in dirs:
    for base, _, files in os.walk(d):
      for f in files:
        if not f.endswith(".py"):
          continue
        p = Path(base) / f
        try:
          text = p.read_text(errors="replace")
        except OSError:
          continue
        for n, line in enumerate(text.splitlines(), 1):
          m = INDEX_READERS.search(line)
          if m:
            hits.append((f"{_site(root, p)}:{n}", m.group(1)))
  return hits


# ---- the three claims -----------------------------------------------------------------------

def tree_identity_holds(root):
  """CLAIM 1: `HEAD:tinygrad` == `refs/remotes/upstream/master:tinygrad`, HELD WITHOUT NAMING EITHER.

  The full ref, not `upstream`: `upstream` alone resolves through `refs/remotes/upstream/HEAD`, and
  a second spelling of one side is a second place for the two sides to disagree.

  Two assertions, each of which can fail: both sides RESOLVE (an unresolvable side is a named False
  and not a silent `"" == ""`, which is the vacuous negative this gate exists to refuse), and they are
  EQUAL. The values are PRINTED and are never assigned to a constant in this file.
  """
  head, up = resolve(root, "HEAD:tinygrad"), resolve(root, "refs/remotes/upstream/master:tinygrad")
  for name, got in (("HEAD:tinygrad", head), ("refs/remotes/upstream/master:tinygrad", up)):
    if not got:
      print(f"pinned-tree-gate: {name} did not resolve -- a comparison of two empty strings is the "
            f"vacuous negative, so this refuses rather than holds")
      return False
  if head != up:
    print(f"pinned-tree-gate: the two trees DIFFER -- HEAD:tinygrad {head[:12]}, "
          f"refs/remotes/upstream/master:tinygrad {up[:12]}; the vendored copy is not upstream's")
    return False
  print(f"pinned-tree-gate: TREE IDENTITY holds -- HEAD:tinygrad == refs/remotes/upstream/master:tinygrad "
        f"== {head[:12]} (both sides DERIVED by git rev-parse; no sha is written in this file)")
  return True


def index_population_holds(root):
  """CLAIM 2: THE INDEX POPULATION IS THE TREE POPULATION, delegated to the instrument that already
  answers it, and reported as the REFUSAL it is.

  `checks/index-arm-gate.py` is imported BY PATH and its `report()` is called; nothing about the
  census is reimplemented here. A non-zero return is REFUSED (3) rather than FAIL (1) for
  `index-arm-gate.py`'s stated reason, which this file adopts rather than re-argues: the blobs are
  right and the files are on disk, and the thing that is wrong is the TOOL.

  The count that matters is printed in the instrument's own SHAPES, and `INDEX_READERS` says which
  call sites that count is about -- so a reader is not left to guess what an armed index costs.
  """
  sys.path.insert(0, str(ROOT / "gates"))
  rc, census = _load("index_arm", ROOT / "checks" / "index-arm-gate.py").report(root)
  n = sum(len(census.get(k, [])) for k in ("DELETION", "INTENT", "STALE", "FOREIGN"))
  if rc != PASS:
    readers = index_readers(root, homes(root))
    print(f"pinned-tree-gate: REFUSED, NOT A VERDICT -- the index carries {n} path(s) HEAD does not "
          f"(INDEX-ARM SHAPES: {', '.join(f'{k}={len(census.get(k, []))}' for k in ('DELETION', 'STALE', 'FOREIGN', 'INTENT'))}). "
          f"The tree is fine; the TOOL is pointed wrong. EVERY INSTRUMENT THAT READS IT IS AFFECTED, "
          f"AND {len(readers)} site(s) IN THE GATE HOMES CALL `git ls-files`/`diff-index`:")
    for site, what in readers[:8]:
      print(f"      {site}  {what}")
    if len(readers) > 8:
      print(f"      ... and {len(readers) - 8} more")
    print("      MEASURED CONSEQUENCE: `.agents/slop/upstream-delta.py`'s `our_blobs()` reads "
          "`git ls-files -s tinygrad/`, so under this index it derives its PIN from the PRE-re-vendor "
          "blobs while `.agents/UPSTREAM-PIN.md` cites that same line as the re-derivation of its own "
          "four rows. THE DOCUMENT AND THE INSTRUMENT DISAGREE, AND BOTH ARE HONEST.")
    return False
  print(f"pinned-tree-gate: INDEX POPULATION holds -- the index agrees with HEAD on all "
        f"{census.get('n_tree', '?')} paths (delegated to checks/index-arm-gate.py; nothing here "
        f"reimplements that census)")
  return True


def no_transcribed_tree_sha(root):
  """CLAIM 3: NO GATE HOME TRANSCRIBES A `tinygrad/` TREE VALUE.

  This is the check that would have caught the five sites. The population is a DIRECTORY WALK of the
  DERIVED gate homes and the tree values are a DERIVED window of this repository's own history, so
  neither is typed; a fourth site added tomorrow is found by the same two derivations.

  One assertion, and it names the site rather than the count alone: a hit prints `file:line`, the
  literal, and the tree it abbreviates -- because "4 sites" does not tell a reader where to look, and
  a count beside no site is a number nobody can act on.
  """
  trees = tree_values(root)
  if not trees:
    print("pinned-tree-gate: no `tinygrad/` tree value could be derived from this repository's own "
          "history, so there is no population to compare a literal against -- that is DEAD, not a "
          "clean census")
    return False
  dirs = homes(root)
  hits = transcribed(root, dirs, trees)
  if hits:
    print(f"pinned-tree-gate: {len(hits)} TRANSCRIBED TREE SHA(S) in the derived gate homes "
          f"{[d.name for d in dirs]} -- each is a sentence a re-vendor falsifies for free:")
    for site, lit, tree in hits:
      cur = "IS THE CURRENT TREE" if tree == resolve(root, "HEAD:tinygrad") else "is a RETIRED tree"
      print(f"      {site}  {lit}  -> {tree[:12]} ({cur})")
    print("      DELETE THE SHA AND KEEP THE COMPARISON: a sha in prose is a transcription, and the "
          "identity it stands in for is measurable. `gates/pinned-tree-gate.py --plant` shows the "
          "claim can still go red on a planted one.")
    return False
  print(f"pinned-tree-gate: NO TRANSCRIBED TREE SHA in the derived gate homes "
        f"{[d.name for d in dirs]} -- {len(trees)} distinct `tinygrad/` tree values over the last "
        f"{DEPTH} commits that touched it, and no hex run under those homes abbreviates any of them")
  return True


# ---- the plant ------------------------------------------------------------------------------

def plant(root):
  """THREE STATES OF CLAIM 3, IN TEMP DIRECTORIES, AND THE TWO THAT MAKE THE THIRD MEANINGFUL.

      .venv/bin/python gates/pinned-tree-gate.py --plant

  THE PRIOR FAILURE THIS SHAPE IS BUILT AGAINST, because both halves of it are in the tree's record:
  a plant that "made the lane emit nothing while the check scored it as a successful plant" passes
  when the check cannot tell nothing from agreement, and a negative that flattens both sides to one
  constant passes for the same reason. So the three states are NOT "one planted literal, looks red":

      CLEAN       a home with a file containing NO tree abbreviation -> 0 sites. THE CONTROL, and it
                  is the state that fails if the check reports a site for everything.
      PLANTED     the same home PLUS ONE FILE whose only content is a hex run that IS a prefix of a
                  RETIRED tree value -> EXACTLY ONE MORE site, naming that file. The literal is
                  COPIED from `tree_values(root)`, never typed, so the plant cannot rot into
                  vacuity the way a transcription does.
      NOT-A-TREE  a third file carrying a 40-hex digest that is NOT a prefix of any tree value ->
                  STILL 0 sites. THE NON-VACUOUS NEGATIVE: without it, a check that matched ANY hex
                  would score PLANTED as a success while measuring nothing.

  FALSIFICATION CLAUSE, and it is the exit status: the plant is WRONG unless CLEAN is 0 AND
  NOT-A-TREE is 0 AND PLANTED is exactly 1 MORE than CLEAN AND the extra site names the planted
  file. If the planted file were unread, or the walk skipped it, or the check matched every hex, the
  counts would be 0/0/0 and the plant prints `PLANT WRONG` and exits 1. A plant that cannot fail is
  a comment.
  """
  trees = tree_values(root)
  if len(trees) < 2:
    print("--plant: WRONG -- this repository's history offers fewer than two distinct `tinygrad/` tree "
          "values, so a RETIRED one cannot be derived and the plant would be testing a constant")
    return 1
  cur = resolve(root, "HEAD:tinygrad")
  retired = next(t for t in trees if t != cur)
  decoy = hashlib.sha1(b"not a tinygrad tree value").hexdigest()
  print(f"--plant: derived {len(trees)} tree values; current {cur[:12]}, retired {retired[:12]}, "
        f"and a 40-hex NON-tree {decoy[:12]}")

  bad = []
  clean_sites = -1
  with tempfile.TemporaryDirectory() as td:
    for name, extra, want_delta in (("CLEAN", None, 0), ("PLANTED", ("planted.py", retired), 1),
                                    ("NOT-A-TREE", ("decoy.py", decoy), 0)):
      home = Path(td) / name / "gates"
      home.mkdir(parents=True)
      (home / "quiet.py").write_text("# a file with no tree abbreviation in it at all\n")
      if extra:
        (home / extra[0]).write_text(f"# planted: tinygrad/ was {extra[1]}\n")
      got = transcribed(root, [home], trees)
      delta = len(got) - 0
      names = [s for s, _, _ in got]
      ok = delta == want_delta and (want_delta == 0 or extra[0] in " ".join(names))
      print(f"  {name:<12} sites={len(got)} delta={delta} want_delta={want_delta} "
            f"{'OK' if ok else '<-- PLANT WRONG'}"
            + ("" if not got else f"  at {names}"))
      if not ok:
        bad.append(f"{name}: {len(got)} site(s), wanted {want_delta} more than CLEAN")
      if name == "CLEAN":
        clean_sites = len(got)
    if clean_sites:
      bad.append(f"the control is not clean: {clean_sites} site(s) with no planted literal")
  print(f"--plant: {'all 3 states OK' if not bad else 'PLANT WRONG: ' + '; '.join(bad)}")
  return 1 if bad else 0


def main():
  if "--plant" in sys.argv:
    return plant(ROOT)
  if not (ROOT / ".git").exists() and not (ROOT / "HEAD").exists():
    print("pinned-tree-gate: DEAD -- no repository here; a gate with no tree measures nothing")
    return DEAD
  ok = [tree_identity_holds(ROOT), index_population_holds(ROOT), no_transcribed_tree_sha(ROOT)]
  if "--json" in sys.argv:
    print("PINNED-TREE JSON " + json.dumps(
      {"identity": resolve(ROOT, "HEAD:tinygrad"), "claims": ok}))
  failed = [n for n, v in zip(("identity", "index-population", "no-transcribed-sha"), ok) if not v]
  if "index-population" in failed and ok[0] and ok[2]:
    print(f"pinned-tree-gate: REFUSED, NOT A VERDICT: {failed[0]}")
    return REFUSED
  if failed:
    print(f"pinned-tree-gate: FAIL -- {failed}")
    return FAIL
  print("pinned-tree-gate: PASS -- the tree identity holds with no sha written here, the index "
        "population is whole, and no gate home transcribes a `tinygrad/` tree value")
  return PASS


if __name__ == "__main__":
  sys.exit(main())