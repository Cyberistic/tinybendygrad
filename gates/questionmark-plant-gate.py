#!/usr/bin/env python3
"""THE PLANT FOR `graphcmp.py`'s `?=0` REGRESSION ROW, AND WHY IT IS A PORT PLANT.

THE ROW. `selfcheck` asserts `dict(ledger(bend_loop_rows(dev)))["?"] == 0` on `--graph loop`
(`graphcmp.py:2938`). It pinned `?=32` until `f251d80d` gave `dt_of` a `(dt, None)` arm, and a
`?=0` row is exactly the shape that cannot fail: `artefacts_ok()` reported zero on a directory
holding nothing, and a plant was once scored as successful while it made the lane emit NOTHING.

WHY NOT ONE OF `graphcmp.py`'s OWN PLANTS. `PLANTS` is applied by `emit_py`, and
`bend_loop_rows` calls `emit_bend(dev, "loop")`, which takes NO plant -- so every py-side plant
is structurally UNREACHABLE from a bend-side measurement, not merely wrong. MEASURED: `loop`'s
census is `BUFFER=3` and carries NO `ALLOC` and NO `STACK`, so `plant_dtype` is a no-op and
`plant_shape` asserts on a STACK that is not there. `f251d80d` recorded the same fact as
"`--plant dtype` on `loop` is VACUOUS". The plant has to be on the PORT.

THE PLANT IS THE EXACT INVERSE OF `f251d80d`, ONE LINE. Reverting `dt_of`'s `None` arm in a
COPY of the port and re-emitting `loop` gives `?=32`; the same machinery on the UNMUTATED copy
gives `?=0`. So 32 is known to be CAUSED by that arm rather than observed beside it. MEASURED
2026-10-19: both lanes 52 rows, rc 0, control 772 MB peak RSS / 1.18 s, planted 845 MB / 1.11 s.

A COPY, AND NEVER THE LIVE TREE. `bin/bend` resolves `import ./../../tinybendygrad/...`
relative to the FILE's own directory, so a scratch tree carrying `.agents/slop/graphcmp.bend`
over its own `tinybendygrad/` runs a DIFFERENT PORT without editing one byte of the real one --
the same reason the 400 oracles under `.agents/slop/` mutate a copy.

THE DISARM, WHICH IS WHAT MAKES THE RED MEAN ANYTHING: `plant_disarm`'s rule, "a red with no
paired disarm proves nothing about where it landed". If the COPY itself perturbed the fold, the
control lane would move; it reads 0, so the 32 is the one line and not the copying.

A GATE THAT POINTS AT `.agents/slop/graphcmp.py`, AND WHY THAT IS NOT THE PRESCRIPTION THAT
DELETED SEVEN DRIVERS: this gate's SUBJECT is that file's row, so it resolves it BY NAME and
REFUSES (3) if it is absent rather than reading a private copy of the counter. The counter is
imported, never reimplemented -- a second `?` reader is a second claim about the same thing.
"""
import importlib.util
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED, ROOT, VERDICT  # noqa: E402

GCMP = ROOT / ".agents" / "slop" / "graphcmp.py"
PROBE = ROOT / ".agents" / "slop" / "graphcmp.bend"

# THE PLANT AS TWO WHOLE LINES AND NOT A FRAGMENT, so an unrelated `case None{}` cannot match.
# `f251d80d`'s diff is exactly the second line replacing the first.
ARMED = "    case None{}: Some{DtShape{dt, None{}}}"
DISARMED = "    case None{}: None{}"


def load():
  """The INSTRUMENT, not a copy of it: `emit_bend`'s `probe=` parameter exists for exactly
  this -- pointing the emitter at a driver other than `BEND_PROBE` -- so the retry guard, the
  0-row trap and `classify` are all exercised rather than reimplemented."""
  if not GCMP.is_file():
    raise FileNotFoundError(GCMP)
  spec = importlib.util.spec_from_file_location("graphcmp", GCMP)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def stage(root: Path, revert: bool) -> Path:
  """A scratch tree whose `graphcmp.bend` imports its OWN `tinybendygrad/`, one level up twice
  exactly as the live one does. `revert=False` is the DISARM: identical machinery, no edit."""
  slop = root / ".agents" / "slop"
  slop.mkdir(parents=True)
  shutil.copytree(ROOT / "tinybendygrad", root / "tinybendygrad")
  shutil.copy(PROBE, slop / "graphcmp.bend")
  fold = root / "tinybendygrad" / "uop" / "fold.bend"
  if revert:
    text = fold.read_text()
    if text.count(ARMED) != 1:
      raise SystemExit(f"PLANT STALE: `dt_of`'s None arm is not the one line `f251d80d` wrote "
                       f"({text.count(ARMED)} occurrences of {ARMED!r}) -- re-measure the "
                       f"plant, do not widen it")
    fold.write_text(text.replace(ARMED, DISARMED))
  return slop / "graphcmp.bend"


def measure(gc, dev: str, probe: Path) -> tuple[int, int]:
  rows = gc.emit_bend(dev, "loop", probe=probe)[0]
  return dict(gc.ledger(rows))["?"], len(rows)


def main() -> int:
  try:
    gc = load()
  except FileNotFoundError as exc:
    print(f"REFUSED, NOT A VERDICT: the instrument is absent: {exc}")
    return REFUSED
  dev = sys.argv[1] if len(sys.argv) > 1 else "CPU"
  bad = []
  with tempfile.TemporaryDirectory() as tmp:
    # BOTH LANES BUILT BEFORE EITHER RUNS, so the control cannot be scored against a tree the
    # plant has already touched.
    ctrl = measure(gc, dev, stage(Path(tmp) / "control", revert=False))
    plant = measure(gc, dev, stage(Path(tmp) / "plant", revert=True))
  (cq, cn), (pq, pn) = ctrl, plant
  print(f"control rows={cn} ?={cq}    planted rows={pn} ?={pq}")
  if cq != 0:
    bad.append(f"the UNMUTATED copy already reads ?={cq} on `--graph loop`: either the PORT has "
               f"regressed (the row in graphcmp.py is red for a real reason -- run selfcheck) or "
               f"COPYING the tree perturbs the fold, and this gate cannot tell those apart")
  if (cq, cn) != (0, 52):
    bad.append(f"the control lane is ({cn} rows, ?={cq}), not (52, 0)")
  if (pq, pn) != (32, 52):
    bad.append(f"the PLANTED lane is ({pn} rows, ?={pq}), not (52, 32) -- the plant did not put "
               f"`?` back, so the `?=0` row in graphcmp.py is a claim nothing can break")
  print(f"questionmark-plant: {VERDICT[FAIL if bad else PASS]}")
  for b in bad:
    print(f"  {b}")
  return FAIL if bad else PASS


if __name__ == "__main__":
  sys.exit(main())