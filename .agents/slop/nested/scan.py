"""Census: which expressions schedule a NESTED (depth >= 2) RANGE, and how small can
the nested one get?  Loop depth is COUNTED from the uop list, never asserted.

    .venv/bin/python .agents/slop/nested/scan.py
"""
import os, sys, base64, pickle, collections, pathlib
os.environ["CCACHE"] = "0"; os.environ["SCACHE"] = "0"
from tinygrad import Tensor, Context
from tinygrad.uop.ops import Ops
import tinygrad.runtime.ops_bend as OB

OUT = pathlib.Path(__file__).parent
LAST = {}
CAP = []
def hook(self, uops):
    LAST["uops"] = uops
    return OB.encode(uops)
OB.BendRenderer.render = hook
_REAL = OB.BendProgram.__call__
def spy(self, *bufs, **kw):
  # MEASURED TRAP: a spy that does NOT chain to the original never launches, and
  # every answer then reads back as zeros -- which reads as "the port is broken"
  # on cases that are actually fine.
  from tinygrad.helpers import to_mv
  v = [to_mv(b, nb) for b, nb in zip(bufs, self.in_bufs)]
  CAP.append((self.src + "".join(f"{len(x)} {bytes(x).hex()}\n" for x in v),
              [str(x) for x in (*kw.get("global_size", (1,1,1)), *kw.get("vals", ()))]))
def _spy_chain(self, *bufs, **kw):
    r = spy(self, *bufs, **kw)
    return _REAL(self, *bufs, **kw)
OB.BendProgram.__call__ = _spy_chain

def depth_of(uops):
  """Loop DEPTH of each RANGE: a RANGE is inside another when some END/BACKEDGE
  names it while it appears after the enclosing RANGE but before the enclosing END.
  Counting RANGEs is not depth -- `dot` has two RANGEs and depth 2, `mulacc` has
  one RANGE and depth 1."""
  idx = {u: i for i, u in enumerate(uops)}
  ends = [i for i, u in enumerate(uops) if u.op in {Ops.END, Ops.BACKEDGE}]
  out = []
  for i, u in enumerate(uops):
    if u.op is not Ops.RANGE: continue
    d = 1
    for e in ends:                       # every loop this RANGE is lexically inside
      s = uops[e]
      if len(s.src) < 2: continue
      st = s.src[1]
      if st is u: continue               # its OWN end
      if idx.get(st, -1) < i and i < e: d += 1
    out.append((i, u.arg, d))
  return out

def cases(T):
  x2 = T([[1.0, 2.0], [3.0, 4.0]]).realize()
  y2 = T([[5.0, 6.0], [7.0, 8.0]]).realize()
  x3 = T([float(v + 1) for v in range(9)]).realize().reshape(3, 3)
  y3 = T([float(2 * v + 1) for v in range(9)]).realize().reshape(3, 3)
  x4 = T([float(v + 1) for v in range(16)]).realize().reshape(4, 4)
  y4 = T([float(2 * v + 1) for v in range(16)]).realize().reshape(4, 4)
  return {
    'mm2':      lambda: x2 @ y2,
    'mm3':      lambda: x3 @ y3,
    'mm4':      lambda: x4 @ y4,
    'red2step': lambda: (x2 * y2).sum(axis=0),
    'red2s4':   lambda: (x4 * y4).sum(axis=0),
    'perm4':    lambda: x4.permute((1, 0)).contiguous(),
    'perm3':    lambda: x3.permute((1, 0)).contiguous(),
    'maxred3':  lambda: x3.max(axis=0),
    'sumall3':  lambda: x3.sum(),
    'flat3':    lambda: (x3 * y3).reshape(9),
  }

want = sys.argv[1:] or None
print(f"{'case':10s} {'uops':>5s} {'RANGE':>5s} {'maxdepth':>8s} {'grid':>10s}  port==cpy")
with Context(DEV='BEND', CACHELEVEL=0):
  CS = cases(Tensor)
  rows = []
  for nm, fn in CS.items():
    if want and nm not in want: continue
    LAST.clear(); CAP.clear()
    r = fn().realize()
    if 'uops' not in LAST or not CAP:
      print(f"{nm:10s}  NO BEND KERNEL"); continue
    uops = LAST["uops"]; ds = depth_of(uops)
    md = max((d for _, _, d in ds), default=0)
    pkt, argv = CAP[-1]
    (OUT/f"packet-{nm}.txt").write_text(pkt)
    (OUT/f"argv-{nm}.txt").write_text(" ".join(argv) + "\n")
    rows.append((nm, len(uops), sum(1 for u in uops if u.op is Ops.RANGE), md, argv, r.data().tolist(), ds))
# THE ORACLE, WRITTEN BY CALLING CPYTHON.  Never typed: `Device['PYTHON']` is
# ops_python.py's own emulator -- the interpreter this unit ports -- and the flat
# f32 list is what the port's output buffer must equal, word for word.
import json
with Context(DEV='PYTHON', CACHELEVEL=0):
  CS = cases(Tensor)
  orc = {nm: CS[nm]().realize().data().tolist() for nm, *_ in rows}
for nm, *_ in rows:
  flat = []
  def f(y):
    if isinstance(y, list):
      for z in y: f(z)
    else: flat.append(float(y))
  f(orc[nm])
  (OUT/f"oracle-{nm}.json").write_text(json.dumps({"dev": "PYTHON", "flat": True, "out": flat}, indent=1))
for nm, nu, nr, md, argv, got, ds in rows:
  same = got == orc[nm]
  print(f"{nm:10s} {nu:5d} {nr:5d} {md:8d} {'x'.join(argv[:3]):>10s}  {'OK ' if same else 'WRONG'}"
        + ("" if same else f"   port={got} cpy={orc[nm]}"))
  for i, arg, d in ds: print(f"           RANGE@{i:3d} {arg} depth={d}")
