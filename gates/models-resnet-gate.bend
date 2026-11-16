# gates/models-resnet-gate.bend -- the gate driver for `tinybendygrad/extra/models/resnet.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/extra/models/resnet.bend as P

import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/dtype.bend as DT
import ./../tinybendygrad/nn/__init__.bend as NN
import ./../tinybendygrad/nn/state.bend as ST
import ./../tinybendygrad/mixin/op.bend as MO
import ./../tinybendygrad/mixin/movement.bend as MX
import ./../tinybendygrad/mixin/reduce.bend as RC
import ./../tinybendygrad/extra/datasets/__init__.bend as D
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

# the `Refused` accessor, in nn/state.bend:817 symbol=main's shape, so `main` can print the
# address the refusal carries rather than discarding it.
def rs_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# :7-9 the three module-level aliases. They exist so `load_from_pretrained` can
# monkeypatch a layer implementation, and the monkeypatch is part of the
# file's contract even though upstream never uses it in this file.

def rs_batchnorm_alias() -> D.Refused:
  D.refuse("extra/models/resnet.py:7 BatchNorm = nn.BatchNorm2d -- mixin/op.py:1662 is SIDE B")

def rs_conv2d_alias() -> D.Refused:
  D.refuse("extra/models/resnet.py:8 Conv2d = nn.Conv2d -- mixin/op.py conv2d is SIDE B")

def rs_linear_alias() -> D.Refused:
  D.refuse("extra/models/resnet.py:9 Linear = nn.Linear -- mixin/op.py:1254 is SIDE B")

# :12-33 BasicBlock. `expansion = 1` (:13) is a CLASS CONSTANT and it is a
# U32 here; it is the one number in this file that is already KNOWN.

def rs_basic_block_expansion() -> U32: 1

# :15  def __init__(self, in_planes, planes, stride=1, groups=1, base_width=64)
def rs_basic_block_init(in_planes: U32, planes: U32, stride: U32, groups: U32,
  base_width: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:15 BasicBlock.__init__ -- FIRST MISSING SYMBOL Conv2d (:17)")

# :28  def __call__(self, x)
def rs_basic_block_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/resnet.py:28 BasicBlock.__call__ -- FIRST MISSING SYMBOL x.batchnorm (:29)")

# :36-62 Bottleneck. `expansion = 4` (:38), `stride_in_1x1` defaults False (:40).
# `width = int(planes * (base_width / 64.0)) * groups` (:41) is plain float
# arithmetic over U32 and is PORTABLE; it is listed as a gap in the report, not
# here, because the def cannot reach its second line without Conv2d.

def rs_bottleneck_expansion() -> U32: 4

# :40  def __init__(self, in_planes, planes, stride=1, stride_in_1x1=False,
#                   groups=1, base_width=64)
def rs_bottleneck_init(in_planes: U32, planes: U32, stride: U32, stride_in_1x1: Bool,
  groups: U32, base_width: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:40 Bottleneck.__init__ -- FIRST MISSING SYMBOL Conv2d (:43)")

# :56  def __call__(self, x)
def rs_bottleneck_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/resnet.py:56 Bottleneck.__call__ -- FIRST MISSING SYMBOL x.batchnorm (:57)")

# :64-153 ResNet.

# :65  def __init__(self, num, num_classes=None, groups=1, width_per_group=64,
#                   stride_in_1x1=False)
def rs_resnet_init(num: U32, num_classes: Maybe<&2, U32>, groups: U32, width_per_group: U32,
  stride_in_1x1: Bool) -> D.Refused:
  D.refuse("extra/models/resnet.py:65 ResNet.__init__ -- FIRST MISSING SYMBOL Conv2d (:87)")

# :95  def _make_layer(self, block, planes, num_blocks, stride, stride_in_1x1)
def rs_resnet_make_layer(block_expansion: U32, planes: U32, num_blocks: U32, stride: U32,
  stride_in_1x1: Bool) -> D.Refused:
  D.refuse("extra/models/resnet.py:95 ResNet._make_layer -- FIRST MISSING SYMBOL BasicBlock/Bottleneck")

# :106 def forward(self, x)
def rs_resnet_forward(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/resnet.py:106 ResNet.forward -- FIRST MISSING SYMBOL x.max_pool2d (:110)")

# :125 def __call__(self, x: Tensor) -> Tensor
def rs_resnet_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/resnet.py:125 ResNet.__call__ -- FIRST MISSING SYMBOL x.max_pool2d (:110)")

# :128 def load_from_pretrained(self)
def rs_resnet_load_from_pretrained() -> D.Refused:
  D.refuse("extra/models/resnet.py:128 ResNet.load_from_pretrained -- FIRST MISSING SYMBOL torch_load/fetch (:139)")

# :155-160 the six constructors. Python spells them as lambdas returning a
# `ResNet`, so each refuses exactly as `rs_resnet_init` does with its `num` and
# `num_classes` already filled in.

def rs_resnet18(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:155 ResNet18 -- FIRST MISSING SYMBOL Conv2d (:87)")
def rs_resnet34(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:156 ResNet34 -- FIRST MISSING SYMBOL Conv2d (:87)")
def rs_resnet50(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:157 ResNet50 -- FIRST MISSING SYMBOL Conv2d (:87)")
def rs_resnet101(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:158 ResNet101 -- FIRST MISSING SYMBOL Conv2d (:87)")
def rs_resnet152(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:159 ResNet152 -- FIRST MISSING SYMBOL Conv2d (:87)")
def rs_resnext50_32x4d(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:160 ResNeXt50_32X4D -- FIRST MISSING SYMBOL Conv2d (:87)")

# :162-170 `if __name__ == "__main__":` -- TinyJit over ResNet18 at 224x224,
# `GlobalCounters.reset()`, then ten more captures. `main` below is this block
# and NOTHING ELSE. There is deliberately no invented census printed here: a
# 1:1 mirror that emits rows upstream does not emit is not a mirror, and the
# census belongs in the report where a reader looks for it.

def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, rs_resnet18(1000))
    srow("resnet_refused_at", rs_at(a))
    row("resnet_ported", False{})
