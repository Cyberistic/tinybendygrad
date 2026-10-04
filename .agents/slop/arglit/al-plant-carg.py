#!/usr/bin/env python3
"""al-plant-carg.py -- PLANT AND DISARM THE `carg` ARM, MEASURED, BOTH DIRECTIONS.

The landed arm is `if op in (Ops.CUSTOM, Ops.CUSTOMI): return f"in({bstr(x[0])},{dt(x[1])})"`
in `.agents/slop/graphcmp.py`. This script removes it, runs the verdict, restores it, runs
the verdict again, and PRINTS THE MD5 OF BOTH STATES so the restoration is proven rather
than asserted (NON-6).

`al-verdict.py` already carries a `pre-arm` mode that flips one predicate. This file is the
VERSION-LEVEL plant: it edits the real source, so it also catches the case where the arm is
present but the WRONG SHAPE -- which the in-memory flip cannot, because it only ever
subtracts the correct arm.

    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/arglit/al-plant-carg.py \
        .agents/slop/arglit/patir-AFTER.txt
"""
from __future__ import annotations

import hashlib
import os
import subprocess
import sys

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SRC = os.path.join(REPO, ".agents/slop/graphcmp.py")
# THE PROBE'S OUTPUT, NEVER THE PROBE. `al-patir.bend` is the source; `patir-AFTER.txt` is
# what `bend` printed from it. Passing the source here is a mistake this file made once and
# `al-verdict.py` now REFUSES (a source line has no `src:` field), so the failure is loud.
BEND = os.path.join(REPO, ".agents/slop/arglit/patir-AFTER.txt")
VERDICT = os.path.join(REPO, ".agents/slop/arglit/al-verdict.py")
PY = os.path.join(REPO, ".venv/bin/python")

HEAD = "  if op in (Ops.CUSTOM, Ops.CUSTOMI):\n"
BODY = '    return f"in({bstr(x[0])},{dt(x[1])})"\n'


def arm_span(src: str) -> tuple[int, int]:
  """The arm is located by its TWO executable lines, never by a copy of its prose: a
  transcribed comment block is exactly the kind of expectation that goes stale silently,
  and the first draft of this file pasted the comment and then refused to plant. MEASURED,
  that refusal is the correct behaviour and it is why this function exists."""
  i = src.find(HEAD)
  if i < 0:
    raise ValueError("head not found")
  j = src.find(BODY, i)
  if j < 0:
    raise ValueError("body not found")
  return i, j + len(BODY)


def md5(path: str) -> str:
  return hashlib.md5(open(path, "rb").read()).hexdigest()


def run(tag: str, bend_rows: str) -> tuple[int, str]:
  out = subprocess.run([PY, VERDICT, bend_rows, tag],
                       capture_output=True, text=True, cwd=REPO,
                       env={**os.environ, "PYTHONPATH": "", "LC_ALL": "C", "DEV": "CPU"})
  if out.returncode != 0:
    # SILENT is NOT A PASS. The first draft of this file printed `??` for a verdict that
    # never arrived and then reported a plant that moved 0 rows, which is precisely the
    # "an instrument that produced nothing must not be reported as a pass" trap.
    raise SystemExit(f"verdict run {tag} failed rc={out.returncode}:\n"
                     f"{out.stdout}\n{out.stderr}")
  return out.returncode, out.stdout + out.stderr


def verdict_line(s: str) -> str:
  line = next((l for l in s.splitlines()
               if l.startswith("# VERDICT ") and "field mismatches" in l), None)
  if line is None:
    raise SystemExit(f"no verdict line in:\n{s}")
  return line


def main() -> int:
  bend_rows = sys.argv[1] if len(sys.argv) > 1 else BEND
  src = open(SRC).read()
  try:
    i, k = arm_span(src)
  except ValueError as e:
    print(f"PLANT IMPOSSIBLE ({e}): the arm's two executable lines are not where this "
          f"instrument expects them. Refusing to report a pass.")
    return 2
  landed_md5 = md5(SRC)
  try:
    _, a = run("LANDED", bend_rows)
    print(f"# ARM LANDED   md5 {landed_md5}\n#   {verdict_line(a)}")
    # PLANT: the arm removed, nothing else touched.
    open(SRC, "w").write(src[:i] + src[k:])
    armed_md5 = md5(SRC)
    _, b = run("ARM-REMOVED", bend_rows)
    print(f"# ARM REMOVED  md5 {armed_md5}\n#   {verdict_line(b)}")
    # DISARM: restore and PROVE it, byte for byte.
    open(SRC, "w").write(src)
    back = md5(SRC)
    print(f"# RESTORED     md5 {back}  {'== LANDED' if back == landed_md5 else 'MISMATCH'}")
  finally:
    open(SRC, "w").write(src)  # the finally is the real guarantee, not the print
  ok = landed_md5 == md5(SRC) and "DISAGREE -- 2 field mismatches" in verdict_line(a) \
      and "DISAGREE -- 4 field mismatches" in verdict_line(b)
  print(f"#\n# THE PLANT MOVED {4 - 2} FIELD MISMATCHES AND THE DISARM RESTORED THEM:"
        f" {'YES' if ok else 'NO'}")
  return 0 if ok else 1


if __name__ == "__main__":
  sys.exit(main())
