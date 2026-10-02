import sys; sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, ParamArg   # noqa: E402
from tinygrad import dtypes                        # noqa: E402



def buf(size, slot=0):
  return UOp(Ops.BUFFER, (), ParamArg(slot, dtypes.i32, size=size, device='CPU'))


# movement.py:184-185, the identity half the task names: `return self if
# ret.shape == self.shape else ret`. Over a (4,) source and a one-element marg the
# ret.shape IS self.shape, so `_mop` hands the ORIGINAL node back -- the same node
# `rewritten` compares by identity.
b4 = buf(4)
t4 = (2, 2)
r1 = UOp(Ops.RESHAPE, (b4, UOp.const(4)))
print('r1.shape          =', r1.shape)
print('r1._mop(RESHAPE) is r1 :', b4._mop(Ops.RESHAPE, (4,)) is b4)
print('b4._mop(RESHAPE,(4,)) is b4 :', b4._mop(Ops.RESHAPE, (4,)) is b4)
print('b4._mop(RESHAPE,(2,2)).shape =', b4._mop(Ops.RESHAPE, (2, 2)).shape)

# THE MOVEMENT RULE the gate row is about: rule 2 is the RESHAPE-on-RESHAPE arm, whose
# `x.shape` read was the fold's hole. Python's `movement_rewrite` over a chain of
# RESHAPEs must collapse to b4.
src = UOp(Ops.RESHAPE, (b4, UOp.const(4)))
print()
print('before chain: shape=', src.shape, 'id=', id(src) % 100000)
out = src._mop(Ops.RESHAPE, t4)
print('after  _mop : shape=', out.shape, 'id=', id(out) % 100000)
print('chain collapsed to b4 (identity):', out is b4)

# and the thing that WAS the wall: `x.shape` on a RESHAPE src is answerable in CPython
print()
print('x.shape where x is a RESHAPE:', src.shape, '(this is rule 2\'s read)')

# the shape the fold now answers, spelled out
print('r1 (reshape over reshape) shape:', src.shape, 'dtype:', src.dtype.name)