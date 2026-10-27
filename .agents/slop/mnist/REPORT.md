# MNIST END-TO-END ON THE BEND DEVICE — REPORT

**Owner:** this unit. **Tree:** `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`
**Started:** 2026-10-27. **Machine rule:** ONE `bend` process at a time, never background.

## STATUS LOG (append-only)

### 2026-10-27, entry 0 — report opened before any measurement

Mandated by the brief: create the report within the first five minutes and never lose it.

Facts established by the brief, NOT yet measured by me (each is a TODO below):

- `tinybendygrad/runtime/ops_python.bend` is the port of upstream `tinygrad/runtime/ops_python.py`.
- `tinybendygrad/runtime/ops_npy.bend` (711 lines) is the port of upstream's 4-line `tinygrad/runtime/ops_npy.py`.
- `tinybendygrad/nn/datasets.bend` (469 lines) is the port of upstream's 14-line `tinygrad/nn/datasets.py`.
- `ops_bend.py` (repo root) is the CPython-side reference device.
- MEASURED 2026-10-26 by another unit: the port's own 32x32x8 convolution takes
  **9 min 18 s** (373 s USER) for ONE image on the Bend device.

## DELIVERABLES

1. [ ] Per-image forward-pass time on the Bend device — measured.
2. [ ] `.npy` data path, prepared host-side, read by the port's own `ops_npy` device.
3. [ ] Model in `tinybendygrad/nn/`, shape gated against CPython.
4. [ ] End-to-end accuracy: port vs CPython, same data, same weights.
5. [ ] Backward pass + one optimizer step, measured; gradients vs CPython.
6. [ ] What was NOT closed, named; cost of one epoch extrapolated.

## MEASUREMENTS

(filled in as measured — every row names its command)

### 2026-10-27, entry 1 — THE CALIBRATION, AND IT CONTRADICTS THE BRIEF'S PREMISE

Command: `.venv/bin/python .agents/slop/mnist/bench.py` (the script is
`.agents/slop/mnist/bench.py`; the device is `ops_bend.py`'s `BendDevice`,
registered by `sys.modules['tinygrad.runtime.ops_bend'] = OB`, the same line
`.agents/slop/convfix/probe.py:41` uses).

| case | kernel | launches | launch time | nuops | net of the 3.25 s overhead |
|---|---|---|---|---|---|
| `fixed` | `(1,)` + `(1,)` | 1 | **3.25 s** | 14 | — |
| `dot784` | `(1,784) @ (784,10)` | 1 | **29.96 s** | 70 | 26.71 s for 7840 MACs |
| `conv28` | `(1,1,28,28) conv2d (1,1,3,3) p0` | 1 | **16.69 s** | 91 | 13.44 s for 6084 MACs |
| `conv28x4` | `(1,1,28,28) conv2d (4,1,3,3) p0` | 1 | **36.07 s** | 185 | 32.82 s for 24336 MACs |

**⇒ THE BRIEF'S 9 min 18 s IS NOT THE COST OF A 28x28 MNIST FORWARD PASS, AND
THE DIFFERENCE IS NOT A SMALL ONE.** The brief's figure is the port's own
`(1,3,32,32) conv2d (8,3,3,3) p1` — a 3-input-channel, 8-output-channel conv,
221184 MACs over 8192 output positions. `conv28x4` is a FOUR-OUTPUT-CHANNEL
conv on the SAME 28x28 spatial size and costs **36.07 s**, not 9 minutes.
⇒ **THE PER-LAUNCH OVERHEAD IS 3.25 s** (a subprocess, a hex round trip of every
buffer, and the interpreter's own start), and the per-MAC cost is **1.35 to
3.4 ms**.

**⇒ AND THE CONSEQUENCE FOR THE PRIORITY ORDER IS THE OPPOSITE OF WHAT THE BRIEF
FEARED:** the interpreter is slow but not catastrophically so, so a full MNIST
evaluation IS feasible on the Bend device. It is the *training* loop that is
not, and even that is bounded rather than hopeless.

### 2026-10-27, entry 2 — THE GATING MEASUREMENT: ONE 28x28 MNIST FORWARD PASS

Command: `.venv/bin/python .agents/slop/mnist/run.py bend 1` (the model is
`.agents/slop/mnist/model.py`: `Conv2d(1,4,3,pad=1) -> ReLU -> max_pool2d(2)
-> Conv2d(4,8,3,pad=1) -> ReLU -> max_pool2d(2) -> flatten(1) -> Linear(392,10)`,
4266 parameters, trained on CPython's `CPU` device by
`.agents/slop/mnist/train.py`).

```
# device=BEND (the PORT's executor) n=1
  img    0 pred=7 label=7  437.688s launches=12
         [55.394, 9.722, 123.924, 8.619, 12.851, 7.628, 9.318, 42.427, 9.412, 141.547, 5.347, 10.744]
```

**⇒ ONE MNIST FORWARD PASS ON THE BEND DEVICE = 437.688 s = 7 min 17.7 s.**
(Wall clock of the whole process: 7 min 18.23 s, 299.96 s USER, 7.59 s system.)

**⇒ AND THE PREDICTION IS RIGHT ON THE FIRST IMAGE: `pred=7 label=7`, AND IT
AGREES WITH CPython's `pred=7` ON THE SAME IMAGE WITH THE SAME WEIGHTS.**

**⇒ TWELVE LAUNCHES**, and the cost is NOT spread evenly:

| launch | seconds | what it must be |
|---|---|---|
| 0 | 55.39 | the constant PAD of the 28x28 input to 30x30 |
| 1 | 9.72 | the conv1 weight copy / the conv's own setup |
| 2 | **123.92** | conv1: 4 x 28 x 28 = 3136 output positions x 9 MACs = 28224 MACs |
| 3 | 8.62 | relu1 (3136 elements) |
| 4 | 12.85 | pool1 (3136 -> 784) |
| 5 | 7.63 | the constant PAD of 14x14 to 16x16 |
| 6 | 9.32 | the conv2 weight copy |
| 7 | 42.43 | ??? (the second conv's index setup) |
| 8 | 9.41 | relu2 (1568 elements) |
| 9 | **141.55** | conv2: 8 x 14 x 14 = 1568 positions x 36 MACs = 56448 MACs |
| 10 | 5.35 | pool2 (1568 -> 392) |
| 11 | 10.74 | the flatten + the 392x10 dot + the argmax |

**⇒ THE PER-MAC COST IS ~2.5 to 4.4 ms**, which is the number that sizes
everything else. **⇒ AND THE 12 LAUNCHES ARE 12 PROCESSES**, each paying the
3.25 s fixed cost, so ~39 s of the 437 s is per-launch overhead and ~398 s is
arithmetic.

**⇒ THE COST OF ONE MNIST EPOCH (60000 images, forward only, no backward), FROM
THIS MEASUREMENT: 60000 x 437.688 s = 26,261,280 s = 303.9 DAYS.** With a
backward pass at the usual ~2x, a training epoch is ~608 days. **⇒ THAT IS THE
NUMBER THE PRIORITY ORDER TURNS ON**, and it is in the report's last section.

### 2026-10-27, entry 3 — THE DATA PATH, PREPARED AND GATED

**THE HOST-SIDE PREPARATION** (data preparation, NOT the port):
`.venv/bin/python .agents/slop/mnist/prepare_npy.py`. It reads the four `.gz`
files that upstream's `tinygrad/nn/datasets.py:5` NAMES -- fetched from
`https://storage.googleapis.com/cvdf-datasets/mnist/` -- strips the IDX headers
at upstream's own skips (`0x10` for the idx3 files, `8` for the idx1 ones) and
writes four `.npy` files. The digests are in `.agents/slop/mnist/npy_facts.rows`
and `.agents/slop/mnist/source_digests.rows`.

| file | shape | dtype | payload bytes | file bytes |
|---|---|---|---|---|
| `mnist_train_images.npy` | (60000,1,28,28) | uint8 | 47040000 | 47040128 |
| `mnist_train_labels.npy` | (60000,) | uint8 | 60000 | 60128 |
| `mnist_test_images.npy` | (10000,1,28,28) | uint8 | 7840000 | 7840128 |
| `mnist_test_labels.npy` | (10000,) | uint8 | 10000 | 10128 |

**THE PORT's OWN `.npy` PATH**, added to `tinybendygrad/nn/datasets.bend`: the
`.npy` v1 header's arithmetic (the six magic bytes, the two version bytes, the
two bytes that hold the header's OWN LENGTH -- 118 for all four files -- the
ten fixed bytes, and the payload that follows), the per-row byte width DERIVED
from the shape (`product(dims[1:])`: 784 for the images, 1 for the labels), and
the rows that compare the `.npy` route to the IDX route.

**THE GATE**: `.venv/bin/python .agents/slop/mnist/oracle_datasets.py` -- **23
rows, 23 MATCH, 0 mismatch.** The oracle reads the REAL files with numpy and
`struct.unpack("<H", raw[8:10])`; the port's numbers are derived from the
format's arithmetic. A row that cannot go red is a label, so the rows are
compared against the files and not against the port.

**THE FOUR WALLS, RE-EXAMINED** (the long version is in
`tinybendygrad/nn/mnist_cnn.bend`'s header, the short one is in
`datasets.bend`'s new section):

- **W1 THE HTTP GET -- STILL A WALL.** The `.npy` route moves the socket to the
  host and leaves the port the arithmetic. It does not make the port capable of
  a socket and it does not pretend to.
- **W2 THE TENSORS -- STILL A WALL FOR `tensor.bend`'s `Tensor`, WHICH IS A UOP
  SLOT IN AN ARENA AND NOT A BUFFER.** **BUT IT IS NOT A WALL FOR THE
  EXECUTOR**, and that is the finding: the Bend device's tensors ARE buffers,
  and the run drives the model through upstream tinygrad's OWN `Tensor` on the
  port's OWN device.
- **W3 `tarfile`/`pickle` FOR CIFAR -- NOT REACHED.** MNIST has no tar and no
  pickle. The wall is untouched and it is named so that "not reached" is a
  measurement and not an omission.
- **W4 `os.path.isfile` -- NOT CALLED, DELIBERATELY.** The `.npy` header's own
  length field IS the presence check: a file that is not there fails to open,
  and one that is truncated fails to decode. The port does not need a third
  question.

### 2026-10-27, entry 4 — THE MODEL, IN `tinybendygrad/nn/`, GATED

**`tinybendygrad/nn/mnist_cnn.bend`** (278 lines) is GENERATED by
`.agents/slop/mnist/gen_mnist_cnn.py` from `.agents/slop/mnist/model.py`'s
constants -- so no `want=` in it is typed by hand, and the port's copy of the
model and the running model cannot drift apart silently.

**THE GATE**: `.venv/bin/python .agents/slop/mnist/oracle_shapes.py` -- **15
rows, 15 MATCH, 0 mismatch.** Nine are SHAPE rows compared against CPython's
OWN `nn.Conv2d(...)(x).shape`, `Tensor.max_pool2d(...)`, `Tensor.flatten(1)`
and `nn.Linear(...)(x).shape`; three are GRAPH rows compared against a
FIXTURE-MATCHED CPython construction (the port builds its conv over a BUFFER
weight and no bias, so CPython's side is `x.conv2d(w)` and not
`nn.Conv2d(...)(x)`, which adds a bias the port's fixture does not have); two
are the pool's UNREDUCED `noop ++ o_ ++ k_` shape, compared against the
generated `want=`.

**⇒ THE PORT CAN BUILD THIS MODEL'S GRAPH APART FROM THE POOLING NODE, AND IT
SAYS SO INSTEAD OF FAKING THE POOL.** `max_pool2d`'s
`repeat`/`shrink_to`/`reshape`/`permute` chain (`tinygrad/mixin/movement.py:
608-616`) is not built by the substrate -- the same wall
`examples/beautiful_mnist.bend` names -- so the pool is a SHAPE here and not a
GRAPH.

**⇒ AND THE WALL THAT HAS FALLEN IS STILL NAMED AS A WALL.** The brief is right
about `tinybendygrad/examples/train_resnet.bend`'s header: it says *"THIS FILE
IS BLOCKED ON A BACKWARD PASS THAT NOBODY HAS EVER EXECUTED"*, and the brief's
own measurement says `tinybendygrad/mixin/gradient.bend`'s `compute_gradient`
is gated against UPSTREAM's own `compute_gradient` at **36 of 36 rows**. **⇒
THAT HEADER IS NOW FALSE, AND A WALL THAT HAS FALLEN IS STILL NAMED AS A WALL.**
The backward pass section of this report measures it AGAIN, end to end, on the
device, and with the numbers.

### 2026-10-27, entry 5 — THE TRAINING, ON CPYTHON, ONCE

`.venv/bin/python .agents/slop/mnist/train.py` -- 8 epochs, 20000 training
images, batch 64, Adam at lr 0.002, on CPython's `CPU` device (upstream
tinygrad's own C renderer). Loss 0.7271 -> 0.0728. 4266 parameters.
The weights are in `.agents/slop/mnist/weights.npz` with a digest per
parameter tensor in `.agents/slop/mnist/weights.rows`.

**⇒ THE BEND DEVICE IS THE EVALUATION DEVICE, NOT THE TRAINING DEVICE**, and
the reason is the measurement in entry 2: one forward pass is 437.688 s, so one
epoch is 303.9 days.
