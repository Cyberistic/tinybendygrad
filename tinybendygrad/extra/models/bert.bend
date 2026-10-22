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

# ===========================================================================
# STUB -- 1:1 PATH MIRROR of extra/models/bert.py (300 LOC). NOT YET PORTED.
#
# THE FIRST MISSING THING IS `nn.Embedding`, AND IT IS ONE OF THE FOUR THE
# VISION MODELS NEVER ASKED FOR. `grep -rnwE "def .*Embedding" --include='*.bend'
# tinybendygrad/` = 0, and so is `grep -rnwE "def .*mo_i\(|def .*mo_fx\("`. The
# resnet.bend census at :40-123 asks for conv2d, batchnorm, linear, sequential,
# argmax, item, torch_load, fetch, get_child, rand and TinyJit; `Embedding` is not
# among them because a convnet indexes a weight tensor by spatial offset, never by
# a token id. Three of the eight files in this directory cannot name one weight
# without it.
#
# WHAT BERT GETS FOR FREE FROM THE VISION WORK, and this is measured, not hoped:
#   `nn.Linear`             nn/layers.bend:427 `nn_linear`  (:16,:130,:225,:264,:265,:266,:292,:310,:239)
#   `Tensor.stack`          mixin/movement.bend:1269 `mxw_stk` (:40)
#   `reshape`               mixin/movement.bend:1431 `mxw_reshape` (:37,:38,:282,:287)
#   `transpose`             mixin/movement.bend:1449 `mxw_permute` (:281,:288)
#   `log_softmax`           mixin/op.bend:1109 `mo_log_softmax` (:54)
#   `Tensor.arange`         mixin/rand.bend:361 `op_arange`     (:55,:192)
#   `Tensor.zeros`          mixin/creation.bend:446 `cr_zeros`  (:141)
#   `Tensor.ones`           mixin/creation.bend:487 `cr_ones`   -- needed by T5, not here
#   `Tensor.cast`/`.float()`mixin/op.bend:370 `mo_cast_t`     (:54,:70)
#   `x.relu`                nn/layers.bend:262 `nn_relu` -- BERT has none; recorded so the
#                           census is a census and not a list of what is convenient
#   `x +` / `x *`           mixin/elementwise.bend:509/510 `ew_add`/`ew_mul` (:56,:67,:197,:232)
#   `Adam`                   nn/optim.bend -- `op_mstep` :898 `op_vstep` :903 `op_mhat` `op_vhat`.
#                           BERT DOES NOT CONSTRUCT ONE, but its TF loader at :90 FILTERS ON
#                           `["adam_v", "adam_m", "beta1_power", "beta2_power"]`, so the names
#                           are load-bearing here even though the optimizer is not called.
#
# WHAT BERT ASKS FOR THAT NO VISION MODEL ASKED FOR -- THE NAMED FOUR:
#   (1) `nn.Embedding`      MISSING. (:182,:183,:184,:46) THE FIRST MISSING SYMBOL.
#   (2) `nn.LayerNorm`      MISSING. (:149,:185,:226,:293) `grep -rnwE "def .*layernorm" = 0`.
#   (3) `Tensor.scaled_dot_product_attention` MISSING. (:279) THE WALL for :270.
#   (4) `Tensor.dropout`    MISSING. (:199,:231,:298) and `:29` skips dropout keys, so the
#                           NAME is in the loader even where the op is not.
# AND TWO MORE, BOTH BERT-ONLY:
#   (5) `gelu` as BERT DEFINES IT, at :236 -- `x * 0.5 * (1.0 + (x / 1.41421).erf())`.
#       `ew_gelu` is MISSING (mixin/elementwise.bend:772 has only the CONSTANT `ew_k.gelu`)
#       and `.erf` is MISSING entirely. clip.py:11 `gelu = Tensor.gelu` is the OTHER
#       gelu, the openai one, so the two files disagree about what the word means.
#   (6) `Tensor.binary_crossentropy_logits` MISSING (:61,:72).
#   (7) `Tensor.argmax` MISSING (:66,:70) -- resnet.bend's census names it MISSING too, so
#       this is NOT a new ask; it is the FIRST one that BERT hits and resnet only reaches
#       it in `postprocess`.
#   (8) `Tensor.chunk` MISSING (:36).
#
# TODO(port): STOPPED AT `BertEmbeddings.__init__` (extra/models/bert.py:180).
# FIRST MISSING SYMBOL: `Embedding(vocab_size, hidden_size)` at bert.py:182, where
# `Embedding = nn.Embedding` is the module-level alias at bert.py:9 and there is no `def Embedding`
# anywhere under `tinybendygrad/`, and no `def mo_i` either.
# **THE `mo_fx` HALF OF THIS EVIDENCE WAS FALSE. CORRECTED 2026-10-20:** `def mo_fx1d` is at
# `mixin/op.bend:1181` and `def mo_fx2d` at `:1189`, so "no `def mo_fx` anywhere" was falsifiable
# and falsified -- the audit's grep demanded a literal `(` after the name and matched neither.
# **THE CONCLUSION IS UNCHANGED AND WAS NEVER IN DOUBT:** `op.bend:1193` shows both are FIXTURES
# returning `r` unchanged, not a gather, and `def mo_i` is still absent. **A CITATION WRONG ON ITS
# EVIDENCE AND RIGHT ON ITS CONCLUSION STILL MISLEADS THE NEXT READER, WHO CHECKS THE EVIDENCE.**
#
# THE TWO `load_from_pretrained` ARE NOT A PORTING PROBLEM AND SHOULD NOT BE
# TREATED AS ONE. bert.py:78-124 reads a TENSORFLOW checkpoint through
# `tf.train.list_variables`, and bert.py:24-31 reads a TORCH checkpoint through
# `torch.load`. `helpers.bend:3191` already records the whole weight-download
# seam as unported I/O, and neither framework has a counterpart. Named here so no
# reader counts them as arithmetic left undone.
#
# `gelu` (:235-236) and `gather` (:161-164) are module-level functions and both are
# NOT PORTED: `gather` (:164) is `onehot @ prediction_logits` and `one_hot` is MISSING,
# and the one-hot itself is built from `Tensor.arange` + `expand` + `==`.
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))

def br_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :9-11 the three monkeypatch aliases. They are part of the file's contract even
# though upstream never rebinds them here, and each refusal names the port file
# that would have to own the layer.
# ---------------------------------------------------------------------------
def br_embedding_alias() -> D.Refused:
  D.refuse("extra/models/bert.py:9 Embedding = nn.Embedding -- MISSING; no `def Embedding`, no `def mo_i`, no `def mo_fx` under tinybendygrad/")

def br_linear_alias() -> D.Refused:
  D.refuse("extra/models/bert.py:10 Linear = nn.Linear -- EXISTS as nn/layers.bend:427 nn_linear; the ALIAS is what is absent")

def br_layernorm_alias() -> D.Refused:
  D.refuse("extra/models/bert.py:11 LayerNorm = nn.LayerNorm -- MISSING; `grep -rnwE \"def .*layernorm\" --include='*.bend' tinybendygrad/` = 0")

# ---------------------------------------------------------------------------
# :13-40 BertForQuestionAnswering.
# ---------------------------------------------------------------------------

# :14 def __init__(self, hidden_size=1024, ..., vocab_size=30522, ...)
def br_qa_init(hidden_size: U32, intermediate_size: U32, max_position_embeddings: U32,
  num_attention_heads: U32, num_hidden_layers: U32, type_vocab_size: U32, vocab_size: U32,
  attention_probs_dropout_prob: F32, hidden_dropout_prob: F32) -> D.Refused:
  D.refuse("extra/models/bert.py:14 BertForQuestionAnswering.__init__ -- FIRST MISSING SYMBOL Bert (:15) -> BertEmbeddings -> Embedding (:182)")

# :18 def load_from_pretrained(self)
def br_qa_load_from_pretrained() -> D.Refused:
  D.refuse("extra/models/bert.py:18 BertForQuestionAnswering.load_from_pretrained -- FIRST MISSING SYMBOL fetch (:20); helpers.bend:3191 records the HTTP seam as unported")

# :33 def __call__(self, input_ids, attention_mask, token_type_ids)
def br_qa_call(+input_ids: T.Tensor, +attention_mask: T.Tensor, +token_type_ids: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:33 BertForQuestionAnswering.__call__ -- FIRST MISSING SYMBOL Tensor.scaled_dot_product_attention via BertSelfAttention (:279)")

# ---------------------------------------------------------------------------
# :42-124 BertForPretraining. Its `loss` (:59) and `accuracy` (:64) are the only
# defs in this file that name an OPTIMIZER SLOT (`adam_v`, `adam_m`) and they do
# so by FILTERING it out, so they name Adam without calling it.
# ---------------------------------------------------------------------------

# :43 def __init__(self, hidden_size=1024, ...)
def br_pre_init(hidden_size: U32, intermediate_size: U32, max_position_embeddings: U32,
  num_attention_heads: U32, num_hidden_layers: U32, type_vocab_size: U32, vocab_size: U32,
  attention_probs_dropout_prob: F32, hidden_dropout_prob: F32) -> D.Refused:
  D.refuse("extra/models/bert.py:43 BertForPretraining.__init__ -- FIRST MISSING SYMBOL Bert (:45) -> BertEmbeddings -> Embedding (:182)")

# :53 def sparse_categorical_crossentropy(self, predictions, labels, ignore_index=-1)
def br_pre_sparse_ce(predictions: T.Tensor, labels: T.Tensor, ignore_index: H.I64) -> D.Refused:
  D.refuse("extra/models/bert.py:53 sparse_categorical_crossentropy -- reached :54 log_softmax (mixin/op.bend:1109 EXISTS); BLOCKED AT :56 by Tensor.flatten, which is MISSING")

# :59 def loss(self, prediction_logits, seq_relationship_logits, masked_lm_ids, masked_lm_weights, next_sentence_labels)
def br_pre_loss() -> D.Refused:
  D.refuse("extra/models/bert.py:59 BertForPretraining.loss -- FIRST MISSING SYMBOL Tensor.binary_crossentropy_logits (:61)")

# :64 def accuracy(self, prediction_logits, seq_relationship_logits, masked_lm_ids, masked_lm_weights, next_sentence_labels)
def br_pre_accuracy() -> D.Refused:
  D.refuse("extra/models/bert.py:64 BertForPretraining.accuracy -- FIRST MISSING SYMBOL Tensor.argmax (:66)")

# :78 def load_from_pretrained(self, tf_weight_path=...datasets/wiki)
def br_pre_load_from_pretrained() -> D.Refused:
  D.refuse("extra/models/bert.py:78 BertForPretraining.load_from_pretrained -- FIRST MISSING SYMBOL import tensorflow (:81); also `adam_v`/`adam_m`/`beta1_power`/`beta2_power` at :90 are the TF optimizer slots, NOT nn/optim.bend's adam")

# ---------------------------------------------------------------------------
# :126-159 the three heads. All three refuse on `Linear`, which EXISTS -- the
# point of naming it is that the FIRST missing symbol is one layer down.
# ---------------------------------------------------------------------------

# :127 def __init__(self, hidden_size, vocab_size, embeddings_weight)
def br_pre_heads_init(hidden_size: U32, vocab_size: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:127 BertPreTrainingHeads.__init__ -- FIRST MISSING SYMBOL BertLMPredictionHead -> BertPredictionHeadTransform.LayerNorm (:149)")

# :132 def __call__(self, sequence_output, masked_lm_positions)
def br_pre_heads_call(+sequence_output: T.Tensor, +masked_lm_positions: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:132 BertPreTrainingHeads.__call__ -- FIRST MISSING SYMBOL gather (:133), whose one_hot at :164 is MISSING")

# :138 def __init__(self, hidden_size, vocab_size, embeddings_weight)
def br_lm_head_init(hidden_size: U32, vocab_size: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:138 BertLMPredictionHead.__init__ -- FIRST MISSING SYMBOL BertPredictionHeadTransform.LayerNorm (:149)")

# :143 def __call__(self, hidden_states)
def br_lm_head_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:143 BertLMPredictionHead.__call__ -- FIRST MISSING SYMBOL nn_dot of `hidden @ embedding_weight.T` (:144); nn/layers.bend:383 nn_dot EXISTS but returns Maybe, not a Tensor")

# :147 def __init__(self, hidden_size)
def br_pred_transform_init(hidden_size: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:147 BertPredictionHeadTransform.__init__ -- FIRST MISSING SYMBOL LayerNorm (:149)")

# :151 def __call__(self, hidden_states)
def br_pred_transform_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:151 BertPredictionHeadTransform.__call__ -- FIRST MISSING SYMBOL gelu (:152); `.erf` (:236) is MISSING and `def ew_gelu` does not exist")

# :155 def __init__(self, hidden_size)
def br_pooler_init(hidden_size: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:155 BertPooler.__init__ -- reached Linear (:156, nn/layers.bend:427 EXISTS); BLOCKED by the missing class shell")

# :158 def __call__(self, hidden_states)
def br_pooler_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:158 BertPooler.__call__ -- FIRST MISSING SYMBOL Tensor.slice on hidden_states[:, 0] (:159)")

# ---------------------------------------------------------------------------
# :161-164 `gather`. NOT PORTED, and named here rather than in the header alone.
# ---------------------------------------------------------------------------
def br_gather(+prediction_logits: T.Tensor, +masked_lm_positions: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:161 gather -- FIRST MISSING SYMBOL Tensor.one_hot, built here as arange (:162) == masked_lm_positions.unsqueeze(2) (:163)")

# ---------------------------------------------------------------------------
# :166-300 the six that carry the wall.
# ---------------------------------------------------------------------------

# :167 def __init__(self, hidden_size, ..., hidden_dropout_prob)
def br_bert_init(hidden_size: U32, intermediate_size: U32, max_position_embeddings: U32,
  num_attention_heads: U32, num_hidden_layers: U32, type_vocab_size: U32, vocab_size: U32,
  attention_probs_dropout_prob: F32, hidden_dropout_prob: F32) -> D.Refused:
  D.refuse("extra/models/bert.py:167 Bert.__init__ -- FIRST MISSING SYMBOL Embedding via BertEmbeddings (:182)")

# :171 def __call__(self, input_ids, attention_mask, token_type_ids)
def br_bert_call(+input_ids: T.Tensor, +attention_mask: T.Tensor, +token_type_ids: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:171 Bert.__call__ -- FIRST MISSING SYMBOL Tensor.scaled_dot_product_attention via BertSelfAttention (:279)")

# :181 def __init__(self, hidden_size, max_position_embeddings, type_vocab_size, vocab_size, hidden_dropout_prob)
def br_embeddings_init(hidden_size: U32, max_position_embeddings: U32, type_vocab_size: U32, vocab_size: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:181 BertEmbeddings.__init__ -- FIRST MISSING SYMBOL Embedding (:182) -- THE FIRST MISSING SYMBOL OF THE WHOLE FILE")

# :188 def __call__(self, input_ids, token_type_ids)
def br_embeddings_call(+input_ids: T.Tensor, +token_type_ids: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:188 BertEmbeddings.__call__ -- FIRST MISSING SYMBOL self.word_embeddings (:193), the same missing Embedding")

# :203 def __init__(self, hidden_size, intermediate_size, num_attention_heads, num_hidden_layers, ...)
def br_encoder_init(hidden_size: U32, intermediate_size: U32, num_attention_heads: U32, num_hidden_layers: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:203 BertEncoder.__init__ -- FIRST MISSING SYMBOL BertLayer -> BertAttention -> scaled_dot_product_attention (:279)")

# :206 def __call__(self, hidden_states, attention_mask)
def br_encoder_call(+hidden_states: T.Tensor, +attention_mask: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:206 BertEncoder.__call__ -- FIRST MISSING SYMBOL BertLayer.__call__ (:208) -> Tensor.scaled_dot_product_attention")

# :212 def __init__(self, hidden_size, intermediate_size, num_attention_heads, ...)
def br_layer_init(hidden_size: U32, intermediate_size: U32, num_attention_heads: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:212 BertLayer.__init__ -- FIRST MISSING SYMBOL BertAttention (:213) -> Tensor.scaled_dot_product_attention (:279)")

# :217 def __call__(self, hidden_states, attention_mask)
def br_layer_call(+hidden_states: T.Tensor, +attention_mask: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:217 BertLayer.__call__ -- FIRST MISSING SYMBOL Tensor.scaled_dot_product_attention (:279)")

# :225 def __init__(self, hidden_size, intermediate_size, hidden_dropout_prob)
def br_output_init(hidden_size: U32, intermediate_size: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:225 BertOutput.__init__ -- reached Linear (:225, EXISTS at nn/layers.bend:427); BLOCKED AT LayerNorm (:226)")

# :229 def __call__(self, hidden_states, input_tensor)
def br_output_call(+hidden_states: T.Tensor, +input_tensor: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:229 BertOutput.__call__ -- FIRST MISSING SYMBOL Tensor.dropout (:231)")

# :235 def gelu(x)  -- NOT BERT'S ONLY GELU. clip.py:11 binds the OTHER one.
def br_gelu(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:235 gelu -- FIRST MISSING SYMBOL Tensor.erf at :236; `def ew_gelu` does not exist in mixin/elementwise.bend")

# :239 def __init__(self, hidden_size, intermediate_size)
def br_intermediate_init(hidden_size: U32, intermediate_size: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:239 BertIntermediate.__init__ -- reached Linear (:240, EXISTS); BLOCKED BY the missing class shell")

# :242 def __call__(self, hidden_states)
def br_intermediate_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:242 BertIntermediate.__call__ -- FIRST MISSING SYMBOL gelu (:246) -> Tensor.erf")

# :249 def __init__(self, hidden_size, num_attention_heads, attention_probs_dropout_prob, hidden_dropout_prob)
def br_attention_init(hidden_size: U32, num_attention_heads: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:249 BertAttention.__init__ -- reached Linear x3 (:264,:265,:266, EXISTS); BLOCKED at BertSelfOutput.LayerNorm via :251")

# :253 def __call__(self, hidden_states, attention_mask)
def br_attention_call(+hidden_states: T.Tensor, +attention_mask: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:253 BertAttention.__call__ -- FIRST MISSING SYMBOL Tensor.scaled_dot_product_attention via BertSelfAttention (:279)")

# :259 def __init__(self, hidden_size, num_attention_heads, attention_probs_dropout_prob)
def br_self_attn_init(hidden_size: U32, num_attention_heads: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:259 BertSelfAttention.__init__ -- q/k/v are Linear (:264-266) and EXIST at nn/layers.bend:427; the CLASS SHELL is what is missing")

# :270 def __call__(self, hidden_states, attention_mask)
def br_self_attn_call(+hidden_states: T.Tensor, +attention_mask: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:270 BertSelfAttention.__call__ -- FIRST MISSING SYMBOL Tensor.scaled_dot_product_attention (:279); q/k/v Linear (:271-273) and transpose_for_scores (:275-277) are PORTED")

# :286 def transpose_for_scores(self, x)
def br_transpose_for_scores(+x: T.Tensor, num_attention_heads: U32, attention_head_size: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:286 transpose_for_scores -- reshape (:287) and transpose (:288) BOTH EXIST (mxw_reshape, mxw_permute); only the method shell is absent")

# :291 def __init__(self, hidden_size, hidden_dropout_prob)
def br_self_out_init(hidden_size: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:291 BertSelfOutput.__init__ -- FIRST MISSING SYMBOL LayerNorm (:293)")

# :296 def __call__(self, hidden_states, input_tensor)
def br_self_out_call(+hidden_states: T.Tensor, +input_tensor: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:296 BertSelfOutput.__call__ -- FIRST MISSING SYMBOL Tensor.dropout (:298)")

# ---------------------------------------------------------------------------
# There is no `if __name__ == "__main__":` in bert.py. `main` prints TWO rows:
# the refusal address and the answer to the four-question census.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, br_embeddings_init(1024, 512, 2, 30522))
    srow("bert_refused_at", br_at(a))
    row("bert_attention_exists", False{})
    row("bert_embedding_exists", False{})