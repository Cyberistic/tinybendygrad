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

# not yet ported.
#
# clip is both halves at once, and that is why it is the one file in this slice
# whose walls overlap resnet.bend's and bert.bend's rather than choosing.
# Its vision half (`ClipVisionTransformer`, :338) asks for `nn.Conv2d`, which
# resnet.bend's census at :68-81 called MISSING and which is NOW BUILT --
# nn/layers.bend:923 `nn_conv2d`. Its text half (`ClipTextTransformer`, :318)
# asks for `nn.Embedding` (:319) and `nn.LayerNorm` (:322), both of which
# resnet.bend NEVER ASKED FOR and both of which are MISSING.
# So the honest reading of THE PORT's `resnet.bend` HEADLINE BLOCK -- "`nn.Conv2d`, `nn.BatchNorm2d` AND
# `nn.Linear` ARE ALL MISSING" -- is STALE for conv2d and linear, and
# `nn/layers.bend:14-27` says so in its own words: "the wall text named the wrong
# BLOCKER, MEASURED AGAINST WHAT IS ON DISK."
#
# the named census for this file:
#   `nn.Embedding`  MISSING (:201,:202,:319) -- the TEXT side.
#   `nn.LayerNorm`  MISSING (:182,:184,:222,:289,:292,:322,:348,:349) -- SEVEN sites,
#                     and this is why clip.py is further from running than retinanet.py
#                     even though both are "vision".
#   `nn.Conv2d`     EXISTS, nn/layers.bend:923 `nn_conv2d` (:343). THE VISION HALF'S
#                     ONLY conv.
#   `nn.Linear`     EXISTS, nn/layers.bend:518 `nn_linear` (:153,:154,:167-170,:261,:279,:280)
#   `Tensor.scaled_dot_product_attention` MISSING (:176,:271) -- BOTH attention sites.
#   `Tensor.quick_gelu` EXISTS, mixin/elementwise.bend:1205 `ew_quick_gelu` (:157).
#   `Tensor.gelu`    AS A BODY, MISSING (mixin/elementwise.bend:754 symbol=ew_k.gelu has only the
#                     CONSTANT `ew_k.gelu`). clip.py:12 binds `Tensor.gelu`, NOT
#                     `Tensor.quick_gelu`, so :156's `h.quick_gelu()` reaches the
#                     body that EXISTS while the module-level alias points at one
#                     that does not. Both facts are recorded because both are true.
#   `Tensor.argmax`  MISSING (:335,:470) -- the EOS-pooling index.
#   `Tensor.triu`    MISSING (:324) -- and it is NOT a creation op: THE PORT's `mixin/creation.bend` HEADER
#                     names `tril`/`triu` in the inventory it measures itself against
#                     and records that they are not in that file either.
#   `Tensor.empty`   mixin/creation.bend:424 `cr_empty` EXISTS (:320,:323,:345,:346,:351).
#   `Tensor.full`    mixin/creation.bend:499 `cr_full`  EXISTS (:324).
#   `Tensor.arange`  mixin/rand.bend:422 `op_arange`   EXISTS (:470).
#   `x.reshape`/`view` mixin/movement.bend:1414 `mxw_reshape` EXISTS.
#   `x.permute`      mixin/movement.bend:1432 `mxw_permute` EXISTS (:272,:290,:463).
#   `x.expand`       nn/layers.bend:625 `nn_expand`     EXISTS (:356).
#   `x.cat`          MISSING (:356) -- and `mx_cat` at mixin/movement.bend:125 is
#                     SHAPE ARITHMETIC `(a,b) -> a+b`, not the op.
#   `x @ proj`       nn/layers.bend:476 `nn_dot` EXISTS but RETURNS `Maybe`, so
#                     `pooled = x @ self.text_projection` (:337,:361,:471) is not
#                     a call that type-checks today.
#   `x.sin`/`x.cos`  NOT NAMED BY clip.py. (extra/models/llama.py:10 needs `.cos` and there is
#                     no `def ew_cos`; clip.py does not share that wall.)
#   `square().sum().sqrt()`  ALL THREE EXIST: ew_square (mixin/elementwise.bend:545 symbol=ew_square),
#                     mo_mean/mo_sum (mixin/op.bend:877 / nn/layers.bend:238),
#                     ew_sqrt (mixin/elementwise.bend:537). The Frobenius norm at
#                     :475,:478 is PORTABLE.
#   `adam`           NOT USED BY THIS FILE.
#   `softmax`        NOT USED DIRECTLY -- both attention sites delegate to
#                     `scaled_dot_product_attention`. `mo_softmax`
#                     (mixin/op.bend:1078) EXISTS and would serve T5 but not this.
#
# the first 140 lines are a bpe tokenizer and are not a porting problem.
# clip.py:15 `default_bpe()` `fetch`es a gzip file (:17), clip.py:17
# `bytes_to_unicode` is a 256-entry dict, and clip.py:60 `gzip.open` +
# `:75 re.compile` are Python string machinery. THE PORT's `helpers.bend` HEADER already
# records the whole HTTP/download seam as unported. Named here so the LOC count
# is not read as arithmetic left undone.
#
# not ported, and named so nobody invents it: `OpenClipEncoder.prepare_image`
# (:446) is PIL -- `from PIL import Image` at :447, `.resize(..., BICUBIC)`,
# `.crop`, `np.array(image.convert('RGB'))` -- and is HOST I/O, not a graph.
#
# TODO(port): STOPPED AT `Open.ClipTextTransformer.__init__` (extra/models/clip.py:318).
# FIRST MISSING SYMBOL: `Embedding(vocab_size, width)` at clip.py:319.
# REACHED BEFORE IT, AND PORTED: `Tensor.empty(ctx_length, width)` at :320
# (mixin/creation.bend:424 symbol=cr_empty) and `Tensor.empty(width, width)` at :323.
# THE GATE MOVED TO `gates/models-clip-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
