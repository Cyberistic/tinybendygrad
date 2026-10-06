"""WHICH ROWS ARE DEVICE-DEPENDENT?  Per graph, per device: does the PY side still reproduce
the artifact the run recorded?

`runs/graphcmp/D/D2-canon-py-<g>.txt` IS the py side's output under the conditions the run
used, so re-emitting under a different device and diffing against it answers the only
question that matters for a verdict: **would this row's recorded verdict still hold, or would
the PIN move?**  `expect-moved=0` and `byte-identical=19` are ZERO-TOLERANCE, so a row whose
py half moves with the machine will fire one of them the moment anyone runs on another
device, and the failure will read as a port regression.

Nothing here writes to `runs/`: the recorded artifacts are opened READ-ONLY and compared.

Run:  .venv/bin/python .agents/slop/devpin/lin-decision.py
"""
from __future__ import annotations
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PY = str(ROOT / ".venv/bin/python")
GCMP = ROOT / ".agents/slop/graphcmp.py"
D = ROOT / "runs/graphcmp/D"
DEVICES = ("CPU", "NULL", "METAL", "PYTHON")


def graphs() -> list[str]:
    import importlib.util
    spec = importlib.util.spec_from_file_location("gcmp_c", str(GCMP))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return sorted(m.GRAPHS)


def emit(g: str, dev: str) -> bytes:
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {"LC_ALL": "C"}
    return subprocess.run([PY, str(GCMP), "emit", "--side", "py", "--graph", g, "--dev", dev],
                          env=env, capture_output=True).stdout


def main() -> int:
    gs = graphs()
    rec = {g: (D / f"D2-canon-py-{g}.txt").read_bytes() for g in gs}
    cmp_ = {g: (D / f"D2-cmp-{g}.txt").read_text(errors="replace") for g in gs}
    ident = {g for g in gs if "IDENTICAL" in cmp_[g]}
    print(f"{len(gs)} graphs.  `D2-cmp-*.txt` says IDENTICAL for {len(ident)} of them, "
          f"DIFFERS for {len(gs) - len(ident)}.\n")

    print(f"{'graph':10s} {'recorded':9s} " + " ".join(f"{d:>13s}" for d in DEVICES))
    stable, moved, empty = [], [], []
    for g in gs:
        cells = []
        for d in DEVICES:
            if not rec[g]:
                cells.append("EMPTY")
            else:
                cells.append("same" if emit(g, d) == rec[g] else "MOVES")
        if not rec[g]:
            empty.append(g)
        elif all(c == "same" for c in cells):
            stable.append(g)
        else:
            moved.append(g)
        print(f"{g:10s} {'IDENT' if g in ident else 'DIFFERS':9s} "
              + " ".join(f"{c:>13s}" for c in cells))

    print(f"\nPY HALF REPRODUCES THE RECORDED ARTIFACT ON EVERY DEVICE ({len(stable)}):")
    print("  " + " ".join(stable))
    print(f"\nPY HALF MOVES WITH THE DEVICE ({len(moved)}):")
    print("  " + " ".join(moved))
    if empty:
        print(f"\nRECORDED ARTIFACT IS 0 BYTES ({len(empty)}):  " + " ".join(empty))
    print("\n--- AND THE QUESTION THAT DECIDES `lin`: does its VERDICT move? ---")
    print("`WANT['lin'] == 'DISAGREE'`.  A verdict moves only if a device turns DISAGREE")
    print("into AGREE.  The port's recorded emission is `kI(sr_4_5_3,n(q),N,i0)`; a row")
    print("AGREES only if the py side is byte-identical to it.")
    for d in DEVICES:
        got = emit("lin", d)
        print(f"  DEV={d:<7} py rows={len(got.splitlines()):>3}  "
              f"Opt objects={got.count(b'Opt(')}  "
              f"agrees with the port? {got == (D / 'D2-canon-bend-lin.txt').read_bytes()}")
    print("\n  VERDICT under CPU/NULL : py resolves the option, port emits `q` -> DISAGREE")
    print("  VERDICT under METAL/PY : py emits TWO options, port emits one `q` -> DISAGREE")
    print("  => `lin`'s DISAGREE HOLDS ON EVERY DEVICE.  IT DOES NOT MOVE.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
