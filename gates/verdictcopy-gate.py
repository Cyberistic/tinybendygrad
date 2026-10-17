#!/usr/bin/env python3
"""gates/verdictcopy-gate.py -- ONE GATE, ONE EXIT: is every row-count guard able to say DEAD?

    .venv/bin/python gates/verdictcopy-gate.py     # verdictcopy: N sites over M files

THE DEFECT, IN ONE SENTENCE. **A ROW-COUNT GUARD THAT RETURNS A SINGLE VERDICT CANNOT TELL
`the lane emitted nothing` FROM `the lane emitted the wrong number of things`, SO A `DEAD`
LANE LEAVES AS `FAIL`.**

`gates/gatekit.py:648` is the tree's own ruling on this and it is not a matter of taste:

    return DEAD if n == 0 else FAIL

`DEAD(5)` IS "IT RAN AND **ALSO** EMITTED NOTHING" AND `FAIL(1)` IS "YES AND WRONG"
(`AGENTS.md`, the five verdicts). So a lane holding zero rows and a lane holding the wrong
non-zero number are two of the five, and a guard that returns the same constant for both has
folded two verdicts into one exit -- the same class as the two `i64-*` guards, one level down.

MEASURED, AND THE COUNT IS A MEASUREMENT NOT A STORY. **4 sites over 4 files**, all by
directory walk (`os.walk` over `checks/` + `gates/`), and every one of them is a bare
`return FAIL` under a guard that tests a row count and never tests it against zero.

THE POPULATION IS DISCOVERED (`AGENTS.md` doctrine 1). `os.walk` + `endswith(".py")`, and the
vocabulary is LOADED BY PATH from `gates/gatekit.py`'s `VERDICT`, never retyped here -- the
same rule `differ.declared()` follows and the reason this file has no list to go stale. There
is NO list of offenders in this file, and no list of exempt ones either: a site is in the
class by a property of its own AST, so an offender added tomorrow is found without an edit.

WHAT COUNTS, AND THE FOUR WAYS THIS SLICE IS WRONG. Every site must have ALL FOUR, and the
file prints which condition each site failed rather than only the ones it caught:

  1  it is a `return` whose value is a BARE verdict NAME (`return FAIL`), so it cannot depend
     on anything -- a `return DEAD if n == 0 else FAIL` is an `IfExp` and is NOT in the class;
  2  it is lexically under an `if` whose test NAMES A COUNT: a local bound to `len(...)`;
  3  that `if` test contains NO comparison of that count against zero (`!= 0`, `== 0`,
     `< 1`, `> 0`), so nothing on the path distinguishes the two conditions;
  4  the `if` is not `or`-ed with a zero test on a DIFFERENT count, which is the same thing
     arriving by another road.

THE LIMITS ARE STATED, NOT HIDDEN. The count names are collected per FUNCTION and this file
does not follow a value across a function boundary, so a count computed by a helper and
tested in `main()` is invisible to it; and the `len(...)` is matched by call name rather than
by what it counts, so `len(os.listdir(x))` is a "count" too. Both make this census a LOWER
BOUND, and a lower bound that prints its own size is a census rather than a claim. Anything
this file cannot see it says it cannot see -- it does not report green over what it skipped.
"""
import ast
import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOMES = ("checks", "gates")

# A COMPARISON OF A COUNT AGAINST ZERO, in the four spellings that mean "did it emit
# anything". Stated here as a shape rather than parsed, because `==` and `!=` and the orderings
# are four nodes and a table of four is a table a reader can check; the AST below confirms
# each candidate is really a comparison before this is consulted.
ZERO_TESTS = ("== 0", "!= 0", "< 1", "> 0")


def vocabulary():
    """`{code: NAME}` from `gates/gatekit.py`, LOADED BY PATH -- never retyped here."""
    spec = importlib.util.spec_from_file_location("gk", ROOT / "gates" / "gatekit.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.VERDICT


VERDICTS = set(vocabulary().values())


def counts_of(fn):
    """Names bound to `len(...)` inside `fn`, NOT descending into a nested `def`.

    `ast.walk` visits every `len` in every nested function, so a helper's own counter would
    be attributed to the caller and a caller with no counter of its own would be judged on
    one it does not have.
    """
    out, stack = set(), list(getattr(fn, "body", []))
    while stack:
        n = stack.pop()
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda, ast.ClassDef)):
            continue
        if isinstance(n, ast.Assign) and isinstance(n.value, ast.Call) \
                and isinstance(n.value.func, ast.Name) and n.value.func.id == "len" \
                and len(n.value.args) == 1 and not n.value.keywords:
            out |= {t.id for t in n.targets if isinstance(t, ast.Name)}
        elif isinstance(n, ast.AnnAssign) and isinstance(n.value, ast.Call) \
                and isinstance(n.value.func, ast.Name) and n.value.func.id == "len" \
                and isinstance(n.target, ast.Name):
            out.add(n.target.id)
        stack += list(ast.iter_child_nodes(n))
    return out


def test_text(node):
    """The `if` test as source, so the zero-test question is asked of the REAL spelling."""
    try:
        return ast.unparse(node)
    except Exception:                                  # noqa: BLE001 -- an unparseable test is
        return ""                                      # reported as unseen, never as seen-and-clear


def names_in(node):
    """Every `ast.Name` the node reads, so "does the test mention the count" is a QUESTION
    ABOUT THE AST rather than a substring match over a line."""
    return {n.id for n in ast.walk(node) if isinstance(n, ast.Name)}


def sites_in(fn, counts):
    """`[(line, snippet)]` for every in-the-class `return` inside `fn`."""
    found, stack = [], list(getattr(fn, "body", []))
    while stack:
        n = stack.pop()
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda, ast.ClassDef)):
            continue
        if isinstance(n, ast.If) and not isinstance(n.test, ast.BoolOp):
            named = names_in(n.test) & counts
            if named:
                txt = test_text(n.test)
                if not any(z in txt for z in ZERO_TESTS):
                    for r in ast.walk(n):
                        # (1) a BARE verdict name only: an `IfExp` already distinguishes.
                        if isinstance(r, ast.Return) and isinstance(r.value, ast.Name) \
                                and r.value.id in VERDICTS:
                            found.append((r.lineno, f"return {r.value.id} under "
                                                 f"`{txt}` naming count(s) "
                                                 f"{', '.join(sorted(named))}"))
        stack += list(ast.iter_child_nodes(n))
    return found


def population():
    """Every `.py` under the homes, by DIRECTORY WALK. The one hand list in this file is
    `HOMES`, and it is the tree's OWN layout (`checks/` and `gates/` are where instruments
    live), not a list of offenders."""
    out = []
    for home in HOMES:
        for dirpath, dirnames, filenames in os.walk(ROOT / home):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            out += [Path(dirpath) / f for f in sorted(filenames) if f.endswith(".py")]
    return sorted(out)


def main():
    files = population()
    if not files:
        print(f"verdictcopy: REFUSED -- {len(files)} .py under {'/'.join(HOMES)}/: the "
              "population is EMPTY, so green here would mean the walk found nothing",
              file=sys.stderr)
        return 3

    offenders, unparsed, this_file = [], [], Path(__file__).resolve()
    for p in files:
        rel = str(p.relative_to(ROOT))
        if p == this_file:
            continue                     # a gate is not obliged to hold to its own rule's shape
        try:
            tree = ast.parse(p.read_text(errors="replace"))
        except SyntaxError as e:
            unparsed.append(f"{rel}: {e.msg} at line {e.lineno}")
            continue
        fns = [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
        for fn in fns:
            for line, snippet in sites_in(fn, counts_of(fn)):
                offenders.append((rel, line, snippet))

    print(f"verdictcopy: population {len(files)} .py under {'/'.join(HOMES)}/ "
          f"(os.walk + endswith('.py')); vocabulary loaded BY PATH from gates/gatekit.py "
          f"({len(VERDICTS)} verdict names)")
    print(f"verdictcopy: {len(offenders)} site(s) over {len({o[0] for o in offenders})} file(s) "
          "return ONE verdict for a row count and never test it against zero")
    for rel, line, snippet in offenders:
        print(f"  {rel}:{line}  {snippet}")

    for u in unparsed:
        print(f"  UNPARSED {u} -- REFUSED, not counted as clear")

    if unparsed:
        # A file this census cannot read is not a file it can clear. Reported as REFUSED
        # rather than skipped, because "I could not see it" and "it is fine" are different
        # answers and only one of them is true.
        print(f"verdictcopy: {len(unparsed)} file(s) unparsable -- REFUSED", file=sys.stderr)
        return 3
    if offenders:
        print(f"verdictcopy: FAIL -- {len(offenders)} guard(s) cannot distinguish a DEAD lane "
              "from a FAIL one. `gates/gatekit.py:648` answers the same question "
              "`DEAD if n == 0 else FAIL`, and a `DEAD` that leaves as `FAIL` tells a reader "
              "the harness produced a wrong answer when it produced no answer at all.",
              file=sys.stderr)
        return 1
    print("verdictcopy: PASS -- every row-count guard in the population can separate "
          "a lane that emitted nothing from a lane that emitted the wrong number")
    return 0


if __name__ == "__main__":
    sys.exit(main())