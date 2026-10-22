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

# ===========================================================================
# STUB -- 1:1 PATH MIRROR of examples/train_resnet.py (45 LOC). NOT YET PORTED.
#
# ** THIS FILE IS BLOCKED ON A BACKWARD PASS THAT NOBODY HAS EVER EXECUTED. **
#
# That is a measured sentence and the measurement is the whole reason this
# stub is honest rather than merely incomplete. Read it before budgeting.
# Measured 2026-10-19 03:46-04:10Z at HEAD 80d329a33.
#
# THE FORWARD CORPUS IS GREEN: 34 of 34 graphs byte-identical (`unhealthy() -> 0`,
# `artefacts_ok() -> 0`, `repro_bad() -> 0`, `310 of 310 files identical across
# two clean runs`). EVERY ONE OF THOSE 34 GRAPHS IS A FORWARD GRAPH. So the
# corpus proves the port can express and execute forward graph construction and
# execution, and it proves NOTHING about a gradient because no graph in it asks
# for one.
#
# THE BACKWARD MACHINERY IS WRITTEN AND UNEXERCISED. Read these five together:
#   `compute_gradient`  mixin/gradient.bend:1473   EXISTS
#   `gr_N` rule defs     mixin/gradient.bend        61 entries, `grep -cE
#                        "^def gr_[0-9]+" = 61
#   `gr_table`           referenced ONLY inside mixin/gradient.bend;
#                        `grep -rn "gr_table" --include='*.bend' tinybendygrad/
#                        | grep -v gradient.bend` = 0
#   `tn_backward`        tensor.bend:2015           EXISTS
#   `compute_gradient`   CALLED FROM EXACTLY ONE PLACE, tensor.bend:2011,
#                        inside `tn_backward.of`. Its only other mention in the
#                        whole tree is a COMMENT, mixin/op.bend:54.
#   `tn_backward`        CALL SITES OUTSIDE tensor.bend = 0. THE INSTRUMENT IS
#                        SELF-REFERENTIAL AND THE DISCLOSURE MATTERS: `grep -rn
#                        "tn_backward" --include='*.bend' tinybendygrad/ | grep
#                        -v "tensor.bend"` returns 5 lines and ALL FIVE ARE
#                        PROSE IN THE TWO STUB FILES THIS UNIT WROTE. Before
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
# SO THE TRAINING PATH IS BLOCKED TWICE OVER, on the backward pass and on the
# loss it would differentiate:
#   `sparse_categorical_crossentropy`  MISSING. `mixin/op.bend:15` puts "the
#   losses" in SIDE B, `mixin/op.bend:1523` is the last line of the file and
#   reads "# SIDE B's SECTION GOES BELOW THIS LINE.", and `grep -rnE "^def
#   mo_sparse" --include='*.bend' tinybendygrad/` = 0. It is the DEFAULT
#   `lossfn` of `extra/training.py:7`.
#
# THE SYMBOL CENSUS. In upstream source order, every symbol :1-45 names:
#
#   `numpy` (:2, used :24,:26,:36,:37,:38)  MISSING. No n-d array library: the
#       `.reshape`, `.astype`, `np.stack`, `np.tile`, `np.expand_dims` and
#       `np.asarray` at :24-38 have no counterpart.
#   `PIL.Image` (:3, used :35)             MISSING. `Image.fromarray(...).resize(
#       (64,64))` at :35 is decode-then-resize and neither half exists.
#   `get_parameters` (:5, used :41)        EXISTS -- nn/state.bend:375.
#   `optim.SGD` (:6, used :41)             MISSING. `grep -c SGD
#       tinybendygrad/nn/optim.bend` = 0. That file's two bodies are LAMB
#       (nn/optim.bend:873) and LARS (:717); SGD is not among them, and SGD is
#       the DEFAULT optimizer of tinygrad's own `train_resnet.py`.
#   `getenv` (:7, used :28)                EXISTS -- helpers.bend:148
#       `getenv_str` and :304 `getenv_int`. Typed, which is exactly what
#       `getenv('TRANSFER')` (a String) and `getenv('NUM', 18)` (a U32) need.
#   `extra.training.train` (:8, used :42)  MISSING. `extra/training.py:7`.
#   `extra.training.evaluate` (:8, :43)    MISSING. `extra/training.py:41`.
#   `extra.models.resnet.ResNet` (:9)      THIS UNIT'S STUB --
#       ./../extra/models/resnet.bend, and it refuses, because `nn.Conv2d` is
#       mixin/op.bend SIDE B.
#   `extra.datasets.fetch_mnist` (:10,:23) PARTIAL. It EXISTS as a REFUSAL:
#       `extra/datasets/__init__.bend:49` `def fetch_mnist(tensors: Bool) ->
#       D.Refused`, written by another unit at 2026-10-19 06:49 local. The
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
#   TWO OF THE MISSING EIGHT ARE THE MILESTONE ITSELF: a loss and a backward
#   pass. The eval path (`examples/test_pkl_imagenet.bend`) needs neither, which
#   is exactly why it is the achievable first milestone and this one is not.
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def tr_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :13-20 ComposeTransforms.
#   :14  def __init__(self, trans)
#   :17  def __call__(self, x)      -- `for t in self.trans: x = t(x)`, a left
#                                       fold over a Python list of callables.
# `__call__` names the real blocker rather than `__init__`: the fold is Bend's
# `List.foldl` and costs nothing, and the callables it would fold are
# `Image.fromarray` (missing) and `np.stack` (missing).
# ---------------------------------------------------------------------------
def tr_compose_init(trans: List<&2, String>) -> D.Refused:
  D.refuse("examples/train_resnet.py:14 ComposeTransforms.__init__ -- FIRST MISSING SYMBOL PIL.Image (:3)")

def tr_compose_call(+x: T.Tensor) -> D.Refused:
  D.refuse("examples/train_resnet.py:17 ComposeTransforms.__call__ -- BLOCKED ON unexercised backward pass: tn_backward tensor.bend:2015 has 0 call sites")

# ---------------------------------------------------------------------------
# :22-45 `if __name__ == "__main__":`. The block is five rounds (`for _ in
# range(5)`, :40), each of which ends in `optimizer.step()` inside
# `extra.training.train`. The bodies below are in upstream line order so the
# first refusal a caller sees is the FIRST missing symbol, not the biggest one.
# ---------------------------------------------------------------------------

# :23  X_train, Y_train, X_test, Y_test = fetch_mnist()
# PARTIAL, and the honest reading is that the answer EXISTS and it is a refusal.
def tr_fetch_mnist() -> D.Refused:
  D.refuse("examples/train_resnet.py:23 fetch_mnist -- extra/datasets/__init__.bend:49 refuses it; no byte source (helpers.bend:3191) and no ndarray")

# :24  X_train = X_train.reshape(-1, 28, 28).astype(np.uint8)
def tr_reshape_uint8() -> D.Refused:
  D.refuse("examples/train_resnet.py:24 FIRST MISSING SYMBOL numpy -- .reshape and .astype have no counterpart")

# :29  model = ResNet(getenv('NUM', 18), num_classes=classes)
def tr_model(num: U32, num_classes: U32) -> D.Refused:
  D.refuse("examples/train_resnet.py:29 ResNet -- BLOCKED ON nn.Conv2d, which is mixin/op.bend SIDE B (mixin/op.bend:1523)")

# :41  optimizer = optim.SGD(get_parameters(model), lr=lr, momentum=0.9)
# `get_parameters` EXISTS (nn/state.bend:375). `optim.SGD` does not.
def tr_optimizer(lr: F32) -> D.Refused:
  D.refuse("examples/train_resnet.py:41 FIRST MISSING SYMBOL optim.SGD -- grep -c SGD tinybendygrad/nn/optim.bend = 0; that file bodies are LAMB :873 and LARS :717")

# :42  train(model, X_train, Y_train, optimizer, 100, BS=32, transform=transform)
def tr_train_round() -> D.Refused:
  D.refuse("examples/train_resnet.py:42 BLOCKED ON unexercised backward pass AND on sparse_categorical_crossentropy (mixin/op.bend:15, SIDE B)")

# :43  evaluate(model, X_test, Y_test, num_classes=classes, transform=transform)
def tr_evaluate_round() -> D.Refused:
  D.refuse("examples/train_resnet.py:43 BLOCKED ON unexercised backward pass AND on sparse_categorical_crossentropy (mixin/op.bend:15, SIDE B)")

# :44  lr /= 1.2
def tr_decay_lr(lr: F32) -> D.Refused:
  D.refuse("examples/train_resnet.py:44 lr /= 1.2 -- reachable only after :42, which is blocked")

def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, tr_train_round())
    srow("train_resnet_refused_at", tr_at(a))
    row("train_resnet_ported", False{})