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

# stub -- 1:1 path mirror of extra/models/retinanet.py (263 loc). not yet ported.
#
# retinanet is the one file in this slice that asks for nothing new. Its
# layer needs are a SUBSET of resnet.bend's, and that is the measured finding of
# this slice: `nn.Conv2d`, `nn.Linear`, `max_pool2d`, `pad`, `permute`,
# `reshape`, `relu`, `where`, `sigmoid` and `sum` are ALL the same symbols
# resnet.bend's census at :40-123 already asked for, and three of them have
# since landed.
#
# what landed since resnet.bend was written, with its instrument:
#   `nn.Conv2d`  nn/layers.bend:923 symbol=nn_conv2d `nn_conv2d`  -- THE PORT's `extra/models/resnet.bend` HEADER records this as
#                 MISSING and discloses that its own instrument was the file's own
#                 refusal. `nn/layers.bend:1-30` is the unit that closed it and it
#                 says so: "the wall text named the wrong blocker".
#   `x.max_pool2d` nn/pool.bend:243 `pool_maxpool` -- THE PORT's `extra/models/resnet.bend` HEADER recorded the
#                 POOL SHAPE ARITHMETIC as existing and the BODY as SIDE B.
#   `Tensor.sigmoid` mixin/elementwise.bend:1186 symbol=ew_sigmoid `ew_sigmoid` (:148,:153)
#   `Tensor.where`   mixin/elementwise.bend:559 `ew_where`   (:153)
#
# what is still missing here, and it is all resnet.bend's list:
#   `Tensor.sequential` MISSING (:141,:167,:214,:215,:216,:217). THE PORT's `extra/models/resnet.bend` HEADER
#                 already names it MISSING with the same instrument, so this is NOT
#                 a new ask. It is the FIVETH most-hit missing symbol in this file
#                 and the FIRST missing symbol of two of its four heads.
#   `Tensor.cat`       MISSING (:142,:168,:197). resnet.bend does not hit it; it is
#                 the closest thing to a new ask and it is one that bert, t5 and
#                 llama ALSO hit (bert.py:40, t5.py:285, rnnt.py:59). FOUR files in
#                 eight ask for it and it has no `def`.
#   `Tensor.one_hot`   MISSING (extra/models/retinanet.py:151) -- new to this slice, and
#                 shared with bert.py's `onehot` (extra/models/bert.py:164) and `one_hot` (extra/models/transformer.py:54).
#   `Tensor.argmax`    MISSING -- NOT HIT HERE. `scores.argsort()` at :15 and :93 is
#                 the numpy spelling and `np.argsort` is MISSING; `mo_argmax` does
#                 not exist either, which THE PORT's `extra/models/resnet.bend` HEADER already names.
#   `Tensor.cast`      mixin/op.bend:386 symbol=mo_cast_t `mo_cast_t` EXISTS (:146).
#   `Tensor.permute`   mixin/movement.bend:1432 `mxw_permute` EXISTS (:141,:167).
#   `x.pad`            mixin/movement.bend:1498 symbol=mxw_pad.put `mxw_pad.go` EXISTS (:213).
#   `x.relu`           nn/layers.bend:292 symbol=nn_relu `nn_relu` EXISTS (:137,:159,:212,:213,:230).
#   `x.sum`            nn/layers.bend:275 symbol=nn_sum `nn_sum` and mixin/op.bend:938 symbol=mo_mean `mo_mean` EXIST.
#   `nn.Embedding`     not used by this file. `softmax` not used (no attention).
#   `adam`             NOT USED BY THIS FILE, though `TRAINING` is read at :144 and
#                 :170 and :190 and IS available as helpers.bend:65 `type Flags`.
#
# two things in retinanet.py are not the port's problem and are named so they
# ARE NOT COUNTED AS OURS:
#   (1) `examples/mlperf/helpers.py` (`generate_anchors`, `BoxCoder`) and
#       `examples/mlperf/losses.py` (`sigmoid_focal_loss`, `l1_loss`) -- retinanet.py:4-5.
#       `ls tinybendygrad/examples/mlperf/` -> "No such file or directory". These are
#       SLICES OUT OF SCOPE, and retinanet.bend names them so nobody reads their
#       absence as a porting gap in the model.
#   (2) `postprocess_detections` (retinanet.py:71-132) is SIXTY-TWO LINES OF NUMPY, and `nms`
#       (retinanet.py:12-26) and `decode_bbox` (retinanet.py:28-36) are pure numpy. There is no ndarray in
#       this port -- `extra/datasets/__init__.bend:17-20` records that `-- (2) AN
#       NDARRAY. .reshape, .astype and np.frombuffer have no counterpart here`.
#
# TODO(port): STOPPED AT `RetinaNet.__init__` (extra/models/retinanet.py:38).
# FIRST MISSING SYMBOL: `ResNetFPN(backbone)` at retinanet.py:46, whose `backbone`
# is `extra/models/resnet.bend` -- WHICH EXISTS AND REFUSES. The refusal at
# THE PORT's `extra/models/resnet.bend` HEADER` names the PORT's own
# `extra/models/resnet.py:7` (upstream has NO `extra/` AT THIS PIN) --
# `BatchNorm = nn.BatchNorm2d` is upstream's `tinygrad/nn/__init__.py:60` -- and that wall text is
# STALE: `nn/pool.bend:370 pool_bn` is a real batchnorm.
# THE GATE MOVED TO `gates/models-retinanet-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
