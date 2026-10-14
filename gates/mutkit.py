#!/usr/bin/env python3
"""mutkit.py -- the MECHANISM a per-gate `-mutate.py` supplies a TABLE to.

A mutation reading answers one question: does a green gate say anything about the RULES, or
only about the absence of a mutation? One mutation that moves nothing at rc=0 is either a
COVERAGE GAP (the rule has no row) or a DEAD DEF (the rule is not on the path), and telling
those apart IS the deliverable -- two units this session hit the "moved nothing" case and
neither could say which.

THE COPY LIVES BESIDE THE ORIGINAL, NEVER IN A TMPDIR. A `.bend` file imports its neighbours
RELATIVE TO ITS OWN PATH, so a copy anywhere else fails to resolve them and answers "the
substrate did not warm" -- a REFUSED exit for the wrong reason, and a harness that reports
"the mutation was found" because the file could not be compiled has learned nothing. The
tree's own driver is NEVER written.

EVERY PATTERN IS ASSERTED UNIQUE BEFORE IT IS APPLIED, so a mutation that silently stopped
matching is a REFUSED entry and not a green one. The MUTATED ROWS ARE READ BEFORE THE GATE
RUNS, because the run deletes the copy -- reading them afterwards compares the BASE against
itself and every mutation reports "moved nothing", which is this harness's own version of
class (e): a test that does not read its input.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def bend_rows(path):
    r = subprocess.run([str(ROOT / "bin" / "bend"), str(path)], capture_output=True, text=True,
                       cwd=str(ROOT))
    return {l.split("=", 1)[0]: l for l in r.stdout.splitlines() if "=" in l}, r.returncode


def _run(gate, driver):
    """Run `gate`'s `main()` with its `DRIVER` pointed at a copy. The copy must EXIST first:
    `Gate`'s warm check is `bend --check-only <driver>` and a missing copy answers
    "no such file", which is a REFUSED exit for the wrong reason."""
    run = ROOT / "gates" / ".mut-run.py"
    mut = driver.with_name(f".{driver.stem}-mut{driver.suffix}")
    run.write_text(
        "import importlib.util, sys\n"
        "from pathlib import Path\n"
        f"spec = importlib.util.spec_from_file_location('g', {str(gate)!r})\n"
        "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
        f"m.DRIVER = Path({str(mut)!r})\n"
        "sys.exit(m.main())\n")
    try:
        r = subprocess.run([sys.executable, str(run)], capture_output=True, text=True,
                           cwd=str(ROOT))
        return r.returncode, r.stdout + r.stderr
    finally:
        mut.unlink(missing_ok=True)
        run.unlink(missing_ok=True)


def main(gate, driver, mutations):
    """`mutations` is a list of `(name, upstream line, find, replace)`. Returns the summary
    line it printed, so a caller can fold two readings into one transcript."""
    src = Path(driver).read_text()
    rc, out = subprocess.run([sys.executable, str(gate)], capture_output=True, text=True,
                             cwd=str(ROOT)).returncode, ""
    if rc != 0:
        print(f"{Path(gate).name}: the UNMUTATED tree is rc={rc}, so a mutation reading would "
              f"be meaningless\n{out}")
        return 1
    base, brc = bend_rows(driver)
    print(f"{Path(gate).name}: BASE is rc=0, {len(base)} rows\n")
    dead, gaps, moved_any = [], [], 0
    for name, py_line, find, repl in mutations:
        n = src.count(find)
        if n != 1:
            print(f"  REFUSED   {name}: the pattern occurs {n} times, expected 1 ({py_line})")
            dead.append(name)
            continue
        mut = Path(driver).with_name(f".{Path(driver).stem}-mut{Path(driver).suffix}")
        mut.write_text(src.replace(find, repl))
        mut_rows, mrc = bend_rows(mut)
        grc, _ = _run(Path(gate), Path(driver))
        moved = sorted(k for k, v in mut_rows.items() if k in base and base[k] != v)
        # A ROW THAT APPEARS OR VANISHES IS A MUTATION THAT MOVED, NOT ONE THAT DID NOT
        # COMPILE. `ra<t>_a<i>` is emitted per key of `reals`, so breaking the END/BACKEDGE
        # use-skip ADDS a program point and the lane gets LONGER; reading that as "did not
        # compile" is how a population change gets filed as a compile failure.
        appeared = sorted(set(mut_rows) - set(base))
        vanished = sorted(set(base) - set(mut_rows))
        print(f"  {name:<54} bend rc={mrc} gate rc={grc}  {len(moved)} rows moved"
              + (f", {len(appeared)} appeared, {len(vanished)} vanished" if appeared or vanished
                 else ""))
        if moved or appeared or vanished:
            moved_any += 1
            if moved:
                print(f"      {', '.join(moved[:14])}"
                      + (f" (+{len(moved) - 14} more)" if len(moved) > 14 else ""))
            for row in appeared:
                print(f"      APPEARED {row}={mut_rows[row][:70]}")
            for row in vanished:
                print(f"      VANISHED {row} (was {base[row][:70]})")
        elif mrc == 0 and grc == 0:
            print("      MOVED NOTHING AT rc=0 -- a COVERAGE GAP: this rule has no row.")
            gaps.append(name)
        else:
            print("      the mutant did not compile -- the rule is load-bearing at TYPE level")
    print(f"\n{Path(gate).name}: {moved_any} of {len(mutations)} mutations moved rows; "
          f"{len(gaps)} moved nothing at rc=0 (coverage gaps); {len(dead)} refused on a "
          f"non-unique pattern")
    return 0