#!/usr/bin/env python3
"""Make "the tree is quiet" a PRECONDITION a run can CHECK, instead of a wish.

    usage: .venv/bin/python .agents/slop/quiesce/quiesce.py --watch SECONDS [--period S] [--needs S]
           .venv/bin/python .agents/slop/quiesce/quiesce.py --gate  [--needs S]
           .venv/bin/python .agents/slop/quiesce/quiesce.py --declare
           .venv/bin/python .agents/slop/quiesce/quiesce.py --plant {moving,quiet}

    EXIT: 0 PASS  ·  3 REFUSED  ·  5 DEAD  ·  2 usage.

WHY. Two runs failed for one reason, and it is not a flaky test. `run34`: a 294 s `differ.py run`
had its port edited 10 s after the graph phase finished (`render/upat.bend` 15:35:12, `ops.bend`
15:35:24, `fold.bend` 15:39:43), so every step from `control` onward emitted `0 rows` -- a compile
break, not a measurement. `getaddrwire`: `graphcmp.bend` was rewritten 3x in 11 min, so the run was
SKIPPED rather than taken. **A 294 s run against a tree whose longest quiet gap is 10 s is not a
measurement.** `AGENTS.md` already owns the general rule for a different resource -- *"THE
PRECONDITION IS THE SUM, NOT THE COUNT"* for `bend`'s RSS -- and this is the same rule applied to
WRITES: the precondition is the LENGTH OF THE QUIET WINDOW, and it is measured, not assumed.

THE FIVE VERDICTS, AND WHY THERE IS NO `FAIL` HERE. A gatekit body spells
`PASS, FAIL, REFUSED, SKIP, DEAD = 0,1,3,4,5`. A quietness precondition can only HOLD, be ABSENT,
or be UNMEASURED, so it emits three of the five:
  * `PASS` (0)   -- a quiet window at least `--needs` seconds long was MEASURED. Never "probably".
  * `REFUSED` (3)-- the tree moves; no window that long exists. The answer is not to wait, it is
                    to SNAPSHOT (see `snapshot.py`). Exit 3 is `env-precond.py`'s REFUSED.
  * `DEAD` (5)   -- the window observed is shorter than the run, so nothing about a window that
                    long was measured. `DEAD IS NOT A ZERO AND NOT A PASS`.
  * `FAIL` (1)   -- meaningless here: nothing compares two answers. Printing it would be a lie.
  * `SKIP` (4)   -- reserved for a caller that declines to sample; this file always samples or dies.

THE POPULATION IS DISCOVERED, NOT LISTED (AGENTS.md Doctrine 1). The port is a DIRECTORY WALK
(`tinybendygrad/**`), not a suffix set or a hand list. The run's OTHER moving inputs are read from
the run's OWN declarations -- `differ.py`'s `GCMP` and `graphcmp.py`'s `BEND_PROBE` -- so a rename
of either travels with the instrument instead of leaving it watching nothing. `--declare` prints
the population it can see and the anchors that named it; a missing anchor is named, not hidden.

`--needs` DEFAULTS TO THE RUN'S OWN MEASURED LENGTH. `run34`'s guard read
`WITHIN-LIMITS rc=1 peak-RSS=771 MB 294s` (`.agents/slop/run34/REPORT.md` §2), so 294 s is the
number a window must beat. A caller overrides it with the real wall time of the run it is about.
"""
from __future__ import annotations

import argparse
import importlib.util
import pathlib
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
SLOP = ROOT / ".agents" / "slop"
LOG = SLOP / "quiesce" / "writes.tsv"

#: run34's measured guard wall time, in seconds. Named, with its reading, so a caller who changes
#: the run's length knows which number they are moving.
NEEDS = 294

PASS, REFUSED, DEAD = 0, 3, 5


def _snapshot():
    """`snapshot.py` loaded BY PATH, the way `differ.py:107` loads `graphcmp.py` -- a bare import
    works only when the file happens to be `sys.path[0]`, and four callers here load by path."""
    spec = importlib.util.spec_from_file_location(
        "quiesce_snapshot", pathlib.Path(__file__).resolve().parent / "snapshot.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def population() -> list[pathlib.Path]:
    """Every path a `differ.py run` READS -- read from `snapshot.py`'s declaration, so the quiet
    gate watches EXACTLY the set the snapshot freezes. ONE declaration, two consumers (Doctrine 1).

    WATCHING ONLY THE PORT WAS MEASURED WRONG, TWICE OVER. The first revision watched the port plus
    the `graphcmp.{py,bend}` pair and read `PASS` over a window in which `checks/differ.py` was
    rewritten at 05:42:13 -- an input the run reads and the gate did not watch. An instrument that
    watches half its population is a gate that passes on a coincidence."""
    return _snapshot().inputs()


def stamp() -> dict[str, int]:
    """`st_mtime_ns` per population path. mtime, not content-hash: a write that restores identical
    bytes is still a write, and the run can still catch a half-written file between the two."""
    out: dict[str, int] = {}
    for p in population():
        try:
            out[str(p.relative_to(ROOT))] = p.stat().st_mtime_ns
        except OSError:
            pass
    return out


# ---------------------------------------------------------------------------
# OBSERVE -- sample, record `start`/`write`/`end` rows in one auditable `.tsv`.
# ---------------------------------------------------------------------------
def observe(seconds: float, period: float, log: pathlib.Path) -> None:
    """Sample every `period` seconds for `seconds`, appending one TSV row per state change.

    The log is the EVIDENCE, not a summary of it: `--gate` re-reads these exact rows, so the
    verdict and the reading cannot disagree about what moved. `start`/`end` are rows too, so the
    observed SPAN is inside the file and `DEAD` (span < needs) is checkable from the log alone.
    """
    start = time.time()
    prev = stamp()
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w") as f:
        f.write(f"start\t{start:.3f}\n")
        f.flush()
        while True:
            now = time.time()
            if now - start >= seconds:
                break
            time.sleep(max(0.0, min(period, seconds - (now - start))))
            cur = stamp()
            for k, v in cur.items():
                if prev.get(k) != v:
                    f.write(f"write\t{time.time():.3f}\t{k}\n")
                    f.flush()
            prev = cur
        f.write(f"end\t{time.time():.3f}\n")
        f.flush()


def read_log(log: pathlib.Path) -> tuple[float, float, list[tuple[float, str]]]:
    start = end = 0.0
    writes: list[tuple[float, str]] = []
    for ln in log.read_text().splitlines():
        parts = ln.split("\t")
        if parts[0] == "start":
            start = float(parts[1])
        elif parts[0] == "end":
            end = float(parts[1])
        elif parts[0] == "write":
            writes.append((float(parts[1]), parts[2]))
    return start, end, writes


def measure(start: float, end: float, writes: list[tuple[float, str]]) -> dict:
    """Distinct writes, per-file counts, the last write, and the LONGEST QUIET GAP.

    The longest gap includes the trailing OPEN window (last write -> `end`) because that open
    window is the one a run would start in. Boundaries are `[start] + instants + [end]`, so a
    truly silent window is `end - start` and a window cut short by a write cannot claim it.
    """
    instants = sorted({round(t, 3) for t, _ in writes})
    bounds = [start, *instants, end]
    gaps = [bounds[i + 1] - bounds[i] for i in range(len(bounds) - 1)]
    per_file: dict[str, int] = {}
    for _t, p in writes:
        per_file[p] = per_file.get(p, 0) + 1
    return {"span": end - start, "writes": len(writes), "files": len(per_file),
            "per_file": per_file, "longest": max(gaps) if gaps else end - start,
            "last": max(instants) if instants else None}


def judge(log: pathlib.Path, needs: float | None) -> int:
    """The verdict, from the LOG alone. Prints its evidence before it exits (`env-precond.py`'s
    rule: a check that exits before it prints the value it asserted cannot be audited)."""
    needs = NEEDS if needs is None else needs
    if not log.exists():
        return refuse(f"no log at {log.relative_to(ROOT)} -- nothing was measured")
    start, end, writes = read_log(log)
    m = measure(start, end, writes)
    print(f"population : {len(population())} paths (the run's inputs, from snapshot.py)")
    print(f"window     : {time.strftime('%H:%M:%S', time.localtime(start))}.."
          f"{time.strftime('%H:%M:%S', time.localtime(end))} ({m['span']:.0f}s)")
    print(f"writes     : {m['writes']} in {m['files']} file(s); last "
          + (time.strftime('%H:%M:%S', time.localtime(m['last'])) if m['last'] else "never"))
    print(f"longest gap: {m['longest']:.0f}s  (run needs {needs:.0f}s)")
    for p, n in sorted(m["per_file"].items()):
        print(f"    {n:>3} write(s)  {p}")
    if m["span"] < needs:
        print(f"DEAD, NOT A VERDICT: observed {m['span']:.0f}s < the run's {needs:.0f}s -- the "
              f"window was never long enough to say whether one that long exists")
        return DEAD
    if m["longest"] >= needs:
        print(f"PASS: a quiet window of {m['longest']:.0f}s >= {needs:.0f}s was MEASURED")
        return PASS
    print(f"REFUSED, NOT A VERDICT: longest quiet window {m['longest']:.0f}s < the run's "
          f"{needs:.0f}s. The tree moves; DO NOT WAIT -- SNAPSHOT "
          f"(.agents/slop/quiesce/snapshot.py).")
    return REFUSED


def refuse(*why: str) -> int:
    print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
    return REFUSED


# ---------------------------------------------------------------------------
# PLANTS -- a fabricated log for each state, so the gate proves it fires in BOTH.
# ---------------------------------------------------------------------------
def _fabricated(kind: str) -> tuple[float, float, list[tuple[float, str]]]:
    start = 1000.0
    if kind == "quiet":
        return start, start + 600.0, []
    # One write every 60 s across the whole span: the longest quiet gap is 60 s, well under the
    # 294 s run, which is exactly the state `getaddrwire` measured (3 writes in 11 min). A fixture
    # whose trailing tail happened to be quiet would PASS and the plant would prove nothing.
    files = ["tinybendygrad/uop/ops.bend", "tinybendygrad/render/upat.bend",
             "tinybendygrad/uop/fold.bend", ".agents/slop/graphcmp.bend"]
    return start, start + 600.0, [(start + 60.0 * (i + 1), files[i % len(files)]) for i in range(9)]


def plant(kind: str) -> int:
    """Two states, and BOTH halves: a moving tree MUST be REFUSED (3), a quiet tree MUST be
    evaluated (0). A gate that can only refuse is a coin that always says no."""
    if kind not in ("moving", "quiet"):
        print(f"unknown plant {kind!r}", file=sys.stderr)
        return 2
    cases = (("moving", "moving", REFUSED), ("quiet", "quiet", PASS))
    bad = []
    for name, k, want in cases:
        s, e, w = _fabricated(k)
        m = measure(s, e, w)
        got = DEAD if m["span"] < NEEDS else (PASS if m["longest"] >= NEEDS else REFUSED)
        print(f"PLANT {name}: longest gap {m['longest']:.0f}s, span {m['span']:.0f}s "
              f"-> {got} (want {want})  {'OK' if got == want else 'WRONG'}")
        if got != want:
            bad.append(name)
    print(f"--plant {kind}: " + ("OK" if not bad else f"FAILED {bad}"))
    return 1 if bad else 0


def declare() -> int:
    """Print NEEDS and then DELEGATE to `snapshot.py`'s `declare()`, so the population and its
    anchors have ONE author: the quietness gate and the freeze cannot disagree about what the run
    reads, because neither keeps its own copy of the list."""
    print(f"NEEDS = {NEEDS}s (run34's `WITHIN-LIMITS 294s`, `.agents/slop/run34/REPORT.md` §2)")
    rc = _snapshot().declare()
    print(f"quietness population = {len(population())} paths (identical to the freeze population)")
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--watch", type=float, help="sample for N seconds, then judge")
    ap.add_argument("--period", type=float, default=5.0, help="seconds between samples (default 5)")
    ap.add_argument("--needs", type=float, default=NEEDS, help=f"run length to beat (default {NEEDS})")
    ap.add_argument("--gate", action="store_true", help="judge the last log without sampling")
    ap.add_argument("--log", default=str(LOG), help="where the write log lives")
    ap.add_argument("--declare", action="store_true", help="print the population and its anchors")
    ap.add_argument("--plant", choices=["moving", "quiet"], default=None)
    a = ap.parse_args()
    if a.plant:
        return plant(a.plant)
    if a.declare:
        return declare()
    log = pathlib.Path(a.log)
    if a.watch:
        observe(a.watch, a.period, log)
        return judge(log, a.needs)
    return judge(log, a.needs)


if __name__ == "__main__":
    sys.exit(main())
