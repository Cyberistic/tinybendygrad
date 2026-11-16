# gates/models-bert-gate.bend -- the gate driver for `tinybendygrad/extra/models/bert.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/extra/models/bert.bend as P

import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/dtype.bend as DT
import ./../tinybendygrad/nn/__init__.bend as NN
import ./../tinybendygrad/nn/state.bend as ST
import ./../tinybendygrad/nn/layers.bend as LN
import ./../tinybendygrad/mixin/op.bend as MO
import ./../tinybendygrad/mixin/movement.bend as MX
import ./../tinybendygrad/mixin/reduce.bend as RC
import ./../tinybendygrad/mixin/elementwise.bend as EW
import ./../tinybendygrad/mixin/creation.bend as CR
import ./../tinybendygrad/mixin/rand.bend as RD
import ./../tinybendygrad/nn/optim.bend as OPT
import ./../tinybendygrad/extra/datasets/__init__.bend as D
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))

def br_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# :9-11 the three monkeypatch aliases. They are part of the file's contract even
# though upstream never rebinds them here, and each refusal names the port file
# that would have to own the layer.

def br_embedding_alias() -> D.Refused:
  D.refuse("extra/models/bert.py:9 Embedding = nn.Embedding -- MISSING; no `def Embedding`, no `def mo_i`, no `def mo_fx` under tinybendygrad/")

def br_linear_alias() -> D.Refused:
  D.refuse("extra/models/bert.py:10 Linear = nn.Linear -- EXISTS as nn/layers.bend:518 symbol=nn_linear; the ALIAS is what is absent")

def br_layernorm_alias() -> D.Refused:
  D.refuse("extra/models/bert.py:11 LayerNorm = nn.LayerNorm -- MISSING; `grep -rnwE \"def .*layernorm\" --include='*.bend' tinybendygrad/` = 0")

# :13-40 BertForQuestionAnswering.

# :14 def __init__(self, hidden_size=1024, ..., vocab_size=30522, ...)
def br_qa_init(hidden_size: U32, intermediate_size: U32, max_position_embeddings: U32,
  num_attention_heads: U32, num_hidden_layers: U32, type_vocab_size: U32, vocab_size: U32,
  attention_probs_dropout_prob: F32, hidden_dropout_prob: F32) -> D.Refused:
  D.refuse("extra/models/bert.py:14 BertForQuestionAnswering.__init__ -- FIRST MISSING SYMBOL Bert (:15) -> BertEmbeddings -> Embedding (:182)")

# :18 def load_from_pretrained(self)
def br_qa_load_from_pretrained() -> D.Refused:
  D.refuse("extra/models/bert.py:18 BertForQuestionAnswering.load_from_pretrained -- FIRST MISSING SYMBOL fetch (:20); THE PORT's `helpers.bend` `NOT PORTED` BLOCK records the HTTP seam as unported")

# :33 def __call__(self, input_ids, attention_mask, token_type_ids)
def br_qa_call(+input_ids: T.Tensor, +attention_mask: T.Tensor, +token_type_ids: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:33 BertForQuestionAnswering.__call__ -- FIRST MISSING SYMBOL Tensor.scaled_dot_product_attention via BertSelfAttention (:279)")

# :42-124 BertForPretraining. Its `loss` (:59) and `accuracy` (:64) are the only
# defs in this file that name an OPTIMIZER SLOT (`adam_v`, `adam_m`) and they do
# so by FILTERING it out, so they name Adam without calling it.

# :43 def __init__(self, hidden_size=1024, ...)
def br_pre_init(hidden_size: U32, intermediate_size: U32, max_position_embeddings: U32,
  num_attention_heads: U32, num_hidden_layers: U32, type_vocab_size: U32, vocab_size: U32,
  attention_probs_dropout_prob: F32, hidden_dropout_prob: F32) -> D.Refused:
  D.refuse("extra/models/bert.py:43 BertForPretraining.__init__ -- FIRST MISSING SYMBOL Bert (:45) -> BertEmbeddings -> Embedding (:182)")

# :53 def sparse_categorical_crossentropy(self, predictions, labels, ignore_index=-1)
def br_pre_sparse_ce(predictions: T.Tensor, labels: T.Tensor, ignore_index: H.I64) -> D.Refused:
  D.refuse("extra/models/bert.py:53 sparse_categorical_crossentropy -- reached :54 log_softmax (mixin/op.bend:1095 symbol=mo_logsumexp EXISTS); BLOCKED AT :56 by Tensor.flatten, which is MISSING")

# :59 def loss(self, prediction_logits, seq_relationship_logits, masked_lm_ids, masked_lm_weights, next_sentence_labels)
def br_pre_loss() -> D.Refused:
  D.refuse("extra/models/bert.py:59 BertForPretraining.loss -- FIRST MISSING SYMBOL Tensor.binary_crossentropy_logits (:61)")

# :64 def accuracy(self, prediction_logits, seq_relationship_logits, masked_lm_ids, masked_lm_weights, next_sentence_labels)
def br_pre_accuracy() -> D.Refused:
  D.refuse("extra/models/bert.py:64 BertForPretraining.accuracy -- FIRST MISSING SYMBOL Tensor.argmax (:66)")

# :78 def load_from_pretrained(self, tf_weight_path=...datasets/wiki)
def br_pre_load_from_pretrained() -> D.Refused:
  D.refuse("extra/models/bert.py:78 BertForPretraining.load_from_pretrained -- FIRST MISSING SYMBOL import tensorflow (:81); also `adam_v`/`adam_m`/`beta1_power`/`beta2_power` at :90 are the TF optimizer slots, NOT nn/optim.bend's adam")

# :126-159 the three heads. All three refuse on `Linear`, which EXISTS -- the
# point of naming it is that the FIRST missing symbol is one layer down.

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
  D.refuse("extra/models/bert.py:143 BertLMPredictionHead.__call__ -- FIRST MISSING SYMBOL nn_dot of `hidden @ embedding_weight.T` (:144); tinybendygrad/nn/layers.bend:476 symbol=nn_dot EXISTS but returns Maybe, not a Tensor")

# :147 def __init__(self, hidden_size)
def br_pred_transform_init(hidden_size: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:147 BertPredictionHeadTransform.__init__ -- FIRST MISSING SYMBOL LayerNorm (:149)")

# :151 def __call__(self, hidden_states)
def br_pred_transform_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:151 BertPredictionHeadTransform.__call__ -- FIRST MISSING SYMBOL gelu (:152); `.erf` (:236) is MISSING and `def ew_gelu` does not exist")

# :155 def __init__(self, hidden_size)
def br_pooler_init(hidden_size: U32) -> D.Refused:
  D.refuse("extra/models/bert.py:155 BertPooler.__init__ -- reached Linear (:156, nn/layers.bend:518 symbol=nn_linear EXISTS); BLOCKED by the missing class shell")

# :158 def __call__(self, hidden_states)
def br_pooler_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:158 BertPooler.__call__ -- FIRST MISSING SYMBOL Tensor.slice on hidden_states[:, 0] (:159)")

# :161-164 `gather`. NOT PORTED, and named here rather than in the header alone.

def br_gather(+prediction_logits: T.Tensor, +masked_lm_positions: T.Tensor) -> D.Refused:
  D.refuse("extra/models/bert.py:161 gather -- FIRST MISSING SYMBOL Tensor.one_hot, built here as arange (:162) == masked_lm_positions.unsqueeze(2) (:163)")

# :166-300 the six that carry the wall.

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
  D.refuse("extra/models/bert.py:225 BertOutput.__init__ -- reached Linear (:225, EXISTS at nn/layers.bend:518 symbol=nn_linear); BLOCKED AT LayerNorm (:226)")

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
  D.refuse("extra/models/bert.py:259 BertSelfAttention.__init__ -- q/k/v are Linear (:264-266) and EXIST at nn/layers.bend:518 symbol=nn_linear; the CLASS SHELL is what is missing")

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

# There is no `if __name__ == "__main__":` in bert.py. `main` prints TWO rows:
# the refusal address and the answer to the four-question census.

def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, br_embeddings_init(1024, 512, 2, 30522))
    srow("bert_refused_at", br_at(a))
    row("bert_attention_exists", False{})
    row("bert_embedding_exists", False{})
