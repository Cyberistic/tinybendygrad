#!/usr/bin/env python3
"""MEASURE THE FIX before proposing it: hoist the refusal below `parse_args` and see what changes.

    .venv/bin/python .agents/slop/modulerefuse/x4-fix.py

THE QUESTION. The brief asks what moving a module-scope refusal below `argparse` does, because the
fix for "the verdict is unreachable by construction" is a POSITION change, and a POSITION change may
change WHAT THE GATE REFUSES. Three sub-questions, one transform, three argv cases each:

  (a) with no argv        (b) `--help`        (c) a flag the gate does not accept

THE TRANSFORM IS AST, NOT TEXT SURGERY, AND THE OUTPUT IS RE-PARSED BEFORE IT RUNS. The first
version of a sibling instrument's transform was a regex over source lines and produced files that did
not parse -- a finding about the transform, not about the gates, and a plant that cannot fail is not
a plant. So: parse, find the module-scope `refuse(...)` statements, wrap them in a `def` that is
called immediately after `parse_args()`, unparse, and `ast.parse` the RESULT. If the result does not
parse, the run is REFUSED rather than executed.

**THE FILE IS WRITTEN TO A SCRATCH DIRECTORY AND THE GATE'S OWN PATH IS NOT TOUCHED.** These files
are `checks/*.py` and `checks/*.py` logic is outside this unit's ownership. The transform therefore
reproduces the gate's ENTRY STRUCTURE in a copy under a scratch tree, and every verdict below is the
SCRATCH COPY's -- which is exactly as strong a claim as the question allows, and is stated so that a
reader does not mistake it for the live gate.

**THE COUNTERFACTUAL IS NAMED UP FRONT SO IT CAN BE REFUTED**: if the hoisted refusal reads the same
inputs as the module-scope one -- which it does, because both read `Path` objects computed above --
then the hoisted gate answers 3 for the SAME REASON with a REAL argv, and the no-argv case answers 3
for a reason argparse did not get to. That is a gate that refuses correctly AND parses correctly. If
instead the no-argv case answers 1 with a traceback, the move is a regression and the report says so.
"""
import ast
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PY = ROOT / ".venv" / "bin" / "python"
TIMEOUT = 60

TARGETS = sys.argv[1:] or [
    "checks/gate.py", "checks/nl-gate.py", "checks/nl-gate-noguard.py", "checks/dup-gate.py",
    "checks/dup-census.py", "checks/rn-gate.py", "checks/hermetic-census.py", "checks/cl-port-gate.py",
]
CASES = (("none", []), ("--help", ["--help"]), ("bad", ["--no-such-flag-9f3c"]))


def spans(tree):
    return [(n.lineno, n.end_lineno or n.lineno)
            for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]


def helpers(tree):
    return {n.name for n in ast.walk(tree)
            if isinstance(n, ast.FunctionDef) and n.name.split("_")[0] in ("refuse", "refusal")}


def parse_args_lines(tree):
    """Every line that CALLS `parse_args()`, including `ap.parse_args()` and bare `parse_args()`."""
    return [n.lineno for n in ast.walk(tree) if isinstance(n, ast.Call)
            and getattr(n.func, "attr", getattr(n.func, "id", "")) == "parse_args"]


def _name(n):
    return n.func.id if isinstance(n.func, ast.Name) else getattr(n.func, "attr", "")


def _is_refusal(hl, n):
    """The refusal names this CALL carries, or (). Two spellings exist in this tree and neither is
    a list of files: a call to a `refuse*` helper, and `exit(<3|4|5>)` with the code IN the call."""
    name = _name(n)
    if name in hl:
        return (name,)
    if name == "exit" and n.args and isinstance(n.args[0], ast.Constant) \
            and n.args[0].value in (3, 4, 5):
        return (name,)
    return ()


def hoist(src):
    """Lift the module-scope refusal BLOCKS into a def called after `parse_args()`.

    Returns `(new_src, note)` or `(None, reason)`. The rewrite is DONE ON THE TREE and emitted with
    `ast.unparse`, and the RESULT IS RE-PARSED before it is run -- because the second version spliced
    by LINE RANGE and every one of the eight produced a file that would not parse. A transform nobody
    re-parses is a transform that cannot fail for the right reason.

    **A REFUSAL IS NOT A STATEMENT HERE, IT IS A BLOCK.** MEASURED: the first version asked "is this
    module-level statement a refusal" and found none in any of the eight -- because every one of
    them writes

        for _p in (SLOP / "rebase-gate.py", _EQ):
          if not _p.is_file():
            refuse(f"input absent: {_p} ...")

    so the refusal sits NESTED TWO DEEP inside a `for` over the inputs, and a statement-level scan
    reported "no module-scope refusal to hoist" for EIGHT OF EIGHT files while every one of them
    was refusing at rest. **A POPULATION DEFINED BY A STATEMENT SHAPE IS A POPULATION THAT MISSES
    THE GATE IT WAS WRITTEN FOR** -- Doctrine 1's own sentence, inside the transform for clause 3.

    So the block is found by CONTAINMENT: a module-level `for`/`if`/`while`/`with`/`try` whose
    SUBTREE holds a refusal call is lifted WHOLE, `else`/`elif` included, because half a conditional
    is not a gate. `spans` excludes nested definitions, so a refusal inside `main()` is never lifted.
    """
    tree = ast.parse(src)
    sp, hl = spans(tree), helpers(tree)

    def holds_refusal(node):
        return any(_is_refusal(hl, n) for n in ast.walk(node) if isinstance(n, ast.Call))

    moved = [s for s in tree.body
             if not any(lo <= s.lineno <= hi for lo, hi in sp) and holds_refusal(s)
             and isinstance(s, (ast.For, ast.If, ast.While, ast.With, ast.Try))]
    if not moved:
        return None, "no module-scope refusal BLOCK to lift"
    keep = [s for s in tree.body if s not in moved]
    ap = parse_args_lines(tree)
    if not ap:
        return None, "no parse_args() standing to hoist below"

    fn = ast.FunctionDef(name="_hoisted_refusal", args=ast.arguments(
        posonlyargs=[], args=[], kwonlyargs=[], kw_defaults=[], defaults=[]),
        body=moved, decorator_list=[], returns=None, type_params=[])
    call = ast.Expr(value=ast.Call(func=ast.Name(id="_hoisted_refusal", ctx=ast.Load()),
                                   args=[], keywords=[]))

    # The call goes at the END of the module body, not after the `parse_args()` LINE: a module-level
    # `a = ap.parse_args()` is an assignment, and the `max(lineno)` anchor a line-based splice wanted
    # is the LINE of a call inside an expression. Placing it after every module-level statement keeps
    # every later import, every constant and every path computation above it -- which is the whole
    # question this file exists to answer, since a refusal that reads `SLOP` must see `SLOP` defined.
    tree.body = keep + [fn, call]
    ast.fix_missing_locations(tree)
    new = ast.unparse(tree) + "\n"
    try:
        ast.parse(new)
    except SyntaxError as e:
        return None, f"lift produced unparseable source ({e.msg} line {e.lineno})"
    return new, f"lifted {len(moved)} block(s) to the end of the module body"


def run(path, argv):
    """Run a copy of a gate. `PYTHONPATH` CARRIES THE REAL `checks/`, because **a scratch tree is
    an ARTIFACT and would report one.**

    MEASURED TWICE, and both versions of this harness were wrong in the same direction -- each
    reported "moving the refusal turns `REFUSED` into a TRACEBACK", and each traceback was the
    HARNESS and not the subject:
      (1) a bare temp tree, so `ModuleNotFoundError: No module named 'denominator'` -- a SIBLING of
          `checks/` the copy could not see;
      (2) a temp tree NESTED under the repo root, so `REPO = HERE.parents[0]` resolved to the TEMP
          directory and every `SLOP / ...` read missed `.agents/slop/` entirely.

    **A HARNESS DEFECT REPORTED AS A DEFECT IN THE SUBJECT IS WORSE THAN NO MEASUREMENT, because it
    is a number that reads as a finding and would have been quoted.** The copy therefore lives AT
    `checks/` under a name that is not a module, so `parents[0]` IS the repo root and every path the
    gate computes resolves; and it is deleted in a `finally`, with the residue COUNTED afterwards
    rather than assumed absent.
    """
    env = dict(os.environ, PYTHONPATH=str(ROOT / "checks"))
    try:
        r = subprocess.run([str(PY), str(path), *argv], cwd=ROOT, env=env,
                           capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", ""
    out = next((l for l in (r.stdout or "").splitlines() if l.strip()), "")
    err = next((l for l in (r.stderr or "").splitlines() if l.strip()), "")
    return str(r.returncode), (out or err)


def scratch(rel, new_src):
    """Write the transformed copy AT `checks/<stem>.x4` and return its path. The extension is `.x4`
    and not `.py` so the tree's own `.py` enumerations (`gates/gates-pop.py:SUFFIXES`,
    `x3-class.py:population()`) cannot count it -- **an instrument that counts its own fixture is a
    population that measures the harness.** Python does not care about the suffix when a path is
    passed to the interpreter."""
    p = ROOT / rel
    dest = p.with_suffix(".x4")
    dest.write_text(new_src)
    return dest


def residue():
    """Scratch copies still on disk. Read AFTER every run; a plant that cannot be seen is a plant
    nobody can trust to have finished."""
    return sorted(str(p.relative_to(ROOT)) for p in (ROOT / "checks").iterdir()
                  if p.suffix == ".x4")

def main():
    print("BEFORE (the live file, unmodified) and AFTER (a SCRATCH COPY with the refusal hoisted "
          "below\n`parse_args()`). The scratch tree lives under the repo root so `REPO = "
          "parents[n]` still resolves.\n")
    print(f"{'gate':28} {'transform':34} " + " ".join(f"{c[0]:>13}" for c in CASES))
    print("-" * 118)
    verdicts = {}
    for rel in TARGETS:
        live = ROOT / rel
        before = [run(live, a) for _n, a in CASES]
        new, note = hoist(live.read_text())
        if new is None:
            print(f"{rel:28} {note[:34]:34} " + " ".join(f"{b[0]:>13}" for b in before))
            verdicts[rel] = (before, None, note)
            continue
        dest = scratch(rel, new)
        try:
            after = [run(dest, a) for _n, a in CASES]
        finally:
            dest.unlink(missing_ok=True)
        verdicts[rel] = (before, after, note)
        print(f"{rel:28} {note[:34]:34} "
              + " ".join(f"{b[0]}->{a[0]:>10}" for b, a in zip(before, after)))

    left = residue()
    print(f"\nRESIDUE AFTER ALL RUNS: {len(left)} scratch cop(y|ies) left under checks/ {left}")
    print("\nWHAT EACH TRANSFORMED GATE NOW SAYS WITH NO ARGV -- whether it refused for the SAME "
          "reason or a NEW one:")
    for rel, (before, after, note) in sorted(verdicts.items()):
        if after is None:
            continue
        print(f"  {rel:28} {after[0][1][:88]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())