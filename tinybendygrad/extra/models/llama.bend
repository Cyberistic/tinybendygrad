import Base
import ./../../tensor.bend as T
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../dtype.bend as DT
import ./../../nn/__init__.bend as NN
import ./../../nn/state.bend as ST
import ./../../nn/layers.bend as LN
import ./../../mixin/op.bend as MO
import ./../../mixin/movement.bend as MX
import ./../../mixin/reduce.bend as RC
import ./../../mixin/elementwise.bend as EW
import ./../../mixin/creation.bend as CR
import ./../../mixin/rand.bend as RD
import ./../../nn/optim.bend as OPT
import ./../datasets/__init__.bend as D

# stub -- 1:1 path mirror of extra/models/llama.py (286 loc). not yet ported.
#
# llama is the furthest of the three transformers and it is furthest by a
# different reason than the other two. bert.bend and t5.bend both fail on a layer
# (`nn.Embedding`, `nn.LayerNorm`/`nn.RMSNorm`). llama fails on a STACK: FOUR
# norms where BERT has one kind and T5 has a hand-written one.
#
# the named census for this file:
#   `nn.Embedding`  MISSING. (:201,:202) `grep -rnwE "def .*Embedding" --include='*.bend' tinybendygrad/` = 0, and so is `def mo_i`/`def mo_fx`.
#   `nn.RMSNorm`    missing. (:53,:54,:137,:138,:200)  five sites, and this is the first missing symbol of the file: extra/models/llama.py:53 `self.q_norm
#   `Tensor.scaled_dot_product_attention` MISSING. (:101,:104) `grep -rnwE "def .*scaled_dot_product_attention" --include='*.bend'` = 0.
#   `softmax`       EXISTS, mixin/op.bend:1141 symbol=mo_softmax `mo_softmax` (:165 in `sample`).
#   `adam`          EXISTS and UNUSED BY THIS FILE. nn/optim.bend:858 symbol=op_mstep
#                   `op_mstep` is
#                   `(self.b1 * self.m[i] + (1.0 - self.b1) * g).cast(...)` -- verbatim, upstream's
#                   `assign` at nn/optim.py:167 (inside upstream's `Adam._step`, declared at
#                   nn/optim.py:161 symbol=_step), and nn/optim.bend:863 symbol=op_vstep
#                   `op_vstep`
#                   is upstream's `assign` at nn/optim.py:168; `op_mhat`/`op_vhat` are
#                   upstream's `m_hat`/`v_hat` at nn/optim.py:169-170. The optimizer
#                   llama.py would train with is ALREADY PORTED; llama.py only INFERENCES.
#                   that is the answer to "does a training LOOP need something new": no. The
#                   adam half is DONE; a training loop would add a loss (`binary_crossentropy_logits`, extra/models/bert.py:61, MISSING).
#
# what exists and llama gets it from the vision work, with its instrument:
#   `nn.Linear`           nn/layers.bend:518 symbol=nn_linear `nn_linear`   (:45,:46,:47,:48,:51,:123,:124,:125,:202)
#   `Tensor.silu`         mixin/elementwise.bend:1199 symbol=ew_silu `ew_silu` (:128) -- and it is `ew_swish` :1220 symbol=ew_swish, no extra def
#   `Tensor.sin`          mixin/elementwise.bend:538 `ew_sin`  (:10)
#   `Tensor.arange`       mixin/rand.bend:427 symbol=op_arange `op_arange`     (:8,:9,:167)
#   `Tensor.stack`        mixin/movement.bend:1257 symbol=mxw_stk `mxw_stk`  (:10,:90)
#   `Tensor.zeros`        mixin/creation.bend:526 symbol=cr_zeros `cr_zeros`  (:83,:158,:170)
#   `Tensor.zeros_like`   mixin/creation.bend:561 symbol=cr_zeros_like `cr_zeros_like` (:158)
#   `x.reshape`           mixin/movement.bend:1414 `mxw_reshape` (:10,:22,:23,:34,:59,:60,:61,:62,:73,:74,:75,:118,:233)
#   `x.transpose`         mixin/movement.bend:1432 `mxw_permute` (:100,:101,:103,:104)
#   `x.repeat`            nn/layers.bend:627 symbol=nn_repeat `nn_repeat`      (:34)
#   `x.softmax`           mixin/op.bend:1141 symbol=mo_softmax `mo_softmax`     (:165)
#   `x.cast`              mixin/op.bend:386 symbol=mo_cast_t `mo_cast_t`       (:10,:204,:216)
#   `x.contiguous_backward` mixin/elementwise.bend:534 `ew_contiguous_backward` (:64,:71,:129,:142,:216)
#   `x.sigmoid`/`x.tanh`  mixin/elementwise.bend:1173 symbol=g_unary / :1232  (through ew_sigmoid, which llama does not name)
#
# the three that are llama-only and not attention-anywhere-ELSE:
#   (1) `Tensor.cos`   MISSING. (:10) mixin/elementwise.bend:538 has `def ew_sin` and there is
#                     NO `def ew_cos`. RoPE needs the pair and only half of it landed.
#   (2) `Tensor.erf`   MISSING. extra/models/bert.py:236 needs it too.
#   (3) `Tensor.multinomial` MISSING. (:184,:187) and `logits.argmax()` MISSING (:151).
#                     `mixin/rand.bend:873 rd_randperm` records at rand.py:249 that
#                     `argsort` is a bitonic sort over four nested Python `for` loops and
#                     marks it `TODO(p3)` -- `multinomial` sits behind the same sort.
#
# not ported, and named so nobody invents it:
#   * `cache_kv` (extra/models/llama.py:82,:83,:86,:90,:92,:93) -- the kv cache is
#     an IN-PLACE slice-assign on a
#     realized tensor plus a `hasattr`/`isinstance(device, tuple)`/`shard_` probe.
#     `nn/optim.bend:3-44` records the same wall for its own in-place arm.
#   * `TinyJit` (:205,:224) -- resnet.bend's census at :116-123 already names it PARTIAL:
#     `engine/jit.bend` is a real port and the `TinyJit` NAME and DECORATOR are not.
#   * `Variable` (:3,:56,:140,:207,:221,:224) -- a shape VALUE symbol, not a tensor op.
#   * `getenv("WQKV"/"STUB_ATTENTION"/"SHARD_KVCACHE")` (:44,:57,:86,:105) -- flag reads.
#   * `convert_from_huggingface` (:230) and `convert_from_gguf` (:269) are dict-key
#     remappers over a weights dict. They are not arithmetic and they are not gated
#     by anything the port has; both refuse on the weights dict itself.
#
# TODO(port): STOPPED AT `Attention.__init__` (extra/models/llama.py:36).
# FIRST MISSING SYMBOL: `nn.RMSNorm(dim, qk_norm)` at extra/models/llama.py:53, which the `if` at
# :53 guards on `qk_norm is not None` -- so it is the SECOND statement of the
# constructor, after four `linear(...)` calls that EXIST, and it is unconditional in
# every configuration llama.py actually builds -- `Transformer.__init__` at extra/models/llama.py:195-196
# passes `qk_norm` through at :199, and every public config in meta's llama sets it).
# THE GATE MOVED TO `gates/models-llama-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
