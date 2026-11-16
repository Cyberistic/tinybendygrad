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

# stub -- 1:1 path mirror of extra/models/mask_rcnn.py (1214 loc). not yet ported.
#
# mask r-cnn is the biggest file in this slice and it has one symbol the other
# SEVEN DO NOT ASK FOR. Everything else it names is on resnet.bend's list, or on
# bert/t5/llama's, or already built. The census below is by HIT COUNT, because
# the count is what makes `Tensor.cat` the file's real subject: it is named
# EIGHTEEN TIMES here, and there is no `def mo_cat`, `def tn_cat` or `def ew_cat`
# under `tinybendygrad/`.
#
# the census of this file's own calls, measured by
# `grep -onE "Tensor\.[a-z_0-9]+|x\.(...)\(|nn\.[A-Z][a-zA-Z]*|get_child|torch_load"
# extra/models/mask_rcnn.py | sort | uniq -c | sort -rn`:
#
#   HIT  SYMBOL                     PORT
#   18   Tensor.cat                  MISSING. mixin/movement.bend:125 `mx_cat` is
#                                   SHAPE ARITHMETIC `(a,b) -> a+b`, NOT the op.
#   10   Tensor.arange               EXISTS, mixin/rand.bend:422 `op_arange`.
#    8   Tensor.where                EXISTS, mixin/elementwise.bend:559 `ew_where`.
#    7   nn.Conv2d                   EXISTS, nn/layers.bend:923 `nn_conv2d`.
#    5   x.clip                      MISSING.
#    5   Tensor.stack                EXISTS, mixin/movement.bend:1257 `mxw_stk`.
#    5   Tensor.relu                 EXISTS, nn/layers.bend:292 `nn_relu`.
#    4   x.reshape                   EXISTS, mixin/movement.bend:1414 `mxw_reshape`.
#    4   nn.Linear                   EXISTS, nn/layers.bend:518 `nn_linear`.
#    2   torch_load                  MISSING, resnet.bend:96-97 already names it.
#    2   Tensor.sqrt                 EXISTS, mixin/elementwise.bend:537 `ew_sqrt`.
#    2   Tensor.full                 EXISTS, mixin/creation.bend:499 `cr_full`.
#    2   get_child                   MISSING, resnet.bend:111-112 already names it.
#    1   x.cast                      EXISTS, mixin/op.bend:386 `mo_cast_t`.
#    1   Tensor.softmax              EXISTS, mixin/op.bend:1140 `mo_softmax`.
#    1   Tensor.ones                 EXISTS, mixin/creation.bend:567 `cr_ones`.
#    1   Tensor.max_pool2d           EXISTS, nn/pool.bend:243 `pool_maxpool`.
#    1   Tensor.log2                 EXISTS, mixin/elementwise.bend:539 `ew_log2`.
#    1   Tensor.chunk                MISSING.
#    1   nn.ConvTranspose2d          MISSING, and it is THE ONLY NEW LAYER.
#
# and the ones this grep cannot see, which is why it is not the census:
#   `topk` (:29) as a MODULE-LEVEL PYTHON FUNCTION, called at :569 and :623 --
#     MISSING. It sorts `argsort` (`mixin/rand.bend:962 symbol=rd_randperm` marks `argsort` `TODO(p3)`
#     as a bitonic sort over four nested Python `for` loops) and then takes n.
#   `tensor_gather` (:79) and `_gather` (:46) and `npgather` (:56) -- MISSING.
#     :46 is `Tensor.where(indices.unsqueeze(...) == Tensor.arange(...), array, 0)`,
#     so it is an OP-ONLY gather built from `ew_where` + `op_arange` + `mxw_reshape`,
#     ALL THREE OF WHICH EXIST. The def does not exist; its ingredients do.
#   `Tensor.round` -- MISSING, and `nearest_interpolate` (:20) is `Tensor.round`
#     followed by a `.unsqueeze(-1)` repeat. `Tensor.cos`/`Tensor.sin` are MISSING
#     and extra/models/llama.py:10 needs `.cos` too --
#     `mixin/elementwise.bend:538 symbol=ew_sin` has `def ew_sin` and there is no `def ew_cos`.
#   `_bilinear_interpolate` (:743) and `ROIAlign` (:869) -- the ROIAlign FORWARD
#     is a gather-and-weight bilinear sample. Its ingredients (`ew_where`,
#   `op_arange`, `mxw_reshape`, `ew_mul`, `ew_add`) all exist and the def does not.
#   `numpy` -- `USE_NP_GATHER` (:74) selects between `npgather` and `_gather`.
#
# not used by this file, named because a reader of this directory would ask:
#   `nn.Embedding`     not named.  `softmax` named ONCE (:1 hit, `Tensor.softmax`)
#                      and EXISTS.  `adam` NOT named -- R-CNN's TRAIN path is a
#                      `_loss` composition, and `nn/optim.bend:858 symbol=op_mstep`
#                      / `:903 op_vstep` exist and go unused, as in all seven.
#
# the biggest single delegation is to the sibling stub. mask_rcnn.py:1186
# `MaskRCNN.__init__` takes `backbone:ResNet` and :117 symbol=__init__ builds
# `ResNet(50, num_classes=None, stride_in_1x1=True)`. `tinybendygrad/extra/models/
# resnet.bend` EXISTS, is 264 lines, and REFUSES -- `rs_resnet_init` at its :214
# refuses with "extra/models/resnet.py:65 ResNet.__init__ -- FIRST MISSING SYMBOL
# Conv2d (:87)", which is STALE, because nn/layers.bend:923 `nn_conv2d` now
# exists. So the FIRST missing symbol of THIS file is a refusal three files over,
# and correcting it is a two-line edit to a file this unit may not touch.
#
# TODO(port): STOPPED AT `MaskRCNN.__init__` (extra/models/mask_rcnn.py:1176).
# FIRST MISSING SYMBOL: the `backbone:ResNet` argument (:1176/:1178), i.e.
# `extra/models/resnet.bend`'s own refusal, whose named wall
# (`mixin/op.py:1662 batchnorm is SIDE B`) is closed by `nn/pool.bend:370 pool_bn`.
# THE INDEPENDENT FIRST MISSING SYMBOL -- the one that survives fixing resnet.bend
# -- IS `Tensor.cat`, at mask_rcnn.py:175 in `BoxList._split_into_xyxy`, which is
# the EIGHTEEN-HIT symbol with no `def` under `tinybendygrad/`.
# THE GATE MOVED TO `gates/models-mask_rcnn-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
