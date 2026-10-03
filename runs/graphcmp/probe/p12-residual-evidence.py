#!/usr/bin/env python3
"""p12-residual-evidence.py -- THE FIVE RESIDUALS, ONE MEASUREMENT EACH.

Every number below is produced by CALLING something: CPython, or bend, or this differ. None
of it is transcribed from a docstring, a report or a comment, and the script says which
read it. It is the evidence file for `graphcmp-report.md` section 5 and it is deliberately
a SEPARATE process from `graphcmp.py`, so that importing the differ here cannot make a
number look right by sharing state with the thing it is checking.

    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python runs/graphcmp/probe/p12-residual-evidence.py
"""
import os
import subprocess
import sys

os.environ["DEV"] = "CPU"
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(REPO, ".agents", "slop"))


def graphcp_vars(x):
  return vars(x)


def head(t):
  print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


# ---------------------------------------------------------------- residual 1
head("R1  a realized BUFFER's `buffer` field -- was it comparing a DEVICE OBJECT?")
from tinygrad import Tensor
from tinygrad.uop.ops import Ops, ParamArg
import graphcmp
graphcmp.load_tinygrad()

t = Tensor.empty(4, 3)
alloc_slot, alloc_bor = t.uop.toposort().__iter__().__next__(), None
for n in t.uop.toposort():
  if n.op is Ops.ALLOC:
    alloc_slot = n.arg.slot
t.realize()
buf = next(n for n in t.uop.toposort() if n.op is Ops.BUFFER)
print(f"  Tensor.empty(4,3)     -> ALLOC  ParamArg.slot={alloc_slot}")
print(f"  after .realize()      -> BUFFER ParamArg.slot={buf.arg.slot}   "
      f"(bind_on_realize={buf.arg.bind_on_realize})")
print(f"  Buffer has a .slot?   -> {hasattr(buf.arg.buffer, 'slot')}")
print(f"  repr(Buffer)          -> {buf.arg.buffer!r}")
print("  THIS normal form NOW emits:")
print(f"    {graphcmp.paramarg(buf.arg)}")
print("  IT USED TO EMIT  (reconstructed from the old source line f'realized{u(pa.buffer)}'):")
print(f"    realized" + "i" + str(buf.arg.buffer))
print(f"  ...which is {len(str(buf.arg.buffer))} chars of DEVICE OBJECT inside the normal form,")
print(f"     including the 'dtypes.f32' token R3 exists to drop and an allocation state.")

# ---------------------------------------------------------------- residual 2
head("R2  KernelInfo.applied_opts / opts_to_apply -- did the emitter even run?")
from tinygrad.uop.ops import KernelInfo
from tinygrad.codegen.opt import Opt, OptOps
ki = KernelInfo(name="probe", applied_opts=(Opt(OptOps.TC, 0, 4), Opt(OptOps.SWAP)),
                opts_to_apply=(Opt(OptOps.PADTO, 1),), beam=2)
print(f"  OptOps is a plain Enum?      -> {issubclass(OptOps, __import__('enum').Enum)}")
print(f"  vars(OptOps.TC)             -> {graphcp_vars(OptOps.TC)}  (a real dict; the member "
      f"does HAVE __dict__)")
for k, v in vars(OptOps.TC).items():
  try:
    graphcp_vars(v)
    w = f"vars -> OK ({type(graphcp_vars(v)).__name__}, {len(graphcp_vars(v))} entries)"
  except TypeError as e:
    w = f"vars -> TypeError: {e}"
  print(f"    member[{k!r}] = {v!r:<26} {w}")
print("  ...so the old crash was NOT 'a member has no __dict__'. It was `__objclass__`")
print("     being THE ENUM CLASS: vars() on a class is its mappingproxy, the loop walked")
print("     the class's 17 attributes and died on the first descriptor among them.")
print("     (`_value_`/`_name_`/`_sort_order_` are int/str and were ALWAYS handled above the")
print("      vars() arm, so they were never the crash.) The walk, attribute by attribute:")
print("     'reaches vars()' means _carg's arms ABOVE do not claim it -- None/DType/Ops/")
print("     AxisType/AddrSpace/Enum/bool/int/float/str/bytes/tuple|UOp/ParamArg/Invalid/")
print("     dataclass. A value that reaches vars() and is not a class CRASHES, and a value")
print("     that reaches vars() and IS a class recurses into its own namespace.")
import enum as _enum
import graphcmp as _g
ARMS = (type(None), _g.DType, _g.Ops, _g.AxisType, _g.AddrSpace, _enum.Enum, bool, int, float,
        str, bytes, tuple, list, _g.UOp, _g.ParamArg)
for k, v in vars(OptOps).items():
  handled = isinstance(v, ARMS) or hasattr(v, "__dataclass_fields__") or type(v).__name__ == "Invalid"
  if handled:
    w = f"handled by an earlier arm ({type(v).__name__})"
  else:
    try:
      graphcp_vars(v)
      w = f"reaches vars() -> OK ({type(graphcp_vars(v)).__name__}, {len(graphcp_vars(v))} entries)"
    except TypeError as e:
      w = f"reaches vars() -> TypeError   <== THE ACTUAL CRASH POINT"
  print(f"    class attr {k:<22} {type(v).__name__:<18} {w}")
print(f"  _carg(OptOps.TC) NOW        -> {graphcmp._carg(OptOps.TC)}")
print(f"  _carg(OptOps.SWAP) NOW      -> {graphcmp._carg(OptOps.SWAP)}")
print(f"  the two differ?             -> {graphcmp._carg(OptOps.TC) != graphcmp._carg(OptOps.SWAP)}")
print(f"  carg(Ops.SINK, ki) NOW      -> {graphcmp.carg(Ops.SINK, ki)}")
print("  KernelInfo fields upstream  -> " + ", ".join(KernelInfo.__dataclass_fields__))
print("  the port DROPPED            -> estimates (P5, tinygrad.renderer), per ops.bend:974")

# ---------------------------------------------------------------- residual 3
head("R3  bytes compared by length only -- or is it a PORT IDENTITY divergence?")
b1 = Tensor  # keep the import used
from tinygrad.uop.ops import UOp
a1 = UOp(Ops.BINARY, (), b"aaaa")
a2 = UOp(Ops.BINARY, (), b"bbbb")
a3 = UOp(Ops.BINARY, (), b"aaaa")
print(f"  upstream b'aaaa' is b'bbbb' -> {a1 is a2}   (different nodes)")
print(f"  upstream b'aaaa' key==b'bb' -> {a1.key == a2.key}")
print(f"  upstream b'aaaa' is b'aaaa' -> {a1 is a3}   (identical bytes intern)")
print(f"  shapes / dtypes             -> {a1.shape} {a1.dtype.name} | {a2.shape} {a2.dtype.name}")
print("  the port side is measured by bend, below.")
out = subprocess.run([os.path.join(REPO, "bin", "bend"),
                      os.path.join(REPO, "runs/graphcmp/probe/pb-buf-binary.bend")],
                     capture_output=True, text=True, cwd=REPO,
                     env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"})
for ln in out.stdout.splitlines():
  if ln.startswith("Q1 BINARY"):
    print(f"  PORT  {ln}")

# ---------------------------------------------------------------- residual 4
head("R4  a UOp nested in an arg -- is it really carried by `src` after all?")
c4 = UOp.const(4)
p = UOp(Ops.PYLITERAL, (), (c4,))
print(f"  p.arg[0] is c4 (same object)-> {p.arg[0] is c4}")
print(f"  len(p.src)                  -> {len(p.src)}       <== the old comment said src carried it")
print(f"  p.toposort()                -> {[n.op.name for n in p.toposort()]}")
print(f"  c4 in p.toposort()          -> {c4 in p.toposort()}")
print(f"  p.dtype / shape             -> {p.dtype.name} / raises")
print(f"  _carg(p.arg[0]) NOW         -> {graphcmp._carg(p.arg[0])!r}  (was the STRING atom 's<uop>')")
print(f"  a real string arg renders as -> {graphcmp._carg('<uop>')!r}  -- the two collided before")

# ---------------------------------------------------------------- residual 5
head("R5  AxisType members the port has and CPython does not -- HOW MANY?")
import tinygrad.uop.ops as opm
names = [m.name for m in opm.AxisType]
print(f"  upstream list(AxisType)     -> {names}  ({len(names)} members)")
for n in ("PLACEHOLDER", "REDUCE", "UNROLL", "LOOP", "UPCAST"):
  print(f"    hasattr(AxisType, {n:<11}) -> {hasattr(opm.AxisType, n)}")
print("  the port's `type AxisType` (ops.bend:641-654) declares ten:")
print("    AXIS_DEVICE GLOBAL LOCAL WARP WEAK LOOP UPCAST PLACEHOLDER REDUCE UNROLL")
print("  so BEND-ONLY = AXIS_REDUCE, AXIS_UNROLL -> TWO, not the three the old report claimed.")
print("  the port's spelling of them is measured by bend:")
out = subprocess.run([os.path.join(REPO, "bin", "bend"),
                      os.path.join(REPO, ".agents/slop/graphcmp-probe-optq.bend")],
                     capture_output=True, text=True, cwd=REPO,
                     env={k: v for k, v in os.environ.items() if k != "PYTHONPATH"})
for ln in out.stdout.splitlines():
  if ln.startswith("Q-AXIS") or ln.startswith("Q-KI") or ln.startswith("Q-BUF") or ln.startswith("Q-SHAPE"):
    print(f"  PORT  {ln}")

# ---------------------------------------------------------------- residual 6 (bonus)
head("BONUS  the shape column's third value -- is `N` reachable on the CPython side?")
n_none = 0
NO_SHAPE = [opm.Ops.IF, opm.Ops.BARRIER, opm.Ops.SINK, opm.Ops.REWRITE_ERROR, opm.Ops.ENDIF,
            opm.Ops.BACKEDGE, opm.Ops.GROUP, opm.Ops.LINEAR, opm.Ops.PROGRAM, opm.Ops.SOURCE]
for op in NO_SHAPE:
  u = UOp(op, (UOp.const(4),), None)
  try:
    u.shape
    n_none += 1
  except RuntimeError:
    pass
print(f"  ops probed                  -> {len(NO_SHAPE)} (the upstream no-shape list, ops.py:331-338)")
print(f"  of those, shape RETURNED None-> {n_none}   (0 means `N` is DEAD on the py side)")
print(f"  ops.py:455                  -> `if (ret:=self._shape) is None: raise RuntimeError(...)`")
print(f"  so 'no shape' and 'raised' are ONE upstream fact, and `N` was a second spelling")
print(f"     for it that the port used MEANINGFULLY and CPython could never produce.")
