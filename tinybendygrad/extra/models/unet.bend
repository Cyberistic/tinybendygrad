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
import ./../../mixin/creation.bend as CR
import ./../../mixin/elementwise.bend as E
import ./../datasets/__init__.bend as D

# stub -- 1:1 path mirror of extra/models/unet.py (262 loc). not yet ported.
#
# the largest file in this directory after inception.py, and the only one that
# IS NOT A VISION CLASSIFIER: it is a Stable-Diffusion UNet, so it brings
# three things no other model here names -- an ATTENTION (`Tensor.scaled_dot_
# product_attention`), a CONDITIONAL EMBEDDING (`timestep_embedding`, upstream:10,
# built from `Tensor.arange`/`cos`/`sin`/`cat`), and a DEVICE CAPABILITY QUERY
# (`Device[Device.DEFAULT].renderer.supported_dtypes()`, :15 and :240).
#
# TODO(port): STOPPED AT `timestep_embedding` (extra/models/unet.py:10), at
# upstream:12
#       freqs = (-math.log(max_period) * Tensor.arange(half) / half).exp()
#   `Tensor.arange` is MISSING. `grep -rnE '^def (rd|cr)_[a-z_]*arange\('
#   --include='*.bend' tinybendygrad/` returns 0; the nearest defs are
#   `cr_full` (mixin/creation.bend:499 symbol=cr_full) and `mo_range`/`mx_range` (nn/layers.bend
#   :110), and those answer a RANGE OF INDICES for a permute order, not a TENSOR.
#   `Tensor.exp` IS built (`ew_exp`, mixin/elementwise.bend:1290 symbol=ew_exp), so :12 is
#   blocked by its SECOND half only -- and the sentence above says which.
#
#   the headline, which is farther up and worth naming first: upstream:7 binds
#       attention = Tensor.scaled_dot_product_attention
#   and that symbol is MISSING. `gates/models-transformer-gate.bend:42` reaches the
#   same wall and the port's `mixin/rand.bend` walls block carries four arms of it -- "gqa arm",
#   "the matmul", "the causal mask", "the attn_mask arm", each "BLOCKED: needs".
#   so unet and transformer share one blocker, and it is the same one.
#
# the other two that no count would reveal, because they are one-line calls to
# FAMILIAR NAMES:
#   `Tensor.cat`   MISSING. :14 builds the embedding with it, and so does
#                  `CrossAttention` (:57) and `UNetModel.__call__` (:259).
#   `Tensor.cos`   MISSING. `tn_sin` IS built (tensor.bend:416); there is no
#                  `cos` ENTRY anywhere -- `grep -rnE '^def (tn|ew)_cos\('
#                  --include='*.bend' tinybendygrad/` returns 0. That asymmetry is
#                  worth recording, because `sin` existing makes `cos` look like a
#                  typo rather than a gap.
#   `Tensor.chunk` MISSING (:68). `Tensor.unsqueeze` MISSING (:13).
#   `Tensor.layernorm` MISSING (:87,:88,:89) -- THE PORT's `nn/__init__.bend` WALL BLOCK.
#   `GroupNorm` MISSING (:20,:29,:105,:227). `pool_bn` (nn/pool.bend:371 symbol=pool_bn) IS
#   BUILT, but it is BatchNorm's decomposition: mean/variance over CHANNELS with
#   a learned affine. GroupNorm's `num_groups` split is a different reduction
#   and `nn/__init__.bend` holds no class for it.
#   `Device[...].renderer.supported_dtypes()` MISSING (:15,:240). There is no
#   such query in `runtime/`; `dtype.bend` carries dtypes and `uop/ops.bend`
#   carries the op, but "what can THIS device do" is a runtime fact with no
#   def.
#
# what is already here is worth saying too, because it removes the obvious
# GUESS: `Tensor.silu` IS built (`ew_silu`, mixin/elementwise.bend:1199 symbol=ew_silu, which is
# `ew_swish` at :1208) and this file names it FIVE times (:21,:25,:27,:229,:240).
# `Tensor.expand` IS built (`cr_expand`, mixin/creation.bend:340 symbol=cr_expand) and :137 needs
# it. `Tensor.conv2d` (`nn_conv2d`, nn/layers.bend:923 symbol=nn_conv2d) and `Tensor.linear`
# (`nn_linear`, :427) EXIST. So this file is not far; it is far in FOUR PLACES
# AT ONCE, which is the shape a diffusion UNet has.
#
# every DEF below refuses, and the return TYPE is `D.Refused`, not a tensor. a
# stub that returned a zero Tensor would be indistinguishable from a layer whose
# weights happen to be zero. `refuse`/`Refused` are DECLARED ONCE at
# `extra/datasets/__init__.bend:40-46` and imported as `D`. Each message names
# the upstream `path:line` of the FIRST MISSING SYMBOL.

# THE GATE MOVED TO `gates/models-unet-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
