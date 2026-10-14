#!/usr/bin/env python3
"""reach.py -- IS AN UNPLANTED VERDICT PLANTABLE BY ARGV, OR IS THE REFUSAL ABOVE THE PARSER?

`.agents/slop/zerogate/REPORT.md` measured the thing that decides whether a plant can exist at all:

    "EVERY ONE REFUSES AT MODULE SCOPE: the `refuse()` call sits *ABOVE* EVERY `argparse` parse
     (`nl-gate.py:81` vs `:51`). SO NO ARGV REACHES THEM -- there is no invocation, of any shape,
     that gets past the refusal."

This file asks that question of the DECLARED verdicts, by AST, for every gate that declares one.

NOTHING NEW IS BUILT HERE. The population is `gates/gates-pop.py:discover()` and the declaration is
`gates/gate-surface.py:declaration()`, BOTH LOADED BY PATH -- the tree already has one module per
question and a second copy of either is a contract with no generator (`AGENTS.md` doctrine 1). This
file adds a third ANSWER about each declared verdict, not a second way of asking.

    .venv/bin/python .agents/slop/plantthe46/reach.py          # the table
    .venv/bin/python .agents/slop/plantthe46/reach.py --rows   # machine rows

THE CLASSIFICATION, and it is decided by WHERE the gate can exit 3, never by whether it did:

    ABOVE-PARSER   a `sys.exit(3)` (or a `refuse()` that does) sits at MODULE scope, above every
                   `parse_args`. No argv of any shape reaches a verdict: the plant cannot exist, and
                   the fix is structural -- move the refusal below the parser -- or the verdict must
                   be declared UNREACHABLE.
    BELOW-PARSER   every `sys.exit(3)` is inside a function reached only after `parse_args`, so some
                   argv CAN move the gate. The verdict may or may not have a plant; that is a
                   separate measurement and `gates/gate-surface.py` is what makes it.

MODULE SCOPE IS MEASURED, NOT ASSUMED: a `sys.exit(3)` directly in `tree.body` is above the parser
by definition; one inside a `def` is below it only if that `def` is called from `main()` AFTER
`parse_args`, so the walk follows the call graph one level (`main` -> its callees) and anything it
cannot reach is reported as `UNKNOWN` rather than credited.
"""
import argparse
import ast
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def by_path(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def gates_pop():
    return by_path(ROOT / "gates" / "gates-pop.py", "gates_pop")


def gate_surface():
    return by_path(ROOT / "gates" / "gate-surface.py", "gate_surface")


# ---- the exit-3 sites, by AST --------------------------------------------------------
def _exit3_calls(node):
    """Every `sys.exit(<int literal 3>)` and every bare `refuse(...)` call in `node`'s subtree."""
    out = []
    for n in ast.walk(node):
        if not isinstance(n, ast.Call):
            continue
        f = n.func
        name = None
        if isinstance(f, ast.Attribute) and f.attr == "exit":
            name = "sys.exit"
        elif isinstance(f, ast.Name):
            name = f.id
        if name is None:
            continue
        if name == "sys.exit" and isinstance(n.args[0] if n.args else None, ast.Constant):
            if n.args[0].value == 3:
                out.append(n.lineno)
        elif name == "refuse":
            # `def refuse(*why): ... sys.exit(3)` -- credit the DEFINITION too, so a gate that
            # spells its refusal inline and a gate that spells it in a helper are one shape.
            out.append(n.lineno)
    return out


def classify(p):
    """`(verdicts, plants, note, where)` for one declaring gate.

    `where` maps exit code -> `ABOVE-PARSER` | `BELOW-PARSER` | `NO-SITE` | `UNKNOWN`, computed
    from the SOURCE, never from a run: a run says which code fired today, not which argv could.
    """
    tree = ast.parse(p.read_text(errors="replace"))
    module_exits = _exit3_calls(ast.Module(body=tree.body, type_ignores=[]))

    # `main()` and everything it calls, so a `refuse()` in a helper counts as below the parser only
    # when the helper is actually reachable from the entry point.
    funcs = {n.name: n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
    reached, frontier = set(), ["main"]
    while frontier:
        name = frontier.pop()
        if name in reached or name not in funcs:
            continue
        reached.add(name)
        for n in ast.walk(funcs[name]):
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in funcs:
                frontier.append(n.func.id)
    fn_exits = {n: _exit3_calls(f) for n, f in funcs.items()}
    below = sorted(x for name in reached for x in fn_exits[name])

    parser_lines = sorted(n.lineno for n in ast.walk(tree)
                          if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                          and n.func.attr == "parse_args")

    surf = gate_surface()
    verdicts, plants, note = surf.declaration(p)
    if verdicts is None:
        return None, None, note, {}
    where = {}
    for rc in verdicts:
        if rc == 3:
            if module_exits:
                where[rc] = "ABOVE-PARSER"
            elif below:
                where[rc] = "BELOW-PARSER"
            elif fn_exits:
                where[rc] = "UNKNOWN"
            else:
                where[rc] = "NO-SITE"
        else:
            where[rc] = "BELOW-PARSER" if parser_lines or reached else "NO-SITE"
    return dict(verdicts), dict(plants or {}), note, where


def main():
    ap = argparse.ArgumentParser(prog="reach.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rows", action="store_true", help="machine rows")
    a = ap.parse_args()

    gp = gates_pop()
    entries, libs = gp.discover(ROOT)
    rows = []
    for p in entries:
        if p.suffix != ".py":
            continue
        verdicts, plants, note, where = classify(p)
        if verdicts is None:
            continue
        for rc in verdicts:
            has_plant = rc in plants
            rows.append((str(p.relative_to(ROOT)), rc, verdicts[rc], where.get(rc, "?"),
                         "yes" if has_plant else "NO"))
    if a.rows:
        for r in rows:
            print("\t".join(str(x) for x in r))
        return 0

    print(f"REACH -- {len(entries)} entry points discovered via `gates/gates-pop.py:discover()`, "
          f"{len(rows)} DECLARED\nverdicts over {len({r[0] for r in rows})} declaring gate(s). "
          f"Classification is from the SOURCE AST:\n  ABOVE-PARSER  a `sys.exit(3)` sits at module "
          f"scope, above every `parse_args` -- NO argv of any shape reaches a verdict.\n")
    w = max(len(r[0]) for r in rows)
    for rel, rc, tok, where, has in rows:
        flag = "  " if has == "yes" else "->"
        print(f"{flag} {rel:{w}}  {rc} {tok:<9} {where}")
    above = [r for r in rows if r[3] == "ABOVE-PARSER"]
    noplant = [r for r in rows if r[4] == "NO"]
    blocked = [r for r in noplant if r[3] == "ABOVE-PARSER"]
    print(f"\nREACH: {len(rows)} declared, {len(rows) - len(noplant)} planted, "
          f"{len(noplant)} unplanted\n  {len(above)} verdict(s) sit ABOVE-PARSER; "
          f"{len(blocked)} of the {len(noplant)} unplanted are BLOCKED BY IT\n"
          f"  -> the plantable remainder is {len(noplant) - len(blocked)}")
    for rel, rc, tok, where, has in blocked:
        print(f"  BLOCKED {rel} {rc} {tok}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
