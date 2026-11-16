# gates/models-vit-gate.bend -- the gate driver for `tinybendygrad/extra/models/vit.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/extra/models/vit.bend as P

import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/dtype.bend as DT
import ./../tinybendygrad/nn/__init__.bend as NN
import ./../tinybendygrad/nn/layers.bend as LN
import ./../tinybendygrad/nn/state.bend as ST
import ./../tinybendygrad/mixin/op.bend as MO
import ./../tinybendygrad/mixin/movement.bend as MX
import ./../tinybendygrad/mixin/creation.bend as CR
import ./../tinybendygrad/mixin/rand.bend as RD
import ./../tinybendygrad/extra/models/transformer.bend as TR
import ./../tinybendygrad/extra/datasets/__init__.bend as D
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def vt_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# :6-17 ViT.__init__. FOUR of the five lines build tensors that EXIST; the fifth
# is the one that refuses.

# :7  def __init__(self, layers=12, embed_dim=192, num_heads=3)
def vt_vit_init(layers: U32, embed_dim: U32, num_heads: U32) -> D.Refused:
  D.refuse("extra/models/vit.py:7 ViT.__init__ -- FIRST MISSING SYMBOL TransformerBlock at :13, which REFUSES on Tensor.scaled_dot_product_attention (transformer.bend:104 symbol=tf_block_attn; walls at THE PORT's `mixin/rand.bend` HEADER)")

# :8  self.embedding = (Tensor.uniform(embed_dim, 3, 16, 16), Tensor.zeros(embed_dim))
def vt_embedding(embed_dim: U32) -> D.Refused:
  D.refuse("extra/models/vit.py:8 ViT.embedding -- rd_uniform (mixin/rand.bend:918 symbol=rd_uniform) and cr_zeros (mixin/creation.bend:526 symbol=cr_zeros) EXIST but both take an O.Arena, so this is the WEIGHT-STORE question, not the uniform question")

# :10 self.cls = Tensor.ones(1, 1, embed_dim)  :11 self.pos_embedding = Tensor.ones(1, 197, embed_dim)
def vt_pos_embedding() -> D.Refused:
  D.refuse("extra/models/vit.py:11 ViT.pos_embedding -- cr_ones (mixin/creation.bend:567 symbol=cr_ones) EXISTS; blocked by the WEIGHT STORE and by Tensor.assign at :53")

# :13 TransformerBlock(embed_dim=embed_dim, num_heads=num_heads, ff_dim=embed_dim*4,
#                       prenorm=True, act=lambda x: x.gelu())
def vt_transformer_block(layers: U32, embed_dim: U32, num_heads: U32) -> D.Refused:
  D.refuse("extra/models/vit.py:13 ViT.__init__ -- TransformerBlock REFUSES: tf_block_init (transformer.bend:92 symbol=tf_block_init) is blocked on Tensor.scaled_dot_product_attention")

# :14 act=lambda x: x.gelu()
def vt_act_gelu(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:14 ViT.__init__ act -- MISSING Tensor.gelu; only ew_quick_gelu (mixin/elementwise.bend:1207 symbol=ew_quick_gelu) exists, with the 1.702 constant, and plain gelu needs erf (THE PORT's `mixin/elementwise.bend` HEADER)")

# :16 self.encoder_norm = (Tensor.uniform(embed_dim), Tensor.zeros(embed_dim))
# :17 self.head = (Tensor.uniform(embed_dim, 1000), Tensor.zeros(1000))
def vt_encoder_norm(embed_dim: U32) -> D.Refused:
  D.refuse("extra/models/vit.py:16 ViT.encoder_norm -- rd_uniform/cr_zeros EXIST; blocked by Tensor.layernorm at :29")

# :19-22 patch_embed. the first convolution in the file, and it is built.

# :19 def patch_embed(self, x)
def vt_patch_embed(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:19 ViT.patch_embed -- Tensor.conv2d EXISTS (nn_conv2d, nn/layers.bend:923 symbol=nn_conv2d); blocked at :21 by reshape's MISSING -1 AXIS INFERENCE")

# :21 x = x.reshape(shape=(x.shape[0], x.shape[1], -1)).permute(order=(0,2,1))
def vt_patch_reshape(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:21 ViT.patch_embed -- MISSING -1 INFERENCE: mxw_reshape (mixin/movement.bend:1417 symbol=mxw_reshape) takes an explicit List<&2, U32> and does not infer an axis (nn/pool.bend:317 symbol=pool_flatten states the same boundary)")

# :21 ... .permute(order=(0,2,1))
def vt_patch_permute(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:21 ViT.patch_embed -- mxw_permute (mixin/movement.bend:1435 symbol=mxw_permute) EXISTS; blocked by the reshape at the same line")

# :24-30 forward. FIVE lines, THREE of them blocked by symbols this file's own
# census already names.

# :24 def forward(self, x)
def vt_forward(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:24 ViT.forward -- FIRST MISSING SYMBOL Tensor.cat at :27")

# :25 ce = self.cls.add(Tensor.zeros(x.shape[0],1,1))
def vt_cls_token(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:25 ViT.forward -- tn_add (tensor.bend:678 symbol=tn_add) and cr_zeros (mixin/creation.bend:526 symbol=cr_zeros) EXIST; this line is BLOCKED ONLY BY THE WEIGHT STORE, not by a primitive")

# :27 x = ce.cat(pe, dim=1)
def vt_cat(+x: T.Tensor, +pe: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:27 ViT.forward -- MISSING Tensor.cat; mx_cat (mixin/movement.bend) concatenates LISTS of U32 for shape arithmetic and is not this")

# :28 x = x.add(self.pos_embedding).sequential(self.tbs)
def vt_sequential(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:28 ViT.forward -- MISSING Tensor.sequential; grep -rniE '^def .*sequential' --include='*.bend' tinybendygrad/ returns 0")

# :29 x = x.layernorm().linear(*self.encoder_norm)
def vt_layernorm(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:29 ViT.forward -- MISSING Tensor.layernorm, named as an open wall at THE PORT's `nn/__init__.bend` WALL BLOCK (mixin/op.py:1644)")

# :30 return x[:, 0].linear(*self.head)
def vt_slice(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:30 ViT.forward -- MISSING SLICE x[:, 0]; rd_slice (mixin/rand.bend:479 symbol=rd_slice) exists but is a 1-D shrink, not an index read")

# :32-73 load_from_pretrained. TWENTY-SEVEN `assign` calls and one `np.load`.

# :32 def load_from_pretrained(m)   -- NOTE it is NOT `self`; upstream takes the
# model as a parameter and it is the only def in this file that does.
def vt_load_pretrained(embed_dim: U32) -> D.Refused:
  D.refuse("extra/models/vit.py:32 ViT.load_from_pretrained -- FIRST MISSING SYMBOL np.load at :40; the port has no ndarray, and THE PORT's `helpers.bend` `NOT PORTED` BLOCK already records the fetch seam as unported")

# :45-55 m.embedding[0].assign(...) -- one def for the block, because the
# blocker is ONE symbol repeated twenty-seven times and naming it twenty-seven
# times would be a census of nothing.
def vt_assign_block(+m: T.Tensor, +v: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:45-71 ViT.load_from_pretrained -- MISSING Tensor.assign (27 call sites); pool.bend:405 symbol=pool_bn_running_stats and tensor.bend:2497 symbol=t_alu3 name the immutability divergence")

# :34 if m.embed_dim == 192 ... :38-39 raise Exception("no pretrained weights")
def vt_url(embed_dim: U32) -> D.Refused:
  D.refuse("extra/models/vit.py:34 ViT.load_from_pretrained -- the URL choice is PURE DATA and could be a record; it is refused here only because the fetch at :40 is missing, and saying so is cheaper than a def nobody can call")

# THERE IS NO `if __name__ == \"__main__\":` IN THIS FILE -- upstream ends at
# :73 inside `load_from_pretrained`. `main` below IS the port's own entry and it
# prints only what this file declares; it invents no census, because a 1:1
# mirror that emits rows upstream does not emit is not a mirror.

def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, vt_vit_init(12, 192, 3))
    srow("vit_refused_at", vt_at(a))
    row("vit_ported", False{})
    srow("vit_init_line", "extra/models/vit.py:7")
    srow("vit_blocker", "extra/models/transformer.py -- TransformerBlock refuses on Tensor.scaled_dot_product_attention")
    urow("vit_default_layers", 12)
    urow("vit_default_embed_dim", 192)
    urow("vit_default_num_heads", 3)
