#!/usr/bin/env python3
"""model.py -- THE MODEL, once, so that CPython and the Bend device run the
same one.

    .venv/bin/python .agents/slop/mnist/train.py     # train + save weights
    .venv/bin/python .agents/slop/mnist/run.py ...   # evaluate

THE SHAPE CONSTANTS ARE THE CONTRACT. They live HERE, in Python, and they are
transcribed -- BY SCRIPT, NEVER BY HAND -- into
`tinybendygrad/nn/mnist_cnn.bend`, which is the port's own copy of the model.
`tinybendygrad/nn/mnist_cnn.bend` prints its shape rows and
`.agents/slop/mnist/oracle_shapes.py` compares them against CPython's OWN
`nn.Conv2d(...)(x).shape`, so the two copies cannot drift apart silently: if
they do, the gate says so.

THE MODEL. A two-convolution MNIST network:

    conv1  Conv2d(1, C1, 3, padding=1)   -> (N, C1, 28, 28)
    relu1  ReLU
    pool1  max_pool2d(2)                 -> (N, C1, 14, 14)
    conv2  Conv2d(C1, C2, 3, padding=1)  -> (N, C2, 14, 14)
    relu2  ReLU
    pool2  max_pool2d(2)                 -> (N, C2, 7, 7)
    flat   flatten(1)                    -> (N, C2*7*7)
    fc     Linear(C2*7*7, 10)

`C1`/`C2` are chosen so that ONE forward pass on the Bend device costs minutes
rather than hours. The cost is stated in the report and it is the reason the
channel counts are small: the executor is an interpreter, and its cost is
proportional to the MAC count.

THE WEIGHTS ARE SAVED AND REUSED. The training happens on CPython's `CPU`
device (fast, and it is upstream tinygrad's own C renderer). The Bend device
then runs INFERENCE with those exact weights, and CPython runs the same
inference with the same weights, and the two are compared per image. Nothing
here is hand-typed: the weights come out of a file the training wrote.
"""
import pathlib
import sys

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from tinygrad import Tensor, nn  # noqa: E402
from tinygrad.nn.state import get_state_dict, load_state_dict  # noqa: E402

# ---------------------------------------------------------------- the shape

IN_H = 28
IN_W = 28
C1 = 4
C2 = 8
K = 3
PAD = 1
POOL = 2
NCLS = 10

CONV1_OUT_H = IN_H + 2 * PAD - K + 1          # 28
POOL1_OUT_H = CONV1_OUT_H // POOL             # 14
CONV2_OUT_H = POOL1_OUT_H + 2 * PAD - K + 1   # 14
POOL2_OUT_H = CONV2_OUT_H // POOL             # 7
FLAT = C2 * POOL2_OUT_H * POOL2_OUT_H         # 392

SHAPES = {
    "in": (1, IN_H, IN_W),
    "conv1": (C1, CONV1_OUT_H, IN_W),
    "pool1": (C1, POOL1_OUT_H, IN_W // POOL),
    "conv2": (C2, CONV2_OUT_H, IN_W // POOL),
    "pool2": (C2, POOL2_OUT_H, IN_W // POOL // POOL),
    "flat": (FLAT,),
    "fc": (NCLS,),
}


class Model:
    """the model, as upstream tinygrad builds it. `nn.Conv2d` and `nn.Linear`
    are upstream's OWN classes -- the oracle's own -- so the shapes and the
    parameters are upstream's."""

    def __init__(self):
        self.conv1 = nn.Conv2d(1, C1, K, padding=PAD)
        self.conv2 = nn.Conv2d(C1, C2, K, padding=PAD)
        self.fc = nn.Linear(FLAT, NCLS)

    def __call__(self, x: Tensor) -> Tensor:
        x = self.conv1(x).relu().max_pool2d(POOL)
        x = self.conv2(x).relu().max_pool2d(POOL)
        return self.fc(x.flatten(1))


# ---------------------------------------------------------------- weights

def save_weights(m: Model, path: pathlib.Path) -> None:
    np.savez(path, **{k: v.numpy() for k, v in get_state_dict(m).items()})


def load_weights(m: Model, path: pathlib.Path) -> None:
    with np.load(path) as z:
        sd = {k: Tensor(z[k]) for k in get_state_dict(m)}
    load_state_dict(m, sd, verbose=False)


def n_params(m: Model) -> int:
    return sum(int(np.prod(v.shape)) for v in get_state_dict(m).values())
