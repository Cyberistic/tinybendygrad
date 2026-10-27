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
import ./../../mixin/elementwise.bend as E
import ./../datasets/__init__.bend as D

# ===========================================================================
# STUB -- 1:1 PATH MIRROR of extra/models/unet.py (262 LOC). NOT YET PORTED.
#
# THE LARGEST FILE IN THIS DIRECTORY AFTER inception.py, AND THE ONLY ONE THAT
# IS NOT A VISION CLASSIFIER: it is a Stable-Diffusion UNet, so it brings
# three things no other model here names -- an ATTENTION (`Tensor.scaled_dot_
# product_attention`), a CONDITIONAL EMBEDDING (`timestep_embedding`, upstream:10,
# built from `Tensor.arange`/`cos`/`sin`/`cat`), and a DEVICE CAPABILITY QUERY
# (`Device[Device.DEFAULT].renderer.supported_dtypes()`, :15 and :240).
#
# TODO(port): STOPPED AT `timestep_embedding` (extra/models/unet.py:10), at
# upstream:12
#       freqs = (-math.log(max_period) * Tensor.arange(half) / half).exp()
#   `Tensor.arange` is MISSING. `grep -rnE '^def (rd|cr)_[a-z_]*arange\('
#   --include='*.bend' tinybendygrad/` returns 0; the nearest defs are
#   `cr_full` (mixin/creation.bend:489 symbol=cr_full) and `mo_range`/`mx_range` (nn/layers.bend
#   :110), and those answer a RANGE OF INDICES for a permute order, not a TENSOR.
#   `Tensor.exp` IS built (`ew_exp`, mixin/elementwise.bend:1312 symbol=ew_exp), so :12 is
#   blocked by its SECOND half only -- and the sentence above says which.
#
#   THE HEADLINE, WHICH IS FARTHER UP AND WORTH NAMING FIRST: upstream:7 binds
#       attention = Tensor.scaled_dot_product_attention
#   and that symbol is MISSING. `extra/models/transformer.bend:19-27` reaches the
#   same wall and `mixin/rand.bend:87-90` carries FOUR arms of it -- "GQA arm",
#   "the matmul", "the causal mask", "the attn_mask arm", each "BLOCKED: needs".
#   SO UNET AND TRANSFORMER SHARE ONE BLOCKER, AND IT IS THE SAME ONE.
#
# THE OTHER TWO THAT NO COUNT WOULD REVEAL, BECAUSE THEY ARE ONE-LINE CALLS TO
# FAMILIAR NAMES:
#   `Tensor.cat`   MISSING. :14 builds the embedding with it, and so does
#                  `CrossAttention` (:57) and `UNetModel.__call__` (:259).
#   `Tensor.cos`   MISSING. `tn_sin` IS built (tensor.bend:423); there is no
#                  `cos` ENTRY anywhere -- `grep -rnE '^def (tn|ew)_cos\('
#                  --include='*.bend' tinybendygrad/` returns 0. That asymmetry is
#                  worth recording, because `sin` existing makes `cos` look like a
#                  typo rather than a gap.
#   `Tensor.chunk` MISSING (:68). `Tensor.unsqueeze` MISSING (:13).
#   `Tensor.layernorm` MISSING (:87,:88,:89) -- nn/__init__.bend:230.
#   `GroupNorm` MISSING (:20,:29,:105,:227). `pool_bn` (nn/pool.bend:382 symbol=pool_bn) IS
#   BUILT, but it is BatchNorm's decomposition: mean/variance over CHANNELS with
#   a learned affine. GroupNorm's `num_groups` split is a different reduction
#   and `nn/__init__.bend` holds no class for it.
#   `Device[...].renderer.supported_dtypes()` MISSING (:15,:240). There is no
#   such query in `runtime/`; `dtype.bend` carries dtypes and `uop/ops.bend`
#   carries the op, but "what can THIS device do" is a runtime fact with no
#   def.
#
# WHAT IS ALREADY HERE IS WORTH SAYING TOO, BECAUSE IT REMOVES THE OBVIOUS
# GUESS: `Tensor.silu` IS built (`ew_silu`, mixin/elementwise.bend:1219 symbol=ew_silu, which is
# `ew_swish` at :1208) and this file names it FIVE times (:21,:25,:27,:229,:240).
# `Tensor.expand` IS built (`cr_expand`, mixin/creation.bend:343 symbol=cr_expand) and :137 needs
# it. `Tensor.conv2d` (`nn_conv2d`, nn/layers.bend:937 symbol=nn_conv2d) and `Tensor.linear`
# (`nn_linear`, :427) EXIST. So this file is not far; it is far in FOUR PLACES
# AT ONCE, which is the shape a diffusion UNet has.
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

def un_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :6-7 THE MODULE-LEVEL ALIAS BLOCK. "allow for monkeypatching" upstream. It is
# restated as three refusals because all three NAMES are absent and a reader
# deserves to see which.
# ---------------------------------------------------------------------------

# :6 Linear, Conv2d, GroupNorm, LayerNorm = nn.Linear, nn.Conv2d, nn.GroupNorm, nn.LayerNorm
def un_alias_nn() -> D.Refused:
  D.refuse("extra/models/unet.py:6 module alias -- MISSING nn.GroupNorm and nn.LayerNorm CLASSES; nn/__init__.bend has 17 defs and ZERO classes, while the OPS nn_linear (nn/layers.bend:427) and nn_conv2d (:756) are built")

# :7 attention, gelu, mixed_precision_dtype = Tensor.scaled_dot_product_attention, ...
def un_alias_attention() -> D.Refused:
  D.refuse("extra/models/unet.py:7 module alias -- MISSING Tensor.scaled_dot_product_attention; four arms walled at mixin/rand.bend:87-90, and transformer.bend:19-27 reaches the same one")

def un_alias_gelu() -> D.Refused:
  D.refuse("extra/models/unet.py:7 module alias -- MISSING Tensor.gelu; only ew_quick_gelu (mixin/elementwise.bend:1217) exists, with the 1.702 constant, and plain gelu needs erf (elementwise.bend:43)")

# `dtypes.float16` EXISTS and is the third name on that line, which is why the
# refusal above names two of three and not "the alias line". THE SPELLING IS
# `S.half()`, not `dtypes.float16` -- dtype.bend:53 records the rename:
# "`spec.bend`'s own heads (`half`, `bfloat16`, `single`, `double`) are tinyspec's".
def un_alias_dtype() -> S.Dt: S.half()

# ---------------------------------------------------------------------------
# :10-15 timestep_embedding.
# ---------------------------------------------------------------------------

# :10 def timestep_embedding(timesteps:Tensor, dim:int, max_period=10000)
def un_timestep_embedding(+timesteps: T.Tensor, dim: U32, max_period: F32) -> D.Refused:
  D.refuse("extra/models/unet.py:10 timestep_embedding -- FIRST MISSING SYMBOL Tensor.arange at :12")

# :12 the arange line, alone, because it is the file's first missing primitive.
def un_arange(half: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:12 timestep_embedding -- MISSING Tensor.arange; mo_range/mx_range (nn/layers.bend:110) answer a permute order, not a Tensor, and cr_full (mixin/creation.bend:417) is a fill")

# :13 args = timesteps.unsqueeze(1) * freqs.unsqueeze(0)
def unsqueeze_axis1(+t: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet.py:13 timestep_embedding -- MISSING Tensor.unsqueeze; and UNDERSIZED DIMS are NOT WRITABLE, so even a broadcast is not this (nn/layers.bend:30-40 measures the same boundary for _broadcasted)")

# :14 out = Tensor.cat(args.cos(), args.sin(), dim=-1)
def un_emb_cat(+a: T.Tensor, +b: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet.py:14 timestep_embedding -- MISSING Tensor.cat AND Tensor.cos; tn_sin IS built (tensor.bend:423) and there is no cos entry anywhere, so the asymmetry is real and not a typo")

# :15 out.cast(...) if mixed_precision_dtype in Device[...].renderer.supported_dtypes() else out
def un_supported_dtypes() -> D.Refused:
  D.refuse("extra/models/unet.py:15 timestep_embedding -- MISSING Device[Device.DEFAULT].renderer.supported_dtypes(); it is a RUNTIME CAPABILITY QUERY and runtime/ has no def that answers it")

# ---------------------------------------------------------------------------
# :17-41 ResBlock.
# ---------------------------------------------------------------------------

# :18 def __init__(self, channels, emb_channels, out_channels, num_groups=32)
def un_resblock_init(channels: U32, emb_channels: U32, out_channels: U32,
  num_groups: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:18 ResBlock.__init__ -- FIRST MISSING SYMBOL nn.GroupNorm at :20; Tensor.silu at :21 (ew_silu, mixin/elementwise.bend:1209) and nn.Conv2d at :22 (nn_conv2d, nn/layers.bend:756) are built")

# :19-22 self.in_layers
def un_resblock_in_layers(channels: U32, out_channels: U32, num_groups: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:19 ResBlock.in_layers -- MISSING nn.GroupNorm; this is a per-GROUP reduction and pool_bn (nn/pool.bend:381) is a per-CHANNEL one, so the built norm is not a parameter away from this")

# :24-27 self.emb_layers = [Tensor.silu, Linear(emb_channels, out_channels)]
def un_resblock_emb_layers(emb_channels: U32, out_channels: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:24 ResBlock.emb_layers -- Tensor.silu and the nn_linear OP (nn/layers.bend:427) are BOTH built; blocked by x.sequential at :38")

# :28-33 self.out_layers
def un_resblock_out_layers(out_channels: U32, num_groups: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:28 ResBlock.out_layers -- MISSING nn.GroupNorm at :29, same reason as :19")

# :34 self.skip_connection = Conv2d(channels, out_channels, 1) if channels != out_channels else (lambda x: x)
def un_resblock_skip(channels: U32, out_channels: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:34 ResBlock.skip_connection -- nn_conv2d EXISTS and the `if` is a Bool over two U32s, which is total; blocked only by this file having no layer STORE to put the conv in")

# :36 def __call__(self, x:Tensor, emb:Tensor) -> Tensor
def un_resblock_call(+x: T.Tensor, +emb: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet.py:36 ResBlock.__call__ -- FIRST MISSING SYMBOL x.sequential at :37; grep -rniE '^def .*sequential' --include='*.bend' tinybendygrad/ returns 0")

# :39 h = h + emb_out.reshape(*emb_out.shape, 1, 1)
def un_resblock_add(+h: T.Tensor, +emb_out: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet.py:39 ResBlock.__call__ -- tn_add (tensor.bend:680) and mxw_reshape (mixin/movement.bend:1431) are BOTH built and the fold answers the broadcast (uop/fold.bend:999); blocked only by x.sequential at :37")

# ---------------------------------------------------------------------------
# :43-59 CrossAttention.
# ---------------------------------------------------------------------------

# :44 def __init__(self, query_dim, ctx_dim, n_heads, d_head)
def un_xattn_init(query_dim: U32, ctx_dim: U32, n_heads: U32, d_head: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:44 CrossAttention.__init__ -- FIRST MISSING SYMBOL bias=False at :45: nn_linear (nn/layers.bend:427) takes bias as a Maybe<&2, T.Tensor> and None{} IS `bias=False`, so the OP is fine; what is missing is the layer STORE that nn.Linear.__init__ would have created")

# :50 self.attn = attention
def un_xattn_attn() -> D.Refused:
  D.refuse("extra/models/unet.py:50 CrossAttention.attn -- MISSING Tensor.scaled_dot_product_attention; this is the same blocker as extra/models/unet.py:7 and transformer.bend:108")

# :53 def __call__(self, x:Tensor, ctx:Optional[Tensor]=None) -> Tensor
def un_xattn_call(+x: T.Tensor, ctx: Maybe<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/unet.py:53 CrossAttention.__call__ -- FIRST MISSING SYMBOL self.attn(q, k, v) at :57, i.e. Tensor.scaled_dot_product_attention")

# :56 ... .reshape(x.shape[0], -1, self.num_heads, self.head_size).transpose(1, 2)
def un_xattn_head_split() -> D.Refused:
  D.refuse("extra/models/unet.py:56 CrossAttention.__call__ -- MISSING -1 INFERENCE; mxw_reshape (mixin/movement.bend:1431) takes an explicit List<&2, U32> and does not infer an axis (nn/pool.bend:322 states the same boundary)")

# ---------------------------------------------------------------------------
# :61-80 GEGLU and FeedForward.
# ---------------------------------------------------------------------------

# :62 def __init__(self, dim_in, dim_out)
def un_geglu_init(dim_in: U32, dim_out: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:62 GEGLU.__init__ -- the nn_linear OP EXISTS; blocked by the layer STORE, and by Tensor.gelu at :64 (see un_alias_gelu)")

# :67 def __call__(self, x:Tensor) -> Tensor
def un_geglu_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet.py:67 GEGLU.__call__ -- FIRST MISSING SYMBOL Tensor.chunk at :68; x, gate = self.proj(x).chunk(2, dim=-1)")

def un_chunk_last(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet.py:68 GEGLU.__call__ -- MISSING Tensor.chunk; no def named chunk( exists in tinybendygrad")

# :71 def __init__(self, dim, mult=4)
def un_ff_init(dim: U32, mult: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:71 FeedForward.__init__ -- blocked by GEGLU.__init__ at :62")

# :79 def __call__(self, x:Tensor) -> Tensor
def un_ff_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet.py:79 FeedForward.__call__ -- FIRST MISSING SYMBOL x.sequential at :80")

# ---------------------------------------------------------------------------
# :82-95 BasicTransformerBlock. THREE LayerNorms AND TWO ATTENTIONS.
# ---------------------------------------------------------------------------

# :83 def __init__(self, dim, ctx_dim, n_heads, d_head)
def un_btb_init(dim: U32, ctx_dim: U32, n_heads: U32, d_head: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:83 BasicTransformerBlock.__init__ -- FIRST MISSING SYMBOL CrossAttention at :84, i.e. Tensor.scaled_dot_product_attention")

# :87-89 self.norm1 = LayerNorm(dim)  self.norm2 = LayerNorm(dim)  self.norm3 = LayerNorm(dim)
def un_btb_norms(dim: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:87 BasicTransformerBlock.norm1 -- MISSING Tensor.layernorm, named as an open wall at nn/__init__.bend:230 (mixin/op.py:1644)")

# :91 def __call__(self, x:Tensor, ctx:Optional[Tensor]=None) -> Tensor
def un_btb_call(+x: T.Tensor, ctx: Maybe<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/unet.py:91 BasicTransformerBlock.__call__ -- FIRST MISSING SYMBOL Tensor.layernorm at :92, and Tensor.scaled_dot_product_attention behind it")

# ---------------------------------------------------------------------------
# :98-122 SpatialTransformer.
# ---------------------------------------------------------------------------

# :99-100 def __init__(self, channels, n_heads, d_head, ctx_dim, use_linear,
#                       depth=1, norm_eps=1e-5)
def un_sp_init(channels: U32, n_heads: U32, d_head: U32, use_linear: Bool, depth: U32,
  norm_eps: F32) -> D.Refused:
  D.refuse("extra/models/unet.py:99 SpatialTransformer.__init__ -- FIRST MISSING SYMBOL nn.GroupNorm at :105 (nn/__init__.bend holds no class for it, and pool_bn is a per-CHANNEL norm, not a per-GROUP one)")

# :112 def __call__(self, x:Tensor, ctx:Optional[Tensor]=None) -> Tensor
def un_sp_call(+x: T.Tensor, ctx: Maybe<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/unet.py:112 SpatialTransformer.__call__ -- FIRST MISSING SYMBOL Tensor.permute at :116 (mxw_permute, mixin/movement.bend:1449, EXISTS) reached only after nn.GroupNorm at :115, which is MISSING")

# ---------------------------------------------------------------------------
# :124-138 Downsample and Upsample. THE TWO SHORTEST CLASSES IN THE FILE, AND
# THE ONLY ONES WHOSE BODY IS ONE BUILT OP.
# ---------------------------------------------------------------------------

# :125 def __init__(self, channels)
def un_downsample_init(channels: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:125 Downsample.__init__ -- nn_conv2d (nn/layers.bend:756) EXISTS and takes stride; blocked only by the layer STORE")

# :128 def __call__(self, x:Tensor) -> Tensor
def un_downsample_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet.py:128 Downsample.__call__ -- this body is ONE CALL to an EXISTING op; it is the closest this file comes to working and it is blocked by the store, not by a primitive")

# :136-137 bs,c,py,px = x.shape ; z = x.reshape(...).expand(...).reshape(...)
def un_upsample_expand(bs: U32, c: U32, py: U32, px: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:137 Upsample.__call__ -- cr_expand (mixin/creation.bend:271) and mxw_reshape (mixin/movement.bend:1431) are BOTH built and every dim here is an explicit U32; this is the nearest-miss in the file")

# :138 return self.conv(z)
def un_upsample_call(+z: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet.py:138 Upsample.__call__ -- nn_conv2d EXISTS; blocked by the layer STORE")

# ---------------------------------------------------------------------------
# :141-262 UNetModel.
# ---------------------------------------------------------------------------

# :142-144 def __init__(self, adm_in_ch, in_ch, out_ch, model_ch,
#                       attention_resolutions, num_res_blocks, channel_mult,
#                       transformer_depth, ctx_dim, use_linear=False,
#                       d_head=None, n_heads=None, num_groups=32, st_norm_eps=1e-5)
def un_unet_init(adm_in_ch: Maybe<&2, U32>, in_ch: U32, out_ch: U32, model_ch: U32,
  num_res_blocks: U32, use_linear: Bool, d_head: Maybe<&2, U32>,
  n_heads: Maybe<&2, U32>, num_groups: U32, st_norm_eps: F32) -> D.Refused:
  D.refuse("extra/models/unet.py:142 UNetModel.__init__ -- FIRST MISSING SYMBOL ResBlock at :184, i.e. nn.GroupNorm at unet.py:20")

# :159-164 self.time_embed = [Linear(model_ch, time_embed_dim), Tensor.silu, Linear(...)]
def un_time_embed(model_ch: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:160 UNetModel.time_embed -- nn_linear and ew_silu (mixin/elementwise.bend:1209) are BOTH built; blocked by x.sequential at :234")

# :175-177 self.input_blocks
def un_input_blocks(model_ch: U32, in_ch: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:175 UNetModel.input_blocks -- nn_conv2d (nn/layers.bend:756) EXISTS; blocked by the layer STORE")

# :202-206 self.middle_block
def un_middle_block(model_ch: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:202 UNetModel.middle_block -- FIRST MISSING SYMBOL ResBlock at :203, i.e. nn.GroupNorm at unet.py:20")

# :208-224 self.output_blocks
def un_output_blocks(model_ch: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:208 UNetModel.output_blocks -- FIRST MISSING SYMBOL ResBlock at :213, i.e. nn.GroupNorm at unet.py:20")

# :226-230 self.out = [GroupNorm(num_groups, ch), Tensor.silu, Conv2d(model_ch, out_ch, 3, padding=1)]
def un_out_layers(model_ch: U32, out_ch: U32, num_groups: U32) -> D.Refused:
  D.refuse("extra/models/unet.py:226 UNetModel.out -- MISSING nn.GroupNorm at :227")

# :232 def __call__(self, x, tms, ctx, y=None)
def un_unet_call(+x: T.Tensor, +tms: T.Tensor, +ctx: T.Tensor,
  y: Maybe<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/unet.py:232 UNetModel.__call__ -- FIRST MISSING SYMBOL timestep_embedding at :233, which is Tensor.arange at :12")

# :240 if mixed_precision_dtype in Device[Device.DEFAULT].renderer.supported_dtypes():
def un_mixed_precision() -> D.Refused:
  D.refuse("extra/models/unet.py:240 UNetModel.__call__ -- MISSING Device[...].renderer.supported_dtypes(); ew_cast (mixin/elementwise.bend:180) is built, so the cast itself is fine and only the CAPABILITY QUERY is absent")

# :259 x = x.cat(saved_inputs.pop(), dim=1)
def un_unet_cat(+x: T.Tensor, +skip: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet.py:259 UNetModel.__call__ -- MISSING Tensor.cat; mx_cat (mixin/movement.bend) concatenates LISTS of U32 for shape arithmetic and is not this")

# :262 return x.sequential(self.out)
def un_unet_out(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet.py:262 UNetModel.__call__ -- FIRST MISSING SYMBOL x.sequential")

# ---------------------------------------------------------------------------
# THERE IS NO `if __name__ == \"__main__\":` IN THIS FILE -- upstream ends at
# :262. `main` below IS the port's own entry and it invents no census, because a
# 1:1 mirror that emits rows upstream does not emit is not a mirror.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, un_unet_init(None{}, 4, 4, 320, 2, False{}, None{}, None{}, 32, 1.0e-5))
    srow("unet_refused_at", un_at(a))
    row("unet_ported", False{})
    srow("unet_first_blocker_line", "extra/models/unet.py:12")
    srow("unet_first_blocker", "Tensor.arange")
    srow("unet_headline_blocker", "Tensor.scaled_dot_product_attention -- shared with transformer.bend and mixin/rand.bend:87-90")
    srow("unet_classes", "11")
    srow("unet_alias_dtype", "S.half() -- dtype.bend:53 renamed dtypes.float16")
    urow("unet_default_num_groups", 32)