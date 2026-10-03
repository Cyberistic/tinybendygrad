#!/usr/bin/env python3
"""debug_oracle.py -- THE CPython authority for the seven `DEBUG`-gated prints.

EVERY expected string is produced by CALLING CPython in a subprocess whose `DEBUG`
comes from the command line. Nothing here is transcribed from a source comment.

    env -u PYTHONPATH .venv/bin/python .agents/slop/debug_oracle.py 2

Rows are `name=value`, one per line. A site that printed nothing at this level
answers `name=` (empty), so the level-0 control is the same row set with every
value empty and the level-2 set is the same row names with values. THAT IS THE
PROOF THE GATE MOVES: the row NAMES are constant across levels and the VALUES are
not, so a row that passes at both 0 and 2 is a bug in the gate, not a pass.

TWO INDEPENDENT LANES OF EVIDENCE.

  LANE A -- CALL THE REAL FUNCTION AND READ BACK WHAT IT PRINTED.
    allreduce.py:16  `handle_allreduce` over a real BUFFER UOp whose `.device` is a
                     4-tuple, in three ContextVar configurations, so the mode name
                     in the f-string is tinygrad's own choice among the three.
    memory.py:59     `memory_plan_rewrite` over two real graphs, one whose savings
                     round away to the same two decimals and one whose do not.
    state.py:260     `torch_load` over a real on-disk pickle whose GLOBAL opcode
                     names a module outside `whitelist`, so the real nested
                     `TorchPickle.find_class` runs and returns the real `Dummy`.
    amdev.py:185/225/251/254   NOT CALLABLE on this host. MEASURED:
                     `AMDev(0)` raises `AttributeError: 'int' object has no
                     attribute 'pcibus'` because `AMDev.__init__` (:157) reads
                     `pci_dev.pcibus` off a real `/dev/kfd` device. LANE B covers
                     these four.

  LANE B -- EXEC UPSTREAM'S OWN SOURCE LINE AT THE CITED POSITION.
    For all seven sites the exact text at `tinygrad/<file>.py:<line>` is read with
    `linecache` and `exec`'d with the live `DEBUG` ContextVar and stand-ins for the
    names the f-string interpolates. The printed text therefore cannot be wrong by
    transcription, and a wrong LINE fails loudly (`err_*` becomes a NameError)
    instead of quietly printing something plausible. This lane cross-checks the
    three LANE A strings.

`dbg_ge<N>_D<L>` is the ContextVar itself: `DEBUG = ContextVar("DEBUG", 0)`
(helpers.py:237) over `getenv = type(default)(os.getenv(key, default))`
(helpers.py:163). `DEBUG` is an INT, and these rows say so from the live object.
`thr_<site>` is the threshold READ OUT OF THE SOURCE LINE, not asserted here, so a
wrong threshold in this file's table cannot make the gate pass.
"""
import os, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PY = os.path.join(ROOT, '.venv', 'bin', 'python')

# (tag, file, line). The THRESHOLD is not in this table: LANE B reads it out of the
# line itself.
SITES = [
    ("ar",    "tinygrad/schedule/allreduce.py",         16),
    ("mem",   "tinygrad/schedule/memory.py",            59),
    ("st",    "tinygrad/nn/state.py",                  260),
    ("am185", "tinygrad/runtime/support/am/amdev.py",  185),
    ("am225", "tinygrad/runtime/support/am/amdev.py",  225),
    ("am251", "tinygrad/runtime/support/am/amdev.py",  251),
    ("am254", "tinygrad/runtime/support/am/amdev.py",  254),
]

# LANE A keeps only the lines its own site prints. The filter is a PREFIX, and the
# prefixes are the first tokens of the strings LANE B produces, so a site whose
# prefix is wrong shows up as `*_lines=0` at every level instead of hiding.
KEEP = {"ar":  (" ALLREDUCE ",),
        "mem": ("memory reduced from ",),
        "st":  ("WARNING: returning Dummy for ",)}

PREAMBLE = r'''
import sys, io, os
sys.path.insert(0, __ROOT__)
from tinygrad.helpers import DEBUG, getenv
def emit(t, v): print("@@" + t + "\t" + str(v))
for _n in (1, 2, 3): emit("ge{0}".format(_n), int(DEBUG >= _n))
emit("bool", int(bool(DEBUG)))
emit("value", repr(DEBUG.value))
emit("key", DEBUG.key)
emit("int_getenv", repr(getenv("DBGPROBE", 0)))
'''

LANE_B = r'''
import linecache, re
SITES = __SITES__
ROOTDIR = __ROOT__
class FakeDev:
  devfmt = "0000:01:00.0"
class FakeIP:
  pass
class FakeBuf:
  dtype = "dtypes.f32"
def stmt(path, line):
  """the whole logical line starting at `line`. memory.py:59's `if` header ends in
  `:` and its `print` is on :60, so reading ONE physical line is an
  IndentationError, not a wrong answer. Continuation is taken while the brackets
  are unbalanced or the text ends in `:`."""
  p = os.path.join(ROOTDIR, path)
  parts, n = [], line
  while True:
    s = linecache.getline(p, n)
    parts.append(s.strip())
    t = "".join(parts)
    if (t.count("(") <= t.count(")") and t.count("[") <= t.count("]")
        and t.count("{") <= t.count("}") and not t.endswith(":")):
      return t, len(parts)
    n += 1
seen = []
for tag, path, line in SITES:
  src, nlines = stmt(path, line)
  emit("src_" + tag, src)
  emit("span_" + tag, nlines)
  m = re.search(r"DEBUG\s*>=\s*(\d+)", src)
  if m is None:
    emit("ge_" + tag, "NOT-A-DEBUG-GATE")
    emit("thr_" + tag, ""); emit("err_" + tag, ""); emit("out_" + tag, "")
    continue
  thr = int(m.group(1))
  scope = {"DEBUG": DEBUG, "self": FakeDev(), "ip": FakeIP(), "buf": FakeBuf(),
           "module": "os.path", "name": "join",
           "nbytes": {"b": 12032}, "arena_sizes": {"b0": 11776},
           "first_appearance": {"b": 0}, "arenas": {"b0": 0},
           "use_all2all": False, "use_ring": True, "ndev": 4, "numel": 300000,
           "print": lambda *a, **k: seen.append(" ".join(str(x) for x in a))}
  err = ""
  try: exec(src, scope)
  except Exception as e: err = "%s:%s" % (type(e).__name__, e)
  emit("ge_" + tag, int(DEBUG >= thr))
  emit("thr_" + tag, thr)
  emit("err_" + tag, err)
  emit("out_" + tag, " | ".join(seen))
  seen = []
'''

LANE_A_AR = r'''
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.helpers import Context
from tinygrad.schedule.allreduce import handle_allreduce
# `vmin_vmax` is not decoration: without it `buf.max_shape` is None and
# `buf.pad_to(buf.max_shape)` (:19) raises `TypeError: 'NoneType' object is not
# iterable` on the NAIVE case, which kills the rest of the loop and silently costs
# the ALL2ALL row. MEASURED, not assumed.
def buf(devs, size, dt=dtypes.float32):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=0, dtype=dt, size=size, vmin_vmax=(0, size),
                                      name="b", device=tuple(devs)))
def run(devs, size):
  # `red.arg` is `(op, device)` (:9) and `device` is what the NAIVE arm hands to
  # `copy_to_device` (:32). A `None` device raises `TypeError: 'NoneType' object is
  # not iterable` there, which kills the loop before the ALL2ALL row runs.
  red = UOp(Ops.REDUCE, src=(buf(devs, size),), arg=(Ops.ADD, devs[0]))
  handle_allreduce(red.src[0], red)
FOUR = ["CPU:0","CPU:1","CPU:2","CPU:3"]
run(FOUR, 300000)                                  # RING:     RING=1 default, ndev>2, over threshold
run(["CPU:0","CPU:1"], 100)                        # NAIVE:    two nodes, under threshold
with Context(ALL2ALL=2): run(FOUR, 100)            # ALL2ALL:  ALL2ALL>=2 forces it
'''

LANE_A_MEM = r'''
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
import tinygrad.schedule.memory as M
def B(slot, size, dev="CPU", dt=dtypes.int32):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=slot, dtype=dt, size=size, name="B%d" % slot, device=dev))
def SINK(body, *args): return UOp(Ops.SINK, src=(body, *args))
# FIXTURE 1 -- memory.bend's own FIXTURE 2: five collected buffers, two lanes, and
# the savings (12032 -> 11776 bytes) round away at two decimals.
A2, B2, C2, D2, E2, F2 = B(2,1024), B(3,2048), B(4,512), B(5,256), B(6,128), B(7,64)
STORE = UOp(Ops.STORE, src=(A2, B2), arg=ParamArg(slot=0, dtype=dtypes.int32))
lin1 = UOp(Ops.LINEAR, src=(SINK(STORE, B2), SINK(STORE, C2),
                           SINK(UOp(Ops.ADD, src=(D2,E2)), D2, E2),
                           SINK(UOp(Ops.MUL, src=(D2,F2)), D2, F2)))
M.memory_plan_rewrite(lin1)
# FIXTURE 2 -- four 512KiB buffers, two live at a time, ONE lane. This is the row
# that separates `{omem:.2f}` from `{nmem:.2f}`, which fixture 1 cannot.
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
# re-reads pickle FOUR. So the dict that carries the GLOBAL opcodes is the fourth
# pickle and `ids` is the fifth. `os.path.join` pickles as module `posixpath`,
# which is NOT in `whitelist` (:250), and `collections` / `numpy` ARE, so those two
# entries are the negative pair that must not print.
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
  p = subprocess.run([PY, '-c', PREAMBLE.replace("__ROOT__", repr(ROOT)) + body],
                     cwd=ROOT, env=env, capture_output=True, text=True)
  tags, plain = {}, []
  for ln in p.stdout.split('\n'):
    if ln.startswith('@@'):
      t, _, v = ln[2:].partition('\t')
      tags.setdefault(t, v)
    elif ln.strip():
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
  rows.append((f"dbg_int_getenv_D{lvl}", base.get("int_getenv", "MISSING")))

  lb = LANE_B.replace("__ROOT__", repr(ROOT)).replace("__SITES__", repr(SITES))
  b, _, _ = child(level, lb)
  for tag, _, _ln in SITES:
    rows.append((f"ge_{tag}", b.get("ge_" + tag, "MISSING")))
    rows.append((f"thr_{tag}", b.get("thr_" + tag, "MISSING")))
    rows.append((f"err_{tag}", b.get("err_" + tag, "MISSING")))
    rows.append((f"laneB_{tag}", b.get("out_" + tag, "")))

  for tag, body in (("ar", LANE_A_AR), ("mem", LANE_A_MEM), ("st", LANE_A_ST)):
    _, plain, p = child(level, body)
    kept = [ln for ln in plain if any(k in ln for k in KEEP[tag])]
    rows.append((f"laneA_{tag}_lines", len(kept)))
    for i, ln in enumerate(kept):
      rows.append((f"laneA_{tag}_{i}", ln))

  for k, v in rows:
    print(f"{k}={v}")
  print(f"dbg_lane_rows={len(rows)}")


if __name__ == '__main__':
  main()