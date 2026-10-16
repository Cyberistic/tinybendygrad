#!/usr/bin/env python3
"""Census of UNRUNNABLE RECIPES in `.bend` files: a documented procedure whose named paths do not resolve.

THE QUESTION.  "SOMETHING WAS WRITTEN AND NOTHING READS IT BACK" is the dominant defect class in this
tree, and the shipped half of it is a PROCEDURE THAT CANNOT BE RUN: a `.bend` file prints a recipe in
a comment, and the script or oracle the recipe names is gone.  `tinybendygrad/mixin/rand.bend:85-88`
is the named instance (`$ORACLE_DIR/rd-gate.sh`, `rd-truth.py`, `rd-mutate.py`).  The question is not
"is `rand.bend` broken" -- it is HOW MANY SHIPPED FILES DOCUMENT A PROCEDURE THAT NO LONGER RUNS, AND
WHAT IS THE DENOMINATOR.

HOW THE POPULATION IS FOUND, AND WHY IT IS NOT A LIST.
  FILES:   `os.walk` over ROOTS, `.bend` suffix.  A DIRECTORY WALK, per doctrine 1.
  TOKENS:  ONE permissive pattern, no suffix set and no truncation.  Every shell/word-delimited run
           that contains a `/` and a `.` after its last `/` is a CANDIDATE.  A candidate is RESOLVED
           AGAINST THE FILESYSTEM, never filtered by its extension.
  BECAUSE A TRUNCATED TOKEN IS NOT A HARMLESSLY BLIND ONE, IT IS A TOKEN THAT WRITES FALSE ROWS IN
  BOTH DIRECTIONS.  `checks/repro-paths.py`'s `(?:sh|py|bend|mjs|json)` read
  `...blastradius.cpython-312.pyc` as `...312.py` (a DANGLING row for a name that never existed) and
  read `gates/tn_graph_census-gate.py.bak` as `...gate.py` -- A FILE THAT EXISTS, so a broken
  reference counted as RESOLVED.  So there is no suffix filter here to be stale and nothing to
  truncate: the token is taken whole and `os.path.exists` decides.

FOUR STATES PER NAMED PATH, AND THE THREE-STATE QUESTION IS THREE QUESTIONS.
  ON DISK / IN HEAD / NEITHER.  "IS IT IN `HEAD`" IS A DIFFERENT QUESTION WITH A DIFFERENT ANSWER
  from "does it exist": the colocated-`jj` index arms `git ls-files` with `e69de29b` placeholders for
  untracked files, so the INDEX is asked about neither.  HEAD IS `git ls-tree -r HEAD --name-only`,
  which no `jj` subcommand rewrites.
  Plus a FIFTH state that is not a state of the path: `UNRESOLVED-ENV`, for a `$VAR/...` token whose
  variable has no assignment in the same file.  An unassigned variable is not a missing path; it is a
  path this file never told you where to look, and it is reported as its own row.

WHAT A "RECIPE" LABEL MEANS HERE, AND WHY IT IS NOT THE POPULATION.
  The POPULATION is every path token in every `.bend` file the walk found.  `RECIPE` is a LABEL on a
  row, applied afterwards, and the label is deliberately generous: a token in COMMAND POSITION -- the
  first token of a comment-stripped line, or a `$VAR/...` prefix, or a `name.ext` whose extension is
  in COMMAND_WORDS -- which is how a procedure reads itself.  A label cannot hide a row, because every
  unresolved token is printed whether or not it earned the label.

AND "EXISTS" IS NOT "RUNS".  For every path that resolves, the tree is asked whether the basename
appears on any NON-COMMENT line anywhere (`READS=code`) or only inside comments (`READS=prose`).  A
comment is a citation; a code line is a reader.  "EXISTS, AND NOTHING EXECUTES IT" AND "EXISTS, AND
SOMETHING EXECUTES IT" ARE DIFFERENT ROWS AND THE SECOND IS RARE.

OUTPUT.  A `.rows` table, one row per named path, plus a summary on stdout.  Exit 0 always: this is a
CENSUS, and a census that returns non-zero is a gate, and nothing calls this.

THE OUTPUT IS BYTE-REPRODUCIBLE, AND IT WAS NOT UNTIL THIS SENTENCE EXISTED.  The `note` column
joins the paths that share a basename, and it joined them in `set`-iteration order, so the table's
sha256 changed between runs of the SAME TREE: MEASURED `1f83544…` at `PYTHONHASHSEED=1` and
`97a6135…` at `PYTHONHASHSEED=2`, differing in 20 rows that a reader cannot tell apart.  **A census
whose table cannot be reproduced is a census nobody can diff**, which is the one property
`checks/differ.py repro` exists to protect and this file would have failed it.  Both indexes now
build over `sorted(disk)`.  Re-verify with two seeds before believing any number here.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import re
import subprocess
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# THE POPULATION OF FILES IS A WALK.  ROOTS are the top-level directories that can hold a shipped
# `.bend`; the `.bend` suffix is the only filter.  `references/` is excluded and says so in the
# summary: it is `.gitignore`d third-party source, not this project's claim about itself.
ROOTS = ("tinybendygrad", "gates", "checks", "oracles", "examples", "langs", "runs", "spec",
         "tools", "extra", "probe", "test", "docs", "bin", ".agents")
SKIP_DIRS = frozenset({".git", "__pycache__", "references", ".venv", "node_modules", ".jj"})
# File KINDS that can execute a path, and KINDS that cannot.  A kind filter is a claim about what a
# file CAN DO; it is not a list of file NAMES, so nothing here can go stale as the tree changes.
EXEC_KINDS = frozenset({"py", "sh", "mjs", "js", "cjs", "ts", "tsx", "bend", "json", "toml", "cfg", "mk"})
PROSE_KINDS = frozenset({"md", "rows", "tsv", "txt", "out", "err", "csv"})

# ONE PERMISSIVE TOKEN PATTERN.  No suffix alternation, so nothing can be truncated at a remembered
# extension.  A candidate is any word-delimited run that holds a `/` and a `.` after its last `/`.
CANDIDATE = re.compile(r"[^\s`'\"|;,(){}<>\[\]]*?/[^\s`'\"|;,(){}<>\[\]]*")
TRAILING_DOT_EXT = re.compile(r"/[^/]*\.[A-Za-z0-9_.+-]+\Z")
# `foo.py:12` and `foo.py#L4` cite a LINE of a file; the LINE part is not part of the name.
LINE_CITE = re.compile(r":\d+(?:[:-]\d+)?\Z|#L\d+\Z")

# COMMAND POSITION, for the RECIPE LABEL ONLY.
COMMAND_WORDS = frozenset({
    "sh", "bash", "zsh", "python", "python3", "node", "cc", "clang", "gcc", "git", "diff", "diff3",
    "make", "xcrun", "cargo", "uv", "ruff", "bend", "tee", "sort", "awk", "sed", "grep", "rm", "ls",
    "cat", "cp", "mv", "mkdir", "wc", "head", "tail", "jq", "env", "time", "open",
})
# `...` is an ellipsis and `//` is a doubled separator: a FAMILY, not a file.  `tinybendygrad/
# runtime/ops_cl.bend:7` writes `.../a.bend` and `ops_qcom.bend:69` writes `.../kgsl.py`.  Counting
# those as dangling rows would be this file's own version of a false citation, and the first run
# wrote 4 of them before the class existed.
FAMILY = re.compile(r"\.\.\.|//|[*?]")

# A PATH TOKEN MUST BE DELIMITED ON BOTH SIDES.  `tinybendygrad/mixin/elementwise.bend:43` writes
# `(1/math.log(2))` and the first run read the expression as a path named `1/math.log` -- 11 false
# dangling rows across three files, all of them arithmetic.  A token glued to `(` on the right is a
# CALL; one glued to `.` on the right is a member access; one glued to a word character is part of a
# longer name.  The left side is already delimited by the CANDIDATE pattern's character class.
GLUED_RIGHT = re.compile(r"[(\[.]|\w")

# A CITATION THAT SAYS A PATH DOES NOT HAPPEN.  `tinybendygrad/runtime/ops_rdma.bend:173` writes
# "the trace IS the record of the call. `import "./x.c"`" and `ops_dsp.bend:132` writes "No `import
# "./x.c"`" -- the SAME token, and one of the two is a claim that the path is absent BY DESIGN.  The
# census counts both and says which, because a `./x.c` row that means "and there is none of these"
# is not a dangling reference and must not be reported as one.
NEGATION = re.compile(r"\b(no|not|never|without|zero|absent|blocked)\b[^`]{0,40}$", re.IGNORECASE)

# THREE MORE SHAPES THAT ARE NOT PATHS, ALL FOUND BY THE FIRST PASS AND ALL WRITTEN AS DANGLING ROWS.
#   1. MEMBER ACCESS.  `tinybendygrad/engine/realize.bend:1538` writes "uop/ops.ParamArg with 13
#      fields" -- a record name, not a file.  A final segment whose dot is followed by an UPPERCASE
#      letter is an attribute, and Python module files do not carry capitals mid-name.
MEMBER = re.compile(r"\.[A-Z]")
#   2. PAIR SHORTHAND.  `tinybendygrad/mixin/creation.bend:917` writes "the wgsl.bend/device.bend
#      lesson" -- TWO files, neither of which is named.  A token whose FIRST segment already ends in
#      a file extension is the author naming two things with one slash.
#
#      **AND THE FIRST VERSION OF THIS RULE WAS `\A[^/]*\.[A-Za-z0-9]+/`, WHICH DELETED 666 REAL
#      ROWS.**  `[^/]*` matches the EMPTY string, so it matched `.agents/slop/dk-mutate.py` -- the
#      leading dot of a DOTFILE reads as an extension -- and every `.agents/` citation in the tree
#      vanished from the census.  MEASURED: NEITHER went 886 -> 220 and 23 of the rows it removed
#      were the dangling `.agents/slop/` instruments this census exists to find.  The leading `[^/.]`
#      is the fix; it says a segment must have a first character before its dot.  **A REJECTION RULE
#      THAT IS WRONG DOES NOT ADD A FALSE ROW, IT DELETES A TRUE ONE, AND THE SECOND FAILURE IS THE
#      DANGEROUS ONE** -- so `REJECTED` below TALLIES every rule that drops a token, and the tally
#      prints.  An exclusion that cannot report its own size is an exclusion that can go blind.
PAIR_SHORTHAND = re.compile(r"\A[^/.][^/]*\.[A-Za-z0-9]+/")
#   3. A GIT REVISION.  `tinybendygrad/uop/ops.bend:1056` writes `6c3d401cf324:tinygrad/uop/ops.py` --
#      `git show REV:PATH`, where the path is real and the revision is the part that may not be.
#      MEASURED elsewhere in this tree: `.agents/TOOLS.md`'s own census read `xd1/pin` as an
#      INSTRUMENT when it is a REVISION REFERENCE (`git cat-file -t` answers `commit`).  The same
#      mistake twice, so the revision is peeled off and reported in its own column.
REVISION = re.compile(r"\A[0-9a-f]{7,40}[:/]")

# A path OUTSIDE the tree is not a claim about the tree.  `/tmp/py.txt` is a recipe's scratch target
# (19 rows of it); `/usr/lib/libobjc.dylib` is a system dylib (6).  Neither is missing; both are
# absent BECAUSE they are supposed to be.  Labelled, not dropped, so the count is auditable.
OUTSIDE_PREFIX = ("/tmp/", "/var/", "/usr/", "/dev/", "/opt/", "/private/", "/System/", "/bin/",
                  "/sbin/", "/Library/", "/etc/", "/proc/")

# THE PORT MIRRORS UPSTREAM'S LAYOUT, AND ITS PROSE CITES UPSTREAM BY THE PORT'S OWN RELATIVE NAME.
# `tinybendygrad/mixin/elementwise.bend` writing `mixin/elementwise.py` means
# `tinygrad/mixin/elementwise.py`, which is vendored here.  Without this class the first run wrote 27
# false dangling rows for ONE file and the top of the table was a mirror artifact, not a defect.
MIRROR_ROOTS = ("tinygrad",)

# A TRAILING SENTENCE DOT IS NOT PART OF A FILENAME.  `.agents/slop/w64/cands/cand0.bend:1` writes
# `generated by checks/gen.sh. Do not hand-edit` and the first run read the path as `checks/gen.sh.`,
# a name that never existed -- 7 false dangling rows for a file that is right there.  This strips a
# trailing `.` or `,` ONLY WHEN WHAT REMAINS STILL ENDS IN ALPHANUMERIC, so `gen.sh.` becomes
# `gen.sh` while `gen.pyc` is never cut down to `gen.py`.  That asymmetry is the whole difference
# between de-punctuating and the remembered-extension bug.
TRAILING_PUNCT = re.compile(r"[.,:;]+\Z")


def detokenize(token: str) -> str:
    # `.search`, NOT `.match`: `match` anchors at position 0, so `[.,:;]+\Z` could only ever fire on
    # a token that was nothing but punctuation.  MEASURED: with `.match` this returned
    # `checks/gen.sh.` unchanged and the 7 rows it was written to remove survived.  A repair that
    # does not repair, silently, is the failure mode this census exists to find.
    stripped = token
    while len(stripped) > 1 and TRAILING_PUNCT.search(stripped) and stripped[-2].isalnum():
        stripped = stripped[:-1]
    return stripped


def suffix_index(disk: set[str]) -> dict[str, list[str]]:
    """Every path in the tree, indexed by each of its path SUFFIXES, so `autogen/libusb.py` can be
    answered without knowing whether the author meant `tinybendygrad/runtime/autogen/` or
    `tinygrad/runtime/autogen/`.  MEASURED: `tinybendygrad/runtime/support/usb.bend` writes
    `autogen/libusb.py` in 23 places and only `tinygrad/runtime/autogen/libusb.py` exists, so the
    port's own mirror does NOT exist and the author meant UPSTREAM.  A resolver that tries one root
    writes 46 false dangling rows; the suffix index answers the question the citation actually asks,
    and a token with MORE THAN ONE match is reported as ambiguous rather than as resolved."""
    idx: dict[str, list[str]] = {}
    for p in sorted(disk):
        parts = p.split("/")
        for i in range(1, len(parts)):
            idx.setdefault("/".join(parts[i:]), []).append(p)
    return idx

# A filename token with NO directory part: `rd-truth.py`, `oracle_py.py`.  This is the shape
# `rand.bend`'s own driver reference reduces to once the variable is stripped, so it is measured.
BARE_FILENAME = re.compile(r"[A-Za-z0-9_.+-]*\.[A-Za-z0-9_.+-]+")
EXECUTABLE_SUFFIX = re.compile(r"\.(?:sh|py|mjs|js|ts|bend|rows|tsv|json|out|err|md|pyc|bak)\Z")

# A `$VAR/...` token, and the same-file assignment that would resolve it.
ENV_TOKEN = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?(/[^\s`'\"|;,(){}]*)?")
ENV_ASSIGN = re.compile(r"^\s*(?:export\s+|declare\s+-\w+\s+|set\s+|ENV\[)?" + r"([A-Za-z_][A-Za-z0-9_]*)=")


def walk_bend_files(roots=ROOTS) -> list[str]:
    """(b) A DIRECTORY WALK.  Not a glob: `glob('*.bend')` returns [] when the suffix is on `.gitignore`."""
    out: list[str] = []
    for root in roots:
        base = os.path.join(ROOT, root)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
            for name in sorted(filenames):
                if name.endswith(".bend"):
                    full = os.path.join(dirpath, name)
                    out.append(os.path.relpath(full, ROOT))
    return sorted(out)


def head_paths() -> set[str]:
    """HEAD, NOT THE INDEX.  The colocated `jj` index holds `e69de29b` intent-to-add placeholders for
    untracked files, so `git ls-files` answers about the INDEX and moves with `GIT_INDEX_FILE`.
    `git ls-tree -r HEAD` is the immutable question."""
    r = subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD"],
                       cwd=ROOT, capture_output=True, text=True, check=False)
    if r.returncode != 0:
        return set()
    return {line for line in r.stdout.splitlines() if line}


def all_disk_paths() -> set[str]:
    """EVERY file in the tree, git-tracked or not, so 'is this basename anywhere' has an answer that
    is not the index's."""
    out: set[str] = set()
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        rel = os.path.relpath(dirpath, ROOT)
        prefix = "" if rel == "." else rel + "/"
        out.update(prefix + f for f in filenames)
    return out


def strip_comment(line: str) -> tuple[str, bool]:
    """(stripped, is_comment).  Bend comments are `#`, and a recipe lives inside one."""
    s = line.lstrip()
    return (s[1:], True) if s.startswith("#") else (s, False)


def resolve(token: str, containing: str) -> tuple[str, str]:
    """(state, resolved_relpath).  State is one of ON-DISK / MIRROR / OUTSIDE / NEITHER / PATTERN.

    Tried, in order, and the FIRST hit wins: as given, relative to the CONTAINING FILE'S DIRECTORY,
    ROOT-relative, and absolute.  Nothing is rewritten or shortened.

    **THE FILE-DIRECTORY TRY IS NOT OPTIONAL, AND OMITTING IT WROTE 338 FALSE DANGLING ROWS ON THE
    FIRST RUN.**  `tinybendygrad/runtime/autogen/libclang.bend` carries 340 `import
    "../../../.agents/slop/clangshim/libclang-tramp.c"` lines; both imported `.c` files are on disk
    and in HEAD, and a ROOT-relative-only resolve read every one of them as dangling.  A resolver
    that does not know where the document sits writes false rows in the same direction as the
    remembered-extension bug did, and with the same consequence: a reader sees 338 dangling imports
    and concludes the substrate is broken."""
    if token.endswith("/") or not TRAILING_DOT_EXT.search(token) or FAMILY.search(token):
        return "PATTERN", token
    here = os.path.join(ROOT, os.path.dirname(containing))
    # EVERY ANCESTOR of the containing directory, nearest first, then ROOT.  `tinybendygrad/nn/
    # __init__.bend` writing `mixin/op.bend` means `tinybendygrad/mixin/op.bend`, which is neither
    # the file's own directory nor the repository root: the port's source set is its own root.  A
    # two-base resolve read 41 rows of `mixin/op.bend` as dangling; the ancestor walk is what makes
    # the citation shape honest without naming `tinybendygrad/` as a special root.
    tries = [token, os.path.join(ROOT, token), os.path.normpath(os.path.join(ROOT, token))]
    d = here
    while True:
        tries.append(os.path.join(d, token))
        if os.path.normpath(d) == ROOT:
            break
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    for cand in tries:
        if os.path.exists(cand):
            full = cand if os.path.isabs(cand) else os.path.normpath(os.path.join(ROOT, cand))
            return "ON-DISK", os.path.relpath(full, ROOT)
    for mirror in MIRROR_ROOTS:
        cand = os.path.join(ROOT, mirror, token.lstrip("./"))
        if os.path.exists(cand):
            return "MIRROR", os.path.relpath(cand, ROOT)
    if token.startswith(OUTSIDE_PREFIX) or os.path.isabs(token):
        return "OUTSIDE", token
    return "NEITHER", token


def basename_index(disk: set[str]) -> dict[str, list[str]]:
    idx: dict[str, list[str]] = {}
    for p in sorted(disk):
        idx.setdefault(os.path.basename(p), []).append(p)
    return idx


def declared_names() -> dict[str, str]:
    """A GENERATOR'S OWN DECLARATION, LOADED BY PATH -- doctrine 1 rule (a).

    A `code` line is a reader ONLY when the name appears as a literal.  `checks/differ.py`'s
    `declared()` DERIVES its artifact names out of `corpus()`/`CONTROLS`/`PLANTS`, so NO filename
    token appears in any code line and a literal-scan reader calls `D1-graph-mselect.txt` unread --
    MEASURED FALSE: it is in `differ.declared()`, it is on disk, it is not in HEAD, and
    `tinybendygrad/uop/ops.bend:1179` and `:4682` both cite it.  A reader that can only see literals
    cannot see a generator, and a generator is the definition of a reader here.

    So every module in the tree that defines `declared()` is IMPORTED and ASKED, and a name it
    returns is labelled `declared`.  The module list is DISCOVERED by a walk over `checks/` and
    `gates/` for `def declared`, not typed in."""
    out: dict[str, str] = {}
    mods: list[str] = []
    for root in ("checks", "gates"):
        base = os.path.join(ROOT, root)
        for name in sorted(os.listdir(base)):
            if not name.endswith(".py"):
                continue
            path = os.path.join(base, name)
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    # A TOP-LEVEL `def declared(`, not the string anywhere: six modules in this tree
                    # MENTION `def declared` in a docstring and define nothing, and matching the
                    # string imported four of them for no names.
                    if not re.search(r"^def declared\(", fh.read(), re.MULTILINE):
                        continue
            except OSError:
                continue
            mods.append(f"{root}/{name}")
    for mod in mods:
        try:
            spec = importlib.util.spec_from_file_location(f"_decl_{mod.replace('/', '_')[:-3]}",
                                                          os.path.join(ROOT, mod))
            module = importlib.util.module_from_spec(spec)
            sys.path.insert(0, os.path.join(ROOT, "checks"))
            spec.loader.exec_module(module)
            for n in module.declared():
                out[n] = mod
        except Exception as exc:  # a module that will not import is itself a fact
            out[f"IMPORT-FAILED:{mod}"] = f"{type(exc).__name__}: {exc}"
    print(f"DECLARED SOURCES   : {len(mods)} modules define declared() -> "
          f"{len([k for k in out if not k.startswith('IMPORT-FAILED')])} names")
    for k in sorted(out):
        if k.startswith("IMPORT-FAILED:"):
            print(f"                      {k} = {out[k]}")
    return out


def head_history_paths() -> set[str]:
    """EVERY PATH EVER IN **OUR** HISTORY: `git log HEAD`, not `git log --all`.

    **AND `git log --all` IS THE WRONG QUESTION HERE, MEASURED BOTH WAYS.**  `2807aba5e` is an
    ancestor of HEAD and `git log --all --format='%h %s' --name-status -- 'tinybendygrad/codegen/
    late.bend'` reports `D tinybendygrad/codegen/late.bend` for it -- but the BULK sweep
    `git log --all --diff-filter=D --name-only --pretty=format:` does NOT list that path, and I
    spent a pass believing it.  The bulk sweep is 23 555 paths and silently incomplete; the per-path
    query is the one that answers.  So the census asks the per-path-equivalent question ONCE, over
    `HEAD` only, and every NEITHER row is then split into WAS-OURS vs NEVER-WAS.

    A SECOND measurement makes `--all` wrong in the other direction too: `.agents/slop/backward/
    bwd-mutate.sh` is `A` in three commits and `5444ea42e` is **NOT** an ancestor of HEAD, so it
    lives on a ref this branch never merged.  "In some commit under some ref" and "in our history"
    are different questions, and only the second one is recoverable by `git show HEAD:path`."""
    r = subprocess.run(["git", "log", "HEAD", "--pretty=format:", "--name-only"],
                       cwd=ROOT, capture_output=True, text=True, check=False)
    return {line for line in r.stdout.splitlines() if line}


PRODUCT = re.compile(r"(?:-o|>|--out(?:put)?[= ])\s*(\S+)")

# A RECIPE THAT MAKES ITS OWN TARGET IS NOT A DANGLING REFERENCE.  `tinybendygrad/runtime/autogen/
# libclang.bend:5-6` reads
#     ./bin/bend .agents/slop/ag-emit.bend -o .agents/slop/ag-emit.bin
#     .agents/slop/ag-emit.bin > <this file>
# so `ag-emit.bin` is ABSENT BY DESIGN on the first run and WRONG once present.  The census cannot
# see that from the row alone, so it collects every path this file PRODUCES and labels the row
# `RECIPE-PRODUCT` instead of calling it gone.  MEASURED: without this class the census reports a
# build artifact as one of its two hard misses.


def products_of(text: str) -> set[str]:
    return {m.group(1).strip("'\"`") for m in PRODUCT.finditer(text)}


def reader_index() -> dict[str, str]:
    """One pass over EVERY text file in the tree: for each filename named anywhere, is it named on a
    NON-COMMENT line, i.e. is something a PROGRAM READS rather than merely CITES?

    Two file kinds, and the distinction is a claim about the KIND, not a list of names:
      `EXEC_KINDS` can execute a path (`.py .sh .mjs .js .ts .tsx .bend .json .toml .cfg .mk`).
      `PROSE_KINDS` cannot (`*.md .rows .tsv .txt .out .err .csv`), so every line in one is prose.
    A CODE line is a reader.  A COMMENT LINE, and any line of a prose kind, is a citation.  The index
    is built over the whole tree, not over the `.bend` files alone, because a gate in `gates/`
    reading an oracle in `oracles/` is exactly the reader the census is looking for."""
    index: dict[str, str] = {}
    scanned = 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            kind = name[name.rfind(".") + 1:] if "." in name else ""
            if kind not in EXEC_KINDS and kind not in PROSE_KINDS:
                continue
            full = os.path.join(dirpath, name)
            try:
                if os.path.getsize(full) > 4_000_000:
                    continue
                with open(full, encoding="utf-8", errors="replace") as fh:
                    text = fh.read()
            except OSError:
                continue
            scanned += 1
            force_prose = kind in PROSE_KINDS
            for line in text.splitlines():
                stripped, is_comment = strip_comment(line)
                for cand in BARE_FILENAME.finditer(stripped):
                    hit = cand.group(0)
                    if force_prose or is_comment:
                        index.setdefault(hit, "prose")
                    else:
                        index[hit] = "code"
    print(f"READER SCAN         : {scanned} text files, {len(index)} distinct filenames")
    for name, mod in declared_names().items():
        if not name.startswith("IMPORT-FAILED:"):
            index[name] = f"declared-by:{mod}"
    return index


def load_texts(files: list[str]) -> dict[str, str]:
    out = {}
    for rel in files:
        try:
            with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as fh:
                out[rel] = fh.read()
        except OSError:
            out[rel] = ""
    return out


def recipe_label(stripped: str, token: str) -> bool:
    """Generous COMMAND-POSITION test.  A label, not a filter: it never hides a row."""
    first = stripped.split()[0] if stripped.split() else ""
    if first == token or first.endswith(token):
        return True
    if token.startswith("$"):
        return True
    if EXECUTABLE_SUFFIX.search(token) and any(
        w in stripped.split()[:2] for w in COMMAND_WORDS):
        return True
    return False


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=os.path.join(ROOT, "checks", "unrunnable-recipes.rows"))
    args = ap.parse_args()

    bend = walk_bend_files()
    head = head_paths()
    disk = all_disk_paths()
    by_base = basename_index(disk)
    suf = suffix_index(disk)
    texts = load_texts(bend)
    readers_idx = reader_index()
    hist = head_history_paths()
    print(f"HEAD-REACHABLE PATHS: {len(hist)} (every path `git log HEAD` ever touched)")

    rows: list[tuple] = []
    revisions: set[str] = set()
    rejected: Counter = Counter()
    for rel in bend:
        stratum = rel.split("/")[0]
        for lineno, line in enumerate(texts[rel].splitlines(), 1):
            stripped, is_comment = strip_comment(line)
            # ENV FIRST: a `$VAR/x.py` token must not ALSO be reported as a dangling `$VAR/x.py`.
            envs = list(ENV_TOKEN.finditer(stripped))
            for m in envs:
                if not m.group(2):
                    continue
                var, tail = m.group(1), m.group(2)
                assigned = any(ENV_ASSIGN.match(ln) and
                               ENV_ASSIGN.match(ln).group(1) == var
                               for ln in texts[rel].splitlines())
                base = os.path.basename(tail)
                rows.append((
                    stratum, rel, lineno, f"${var}{tail}",
                    "UNRESOLVED-ENV" if not assigned else "ENV-RESOLVED",
                    "yes" if is_comment else "no",
                    "yes" if recipe_label(stripped, f"${var}{tail}") else "no",
                    "-",
                    ";".join(by_base.get(base, []))[:200] or "BASENAME-ABSENT",
                    "no", "-",
                ))
            # NOW the bare path tokens, with the env-rooted SPANS REMOVED so `$VAR/x.py` is not also
            # read as a path named `$VAR/x.py`.  This span subtraction is one of the places a
            # silently-wrong row came from; the census prints the env row instead.
            masked = stripped
            for m in envs:
                if m.group(2):
                    s, e = m.span()
                    masked = masked[:s] + " " * (e - s) + masked[e:]
            for cand in CANDIDATE.finditer(masked):
                token = cand.group(0)
                if not TRAILING_DOT_EXT.search(token):
                    rejected["no-dotted-tail"] += 1
                    continue
                end = cand.end()
                negated = "yes" if NEGATION.search(masked[:cand.start()]) else "no"
                revision = "-"
                if PAIR_SHORTHAND.match(token):
                    rejected["pair-shorthand"] += 1
                    continue
                if MEMBER.search(token.split("/")[-1]):
                    rejected["member-access"] += 1
                    continue
                if end < len(masked) and GLUED_RIGHT.match(masked[end]):
                    rejected["glued-right"] += 1
                    continue
                if REVISION.match(token):
                    revision, _, token = token.partition(":")
                    rejected["git-revision"] += 1
                if REVISION.match(token):
                    revision, _, token = token.partition(":")
                name = detokenize(LINE_CITE.sub("", token))
                if revision != "-" and revision not in revisions:
                    revisions.add(revision)
                state, resolved = resolve(name, rel)
                if state == "PATTERN":
                    rejected["family-or-glob"] += 1
                    continue
                if state == "NEITHER":
                    hits = suf.get(name, [])
                    if len(hits) == 1:
                        state, resolved = "SUFFIX", hits[0]
                    elif len(hits) > 1:
                        state, resolved = "AMBIGUOUS", ";".join(hits[:6]) + f" (+{len(hits) - 6})"
                in_head = name in head or resolved in head
                if state == "ON-DISK":
                    verdict = "ON-DISK/TRACKED" if in_head else "ON-DISK/UNTRACKED"
                    reads = readers_idx.get(os.path.basename(resolved), "none")
                    note = resolved
                elif state == "SUFFIX":
                    verdict = "SUFFIX/TRACKED" if in_head else "SUFFIX/UNTRACKED"
                    reads = readers_idx.get(os.path.basename(resolved), "none")
                    note = "resolves as a path SUFFIX: " + resolved
                elif state == "AMBIGUOUS":
                    verdict, reads = "AMBIGUOUS-SUFFIX", "-"
                    note = f"{name} matches {resolved} -- root unknown, so NOT counted as resolved"
                elif state == "MIRROR":
                    verdict = "MIRROR/UPSTREAM" if resolved in head else "MIRROR/UNTRACKED"
                    reads = readers_idx.get(os.path.basename(resolved), "none")
                    note = resolved
                elif state == "OUTSIDE":
                    verdict = "OUTSIDE-TREE"
                    reads = "-"
                    note = "out of tree by construction"
                elif in_head:
                    verdict, reads, note = "IN-HEAD-ONLY", "-", "recoverable: git show HEAD:" + resolved
                elif state == "NEITHER" and name in products_of(texts[rel]):
                    verdict, reads = "RECIPE-PRODUCT", "-"
                    note = "this recipe's own -o/> target: absent on the first run by design"
                elif state == "NEITHER" and (name in hist or resolved in hist):
                    verdict, reads = "WAS-OURS", "-"
                    note = "deleted from our history; `git log HEAD -- <path>` finds the commit"
                elif state == "NEITHER":
                    verdict, reads = "NEITHER", "-"
                    note = ";".join(by_base.get(os.path.basename(name), []))[:200] or "BASENAME-ABSENT"
                rows.append((stratum, rel, lineno, name, verdict,
                             "yes" if is_comment else "no",
                             "yes" if recipe_label(stripped, token) else "no",
                             reads, note, negated, revision))

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("stratum\tfile\tline\ttoken\tstate\tin-comment\trecipe\treads\tnote\tnegated\trevision\n")
        for row in sorted(set(rows)):
            fh.write("\t".join(str(c) for c in row) + "\n")

    uniq = sorted(set(rows))
    # EVERY REVISION A RECIPE PINS, ANSWERED OF GIT, NOT OF THE INDEX.
    rev_state = {}
    for rev in sorted(revisions):
        r = subprocess.run(["git", "cat-file", "-t", rev], cwd=ROOT,
                           capture_output=True, text=True, check=False)
        rev_state[rev] = r.stdout.strip() if r.returncode == 0 else "NOT-A-REV"
    states: dict[str, int] = {}
    for r in uniq:
        states[r[4]] = states.get(r[4], 0) + 1
    strata: dict[str, int] = {}
    for r in uniq:
        strata[r[0]] = strata.get(r[0], 0) + 1
    broken = {"NEITHER", "UNRESOLVED-ENV", "IN-HEAD-ONLY", "WAS-OURS", "RECIPE-PRODUCT"}
    unres = [r for r in uniq if r[4] in broken]
    unres_recipe = [r for r in unres if r[6] == "yes"]
    with_recipe = {r[1] for r in uniq if r[6] == "yes"}
    print(f"BEND FILES (walk)   : {len(bend)}  " + " ".join(
        f"{k}={v}" for k, v in sorted(Counter(r.split('/')[0] for r in bend).items())))
    print(f"FILES WITH A RECIPE : {len(with_recipe)}")
    print(f"ROWS                : {len(uniq)}")
    print("BY STATE            : " + "  ".join(f"{k}={states[k]}" for k in sorted(states)))
    print("BY STRATUM          : " + "  ".join(f"{k}={v}" for k, v in sorted(strata.items())))
    print("REJECTED (each rule's OWN size -- an exclusion that cannot report its size can go blind):")
    for k, v in sorted(rejected.items()):
        print(f"                      {k}={v}")
    print("REVISION PINS        : " + (", ".join(f"{k}={v}" for k, v in sorted(rev_state.items())) or "none"))
    print(f"UNRESOLVED ROWS     : {len(unres)}")
    print(f"UNRESOLVED+RECIPE   : {len(unres_recipe)} in {len({r[1] for r in unres_recipe})} files")
    print(f"TABLE               : {os.path.relpath(args.out, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())