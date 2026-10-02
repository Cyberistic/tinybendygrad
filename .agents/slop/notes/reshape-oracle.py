import sys; sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, ParamArg, dtype_from_uop   # noqa: E402
from tinygrad import dtypes                                      # noqa: E402


def buf(size, name='4', slot=0):
  return UOp(Ops.BUFFER, (), ParamArg(slot, dtypes.i32, size=size, device='CPU'))


def st(*dims):
  return UOp(Ops.STACK, tuple(UOp.const(d) for d in dims))


def sig(tag, u):
  try:
    shp = None if u._shape is None else tuple(f'{x}:{type(x).__name__}' for x in u._shape)
  except Exception as e:
    shp = f'RAISE {type(e).__name__}: {e}'
  print(f'{tag:16} shape={shp} dtype={u.dtype.name} srcops={[s.op.name for s in u.src]}')


b4 = buf(4)

# 1. THE 2-D FIXTURE, built two ways: by hand and through `_mop`. CPython's ucache
#    makes them the SAME node, which is the hash-consing the Bend arena mirrors.
m = UOp(Ops.RESHAPE, (b4, st(2, 2)))
sig('resh_2d', m)
m_mop = b4._mop(Ops.RESHAPE, (2, 2))
print('   same node as by-hand:', m is m_mop, ' nsrc:', len(m_mop.src))

# 2. THE ONE-ELEMENT MARG, a bare CONST -- movement.py:184's identity test
m1 = b4._mop(Ops.RESHAPE, (4,))
sig('resh_1d', m1)
print('   identity ret==self:', m1.shape == b4.shape, '(oracle wants True)')

# 3. THE NOOP SPECIAL CASE with a WRONG product on purpose
mno = UOp(Ops.RESHAPE, (UOp(Ops.NOOP, (b4,)), st(2, 3)))
sig('resh_noop', mno)
print('   marg:', mno.marg, '(the NOOP arm skips BOTH checks)')

# 4-6. THE THREE `raise`s
sig('resh_badprod', UOp(Ops.RESHAPE, (b4, st(2, 3))))
sig('resh_negative', UOp(Ops.RESHAPE, (b4, UOp.const(-2))))
sym = UOp(Ops.SPECIAL, (UOp.const(0),), 'N')
sig('resh_symbolic', UOp(Ops.RESHAPE, (b4, UOp(Ops.STACK, (UOp.const(2), sym)))))

# 7. dtype_from_uop: `if op in GroupOp.Movement: return src[0].dtype`
print('dtype buf  =', dtype_from_uop(Ops.RESHAPE, (b4, UOp.const(4)), None).name)
print('dtype noop =', dtype_from_uop(Ops.RESHAPE, (UOp(Ops.NOOP, (b4,)), UOp.const(4)), None).name)
