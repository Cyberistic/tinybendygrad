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
# T5 is the cheapest of the attention files and the reason is worth naming:
# of the five in this slice that have attention -- transformer:27, bert:279,
# clip:176 and :271, llama:101 and :104 -- t5 is the only one that spells its
# ATTENTION OUT INSTEAD OF CALLING `scaled_dot_product_attention`. UPSTREAM
# `extra/models/t5.py` HAS NO `scaled_dot_product_attention` AT ALL -- NOT AT THE
# PIN AND NOT AT ANY REVISION -- so the claim is an ABSENCE, and the claim about
# what IS there is the one the citation has to carry: extra/models/t5.py:210
# symbol=Tensor.matmul is `Tensor.matmul(query_states, key_states.transpose(3, 2))`
# and the PORT's OWN extra/models/t5.py:217 (upstream has NO extra/models/ AT THIS PIN) is
# `Tensor.matmul(attn_weights, value_states)` -- it never reaches the fused op.
# So T5's SECOND wall is `Tensor.matmul`, which is MISSING
# (`grep -rnE "^def mo_matmul" --include='*.bend' tinybendygrad/` = 0), while
# `Tensor.softmax` at the PORT's own extra/models/t5.py:215 IS PRESENT as
# mixin/op.bend:1141 symbol=mo_softmax.
# `THE PORT's `mixin/op.bend` HEADER` names `matmul` as WALL 8 -- "a WMMA lowering over
# `UOp(Ops.WMMA, ...)` with a device-specific arg" -- but `THE PORT's `nn/layers.bend` HEADER`
# says the same name is a LIE for the LAYER's arithmetic: `nn_dot` there is
# RESHAPE + RESHAPE + PERMUTE + MUL + REDUCE + CAST, all six of which EXIST.
# So `Tensor.matmul` is `nn_dot` renamed, and extra/models/t5.py is CLOSER THAN BERT.
#
# WHAT EXISTS, WITH ITS INSTRUMENT:
#   `nn.Linear`        nn/layers.bend:518 symbol=nn_linear   (:77,:78,:79,:112,:113,:114,:115)
#   `Tensor.softmax`   mixin/op.bend:1141 symbol=mo_softmax  (:216)  <-- the named family, PRESENT
#   `Tensor.mean`      mixin/op.bend:938 symbol=mo_mean      (:65)
#   `Tensor.min`       mixin/op.bend:1176 symbol=mo_min      (:158) the REDUCTION; matches the
#                                                      `axis=0` at :162
#   `Tensor.where`     mixin/elementwise.bend:559 symbol=ew_where (:164)
#   `Tensor.log`       mixin/elementwise.bend:1256 symbol=ew_log  (:153)
#   `Tensor.pow(2)`    mixin/elementwise.bend:508 symbol=ew_pow  (:65) -- a BINOP, which is what
#                                                      `pow(2)` is here
#   `Tensor.ones`      mixin/creation.bend:567 symbol=cr_ones  (:56)
#   `Tensor.zeros_like` mixin/creation.bend:561 symbol=cr_zeros_like (:142)
#   `Tensor.full_like` mixin/creation.bend:522 symbol=cr_full_like  (:160)
#   `Tensor.arange`    mixin/rand.bend:427 symbol=op_arange  (:169,:170)
#   `Tensor.stack`     mixin/movement.bend:1257 symbol=mxw_stk (:159)
#   `x.reshape`/`view` mixin/movement.bend:1417 symbol=mxw_reshape (:178,:190,:194,:258)
#   `x.transpose`      mixin/movement.bend:1435 symbol=mxw_permute (:178,:190,:194,:210)
#   `x.cast`           mixin/op.bend:386 symbol=mo_cast_t     (:10,:65,:156,:216)
#
# WHAT IS MISSING, NAMED:
#   (1) `nn.Embedding`  MISSING. (:118,:251,:270) THE FIRST MISSING SYMBOL.
#   (2) `Tensor.matmul` MISSING. (:210,:218) THE SECOND WALL, and the one that makes T5
#       unlike BERT.
#   (3) `Tensor.rsqrt`  MISSING. (:66) `grep -rnE "^def mo_rsqrt" = 0`. NOTE
#       `nn/pool.bend:377` has `pool_rsqrt` = `MO.mo_recip(E.ew_sqrt(t))` -- that IS
#       rsqrt, but it is NAMED FOR A BATCHNORM and is not reachable as `Tensor.rsqrt`.
#   (4) `Tensor.abs`    MISSING. (:145)
#   (5) `Tensor.gelu`   MISSING as a BODY. mixin/elementwise.bend:754 symbol=ew_k.gelu has the CONSTANT
#       `ew_k.gelu` and :1217 has `ew_quick_gelu`, but there is no `def ew_gelu`.
#       (:82)
#   (6) `Tensor.cat`    MISSING. (:285)
#   (7) `Tensor.gelu`   and above: `Tensor.gelu` is the openai gelu, the SAME ONE
#       clip.py:11 binds. bert.py:235 defines the BERT gelu over `.erf`, which is a
#       different function under the same name in the same directory.
#
# ON `adam`: NOT USED BY THIS FILE. t5.py constructs no optimizer and names no
# optimizer slot. It is named here because it is the second of three files in this
# directory where a reader would assume it, and the answer is that
# `nn/optim.bend:858 symbol=op_mstep` / `:903 op_vstep` EXIST and go unused by all three.
#
# THE TOKENIZER IS NOT A PORTING PROBLEM. t5.py:26 imports `SentencePieceProcessor`
# from the `sentencepiece` package (the file's own line 1 is the pip install), and
# t5.py:44 wraps it. There is no counterpart and there will not be one in the port.
#
# TODO(port): STOPPED AT `T5Attention.__init__` (extra/models/t5.py:101).
# FIRST MISSING SYMBOL: `nn.Embedding(self.relative_attention_num_buckets,
# self.n_heads)` at t5.py:118, reached from `T5LayerSelfAttention` (:226) from
# `T5Block` (:234) from `T5Stack.__init__` (:249).
# THE GATE MOVED TO `gates/models-t5-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
