#!/usr/bin/env python3
"""ARGOWNER handoff: BUILD and MEASURE the one edit that is outside my write scope.

THE SITUATION.  Adding `ABoolList` to `Arg` broke `.agents/slop/graphcmp.bend:411
argstr` -- the differ's OWN harness, which every one of the 34 corpus graphs is
measured through.  Measured: `emit bend: 0 rows after 5 attempts` for 34 of 34
graphs.  That is DEAD (ran, emitted nothing), not zero and not a pass.

I may not edit that file: my scope is `tinybendygrad/` and `.agents/slop/argowner/`.
So this script COPIES it here, applies the two edits, fixes the import depth (this
directory is one level deeper than `.agents/slop/`), compiles and RUNS the copy, and
diffs its `flip` rows against the CPython rows already on disk.  The original is
never opened for writing; the copy's md5 and the original's md5 are both printed so
a reader can check that.

This makes the handoff a MEASUREMENT instead of a prediction.  It is not a landing.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
SRC = os.path.join(ROOT, ".agents/slop/graphcmp.bend")
HERE = os.path.join(ROOT, ".agents/slop/argowner")
DST = os.path.join(HERE, "handoff-graphcmp.bend")
PY = os.path.join(ROOT, ".venv/bin/python")


def md5(p):
    with open(p, "rb") as fh:
        return hashlib.md5(fh.read()).hexdigest()


def build():
    src = open(SRC).read()
    # 1. depth: this dir is one level below .agents/slop/
    out = src.replace("./../../tinybendygrad/", "./../../../tinybendygrad/")
    # 2. the ONE compile arm: `argstr` is closed over `Arg`, so a new ctor breaks it.
    arm = "    case O.ATuple{ys}: us(ys)\n"
    assert out.count(arm) == 1, out.count(arm)
    out = out.replace(arm, arm + "    case O.ABoolList{bs}: String.concat([\"n(\", String.join(bools.go(bs, Nil{}), \",\"), \")\"])\n")
    # 3. the helper `bools.go`, mirroring the existing `u32s.go`
    assert "\ndef u32s.go(" in out
    helper = ('\ndef bools.go(ys: List<&2, Bool>, acc: List<&2, String>) -> List<&2, String>:\n'
              '  match ys:\n'
              '    case Nil{}: acc\n'
              '    case b <> r: bools.go(r, List.append(&2, String, acc, [bo(b)]))\n')
    out = out.replace("\ndef u32s.go(", helper + "\ndef u32s.go(")
    # 4. `g_flip` must BUILD the bool spelling, which is now what the port's live
    #    FLIP path builds (prepare.bend `pr_flip`, movement.bend `G.flip` and
    #    `mxw_flip_new`, fold.bend `g_mv_flip` -- all measured `ABoolList`).
    gflip = "O.OpsFLIP{}, [O.Found.i(r43)], O.ATuple{[1, 0]}, O.TNone{}"
    assert out.count(gflip) == 1, out.count(gflip)
    out = out.replace(gflip, "O.OpsFLIP{}, [O.Found.i(r43)], O.ABoolList{[True{}, False{}]}, O.TNone{}")
    open(DST, "w").write(out)
    return out


def main():
    print(f"# SRC  .agents/slop/graphcmp.bend          md5 {md5(SRC)}")
    build()
    print(f"# DST  .agents/slop/argowner/handoff-graphcmp.bend  md5 {md5(DST)}")
    print(f"# SRC md5 UNCHANGED after the build: {md5(SRC)} "
          f"(this script only ever opened SRC for reading)")
    r = subprocess.run([PY, "checks/bounded.py", "--seconds", "900", "--mb", "3072", "--",
                        "./bin/bend", os.path.relpath(DST, ROOT), "--check-only"],
                       cwd=ROOT, capture_output=True, text=True)
    tok = "NO-TOKEN"
    for ln in r.stderr.split("\n"):
        if ln.startswith("[bounded] "):
            m = re.search(r"\b(WITHIN-LIMITS|KILLED-ON-MEMORY|TIMED-OUT)\b", ln)
            tok = m.group(1) if m else "UNPARSED"
    print(f"\n## COMPILE  token={tok} rc={r.returncode}")
    for ln in r.stderr.split("\n"):
        if not ln.startswith("[bounded] ") and ln.strip():
            print("  " + ln)
    if "ALL PROOFS CHECK" not in r.stdout:
        print("\nVERDICT: DEAD -- the handoff copy does not compile; the measurement stops")
        return 5

    print("\n## RUN -- the graph name is a POSITIONAL arg (graphcmp.py:1948 "
          "`[BEND, probe, graph]`), not `--graph`; the first run of this script "
          "passed `--graph flip` and got 0 rows for that reason alone")
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
    env.update(LC_ALL="C", DEV="CPU")
    rr = subprocess.run([PY, "checks/bounded.py", "--seconds", "900", "--mb", "3072", "--",
                         "./bin/bend", os.path.relpath(DST, ROOT), "flip"],
                        cwd=ROOT, capture_output=True, text=True, env=env)
    tok = "NO-TOKEN"
    for ln in rr.stderr.split("\n"):
        if ln.startswith("[bounded] "):
            m = re.search(r"\b(WITHIN-LIMITS|KILLED-ON-MEMORY|TIMED-OUT)\b", ln)
            tok = m.group(1) if m else "UNPARSED"
    bend_rows = [ln for ln in rr.stdout.split("\n") if ln.strip() and not ln.startswith("bend ")]
    py_rows = [ln for ln in open(os.path.join(ROOT, "oracles/rows-flip-py.rows")).read().split("\n")
               if ln.strip()]
    old_rows = [ln for ln in open(os.path.join(ROOT, "oracles/rows-flip-bend.rows")).read().split("\n")
                if ln.strip()]
    print(f"  token={tok}  cpython rows={len(py_rows)}  handoff-bend rows={len(bend_rows)}"
          f"  baseline-bend rows={len(old_rows)}")
    same = bend_rows == py_rows
    print(f"\n# VERDICT: {'AGREE (byte-identical to the CPython rows)' if same else 'DISAGREE'}")
    if not same:
        for a, b in zip(old_rows or [None] * 9, py_rows):
            print(f"  baseline {a}\n  cpython  {b}")
    else:
        for a, b in zip(old_rows, py_rows):
            mark = "  same" if a == b else "  MOVED"
            print(f"  {mark}\n    baseline {a}\n    handoff  {b}")
    return 0 if same else 1


if __name__ == "__main__":
    sys.exit(main())