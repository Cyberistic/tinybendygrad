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
# STUB -- 1:1 PATH MIRROR of extra/models/mask_rcnn.py (1214 LOC). NOT YET PORTED.
#
# MASK R-CNN IS THE BIGGEST FILE IN THIS SLICE AND IT HAS **ONE** SYMBOL THE OTHER
# SEVEN DO NOT ASK FOR. Everything else it names is on resnet.bend's list, or on
# bert/t5/llama's, or already built. The census below is by HIT COUNT, because
# the count is what makes `Tensor.cat` the file's real subject: it is named
# EIGHTEEN TIMES here, and there is no `def mo_cat`, `def tn_cat` or `def ew_cat`
# under `tinybendygrad/`.
#
# THE CENSUS OF THIS FILE'S OWN CALLS, MEASURED BY
# `grep -onE "Tensor\.[a-z_0-9]+|x\.(...)\(|nn\.[A-Z][a-zA-Z]*|get_child|torch_load"
# extra/models/mask_rcnn.py | sort | uniq -c | sort -rn`:
#
#   HIT  SYMBOL                     PORT
#   18   Tensor.cat                  MISSING. mixin/movement.bend:127 `mx_cat` is
#                                   SHAPE ARITHMETIC `(a,b) -> a+b`, NOT the op.
#   10   Tensor.arange               EXISTS, mixin/rand.bend:424 `op_arange`.
#    8   Tensor.where                EXISTS, mixin/elementwise.bend:571 `ew_where`.
#    7   nn.Conv2d                   EXISTS, nn/layers.bend:937 `nn_conv2d`.
#    5   x.clip                      MISSING.
#    5   Tensor.stack                EXISTS, mixin/movement.bend:1272 `mxw_stk`.
#    5   Tensor.relu                 EXISTS, nn/layers.bend:299 `nn_relu`.
#    4   x.reshape                   EXISTS, mixin/movement.bend:1431 `mxw_reshape`.
#    4   nn.Linear                   EXISTS, nn/layers.bend:530 `nn_linear`.
#    2   torch_load                  MISSING, resnet.bend:97-98 already names it.
#    2   Tensor.sqrt                 EXISTS, mixin/elementwise.bend:549 `ew_sqrt`.
#    2   Tensor.full                 EXISTS, mixin/creation.bend:489 `cr_full`.
#    2   get_child                   MISSING, resnet.bend:112-113 already names it.
#    1   x.cast                      EXISTS, mixin/op.bend:390 `mo_cast_t`.
#    1   Tensor.softmax              EXISTS, mixin/op.bend:1157 `mo_softmax`.
#    1   Tensor.ones                 EXISTS, mixin/creation.bend:559 `cr_ones`.
#    1   Tensor.max_pool2d           EXISTS, nn/pool.bend:250 `pool_maxpool`.
#    1   Tensor.log2                 EXISTS, mixin/elementwise.bend:551 `ew_log2`.
#    1   Tensor.chunk                MISSING.
#    1   nn.ConvTranspose2d          MISSING, and it is THE ONLY NEW LAYER.
#
# AND THE ONES THIS GREP CANNOT SEE, WHICH IS WHY IT IS NOT THE CENSUS:
#   `topk` (:29) as a MODULE-LEVEL PYTHON FUNCTION, called at :569 and :623 --
#     MISSING. It sorts `argsort` (`mixin/rand.bend:880` marks `argsort` `TODO(p3)`
#     as a bitonic sort over four nested Python `for` loops) and then takes n.
#   `tensor_gather` (:79) and `_gather` (:46) and `npgather` (:56) -- MISSING.
#     :46 is `Tensor.where(indices.unsqueeze(...) == Tensor.arange(...), array, 0)`,
#     so it is an OP-ONLY gather built from `ew_where` + `op_arange` + `mxw_reshape`,
#     ALL THREE OF WHICH EXIST. The def does not exist; its ingredients do.
#   `Tensor.round` -- MISSING, and `nearest_interpolate` (:20) is `Tensor.round`
#     followed by a `.unsqueeze(-1)` repeat. `Tensor.cos`/`Tensor.sin` are MISSING
#     and extra/models/llama.py:10 needs `.cos` too -- `mixin/elementwise.bend:550` has
#     `def ew_sin` and there is no `def ew_cos`.
#   `_bilinear_interpolate` (:743) and `ROIAlign` (:869) -- the ROIAlign FORWARD
#     is a gather-and-weight bilinear sample. Its ingredients (`ew_where`,
#   `op_arange`, `mxw_reshape`, `ew_mul`, `ew_add`) all exist and the def does not.
#   `numpy` -- `USE_NP_GATHER` (:74) selects between `npgather` and `_gather`.
#
# NOT USED BY THIS FILE, NAMED BECAUSE A READER OF THIS DIRECTORY WOULD ASK:
#   `nn.Embedding`     not named.  `softmax` named ONCE (:1 hit, `Tensor.softmax`)
#                      and EXISTS.  `adam` NOT named -- R-CNN's TRAIN path is a
#                      `_loss` composition, and `nn/optim.bend:898 op_mstep`
#                      / `:903 op_vstep` exist and go unused, as in all seven.
#
# THE BIGGEST SINGLE DELEGATION IS TO THE SIBLING STUB. mask_rcnn.py:1186
# `MaskRCNN.__init__` takes `backbone:ResNet` and :117 symbol=__init__ builds
# `ResNet(50, num_classes=None, stride_in_1x1=True)`. `tinybendygrad/extra/models/
# resnet.bend` EXISTS, is 264 lines, and REFUSES -- `rs_resnet_init` at its :214
# refuses with "extra/models/resnet.py:65 ResNet.__init__ -- FIRST MISSING SYMBOL
# Conv2d (:87)", which is STALE, because nn/layers.bend:937 `nn_conv2d` now
# exists. So the FIRST missing symbol of THIS file is a refusal three files over,
# and correcting it is a two-line edit to a file this unit may not touch.
#
# TODO(port): STOPPED AT `MaskRCNN.__init__` (extra/models/mask_rcnn.py:1176).
# FIRST MISSING SYMBOL: the `backbone:ResNet` argument (:1176/:1178), i.e.
# `extra/models/resnet.bend`'s own refusal, whose named wall
# (`mixin/op.py:1662 batchnorm is SIDE B`) is closed by `nn/pool.bend:381 pool_bn`.
# THE INDEPENDENT FIRST MISSING SYMBOL -- the one that survives fixing resnet.bend
# -- IS `Tensor.cat`, at mask_rcnn.py:175 in `BoxList._split_into_xyxy`, which is
# the EIGHTEEN-HIT symbol with no `def` under `tinybendygrad/`.
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))

def mr_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :16-98 THE MODULE-LEVEL HELPERS. Six of them, and three are the file's real
# subject. `nearest_interpolate` (:20) and `topk` (:29) are named first because
# `Tensor.round` and `argsort` are the two walls between here and the FPN.
# ---------------------------------------------------------------------------

# :16 def rint(tensor)
def mr_rint(+tensor: T.Tensor) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:16 rint -- FIRST MISSING SYMBOL Tensor.round; `grep -rnE \"^def (mo|tn|ew)_round\" --include='*.bend' tinybendygrad/` = 0")

# :20 def nearest_interpolate(tensor, scale_factor)
def mr_nearest_interpolate(+tensor: T.Tensor, scale_factor: U32) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:20 nearest_interpolate -- FIRST MISSING SYMBOL Tensor.round via rint (:21), then Tensor.repeat (:22) for the unsqueeze-repeat")

# :24 def meshgrid(x, y)
def mr_meshgrid(+x: T.Tensor, +y: T.Tensor) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:24 meshgrid -- FIRST MISSING SYMBOL Tensor.cat (:25,:26); the expand (:25) is nn/layers.bend:520 nn_expand and EXISTS")

# :29 def topk(input_, k, dim=-1, largest=True, sorted=False)
def mr_topk(+input_: T.Tensor, k: U32, dim: H.I64) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:29 topk -- FIRST MISSING SYMBOL argsort, which mixin/rand.bend:880 marks TODO(p3): a BITONIC SORT over four nested Python `for` loops. `sorted=False` (:30) is a Python-visible optimization flag, so the port's sort cannot silently replace it")

# :46 def _gather(array, indices)
def mr_gather(+array: T.Tensor, +indices: T.Tensor) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:46 _gather -- Tensor.where EXISTS (mixin/elementwise.bend:571), Tensor.arange EXISTS (mixin/rand.bend:361), x.reshape EXISTS; the INGREDIENTS are all ported and the def is not written")

# :56 def npgather(array, indices)
def mr_npgather(+array: T.Tensor, +indices: T.Tensor) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:56 npgather -- FIRST MISSING SYMBOL an NDARRAY; extra/datasets/__init__.bend:17-20 records np.frombuffer/.astype as having no counterpart. Selected by USE_NP_GATHER at :74")

# :62 def get_strides(shape)
def mr_get_strides() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:62 get_strides -- np.cumprod over a shape tuple (:63); pure numpy over a list of ints")

# :69 def tensor_getitem(tensor, *keys)
def mr_tensor_getitem(+tensor: T.Tensor) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:69 tensor_getitem -- FIRST MISSING SYMBOL the varargs `*keys` (:70) and the TUPLE unpack, plus Tensor.cast (:71) which EXISTS")

# :79 def tensor_gather(tensor, indices)
def mr_tensor_gather(+tensor: T.Tensor, +indices: T.Tensor) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:79 tensor_gather -- FIRST MISSING SYMBOL _gather (:91,:95), whose ingredients exist and whose def does not")

# :109 def permute_and_flatten(layer, N, A, C, H, W)
def mr_permute_and_flatten(+layer: T.Tensor, n: U32, a: U32, c: U32, h: U32, w: U32) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:109 permute_and_flatten -- mxw_permute EXISTS and mxw_reshape EXISTS; FIRST MISSING SYMBOL Tensor.flatten (:112)")

# ---------------------------------------------------------------------------
# :116-302 BoxList. A dict-backed Python object with 24 methods, and it is the
# reason `Tensor.cat` is this file's subject: `:175`, `:179`, `:218`, `:244`,
# `:260`, `:289` and `:296` are all cats.
# ---------------------------------------------------------------------------

# :117 def __init__(self, bbox, image_size, mode="xyxy")
def mr_boxlist_init(+bbox: T.Tensor, image_size: List<&2, U32>) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:117 BoxList.__init__ -- reached :125 Tensor.min/max style clamp; BLOCKED BY the Python DICT at :131 and the Python LIST-OF-List field store at :155")

# :137 def __repr__(self)
def mr_boxlist_repr() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:137 BoxList.__repr__ -- a STRING over a Python dict; no graph and no tensor")

# :145 def area(self)
def mr_boxlist_area() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:145 BoxList.area -- Tensor.prod EXISTS, mixin/op.bend:822 mo_prod (:147); the wall is the Python OBJECT: it reads self.size (:146) and the result is a Tensor used in a Python `if` at :151")

# :154 def add_field(self, field, field_data)
def mr_boxlist_add_field() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:154 BoxList.add_field -- FIRST MISSING SYMBOL the Python dict WRITE self.fields[field] = (:155)")

# :170 def convert(self, mode)
def mr_boxlist_convert() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:170 BoxList.convert -- FIRST MISSING SYMBOL Tensor.cat (:175), the EIGHTEEN-HIT MISSING SYMBOL")

# :186 def _split_into_xyxy(self)
def mr_boxlist_split() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:186 _split_into_xyxy -- Tensor.chunk (:188); `def mo_chunk` does not exist. This is the ONE Tensor.chunk hit in the whole file")

# :200 def resize(self, size, *args, **kwargs)
def mr_boxlist_resize() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:200 BoxList.resize -- FIRST MISSING SYMBOL Tensor.cat (:218) and x.clip (:215) -- TWO missing symbols in one expression")

# :229 def transpose(self, method)
def mr_boxlist_transpose() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:229 BoxList.transpose -- FIRST MISSING SYMBOL Tensor.cat (:244)")

# :254 def clip_to_image(self, remove_empty=True)
def mr_boxlist_clip_to_image() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:254 clip_to_image -- FIRST MISSING SYMBOL x.clip (:255), and :260 is a Tensor.stack over a LIST COMPREHENSION")

# :267 def __getitem__(self, item)
def mr_boxlist_getitem() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:267 BoxList.__getitem__ -- FIRST MISSING SYMBOL tensor_getitem (:273), which is :69")

# :282 def cat_boxlist(bboxes)
def mr_cat_boxlist() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:282 cat_boxlist -- FIRST MISSING SYMBOL Tensor.cat (:289,:296)")

# ---------------------------------------------------------------------------
# :305-348 the two FPN/BACKBONE classes.
# ---------------------------------------------------------------------------

# :306 def __init__(self, in_channels_list, out_channels)
def mr_fpn_init(in_channels_list: List<&2, U32>, out_channels: U32) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:306 FPN.__init__ -- nn_conv2d EXISTS at nn/layers.bend:756 (:309,:310); BLOCKED BY the Python list .append at :309,:310")

# :313 def __call__(self, x: Tensor)
def mr_fpn_call(+x: List<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:313 FPN.__call__ -- FIRST MISSING SYMBOL nearest_interpolate (:322), i.e. Tensor.round; the rest is conv + add + nn_expand, ALL PORTED")

# :334 def __init__(self, resnet, out_channels=256)
def mr_resnetfpn_init(out_channels: U32) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:334 ResNetFPN.__init__ -- FIRST MISSING SYMBOL the `resnet` argument (:334), i.e. extra/models/resnet.bend's refusal")

# :346 def __call__(self, x)
def mr_resnetfpn_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:346 ResNetFPN.__call__ -- FIRST MISSING SYMBOL self.body.bn1/conv1, i.e. the sibling stub")

# ---------------------------------------------------------------------------
# :351-485 the ANCHOR GENERATOR. numpy throughout.
# ---------------------------------------------------------------------------

# :352 def __init__(self, sizes=((32,64,...),), aspect_ratios=((0.5,1.0,2.0),), stride=None)
def mr_anchor_gen_init() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:352 AnchorGenerator.__init__ -- FIRST MISSING SYMBOL np.array over the default `sizes` tuple (:354); nn/pool.bend:326 `pool_flatten` exists and is NOT numpy")

# :383 def grid_anchors(self, grid_sizes)
def mr_anchor_grid() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:383 grid_anchors -- FIRST MISSING SYMBOL Tensor.arange (:390,:393) EXISTS, then Tensor.stack (:399) EXISTS, then torch.cat (:399) -- the call at :399 is `torch.cat`, NOT `Tensor.cat`, and `torch` is MISSING")

# :407 def add_visibility_to(self, boxlist)
def mr_anchor_visibility() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:407 add_visibility_to -- FIRST MISSING SYMBOL Tensor.ones (:419) and a uint8 dtype compare; Tensor.where EXISTS but the mask arithmetic at :419-421 is `anchors.shape[0]`-length arithmetic over an int tensor")

# :422 def __call__(self, image_list, feature_maps)
def mr_anchor_gen_call() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:422 AnchorGenerator.__call__ -- FIRST MISSING SYMBOL grid_anchors (:424) -> torch.cat (:399)")

# :438 def generate_anchors(...)
def mr_generate_anchors() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:438 generate_anchors -- np.meshgrid/np.sqrt/np.arange over a sizes tuple (:440); Tensor.sqrt EXISTS (mixin/elementwise.bend:549) and `def mo_meshgrid` does not")

# :444 def _generate_anchors(base_size, scales, aspect_ratios)
def mr_anchors_base() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:444 _generate_anchors -- FIRST MISSING SYMBOL torch.cat (:447); `torch` has no counterpart, and it is a DIFFERENT call from the `Tensor.cat` the port would need")

# :461 def _mkanchors(ws, hs, x_ctr, y_ctr)
def mr_mkanchors() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:461 _mkanchors -- FIRST MISSING SYMBOL torch.cat (:464)")

# :473 def _ratio_enum(anchor, ratios)
def mr_ratio_enum() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:473 _ratio_enum -- rint/Tensor.sqrt EXIST (:477); BLOCKED BY the torch.cat at :464 on the way in")

# :483 def _scale_enum(anchor, scales)
def mr_scale_enum() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:483 _scale_enum -- FIRST MISSING SYMBOL torch.cat, same wall as :464")

# ---------------------------------------------------------------------------
# :491-654 RPNHead / RPNPostProcessor / RPN.
# ---------------------------------------------------------------------------

# :492 def __init__(self, in_channels, num_anchors)
def mr_rpn_head_init(in_channels: U32, num_anchors: U32) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:492 RPNHead.__init__ -- FIRST MISSING SYMBOL Conv2d at :496-500; the BODY exists at nn/layers.bend:756 nn_conv2d and the class shell does not")

# :503 def __call__(self, features)
def mr_rpn_head_call(+features: List<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:503 RPNHead.__call__ -- FIRST MISSING SYMBOL Tensor.cat (:505)")

# :507 def boxlist_nms(boxlist, nms_thresh, max_proposals=-1, score_field="scores")
def mr_boxlist_nms() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:507 boxlist_nms -- FIRST MISSING SYMBOL topk (:509) -> argsort, the same wall as :29")

# :521 def remove_small_boxes(boxlist, min_size)
def mr_remove_small() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:521 remove_small_boxes -- FIRST MISSING SYMBOL x.clip (:526) and Tensor.arange")

# :535 def __init__(self, pre_nms_top_n, post_nms_top_n, nms_thresh, min_size, ...)
def mr_rpn_post_init() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:535 RPNPostProcessor.__init__ -- a dict of nine numbers, which is data and not a graph; it is refused because the fields (:570,:572,:583,:602) all read tensors this port cannot produce")

# :569 def __call__(self, anchors, objectness, box_regression)
def mr_rpn_post_call() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:569 RPNPostProcessor.__call__ -- FIRST MISSING SYMBOL topk, called here FIRST at :569")

# :631 def __init__(self, in_channels, num_anchors, ...)
def mr_rpn_init(in_channels: U32, num_anchors: U32) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:631 RPN.__init__ -- FIRST MISSING SYMBOL RPNHead (:635) -> Conv2d (:496)")

# :643 def __call__(self, images, features, gt_instances=None)
def mr_rpn_call() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:643 RPN.__call__ -- FIRST MISSING SYMBOL self.rpn_head (:649) -> Conv2d")

# ---------------------------------------------------------------------------
# :657-880 the EXTRACTORS AND ROIAlign.
# ---------------------------------------------------------------------------

# :657 def make_conv3x3(in_channels, out_channels, stride=1)
def mr_make_conv3x3() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:657 make_conv3x3 -- FIRST MISSING SYMBOL nn.Conv2d; nn/layers.bend:756 nn_conv2d EXISTS and its `padding` is a SHAPE LIST (nn/__init__.bend:196 nn_same), not the int 1 at :659")

# :676 class MaskRCNNFPNFeatureExtractor / :677 def __init__(self, in_channels_list, out_channels, norm_frozen=False)
def mr_fpn_extractor_init() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:677 MaskRCNNFPNFeatureExtractor.__init__ -- FIRST MISSING SYMBOL the LastLevelMaxPool (:681), which is Tensor.max_pool2d and EXISTS at nn/pool.bend:250")

# :697 def forward(self, x)
def mr_fpn_extractor_forward(+x: List<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:697 MaskRCNNFPNFeatureExtractor.forward -- FIRST MISSING SYMBOL Tensor.cat (:706,:711); mxw_permute (:706), mxw_reshape and nn_expand ALL EXIST")

# :706 class MaskRCNNC4Predictor / :707 def __init__(self, in_channels, num_classes)
def mr_c4_predictor_init() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:707 MaskRCNNC4Predictor.__init__ -- FIRST MISSING SYMBOL nn.Linear (:713); nn/layers.bend:427 nn_linear EXISTS")

# :716 def forward(self, x)
def mr_c4_predictor_forward(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:716 MaskRCNNC4Predictor.forward -- FIRST MISSING SYMBOL the module-level nn.Linear holding (:711,:715)")

# :743 def _bilinear_interpolate(x, size, align_corners, scale_factor=None)
def mr_bilinear() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:743 _bilinear_interpolate -- FIRST MISSING SYMBOL x.clip (:750) and the reshape/permute/where chain; ew_where, op_arange, mxw_reshape and ew_mul/ew_add ALL EXIST, so this def is WRITEABLE and simply IS NOT WRITTEN")

# :869 class ROIAlign / :870 def __init__(self, output_size, spatial_scale, sampling_ratio, aligned=True)
def mr_roi_align_init() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:870 ROIAlign.__init__ -- FOUR integers and a Bool (:871-874); it is refused because its __call__ at :877 is the bilinear gather, not because this signature is hard")

# :877 def __call__(self, input, rois)
def mr_roi_align_call(+input: T.Tensor, +rois: T.Tensor) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:877 ROIAlign.__call__ -- FIRST MISSING SYMBOL _bilinear_interpolate (:880), which is :743")

# ---------------------------------------------------------------------------
# :882-1130 the POOLER, HEADS AND MASK.
# ---------------------------------------------------------------------------

# :883 class LevelMapper / :884 def __init__(self, k_min, k_max)
def mr_level_mapper_init(k_min: F32, k_max: F32) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:884 LevelMapper.__init__ -- math.floor/ceil over two floats (:886); plain F32 arithmetic with no tensor, so it is portable and is refused only because the Pooler that reads it is not")

# :897 class Pooler / :898 def __init__(self, output_size, scales, sampling_ratio)
def mr_pooler_init(output_size: U32, scales: List<&2, F32>) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:898 Pooler.__init__ -- FIRST MISSING SYMBOL the Python list .append at :903,:906 building `poolers`")

# :919 def forward(self, x, boxes)
def mr_pooler_forward() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:919 Pooler.forward -- FIRST MISSING SYMBOL Tensor.cat (:922,:928), and the boxlevel_to_level arithmetic at :926 is a Python float expression over a tensor list")

# :951 class FPNPredictor / :952 def __init__(self, in_channels, hidden_size, num_classes)
def mr_fpn_predictor_init() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:952 FPNPredictor.__init__ -- FIRST MISSING SYMBOL nn.Linear (:958,:963); nn_linear EXISTS at nn/layers.bend:427")

# :965 class PostProcessor / :966 def __init__(self, score_thresh=0.05, nms_thresh=0.5, detections_per_img=100, ...)
def mr_post_init() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:966 PostProcessor.__init__ -- five floats and an int (:967-972); refused because every field it configures is read inside the :1014 loop, which is numpy")

# :1014 def forward(self, boxes, scores)
def mr_post_forward() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:1014 PostProcessor.forward -- FIRST MISSING SYMBOL topk (:1024) -> argsort; the loop at :1018-1034 is a Python for over boxes whose length is a tensor value")

# :1057 class RoIBoxHead / :1058 def __init__(self, in_channels, hidden_size, num_classes, ...)
def mr_roi_box_head_init() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:1058 RoIBoxHead.__init__ -- FIRST MISSING SYMBOL the Python LIST COMPREHENSION at :1063 building `fc_layers` from a range")

# :1071 def forward(self, x)
def mr_roi_box_head_forward() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:1071 RoIBoxHead.forward -- FIRST MISSING SYMBOL the in-place `x = x.flatten(start_dim=1)` (:1072), which is a rebind AND a flatten; nn/layers.bend:242 nn_sum exists but `def mo_flatten` does not")

# :1077 class MaskPostProcessor / :1078 def __init__(self, mask_threshold=0.5, ...)
def mr_mask_post_init() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:1078 MaskPostProcessor.__init__ -- two floats (:1079); refused because :1084-1095 is pastes_in_image, a Python dict keyed by a slice, with no tensor spelling")

# :1104 class Mask / :1105 def __init__(self, x, ...)
def mr_mask_init() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:1105 Mask.__init__ -- FIRST MISSING SYMBOL the Python DICT at :1108 keyed by a string")

# :1112 def paste(self, boxes, seg_masks)
def mr_mask_paste() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:1112 Mask.paste -- FIRST MISSING SYMBOL x.clip (:1118)")

# :1120 class RoIHeads / :1121 def __init__(self, box_roi_pool, box_head, box_predictor, mask_roi_pool, ...)
def mr_roi_heads_init() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:1121 RoIHeads.__init__ -- no graph; it stores five subservices (:1122-1126) and returns None")

# :1130 def forward(self, features, proposals)
def mr_roi_heads_forward() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:1130 RoIHeads.forward -- FIRST MISSING SYMBOL Tensor.cat (:1135)")

# ---------------------------------------------------------------------------
# :1131-1174 the IMAGE LIST. `to_image_list` (:1141) is numpy padding.
# ---------------------------------------------------------------------------

# :1132 class ImageList / :1133 def __init__(self, tensors, image_sizes)
def mr_image_list_init() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:1133 ImageList.__init__ -- FIRST MISSING SYMBOL the caller's batch dim (:1134), i.e. images.tensors at :1205")

# :1141 def to_image_list(tensors, size_divisible=32)
def mr_to_image_list() -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:1141 to_image_list -- FIRST MISSING SYMBOL np.array/np.floor/np.ceil (:1152-1158); mxw_pad.go EXISTS at mixin/movement.bend:1517 and the max padding size is a numpy reduction over the batch")

# ---------------------------------------------------------------------------
# :1176-1209 MaskRCNN.
# ---------------------------------------------------------------------------

# :1177 def __init__(self, num_classes, image_mean, image_std, ...)
def mr_maskrcnn_init(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:1177 MaskRCNN.__init__ -- FIRST MISSING SYMBOL the `backbone:ResNet` argument (:1178); tinybendygrad/extra/models/resnet.bend EXISTS and REFUSES at its own :214")

# :1194 def __call__(self, images)
def mr_maskrcnn_call(+images: T.Tensor) -> D.Refused:
  D.refuse("extra/models/mask_rcnn.py:1194 MaskRCNN.__call__ -- FIRST MISSING SYMBOL to_image_list (:1205), i.e. np.array; the three model calls at :1206-1208 are all the sibling stub")

# ---------------------------------------------------------------------------
# :1211-1214 the `if __name__ == "__main__":` block -- ResNet(50,
# num_classes=None, stride_in_1x1=True), then MaskRCNN(backbone=resnet), then
# load_from_pretrained(). `main` below IS this block and NOTHING ELSE.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, mr_maskrcnn_init(81))
    srow("mask_rcnn_refused_at", mr_at(a))
    row("mask_rcnn_conv2d_exists", True{})
    row("mask_rcnn_cat_exists", False{})