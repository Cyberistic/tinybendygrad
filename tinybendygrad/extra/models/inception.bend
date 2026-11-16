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

# stub -- 1:1 path mirror of extra/models/inception.py (344 loc). not yet
# PORTED.
#
# the largest file in this directory, and the only one with a second, foreign
# MATHEMATICS REQUIREMENT AT THE END. Two thirds of it is ordinary Inception v3;
# the last twenty lines are `calculate_frechet_distance` (upstream:323-344),
# which is `scipy.linalg.sqrtm` -- a MATRIX SQUARE ROOT over 2048x2048 float
# matrices. `from scipy import linalg` is upstream:8 and there is no scipy here,
# no ndarray here, and no linear-algebra module here at all. The FID score is
# therefore not a porting problem but a FOREIGN-DEPENDENCY problem, and it is
# better to say so than to queue it behind a conv2d.
#
# TODO(port): STOPPED AT `BasicConv2d.__init__` (extra/models/inception.py:12),
# at upstream:14
#       self.conv = Conv2d(in_ch, out_ch, bias=False, kwargs)
#   `Tensor.conv2d` IS BUILT (`nn_conv2d`, nn/layers.bend:923 symbol=nn_conv2d, and its bias IS a
#   `Maybe<&2, T.Tensor>` so `bias=False` is `None{}` -- exactly the arm
#   `nn_cnv.add` at nn/layers.bend:881 symbol=nn_cnv.add spells). WHAT IS MISSING IS THE CLASS: `nn/__init__.bend`
#   has 17 defs and ZERO classes, so there is no `nn.Conv2d` to construct, no
#   `kwargs` to forward and no weight to hold a shape.
#   and the very next line is a harder one: upstream:15
#       self.bn = BatchNorm2d(out_ch, eps=0.001)
#   `pool_bn` (nn/pool.bend:371 symbol=pool_bn) is BUILT and `pool_bend:44-48` measures
#   `Tensor.batchnorm` as a pure DECOMPOSITION. The half that is NOT a
#   decomposition -- the running-statistics update -- is REFUSED at
#   `pool_bend:415`, naming both causes: `TRAINING` is not a binding in this
#   tree, and `Tensor.assign` is not a def. `load_from_pretrained` (:273) reads
#   `running_mean`/`running_var` out of the checkpoint, so this is not optional
#   for this file.
#
# the pools are WHERE this file breaks sharply with the others, and it is worth
# being precise because a count would call all of it "pools: done".
#   `pool_maxpool` (nn/pool.bend:243) and `pool_avgpool` (:260) are BUILT and
#   both are unpadded. this file pads on every pool it calls:
#     upstream:38  x.avg_pool2d(kernel_size=(3,3), stride=1, padding=1)
#     upstream:79  x.avg_pool2d(kernel_size=(3,3), stride=1, padding=1)
#     upstream:123 x.avg_pool2d(kernel_size=(3,3), stride=1, padding=1)
#     upstream:134 x.avg_pool2d(kernel_size=5, stride=3, padding=1)
#     upstream:135 x.avg_pool2d(kernel_size=1, padding=1)
#     upstream:147 Tensor.max_pool2d(x, kernel_size=(3,3), stride=2, padding=1)
#     upstream:150 Tensor.max_pool2d(x, kernel_size=(3,3), stride=2, padding=1)
#     upstream:162 Tensor.avg_pool2d(x, kernel_size=(8,8), padding=1)
#     upstream:203 :213 :225 avg_pool2d(..., padding=1, count_include_pad=False)
#     upstream:237 x.max_pool2d(kernel_size=(3,3), stride=1, padding=1)
#   and BOTH padded arms are REFUSED -- `pool_maxpool_padded` (pool.bend:246
#   symbol=pool_maxpool_padded) and
#   `pool_avgpool_padded` (pool.bend:255 symbol=pool_avgpool_padded) -- for ONE named cause:
#   "BLOCKED: mixin/op.py:290 the value!=0 arm, needs identity_element
#   (uop/ops.py:61), not a def". `pool.bend:239-241` adds why that matters
#   rather than being pedantry: "A `max_pool2d` padded with ZERO would be wrong
#   for any negative input, so the padded arm is REFUSED rather than built
#   wrong."
#   so: 12 of the 17 pool calls in this file need an arm that is refused, and
#   the 5 that do not are NAMED HERE SO THE NUMBER IS CHECKABLE:
#     NEEDS A REFUSED ARM -- :38 :79 :123 :134 :135 :147 :150 :162 :203 :213
#                            :225 :237
#     ON THE BUILT ARM    -- :54 :97 :290 :294 :308
#   (measured with `grep -nE '(avg_pool2d|max_pool2d)\(' extra/models/inception.py`,
#   which is why the denominator 17 is here and not "the pools".)
#   and the 5 survivors are the trivial ones: each is in InceptionB (:54),
#   InceptionD (:97) or FidInceptionV3.__call__ (:290, :294, :308), while every
#   named branch pool of a class (:38, :79, :123, :134, :147, :150, :162) is
#   refused. A "5 of 17 pools work" line would be true AND useless, because the
#   5 are the easy half and the 12 are what makes an Inception3 an Inception3.
#
# `Tensor.cat` is MISSING and it is how this file JOINS its branches:
# upstream:40, :56, :81, :99, :121, :122, :125, :205, :215, :227, :239 -- ELEVEN
# calls, and the model is a tree of them. `grep -rniE '^def .*cat' --include=
# '*.bend' tinybendygrad/` returns 0 for a `cat` ENTRY; the `mx_cat` in
# `mixin/movement.bend` and `pool_sh` in `nn/pool.bend` concatenate LISTS of U32
# for shape arithmetic, which is the conflation `resnet.bend:98-106` warns about.
#
# `Tensor.interpolate` is MISSING and it is the FIRST LINE of
# `FidInceptionV3.__call__` (upstream:284). `np.load`, `np.cov`,
# `np.atleast_1d/2d`, `np.isfinite`, `np.trace` and `np.load` are all MISSING
# (:314, :318, :319, :324-327, :332, :342) -- there is no ndarray in this tree,
# and `extra/datasets/__init__.bend:21-23` already says why for a neighbouring
# file: "`.reshape`, `.astype` and `np.frombuffer` have no counterpart here:
# `Tensor` in `tensor.bend` is a UOp slot in an arena, not a buffer".
#
# every DEF below refuses, and the return TYPE is `D.Refused`, not a tensor. a
# stub that returned a zero Tensor would be indistinguishable from a layer whose
# weights happen to be zero. `refuse`/`Refused` are DECLARED ONCE at
# `extra/datasets/__init__.bend:40-46` and imported as `D`. Each message names
# the upstream `path:line` of the FIRST MISSING SYMBOL.
# THE GATE MOVED TO `gates/models-inception-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
