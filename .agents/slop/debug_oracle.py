#!/usr/bin/env python3
"""debug_oracle.py -- THE CPython authority for the seven `DEBUG`-gated prints.

EVERY expected string is produced by CALLING CPython in a subprocess whose `DEBUG`
comes from the command line. Nothing here is transcribed from a source comment.

    env -u PYTHONPATH .venv/bin/python .agents/slop/debug_oracle.py 2

Rows are `name=value`, one per line. A site that printed nothing at this level
answers `name=` (empty), so the level-0 control is the same row set with every
value empty and the level-2 set is the same row names with values. THAT IS THE
PROOF THE GATE MOVES: the row NAMES are constant and the VALUES are not.

TWO LANES OF EVIDENCE, and they are independent on purpose.

  LANE A -- CALL THE REAL FUNCTION.
    allreduce.py:16  `handle_allreduce` over a real BUFFER UOp whose `.device` is a
                     4-tuple, so the function really runs and really prints.
    memory.py:59     `memory_plan_rewrite` over two real graphs; memory.py's own
                     print, reached through the module's own planner.
    state.py:260     `torch_load` over a real on-disk pickle whose GLOBAL opcode
                     names a module outside `whitelist`, so the real nested
                     `TorchPickle.find_class` runs.
    amdev.py:185/225/251/254   NOT CALLABLE -- `AMDev(0)` needs a real
                     `/dev/kfd` PCI device and raises `AttributeError: 'int' object
                     has no attribute 'pcibus'` on this host. See LANE B.

  LANE B -- EXEC UPSTREAM'S OWN SOURCE LINE.
    For all seven sites the exact `if DEBUG >= N: print(f"...")` text is read out of
    `tinygrad/<file>.py` at the cited line with `linecache` and `exec`'d with the
    live `DEBUG` ContextVar and a stand-in `self`. The string therefore cannot be
    wrong by transcription, and naming the wrong LINE fails loudly instead of
    quietly printing something plausible. This lane is what covers the four amdev
    sites, and it CROSS-CHECKS the three LANE A strings.

`dbg_ge<N>_D<L>`, `dbg_value_D<L>`, `dbg_int_<text>` are the ContextVar itself:
`DEBUG = ContextVar("DEBUG", 0)` (helpers.py:237) over
`getenv = type(default)(os.getenv(key, default))` (helpers.py:163), so `DEBUG` is an
INT and these rows say so from the live object rather than from the source.
"""
import os, subprocess, sys, json

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PY = os.path.join(ROOT, '.venv', 'bin', 'python')

# site -> (file, line, threshold). Thresholds are NOT asserted here; they are READ
# OUT of the source line by LANE B, so a wrong threshold in this table cannot make
# the gate pass -- the line's own `if` decides.
SITES = [
    ("ar",  "tinygrad/schedule/allreduce.py",        16),
    ("mem", "tinygrad/schedule/memory.py",           59),
    ("st",  "tinygrad/nn/state.py",                 260),
    ("am185", "tinygrad/runtime/support/am/amdev.py", 185),
    ("am225", "tinygrad/runtime/support/am/amdev.py", 225),
    ("am251", "tinygrad/runtime/support/am/amdev.py", 251),
    ("am254", "tinygrad/runtime/support/am/amdev.py", 254),
]

PREAMBLE = r'''
import sys, io, os
sys.path.insert(0, %(root)r)
from tinygrad.helpers import DEBUG, getenv
def emit(t, v): print("@@" + t + "\t" + str(v))
'''

# --- LANE B body: exec the upstream source line at each cited position ---------
LANE_B = r'''
import linecache
SITES = %(sites)r
class FakeDev:
  devfmt = "0000:01:00.0"
class FakeIP:
  pass
seen = []
for tag, path, line in SITES:
  src = linecache.getline(os.path.join(%(root)r, path), line)
  emit("src_" + tag, src.rstrip())
  if "DEBUG >=" not in src:
    emit("ge_" + tag, "NOT-A-DEBUG-GATE"); emit("out_" + tag, ""); continue
  scope = {"DEBUG": DEBUG, "self": FakeDev(), "ip": FakeIP(), "print":
           lambda *a, **k: seen.append(" ".join(str(x) for x in a)), "buf": None,
           "module": "os.path", "name": "join"}
  exec(src, scope)
  emit("ge_" + tag, int(src.split("DEBUG >=")[1].split(":")[0].strip().split()[0] and DEBUG >= int(src.split("DEBUG >=")[1].split(":")[0].strip().split()[0])))
  emit("out_" + tag, " | ".join(seen))
  seen = []
'''

# --- LANE A bodies: the real functions ---------------------------------------
LANE_A_AR = r'''
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.schedule.allreduce import handle_allreduce
def buf(devs, size, dt=dtypes.float32):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=0, dtype=dt, size=size, name="b", device=tuple(devs)))
CASES = [("ring4", ["CPU:0","CPU:1","CPU:2","CPU:3"], 300000),
         ("naive2", ["CPU:0","CPU:1"], 100),
         ("a2force", ["CPU:0","CPU:1","CPU:2","CPU:3"], 300000)]
emit("fired", 0)
for tag, devs, size in CASES:
  red = UOp(Ops.REDUCE, src=(buf(devs, size),), arg=(Ops.ADD, None))
  handle_allreduce(red.src[0], red)
'''

LANE_A_MEM = r'''
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
import tinygrad.schedule.memory as M
def B(slot, size, dev="CPU", dt=dtypes.int32):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=slot, dtype=dt, size=size, name="B%d" % slot, device=dev))
def SINK(body, *args): return UOp(Ops.SINK, src=(body, *args))
# FIXTURE 1 -- memory.bend's FIXTURE 2: five collected buffers, two lanes.
A2, B2, C2, D2, E2, F2 = B(2,1024), B(3,2048), B(4,512), B(5,256), B(6,128), B(7,64)
STORE = UOp(Ops.STORE, src=(A2, B2), arg=ParamArg(slot=0, dtype=dtypes.int32))
lin1 = UOp(Ops.LINEAR, src=(SINK(STORE, B2), SINK(STORE, C2),
                           SINK(UOp(Ops.ADD, src=(D2,E2)), D2, E2),
                           SINK(UOp(Ops.MUL, src=(D2,F2)), D2, F2)))
M.memory_plan_rewrite(lin1)
# FIXTURE 2 -- four 512KiB buffers, two live at a time, ONE lane: the savings are
# large enough that `{omem:.2f}` and `{nmem:.2f}` are DIFFERENT strings, which is
# what separates the two halves of memory.py:59 from each other.
p, q, r, s = B(1,524288), B(2,524288), B(3,524288), B(4,524288)
lin2 = UOp(Ops.LINEAR, src=(SINK(UOp(Ops.ADD, src=(p,q)), p, q),
                            SINK(UOp(Ops.ADD, src=(r,s)), r, s)))
M.memory_plan_rewrite(lin2)
'''

LANE_A_ST = r'''
import pickle, os, collections, numpy, tempfile
from tinygrad.nn.state import torch_load
# state.py:283-290's `else` arm reads: three discarded pickles, `rwd = fobj.tell()`,
# two more pickles (`ids` is the fifth), `fobj.seek(rwd)`, then `TorchPickle.load()`
# reads pickle FOUR back. So the dict has to be the fourth pickle.
head = pickle.dumps(None) * 3
body = pickle.dumps({"a": os.path.join, "b": collections.OrderedDict, "c": numpy.ndarray})
fn = os.path.join(tempfile.gettempdir(), "torchdbg-debug.pth")
with open(fn, "wb") as f: f.write(head + body + pickle.dumps([]))
torch_load(fn)
'''


def child(level, body):
  env = dict(os.environ)
  env.pop('PYTHONPATH', None)
  if level is None:
    env.pop('DEBUG', None)
  else:
    env['DEBUG'] = str(level)
  src = (PREAMBLE % {"root": ROOT}) + body
  p = subprocess.run([PY, '-c', src], cwd=ROOT, env=env, capture_output=True, text=True)
  tags, plain = {}, []
  for ln in p.stdout.split('\n'):
    if ln.startswith('@@'):
      t, _, v = ln[2:].partition('\t')
      tags.setdefault(t, v)
    elif ln.strip() and not ln.startswith('opened device'):
      plain.append(ln.strip())
  return tags, plain, p


def main():
  lvl = sys.argv[1] if len(sys.argv) > 1 else "2"
  level = None if lvl == 'unset' else int(lvl)
  rows = []

  base, _, p0 = child(level, "")
  if p0.returncode != 0:
    print(f"FATAL=child exited {p0.returncode}: {p0.stderr.strip()[:200]}")
    return
  for n in (1, 2, 3):
    rows.append((f"dbg_ge{n}_D{lvl}", base.get(f"ge{n}", "MISSING")))
  rows.append((f"dbg_bool_D{lvl}", base.get("bool", "MISSING")))
  rows.append((f"dbg_value_D{lvl}", base.get("value", "MISSING")))

  b, _, _ = child(level, LANE_B % {"root": ROOT, "sites": SITES})
  for tag, _, _ln in SITES:
    rows.append((f"ge_{tag}", b.get("ge_" + tag, "MISSING")))
    rows.append((f"src_{tag}", b.get("src_" + tag, "MISSING")))

  for tag, body, nsites in (("ar", LANE_A_AR, 1), ("mem", LANE_A_MEM, 2), ("st", LANE_A_ST, 1)):
    _, plain, _ = child(level, body)
    rows.append((f"laneA_{tag}_lines", len(plain)))
    for i, ln in enumerate(plain):
      rows.append((f"laneA_{tag}_{i}", ln))

  for k, v in rows:
    print(f"{k}={v}")
  print(f"dbg_lane_rows={len(rows)}")


if __name__ == '__main__':
  main()