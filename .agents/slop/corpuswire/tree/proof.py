#!/usr/bin/env python3
"""Prove the corpus-growth protocol on a SCRATCH tree, with NO bend.

`corpusproto` claimed a corpus addition makes TWO pins go red. This reproduces that
claim against the CURRENT tree, then refutes its scope: the number is two only while
the new graph is left OUT of `WANT`; adding its `WANT` row makes it THREE.

Everything runs in a TemporaryDirectory: the copied `corpus-figure.py` is told its
`__file__` lives at `<tmp>/checks/corpus-figure.py`, so `run_health()` reads
`<tmp>/runs/graphcmp/D/D0-run-summary.txt` -- a SYNTHETIC summary for a corpus that has
not been run. No `.txt` is persisted anywhere, and no `bend` process is spawned.
"""
from __future__ import annotations

import importlib.util
import pathlib
import tempfile

ROOT = pathlib.Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
TREE = ROOT / ".agents/slop/corpuswire/tree"

# The base corpus as MEASURED at 2026-10-06 13:59 (sha256 pinned in REPORT.md):
BASE_GRAPHS, BASE_WANT, BASE_UNSET = 30, 20, 10  # 5 old unset + the 5 NEW ones


def load(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def synthetic_summary(graphs: int, answered: int, unset: int) -> str:
    """A summary `cmd_run` WOULD write for a corpus of this shape."""
    return "\n".join([
        f"graphs={graphs}",
        f"graphs-answered={answered}",
        f"graphs-unset={unset}",
        "expect-moved=0", "graphs-agree=21", "graphs-disagree=4",
        "byte-identical=21", "not-comparable=0",
        "stable-pairs=5 of 5", "stable-failed=0 of 5", "stable-differ=0 of 5",
        "plants-disagree=7 of 7", "cross=1 of 1", "selfcheck=# SELFCHECK: OK",
        "conflations=4 of 4", "controls=5 of 5",
        "oracle-selfcheck=# ORACLE SELFCHECK: OK", "census-rc=rc=0",
        "dev=CPU", "lc_all=C", "noopt=0", "pythonhashseed=0",
    ]) + "\n"


def gate(scenario: str, graphs: int, answered: int, unset: int) -> int:
    """Run the COPIED `checks/corpus-figure.py`'s real `run_health()` on a fake summary."""
    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)
        (td / "checks").mkdir()
        (td / "runs/graphcmp/D").mkdir(parents=True)
        (td / "runs/graphcmp/D/D0-run-summary.txt").write_text(
            synthetic_summary(graphs, answered, unset))
        mod = load("cf", TREE / "checks/corpus-figure.py")
        mod.__file__ = str(td / "checks/corpus-figure.py")   # so parents[1] is the tmp root
        ok, line = mod.run_health()
    print(f"  {scenario:44s} ok={ok}  {'; '.join(l for l in [line] if 'RED' in l)}")
    return 0 if ok else 1


def main() -> int:
    print(f"BASE (measured 2026-10-06 13:59): GRAPHS={BASE_GRAPHS} WANT={BASE_WANT} "
          f"unset={BASE_UNSET}\n")
    print("`corpus-figure.py`'s `run_health()`, on synthetic summaries (no bend):")
    red = 0
    # S0 -- the tree as it stands: the corpus already grew, WANT did not.
    red += gate("S0  today: 30/20/10  (nothing wired)", BASE_GRAPHS, 20, BASE_UNSET)
    # S1 -- corpusproto's method: +1 graph in GRAPHS, NO WANT row.
    red += gate("S1  +1 graph, no WANT row  (31/20/11)", BASE_GRAPHS + 1, 20, BASE_UNSET + 1)
    # S2 -- protocol step 1: +1 graph AND its WANT row.
    red += gate("S2  +1 graph + its WANT row  (31/21/10)", BASE_GRAPHS + 1, 21, BASE_UNSET)
    print(f"\nscenarios red: {red} of 3")

    # The GRAPHS-vs-WANT census, which needs NO summary and NO bend, on the LIVE tree.
    g = load("gc", ROOT / ".agents/slop/graphcmp.py")
    d = load("dm", ROOT / "checks/differ.py")
    gap = sorted(set(g.GRAPHS) - set(d.WANT))
    print(f"\nLIVE corpus-vs-WANT census (want/census.py's question, no run needed):")
    print(f"  GRAPHS={len(g.GRAPHS)}  WANT={len(d.WANT)}  UNCOMPARED={len(gap)} {gap}")
    print("  -> RED before any bend run.")

    # The task's exact scratch: ONE dummy graph added to `WANT` only, caught by the
    # census direction no run can reach ("a table entry nothing can produce").
    dummy = load("dm_dummy", TREE / "checks/differ_wantdummy.py")
    want_only = sorted(set(dummy.WANT) - set(g.GRAPHS))
    print(f"\nWANT-only dummy: {want_only}  -> "
          f"{'RED (table entry nothing can produce)' if want_only else 'green'}")
    return 1 if red or gap or want_only else 0


if __name__ == "__main__":
    raise SystemExit(main())
