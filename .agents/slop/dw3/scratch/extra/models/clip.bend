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
# STUB -- 1:1 PATH MIRROR of extra/models/clip.py (480 LOC). NOT YET PORTED.
#
# CLIP IS BOTH HALVES AT ONCE, AND THAT IS WHY IT IS THE ONE FILE IN THIS SLICE
# WHOSE WALLS OVERLAP resnet.bend's AND bert.bend's RATHER THAN CHOOSING.
# Its vision half (`ClipVisionTransformer`, :338) asks for `nn.Conv2d`, which
# resnet.bend's census at :68-81 called MISSING and which is NOW BUILT --
# nn/layers.bend:756 `nn_conv2d`. Its text half (`ClipTextTransformer`, :318)
# asks for `nn.Embedding` (:319) and `nn.LayerNorm` (:322), both of which
# resnet.bend NEVER ASKED FOR and both of which are MISSING.
# So the honest reading of resnet.bend:21 -- "`nn.Conv2d`, `nn.BatchNorm2d` AND
# `nn.Linear` ARE ALL MISSING" -- is STALE for conv2d and linear, and
# `nn/layers.bend:14-27` says so in its own words: "THE WALL TEXT NAMED THE WRONG
# BLOCKER, MEASURED AGAINST WHAT IS ON DISK."
#
# THE NAMED CENSUS FOR THIS FILE:
#   `nn.Embedding`  MISSING (:201,:202,:319) -- the TEXT side.
#   `nn.LayerNorm`  MISSING (:182,:184,:222,:289,:292,:322,:348,:349) -- SEVEN sites,
#                     and this is why clip.py is further from running than retinanet.py
#                     even though both are "vision".
#   `nn.Conv2d`     EXISTS, nn/layers.bend:756 `nn_conv2d` (:343). THE VISION HALF'S
#                     ONLY conv.
#   `nn.Linear`     EXISTS, nn/layers.bend:427 `nn_linear` (:153,:154,:167-170,:261,:279,:280)
#   `Tensor.scaled_dot_product_attention` MISSING (:176,:271) -- BOTH attention sites.
#   `Tensor.quick_gelu` EXISTS, mixin/elementwise.bend:1217 `ew_quick_gelu` (:157).
#   `Tensor.gelu`    AS A BODY, MISSING (mixin/elementwise.bend:772 has only the
#                     CONSTANT `ew_k.gelu`). clip.py:11 binds `Tensor.gelu`, NOT
#                     `Tensor.quick_gelu`, so :157's `h.quick_gelu()` reaches the
#                     body that EXISTS while the module-level alias points at one
#                     that does not. Both facts are recorded because both are true.
#   `Tensor.argmax`  MISSING (:335,:470) -- the EOS-pooling index.
#   `Tensor.triu`    MISSING (:324) -- and it is NOT a creation op: `mixin/creation.bend:9`
#                     names `tril`/`triu` in the inventory it measures itself against
#                     and records that they are not in that file either.
#   `Tensor.empty`   mixin/creation.bend:336 `cr_empty` EXISTS (:320,:323,:345,:346,:351).
#   `Tensor.full`    mixin/creation.bend:417 `cr_full`  EXISTS (:324).
#   `Tensor.arange`  mixin/rand.bend:361 `op_arange`   EXISTS (:470).
#   `x.reshape`/`view` mixin/movement.bend:1431 `mxw_reshape` EXISTS.
#   `x.permute`      mixin/movement.bend:1449 `mxw_permute` EXISTS (:272,:290,:463).
#   `x.expand`       nn/layers.bend:520 `nn_expand`     EXISTS (:356).
#   `x.cat`          MISSING (:356) -- and `mx_cat` at mixin/movement.bend:124 is
#                     SHAPE ARITHMETIC `(a,b) -> a+b`, not the op.
#   `x @ proj`       nn/layers.bend:383 `nn_dot` EXISTS but RETURNS `Maybe`, so
#                     `pooled = x @ self.text_projection` (:337,:361,:471) is not
#                     a call that type-checks today.
#   `x.sin`/`x.cos`  NOT NAMED BY clip.py. (llama.py:10 needs `.cos` and there is
#                     no `def ew_cos`; clip.py does not share that wall.)
#   `square().sum().sqrt()`  ALL THREE EXIST: ew_square (mixin/elementwise.bend:557),
#                     mo_mean/mo_sum (mixin/op.bend:891 / nn/layers.bend:242),
#                     ew_sqrt (mixin/elementwise.bend:549). The Frobenius norm at
#                     :475,:478 is PORTABLE.
#   `adam`           NOT USED BY THIS FILE.
#   `softmax`        NOT USED DIRECTLY -- both attention sites delegate to
#                     `scaled_dot_product_attention`. `mo_softmax`
#                     (mixin/op.bend:1095) EXISTS and would serve T5 but not this.
#
# THE FIRST 140 LINES ARE A BPE TOKENIZER AND ARE NOT A PORTING PROBLEM.
# clip.py:15 `default_bpe()` `fetch`es a gzip file (:16), clip.py:37
# `bytes_to_unicode` is a 256-entry dict, and clip.py:64 `gzip.open` +
# `:88 re.compile` are Python string machinery. `helpers.bend:2815` already
# records the whole HTTP/download seam as unported. Named here so the LOC count
# is not read as arithmetic left undone.
#
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT: `OpenClipEncoder.prepare_image`
# (:446) is PIL -- `from PIL import Image` at :447, `.resize(..., BICUBIC)`,
# `.crop`, `np.array(image.convert('RGB'))` -- and is HOST I/O, not a graph.
#
# TODO(port): STOPPED AT `Open.ClipTextTransformer.__init__` (extra/models/clip.py:318).
# FIRST MISSING SYMBOL: `Embedding(vocab_size, width)` at clip.py:319.
# REACHED BEFORE IT, AND PORTED: `Tensor.empty(ctx_length, width)` at :320
# (mixin/creation.bend:336) and `Tensor.empty(width, width)` at :323.
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))

def cl_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :11 and :14-17. `gelu = Tensor.gelu` is a module-level ALIAS that mlperf
# monkeypatches, and it points at a body mixin/elementwise.bend does not have.
# ---------------------------------------------------------------------------

# :11 gelu = Tensor.gelu
def cl_gelu_alias() -> D.Refused:
  D.refuse("extra/models/clip.py:11 gelu = Tensor.gelu -- MISSING as a BODY; mixin/elementwise.bend:772 has the CONSTANT ew_k.gelu and :1217 has `def ew_quick_gelu`, which is a DIFFERENT function")

# :14-17 @lru_cache() / def default_bpe()
def cl_default_bpe() -> D.Refused:
  D.refuse("extra/models/clip.py:14 default_bpe -- FIRST MISSING SYMBOL fetch (:16); helpers.bend:2815 records the HTTP seam as unported")

# ---------------------------------------------------------------------------
# :19-138 Tokenizer / Tokenizer.ClipTokenizer. NOT PORTED: gzip, re, and a
# Python `dict` of 49408 entries. One def is named so the class is not invisible.
# ---------------------------------------------------------------------------

# :56 def __init__(self, version=None)  [Tokenizer.ClipTokenizer]
def cl_tokenizer_init(version: Maybe<&2, String>) -> D.Refused:
  D.refuse("extra/models/clip.py:56 Tokenizer.ClipTokenizer.__init__ -- FIRST MISSING SYMBOL gzip.open(default_bpe()) (:64); :88 re.compile and :78 the 49408-entry vocab dict follow")

# ---------------------------------------------------------------------------
# :140-234 Closed -- the OpenAI CLIP. FOUR Linear pairs, FOUR LayerNorms, and
# the fused attention.
# ---------------------------------------------------------------------------

# :152 class Closed.ClipMlp / :153 def __init__(self)
def cl_mlp_init() -> D.Refused:
  D.refuse("extra/models/clip.py:152 ClipMlp.__init__ -- fc1/fc2 are Linear (:153,:154) and nn/layers.bend:427 nn_linear EXISTS; BLOCKED BY the missing class shell")

# :155 def __call__(self, h)
def cl_mlp_call(+h: T.Tensor) -> D.Refused:
  D.refuse("extra/models/clip.py:155 ClipMlp.__call__ -- FIRST MISSING SYMBOL Tensor.quick_gelu (:157); mixin/elementwise.bend:1217 `def ew_quick_gelu` EXISTS, so this ONE line is REACHABLE")

# :160 class Closed.ClipAttention / :161 def __init__(self, width, heads)
def cl_closed_attn_init(width: U32, heads: U32) -> D.Refused:
  D.refuse("extra/models/clip.py:161 Closed.ClipAttention.__init__ -- q/k/v/out are Linear (:167-170) and EXIST; BLOCKED BY the missing class shell")

# :172 def __call__(self, x, attn_mask=None)
def cl_closed_attn_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/clip.py:172 Closed.ClipAttention.__call__ -- FIRST MISSING SYMBOL Tensor.scaled_dot_product_attention (:176); the projections (:175) and mxw_permute (:176,:178) are PORTED")

# :196 class Closed.ClipTransformer / :197 def __init__(self, width, layers, heads)
def cl_closed_transformer_init(width: U32, layers: U32, heads: U32) -> D.Refused:
  D.refuse("extra/models/clip.py:197 Closed.ClipTransformer.__init__ -- FIRST MISSING SYMBOL LayerNorm (:182) -- reached :179 before the q/k/v projections")

# :216 def __call__(self, x, attn_mask=None)
def cl_closed_transformer_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/clip.py:216 Closed.ClipTransformer.__call__ -- FIRST MISSING SYMBOL self.layer_norm1 (:182), a LayerNorm")

# :197 def text_transformer(self, x, attn_mask=None)
def cl_closed_text_transformer(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/clip.py:197 text_transformer -- FIRST MISSING SYMBOL self.transformer (:200) -> LayerNorm (:182)")

# :207 def vision_transformer(self, x)
def cl_closed_vision_transformer(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/clip.py:207 vision_transformer -- FIRST MISSING SYMBOL Conv2d (:230); nn/layers.bend:756 `def nn_conv2d` EXISTS, so THIS def's only wall is the missing layer class")

# :236 class FrozenClosedClipEmbedder / :237 def __init__(self, ret_layer_idx=None)
def cl_closed_embedder_init(ret_layer_idx: Maybe<&2, U32>) -> D.Refused:
  D.refuse("extra/models/clip.py:237 FrozenClosedClipEmbedder.__init__ -- FIRST MISSING SYMBOL the tokenizer it builds from (:240); the Frozen half at :238 is `no_grad` + `eval`")

# :242 def __call__(self, texts)
def cl_closed_embedder_call() -> D.Refused:
  D.refuse("extra/models/clip.py:242 FrozenClosedClipEmbedder.__call__ -- FIRST MISSING SYMBOL TextTransformer.forward (:247) -> LayerNorm (:222)")

# :249 Open. NOT PORTED. NOT PORTED. NOT PORTED: the "leaky" softmax of open-clip
# at :277 is `(x * 100.0).softmax(dim=-1).to(x.dtype)` and it is the ONLY
# `softmax` any file in this slice calls DIRECTLY on the open side.
# ---------------------------------------------------------------------------

# :250 class Open / :251 def __init__(self, embed_dim, num_heads, layers, mlp_ratio=4.0)
def cl_open_init(embed_dim: U32, num_heads: U32, layers: U32) -> D.Refused:
  D.refuse("extra/models/clip.py:251 Open.__init__ -- FIRST MISSING SYMBOL LayerNorm (:289)")

# :271 def __call__(self, x, attn_mask=None)  [Open.ResidualAttentionBlock]
def cl_open_attn_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/clip.py:271 ResidualAttentionBlock.__call__ -- FIRST MISSING SYMBOL Tensor.scaled_dot_product_attention; out_proj is Linear (:261) and EXISTS")

# :285 class Open.ClipTransformer / :286 def __init__(self, width, layers, heads, ...)
def cl_open_transformer_init(width: U32, layers: U32, heads: U32) -> D.Refused:
  D.refuse("extra/models/clip.py:286 Open.ClipTransformer.__init__ -- FIRST MISSING SYMBOL LayerNorm (:289)")

# :296 def __call__(self, x, attn_mask=None)
def cl_open_transformer_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/clip.py:296 Open.ClipTransformer.__call__ -- FIRST MISSING SYMBOL self.ln_1 (:289)")

# :318 class Open.ClipTextTransformer / :319 def __init__(self, width, n_heads, layers, vocab_size=49408, ctx_length=77)
def cl_text_transformer_init(width: U32, n_heads: U32, layers: U32, vocab_size: U32, ctx_length: U32) -> D.Refused:
  D.refuse("extra/models/clip.py:319 ClipTextTransformer.__init__ -- FIRST MISSING SYMBOL Embedding (:319) -- THE FIRST MISSING SYMBOL OF THE WHOLE FILE; cr_empty (:320,:323) EXISTS at mixin/creation.bend:336")

# :327 def __call__(self, text)
def cl_text_transformer_call(+text: T.Tensor) -> D.Refused:
  D.refuse("extra/models/clip.py:327 ClipTextTransformer.__call__ -- FIRST MISSING SYMBOL self.token_embedding (:331), the same missing Embedding")

# :338 class Open.ClipVisionTransformer / :339 def __init__(self, width, layers, d_head, image_size, patch_size)
def cl_vision_transformer_init(width: U32, layers: U32, d_head: U32, image_size: U32, patch_size: U32) -> D.Refused:
  D.refuse("extra/models/clip.py:339 ClipVisionTransformer.__init__ -- FIRST MISSING SYMBOL LayerNorm (:348); the ONLY conv, nn_conv2d at nn/layers.bend:756, EXISTS (:343)")

# :352 def __call__(self, x)
def cl_vision_transformer_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/clip.py:352 ClipVisionTransformer.__call__ -- reached :353 nn_conv2d and :355 mxw_reshape and :356 nn_expand, ALL PORTED; BLOCKED AT :356 Tensor.cat")

# :368 class FrozenOpenClipEmbedder / :369 def __init__(self, dims, n_heads, layers, return_pooled, ln_penultimate=False, clip_tokenizer_version=None)
def cl_frozen_open_init(dims: U32, n_heads: U32, layers: U32, return_pooled: Bool) -> D.Refused:
  D.refuse("extra/models/clip.py:369 FrozenOpenClipEmbedder.__init__ -- FIRST MISSING SYMBOL Open.ClipTransformer (:386) -> LayerNorm (:289)")

# :376 def tokenize(self, text, device=None)
def cl_tokenize() -> D.Refused:
  D.refuse("extra/models/clip.py:376 tokenize -- FIRST MISSING SYMBOL the Tokenizer (:95), which is gzip + re + a 49408-entry dict")

# :379 def text_transformer_forward(self, x, attn_mask=None)
def cl_frozen_text_forward(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/clip.py:379 text_transformer_forward -- FIRST MISSING SYMBOL self.transformer (:382) -> LayerNorm (:322)")

# :384 def embed_tokens(self, tokens)
def cl_embed_tokens(+tokens: T.Tensor) -> D.Refused:
  D.refuse("extra/models/clip.py:384 embed_tokens -- FIRST MISSING SYMBOL self.token_embedding (:386) / self.transformer (:387); the EOS pool at :390 is Tensor.argmax, MISSING")

# :399 def __call__(self, texts)
def cl_frozen_open_call() -> D.Refused:
  D.refuse("extra/models/clip.py:399 FrozenOpenClipEmbedder.__call__ -- FIRST MISSING SYMBOL self.tokenizer (:401), i.e. gzip + re")

# :428 class OpenClipEncoder / :429 def __init__(self, dims, text_cfg, vision_cfg, **_)
def cl_openclip_encoder_init(dims: U32) -> D.Refused:
  D.refuse("extra/models/clip.py:429 OpenClipEncoder.__init__ -- FIRST MISSING SYMBOL Open.ClipTransformer (:450) -> LayerNorm")

# :446 def prepare_image(self, image)
def cl_prepare_image() -> D.Refused:
  D.refuse("extra/models/clip.py:446 prepare_image -- FIRST MISSING SYMBOL from PIL import Image (:447); this is HOST I/O -- resize/crop/np.array -- and not a graph")

# :464 def encode_tokens(self, tokens)
def cl_openclip_encode_tokens(+tokens: T.Tensor) -> D.Refused:
  D.refuse("extra/models/clip.py:464 encode_tokens -- FIRST MISSING SYMBOL self.transformer (:467) -> LayerNorm; :469 also needs Tensor.argmax for the EOS index and :470 `x @ self.text_projection` is nn_dot, which RETURNS Maybe")

# :473 def get_clip_score(self, tokens, image)
def cl_get_clip_score(+tokens: T.Tensor, +image: T.Tensor) -> D.Refused:
  D.refuse("extra/models/clip.py:473 get_clip_score -- FIRST MISSING SYMBOL self.visual (:474); the Frobenius norm at :475,:478 is FULLY PORTED (ew_square, mo_sum, ew_sqrt)")

# ---------------------------------------------------------------------------
# There is no `if __name__ == "__main__":` in clip.py. `main` prints TWO rows.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, cl_text_transformer_init(768, 12, 12, 49408, 77))
    srow("clip_refused_at", cl_at(a))
    row("clip_conv2d_exists", True{})
    row("clip_embedding_exists", False{})