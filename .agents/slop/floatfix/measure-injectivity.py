#!/usr/bin/env python3
"""THROWAWAY measurement: how many DISTINCT f32 patterns does the half-subnormal
class map onto, under (a) the pre-fix JS rule, (b) the post-fix JS rule, (c) the C
rule, (d) CPython's own codec?

The lanes come from `gates/subnormal-flush-gate.py` BY PATH (no second copy of the
shim, the extractor or the fixture), and the pre-fix file comes from `git show
HEAD:tinybendygrad/runtime/dtype.js`, so the "before" is the tree's own bytes and
not a transcription of them.
"""
import importlib.util
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location("sfg", ROOT / "gates" / "subnormal-flush-gate.py")
sfg = importlib.util.module_from_spec(spec)
sys.path.insert(0, str(ROOT / "gates"))
spec.loader.exec_module(sfg)

h2f = sfg.half_subnormals()
pos = [h for h in h2f if h < 0x8000]
neg = [h for h in h2f if h >= 0x8000]
print(f"population: {len(h2f)} half subnormals ({len(pos)} positive, {len(neg)} negative)")


def distinct(rows, keys):
    return len({rows[k] for k in keys})


def report(tag, rows):
    keys = [f"h2f_{h:x}" for h in pos]
    print(f"  {tag:<22} distinct over {len(pos)} positive = {distinct(rows, keys)}"
          f" | over all {len(h2f)} = {distinct(rows, [f'h2f_{h:x}' for h in h2f])}"
          f" | m=1 -> {rows['h2f_1']} | m=513 -> {rows['h2f_201']}"
          f" | m=512 -> {rows['h2f_200']} | m=1023 -> {rows['h2f_3ff']}")


ALL = list(h2f)


with tempfile.TemporaryDirectory() as tmp:
    work = pathlib.Path(tmp)
    fixed = (ROOT / "tinybendygrad" / "runtime" / "dtype.js").read_text()
    pre = subprocess.run(["git", "show", "HEAD:tinybendygrad/runtime/dtype.js"],
                         cwd=ROOT, capture_output=True, text=True, check=True).stdout
    csrc = (ROOT / "tinybendygrad" / "runtime" / "dtype.c").read_text()
    for tag, src in (("PRE-FIX (git HEAD)", pre), ("POST-FIX (worktree)", fixed)):
        rows = sfg.js_lane(work, src, ALL, [])
        report(f"JS {tag}", rows)
    rows = sfg.c_lane(work, csrc, ALL, [])
    report("C dtype.c", rows)
    rows = sfg.oracle_rows(ALL, [])
    report("CPython struct", rows)
