import Base
import ./../../tensor.bend as T
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../dtype.bend as DT
import ./../../nn/__init__.bend as NN
import ./../../nn/layers.bend as LN
import ./../../nn/state.bend as ST
import ./../../mixin/op.bend as MO
import ./../../mixin/movement.bend as MX
import ./../../mixin/elementwise.bend as E
import ./../datasets/__init__.bend as D

# stub -- 1:1 path mirror of extra/models/convnext.py (63 loc). not yet ported.
#
# what changed since `resnet.bend` was written, and this file is the evidence:
# the port's `resnet.bend` headline block still reads "nn.Conv2d, nn.BatchNorm2d and nn.Linear are all
# MISSING", and THE PORT's `resnet.bend` HEADLINE BLOCK cites
# the port's `mixin/op.bend` last line as "side b is the
# BUILT THE OPS:
#   `Tensor.conv2d`  nn/layers.bend:923 symbol=nn_conv2d `nn_conv2d`   -- from the primitives,
#                        `mixin/op.bend`'s SIDE B never having been filled
#   `Tensor.linear`   nn/layers.bend:518 symbol=nn_linear `nn_linear`
#   `Tensor.relu`     nn/layers.bend:292 symbol=nn_relu `nn_relu` (a NAME onto `tn_relu`,
#                        tensor.bend:767, not a second copy)
# and `tinybendygrad/nn/pool.bend` built `Tensor.batchnorm` (pool.bend:371 symbol=pool_bn) and
# the pools. So the arithmetic a ConvNeXt block needs IS in the tree. What is
# still absent is every LAYER CLASS: `nn/__init__.bend` has 17 defs
# (`grep -cE '^def ' nn/__init__.bend` = 17) and all 17 are shape arithmetic --
# `nn_app nn_len nn_neg1 nn_i64_app nn_mt nn_mt_seq nn_half nn_prod nn_groups
# nn_k1 nn_pair.right nn_pair.left nn_pad.go nn_same nn_scale nn_bound nn_glorot`
# -- and ZERO classes. `layers.bend` supplied FUNCTIONS where upstream had
# METHODS; the CONSTRUCTORS that own weights and fill a state dict are the part
# nobody has written, for any model, in this tree.
#
# TODO(port): STOPPED AT `Block.__init__` (extra/models/convnext.py:5).
#   The FIRST line of that constructor (:7) is
#       self.dwconv = Conv2d(dim, dim, kernel_size=7, padding=3, groups=dim)
#   `Tensor.conv2d` is BUILT (`nn_conv2d`, nn/layers.bend:923 symbol=nn_conv2d, and it already
#   takes `groups` and a `Maybe<&2, List<&2, U32>>` padding, so both arguments
#   are expressible) -- but there is NO `nn.Conv2d` CLASS: nothing builds the
#   `(dim, dim, 7, 7)` weight, nothing gives the layer a name, and nothing makes
#   it a `get_state_dict` (nn/state.bend:308) node.
#   and the second line is a harder miss: `:8 self.norm = LayerNorm(dim,
#   eps=1e-6)`. `Tensor.layernorm` does not exist. The port says so in its own
#   words at `nn/__init__.bend:219`: "TODO(p3) mixin/op.py:1661 x.layernorm --
#   SIDE B, not built", and that line is still true even though the conv2d and
#   linear lines beside it stopped being true.
#   so the honest first blocker is the constructor, and the honest first
#   *PRIMITIVE* BEHIND IT IS `Tensor.layernorm`.
#
# THE TWO SPELLINGS OF A VALUE, because upstream keeps them apart and this file
# must too: `Tensor.gelu` is named at :16 and `x.gelu()` inside the `act` is
# the same method. `mixin/elementwise.bend:1205 symbol=ew_quick_gelu` is `ew_quick_gelu`, which uses
# the `1.702` constant (`ew_k.quick_gelu`, :774). Plain `gelu` is NOT a def:
# elementwise.bend:43 lists `erf` among the operations this file does not have,
# and :758 records that the `0.044715` cubic is a CLOSE APPROXIMATION that
# "is wrong in the ninth" place. So :16 is REFUSED on the primitive rather than
# silently answered with the quick variant.
#
# `Tensor.sequential` (:14, :31, :32) is MISSING for every model in this
# directory. `grep -rniE '^def .*sequential' --include='*.bend' tinybendygrad/`
# returns 0, and the refusal below names the address rather than describing it.
#
# THE WEIGHT LOADER (:44-52) is the same seam every model in this directory
# stops at, and THE PORT's `resnet.bend` SYMBOL CENSUS already measures it for `fetch`. Its extra
# member here is `Tensor.assign` at :51 -- `pool.bend:397` names the instrument
# ("`Tensor.assign` -- tinygrad/nn/__init__.py:56 `self.running_mean.assign(...)`", and
# `tensor.bend:2679 symbol=tn_param.of` states the divergence: "Python's `is_param_` mutates in
# place; this returns a new [tensor]"), so `mv.assign(...)` and `.realize()` are
# both refused for the same reason BatchNorm's running stats are.
#
# every DEF below refuses, and the return TYPE is `D.Refused`, not a tensor. a
# stub that returned a zero Tensor or an empty list would be indistinguishable
# from a layer whose weights happen to be zero. `refuse` and the `Refused` type
# are DECLARED ONCE at `extra/datasets/__init__.bend:40-46` and imported as `D`.
# Each message names the upstream `path:line` of the FIRST MISSING SYMBOL.
# THE GATE MOVED TO `gates/models-convnext-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
