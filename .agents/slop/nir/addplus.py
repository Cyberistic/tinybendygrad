#!/usr/bin/env python3
"""Add the `+` affix to whatever parameter Bend says was consumed more than once.

Bend params are affine unless prefixed `+` (renderer/__init__.bend convention 5),
and the compiler's "consumed more than once" error names the parameter -- but the
`Location:` line NUMBER it prints is the blank line ABOVE the `def`, not the def
line. Editing by that number silently changes nothing, which is what made the
first version of this script report 80 successes and fix zero errors.

So the def line is located by MATCHING it, and the number is only used to pick
the right `def` when the error names one.

  .venv/bin/python .agents/slop/nir/addplus.py tinybendygrad/renderer/nir.bend 80
"""
import re, subprocess, sys, pathlib

path = pathlib.Path(sys.argv[1])
budget = int(sys.argv[2]) if len(sys.argv) > 2 else 80
root = pathlib.Path(__file__).resolve().parents[3]
DEF = re.compile(r"def ([\w.]+)\((\w+):")

for step in range(budget):
  proc = subprocess.run(["./bin/bend", str(path), "--check-only"], cwd=root,
                        capture_output=True, text=True)
  txt = proc.stdout + proc.stderr
  lines = txt.splitlines()
  where = next((i for i, l in enumerate(lines) if l.startswith("Location:")), None)
  if "consumed more than once" not in txt or where is None:
    print(f"-- stopped at step {step}; compiler says:")
    print("\n".join(lines[:16]))
    break
  body = next((i for i in range(where + 1, len(lines))
               if DEF.search(lines[i].lstrip("0123456789 |>"))), None)
  if body is None:
    print("-- no def line under Location:\n" + "\n".join(lines[:16]))
    break
  m = DEF.search(lines[body].lstrip("0123456789 |>"))
  src = path.read_text().splitlines(keepends=True)
  idx = body - (where + 1) + int(lines[where].splitlines and 0)  # placeholder, fixed below
  # the compiler prints `NNN>| def ...`; recover NNN and use it as a cross-check
  num = re.match(r"^(\d+)", lines[body]).group(1)
  idx = int(num) - 1
  if f"+{m.group(2)}:" in src[idx]:
    print(f"-- {m.group(1)}.{m.group(2)} already affixed at line {idx+1}; stopping")
    print("\n".join(lines[:16]))
    break
  src[idx] = src[idx].replace(f"{m.group(2)}:", f"+{m.group(2)}:", 1)
  path.write_text("".join(src))
  print(f"  step {step}: +{m.group(2)} in {m.group(1)} (line {idx+1})")
