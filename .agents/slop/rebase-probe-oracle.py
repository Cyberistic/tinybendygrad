#!/usr/bin/env python3
"""rebase-probe-oracle.py -- is this (port, oracle) pair GATEABLE yet?

  For each pair: run the .bend (interpreted) and the oracle, and report
    rows_a rows_b shared disagree
  shared==0 is unwirable under GUARD 4 (lane pairs must share a row NAME); shared>0 with
  disagree>0 is a real finding to report, not to fix by editing a read-only port.

  usage: python3 .agents/slop/rebase-probe-oracle.py [--native]
"""
import pathlib, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parents[2]


def rows(text):
  out = {}
  for line in text.splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k.strip()] = v.strip()
  return out


def bend_rows(port, native=False):
  bend = REPO / port
  if native:
    out = pathlib.Path("/tmp/rebase-probe") / f"{bend.stem}.bin"
    out.parent.mkdir(exist_ok=True)
    b = subprocess.run(["./bin/bend", str(bend), "-o", str(out)], cwd=REPO,
                       capture_output=True, text=True)
    if b.returncode or not out.exists():
      return {}, f"compile rc={b.returncode} {b.stderr[-200:]}"
    out.chmod(0o755)
    r = subprocess.run([str(out)], cwd=REPO, capture_output=True, text=True)
    return rows(r.stdout), f"rc={r.returncode} {r.stderr[-200:]}"
  r = subprocess.run(["./bin/bend", str(bend)], cwd=REPO, capture_output=True, text=True)
  return rows(r.stdout), f"rc={r.returncode} {r.stderr[-200:]}"


def oracle_rows(spec):
  argv = spec.split()
  r = subprocess.run([sys.executable, *argv], cwd=REPO, capture_output=True, text=True,
                     env=dict(__import__("os").environ, DEV="NULL"))
  return rows(r.stdout), f"rc={r.returncode} {r.stderr[-200:]}"


def main():
  native = "--native" in sys.argv
  pairs = [ln.split("=", 1) for ln in sys.stdin.read().splitlines() if "=" in ln]
  print(f"{'port':<44} {'bend':>5} {'orac':>5} {'shar':>5} {'dis':>5}  note")
  for port, spec in pairs:
    a, an = bend_rows(port.strip(), native)
    b, bn = oracle_rows(spec.strip())
    shared = set(a) & set(b)
    dis = [k for k in shared if a[k] != b[k]]
    note = "" if not dis else "; ".join(f"{k}: bend={a[k]!r} py={b[k]!r}" for k in dis[:2])
    print(f"{port.strip():<44} {len(a):>5} {len(b):>5} {len(shared):>5} {len(dis):>5}  "
          f"{note or (an if not a else '') if not shared else note}")
    if len(shared) and dis:
      print(f"     bend keys sample: {sorted(a)[:4]}")
      print(f"     py   keys sample: {sorted(b)[:4]}")
  return 0


if __name__ == "__main__":
  sys.exit(main())