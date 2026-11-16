import Base
import ./../tensor.bend as T
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../nn/state.bend as ST
import ./../nn/optim.bend as OPT
import ./../nn/datasets.bend as DS
import ./../nn/__init__.bend as NN
import ./../mixin/op.bend as MO
import ./../mixin/gradient.bend as GR
import ./../extra/models/resnet.bend as RESNET
import ./../extra/datasets/__init__.bend as D

# stub -- 1:1 path mirror of examples/train_resnet.py (45 loc). not yet ported.
#
#  this file is blocked on a backward pass that nobody has ever executed. 
#
# That is a measured sentence and the measurement is the whole reason this
# stub is honest rather than merely incomplete. Read it before budgeting.
# Measured 2026-10-19 03:46-04:10Z at HEAD 80d329a33.
#
# THE FORWARD CORPUS IS GREEN: 34 of 34 graphs byte-identical (`unhealthy() -> 0`,
# `artefacts_ok() -> 0`, `repro_bad() -> 0`, `310 of 310 files identical across
# two clean runs`). every one of those 34 graphs is a forward graph. So the
# corpus proves the port can express and execute forward graph construction and
# execution, and it proves NOTHING about a gradient because no graph in it asks
# for one.
#
# the backward machinery is written and unexercised. Read these five together:
#   `compute_gradient`  mixin/gradient.bend:1581 symbol=compute_gradient   EXISTS
#   `gr_N` rule defs     mixin/gradient.bend        61 entries, `grep -cE
#                        "^def gr_[0-9]+" = 61
#   `gr_table`           referenced ONLY inside mixin/gradient.bend;
#                        `grep -rn "gr_table" --include='*.bend' tinybendygrad/
#                        | grep -v gradient.bend` = 0
#   `tn_backward`        tensor.bend:1988           EXISTS
#   `compute_gradient`   CALLED FROM EXACTLY ONE PLACE, tensor.bend:1985,
#                        inside `tn_backward.of`. Its only other mention in the
#                        whole tree is a COMMENT, THE PORT's `mixin/op.bend` HEADER.
#   `tn_backward`        CALL SITES OUTSIDE tensor.bend = 0. THE INSTRUMENT IS
#                        self-referential and the disclosure matters: `grep -rn
#                        "tn_backward" --include='*.bend' tinybendygrad/ | grep
#                        -v "tensor.bend"` returns 5 lines and ALL FIVE ARE
#                        prose in the two stub files this unit wrote. Before
#                        this unit ran, that grep returned 0. A grep whose hits
#                        are the instrument's own comments measures nothing, and
#                        reporting it as "0 callers" without saying so would be
#                        the citation-of-an-incident failure in miniature.
#
# READ THE FIVE TOGETHER. The reverse-mode rule table is 61 rules of real code
# and the driver reaches it, and NOTHING CALLS THE DRIVER. The pass has never
# produced a single gradient against a CPython oracle, so not one of those 61
# rules has ever been compared against the rule it claims to port. A rule that
# has never been executed has never been wrong either -- which is the same
# argument `AGENTS.md` makes about `DEAD`, and it is why the word here is
# "unexercised" and not "working".
#
# so the training path is blocked twice over, on the backward pass and on the
# loss it would differentiate:
#   `sparse_categorical_crossentropy`  MISSING. `THE PORT's `mixin/op.bend` HEADER` puts "the
#   losses" in SIDE B, `mixin/op.bend:1509 symbol=t_softmax3.go` is the last line of the file and
#   reads "# side b's section goes below this line.", and `grep -rnE "^def
#   mo_sparse" --include='*.bend' tinybendygrad/` = 0. It is the DEFAULT
#   `lossfn` of `extra/training.py:7`.
#
# THE SYMBOL CENSUS. In upstream source order, every symbol :1-45 names:
#
#   `numpy` (examples/train_resnet.py:2), used at :24 (`.astype`), :25 (`.astype`), :36 (`np.stack`) and :38 (`np.tile`). MISSING. No n-d array library: the
#       `.reshape`, `.astype`, `np.stack`, `np.tile`, `np.expand_dims` and
#       `np.asarray` at :24-38 have no counterpart.
#   `PIL.Image` (:3, used :35)             MISSING. `Image.fromarray(...).resize(
#       (64,64))` at :35 is decode-then-resize and neither half exists.
#   `get_parameters` (:5, used :41)        EXISTS -- nn/state.bend:363.
#   `optim.SGD` (:6, used :41)             MISSING. `grep -c SGD
#       tinybendygrad/nn/optim.bend` = 0. That file's two bodies are LAMB
#       (nn/optim.bend:830 symbol=op_postwd) and LARS (:717); SGD is not among them, and SGD is
#       the DEFAULT optimizer of tinygrad's own `train_resnet.py`.
#   `getenv` (:7, used :28)                EXISTS -- helpers.bend:148 symbol=getenv_str
#       `getenv_str` and :304 `getenv_int`. Typed, which is exactly what
#       `getenv('TRANSFER')` (a String) and `getenv('NUM', 18)` (a U32) need.
#   `extra.training.train` (:8, used :42)  MISSING. `extra/training.py:7`.
#   `extra.training.evaluate` (:8, :43)    MISSING. `extra/training.py:41`.
#   `extra.models.resnet.ResNet` (:9)      THIS UNIT'S STUB --
#       ./../extra/models/resnet.bend, and it refuses, because `nn.Conv2d` is
#       mixin/op.bend SIDE B.
#   `extra.datasets.fetch_mnist` (:10,:23) PARTIAL. It EXISTS as a REFUSAL:
#       `extra/datasets/__init__.bend:49 symbol=fetch_mnist` -- the port's `def fetch_mnist(tensors: Bool) -> D.Refused`,
#       written by another unit at 2026-10-19 06:49 local. The
#       CALL at :23 is therefore answerable and its answer is a refusal, which
#       is the correct answer rather than a gap.
#   `ComposeTransforms` (:13-20)           PORTABLE IN PRINCIPLE, NOT PORTED. It
#       is a left fold over a list of one-arg callables (:18-19). The fold is
#       Bend-idiomatic; the callables are `Image.fromarray` (missing) and
#       `np.stack` (missing), so there is nothing to fold.
#   `sparse_categorical_crossentropy`      MISSING -- SIDE B, above.
#   `ResNet` backward                      MISSING IN EXERCISE -- the machinery
#       EXISTS (see the header) and NOTHING CALLS IT.
#
#   3 of the 12 upstream symbols are present, 8 are missing and 1 is partial.
#   two of the missing eight are the milestone itself: a loss and a backward
#   pass. The eval path (`examples/test_pkl_imagenet.bend`) needs neither, which
#   is exactly why it is the achievable first milestone and this one is not.
# THE GATE MOVED TO `gates/train_resnet-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the census this file prints, and `gates/<name>-gate.bend` is the
# driver that prints them.
