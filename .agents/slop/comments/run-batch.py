#!/usr/bin/env python3
"""**THE **BATCH **RUNNER** -- **GENERATE **THE **OPS**, **APPLY **THEM **WITH **`cut.py`**, **AND
**REPORT **THE **CUT**.

**⇒⇒† AND **IT **NEVER **WRITES **THE **`.bend` **FILES **ITSELF**: **⇒⇒† AND **`cut.py` **IS **THE
**ONLY **WRITER**, **⇒⇒† AND **IT **REFUSES **IF **A **NON-`#` **LINE **MOVED**.

**USAGE**: `run-batch.py uop/ops.bend` **⇒⇒† AND **IT **PRINTS **THE **CUT **AND **RETURNS **THE
**NEW **COMMENT **MASS**."""
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]

spec = importlib.util.spec_from_file_location("tp", HERE / "trim-plan.py")
tp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tp)


def mass(f: pathlib.Path):
  n = lines = 0
  for _i, _j, blk in tp.blocks(f):
    n += 1
    lines += len(blk)
  return n, lines


def main() -> int:
  rel = sys.argv[1]
  lim = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 4
  f = ROOT / "tinybendygrad" / rel
  before = mass(f)
  with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
    ops_path = tf.name
  try:
    r = subprocess.run(
      [sys.executable, str(HERE / "gen-ops.py"), rel, str(lim)],
      capture_output=True, text=True, cwd=ROOT)
    if r.returncode != 0:
      sys.stderr.write(r.stderr)
      return r.returncode
    pathlib.Path(ops_path).write_text(r.stdout)
    ops = json.loads(r.stdout)
    r2 = subprocess.run(
      [sys.executable, str(HERE / "cut-by-ordinal.py"), str(f), ops_path],
      capture_output=True, text=True, cwd=ROOT)
    sys.stdout.write(r2.stdout)
    sys.stderr.write(r2.stderr)
    if r2.returncode != 0:
      return r2.returncode
  finally:
    pathlib.Path(ops_path).unlink(missing_ok=True)
  after = mass(f)
  print(f"THE CUT {rel}: {before[0]} blocks/{before[1]} lines -> {after[0]} blocks/{after[1]} lines "
        f"(the cut: {before[1]-after[1]} lines, {len(ops)} blocks)")
  return 0


if __name__ == "__main__":
  sys.exit(main())
