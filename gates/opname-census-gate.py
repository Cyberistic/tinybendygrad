#!/usr/bin/env python3
"""opname-census-gate.py -- DOES ANY DRIVER CONSTRUCT AN `Op` THE PORT's ENUM DOES NOT DECLARE?

    .venv/bin/python gates/opname-census-gate.py            # the census, the rows, the verdict
    .venv/bin/python gates/opname-census-gate.py --plant    # the plant, the control, the wrong shapes

THE HOLE THIS FILE FILLS, AND IT IS A POPULATION HOLE.

`checks/port-compile-gate.py` compiles EVERY `.bend` under `tinybendygrad/` -- 169 files, 165 of
them compile -- and it says so on every run. **AND ITS POPULATION IS THE PORT.** `gates/`,
`oracles/`, `checks/` and `.agents/` are OUTSIDE it, so a driver that does not compile is a file
that no compile census in this tree ever looked at. MEASURED: `gates/ptx_render_census_axis.bend`
carried `O.OpsGROUP{}` -- a constructor for an op upstream DELETED in `4e0192eaf remove Ops.GROUP
(#18637)` -- and the file did not compile, and the gate that ran it was REFUSED, and nothing in
the tree said so. Seven days. The instrument that would have caught it did not exist, and the
one that existed could not see it.

⇒ **SO THE POPULATION IS THE TREE's DRIVERS: EVERY `.bend` THAT IS NOT IN THE PORT.**

THE POPULATION IS DISCOVERED, NOT LISTED.  It is `checks/compile-census.py`'s own `discover()`,
LOADED BY PATH: an `os.walk(".")` over the repo, minus the subtree `checks/substrate.py`
declares (`POP_ROOT`, the port), minus that file's own `SKIP_DIRS` -- each of which carries its
REASON, and the census PRINTS the subtraction rather than asserting it. `AGENTS.md` doctrine 1:
"A population is (a) a GENERATOR'S OWN DECLARATION, LOADED BY PATH ... (b) a DIRECTORY WALK ...
A BASENAME SHAPE, A SUFFIX SET, AND A HAND LIST ARE NOT POPULATIONS." This is (a) and (b) at
once, and it is the same declaration the tree's own compile census uses, so the two cannot
disagree about what a driver is.

THE ENUM IS THE PORT's OWN DECLARATION, AND IT IS READ BY THE TREE's OWN PARSER.
`gates/opseven-gate.py`'s `_declared_ops()` reads `tinybendygrad/uop/ops.bend`'s `type Op is
Data:` block, and its `_upstream_ops()` reads upstream's `Ops` -- BOTH LOADED BY PATH, because
both of those parsers are where this tree's three hard-won facts about the enum live, and a
second copy of either would rot alone:

  * UPSTREAM's `Ops` ENUM LIVES IN `tinygrad/uop/__init__.py`, NOT IN `ops.py`. A grep of
    `ops.py` finds no `class Ops` AT ALL.
  * UPSTREAM WRITES SEVERAL MEMBERS PER LINE (`BUFFER = auto(); ALLOC = auto()`), so a regex
    that takes only the FIRST per line UNDERCOUNTS BY HALF -- 75 comes out as 30 without the
    fix, and the gate that read it that way reported 45 deleted members and REFUSED.
  * THE PORT's ENUM IS EXACTLY UPSTREAM's AT THE PIN: 75 and 75, 0 missing, 0 extra. The
    census PRINTS that comparison on every run, so a re-vendor that moves it says so here
    instead of in a sentence somewhere else.

THE CLASSIFICATION IS BY CODE, NOT BY TEXT, AND THAT IS THE CORRECTION THIS FILE EXISTS TO MAKE.
A text census OVERSTATES, and the three cases it overstated are the three this file resolves:

  OpsGROUP   a REAL COMPILE ERROR -- a constructor in code for an op the enum does not declare.
  OpsFLIP    a LATENT STALE REFERENCE IN A FRAGMENT -- the file's own STANDING CONDITION is
             `expected : 'def', 'type' or 'law'` (bare statements at top level), NOT `OpsFLIP`.
  OpsX       a PLACEHOLDER IN A COMMENT -- the file COMPILES.

⇒ **A CENSUS THAT NAMES A BROKEN DRIVER WITHOUT SAYING WHETHER IT IS BROKEN IS A CENSUS OF
NAMES.** So every candidate here is COMPILED, and the verdict is the compiler's.

THE THREE CLASSES, AND THEY ARE THE COMPILER'S VERDICT AND NOT A LIST OF FILENAMES:

  COMPILE-FINDING       the compiler's own error NAMES the candidate. THE FILE IS BROKEN BY IT.
  COMPILE-LATENT-STALE  the compiler does not blame the candidate. The file either COMPILES
                        (so the name does not break it today, and it is ONE RE-VENDOR away from
                        breaking it) or the file's OWN STANDING CONDITION masks it (the FRAGMENT
                        case). Either way the name is REAL and no compile check in the tree can
                        see it.
  COMPILE-NONE          the candidate is a PLACEHOLDER -- a name where a construction belongs,
                        in a spot the compiler does not read. NOT A FINDING, and reported anyway
                        so the class is visible.

⇒ THE PLACEHOLDER IS NOT A FINDING, and the tree says why in its own words: "A NAME IN A
COMMENT IS NOT A CONSTRUCTION". The instance is PRESENT in this tree and the census PROVES it
on every run: it prints the RAW-TEXT mention count and the CODE mention count, and the
difference between them IS the proof -- `gates/tn_binop_sweep.bend` mentions `O.OpsX{}` in a
COMMENT today, and a text census counts it as a construction.

⇒ AND THE CENSUS MUST NOT FIRE ON THE PORT's OWN STATE RECORDS. Its candidate shape is
`Ops`-PREFIXED AND A CONSTRUCTION, so an accessor-fed record cell -- `runtime/ops_dsp.bend`'s
`Tr.refused(...)` cells, which are CALLS to a def in the same file and not constructions of an
`Op` -- is not a candidate, and `Tr` is not a member of the `Op` enum either. MEASURED, in
`--selftest`, which scans that file and prints the count.

THE COUNT IS A LOWER BOUND, AND THE INSTRUMENT SAYS SO.  "A PARSER THAT COUNTS FEWER IS A
PARSER THAT UNDERSTATES. THE INSTRUMENT IS A LOWER BOUND AND SAYS SO." The ways this census can
undercount, named:
  * a stale op in a PYTHON oracle (`.py`) is invisible -- this census reads `.bend`;
  * a stale op in the PORT is invisible HERE -- `checks/port-compile-gate.py` owns that
    population and would report it as a compile FINDING;
  * a mention in PROSE is invisible, and that is the POINT (see `OpsX` above);
  * a masked candidate gets no PER-SITE attribution, because the compiler never reached the
    site that would carry it.

THE PLANT IS A TEXT EDIT ON THE WORKING TREE, NEVER `git show HEAD:`. A plant that reads HEAD
plants nothing the moment HEAD carries the fix. The subject is `gates/opname-census-plantcase.bend`,
a file this gate OWNS -- a subject another unit owns is a shared path, and `AGENTS.md` records
what happens to shared paths. The plant edits a COPY under a scratch name, the census
discovers the copy by its own walk, and the copy is deleted when the run ends.

⇒ **AND THIS CENSUS IS NOW A GATE THE EDGE RUNS, AND ITS BLIND SPOT IS DECLARED RATHER THAN
CLOSED HERE.** Two things changed on 2026-10-22 and both are MEASURED:

  * **IT WAS UNREACHABLE.** MEASURED: `gates/opname-census-gate.py` was in neither
    `gates/edge-cost.rows` nor `gates/edge-trace.rows`, so the edge never ran it -- and a census
    nobody runs is a census whose verdict nobody reads. That is the SAME defect
    `checks/compile-census.py` had: its artefact said `COLD ... gates/crp_graph_census.bend` for
    a day and a half and NOBODY WAS TOLD. So this file declares `EDGE_CANDIDATE = True`, which is
    the tree's own hook (`gates/edge-oracle-pin-gate.py` uses it too) and which the edge reads BY
    PATH, the way it reads a gate's `RED_IS`.
  * **ITS BLIND SPOT IS THE COMPILE CENSUS's POPULATION, NOT A DEFECT IN THIS FILE.** This census
    compiles ONLY the files that NAME a stale op, so a driver that fails for a TYPE ERROR is never
    compiled by it. **THE COMPILE CENSUS SEES EVERYTHING; THIS ONE SEES THE CLASS.** The run
    prints the complement -- `compiled=` and `not-compiled=` with the population as the
    denominator -- and names the sibling that covers the rest:
    `checks/compile-census.py`, whose verdict the edge runs as `gates/compile-census-gate.py`.
    **DO NOT MERGE THEM AND DO NOT GROW EITHER'S POPULATION HERE**: two instruments with different
    populations and different questions are RIGHT, and a second copy of either is not.
"""
from __future__ import annotations

import importlib.util
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
ROWS = HERE / "opname-census.rows"
SUBJECT = HERE / "opname-census-plantcase.bend"
MB, SECONDS = 2048, 300

# THE EDGE'S HOOK, DECLARED HERE AND READ BY THE EDGE. This census holds no pin of its own -- it
# compares a NAME against the port's own enum -- so the edge's selection rule ("a member that
# holds a pin its own code reads") would not see it, and a census the edge never runs is a census
# whose verdict nobody reads. **THAT IS THE SAME DEFECT `checks/compile-census.py` HAD**:
# MEASURED 2026-10-22, its rows said `COLD ... gates/crp_graph_census.bend` for a day and a half
# and NOBODY WAS TOLD, because nothing ran it and nothing read its artefact. The tree's own escape
# is used by `gates/edge-oracle-pin-gate.py` and by `gates/compile-census-gate.py`, and it is read
# BY PATH, the same way the edge reads a gate's `RED_IS`.
EDGE_CANDIDATE = True


def _load(rel: str, name: str):
    """A MODULE, LOADED BY PATH. Never imported by name and never re-typed."""
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# THE HOUSE INSTRUMENTS, BY PATH. `pc` owns the compile verdict and the comment stripper;
# `cc` owns the population; `og` owns the two enum parsers.
pc = _load("checks/port-compile-gate.py", "port_compile")
cc = _load("checks/compile-census.py", "compile_census")
og = _load("gates/opseven-gate.py", "opseven_gate")
sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED  # noqa: E402
from bendlock import bend_lock  # noqa: E402

# THE THREE SHAPES A MENTION CAN HAVE, AND ONLY ONE OF THEM IS A CANDIDATE.
#   CONSTRUCTION  `OpsNAME{` -- a constructor application. THIS IS THE FINDING SHAPE.
#   ACCESSOR      `OpsNAME(` -- a CALL to something named like an op. Not a construction, and
#                 it is here so the census can SAY it saw one and did not count it.
#   BARE          `OpsNAME`  -- a NAME with neither. The PLACEHOLDER shape.
# THE PREFIX IS PART OF THE SHAPE, and that is the negative control: `runtime/ops_dsp.bend`'s
# accessor-fed `Tr.refused(...)` cells are calls to a def of ANOTHER type, and `Tr` is not an
# `Op` member, so no shape here can reach them.
CONSTRUCTION = re.compile(r"\bOps([A-Z0-9_]+)\s*\{")
ACCESSOR = re.compile(r"\bOps([A-Z0-9_]+)\s*\(")
BARE = re.compile(r"\bOps([A-Z0-9_]+)\b(?!\s*[({])")

# THE COMPILER'S OWN VERDICT ABOUT WHICH CONSTRUCTOR IT REFUSED. Two shapes, MEASURED:
#   `- expected : a declared constructor (../tinybendygrad/uop/ops.Op declares ...)` with
#     `- observed : O.OpsGROUP{}` -- the ARGUMENT form;
#   `- message  : a declared constructor (unknown: ../tinybendygrad/uop/ops.OpsGROUP)` -- the
#     MATCH-ARM form, which has no `observed :` line at all.
# The name is read as a WHOLE (`\b`), not as a substring: `OpsAD` is a substring of the
# declared `OpsADD`, and a substring test would blame the wrong candidate.
BLAMED = re.compile(r"unknown:\s*[^\n]*?\.Ops([A-Z0-9_]+)\b|observed\s*:\s*[^\n]*?\bOps([A-Z0-9_]+)\b")

# A FRAGMENT'S OWN STANDING CONDITION: bare statements at top level, where a `def`, a `type`
# or a `law` belongs. It is the COMPILER's wording, so a fragment is a class the compiler
# names and not a list of file names.
FRAGMENT = re.compile(r"expected\s*:\s*'def',\s*'type'\s*or\s*'law'")

FINDING, LATENT, NONE = "COMPILE-FINDING", "COMPILE-LATENT-STALE", "COMPILE-NONE"


# --------------------------------------------------------------------------- the compile verdict
def _run(path: str) -> tuple[str, str, str]:
    """ONE compiler invocation. Returns `(state, detail, stderr)`.

    THE ENVELOPE IS `checks/port-compile-gate.py`'s -- `checks/bounded.py` under
    `gates/bendlock.py` -- and the CLASSIFIER is its `verdict_of()`, imported BY PATH, so the
    two cannot drift on what a verdict MEANS. What is re-typed here is the SUBPROCESS CALL,
    because `pc.judge()` returns the state and not the STREAMS, and the attribution needs the
    compiler's own error TEXT. `selfcheck()` below compares this function's state against
    `pc.judge()`'s on a real file, ON EVERY RUN, so the re-typed envelope cannot drift
    silently -- a copy that is asserted against its original is a copy that is CHECKED.
    """
    with bend_lock():
        p = subprocess.run([pc.PY, pc.BOUNDED, "--mb", str(MB), "--seconds", str(SECONDS),
                            "--", str(pc.BEND), path, "--check-only"],
                           cwd=ROOT, capture_output=True, text=True,
                           env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"})
    tok = pc.TOKEN.search(p.stderr)
    token = tok.group("token") if tok else "NO-TOKEN"
    if token != "WITHIN-LIMITS":
        return pc.NOM, f"the bounded token was {token}", p.stderr
    state, detail = pc.verdict_of(p.stdout, p.stderr)
    return state, detail, p.stderr


def compile_verdict(path: str) -> tuple[str, str, str]:
    """`(state, detail, stderr)` for one file, on the house's TWO LANES.

    `--check-only` answers a SAFETY question as well as a typing one: it refuses a file whose
    defs rely on unsafe or foreign code, and that refusal is a fact about the PROMISE and not
    about whether the file parses. So the second lane -- does the compiler still EMIT C for
    it -- is asked of exactly those files, by `pc.emits_c()`, imported BY PATH.
    """
    state, detail, stderr = _run(path)
    if state in (pc.ST_INCOMPLETE, pc.ST_FOREIGN):
        em = pc.emits_c(path, MB, SECONDS)
        state = pc.AS_C if em == "YES" else pc.COLD
        detail = f"{detail} -- the emit lane said {em}"
    return state, detail, stderr


def compile_verdict_str(text: str) -> tuple[str, str, str]:
    """`compile_verdict()` for a TEXT rather than for a file on disk.

    The text is written to a scratch file BESIDE THE SUBJECT, because a bend file's relative
    imports resolve against its OWN directory -- a scratch in the system temp dir would
    answer "no such file" and the verdict would be about the temp dir.
    """
    scratch = HERE / "_opname_shapecase.bend"
    scratch.write_text(text)
    try:
        return compile_verdict(str(scratch))
    finally:
        scratch.unlink(missing_ok=True)


def selfcheck(path: str) -> tuple[bool, str]:
    """THIS FILE's envelope AND `pc.judge()`'s, ON THE SAME FILE. They must AGREE.

    A census that compiles through a copy of somebody else's envelope is a census whose
    verdict could be an artefact of the copy. So the copy is CHECKED, on every run, against
    the instrument it copies -- and the subject is DISCOVERED (the first file of the
    population), not named here.
    """
    mine, _, _ = _run(path)
    theirs, _, _ = pc.judge(path, MB, SECONDS)
    return mine == theirs, f"mine={mine} theirs={theirs}"


# --------------------------------------------------------------------------- the scanner
def code_of(path: Path) -> str:
    """The file's CODE: every comment removed, by the house stripper, imported BY PATH.

    `checks/port-compile-gate.py`'s `strip_comments()` knows that a `#` inside a string is
    not a comment, and it blanks the string literals before it strips -- so a mention in a
    string is invisible too, and that is right: a mention in a string is not a construction
    either.
    """
    return pc.strip_comments(path.read_text())


def mentions(text: str) -> tuple[set[str], set[str], set[str]]:
    """`(constructions, accessors, bare names)` in one text. A name can be in more than one."""
    return set(CONSTRUCTION.findall(text)), set(ACCESSOR.findall(text)), set(BARE.findall(text))


def comment_only_sites(raw: str, stripped: str) -> list[tuple[int, str]]:
    """THE SITES A TEXT CENSUS WOULD COUNT AND A CODE CENSUS MUST NOT: `(line, name)`.

    `strip_comments()` keeps the line COUNT and the column positions of everything before the
    comment, so the RAW line and the STRIPPED line can be compared line for line: a
    construction in the raw line and not in the stripped one is a mention in a COMMENT (or in
    a string), and it is NOT a construction.

    ⇒ **THIS IS THE OVERSTATEMENT, SITE BY SITE.** A text census counts these; a code census
    must not. The instance is PRESENT in this tree today and the census prints it on every
    run, so the claim is a measurement and not a story.
    """
    out = []
    for i, (a, b) in enumerate(zip(raw.split("\n"), stripped.split("\n")), 1):
        gone = set(CONSTRUCTION.findall(a)) - set(CONSTRUCTION.findall(b))
        out += [(i, f"Ops{n}") for n in sorted(gone)]
    return out


def code_only(text: str) -> str:
    """The text with every comment removed AND every blank line DROPPED.

    THE BLANK-LINE DROP IS THE FIX, AND IT IS COPIED FROM
    `gates/ptx_render_census-gate.py`'s `_code_only()`, WHICH WAS FIXED FOR EXACTLY THIS
    REASON. A comment on its own line contributes a line that is EMPTY once the comment is
    gone, and comparing LINE LISTS would call that "not comment-only" -- which is the most
    comment-only edit there is. Measured three times independently in this tree: a comment
    APPENDED to a line carrying two statements DELETES the second (and the file may still
    COMPILE -- only this proof catches it), and a whole-line comment AT COLUMN 0 does not
    break a bend file.
    """
    return "\n".join(l for l in pc.strip_comments(text).split("\n") if l.strip())


def negative_control() -> tuple[bool, str]:
    """THE NEGATIVE CONTROL, MEASURED ON EVERY RUN. `runtime/ops_dsp.bend`'s `Tr.refused` cells.

    Returns `(ok, why)`. `ok` is TRUE when the control did NOT fire, i.e. when the scanner
    produced no candidate for that file -- which is the shape it must have.

    They are ACCESSOR-FED -- calls to a def in the same file -- and they are not constructions
    of an `Op`, and `Tr` is not a member of the `Op` enum. So the scanner must produce ZERO
    candidates for that file. A scanner whose shape was "a name followed by `(`" would have
    found them, and the class it would have found them in is a fixture-embedded record cell
    rather than an op. THE PREFIX IS WHAT EXCLUDES THEM: every shape here is `Ops`-PREFIXED.

    IT RUNS ON EVERY RUN AND NOT IN A MODE NOBODY CALLS, because a negative control that is
    only reachable by hand is a control that is not running.
    """
    path = ROOT / "tinybendygrad" / "runtime" / "ops_dsp.bend"
    if not path.is_file():
        return False, f"{path.relative_to(ROOT)} is absent, so the negative control cannot run"
    code = code_of(path)
    ctor, acc, bare = mentions(code)
    defs = len(re.findall(r"\bdef Tr\.refused\(", code))
    calls = len(re.findall(r"\bTr\.refused\(", code)) - defs
    why = (f"{path.relative_to(ROOT)}: constructions={len(ctor)} accessors={len(acc)} bare="
           f"{len(bare)}  ::  `Tr.refused` is DEFINED {defs} time(s) and CALLED {calls} time(s), "
           "and it is a def of ANOTHER type, so no `Ops`-prefixed shape can reach it")
    return not (ctor or acc or bare), why


# --------------------------------------------------------------------------- the census
def census(rows_path: Path | None = None) -> tuple[int, list[dict], list[tuple[str, int, str]]]:
    """THE CENSUS. Returns `(verdict, rows, comment_only)`.

    THE VERDICT IS ABOUT THE POPULATION, NOT ABOUT THE ROWS. A file with no candidate is not
    a row here -- there is nothing to say about it -- and the DENOMINATOR is printed so a
    reader can see how many files were read and how many of them named anything stale.
    """
    pop, dropped = cc.discover()
    if not pop:
        print("REFUSED: the walk found no .bend outside the port, so this run read nothing and "
              "must not report agreement")
        return REFUSED, [], []

    declared = set(og._declared_ops())
    upstream = set(og._upstream_ops())
    print(f"POPULATION  .bend handed={len(pop)}  ::  `checks/compile-census.py`'s `discover()`, "
          f"LOADED BY PATH: os.walk('.') minus substrate.py POP_ROOT={cc.substrate.POP_ROOT}/")
    for reason, n in dropped:
        print(f"EXCLUDED    {n:5d}  ::  {reason}")
    print(f"ENUM        port={len(declared)} upstream={len(upstream)} "
          f"missing-from-port={len(upstream - declared)} extra-in-port={len(declared - upstream)}"
          f"  ::  `gates/opseven-gate.py`'s `_declared_ops()` and `_upstream_ops()`, BY PATH")

    rows: list[dict] = []
    raw_stale = code_stale = 0
    comment_only: list[tuple[str, int, str]] = []
    compiled = 0
    for rel in pop:
        path = ROOT / rel
        try:
            raw = path.read_text()
        except OSError as e:
            print(f"REFUSED    {rel}: {e}")
            return REFUSED, rows, comment_only
        raw_ctor, _, _ = mentions(raw)
        code = code_of(path)
        ctor, acc, bare = mentions(code)
        raw_stale += len({n for n in raw_ctor if n not in declared})
        code_stale += len({n for n in ctor if n not in declared})
        for line, name in comment_only_sites(raw, code):
            if name[len("Ops"):] not in declared:
                comment_only.append((rel, line, name))
        unknown = {n for n in ctor | acc | bare if n not in declared}
        if not unknown:
            continue
        compiled += 1
        state, detail, stderr = compile_verdict(rel)
        if state == pc.NOM:
            print(f"REFUSED    {rel}: the compile produced no verdict ({detail}), so this census "
                  "cannot say anything about the candidates in it")
            return REFUSED, rows, comment_only
        blamed = {a or b for a, b in BLAMED.findall(stderr)}
        standing = "FRAGMENT" if FRAGMENT.search(stderr) else state
        for name in sorted(unknown):
            if name in blamed:
                klass = FINDING
            elif name not in ctor:
                klass = NONE
            else:
                klass = LATENT
            rows.append({"class": klass, "file": rel, "name": f"Ops{name}",
                         "shape": ("CONSTRUCTION" if name in ctor
                                   else "ACCESSOR" if name in acc else "NAME"),
                         "compiles": "yes" if state in (pc.COMPILES, pc.AS_C) else "no",
                         "standing": standing, "detail": detail[:160]})

    print(f"SCAN        raw-text stale constructions={raw_stale}  code stale constructions="
          f"{code_stale}  ::  the difference is the OVERSTATEMENT a text census makes, and the "
          "sites are named below.")
    for rel, line, name in comment_only:
        print(f"COMMENT-ONLY {rel}:{line}  {name}  ::  a mention in a COMMENT is not a "
              "construction -- a TEXT census would report this as a stale op")
    # THE COMPLEMENT, PRINTED WITH ITS DENOMINATOR, AND IT IS NOT A DEFECT TO BE FIXED HERE.
    #
    # **THIS CENSUS COMPILES ONLY THE FILES THAT NAME A STALE OP** (`if not unknown: continue`),
    # so a driver that fails for a TYPE ERROR is never compiled by it. **THAT IS THIS
    # INSTRUMENT'S POPULATION AND NOT A BLIND SPOT TO BE CLOSED HERE**: the class it does not
    # see is covered by `checks/compile-census.py`, which compiles EVERY `.bend` outside the port
    # and whose verdict the edge now runs as `gates/compile-census-gate.py`. **THE COMPILE CENSUS
    # SEES EVERYTHING; THIS ONE SEES THE CLASS.** Two instruments with different populations and
    # different questions are RIGHT, and a SECOND COPY OF EITHER IS NOT -- so neither of them
    # grows the other's population here.
    print(f"COMPLEMENT  compiled={compiled}  not-compiled={len(pop) - compiled} of {len(pop)}  ::  "
          "this census compiles ONLY the files that NAME a stale op, so a driver that fails for a "
          "TYPE ERROR is never compiled by it. That class is covered by "
          "`checks/compile-census.py`, which compiles EVERY driver, and whose verdict the edge runs "
          "as `gates/compile-census-gate.py`. TWO INSTRUMENTS, DIFFERENT POPULATIONS, DIFFERENT "
          "QUESTIONS -- AND A SECOND COPY OF EITHER IS NOT.")
    tally: dict[str, int] = {}
    for r in rows:
        tally[r["class"]] = tally.get(r["class"], 0) + 1
    print(f"CANDIDATES  files={len({r['file'] for r in rows})} names={len(rows)}")
    for k in (FINDING, LATENT, NONE):
        print(f"CENSUS      {k}={tally.get(k, 0)}")

    ok, why = selfcheck(pop[0])
    print(f"SELF-CHECK  envelope agrees with checks/port-compile-gate.py's judge(): {ok!s:<5} "
          f"({why}) on {pop[0]}")
    if not ok:
        return REFUSED, rows, comment_only
    neg, why = negative_control()
    print(f"NEGATIVE    the control fired={not neg!s:<5} :: {why}")
    if not neg:
        print("  THE NEGATIVE CONTROL FIRED: the scanner reached something that is not an op "
              "construction, so its candidate shape is wider than it claims.")
        return REFUSED, rows, comment_only

    print("LOWER BOUND the counts above are a LOWER BOUND over the stale constructions in the "
          "tree's `.bend` drivers: a stale op in a PYTHON oracle is invisible (this census reads "
          "`.bend`), a stale op in the PORT is invisible HERE (`checks/port-compile-gate.py` owns "
          "that population), a mention in PROSE is invisible (that is the point), and a masked "
          "candidate gets no per-site attribution.")

    if rows_path is not None:
        rows_path.write_text(_rows_text(rows, len(pop), tally, raw_stale, code_stale))
        print(f"ARTIFACT    {rows_path.relative_to(ROOT)}")

    for r in rows:
        print(f"{r['class']:<20} {r['file']}  {r['name']}  {r['shape']}  compiles={r['compiles']}  "
              f"standing={r['standing']}  ::  {r['detail']}")

    failed = tally.get(FINDING, 0) + tally.get(LATENT, 0)
    if failed:
        print(f"VERDICT     FAIL: {failed} candidate(s) name a constructor the port's `Op` enum "
              "does not declare")
        return FAIL, rows, comment_only
    print("VERDICT     PASS: no driver names a constructor the port's `Op` enum does not declare")
    return PASS, rows, comment_only


def _rows_text(rows: list[dict], pop_n: int, tally: dict, raw: int, code: int) -> str:
    head = [
        "# opname-census.rows -- GENERATED by `gates/opname-census-gate.py`, which is its ONLY "
        "writer.",
        "# One TAB-separated row per CANDIDATE: a name the port's `Op` enum does not declare, in "
        "a `.bend` driver.",
        f"# population={pop_n}  raw-text stale constructions={raw}  code stale constructions={code}"
        "  ::  the difference is the OVERSTATEMENT a text census makes.",
        f"# class: FINDING={tally.get(FINDING, 0)}  LATENT-STALE={tally.get(LATENT, 0)}  "
        f"NONE={tally.get(NONE, 0)}  ::  FINDING is the compiler blaming the name; LATENT-STALE is "
        "the compiler not blaming it (the file compiles, or its own standing condition masks it); "
        "NONE is a PLACEHOLDER and is not a finding.",
        "# The counts are a LOWER BOUND; the reasons are in the gate's own header.",
        "class\tfile\tname\tshape\tcompiles\tstanding\tdetail",
    ]
    body = [f"{r['class']}\t{r['file']}\t{r['name']}\t{r['shape']}\t{r['compiles']}\t"
            f"{r['standing']}\t{r['detail']}" for r in rows]
    return "\n".join(head + body) + "\n"


# --------------------------------------------------------------------------- the plant
# THE ANCHOR IS TWO LINES, AND THAT IS NOT FIDELITY FOR ITS OWN SAKE.  A ONE-LINE ANCHOR
# (`  O.OpsADD{}`) matched the fixture's own PROSE -- the header line that shows the two-part
# line in backticks -- and the plant replaced the MENTION IN THE COMMENT instead of the
# construction in the code, so it planted nothing and the census stayed green.  MEASURED, on
# the first run of this plant.  The anchor now carries the DEF it belongs to, so the only
# place it can match is the code.
PLANT_ANCHOR = "def plant_op() -> O.Op:\n  O.OpsADD{}"
PLANT_UNKNOWN = "def plant_op() -> O.Op:\n  O.OpsGROUP{}"
# THE FRAGMENT'S SUBJECT, AND IT IS THE GATE's OWN: `gates/opname-census-fragment.bend` is bare
# statements at top level, so the compiler refuses it at its first statement with `expected :
# 'def', 'type' or 'law'` -- its OWN STANDING CONDITION -- and that refusal is exactly what
# MASKS a stale name in it.  A REAL fragment with this shape is `oracles/lift-rows.bend`, and
# the plant deliberately does NOT read it: that file is another unit's and was DIRTY in this
# tree while this gate was written, and a plant that reads a file another unit is editing is a
# plant whose subject can move under it.
FRAGMENT_SUBJECT = HERE / "opname-census-fragment.bend"


def two_part_line(raw: str) -> tuple[int, str] | None:
    """`(index, line)` of the line that carries a LIST OPENER and its first element on ONE
    line -- FOUND IN THE CODE, NOT IN A COMMENT.

    `strip_comments()` keeps the line COUNT and the columns, so the stripped line at index
    `i` is the code of the raw line at index `i` and the two can be compared.  MEASURED, on
    the first run of this plant: the search over the RAW text found the fixture's own
    PROSE, which shows that line inside backticks, and the "wrong shape" was then applied to
    a comment -- where it does nothing at all.
    """
    raw_lines = raw.split("\n")
    code_lines = pc.strip_comments(raw).split("\n")
    for i, ln in enumerate(code_lines):
        if ln.startswith("  [") and ln.rstrip().endswith(",") and i < len(raw_lines):
            return i, raw_lines[i]
    return None


def plant() -> int:
    """THE PLANT, THE CONTROL, THE PLACEHOLDER, AND THE TWO WRONG SHAPES.

        .venv/bin/python gates/opname-census-gate.py --plant

    EVERY EDIT IS A TEXT EDIT ON THE WORKING TREE. NEVER `git show HEAD:` -- a plant that
    reads HEAD plants nothing the moment HEAD carries the fix, and three units in this tree
    scored green under `--falsify` for exactly that reason.

    THE THREE NAMED CASES, AND THE PLANT MAKES EACH ONE:
      PLANT-1  `O.OpsGROUP{}` in code          -> COMPILE-FINDING
      PLANT-2  `O.OpsFLIP{}` in a FRAGMENT     -> COMPILE-LATENT-STALE (the fragment's own
                                                standing condition masks it)
      PLANT-3  `O.OpsX{}` in a COMMENT         -> COMPILE-NONE: a PLACEHOLDER, not a finding
      CONTROL  a comment of the same size      -> nothing moves, and the comment-only proof
                                                holds
      SHAPE-A  a comment BETWEEN the two parts -> the second part is DELETED, and only the
                                                comment-stripped proof catches it
      SHAPE-B  a whole-line comment at col 0  -> does NOT break the file, and the proof still
                                                calls it comment-only (the blank-line drop)
    """
    if not SUBJECT.is_file():
        print(f"REFUSED: {SUBJECT.relative_to(ROOT)} is absent, so there is nothing to plant into")
        return REFUSED
    original = SUBJECT.read_text()
    if PLANT_ANCHOR not in original:
        print(f"REFUSED: the plant's anchor {PLANT_ANCHOR!r} is not in {SUBJECT.name} as it "
              "stands. THE PLANT IS A TEXT EDIT ON THE WORKING TREE, so an anchor that moved "
              "means the plant must be re-anchored -- NOT that it should fall back to reading git.")
        return REFUSED
    if not FRAGMENT_SUBJECT.is_file():
        print(f"REFUSED: {FRAGMENT_SUBJECT.relative_to(ROOT)} is absent, so the fragment case "
              "cannot be planted")
        return REFUSED

    bad = 0
    # PLANT-1: the op upstream deleted, constructed again, in code.
    bad += _plant_one("PLANT-1 (O.OpsGROUP{} in code -> COMPILE-FINDING)",
                      original.replace(PLANT_ANCHOR, PLANT_UNKNOWN, 1), HERE / "_opname_plant.bend",
                      FINDING, "the op upstream deleted, constructed again")
    # PLANT-2: the same, in a FRAGMENT, where the fragment's OWN standing condition masks it.
    frag = FRAGMENT_SUBJECT.read_text()
    frag_anchor = next((ln for ln in frag.split("\n") if "O.OpsADD{}" in ln), None)
    if frag_anchor is None:
        print("PLANT-2     NOT APPLICABLE, AND THAT IS A MEASUREMENT: the fragment carries no "
              "O.OpsADD{} to replace")
    else:
        bad += _plant_one("PLANT-2 (O.OpsFLIP{} in a FRAGMENT -> COMPILE-LATENT-STALE)",
                          frag.replace("O.OpsADD{}", "O.OpsFLIP{}", 1),
                          HERE / "_opname_plant.bend", LATENT,
                          "the fragment's own standing condition masks the name")
    # PLANT-3: the PLACEHOLDER. A mention in a COMMENT is not a construction.
    commented = original.replace(PLANT_ANCHOR,
                                 PLANT_ANCHOR + "  # the placeholder: O.OpsX{}", 1)
    bad += _plant_none("PLANT-3 (O.OpsX{} in a COMMENT -> COMPILE-NONE, a PLACEHOLDER)",
                       commented, HERE / "_opname_plant.bend",
                       "the raw text names it and the CODE does not", want_site="OpsX")
    # CONTROL: a comment of the same size on a line that carries ONE statement.
    control = original.replace(PLANT_ANCHOR, PLANT_ANCHOR + "  # control: a comment, same size", 1)
    bad += _plant_none("CONTROL (a comment of the same size -> nothing moves)", control,
                       HERE / "_opname_plant.bend", "the comment-only proof holds")
    # SHAPE-A: a comment BETWEEN the two parts of a two-part line. The second part is DELETED.
    two = two_part_line(original)
    if two is None:
        print("SHAPE-A     NOT APPLICABLE, AND THAT IS A MEASUREMENT: the subject has no line "
              "that carries a list opener and its first element on one line")
    else:
        idx, two_part = two
        # THE EDIT IS BY LINE INDEX, NOT BY STRING.  The fixture's own PROSE shows this line
        # inside backticks, so `str.replace` found the COMMENT first and the "wrong shape" was
        # applied to a comment -- where it deletes nothing.  MEASURED, on the first run.
        lines_a = original.split("\n")
        lines_a[idx] = two_part.replace("[", "[  # a comment between the opener and the element", 1)
        shape_a = "\n".join(lines_a)
        same = code_only(shape_a) == code_only(original)
        state, _, _ = compile_verdict_str(shape_a)
        print(f"SHAPE-A     comment between the two parts of a two-part line (line {idx + 1}): "
              f"comment-only={same!s:<5} compiles={state:<14} ::  the second part is DELETED and "
              "only this proof catches it")
        if same:
            print("  THE WRONG SHAPE DID NOT MISBEHAVE: it was comment-only after all, so it is "
                  "not a demonstration of anything.")
            bad += 1
    # SHAPE-B: a whole-line comment AT COLUMN 0. It does NOT break a bend file, and the proof
    # must still call it comment-only -- which is what the blank-line drop buys.
    lines = original.split("\n")
    indent = next((i for i, ln in enumerate(lines)
                   if i > 0 and ln.startswith("  ") and lines[i - 1].strip()
                   and not lines[i - 1].lstrip().startswith("#")), None)
    if indent is None:
        print("SHAPE-B     NOT APPLICABLE, AND THAT IS A MEASUREMENT: no indented body follows a "
              "non-comment line in the subject")
    else:
        shape_b = list(lines)
        shape_b.insert(indent, "# a comment inserted at column 0")
        shape_b = "\n".join(shape_b)
        same = code_only(shape_b) == code_only(original)
        print(f"SHAPE-B     a whole-line comment at column 0: comment-only={same!s:<5}  ::  it does "
              "NOT break the file, and the blank-line drop is what keeps the proof true")
        if not same:
            print("  THE WRONG SHAPE WAS READ AS AN EDIT: a whole-line comment IS comment-only, "
                  "and a proof that says otherwise proves nothing.")
            bad += 1

    print(f"\n=== plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
    return FAIL if bad else PASS


def _plant_one(label: str, text: str, scratch: Path, want: str, why: str) -> int:
    """PLANT ONE CASE: the census must report `want` for the planted file, and go RED."""
    scratch.write_text(text)
    try:
        verdict, rows, _ = census(None)
    finally:
        scratch.unlink(missing_ok=True)
    mine = [r for r in rows if r["file"] == str(scratch.relative_to(ROOT))]
    got = mine[0]["class"] if mine else "NO-ROW"
    print(f"{label:<58} census-verdict={'FAIL' if verdict == FAIL else verdict}  class={got}  "
          f":: {why}")
    if got != want or verdict != FAIL:
        print(f"  THE PLANT DID NOT FIRE: wanted {want} and a red census, got {got} and "
              f"{'FAIL' if verdict == FAIL else verdict}.")
        return 1
    return 0


def _plant_none(label: str, text: str, scratch: Path, why: str,
                want_site: str | None = None) -> int:
    """PLANT ONE CASE THAT MUST NOT FIRE: the census must find NOTHING in the planted file.

    `want_site` names a COMMENT-ONLY mention the census must REPORT as a site -- because a
    census that classifies by code and does not REPORT the text it discarded is a census
    whose discrimination cannot be SEEN.
    """
    scratch.write_text(text)
    try:
        verdict, rows, comment_only = census(None)
    finally:
        scratch.unlink(missing_ok=True)
    mine = [r for r in rows if r["file"] == str(scratch.relative_to(ROOT))]
    sites = [f"{f}:{ln} {nm}" for f, ln, nm in comment_only if f == str(scratch.relative_to(ROOT))]
    print(f"{label:<58} census-verdict={'FAIL' if verdict == FAIL else verdict}  rows={len(mine)}"
          f"  :: {why}")
    if want_site is not None:
        hit = [s for s in sites if want_site in s]
        print(f"{'':<58} comment-only sites={sites}  ::  the discarded mention must be NAMED")
        if not hit:
            print(f"  THE CENSUS DID NOT REPORT THE MENTION IT DISCARDED: {want_site} is not among "
                  f"{sites}.")
            return 1
    if mine or verdict != PASS:
        print("  THE CONTROL IS NOT A CONTROL: it moved the census, or it edited more than a "
              "comment.")
        return 1
    return 0


def selftest() -> int:
    """THE NEGATIVE CONTROL, ON ITS OWN. It also runs inside every census run.

        .venv/bin/python gates/opname-census-gate.py --selftest
    """
    neg, why = negative_control()
    print(f"NEGATIVE    the control fired={not neg!s:<5} :: {why}")
    if not neg:
        print("  THE NEGATIVE CONTROL FIRED: the scanner reached something that is not an op "
              "construction.")
        return FAIL
    return PASS


def main() -> int:
    if "--plant" in sys.argv:
        return plant()
    if "--selftest" in sys.argv:
        return selftest()
    if not pc.BEND.is_file():
        print(f"REFUSED: {pc.BEND} is absent, so no file can be judged; a census over zero judged "
              "files is not a census")
        return REFUSED
    verdict, _, _ = census(ROWS)
    return verdict


if __name__ == "__main__":
    sys.exit(main())
