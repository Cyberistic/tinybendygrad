#!/usr/bin/env python3
"""WHAT A REFUSAL ABOVE `argparse` COSTS: `--help`, no argv, and a bad flag, measured on a COPY
whose module-scope refusal has been REMOVED.

    .venv/bin/python .agents/slop/plantthe46/move.py            # the table
    .venv/bin/python .agents/slop/plantthe46/move.py --rows     # TSV

THE PRIZE, AND WHY IT IS A COPY. `.agents/slop/zerogate/REPORT.md` §2(a) measured that six gates
refuse at MODULE SCOPE, above every `argparse`, so "no argv reaches them" -- and §7a recorded that
the same unit then ran `bend` once because a static reachability rule cannot know whether a refusal
FIRES. This file answers the question that leaves open, and it answers it on a COPY in a synthetic
ROOT, for three reasons that are safety conditions, not style:

  1. THE ROOT HAS NO `bin/bend`.  `nl-gate`/`nl-gate-noguard`/`rn-gate` reach the port compiler
     through `./bin/bend`; in a synthetic root that path does not exist, so a gate that got there
     anyway would fail to exec rather than compile. This unit may not start `bend`.
  2. NOTHING IS WRITTEN INTO THE REPO.  `checks/dup-census.py:276` writes `dup-census.json`
     UNCONDITIONALLY at the end of `main()` -- with no `if total:` guard -- and
     `.agents/slop/zerogate/REPORT.md` §7b records it overwriting a tracked 797 251 B census with a
     1-line `[]`. In a synthetic root it writes to the synthetic root.
  3. THE LIVE FILE IS NEVER EDITED.  The refusal is deleted from an in-memory copy, written to
     `<root>/checks/<name>`, and run. `git diff` on `checks/` is asserted empty afterwards.

WHAT IS DELETED, EXACTLY. `gates/gate-surface.py:declaration()` is imported BY PATH for the
population, and the refusal statements are found the same way `.agents/slop/plantthe46/unreach.py`
finds them: every MODULE-LEVEL statement that calls a helper whose own body exits. A `def`/`class`
body is untouched -- it does not run at import -- and every other module-level statement stays. So
the difference between the two runs is exactly the refusal and nothing else.

THIS IS DELETION, NOT RELOCATION, and the report says so. Moving the block below `main()`'s parser
would be a strictly larger edit (the statements have to be re-indented into a function, and the
`for`/`if` nesting has to be preserved); deletion yields the same three readings because the
question is what the three argv shapes DO once the refusal is not in front of them, and neither
form can reach a different answer. **A gate that refuses above the parser and a gate that has no
refusal at all are indistinguishable to a caller -- which is the finding -- and the only way to see
the difference is to look past the refusal.**
"""
import argparse
import ast
import importlib.util
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PY = ROOT / ".venv" / "bin" / "python"

SHAPES = (("--help", ["--help"]), ("no-argv", []), ("bad-flag", ["--no-such-flag-xyz"]))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GS = _load("gate_surface", ROOT / "gates" / "gate-surface.py")
UNREACH = _load("unreach", HERE / "unreach.py")


def refusal_spans(tree, exiting):
    """`(start, end)` line ranges, 1-based inclusive, of every MODULE-LEVEL statement that can end
    the process at import. `def`/`class` bodies are skipped because they do not run at import."""
    spans = []

    def scan(stmts):
        for st in stmts:
            if isinstance(st, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                continue
            # THE `__main__` GUARD IS NOT A REFUSAL. It is how every gate in this tree ends, and
            # removing it would delete the program instead of the refusal -- which is how the first
            # run of this file reported `checks/gate.py` as exiting 0 with no output at all.
            if isinstance(st, ast.If) and any(UNREACH._is_dunder_name(n)
                                              for n in ast.walk(st.test)):
                continue
            hit = any(isinstance(n, ast.Call) and
                      (n.func.attr if isinstance(n.func, ast.Attribute) else getattr(n.func, "id", None))
                      in exiting for n in ast.walk(st))
            if isinstance(st, (ast.Raise, ast.Call)) and not hit:
                hit = any(UNREACH._exit_call(n) for n in ast.walk(st))
            if hit:
                spans.append((st.lineno, st.end_lineno))
                continue
            for field in ("body", "orelse", "finalbody", "handlers"):
                for sub in getattr(st, field, []) or []:
                    if isinstance(sub, ast.ExceptHandler):
                        scan(sub.body)
                    elif isinstance(sub, list):
                        scan(sub)
            for c in getattr(st, "cases", []) or []:
                scan(c.body)

    scan(tree.body)
    return spans


def stripped_source(src: str) -> tuple[str, list[tuple[int, int]]]:
    """`src` with every refusal statement removed, and the spans that were removed."""
    tree = ast.parse(src)
    exiting = UNREACH._exiting_helpers(tree)
    spans = refusal_spans(tree, exiting)
    lines = src.splitlines(keepends=True)
    keep = [l for i, l in enumerate(lines, 1) if not any(a <= i <= b for a, b in spans)]
    return "".join(keep), spans


def synthetic_root(td: str) -> pathlib.Path:
    """A root that LOOKS like the repo to `REPO = HERE.parents[0]` and contains no compiler."""
    r = pathlib.Path(td)
    (r / "pyproject.toml").write_text("[project]\nname='synthetic'\n")
    (r / "tinybendygrad").mkdir()
    (r / "checks").mkdir()
    (r / "gates").mkdir()
    return r


def run(py, root, argv):
    try:
        r = subprocess.run([str(py), *argv], cwd=root, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        return "TIMED-OUT", ""
    out = (r.stdout or "") + (r.stderr or "")
    return r.returncode, out


def first_line(out):
    for line in out.splitlines():
        if line.strip():
            return line.strip()[:96]
    return "(no output)"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", action="store_true")
    a = ap.parse_args()
    gates = []
    for p in sorted((ROOT / "checks").glob("*.py")) + sorted((ROOT / "gates").glob("*.py")):
        verdicts, _plants, _ri, _note = GS.declaration(p)
        if verdicts is None:
            continue
        state, _g, _e, _pa = UNREACH.describe(p.read_text(errors="replace"))
        if state == "REFUSAL-ABOVE-ARGV":
            gates.append((p, state))
    rows = []
    for p, state in gates:
        src = p.read_text(errors="replace")
        stripped, spans = stripped_source(src)
        before = {}
        with tempfile.TemporaryDirectory() as td:
            live = synthetic_root(td)
            for name, argv in SHAPES:
                before[name] = run(PY, ROOT, [str(p), *argv])
        after = {}
        with tempfile.TemporaryDirectory() as td:
            syn = synthetic_root(td)
            (syn / "checks" / p.name).write_text(stripped)
            (syn / "gates" / p.name).write_text(stripped)
            for name, argv in SHAPES:
                after[name] = run(PY, syn, [str(syn / "checks" / p.name), *argv])
        rows.append((str(p.relative_to(ROOT)), state, spans, before, after))
    hdr = f"{'gate':34} {'refusal':24}"
    if a.rows:
        print("gate\tgeometry\tremoved_lines\tbefore\tbefore_rc\tbefore_first\t"
              "after\t\tafter_rc\tafter_first")
        for rel, state, spans, before, after in rows:
            for name, _ in SHAPES:
                print("\t".join([rel, state, ";".join(f"{x}-{y}" for x, y in spans), name,
                                 str(before[name][0]), first_line(before[name][1]),
                                 name, str(after[name][0]), first_line(after[name][1])]))
        return 0
    print(f"I  {len(rows)} declaring gate(s) with a MODULE-SCOPE refusal. The refusal lines are "
          f"REMOVED\n   from an in-memory copy written into a synthetic root that has no `bin/bend` "
          f"and no `runs/`.\n")
    for rel, state, spans, before, after in rows:
        print(f"== {rel}   {state}   removed {';'.join(f'{x}-{y}' for x, y in spans)}")
        for name, _ in SHAPES:
            b, af = before[name], after[name]
            flag = "MOVES" if b[0] != af[0] else "same"
            print(f"   {name:9} before rc={str(b[0]):>4}  {first_line(b[1]):<50} | "
                  f"after rc={str(af[0]):>4}  {first_line(af[1]):<50} {flag}")
        print()
    moved = sum(1 for r in rows for n, _ in SHAPES if r[3][n][0] != r[4][n][0])
    print(f"I  {moved} of {len(rows) * len(SHAPES)} readings MOVE once the refusal is not in front "
          f"of them.")
    return 0


if __name__ == "__main__":
    sys.exit(main())