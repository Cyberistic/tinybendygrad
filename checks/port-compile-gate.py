#!/usr/bin/env python3
"""port-compile-gate.py -- DOES THE PORT COMPILE? A census over EVERY `.bend` under the port.

    .venv/bin/python checks/port-compile-gate.py            # the census, the rows, the verdict
    .venv/bin/python checks/port-compile-gate.py --plant    # the plant, the control, the two wrong shapes
    .venv/bin/python checks/port-compile-gate.py --file F   # judge ONE file (the plant's unit)

WHY THIS FILE EXISTS, AND IT IS NOT A NEW COMPILE GATE FOR THE SAKE OF ONE.

`checks/substrate.py` IS the per-file compile check, and it COVERS this population: its
`POP_ROOT` is `tinybendygrad`, so `tinybendygrad/runtime/support/autogen.bend` is in it, and
MEASURED, `checks/substrate.py <that file>` answers `COLD ... :: SOME PROOFS FAIL` on the
bytes as they stood and `WARM` on the bytes as they stand now. So the INSTRUMENT EXISTED and
COVERED the file, and the defect was there anyway. Two things explain that, and both are
findings rather than reasons to add a second instrument:

  1. `checks/substrate.py` CANNOT BE GREEN over this population, and a check that is always red
     is not a check. Its verdict is `COLD` for EVERY file whose first line is not
     `ALL PROOFS CHECK`, and the port holds files that will never say it: the proof files
     (`LAWS.bend`, `PROOF.bend`, `PROOF2.bend`) say `Error: N TODOs found. The code is
     incomplete, and not a valid proof yet.`, and the FFI files say `Error: N defs rely on
     unsafe or foreign code:`. Both are the tree's STANDING conditions, and both are
     REPORTED here as what they are rather than as defects.
  2. In the reachable edge it does not even get that far: `gates/edge-trace.rows` (written
     2026-10-22T04:46:41Z, HEAD=337b7cc15) records `checks/substrate.py  RAN  REFUSED  rc=3
     0.58s` -- it REFUSED in half a second, and `gates/edge-trace.rows` is the tree's only
     record of what RUNS. A REFUSED gate has no verdict, and a gate with no verdict does not
     report a file that does not compile.

SO WHAT IS ADDED IS NOT A SECOND JUDGE: it is the READING that turns a compile census into a
VERDICT, with the standing conditions named as standing, and a population DISCOVERED by the
instrument that owns it.

THE POPULATION IS THE ROUTER'S, LOADED BY PATH. `checks/substrate.py` is imported by path and
its `POP_ROOT` and `instrument_for()` are asked which files the BEND instrument judges. A
hand list of four proof files is the same defect this project has catalogued twenty times: a
population an instrument FILTERS is a population it cannot be wrong about, because it cannot
be anything. `AGENTS.md` doctrine 1: "Never list in this file what an instrument discovers."

THE VERDICT TOKEN, NOT THE EXIT STATUS. `checks/bounded.py`'s contract is the child's stdout
byte for byte on stdout, and the child's stderr PLUS ONE `[bounded] <TOKEN>  rc=...` record
on stderr. The TOKEN is `WITHIN-LIMITS` / `KILLED-ON-MEMORY` / `TIMED-OUT` / `NOT-STARTED` /
`NO-VERDICT`, and a run whose token is not `WITHIN-LIMITS` PROVES NOTHING about the file, so
it is counted `NO-MEASUREMENT` and never `COLD`. `AGENTS.md` records a unit that lost 425 rows
by believing the exit status instead.

THE COMPILER'S OWN VERDICT, READ THE WAY `checks/substrate.py` READS IT: a healthy file
answers `ALL PROOFS CHECK` on STDOUT, and a broken one answers NOTHING on stdout and
`SOME PROOFS FAIL` / `Error: ...` on STDERR. The two are joined stdout-first, and the
42-byte update notice (`bend <ver> is available: run bend update`) and the `[bounded]` record
are not the compiler's answer. `gates/gatekit.py`'s `NOTICE` is imported rather than re-typed.

THE CLASSES ARE THE COMPILER'S OWN ERROR CLASSES, NOT A LIST OF FILENAMES:
  COMPILES        the first line is `ALL PROOFS CHECK`.
  INCOMPLETE      `Error: N TODOs found.` -- the file DECLARES that it is not a proof yet.
                  A file that says so is not a defect; it is a file that has not been finished.
  FOREIGN         `Error: N defs rely on unsafe or foreign code:` -- the file PARSES AND
                  TYPE-CHECKS and the SAFETY verdict is what fails, because a foreign def is
                  a promise the checker reads the type of and never the code of
                  (`references/bend/bend2/main.ts:824-829`). `tinybendygrad/runtime/autogen/
                  libclang.bend` (336) and `tinybendygrad/sz.bend` (7) are in this class.
  FINDING         anything else: a syntax or type error. THIS IS THE ONLY CLASS THAT FAILS.
  NO-MEASUREMENT  the run was killed, timed out, or could not start.

AND A SECOND LANE FOR THE TWO CLASSES THAT ARE NOT DEFECTS, because `--check-only` answers
a SAFETY question as well as a typing one: does the compiler EMIT C for the file at all?
So the two lanes together say what each word means:
  COMPILES        `--check-only` says `ALL PROOFS CHECK`.
  COMPILES-AS-C   the checker refuses for a PROMISE and the compiler still emits. The file
                  COMPILES; what the checker refused is the safety proof about the promise.
  COLD-BY-DESIGN  the checker's own standing classes, and the compiler does not emit for
                  them either. These are the tree's KNOWN cold files.
  FINDING         neither. THIS IS THE ONLY CLASS THAT FAILS.

**AND THE EMIT LANE HAS A THIRD ANSWER, WHICH IS NOT A REFINEMENT.** `checks/bounded.py`'s
own header says a run whose token is not `WITHIN-LIMITS` "PROVES NOTHING", and the first
draft of this file answered "does not emit" for a KILLED run -- the defect this file exists
to end, one level down. MEASURED, 2026-10-22, on `tinybendygrad/sz.bend`: the emit is
KILLED-ON-MEMORY at 2100 MB peak under a 2048 MB ceiling, at 4197 MB peak under a 4096 MB
ceiling, and UNBOUNDED it emits 3.4 MB of C and exits 0. **So "sz.bend does not compile"
is NOT what the census measured about it** -- "sz.bend's EMIT does not fit under the tree's
ceiling" is, and the two are different claims. The census therefore reports the kill in the
file's row and does NOT count it as a finding.

THE COUNT IS THE DELIVERABLE AND IT DEPENDS ON THE RULE, SO THE RULE IS PRINTED WITH IT.
MEASURED, 2026-10-22, over the 169 files under `tinybendygrad/`, AFTER the repair:
  compiled                                    165 of 169
  cold by design                               4 of 169  (LAWS, PROOF, PROOF2 -- the file
                                               declares it is not a proof yet -- and sz.bend,
                                               whose emit is over the tree's ceiling)
  a syntax or type error                       0 of 169
and BEFORE `tinybendygrad/runtime/support/autogen.bend` was repaired the same numbers were
163, 6 and 1. The file that moved them is the one whose `match` spelled three patterns for
one scrutinee.

ONE `bend` AT A TIME, ALWAYS, and the lock is taken PER INVOCATION (`gates/bendlock.py`),
because a gate that takes it once holds it for the whole sweep and every other unit waits for
the whole time -- MEASURED 2026-10-22, `checks/bendlock.sh -- <a gate that runs 11 bends>`
held the lock for 26 MINUTES.

THE COST IS PRINTED, BECAUSE A GATE THAT COMPILES 169 FILES IS HEAVY and a reader deserves
the number before deciding how often to run it. MEASURED: **142 s for 169 files, 0.84 s per
file, one bend at a time** (on 12 cores, with other units live). That is a NIGHTLY or
PRE-MERGE census, NOT a per-commit gate: at 0.84 s a file, a per-commit run over 169 files
spends two and a half minutes of a core, and `AGENTS.md`'s rule is on the SUM of concurrent
peaks, so a per-commit sweep is also the wrong SHAPE -- it re-measures 168 files that did not
change. The per-commit shape is a sweep over the CHANGED files, and the census is what says
which those are.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY, BOUNDED = ".venv/bin/python", "checks/bounded.py"
BEND = ROOT / "bin" / "bend"

# THE POPULATION DECLARATION AND THE ROUTER, LOADED BY PATH, NOT RE-TYPED.
_spec = importlib.util.spec_from_file_location("substrate", ROOT / "checks" / "substrate.py")
substrate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(substrate)          # module level only defines things

sys.path.insert(0, str(ROOT / "gates"))
from gatekit import NOTICE                    # noqa: E402  (the path has to exist first)
from bendlock import bend_lock                # noqa: E402

# `checks/bounded.py`'s OWN verdict token, read off stderr. MATCHED ANYWHERE IN THE LINE, NOT
# AT ITS START: `checks/substrate.py:302` re-emits the record with its own prefix, so an
# anchored pattern finds nothing and every file would read NO-MEASUREMENT -- a census
# silently measuring zero, which is the defect this file exists to end.
TOKEN = re.compile(r"\[bounded\] (?P<token>WITHIN-LIMITS|KILLED-ON-MEMORY|TIMED-OUT|"
                   r"NOT-STARTED|NO-VERDICT)\b")
# THE COMPILER'S OWN ERROR CLASSES. These are the strings `bin/bend --check-only` prints
# (`references/bend/bend2/main.ts:811-813` for the second), read as the SHAPE and not as a
# file name, so the standing classes MOVE with the files instead of rotting in a list here.
RE_INCOMPLETE = re.compile(r"^Error: \d+ TODOs? found\.")
RE_FOREIGN = re.compile(r"^Error: \d+ defs? rely on unsafe or foreign code:")

COMPILES, AS_C, COLD, FINDING, NOM = (
    "COMPILES", "COMPILES-AS-C", "COLD-BY-DESIGN", "FINDING", "NO-MEASUREMENT")
# THE TWO STANDING CLASSES, AS THE COMPILER SPELLS THEM. They are STATES here and
# PATTERNS above, so they have different names: the patterns say WHAT the error text is,
# the states say WHAT THE FILE IS.
ST_INCOMPLETE, ST_FOREIGN = "INCOMPLETE", "FOREIGN"
PASS, FAIL, REFUSED = 0, 1, 3
# THE FILES THAT ARE COLD BY DESIGN ARE THE ONES THAT DECLARE THEY ARE NOT A PROOF YET,
# or that bind a C library. BOTH CLASSES COME FROM THE COMPILER'S OWN ERROR TEXT, so the
# set MOVES with the files: a proof file whose TODOs land stops being cold, and a file
# that stops binding foreign code stops being foreign.
KNOWN = (COLD,)


def emits_c(path: str, mb: int, seconds: int) -> str:
    """DOES THE COMPILER EMIT C FOR THIS FILE? A second, cheaper-to-read question.

    `--check-only` answers a SAFETY question as well as a typing one: bend refuses a book
    whose defs RELY ON FOREIGN OR UNSAFE CODE (`references/bend/bend2/main.ts:824-829`: "A
    foreign def is a promise like @unsafe is: the checker reads its type, never its code").
    That refusal is a fact about the PROMISE, not about whether the file parses and
    type-checks, and `tinybendygrad/runtime/autogen/libclang.bend`'s own header says so:
    "`bend -o out.c` is rc=0 and `cc` links and runs it -- so the file COMPILES as C and
    CANNOT BE RUN."

    SO THE TWO LANES ARE ASKED, AND THEY DISAGREE ON PURPOSE: `--check-only` says
    `ALL PROOFS CHECK`, and the EMIT says whether the compiler can produce a program for
    the file at all.

    **AND THE THIRD ANSWER IS THE ONE THIS FUNCTION HAD TO LEARN.** It returns `YES`, `NO`
    or `NOT-MEASURED`, and the third is not a refinement: `checks/bounded.py`'s own header
    says a run whose token is not `WITHIN-LIMITS` "PROVES NOTHING", and the first draft of
    this function answered `NO` for a KILLED run -- which is the defect this file exists to
    end, one level down. MEASURED, 2026-10-22, on `tinybendygrad/sz.bend`: the emit is
    KILLED-ON-MEMORY at 2100 MB peak under a 2048 MB ceiling, at 4197 MB peak under a
    4096 MB ceiling, and UNBOUNDED it emits 3.4 MB of C and exits 0. So "sz.bend does not
    compile" is NOT what the census measured about it; "sz.bend's EMIT does not fit under
    the tree's ceiling" is, and the two are different claims.
    """
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "out.c"
        with bend_lock():
            p = subprocess.run([PY, BOUNDED, "--mb", str(mb), "--seconds", str(seconds),
                                "--", str(BEND), path, "-o", str(out)],
                               cwd=ROOT, capture_output=True, text=True,
                               env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"})
        tok = TOKEN.search(p.stderr)
        token = tok.group("token") if tok else "NO-TOKEN"
        if token != "WITHIN-LIMITS":
            return f"NOT-MEASURED ({token})"
        return "YES" if (out.is_file() and out.stat().st_size > 0 and p.returncode == 0) else "NO"


def population() -> list[str]:
    """EVERY file the BEND instrument judges, by `os.walk` over the population declaration."""
    out = []
    for d, dirs, fs in os.walk(substrate.POP_ROOT):
        dirs.sort()
        for f in sorted(fs):
            p = os.path.join(d, f)
            if substrate.instrument_for(p)[0] == "bend":
                out.append(p)
    return out


def verdict_of(stdout: str, stderr: str) -> tuple[str, str]:
    """The COMPILER's answer, joined the way `checks/substrate.py` joins it.

    Returns `(state, detail)`. stdout first, because that is the order `2>&1` gave, and
    the 42-byte update notice is not one of the two answers.

    THE CLASS IS THE `Error:` LINE, NOT THE FIRST LINE. MEASURED, and the first draft of
    this function got it wrong: it matched the error classes against the FIRST line, which
    is `SOME PROOFS FAIL` for every failure, so all five standing files came back as
    FINDING -- the census reporting the tree's KNOWN conditions as defects, which is the
    "a check that cannot be wrong because it cannot be anything" shape one level down. The
    compiler prints the class on the NEXT line (`Error: N TODOs found.`, `Error: N defs
    rely on unsafe or foreign code:`), and that is the line the class is read from.
    """
    said = [ln for ln in stderr.split("\n")
            if ln.strip() and not NOTICE.match(ln.strip())
            and not ln.startswith(("[bounded]", "  "))]
    merged = [ln for ln in stdout.split("\n") if ln] + said
    if not merged:
        return NOM, "the compiler said nothing"
    first = merged[0]
    if first.strip() == "ALL PROOFS CHECK":
        return COMPILES, first
    err = next((ln for ln in merged if ln.startswith("Error:")), first)
    if RE_INCOMPLETE.match(err):
        return ST_INCOMPLETE, err
    if RE_FOREIGN.match(err):
        return ST_FOREIGN, err
    return FINDING, err


def judge(path: str, mb: int, seconds: int) -> tuple[str, str, float]:
    """One file. Returns `(state, detail, seconds)`. The exit status is NOT read: the TOKEN
    is the verdict, and the status cannot mean one thing."""
    with bend_lock():
        p = subprocess.run([PY, BOUNDED, "--mb", str(mb), "--seconds", str(seconds),
                            "--", str(BEND), path, "--check-only"],
                           cwd=ROOT, capture_output=True, text=True,
                           env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"})
    tok = TOKEN.search(p.stderr)
    if not tok or tok.group("token") != "WITHIN-LIMITS":
        return NOM, (tok.group("token") if tok else "NO-TOKEN"), 0.0
    state, first = verdict_of(p.stdout, p.stderr)
    return state, first, 0.0


def census(mb: int, seconds: int, rows: Path) -> int:
    pop = population()
    if not pop:
        print(f"REFUSED: no file under {substrate.POP_ROOT}/ is judged by the bend instrument, "
              "so this run judged nothing and must not report agreement")
        return REFUSED
    tally: dict[str, int] = {}
    findings: list[str] = []
    unmeasured: list[str] = []
    started = time.monotonic()
    with rows.open("w") as fh:
        fh.write(f"# port-compile: one `bin/bend --check-only` per .bend under "
                 f"{substrate.POP_ROOT}/, ONE AT A TIME, under checks/bounded.py.\n")
        fh.write(f"# taken={time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}  "
                 f"population={len(pop)}  ceiling {mb} MB, {seconds} s each.\n")
        fh.write("# state= COMPILES | COMPILES-AS-C | COLD-BY-DESIGN | FINDING | NO-MEASUREMENT\n")
        fh.write("# COMPILES       `--check-only` says `ALL PROOFS CHECK`.\n")
        fh.write("# COMPILES-AS-C  the checker refuses for a PROMISE (the file binds foreign or\n")
        fh.write("#   unsafe code, or declares TODO) and the compiler STILL EMITS C for it.\n")
        fh.write("# COLD-BY-DESIGN the checker's own standing classes: `Error: N TODOs found.`\n")
        fh.write("#   (the file declares it is not a proof yet) or `Error: N defs rely on unsafe\n")
        fh.write("#   or foreign code:` (the file PARSES AND TYPE-CHECKS; the SAFETY verdict is\n")
        fh.write("#   what fails).  Only FINDING is a defect.\n")
        fh.write("state\tfile\tdetail\n")
        for i, path in enumerate(pop, 1):
            t0 = time.monotonic()
            state, detail, _ = judge(path, mb, seconds)
            dt = time.monotonic() - t0
            if state in (ST_INCOMPLETE, ST_FOREIGN):
                # THE SECOND LANE, and it is asked ONLY of the files the first lane did not
                # clear, so the extra cost is the size of the standing classes and not of
                # the population. THREE answers, and the third is not a refinement: a
                # KILLED emit is NOT MEASUREMENT, so it is REPORTED and not read as "does
                # not emit" -- but the file stays in the standing class it is in, because
                # the class came from the COMPILER'S OWN ERROR TEXT and not from the emit.
                em = emits_c(path, mb, seconds)
                if em == "YES":
                    state, detail = AS_C, f"{detail} -- AND THE COMPILER EMITS C FOR IT"
                elif em == "NO":
                    state, detail = COLD, f"{detail} -- and the compiler does NOT emit C"
                else:
                    state, detail = COLD, f"{detail} -- and the EMIT lane was {em}, so the EMIT " \
                                         f"is NOT a verdict about this file"
            tally[state] = tally.get(state, 0) + 1
            if state == FINDING:
                findings.append(f"{path} :: {detail}")
            if state == NOM:
                unmeasured.append(f"{path} :: {detail}")
            fh.write(f"{state}\t{path}\t{detail}\n")
            fh.flush()
            print(f"{state:<15} {path:<58} {dt:6.1f}s  {detail[:70]}", flush=True)
    total = time.monotonic() - started
    print()
    for k in (COMPILES, AS_C, COLD, FINDING, NOM):
        if k in tally:
            print(f"CENSUS      {k}={tally[k]}")
    compiled = tally.get(COMPILES, 0) + tally.get(AS_C, 0)
    print(f"DENOMINATOR population={len(pop)}  compiled={compiled}  "
          f"cold-by-design={tally.get(COLD, 0)}  findings={tally.get(FINDING, 0)}  "
          f"unmeasured={tally.get(NOM, 0)}")
    print(f"COST        {total:.1f}s for {len(pop)} file(s) = {total / max(len(pop), 1):.2f}s per "
          f"file, ONE bend at a time.  THIS IS HEAVY: it is a NIGHTLY or PRE-MERGE census, not a "
          f"per-commit gate.")
    print(f"ARTIFACT    {rows.relative_to(ROOT)}")
    for f in findings:
        print(f"FINDING     {f}")
    if unmeasured:
        for u in unmeasured:
            print(f"NO-MEASUREMENT {u}")
    if unmeasured:
        print(f"REFUSED: {len(unmeasured)} of {len(pop)} file(s) were NOT measured, so the counts "
              "above are not a verdict about the population")
        return REFUSED
    return FAIL if findings else PASS


# --------------------------------------------------------------------------- the plant
# THE PLANT IS A TEXT EDIT ON THE FILE AS IT STANDS NOW, NEVER A READ OF `git show HEAD:`.
# A plant that reads HEAD plants nothing the moment HEAD carries the defect's fix, and a unit
# measured exactly that: it scored green under `--falsify` because its plant had become a
# no-op. So the bytes come from the WORKING TREE, and the edit is applied to them.
PLANT_OLD = "    case +c1 <> rest: rep_go2(rest, List.append(&2, Char, acc, rep_emit2(pend, c1)), rep_next(pend, c1))"
PLANT_NEW = "    case c1 c2 rest: rep_go2(rest, List.append(&2, Char, acc, rep_emit2(pend, c1)), rep_next(pend, c1))"
SUBJECT = "tinybendygrad/runtime/support/autogen.bend"


def strip_comments(text: str) -> str:
    """The file with every `#` comment removed -- the PROOF that an edit is comment-only.

    A `#` inside a string is not a comment, and this file's strings carry `"` and `\\`, so the
    string literals are blanked FIRST, the way `checks/substrate.py:672-677` does it.
    """
    out = []
    in_str = False
    for ln in text.split("\n"):
        buf, i = [], 0
        while i < len(ln):
            ch = ln[i]
            if in_str:
                if ch == "\\":
                    buf.append(" " * 2)
                    i += 2
                    continue
                if ch == '"':
                    in_str = False
                buf.append(" ")
                i += 1
                continue
            if ch == '"':
                in_str = True
                buf.append(" ")
                i += 1
                continue
            if ch == "#":
                break
            buf.append(ch)
            i += 1
        # RSTRIPPED, because a comment-only edit necessarily leaves the whitespace that
        # preceded the `#`, and that whitespace is not code. MEASURED: without this, the
        # control below reads as "not comment-only" for a difference of two spaces, and a
        # control that is rejected for trailing whitespace is a control that proves nothing.
        out.append("".join(buf).rstrip())
    return "\n".join(out)


def plant() -> int:
    """The plant, the control, and the two wrong shapes of a comment-only edit."""
    src = ROOT / SUBJECT
    if not src.is_file():
        print(f"REFUSED: {SUBJECT} is absent, so there is nothing to plant into")
        return REFUSED
    original = src.read_text()
    if PLANT_OLD not in original:
        print(f"REFUSED: the plant's anchor line is not in {SUBJECT} as it stands. THE PLANT IS A "
              f"TEXT EDIT ON THE WORKING TREE, so an anchor that moved means the plant must be "
              f"re-anchored -- NOT that it should fall back to reading git.")
        return REFUSED
    lines = original.split("\n")
    idx = next(i for i, ln in enumerate(lines) if ln == PLANT_OLD)

    # 1. THE PLANT: the compile error put back, by a text edit on the working tree.
    planted = original.replace(PLANT_OLD, PLANT_NEW)
    # 2. THE CONTROL: a comment of the SAME SIZE on the SAME line. It must move nothing.
    control = original.replace(PLANT_OLD, PLANT_OLD + "  # control: a comment, same size, no code")

    cases = [
        ("PLANT", planted, "the compile error put back: `case c1 c2 rest:`"),
        ("CONTROL", control, "a comment of the same size on the same line"),
    ]
    # 3. THE TWO WRONG SHAPES OF A "COMMENT-ONLY EDIT", MEASURED, NOT ASSUMED. A control
    #    that edits more than it meant to is not a control, and the two shapes below are the
    #    ways that happens in THIS language.
    #
    #    SHAPE A -- a comment appended to the FIRST part of a line that carries two parts
    #    deletes the second. A bend `case` line carries a PATTERN and a BODY, and a `#` runs
    #    to the end of the line, so a comment inserted between them swallows the body and
    #    the arm is left empty. MEASURED, and the compiler's answer points at a DIFFERENT
    #    line -- the NEXT `case` -- because the empty arm is what it notices. That is the
    #    shape that makes a control look like it broke something else.
    two_part = next((ln for ln in lines if ln.startswith("    case ") and ": " in ln
                     and not ln.rstrip().endswith(":")), None)
    if two_part is not None:
        head, _, tail = two_part.partition(": ")
        a = list(lines)
        a[lines.index(two_part)] = f"{head}: # a comment appended to the pattern{tail}"
        cases.append(("WRONG-SHAPE-A (comment on the pattern, body on the same line)",
                      "\n".join(a), "the second part of a two-part line is DELETED"))
    else:
        print("WRONG-SHAPE-A  NOT APPLICABLE, AND THAT IS A MEASUREMENT: no line of "
              f"{SUBJECT} carries a pattern and a body on one line.")
    #
    #    SHAPE B -- a comment line inserted AT COLUMN 0 above an indented body. In bend
    #    this does NOT break the file: the parser skips whole-line comments, so the block
    #    below is untouched. MEASURED at three insertion points (above a def's body, above
    #    a match's first case, and at the top of the file) -- ALL THREE still compile. The
    #    shape is a property of the COMMENT STYLE, not of bend's parser, and the lesson
    #    survives: a control's edit must be PROVEN comment-only, and the proof is the
    #    comment-stripped bytes, not the compiler's verdict.
    indent = next((i for i, ln in enumerate(lines)
                   if i > 0 and ln.startswith("  ") and lines[i - 1].strip()
                   and not lines[i - 1].lstrip().startswith("#")), None)
    if indent is not None:
        b = list(lines)
        b.insert(indent, "# a comment inserted at column 0")
        cases.append((f"WRONG-SHAPE-B (column-0 comment above line {indent + 1})",
                      "\n".join(b), "a comment line at column 0, above an indented body"))
    else:
        print("WRONG-SHAPE-B  NOT APPLICABLE, AND THAT IS A MEASUREMENT: no indented body "
              f"follows a non-comment line in {SUBJECT}.")

    bad = 0
    for name, text, why in cases:
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / Path(SUBJECT).name
            p.write_text(text)
            state, detail, _ = judge(str(p), 2048, 300)
        # A COMMENT-ONLY EDIT IS PROVED BY THE COMMENT-STRIPPED BYTES, not by the verdict.
        same_code = strip_comments(text) == strip_comments(original)
        print(f"{name:<46} verdict={state:<14} comment-only={same_code!s:<5} {why}")
        print(f"{'':<46} :: {detail[:110]}")
        if name == "PLANT" and state != FINDING:
            print("  THE PLANT DID NOT FIRE: the check did not go red on the defect it plants.")
            bad += 1
        if name == "CONTROL" and (state != COMPILES or not same_code):
            print("  THE CONTROL IS NOT A CONTROL: it moved the verdict, or it edited more than a "
                  "comment.")
            bad += 1
    print(f"\n=== plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
    return FAIL if bad else PASS


def main() -> int:
    ap = argparse.ArgumentParser(prog="checks/port-compile-gate.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rows", default="checks/port-compile.rows")
    ap.add_argument("--mb", type=int, default=substrate.DEFAULT_MB)
    ap.add_argument("--seconds", type=int, default=substrate.SHELL_SECONDS)
    ap.add_argument("--plant", action="store_true")
    ap.add_argument("--file", default=None, help="judge ONE file and print its state")
    a = ap.parse_args()

    if not BEND.is_file():
        print("REFUSED: bin/bend is absent, so no file can be judged; a census over zero judged "
              "files is not a census")
        return REFUSED
    if a.plant:
        return plant()
    if a.file:
        state, detail, _ = judge(a.file, a.mb, a.seconds)
        print(f"{state}\t{a.file}\t{detail}")
        return FAIL if state == FINDING else (REFUSED if state == NOM else PASS)
    return census(a.mb, a.seconds, ROOT / a.rows)


if __name__ == "__main__":
    sys.exit(main())
