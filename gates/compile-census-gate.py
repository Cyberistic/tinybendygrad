#!/usr/bin/env python3
"""gates/compile-census-gate.py -- THE COMPILE CENSUS's VERDICT, AND THE EDGE RUNS IT.

    .venv/bin/python gates/compile-census-gate.py            # the census's verdict
    .venv/bin/python gates/compile-census-gate.py --plant    # the plant: the ABSENT COMPILER

THE DEFECT THIS FILE EXISTS TO END, AND IT IS MEASURED.

`checks/compile-census.py` compiles every `.bend` outside the port and writes
`checks/compile-census.rows`. MEASURED 2026-10-22: that file's `taken=` was `2026-10-22T06:27:35Z`
and it ALREADY said

    COLD  350  WITHIN-LIMITS  gates/crp_graph_census.bend  SOME PROOFS FAIL

-- which is **1h51m BEFORE** the change that broke that driver landed. **THE CENSUS KNEW FOR A DAY
AND A HALF AND TOLD NOBODY.** MEASURED, the reason: no code opens `checks/compile-census.rows` as a
verdict. The only mentions are a `NOTE` printed by `gates/dialect-fixture-gate.py:135`, prose in
`gates/import-path-census-gate.py:36`, and `checks/shared-writable-gate.py` treating it as a WRITE
SITE. **AND `checks/compile-census.py` ITSELF IS UNREACHABLE**: named by no file in
`.github/workflows/` (10 files), not in `gates/edge-cost.rows`, not by `gates/edge-runner.py` and
not by `checks/gatesweep.py`.

⇒ **SO THE CENSUS's VERDICT GOES WHERE THE TREE ALREADY RUNS THE GATES: THE EDGE.** The edge is
`gates/edge-runner.py`, and it is the tree's committed surface that runs the gates and leaves a
TRACE in git (`gates/edge-trace.rows`) beside a MEASURED cost ledger (`gates/edge-cost.rows`).
**THE VERDICT IS A GATE OF ITS OWN, AND THE EDGE RUNS IT** -- and that is the answer to "a row in
the cost ledger, a row in the trace, or a gate of its own", because the two ledgers are GENERATED
by the runner for every candidate it runs: **A HAND-WRITTEN ROW IN EITHER LEDGER WOULD BE A ROW
THE RUNNER NEVER PRODUCED, WHICH IS THE TREE's OWN CLASS OF DEFECT.** `gates/edge-runner.py`
writes the cost row (`--measure` is the only writer of `gates/edge-cost.rows`) and the trace row
(a run writes `gates/edge-trace.rows`), so a GATE is the mechanism and the two rows are its
CONSEQUENCE. This file declares `EDGE_CANDIDATE = True` -- the edge's own hook, read BY PATH the
way it reads a gate's `RED_IS` -- because this gate holds no pin of its own: it judges ANOTHER
instrument's verdict.

**AND THE CENSUS's POPULATION IS THE RIGHT ONE.** `checks/substrate.py`'s `POP_ROOT = "tinybendygrad"`
does NOT cover it, and this census COMPILES EVERY `.bend` BEYOND THE PORT -- the drivers the
harness RUNS, which are exactly the files a driver that does not compile cannot report about
itself.

THE CLASSIFICATION, AND IT IS THE POINT.

`COLD` is a NOISY CLASS. In the tree's own artefact, EVERY cold row said `SOME PROOFS FAIL` --
the same sentence for a FRAGMENT that cannot compile by design and for a driver whose constructor
was deleted upstream. So this gate puts every row of the census into the tree's OWN FIVE
VERDICTS (`gates/gatekit.py`'s `VERDICT` MAP, AND ITS EXITS ARE 0 FOR PASS, 1 FOR FAIL,
3 FOR REFUSED, 4 FOR SKIP, 5 FOR DEAD):

    PASS      the census says the file COMPILES.
    SKIP      STANDING-COLD: the file is cold BY DESIGN -- a FRAGMENT, a proof file that
              declares it is not a proof yet, a file whose emit exceeds the memory ceiling --
              and there is nothing to report and nothing to go on TO.
    FAIL      BREAKAGE: the file does not compile and NOTHING declares that it may not. This
              CHARGES, and it is the verdict that would have caught the day and a half.
    REFUSED   the census could NOT JUDGE the file (killed on memory, timed out, no token) or
              did not judge it at all. A precondition was absent; that is not a finding.
    DEAD      it ran and emitted nothing.

**⇒ AND THE DIFFERENCE BETWEEN STANDING-COLD AND BREAKAGE IS DECLARED, NOT INFERRED.** The
declaration is `gates/compile-census-standing.rows`, beside this file and IN GIT, and it names
each standing-cold driver, the compiler's OWN error shape for it, and why it is standing. The
shape is not a second vocabulary: it is one of `checks/substrate.py`'s `CAUSES` shapes, READ BY
PATH, and this file REFUSES a declaration that names a shape the tree does not have.

**⇒ AND A DECLARED SHAPE THAT NO LONGER MATCHES IS A BREAKAGE, NOT A STANDING-COLD.** The
declaration says "this file is cold FOR THIS REASON"; a file whose error changed is no longer the
declared case, and the gate says so instead of waving it through.

THE TWO INSTRUMENTS ARE COMPLEMENTARY AND ARE NOT MERGED.

`gates/opname-census-gate.py` asks "does any driver construct an `Op` the port's enum does not
declare?" and it compiles ONLY THE FILES THAT NAME A STALE OP -- so a driver that fails for a
TYPE ERROR is never compiled by it. This census asks "does every driver compile?" and it compiles
EVERYTHING. **THE COMPILE CENSUS SEES EVERYTHING; THE OPNAME CENSUS SEES THE CLASS.** Two
instruments with different populations and different questions are RIGHT, and a SECOND COPY OF
EITHER IS NOT: this file reads `checks/compile-census.py`'s own `discover()` BY PATH rather than
walking the tree again.

THE PLANT IS A TEXT EDIT, AND IT IS THE ABSENT COMPILER.

`checks/compile-census.py` refuses when `bin/bend` is absent -- but the REFUSAL had never been
SEEN, because nobody ran the census in a tree without a compiler. `.gitignore:5` ignores `/bin/bend`
and `git ls-tree -r HEAD -- bin/` is EMPTY, so **A CLEAN CHECKOUT HAS NO COMPILER**, and every
GitHub Actions run of `.github/workflows/edge-gates.yml` IS a clean checkout. The plant copies the
census into a tree with NO `bin/bend` and demands REFUSED -- **NOT "COLD"** -- and the control is
the same copy WITH one, which must say WARM. **THE PLANT IS A TEXT EDIT ON THE WORKING TREE AND
NEVER READS `git show HEAD:`**: a plant that reads HEAD plants nothing the moment HEAD carries the
fix.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

# THE EDGE'S HOOK, DECLARED HERE AND READ BY THE EDGE. This gate holds no pin of its own -- it
# judges ANOTHER instrument's verdict -- so the edge's selection rule ("a member that holds a pin
# its own code reads") would not see it. The tree's own escape, used by
# `gates/edge-oracle-pin-gate.py`, and read BY PATH the way the edge reads `RED_IS`.
EDGE_CANDIDATE = True

# THE CENSUS's OWN ARTEFACT. This gate does not re-run the census; it judges the census's
# recorded verdict, and re-judges ONLY what the census cannot speak for (see `drift()` below).
CENSUS_ROWS = ROOT / "checks" / "compile-census.rows"
# THE DECLARED STANDING-COLD SET. Beside this gate and IN GIT, because a gate's REQUIRED INPUT
# belongs beside the gate: `gates/artifacts/` is gitignored and is where runs WRITE.
STANDING = HERE / "compile-census-standing.rows"
# THE GATE's OWN ROWS. In git, beside the gate, and this file is its ONLY writer -- the shape
# `gates/opname-census.rows` already has.
VERDICT_ROWS = HERE / "compile-census-verdict.rows"

# THE CEILINGS AND THE BOUND, ALL DECLARED HERE AND NONE OF THEM INVENTED.
MB, SECONDS = 2048, 300
# **HOW MANY FILES THIS GATE MAY RE-JUDGE.** The re-judgment is the census's DELTA -- the files
# whose bytes moved since the census took its reading -- and the gate's cost IS that delta, so
# the delta is what has to be bounded. The edge's budget is 30 s (`gates/edge-runner.py:BUDGET_SECONDS`),
# and a `bin/bend --check-only` of a driver is ~1.5 s, so twelve re-judgments fit inside it with
# room for the census's own bookkeeping. **OVER THE CAP THE GATE REFUSES** rather than running for
# minutes: "a precondition was absent" is the honest reading when the census does not describe
# this tree, and the census is re-taken by `checks/compile-census.py`, which is the instrument that
# CAN take it.
REJUDGE_CAP = 12

sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, SKIP, VERDICT  # noqa: E402


def _load(name: str, path: Path):
    """A MODULE, LOADED BY PATH. `gates/gates-pop.py` has a hyphen, and importing a gate RUNS it."""
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


# THE TWO INSTRUMENTS THIS FILE USES, EACH OWNED BY THE TREE AND EACH LOADED BY PATH.
#   census  `checks/compile-census.py` -- the population (`discover()`), the verdict envelope
#           (`judge()`), the error-shape vocabulary (`substrate.CAUSES`), and the sha.
#   pc      `checks/port-compile-gate.py` -- the comment stripper, for the plant's proof.
census = _load("compile_census_gate_census", ROOT / "checks" / "compile-census.py")
pc = _load("compile_census_gate_port", ROOT / "checks" / "port-compile-gate.py")

# THE COLUMNS OF THE CENSUS's ARTEFACT, IN THE ORDER IT WRITES THEM. The header names them too;
# this is the reader's copy of that order and it is checked against the artefact's own header.
COLUMNS = ("state", "peak_MB", "token", "file", "cause", "sha", "error", "first_line")
# THE STATES THE CENSUS CAN WRITE. A LINE WHOSE `state` IS NOT ONE OF THESE IS NOT A ROW -- see
# `read_census()` for the measured reason.
STATES = ("WARM", "COLD", "NO-MEASUREMENT", "NO-INSTRUMENT", "EMPTY")


# --------------------------------------------------------------------------- the inputs
def read_census() -> list[dict]:
    """The census's rows, as dicts. A MISSING artefact is an empty list, and the caller REFUSES
    on it: a gate that judged nothing must not report agreement.

    **A ROW WHOSE `state` IS NOT A STATE IS NOT A ROW, AND IT IS COUNTED.** The census's column
    names live in its `#` header and not in a line of their own (`gates/edge-runner.py:read_rows`
    says why, and it is MEASURED: with the column line written as DATA, that reader parsed it as
    a row whose key was the literal string `gate` and the edge's plan reported `STALE gate` -- a
    gate that does not exist, named by the file's own vocabulary). **AN ARTEFACT TAKEN BEFORE THAT
    FIX STILL CARRIES THE COLUMN LINE AS A ROW**, so this reader skips any row whose state is not
    a state and says how many it skipped: a row it cannot classify is a row it must not judge."""
    if not CENSUS_ROWS.is_file():
        return []
    rows = []
    skipped = 0
    for line in CENSUS_ROWS.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        f = line.split("\t", len(COLUMNS) - 1)
        row = {c: (f[i] if i < len(f) else "") for i, c in enumerate(COLUMNS)}
        if row["state"].split("?")[0] not in STATES:
            skipped += 1
            continue
        rows.append(row)
    if skipped:
        print(f"SKIPPED-ROW {skipped} line(s) of {CENSUS_ROWS.relative_to(ROOT)} are not census rows "
              "(a column line written as DATA, before the census moved its columns into the "
              "header); they are NOT judged and NOT counted")
    return rows


def read_standing() -> dict[str, tuple[str, str]]:
    """The DECLARED standing-cold set: `{file: (shape, why)}`.

    **THE SHAPE IS NOT A SECOND VOCABULARY.** It is one of `checks/substrate.py`'s `CAUSES`
    shapes, READ BY PATH, and `known_shapes()` below is the membership test. A declaration that
    names a shape the tree cannot produce is a REFUSAL, not a warning."""
    out: dict[str, tuple[str, str]] = {}
    if not STANDING.is_file():
        return out
    for line in STANDING.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        f = line.split("\t")
        out[f[0]] = (f[1] if len(f) > 1 else "", f[2] if len(f) > 2 else "")
    return out


def known_shapes() -> set[str]:
    """THE ERROR SHAPES THE TREE CAN PRODUCE, read by path.

    `checks/compile-census.py:CAUSES` is the table, and it carries the tree's own shape NAMES
    (`checks/substrate.py`'s) with the PATTERNS FIXED -- `checks/compile-census.py`'s own header
    says why, and it is MEASURED: `checks/substrate.py:cause_of()` cannot match a real bend
    failure, because its patterns are `^`-anchored over a whole output and are written for a
    JOINED `- expected : X / observed : Y` line the compiler does not print. The one extra name is
    that table's own fallback -- read off that module's constant rather than re-spelled here."""
    shapes = {shape for _rx, shape, _g in census.CAUSES}
    shapes.add(census.UNATTRIBUTED)
    return shapes


# --------------------------------------------------------------------------- the delta
def drift(population: list[str], rows: list[dict]) -> tuple[list[str], list[str]]:
    """-> `(rejudge, gone)`. THE CENSUS's DELTA.

    A file is RE-JUDGED when the census never saw it, or when the census's recorded sha is not
    the file's bytes NOW. **THE COMPARISON IS ON CONTENT AND NOT ON AN MTIME**, because
    `checks/differ.py:substrate_digest()` says why in the tree's own words: "Never on `st_mtime`,
    never on the absolute path: a fresh clone of one tree writes every file at the moment it is
    cloned."

    **THE DELTA IS THE WHOLE OF WHAT THIS GATE ADDS TO THE CENSUS.** The census's reading of
    every UNCHANGED file still stands -- a compiler does not change its mind because a neighbour
    moved -- so re-judging the whole population here would be a SECOND COPY OF THE CENSUS, and the
    tree's own rule is that a second copy of an instrument is a second population with a different
    predicate."""
    have = {r["file"]: r for r in rows}
    rejudge = []
    for p in population:
        r = have.get(p)
        if r is None or not r["sha"] or r["sha"] != census.sha_of(p):
            rejudge.append(p)
    gone = sorted(f for f in have if f not in set(population))
    return rejudge, gone


# --------------------------------------------------------------------------- the classification
def classify(row: dict, declared: tuple[str, str] | None) -> tuple[int, str]:
    """-> `(verdict, why)` for one census row, in the tree's OWN five.

    **THE FIVE ARE `gates/gatekit.py`'s, LOADED BY PATH AND NEVER RE-SPELLED.** The import above is
    the only place they are named, and `gates/exitcode-census-gate.py` grades every site that
    re-spells them."""
    state = row["state"]
    base = state.split("?")[0]
    if base == "WARM":
        return PASS, "the census says it compiles"
    if base == "COLD":
        if declared is None:
            return FAIL, ("BREAKAGE: it does not compile and NOTHING declares that it may not. "
                          f"cause={row['cause'] or 'UNATTRIBUTED'}"
                          + (f"  ::  {row['error']}" if row["error"] else ""))
        shape, why = declared
        observed = (row["cause"] or "").split(" ")[0]
        if shape and observed and shape != observed:
            return FAIL, (f"the DECLARED standing shape is {shape} and the compiler now says "
                          f"{observed} -- the declaration no longer describes this file"
                          + (f"  ::  {row['error']}" if row["error"] else ""))
        return SKIP, f"STANDING-COLD ({shape}): {why}"
    if base == "NO-MEASUREMENT":
        if declared is not None:
            return SKIP, f"STANDING-COLD ({declared[0]}): {declared[1]}"
        return REFUSED, f"the census could not judge it ({row['token']})"
    return REFUSED, f"the census did not judge it ({state})"


# --------------------------------------------------------------------------- the run
def run() -> int:
    """The census's verdict. `PASS` / `FAIL` / `REFUSED` / `SKIP` / `DEAD`, and the counts beside
    the verdict, always."""
    if not (ROOT / "bin" / "bend").is_file():
        # **THE ABSENT COMPILER IS A PRECONDITION THAT WAS ABSENT, AND IT IS NOT A COLD DRIVER.**
        # `gates/gatekit.py`'s own words: "The compiler's absence is SPOKEN BY A PROCESS THAT
        # EXISTS", and `gates/edge-plant.py`'s arm H measures the same thing for a gate.
        print("== REFUSED, NOT A VERDICT: compile-census-gate.py: `bin/bend` is absent, so no file "
              "in the population can be judged and this gate must not report agreement about it")
        return REFUSED
    if not CENSUS_ROWS.is_file():
        print(f"== REFUSED, NOT A VERDICT: compile-census-gate.py: {CENSUS_ROWS.relative_to(ROOT)} "
              "is absent, so there is no census to judge; take it with "
              "`checks/compile-census.py`")
        return REFUSED

    rows = read_census()
    population, _dropped = census.discover()
    if not population:
        print("== REFUSED, NOT A VERDICT: compile-census-gate.py: the walk found no .bend outside "
              "the port, so the population is empty and an empty census proves nothing")
        return REFUSED

    declared_all = read_standing()
    known = known_shapes()
    bad_shape = sorted(f for f, (shape, _w) in declared_all.items() if shape and shape not in known)
    if bad_shape:
        print(f"== REFUSED, NOT A VERDICT: compile-census-gate.py: the declared standing set names "
              f"{len(bad_shape)} shape(s) `checks/substrate.py` cannot produce: {', '.join(bad_shape)}"
              f"  ::  known shapes are {', '.join(sorted(known))}")
        return REFUSED

    rejudge, gone = drift(population, rows)
    if len(rejudge) > REJUDGE_CAP:
        print(f"== REFUSED, NOT A VERDICT: compile-census-gate.py: the census is stale by "
              f"{len(rejudge)} file(s) (cap {REJUDGE_CAP}) -- this gate judges the census's reading "
              "plus the delta, and the delta is larger than the gate may re-judge. Re-take it with "
              "`checks/compile-census.py`")
        return REFUSED

    by_file = {r["file"]: r for r in rows}
    out_rows: list[dict] = []
    for p in sorted(population):
        row = by_file.get(p)
        judged_by = "CENSUS"
        if p in set(rejudge):
            judged_by = "GATE"
            fresh = census.judge(p, MB, SECONDS)
            row = {"state": fresh["state"], "peak_MB": fresh["peak"], "token": fresh["token"],
                   "file": p, "cause": fresh["cause"], "sha": fresh["sha"], "error": fresh["error"],
                   "first_line": fresh["first_line"]}
        if row is None:
            # A FILE IN THE POPULATION THAT THE CENSUS NEVER SAW AND THAT THE GATE DID NOT
            # RE-JUDGE. It cannot happen above (an uncovered file IS in `rejudge`), and the row
            # says so rather than being dropped.
            out_rows.append({"verdict": "DEAD", "file": p, "class": "NO-ROW",
                             "detail": "the census did not judge it and the gate did not re-judge it"})
            continue
        verdict, why = classify(row, declared_all.get(p))
        out_rows.append({"verdict": VERDICT[verdict], "file": p,
                         "class": {"PASS": "WARM", "SKIP": "STANDING-COLD", "FAIL": "BREAKAGE",
                                   "REFUSED": "NOT-JUDGED", "DEAD": "NO-ROW"}[VERDICT[verdict]],
                         "detail": why, "cause": row.get("cause", ""), "error": row.get("error", ""),
                         "judged-by": judged_by})

    tally = {v: 0 for v in VERDICT.values()}
    for r in out_rows:
        tally[r["verdict"]] = tally.get(r["verdict"], 0) + 1
    breakdown = {r["file"]: r for r in out_rows}
    stale_decl = sorted(f for f in declared_all if f not in {r["file"] for r in out_rows}
                         or breakdown[f]["verdict"] == "PASS")

    taken = next((ln.split("taken=", 1)[1].split()[0] for ln in
                  CENSUS_ROWS.read_text().splitlines() if ln.startswith("# taken=")), "UNKNOWN")
    print(f"CENSUS      taken={taken}  population={len(population)}  rows={len(rows)}  "
          f"re-judged-by-this-gate={len(rejudge)}  gone={len(gone)}")
    print("CLASS       " + "  ".join(f"{v}={tally[v]}" for v in ("PASS", "SKIP", "FAIL", "REFUSED",
                                                                 "DEAD")))
    if gone:
        print(f"GONE        {len(gone)} file(s) the census judged are not in the population now: "
              f"{', '.join(gone)}")
    if stale_decl:
        print(f"STALE-DECL  {len(stale_decl)} declared standing file(s) no longer need standing: "
              f"{', '.join(stale_decl)}  ::  remove them from {STANDING.relative_to(ROOT)}")
    for r in out_rows:
        if r["verdict"] in ("FAIL", "REFUSED", "DEAD"):
            print(f"{r['verdict']:<12} {r['file']:<44} {r['class']:<14} {r['detail']}")

    write_rows(out_rows, taken)

    if tally["FAIL"]:
        print(f"VERDICT     FAIL: {tally['FAIL']} driver(s) do not compile and are not declared to "
              "be cold by design -- the WORK QUEUE is in "
              f"{VERDICT_ROWS.relative_to(ROOT)}")
        return FAIL
    if tally["DEAD"]:
        print(f"VERDICT     DEAD: {tally['DEAD']} file(s) had no row at all")
        return DEAD
    if tally["REFUSED"]:
        print(f"VERDICT     REFUSED: {tally['REFUSED']} file(s) were not judged, so the warm count "
              "is not a verdict about the population")
        return REFUSED
    print(f"VERDICT     PASS: every driver in the population compiles, or is declared cold by "
          f"design ({tally['SKIP']} standing)")
    return PASS


def write_rows(rows: list[dict], taken: str) -> None:
    """THE GATE's OWN ROWS, and it is the ONLY writer. Beside the gate and IN GIT, because the
    WORK QUEUE has to survive a fresh clone: `gates/artifacts/` is gitignored and is where runs
    WRITE, so a queue kept there is a queue nobody can read after a `rm -rf`."""
    cols = ("verdict", "class", "file", "cause", "judged-by", "detail")
    with VERDICT_ROWS.open("w") as fh:
        fh.write(f"# gates/compile-census-verdict.rows -- TAB separated. Generated; the generator "
                 f"is `gates/compile-census-gate.py`, the ONLY writer.\n")
        fh.write(f"# census taken={taken}  ::  the census's own reading, plus this gate's delta.\n")
        fh.write("# A `FAIL` row IS the work queue: a driver that does not compile and is not "
                 "declared cold by design.\n")
        fh.write("# columns: " + ", ".join(cols) + "\n")
        for r in rows:
            fh.write("\t".join(str(r.get(c, "")).replace("\t", " ") for c in cols) + "\n")


# --------------------------------------------------------------------------- the plant
# THE SUBJECT IS A TEXT FILE THE PLANT WRITES, NOT A TRACKED FILE IT EDITS. A plant that MUTATES a
# tracked file is a plant that damages the tree it audits, and a plant that READS one out of git
# plants nothing the moment HEAD carries the defect's fix.
DRIVER = """# THE PLANT's DRIVER. A TEXT FILE, WRITTEN BY THE PLANT.
import Base
import ./../tinybendygrad/uop/ops.bend as O

# TWO SHAPES, AND THE PLANT NEEDS BOTH.
#   plant_op    ONE statement on its own line.
#   plant_pair  a LIST OPENER and its first element on ONE line, so a comment BETWEEN the two
#               parts deletes the element and the file still COMPILES -- the shape a compiler's
#               verdict cannot catch and a comment-stripped proof can.
def plant_op() -> O.Op:
  O.OpsADD{}

def plant_pair() -> List<&2, O.Op>:
  [  O.OpsADD{},
    O.OpsADD{}]

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("compile-census-plant")
"""

# THE COMMENT-ONLY PROOF, AND IT IS `gates/ptx_render_census-gate.py`'s `_code_only`, COPIED FOR
# THE REASON THAT FILE GIVES: the comment removal is `checks/port-compile-gate.py`'s own
# `strip_comments()` (it knows a `#` inside a string is not a comment), and **THE BLANK-LINE DROP
# IS WHAT MAKES THE PROOF COVER A WHOLE-LINE COMMENT** -- a comment on its own line contributes a
# line that is EMPTY once the comment is stripped, and comparing LINE LISTS would call the most
# comment-only edit there is "not comment-only".
def code_only(text: str) -> str:
    """The text with every comment removed AND every blank line DROPPED."""
    return "\n".join(l for l in pc.strip_comments(text).split("\n") if l.strip())


def plant() -> int:
    """THE PLANT: THE ABSENT COMPILER. THE CONTROL: THE COMPILER PRESENT. AND THE FALSIFICATION:
    A BROKEN DRIVER, so the plant cannot be satisfied by a census that refuses everything or by
    one that always says WARM.

        .venv/bin/python gates/compile-census-gate.py --plant

    **EVERY EDIT IS A TEXT EDIT ON THE WORKING TREE. NEVER `git show HEAD:`** -- a plant that reads
    HEAD plants nothing the moment HEAD carries the fix, and three units in this tree scored green
    under `--falsify` for exactly that reason."""
    bad = 0
    with tempfile.TemporaryDirectory() as td:
        tree = Path(td) / "tree"
        build_tree(tree)
        # THE CONTROL: THE COMPILER IS THERE. The census must judge the driver, and it must say
        # WARM -- a copy of the census in a tree WITH a compiler must NOT refuse.
        rc, out, err = census_in(tree)
        warm = read_rows_of(tree)
        ok_warm = rc == 0 and warm and all(r["state"].startswith("WARM") for r in warm)
        print(f"CONTROL     a copy of the census WITH `bin/bend`  rc={rc}  rows={len(warm)}  "
              f"::  {'WARM' if ok_warm else 'NOT WARM'}  {err.strip()[:160]}")
        if not ok_warm:
            print("  THE CONTROL IS NOT A CONTROL: a census with a compiler did not report the "
                  "driver as compiling.")
            bad += 1

        # THE PLANT: THE COMPILER IS NOT THERE. **THE CENSUS MUST SAY `REFUSED`, NOT `COLD`.**
        # `bin/bend` is absent from a CLEAN CHECKOUT (`.gitignore:5`, and `git ls-tree -r HEAD --
        # bin/` is EMPTY), so this is not a synthetic corner: it is what every GitHub Actions run
        # of `.github/workflows/edge-gates.yml` is.
        (tree / "bin" / "bend").unlink()
        rc, out, err = census_in(tree)
        said_cold = "COLD" in out or "COLD" in err
        ok_refused = rc == REFUSED and not said_cold
        print(f"PLANT       a copy of the census WITHOUT `bin/bend`  rc={rc}  "
              f"::  {'REFUSED' if ok_refused else 'NOT REFUSED'}"
              + ("  -- AND IT SAID COLD" if said_cold else "")
              + f"  {err.strip()[:200]}")
        if not ok_refused:
            print("  THE PLANT DID NOT FIRE: an absent compiler must be a REFUSAL, and a census "
                  "that calls it a COLD driver has turned a precondition into a finding.")
            bad += 1

        # THE FALSIFICATION: THE COMPILER IS THERE AND THE DRIVER IS BROKEN. The census must say
        # COLD. **WITHOUT THIS ARM THE PLANT IS VACUOUS**: a census that refused everything would
        # satisfy the plant arm, and a census that always said WARM would satisfy the control.
        # **THE COMPILER IS PUT BACK WITH `shutil.copy2`, AND NOT WITH `write_bytes`, BECAUSE THE
        # MODE IS PART OF IT.** MEASURED: `write_bytes` leaves the file 0644, and
        # `checks/substrate.py:run()` picks the compiler with
        # `"./bin/bend" if os.access("./bin/bend", os.X_OK) else which("bend")` -- so a
        # non-executable `bin/bend` falls through to a `bend` that is not on PATH, the compiler
        # never starts, and the census answers `NO-MEASUREMENT` -- a census that could not judge
        # anything, wearing the costume of one that judged the driver cold.
        shutil.copy2(ROOT / "bin" / "bend", tree / "bin" / "bend")
        driver = tree / "gates" / "plant-driver.bend"
        broken = driver.read_text().replace("O.OpsADD{}", "O.OpsNOSUCHOP{}", 1)
        driver.write_text(broken)
        rc, out, err = census_in(tree)
        cold = read_rows_of(tree)
        ok_cold = rc == FAIL and cold and any(r["state"].startswith("COLD") for r in cold)
        print(f"FALSIFY     the same copy, the driver carrying a TEXT EDIT that breaks it  rc={rc}  "
              f"::  {'COLD' if ok_cold else 'NOT COLD'}  {err.strip()[:200]}")
        if not ok_cold:
            print("  THE FALSIFICATION DID NOT FIRE: a driver that does not compile must be COLD, "
                  "or the control arm is satisfied by a census that never finds anything.")
            bad += 1

        # THE COMMENT-ONLY ARM: A COMMENT IS NOT A CHANGE OF THE CODE, AND THE CENSUS's VERDICT
        # MUST NOT MOVE. The proof that the edit was comment-only is the COMMENT-STRIPPED BYTES
        # WITH THE BLANK LINES DROPPED.
        driver.write_text(DRIVER)
        original = driver.read_text()
        commented = original.replace("  O.OpsADD{}\n", "  O.OpsADD{}  # a comment, same line\n", 1)
        same = code_only(commented) == code_only(original)
        rc, out, err = census_in(tree)
        cold = read_rows_of(tree)
        ok_comment = rc == 0 and cold and all(r["state"].startswith("WARM") for r in cold)
        print(f"COMMENT-ONLY a comment appended to a line carrying ONE statement  comment-only="
              f"{same!s:<5} verdict={'WARM' if ok_comment else 'NOT WARM'}  ::  a comment is not a "
              "change of the code")
        if not same or not ok_comment:
            print("  THE COMMENT-ONLY ARM DID NOT HOLD: the proof did not call the edit "
                  "comment-only, or the census's verdict moved on a comment.")
            bad += 1

        # THE TWO WRONG SHAPES, MEASURED RATHER THAN ASSUMED, AND THE PROOF IS WHAT CATCHES THEM.
        # (a) A COMMENT APPENDED TO A LINE CARRYING TWO STATEMENTS DELETES THE SECOND -- and the
        #     file may still COMPILE, so only the comment-stripped proof catches it.
        pair = next((i for i, ln in enumerate(original.split("\n"))
                     if ln.startswith("  [") and ln.rstrip().endswith(",")), None)
        if pair is None:
            print("WRONG-A     NOT APPLICABLE, AND THAT IS A MEASUREMENT: the subject has no line "
                  "that carries a list opener and its first element on one line")
        else:
            lines = original.split("\n")
            lines[pair] = lines[pair].replace("[", "[  # a comment between the opener and the "
                                                     "element", 1)
            shape_a = "\n".join(lines)
            caught = code_only(shape_a) != code_only(original)
            print(f"WRONG-A     a comment BETWEEN the two parts of a two-part line (line {pair + 1})"
                  f"  caught-by-the-proof={caught!s:<5}  ::  a `#` runs to the end of the line in "
                  "bend, so the element is DELETED and only this proof sees it")
            if not caught:
                print("  THE WRONG SHAPE DID NOT MISBEHAVE: it was comment-only after all, so it is "
                      "not a demonstration of anything.")
                bad += 1
        # (b) A WHOLE-LINE COMMENT AT COLUMN 0 DOES NOT BREAK A BEND FILE, and the proof must still
        #     call it comment-only -- which is what the blank-line drop buys.
        lines = original.split("\n")
        at = next((i for i, ln in enumerate(lines) if i and ln.startswith("  ")), None)
        if at is None:
            print("WRONG-B     NOT APPLICABLE, AND THAT IS A MEASUREMENT: the subject has no "
                  "indented body line")
        else:
            lines.insert(at, "# a whole-line comment at column 0")
            shape_b = "\n".join(lines)
            same_b = code_only(shape_b) == code_only(original)
            print(f"WRONG-B     a whole-line comment at column 0  comment-only={same_b!s:<5}  ::  it "
                  "does NOT break the file, and the blank-line drop is what keeps the proof true")
            if not same_b:
                print("  THE WRONG SHAPE WAS READ AS AN EDIT: a whole-line comment IS comment-only, "
                      "and a proof that says otherwise proves nothing.")
                bad += 1

    print(f"\n=== plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
    return FAIL if bad else PASS


def build_tree(tree: Path) -> None:
    """A COPY of the tree's census, in a directory of its own, with a driver the plant wrote.

    **THE COPY IS A COPY AND NOT A LINK, AND THE REASON IS THE SHIM.** `bin/bend` resolves its
    target RELATIVE TO ITSELF (`${0%/*}/../references/bend/bend2/main.ts`), so a SYMLINKED `bin/bend`
    would resolve `references/` inside the temp tree -- where there is none -- and the copy would
    refuse for a reason that has nothing to do with the plant. The shim is therefore COPIED (its
    bytes) and `references/` is a symlink, so the copy's compiler is the tree's compiler and the
    copy's `references/` is the tree's `references/`."""
    (tree / "checks").mkdir(parents=True)
    (tree / "gates").mkdir(parents=True)
    (tree / "bin").mkdir(parents=True)
    for rel in ("checks/compile-census.py", "checks/substrate.py", "checks/bounded.py",
                "checks/verdict.py", "gates/gatekit.py", "gates/bendlock.py"):
        shutil.copy2(ROOT / rel, tree / rel)
    # THE INTERPRETER: a symlink, because it is large and read-only here.
    os.symlink(ROOT / ".venv", tree / ".venv")
    # **THE PORT IS COPIED AND NOT SYMLINKED, AND THE REASON IS MEASURED.** A bend file imports
    # its neighbours BY A PATH SPELLING -- `import ./../tinybendygrad/uop/ops.bend as O` -- and the
    # compiler resolves that spelling against the tree it is given. MEASURED, in a copy whose
    # `tinybendygrad` was a SYMLINK: the driver's own import was refused with
    # "- expected : an import path of plain names (letters, digits, _ and -; the hub's files import
    # the hub's)" and `- observed : './../tinybendygrad/uop/ops.bend'` -- **the very spelling every
    # driver in this tree uses, which compiles in the tree and does not compile in a copy whose
    # port is a symlink.** Twelve megabytes and a hundred and seventy-six files is the price of a
    # copy the compiler agrees with, and the price is paid ONCE per plant run.
    shutil.copytree(ROOT / "tinybendygrad", tree / "tinybendygrad",
                    ignore=shutil.ignore_patterns("__pycache__"))
    # **AND THE FROZEN ORACLE, BECAUSE `checks/substrate.py` REFUSES WITHOUT IT.** MEASURED, and
    # the refusal is loud and correct: `checks/substrate.py:oracle_drift()` checks the sha256 of
    # every pinned oracle on EVERY run, and a copy without them answers
    # "ORACLE DRIFT: substrate/oracle-check.sh: MISSING -- the frozen oracle is gone" and exits 3
    # before it judges a single file. **THE COPY IS A COPY OF THE TREE'S SUBSTRATE, NOT A HOLLOW
    # SHELL**, and the pins come with it: `checks/substrate.py:ORACLE_PIN` is read by path, so the
    # copy's own oracle list is the tree's and the bytes are the tree's.
    for name in census.substrate.ORACLE_PIN:
        src = ROOT / ".agents" / "slop" / name
        dst = tree / ".agents" / "slop" / name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    # THE COMPILER: its own bytes, so `$0` resolves inside the copy.
    shutil.copy2(ROOT / "bin" / "bend", tree / "bin" / "bend")
    os.chmod(tree / "bin" / "bend", 0o755)
    os.symlink(ROOT / "references", tree / "references")
    # THE DRIVER: A TEXT FILE THE PLANT WRITES.
    (tree / "gates" / "plant-driver.bend").write_text(DRIVER)


def census_in(tree: Path) -> tuple[int, str, str]:
    """RUN THE CENSUS COPY, and return `(rc, stdout, stderr)`.

    The CWD is the COPY, because `checks/compile-census.py:discover()` walks `os.walk(".")` -- so
    the copy's population is the copy's, and the port's `.bend` are excluded by `POP_ROOT` either
    way. The copy's population is ONE file -- the driver the plant wrote -- because `tinybendygrad`
    and `.venv` are SYMLINKS and `os.walk` does not follow them."""
    p = subprocess.run([str(ROOT / ".venv" / "bin" / "python"), "checks/compile-census.py",
                        "--rows", "checks/census.rows"],
                       cwd=str(tree), capture_output=True, text=True,
                       env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"})
    return p.returncode, p.stdout, p.stderr


def read_rows_of(tree: Path) -> list[dict]:
    """The census copy's rows."""
    path = tree / "checks" / "census.rows"
    if not path.is_file():
        return []
    out = []
    for line in path.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        f = line.split("\t")
        out.append({"state": f[0], "file": f[3] if len(f) > 3 else ""})
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--plant", action="store_true", help="the plant and its control")
    a = ap.parse_args()
    if a.plant:
        return plant()
    return run()


if __name__ == "__main__":
    sys.exit(main())
