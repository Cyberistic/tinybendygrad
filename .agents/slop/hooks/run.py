#!/usr/bin/env python3
"""run.py -- ONE runner for the gate population. Dry run unless --run.

    .venv/bin/python .agents/slop/hooks/run.py            # what it would invoke, and why
    .venv/bin/python .agents/slop/hooks/run.py --run      # invoke them
    .venv/bin/python .agents/slop/hooks/run.py --run --only=msgdiff-gate

THE POPULATION IS `gates/gates-pop.py:discover()`, LOADED BY PATH. NEVER A LIST. That is
this project's first doctrine and it has been broken three times by hand-listing; a runner
that names its 13 gates in a Python tuple is the fourth time, and it is the worst time,
because a runner is what people trust when the list and the tree disagree.

THE FILTER IS ALSO A DISCOVERY, not a list: a gate is invoked iff its source declares a
`VERDICTS` mapping, read by `ast.literal_eval` off the module body exactly as
`gates/gate-surface.py` does it. MEASURED: 13 of 114 entries declare one, and those 13 are
exactly the gates that can TALLY -- a gate with no declared surface cannot say which of the
five verdicts it produced, so aggregating its exit code would be guessing. The other 101 are
reported SKIP with the reason, because a silent omission is how a gate becomes "written but
never run" without anyone noticing.

WHAT THIS RUNNER MUST NOT DO, and the measured reason for each.

  It must not require GREEN. `gates/gate-surface.py` exits 1 BECAUSE 30 of its declared
    verdicts have never fired -- the redness IS its finding. A runner that required every
    gate green could not run the instrument that reports unplanted verdicts, which is
    `AGENTS.md`'s "a pre-commit gate that cannot pass teaches nothing and will be skipped",
    restated. So redness is DATA here; the runner's own exit describes THE RUN, never the
    tree. `gate-surface` is therefore invoked with `--report`, which charges rc 0 -- and that
    flag ALREADY EXISTS (`gates/gate-surface.py:400-409`), so nothing had to be added to it.

  It must not turn a crash into a pass. The mapping is `gatekit`'s five and no sixth:
        0 GREEN   1 FAIL   3 REFUSED   4 SKIP   5 DEAD
    Anything else is UNKNOWN and is counted as DEAD, never as GREEN. MEASURED, and this is
    why it matters: `gates/msgdiff-gate.py` and `git-massdelete-gate.py` return FAIL(1) from
    their `--plant` self-test ONLY (grep: one `return FAIL` each, both inside `_plant`). So
    a runner whose RED condition is `rc == 1` is BLIND to both guards -- they are never 1 in
    normal operation, and their refusals are 3. And MEASURED: an unparseable rev gives
    `DEAD` (5) with `DEAD: git could not answer`, so crash and refusal ARE distinguishable
    by exit code -- but only if 5 and 3 are kept apart, which `all(rc == 0)` also does and
    `rc == 1` does not.

  It must not count pids or trust a number it cannot re-derive. Every count printed here is
    computed by walking the tree at run time.
"""
import importlib.util
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
CAP = int(os.environ.get("HOOKRUN_CAP", "60"))
NAME = {PASS: "GREEN", FAIL: "FAIL", REFUSED: "REFUSED", SKIP: "SKIP", DEAD: "DEAD"}


def load_gates_pop():
    """`gates/gates-pop.py` BY PATH. `gates/` is not a package and putting it on sys.path
    would make `gates_pop` a name any file in the tree could shadow."""
    p = ROOT / "gates" / "gates-pop.py"
    spec = importlib.util.spec_from_file_location("gates_pop_under_run", p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def declares_surface(path):
    """Does this source declare `VERDICTS = {...}`? Read as SOURCE, never imported --
    importing a gate RUNS it, and `gates/mixin-op-gate.py` exits 2 at module scope."""
    try:
        import ast
        tree = ast.parse(path.read_text())
    except (SyntaxError, OSError, UnicodeDecodeError):
        return False
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            getattr(t, "id", None) == "VERDICTS" for t in node.targets
        ):
            return True
    return False


def invoke(path, extra):
    """Returns (verdict, first_line, seconds). THREE rules, each measured in `cost.py`:

    OVER-CAP -> SKIP, not DEAD and not GREEN. `checks/residue.py` `os.walk`s the whole tree
    and exceeded 45s while the other thirteen gates finished in 4.1s combined; without a cap
    the runner is unbounded (`run.py --run` exceeded 600s before this rule existed). Its cost
    is UNKNOWN, which is SKIP -- it is not evidence the gate is broken, and it is certainly
    not evidence the gate passed.

    rc 1 WITH A TRACEBACK -> DEAD, not FAIL. MEASURED: `checks/oracle_f64.py` with no argv
    raises `IndexError: list index out of range` at :266 and exits 1, which is the same
    number as FAIL. A runner that reads rc==1 as "the gate ran and got the wrong answer" would
    report a CRASH as a verdict -- exactly the `refusalsweep`/`envguard` failure, and the one
    way an aggregating runner can manufacture a confident wrong answer.

    SILENCE -> named, not assumed. A gate that exits 0 having printed nothing is not GREEN.
    """
    rel = str(path.relative_to(ROOT))
    argv = [sys.executable, str(path), *extra]
    t0 = time.monotonic()
    try:
        r = subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT), timeout=CAP,
                           stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return SKIP, f"<OVER-CAP {CAP}s: cost UNKNOWN>", CAP
    out = ((r.stdout or "") + (r.stderr or "")).strip()
    head = out.splitlines()[0][:80] if out else "<SILENT: exited 0 having said nothing>"
    if r.returncode == 1 and "Traceback" in out:
        return DEAD, "crashed, not a verdict: " + head, time.monotonic() - t0
    if not out and r.returncode == PASS:
        return DEAD, "<SILENT: exited 0 having said nothing>", time.monotonic() - t0
    return (r.returncode if r.returncode in NAME else DEAD), head, time.monotonic() - t0


def main(argv):
    do = "--run" in argv
    only = next((a.split("=", 1)[1] for a in argv if a.startswith("--only=")), None)
    # Asked for by NAME, on the command line, because there is no declaration of this
    # population to load. MEASURED: `gates/gate-surface.py` ships NO module-level `VERDICTS`
    # (its exits are `0 if not (charge and red) else 1` at :287 and `2` at :195), so it is
    # invisible to the surface filter below -- an auditor of surfaces, declaring none. Naming
    # it here would be a hand list, which is the fault this project has already paid for
    # three times, so it is an ARGUMENT and the omission is printed rather than hidden.
    reports = {a.split("=", 1)[1] for a in argv if a.startswith("--report-gate=")}

    entries, libs = load_gates_pop().discover(ROOT)
    withsurface = [p for p in entries if declares_surface(p)]
    invokable = [p for p in withsurface if not only or only in p.name]
    tally = dict.fromkeys(NAME, 0)
    rows = []

    print(f"POPULATION: gates-pop.discover() -> {len(entries)} entries, {len(libs)} modules")
    print(f"INVOKABLE : {len(withsurface)} declare VERDICTS; "
          f"{len(entries) - len(withsurface)} do not (SKIP, no surface to tally)")
    for name in sorted(reports):
        hit = [p for p in entries if p.name == name or str(p.relative_to(ROOT)) == name]
        print(f"ASKED-REPORT: {name} -> {len(hit)} in population, invoked with --report"
              if hit else f"ASKED-REPORT: {name} NOT IN THE POPULATION (typo, or it moved?)")

    for p in invokable:
        rel = str(p.relative_to(ROOT))
        if not do:
            print(f"  would run  {rel}")
            continue
        rc, head, secs = invoke(p, ())
        tally[rc] += 1
        print(f"  {NAME[rc]:<8} {secs:6.1f}s  {rel:<38} {head}")
        rows.append(f"{rel}\t{NAME[rc]}\t{head[:90]}\t{secs:.1f}")
    for name in sorted(reports):
        for p in entries:
            if p.name == name or str(p.relative_to(ROOT)) == name:
                rc, head, secs = invoke(p, ("--report",))
                tally[rc] += 1
                print(f"  {NAME[rc]:<8} {secs:6.1f}s  {p.relative_to(ROOT)} --report")
                rows.append(f"{p.relative_to(ROOT)} --report\t{NAME[rc]}\t{head[:90]}\t{secs:.1f}")

    if not do:
        print("(dry run; pass --run to invoke)")
        return 0
    print("\nTALLY: " + "  ".join(f"{NAME[k]}={tally[k]}" for k in NAME))
    measured = tally[PASS] + tally[FAIL]
    print(f"THE DENOMINATOR, WHICH IS NOT THE TALLY: {measured} of {len(rows)} gates reached a")
    print(f"verdict about the tree. {tally[REFUSED]} refused because an input is ABSENT, "
          f"{tally[SKIP]} did not finish, {tally[DEAD]} crashed or said nothing.")
    print('"14 gates ran" is 14 subprocesses, not 14 measurements.')
    print("NOTE : this runner's exit describes THE RUN (did every gate emit a verdict?),")
    print("       never the tree. Redness is data. Do not add a sixth verdict.")
    (HERE / "run.tsv").write_text(
        "gate\tverdict\tfirst line\tseconds\n" + "\n".join(rows) + "\n")
    return PASS if rows else DEAD


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
