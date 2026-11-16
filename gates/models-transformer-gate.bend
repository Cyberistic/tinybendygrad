# gates/models-transformer-gate.bend -- the gate driver for `tinybendygrad/extra/models/transformer.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/extra/models/transformer.bend as P

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

def tf_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# :3-39 TransformerBlock. `num_heads` (:7), `head_size = embed_dim // num_heads`
# (:8) and `prenorm`/`act`/`dropout` (:9-10) are the constructor's body, and
# `NN.nn_len`/`U32.div` cover the integer half. The SEVEN weight tuples (:12-22)
# are the first thing this file cannot build, and `rd_scaled_uniform` is why they
# are NOT the first thing.

# :4  def __init__(self, embed_dim, num_heads, ff_dim, prenorm=False,
#                  act=lambda x: x.relu(), dropout=0.1)
def tf_block_init(embed_dim: U32, num_heads: U32, ff_dim: U32, prenorm: Bool, dropout: F32) -> D.Refused:
  D.refuse("extra/models/transformer.py:4 TransformerBlock.__init__ -- reached :12 Tensor.scaled_uniform (mixin/rand.bend:937 symbol=rd_scaled_uniform EXISTS); BLOCKED AT :27 scaled_dot_product_attention via attn")

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

# :41-61 Transformer. `self.embed` (:44) is `Tensor.scaled_uniform(...).is_param_(False)`
# and `self.freqs`-equivalent does not exist here -- that is llama.py's.

# :42 def __init__(self, syms, maxlen, layers, embed_dim, num_heads, ff_dim)
def tf_transformer_init(syms: U32, maxlen: U32, layers: U32, embed_dim: U32, num_heads: U32, ff_dim: U32) -> D.Refused:
  D.refuse("extra/models/transformer.py:42 Transformer.__init__ -- FIRST MISSING SYMBOL TransformerBlock (:45), whose attn is scaled_dot_product_attention")

# :48 def forward(self, x)
def tf_transformer_forward(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/transformer.py:48 Transformer.forward -- FIRST MISSING SYMBOL Tensor.eye (:51)")

# There is no `if __name__ == "__main__":` in transformer.py. `main` below is
# this file and nothing else, and it prints the TWO rows that are answers rather
# than the census -- the census belongs in the report.

def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, tf_block_init(512, 8, 2048, False{}, 0.1))
    srow("transformer_refused_at", tf_at(a))
    row("transformer_attention_exists", False{})
