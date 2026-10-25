"""PROBE -- HOW FAR `gr_17` (RESHAPE) AND `gr_14` (REDUCE) ARE, MEASURED.

THE QUESTION.  The brief asks: *MEASURE WHETHER `gr_17` IS LANDABLE WITHOUT `resolve`
(A STATIC SHAPE'S `prod` IS INTEGER MULTIPLICATION, WHICH MAY ALREADY EXIST IN THE
PORT)* -- and the port's own comment at `gradient.bend:627-639` records that upstream's
`pm_gradient` HAS NO ARITY CHECK, so the RESHAPE rule answers 2 gradients for a 1-src
RESHAPE and upstream's own `compute_gradient` assert fires.

THIS FILE ANSWERS BOTH HALVES, AND THE ANSWER TO THE SECOND HALF IS NOT THE ONE THE
PORT'S COMMENT GIVES:

  * `gr_17` (RESHAPE) -- upstream's rule is `(ctx.reshape(ret.src[0].shape), None)`
    (`tinygrad/mixin/gradient.py:85`) and `ctx.reshape` is `tinygrad/mixin/movement.py:164`.
    **⇒ `reshape` NEVER CALLS `resolve`.**  Its needs are `self.shape`, `prod`, and a
    shape equality -- and `prod` of a STATIC shape is INTEGER MULTIPLICATION.
  * `gr_14` (REDUCE) -- upstream's rule is `reduce_gradient(ctx, ret, ret.arg[0])`
    (`tinygrad/mixin/gradient.py:8-18`), whose three arms call `_rop` (ops.py:633-642)
    and `_broadcast_to` (movement.py:128).  BOTH ask `resolve(...)` -- but **FOR A STATIC
    SHAPE THE ARGUMENT OF `resolve` IS A PYTHON BOOL, NOT A UOP**, so no symbolic
    solving happens even there.

⇒ THE INSTRUMENT.  **`resolve` IS PATCHED AND COUNTED**, and every call records whether
its argument is a `UOp` (a SYMBOLIC question) or a `bool` (a STATIC question).  That is
the difference between "needs a symbolic solver" and "needs the identity on a bool",
and it is the difference the port's comments are about.

Run:
    LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/backward4/probe-gr17.py
"""
import tinygrad.uop.ops as ops_mod
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.mixin.gradient import compute_gradient, pm_gradient, _deepwalk

# --- THE INSTRUMENT: COUNT `resolve` AND CLASSIFY ITS ARGUMENT ---------------
RESOLVE_CALLS = []
_real_resolve = ops_mod.resolve


def traced_resolve(x, default=None):
  RESOLVE_CALLS.append("UOp" if isinstance(x, UOp) else type(x).__name__)
  return _real_resolve(x, default)


ops_mod.resolve = traced_resolve


def leaf(slot, size):
  return UOp(Ops.BUFFER, src=(UOp(Ops.STACK, src=(UOp(Ops.CONST, arg=size),)),),
             arg=ParamArg(slot, dtypes.float32))


def reset():
  RESOLVE_CALLS.clear()


def report(label):
  sym = [c for c in RESOLVE_CALLS if c == "UOp"]
  print("    resolve calls: %d   of which SYMBOLIC (a UOp argument): %d   %s"
        % (len(RESOLVE_CALLS), len(sym), RESOLVE_CALLS))


def tok(u):
  return "%s/%d" % (u.op.name, len(u.src))


# ---------------------------------------------------------------------------
# gr_17 -- RESHAPE
# ---------------------------------------------------------------------------
def probe_gr17():
  print("=== gr_17: RESHAPE, on a STATIC shape")
  buf = leaf(0, 6)
  shape_node = UOp(Ops.STACK, src=(UOp(Ops.CONST, arg=2), UOp(Ops.CONST, arg=3)))
  # upstream's OWN `reshape` builds the node, so the fixture is upstream's shape:
  r = buf.reshape((2, 3))
  print("    upstream's own reshape: op=%s nsrc=%d arg=%r shape=%r"
        % (r.op.name, len(r.src), r.arg, r.shape))
  gbuf = leaf(1, 6)
  g = gbuf.reshape((2, 3))

  reset()
  grads = compute_gradient(r, g, {buf})
  print("    grads: %s" % " ".join("%s->%s" % (tok(k), tok(v)) for k, v in grads.items()))
  report("gr_17")
  for k, v in grads.items():
    print("    the gradient of %s is %s arg=%r shape=%r" % (tok(k), tok(v), getattr(v, "arg", None), v.shape))
  return True


# ---------------------------------------------------------------------------
# gr_14 -- REDUCE
# ---------------------------------------------------------------------------
def probe_gr14():
  print("=== gr_14: REDUCE, on a STATIC shape")
  buf = leaf(0, 6)
  red = UOp(Ops.REDUCE, src=(buf,), arg=(Ops.ADD, 1))
  print("    the REDUCE node: op=%s nsrc=%d arg=%r shape=%r" % (red.op.name, len(red.src), red.arg, red.shape))
  ctx = leaf(1, 6)
  reset()
  try:
    grads = compute_gradient(red, ctx, {buf})
    print("    grads: %s" % " ".join("%s->%s" % (tok(k), tok(v)) for k, v in grads.items()))
    report("gr_14")
    for k, v in grads.items():
      print("    the gradient of %s is %s arg=%r shape=%r" % (tok(k), tok(v), getattr(v, "arg", None), v.shape))
  except Exception as e:
    print("    RAISED %s: %s" % (type(e).__name__, e))
    report("gr_14")


# ---------------------------------------------------------------------------
# THE ARITY BUG the port's comment records -- reproduced, on upstream's OWN reshape
# ---------------------------------------------------------------------------
def probe_arity():
  print("=== the RESHAPE ARITY, on upstream's OWN reshape (2 srcs) and on a 1-src one")
  buf = leaf(0, 6)
  r2 = buf.reshape((2, 3))
  lg = pm_gradient.rewrite(r2, ctx=leaf(1, 6))
  print("    upstream's own reshape: len(lgrads)=%d  len(t0.src)=%d  -> %s"
        % (len(lg), len(r2.src), "ARITY MATCHES" if len(lg) == len(r2.src) else "MISMATCH"))
  r1 = UOp(Ops.RESHAPE, src=(buf,), arg=(2, 3))
  lg1 = pm_gradient.rewrite(r1, ctx=leaf(1, 6))
  print("    a ONE-src RESHAPE:      len(lgrads)=%d  len(t0.src)=%d  -> %s"
        % (len(lg1), len(r1.src), "ARITY MATCHES" if len(lg1) == len(r1.src) else "MISMATCH"))


probe_gr17()
probe_gr14()
probe_arity()
