#!/usr/bin/env python3
"""ABI4CHK-3 -- DO THE PLANTS MOVE, ON EACH TREE, WITH THE GATE'S OWN BYTES.

THE ORDER IS THE POINT, AND IT IS NOT NEGOTIABLE:

  1. ASSERT THE LANE IS IN THE ARTIFACT.  Emit the gate's own probe, compile it,
     and count the tokens the plants are written against.  A plant that patches a
     file the artifact does not contain is a plant that CANNOT move, and the
     report must say so BEFORE the moved-count, not after.
  2. Only then run shipped + each plant + each disarm and count moved rows.

Nothing here is transcribed: the probe, the three site anchors, the three plants
and the three disarms are imported from the gate file at the tree under test.

    .venv/bin/python .agents/slop/abi4check/plant-measure.py <tree> <gate.py> <outdir>
"""
from __future__ import annotations

import importlib.util
import json
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
if tree != REPO:
    # The tree under test gets the shim that resolves to the shared compiler.  A
    # symlink READS the other unit's checkout; it does not move or check it out.
    bend_dir = tree / "bin"
    bend_dir.mkdir(exist_ok=True)
    shutil.copy(REPO / "bin" / "bend", bend_dir / "bend")
    (bend_dir / "bend").chmod(0o755)
    ref = tree / "references" / "bend"
    ref.mkdir(parents=True, exist_ok=True)
    link = ref / "bend2"
    if not link.exists() and not link.is_symlink():
        link.symlink_to(REPO / "references" / "bend" / "bend2")

g = importlib.util.module_from_spec(
    importlib.util.spec_from_file_location("abi4gate_under_test", gate_path))
sys.modules["abi4gate_under_test"] = g
g.__spec__.loader.exec_module(g)  # the gate's REPO/refuse() runs here, at import

lane = tree / "tinybendygrad" / "runtime" / "dtype.js"
pristine = lane.read_text()
cs = g.cases()
names = [r.name for r in cs]
ROW = g.ROW

report: dict[str, object] = {"tree": str(tree), "gate": str(gate_path),
                             "rows": len(cs), "arms": {}}


def emit_for(text_bind: str) -> str:
    t = g.emit(cs)
    if text_bind == "=":
        t = re.sub(r"^(    v\d+ : \w+) <-", r"\1 =", t, flags=re.M)
    return t


def compile_and_run(work: pathlib.Path, cs, label):
    bend_src = work / "f32.bend"
    out_js = work / "f32.js"
    if out_js.exists():
        out_js.unlink()
    r = subprocess.run([str(BEND), str(bend_src), "-o", str(out_js)],
                       capture_output=True, text=True, timeout=3600)
    said = r.stdout + "\n".join(
        l for l in r.stderr.splitlines() if "is available: run bend update" not in l)
    if not out_js.exists():
        print(f"  {label:<12} NO BACKEND  bend rc={r.returncode}")
        for line in said.splitlines()[:7]:
            print("      | " + line)
        return None, said
    p = subprocess.run(["node", str(out_js)], capture_output=True, text=True, timeout=600)
    rows = {m[1]: m[2].strip() for m in map(ROW.match, p.stdout.splitlines()) if m}
    if p.returncode != 0 or len(rows) != len(cs):
        print(f"  {label:<12} node rc={p.returncode} rows {len(rows)}/{len(cs)} "
              f"-- REFUSING TO COUNT IT")
        return None, said
    return rows, said


for bind in ("<-", "="):
    print(f"\n{'=' * 78}\nBIND {bind!r}\n{'=' * 78}")
    with tempfile.TemporaryDirectory() as td:
        work = pathlib.Path(td) / "tree"
        work.mkdir()
        shutil.copytree(tree / "tinybendygrad", work / "tinybendygrad")
        work.joinpath("f32.bend").write_text(emit_for(bind))
        base, said = compile_and_run(work, cs, "shipped")
        (out / f"bind{bind}.shipped.said").write_text(said)
        if base is None:
            report["arms"][f"bind{bind}"] = "GATE CANNOT REACH A VERDICT"
            continue
        # ---- STEP 1: THE LANE ASSERTION, BEFORE ANY PLANT IS PLANTED.
        js = work.joinpath("f32.js").read_text()
        toks = {t: js.count(t) for t in
                ("of32", "bits32", "fp8_decode", "i64_of", "pack64", "dtype.js", "dtype.c")}
        disk = {t: pristine.count(t) for t in ("of32", "bits32", "fp8_decode",
                                               "i64_of", "pack64")}
        print("  STEP 1 -- IS THE LANE IN THE ARTIFACT?  (shipped probe, compiled)")
        print(f"    {'':<12} {'emitted probe':>14} {'dtype.js on disk':>18}")
        for t, n in toks.items():
            print(f"    {t:<12} {n:>14} {disk.get(t, ''):>18}")
        live = toks["of32"] + toks["bits32"]
        verdict = ("LANE PRESENT: the tokens the plants edit are in the artifact"
                   if live else "LANE ABSENT: `of32` and `bits32` are BOTH 0 in the "
                   "emitted probe, so NO plant or break can reach them")
        print(f"    -> {verdict}")
        report.setdefault("lane_assertion", {})[f"bind{bind}"] = {
            "emitted": toks, "on_disk": disk, "verdict": verdict}
        # ---- STEP 2: PLANTS AND DISARMS.
        arms: dict[str, str] = {"shipped": pristine}
        for s in "ABC":
            arms[f"disarm-{s}"] = g.swap(pristine, *g.DISARMS[s])
            arms[f"plant-{s}"] = g.swap(pristine, *g.PLANTS[s])
        res = {}
        for a, text in arms.items():
            if a == "shipped":
                res[a] = base
                continue
            work.joinpath("tinybendygrad/runtime/dtype.js").write_text(text)
            work.joinpath("f32.bend").write_text(emit_for(bind))
            r, _ = compile_and_run(work, cs, a)
            if r is None:
                print(f"  {a:<12} arm refused -- it contributes an ABSENCE, not a count")
            res[a] = r
        print("  STEP 2 -- MOVED ROWS, shipped vs each arm")
        moved = {}
        for a in arms:
            if a == "shipped" or res.get(a) is None:
                continue
            mv = [n for n in names if base[n] != res[a][n]]
            moved[a] = len(mv)
            note = f"   e.g. {mv[:2]}" if mv else (
                "   (the only correct count)" if a.startswith("disarm")
                else "   ** A PLANT THAT MOVED NOTHING -- IT PROVES NOTHING")
            print(f"    {a:<12} moved {len(mv):>3}/{len(cs)}{note}")
        report["arms"][f"bind{bind}"] = moved
(out / "plant-measure.json").write_text(json.dumps(report, indent=1))
print(f"\nwrote {out / 'plant-measure.json'}")