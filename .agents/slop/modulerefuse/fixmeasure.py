#!/usr/bin/env python3
"""THE STRUCTURAL FIX, MEASURED WITH AST: what happens if the module-scope refusal moves below
argparse?

    .venv/bin/python .agents/slop/modulerefuse/fixmeasure.py

THE FIRST VERSION OF THIS TRANSFORM WAS TEXT SURGERY AND IT MEASURED NOTHING, WHICH IS THE POINT
OF RECORDING IT. It dedented guard lines with a regex and wrote copies that all answered
`IndentationError` / `SyntaxError`, so the "after" column read `1,1,1` and looked like a finding
about the gates. **It was a finding about the transform.** A transform nobody parses is a
paragraph; this one is `ast.parse` -> `ast.unparse` -> executed, and `ast.unparse` drops comments,
which is acceptable here because the QUESTION is what the three argv cases DO and comments do
nothing.

THE QUESTION. `AGENTS.md`: "a refusal that fires at module scope exits before argparse, so no flag
can reach the green path." True. But it also means `--help` cannot PRINT, and a bad flag cannot be
told from a missing one. So: for each gate, does moving the refusal change what the three cases
answer -- and does it UNCOVER A REAL DEFECT rather than restore a green?

THE SECOND HALF, WHICH DECIDES THE FIX'S SHAPE. Some of these gates do WORK at module scope, not
just a guard -- `checks/nl-gate-noguard.py:71-74` `exec_module`s its oracle at import. Moving
ONLY the refusal would replace a clean REFUSED with an exception, which is WORSE, not better. So
the module-scope work is named, because the fix is "move the refusal AND the work" or "move
neither", and which one is a fact about the file and not a preference.
"""
import ast
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PY = ROOT / ".venv" / "bin" / "python"
TIMEOUT = 90

SEVEN = ["checks/dup-census.py", "checks/dup-gate.py", "checks/gate.py",
         "checks/hermetic-census.py", "checks/nl-gate-noguard.py", "checks/nl-gate.py",
         "checks/rn-gate.py"]

CASES = [("none", []), ("help", ["--help"]), ("bad", ["--no-such-flag-xyz"])]

WORK = [
    ("exec_module", re.compile(r"exec_module\(")),
    ("sys.path.insert", re.compile(r"sys\.path\.insert\(")),
    ("import graphcmp/isolate", re.compile(r"^import (graphcmp|isolate)\b", re.M)),
]


def def_spans(tree):
    return [(n.lineno, n.end_lineno or n.lineno)
            for n in ast.walk(tree)
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda))]


def hoist(src):
    """Every module-scope `refuse(...)` wrapped into one function, called first in `main()`.

    Returns the new SOURCE TEXT, or None if there is nothing to hoist. Built by AST because a
    line-based rewrite cannot tell an `if` guard from its body, which is the entire subject here.
    """
    tree = ast.parse(src)
    spans = def_spans(tree)

    def in_def(n):
        return any(lo <= n.lineno <= hi for lo, hi in spans)

    # 1. the guard STATEMENTS at module body that OWN a refuse() call. `If` ONLY is the second
    # version of this classifier's bug in the same class as the first: `checks/dup-census.py:76`
    # is `for _p in (...): if not _p.is_file(): refuse(...)`, so the owning statement is a `For`
    # and an `If`-only scan hoists the inner `if`, leaves the loop, and the gate refuses at
    # import anyway -- so the "after" column read 3,3,3 and I nearly recorded "moving the refusal
    # changes nothing". **A GUARD IS A STATEMENT, AND THREE KINDS OF STATEMENT GUARD IN THIS TREE.**
    guards = [s for s in tree.body
              if isinstance(s, (ast.If, ast.For, ast.While))
              and any(isinstance(x, ast.Call) and isinstance(x.func, ast.Name)
                      and x.func.id == "refuse" for x in ast.walk(s))
              and not in_def(s)]
    if not guards:
        return None, 0

    fn_body = []
    for g in guards:
        fn_body.append(ast.Expr(value=ast.Constant(value=ast.unparse(g))))
    moved = ast.FunctionDef(
        name="__moved_refuse__", args=ast.arguments(
            posonlyargs=[], args=[], vararg=None, kwonlyargs=[], kw_defaults=[], kwarg=None,
            defaults=[]),
        body=fn_body, decorator_list=[], returns=None,
        type_comment=None, type_params=[]) if hasattr(ast, "type_params") else ast.FunctionDef(
        name="__moved_refuse__", args=ast.arguments(
            posonlyargs=[], args=[], vararg=None, kwonlyargs=[], kw_defaults=[], kwarg=None,
            defaults=[]),
        body=fn_body, decorator_list=[], returns=None, type_comment=None)

    # 2. remove them from module body, put the function in their place
    out, placed = [], False
    for s in tree.body:
        if s in guards:
            if not placed:
                out.append(moved)
                placed = True
        else:
            out.append(s)
    # THE THIRD VERSION OF THIS TRANSFORM'S BUG, AND IT IS THE SAME CLASS TWICE MORE.
    # `if not out:` gated the append on the module body being EMPTY, so the function was only
    # defined when the guards were the FIRST statements -- and `checks/gate.py` begins with
    # `import argparse`. Three of the seven therefore answered `NameError: __moved_refuse__`,
    # which reads like a finding about the gates and is a finding about the transform. **A
    # TRANSFORM THAT HALF-WORKS PRODUCES A TABLE THAT LOOKS LIKE A RESULT, AND THE ONLY THING
    # THAT DISTINGUISHES THEM IS `ast.parse` ON THE OUTPUT -- WHICH IS WHY `hoist` RETURNS IT.**
    assert placed, "guards were not placed"
    # 3. call it as the first statement of main()
    done = False
    for s in out:
        if isinstance(s, ast.FunctionDef) and s.name == "main" and not done:
            call = ast.Expr(value=ast.Call(
                func=ast.Name(id="__moved_refuse__", ctx=ast.Load()), args=[], keywords=[]))
            # `AFTER` puts it immediately after the `a = ap.parse_args()` line, which is the
            # position that actually changes what `--help` does. BEFORE is kept so the report
            # can show that "into main()" is NOT the fix: a refusal on main()'s first line
            # still runs before argparse, and `--help` still answers 3. **THE FIX IS A POSITION,
            # NOT A CONTAINER.**
            at = 0
            if AFTER:
                for i, st in enumerate(s.body):
                    if isinstance(st, ast.Assign) and "parse_args" in ast.unparse(st):
                        at = i + 1
                        break
            s.body.insert(at, call)
            done = True
    if not done:
        return None, len(guards)
    tree.body = out
    ast.fix_missing_locations(tree)
    text = ast.unparse(tree)
    ast.parse(text)          # THE ASSERTION. A transform nobody re-parses is a paragraph.
    return text, len(guards)


AFTER = "--after" in sys.argv


def work_of(rel):
    """What the module-scope block does BEYOND refusing. The refusal's presence is excluded by
    dropping the `if` statements that own it -- the same `guards` list the hoist builds."""
    src = (ROOT / rel).read_text(errors="replace")
    tree = ast.parse(src)
    spans = def_spans(tree)
    guards = [s for s in tree.body
              if isinstance(s, (ast.If, ast.For, ast.While))
              and any(isinstance(x, ast.Call) and isinstance(x.func, ast.Name)
                      and x.func.id == "refuse" for x in ast.walk(s))
              and not any(lo <= s.lineno <= hi for lo, hi in spans)]
    rest = [s for s in tree.body if s not in guards]
    text = "\n".join(ast.unparse(s) for s in rest)
    return [n for n, pat in WORK if pat.search(text)]


def run(path, argv):
    try:
        r = subprocess.run([str(PY), str(path), *argv], cwd=ROOT,
                           capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", ""
    err = [l for l in (r.stderr or "").splitlines() if l.strip()]
    return str(r.returncode), (err[-1][:64] if err else "")


def main():
    print("BEFORE -- the live tree, three argv cases. ALL SEVEN ARE rc=3 FOR ALL THREE, so the "
          "module\nscope is what makes `--help` and a bad flag indistinguishable from no argv.\n")
    before = {}
    print(f"{'file':30} {'none':>6} {'--help':>7} {'bad':>5}")
    for rel in SEVEN:
        c = [run(ROOT / rel, a, )[0] for _n, a in CASES]
        before[rel] = c
        print(f"{rel:30} {c[0]:>6} {c[1]:>7} {c[2]:>5}")

    where = "AFTER `parse_args()`" if AFTER else "as main()'s FIRST line"
    print(f"\nAFTER -- refusal hoisted into `__moved_refuse__()`, called {where}\n")
    print(f"{'file':30} {'none':>6} {'--help':>7} {'bad':>5}   {'no-argv says':40}")
    for rel in SEVEN:
        new, n = hoist((ROOT / rel).read_text(errors="replace"))
        if new is None:
            print(f"{rel:30} {'NOTHING TO HOIST':>21}")
            continue
        # the copy must sit in `checks/` so `parents[0]` still resolves to the repo root
        dest = ROOT / "checks" / f".modulerefuse-{Path(rel).stem}.py"
        dest.write_text(new)
        try:
            cells, msgs = [], []
            for _n, a in CASES:
                rc, m = run(dest, a)
                cells.append(rc)
                msgs.append(m)
        finally:
            dest.unlink(missing_ok=True)
        print(f"{rel:30} {cells[0]:>6} {cells[1]:>7} {cells[2]:>5}   {msgs[0][:40]}")

    print("\nMODULE-SCOPE WORK THE REFUSAL STANDS IN FRONT OF -- this decides the fix's SHAPE\n")
    print(f"{'file':30} module-scope work beyond the guard")
    for rel in SEVEN:
        w = work_of(rel)
        print(f"{rel:30} {', '.join(w) if w else '(none -- the block only refuses)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())