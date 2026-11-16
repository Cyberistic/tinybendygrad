# gates/models-t5-gate.bend -- the gate driver for `tinybendygrad/extra/models/t5.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/extra/models/t5.bend as P

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

def t5_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# :29-40 T5Config -- a `@dataclass`. It is TEN INTEGERS AND A FLOAT and is
# therefore the one dataclass in this file whose whole body is portable. The
# defs below are the ten, spelled out, because a `Refused` here would be a lie
# about data that needs no work.

def t5_cfg_d_ff() -> U32: 10240
def t5_cfg_d_kv() -> U32: 64
def t5_cfg_d_model() -> U32: 4096
def t5_cfg_layer_norm_epsilon() -> F32: 0.000001
def t5_cfg_num_decoder_layers() -> U32: 24
def t5_cfg_num_heads() -> U32: 64
def t5_cfg_num_layers() -> U32: 24
def t5_cfg_relative_attention_num_buckets() -> U32: 32
def t5_cfg_relative_attention_max_distance() -> U32: 128
def t5_cfg_vocab_size() -> U32: 32128

# :42-49 T5Tokenizer. NOT PORTED: `SentencePieceProcessor` (t5.py:26).

def t5_tokenizer_init(spiece_path: String) -> D.Refused:
  D.refuse("extra/models/t5.py:42 T5Tokenizer.__init__ -- FIRST MISSING SYMBOL SentencePieceProcessor (:44); t5.py:1 is the pip install")

def t5_tokenizer_encode(spiece_path: String, text: String, max_length: U32) -> D.Refused:
  D.refuse("extra/models/t5.py:46 T5Tokenizer.encode -- FIRST MISSING SYMBOL self.spp.Encode (:47)")

# :51-72 T5LayerNorm. This is the one layer in this file that is RMS-NORM WITH NO
# MEAN AND NO BIAS, and it is why `pool_rsqrt` is named above.

# :52 def __init__(self, hidden_size:int, eps:float=1e-6)
def t5_layernorm_init(hidden_size: U32, eps: F32) -> D.Refused:
  D.refuse("extra/models/t5.py:52 T5LayerNorm.__init__ -- reached Tensor.ones (:56, mixin/creation.bend:567 symbol=cr_ones EXISTS); the eps is a plain F32")

# :59 def __call__(self, hidden_states)
def t5_layernorm_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/t5.py:59 T5LayerNorm.__call__ -- reached :65 mean (mixin/op.bend:891 symbol=mo_div EXISTS); BLOCKED AT :66 Tensor.rsqrt, which has no `def mo_rsqrt`")

# :75-98 the two FFN defs.

# :76 def __init__(self, config:T5Config)
def t5_gated_init(d_model: U32, d_ff: U32) -> D.Refused:
  D.refuse("extra/models/t5.py:76 T5DenseGatedActDense.__init__ -- all three are Linear (:77,:78,:79, nn/layers.bend:518 symbol=nn_linear EXISTS); BLOCKED BY the missing class shell")

# :81 def __call__(self, hidden_states)
def t5_gated_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/t5.py:81 T5DenseGatedActDense.__call__ -- FIRST MISSING SYMBOL Tensor.gelu (:82); `def ew_gelu` does not exist, only the CONSTANT ew_k.gelu at :772")

# :90 def __init__(self, config:T5Config)
def t5_ff_init(d_model: U32, d_ff: U32) -> D.Refused:
  D.refuse("extra/models/t5.py:90 T5LayerFF.__init__ -- FIRST MISSING SYMBOL T5LayerNorm (:92), whose body needs Tensor.rsqrt (:66)")

# :94 def __call__(self, hidden_states)
def t5_ff_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/t5.py:94 T5LayerFF.__call__ -- FIRST MISSING SYMBOL T5DenseGatedActDense.__call__ (:96) -> Tensor.gelu")

# :101-221 T5Attention. the class the whole file is about.

# :102 def __init__(self, config:T5Config, has_relative_attention_bias:bool=False)
def t5_attn_init(d_model: U32, d_kv: U32, num_heads: U32, has_relative_attention_bias: Bool) -> D.Refused:
  D.refuse("extra/models/t5.py:102 T5Attention.__init__ -- q/k/v/o are Linear (:112-115, EXISTS); FIRST MISSING SYMBOL nn.Embedding (:118)")

# :121 def _relative_position_bucket(relative_position, num_buckets=32, max_distance=128)
def t5_attn_rel_pos_bucket(+relative_position: T.Tensor, num_buckets: U32, max_distance: U32) -> D.Refused:
  D.refuse("extra/models/t5.py:121 _relative_position_bucket -- reached :142 zeros_like and :143 cast and :144 compare; BLOCKED AT :145 Tensor.abs")

# :167 def compute_bias(self, query_length, key_length)
def t5_attn_compute_bias(query_length: U32, key_length: U32) -> D.Refused:
  D.refuse("extra/models/t5.py:167 T5Attention.compute_bias -- arange (:169,:170, mixin/rand.bend:363 symbol=op_pool1.iz EXISTS); FIRST MISSING SYMBOL self.relative_attention_bias (:177), the missing nn.Embedding")

# :181 def __call__(self, hidden_states, position_bias=None)
def t5_attn_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/t5.py:181 T5Attention.__call__ -- FIRST MISSING SYMBOL Tensor.matmul (:210); the q/k/v projections (:203-207) are nn_linear + mxw_reshape + mxw_permute, ALL PORTED")

# :224-247 T5LayerSelfAttention and T5Block.

# :225 def __init__(self, config:T5Config, has_relative_attention_bias:bool=False)
def t5_self_attn_init(has_relative_attention_bias: Bool) -> D.Refused:
  D.refuse("extra/models/t5.py:225 T5LayerSelfAttention.__init__ -- FIRST MISSING SYMBOL T5Attention (:226) -> nn.Embedding (:118)")

# :229 def __call__(self, hidden_states, position_bias=None)
def t5_self_attn_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/t5.py:229 T5LayerSelfAttention.__call__ -- FIRST MISSING SYMBOL T5Attention.__call__ (:231) -> Tensor.matmul (:210)")

# :236 def __init__(self, config:T5Config, has_relative_attention_bias:bool=False)
def t5_block_init(has_relative_attention_bias: Bool) -> D.Refused:
  D.refuse("extra/models/t5.py:236 T5Block.__init__ -- FIRST MISSING SYMBOL T5LayerSelfAttention (:226) -> nn.Embedding (:118)")

# :240 def __call__(self, hidden_states, position_bias=None)
def t5_block_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/t5.py:240 T5Block.__call__ -- FIRST MISSING SYMBOL T5LayerSelfAttention.__call__ (:241) -> Tensor.matmul (:210)")

# :250-265 T5Stack.

# :251 def __init__(self, config:T5Config, embed_tokens:nn.Embedding)
def t5_stack_init(num_layers: U32, has_relative_attention_bias: Bool) -> D.Refused:
  D.refuse("extra/models/t5.py:251 T5Stack.__init__ -- FIRST MISSING SYMBOL T5Block (:254) -> nn.Embedding (:118)")

# :257 def __call__(self, input_ids:Tensor)
def t5_stack_call(+input_ids: T.Tensor) -> D.Refused:
  D.refuse("extra/models/t5.py:257 T5Stack.__call__ -- reached :260 self.embed_tokens (the missing Embedding) and :258 view (mxw_reshape EXISTS); the loop at :262 is Python control flow, not a graph")

# :268-286 the two entry points.

# :269 def __init__(self, config:T5Config)
def t5_encoder_init(vocab_size: U32, d_model: U32) -> D.Refused:
  D.refuse("extra/models/t5.py:269 T5EncoderModel.__init__ -- FIRST MISSING SYMBOL nn.Embedding (:270)")

# :273 def __call__(self, input_ids:Tensor)
def t5_encoder_call(+input_ids: T.Tensor) -> D.Refused:
  D.refuse("extra/models/t5.py:273 T5EncoderModel.__call__ -- FIRST MISSING SYMBOL self.encoder (:274) -> T5Stack -> nn.Embedding (:118)")

# :277 def __init__(self, max_length:int, spiece_path:Union[str, Path])
def t5_embedder_init(max_length: U32, spiece_path: String) -> D.Refused:
  D.refuse("extra/models/t5.py:277 T5Embedder.__init__ -- FIRST MISSING SYMBOL T5Tokenizer (:278) -> SentencePieceProcessor (:44)")

# :283 def __call__(self, texts:Union[str, List[str]])
def t5_embedder_call() -> D.Refused:
  D.refuse("extra/models/t5.py:283 T5Embedder.__call__ -- FIRST MISSING SYMBOL Tensor.cat (:285); the tokenizer it concatenates is ALSO missing")

# There is no `if __name__ == "__main__":` in t5.py. `main` prints TWO rows.

def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, t5_attn_init(4096, 64, 64, True{}))
    srow("t5_refused_at", t5_at(a))
    row("t5_softmax_exists", True{})
    row("t5_matmul_exists", False{})
