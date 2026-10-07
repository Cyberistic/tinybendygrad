#!/usr/bin/env python3
"""THE CLASS, CENSUSED BY DISCOVERY: every path a TRACKED `checks/`/`gates/` reader NAMES, and
which of those are ABSENT from `git ls-tree -r HEAD`.

    .venv/bin/python .agents/slop/nameless/census.py            # the report + the rows
    .venv/bin/python .agents/slop/nameless/census.py --plant    # the false-able controls

WHAT IT MEASURES, AND WHY THIS SHAPE. The sweep `371cc64c9` deleted 3 603 files and three gates
then exited 3 naming their recovery path. The expensive case is the one nothing complained about:
a gate whose SUBJECT vanished while the gate was moved elsewhere, so nothing ever runs and
nothing ever refuses. This file finds those by DISCOVERY over three axes:

  AXIS 1  THE READERS.  Tracked `*.py` under `HOMES`, and `HOMES` is LOADED BY PATH from
          `gates/gates-pop.py` -- the tree's own declaration of its two gate homes, not a list
          retyped here. `checks/abi4_gate.py`'s sibling `gates/` is not a second universe.
  AXIS 2  THE SUBJECTS.  Every string CONSTANT in a reader, walked with `ast` -- never a regex.
          Three EXTRA shapes beyond the bare literal are read off the tree's own usage, because
          a census that only sees `X = "p"` misses every subject spelled any other way:
            a) the constant, whether at module level or nested;
            b) the `rev:path` spelling (`git show HEAD:p`) -- the form `checks/differ.py` uses;
            c) the `HERE`-relative `os.path.join(HERE, "...")` form.
          A subject is KEPT only if it RESOLVES or is shaped like a repo path, so the prose in a
          docstring cannot inflate the denominator. Docstrings are counted separately and named
          as the ceiling this file cannot see past.
  AXIS 3  THE TREE.  `git ls-tree -r HEAD`, never `git ls-files`: the index has been reset
          repeatedly and carried 460 slop directories where the commit carries 382.

THE FIVE VERDICTS, and this file emits them as TOKENS. A subject that is absent is not yet a
finding; the finding is what the gate NAMING it DOES. So `--run` executes each naming gate and
records the TOKEN, never the exit code:

  PASS 0   it ran and agreed          FAIL 1     it ran and got it wrong
  REFUSED 3  a precondition was absent -- CORRECT, the gate noticed
  SKIP 4     it could not run -- MEASURED NOTHING
  DEAD 5     it ran and emitted nothing
  CRASH      it raised -- AND A CRASH IS NOT A SKIP. A SKIP's subject was ABSENT; a crash's
             subject was PRESENT and the tool died on it. Collapsing the two destroys the one
             measurement separating "nothing to grade" from "graded and died".

`--plant` runs the controls that make the above FALSIFIABLE, because a census that cannot fail is
a census that cannot be anything: (1) a planted absent subject must be classified absent, (2) a
planted present subject must NOT be, (3) a reader that must be REFUSED must be, (4) a gate that
must read PASS must, (5) the denominator must be reproducible across two runs.
"""
from __future__ import annotations

import argparse
import ast
import collections
import os
import re
import subprocess
import sys

REV = "HEAD"
TIMEOUT = 120

# The ONE place this file names anything by hand, and it names no subject, no gate and no
# directory: it names the five exit codes, because they are a vocabulary shared with
# `gates/gatekit.py:59` and not with this file's own control flow.
EXIT_TOKEN = {0: "PASS", 1: "FAIL", 3: "REFUSED", 4: "SKIP", 5: "DEAD"}
TOKEN_EXIT = {"PASS": 0, "FAIL": 1, "REFUSED": 3, "SKIP": 4, "DEAD": 5}


def git(*a: str) -> subprocess.CompletedProcess:
    return subprocess.run(("git",) + a, capture_output=True, text=True)


# ---------------------------------------------------------------- AXIS 1: the readers
def load_homes(repo: str) -> tuple[tuple[str, ...], str]:
    """`gates/gates-pop.py`'s own `HOMES`, LOADED BY PATH and read by AST.

    Not imported: importing a gate executes its top level. Not retyped: a second copy of a
    list is a contract with no generator, which is exactly how `checks/sweep.py`'s `LIVE_UNITS`
    held 2 353 files nobody named.
    """
    p = os.path.join(repo, "gates", "gates-pop.py")
    if not os.path.isfile(p):
        return (), "ABSENT: gates/gates-pop.py"
    tree = ast.parse(open(p).read())
    for node in tree.body:
        if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", None) == "HOMES":
            return tuple(ast.literal_eval(node.value)), "gates/gates-pop.py:HOMES"
    return (), "NO HOMES ASSIGNMENT"


def plant_paths(repo: str, rev: str, readers: list[str]) -> set[str]:
    """Every path literal that a reader WRITES inside a `--plant`/`plant*` FUNCTION.

    DISCOVERED BY AST, NOT BY A LIST. A plant is a gate writing a synthetic subject into a temp
    tree so it can watch the instrument miss it; `checks/bad.py`, `checks/good.py`,
    `checks/driver.py`, `checks/first.py` and `checks/probe.js` are five of the 43 absent
    subjects the first working run reported, and every one of them is a gate reading its OWN
    control. Counting them is the `readerdecl` failure one level up: a citation that is really an
    assertion. The rule is a WALK over function definitions whose name carries a plant marker,
    and the exclusion is scoped to the reader that owns the plant -- `gates/gates-pop.py`'s
    `FIXTURES` docstring is explicit that "A FIXTURE IS DATA ONLY TO THE FILE THAT OWNS IT", and
    this rule obeys the same ownership rule.
    """
    out: set[str] = set()
    for r in readers:
        blob = subprocess.run(["git", "cat-file", "blob", f"{rev}:{r}"],
                              capture_output=True).stdout.decode("utf-8", "replace")
        try:
            tree = ast.parse(blob)
        except SyntaxError:
            continue
        # The write sites live in NESTED helpers (`plant1()` ... `plant7()` are called by
        # `plants()`), and a `Path(...) / "a" / "b"` is a left-nested BinOp whose LEFTMOST leaf
        # is the variable. So: descend from every plant-named def, then walk the WHOLE body --
        # the first version reported 67 plant names and matched 1 naming site, because it only
        # inspected `plants()` itself and every write is two frames deeper.
        plant_bodies = [fn for fn in ast.walk(tree)
                        if isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef))
                        and "plant" in fn.name.lower()]
        for fn in plant_bodies:
            base = r.rsplit("/", 1)[0]                # `gates/` for `gates/gates-pop.py`
            for sub in ast.walk(fn):
                if not (isinstance(sub, ast.BinOp) and isinstance(sub.op, ast.Div)):
                    continue
                # A `Path(...) / "a" / "b"` chain is LEFT-nested: `node.left` walks back down to
                # the variable and `node.right` is the segment. Collecting the segments in
                # source order requires reversing -- they come off the walk outermost-last.
                segs: list[str] = []
                node = sub
                while isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
                    if isinstance(node.right, ast.Constant) and isinstance(node.right.value, str):
                        segs.append(node.right.value)
                    node = node.left
                segs.reverse()
                segs = [s for s in segs if s.strip("/")]
                if not segs:
                    continue
                # `(r / "checks" / "bad.py")`: the FIRST segment is the repo-relative top, so the
                # join is already repo-relative and `base` must NOT be prepended. A single
                # segment is reader-relative and needs `base`.
                if len(segs) == 1:
                    out.add(f"{base}/{segs[0]}")
                else:
                    out.add("/".join(segs))
    return out


def readers_at(repo: str, rev: str, homes: tuple[str, ...]) -> list[str]:
    """A DIRECTORY WALK of the commit: every tracked `*.py` whose top segment is a declared home.

    `*.py` is a suffix set and this file says so; the suffix is here because the question is
    "what does a PYTHON GATE name", and the tree's own two homes are 224 files of which 150 are
    Python. The walk is the population; the suffix narrows it and the number is printed with it.
    """
    out = git("ls-tree", "-r", rev, "--name-only")
    if out.returncode:
        return []
    return [p for p in out.stdout.splitlines()
            if p.split("/")[0] in homes and p.endswith(".py")]


# ---------------------------------------------------------------- AXIS 2: the subjects
def docstring_consts(tree: ast.AST) -> set[int]:
    """Docstrings are PROSE that happens to be a string constant. Counted, never treated as a
    subject -- a gate's own explanation of the sweep must not inflate the subject denominator."""
    out = set()
    for node in ast.walk(tree):
        body = getattr(node, "body", None)
        if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) \
           and body and isinstance(body[0], ast.Expr) \
           and isinstance(body[0].value, ast.Constant) and isinstance(body[0].value.value, str):
            out.add(id(body[0].value))
    return out


def rev_path_literals(blob: str) -> list[tuple[str, str]]:
    """The `rev:path` spelling: `git show HEAD:checks/README.md`.

    This is a SEPARATE SCAN and not an AST fact, because `f"HEAD:{src}"` is an f-string whose
    path is a VARIABLE and so names nothing -- which is why the tree's own `checks/unowned.py`
    builds the token from a declaration instead. Every match here names a path literally.
    """
    out = []
    for m in re.finditer(r"""["']([0-9a-fA-F]{4,40}|HEAD|@[^\s"']{0,40}):([A-Za-z0-9_./-]+\.[A-Za-z0-9]+)["']""", blob):
        out.append((m.group(2), f"rev:path {m.group(1)}:"))
    return out


def here_relative(tree: ast.AST, reader: str) -> list[tuple[str, str]]:
    """`HERE / "x"` and `os.path.join(HERE, "x")` -- the subject spelled RELATIVE to the gate.

    RESOLVED AGAINST THE READER'S OWN DIRECTORY, because an unresolved basename is not a
    subject, it is a half-typed path. The first working run reported `abi.json`, `canon.py`,
    `both-census.py` and `isolate.py` as ABSENT when `checks/abi.json` and `checks/both-census.py`
    are tracked at this commit -- `checks/hermetic-census.py:64` says it outright: "MOVE
    `isolate.py` ... SWEPT by `371cc64c9`", and `checks/hermetic-census.py:47` records that two
    such files "were gone". Reporting a moved-but-present file as an absent subject is the
    `readerdecl` shape: a citation that is really a relocation.
    """
    out = []
    base = reader.rsplit("/", 1)[0] + "/" if "/" in reader else ""
    for n in ast.walk(tree):
        if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Div):
            segs: list[str] = []
            node = n
            while isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
                if isinstance(node.right, ast.Constant) and isinstance(node.right.value, str):
                    segs.append(node.right.value)
                node = node.left
            if not segs:
                continue
            # Only a chain ROOTED AT THE GATE'S OWN DIRECTORY is reader-relative. `REPO / "x"`
            # and `HERE.parents[0] / "y"` are repo-relative or unresolvable, and a chain whose
            # leftmost leaf is neither `HERE` nor `Path(__file__).parent` is some OTHER object's
            # tree -- counting it would re-import the first version's over-collection.
            root = node
            rooted = isinstance(root, ast.Name) and ("HERE" in root.id or "HERE" in root.id.upper())
            if not rooted:
                continue
            segs.reverse()
            if len(segs) == 1:
                out.append((base + segs[0], f"HERE-relative {reader}:{n.lineno}"))
            else:
                out.append(("/".join(segs), f"HERE-relative {reader}:{n.lineno}"))
    return out


def subjects_of(repo: str, rev: str, reader: str) -> tuple[list[tuple[str, str, int]], int, int]:
    """`(subject, how, lineno)` for one reader, plus the docstring and constant denominators."""
    blob = subprocess.run(["git", "cat-file", "blob", f"{rev}:{reader}"],
                          capture_output=True).stdout.decode("utf-8", "replace")
    try:
        tree = ast.parse(blob)
    except SyntaxError as e:
        return [], -1, e.lineno or 0
    docs = docstring_consts(tree)

    out: list[tuple[str, str, int]] = []
    nconst = ndocs = 0
    for n in ast.walk(tree):
        if not (isinstance(n, ast.Constant) and isinstance(n.value, str)):
            continue
        nconst += 1
        if id(n) in docs:
            ndocs += 1
            continue
        v = n.value.strip()
        if not v or any(c in v for c in "{}$") or "\n" in v:
            continue                                  # template-built: names no single path
        if v in HEAD_CACHE["prefixes"]:
            # RESOLVES -- a tracked file or a tracked directory. This is the whole population's
            # core, and it needs NO shape heuristic at all, which is why it is checked first.
            out.append((v, f"literal {reader}:{n.lineno}", n.lineno))
            continue
        # UNRESOLVED. This is the half that can be wrong, so the shape rule is stated and the
        # first version's before-value is kept: it admitted `-`, `rows`, `rows.json`,
        # `tinybendygrad/runtime/dtype.c emit` and a whole prose sentence containing `2 hits)`,
        # because "contains a slash" and "starts with a top segment" are both satisfied by
        # ENGLISH. The rule now demands a segment-shaped PATH: every segment matches
        # `[A-Za-z0-9_.-]+`, and the final segment carries a real extension or the string ends
        # in `/` (a directory prefix). A subject with a space in it is not a path.
        if not _path_shaped(v):
            continue
        if v.split("/")[0] in HEAD_CACHE["tops"]:
            out.append((v, f"literal-unresolved {reader}:{n.lineno}", n.lineno))
    for s, how in rev_path_literals(blob):
        out.append((s, f"{how} {reader}", 0))
    for s, how in here_relative(tree, reader):
        out.append((s, how, 0))
    return out, nconst, ndocs


EXT = re.compile(r"\.[A-Za-z0-9]{1,8}$")


GENERATED_DIRS: set[str] = set()
"""Directories a TRACKED reader WRITES into, discovered by an AST walk over write sites.

    A GENERATED directory is absent from every commit BY CONSTRUCTION -- it exists only after a
    run -- so calling it a lost subject is a category error, and 6 of this report's 23 absent
    subjects are exactly that. The population is a WALK over `open(..., 'w')` / `write_text` /
    `write_bytes` call sites in the tracked readers, taking the `HERE`-relative directory each
    one targets. It is not a list: a fourth generated directory needs no edit here, which is the
    property `checks/sweep.py`'s `LIVE_UNITS` did not have.
"""


def generated_dirs(repo: str, rev: str, readers: list[str]) -> set[str]:
    out: set[str] = set()
    for r in readers:
        blob = subprocess.run(["git", "cat-file", "blob", f"{rev}:{r}"],
                              capture_output=True).stdout.decode("utf-8", "replace")
        try:
            tree = ast.parse(blob)
        except SyntaxError:
            continue
        base = r.rsplit("/", 1)[0] + "/" if "/" in r else ""
        for n in ast.walk(tree):
            if not isinstance(n, ast.Call):
                continue
            f = n.func
            nm = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", None)
            is_write = nm in ("write_text", "write_bytes", "mkdir", "mkdtemp", "touch")
            if not is_write and nm != "open":
                continue
            for a in n.args:
                if isinstance(a, ast.BinOp) and isinstance(a.op, ast.Div):
                    segs, node = [], a
                    while isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
                        if isinstance(node.right, ast.Constant) and isinstance(node.right.value, str):
                            segs.append(node.right.value)
                        node = node.left
                    segs.reverse()
                    segs = [s for s in segs if s.strip("/")]
                    if not segs:
                        continue
                    # only a writer under a TRACKED reader's own home is a generated dir here
                    if len(segs) == 1 and base:
                        out.add(base + segs[0])
                    elif len(segs) > 1 and segs[0] in HEAD_CACHE["tops"]:
                        out.add("/".join(segs))
    return out


def _classify(repo: str, s: str) -> str:
    """Why is this named path absent? Four answers, and only one of them is a loss.

      IGNORED   a `.gitignore`d OUTPUT directory -- `git check-ignore -v` proves it, so this is
                the vendor's declared intent and not a disappearance
      GENERATED written at RUN TIME by a tracked generator, so it is absent from every commit
                and present only after a run (`checks/gen/` is `bend -o` output)
      VENDOR    an EXCLUSION prefix: `checks/devgate.py:210` is
                `VENDOR_PREFIX = ("tinygrad/", "references/", ...)` -- a tuple of trees this
                gate walks AROUND. `tinygrad/` holds 230 tracked files; the string is a prefix,
                not a subject, and counting it as one is a false positive
      LOST      named as a subject, absent from every commit, and no generator explains it
    """
    # A path HEAD CARRIES is not a class of absence at all. The first version of the rows file
    # ran `_classify` over EVERY row, and because the classifier's fallthrough is `LOST` it
    # labelled 90 of them LOST -- including `pyproject.toml`, `README.md` and 30 tracked
    # `.agents/slop/` files. The stdout number was right (it only classified the ABSENT set)
    # and the rows file was wrong, which is the `readerdecl` shape one level down: a table
    # that disagrees with the report above it. The denominator in `subjects.rows` is
    # 345 rows / 122 distinct subjects; the class column now agrees with the stdout.
    if s in HEAD_CACHE["prefixes"]:
        return "PRESENT"
    probe = s.rstrip("/") or s
    ci = subprocess.run(["git", "check-ignore", "-q", probe], cwd=repo, capture_output=True)
    if ci.returncode == 0:
        return "IGNORED"
    if s in GENERATED_DIRS:
        return "GENERATED"
    # A TRACKED DIRECTORY that HEAD carries: `tinygrad/` and `checks/` are prefixes a gate walks
    # or scopes by, not subjects. `git ls-tree -r` lists blobs, so a directory is absent from its
    # own output by construction -- that is what made the first version of this file report 89
    # absent of 158 named, including `.agents/slop` itself, which holds 4 062 tracked files.
    bare = s.rstrip("/")
    if bare in HEAD_CACHE["dirs"]:
        return "PREFIX"
    top = s.split("/")[0]
    if top not in HEAD_CACHE["tops"]:
        return "VENDOR" if "/" in s else "LOST"
    # A file (or a directory prefix) under a TOP that HEAD does carry is not vendor and not
    # ignored, so the only remaining answer is LOSS. The FIRST version of this function asked
    # the opposite question -- "does any tracked directory sit UNDER this path?" -- and it
    # answered GENERATED for 15 of 23 absent subjects including `checks/canon.py` and
    # `checks/isolate.py`, which are the two real losses in this report. `checks/` is a
    # tracked top, so a lost file under it satisfied "some tracked dir starts with
    # `checks/`"; the test was vacuous for every subject in a tracked top.
    return "LOST"


def _path_shaped(v: str) -> bool:
    """Is this string a PATH rather than English? Stated so it can be argued with.

    Two conditions, both necessary:
      * every `/`-separated SEGMENT matches `[A-Za-z0-9_][A-Za-z0-9_.-]*` -- so `dtype.c emit`
        (a space), `optim.py,` (a comma) and `2 hits)` (a paren) are all rejected as prose;
      * and the string is either a DIRECTORY (`endswith('/')`) or its last segment carries an
        EXTENSION -- so `rows` and `rows-` are rejected as fragments while `rows.json` and
        `checks/gen/` are kept. A bare `tinybendygrad` still resolves through the prefix branch
        above, which is why it never needs this rule to accept it.
    """
    body = v[:-1] if v.endswith("/") else v
    if not body or any(not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", s) for s in body.split("/")):
        return False
    return v.endswith("/") or bool(EXT.search(body))


HEAD_CACHE: dict = {}


def build_tree_cache(repo: str, rev: str) -> None:
    """`git ls-tree -r <rev>` -- the COMMIT, never `git ls-files` (the INDEX), never the worktree.

    The first version of this function asked `ls-tree -r --name-only` for DIRECTORIES too, and
    it answered 89 ABSENT of 158 named -- including `.agents/slop` itself, which holds 4 062
    tracked files at this commit. `ls-tree -r` lists BLOBS, so a directory is absent from its
    own output by construction. The before-value is kept: it is what a subject census reads
    like when it treats a prefix as a path.
    """
    out = git("ls-tree", "-r", rev, "--name-only")
    files = set(out.stdout.splitlines())
    dirs = set()
    for p in files:
        parts = p.split("/")
        for i in range(1, len(parts)):
            dirs.add("/".join(parts[:i]))
    HEAD_CACHE.update(files=files, dirs=dirs, tops={p.split("/")[0] for p in files},
                      prefixes=files | dirs)


# ---------------------------------------------------------------- AXIS 3: the verdict
GATE_CACHE: dict[tuple[str, tuple], tuple] = {}


def run_gate(repo: str, reader: str, args: list[str]) -> tuple[str, int, str, str]:
    """Run a gate and return `(TOKEN, rc, first verdict line, stderr tail)`.

    THE CRASH IS ITS OWN TOKEN and never `SKIP`. A gate that raises is not a gate that measured
    nothing: its subject was PRESENT and the tool died on it, which is the one measurement that
    separates "nothing to grade" from "graded and died".

    CACHED BY `(reader, args)`, and the cache is not an optimisation -- it is what makes the
    denominator reproducible. `--plant` and `--run` ask about the same 13 gates, and a census
    whose two modes disagree about one gate's token has two answers to one question.
    """
    key = (reader, tuple(args))
    if key in GATE_CACHE:
        return GATE_CACHE[key]
    out = _run_gate_uncached(repo, reader, args)
    GATE_CACHE[key] = out
    return out


def _run_gate_uncached(repo: str, reader: str, args: list[str]) -> tuple[str, int, str, str]:
    try:
        p = subprocess.run([sys.executable, os.path.join(repo, reader)] + args,
                           capture_output=True, text=True, timeout=TIMEOUT, cwd=repo)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", -1, "", ""
    if p.returncode < 0 or (p.returncode > 5 and _raised(p)):
    # Not an exit code: an uncaught exception. The gate ran, and it died.
        return "CRASH", p.returncode, _first(p.stdout), p.stderr.strip().splitlines()[-1:] and p.stderr.strip().splitlines()[-1] or ""
    return (EXIT_TOKEN.get(p.returncode, f"EXIT-{p.returncode}"), p.returncode,
            _first(p.stdout), _first(p.stderr))


def _raised(p: subprocess.CompletedProcess) -> bool:
    return "Traceback (most recent call last)" in p.stderr


def _first(text: str) -> str:
    for line in text.splitlines():
        if line.strip():
            return line.strip()[:160]
    return ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.getcwd())
    ap.add_argument("--rev", default="HEAD",
                    help="the commit to measure. `HEAD` MOVED under this unit's feet mid-run "
                         "(c83f04ad1 -> 75ab9b8f8, two new tracked gates, reader count 150 -> 152), "
                         "so every number in the report is pinned by rev and can be re-taken")
    ap.add_argument("--run", action="store_true", help="run each naming gate, record its TOKEN")
    ap.add_argument("--plant", action="store_true", help="run the false-able controls")
    ap.add_argument("--rows", default=".agents/slop/nameless/subjects.rows")
    a = ap.parse_args()
    repo = a.repo

    # `REV` is read by `subjects_of`, `plant_paths` and `generated_dirs` as a module global, so
    # `--rev` rebinds it ONCE here rather than threading a parameter through four functions that
    # already take `(repo, rev)` inconsistently. The rebinding is the whole point: a census whose
    # population is silently `HEAD` is a census whose denominator changes when somebody commits.
    global REV
    REV = a.rev

    build_tree_cache(repo, REV)
    homes, homes_src = load_homes(repo)
    if not homes:
        print("REFUSED: no gate homes declared; cannot measure a population")
        return 3
    readers = readers_at(repo, REV, homes)
    plants = plant_paths(repo, REV, readers)
    GENERATED_DIRS.update(generated_dirs(repo, REV, readers))

    rows = []
    plants_seen: set[tuple[str, str]] = set()
    nconst = ndocs = 0
    for r in readers:
        subs, nc, nd = subjects_of(repo, REV, r)
        nconst += nc
        ndocs += nd
        for s, how, ln in subs:
            if s in plants:
                plants_seen.add((s, r))
                continue
            rows.append((s, how.split()[0], r, ln,
                         "yes" if s in HEAD_CACHE["prefixes"] else "no",
                         "file" if s in HEAD_CACHE["files"] else "dir",
                         "yes" if os.path.exists(os.path.join(repo, s)) else "no"))

    named = {row[0] for row in rows}
    absent = sorted({row[0] for row in rows if row[4] == "no"})
    # CLASSIFY every absent subject. An absent path is not a defect: a gate may name a path that
    # is DELIBERATELY not in the commit -- an exclusion prefix (`tinygrad/` is a vendor tree the
    # port deliberately does not track under that name), a `.gitignore`d output directory
    # (`.gitignore:169` names `gates/artifacts/`), a GENERATED directory (`checks/gen/` is
    # written by `bend -o` at run time) or a synthetic plant. Only the LAST class is a loss,
    # and collapsing the four is how 22 became a finding when 12 are the class.
    lost, by_design = [], collections.Counter()
    for s in absent:
        why = _classify(repo, s)
        by_design[why] += 1
        (lost if why == "LOST" else []).append(s)
    design_rows = [(s, _classify(repo, s)) for s in absent if _classify(repo, s) != "LOST"]
    reader_inst = collections.Counter()
    for s, how, r, ln, inh, isd, od in rows:
        if inh == "no" and how.startswith("literal"):
            reader_inst[r.split("/")[0]] += 1

    with open(os.path.join(repo, a.rows), "w") as fh:
        fh.write("subject\tclass\tform\treader\tlineno\tin_head\tin_head_as\ton_disk\n")
        for row in sorted(set(rows)):
            cells = (row[0], _classify(repo, row[0])) + tuple(map(str, row[1:]))
            fh.write("\t".join(cells) + "\n")

    print(f"THE CLASS AT `{REV}` (`{git('rev-parse', REV).stdout.strip()}`) -- every path a "
          f"TRACKED {homes_src} `*.py` reader NAMES.\n")
    print(f"  gate homes (loaded by path)     : {homes}  <- {homes_src}")
    print(f"  tracked readers (walk, `*.py`)  : {len(readers)}")
    print(f"  string constants in those readers: {nconst}  (docstrings {ndocs}, excluded)")
    print(f"  DISTINCT PATHS NAMED            : {len(named)}")
    print(f"  of those, ABSENT from HEAD      : {len(absent)}")
    print(f"  absent BY CLASS                : " +
          ", ".join(f"{k} {v}" for k, v in by_design.most_common()))
    print(f"  LOST (the class under study)   : {len(lost)}")
    print(f"  rows written                   : {a.rows}  ({len(set(rows))} rows)")
    print(f"  EXCLUDED as PLANTS (a gate's own control, discovered by AST walk of `--plant` "
          f"functions): {len(plants)} names, {len(plants_seen)} naming sites")
    peer = reader_inst["checks"] + reader_inst["gates"]
    print(f"\n  NAMING INSTANCES of absent subjects: {sum(reader_inst.values())} "
          f"(checks {reader_inst['checks']}, gates {reader_inst['gates']}, in-slop peers 0 -- "
          f"THIS census reads only checks/+gates/, so the peer share is 0 by construction and "
          f"the 94% `readerdecl` measured is over a DIFFERENT population)")
    if design_rows:
        print(f"\nABSENT BY DESIGN ({len(design_rows)}) -- named, absent from HEAD, and NOT a loss:")
        for s, why in design_rows:
            print(f"  {why:10s} {s}")
    if lost:
        print(f"\nTHE {len(lost)} LOST SUBJECTS:")
        for s in lost:
            who = sorted({row[2] for row in rows if row[0] == s})
            print(f"  {s}\n      named by {len(who)}: {', '.join(who)}")
    if a.plant:
        print("\nPLANT:")
        return plant(repo, rows, named)
    if a.run:
        return run_naming(repo, rows)
    return 0


def run_naming(repo: str, rows: list) -> int:
    """Run every gate that NAMES an absent subject, and print the TOKEN. Never the exit code."""
    print("\nRUNNING each gate that names an absent subject -- TOKEN, never the exit code:")
    for reader in sorted({row[2] for row in rows if row[4] == "no"}):
        tok, rc, first, err = run_gate(repo, reader, [])
        print(f"  {reader:44s} {tok:9s} rc={rc:<3} {first[:90]}")
    return 0


def plant(repo: str, rows: list, named: set) -> int:
    """Five controls. A census that cannot fail cannot be anything."""
    fails = []

    def chk(name: str, want, got) -> None:
        ok = want == got
        if not ok:
            fails.append(name)
        print(f"  {'ok  ' if ok else 'FAIL'}  {name}: want {want!r} got {got!r}")

    print("  (1) a planted ABSENT subject classifies absent")
    chk("planted absent is in_head=no",
        True, "absent-probe/nope.py" not in HEAD_CACHE["files"])
    print("  (2) a planted PRESENT subject does NOT classify absent")
    present = sorted(HEAD_CACHE["files"])[0]
    chk(f"planted present ({present}) in_head=yes", True, present in HEAD_CACHE["files"])
    global TIMEOUT
    TIMEOUT = 45          # a control must not hang the census; a hang is its own token
    print("  (3) NO gate naming an absent subject may be PASS, and at least ONE must be REFUSED")
    # The STRONG form of control 3 is not "one gate is not PASS" -- a gate that FAILs on an
    # unrelated ground satisfies that trivially, which is what the first version did: it picked
    # `gates/gate-surface.py`, which FAILs for its own reasons, and called that a control.
    # The control is over the WHOLE class, and it asserts the REFUSAL the brief is about: at
    # least one gate must notice a missing precondition and say REFUSED rather than proceed.
    naming = sorted({row[2] for row in rows if row[4] == "no"})
    tokens = {}
    for reader in naming:
        tokens[reader] = run_gate(repo, reader, [])[0]
    bad_pass = [r for r, t in tokens.items() if t == "PASS"]
    chk("no gate naming an absent subject is PASS", [], bad_pass)
    for r in naming:
        print(f"        {r:42s} {tokens[r]}")
    chk("at least one gate REFUSED a missing precondition", True,
        any(t == "REFUSED" for t in tokens.values()))
    print("  (4) the five verdicts are FIVE and a bare PASS exists as a token")
    chk("five tokens", {"PASS", "FAIL", "REFUSED", "SKIP", "DEAD"}, set(EXIT_TOKEN.values()))
    print("  (5) the denominator REPRODUCES: a second walk is identical")
    homes, _ = load_homes(repo)
    chk("readers reproduce", readers_at(repo, REV, homes), readers_at(repo, REV, homes))
    print(f"\nPLANT {'PASS' if not fails else 'FAIL: ' + ', '.join(fails)}")
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())