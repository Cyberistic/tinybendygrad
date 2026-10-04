#!/usr/bin/env python3
"""SURFACE2 stage 3 -- CLASSIFY THE 39 BY WHAT A CALLER MUST BE ABLE TO DO.

THE CRITERION, stated once and applied mechanically:

  A missing method is NEEDED-TO-BE-A-DEVICE iff invoking IT performs at least one of
  the FOUR DEVICE OPERATIONS:

      ALLOCATE   storage is bound to a Buffer     (Buffer.allocate)
      LAUNCH     a linear is built and run        (run_linear)
      READ BACK  bytes are asked of the tensor    (Buffer.as_memoryview)
      MOVE       a movement node is built         (UOp._mop returning a new node)

  MOVE IS NOT ONE OF THE FOUR and it is not a bin criterion on its own: a first pass
  counted `_mop` calls and reported `shard` RESHAPEful, because UNSHARD is in
  `GroupOp.Movement`, and `__imatmul__` reshapeful, because matmul reshapes an internal
  buffer. Neither is a reshape A CALLER can perform through the method. The column is
  printed next to `what the caller holds back` so the reader can see which it is.

  NEEDED-TO-BE-USEFUL  : it performs NONE of the four, but a caller cannot write a
                         class of program without it.
  NOT-A-DEVICE-CONCERN : it performs NONE of the four and a caller CAN write the
                         program a different way -- or never wanted it.

**THE DELTA, AND WHY IT IS THE ONLY HONEST INSTRUMENT HERE.** Measured, not guessed:
`Tensor([1.0, 2.0], device='PYTHON')` ALONE reports `ALLOCATE=1 RESHAPE=1`, because
constructing a BUFFER is itself an allocation and the cast path builds a movement
node. A first pass at this probe reported `ALLOCATE` crossed for all 39, which is the
FIXTURE talking, not the method. So every program here is TWO PHASES -- `fx()`
prepares and `use(*args)` invokes the method under test -- and the printed number is
`use - fx`. **A row that reported the program's totals would have classified 39 of 39
as device-necessary.**

INSTRUMENTED SEAMS, all four rebound in every module that bound the name by value
(`from ... import` copies the reference, so rebinding one module reads zero on a
launch that really happened -- the same trap for `run_linear`):

    Buffer.allocate, run_linear, Buffer.as_memoryview, UOp._mop

    env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python \
      .agents/slop/surface2/stage3-classify.py
"""
import os, sys, io, ctypes, contextlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, ROOT)
os.environ.setdefault("DEV", "NULL")

from tinygrad.tensor import Tensor
from tinygrad.uop.ops import UOp, Ops
from tinygrad.device import Buffer
import tinygrad.engine.realize as R
import tinygrad.engine.jit as JIT
import tinygrad.tensor as TP

KEYS = ("ALLOCATE", "LAUNCH", "READBACK", "MOVE")
CNT = {k: 0 for k in KEYS}


def _bump(k):
  CNT[k] += 1


def _install():
  o_alloc = Buffer.allocate

  def alloc(self, *a, **k):
    _bump("ALLOCATE")
    return o_alloc(self, *a, **k)
  Buffer.allocate = alloc

  o_run = R.run_linear

  def run(*a, **k):
    _bump("LAUNCH")
    return o_run(*a, **k)
  R.run_linear = run
  TP.run_linear = run
  JIT.run_linear = run

  o_mm = Buffer.as_memoryview

  def mm(self, *a, **k):
    _bump("READBACK")
    return o_mm(self, *a, **k)
  Buffer.as_memoryview = mm

  o_mop = UOp._mop

  def mop(self, op, arg):
    r = o_mop(self, op, arg)
    if r is not self:
      _bump("MOVE")
    return r
  UOp._mop = mop



_install()


def observe(x):
  """WHAT THE CALLER HOLDS BACK. A reshape is visible as a RESULT, not as a call.

  `.shape` is asked in a GUARD because `decode_hevc_frame` returns a graph whose shape is
  not answerable: `tensor.py:563` passes `arg="encdec"` where ops.py:1259 declares
  `CustomFunction(name:str, dtype:DType = dtypes.void)`, so `dtype_from_uop` reads
  `arg.dtype` off a STRING and raises. That is an UPSTREAM defect -- reported, not fixed
  -- and it is why this row needs the guard: without it one broken method takes the
  whole table down, which is how a table becomes an assertion."""
  def sh(t):
    try:
      return " shape=%s" % (tuple(t.shape),)
    except Exception as e:
      return " shape=<%s>" % type(e).__name__
  if isinstance(x, Tensor):
    return "%s%s" % (x.uop.op.name, sh(x))
  if isinstance(x, UOp):
    return "%s (UOp)" % x.op.name
  if isinstance(x, (tuple, list)) and x and isinstance(x[0], Tensor):
    return "%s%s" % (x[0].uop.op.name, sh(x[0]))
  return type(x).__name__

PROGRAMS = []


def P(name):
  def deco(mk):
    PROGRAMS.append((name, *mk()))
  return deco


def L(n=2):
  return Tensor([1.0 + i for i in range(n)], device="PYTHON")


# ---------------------------------------------------------------- the 39
@P("__del__")
def _():
  def f1():
    return (L(),)
  def u1(a):
    del a
    return "gone"
  return f1, u1


@P("__bool__")
def _():
  def f1():
    return L(),
  def u1(t):
    return bool(t)
  return f1, u1


@P("as_param")
def _():
  def f1():
    return L(),
  def u1(t):
    return t.as_param(3)
  return f1, u1


@P("call")
def _():
  def f1():
    return L(), L(), L(),
  def u1(a, b, c):
    return a.call(b, fxn=c)
  return f1, u1


@P("custom_kernel")
def _():
  # `UOp.custom_kernel` (ops.py:1313) is `fxn(*placeholders).call(*srcs)`, so the fxn must
  # return an OPAQUE CALL BODY -- one of SINK/PROGRAM/LINEAR/STORE/CUSTOM_FUNCTION
  # (ops.py:1391) -- and NOT a value-producing body. A plain `uopfunc` decorator is
  # refused here because it already appended a `.call`; the first pass of this probe read
  # that AssertionError as "custom_kernel does not work".
  def body(a, b):
    return b.alu(Ops.ADD, a)

  def f1():
    # both operands must be shape (4,): a mismatch fails in the ALU broadcast and has
    # nothing to do with `custom_kernel`.
    return Tensor.empty(4, device="PYTHON"), Tensor.empty(4, device="PYTHON"),
  def u1(a, b):
    return a.custom_kernel(b, fxn=body)
  return f1, u1


@P("linear_with_vars")
def _():
  def f1():
    return L(),
  def u1(t):
    return t.linear_with_vars()
  return f1, u1


@P("schedule_linear")
def _():
  def f1():
    return L(),
  def u1(t):
    return t.schedule_linear()
  return f1, u1


@P("realize")
def _():
  def f1():
    return (L() + 1),
  def u1(t):
    return t.realize()
  return f1, u1


@P("_buffer")
def _():
  def f1():
    return L(),
  def u1(t):
    return t._buffer()
  return f1, u1


@P("_data")
def _():
  def f1():
    return L(),
  def u1(t):
    return t._data()
  return f1, u1


@P("data")
def _():
  def f1():
    return L(),
  def u1(t):
    return t.data()
  return f1, u1


@P("tolist")
def _():
  def f1():
    return L(),
  def u1(t):
    return t.tolist()
  return f1, u1


@P("numpy")
def _():
  def f1():
    return L(),
  def u1(t):
    return t.numpy()
  return f1, u1


@P("clone")
def _():
  def f1():
    return L(),
  def u1(t):
    return t.clone()
  return f1, u1


@P("to")
def _():
  def f1():
    return L(),
  def u1(t):
    return t.to("PYTHON")
  return f1, u1


@P("to_")
def _():
  def f1():
    return L(),
  def u1(t):
    t.to_("PYTHON")
    return t
  return f1, u1


@P("shard")
def _():
  def f1():
    return L(),
  def u1(t):
    return t.shard(("PYTHON", "PYTHON"), 0)
  return f1, u1


@P("shard_")
def _():
  def f1():
    return L(),
  def u1(t):
    t.shard_(("PYTHON", "PYTHON"), 0)
    return t
  return f1, u1


@P("shard_like")
def _():
  def f1():
    return L(), L(4),
  def u1(a, b):
    return a.shard_like(b)
  return f1, u1


@P("from_blob")
def _():
  def f1():
    buf = (ctypes.c_float * 2)(1.0, 2.0)
    # the ctypes OBJECT is unhashable and `Buffer.allocate` puts the arg in a cache key
    # (device.py:270), so an unconverted `from_blob` dies in the ALLOCATOR and reports a
    # TypeError that has nothing to do with the method. A first pass of this probe
    # reported that TypeError and read it as "from_blob does not work".
    return (ctypes.cast(buf, ctypes.c_void_p).value,),
  def u1(ptr):
    return Tensor.from_blob(ptr, (2,), dtype="float32")
  return f1, u1


@P("from_url")
def _():
  # `fetch` (helpers.py:472) returns `pathlib.Path(url)` for a url starting with "/",
  # so a LOCAL path exercises `from_url` end to end with no network. `file://` does NOT
  # take that branch and dies on `assert r.status in {200,206}` with a file:// response,
  # which is a statement about urllib and not about the method.
  def f1():
    return ("/etc/hosts",),
  def u1(u):
    return Tensor.from_url(u[0])
  return f1, u1


@P("manual_seed")
def _():
  def f1():
    Tensor.manual_seed(7)
    return None,
  def u1(_):
    Tensor.manual_seed(42)
    return None
  return f1, u1


@P("_next_counter")
def _():
  def f1():
    return None,
  def u1(_):
    return Tensor._next_counter("PYTHON", 3)
  return f1, u1


@P("__setitem__")
def _():
  def f1():
    return L(),
  def u1(t):
    t[0] = 9.0
    return t
  return f1, u1


@P("__delitem__")
def _():
  def f1():
    return L(),
  def u1(t):
    del t[0]
    return t
  return f1, u1


@P("__iadd__")
def _():
  def f1():
    return L(),
  def u1(t):
    t += 1
    return t
  return f1, u1


@P("__isub__")
def _():
  def f1():
    return L(),
  def u1(t):
    t -= 1
    return t
  return f1, u1


@P("__imul__")
def _():
  def f1():
    return L(),
  def u1(t):
    t *= 2
    return t
  return f1, u1


@P("__itruediv__")
def _():
  def f1():
    return L(),
  def u1(t):
    t /= 2
    return t
  return f1, u1


@P("__ifloordiv__")
def _():
  def f1():
    return L(),
  def u1(t):
    t //= 2
    return t
  return f1, u1


@P("__ipow__")
def _():
  def f1():
    return L(),
  def u1(t):
    t **= 2
    return t
  return f1, u1


@P("__iand__")
def _():
  def f1():
    return Tensor([1, 2], device="PYTHON"),
  def u1(t):
    t &= 1
    return t
  return f1, u1


@P("__ior__")
def _():
  def f1():
    return Tensor([1, 2], device="PYTHON"),
  def u1(t):
    t |= 4
    return t
  return f1, u1


@P("__ixor__")
def _():
  def f1():
    return Tensor([1, 2], device="PYTHON"),
  def u1(t):
    t ^= 3
    return t
  return f1, u1


@P("__ilshift__")
def _():
  def f1():
    return Tensor([1, 2], device="PYTHON"),
  def u1(t):
    t <<= 1
    return t
  return f1, u1


@P("__irshift__")
def _():
  def f1():
    return Tensor([1, 2], device="PYTHON"),
  def u1(t):
    t >>= 1
    return t
  return f1, u1


@P("__imatmul__")
def _():
  def f1():
    return L(2), L(2),
  def u1(a, b):
    a @= b
    return a
  return f1, u1


@P("__eq__")
def _():
  def f1():
    return L(), L(),
  def u1(a, b):
    return a == b
  return f1, u1


@P("decode_hevc_frame")
def _():
  def f1():
    from tinygrad.uop.ops import Variable  # `Variable = UOp` (ops.py:1918)
    return L(1), UOp.variable("pos", 0, 100).bind(4),
  def u1(t, pos):
    return t.decode_hevc_frame(pos, (1, 4), t)
  return f1, u1


def run_one(fx, use):
  for k in KEYS:
    CNT[k] = 0
  args, err = None, ""
  try:
    with contextlib.redirect_stdout(io.StringIO()):
      args = fx()
  except Exception as e:
    return dict.fromkeys(KEYS, -1), -1, "fx: %s: %s" % (type(e).__name__, str(e)[:60]), "-"
  base = dict(CNT)
  status, what = "OK", "-"
  try:
    with contextlib.redirect_stdout(io.StringIO()):
      r = use(*args)
      what = observe(r)
  except Exception as e:
    status = "RAISED"
    err = "%s: %s" % (type(e).__name__, str(e)[:60])
    if os.environ.get("S2_TB"):
      import traceback
      traceback.print_exc()
  delta = {k: CNT[k] - base[k] for k in KEYS}
  return delta, status, err, what


def main():
  # THE INSTRUMENT'S OWN NEGATIVE CONTROL, and it is the row that makes the whole table
  # mean something: a program that builds the FIXTURE and calls NOTHING. If any counter
  # fires here it is reading construction, not the method, and every other row is void.
  d, status, err, what = run_one(lambda: (L(),), lambda t: t)
  print("CONTROL (fixture only, no method)  seams=%s  %s" % (
    " ".join("%s=%d" % (k, d[k]) for k in KEYS), "SEAMS ARE QUIET" if not any(d.values())
    else "INSTRUMENT IS BROKEN -- every row below is void"))
  print()
  print("%-18s %-8s %-22s %-9s %s" % ("method", "invoke", "seams crossed", "move", "what the caller holds back"))
  print("-" * 112)
  out = []
  for name, fx, use in PROGRAMS:
    d, status, err, what = run_one(fx, use)
    crossed = [k for k in KEYS if d[k] > 0 and k != "MOVE"]
    print("%-18s %-8s %-22s %-9d %s%s" % (
      name, status, ",".join(crossed) or "-", d["MOVE"], what, ("   <- " + err) if err else ""))
    out.append((name, status, d, crossed, what))
  print()
  print("methods crossing ZERO of ALLOCATE/LAUNCH/READBACK:",
        sum(1 for _, _, _, c, _ in out if not c), "of", len(out))
  return out


if __name__ == "__main__":
  main()