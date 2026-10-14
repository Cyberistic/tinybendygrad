#!/usr/bin/env python3
"""THE SET, classified by BEHAVIOUR with the AST as evidence, and the two disagreements named.

    .venv/bin/python .agents/slop/modulerefuse/x3-class.py

SCOPE, in the same sentence as the number it produces: **every `checks/*.py` and `gates/*.py` at the
top level of its home, on DISK, that the process answers `REFUSED` (3) with NO argv.** Not the eight
inherited, not a column: the population is enumerated by `iterdir()` and the verdict is MEASURED, so
a gate the predicate cannot see is invisible in BOTH halves rather than in one.

THE THREE CLASSES, and the middle one is the whole subject:

  FIRING-AT-MODULE-SCOPE  the exit that FIRES sits above every `parse_args`, so the process is gone
                          before argv is read. NO FLAG AND NO PLANT CAN EVER REACH THE GREEN PATH.
                          The verdict is not hard to reach; it is unreachable BY CONSTRUCTION.
  ARMS-BUT-CANNOT-IMPORT the same AST shape, and the module dies on an import first. The refusal
                          is unreachable and so is everything else -- a DIFFERENT defect wearing
                          the same shape, and naming it apart matters because the fix differs.
  ARGV-REACHABLE          the refusal that fires is inside `main()` (or there is no `parse_args` at
                          all), so an argv reaches past it. The green path exists. NOT in this set.

**"HAS A MODULE-SCOPE REFUSAL" IS NOT "A MODULE-SCOPE REFUSAL FIRES", AND THE INSTRUMENT THAT
CONFLATED THEM IS THE FIFTH REPRODUCED INSTANCE OF DOCTRINE 1 IN THIS TREE.** A gate can carry
three module-scope guards whose conditions are all FALSE and still refuse from `main()`; measured
here, `checks/oracle_f64.py` refuses at module scope `:84` and `:87`, both guards FALSE, and exits
3 from `main()`:279. So this file does not classify by the AST alone -- **it matches the refusal
TEXT the process printed against the text each guard would print**, which is the only thing that can
tell which guard fired. `checks/norm_check.py` is the same shape with rc=0, and it is why two
prior units read this column as a column.

`zerogate` put `git-index-guard.py` in the set on the strength of an rc=3 read. rc=3 with NO argv is
what a gate with a `usage:` line does; it is not the same as a refusal that cannot be left, and this
file measures the difference instead of reasoning about it.
"""
import ast
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PY = ROOT / ".venv" / "bin" / "python"
HOMES = ("checks", "gates")
TIMEOUT = 45
sys.path.insert(0, str(ROOT / "gates"))
from gatekit import REFUSED  # noqa: E402


def population():
    """Every `*.py` at the top level of a gate home. `iterdir()`, not `rglob()`: a `__pycache__`
    under a home must not contribute a cached `.pyc`, and `gates/gates-pop.py:discover()` walks the
    same way for the same reason."""
    out = []
    for home in HOMES:
        h = ROOT / home
        if h.is_dir():
            out += [p for p in sorted(h.iterdir()) if p.suffix == ".py" and p.is_file()]
    return out


def guards(path):
    """`(line, in_a_def, static_text)` for every refusal-vocabulary call, classified by scope.

    `static_text` is the string CONSTANTS inside the guard's own expression, which is what makes a
    refusal self-describing: `refuse(f"input absent: {_p}")` always prints the substring
    `input absent: `, so a printed refusal can be matched back to the guard that fired. Every gate in
    this class prints one fixed literal -- `input absent`, `REPO does not hold the tree`,
    `needs <workdir>` -- and the measurement is that the match SUCCEEDS rather than the assumption
    that it could.
    """
    try:
        tree = ast.parse(path.read_text(errors="replace"))
    except SyntaxError:
        return None
    spans = [(n.lineno, n.end_lineno or n.lineno)
             for n in ast.walk(tree)
             if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
    helpers = {n.name for n in ast.walk(tree)
               if isinstance(n, ast.FunctionDef) and n.name.split("_")[0] in ("refuse", "refusal")}
    out = []
    for n in ast.walk(tree):
        if not isinstance(n, ast.Call):
            continue
        name = n.func.id if isinstance(n.func, ast.Name) else getattr(n.func, "attr", "")
        hit = name in helpers or (name == "exit" and n.args and isinstance(n.args[0], ast.Constant)
                                  and n.args[0].value in (3, 4, 5))
        if not hit:
            continue
        lits = [c.value for c in ast.walk(n)
                if isinstance(c, ast.Constant) and isinstance(c.value, str) and len(c.value) > 4]
        out.append((n.lineno, any(lo <= n.lineno <= hi for lo, hi in spans), tuple(lits)))
    return sorted(set(out))


def ap_line(path):
    try:
        tree = ast.parse(path.read_text(errors="replace"))
    except SyntaxError:
        return None
    ap = [n.lineno for n in ast.walk(tree)
          if isinstance(n, ast.Call) and getattr(n.func, "attr", "") == "parse_args"]
    return min(ap) if ap else None


def firing(path, printed):
    """Which guard's LITERALS appear in the refusal the process actually printed.

    Returns `(line, in_a_def)` of the match, or None. A refusal whose text matches NO guard is
    REPORTED as unmatched rather than guessed at, because a guess here would be a second population
    held by hand -- the exact fault `zerogate` measured in `coindependent/surface.py:25`'s 42 paths.
    """
    g = guards(path) or []
    hit = [(l, d) for l, d, lits in g if any(x[:24] in printed for x in lits)]
    if hit:
        return min(hit)
    return ("UNMATCHED", None) if g else None


def run(rel, argv):
    try:
        r = subprocess.run([str(PY), str(ROOT / rel), *argv], cwd=ROOT,
                           capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", "", ""
    o = next((l for l in (r.stdout or "").splitlines() if l.strip()), "")
    e = next((l for l in (r.stderr or "").splitlines() if l.strip()), "")
    return str(r.returncode), o, e


def main():
    rows = []
    for p in population():
        rel = str(p.relative_to(ROOT))
        base, out, err = run(rel, [])
        if base != str(REFUSED):
            continue
        printed = (out + " " + err).strip()
        hit = firing(p, printed)
        if hit is None:
            klass = "ARMS-BUT-CANNOT-IMPORT"   # no refusal vocabulary at all: the 3 is elsewhere
        elif hit[0] == "UNMATCHED":
            klass = "REFUSED-NO-WITNESS"        # exits 3 and names no guard: `zerogate`'s gate (e)
        elif hit[1]:
            klass = "ARGV-REACHABLE"           # the guard that fired is INSIDE a def
        else:
            klass = "FIRING-AT-MODULE-SCOPE"
        rows.append((rel, klass, hit, ap_line(p), printed))

    print(f"REFUSED (3) WITH NO ARGV, over {'/'.join(HOMES)}/*.py at the top level of each home\n")
    print(f"{'':2} {'gate':32} {'class':26} {'fired at':>16} {'in main?':>9} {'parse_args':>10}")
    print("-" * 100)
    counts = {}
    for rel, klass, hit, ap, tok in sorted(rows, key=lambda r: (r[1], r[0])):
        counts[klass] = counts.get(klass, 0) + 1
        at = f"{hit[0]}:refuse" if hit and hit[0] != "UNMATCHED" else (hit[0] if hit else "--")
        ind = "main" if hit and hit[1] else "module"
        print(f"  {rel:32} {klass:26} {at:>16} {ind:>9} {str(ap):>10}")
    print()
    for k, v in sorted(counts.items()):
        print(f"{k:28} {v}")
    hard = counts.get("FIRING-AT-MODULE-SCOPE", 0)
    print(f"\nTHE SET (green unreachable BY CONSTRUCTION): {hard}, over the "
          f"{len(rows)} gate(s) that refuse with no argv.")
    for rel, klass, hit, ap, tok in sorted(rows, key=lambda r: r[0]):
        if klass == "FIRING-AT-MODULE-SCOPE":
            print(f"   {rel}")
    print("\nTHE REFUSAL TEXT, because 'which guard fired' is only a claim until it is read:")
    for rel, klass, hit, ap, tok in sorted(rows, key=lambda r: r[0]):
        if klass == "FIRING-AT-MODULE-SCOPE":
            print(f"  {rel:30} {tok[:96]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())