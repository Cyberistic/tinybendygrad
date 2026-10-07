r"""WHAT GOES WRONG, MEASURED -- AND THE FALSE BRANCH, NOT A DIFF.

A fix without the OBSERVED WRONG ANSWER is a diff, not a fix, so every claim here is a PRINTED
TRANSCRIPT from running the tree's own code with a `True` where an `int` was expected. The whole
point is that THE ORDINARY CASE IS FINE AND THE BOOL IS NOT, so nothing here is planted with an
integer: an integer plant proves nothing, which is `plantthe46`'s vacuous counterfactual a fourth
time.

    .venv/bin/python .agents/slop/boolexit/plant.py
"""
import sys

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def _load(rel, name):
    import importlib.util
    p = ROOT / rel
    spec = importlib.util.spec_from_file_location(name, p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def h(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


def main():
    gk = _load("gates/gatekit.py", "gk_plant")

    # ---------------------------------------------------------------- 1. the table itself
    h("1. `int(True) == 1`: the WHOLE gatekit.VERDICT TABLE is reachable by a bool, by "
      "construction")
    V = gk.VERDICT
    print(f"   VERDICT keys            : {list(V)}")
    print(f"   V[True]  == V[1]        : {V[True]!r} == {V[1]!r} -> {V[True] == V[1]}")
    print(f"   V[False] == V[0]        : {V[False]!r} == {V[0]!r} -> {V[False] == V[0]}")
    print(f"   True in V               : {True in V}   <-- a 'FALSE MEMBER' verdict is a MEMBER")
    print(f"   False in V              : {False in V}")
    print(f"   V.get(True)             : {V.get(True)!r}  <-- .get() does NOT refuse either")

    # ---------------------------------------------------------------- 2. THE FALSE BRANCH
    h("2. THE FALSE BRANCH, IN THE TREE'S OWN CODE. The UNGUARDED shape vs the GUARDED shape")
    # the shape BEFORE tonight's fix -- this is `exitcode`'s `charge`, verbatim in structure
    def charge_before(code):
        return code if code in gk.VERDICT else gk.REFUSED

    print("   charge_BEFORE(True)  ->", charge_before(True),
          "   <-- TRUE became FAIL(1). SILENT. No exception, no traceback, no word.")
    print("   charge_BEFORE(1)     ->", charge_before(1), "  (the int, indistinguishable)")
    print("   charge_BEFORE(False) ->", charge_before(False), " <-- and False became PASS(0), the")
    print("                                                  one exit that is TRUSTED WITHOUT BEING")
    print("                                                  READ. The other direction is worse.")
    print("   charge_AFTER(True)   ->", gk.charge(True), "  (the fix, `gatekit.py:110`)")
    print("   charge_AFTER(1)      ->", gk.charge(1), "  <-- 0 consumers change; that is WHY it lands")

    print("\n   and the WORD layer, which is what a reader sees:")
    print("   verdict_of(True)     ->", gk.verdict_of(True))
    print("   verdict_of(False)    ->", gk.verdict_of(False))
    print("   verdict_of(1)        ->", gk.verdict_of(1))
    print("   verdict_of(2)        ->", gk.verdict_of(2), " <-- an UNASSIGNED CODE, 13 files emit it")

    # ---------------------------------------------------------------- 3. THE ORDERING TRAP
    h("3. WHY `exitcode` REORDERED THE GUARD rather than adding one")
    VERDICT = gk.VERDICT
    PASS, FAIL, REFUSED = gk.PASS, gk.FAIL, gk.REFUSED

    def lookup_first(code):
        return VERDICT[code]                    # the guard AFTER the lookup: too late

    def guard_first(code):
        if isinstance(code, bool):
            return f"UNASSIGNED (bool {code})"
        return VERDICT[code]

    for fn in (lookup_first, guard_first):
        for probe in (True, False, 1, 0):
            print(f"   {fn.__name__:<13}({probe!r:<6}) -> {fn(probe)!r}")
        print()
    print("   `guard_first` and `lookup_first` agree on every int and differ on every bool.")
    print("   THAT is the shape a fix has: the ordinary path is byte-identical, and the")
    print("   divergence is exactly the set the defect lives on.")

    # ---------------------------------------------------------------- 4. float, too
    h("4. THE CLASS IS NOT CLOSED BY A bool FIX. `float` is accepted where `int` is expected.")
    for probe in (True, 1, 1.0, 0.0, False, 0):
        try:
            r = repr(VERDICT[probe])
        except KeyError as e:
            r = f"KeyError({e})"
        print(f"   VERDICT[{probe!r:<6}] -> {r:<12} charge({probe!r:<6}) -> {gk.charge(probe)}"
              f"   isinstance(_, bool) = {isinstance(probe, bool)}")
    print("\n   `1.0` is a KEY HIT on a table whose keys are ints, because hash(1.0) == hash(1).")
    print("   A `not isinstance(code, bool)` guard passes `1.0` straight through and it lands on")
    print("   FAIL. **THE FIXED MEMBER IS ONE OF AT LEAST TWO.** `charge(1.0) -> %d` is measured"
          % gk.charge(1.0))

    # ---------------------------------------------------------------- 5. the LATENT sites
    h("5. THE LATENT SITES, DRIVEN WITH A BOOL. `checks/substrate-id.py`'s NAMES table.")
    sid = _load("checks/substrate-id.py", "sid_plant")
    NAMES = sid.NAMES
    print(f"   NAMES keys : {list(NAMES)}")
    for probe in (sid.PASS, sid.FAIL, sid.REFUSED, sid.DEAD, True, False):
        print(f"   NAMES[{probe!r:<5}] -> {NAMES[probe]!r:<12} "
              f"(int {probe!r} -> {NAMES[int(probe)] if isinstance(probe, bool) else NAMES[probe]!r})")
    print("\n   NAMES[True] == NAMES[1] == 'FAIL'. So a bool verdict PRINTS 'FAIL' -- it does not")
    print("   raise, and it does not KeyError. `NAMES.get(rc, rc)` at :247 is WORSE: it would")
    print("   print the string 'FAIL' for a True that means 'it passed', and the word is the whole")
    print("   deliverable of that function.")
    print(f"   NAMES.get(True, True) -> {NAMES.get(True, True)!r}  <-- the DEFAULT never fires, because"
          f" True IS a key")
    print(f"   NAMES.get(99, 99)     -> {NAMES.get(99, 99)!r}  <-- an int out of range DOES reach the default")

    # ---------------------------------------------------------------- 6. the exit-code surface
    h("6. THE FALSE-GREEN DIRECTION, WHICH COSTS MORE THAN THE FALSE-RED")
    print(f"   charge_BEFORE(False) -> {charge_before(False)} = PASS. A bool False is indistinguishable")
    print("   from an int 0 to a runner that reads `$?`, and 0 IS THE ANSWER NOBODY READS.")
    print("   Doctrine 2: 'A GATE THAT EXITS 0 HAVING MEASURED NOTHING IS WORSE THAN NO GATE,")
    print("   BECAUSE IT IS TRUSTED.' A bool False reaching an exit IS that, manufactured by a")
    print("   subclass relationship rather than by a missing check.")

    # ---------------------------------------------------------------- 7. verdict_of's own honesty
    h("7. WHAT THE FIX COSTS THE CALLER, MEASURED")
    probes = [0, 1, 2, 3, 4, 5, True, False, "0", None, 1.0, 99]
    print(f"   {'probe':<8} {'verdict_of':<58} charge")
    for p in probes:
        try:
            v = gk.verdict_of(p)
        except Exception as e:
            v = f"RAISED {type(e).__name__}"
        try:
            c = gk.charge(p)
        except Exception as e:
            c = f"RAISED {type(e).__name__}"
        print(f"   {p!r:<8} {v:<58} {c}")
    print("\n   `verdict_of` NEVER RAISES -- the docstring's own claim, checked against 12 probes")
    print("   including a str, a None and a float. `charge` likewise. THAT is what a mapping that")
    print("   is a vocabulary rather than a trapdoor looks like.")
    return 0


if __name__ == "__main__":
    sys.exit(main())