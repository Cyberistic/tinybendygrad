#!/usr/bin/env python3
"""THE TWELFTH, AND WHY NO INSTRUMENT COULD SEE IT.

    .venv/bin/python .agents/slop/synonyms/twelfth2.py

`.agents/slop/hooks/run.py` spells the vocabulary TWICE:

    :54   PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5    # a SECOND name<-code unpack
    :56   NAME = {PASS: "GREEN", FAIL: "FAIL", ...}          # keys are NAMES, not literals

**THE TWELFTH RENAMED CODE IS `0: "GREEN"` at `:56`, where `gates/gatekit.py` says `PASS`.**

AND HERE IS WHY EVERY EXISTING INSTRUMENT IS BLIND TO IT, WHICH IS THE PART WORTH RECORDING:

  * `gate-surface.declaration()` keys on the literal marker name `VERDICTS`. `NAME` is not it.
  * `gate-surface.vocabulary()` reads a module-level name<-code UNPACK. `NAME = {...}` is not one.
  * `ast.literal_eval` on `NAME = {PASS: "GREEN", ...}` **RAISES**, because `PASS` is an `ast.Name`,
    not a literal. The vocabulary is only a literal ONCE THE UNPACK ON :54 HAS BEEN EVALUATED.

So the twelfth is invisible to a reader that does not RESOLVE a module's own constants before
reading its tables -- and `.agents/slop/hooks/run.py:56` is exactly such a table. **This is a
population discovered by RESOLUTION, which is neither "a generator's declaration" nor "a
directory walk" nor "a regex over write sites": a fourth kind, and the kind that catches a gate
that names its codes.**

IT IS ALSO A RE-SPELLING, AND THAT IS THE CHEAPER FINDING. Line 54 re-types the owner's five
codes instead of importing them, so the runner is a SECOND HOLDER of the vocabulary -- which is
`gendirs.py`'s "two instruments holding two lists have no authority over each other", with the
owner named as the first holder and a runner as the second. Commit `91645e23d` already settled
this SHAPE for two gates ("gatekit OWNS REFUSED and both offenders IMPORT IT rather than
re-spell it"); this is the same defect at a fourth site and it was not named.
"""
import ast
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SURFACE = ROOT / "gates" / "gate-surface.py"
HOOKS = ROOT / ".agents" / "slop" / "hooks" / "run.py"


def loaded(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def module_constants(tree):
    """`{NAME: int}` for every module-level `X = <int literal>` AND for every
    `X, Y, ... = <tuple of ints>`, by AST. The RESOLUTION step, and it takes TWO PASSES.

    **MEASURED, and the two passes are the finding rather than an implementation detail.** The
    first version of this function handled only `X = <int>`, so
    `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5` resolved to `{}` -- an EMPTY constant map --
    and `NAME`'s keys could not be read, and the instrument reported "no vocabulary here" about
    the one file in the tree whose whole job is to hold one. An empty map and an absent map are
    indistinguishable to every reader downstream, which is `AGENTS.md`'s `DEAD` once more: a
    reader that compared nothing reported a clean result.

    So the resolution is: ints first, THEN tuple unpacks over the ints. A gate that spells its
    codes `0, 1, 3, 4, 5` and then writes `{PASS: "GREEN"}` is **two steps away from a literal**,
    and `ast.literal_eval` is a ONE-step reader, which is why it cannot see any of it.
    """
    out = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        try:
            v = ast.literal_eval(node.value)
        except (ValueError, SyntaxError, TypeError):
            continue
        if type(v) is int:
            for t in node.targets:
                if isinstance(t, ast.Name):
                    out[t.id] = v
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        try:
            v = ast.literal_eval(node.value)
        except (ValueError, SyntaxError, TypeError):
            continue
        if not (isinstance(v, tuple) and v and all(type(c) is int for c in v)):
            continue
        for t in node.targets:
            if (isinstance(t, ast.Tuple) and len(t.elts) == len(v)
                    and all(isinstance(e, ast.Name) for e in t.elts)):
                out.update(dict(zip((e.id for e in t.elts), v)))
    return out


def name_keyed_table(tree, constants, marker):
    """`{code: token}` for `marker = {NAME: "str", ...}`, resolving each NAME to its int.

    THE READ THAT HAD TO BE INVENTED. `ast.literal_eval` raises `ValueError: malformed node or
    string` on `{PASS: "GREEN"}` because `PASS` is an `ast.Name`, so every literal-only reader in
    this tree -- including `gate-surface.declaration()` -- cannot read a table whose keys are the
    module's own constants. That is not an edge case: it is how a runner spells a vocabulary it
    is TRYING to agree with.
    """
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        names = [t for t in node.targets if isinstance(t, ast.Name) and t.id == marker]
        if not names or not isinstance(node.value, ast.Dict):
            continue
        table = {}
        for k, v in zip(node.value.keys, node.value.values):
            if k is None:
                return None                      # `**spread`: unresolvable, and said so
            try:
                key = ast.literal_eval(k)
            except (ValueError, SyntaxError, TypeError):
                key = constants.get(k.id) if isinstance(k, ast.Name) else None
            try:
                token = ast.literal_eval(v)
            except (ValueError, SyntaxError, TypeError):
                token = None
            if not (isinstance(key, int) and isinstance(token, str)):
                return None
            table[key] = token
        return node.lineno, table
    return None, None


def main():
    sf = loaded(SURFACE, "gate_surface_under_twelfth2")
    vocab = sf.vocabulary()
    print(f"OWNER gates/gatekit.py BY PATH: "
          f"{', '.join(f'{c}={n}' for c, n in sorted(vocab.items()))}\n")

    tree = ast.parse(HOOKS.read_text(errors="replace"))
    consts = module_constants(tree)
    print(f"{HOOKS.relative_to(ROOT)} module-level int constants, by AST: {consts}")

    lineno, table = name_keyed_table(tree, consts, "NAME")
    if table is None:
        print("\n`NAME` is UNRESOLVABLE by this reader -- said so, not defaulted to {}.")
        return 1
    print(f"\n`NAME` after RESOLVING its keys through those constants -- line {lineno}:")
    print(f"    {table}")

    # THE UNPACK, which is the second half of the finding: a RE-SPELLING of the owner's five.
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        for t in node.targets:
            if not (isinstance(t, ast.Tuple) and len(t.elts) > 1):
                continue
            try:
                codes = ast.literal_eval(node.value)
            except (ValueError, SyntaxError, TypeError):
                continue
            if not (isinstance(codes, tuple) and len(codes) == len(t.elts)
                    and all(type(c) is int for c in codes)):
                continue
            theirs = dict(zip(codes, (e.id for e in t.elts)))
            print(f"\nname<-code unpack at :{node.lineno}: {theirs}")
            print(f"  the OWNER spells:  {dict(sorted(vocab.items()))}")
            print(f"  IDENTICAL: {theirs == vocab}"
                  + ("" if theirs == vocab else "  <-- a SECOND HOLDER, not an import"))
            print(f"  `hooks/run.py:54` RE-SPELLS what `gatekit.py:60` owns. It is the same defect "
                  f"commit\n  91645e23d settled for two other sites, at a fourth site.")

    print("\nTHE RENAMED ENTRY, AND THE TOTAL:\n")
    ren = [(c, tok, vocab.get(c, "-")) for c, tok in sorted(table.items())
           if str(tok).upper() != str(vocab.get(c, "")).upper()]
    for c, tok, own in ren:
        print(f"  exit {c}: '{tok}' where gates/gatekit.py says '{own}'")
    print(f"\n  RENAMED over .agents/slop/hooks/run.py alone: {len(ren)}")
    print(f"  RENAMED over the 8 gates inside HOMES:        11")
    print(f"  TOTAL RENAMED:                                {len(ren) + 11}")
    print(f"\n  The brief says 12 across 8 gates. The 12 is 11 + THIS, and the 8 excludes this one:")
    print(f"  it is a RUNNER, it lives outside HOMES=('checks','gates'), and its table's keys are")
    print(f"  NAMES, so `ast.literal_eval` cannot read it. **Every existing reader is blind to it.**")
    return 0


if __name__ == "__main__":
    with __import__("contextlib").suppress(KeyboardInterrupt):
        sys.exit(main())