#!/usr/bin/env python3
"""wire-measure.py -- measure ONE port/oracle pair through rebase-scan-oracles.py, and print
every shared row by name.

WHY A SEPARATE FILE. `--oracle` on rebase-gate.py is a NO-OP: main() calls targets_of(),
which SNAPSHOTS `tuple(BASE_ORACLES.get(port, []))`, and only THEN applies
`BASE_ORACLES[port] = [a.oracle]`. The loop iterates the snapshot, so an override never
reaches a lane. Measured against the live tree, not read off the source:
  --port tinybendygrad/device.bend --oracle .agents/slop/device-oracle.py
    -> `[oracle-override] ... -> device-oracle.py` then
       `NOT-STARTED  ... no oracle wired in BASE_ORACLES`
i.e. the flag printed its own confirmation and changed nothing. The flag's docstring says
its whole reason for existing is proving a planted disagreement WITHOUT editing the gate,
and it cannot do that for any port, wired or not.

So measurement goes through rebase-scan-oracles.py's own `bend_rows`/`oracle_rows` --
the SAME reader `measure_roster()` uses -- and prints the shared NAMES, because a count
alone cannot tell "23 rows agree" from "23 of 110 rows agree and the other 87 were never
compared". Usage:

    .venv/bin/python .agents/slop/wire-measure.py <port.bend> <oracle-spec>
"""
import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def load(name, path):
  spec = importlib.util.spec_from_file_location(name, path)
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


def main():
  if len(sys.argv) != 3:
    raise SystemExit(__doc__.strip().splitlines()[-1])
  port, oracle = sys.argv[1], sys.argv[2]
  scan = load("wire_measure_scan", HERE / "rebase-scan-oracles.py")
  b, o = scan.bend_rows(port), scan.oracle_rows(oracle)
  shared = sorted(set(b) & set(o))
  dis = [(k, b[k], o[k]) for k in shared if b[k] != o[k]]
  print(f"port   {port}: {len(b)} rows")
  print(f"oracle {oracle}: {len(o)} rows")
  print(f"shared {len(shared)}   disagree {len(dis)}")
  for k, bv, ov in dis:
    print(f"  DISAGREE {k}: bend={bv!r} oracle={ov!r}")
  print("--- shared rows ---")
  for k in shared:
    print(f"  {k} = {b[k]}" + ("   <<< DISAGREES" if b[k] != o[k] else ""))
  print("--- port-only (never compared) ---")
  for k in sorted(set(b) - set(o)):
    print(f"  {k} = {b[k][:70]}")
  print("--- oracle-only (never compared) ---")
  for k in sorted(set(o) - set(b)):
    print(f"  {k} = {o[k][:70]}")
  return 1 if dis or not shared else 0


if __name__ == "__main__":
  sys.exit(main())
