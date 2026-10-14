#!/usr/bin/env python3
"""THE 17 SHELL ENTRY POINTS: RUN WITH THE INTERPRETER THAT MATCHES THEIR SHEBANG.

    .venv/bin/python .agents/slop/exitsurvey/shellentry.py --cap 40

**A DEFECT MEASURED IN THE TREE'S OWN INSTRUMENT.** `gates/gate-surface.py:311` builds every plant's
command as `[str(PY), str(gate), *argv]` -- PYTHON, unconditionally -- while
`gates/gates-pop.py:141` puts `.sh` IN THE SAME POPULATION as `.py` (`SUFFIXES = (".py", ".sh")`).
So 17 of 128 discovered entry points are executed by the wrong interpreter, and a shell gate's
verdict as measured is the verdict of a Python syntax error. MEASURED HERE, not asserted:
`checks/demo.sh` answers `rc 0` under `bash` and `rc 1` under `.venv/bin/python` -- so the census
of the shell half of the population, taken with the interpreter the tree's own instrument uses,
reports a red that is not the tree's.

**THIS IS FILED, NOT FIXED: `gates/gate-surface.py` IS NOT MINE.** The measurement is here because
the unassigned-code census needs the shell half's real exits, and 17 gates whose measured exit is
an interpreter error are not a census.
"""
import contextlib
import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def loaded(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run(cmd, cap):
    try:
        r = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True, timeout=cap,
                           stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return None, f"<OVER-CAP {cap}s: cost UNKNOWN, and an unrun plant is not a verdict>"
    out = ((r.stdout or "") + (r.stderr or ""))
    head = next((l.strip() for l in out.splitlines() if l.strip()), "<SILENT>")[:78]
    return r.returncode, head


def main():
    cap = 40
    if "--cap" in sys.argv:
        cap = float(sys.argv[sys.argv.index("--cap") + 1])
    gk = loaded(ROOT / "gates" / "gatekit.py", "gk_under_shellentry")
    gs = loaded(ROOT / "gates" / "gate-surface.py", "gs_under_shellentry")
    entries, libs = gs.population(ROOT)
    sh = [p for p in sorted(entries) if p.suffix == ".sh"]
    print(f"POPULATION gates-pop.discover() BY PATH: {len(entries)} entry points; "
          f"{len(sh)} of them are `.sh` (`gates-pop.py:141` SUFFIXES puts both in one set)")
    print(f"OWNER gates/gatekit.py: "
          f"{', '.join(f'{c}={w}' for c, w in sorted(gs.vocabulary().items()))}\n")
    print(f"{'GATE':34} {'via PY (gate-surface:311)':>26}  {'via bash':>9}   AGREE?")
    print("-" * 90)
    differ = same = over = 0
    unassigned = []
    for p in sh:
        rel = str(p.relative_to(ROOT))
        rpy, hpy = run([sys.executable, str(p)], cap)
        rsh, hsh = run(["bash", str(p)], cap)
        if rpy is None or rsh is None:
            over += 1
            print(f"{rel:34} {str(rpy):>26}  {str(rsh):>9}   OVER-CAP -> measured nothing")
            continue
        ok = "yes" if rpy == rsh else "NO"
        differ += rpy != rsh
        same += rpy == rsh
        print(f"{rel:34} {rpy:>26}  {rsh:>9}   {ok}")
        if rpy != rsh:
            print(f"{'':34} python said: {hpy[:66]}")
            print(f"{'':34} bash   said: {hsh[:66]}")
        if rsh not in gk.VERDICT:
            unassigned.append((rel, rsh, hsh))
    print("-" * 90)
    print(f"{same} AGREE, {differ} DIFFER, {over} over-cap (measured nothing, and a SKIP is not "
          f"a pass)")
    print(f"\nTHE UNASSIGNED-CODE CLASS IN THE SHELL HALF, at the gate's OWN exit: {len(unassigned)}")
    for rel, rc, head in unassigned:
        print(f"  {rel:34} rc={rc}  {gk.verdict_of(rc)}\n      {head[:72]}")
    if not unassigned:
        print("  (none) -- the shell half is entirely inside the five, once run with `bash`.")
    print("\nA `.sh` PLANT MEASURED BY `gate-surface.py:311` IS NOT A VERDICT ABOUT THE GATE.")
    print("It is the verdict of a Python parser meeting a shebang, and 6 of the five codes can be")
    print("produced by either accident: `rc 1` from a SyntaxError is indistinguishable from FAIL.")
    return 0


if __name__ == "__main__":
    with contextlib.suppress(KeyboardInterrupt):
        sys.exit(main())