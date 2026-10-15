#!/usr/bin/env python3
"""gatesweep.py -- run the gate population under a watchdog and tally the FIVE verdicts.

    .venv/bin/python checks/gatesweep.py --plan           # the population and the control, run nothing
    .venv/bin/python checks/gatesweep.py --prove          # classify REAL captured outcomes, run nothing
    .venv/bin/python checks/gatesweep.py --selftest       # drive the loop on SYNTHETIC gates, temp-dir
    .venv/bin/python checks/gatesweep.py --selftest --plant   # ... and the selftest MUST fail
    .venv/bin/python checks/gatesweep.py                  # run every gate, write the rows

THE FOREIGN SWEEP THIS REPLACES. A zsh script under `/tmp` ran `gates/*-gate.py`, kept only `$?`,
and sent every gate's output to `/dev/null` -- so a gate that ran and emitted nothing (DEAD, 5)
was indistinguishable from one that agreed (PASS, 0). Four faults, and each is answered here:

  POPULATION  a DIRECTORY WALK of `gates/` for `*-gate.py`, DERIVED at run time, never listed.
              The control is `gates/gates-pop.py:discover()`, which answers a DIFFERENT question
              ("every entry point in both gate homes") and is printed beside the walk so the two
              denominators are seen to disagree on purpose. A literal list is not a population;
              neither is the foreign glob, and the control is how the walk stays auditable.
  WATCHDOG    every gate runs THROUGH `checks/bounded.py`, so a hung or hungry gate is killed and
              its PEAK is reported. The kill's own TOKEN (KILLED-ON-MEMORY / TIMED-OUT /
              NOT-STARTED / NO-VERDICT) is read -- never the exit status, which the watchdog's own
              header records a unit losing 425 rows to.
  OUTPUT      both streams are CAPTURED, so DEAD-by-silence is a state this instrument can see:
              a gate that exits 0 having printed nothing is DEAD, and that is the whole point.
  VERDICT     the five are `gates/gatekit.py`'s, LOADED BY PATH. Every `*-gate.py` here is a
              gatekit gate, so its exit code IS its declared verdict -- but only once the
              watchdog's 3/4/5 are separated from the gate's, an unassigned code REFUSES, and a
              crash (rc 1 + a traceback) is DEAD rather than FAIL.

WHAT THIS FILE DOES NOT DO. It does not scrape a gate's PROSE for a verdict word. The token is
`gatekit.VERDICT`'s own word for the exit code, because the tree SPELLS the token as the exit --
`gatekit.py:60` is `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`. A word matched out of free
text is a shape, and this project has paid for shape-matching a population three times.
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
        entries, libs = _load("gw_pop", root / "gates" / "gates-pop.py").discover(root)
    return f"{len(entries)} entries + {len(libs)} modules"


gatekit = _load("gw_gatekit", GATES / "gatekit.py")     # the FIVE, and `VERDICT`
bounded = _load("gw_bounded", HERE / "bounded.py")      # its TOKENS, imported not re-typed


def population(root: Path = ROOT) -> list[Path]:
    """Every `*-gate.py` under `gates/`, by DIRECTORY WALK (`os.walk`, `lstat`-regular).

    `__pycache__` is not descended and a symlink is not a file, so a cached `.pyc` and a link
    target cannot be counted as a gate. The set is derived from the tree at run time; nothing
    here is a name written down once.
    """
    found = []
    for dirpath, dirnames, filenames in os.walk(root / "gates", followlinks=False):
        dirnames[:] = [d for d in dirnames if d != "__pycache__"]
        for name in filenames:
            p = Path(dirpath) / name
            if name.endswith("-gate.py") and stat.S_ISREG(os.lstat(p).st_mode):
                found.append(p)
    return sorted(found)


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


def run_one(gate: Path, seconds: int, mb: int) -> tuple[str, str, int, float, str]:
    """`(verdict, token, rc, seconds, peak)` for one gate, run under `checks/bounded.py`."""
    cmd = [str(PY), str(HERE / "bounded.py"), "--seconds", str(seconds), "--mb", str(mb),
           "--", str(PY), str(gate)]
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


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plan", action="store_true", help="print the population and the control")
    ap.add_argument("--prove", action="store_true", help="classify real captured outcomes")
    ap.add_argument("--selftest", action="store_true", help="drive the loop on synthetic gates")
    ap.add_argument("--plant", action="store_true",
                    help="with --selftest: mislabel one expected verdict, so the selftest MUST fail")
    ap.add_argument("--seconds", type=int, default=600, help="per-gate wall bound")
    ap.add_argument("--mb", type=int, default=2048, help="per-gate peak-RSS ceiling")
    ap.add_argument("--out", type=Path, default=ROOT / "gates" / "artifacts" / "gates-sweep.rows")
    args = ap.parse_args(argv)

    gates = population(ROOT)
    # the control, printed every run: `discover()` answers "entry points", not "*-gate.py"
    try:
        control_line = control(ROOT)
    except Exception as exc:                      # a control that cannot run is named, not zero
        control_line = f"UNAVAILABLE ({type(exc).__name__})"
    print(f"POPULATION: directory walk gates/*-gate.py -> {len(gates)}")
    print(f"CONTROL   : gates-pop.discover() -> {control_line} (a DIFFERENT question)")

    if args.plan:
        for g in gates:
            print(f"  would run  {g.relative_to(ROOT)}")
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


def sweep(gates: list[Path], out: Path, seconds: int, mb: int) -> int:
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
        for g in gates:
            verdict, token, rc, took, peak = run_one(g, seconds, mb)
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
# FIVE ONE-LINE GATES, ONE PER FIXTURE, NAMED SO THE SLEEPER SORTS LAST: `population()` sorts, so
# `skip-gate.py` being last IS the window the flush proof reads into. Each source is the SMALLEST
# child that lands on its verdict, and the expected verdict is what `classify` must return -- so a
# child drifting onto another branch is a FAIL here and not a silent pass.
PLANTS = (
    ("dead-gate.py", "DEAD", ""),                                      # rc 0, emitted nothing
    ("fail-gate.py", "FAIL", "import sys; sys.stderr.write('no\\n'); sys.exit(1)"),
    ("pass-gate.py", "PASS", "print('ok')"),
    ("refuse-gate.py", "REFUSED", "import sys; sys.stderr.write('absent\\n'); sys.exit(3)"),
    ("skip-gate.py", "SKIP", "import time; time.sleep(60)"),           # the 1 s bound kills it
)


def selftest(plant: bool = False) -> int:
    """Drive `sweep()` on a SYNTHETIC population and assert what it wrote. PASS=0, FAIL=1.

    THE POPULATION IS A TEMP `gates/` INSIDE THE REPO, so `population()` walks it and every
    `relative_to(ROOT)` in the loop holds -- the loop under test is the loop that runs. Nothing
    here is a unit test of `classify()`: the subject is the ROWS FILE, because that is the artifact
    a killed sweep leaves behind and the only thing a reader downstream ever sees.

    `plant=True` MISLABELS ONE EXPECTED VERDICT ON PURPOSE. A selftest that cannot go red is a
    claim with no counterexample, so the mutation is a flag on the same code path rather than a
    second harness: `.venv/bin/python checks/gatesweep.py --selftest --plant` MUST return 1.
    """
    results: list[tuple[str, bool, str]] = []
    with tempfile.TemporaryDirectory(prefix="gwself.", dir=ROOT / ".agents" / "slop") as td:
        root = Path(td)
        (root / "gates").mkdir()
        for name, _, src in PLANTS:
            (root / "gates" / name).write_text(src)
        gates = population(root)                       # the SAME directory walk the real run uses
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

    failed = 0
    for name, ok, detail in results:
        print(f"[{'PASS' if ok else 'FAIL':>4}] {name}\n          {detail}")
        failed += 1 if not ok else 0
    print(f"\n=== selftest {'PASS' if not failed else 'FAIL'}: {len(results)} case(s), "
          f"{failed} failed{' -- PLANTED, and the failure is the point' if plant else ''} ===")
    return gatekit.FAIL if failed else gatekit.PASS


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
