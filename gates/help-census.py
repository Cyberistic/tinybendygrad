#!/usr/bin/env python3
"""help-census.py -- ask every instrument in the tree WHAT IT MEASURES, and tally the answers.

    .venv/bin/python gates/help-census.py --plan          # the population and the reason, runs nothing
    .venv/bin/python gates/help-census.py                 # every entry point, `--help`, into gates/help-census.rows
    .venv/bin/python gates/help-census.py --jobs 8        # read THE PRECONDITION LINE first

THE QUESTION. **HOW MANY INSTRUMENTS CRASH WHEN ASKED `--help` INSTEAD OF REFUSING.** One is on
record -- `gates/crp_graph_census-mutate.py --help` raised `ValueError: max() iterable argument is
empty` -- and that is ONE FILE out of a DISCOVERED population nobody had asked. Every instrument
here exists to measure something, and a file that cannot say what it measures cannot be audited by
a reader who has not read its source.

WHY THE SHAPE MATTERS MORE THAN THE COUNT. `gates/gatekit.py:140` says a traceback stays `DEAD`
and `DEAD` has exit **5** -- but a crash exits **1**, and **1 is `FAIL`**. So every reader that
switches on the exit code reads a crash as a gate that ran and got the wrong answer, which is the
one claim the tree's own vocabulary forbids. This census counts the instruments whose `--help`
says `FAIL` while meaning `DEAD`.

THE SIX SHAPES, KEPT SEPARATE BECAUSE THE EXIT CODE ERASES THE DIFFERENCE.

    USAGE       rc 0 and it said something           PASS
    SILENT      rc 0 and it said NOTHING              DEAD   -- ran, emitted nothing
    RAISED      a traceback                           DEAD   -- ran, crashed
    SAID        rc != 0, a message, no traceback      already REFUSED-shaped, READS as FAIL
    SKIP        rc 4: it says `--help` is unsupported SKIP
    REFUSED     rc 3                                          -- a precondition was absent

`RAISED` IS SPLIT AGAIN, BECAUSE A CRASH AND AN ABSENT FIXTURE LOOK IDENTICAL AND ARE NOT. A gate
that wanted a fixture and got a `--help` raised `FileNotFoundError`; that is a REFUSAL -- a correct
behaviour that looks like a bug -- and `AGENTS.md` says so ("a precondition was absent"). So every
RAISED row is RE-RUN from an EMPTY directory, which is how "point it at a path that does not exist
rather than at one that does" is implemented: **PRECONDITION** if the second run stops raising for
a missing-path reason, **INTRINSIC** if it raises either way. The verdict is the DIFFERENCE between
two runs of the same program, so an instrument whose message merely changes is not scored.

THE POPULATION IS `gates/gates-pop.py:discover()`, LOADED BY PATH -- not a glob, not a suffix set,
not a hand list, because "a hand list is not a population, and an instrument that cannot see its
population cannot be wrong, because it cannot be anything". The vocabulary is
`checks/gatesweep.py:classify`, loaded by path too, because it already grades a captured outcome and
a second copy of the vocabulary is the same fault as a second copy of a population.

THE PRECONDITION LINE, AND IT IS WHY `--jobs` DEFAULTS TO 1. `AGENTS.md` asks for the
`bend`-compiling instruments to be separated out and run ONE AT A TIME with the pure-Python ones in
parallel. **THE SEPARATION CANNOT BE MADE STATICALLY, AND MEASURED, NOT ASSUMED**: the cheapest
static classifier fires on **186 of 215** entries, because `bend` appears in prose --
`checks/bounded.py` names it, `gates/gendirs.py` names it, and the 29 it spares are not the 29 that
never run it. So `--jobs` reads the ledger and PRINTS the sum of the N largest MEASURED peaks before
running anything: at `--jobs 1` that sum is the largest single peak, which is the tightest bound
available without knowing which instrument compiles `bend`, and it is below `AGENTS.md`'s 60% of
`hw.memsize` or the run refuses.

EXIT 0 when nothing crashes, 1 when something does, 3 when the run itself measured nothing.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import time
import warnings
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY = ROOT / ".venv" / "bin" / "python"
LEDGER = HERE / "help-census.rows"
MEM_GB = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / 1024 ** 3

REC = re.compile(r"\[bounded\] (\S+)\s+rc=(-?\d+)\s+peak-RSS=(\d+(?:\.\d+)?) MB")
TRACEBACK = "Traceback (most recent call last)"
# AN EXCEPTION CLASS NAME AND A PHRASE, NOT A PATH SHAPE. A path shape is `repro-paths.py`'s
# suffix set all over again; this census does not need to know WHICH path, only that the program
# stopped because a file it wanted was not there.
MISSING = re.compile(r"FileNotFoundError|NotADirectoryError|IsADirectoryError|No such file|"
                     r"does not exist|not at the repo root")
SHAPES = ("USAGE", "SILENT", "RAISED", "SAID", "SKIP", "REFUSED")
MEANING = {"USAGE": "PASS", "SILENT": "DEAD", "RAISED": "DEAD",
           "SAID": "REFUSED (reads FAIL)", "SKIP": "SKIP", "REFUSED": "REFUSED"}
COLUMNS = ("instrument", "reason", "shape", "verdict", "read_as", "rc", "token",
           "peak_mb", "seconds", "last_line")


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def population(root: Path = ROOT):
    """`(entries, libs, opaque, gates-pop)` -- the discovered population and the module that found it.

    `discover()` re-parses the tree and emits that file's own `SyntaxWarning`s, so they are
    silenced rather than allowed into a console whose numbers are the measurement.
    """
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        gp = _load("hc_pop", root / "gates" / "gates-pop.py")
        # BOTH CALLS INSIDE THE GUARD, MEASURED: the first version returned from under it, and
        # `discover()` leaked six `<unknown>:299 SyntaxWarning` lines into a console whose numbers
        # are the run -- the same leak `checks/gatesweep.py:control()` silences for the same call.
        entries, libs = gp.discover(root)
        opaque = gp.opaque(root)
    return entries, libs, opaque, gp


def command_for(p: Path, reason: str) -> list[str]:
    """The argv that runs this entry point with `--help`, chosen by REASON rather than by suffix.

    `js-main` runs under `node` because JavaScript has no shebang to exec; `sh-*` is exec'd only
    when the mode bit says so and handed to `/bin/sh` otherwise, because a non-executable shell
    file dispatched as `[p, "--help"]` fails `EACCES` and would be counted as a crash the
    instrument did not have.
    """
    if reason == "py-main":
        return [str(PY), str(p), "--help"]
    if reason == "js-main":
        return ["node", str(p), "--help"]
    return [str(p), "--help"] if os.access(p, os.X_OK) else ["/bin/sh", str(p), "--help"]


def shape_of(rc: int, btoken: str, out: str, sweep, gatekit) -> tuple[str, str, str]:
    """`(shape, verdict, read_as)`: what it IS, what `classify` says, and what `$?` says.

    The last one is the whole census: `read_as` is `gatekit.VERDICT`'s own word for the exit code,
    which is the only thing a caller that switches on `$?` ever sees. A crash is `FAIL` there and
    `DEAD` here, and the difference is a defect nobody has counted.
    """
    verdict, token = sweep.classify(btoken, rc, out)
    read_as = gatekit.VERDICT.get(rc, f"UNASSIGNED({rc})")
    if btoken in ("KILLED-ON-MEMORY", "TIMED-OUT"):
        return "SKIP", f"{verdict}/{token}", read_as
    if (verdict, token) == ("DEAD", "SILENT"):
        return "SILENT", f"{verdict}/{token}", read_as
    if (verdict, token) == ("DEAD", "TRACEBACK"):
        return "RAISED", f"{verdict}/{token}", read_as
    if rc == 3:
        return "REFUSED", f"{verdict}/{token}", read_as
    if rc == 4:
        return "SKIP", f"{verdict}/{token}", read_as
    return ("SAID", f"{verdict}/{token}", read_as) if rc else ("USAGE", f"{verdict}/{token}", read_as)


def run_one(p: Path, reason: str, seconds: int, mb: int, sweep, gatekit, scratch: Path) -> dict:
    """One row: rc, the watchdog's token, peak, wall time, shape, and the last line it printed."""
    argv = [str(PY), str(ROOT / "checks" / "bounded.py"), "--seconds", str(seconds),
            "--mb", str(mb), "--", *command_for(p, reason)]
    t0 = time.monotonic()
    r = subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT), timeout=seconds + 120)
    took = time.monotonic() - t0
    m = REC.search(r.stderr)
    btoken, rc, peak = (m.group(1), int(m.group(2)), float(m.group(3))) if m else \
                       ("NO-RECORD", r.returncode, 0.0)
    # THE INSTRUMENT'S OWN WORDS: `bounded`'s record and its two-space continuations are the
    # watchdog's, and a census that counts them has counted rows that are not rows.
    said = "\n".join(l for l in r.stderr.splitlines() if not l.startswith(("[bounded]", "  ")))
    out = r.stdout + "\n" + said
    shape, verdict, read_as = shape_of(rc, btoken, out, sweep, gatekit)
    if shape == "RAISED":
        shape += "-" + raised_as(argv, seconds, mb, out, scratch)
    return {"instrument": str(p.relative_to(ROOT)), "reason": reason, "shape": shape,
            "verdict": verdict, "read_as": read_as, "rc": rc, "token": btoken,
            "peak_mb": peak, "seconds": round(took, 2),
            "last_line": next((l for l in reversed(out.splitlines()) if l.strip()), "")}


def raised_as(argv: list[str], seconds: int, mb: int, first_out: str, scratch: Path) -> str:
    """`PRECONDITION` or `INTRINSIC` -- the same program, run again from an EMPTY directory."""
    try:
        again = subprocess.run(argv, capture_output=True, text=True, cwd=str(scratch),
                               timeout=seconds + 120)
    except subprocess.TimeoutExpired:
        return "INTRINSIC"
    second = again.stdout + again.stderr
    if TRACEBACK not in second:
        return "PRECONDITION"
    return "PRECONDITION" if MISSING.search(first_out) and MISSING.search(second) else "INTRINSIC"


def precondition_line(jobs: int, population_size: int) -> int:
    """The `AGENTS.md` sum rule, against the ledger's MEASURED peaks, and its OWN DENOMINATOR.

    A bound computed from a ledger covering fewer instruments than the population is a bound on
    the wrong population, so the row count is printed beside it. MEASURED: the first version
    printed `sum of the 1 largest MEASURED peaks ... = 0 MB` over a ONE-ROW ledger left by a
    `--only` smoke test, and a reader would have taken 0 MB for a measurement of the whole tree.
    """
    peaks = []
    if LEDGER.is_file():
        peaks = [float(l.split("\t")[COLUMNS.index("peak_mb")])
                 for l in LEDGER.read_text().splitlines()[1:] if "\t" in l]
    top = sorted(peaks, reverse=True)[:jobs]
    bound = sum(top) if top else 0.0
    ok = bound <= 0.6 * MEM_GB * 1024
    print(f"PRECONDITION: --jobs {jobs}, sum of the {len(top)} largest MEASURED peaks over "
          f"{len(peaks)}/{population_size} ledger rows in {LEDGER.name} = {bound:.0f} MB = "
          f"{100 * bound / (MEM_GB * 1024):.1f}% of {MEM_GB:.0f} GB -- "
          f"{'within' if ok else 'ABOVE'} 60%" + ("" if len(peaks) >= population_size else
          f"  [PARTIAL LEDGER: the bound is over {len(peaks)} of {population_size}]"))
    return 0 if ok else 3


def plan(root: Path = ROOT) -> int:
    """The population and how each entry is invoked, and NOTHING RUN."""
    entries, libs, opaque, gp = population(root)
    sweep = _load("hc_sweep", root / "checks" / "gatesweep.py")
    print(f"homes      : {gp._homes(root)}   (derived by gate_homes(), not listed)")
    print(f"population : {len(entries)} entry points + {len(libs)} modules + {len(opaque)} opaque "
          f"= {len(entries) + len(libs) + len(opaque)} regular files walked")
    for reason, n in sorted(Counter(gp.entry_reason(p) for p in entries).items()):
        print(f"  {reason:<12} {n}")
    print(f"control    : checks/gatesweep.py:population() -- "
          f"{len(sweep.population(root))} `gates/*-gate.py`, a DIFFERENT question, printed to disagree")
    for p in entries:
        print("  " + " ".join(command_for(p, gp.entry_reason(p))))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--plan", action="store_true", help="print the population, run nothing")
    ap.add_argument("--jobs", type=int, default=1, help="instruments at once (see the precondition)")
    ap.add_argument("--seconds", type=int, default=60, help="per-instrument time bound")
    ap.add_argument("--mb", type=int, default=2048, help="per-instrument memory ceiling")
    ap.add_argument("--only", default="", help="substring filter on the instrument path")
    args = ap.parse_args(argv)
    if args.plan:
        return plan()

    entries, libs, opaque, gp = population()
    if args.jobs < 1 or precondition_line(args.jobs, len(entries)):
        return 3

    sweep = _load("hc_sweep", ROOT / "checks" / "gatesweep.py")
    gatekit = _load("hc_gatekit", ROOT / "gates" / "gatekit.py")
    todo = [p for p in entries if args.only in str(p)]
    if not todo:
        print(f"REFUSED: --only {args.only!r} selected 0 of {len(entries)} discovered entry points")
        return 3
    with tempfile.TemporaryDirectory() as tmp:
        scratch = Path(tmp)
        one = lambda p: run_one(p, gp.entry_reason(p), args.seconds, args.mb, sweep, gatekit, scratch)
        rows = list(ThreadPoolExecutor(args.jobs).map(one, todo)) if args.jobs > 1 \
            else [one(p) for p in todo]
    # `--only` IS A LOOK AT PART OF THE TREE, AND A LOOK DOES NOT REPLACE THE LEDGER. MEASURED: the
    # first version wrote `rows` unconditionally, so one `--only` smoke test DESTROYED a 218-row
    # census and left one row claiming to be it -- which is the failure mode `rebase-gate-selftest`
    # names, "0 comparisons is indistinguishable from agreement", with the file itself as the answer.
    if args.only:
        print(f"LEDGER: not written -- --only {args.only!r} is {len(rows)} of {len(entries)}, and "
              f"{LEDGER.name} keeps the census that covers the whole population")
    else:
        LEDGER.write_text("\t".join(COLUMNS) + "\n" + "".join(
            "\t".join(str(r[c]) for c in COLUMNS) + "\n" for r in rows))
    return tally(rows, len(entries), len(libs), len(opaque), args)


def tally(rows, n_entries, n_libs, n_opaque, args) -> int:
    """Six shapes, each with its own denominator, and the crash rows named with their last line."""
    counts = Counter(r["shape"] for r in rows)
    print(f"\nrows {len(rows)} of {n_entries} entry points (+{n_libs} modules, +{n_opaque} "
          f"opaque); --jobs {args.jobs} --seconds {args.seconds} --mb {args.mb}")
    print(f"{'shape':<18}{'n':>5}  {'the verdict':<20}the shapes inside it")
    for shape in SHAPES:
        keys = sorted(k for k in counts if k == shape or k.startswith(shape + "-"))
        n = sum(counts[k] for k in keys)
        print(f"{shape:<18}{n:>5}  {MEANING[shape]:<20}"
              + ", ".join(sorted(k.split("-", 1)[1] for k in keys if "-" in k)))
    seen = Counter(r["read_as"] for r in rows)
    print(f"\nWHAT A CALLER READING ONLY $? SEES: "
          + ", ".join(f"{seen[v]} {v}" for v in sorted(seen)))
    crashers = [r for r in rows if r["shape"].startswith("RAISED") and r["read_as"] == "FAIL"]
    print(f"CRASHES THAT `$?` READS AS FAIL: {len(crashers)} of {len(rows)}")
    for r in crashers:
        print(f"  {r['instrument']}  rc={r['rc']}  {r['shape']}\n    {r['last_line'][:120]}")
    peaks = sorted(((r["peak_mb"], r["instrument"]) for r in rows), reverse=True)[:5]
    slow = sorted(((r["seconds"], r["instrument"]) for r in rows), reverse=True)[:5]
    print("TOP PEAKS (MB): " + ", ".join(f"{p:.0f} {i}" for p, i in peaks))
    print("SLOWEST (s)  : " + ", ".join(f"{s:.1f} {i}" for s, i in slow))
    print(f"LEDGER: {LEDGER.relative_to(ROOT)} holds the whole-population census"
          if args.only else f"LEDGER: {LEDGER.relative_to(ROOT)} ({len(rows)} rows)")
    return 1 if crashers else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))