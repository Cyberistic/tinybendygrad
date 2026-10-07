#!/usr/bin/env python3
"""gate-surface.py -- THE VERDICT SURFACE OF EVERY GATE: what each one DECLARES, and what a run
can actually MAKE it emit.

    .venv/bin/python gates/gate-surface.py            # the census AND the check
    .venv/bin/python gates/gate-surface.py --report   # the census only, rc never charged
    .venv/bin/python gates/gate-surface.py --plant    # the two-state self-test, synthetic tree only

THE NUMBER NOBODY WROTE DOWN. `.agents/slop/coindependent/REPORT.md` measured, over the 73 entry
points it could present a state for WITHOUT `bend`: **107 distinct exit codes declared, 28 reached,
79 (74%) never observed to fire, 40 more entry points presented in no state at all, and 9 gates
whose real surface is ZERO** (4 declare `REFUSED` as their only exit; 5 more could be driven only
to `REFUSED` because the input they compare against was swept). `AGENTS.md`'s sentence is why this
is the project's most important number: *"A gate that exits 0 having measured nothing is worse than
no gate, because it is trusted."* That measurement was a session's finding. This file makes it a
number EVERY RUN.

WHY THE DECLARATION, AND WHY IT IS NOT A SOURCE SCAN. `coindependent`'s 107 was PARSED from source
-- every literal that reaches an `exit`/`SystemExit`/`return` -- which is a SHAPE the file happens to
have, not a claim its author made. So a gate here DECLARES its own surface:

    VERDICTS = {0: "GREEN", 1: "RED", 3: "REFUSED"}     # exit code -> the token it prints
    PLANTS   = {0: ["--plant"], 3: ["--disarm", "DELETE"]}   # exit code -> argv that REACHES it

Read by `ast.literal_eval` off the MODULE BODY and never by import, because importing a gate RUNS
it: `gates/mixin-op-gate.py` and `gates/beautiful-mnist-gate.py` call `sys.exit(2)` at module scope,
and every `gatekit.Gate` clears its output directory in its constructor. Reading the two constants
out of the source the author wrote is reading a DECLARATION; scanning for `return 1` is reading a
shape. **A declaration cannot audit itself (`gates/gates-pop.py`'s own lesson), so this file does
not TRUST the declaration -- it EXECUTES each plant and requires the observed rc to equal the
declared one.**

THE RULE, AND IT IS THE WHOLE POINT. **A declared verdict with no plant is RED, named.** *"A check
nobody has ever seen fire is a check of unknown value."* Three reds, each with its own denominator:

  UNPLANTED  a declared exit code no declared plant reaches -- a claim of unknown value.
  MISPLANT   a plant whose observed rc is not the rc it was declared to reach.
  NO-GREEN   a gate that declares no rc 0, so it can never report agreement: real surface ZERO.

AND THE POPULATION IS NOT A SECOND LIST. It is `gates/gates-pop.py:discover()`, loaded BY PATH, the
same one-module-N-consumers shape `gates/gendirs.py` gave the generated directories. `coindependent`
walked its own `os.walk` and got **113** where `gates-pop` got **111** on the same tree. Reusing the
function makes the two numbers ONE BY CONSTRUCTION -- which is not the same as settling which was
right, and clause II prints the CONTROL (`os.walk`, recursive) beside it so the difference is named
rather than dissolved.

EXIT: 0 green, 1 red, 2 REFUSED -- a precondition was missing (no `pyproject.toml`/`tinybendygrad`
at the root, or an EMPTY population, because a gate over 0 files cannot fail). A `--report` run
prints the same census and returns 0.

PLANTED, plus the blind spot this file OWNS. `--plant` builds synthetic trees and asserts:
(1) a gate with an UNPLANTED verdict is RED and the verdict is NAMED, and (2) a gate whose every
verdict is planted is GREEN. **The blind spot is asserted too, because it is the class that let
`checks/citation-gate.py` stay green against a root that does not exist:** a plant that exits 0
having read nothing is indistinguishable, from the exit status alone, from a plant that agreed. This
file cannot tell green-correct from green-vacuous without a per-gate "did you read your input"
assertion, so plant 3 asserts the LIMIT rather than hiding it. See `--report`'s last line.
"""
import argparse
import ast
import contextlib
import io
import importlib.util
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY = ROOT / ".venv" / "bin" / "python"
TIMEOUT = 180


def refuse(*why):
    """exit 2 = REFUSED, and NOT a verdict. `checks/abi_gate.py`'s rule, in this file's idiom.

    Placed BEFORE any measurement, because an assertion downstream of what it asserts cannot turn
    an exception into a refusal (`checks/census.py`'s docstring records the tree doing exactly that:
    rc 1 and a traceback, which carries no denominator and so counts nowhere).
    """
    print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
    sys.exit(2)


def gates_pop():
    """`gates/gates-pop.py`, loaded BY PATH -- NEVER by name. `gates/` is not a package, and putting
    it on `sys.path` would make `gates_pop` a name any file in the tree could shadow: an instrument
    loaded by a bindable name is an instrument whose POPULATION anybody can choose. This is the same
    loader `gates/gendirs.py`'s two consumers use, for the same reason."""
    p = HERE / "gates-pop.py"
    if not p.is_file():
        refuse("gates/gates-pop.py is gone -- it IS the shared population, and this file has no "
               "second copy of the gate list by design")
    spec = importlib.util.spec_from_file_location("gates_pop", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---- clause I: the population, shared -----------------------------------------------
def population(root):
    """`(entries, libs)` from `gates-pop.discover()`. The ONLY definition of the population."""
    return gates_pop().discover(root)


def walk_control(root, homes):
    """A LABELLED CONTROL, not the population: the recursive `os.walk` count `coindependent` used.

    It exists to answer one question -- does reusing `discover()` make the 113-vs-111 disagreement
    disappear -- and the answer is printed beside `discover()`'s count. It is never used to decide
    what is a gate; two instruments holding two lists have no authority over each other, and this is
    the SECOND one deliberately, so the difference is visible.
    """
    out = set()
    for home in homes:
        h = root / home
        if not os.path.isdir(h):
            continue
        for dirpath, dirnames, filenames in os.walk(h):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if fn.endswith((".py", ".sh")):
                    out.add(str((Path(dirpath) / fn).relative_to(root)))
    return out


# ---- clause II: the DECLARATION, read not executed ---------------------------------
DECL = ("VERDICTS", "PLANTS")


def declaration(p):
    """`(verdicts, plants, note)` from the MODULE BODY of `p`, by `ast.literal_eval`.

    NEVER by import: importing a gate RUNS it -- `gates/mixin-op-gate.py`/`gates/beautiful-mnist-gate.py`
    `sys.exit(2)` at module scope, every `gatekit.Gate` clears its own directory at construction, and
    a gate whose only input is missing refuses at import. A declaration is a constant the author
    wrote; `literal_eval` reads exactly that and nothing else.
    """
    try:
        tree = ast.parse(p.read_text(errors="replace"))
    except SyntaxError as e:
        return None, None, f"UNPARSEABLE ({e.msg} line {e.lineno})"
    found = {}
    for node in tree.body:
        if isinstance(node, ast.Assign):
            targets = [t for t in node.targets if isinstance(t, ast.Name)]
        elif isinstance(node, ast.AnnAssign) and node.value is not None:
            targets = [node.target] if isinstance(node.target, ast.Name) else []
        else:
            continue
        for t in targets:
            if t.id in DECL:
                try:
                    found[t.id] = ast.literal_eval(node.value)
                except (ValueError, SyntaxError, TypeError):
                    found[t.id] = f"NOT A LITERAL"
    # `VERDICTS` IS THE MARKER. A file that names a `PLANTS` variable for its own reasons
    # (`checks/differ.py`, `checks/abi4_gate.py` both do, MEASURED -- my first run reported them
    # MALFORMED, which was a finding about this scanner and not about those files) is NOT a gate
    # that declared a surface. Only a file that ships `VERDICTS` is asked for the rest.
    if "VERDICTS" not in found:
        return None, None, ""
    if not isinstance(found["VERDICTS"], dict):
        return None, None, "VERDICTS is not a mapping"
    if "PLANTS" in found and not isinstance(found["PLANTS"], dict):
        return None, None, "VERDICTS is declared but PLANTS is not a literal mapping"
    return found["VERDICTS"], found.get("PLANTS"), ""


def reach(gate, argv):
    """`(rc, output)` for one declared plant. A TIMEOUT/EXC is NOT a verdict -- it is this
    instrument refusing to call an unrun plant a dead one, which is `coindependent`'s own rule:
    "an instrument that has not tried cannot call a verdict dead." """
    cmd = [str(PY), str(gate), *[str(a) for a in argv]]
    try:
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=TIMEOUT)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except subprocess.TimeoutExpired:
        return "TIMEOUT", ""
    except Exception as e:                        # a crashed command is still a measurement
        return "EXC", f"{type(e).__name__}: {e}"


# ---- the report --------------------------------------------------------------------
def report(root, charge=True):
    """The census over `root`: declared / reached / difference, per declaring gate, with every
    UNPLANTED, MISPLANT and NO-GREEN verdict NAMED. Returns rc."""
    gpop = gates_pop()
    entries, libs = population(root)
    if not entries:
        print(f"I  EMPTY POPULATION: no entry point under {'/'.join(gpop.HOMES)}/ -- and an empty "
              f"population\n   cannot fail, which is the defect this file exists for. REFUSED.")
        return 2

    print(f"I  DISCOVERED {len(entries)} entry point(s) under {'/'.join(gpop.HOMES)}/ "
          f"(+{len(libs)} module(s) with no entry guard)\n")
    control = walk_control(root, gpop.HOMES)
    disc = {str(p.relative_to(root)) for p in entries} | {
        str(p.relative_to(root)) for p in libs}
    only_walk = sorted(control - disc)
    print(f"I  POPULATION CONTROL: `discover()` sees {len(disc)} file(s) "
          f"({len(entries)} entries + {len(libs)} libs) vs\n   recursive `os.walk` {len(control)} "
          f"-- reusing the shared function makes the two numbers ONE BY\n   CONSTRUCTION, which is "
          f"not the same as settling which was right. {len(only_walk)} file(s) the\n   recursive "
          f"walk sees and `discover()` does not:")
    for rel in only_walk:
        print(f"I    WALK-ONLY {rel}")
    print()

    declared_total = reached_total = 0
    unplanted = misplant = nogreen = malformed = 0
    declaring = 0
    rows = []
    for p in entries:
        if p.suffix != ".py":
            continue
        verdicts, plants, note = declaration(p)
        if note:
            malformed += 1
            rows.append((p, None, None, note))
            continue
        if verdicts is None:
            continue
        declaring += 1
        verdicts = dict(verdicts)
        plants = dict(plants or {})
        reached = {}
        issues = []
        for rc in verdicts:
            declared_total += 1
            if rc not in plants:
                unplanted += 1
                issues.append(f"UNPLANTED {rc} {verdicts[rc]!r} -- declared, no plant")
                continue
            got, _out = reach(p, plants[rc])
            if got == rc:
                reached[rc] = got
                reached_total += 1
            elif got in ("TIMEOUT", "EXC"):
                issues.append(f"UNREACHED {rc} {verdicts[rc]!r} -- plant {got}, not tried")
            else:
                misplant += 1
                issues.append(f"MISPLANT  {rc} {verdicts[rc]!r} -- plant {plants[rc]} produced {got}")
        if 0 not in verdicts:
            nogreen += 1
            issues.append("NO-GREEN  -- declares no rc 0, so it can never report agreement")
        rows.append((p, verdicts, reached, issues))

    print(f"II DECLARATIONS: {declaring}/{len(entries)} entries declare VERDICTS -- "
          f"{len(entries) - declaring} do not, and each\n   one is a gate whose surface nobody has "
          f"written down (the backlog, counted not hidden)\n")
    if malformed:
        print(f"II MALFORMED DECLARATION: {malformed}\n")

    red = 0
    for p, verdicts, reached, issues in rows:
        rel = str(p.relative_to(root))
        if verdicts is None:
            print(f"II {rel}: MALFORMED -- {issues}")
            red = 1
            continue
        d = "/".join(str(k) for k in sorted(verdicts)) or "-"
        r = "/".join(str(k) for k in sorted(reached)) or "(none)"
        print(f"   {rel:44} declared {d:16} reached {r}")
        for issue in issues:
            print(f"     RED {rel}: {issue}")
            red = 1

    print()
    print(f"II SURFACE: {declared_total} verdicts declared, {reached_total} reached by a declared "
          f"plant,\n   {declared_total - reached_total} not reached, {unplanted} unplanted, "
          f"{misplant} misplant, {nogreen} NO-GREEN\n")
    if declaring == 0:
        print("III ZERO DECLARATIONS: this instrument measured the exit surface of NOTHING. A run "
              "that\ndeclares no verdict cannot fail, which is the `artefacts_ok()` shape. RED.")
        red = 1
    if charge and red:
        print("III RED: at least one declared verdict has no plant, or a plant missed its verdict, "
              "or a\ngate declares no green. EACH IS A CLAIM OF UNKNOWN VALUE (`AGENTS.md`: "
              "\"a check nobody has\never seen fire is a check of unknown value\").")
    print()
    print(f"GATE-SURFACE: {'RED' if red else 'OK'} -- {declaring} gate(s) declare a surface, "
          f"{reached_total}/{declared_total} verdicts reached, {unplanted} unplanted, "
          f"{nogreen} NO-GREEN")
    return 1 if (charge and red) else 0


# ---- clause III: the two-state plant, plus the blind spot ---------------------------
MAIN = "if __name__ == '__main__':\n    raise SystemExit(0)\n"
# A synthetic gate that returns the rc it is HANDED, so a declared plant reaches any code exactly.
DRIVER = ("import sys\nVERDICTS = {0: 'PASS', 1: 'FAIL', 3: 'REFUSED'}\n"
          "PLANTS = {0: [], 1: ['1'], 3: ['3']}\n"
          "if __name__ == '__main__':\n"
          "    sys.exit(int(sys.argv[1]) if len(sys.argv) > 1 else 0)\n")
UNPLANTED = ("import sys\nVERDICTS = {0: 'PASS', 1: 'FAIL', 3: 'REFUSED'}\n"
             "PLANTS = {0: []}\n"
             "if __name__ == '__main__':\n"
             "    sys.exit(int(sys.argv[1]) if len(sys.argv) > 1 else 0)\n")
NOGREEN = ("import sys\nVERDICTS = {3: 'REFUSED'}\nPLANTS = {3: ['3']}\n"
           "if __name__ == '__main__':\n"
           "    sys.exit(int(sys.argv[1]) if len(sys.argv) > 1 else 0)\n")
# THE BLIND SPOT, IN A GATE: exits 0, reads nothing, but plants every verdict it declares.
VACUOUS = ("import sys\nVERDICTS = {0: 'PASS'}\nPLANTS = {0: []}\n"
           "if __name__ == '__main__':\n    sys.exit(0)\n")


def _tree(root):
    (root / "pyproject.toml").write_text("[project]\nname='x'\n")
    (root / "tinybendygrad").mkdir()
    (root / "checks").mkdir()
    (root / "gates").mkdir()


def _run_report(root, charge=True):
    """`report` with its stdout captured, so a plant can assert what was NAMED rather than only
    that the exit moved. A plant that checks the rc alone cannot tell naming from silence."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = report(root, charge=charge)
    return rc, buf.getvalue()


def plants():
    """THREE plants, asserting THREE different directions, on SYNTHETIC trees only. Returns rc.

    PLANT 1 -- an UNPLANTED verdict is RED **and NAMED**. `rc==1` alone is satisfiable by a gate
    that reds on everything, so the assertion is on the WORD: the verdict's token and its code must
    appear in the transcript.
    PLANT 2 -- every verdict planted is GREEN. The control direction: a checker that never passes
    has shown nothing (`coindependent`: "a gate demonstrated only in its green state has shown
    nothing" -- and the converse is equally true).
    PLANT 3 -- the BLIND SPOT, ASSERTED NOT HIDDEN. A gate that exits 0 having read NOTHING is
    PASSED by this file. That is the `checks/citation-gate.py` shape -- green against a root that
    does not exist -- and this file CANNOT distinguish it from agreement without a per-gate "did
    you read your input" assertion. Asserting the limit is the honest alternative to promising a
    discrimination this instrument does not have.
    """
    rc = 0
    checks = []

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r)
        (r / "checks" / "unplanted.py").write_text(UNPLANTED)
        got, said = _run_report(r)
        named = ("FAIL" in said and "UNPLANTED 1" in said and "UNPLANTED 3" in said
                 and "REFUSED" in said)
        checks.append(("1: an UNPLANTED verdict is RED and the verdict is NAMED", got == 1 and named,
                       f"rc={got} named 'UNPLANTED 1'/'UNPLANTED 3'/FAIL/REFUSED={named}"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r)
        (r / "checks" / "planted.py").write_text(DRIVER)
        got, said = _run_report(r)
        checks.append(("2: every verdict planted is GREEN", got == 0 and "GATE-SURFACE: OK" in said,
                       f"rc={got} said_ok={'GATE-SURFACE: OK' in said}"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r)
        (r / "checks" / "nogreen.py").write_text(NOGREEN)
        got, said = _run_report(r)
        checks.append(("3a: a gate that declares NO GREEN is RED (real surface ZERO)",
                       got == 1 and "NO-GREEN" in said, f"rc={got} named_NO-GREEN={'NO-GREEN' in said}"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r)
        (r / "checks" / "vacuous.py").write_text(VACUOUS)
        got, said = _run_report(r)
        blind = got == 0
        checks.append(("3b: THE BLIND SPOT, ASSERTED -- a plant that exits 0 having read NOTHING is "
                       "PASSED. This file cannot tell green-correct from green-vacuous without a "
                       "per-gate input assertion.", blind,
                       f"rc={got} -- the honest limit, not a hidden one"))

    with tempfile.TemporaryDirectory() as td:
        r = Path(td); _tree(r)
        (r / "checks" / "empty.py").write_text(MAIN)
        got, _said = _run_report(r)
        checks.append(("3c: ZERO declaring gates is RED, never a vacuous green", got == 1,
                       f"rc={got}"))

    print("PLANTS -- three directions plus the blind spot, because an instrument that hides its "
          "own blind\nspot is the defect this project has catalogued twenty times")
    for name, ok, got in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {got}")
        rc |= 0 if ok else 1
    print(f"PLANTS: {'GREEN' if rc == 0 else 'RED'} ({sum(1 for c in checks if c[1])}/{len(checks)})")
    return rc


def main():
    ap = argparse.ArgumentParser(
        prog="gates/gate-surface.py", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="DENOMINATOR: every entry point `gates-pop.discover()` finds. A verdict with no "
               "denominator is a claim nobody can check.")
    ap.add_argument("--plant", action="store_true",
                    help="the two-state self-test on synthetic trees; never touches the live tree")
    ap.add_argument("--report", action="store_true",
                    help="the census only; rc is never charged, so a red surface does not fail a run")
    ap.add_argument("--root", default=None, help="point at another tree (plant/disarm only)")
    a = ap.parse_args()
    if not a.root:
        for marker in ("pyproject.toml", "tinybendygrad"):
            if not (ROOT / marker).exists():
                refuse(f"the repo root is not here: {marker} is absent at {ROOT}")
        return plants() if a.plant else report(ROOT, charge=not a.report)
    return plants() if a.plant else report(Path(a.root).resolve(), charge=not a.report)


if __name__ == "__main__":
    sys.exit(main())
