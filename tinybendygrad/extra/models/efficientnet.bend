import Base
import ./../../tensor.bend as T
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../dtype.bend as DT
import ./../../nn/__init__.bend as NN
import ./../../nn/layers.bend as LN
import ./../../nn/pool.bend as PL
import ./../../nn/state.bend as ST
import ./../../mixin/op.bend as MO
import ./../../mixin/movement.bend as MX
import ./../../mixin/rand.bend as RD
import ./../../mixin/elementwise.bend as E
import ./../datasets/__init__.bend as D

# not yet ported.
#
# the only model here that stores its weights as bare `Tensor`s rather than in
# LAYER CLASSES, and that single design decision removes this file's most
# obvious blocker and creates a different one. `self._expand_conv =
# Tensor.glorot_uniform(oup, input_filters, 1, 1)` (upstream:11) is a TENSOR,
# not a `Conv2d`, so `nn.Conv2d` is NEVER NAMED in this file -- and therefore
# this is the only model in the directory whose first constructor line resolves
# to an existing def.
#
# TODO(port): STOPPED AT `MBConvBlock.__init__` (extra/models/efficientnet.py:7),
# at upstream:11
#       self._expand_conv = Tensor.glorot_uniform(oup, input_filters, 1, 1)
#   and that line IS BUILT: `rd_glorot_uniform` (mixin/rand.bend:943 symbol=rd_glorot_uniform) over the
#   bound `nn_glorot` (nn/__init__.bend:208). THE FIRST LINE THAT IS NOT is
#   upstream:12
#       self._bn0 = BatchNorm2d(oup, track_running_stats=track_running_stats)
#   and the blocker is NOT the normalisation -- `pool_bn` (nn/pool.bend:371 symbol=pool_bn) IS
#   BUILT and `pool.bend:43-47` measures `Tensor.batchnorm` as a pure
#   DECOMPOSITION (`x - mean`, `* weight`, `.mul(invstd)`, `+ bias`). The blocker
#   is the HALF OF BatchNorm THAT IS NOT A DECOMPOSITION: the running-statistics
#   update, refused at `pool.bend:404`, whose two causes are NAMED there --
#   "`TRAINING` is not a binding in tinybendygrad (comments only)" and
#   "`Tensor.assign` is not a def (tinybendygrad/tensor.bend:2497 symbol=t_alu3 states the immutability
#   divergence)".
#
#   and here that half is not optional. Upstream:39 is
#       x = self._bn0(x.conv2d(self._expand_conv)).swish()
#   which takes BatchNorm's EVAL branch (nn/__init__.py:43,
#   `track_running_stats and not TRAINING`) -- the branch `pool.bend:401-403`
#   calls "the ONLY path ResNet INFERENCE takes" and "buildable". So an
#   EfficientNet at INFERENCE needs the built half and could use it. But this
#   constructor's `track_running_stats=True` (:8) is the TRAINING default, and
#   `load_from_pretrained` (:134) reads `running_mean`/`running_var` OUT of the
#   checkpoint. A model that cannot be trained and cannot be loaded is a model
#   that can only ever produce its own random initialisation.
#
# `avg_pool2d` is built (`pool_avgpool`, nn/pool.bend:252) but not for the calls
# THIS FILE MAKES, and that is worth stating precisely because it is the kind of
# near-miss a count hides:
#   upstream:44  x.avg_pool2d(kernel_size=x.shape[2:4])     -- UNPADDED, BUILT
#   upstream:130 x.avg_pool2d(kernel_size=x.shape[2:4])     -- UNPADDED, BUILT
#   upstream:134-163 `count_include_pad` never appears here, so this file is
#                UNAFFECTED -- and `inception.py` is not.
# Both of the calls are `kernel_size = the whole spatial extent`, i.e. an
# ADAPTIVE-to-1x1 pool with a DYNAMIC kernel read out of the tensor's own shape.
# `pool_adaptive_avg` (nn/pool.bend:304 symbol=pool_adaptive_avg) takes an `AP` RECORD
# with the input
# dims as `U32` values, so a caller must already have projected the shape --
# `nn_shape` (nn/layers.bend:92) answers a `Maybe<&2, List<&2, U32>>`, and on
# the `SU` arm it answers `None`. THAT IS THE SEAM, and it is a `Maybe` rather
# than a wall.
#
# every DEF below refuses, and the return TYPE is `D.Refused`, not a tensor. a
# stub that returned a zero Tensor would be indistinguishable from a weight that
# happens to be zero -- and in THIS file that is not a hypothetical, because
# every weight IS a bare Tensor and a zeroed Tensor is exactly what a failed
# initialiser looks like. `refuse`/`Refused` are DECLARED ONCE at
# `extra/datasets/__init__.bend:40-46` and imported as `D`.
# THE GATE MOVED TO `gates/models-efficientnet-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
