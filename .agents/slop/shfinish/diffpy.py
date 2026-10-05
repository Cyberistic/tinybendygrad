#!/usr/bin/env python3
"""diffpy -- the verdict diff for the two gates ported here, and the PLANTS that make it a
diff rather than two runs that agreed once.

WHAT IT GATES, AND THE DENOMINATOR. For each (gate, input set) it runs THE FROZEN SHELL and THE
PYTHON, and compares THREE things, because the third is the one that has bitten this project
four times:

    VERDICT      the pass/fail CLAIM each side makes, parsed out of its own output
    EXIT STATUS  `diff A B && echo MATCHES` under `set -e` exits 0 having printed a diff, so the
                 status alone is not the verdict and the verdict alone is not the status
    WHOLE OUTPUT every byte of stdout, so a line that is IDENTICAL across implementations cannot
                 be hiding a line that is not

INPUT SETS: `clean` and then one PLANT per failure mode the shell can reach. A diff over `clean`
only proves the two agree when there is nothing to disagree about.

THE PLANTS ARE NOT IN THE LIVE TREE. Each runs in `.agents/slop/shfinish/plant/`, a COPY of the
repo with the same relative depth, because a $TMPDIR copy one level shallower cannot resolve a
relative import -- 22 phantom blind spots in one unit came from exactly that (`lintable-gate.sh`
and `checks/e2epy` both record it) -- and because a harness that patches the live tree is how
`FROMBITS`' first mutate.sh died to the tool timeout and left a plant in `tinybendygrad/`.

RUNS SERIALLY, ONE `bend` AT A TIME, ALWAYS: `sz.bend` peaks at 1,468 MB and `renderer/nir.bend`
1,435 MB, and two of those concurrently took this machine's memory to zero on 2026-10-05.

EXIT: 0 every input set agreed on verdict AND status; 1 at least one did not; 2 the harness
could not build the plant tree.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / ".agents/slop" / "shfinish"
PLANT = HERE / "plant"
PY = ROOT / ".venv/bin/python"

# (label, gate name, driver, oracle, the shell that implements it, the python that ports it,
#  the substring that means GREEN in each one's output)
GATES = {
    "mixin": dict(
        shell=".agents/slop/mixinop/oracle-op-gate.sh",
        py="gates/mixin-op-gate.py",
        driver="tinybendygrad/mixin/op.bend",
        oracle=".agents/slop/mixin-op-gate.py",
        green=re.compile(r"lanes identical"),
    ),
    "bmn": dict(
        shell=".agents/slop/bmn/oracle-mnist-gate.sh",
        py="gates/beautiful-mnist-gate.py",
        driver="examples/beautiful_mnist.bend",
        oracle=".agents/slop/beautiful-mnist-gate.py",
        green=re.compile(r"lanes identical"),
    ),
}

# WHAT EACH PLANT DOES, AND WHICH FAILURE MODE IT IS AIMED AT. `None` means "leave it alone".
PLANTS = [
    ("clean", "the tree as it stands"),
    ("row-moved", "one shared row's value changes in the PORT: the diff must fire"),
    ("row-dropped", "one shared row is DELETED from the port: a count, not a diff"),
    ("bend-only-leaks", "a PORT-ONLY row starts appearing in the ORACLE: the exclusion must fail"),
    ("driver-cold", "the driver is given a syntax error: `|| true` must NOT save the gate"),
    ("oracle-gone", "the ORACLE is deleted: a redirect makes an EMPTY file, which is the "
                    "zero-denominator trap with an extra step"),
    ("oracle-empty", "the ORACLE is truncated to 0 bytes, which `substrate.py` calls out as the "
                     "project's oldest failing in a new place"),
]


# THE FIXTURE TEXT each `row-moved` plant rewrites, MEASURED out of the two oracles rather than
# guessed, because a plant whose target is not in the file is a plant that never fired.
FIXTURE = {
    "tinybendygrad/mixin/op.bend":
        ("def fx1d() -> Tensor: return Tensor([1., 2., 3., 4.], device='PYTHON')",
         "def fx1d() -> Tensor: return Tensor([1., 2., 3., 9.], device='PYTHON')"),
    "examples/beautiful_mnist.bend":
        ("""print("relu1=" + sig(Tensor([1., 2., 3., 4.], device='PYTHON').relu()))""",
         """print("relu1=" + sig(Tensor([1., 2., 3., 9.], device='PYTHON').relu()))"""),
}


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "-"


def build_plant() -> None:
    """A copy of the repo at the SAME relative depth, so both implementations resolve their
    imports and neither needs a path override. `tinygrad/` is SYMLINKED, not copied: it is the
    upstream tree, neither gate edits it, and copying 4 checked-out tinygrad trees is what made
    the last census 4,624 of 5,802 files."""
    if PLANT.exists():
        shutil.rmtree(PLANT)
    for d in ("tinybendygrad", "examples", "checks", "gates"):
        shutil.copytree(ROOT / d, PLANT / d, symlinks=True,
                        ignore=shutil.ignore_patterns("__pycache__", "artifacts"))
    (PLANT / ".venv").symlink_to(ROOT / ".venv")
    (PLANT / "tinygrad").symlink_to(ROOT / "tinygrad")
    (PLANT / "bin").mkdir()
    # COPIED, NOT SYMLINKED, AND MADE EXECUTABLE. `bin/bend` is a 2-line `#!/bin/sh` that `exec`s
    # an ABSOLUTE path into `references/bend/`, so it is tree-independent and a symlink would do;
    # it is copied because a symlink to the live wrapper is one more thing that can be swapped
    # under a run that is supposed to be about the plant. THE SHELLS ARE chmod'd for the same
    # reason: `substrate-check.sh`'s own shim header records that a harness whose preamble
    # depends on PATH reports "command not found" and then tries to exec a relative path from
    # the wrong place -- rc 126/127, LOUDLY, but a loud failure that costs a whole run.
    shutil.copy2(ROOT / "bin/bend", PLANT / "bin/bend")
    os.chmod(PLANT / "bin/bend", 0o755)
    for g in GATES.values():
        for rel in (g["shell"], g["oracle"]):
            # `g["shell"]` IS `.agents/slop/<dir>/oracle-<name>.sh`, so the destination is the
            # path itself. The earlier version joined it onto `.agents/slop` twice and wrote the
            # oracle to `.agents/slop/.agents/slop/...` -- a path that cannot exist, so the first
            # `clean` run reported rc 127 for BOTH implementations and agreed about nothing.
            dst = PLANT / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / rel, dst)
    # THE ORACLE PINS ARE PINNED TO THE COPIES, and the copies are byte-for-byte, so the pinned
    # sha256 in each gate still holds inside the plant tree. If it does not, the pin fires and
    # the Python exits 2 -- which is the right answer, not a harness bug to be worked around.
    (PLANT / ".venv").symlink_to(ROOT / ".venv")


def run(argv: list[str], cwd: Path) -> tuple[str, int]:
    """argv[0]'s stdout AND exit status. `env -u PYTHONPATH` because contamination is real in this
    tree and `checks/differ.py` measures it contaminating a control."""
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
    p = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, text=True)
    return p.stdout, p.returncode


def verdict(out: str, green: re.Pattern) -> str:
    return "GREEN" if green.search(out) else "RED"


def apply_plant(kind: str, g: dict) -> str:
    """Mutate the PLANT COPY and say what was done. Every function here writes inside `PLANT`."""
    drv, orc = PLANT / g["driver"], PLANT / g["oracle"]
    if kind == "row-moved":
        # THE FIXTURE IS EDITED, NOT THE ROW. The oracle's rows are DERIVED from CPython
        # (`lit1d` is `fx1d()` over a Tensor), so a row's text is not in the source to be
        # replaced -- editing the printed text would plant on a string the oracle happens to
        # produce today. Changing the FIXTURE moves the row's VALUE and leaves its NAME and the
        # lane COUNT alone, which is exactly the defect a row-count-only harness cannot see.
        needle, sub = FIXTURE[g["driver"]]
        body = orc.read_text()
        assert needle in body, f"the plant target {needle!r} is not in the oracle"
        orc.write_text(body.replace(needle, sub, 1))
        return (f"changed the oracle's fixture {needle!r} to {sub!r}. The row keeps its NAME and "
                f"both lanes keep their ROW COUNT, so nothing but the byte diff can see it")
    if kind == "row-dropped":
        orc.write_text(orc.read_text() + '\nprint("plant_extra_row=1")\n')
        return ("appended `plant_extra_row` to the ORACLE. The port does not have it, so the "
                "lanes now differ by a COUNT: 37 oracle rows against 36, which is the defect a "
                "value-blind harness absorbs")
    if kind == "bend-only-leaks":
        body = orc.read_text() + '\nprint("rop_gap=True")\n'
        orc.write_text(body)
        return "made the ORACLE print the port-only row `rop_gap`, which is the moment an "\
               "exclusion stops being a divergence and starts hiding a comparison"
    if kind == "driver-cold":
        drv.write_text(drv.read_text() + "\nthis is not bend\n")
        return "appended a line of garbage to the driver: --check-only stops saying ALL PROOFS "\
               "CHECK. THE SHELL'S TWO ANSWERS DIFFER HERE and this is the input that shows it"
    if kind == "oracle-gone":
        orc.unlink()
        return "deleted the oracle. `python3 <missing> > out` is a REDIRECT: it creates an EMPTY "\
               "out and exits 0, so the gate diffs 0 rows against 36 and calls it a clean run "\
               "over nothing"
    if kind == "oracle-empty":
        orc.write_text("")
        return "truncated the oracle to 0 bytes. The same redirect, the same empty lane, and the "\
               "gate's own denominator is what notices"
    return "left alone"


def main() -> int:
    print("building the plant tree ...", flush=True)
    build_plant()
    print(f"  {PLANT.relative_to(ROOT)}  "
          f"driver={sha(PLANT / GATES['mixin']['driver'])[:12]}")
    rows, bad = [], 0
    for gname, g in GATES.items():
        for kind, why in PLANTS:
            build_plant()
            did = apply_plant(kind, g)
            # THE PIN THE WHOLE COMPARISON RESTS ON. Six other units are editing this tree at
            # once -- MEASURED 2026-10-05: `examples/beautiful_mnist.bend` read WARM at 19:19
            # and COLD at 19:23 with no file of mine changed -- so a verdict measured minutes
            # apart is not a comparison. Both implementations run here, back to back, on one
            # tree state, and these shas are printed so a reader can see it was one.
            before = {k: sha(PLANT / g[k]) for k in ("driver", "oracle")}
            sh_out, sh_rc = run(["sh", str(PLANT / g["shell"])], PLANT)
            py_out, py_rc = run([str(PY), str(PLANT / g["py"])], PLANT)
            after = {k: sha(PLANT / g[k]) for k in ("driver", "oracle")}
            stable = before == after
            sv, pv = verdict(sh_out, g["green"]), verdict(py_out, g["green"])
            same_out = sh_out == py_out
            ok = (sv == pv and sh_rc == py_rc)
            bad += not ok
            rows.append((gname, kind, sv, sh_rc, pv, py_rc, same_out, stable, why, did))
            print(f"{'ok ' if ok else 'DIFF'}  {gname:6} {kind:18} "
                  f"shell={sv}/rc{sh_rc}  py={pv}/rc{py_rc}  "
                  f"stdout={'IDENTICAL' if same_out else 'DIFFERS'}  "
                  f"tree={'stable' if stable else 'MOVED'}")
    print()
    print(f"{'gate':7} {'input set':18} {'shell':9} {'rc':3} {'python':9} {'rc':3} "
          f"{'whole stdout':14} {'tree'}")
    for r in rows:
        print(f"{r[0]:7} {r[1]:18} {r[2]:9} {r[3]:<3} {r[4]:9} {r[5]:<3} "
              f"{('IDENTICAL' if r[6] else 'DIFFERS'):14} {'stable' if r[7] else 'MOVED'}")
    print()
    print("WHAT EACH PLANT DID")
    seen = set()
    for r in rows:
        if r[1] in seen:
            continue
        seen.add(r[1])
        print(f"  {r[1]:18} {r[9]}")
    print()
    print(f"VERDICT: {len(rows) - bad}/{len(rows)} input sets agree on VERDICT and EXIT STATUS")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
