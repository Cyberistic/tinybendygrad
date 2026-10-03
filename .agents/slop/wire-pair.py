#!/usr/bin/env python3
"""wire-pair.py -- ONE (port, oracle) pair: shared row names, and every disagreement NAMED.

This exists because a survey answers a different question. `rebase-scan-oracles.py` asks "does
this oracle share ANY row name with this port"; that is how a wire-up LIST is computed, and it
is not a verdict. Four things this adds, each of which has cost real time on this tree:

  * Every disagreement is named, with both values. "6 rows disagree" is a number to fix later;
    `PTX tensor_cores sm_75: bend [f16->f32] py=[half->float]` is a bug report, and the six
    disagreements that found the stale pre-rename dtype literals were only readable this way.
  * UNSHARED names are counted from BOTH sides. An oracle sharing 3 of 1042 rows gates 3 rows
    and its other 1039 are decoration; `ops_cpu` is wired that way and says so in its comment.
  * The oracle's exit status and its row count are reported SEPARATELY from the shared count,
    because GUARD 2 ("a lane that printed nothing compared nothing") is decided on the LANE and
    not on the intersection -- a shared count of 0 and a lane of 0 rows are different failures.
  * It says whether the port's rows are FULLY covered, because a lane that agrees on 3 of 353
    is a different claim from a lane that agrees on 353 of 353 even though both are green.

CONTROL. The instrument is only worth reading if it can fail. `wire-pair.py
tinybendygrad/renderer/tc_ptx.bend ".agents/slop/tcptx-oracle.py rows"` reports 6 disagreements
on the live tree and is kept as the standing control: if a run of this script ever reports 0
disagreements for that pair, this script has stopped working.

  usage: python3 .agents/slop/wire-pair.py PORT ORACLE_SPEC [ORACLE_SPEC...]
         PORT is a .bend path, ORACLE_SPEC is `path` or `path arg` exactly as BASE_ORACLES.
"""
import json, os, pathlib, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parents[2]
CACHE = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "rebase-wired-rows"


def rows(text):
  out = {}
  for line in text.splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k.strip()] = v.strip()
  return out


def bend_rows(port, tries=3):
  f = CACHE / (port.replace("/", "_") + ".json")
  if f.exists():
    return json.loads(f.read_text())
  for i in range(tries):
    r = subprocess.run(["./bin/bend", port], cwd=REPO, capture_output=True, text=True, timeout=1800)
    d = rows(r.stdout)
    if d:
      CACHE.mkdir(exist_ok=True)
      f.write_text(json.dumps(d))
      return d
    print(f"  ({port} printed 0 rows on attempt {i + 1})", file=sys.stderr)
  return {}


def run(argv, timeout=1800):
  try:
    return subprocess.run(argv, cwd=REPO, capture_output=True, text=True,
                          env=dict(os.environ, DEV="NULL"), timeout=timeout)
  except subprocess.TimeoutExpired:
    return None


def main():
  a = sys.argv[1:]
  port, specs = a[0], a[1:]
  b = bend_rows(port)
  print(f"{port}: {len(b)} rows")
  for spec in specs:
    argv = spec.split()
    r = run([sys.executable, *argv])
    if r is None:
      print(f"\n{spec}: TIMED OUT -- a probe that hangs is not an oracle")
      continue
    o = rows(r.stdout)
    shared = sorted(set(o) & set(b))
    bad = [k for k in shared if o[k] != b[k]]
    only_o, only_b = sorted(set(o) - set(b)), sorted(set(b) - set(o))
    print(f"\n{spec}")
    print(f"  rc={r.returncode} oracle_rows={len(o)} shared={len(shared)} disagree={len(bad)}"
          f"  oracle_only={len(only_o)} port_only={len(only_b)}"
          f"  {'PORT FULLY COVERED' if not only_b else 'PORT PARTLY COVERED'}")
    if r.returncode:
      print(f"  stderr: {' '.join(r.stderr.split())[-300:]}")
    for k in bad[:40]:
      print(f"  DISAGREE {k}\n    bend   {b[k][:220]}\n    oracle {o[k][:220]}")
    if len(bad) > 40:
      print(f"  ... {len(bad) - 40} more")
    if only_o and len(only_o) <= 15:
      print(f"    oracle-only: {only_o}")
    if only_b and len(only_b) <= 15:
      print(f"    port-only: {only_b}")
  return 0


if __name__ == "__main__":
  sys.exit(main())