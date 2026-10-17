"""GATE on the path resolver: `checks/pathresolve.py` must lose NOTHING and REFUSE EVERY REST.

    .venv/bin/python gates/path-resolve-gate.py            # the census, as a gate
    .venv/bin/python gates/path-resolve-gate.py --plant    # the three seeds, then the census

WHAT THIS GATES, AND WHY IT IS NOT `runs-artifacts.py`'S CENSUS AGAIN. Three instruments in this
tree each had a population that could not name a path -- `checks/runs-artifacts.py:resolve()`'s
no-argument `.parent`, `gates/exitcode-census-gate.py`'s two derived homes, and
`checks/differ.py:SUBSTRATE_INPUTS`'s hand list -- and `checks/pathresolve.py` is the measurement
that says whether the first can be replaced by something that loses nothing. **A RESOLVER NOBODY
RUNS IS A LIST WITH BETTER DOCSTRINGS**, so this file runs it on every invocation and FAILS when
the successor is worse than the thing it replaces.

THE FIVE EXITS COME FROM `gates/gatekit.py`, LOADED BY PATH. `gates/exitcode-census-gate.py` names
the same reason it loads its neighbours by path: `gates/gates-pop.py:95`'s `HOMES` tuple is the
defect, and a gate that hard-codes a number it could read has rebuilt it one level down.

    PASS     no UNEXPLAINED loss, and every refusal carried a reason
    FAIL     the successor named a DIFFERENT EXISTING path for a site the legacy named -- SILENT
             DISAGREEMENT, the shape `AGENTS.md` warns about when it says the difference between
             two instruments IS the finding
    REFUSED  the census could not be taken: no population, or a neighbour failed to load
    SKIP     deliberately unused; this gate either measures or refuses
    DEAD     it ran and emitted nothing -- checked, because `rebase-gate-selftest.py:1168` records
             twelve committed files printing 0 rows for an hour

**WHAT IS DELIBERATELY NOT A FAILURE.** A site the legacy REACHED and the successor REFUSED is not
a loss: the successor said so, per path, with a reason, which is the entire contract. MEASURED
today: LOST 24 distinct (lane, file) pairs over 58 sites, every one of them a refusal, a `BLIND-ENV`
(the legacy bound a name to `""` -- its own spelling of "I cannot name this" -- in a scope that has
nothing to do with the site), or a `NAMED-ROOT` (the successor named the repo root, which is not a
file). Zero `UNEXPLAINED`. **WEAKENING THIS GATE TO GO GREEN IS THE ONE EDIT THAT WOULD MAKE IT
LIAR**, so the plant below drives the three resolver rules that the census's verdict rests on and
turns red if any of them stops being true.
"""
from __future__ import annotations

import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
#: The instrument under gate, named BY PATH and LOADED BY PATH. Never imported by name: a
#: `import pathresolve` would resolve against whichever directory happened to be first on
#: `sys.path`, and a gate that tests a copy is a gate that tests nothing.
UNDER = "checks/pathresolve.py"
GATEKIT = "gates/gatekit.py"

#: The three resolver RULES the verdict rests on: `(seed, variable, expected_path_or_None)`. These
#: are claims about BEHAVIOUR and they are asserted over `checks/pathresolve.py:seed_answers()`,
#: not over that file's STDOUT -- a gate that decides by parsing another gate's prose is a gate
#: that fails on a rewrap. `None` means the claim is a REFUSAL, and the refusal must carry a reason.
CLAIMS = (("path", "G", "checks/gen"), ("path", "HERE", "checks"),
          ("climb", "D", "runs/g"), ("climb", "ROOT", ""),
          ("refuse", "G", None))


def instrument(rel, name=None):
    """Load a module BY PATH. `gates/exitcode-census-gate.py:instrument()` is the same function
    with the same reason, and copying it here rather than sharing it is a cost this tree pays twice
    already."""
    spec = importlib.util.spec_from_file_location(name or rel.replace("/", "_")[:-3],
                                                  os.path.join(ROOT, rel))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def plant_bad(pr):
    """Every claim, re-derived by running the seeds. Returns the claims that are no longer true."""
    rows = {(name, var): (path, why) for name, var, path, why in pr.seed_answers()[1]}
    bad = []
    for seed, var, want in CLAIMS:
        got = rows.get((seed, var))
        if got is None:
            bad.append(f"seed {seed} has no variable {var}")
        elif want is None:
            if got[0] is not None or not got[1]:
                bad.append(f"seed {seed} {var} = {got[0]!r} -- the claim is a REFUSAL WITH A REASON "
                           f"and this is {got!r}")
        elif got[0] != want:
            bad.append(f"seed {seed} {var} = {got[0]!r}, want {want!r}")
    return bad


#: THE THREE REGRESSIONS, EACH ONE A ONE-EDIT REINTRODUCTION OF A DEFECT THAT WAS MEASURED. A GATE
#: THAT HAS NEVER BEEN SEEN TO GO RED IS A GATE WHOSE PASS IS A COINCIDENCE WITH THE DISPATCH
#: ORDER -- `checks/sweep.py:291` says that in its own comment about `LIVE_UNITS`, and this tree
#: measured 6 finished units holding 2,353 files behind a list of 14 names.
#:
#:     drop-parent   the `ast.Attribute` branch descends instead of climbing, which is
#:                   `checks/runs-artifacts.py:201` verbatim -- the defect this gate's subject exists
#:                   to replace
#:     flat-file     `Path(__file__)` answers `""` and means the DIRECTORY, one level too shallow
#:     silent-wrong  every refusal becomes a bare BASENAME, which is the one shape the contract
#:                   forbids: "a resolver that emits a wrong path confidently is worse than one that
#:                   emits nothing"
REGRESSIONS = (
    ("drop-parent",
     "the `Attribute` branch answers a no-argument `.parent` by descending into the call below it"),
    ("flat-file", "`Path(__file__)` answers the file's DIRECTORY, so `.parent` is one level shallow"),
    ("silent-wrong", "every refusal becomes a bare basename, with no reason and no refusal"),
)


def self_test(pr):
    """Reintroduce each regression in memory and assert the census catches it. **THE REGRESSION IS
    A MONKEYPATCH OF `resolve`, NOT AN EDIT ON DISK**, so the tree is never in a broken state and
    the gate is never measured against a tree somebody has to remember to restore."""
    import ast as _ast
    original = pr.resolve
    broken = {}
    for name, why in REGRESSIONS:
        def regressed(node, env, base, depth=0, _name=name):
            if _name == "drop-parent" and isinstance(node, _ast.Attribute) and node.attr == "parent":
                return original(node.value, env, base, depth + 1)
            if _name == "flat-file" and isinstance(node, _ast.Call) \
                    and getattr(node.func, "attr", "") == "Path":
                return ("", None)
            if _name == "silent-wrong":
                return (original(node, env, base, depth)[0] or "?", None) if \
                    original(node, env, base, depth)[0] is None else original(node, env, base, depth)
            return original(node, env, base, depth)
        pr.resolve = regressed
        try:
            bad_plant = plant_bad(pr)
            _body, _lost, (code, _why), facts = pr.census()
            unexplained = facts["buckets"].get("UNEXPLAINED", 0)
            # **CAUGHT MEANS SOMETHING WENT RED, NOT THAT A PARTICULAR INSTRUMENT WENT RED.** The
            # `flat-file` regression is invisible to the set difference -- it moves LOST and GAINED
            # and moves neither verdict -- and is caught by the PLANT instead, because
            # `Path(__file__)` answering the file's DIRECTORY makes `HERE` bind to `".."` rather
            # than `"checks"`. A self-test that demanded one instrument catch every regression
            # would be demanding a claim no instrument makes.
            broken[name] = (code, unexplained, bad_plant, why)
        except Exception as exc:
            broken[name] = (None, f"{type(exc).__name__}: {exc}", [], why)
        finally:
            pr.resolve = original
    return broken


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    try:
        gatekit, pr = instrument(GATEKIT), instrument(UNDER)
    except Exception as exc:  # A NEIGHBOUR THAT WILL NOT IMPORT IS A MISSING PRECONDITION.
        print(f"REFUSED {type(exc).__name__}: {exc}", file=sys.stderr)
        return gatekit.REFUSED if "gatekit" in dir() else 3, f"gatekit did not load: {exc}"
    if not hasattr(pr, "census") or not hasattr(pr, "seed_answers"):
        print(f"REFUSED {UNDER} no longer exports census()/plant()", file=sys.stderr)
        return gatekit.REFUSED, f"{UNDER} no longer exports census()/seed_answers()"

    out = sys.stdout
    sys.stdout = open(os.devnull, "w")  # THE PLANT PRINTS; THE CENSUS PRINTS; THIS GATE DECIDES.
    try:
        pr.plant()
        bad_plant = plant_bad(pr)
        body, lost, (verdict, why), facts = pr.census()
    except Exception as exc:
        sys.stdout = out
        print(f"REFUSED {type(exc).__name__}: {exc}", file=sys.stderr)
        return gatekit.REFUSED, f"the census could not be taken: {type(exc).__name__}: {exc}"
    finally:
        sys.stdout = out

    if "--self-test" in argv:
        print("SELF-TEST, each regression reintroduced in memory and the census re-run:")
        missed = []
        # **THE LOOP VARIABLE IS NOT NAMED `bad_plant`.** MEASURED: it was, and the loop rebound
        # `main`'s own `bad_plant`, so `--self-test` made the gate report the LAST REGRESSION'S
        # plant failure as its own verdict -- a self-test that turns the gate red for the wrong
        # reason, which is the shape `gates/runner.py:391`'s lesson names.
        for name, (code, unexplained, broke, why) in sorted(self_test(pr).items()):
            caught = code == gatekit.FAIL or bool(broke) or isinstance(unexplained, str)
            by = "census" if code == gatekit.FAIL else "plant" if broke else "NOTHING"
            print(f"  {'CAUGHT  ' if caught else 'MISSED  '} {name:<14} by={by:<8} "
                  f"verdict={code} UNEXPLAINED={unexplained} plant={broke or 'ok'}  -- {why}")
            if not caught:
                missed.append(name)
        if missed:
            print(f"  the census did NOT catch: {', '.join(missed)}", file=sys.stderr)
            return gatekit.FAIL, "the census cannot see " + ", ".join(missed)

    print(f"census body  {facts['buckets']}")
    print(f"lost pairs   {len(facts['old'] - facts['new'])} of {len(facts['old'])} legacy-reached"
          f"   gained {len(facts['gained'])}")
    print(f"MAYBE-NONE   {len(facts['maybenone'])} over the whole tracked .py universe, "
          f"{sum(1 for m in facts['maybenone'] if m in facts['graded'])} of them inside W")
    for m in facts["maybenone"]:
        print(f"  {'INSIDE W  ' if m in facts['graded'] else 'OUTSIDE W '} {m}")
    if "--census" in argv:
        print(body)

    if bad_plant:
        return gatekit.FAIL, "the plant no longer proves " + "; ".join(bad_plant)
    unexplained = facts["buckets"].get("UNEXPLAINED", 0)
    if unexplained:
        return gatekit.FAIL, (f"{unexplained} site(s) the successor names a DIFFERENT EXISTING "
                              f"path for; a silent disagreement is worse than a clean zero")
    if not body.strip():
        return gatekit.DEAD, "the census produced no rows, which is DEAD and not PASS"
    if not facts["lanes"][0]:
        return gatekit.REFUSED, "the discovered lane population is EMPTY"
    return gatekit.PASS, (f"{len(facts['old'])} legacy-reached files, none lost unexplained "
                          f"({len(facts['gained'])} gained); "
                          f"refusals {sum(len(v) for v in facts['refusals'].values())} over "
                          f"{len(facts['refusals'])} classes, every one with a reason")


if __name__ == "__main__":
    code, why = main()
    print(f"{'PASS' if code == 0 else 'FAIL' if code == 1 else 'REFUSED' if code == 3 else 'DEAD'}"
          f"  {why}")
    sys.exit(code)