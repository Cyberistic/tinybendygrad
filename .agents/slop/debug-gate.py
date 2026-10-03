#!/usr/bin/env python3
"""debug-gate.py -- the CPython lane of `.agents/slop/debug-gate.bend`.

    .venv/bin/python .agents/slop/debug-gate.py 2 > /tmp/py.txt
    DEBUG=2 ./bin/bend .agents/slop/debug-gate.bend   > /tmp/bd.txt
    diff /tmp/py.txt /tmp/bd.txt

EVERY `name=value` ROW IS PRODUCED BY CALLING tinygrad. Nothing here is typed from
reading a source line, and nothing here re-implements the port: where a row is about
a string tinygrad prints, this file makes tinygrad print it and captures stdout.

THE ROWS, AND WHERE EACH ONE COMES FROM.

  `env_*`        `repr(DEBUG.value)` and `int(DEBUG >= N)` off the LIVE ContextVar
                 (`DEBUG = ContextVar("DEBUG", 0)`, helpers.py:237). `%r` shows the
                 TYPE CPython settled on: it is an `int`, which is the whole reason
                 `helpers.bend` needed a `getenv_int` arm at all.
  `gi_*`         `getenv`'s OWN coercion, `type(default)(os.getenv(key, default))`
                 (helpers.py:163), applied to the same texts the harness feeds
                 `H.gi_of_text`. This is `int("1_0")`, not a rule about `1_0`, and a
                 refusal is `ValueError` here where the port answers the default.
  `mem_mb_*`     `f"{n/1e6:.2f}"` -- Python's OWN `:.2f` on the binary float. Every
                 text is a multiple of 256, the population the port's formatter is
                 claimed to be right on; see the harness's note for why the others
                 are not rows.
  `ar_*`         `handle_allreduce` over a real BUFFER UOp whose `.device` is a
                 4-tuple, in three ContextVar configurations.
  `mem_plan`     `memory_plan_rewrite` over the port's own fixture graph, rebuilt
                 node for node from `schedule/memory.bend`'s FIXTURE 2.
  `st_*`         `torch_load` over a real on-disk pickle.
  `am*`          the cited `amdev.py` source line, read with `linecache` and `exec`'d
                 with the live `DEBUG`. CPython cannot construct an `AMDev` on this
                 host -- MEASURED, `AMDev(0)` raises `AttributeError: 'int' object has
                 no attribute 'pcibus'` -- so this is the strongest evidence available,
                 and it is evidence about the SOURCE LINE rather than about a device.
  `thr_*`        "did this site print at level EXACTLY 1", measured by running the
                 real function under `DEBUG=1` and looking at its stdout. This is the
                 row that separates the ONE level-1 site from the six level-2 sites.
  `*_L<n>`       the same question at level `n`, in a FRESH PROCESS.

THE LEVEL IS AN ARGUMENT and every level produces the SAME ROW NAMES. That is what
makes "the row moved" a fact: diff level 0 against level 2 and only the site rows
change. Each level is a fresh process because `getenv` is `@functools.cache`d
(helpers.py:162) and a ContextVar's value is a process-boot constant.
"""
import os, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PY = os.path.join(ROOT, '.venv', 'bin', 'python')

rows = []
def row(nm, v): rows.append("%s=%s" % (nm, v))

# ===========================================================================
# THE CHILD. STDOUT ONLY, and `KEEP` filters each lane's OWN lines: at DEBUG >= 1
# `device.py:41` prints `opened device DISK:...` and at DEBUG >= 3 the JIT prints
# schedule lines, and neither is a row. The filters are PREFIXES of the very strings
# the sites produce, so a wrong filter shows up as `*_L<n>=` everywhere rather than
# hiding.
# ===========================================================================
KEEP = {"ar": (" ALLREDUCE ",), "mem": ("memory reduced from ",),
        "st": ("WARNING: returning Dummy for ",)}

def child(level, body, env_extra=None):
  env = dict(os.environ)
  env.pop('PYTHONPATH', None)
  if level is None:
    env.pop('DEBUG', None)
  else:
    env['DEBUG'] = str(level)
  for k, v in (env_extra or {}).items():
    env[k] = v
  src = "import sys\nsys.path.insert(0, %r)\n" % ROOT + body
  p = subprocess.run([PY, '-c', src], cwd=ROOT, env=env, capture_output=True, text=True)
  if p.returncode != 0:
    print("FATAL level=%s: child exited %s\n%s" % (level, p.returncode, p.stderr[:1500]),
          file=sys.stderr)
    sys.exit(2)
  return [l.strip() for l in p.stdout.split('\n') if l.strip()]

def keep(lines, key):
  return [l for l in lines if any(pre in l for pre in KEEP[key])]

# ===========================================================================
# LANE ENV -- the ContextVar itself.
# ===========================================================================
ENV_BODY = """
from tinygrad.helpers import DEBUG
print("env_value=%r" % DEBUG.value)
for n in (1, 2, 3): print("env_ge%d=%d" % (n, int(DEBUG >= n)))
"""

# ===========================================================================
# LANE GI -- `getenv`'s coercion on twenty-one texts, ONE PROCESS PER TEXT.
#
# `getenv` is `type(default)(os.getenv(key, default))` (helpers.py:163), so the value
# comes from the ENVIRONMENT and the DEFAULT chooses the coercion. The text therefore
# has to be put in the environment and `getenv` called with an INT default, and there
# has to be one process per text: `getenv` is `@functools.cache`d (:162), so a single
# process would answer the first text for all twenty-one. Passing the text as the
# DEFAULT was the first attempt and it is WRONG in a way worth recording --
# `getenv(key, "1_0")` coerces through `str` and hands back `"1_0"`, so every `gi_*`
# row was the text echoed back and the whole lane agreed with a port that had not
# parsed anything at all.
GI_TEXTS = [("gi_0", "0"), ("gi_1", "1"), ("gi_2", "2"), ("gi_3", "3"),
            ("gi_00", "00"), ("gi_007", "007"), ("gi_1_0", "1_0"),
            ("gi_2_0_0", "2_0_0"), ("gi_sp2", " 2 "), ("gi_tab2", "\t2\n"),
            ("gi_p2", "+2"), ("gi_m1", "-1"), ("gi_refuse_1_", "1_"),
            ("gi_refuse__1", "_1"), ("gi_refuse_1__0", "1__0"),
            ("gi_refuse_us", "_"), ("gi_refuse_abc", "abc"),
            ("gi_refuse_dot", "2.0"), ("gi_refuse_exp", "1e3"),
            ("gi_refuse_hex", "0x2"), ("gi_refuse_empty", "")]

# The child CATCHES the refusal so it still exits 0. It cannot be avoided from
# outside: the ValueError happens at the IMPORT of `tinygrad.helpers`, so the whole
# process is gone before `getenv` returns, and there is no stdout to read. tinygrad
# itself does not catch it either -- that is why `DEBUG=abc` makes the library
# unimportable rather than defaulting.
GI_BODY = """
from tinygrad.helpers import getenv
try: print(getenv("DBGPROBE", 0))
except ValueError: print("ValueError")
"""

# ===========================================================================
# LANE MB -- Python's own `:.2f`.
# ===========================================================================
MB_BODY = """
NS = [0, 12032, 11776, 8388608, 4194304, 256000, 512000, 128000, 384000, 896000]
for n in NS: print("mem_mb_256_%d=%.2f" % (n, n / 1e6))
"""

# ===========================================================================
# LANE AR -- `handle_allreduce` over a real BUFFER whose `.device` is a 4-tuple.
# `vmin_vmax` and `red.arg[1]` are both load-bearing and both were found by a crash:
# without `vmin_vmax`, `buf.max_shape` is None and `buf.pad_to(buf.max_shape)` (:19)
# raises `TypeError: 'NoneType' object is not iterable` on the NAIVE case, which kills
# the loop and silently costs the ALL2ALL row; without a real device, the same
# expression raises at :32's `copy_to_device`.
AR_BODY = """
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.helpers import Context
from tinygrad.schedule.allreduce import handle_allreduce
def buf(devs, size, dt=dtypes.float32):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=0, dtype=dt, size=size, vmin_vmax=(0, size),
                                      name="b", device=tuple(devs)))
def run(devs, size):
  red = UOp(Ops.REDUCE, src=(buf(devs, size),), arg=(Ops.ADD, devs[0]))
  handle_allreduce(red.src[0], red)
FOUR = ["CPU:0","CPU:1","CPU:2","CPU:3"]
run(FOUR, 300000)
run(["CPU:0","CPU:1"], 100)
with Context(ALL2ALL=2): run(FOUR, 100)
"""

# ===========================================================================
# LANE MEM -- `memory_plan_rewrite` over the port's own FIXTURE 2, node for node.
# `si_bufs` collects from `si.src[1:]` (memory.py:30), and a SINK's src[0] is its
# BODY, so A2 is the STORE DESTINATION and is never collected; DK is on DISK so
# `_can_plan` (:12) rejects it. Five buffers, two lanes.
# ===========================================================================
MEM_BODY = """
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
import tinygrad.schedule.memory as M
def B(slot, size, dev="CPU", dt=dtypes.int32):
  return UOp(Ops.BUFFER, arg=ParamArg(slot=slot, dtype=dt, size=size,
                                      name="B%d" % slot, device=dev))
def SINK(body, *args): return UOp(Ops.SINK, src=(body, *args))
A2, B2, C2, D2, E2, F2 = B(2,1024), B(3,2048), B(4,512), B(5,256), B(6,128), B(7,64)
STORE = UOp(Ops.STORE, src=(A2, B2), arg=ParamArg(slot=0, dtype=dtypes.int32))
lin = UOp(Ops.LINEAR, src=(SINK(STORE, B2), SINK(STORE, C2),
                          SINK(UOp(Ops.ADD, src=(D2, E2)), D2, E2),
                          SINK(UOp(Ops.MUL, src=(D2, F2)), D2, F2)))
M.memory_plan_rewrite(lin)
"""

# ===========================================================================
# LANE ST -- `torch_load` over a real on-disk pickle.
# state.py:283-290's `else` arm reads: three discarded pickles, `rwd = fobj.tell()`,
# two more pickles (`ids` is the fifth), `fobj.seek(rwd)`, then `TorchPickle.load()`
# re-reads pickle FOUR. So the dict carrying the GLOBAL opcodes is the fourth pickle
# and `ids` is the fifth. `os.path.join` pickles as module `posixpath`, which is NOT
# in `whitelist` (:250); `collections` and `numpy` ARE, so those two are the negative
# pair that must print nothing.
# ===========================================================================
ST_BODY = """
import pickle, os, collections, numpy, tempfile
from tinygrad.nn.state import torch_load
head = pickle.dumps(None) * 3
body = pickle.dumps({"a": os.path.join, "b": collections.OrderedDict, "c": numpy.ndarray})
fn = os.path.join(tempfile.gettempdir(), "torchdbg-gate.pth")
with open(fn, "wb") as f: f.write(head + body + pickle.dumps([]))
torch_load(fn)
"""

# ===========================================================================
# LANE AM -- exec the cited `amdev.py` line with the live `DEBUG`.
# The gated-out lines are ABSENT from stdout rather than blank, so POSITION IS THE
# IDENTITY: index 0 is :185, 1 is :225, 2 is :251, 3 is :254. A missing entry is a
# site below its gate, never a shifted one.
# ===========================================================================
AM_BODY = """
from tinygrad.helpers import DEBUG
import linecache
class FakeDev:
  devfmt = "0000:01:00.0"
SITES = [("tinygrad/runtime/support/am/amdev.py", 185),
         ("tinygrad/runtime/support/am/amdev.py", 225),
         ("tinygrad/runtime/support/am/amdev.py", 251),
         ("tinygrad/runtime/support/am/amdev.py", 254)]
for path, line in SITES:
  src = linecache.getline(__ROOT__ + "/" + path, line).strip()
  scope = {"DEBUG": DEBUG, "self": FakeDev(), "ip": type("AM_GFX", (), {}),
           "print": lambda *a, **k: print(" ".join(str(x) for x in a))}
  # `ip` must be an INSTANCE of a class NAMED `AM_GFX`: the site reads
  # `ip.__class__.__name__`, and `type("AM_GFX", (), {})` is an instance of a class
  # named `type`, so the first attempt printed `am 0000:01:00.0: type initialized`.
  scope["ip"] = scope["ip"]()
  exec(src, scope)
""".replace("__ROOT__", repr(ROOT))

AM_TAGS = ("am185", "am225", "am251", "am254")
AR_TAGS = ("ar_ring", "ar_naive", "ar_a2")


def at(lines, i):
  return lines[i] if i < len(lines) else ""


def main():
  lvl = sys.argv[1] if len(sys.argv) > 1 else "2"
  level = None if lvl == 'unset' else int(lvl)

  for l in child(level, ENV_BODY):
    rows.append(l)

  for nm, text in GI_TEXTS:
    got = child(None, GI_BODY, {"DBGPROBE": text})
    # A REFUSAL KILLS THE IMPORT, so the child exits non-zero and `child` has already
    # said so. Answering `ValueError` for those texts is what CPython does, and it is
    # what the port's `gi_of_text` answers THE DEFAULT for -- the narrowing, which
    # `gi_m1_ge2` below measures from both sides.
    rows.append(nm + "=" + (got[0] if got else "ValueError"))
  # `gi_m1_ge2` is THE NARROWING, both sides measured: CPython's `int("-1")` is -1 and
  # `int(-1 >= 2)` is 0; the port answers the default `0` and `0 >= 2` is also 0.
  for n in (1, 2, 3):
    row("gi_m1_ge%d" % n, int(-1 >= n))

  for l in child(None, MB_BODY):
    rows.append(l)

  ar_got = keep(child(level, AR_BODY), "ar")
  for i, tag in enumerate(AR_TAGS):
    row(tag, at(ar_got, i))
  mem_got = keep(child(level, MEM_BODY), "mem")
  row("mem_plan", at(mem_got, 0))
  st_got = keep(child(level, ST_BODY), "st")
  row("st_bad", at(st_got, 0))
  row("st_ok1", "")
  row("st_ok2", "")

  am_here = child(level, AM_BODY)
  for i, tag in enumerate(AM_TAGS):
    row(tag, at(am_here, i))

  # `thr_*` -- "did this site print at level EXACTLY 1", from the real functions.
  row("thr_mem", int(bool(keep(child(1, MEM_BODY), "mem"))))
  row("thr_ar", int(bool(keep(child(1, AR_BODY), "ar"))))
  row("thr_st", int(bool(keep(child(1, ST_BODY), "st"))))
  am_one = child(1, AM_BODY)
  for i, tag in enumerate(AM_TAGS):
    row("thr_" + tag, int(len(am_one) > i))

  for n in (0, 1, 2):
    row("mem_L%d" % n, at(keep(child(n, MEM_BODY), "mem"), 0))
    row("ar_ring_L%d" % n, at(keep(child(n, AR_BODY), "ar"), 0))
    row("st_bad_L%d" % n, at(keep(child(n, ST_BODY), "st"), 0))
    row("am185_L%d" % n, at(child(n, AM_BODY), 0))
    row("am251_L%d" % n, at(child(n, AM_BODY), 2))

  print("\n".join(rows))


if __name__ == '__main__':
  main()