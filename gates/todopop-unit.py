#!/usr/bin/env python3
"""todopop-unit.py -- THE POPULATION. One declaration, loaded by path, that says what a row is.

    .venv/bin/python gates/todopop-gate.py --numbers    # every unit, differently named

THE FILENAME CARRIES A HYPHEN, so this file cannot be imported and is loaded BY PATH. That is the
point: `gates/todo-census.py` and `gates/todopop-gate.py` are two consumers of ONE declaration, and
the declaration has no name to be imported under. It is the `differ.declared()` shape (doctrine 1):
a generator's own declaration, loaded by path, instead of a list a reader has to keep in sync.

WHAT A ROW IS. A row is ONE LINE of ONE `.bend` file of the subject that contains the token
`TODO` under `\bTODO\b`. One line yields at most one row no matter how many tokens it carries.
The census calls this a SITE; this file calls it a ROW; they are the same unit and the name is not
load-bearing.

WHY THE LINE AND NOT THE TOKEN, FROM THE TEXT AND NOT FROM A COUNT. The port cites its own work by
`file:line`, so a line is the finest address the tree already uses, and a token inside a line is not
addressable by anything the tree writes down. The token unit is not a finer cut of the same thing
either. Read `todopop-gate.py --numbers`: TOKEN-OCCURRENCES is larger than ROWS, and every line
accounting for the difference is either two REAL tasks on one line (`tinybendygrad/tensor.bend`
carries "both as `TODO(p3) ops.py:821` and `TODO(p3) ops.py:655`") or one task plus a pointer at
another (`tinybendygrad/uop/weak.bend`, "see the TODO on that def"). So the token unit
under-counts tasks and over-counts pointers; the line is the unit that can be addressed, cited and
re-found. A TASK count is a different question and is not reported here.

WHY `\bTODO\b` AND NOT THE SUBSTRING. `TODOs` in prose -- "the four TODOs it lists", in
`tinybendygrad/runtime/support/am/amdev.bend` and five other files -- is a mention of a set, not a
marker. The substring unit reads those as rows and the word-boundary unit does not; `--numbers`
reports both under their own names, and the difference is exactly those lines.

WHAT A ROW IS NOT. Not a task, which is not derivable from text; not a file, which `--numbers`
reports as ROWS-FILES; not a tracked file, which excludes the untracked `.bend` files a porting
unit is adding right now; and not a classification -- `todo-census.py` cuts its rows into
GAP/NONG/FRAG/XREF/UNDECIDED and this file cuts none of them, so a change to that taxonomy cannot
move this population.

A POPULATION THAT IS A REGEX PLUS A WALK. `TOKEN` is the shape, `walk` is the discovery. Both are
statements about how to FIND rows, not about how many there are: this file contains no count, no
expected value and no transcription, so it cannot go stale when the subject moves -- and the subject
IS moving, which is why every number `todopop-gate.py` prints arrives with a digest and a stamp.
"""
import hashlib
import os
import re
from datetime import datetime, timezone

# The token. `\bTODO\b` is the whole unit's definition of "mentions TODO"; `todopop-gate.py` lane 1
# reads this literal back out of `todo-census.py`'s AST and FAILS if the two ever differ.
TOKEN = re.compile(r"\bTODO\b")

# The near-miss unit, declared so the control in the plant has a name and not a magic string.
SUBSTRING = re.compile("TODO")


def unit():
    """The one-sentence statement, for a report to quote without re-deriving it."""
    return ("ROW = one line of one .bend file of the subject containing the token TODO under "
            r"\bTODO\b; one line yields at most one row however many tokens it carries")


def walk(root, ext=".bend"):
    """The subject, DISCOVERED. os.walk + endswith; never glob, which returns [] on this tree."""
    found = []
    for dirpath, _dirs, names in os.walk(root):
        for name in names:
            if name.endswith(ext):
                found.append(os.path.join(dirpath, name))
    return sorted(found)


def key(path, repo, root):
    """A row's path component, under the census's own rule.

    `todo-census.py` emits `relpath(path, REPO if path.startswith(REPO) else root)`, so a live row
    reads `tinybendygrad/uop/ops.bend` and a row of a planted copy reads `uop/ops.bend`. This is
    restated, not improved on: the gate compares SETS of the census's own strings, and if the
    census's rule changes, the comparison fails rather than silently re-normalising to a match.
    """
    return os.path.relpath(path, repo if path.startswith(repo) else root)


def rows(paths, repo, root):
    """[(path key, 1-based line)] -- one row per line, in walk order then line order."""
    out = []
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for number, line in enumerate(handle.read().splitlines(), 1):
                if TOKEN.search(line):
                    out.append((key(path, repo, root), number))
    return out


def tokens(paths):
    """The token unit: how many `\bTODO\b` occurrences the same files carry. A DIFFERENT question."""
    return sum(len(TOKEN.findall(open(p, encoding="utf-8", errors="replace").read()))
               for p in paths)


def substring_rows(paths):
    """The near-miss unit: lines carrying `TODO` at all, boundaries or not."""
    total = 0
    for path in paths:
        text = open(path, encoding="utf-8", errors="replace").read()
        total += sum(1 for line in text.splitlines() if SUBSTRING.search(line))
    return total


def digest(paths, repo=None):
    """Content pin for the subject: sha256 over `sha256  relpath` in walk order.

    A count of a moving tree is a reading, not a fact, and the tree IS moving -- a unit is porting
    `tinybendygrad/extra/`. Two runs whose digests differ measured two subjects, whatever their
    row sets have in common, and two runs whose digests agree measured one subject and may be
    compared forever.
    """
    sha = hashlib.sha256()
    for path in paths:
        name = os.path.relpath(path, repo) if repo else path
        with open(path, "rb") as handle:
            sha.update(f"{hashlib.sha256(handle.read()).hexdigest()}  {name}\n".encode())
    return sha.hexdigest()


def stamp():
    """UTC, so a reading quoted in a report names the minute it was taken in."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
