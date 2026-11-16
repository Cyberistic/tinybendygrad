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

# stub -- 1:1 path mirror of extra/models/bert.py (300 loc). not yet ported.
#
# the first missing thing is `nn.Embedding`, and it is one of the four the
# VISION MODELS NEVER ASKED FOR. `grep -rnwE "def .*Embedding" --include='*.bend'
# tinybendygrad/` = 0, and so is `grep -rnwE "def .*mo_i\(|def .*mo_fx\("`. The
# resnet.bend census at :40-123 asks for conv2d, batchnorm, linear, sequential,
# argmax, item, torch_load, fetch, get_child, rand and TinyJit; `Embedding` is not
# among them because a convnet indexes a weight tensor by spatial offset, never by
# a token id. Three of the eight files in this directory cannot name one weight
# without it.
#
# what bert gets for free from the vision work, and this is measured, not hoped:
#   `nn.Linear`             nn/layers.bend:518 symbol=nn_linear  (:16,:130,:225,:264,:265,:266,:292,:310,:239)
#   `Tensor.stack`          mixin/movement.bend:1257 symbol=mxw_stk (:40)
#   `reshape`               mixin/movement.bend:1417 symbol=mxw_reshape (:37,:38,:282,:287)
#   `transpose`             mixin/movement.bend:1435 symbol=mxw_permute (:281,:288)
#   `log_softmax`           mixin/op.bend:1155 symbol=mo_log_softmax (:54)
#   `Tensor.arange`         mixin/rand.bend:427 symbol=op_arange     (:55,:192)
#   `Tensor.zeros`          mixin/creation.bend:526 symbol=cr_zeros  (:141)
#   `Tensor.ones`           mixin/creation.bend:567 symbol=cr_ones   -- needed by T5, not here
#   `Tensor.cast`/`.float()`mixin/op.bend:386 symbol=mo_cast_t     (:54,:70)
#   `x.relu`                nn/layers.bend:292 symbol=nn_relu -- BERT has none; recorded so the
#                           census is a census and not a list of what is convenient
#   `x +` / `x *`           mixin/elementwise.bend:499/510 `ew_add`/`ew_mul` (:56,:67,:197,:232)
#   `Adam`                   nn/optim.bend -- `op_mstep` :898 `op_vstep` :903 `op_mhat` `op_vhat`.
#                           bert does not construct one, but its tf loader at :90 filters on
#                           `["adam_v", "adam_m", "beta1_power", "beta2_power"]`, so the names
#                           are load-bearing here even though the optimizer is not called.
#
# what bert asks for that no vision model asked for -- the named four:
#   (1) `nn.Embedding`      MISSING. (:182,:183,:184,:46) THE FIRST MISSING SYMBOL.
#   (2) `nn.LayerNorm`      MISSING. (:149,:185,:226,:293) `grep -rnwE "def .*layernorm" = 0`.
#   (3) `Tensor.scaled_dot_product_attention` MISSING. (:279) THE WALL for :270.
#   (4) `Tensor.dropout`    MISSING. (:199,:231,:298) and `:29` skips dropout keys, so the
#                           NAME is in the loader even where the op is not.
# and two more, both bert-only:
#   (5) `gelu` as BERT DEFINES IT, at :236 -- `x * 0.5 * (1.0 + (x / 1.41421).erf())`.
#       `ew_gelu` is MISSING (mixin/elementwise.bend:754 has only the CONSTANT `ew_k.gelu`)
#       and `.erf` is MISSING entirely. clip.py:12 `gelu = Tensor.gelu` is the OTHER
#       gelu, the openai one, so the two files disagree about what the word means.
#   (6) `Tensor.binary_crossentropy_logits` MISSING (extra/models/bert.py:61, extra/models/bert.py:72).
#   (7) `Tensor.argmax` MISSING (:66,:70) -- resnet.bend's census names it MISSING too, so
#       this is NOT a new ask; it is the FIRST one that BERT hits and resnet only reaches
#       it in `postprocess`.
#   (8) `Tensor.chunk` MISSING (:36).
#
# TODO(port): STOPPED AT `BertEmbeddings.__init__` (extra/models/bert.py:180).
# FIRST MISSING SYMBOL: `Embedding(vocab_size, hidden_size)` at extra/models/bert.py:182, where
# `Embedding = nn.Embedding` is the module-level alias at extra/models/bert.py:9 and there is no `def Embedding`
# anywhere under `tinybendygrad/`, and no `def mo_i` either.
# the `mo_fx` half of this evidence was FALSE. corrected 2026-10-20: `def mo_fx1d` is at
# `mixin/op.bend:1287` symbol=mo_fx1d and `def mo_fx2d` at `mixin/op.bend:1295` symbol=mo_fx2d,
# so "no `def mo_fx` anywhere" was falsifiable
# and falsified -- the audit's grep demanded a literal `(` after the name and matched neither.
# the conclusion is unchanged and was never in doubt: `mixin/op.bend:1295` symbol=mo_fx2d
# shows both are FIXTURES
# returning `r` unchanged, not a gather, and `def mo_i` is still absent. A CITATION WRONG ON ITS
# evidence and right on its conclusion still misleads the next reader, who checks the evidence.
#
# the two `load_from_pretrained` are not a porting problem and should not be
# TREATED AS ONE. extra/models/bert.py:78-124 reads a TENSORFLOW checkpoint through
# `tf.train.list_variables` (extra/models/bert.py:85), and the TORCH loader is
# `extra/models/bert.py:24-31`, whose `torch.load` is at extra/models/bert.py:26. `THE PORT's `helpers.bend` HEADER`
# already records the whole weight-download seam as unported I/O, and neither framework
# has a counterpart. Named here so no reader counts them as arithmetic left undone.
#
# `gelu` (:235-236) and `gather` (:161-164) are module-level functions and both are
# NOT PORTED: `gather` (:164) is `onehot @ prediction_logits` and `one_hot` is MISSING,
# and the one-hot itself is built from `Tensor.arange` + `expand` + `==`.
# THE GATE MOVED TO `gates/models-bert-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
