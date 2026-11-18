import Base
import ./../../tensor.bend as T
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../dtype.bend as DT
import ./../../nn/__init__.bend as NN
import ./../../nn/state.bend as ST
import ./../../nn/layers.bend as LN
import ./../../mixin/op.bend as MO
import ./../../mixin/movement.bend as MX
import ./../../mixin/reduce.bend as RC
import ./../../mixin/elementwise.bend as EW
import ./../../mixin/creation.bend as CR
import ./../../mixin/rand.bend as RD
import ./../../nn/optim.bend as OPT
import ./../datasets/__init__.bend as D

# stub -- 1:1 path mirror of extra/models/transformer.py (61 loc). not yet ported.
#
# the headline, and it is the answer to "do these models need anything the vision
# models did not ask for": yes, and it is exactly one name.
# `Tensor.scaled_dot_product_attention` (extra/models/transformer.py:27) is MISSING, and
# `grep -rnwE "def .*scaled_dot_product_attention" --include='*.bend' tinybendygrad/`
# returns 0. A vision model never names it -- resnet.bend's own census at :40-123
# asks for conv2d, batchnorm, linear, sequential, argmax, item, torch_load, fetch,
# get_child, rand and TinyJit, and `scaled_dot_product_attention` is not among them
# because no convolution has ever attended to anything.
#
# EVERYTHING ELSE IN THIS FILE IS ALREADY HERE, which is the other half of the
# finding and the reason the distance is this short:
#
# SO `TransformerBlock.__init__` IS PORTABLE TODAY. `rd_scaled_uniform` + `cr_zeros`
# + `cr_ones` + `NN.nn_scale` are all callable and all gated upstream, so the eight
# weight TUPLEs of :12-22 can be allocated. The def below refuses anyway, because a
# refusable half of a class is not the class.
#
# TODO(port): STOPPED AT `TransformerBlock.attn` (extra/models/transformer.py:24).
# MISSING:
#   (1) `Tensor.scaled_dot_product_attention` -- `mixin/rand.py:298`. It is
#       the ONLY symbol in this file with no counterpart, and it is the wall for
#       `attn` (:27), for `Transformer.forward`'s `log_softmax` half (:60 needs only
#       `mo_log_softmax`, which EXISTS), and for every other transformer-shaped file
#       in this directory -- bert.py:279, clip.py:176, clip.py:271, llama.py:101,
#       llama.py:104.
#   (2) `x.layernorm` -- `grep -rnwE "def .*layernorm" --include='*.bend'` = 0.
#       `TransformerBlock.__call__`'s `x.layernorm()` (extra/models/transformer.py:32, :36, :38) and nothing else in this file
#       runs without it. It is the SECOND wall and the one that survives fixing (1).
#   (3) `x.dropout` -- `grep -rnwE "def .*dropout" --include='*.bend'` = 0 (:32,:33,:35,:37).
#   (4) `Tensor.eye` (:51) -- MISSING; `mixin/creation.bend:9` names `eye` in the
#       inventory it measures itself AGAINST and records that it is NOT in that file.
#   (5) `x.int().one_hot(...)` (:54) -- `one_hot` MISSING.
#   (6) `Tensor.cat` (:56) and `Tensor.flatten` (:56) -- `mo_cat`/`mx_flatten` MISSING.
#       `mixin/movement.bend:125` `mx_cat` is SHAPE ARITHMETIC (`(a,b) -> a+b`), not
#       the op, so it does not close this.
#   (7) `x.sequential(self.tbs)` (:59) -- MISSING, and resnet.bend's own census names
#       it MISSING too, so this one is NOT a new ask.
#
# not ported, and named so nobody invents it: `maxlen_eye` (:51), the three-element
# list comprehension of :26 (a Python comprehension over `self.query`/`key`/`value`).
#
# ON `adam`: NOT USED BY THIS FILE. `extra/models/transformer.py` never constructs an
# optimizer. The one that DOES is llama.py's sampling caller, and `nn/optim.bend`
# already carries `op_mstep` :898 and `op_vstep` :903 -- see llama.bend's header.
# THE GATE MOVED TO `gates/models-transformer-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
