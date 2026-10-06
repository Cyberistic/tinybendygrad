#!/usr/bin/env python3
"""ABI4CHK-2 -- assert the LANE is in the ARTIFACT before planting anything.

Builds the EXACT probe `checks/abi4_gate.py` builds, by IMPORTING its own
`cases()` and `emit()` -- nothing is transcribed, so this cannot drift from the
gate the way a retyped probe can.  Two spellings of the bind, because the two
trees disagree about whether the seams are effects.  Writes nothing live.

    .venv/bin/python .agents/slop/abi4check/probe-measure.py <tree-root> <outdir>
"""
from __future__ import annotations

import importlib.util
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

OUT = pathlib.Path(sys.argv[2]).resolve()
OUT.mkdir(parents=True, exist_ok=True)

# import the gate as a module WITHOUT running main().  The depth is PROVED, not
# assumed -- the same rule `checks/abi4_gate.py:refuse()` follows.
gate_path = pathlib.Path(__file__).resolve().parents[3] / "checks" / "abi4_gate.py"
if not gate_path.is_file():
    sys.exit(f"not the repo root: {gate_path} is absent (parents[N] stale after a move?)")
g = importlib.util.module_from_spec(importlib.util.spec_from_file_location("abi4gate", gate_path))
sys.modules["abi4gate"] = g
g.__spec__.loader.exec_module(g)  # noqa: E402

BEND = g.BEND
ROW = g.ROW


def run(root: pathlib.Path, cs, bind, label) -> None:
    with tempfile.TemporaryDirectory() as td:
        work = pathlib.Path(td) / "tree"
        work.mkdir()
        shutil.copytree(root / "tinybendygrad", work / "tinybendygrad")
        text = g.emit(cs)
        if bind != "<-":                       # only the bind spelling differs
            text = re.sub(r"^(    v\d+ : \w+) <-", r"\1 =", text, flags=re.M)
        bend_src = work / "f32.bend"
        bend_src.write_text(text)
        out = work / "f32.js"
        if out.exists():
            out.unlink()
        r = subprocess.run([str(BEND), str(bend_src), "-o", str(out)],
                           capture_output=True, text=True, timeout=3600)
        said = r.stdout + "\n".join(
            l for l in r.stderr.splitlines() if "is available: run bend update" not in l)
        (OUT / f"{label}.probe.bend").write_text(text)
        (OUT / f"{label}.bend.said").write_text(said)
        print(f"\n=== {label} (bind {bind!r})  bend rc={r.returncode}  "
              f"backend emitted: {out.exists()}")
        if not out.exists():
            print("  NO BACKEND.  bend said:")
            for line in said.splitlines()[:9]:
                print("    | " + line)
            return
        (OUT / f"{label}.probe.js").write_text(out.read_text())
        p = subprocess.run(["node", str(out)], capture_output=True, text=True, timeout=600)
        rows = [m for m in map(ROW.match, p.stdout.splitlines()) if m]
        js = out.read_text()
        print(f"  node rc={p.returncode}  rows {len(rows)}/{len(cs)}")
        for tok in ("i64_of", "pack64", "fp8_decode", "of32", "bits32",
                    "dtype.js", "dtype.c"):
            print(f"    emitted-probe count of {tok!r:<12} = {js.count(tok)}")
        lane = root / "tinybendygrad" / "runtime" / "dtype.js"
        if lane.is_file():
            lt = lane.read_text()
            print(f"    dtype.js ON DISK: i64_of={lt.count('i64_of')} "
                  f"pack64={lt.count('pack64')} fp8_decode={lt.count('fp8_decode')}")
        (OUT / f"{label}.rows").write_text(
            "\n".join(f"{m[1]} = {m[2]}" for m in rows) + "\n")


root = pathlib.Path(sys.argv[1]).resolve()
cs = g.cases()
print(f"gate probe from {gate_path}")
print(f"tree={root}  rows={len(cs)}  first expr={cs[0].expr}")
for bind, label in (("<-", "bind-lt"), ("=", "bind-eq")):
    run(root, cs, bind, label)