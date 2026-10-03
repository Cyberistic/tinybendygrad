#!/usr/bin/env python3
"""wire-lanes.py -- ALL THREE LANES of one port compared pairwise, counts only.

rebase-gate.py compares every lane pair (GUARD 4) and reports the disagreements, but it only
runs for a port that is already in BASE_ORACLES, and it prints a verdict for the whole port.
This is the pre-flight for a CANDIDATE wire: it runs the interpreted lane, the compiled native
lane and the oracle, and prints the three row counts and the three pairwise agreement counts.

It prints COUNTS AND NAMES and never a row value, because the first version of this printed
whole row dicts and a single `state_RDNA3` row is 512 bytes of digits -- the one number a reader
needs (`disagree=0`) was at the far end of ten thousand characters of noise.

The "five ports" sentence below is a past-tense account of one malformed invocation. It is
not a standing census and it is not re-checked. Do not treat it as a control.

`--names` prints the disagreement names only, for a lane that is NOT clean.

  usage: python3 .agents/slop/wire-lanes.py PORT ORACLE_SPEC
"""
import pathlib, subprocess, sys, tempfile

from wire_parse import rows, stripped_env

REPO = pathlib.Path(__file__).resolve().parents[2]


def sh(*a, **kw):
  return subprocess.run(a, cwd=REPO, capture_output=True, text=True, timeout=1800, **kw)


def bend_lane(port, native):
  if native:
    with tempfile.TemporaryDirectory() as td:
      b = pathlib.Path(td) / "out.bin"
      c = sh("./bin/bend", port, "-o", str(b))
      if c.returncode or not b.exists():
        return None, f"compile failed: {' '.join(c.stderr.split())[-160:]}"
      b.chmod(0o755)
      r = sh(str(b))
      return rows(r.stdout), None if r.returncode == 0 else r.stderr[-160:]
  return rows(sh("./bin/bend", port).stdout), None


def main():
  a = sys.argv[1:]
  port, spec = a[0], a[1]
  argv = spec.split()
  names = "--names" in a
  interp, e1 = bend_lane(port, False)
  nat, e2 = bend_lane(port, True)
  o = subprocess.run([sys.executable, *argv], cwd=REPO, capture_output=True, text=True,
                     env=stripped_env({"DEV": "NULL"}), timeout=1800)
  ora = rows(o.stdout)
  lanes = {"interpreted": interp, "native": nat, "oracle": ora}
  print(f"{port}")
  for k, v in lanes.items():
    print(f"  {k:<13} rows={len(v) if v is not None else 'NONE'}"
          + (f"  ({e1 if k == 'interpreted' else e2})" if v is None else ""))
  print(f"  oracle rc={o.returncode}"
        + (f"  stderr: {' '.join(o.stderr.split())[-200:]}" if o.returncode else ""))
  # AN EMPTY LANE IS NOT A PASS. Measured on this tool's first run: five ports were checked
  # with a MALFORMED argument list, both lanes came back empty, every pairwise comparison
  # reported shared=0 disagree=0, and the verdict line said CLEAN -- the same lie
  # rebase-gate.py's GUARD 2 exists to prevent, reproduced by a second instrument. A lane
  # with no rows compared nothing, so it is named BROKEN here before any verdict is printed,
  # and a pair that shares NO row name is reported as UNCOMPARABLE rather than as agreement.
  empty = [k for k, v in lanes.items() if not v]
  worst = 0
  keys = sorted(lanes)
  incomparable = []
  for i, x in enumerate(keys):
    for y in keys[i + 1:]:
      a1, a2 = lanes[x], lanes[y]
      if a1 is None or a2 is None:
        continue
      sh_ = set(a1) & set(a2)
      if not sh_:
        incomparable.append(f"{x}/{y}")
      bad = sorted(k for k in sh_ if a1[k] != a2[k])
      worst = max(worst, len(bad))
      print(f"  {x} vs {y}: shared={len(sh_)} disagree={len(bad)}"
            + ("  UNCOMPARABLE" if not sh_ else ""))
      if names:
        for k in bad:
          print(f"    {k}\n      {x:<13} {a1[k][:160]}\n      {y:<13} {a2[k][:160]}")
  if empty:
    print(f"  VERDICT: BROKEN -- lane(s) with ZERO rows: {', '.join(empty)}")
  elif incomparable:
    print(f"  VERDICT: BROKEN -- lane pair(s) sharing no row name: {', '.join(incomparable)}")
  elif worst:
    print(f"  VERDICT: RED ({worst} disagreement(s))")
  else:
    print("  VERDICT: CLEAN")
  return 0


if __name__ == "__main__":
  sys.exit(main())