#!/usr/bin/env python3
"""runner.py -- the PRECONDITIONS a gate sweep must satisfy before it spends an hour, and the
verdict table it writes when they are satisfied.

    .venv/bin/python gates/runner.py --plan      # population, derivations, projection. Runs NOTHING.
    .venv/bin/python gates/runner.py --plant     # the five refusals, on synthetic state. No bend.
    .venv/bin/python gates/runner.py             # the DEFAULT: a BUDGETED prefix of the sweep
    .venv/bin/python gates/runner.py --all       # every discovered gate. See "WHAT A FULL SWEEP COSTS".
    .venv/bin/python gates/runner.py --only gates/rand_census-gate.py --only gates/wk-f32-gate.py

Exit: 0 every gate in the SET ran · 1 something failed · 3 a precondition was absent · 4 the budget
stopped the sweep, or `--measure-only` ran under unsatisfied preconditions · 5 the set was empty.

MEASURED 2026-10-16, three serial runs of the same 10 gates: **`PASS=8 FAIL=2` every time**
(`indexread-gate` + `pins-shape-gate`, ONE defect — `pins-shape-gate.py: ls-files` is
`indexread-gate`'s new offender, recorded already in `.agents/TOOLS.md`), wall **113.1 / 113.0 /
110.5 s**. Projected over the 77-gate set: **788–913 s**. Every number, and the run-to-run spread
that makes each of them soft, is in `gates/runner-cost.rows` and in the table in `gates/README.md`.

WHY THIS FILE EXISTS WHEN `checks/gatesweep.py` ALREADY SWEEPS. `gatesweep.py` is the LOOP and it is
not to be rewritten: it walks the population, runs each gate through `checks/bounded.py`, reads the
watchdog's TOKEN rather than its status, classifies into the five, and flushes a row per gate.
MEASURED 2026-10-15 over 70 gates: `PASS=66 FAIL=2 SKIP=2 DEAD=0` in 616.0 s. It is missing the one
thing that makes a sweep DANGEROUS rather than slow: **it starts.** No precondition stands between
the operator and an hour of `bend` at 1-2 GiB a piece, and every way this tree has been hurt by that
is a missing precondition:

  INDEX ARMED    `checks/index-arm-gate.py` answers `REFUSED` on **47 paths RIGHT NOW**. A sweep that
                 runs anyway and reports "the tree is fine" has attributed a git-index condition to
                 the gates -- and `gates/indexread-gate.py` MEASURED a gate's own verdict moving
                 because a DIFFERENT file's commit read the index.
  POPULATION     An empty or half-discovered population is the one answer a sweep cannot report as a
                 number, because a tally with denominator 0 is indistinguishable from a tally of 0
                 disagreements. `--plant` drives it to zero and the runner refuses.
  DRIFT          This file DELEGATES its loop and its watchdog BY PATH. A delegation with no pin is a
                 delegation whose meaning can change underneath rows already written.
  CONCURRENCY    MEASURED, hit today: two gates shared `gates/artifacts/realize_graph_census-gate/`
                 and one died on `FileNotFoundError: .tmp.gate.bin`, and a `nohup` census recorded as
                 DEAD was still running. `gates/artifacts/` is `.gitignore`d, so nothing recorded
                 either. SERIAL IS NOT ENOUGH; the exclusion has to be CROSS-PROCESS.

A REFUSAL IS NOT A VERDICT. All five refusals exit `gatekit.REFUSED` (3) and print
`REFUSED, NOT A VERDICT`, because the tree is fine in every one of them -- the RUN is not permitted.
That is `checks/index-arm-gate.py`'s own shape, copied rather than invented.

THE POPULATION IS DERIVED, AND THE DERIVATION'S BLIND SPOT IS A NUMBER, NOT A HOPE.

  A       `checks/gatesweep.py:population()` -- a directory walk for `*-gate.py`.
          The figure is `gatesweep.py --plan`'s POPULATION line; it is NOT transcribed here
          because the population moves as other units land gates -- it read 76, 77, 78, 79 and
          80 within one session, and `gates/docnum-claim-gate.py` is what holds the comparison.
  B       `gates/gates-pop.py:discover()`, filtered to the `gates/` home: entry points by AST
          `__main__`, in HOMES derived by `gate_homes()`. MEASURED 114.
  LANES   the entry points some gate NAMES AS ITS OWN INPUT, read from the kernel's own
          declaration -- `gatekit.Gate(bend=..., oracle=...)` string LITERALS. MEASURED 12.
  RUN SET `A \\ LANES`. MEASURED 76, because no `*-gate.py` is anybody's lane.

**THE FIRST DERIVATION I WROTE WAS WRONG AND THE TREE CAUGHT IT, SO THE NUMBER IS HERE.** It was
`A \\ B` -- "nothing else claims this file as its input" -- over every AST string constant, which
made `X-mutate.py` claim `X-gate.py`, because a mutation harness RUNS its gate. MEASURED: **9 of 76
real gates dropped**, one of them by a gate rather than by its own mutator (`decomp_value-gate.py`
claims `decomp_graph_census-gate.py`). Being named is not the same relation as being an INPUT, and
the run set is 9 gates larger than the shape that got it wrong. **THE BLIND SPOT IS REPORTED, NOT
ASSUMED:** `GATES OUTSIDE THE WALK` is the set of entry points that construct a `gatekit.Gate` and
are not in the run set, and it is **0** -- so the name shape misses no gatekit gate, which is the
one thing a name shape cannot say about itself. The 13 gates in the run set that construct no `Gate`
at all (`msgdiff-gate`, `indexread-gate`, `devtag-gate`, ...) are hand-rolled and are counted, not
inferred.

WHAT SHOULD RUN BY DEFAULT, MEASURED, AND THE ANSWER IS NOT A LIST AND NOT "ALL OF THEM".
MEASURED here, 8 gates spanning the distribution: **the four cheapest cost 5 s and 213 MB between
them; the dearest cost 32 s and 1,041 MB** (row file `gates/runner-cost.rows`, the read side below).
`.agents/TOOLS.md` records a prior full sweep of 70 gates at 616.0 s with per-gate peaks to
2,168 MB; `AGENTS.md` records `bend` peaks of 1,152 MB against 16 GiB of `hw.memsize`. The spread
between the gate you want on every commit and the gate that costs 32 s and a gigabyte is two orders
of magnitude, so a default that runs both spends its usefulness on the cheap one and its memory on
the dear one.
**THE DEFAULT IS THEREFORE A BUDGET, NOT A SUBSET: gates start in the discovered order and the
sweep STOPS when `--budget-seconds` is spent.** Nothing here names a gate. A subset named in this
file would be the eighth instrument in this tree to hold a population it wrote down, and it would be
wrong the day a gate is renamed.
**AND THE STOP IS NOT A PASS.** A budgeted prefix exits 4 (`SKIP`) and prints how many did not run,
because the remainder measured nothing and a table that cannot say so is a bill. `--all` is the
sweep; the default is a slice of it; the difference is one flag and one number.
"""
import argparse
import ast
import contextlib
import io
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
LOCK = HERE / "artifacts" / ".runner.lock"
COSTS = HERE / "runner-cost.rows"
HEADER = "gate\tverdict\ttoken\rc\tseconds\tpeakMB\tloadavg"
LANE_KWARGS = ("bend", "oracle")          # the kernel's own declaration of a gate's INPUTS
PEAK = re.compile(r"peak-RSS=(\d+)")

# WHAT THIS FILE DELEGATES, PINNED. `checks/gatesweep.py` owns the loop, the walk and the
# classifier; `checks/bounded.py` owns the tokens; `gates/gatekit.py` owns the five verdicts. All
# three are LOADED BY PATH and none is re-spelled here. A pin on a delegation is not a lock on a
# file: it is the statement that the rows already on disk were written by THAT loop -- the same
# reason `checks/differ.py`'s `ORACLE_PIN` and `gates/gates-pop.py`'s `FIXTURES` exist.
# MEASURED 2026-10-16 with `shasum -a 256`; `gatekit.oracle_drift` reports the delta.
DELEGATED = {
    "checks/gatesweep.py": "7ed8f18430cbc8382c95f97b02184bd1562882f2631719697279e75ba6ab159b",
    "checks/bounded.py": "e90b068d974107b6ebfab01f1541c6433c43fe10af61350831f0c5cbfc482c37",
    "checks/index-arm-gate.py": "59cd651638096ed32f319ded3318e791d5a181c5e0f80bf1a6087f6a06645480",
}
INSTRUMENTS = {"gatekit": "gatekit.py", "sweep": "../checks/gatesweep.py",
               "gpop": "gates-pop.py", "idxarm": "../checks/index-arm-gate.py",
               "surface": "gate-surface.py"}


def _load(name, path):
    """One sibling instrument BY PATH. Every one of the five is guarded by `if __name__ ==
    "__main__"`, which was CHECKED and not assumed: importing a gate RUNS it, and
    `gates/mixin-op-gate.py` and `gates/beautiful-mnist-gate.py` exit 2 at module scope."""
    if not path.is_file():
        return None, f"{path} is absent -- it owns a measurement this file does not re-spell"
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod, ""


def instruments():
    """`(mods, "")` or `(None, why)`. One load per process: `_load` executes the module, and a
    second `exec_module` of `gates-pop.py` re-derives the root set for nothing."""
    mods = {}
    for tag, rel in INSTRUMENTS.items():
        mod, err = _load(f"runner_{tag}", (HERE / rel).resolve())
        if mod is None:
            return None, err
        mods[tag] = mod
    return mods, ""


# ------------------------------------------------------------------ the population, derived
def _tree(p):
    try:
        return ast.parse(p.read_text())
    except (OSError, SyntaxError, ValueError):
        return None


def _calls(tree, name):
    for n in ast.walk(tree):
        if isinstance(n, ast.Call):
            fn = n.func
            if (getattr(fn, "id", None) or getattr(fn, "attr", None)) == name:
                yield n


def derive(mods, root):
    """`(sets, "")` -- the run set and four more, every one DERIVED and none written down.

    `outside` is THE NUMBER THIS FILE EXISTS TO MAKE: an entry point that constructs a
    `gatekit.Gate` and is not in the run set. It is the population's edge, and a non-empty one means
    the derivation cannot see a gate -- so `decide_population()` REFUSES rather than running 76
    of 77. MEASURED 0 on this tree, which is the only reason the name shape is tolerable HERE and
    not in general."""
    walk = mods["sweep"].population(root)
    entries = [p for p in mods["gpop"].discover(root)[0] if p.parent.name == "gates"]
    names = {p.name for p in entries}
    lanes, ctors = {}, set()
    for p in entries:
        tree = _tree(p)
        for call in (() if tree is None else _calls(tree, "Gate")):
            ctors.add(p.name)
            for kw in call.keywords:
                if kw.arg in LANE_KWARGS and isinstance(kw.value, ast.Constant) \
                        and isinstance(kw.value.value, str):
                    lane = Path(kw.value.value).name
                    if lane in names and lane != p.name:
                        lanes.setdefault(lane, set()).add(p.name)
    run = [p for p in walk if p.name not in lanes]
    got = {p.name for p in run}
    return {"walk": walk, "entries": entries, "lanes": lanes, "run": run,
            "outside": sorted((ctors & names) - got), "hand_rolled": sorted(got - ctors),
            "residual": sorted(names - got - set(lanes))}


def lock_state(path=LOCK):
    """`("FREE", None) | ("HELD-LIVE", pid) | ("HELD-STALE", pid)`.

    A STALE LOCK IS STILL A REFUSAL. It is tempting to clear a lock whose pid is gone, because
    otherwise a crashed runner bricks the tree -- but a lock is a claim about INTENT, and a pid that
    no longer exists cannot be asked whether the sweep it described is still wanted. The refusal
    prints the `rm` and stops. That is the difference between a lock and a heuristic, and it is why
    `checks/index-arm-gate.py` refuses an armed index instead of disarming it."""
    if not path.exists():
        return "FREE", None
    try:
        pid = int(path.read_text().split()[0])
    except (ValueError, IndexError, OSError):
        return "HELD-STALE", "unreadable"
    try:
        os.kill(pid, 0)                      # signal 0 tests EXISTENCE and delivers nothing
    except ProcessLookupError:
        return "HELD-STALE", pid             # nobody owns that pid: still a refusal, see above
    return "HELD-LIVE", pid                  # and PermissionError means alive, just not ours


# ------------------------------------------------------------------ the five refusals
# FOUR DECISION FUNCTIONS, EACH RETURNING `None` OR THE REASON, each used by BOTH `preconditions`
# and `plant()`. The first version of this file had `plant()` reach past them into `oracle_drift`,
# `lock_state` and `report` and assert that THOSE fired -- and MEASURED, breaking the branch
# `if state != "FREE":` in `preconditions` left the plant green. **A PLANT THAT DRIVES A HELPER IS
# NOT A PLANT OF THE DECISION.** The split is one function per precondition precisely so that the
# plant and the sweep cannot disagree about what the precondition IS.


def decide_pins(mods, pins=None):
    drift = mods["gatekit"].oracle_drift(DELEGATED if pins is None else pins)
    return "PIN-DRIFT: " + "; ".join(drift) if drift else None


def decide_population(pop):
    if not pop["run"] or not pop["entries"]:
        return (f"NO-POPULATION: walk={len(pop['walk'])} entries={len(pop['entries'])}; a tally "
                f"with a denominator of 0 reports 0 disagreements")
    if pop["outside"]:
        return (f"NO-POPULATION: {len(pop['outside'])} gate(s) construct a gatekit.Gate and are "
                f"outside the run set, so the derivation cannot see them: {pop['outside']}")
    return None


def decide_index(mods, root):
    """The census is CALLED, not re-implemented: deletion / stale / foreign-add / intent-to-add are
    `checks/index-arm-gate.py`'s own shapes, and a second copy of that census is the fault
    `AGENTS.md` names seven times. It PRINTS, so its stdout is captured and its own refusal line is
    reported back -- a refusal the operator cannot read is a refusal they cannot test."""
    said = io.StringIO()
    try:
        with contextlib.redirect_stdout(said):
            rc, _census = mods["idxarm"].report(root, None)
    except Exception as exc:                       # a census that RAISED has not found an index
        return f"INDEX-ARM: the census raised {type(exc).__name__}: {exc}"
    if rc == mods["gatekit"].PASS:
        return None
    head = next((l for l in said.getvalue().splitlines() if "REFUSED" in l), f"rc={rc}")
    return f"INDEX-ARM: {head}"


def decide_lock(path=LOCK):
    state, pid = lock_state(path)
    if state == "FREE":
        return None
    return (f"LOCK-HELD ({state}, pid {pid}): another sweep holds {path.name}; `rm {path}` once "
            f"you are sure it is dead")


def preconditions(mods, pop, root=ROOT, lock=True):
    """Every precondition as `(code, why)`, evaluated cheapest-first. None of them runs a `bend`.

    The order is the order of cost: a missing instrument and a moved pin are answered before the
    two that read the tree's git state, because a refusal that spent a `git ls-files` to discover a
    missing file wasted the operator's patience before it told them anything."""
    decided = [decide_pins(mods), decide_population(pop), decide_index(mods, root)]
    if lock:
        decided.append(decide_lock())
    return [(mods["gatekit"].REFUSED, why) for why in decided if why]


# ------------------------------------------------------------------ one gate, and its MACHINE
def run_one(gate, mods, seconds, mb):
    """`(verdict, token, rc, seconds, peakMB, loadavg)` for ONE gate, through `bounded.py`.

    `sweep.classify` does the classifying and is CALLED, not re-spelled: the watchdog token beats
    the exit status, a traceback is DEAD and not FAIL, an unassigned code REFUSES. What is added is
    the one rule `gatesweep.py` does not have, and it is MEASURED:
    `gates/ops_python_exec-gate.py:113,115,204` call `sys.exit(<string>)`, which PRINTS the string
    and exits **1**, so its refusal line beginning `REFUSED:` was tallied a FAILURE by a sweep.
    **A GATE THAT SAYS ONE VERDICT AND EXITS ANOTHER IS NOT A VERDICT, IT IS A REFUSAL** -- the exit
    code is the transport, and a string handed to `sys.exit` is a message, not a code."""
    sweep = mods["sweep"]
    cmd = [str(sweep.PY), str(sweep.HERE / "bounded.py"), "--seconds", str(seconds), "--mb", str(mb),
           "--", str(sweep.PY), str(gate)]
    t0 = time.monotonic()
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(ROOT))
    took = time.monotonic() - t0
    m = sweep.REC.search(r.stderr or "")
    btoken, rc = (m.group(1), int(m.group(2))) if m else ("NO-RECORD", r.returncode)
    said = "\n".join(l for l in (r.stderr or "").splitlines()
                     if not l.startswith(("[bounded]", "  ")))
    text = (r.stdout or "") + "\n" + said
    verdict, token = sweep.classify(btoken, rc, text)
    mismatch = spoken_disagrees(text, verdict, mods, token)
    if mismatch:
        verdict, token = mods["gatekit"].VERDICT[mods["gatekit"].REFUSED], mismatch
    peak = PEAK.search(r.stderr or "")
    return verdict, token, rc, took, int(peak.group(1)) if peak else -1, os.getloadavg()[0]


SPOKEN = re.compile(r"\b(GREEN|RED|PASS|FAIL|REFUSED|DEAD|SKIP)\b")


def spoken_disagrees(text, verdict, mods, token=None):
    """`None`, or `TOKEN-MISMATCH(says W, exit says V)` when the gate's OWN output names a verdict
    and the exit code names a different one.

    ONLY `gatekit`'s five NAMES COUNT. MEASURED, and the first version of this rule was WRONG IN THE
    SAFE DIRECTION: `gates/gate-surface.py` declares its own surface as `{0: "GREEN", 1: "RED",
    3: "REFUSED"}`, `gates/pins-shape-gate.py` prints `RED` and exits 1, and a rule that read `RED`
    as a claim about `FAIL` called a gate that AGREED a mismatch -- so a green gate was refused. A
    word this tree has not bound to a code is not a claim about a code; it is prose. The five names
    are read from `gates/gatekit.py`'s module-level unpack through `gate_surface.vocabulary()`, which
    exists precisely so that nobody transcribes the mapping a second time.
    """
    if token != verdict or verdict not in ("PASS", "FAIL"):
        return None
    names = {n for n in SPOKEN.findall(text) if n in mods["surface"].vocabulary().values()}
    if names and names != {verdict}:
        return f"TOKEN-MISMATCH(says {'/'.join(sorted(names))}, exit says {verdict})"
    return None


# ------------------------------------------------------------------ the table, and the budget
def costs():
    """`{gate: (seconds, peakMB)}` from `gates/runner-cost.rows`, which a real run writes. A cost
    table with no coverage is UNPRICED and says so: `1 of 76 gates measured` does not price 76."""
    out = {}
    if COSTS.is_file():
        for line in COSTS.read_text().splitlines():
            f = line.split("\t")
            if len(f) >= 6 and f[4].replace(".", "").isdigit() and f[5].lstrip("-").isdigit():
                out[f[0]] = (float(f[4]), int(f[5]))
    return out


def project(n_gates, table):
    """A full sweep's cost from measured rows, WITH ITS COVERAGE. Never a number without one."""
    if not table:
        return "UNPRICED -- no measured rows in gates/runner-cost.rows"
    secs = sum(v[0] for v in table.values())
    return (f"{len(table)} of {n_gates} gates measured: {secs:.0f}s for the measured "
            f"{len(table)}, mean {secs / len(table):.1f}s, max peak {max(v[1] for v in table.values())} MB"
            f" -> {'at least ' if len(table) < n_gates else ''}{secs / len(table) * n_gates:.0f}s "
            f"for {n_gates} if the mean holds")


def sweep_run(gates, mods, out, seconds, mb, budget, stamp="SWEEP"):
    """SERIAL BY CONSTRUCTION: one `subprocess.run`, one `bend`, one artifact directory, one loop
    iteration. There is no pool and no thread here to remove, because the loop is a `for`
    statement and the only concurrency in the process is the reader's terminal.

    The ROW FILE is flushed per gate, so a sweep that dies at gate 69 keeps its 68 -- and the cost
    table is APPENDED to per gate, which is what makes `--plan`'s projection a measurement rather
    than a memory."""
    tally, spent, ran, peak_max = {}, 0.0, 0, 0
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w") as sink, COSTS.open("a") as costs_sink:
        sink.write(f"# {stamp}\n{HEADER}\n")
        for g in gates:
            if budget is not None and spent >= budget:
                break
            verdict, token, rc, took, peak, load = run_one(g, mods, seconds, mb)
            spent, ran = spent + took, ran + 1
            peak_max = max(peak_max, peak)
            tally[verdict] = tally.get(verdict, 0) + 1
            row = f"{g.relative_to(ROOT)}\t{verdict}\t{token}\t{rc}\t{took:.1f}\t{peak}\t{load:.1f}\n"
            sink.write(row)
            sink.flush()
            costs_sink.write(row)
            costs_sink.flush()
            print(f"  {verdict:<8} {took:6.1f}s  peak={peak:>5}MB  loadavg={load:5.1f}  "
                  f"{g.relative_to(ROOT)}  {token}")
    return tally, spent, ran, peak_max


def take_lock():
    """`O_CREAT|O_EXCL`, so two runners cannot both believe they hold it. Released in `finally`."""
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(str(LOCK), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        state, pid = lock_state()
        return state, pid
    os.write(fd, f"{os.getpid()} {time.time():.0f} gates/runner.py\n".encode())
    os.close(fd)
    return None


# ------------------------------------------------------------------ the plant
def plant():
    """The FIVE refusals, each driven into its state on SYNTHETIC input. No `bend`, no live gate, no
    live git index. A precondition never observed to fire is a comment, and every branch asserts the
    REFUSAL rather than the absence of one."""
    mods, err = instruments()
    if mods is None:
        print(f"REFUSED, NOT A VERDICT: {err}", file=sys.stderr)
        return 3
    gatekit = mods["gatekit"]
    cases = []
    with tempfile.TemporaryDirectory(prefix="runner.plant.", dir=str(HERE / "artifacts")) as td:
        td = Path(td)
        # PIN-DRIFT: a file that is present and is NOT the pinned bytes. `decide_pins` is the SHIPPED
        # decision, not the helper: breaking `preconditions`'s use of it is what must turn this red.
        victim = td / "delegated.py"
        victim.write_text("not the pinned bytes\n")
        fired = decide_pins(mods, {str(victim): "0" * 64})
        cases.append(("PIN-DRIFT", bool(fired), fired or "no drift reported"))
        cases.append(("PIN clean", decide_pins(mods) is None, "the live DELEGATED pins hold"))

        # NO-POPULATION, two shapes: nothing discovered at all, and a derivation whose entry points
        # all exist while a gatekit gate sits outside the run set. The second is the one the real
        # tree has never hit, and it is the reason `EDGE` is printed on every run.
        empty = {"walk": [], "entries": [], "lanes": {}, "run": [], "outside": [],
                 "hand_rolled": [], "residual": []}
        cases.append(("NO-POPULATION empty", bool(decide_population(empty)),
                      decide_population(empty) or "no refusal"))
        blind = dict(empty, entries=[td / "g.bend"], walk=[td / "g.bend"], run=[td / "g.bend"],
                     outside=["lost-gate.py"])
        cases.append(("NO-POPULATION blind", bool(decide_population(blind)),
                      decide_population(blind) or "no refusal"))
        cases.append(("POPULATION ok", decide_population(
            {"walk": [1], "entries": [1], "run": [1], "outside": [], "lanes": {},
             "hand_rolled": [], "residual": []}) is None, "a populated derivation does not refuse"))

        # LOCK-HELD, all three states. A LIVE pid is this process; a STALE one is a pid nothing owns.
        # Both refuse, and so does FREE -- by NOT refusing, which is the other half of the plant.
        lock = td / "lock"
        cases.append(("LOCK free", decide_lock(lock) is None, "no file -> no refusal"))
        lock.write_text(f"{os.getpid()} 0 gates/runner.py\n")
        cases.append(("LOCK live", bool(decide_lock(lock)), decide_lock(lock) or "no refusal"))
        lock.write_text("999999 0 gates/runner.py\n")
        cases.append(("LOCK stale", bool(decide_lock(lock)), decide_lock(lock) or "no refusal"))

        # INDEX-ARM: a synthetic repo whose index holds a deletion the HEAD tree does not. MEASURED:
        # the same census that answers REFUSED on 47 paths of this tree answers it on a tree with
        # ONE deletion, so the plant is about the DECISION, not about this tree being broken.
        _plant_repo(td / "repo")
        cases.append(("INDEX-ARM armed", bool(decide_index(mods, td / "repo")),
                      (decide_index(mods, td / "repo") or "no refusal")[:110]))

        # TOKEN-MISMATCH, both directions, plus the fact that `gatesweep.classify` alone gets it
        # wrong: `gates/ops_python_exec-gate.py:113,115,204` print a refusal and exit 1.
        names = set(mods["surface"].vocabulary().values())
        cases.append(("spoken RED is prose", spoken_disagrees("RED", "FAIL", mods, "FAIL") is None,
                      "RED is not one of gatekit's five, so it claims nothing"))
        cases.append(("spoken REFUSED is a claim",
                      bool(spoken_disagrees("REFUSED", "FAIL", mods, "FAIL")),
                      f"vocabulary {sorted(names)}"))
        cases.append(("spoken PASS agrees",
                      spoken_disagrees("PASS", "PASS", mods, "PASS") is None, "PASS + exit 0"))
    bad = [n for n, ok, _d in cases if not ok]
    for n, ok, d in cases:
        print(f"  {'OK  ' if ok else 'BAD '} {n:<20} {d}")
    print(f"--plant: {'all five fire' if not bad else 'DID NOT FIRE: ' + ', '.join(bad)}")
    return gatekit.FAIL if bad else gatekit.PASS


def _plant_repo(repo):
    """Two committed files, then one deleted and staged: the smallest tree that arms an index. The
    index file is `agent-index` so the plant cannot leave the tree's own index staged."""
    repo.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, GIT_INDEX_FILE=str(repo / ".git" / "agent-index"))
    for cmd in (["init", "-q"], ["config", "user.email", "r@x"], ["config", "user.name", "r"]):
        subprocess.run(["git", "-C", str(repo), *cmd], capture_output=True, env=env)
    (repo / "a.py").write_text("a\n")
    (repo / "b.py").write_text("b\n")
    subprocess.run(["git", "-C", str(repo), "add", "-A"], capture_output=True, env=env)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "two"], capture_output=True, env=env)
    (repo / "b.py").unlink()
    subprocess.run(["git", "-C", str(repo), "add", "-A"], capture_output=True, env=env)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true", help="every gate in the set, not a budgeted prefix")
    ap.add_argument("--plan", action="store_true", help="print the set and the projection. Runs NOTHING.")
    ap.add_argument("--plant", action="store_true", help="the five refusals, on synthetic state")
    ap.add_argument("--only", action="append", default=[], metavar="PATH",
                    help="run exactly this gate. A SELECTION, never the population.")
    ap.add_argument("--budget-seconds", type=float, default=300.0,
                    help="stop the sweep after this much wall time (default 300)")
    ap.add_argument("--seconds", type=int, default=900, help="per-gate wall bound")
    ap.add_argument("--mb", type=int, default=2048, help="per-gate peak-RSS ceiling")
    ap.add_argument("--measure-only", action="store_true",
                    help="run the set FOR COST under refused preconditions, and exit SKIP(4). "
                         "NEVER a verdict: the rows are stamped MEASUREMENT and the exit is 4.")
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args(argv)

    mods, err = instruments()
    if mods is None:
        print(f"REFUSED, NOT A VERDICT: {err}", file=sys.stderr)
        return 3
    gatekit = mods["gatekit"]
    if args.plant:
        return plant()

    pop = derive(mods, ROOT)
    print(f"SET        A  walk gates/*-gate.py           {len(pop['walk']):>4}")
    print(f"           B  gates-pop.discover() in gates/ {len(pop['entries']):>4}  (a DIFFERENT "
          f"question: entry points)")
    print(f"           LANES  Gate(bend=,oracle=) literals {len(pop['lanes']):>4}")
    print(f"           RUN SET = A \\ LANES              {len(pop['run']):>4}")
    print(f"EDGE       gates OUTSIDE the run set        {len(pop['outside']):>4}  "
          f"{pop['outside'] or '(the name shape misses no gatekit gate)'}")
    print(f"           hand-rolled gates in the set     {len(pop['hand_rolled']):>4}  "
          f"{pop['hand_rolled'] or ''}")
    print(f"           entry points neither (residual)  {len(pop['residual']):>4}  "
          f"(mutators, generators, meta-instruments)")
    print(f"PROJECTION {project(len(pop['run']), costs())}")
    print(f"MACHINE    ceiling {args.mb} MB per gate against "
          f"{os.sysconf('SC_PAGE_SIZE') * os.sysconf('SC_PHYS_PAGES') >> 30} GB hw.memsize, "
          f"loadavg {os.getloadavg()[0]:.1f} on {os.cpu_count()} cores")

    # The preconditions are asked BEFORE `--plan` answers, because a plan that cannot be executed
    # is the most expensive kind of plan: a reader who is told what would run, and not told that it
    # would refuse, learns that the sweep is ready when it is not.
    refused = preconditions(mods, pop)
    for _code, why in refused:
        print(f"  REFUSED, NOT A VERDICT: {why}", file=sys.stderr)
    if args.plan:
        for g in pop["run"]:
            print(f"  would run  {g.relative_to(ROOT)}")
        print(f"PLAN: {len(refused)} precondition(s) would REFUSE this run: "
              f"{[w.split(':')[0] for _c, w in refused] or 'none'}")
        return gatekit.REFUSED if refused else gatekit.PASS
    if refused and not args.measure_only:
        print(f"REFUSED, NOT A VERDICT: {len(refused)} precondition(s); NOTHING was run",
              file=sys.stderr)
        return gatekit.REFUSED
    if refused:
        # `--measure-only` is NOT AN OVERRIDE, IT IS A LOWER CLAIM. The preconditions above still
        # hold and are still printed; what changes is that this run claims COST and nothing else,
        # so it exits `SKIP` (4) whatever the gates said and no tally of it is a verdict about the
        # tree. A mode that runs under a broken precondition and exits 0 is the exact defect
        # `gatekit` gained exit 5 to stop.
        print(f"MEASUREMENT, NOT A SWEEP: running under {len(refused)} UNSATISFIED precondition(s) "
              f"-- {[w.split(':')[0] for _c, w in refused]}; these rows price gates and adjudicate "
              f"nothing, and this exit is SKIP(4) whatever they say.")

    gates = pop["run"]
    if args.only:
        want = {Path(a).name for a in args.only}
        gates = [g for g in gates if g.name in want]
        missing = sorted(want - {g.name for g in gates})
        if missing:
            print(f"REFUSED, NOT A VERDICT: --only named {missing}, which the RUN SET does not "
                  f"contain, so it would have been a gate nobody discovered", file=sys.stderr)
            return gatekit.REFUSED

    held = take_lock()
    if held:
        print(f"REFUSED, NOT A VERDICT: LOCK-HELD ({held[0]}, pid {held[1]}): {LOCK.name} exists; "
              f"`rm {LOCK}` once you are sure it is dead", file=sys.stderr)
        return gatekit.REFUSED
    try:
        out = args.out if args.out else LOCK.parent / f"runner{'-all' if args.all else ''}.rows"
        # `--out gates/artifacts/x.rows` is relative to the REPO, not to whatever `cwd` the caller
        # happened to be in, and it must be absolute before the summary's `relative_to(ROOT)`.
        # MEASURED by passing a relative one: the sweep ran, wrote every row, and then died on the
        # LAST PRINT -- the shape this project's own rule warns about, an instrument that fails
        # after the work instead of before it.
        out = (ROOT / out).resolve()
        budget = None if args.all else args.budget_seconds
        tally, spent, ran, peak = sweep_run(
            gates, mods, out, args.seconds, args.mb, budget,
            stamp=("MEASUREMENT -- preconditions UNSATISFIED" if refused else "SWEEP"))
    finally:
        LOCK.unlink(missing_ok=True)
    print("TALLY: " + "  ".join(f"{k}={v}" for k, v in sorted(tally.items(), key=lambda kv: str(kv[0]))))
    about = tally.get("PASS", 0) + tally.get("FAIL", 0)
    print(f"THE DENOMINATOR: {about} of {len(gates)} gate(s) run reached a verdict about the tree; "
          f"{tally.get('REFUSED', 0)} refused, {tally.get('SKIP', 0)} did not finish, "
          f"{tally.get('DEAD', 0)} crashed or said nothing.")
    print(f"COST: {spent:.1f}s wall for {ran} of {len(pop['run'])} gates, max peak {peak} MB; "
          f"rows -> {out.relative_to(ROOT)}; per-gate costs -> {COSTS.relative_to(ROOT)}")
    if not ran:
        return gatekit.DEAD
    if args.measure_only:
        return gatekit.SKIP
    return gatekit.PASS if ran == len(gates) else gatekit.SKIP


if __name__ == "__main__":
    sys.exit(main())