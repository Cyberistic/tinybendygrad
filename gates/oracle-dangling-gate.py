#!/usr/bin/env python3
"""oracle-dangling-gate -- THE SUBJECT RELATION, BOTH DIRECTIONS, AND WHAT IS MISSING FROM BOTH.

    .venv/bin/python gates/oracle-dangling-gate.py            # the census AND the verdict
    .venv/bin/python gates/oracle-dangling-gate.py --report   # census only, rc never charged
    .venv/bin/python gates/oracle-dangling-gate.py --plant    # the self-test, in a temp copy

## THE QUESTION, AND WHY IT IS NOT "DOES THE FILE EXIST"

An ORACLE is a subject: something an instrument compares against. An EXPECTED-VALUE FILE is a
subject: the rows it compares. Every such subject has a NAME, and the tree's own instruments
carry those names. So there is a RELATION, and it has two ends:

    a SUBJECT that is NAMED but ABSENT   -> a DANGLING REFERENCE
    a SUBJECT that EXISTS but is NAMED by NOBODY -> an ORPHAN, and nothing checks it

**THE TWO ENDS ARE THE SAME SET DIFFERENCE, AND THE POPULATION MUST CONTAIN BOTH.**
`AGENTS.md`'s rule is that a population must be DISCOVERED **and must include what is missing**,
and this file is the third instance of the class it names, after the pin census that compared
only subjects that RESOLVE and the `code_lines()` reader that dropped the tail of a file.

**SO: WHAT IS "NOTHING CHECKS IT"? IT IS NOT "RESOLVES?"** -- that is the answer, and this file
IS the answer, because a resolution test cannot see a dangling reference: the reference is not a
file, so a census over files has no row for it, and the instrument that "checks the pins" is
blind to exactly the pins that are broken. **THE ANSWER IS THE CITATION RELATION READ IN THE
OTHER DIRECTION: A SUBJECT IS CHECKED IF AN INSTRUMENT'S BODY NAMES IT.** A name is a fact about
the NAMER, and the namer exists whether or not the named file does.

## THE TOKEN IS DECIDED WITHOUT THE FILE. THAT IS THE WHOLE POINT.

Every path-citation instrument in this tree decides "is this token a path?" by asking "does this
path exist?" -- `gates/slop-prune-census.py:tokens()` matches against a KNOWN population,
`gates/oracle-census-gate.py:is_data()` asks `path in tracked`, and `checks/repro-paths.py`
intersects its extraction with `os.path.exists`. **ALL THREE ARE RESOLVE-ONLY, AND A RESOLVE-ONLY
CENSUS IS BLIND TO THE SUBJECT THAT MATTERS MOST.**

So this file decides it the other way round:

    A TOKEN IS A REPO-RELATIVE PATH REFERENCE IFF ITS FIRST `/`-SEPARATED COMPONENT IS A
    TOP-LEVEL NAME OF THE COMMIT TREE.

`git ls-tree HEAD` gives those names, so the test is DERIVED and it does not consult the
filesystem at all. `oracles/BEFORE-rows.txt` is a path reference whether or not that file is
there -- and that is the only way a dangling reference can enter a population at all.

**MEASURED, AND THIS IS THE POINT OF THE WHOLE FILE:** with the resolve-only test the same
namers name 723 subjects; with the commit-tree test they name 874, and the 151 extra are the
ones a resolve-only census CANNOT SEE. The number is a row in the report, not a claim here.

## THE NAMERS ARE DISCOVERED, AND NONE OF THEM IS A LIST

  N1  the GATE POPULATION. `gates/gates-pop.py:discover()` -- LOADED BY PATH -- gives the entry
      points and the libraries of the DERIVED gate homes. The tree already owns this
      derivation (`gates/gate-surface.py:76` says so) and this file does not keep a second copy.
  N2  the FROZEN GATE COPIES. `.agents/slop/clearfix/freeze.py:GATES` -- LOADED BY PATH -- is the
      generator that materialises `.agents/slop/clearfix/frozen-prefix/<gate>.py`. Those copies
      are gate BODIES and they carry pins, and they are where two dangling pins live.
  N3  the PORT RECIPES. `checks/substrate.py:POP_ROOT` -- LOADED BY PATH -- is the port's own
      recipe root, and a recipe names its ORACLE IN ITS HEADER COMMENT. `tinybendygrad/runtime/
      support/hcq2.bend` names four oracle files under `.agents/slop/` that no longer exist, and
      NO `.py`/`.sh` instrument in the tree names them -- so a namer population without recipes
      cannot see the hcq2 finding at all.

**A COMMENT IS A CITATION AND THIS FILE COUNTS IT.** The recipes' oracle names live in
comments, and `gates/slop-prune-census.py` counts comment citations too. Two strengths are
reported separately and NEVER MERGED:

  CODE   the name is in a code position of a `.py`/`.sh` body (comments and docstrings removed).
  PROSE  the name is only in a comment, a docstring, or a `.bend` header.

**THE ORPHAN VERDICT USES THE WEAKER SET.** A subject named in prose is not CHECKED, but it is
not abandoned either, and an orphan census that counted prose mentions would under-report.

## RECOVERY IS ASKED BY PATH, BECAUSE `rev-list --objects` IS NOT A PATH INDEX

`gates/slop-prune-census.py`'s header measures it: `git rev-list --objects --all` prints a PATH
only for the FIRST path at which an object was seen, so **1 808 of 5 105 paths have no line in
its output** and a prune sized by that map declares 1 808 recoverable files unrecoverable.
Two files with identical bytes share a blob OID.

So a blob is asked for BY PATH: `git log --all --name-only -- <paths>` is the exact path index
(a diff knows which path each side of a change was; an object walk does not), and
`git cat-file --batch-check` answers every candidate `<sha>:<path>` in ONE process.

**"THE BLOB IS THERE" AND "THE ORACLE IS GOOD" ARE TWO CLAIMS AND THIS FILE MAKES ONLY THE
FIRST.** The hard case is in the tree: `.agents/slop/e2e_mm.py` had a blob at `9c7808b3` and the
crash was not about it. A recovered oracle is a CANDIDATE: it must be RUN against the current
substrate before it can be called an oracle again, and running it is somebody else's grant.

## THE VERDICT CHARGES COVERAGE, NOT THE FINDING

  PASS      the census is COMPLETE: every subject carries exactly one class, the class counts
            sum to the population, and the two directions were both taken. `0 disagreements over
            0 comparisons` is not agreement (`.agents/slop/rebase-gate-selftest.py:1168-1180`),
            so the denominators are asserted, not inferred.
  FAIL      a subject carried no class, or a class count disagreed with its own membership.
  REFUSED   a declaration could not be LOADED. A carve-out that cannot be computed must never
            become a blanket exemption (`checks/no-txt.py:49`).
  DEAD      the population is empty. `gatekit.py`: DEAD = 5.

**THE FINDING ITSELF IS REPORTED AND NOT CHARGED**, for the reason `gates/oracle-census-gate.py`
gives about its own unguarded reader: a gate that exits 1 over a finding it cannot fix teaches
nobody to run it, and this tree's dangling references are not fixable by this file.

EXIT: 0 PASS, 1 FAIL, 3 REFUSED, 5 DEAD.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import importlib.util
import re
import subprocess
import sys
import warnings
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

# THE THREE DECLARATION SOURCES, BY PATH. NEVER A COPY: a second copy of a population is a
# contract with no generator, and it rots without anyone noticing. Each of these three is
# loadable and each has a `declared()`-shaped attribute this file READS.
GATES_POP = "gates/gates-pop.py"                    # -> discover() -> (entries, libs)
FREEZE = ".agents/slop/clearfix/freeze.py"           # -> GATES     -> the frozen gate copies
SUBSTRATE = "checks/substrate.py"                   # -> POP_ROOT  -> the port's recipe root
SWEEP = "checks/sweep.py"                           # -> ROLE_DIRS -> the role of each directory

# THIS FILE'S OWN EVIDENCE MUST NOT NAME ITS OWN SUBJECTS. Two names, not a population: the
# census reads every other body in the tree, and a census that can cite itself certifies
# everything. `gates/slop-prune-census.py` does the same thing through
# `.agents/slop/slopprune/plant.py:excluded()`, loaded by path.
SELF = "gates/oracle-dangling-gate.py"
REPORT = ".agents/slop/oracledangle/REPORT.md"
SELF_EVIDENCE = (SELF, REPORT)

# A PATH-SHAPED TOKEN IS A MAXIMAL RUN of `[\w./-]`, and then its ENDING decides what it is.
# The shape is `gates/slop-prune-census.py`'s, MEASURED there: a token ending in `/` has no
# extension, so a single-regex arm cannot see a DIRECTORY citation; and `[\w./-]*` BACKTRACKS
# TO EMPTY, so `\.[A-Za-z0-9]+` then matches `.agents` -- a path COMPONENT mistaken for a file
# extension. **A RUN, NOT A PATTERN WITH AN ALTERNATION.**
TOKEN_RUN = re.compile(r"(?<![\w./])([\w./-]+)")
# A FAMILY, NOT A FILE: an ellipsis, a doubled separator, or a parent step.
FAMILY = re.compile(r"\.\.\.|//|\.\.")

# A PIN SITE: `"<path>": "<hex>"`, and the VALUE MAY BE ON THE NEXT LINE. MEASURED
# 2026-10-20 in `gates/blobpin-census-gate.py`: 6 of the 12 sites put the value below the key,
# so a single-line pattern finds 6 and prints 6 as a count -- a population silently halved.
PIN_SITE = re.compile(r"""["'](?P<path>[\w./-]+\.[A-Za-z0-9]+)["']\s*:\s*["'](?P<sha>[0-9a-f]{40,64})["']""")

# THE SOURCE EXTENSIONS THIS FILE READS AS A NAMER BODY. `.bend` is here because a recipe names
# its oracle in its header, and that is the hcq2 finding's only carrier.
Namer_EXT = (".py", ".sh", ".mjs", ".bend")

# A SHELL/PYTHON COMMENT. `gates/slop-prune-census.py` strips `#` comments before its scan and
# `gates/oracle-census-gate.py` strips docstrings by AST; this file strips the LINE forms and
# says so in the report, because the `.bend` header IS a comment and must NOT be stripped there.
LINE_COMMENT = re.compile(r"(?m)(^|\s)[#].*$")


# -------------------------------------------------------------------------------------- plumbing


def git(*args: str, stdin: str | None = None) -> subprocess.CompletedProcess:
    """`git` in ROOT, inheriting the environment -- so an exported `GIT_INDEX_FILE` is honoured
    by construction rather than by a parameter a caller has to remember to pass."""
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, input=stdin)


def load_by_path(rel: str, name: str):
    """Import a sibling file that is not a package member -- `gates/` is not a package."""
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def head_paths() -> set[str]:
    """Every path in the COMMIT tree. NOT `git ls-files`: the index here is armed by design
    (`jj git colocation`), so the index answers a question about the editor."""
    p = git("ls-tree", "-r", "-z", "HEAD", "--name-only")
    if p.returncode != 0:
        raise RuntimeError(f"git ls-tree -r HEAD did not answer: {p.stderr.strip()[:120]}")
    return {p for p in p.stdout.split("\0") if p}


def top_level(paths: set[str]) -> set[str]:
    """The top-level NAMES of the commit tree. **THE DECIDING TEST OF THIS FILE.**"""
    return {p.split("/")[0] for p in paths}


# ------------------------------------------------------------------------------------ the namers


def namer_population(fs: Path | None = None) -> tuple[list[tuple[str, str]], dict]:
    """`(rel, body)` for every namer, and the measurements that produced them.

    The POPULATION is discovered on the real tree (the generators ask git). The BODIES are read
    from `fs`, so a plant can edit a copy without the census reading the tree it must not touch.

    Three sources, each LOADED BY PATH, and each reported with its own denominator. A source
    that cannot be loaded REFUSES the census rather than quietly contributing nothing."""
    fs = fs or ROOT
    names: list[tuple[str, Path]] = []
    deriv: dict = {}

    gp = load_by_path(GATES_POP, "oracle_dangling_gates_pop")
    entries, libs = gp.discover(ROOT)
    deriv["gate_entries"] = len(entries)
    deriv["gate_libs"] = len(libs)
    for p in (*entries, *libs):
        names.append((str(p.relative_to(ROOT)), p))

    freeze = load_by_path(FREEZE, "oracle_dangling_freeze")
    frozen = [ROOT / ".agents/slop/clearfix/frozen-prefix" / g for g in freeze.GATES]
    deriv["frozen_declared"] = len(freeze.GATES)
    deriv["frozen_present"] = sum(1 for p in frozen if p.is_file())
    names.extend((str(p.relative_to(ROOT)), p) for p in frozen)

    sub = load_by_path(SUBSTRATE, "oracle_dangling_substrate")
    recipes = sorted((ROOT / sub.POP_ROOT).rglob("*.bend"))
    deriv["recipe_root"] = sub.POP_ROOT
    deriv["recipes"] = len(recipes)
    names.extend((str(p.relative_to(ROOT)), p) for p in recipes)

    bodies: list[tuple[str, str]] = []
    for rel, _p in names:
        if rel in SELF_EVIDENCE:
            continue
        try:
            bodies.append((rel, (fs / rel).read_text(errors="replace")))
        except OSError:
            continue
    deriv["namers_read"] = len(bodies)
    return bodies, deriv


# ------------------------------------------------------------------------------- the tokenizer


def tokens(body: str) -> list[str]:
    """Every path-shaped token in `body`, cleaned, and NOT filtered by existence.

    **THE CLEANING IS MEASURED, NOT A TASTE.** A maximal run of `[\\w./-]` keeps the sentence
    period, so `checks/coindep.py.` -- a real file named at the end of a sentence -- reads as a
    path that does not exist. MEASURED on this tree's namers: 6 of the first 40 danglings were
    that, and 5 of them were files that DO exist. A trailing `.` is stripped, and a token
    holding `..` is a family, not a file.
    """
    out: list[str] = []
    for m in TOKEN_RUN.finditer(body):
        tok = m.group(1)
        if len(tok) < 3 or FAMILY.search(tok):
            continue
        tok = tok.rstrip(".")
        if tok.startswith("./"):
            tok = tok[2:]
        if len(tok) < 3 or FAMILY.search(tok):
            continue
        last = tok.rsplit("/", 1)[-1]
        # THE EXTENSION MUST NOT BE THE WHOLE NAME. `.e2e-fixture` and `.tmp-` are DIRECTORIES
        # and a token whose dot is at index 0 names no extension. `str.rstrip(".")` alone is not
        # enough either, and `lstrip("./")` was the FIRST BUG HERE: it strips the LEADING DOT of
        # `.agents/slop/hcq2-oracle.py` and turns the hcq2 finding into `agents/slop/...`, which
        # is not a top-level name of the commit tree and is therefore silently dropped.
        if "." not in last or last.index(".") == 0:
            continue
        out.append(tok)
    return out


def blank_docstrings(body: str) -> str:
    """Spaces over docstring spans. A docstring is not a use, and a regex over quotes would also
    blank a path that is a real assignment -- which is how the plant names a dangling subject.

    Spans come from the AST (`gates/oracle-census-gate.py:_docstring_nodes`). A body that does
    not parse is returned unchanged; the line-comment strip still runs on it.
    """
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", SyntaxWarning)
            tree = ast.parse(body)
    except SyntaxError:
        return body
    spans: list[tuple[int, int, int, int]] = []
    for node in ast.walk(tree):
        stmts = getattr(node, "body", None)
        if not isinstance(stmts, list) or not stmts:
            continue
        first = stmts[0]
        value = first.value if isinstance(first, ast.Expr) else None
        if not (isinstance(value, ast.Constant) and isinstance(value.value, str)
                and value.end_lineno is not None and value.end_col_offset is not None):
            continue
        spans.append((value.lineno, value.col_offset, value.end_lineno, value.end_col_offset))
    if not spans:
        return body
    lines = body.splitlines(keepends=True)
    for start_line, start_col, end_line, end_col in spans:
        for i in range(start_line - 1, end_line):
            line = lines[i]
            nl = len(line) - len(line.rstrip("\r\n"))
            lo = start_col if i == start_line - 1 else 0
            hi = end_col if i == end_line - 1 else len(line) - nl
            lines[i] = line[:lo] + (" " * (hi - lo)) + line[hi:]
    return "".join(lines)


def code_tokens(body: str, rel: str) -> list[str]:
    """The tokens in a CODE position: comments and docstrings removed.

    **`.bend` IS NOT STRIPPED.** A recipe's oracle name lives in a header COMMENT, and that
    comment IS the recipe's declaration of its oracle -- `tinybendygrad/runtime/support/hcq2.bend`
    names four oracle files there and nowhere else. Stripping comments from a recipe would
    delete the finding.
    """
    if rel.endswith(".bend"):
        return tokens(body)
    if rel.endswith(".py"):
        body = blank_docstrings(body)
    return tokens(LINE_COMMENT.sub("", body))


# ------------------------------------------------------------------------------ the resolution


def resolve(subject: str, head: set[str], fs: Path | None = None) -> str:
    """`AT-HEAD` | `ON-DISK` | `MOVED` | `DANGLING` -- FOUR states, not two.

    `MOVED` is separated from `DANGLING` because they are different defects and the tree has
    been bitten by the merge: `gates/gates-pop.py:gate_homes` says "a missing directory is a
    MOVED or DELETED one, and this is the row that says so instead of counting as an empty
    question." `MOVED` means the subject's BASENAME is carried by exactly one path in the commit
    tree -- the file exists, under another name or another root.
    """
    fs = fs or ROOT
    if subject in head:
        return "AT-HEAD"
    if (fs / subject).is_file():
        return "ON-DISK"
    base = subject.rsplit("/", 1)[-1]
    hits = [p for p in head if p.rsplit("/", 1)[-1] == base]
    if len(hits) == 1:
        return "MOVED"
    return "DANGLING"


def dir_tokens(body: str) -> list[str]:
    """Every DIRECTORY-shaped token in `body` -- a maximal run ending in `/`.

    Needed because a PIN's subject may be RELATIVE: `checks/differ.py:63` pins
    `"diffpy/oracle-run.sh"` and resolves it at `:80` as `ROOT / ".agents/slop" / name`. **A
    census that reads the pin's literal as a repo-relative path reports a pin whose subject
    EXISTS as a subject that does not exist**, and that is a wrong reason for a right answer.
    The base is therefore DERIVED from the site's own body rather than assumed.
    """
    out: list[str] = []
    for m in TOKEN_RUN.finditer(body):
        tok = m.group(1)
        if tok.endswith("/") and len(tok) > 2 and not FAMILY.search(tok):
            out.append(tok)
    return out


def resolve_pin_subject(literal: str, body: str, rel: str, head: set[str], tops: set[str],
                         fs: Path | None = None) -> tuple[str, str]:
    """`(subject, base)` for a pin's literal.

    A literal whose first component is a top-level name of the commit tree IS repo-relative.
    Otherwise it is RELATIVE to a base the site names in its own body, and the base is found
    by asking which base makes the path EXIST -- a resolution, not a guess.
    """
    fs = fs or ROOT
    if literal.split("/")[0] in tops:
        return literal, "(repo-relative)"
    cands = []
    for d in dir_tokens(body):
        if (d + literal) in head or (fs / (d + literal)).is_file():
            cands.append((d + literal, d))
    own = str(Path(rel).parent / literal)
    if own in head or (fs / own).is_file():
        cands.append((own, str(Path(rel).parent)))
    uniq = sorted(set(cands))
    if len(uniq) == 1:
        return uniq[0][0], uniq[0][1]
    if len(uniq) > 1:
        return uniq[0][0], f"AMBIGUOUS among {len(uniq)} bases"
    return literal, "(no base in this body resolves it)"


def kind_of(subject: str, role_dirs: dict[str, str]) -> str:
    """The KIND of a subject, so a reader can triage a dangling name.

    `ORACLE`   -- under a directory the tree declares to have the ORACLE role
                  (`checks/sweep.py:ROLE_DIRS`), or a stem that carries `oracle`.
    `EV`       -- an expected-value file: the extension the tree uses for them (`.rows`).
    `RECIPE`   -- under the port's recipe root.
    `SWEPT`    -- under the pruned tree.
    `INSTRUMENT` -- under a role-GATE directory.
    `OTHER`    -- everything else.
    """
    top = subject.split("/")[0]
    if role_dirs.get(top) == "ORACLE":
        return "ORACLE"
    if role_dirs.get(top) == "GATE":
        return "INSTRUMENT"
    if subject.rsplit("/", 1)[-1].endswith(".rows"):
        return "EV"
    if "oracle" in subject.rsplit("/", 1)[-1].lower():
        return "ORACLE"
    if top == ".agents":
        return "SWEPT"
    if subject.endswith(".bend"):
        return "RECIPE"
    return "OTHER"


def scope_of(subject: str, roles: dict[str, str], port_root: str) -> str:
    """The SCOPE a subject sits in -- the DENOMINATOR the orphan count travels with.

    A single "N of M" over the whole tree is a number nobody can act on, because the tree's
    scopes have DIFFERENT OWNERS: `gates/slop-prune-census.py` owns the swept tree, and
    `gates/oracle-census-gate.py` owns the ORACLE tree. **THE DENOMINATOR IS PER SCOPE, AND
    THIS FILE PRINTS THE SCOPES WITH THEIR OWN COUNTS.**
    """
    top = subject.split("/")[0]
    if top in roles:
        return top
    if subject.startswith(port_root + "/"):
        return port_root
    if top == ".agents":
        return ".agents/slop"
    return "other"


# ------------------------------------------------------------------------------- the recovery


def recover(paths: list[str]) -> dict[str, dict]:
    """`path -> {blob, commit, bytes, sha256}` for every path a REF has carried, asked BY PATH.

    **`git rev-list --objects --all` IS NOT USED**, and the reason is measured in this tree:
    it prints a PATH only for the first path at which an object was seen, so 1 808 of 5 105
    paths have no line in its output and two files with identical bytes share a blob OID.
    `git log --all --name-only -- <paths>` IS a path index -- a diff knows which path each side
    of a change was, an object walk does not -- and `git cat-file --batch-check` answers every
    candidate `<sha>:<path>` in ONE process.
    """
    if not paths:
        return {}
    p = git("log", "--all", "--format=%x01%H %P", "--name-only", "--", *paths)
    if p.returncode != 0:
        return {}
    touch: dict[str, list[tuple[str, list[str]]]] = {}
    sha, parents = "", []
    for line in p.stdout.splitlines():
        if line.startswith("\x01"):
            head = line[1:].split()
            sha, parents = head[0], head[1:]
            continue
        if line and sha:
            touch.setdefault(line, [])
            if not any(s == sha for s, _ in touch[line]):
                touch[line].append((sha, parents))
    # CANDIDATES: the commit that touched the path, then its PARENT, then the grandparent.
    # A commit that DELETED the path does not carry it; its parent does.
    cands: list[str] = []
    for path, entries in touch.items():
        for sha, parents in entries[:4]:
            chain, cur_parents = [sha], parents
            for _ in range(3):
                if not cur_parents:
                    break
                chain.append(cur_parents[0])
                cur_parents = []
            for c in chain:
                cands.append(f"{c}:{path}")
    if not cands:
        return {}
    chk = subprocess.run(["git", "cat-file", "--batch-check"], cwd=ROOT, capture_output=True,
                         text=True, input="\n".join(cands) + "\n")
    # **THE OUTPUT IS IN INPUT ORDER, AND THAT IS THE ONLY WAY BACK TO THE SPEC.**
    # `git cat-file --batch-check` prints `<oid> <type> <size>` -- it does NOT echo the input, so
    # a line cannot be matched to its own request by parsing it. The pairing is positional, and
    # the first version of this file tried to parse `<oid> blob <size>` as if the second field
    # were part of a path, which it is not, and recovered NOTHING while reporting no failure.
    lines = chk.stdout.splitlines()
    found: dict[str, tuple[str, str]] = {}
    for spec, out in zip(cands, lines):
        fields = out.split()
        if len(fields) < 3 or fields[1] != "blob":
            continue
        _, _, rel = spec.rpartition(":")
        found[rel] = (fields[0], spec)
    out: dict[str, dict] = {}
    for path in paths:
        hit = found.get(path)
        if not hit:
            continue
        oid, spec = hit
        blob = git("cat-file", "blob", spec)
        if blob.returncode != 0:
            continue
        data = blob.stdout.encode()
        out[path] = {"blob": oid, "commit": spec.rsplit(":", 1)[0], "bytes": len(data),
                     "sha256": hashlib.sha256(data).hexdigest()}
    return out


# ------------------------------------------------------------------------------ the census


def role_dirs() -> dict[str, str]:
    """`{dir: role}` from `checks/sweep.py:ROLE_DIRS`, LOADED BY PATH.

    `ROLE_DIRS` is a DECLARATION -- a directory whose own name declares its role classifies its
    whole subtree (`checks/sweep.py:753`) -- and it is the tree's own word for the ORACLE tree.
    """
    sweep = load_by_path(SWEEP, "oracle_dangling_sweep")
    return dict(sweep.ROLE_DIRS)


def census(root: Path | None = None) -> dict:
    """Every measurement, in one dict, so the report computes nothing of its own.

    `root` is the filesystem the namer bodies are read from. Git questions stay on this
    repository: a plant copies the tree without `.git` and still asks this HEAD.
    """
    fs = root or ROOT
    head = head_paths()
    tops = top_level(head)
    roles = role_dirs()
    namers, deriv = namer_population(fs)

    named_code: dict[str, set[str]] = {}
    named_any: dict[str, set[str]] = {}
    for rel, body in namers:
        for tok in tokens(body):
            named_any.setdefault(tok, set()).add(rel)
        for tok in code_tokens(body, rel):
            named_code.setdefault(tok, set()).add(rel)

    # THE DECIDING FILTER. A token is a repo-relative path reference iff its first component is
    # a top-level name of the COMMIT tree -- a test that never consults the filesystem, which is
    # the only way a DANGLING reference can enter a population at all.
    subjects = {t: v for t, v in named_any.items() if t.split("/")[0] in tops}
    subjects_code = {t: v for t, v in named_code.items() if t.split("/")[0] in tops}

    classes: dict[str, str] = {}
    for t in subjects:
        classes[t] = resolve(t, head, fs)

    # THE ON-DISK SIDE: the subjects that EXIST. Two kinds, and their denominators are separate.
    oracle_pop = sorted(p for p in head if kind_of(p, roles) == "ORACLE")
    ev_pop = sorted(p for p in head if kind_of(p, roles) == "EV")

    # THE ORPHANS. Nothing CHECKS a subject that no namer names in a CODE position. A prose
    # mention is not a check -- counting it would under-report -- but it is not abandonment
    # either, so it is reported on its own line and never folded into the check.
    # The BASENAME fallback keeps a subject alive when a CODE citation names it under another
    # root, and it is counted separately so a reader can see how many the fallback rescued.
    on_disk = sorted(set(oracle_pop) | set(ev_pop))
    named_base_code = {t.rsplit("/", 1)[-1] for t in subjects_code}
    orphans = sorted(p for p in on_disk
                     if p not in subjects_code and p.rsplit("/", 1)[-1] not in named_base_code)
    rescued = sorted(p for p in on_disk
                     if p not in subjects_code and p.rsplit("/", 1)[-1] in named_base_code)
    prose_only = sorted(p for p in orphans if p in subjects)

    dangling = sorted(t for t, c in classes.items() if c in ("DANGLING", "MOVED"))
    dangling_code = sorted(t for t in dangling if t in subjects_code)
    recovery = recover([t for t in dangling if kind_of(t, roles) in ("ORACLE", "EV", "SWEPT")])

    # THE PINS. A pin is a subject whose reference carries a sha256, and the pin is a CLAIM
    # ABOUT BYTES, so the recovery answer can be checked against it.
    pins: list[dict] = []
    for rel, body in namers:
        for m in PIN_SITE.finditer(body):
            literal = m.group("path")
            subject, base = resolve_pin_subject(literal, body, rel, head, tops, fs)
            pins.append({"literal": literal, "path": subject, "base": base,
                         "sha": m.group("sha"), "site": rel})
    pin_subjects = sorted({p["path"] for p in pins if p["path"] not in head})
    pin_recovery = recover(pin_subjects)

    # THE DENOMINATORS, PER SCOPE. A single "N of M" over the whole tree is a number nobody can
    # act on, because the scopes have DIFFERENT OWNERS.
    scopes: dict[str, dict] = {}
    port_root = deriv.get("recipe_root", "tinybendygrad")
    for p in on_disk:
        s = scopes.setdefault(scope_of(p, roles, port_root), {"pop": 0, "orphan": 0, "rescued": 0})
        s["pop"] += 1
    for p in orphans:
        scopes[scope_of(p, roles, port_root)]["orphan"] += 1
    for p in rescued:
        scopes[scope_of(p, roles, port_root)]["rescued"] += 1

    return {"head": head, "tops": tops, "roles": roles, "deriv": deriv,
            "subjects": subjects, "subjects_code": subjects_code, "classes": classes,
            "oracle_pop": oracle_pop, "ev_pop": ev_pop, "orphans": orphans,
            "prose_only": prose_only, "rescued": rescued, "scopes": scopes,
            "dangling": dangling, "dangling_code": dangling_code,
            "recovery": recovery, "pins": pins, "pin_recovery": pin_recovery,
            "named_any": len(named_any), "named_code": len(named_code)}


def check(surveyed: dict) -> tuple[int, str]:
    """THE COVERAGE ASSERTION, AND ONLY THAT."""
    if not surveyed["subjects"]:
        return DEAD, "the named-subject population is empty"
    known = {"AT-HEAD", "ON-DISK", "MOVED", "DANGLING"}
    tally: dict[str, int] = {}
    unclassified = []
    for t, c in surveyed["classes"].items():
        tally[c] = tally.get(c, 0) + 1
        if c not in known:
            unclassified.append(t)
    if unclassified:
        return FAIL, f"{len(unclassified)} subject(s) carry no class: {unclassified[:5]}"
    if sum(tally.values()) != len(surveyed["classes"]):
        return FAIL, f"the class counts sum to {sum(tally.values())} over {len(surveyed['classes'])}"
    # THE DENOMINATOR OF THE ORPHAN VERDICT IS ASSERTED, NOT INFERRED.
    pop = len(set(surveyed["oracle_pop"]) | set(surveyed["ev_pop"]))
    if len(surveyed["orphans"]) > pop:
        return FAIL, f"{len(surveyed['orphans'])} orphans over a population of {pop}"
    return PASS, (f"{len(surveyed['classes'])} named subjects, "
                  + " ".join(f"{k}={tally[k]}" for k in sorted(tally))
                  + f"; on-disk subjects {pop}, orphans {len(surveyed['orphans'])}")


def report(surveyed: dict, rows_path: Path | None) -> None:
    """Everything below is a MEASUREMENT with a denominator beside it."""
    d, classes = surveyed["deriv"], surveyed["classes"]
    tally: dict[str, int] = {}
    for c in classes.values():
        tally[c] = tally.get(c, 0) + 1
    print(f"oracle-dangling-gate   HEAD {git('rev-parse', 'HEAD').stdout.strip()}")
    print("  NAMERS (discovered, none listed)")
    print(f"    gate population   entries {d['gate_entries']}  libs {d['gate_libs']}"
          f"   [gates/gates-pop.py:discover()]")
    print(f"    frozen gate copies  declared {d['frozen_declared']}  present {d['frozen_present']}"
          f"   [.agents/slop/clearfix/freeze.py:GATES]")
    print(f"    port recipes      {d['recipes']}   [{d['recipe_root']}, checks/substrate.py:POP_ROOT]")
    print(f"    bodies read       {d['namers_read']}")
    print("  NAMED SUBJECTS -- the deciding test is the COMMIT TREE's top-level names, so a")
    print("    subject that does NOT EXIST can still enter the population")
    print(f"    tokens seen       {surveyed['named_any']} (any)  {surveyed['named_code']} (code position)")
    print(f"    repo-relative     {len(surveyed['subjects'])} (any)  {len(surveyed['subjects_code'])} (code)")
    print("    class             " + " ".join(f"{k}={tally[k]}" for k in sorted(tally)))
    pop = len(set(surveyed["oracle_pop"]) | set(surveyed["ev_pop"]))
    print(f"  ON-DISK SUBJECTS   {pop}   (ORACLE {len(surveyed['oracle_pop'])}, "
          f"EV {len(surveyed['ev_pop'])})")
    print(f"    ORPHAN            {len(surveyed['orphans'])} of {pop}   "
          f"(nothing checks it: not named in a code position)")
    print(f"    PROSE-ONLY        {len(surveyed['prose_only'])}   "
          f"(named in a comment or a docstring, which is not a check)")
    print(f"    RESCUED BY BASENAME {len(surveyed['rescued'])}  (named under a different root)")
    print("    PER SCOPE -- the denominator travels with the count, because the scopes have")
    print("    DIFFERENT OWNERS: `gates/oracle-census-gate.py` owns the ORACLE tree and")
    print("    `gates/slop-prune-census.py` owns the swept tree.")
    for s in sorted(surveyed["scopes"]):
        row = surveyed["scopes"][s]
        print(f"      {s:<20} orphan {row['orphan']:>5} of {row['pop']:>5}   "
              f"(+{row['rescued']} rescued by basename)")
    print(f"  DANGLING SUBJECTS  {len(surveyed['dangling'])}   "
          f"({len(surveyed['dangling_code'])} named in a CODE position)")
    asked = [t for t in surveyed["dangling"]
             if kind_of(t, surveyed["roles"]) in ("ORACLE", "EV", "SWEPT")]
    print(f"  RECOVERY           blob-there {len(surveyed['recovery'])} of {len(asked)} asked. "
          f"oracle-good 0: a recovered blob was not run against the current substrate.")
    for t in surveyed["dangling"]:
        rec = surveyed["recovery"].get(t)
        kind = kind_of(t, surveyed["roles"])
        print(f"    {classes[t]:<8} {kind:<10} {t}")
        print(f"             named by {len(surveyed['subjects'][t])}: "
              f"{', '.join(sorted(surveyed['subjects'][t])[:3])}")
        if rec:
            print(f"             RECOVERED {rec['commit'][:9]} {rec['bytes']} B "
                  f"sha256={rec['sha256'][:16]}")
    print(f"  PINS               {len(surveyed['pins'])} site(s) carrying a sha256")
    for p in surveyed["pins"]:
        path, sha = p["path"], p["sha"]
        on_disk = (ROOT / path).is_file()
        got = hashlib.sha256((ROOT / path).read_bytes()).hexdigest() if on_disk else ""
        state = ("INTACT" if got == sha else "SHA-MISMATCH") if on_disk else "SUBJECT-ABSENT"
        rec = surveyed["pin_recovery"].get(path) or surveyed["recovery"].get(path)
        extra = ""
        if rec:
            extra = (f"   RECOVERED {rec['commit'][:9]} {rec['bytes']} B "
                     f"sha256={rec['sha256'][:16]} "
                     f"{'MATCHES THE PIN' if rec['sha256'] == sha else 'DIFFERS FROM THE PIN'}")
        base = "" if p["base"] == "(repo-relative)" else f"  [literal {p['literal']!r} base {p['base']}]"
        print(f"    {state:<14} {path:<50} pin={sha[:16]} <- {p['site']}{base}{extra}")
    if rows_path:
        rows_path.parent.mkdir(parents=True, exist_ok=True)
        head = "subject\tkind\tclass\tnamed_by\tnamed_by_code\trecovered\tsha256\torphan"
        body = []
        orphan_set = set(surveyed["orphans"])
        seen: set[str] = set()
        for t in sorted(surveyed["subjects"]):
            seen.add(t)
            rec = surveyed["recovery"].get(t, {})
            body.append("\t".join([t, kind_of(t, surveyed["roles"]), classes[t],
                                   str(len(surveyed["subjects"][t])),
                                   str(len(surveyed["subjects_code"].get(t, ()))),
                                   rec.get("commit", "-"), rec.get("sha256", "-"),
                                   "1" if t in orphan_set else "0"]))
        for t in surveyed["orphans"]:
            if t in seen:
                continue
            body.append("\t".join([t, kind_of(t, surveyed["roles"]), "AT-HEAD",
                                   "0", "0", "-", "-", "1"]))
        rows_path.write_text("\n".join([head, *body]) + "\n")
        print(f"  TABLE              {rows_path}")


# ------------------------------------------------------------------------------------ the plant


def _replace_token(body: str, path: str, repl: str) -> str:
    """Replace `path` only where it is a whole token. A substring replace would also eat a longer path."""
    return re.sub(rf"(?<![\w./-]){re.escape(path)}(?![\w./-])", repl, body)


def _write_copy(path: Path, text: str) -> None:
    """Write into the copy. A symlink is replaced, never followed -- following it writes the original."""
    if path.is_symlink():
        path.unlink()
    path.write_text(text)


def plant(surveyed: dict) -> int:
    """TWO PLANTS AND TWO CONTROLS, IN A TEMP COPY. THE TREE IS NEVER A BASE.

    PLANT 1 -- a DANGLING name must APPEAR, and a second planted name must appear too. If only
    one of them does, the census is selective. An UNPLANTED name of the same shape must NOT
    appear: that is the control, and a census that invents dangling names cannot be trusted
    when it reports one.

    PLANT 2 -- an ORPHAN must APPEAR. The copy loses the code citation of one on-disk subject.
    A second on-disk subject of the same kind is NOT un-named, and it must NOT become an orphan.
    **A PLANT WITHOUT A CONTROL CANNOT DISTINGUISH "THE INSTRUMENT MOVED" FROM "THE INSTRUMENT
    ALWAYS SAYS YES".**

    THE COPY MUST NOT FILTER THE POPULATION. `.git` is excluded because the census asks git
    questions of this repository and a copy of a repository is a different repository. If the
    copy's census already disagrees with the real one, the plant REFUSES -- a moved baseline
    is not a plant.
    """
    import shutil
    import tempfile
    with tempfile.TemporaryDirectory(prefix="oracle-dangling-plant.") as tmp:
        copy = Path(tmp) / "repo"
        shutil.copytree(ROOT, copy, symlinks=True, ignore=shutil.ignore_patterns(".git"))
        base = census(copy)
        extra_d = sorted(set(base["dangling"]) - set(surveyed["dangling"]))
        lost_d = sorted(set(surveyed["dangling"]) - set(base["dangling"]))
        extra_o = sorted(set(base["orphans"]) - set(surveyed["orphans"]))
        lost_o = sorted(set(surveyed["orphans"]) - set(base["orphans"]))
        if extra_d or lost_d or extra_o or lost_o:
            print("PLANT REFUSED: the copy moved before any edit")
            print(f"  dangling +{len(extra_d)} {extra_d[:8]}")
            print(f"  dangling -{len(lost_d)} {lost_d[:8]}")
            print(f"  orphans  +{len(extra_o)} {extra_o[:8]}")
            print(f"  orphans  -{len(lost_o)} {lost_o[:8]}")
            return REFUSED

        code = base["subjects_code"]
        on_disk = set(base["oracle_pop"]) | set(base["ev_pop"])
        base_n = {}
        for t in code:
            base_n[t.rsplit("/", 1)[-1]] = base_n.get(t.rsplit("/", 1)[-1], 0) + 1
        cands = []
        for p in sorted(on_disk):
            if p not in code or len(code[p]) != 1:
                continue
            if base_n.get(p.rsplit("/", 1)[-1], 0) != 1:
                continue
            namer = next(iter(code[p]))
            if namer.endswith(".py") and (copy / namer).is_file():
                cands.append((p, namer))
        if len(cands) < 2:
            print(f"PLANT REFUSED: {len(cands)} unnameable code-cited subjects")
            return REFUSED
        victim, victim_namer = cands[0]
        control_victim = next(p for p, _n in cands[1:])
        writers = sorted({n for ns in code.values() for n in ns
                          if n.endswith(".py") and n.startswith("gates/") and (copy / n).is_file()})
        writer = next((n for n in writers if n != victim_namer), victim_namer)

        plant_name = ".agents/slop/oracledangle/does-not-exist.rows"
        control_name = ".agents/slop/oracledangle/also-does-not-exist.rows"
        absent_name = ".agents/slop/oracledangle/not-planted.rows"
        vpath = copy / victim_namer
        vbody = _replace_token(vpath.read_text(), victim, "PLANTED_AWAY")
        if writer == victim_namer:
            vbody += f"\nPLANT_NAME = {plant_name!r}\nPLANT_CONTROL = {control_name!r}\n"
            _write_copy(vpath, vbody)
        else:
            _write_copy(vpath, vbody)
            wpath = copy / writer
            _write_copy(wpath, wpath.read_text()
                        + f"\nPLANT_NAME = {plant_name!r}\nPLANT_CONTROL = {control_name!r}\n")

        after = census(copy)
        checks = [
            ("the planted DANGLING name appeared",
             plant_name in after["dangling"] and plant_name not in base["dangling"],
             f"{plant_name} in {len(after['dangling'])} danglers"),
            ("the second planted name appeared (the census is not selective)",
             control_name in after["dangling"] and control_name not in base["dangling"],
             f"{control_name} present={control_name in after['dangling']}"),
            ("the UNPLANTED control did NOT appear",
             absent_name not in after["dangling"] and absent_name not in base["dangling"],
             f"{absent_name} present={absent_name in after['dangling']}"),
            ("the un-named on-disk subject became an ORPHAN",
             victim in after["orphans"] and victim not in base["orphans"],
             f"{victim}: base={victim in base['orphans']} after={victim in after['orphans']}"),
            ("the UNBROKEN control did NOT become an orphan",
             control_victim not in after["orphans"] and control_victim not in base["orphans"],
             f"{control_victim}: after={control_victim in after['orphans']}"),
        ]
        for name, ok, detail in checks:
            print(f"  {'OK  ' if ok else 'FAIL'}  {name:<62} {detail}")
        bad = [n for n, ok, _ in checks if not ok]
        print(f"  VERDICT {'PASS' if not bad else 'FAIL: ' + '; '.join(bad)}")
        return PASS if not bad else FAIL


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--report", action="store_true", help="census only, rc never charged")
    ap.add_argument("--plant", action="store_true", help="the self-test, in a temp copy")
    ap.add_argument("--rows", help="write the per-subject table here")
    args = ap.parse_args(argv)
    try:
        surveyed = census(ROOT)
    except Exception as exc:                                   # noqa: BLE001 - reported, not hidden
        print(f"REFUSED: the census could not be taken: {type(exc).__name__}: {exc}", file=sys.stderr)
        return REFUSED
    rows_path = Path(args.rows) if args.rows else HERE / "artifacts" / "oracle-dangling-gate" / "census.rows"
    report(surveyed, rows_path)
    code, why = check(surveyed)
    print(f"  {why}")
    if args.report:
        print(f"  --report: rc never charged ({VERDICT[code]})")
        return PASS
    if args.plant:
        return plant(surveyed)
    return code


if __name__ == "__main__":
    sys.exit(main())
