#!/usr/bin/env python3
"""gatesweep.py -- run the gate population under a watchdog and tally the FIVE verdicts.

    .venv/bin/python checks/gatesweep.py --plan           # the population and the control, run nothing
    .venv/bin/python checks/gatesweep.py --prove          # classify REAL captured outcomes, run nothing
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
      `cost.tsv`/`cost.out` -- per gate: rc (or `OVER-CAP`), seconds, path, first line of output.
      `run.tsv`             -- per gate: the VERDICT that run recorded.
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
        # `run.tsv` keys `gate-surface.py --report` by its flags; the path is the subject
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
    if args.prove:
        hooks = ROOT / ".agents" / "slop" / "hooks"
        artifact_census(ROOT)
        return prove(hooks / "cost.out", hooks / "run.tsv")

    tally = dict.fromkeys(set(gatekit.VERDICT.values()), 0)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    # FLUSHED PER GATE: a sweep that dies at gate 69 must leave 68 rows, not zero
    sink = args.out.open("w")
    sink.write("gate\tverdict\ttoken\trc\tseconds\n")
    rows = 0
    for g in gates:
        verdict, token, rc, took, peak = run_one(g, args.seconds, args.mb)
        tally[verdict] = tally.get(verdict, 0) + 1
        rel = str(g.relative_to(ROOT))
        print(f"  {verdict:<8} {took:6.1f}s  rc={rc:<4} peak={peak:>4}MB  {rel:<38} {token}")
        sink.write(f"{rel}\t{verdict}\t{token}\t{rc}\t{took:.1f}\n")
        sink.flush()
        rows += 1
    sink.close()
    print("TALLY: " + "  ".join(f"{k}={v}" for k, v in sorted(tally.items())))
    # the denominator, which is not the tally: only PASS/FAIL are verdicts about the TREE
    about = tally.get("PASS", 0) + tally.get("FAIL", 0)
    print(f"THE DENOMINATOR: {about} of {rows} gates reached a verdict about the tree; "
          f"{tally.get('REFUSED', 0)} refused, {tally.get('SKIP', 0)} did not finish, "
          f"{tally.get('DEAD', 0)} crashed or said nothing.")
    print(f"rows -> {args.out.relative_to(ROOT)}")
    return 0 if rows else gatekit.DEAD            # describes THE RUN, never the tree


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
