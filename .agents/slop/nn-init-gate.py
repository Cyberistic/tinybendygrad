#!/usr/bin/env python3
"""The CPython lane for `tinybendygrad/nn/__init__.bend`'s gate.

    .venv/bin/python .agents/slop/nn-init-gate.py > /tmp/py.txt
    ./bin/bendygrad/nn/__init__.bend          > /tmp/bd.txt
    diff

NOTHING IS COMPUTED ON A DEVICE. Every row is a `.shape`, a `.padding`, an
`.axis`, a `state_dict` key list or an `is_param` flag, and every one of those is
a graph fact in tinygrad and a plain Python value here. The float rows
(`nn_glorot`, `nn_formula`) print the f32 IMAGE of the Python double -- via
`numpy.float32` -- because the port's answer is an `F32` and comparing an f32
against a double would be red for a rounding reason rather than a formula reason.

THE PRINTERS MATCH THE PORT. `H.i64_text` prints `hi:lo`, so a Python `-1` prints
as `4294967295:4294967295` and a `1` as `0:1`; `nn_u` and `nn_k` join with a
trailing `","`. Every row below is printed through the same join so a diff is a
diff of values and not of formatting.
"""
import sys, os, math, struct
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)
from tinygrad import Tensor, nn
from tinygrad.nn.state import get_state_dict

def i64(v):
  # `H.i64_text` is `hi:lo` of the TWO'S COMPLEMENT pair, and the two words are
  # NOT symmetric: `hi` is the SIGN EXTENSION (0xFFFFFFFF or 0) and `lo` is the
  # low word's unsigned mask. Two wrong versions of this helper, both caught by
  # the diff: the first subtracted 2^32 from the low word of a negative and
  # printed `4294967295:-4294967297`, and the second masked BOTH words and
  # printed `1:1` for the value 1. `hi` is only 0 or 0xFFFFFFFF here because
  # every negative in this file is -1 or -2.
  return '%d:%d' % (0xFFFFFFFF if v < 0 else 0, v & 0xFFFFFFFF)
def u(xs): return ''.join('%d,' % x for x in xs)
def i(xs): return ''.join(i64(x) + ',' for x in xs)
def k(es): return ''.join(x + ',' for x in es)
def row(nm, b): print('%s=%s' % (nm, b))
def f32(x): return '%.8g' % struct.unpack('f', struct.pack('f', x))[0]

KS3, KS5 = (3, 3), (5, 5)

# nn_conv -- `Tensor.uniform(out_channels, in_channels//groups, *kernel_size)`,
# :106, for the four convolutions `beautiful_mnist.py` builds at lines 10-14.
row('nn_conv', u(nn.Conv2d(1, 32, 5).weight.shape) == '32,1,5,5,'
  and u(nn.Conv2d(32, 32, 5).weight.shape) == '32,32,5,5,'
  and u(nn.Conv2d(32, 64, 3).weight.shape) == '64,32,3,3,'
  and u(nn.Conv2d(64, 64, 3).weight.shape) == '64,64,3,3,')

# nn_convb -- `Tensor.uniform(out_channels)` at :107
row('nn_convb', u(nn.Conv2d(1, 32, 5).bias.shape) == '32,')

# nn_conv0 -- the DEGENERATE `in_channels//groups` at :106. It is `0` and not an
# error: tinygrad only divides, it does not validate. A port that guarded it
# would answer 1 and this row would go red.
row('nn_conv0', u(nn.Conv2d(1, 4, 3, groups=2).weight.shape) == '4,0,3,3,')

# nn_same -- `padding='same'` at :99-103, over the square cases and the
# non-square one. `dilation` MULTIPLIES the pad, so d=2 is 2 not 1.
row('nn_same', u(nn.Conv2d(1, 1, 3, padding='same').padding) == '1,1,1,1,'
  and u(nn.Conv2d(1, 1, 3, padding='same', dilation=2).padding) == '2,2,2,2,'
  and u(nn.Conv2d(1, 1, 3, padding='same', dilation=3).padding) == '3,3,3,3,'
  and u(nn.Conv2d(1, 1, (3, 4), padding='same').padding) == '1,2,1,1,')

# nn_same_rev -- the SAME non-square fixture as its own row. It is duplicated on
# purpose: `nn_same` is a conjunction of four cases and a conjunction reports one
# Bool, so a reader cannot tell WHICH case moved. This row can.
row('nn_same_rev', u(nn.Conv2d(1, 1, (3, 4), padding='same').padding) == '1,2,1,1,')

# nn_ks2 -- `make_tuple(kernel_size, 2)` at :98, the INT arm
row('nn_ks2', nn.Conv2d(1, 1, 5).kernel_size == KS5)

# nn_c1d -- `Conv1d` wraps its kernel in a 1-tuple at :78, so a 1-D conv's
# `padding='same'` has length 2 and not 4.
row('nn_c1d', u(nn.Conv1d(1, 1, 3, padding='same').padding) == '1,1,')

# nn_lin -- `Tensor.uniform(out_features, in_features)` at :174 and the bias at
# :175. 576 is beautiful_mnist's own derived width, not a number this file picks.
row('nn_lin', u(nn.Linear(576, 10).weight.shape) == '10,576,'
  and u(nn.Linear(576, 10).bias.shape) == '10,')

# nn_bn_mask -- `shape_mask = [1, -1, *([1]*(x.ndim-2))]` at :42. `ndim` is not
# an argument of `__init__`, so the oracle evaluates the EXPRESSION for the three
# ranks a 2-D and a 3-D norm see. The ndim=1 case is the saturating one:
# `[1] * -1` is `[]` in Python and the two head elements are still there.
row('nn_bn_mask', i([1, -1] + [1] * (4 - 2)) == '0:1,4294967295:4294967295,0:1,0:1,'
  and i([1, -1] + [1] * (2 - 2)) == '0:1,4294967295:4294967295,'
  and i([1, -1] + [1] * (1 - 2)) == '0:1,4294967295:4294967295,')

# nn_bn_axes -- `reduce_axes = tuple(x for x in range(x.ndim) if x != 1)` at :47
row('nn_bn_axes', tuple(x for x in range(4) if x != 1) == (0, 2, 3)
  and tuple(x for x in range(2) if x != 1) == (0,))

# nn_bn_st -- the `__dict__` ORDER at :33-39. `eps`, `track_running_stats` and
# `momentum` are assigned FIRST and are not tensors, so `get_state_dict` drops
# them (state.py:107) and the five keys are what remain, in assignment order.
b = nn.BatchNorm(32)
sd = get_state_dict(b)
row('nn_bn_st', k(sd.keys()) == 'weight,bias,num_batches_tracked,running_mean,running_var,'
  and k('%s' % v.is_param for v in sd.values()) == 'True,True,False,False,False,')

# nn_bn_flags -- the two ternaries at :35-36 (`affine`) and :39 (`track`) are
# INDEPENDENT, so two rows: `affine=False` keeps `num_batches_tracked` because
# :38 is outside both ternaries, and `track=False` keeps weight and bias.
row('nn_bn_flags', k(get_state_dict(nn.BatchNorm(4, affine=False)).keys())
  == 'num_batches_tracked,running_mean,running_var,'
  and k(get_state_dict(nn.BatchNorm(4, track_running_stats=False)).keys())
  == 'weight,bias,num_batches_tracked,')

# nn_bn_shapes -- `Tensor.ones(sz)`/`Tensor.zeros(sz)` at :35-36 and the SCALAR
# `Tensor.zeros(dtype='long')` at :38, whose shape is the empty tuple.
# `affine=False` is `None` in Python, not a shape, so there is nothing to call
# `.shape` on. The PORT encodes "no parameter" as the EMPTY shape list, and that
# is a DIVERGENCE stated rather than hidden: `Nil{}` is this file's spelling of
# Python's `None` and it is why `bn_w`'s signature carries the `affine` Bool at
# all. The Python fact being asserted here is that the attribute is `None`.
row('nn_bn_shapes', u(nn.BatchNorm(32).weight.shape) == '32,'
  and u(nn.BatchNorm(32).bias.shape) == '32,'
  and nn.BatchNorm(32, affine=False).weight is None
  and u(nn.BatchNorm(32).num_batches_tracked.shape) == '')

# nn_ct -- `ConvTranspose2d.__init__` reassigns `self.weight` at :150 with the
# in/out channels the OTHER WAY ROUND. The `__dict__` key order is unaffected by
# a reassignment, so the shape is the whole claim.
row('nn_ct', u(nn.ConvTranspose2d(1, 2, 3).weight.shape) == '1,2,3,3,'
  and u(nn.Conv2d(1, 2, 3).weight.shape) == '2,1,3,3,')

# nn_ln -- `self.axis = tuple(-1-i for i in range(len(self.normalized_shape)))`
# at :253. Two rows' worth in one, because the one-element axis is the case a
# "just prepend -1" implementation gets right for free.
row('nn_ln', i(nn.LayerNorm(3).axis) == '4294967295:4294967295,'
  and i(nn.LayerNorm((2, 3)).axis)
    == '4294967295:4294967295,4294967295:4294967294,')

# nn_ln_sh -- `Tensor.ones(*self.normalized_shape)` at :254
row('nn_ln_sh', u(nn.LayerNorm((2, 3)).weight.shape) == '2,3,')

# nn_ln2d -- `x.permute(0, 2, 3, 1).permute(0, 3, 1, 2)` at :279. The two index
# LISTS are the whole method, and the second is the INVERSE of the first.
row('nn_ln2d', u((0, 2, 3, 1)) == '0,2,3,1,' and u((0, 3, 1, 2)) == '0,3,1,2,')

# nn_gn -- `x.reshape(x.shape[0], num_groups, -1)` at :203/:231 and the affine
# `reshape(1, -1, *[1] * (x.ndim-2))` at :207/:233. The `-1` is Python's INFERRED
# dim and the whole reshape is illegal without it.
row('nn_gn', i((2, 2, -1)) == '0:2,0:2,4294967295:4294967295,'
  and i([1, -1] + [1] * (4 - 2)) == '0:1,4294967295:4294967295,0:1,0:1,')

# nn_rms -- `Tensor.ones(dim)` at :298 and `x.square().mean(-1, keepdim=True)`'s
# axis at :300, resolved against the rank.
row('nn_rms', u(nn.RMSNorm(4).weight.shape) == '4,' and u((4 - 1,)) == '3,')

# nn_emb -- `Tensor.glorot_uniform(vocab_size, embed_size)` at :389
row('nn_emb', u(nn.Embedding(10, 3).weight.shape) == '10,3,')

# nn_glorot -- mixin/rand.py:197, `(6 / (fan_in + prod(shape[1:]))) ** 0.5`. It is
# a `sqrt` of a RATIO and NOT `1/sqrt`; the two differ by `sqrt(6)` and a port
# that used `nn_bound` here would answer `0.2773501` against Python's
# `0.6793662`. This row is the reason the two are separate defs.
row('nn_glorot', f32((6 / (10 + 3)) ** 0.5) == '0.67936623')

# nn_lstm -- the four parameter shapes at :409-412, `hidden_size*4` in three
row('nn_lstm', u(nn.LSTMCell(3, 4).weight_ih.shape) == '16,3,'
  and u(nn.LSTMCell(3, 4).weight_hh.shape) == '16,4,'
  and u(nn.LSTMCell(3, 4).bias_ih.shape) == '16,')

# nn_lstm_st -- the four `__dict__` keys in assignment order at :409-412
row('nn_lstm_st', k(get_state_dict(nn.LSTMCell(3, 4)).keys())
  == 'weight_ih,weight_hh,bias_ih,bias_hh,')

# nn_formula -- `1 / math.sqrt(in_c * prod(ks))` at :105 for `Conv2d(1,32,5)` and
# `1 / math.sqrt(in_features)` at :173 for `nn.Linear(576,10)`. The U32-to-F32
# conversion at the real call site is a `TODO(p3)` (`U32.to_f32` is an unfilled
# law); the FORMULAS are what is gated, which is why the factors are literals.
row('nn_formula', f32(1 / math.sqrt(1 * 25)) == '0.2'
  and f32(1 / math.sqrt(576)) == '0.041666668')
