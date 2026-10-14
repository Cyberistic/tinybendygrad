#!/usr/bin/env python3
"""Sort every file under .agents/slop and runs into exactly four buckets, then act on three.

    usage: .venv/bin/python checks/sweep.py --plan          # classify, print the plan, delete nothing
           .venv/bin/python checks/sweep.py --apply DOC GATE ORACLE DELETE

THE RULE, AS THE USER STATED IT:

    anything in slop which isn't real documentation, or should be moved to checks/ (gates),
    oracles, or whatever, should be deleted. This includes one-off test scripts.

So there are five buckets, and one verdict that is not a bucket:

    DOC      a .md report. It records a measurement or a decision. It stays in slop.
    GATE     it RUNS and DECIDES, and something load-bearing names it. It moves to checks/.
    ORACLE   it is reference DATA a gate compares against -- never executed, only diffed.
             It moves to oracles/.
    AUTHORED a NAMING AUTHORITY renders this name, so it is an OUTPUT CONTRACT rather than a file
             somebody made once. `checks/differ.py` DECLARES 136 of them and reads 12 by name; a
             sweep that calls them junk is measuring its own tokenizer, not the tree.
    DELETE   an OUTPUT no authority renders, no committed text names, and no one owns. ONE-OFF
             PROBES, MUTATORS, GENERATED ROW DUMPS, .err CAPTURES, SHADOW TREES OF THE SOURCE --
             and nothing else. It is a VERDICT, and it is reached only by saying so.

    UNKNOWN  a test COULD NOT BE RUN. Reported, never acted on, and tagged with `needs=`: the
             cheapest test that would resolve the row. **IT IS NOT A BUCKET, IT IS A RECORD OF
             NOT-SURE, AND IT IS THE ONLY VERDICT `--apply` CANNOT BE POINTED AT.**

DELETE WAS NOT A VERDICT UNTIL 2026-10-06. `verdict_for` ended in `return "DELETE"`, which is the
ABSENCE of a verdict: it is what a classifier emits when every escape declined to fire, and it is the
only bucket `--apply` destroys. **A CLASSIFIER WITH NO VERDICT FOR *I CANNOT TELL* DELETES THE
UNCLASSIFIABLE BY DEFAULT** -- and MEASURED on this tree, 354 of 1,421 rows were reaching that
default, with no record that any of them was doubtful. `UNKNOWN` is what a row says instead, and it
carries the test that would end the doubt, because **a group with no deciding test is a group that has
been labelled.**

WHY THE GATE SET IS DEFINED BY BEING NAMED, NOT BY BEING EXECUTABLE.  MEASURED: `.agents/slop`
holds 5,817 `.sh`/`.py` files and 515 executables, of which **367 are copies of UPSTREAM's own
scripts** (`dev`, `run`, `setup`, `serve`, `train`) inside shadow trees of the source. And the
citation test has already been got wrong three times in this project -- a bare-basename match
reported 3,574 false citations, 138 of them copies of one `__init__.bend`; a bare-substring match
reported 6 citers for a ZERO-BYTE `.err`. **A GATE IS A GATE BECAUSE SOMETHING DEPENDS ON IT, AND
THE ONLY WAY TO KNOW THAT IS TO ASK WHAT NAMES IT.**

CITATIONS ARE WHOLE PATH TOKENS. `in` IS NOT A CITATION TEST. The matcher is a word-boundary
regex over committed reports plus `AGENTS.md` and `checks/README.md`, because a bare `in` is how
four files at the repository root were once kept alive by a report mentioning `.error`.

LIVE FILES ARE NEVER TOUCHED. The window is `--live-minutes`, and it is checked at ACT time, not
only at classify time, because five units are writing into slop while this runs. **`--plan` ALSO
PRINTS THE COUNT AT WINDOW 0 BECAUSE THE WINDOW IS A CLOCK AND NOT A MEASUREMENT OF THE TREE:**
MEASURED, same tree, nothing edited, `DELETING 366 / 44 / 0` at 0, 60 and 1440 minutes.
"""
from __future__ import annotations

import argparse
import ast
import collections
import functools
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SLOP = os.path.join(ROOT, ".agents/slop")
RUNS = os.path.join(ROOT, "runs")
CHECKS = os.path.join(ROOT, "checks")
ORACLES = os.path.join(ROOT, "oracles")
# `RESIDUE_ROOTS` IS NOT DERIVED, AND IT SHOULD NOT BE. MEASURED 2026-10-12, the obvious
# derivation -- "every directory an instrument writes into that git cannot restore" -- is exactly
# what `checks/runs-artifacts.py:unrecoverable_dirs()` computes, and it answers `{runs/, runs/graphcmp/,
# bin/}`. IT DOES NOT ANSWER `.agents/slop`, WHICH IS CORRECT AND FATAL: `.agents/slop` holds **4,491**
# tracked files, so a rule keyed on "untracked" drops it, and dropping it stops the sweep cleaning
# the one tree the sweep exists for. **THE ROOTS ANSWER "WHERE IS THERE RESIDUE"; THE DERIVATION
# ANSWERS "WHERE IS A DELETION IRREVERSIBLE". THEY ARE DIFFERENT QUESTIONS AND ONLY THE SECOND ONE
# IS DERIVABLE, SO THE SECOND ONE IS THE ONE `verdict_for` ASKS, AT `GENERATED_READ_DIRS` BELOW.**
RESIDUE_ROOTS = (".agents/slop", "runs")

@functools.cache
def load_by_path(path: str):
    """Execute one of this project's instruments BY PATH, ONCE per process per path.

    **THREE CALL SITES, ONE SHARED MEASUREMENT, AND THE COST WAS PAID THREE TIMES OVER.**
    `generated_read_dirs`, `house_excluded` and `residue_copies` each hand-rolled
    `spec_from_file_location` + `exec_module`, which reads and executes the WHOLE module. MEASURED
    2026-10-14 16:47: `checks/residue.py` (750 lines) costs **0.150 ms** to execute once the
    `__pycache__` is warm, and `house_excluded` alone is called **974 times** per `--plan` -- so
    **0.146 s** of pure waste, re-executing a module to read one 21-element tuple and a one-line
    `excluded()`. Small next to a 535 s bug and free to remove, and the three copies were three
    chances to forget a key.

    **THE KEY IS THE PATH, BECAUSE THE PATH IS WHAT NAMES THE MODULE AND WHERE TO FIND IT.**
    `functools.cache` on an argument that is not the whole input is how `_GENERATED_CACHE` below
    became a global wearing a parameter's name.

    Raises on a module that will not execute; every call site already catches.
    """
    spec = importlib.util.spec_from_file_location(
        os.path.splitext(os.path.basename(path))[0], path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


_GENERATED_CACHE: dict[str, dict[str, set[str]]] = {}


def generated_read_dirs(root: str = ROOT) -> dict[str, set[str]]:
    """Directory -> the instruments that READ it, for directories git cannot restore. **LOADED BY
    PATH FROM THE ONE IMPLEMENTATION** (`checks/runs-artifacts.py`), the same shape as
    `house_excluded`'s `residue.EXCLUDED_DIRS` at :222 and for the same reason: a second copy of a
    derived set is a contract with no generator, which is how `LIVE_UNITS` held 53% of `.slop`.

    MEASURED 2026-10-12 16:04 on the live tree: `runs/graphcmp/D` has **8 readers of the 188
    instruments** in `checks/` + `gates/`, **0 of its 241 files are in git**, and `checks/sweep.py:72`
    puts `runs` in `RESIDUE_ROOTS` -- so a sweep is entitled to destroy all 241 of them and
    `git ls-tree -r HEAD` can restore none. `AGENTS.md` records the same shape for a gate's inputs
    kept under `gates/artifacts/`, which is `.gitignore`d: one `rm -rf` deletes anything kept there
    and git cannot bring it back.

    **THE CACHE IS NOW KEYED BY `root` AND WAS NOT.** MEASURED 2026-10-14 16:47: the old global was
    a single slot, so the SECOND root to ask got the FIRST root's answer -- **a memo that ignores its
    key argument is a global wearing a parameter's name, and it converts a parameterised function
    back into a module-level one** while every signature still says otherwise. That is the exact
    shape of the seven blindnesses this file has already paid for, one level down, and it is armed the
    moment any caller passes a root other than `ROOT`: `verdict_for`'s own docstring promises `f`
    exists "because `--plant` builds this over a synthetic tree", and a synthetic tree's census would
    have been the production tree's. LATENT TODAY -- MEASURED 2026-10-14 16:47, the only caller is
    `verdict_for`, and every path into it reaches `facts()` with no argument. **LATENT IS NOT SAFE;
    IT IS UNEXERCISED.**

    MEASURED 2026-10-14 16:47, cold, on a tree three other units are writing to: **16.1 s**, and it
    answers 3 directories (`bin`, `runs`, `runs/graphcmp`). Warm: 1.1 microseconds. It is asked once
    per process, so it is a budget line and not a bug -- but see `Facts.__init__`, where it is paid
    INSIDE the first `verdict_for`, which is how a one-time cost reads as a per-row cost.
    """
    if root not in _GENERATED_CACHE:
        try:
            m = load_by_path(os.path.join(root, "checks/runs-artifacts.py"))
            _GENERATED_CACHE[root] = {d: set(v["readers"])
                                      for d, v in m.census_unrecoverable(root)[1].items()
                                      if v["readers"]}
        except Exception:
            # A SWEEP THAT CANNOT ASK MUST NOT GUESS, AND MUST NOT REFUSE TO RUN: the classifier's
            # own rule is that an unanswerable question is `UNKNOWN`, and the guard below degrades
            # to the hand list rather than to "delete everything".
            _GENERATED_CACHE[root] = {RUNS: set()}
    return _GENERATED_CACHE[root]

# `UNKNOWN` IS TAGGED, AND THE TAG IS THE POINT. `needs=` travels with the verdict instead of
# travelling with a sentence in a report nobody reads, and the tag is why no `--apply` argument can
# reach one of these rows: nothing equals `UNKNOWN:belts-disagree`. **AN UN-ACTIONABLE VERDICT IS SAFE
# BY CONSTRUCTION, NOT BY THE AUTHOR REMEMBERING.**
UNKNOWN = "UNKNOWN"

# A ROW THAT IS A TOOL IS A DIFFERENT KIND OF CLAIM FROM A ROW THAT IS AN OUTPUT. An output nobody
# names is junk. **A TOOL nobody names is a question about a person**, and this classifier cannot
# answer it, so it is `UNKNOWN` and not `DELETE` -- which is also the only thing standing between a
# sweep and the four of this project's own incident reports written by people.
TOOL_EXT = (".py", ".sh", ".mjs", ".c", ".js", ".ts", ".bend")

# What counts as being NAMED. Reports are where claims live; AGENTS.md and checks/README.md are
# what a reader actually reads.
#
# `:(glob)` IS LOAD-BEARING AND ITS ABSENCE WAS A 63% CORRUPTION. MEASURED 2026-10-05: git's
# DEFAULT pathspec magic treats `*` as FNM_PATHNAME-OFF, so `*` CROSSES `/`. `.agents/slop/*.md`
# therefore matched **195** files where `:(glob).agents/slop/*.md` matches **98** — and the extra 97
# were reports from INSIDE the shadow trees this script exists to delete, i.e. COPIES OF THE CORPUS
# ITSELF. The citation blob was **3,736,092 chars of which 1,370,376 were real**: 63% of the
# evidence was a copy of the evidence, so any file named inside a shadow tree counted as "named" and
# the KEEP set was inflated by exactly the files the sweep should have removed.
#
# **A CITATION INDEX BUILT FROM THE TREE BEING SWEPT IS NOT A CITATION INDEX.**
#
# **`checks/*.py` AND `gates/*.py` WERE MISSING, AND THAT IS WHY THE e2e GATE DIED.** MEASURED
# 2026-10-05: this list was byte-identical before and after the sweep that deleted `e2e_mm.py`,
# `e2e_mm.bend` and `e2e_mm_run.mjs` — stage 1's driver, so `checks/e2e.py` exited 2 in stage 1 and
# stages 2-8 NEVER RAN. The guard was not broken; **the gate was not in the corpus.** Both
# `checks/e2e.py` and `checks/sweep.py` name `e2e_mm.py`, and `checks/README.md` has named it
# **0 times, then and now** — so the ONLY thing keeping the project's one artifact alive was
# `.agents/slop/E2E-THROUGH-PORT.md`. **AN INSTRUMENT'S SURVIVAL DEPENDED ON A REPORT MENTIONING IT.**
#
# **A GATE NAMES ITS OWN INPUTS. THAT IS STRUCTURAL; A REPORT MENTIONING THEM IS A COINCIDENCE.**
NAMED_BY = [":(glob).agents/slop/*.md", "AGENTS.md", ":(glob)checks/*.md",
            ":(glob)gates/*.md", ":(glob).agents/*.md",
            ":(glob)checks/*.py", ":(glob)gates/*.py"]

# THIS CHECK'S OWN OUTPUT. It is excluded from the corpus above, and the exclusion is what stops this
# file from being the citation that keeps the rows it is reporting on. It is a MODULE CONSTANT so the
# discovery below finds it by the same rule that finds `residue.OUT`, with no entry written here.
SELF = ".agents/slop/slopfinal"


# ---- THE PATH RESOLVER. DISCOVERED BY WALK, NEVER BY A LIST OF DIRECTORIES. --------------------
#
# **EVERY SPELLING A PATH IS ACTUALLY WRITTEN IN, AND EACH ONE IS MEASURED.** The previous
# resolver handled `Constant`, `Name` and `Call(join)` and MEASURED 2026-10-14 on 209
# instruments it named **1** directory. Each addition below is here because a count of the tree
# said it was load-bearing, not because it sounds right:
#
#   `BinOp(Div)`    MEASURED 2026-10-14: **854** `Div` sites in `checks/` + `gates/`, of which
#                   **612** have a string literal or a string-bound name as an operand and so
#                   are provably PATH divisions; 1 is arithmetic and 241 are over computed
#                   values. `Path.__truediv__` is the dominant path spelling in this tree --
#                   **93 of 154 `write_text` receivers are a `BinOp`** -- and `Div` was not
#                   implemented at all.
#   `BinOp(Add)`    40 `Add` sites; `SLOP + "/sub"` is the other spelling.
#   the RECEIVER    MEASURED: `write_text` has 154 call sites and is a METHOD at every one of
#                   them, so the path is the RECEIVER and the argument is the CONTENT. The old
#                   resolver read `node.args`, so on 154 write sites it was reading file
#                   contents for a path. MEASURED: **0** of those 154 content arguments carries
#                   a `.agents/slop` literal, so nothing was found -- and nothing found looks
#                   exactly like nothing there.
#   LOCAL SCOPES    MEASURED: **120 of 209** instruments bind a name inside a function that is
#                   not bound at module level, and a module-level-only environment cannot see
#                   the tree's write sites.
#   SOURCE ORDER    `checks/slop-declare.py:90-92` is `ROOT = ...`, `SLOP = ".agents/slop"`,
#                   `HERE = ROOT / SLOP / "declare"`. Resolving each binding against an EMPTY
#                   environment lost `SLOP`, so `HERE` became `UNKNOWN/UNKNOWN/declare`, held no
#                   `.agents/slop/` prefix, and **`.agents/slop/declare` disappeared from the
#                   census while the census reported "0 invisible sites".** A resolver that
#                   resolves in the wrong order CANNOT SEE, and a resolver that cannot see
#                   reports `0` instead of `I do not know`.
#
# **THE FAIL-SAFE IS FIXED AND IT IS NOT SYMMETRIC.** Everything here feeds `house_excluded`,
# which removes a tree from the citation corpus; removing evidence makes rows uncited and an
# uncited row is one `DELETE` away. So an unresolvable part becomes the marker `UNKNOWN_MARK`,
# a byte that cannot occur in a path, and `slop_dir()` REFUSES any directory whose first
# component carries it:
#
#     os.path.join(ROOT, ".agents/slop/residue")  ->  ?/.agents/slop/residue   -> `residue`
#     os.path.join(ROOT, SLOP, "sub")             ->  ?/.agents/slop/sub      -> `sub`
#     os.path.join(ROOT, SLOP, name)              ->  ?/.agents/slop/?        -> REFUSED
#
# **THE PREFIX IS REAL AND THE FIRST COMPONENT IS NOT, AND REFUSING IS THE ONLY HONEST ANSWER.**
# A resolver that dropped the unknown argument and took the next component would name a
# directory nobody writes to -- and a directory the sweep stops reading is a directory the
# sweep may destroy.
UNKNOWN_MARK = "\x00"
MODULE_MARK = "\x01"          # "this name is an IMPORTED MODULE": not a path, and an alias
                              # is not the module (`importlib.util` vs `util`). MEASURED
                              # 2026-10-14: omitting this hid `.agents/slop/oracletxt` from the
                              # READ census twice, for two different reasons.
# THE FILESYSTEM VOCABULARY. **THIS IS A VOCABULARY OF THE LANGUAGE, NOT A POPULATION OF THIS
# REPOSITORY** -- the directories are found by walking the ASTs, and nothing below names one.
# It is keyed by `(module, function)` rather than by BARE CALLEE NAME for a measured reason:
# **62 of the tree's 62 `replace` call sites are `str.replace`**, and
# `checks/cl-port-gate.py:245`'s first argument is the literal
# `'import "../../../.agents/slop/clangshim/libclang-ffi.c"'` -- so a bare-name table excludes
# `.agents/slop/clangshim`, which `checks/cl-port-gate.py:51` reads as `SHIM / "libclang-ffi.c"`
# and `:89` ASSERTS the shipped port still imports. **A STRING METHOD SHARES A NAME WITH A
# FILESYSTEM ONE, AND THAT IS THE FALSE POSITIVE THAT MATTERS MOST.**
FS_WRITES = {("os", "makedirs"): (0,), ("os", "mkdir"): (0,), ("os", "open"): (0,),
             ("os", "link"): (0,), ("os", "symlink"): (0,),
             ("os", "rename"): (0, 1), ("os", "replace"): (0, 1),
             ("shutil", "copy"): (1,), ("shutil", "copy2"): (1,),
             ("shutil", "copyfile"): (1,), ("shutil", "copytree"): (1,), ("shutil", "move"): (1,),
             ("shutil", "copymode"): (1,), ("shutil", "copystat"): (1,),
             ("json", "dump"): (1,), ("pickle", "dump"): (1,)}
# `open` IS A BUILTIN AND LIVES IN NO MODULE. **IT IS HERE ONLY BECAUSE A MODE DECIDES IT.**
BARE_WRITES = {"open": (0,)}
# METHODS ON A `Path`. "R" the RECEIVER only -- the argument is CONTENT. "RA" receiver and
# arguments: `rename`/`replace`/`symlink_to` create entries on both sides.
FS_METHOD_WRITES = {"write_text": "R", "write_bytes": "R", "touch": "R", "mkdir": "R",
                    "open": "R", "symlink_to": "RA", "rename": "RA", "replace": "RA"}
# **DEAD (5) -- NOTHING READS THIS TABLE, AND IT IS NOT A SUBSET OF ANYTHING.** `_table_lookup`
# selects `FS_WRITES` or `FS_READS`; `FS_DELETES` has ONE mention in the file, which is this
# comment. `FS_WRITES` carries 15 entries and NONE of these four, so this is neither a duplicate
# of the write vocabulary nor a wired-in refinement of it.
# **KEPT, NOT DELETED, BECAUSE IT IS THE ONLY MACHINE-READABLE RECORD OF A DECISION.** The
# decision: destructive calls name a path an instrument wants GONE, so excluding a directory
# something deletes would protect a directory that is already doomed. It is STATED AND UNBUILT.
# **AND THE NUMBER THAT JUSTIFIED IT HAD DRIFTED INTO FICTION.** This read `MEASURED: 11 sites`.
# MEASURED 2026-10-15 by AST over all 1,779 tracked .py (0 unparseable): **143** -- `shutil.rmtree`
# 107, `os.unlink` 20, `os.remove` 13, `os.rmdir` 3 -- and no scope reproduces 11 (`checks/` +
# `gates/` is 12; minus this file's own two, 10). A citation is a LOWER BOUND; this one had
# stopped being one, and a fiction followed by a `{...}` reads as configuration.
# **THE ONE MEASUREMENT THAT REVIVES IT: the directories `FS_WRITES` + `FS_DELETES` would mark as
# written, diffed against what `FS_WRITES` marks today.** That changes a load-bearing exclusion
# set, so it is measured before it is built.
FS_DELETES = {("os", "remove"): (0,), ("os", "rmdir"): (0,), ("os", "unlink"): (0,),
              ("shutil", "rmtree"): (0,)}
# THE READ SIDE, WHICH IS WHAT MAKES `self_output_dirs` REFUSE A COLLISION. **A PATH HANDED TO
# AN IMPORT MACHINE IS A READ**, and no `open` and no `read_text` sees it: MEASURED,
# `checks/oracle-txt-census.py:215` is `importlib.util.spec_from_file_location("plant", ROOT /
# ".agents/slop/oracletxt/plant.py")`, and it is the whole reason `.agents/slop/oracletxt` is
# not excluded.
FS_READS = {("os", "readlink"): (0,), ("os", "stat"): (0,), ("os", "lstat"): (0,),
            ("importlib", "spec_from_file_location"): (1,), ("runpy", "run_path"): (0,)}
FS_READ_METHODS = frozenset({"read_text", "read_bytes", "readlink", "iterdir", "glob",
                             "exists", "is_file", "is_dir", "stat", "lstat", "resolve"})
PATH_CTORS = frozenset({"Path", "PurePosixPath", "PosixPath", "join", "joinpath",
                        "resolve", "absolute", "expanduser", "parent"})
PATH_ANNOTATIONS = frozenset({"Path", "PurePosixPath", "PosixPath", "PurePath"})
PATH_KEYWORDS = frozenset({"file", "fp", "src", "dst", "target", "dirpath"})
WRITE_MODES = frozenset("wax+")
SLOP_PREFIX = ".agents/slop"


def _table_lookup(table: dict, mod: str | None, fn: str):
    """`table[(mod, fn)]`, then the FIRST component, then the LAST -- all three, in that order.

    MEASURED 2026-10-14, ONE FALLBACK WAS NOT ENOUGH TWICE. `import importlib.util` yields the
    dotted name `importlib.util`; the table is keyed `importlib`; falling back to the last
    component yields `util`, which is a DIFFERENT module, so the lookup declines."""
    if mod is None:
        return None
    parts = mod.split(".")
    for key in (mod, parts[0], parts[-1]):
        if (key, fn) in table:
            return table[(key, fn)]
    return None


def _resolve(node, env) -> str:
    """The path a node contributes, with `UNKNOWN_MARK` where a part cannot be named.

    EVERY SHAPE THAT IS NOT A PATH EXPRESSION RETURNS THE MARKER AND NOT `None`, because the
    marker is what lets `slop_dir()` SEE that an opaque part sits AFTER a real `.agents/slop/`
    prefix -- which is the case that must be refused. **A RESOLVER THAT RETURNS `None` FOR ONE
    PART AND A STRING FOR ANOTHER CANNOT DISTINGUISH `os.path.join(ROOT, SLOP, "sub")` FROM
    `os.path.join(ROOT, SLOP, name)`, AND THE SECOND ONE MUST NOT BECOME A DIRECTORY.**"""
    if isinstance(node, ast.Constant):
        return node.value if isinstance(node.value, str) else UNKNOWN_MARK
    if isinstance(node, ast.Name):
        v = env.get(node.id)
        if v is None or v[0].startswith(MODULE_MARK):
            return UNKNOWN_MARK
        return v[0]
    if isinstance(node, ast.BinOp):
        left, right = _resolve(node.left, env), _resolve(node.right, env)
        if isinstance(node.op, ast.Div):
            return left + right if left.endswith("/") else left + "/" + right
        if isinstance(node.op, ast.Add):
            return left + right
        return UNKNOWN_MARK
    if isinstance(node, ast.Call):
        fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
        if fn in ("join", "joinpath"):
            # `"".join([SLOP, "a"])` passes ONE argument that is a LIST. **This is the ONE
            # spelling the previous resolver claimed to support**, and a form of it that does
            # not resolve is a defect its own docstring cannot survive.
            args = list(node.args)
            if len(args) == 1 and isinstance(args[0], (ast.List, ast.Tuple)):
                args = list(args[0].elts)
            return "/".join(_resolve(a, env).strip("/") or UNKNOWN_MARK for a in args) or UNKNOWN_MARK
        if fn in ("resolve", "absolute", "expanduser"):
            return _resolve(node.func.value, env) if isinstance(node.func, ast.Attribute) else UNKNOWN_MARK
        if fn == "parent":
            base = _resolve(node.func.value, env) if isinstance(node.func, ast.Attribute) else UNKNOWN_MARK
            return base.rpartition("/")[0] or UNKNOWN_MARK
        if fn in ("Path", "PurePosixPath", "PosixPath"):
            return _resolve(node.args[0], env).rstrip("/") if node.args else UNKNOWN_MARK
        return UNKNOWN_MARK
    # `Path(__file__).resolve().parents[1]` LANDS HERE, AND IT IS THE SPELLING THE THIRD REPORT
    # NAMED. MEASURED 2026-10-14: `parents` is a PROPERTY, so the node is a `Subscript` whose
    # `.value` is a bare `ast.Attribute` and NOT an `ast.Call` -- which is why a branch requiring
    # the `Call` form could never reach it, and why it was DEAD CODE rather than a working one.
    # **SEEING THE SHAPE IS NOT ANSWERING IT.** `parents[1]` names a directory this resolver
    # cannot name without executing the module, and guessing the repo root would exclude ALL of
    # `.agents/slop` from the citation corpus on the strength of a subscript.
    return UNKNOWN_MARK


def _is_path_expr(node, env) -> bool:
    """Is this node a PATH? A `str` is not, and a `str` has every method a `Path` has.

    **A BINDING TO A STRING IS NOT A BINDING TO A PATH**, which is the residual half of the
    `str.replace` defect: `text = "..."` then `text.replace(...)` made `text` a bound name, and
    treating that as a `Path` read the receiver's ARGUMENT as a path. Every binding therefore
    carries an `is_path` flag taken from the value's own SHAPE: a `BinOp` over `/` or `+`, or a
    `PATH_CTORS` call, or a name that is itself a path. A bare string literal is NOT a path --
    which is correct, because the one place a bare literal is certainly a path
    (`os.makedirs(".agents/slop/x")`) is a MODULE FUNCTION, where this is never consulted."""
    if isinstance(node, ast.Name):
        v = env.get(node.id)
        return v is not None and v[1] and not v[0].startswith(MODULE_MARK)
    if isinstance(node, ast.BinOp):
        return isinstance(node.op, (ast.Div, ast.Add))
    if isinstance(node, ast.Call):
        fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
        return fn in PATH_CTORS
    return False


def _module_of(node, env) -> str | None:
    """The module a call is qualified by, or `None`. **A DOTTED CHAIN IS ONE NAME**:
    `importlib.util.spec_from_file_location` is qualified by `importlib.util`, which is an
    `ast.Attribute`, and a name-keyed test declines it -- twice, for two different reasons."""
    if not isinstance(node.func, ast.Attribute):
        return None
    parts, cur = [], node.func.value
    while isinstance(cur, ast.Attribute):
        parts.append(cur.attr)
        cur = cur.value
    if not isinstance(cur, ast.Name):
        return None
    dotted = ".".join(reversed(parts + [cur.id]))
    v = env.get(dotted) or env.get(cur.id)
    if v is not None and v[0].startswith(MODULE_MARK):
        return v[0][len(MODULE_MARK):] or None
    return dotted.rsplit(".", 1)[-1] if cur.id in sys.stdlib_module_names else None


def _bind(stmts, env):
    """Thread a binding environment through a statement list **IN SOURCE ORDER**."""
    for st in stmts:
        if isinstance(st, ast.Import):
            for a in st.names:
                env[a.asname or a.name.split(".")[0]] = (MODULE_MARK + a.name, False)
            continue
        if isinstance(st, ast.ImportFrom):
            for a in st.names:
                if a.name != "*":
                    env[a.asname or a.name] = (MODULE_MARK + (st.module or ""), False)
            continue
        targets, value = [], None
        if isinstance(st, ast.Assign):
            targets = [t for t in st.targets if isinstance(t, ast.Name)]
            value = st.value
        elif isinstance(st, ast.AnnAssign) and isinstance(st.target, ast.Name) and st.value:
            targets, value = [st.target], st.value
        if len(targets) == 1 and value is not None:
            env[targets[0].id] = (_resolve(value, env), _is_path_expr(value, env))
        for field in ("body", "orelse", "finalbody"):
            sub = getattr(st, field, None)
            if isinstance(sub, list) and sub and isinstance(sub[0], ast.stmt):
                _bind(sub, env)
        for h in getattr(st, "handlers", None) or []:
            _bind(h.body, env)
    return env


def _scopes(tree):
    """`(statements, environment)` per scope. A FUNCTION IS ONE SCOPE AND THE MODULE SCOPE IS
    THE TOP-LEVEL STATEMENTS WITH THE FUNCTION BODIES REMOVED -- an earlier version walked
    `tree.body` and descended into every function, so every function-level write was counted
    TWICE (MEASURED: 552 sites where the true figure was 274). The directory SET was unaffected
    because it is a set, so the headline never showed it. **A COUNT THAT DOUBLE-COUNTS AND A
    COUNT THAT READS CLEAN ARE THE SAME FAILURE, AND ONLY THE FIRST ONE GETS NOTICED.**"""
    menv = _bind(list(tree.body), {})
    out = [([s for s in tree.body
             if not isinstance(s, (ast.FunctionDef, ast.AsyncFunctionDef))], dict(menv))]
    for fn in ast.walk(tree):
        if isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
            args = fn.args
            positional = list(getattr(args, "posonlyargs", [])) + list(args.args)
            fenv = dict(menv)
            for a in positional + list(args.kwonlyargs):
                if a.arg not in ("self", "cls"):
                    fenv.setdefault(a.arg, (UNKNOWN_MARK, _annotated_path(a)))
            for p, d in zip(positional[len(positional) - len(args.defaults):], args.defaults):
                fenv[p.arg] = (_resolve(d, fenv), _is_path_expr(d, fenv) or _annotated_path(p))
            out.append((fn.body, _bind(list(fn.body), fenv)))
    return out


def _annotated_path(a) -> bool:
    """Is this parameter ANNOTATED as a Path? Decidable from the AST, and it needs no list.
    A parameter with no such annotation could be a Path and could be a string, so it is not
    treated as one: the cost is a missed write, never an invented ownership claim."""
    return isinstance(a.annotation, ast.Name) and a.annotation.id in PATH_ANNOTATIONS


def _path_slots(node, env, read: bool) -> list | None:
    """The AST nodes at this call site that hold a PATH, or `None` if the site is not one.

    `None` IS A VERDICT. On the write side it is reached for a callee outside the vocabulary,
    for a method whose qualifier is not a path expression, and -- the one that matters --
    **for `open` whose mode is a read or does not resolve. AN UNRESOLVED MODE IS NOT A WRITE.**
    MEASURED 2026-10-14: the tree's `open` sites are 57 bare `open(...)`, 9 `Path.open(...)`
    and 4 with a `BinOp` receiver, and the previous mode test read `node.args[1]` ONLY -- so
    `Path.open`, which takes `mode=` as a KEYWORD, and any `open(p, mode="w")`, read as no mode
    at all, defaulted to `"r"`, and a genuine write was skipped."""
    if isinstance(node.func, ast.Name):
        spec, recv = BARE_WRITES.get(node.func.id), None
        if spec is None:
            return None
    elif isinstance(node.func, ast.Attribute):
        mod = _module_of(node, env)
        fn = node.func.attr
        if mod is not None:
            spec = _table_lookup(FS_WRITES if not read else FS_READS, mod, fn)
            recv = None
        elif _is_path_expr(node.func.value, env):
            spec = FS_METHOD_WRITES.get(fn) if not read else (
                "R" if fn in FS_READ_METHODS else None)
            recv = node.func.value
        else:
            return None
        if spec is None:
            return None
    else:
        return None
    slots: list = []
    if isinstance(spec, str):
        if recv is not None:
            slots.append(recv)
        if spec == "RA":
            slots += list(node.args)
    else:
        slots += [node.args[i] for i in spec if i < len(node.args)]
    slots += [k.value for k in node.keywords if k.arg in PATH_KEYWORDS]
    callee = node.func.id if isinstance(node.func, ast.Name) else node.func.attr
    if callee == "open":
        mode = _resolve(node.args[1], env) if len(node.args) > 1 else None
        if mode is None:
            mode = next((_resolve(k.value, env) for k in node.keywords if k.arg == "mode"), None)
        if read:
            if mode is not None and any(ch in mode for ch in WRITE_MODES):
                return None                     # a write, not a read
        elif mode is None or not any(ch in mode for ch in WRITE_MODES):
            return None                         # a read, or an unknown mode: not a write
    return slots


def slop_dir(value: str) -> str | None:
    """The `.agents/slop/<dir>` a path names, or `None`.

    **FOUR RULES, AND THE FOURTH IS THE ONE THAT MAKES THE OTHER THREE SAFE.** One component, no
    dot -- a FILE an instrument writes is not an output DIRECTORY. A trailing slash is not a
    suffix -- the tail is stripped. An empty tail is not a directory. And a first component
    carrying `UNKNOWN_MARK` NAMES NO DIRECTORY AT ALL: the `.agents/slop/` prefix can be real
    while the directory inside it is a loop variable. **AN EXCLUSION MUST BE COARSER THAN THE
    NAME IT EXCLUDES, AND IT MUST ALSO BE ACTUAL.**"""
    if SLOP_PREFIX + "/" not in value:
        return None
    head = value.split(SLOP_PREFIX + "/", 1)[1].strip("/").split("/")[0]
    if not head or "." in head or UNKNOWN_MARK in head:
        return None
    return SLOP_PREFIX + "/" + head


def _instrument_files(root: str) -> list[str]:
    """Every `.py` under `checks/` and `gates/`, by DIRECTORY WALK.

    **A WALK, NOT A GLOB, AND ON THIS TREE THE DIFFERENCE IS ZERO.** MEASURED 2026-10-14 14:20:
    `os.walk` finds **209** and `glob('checks/*.py') + glob('gates/*.py')` finds **209**, with an
    empty symmetric difference -- so the glob is not the blind spot here. The walk is used
    because a walk cannot be defeated by a new subdirectory. **AND THE DENOMINATOR MOVED WHILE
    I COUNTED IT**: the same walk read **208** at 14:18 and **209** at 14:20, the delta being
    `gates/.mut-run.py` written by another unit mid-census. **A COUNT WITHOUT A TIMESTAMP IS A
    CLAIM ABOUT A TREE THAT STOPPED EXISTING.**"""
    out = []
    for base in ("checks", "gates"):
        for dirpath, dirnames, filenames in os.walk(os.path.join(root, base)):
            dirnames[:] = sorted(d for d in dirnames if d != "__pycache__")
            out += [os.path.join(dirpath, f) for f in sorted(filenames) if f.endswith(".py")]
    return sorted(out)


_TARGETS_CACHE: dict[str, tuple[set[str], set[str]]] = {}


def _slop_targets(root: str) -> tuple[set[str], set[str]]:
    """`(written, read)` -- every `.agents/slop/<dir>` a live instrument touches, by AST.

    **ONE PASS, ONE PARSE PER FILE, ONE RESULT PER ROOT.** `house_excluded` asks this question
    once per CORPUS FILE, and MEASURED 2026-10-14 13:14Z a full `--plan` exceeded 15 minutes
    with the resolver recomputed per row. **THIS IS THE PROJECT'S THIRD PERFORMANCE BUG AND IT
    IS A PER-ITEM SCAN OF A SHARED MEASUREMENT**: the answer does not change between two rows in
    the same directory, so recomputing it is not an optimisation to avoid, it is the only wrong
    shape. `generated_read_dirs` at the top of this file already carries a cache for exactly
    this reason and the same comment.

    **A CACHE IS NOT A POPULATION, AND THE DIFFERENCE IS WHERE THE POPULATION IS BUILT.** The
    set is derived here, by walking the instrument ASTs, on the first call; the cache only stops
    the SAME derivation being redone 974 times in the same process. Nothing here names a
    directory.

    **THE KEY IS `root` AND THE VALUE IS NOT A PURE FUNCTION OF `root` -- IT IS A SNAPSHOT, AND
    THAT IS THE DESIGN, NOT AN ACCIDENT.** MEASURED 2026-10-14 16:47, cold: **0.647 s** for one
    census of **209 instruments**, answering **3 written** and **7 read** `.agents/slop/<dir>`s.
    Warm: 1 microsecond. The 974 calls it serves are `house_excluded`, one per corpus row.

    **WHAT CHANGES BETWEEN TWO CALLS WITHIN ONE RUN: THE TREE UNDER `checks/` AND `gates/`.** Those
    are 209 source files three other units are editing, and this very function's docstring records
    the census growing from **208 to 209 in two minutes** on 2026-10-14 14:18 -> 14:20, the delta
    being `gates/.mut-run.py`. So there is no honest "nothing changes" and this cache does not claim
    one.

    **WHY FREEZING IS STILL THE CORRECT ANSWER: A PLAN MUST BE INTERNALLY COHERENT.** The rows
    `house_excluded` decides are the corpus the same run reads and indexes; a census that moved
    mid-run would let a report be excluded from a corpus built with one answer and judged against
    another, and nothing downstream could detect it, because both answers are individually
    defensible. A point-in-time snapshot is the only shape a report can be checked against, and it
    is the same reason `Facts` is `functools.cache`d, the same reason `classify` takes ONE walk and
    applies the window afterwards, and the same reason `generated_read_dirs` is memoised.

    **THE SCOPE IS THE PROCESS, AND `_TARGETS_CACHE.clear()` IS THE INVALIDATION HOOK.** No
    long-lived caller exists: `--plan` and `--apply` each build one `Facts` and exit, and `facts()`
    is `@functools.cache`d per root, so there is exactly one snapshot per run. Anything that must
    see a later census has to clear both caches, and `sweep.py` has no such path.
    """
    if root not in _TARGETS_CACHE:
        writes: set[str] = set()
        reads: set[str] = set()
        for path in _instrument_files(root):
            try:
                tree = ast.parse(open(path, errors="replace").read())
            except (OSError, SyntaxError):
                continue
            for body, env in _scopes(tree):
                for node in ast.walk(ast.Module(body=list(body), type_ignores=[])):
                    if not isinstance(node, ast.Call):
                        continue
                    for read, out in ((False, writes), (True, reads)):
                        for slot in _path_slots(node, env, read) or []:
                            d = slop_dir(_resolve(slot, env))
                            if d:
                                out.add(d)
        _TARGETS_CACHE[root] = (writes, reads)
    return _TARGETS_CACHE[root]


def _slop_write_targets(root: str) -> set[str]:
    return _slop_targets(root)[0]


def _slop_read_targets(root: str) -> set[str]:
    return _slop_targets(root)[1]


def self_output_dirs(root: str = ROOT) -> tuple[str, ...]:
    """Every directory under `.agents/slop` that an instrument in `checks/` or `gates/` WRITES TO
    **AND THAT NO INSTRUMENT READS**.

    THE THIRD OCCURRENCE OF ONE SHAPE HAS A FIX THAT IS NOT A LIST. `.agents/slop/residue/
    000-the-residue.md` names every residue row by path; the moment it was staged the next run found
    every row CITED by the report that enumerates them, and the residue collapsed from 40 `UNNAMED`
    to 0. A THIRD variant is waiting for any report of mine, so the fix is structural.

    **WRITE-TARGET, NOT MENTION, AND THE DIFFERENCE IS THE WHOLE PROBLEM.** A first attempt took
    every string literal beginning `.agents/slop/` and got **24 directories from 61 modules** --
    including `e2e_mm.py`, `e2e_port/run-port-mm.sh`, `f64/run-f64.sh` and `graphcmp.py`. Those are a
    gate's REQUIRED INPUTS: excluding them re-breaks the one artifact in this repository, and it
    would do it *silently*, by making stage 1's driver invisible to the census that exists to keep
    it alive. **A MENTION IS NOT AN OWNERSHIP CLAIM; A WRITE IS.** So a directory is excluded only
    when a binding resolves to it AND a write call names it.

    **AND A WRITE IS NOT ENOUGH, WHICH IS WHAT THE 2026-10-14 REWRITE COST.** A directory an
    instrument BOTH writes and READS is a gate's required input that happens to sit beside its
    output, and excluding it re-breaks the gate by the route the paragraph above warns about.
    MEASURED 2026-10-14 13:20Z on 209 instruments: the write census names **3** directories and the
    read census names **7**, and the intersection is **2** -- `.agents/slop/declare`
    (`checks/slop-declare.py:250` writes `declare.tsv`, `:128`/`:216` read the directory) and
    `.agents/slop/oracletxt` (`checks/oracle-txt-census.py:473` writes `census.json`, **`:215`
    LOADS `.agents/slop/oracletxt/plant.py` BY PATH AS ITS PLANT GENERATOR**). So this function
    returns **1**, and `self_output_conflicts()` reports the 2 it refuses. **A RESOLVER THAT IS
    MORE CORRECT ABOUT WRITES IS NOT, BY ITSELF, A SAFER EXCLUSION**, and the difference between
    those two sentences is the whole reason this function was deferred three times.

    DISCOVERED BY AST, NEVER EXECUTED. Executing 209 modules to read a constant would run 209
    instruments' import side effects to answer a question about text.
    """
    writes, reads = _slop_write_targets(root), _slop_read_targets(root)
    return tuple(sorted(writes - reads))


def self_output_conflicts(root: str = ROOT) -> tuple[str, ...]:
    """Directories that are BOTH written and read, and are therefore NOT excluded.

    **A REFUSAL IS A VERDICT AND IT IS REPORTED, BECAUSE A SILENT REFUSAL IS THE SAME OBJECT AS
    A MISS.** `main()` prints this beside the exclusion list; without that line this function
    would be an unmeasurable improvement indistinguishable from the bug it replaced."""
    return tuple(sorted(_slop_write_targets(root) & _slop_read_targets(root)))


def self_excludes(root: str = ROOT) -> list[str]:
    """The `:(exclude)` pathspecs for those directories, plus this file's own."""
    return [f":(exclude){d}/**" for d in (*self_output_dirs(root), SELF)]


def house_excluded(root: str, rel: str) -> bool:
    """Is this path OUT OF CENSUS by the house rules -- a shadow tree, or an instrument's own output?

    **CONSUME `residue.EXCLUDED_DIRS`, DO NOT COPY IT.** The house rules exclude `dd-cone-wt/`,
    `xd1/`, `strays/`, `strays-root/`, `rf2root/`, `diffpy/`, `e2e*/`, `f64/`, `portexec/`,
    `gates/{oracles,artifacts}/` and every live unit's directory from every walk. Those names live in
    `checks/residue.py`, which is another unit's file, and a second copy of them here would be a
    contract with no generator -- the shape that produced `LIVE_UNITS`, `ORACLE_WORD` and the 139
    `.txt` names in one session. So the question is ASKED.

    ONE PREDICATE FOR BOTH ROLES. A path that is out of census must be out of census for the CITATION
    INDEX and for the WALK, or the index reads a shadow tree's own report as an authority while the
    classifier calls the same tree junk -- two instruments, one tree, opposite answers.

    **CALLED 974 TIMES PER `--plan`, AND WHAT IT COSTS PER CALL IS THE HEADLINE.** MEASURED
    2026-10-14 16:41: `Facts.__init__` builds the corpus, `committed_files` is called at :923 and
    :931, and each call walks `sorted(tracked)` filtering for `.md` under `.agents/slop/`, which is
    **487 paths**, so **2 x 487 = 974 invocations**. `self_output_dirs` is memoised (`_TARGETS_CACHE`)
    and costs 0.129 ms/row warm; the `checks/residue.py` load it used to repeat per call is now
    `load_by_path`, one execution for the whole process.
    """
    if any(rel.startswith(d + "/") for d in (*self_output_dirs(root), SELF)):
        return True
    try:
        return load_by_path(os.path.join(root, "checks/residue.py")).excluded(rel)
    except Exception:
        return False


# A gate names itself with these words. `-gate`/`-check` decide; `probe`/`mutate`/`gen`/`fix` are
# a thing that was run once. The distinction is the project's own vocabulary, not mine.
#
# **`GATE_WORD` IS GONE AND ITS BRANCH WAS DEAD CODE.** It was read in a branch that required
# `name in mentioned` to be true, and the line above it returned `KEEP-CITED` on exactly that
# condition, so the branch had no input that could reach it. **AN UNREACHABLE RULE IS NOT A SAFETY
# NET, IT IS A COMMENT THAT LOOKS LIKE ONE.** Its vocabulary is not lost: `differ.declared()` and the
# citation belts are what decide a gate now, and re-ordering that branch to be live would be a
# separate decision because it would make `--apply GATE` MOVE files.
ORACLE_WORD = re.compile(r"(^|[-_.])(oracle|rows|expect|pins|baseline)([-_.]|$)")

# Never touch these, whatever they look like. Each has caused a loss or a false verdict.
#
# `E2E_CHAIN` IS HERE BECAUSE I DELETED IT ONCE. The first `--apply DELETE` run moved 521 files
# and deleted the fixtures and stage drivers of the project's ONE artifact: `e2e_mm.py`,
# `e2e_mm.bend`, `e2e_mm_run.mjs`, `e2e_port/`, `f64/`, `e2e/`. `e2e.sh` itself was moved to
# `checks/` and left pointing at paths that no longer existed, so the artifact was a script that
# could not run. It was recoverable only because every one of those files happened to be
# committed -- WHICH IS NOT A PROPERTY OF THE SWEEP, IT IS A PROPERTY OF THE DAY.
#
# **`strays/` AND `strays-root/` WERE HERE AND WERE REMOVED, AND THE REASON IS THE THING THIS
# COMMENT ALREADY SAYS ABOVE IN ONE PLACE.** MEASURED 2026-10-05: the marking was
# `"42 files restored from origin after regressing"` -- an INCIDENT, not a DEPENDENCY, which is
# the same false-warrant shape as the six finished `LIVE_UNITS` that held 53% of `.slop`. Every
# mention of either directory outside itself is PROSE: `checks/nvrows-deadrow-gate.py:69`,
# `:205`, `checks/repro-paths.py:28`, `checks/wallcheck.py:101` name them in a docstring or a
# `--file` help string, and no code position reads them. Parked both, re-ran the gates: `no-strays`
# and `repro-paths` and `nvrows-deadrow-gate` produced BYTE-IDENTICAL output, `wallcheck` differed
# only in the pin hash (a concurrent commit), and `no-txt` fell 342 -> 338. **ZERO DEPENDENCY.**
# The `origin` arm is 18 of 21 byte-identical to live; the other 3 are older revisions, two of them
# reproduced by a named commit and `fold.bend` by none, which is why exactly one file was kept and
# 25 were deleted against `.agents/slop/strays/MANIFEST.tsv`. **A PAST ACCIDENT IS NOT A REASON TO
# KEEP A DIRECTORY FOREVER; THE TEST IS WHAT NAMES IT, AND THE ANSWER WAS NOTHING.**
PROTECTED = re.compile(
    r"(RECOVERY-0BYTE\.md$)"                           # the zero-byte incident
    r"|(^\.agents/slop/(e2e|e2e_port|f64|portexec)/)"  # the artifact's fixtures and stage drivers
    r"|(^\.agents/slop/e2e(_mm(\.py|\.bend|_run\.mjs))?\.sh$)"   # e2e.sh itself, and its three fixtures
    r"|(^\.agents/slop/(opsbend-milestone|substrate-check|graphcmp-(run|repro))\.sh$)"
    r"|(^checks/)"                                     # the gates themselves
)

# The differ's implementation and its frozen shell bodies. These are not one-off scripts: they are
# the thing every corpus number comes from. They move, but they move to a real home.
DIFFER = {"graphcmp.py", "graphcmp.bend", "graphcmp-oracle.py",
          "graphcmp-run.sh", "graphcmp-repro.sh", "graphcmp-dbg-oracle.py"}

# A DIRECTORY WHOSE OWN NAME DECLARES ITS ROLE CLASSIFIES ITS WHOLE SUBTREE. MEASURED 2026-10-05:
# `oracles/` (79 files, 520 KB, named by 4 reports) held 60 `.txt` of EXPECTED VALUES and was about to
# be deleted, because the verdict is computed per FILE from its BASENAME — and a file called
# `blob-bn.txt` inside a directory called `oracles` looks like a row dump. **THE ROLE IS A PROPERTY OF
# THE DIRECTORY AND WAS BEING READ FROM THE FILE.** These are the four names this project uses to
# mean a role, so a directory that is one of them is one.
#
# **`strays`/`strays-root` WERE IN THIS DICT AND ARE GONE.** A name in `ROLE_DIRS` is not a milder
# form of `PROTECTED`, it is a STRONGER one: `verdict_for` returns on the FIRST matching path part,
# before the citation test runs at all, so listing a directory here exempted its whole subtree from
# even being classified. **AN INCIDENT WAS ENCODED AS A NAME, WHICH MEANT NOBODY COULD EVER
# DISCOVER THAT THE INCIDENT HAD STOPPED BEING TRUE.** The name outlived its reason exactly the way
# the six finished `LIVE_UNITS` below did.
ROLE_DIRS = {"oracles": "ORACLE", "gates": "GATE", "checks": "GATE"}

# LIVE_UNITS lived here, a tuple of 14 names. It is gone, and `live_units()` near
# `live_set` is what answers the question now: **A GUARD THAT IS CORRECT EXCEPT FOR
# THE LAST DISPATCH IS NOT A GUARD, IT IS A COINCIDENCE WITH THE DISPATCH ORDER.**
# That sentence is why the tuple existed; the tuple kept being wrong in exactly the
# way it described.

# Four MUTATION ARMS, NOT A COPY. `dd-cone-wt/` is 43 MB and 572 files, and the shadowtrees unit
# measured that its four arms differ in exactly TWO files and that `codegen/decomp/dtype.bend` is
# FOUR DISTINCT STATES: **deleting three of the arms destroys three arms.** It is the record of what
# four mutations did, and a mutation's value is its DIFFERENCE from the real file, so the evidence
# is the four-way divergence rather than any one of the trees.
PROTECTED_DIRS = ("dd-cone-wt",)


def committed_files(root: str = ROOT, copies: set[str] | None = None) -> list[tuple[str, str]]:
    """(path, text) for every committed report and every reader-facing doc, read once each.

    PER FILE, because a citation with no ATTRIBUTION cannot be examined. The union of these texts is
    a blob, and a blob answers "is this name mentioned" and nothing else -- so it cannot tell a
    report that depends on a file from a shadow tree naming the files it copied, which are the same
    answer and not the same fact. `checks/residue.py` says the same thing about the same instrument.

    `HEAD:`, AND THAT IS A MEASURED BLIND SPOT. `git show HEAD:<path>` reads the COMMIT, so a report
    that is EDITED BUT UNCOMMITTED contributes its old text, and an UNTRACKED report contributes
    nothing. `Facts.dirty_corpus()` measures the size of the gap and the plan prints it, because a
    bounded blind spot nobody is told the size of is an unbounded one.

    **`.agents/slop` IS WALKED, NOT GLOBBED, AND `:(glob)` WAS THE WRONG DISCRIMINATOR.** The corpus
    once read `:(glob).agents/slop/*.md`, which was introduced because git's default pathspec treats
    `*` as FNM_PATHNAME-OFF, so `*` CROSSES `/` and matched shadow-tree reports -- MEASURED then, 63%
    of the blob was a copy of the evidence. But `:(glob)` does not cross `/` either, and **every unit
    writes its report into a SUBDIRECTORY.** MEASURED on this tree: 262 committed `.md` under
    `.agents/slop`, of which `:(glob)` reaches **98**. **164 real reports were invisible to the index
    that exists to find out what the project depends on**, and the fix for a false positive created a
    false negative 164 times over. Depth cannot tell a unit's claim from a shadow tree's copy --
    `.agents/slop/abi4/README.md` and `.agents/slop/arghalf/pin-tree/tinygrad/viz/README.md` are both
    at depth 2 -- so depth is not used.

    **THE DISCRIMINATOR IS WHETHER THE FILE IS A BYTE-COPY, WHICH IS A PROOF AND NOT A LIST.** A
    corpus file identical to another file contributes no citation the other does not already
    contribute. MEASURED: of 257 widened candidates, **251 survive** (5 out of census by the house
    rules, 1 a copy). Same principle as G8 one level up: G8 asks "is the CITER a copy?", this asks
    "is the CORPUS MEMBER a copy?".
    """
    copies = copies or set()
    out, seen = [], set()
    try:
        names = subprocess.run(["git", "ls-files", "--", *NAMED_BY, *self_excludes(root)],
                               cwd=root, capture_output=True, text=True).stdout.split()
    except Exception:
        return []
    tracked = tracked_files(root)
    names += [n for n in sorted(tracked)
              if n.endswith(".md") and n.startswith(".agents/slop/")
              and n not in copies and not house_excluded(root, n)]
    for nm in names:
        if nm in seen:
            continue
        seen.add(nm)
        try:
            r = subprocess.run(["git", "show", f"HEAD:{nm}"], cwd=root,
                               capture_output=True, text=True, errors="replace")
            if r.returncode == 0:
                out.append((nm, r.stdout))
        except Exception:
            pass
    return out


def committed_named_text(root: str = ROOT) -> str:
    """Every committed report and every reader-facing doc, as one blob."""
    return "\n".join(t for _nm, t in committed_files(root))


def tracked_files(root: str = ROOT) -> set[str]:
    """`git ls-files` MINUS the tracked-but-deleted.

    `git ls-files` RETURNS TRACKED-BUT-DELETED PATHS, so membership tested against it alone calls a
    file committed when it is not on disk at all -- and an uncommitted row would then be deleted as
    if `git` could restore it.

    **`os.path.lexists`, NOT `Path.exists()`: `exists()` FOLLOWS SYMLINKS AND THIS TREE HAS 167 OF
    THEM**, so a dangling link inside `.slop` is reported here as ABSENT while `git` tracks it, and a
    tracked row would be called untracked on the strength of a link's target.

    MEASURED, because the count was quoted as a defect that has since stopped being one: `git
    ls-files` returns 4,609 paths on this tree and **all 4,609 are on disk -- 0 phantom, 0 entries
    carrying the intent-to-add empty-blob SHA `e69de29`.** The 4,109 figure in circulation was true
    earlier today and is FALSE NOW, which is exactly why a premise that is not re-measured decays.
    """
    r = subprocess.run(["git", "ls-files", "-z"], cwd=root, capture_output=True, text=True)
    return {p for p in r.stdout.split("\0") if p and os.path.lexists(os.path.join(root, p))}


def residue_copies(root: str, rows: list[str]) -> set[str]:
    """Which of these residue files are byte-identical to a file OUTSIDE the residue.

    CONSUMED, NOT REIMPLEMENTED. `checks/residue.py` already builds this index and it is not this
    file's to change, so a second sha256 pass over 4,609 tracked files would be a second contract
    with no generator -- which is how four artifacts came to be LOST and four others NEW in this
    project. One import, one call.

    AN AUTHORITY THAT CANNOT BE ASKED YIELDS NOTHING RATHER THAN A TRACEBACK, and `set()` here makes
    the G8 discriminator below DECLINE, which leaves the row `UNKNOWN` -- the safe direction. A
    missing twin map must never become a blanket exemption, and it cannot become a false DELETE
    either, because the only rows it can move are ones already reached from inside the residue.
    """
    try:
        m = load_by_path(os.path.join(root, "checks/residue.py"))
        return set(m.outside_twins(root, tracked_files(root), [(r, 0) for r in rows]))
    except Exception:
        return set()



def declared_names() -> set[str]:
    """Every artifact name `checks/differ.py` RENDERS, plus the `.err` twin its writer emits beside
    each one. IMPORTED, NEVER COPIED: a second list of these names would be a contract with no
    generator, and a stale copy of a contract is how four artifacts came to be LOST and four others
    NEW in this project (`differverdict/VERDICT.md`, at HEAD).

    An authority that cannot be asked yields NO names rather than a traceback: **a carve-out that
    cannot be computed must never become a blanket exemption**, so the rows simply stop being
    AUTHORED and become `UNKNOWN` or `DELETE` as the rest of the tests decide, visibly.
    """
    try:
        spec = importlib.util.spec_from_file_location("differ", os.path.join(CHECKS, "differ.py"))
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        names = set(m.declared())
    except Exception:
        return set()
    return names | {n + ".err" for n in names}


def mentioned_filenames(blob: str) -> set[str]:
    """Every filename-shaped token the corpus mentions, extracted in ONE pass.

    THE THIRD INSTANCE OF THIS PROJECT'S WORST PERFORMANCE BUG, AND THE THIRD TIME THE FIX IS ALSO
    THE MORE CORRECT ANSWER:
      1. `_cleanup/classify.py` ran an empty-pattern `git grep` over the whole repo -- >20 minutes.
      2. `move_gates.py` ran one `git grep` PER FILE over the same corpus.
      3. This file scanned a 3.4 MB corpus ONCE PER FILE: 23,000 x 3.4 MB = ~78 GB of scanning,
         and the first `--plan` TIMED OUT AT 15 MINUTES.

    All three share one shape: **A PER-ITEM SCAN OF A SHARED CORPUS.** The corpus does not change
    between items, so scanning it once is not an optimisation, it is the only correct shape.

    And the single pass is MORE correct than the regex-per-file was. A `name.ext` token pattern
    boundaries itself, so a report mentioning `.error` cannot cite a file called `.err`, and
    `xgraphcmp.py` cannot cite `graphcmp.py` -- which is exactly the rule, arrived at by indexing
    rather than by defending a boundary class.
    """
    return set(re.findall(r"[A-Za-z0-9_][A-Za-z0-9_.-]*\.[A-Za-z0-9]+", blob))


# BELT B, WHICH SHARES NO PATTERN WITH BELT A. This project has been bitten by a belt that could not
# see a stop its sibling belt stopped on, BECAUSE THE TWO SHARED THE REGEX'S ASSUMPTION, so the second
# belt here is a `str.translate` TABLE and has no pattern in it at all. It also finds something belt A
# provably cannot: `mentioned_filenames`'s pattern ends `\.[A-Za-z0-9]+`, so on `ops.staged-blob-24323`
# it matches `ops.staged-blob` and NEVER THE FILE'S NAME -- **a corpus token ending in a hyphenated
# segment is invisible to belt A, and there are files with those names.**
_WORD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-./"


def whole_path_tokens(blob: str) -> set[str]:
    """Every byte that is not a path character becomes a space, then split. A token with a dot in it
    is a name; a token without one is a directory, and `runs/graphcmp/D` names no file."""
    table = str.maketrans({chr(i): " " for i in range(128) if chr(i) not in _WORD})
    return {t for t in blob.translate(table).split() if "." in t}


def in_residue(rel: str) -> bool:
    """Is this path inside one of the two trees this classifier sweeps?

    A CITATION FROM INSIDE THE RESIDUE DOES NOT KEEP A ROW. It is either a real dependency between
    two of the residue's own tools or a shadow tree naming the files it copied, **and those two are
    indistinguishable from out here**, so a row that only the residue names is `UNKNOWN`, not cited.
    """
    parts = rel.split(os.sep)
    return len(parts) > 1 and f"{parts[0]}/{parts[1]}" in RESIDUE_ROOTS


def witness_committed(rel: str, tracked: set[str], root: str = ROOT) -> bool:
    """Is there a COMMITTED report in this row's OWN directory?

    The cheapest decidable test for a tool row, and mechanical: either the directory holds a `.md`
    that is in git, in which case the citation belts have already asked it whether it names the tool,
    or it does not, in which case **the only thing that could ever explain this row is missing**.
    `committed_files` reads `git show HEAD:`, so an EDITED-BUT-UNCOMMITTED report contributes its old
    text -- an uncommitted report cites nothing, and says so here.

    **`root` IS A PARAMETER AND IT WAS NOT.** It read the module global, which is right in production
    and untestable anywhere else: a synthetic tree's row asked whether ITS OWN directory held a
    report and got the PRODUCTION directory's answer, so the one `needs=` this function decides could
    not be planted at all. A predicate that reads a global cannot be exercised against a fixture, and
    **a test that cannot be run is not a test.**
    """
    d = os.path.dirname(rel)
    try:
        names = os.listdir(os.path.join(root, d))
    except OSError:
        return False
    return any(n.endswith(".md") and f"{d}/{n}" in tracked for n in names)


class Facts:
    """Everything the classifier needs that is not the row itself, measured ONCE.

    A PER-ITEM SCAN OF A SHARED CORPUS is this project's third performance bug and it is not an
    optimisation to avoid: the corpus does not change between items, so 1,421 scans of 3.4 MB is the
    same shape as the 23,000 x 3.4 MB that timed out `--plan` at 15 minutes.

    `root` IS A PARAMETER, not a module global, because `--plant` builds this over a synthetic tree
    and a Facts that could only describe the production tree would make every plant a tautology.
    """

    def __init__(self, root: str = ROOT) -> None:
        self.root = root
        self.tracked = tracked_files(root)
        self.files = walk_residue(root)
        # G8'S MAP, and the corpus filter's map -- ONE sha256 index, asked twice. Built here rather
        # than per row because it is a per-item scan of a shared corpus again: asking per row would
        # re-hash every tracked file once per residue row.
        self.copies = residue_copies(root, [r for r, _ in self.files])
        self.declared = declared_names()
        self.chars = 0
        # Belt A's key set is `mentioned_filenames` over the joined blob, token for token: neither
        # pattern can span the newline that joins the files, so indexing per file and taking the
        # union is the same set, and every verdict that used the blob keeps its meaning.
        self.cites: list[dict[str, set[str]]] = [{}, {}]
        # THE CORPUS IS READ ONCE. It was read TWICE with identical arguments -- the second read
        # existed only to recover the list of names, which the first read already held. MEASURED
        # 2026-10-14 16:44: the corpus is **670 members** (327 named by `NAMED_BY` + 453 tracked
        # `.md` under `.agents/slop/`, 110 overlapping, deduped), and `committed_files` spends
        # **one `git show` subprocess per member at 59.6 ms** on a three-agent host, so the duplicate
        # read cost **40 s per call, 80 s per `--plan`, to produce a list the first read had already
        # produced.** Same shape as the 974 calls above: a shared measurement, recomputed, for an
        # answer already in hand. **THE SECOND CALL WAS NOT A CROSS-CHECK, BECAUSE IT COULD NOT BE:
        # IT PASSED THE SAME TWO ARGUMENTS.**
        self.corpus_names = []
        for nm, text in committed_files(root, self.copies):
            self.corpus_names.append(nm)
            self.chars += len(text)
            for belt, toks in ((0, mentioned_filenames(text)), (1, whole_path_tokens(text))):
                index = self.cites[belt]
                for tok in toks:
                    index.setdefault(tok, set()).add(nm)
                    index.setdefault(tok.rsplit("/", 1)[-1], set()).add(nm)
        self.mentioned = set(self.cites[0])

    def dirty_corpus(self) -> tuple[int, int]:
        """(files, bytes) of the corpus that is DIRTY in the worktree, so the index reads stale text.

        Printed next to the headline rather than in a comment, because a bounded blind spot nobody
        is told the size of is an unbounded one.
        """
        names = set(self.corpus_names)
        try:
            st = subprocess.run(["git", "status", "--porcelain", "-z"], cwd=self.root,
                                capture_output=True, text=True).stdout
        except Exception:
            return (0, 0)
        dirty = {x[3:] for x in st.split("\0") if len(x) > 3} & names
        byts = 0
        for d in dirty:
            try:
                byts += os.lstat(os.path.join(self.root, d)).st_size
            except OSError:
                pass
        return (len(dirty), byts)


def walk_residue(root: str = ROOT) -> list[tuple[str, int]]:
    """(relpath, lstat size) for every file under both residue roots. `lstat`, NEVER `getsize`.

    `getsize` and `Path.exists()` both FOLLOW SYMLINKS, and this tree has 167 of them pointing into
    `.venv` and into shadow trees -- which once made a 168 MB tree report as 1,291 MB, a 7.5x
    headline on the one number the instrument exists to publish.
    """
    out = []
    for base in RESIDUE_ROOTS:
        for dirpath, _d, files in os.walk(os.path.join(root, base)):
            for f in files:
                p = os.path.join(dirpath, f)
                try:
                    out.append((os.path.relpath(p, root), os.lstat(p).st_size))
                except OSError:
                    pass
    return out


def port_files(root: str = ROOT, base: str | None = None) -> list[str]:
    """Every file under the SHIPPED PORT, `tinybendygrad/`, by walk -- no suffix filter.

    **A POPULATION `walk_residue` HAS NEVER SEEN, AND `verdict_for` CANNOT CLASSIFY IT BECAUSE
    NOTHING EVER ASKS.** MEASURED 2026-10-06: `RESIDUE_ROOTS` is `(.agents/slop, runs)`, so all 144
    files of the port reach no verdict -- a missing population is invisible exactly like an
    unclassifiable row, and this one hides behind a walk that simply does not descend.

    `base` IS A PARAMETER because `witness_committed`'s lesson is the same one level up: a walk that
    reads a module global can only ever describe the production tree, so the arm could not be planted
    against a fixture and a test that cannot be run is not a test.
    """
    out = []
    for dirpath, _d, files in os.walk(base or os.path.join(root, "tinybendygrad")):
        for f in files:
            p = os.path.join(dirpath, f)
            try:
                os.lstat(p)
            except OSError:
                continue
            out.append(os.path.relpath(p, root))
    return sorted(out)


def port_report(f: Facts, population: list[str] | None = None
                ) -> tuple[collections.Counter, collections.Counter, int]:
    """Classify the port under the SAME rules, and RETURN the counts. REPORT-ONLY.

    **THE PORT IS NEVER A BUCKET `--apply` CAN REACH.** The tree SHIPS, and a population a
    DELETE-capable pass can walk is a population it can destroy -- so this returns counts to the
    plan and is never fed into `rows`. `UNKNOWN` is the interesting column: a file the rules cannot
    place is the whole finding, and reporting it is what ends the silence, not classifying it.
    """
    population = port_files(f.root) if population is None else population
    buckets: collections.Counter = collections.Counter()
    needs: collections.Counter = collections.Counter()
    for rel in population:
        v = verdict_for(rel, f.mentioned, f, set())
        buckets[bucket(v)] += 1
        if v.startswith(UNKNOWN):
            needs[v.partition(":")[2].split(" (")[0]] += 1
    return buckets, needs, len(population)


@functools.cache
def facts(root: str = ROOT) -> Facts:
    """The measurements, built once per process. `--plan` classifies every row against one tree."""
    return Facts(root)


def live_set(minutes: int, root: str = ROOT) -> set[str]:
    cutoff = time.time() - minutes * 60
    live = set()
    for base in (SLOP, RUNS):
        for dirpath, _d, files in os.walk(os.path.join(root, base)):
            for f in files:
                p = os.path.join(dirpath, f)
                try:
                    if os.path.getmtime(p) >= cutoff:
                        live.add(os.path.relpath(p, root))
                except OSError:
                    pass
    return live


_LIVE_UNIT_CACHE: dict[tuple[int, str], set[str]] = {}


def live_units(minutes: int, root: str = ROOT) -> set[str]:
    """THE LIVE ROSTER, DISCOVERED: a unit is live iff the NEWEST file under
    `.agents/slop/<name>/` is younger than the window. One walk, one level down,
    no names, no ledger -- the input is the tree itself.

    **THE LOWER BOUND, STATED WHERE THE RULE LIVES:** a unit that has been
    DISPATCHED but has not yet WRITTEN a file is invisible to an mtime rule, so
    `w=0` names 0 while house rules say units are running. This rule can never
    kill a live unit's files, but it can MISS one with nothing to show yet. It is
    a LOWER BOUND on liveness, not an equality. If a dispatch-time record naming
    each unit's directory ever appears, this becomes `OR` with that record -- a
    declared input, not a tuple. Until then, silence is the honest count.

    **A GUARD THAT IS CORRECT EXCEPT FOR THE LAST DISPATCH IS NOT A GUARD, IT IS
    A COINCIDENCE WITH THE DISPATCH ORDER.** That sentence is why the tuple this
    replaces existed; the warning now belongs to the clock, and the fix is that the
    roster is the tree's own declaration of recentness, not a list.

    Cached per (minutes, root): one walk per window per process, the same shape as
    `live_set` being called once per window.
    """
    key = (minutes, root)
    if key in _LIVE_UNIT_CACHE:
        return _LIVE_UNIT_CACHE[key]
    cutoff = time.time() - minutes * 60
    newest: dict[str, float] = {}
    slop = os.path.join(root, ".agents/slop")
    for dirpath, _d, files in os.walk(slop):
        for f in files:
            p = os.path.join(dirpath, f)
            try:
                top = os.path.relpath(p, slop).split(os.sep)[0]
                newest[top] = max(newest.get(top, 0.0), os.path.getmtime(p))
            except OSError:
                continue
    live = {top for top, mt in newest.items() if mt >= cutoff}
    _LIVE_UNIT_CACHE[key] = live
    return live


def classify(f: Facts, window: int) -> list[tuple[str, int, str]]:
    """`(verdict, size, rel)` for the whole residue at ONE window, from ONE walk.

    THE WALK IS TAKEN ONCE AND THE WINDOW APPLIED AFTERWARDS, WHICH IS THE WHOLE OF THE FIX. Reading
    the tree separately per window measures the tree AND THE CLOCK, so the two are confounded and
    neither number is checkable; freezing the population makes the window the only thing that moves.
    """
    live = live_set(window, f.root)
    live_dirs = live_units(window, f.root)
    out = []
    for rel, sz in f.files:
        v = verdict_for(rel, f.mentioned, f, live_dirs)
        if rel in live and v not in ("PROTECTED", "LIVE-UNIT"):
            v = "LIVE"
        out.append((v, sz, rel))
    return out


def verdict_for(rel: str, mentioned: set[str], f: Facts | None = None,
                live_dirs: set[str] | None = None) -> str:
    """The one classification. `f` defaults to the once-per-process measurements, so a caller that
    only has a `mentioned` set -- `checks/residue.py` has exactly that -- still gets them.

    RETURNS A TAGGED VERDICT: a bucket name, or `UNKNOWN:<the cheapest test that would resolve it>`.
    """
    f = f if f is not None else facts()
    live_dirs = live_dirs if live_dirs is not None else live_units(60, f.root)
    name = os.path.basename(rel)
    parts = rel.split(os.sep)
    top = parts[2] if len(parts) > 2 else ""

    # A role directory decides for its whole subtree, before any per-file judgement.
    for part in parts:
        if part in ROLE_DIRS:
            return ROLE_DIRS[part]
    if PROTECTED.search(rel):
        return "PROTECTED"
    # A live unit's own directory, discovered by mtime, NOT by name. The per-file
    # window catches files; this catches the DIRECTORY a unit is about to write into.
    # `live_units` is the lower bound -- a dispatched-but-not-yet-written unit is
    # invisible, and the contract says so there, not here.
    if top in live_dirs and rel.startswith(".agents/slop" + os.sep):
        return "LIVE-UNIT"
    if top in PROTECTED_DIRS:
        return "PROTECTED"
    # A DIRECTORY GIT CANNOT RESTORE, THAT SOMETHING READS, IS NOT JUNK. This is the bucket the
    # residue could never reach: `verdict_for` asks whether a name is AUTHORED, CITED or NAMED, and
    # `runs/graphcmp/D`'s 241 files are named by a GENERATOR (`checks/differ.py:42`) that no
    # committed text mentions, so they fell through to the `return "DELETE"` at the bottom. The
    # predicate is DERIVED -- see `generated_read_dirs` -- so adding a thirteenth reader changes
    # this verdict with no edit here.
    for d in generated_read_dirs(f.root):
        if rel.startswith(d + "/"):
            return "GENERATED"
    if name.endswith(".md"):
        return "DOC"
    if name in DIFFER:
        return "GATE"
    # A NAMING AUTHORITY RENDERS THIS NAME, so it is an output contract between two drivers and not a
    # file somebody made once. MEASURED 2026-10-06: `differ.declared()` renders 136 of the rows this
    # classifier used to call DELETE -- **100% of `runs/graphcmp/D` and 100% of `.agents/slop/spine/art-a`
    # -- and the literal-token citation corpus sees ONE of those basenames.** The corpus indexes
    # literal tokens; this project BUILDS its names. So `DELETE` was measuring "referenced by no
    # literal" and publishing it as "junk". One import, one call, and it is the whole of that group.
    if name in f.declared:
        return "AUTHORED"
    # THE CITATION, AND THE TWO BELTS MUST AGREE BEFORE IT DECIDES ANYTHING. They index the SAME
    # population and share no pattern, so a disagreement is a fact about the TOKENIZER and not about
    # the tree -- which is exactly the failure this project has already paid for once, in a belt that
    # missed a stop its sibling stopped on because the two shared the regex's assumption.
    belt_a, belt_b = f.cites[0].get(name, set()), f.cites[1].get(name, set())
    if belt_a ^ belt_b:
        only_a, only_b = sorted(belt_a - belt_b), sorted(belt_b - belt_a)
        # `mentioned_filenames`'s pattern both TRUNCATES a name whose last segment is followed by a
        # hyphen (`ops.staged-blob-24323` -> `ops.staged-blob`) and INVENTS a citation out of a glob
        # (`mm-*-gate.sh` -> `gate.sh`), so the two halves of this sentence are usually about the
        # REGEX being wrong. Which half is right is not a question a sweep may answer.
        return f"{UNKNOWN}:belts-disagree (the token regex sees {only_a[:1]}, " \
               f"the path scanner sees {only_b[:1]})"
    # ---- G8, AND THE MEASUREMENT THAT SAYS IT IS SUBSUMED BY THE CORPUS FILTER. ----
    # A CITATION IS NOT A LINE OF TEXT. IT IS A LINE OF TEXT PLUS THE AUTHORITY OF WHOSE TEXT IT IS,
    # and `in_residue` answers WHERE a citer lives and never WHETHER IT IS AN AUTHORITY. The residue's
    # own report is the proof the question is real: 40 `UNNAMED` rows became `CITED` the moment the
    # report that NAMES every row was committed.
    #
    # **SO THE DISCRIMINATOR WAS WRITTEN, AND IT DECIDES 0 ROWS, AND ITS DISARM DOES NOT MOVE THE
    # NUMBER.** "Is the citer itself a byte-copy of a file outside the residue?" is the right question
    # and it is also a question `committed_files` has ALREADY ANSWERED FOR EVERY CORPUS MEMBER, so no
    # copy is ever a citer and the case never arises. Before the corpus was filtered the class held
    # **79 rows**; after, **0**, and emptying the twin map G8 would have read changes it back to **0**.
    # **A DISCRIMINATOR WHOSE ANSWER IS ALREADY GIVEN IS NOT A CLAUSE, IT IS A RESTATEMENT** -- so the
    # rule that actually did the work is the corpus filter below, whose measured delta is **190 rows
    # that stop being DELETE and 0 that become DELETE**. Writing G8 here as well would be a second
    # answer to a settled question, and two answers to one question is how `LIVE_UNITS` happened.
    if belt_b and not {c for c in belt_b if not in_residue(c)}:
        return f"{UNKNOWN}:residue-internal-citer (named only from inside the residue by {sorted(belt_b)[0]})"

    # ORACLE IS NOT A WORD SHAPE. MEASURED 2026-10-05: this test was `ORACLE_WORD.search(name)` and
    # nothing else, so **670 of 675 ORACLE files were classified by their FILENAME and were named by NO
    # GATE AT ALL** — `gatecensus/` 167, `arith/` 51, `denom/` 50, `hermetic/` 49, `hdrbase/` 33, `eq/`
    # 32, `name-census-lanes/` 31: **finished units' row dumps that matched `rows|oracle|pins|baseline`
    # in a basename.** Only **5** are named by a live `checks/*.py` or `gates/*.py`.
    #
    # THIS IS THE SAME DEFECT AS `LIVE_UNITS`, ONE LEVEL UP, AND THE FILE ALREADY DIAGNOSED IT:
    # "the verdict is computed per FILE from its BASENAME — and a file called `blob-bn.txt` inside a
    # directory called `oracles` looks like a row dump. **THE ROLE IS A PROPERTY OF THE DIRECTORY AND
    # WAS BEING READ FROM THE FILE.**" `ROLE_DIRS` fixed it for four directory NAMES; the word shape
    # reintroduced it for every basename. **A FILE THAT NOBODY NAMES IS NOT REFERENCE DATA.**
    if name in mentioned and ORACLE_WORD.search(name) and not name.endswith((".sh", ".py")):
        return "ORACLE"
    # A FILE A COMMITTED REPORT NAMES IS **NEVER** DELETE. MEASURED 2026-10-05: the first sweep
    # deleted 3,603 files and `checks/repro-paths.py` went from 24 dangling reproduction paths to
    # **166** — because the GATE rule required a gate-shaped NAME *and* a citation, and everything
    # else fell through to DELETE. So a `.bend` fixture named by a report, and a `.py` an oracle
    # script needed, were both deletable while a report still pointed at them.
    #
    # **THE CITATION IS A LOWER BOUND ON VALUE, NOT A SUFFICIENT CONDITION FOR KEEPING.**
    # Naming something proves SOMEBODY DEPENDS ON IT; the name only decides which bucket.
    if name in mentioned:
        return "KEEP-CITED"
    # ---- THE FALLTHROUGH IS A DECISION NOW, NOT A DEFAULT. ----
    # Everything above declined, which used to mean DELETE. It no longer does: `DELETE` is a claim
    # about the row, and these are the two claims this classifier cannot make.
    if rel not in f.tracked:
        return (f"{UNKNOWN}:commit-or-drop (untracked, and nothing renders or names it; git could not"
                " restore it if this pass were wrong)")
    if os.path.splitext(name)[1] in TOOL_EXT and not witness_committed(rel, f.tracked, f.root):
        return (f"{UNKNOWN}:commit-the-report-that-explains-it (a TOOL, and its own directory has no"
                " committed report; nobody can say whose it is or what it was for)")
    return "DELETE"


def bucket(verdict: str) -> str:
    """The bucket a tagged verdict belongs to: `UNKNOWN:belts-disagree` is an `UNKNOWN`."""
    return verdict.partition(":")[0]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plan", action="store_true", help="classify and print; touch nothing")
    ap.add_argument("--apply", nargs="*", default=None,
                    help="verdicts to ACT on: DOC GATE ORACLE DELETE. "
                         "AUTHORED, UNKNOWN and the escapes are kept, never acted on")
    ap.add_argument("--live-minutes", type=int, default=60)
    ap.add_argument("--windows", default="0,60,1440",
                    help="comma-separated liveness windows to report SIDE BY SIDE, each from ONE "
                         "frozen walk. The default is the three that answer 'is this number a "
                         "property of the tree or of the clock?'")
    ap.add_argument("--yes", action="store_true", help="required for DELETE")
    args = ap.parse_args()

    if UNKNOWN in (args.apply or ()):
        print(f"refusing to --apply {UNKNOWN}. It is a record of not-sure, and naming it is the mistake: "
              "the\ncheapest test that would resolve each row travels with it, in `--plan`.",
              file=sys.stderr)
        return 3

    f = facts()
    # THE WINDOWS ARE A LIST, NOT A SCALAR, AND THE DEFAULT IS THE THREE THAT ANSWER THE QUESTION.
    # ONE NUMBER AT ONE WINDOW IS A STATEMENT ABOUT WHEN YOU LOOKED. MEASURED on one frozen
    # population of 2,748 rows: `DELETE` reads 748 / 671 / 0 at 0, 60 and 1440 minutes. Publishing
    # any ONE of those as "the" count is choosing a flattering hour.
    windows = sorted({int(x) for x in args.windows.split(",")} | {args.live_minutes})
    tables = {w: classify(f, w) for w in windows}
    mentioned = f.mentioned
    rows = [(v, sz, rel, rel not in live_set(0, f.root)) for v, sz, rel in tables[args.live_minutes]]

    counts, sizes = collections.Counter(), collections.Counter()
    for v, sz, _r, _c in rows:
        counts[bucket(v)] += 1
        sizes[bucket(v)] += sz

    total_n, total_b = len(rows), sum(sizes.values())
    print(f"# sweep: {total_n} files, {total_b/1048576:.0f} MB, "
          f"live-window {args.live_minutes}m, {len(mentioned)} filenames mentioned in {f.chars} chars")
    n_dirty, n_dirty_b = f.dirty_corpus()
    n_slop = sum(1 for n in f.corpus_names if n.startswith(".agents/slop/"))
    print(f"# corpus: {len(f.corpus_names)} committed files ({n_slop} of them .agents/slop reports at "
          f"ANY depth),\n#   {n_dirty} DIRTY in the worktree: {n_dirty_b/1024:.0f} KB read at HEAD "
          f"instead of from disk -- an uncommitted report cites nothing")
    conflicts = self_output_conflicts(ROOT)
    print(f"# out of census: {', '.join(self_output_dirs(ROOT)) or 'NONE FOUND'} + {SELF} "
          f"(write-targets, discovered) + {len(f.copies)} byte-copies + residue.EXCLUDED_DIRS\n"
          f"#   (a MENTION is not an output; a DEPTH is not a shadow tree; a COPY is excluded by a proof)")
    print(f"# own output excluded from the corpus: {', '.join(self_output_dirs(ROOT)) or 'NONE FOUND'}"
          f" + {SELF}  (write-targets, discovered; a MENTION is not an output)")
    # **A REFUSAL, PRINTED, BECAUSE A SILENT REFUSAL IS INDISTINGUISHABLE FROM A MISS.** These
    # directories ARE written by a live instrument and are NOT excluded, because a live
    # instrument also READS them -- `.agents/slop/oracletxt` holds the plant generator
    # `checks/oracle-txt-census.py:215` loads BY PATH, and excluding it would re-break that gate
    # by the route `self_output_dirs`'s own docstring warns about. MEASURED 2026-10-14 13:20Z:
    # 2 of the 3 write targets are in this list.
    print(f"# REFUSED as out-of-census, written AND read by a live instrument: "
          f"{', '.join(conflicts) or 'NONE'}"
          f"  (an exclusion must be an OUTPUT and not also an INPUT)")
    for v in ("DOC", "GATE", "ORACLE", "AUTHORED", "DELETE", "UNKNOWN",
              "LIVE", "LIVE-UNIT", "PROTECTED"):
        if counts[v]:
            share = sizes[v] / total_b * 100 if total_b else 0
            print(f"#   {v:11s} {counts[v]:7d} files {sizes[v]/1048576:8.1f} MB  {share:5.1f}%")
    # EVERY PATH BY WHICH A ROW REACHES `UNKNOWN`, COUNTED. A not-sure published as one number is a
    # not-sure nobody can act on except in bulk, and these are five different questions.
    needs = collections.Counter(v.partition(":")[2].split(" (")[0] for v, *_ in rows
                                if v.startswith(UNKNOWN))
    for k, n in needs.most_common():
        print(f"#     needs={k:38s} {n:6d} rows")

    # ---- THE TABLE. WHICH NUMBERS ARE CONSTANT AND WHICH ARE A FUNCTION OF THE CLOCK. ----
    # Printed by DEFAULT, because the alternative is a reader taking one cell for a count. A figure
    # that is identical at 0 and 1440 minutes is a property of the TREE; one that is not is a
    # property of WHEN YOU LOOKED, and printing it without the other two columns hides that.
    buckets = ("DOC", "GATE", "ORACLE", "AUTHORED", "KEEP-CITED", "DELETE", "UNKNOWN",
               "LIVE", "LIVE-UNIT", "PROTECTED")
    per = {w: collections.Counter(bucket(v) for v, _s, _r in tables[w]) for w in windows}
    needsp = {w: collections.Counter(v.partition(":")[2].split(" (")[0] for v, *_ in tables[w]
                                    if v.startswith(UNKNOWN)) for w in windows}
    hdr = " ".join(f"{('w=' + str(w) + 'm'):>8s}" for w in windows)
    print(f"\n# THE RESIDUE AT {len(windows)} WINDOWS, ONE FROZEN POPULATION OF {total_n} ROWS")
    print(f"# {'bucket':38s}{hdr}  nature")
    for b in buckets:
        if not any(per[w][b] for w in windows):
            continue
        vals = [per[w][b] for w in windows]
        nature = "CONSTANT -- a property of the tree" if len(set(vals)) == 1 \
            else "MOVES   -- a function of the clock"
        print(f"# {b:38s}" + " ".join(f"{v:8d}" for v in vals) + f"  {nature}")
    print(f"# {'TOTAL':38s}" + " ".join(f"{len(tables[w]):8d}" for w in windows)
          + "  CONSTANT -- the walk happened once")
    print(f"# {'of which needs=:':38s}" + " ".join(f"{sum(needsp[w].values()):8d}" for w in windows)
          + "  (the classes below)")
    for k in sorted({k for w in windows for k in needsp[w]}):
        vals = [needsp[w][k] for w in windows]
        nature = "CONSTANT" if len(set(vals)) == 1 else "MOVES"
        print(f"#   needs={k:32s}" + " ".join(f"{v:8d}" for v in vals) + f"  {nature}")

    # ---- THE PORT: A POPULATION THIS WALK HAS NEVER DESCENDED INTO. ----
    # `walk_residue` walks `RESIDUE_ROOTS`, and the shipped `tinybendygrad/` tree is not one of them,
    # so every file there reaches NO verdict at all. It is REPORTED here and never acted on: the tree
    # ships, and a population a DELETE-capable pass can walk is a population it can destroy. It is
    # not in `rows`, so no `--apply` argument can reach it. **A MISSING POPULATION AND AN
    # UNCLASSIFIABLE ROW ARE THE SAME SILENCE, AND `UNKNOWN` IS WHAT BREAKS IT.**
    pb, pn, ptot = port_report(f)
    print(f"\n# THE SHIPPED PORT, REPORT-ONLY (never a bucket `--apply` can reach): "
          f"{ptot} files under tinybendygrad/")
    for b in ("DOC", "GATE", "ORACLE", "AUTHORED", "KEEP-CITED", "DELETE", "UNKNOWN"):
        if pb[b]:
            print(f"#   {b:11s} {pb[b]:6d} files")
    for k, n in pn.most_common():
        print(f"#     needs={k:38s} {n:6d} rows")

    if args.plan or not args.apply:
        keep = counts["DOC"] + counts["GATE"] + counts["ORACLE"] + counts["AUTHORED"]
        print(f"\n# KEEPING {keep} of {total_n}: "
              f"{counts['DOC']} doc + {counts['GATE']} gate + {counts['ORACLE']} oracle "
              f"+ {counts['AUTHORED']} authored")
        print(f"# REPORTING AND NOT ACTING ON {counts['UNKNOWN']} rows: a test could not be run for them")
        cold_n = sum(1 for v, _s, _r, c in rows if v == "DELETE" and c)
        cold_b = sum(s for v, s, _r, c in rows if v == "DELETE" and c)
        print(f"# DELETING {counts['DELETE']} files, {sizes['DELETE']/1048576:.0f} MB"
              + (f" -- of which {cold_n}, {cold_b/1048576:.0f} MB, with the liveness window OFF"
                 if cold_n != counts["DELETE"] else ""))
        if counts["DELETE"] > total_n * 0.5:
            print("#   (more than half. A sweep that keeps less than it removes is not a tidy-up;\n"
                  "#    it is a decision about what this directory is FOR.)")
        big = sorted((r for r in rows if r[0] == "DELETE"), key=lambda d: -d[1])[:12]
        if big:
            print("# largest DELETEs:")
            for _v, sz, rel, _c in big:
                print(f"#     {sz/1024:9.1f} KB  {rel}")
        return 0

    if "DELETE" in args.apply and not args.yes:
        print("refusing to DELETE without --yes. A deletion pass that needs no confirmation\n"
              "is the pass where the allow-list was wrong.", file=sys.stderr)
        return 3

    moved = deleted = 0
    for v, sz, rel, _cold in rows:
        src = os.path.join(ROOT, rel)
        # `v not in args.apply` is the check whose absence broke the artifact once: the bucket a
        # caller did NOT name was acted on anyway, because the `elif` tested the VERDICT rather
        # than the REQUEST. `--apply DELETE` moved 521 files and deleted e2e's fixtures.
        if v not in (args.apply or ()):
            continue
        if v == "DELETE":
            try:
                os.remove(src)
                deleted += 1
            except OSError:
                pass
        elif v in ("GATE", "ORACLE"):
            dest_dir = CHECKS if v == "GATE" else ORACLES
            # Flat, because 200 gates in a tree is a tree nobody reads; a name collision is
            # reported rather than silently resolved.
            dest = os.path.join(dest_dir, os.path.basename(rel))
            if os.path.exists(dest):
                continue
            os.makedirs(dest_dir, exist_ok=True)
            try:
                shutil.move(src, dest)
                moved += 1
            except OSError:
                pass

    # Prune directories left empty, derived never listed.
    pruned = 0
    for base in (SLOP, RUNS):
        for dirpath, _dn, _fn in os.walk(base, topdown=False):
            try:
                os.rmdir(dirpath)
                pruned += 1
            except OSError:
                pass
    print(f"DELETED {deleted} files, MOVED {moved} into checks/+oracles/, "
          f"pruned {pruned} empty directories")
    return 0


if __name__ == "__main__":
    sys.exit(main())