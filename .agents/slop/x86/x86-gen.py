#!/usr/bin/env python3
"""x86-gen.py -- rewrite the `Gate.rowsN()` chunks of `tinybendygrad/renderer/isa/x86.bend`
from `.agents/slop/x86/x86-oracle.py gate`, and re-derive the `Gate.rows()` join.

The gate is GENERATED (`device.bend` and `renderer/__init__.bend` do the same for their
own rows) because seventy-four of its rows are CPython's `encode()` bytes and typing
those is how `ops_nv` shipped 33 wrong constants behind 590 green rows.

    .venv/bin/python .agents/slop/x86/x86-gen.py            # rewrite the chunks
    .venv/bin/python .agents/slop/x86/x86-gen.py --check    # would it change anything

`--check` exits 1 when the file is stale, which is the only exit status in this unit
that means anything: `--check-only` on the .bend exits 1 even when it is clean.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TARGET = ROOT / "tinybendygrad/renderer/isa/x86.bend"
ORACLE = ROOT / ".agents/slop/x86/x86-oracle.py"

START = re.compile(r"^def Gate\.rows0\(\) -> List<&2, String>: \[$")
END = re.compile(r"^def main\(\) -> IO\(Unit\):$")


def main():
  src = subprocess.run([str(ROOT / ".venv/bin/python"), str(ORACLE), "gate"],
                       capture_output=True, text=True, check=True).stdout.rstrip("\n")
  n = src.count("def Gate.rows")
  body = src + "\n".join([
    "",
    "# THE TABLE, IN CHUNKS. `String.concat` is ONE `IO.print` over 700 arguments and the",
    "# parser refuses it, and a fold over a list of row-strings would cost a step per row.",
    "# %d list literals joined by `List.concat` is the shape that compiles and is one" % n,
    "# `IO.print`.",
    "",
    "def Gate.rows() -> List<&2, String>:",
    "  List.concat(&2, String, [" + ", ".join(f"Gate.rows{i}()" for i in range(n)) + "])",
    "",
  ])
  lines = TARGET.read_text().split("\n")
  lo = next(i for i, l in enumerate(lines) if START.match(l))
  hi = next(i for i, l in enumerate(lines) if END.match(l))
  new = lines[:lo] + body.split("\n") + lines[hi:]
  if new == lines:
    print("clean")
    return 0
  if "--check" in sys.argv:
    print(f"STALE: {TARGET.relative_to(ROOT)} would change at lines {lo + 1}..{hi + 1}")
    return 1
  assert hi > lo, f"chunk block {lo + 1}..{hi + 1} is inverted"
  TARGET.write_text("\n".join(new))
  print(f"rewrote {hi - lo + 1} lines -> {len(body.split(chr(10)))} lines, {n} chunks")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
