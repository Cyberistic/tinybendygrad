#!/usr/bin/env python3
"""THE TABLE: pin -> artifact -> how many pins read it.

There is NO SWEEP HERE. `sens.py` owns it, because the first revision of this file re-ran the
perturbations to fill a witness column and then reported `stable-failed` as having NO
WITNESS -- not because the pin is dead (sens.py moves it) but because this file's private copy
of the sweep did not know about the `__ONE_LINE__` sentinel sens.py had just grown. A second
copy of a sweep is a sweep that will disagree with the first, silently. So this file IMPORTS
sens.py's measured rows and tallies them.
"""
import collections
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import derive  # noqa: E402
import sens  # noqa: E402

ROOT = derive.ROOT
PINS = derive.differ.PINS
SRC = (ROOT / "checks/differ.py").read_text()
# The two D9 branches are ONE artifact family, so the tally groups them; the two branches are
# what make `stable-failed` and `stable-differ` separately sensitive rather than one number.
NORMALISE = {"D9-stability-* (0-ROW branch)": "D9-stability-* (both branches)"}


def witness_table():
    """pin -> witness family, from `sens.run()`'s MEASURED rows. Absent pin = no witness."""
    out = {}
    for family, _artifact, moved, err in sens.run():
        for k in moved:
            out.setdefault(k, NORMALISE.get(family, family))
        if err:
            print(f"!! {family}: {err}")
    for k in ("graphs", "graphs-answered", "graphs-unset"):
        out.setdefault(k, "(NO ARTIFACT -- graphcmp.GRAPHS + WANT, both source)")
    return out


def blame():
    """The PINS BLOCK's blame -- one range, not 17 per-key guesses.

    A per-key line number is not a thing that exists: the dict is written FOUR keys to a line,
    which is why the first revision of this file blamed 0 for all 17.
    """
    lines = SRC.splitlines()
    start = next(i for i, l in enumerate(lines, 1) if l.startswith("PINS = {"))
    end = next(i for i, l in enumerate(lines, 1) if i > start and l.startswith("}"))
    r = subprocess.run(["git", "-C", str(ROOT), "log", "--format=%h|%cI|%s", "-L",
                        f"{start},{end}:checks/differ.py"], capture_output=True, text=True)
    return start, end, [tuple(ln.split("|", 2)) for ln in r.stdout.splitlines() if "|" in ln]


if __name__ == "__main__":
    ok, _ = derive.selfcheck()
    if not ok:
        raise SystemExit(1)
    wit = witness_table()
    start, end, bl = blame()
    print(f"\n== PIN -> WITNESS ARTIFACT (MEASURED by sens.py) ==\n"
          f"all 17 live in checks/differ.py:{start}-{end} -- ONE dict, four keys to a line\n")
    for k in PINS:
        print(f"  {k:18} {wit.get(k, '** NO WITNESS FOUND **')}")
    tally = collections.Counter(wit.values())
    print("\n== HOW MANY PINS READ EACH WITNESS ==\n")
    for w, n in tally.most_common():
        print(f"  {n:2}  <-  {w}")
    print(f"\n  PINS={len(PINS)}  DISTINCT WITNESSES={len(tally)}  MAX={max(tally.values())}")
    print(f"  dead pins (no witness): {[k for k in PINS if k not in wit] or 'NONE'}")
    print("\n== THE PINS BLOCK'S OWN BLAME ==")
    for h, when, subject in bl[:5]:
        print(f"  {h}  {when}  {subject[:92]}")
