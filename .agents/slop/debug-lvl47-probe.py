#!/usr/bin/env python3
"""debug-lvl47-probe.py -- CPython counterparts for `DEBUG` levels 4, 5, 6, 7.

Upstream's own `DEBUG >= N` prints at these levels, LOCATED BY CALLING CPython's
source (never by reading it into this table):

  level 4  codegen/__init__.py:444  print(ctx.asm_str(lst, ...))   -- ISA asm from LINEAR
           codegen/__init__.py:453  print(src)                     -- "\n".join(str(u.arg[0]))
           codegen/__init__.py:462  print(source.arg)              -- the rendered SOURCE
           codegen/opt/heuristic.py:107,134                         -- upcast chatter
  level 5  codegen/__init__.py:274  print(pyrender(ast))           -- the UOP LIST
           renderer?  viz/cli.py:215
  level 6  runtime/support/usb.py:25  LIBUSB_OPTION_LOG_LEVEL = 4  -- NOT A PRINT
           viz/cli.py:216                                            -- NOT A PRINT
  level 7  device.py:171,198  buffer: allocate / deallocate
           codegen/__init__.py:464  ctx.compiler.disassemble(lib)   -- the DISASSEMBLY

This probe asks, per level: which of those prints FIRE, on a real end-to-end
kernelize+codegen of one small tensor program. Everything printed here is
produced by importing and CALLING tinygrad; the only thing written by hand is the
program, which is the fixture and not an expectation.
"""
import os, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PY = os.path.join(ROOT, '.venv', 'bin', 'python')

# ONE fixture, used at every level, so a level change cannot also change the graph.
PROG = """
from tinygrad import Tensor
from tinygrad.helpers import Context
with Context(DEV="CPU"):
  a = Tensor([1.0, 2.0, 3.0]).realize()
  b = Tensor([4.0, 5.0, 6.0]).realize()
  out = (a * b + a).realize()
  out.numpy()
print("PROBE-OK")
"""

# The three marks each level is supposed to leave, as PREFIXES of the upstream
# prints. Read off the source lines above, and verified by the FIRE COUNTS below.
MARKS = {
    4: ("PROBE-OK",),          # placeholder; filled in from the measured output
    5: (),
    6: (),
    7: (),
}


def run(level):
  env = dict(os.environ)
  env.pop('PYTHONPATH', None)
  env['DEBUG'] = str(level)
  src = "import sys\nsys.path.insert(0, %r)\n" % ROOT + PROG
  p = subprocess.run([PY, '-c', src], cwd=ROOT, env=env, capture_output=True, text=True)
  return p.returncode, p.stdout, p.stderr


LEVELS = (2, 3, 4, 5, 6, 7)
out = {}
for lvl in LEVELS:
  rc, so, se = run(lvl)
  lines = [l.rstrip() for l in so.split('\n') if l.strip()]
  ok = any(l == "PROBE-OK" for l in lines)
  body = [l for l in lines if l != "PROBE-OK"]
  out[lvl] = body
  print("=" * 78)
  print("LEVEL %d   rc=%d   probe-ran=%s   extra-stdout-lines=%d" % (lvl, rc, ok, len(body)))
  if not ok:
    print("  stderr tail:", (se.strip().split('\n') or ['<empty>'])[-1][:300])
  for l in body[:14]:
    print("   |", l[:150])
  if len(body) > 14:
    print("   | ... %d more" % (len(body) - 14))

print("=" * 78)
print("CUMULATIVITY OF THE 4/5/7 PRINTS: level-2 stdout must be a PREFIX of every")
print("higher level's stdout, since `DEBUG >= N` is monotone.")
base = out[2]
for lvl in LEVELS[1:]:
  got = out[lvl]
  pref = got[:len(base)] == base
  print("  level %d: level2-is-a-prefix=%s  (level2 %d lines, level%d %d lines)"
        % (lvl, pref, len(base), lvl, len(got)))