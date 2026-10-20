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

    PASS 0     the tree identity holds, the index population is whole, and no gate home claims the
               current `tinygrad/` tree by a transcribed sha
    FAIL 1     a check ran and answered no -- a sha names the current tree and no verified record
               owns that line, or the two trees differ
    REFUSED 3   a precondition was absent, or a dated record's date does not match the commit its
               derive names. An ARMED INDEX IS NOT A WRONG TREE: the blobs are right and the files
               are on disk, but every instrument that reads `git ls-files` in this tree is reading
               a POPULATION THAT IS NOT THE TREE
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
(d) A DATED RECORD IS A BINDING, IMPORTED FROM `gates/rotclaim-gate.py` (`spans`), NOT A COMMENT
AND NOT A SECOND COPY OF THAT GATE. `*_RECORD_DATE` + `*_RECORD_DERIVE` -- the names in this tree
are `REVENDOR_RECORD_DATE` and `REVENDOR_RECORD_DERIVE` -- own the lines of those two assignments
only when a second git call says the date matches the commit the derive names. A comment that says
"dated record" is not an assignment, so it owns nothing. A date that does not match is REFUSED, and
that record owns nothing either. A sha that prefixes the current `HEAD:tinygrad` and is not on those
lines is a live claim: it goes false at the next re-vendor, and refreshing it is not a fix. A sha
that prefixes only a retired tree is a pin for a past revision, which is not stale. `gates/artifacts/`
is a run's transcript (`_generated`, imported from the same module), not a source claim.
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import warnings
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


def _record():
  """The dated-record test, loaded by path from `rotclaim-gate.py`. Not copied.

  That module loads this file lazily, and only when its own judge runs. Loading it back at
  import time is a cycle, so this is called from the claim and the plant, not from import.
  `spans` is the test: ast assignments `*_RECORD_DATE` + `*_RECORD_DERIVE`, a second git call
  for the date, and owned lines only when that call agrees. A comment is not an assignment.
  """
  if _record.mod is None:
    _record.mod = _load("pinrecord_rotclaim", HERE / "rotclaim-gate.py")
  return _record.mod


_record.mod = None


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


def _split_site(site):
  path, _, line = site.rpartition(":")
  return path, int(line)


def classify(display_root, dirs, trees, git_root, emit_seen=False):
  """Each transcribed tree sha is a record, a past pin, a transcript, or a live claim.

  The record test is `_record().spans`, imported, not reimplemented. This function only
  applies it to the hits `transcribed` already found, and splits a current-tree sha from a
  retired one: rotclaim's own judge still calls every non-owned tree sha live, and a pin
  for a past revision is not that.
  """
  rc = _record()
  current = resolve(git_root, "HEAD:tinygrad")
  hits = transcribed(display_root, dirs, trees)
  rows, by_file = [], {}
  for site, literal, tree in hits:
    path, line = _split_site(site)
    if rc._generated(path):
      rows.append({"kind": "generated", "file": site, "literal": literal, "state": "TRANSCRIPT"})
      continue
    by_file.setdefault(path, []).append((line, literal, tree, site))
  seen = set()
  for d in dirs:
    if not d.is_dir():
      continue
    for base, dirnames, files in os.walk(d):
      dirnames[:] = [n for n in dirnames if n not in ("__pycache__", "artifacts") and not n.startswith(".tmp")]
      for fname in files:
        if not fname.endswith(".py"):
          continue
        p = Path(base) / fname
        rel = _site(display_root, p)
        try:
          text = p.read_text(errors="replace")
        except OSError:
          continue
        # `spans` parses with `ast.parse(text)` and no filename, so a `\.` in some other
        # file's docstring warns as `<unknown>`. That warning is not this claim.
        with warnings.catch_warnings():
          warnings.simplefilter("ignore", SyntaxWarning)
          owned, recs = rc.spans(text, git_root)
        for rec in recs:
          row = dict(rec)
          row["file"] = rel
          rows.append(row)
        n_live = 0
        for line, literal, tree, site in by_file.get(rel, []):
          if any(a <= line <= b for a, b in owned):
            rows.append({"kind": "owned", "file": site, "literal": literal, "state": "RECORD"})
            continue
          if tree == current:
            n_live += 1
            rows.append({"kind": "live", "file": site, "literal": literal, "state": "LIVE"})
          else:
            rows.append({"kind": "past", "file": site, "literal": literal, "state": "PIN"})
        if emit_seen:
          rows.append({"kind": "file", "file": rel, "state": "SEEN", "live": n_live})
        seen.add(rel)
  for path, items in sorted(by_file.items()):
    if path in seen:
      continue
    for _line, literal, tree, site in items:
      kind = "live" if tree == current else "past"
      state = "LIVE" if tree == current else "PIN"
      rows.append({"kind": kind, "file": site, "literal": literal, "state": state})
  return rows


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


def _n(rows, kind, state=None):
  return sum(1 for r in rows if r["kind"] == kind and (state is None or r["state"] == state))


def no_transcribed_tree_sha(root):
  """CLAIM 3: NO GATE HOME MAKES A LIVE CLAIM THAT THE CURRENT `tinygrad/` TREE IS A TRANSCRIBED SHA.

  The hits are still `transcribed`. The class of each hit is `classify`, which imports the record
  test rather than matching the words "dated record". A verified record and a retired-tree pin are
  printed and are not failures. A sha of the current tree, not on a verified binding, is a failure.
  A record whose date does not match is REFUSED. Refreshing a sha is not a fix, and this function
  does not write one.
  """
  trees = tree_values(root)
  if not trees:
    print("pinned-tree-gate: no `tinygrad/` tree value could be derived from this repository's own "
          "history, so there is no population to compare a literal against -- that is DEAD, not a "
          "clean census")
    return DEAD
  dirs = homes(root)
  rows = classify(root, dirs, trees, root)
  shown = [r for r in rows if r["kind"] != "file"]
  if shown:
    print("\n".join("pinned-tree\t" + _record().emit(r) for r in shown))
  live, refused = _n(rows, "live"), _n(rows, "record", "REFUSED")
  print(f"pinned-tree-gate: live={live} past={_n(rows, 'past')} "
        f"verified={_n(rows, 'record', 'VERIFIED')} refused={refused} "
        f"owned={_n(rows, 'owned')} transcript={_n(rows, 'generated')}")
  if live:
    print("pinned-tree-gate: FAIL -- a sha names the current tinygrad/ tree and no verified record "
          "owns that line. Refreshing the sha is not a fix.")
    return FAIL
  if refused:
    print("pinned-tree-gate: REFUSED -- a dated record's date does not match the commit its derive names")
    return REFUSED
  print(f"pinned-tree-gate: no live claim of the current tree in {[d.name for d in dirs]}")
  return PASS


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

  THE CONTROL ABOVE IS UNBROKEN: it still calls `transcribed`. The copy directions call `classify`
  on a copy of `corpusfresh-gate.py`. A dated record whose derive matches stays green, including
  when the current tree sha sits on the binding line. A comment that says "dated record" does not
  exempt that sha. A wrong date is a record row in state REFUSED. A direction that emits no row
  is REFUSED, not a success.
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
  fresh = (HERE / "corpusfresh-gate.py").read_text()
  pair = _record().records_of(fresh).get("REVENDOR")
  date = pair["date"][2] if pair and "date" in pair else ""
  if not cur or not date or any(t.startswith(decoy) for t in trees):
    print("--plant: REFUSED -- no current tree, no REVENDOR record, or the decoy prefixes a real tree")
    return REFUSED

  def drop_bindings(text):
    drop = set()
    for rec in _record().records_of(text).values():
      for key in ("date", "derive"):
        start, end, _value = rec[key]
        drop.update(range(start, end + 1))
    return "\n".join(ln for i, ln in enumerate(text.splitlines(), 1) if i not in drop) + "\n"

  def assess(text):
    with tempfile.TemporaryDirectory(prefix="pinrecord-") as td:
      home = Path(td) / "gates"
      home.mkdir()
      (home / "fixture.py").write_text(text)
      return classify(Path(td), [home], trees, root, emit_seen=True)

  def classified(text):
    got = assess(text)
    if not got or not any(r["kind"] == "file" for r in got):
      return None
    rec = next((r["state"] for r in got if r["kind"] == "record"), "ABSENT")
    return (_n(got, "live"), rec, _n(got, "past"), _n(got, "owned"))

  silent = []

  def check(label, got, want):
    if got is None:
      silent.append(label)
      bad.append(label)
      print(f"  {label}: REFUSED SILENT wanted={want}")
      return
    ok = got == want
    print(f"  {label}: {'OK' if ok else 'REFUSED'} verdict={got} wanted={want}")
    if not ok:
      bad.append(label)

  check("record-control", classified(fresh), (0, "VERIFIED", 0, 0))
  check("record-owns-current-sha", classified(fresh.replace(
    f'REVENDOR_RECORD_DATE = "{date}"', f'REVENDOR_RECORD_DATE = "{date}"  # {cur}', 1)),
    (0, "VERIFIED", 0, 1))
  check("prose-does-not-exempt", classified(drop_bindings(fresh) + f"# this was a dated record\n# {cur}\n"),
        (1, "ABSENT", 0, 0))
  check("wrong-date", classified(fresh.replace(
    f'REVENDOR_RECORD_DATE = "{date}"', f'REVENDOR_RECORD_DATE = "1999-01-01T00:00:00Z"  # {cur}', 1)),
    (1, "REFUSED", 0, 0))
  check("wrong-date-no-sha", classified(fresh.replace(
    f'REVENDOR_RECORD_DATE = "{date}"', 'REVENDOR_RECORD_DATE = "1999-01-01T00:00:00Z"', 1)),
    (0, "REFUSED", 0, 0))
  check("past-pin", classified(f"# {retired}\n"), (0, "ABSENT", 1, 0))
  check("current-sha-is-live", classified(f"# {cur}\n"), (1, "ABSENT", 0, 0))
  check("not-a-tree-on-a-record", classified(fresh + f"\n# {decoy}\n"), (0, "VERIFIED", 0, 0))
  if silent:
    print(f"--plant: REFUSED -- {len(silent)} direction(s) emitted nothing: {silent}")
    return REFUSED
  print(f"--plant: {'OK' if not bad else 'PLANT WRONG: ' + '; '.join(bad)}")
  return 1 if bad else 0


def main():
  if "--plant" in sys.argv:
    return plant(ROOT)
  if not (ROOT / ".git").exists() and not (ROOT / "HEAD").exists():
    print("pinned-tree-gate: DEAD -- no repository here; a gate with no tree measures nothing")
    return DEAD
  ident_ok = tree_identity_holds(ROOT)
  index_ok = index_population_holds(ROOT)
  sha = no_transcribed_tree_sha(ROOT)
  if "--json" in sys.argv:
    print("PINNED-TREE JSON " + json.dumps({
      "identity": resolve(ROOT, "HEAD:tinygrad"),
      "claims": [ident_ok, index_ok, sha == PASS],
      "sha": sha}))
  if sha == DEAD:
    print("pinned-tree-gate: DEAD")
    return DEAD
  failed = []
  if not ident_ok:
    failed.append("identity")
  if not index_ok:
    failed.append("index-population")
  if sha == FAIL:
    failed.append("live-claim")
  if sha == REFUSED:
    failed.append("record-date")
  if "live-claim" in failed or "identity" in failed:
    print(f"pinned-tree-gate: FAIL -- {failed}")
    return FAIL
  if failed:
    print(f"pinned-tree-gate: REFUSED, NOT A VERDICT: {failed[0]}")
    return REFUSED
  print("pinned-tree-gate: PASS -- the tree identity holds with no sha written here, the index "
        "population is whole, and no gate home claims the current tinygrad/ tree by a transcribed sha")
  return PASS


if __name__ == "__main__":
  sys.exit(main())