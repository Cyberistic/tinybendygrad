#!/usr/bin/env python3
"""oracle-census-gate -- for every COMMITTED ORACLE, THREE SEPARATE ANSWERS: who NAMES it,
who READS it, and whether "is it current" is even a question that can be asked.

    .venv/bin/python gates/oracle-census-gate.py            # the census AND the check
    .venv/bin/python gates/oracle-census-gate.py --report   # census only, rc never charged
    .venv/bin/python gates/oracle-census-gate.py --plant    # the self-test, synthetic input

WHY THREE QUESTIONS AND NOT ONE. The task that produced this file asked "which committed oracle
files does no generator name", which is ONE question with a presupposition in it -- that being
named is the same as being wanted. It is not, and the three answers disagree with each other
measurably:

    oracles/schedule-bodies/BEFORE-rows.rows   NAMED AND READ BY A LIVE INSTRUMENT
                                                (`checks/sb-gate.sh:55`), AND THE INSTRUMENT
                                                REFUSES: run it, rc=3, "the CPython oracle is
                                                absent". Named, read, and running nothing.
    oracles/usb-oracle-BEFORE.rows             NAMED BY A HAND-TYPED LITERAL (`checks/dup-gate.py`'s
                                                `PLANTS`), READ by nothing -- the name is a PLANT
                                                ARGUMENT, so the "read" is a gate testing itself.
    oracles/Baseline... (the 115 byte-identical twins)
                                                NAMED BY NOTHING IN CODE, and their content is
                                                byte-for-byte recoverable from a sibling, so the
                                                file carries no information a sibling does not.

So the population is declared per file as a CLASS, and the class is computed from three
INDEPENDENT measurements that are printed in three separate columns. Collapsing them into one
column is how a snapshot gets reported as an oracle.

THE POPULATION IS A DIRECTORY WALK, AT EVERY DEPTH (`AGENTS.md`, doctrine 1b). `oracles/` is the
one directory whose OWN NAME declares its role -- `checks/sweep.py:ROLE_DIRS = {"oracles":
"ORACLE", ...}`, which is a declaration rather than a shape -- so the population is every tracked
path under it, not `*.rows`, not `*oracle*`, and not a hand list. It is read from
`git ls-tree -r HEAD`, NOT `git ls-files`: `jj git colocation` arms git's index with `e69de29b`
placeholders (`AGENTS.md`, measured: 882 of them), so the index answers a question about the
editor. MEASURED 2026-10-16: **357** paths, which is `checks/runs-artifacts.py:307`'s own table
(`oracles/ 357`) -- two instruments, one number, read two different ways.

WHAT "NAMED" MEANS HERE, AND THE THREE THINGS THAT ARE NOT IT. A name in prose is a citation;
`checks/runs-artifacts.py`'s docstring already established that a docstring is not a use, and
`.agents/slop/nameless/census.py` exists because the tree could not tell the difference. So:

    GENERATOR-DECLARED  the path is in a generator's OWN `declared()`, LOADED BY PATH.
    WRITE-SITE          some instrument's CODE contains a write construct naming the path.
    HAND-LITERAL        named in code, inside a table somebody typed.
    SWEPT-TREE-ONLY     named in code, but ONLY by instruments under `.agents/slop/`.
    NONE                no code names it.

`.agents/slop/` IS ITS OWN CLASS AND NOT A SUBSET OF `NONE`, because `AGENTS.md` records that
85 of the paths `.agents/TOOLS.md` named are gone and 85 of those were under `.agents/slop/`: a
naming that lives in a swept tree is a naming with a shelf life, and reporting it as absent would
be a wrong reason for the right answer.

WHAT THIS GATE CHARGES, AND WHY IT IS NOT "EVERY ORACLE IS NAMED".
A gate that exits 0 having measured nothing is worse than no gate, because it is trusted; and a
gate that exits 1 over a finding it cannot fix teaches nobody to run it, which is the same
failure in the other direction. So this charges ONLY ITS OWN COVERAGE:

    PASS      every member of the population carries exactly one class, and the class counts
              sum to the population. 0 disagreements over 0 comparisons is not agreement
              (`.agents/slop/rebase-gate-selftest.py:1168-1180`, the six states), so the
              denominator is asserted, not inferred.
    FAIL      a path fell in no class, or a class disagreed with its own membership.
    REFUSED   `differ.declared()` could not be LOADED. A carve-out that cannot be computed must
              never become a blanket exemption (`checks/no-txt.py:49`), and `differ.declared()`
              is the tree's one loadable oracle declaration -- if it goes, the `GENERATOR-DECLARED`
              column becomes a clean zero, which is exactly the "cannot be anything" shape.
    DEAD      the population is empty. `gatekit.py:60`: DEAD = 5, "it ran and emitted nothing".

THE SUBSTANTIVE CENSUS IS REPORTED AND NOT CHARGED, for the reason `checks/no-txt.py:208-215`
gives about its own unguarded reader: this gate's verdict -- is the census complete -- is INVARIANT
under the tree holding zero generators, because a class count of 0 is a measurement and not a
crash. Charging the finding would make the gate red for a state the tree cannot leave from here,
and a gate that cannot pass is skipped.

THE TABLE IS BYTE-REPRODUCIBLE ACROSS SEEDS, AND IT WAS NOT UNTIL EVERY INDEX BUILT OVER
`sort()`. `checks/unrunnable-recipes.py`'s own header records the same defect it fixed: a `note`
column joined in `set`-iteration order, sha256 `1f83544...` at `PYTHONHASHSEED=1` and
`97a6135...` at `2`, 20 rows a reader cannot tell apart. `--plant` re-derives the whole census
from a synthetic tree and byte-compares it, so a regression in that property FAILS rather than
being noticed by a human diffing two runs.

WHAT IT CANNOT SEE, NAMED. (1) A write site expressed as a computed name -- `"oracles/" + tag`
where `tag` is a loop variable -- is invisible to a constant walk, and `--report` prints the
UNRESOLVED string templates it found so the blind spot has a size. (2) It reads `.py`, `.sh` and
`.mjs`; a `.bend` recipe can name a path (`.agents/slop/unreadable/cites.rows` says those are
readable-but-unread) and this file does not parse Bend. (3) It cannot tell a stale oracle from a
correct one, and it says so rather than guessing: the `CURRENT` column is `UNASKABLE` for every
file with no generator, and that IS the finding, not a gap in the instrument.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import importlib.util
import os
import re
import subprocess
import sys
import warnings
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

# `ast.parse` on the OTHER instruments' sources emits their `SyntaxWarning`s onto OUR stderr, and
# `checks/no-txt.py:220` states the rule that makes this a defect rather than a taste question:
# stdout is what callers parse. Five warnings about other people's escapes were reaching a reader
# of this gate's verdict, attributed to this file.
warnings.filterwarnings("ignore", category=SyntaxWarning)

# gatekit's vocabulary: PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5.
# `SKIP` (4) is deliberately unreachable: this gate always measures or refuses, which is the
# distinction `checks/runs-artifacts.py:26-29` draws and the reason this file is not that one.

# THE ROLE-DECLARING DIRECTORY. `checks/sweep.py:766` spells `ROLE_DIRS = {"oracles": "ORACLE",
# "gates": "GATE", "checks": "GATE"}`, so `oracles` is this project's word for a role and a
# directory carrying it declares its whole subtree. THE STRING IS NAMED HERE AND ITS SINGLE
# JUSTIFICATION IS NAMED WITH IT, because a lone constant in a gate file is a list.
ORACLE_DIR = "oracles"

# WHERE A GENERATOR'S DECLARATION IS LOADED FROM. A PATH, never a copy: `checks/no-txt.py:39-43`
# and `checks/differ.py:330-337` both make this point about the same list, and a second copy of
# `differ.declared()` is the exact failure this census exists to count.
DIFFER = "checks/differ.py"

# INSTRUMENT DIRECTORIES. `checks/` and `gates/` are this project's instruments; `.agents/slop/` is
# the swept scratch tree whose contents `AGENTS.md` records as deletable while still named.
LIVE_HOMES = ("checks", "gates", "langs", "examples")
SWEPT = ".agents/slop/"

# EXTENSIONS THAT ARE SOURCE, NOT DATA. **A LIST, AND IT IS A LIST** -- so its cost is stated:
# a data file with an extension absent here is counted as code and drops out of the census. The
# alternative, "any extension", put `.pyc` and a `CHECKSUMS` file in the population.
# MEASURED the alternative's damage on this tree: 1,255 `.py` files whose names are mentioned by
# 700+ instruments would have been 1,255 "consumers" of nothing.
SOURCE_EXT = frozenset(""".py .sh .bend .mjs .md .c .h .cuh .cpp .cc .metal .toml .lock .jpg .png
                       .svg .yaml .yml .cfg .ini .so .dylib .wasm .js .ts .css .html""".split())

# A PATH TOKEN. It must END at an extension boundary, which is a fix and not a style: the
# `(?:sh|py|bend|mjs|json)` set in `checks/repro-paths.py` read `blastradius.cpython-312.pyc` as
# `blastradius...312.py` -- a DANGLING row for a name that never existed -- and read
# `gates/tn_graph_census-gate.py.bak` as `...-gate.py`, A FILE THAT EXISTS, so a broken
# reference counted as RESOLVED (`unrunnable-recipes.py`'s header, the same measurement twice).
PATH_TOKEN = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.+-]*(?:/[A-Za-z0-9_.+-]+)*\.[A-Za-z0-9]+")

# A SHELL REDIRECT. The target is a WRITE; a `2>&1` and a `|` are neither.
REDIRECT = re.compile(r"""\d?>>?\s*(?:"([^"\n]+)"|'([^'\n]+)'|([^\s;|&<>()]+))""")

# THE PYTHON CALLS THAT PRODUCE A FILE. `WRITES` is `gates/gatekit.py`'s question about lanes and
# `checks/runs-artifacts.py:92`'s about the tree; the union is here rather than imported because
# `runs-artifacts.py` is a CHECK and this is a GATE, and one importing the other would make this
# census's population a function of a file that is free to change under it.
WRITE_CALLS = frozenset("""write_text write_bytes writelines open mkdir makedirs touch rename
                          replace copy copyfile copy2 move symlink_to hardlink_to mkstemp
                          NamedTemporaryFile TemporaryDirectory""".split())


# --------------------------------------------------------------------------------------- tree


def head_paths(paths=()) -> set[str]:
    """Every tracked path, from the COMMIT.

    NOT `git ls-files`: `jj git colocation` stages an `e69de29b` placeholder for every untracked
    file, and MEASURED on this tree that changes the answer (`AGENTS.md`: 882 placeholders, 7.9 MB
    across 149 owner directories, `git diff --cached` naming 0). The index is a question about the
    editor. `git ls-tree -r HEAD` is the question about the repository.
    """
    cmd = ["git", "ls-tree", "-r", "HEAD", "--name-only"]
    if paths:
        cmd += ["--", *paths]
    out = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    return {p for p in out.stdout.split("\n") if p}


def blob(path: str) -> bytes:
    """The bytes `HEAD` holds, so an armed index cannot make a stale file look current."""
    return subprocess.run(["git", "cat-file", "blob", f"HEAD:{path}"],
                          cwd=ROOT, capture_output=True).stdout


# -------------------------------------------------------------------------------- populations


def blobs(pop: list[str]) -> dict[str, bytes]:
    """Every population member's bytes from `HEAD`, ONCE.

    THE FIRST VERSION OF THIS FILE called `blob()` from `census()` and AGAIN from `twins()` --
    714 `git cat-file` subprocesses for 357 files -- and three consecutive runs at three hash
    seeds exceeded a 120 s budget. Two measurements over one population do not need two reads,
    and a gate that takes 28 s is a gate people run once.
    """
    return {p: blob(p) for p in pop}


def population(tracked: set[str]) -> list[str]:
    """Every tracked path at or below `ORACLE_DIR`, at EVERY depth. A directory walk.

    The sort is load-bearing rather than cosmetic: `head_paths` returns a SET, and a set's
    iteration order is `PYTHONHASHSEED`-dependent, so an unsorted walk makes the table's sha256
    move between runs of the same tree (`unrunnable-recipes.py`'s own defect).
    """
    return sorted(p for p in tracked if p == ORACLE_DIR or p.startswith(ORACLE_DIR + "/"))


def code_paths(tracked: set[str]) -> list[str]:
    """The instruments whose CODE is read for names: `.py`, `.sh`, `.mjs` and nothing else.

    `.bend` is NOT here and the reason is stated rather than hidden: `checks/unrunnable-recipes.py`
    exists because a `.bend` comment can NAME a path, and this file cannot parse Bend. Naming it
    in the population would make the count look complete while the largest namer class in the
    tree went unread.
    """
    return sorted(p for p in tracked
                  if os.path.splitext(p)[1] in (".py", ".sh", ".mjs")
                  and not p.startswith(("tinygrad/", "references/", "test/")))


def is_data(path: str, tracked: set[str]) -> bool:
    """A tracked, non-source path. The two questions are separate and both are asked."""
    return path in tracked and os.path.splitext(path)[1] not in SOURCE_EXT


# ------------------------------------------------------------------------------ who NAMES it


def _docstring_nodes(tree: ast.AST) -> set[int]:
    """Every docstring constant's `id`. `runs-artifacts.py:226-237` -- a docstring is not a use."""
    out = set()
    for n in ast.walk(tree):
        body = getattr(n, "body", None)
        if isinstance(body, list) and body and isinstance(body[0], ast.Expr) \
                and isinstance(body[0].value, ast.Constant) \
                and isinstance(body[0].value.value, str):
            out.add(id(body[0].value))
    return out


def python_names(path: str, tracked: set[str]) -> dict[str, set[str]]:
    """`{data path -> {role}}` for every code-position constant in ONE `.py`.

    ROLE IS DERIVED FROM THE ENCLOSING NODE, and this is the second version -- the first walked
    only `ast.Call` arguments and therefore found **0** of the one real hit, because
    `checks/dup-gate.py:373`'s name sits in a MODULE-LEVEL `PLANTS = {...}` and is read later by
    `main(PLANTS[rc])`. A census that only looks where it expects finds nothing, and a clean
    zero is the shape it returns while doing it (`runs-artifacts.py:115-116`).

    `tracked` IS A PARAMETER, not a module global, because the first version closed over one and
    the closure was never bound -- so `is_data()` raised `NameError` on the first instrument it
    read, and the census would have reported an empty population rather than a broken loader.
    """
    try:
        tree = ast.parse((ROOT / path).read_text(errors="replace"))
    except (OSError, SyntaxError):
        return {}
    docs = _docstring_nodes(tree)
    parent = {c: n for n in ast.walk(tree) for c in ast.iter_child_nodes(n)}
    out: dict[str, set[str]] = {}
    for leaf in ast.walk(tree):
        if not (isinstance(leaf, ast.Constant) and isinstance(leaf.value, str)):
            continue
        if id(leaf) in docs or not is_data(leaf.value, tracked):
            continue
        node, role = parent.get(leaf), "bare"
        while node is not None:
            if isinstance(node, ast.Call):
                fn = node.func.attr if isinstance(node.func, ast.Attribute) \
                    else getattr(node.func, "id", "")
                role = "write" if fn in WRITE_CALLS else "arg"
                break
            if isinstance(node, ast.Assign):
                names = [t.id for t in node.targets if isinstance(t, ast.Name)]
                if any(n in names for n in ("PLANTS", "EXIT_SURFACE", "VERDICTS", "LITERALS",
                                            "PINS", "Lanes", "LINES", "ROWS", "DIVERGES")):
                    role = "table"
                node = parent.get(node)
                break
            if isinstance(node, (ast.List, ast.Tuple, ast.Set, ast.Dict)):
                role = "table"
            node = parent.get(node)
        out.setdefault(leaf.value, set()).add(role)
    return out


def shell_names(path: str, tracked: set[str]) -> dict[str, set[str]]:
    """`{path -> {role}}` for one `.sh`/`.mjs`, with comments removed FIRST.

    Comments are removed before the token scan rather than filtered after it, because `AGENTS.md`
    records the failure this shape has taken three times: 670 of 675 ORACLE files classified by
    FILENAME, 180 of 333 ledger paths that are gone, and a 12th stale citation in the file that
    defines the class. A mention inside `#` is a citation and cannot be a writer.
    """
    try:
        text = (ROOT / path).read_text(errors="replace")
    except OSError:
        return {}
    code = "\n".join(l for l in text.split("\n")
                     if not l.lstrip().startswith(("#", "//", "*")))
    out: dict[str, set[str]] = {}
    for m in REDIRECT.finditer(code):
        target = (m.group(1) or m.group(2) or m.group(3) or "").strip()
        if is_data(target, tracked):
            out.setdefault(target, set()).add("write")
    for m in PATH_TOKEN.finditer(code):
        tok = m.group(0).lstrip("./")
        if is_data(tok, tracked) and tok not in out:
            out.setdefault(tok, set()).add("arg")
    return out


def names(tracked: set[str], instruments: list[str]) -> dict[str, dict[str, set[str]]]:
    """`{path -> {role -> {instrument}}}` over the whole instrument population, ONCE."""
    out: dict[str, dict[str, set[str]]] = {}
    for rel in instruments:
        found = shell_names(rel, tracked) if os.path.splitext(rel)[1] in (".sh", ".mjs") \
            else python_names(rel, tracked)
        for target, roles in found.items():
            for role in roles:
                out.setdefault(target, {}).setdefault(role, set()).add(rel)
    return out


def declared(rel: str = DIFFER):
    """`differ.declared()`'s paths, LOADED BY PATH, or raise.

    The raise is the point. `checks/no-txt.py:49`: a loader that fails returns an empty set, so
    its files are REPORTED -- and the symmetric case here is worse, because an empty set makes
    `GENERATOR-DECLARED` a clean 0 over a population of 357, and a zero over a broken loader is
    indistinguishable from a zero over a tree that has no generators. REFUSED is the honest exit,
    and `rel` is a PARAMETER so the REFUSED arm is reachable by a plant rather than asserted.
    """
    spec = importlib.util.spec_from_file_location("differ_decl", ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    names_ = mod.declared()
    prefix = mod.D.relative_to(ROOT).as_posix()
    return {(f"{prefix}/{n}" if prefix else n) for n in names_}, len(names_)


# ---------------------------------------------------------------------------------- the table


def row_for(path: str, namer: dict[str, dict[str, set[str]]],
            declared_paths: set[str], data: bytes) -> dict[str, object]:
    """ONE population member, with the THREE ANSWERS HELD APART.

    Kept apart on purpose. A single `status` column is what produced `checks/txt-owners.py`'s
    three self-recorded faults, and what made 670 of 675 files "classified" by a basename.
    """
    roles = namer.get(path, {})
    # A ROLE BUCKET CAN BE EMPTY and the first version indexed it anyway: `next(iter(live.values()))`
    # returned the first role's set whether or not that role had any LIVE instrument in it, so a
    # path named only by `.agents/slop/` under role `arg` and by nothing live raised IndexError
    # while picking its witness. `max(..., key=len)` over the NON-EMPTY buckets, then sorted --
    # the largest bucket is the tie-break that does not depend on dict order.
    live = {r: sorted(i for i in v if not i.startswith(SWEPT)) for r, v in roles.items()}
    swept = {r: sorted(i for i in v if i.startswith(SWEPT)) for r, v in roles.items()}
    live = {r: v for r, v in live.items() if v}
    swept = {r: v for r, v in swept.items() if v}

    def witness(buckets):
        return max(sorted(buckets), key=lambda r: (len(buckets[r]), r))

    if path in declared_paths:
        named_by, why = "GENERATOR-DECLARED", f"in {DIFFER}:declared()"
    elif "write" in live:
        named_by, why = "WRITE-SITE", live["write"][0]
    elif "write" in swept:
        named_by, why = "WRITE-SITE-SWEPT", swept["write"][0]
    elif live:
        named_by, why = "HAND-LITERAL", live[witness(live)][0]
    elif swept:
        named_by, why = "SWEPT-TREE-ONLY", swept[witness(swept)][0]
    else:
        named_by, why = "NONE", ""

    read_by = "LIVE-READ" if live else ("SWEPT-READ" if swept else "NO-READ")
    # "IS IT CURRENT" IS NOT A QUESTION WITHOUT A PRODUCER. 0 of the write-site and declared
    # classes reached this tree today, so the honest cell is UNASKABLE -- and printing a staleness
    # number there would be the instrument inventing a measurement it did not take.
    current = "UNASKABLE" if named_by in ("NONE", "SWEPT-TREE-ONLY", "HAND-LITERAL",
                                          "WRITE-SITE-SWEPT") else "ASKABLE"
    return {"path": path, "bytes": len(data), "sha": hashlib.sha256(data).hexdigest(),
            "named_by": named_by, "why": why, "read_by": read_by, "current": current,
            "readers": sorted(set(live.get("arg", [])) | set(live.get("table", [])))}


def table(rows: list[dict[str, object]]) -> str:
    """The census as a `.rows` table, deterministic in two seeds because every list is sorted."""
    head = "path\tbytes\tsha12\tnamed_by\tread_by\tcurrent\treaders"
    body = [f"{r['path']}\t{r['bytes']}\t{r['sha'][:12]}\t{r['named_by']}\t{r['read_by']}\t"
            f"{r['current']}\t{','.join(r['readers'])}" for r in sorted(rows, key=lambda r: r["path"])]
    return "\n".join([head, *body]) + "\n"


# ------------------------------------------------------------------------------------ verdicts


EXIT_SURFACE = VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED", 5: "DEAD"}  # VERDICTS: legacy alias of EXIT_SURFACE
PLANTS = {0: ["--plant"], 1: ["--plant-broken"], 3: ["--plant-undeclared"], 5: ["--plant-dead"]}
# NO `RED_IS`, AND THE ABSENCE IS THE DECLARATION. `gates/gate-surface.py:361` accepts exactly
# `FINDING | UNTAKEN | FAILURE` and rejected a fourth value -- and the value this file first
# shipped, `CENSUS-INCOMPLETE`, was exactly the growth gate-surface.py:42-44 forbids ("a taxonomy
# of excusable reds would grow a second class the first time somebody wanted one"). A census that
# cannot classify its own population is a FAILURE of this file, not a finding about the tree, so
# absence is correct: `gate-surface.py:46` reads a missing `RED_IS` as "my red is about the tree",
# which is what is meant here.
#
# **EVERY DECLARED EXIT IS PLANTED, AND TWO OF THE FOUR ARE REAL ARMS OF `main()` RATHER THAN
# PLANTS BOLTED ON.** An unplanted verdict is "a claim of unknown value" to that same file, and a
# gate that declares `REFUSED` and can never refuse is the same defect as a comment that says a
# pin is checked. So `--plant-undeclared` points the declaration LOADER at a path that does not
# exist, and `--plant-dead` hands `check()` an empty population -- which is what it does when the
# walk finds nothing, so the DEAD arm is the real one and not a special case.


def census(tracked: set[str] | None = None, instruments: list[str] | None = None,
           decl: set[str] | None = None,
           data: dict[str, bytes] | None = None) -> list[dict[str, object]]:
    """The whole census. Every argument is injectable so `--plant` can drive a synthetic tree."""
    tracked = tracked if tracked is not None else head_paths()
    pop = population(tracked)
    decl = decl if decl is not None else set()
    data = data if data is not None else blobs(pop)
    namer = names(tracked, instruments if instruments is not None else code_paths(tracked))
    return [row_for(p, namer, decl, data[p]) for p in pop]


def classify(rows: list[dict[str, object]], twin: dict[str, list[str]]) -> list[tuple[str, str]]:
    """READ-BY-LIVE / FROZEN / DEAD-WEIGHT per file, and the reason is a MEASUREMENT each time.

    DEAD-WEIGHT is deliberately the NARROWEST of the three: 0 bytes, or content byte-identical to
    a sibling AND no live reader. The two conditions are separate because each alone would be a
    wrong reason -- an empty file a gate reads is a gate's fixture, and a duplicated file a gate
    reads is the fixture too.

    **THE CLASS IS `READ-BY-LIVE-INSTRUMENT` AND NOT `LIVE-ORACLE`, AND THE FIRST VERSION WAS
    WRONG IN THE DIRECTION THAT FLATTERS.** Naming it LIVE claimed the reader USES the file;
    `checks/sb-gate.sh` NAMES `oracles/schedule-bodies/BEFORE-rows.rows` at `:55` and then REFUSES
    -- run it: rc=3, "the CPython oracle is absent". A file read by a gate that measures nothing
    is read, and it is not live. So the class says what is measured (an instrument outside the
    swept tree names it in code) and `--probe-readers` measures the rest (does that instrument
    actually answer) without folding the two into one word.
    """
    live_readers = {r["path"] for r in rows if r["read_by"] == "LIVE-READ"}
    out = []
    for r in rows:
        if r["bytes"] == 0:
            kind = "DEAD-WEIGHT(0 bytes)"
        elif twin.get(r["sha"]) and len(twin[r["sha"]]) > 1 and r["path"] not in live_readers:
            kind = f"DEAD-WEIGHT(== {sorted(x for x in twin[r['sha']] if x != r['path'])[0]})"
        elif r["read_by"] == "LIVE-READ":
            kind = "READ-BY-LIVE-INSTRUMENT"
        else:
            kind = "FROZEN-SNAPSHOT"
        out.append((r["path"], kind))
    return out


def probe_readers(rows: list[dict[str, object]], budget: int = 30) -> list[tuple[str, str, str]]:
    """`(reader, exit, first REFUSED/FAILED line)` for every SHELL reader, ONCE each.

    OPT-IN (`--probe-readers`), because it EXECUTES the tree's own gates and a gate is a program
    with effects. The default run must be a read. A `.py` reader is NOT invoked even then: a
    census has no business running a Python gate it did not write, and the class `NOT-INVOKED`
    is reported instead of a guess.

    WHY THIS EXISTS AT ALL: "named in code" and "the named thing runs" are different questions,
    and on this tree they answer differently for the ONE oracle a live instrument names. A
    reader that REFUSES is `gatekit.py`'s `REFUSED` = 3 -- "a precondition was absent" -- and a
    baseline whose only reader refuses is a baseline that holds up a gate, not a gate.
    """
    readers = sorted({i for r in rows for i in r["readers"]})
    out = []
    for rel in readers:
        if os.path.splitext(rel)[1] != ".sh":
            out.append((rel, "NOT-INVOKED", "a census does not run a gate it did not write"))
            continue
        try:
            p = subprocess.run(["sh", rel], cwd=ROOT, capture_output=True, text=True,
                               timeout=budget)
        except subprocess.TimeoutExpired:
            out.append((rel, f"TIMEOUT>{budget}s", "the reader did not finish"))
            continue
        said = next((l.strip() for l in (p.stdout + p.stderr).splitlines()
                     if "REFUSED" in l or "FAIL" in l or "Traceback" in l), "")
        out.append((rel, f"rc={p.returncode}", said[:110]))
    return out


def twins(pop: list[str], data: dict[str, bytes]) -> dict[str, list[str]]:
    """sha256 -> every path holding those bytes. A hash BUILT OVER A SORTED LIST."""
    out: dict[str, list[str]] = {}
    for p in pop:
        out.setdefault(hashlib.sha256(data[p]).hexdigest(), []).append(p)
    return {k: sorted(v) for k, v in sorted(out.items())}


def check(rows: list[dict[str, object]]) -> tuple[int, str]:
    """THE COVERAGE ASSERTION, AND ONLY THAT. See the module docstring for what is not charged."""
    if not rows:
        return DEAD, "the population is empty -- the walk found nothing, or HEAD has no oracle"
    known = {"GENERATOR-DECLARED", "WRITE-SITE", "WRITE-SITE-SWEPT", "HAND-LITERAL",
             "SWEPT-TREE-ONLY", "NONE"}
    tally: dict[str, int] = {}
    unclassified = []
    for r in rows:
        tally[r["named_by"]] = tally.get(r["named_by"], 0) + 1
        if r["named_by"] not in known:
            unclassified.append(r["path"])
    total = sum(tally.values())
    if unclassified:
        return FAIL, f"{len(unclassified)} path(s) carry no class: {unclassified[:5]}"
    if total != len(rows):
        return FAIL, f"the class counts sum to {total} over a population of {len(rows)}"
    return PASS, (f"{total} paths, {len(tally)} classes, "
                  + " ".join(f"{k}={v}" for k, v in sorted(tally.items())))


def report(rows: list[dict[str, object]], twin: dict[str, list[str]]) -> None:
    """Everything below is REPORTED and not charged; see the docstring.

    **TO STDERR, UNCONDITIONALLY, AND THIS IS A FIX.** The human summary went to stdout while
    `--table` also wrote the table there, so a caller parsing the table got 373 lines for a
    population of 357 -- MEASURED, and it is the `checks/no-txt.py:215` rule ("stdout is what
    callers parse") restated for a gate. A header row, twelve indented detail rows and one
    summary line arrived interleaved with the data, and an `awk -F'\\t'` over it reported a class
    of 15 rows whose fourth field was empty -- fifteen rows that do not exist.
    """
    out = sys.stderr
    named = {}
    for r in rows:
        named[r["named_by"]] = named.get(r["named_by"], 0) + 1
    reads = {}
    for r in rows:
        reads[r["read_by"]] = reads.get(r["read_by"], 0) + 1
    cur = {}
    for r in rows:
        cur[r["current"]] = cur.get(r["current"], 0) + 1
    print(f"  population      {len(rows)} tracked paths under {ORACLE_DIR}/ "
          f"(git ls-tree -r HEAD, every depth)", file=out)
    print("  named by        " + " ".join(f"{k}={v}" for k, v in sorted(named.items())), file=out)
    print("  read by         " + " ".join(f"{k}={v}" for k, v in sorted(reads.items())), file=out)
    print("  current         " + " ".join(f"{k}={v}" for k, v in sorted(cur.items())), file=out)
    kinds = {}
    for _, k in classify(rows, twin):
        kinds[k.split("(")[0]] = kinds.get(k.split("(")[0], 0) + 1
    print("  class           " + " ".join(f"{k}={v}" for k, v in sorted(kinds.items())), file=out)
    for r in sorted(rows, key=lambda r: r["path"]):
        if r["read_by"] in ("LIVE-READ", "SWEPT-READ") or r["named_by"] == "GENERATOR-DECLARED":
            print(f"    {r['read_by']:<11} {r['named_by']:<19} {r['path']}"
                  + (f"  <- {', '.join(r['readers'])}" if r["readers"] else ""), file=out)


def _synthetic() -> list[dict[str, object]]:
    """A five-member population with one member of every `named_by` class and of every `kind`.

    BUILT HERE RATHER THAN ON DISK so the plant cannot be perturbed by another unit writing
    `oracles/`, which is the reason `checks/txt-owners.py:36` calls its own census "a
    deliverable, not a gate" -- but this file IS a gate, so it needs a tree it owns.
    """
    tree = {
        "oracles/a.rows": b"a=1\n",          # byte-identical to b -> DEAD-WEIGHT(twin)
        "oracles/b.rows": b"a=1\n",
        "oracles/empty.err": b"",            # 0 bytes -> DEAD-WEIGHT(0 bytes)
        "oracles/named.rows": b"c=1\n",      # named by a live instrument -> LIVE-ORACLE
        "oracles/swept.rows": b"d=1\n",      # named only from .agents/slop/ -> FROZEN-SNAPSHOT
        "oracles/declared.rows": b"e=1\n",   # in declared() -> GENERATOR-DECLARED
        "oracles/lonely.rows": b"f=1\n",     # named by nothing -> FROZEN-SNAPSHOT
    }
    namer = {
        "oracles/named.rows": {"arg": {"checks/dup-gate.py"}},
        "oracles/swept.rows": {"arg": {SWEPT + "x.py"}},
        "oracles/table.rows": {"table": {"checks/y.py"}},
    }
    # EVERY member, not only the named ones: dropping an unnamed path would make the `NONE` and
    # `FROZEN-SNAPSHOT` classes unreachable, and a class the plant cannot reach is a class the
    # census cannot report -- which is the first version of this, and it reported the gap as
    # `MISSING` against a population that had been quietly trimmed to three members.
    return [row_for(p, namer, {"oracles/declared.rows"}, tree[p]) for p in sorted(tree)]


def plant() -> int:
    """THE THREE PROPERTIES THIS FILE CLAIMS, DRIVEN ON A SYNTHETIC TREE. No `bend`, no oracle.

    1 SEED-INDEPENDENCE, IN TWO PROCESSES. The first version of this compared two builds inside
    ONE interpreter, which cannot fail: `set` iteration order is fixed within a process, so the
    two tables were the same object compared to itself and the check was theatre. `PYTHONHASHSEED`
    is the input that moves `str` hashing, so the only honest test spawns two children with
    different seeds and byte-compares their tables. `checks/unrunnable-recipes.py` records the
    real defect with two shas (`1f83544...` at seed 1, `97a6135...` at seed 2, 20 rows apart).
    2 CLASS COVERAGE over BOTH axes. `named_by` (six classes) and `kind` (three) are different
    questions and the first version of this plant put a `named_by` name into the `kind` set, so
    it demanded a `kind` that `classify()` cannot produce and reported MISSING for it.
    3 THE FAIL ARM: a population whose class is UNKNOWN must FAIL, because `check()` is the only
    thing standing between this file and a clean zero over 357 files.
    """
    rows = _synthetic()
    # 1 -- two processes, two seeds, one table.
    shas = []
    for seed in ("1", "2"):
        env = dict(os.environ, PYTHONHASHSEED=seed)
        out = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--table-sha"],
                             cwd=ROOT, env=env, capture_output=True, text=True)
        shas.append(out.stdout.strip().splitlines()[-1] if out.stdout.strip() else f"rc={out.returncode}")
    stable = len(set(shas)) == 1 and shas[0].startswith(hashlib.sha256(
        table(_synthetic()).encode()).hexdigest()[:16])
    print(f"  seed-independence  {'STABLE ' + shas[0] if stable else 'MOVES: ' + ' '.join(shas)}")
    # 2 -- both axes, each against its own vocabulary.
    kinds = {k.split("(")[0] for _, k in classify(rows, _twin_of(rows))}
    want_kind = {"READ-BY-LIVE-INSTRUMENT", "FROZEN-SNAPSHOT", "DEAD-WEIGHT"}
    print(f"  kind coverage      {'OK' if want_kind <= kinds else 'MISSING ' + str(sorted(want_kind - kinds))}"
          + f"  ({', '.join(sorted(kinds))})")
    classes = {r["named_by"] for r in rows}
    want_class = {"GENERATOR-DECLARED", "HAND-LITERAL", "SWEPT-TREE-ONLY", "NONE"}
    print(f"  named_by coverage  {'OK' if want_class <= classes else 'MISSING ' + str(sorted(want_class - classes))}"
          + f"  ({', '.join(sorted(classes))})")
    code, why = check(rows)
    print(f"  coverage check     rc={code} ({VERDICT[code]}) {why}")
    # 3 -- the FAIL arm, on the same rows with one class renamed.
    broken = [dict(r, named_by="MADE-UP") for r in rows]
    fcode, fwhy = check(broken)
    print(f"  unknown-class arm  rc={fcode} ({VERDICT[fcode]}) {fwhy[:60]}")
    bad = []
    if not stable:
        bad.append("the table moves with PYTHONHASHSEED")
    if not want_kind <= kinds or not want_class <= classes:
        bad.append("a class is unreachable, so the census cannot see it")
    if code != PASS:
        bad.append("a complete synthetic population did not PASS")
    if fcode != FAIL:
        bad.append("an unknown class did not FAIL")
    print(f"--plant: {'all four properties hold' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 1 if bad else 0


def _twin_of(rows: list[dict[str, object]]) -> dict[str, list[str]]:
    """`{sha: [paths]}` over a synthetic population, so `classify()` sees its twin condition."""
    out: dict[str, list[str]] = {}
    for r in rows:
        out.setdefault(r["sha"], []).append(r["path"])
    return {k: sorted(v) for k, v in sorted(out.items())}


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--report", action="store_true", help="census only, rc never charged")
    ap.add_argument("--plant", action="store_true", help="the self-test")
    ap.add_argument("--plant-broken", action="store_true", help="drive the FAIL arm")
    ap.add_argument("--plant-undeclared", action="store_true",
                    help="drive the REFUSED arm by pointing the declaration loader at a path "
                         "that does not exist")
    ap.add_argument("--plant-dead", action="store_true",
                    help="drive the DEAD arm with an empty population")
    ap.add_argument("--table", action="store_true",
                    help="the per-file table on stdout: path x [named by / read by / current]")
    ap.add_argument("--probe-readers", action="store_true",
                    help="INVOKE each shell reader once and print its exit. Executes the tree's "
                         "own gates, so it is off by default and the default run reads nothing.")
    ap.add_argument("--table-sha", action="store_true",
                    help="print the synthetic table's sha256 and nothing else; the plant's "
                         "seed-independence arm spawns this under two PYTHONHASHSEEDs")
    args = ap.parse_args(argv)

    if args.table_sha:
        print(hashlib.sha256(table(_synthetic()).encode()).hexdigest())
        return PASS

    if args.plant:
        return plant()
    # A PLANT FOR EACH NON-PASS VERDICT RETURNS THE CODE IT DEMONSTRATES. The first version returned
    # `0 if code == FAIL else 1` -- the INVERSE -- and `gates/gate-surface.py` caught it as two
    # MISPLANTs (`plant ['--plant-broken'] produced 0`, `plant ['--plant-dead'] produced 0`), which
    # is exactly what a declared-but-unreachable verdict costs: the reader is told the arm exists
    # and the arm cannot be driven. `PLANTS[rc]` is the argv that REACHES rc.
    if args.plant_broken:
        rows = [{"path": "oracles/x.rows", "bytes": 1, "sha": "0" * 64, "named_by": "MADE-UP",
                 "why": "", "read_by": "NO-READ", "current": "UNASKABLE", "readers": []}]
        code, why = check(rows)
        print(f"  unknown class      rc={code} ({VERDICT[code]}) {why}")
        return code
    if args.plant_undeclared:
        return run_census(DIFFER + ".absent-on-purpose", args)
    if args.plant_dead:
        code, why = check([])
        print(f"  empty population   rc={code} ({VERDICT[code]}) {why}")
        return code

    return run_census(DIFFER, args)


def run_census(differs: str, args) -> int:
    """The census proper, with the declaration loader's source as a parameter.

    So `--plant-undeclared` reaches the REFUSED arm through the SAME four lines a broken tree
    would reach it through, rather than through a branch that exists only for the plant. A plant
    that drives a different code path than the tree proves nothing about the tree.
    """
    try:
        decl, n_declared = declared(differs)
    except Exception as exc:
        print(f"== REFUSED, NOT A VERDICT: {differs}:declared() could not be loaded: {exc!r}",
              file=sys.stderr)
        print("   A carve-out that cannot be computed must never become a blanket exemption, and "
              "an EMPTY set would make GENERATOR-DECLARED a clean 0 over the whole population.",
              file=sys.stderr)
        return REFUSED

    tracked = head_paths()
    data = blobs(population(tracked))
    rows = census(tracked, None, decl, data)
    twin = twins(population(tracked), data)
    code, why = check(rows)
    print(f"  differ.declared()  {n_declared} names, {len(decl & {r['path'] for r in rows})} of them "
          f"under {ORACLE_DIR}/", file=sys.stderr)
    report(rows, twin)
    if args.probe_readers:
        for rel, rc, said in probe_readers(rows):
            print(f"    reader {rel:<26} {rc:<14} {said}", file=sys.stderr)
    if args.table:
        sys.stdout.write(table(rows))
    print(f"  {why}", file=sys.stderr)
    if args.report:
        print(f"  --report: rc never charged ({VERDICT[code]})", file=sys.stderr)
        return PASS
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))