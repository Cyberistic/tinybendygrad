#!/usr/bin/env python3
"""gatesweep.py -- run the gate population under a watchdog and tally the FIVE verdicts.

    .venv/bin/python checks/gatesweep.py --plan           # the population and the control, run nothing
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

TWO CLASSES A WIDER POPULATION ADMITS, AND NEITHER IS CLOSED HERE. `--selftest`'s WIDTH case
plants both, because a walk is not made honest by being wide.

  A LANE IS NOT A GATE. A `*-oracle.py` run bare prints rows and exits 0, so it lands on PASS and
  PASS is a claim about nothing -- "0 disagreements over 0 comparisons". MEASURED:
  `gates/ew-explog-oracle.py` and `gates/tn_add_sub-oracle.py` both answer rc 0 with rows.
  **NO LANE FILTER IS INSTALLED**, because the declaration available is not a population: of the
  `-oracle.py` members, 13 are named by a `Gate(oracle=...)` argument read off the AST and 15 are
  named by no declaration at all, so a filter would catch 13 of 28 and be a list wearing a
  declaration's clothes. The number moves; the class is what `--selftest`'s `SCRIPT` fixture
  holds still.
  A DRIVER WITH NO `main` IS NOT AN ENTRY. `entry_reason()` asks for `__main__`, so a file whose
  work happens at import is invisible however wide the walk is -- MEASURED 2026-10-18 18:00Z, 70
  of the 76 `py-lib` files under the two homes execute at their top level. **AND THE BUCKET
  ITSELF IS THE FINDING**: `gates-pop.py` calls a module and a script the same word, so its
  `py-lib` count cannot be split without this file's own AST pass.
"""
from __future__ import annotations

import argparse
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


def control(root: Path = ROOT) -> str:
    """`gates/gates-pop.py:discover()`, the denominator the walk is checked against.

    `discover()` answers a DIFFERENT question -- "every entry point in both gate homes" -- and it
    re-parses the tree, emitting `gates-pop.py`'s own `SyntaxWarning`s. Those are not this run's
    subject, so they are silenced here and not allowed into a console whose verdicts matter.
    """
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        entries, libs = gpop.discover(root)
    return f"{len(entries)} entries + {len(libs)} modules"


gatekit = _load("gw_gatekit", GATES / "gatekit.py")     # the FIVE, and `VERDICT`
bounded = _load("gw_bounded", HERE / "bounded.py")      # its TOKENS, imported not re-typed
with warnings.catch_warnings():                          # `gates-pop` parses `.rows` fixtures
    warnings.simplefilter("ignore")                      # and emits its own SyntaxWarnings
    gpop = _load("gw_pop", GATES / "gates-pop.py")

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


def classify(btoken: str, rc: int, text: str) -> tuple[str, str]:
    """`(verdict, token)` from the watchdog's token, the gate's rc, and its captured output.

    Every branch is a measured shape, and the order is the order the evidence is trustworthy in:
      a kill           -> SKIP: it did not answer, so it measured nothing (bounded's own note)
      not started      -> REFUSED: the command itself was an absent precondition
      nothing said, or the watchdog said so -> DEAD: it ran and emitted nothing
      rc 1 + traceback -> DEAD: a crash is not the wrong answer (`hooks/run.py`'s rule, measured)
      else             -> the exit code IS the verdict, through gatekit's own table
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
    return (word, word) if word else ("REFUSED", f"UNASSIGNED({rc})")


def run_one(gate: Path, reason: str, seconds: int, mb: int) -> tuple[str, str, int, float, str]:
    """`(verdict, token, rc, seconds, peak)` for one gate, run under `checks/bounded.py`.

    The interpreter is the one `reason` names, and an UNKNOWN reason is a REFUSAL rather than a
    guess: `RUNNERS.get(reason.split("-")[0], [])` on a language this tree grows would hand it to
    the Python interpreter, and a Python parse error recorded as `FAIL` is a FAIL about the wrong
    subject -- the same defect as running `gate.sh` with `python`.
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
    verdict, token = classify(btoken, rc, r.stdout + "\n" + said)
    peak = re.search(r"peak-RSS=(\d+)", r.stderr)
    return verdict, token, rc, took, (peak.group(1) if peak else "?")


# --------------------------------------------------------------------- the proof, on real data
def prove(cost_tsv: Path, truth_tsv: Path) -> int:
    """Classify REAL, already-captured gate outcomes and require the recorded verdict.

    Inputs are two transcripts a PRIOR run already wrote, so no gate is run:
      `checks/gatesweep-cost.out` -- per gate: rc (or `OVER-CAP`), seconds, path, first line.
      `checks/gatesweep-run.tsv`  -- per gate: the VERDICT that run recorded.
    Both are pinned by content (see `PROVE_PIN`); drift is a REFUSAL, not a smaller proof.
    The classifier must reproduce every recorded verdict from (rc, first-line) alone.
    """
    truth = {}
    for line in truth_tsv.read_text().splitlines()[1:]:
        cells = line.split("\t")
        if len(cells) >= 2:
            truth[cells[0]] = {"GREEN": "PASS"}.get(cells[1], cells[1])   # run.py spells 0 GREEN
    row = re.compile(r"^\s*(\d+|OVER-CAP)\s+([\d.]+)s\s+(\S+)\s+(.*)$")
    n = ok = 0
    for line in cost_tsv.read_text().splitlines():
        m = row.match(line)
        if not m:
            continue
        rc_s, _, path, head = m.groups()
        # a bound fired iff the run reached a cap: the watchdog's token, not a number, says so
        rc = int(rc_s) if rc_s.isdigit() else 0
        btoken = bounded.TIMEOUT if rc_s == "OVER-CAP" else bounded.WITHIN
        verdict, token = classify(btoken, rc, head)
        # `checks/gatesweep-run.tsv` keys `gate-surface.py --report` by its flags; the path is the subject
        want = truth.get(path) or truth.get(path + " --report")
        n += 1
        ok += verdict == want
        print(f"  {'OK ' if verdict == want else 'BAD'}  rc={rc_s:<8} {path:<32} "
              f"-> {verdict:<7} token={token:<14} recorded={want}")
    print(f"PROOF: {ok}/{n} recorded verdicts reproduced from (rc, first line) alone")
    return 0 if ok == n and n else 1


def artifact_census(root: Path = ROOT) -> None:
    """What `gates/artifacts/*/` CAN and CANNOT say, since the brief names it as the proof input.

    `gatekit.Gate` PROMOTES its lanes on PASS and leaves the directory EMPTY otherwise
    (`_clear` empties at construction, `_settle(False)` unlinks the staged files), so a
    directory's CONTENTS are a real captured outcome: populated == the gate reached the diff
    and agreed. But every file here is a LANE (`py.rows`/`bd.out`/`bn.out`/`*.cmp`/`gate.bin`)
    -- never a gate's stdout -- so the directory is NOT an input a token parser can read. That
    is stated rather than papered over, and the token proof runs on the captured transcripts.
    """
    art = root / "gates" / "artifacts"
    dirs = [d for d in art.iterdir() if d.is_dir()]
    pop = [d for d in dirs if any(d.iterdir())]
    empty = [d for d in dirs if not any(d.iterdir())]
    kinds = sorted({f for d in dirs for f in os.listdir(d)
                    if (d / f).is_file() and not f.startswith(".tmp.")})
    print(f"ARTIFACTS: {len(dirs)} gate dirs -- {len(pop)} hold promoted lanes (reached the diff), "
          f"{len(empty)} empty {[d.name for d in empty]}")
    print(f"           a dir holds {kinds}: LANE files, never a gate's stdout")


def report(root: Path = ROOT) -> list[tuple[Path, str]]:
    """Print the FOUR DENOMINATORS, then return the population. Every number is derived here.

    THE ROWS, AND WHY THERE ARE FOUR. `WALK` is what this file now sweeps. `SUFFIX` is the old
    question, asked and answered beside it so the widening is a number rather than an intention.
    `BEFORE` is what this file ACTUALLY swept before the change -- the walk hard-coded to one
    home -- and it is a third number because the two defects are independent: MEASURED, 9 of the
    gap is 9 CONFORMING `checks/*-gate.py` files the suffix had already approved and the home
    could not reach, so quoting only `WALK - SUFFIX` would attribute them to the suffix. `DELTA`
    is the gap split into its two causes, because the remedies differ: a NAME costs a rename the
    brief forbids and a HOME costs nothing at all.
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
        control_line = control(root)
    except Exception as exc:                      # a control that cannot run is named, not zero
        control_line = f"UNAVAILABLE ({type(exc).__name__})"
    print(f"HOMES     : gate_homes() -> {', '.join(hs)}  (MEASURED, not named here)")
    print(f"PRUNED    : dotted entries the walk skips                 -> {pruned}")
    print(f"WALK      : entry points in every derived home            -> {len(pop)}")
    print(f"SUFFIX    : of those, ending in `{SUFFIX}`                -> {len(sfx)}"
          f"   ({files} files end so; {files - len(sfx)} has no entry point)")
    print(f"BEFORE    : `-gate.py` in the one home this file walked   -> {len(before)}")
    print(f"DELTA     : {len(pop)} - {len(before)} = +{len(pop) - len(before)}"
          f"   (+{by_name} by NAME, +{by_home} by HOME)")
    print(f"CONTROL   : gates-pop.discover() -> {control_line}")
    print("            (immediate files only; the walk descends, and `gates/oracles/` is tracked)")
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
    ap.add_argument("--plan", action="store_true", help="print the population and the control")
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
        artifact_census(ROOT)
        drift = gatekit.oracle_drift(PROVE_PIN)   # a transcript that MOVED is a proof of other bytes
        if drift:
            print("PROVE: REFUSED -- " + "; ".join(drift))
            return gatekit.REFUSED
        return prove(ROOT / PROVE_COST, ROOT / PROVE_TRUTH)

    return sweep(gates, args.out, args.seconds, args.mb)


def sweep(gates: list[tuple[Path, str]], out: Path, seconds: int, mb: int) -> int:
    """THE LOOP `main()` RUNS: header, one row per gate, tally, denominator. Describes THE RUN.

    `main()`'s default branch is this call and nothing else, so the `--selftest` that drives it drives
    the REAL path rather than a copy of it. Every row is `flush()`ed as its gate finishes, which is
    the durability property: a sweep killed at gate 69 leaves 68 rows on disk, not zero -- and that
    is the one claim a run that COMPLETES cannot make, so `--selftest` reads the file mid-sweep.
    """
    tally = dict.fromkeys(set(gatekit.VERDICT.values()), 0)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w") as sink:
        sink.write(HEADER + "\n")
        sink.flush()
        rows = 0
        for g, reason in gates:
            verdict, token, rc, took, peak = run_one(g, reason, seconds, mb)
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

    `plant=True` MISLABELS THE EXPECTATIONS ON PURPOSE -- one verdict and one width. A selftest
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
