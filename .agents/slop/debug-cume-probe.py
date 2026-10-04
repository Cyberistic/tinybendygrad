#!/usr/bin/env python3
"""debug-cume-probe.py -- IS `DEBUG` CUMULATIVE IN UPSTREAM? Measured, not read.

Levels are cumulative iff raising DEBUG keeps EVERY lower-threshold site firing.
The seven sites this repository already gates have thresholds 1 (memory.py:59) and
2 (allreduce.py:16, state.py:260, amdev.py:185/225/251/254), so the question is
measurable WITHOUT inventing a site: run each site's own code at DEBUG=1..7 and
print whether it fired. A non-cumulative DEBUG would drop a threshold-2 site when
DEBUG goes to 4, which is the failure the coordinator named.

Every number here is produced by CALLING tinygrad. Nothing is transcribed.
"""
import os, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PY = os.path.join(ROOT, '.venv', 'bin', 'python')


def child(level, body):
  env = dict(os.environ)
  env.pop('PYTHONPATH', None)
  if level is None:
    env.pop('DEBUG', None)
  else:
    env['DEBUG'] = str(level)
  src = "import sys\nsys.path.insert(0, %r)\n" % ROOT + body
  p = subprocess.run([PY, '-c', src], cwd=ROOT, env=env, capture_output=True, text=True)
  if p.returncode != 0:
    return "CHILD-EXIT-%s: %s" % (p.returncode, p.stderr.strip().split('\n')[-1][:160])
  return [l.strip() for l in p.stdout.split('\n') if l.strip()]


MEM = """
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
import tinygrad.schedule.memory as M
def B(slot, size, dev="CPU", dt=dtypes.int32):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=slot, dtype=dt, size=size, name="B%d" % slot, device=dev))
def SINK(body, *args): return UOp(Ops.SINK, src=(body, *args))
A2, B2, C2, D2, E2, F2 = B(2,1024), B(3,2048), B(4,512), B(5,256), B(6,128), B(7,64)
STORE = UOp(Ops.STORE, src=(A2, B2), arg=ParamArg(slot=0, dtype=dtypes.int32))
lin = UOp(Ops.LINEAR, src=(SINK(STORE, B2), SINK(STORE, C2),
                          SINK(UOp(Ops.ADD, src=(D2, E2)), D2, E2),
                          SINK(UOp(Ops.MUL, src=(D2, F2)), D2, F2)))
M.memory_plan_rewrite(lin)
"""

AR = """
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.helpers import Context
from tinygrad.schedule.allreduce import handle_allreduce
def buf(devs, size, dt=dtypes.float32):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=0, dtype=dt, size=size, vmin_vmax=(0, size), name="b", device=tuple(devs)))
red = UOp(Ops.REDUCE, src=(buf(["CPU:0","CPU:1","CPU:2","CPU:3"], 300000),), arg=(Ops.ADD, "CPU:0"))
handle_allreduce(red.src[0], red)
"""

ST = """
import pickle, os, collections, numpy, tempfile
from tinygrad.nn.state import torch_load
head = pickle.dumps(None) * 3
body = pickle.dumps({"a": os.path.join, "b": collections.OrderedDict, "c": numpy.ndarray})
fn = os.path.join(tempfile.gettempdir(), "debug-cume-gate.pth")
with open(fn, "wb") as f: f.write(head + body + pickle.dumps([]))
torch_load(fn)
"""

AM = """
from tinygrad.helpers import DEBUG
import linecache
class FakeDev: devfmt = "0000:01:00.0"
for path, line in [("tinygrad/runtime/support/am/amdev.py", 185),
                   ("tinygrad/runtime/support/am/amdev.py", 225),
                   ("tinygrad/runtime/support/am/amdev.py", 251),
                   ("tinygrad/runtime/support/am/amdev.py", 254)]:
  src = linecache.getline(%r + "/" + path, line).strip()
  scope = {"DEBUG": DEBUG, "self": FakeDev(), "ip": type("AM_GFX", (), {}),
           "print": lambda *a, **k: print(" ".join(str(x) for x in a))}
  scope["ip"] = scope["ip"]()
  exec(src, scope)
""" % ROOT

LANES = (("mem", MEM, ("memory reduced from ",)), ("ar", AR, (" ALLREDUCE ",)),
         ("st", ST, ("WARNING: returning Dummy for ",)), ("am", AM, ()))

LEVELS = (0, 1, 2, 3, 4, 5, 6, 7)

print("THRESHOLD-SITE CUMULATIVITY -- did each site's own code fire, by level?")
print("%-5s %s" % ("level", "  ".join("%-4s" % n for n, _, _ in LANES)))
fired = {}
for lvl in LEVELS:
  marks = []
  for name, body, _ in LANES:
    out = child(lvl, body)
    n = 0 if isinstance(out, str) else sum(1 for l in out if l.startswith("am ") or "ALLREDUCE" in l
                                            or "memory reduced" in l or "Dummy for" in l)
    marks.append("fire" if n else "-")
    fired.setdefault(name, {})[lvl] = n
  print("%-5d %s" % (lvl, "  ".join("%-4s" % m for m in marks)))

print()
print("EXACT TEXTS at level 7 (the highest), per lane -- these are what must be")
print("IDENTICAL at levels 2..7 if DEBUG is cumulative.")
for name, body, _ in LANES:
  print("  %-4s %s" % (name, child(7, body)))

print()
print("DIFFERENCE vs level 2, per lane (a non-empty list would break cumulativeness):")
for name, body, _ in LANES:
  a, b = child(2, body), child(7, body)
  if isinstance(a, str) or isinstance(b, str):
    print("  %-4s ERROR %r %r" % (name, a, b))
  else:
    print("  %-4s level2=%d level7=%d same=%s" % (name, len(a), len(b), a == b))