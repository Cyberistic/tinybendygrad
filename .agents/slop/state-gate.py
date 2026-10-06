#!/usr/bin/env python3
"""The CPython lane for `tinybendygrad/nn/state.bend`'s gate.

    .venv/bin/python .agents/slop/state-gate.py > /tmp/py.txt
    ./bin/bend tinybendygrad/nn/state.bend          > /tmp/bd.txt
    diff

NOTHING IS EXECUTED ON A DEVICE. `get_state_dict` returns NAMES, and a name is a
function of the object SHAPE alone, so the whole oracle is `str.strip`, `str(i)`
and dict insertion order. `TensorIO.seek` is the one row that reads a tensor and
it reads only `len()`, which for a `Tensor([1.0], dtype='uint8')` is 1 with no
device touched.

THE PRINTER MATCHES THE PORT. The port's `sd_keys` joins keys with a trailing
`","` and `sd_names` joins `NAME:DTYPE,`; this oracle does the same, so a diff is
a diff of VALUES and not of formatting. `sd_tens` is the row that depends on it:
a bare tensor's key is the empty string, which prints as `","` on both sides.
"""
import sys, os, collections
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)
from tinygrad import Tensor, dtypes
from tinygrad.nn.state import (get_state_dict, get_parameters, safe_dtypes,
                               inverse_safe_dtypes, TensorIO)

def keys(o, prefix=''):
  return ''.join(k + ',' for k in get_state_dict(o, prefix=prefix).keys())

def row(nm, b):
  print('%s=%s' % (nm, b))

t1, t2, t3 = Tensor([1.0]), Tensor([2.0]), Tensor([3.0])

# sd_tens -- a bare tensor. `get_state_dict(t)` is `{'': t}`; the key is
# `''.strip('.')` at state.py:103.
row('sd_tens', keys(t1) == ',')

# sd_map -- `{'w': t}`
row('sd_map', keys({'w': t1}) == 'w,')

# sd_seq -- `[t, t]`. The keys are INDICES: the list arm's `f"{prefix}{str(i)}."`
# at state.py:109.
row('sd_seq', keys([t1, t2]) == '0,1,')

# sd_nest -- a mapping of a list of mappings, with the middle child a non-mapping
# so that `OOther` (Python's `state_dict` staying `{}` at :107) is covered: a relu
# in the middle of `Model.layers` contributes no key and does not shift the rest.
bn = {'weight': t1, 'bias': t2, 'num_batches_tracked': t3, 'running_mean': t1, 'running_var': t2}
row('sd_nest', keys({'layers': [bn, Tensor.relu, {'weight': t3}]}) ==
  'layers.0.weight,layers.0.bias,layers.0.num_batches_tracked,layers.0.running_mean,'
  'layers.0.running_var,layers.2.weight,')

# sd_strip -- `prefix.strip('.')` over six prefixes. `a..b..` is the one that
# matters: the interior run SURVIVES.
row('sd_strip', all(p.strip('.') == q for p, q in
  [('', ''), ('.', ''), ('..', ''), ('.a.', 'a'), ('a..b..', 'a..b'), ('a', 'a')]))

# sd_attr -- rungs 2 and 4: a namedtuple's `_asdat()` and an object's `__dict__`.
NT = collections.namedtuple('NT', 'a b')
class C:
  def __init__(self): self.q = t1
row('sd_attr', keys(NT(t1, t2)) == 'a,b,' and keys(C()) == 'q,')

# sd_ord -- THE ORDERING FIXTURE. An OrderedDict is a dict AND it HAS a
# `__dict__` (measured: `dict(OrderedDict().__dict__) == {}`), so Python's rung 3
# and rung 4 both claim it and only the ORDER gives `['z','a']` instead of `[]`.
od = collections.OrderedDict([('z', t1), ('a', t2)])
row('sd_ord', keys(od) == 'z,a,' and hasattr(od, '__dict__'))

# sd_dup -- THE DICT-COLLAPSE FIXTURE. `dict.update` keeps the FIRST position and
# the LAST value; the port's `sd_put` has to be told. The count and the value are
# asserted separately so a filter-instead-of-overwrite would fail the second.
d1, d2 = Tensor([1.0]), Tensor([1.0, 2.0])
sd = get_state_dict({'a.b': d1, 'a': {'b': d2}})
row('sd_dup', list(sd.keys()) == ['a.b'] and sd['a.b'].numel() == 2)

# sd_safe -- the 15 `safe_dtypes` KEYS in the source's order. The KEYS are the
# safetensors spellings and they are state.py's own data, which is why this row
# is a diff line; the dtypes are `sd_safedt`.
#
# THE DTYPE NAME VOCABULARIES DIFFER AND THE DIFF MUST NOT HIDE IT. `spec.bend`'s
# `Dt.nm` is the C spelling (`signed char`, `unsigned char`, `float8_e4m3`,
# `__bf16`) and tinygrad's `DType.name` is the short one (`char`, `uchar`,
# `fp8e4m3`, `bfloat16`); 8 of the 15 differ. `spec.bend` is READ-ONLY to this
# unit, so the port prints its vocabulary and the ORACLE would print the other
# one, and a joined `NAME:DTYPE` row would be red for a reason that is neither
# side's bug. The keys row and the bijection row below are the diffable claims.
row('sd_safe', ','.join(safe_dtypes.keys()) ==
  'BOOL,I8,U8,I16,U16,I32,U32,I64,U64,F8_E4M3,F8_E5M2,F16,BF16,F32,F64')

# sd_safedt -- the table is a BIJECTION onto 15 distinct dtypes, checked through
# the port's real lookup path (`sd_get`, a search over the table) rather than by
# restating the table. `safe_load` does `safe_dtypes[v['dtype']]` and `safe_save`
# does `inverse_safe_dtypes[v.dtype]`, so a table that mapped two spellings to
# one dtype would lose a tensor on the round trip with no error anywhere.
names = ['bool', 'char', 'uchar', 'short', 'ushort', 'int', 'uint', 'long', 'ulong',
         'fp8e4m3', 'fp8e5m2', 'half', 'bfloat16', 'float', 'double']
row('sd_safedt', all(getattr(dtypes, n) is safe_dtypes[k]
  for n, k in zip(names, safe_dtypes.keys()))
  and len({id(v) for v in safe_dtypes.values()}) == 15)

# sd_invn -- a COUNT and not a boolean, because a table that lost its last entry
# would still satisfy every per-entry row.
row('sd_invn', len(safe_dtypes) == 15)

# sd_inv -- the round trip. `safe_load` looks a spelling UP and `safe_save` looks
# a dtype UP, so a table that is not a bijection corrupts one direction silently.
row('sd_inv', all(inverse_safe_dtypes[safe_dtypes[k]] == k for k in safe_dtypes))

# sd_seek -- `TensorIO.seek`'s clamp. `H.i64_text` prints `hi:lo`, and a U32 that
# wraps -1 to 4294967295 would print `4294967295:4294967295` where the answer is
# `0:0`. The two negative offsets are the rows that catch it.
u8 = Tensor([1.0], dtype='uint8')
def sk(args):
  io = TensorIO(u8)
  io.seek(*args)
  return '%d:%d' % (io._position >> 32 & 4294967295, io._position & 4294967295)
row('sd_seek', sk((0,)) == '0:0' and sk((1,)) == '0:1' and sk((-1,)) == '0:0'
  and sk((1, 1)) == '0:1' and sk((0, 2)) == '0:1' and sk((9,)) == '0:1'
  and sk((-5,)) == '0:0')

# sd_param -- `len(get_parameters(...))` is the count of LEAVES. The fixture is a
# three-entry layer list with a non-mapping in the middle: 5 + 2 = 7.
class Net:
  def __init__(self):
    self.layers = [bn, Tensor.relu, {'weight': t3, 'bias': t1}]
row('sd_param', len(get_parameters(Net())) == 7)
