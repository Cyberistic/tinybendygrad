#!/usr/bin/env python3
"""gates/edge-fixture-census.py -- THE NEED CENSUS: what does a gate ACTUALLY need, and is it safe?

    .venv/bin/python gates/edge-fixture-census.py            # the census + the ledger
    .venv/bin/python gates/edge-fixture-census.py --plant    # the plant, in a TEMP COPY
    .venv/bin/python gates/edge-fixture-census.py --gate checks/e2e.py --rows PATH

THE QUESTION. `checks/e2e.py` CRASHED on its first run under the edge
(`AttributeError: 'ProgramInfo' object has no attribute 'vals'`), and the edge could not tell
whether the cause was a MISSING fixture or a STALE one. **THE ANSWER IS BOTH, AND THEY ARE
DIFFERENT FIXES**, so the question this file answers is the one underneath both:

    WHICH FILES DOES THIS GATE NEED, AND IS EACH ONE SAFE?

"SAFE" here is `gates/slop-prune-census.py`'s question, asked of ONE gate instead of a whole
tree: `.agents/slop/` is being pruned, so a gate whose inputs live there is a gate one
`rm -rf` away from being DEAD. **THE ANSWER IS A SET AND ITS DENOMINATOR, NOT A VERDICT.**

## THE CLOSURE, AND WHAT IT IS NOT

A CLOSURE is the set of files reachable from the gate through the gate's own CODE. It is
computed here by WALK, never from a list of names:

  * a file is SCANNED iff it is a PROGRAM in a language the tree can read, decided by
    `gates/gates-pop.py:entry_reason()` -- the tree's own instrument, loaded BY PATH. A
    `.bend` or a `.json` is DATA and cannot name a path at runtime, so it is not scanned.
  * its CODE lines come from `gates/pincensus-pop.py:code_lines()`, so a path in a COMMENT or
    a DOCSTRING is not a requirement. **MEASURED 2026-10-20: `checks/e2e.py` names 21
    `.agents/slop/` paths in its PROSE and 9 in its CODE, and the prose ones include
    `.agents/slop/ops_bend-milestone-expected.txt`, a path that has not existed since the
    fixture was renamed to `.md`.** A closure over raw text would carry a dead path as a
    requirement forever.
  * a path-shaped token is RESOLVED against the tree, and a token with a variable PREFIX
    (`ROOT/.agents/slop/opsbend-milestone`) is resolved by stripping leading segments until
    a file answers -- and the resolution must be UNIQUE or it is reported, never guessed.

**THE CLOSURE IS A LOWER BOUND, AND THE DIFFERENCE IS A NUMBER, NOT A SILENCE.** A path
ASSEMBLED AT RUNTIME from parts (`SLOP + "/" + name`) is invisible to any static scan. The
census counts the bodies that hold a `.agents/slop/` prefix without naming a census path --
the same arm `gates/slop-prune-census.py` calls `root_prefixed` -- and prints it beside the
closure, so a reader can see the size of the blind spot instead of trusting the closure.

## THE COPY, AND WHY THE PIN CENSUS DECIDES WHICH FILES MAY BE REWRITTEN

A fixture that lives in a pruned tree must ALSO live in git beside the gate. **AND A MOVE
IS NOT A COPY WHEN THE FILE'S BYTES ARE A PIN'S SUBJECT.** `checks/e2e.py` pins the frozen
shell oracle by CONTENT, and `revert(oracle) == checks/e2e.sh` is a byte identity: rewriting
a byte of the oracle moves a pin that `checks/e2e.py` checks on every run. So the census
asks the tree's OWN pin census -- `gates/pincensus-pop.py:rule_a()` and
`gates/bind-subject.py:resolve()`, both loaded BY PATH -- which of the gate's inputs are
byte-pinned, and only those are copied VERBATIM. The rest are RELOCATED, which is the
prefix substitution and nothing else, and the census verifies that the copy is EXACTLY the
substitution of the BLOB.

**THE BLOB IS THE SOURCE, NOT THE WORKTREE.** Every byte is read with
`git cat-file blob HEAD:<path>`, so a worktree that was edited by another unit cannot
launder its bytes into the copy. The census prints the blob OID it used for every file.

## THE PLANT, AND WHY IT HAS A CONTROL

A census that cannot fail is a census that cannot be wrong. The plant runs in a TEMP COPY
and asks three things of it:

  1 DISCOVERY.  A NEW file is planted under the pruned tree and a code reference to it is
     added to a file already in the closure. The closure must GROW BY EXACTLY ONE. A census
     that cannot see a reference a hand list would have missed FAILS here.
  2 FIDELITY, ONE SIDE.  A byte is changed in the COPY. The census must report MISMATCH.
  3 FIDELITY, BOTH SIDES -- THE CONTROL.  The SAME byte is changed in the copy AND in the
     blob-side expectation. The census must STILL report CURRENT.

**PLANT 3 IS THE ONE THAT MAKES PLANT 2 MEANINGFUL.** A check that compares a value with
itself is a tautology that cannot fail, and a check that compares the copy with the copy
would report MISMATCH for plant 2 and MISMATCH for plant 3 too -- i.e. it would be a
constant. The control is what proves the two sides are INDEPENDENT values: one changes the
verdict and the other does not. **A PLANT THAT FLATTENS BOTH SIDES TO ONE CONSTANT IS
VACUOUS, AND THIS ONE IS BUILT SO IT CANNOT BE.**

VERDICTS, in `AGENTS.md`'s five. PASS 0. FAIL the census cannot measure or a copy drifted.
REFUSED 3 git or the walk did not answer. DEAD 5 the closure found 0 files.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import time
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SLOP = ".agents/slop"
HOME = "checks/.e2e-fixture"      # THE NEW HOME. In git, beside the gate, NOT under the pruned tree.
DEFAULT_GATE = "checks/e2e.py"
LEDGER = "gates/edge-fixture.rows"

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5

# A path-shaped token is a MAXIMAL RUN of `[\w./-]`, and its ENDING decides what it is.
# THE SHAPE IS `gates/slop-prune-census.py`'s, and it is reproduced here rather than imported
# because that file's `tokens()` yields tuples and this one needs the line number too.
TOKEN = re.compile(r"(?<![\w./])([\w./-]+)")
FAMILY = re.compile(r"\.\.\.|//")           # an ellipsis or a doubled separator: a family, not a file
JS_COMMENT = re.compile(r"//[^\n]*|/\*.*?\*/", re.S)
# A shell or python ASSIGNMENT whose value is a path-shaped literal. This is the arm that
# catches a path the file uses but never spells in one piece: `RUN="$ROOT/.agents/slop/x"`.
ASSIGN = re.compile(r"""^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*["']([^"']+)["']""")
# AN ASSIGNMENT WHOSE RIGHT-HAND SIDE CARRIES A PATH LITERAL AMIDST OTHER TEXT:
# `BEND = ROOT / ".agents/slop/e2e_mm.bend"`. The first shape above cannot see it, and the
# file it names is WRITTEN on every run, so a census that cannot see it copies a file the
# gate then overwrites -- and the copy is dirty from the first run.
ASSIGN_PATH = re.compile(r"""^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$""")
QUOTED = re.compile(r"""["']([^"']+)["']""")
# A WRITE THROUGH A NAME: `BEND.write_text(...)`. The receiver is a variable, so the path
# is the variable's VALUE.
WRITE_CALL = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*(?:write_text|write_bytes|open)\s*\(")


def whole_literals(line: str) -> set[str]:
    """-> the string literals of `line` whose WHOLE content is a path-shaped token.

    **A PATH SPELLED WHOLE IS A REQUIREMENT AND A PATH EMBEDDED IN A SENTENCE IS A
    CITATION, AND THE DIFFERENCE IS THE WHOLE OF THE PROBLEM.** `stage([PY,
    "checks/.e2e-fixture/e2e_mm.py"])` opens a file. `print("... at all
    (`.agents/slop/e2esh/plant.py`).", file=sys.stderr)` NAMES one, in a sentence, and
    following it as a requirement dragged the whole pruned tree back into the closure
    through a citation in an ERROR MESSAGE -- 29 files the gate does not open.

    The rule is the string's own extent, not a list of call sites: a literal whose content
    IS the token is a path the program uses; a literal with the token inside it is prose
    that happens to be in code."""
    out = set()
    for m in QUOTED.finditer(line):
        lit = m.group(1).strip()
        if lit.startswith("${"):
            lit = lit[2:]
        lit = lit.lstrip("$")
        if lit and "/" in lit:
            out.add(lit)
    return out
WRITE_CALL = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*(?:write_text|write_bytes|open)\s*\(")
# THE DISCOVERY ARM. A gate that resolves one of its inputs BY STEM -- "the one file in this
# directory whose stem is X" -- names NO PATH AT ALL, so a scan of paths cannot see it.
# `.agents/slop/opsbend_milestone_gate.py` declares `_EXPECTED_STEM = "ops_bend-milestone-
# expected"` and finds `ops_bend-milestone-expected.md` BESIDE ITSELF, and that file is
# 4 626 bytes of expectation stage 5 cannot run without. **THE CLOSURE MISSED IT, AND THAT
# IS NOT A HYPOTHETICAL BLIND SPOT -- IT IS A FILE THE GATE NEEDS.** The declaration is the
# tree's own idiom (doctrine 1: a generator's own declaration), so the census reads it.
DISCOVERY = re.compile(r"""^\s*([A-Za-z_][A-Za-z0-9_]*_(?:STEM|PREFIX))\s*=\s*["']([^"']+)["']""")
# THE WRITE ARM. A file a program WRITES is an OUTPUT, and an output that lives in a tracked
# copy DIRTIES THE TREE ON EVERY RUN -- so the census has to know which files are outputs
# before it can say what may be copied. The shapes are the ones the tree's own scripts use:
# a shell redirect, bend's `-o`, and python's three writers.
WRITE = re.compile(r"(?:>>?|\s-o\s+|\srm\s+-\w+\s+)\s*\"?([\w./${}-]+)")
PY_WRITE = re.compile(r"(?:write_text|write_bytes)\(\s*[^)]*?([\w./${}-]+)\s*\)|open\(\s*[\"']([^\"']+)[\"']\s*,\s*[\"']w")

COLUMNS = ("path", "role", "class", "input-output", "cited-by", "transform", "blob", "bytes",
           "sha256", "source", "verdict")


def load(name: str, path: Path):
    """A MODULE, LOADED BY PATH. Never imported by name: `gates/gates-pop.py` has a hyphen."""
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        spec.loader.exec_module(mod)
    return mod


def git(*args: str, cwd: Path | None = None) -> subprocess.CompletedProcess:
    """`git` in ROOT, inheriting the environment -- so an exported `GIT_INDEX_FILE` is honoured
    by construction rather than by a parameter a caller has to remember to pass.

    **THE ROOT IS A PARAMETER, AND IT IS A DIFFERENT ROOT FROM THE ONE THE FILES COME
    FROM.** The plant runs the census over a TEMP COPY of the closure, and the BLOBS it
    compares against are the ones in the REAL repository: a copy is not a repository, and a
    fidelity check that read its expectation out of the copy it is checking would be a
    tautology."""
    return subprocess.run(["git", *args], cwd=str(cwd or ROOT), capture_output=True, text=True)


def blob_of(path: str, git_root: Path | None = None) -> bytes | None:
    """THE BLOB AT THIS PATH IN HEAD, or None. **The blob is the source of truth for a
    recovery, not the worktree**: a worktree another unit edited would otherwise launder its
    bytes into the copy and the copy would be faithful to nothing.

    BYTES, NOT TEXT: the closure holds a 578 KB compiled executable, and a text decode of it
    raises `UnicodeDecodeError` -- a census that dies on a binary is a census whose
    population is the files that happen to be text."""
    r = subprocess.run(["git", "cat-file", "blob", f"HEAD:{path}"], cwd=str(git_root or ROOT),
                       capture_output=True)
    return r.stdout if r.returncode == 0 else None


def head_blob_ids(git_root: Path | None = None) -> dict[str, str]:
    """`path -> blob oid` for HEAD. `git ls-tree -r HEAD -z`, never `git ls-files`: the index
    is armed by design on this tree, and a denominator that moves with another unit's `jj`
    invocation is a reading of the weather."""
    r = git("ls-tree", "-r", "-z", "HEAD", cwd=git_root)
    out = {}
    for rec in r.stdout.split("\0"):
        if not rec:
            continue
        meta, _, path = rec.partition("\t")
        parts = meta.split()
        if len(parts) == 3:
            out[path] = parts[2]
    return out


# ---------------------------------------------------------------------------- the closure
def code_lines_of(path: Path, gp, pp):
    """-> [(lineno, line)] the CODE of `path`, or None when it is not a program.

    **THE CLASSIFIER IS `gates/gates-pop.py:entry_reason()`, THE TREE'S OWN, LOADED BY PATH.**
    `gates/pincensus-pop.py:host_of()` was tried first and it is BLIND to a `zsh` script: its
    shell test is `\\b(?:sh|bash)\\b` and `zsh` does not match it, so
    `.agents/slop/f64/run-f64.sh` and `.agents/slop/e2e_port/run-port-mm.sh` -- THE TWO BIGGEST
    INPUTS THE GATE HAS -- were classified as PROSE and their paths never read. That is
    MEASURED, and it is why the classifier here is the one that knows about `zsh`."""
    try:
        src = path.read_text(errors="replace")
    except OSError:
        return None
    reason = gp.entry_reason(path)
    if reason is None:
        return None
    if reason.startswith("js-"):
        return [(i, l) for i, l in enumerate(src.splitlines(), 1) if JS_COMMENT.sub("", l).strip()]
    if reason.startswith("py-"):
        return pp.code_lines(src, "python")
    return pp.code_lines(src, "shell")


def tokens_of(lines) -> list[tuple[int, str, str, str]]:
    """-> [(lineno, line, token, kind)] every path-shaped token in CODE, and WHETHER IT IS A
    REQUIREMENT OR A CITATION.

    **A PATH SPELLED WHOLE IS A REQUIREMENT; A PATH EMBEDDED IN A SENTENCE IS A CITATION.**
    The two are told apart by the STRING LITERALS of the line, and there are TWO ways a path
    can be spelled whole:

      WHOLE-LITERAL  the token IS the content of a string literal. `stage([PY,
                     "checks/.e2e-fixture/e2e_mm.py"])` opens a file.
      BARE           the token is NOT inside any string literal and stands alone as a word.
                     A shell does not quote every argument: `"$ROOT/.venv/bin/python"
                     checks/.e2e-fixture/opsbend_milestone_gate.py` names a file that is
                     opened, and the token is bare.

    And the third kind, EMBEDDED, is a CITATION: a path inside a longer string literal is
    prose that happens to be in code. `print("... at all (`.agents/slop/e2esh/plant.py`).",
    file=sys.stderr)` NAMES a file in a sentence, and following it as a requirement dragged
    the whole pruned tree back into the closure -- 29 files the gate does not open."""
    out = []
    for lineno, line in lines:
        lits = [(m.start(1), m.end(1), m.group(1).strip()) for m in QUOTED.finditer(line)]
        for m in TOKEN.finditer(line):
            tok = m.group(1)
            if FAMILY.search(tok) or len(tok) < 3:
                continue
            start, end = m.start(1), m.end(1)
            inside = [lit for lo, hi, lit in lits if not (end <= lo or start >= hi)]
            if inside:
                norm = {lit.lstrip("$").removeprefix("${") for lit in inside}
                kind = "WHOLE-LITERAL" if tok in norm else "EMBEDDED"
            else:
                kind = "BARE"
            out.append((lineno, line, tok, kind))
    return out


def substitute(tok: str, assigns: dict[str, str], depth: int = 4) -> str:
    """-> `tok` with a leading VARIABLE replaced by the literal it was assigned.

    **THIS IS THE ARM THAT FINDS THE FILES A FILE USES BUT NEVER SPELLS IN ONE PIECE.**
    `opsbend-milestone.sh` says `RUN="$ROOT/.agents/slop/opsbend-milestone"` and then
    `"$RUN/PACKET.in"`. The first is a path, the second is a VARIABLE followed by a path, and
    a scan that reads only whole tokens sees a directory and a dangling `RUN/PACKET.in` -- so
    it misses the four files the milestone actually reads. Substituting the assignment turns
    the second into `.agents/slop/opsbend-milestone/PACKET.in`, which resolves.

    **THE DOLLAR IS PART OF THE NAME AND NOT PART OF THE ASSIGNMENT, AND GETTING THAT WRONG
    LOSES THE WRITE ARM.** A shell writes `"$RUN/build.out"`, so the token is `$RUN/build.out`
    and the assignment is keyed `RUN`; a substitution that looked up `$RUN` would find
    nothing and the file would be classified an INPUT when a program writes it on every run.
    So the `$` and the braces are stripped before the lookup and put back after it.

    The recursion is bounded (`depth`) because an assignment may name another assignment,
    and a cycle must not hang the census."""
    if depth <= 0:
        return tok
    sigil = ""
    name = tok
    if name.startswith("${"):
        sigil, _, rest = name.partition("}")
        name = rest
        sigil = "${" + sigil
    elif name.startswith("$"):
        sigil, name = "$", name[1:]
    head, sep, rest = name.partition("/")
    if head in assigns:
        return substitute(assigns[head] + sep + rest, assigns, depth - 1)
    return sigil + name


def resolve(tok: str, root: Path) -> tuple[str | None, str | None]:
    """-> (kind, path) for a token: ("file", rel) / ("dir", rel) / (None, None).

    **A VARIABLE PREFIX IS STRIPPED ONE SEGMENT AT A TIME, AND THE RESOLUTION MUST BE
    UNIQUE.** `ROOT/.agents/slop/opsbend-milestone` names a file three segments in; the
    segments before it are a shell variable's value, not part of the path. Stopping at the
    first hit is safe only because the first hit is a FILE; a token that stops at a
    DIRECTORY is a directory reference and is reported as one, because a directory reference
    names every file under it and this census cannot know which of them the gate reads."""
    parts = tok.split("/")
    for i in range(len(parts)):
        rel = os.path.normpath("/".join(parts[i:]))
        if not rel or rel.startswith("..") or rel.startswith("/"):
            continue
        cand = root / rel
        try:
            if cand.is_symlink():
                continue
            if cand.is_file():
                return "file", rel
            if cand.is_dir():
                return "dir", rel
        except OSError:
            continue
    return None, None


def closure(gate: str, root: Path, gp, pp, pinned: dict[str, str] | None = None,
            git_root: Path | None = None) -> dict:
    """The transitive input closure of `gate`, and the shape of the walk that produced it.

    **A PINNED FILE IS A LEAF, AND THAT IS THE POINT.** `checks/e2e.py`'s `ORACLE_SHA` names
    the frozen shell oracle and `BODY_SHA` names the live shell body; both are RECORDS of the
    shell's bytes, and the paths inside them are the SHELL's paths, not the Python port's.
    Recursing into a record and calling what it names a REQUIREMENT is how a census ends up
    asserting that the port needs 23 files it has not used since the fixture was relocated.
    So a file whose bytes are a pin's subject is scanned for nothing and linked from."""
    pinned = pinned or {}
    seen: set[str] = {gate}
    roles: dict[str, str] = {gate: "GATE"}
    cited: dict[str, set[str]] = {}
    dirs: set[str] = set()
    dangling: dict[str, list[str]] = {}
    programs: list[str] = []
    outputs: dict[str, set[str]] = {}
    citations: dict[str, list[str]] = {}
    tails: list[str] = []
    tops = top_level_dirs(root, git_root)
    queue = [gate]
    while queue:
        cur = queue.pop(0)
        path = root / cur
        lines = code_lines_of(path, gp, pp)
        if lines is None:
            roles[cur] = "DATA"
            continue
        roles[cur] = "PROGRAM"
        # THE INVISIBLE TAIL, MEASURED. `gates/pincensus-pop.py:code_lines()` opens a
        # DOCSTRING at a line that is exactly `'''` and closes it at the next line that
        # ENDS with `'''`. A file that embeds a raw triple-quoted block -- and
        # `checks/.e2e-fixture/e2e_mm.py` embeds the whole `.bend` it generates -- ends with
        # a bare `'''`, so everything after it, INCLUDING ITS `if __name__ == "__main__":`
        # GUARD, is invisible to every instrument that asks that function for the code.
        # MEASURED 2026-10-20: the last code line of that file is 549 and the file has 554.
        try:
            total = len(path.read_text(errors="replace").splitlines())
        except OSError:
            total = 0
        if lines and total and lines[-1][0] < total:
            tails.append(f"{cur}: code ends at {lines[-1][0]}, file has {total} lines")
        programs.append(cur)
        if cur in pinned:
            roles[cur] = "PINNED-RECORD"
            continue
        # THE ASSIGNMENT ARM. A path the file uses but never spells in one piece is a path
        # this scan would otherwise miss, and the one that matters here is
        # `RUN="$ROOT/.agents/slop/opsbend-milestone"` -- the whole milestone directory.
        assigns = {m.group(1): m.group(2) for m in
                   (ASSIGN.match(ln) for _, ln in lines) if m}
        for _, line in lines:
            m = ASSIGN_PATH.match(line)
            if not m or m.group(1) in assigns:
                continue
            for lit in QUOTED.findall(m.group(2)):
                if "/" in lit and not lit.startswith("/"):
                    assigns.setdefault(m.group(1), lit)
        for lineno, line, tok, kind in tokens_of(lines):
            if kind == "EMBEDDED":
                citations.setdefault(cur, []).append(f"{lineno}:{tok}")
                continue
            expanded = substitute(tok, assigns)
            for cand in (expanded, tok):
                what, rel = resolve(cand, root)
                if what == "file":
                    cited.setdefault(rel, set()).add(f"{cur}:{lineno}")
                    if rel not in seen:
                        seen.add(rel)
                        queue.append(rel)
                    break
                if what == "dir":
                    dirs.add(rel)
                    break
            else:
                if looks_like_path(tok, tops) and loose_path(tok, tops) not in outputs:
                    dangling.setdefault(cur, []).append(f"{lineno}:{tok}")
        # THE DISCOVERY ARM. The program resolves an input BY STEM beside itself, so the
        # input has no path to be found by. The declaration is in the program's own source.
        for lineno, line in lines:
            m = DISCOVERY.match(line)
            if not m:
                continue
            name, stem = m.group(1), m.group(2)
            for sib in sorted(path.parent.iterdir()):
                if not sib.is_file():
                    continue
                if (sib.stem == stem) if name.endswith("_STEM") else sib.name.startswith(stem):
                    rel = str(sib.relative_to(root))
                    cited.setdefault(rel, set()).add(f"{cur}:{lineno} ({name})")
                    if rel not in seen:
                        seen.add(rel)
                        queue.append(rel)
        # THE WRITE ARM. The same walk, a second question: which of the files this program
        # WRITES. An output is not a requirement, and an output inside a tracked copy is a
        # tree that is dirty every time the gate runs.
        for lineno, line in lines:
            for m in list(WRITE.finditer(line)) + list(PY_WRITE.finditer(line)):
                target = m.group(1) or m.group(2)
                if not target:
                    continue
                rel = loose_path(substitute(target, assigns), tops)
                if rel:
                    outputs.setdefault(rel, set()).add(f"{cur}:{lineno}")
            for m in WRITE_CALL.finditer(line):
                value = assigns.get(m.group(1))
                if not value:
                    continue
                rel = loose_path(substitute(value, assigns), tops)
                if rel:
                    outputs.setdefault(rel, set()).add(f"{cur}:{lineno}")
    return {"files": seen, "roles": roles, "cited": cited, "dirs": dirs,
            "dangling": dangling, "programs": programs, "outputs": outputs,
            "citations": citations, "tails": tails}


def top_level_dirs(root: Path, git_root: Path | None = None) -> set[str]:
    """-> the tree's own top-level directory names, DISCOVERED from the commit tree.

    **A DANGLING PATH IS A PATH-SHAPED TOKEN WHOSE FIRST SEGMENT IS A TREE DIRECTORY, AND
    NOTHING ELSE.** Without that test the census reported 421 dangling tokens, of which the
    real ones were a handful and the rest were `64/64`, `W/a.log` and `apple/metal-3` -- a
    report nobody reads is a report nobody trusts. The directory names come from
    `git ls-tree -r HEAD`, so the test is the tree's own vocabulary and not a list."""
    r = git("ls-tree", "-r", "--name-only", "HEAD", cwd=git_root)
    return {p.split("/", 1)[0] for p in r.stdout.splitlines() if "/" in p}


def loose_path(tok: str, tops: set[str]) -> str:
    """-> the tree-relative path a token names, WHETHER OR NOT THE FILE EXISTS.

    **A FILE THAT DOES NOT EXIST YET IS STILL A PATH, AND THAT IS THE CASE AN OUTPUT IS.**
    `e2e_mm.py` writes `checks/.e2e-fixture/e2e_mm.bend` on every run; the census has to be
    able to say "this is an OUTPUT" about a file that is not on disk until the gate has run
    once, or it copies it, and the copy is then overwritten by the first run."""
    parts = tok.split("/")
    for i in range(len(parts)):
        head = parts[i].lstrip("$")
        if head in tops:
            return "/".join(parts[i:])
    return ""


def looks_like_path(tok: str, tops: set[str]) -> bool:
    """Whether `tok` names something in THIS tree. A token whose first segment is not a
    directory of the tree is not a path of the tree -- it is a word with a slash in it."""
    if tok.startswith("/") or tok.startswith("-"):
        return False
    head = tok.split("/", 1)[0].lstrip(".")
    return head in tops


# ---------------------------------------------------------------- the pin census, loaded by path
def pinned_inputs(gate: str, root: Path, pp, bs) -> dict[str, str]:
    """-> {subject path: the pin name that pins it} for the gate's own byte-pinned inputs.

    **THE TREE'S OWN PIN CENSUS DECIDES THIS, AND IT IS LOADED BY PATH.** A file whose bytes
    are a pin's subject cannot be rewritten: `checks/e2e.py` checks
    `sha256(frozen oracle) == ORACLE_SHA` and `sha256(revert(oracle)) == BODY_SHA` on every
    run, so a moved byte is a RED. A hand list of "the files that are pinned" would be a
    second copy of the pin census with no generator between them."""
    src = root / gate
    try:
        text = src.read_text(errors="replace")
    except OSError:
        return {}
    host = pp.host_of(text)
    code = {gate: pp.code_lines(text, host)} if host != "prose" else {}
    decls = bs.declarations({gate: text}, code)
    out = {}
    for site in pp.rule_a({gate: text}, {gate: host}):
        if site["host"] == "prose":
            continue
        decl = decls.get(gate, {"subjects": {}, "artifacts": {}, "run-dirs": [], "at": {}})
        resolved = bs.resolve(site["name"], decl)
        if resolved is not None and resolved.get("kind") == "SUBJECT":
            out[resolved["value"]] = site["name"]
        for key in (site.get("pairs") or {}):
            out.setdefault(key, site["name"])
    return out


def declared_but_unused(gate: str, root: Path, pp, bs) -> list[dict]:
    """The gate's `_SUBJECT` declarations that its own code NEVER LOADS.

    **A DECLARATION NOBODY READS IS A LITERAL WITH A NAME ON IT.** `checks/e2e.py` declares
    `ORACLE_SUBJECT = ".agents/slop/e2epy/oracle-e2e.sh"` and `BODY_SUBJECT = "checks/e2e.sh"`,
    and `oracle_drift()` reads the subject from a LITERAL in the code instead:
    `copy = REPO / ".agents/slop/e2epy/oracle-e2e.sh"`. The two agree today BY COINCIDENCE.
    The pin census measures the DECLARATION, so a reader of that census is reading a subject
    the gate does not read -- and the moment they disagree, the census goes on measuring a
    subject the gate ignores. MEASURED 2026-10-20: both declarations are never loaded."""
    src = root / gate
    try:
        text = src.read_text(errors="replace")
        tree = ast.parse(text)
    except (OSError, SyntaxError, ValueError):
        return []
    loaded = {n.id for n in ast.walk(tree) if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load)}
    declared = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            name = node.targets[0].id
            if name.endswith("_SUBJECT") and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
                declared.add((name, node.value.value))
    out = []
    for name, value in sorted(declared):
        out.append({"name": name, "value": value, "loaded": name in loaded,
                    "in-code": value in text})
    return out


# ---------------------------------------------------------------- the copy, and its fidelity
def transform_of(old: bytes, pinned: bool) -> bytes:
    """The bytes the copy must have. A PINNED file is copied VERBATIM; every other file is
    RELOCATED, which is the prefix substitution and NOTHING ELSE."""
    if pinned:
        return old
    return old.replace(SLOP.encode() + b"/", HOME.encode() + b"/")


def copy_path(rel: str) -> str:
    """The path of `rel` in the new home. A file outside the pruned tree has no copy."""
    if not rel.startswith(SLOP + "/"):
        return ""
    return HOME + "/" + rel[len(SLOP) + 1:]


def census(gate: str, root: Path, git_root: Path | None = None) -> dict:
    """Every measurement, in one dict, so the report computes nothing of its own."""
    gp = load("edge_fixture_gp", root / "gates" / "gates-pop.py")
    pp = load("edge_fixture_pp", root / "gates" / "pincensus-pop.py")
    bs = load("edge_fixture_bs", root / "gates" / "bind-subject.py")
    if not (gp and pp and bs):
        return {"error": "the tree's own instruments did not load"}
    pinned = pinned_inputs(gate, root, pp, bs)
    cl = closure(gate, root, gp, pp, pinned, git_root)
    if not cl["files"]:
        return {"error": "the closure found 0 files"}
    ids = head_blob_ids(git_root)
    rows = []
    for rel in sorted(cl["files"]):
        if rel == gate:
            continue
        # WHERE THE FILE LIVES, AND WHERE IT CAME FROM. A file under the pruned tree is a
        # REQUIREMENT the tree has not moved yet; a file under the new home is the copy of
        # the file at the SAME relative path under the pruned tree, and its source is
        # discovered by inverting the home -- not written down here.
        under_home = rel.startswith(HOME + "/")
        under_slop = rel.startswith(SLOP + "/")
        if under_home:
            src, dst = SLOP + "/" + rel[len(HOME) + 1:], rel
        elif under_slop:
            src, dst = rel, copy_path(rel)
        else:
            src = dst = ""
        old = blob_of(src, git_root) if src else None
        is_pinned = rel in pinned or src in pinned
        want = transform_of(old, is_pinned) if old is not None else None
        verdict = "-"
        if src:
            if src in cl["outputs"] or rel in cl["outputs"]:
                # AN OUTPUT IS NOT COPIED. A file a program writes is not a requirement, and a
                # copy of it inside a tracked tree is a tree that is dirty every time the gate
                # runs -- and `opsbend-milestone.sh` REBUILDS `bend-executor` whenever the
                # source is newer, so a tracked copy of it would change on the next run.
                verdict = "OUTPUT-NOT-COPIED"
            else:
                cp = root / dst
                if not cp.is_file():
                    verdict = "MISSING"
                elif old is None:
                    verdict = "NO-BLOB"
                elif cp.read_bytes() == want:
                    verdict = "CURRENT"
                else:
                    verdict = "MISMATCH"
        rows.append({
            "path": rel,
            "role": cl["roles"].get(rel, "DATA"),
            "class": ("FIXTURE" if under_slop else "COPY" if under_home else "TREE"),
            "input-output": ("OUTPUT" if rel in cl["outputs"] else "INPUT"),
            "cited-by": ";".join(sorted(cl["cited"].get(rel, ()))) or "-",
            "transform": ("PINNED-VERBATIM" if is_pinned else "RELOCATED") if src else "-",
            "blob": ids.get(rel, "-"),
            "bytes": len(old) if old is not None else -1,
            "sha256": hashlib.sha256(want).hexdigest()[:16] if want is not None else "-",
            "source": src or "-",
            "verdict": verdict,
        })
    # EVERY FILE IN THE NEW HOME IS VERIFIED, NOT ONLY THE ONES THE CLOSURE REACHES. A copy
    # that is checked only where the closure happens to point leaves the rest of it
    # unaccounted for, and "unaccounted for" is how a stale file survives a move.
    home = root / HOME
    for path in sorted(home.rglob("*")) if home.is_dir() else []:
        if not path.is_file():
            continue
        rel = str(path.relative_to(root))
        if any(r["path"] == rel for r in rows):
            continue
        src = SLOP + "/" + rel[len(HOME) + 1:]
        old = blob_of(src, git_root)
        is_pinned = rel in pinned or src in pinned
        want = transform_of(old, is_pinned) if old is not None else None
        verdict = "NO-BLOB" if old is None else ("CURRENT" if path.read_bytes() == want else "MISMATCH")
        rows.append({
            "path": rel, "role": "COPY", "class": "COPY",
            "input-output": "INPUT", "cited-by": "-",
            "transform": "PINNED-VERBATIM" if is_pinned else "RELOCATED",
            "blob": ids.get(src, "-"), "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()[:16],
            "source": src, "verdict": verdict,
        })
    # THE BLIND SPOT, COUNTED. Bodies that hold the pruned tree's prefix without naming a
    # census path are the necessary condition for a RUNTIME-ASSEMBLED citation, and the
    # closure cannot see those. It is a number, printed, never a silence.
    prefix_holders = []
    for base in ("checks", "gates"):
        d = root / base
        if not d.is_dir():
            continue
        for entry in sorted(d.iterdir()):
            if not entry.is_file() or entry.suffix not in (".py", ".sh", ".mjs"):
                continue
            try:
                body = entry.read_text(errors="replace")
            except OSError:
                continue
            if SLOP + "/" in body and not any(r["path"] in body for r in rows):
                prefix_holders.append(f"{base}/{entry.name}")
    return {"gate": gate, "rows": rows, "closure": cl, "pinned": pinned,
            "prefix_holders": prefix_holders,
            "unused_declarations": declared_but_unused(gate, root, pp, bs),
            "head": git("rev-parse", "HEAD", cwd=git_root).stdout.strip()}


def report(c: dict) -> int:
    rows, cl = c["rows"], c["closure"]
    fixture = [r for r in rows if r["class"] == "FIXTURE"]
    copies = [r for r in rows if r["class"] == "COPY"]
    verdicts = {}
    for r in copies:
        verdicts[r["verdict"]] = verdicts.get(r["verdict"], 0) + 1
    print(f"edge-fixture-census   gate {c['gate']}   HEAD {c['head']}   "
          f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}")
    print(f"  CLOSURE     transitive, by WALK over the gate's own CODE. "
          f"{len(cl['files'])} files, {len(cl['programs'])} of them programs")
    print(f"    programs scanned {len(cl['programs'])}   data {len(cl['files']) - len(cl['programs'])}")
    print(f"    DIRECTORY references {len(cl['dirs'])}: " + (", ".join(sorted(cl['dirs'])) or "-"))
    print(f"    DANGLING path-shaped tokens (named, absent) {sum(len(v) for v in cl['dangling'].values())}")
    for f, v in sorted(cl["dangling"].items()):
        for item in sorted(set(v)):
            print(f"      {f}: {item}")
    print(f"  INVISIBLE   {len(cl['tails'])} program(s) have a tail the tree's own "
          f"`code_lines()` cannot see.")
    print("    `code_lines()` opens a docstring at a line that is exactly `'''` and closes it at")
    print("    the next line that ENDS with `'''`, so a file embedding a raw triple-quoted block")
    print("    has its last lines -- including its `__main__` guard -- invisible. A census that")
    print("    does not say so reads a tail that is not there as an absence of paths.")
    for t in cl["tails"]:
        print(f"      ? {t}")
    print(f"  FIXTURE     {len(fixture)} of {len(rows)} closure files are still under {SLOP}/ "
          f"-- the RISK, and it is the number that says whether a prune can still break this gate.")
    print(f"  COPY        {len(copies)} closure files live in the new home {HOME}/.")
    for v in ("CURRENT", "MISMATCH", "MISSING", "NO-BLOB", "OUTPUT-NOT-COPIED"):
        if v in verdicts:
            print(f"    {v:<18} {verdicts[v]}")
    outs = [r for r in rows if r["input-output"] == "OUTPUT"]
    print(f"    of which OUTPUT {len(outs)}: a file a program WRITES is not a requirement, and "
          f"an output\n    inside a tracked copy is a tree that is dirty every time the gate runs.")
    for r in outs:
        print(f"      OUTPUT {r['path']}")
    print(f"    copy home  {HOME}/  (in git, beside the gate, NOT under the pruned tree)")
    print(f"    PINNED     {len(c['pinned'])} of the gate's inputs are byte-pinned and are copied "
          f"VERBATIM:")
    for path, name in sorted(c["pinned"].items()):
        print(f"      {name:<16} {path}")
    print(f"  BLIND SPOT  {len(c['prefix_holders'])} live bodies hold the '{SLOP}/' prefix without "
          f"naming a closure path.")
    print("    That is the necessary condition for a RUNTIME-ASSEMBLED citation, which a static")
    print("    closure cannot see. The closure is a LOWER BOUND and this is the size of the gap.")
    for h in c["prefix_holders"]:
        print(f"      ? {h}")
    unused = [d for d in c["unused_declarations"] if not d["loaded"]]
    print(f"  SUBJECTS    {len(c['unused_declarations'])} `_SUBJECT` declaration(s) in the gate; "
          f"{len(unused)} of them are NEVER LOADED by the gate's own code.")
    for d in c["unused_declarations"]:
        state = "LOADED" if d["loaded"] else "NEVER-LOADED"
        print(f"      {d['name']:<16} {state:<14} {d['value']}")
    bad = [r for r in rows if r["verdict"] in ("MISMATCH", "MISSING", "NO-BLOB")]
    return FAIL if bad else PASS


def plant(c: dict) -> int:
    """THE PLANT, IN A TEMP REPOSITORY. The tree is not touched.

    THREE QUESTIONS, AND THE THIRD IS THE CONTROL THAT MAKES THE SECOND MEANINGFUL.

    **THE PLANT RUNS IN ITS OWN GIT REPOSITORY, AND THAT IS WHAT MAKES THE CONTROL
    POSSIBLE.** The census compares the copy's BYTES with the TRANSFORM of a BLOB's bytes.
    A control that moves both sides at once needs the blob to move too, and the blob lives
    in a repository -- so the plant builds one: a mirror of the closure, `git init`, one
    commit. The blob is then the mirror's own, and the plant can move it.

    **AND THE MIRROR IS A MIRROR, NOT THE TREE.** Copying 194 MB of `.agents/slop/` to
    perturb 40 files is a slow way to learn nothing; the mirror holds the closure, the
    sources the copies came from, and nothing else."""
    import shutil
    import tempfile
    gate = c["gate"]
    copies = [r for r in c["rows"] if r["class"] == "COPY" and r["verdict"] == "CURRENT"]
    if not copies:
        print("PLANT REFUSED: no copy is CURRENT, so there is nothing to perturb")
        return REFUSED
    victim = min(copies, key=lambda r: len(r["path"]))
    with tempfile.TemporaryDirectory(prefix="edge-fixture-plant.") as tmp:
        mirror = Path(tmp) / "repo"
        mirror.mkdir()
        wanted = {r["path"] for r in c["rows"]} | {r["source"] for r in c["rows"] if r["source"] != "-"}
        wanted.add(gate)
        # THE TREE'S OWN INSTRUMENTS, because the census in the mirror needs them and they
        # are not part of the gate's closure. They are named HERE, in the plant, and not
        # anywhere in the census: a census that loads a different instrument in a different
        # tree is two instruments.
        wanted |= {"gates/gates-pop.py", "gates/pincensus-pop.py", "gates/bind-subject.py"}
        for rel in sorted(wanted):
            src = ROOT / rel
            if not src.is_file():
                continue
            dst = mirror / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
        git("-c", "user.email=plant@localhost", "-c", "user.name=plant", "init", "-q", cwd=mirror)
        git("-c", "user.email=plant@localhost", "-c", "user.name=plant", "add", "-A", cwd=mirror)
        git("-c", "user.email=plant@localhost", "-c", "user.name=plant", "commit", "-q",
            "-m", "plant baseline", cwd=mirror)
        gp = load("edge_fixture_gp2", mirror / "gates" / "gates-pop.py")
        pp = load("edge_fixture_pp2", mirror / "gates" / "pincensus-pop.py")
        bs = load("edge_fixture_bs2", mirror / "gates" / "bind-subject.py")
        base = census(gate, mirror, mirror)
        # ---- PLANT 1: DISCOVERY. A new file, named by a CODE line the scanner must follow.
        planted = f"{SLOP}/edge-plant-probe.txt"
        (mirror / planted).parent.mkdir(parents=True, exist_ok=True)
        (mirror / planted).write_text("planted\n")
        host = mirror / victim["path"]
        # THE REFERENCE GOES WHERE THE SCANNER CAN SEE IT, AND WHERE THAT IS, IS MEASURED.
        # `gates/pincensus-pop.py:code_lines()` opens a DOCSTRING at a line that is exactly
        # `'''` and never closes it, so the tail of a file that embeds a raw triple-quoted
        # block is invisible -- and `checks/.e2e-fixture/e2e_mm.py` ends with such a block,
        # so its `if __name__ == "__main__":` is invisible too. A plant that appended its
        # reference at the end of that file would be testing the DOCSTRING BUG and not the
        # scanner, so the reference goes in after the FIRST line, which every reader sees.
        body = host.read_text()
        host.write_text(body.replace("\n", f'\nPLANTED_REF = "{planted}"\n', 1))
        after = census(gate, mirror, mirror)
        grew = sorted(set(after["closure"]["files"]) - set(base["closure"]["files"]))
        # THE PLANT IS PUT BACK, because the next two questions are about FIDELITY and a
        # leftover edit in the copy would make the control's answer meaningless: the control
        # moves the copy and the blob TOGETHER, and a copy that also carries plant 1's edit
        # is not the copy the blob describes.
        host.write_text(body)
        # ---- PLANT 2: FIDELITY, ONE SIDE. The COPY moves; the blob does not.
        dst = mirror / victim["path"]
        dst.write_bytes(dst.read_bytes() + b"plant\n")
        two = census(gate, mirror, mirror)
        row2 = next(r for r in two["rows"] if r["path"] == victim["path"])
        # ---- PLANT 3: THE CONTROL. The SAME byte moves on BOTH sides, and the blob is
        # re-committed, so the expectation moves with the copy.
        dst.write_bytes(dst.read_bytes()[:-len(b"plant\n")])
        source = mirror / victim["source"]
        source.write_bytes(source.read_bytes() + b"plant\n")
        git("-c", "user.email=plant@localhost", "-c", "user.name=plant", "add", "-A", cwd=mirror)
        git("-c", "user.email=plant@localhost", "-c", "user.name=plant", "commit", "-q",
            "-m", "plant both sides", cwd=mirror)
        dst.write_bytes(dst.read_bytes() + b"plant\n")
        three = census(gate, mirror, mirror)
        row3 = next(r for r in three["rows"] if r["path"] == victim["path"])
        checks = [
            ("plant 1: the closure GREW by exactly the planted file",
             grew == [planted], f"grew {grew}"),
            ("plant 2: one side moved -> MISMATCH", row2["verdict"] == "MISMATCH", row2["verdict"]),
            ("plant 3 (CONTROL): both sides moved -> CURRENT",
             row3["verdict"] == "CURRENT", row3["verdict"]),
        ]
        print(f"PLANT, in a TEMP REPOSITORY at {mirror}. The tree was not touched.")
        print(f"  PLANTED FILE  {planted}   named by a code line added to {victim['path']}")
        print(f"  PERTURBED     {victim['path']} (the copy) and {victim['source']} (the blob side)")
        for name, ok, detail in checks:
            print(f"  {'OK  ' if ok else 'FAIL'}  {name:<58} {detail}")
        ok = all(c[1] for c in checks)
        print(f"  VERDICT {'PASS' if ok else 'FAIL'}")
        return PASS if ok else FAIL


def write_rows(c: dict, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with dest.open("w") as fh:
        fh.write(f"# {LEDGER} -- TAB separated. Generated; the generator is "
                 f"`gates/edge-fixture-census.py`, the ONLY writer.\n")
        fh.write(f"# columns: {', '.join(COLUMNS)}\n")
        fh.write(f"# written {stamp} HEAD={c['head']} gate={c['gate']}\n")
        for r in c["rows"]:
            fh.write("\t".join(str(r[col]) for col in COLUMNS) + "\n")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--gate", default=DEFAULT_GATE, help="the gate to census")
    ap.add_argument("--rows", default=LEDGER, help="where the need ledger is written")
    ap.add_argument("--plant", action="store_true", help="the plant, in a temp copy")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args(argv)
    c = census(a.gate, ROOT)
    if "error" in c:
        print(f"REFUSED: {c['error']}", file=sys.stderr)
        return REFUSED
    if a.plant:
        return plant(c)
    if not a.quiet:
        write_rows(c, ROOT / a.rows)
        rc = report(c)
    else:
        rc = FAIL if [r for r in c["rows"]
                      if r["verdict"] in ("MISMATCH", "MISSING", "NO-BLOB")] else PASS
    return rc


if __name__ == "__main__":
    sys.exit(main())
