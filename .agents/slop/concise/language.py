#!/usr/bin/env python3
"""Prose that explains the LANGUAGE, not the project.

The named target: "# increment the counter", "# return the list". Every other
target in the `concise` brief is a comparison against something already in the
file. This one is different: it is defined by what a sentence does NOT contain.
A language-explaining comment mentions only words the reader already knows from
reading the code -- keywords, builtins, stdlib names -- and NO name that belongs
to this project. So the test is a NEGATIVE:

  A comment qualifies only if EVERY content word is in the language vocabulary
  (Python keywords, builtins, `dir(builtins)`, and the stdlib modules this tree
  imports) AND it names nothing project-specific: no backticked identifier, no
  `.bend`/`.py`/`.md`/`.rows` filename, no path separator, no tinygrad symbol
  (a capitalised `CamelCase`, which is how this project spells its own types),
  and no digit.

That last clause is what makes the filter honest rather than convenient: this
tree's load-bearing comments are full of `ops.py:1408` and `7 dtypes`, and a
detector that could not see them would propose deleting the evidence. The
negative is checked FIRST, so a sentence carrying any of those never reaches the
vocabulary test.

Population: every tracked .py, os.walk x `git ls-tree -r HEAD`.
"""

import ast
import builtins
import io
import keyword
import os
import re
import subprocess
import sys
import tokenize

ROOTS = ("checks", "gates", "tinybendygrad", ".agents/slop")
STDLIB = {
    "os", "sys", "re", "io", "ast", "json", "math", "time", "subprocess", "shutil",
    "pathlib", "Path", "tempfile", "hashlib", "collections", "itertools", "functools",
    "dataclasses", "typing", "unittest", "argparse", "csv", "difflib", "fnmatch",
    "textwrap", "pickle", "random", "string", "operator", "enum", "abc", "copy",
    "contextlib", "stat", "signal", "socket", "struct", "threading", "traceback",
    "warnings", "weakref", "gzip", "platform", "shlex", "glob", "inspect", "abc",
}
WORDLIST = "/usr/share/dict/words"


def english() -> set[str] | None:
    """Plain English, casefolded. Needed because the brief's own example of the
    target is "# increment the counter" -- `increment` and `counter` are ENGLISH,
    not Python names, so a vocabulary of keywords and builtins cannot see them.
    v1 of this detector used exactly that vocabulary, its control FAILED, and it
    reported 0 over 18 285 comment lines for the wrong reason. Returns None when
    the wordlist is absent, and the caller REFUSES rather than reporting a zero
    it cannot support."""
    try:
        with open(WORDLIST, encoding="utf-8", errors="replace") as fh:
            return {line.strip().casefold() for line in fh if line.strip()}
    except OSError:
        return None


ENGLISH = english()
LANG = (set(keyword.kwlist) | set(dir(builtins)) | STDLIB
        | {"self", "cls", "None", "True", "False", "args", "kwargs", "stdout",
           "stderr", "stdin", "rc", "argv", "env", "idx", "i", "j", "n", "x", "y",
           "key", "val", "vals", "tmp", "src", "dst", "fd", "buf", "data", "out"}
        | (ENGLISH or set()))
PROJECT = re.compile(
    # NO re.IGNORECASE. v1 had it, and `[A-Z][a-z]+[A-Z]` -- the CamelCase
    # detector for this project's own type names -- then matched ANY lowercase
    # word of 3+ letters, including the `increment` in the brief's own example.
    # The control caught it; without the control this detector would have
    # reported a clean 0 over 18 285 comment lines while matching everything.
    # Case sensitivity is the POINT of the CamelCase clause.
    r"`|[:/\\]|_[a-z]|[A-Z][a-z]+[A-Z]|\.bend|\.py|\bTODO\b|\d")
STOP = frozenset("""a an the of to in is are was be been being and or not for with on at
by from as it its this that these those then than so such do does did doing have has had
will would can could should may might must not no nor only just also very much more most
some any each every other another same new old good bad better best first last next prev
""".split())
BANNER = re.compile(r"^[-=#*~]{3,}\s*[A-Z][A-Z ]*\s*[-=#*~]{3,}$|^-{3,}\s")
# The POSITIVE half. v3 used only the negative ("names nothing project-specific")
# and reported 141 blocks of 5 493 -- but reading them, they are PROJECT RATIONALE
# in plain English: "a dead lane is never a green one", "LAST, because it is the
# only step that can be undone by a later one". None of those explains the
# LANGUAGE, and all of them pass a "no filename" test, so the negative is
# necessary and not sufficient. A block qualifies only if it also names a language
# MECHANISM -- the things a reader already knows from reading the code.
MECHANISM = frozenset("""assign assigns assignment loop loops looping iterate iterates
iteration return returns returning parameter parameters argument arguments list lists
dict dicts dictionary string strings literal literals import imports call calls calling
variable variables increment decrement initialise initialize init bool boolean integer
float keyword identifier scope block tuple set comprehension slice index subscript
""".split())


def prose(path: str):
    """Yield (first_lineno, MERGED_RUN_TEXT) -- one entry per consecutive comment
    BLOCK, not per physical line.

    v2 of this detector tested each PHYSICAL line and reported 1 383 hits over
    18 285 lines, and every one I looked at was a CONTINUATION of a wrapped
    sentence: "citation could plausibly name." is the tail of a sentence whose
    first line named a file. A block's meaning is distributed ACROSS its lines, so
    testing a line answers a question nobody asked. Merging the run first is the
    fix, and the count that comes out is the one to quote.
    """
    with open(path, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(src).readline))
    except (tokenize.TokenError, SyntaxError):
        return
    run: list[str] = []
    start = 0
    prev_line = -2
    for tok in toks:
        if tok.type != tokenize.COMMENT:
            continue
        text = tok.string.lstrip("#").strip()
        if tok.start[0] != prev_line + 1:
            if run:
                yield start, " ".join(run)
            run, start = [], tok.start[0]
        run.append(text)
        prev_line = tok.start[0]
    if run:
        yield start, " ".join(run)


def fires(text: str) -> bool:
    """THE rule, in one place. `plant.py` imports THIS rather than restating it:
    an earlier version of the control kept its own copy of the three-clause test
    and therefore lacked the MECHANISM clause, so it PASSED a case the detector
    rejects -- a second copy of the rule is the same fault as a second copy of a
    population, and it makes the control measure the copy."""
    if len(text.split()) < 3 or PROJECT.search(text) or BANNER.match(text):
        return False
    content = {w.casefold() for w in re.findall(r"[A-Za-z_][A-Za-z_0-9]*", text)} - STOP
    return bool(content) and content <= LANG and bool(content & MECHANISM)


def main() -> int:
    if ENGLISH is None:
        print(f"REFUSED, NOT A VERDICT: no wordlist at {WORDLIST}, and a vocabulary of "
              f"keywords and builtins alone cannot see the target class -- the brief's "
              f"own example '# increment the counter' is two ENGLISH words. Reporting a "
              f"zero here would be a zero with no instrument behind it.")
        return 3

    tracked = set(subprocess.run(
        ["git", "ls-tree", "-r", "HEAD", "--name-only", "--", *ROOTS],
        capture_output=True, text=True, check=True).stdout.splitlines())
    files = []
    for root in ROOTS:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            files += [os.path.join(dirpath, f) for f in filenames if f.endswith(".py")]
    files = sorted(set(files) & tracked)

    hits, checked = [], 0
    for path in files:
        for lineno, text in prose(path):
            checked += 1
            if fires(text):
                hits.append((path, lineno, text))

    print(f"population: {len(files)} tracked .py files, os.walk x git ls-tree -r HEAD; "
          f"{checked} comment BLOCKS examined (a block is a run of consecutive comment "
          f"lines, merged -- a line is not a unit of meaning here)")
    print(f"vocabulary: {len(LANG)} tokens = keywords + builtins + {len(STDLIB)} stdlib "
          f"names + {len(ENGLISH)} words from {WORDLIST}, casefolded")
    print(f"LANGUAGE-EXPLAINING PROSE (every content word is a known word, the block "
          f"names nothing project-specific, AND it names a language MECHANISM): "
          f"{len(hits)}\n")
    for path, lineno, text in hits[:40]:
        print(f"  {path}:{lineno}  {text[:100]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
