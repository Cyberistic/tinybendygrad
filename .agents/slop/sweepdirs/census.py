#!/usr/bin/env python3
"""Which `.agents/slop/<dir>` do this tree's instruments WRITE and READ?

ONE RESOLVER, LOADED BY PATH from `checks/sweep.py`; the only thing that varies is the
POPULATION -- which files count as an instrument.  A second copy of the resolver would be a
second vocabulary with no generator, which is the defect this whole tree keeps paying for.

    .venv/bin/python .agents/slop/sweepdirs/census.py
"""
from __future__ import annotations

import ast
import importlib.util
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))


def load(name: str, rel: str):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, rel))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


SW = load("sweep", "checks/sweep.py")
CODE_EXT = (".py", ".sh", ".mjs", ".js", ".bend")
# SPELLED ONCE. `SLOP` is `sweep.py`'s own prefix (consumed, not copied, as `slop_file` below
# already does) because a census of `.agents/slop/<dir>` that hardcodes the prefix is a second copy
# of a list with no generator.
PY = ".py"
NON_PY = tuple(e for e in CODE_EXT if e != PY)
SLOP = SW.SLOP_PREFIX + "/"


def committed_paths() -> set[str] | None:
    """THE COMMIT TREE, unfiltered -- or `None` if git did not answer.

    `git ls-tree -r -z --name-only HEAD`, which is `checks/slop-declare.py:148` IN INTENT: one
    population read out of `.git/objects`, so no index reset can reach it. `--no-optional-locks` so
    asking the question never writes the index either.

    **THE PATHSPEC IS ABSENT, AND NOT FOR STYLE.** MEASURED: `git ls-tree -r --name-only HEAD --
    '*.py'` prints **0 rows and exits 0**, and `:(glob)` is `fatal: pathspec magic not supported by
    this command: 'glob'`. `ls-tree` has no pathspec vocabulary at all, so a pathspec here is a
    **SILENT ZERO** -- the one failure this census cannot be allowed to have, because `writes 0
    reads 0` reads as "nothing in this tree touches .agents/slop". `None` is returned instead of
    `set()` so the caller can tell the two apart, as `slop-declare.py:142` does.

    **AND WHAT IT REPLACES IS NOT A TIDY-UP.** `git ls-files` names the INDEX, and `jj` COLOCATES
    INTO GIT'S INDEX ON EVERY SNAPSHOT, arming an INTENT-TO-ADD PLACEHOLDER -- the empty blob -- for
    every untracked file. MEASURED on this tree: **1 096** placeholders carrying
    `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` (`git hash-object -t blob /dev/null`), **190** of
    them ending `.py`, of which **515 tree-wide hold real non-empty content ON DISK**. So the
    population answered **1 987** `.py` where the tree holds **1 835**: **154 files that are not
    committed, and 2 committed files it never saw** -- both of them GATES, `gates/upstream-pow-
    dtype-gate.py` and `gates/upstream-promo-lattice-gate.py`.

    **`--with-tree=HEAD` IS NOT THE FIX AND WAS MEASURED**: it answers **1 989** and every one of
    the **190** placeholders survives, because it PRETENDS the tree's paths are IN the index. It is
    a UNION of the two snapshots, which is the defect with a `--with-tree` on it.
    """
    r = subprocess.run(["git", "--no-optional-locks", "ls-tree", "-r", "-z", "--name-only", "HEAD"],
                       cwd=ROOT, capture_output=True, text=True)
    return None if r.returncode else {p for p in r.stdout.split("\0") if p}


def census(files: list[str], namer=SW.slop_dir) -> tuple[set[str], set[str]]:
    """`(written, read)` `.agents/slop/...` over this file list, by AST, with sweep's resolver."""
    writes: set[str] = set()
    reads: set[str] = set()
    for rel in files:
        try:
            tree = ast.parse(open(os.path.join(ROOT, rel), errors="replace").read())
        except (OSError, SyntaxError):
            continue
        for body, env in SW._scopes(tree):
            for node in ast.walk(ast.Module(body=list(body), type_ignores=[])):
                if not isinstance(node, ast.Call):
                    continue
                for read, out in ((False, writes), (True, reads)):
                    for slot in SW._path_slots(node, env, read) or []:
                        d = namer(SW._resolve(slot, env))
                        if d:
                            out.add(d)
    return writes, reads


def slop_file(value: str) -> str | None:
    """`slop_dir`'s finer sibling: the FILE a write names, or `None`.

    `slop_dir` keeps ONE component; the evidence names a FILE, so the truncation is where an
    ownership claim about `residue/000-the-residue.md` becomes a claim about all of `residue/`.
    Every component must be nameable -- one opaque component makes the whole path opaque.
    """
    if SLOP not in value:
        return None
    tail = value.split(SLOP, 1)[1].strip("/")
    if not tail or SW.UNKNOWN_MARK in tail or "." not in tail.rsplit("/", 1)[-1]:
        return None
    return SLOP + tail


REDIRECT = re.compile(r">>?\s*['\"]?|(?:\btee\b|\bcp\b|\bmv\b|\bcat\b)\s+.*?['\"]?(?=[^\s'\"]*\.agents/slop/)")
SLOPT = re.compile(r"\.agents/slop/([A-Za-z0-9_-]+)")


def shell_belt(files: list[str]) -> set[str]:
    """A REGEX over the tree's own write sites for the half an AST walk over `.py` cannot see:
    a shell redirect (`>`, `>>`, `tee`, `cp`, `mv`) whose operand names `.agents/slop/<dir>`."""
    out: set[str] = set()
    for rel in files:
        try:
            text = open(os.path.join(ROOT, rel), errors="replace").read()
        except OSError:
            continue
        for line in text.splitlines():
            if line.lstrip().startswith("#"):
                continue
            if REDIRECT.search(line) and ".agents/slop/" in line:
                out |= {".agents/slop/" + m for m in SLOPT.findall(line)}
    return out


def scope(name: str) -> list[str]:
    """The four populations, each a PREDICATE over ONE tree read.

    `code` is a DISK WALK over `checks/`+`gates/` that never consults git, so it is left exactly
    as it was. The other three were `git ls-files` PATHSPECS, and a pathspec is not available
    (`committed_paths`, above), so each is spelled here as the predicate git's pathspec turned out to
    evaluate to. **THOSE THREE EQUIVALENCES ARE MEASURED AGAINST GIT, NOT ASSUMED** --
    `git ls-files -- '*.py'` ≡ `endswith(".py")` **SAME**; `:(glob).agents/slop/**/*.py` ∪
    `.agents/slop/*.py` ≡ `startswith(".agents/slop/") and endswith(".py")` **SAME**; the four
    `*.sh|*.mjs|*.js|*.bend` ≡ `endswith(CODE_EXT - {".py"})` **SAME** -- each `diff`ed against the
    index it replaces, so the only thing this change moves is WHICH SNAPSHOT answers.

    `endswith` over a TUPLE is the `nonpy` case, so no per-extension branch exists to rot.

    **THE `os.path.lexists` FILTER IS GONE, AND ITS ABSENCE WAS MEASURED, NOT ASSUMED**: a tree
    path absent from the worktree is what `census()`'s `except OSError` already swallowed, so
    dropping the filter could only ever have ADDED rows -- MEASURED **0** in all three scopes
    (`tree` 1 835, `agents` 760, `nonpy` 607, absent 0/0/0). Membership now comes from ONE snapshot
    and the readers keep tolerating absence.
    """
    paths = committed_paths()
    if paths is None:
        raise SystemExit("`git ls-tree -r HEAD` did not answer, so the population is UNKNOWN, not "
                         "empty: printing `0 instruments` off a broken walk reads as a clean tree")
    if name == "code":            # sweep._instrument_files' own population: disk, checks/ + gates/
        return [os.path.relpath(os.path.join(dp, f), ROOT)
                for base in ("checks", "gates")
                for dp, _d, fs in os.walk(os.path.join(ROOT, base))
                for f in sorted(fs) if f.endswith(".py")]
    if name == "tree":
        return sorted(p for p in paths if p.endswith(PY))
    if name == "agents":
        return sorted(p for p in paths if p.startswith(SLOP) and p.endswith(PY))
    if name == "nonpy":           # the regex belt's population: every OTHER code file
        return sorted(p for p in paths if p.endswith(NON_PY))
    raise SystemExit(f"unknown scope {name}")


def main() -> int:
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()
    print(f"# census {stamp}  HEAD {head}")
    for name in ("code", "tree", "agents"):
        files = scope(name)
        w, r = census(files)
        print(f"# {name:8s} {len(files):5d} .py -> writes {len(w):3d} {sorted(w)}")
        print(f"# {'':8s} {'':5s}      reads  {len(r):3d} {sorted(r)}")
        print(f"# {'':8s} {'':5s}      writes-reads {len(w - r):3d} {sorted(w - r)}")
    files = scope("nonpy")
    belt = shell_belt(files)
    pybelt = shell_belt(scope("tree"))
    print(f"# nonpy    {len(files):5d} code files -> shell-belt {len(belt):3d} {sorted(belt)}")
    print(f"# py-belt  {len(scope('tree')):5d} .py files -> shell-belt {len(pybelt):3d} {sorted(pybelt)}")
    wf, _rf = census(scope("tree"), namer=slop_file)
    print(f"# files    {len(scope('tree')):5d} .py -> files written {len(wf):3d}: "
          + "  ".join(sorted(wf)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
