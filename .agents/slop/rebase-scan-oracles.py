#!/usr/bin/env python3
"""rebase-scan-oracles.py -- find (port, oracle) pairs that can actually be GATED.

  GUARD 4 says two lanes must share at least one row NAME, so an oracle is only wireable if
  it prints `name=value` rows whose names COLLIDE with the ones its port prints. This measures
  that collision for every candidate oracle against every gated port, so the wire-up list is
  computed rather than guessed -- and so a pair that cannot be gated is named as unwirable
  rather than wired and left BROKEN.

  usage: python3 .agents/slop/rebase-scan-oracles.py [--probes P] [--ports P]
"""
import os, pathlib, re, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parents[2]
SLOP = REPO / ".agents" / "slop"
CACHE = pathlib.Path("/tmp/rebase-scan")


def rows(text):
  out = {}
  for line in text.splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k.strip()] = v.strip()
  return out


def run(argv, env=None, timeout=240):
  """A probe that hangs is NOT an oracle and must not stop the sweep.

  Measured: `nv_nvdev_gate.py` timed out at 900s and took the whole scan down with it, losing
  every result it had already computed -- a scan that dies on its third probe reports nothing
  about the first two. A probe that exceeds its budget is recorded as no rows and named."""
  try:
    return subprocess.run(argv, cwd=REPO, capture_output=True, text=True, timeout=timeout,
                          env=env)
  except subprocess.TimeoutExpired:
    print(f"  (probe timed out after {timeout}s, treated as emitting no rows: {argv[1]})")
    return None


def bend_rows(port):
  CACHE.mkdir(exist_ok=True)
  f = CACHE / (port.replace("/", "_") + ".json")
  if f.exists():
    import json
    return json.loads(f.read_text())
  r = run(["./bin/bend", str(REPO / port)], timeout=600)
  # 0 rows is INDISTINGUISHABLE from "this port has no main", and bend's machine stack
  # overflows on roughly 1 run in 20 and sometimes prints ZERO rows. A probe that reports 0
  # rows is therefore re-run once before being believed, and a second 0 is believed.
  d = rows(r.stdout) if r is not None else {}
  if not d and r is not None:
    r2 = run(["./bin/bend", str(REPO / port)], timeout=600)
    d2 = rows(r2.stdout) if r2 is not None else {}
    print(f"  ({port} printed 0 rows, re-ran: {len(d2)})" if d2 else
          f"  ({port} printed 0 rows twice -- trusting it)")
    d = d or d2
  import json
  f.write_text(json.dumps(d))
  return d


def oracle_rows(spec):
  CACHE.mkdir(exist_ok=True)
  f = CACHE / ("o_" + re.sub(r"\W", "_", spec) + ".json")
  if f.exists():
    import json
    return json.loads(f.read_text())
  r = run([sys.executable, *spec.split()], env=dict(os.environ, DEV="NULL"))
  d = rows(r.stdout) if r is not None and r.returncode == 0 else {}
  import json
  f.write_text(json.dumps(d))
  return d


def main():
  args = sys.argv[1:]
  targets = [ln.strip() for ln in os.environ.get("PORTS", "").split() if ln.strip()]
  if not targets:
    targets = [ln.strip() for ln in
               (REPO / ".agents" / "slop" / "rebase" / "targets.txt").read_text().splitlines()
               if ln.strip()]
  cand = sorted({str(p.relative_to(REPO)) for p in SLOP.rglob("*.py")
                 if re.search(r"(oracle|gate)", p.name) and "rebase-" not in p.name
                 and "rebase_" not in p.name})
  probes = [ln.strip() for ln in os.environ.get("PROBES", "").split("|") if ln.strip()] or cand

  best = []
  for spec in probes:
    o = oracle_rows(spec)
    if not o:
      continue
    for port in targets:
      b = bend_rows(port)
      if not b:
        continue
      shared = set(o) & set(b)
      if not shared:
        continue
      dis = [k for k in shared if o[k] != b[k]]
      best.append((len(shared), len(dis), port, spec))
  best.sort(reverse=True)
  print(f"{'shared':>6} {'dis':>5}  {'port':<44} oracle")
  for n, d, port, spec in best:
    print(f"{n:>6} {d:>5}  {port:<44} {spec}")
  print(f"\n{len({p for _, _, p, _ in best})} of {len(targets)} target ports have a wireable oracle")
  return 0


if __name__ == "__main__":
  sys.exit(main())