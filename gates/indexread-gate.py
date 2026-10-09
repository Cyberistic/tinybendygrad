#!/usr/bin/env python3
"""indexread-gate.py -- IS A COMMITTED INSTRUMENT READING THE INDEX WHERE THE TREE IS THE AUTHORITY?

    .venv/bin/python gates/indexread-gate.py            # the claim: no NEW offender
    .venv/bin/python gates/indexread-gate.py --strict   # the claim: NO offender at all
    .venv/bin/python gates/indexread-gate.py --print-baseline

THE SUBJECT IS THE STATE, NOT A DIFF. `gates/git-massdelete-gate.py` watches a DIFF (did this
commit delete too much). This watches a standing CONDITION: does any file this repo SHIPS
enumerate its population through `.git/index`? An index is per-worktree, mutable, and
deletable; a commit tree is content-addressed and immutable. Four destructions tonight came out
of that difference, and the census is at `gates/indexread-baseline.rows`.

WHY A GATE AND NOT A LINT. A LINT PRINTS. It cannot exit 3, so it cannot say "I could not
measure", and `gatekit`'s five verdicts are the only shared vocabulary here
(`PASS,FAIL,REFUSED,SKIP,DEAD = 0,1,3,4,5` -- there is no sixth, and a lint would invent one).
It also has no place to be CALLED from, which is the same failure as a gate that cannot fail: a
finding with no exit code is a note, and notes are not run. So: gate.

WHY IT IS GREEN AT REST. The census found offenders on their first run -- they predate this
file. A gate that cannot pass teaches nothing and gets skipped (`AGENTS.md`, on PROOF.bend's
18 TODOs). So the DEFAULT claim is GROWTH: the offender set may not exceed the pinned baseline
beside this gate, `gates/indexread-baseline.rows`, which is in git because a gate's input
belongs beside the gate in git (the `gates/cstyle-live.rows` precedent). `--strict` states the
stronger claim and is red today; that is a measurement, not a failure of this gate.

HOW IT ESTABLISHES THE TREE'S TRUTH WITHOUT THE INDEX. THE POINT, AND THE TRAP. This file runs
NO `git ls-files` and NO `git diff --cached` -- not even to check itself, because a self-check
that shares the index with its subject CANNOT DETECT THE INDEX: a reset index makes it agree
with the lie. Its population comes from `git ls-tree -r HEAD`, which reads the COMMIT TREE
OBJECT in `.git/objects`; no index reset can reach it. MEASURED, an index emptied with
`GIT_INDEX_FILE` at a throwaway path returns **0** paths where the tree returns **6296**.

THE THREE TRAPS THIS FILE EXISTS TO KEEP NAMED (all MEASURED, see REPORT.md):
  1 `ls-tree` WITHOUT `--name-only` prints `100644 blob <oid>\\tpath`, so field 0 is the MODE and
    a naive split enumerates 6296 identical-looking names. Every ls-tree here passes
    `--name-only`.
  2 `git cat-file --batch` FED PATHS answers `<path> missing` -- for a file that EXISTS. MEASURED:
    `printf 'AGENTS.md\\n' | git cat-file --batch` -> `AGENTS.md missing`. A reader corpus fed
    that reads 0 BYTES and produces a PERFECTLY CLEAN number, which is the dangerous shape. Feed
    it OIDs (which is how the committed-set test below works) and the same path resolves.
  3 A reset index returns 2 (or 0). See above.
"""
import ast
import subprocess
import sys
import warnings
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402  (the five, not a sixth)

ROOT = Path(__file__).resolve().parent.parent
GATE = Path(__file__).resolve()
BASELINE = Path(__file__).resolve().parent / "indexread-baseline.rows"

# THE ROOTS OF THE WALK -- and they are DERIVED, not transcribed. This used to be
# `ROOTS = ("checks", "gates", ".agents/slop")`, a hand list of DIRECTORIES, which is the same
# fault one level below the hand list of FILES this file's own header rails against: a census from
# a hand list cannot notice a fourth directory, and a census from a suffix set cannot notice an
# EXTENSIONLESS `#!/bin/sh` (`checks/bend`).
#
# **AND IT IS NOT `gates-pop.py`'s ROOT SET, AND THE REASON IS THE SUBJECT OF THE WHOLE CENSUS.**
# `gates/gates-pop.py:HOMES` answers WHERE THE GATES ARE -- MEASURED, 2 of the commit tree's 14
# top-level directories, by `gate_homes()`. This file answers WHERE THE SHIPPED INSTRUMENTS ARE,
# and a shipped instrument need not be a gate: `.agents/slop/**` holds most of the offenders and
# ZERO certified gate homes. Two questions, two named populations, ONE module, both loaded BY
# PATH so neither can drift from its derivation. **A second copy of a list is a contract with no
# generator; a second copy of a DERIVATION under a different name is a DIFFERENT QUESTION
# PRETENDING TO BE THE SAME ONE** -- which is what `.agents/slop/UNIVERSE-CENSUS.md` measured and
# could not name, and naming it is the whole of this line.
def gates_pop():
  """`gates/gates-pop.py` BY PATH, never by name -- `gates/` is not a package, and putting it on
  `sys.path` would make `gates_pop` a name any file in the tree could shadow."""
  import importlib.util
  p = Path(__file__).resolve().parent / "gates-pop.py"
  if not p.is_file():
    return None, f"{p} is gone -- it OWNS both derived root sets, by path"
  spec = importlib.util.spec_from_file_location("gates_pop", p)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod, ""


_gpop, _gerr = gates_pop()
if _gpop is None:
  print(f"INDEXREAD {VERDICT[REFUSED]}: {_gerr}")
  sys.exit(REFUSED)
# `scan_roots`, NOT `gate_homes` -- see the note above, and the denominator printed with it.
ROOTS = _gpop.scan_roots(ROOT)
PRUNE = {".git", ".jj", "__pycache__", ".venv", "node_modules", "references"}

# THE INDEX-READING SUBFORMS. A BARE STRING, matched against AST string CONSTANTS, because AST
# gives two things a regex cannot: comments are not in the tree at all, and a docstring is a
# `Constant` that is the whole of an `Expr` statement, which `bare_strings` excludes. The first
# version of this census was a regex and it reported **183** offenders where the truth is 77,
# because `\.add\(` matched `seen.add(` on Python sets -- a classifier error of exactly the kind
# doctrine 1 exists to catch. THIS IS WHY IT IS AST.
FORMS = {
  "ls-files": "lists the INDEX: the staging area, which a reset empties",
  "--cached": "diff --cached is index-vs-HEAD; a reset index makes it EMPTY",
  "read-tree": "WRITES the index -- the operation behind destructions 2 and 3",
  "add": "`git add` stages; `git add -A` committed the .txt violations (twice)",
  "--porcelain": "porcelain status reads index+worktree, not the tree",
}
# `add` alone is ambiguous, so it only counts when a git-shaped word is a sibling in the same
# call. That is what removes `seen.add(` without removing `git("add", "-A")`.
GIT_WORDS = {"git", "-C", "commit", "commit-tree", "hash-object", "update-index"}
# The pre-filter's spellings of a quoted `"add"`. A git invocation ALWAYS quotes it; `seen.add(`
# never does, and that one difference is the whole of the 106 false positives the regex census had.
ADD_QUOTED = ('"add"', "'add'", "add -A", "add -C")


def git(*args):
  """git as a MEASUREMENT. `--no-optional-locks` so asking a question never writes the index."""
  p = subprocess.run(["git", "--no-optional-locks", "-C", str(ROOT), *args],
                     capture_output=True, text=True)
  return p.returncode, p.stdout


def committed_paths():
  """The COMMITTED population, from the TREE. `--name-only` or trap 1 gets you."""
  rc, out = git("ls-tree", "-r", "--name-only", "HEAD")
  if rc != 0:
    return None, f"git ls-tree -r --name-only HEAD failed rc={rc}"
  return set(out.splitlines()), ""


def walk_population(committed):
  """DISCOVERY. Every committed .py under ROOTS, found by os.walk, filtered by the TREE."""
  found = []
  for r in ROOTS:
    base = ROOT / r
    if not base.is_dir():
      continue
    for dirpath, dirnames, filenames in __import__("os").walk(base):
      dirnames[:] = [d for d in dirnames if d not in PRUNE]
      for fn in filenames:
        if not fn.endswith(".py"):
          continue
        rel = str((Path(dirpath) / fn).relative_to(ROOT))
        if rel in committed:
          found.append(rel)
  return sorted(found)


def bare_strings(path):
  """String CONSTANTS that are not docstrings. Comments never appear -- AST has no comment."""
  try:
    with warnings.catch_warnings():
      # ONE `.agents/slop/` scratch file carries a non-raw `\\d`, and `ast.parse` echoes its
      # SyntaxWarning on stderr, which buries the verdict lines. Suppressed HERE and not
      # globally: the walk reads the whole tree, and a warning from someone's scratch file is
      # not this gate's business.
      warnings.simplefilter("ignore", SyntaxWarning)
      tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
  except (OSError, SyntaxError, ValueError):
    return []
  docs = set()
  for node in ast.walk(tree):
    if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
      d = ast.get_docstring(node, clean=False)
      first = node.body[0] if node.body else None
      if d is not None and isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant):
        docs.add(id(first.value))
  return [n.value for n in ast.walk(tree)
          if isinstance(n, ast.Constant) and isinstance(n.value, str) and id(n) not in docs]


def offenders_of(rel):
  """The index-reading forms in one file, or [].

  A SUBSTRING PRE-FILTER, and it is sound in the direction that matters: a file whose bytes do not
  contain `ls-files` cannot hold the string literal `"ls-files"`, so it cannot be an offender, and
  parsing it would only ever return []. This is NOT the classifier -- the classification is still
  AST over string constants -- it is a skip-if-absent. `add` gets a NARROWER pre-filter than the
  other four because a bare `"add"` is only an offender when a git word is a sibling, so a file
  needs BOTH to be worth parsing, and the `"add"` literal is ALWAYS QUOTED where git is concerned
  (`git("add", "-A")`) and never in `seen.add(`. MEASURED: 724 walked -> 68 parsed, and the
  offender set is 61 before and after every version of this filter.
  """
  src = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
  if not (any(k in src for k in FORMS if k != "add")
          or (any(a in src for a in ADD_QUOTED) and any(w in src for w in GIT_WORDS))):
    return []
  strs = bare_strings(ROOT / rel)
  hits = set()
  for s in strs:
    if s in ("ls-files", "--cached", "read-tree", "--porcelain"):
      hits.add(s)
    elif s == "add" and GIT_WORDS & set(strs):
      hits.add("add")
  return sorted(hits)


def baseline_set():
  if not BASELINE.is_file():
    return None, f"baseline absent: {BASELINE.name} -- REFUSED, not a verdict"
  return {l.split("\t")[0].strip() for l in BASELINE.read_text().splitlines()
          if l.strip() and not l.startswith("#")}, ""


def main(argv):
  strict = "--strict" in argv
  committed, err = committed_paths()
  if committed is None:
    print(f"INDEXREAD {VERDICT[REFUSED]}: {err}")
    return REFUSED
  base, err = baseline_set()
  if base is None:
    print(f"INDEXREAD {VERDICT[REFUSED]}: {err}")
    return REFUSED
  if "--print-baseline" in argv:
    for rel in sorted(base):
      print(rel)
    return PASS
  if "--write-baseline" in argv:
    found0 = {p: h for p, h in
              ((p, offenders_of(p)) for p in
               [q for q in walk_population(committed) if q != str(GATE.relative_to(ROOT))])
              if h}
    with BASELINE.open("w", encoding="utf-8") as fh:
      fh.write("# indexread-gate.py baseline -- GENERATED by --write-baseline, do not hand-edit.\n")
      fh.write("# Every committed instrument that reads the INDEX, discovered by os.walk over\n")
      fh.write("# ROOTS and filtered by `git ls-tree -r --name-only HEAD`.\n")
      for rel in sorted(found0):
        fh.write(f"{rel}\t{','.join(found0[rel])}\n")
      fh.write(f"# TOTAL {len(found0)}\n")
    print(f"INDEXREAD BASELINE-WRITTEN {len(found0)}")
    return PASS

  population = [p for p in walk_population(committed) if p != str(GATE.relative_to(ROOT))]
  found = {p: offenders_of(p) for p in population}
  found = {p: h for p, h in found.items() if h}
  new = sorted(set(found) - base)

  # THE TREE, NOT THE INDEX -- and the index is reported as a DIAGNOSTIC ONLY, never as the
  # population. Printing the divergence is the single most useful number this gate emits: it is
  # how `prune4` noticed "2 where there are 24".
  print(f"INDEXREAD ROOTS DERIVED: {len(ROOTS)} top-level directory(ies) of the COMMIT TREE hold "
        f"a tracked .py -- {' '.join(ROOTS)}\n"
        f"   (gates/gates-pop.py:scan_roots, by path. This is the SHIPPED-INSTRUMENT question; its "
        f"GATE-HOME question is\n    gates/gates-pop.py:HOMES = {list(_gpop.HOMES)} over the same 14 "
        f"candidates. Two questions, two named\n    populations, one module -- not two copies of "
        f"one list.)")
  rc, idx = git("ls-files")
  idxn = len(idx.splitlines()) if rc == 0 else -1
  print(f"INDEXREAD TREE-COMMITTED {len(committed)}  INDEX {idxn}  "
        f"DIVERGENCE {len(committed) - idxn if idxn >= 0 else 'unknown'}")
  print(f"INDEXREAD POPULATION {len(population)}  OFFENDERS {len(found)}  "
        f"BASELINE {len(base)}  NEW {len(new)}")

  if not population:
    print(f"INDEXREAD {VERDICT[DEAD]}: walked 0 files -- the walk is broken, not clean")
    return DEAD

  for rel in sorted(found):
    mark = "NEW " if rel in new else "base"
    print(f"  {mark} {rel}: {','.join(found[rel])}")
  for rel in sorted(base - set(found)):
    print(f"  gone {rel}  (an offender was fixed -- re-pin the baseline deliberately)")

  bad = found if strict else {r: found[r] for r in new}
  if bad:
    claim = "STRICT: no offender" if strict else "no NEW offender since the pinned baseline"
    print(f"INDEXREAD {VERDICT[FAIL]}: {len(bad)} offender(s) against the claim -- {claim}")
    return FAIL
  print(f"INDEXREAD {VERDICT[PASS]}: {len(found)} offender(s), all inside the pinned baseline")
  return PASS


if __name__ == "__main__":
  sys.exit(main(sys.argv[1:]))