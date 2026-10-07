#!/usr/bin/env python3
"""THE RUNNER, AS A CONSUMER OF `gates/gate-surface.py`'s CLAUSE IV. NO GATE NAME ANYWHERE.

    .venv/bin/python .agents/slop/declareverdict/runner.py

It reads the census `gate-surface.py` prints and charges every gate whose class is not FINDING.
There is no `--report-gate=`, no tuple, no set of names: the population came from
`gates-pop.discover()` and the class came from each gate's own module body. Delete a gate and the
runner has nothing to update; add one that declares nothing and the runner charges it.

THE EXIT-CODE MAPPING, which a runner aggregates on and CANNOT INVENT:

    rc -> verdict, read from `gates/gatekit.py` BY PATH (never re-typed here)
    0 GREEN   1 FAIL   3 REFUSED   4 SKIP   5 DEAD        a code NOT in that map is UNKNOWN

**UNKNOWN IS CHARGED, and it is charged even from a gate whose class is FINDING.** A `RED_IS` claim
buys amnesty for a RED; it cannot buy amnesty for an exit code the tree has no name for, because an
aggregator that meets UNKNOWN either guesses or calls it DEAD and neither is a pass. That is
`refusalsweep`/`envguard`'s exact failure -- a gate that crashes where it should have refused cannot
tell "the input is absent" from "I am broken" -- and the class is a claim about MEANING while the
code is what gets summed.

FIVE PLANTS, ON SYNTHETIC GATES. Plant 4 is the one that matters most.
  1  a declared FINDING gate's red is TALLIED, not charged -- the runner does not exit non-zero
  2  the SAME GATE with `RED_IS` deleted is CHARGED -- the negative, and the one that matters
  3  an undeclared red whose rc-0 plant never ran is UNTAKEN and is charged, because a gate that
     has never agreed has nothing to have failed from
  4  a declared FINDING gate that declares an exit code `gatekit` has no name for is STILL CHARGED
     -- and 4b is that same gate with the code owned, which is TALLIED. `RED_IS` is not amnesty.
  5  a gate declaring all five OWNED codes is charged for nothing
"""
import contextlib
import importlib.util
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SURFACE = ROOT / "gates" / "gate-surface.py"
PY = ROOT / ".venv" / "bin" / "python"

ROW = re.compile(r"^\s+(\S+\.py)\s+declared\s+(\S+)\s+reached\b.*?\bred=(\w+)\s*(.*)$")


def loaded(path, name):
    """A module BY PATH, never by name. `gates/` is not a package, and putting it on `sys.path`
    would make the name a bindable one any file in the tree could shadow -- an instrument loaded by
    a bindable name is an instrument whose VOCABULARY anybody can choose."""
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def vocabulary():
    """`{rc: verdict}` from `gates/gatekit.py`, through `gate-surface.py`'s OWN reader.

    Reused, not reimplemented: two readers of one owner's declaration are two copies of the
    vocabulary, and a runner holding a second copy of a mapping is blind exactly where the copies
    disagree. `gate-surface.py` guards its `main()`, so loading it runs nothing.
    """
    return loaded(SURFACE, "gate_surface_under_runner").vocabulary()


def classes(root=None):
    """`({gate: (codes, class, why)}, rc)` from a census over `root` (the live tree by default).

    `--report`, because the census's own red is a FINDING about the population and charging it here
    would charge this runner twice for one defect. The classes are read from the same transcript, so
    a runner is not a second source of truth: it reads what the census already decided.
    """
    argv = [str(PY), str(SURFACE), "--report"] + ([f"--root={root}"] if root else [])
    p = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True)
    return {m.group(1): (m.group(2).split("/"), m.group(3), m.group(4))
            for m in map(ROW.match, p.stdout.splitlines()) if m}


def unmapped(codes, vocab):
    """The declared codes `gates/gatekit.py` has no name for. An ABSENCE, and it is charged."""
    return [c for c in codes if c != "-" and int(c) not in vocab]


def verdict(cls, vocab):
    """THE RUNNER'S OWN VERDICT, as `main()` computes it: exit 1 unless every gate is TALLIED.

    Two independent charges, because they are two different defects: `class != FINDING` is a claim
    about what the gate's red MEANS, and an unmapped code is a claim about what the NUMBER is.
    """
    charged = [g for g, (codes, k, _) in cls.items() if k != "FINDING" or unmapped(codes, vocab)]
    return (1 if charged else 0), charged


def tree(td, name, source):
    r = Path(td)
    (r / "pyproject.toml").write_text("[project]\nname='x'\n")
    (r / "tinybendygrad").mkdir()
    (r / "checks").mkdir()
    (r / "gates").mkdir()
    (r / "checks" / name).write_text(source)
    return r


CLAIM = ("import sys\nVERDICTS = {0: 'PASS', 1: 'RED'}\nPLANTS = {0: [], 1: ['--red']}\n"
         "if __name__ == '__main__':\n"
         "    sys.exit(1 if '--red' in sys.argv else 0)\n")
FINDING_GATE = CLAIM.replace("PLANTS = ", "RED_IS = 'FINDING'\nPLANTS = ")
NEVER_GREEN = ("import sys\nVERDICTS = {0: 'PASS', 1: 'RED'}\nPLANTS = {1: ['--red']}\n"
               "if __name__ == '__main__':\n"
               "    sys.exit(1 if '--red' in sys.argv else 0)\n")
# Plant 4a: plant 1's gate, plus ONE extra code that `gatekit` does not own (`checks/dup-gate.py`
# and `checks/wallcheck.py` both spell exit 2 USAGE; this spells it REFUSED, as gate-surface does).
UNMAPPED_CLAIM = FINDING_GATE.replace(
    "VERDICTS = {0: 'PASS', 1: 'RED'}", "VERDICTS = {0: 'PASS', 1: 'RED', 2: 'REFUSED'}").replace(
    "PLANTS = {0: [], 1: ['--red']}", "PLANTS = {0: [], 1: ['--red'], 2: ['--refused']}").replace(
    "sys.exit(1 if '--red' in sys.argv else 0)", "sys.exit(2 if '--refused' in sys.argv else 0)")
# Plant 5: the same gate as 4a with the unmapped code spelled the way `gatekit` spells 3, and then
# with all five OWNED codes. 4a/5 differ ONLY in whether the owner names the code, so the charge can
# only be reading the vocabulary.
ALL_FIVE = ("import sys\nRED_IS = 'FINDING'\n"
            "VERDICTS = {0: 'PASS', 1: 'FAIL', 3: 'REFUSED', 4: 'SKIP', 5: 'DEAD'}\n"
            "PLANTS = {0: ['0'], 1: ['1'], 3: ['3'], 4: ['4'], 5: ['5']}\n"
            "if __name__ == '__main__':\n    sys.exit(int(sys.argv[1]))\n")


def planted(source, vocab=None):
    """The runner's own VERDICT over a one-gate tree: `(rc, classes, charged)`."""
    with tempfile.TemporaryDirectory() as td:
        cls = classes(tree(td, "g.py", source))
    rc, charged = verdict(cls, vocab if vocab is not None else vocabulary())
    return rc, cls, charged


def main():
    vocab = vocabulary()
    cls = classes()
    rc, charged = verdict(cls, vocab)
    charged = set(verdict(cls, vocab)[1])
    tallied = sorted(g for g in cls if g not in charged)
    print(f"RUNNER -- population and classes came from `gates/gate-surface.py --report`, which this "
          f"runner invoked\n   with NO ARGUMENT. No gate name is written in this file.")
    print(f"EXIT VOCABULARY, read from gates/gatekit.py BY PATH: "
          f"{', '.join(f'{k}={v}' for k, v in sorted(vocab.items()))}\n")
    for g in charged:
        codes, k, _ = cls[g]
        bits = [] if k == "FINDING" else [f"red={k}"]
        bits += [f"exit {c} has no name in gates/gatekit.py" for c in unmapped(codes, vocab)]
        print(f"  CHARGED   {g:44} {'; '.join(bits)}")
    for g in tallied:
        print(f"  TALLIED   {g:44} red=FINDING -- its red is its finding")
    print(f"\nRUNNER: {len(charged)} charged, {len(tallied)} tallied, {len(cls)} gates classed")

    checks = []
    got, _c, _h = planted(FINDING_GATE, vocab)
    checks.append(("1: a DECLARED FINDING gate's red is tallied, so the runner does not exit 1",
                   got == 0, f"rc={got}"))
    got, c, _h = planted(CLAIM, vocab)
    checks.append(("2: THE SAME GATE WITH `RED_IS` DELETED is charged -- otherwise the declaration "
                   "would be decoration and every red would pass",
                   got == 1 and c.get("checks/g.py", (None, None, None))[1] == "FAILURE",
                   f"rc={got} class={c.get('checks/g.py') and c['checks/g.py'][1]}"))
    got, c, _h = planted(NEVER_GREEN, vocab)
    checks.append(("3: an undeclared gate that has NEVER reached rc 0 is UNTAKEN and charged -- a "
                   "gate that has never agreed has nothing to have failed from",
                   got == 1 and c.get("checks/g.py", (None, None, None))[1] == "UNTAKEN",
                   f"rc={got} class={c.get('checks/g.py') and c['checks/g.py'][1]}"))
    got, c, h = planted(UNMAPPED_CLAIM, vocab)
    checks.append(("4a: a DECLARED FINDING gate that declares an exit code `gatekit` has no name for "
                   "is STILL CHARGED -- `RED_IS` is a claim about meaning, not about the NUMBER an "
                   "aggregator sums", got == 1 and h == ["checks/g.py"], f"rc={got} charged={h}"))
    got, c, h = planted(ALL_FIVE, vocab)
    checks.append(("4b/5: the SAME DECLARED FINDING gate spelling all FIVE codes the way `gatekit` "
                   "spells them is charged for nothing -- or 4a is a runner that charges every code",
                   got == 0 and h == [] and c["checks/g.py"][1] == "FINDING", f"rc={got} charged={h}"))

    print()
    for name, ok, obs in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {obs}")
    bad = sum(1 for c_ in checks if not c_[1])
    print(f"PLANTS: {'GREEN' if not bad else 'RED'} ({len(checks) - bad}/{len(checks)})")
    return 1 if (rc or bad) else 0


if __name__ == "__main__":
    with contextlib.suppress(KeyboardInterrupt):
        sys.exit(main())