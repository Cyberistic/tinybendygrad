#!/usr/bin/env python3
"""shader-gate.py -- BENCH the port's shader graph against CPython's, row for row.

    .venv/bin/python shaders/shader-gate.py            # PASS / FAIL / DEAD / REFUSED
    .venv/bin/python shaders/shader-gate.py --plant    # the gate must go RED

THE CLAIM: the anti-aliased circle in `shader.bend` is the same UOp graph as the one the
same formula builds in CPython tinygrad -- including the screen-space derivative, which is
`pad` + `shrink` and not an op the IR has.

WHY TWO LANES AND NO PIN. A pin would only be a second, weaker statement of the same thing:
the oracle's own drift is tinygrad's drift, and the corpus already pins the substrate by
sha256. A pin here would restate the substrate pin and rot independently of it.

THE VERDICTS ARE THE FIVE, WITH EXITS: PASS 0, FAIL 1, REFUSED 3, DEAD 5.
  REFUSED  bin/bend or .venv is absent, OR a lane printed an `arg` this fixture cannot
           render (`?`). Two unknown args agreeing is the "0 disagreements over 0
           comparisons" defect wearing a green shirt.
  DEAD     a lane printed NO ROWS. A lane that prints nothing is not a lane that agreed.
  FAIL     a row differs.

WHAT IS NORMALISED AND WHY. The only text the two sides spell differently is a float
constant: the port prints the EXACT f32 (`9.999999747378752e-05`) and CPython prints the
shortest repr of the double it was given (`0.0001`). Those are the same number to f32, so
the gate parses the constant and round-trips it through f32 before comparing -- ONE
normalisation, stated here, and not a lenient comparison.

THE PLANT IS THE POINT. `--plant` rewrites `SH_R()` in a COPY of `shader.bend` and runs THAT
copy, so the PORT's own graph moves and not the oracle's. A gate planted only on the oracle
side proves the comparer and not the port. A gate that cannot go red is a label, and this one
proves it can on every invocation that asks."""
import argparse
import os
import re
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BEND = ROOT / "bin" / "bend"
PY = ROOT / ".venv" / "bin" / "python"
PASS, FAIL, REFUSED, DEAD = 0, 1, 3, 5

CONST = re.compile(r"^ConstFloat\((.*)\)$")


def f32(text: str) -> str:
  try:
    return repr(struct.unpack("f", struct.pack("f", float(text)))[0])
  except ValueError:
    return text


def norm(row: str) -> str:
  d, op, dt, *rest = row.split(" ")
  arg = " ".join(rest)
  m = CONST.match(arg)
  return " ".join([d, op, dt, f"ConstFloat({f32(m.group(1))})" if m else arg])


def lane(cmd: list[str], env: dict[str, str]) -> tuple[list[str], str]:
  r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, env=env)
  if r.returncode != 0:
    return [], f"rc={r.returncode} {(r.stderr or r.stdout).strip()[:400]}"
  return [norm(l) for l in r.stdout.splitlines() if l and not l.startswith("#")], ""


def first_diff(a: list[str], b: list[str]) -> tuple[int, str, str] | None:
  for i, (x, y) in enumerate(zip(a, b)):
    if x != y:
      return i, x, y
  if len(a) != len(b):
    i = min(len(a), len(b))
    return i, a[i] if i < len(a) else "<eof>", b[i] if i < len(b) else "<eof>"
  return None


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--plant", action="store_true", help="mutate the shader and require FAIL")
  args = ap.parse_args()

  if not BEND.exists() or not PY.exists():
    print(f"REFUSED -- {'bin/bend' if not BEND.exists() else '.venv/bin/python'} is absent")
    return REFUSED

  env = dict(os.environ)
  target = HERE / "shader-rows.bend"
  if args.plant:
    # A PORT-SIDE PLANT. The copy sits in this folder so its relative imports still resolve,
    # and `SH_R` is the one line the plant rewrites -- a mutation of a parameter, not of the
    # formula, so the graph must move in exactly one CONST and nowhere else.
    src = target.read_text()
    assert "def SH_R() -> F32: 0.5" in src, "the plant's anchor moved; it rewrites SH_R"
    target = HERE / ".plant.bend"
    target.write_text(src.replace("def SH_R() -> F32: 0.5", "def SH_R() -> F32: 0.4"))
  bend, berr = lane([str(BEND), str(target)], env)
  py, perr = lane([str(PY), str(HERE / "shader-oracle.py")], env)
  if args.plant:
    target.unlink()
  print(f"bend={len(bend)} rows  cpython={len(py)} rows")

  for name, rows, err in (("bend", bend, berr), ("cpython", py, perr)):
    if err:
      print(f"{name.upper()}: {err}")
    if not rows:
      print(f"DEAD -- the {name} lane printed no rows: a lane that prints nothing did not agree")
      return DEAD
    unknown = [r for r in rows if r.endswith(" ?")]
    if unknown:
      print(f"REFUSED -- the {name} lane has {len(unknown)} unrenderable arg(s), first: {unknown[0]}")
      return REFUSED

  d = first_diff(bend, py)
  if args.plant:
    if d is None:
      print("PLANT DID NOT FIRE -- a changed RADIUS still agreed, so the gate compares nothing")
      return FAIL
    print(f"PLANT FIRED -- row {d[0]}: bend={d[1]!r} cpython={d[2]!r}")
    return PASS
  if d is not None:
    print(f"FAIL -- row {d[0]}: bend={d[1]!r} cpython={d[2]!r}")
    return FAIL

  # THE SECOND QUESTION. Graph parity says the two sides AGREE; it cannot say the formula is
  # a circle, and a shader that multiplies `fwidth` by zero agrees with its own oracle.
  v = subprocess.run([str(PY), str(HERE / "shader-oracle.py"), "--values"],
    cwd=ROOT, capture_output=True, text=True, env=env)
  print(v.stdout.strip())
  if v.returncode != 0:
    print("FAIL -- the formula is not a circle")
    return FAIL
  print(f"PASS -- {len(bend)} rows agree, including the fwidth subgraph, and the formula is a circle")
  return PASS


if __name__ == "__main__":
  sys.exit(main())
