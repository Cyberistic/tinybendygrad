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
# STUB -- 1:1 PATH MIRROR of extra/models/llama.py (286 LOC). NOT YET PORTED.
#
# LLAMA IS THE FURTHEST OF THE THREE TRANSFORMERS AND IT IS FURTHEST BY A
# DIFFERENT REASON THAN THE OTHER TWO. bert.bend and t5.bend both fail on a LAYER
# (`nn.Embedding`, `nn.LayerNorm`/`nn.RMSNorm`). llama fails on a STACK: FOUR
# norms where BERT has one kind and T5 has a hand-written one.
#
# THE NAMED CENSUS FOR THIS FILE:
#   `nn.Embedding`  MISSING. (:201,:202) `grep -rnwE "def .*Embedding" --include='*.bend' tinybendygrad/` = 0, and so is `def mo_i`/`def mo_fx`.
#   `nn.RMSNorm`    MISSING. (:53,:54,:137,:138,:200)  FIVE sites, and this is THE FIRST MISSING SYMBOL of the file: extra/models/llama.py:53 `self.q_norm
#   `Tensor.scaled_dot_product_attention` MISSING. (:101,:104) `grep -rnwE "def .*scaled_dot_product_attention" --include='*.bend'` = 0.
#   `softmax`       EXISTS, mixin/op.bend:1157 symbol=mo_softmax `mo_softmax` (:165 in `sample`).
#   `adam`          EXISTS and UNUSED BY THIS FILE. nn/optim.bend:900 symbol=op_mstep
#                   `op_mstep` is
#                   `(self.b1 * self.m[i] + (1.0 - self.b1) * g).cast(...)` -- verbatim, upstream's
#                   `assign` at nn/optim.py:167 (inside upstream's `Adam._step`, declared at
#                   nn/optim.py:161 symbol=_step), and nn/optim.bend:905 symbol=op_vstep
#                   `op_vstep`
#                   is upstream's `assign` at nn/optim.py:168; `op_mhat`/`op_vhat` are
#                   upstream's `m_hat`/`v_hat` at nn/optim.py:169-170. The optimizer
#                   llama.py would train with is ALREADY PORTED; llama.py only INFERENCES.
#                   THAT IS THE ANSWER TO "DOES A TRAINING LOOP NEED SOMETHING NEW": NO. The
#                   adam half is DONE; a training loop would add a loss (`binary_crossentropy_logits`, extra/models/bert.py:61, MISSING).
#
# WHAT EXISTS AND LLAMA GETS IT FROM THE VISION WORK, WITH ITS INSTRUMENT:
#   `nn.Linear`           nn/layers.bend:530 symbol=nn_linear `nn_linear`   (:45,:46,:47,:48,:51,:123,:124,:125,:202)
#   `Tensor.silu`         mixin/elementwise.bend:1221 symbol=ew_silu `ew_silu` (:128) -- and it is `ew_swish` :1220 symbol=ew_swish, no extra def
#   `Tensor.sin`          mixin/elementwise.bend:550 `ew_sin`  (:10)
#   `Tensor.arange`       mixin/rand.bend:424 symbol=op_arange `op_arange`     (:8,:9,:167)
#   `Tensor.stack`        mixin/movement.bend:1272 symbol=mxw_stk `mxw_stk`  (:10,:90)
#   `Tensor.zeros`        mixin/creation.bend:518 symbol=cr_zeros `cr_zeros`  (:83,:158,:170)
#   `Tensor.zeros_like`   mixin/creation.bend:553 symbol=cr_zeros_like `cr_zeros_like` (:158)
#   `x.reshape`           mixin/movement.bend:1431 `mxw_reshape` (:10,:22,:23,:34,:59,:60,:61,:62,:73,:74,:75,:118,:233)
#   `x.transpose`         mixin/movement.bend:1449 `mxw_permute` (:100,:101,:103,:104)
#   `x.repeat`            nn/layers.bend:640 symbol=nn_repeat `nn_repeat`      (:34)
#   `x.softmax`           mixin/op.bend:1157 symbol=mo_softmax `mo_softmax`     (:165)
#   `x.cast`              mixin/op.bend:390 symbol=mo_cast_t `mo_cast_t`       (:10,:204,:216)
#   `x.contiguous_backward` mixin/elementwise.bend:546 `ew_contiguous_backward` (:64,:71,:129,:142,:216)
#   `x.sigmoid`/`x.tanh`  mixin/elementwise.bend:1196 / :1232  (through ew_sigmoid, which llama does not name)
#
# THE THREE THAT ARE LLAMA-ONLY AND NOT ATTENTION-ANYWHERE-ELSE:
#   (1) `Tensor.cos`   MISSING. (:10) mixin/elementwise.bend:550 has `def ew_sin` and there is
#                     NO `def ew_cos`. RoPE needs the pair and only half of it landed.
#   (2) `Tensor.erf`   MISSING. extra/models/bert.py:236 needs it too.
#   (3) `Tensor.multinomial` MISSING. (:184,:187) and `logits.argmax()` MISSING (:151).
#                     `mixin/rand.bend:880 rd_randperm` records at rand.py:249 that
#                     `argsort` is a bitonic sort over four nested Python `for` loops and
#                     marks it `TODO(p3)` -- `multinomial` sits behind the same sort.
#
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT:
#   * `cache_kv` (extra/models/llama.py:82,:83,:86,:90,:92,:93) -- the kv cache is
#     an IN-PLACE slice-assign on a
#     realized tensor plus a `hasattr`/`isinstance(device, tuple)`/`shard_` probe.
#     `nn/optim.bend:3-45` records the same wall for its own in-place arm.
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
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))

def lm_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :7-10 `precompute_freqs_cis`. The ONE def in this file whose first line is a
# ported symbol (`Tensor.arange`, mixin/rand.bend:361) and whose second is not.
# ---------------------------------------------------------------------------

# :7  def precompute_freqs_cis(dim: int, end: int, theta: float = 10000.0) -> Tensor
def lm_precompute_freqs_cis(dim: U32, end: U32, theta: F32) -> D.Refused:
  D.refuse("extra/models/llama.py:7 precompute_freqs_cis -- reached :8 Tensor.arange (mixin/rand.bend:361 EXISTS); BLOCKED AT :10 Tensor.cos, and there is no `def ew_cos`")

# :14 def complex_mult(A, c, d)
def lm_complex_mult(+a: T.Tensor, +c: T.Tensor, +d: T.Tensor) -> D.Refused:
  D.refuse("extra/models/llama.py:14 complex_mult -- reached :16,:17 the two arithmetic arms (ew_mul/ew_sub/ew_add ALL EXIST); BLOCKED AT :18 Tensor.cat")

# :20 def apply_rotary_emb(xq:Tensor, xk:Tensor, freqs_cis:Tensor) -> tuple[Tensor, Tensor]
def lm_apply_rotary_emb(+xq: T.Tensor, +xk: T.Tensor, +freqs_cis: T.Tensor) -> D.Refused:
  D.refuse("extra/models/llama.py:20 apply_rotary_emb -- FIRST MISSING SYMBOL complex_mult (:26), which is blocked on Tensor.cat")

# :30 def repeat_kv(x:Tensor, n_rep:int) -> Tensor
def lm_repeat_kv(+x: T.Tensor, n_rep: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:30 repeat_kv -- nn/layers.bend:523 nn_repeat EXISTS (:34) and mxw_reshape EXISTS; BLOCKED BY the missing signature tuple at :31")

# ---------------------------------------------------------------------------
# :36-119 Attention. THE CLASS THAT NAMES THE TWO MISSING FAMILIES.
# ---------------------------------------------------------------------------

# :37 def __init__(self, dim, n_heads, n_kv_heads=None, max_context=0, linear=nn.Linear, qk_norm=None)
def lm_attn_init(dim: U32, n_heads: U32, n_kv_heads: Maybe<&2, U32>, max_context: U32, qk_norm: Maybe<&2, F32>) -> D.Refused:
  D.refuse("extra/models/llama.py:37 Attention.__init__ -- wq/wk/wv/wo are linear (:45-51, nn/layers.bend:427 EXISTS); FIRST MISSING SYMBOL nn.RMSNorm (:53)")

# :40 self.head_dim = dim // n_heads
def lm_attn_head_dim(dim: U32, n_heads: U32) -> U32:
  U32.div(dim, n_heads)

# :41 self.n_rep = self.n_heads // self.n_kv_heads
def lm_attn_n_rep(n_heads: U32, n_kv_heads: U32) -> U32:
  U32.div(n_heads, n_kv_heads)

# :56 def __call__(self, x, start_pos, freqs_cis, mask=None) -> Tensor
def lm_attn_call(+x: T.Tensor, start_pos: U32, +freqs_cis: T.Tensor) -> D.Refused:
  D.refuse("extra/models/llama.py:56 Attention.__call__ -- FIRST MISSING SYMBOL self.q_norm (:67) if qk_norm is set, else Tensor.scaled_dot_product_attention (:101); the kv-cache arm (:83-93) is a THIRD wall and is NOT PORTED")

# ---------------------------------------------------------------------------
# :121-130 FeedForward.
# ---------------------------------------------------------------------------

# :122 def __init__(self, dim:int, hidden_dim:int, linear=nn.Linear)
def lm_ff_init(dim: U32, hidden_dim: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:122 FeedForward.__init__ -- w1/w2/w3 are linear (:123-125, EXISTS); BLOCKED BY the missing class shell")

# :127 def __call__(self, x:Tensor) -> Tensor
def lm_ff_call(+x: T.Tensor) -> D.Refused:
# THE REFUSAL BELOW NAMES `mixin/elementwise.bend:1221`, AND `ew_silu` IS THERE:
# mixin/elementwise.bend:1221 symbol=ew_silu. THE STRING IS A DIAGNOSTIC ADDRESS,
# NOT BEHAVIOUR: `Refused{at}` is a payload no computation reads, and the address
# it names WAS STALE.
  D.refuse("extra/models/llama.py:127 FeedForward.__call__ -- FIRST MISSING SYMBOL Tensor.silu (:128); mixin/elementwise.bend:1221 `def ew_silu` EXISTS, so this def is REACHABLE TODAY")

# ---------------------------------------------------------------------------
# :132-142 TransformerBlock.
# ---------------------------------------------------------------------------

# :133 def __init__(self, dim, hidden_dim, n_heads, n_kv_heads, norm_eps, max_context, linear=nn.Linear, feed_forward=FeedForward, qk_norm=None)
def lm_block_init(dim: U32, hidden_dim: U32, n_heads: U32, n_kv_heads: U32, norm_eps: F32, max_context: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:133 TransformerBlock.__init__ -- FIRST MISSING SYMBOL Attention (:135) -> nn.RMSNorm (:53)")

# :140 def __call__(self, x, start_pos, freqs_cis, mask)
def lm_block_call(+x: T.Tensor, start_pos: U32, +freqs_cis: T.Tensor) -> D.Refused:
  D.refuse("extra/models/llama.py:140 TransformerBlock.__call__ -- FIRST MISSING SYMBOL self.attention_norm (:141), a second nn.RMSNorm")

# ---------------------------------------------------------------------------
# :145-193 `sample`. THE OPENAI SAMPLER. Its alpha counter is a `setattr` on the
# function object (:158,:191), which is Python-level state with no Bend spelling,
# so this def has a divergence as well as the four missing ops.
# ---------------------------------------------------------------------------

# :145 def sample(logits: Tensor, temp: float, k: int, p: float, af: float, ap: float)
def lm_sample(+logits: T.Tensor, temp: F32, k: U32, p: F32, af: F32, ap: F32) -> D.Refused:
  D.refuse("extra/models/llama.py:145 sample -- FIRST MISSING SYMBOL logits.argmax (:151); mo_softmax EXISTS (:165), arange EXISTS (:167), pad EXISTS (mixin/movement.bend:1517), and Tensor.multinomial (:184,:187) is MISSING BEHIND `argsort` (mixin/rand.bend:880 TODO(p3))")

# ---------------------------------------------------------------------------
# :195-225 Transformer.
# ---------------------------------------------------------------------------

# :196 def __init__(self, dim, hidden_dim, n_heads, n_layers, norm_eps, vocab_size, linear=nn.Linear, embedding=nn.Embedding, n_kv_heads=None, rope_theta=10000, max_context=1024, jit=True, feed_forward=FeedForward, qk_norm=None, disable_kv_cache=False)
def lm_transformer_init(dim: U32, hidden_dim: U32, n_heads: U32, n_layers: U32, norm_eps: F32, vocab_size: U32, n_kv_heads: Maybe<&2, U32>, rope_theta: U32, max_context: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:196 Transformer.__init__ -- FIRST MISSING SYMBOL TransformerBlock (:198) -> nn.RMSNorm (:53); nn.Embedding (:201) and TinyJit (:205) are the SECOND and THIRD")

# :207 def forward(self, tokens, start_pos, temperature, top_k, top_p, alpha_f, alpha_p)
def lm_transformer_forward(+tokens: T.Tensor, start_pos: U32, temperature: F32) -> D.Refused:
  D.refuse("extra/models/llama.py:207 Transformer.forward -- FIRST MISSING SYMBOL self.tok_embeddings (:209), the missing nn.Embedding")

# :221 def __call__(self, tokens, start_pos, temperature=0.0, top_k=0, top_p=0.8, alpha_f=0.0, alpha_p=0.0)
def lm_transformer_call(+tokens: T.Tensor, start_pos: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:221 Transformer.__call__ -- FIRST MISSING SYMBOL self.forward_jit (:223,:224); TinyJit is PARTIAL per resnet.bend:116-123 -- engine/jit.bend is a port and the NAME and the DECORATOR are not")

# ---------------------------------------------------------------------------
# :227-286 the three helpers. None of them is a graph.
# ---------------------------------------------------------------------------

# :230 def convert_from_huggingface(weights:dict[str, Tensor], n_layers, n_heads, n_kv_heads, permute_layers=True)
def lm_from_huggingface(n_layers: U32, n_heads: U32, n_kv_heads: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:230 convert_from_huggingface -- FIRST MISSING SYMBOL the weights dict (:248); `permute` (:233) is reshape+transpose+reshape and IS ported, and `.rotary_emb.` keys are dropped at :250")

# :269 def convert_from_gguf(weights:dict[str, Tensor], n_layers:int)
def lm_from_gguf(n_layers: U32) -> D.Refused:
  D.refuse("extra/models/llama.py:269 convert_from_gguf -- FIRST MISSING SYMBOL the weights dict (:280); the keymap at :271-279 is a dict comprehension over `range(n_layers)` and is plain data")

# :284 def fix_bf16(weights:dict[Any, Tensor])
def lm_fix_bf16() -> D.Refused:
  D.refuse("extra/models/llama.py:284 fix_bf16 -- FIRST MISSING SYMBOL the weights dict (:286); the body (:286) is two `cast`s and mo_cast_t EXISTS, so the CAST is not the wall")

# ---------------------------------------------------------------------------
# There is no `if __name__ == "__main__":` in llama.py. `main` prints TWO rows.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, lm_attn_init(4096, 32, None{}, 2048, None{}))
    srow("llama_refused_at", lm_at(a))
    row("llama_attention_exists", False{})
    row("llama_adam_exists", True{})