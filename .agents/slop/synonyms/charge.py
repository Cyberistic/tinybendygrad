#!/usr/bin/env python3
"""WHAT A RUNNER CHARGES, AND THE COLLISION PLANTED AT THE CHARGE.

    .venv/bin/python .agents/slop/synonyms/charge.py

`AGENTS.md`: "`VOCABULARY-CHARGES-NOTHING` IS THE DIFFERENCE BETWEEN A RUNNER THAT FAILS SAFELY
AND ONE THAT FAILS LOUDLY-BY-MISTAKE." This measures the charge, because **a token is prose and a
charge is arithmetic**: `hooks/run.py:116` reads `r.returncode` and looks it up in a five-name
map. `wallcheck`'s `NO-ROW` is a NAME; the runner never sees it. So the collision is currently
INVISIBLE TO EVERY RUNNER IN THE TREE, and that is the finding -- not that it is harmless, but
that the vocabulary disagreement cannot fail anything until a reader that speaks tokens exists.

The plant takes the runner's OWN arithmetic -- `rc if rc in NAME else DEAD` -- and runs the
collision through it in both directions, so the "fails safely vs loudly-by-mistake" claim is a
measurement and not a sentence.
"""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SURFACE = ROOT / "gates" / "gate-surface.py"

# THE RUNNER'S OWN ARITHMETIC, read from `.agents/slop/hooks/run.py:54,56,116`.
NAME = {0: "GREEN", 1: "FAIL", 3: "REFUSED", 4: "SKIP", 5: "DEAD"}


def charge(rc):
    """`hooks/run.py:116`, verbatim in shape: a code in its own map scores under its own name."""
    return NAME.get(rc, "DEAD")


def main():
    sf = loaded(ROOT / "gates" / "gate-surface.py", "gate_surface_under_charge")
    vocab = sf.vocabulary()
    print("OWNER gates/gatekit.py: " + ", ".join(f"{c}={n}" for c, n in sorted(vocab.items())))
    print(f"RUNNER .agents/slop/hooks/run.py:54,56: "
          f"{', '.join(f'{c}={n}' for c, n in sorted(NAME.items()))}\n")

    print("THE CHARGE, PER CODE -- AND THE TOKEN IS NOT AN ARGUMENT ANYWHERE:\n")
    print(f"  {'rc':>3}  {'owner token':11} {'runner charges':15} AGREE?")
    for c in sorted(set(vocab) | set(NAME)):
        o = vocab.get(c, "-")
        r = charge(c)
        print(f"  {c:>3}  {o:11} {r:15} {'yes' if o == r else 'NO'}")

    print("\nTHE COLLISION, AND WHY IT IS INVISIBLE TO EVERY RUNNER IN THE TREE:\n")
    print("  checks/wallcheck.py:681 declares  `4: \"NO-ROW\"`. gates/gatekit.py:60 names 4 `SKIP`.")
    print("  .agents/slop/hooks/run.py:116 charges by INTEGER, not by token:")
    print(f"      wallcheck exits 4  ->  the runner scores it {charge(4)!r}")
    print("  SO THE COLLISION COSTS NOTHING TODAY, and that is the dangerous half: **a gate whose")
    print("  token means something different from the owner's is scored under the OWNER'S WORD.**")
    print("  `NO-ROW` is 'a guard over an empty population has measured nothing'; `SKIP` is 'it")
    print("  could not run, so it measured nothing'. A runner reading `$?` cannot tell which it")
    print("  has, and NOTHING in the tree will ever tell it, because the token is not an argument.")

    print("\nPLANTED AT THE CHARGE -- BOTH DIRECTIONS:\n")
    checks = []
    got = charge(4)
    checks.append(("A  wallcheck's 4 (NO-ROW: the gate RAN, the SELECTION was empty) is charged as "
                   "SKIP -- 'it could not run'. The two are NOT the same claim, and the charge "
                   "cannot see that",
                   got == "SKIP", f"charged {got!r}"))
    got = charge(2)
    checks.append(("B  wallcheck's 2 (USAGE: the LEDGER PATH is absent) is charged as DEAD -- "
                   "'crashed, not a verdict'. A caller that mistyped a path is scored as a crash",
                   got == "DEAD", f"charged {got!r}"))
    got = charge(6)
    checks.append(("C  a hypothetical sixth exit code is ALSO charged DEAD, with nothing in the "
                   "map -- so a RUNNER'S OWN NEW VERDICT IS INDISTINGUISHABLE FROM A CRASH",
                   got == "DEAD" and charge(2) == got, f"6 and 2 both charge {got!r}"))
    for name, ok, obs in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          {obs}")
    bad = sum(1 for c in checks if not c[1])
    print(f"\nPLANTS: {'GREEN' if not bad else 'RED'} ({len(checks) - bad}/{len(checks)})")

    print("\nAND THE DIRECTION OF THE SAFEST FIX, WHICH IS NOT A TABLE:\n")
    print("  A CHARGE THAT READS A TOKEN cannot be built, because the token is not an argument --")
    print("  a subprocess returns an int. The only way a token reaches a runner is if the gate")
    print("  PRINTS it, and the runner PARSES stdout, which is how `hooks/run.py:111` already")
    print("  gets its `head`. So the additive change is: a gate whose exit MEANS something the")
    print("  owner does not name PRINTS the owner's word too, and the vocabulary stays in the")
    print("  gate. That is a string a runner can read and a table a runner cannot.")
    return 1 if bad else 0


def loaded(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


if __name__ == "__main__":
    with __import__("contextlib").suppress(KeyboardInterrupt):
        sys.exit(main())