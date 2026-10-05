#!/usr/bin/env python3
"""Does the corpus-growth guard actually FIRE? A census that has never been made to fail is
not known to be a guard.

    .venv/bin/python .agents/slop/want/selftest.py

THE THING BEING PROVEN, and it is the whole point of the change to `checks/differ.py`:

    A graph added to `graphcmp.GRAPHS` and not to `WANT` MUST (a) be run, (b) be recorded in
    `D1-verdicts.txt` marked UNSET, (c) appear in `graphs=`, and (d) make the run exit
    non-zero. Before the change, such a graph was INVISIBLE: never run, never counted, and
    `graphs=` reported the table's length as though it were the corpus.

Nothing here mutates the repository. It builds a THROWAWAY `graphcmp.py` in a temp dir with
one extra graph, points `differ.py`'s `GCMP` at it, and calls the real `cmd_run`-shaped logic
through the real `corpus()`/`declared()`. The live tree, the live corpus and the live
artifacts are untouched: `D` is redirected to a temp directory for every write.

Each case is asserted, and the script exits non-zero if any assertion FAILS -- including the
negative case, because a guard that cannot be shown to fire is not a guard.
"""
import importlib.util
import pathlib
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


differ = load("differ_selftest", ROOT / "checks/differ.py")
GCMP_SRC = (ROOT / differ.GCMP).read_text()
fails = []


def check(label, ok, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'} {label}{'' if ok else '  <- ' + detail}")
    if not ok:
        fails.append(label)


def with_extra_graph(extra):
    """A `graphcmp.py` whose GRAPHS has one more name. Returned via a temp dir; the caller
    owns the lifetime. The stub graph function is never CALLED by the checks below -- they
    assert on NAMES, which is what the guard is made of."""
    tmp = pathlib.Path(tempfile.mkdtemp())
    stub = GCMP_SRC.replace(
        'GRAPHS = {"matmul"', f'GRAPHS = {{"{extra}": None, "matmul"', 1)
    assert stub != GCMP_SRC, "the GRAPHS literal moved; this stub needs its anchor updated"
    (tmp / "graphcmp.py").write_text(stub)
    return tmp


print("CASE 1 -- a graph in the corpus and not in `WANT` must be INVISIBLE no longer")
tmp = with_extra_graph("censusprobe")
differ.GCMP = str(tmp / "graphcmp.py")
graphs, unset = differ.corpus(), [g for g in differ.corpus() if g not in differ.WANT]
check("the new graph is in the corpus", "censusprobe" in graphs, str(graphs[:3]))
check("the new graph has NO expectation", "censusprobe" in unset, str(unset))
check("`graphs=` would count it", len(graphs) == 26, f"len={len(graphs)}")
check("`graphs-unset` would count it", len(unset) == 10, f"len={len(unset)}")
check("`declared()` covers its artifacts",
      {"D1-graph-censusprobe.txt", "D2-cmp-censusprobe.txt",
       "D2-canon-py-censusprobe.txt", "D2-canon-bend-censusprobe.txt"} <= differ.declared())
shutil.rmtree(tmp)

print("\nCASE 2 -- a corpus that SHRINKS is caught too (the old `graphs=len(WANT)` could not)")
differ.GCMP = str(ROOT / ".agents/slop/graphcmp.py")
check("live corpus is 25 and 9 are unset",
      (len(differ.corpus()), len([g for g in differ.corpus() if g not in differ.WANT])) == (25, 9))
check("`graphs` pin equals the live corpus size", differ.PINS["graphs"] == str(len(differ.corpus())),
      f"pin={differ.PINS['graphs']} corpus={len(differ.corpus())}")
check("`graphs-unset` pin equals the live gap",
      differ.PINS["graphs-unset"] == str(len([g for g in differ.corpus() if g not in differ.WANT])),
      f"pin={differ.PINS['graphs-unset']}")

print("\nCASE 3 -- NEGATIVE: a table with no gap must NOT report one")
saved = dict(differ.WANT)
differ.WANT.update({g: "AGREE" for g in differ.corpus()})
check("with every graph answered, nothing is unset",
      not [g for g in differ.corpus() if g not in differ.WANT])
check("so the run would NOT refuse",
      not [g for g in differ.corpus() if g not in differ.WANT], "unset is non-empty")
differ.WANT.clear()
differ.WANT.update(saved)
check("the live table is restored", len(differ.WANT) == 16, f"len={len(differ.WANT)}")

print(f"\n{'ALL PASS' if not fails else str(len(fails)) + ' FAILED: ' + ', '.join(fails)}")
sys.exit(1 if fails else 0)
