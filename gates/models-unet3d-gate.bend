# gates/models-unet3d-gate.bend -- the gate driver for `tinybendygrad/extra/models/unet3d.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/extra/models/unet3d.bend as P

import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/dtype.bend as DT
import ./../tinybendygrad/nn/__init__.bend as NN
import ./../tinybendygrad/nn/layers.bend as LN
import ./../tinybendygrad/nn/pool.bend as PL
import ./../tinybendygrad/nn/state.bend as ST
import ./../tinybendygrad/mixin/op.bend as MO
import ./../tinybendygrad/mixin/movement.bend as MX
import ./../tinybendygrad/extra/datasets/__init__.bend as D
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def u3_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# :7-13 DownsampleBlock. The TWO lists (:9 and :10) are the same three things,
# so they are two defs and not one, exactly as upstream has them.

# :8  def __init__(self, c0, c1, stride=2)
def u3_down_init(c0: U32, c1: U32, stride: U32) -> D.Refused:
  D.refuse("extra/models/unet3d.py:8 DownsampleBlock.__init__ -- FIRST MISSING SYMBOL nn.InstanceNorm at :9 (the nn.Conv2d CLASS is missing too; the op nn_conv2d, nn/layers.bend:745 symbol=nn_pads.grp.go, EXISTS and is nd-generic)")

# :9  self.conv1 = [nn.Conv2d(c0, c1, (3,3,3), stride=stride,
#                              padding=(1,1,1,1,1,1), bias=False), nn.InstanceNorm(c1), Tensor.relu]
def u3_down_conv1(c0: U32, c1: U32, stride: U32) -> D.Refused:
  D.refuse("extra/models/unet3d.py:9 DownsampleBlock.conv1 -- MISSING nn.InstanceNorm; Tensor.relu IS nn_relu (nn/layers.bend:259 symbol=nn_reduce.keep)")

# :10 self.conv2 = [nn.Conv2d(c1, c1, (3,3,3), padding=(1,)*6, bias=False), ...]
def u3_down_conv2(c1: U32) -> D.Refused:
  D.refuse("extra/models/unet3d.py:10 DownsampleBlock.conv2 -- MISSING nn.InstanceNorm; the nn_conv2d OP EXISTS but takes no `bias=False` -- its bias is a Maybe<&2, T.Tensor> argument (tinybendygrad/nn/layers.bend:691 symbol=nn_pool.go)")

# :12 def __call__(self, x)
def u3_down_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet3d.py:12 DownsampleBlock.__call__ -- FIRST MISSING SYMBOL x.sequential at :13")

# :15-24 UpsampleBlock. THE TRANSPOSE AND THE CAT.

# :16 def __init__(self, c0, c1)
def u3_up_init(c0: U32, c1: U32) -> D.Refused:
  D.refuse("extra/models/unet3d.py:16 UpsampleBlock.__init__ -- FIRST MISSING SYMBOL nn.ConvTranspose2d at :17, and no def named conv_transpose( exists in tinybendygrad")

# :17 self.upsample_conv = [nn.ConvTranspose2d(c0, c1, (2,2,2), stride=2)]
def u3_up_transpose(c0: U32, c1: U32) -> D.Refused:
  D.refuse("extra/models/unet3d.py:17 UpsampleBlock.upsample_conv -- MISSING nn.ConvTranspose2d; the port has a FORWARD conv only (nn/layers.bend:745 symbol=nn_pads.grp.go), and a transpose is a different graph, not a parameter of it")

# :23 x = Tensor.cat(x, skip, dim=1) -- THE SKIP. Named on its own because it is
# the symbol whose absence makes the up path a plain stack of convolutions.
def u3_up_cat(+x: T.Tensor, +skip: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet3d.py:23 UpsampleBlock.__call__ -- MISSING Tensor.cat; mixin/movement.bend's mx_cat and nn/pool.bend's pool_sh concatenate LISTS of U32 for shape arithmetic and are not this")

# :21 def __call__(self, x, skip)
def u3_up_call(+x: T.Tensor, +skip: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet3d.py:21 UpsampleBlock.__call__ -- FIRST MISSING SYMBOL nn.ConvTranspose2d at :17")

# :26-46 UNet3D.

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

# :48-55 load_from_pretrained. THE PYTORCHECKPOINT SEAM.

# :48 def load_from_pretrained(self)
def u3_load_pretrained() -> D.Refused:
  D.refuse("extra/models/unet3d.py:48 UNet3D.load_from_pretrained -- FIRST MISSING SYMBOL fetch at :50; THE PORT's `helpers.bend` `NOT PORTED` BLOCK records the whole HTTP seam as unported")

# :51 torch.jit.load(fn, map_location=torch.device("cpu")).state_dict()
def u3_load_torch() -> D.Refused:
  D.refuse("extra/models/unet3d.py:51 UNet3D.load_from_pretrained -- MISSING torch; upstream:2 is `import torch` and the port has no torch of any kind, so this is not the tinygrad torch_load seam the other models stop at")

# :55 obj.assign(v.numpy())
def u3_load_assign(+obj: T.Tensor, +v: T.Tensor) -> D.Refused:
  D.refuse("extra/models/unet3d.py:55 UNet3D.load_from_pretrained -- MISSING Tensor.assign; pool.bend:405 symbol=pool_bn_running_stats and tensor.bend:2497 symbol=t_alu3 both name the immutability divergence")

# :57-59 `if __name__ == "__main__":`. `main` below IS this block and nothing
# else. No invented census: a 1:1 mirror that emits rows upstream does not emit
# is not a mirror.

def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, u3_down_init(1, 32, 1))
    srow("unet3d_refused_at", u3_at(a))
    row("unet3d_ported", False{})
    srow("unet3d_down_init_line", "extra/models/unet3d.py:8")
    urow("unet3d_filters_len", u3_filters_len())
    urow("unet3d_bottleneck_width", u3_filters(4))
