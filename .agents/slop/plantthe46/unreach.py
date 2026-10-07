#!/usr/bin/env python3
"""WHICH DECLARED VERDICTS A PLANT CANNOT REACH, AND WHY -- BY AST, NOT BY RUNNING ANYTHING.

    .venv/bin/python .agents/slop/plantthe46/unreach.py            # the table
    .venv/bin/python .agents/slop/plantthe46/unreach.py --rows     # TSV

THE QUESTION. `gates/gate-surface.py` makes a DECLARED verdict with no PLANT red and named. That
instrument needs a plant to be a plant. **`zerogate` found the state in which a plant is impossible
-- a refusal at MODULE SCOPE, above every `argparse`, so no argv of any shape gets past it -- and
named the class without separating it from the merely-unplanted.** This file separates them, and it
separates them WITHOUT RUNNING A GATE, because running is what started `bend`.

WHAT IT READS. `gates/gate-surface.py:declaration()` -- IMPORTED BY PATH, the tree's own declaration
reader, so this is the SECOND CONSUMER OF ONE READER and not a fourth AST walk of `VERDICTS`. What
this file adds is the line geometry: at what line does the gate exit at module scope, and at what
line does it parse argv. **A verdict is PLANTABLE only if the module survives to the parser.** A
`sys.exit(3)` on line 81 with `parse_args` on line 140 means every declared verdict other than the
refusal is UNREACHABLE BY CONSTRUCTION: it is not unplanted, it is unplantABLE.

WHAT IT CANNOT SEE, AND SAYS SO. Whether a refusal FIRES is a property of the FILESYSTEM, not of
the source -- `zerogate/REPORT.md` §7a records a static rule of exactly this shape running `bend`
once, because a module-scope `sys.exit(3)` makes everything after it unreachable and "names bend"
and "can reach bend" are different claims. So this file classifies REACHABILITY (a property of the
program text) and never CLASSIFIES WHETHER THE REFUSAL FIRES. The firing is measured separately, by
execution, in `plant.py`, and the two are kept apart on purpose.
"""
import argparse
import ast
import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
GS = ROOT / "gates" / "gate-surface.py"


def load_gate_surface():
    """`gates/gate-surface.py` BY PATH. Its `declaration()` is the tree's reader of `VERDICTS`;
    importing a gate RUNS it, and importing a gate by NAME would let any file in the tree shadow it."""
    spec = importlib.util.spec_from_file_location("gate_surface", GS)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GSMOD = load_gate_surface()

EXITCALLS = (ast.Call,)
TERMINALS = {"exit": "sys.exit", "SystemExit": "raise SystemExit", "quit": "sys.quit"}


def _exit_call(node):
    """True if `node` is a call that terminates the process at import time.

    `sys.exit(3)`, `raise SystemExit(3)`, `exit(3)`. A bare `sys.exit(main())` is counted as an exit
    TOO, but with an UNKNOWN code -- it is an exit whose code is computed, which is exactly the case
    `coindependent/vocab.py` documented itself blind to (its declared column is a lower bound)."""
    if not isinstance(node, ast.Call):
        return None
    f = node.func
    if isinstance(f, ast.Attribute) and f.attr in ("exit", "quit") and \
            isinstance(f.value, ast.Name) and f.value.id in ("sys", "builtins"):
        arg = node.args[0] if node.args else None
        return ("attribute", f.attr, arg)
    if isinstance(f, ast.Name) and f.id in ("exit", "quit"):
        arg = node.args[0] if node.args else None
        return ("name", f.id, arg)
    return None


def _int_of(node):
    """The integer literal an exit carries, or None when it is computed."""
    if isinstance(node, ast.Constant) and isinstance(node.value, int):
        return node.value
    return None


def _is_dunder_name(node):
    return (isinstance(node, ast.Name) and node.id == "__name__") or \
           (isinstance(node, ast.Constant) and node.value == "__name__")


def _is_main(node):
    return (isinstance(node, ast.Constant) and node.value == "__main__") or \
           (isinstance(node, ast.Name) and node.id == "__main__")


def _exiting_helpers(tree):
    """The names of this file's OWN helpers that terminate the process, DERIVED not assumed.

    `refuse(...)` is this tree's refusal idiom (`gates/gatekit.py:59`, `checks/abi_gate.py`) and it
    is a CALL, not an exit, so a scanner that only knows `sys.exit` sees a clean module. Whether
    `refuse` exits is a property of its own body, so it is read: a def whose subtree contains a
    `sys.exit`/`raise SystemExit` is an exiting helper. Nothing is listed.
    """
    out = set()
    for n in ast.walk(tree):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if any(_exit_call(x) for x in ast.walk(n)):
                out.add(n.name)
    return out


def geometry(src):
    """`(guard_line, module_exits, exiting_helper_calls, first_parse_args)` for one gate's text.

    MODULE SCOPE is `tree.body` plus the bodies of `if` statements at module scope -- NOT function
    bodies, because a function body does not run at import. The parser is looked for EVERYWHERE,
    because the question is whether the module survives long enough to reach it, and `parse_args`
    lives inside `main()` in every gate in this tree."""
    tree = ast.parse(src)
    exiting = _exiting_helpers(tree)

    def walk(stmts):
        """Every EXPRESSION that runs at module import, in source order.

        A module-level `refuse(...)` is an `ast.Expr` whose `.value` is the call -- which is why a
        scanner that only inspects the statements it is handed sees a clean module. `def`/`class`
        bodies do NOT run at import and are skipped; every other statement form executes, so its
        sub-statements are followed (`if`/`for`/`while`/`with`/`try`/`match`)."""
        for st in stmts:
            if isinstance(st, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                continue
            if isinstance(st, ast.Expr):
                yield st.value
            elif isinstance(st, ast.If):
                yield from walk(st.body); yield from walk(st.orelse)
            elif isinstance(st, (ast.For, ast.AsyncFor, ast.While)):
                yield from walk(st.body); yield from walk(st.orelse)
            elif isinstance(st, (ast.With, ast.AsyncWith)):
                yield from walk(st.body)
            elif isinstance(st, ast.Try):
                yield from walk(st.body); yield from walk(st.orelse); yield from walk(st.finalbody)
                for h in st.handlers:
                    yield from walk(h.body)
            elif isinstance(st, ast.Match):
                for c in st.cases:
                    yield from walk(c.body)
            elif isinstance(st, (ast.Raise, ast.Assign, ast.AnnAssign, ast.AugAssign,
                                 ast.Return, ast.Assert, ast.Delete, ast.Global, ast.Nonlocal)):
                yield st

    guard = None
    for st in tree.body:
        if isinstance(st, ast.If) and isinstance(st.test, ast.Compare) and \
                _is_dunder_name(st.test.left) and any(_is_main(c) for c in st.test.comparators):
            guard = st.lineno
            break
    module_exits = []
    for n in walk(tree.body):
        if isinstance(n, ast.Raise) and n.exc:
            c = _exit_call(n.exc)
            if c:
                module_exits.append((n.lineno, "raise SystemExit", _int_of(c[2])))
        c = _exit_call(n)
        if c:
            module_exits.append((n.lineno, f"{c[0]}:{c[1]}", _int_of(c[2])))
            continue
        if isinstance(n, ast.Call):
            fn = n.func
            name = fn.attr if isinstance(fn, ast.Attribute) else getattr(fn, "id", None)
            if name in exiting:
                module_exits.append((n.lineno, f"{name}()", None))
    parses = sorted(n.lineno for n in ast.walk(tree) if isinstance(n, ast.Call) and
                    (getattr(n.func, "attr", None) or getattr(n.func, "id", None))
                    in ("parse_args", "parse_known_args"))
    argv = sorted(n.lineno for n in ast.walk(tree) if isinstance(n, ast.Attribute)
                 and n.attr == "argv" and isinstance(n.value, ast.Name) and n.value.id == "sys")
    return guard, sorted(module_exits), sorted(parses), (argv[0] if argv else None)


def describe(src):
    """The one class name, and the geometry that produced it.

    `GUARDED` IS THE NORMAL CASE and it is reached for a reason worth stating: `sys.exit(main())`
    INSIDE the `if __name__` block is not a module-scope refusal at all, it is how every gate in
    this tree ends. Only an exit whose line is ABOVE the guard can fire before the program has read
    an argument, and only such an exit makes a declared verdict unplantable by argv.
    """
    guard, exits, parses, argv = geometry(src)
    first_exit = exits[0] if exits else None
    first_parse = parses[0] if parses else None
    argv_line = min([x for x in (first_parse, argv) if x is not None], default=None)
    if first_exit is None:
        return "GUARDED-OR-NONE", guard, first_exit, argv_line
    if guard is not None and first_exit[0] >= guard:
        return "GUARDED", guard, first_exit, argv_line
    if argv_line is None:
        return "REFUSAL-NO-ARGV", guard, first_exit, argv_line
    if first_exit[0] < argv_line:
        return "REFUSAL-ABOVE-ARGV", guard, first_exit, argv_line
    return "REFUSAL-ABOVE-GUARD", guard, first_exit, argv_line


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", action="store_true")
    a = ap.parse_args()
    out = []
    for p in sorted((ROOT / "gates").rglob("*.py")) + sorted((ROOT / "checks").rglob("*.py")):
        rel = p.relative_to(ROOT)
        verdicts, plants, red_is, note = GSMOD.declaration(p)
        if verdicts is None:
            continue
        verdicts, plants = dict(verdicts), dict(plants or {})
        try:
            state, guard, first_exit, first_parse = describe(p.read_text(errors="replace"))
        except SyntaxError as e:
            out.append((str(rel), state := "UNPARSEABLE", len(verdicts), len(plants),
                        len(verdicts) - len(plants), str(guard), str(first_exit), str(first_parse), note))
            continue
        unplanted = [rc for rc in verdicts if rc not in plants]
        out.append((str(rel), state, len(verdicts), len(plants), len(unplanted),
                    str(guard), f"{first_exit[0]}:{first_exit[1]}={first_exit[2]}" if first_exit else "-",
                    str(first_parse) if first_parse else "-",
                    ",".join(str(x) for x in sorted(unplanted))))
    if a.rows:
        print("gate\tgeometry\tdeclared\tplanted\tunplanted\tguard\tfirst_module_exit\tfirst_parse_args\tunplanted_rcs")
        for r in out:
            print("\t".join(str(x) for x in r))
        return 0
    w = max((len(r[0]) for r in out), default=10)
    for r in out:
        print(f"{r[0]:{w}}  {r[1]:22} declared={r[2]} planted={r[3]} unplanted={r[4]}  "
              f"guard@{r[5]} exit@{r[6]} argv@{r[7]}  [{r[8]}]")
    hard = [r for r in out if r[1] == "REFUSAL-ABOVE-ARGV"]
    print(f"\nREFUSAL-ABOVE-ARGV: {len(hard)} of {len(out)} declaring gates")
    for r in hard:
        print(f"  {r[0]}: exit@{r[6]} argv@{r[7]} guard@{r[5]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())