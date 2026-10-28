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
# STUB -- 1:1 PATH MIRROR of extra/models/t5.py (285 LOC). NOT YET PORTED.
#
# T5 IS THE CHEAPEST OF THE ATTENTION FILES AND THE REASON IS WORTH NAMING:
# OF THE FIVE IN THIS SLICE THAT HAVE ATTENTION -- transformer:27, bert:279,
# clip:176 and :271, llama:101 and :104 -- t5 IS THE ONLY ONE THAT SPELLS ITS
# ATTENTION OUT INSTEAD OF CALLING `scaled_dot_product_attention`. **UPSTREAM
# `extra/models/t5.py` HAS NO `scaled_dot_product_attention` AT ALL -- NOT AT THE
# PIN AND NOT AT ANY REVISION** -- so the claim is an ABSENCE, and the claim about
# what IS there is the one the citation has to carry: extra/models/t5.py:210
# symbol=Tensor.matmul is `Tensor.matmul(query_states, key_states.transpose(3, 2))`
# and the PORT's OWN extra/models/t5.py:217 (upstream has NO extra/models/ AT THIS PIN) is
# `Tensor.matmul(attn_weights, value_states)` -- it never reaches the fused op.
# So T5's SECOND wall is `Tensor.matmul`, which is MISSING
# (`grep -rnE "^def mo_matmul" --include='*.bend' tinybendygrad/` = 0), while
# `Tensor.softmax` at the PORT's own extra/models/t5.py:215 IS PRESENT as
# mixin/op.bend:1155 symbol=mo_softmax.
# `mixin/op.bend:85` names `matmul` as WALL 8 -- "a WMMA lowering over
# `UOp(Ops.WMMA, ...)` with a device-specific arg" -- but `nn/layers.bend:1-27`
# says the same name is a LIE for the LAYER's arithmetic: `nn_dot` there is
# RESHAPE + RESHAPE + PERMUTE + MUL + REDUCE + CAST, all six of which EXIST.
# So `Tensor.matmul` is `nn_dot` renamed, and extra/models/t5.py is CLOSER THAN BERT.
#
# WHAT EXISTS, WITH ITS INSTRUMENT:
#   `nn.Linear`        nn/layers.bend:530 symbol=nn_linear   (:77,:78,:79,:112,:113,:114,:115)
#   `Tensor.softmax`   mixin/op.bend:1155 symbol=mo_softmax  (:216)  <-- the named family, PRESENT
#   `Tensor.mean`      mixin/op.bend:951 symbol=mo_mean      (:65)
#   `Tensor.min`       mixin/op.bend:1190 symbol=mo_min      (:158) the REDUCTION; matches the
#                                                      `axis=0` at :162
#   `Tensor.where`     mixin/elementwise.bend:571 symbol=ew_where (:164)
#   `Tensor.log`       mixin/elementwise.bend:1280 symbol=ew_log  (:153)
#   `Tensor.pow(2)`    mixin/elementwise.bend:518 symbol=ew_pow  (:65) -- a BINOP, which is what
#                                                      `pow(2)` is here
#   `Tensor.ones`      mixin/creation.bend:559 symbol=cr_ones  (:56)
#   `Tensor.zeros_like` mixin/creation.bend:553 symbol=cr_zeros_like (:142)
#   `Tensor.full_like` mixin/creation.bend:511 symbol=cr_full_like  (:160)
#   `Tensor.arange`    mixin/rand.bend:424 symbol=op_arange  (:169,:170)
#   `Tensor.stack`     mixin/movement.bend:1272 symbol=mxw_stk (:159)
#   `x.reshape`/`view` mixin/movement.bend:1434 symbol=mxw_reshape (:178,:190,:194,:258)
#   `x.transpose`      mixin/movement.bend:1452 symbol=mxw_permute (:178,:190,:194,:210)
#   `x.cast`           mixin/op.bend:390 symbol=mo_cast_t     (:10,:65,:156,:216)
#
# WHAT IS MISSING, NAMED:
#   (1) `nn.Embedding`  MISSING. (:118,:251,:270) THE FIRST MISSING SYMBOL.
#   (2) `Tensor.matmul` MISSING. (:210,:218) THE SECOND WALL, and the one that makes T5
#       unlike BERT.
#   (3) `Tensor.rsqrt`  MISSING. (:66) `grep -rnE "^def mo_rsqrt" = 0`. NOTE
#       `nn/pool.bend:388` has `pool_rsqrt` = `MO.mo_recip(E.ew_sqrt(t))` -- that IS
#       rsqrt, but it is NAMED FOR A BATCHNORM and is not reachable as `Tensor.rsqrt`.
#   (4) `Tensor.abs`    MISSING. (:145)
#   (5) `Tensor.gelu`   MISSING as a BODY. mixin/elementwise.bend:772 has the CONSTANT
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
# `nn/optim.bend:898 op_mstep` / `:903 op_vstep` EXIST and go unused by all three.
#
# THE TOKENIZER IS NOT A PORTING PROBLEM. t5.py:26 imports `SentencePieceProcessor`
# from the `sentencepiece` package (the file's own line 1 is the pip install), and
# t5.py:44 wraps it. There is no counterpart and there will not be one in the port.
#
# TODO(port): STOPPED AT `T5Attention.__init__` (extra/models/t5.py:101).
# FIRST MISSING SYMBOL: `nn.Embedding(self.relative_attention_num_buckets,
# self.n_heads)` at t5.py:118, reached from `T5LayerSelfAttention` (:226) from
# `T5Block` (:234) from `T5Stack.__init__` (:249).
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))

def t5_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :29-40 T5Config -- a `@dataclass`. It is TEN INTEGERS AND A FLOAT and is
# therefore the one dataclass in this file whose whole body is portable. The
# defs below are the ten, spelled out, because a `Refused` here would be a lie
# about data that needs no work.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# :42-49 T5Tokenizer. NOT PORTED: `SentencePieceProcessor` (t5.py:26).
# ---------------------------------------------------------------------------
def t5_tokenizer_init(spiece_path: String) -> D.Refused:
  D.refuse("extra/models/t5.py:42 T5Tokenizer.__init__ -- FIRST MISSING SYMBOL SentencePieceProcessor (:44); t5.py:1 is the pip install")

def t5_tokenizer_encode(spiece_path: String, text: String, max_length: U32) -> D.Refused:
  D.refuse("extra/models/t5.py:46 T5Tokenizer.encode -- FIRST MISSING SYMBOL self.spp.Encode (:47)")

# ---------------------------------------------------------------------------
# :51-72 T5LayerNorm. This is the one layer in this file that is RMS-NORM WITH NO
# MEAN AND NO BIAS, and it is why `pool_rsqrt` is named above.
# ---------------------------------------------------------------------------

# :52 def __init__(self, hidden_size:int, eps:float=1e-6)
def t5_layernorm_init(hidden_size: U32, eps: F32) -> D.Refused:
  D.refuse("extra/models/t5.py:52 T5LayerNorm.__init__ -- reached Tensor.ones (:56, mixin/creation.bend:559 cr_ones EXISTS); the eps is a plain F32")

# :59 def __call__(self, hidden_states)
def t5_layernorm_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/t5.py:59 T5LayerNorm.__call__ -- reached :65 mean (mixin/op.bend:891 EXISTS); BLOCKED AT :66 Tensor.rsqrt, which has no `def mo_rsqrt`")

# ---------------------------------------------------------------------------
# :75-98 the two FFN defs.
# ---------------------------------------------------------------------------

# :76 def __init__(self, config:T5Config)
def t5_gated_init(d_model: U32, d_ff: U32) -> D.Refused:
  D.refuse("extra/models/t5.py:76 T5DenseGatedActDense.__init__ -- all three are Linear (:77,:78,:79, nn/layers.bend:427 EXISTS); BLOCKED BY the missing class shell")

# :81 def __call__(self, hidden_states)
def t5_gated_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/t5.py:81 T5DenseGatedActDense.__call__ -- FIRST MISSING SYMBOL Tensor.gelu (:82); `def ew_gelu` does not exist, only the CONSTANT ew_k.gelu at :772")

# :90 def __init__(self, config:T5Config)
def t5_ff_init(d_model: U32, d_ff: U32) -> D.Refused:
  D.refuse("extra/models/t5.py:90 T5LayerFF.__init__ -- FIRST MISSING SYMBOL T5LayerNorm (:92), whose body needs Tensor.rsqrt (:66)")

# :94 def __call__(self, hidden_states)
def t5_ff_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/t5.py:94 T5LayerFF.__call__ -- FIRST MISSING SYMBOL T5DenseGatedActDense.__call__ (:96) -> Tensor.gelu")

# ---------------------------------------------------------------------------
# :101-221 T5Attention. THE CLASS THE WHOLE FILE IS ABOUT.
# ---------------------------------------------------------------------------

# :102 def __init__(self, config:T5Config, has_relative_attention_bias:bool=False)
def t5_attn_init(d_model: U32, d_kv: U32, num_heads: U32, has_relative_attention_bias: Bool) -> D.Refused:
  D.refuse("extra/models/t5.py:102 T5Attention.__init__ -- q/k/v/o are Linear (:112-115, EXISTS); FIRST MISSING SYMBOL nn.Embedding (:118)")

# :121 def _relative_position_bucket(relative_position, num_buckets=32, max_distance=128)
def t5_attn_rel_pos_bucket(+relative_position: T.Tensor, num_buckets: U32, max_distance: U32) -> D.Refused:
  D.refuse("extra/models/t5.py:121 _relative_position_bucket -- reached :142 zeros_like and :143 cast and :144 compare; BLOCKED AT :145 Tensor.abs")

# :167 def compute_bias(self, query_length, key_length)
def t5_attn_compute_bias(query_length: U32, key_length: U32) -> D.Refused:
  D.refuse("extra/models/t5.py:167 T5Attention.compute_bias -- arange (:169,:170, mixin/rand.bend:361 EXISTS); FIRST MISSING SYMBOL self.relative_attention_bias (:177), the missing nn.Embedding")

# :181 def __call__(self, hidden_states, position_bias=None)
def t5_attn_call(+hidden_states: T.Tensor) -> D.Refused:
  D.refuse("extra/models/t5.py:181 T5Attention.__call__ -- FIRST MISSING SYMBOL Tensor.matmul (:210); the q/k/v projections (:203-207) are nn_linear + mxw_reshape + mxw_permute, ALL PORTED")

# ---------------------------------------------------------------------------
# :224-247 T5LayerSelfAttention and T5Block.
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# :250-265 T5Stack.
# ---------------------------------------------------------------------------

# :251 def __init__(self, config:T5Config, embed_tokens:nn.Embedding)
def t5_stack_init(num_layers: U32, has_relative_attention_bias: Bool) -> D.Refused:
  D.refuse("extra/models/t5.py:251 T5Stack.__init__ -- FIRST MISSING SYMBOL T5Block (:254) -> nn.Embedding (:118)")

# :257 def __call__(self, input_ids:Tensor)
def t5_stack_call(+input_ids: T.Tensor) -> D.Refused:
  D.refuse("extra/models/t5.py:257 T5Stack.__call__ -- reached :260 self.embed_tokens (the missing Embedding) and :258 view (mxw_reshape EXISTS); the loop at :262 is Python control flow, not a graph")

# ---------------------------------------------------------------------------
# :268-286 the two entry points.
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# There is no `if __name__ == "__main__":` in t5.py. `main` prints TWO rows.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, t5_attn_init(4096, 64, 64, True{}))
    srow("t5_refused_at", t5_at(a))
    row("t5_softmax_exists", True{})
    row("t5_matmul_exists", False{})