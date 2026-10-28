import Base
import ./../../tensor.bend as T
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../dtype.bend as DT
import ./../../nn/__init__.bend as NN
import ./../../nn/layers.bend as LN
import ./../../nn/pool.bend as PL
import ./../../nn/state.bend as ST
import ./../../mixin/op.bend as MO
import ./../../mixin/movement.bend as MX
import ./../datasets/__init__.bend as D

# ===========================================================================
# STUB -- 1:1 PATH MIRROR of extra/models/unet3d.py (59 LOC). NOT YET PORTED.
#
# THE SHORTEST FILE IN THE DIRECTORY AND THE ONLY ONE THAT IS 3-D, and those
# two facts pull in opposite directions. It is short because it has four classes
# and no arithmetic worth the name. It is hard because the ONE conv call at
# upstream:9 has a 3-tuple kernel `(3,3,3)` and a 6-tuple padding
# `(1,1,1,1,1,1)`, so both of this tree's 2-D-shaped layer walls bind at once.
#
# TODO(port): STOPPED AT `DownsampleBlock.__init__` (extra/models/unet3d.py:7).
#   The FIRST line of that constructor is upstream:9
#       nn.Conv2d(c0, c1, kernel_size=(3,3,3), stride=stride,
#                 padding=(1,1,1,1,1,1), bias=False), nn.InstanceNorm(c1)
#   `nn_conv2d` (nn/layers.bend:937 symbol=nn_conv2d) IS nd-GENERIC on purpose -- it reads
#   `ni = len(weight.shape[2:])` at nn/layers.bend:724 and derives every shape
#   from it -- so a 3-D kernel is arithmetically expressible. BUT:
#     * THE CLASS IS MISSING. `nn/__init__.bend` has 17 defs and ZERO classes
#       (`grep -cE '^def ' nn/__init__.bend` = 17), so there is no `nn.Conv2d`
#       to construct, no `(c0, c1, 3, 3, 3)` weight and no `bias=False` spelling.
#     * `nn.InstanceNorm` IS MISSING ENTIRELY. `pool.bend:44-48` measures
#       `Tensor.batchnorm` as BUILT (`pool_bn`, pool.bend:382 symbol=pool_bn) and names the
#       ONE part of `nn.BatchNorm` that is not a decomposition -- the running
#       stats update, refused at pool.bend:415 because `TRAINING` is not a
#       binding in this tree and `Tensor.assign` is not a def. InstanceNorm has
#       NO running stats at all (nn/__init__.py:209), so it is STRICTLY EASIER
#       than BatchNorm: it is the `pool_bn` decomposition over `shape[1:]` with
#       no `running_mean`, no `running_var` and no `TRAINING` read. THAT IS THE
#       HONEST FIRST PRIMITIVE BLOCKER.
#   AND THE SECOND IS HARDER STILL: upstream:17
#       nn.ConvTranspose2d(c0, c1, kernel_size=(2,2,2), stride=2)
#   `grep -rnE '^def .*conv_transpose' --include='*.bend' tinybendygrad/`
#   returns 0. The port has a FORWARD conv only. `_conv_transpose` is a
#   different graph (dilation instead of shrink, and its output shape
#   arithmetic is not `_pool`'s), so it is not a parameter of `nn_conv2d`.
#
# `Tensor.cat` is MISSING and every second line in this file needs it: :23
# (`Tensor.cat(x, skip, dim=1)`) is the skip connection, and it is the single
# reason the up path is not merely a stack of convolutions.
# `grep -rniE '^def .*cat' --include='*.bend' tinybendygrad/` returns 0 for a
# `cat` ENTRY -- the only `cat` defs are `mx_cat` (mixin/movement.bend) and
# `pool_sh`, and those concatenate LISTS of U32 for shape arithmetic, not
# tensors. Conflating them is the exact mistake `resnet.bend:99-107` warns about
# with a looser grep, so the name is anchored here.
#
# `torch` IS NOT PRESENT AT ALL. :2 is `import torch` and :51 is
# `torch.jit.load(fn, map_location=torch.device("cpu")).state_dict()`,
# :54-55 `assert obj.shape == v.shape` then `obj.assign(v.numpy())`. The
# manifest's "python model/harness" is generous: the checkpoint reader here is
# PyTorch's own serializer, not tinygrad's, so this is a SECOND weight format on
# top of the `torch_load` seam every other model in this directory stops at.
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

def u3_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :7-13 DownsampleBlock. The TWO lists (:9 and :10) are the same three things,
# so they are two defs and not one, exactly as upstream has them.
# ---------------------------------------------------------------------------

# :8  def __init__(self, c0, c1, stride=2)
def u3_down_init(c0: U32, c1: U32, stride: U32) -> D.Refused:
  D.refuse("extra/models/unet3d.py:8 DownsampleBlock.__init__ -- FIRST MISSING SYMBOL nn.InstanceNorm at :9 (the nn.Conv2d CLASS is missing too; the op nn_conv2d, nn/layers.bend:756, EXISTS and is nd-generic)")

# :9  self.conv1 = [nn.Conv2d(c0, c1, (3,3,3), stride=stride,
#                              padding=(1,1,1,1,1,1), bias=False), nn.InstanceNorm(c1), Tensor.relu]
def u3_down_conv1(c0: U32, c1: U32, stride: U32) -> D.Refused:
  D.refuse("extra/models/unet3d.py:9 DownsampleBlock.conv1 -- MISSING nn.InstanceNorm; Tensor.relu IS nn_relu (nn/layers.bend:262)")

# :10 self.conv2 = [nn.Conv2d(c1, c1, (3,3,3), padding=(1,)*6, bias=False), ...]
def u3_down_conv2(c1: U32) -> D.Refused:
  D.refuse("extra/models/unet3d.py:10 DownsampleBlock.conv2 -- MISSING nn.InstanceNorm; the nn_conv2d OP EXISTS but takes no `bias=False` -- its bias is a Maybe<&2, T.Tensor> argument (nn/layers.bend:714)")

# :12 def __call__(self, x)
def u3_down_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet3d.py:12 DownsampleBlock.__call__ -- FIRST MISSING SYMBOL x.sequential at :13")

# ---------------------------------------------------------------------------
# :15-24 UpsampleBlock. THE TRANSPOSE AND THE CAT.
# ---------------------------------------------------------------------------

# :16 def __init__(self, c0, c1)
def u3_up_init(c0: U32, c1: U32) -> D.Refused:
  D.refuse("extra/models/unet3d.py:16 UpsampleBlock.__init__ -- FIRST MISSING SYMBOL nn.ConvTranspose2d at :17, and no def named conv_transpose( exists in tinybendygrad")

# :17 self.upsample_conv = [nn.ConvTranspose2d(c0, c1, (2,2,2), stride=2)]
def u3_up_transpose(c0: U32, c1: U32) -> D.Refused:
  D.refuse("extra/models/unet3d.py:17 UpsampleBlock.upsample_conv -- MISSING nn.ConvTranspose2d; the port has a FORWARD conv only (nn/layers.bend:756), and a transpose is a different graph, not a parameter of it")

# :23 x = Tensor.cat(x, skip, dim=1) -- THE SKIP. Named on its own because it is
# the symbol whose absence makes the up path a plain stack of convolutions.
def u3_up_cat(+x: T.Tensor, +skip: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet3d.py:23 UpsampleBlock.__call__ -- MISSING Tensor.cat; mixin/movement.bend's mx_cat and nn/pool.bend's pool_sh concatenate LISTS of U32 for shape arithmetic and are not this")

# :21 def __call__(self, x, skip)
def u3_up_call(+x: T.Tensor, +skip: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet3d.py:21 UpsampleBlock.__call__ -- FIRST MISSING SYMBOL nn.ConvTranspose2d at :17")

# ---------------------------------------------------------------------------
# :26-46 UNet3D.
# ---------------------------------------------------------------------------

# :27 def __init__(self, in_channels=1, n_class=3)
def u3_unet3d_init(in_channels: U32, n_class: U32) -> D.Refused:
  D.refuse("extra/models/unet3d.py:27 UNet3D.__init__ -- FIRST MISSING SYMBOL nn.InstanceNorm at :9 via DownsampleBlock")

# :28 filters = [32, 64, 128, 256, 320] -- RESTATED, because a reader of this
# stub should not have to open Python to learn that the bottleneck is 320 wide.
def u3_filters(i: U32) -> U32:
  match i:
    case 0: 32
    case 1: 64
    case 2: 128
    case 3: 256
    case _: 320

def u3_filters_len() -> U32: 5

# :30 self.input_block  :31 self.downsample  :32 self.bottleneck
def u3_unet3d_downsample() -> D.Refused:
  D.refuse("extra/models/unet3d.py:31 UNet3D.downsample -- blocked by DownsampleBlock.__init__ at :8, whose first missing symbol is nn.InstanceNorm")

# :33 self.upsample
def u3_unet3d_upsample() -> D.Refused:
  D.refuse("extra/models/unet3d.py:33 UNet3D.upsample -- FIRST MISSING SYMBOL nn.ConvTranspose2d at :17")

# :34 self.output = {"conv": nn.Conv2d(filters[0], n_class, kernel_size=(1,1,1))}
def u3_unet3d_output(n_class: U32) -> D.Refused:
  D.refuse("extra/models/unet3d.py:34 UNet3D.output -- needs the nn.Conv2d CLASS for the 1x1x1 kernel; the op nn_conv2d EXISTS")

# :36 def __call__(self, x)
def u3_unet3d_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet3d.py:36 UNet3D.__call__ -- FIRST MISSING SYMBOL x.sequential at :13 via DownsampleBlock.__call__")

# ---------------------------------------------------------------------------
# :48-55 load_from_pretrained. THE PYTORCHECKPOINT SEAM.
# ---------------------------------------------------------------------------

# :48 def load_from_pretrained(self)
def u3_load_pretrained() -> D.Refused:
  D.refuse("extra/models/unet3d.py:48 UNet3D.load_from_pretrained -- FIRST MISSING SYMBOL fetch at :50; helpers.bend:3193 records the whole HTTP seam as unported")

# :51 torch.jit.load(fn, map_location=torch.device("cpu")).state_dict()
def u3_load_torch() -> D.Refused:
  D.refuse("extra/models/unet3d.py:51 UNet3D.load_from_pretrained -- MISSING torch; upstream:2 is `import torch` and the port has no torch of any kind, so this is not the tinygrad torch_load seam the other models stop at")

# :55 obj.assign(v.numpy())
def u3_load_assign(+obj: T.Tensor, +v: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet3d.py:55 UNet3D.load_from_pretrained -- MISSING Tensor.assign; pool.bend:408 and tensor.bend:2539 both name the immutability divergence")

# ---------------------------------------------------------------------------
# :57-59 `if __name__ == "__main__":`. `main` below IS this block and nothing
# else. No invented census: a 1:1 mirror that emits rows upstream does not emit
# is not a mirror.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, u3_down_init(1, 32, 1))
    srow("unet3d_refused_at", u3_at(a))
    row("unet3d_ported", False{})
    srow("unet3d_down_init_line", "extra/models/unet3d.py:8")
    urow("unet3d_filters_len", u3_filters_len())
    urow("unet3d_bottleneck_width", u3_filters(4))