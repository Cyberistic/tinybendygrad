#!/usr/bin/env python3
"""`graphcmp.GRAPHS` against `differ.WANT`, BOTH DIRECTIONS, named one by one.

    .venv/bin/python .agents/slop/want/census.py

WHY THIS FILE EXISTS.  `checks/differ.py:89-103` was a literal table of graph names ->
expected verdict and the run loop iterated `WANT`, so `graphcmp.GRAPHS` was never read by
the run and `D0-run-summary.txt`'s `graphs=` line counted what `WANT` wrote rather than the
size of the corpus. A graph absent from `WANT` was therefore INVISIBLE, and nine have been
invisible for the whole recorded run. Naming the gap by hand is how it rotted:
`git log -S'"flip": "AGREE"' -- checks/differ.py` returns nothing, so those graphs were
NEVER in any run, not dropped from one.

So the table is derived on both sides HERE, in one place, from the two live sources -- the
corpus (`graphcmp.GRAPHS`) and the table (`differ.WANT`) -- and this is the FIRST thing
written for that job, because a fix whose own census arrives after the fix is a fix that
cannot be checked against what it changed.

EXITS NON-ZERO WHEN THE TWO SIDES DISAGREE, and prints which set is short.  That is the
whole instrument: an inventory nobody has to re-derive is an inventory that can be re-read.
"""
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / ".venv/lib"))
sys.path.insert(0, str(ROOT))


def load(name, path):
    """Import a module BY PATH, so this works without the repo on `sys.path`."""
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


differ = load("differ", ROOT / "checks/differ.py")
graphcmp = load("graphcmp", ROOT / ".agents/slop/graphcmp.py")

GRAPHS, WANT = graphcmp.GRAPHS, differ.WANT
in_want_not_graphs = sorted(set(WANT) - set(GRAPHS))
uncompared = sorted(set(GRAPHS) - set(WANT))

print(f"corpus   graphcmp.GRAPHS : {len(GRAPHS):3d}  {' '.join(sorted(GRAPHS))}")
print(f"table    differ.WANT     : {len(WANT):3d}  {' '.join(WANT)}")
print()
print(f"in WANT, NOT in the corpus (a table entry nothing can produce) : {len(in_want_not_graphs)}")
for g in in_want_not_graphs:
    print(f"  WANT-ONLY {g}")
print(f"in the corpus, NOT in WANT (DECLARED, NEVER RUN, NO EXPECTATION) : {len(uncompared)}")
for g in uncompared:
    print(f"  UNCOMPARED {g}")
print()
print(f"answers the run can compare : {len(WANT) - len(in_want_not_graphs)}")
print(f"questions with no expectation: {len(uncompared)}")
print(f"`graphs=` reports           : {len(differ.corpus())}  <- what `cmd_run` counts today, "
      f"the size of what was ASKED FOR")

# `declared()` is the population `artefacts_ok()` guards and `checks/no-txt.py` excuses, so a
# name the run writes that `declared()` omits is an artifact nothing guards and no policy
# excuses. Since the run now writes every graph in the corpus, the population is the CORPUS.
written = {f"D1-graph-{g}.txt" for g in differ.corpus()} | {f"D2-cmp-{g}.txt" for g in differ.corpus()} \
    | {f"D2-canon-{s}-{g}.txt" for s in ("py", "bend") for g in differ.corpus()}
undeclared = sorted(written - differ.declared())
print(f"\nthe run writes {len(written)} per-graph `.txt` names; "
      f"`declared()` misses {len(undeclared)} of them")
for n in undeclared:
    print(f"  UNDECLARED {n}")

sys.exit(1 if (uncompared or in_want_not_graphs or undeclared) else 0)
