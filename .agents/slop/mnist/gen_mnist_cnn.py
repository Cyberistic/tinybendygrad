#!/usr/bin/env python3
"""gen_mnist_cnn.py -- GENERATE `tinybendygrad/nn/mnist_cnn.bend`.

    .venv/bin/python .agents/slop/mnist/gen_mnist_cnn.py

WHY A GENERATOR. The brief's rule: "THE EXPECTATIONS ARE TRANSCRIBED BY SCRIPT,
NEVER TYPED." Every `want=` in the emitted `.bend` file is computed here from
`.agents/slop/mnist/model.py`'s constants -- the SAME constants the Python model
and the trained weights use -- so the port's copy of the model and the running
model cannot drift apart without the generator saying so.

AND IT IS NOT A SECOND DERIVATION OF THE TRUTH. The `want=` values are the
FORMULA's answers; the port's rows are the port's OWN `nn_conv2d`/`nn_linear`/
`mx_pool_shape` answers; and `.agents/slop/mnist/oracle_shapes.py` compares the
port's `got=` against CPython's OWN `nn.Conv2d(...)(x).shape`. Three
derivations, and the oracle asserts the third agrees with the second.

THE EMITTED FILE IS NOT HAND-EDITED. The next run overwrites it. The header it
carries says so, so a reader knows which file is the source.

THE TEMPLATE IS A `string.Template` AND NOT AN f-STRING, because the emitted
Bend is FULL OF BRACES -- `None{}`, `Some{...}`, `MnShape{...}` -- and an
f-string would read every one of them as a substitution.
"""
import pathlib
import string
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import model as M  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parents[3] / "tinybendygrad" / "nn" / "mnist_cnn.bend"


def shape4(c: int, h: int, w: int) -> str:
    return f"1,{c},{h},{w}"


TEMPLATE = string.Template(r'''# tinybendygrad/nn/mnist_cnn.bend -- THE MNIST MODEL, PORTED.
#
# **GENERATED FILE. DO NOT HAND-EDIT.** `.agents/slop/mnist/gen_mnist_cnn.py`
# writes it, from `.agents/slop/mnist/model.py`'s constants, and the next run
# overwrites it. The reason it is generated is the brief's rule that the
# EXPECTATIONS ARE TRANSCRIBED BY SCRIPT AND NEVER TYPED: every `want=` below
# is computed, not written.
#
# WHAT THIS FILE IS. The port's own copy of the MNIST model that the end-to-end
# run uses, in the port's own idiom: the SHAPE ARITHMETIC of every layer, and
# the GRAPH of the layers the substrate can build.
#
# THE MODEL. It is `.agents/slop/mnist/model.py`'s, and that file is what the
# trained weights belong to:
#
#     conv1  Conv2d(1, $C1, $K, padding=$PAD)    -> (1, $C1, $CONV1_OUT_H, $IN_W)
#     relu1  ReLU
#     pool1  max_pool2d($POOL)                   -> (1, $C1, $POOL1_OUT_H, $POOL1_OUT_W)
#     conv2  Conv2d($C1, $C2, $K, padding=$PAD)   -> (1, $C2, $CONV2_OUT_H, $POOL1_OUT_W)
#     relu2  ReLU
#     pool2  max_pool2d($POOL)                   -> (1, $C2, $POOL2_OUT_H, $POOL2_OUT_W)
#     flat   flatten(1)                          -> (1, $FLAT)
#     fc     Linear($FLAT, $NCLS)
#
# WHAT IS PORTED HERE, AND WHAT IS NOT, AND WHY. THE SHAPE IS CLOSED FOR EVERY
# LAYER: the convs' shapes come from the port's OWN `nn_conv2d`
# (`tinybendygrad/nn/layers.bend`), the pool's from the port's OWN
# `mx_pool_shape` (`tinybendygrad/mixin/movement.bend:905`), and the linear's
# from the port's OWN `nn_linear`. THE NODE IS CLOSED FOR THE CONVS AND THE
# LINEAR AND NOT FOR THE POOL: `examples/beautiful_mnist.bend`'s header names
# the reason -- `max_pool2d`'s `repeat`/`shrink_to`/`reshape`/`permute` chain
# (`tinygrad/mixin/movement.py:608-616`) is not built by the substrate, so the
# pool is a SHAPE here and not a GRAPH. **=> THE PORT CAN BUILD THIS MODEL'S
# GRAPH APART FROM THE POOLING NODE, AND IT SAYS SO INSTEAD OF FAKING THE
# POOL.**
#
# THE FOUR WALLS OF `tinybendygrad/nn/datasets.bend`, RE-EXAMINED FOR THIS MODEL:
#
#   W1 THE HTTP GET -- `Tensor.from_url(url, gunzip=True)`. **STILL A WALL, AND
#      IT IS STILL THE RIGHT WALL TO ROUTE AROUND**: the bytes are prepared on
#      the HOST (`.agents/slop/mnist/prepare_npy.py`, from the SAME four
#      `storage.googleapis.com/cvdf-datasets/mnist` files upstream's
#      `datasets.py:5` names) and written as `.npy`. The port's `.npy` path in
#      `tinybendygrad/nn/datasets.bend` owns the SHAPE ARITHMETIC of those
#      files, which is the part that is arithmetic and not a socket.
#   W2 THE TENSORS THEMSELVES -- "`.reshape`, `.astype` AND `np.frombuffer`
#      HAVE NO COUNTERPART HERE: `Tensor` IN `tensor.bend` IS A UOP SLOT IN AN
#      ARENA, NOT A BUFFER". **THIS WALL IS THE ONE THE END-TO-END RUN GOES
#      THROUGH, AND IT IS NOT A WALL FOR THE EXECUTOR.** `Tensor` in
#      `tensor.bend` is a graph node; the BEND DEVICE's tensors are buffers in
#      the host allocator. The run therefore drives the model through upstream
#      tinygrad's OWN `Tensor` on the port's OWN device -- the device whose
#      kernels are the port's compiled executor -- and reads the result back
#      through `BendProgram.__call__`'s `PACKET.out` copy. **=> THE DEVICE READ
#      IS NOT A NEW SUBSYSTEM: IT IS THE EXECUTOR's OUTPUT COMING BACK.**
#   W3 `tarfile`/`pickle` FOR CIFAR -- **NOT REACHED BY THIS MODEL.** MNIST has
#      no tar and no pickle; the label file is a flat `uint8` vector and the
#      image file is a `uint8` matrix. The wall is untouched, and it is named
#      here so that "not reached" is a measurement and not an omission.
#   W4 `os.path.isfile` -- **THE PORT's OWN `.npy` PATH DOES NOT CALL IT**, and
#      that is a DELIBERATE OMISSION AND NOT AN ACCIDENT: the `.npy` header's
#      own length field IS the presence check, because a truncated `.npy` fails
#      to decode, and a file that is not there fails to open. The port's path
#      therefore answers "is this file here" with the SAME question the host
#      asked when it opened it.
#
# THE ROWS. `mn_row.line(nm, got, want)` prints `nm got=<...> want=<...>` -- the
# spelling `tinybendygrad/nn/layers.bend` uses. **A PRINTED ROW IS A LABEL**:
# `examples/beautiful_mnist.bend`'s own header records that a one-line
# regression in a copy leaves `bend --check-only` GREEN, because the port's
# compilation IR is outside the law system by design. So the COMPARER is
# `.agents/slop/mnist/oracle_shapes.py`, and it compares the port's `got=`
# against CPython's OWN `nn.Conv2d(...)(x).shape`, `Tensor.max_pool2d(...)`
# and `nn.Linear(...)(x).shape` -- not against this file's `want=`. The `want=`
# is here so that a reader can see both without running anything.
#
# THE IMPORT SET IS THE PORT's. `layers.bend` brings the conv/linear/relu, and
# `mixin/movement.bend` brings `_pool`'s output shape. Nothing here reimplements
# a layer.

import Base
import ./../tensor.bend as T
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../mixin/movement.bend as MX
import ./layers.bend as L

# ===========================================================================
# THE CONSTANTS. Every one of them is in `model.py` too, and the generator
# copied them from there.
# ===========================================================================

def MN_IN_H() -> U32: $IN_H
def MN_IN_W() -> U32: $IN_W
def MN_C1() -> U32: $C1
def MN_C2() -> U32: $C2
def MN_K() -> U32: $K
def MN_PAD() -> U32: $PAD
def MN_POOL() -> U32: $POOL
def MN_NCLS() -> U32: $NCLS
def MN_FLAT() -> U32: $FLAT
def MN_POOL1_OUT_H() -> U32: $POOL1_OUT_H
def MN_POOL1_OUT_W() -> U32: $POOL1_OUT_W
def MN_POOL2_OUT_H() -> U32: $POOL2_OUT_H
def MN_POOL2_OUT_W() -> U32: $POOL2_OUT_W
def MN_NPARAM() -> U32: $NPARAM

# THE SHAPE, as a four-field record: (n, c, h, w). A 2-D shape is the same
# record with h = w = 1, which is what `examples/beautiful_mnist.bend` does and
# for the same reason -- one record is one fewer type, and every shape in this
# model has an explicit width.
type MnShape is Data:
  MnShape{n: U32, c: U32, h: U32, w: U32}

def mn_in() -> MnShape: MnShape{1, 1, MN_IN_H(), MN_IN_W()}

# `H.prod_u32` is `helpers.bend`'s `prod` (helpers.py:14), and the BUFFER a
# tensor is built over needs its ELEMENT count.
def mn_prod(xs: List<&2, U32>) -> U32: H.prod_u32(xs)

# THE TENSOR FIXTURE: a BUFFER plus a RESHAPE. A BUFFER ALONE IS UNUSABLE --
# `fold.shape` does not answer a BUFFER, and every identity test in the layers
# reads its source's shape. This is `tinybendygrad/nn/layers.bend`'s own
# `nn_row.t`, and it is copied rather than re-derived.
def mn_t(ns: List<&2, U32>, slot: U32, size: U32) -> T.Tensor:
  MX.mxw_reshape(MX.mxw_buf(O.Arena.empty(), slot, size), ns)

# THE PORT's OWN SHAPE SPELLING: `MX.mx_show` joins the dims with a comma and
# NO parentheses. CPython's `Tensor.shape` prints as a TUPLE, so the port's
# spelling is the dims and the oracle converts.
def mn_show(xs: List<&2, U32>) -> String: MX.mx_show(xs)

def mn_shp(t: T.Tensor) -> String:
  mn_show(Maybe.default(&2, List<&2, U32>, L.nn_shape(t), Nil{}))

# `_pool`'s OUTPUT SHAPE, `noop ++ o_ ++ k_`, which is `mx_pool_shape`
# (movement.bend:905) and is NOT TRUNCATED: the reduce at `op.py:1553` and
# `op.py:1371` is what eats the `k_` half. The row `mnist_pool1_full` prints
# the unreduced list so the `k_` half stays visible.
def mn_pool_full(shp: List<&2, U32>) -> List<&2, U32>:
  MX.mx_pool_shape(shp, [MN_POOL(), MN_POOL()], [MN_POOL(), MN_POOL()], [1, 1])

# THE REDUCED POOL SHAPE -- what `Tensor.max_pool2d` RETURNS, which is the
# `noop ++ o_` half with the kernel dims eaten. The TAKE IS LOAD-BEARING HERE
# and not in `examples/beautiful_mnist.bend`: there the walk read four indices
# and the two trailing dims were unread, so the take was dead code; here the
# reduced shape is the INPUT SHAPE of the next layer, and its element count is
# the size of the next BUFFER.
def mn_pool_out(shp: List<&2, U32>) -> List<&2, U32>:
  List.take(&2, U32, mn_pool_full(shp), 4n)

# THE CONV, through the port's OWN `nn_conv2d` (layers.bend:927). The
# argument order is `groups, stride, dilation, pad_v, padding, bias`, and
# `padding = None{}` with `pad_v = $PAD` is upstream's `padding=$PAD` --
# `nn_pads` (layers.bend) turns the int into the flat four-element list
# `resolve_pool_pads` returns.
def mn_conv(+shp: List<&2, U32>, +wshp: List<&2, U32>) -> Maybe<&2, T.Tensor>:
  L.nn_conv2d(mn_t(shp, 0, mn_prod(shp)),
              mn_t(wshp, 1, mn_prod(wshp)),
              1, 1, 1, MN_PAD(), None{}, None{})

# `nn.Linear.__call__` -- nn/__init__.py:180: `x(n, in)`, `weight(out, in)`,
# `bias(out)`.
def mn_linear(+shp: List<&2, U32>, +wshp: List<&2, U32>, +bshp: List<&2, U32>) -> Maybe<&2, T.Tensor>:
  L.nn_linear(mn_t(shp, 0, mn_prod(shp)),
              mn_t(wshp, 1, mn_prod(wshp)),
              Some{mn_t(bshp, 2, mn_prod(bshp))})

# THE LINEAR WITHOUT ITS BIAS. CPython's `x.dot(w)` on a `(1,392)` and a
# `(392,10)` has NO bias add, and the port's `nn_linear` with `None{}` has none
# either -- so the two graphs are comparable. WITH the bias they are not: the
# port's bias is a BUFFER and CPython's is a CONT-backed ADD, and the oracle
# compares that difference rather than hiding it.
def mn_linear_nb(+shp: List<&2, U32>, +wshp: List<&2, U32>) -> Maybe<&2, T.Tensor>:
  L.nn_linear(mn_t(shp, 0, mn_prod(shp)), mn_t(wshp, 1, mn_prod(wshp)), None{})

# THE PORT's GRAPH SIGNATURE, `MX.mxw_sig` (movement.bend:1380): node count,
# root op, source count and source ops in ONE string, because a fixture that
# drops one of the four can be green on a wrong graph.
def mn_sig(+t: T.Tensor) -> String: MX.mxw_sig(T.Tensor.ar(t), T.Tensor.u(t))

def mn_sig_of(m: Maybe<&2, T.Tensor>) -> String:
  match m:
    case Some{t}: mn_sig(t)
    case None{}: "NONE"

def mn_shp_of(m: Maybe<&2, T.Tensor>) -> String:
  match m:
    case Some{t}: mn_shp(t)
    case None{}: "NONE"

def mn_row.line(nm: String, got: String, want: String) -> IO(Unit):
  IO.print(String.concat([nm, " got=", got, " want=", want]))

# ===========================================================================
# THE ROWS.
# ===========================================================================

# THE MODEL's INPUT, and the shape the walk starts from.
def mn_row_in() -> IO(Unit):
  mn_row.line("mnist_in_shape", mn_show([1, 1, MN_IN_H(), MN_IN_W()]), "$SHAPE_IN")

# CONV1: the port's own `nn_conv2d` over the model's own input shape.
def mn_row_conv1() -> IO(Unit):
  do IO<Unit>:
    mn_row.line("mnist_conv1_shape", mn_shp_of(mn_conv([1, 1, MN_IN_H(), MN_IN_W()], [MN_C1(), 1, MN_K(), MN_K()])),
      "$SHAPE_CONV1")
    mn_row.line("mnist_conv1_sig", mn_sig_of(mn_conv([1, 1, MN_IN_H(), MN_IN_W()], [MN_C1(), 1, MN_K(), MN_K()])),
      "SEE-ORACLE")

# RELU1: `Tensor.relu` (elementwise.py:674) -- the shape is its input's.
def mn_row_relu1() -> IO(Unit):
  mn_row.line("mnist_relu1_shape",
    mn_shp(L.nn_relu(mn_t([1, MN_C1(), MN_IN_H(), MN_IN_W()], 0, mn_prod([1, MN_C1(), MN_IN_H(), MN_IN_W()])))),
    "$SHAPE_RELU1")

# POOL1: `Tensor.max_pool2d(2)` (op.py:1333). `s_ = stride if stride is not None
# else k_` at op.py:1367 is the whole of the `i // 2`, and it is why the stride
# list is [2,2] and NOT [1,1].
def mn_row_pool1() -> IO(Unit):
  do IO<Unit>:
    mn_row.line("mnist_pool1_full", mn_show(mn_pool_full([1, MN_C1(), MN_IN_H(), MN_IN_W()])),
      "$POOL1_FULL")
    mn_row.line("mnist_pool1_shape", mn_show(mn_pool_out([1, MN_C1(), MN_IN_H(), MN_IN_W()])),
      "$SHAPE_POOL1")

# CONV2: the port's own `nn_conv2d` over the POOL1 OUTPUT SHAPE.
def mn_row_conv2() -> IO(Unit):
  do IO<Unit>:
    mn_row.line("mnist_conv2_shape",
      mn_shp_of(mn_conv([1, MN_C1(), MN_POOL1_OUT_H(), MN_POOL1_OUT_W()], [MN_C2(), MN_C1(), MN_K(), MN_K()])),
      "$SHAPE_CONV2")
    mn_row.line("mnist_conv2_sig",
      mn_sig_of(mn_conv([1, MN_C1(), MN_POOL1_OUT_H(), MN_POOL1_OUT_W()], [MN_C2(), MN_C1(), MN_K(), MN_K()])),
      "SEE-ORACLE")

# POOL2, on the conv2 output shape.
def mn_row_pool2() -> IO(Unit):
  do IO<Unit>:
    mn_row.line("mnist_pool2_full",
      mn_show(mn_pool_full([1, MN_C2(), MN_POOL1_OUT_H(), MN_POOL1_OUT_W()])),
      "$POOL2_FULL")
    mn_row.line("mnist_pool2_shape",
      mn_show(mn_pool_out([1, MN_C2(), MN_POOL1_OUT_H(), MN_POOL1_OUT_W()])),
      "$SHAPE_POOL2")

# THE FLATTEN: `x.flatten(1)` (movement.py:345) collapses dims 1.. into one.
def mn_row_flat() -> IO(Unit):
  mn_row.line("mnist_flat",
    U32.show(U32.mul(MN_C2(), U32.mul(MN_POOL2_OUT_H(), MN_POOL2_OUT_W()))),
    "$FLAT")

# THE LINEAR, through the port's OWN `nn_linear`.
def mn_row_fc() -> IO(Unit):
  do IO<Unit>:
    mn_row.line("mnist_fc_shape", mn_shp_of(mn_linear([1, MN_FLAT()], [MN_NCLS(), MN_FLAT()], [MN_NCLS()])), "1,$NCLS")
    mn_row.line("mnist_fc_sig", mn_sig_of(mn_linear([1, MN_FLAT()], [MN_NCLS(), MN_FLAT()], [MN_NCLS()])), "SEE-ORACLE")
    mn_row.line("mnist_fc_sig_nobias",
      mn_sig_of(mn_linear_nb([1, MN_FLAT()], [MN_NCLS(), MN_FLAT()])), "SEE-ORACLE")

# THE PARAMETER COUNT, the way upstream counts it: every element of every
# parameter tensor -- `nn.Conv2d` has a weight (cout,cin,k,k) and a bias
# (cout); `nn.Linear` has a weight (out,in) and a bias (out).
def mn_row_nparam() -> IO(Unit):
  mn_row.line("mnist_nparam", U32.show(MN_NPARAM()), "$NPARAM")

def main() -> IO(Unit):
  do IO<Unit>:
    mn_row_in()
    mn_row_conv1()
    mn_row_relu1()
    mn_row_pool1()
    mn_row_conv2()
    mn_row_pool2()
    mn_row_flat()
    mn_row_fc()
    mn_row_nparam()
''')


def main() -> int:
    C1, C2, K, PAD, POOL, NCLS = M.C1, M.C2, M.K, M.PAD, M.POOL, M.NCLS
    FLAT = M.FLAT
    # the parameter count, the way upstream counts it: every element of every
    # parameter tensor. `nn.Conv2d` has a weight (cout,cin,k,k) and a bias
    # (cout); `nn.Linear` has a weight (out,in) and a bias (out).
    n_conv1 = C1 * 1 * K * K + C1
    n_conv2 = C2 * C1 * K * K + C2
    n_fc = NCLS * FLAT + NCLS
    n_params = n_conv1 + n_conv2 + n_fc

    src = TEMPLATE.substitute(
        IN_H=M.IN_H,
        IN_W=M.IN_W,
        C1=C1,
        C2=C2,
        K=K,
        PAD=PAD,
        POOL=POOL,
        NCLS=NCLS,
        FLAT=FLAT,
        CONV1_OUT_H=M.CONV1_OUT_H,
        POOL1_OUT_H=M.POOL1_OUT_H,
        POOL1_OUT_W=M.IN_W // POOL,
        CONV2_OUT_H=M.CONV2_OUT_H,
        POOL2_OUT_H=M.POOL2_OUT_H,
        POOL2_OUT_W=M.IN_W // POOL // POOL,
        POOL1_FULL=f"1,{C1},{M.POOL1_OUT_H},{M.IN_W // POOL},2,2",
        POOL2_FULL=f"1,{C2},{M.POOL2_OUT_H},{M.IN_W // POOL // POOL},2,2",
        SHAPE_IN=shape4(1, M.IN_H, M.IN_W),
        SHAPE_CONV1=shape4(C1, M.CONV1_OUT_H, M.IN_W),
        SHAPE_RELU1=shape4(C1, M.IN_H, M.IN_W),
        SHAPE_POOL1=shape4(C1, M.POOL1_OUT_H, M.IN_W // POOL),
        SHAPE_CONV2=shape4(C2, M.CONV2_OUT_H, M.IN_W // POOL),
        SHAPE_POOL2=shape4(C2, M.POOL2_OUT_H, M.IN_W // POOL // POOL),
        NPARAM=n_params,
    )

    OUT.write_text(src)
    print(f"# wrote {OUT} ({len(src.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
