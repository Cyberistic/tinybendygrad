#!/usr/bin/env python3
"""ew_activation-gate.py -- THE GATE over the port's ACTIVATION FAMILY.

    .venv/bin/python gates/ew_activation-gate.py              # both lanes
    .venv/bin/python gates/ew_activation-gate.py --no-plants  # the live comparison only
    .venv/bin/python gates/ew_activation-gate.py --plants     # the plants only

WHAT IT GATES, IN TWO LANES, AND BOTH ARE MEASUREMENTS.

  LANE 1 -- THE LIVE COMPARISON.  The port builds a graph for each of the 255
  activation graphs (fifteen method/parameter sets over seventeen fixtures) and the
  graph is put in the SAME CANONICAL FORM as CPython's and compared node by node;
  then the port's own graph is REBUILT as tinygrad UOps and realized, and its value
  is compared with CPython's, bit for bit.  A disagreement in EITHER is a FAIL.

  LANE 2 -- THE PLANTS.  Every way the port could be wrong is re-introduced on a COPY
  of the port's own source and the comparison is asked whether it SEES it.  A PLANT
  THAT DOES NOT MOVE THE COMPARISON IS A HOLE IN THE COMPARISON, and a hole is not a
  pass.

WHY LANE 2 IS NOT OPTIONAL.  A comparison that answers "the port agrees with CPython"
is worth nothing on its own: an instrument that compares nothing also agrees with
everything.  LANE 2 is what makes LANE 1 mean something, and it is what found the two
real defects this tree had:

  `uop/fold.bend`'s `least_upper_float` had NO `CWeakFloat` arm.  CPython's `is_float`
  is `dt.kind == 'f'` and a WEAK FLOAT's kind is 'f', so `least_upper_float(weakfloat)`
  IS `weakfloat`; the port's `CFloat` arm is the STRONG float class, so a weakfloat
  fell through to `case _` and came back `float32`.  MEASURED: **238 of 255 rows** and
  the difference was THREE `CAST f32` nodes that upstream does not have -- in every
  already-ported method that uses a unary ALU (`sigmoid`, `tanh`, `quick_gelu`,
  `swish`, `silu`).  **NO GATE COULD SEE IT, because every one of those gates'
  fixtures is an INT.**

  `mixin/elementwise.bend`'s `ew_tanh` had its operands in the wrong order, so the
  port computed `sigmoid(2*self) * self - 1.0` where upstream computes
  `2*sigmoid(2*self) - 1.0`.  MEASURED: the port's `tanh(0.5)` was
  `-0.6344707012176514` and CPython's is `0.46211719512939453`; the port's `tanh(0.0)`
  was `-1.0` and CPython's is `0.0`.  **THE CENSUS'S `ew_tanh` ROW CANNOT SEE IT** --
  it prints the ROOT's src ops, and the root is the ADD of `sub` either way
  (`Ops.MUL Ops.MUL`).

THE GRAPH-ONLY ARM IS THE ONE NOBODY EXPECTS, AND IT IS THE ONE THAT BITES.  ONE PLANT
MOVES 51 GRAPH ROWS AND **ZERO** VALUE ROWS: `a = s * self` built as `self * s` is a
COMMUTATIVE MUL, so the number is the same and the GRAPH is not.  A comparison that
only read VALUES would have missed it, and so would the census's signature row.  LANE 2
ASSERTS THAT AT LEAST ONE PLANT MOVES GRAPH ROWS AND NO VALUE ROWS, because if none
did then the canonical graph diff would be redundant with a value comparison and the
whole point of this gate would be gone.

THE CONSTANTS ARE COMMITTED AT `float32` ON BOTH LANES, AND THAT LOOKS WRONG ON THE
PYTHON DEVICE.  **DO NOT "FIX" IT.**  Upstream's `asin` names `math.pi / 2`, a DOUBLE;
the port has no F64 and names `f32(math.pi / 2)`.  MEASURED: with the constant left in
DOUBLE the two differ by EXACTLY ONE ULP at some inputs -- **29 of the 255 rows** on
the double-precision PYTHON device -- and swapping the constant's value in CPython's OWN
graph is what moves it.  MEASURED TOO: tinygrad's own generated float32 kernel writes
`1.5707963705062866f`, the f32-exact value with an `f` suffix, so on a REAL float32
device upstream's constant and the port's are THE SAME NUMBER.  The comparison
therefore commits the weak float constants at `float32` on BOTH lanes, which is what a
float32 device does.  See `gates/ew_activation-compare.py`'s `commit()`.

WHERE THE INPUTS LIVE, AND WHY.  `gates/README.md`: "a gate's `.bend` driver and its
CPython oracle sit in `gates/`, named by the gate that needs them", because a sweep of
`.agents/slop/` deleted seven of nine driver/oracle files out from under gates that
were still naming them, and every one of those gates went red on `no such file` rather
than on a value.  **THE INSTRUMENT THAT FOUND THESE TWO DEFECTS WAS ITSELF UNTRACKED IN
`.agents/slop/`, AND THE TREE HAS ALREADY LOST `worker_oracle.py` THAT WAY.**  So the
driver, the oracle, the comparison, the plants and the expected values are all in
`gates/`, beside this file, IN GIT.

EXIT STATUS: 0 both lanes pass · 1 a lane disagreed · 3 a precondition was absent (no
toolchain, the driver did not compile, the comparison refused) · 4 the plant lane was
skipped by `--no-plants` and that is REPORTED AND NOT A PASS.
"""
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from bendlock import bend_lock  # noqa: E402
from gatekit import ART, DEAD, FAIL, PASS, REFUSED, SKIP, VERDICT  # noqa: E402

NAME = "ew_activation-gate"
OUT = ART / NAME
DRIVER = HERE / "ew_activation.bend"
ORACLE = HERE / "ew_activation-oracle.py"
COMPARE = HERE / "ew_activation-compare.py"
PLANT = HERE / "ew_activation-plant.py"
PINS = HERE / "ew_activation-pins.rows"
PY = ROOT / ".venv" / "bin" / "python"
BEND = ROOT / "bin" / "bend"
BEND_MAIN = ROOT / "references" / "bend" / "bend2" / "main.ts"

SUMMARY = re.compile(r"^SUMMARY graph_rows=(\d+) graph_differing=(\d+) value_rows=(\d+) "
                     r"value_differing=(\d+) selfcheck_rows=(\d+) selfcheck_disagreeing=(\d+)$",
                     re.M)


def say(msg: str) -> None:
  print(f"{NAME}: {msg}", file=sys.stderr)


def live_lane() -> int:
  """LANE 1: THE PORT'S OWN GRAPH against CPython's, on the WORKING COPY."""
  if not BEND_MAIN.is_file():
    say(f"REFUSED: no toolchain at {BEND_MAIN} -- `references/` is gitignored, so a clone "
        f"without it cannot compile anything")
    return REFUSED
  # THE OUTPUT DIRECTORY IS EMPTIED FIRST.  `gates/gatekit.py`'s own reason: a run that
  # failed used to leave the PREVIOUS run's `bd.out` exactly where it was, so a reader
  # diffing it after a RED run was diffing the last GREEN run.
  OUT.mkdir(parents=True, exist_ok=True)
  for p in OUT.iterdir():
    if p.is_file():
      p.unlink()
  port_rows = OUT / "bd.out"
  with bend_lock() as waited:
    if waited:
      say(f"waited {waited}s for the bend lock")
    r = subprocess.run([str(BEND), str(DRIVER)], cwd=ROOT, capture_output=True, text=True)
  port_rows.write_text(r.stdout)
  if r.returncode != 0:
    said = "\n".join(l for l in (r.stderr or "").splitlines()
                     if l.strip() and not l.startswith("bend "))
    say(f"the driver did not compile (rc={r.returncode}); the port is not measurable "
        f"right now: {said[-400:]}")
    return REFUSED
  if not port_rows.read_text().strip():
    say("the driver ran and emitted no rows")
    return DEAD
  cpy_rows = OUT / "py.rows"
  with open(cpy_rows, "w") as f:
    o = subprocess.run([str(PY), str(ORACLE), str(port_rows)], stdout=f,
                       stderr=subprocess.PIPE, text=True)
  if o.returncode != 0:
    say(f"the oracle failed rc={o.returncode}: {(o.stderr or '').strip()[-300:]}")
    return REFUSED
  c = subprocess.run([str(PY), str(COMPARE), str(port_rows), str(cpy_rows)],
                     capture_output=True, text=True)
  # THE COMPARISON'S OWN OUTPUT IS PRINTED AND NOT STORED.  `gates/retention-check.py`
  # clause I holds a gate's output directory to the SEVEN names `gates/gatekit.py` may
  # write, and a file outside that set is RESIDUE -- so this gate writes `bd.out` and
  # `py.rows` and NOTHING else, and everything else it has to say it says HERE.
  for line in (c.stdout + c.stderr).splitlines():
    print(line)
  m = SUMMARY.search(c.stdout)
  if not m:
    say("the comparison printed no SUMMARY line -- it refused")
    return REFUSED
  rows, gd, vrows, vd, sc, scd = (int(x) for x in m.groups())
  say(f"LANE 1 live comparison: graph rows={rows} differing={gd} | value rows={vrows} "
      f"differing={vd} | selfcheck rows={sc} disagreeing={scd}")
  if c.returncode == 0:
    return PASS
  if c.returncode == 1:
    return FAIL
  say(f"the comparison refused (rc={c.returncode})")
  return REFUSED


def plant_lane() -> int:
  """LANE 2: every way the port could be wrong, re-introduced on a COPY, and the
  comparison asked whether it SEES it."""
  if not PINS.is_file():
    say(f"REFUSED: {PINS} is missing -- a plant harness with no expected values asserts "
        f"nothing, and its expected values are its INPUT")
    return REFUSED
  r = subprocess.run([str(PY), str(PLANT)], cwd=ROOT, capture_output=True, text=True)
  for line in r.stdout.splitlines():
    print(line)
  if r.stderr.strip():
    for line in r.stderr.splitlines():
      print(line, file=sys.stderr)
  if r.returncode == 0:
    return PASS
  if r.returncode == 1:
    return FAIL
  say(f"the plants refused (rc={r.returncode})")
  return REFUSED


def main(argv) -> int:
  only_plants = "--plants" in argv
  no_plants = "--no-plants" in argv
  OUT.mkdir(parents=True, exist_ok=True)
  code = PASS
  if not only_plants:
    c = live_lane()
    if c != PASS:
      code = c
  if not no_plants:
    c = plant_lane()
    if c != PASS and code == PASS:
      code = c
  if no_plants and not only_plants:
    print("== SKIPPED: the plant lane was not run (`--no-plants`), and a SKIP IS NOT A PASS")
    return SKIP
  if code == PASS:
    print(f"{NAME}: PASS -- the port's activation family builds CPython's graphs node for "
          f"node and computes CPython's values bit for bit, and every one of the ten plants "
          f"is still DETECTED (the expected values are in {PINS.name}, beside this gate)")
  else:
    print(f"{NAME}: {VERDICT[code]}")
  return code


if __name__ == "__main__":
  sys.exit(main(sys.argv))
