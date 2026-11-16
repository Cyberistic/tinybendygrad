# gates/train_resnet-gate.bend -- the gate driver for `tinybendygrad/examples/train_resnet.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/examples/train_resnet.bend as P

import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/nn/state.bend as ST
import ./../tinybendygrad/nn/optim.bend as OPT
import ./../tinybendygrad/nn/datasets.bend as DS
import ./../tinybendygrad/nn/__init__.bend as NN
import ./../tinybendygrad/mixin/op.bend as MO
import ./../tinybendygrad/mixin/gradient.bend as GR
import ./../tinybendygrad/extra/models/resnet.bend as RESNET
import ./../tinybendygrad/extra/datasets/__init__.bend as D
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def tr_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# :13-20 ComposeTransforms.
#   :14  def __init__(self, trans)
#   :17  def __call__(self, x)      -- `for t in self.trans: x = t(x)`, a left
#                                       fold over a Python list of callables.
# `__call__` names the real blocker rather than `__init__`: the fold is Bend's
# `List.foldl` and costs nothing, and the callables it would fold are
# `Image.fromarray` (missing) and `np.stack` (missing).

def tr_compose_init(trans: List<&2, String>) -> D.Refused:
  D.refuse("examples/train_resnet.py:14 ComposeTransforms.__init__ -- FIRST MISSING SYMBOL PIL.Image (:3)")

def tr_compose_call(+x: T.Tensor) -> D.Refused:
  D.refuse("examples/train_resnet.py:17 ComposeTransforms.__call__ -- BLOCKED ON unexercised backward pass: tn_backward tensor.bend:1988 symbol=tn_backward has 0 call sites")

# :22-45 `if __name__ == "__main__":`. The block is five rounds (`for _ in
# range(5)`, :40), each of which ends in `optimizer.step()` inside
# `extra.training.train`. The bodies below are in upstream line order so the
# first refusal a caller sees is the FIRST missing symbol, not the biggest one.

# :23  X_train, Y_train, X_test, Y_test = fetch_mnist()
# PARTIAL, and the honest reading is that the answer EXISTS and it is a refusal.
def tr_fetch_mnist() -> D.Refused:
  D.refuse("examples/train_resnet.py:23 fetch_mnist -- extra/datasets/__init__.bend:49 symbol=fetch_mnist refuses it; no byte source (THE PORT's `helpers.bend` `NOT PORTED` BLOCK) and no ndarray")

# :24  X_train = X_train.reshape(-1, 28, 28).astype(np.uint8)
def tr_reshape_uint8() -> D.Refused:
  D.refuse("examples/train_resnet.py:24 FIRST MISSING SYMBOL numpy -- .reshape and .astype have no counterpart")

# :29  model = ResNet(getenv('NUM', 18), num_classes=classes)
def tr_model(num: U32, num_classes: U32) -> D.Refused:
  D.refuse("examples/train_resnet.py:29 ResNet -- BLOCKED ON nn.Conv2d, which is mixin/op.bend SIDE B (mixin/op.bend:1509 symbol=t_softmax3.go)")

# :41  optimizer = optim.SGD(get_parameters(model), lr=lr, momentum=0.9)
# `get_parameters` EXISTS (nn/state.bend:363). `optim.SGD` does not.
def tr_optimizer(lr: F32) -> D.Refused:
  D.refuse("examples/train_resnet.py:41 FIRST MISSING SYMBOL optim.SGD -- grep -c SGD tinybendygrad/nn/optim.bend = 0; that file bodies are LAMB :873 and LARS :717")

# :42  train(model, X_train, Y_train, optimizer, 100, BS=32, transform=transform)
def tr_train_round() -> D.Refused:
  D.refuse("examples/train_resnet.py:42 BLOCKED ON unexercised backward pass AND on sparse_categorical_crossentropy (THE PORT's `mixin/op.bend` HEADER, SIDE B)")

# :43  evaluate(model, X_test, Y_test, num_classes=classes, transform=transform)
def tr_evaluate_round() -> D.Refused:
  D.refuse("examples/train_resnet.py:43 BLOCKED ON unexercised backward pass AND on sparse_categorical_crossentropy (THE PORT's `mixin/op.bend` HEADER, SIDE B)")

# :44  lr /= 1.2
def tr_decay_lr(lr: F32) -> D.Refused:
  D.refuse("examples/train_resnet.py:44 lr /= 1.2 -- reachable only after :42, which is blocked")

def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, tr_train_round())
    srow("train_resnet_refused_at", tr_at(a))
    row("train_resnet_ported", False{})
