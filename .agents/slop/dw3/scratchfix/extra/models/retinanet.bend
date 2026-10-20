import Base
import ./../../tensor.bend as T
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../dtype.bend as DT
import ./../../nn/__init__.bend as NN
import ./../../nn/state.bend as ST
import ./../../nn/layers.bend as LN
import ./../../nn/pool.bend as PL
import ./../../mixin/op.bend as MO
import ./../../mixin/movement.bend as MX
import ./../../mixin/reduce.bend as RC
import ./../../mixin/elementwise.bend as EW
import ./../../mixin/creation.bend as CR
import ./../../mixin/rand.bend as RD
import ./../../nn/optim.bend as OPT
import ./../datasets/__init__.bend as D

# ===========================================================================
# STUB -- 1:1 PATH MIRROR of extra/models/retinanet.py (263 LOC). NOT YET PORTED.
#
# RETINANET IS THE ONE FILE IN THIS SLICE THAT ASKS FOR **NOTHING NEW**. Its
# layer needs are a SUBSET of resnet.bend's, and that is the measured finding of
# this slice: `nn.Conv2d`, `nn.Linear`, `max_pool2d`, `pad`, `permute`,
# `reshape`, `relu`, `where`, `sigmoid` and `sum` are ALL the same symbols
# resnet.bend's census at :40-123 already asked for, and three of them have
# since landed.
#
# WHAT LANDED SINCE resnet.bend WAS WRITTEN, WITH ITS INSTRUMENT:
#   `nn.Conv2d`  nn/layers.bend:756 `nn_conv2d`  -- resnet.bend:69-81 records this as
#                 MISSING and discloses that its own instrument was the file's own
#                 refusal. `nn/layers.bend:1-30` is the unit that closed it and it
#                 says so: "THE WALL TEXT NAMED THE WRONG BLOCKER".
#   `x.max_pool2d` nn/pool.bend:250 `pool_maxpool` -- resnet.bend:64-66 recorded the
#                 POOL SHAPE ARITHMETIC as existing and the BODY as SIDE B.
#   `Tensor.sigmoid` mixin/elementwise.bend:1196 `ew_sigmoid` (:148,:153)
#   `Tensor.where`   mixin/elementwise.bend:571 `ew_where`   (:153)
#
# WHAT IS STILL MISSING HERE, AND IT IS ALL resnet.bend's LIST:
#   `Tensor.sequential` MISSING (:141,:167,:214,:215,:216,:217). resnet.bend:87-88
#                 already names it MISSING with the same instrument, so this is NOT
#                 a new ask. It is the FIVETH most-hit missing symbol in this file
#                 and the FIRST missing symbol of two of its four heads.
#   `Tensor.cat`       MISSING (:142,:168,:197). resnet.bend does not hit it; it is
#                 the closest thing to a new ask and it is one that bert, t5 and
#                 llama ALSO hit (bert.py:40, t5.py:285, rnnt.py:59). FOUR files in
#                 eight ask for it and it has no `def`.
#   `Tensor.one_hot`   MISSING (:151) -- new to this slice, and shared with bert.py
#                 (:164) and transformer.py (:54).
#   `Tensor.argmax`    MISSING -- NOT HIT HERE. `scores.argsort()` at :15 and :93 is
#                 the numpy spelling and `np.argsort` is MISSING; `mo_argmax` does
#                 not exist either, which resnet.bend:89-93 already names.
#   `Tensor.cast`      mixin/op.bend:370 `mo_cast_t` EXISTS (:146).
#   `Tensor.permute`   mixin/movement.bend:1449 `mxw_permute` EXISTS (:141,:167).
#   `x.pad`            mixin/movement.bend:1517 `mxw_pad.go` EXISTS (:213).
#   `x.relu`           nn/layers.bend:262 `nn_relu` EXISTS (:137,:159,:212,:213,:230).
#   `x.sum`            nn/layers.bend:242 `nn_sum` and mixin/op.bend:891 `mo_mean` EXIST.
#   `nn.Embedding`     NOT USED BY THIS FILE. `softmax` NOT USED (no attention).
#   `adam`             NOT USED BY THIS FILE, though `TRAINING` is read at :144 and
#                 :170 and :190 and IS available as helpers.bend:65 `type Flags`.
#
# TWO THINGS IN retinanet.py ARE NOT THE PORT'S PROBLEM AND ARE NAMED SO THEY
# ARE NOT COUNTED AS OURS:
#   (1) `examples/mlperf/helpers.py` (`generate_anchors`, `BoxCoder`) and
#       `examples/mlperf/losses.py` (`sigmoid_focal_loss`, `l1_loss`) -- retinanet.py:4-5.
#       `ls tinybendygrad/examples/mlperf/` -> "No such file or directory". These are
#       SLICES OUT OF SCOPE, and retinanet.bend names them so nobody reads their
#       absence as a porting gap in the model.
#   (2) `postprocess_detections` (:71-132) is SIXTY-TWO LINES OF NUMPY, and `nms`
#       (:12-26) and `decode_bbox` (:28-36) are pure numpy. There is no ndarray in
#       this port -- `extra/datasets/__init__.bend:17-20` records that `-- (2) AN
#       NDARRAY. .reshape, .astype and np.frombuffer have no counterpart here`.
#
# TODO(port): STOPPED AT `RetinaNet.__init__` (extra/models/retinanet.py:38).
# FIRST MISSING SYMBOL: `ResNetFPN(backbone)` at retinanet.py:46, whose `backbone`
# is `extra/models/resnet.bend` -- WHICH EXISTS AND REFUSES. The refusal at
# `tinybendygrad/extra/models/resnet.bend:166` names `extra/models/resnet.py:7
# BatchNorm = nn.BatchNorm2d -- mixin/op.py:1662 is SIDE B`, and that wall text is
# STALE: `nn/pool.bend:381 pool_bn` is a real batchnorm.
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))

def rn_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :10 `ConvFPN = ConvHead = ConvClassificationHeadLogits = nn.Conv2d`. THREE
# aliases on ONE class. All three now have a real body -- nn/layers.bend:756 --
# so these refusals are about the CLASS SHELL, not about a missing op, and that
# distinction is the point.
# ---------------------------------------------------------------------------
def rn_convfpn_alias() -> D.Refused:
  D.refuse("extra/models/retinanet.py:10 ConvFPN = nn.Conv2d -- the BODY EXISTS at nn/layers.bend:756 nn_conv2d; the class shell and its kernel_size/padding/bias arguments do not")

def rn_convhead_alias() -> D.Refused:
  D.refuse("extra/models/retinanet.py:10 ConvHead = nn.Conv2d -- SAME BODY as rn_convfpn_alias; nn/layers.bend:756 takes groups/stride/dilation and takes NO kernel_size")

def rn_clslogits_alias() -> D.Refused:
  D.refuse("extra/models/retinanet.py:10 ConvClassificationHeadLogits = nn.Conv2d -- THREE NAMES, ONE CLASS; nn/layers.bend:756 is that one body and retinanet.py uses all three spellings")

# ---------------------------------------------------------------------------
# :12-36 the two numpy functions. NOT NUMPY-CONVERTIBLE TODAY.
# ---------------------------------------------------------------------------

# :12 def nms(boxes, scores, thresh=0.5)
def rn_nms() -> D.Refused:
  D.refuse("extra/models/retinanet.py:12 nms -- FIRST MISSING SYMBOL an NDARRAY; extra/datasets/__init__.bend:17-20 records that np.frombuffer/.astype have no counterpart. `np.argsort` (:15) is also MISSING")

# :28 def decode_bbox(offsets, anchors)
def rn_decode_bbox() -> D.Refused:
  D.refuse("extra/models/retinanet.py:28 decode_bbox -- FIRST MISSING SYMBOL np.rollaxis (:29); np.exp (:33) is NOT the wall -- mixin/op.bend:987 mo_exp and mixin/elementwise.bend:1286 ew_exp BOTH exist -- so the ndarray is the whole of it")

# ---------------------------------------------------------------------------
# :38-68 RetinaNet.
# ---------------------------------------------------------------------------

# :39 def __init__(self, backbone:ResNet, num_classes=264, num_anchors=9, scales=None, aspect_ratios=None)
def rn_retinanet_init(num_classes: U32, num_anchors: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:39 RetinaNet.__init__ -- FIRST MISSING SYMBOL ResNetFPN (:46), whose backbone is extra/models/resnet.bend, which EXISTS AND REFUSES")

# :49 def __call__(self, x:Tensor, **kwargs)
def rn_retinanet_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:49 RetinaNet.__call__ -- FIRST MISSING SYMBOL self.forward (:50) -> self.head (:53) -> Tensor.sequential")

# :52 def forward(self, x:Tensor, **kwargs)
def rn_retinanet_forward(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:52 RetinaNet.forward -- FIRST MISSING SYMBOL self.backbone (:53), i.e. the ResNet stub")

# :55 def load_from_pretrained(self)
def rn_retinanet_load_from_pretrained() -> D.Refused:
  D.refuse("extra/models/retinanet.py:55 RetinaNet.load_from_pretrained -- FIRST MISSING SYMBOL get_child (:65); `grep -rnE \"^def .*get_child\" --include='*.bend' tinybendygrad/` = 0. The two URLs at :56-59 and torch.hub at :61 are out of scope")

# :71 def postprocess_detections(self, predictions, input_size=(800,800), ...)
def rn_postprocess_detections() -> D.Refused:
  D.refuse("extra/models/retinanet.py:71 postprocess_detections -- FIRST MISSING SYMBOL generate_anchors (:72) from examples/mlperf/helpers.py, a file that does not exist in this port; :73 also needs np.ceil and the loop at :76 is numpy")

# ---------------------------------------------------------------------------
# :134-155 ClassificationHead.
# ---------------------------------------------------------------------------

# :135 def __init__(self, in_channels, num_anchors, num_classes)
def rn_cls_head_init(in_channels: U32, num_anchors: U32, num_classes: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:135 ClassificationHead.__init__ -- the four ConvHeads (:137,:138) have a body at nn/layers.bend:756; BLOCKED BY the missing class shell")

# :140 def __call__(self, x, labels=None, matches=None)
def rn_cls_head_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:140 ClassificationHead.__call__ -- FIRST MISSING SYMBOL Tensor.sequential (:141)")

# :150 def _compute_loss(self, x, labels, matches)
def rn_cls_head_loss(+x: T.Tensor, +labels: T.Tensor, +matches: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:150 _compute_loss -- FIRST MISSING SYMBOL Tensor.one_hot (:151)")

# ---------------------------------------------------------------------------
# :157-182 RegressionHead.
# ---------------------------------------------------------------------------

# :158 def __init__(self, in_channels, num_anchors, box_coder=None)
def rn_reg_head_init(in_channels: U32, num_anchors: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:158 RegressionHead.__init__ -- FIRST MISSING SYMBOL BoxCoder (:162,:163) from examples/mlperf/helpers.py, WHICH DOES NOT EXIST HERE")

# :166 def __call__(self, x, bboxes=None, matches=None, anchors=None)
def rn_reg_head_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:166 RegressionHead.__call__ -- FIRST MISSING SYMBOL Tensor.sequential (:167)")

# :176 def _compute_loss(self, x, bboxes, matches, anchors)
def rn_reg_head_loss(+x: T.Tensor, +bboxes: T.Tensor, +matches: T.Tensor, +anchors: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:176 _compute_loss -- FIRST MISSING SYMBOL l1_loss (:180) from examples/mlperf/losses.py, WHICH DOES NOT EXIST HERE; :179 also needs BoxCoder.encode")

# ---------------------------------------------------------------------------
# :184-198 RetinaHead.
# ---------------------------------------------------------------------------

# :185 def __init__(self, in_channels, num_anchors, num_classes)
def rn_head_init(in_channels: U32, num_anchors: U32, num_classes: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:185 RetinaHead.__init__ -- FIRST MISSING SYMBOL ClassificationHead (:186) -> Tensor.sequential (:141)")

# :189 def __call__(self, x, **kwargs)
def rn_head_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:189 RetinaHead.__call__ -- FIRST MISSING SYMBOL Tensor.sequential (:167); the TRAINING branch at :190 reads helpers.bend:65 Flags, which EXISTS")

# ---------------------------------------------------------------------------
# :200-218 ResNetFPN.
# ---------------------------------------------------------------------------

# :201 def __init__(self, resnet:ResNet, out_channels=256, returned_layers=[2,3,4])
def rn_fpn_init(out_channels: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:201 ResNetFPN.__init__ -- FIRST MISSING SYMBOL self.body.in_planes (:204), i.e. the ResNet stub's fields")

# :208 def compute_grid_sizes(self, input_size)
def rn_fpn_grid_sizes(input_size: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:208 compute_grid_sizes -- FIRST MISSING SYMBOL np.array/np.ceil/np.arange (:209); a PURE numpy expression over two ints, and there is no ndarray to hold it")

# :211 def __call__(self, x:Tensor)
def rn_fpn_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/retinanet.py:211 ResNetFPN.__call__ -- FIRST MISSING SYMBOL self.body.bn1 (:212) then self.body.conv1 (:212); max_pool2d EXISTS at nn/pool.bend:250, pad EXISTS, and :214-217 are Tensor.sequential, MISSING")

# ---------------------------------------------------------------------------
# :220-257 the three FPN defs. `ExtraFPNBlock.__call__` is the closest this file
# comes to being runnable: it is two convs (:229,:230) and a list EXTEND (:231).
# ---------------------------------------------------------------------------

# :221 def __init__(self, in_channels, out_channels)
def rn_extra_fpn_init(in_channels: U32, out_channels: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:221 ExtraFPNBlock.__init__ -- p6/p7 are ConvFPN (:222,:223) with a body at nn/layers.bend:756; BLOCKED BY the missing class shell")

# :226 def __call__(self, p, c)
def rn_extra_fpn_call(+p: List<&2, T.Tensor>, +c: List<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/retinanet.py:226 ExtraFPNBlock.__call__ -- nn_conv2d EXISTS (:229,:230) and nn_relu EXISTS (:230); BLOCKED AT :231 p.extend, an IN-PLACE mutation of a LIST argument, which a `Data`/immutable list cannot express")

# :235 def __init__(self, in_channels_list, out_channels, extra_blocks=None)
def rn_fpn_init2(in_channels_list: List<&2, U32>, out_channels: U32) -> D.Refused:
  D.refuse("extra/models/retinanet.py:235 FPN.__init__ -- FIRST MISSING SYMBOL self.inner_blocks.append (:238), a Python list APPEND. `self.inner_blocks, self.layer_blocks = [], []` at :236 is the same in-place list growth and it is the FIRST line of the constructor")

# :242 def __call__(self, x:Tensor)
def rn_fpn_forward(+x: List<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/retinanet.py:242 FPN.__call__ -- FIRST MISSING SYMBOL self.inner_blocks[-1] (:243); :251 is a 4-step reshape+expand+reshape+SLICE upsample and nn/layers.bend:520 nn_expand covers the expand half ONLY")

# ---------------------------------------------------------------------------
# :259-263 the `if __name__ == "__main__":` block. It builds ResNeXt50_32X4D and
# calls load_from_pretrained. `main` below IS this block and NOTHING ELSE.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, rn_retinanet_init(264, 9))
    srow("retinanet_refused_at", rn_at(a))
    row("retinanet_conv2d_exists", True{})
    row("retinanet_sequential_exists", False{})