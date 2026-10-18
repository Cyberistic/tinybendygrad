#!/usr/bin/env python3
"""lane-census.py -- A MEMBER THAT PRINTED ROWS AND HAD THEM COMPARED BY NOTHING IS NOT A PASS.

    .venv/bin/python gates/lane-census.py            # the census, no execution (the sweep's default)
    .venv/bin/python gates/lane-census.py --run      # ... and EXECUTE every unconsumed member
    .venv/bin/python gates/lane-census.py --rows     # one `member=` line per executed member
    .venv/bin/python gates/lane-census.py --plant    # two plants; the second is the vacuity guard
    .venv/bin/python gates/lane-census.py --rss      # peak RSS + wall clock only, run nothing

`checks/gatesweep.py` runs every entry point in the derived gate homes, keeps `$?`, and prints the
word. MEASURED 2026-10-18T18:15:41Z on its own `--plan`: `WALK 250`. Its classifier
(`checks/gatesweep.py:248`) reads `rc == 0 and not text.strip()` as `DEAD` and everything else
falls through to `gatekit.VERDICT[0]`, which is **`PASS`**. A bare lane prints rows and exits 0,
so it lands on `PASS` -- and `PASS` in that tally means "it agreed". It agreed with NOTHING.

    $ .venv/bin/python gates/tn_add_sub-oracle.py ; echo "rc=$?"
    add_op_is_add=1
    ... 18 more `name=value` rows ...
    rc=0

**THIS IS DOCTRINE 2'S `DEAD`, AND THE CLASS IS NOT NEW.** `gates/gatekit.py:646` already returns
`DEAD if n == 0 else FAIL` for a gate's OWN lane, so a gate whose driver emits nothing is honest
today. **The gap is entirely OUTSIDE `gatekit`: it is the lane run BARE**, which no `Gate` object
exists to notice, and the only thing that sees it is the sweep's exit-status classifier.

## WHY THERE IS NO LANE FILTER IN HERE, AND WHY THE COUNT IS NOT WRITTEN DOWN

The obvious repair is to teach the sweep "do not run a lane", and a filter needs to know which
files are lanes. MEASURED, that question has no cheap answer in this tree. The reading below is
2026-10-18T18:43:57Z, `--run --seconds 4` over four attempts, and **the walk MOVES**: it read 250
members at 18:15:41Z and 251 at 18:43:57Z, because other units are writing gates into it.

  NAMED    15 of the walk's members are named by a `Gate(...)` `oracle=`/`bend=` argument read off
           the AST (`declared()`, below). 124 distinct lane filenames are named tree-wide and 15
           of THEM are walk members; the rest live outside the homes (`.agents/slop/`, ...). The
           first version of this file measured 13 at 18:16:42Z; it is 15 an hour later, and a
           figure written down once is wrong within the hour, which is why `report()` prints it.
  SHAPE    a stem carrying `oracle` finds 20 of the walk's members, and the tree holds 28 such
           filenames tree-wide. `AGENTS.md`'s DOCTRINE 1: "A BASENAME SHAPE, A SUFFIX SET, AND A
           HAND LIST ARE NOT POPULATIONS", and `gates/oracleblind-census.py` already reports that
           walk as "a second CLASS ... an oracle no gate names is a denominator, not a verdict".

**AND THE SHAPE IS NOT THE CLASS.** MEASURED, of the 20 oracle-shaped walk members, 7 are
unconsumed AND print rows; the other 13 are either silent or already declared. So **the honest
denominator is the walk, not the spelling**: 236 unconsumed members, of which **12 printed 2,160
`name=value` rows that no `Gate` names**, over 4 attempts at a 4 s per-member cap, with **111 of
the 236 UNCLASSIFIED** (`TIMED-OUT` at that cap) -- so **12 IS A LOWER BOUND, not a total**, and
this file prints the unclassified count beside it for exactly that reason.

So a filter would be a list wearing a declaration's clothes, and this file refuses to be one.
**NO LANE NAME APPEARS IN THIS FILE, AND NONE MAY BE ADDED.** Membership below is a walk plus an
AST, both loaded by path.

## THE MECHANISM: A LANE IS DISCOVERABLE BY WHAT IT PRINTS

A lane's consumer is declared, and the declaration is the ROW NAME:

  `gatekit.Gate` carries `rows=` (how many `name=value` rows each lane emits BEFORE exclusions)
  and `pins=[(lane, row)]` -- extra `(lane, row_name)` assertions that a named row is PRESENT in a
  named lane (`gates/gatekit.py`, `Gate.__init__`'s docstring). Those are DECLARATIONS OF ROW
  NAMES, owned by the consumer and read off the AST.

A lane's output is what it printed. So the join that makes a lane discoverable is:

    printed_rows(member)  INTERSECT  declared_rows(the Gates that name it)  ==  nothing

and for a member no `Gate` names, the intersection is empty **by definition and without running
anything**. What is NOT free is `printed_rows` for an unconsumed member -- the tree holds no record
of it, because `gatekit.Gate.__init__` writes each lane's captured streams under
`gates/artifacts/<name>/` and an unconsumed member owns no artifact directory. So:

  `--run`   EXECUTES the member (one subprocess, under `checks/bounded.py`, LOADED BY PATH) and
            parses its stdout for the `name=value` grammar. This is the only arm that can be wrong
            about a lane, which is why it is the arm that is optional and the arm the plant moves.
  no `--run` the census still reports the DENOMINATOR it can reach without executing: how many
            walk members no `Gate` names at all. That number is a bound on the class, never a
            verdict on it, and it is printed as such.

**COST, MEASURED, AND IT IS WHY `--run` IS NOT THE DEFAULT.** Execution-based discovery costs one
subprocess per unconsumed member. `checks/gatesweep.py --plan` (2026-10-18T18:15:41Z) answers
`WALK 250`, of which 215 are undeclared `py-main`; 25 of the first 25 probed by hand did not finish
inside a 120 s wall, and the undeclared set contains the `bend`-launching lanes.

**THE FULL CENSUS'S OWN PRICE, MEASURED 2026-10-18T18:32:02Z-18:43:57Z.** A 4 s per-member cap
classified **125 of 236** members `WITHIN-LIMITS` and left **111 `TIMED-OUT`**; covering the 236
took **FOUR ATTEMPTS and ~12 minutes of wall clock**, because the `bend` precondition below stopped
each attempt after 15 members whenever another unit's `bend` came up. Largest single member peak
**1,296 MB** (watchdog-reported), so a census that ran the whole unconsumed set in one process
would sit far above the 60 %-of-`hw.memsize` sum-precondition `AGENTS.md` sets. **A CENSUS THAT
RUNS THE SWEEP IS A SWEEP, SO THE DEFAULT RUNS NOTHING.** `--run` is one arm behind an explicit
flag, `--rows` prints one machine-readable `member=` line per member so an interrupted run can
report what it DID finish, and `--rss` measures without executing.

## THE `bend` PRECONDITION, AND IT IS A PRECONDITION RATHER THAN A FILTER

`AGENTS.md`: "NEVER TWO CONCURRENT `bend` PROCESSES (two units are live)." MEASURED at
2026-10-18T18:17:14Z, one was in flight (`bend2/main.ts ... .agents/slop/graphcmp.bend range`), and
MEASURED AGAIN at 18:25-18:33Z, one appeared MID-RUN and stopped a census 236 members into the
class -- so the check is taken before every member and not once at the start. The refusal is
`REFUSED` (3) and not a zero: **a census that measured nothing because the machine was busy is not
a census that found nothing**, and the two share an exit only if the exit is not the verdict.

## WHY THE ORACLE'S OWN EXIT IS NOT WHERE THE RULE LIVES

The brief asks for the rule "at the oracle's own exit". MEASURED, it cannot go there, and the
reason is structural rather than difficult:

**the number of rows a bare lane should print is declared by its CONSUMER** (`Gate.rows`), so a
lane with no consumer has no expected row count to check itself against. Charging its own exit
would mean writing that count into the lane -- i.e. naming it, which is the forbidden list, and it
is the same list that made 15 of these lanes unnamed in the first place. **The rule therefore
lives in the RUNNER, and this file IS that runner**, as a gate over the class rather than as an
edit to 200 files it is forbidden to touch.

`gates/gatekit.py` needs NO CHANGE and gets none: `run()` already returns `DEAD if n == 0` for a
lane it launched (`gates/gatekit.py:646`). The gap is upstream of `gatekit` and downstream of it
nowhere.

## THE FIVE VERDICTS, AND WHICH OF THEM THIS FILE CAN REACH

`DEAD 5` (a walk member printed lane rows and no `Gate` names it -- it ran, it said something, and
nothing compared it), `REFUSED 3` (a `bend` process is in flight or appeared mid-run,
`checks/gatesweep.py` / `checks/bounded.py` / `gates/gatekit.py` is absent, the walk is empty, or
`--run` stopped before it covered the unconsumed set), `PASS 0` (every executed lane was named by a
`Gate`).

**AND `PASS` IS UNREACHABLE IN `--run` ITSELF, WHICH IS WHY PLANT 2(a) EXISTS.** MEASURED: `--run`
iterates the UNCONSUMED members only -- executing a consumed lane a second time would launch `bend`
for a comparison `gatekit` has already made -- so `declared_by` is structurally 0 for every member
it runs, and at 2026-10-18T18:43:57Z the live reading was 12 `DEAD` and **0 rows with
`declared>0`**. The `PASS` branch of `verdict()` therefore has NO live witness in this file's own
`--run`, and a branch with no witness is a branch nobody checks -- which is why PLANT 2 plants a
consumed lane rather than looking for one.

**`FAIL 1` AND `SKIP 4` ARE UNREACHABLE HERE AND THAT IS A CLAIM, NOT AN OMISSION.** `FAIL` needs
a pinned baseline, and **this file HAS NO PINS**: a census that drifts is a wider class, not a
different answer, and `gates/gates-pop.py:read_ledger` is where the tree keeps that record instead
-- so quoting a `FAIL` this file cannot emit would be a verdict with no code path, which is the
`SKIP` comment `gates/gatekit.py` already makes about its own vacant slot. `SKIP` needs something
that could not run, and every arm here either runs or the WHOLE arm is `REFUSED`; `--rows` and the
bare run measure the declaration census, which always has a denominator because the walk always has
members.

## THE PLANT, AND WHY ITS NEGATIVE CASE IS NOT VACUOUS

PLANT 1 -- **THE FALSE PASS LEAVES `PASS`.** A synthetic member is planted that prints lane rows
and is named by no `Gate`, and the SAME captured output is classified twice: by
`checks/gatesweep.py`'s own `classify()` -- loaded BY PATH, the real function, not a copy of it --
and by `verdict()` here. The plant asserts `PASS` from the first and `DEAD` from the second, and it
prints `comparisons=0 disagreements=0` from this file's own arithmetic, so the literal state the
brief names is on the record rather than paraphrased.

PLANT 2 -- **THE VACUITY GUARD, AND IT IS TWO DIRECTIONS.** A rule that fires on everything is
satisfied by PLANT 1 alone, so PLANT 2 asserts the rule does NOT fire on either shape that must not
be DEAD by it:

  (a) a member that PRINTS lane rows AND IS NAMED BY A `Gate` -- the consumed lane. Charging it
      would make every gate in the tree DEAD and would make the census a tautology;
  (b) a member that prints PROSE and no `name=value` row -- a census, a reporter, `--help`. **This
      is the "flatten both sides to one constant" trap the brief names**: a rule that charged every
      undeclared member would pass PLANT 1 and be unable to tell a lane from a census, and the
      vacuous version -- `no Gate names it -> DEAD`, with the printed-rows test dropped -- is
      asserted to be WRONG here, so a later edit that drops the grammar arm turns this plant RED
      instead of green.
"""
from __future__ import annotations

import argparse
import ast
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import time
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY = ROOT / ".venv" / "bin" / "python"

GATESWEEP = ROOT / "checks" / "gatesweep.py"      # the WALK and the classifier, LOADED BY PATH
BOUNDED = ROOT / "checks" / "bounded.py"          # the watchdog, LOADED BY PATH

# THE ROW GRAMMAR. `gates/oracleblind-census.py` parses the same shape and calls it "this tree's
# `(row_name, value)` convention"; `gatekit._lines` counts every non-blank line, which is WIDER and
# would charge every gate's prose to the lane class. `name=` is the narrow one and the tree's own.
ROW = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

# HOW MANY MEMBERS ARE NAMED BY A `Gate(...)` CALL, AND WHICH ARGUMENTS NAME A LANE. `Gate` is
# `gatekit.Gate`, and every lane-taking keyword of its signature is listed here BECAUSE THE
# SIGNATURE IS THE DECLARATION -- a new lane keyword added to `Gate` without a line here is a
# member this census cannot reach, which is why the count below is printed with its own denominator
# rather than trusted. These are ARGUMENT NAMES of a constructor, not lane names.
LANE_KWARGS = ("oracle", "bend")
GATE_CTOR = "Gate"


def load(name: str, path: Path):
    """A MODULE, LOADED BY PATH, and never re-derived here.

    `gates/arenasrc_census.py` fixed its membership by making its population BE `nilsrc`'s own
    declaration (loaded by path), so `rows == declared sites` holds by construction and is also
    asserted; `gates/gates-pop.py:gate_homes()` is the same shape for the homes. This file owns no
    population of its own and spells no path into one.
    """
    if not path.is_file():
        return None
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def gatesweep():
    return load("gatesweep_for_lane_census", GATESWEEP)


def bounded():
    return load("bounded_for_lane_census", BOUNDED)


# ---------------------------------------------------------------------------------------------
# POPULATION ONE: THE WALK. Nothing is spelled; `population()` is the sweep's own, and the sweep's
# own is `gates/gates-pop.py`'s `gate_homes()` + `entry_reason()` under `os.walk`.
def population(gs) -> list[tuple[Path, str]]:
    return gs.population()


# ---------------------------------------------------------------------------------------------
# POPULATION TWO: THE DECLARATION. `Gate(...)` call sites read off the AST of the walk itself, so
# the declaring set is a SUBSET of the walked set by construction and a lane outside the homes can
# only be named, never walked.
def declared(members: list[tuple[Path, str]]) -> dict[str, list[str]]:
    """`{lane filename -> [gate paths that name it]}`, from `Gate(oracle=..., bend=...)`.

    Read off the AST, never off a spelling of the filename and never off a `grep -l oracle`. A
    member of the walk that appears here is a CONSUMED LANE: some `Gate` launches it, diffs it and
    pins its rows. The reverse of this map -- `rows a gate pins` -- is what makes a lane
    discoverable by what it prints, and `checks/gatesweep.py` needs no change to use it because
    the map is built from the walk it already has.
    """
    out: dict[str, list[str]] = {}
    for path, _reason in members:
        if path.suffix != ".py":
            continue
        try:
            tree = ast.parse(path.read_text(errors="replace"))
        except (SyntaxError, ValueError):
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            if getattr(node.func, "id", None) != GATE_CTOR:
                continue
            for kw in node.keywords:
                if kw.arg not in LANE_KWARGS:
                    continue
                val = kw.value
                if isinstance(val, ast.Constant) and isinstance(val.value, str):
                    out.setdefault(Path(val.value).name, []).append(str(path))
    return out


def _module_rows(tree: ast.Module) -> dict[str, tuple[str, ...]]:
    """`{NAME: the string constants of a module-level tuple/list}` -- a LOCAL vocabulary, resolved.

    MEASURED, and it is the reason this function exists in this shape. The first version read
    `pins=[(lane, row) for lane in ("py", "bd") for row in ROWS]` as "not a list" and skipped it,
    so 6 lanes reported a pinned vocabulary where the walk holds 68 `Gate(` sites -- **the exact
    defect `AGENTS.md` records under `checks/repro-paths.py`, "IT STOPPED AT A *REMEMBERED*
    EXTENSION, SO A PREFIX OF A PATH WAS READ AS THE PATH"**: a comprehension is the commonest
    spelling of this declaration and a shape that only knows `ast.List` cannot see it. So the
    comprehension is resolved through the module's OWN names, and a comprehension this cannot
    resolve is COUNTED (`dynamic`) rather than dropped.
    """
    out: dict[str, tuple[str, ...]] = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 \
                and isinstance(node.targets[0], ast.Name) \
                and isinstance(node.value, (ast.Tuple, ast.List)):
            consts = tuple(e.value for e in node.value.elts
                           if isinstance(e, ast.Constant) and isinstance(e.value, str))
            if len(consts) == len(node.value.elts):
                out[node.targets[0].id] = consts
    return out


def pinned_rows(members: list[tuple[Path, str]]) -> tuple[dict[str, set[str]], int]:
    """`({lane filename -> {pinned row names}}, dynamic_count)`, from `Gate(pins=[...])`.

    THE ROW-NAME VOCABULARY. This is the half of the mechanism that costs nothing: a consumer
    DECLARES the row names it needs from a lane, so the tree already owns a declaration of what a
    consumed lane prints and the join to the printed rows needs no list. `gates/gatekit.py` holds
    the same rows as `(lane, row)` tuples and asserts each one is PRESENT in the lane's raw
    (`gates/gatekit.py`, the `for lane, row in self.pins:` loop) -- so a pinned row that a lane
    stopped printing is already a FAIL there, and this map cannot be a second opinion that rots.

    `dynamic_count` is the number of `pins=` values this function could not resolve to row names.
    It is RETURNED rather than swallowed: a shape that cannot see its own population must print the
    part it cannot see, or it is a denominator dressed as a verdict.
    """
    out: dict[str, set[str]] = {}
    dynamic = 0
    for path, _reason in members:
        if path.suffix != ".py":
            continue
        try:
            tree = ast.parse(path.read_text(errors="replace"))
        except (SyntaxError, ValueError):
            continue
        vocab = _module_rows(tree)
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call) or getattr(node.func, "id", None) != GATE_CTOR:
                continue
            own = {k.arg: k.value for k in node.keywords if k.arg}
            orc = own.get("oracle")
            name = Path(orc.value).name if isinstance(orc, ast.Constant) else None
            pins = own.get("pins")
            if name is None or pins is None:
                continue
            pairs: list[ast.expr] = []
            if isinstance(pins, (ast.List, ast.Tuple)):
                pairs = list(pins.elts)
            elif isinstance(pins, (ast.ListComp, ast.GeneratorExp)):
                # the last `for x in <literal>` target is the ROW, and its iterable is the ROWS tuple
                last = pins.generators[-1]
                rows = vocab.get(last.iter.id if isinstance(last.iter, ast.Name) else "")
                if rows is None:
                    dynamic += 1
                    continue
                pairs = [ast.Tuple(elts=[ast.Constant(lane), ast.Constant(row)], ctx=ast.Load())
                         for lane in ("py", "bd") for row in rows]
            else:
                dynamic += 1
                continue
            for elt in pairs:
                if not isinstance(elt, (ast.Tuple, ast.List)) or len(elt.elts) != 2:
                    continue
                row = elt.elts[1]
                if isinstance(row, ast.Constant) and isinstance(row.value, str):
                    out.setdefault(name, set()).add(row.value)
    return out, dynamic


# ---------------------------------------------------------------------------------------------
# POPULATION THREE: WHAT A MEMBER PRINTS. The only arm that can be wrong about a lane, so it is
# the arm that is opt-in.
def bend_in_flight() -> list[str]:
    """The `bend` processes this machine is already running, by PROCESS LIST.

    `AGENTS.md`'s rule is "NEVER TWO CONCURRENT `bend` PROCESSES", and a census that executes lanes
    launches them. Asking `ps` is a MEASUREMENT of the machine; naming a pid file would be a
    declaration that a second unit's run does not honour.
    """
    try:
        out = subprocess.run(["ps", "-Ao", "args"], capture_output=True, text=True,
                             timeout=15).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    return [l.strip() for l in out.splitlines() if "bend2/main.ts" in l and "grep" not in l]


def rows_in(text: str) -> list[str]:
    return [l for l in (text or "").splitlines() if ROW.match(l)]


def execute(path: Path, reason: str, gs, seconds: float) -> tuple[str, str, int, float, float]:
    """`(stdout, token, rc, peak_mb, seconds_taken)` for ONE member, under `checks/bounded.py`.

    THE INTERPRETER IS THE SWEEP'S OWN `RUNNERS`, LOADED BY PATH (`checks/gatesweep.py:144`), and
    NOT re-derived here. MEASURED, the cost of deriving it: this function's first version spelled
    `py -> .venv/bin/python` and reached for a `PY` that `checks/bounded.py` does not have, so the
    first `sh-*` member of the walk raised `AttributeError` and the whole census died 236 members
    into its own run. `checks/gatesweep.py:run_one` already says the rule out loud -- "an UNKNOWN
    reason is a REFUSAL rather than a guess: `RUNNERS.get(reason.split("-")[0], [])` on a language
    this tree grows would hand it to the Python interpreter" -- and a second spelling of that
    table is a list wearing a declaration's clothes, the class this file refuses to be.

    THE TOKEN IS THE CONTRACT, because the watchdog's own header records that a unit lost 425 rows
    by believing the exit status instead. **THIS FUNCTION RETURNS THE TOKEN AND NOBODY READS
    `$?`:** the caller decides `DEAD` from `printed rows` and from `declared`, never from the
    child's exit.
    """
    runner = gs.RUNNERS.get(reason.split("-")[0]) if reason else None
    if not runner:
        return "", f"NO-RUNNER({reason})", 3, 0.0, 0.0
    env = dict(os.environ, DEV="CPU", SPEC="1", PYTHONDONTWRITEBYTECODE="1")
    with tempfile.TemporaryDirectory() as td:
        out_f, err_f = Path(td) / "o", Path(td) / "e"
        cmd = [str(PY), str(BOUNDED), "--seconds", str(int(seconds)), "--mb", "2048",
               "--", *runner, str(path)]
        with out_f.open("wb") as o, err_f.open("wb") as e:
            t0 = time.time()
            r = subprocess.run(cmd, stdout=o, stderr=e, cwd=str(ROOT), env=env,
                               timeout=seconds * 4)
            elapsed = time.time() - t0
        err = err_f.read_text(errors="replace")
        m = re.search(r"peak-RSS=([0-9.]+)", err)
        tok = re.search(r"\[bounded\] (\S+)", err)
        return (out_f.read_text(errors="replace"), (tok.group(1) if tok else "NO-RECORD"),
                r.returncode, float(m.group(1)) if m else 0.0, elapsed)


# ---------------------------------------------------------------------------------------------
# THE VERDICT. Five words, `gates/gatekit.py`'s table, LOADED BY PATH -- never a second copy.
def verdicts(gk):
    return gk.PASS, gk.FAIL, gk.REFUSED, gk.SKIP, gk.DEAD


# THE THREE WORDS THIS RULE CAN PRODUCE, AND WHY A MEMBER THAT PRINTED NO LANE ROW IS NOT ONE OF
# THE TWO VERDICTS. `NOT-A-LANE` is a LABEL rather than a verdict: the member ran and said
# something, and the question this census asks ("did anything compare its rows?") has no answer for
# it because it asked none. Charging it `DEAD` here would double-count `gates/gatesweep.py`'s own
# SILENT arm, and charging it `PASS` would repeat the defect this file exists for.
NOT_A_LANE = "NOT-A-LANE"


def verdict(printed_rows: int, declared_by: int, dead: int, pass_code: int) -> tuple[int, str]:
    """`(exit, word)` for ONE member. The whole rule, in three lines and no names.

    A member that printed lane rows and that no `Gate` names compared NOTHING, so it is `DEAD`: it
    ran, it said something, and the thing it said was never diffed against anything. A member a
    `Gate` names is that gate's own lane and is not this class. A member that printed no lane row
    is not this class either -- it may have said nothing at all (`gates/gatesweep.py`'s own `DEAD`,
    one arm further out) or it may have printed prose (a census, a reporter, `--help`), and telling
    those two apart is what the `--plant` vacuity guard holds still.
    """
    if not printed_rows:
        return pass_code, NOT_A_LANE
    return (dead, "DEAD") if not declared_by else (pass_code, "PASS")


# ---------------------------------------------------------------------------------------------
# THE REPORT
def report(run: bool, seconds: float, show_rows: bool) -> int:
    gs, bd = gatesweep(), bounded()
    if gs is None:
        print("== REFUSED, NOT A VERDICT: checks/gatesweep.py is absent -- the WALK and the "
              "classifier are LOADED BY PATH, not re-derived here", file=sys.stderr)
        return 3
    if bd is None:
        print("== REFUSED, NOT A VERDICT: checks/bounded.py is absent -- the watchdog is LOADED "
              "BY PATH", file=sys.stderr)
        return 3
    gk = load("gatekit_for_lane_census", HERE / "gatekit.py")
    if gk is None:
        print("== REFUSED, NOT A VERDICT: gates/gatekit.py is absent -- the five verdicts are "
              "LOADED BY PATH", file=sys.stderr)
        return 3
    PASS, _, REFUSED, _, DEAD = verdicts(gk)

    members = population(gs)
    if not members:
        print("== REFUSED, NOT A VERDICT: the WALK is EMPTY, and a population that cannot fail "
              "is `artefacts_ok()`'s shape", file=sys.stderr)
        return REFUSED
    by_reason = Counter(r for _, r in members)
    named = declared(members)
    pins, dynamic = pinned_rows(members)
    named_here = {p.name for p, _ in members}
    consumed = sorted(n for n in named if n in named_here)

    # THE BEND PRECONDITION, AS A MEASUREMENT. A census that cannot run because the machine is busy
    # has measured nothing, and REFUSED is the only honest word for it.
    flying = bend_in_flight() if run else []

    unconsumed = [(p, r) for p, r in members if p.name not in named]
    print(f"POPULATION : walk() entry points in the derived homes  -> {len(members)}   "
          f"({', '.join(f'{k}={v}' for k, v in sorted(by_reason.items()))})")
    print(f"DECLARED   : `Gate(` call sites in that walk              -> "
          f"{sum(1 for p, _ in members if _declares(p))}")
    print(f"LANES      : distinct lane filenames named tree-wide     -> {len(named)}")
    print(f"CONSUMED   : of those, MEMBERS OF THIS WALK               -> {len(consumed)}")
    print(f"PINS       : lanes with a declared ROW NAME (`pins=`)     -> {len(pins)}"
          f"   ({sum(len(v) for v in pins.values())} row names; {dynamic} `pins=` value(s) "
          f"this reader could not resolve and did NOT count)")
    print(f"UNCONSUMED : walk members no `Gate` names                 -> {len(unconsumed)}"
          f"   [BOUND on the class, not a verdict on it]")

    if not run:
        print("RUN        : REFUSED BY THE CALLER -- this mode EXECUTES NOTHING. `--run` executes "
              "the\n             unconsumed members and is refused while a `bend` process is in "
              "flight; `--rss`\n             measures this census without executing it.")
        print(f"LANE-CENSUS: {'OK' if not unconsumed else 'BOUND ONLY'} -- "
              f"{len(unconsumed)} of {len(members)} walk members are named by no `Gate`, and this "
              "mode\n             did not execute one of them, so no member's PRINTED rows are "
              "known.")
        return REFUSED if flying else 0

    if flying:
        print(f"REFUSED    : {len(flying)} `bend` process(es) already in flight -- "
              "`AGENTS.md` forbids two at once,\n             and a census that refused to measure "
              "is REFUSED (3), not 0.")
        for l in flying[:4]:
            print(f"             in flight: {l[:110]}")
        print(f"LANE-CENSUS: REFUSED -- {len(unconsumed)} member(s) NOT RUN. "
              f"comparisons=0 disagreements=0 is NOT a verdict here.")
        return REFUSED

    rows_out: list[tuple[Path, str, int, int, float]] = []
    peak_max = 0.0
    stopped = ""
    t_start = time.time()
    for path, reason in unconsumed:
        # THE PRECONDITION IS CONSULTED BEFORE EVERY MEMBER, NOT ONCE AT THE START. MEASURED, that
        # is the difference between a rule and a snapshot: another unit's `bend` can start inside
        # a 236-member run, and a check taken before the loop would have launched a second one
        # while reporting that the machine was clear. `gates/gatekit.py` already holds the shape
        # (`device_precondition` is consulted on EVERY run, not once), and this is the same rule
        # about a different resource.
        flying_now = bend_in_flight()
        if flying_now:
            stopped = (f"a `bend` process appeared mid-run ({len(flying_now)} live) -- "
                       f"{len(unconsumed) - len(rows_out)} member(s) NOT RUN")
            print(f"STOPPED AT {len(rows_out)}: {stopped}.")
            break
        out, tok, _rc, peak, _took = execute(path, reason, gs, seconds)
        peak_max = max(peak_max, peak)
        rows_out.append((path, tok, len(rows_in(out)), len(named.get(path.name, ())), peak))
        # ONE MACHINE-READABLE LINE PER EXECUTED MEMBER, whatever it printed. `--rows` used to print
        # only the rows, so an interrupted run could say nothing about the 15 members it had already
        # classified -- and a census that cannot report what it finished measured nothing on those
        # either. The line is `member=` so it parses with the SAME grammar as a lane row.
        if show_rows:
            print(f"member={path.relative_to(ROOT)} rows={len(rows_in(out))} "
                  f"declared={len(named.get(path.name, ()))} token={tok} rc={_rc} peak={peak:.0f}")
            for l in rows_in(out):
                print(f"  {path.name}: {l[:96]}")
        else:
            print(f"member={path.relative_to(ROOT)} rows={len(rows_in(out))} "
                  f"declared={len(named.get(path.name, ()))} token={tok} rc={_rc} peak={peak:.0f}",
                  flush=True)

    lanes = [(p, t, n, d, pk) for p, t, n, d, pk in rows_out if n]
    dead = [x for x in lanes if not x[3]]
    silent = [x for x in rows_out if not x[2]]
    compared = sum(min(n, d) for _p, _t, n, d, _pk in lanes)
    print(f"EXECUTED   : {len(rows_out)}/{len(unconsumed)} member(s), {seconds:g}s cap each, "
          f"serially, DEV=CPU SPEC=1")
    print(f"PRINTED    : members that emitted >=1 `name=value` row -> {len(lanes)}")
    print(f"SILENT     : members that emitted none                  -> {len(silent)}"
          f"   [NOT this class -- `gates/gatesweep.py` answers SILENT/DEAD for those]")
    print(f"DEAD       : printed rows and NO declared consumer       -> {len(dead)}")
    print(f"COMPARISONS: declared row names met by printed rows      -> {compared}")
    print(f"DISAGREES  : {0 if not dead else 'n/a -- nothing compared them'}"
          f"   over {compared} comparisons")
    print(f"PEAK RSS   : {peak_max:.0f} MB (the largest single member, watchdog-reported); "
          f"wall {time.time() - t_start:.0f}s for {len(rows_out)} member(s)")
    if stopped or len(rows_out) < len(unconsumed):
        why = stopped or "the loop ended early"
        print(f"\nLANE-CENSUS: REFUSED -- {why}. {len(rows_out)} of {len(unconsumed)} "
              f"unconsumed\n             member(s) were executed, so this run MEASURED NOTHING "
              f"ABOUT THE REST, and\n             `PASS` over an unexecuted population is the "
              f"`0 disagreements over 0\n             comparisons` shape this file exists for. "
              f"comparisons={compared}.")
        return REFUSED
    if dead:
        print("\nDEAD, and each of these ran, printed rows, and had them compared by nothing:")
        for p, tok, n, _d, _pk in dead:
            print(f"  DEAD  rc=0 rows={n:<4} token={tok:<14} {p}")
        print(f"\nLANE-CENSUS: DEAD -- {len(dead)} member(s) printed lane rows with no declared "
              f"consumer,\n             over a walk of {len(members)}. "
              f"comparisons={compared} disagreements=0.")
        return DEAD
    print(f"\nLANE-CENSUS: PASS -- {len(lanes)} lane(s) executed, every one named by a `Gate`, "
          f"over a walk of\n             {len(members)}; {compared} comparisons.")
    return 0


def _declares(path: Path) -> bool:
    """Whether this member's OWN SOURCE calls `Gate(...)` -- the gate/no-gate split, off the AST."""
    if path.suffix != ".py":
        return False
    try:
        tree = ast.parse(path.read_text(errors="replace"))
    except (SyntaxError, ValueError, OSError):
        return False
    return any(isinstance(n, ast.Call) and getattr(n.func, "id", None) == GATE_CTOR
               for n in ast.walk(tree))


# ---------------------------------------------------------------------------------------------
# THE PLANTS. The negative case is TWO directions, because the vacuous rule and the wrong rule
# both pass a single positive plant.
PLANT_LANE = (
    "# a synthetic lane: prints `name=value` rows and is named by NO Gate\n"
    "print('plant_row_a=1')\n"
    "print('plant_row_b=1')\n"
)
PLANT_PROSE = (
    "# a synthetic census: says something, and says NONE of it in the row grammar\n"
    "print('PLANT: a census is not a lane -- this line is prose and carries no `=`\n")
PLANT_GATE = (
    "# a synthetic CONSUMED lane: prints rows AND is named by a `Gate`, so it is not DEAD here\n"
    "import sys\n"
    "from gatekit import Gate, main\n"
    "GATE = Gate('plant-consumed', bend='unused.bend',\n"
    "            oracle='plant-consumed-oracle.py', rows=1,\n"
    "            pins=[('py', 'plant_row_a')])\n"
    "if __name__ == '__main__':\n"
    "    sys.exit(main(GATE, 'plant'))\n"
)


def plants() -> int:
    """Two plants. PLANT 1 moves the FALSE PASS out of `PASS`; PLANT 2 holds the rule still."""
    gs, gk = gatesweep(), load("gatekit_for_lane_census_plant", HERE / "gatekit.py")
    if gs is None or gk is None:
        print("--plant: REFUSED -- checks/gatesweep.py / gates/gatekit.py absent, and a plant that "
              "cannot run is a plant nobody runs")
        return 3
    PASS, _, REFUSED, _, DEAD = verdicts(gk)
    rc = 0
    checks: list[tuple[str, bool, str]] = []

    # -- PLANT 1: THE FALSE PASS LEAVES `PASS`. The REAL classifier, loaded by path.
    with tempfile.TemporaryDirectory() as td:
        d = Path(td)
        (d / "plant-unconsumed-lane.py").write_text(PLANT_LANE)
        out = subprocess.run([str(PY), str(d / "plant-unconsumed-lane.py")],
                             capture_output=True, text=True, timeout=30).stdout
        printed = len(rows_in(out))
        declared_by = len(declared([(d / "plant-unconsumed-lane.py", "py-main")]))
        want = verdict(printed, declared_by, DEAD, PASS)[0]
        old_word, _old_tok = gs.classify("WITHIN-LIMITS", 0, out)
        new_word = gk.VERDICT[want]
        ok1 = printed == 2 and declared_by == 0 and old_word == "PASS" and new_word == "DEAD"
        print(f"  {'PASS' if ok1 else 'FAIL'}  1: a lane with no declared consumer is PASS under "
              f"`checks/gatesweep.py`\n"
              f"          observed: printed={printed} rows, declared_by={declared_by}, "
              f"sweep says {old_word!r}, lane-census says {new_word!r}")
        checks.append(("1", ok1))
        print(f"          comparisons={0} disagreements={0}  "
              f"-- 0 DISAGREEMENTS OVER 0 COMPARISONS, which is NOT agreement")

    # -- PLANT 2: THE VACUITY GUARD, TWO DIRECTIONS.
    with tempfile.TemporaryDirectory() as td:
        d = Path(td)
        (d / "plant-consumed-oracle.py").write_text(PLANT_LANE)
        (d / "plant-gate.py").write_text(PLANT_GATE)
        # (a) THE CONSUMED LANE. Its consumer is a `Gate(...)` in the walk, so it is named.
        consumed = declared([(d / "plant-gate.py", "py-main")])
        a_named = len(consumed.get("plant-consumed-oracle.py", ()))
        a_code, a_word = verdict(2, a_named, DEAD, PASS)
        ok_a = a_named == 1 and a_word != "DEAD"
        # (b) THE PROSE MEMBER. It prints, it is undeclared, and it emitted no `name=value` row.
        prose = subprocess.run([str(PY), "-c", PLANT_PROSE], capture_output=True, text=True,
                               timeout=30).stdout
        b_rows = len(rows_in(prose))
        b_code, b_word = verdict(b_rows, 0, DEAD, PASS)
        # Its `declared_by` is ASKED, not assumed: the same map that named the consumed lane names
        # nothing that carries this member's name, and 0 there is what makes it a counter-example.
        b_declared_by = len(consumed.get("plant-prose-census.py", ()))
        ok_b = b_rows == 0 and b_declared_by == 0 and b_word == NOT_A_LANE
        # AND THE VACUOUS RULE IS SHOWN TO DISAGREE, so dropping the row-grammar arm turns this
        # RED rather than green. The vacuous rule is the ONE the brief names -- "`no Gate names it`
        # -> DEAD" -- written out here as the counter-example it is, and the assertion is that the
        # two rules PART COMPANY ON A MEMBER THAT REALLY WAS EXECUTED: `prose` is a live run whose
        # stdout held zero `name=value` rows, which is what every unconsumed CENSUS in this tree
        # looks like (`gates/tn_graph_census.py`, `gates/docnum-census.py`, ...). Under the vacuous
        # rule all of those are DEAD, and a census -- which is an instrument, not a comparison --
        # would be indistinguishable from a lane. THIS IS THE "FLATTEN BOTH SIDES TO ONE CONSTANT"
        # TRAP: a rule that fires on every undeclared member is satisfied by PLANT 1 alone.
        vacuous_word = "DEAD" if not b_declared_by else "PASS"
        ok_v = vacuous_word == "DEAD" and b_word == NOT_A_LANE
        ok2 = ok_a and ok_b and ok_v
        print(f"  {'PASS' if ok2 else 'FAIL'}  2: the rule does NOT fire on a CONSUMED lane or on a "
              f"PROSE member, and the\n          VACUOUS rule (`no Gate names it` alone) DISAGREES "
              f"with it on the prose member\n"
              f"          observed: consumed_named={a_named}->{a_word}, prose_rows={b_rows} "
              f"declared_by={b_declared_by}->{b_word}, vacuous_rule_says={vacuous_word}")
        checks.append(("2", ok2))

    rc = 0 if all(ok for _, ok in checks) else 1
    print(f"--plant: {'GREEN' if rc == 0 else 'RED'} ({sum(1 for _, ok in checks if ok)}/"
          f"{len(checks)})")
    return rc


def rss() -> int:
    """PEAK RSS AND WALL CLOCK for the census itself, executing NOTHING."""
    t0 = time.time()
    gs = gatesweep()
    if gs is None:
        return 3
    members = population(gs)
    named = declared(members)
    pins, dynamic = pinned_rows(members)
    here = {p.name for p, _ in members}
    try:
        import resource
        peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / (1024 if sys.platform != "darwin"
                                                                    else 1024 * 1024)
    except ImportError:
        peak = float("nan")
    print(f"--rss: walk={len(members)} declared_lanes={len(named)} "
          f"consumed_in_walk={len(set(named) & here)} pinned_lanes={len(pins)} "
        f"unresolved_pins={dynamic} "
          f"peak_rss={peak:.0f}MB elapsed={time.time() - t0:.2f}s ran_nothing=yes")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="gates/lane-census.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog="DENOMINATOR: the WALK from checks/gatesweep.py, and the "
                                        "`Gate(` call sites inside it. No lane is named here.")
    ap.add_argument("--run", action="store_true",
                    help="EXECUTE every walk member no `Gate` names and parse what it prints; "
                         "REFUSED while a `bend` process is in flight")
    ap.add_argument("--rows", action="store_true",
                    help="print one machine-readable `member=` line per executed member, so "
                         "an interrupted run reports what it DID finish")
    ap.add_argument("--seconds", type=float, default=20.0, help="per-member cap for --run")
    ap.add_argument("--plant", action="store_true", help="two plants; the second is the vacuity guard")
    ap.add_argument("--rss", action="store_true", help="peak RSS + wall clock, execute nothing")
    a = ap.parse_args(argv)
    if a.plant:
        return plants()
    if a.rss:
        return rss()
    return report(a.run, a.seconds, a.rows)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))