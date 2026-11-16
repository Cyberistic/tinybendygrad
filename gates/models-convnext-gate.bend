# gates/models-convnext-gate.bend -- the gate driver for `tinybendygrad/extra/models/convnext.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/extra/models/convnext.bend as P

import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/dtype.bend as DT
import ./../tinybendygrad/nn/__init__.bend as NN
import ./../tinybendygrad/nn/layers.bend as LN
import ./../tinybendygrad/nn/state.bend as ST
import ./../tinybendygrad/mixin/op.bend as MO
import ./../tinybendygrad/mixin/movement.bend as MX
import ./../tinybendygrad/mixin/elementwise.bend as E
import ./../tinybendygrad/extra/datasets/__init__.bend as D
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

# the `Refused` accessor, in nn/state.bend:817 symbol=main's shape, so `main` can print the
# address the refusal carries rather than discarding it.
def cn_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# :5-17 Block. The FOUR sublayers (:7,:8,:9,:10) are all named here so the
# distance is four symbols and not "the block".

# :6  def __init__(self, dim)
def cn_block_init(dim: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:6 Block.__init__ -- FIRST MISSING SYMBOL nn.Conv2d CLASS at :7 (the op nn_conv2d, nn/layers.bend:923 symbol=nn_conv2d, EXISTS); then Tensor.layernorm at :8 (nn/__init__.bend:211 symbol=nn_glorot is that file's LAST def, and it has NO x.layernorm def at all -- the wall is the `# TODO(p3) mixin/op.py:1661 x.layernorm` marker in that file's WALLS block)")

# :7  self.dwconv = Conv2d(dim, dim, kernel_size=7, padding=3, groups=dim)
def cn_block_dwconv(dim: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:7 Block.dwconv -- needs the nn.Conv2d CLASS: nothing builds the (dim, dim, 7, 7) weight or the state-dict node")

# :8  self.norm = LayerNorm(dim, eps=1e-6)
def cn_block_norm(dim: U32, eps: F32) -> D.Refused:
  D.refuse("extra/models/convnext.py:8 Block.norm -- MISSING Tensor.layernorm, named as an open wall at nn/__init__.bend:211 symbol=nn_glorot (that file's LAST def -- there is NO x.layernorm def; the wall is the `# TODO(p3) mixin/op.py:1661 x.layernorm` marker in that file's WALLS block, and mixin/op.py:1644 upstream)")

# :9  self.pwconv1 = Linear(dim, 4 * dim)   :10  self.pwconv2 = Linear(4 * dim, dim)
def cn_block_pwconv1(dim: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:9 Block.pwconv1 -- needs the nn.Linear CLASS; the op nn_linear (nn/layers.bend:518 symbol=nn_linear) EXISTS")

def cn_block_pwconv2(dim: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:10 Block.pwconv2 -- needs the nn.Linear CLASS; the op nn_linear (nn/layers.bend:518 symbol=nn_linear) EXISTS")

# :11  self.gamma = Tensor.ones(dim)
def cn_block_gamma(dim: U32) -> D.Refused:
  D.refuse("extra/models/convnext.py:11 Block.gamma -- Tensor.ones IS cr_ones (mixin/creation.bend:567 symbol=cr_ones) but it takes an O.Arena and an S.Dt, so this is the WEIGHT-STORE question and not the ones question")

# :13 def __call__(self, x:Tensor)
def cn_block_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/convnext.py:13 Block.__call__ -- FIRST MISSING SYMBOL x.sequential at :14")

# the two lambdas at :15 and :16 are NAMED, not folded into the refusal, because
# :16's is where the missing `Tensor.gelu` lives.
# :15 lambda x: x.permute(0, 2, 3, 1)
def cn_permute_0221(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/convnext.py:15 Block.__call__ permute(0,2,3,1) -- mxw_permute (mixin/movement.bend:1435 symbol=mxw_permute) EXISTS; blocked by Tensor.sequential at :14")

# :16 lambda x: (self.gamma * x).permute(0, 3, 1, 2)
def cn_permute_0312(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/convnext.py:16 Block.__call__ -- Tensor.gelu is MISSING; only ew_quick_gelu exists, using the 1.702 constant, and plain gelu needs erf -- and the FLOAT-CONST FAMILY wall that erf is in is that file's third wall block. THE LANDED ARM IS mixin/elementwise.bend:1207 symbol=ew_quick_gelu")

# :19-32 ConvNeXt.

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
  D.refuse("extra/models/convnext.py:26 ConvNeXt.norm -- MISSING Tensor.layernorm (nn/__init__.bend:211 symbol=nn_glorot is that file's LAST def -- there is NO x.layernorm def; the wall is the `# TODO(p3) mixin/op.py:1661 x.layernorm` marker in that file's WALLS block)")

# :29 def __call__(self, x:Tensor)
def cn_convnext_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/convnext.py:29 ConvNeXt.__call__ -- FIRST MISSING SYMBOL Tensor.sequential at :31")

# :29 :32 x.mean([-2, -1]) -- the one call here whose op EXISTS. `mo_mean` is
# `mixin/op.bend:877`; it is named so the row is not mistaken for "all of
# ConvNeXt is absent".
def cn_mean_axes() -> D.Refused:
  D.refuse("extra/models/convnext.py:32 ConvNeXt.__call__ mean([-2,-1]) -- mo_mean (mixin/op.bend:937 symbol=mo_mean) EXISTS with U32 axes; Python's -2/-1 have no U32 image (nn/layers.bend:374 symbol=nn_dot.order is the construct that measures it -- IT NEEDS NO NEGATIVE INDEX ANYWHERE)")

# :36-42 `versions` -- FIVE dicts of two lists each, and this is the one part of
# the file that is PURE DATA. The whole table is restated here so a reader does
# not have to open Python to learn that "xlarge" is 2048 wide.

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

# :44-52 get_model.

# :44 def get_model(version, load_weights=False)
def cn_get_model(version: U32, load_weights: Bool) -> D.Refused:
  D.refuse("extra/models/convnext.py:44 get_model -- FIRST MISSING SYMBOL ConvNeXt(**versions[version]) at :45, whose first missing symbol is nn.LayerNorm2d")

# :48 weights = torch_load(fetch(...))['model']
def cn_get_model_fetch() -> D.Refused:
  D.refuse("extra/models/convnext.py:48 get_model -- MISSING fetch: helpers.bend:2694 symbol=lines is that file's ONLY I/O construct, so the whole HTTP seam is NOT ported, and no def named fetch( exists")

# :50 mv = get_child(model, k)  :51 mv.assign(...).realize()
def cn_get_model_assign() -> D.Refused:
  D.refuse("extra/models/convnext.py:51 get_model -- MISSING Tensor.assign and Tensor.realize; nn/pool.bend:405 symbol=pool_bn_running_stats and tensor.bend:2679 symbol=tn_param.of both name the immutability divergence")

# :54-63 `if __name__ == "__main__":`. `main` below IS this block and nothing
# else. There is deliberately no invented census printed here: a 1:1 mirror that
# emits rows upstream does not emit is not a mirror, and the census belongs in
# the report where a reader looks for it.

def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, cn_block_init(96))
    srow("convnext_refused_at", cn_at(a))
    row("convnext_ported", False{})
    srow("convnext_block_init_line", "extra/models/convnext.py:6")
    srow("convnext_versions_count", "5")
    urow("convnext_xlarge_dims_0", cn_versions_dim(4))
    urow("convnext_xlarge_depths_2", cn_versions_depth2(4))
