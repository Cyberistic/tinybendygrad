import Base
import ./../../tensor.bend as T
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../dtype.bend as DT
import ./../../nn/__init__.bend as NN
import ./../../nn/layers.bend as LN
import ./../../nn/state.bend as ST
import ./../../mixin/op.bend as MO
import ./../../mixin/movement.bend as MX
import ./../../mixin/creation.bend as CR
import ./../../mixin/rand.bend as RD
import ./transformer.bend as TR
import ./../datasets/__init__.bend as D

# ===========================================================================
# STUB -- 1:1 PATH MIRROR of extra/models/vit.py (73 LOC). NOT YET PORTED.
#
# THE ONLY MODEL IN THIS DIRECTORY THAT DOES NOT BEGIN WITH A CONVOLUTION, AND
# THAT IS THE WHOLE OF ITS DISTINCTIVE BLOCKER. Every other file here names
# `nn.Conv2d` in its first constructor; `ViT.__init__` names `Tensor.uniform`,
# `Tensor.zeros` and `Tensor.ones` (upstream:8-11,16-17) -- all FOUR are built
# (`rd_uniform` mixin/rand.bend:921 symbol=rd_uniform, `cr_zeros` mixin/creation.bend:518 symbol=cr_zeros,
# `cr_ones` mixin/creation.bend:559 symbol=cr_ones) -- and then names `TransformerBlock` at
# upstream:13.
#
# TODO(port): STOPPED AT `ViT.__init__` (extra/models/vit.py:6), at upstream:13
#       TransformerBlock(embed_dim=embed_dim, num_heads=num_heads,
#                        ff_dim=embed_dim*4, prenorm=True, act=lambda x: x.gelu())
#   `extra/models/transformer.py` IS PORTED AS A FILE -- `transformer.bend` is on
#   disk and 1:1 with upstream's 61 LOC -- but every def in it REFUSES, and its
#   own header (transformer.bend:19-27) names the single missing primitive:
#   `Tensor.scaled_dot_product_attention`. `transformer.bend:108` is
#   `tf_block_attn`, which refuses on it, and `mixin/rand.bend:87-90` carries
#   FOUR walls for its arms -- "GQA arm", "the matmul", "the causal mask", "the
#   attn_mask arm". So THIS FILE IS NOT BLOCKED ON A SIBLING THAT IS ABSENT. IT
#   IS BLOCKED ON A SIBLING THAT IS PRESENT AND REFUSING, WHICH IS A DIFFERENT
#   AND MORE USEFUL FACT: `tf_block_init` (transformer.bend:96) is the exact
#   address to go to, and its refusal carries the exact symbol.
#
#   THE SECOND BLOCKER, AND IT IS ONE UNBELIEVABLY SHORT LINE: upstream:29
#       x = x.layernorm().linear(*self.encoder_norm)
#   `Tensor.layernorm` does not exist. `nn/__init__.bend:230` names it as an
#   open wall -- "TODO(p3) mixin/op.py:1661 x.layernorm -- SIDE B, not built" --
#   and that line is STILL TRUE even though the `x.conv2d` (:231), `x.batchnorm`
#   (:229) and `x.linear` (:227) walls beside it stopped being true, because
#   `nn/layers.bend` and `nn/pool.bend` were written to close exactly those
#   three and nobody went back for layernorm. THE WALL LIST DECAYED AND NOTHING
#   NOTICED, WHICH IS THE POINT OF NAMING IT BY LINE INSTEAD OF BY "SIDE B".
#
# THE `-1` IN `x.reshape(shape=(x.shape[0], x.shape[1], -1))` (upstream:21) IS A
# REAL MISSING PRIMITIVE AND IT IS NOT A LAYER. `mxw_reshape`
# (mixin/movement.bend:1431) takes an EXPLICIT `List<&2, U32>`; it does not infer
# an axis. `nn/pool.bend:322-324` states the same boundary for its own `flatten`
# ("`-1` is NOT spelled because no def here infers an axis (that is
# `Tensor.reshape`'s `get_shape`, and the port writes its targets out)"). So
# :21 needs a `get_shape`/`prod` inference the port does not have, and :30's
# `x[:, 0]` needs a SLICE, which `rd_slice` (mixin/rand.bend:476 symbol=rd_slice) is not.
#
# `Tensor.gelu` is named twice -- `act=lambda x: x.gelu()` at :14 and nothing
# else in this file. Plain `gelu` is NOT a def: `mixin/elementwise.bend:1217`
# is `ew_quick_gelu`, using the `1.702` constant (`ew_k.quick_gelu` :774), and
# `elementwise.bend:43` lists `erf` among the operations this tree lacks.
#
# `np.load` (upstream:40) AND `Tensor.assign` (upstream:45-71, TWENTY-SEVEN
# CALLS) ARE THE LOADER. `pool.bend:408` names the second: "`Tensor.assign` --
# nn/__init__.py:56 `self.running_mean.assign(...)`
# divergence outright ("Python's `is_param_` mutates in place; this returns a
# new [tensor]"). So `ViT` cannot load a single one of its parameters, which is
# worth saying plainly: a ViT whose weights cannot be written is a ViT that can
# only ever produce its own random initialisation.
#
# EVERY DEF BELOW REFUSES, AND THE RETURN TYPE IS `D.Refused`, NOT A TENSOR. A
# stub that returned a zero Tensor would be indistinguishable from a layer whose
# weights happen to be zero. `refuse`/`Refused` are DECLARED ONCE at
# `extra/datasets/__init__.bend:40-46` and imported as `D`. Each message names
# the upstream `path:line` of the FIRST MISSING SYMBOL.
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def vt_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :6-17 ViT.__init__. FOUR of the five lines build tensors that EXIST; the fifth
# is the one that refuses.
# ---------------------------------------------------------------------------

# :7  def __init__(self, layers=12, embed_dim=192, num_heads=3)
def vt_vit_init(layers: U32, embed_dim: U32, num_heads: U32) -> D.Refused:
  D.refuse("extra/models/vit.py:7 ViT.__init__ -- FIRST MISSING SYMBOL TransformerBlock at :13, which REFUSES on Tensor.scaled_dot_product_attention (transformer.bend:108; walls at mixin/rand.bend:87-90)")

# :8  self.embedding = (Tensor.uniform(embed_dim, 3, 16, 16), Tensor.zeros(embed_dim))
def vt_embedding(embed_dim: U32) -> D.Refused:
  D.refuse("extra/models/vit.py:8 ViT.embedding -- rd_uniform (mixin/rand.bend:921) and cr_zeros (mixin/creation.bend:518) EXIST but both take an O.Arena, so this is the WEIGHT-STORE question, not the uniform question")

# :10 self.cls = Tensor.ones(1, 1, embed_dim)  :11 self.pos_embedding = Tensor.ones(1, 197, embed_dim)
def vt_pos_embedding() -> D.Refused:
  D.refuse("extra/models/vit.py:11 ViT.pos_embedding -- cr_ones (mixin/creation.bend:559) EXISTS; blocked by the WEIGHT STORE and by Tensor.assign at :53")

# :13 TransformerBlock(embed_dim=embed_dim, num_heads=num_heads, ff_dim=embed_dim*4,
#                       prenorm=True, act=lambda x: x.gelu())
def vt_transformer_block(layers: U32, embed_dim: U32, num_heads: U32) -> D.Refused:
  D.refuse("extra/models/vit.py:13 ViT.__init__ -- TransformerBlock REFUSES: tf_block_init (transformer.bend:96) is blocked on Tensor.scaled_dot_product_attention")

# :14 act=lambda x: x.gelu()
def vt_act_gelu(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:14 ViT.__init__ act -- MISSING Tensor.gelu; only ew_quick_gelu (mixin/elementwise.bend:1229) exists, with the 1.702 constant, and plain gelu needs erf (elementwise.bend:43)")

# :16 self.encoder_norm = (Tensor.uniform(embed_dim), Tensor.zeros(embed_dim))
# :17 self.head = (Tensor.uniform(embed_dim, 1000), Tensor.zeros(1000))
def vt_encoder_norm(embed_dim: U32) -> D.Refused:
  D.refuse("extra/models/vit.py:16 ViT.encoder_norm -- rd_uniform/cr_zeros EXIST; blocked by Tensor.layernorm at :29")

# ---------------------------------------------------------------------------
# :19-22 patch_embed. THE FIRST CONVOLUTION IN THE FILE, AND IT IS BUILT.
# ---------------------------------------------------------------------------

# :19 def patch_embed(self, x)
def vt_patch_embed(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:19 ViT.patch_embed -- Tensor.conv2d EXISTS (nn_conv2d, nn/layers.bend:937); blocked at :21 by reshape's MISSING -1 AXIS INFERENCE")

# :21 x = x.reshape(shape=(x.shape[0], x.shape[1], -1)).permute(order=(0,2,1))
def vt_patch_reshape(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:21 ViT.patch_embed -- MISSING -1 INFERENCE: mxw_reshape (mixin/movement.bend:1434) takes an explicit List<&2, U32> and does not infer an axis (nn/pool.bend:322 states the same boundary)")

# :21 ... .permute(order=(0,2,1))
def vt_patch_permute(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:21 ViT.patch_embed -- mxw_permute (mixin/movement.bend:1452) EXISTS; blocked by the reshape at the same line")

# ---------------------------------------------------------------------------
# :24-30 forward. FIVE lines, THREE of them blocked by symbols this file's own
# census already names.
# ---------------------------------------------------------------------------

# :24 def forward(self, x)
def vt_forward(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:24 ViT.forward -- FIRST MISSING SYMBOL Tensor.cat at :27")

# :25 ce = self.cls.add(Tensor.zeros(x.shape[0],1,1))
def vt_cls_token(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:25 ViT.forward -- tn_add (tensor.bend:685) and cr_zeros (mixin/creation.bend:518) EXIST; this line is BLOCKED ONLY BY THE WEIGHT STORE, not by a primitive")

# :27 x = ce.cat(pe, dim=1)
def vt_cat(+x: T.Tensor, +pe: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:27 ViT.forward -- MISSING Tensor.cat; mx_cat (mixin/movement.bend) concatenates LISTS of U32 for shape arithmetic and is not this")

# :28 x = x.add(self.pos_embedding).sequential(self.tbs)
def vt_sequential(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:28 ViT.forward -- MISSING Tensor.sequential; grep -rniE '^def .*sequential' --include='*.bend' tinybendygrad/ returns 0")

# :29 x = x.layernorm().linear(*self.encoder_norm)
def vt_layernorm(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:29 ViT.forward -- MISSING Tensor.layernorm, named as an open wall at nn/__init__.bend:230 (mixin/op.py:1644)")

# :30 return x[:, 0].linear(*self.head)
def vt_slice(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:30 ViT.forward -- MISSING SLICE x[:, 0]; rd_slice (mixin/rand.bend:477) exists but is a 1-D shrink, not an index read")

# ---------------------------------------------------------------------------
# :32-73 load_from_pretrained. TWENTY-SEVEN `assign` calls and one `np.load`.
# ---------------------------------------------------------------------------

# :32 def load_from_pretrained(m)   -- NOTE it is NOT `self`; upstream takes the
# model as a parameter and it is the only def in this file that does.
def vt_load_pretrained(embed_dim: U32) -> D.Refused:
  D.refuse("extra/models/vit.py:32 ViT.load_from_pretrained -- FIRST MISSING SYMBOL np.load at :40; the port has no ndarray, and helpers.bend:3194 already records the fetch seam as unported")

# :45-55 m.embedding[0].assign(...) -- one def for the block, because the
# blocker is ONE symbol repeated twenty-seven times and naming it twenty-seven
# times would be a census of nothing.
def vt_assign_block(+m: T.Tensor, +v: T.Tensor) -> D.Refused:
  D.refuse("extra/models/vit.py:45-71 ViT.load_from_pretrained -- MISSING Tensor.assign (27 call sites); pool.bend:408 and tensor.bend:2539 name the immutability divergence")

# :34 if m.embed_dim == 192 ... :38-39 raise Exception("no pretrained weights")
def vt_url(embed_dim: U32) -> D.Refused:
  D.refuse("extra/models/vit.py:34 ViT.load_from_pretrained -- the URL choice is PURE DATA and could be a record; it is refused here only because the fetch at :40 is missing, and saying so is cheaper than a def nobody can call")

# ---------------------------------------------------------------------------
# THERE IS NO `if __name__ == \"__main__\":` IN THIS FILE -- upstream ends at
# :73 inside `load_from_pretrained`. `main` below IS the port's own entry and it
# prints only what this file declares; it invents no census, because a 1:1
# mirror that emits rows upstream does not emit is not a mirror.
# ---------------------------------------------------------------------------
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