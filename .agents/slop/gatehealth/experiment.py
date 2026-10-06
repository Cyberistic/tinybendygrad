#!/usr/bin/env python3
"""Clause IV / clause I evidence for the gatehealth unit.

Builds STATIC fixtures so the verdict is not a measurement of a moving tree, runs
`gates/retention-check.py` against them, and writes every capture as `.out`/`.rows`.
"""
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent
PY = ROOT / ".venv" / "bin" / "python"
RC = ROOT / "gates" / "retention-check.py"

GATES = ("bc-u32-gate", "beautiful-mnist-gate", "ew-consts-gate", "ew-explog-gate",
         "i64-shl", "i64-shr", "mixin-op-gate", "ops-core-gate", "wk-cd-gate",
         "wk-eval-gate", "wk-f32-gate")
# gatekit.py:68-70 LANE_ROWS/LANE_OUT/LANE_CMP and gatekit.py:317's gate.bin literal.
FILES = ("py.rows", "bd.out", "bn.out", "py.cmp", "bd.cmp", "bn.cmp", "gate.bin")


def build_syn():
    syn = HERE / "gates-syn"
    if syn.exists():
        shutil.rmtree(syn)
    for g in GATES:
        d = syn / g
        d.mkdir(parents=True)
        for n in FILES:
            (d / n).write_text("x\n")
    return syn


def run(tag, *dirs):
    argv = [str(PY), str(RC)]
    for d in dirs:
        argv += ["--dir", d]
    r = subprocess.run(argv, capture_output=True, text=True, cwd=ROOT)
    (HERE / f"{tag}.out").write_text(r.stdout)
    (HERE / f"{tag}.err").write_text(r.stderr)
    with (HERE / "rc.rows").open("a") as f:
        f.write(f"{tag}\trc={r.returncode}\n")
    return r.returncode


def build_graphcmp(dirname, break_summary=False):
    """A copy of `runs/graphcmp/D`, DERIVED here and not committed.

    The corpus is 139 `.txt` artifacts; committing a copy would put 139 NEW `.txt` paths in the
    tree, outside `differ.declared()`'s carve-out, which `checks/no-txt.py` exists to catch. So the
    fixture is built from the live run on demand and deleted after the capture.
    """
    dst = HERE / dirname
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(ROOT / "runs" / "graphcmp" / "D", dst)
    if break_summary:
        (dst / "D0-run-summary.txt").write_text("graphs=25\ngraphs-agree=0\n")
    return dst


def main():
    (HERE / "rc.rows").write_text("tag\trc\n")
    syn = build_syn()
    run("after-syn-clean", f"gates={syn}")
    # plant: one undeclared file must still fire clause I
    (syn / "wk-f32-gate" / "stray.leftover").write_text("junk\n")
    run("after-syn-plant", f"gates={syn}")
    (syn / "wk-f32-gate" / "stray.leftover").unlink()

    gok = build_graphcmp("graphcmp-ok")
    gbad = build_graphcmp("graphcmp-broken", break_summary=True)
    run("after-graphcmp-ok", f"graphcmp={gok}")
    run("after-graphcmp-broken", f"graphcmp={gbad}")
    shutil.rmtree(gok)
    shutil.rmtree(gbad)
    print("done -- transient graphcmp copies removed")


if __name__ == "__main__":
    sys.exit(main())
