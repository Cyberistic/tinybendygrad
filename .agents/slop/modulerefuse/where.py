#!/usr/bin/env python3
"""WHERE does each candidate refuse? AST, not prose, not the message.

The question is answered by finding the CALL SITE of the refusal helper and asking whether it is
at module body level or inside a function. A refusal at module scope runs during IMPORT, so no
argv has been read yet -- argparse lives under `if __name__ == '__main__'`, so a module-scope
refusal makes every flag unreachable BY CONSTRUCTION, not by difficulty.

    .venv/bin/python .agents/slop/modulerefuse/where.py
"""
import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

CANDIDATES = [
    "checks/gate.py", "checks/nl-gate.py", "checks/nl-gate-noguard.py",
    "checks/dup-gate.py", "checks/dup-census.py", "checks/rn-gate.py",
    "checks/hermetic-census.py", "checks/git-index-guard.py",
    "checks/norm_check.py", "checks/oracle_f64.py",
]

# WHAT COUNTS AS A REFUSAL. A call to a `refuse`-named helper, a `sys.exit(<int>)` at a site whose
# line text says REFUSED, or a `SystemExit(3|4|5)`. NOT a `sys.exit(msg)` -- that is a crash that
# happens to carry a string, and it exits 1.
REFUSE_NAME = re.compile(r"^(refuse|_refuse|die_refuse|guard_refuse)\b") if False else None


def exit_codes(tree):
    """Every `sys.exit(<int literal>)` / `raise SystemExit(<int literal>)` with its lineno."""
    out = []
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.args:
            a = n.args[0]
            if n.func.attr == "exit" and isinstance(a, ast.Constant) and isinstance(a.value, int):
                out.append((n.lineno, a.value))
        elif isinstance(n, ast.Raise) and isinstance(n.exc, ast.Call):
            fn = n.exc.func
            name = getattr(fn, "id", getattr(fn, "attr", ""))
            if name == "SystemExit" and n.exc.args and isinstance(n.exc.args[0], ast.Constant) \
                    and isinstance(n.exc.args[0].value, int):
                out.append((n.lineno, n.exc.args[0].value))
    return out


def main():
    for rel in CANDIDATES:
        p = ROOT / rel
        src = p.read_text(errors="replace")
        tree = ast.parse(src)
        # WHICH functions could contain a refusal, and the set of REFUSED helper names.
        func_lines = {n.name: (n.lineno, n.end_lineno) for n in ast.walk(tree)
                      if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
        helpers = {n.name for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)
                   and n.name.split("_")[0] in ("refuse", "refusal")}

        sites = []
        for n in ast.walk(tree):
            if not isinstance(n, ast.Expr):
                continue
            v = n.value
            hit = None
            if isinstance(v, ast.Call) and isinstance(v.func, ast.Name) and v.func.id in helpers:
                hit = v.func.id
            elif (isinstance(v, ast.Call) and isinstance(v.func, ast.Attribute)
                  and v.func.attr == "exit" and v.args
                  and isinstance(v.args[0], ast.Constant)
                  and v.args[0].value in (3, 4, 5)):
                hit = f"exit({v.args[0].value})"
            elif isinstance(v, ast.Call) and isinstance(v.func, ast.Name) and v.func.id == "raise_Sysexit":
                hit = "raise_Sysexit"
            if hit:
                owner = next((nm for nm, (lo, hi) in func_lines.items() if lo <= n.lineno <= hi), None)
                sites.append((n.lineno, hit, owner or "MODULE"))
            # an `if ...: sys.exit(3)` at body level is an `If`, not an `Expr`
            if isinstance(v, ast.If):
                for sub in ast.walk(v):
                    if (isinstance(sub, ast.Call) and isinstance(sub.func, ast.Attribute)
                            and sub.func.attr == "exit" and sub.args
                            and isinstance(sub.args[0], ast.Constant)
                            and sub.args[0].value in (3, 4, 5)):
                        owner = next((nm for nm, (lo, hi) in func_lines.items()
                                      if lo <= sub.lineno <= hi), None)
                        sites.append((sub.lineno, f"exit({sub.args[0].value})", owner or "MODULE"))

        mods = sorted(s for s in sites if s[2] == "MODULE")
        inside = sorted(s for s in sites if s[2] != "MODULE")
        argparse_line = next((n.lineno for n in ast.walk(tree)
                              if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                              and n.func.attr == "parse_args"), None)
        print(f"{rel}")
        print(f"   argparse.parse_args at : {argparse_line}")
        print(f"   MODULE-scope refusals  : {mods if mods else 'NONE'}")
        print(f"   inside main()/other   : {inside if inside else 'NONE'}")
        print(f"   VERDICT               : "
              f"{'MODULE-SCOPE -- no argv can reach a green path' if mods else 'INSIDE main()'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())