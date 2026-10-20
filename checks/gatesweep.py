#!/usr/bin/env python3
"""gatesweep.py -- run the gate population under a watchdog and tally the FIVE verdicts.

    .venv/bin/python checks/gatesweep.py --plan           # the population, the control, and the PROJECTION
    .venv/bin/python checks/gatesweep.py --plan --suffix  # ... of the OLD suffix set alone
    .venv/bin/python checks/gatesweep.py --prove          # classify REAL captured outcomes, run nothing
    .venv/bin/python checks/gatesweep.py --selftest       # drive the loop on SYNTHETIC gates, temp-dir
    .venv/bin/python checks/gatesweep.py --selftest --plant   # ... and the selftest MUST fail
    .venv/bin/python checks/gatesweep.py                  # run every gate, write the rows

THE FOREIGN SWEEP THIS REPLACES. A zsh script under `/tmp` ran `gates/*-gate.py`, kept only `$?`,
and sent every gate's output to `/dev/null` -- so a gate that ran and emitted nothing (DEAD, 5)
was indistinguishable from one that agreed (PASS, 0). Four faults, and each is answered here:

  POPULATION  a DIRECTORY WALK of the DERIVED gate homes for ENTRY POINTS -- the spelling of a
              file never decides membership, and `os.walk` never returns `[]` for a tree that has
              files in it. **BOTH DEFECTS THIS FILE HAD ARE ONE LINE.** It walked `root/"gates"`
              -- a HARD-CODED HOME -- and then kept `name.endswith("-gate.py")` -- a SUFFIX --
              and a suffix is a hand list with a wildcard in it (`AGENTS.md`'s "A BASENAME SHAPE,
              A SUFFIX SET, AND A HAND LIST ARE NOT POPULATIONS"). The two defects are
              INDEPENDENT and cost different amounts: a NAME is what a rename would fix, and the
              brief forbids one, and a HOME costs nothing at all. **NO COUNT IS TRANSCRIBED
              HERE.** `report()` prints `WALK`, `SUFFIX`, `BEFORE` and `DELTA` on every run,
              because four other units are writing gates into this tree and a figure written down
              once is wrong within the hour. The reading that motivated the change, 2026-10-18
              18:08Z: `WALK 250 - BEFORE 96 = +154 (+146 by NAME, +8 by HOME)`, and the HOME half
              is 9 `checks/` FILES the suffix had already approved and the one hard-coded home
              could not reach -- 8 of them entry points, the ninth (`checks/reorder-gate.py`)
              carrying the suffix without a `__main__`, which is the class below.
              The homes come from `gates/gates-pop.py:gate_homes()` LOADED BY PATH and the entry
              test from that same module's `entry_reason()`, so a second copy of the vocabulary
              cannot rot beside the first. A literal list is not a population; neither is the
              foreign glob; and `gate_homes()` is how the walk stays auditable.
  PROJECTION  the two populations this file prints COME FROM TWO INSTRUMENTS WITH TWO WALK RULES
              -- this walk descends and prunes dotted names, `gates-pop.discover()` is `iterdir()`,
              immediate and dotted-kept -- and until `project()` existed NOTHING BRIDGED THEM, so a
              reader saw two numbers and concluded the instruments disagreed. `project()` derives
              each term from its OWN side's rule and prints the two numbers' difference AS VALUES
              with every name, beside the numbers they explain. **NOT A SET DIFFERENCE:** that
              identity is true of any two sets and would print `HELD` for ever. **NOT A MERGE:**
              merging the walks makes both terms zero and destroys the projection.
  WATCHDOG    every gate runs THROUGH `checks/bounded.py`, so a hung or hungry gate is killed and
              its PEAK is reported. The kill's own TOKEN (KILLED-ON-MEMORY / TIMED-OUT /
              NOT-STARTED / NO-VERDICT) is read -- never the exit status, which the watchdog's own
              header records a unit losing 425 rows to.
  OUTPUT      both streams are CAPTURED, so DEAD-by-silence is a state this instrument can see:
              a gate that exits 0 having printed nothing is DEAD, and that is the whole point.
  VERDICT     the five are `gates/gatekit.py`'s, LOADED BY PATH. Every member here is a gatekit
              gate, so its exit code IS its declared verdict -- but only once the watchdog's
              3/4/5 are separated from the gate's, an unassigned code REFUSES, and a crash
              (rc 1 + a traceback) is DEAD rather than FAIL. **THE RUNNER FOLLOWS THE MEMBER'S
              OWN LANGUAGE**, because a walk that admits `checks/gate.sh` and then runs it with
              the Python interpreter has widened the population and destroyed it in one line:
              MEASURED, `sh checks/gate.sh` answers rc 3 and `python checks/gate.sh` answers a
              SyntaxError, and the sweep would have recorded the second as a FAIL about the tree.

WHAT THIS FILE DOES NOT DO. It does not scrape a gate's PROSE for a verdict word. The token is
`gatekit.VERDICT`'s own word for the exit code, because the tree SPELLS the token as the exit --
`gatekit.py:60` is `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`. A word matched out of free
text is a shape, and this project has paid for shape-matching a population three times.

TWO CLASSES A WIDER POPULATION ADMITS, AND ONE OF THEM IS NOW CLOSED. `--selftest`'s WIDTH case
plants both, because a walk is not made honest by being wide.

  A LANE IS NOT A GATE -- **CLOSED 2026-10-18, BY `classify()`'s LAST ARM, NOT BY A FILTER.** A
  `*-oracle.py` run bare prints rows and exits 0, so it used to land on `PASS` and `PASS` was a
  claim about nothing -- "0 disagreements over 0 comparisons". **THE REMEDY IS NOT A LANE FILTER
  AND NEVER WAS GOING TO BE ONE:** the declaration available is not a population, so a filter
  would have caught the `Gate(oracle=...)`-named minority and been a list wearing a declaration's
  clothes. `classify()` instead asks the question that needs no list -- did anything COMPARE this
  member's rows -- using three helpers `gates/lane-census.py` owns and this file LOADED BY PATH
  (`rows_in`, `DECIDED`, and `declared()`'s `Gate(oracle=..., bend=...)` AST read over the walk
  this file already holds): **a member that printed `name=value` rows, that no `Gate` names, and
  that printed no verdict word of its own is `DEAD, UNCONSUMED-LANE`, not `gatekit.VERDICT[0]`.**
  The arm intercepts that one answer and nothing else -- a member that was about to be `FAIL`,
  `REFUSED`, `SKIP` or `DEAD` keeps its own verdict and its own token, because each of those
  already carries evidence a reader can check and `PASS` on an unconsumed lane carried none.
  **A LANE THAT PRINTS ITS OWN VERDICT IS NOT CHARGED** (`gates/devtag-gate.py` is the measured
  shape: rows, no consumer, and its own `PASS`), and neither is a CENSUS that prints no
  `name=value` row at all -- drop either arm and the rule flattens both sides to one constant,
  which is why `gates/artifactverdict-gate.py` plants both.

  A DRIVER WITH NO `main` IS NOT AN ENTRY. `entry_reason()` asks for `__main__`, so a file whose
  work happens at import is invisible however wide the walk is -- MEASURED 2026-10-18 18:12Z,
  **67 of the 73 `py-lib` files** under the two homes execute at their top level, and all 67 are
  tracked. (`gates/artifacts/` and dotted names excluded: the former is `.gitignore`d and
  `rm -rf`-able, the latter the walk prunes. **AND THE BUCKET ITSELF IS PART OF THE FINDING**:
  `gates-pop.py` calls a module and a script the same word, so its own `py-lib` count cannot be
  split without an AST pass, and that pass is this file's -- which is why the figure is quoted
  here and not there.)
"""
from __future__ import annotations

import argparse
import ast
import importlib.util
import os
import re
import stat
import subprocess
import sys
import tempfile
import threading
import time
import warnings
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
GATES = ROOT / "gates"
PY = ROOT / ".venv" / "bin" / "python"
TRACEBACK = "Traceback (most recent call last)"
# The record `checks/bounded.py` writes on stderr, WITHOUT its two spaces assumed: `[bounded]
# <TOKEN>  rc=<child rc>`. The rc here is ALWAYS the child's own, even on a kill, so it is the
# gate's exit and the TOKEN is the watchdog's -- the one pair that settles the 3/4/5 collision.
REC = re.compile(r"\[bounded\] (\S+)  rc=(-?\d+)")
HEADER = "gate\tverdict\ttoken\trc\tseconds"

# THE PROOF'S INPUTS LIVE BESIDE THE GATE, IN GIT, AND ARE PINNED BY CONTENT. `--prove` read
# `.agents/slop/hooks/`, which is PRUNABLE -- `AGENTS.md` counts 85 of the 169 already-gone paths
# under `.agents/slop/` -- so one prune leaves this instrument reporting `0/0`, which its own
# `return 0 if ok == n and n else 1` calls a failure but its denominator cannot say. A missing
# input is not a smaller proof, it is a proof of nothing. The pin is what makes the move a contract
# and not a copy: an unpinned transcript can be edited into passing.
PROVE_COST = "checks/gatesweep-cost.out"        # that run's captured per-gate stdout
PROVE_TRUTH = "checks/gatesweep-run.tsv"        # and the verdicts it recorded
PROVE_PIN = {
    PROVE_COST: "de8038e7bfc24f8be65d8357773e4329d8cfedadb98e86b691ca17a1aebb65b2",
    PROVE_TRUTH: "d44ab732bf834012d5127b3d099a097312678d013401fa93761320b4b8c555a2",
}


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)             # all three are side-effect-free at import
    return module


def control(root: Path = ROOT) -> tuple[list[Path], list[Path]]:
    """`gates/gates-pop.py:discover()` -- `(entries, modules)`, the OTHER WALK, UNFORMATTED.

    `discover()` answers a DIFFERENT question -- "every entry point in both gate homes" -- and it
    re-parses the tree, emitting `gates-pop.py`'s own `SyntaxWarning`s. Those are not this run's
    subject, so they are silenced here and not allowed into a console whose verdicts matter.

    **THE MEMBERS, NOT ONLY THE COUNT, BECAUSE `project()` BRIDGES THE TWO WALKS AND A COUNT
    CANNOT BE BRIDGED WITH.** This used to return a finished string, which is what left the
    difference between the two numbers to be carried by a prose fragment in
    `checks/oracle-txt-census.py` -- a figure printed nowhere beside the numbers it explains.
    """
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        return gpop.discover(root)


def project(here: list[Path], there: list[Path], home_dirs: set[Path]) -> dict:
    """HOW `WALK` AND `CONTROL` DIFFER, AS VALUES: `deep`, `dot`, `bridged`, `held`, and a residue.

    THE DEFECT THIS EXISTS FOR. The two numbers this file prints come from two instruments with
    two walk rules -- `walk()` is `os.walk`, RECURSIVE, with dotted names pruned; `discover()` is
    `iterdir()`, IMMEDIATE ONLY, dotted names KEPT -- and until now NOTHING bridged them, so a
    reader seeing `WALK 271` and `CONTROL 273` concludes the instruments DISAGREE. They do not.
    **Both walks are correct and both are what they claim, so MERGING THEM WOULD DESTROY THIS
    FUNCTION BY MAKING BOTH TERMS ZERO. THE DIFFERENCE IS THE USEFUL PART; DO NOT "FIX" IT.**

    **THE TERMS COME FROM EACH WALK'S OWN RULE AND NEVER FROM THE OTHER WALK'S SET, AND THAT IS
    THE WHOLE OF IT.** `deep` is every `here` member that is not an immediate child of a home --
    the WALK's depth rule, measured on the WALK. `dot` is every `there` member with a dotted name
    -- the CONTROL's dot rule, measured on the CONTROL. `bridged` is `len(here) - len(deep) +
    len(dot)` and `held` says whether it EQUALS `len(there)`.

    **A PROJECTION BUILT AS A SET DIFFERENCE WOULD BE A TAUTOLOGY THAT PRINTS `HELD` FOREVER.**
    `len(W) - len(W - C) + len(C - W) == len(C)` is an identity of set theory -- true for ANY two
    sets, true of two trees with nothing in common -- so a bridge built that way cannot fail and
    a reader would read agreement into a constant. Deriving each term from its own side's rule is
    what makes `held` a CLAIM: *these two instruments differ by these two rules and by no third.*
    The residue is what a third reason looks like when one exists -- `extra` is a `here` member
    the control lacks for a reason that is NOT depth and `stray` is a `there` member the walk
    lacks for a reason that is NOT a dotted name -- and both are EMPTY on this tree. MEASURED
    2026-10-20 by `.venv/bin/python checks/gatesweep.py --plan`, FOUR READINGS AS THE TREE MOVED
    UNDER THIS UNIT, WHICH IS THE PROOF THAT THE TERMS ARE MEASURED: 00:19:12Z `WALK 271`,
    `CONTROL 273`, `bridged 273`; 00:21:03Z `WALK 273`, `CONTROL 275`, `bridged 275`; 00:21:57Z
    and 00:23:00Z unchanged. **`deep` and `dot` DID NOT MOVE ACROSS THE +2/+2** -- `deep 2`,
    `dot 4`, `extra 0`, `stray 0` in every reading -- so both arrivals were immediate and
    undotted, which is what a held projection says. **WHICH MEMBERS ARRIVED IS NOT RECORDED AND
    IS NOT CLAIMED**: another unit was writing `gates/banner-emit-*` and `gates/cites-pop-gate.py`
    throughout, so attributing the +2 to any of them would be a measurement this unit did not
    take. `dot` was **5** in the brief that asked for this and is **4** in every reading --
    `gates/.wgsl-mut-oracle.py` is gone -- so neither term is typed.
    """
    a, b = set(here), set(there)
    deep = sorted(p for p in a if p.parent not in home_dirs)
    dot = sorted(p for p in b if p.name.startswith("."))
    bridged = len(a) - len(deep) + len(dot)
    return {"walk": len(a), "control": len(b), "deep": deep, "dot": dot, "bridged": bridged,
            "held": bridged == len(b),
            "extra": sorted((a - b) - set(deep)), "stray": sorted((b - a) - set(dot))}


def bridge(proj: dict, root: Path) -> None:
    """PRINT `project()`'s values, EVERY NAME, so the two printed numbers are never read apart.

    The names are the point. `dot` is another unit's in-flight scratch under `checks/`, and a
    reader told only "the control keeps 4 more" cannot tell a scratch file from a gate; the
    `deep` names are the two TRACKED `gates/oracles/*.sh`, which is the same fact behind the
    19-vs-21 shell count `gates-pop` and `population()` used to report as a bare disagreement.

    The residue prints ONLY when it is non-empty, because its absence is the claim and printing
    `-> 0` twice would be noise dressed as evidence. When it IS non-empty the walk and the control
    differ by a THIRD rule -- the two `ENTRIES` tuples, one per file, are the live candidate -- and
    `held` is False, which is the only reading of a `DIFFERS BY` line a reader needs.
    """
    gap = proj["bridged"] - proj["control"]
    print(f"PROJECTION : {proj['walk']} - {len(proj['deep'])} deeper + {len(proj['dot'])} dotted "
          f"= {proj['bridged']} == CONTROL({proj['control']}) -> "
          f"{'HELD' if proj['held'] else f'DIFFERS BY {gap:+d}'}")
    for label, term, why in (("DEEPER", "deep", "walk DESCENDS, control is iterdir() immediate"),
                             ("DOTTED", "dot", "walk PRUNES dotted, control keeps them"),
                             ("UNEXPLAINED-WALK", "extra", "neither rule: a THIRD difference"),
                             ("UNEXPLAINED-CONTROL", "stray", "neither rule: a THIRD difference")):
        if not proj[term] and term in ("extra", "stray"):
            continue
        print(f"  {label:<19}: {why:<45} -> {len(proj[term])}")
        for p in proj[term]:
            print(f"                     {p.relative_to(root)}")


gatekit = _load("gw_gatekit", GATES / "gatekit.py")     # the FIVE, and `VERDICT`
bounded = _load("gw_bounded", HERE / "bounded.py")      # its TOKENS, imported not re-typed
with warnings.catch_warnings():                          # `gates-pop` parses `.rows` fixtures
    warnings.simplefilter("ignore")                      # and emits its own SyntaxWarnings
    gpop = _load("gw_pop", GATES / "gates-pop.py")

# THE ROW GRAMMAR AND THE DECISION WORDS ARE `gates/lane-census.py`'s, LOADED BY PATH -- and this
# file holds NO copy of either. `gates/lane-census.py` owns `rows_in()`, `DECIDED` and the
# `Gate(oracle=..., bend=...)` AST reader that says who consumes a lane; `AGENTS.md`'s DOCTRINE 1
# records SIX instruments in this repo that declared a population by hand and lost the class for
# it, and a hand-typed `^name=` is that same mistake wearing a regex. `None` is a POSSIBLE answer
# and it is not an error to swallow: without this module `classify()` cannot tell whether anything
# compared a member's rows, and it says `REFUSED, NOT A VERDICT: NO-RULE` rather than the `PASS`
# this change exists to stop it from writing.
try:
    lanecensus = _load("gw_lanecensus", GATES / "lane-census.py")
except (OSError, SyntaxError, ImportError):
    lanecensus = None

# `gates-pop`'s OWN vocabulary for "running this file as a program is its measurement", by NAME
# and never re-spelled: a second copy of the list would be a second population.
ENTRIES = ("py-main", "sh-dispatch", "sh-selfref", "js-main")
SUFFIX = "-gate.py"                       # THE OLD QUESTION, kept and asked, never the population
RUNNERS = {"py": [str(PY)], "sh": ["/bin/sh"], "js": ["node"]}
OLD_HOME = "gates"     # THE HOME THIS FILE USED TO WALK. A record of the PAST, never the
                        # population -- it is quoted once, by `report()`, to print `BEFORE`.

# WHAT THE WALK DOES NOT DESCEND, and it is `gates-pop.py`'s OWN tuple LOADED BY PATH plus one
# rule. `gates-pop._SKIP` is `(".git", ".jj", "__pycache__")`; a name beginning with `.` is the
# second half. **MEASURED 2026-10-18 18:06Z: 6 of the 6 dotted entries under the two homes are
# ABSENT from `git ls-tree -r HEAD`** -- four `checks/.tmp-*` (another unit's in-flight scratch,
# the instance `gates-pop.py`'s own ledger note records), `gates/.wgsl-mut-oracle.py` and a
# mutation plant's staged copy under `gates/.realize-mut-stage/` -- so the rule agrees with
# `gates-pop`'s definition of a gate ("the COMMIT TREE carries it") on every file in this tree,
# and it agrees WITHOUT A GIT CALL PER MEMBER, which is what lets `--selftest` walk a synthetic
# tree that is not a repository at all. `PRUNED` prints the LIVE count every run because that
# number moves with other units' scratch. The two TRACKED files under `gates/oracles/` are not
# dotted and stay in, which is why `WALK` and `CONTROL` differ.
SKIPPED = tuple(gpop._SKIP)


def _prune(dirnames: list[str], keep_dot: bool) -> None:
    dirnames[:] = [d for d in dirnames
                   if d not in SKIPPED and (keep_dot or not d.startswith("."))]


def homes(root: Path = ROOT) -> tuple[str, ...]:
    """The gate HOMES, measured by `gates/gates-pop.py:gate_homes()` LOADED BY PATH.

    Measured, not written down, and that is the whole of the second defect: this file used to
    walk `root/"gates"` alone, so the nine `checks/*-gate.py` gates -- files the suffix had
    ALREADY APPROVED -- were unreachable. A home named in code is a list with a path in it.

    `gate_homes` reads 1,065 files and re-parses `gates-pop.py` itself, so it emits the same
    warnings; silencing is inside this function rather than at the call site so no caller can
    forget it.
    """
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        return gpop.gate_homes(root)[0]


def walk(root: Path, hs: tuple[str, ...], keep_dot: bool = False) -> list[tuple[Path, str]]:
    """`[(path, reason)]` for every ENTRY POINT under `hs`, by DIRECTORY WALK.

    `os.walk` + `gates-pop.entry_reason()`, and nothing else: no suffix, no glob (the file's own
    header records `glob('*.bend')` answering `[]` over a tree holding 1,890 tracked lines), and
    no name written down once. The reason travels with the path because it is what says which
    INTERPRETER runs the member, and a walk that knows a member's language and then runs it with
    the wrong one has measured nothing.

    `gates-pop`'s OWN `SyntaxWarning`s are silenced here rather than in the caller, because
    `entry_reason` re-parses `gates-pop.py` ITSELF -- `<unknown>:299` on stdout is that file's
    escape sequence being read a second time by the instrument that owns it. A console whose
    verdicts matter cannot carry another instrument's warnings.
    """
    found = []
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        for home in hs:
            base = root / home
            if not base.is_dir():
                continue
            for dirpath, dirnames, filenames in os.walk(base, followlinks=False):
                _prune(dirnames, keep_dot)
                for name in filenames:
                    if name.startswith(".") and not keep_dot:
                        continue
                    p = Path(dirpath) / name
                    if not stat.S_ISREG(os.lstat(p).st_mode):
                        continue               # a symlink is not a file: lstat, never exists()
                    reason = gpop.entry_reason(p)
                    if reason in ENTRIES:
                        found.append((p, reason))
    return sorted(found)


def population(root: Path = ROOT) -> list[tuple[Path, str]]:
    """THE POPULATION: every entry point in every DERIVED gate home. Nothing is spelled."""
    return walk(root, homes(root))


def suffix(root: Path, hs: tuple[str, ...]) -> list[Path]:
    """THE OLD QUESTION, KEPT AND ASKED: which of the walk end in `-gate.py`?

    Kept because a widened population with no record of what it added is a SILENT
    reinterpretation of "the sweep passed". `report()` prints the two side by side, and
    `--suffix` runs this set instead of the walk, so the old denominator stays obtainable.
    """
    return [p for p, _ in walk(root, hs) if p.name.endswith(SUFFIX)]


def unconsumed_lane(name: str | None, consumed: frozenset[str], text: str) -> bool:
    """Whether THIS member printed lane rows that nothing compared.

    **THE THREE ARMS ARE `gates/lane-census.py`'s, LOADED BY PATH, AND THIS FUNCTION ADDS
    NOTHING.** `rows_in` is its row grammar, `DECIDED` is its own table of the five verdict words
    (checked against `gatekit.VERDICT` by that file's own plant on every run), and `consumed` is
    `declared()` -- the `Gate(oracle=..., bend=...)` call sites read off the AST of the very walk
    this sweep holds. A member is charged only when ALL THREE hold, and every one of them is a
    measurement rather than a preference:

      it printed `name=value` rows   drop this arm and every unconsumed CENSUS in this tree is
                                     DEAD -- a census is an instrument, not a comparison, and this
                                     is the "flatten both sides to one constant" trap;
      no `Gate` names it             drop this arm and every gate in the tree is DEAD;
      it printed no verdict word     drop this arm and a SELF-VERIFYING gate is charged for
                                     lacking a second opinion (`gates/devtag-gate.py`'s measured
                                     shape: 7 rows, no consumer, and it prints its own `PASS`).

    **`name is None` DOES NOT CHARGE, AND THAT IS THE FAIL-SAFE DIRECTION.** An unknown member
    cannot be shown to be unconsumed, and a rule that manufactures a `DEAD` out of missing evidence
    is the same defect inverted. It is not a hole in the population: `sweep()` passes every member's
    own name, and the only callers that omit it are `--prove`'s pinned transcript (a first line per
    gate -- MEASURED, it carries no `name=` row at all, so the rule is structurally inert there and
    14/14 reproduce either way) and the two-function plant, which must see the OLD answer.
    """
    if lanecensus is None or name is None or name in consumed:
        return False
    return bool(lanecensus.rows_in(text)) and not lanecensus.DECIDED.search(text)


def classify(btoken: str, rc: int, text: str, name: str | None = None,
             consumed: frozenset[str] = frozenset()) -> tuple[str, str]:
    """`(verdict, token)` from the watchdog's token, the gate's rc, and its captured output.

    Every branch is a measured shape, and the order is the order the evidence is trustworthy in:
      a kill           -> SKIP: it did not answer, so it measured nothing (bounded's own note)
      not started      -> REFUSED: the command itself was an absent precondition
      nothing said, or the watchdog said so -> DEAD: it ran and emitted nothing
      rc 1 + traceback -> DEAD: a crash is not the wrong answer (`hooks/run.py`'s rule, measured)
      else             -> the exit code IS the verdict, through gatekit's own table
      ... and ONE arm on the `PASS` fall-through alone: a member that printed lane rows, that no
      `Gate` names, and that printed no verdict of its own is `DEAD`, not `gatekit.VERDICT[0]`.

    **WHY THAT LAST ARM IS CORRECT AND NOT MERELY STRICTER.** It intercepts exactly one answer --
    the one the sweep was about to write when it had nothing to compare against. `PASS` in this file
    means "the member ran and its exit code said so", and for a member no `Gate` declares there is
    no exit code that means anything, because nothing in the tree is waiting to read the rows: the
    old answer was a claim about NOTHING, which is precisely what `gates/lane-census.py` calls
    "0 disagreements over 0 comparisons" and precisely what `AGENTS.md` records about
    `artefacts_ok()`. So the arm does not make the sweep harsher about the TREE -- a member it
    would have called `FAIL`, `REFUSED`, `SKIP` or `DEAD` is untouched, and each of those already
    carries evidence the reader can check. It makes the sweep NARROWER about the CLAIM: `PASS` is
    withheld from precisely the members that have not earned it, and the token `UNCONSUMED-LANE`
    names the reason on the row so a reader sees which members moved.

    `NO-RULE` is the other half of the same honesty: with `gates/lane-census.py` absent the three
    arms cannot be evaluated, and a verdict this file cannot evaluate is not a verdict.
    """
    if btoken in (bounded.MEMORY, bounded.TIMEOUT):
        return "SKIP", btoken
    if btoken == bounded.UNSTARTED:
        return "REFUSED", btoken
    if btoken == bounded.NOVERDICT or (rc == 0 and not text.strip()):
        return "DEAD", btoken if btoken == bounded.NOVERDICT else "SILENT"
    if rc == 1 and TRACEBACK in text:
        return "DEAD", "TRACEBACK"
    word = gatekit.VERDICT.get(rc)
    if word == gatekit.VERDICT[gatekit.PASS]:
        if lanecensus is None:
            return gatekit.VERDICT[gatekit.REFUSED], "NO-RULE"
        if unconsumed_lane(name, consumed, text):
            return gatekit.VERDICT[gatekit.DEAD], "UNCONSUMED-LANE"
    return (word, word) if word else ("REFUSED", f"UNASSIGNED({rc})")


def run_one(gate: Path, reason: str, seconds: int, mb: int,
            consumed: frozenset[str] = frozenset()) -> tuple[str, str, int, float, str]:
    """`(verdict, token, rc, seconds, peak)` for one gate, run under `checks/bounded.py`.

    The interpreter is the one `reason` names, and an UNKNOWN reason is a REFUSAL rather than a
    guess: `RUNNERS.get(reason.split("-")[0], [])` on a language this tree grows would hand it to
    the Python interpreter, and a Python parse error recorded as `FAIL` is a FAIL about the wrong
    subject -- the same defect as running `gate.sh` with `python`.

    `consumed` is the CALLER'S set of lane filenames some `Gate` names, built once per run because
    it costs a full AST pass over the walk (MEASURED 1.10 s at 252 members, 2026-10-18 19:0xZ) and
    it is the difference between one computation and 252 of them.
    """
    runner = RUNNERS.get(reason.split("-")[0]) if reason else None
    if not runner:
        return "REFUSED", f"NO-RUNNER({reason})", gatekit.REFUSED, 0.0, "?"
    cmd = [str(PY), str(HERE / "bounded.py"), "--seconds", str(seconds), "--mb", str(mb),
           "--", *runner, str(gate)]
    t0 = time.monotonic()
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(ROOT))
    took = time.monotonic() - t0
    m = REC.search(r.stderr)
    btoken, rc = (m.group(1), int(m.group(2))) if m else ("NO-RECORD", r.returncode)
    # the gate's OWN words: the record and its continuation lines are the watchdog's, not the gate's
    said = "\n".join(l for l in r.stderr.splitlines() if not l.startswith(("[bounded]", "  ")))
    verdict, token = classify(btoken, rc, r.stdout + "\n" + said, gate.name, consumed)
    peak = re.search(r"peak-RSS=(\d+)", r.stderr)
    return verdict, token, rc, took, (peak.group(1) if peak else "?")


# --------------------------------------------------------------------- the proof, on real data
def prove(cost_tsv: Path, truth_tsv: Path, pop: list[tuple[Path, str]]) -> int:
    """Classify REAL, already-captured gate outcomes and require the recorded verdict.

    Inputs are two transcripts a PRIOR run already wrote, so no gate is run:
      `checks/gatesweep-cost.out` -- per gate: rc (or `OVER-CAP`), seconds, path, first line.
      `checks/gatesweep-run.tsv`  -- per gate: the VERDICT that run recorded.
    Both are pinned by content (see `PROVE_PIN`); drift is a REFUSAL, not a smaller proof.
    The classifier must reproduce every recorded verdict from (rc, first-line) alone.

    **THE LANE RULE IS ASKED HERE AND CANNOT FIRE, AND THAT IS A MEASUREMENT, NOT A LAPSE.** `pop`
    is the same walk `sweep()` gets, so the rule is evaluated over the identical declaration set --
    but this transcript carries ONE FIRST LINE per gate (`row`'s `(.*)$` group), and MEASURED at
    14/14 on 2026-10-18: not one of those 14 first lines matches `lane-census`'s `^name=` grammar.
    So the pinned proof is STRUCTURALLY BLIND to the class, which is why it reads green both before
    and after the rule and why `PASS 9 -> 0` cannot be demonstrated on it. The proof's job is to
    pin the transcripts against drift, not to census the population; the census is
    `gates/lane-census.py --run`, and the sweep that would move the tally is `checks/gatesweep.py`.
    """
    truth = {}
    for line in truth_tsv.read_text().splitlines()[1:]:
        cells = line.split("\t")
        if len(cells) >= 2:
            truth[cells[0]] = {"GREEN": "PASS"}.get(cells[1], cells[1])   # run.py spells 0 GREEN
    row = re.compile(r"^\s*(\d+|OVER-CAP)\s+([\d.]+)s\s+(\S+)\s+(.*)$")
    consumed = frozenset(lanecensus.declared(pop)) if lanecensus is not None else frozenset()
    n = ok = 0
    for line in cost_tsv.read_text().splitlines():
        m = row.match(line)
        if not m:
            continue
        rc_s, _, path, head = m.groups()
        # a bound fired iff the run reached a cap: the watchdog's token, not a number, says so
        rc = int(rc_s) if rc_s.isdigit() else 0
        btoken = bounded.TIMEOUT if rc_s == "OVER-CAP" else bounded.WITHIN
        verdict, token = classify(btoken, rc, head, Path(path).name, consumed)
        # `checks/gatesweep-run.tsv` keys `gate-surface.py --report` by its flags; the path is the subject
        want = truth.get(path) or truth.get(path + " --report")
        n += 1
        ok += verdict == want
        print(f"  {'OK ' if verdict == want else 'BAD'}  rc={rc_s:<8} {path:<32} "
              f"-> {verdict:<7} token={token:<14} recorded={want}")
    print(f"PROOF: {ok}/{n} recorded verdicts reproduced from (rc, first line) alone")
    return 0 if ok == n and n else 1


def gate_names(pop: list[tuple[Path, str]]) -> frozenset[str]:
    """The `Gate(name)` values declared INSIDE the walk, off the AST. Who owns an artifact dir.

    `gatekit.Gate.__init__` takes `name` as its FIRST POSITIONAL argument (`gates/gatekit.py:377`)
    and spends it as `self.dir = ART / name` (`:411`), so a directory under `gates/artifacts/` is
    owned by whichever walk member spelled that string. MEASURED 2026-10-18 19:0xZ: a reader that
    looks for `name=` as a KEYWORD sees none of them -- every gate in this tree writes
    `Gate("tn_add_sub-gate", bend=..., ...)` -- and answers "82 dirs, 0 owners", which is the
    `0 over 0` this file exists to stop. `gates/lane-census.py:declared()` cannot answer this
    question either, and that is not an overlap: it reads `oracle=`/`bend=` (which LANE a gate
    consumes), this reads the positional `name=` (which DIRECTORY a gate owns).
    """
    out = set()
    for path, _reason in pop:
        if path.suffix != ".py":
            continue
        try:
            tree = ast.parse(path.read_text(errors="replace"))
        except (SyntaxError, ValueError, OSError):
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and getattr(node.func, "id", None) == "Gate" and node.args:
                head = node.args[0]
                if isinstance(head, ast.Constant) and isinstance(head.value, str):
                    out.add(head.value)
    return frozenset(out)


def artifact_census(root: Path = ROOT, pop: list[tuple[Path, str]] | None = None) -> None:
    """What `gates/artifacts/*/` CAN and CANNOT say, since the brief names it as the proof input.

    `gatekit.Gate` PROMOTES its lanes on PASS and leaves the directory EMPTY otherwise
    (`_clear` empties at construction, `_settle(False)` unlinks the staged files), so a
    directory's CONTENTS are a real captured outcome: populated == the gate reached the diff
    and agreed. But every file here is a LANE (`py.rows`/`bd.out`/`bn.out`/`*.cmp`/`gate.bin`)
    -- never a gate's stdout -- so the directory is NOT an input a token parser can read. That
    is stated rather than papered over, and the token proof runs on the captured transcripts.

    **AN EMPTY DIRECTORY IS NOT `DEAD`, AND THE TREE SAYS SO IN ITS OWN SOURCE.** The obvious
    reading -- "nothing in it, so nothing compared it", the `artefacts_ok()` shape `AGENTS.md`
    records -- is REFUTED by `gates/gatekit.py`'s measured note: "_clear() ... BOTH GATES GO rc=2
    WITH AN EMPTY DIRECTORY". rc 2 is a code `VERDICT` does NOT name, so `classify()` calls it
    `REFUSED, UNASSIGNED(2)`: a gate that refuses before `run()` leaves an empty directory by
    DESIGN, and `FAIL`, `REFUSED`, `SKIP` and `DEAD` all end empty too. **SO EMPTINESS DECIDES
    NOTHING, AND A GATE THAT CHARGED IT `DEAD` WOULD BE WRONG IN FOUR DIRECTIONS AT ONCE.** A
    wrong reason is worse than no reason, so this census does not make that claim.

    **WHAT IT REPORTS INSTEAD IS THE REAL `0 over 0`, AND IT IS A SPLIT, NOT A VERDICT.** The
    82 directories were being counted as "82 gate dirs" while the walk declares far fewer owners,
    so `len(dirs)` was a denominator padded with directories no CURRENT gate can write. MEASURED
    2026-10-18 19:0xZ: 82 dirs, 65 populated, 17 empty, and of the 17 empty **12 have an owner in
    the walk and 5 have none** -- `arenasrc-census`, `cells`, `opseven-mut`, `sensitiv`,
    `tnvalue`. Those 5 are the population this file's own doctrine is about: a directory that
    exists, that holds nothing, and that no member of the walk can populate. **THEY ARE COUNTED
    AND NAMED; THEY ARE NOT CALLED `DEAD`,** because `gates/artifacts/` is `.gitignore`d, is
    written by gate runs, and nothing in the tree reads an orphaned dir -- which is a finding for
    a gate that owns artifact lifecycle, not a verdict this census may issue.
    """
    art = root / "gates" / "artifacts"
    dirs = [d for d in art.iterdir() if d.is_dir()]
    pop = population(root) if pop is None else pop
    owners = gate_names(pop)
    full = [d for d in dirs if any(d.iterdir())]
    empty = [d for d in dirs if not any(d.iterdir())]
    orphan = [d for d in empty if d.name not in owners]
    mine = [d for d in empty if d.name in owners]
    unowned = [d for d in dirs if d.name not in owners]
    kinds = sorted({f for d in dirs for f in os.listdir(d)
                    if (d / f).is_file() and not f.startswith(".tmp.")})
    print(f"ARTIFACTS: {len(dirs)} gate dirs -- {len(full)} hold promoted lanes (reached the diff), "
          f"{len(empty)} empty")
    print(f"           a dir holds {kinds}: LANE files, never a gate's stdout")
    print(f"OWNERS    : `Gate(` name= declared in the walk            -> {len(owners)}"
          f"   ({len(unowned)} of the {len(dirs)} dirs are named by NO walk member -- "
          f"{sorted(d.name for d in unowned)})")
    print(f"EMPTY     : of the {len(empty)} empty, {len(mine)} HAVE an owner -- that owner's "
          f"verdict, and\n           EMPTINESS DECIDES NOTHING (`gates/gatekit.py`: rc=2 "
          f"REFUSED leaves an empty dir)")
    print(f"CANT-WRITE: empty AND named by no walk member            -> {len(orphan)}"
          f"   {sorted(d.name for d in orphan)}")
    print("           a directory nothing can write and nothing reads is the `0 over 0`; it is "
          "REPORTED, not\n           called DEAD -- `gates/artifacts/` is .gitignore'd, so no "
          "verdict may rest on it.")


def report(root: Path = ROOT) -> list[tuple[Path, str]]:
    """Print the DENOMINATORS, then return the population. Every number is derived here.

    THE ROWS, AND WHY THERE ARE SIX. `WALK` is what this file now sweeps. `SUFFIX` is the old
    question, asked and answered beside it so the widening is a number rather than an intention.
    `BEFORE` is what this file ACTUALLY swept before the change -- the walk hard-coded to one
    home -- and it is a third number because the two defects are independent: MEASURED, 9 of the
    gap is 9 CONFORMING `checks/*-gate.py` files the suffix had already approved and the home
    could not reach, so quoting only `WALK - SUFFIX` would attribute them to the suffix. `DELTA`
    is the gap split into its two causes, because the remedies differ: a NAME costs a rename the
    brief forbids and a HOME costs nothing at all. `CONTROL` is the other instrument, and
    `PROJECTION` is the BRIDGE between it and `WALK` -- the sixth row, and the one that makes the
    other five readable: without it two populations printed one under the other are two verdicts.
    """
    hs = homes(root)
    if not hs:
        print("POPULATION: REFUSED, NOT A VERDICT -- gate_homes() certified NO home, and a "
              "population that is empty cannot fail (artefacts_ok()'s shape)", file=sys.stderr)
        raise SystemExit(gatekit.REFUSED)
    pop = walk(root, hs)
    sfx = [p for p, _ in pop if p.name.endswith(SUFFIX)]
    before = [p for p, _ in walk(root, (OLD_HOME,)) if p.name.endswith(SUFFIX)]
    pruned = len(walk(root, hs, keep_dot=True)) - len(pop)
    files = sum(1 for p in _all_files(root, hs) if p.name.endswith(SUFFIX))
    by_name, by_home = len(pop) - len(sfx), len(sfx) - len(before)
    try:
        entries, modules = control(root)
    except Exception as exc:                      # a control that cannot run is named, not zero
        print(f"CONTROL   : gates-pop.discover() -> UNAVAILABLE ({type(exc).__name__})")
        print("PROJECTION : REFUSED, NOT A VERDICT -- one walk is missing, and a bridge between "
              "one walk\n              and nothing is the number beside it written twice.")
        return pop
    print(f"HOMES     : gate_homes() -> {', '.join(hs)}  (MEASURED, not named here)")
    print(f"PRUNED    : dotted entries the walk skips                 -> {pruned}")
    print(f"WALK      : entry points in every derived home            -> {len(pop)}")
    print(f"SUFFIX    : of those, ending in `{SUFFIX}`                -> {len(sfx)}"
          f"   ({files} files end so; {files - len(sfx)} has no entry point)")
    print(f"BEFORE    : `-gate.py` in the one home this file walked   -> {len(before)}")
    print(f"DELTA     : {len(pop)} - {len(before)} = +{len(pop) - len(before)}"
          f"   (+{by_name} by NAME, +{by_home} by HOME)")
    print(f"CONTROL   : gates-pop.discover() -> {len(entries)} entries + {len(modules)} modules")
    print("            (immediate files only; the walk descends, and `gates/oracles/` is tracked)")
    bridge(project([p for p, _ in pop], entries, {root / h for h in hs}), root)
    return pop


def _all_files(root: Path, hs: tuple[str, ...]):
    """Every REGULAR FILE under `hs`, for the one row that counts files rather than entries."""
    for home in hs:
        base = root / home
        if not base.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(base, followlinks=False):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for name in filenames:
                p = Path(dirpath) / name
                if stat.S_ISREG(os.lstat(p).st_mode):
                    yield p


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plan", action="store_true",
                    help="print the population, the control, and the PROJECTION between them")
    ap.add_argument("--prove", action="store_true", help="classify real captured outcomes")
    ap.add_argument("--selftest", action="store_true", help="drive the loop on synthetic gates")
    ap.add_argument("--plant", action="store_true",
                    help="with --selftest: mislabel one expected verdict, so the selftest MUST fail")
    ap.add_argument("--suffix", action="store_true",
                    help="sweep the OLD suffix set instead of the walk (the pre-change denominator)")
    ap.add_argument("--seconds", type=int, default=600, help="per-gate wall bound")
    ap.add_argument("--mb", type=int, default=2048, help="per-gate peak-RSS ceiling")
    ap.add_argument("--out", type=Path, default=ROOT / "gates" / "artifacts" / "gates-sweep.rows")
    args = ap.parse_args(argv)

    gates = report(ROOT)
    if args.suffix:
        named = {p for p, _ in gates if p.name.endswith(SUFFIX)}
        gates = [(p, r) for p, r in gates if p in named]
        print(f"SUFFIX RUN: {len(gates)} members -- the suffix set over EVERY derived home. "
              f"`BEFORE` above is that same suffix over the ONE home this file used to walk, and "
              f"the difference between the two lines is the HOME half of `DELTA`, not the name.")

    if args.plan:
        for g, reason in gates:
            print(f"  would run  {reason:<11} {g.relative_to(ROOT)}")
        return 0
    if args.selftest:
        return selftest(plant=args.plant)
    if args.prove:
        artifact_census(ROOT, gates)
        drift = gatekit.oracle_drift(PROVE_PIN)   # a transcript that MOVED is a proof of other bytes
        if drift:
            print("PROVE: REFUSED -- " + "; ".join(drift))
            return gatekit.REFUSED
        return prove(ROOT / PROVE_COST, ROOT / PROVE_TRUTH, gates)

    return sweep(gates, args.out, args.seconds, args.mb)


def sweep(gates: list[tuple[Path, str]], out: Path, seconds: int, mb: int) -> int:
    """THE LOOP `main()` RUNS: header, one row per gate, tally, denominator. Describes THE RUN.

    `main()`'s default branch is this call and nothing else, so the `--selftest` that drives it drives
    the REAL path rather than a copy of it. Every row is `flush()`ed as its gate finishes, which is
    the durability property: a sweep killed at gate 69 leaves 68 rows on disk, not zero -- and that
    is the one claim a run that COMPLETES cannot make, so `--selftest` reads the file mid-sweep.
    """
    tally = dict.fromkeys(set(gatekit.VERDICT.values()), 0)
    # THE DECLARATION, ONCE PER RUN AND NEVER PER MEMBER. `gates/lane-census.py:declared()` reads the
    # `Gate(oracle=..., bend=...)` call sites off the AST of `gates` -- the walk THIS CALL holds, so
    # the declaring set is a SUBSET of the walked set by construction and no lane can be declared
    # that the sweep would not run. With the helpers absent the set is EMPTY, and an empty set makes
    # every row-printing member unconsumed: `classify()` answers `NO-RULE` before it can use it, so
    # the failure is a REFUSED sweep rather than a sweep that charged 252 members on no evidence.
    consumed = frozenset(lanecensus.declared(gates)) if lanecensus is not None else frozenset()
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w") as sink:
        sink.write(HEADER + "\n")
        sink.flush()
        rows = 0
        for g, reason in gates:
            verdict, token, rc, took, peak = run_one(g, reason, seconds, mb, consumed)
            tally[verdict] = tally.get(verdict, 0) + 1
            rel = str(g.relative_to(ROOT))
            print(f"  {verdict:<8} {took:6.1f}s  rc={rc:<4} peak={peak:>4}MB  {rel:<38} {token}")
            sink.write(f"{rel}\t{verdict}\t{token}\t{rc}\t{took:.1f}\n")
            sink.flush()
            rows += 1
    print("TALLY: " + "  ".join(f"{k}={v}" for k, v in sorted(tally.items())))
    # the denominator, which is not the tally: only PASS/FAIL are verdicts about the TREE
    about = tally.get("PASS", 0) + tally.get("FAIL", 0)
    print(f"THE DENOMINATOR: {about} of {rows} gates reached a verdict about the tree; "
          f"{tally.get('REFUSED', 0)} refused, {tally.get('SKIP', 0)} did not finish, "
          f"{tally.get('DEAD', 0)} crashed or said nothing.")
    print(f"rows -> {out.relative_to(ROOT)}")
    return 0 if rows else gatekit.DEAD            # describes THE RUN, never the tree


# --------------------------------------------------------------------- the selftest, on plants
# FIVE ONE-LINE GATES, ONE PER FIXTURE, NAMED SO THE SLEEPER SORTS LAST: `walk()` sorts, so
# `skip-gate.py` being last IS the window the flush proof reads into. Each source is the SMALLEST
# child that lands on its verdict, and the expected verdict is what `classify` must return -- so a
# child drifting onto another branch is a FAIL here and not a silent pass.
#
# **EVERY BODY IS INSIDE AN ENTRY GUARD, AND BEFORE THIS CHANGE NONE OF THEM WAS.** The population
# used to be a suffix, so a fixture that merely printed something counted; the walk asks
# `entry_reason`, and a one-line `print('ok')` is `py-lib` -- a MODULE that runs at import, which
# is a real 70-file class in this tree and NOT a gate. **A FIXTURE THAT DOES NOT SATISFY THE
# POPULATION IS A SELFTEST OF NOTHING**, and it fails the other way: the selftest went 4 of 4
# red with an EMPTY population while the tool it was testing reported `0 of 0`.
PLANTS = (
    ("dead-gate.py", "DEAD", "pass"),                                 # rc 0, emitted nothing
    ("fail-gate.py", "FAIL", "import sys; sys.stderr.write('no\\n'); sys.exit(1)"),
    ("pass-gate.py", "PASS", "print('ok')"),
    ("refuse-gate.py", "REFUSED", "import sys; sys.stderr.write('absent\\n'); sys.exit(3)"),
    ("skip-gate.py", "SKIP", "import time; time.sleep(60)"),           # the 1 s bound kills it
)
# THE WIDTH FIXTURES, and they are TWO because the fix has two halves and one residual.
# `HOMES` is a synthetic tree DECLARING ITS OWN UNIVERSE, which is what `gate_homes()` does for a
# real one: a synthetic tree certifies no home, and an empty population cannot fail.
HOMES = ("gates",)
MAIN = 'if __name__ == "__main__":\n'


def guarded(body: str) -> str:
    """`body`, one statement per line, INSIDE an entry guard -- the shape the walk admits."""
    return MAIN + "".join(f"    {line}\n" for line in body.splitlines() if line)


UNCONFORMING = "nonconforming.py"     # an entry guard, and a name that is NOT `-gate.py`
SCRIPT = "script-no-main.py"          # THE SAME PROGRAM with the guard REMOVED
SCRIPT_SRC = 'print("ok")\n'
# THE BRIDGE FIXTURES: one member per RULE the two walks differ by, planted at a KNOWN depth, so
# `project()`'s terms are measured against a world that MOVED and not against a constant.
WITNESS = "home-witness.py"           # certifies the synthetic tree's home (see below)
DEEPER = "oracles/planted-deeper.py"  # a SUBDIRECTORY member: the walk descends, `iterdir()` cannot
DOT_A, DOT_B = ".tmp-plant-a.py", ".tmp-plant-b.py"   # dotted members: pruned by the walk, kept
THIRD = "third-reason.py"             # immediate, undotted, and DENIED the control: a THIRD rule


def selftest(plant: bool = False) -> int:
    """Drive `sweep()` on a SYNTHETIC population and assert what it wrote. PASS=0, FAIL=1.

    THE POPULATION IS A TEMP `gates/` INSIDE THE REPO, so `walk()` reads it and every
    `relative_to(ROOT)` in the loop holds -- the loop under test is the loop that runs. Nothing
    here is a unit test of `classify()`: the subject is the ROWS FILE, because that is the artifact
    a killed sweep leaves behind and the only thing a reader downstream ever sees.

    The WIDTH case is the plant for the population itself, and it asserts BOTH DIRECTIONS: a
    population that cannot GROW is blind and a population that cannot SHRINK is a floor, and they
    are different mistakes. `SCRIPT` is the counterexample in the other direction -- the identical
    program with its entry guard removed stays OUT of the walk however wide the walk is, which is
    the THIRD defect (`AGENTS.md`: "`glob('*.bend')` returns `[]` ...") measured on a fixture
    instead of argued in prose. **A WIDER WALK IS NOT A COMPLETE ONE, AND ONLY A FIXTURE PROVES
    IT**, because on the live tree every member is named to suit.

    `plant=True` MISLABELS THE EXPECTATIONS ON PURPOSE -- one verdict, one width, and one bridge.
    A selftest
    that cannot go red is a claim with no counterexample, so the mutation is a flag on the same
    code path rather than a second harness: `.venv/bin/python checks/gatesweep.py --selftest
    --plant` MUST return 1.
    """
    results: list[tuple[str, bool, str]] = []
    with tempfile.TemporaryDirectory(prefix="gwself.", dir=ROOT / ".agents" / "slop") as td:
        root = Path(td)
        (root / "gates").mkdir()
        for name, _, src in PLANTS:
            (root / "gates" / name).write_text(guarded(src))
        gates = walk(root, HOMES)                      # the SAME directory walk the real run uses
        out = root / "rows.rows"
        worker = threading.Thread(target=sweep, args=(gates, out, 1, 512), daemon=True)
        worker.start()
        # THE FLUSH PROOF. Read the file while the sweep is STILL RUNNING and require rows on disk;
        # `worker.is_alive()` is sampled with the read, so a file that was complete at exit cannot
        # be mistaken for one written incrementally. The sleeper holds the window open ~1 s.
        sample: tuple[int, bool] | None = None
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if out.exists() and (n := len(out.read_text().splitlines()) - 1):
                sample = (n, worker.is_alive())
                break
            time.sleep(0.02)
        worker.join(60)

        lines = out.read_text().splitlines() if out.exists() else []
        want = {name: token for name, token, _ in PLANTS}
        if plant:
            want["dead-gate.py"] = "PASS"              # the planted lie: the row will say DEAD
        cells = [c for c in (l.split("\t") for l in lines[1:]) if len(c) >= 2]
        got = {Path(c[0]).name: c[1] for c in cells}
        wrong = [f"{k} -> {got.get(k)!r}, expected {v!r}" for k, v in want.items() if got.get(k) != v]
        results.append(("FIVE VERDICTS: the rows file classifies each planted child as planted",
                        not wrong, "; ".join(wrong) or
                        "  ".join(f"{k}={v}" for k, v in sorted(got.items()))))
        results.append(("SHAPE: a header and exactly one row per gate",
                        lines[:1] == [HEADER] and len(cells) == len(PLANTS),
                        f"{len(cells)} rows, header {lines[:1]!r}"))
        results.append(("INCREMENTAL: rows are ON DISK while the sweep is STILL RUNNING",
                        sample is not None and sample[1] and 1 <= sample[0] < len(PLANTS),
                        f"read {sample} (rows, sweep-alive) mid-sweep"
                        if sample else "never saw a row on disk before the sweep exited"))

        # THE BRIDGE PLANT: the two walks DIFFER BY A KNOWN AMOUNT, AND THE PROJECTION MUST MOVE.
        # `gates-pop.py`'s OWN home witness is LOADED BY PATH and never transcribed -- it is the
        # same `GOOD_ROOT` that module's plants write, and a synthetic tree that certifies no home
        # gets `discover() -> 0, 0`, which is `artefacts_ok()`'s shape and would leave every term
        # below vacuously satisfied.
        (root / "gates" / WITNESS).write_text(gpop.GOOD_ROOT)
        hs = homes(root)
        home_dirs = {root / h for h in hs}

        def reading() -> dict:
            """Both walks over the synthetic tree -- THE SAME PAIR `report()` bridges."""
            return project([p for p, _ in walk(root, hs)], control(root)[0], home_dirs)

        base = reading()
        (root / "gates" / DEEPER).parent.mkdir(parents=True)
        (root / "gates" / DEEPER).write_text(guarded('print("ok")'))
        for dotted in (DOT_A, DOT_B):
            (root / "gates" / dotted).write_text(guarded('print("ok")'))
        moved = reading()
        for planted in (DEEPER, DOT_A, DOT_B):        # RESTORE, because `TemporaryDirectory` is
            (root / "gates" / planted).unlink()       # the only control this case has
        (root / "gates" / DEEPER).parent.rmdir()
        restored = reading()
        want_deep, want_dot = len(base["deep"]) + 1, len(base["dot"]) + 2
        if plant:
            want_deep += 1                            # the third planted lie, on the bridge
        bridge_ok = (hs == HOMES and base["walk"] == len(PLANTS) + 1
                     and base["held"] and base["deep"] == [] and base["dot"] == []
                     and moved["held"] and len(moved["deep"]) == want_deep
                     and len(moved["dot"]) == want_dot
                     and moved["deep"] == [root / "gates" / DEEPER]
                     and [p.name for p in moved["dot"]] == [DOT_A, DOT_B]
                     and moved["walk"] == base["walk"] + 1
                     and moved["control"] == base["control"] + 2
                     and restored == base)
        results.append(("BRIDGE: the two walks differ by DEPTH and by DOTTED NAMES, the projection "
                        "MOVES by exactly those amounts, and RESTORING the copy puts it back",
                        bridge_ok,
                        f"homes {hs} from the planted {WITNESS}; base walk {base['walk']} "
                        f"control {base['control']} deep {len(base['deep'])} dot "
                        f"{len(base['dot'])} bridged {base['bridged']} held {base['held']}"
                        f" -> +{DEEPER} +{DOT_A} +{DOT_B} -> walk {moved['walk']} control "
                        f"{moved['control']} deep {len(moved['deep'])} (want {want_deep}) dot "
                        f"{len(moved['dot'])} (want {want_dot}) bridged {moved['bridged']} held "
                        f"{moved['held']} -> restored == base: {restored == base}"
                        if bridge_ok else
                        f"homes {hs} want {HOMES}; base {base} want walk {len(PLANTS) + 1}; "
                        f"moved deep {len(moved['deep'])}/{want_deep} dot "
                        f"{len(moved['dot'])}/{want_dot} walk {moved['walk']}/{base['walk'] + 1} "
                        f"control {moved['control']}/{base['control'] + 2}; "
                        f"restored == base: {restored == base}"))

        # THE FALSIFICATION, AND IT IS THE CLAUSE THAT MAKES `held` A MEASUREMENT. A file cannot
        # make the two walks disagree on its own -- they share `entry_reason` -- so the third
        # reason is PLANTED: an immediate, undotted member the control is DENIED. Neither rule can
        # explain it, so `extra` is non-empty and `held` is FALSE. **A check that cannot go red is
        # a constant wearing a check's name**, and `held` computed as a set difference would be
        # exactly that -- see `project()`.
        (root / "gates" / THIRD).write_text(guarded('print("ok")'))
        lying = project([p for p, _ in walk(root, hs)],
                        [p for p in control(root)[0] if p != root / "gates" / THIRD], home_dirs)
        (root / "gates" / THIRD).unlink()
        (root / "gates" / WITNESS).unlink()          # the WIDTH plant's base is `len(PLANTS)` alone
        lies_ok = (not lying["held"] and lying["extra"] == [root / "gates" / THIRD]
                   and lying["deep"] == [] and lying["dot"] == [] and lying["stray"] == [])
        results.append(("FALSIFICATION: a THIRD difference the two rules cannot explain makes "
                        "`held` FALSE and NAMES the member -- so `HELD` is not a constant",
                        lies_ok,
                        f"{THIRD} denied the control -> held {lying['held']} bridged "
                        f"{lying['bridged']} vs control {lying['control']} "
                        f"(DIFFERS BY {lying['bridged'] - lying['control']:+d}); extra "
                        f"{[p.name for p in lying['extra']]}, deep {len(lying['deep'])}, dot "
                        f"{len(lying['dot'])}, stray {len(lying['stray'])}"
                        if lies_ok else
                        f"held {lying['held']} bridged {lying['bridged']} control "
                        f"{lying['control']} extra {[p.name for p in lying['extra']]} "
                        f"(want [{THIRD}]) deep {len(lying['deep'])} dot {len(lying['dot'])} "
                        f"stray {len(lying['stray'])}"))

        # THE WIDTH PLANT, BOTH DIRECTIONS. `base` is the walk over the fixtures ALONE, so every
        # expected number below is `len(PLANTS)` -- a declared constant -- and never the observed
        # value it is checking, which would be a tautology with a denominator.
        base = walk(root, HOMES)
        want_base = len(PLANTS)
        (root / "gates" / UNCONFORMING).write_text(guarded('print("ok")'))
        (root / "gates" / SCRIPT).write_text(SCRIPT_SRC)
        grew, grew_sfx = walk(root, HOMES), suffix(root, HOMES)
        (root / "gates" / PLANTS[0][0]).unlink()      # delete ONE CONFORMING member
        shrank, shrank_sfx = walk(root, HOMES), suffix(root, HOMES)
        if plant:
            want_base += 1                             # the second planted lie, on the population
        width_ok = (len(base) == want_base
                    and len(grew) == want_base + 1 and len(grew_sfx) == want_base
                    and len(shrank) == want_base and len(shrank_sfx) == want_base - 1)
        results.append(("WIDTH: a NON-CONFORMING name joins the walk and misses the suffix, and "
                        "deleting a conforming one moves BOTH back",
                        width_ok,
                        f"walk {len(base)} (want {want_base}) -> +{UNCONFORMING} -> {len(grew)} "
                        f"want {want_base + 1}, suffix {len(grew_sfx)} want {want_base}; "
                        f"-{PLANTS[0][0]} -> walk {len(shrank)} want {want_base}, "
                        f"suffix {len(shrank_sfx)} want {want_base - 1}"
                        f"; {SCRIPT} (no entry guard) stayed OUT at {len(grew) - len(base)} added"
                        if width_ok else
                        f"walk {len(base)}/{want_base} -> {len(grew)}/{want_base + 1} "
                        f"(sfx {len(grew_sfx)}/{want_base}) -> {len(shrank)}/{want_base} "
                        f"(sfx {len(shrank_sfx)}/{want_base - 1})"))

    failed = 0
    for name, ok, detail in results:
        print(f"[{'PASS' if ok else 'FAIL':>4}] {name}\n          {detail}")
        failed += 1 if not ok else 0
    print(f"\n=== selftest {'PASS' if not failed else 'FAIL'}: {len(results)} case(s), "
          f"{failed} failed{' -- PLANTED, and the failure is the point' if plant else ''} ===")
    return gatekit.FAIL if failed else gatekit.PASS


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
