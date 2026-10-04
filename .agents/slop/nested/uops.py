"""Dump the uop stream the BEND packet carries, with CPython's OWN loop table beside
the port's own scan.  Nothing here is typed: `loop_ends` is CPython's dict from
ops_python.py:51, and the "port scan" column is a re-implementation of
ops_python.bend:1657-1662 (`Prog.loop.go`) applied to the same list.

    .venv/bin/python .agents/slop/nested/uops.py [case ...]

TRAP (ops-python-probe.py's docstring, re-hit here): every input is an explicit
list and is built INSIDE the Context, because an input realized outside realizes
on the DEFAULT device (METAL on this box) and the first .realize() dies in
elf.py with `sel_registerName`.  `Tensor.arange` likewise realizes to CPU.
"""
import os, sys, base64, pickle, collections, pathlib
os.environ["CCACHE"] = "0"; os.environ["SCACHE"] = "0"
from tinygrad import Tensor, Context
from tinygrad.uop.ops import Ops
import tinygrad.runtime.ops_bend as OB

OUT = pathlib.Path(__file__).parent
LAST = {}

# BendRenderer.render FORKED PythonRenderer.render (ops_bend.py:235), so the hook
# has to go on BendRenderer or it is never called.
def hook(self, uops):
    LAST["uops"] = uops
    LAST["wire"] = OB.encode(uops)
    return OB.encode(uops)          # the REAL render, so the packet still runs
OB.BendRenderer.render = hook

# The RENDERER's output carries no buffer lines; BendProgram.__call__ appends them.
# Spying there reproduces the file byte for byte (ops-python-probe.py:102-116).
CAP = []
_REAL = OB.BendProgram.__call__
def spy(self, *bufs, **kw):
  # MEASURED TRAP: a spy that does NOT chain to the original never launches, and
  # every answer then reads back as zeros -- which reads as "the port is broken"
  # on cases that are actually fine.
  from tinygrad.helpers import to_mv
  views = [to_mv(b, nb) for b, nb in zip(bufs, self.in_bufs)]
  CAP.append((self.src + "".join(f"{len(v)} {bytes(v).hex()}\n" for v in views),
              [str(x) for x in (*kw.get("global_size", (1, 1, 1)), *kw.get("vals", ()))]))
def _spy_chain(self, *bufs, **kw):
    r = spy(self, *bufs, **kw)
    return _REAL(self, *bufs, **kw)
OB.BendProgram.__call__ = _spy_chain

def cases():
  xs = Tensor([float(v + 1) for v in range(16)]).realize().reshape(4, 4)
  ys = Tensor([float(2 * v + 1) for v in range(16)]).realize().reshape(4, 4)
  a = Tensor([1.0, 2.0, 3.0, 4.0]).realize()
  b = Tensor([10.0, 20.0, 30.0, 40.0]).realize()
  return {'add4': lambda: a + b, 'dot': lambda: xs @ ys,
          'permute': lambda: xs.permute((1, 0)).contiguous(),
          'mulacc': lambda: (xs * ys).sum(axis=0),
          'maxred': lambda: xs.max(axis=0)}

def dump(name):
  uops = LAST["uops"]
  idx = {u: i for i, u in enumerate(uops)}
  # CPython, ops_python.py:51 -- LAST end per start node wins (dict overwrite)
  cpy = {}
  for i, u in enumerate(uops):
    if u.op in {Ops.END, Ops.BACKEDGE}: cpy[u.src[1]] = i
  print(f"===== {name}: {len(uops)} uops, "
        f"{sum(1 for u in uops if u.op is Ops.RANGE)} RANGE, "
        f"{sum(1 for u in uops if u.op is Ops.END)} END, "
        f"{sum(1 for u in uops if u.op is Ops.BACKEDGE)} BACKEDGE")
  for i, u in enumerate(uops):
    tag = ""
    if u.op is Ops.RANGE:
      tag = f"  <<RANGE {u.arg} trip={u.src[0]}>>"
    elif u.op is Ops.END:
      tag = f"  <<END   start={idx.get(u.src[1],'NONODE')} loop_ends[{idx.get(u.src[1],'NONODE')}]={cpy.get(u.src[1],'ABSENT')}>>"
    elif u.op is Ops.BACKEDGE:
      tag = f"  <<BACKEDGE head={idx.get(u.src[1],'NONODE')} cond={idx.get(u.src[2],'NONODE')}>>"
    if u.op in (Ops.RANGE, Ops.END, Ops.BACKEDGE):
      print(f"{i:3d} {u.op!s:16s} srcs={[idx.get(s,'NONODE') for s in u.src]}{tag}")
  print("   CPython loop_ends:", {idx[k]: v for k, v in cpy.items()})
  # THE PORT'S OWN SCAN, ops_python.bend:1657-1662: hit = LAST i with u END/BACKEDGE
  # and u.src[1] is r.  Reproduced here so the two meet on one list.
  for r_i, r in enumerate(uops):
    if r.op is not Ops.RANGE: continue
    scan = 0
    for j, u in enumerate(uops):
      if u.op in (Ops.END, Ops.BACKEDGE) and len(u.src) > 1 and u.src[1] is r: scan = j
    real = cpy.get(r, 'ABSENT')
    print(f"   RANGE@{r_i} {r.arg}: port scan={scan}  CPython loop_ends={real}   "
          f"{'SAME' if scan == real else '*** DIFFERS ***'}")
  print("   ends per RANGE node:", dict(collections.Counter(
      idx[u.src[1]] for u in uops if u.op in {Ops.END, Ops.BACKEDGE} and u.src[1] in idx)))

want = sys.argv[1:] or ['add4', 'dot', 'permute', 'mulacc']
with Context(DEV='BEND', CACHELEVEL=0):
  CS = cases()
  for nm in want:
    LAST.clear()
    r = CS[nm]().realize()
    if 'uops' not in LAST:
      print(f"--- {nm}: NO BEND KERNEL, gates nothing"); continue
    (OUT/f"wire-{nm}.txt").write_text(LAST["wire"])
    CAP.clear()
    CS[nm]().realize()          # second launch: capture the FULL packet + argv
    if CAP:
      pkt, argv = CAP[-1]
      (OUT/f"packet-{nm}.txt").write_text(pkt)
      (OUT/f"argv-{nm}.txt").write_text(" ".join(argv) + "\n")
    print(f"--- {nm}  argv={CAP[-1][1] if CAP else 'NONE'}")
    dump(nm)
    print(f"   PORT  {r.data().tolist()}")
print("--- CPython DEV=PYTHON, the oracle (the emulator this file ports)")
with Context(DEV='PYTHON', CACHELEVEL=0):
  CS = cases()
  for nm in want:
    print(f"   {nm} {CS[nm]().realize().data().tolist()}")
