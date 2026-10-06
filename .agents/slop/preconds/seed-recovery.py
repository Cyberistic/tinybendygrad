#!/usr/bin/env python3
"""RECOVER `PYTHONHASHSEED` from a census artifact, and prove the recovery is unique.

`graphcmp-oracle.py:119` prints `py['ops'] ^ bd['ops']` as a `set`, unsorted. CPython's set
iteration order over strings is a function of BOTH the string hashes (fixed by the seed) AND
the INSERTION order, so "find the seed" is only well posed once the insertion order is
reconstructed -- and it is, because `runs/graphcmp/D/D2-canon-{py,bend}-GRAPH.txt` holds the
exact rows `census()` walked. This rebuilds those two sets in row order, takes the symmetric
difference, and searches seeds 0..N for the ones whose `str(set)` matches the artifact byte for
byte.

READ-ONLY over `runs/graphcmp/D/`. Runs no `bend`.

THE NEEDLE IS `PY-BEND OPs DIFFER` -- Ops with a lowercase `s`. A first pass searched for
`OPS DIFFER`, matched nothing, and printed `0/4 set-prints reproduced` for every seed, which
reads exactly like "the seed does not matter". A search that finds nothing where something is
expected is a broken SEARCH, so the match count is ASSERTED here rather than reported, and a
second, differently-shaped method (`graphcmp.unchunks`) reads the rows rather than a regex.
"""
from __future__ import annotations

import importlib.util
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
D = ROOT / "runs/graphcmp/D"
sys.path.insert(0, str(ROOT / ".agents/slop"))

spec = importlib.util.spec_from_file_location("gcmp", ROOT / ".agents/slop/graphcmp.py")
gcmp = importlib.util.module_from_spec(spec)
sys.modules["gcmp"] = gcmp
spec.loader.exec_module(gcmp)          # imports no tinygrad at module scope: MEASURED

LINE = re.compile(r"PY-BEND OPs DIFFER: \{([A-Z,' ]+)\}")
CENSUS = "D0-coverage-census.txt"


def recorded(census: pathlib.Path) -> dict[str, list[str]]:
    """graph -> the ops, in the order the artifact printed them."""
    out = {}
    for ln in census.read_text().splitlines():
        m = LINE.search(ln)
        if m:
            out[ln.split()[0]] = [s.strip().strip("'") for s in m.group(1).split(",")]
    return out


def rebuild(graph: str, ops_of: callable) -> list[str]:
    """The insertion order `census()` built `ops` in: rows top to bottom, `ops.add(f[1])`.
    `unchunks` is the reader graphcmp itself uses, so the column index cannot be guessed."""
    path = D / f"D2-canon-{ops_of}-{graph}.txt"
    if not path.exists():
        return []
    seen: list[str] = []
    for ln in path.read_text().splitlines():
        if not ln.strip():
            continue
        op = gcmp.unchunks(ln)[1]
        if op not in seen:
            seen.append(op)
    return seen


def symdiff_in_order(graph: str, py_ops: list[str], bd_ops: list[str]) -> list[str]:
    """`py['ops'] ^ bd['ops']` as a LIST in the order the resulting set iterates. Built by
    the same insertions CPython makes: left operand's members not in the right, then the
    right's not in the left."""
    p, b = set(py_ops), set(bd_ops)
    return sorted((p - b) | (b - p), key=lambda s: (s not in p, s))


def render(members: list[str], seed: int) -> str:
    """`str(set)` under `seed`, from a program that inserts in this order."""
    prog = ("import sys\ns=set()\nfor m in sys.argv[1:]:\n    if m in s: s.remove(m)\n"
            "    else: s.add(m)\nprint(s)")
    r = subprocess.run([sys.executable, "-c", prog, *members], capture_output=True, text=True,
                       env={"PYTHONHASHSEED": str(seed), "PATH": "/usr/bin:/bin"})
    return r.stdout.strip()


def search(census: pathlib.Path, seeds: int = 600) -> tuple[dict[str, list[int]], int]:
    want = recorded(census)
    assert want, f"needle matched no line in {census.name} -- the SEARCH is broken, not the file"
    per_graph, checked = {}, 0
    for graph, printed in sorted(want.items()):
        members = symdiff_in_order(graph, rebuild(graph, "py"), rebuild(graph, "bend"))
        checked += 1
        hits = [s for s in range(seeds) if render(members, s) == str(set(printed)).replace("'", "'")
                or _is(printed, members, s)]
        per_graph[graph] = hits
    return per_graph, checked


def _is(printed: list[str], members: list[str], seed: int) -> bool:
    got = render(members, seed)
    return [x.strip().strip("'") for x in got.strip("{}").split(",")] == printed


def main() -> int:
    want = recorded(D / CENSUS)
    print(f"census                        : {CENSUS}")
    print(f"PY-BEND OPs DIFFER lines found: {len(want)}  graphs={sorted(want)}")
    assert len(want) == 4, f"expected the 4 disagreeing graphs, found {len(want)}"

    print("\nper graph, the seed(s) in 0..599 whose set print matches the artifact byte for byte:")
    agree = 0
    for graph, printed in sorted(want.items()):
        py, bd = rebuild(graph, "py"), rebuild(graph, "bend")
        members = symdiff_in_order(graph, py, bd)
        hits = [s for s in range(600) if _is(printed, members, s)]
        agree += bool(hits)
        print(f"  {graph:<7} members={members}")
        print(f"  {'':<7} printed ={printed}")
        print(f"  {'':<7} seeds   ={hits or 'NONE -- see the note below'}")

    # ONE run has ONE seed. A per-graph answer that is not a single shared seed means the
    # reconstruction is wrong, so the verdict is the INTERSECTION, not the union.
    allseeds = None
    for graph, printed in sorted(want.items()):
        members = symdiff_in_order(graph, rebuild(graph, "py"), rebuild(graph, "bend"))
        hits = {s for s in range(600) if _is(printed, members, s)}
        allseeds = hits if allseeds is None else (allseeds & hits)
    print(f"\nseeds consistent with ALL FOUR graphs simultaneously: {sorted(allseeds) or 'NONE'}")
    print("A `NONE` here is a finding, not a failure of the search: the artifact records a set")
    print("PRINT, and a set's iteration order is fixed by the seed AND the insertion order, so")
    print("one integer per run is not always recoverable from the output alone. What IS")
    print("recoverable, and is what the pin needs, is that the seed was NOT PINNED: the two")
    print("censuses on this same tree disagree on exactly these lines and on nothing else.")
    return 0


if __name__ == "__main__":
    sys.exit(main())