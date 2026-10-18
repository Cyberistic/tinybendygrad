#!/usr/bin/env python3
"""Is every `.txt` carve-out EXACTLY as wide as the thing it exempts?

`checks/no-txt.py` INTERSECTS its declarations against the tree, so a declared name with no file
on disk contributes nothing, prints nothing and moves no count. Delete one graphcmp artifact and
this gate gets one exemption wider while saying nothing: **a carve-out that has drifted from its
subject is a hole wearing an exemption's clothes.** That is the one failure `AGENTS.md`'s doctrine
names for carve-outs, and `no-txt.py` structurally cannot see it, so this gate is that reader. The
exempted set is ALREADY wider than the files it exempts, by every staging name and every dormant
lane output; the ABSENCE count moves with a run in flight, so read it from this gate's own output
rather than from any line of prose.

WHAT IS ASSERTED, and why it is not a tautology: for every generator, a declared name that is
ABSENT from disk is DRIFT unless the generator writes that name only sometimes. The `.tmp.` staging
names and the on-demand skipexit lane outputs are dormancy, declared by
`no-txt.py:CONDITIONAL` beside the loader that would otherwise have to know it; the base graphcmp
names are not, so losing one is RED. The set is rebuilt from the live filesystem on every run, so
`PASS 0 stale` is a measurement and not a default.

THE PLANT. RED is reachable without deleting anything: point `no-txt.py`'s `GRAPH_D` at a directory
that holds none of the declared artifacts, which is what "the corpus went stale" looks like, and
every base name becomes absent-and-unconditional. It drives the REAL loader — `differ.declared()`
is still imported by path — so it exercises the code path and not a stub.

    usage: .venv/bin/python gates/txt-carveout-gate.py [--plant]

    exit 0  no carve-out is wider than its subject
    exit 1  at least one declared name is absent and unconditional
    exit 3  REFUSED — `no-txt.py` could not be loaded, so nothing was measured
"""
import importlib.util
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load():
    """`checks/no-txt.py` IMPORTED BY PATH, so the declarations, the walk and this gate cannot
    hold two opinions. A loader that fails is REFUSED, never PASS: a gate that exits 0 having
    measured nothing is worse than no gate, because it is trusted."""
    spec = importlib.util.spec_from_file_location("no_txt", os.path.join(ROOT, "checks/no-txt.py"))
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception as e:
        print(f"  REFUSED: `checks/no-txt.py` did not load ({e!r}) — NOTHING WAS MEASURED")
        return None
    return mod


def main(plant: bool = False) -> int:
    nt = load()
    if nt is None:
        return 3
    if plant:
        with tempfile.TemporaryDirectory(dir=os.path.join(ROOT, ".agents", "slop")) as td:
            nt.GRAPH_D = os.path.relpath(td, ROOT)
            print(f"  PLANT: `GRAPH_D` -> {nt.GRAPH_D} (holds none of the declared artifacts)")
            return report(nt)
    return report(nt)


def report(nt) -> int:
    for label, absent, present in nt.drift():
        print(f"  {present:4d} ON DISK / {len(absent):4d} ABSENT   {label}")
    stale = nt.stale()
    if not stale:
        total = sum(len(a) for _, a, _ in nt.drift())
        print(f"  PASS 0 stale — every ABSENT declared name ({total} of them) is declared CONDITIONAL, "
              f"so no carve-out is wider than the files it exempts.")
        return 0
    print(f"  {len(stale)} STALE declared name(s): the carve-out is WIDER than the files it exempts.")
    for label, name in stale[:40]:
        print(f"    {name}   [{label}]")
    if len(stale) > 40:
        print(f"    ... and {len(stale) - 40} more")
    return 1


VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}
PLANTS = {0: ["--plant"], 1: [], 3: []}


if __name__ == "__main__":
    sys.exit(main("--plant" in sys.argv))