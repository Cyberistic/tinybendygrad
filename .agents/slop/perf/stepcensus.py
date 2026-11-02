"""Steps/launch for the 32x32 kernel under a BendRenderer knob, from the packet's own control flow.

usage: stepcensus.py <knob> <value>
  baseline | float4=0|1 | shared=0|1 | global_max=<int> | tensor_cores=<nv|amd>
Prints the packet's dimensions, RANGE extents, and the executed step count.
"""
import sys, pathlib, subprocess

ROOT = pathlib.Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
sys.path.insert(0, str(ROOT)); sys.path.insert(0, str(ROOT / ".agents/slop/perf"))
# THE INTERPRETER LANE'S packet is the input here, so pin it: `BEND_C` defaults to 1 (compiled)
# since 2026-11-02 and the compiled lane never builds a packet.
import os as _os
_os.environ["BEND_C"] = "0"
import ops_bend as OB
sys.modules["tinygrad.runtime.ops_bend"] = OB
from bench import build
from tinygrad import Context, Tensor
import tinygrad.dtype as dt

R = OB.BendRenderer
knob, val = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
if knob == "float4":   R.supports_float4 = bool(int(val))
elif knob == "shared": R.has_shared = bool(int(val))
elif knob == "global_max": R.global_max = (int(val),) * 3
elif knob == "local_max":  R.local_max = (int(val),) * 3
elif knob == "tensor_cores":
  if val == "nv":  from tinygrad.renderer.cstyle import NVRenderer as Other
  elif val == "amd": from tinygrad.renderer.cstyle import AMDRenderer as Other
  R.tensor_cores = Other.target.__class__ and [] or []
elif knob != "baseline":
  sys.exit(f"unknown knob {knob}")

orig = subprocess.run
saved = {}
def cap(cmd, **kw):
  if "bend-executor" in str(cmd[0]) and "pkt" not in saved:
    saved["pkt"] = pathlib.Path(cmd[1]).read_text()
  return orig(cmd, **kw)
subprocess.run = cap
try:
  with Context(DEV="BEND"):
    mats = build(32)
    ts = [Tensor(m).realize() for m in mats]
    a, b, c = ts
    _ = ((a @ b) @ c).realize().numpy()
except Exception as e:
  print(f"{knob}={val}: REFUSED -- {type(e).__name__}: {str(e)[:120]}")
  sys.exit(0)
finally:
  subprocess.run = orig

pkt = saved["pkt"]
ops = {}
for ln in pkt.splitlines():
  if ":" not in ln or ln.startswith("bendexec"):
    continue
  head, rest = ln.split(":", 1)
  ops[int(head)] = rest.strip()
n = max(ops)

def resolve(i, depth=0):
  """the integer a src resolves to, through CONST/CAST/AFTER chains, or None"""
  if depth > 8 or i not in ops:
    return None
  parts = ops[i].split()
  op = parts[0]
  if op == "CONST":
    tok = [p for p in parts if p.startswith("c:")]
    return int(tok[0][2:]) if tok else None
  if op in ("CAST", "AFTER", "BITCAST"):
    srcs = [int(p) for p in parts[2:] if p.lstrip("-").isdigit()]
    return resolve(srcs[0], depth + 1) if srcs else None
  return None

ranges, ends = {}, {}
for i, body in ops.items():
  parts = body.split()
  if parts[0] == "RANGE":
    srcs = [int(p) for p in parts[2:] if p.lstrip("-").isdigit()]
    ranges[i] = resolve(srcs[-1])
  elif parts[0] == "END":
    srcs = [int(p) for p in parts[2:] if p.lstrip("-").isdigit()]
    if len(srcs) >= 2: ends[i] = srcs[-1]

cnt, steps, pc, guard = {}, 0, 1, 0
while pc <= n:
  guard += 1
  if guard > 20_000_000:
    sys.exit("runaway simulation")
  steps += 1
  body = ops[pc].split()
  if body[0] == "RANGE":
    if pc in ranges and ranges[pc]:
      cnt[pc] = ranges[pc]          # RANGE re-initialises its counter on every entry
    pc += 1
  elif body[0] == "END" and pc in ends:
    t = ends[pc]
    ext = ranges.get(t)
    if ext:
      cnt[t] = cnt.get(t, 1) - 1
      pc = t + 1 if cnt[t] > 0 else pc + 1
    else:
      pc += 1
  else:
    pc += 1

shape = {i: e for i, e in ranges.items() if e}
print(f"{knob}={val or '-'}: uops={n} ranges={shape} ends_target={ends} steps/launch={steps:,}")
