#!/usr/bin/env python3
"""PLANTS FOR `checks/oracle-txt-census.py`. Each MUST BE ABLE TO MOVE.

A PLANT THAT CANNOT MOVE IS A PLANT THAT PASSES. Every plant here is built as a function that
mutates a PRIVATE tree and re-runs the census's own functions; the runner asserts the census CHANGED
between states. It writes into a `tempfile` tree, never into `oracles/`: a plant inside the
population under test is a plant that moves the answer it measures (the census says so itself,
`code_files()`).

  PLANT 1  SHAPE. Rename the bytes to a name with no hint and the verdict must not move; rewrite the
           bytes and it MUST move. Name-driven classification fails the first; content-blind
           classification fails the second.

  PLANT 2  REACH. The census used to call every reader whose path is GONE a STALE read of the file.
           **STALE AND ABSENT ARE TWO VERDICTS.** A reader whose sub-tree survived MOVED (STALE); a
           reader sharing only the basename is a NAMESAKE (ABSENT). The plant constructs both states
           on the SAME file with the SAME bytes, and requires the census to tell them apart. Before
           the split both read STALE and beat 2 below FAILS.

usage: .venv/bin/python .agents/slop/oracletxt/plant.py
"""
from __future__ import annotations

import importlib.util
import pathlib
import shutil
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
CENSUS = HERE.parents[2] / "checks/oracle-txt-census.py"
SPEC = importlib.util.spec_from_file_location("census", CENSUS)


def excluded() -> frozenset[str]:
    """The reader-set exclusions THIS plant declares to the census, derived from `__file__`.

    This file names oracle `.txt` paths as fixture bytes, so the census would count it as a reader
    of whatever it names. The exclusion is its OWN tree, computed rather than typed: move the plant
    and the exclusion moves with it. `checks/oracle-txt-census.py:plant_exclusions()` loads this by
    path, so this is the ONE declaration -- a second copy in the census is the hand-list fault the
    `skip` tuple was.
    """
    return frozenset({f"{HERE.relative_to(HERE.parents[2])}/"})

ROWD = "alpha=1\nbeta=2\ngamma=3\n"
SRC = "def f(x: int) -> int:\n    return x\n\n\nclass C:\n    pass\n"
CRASH = "Traceback (most recent call last):\n  File \"o.py\", line 1\nValueError: boom\n"


def load():
    m = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(m)
    return m


def report(name, ok, detail):
    print(f"  {'PASS' if ok else 'FAIL'}  {name}\n        {detail}")
    return ok


def census(m, root, readers):
    """Run the census over `root`, with `readers` as the only tracked scripts."""
    m.ROOT = root
    m.ORACLES = root / "oracles"
    m.code_files = lambda: readers
    rows, thr = m.census()
    return rows, thr, {r["path"]: r for r in rows}


def plant_shape(m, tmp):
    """Rename the bytes and the verdict must hold; rewrite the bytes and it must move."""
    oracles = tmp / "oracles"
    oracles.mkdir(parents=True)
    (oracles / "blessed.rows").write_text(ROWD)
    target = oracles / "zzz-no-hint.txt"
    target.write_text(ROWD)
    _, thr, a = census(m, tmp, [])

    # beat 1: a ROWDUMP at a no-hint name -- classified by bytes, so still a rowdump.
    s1 = a["oracles/zzz-no-hint.txt"]["shape"]
    # beat 2: the SAME name, SOURCE bytes -- the verdict MUST move. A name-driven classifier cannot.
    target.write_text(SRC)
    (oracles / "oracle-looking.txt").write_text(ROWD)
    (oracles / "rows-looking.txt").write_text(CRASH)
    _, thr, b = census(m, tmp, [])
    s2 = b["oracles/zzz-no-hint.txt"]["shape"]
    ol = b["oracles/oracle-looking.txt"]["shape"]
    rl = b["oracles/rows-looking.txt"]["shape"]

    return all([
        report("plant1 beat 1: rowdump at a name with no hint keeps its shape",
               s1 == "rowdump", f"zzz-no-hint.txt -> {s1}"),
        report("plant1 beat 2: source bytes at the SAME name MOVES the verdict",
               s2 == "source-in-txt" and s2 != s1, f"zzz-no-hint.txt {s1} -> {s2}"),
        report("plant1: a rowdump at an ORACLE-LOOKING name is still a rowdump (the name is not it)",
               ol == "rowdump", f"oracle-looking.txt -> {ol}"),
        report("plant1: a crash dump at a ROWS-LOOKING name is still a crash dump",
               rl == "crash-dump-in-txt", f"rows-looking.txt -> {rl}"),
    ])


def plant_reach(m, tmp):
    """One file, one set of bytes; the READER's path decides STALE vs ABSENT."""
    oracles = tmp / "oracles"
    (oracles / "sub").mkdir(parents=True)
    donor = oracles / "sub/rows.txt"
    donor.write_text(ROWD)
    (tmp / "gone/sub").mkdir(parents=True)      # the reader's OLD sub-tree, still on disk
    (tmp / "else").mkdir(parents=True)          # a directory that shares nothing but the basename
    reader = tmp / "reader.py"

    # beat 1: the reader's path is gone and its SUB-TREE survived -> the read MOVED -> STALE.
    reader.write_text('OPEN = "gone/sub/rows.txt"\n')
    _, _, a = census(m, tmp, [reader])
    r1 = a["oracles/sub/rows.txt"]

    # beat 2: the reader's path is gone with ONLY the basename in common -> a NAMESAKE -> ABSENT.
    reader.write_text('OPEN = "else/rows.txt"\n')
    _, _, b = census(m, tmp, [reader])
    r2 = b["oracles/sub/rows.txt"]

    # beat 3: the reader names the gone sub-tree again, and NOW the path EXISTS with DIFFERENT bytes.
    reader.write_text('OPEN = "gone/sub/rows.txt"\n')
    (tmp / "gone/sub/rows.txt").write_text("plant2_namesake=1\n")
    _, _, c = census(m, tmp, [reader])
    r3c = c["oracles/sub/rows.txt"]

    # beat 4: the reader's path EXISTS holding THIS file's bytes -> LIVE.
    (tmp / "gone/sub/rows.txt").write_text(ROWD)
    _, _, d = census(m, tmp, [reader])
    r4 = d["oracles/sub/rows.txt"]

    verdicts = ["STALE" if r1["stale"] else "ABSENT",
                "STALE" if r2["stale"] else "ABSENT",
                "SHADOW" if r3c["shadow"] else "?",
                "LIVE" if r4["live"] else "?"]
    return all([
        report("plant2 beat 1: a reader whose path is GONE and whose SUB-TREE survived reads STALE",
               bool(r1["stale"]) and not r1["absent"], f"sub/rows.txt -> {verdicts[0]}"),
        report("plant2 beat 2: a reader whose path is GONE with ONLY the basename reads ABSENT, "
               "not STALE",
               bool(r2["absent"]) and not r2["stale"], f"sub/rows.txt -> {verdicts[1]}"),
        report("plant2 beat 3: a reader's path holding DIFFERENT bytes reads SHADOW",
               bool(r3c["shadow"]), f"sub/rows.txt -> {verdicts[2]}"),
        report("plant2 beat 4: a reader's path holding THESE bytes reads LIVE",
               bool(r4["live"]), f"sub/rows.txt -> {verdicts[3]}"),
        report("plant2: the four beats were DISTINCT STATES -- the plant MOVED",
               len(set(verdicts)) == 4, " -> ".join(verdicts)),
        report("plant2: the file under test was never edited",
               donor.read_text() == ROWD, "donor bytes identical throughout"),
    ])


def main() -> int:
    m = load()
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="oracletxt-plant-"))
    try:
        print("PLANT 1 -- SHAPE, moved by rewriting the bytes")
        ok1 = plant_shape(m, tmp)
        print("\nPLANT 2 -- REACH, moved by the READER's path (STALE vs ABSENT)")
        ok2 = plant_reach(m, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n  {'ALL PLANTS PASS' if ok1 and ok2 else 'PLANT FAILURE'}")
    return 0 if ok1 and ok2 else 1


if __name__ == "__main__":
    sys.exit(main())
