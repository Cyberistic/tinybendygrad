#!/usr/bin/env python3
"""dev-native-clobber.py -- can a CONCURRENT gate run make a clean lane read BROKEN?

THE MECHANISM UNDER TEST. run_port() names its compiled artifact after the BEND STEM:

    out = pathlib.Path("/tmp/rebase-gate") / f"{bend.stem}.bin"
    out.parent.mkdir(exist_ok=True)
    out.unlink(missing_ok=True)          # <-- unconditional
    b = sh("./bin/bend", str(bend), "-o", str(out))
    ...
    out.chmod(0o755)
    n = sh(str(out))                    # <-- executes whatever is at that path NOW

`device` is a unique stem, so device.bend cannot be clobbered BY ANOTHER PORT. It can be
clobbered by another PROCESS running the same port, and several agents are live on this
machine. So the clobber window is: agent A unlinks device.bin, agent B unlinks + compiles +
runs device.bend, agent A then executes the file at that path -- which now holds B's binary,
or nothing at all. A's verdict is then a fact about B's run.

`rebase-stability.py` already knows this and works around it (it shards by STEM, not by port,
with the reason in a comment at its line 284). The whole-tree sweep does NOT shard, because it
is sequential -- so the sweep only collides with ANOTHER SWEEP, which is exactly what several
live agents produce.

WHAT THIS MEASURES, and it is deliberately narrow:

  CONTROL   one gate_port() call, nothing else running. Establishes the baseline verdict and
            proves the lane is healthy to begin with.
  CONTROL   the compiled binary run 40x with no competitor. Separates "this binary is flaky"
            from "the path is contested".
  ATTACK    two threads calling gate_port() on the SAME port simultaneously, and the mirror
            case: two threads on ports that SHARE A STEM (`dtype.bend` and
            `codegen/decomp/dtype.bend`), which is the collision rebase-stability.py names.

The ATTACK is the point and it is allowed to FAIL LOUDLY: if two concurrent gate runs can
turn a clean lane red, then a BROKEN in a whole-tree sweep is not a statement about the port
at all, and every BROKEN in such a sweep is suspect until it is reproduced alone.

  usage: .venv/bin/python .agents/slop/dev-native-clobber.py [--threads N]
"""
import argparse, concurrent.futures as cf, importlib.util, json, pathlib, subprocess, sys, threading, time

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
PORT = "tinybendygrad/device.bend"
STEM_CLASH = ["tinybendygrad/dtype.bend", "tinybendygrad/codegen/decomp/dtype.bend"]


def load_gate():
  spec = importlib.util.spec_from_file_location("clobber_gate", HERE / "rebase-gate.py")
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--threads", type=int, default=4)
  ap.add_argument("--rounds", type=int, default=3)
  a = ap.parse_args()
  g = load_gate()
  base = json.loads((HERE / "rebase" / "baseline.json").read_text())
  print(f"load {time.strftime('%H:%M:%S')}  loadavg {__import__('os').getloadavg()[0]:.1f}\n")

  def gate(port):
    v, now = g.gate_port(REPO / port, g.BASE_ORACLES[port], base, native=True)
    return port, v["state"], v["why"][:90], {k: l["rc"] for k, l in v["lanes"].items()}

  print("CONTROL 1 -- one gate_port(), nothing else running")
  p, state, why, lanes = gate(PORT)
  print(f"  {p} -> {state}  lanes={lanes}\n  {why}\n")
  baseline_state = state

  print("CONTROL 2 -- the compiled binary alone, 40 runs, no competitor")
  out = pathlib.Path("/tmp/rebase-gate") / "device-stress.bin"
  b = subprocess.run(["./bin/bend", PORT, "-o", str(out)], cwd=REPO, capture_output=True, text=True)
  out.chmod(0o755)
  rcs, rows = {}, {}
  for _ in range(40):
    r = subprocess.run([str(out)], cwd=REPO, capture_output=True, text=True)
    rcs[r.returncode] = rcs.get(r.returncode, 0) + 1
    n = sum(1 for l in r.stdout.splitlines() if "=" in l)
    rows[n] = rows.get(n, 0) + 1
  print(f"  compile rc={b.returncode}   rc tally {rcs}   row-count tally {rows}\n")

  print(f"ATTACK 1 -- {a.threads} threads on the SAME port, {a.rounds} rounds")
  print("  (this is two agents both running the gate over device.bend)")
  for rnd in range(1, a.rounds + 1):
    with cf.ThreadPoolExecutor(max_workers=a.threads) as ex:
      futs = [ex.submit(gate, PORT) for _ in range(a.threads)]
      res = [f.result() for f in futs]
    states = {}
    for _, st, why, lanes in res:
      states[st] = states.get(st, 0) + 1
    print(f"  round {rnd}: {states}")
    for _, st, why, lanes in res:
      if st != baseline_state:
        print(f"    !! DIVERGED from the control: {st}  lanes={lanes}\n       {why}")

  print(f"\nATTACK 2 -- {a.threads} threads over ports that SHARE THE STEM `dtype`")
  print(f"  {STEM_CLASH} both compile to /tmp/rebase-gate/dtype.bin")
  for rnd in range(1, a.rounds + 1):
    jobs = [STEM_CLASH[i % len(STEM_CLASH)] for i in range(a.threads)]
    with cf.ThreadPoolExecutor(max_workers=a.threads) as ex:
      futs = [ex.submit(gate, p) for p in jobs]
      res = [f.result() for f in futs]
    for p, st, why, lanes in res:
      bad = [k for k, lrc in lanes.items() if lrc != 0 and k != "check"]
      print(f"  round {rnd} {p:<40} {st:<12} dead={bad or '-'}")
  return 0


if __name__ == "__main__":
  sys.exit(main())