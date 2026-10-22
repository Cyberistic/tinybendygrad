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
import ./../../mixin/elementwise.bend as E
import ./../datasets/__init__.bend as D

# ===========================================================================
# STUB -- 1:1 PATH MIRROR of extra/models/convnext.py (63 LOC). NOT YET PORTED.
#
# WHAT CHANGED SINCE `resnet.bend` WAS WRITTEN, AND THIS FILE IS THE EVIDENCE:
# `resnet.bend:21` still reads "nn.Conv2d, nn.BatchNorm2d AND nn.Linear ARE ALL
# MISSING", and `resnet.bend:35` cites `mixin/op.bend:1523` as "SIDE B IS THE
# EMPTY HALF". BOTH ARE NOW STALE. `tinybendygrad/nn/layers.bend` (941 lines)
# BUILT THE OPS:
#   `Tensor.conv2d`  nn/layers.bend:756 `nn_conv2d`   -- from the primitives,
#                        `mixin/op.bend`'s SIDE B never having been filled
#   `Tensor.linear`   nn/layers.bend:427 `nn_linear`
#   `Tensor.relu`     nn/layers.bend:262 `nn_relu` (a NAME onto `tn_relu`,
#                        tensor.bend:774, not a second copy)
# and `tinybendygrad/nn/pool.bend` built `Tensor.batchnorm` (pool.bend:381) and
# the pools. So the arithmetic a ConvNeXt block needs IS in the tree. What is
# still absent is every LAYER CLASS: `nn/__init__.bend` has 17 defs
# (`grep -cE '^def ' nn/__init__.bend` = 17) and all 17 are shape arithmetic --
# `nn_app nn_len nn_neg1 nn_i64_app nn_mt nn_mt_seq nn_half nn_prod nn_groups
# nn_k1 nn_pair.right nn_pair.left nn_pad.go nn_same nn_scale nn_bound nn_glorot`
# -- and ZERO classes. `layers.bend` supplied FUNCTIONS where upstream had
# METHODS; the CONSTRUCTORS that own weights and fill a state dict are the part
# nobody has written, for any model, in this tree.
#
# TODO(port): STOPPED AT `Block.__init__` (extra/models/convnext.py:5).
#   The FIRST line of that constructor (:7) is
#       self.dwconv = Conv2d(dim, dim, kernel_size=7, padding=3, groups=dim)
#   `Tensor.conv2d` is BUILT (`nn_conv2d`, nn/layers.bend:756, and it already
#   takes `groups` and a `Maybe<&2, List<&2, U32>>` padding, so both arguments
#   are expressible) -- but there is NO `nn.Conv2d` CLASS: nothing builds the
#   `(dim, dim, 7, 7)` weight, nothing gives the layer a name, and nothing makes
#   it a `get_state_dict` (nn/state.bend:318) node.
#   AND THE SECOND LINE IS A HARDER MISS: `:8 self.norm = LayerNorm(dim,
#   eps=1e-6)`. `Tensor.layernorm` does not exist. The port says so in its own
#   words at `nn/__init__.bend:230`: "TODO(p3) mixin/op.py:1644 x.layernorm --
#   SIDE B, not built", and that line is still true even though the conv2d and
#   linear lines beside it stopped being true.
#   SO THE HONEST FIRST BLOCKER IS THE CONSTRUCTOR, AND THE HONEST FIRST
#   *PRIMITIVE* BEHIND IT IS `Tensor.layernorm`.
#
# THE TWO SPELLINGS OF A VALUE, because upstream keeps them apart and this file
# must too: `Tensor.gelu` is named at :16 and `x.gelu()` inside the `act` is
# the same method. `mixin/elementwise.bend:1217` is `ew_quick_gelu`, which uses
# the `1.702` constant (`ew_k.quick_gelu`, :774). Plain `gelu` is NOT a def:
# elementwise.bend:43 lists `erf` among the operations this file does not have,
# and :758 records that the `0.044715` cubic is a CLOSE APPROXIMATION that
# "is wrong in the ninth" place. So :16 is REFUSED on the primitive rather than
# silently answered with the quick variant.
#
# `Tensor.sequential` (:14, :31, :32) is MISSING for every model in this
# directory. `grep -rniE '^def .*sequential' --include='*.bend' tinybendygrad/`
# returns 0, and the refusal below names the address rather than describing it.
#
# THE WEIGHT LOADER (:44-52) is the same seam every model in this directory
# stops at, and `resnet.bend:99-111` already measures it for `fetch`. Its extra
# member here is `Tensor.assign` at :51 -- `pool.bend:408` names the instrument
# ("`Tensor.assign` -- op.py:56-57 `self.running_mean.assign(...)`", and
# `tensor.bend:2539` states the divergence: "Python's `is_param_` mutates in
# place; this returns a new [tensor]"), so `mv.assign(...)` and `.realize()` are
# both refused for the same reason BatchNorm's running stats are.
#
# EVERY DEF BELOW REFUSES, AND THE RETURN TYPE IS `D.Refused`, NOT A TENSOR. A
# stub that returned a zero Tensor or an empty list would be indistinguishable
# from a layer whose weights happen to be zero. `refuse` and the `Refused` type
# are DECLARED ONCE at `extra/datasets/__init__.bend:40-46` and imported as `D`.
# Each message names the upstream `path:line` of the FIRST MISSING SYMBOL.
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

# the `Refused` accessor, in nn/state.bend:227's shape, so `main` can print the
# address the refusal carries rather than discarding it.
def cn_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :5-17 Block. The FOUR sublayers (:7,:8,:9,:10) are all named here so the
# distance is four symbols and not "the block".
# ---------------------------------------------------------------------------

# :6  def __init__(self, dim)
def cn_block_init(dim: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:6 Block.__init__ -- FIRST MISSING SYMBOL nn.Conv2d CLASS at :7 (the op nn_conv2d, nn/layers.bend:756, EXISTS); then Tensor.layernorm at :8 (nn/__init__.bend:230)")

# :7  self.dwconv = Conv2d(dim, dim, kernel_size=7, padding=3, groups=dim)
def cn_block_dwconv(dim: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:7 Block.dwconv -- needs the nn.Conv2d CLASS: nothing builds the (dim, dim, 7, 7) weight or the state-dict node")

# :8  self.norm = LayerNorm(dim, eps=1e-6)
def cn_block_norm(dim: U32, eps: F32) -> D.Refused:
  D.refuse("extra/models/convnext.py:8 Block.norm -- MISSING Tensor.layernorm, named as an open wall at nn/__init__.bend:230 (mixin/op.py:1644)")

# :9  self.pwconv1 = Linear(dim, 4 * dim)   :10  self.pwconv2 = Linear(4 * dim, dim)
def cn_block_pwconv1(dim: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:9 Block.pwconv1 -- needs the nn.Linear CLASS; the op nn_linear (nn/layers.bend:427) EXISTS")

def cn_block_pwconv2(dim: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:10 Block.pwconv2 -- needs the nn.Linear CLASS; the op nn_linear (nn/layers.bend:427) EXISTS")

# :11  self.gamma = Tensor.ones(dim)
def cn_block_gamma(dim: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:11 Block.gamma -- Tensor.ones IS cr_ones (mixin/creation.bend:487) but it takes an O.Arena and an S.Dt, so this is the WEIGHT-STORE question and not the ones question")

# :13 def __call__(self, x:Tensor)
def cn_block_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/convnext.py:13 Block.__call__ -- FIRST MISSING SYMBOL x.sequential at :14")

# the two lambdas at :15 and :16 are NAMED, not folded into the refusal, because
# :16's is where the missing `Tensor.gelu` lives.
# :15 lambda x: x.permute(0, 2, 3, 1)
def cn_permute_0221(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/convnext.py:15 Block.__call__ permute(0,2,3,1) -- mxw_permute (mixin/movement.bend:1449) EXISTS; blocked by Tensor.sequential at :14")

# :16 lambda x: (self.gamma * x).permute(0, 3, 1, 2)
def cn_permute_0312(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/convnext.py:16 Block.__call__ -- Tensor.gelu is MISSING; only ew_quick_gelu (mixin/elementwise.bend:1217) exists, using the 1.702 constant, and plain gelu needs erf (elementwise.bend:43)")

# ---------------------------------------------------------------------------
# :19-32 ConvNeXt.
# ---------------------------------------------------------------------------

# :20 def __init__(self, in_chans=3, num_classes=1000, depths=[3, 3, 9, 3],
#                   dims=[96, 192, 384, 768])
def cn_convnext_init(in_chans: U32, num_classes: U32, depth0: U32, depth1: U32,
  depth2: U32, depth3: U32, dim0: U32, dim1: U32, dim2: U32, dim3: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:20 ConvNeXt.__init__ -- FIRST MISSING SYMBOL nn.LayerNorm2d at :22")

# :21-24 self.downsample_layers
def cn_downsample(in_chans: U32, dim0: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:21 ConvNeXt.downsample_layers -- FIRST MISSING SYMBOL nn.LayerNorm2d at :22 (the class nn.Conv2d at :22 is available as an op only)")

# :25 self.stages -- the list of Block lists
def cn_stages(depth0: U32, depth1: U32, depth2: U32, depth3: U32, dim0: U32,
  dim1: U32, dim2: U32, dim3: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:25 ConvNeXt.stages -- blocked by Block.__init__ at :6, whose first missing symbol is the nn.Conv2d CLASS")

# :26 self.norm = LayerNorm(dims[-1])  :27 self.head = Linear(dims[-1], num_classes)
def cn_convnext_head(num_classes: U32, dim3: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:26 ConvNeXt.norm -- MISSING Tensor.layernorm (nn/__init__.bend:230)")

# :29 def __call__(self, x:Tensor)
def cn_convnext_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/convnext.py:29 ConvNeXt.__call__ -- FIRST MISSING SYMBOL Tensor.sequential at :31")

# :29 :32 x.mean([-2, -1]) -- the one call here whose op EXISTS. `mo_mean` is
# `mixin/op.bend:891`; it is named so the row is not mistaken for "all of
# ConvNeXt is absent".
def cn_mean_axes() -> D.Refused:
  D.refuse("extra/models/convnext.py:32 ConvNeXt.__call__ mean([-2,-1]) -- mo_mean (mixin/op.bend:891) EXISTS with U32 axes; Python's -2/-1 have no U32 image (nn/layers.bend:318 measures this)")

# ---------------------------------------------------------------------------
# :36-42 `versions` -- FIVE dicts of two lists each, and this is the one part of
# the file that is PURE DATA. The whole table is restated here so a reader does
# not have to open Python to learn that "xlarge" is 2048 wide.
# ---------------------------------------------------------------------------
def cn_versions_name(n: U32) -> String:
  match n:
    case 0: "tiny"
    case 1: "small"
    case 2: "base"
    case 3: "large"
    case _: "xlarge"

def cn_versions_depth(n: U32) -> U32:
  match n:
    case 0: 3
    case 1: 3
    case 2: 3
    case 3: 27
    case _: 27

def cn_versions_depth2(n: U32) -> U32:
  match n:
    case 0: 3
    case 1: 3
    case 2: 9
    case 3: 27
    case _: 27

def cn_versions_dim(n: U32) -> U32:
  match n:
    case 0: 96
    case 1: 96
    case 2: 128
    case 3: 192
    case _: 256

def cn_versions_dim2(n: U32) -> U32:
  match n:
    case 0: 192
    case 1: 192
    case 2: 256
    case 3: 384
    case _: 512

# ---------------------------------------------------------------------------
# :44-52 get_model.
# ---------------------------------------------------------------------------

# :44 def get_model(version, load_weights=False)
def cn_get_model(version: U32, load_weights: Bool) -> D.Refused:
  D.refuse("extra/models/convnext.py:44 get_model -- FIRST MISSING SYMBOL ConvNeXt(**versions[version]) at :45, whose first missing symbol is nn.LayerNorm2d")

# :48 weights = torch_load(fetch(...))['model']
def cn_get_model_fetch() -> D.Refused:
  D.refuse("extra/models/convnext.py:48 get_model -- MISSING fetch: helpers.bend:3191 records the whole HTTP seam as unported, and no def named fetch( exists")

# :50 mv = get_child(model, k)  :51 mv.assign(...).realize()
def cn_get_model_assign() -> D.Refused:
  D.refuse("extra/models/convnext.py:51 get_model -- MISSING Tensor.assign and Tensor.realize; pool.bend:408 and tensor.bend:2539 both name the immutability divergence")

# ---------------------------------------------------------------------------
# :54-63 `if __name__ == "__main__":`. `main` below IS this block and nothing
# else. There is deliberately no invented census printed here: a 1:1 mirror that
# emits rows upstream does not emit is not a mirror, and the census belongs in
# the report where a reader looks for it.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, cn_block_init(96))
    srow("convnext_refused_at", cn_at(a))
    row("convnext_ported", False{})
    srow("convnext_block_init_line", "extra/models/convnext.py:6")
    srow("convnext_versions_count", "5")
    urow("convnext_xlarge_dims_0", cn_versions_dim(4))
    urow("convnext_xlarge_depths_2", cn_versions_depth2(4))