#!/usr/bin/env python3
"""compile-census.py -- the `.bend` COMPILE CENSUS for the part of the tree `substrate.py` does NOT walk.

    checks/compile-census.py [--rows PATH] [--mb N] [--seconds N]

WHY THIS IS NOT A GATE, MEASURED. `checks/substrate.py` IS ALREADY the per-file compile check:
`POP_ROOT = "tinybendygrad"`, an `os.walk` population, `bin/bend <file> --check-only` per file under
`checks/bounded.py`, a `WARM`/`COLD` verdict each, and a `ROUTE` denominator. MEASURED 2026-10-17,
`--root` over two files prints `ROUTE bend=2 cc=0 node=0 no-instrument=0  (of 2 file(s))`.
**SO A NEW PER-FILE COMPILE GATE WOULD BE A FORK OF THAT, AND THIS IS NOT ONE.** This file asks
`substrate.py` for the population instead of naming one: it imports `substrate` BY PATH and reads
`POP_ROOT` off it, so the coverage boundary is the INSTRUMENT'S declaration and not a hand list
here. `AGENTS.md` doctrine 1: "Never list in this file what an instrument discovers."

THE GAP, AND ITS TWO NUMBERS ARE NOW COMPUTED, NOT TRANSCRIBED. `os.walk(".")` over the repo,
`references/` excluded (`.gitignore:2`, the vendored bend compiler's own 1,714 `.bend`),
`.agents/slop/` excluded (agent scratch), `runs/` excluded (run artifacts; `runs/margsym/snap/` is a
SNAPSHOT OF THE PORT, so compiling it twice is not a second opinion), leaves the `.bend` that
`substrate.py`'s default root never sees. THE COUNT USED TO BE WRITTEN HERE AND WAS 90, WITH 82 IN
`git ls-tree -r HEAD`; both were a second copy of a measurement the tool recomputes on every run, so
both rotted. THEY ARE NOT HERE ANY MORE: `main()` prints `POPULATION .bend handed=` and
`POPULATION untracked=`, and those are the numbers. THEY ARE THE GATES' OWN DRIVERS (`gates/*.bend`),
the oracle drivers (`oracles/*.bend`), `checks/*.bend`, `examples/`, `langs/` -- i.e. the files the
harness RUNS, which are exactly the files a driver that does not compile cannot report.

`untracked=` IS A DENOMINATOR CAVEAT AND IT IS NOT COSMETIC. `discover()` walks the WORKING COPY, so
the population is whatever is on the machine, and part of it cannot be committed: MEASURED 2026-10-18,
of 91 handed, **86 are in HEAD and 5 are not** -- `gates/{cstyle,decomp,realize}-mut-driver.bend`,
`gates/.realize-mut-stage/realize_graph_census.bend` and `oracles/probe-su.bend`. **SO THE `.rows`
ARTEFACT IS A CENSUS OF A TREE THAT DOES NOT EXIST IN A CLONE**, where `discover()` hands 86 and the
committed file carries 87 rows, one of them for a path no checkout has. Every number this tool prints
is therefore a reading of THIS MACHINE at THIS MOMENT, which is why the header now carries the run's
UTC stamp.

THE FIRST REAL BREAKAGE, FOUND BEFORE ANYTHING WAS INTRODUCED. `checks/gate_norm.bend:27` imports
`../../../tinybendygrad/base.bend`. From `checks/` that is THREE levels above the repo root, so it
resolves to `/Users/cyberistic/src/tinybendygrad/base.bend` -- a checkout that does not exist -- and
`bend` answers `SOME PROOFS FAIL`. `checks/gate_norm.py:120` pops that file, so the gate is running
a driver that cannot resolve. **IT IS UNCONDITIONALLY BROKEN FOR ANY CHECKOUT DEPTH** (the repo root
is always exactly `../` from `checks/`), which is why the path is wrong and not merely stale.

THE COUNT IS THE VERDICT. Per `AGENTS.md`: a check that prints "OK" over N files with no count
cannot be falsified, and this file's own `TOTALS` line is `name=value` throughout so the rows
aggregate by `awk` without a parser.

EXIT STATUS, `gates/gatekit.py`'s five by path via `checks/verdict.py`, never re-spelled:
  0  every file judged and every one WARM
  1  at least one COLD -- a file did not compile, named on stdout with its first line
  3  REFUSED: an input was absent (no `bend`, no rows sink, the walk found nothing, or a file the
     instrument could not judge). `SKIP IS NOT PASS`, and a count of 0 over 0 files is not a census.
A `KILLED-ON-MEMORY` / `TIMED-OUT` / `NOT-STARTED` from `checks/bounded.py` is READ AS A TOKEN and
NOT as the child's exit status, per `checks/bounded.py`'s own header; such a file is counted
`NO-MEASUREMENT`, not `COLD`, because the instrument proved nothing about it.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# `checks/verdict.py` IS BESIDE THIS FILE, not under `gates/`. The three `sys.path.insert`
# sites below read `ROOT / "gates"`, and `gates/verdict.py` does not exist -- MEASURED, so every
# REFUSED path in this file raised `ModuleNotFoundError: No module named 'verdict'` instead of
# printing its sentence and exiting 3. `SKIP IS NOT PASS` and exit 3 is `REFUSED`, so the
# instrument could not say the one word it exists to say. `checks/verdict.py`'s own header spells
# the import (`sys.path.insert(0, str(Path(__file__).resolve().parent))`); that is `HERE`.
HERE = Path(__file__).resolve().parent
PY = ".venv/bin/python"

# THE BEND LOCK, PER INVOCATION. `checks/bendlock.sh`'s own header says it: "**THE LOCK IS HELD
# FOR THE WHOLE COMMAND, AND A COMMAND THAT RUNS **MANY** BENDS **MONOPOLISES IT** ... SO FOR A
# GATE THAT RUNS MANY BENDS, **ACQUIRE THE LOCK **PER **INVOCATION**, NOT **ONCE **FOR **THE
# **GATE** -- `gates/bendlock.py` **IS **THAT **LOCK** (it shares this path, so the two exclude
# each other).**" **THIS CENSUS COMPILES MANY FILES** -- a hundred and more of them -- and it took
# the lock ONCE, which made it wait on itself, or not take it at all, which let it run beside
# another unit's compiler. `gates/bendlock.py` is the same lock and the same path, so the two
# exclude each other. MEASURED, the shape it fixes: `checks/bendlock.sh -- .venv/bin/python
# checks/compile-census.py` would hold the lock for the WHOLE census and every other unit would
# wait for all of it.
sys.path.insert(0, str(ROOT / "gates"))
from bendlock import bend_lock  # noqa: E402

# THE INSTRUMENT'S OWN POPULATION DECLARATION, LOADED BY PATH. Not re-typed here: a second copy of
# the vocabulary is the same fault as a second copy of a population (`checks/cl-port-gate.py:65`).
_spec = importlib.util.spec_from_file_location("substrate", ROOT / "checks" / "substrate.py")
substrate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(substrate)                      # module level is inert (it only defines)

# THE WATCHDOG, AND IT IS `checks/substrate.py`'s OWN CONSTANT READ BY PATH -- the same file, the
# same arguments, the same verdict token. A second spelling of the watchdog's path is a second
# instrument that can drift from the first.
BOUNDED = substrate.BOUNDED

# WHAT THE WALK DOES NOT SEE, AND WHY. Each is a MEASURED exclusion, not a preference; the counts
# travel in the CENSUS line so the subtraction is a number and not a claim.
SKIP_DIRS = {
    ".git": "VCS internals", "node_modules": "third-party", "__pycache__": "build output",
    ".venv": "third-party", "references": ".gitignore:2, the vendored bend compiler, 1714 .bend",
    ".agents": "agent scratch, 113 .bend under slop/, swept by checks/sweep.py",
    "runs": "run artifacts; runs/margsym/snap/ is a SNAPSHOT OF THE PORT",
}

# `checks/bounded.py`'s own verdict TOKEN, read off stderr. The exit status is the child's and cannot
# mean one thing (`bounded.py`: `sh -c 'exit 3'` is a refusal at 0 MB and a kill at 2,988 MB).
# MATCHED ANYWHERE IN THE LINE, NOT AT ITS START: `substrate.py:302` RE-EMITS the record with its own
# `[substrate] <file>: ` prefix, so an anchored `^\[bounded\]` finds nothing and every file would be
# counted NO-MEASUREMENT -- the census silently measuring zero, which is the defect this file exists
# to remove. MEASURED on that defect: the anchored form returned `NO-TOKEN` for 2 of 2 files that
# had in fact reported `WITHIN-LIMITS rc=1`.
TOKEN_RC = re.compile(r"\[bounded\] (?P<token>WITHIN-LIMITS|KILLED-ON-MEMORY|TIMED-OUT|NOT-STARTED"
                      r"|NO-VERDICT)\b[^:]*?(?:rc=(?P<rc>\d+))?")
# `gates/gatekit.py:NOTICE` is bend's 42-byte update line on stderr; it is not the instrument's answer.
NOTICE = substrate.NOTICE

# THE SHAPE THE COMPILER'S ERROR DID NOT MATCH. It is a name here so that a reader of this
# file's rows, and `gates/compile-census-gate.py`, can ask for the set of shapes the tree can
# produce without re-typing it.
UNATTRIBUTED = "UNATTRIBUTED"

# THE COMPILER's OWN ERROR SHAPES. **THE NAMES ARE `checks/substrate.py`'s -- THE TREE's OWN
# VOCABULARY, SO A READER WHO KNOWS ONE KNOWS THE OTHER -- AND THE PATTERNS ARE FIXED, BECAUSE
# `checks/substrate.py:cause_of()` CANNOT MATCH A REAL BEND FAILURE.** MEASURED, three defects,
# and `cause_of_lines()` above says what they are: the `^` anchor over a whole output, the JOINED
# form the compiler does not print, and the `'def','type'` spacing the compiler does not print.
#
# THE ORDER IS THE TABLE's OWN ORDER (`checks/substrate.py:773`: "most specific first, so the
# generic type-mismatch shape cannot swallow `a defined name`), and the last two arms are the ones
# the tree's table lacks: an ARITY error ("expected : X with N fields") and the fallback.
#
# **⇒ AND A SHAPE IS A CLASS, NOT A VERDICT.** `MISSING-DEF` and `UNKNOWN-CTOR` are BREAKAGES in
# this tree and `SYNTAX` and `FOREIGN` are STANDING-COLD in it; the shape says WHICH, and
# `gates/compile-census-standing.rows` says which files are allowed to be which.
CAUSES = (
    (re.compile(r"^Error: (\d+) TODOs? found\."), "HOLES", 1),
    (re.compile(r"^Error: (\d+) defs rely on unsafe or foreign code:"), "FOREIGN", 1),
    (re.compile(r"^- expected : a fresh name \(duplicate declaration: (\S+?)\)"), "DUPLICATE", 1),
    (re.compile(r"^- expected : a defined name / observed : (\S+)"), "MISSING-DEF", 1),
    (re.compile(r"^- expected : a declared constructor .* / observed : (\S+)"), "UNKNOWN-CTOR", 1),
    (re.compile(r"^- message\s*: a declared constructor \(unknown: (\S+?)\)"), "UNKNOWN-CTOR", 1),
    (re.compile(r"^- expected : ('def',\s*'type'\s*or\s*'law') / observed : (\S+)"), "SYNTAX", 2),
    (re.compile(r"^- expected : [\w./]*?([A-Za-z_]\w*) with \d+ fields"), "ARITY", 1),
    (re.compile(r"^- expected : (\S+) / observed : (\S+)"), "TYPE-MISMATCH", 2),
)


def cause_of_lines(output: str) -> tuple[str, str, str]:
    """THE COMPILER's OWN ERROR SHAPE, the symbol it names, and the LINE it said it on.

    **THE SHAPE NAMES ARE `checks/substrate.py`'s -- THE TREE's OWN VOCABULARY -- AND THE PATTERNS
    ARE FIXED, BECAUSE `checks/substrate.py:cause_of()` CANNOT MATCH A REAL BEND FAILURE.**
    MEASURED, two defects, and both are in the table's own patterns:

      (a) **THE `^` ANCHOR.** `checks/substrate.py:cause_of()` searches the WHOLE output, and
          `re.search` without `re.MULTILINE` anchors at the START OF THE STRING. A bend failure's
          FIRST line is `SOME PROOFS FAIL` and the error is on the second, so the whole-output
          search answers `None` for EVERY real failure. MEASURED on a synthetic three-line failure:
          `cause_of()` answered `None` where the per-line search answers `('HOLES', '34')`.
      (b) **THE JOINED FORM.** The table's patterns are written for `- expected : X / observed : Y`
          ON ONE LINE, and the compiler prints the two halves on SEPARATE lines:
          `- expected : a defined name` and `- observed : C.render_kernel`. ⇒ **THE PAIRS ARE
          JOINED HERE, ONCE, AND THE TABLE IS THEN APPLIED TO THE FORM IT WAS WRITTEN FOR.**
          MEASURED, on the real output of `checks/.e2e-fixture/f64/emit-f64.bend`: the joined
          haystack answers `('MISSING-DEF', 'C.render_kernel')` where the table's own reader
          answers `None`.
      (c) **THE SPACING.** The `SYNTAX` pattern spells `'def','type' or 'law'` with no space after
          the comma, and the compiler prints `'def', 'type' or 'law'`. `gates/opname-census-gate.py`'s
          own `FRAGMENT` regex gets this right (`'def',\\s*'type'\\s*or\\s*'law'`), so the tree has
          both spellings and only one of them matches.

    ⇒ **THE CAUSE IS WHAT MAKES `COLD` A CLASS AND NOT A NOISE.** `COLD` alone says "the first
    line was not `ALL PROOFS CHECK`", which every failure in the tree shares; the shape says
    WHICH failure, and the compiler's own wording is what names them."""
    lines = join_pairs(output.splitlines())
    for rx, shape, group in CAUSES:
        for line in lines:
            if m := rx.search(line):
                return shape, " ".join(m.group(group).split()), line.strip()
    return UNATTRIBUTED, "", ""


def join_pairs(lines: list[str]) -> list[str]:
    """THE COMPILER's `- expected :` / `- observed :` PAIRS, JOINED ONTO ONE LINE.

    **THE COMPILER PRINTS THE TWO HALVES ON SEPARATE LINES AND THE TREE's TABLE PATTERNS ARE
    WRITTEN FOR THE JOINED FORM** -- `checks/substrate.py:CAUSES` spells them
    `- expected : a defined name / observed : (\\S+)`. MEASURED on the real output of
    `oracles/nv_ip_rows_c.bend`:

        - expected : a defined name
        - observed : IO

    and the table's `MISSING-DEF` pattern does not match either line. **SO THE PAIR IS JOINED
    HERE**, with the joiner the table's own patterns use, and the table is then applied to the
    form it was written for. A line that has no partner is left alone."""
    out: list[str] = []
    i = 0
    while i < len(lines):
        ln = lines[i]
        nxt = lines[i + 1] if i + 1 < len(lines) else ""
        if ln.startswith("- expected : ") and nxt.startswith("- observed : "):
            out.append(f"{ln} / observed : {nxt[len('- observed : '):]}")
            i += 2
            continue
        out.append(ln)
        i += 1
    return out


def sha_of(path: str) -> str:
    """The file's sha256, so the census's record is keyed on CONTENT.

    `checks/differ.py:substrate_digest()` says why, in the tree's own words: "Keyed on CONTENT and
    on the path RELATIVE TO `ROOT`. Never on `st_mtime`". A census keyed on an mtime cannot tell a
    file that was edited from a file that was merely checked out, and a fresh clone writes every
    file at the moment it was cloned.
    """
    try:
        return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
    except OSError:
        return "ABSENT"


def compiler_words(path: str, mb: int, seconds: int) -> tuple[str, str]:
    """THE COMPILER's OWN WORDS for one file: `(shape, the line it said them on)`.

    **WHY THE COMPILER IS ASKED AGAIN, AND ONLY FOR THE FILES THAT ARE COLD.** `checks/substrate.py`
    is this census's VERDICT instrument and stays so -- routing, `EMPTY` before `MISSING`, the
    `[bounded]` record, the exit status discarded in favour of the FIRST LINE -- all of it lives in
    the one file that owns it, and a bug fixed there moves this census for free. **BUT IT DOES NOT
    FORWARD THE COMPILER's OUTPUT**: `checks/substrate.py:half1()` emits the FIRST line of the
    merged output and nothing else, and the CAUSES section it can print (`--causes`) is built by
    `checks/substrate.py:cause_of()`, whose `^`-anchored patterns are searched against the WHOLE
    output -- **and a bend failure's FIRST line is `SOME PROOFS FAIL`, so the anchor never matches
    and every real failure reads `UNATTRIBUTED`. MEASURED, on a synthetic three-line failure:
    `cause_of()` answered `None` where the per-line search answers `('HOLES', '34')`.

    ⇒ **SO THE WORDS ARE ASKED FOR DIRECTLY, AND THE COST IS THE SIZE OF THE COLD CLASS AND NOT OF
    THE POPULATION.** The envelope is `checks/bounded.py` under `gates/bendlock.py` -- the same
    watchdog and the same lock this census's other call uses -- and the shape is
    `checks/substrate.py`'s own `CAUSES` table applied LINE BY LINE (`cause_of_lines()` above).

    **WITHOUT THE WORDS, `COLD` IS A NOISE.** Every cold row in this tree's own artefact said
    `SOME PROOFS FAIL`, which is the same sentence for a FRAGMENT that cannot compile by design and
    for a driver whose constructor was deleted upstream."""
    with bend_lock():
        p = subprocess.run([PY, BOUNDED, "--mb", str(mb), "--seconds", str(seconds), "--",
                            "./bin/bend", path, "--check-only"],
                           cwd=ROOT, capture_output=True, text=True,
                           env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"})
    tok = next((m for m in (TOKEN_RC.search(ln) for ln in p.stderr.split("\n")) if m), None)
    if not tok or tok.group("token") != "WITHIN-LIMITS":
        return "NO-MEASUREMENT", f"the bounded token was {tok.group('token') if tok else 'NO-TOKEN'}"
    shape, symbol, error = cause_of_lines(p.stderr)
    return (shape if shape == "UNATTRIBUTED" else f"{shape} {symbol}".strip()), error[:200]


def discover() -> tuple[list[str], list[str]]:
    """EVERY `.bend` under the repo, by `os.walk`, MINUS the subtree `substrate.py` declares.

    The walk is unfiltered: `endswith` is applied by `substrate.instrument_for`, the ROUTER, and
    never here (`substrate.discover`'s docstring, measured on the four `ops.staged-*` strays).
    Returns `(population, dropped)` where `dropped` is `[(reason, count)]` so the CENSUS line can
    print the subtraction instead of asserting it.
    """
    out, dropped = [], {}
    for d, dirs, fs in os.walk("."):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
        for f in sorted(fs):
            p = os.path.normpath(os.path.join(d, f))
            if not f.endswith(".bend"):
                continue
            if p.startswith(substrate.POP_ROOT + os.sep) or p == substrate.POP_ROOT:
                dropped[f"already covered by substrate.py POP_ROOT={substrate.POP_ROOT}"] = \
                    dropped.get(f"already covered by substrate.py POP_ROOT={substrate.POP_ROOT}", 0) + 1
                continue
            out.append(p)
    for name in SKIP_DIRS:
        n = sum(1 for _ in os.walk(name)) and len(
            [1 for d, _, fs in os.walk(name) for x in fs if x.endswith(".bend")])
        if n:
            dropped[f"skipped dir {name}/ -- {SKIP_DIRS[name]}"] = n
    return out, sorted(dropped.items())


def judge(path: str, mb: int, seconds: int) -> dict:
    """One file. Returns `{state, token, first_line, peak, cause, error, sha}`.

    THE SUBSTRATE GATE IS THE INSTRUMENT, CALLED AS A SUBPROCESS, NOT REIMPLEMENTED. Everything that
    makes its verdict correct -- routing, `EMPTY` before `MISSING`, `--check-only`'s exit status
    being DISCARDED in favour of the FIRST LINE, the `[bounded]`/`MACHINE` lines kept off stdout --
    stays in the one file that owns it, and a bug fixed there moves this census for free.

    **THE CAUSE, THE ERROR AND THE SHA ARE THREE MORE MEASUREMENTS OF THE SAME RUN, AND NONE OF
    THEM IS A SECOND INSTRUMENT.** The cause is the compiler's own error shape, read off the
    stderr this call already captured (`cause_of_lines()` above, over `checks/substrate.py`'s
    `CAUSES` table); the error is the compiler's own line; the sha is the file's bytes.
    **WITHOUT THE CAUSE, `COLD` IS A NOISE**: twenty-one rows in this tree's own artefact all
    said `SOME PROOFS FAIL`, which is the same sentence for a FRAGMENT and for a driver whose
    constructor was deleted upstream. **WITHOUT THE SHA, THE ARTEFACT IS A SNAPSHOT NOTHING CAN
    CHECK**: a reader cannot tell a census that describes this tree from one that describes last
    week's.
    """
    # THE LOCK IS TAKEN FOR THIS ONE COMPILATION AND RELEASED IMMEDIATELY AFTER, so a census over
    # a hundred files does not monopolise it for the whole run. See the import at the top of this
    # file for why it is PER INVOCATION and not once for the census.
    with bend_lock():
        p = subprocess.run([PY, "checks/substrate.py", "--mb", str(mb), "--seconds", str(seconds),
                            path],
                           cwd=ROOT, capture_output=True, text=True,
                           env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"})
    row = next((ln for ln in p.stdout.split("\n") if ln.startswith(("WARM", "COLD", "EMPTY",
                                                                    "NO INSTRUMENT"))), "")
    # SEARCHED ACROSS THE LINE, NOT ANCHORED. MEASURED, AND IT COST A WHOLE 35-FILE RUN:
    # `substrate.py:302` re-emits bounded.py's record as `[substrate] <file>: [bounded] WITHIN-LIMITS
    # ...`, so a `ln.startswith("[bounded] ")` test found nothing, every row came back `NO-TOKEN`, and
    # the `NO-TOKEN -> NO-MEASUREMENT` rule below then labelled **35 of 35 files NO-MEASUREMENT while
    # all 35 were WARM** -- a census measuring zero over a full population, which is the precise
    # failure this file was written to end. A census that cannot see its own instrument's verdict is
    # the `DEAD` of `gates/gatekit.py:55` wearing a count.
    tok = next((m for m in (TOKEN_RC.search(ln) for ln in p.stderr.split("\n")) if m), None)
    tok, rc = (tok.group("token"), tok.group("rc")) if tok else ("NO-TOKEN", "")
    sha = sha_of(path)
    if not row:                      # the instrument emitted nothing about this file at all
        return {"state": "NO-MEASUREMENT", "token": tok,
                "first_line": "substrate.py emitted no verdict for this file", "peak": "",
                "cause": "NO-VERDICT", "error": "", "sha": sha}
    state = row.split()[0]
    why = " :: ".join(x for x in row.split("::")[1:]).strip() if "::" in row else ""
    # bounded.py's token is the verdict. A KILL is not a COLD and a NOT-STARTED is not a COLD.
    if tok in ("KILLED-ON-MEMORY", "TIMED-OUT", "NOT-STARTED", "NO-VERDICT"):
        state = "NO-MEASUREMENT"
    elif tok == "NO-TOKEN":
        # A MISSING TOKEN IS NOT A VERDICT EITHER, and it is the case this run actually hit: the
        # instrument's own verdict line is right there, so reporting it as NO-MEASUREMENT would throw
        # away a measurement that was taken. It is reported, and the CENSUS line carries the count, so
        # a reader sees that the token was unread rather than trusting `WITHIN-LIMITS` that is absent.
        state = state + "?NOTOKEN"
    peak = next((m.group(1) for m in
                 (re.search(r"peak-RSS=(\d+) MB", ln) for ln in p.stderr.split("\n")) if m), "")
    # THE COMPILER's OWN WORDS, AND ONLY FOR THE FILES THAT ARE COLD. `checks/substrate.py` is the
    # verdict instrument and does not forward the compiler's output; `compiler_words()` asks again,
    # and the cost is the size of the COLD class and not of the population.
    cause, error = ("", "")
    if state.startswith("COLD"):
        cause, error = compiler_words(path, mb, seconds)
    else:
        cause, error = "WARM", ""
    return {"state": state, "token": tok, "first_line": (why or row)[:160], "peak": peak,
            "cause": cause, "error": error, "sha": sha}


def main() -> int:
    ap = argparse.ArgumentParser(prog="checks/compile-census.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rows", default="checks/compile-census.rows")
    ap.add_argument("--mb", type=int, default=substrate.DEFAULT_MB)
    ap.add_argument("--seconds", type=int, default=substrate.SHELL_SECONDS)
    a = ap.parse_args()

    if not (ROOT / "bin" / "bend").is_file():
        sys.path.insert(0, str(HERE))
        from verdict import REFUSED, settle
        settle(REFUSED, "bin/bend is absent, so no file in this population can be judged; a census "
                        "over zero judged files is not a census")
    pop, dropped = discover()
    if not pop:
        sys.path.insert(0, str(HERE))
        from verdict import REFUSED, settle
        settle(REFUSED, f"the walk found no .bend outside {substrate.POP_ROOT}/ and the skipped "
                        "directories; the population is empty and an empty census proves nothing")

    # THE COMMITTED TREE, BY `ls-tree` AND NOT BY `ls-files`: `AGENTS.md` -- the index is ARMED
    # (`jj` colocated snapshots stage into `.git/index`), so `ls-files` answers with intent-to-add
    # placeholders and would report scratch this tree cannot check out. `ls-tree -r HEAD` is the
    # tree. THE NUMBER IS A CAVEAT, NOT A FILTER: nothing is dropped below, because a `.bend` on
    # disk and uncommittable is still a `.bend` a reader of this artefact cannot reproduce.
    committed = set(subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"],
                                   cwd=ROOT, capture_output=True, text=True).stdout.split("\n"))
    untracked = [p for p in pop if p not in committed]
    print(f"POPULATION .bend handed={len(pop)}  ::  the complement of substrate.py "
          f"POP_ROOT={substrate.POP_ROOT}/ under os.walk('.')")
    print(f"POPULATION untracked={len(untracked)} of {len(pop)}  ::  in the WORKING COPY and NOT in "
          f"`git ls-tree -r HEAD`, so a clean clone's discover() hands {len(pop) - len(untracked)}")
    for p in untracked:
        print(f"UNTRACKED  {p}")
    for reason, n in dropped:
        print(f"EXCLUDED   {n:5d}  ::  {reason}")

    tally: dict[str, int] = {}
    sink = ROOT / a.rows
    with sink.open("w") as fh:
        fh.write(f"# compile-census: per-file `bin/bend --check-only` over the {len(pop)} .bend that "
                 f"checks/substrate.py's POP_ROOT={substrate.POP_ROOT}/ does not walk.\n"
                 f"# taken={time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}  "
                 f"committed={len(pop) - len(untracked)}  untracked={len(untracked)}  ::  A SNAPSHOT. "
                 f"`discover()` walks the WORKING COPY, so that count is `len(discover())` AT THIS "
                 f"MOMENT and it MOVES as drivers land; a run whose `handed=` differs from the number "
                 f"on the line above is the tree having moved, not this file being wrong. Re-run to "
                 f"re-take it.\n"
                 f"# state= WARM|COLD|NO-MEASUREMENT|NO-INSTRUMENT|<state>?NOTOKEN  token= checks/bounded.py's OWN verdict token, "
                 f"read off stderr because its exit status cannot mean one thing.\n"
                 "# first_line= the instrument's first stderr line, or the verdict row.\n"
                 "# cause= the COMPILER's OWN error shape, from `checks/substrate.py`'s `CAUSES` table\n"
                 "#   (loaded by path) applied LINE BY LINE -- `substrate.cause_of()` searches the whole\n"
                 "#   output and its `^`-anchored patterns never match, because a bend failure's first\n"
                 "#   line is `SOME PROOFS FAIL` and the error is on the second.  `COLD` ALONE IS A\n"
                 "#   NOISE: every failure in the tree shares the sentence `SOME PROOFS FAIL`, and a\n"
                 "#   FRAGMENT and a driver whose constructor was deleted upstream must not be read\n"
                 "#   the same way.\n"
                 "# sha= the file's sha256, so the record is keyed on CONTENT.  `checks/differ.py`'s\n"
                 "#   `substrate_digest()` says why: \"Never on st_mtime\".  A reader can now tell a\n"
                 "#   census that describes THIS tree from one that describes last week's.\n"
                 "# error= the compiler's OWN line, verbatim, so a row names the error and not a\n"
                 "#   class of it.  This is the column `gates/compile-census-gate.py` prints.\n"
                 "# **THE COLUMN NAMES ARE IN THIS HEADER AND NOT IN A LINE OF THEIR OWN, AND THAT IS\n"
                 "# A FIX AND NOT A STYLE.** MEASURED 2026-10-20 on `gates/edge-runner.py`'s reader of\n"
                 "# a generated `.rows`: with the column line written as DATA, the reader parsed it as\n"
                 "# a row whose key was the literal string `gate`, and the edge's plan then reported\n"
                 "# `STALE gate` -- a gate that does not exist, named by the file's own vocabulary.\n"
                 "# The house style agrees: `gates/crp_graph_census-pins.rows` puts its column names\n"
                 "# in the `#` header and writes no column line at all.\n"
                 f"# ceiling {a.mb} MB, {a.seconds} s, ONE bend process at a time.\n"
                 "# columns: state, peak_MB, token, file, cause, sha, error, first_line\n")
        for i, path in enumerate(pop, 1):
            r = judge(path, a.mb, a.seconds)
            state = r["state"]
            tally[state] = tally.get(state, 0) + 1
            fh.write(f"{state}\t{r['peak']}\t{r['token']}\t{path}\t{r['cause']}\t{r['sha']}\t"
                     f"{r['error']}\t{r['first_line']}\n")
            fh.flush()
            print(f"{state:<15} {path:<48} [{r['token']}] {r['cause']:<22} {r['error']}")

    judged = len(pop)
    # ANY STATE THAT IS NOT A MEASUREMENT IS COUNTED AS UNJUDGED, by PREFIX rather than by an
    # enumeration: a new state added above that is not listed here would otherwise be silently
    # excluded from the denominator, which is the shape `AGENTS.md` calls a check that cannot be
    # wrong because it cannot be anything.
    unjudged = sum(n for k, n in tally.items() if not k.startswith(("WARM", "COLD")))
    cold = tally.get("COLD", 0)
    print()
    for k in sorted(tally):
        print(f"CENSUS      {k}={tally[k]}")
    print(f"DENOMINATOR handed={judged} judged={judged - unjudged} (.bend outside "
          f"{substrate.POP_ROOT}/); warm={tally.get('WARM', 0)} cold={cold} unjudged={unjudged}")
    print(f"ARTIFACT    {a.rows}")
    if unjudged:
        sys.path.insert(0, str(HERE))
        from verdict import REFUSED, settle
        settle(REFUSED, f"{unjudged} of {judged} files were NOT judged, so the warm count above is "
                        f"not a verdict about the population")
    return 1 if cold else 0


if __name__ == "__main__":
    sys.exit(main())