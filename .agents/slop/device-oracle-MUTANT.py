#!/usr/bin/env python3
"""device-oracle-MUTANT.py -- device-oracle.py with EXACTLY ONE LINE CHANGED, for the
control that must show the device.bend lane able to go RED.

⚠ WHY A SEPARATE FILE AND NOT A FLAG. `rebase-gate.py --oracle` looks like the way to plant a
disagreement without editing anything, and it is a NO-OP: main() calls targets_of(), which
snapshots `tuple(BASE_ORACLES.get(port, []))`, and only then applies
`BASE_ORACLES[port] = [a.oracle]`. The loop iterates the snapshot. Measured on this tree,
`--port tinybendygrad/device.bend --oracle <anything>` prints `[oracle-override] ...` and then
answers `NOT-STARTED: no oracle wired in BASE_ORACLES`, and for an already-wired port it runs
the BASE oracle anyway. REPORTED, NOT FIXED (rebase-gate.py is another unit's file mid-edit),
so the control plants by pointing BASE_ORACLES at THIS file and restores the entry after.

THE ONE LINE. `row("allow_lower", allowed(False, "python:1"))` becomes ... 0. Not a swapped
constant, not a deleted row, and not a truncated lane: the planted disagreement must be
ORDINARY -- the port right, one oracle answer wrong -- because that is the shape a stale
hand-typed expectation takes, and that is the shape this control exists to catch. A mutant
that raised would be caught by GUARD 3 (a dead lane) and would prove nothing about GUARD 4.

It is the SAME ROW the port fix moved. device.py:30 rebinds `ix = self.canonicalize(ix)` and
:31 asserts on the rebound value, so CPython answers 1 for a lowercase spelling; the port
shipped `allowed(allow, ix)` -- a transcription of the assert STATEMENT, which structurally
cannot see the rebind -- and answered 0. `device_usage` is now `allowed(allow, canon(ix))`.
So this control fails if and only if that fix regresses, which is why it is worth the file.

Everything else is device-oracle.py byte for byte: it calls Device._canonicalize,
ALL_DEVICES, is_disk_device and Device[ix] under Context(ALLOW_DEVICE_USAGE=..), so every
other row is still real CPython and the planted row is the only disagreement by construction.
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REAL = HERE / "device-oracle.py"

PLANT_FROM = '  row("allow_lower", allowed(False, "python:1"))'
PLANT_TO = '  row("allow_lower", 0)  # PLANTED for the control: the ONE wrong answer'


def main():
  src = REAL.read_text()
  if src.count(PLANT_FROM) != 1:
    raise SystemExit(f"REFUSING: {PLANT_FROM!r} occurs {src.count(PLANT_FROM)} times in "
                     f"{REAL.name}, not exactly once. A mutant that plants something other "
                     "than the one row cannot be read as a one-row control.")
  out = src.replace(PLANT_FROM, PLANT_TO)
  # Prove the delta is ONE line, not one line that happens to look like it.
  changed = [(i, a, b) for i, (a, b) in enumerate(zip(src.splitlines(), out.splitlines()), 1)
             if a != b]
  if len(src.splitlines()) != len(out.splitlines()) or len(changed) != 1:
    raise SystemExit(f"REFUSING: the mutation changed {len(changed)} lines and "
                     f"{len(src.splitlines())}->{len(out.splitlines())} lines, not 1 and 1.")
  print(f"# ONE LINE CHANGED from {REAL.name}: line {changed[0][0]}", file=sys.stderr)
  print(f"#   - {changed[0][1]}", file=sys.stderr)
  print(f"#   + {changed[0][2]}", file=sys.stderr)
  exec(compile(out, str(REAL), "exec"), {"__name__": "__main__", "__file__": str(REAL)})


if __name__ == "__main__":
  main()
