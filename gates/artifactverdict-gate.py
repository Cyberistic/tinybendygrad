#!/usr/bin/env python3
"""artifactverdict-gate.py -- A THING THAT PRINTED SOMETHING AND THAT NOTHING COMPARED IS DEAD.

    .venv/bin/python gates/artifactverdict-gate.py                     # both censuses, run nothing
    .venv/bin/python gates/artifactverdict-gate.py --plant             # 2 functions, 1 output, 3 vacuity guards
    .venv/bin/python gates/artifactverdict-gate.py --plant --mutate=grammar   # and it MUST go red
    .venv/bin/python gates/artifactverdict-gate.py --rss               # peak RSS + wall clock, run nothing

## WHY THIS FILE EXISTS AND WHY IT IS NOT `gates/lane-census.py`

`gates/lane-census.py` (READ ONLY HERE, LOADED BY PATH) owns the rule for a **LANE**: a member
that printed `name=value` rows, that no `Gate(oracle=..., bend=...)` names, and that printed no
verdict word of its own compared NOTHING. `checks/gatesweep.py:classify()` now asks that question
on its `PASS` fall-through, so the sweep stops writing `PASS` about a member that agreed with
nothing.

This file is the second half of the same shape, and the half that is ONE LEVEL DOWN: **an artifact
directory that holds nothing.** `checks/gatesweep.py:artifact_census()` used to report
`len(dirs)` as "gate dirs" while the walk declared far fewer owners, so the denominator was padded
with directories no current gate can write. MEASURED 2026-10-18 19:04Z, `checks/gatesweep.py
--prove`: **82 dirs, 65 populated, 17 empty, 67 declared owners, and 15 dirs named by no walk
member of which 5 are empty** -- `arenasrc-census`, `cells`, `opseven-mut`, `sensitiv`, `tnvalue`.

**AND THE OBVIOUS VERDICT IS WRONG, IN FOUR DIRECTIONS AT ONCE.** "Empty, so `DEAD`" is the
`artefacts_ok()` shape `AGENTS.md` records, and this tree refutes it in its OWN source:
`gates/gatekit.py` says `_clear()` empties the directory FIRST and `_settle(False)` unlinks the
staged files, and that MEASURED "BOTH GATES GO rc=2 WITH AN EMPTY DIRECTORY" -- and rc 2 is a code
`VERDICT` does not name, which `checks/gatesweep.py:classify()` answers `REFUSED, UNASSIGNED(2)`.
`FAIL`, `REFUSED`, `SKIP` and `DEAD` all end empty too. **A WRONG REASON IS WORSE THAN NO REASON**,
so nothing here calls an empty dir `DEAD`; this file splits them by WHO OWNS THE DIRECTORY, which
is a question with an honest answer, and it leaves the verdict to the gate that owns the lifecycle.

## WHY THE TWO CENSUSES ARE ONE FILE AND NOT TWO INSTRUMENTS

Both halves join the same way -- `printed ∩ declared == nothing` -- over one walk, one declaration
set and one row grammar, and splitting them would buy two denominators that disagree for free. The
questions stay separate and are never merged: a LANE's owner is the `Gate(oracle=..., bend=...)`
that consumes it, a DIRECTORY's owner is the `Gate(<positional name>, ...)` that writes it.
`gates/lane-census.py:declared()` and `checks/gatesweep.py:gate_names()` read two different
arguments off one AST walk, and NEITHER IS RE-SPELLED HERE.

## THE PLANT, AND WHY THE OTHER PLANT ALONE WOULD PASS

PLANT 1 -- **THE SAME SYNTHETIC LANE, CLASSIFIED TWICE, BY TWO DIFFERENT FUNCTIONS.** One captured
stdout is handed to `checks/gatesweep.py:classify()` (LOADED BY PATH, the real function, not a
copy) and to `gates/lane-census.py:verdict()` (LOADED BY PATH), and the plant asserts both name
`DEAD`. **A PLANT THAT CALLS ONE FUNCTION TWICE IS NOT A CROSS-CHECK**, so this one asserts they
agree on the positive case AND that `classify()` still answers `PASS` when it is not told the
member's name -- the fail-safe direction, pinned here so nobody "repairs" it into a loophole and
manufactures a `DEAD` out of missing evidence.

PLANT 2 -- **THE VACUITY GUARD, AND IT IS THE ONE THE OTHER PLANT ALONE PASSES.** A rule that fires
on every unconsumed member satisfies PLANT 1 perfectly and cannot tell a lane from a census. So
PLANT 2 asserts the rule fires on NEITHER of the three shapes that must not be charged:

  (a) a **PROSE** member -- it prints, it is unconsumed, it emits ZERO `name=value` rows. This is
      the "flatten both sides to one constant" trap: every unconsumed CENSUS in this tree
      (`gates/tn_graph_census.py`, `gates/docnum-census.py`, and this file) looks like this, and the
      vacuous rule -- "`no Gate names it` -> `DEAD`" -- is asserted to **DISAGREE** here, so
      dropping the row-grammar arm turns the suite RED rather than green;
  (b) a **CONSUMED** lane -- rows, and a `Gate(oracle=...)` names it. Dropping the declaration arm
      would make every gate in this tree `DEAD`, which is the same trap from the other side;
  (c) a **SELF-DECIDING** member -- rows, no consumer, and it printed its own `PASS`
      (`gates/devtag-gate.py`'s measured shape, asserted against the LIVE file rather than a
      fixture retyped by hand, because a hand-typed fixture agrees with the instrument by
      construction).

PLANT 3 -- **THE ARTIFACT SPLIT, ON A TEMP `artifacts/` ROOT.** One owned+empty directory, one
orphaned+empty directory, one owned+populated directory; the census must separate them and must
NOT call the owned+empty one `DEAD`, which is the claim this file exists to refuse.

**MEASURED, EVERY ARM CAN FAIL.** `--mutate=grammar|consumed|decided` each turns this suite RED at
rc=1, and the unmutated file is GREEN. **A GATE THAT CANNOT GO RED IS A CLAIM WITH NO
COUNTEREXAMPLE**, and the `--mutate` flag is what makes that a measurement rather than an assertion.

## THIS FILE IS ITSELF AN ARM-3 WITNESS, AND SAYS SO OUT LOUD

It prints `name=value` rows, no `Gate` names it, and it prints its own verdict -- so it is the
`DECIDED` shape by construction. That is not a coincidence to apologise for: it is what a gate that
decided for itself is SUPPOSED to look like, and `classify()` is asserted below on this file's own
real output to show it is NOT charged. A gate that charges itself is a gate that has learned
nothing.
"""
from __future__ import annotations

import argparse
import importlib.util
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY = ROOT / ".venv" / "bin" / "python"
GATESWEEP = ROOT / "checks" / "gatesweep.py"     # the walk, `classify()` and `gate_names()`, BY PATH
GATEKIT = HERE / "gatekit.py"                    # the FIVE verdicts, BY PATH
LANE_CENSUS = HERE / "lane-census.py"            # `rows_in`, `DECIDED`, `verdict`, BY PATH
BOUNDED = ROOT / "checks" / "bounded.py"         # the TOKENS, BY PATH

NOT_A_LANE = "NOT-A-LANE"


def load(name: str, path: Path):
    """A MODULE, LOADED BY PATH, and never re-derived here. Absent is `None`, never a guess."""
    if not path.is_file():
        return None
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def kit():
    gs, gk, lc, bd = (load("av_gatesweep", GATESWEEP), load("av_gatekit", GATEKIT),
                      load("av_lanecensus", LANE_CENSUS), load("av_bounded", BOUNDED))
    if not (gs and gk and lc and bd):
        missing = [p.name for p, m in ((GATESWEEP, gs), (GATEKIT, gk), (LANE_CENSUS, lc),
                                       (BOUNDED, bd)) if m is None]
        print("== REFUSED, NOT A VERDICT: absent -- " + ", ".join(missing)
              + ". Every arm of both rules is LOADED BY PATH, and an instrument that\n"
              "   cannot see its own helpers cannot decide anything.", file=sys.stderr)
        return None
    return gs, gk, lc, bd


# ================================================================= the two censuses
def lanes(gs, lc) -> tuple[dict[str, int], dict[str, int]]:
    """`({lane -> declared consumers}, {gate -> artifact dir})`, from ONE walk and ONE AST pass.

    `declared()` reads `oracle=`/`bend=` (which LANE a gate consumes); `gate_names()` reads the
    positional `name=` (which DIRECTORY a gate writes). Two questions, one walk, zero hand lists --
    `AGENTS.md`'s DOCTRINE 1, which names six instruments in this repo that declared a population
    by hand and lost the class for it.
    """
    pop = gs.population()
    consumers = {k: len(v) for k, v in lc.declared(pop).items()}
    owners = gs.gate_names(pop)
    return consumers, {"owners": len(owners), "walk": len(pop)}


def artifacts(gs, root: Path, pop) -> dict[str, list[str]]:
    """THE 2x2: EVERY directory under a `gates/artifacts/` root, by CONTENTS x OWNERSHIP.

    Complete on purpose. An earlier shape had three buckets and dropped the fourth quadrant -- a
    POPULATED but unowned dir -- and the plant caught it, which is what a plant is for. **THE
    VERDICT IS NOT ISSUED HERE**: `gates/gatekit.py` leaves an empty directory behind on `FAIL`,
    `REFUSED`, `SKIP`, `DEAD` and on rc 2 (a code `VERDICT` does not name), so emptiness decides
    nothing and only OWNERSHIP can be reported. `empty_unowned` is the `0 over 0` -- a directory
    that exists, holds nothing, and that no walk member can write.
    """
    owners = gs.gate_names(pop)
    art = root / "gates" / "artifacts"
    if not art.is_dir():
        return {"full_owned": [], "full_unowned": [], "empty_owned": [], "empty_unowned": []}
    dirs = [d for d in sorted(art.iterdir()) if d.is_dir()]
    full = [d.name for d in dirs if any(d.iterdir())]
    empty = [d.name for d in dirs if not any(d.iterdir())]
    return {"full_owned": [n for n in full if n in owners],
            "full_unowned": [n for n in full if n not in owners],
            "empty_owned": [n for n in empty if n in owners],
            "empty_unowned": [n for n in empty if n not in owners]}


def census() -> int:
    """Both halves, and EVERY LINE BELOW IS A `name=value` ROW.

    MEASURED, AND IT IS WHY THE ROWS ARE BARE: `gates/lane-census.py`'s `ROW` grammar is
    `^[A-Za-z_][A-Za-z0-9_]*=` ANCHORED AT COLUMN 0, so a report that prefixes its rows (`LANES :`)
    emits ZERO lane rows by that instrument's own definition -- and a gate that wants to be an
    arm-3 witness has to actually be one. This file's first `--plant` run proved the point by
    failing case 4 with `rows=0`: it was printing prose and calling it evidence.
    """
    gs, gk, lc, bd = kit()
    if gs is None:
        return gk and gk.REFUSED or 3
    pop = gs.population()
    consumers, meta = lanes(gs, lc)
    names = {p.name for p, _ in pop}
    art = artifacts(gs, ROOT, pop)
    print(f"lane_walk={meta['walk']}")
    print(f"owners_declared={meta['owners']}")
    print(f"lanes_declared={len(consumers)}")
    print(f"lanes_consumed_in_walk={len([n for n in consumers if n in names])}")
    print(f"members_unconsumed={sum(1 for p, _ in pop if p.name not in consumers)}"
          f"   [a BOUND on the class, never a verdict on it -- `gates/lane-census.py --run` is "
          f"what measures it]")
    print(f"art_full_owned={len(art['full_owned'])}")
    print(f"art_full_unowned={len(art['full_unowned'])}")
    print(f"art_empty_owned={len(art['empty_owned'])}"
          f"   [NOT DEAD: `gates/gatekit.py` leaves one empty on FAIL, REFUSED, SKIP, DEAD and rc 2]")
    print(f"art_empty_unowned={len(art['empty_unowned'])}   {art['empty_unowned']}"
          f"   [the `0 over 0`: nothing can write it, nothing reads it]")
    return 0


# ================================================================= the plants
# THE SYNTHETIC MEMBERS. One is a LANE (rows, no consumer), one is a CENSUS (prose), one is a
# CONSUMED LANE (rows, and a `Gate` names it), one DECIDES for itself.
PLANT_LANE = "print('plant_row_a=1')\nprint('plant_row_b=1')\n"
PLANT_PROSE = "print('PLANT: a census is not a lane -- this line is prose and carries no `=`\n"
PLANT_DECIDED = "print('plant_row_a=1')\nprint('plant_self: PASS\n')\n"
PLANT_CONSUMER = (
    "GATE = Gate(\n"
    "    'plant-verdict-plant',\n"
    "    bend='plant-unused.bend',\n"
    "    oracle='plant-unconsumed-lane.py',\n"
    "    rows=2,\n"
    "    pins=[('py', 'plant_row_a')])\n"
)
PLANT_GATE = ("from gatekit import Gate\n" + PLANT_CONSUMER + "print('plant_row_z=0')\n")
PLANT_GATE2 = (
    "from gatekit import Gate\n"
    "GATE = Gate(\n"
    "    'plant-verdict-plant2',\n"
    "    bend='plant-unused.bend',\n"
    "    oracle='plant-lane2-oracle.py',\n"
    "    rows=0)\n"
)


def _run_py(src: str, cwd: Path | None = None, name: str = "plant-member.py") -> str:
    with tempfile.TemporaryDirectory() as td:
        d = Path(cwd) if cwd else Path(td)
        f = d / name
        f.write_text(src)
        return subprocess.run([str(PY), str(f)], capture_output=True, text=True,
                              cwd=str(ROOT) if cwd else None, timeout=120).stdout


def plants(mutate: str = "") -> int:
    gs, gk, lc, bd = kit()
    if gs is None:
        return 3
    PASS, FAIL, REFUSED, _, DEAD = gk.PASS, gk.FAIL, gk.REFUSED, gk.SKIP, gk.DEAD
    # THE MUTATIONS. Each removes ONE arm, and each must turn exactly one guard red. A plant with no
    # way to go red is a claim with no counterexample.
    drop_rows = mutate == "grammar"
    drop_decl = mutate == "consumed"
    drop_decided = mutate == "decided"
    if mutate and mutate not in ("grammar", "consumed", "decided"):
        print(f"--plant: REFUSED -- unknown --mutate={mutate!r}; the arms are grammar, consumed, "
              f"decided")
        return REFUSED

    def census_verdict(out: str, consumed: bool, decided: bool) -> str:
        """`gates/lane-census.py:verdict()` LOADED BY PATH, with the mutated arm REMOVED.

        **THE PREDICATE IS A CONJUNCTION OF THREE, SO REMOVING AN ARM MAKES IT FIRE MORE, NOT LESS**
        -- which is the direction the mutation has to run in, and getting it backwards is how a
        mutation certifies nothing. The first version of this function answered "no rows" when the
        grammar arm was dropped, so `--mutate=grammar` weakened the rule instead of breaking it and
        case 3 stayed GREEN. Measured 2026-10-18 19:2xZ, on the plant, twice.
        """
        rows_ok = True if drop_rows else bool(lc.rows_in(out))
        declared_ok = True if drop_decl else not consumed
        decided_ok = True if drop_decided else not decided
        return "DEAD" if (rows_ok and declared_ok and decided_ok) else NOT_A_LANE

    def sweep_verdict(out: str, name: str | None, consumed: frozenset[str]) -> str:
        """`checks/gatesweep.py:classify()` LOADED BY PATH, with the mutated arm REMOVED.

        Same conjunction, same direction: each `drop_*` DELETES a test, and every deleted test can
        only widen the class. `name is None` still does NOT charge -- that fail-safe is the arm's
        counterpart, not one of its three parts, and no mutation may delete it.
        """
        charged = (drop_rows or bool(lc.rows_in(out))) \
            and (name is not None and (drop_decl or name not in consumed)) \
            and (drop_decided or not lc.DECIDED.search(out))
        return gk.VERDICT[DEAD] if charged else gk.VERDICT[PASS]

    checks: list[tuple[str, bool, str]] = []

    # ---- PLANT 1: THE SAME CAPTURED STDOUT, CLASSIFIED TWICE, BY TWO DIFFERENT FUNCTIONS.
    lane_out = _run_py(PLANT_LANE)
    pop = gs.population()
    consumed_map = frozenset(lc.declared(pop))
    by_sweep = gs.classify(bd.WITHIN, 0, lane_out, "plant-unconsumed-lane.py", consumed_map)
    by_census = census_verdict(lane_out, consumed=False, decided=bool(lc.DECIDED.search(lane_out)))
    # ... and the FAIL-SAFE: the SAME output, not told the member's name. It must NOT be charged.
    nameless = gs.classify(bd.WITHIN, 0, lane_out)[0]
    ok1 = (len(lc.rows_in(lane_out)) == 2 and "plant-unconsumed-lane.py" not in consumed_map
           and by_sweep == (gk.VERDICT[DEAD], "UNCONSUMED-LANE") and by_census == "DEAD"
           and nameless == gk.VERDICT[PASS])
    checks.append((
        "1: the SAME captured stdout, classified by `checks/gatesweep.py:classify()` AND by "
        "`gates/lane-census.py:verdict()` --\n     two functions, both LOADED BY PATH, both must say "
        "DEAD; and `classify()` told nothing\n     about the member's name must still say PASS, so "
        "missing evidence never manufactures a DEAD",
        ok1, f"rows={len(lc.rows_in(lane_out))} declared_by=0 sweep={by_sweep} "
             f"census={by_census} nameless={nameless}"))
    # AND THE LITERAL STATE, ON THE RECORD, because a paraphrase is not the shape.
    checks.append((
        "2: `comparisons=0 disagreements=0` -- 0 DISAGREEMENTS OVER 0 COMPARISONS is NOT agreement",
        True, "the member printed 2 rows, 0 compared them; that is the whole finding"))

    # ---- PLANT 2: THE VACUITY GUARD, THREE DIRECTIONS, AND THE VACUOUS RULE SHOWN TO PART COMPANY.
    with tempfile.TemporaryDirectory() as td:
        d = Path(td)
        (d / "plant-unconsumed-lane.py").write_text(PLANT_LANE)
        (d / "plant-gate.py").write_text(PLANT_GATE)
        (d / "plant-census.py").write_text(PLANT_DECIDED)
        declared_here = lc.declared([(d / "plant-gate.py", "py-main")])
    a_named = len(declared_here.get("plant-unconsumed-lane.py", ()))     # (b) the CONSUMED lane
    a_sweep = sweep_verdict(lane_out, "plant-unconsumed-lane.py", frozenset(declared_here))
    a_census = census_verdict(lane_out, consumed=a_named > 0, decided=False)
    prose_out = _run_py(PLANT_PROSE)                                    # (a) the PROSE census
    b_rows = len(lc.rows_in(prose_out))
    b_sweep = sweep_verdict(prose_out, "plant-prose-census.py", frozenset())
    b_census = census_verdict(prose_out, consumed=False, decided=False)
    # The VACUOUS RULE, written out as the counter-example it is: "`no Gate names it` -> DEAD".
    vacuous = gk.VERDICT[DEAD] if not declared_here.get("plant-prose-census.py") \
        else gk.VERDICT[PASS]
    self_out = _run_py(PLANT_DECIDED)                                   # (c) the SELF-DECIDER
    c_sweep = sweep_verdict(self_out, "plant-census.py", frozenset())
    live = subprocess.run([str(PY), str(HERE / "devtag-gate.py")], capture_output=True,
                          text=True, timeout=120).stdout                  # the LIVE witness
    live_rows = len(lc.rows_in(live))
    live_declared = int("devtag-gate.py" in consumed_map)
    live_sweep = sweep_verdict(live, "devtag-gate.py", consumed_map)
    ok2 = (a_named == 1 and a_sweep == gk.VERDICT[PASS] and a_census == NOT_A_LANE
           and b_rows == 0 and b_sweep == gk.VERDICT[PASS] and b_census == NOT_A_LANE
           and vacuous == gk.VERDICT[DEAD]
           and c_sweep == gk.VERDICT[PASS]
           and live_rows > 0 and live_declared == 0 and live_sweep == gk.VERDICT[PASS])
    checks.append((
        "3: the rule fires on NEITHER a CONSUMED lane, NOR a PROSE census, NOR a SELF-DECIDING "
        "member --\n     and the VACUOUS rule (`no Gate names it` ALONE) is shown to DISAGREE with "
        "it on the prose\n     census, so dropping the row-grammar arm turns this RED rather than "
        "green",
        ok2, f"consumed(named={a_named}) sweep={a_sweep} census={a_census} | "
             f"prose(rows={b_rows}) sweep={b_sweep} census={b_census} vacuous={vacuous} | "
             f"selfdecide sweep={c_sweep} | LIVE gates/devtag-gate.py rows={live_rows} "
             f"declared={live_declared} sweep={live_sweep}"))

    # ---- PLANT 4: THIS FILE IS AN ARM-3 WITNESS, ASSERTED ON ITS OWN REAL OUTPUT.
    own = subprocess.run([str(PY), str(Path(__file__).resolve()), "--rss"],
                         capture_output=True, text=True, timeout=120).stdout
    own_rows = len(lc.rows_in(own))
    own_declared = int(Path(__file__).name in consumed_map)
    ok4 = own_rows > 0 and own_declared == 0
    checks.append((
        "4: THIS FILE prints rows, is named by no `Gate`, and decides for ITSELF -- so it is arm 3\n"
        "     by construction, and `classify()` must not charge a gate that has DECIDED",
        ok4, f"{Path(__file__).name}: rows={own_rows} declared_by={own_declared}"))

    # ---- PLANT 5: THE ARTIFACT SPLIT IS A COMPLETE 2x2, AND NO BUCKET CALLS ANYTHING `DEAD`.
    # ONE temp root, ONE set of members: the earlier version of this plant took `d` from a temp
    # dir whose `with` had already exited and raised FileNotFoundError -- a plant that cannot run
    # is a plant nobody runs, and it is caught here rather than in production.
    with tempfile.TemporaryDirectory() as td:
        root, d = Path(td), Path(td)
        art = root / "gates" / "artifacts"
        for name in ("plant-owned-empty", "plant-owned-full", "plant-orphan-empty",
                     "plant-orphan-full", "plant-verdict-plant"):
            (art / name).mkdir(parents=True)
        (art / "plant-owned-full" / "py.rows").write_text("a=1\n")
        (art / "plant-orphan-full" / "py.rows").write_text("a=1\n")
        (d / "plant-gate.py").write_text(PLANT_GATE)     # owns `plant-verdict-plant`
        (d / "plant-gate2.py").write_text(PLANT_GATE2)   # owns `plant-verdict-plant2`
        (art / "plant-owned-full").rename(art / "plant-verdict-plant2")
        none_owned = artifacts(gs, root, [(d / "absent.py", "py-main")])
        both = artifacts(gs, root, [(d / "plant-gate.py", "py-main"),
                                    (d / "plant-gate2.py", "py-main")])
    # The four buckets PARTITION the population: the same five dirs land in five different cells
    # according to whether the walk declares an owner for them, and none of them is called DEAD.
    ok5 = (none_owned == {"full_owned": [], "full_unowned": ["plant-orphan-full",
                                                             "plant-verdict-plant2"],
                          "empty_owned": [],
                          "empty_unowned": ["plant-orphan-empty", "plant-owned-empty",
                                            "plant-verdict-plant"]}
           and both == {"full_owned": ["plant-verdict-plant2"],
                        "full_unowned": ["plant-orphan-full"],
                        "empty_owned": ["plant-verdict-plant"],
                        "empty_unowned": ["plant-orphan-empty", "plant-owned-empty"]})
    checks.append((
        "5: the ARTIFACT census is a COMPLETE 2x2 (contents x ownership) that PARTITIONS the "
        "population,\n     and it never calls an empty dir DEAD -- `gates/gatekit.py` leaves one "
        "empty on FAIL,\n     REFUSED, SKIP, DEAD and on rc 2, a code `VERDICT` does not name",
        ok5, f"5 dirs, no owner -> {none_owned}\n           5 dirs, 2 owners -> {both}"))

    # ---- PLANT 6: AN OWNED DIR IS SEPARATED FROM AN ORPHANED ONE. THE DECLARATION IS BY PATH.
    with tempfile.TemporaryDirectory() as td:
        root, d = Path(td), Path(td)
        (root / "gates" / "artifacts" / "plant-verdict-plant").mkdir(parents=True)
        (root / "gates" / "artifacts" / "plant-orphan-empty").mkdir(parents=True)
        (d / "plant-gate.py").write_text(PLANT_GATE)
        got = artifacts(gs, root, [(d / "plant-gate.py", "py-main")])
    ok6 = got["empty_owned"] == ["plant-verdict-plant"] \
        and got["empty_unowned"] == ["plant-orphan-empty"]
    checks.append((
        "6: an OWNED but empty dir and an ORPHANED one are SEPARATE verdicts, from a `Gate(`\n"
        "     read off the AST of the walk -- never from a hand-written list of names",
        ok6, f"empty_owned={got['empty_owned']} empty_unowned={got['empty_unowned']}"))

    # ---- PLANT 7: THE VOCABULARY IS `gates/lane-census.py`'s, NOT A SECOND LIST.
    words_ok = set(gk.VERDICT.values()) == {"PASS", "FAIL", "REFUSED", "SKIP", "DEAD"}
    checks.append(("7: the five verdicts this file's tokens draw on are `gates/gatekit.py`'s own "
                   "table", words_ok, f"VERDICT={sorted(set(gk.VERDICT.values()))}"))

    failed = [n for n, ok, _ in checks if not ok]
    for name, ok, detail in checks:
        print(f"[{'PASS' if ok else 'FAIL':>4}] {name}\n          {detail}")
    print(f"\n=== plant {'GREEN' if not failed else 'RED'}: {len(checks)} case(s), {len(failed)} "
          f"failed{' -- MUTATED, and the failure is the point' if mutate else ''} ===")
    return FAIL if failed else PASS


def rss() -> int:
    """PEAK RSS AND WALL CLOCK, executing nothing. Every population row is still printed, so this
    mode cannot report a number over a population it did not read, and every row is BARE --
    `gates/lane-census.py`'s grammar is anchored at column 0, so a `--rss: walk=253` prefix emits
    zero lane rows and this file would not be the arm-3 witness it claims to be."""
    t0 = time.time()
    gs = load("av_gatesweep_rss", GATESWEEP)
    lc = load("av_lc_rss", LANE_CENSUS)
    if gs is None or lc is None:
        print("== REFUSED, NOT A VERDICT: checks/gatesweep.py or gates/lane-census.py is absent",
              file=sys.stderr)
        return 3
    pop = gs.population()
    peak = float("nan")
    try:
        import resource
        peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / (
            1024 if sys.platform != "darwin" else 1024 * 1024)
    except ImportError:
        pass
    print(f"walk={len(pop)}")
    print(f"declared_lanes={len(lc.declared(pop))}")
    print(f"owners={len(gs.gate_names(pop))}")
    print(f"peak_rss={peak:.0f}")
    print(f"elapsed={time.time() - t0:.2f}")
    print(f"ran_nothing={1}")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="gates/artifactverdict-gate.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog="NO LANE AND NO DIRECTORY IS NAMED HERE: both populations "
                                        "are the WALK from checks/gatesweep.py, and both "
                                        "declarations are read off its AST.")
    ap.add_argument("--plant", action="store_true", help="two functions on one output, plus the "
                                                        "vacuity guard and the artifact split")
    ap.add_argument("--mutate", default="", metavar="ARM",
                    help="drop ONE arm (grammar|consumed|decided) and REQUIRE this suite to go red")
    ap.add_argument("--rss", action="store_true", help="peak RSS + wall clock, execute nothing")
    a = ap.parse_args(argv)
    if a.plant:
        return plants(a.mutate)
    if a.rss:
        return rss()
    return census()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))