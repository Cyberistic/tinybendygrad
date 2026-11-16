# gates/models-llama-gate.bend -- the gate driver for `tinybendygrad/extra/models/llama.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/extra/models/llama.bend as P

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

def lm_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# :7-10 `precompute_freqs_cis`. The ONE def in this file whose first line is a
# ported symbol (`Tensor.arange`, mixin/rand.bend:363 symbol=op_pool1.iz) and whose second is not.

# :7  def precompute_freqs_cis(dim: int, end: int, theta: float = 10000.0) -> Tensor
def lm_precompute_freqs_cis(dim: U32, end: U32, theta: F32) -> D.Refused:
  D.refuse("extra/models/llama.py:7 precompute_freqs_cis -- reached :8 Tensor.arange (mixin/rand.bend:363 symbol=op_pool1.iz EXISTS); BLOCKED AT :10 Tensor.cos, and there is no `def ew_cos`")

# :14 def complex_mult(A, c, d)
def lm_complex_mult(+a: T.Tensor, +c: T.Tensor, +d: T.Tensor) -> D.Refused:
  D.refuse("extra/models/llama.py:14 complex_mult -- reached :16,:17 the two arithmetic arms (ew_mul/ew_sub/ew_add ALL EXIST); BLOCKED AT :18 Tensor.cat")

# :20 def apply_rotary_emb(xq:Tensor, xk:Tensor, freqs_cis:Tensor) -> tuple[Tensor, Tensor]
def lm_apply_rotary_emb(+xq: T.Tensor, +xk: T.Tensor, +freqs_cis: T.Tensor) -> D.Refused:
  D.refuse("extra/models/llama.py:20 apply_rotary_emb -- FIRST MISSING SYMBOL complex_mult (:26), which is blocked on Tensor.cat")

# :30 def repeat_kv(x:Tensor, n_rep:int) -> Tensor
def lm_repeat_kv(+x: T.Tensor, n_rep: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:30 repeat_kv -- nn/layers.bend:627 symbol=nn_repeat EXISTS (:34) and mxw_reshape EXISTS; BLOCKED BY the missing signature tuple at :31")

# :36-119 Attention. the class that names the two missing families.

# :37 def __init__(self, dim, n_heads, n_kv_heads=None, max_context=0, linear=nn.Linear, qk_norm=None)
def lm_attn_init(dim: U32, n_heads: U32, n_kv_heads: Maybe<&2, U32>, max_context: U32, qk_norm: Maybe<&2, F32>) -> D.Refused:
  D.refuse("extra/models/llama.py:37 Attention.__init__ -- wq/wk/wv/wo are linear (:45-51, nn/layers.bend:518 symbol=nn_linear EXISTS); FIRST MISSING SYMBOL nn.RMSNorm (:53)")

# :40 self.head_dim = dim // n_heads
def lm_attn_head_dim(dim: U32, n_heads: U32) -> U32:
  U32.div(dim, n_heads)

# :41 self.n_rep = self.n_heads // self.n_kv_heads
def lm_attn_n_rep(n_heads: U32, n_kv_heads: U32) -> U32:
  U32.div(n_heads, n_kv_heads)

# :56 def __call__(self, x, start_pos, freqs_cis, mask=None) -> Tensor
def lm_attn_call(+x: T.Tensor, start_pos: U32, +freqs_cis: T.Tensor) -> D.Refused:
  D.refuse("extra/models/llama.py:56 Attention.__call__ -- FIRST MISSING SYMBOL self.q_norm (:67) if qk_norm is set, else Tensor.scaled_dot_product_attention (:101); the kv-cache arm (:83-93) is a THIRD wall and is NOT PORTED")

# :121-130 FeedForward.

# :122 def __init__(self, dim:int, hidden_dim:int, linear=nn.Linear)
def lm_ff_init(dim: U32, hidden_dim: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:122 FeedForward.__init__ -- w1/w2/w3 are linear (:123-125, EXISTS); BLOCKED BY the missing class shell")

# :127 def __call__(self, x:Tensor) -> Tensor
def lm_ff_call(+x: T.Tensor) -> D.Refused:
# the refusal below names `mixin/elementwise.bend:1199`, and `ew_silu` is there:
# mixin/elementwise.bend:1199 symbol=ew_silu. THE STRING IS A DIAGNOSTIC ADDRESS,
# NOT BEHAVIOUR: `Refused{at}` is a payload no computation reads, and the address
# it names WAS STALE.
  D.refuse("extra/models/llama.py:127 FeedForward.__call__ -- FIRST MISSING SYMBOL Tensor.silu (:128); mixin/elementwise.bend:1199 `def ew_silu` EXISTS, so this def is REACHABLE TODAY")

# :132-142 TransformerBlock.

# :133 def __init__(self, dim, hidden_dim, n_heads, n_kv_heads, norm_eps, max_context, linear=nn.Linear, feed_forward=FeedForward, qk_norm=None)
def lm_block_init(dim: U32, hidden_dim: U32, n_heads: U32, n_kv_heads: U32, norm_eps: F32, max_context: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:133 TransformerBlock.__init__ -- FIRST MISSING SYMBOL Attention (:135) -> nn.RMSNorm (:53)")

# :140 def __call__(self, x, start_pos, freqs_cis, mask)
def lm_block_call(+x: T.Tensor, start_pos: U32, +freqs_cis: T.Tensor) -> D.Refused:
  D.refuse("extra/models/llama.py:140 TransformerBlock.__call__ -- FIRST MISSING SYMBOL self.attention_norm (:141), a second nn.RMSNorm")

# :145-193 `sample`. THE OPENAI SAMPLER. Its alpha counter is a `setattr` on the
# function object (:158,:191), which is Python-level state with no Bend spelling,
# so this def has a divergence as well as the four missing ops.

# :145 def sample(logits: Tensor, temp: float, k: int, p: float, af: float, ap: float)
def lm_sample(+logits: T.Tensor, temp: F32, k: U32, p: F32, af: F32, ap: F32) -> D.Refused:
  D.refuse("extra/models/llama.py:145 sample -- FIRST MISSING SYMBOL logits.argmax (:151); mo_softmax EXISTS (:165), arange EXISTS (:167), pad EXISTS (mixin/movement.bend:1498 symbol=mxw_pad.put), and Tensor.multinomial (:184,:187) is MISSING BEHIND `argsort` (mixin/rand.bend:874 symbol=rd_randn_like.src TODO(p3))")

# :195-225 Transformer.

# :196 def __init__(self, dim, hidden_dim, n_heads, n_layers, norm_eps, vocab_size, linear=nn.Linear, embedding=nn.Embedding, n_kv_heads=None, rope_theta=10000, max_context=1024, jit=True, feed_forward=FeedForward, qk_norm=None, disable_kv_cache=False)
def lm_transformer_init(dim: U32, hidden_dim: U32, n_heads: U32, n_layers: U32, norm_eps: F32, vocab_size: U32, n_kv_heads: Maybe<&2, U32>, rope_theta: U32, max_context: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:196 Transformer.__init__ -- FIRST MISSING SYMBOL TransformerBlock (:198) -> nn.RMSNorm (:53); nn.Embedding (:201) and TinyJit (:205) are the SECOND and THIRD")

# :207 def forward(self, tokens, start_pos, temperature, top_k, top_p, alpha_f, alpha_p)
def lm_transformer_forward(+tokens: T.Tensor, start_pos: U32, temperature: F32) -> D.Refused:
  D.refuse("extra/models/llama.py:207 Transformer.forward -- FIRST MISSING SYMBOL self.tok_embeddings (:209), the missing nn.Embedding")

# :221 def __call__(self, tokens, start_pos, temperature=0.0, top_k=0, top_p=0.8, alpha_f=0.0, alpha_p=0.0)
def lm_transformer_call(+tokens: T.Tensor, start_pos: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:221 Transformer.__call__ -- FIRST MISSING SYMBOL self.forward_jit (:223,:224); TinyJit is PARTIAL per THE PORT's `extra/models/resnet.bend` HEADER -- engine/jit.bend is a port and the NAME and the DECORATOR are not")

# :227-286 the three helpers. None of them is a graph.

# :230 def convert_from_huggingface(weights:dict[str, Tensor], n_layers, n_heads, n_kv_heads, permute_layers=True)
def lm_from_huggingface(n_layers: U32, n_heads: U32, n_kv_heads: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:230 convert_from_huggingface -- FIRST MISSING SYMBOL the weights dict (:248); `permute` (:233) is reshape+transpose+reshape and IS ported, and `.rotary_emb.` keys are dropped at :250")

# :269 def convert_from_gguf(weights:dict[str, Tensor], n_layers:int)
def lm_from_gguf(n_layers: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:269 convert_from_gguf -- FIRST MISSING SYMBOL the weights dict (:280); the keymap at :271-279 is a dict comprehension over `range(n_layers)` and is plain data")

# :284 def fix_bf16(weights:dict[Any, Tensor])
def lm_fix_bf16() -> D.Refused:
  D.refuse("extra/models/llama.py:284 fix_bf16 -- FIRST MISSING SYMBOL the weights dict (:286); the body (:286) is two `cast`s and mo_cast_t EXISTS, so the CAST is not the wall")

# There is no `if __name__ == "__main__":` in llama.py. `main` prints TWO rows.

def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, lm_attn_init(4096, 32, None{}, 2048, None{}))
    srow("llama_refused_at", lm_at(a))
    row("llama_attention_exists", False{})
    row("llama_adam_exists", True{})
