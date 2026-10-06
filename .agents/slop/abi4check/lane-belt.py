#!/usr/bin/env python3
"""ABI4CHK-4 -- THE BELT.  A SECOND METHOD THAT SHARES NO ASSUMPTION WITH THE COUNT.

Step 1 of `plant-measure.py` counts TOKENS in the emitted probe, and "the plants
moved 0 rows" is downstream of the same fact: both assume `dtype.js` reaches the
artifact.  ONE TOKENIZER, ONE ASSUMPTION IS NOT A BELT.

So here the lane is attacked twice more, and neither attack reads a token:

  B1  PLANT UNCOMPILABLE JS into `runtime/dtype.js`.  If anything compiles or
      consumes that file, the run dies.  98/98 identical rows says the file was
      never read -- no token counting involved.
  B2  PLANT `throw new Error("LANE_REACHED")` at module top level.  Valid JS, so
      it compiles; the only way it stays silent is that the MODULE NEVER RAN.
      This is a semantic fact about execution, not about text.

Both run against the LIVE tree, on a COPY.  Writes nothing live.

    .venv/bin/python .agents/slop/abi4check/lane-belt.py <tree> <gate.py> <outdir>
"""
from __future__ import annotations

import importlib.util
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

tree = pathlib.Path(sys.argv[1]).resolve()
gate_path = pathlib.Path(sys.argv[2]).resolve()
out = pathlib.Path(sys.argv[3]).resolve()
out.mkdir(parents=True, exist_ok=True)
REPO = pathlib.Path(__file__).resolve().parents[3]
BEND = tree / "bin" / "bend"

g = importlib.util.module_from_spec(
    importlib.util.spec_from_file_location("abi4gate_belt", gate_path))
sys.modules["abi4gate_belt"] = g
g.__spec__.loader.exec_module(g)

lane = tree / "tinybendygrad" / "runtime" / "dtype.js"
pristine = lane.read_text()
cs = g.cases()
names = [r.name for r in cs]
ROW = g.ROW
emit = re.sub(r"^(    v\d+ : \w+) <-", r"\1 =", g.emit(cs), flags=re.M)

# LANE_REACHED is deliberately not one of the gate's tokens and shares no regex
# with the count belt: it is an exception, and only EXECUTION can produce one.
PLANTS = {
    "B1-uncompilable": 'THIS_IS_NOT_JS ((( error\n',
    "B2-throws-on-load": 'throw new Error("LANE_REACHED");\n',
    "B3-marker-only": 'const LANE_REACHED_MARKER_7a3f = 1;\n',
}


def once(work, label):
    work.joinpath("f32.bend").write_text(emit)
    o = work / "f32.js"
    if o.exists():
        o.unlink()
    r = subprocess.run([str(BEND), str(work / "f32.bend"), "-o", str(o)],
                       capture_output=True, text=True, timeout=3600)
    if not o.exists():
        return None, f"bend rc={r.returncode}", (r.stdout + r.stderr)[:400]
    p = subprocess.run(["node", str(o)], capture_output=True, text=True, timeout=600)
    rows = {m[1]: m[2].strip() for m in map(ROW.match, p.stdout.splitlines()) if m}
    return rows, f"bend rc=0 node rc={p.returncode} rows {len(rows)}/{len(cs)}", p.stderr[:400]


with tempfile.TemporaryDirectory() as td:
    work = pathlib.Path(td) / "tree"
    work.mkdir()
    shutil.copytree(tree / "tinybendygrad", work / "tinybendygrad")
    base, st, err = once(work, "shipped")
    print(f"shipped  {st}")
    if base is None:
        sys.exit("the probe does not compile at all; the belts have nothing to compare")
    (out / "base.rows").write_text("\n".join(f"{n} = {base[n]}" for n in names) + "\n")
    print(f"{'':<22}{'rows':>7}  {'moved':>6}  identical to shipped?  what it says")
    for label, body in PLANTS.items():
        work.joinpath("tinybendygrad/runtime/dtype.js").write_text(pristine + "\n" + body)
        rows, st, err = once(work, label)
        if rows is None:
            print(f"  {label:<20} NO BACKEND  {st}  -> the file IS read")
            continue
        moved = sum(1 for n in names if rows.get(n) != base[n])
        same = rows == base
        note = ("module never executed -- it did NOT even throw"
                if "LANE_REACHED" in label else
                "file never compiled into the artifact" if "uncompilable" in label
                else "never referenced")
        print(f"  {label:<20} {len(rows):>5}  {moved:>6}  {str(same):<19}  {note}")
        (out / f"{label}.rows").write_text(
            "\n".join(f"{n} = {rows.get(n)}" for n in names) + "\n")
print(f"\nwrote {out}")