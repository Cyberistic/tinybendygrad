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
# STUB -- 1:1 PATH MIRROR of extra/models/transformer.py (61 LOC). NOT YET PORTED.
#
# THE HEADLINE, AND IT IS THE ANSWER TO "DO THESE MODELS NEED ANYTHING THE VISION
# MODELS DID NOT ASK FOR": YES, AND IT IS EXACTLY ONE NAME.
# `Tensor.scaled_dot_product_attention` (transformer.py:27, :60) is MISSING, and
# `grep -rnwE "def .*scaled_dot_product_attention" --include='*.bend' tinybendygrad/`
# returns 0. A vision model never names it -- resnet.bend's own census at :40-123
# asks for conv2d, batchnorm, linear, sequential, argmax, item, torch_load, fetch,
# get_child, rand and TinyJit, and `scaled_dot_product_attention` is not among them
# because no convolution has ever attended to anything.
#
# EVERYTHING ELSE IN THIS FILE IS ALREADY HERE, which is the other half of the
# finding and the reason the distance is this short:
#   `Tensor.scaled_uniform`  mixin/rand.bend:855 `rd_scaled_uniform`   (:12,:13,:14,:16,:18,:19,:44,:46)
#   `Tensor.zeros`           mixin/creation.bend:446 `cr_zeros`         (:12,:13,:14,:16,:18,:19,:21,:22)
#   `Tensor.ones`            mixin/creation.bend:487 `cr_ones`          (:21,:22)
#   `x.linear`               nn/layers.bend:427 `nn_linear`            (:26,:28,:32,:33,:36,:37)
#   `reshape`                mixin/movement.bend:1431 `mxw_reshape`     (:26,:28)
#   `transpose`              mixin/movement.bend:1449 `mxw_permute`     (:26,:27)
#   `x.relu`                 nn/layers.bend:262 `nn_relu`              (the `act` default, :4)
#   `x.dot`                  nn/layers.bend:383 `nn_dot`               (:58,:60)
#   `log_softmax`            mixin/op.bend:1109 `mo_log_softmax`       (:60)
#   `softmax` (its sibling)  mixin/op.bend:1095 `mo_softmax`            EXISTS -- the ONE named family that is present
#   `x.expand`               nn/layers.bend:520 `nn_expand`             (:52)
#   `x.cast` / `.int()`      mixin/op.bend:370 `mo_cast_t`             (:54)
#
# SO `TransformerBlock.__init__` IS PORTABLE TODAY. `rd_scaled_uniform` + `cr_zeros`
# + `cr_ones` + `NN.nn_scale` are all callable and all gated upstream, so the eight
# weight TUPLEs of :12-22 can be allocated. The def below refuses anyway, because a
# refusable half of a class is not the class.
#
# TODO(port): STOPPED AT `TransformerBlock.attn` (extra/models/transformer.py:24).
# MISSING:
#   (1) `Tensor.scaled_dot_product_attention` -- transform.py's `op.py:1177`. It is
#       the ONLY symbol in this file with no counterpart, and it is the wall for
#       `attn` (:27), for `Transformer.forward`'s `log_softmax` half (:60 needs only
#       `mo_log_softmax`, which EXISTS), and for every other transformer-shaped file
#       in this directory -- bert.py:279, clip.py:176, clip.py:271, llama.py:101,
#       llama.py:104.
#   (2) `x.layernorm` -- `grep -rnwE "def .*layernorm" --include='*.bend'` = 0.
#       `TransformerBlock.__call__` (:32, :36, :38) and nothing else in this file
#       runs without it. It is the SECOND wall and the one that survives fixing (1).
#   (3) `x.dropout` -- `grep -rnwE "def .*dropout" --include='*.bend'` = 0 (:32,:33,:35,:37).
#   (4) `Tensor.eye` (:51) -- MISSING; `mixin/creation.bend:9` names `eye` in the
#       inventory it measures itself AGAINST and records that it is NOT in that file.
#   (5) `x.int().one_hot(...)` (:54) -- `one_hot` MISSING.
#   (6) `Tensor.cat` (:56) and `Tensor.flatten` (:56) -- `mo_cat`/`mx_flatten` MISSING.
#       `mixin/movement.bend:124` `mx_cat` is SHAPE ARITHMETIC (`(a,b) -> a+b`), not
#       the op, so it does not close this.
#   (7) `x.sequential(self.tbs)` (:59) -- MISSING, and resnet.bend's own census names
#       it MISSING too, so this one is NOT a new ask.
#
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT: `maxlen_eye` (:51), the three-element
# list comprehension of :26 (a Python comprehension over `self.query`/`key`/`value`).
#
# ON `adam`: NOT USED BY THIS FILE. `extra/models/transformer.py` never constructs an
# optimizer. The one that DOES is llama.py's sampling caller, and `nn/optim.bend`
# already carries `op_mstep` :898 and `op_vstep` :903 -- see llama.bend's header.
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))

def tf_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :3-39 TransformerBlock. `num_heads` (:7), `head_size = embed_dim // num_heads`
# (:8) and `prenorm`/`act`/`dropout` (:9-10) are the constructor's body, and
# `NN.nn_len`/`U32.div` cover the integer half. The SEVEN weight tuples (:12-22)
# are the first thing this file cannot build, and `rd_scaled_uniform` is why they
# are NOT the first thing.
# ---------------------------------------------------------------------------

# :4  def __init__(self, embed_dim, num_heads, ff_dim, prenorm=False,
#                  act=lambda x: x.relu(), dropout=0.1)
def tf_block_init(embed_dim: U32, num_heads: U32, ff_dim: U32, prenorm: Bool, dropout: F32) -> D.Refused:
  D.refuse("extra/models/transformer.py:4 TransformerBlock.__init__ -- reached :12 Tensor.scaled_uniform (mixin/rand.bend:855 EXISTS); BLOCKED AT :27 scaled_dot_product_attention via attn")

# :5  assert embed_dim % num_heads == 0, "embed_dim must be divisible by num_heads"
def tf_block_assert_head_size(embed_dim: U32, num_heads: U32) -> Bool:
  Bool.pick(Bool, U32.is_eq(U32.mod(embed_dim, num_heads), 0), True{}, False{})

# :8  self.head_size = embed_dim // num_heads
def tf_block_head_size(embed_dim: U32, num_heads: U32) -> U32:
  U32.div(embed_dim, num_heads)

# :24 def attn(self, x)
def tf_block_attn(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/transformer.py:24 TransformerBlock.attn -- FIRST MISSING SYMBOL Tensor.scaled_dot_product_attention (:27)")

# :30 def __call__(self, x)
def tf_block_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/transformer.py:30 TransformerBlock.__call__ -- FIRST MISSING SYMBOL Tensor.scaled_dot_product_attention via attn (:35), then x.layernorm (:36)")

# ---------------------------------------------------------------------------
# :41-61 Transformer. `self.embed` (:44) is `Tensor.scaled_uniform(...).is_param_(False)`
# and `self.freqs`-equivalent does not exist here -- that is llama.py's.
# ---------------------------------------------------------------------------

# :42 def __init__(self, syms, maxlen, layers, embed_dim, num_heads, ff_dim)
def tf_transformer_init(syms: U32, maxlen: U32, layers: U32, embed_dim: U32, num_heads: U32, ff_dim: U32) -> D.Refused:
  D.refuse("extra/models/transformer.py:42 Transformer.__init__ -- FIRST MISSING SYMBOL TransformerBlock (:45), whose attn is scaled_dot_product_attention")

# :48 def forward(self, x)
def tf_transformer_forward(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/transformer.py:48 Transformer.forward -- FIRST MISSING SYMBOL Tensor.eye (:51)")

# ---------------------------------------------------------------------------
# There is no `if __name__ == "__main__":` in transformer.py. `main` below is
# this file and nothing else, and it prints the TWO rows that are answers rather
# than the census -- the census belongs in the report.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, tf_block_init(512, 8, 2048, False{}, 0.1))
    srow("transformer_refused_at", tf_at(a))
    row("transformer_attention_exists", False{})