#!/usr/bin/env python3
"""DISCOVER every module-scope refusal in the tree, then MEASURE which ones actually FIRE.

A refusal CALL SITE at module scope is a SHAPE. Whether it FIRES is a MEASUREMENT. Two of the
files the brief inherits have the module-scope SHAPE and their guard is FALSE, so they run; and
one of the eight has NO module-scope refusal at all and reaches PASS. **An armed refusal that does
not fire is not a refusal, and an instrument that reports the shape instead of the behaviour
reports an armed gun as a fired one.** So this file EXECUTES each candidate.

    .venv/bin/python .agents/slop/modulerefuse/discover.py

THE CLASSIFIER BUG THIS FILE ALREADY MADE ONCE, RECORDED BECAUSE IT WILL MAKE IT AGAIN.
Version one asked `ast.walk(stmt)` for refusal calls over every top-level statement, which has NO
NOTION OF SCOPE, so `checks/substrate.py:931` -- `if not files: return refuse(...)` INSIDE
`main()` -- counted as module scope, and the run reported an eighth gate whose green path is
unreachable. `--help` on that same file answers rc=0 and prints argparse's usage: it RUNS. **The
instrument reported a gate as structurally dead that was demonstrably alive, on the same tree, one
command apart.** A `def` boundary is the SUBJECT here, so it is excluded by construction: a refusal
is module-scope iff its line falls inside no function's span.
"""
import ast
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PY = ROOT / ".venv" / "bin" / "python"
HOMES = ("checks", "gates")
TIMEOUT = 90


def refuse_helpers(tree):
    """Functions whose NAME says they refuse -- `refuse*`. A shape, and the shape is admitted: the
    alternative is to call every `sys.exit(3)` a refusal, and `checks/sb-gate.sh`'s lesson is that
    a literal list rots. `exit(3|4|5)` is caught separately and needs no list at all."""
    return {n.name for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)
            and n.name.split("_")[0] in ("refuse", "refusal")}


def def_spans(tree):
    """Every function's `(first, last)` line span. `ast` has no parent links, so the scope of a
    node is answered by CONTAINMENT rather than by an attribute that does not exist."""
    return [(n.lineno, n.end_lineno or n.lineno)
            for n in ast.walk(tree)
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda))]


def refusal_sites(tree):
    """`(line, kind, in_a_def)` for every refusal call site in the file."""
    hl = refuse_helpers(tree)
    spans = def_spans(tree)
    out = []
    for n in ast.walk(tree):
        kind = None
        if isinstance(n, ast.Call):
            if isinstance(n.func, ast.Name) and n.func.id in hl:
                kind = n.func.id
            elif (isinstance(n.func, ast.Attribute) and n.func.attr == "exit" and n.args
                  and isinstance(n.args[0], ast.Constant) and n.args[0].value in (3, 4, 5)):
                kind = f"exit({n.args[0].value})"
        elif isinstance(n, ast.Raise) and isinstance(n.exc, ast.Call) \
                and getattr(n.exc.func, "id", "") == "SystemExit" and n.exc.args \
                and isinstance(n.exc.args[0], ast.Constant) \
                and n.exc.args[0].value in (3, 4, 5):
            kind = f"SystemExit({n.exc.args[0].value})"
        if kind:
            out.append((n.lineno, kind, any(lo <= n.lineno <= hi for lo, hi in spans)))
    return sorted(set(out))


def run(rel, argv):
    try:
        r = subprocess.run([str(PY), str(ROOT / rel), *argv], cwd=ROOT,
                           capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", ""
    err = [l for l in (r.stderr or "").splitlines() if l.strip()]
    return str(r.returncode), (err[0][:64] if err else "")


def main():
    found = []
    for home in HOMES:
        h = ROOT / home
        if not h.is_dir():
            continue
        for p in sorted(h.iterdir()):
            if p.suffix != ".py" or not p.is_file():
                continue
            try:
                tree = ast.parse(p.read_text(errors="replace"))
            except SyntaxError:
                continue
            if not refuse_helpers(tree) and not any(
                    k.startswith(("exit(", "SystemExit(")) for _l, k, _d in refusal_sites(tree)):
                continue
            sites = refusal_sites(tree)
            top = [(l, k) for l, k, d in sites if not d]
            if not top:
                continue
            rel = str(p.relative_to(ROOT))
            found.append((rel, top, sites, run(rel, []), run(rel, ["--help"])))

    print(f"DISCOVERED {len(found)} file(s) with a REFUSAL AT MODULE SCOPE "
          f"(AST over {'/'.join(HOMES)}/*.py, `def` spans excluded)\n")
    print(f"{'file':38} {'module-scope sites':30} {'no-argv':>8} {'--help':>7}  first stderr")
    firing, armed = [], []
    for rel, top, sites, base, hlp in found:
        s = ",".join(f"{l}:{k}" for l, k in top)
        tag = ""
        if base[0] == "3":
            firing.append(rel)
            tag = "FIRES"
        elif hlp[0] == "3":
            armed.append(rel)
            tag = "FIRES ONLY WITH --help"
        else:
            armed.append(rel)
            tag = "ARMED, NOT FIRING"
        print(f"{rel:38} {s:30} {base[0]:>8} {hlp[0]:>7}  {base[1] or hlp[1]}   [{tag}]")

    print(f"\nA GATE WHOSE GREEN PATH IS UNREACHABLE BY CONSTRUCTION "
          f"(refuses with NO argv): {len(firing)}")
    for r in firing:
        print(f"   {r}")
    print(f"\nARMED, NOT FIRING WITH NO argv: {len(armed)} -- the shape is there, the guard is "
          f"FALSE, so the process RUNS")
    for r in armed:
        print(f"   {r}")
    print(f"\nDENOMINATOR: files under {'/'.join(HOMES)}/*.py. BOTH ARE CORRECT FOR THIS SCOPE "
          f"AND THE\nNUMBER IS MEANINGLESS WITHOUT IT -- `.agents/slop/pairs` counted 65 live "
          f"shared lists WHOLE-TREE\non the same day, and `coindependent` counted 5 scoped to "
          f"these two homes. Neither is\nwrong; they are different populations.")
    return 0


if __name__ == "__main__":
    sys.exit(main())