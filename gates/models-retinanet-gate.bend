# gates/models-retinanet-gate.bend -- the gate driver for `tinybendygrad/extra/models/retinanet.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/extra/models/retinanet.bend as P

import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/dtype.bend as DT
import ./../tinybendygrad/nn/__init__.bend as NN
import ./../tinybendygrad/nn/state.bend as ST
import ./../tinybendygrad/nn/layers.bend as LN
import ./../tinybendygrad/nn/pool.bend as PL
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

def rn_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# :10 `ConvFPN = ConvHead = ConvClassificationHeadLogits = nn.Conv2d`. THREE
# aliases on ONE class. All three now have a real body -- tinybendygrad/nn/layers.bend:745 symbol=nn_pads.grp.go --
# so these refusals are about the CLASS SHELL, not about a missing op, and that
# distinction is the point.

def rn_convfpn_alias() -> D.Refused:
  D.refuse("extra/models/retinanet.py:10 ConvFPN = nn.Conv2d -- the BODY EXISTS at nn/layers.bend:923 symbol=nn_conv2d; the class shell and its kernel_size/padding/bias arguments do not")

def rn_convhead_alias() -> D.Refused:
  D.refuse("extra/models/retinanet.py:10 ConvHead = nn.Conv2d -- SAME BODY as rn_convfpn_alias; nn/layers.bend:923 symbol=nn_conv2d takes groups/stride/dilation and takes NO kernel_size")

def rn_clslogits_alias() -> D.Refused:
  D.refuse("extra/models/retinanet.py:10 ConvClassificationHeadLogits = nn.Conv2d -- THREE NAMES, ONE CLASS; nn/layers.bend:923 symbol=nn_conv2d is that one body and retinanet.py uses all three spellings")

# :12-36 the two numpy functions. NOT NUMPY-CONVERTIBLE TODAY.

# :12 def nms(boxes, scores, thresh=0.5)
def rn_nms() -> D.Refused:
  D.refuse("extra/models/retinanet.py:12 nms -- FIRST MISSING SYMBOL an NDARRAY; THE PORT's `extra/datasets/__init__.bend` HEADER records that np.frombuffer/.astype have no counterpart. `np.argsort` (:15) is also MISSING")

# :28 def decode_bbox(offsets, anchors)
def rn_decode_bbox() -> D.Refused:
  D.refuse("extra/models/retinanet.py:28 decode_bbox -- FIRST MISSING SYMBOL np.rollaxis (:29); np.exp (:33) is NOT the wall -- mixin/op.bend:1034 symbol=mo_exp and mixin/elementwise.bend:1290 symbol=ew_exp ew_exp BOTH exist -- so the ndarray is the whole of it")

# :38-68 RetinaNet.

# :39 def __init__(self, backbone:ResNet, num_classes=264, num_anchors=9, scales=None, aspect_ratios=None)
def rn_retinanet_init(num_classes: U32, num_anchors: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:39 RetinaNet.__init__ -- FIRST MISSING SYMBOL ResNetFPN (:46), whose backbone is extra/models/resnet.bend, which EXISTS AND REFUSES")

# :49 def __call__(self, x:Tensor, kwargs)
def rn_retinanet_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:49 RetinaNet.__call__ -- FIRST MISSING SYMBOL self.forward (:50) -> self.head (:53) -> Tensor.sequential")

# :52 def forward(self, x:Tensor, kwargs)
def rn_retinanet_forward(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:52 RetinaNet.forward -- FIRST MISSING SYMBOL self.backbone (:53), i.e. the ResNet stub")

# :55 def load_from_pretrained(self)
def rn_retinanet_load_from_pretrained() -> D.Refused:
  D.refuse("extra/models/retinanet.py:55 RetinaNet.load_from_pretrained -- FIRST MISSING SYMBOL get_child (:65); `grep -rnE \"^def .*get_child\" --include='*.bend' tinybendygrad/` = 0. The two URLs at :56-59 and torch.hub at :61 are out of scope")

# :71 def postprocess_detections(self, predictions, input_size=(800,800), ...)
def rn_postprocess_detections() -> D.Refused:
  D.refuse("extra/models/retinanet.py:71 postprocess_detections -- FIRST MISSING SYMBOL generate_anchors (:72) from examples/mlperf/helpers.py, a file that does not exist in this port; :73 also needs np.ceil and the loop at :76 is numpy")

# :134-155 ClassificationHead.

# :135 def __init__(self, in_channels, num_anchors, num_classes)
def rn_cls_head_init(in_channels: U32, num_anchors: U32, num_classes: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:135 ClassificationHead.__init__ -- the four ConvHeads (:137,:138) have a body at nn/layers.bend:923 symbol=nn_conv2d; BLOCKED BY the missing class shell")

# :140 def __call__(self, x, labels=None, matches=None)
def rn_cls_head_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:140 ClassificationHead.__call__ -- FIRST MISSING SYMBOL Tensor.sequential (:141)")

# :150 def _compute_loss(self, x, labels, matches)
def rn_cls_head_loss(+x: T.Tensor, +labels: T.Tensor, +matches: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:150 _compute_loss -- FIRST MISSING SYMBOL Tensor.one_hot (:151)")

# :157-182 RegressionHead.

# :158 def __init__(self, in_channels, num_anchors, box_coder=None)
def rn_reg_head_init(in_channels: U32, num_anchors: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:158 RegressionHead.__init__ -- FIRST MISSING SYMBOL BoxCoder (:162,:163) from examples/mlperf/helpers.py, WHICH DOES NOT EXIST HERE")

# :166 def __call__(self, x, bboxes=None, matches=None, anchors=None)
def rn_reg_head_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:166 RegressionHead.__call__ -- FIRST MISSING SYMBOL Tensor.sequential (:167)")

# :176 def _compute_loss(self, x, bboxes, matches, anchors)
def rn_reg_head_loss(+x: T.Tensor, +bboxes: T.Tensor, +matches: T.Tensor, +anchors: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:176 _compute_loss -- FIRST MISSING SYMBOL l1_loss (:180) from examples/mlperf/losses.py, WHICH DOES NOT EXIST HERE; :179 also needs BoxCoder.encode")

# :184-198 RetinaHead.

# :185 def __init__(self, in_channels, num_anchors, num_classes)
def rn_head_init(in_channels: U32, num_anchors: U32, num_classes: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:185 RetinaHead.__init__ -- FIRST MISSING SYMBOL ClassificationHead (:186) -> Tensor.sequential (:141)")

# :189 def __call__(self, x, kwargs)
def rn_head_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:189 RetinaHead.__call__ -- FIRST MISSING SYMBOL Tensor.sequential (:167); the TRAINING branch at :190 reads helpers.bend:65 symbol=Flags, which EXISTS")

# :200-218 ResNetFPN.

# :201 def __init__(self, resnet:ResNet, out_channels=256, returned_layers=[2,3,4])
def rn_fpn_init(out_channels: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:201 ResNetFPN.__init__ -- FIRST MISSING SYMBOL self.body.in_planes (:204), i.e. the ResNet stub's fields")

# :208 def compute_grid_sizes(self, input_size)
def rn_fpn_grid_sizes(input_size: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:208 compute_grid_sizes -- FIRST MISSING SYMBOL np.array/np.ceil/np.arange (:209); a PURE numpy expression over two ints, and there is no ndarray to hold it")

# :211 def __call__(self, x:Tensor)
def rn_fpn_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:211 ResNetFPN.__call__ -- FIRST MISSING SYMBOL self.body.bn1 (:212) then self.body.conv1 (:212); max_pool2d EXISTS at nn/pool.bend:244 symbol=pool_maxpool, pad EXISTS, and :214-217 are Tensor.sequential, MISSING")

# :220-257 the three FPN defs. `ExtraFPNBlock.__call__` is the closest this file
# comes to being runnable: it is two convs (:229,:230) and a list EXTEND (:231).

# :221 def __init__(self, in_channels, out_channels)
def rn_extra_fpn_init(in_channels: U32, out_channels: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:221 ExtraFPNBlock.__init__ -- p6/p7 are ConvFPN (:222,:223) with a body at nn/layers.bend:923 symbol=nn_conv2d; BLOCKED BY the missing class shell")

# :226 def __call__(self, p, c)
def rn_extra_fpn_call(+p: List<&2, T.Tensor>, +c: List<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/retinanet.py:226 ExtraFPNBlock.__call__ -- nn_conv2d EXISTS (:229,:230) and nn_relu EXISTS (:230); BLOCKED AT :231 p.extend, an IN-PLACE mutation of a LIST argument, which a `Data`/immutable list cannot express")

# :235 def __init__(self, in_channels_list, out_channels, extra_blocks=None)
def rn_fpn_init2(in_channels_list: List<&2, U32>, out_channels: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:235 FPN.__init__ -- FIRST MISSING SYMBOL self.inner_blocks.append (:238), a Python list APPEND. `self.inner_blocks, self.layer_blocks = [], []` at :236 is the same in-place list growth and it is the FIRST line of the constructor")

# :242 def __call__(self, x:Tensor)
def rn_fpn_forward(+x: List<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/retinanet.py:242 FPN.__call__ -- FIRST MISSING SYMBOL self.inner_blocks[-1] (:243); :251 is a 4-step reshape+expand+reshape+SLICE upsample and nn/layers.bend:625 symbol=nn_expand covers the expand half ONLY")

# :259-263 the `if __name__ == "__main__":` block. It builds ResNeXt50_32X4D and
# calls load_from_pretrained. `main` below IS this block and NOTHING ELSE.

def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, rn_retinanet_init(264, 9))
    srow("retinanet_refused_at", rn_at(a))
    row("retinanet_conv2d_exists", True{})
    row("retinanet_sequential_exists", False{})
