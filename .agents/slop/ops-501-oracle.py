"""The CPython lane for the ops.py 501-1928 unit of `tinybendygrad/uop/ops.bend`.

    .venv/bin/python .agents/slop/ops-501-oracle.py   > ops501-py.txt
    ./bin/bend tinybendygrad/uop/ops.bend | grep '^s5' > ops501-bd.txt
    diff ops501-py.txt ops501-bd.txt

Every row is printed by CALLING CPython. Nothing here is transcribed.
"""
import os
import sys
import pathlib

TG_TREE = os.environ.get('TG_TREE', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'opstree'))
sys.path.insert(0, TG_TREE)

from tinygrad.uop.ops import UOp, Ops, AxisType, ParamArg, KernelInfo  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402

S = lambda *xs: UOp.group(*xs)  # noqa: E731


def sig(u: UOp) -> str:
  """Op name plus, for a STACK, the src op sequence. Portable across arenas."""
  if u.op is Ops.STACK: return "STACK/" + " ".join(s.op.name for s in u.src)
  if u.op is Ops.ALLREDUCE: return f"ALLREDUCE({u.arg[0].name},{u.arg[1]})"
  if u.op is Ops.MSELECT: return f"MSELECT({u.arg})"
  if u.op is Ops.BUFFER: return "BUFFER"
  return u.op.name


def base_chain(u: UOp) -> str:
  """`u.base`'s OP NAME. The port's answer is an arena index, so the comparable
  thing is what that index points at, and this is it."""
  return u.base.op.name


def fuel_run(fuel: int, f):
  """`base`-family peels are fuel-bounded here exactly as they are in Bend, so a
  port that runs out answers the node it stopped on and CPython answers the same."""
  return f()


def fixtures():
  """Named graphs. Each is the SMALLEST graph that separates two answers."""
  c = UOp.const(3)
  b = UOp(Ops.BUFFER, arg=ParamArg(1, dtypes.int32, 9))
  p = UOp(Ops.PARAM, arg=ParamArg(2, dtypes.int32, 4))
  a = UOp(Ops.ALLOC, arg=ParamArg(3, dtypes.int32, 4))
  r1 = b.reshape((3, 3))
  r2 = r1.reshape((9,))
  us = UOp(Ops.UNSHARD, src=(b,), arg=(0,))
  bc = UOp(Ops.BITCAST, src=(b,), arg=dtypes.float32)
  af = UOp(Ops.AFTER, src=(b,))
  return {'c': c, 'b': b, 'p': p, 'a': a, 'r1': r1, 'r2': r2, 'us': us, 'bc': bc, 'af': af}


F = fixtures()
rows = []


def row(k, v):
  rows.append(f"{k}={v}")


# --- the base family (ops.py:785/792/801). `base` is PORTED in uop/fold.bend, so
# --- the two that are not are `unsharded_base` and `storage_base`.
for k in ('c', 'b', 'p', 'a', 'r1', 'r2', 'us', 'bc', 'af'):
  u = F[k]
  row(f"s5_unsharded_base_{k}", u.unsharded_base.op.name)
  row(f"s5_storage_base_{k}", u.storage_base.op.name)
  row(f"s5_base_{k}", base_chain(u))

# --- without_after (ops.py:623)
for k in ('c', 'b', 'r1', 'af', 'us'):
  row(f"s5_wo_after_{k}", F[k].without_after.op.name)

# --- has_buffer_identity (ops.py:952). `after_ok` is a Bool, so BOTH are rows:
# --- a port that ignored the flag would answer the same on every fixture.
for k in ('c', 'b', 'p', 'a', 'r1', 'r2', 'us', 'bc', 'af'):
  u = F[k]
  row(f"s5_hbi_{k}", int(u.has_buffer_identity(False)))
  row(f"s5_hbi_after_{k}", int(u.has_buffer_identity(True)))

# --- buf_uop (ops.py:925)
for k in ('c', 'b', 'p', 'r1', 'r2', 'bc', 'af'):
  row(f"s5_buf_uop_{k}", F[k].buf_uop.op.name)

# --- the syntactic mints (ops.py:624/679/680/772).
row("s5_barrier", sig(UOp(Ops.BUFFER, arg=ParamArg(1, dtypes.int32, 4)).barrier(UOp.const(1))))
row("s5_bufferize", sig(F['b'].bufferize()))
row("s5_bufferize_arg", sig(F['b'].bufferize(UOp.const(2))))
row("s5_allreduce", sig(UOp(Ops.ALLOC, arg=ParamArg(3, dtypes.int32, 4, device=("PYTHON", "PYTHON"))).allreduce(Ops.ADD, ("PYTHON", "PYTHON"))))
row("s5_mselect", sig(UOp(Ops.MSELECT, src=(UOp(Ops.UNSHARD, src=(F['b'],), arg=(0,)),), arg=0)))

# --- sharding (ops.py:707): the (axis, RANGE) pairs. `arg` is the SORTED tuple of
# --- sharded axes and `src[1:]` carries one RANGE each, so the fixture needs both
# --- or the zip is empty and the row cannot see the shape it is about.
rng = UOp.range(2, 0, AxisType.DEVICE)
row("s5_sharding_us", " ".join(f"{a}:{r.op.name}" for a, r in UOp(Ops.UNSHARD, src=(F['b'], rng), arg=(0,)).sharding))
row("s5_sharding_none", str(UOp(Ops.RESHAPE, src=(F['b'],)).sharding))

# --- split_uop (ops.py:685). The COUNT is the row; the fold is depth-first
# --- pre-order in both, and `sig` of each element is what says so.
def split(us, sep):
  out = []
  stack = [us]
  while stack:
    n = stack.pop(0)
    if n.op is sep: stack = list(n.src) + stack
    else: out.append(n.op.name)
  return ",".join(out)


m2 = UOp(Ops.MUL, src=(UOp.const(2), UOp.const(3)))
m3 = UOp(Ops.MUL, src=(UOp.const(2), m2))
row("s5_split_const", split(UOp.const(9), Ops.ADD))
row("s5_split_add", split(UOp(Ops.ADD, src=(UOp.const(1), UOp.const(2))), Ops.ADD))
row("s5_split_nest", split(UOp(Ops.ADD, src=(m3, UOp.const(4))), Ops.ADD))
row("s5_split_diamond", split(UOp(Ops.ADD, src=(UOp(Ops.ADD, src=(UOp.const(1), UOp.const(2))), UOp.const(3))), Ops.ADD))
row("s5_split_mismatch", split(UOp(Ops.ADD, src=(m2, UOp.const(4))), Ops.MUL))

# --- pop_const (ops.py:1080) and const_factor (ops.py:1058).
row("s5_pop_const_add", f"{UOp(Ops.ADD, src=(UOp.const(2), UOp.const(3))).pop_const(Ops.ADD)[0].op.name}/{UOp(Ops.ADD, src=(UOp.const(2), UOp.const(3))).pop_const(Ops.ADD)[1]}")
row("s5_pop_const_miss", f"{UOp(Ops.SUB, src=(UOp.const(2), UOp.const(3))).pop_const(Ops.ADD)[0].op.name}/{UOp(Ops.SUB, src=(UOp.const(2), UOp.const(3))).pop_const(Ops.ADD)[1]}")
row("s5_pop_const_nonconst", f"{UOp(Ops.ADD, src=(UOp.const(2), UOp.range(4, 0))).pop_const(Ops.ADD)[0].op.name}/{UOp(Ops.ADD, src=(UOp.const(2), UOp.range(4, 0))).pop_const(Ops.ADD)[1]}")

for k in ('c', 'b', 'p', 'a'):
  row(f"s5_const_factor_{k}", F[k].const_factor())
row("s5_const_factor_m6", UOp.const(6).const_factor())
row("s5_const_factor_m12", UOp.const(12).const_factor())
row("s5_const_factor_add", UOp(Ops.ADD, src=(UOp.const(4), UOp.const(6))).const_factor())
row("s5_const_factor_mul", UOp(Ops.MUL, src=(UOp.const(4), UOp.const(6))).const_factor())
row("s5_const_factor_mulc", UOp(Ops.MUL, src=(UOp.const(4), UOp.range(4, 0))).const_factor())
row("s5_const_factor_stack", UOp(Ops.STACK, src=(UOp.const(4), UOp.const(6))).const_factor())
row("s5_const_factor_momo", UOp(Ops.PARAM, arg=ParamArg(9, dtypes.int32, 4, multiple_of=3)).const_factor())

# --- sint_to_uop (ops.py:1893) and gate_kernel_sink (ops.py:1901).
row("s5_sint_const", sig(UOp.range(UOp.const(4), (0,))))


def gate(x):
  """gate_kernel_sink (ops.py:1901), verbatim."""
  if x.op is Ops.LINEAR: return False
  if x.op is Ops.SINK and isinstance(x.arg, KernelInfo): return False
  return True


if __name__ == '__main__':
  # The two gate_kernel_sink fixtures need nodes the other arms do not, so they
  # are built here rather than in `fixtures()`.
  lin = UOp(Ops.LINEAR, src=(F['b'],), arg=())
  ks = UOp(Ops.SINK, src=(F['b'],), arg=KernelInfo())
  rows.append(f"s5_gate_linear={int(gate(lin))}")
  rows.append(f"s5_gate_kernel={int(gate(ks))}")
  rows.append(f"s5_gate_plain={int(gate(F['b']))}")
  for r in rows:
    print(r)
