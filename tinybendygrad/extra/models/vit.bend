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
import ./../../mixin/rand.bend as RD
import ./transformer.bend as TR
import ./../datasets/__init__.bend as D

# stub -- 1:1 path mirror of extra/models/vit.py (73 loc). not yet ported.
#
# the only model in this directory that does not begin with a convolution, and
# that is the whole of its distinctive blocker. Every other file here names
# `nn.Conv2d` in its first constructor; `ViT.__init__` names `Tensor.uniform`,
# `Tensor.zeros` and `Tensor.ones` (upstream:8-11,16-17) -- all FOUR are built
# (`rd_uniform` mixin/rand.bend:918 symbol=rd_uniform, `cr_zeros` mixin/creation.bend:526 symbol=cr_zeros,
# `cr_ones` mixin/creation.bend:567 symbol=cr_ones) -- and then names `TransformerBlock` at
# upstream:13.
#
# TODO(port): STOPPED AT `ViT.__init__` (extra/models/vit.py:6), at upstream:13
#       TransformerBlock(embed_dim=embed_dim, num_heads=num_heads,
#                        ff_dim=embed_dim*4, prenorm=True, act=lambda x: x.gelu())
#   `extra/models/transformer.py` IS PORTED AS A FILE -- `transformer.bend` is on
#   disk and 1:1 with upstream's 61 LOC -- but every def in it REFUSES, and its
#   own header (transformer.bend:18-26) names the single missing primitive:
#   `Tensor.scaled_dot_product_attention`. `gates/models-transformer-gate.bend:54 symbol=tf_block_attn` is
#   `tf_block_attn`, which refuses on it, and `THE PORT's `mixin/rand.bend` HEADER` carries
#   FOUR walls for its arms -- "GQA arm", "the matmul", "the causal mask", "the
#   attn_mask arm". So this file is not blocked on a sibling that is absent. it
#   is blocked on a sibling that is present and refusing, which is a different
#   AND MORE USEFUL FACT: `tf_block_init` (transformer.bend:92) is the exact
#   address to go to, and its refusal carries the exact symbol.
#
#   the second blocker, and it is one unbelievably short line: upstream:29
#       x = x.layernorm().linear(*self.encoder_norm)
#   `Tensor.layernorm` does not exist. `THE PORT's `nn/__init__.bend` WALL BLOCK` names it as an
#   open wall -- "TODO(p3) mixin/op.py:1661 x.layernorm -- SIDE B, not built" --
#   and that line is STILL TRUE even though the `x.conv2d` (:231), `x.batchnorm`
#   (:229) and `x.linear` (:227) walls beside it stopped being true, because
#   `nn/layers.bend` and `nn/pool.bend` were written to close exactly those
#   three and nobody went back for layernorm. the wall list decayed and nothing
#   noticed, which is the point of naming it by line instead of by "side b".
#
# THE `-1` IN `x.reshape(shape=(x.shape[0], x.shape[1], -1))` (upstream:21) IS A
# real missing primitive and it is not a layer. `mxw_reshape`
# (mixin/movement.bend:1417 symbol=mxw_reshape) takes an EXPLICIT `List<&2, U32>`; it does not infer
# an axis. `nn/pool.bend:317 symbol=pool_flatten` states the same boundary for its own `flatten`
# ("`-1` is NOT spelled because no def here infers an axis (that is
# `Tensor.reshape`'s `get_shape`, and the port writes its targets out)"). So
# :21 needs a `get_shape`/`prod` inference the port does not have, and :30's
# `x[:, 0]` needs a SLICE, which `rd_slice` (mixin/rand.bend:479 symbol=rd_slice) is not.
#
# `Tensor.gelu` is named twice -- `act=lambda x: x.gelu()` at :14 and nothing
# else in this file. Plain `gelu` is NOT a def: `mixin/elementwise.bend:1198 symbol=ew_swish`
# is `ew_quick_gelu`, using the `1.702` constant (`ew_k.quick_gelu` :774), and
# `elementwise.bend:43` lists `erf` among the operations this tree lacks.
#
# `np.load` (upstream:40) AND `Tensor.assign` (upstream:45-71, TWENTY-SEVEN
# CALLS) ARE THE LOADER. `pool.bend:397` names the second: "`Tensor.assign` --
# nn/__init__.py:56 `self.running_mean.assign(...)`
# divergence outright ("Python's `is_param_` mutates in place; this returns a
# new [tensor]"). So `ViT` cannot load a single one of its parameters, which is
# worth saying plainly: a ViT whose weights cannot be written is a ViT that can
# only ever produce its own random initialisation.
#
# every DEF below refuses, and the return TYPE is `D.Refused`, not a tensor. a
# stub that returned a zero Tensor would be indistinguishable from a layer whose
# weights happen to be zero. `refuse`/`Refused` are DECLARED ONCE at
# `extra/datasets/__init__.bend:40-46` and imported as `D`. Each message names
# the upstream `path:line` of the FIRST MISSING SYMBOL.

# THE GATE MOVED TO `gates/models-vit-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
