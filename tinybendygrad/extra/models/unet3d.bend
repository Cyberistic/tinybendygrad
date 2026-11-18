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

# not yet ported.
#
# the shortest file in the directory and the only one that is 3-d, and those
# two facts pull in opposite directions. It is short because it has four classes
# and no arithmetic worth the name. It is hard because the ONE conv call at
# upstream:9 has a 3-tuple kernel `(3,3,3)` and a 6-tuple padding
# `(1,1,1,1,1,1)`, so both of this tree's 2-D-shaped layer walls bind at once.
#
# TODO(port): STOPPED AT `DownsampleBlock.__init__` (extra/models/unet3d.py:7).
#   The FIRST line of that constructor is upstream:9
#       nn.Conv2d(c0, c1, kernel_size=(3,3,3), stride=stride,
#                 padding=(1,1,1,1,1,1), bias=False), nn.InstanceNorm(c1)
#   `nn_conv2d` (nn/layers.bend:923 symbol=nn_conv2d) IS nd-GENERIC on purpose -- it reads
#   `ni = len(weight.shape[2:])` at tinybendygrad/nn/layers.bend:716 symbol=nn_pads.dup and derives every shape
#   from it -- so a 3-D kernel is arithmetically expressible. BUT:
#     * THE CLASS IS MISSING. `nn/__init__.bend` has 17 defs and ZERO classes
#       (`grep -cE '^def ' nn/__init__.bend` = 17), so there is no `nn.Conv2d`
#       to construct, no `(c0, c1, 3, 3, 3)` weight and no `bias=False` spelling.
#     * `nn.InstanceNorm` IS MISSING ENTIRELY. `THE PORT's `nn/pool.bend` HEADER` measures
#       `Tensor.batchnorm` as BUILT (`pool_bn`, pool.bend:371 symbol=pool_bn) and names the
#       ONE part of `nn.BatchNorm` that is not a decomposition -- the running
#       stats update, refused at nn/pool.bend:405 symbol=pool_bn_running_stats because `TRAINING` is not a
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
# tensors. Conflating them is the exact mistake `resnet.bend:98-106` warns about
# with a looser grep, so the name is anchored here.
#
# `torch` IS NOT PRESENT AT ALL. :2 is `import torch` and :51 is
# `torch.jit.load(fn, map_location=torch.device("cpu")).state_dict()`,
# :54-55 `assert obj.shape == v.shape` then `obj.assign(v.numpy())`. The
# manifest's "python model/harness" is generous: the checkpoint reader here is
# PyTorch's own serializer, not tinygrad's, so this is a SECOND weight format on
# top of the `torch_load` seam every other model in this directory stops at.
#
# every DEF below refuses, and the return TYPE is `D.Refused`, not a tensor. a
# stub that returned a zero Tensor would be indistinguishable from a layer whose
# weights happen to be zero. `refuse`/`Refused` are DECLARED ONCE at
# `extra/datasets/__init__.bend:40-46` and imported as `D`. Each message names
# the upstream `path:line` of the FIRST MISSING SYMBOL.
# THE GATE MOVED TO `gates/models-unet3d-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
