# examples/beautiful_mnist.bend -- tinygrad/examples/beautiful_mnist.py (48 lines).
#
# THE UNIT IS A LAYERED GRAPH, NOT A KERNEL, and the split in this file is Python's.
# Four things live in `examples/beautiful_mnist.py` and they sit at four different
# levels of "is this a graph fact":
#
#   1. THE MODEL DEF, `Model.__init__` (:9-16): a `list[Callable[[Tensor],Tensor]]`.
#      The CALLABLES are not data and Bend has no closures, so what is portable is
#      what `nn/__init__.py` does INSIDE each layer constructor -- and that is the
#      pure-integer shape arithmetic `nn/__init__.bend`'s own header names as "the
#      best remaining candidate in the file". PORTED AND GATED, below.
#   2. THE FORWARD GRAPH, `Model.__call__` (:19) = `x.sequential(self.layers)`, and
#      `sequential` (op.py:1243) is `functools.reduce(lambda x,f: f(x), ll, self)`.
#      Graph construction, so it is portable -- but only for the layers whose mixin
#      method the substrate can build. PORTED for relu/linear/log_softmax, WALLED for
#      conv2d/max_pool2d, and the wall is the one `mixin/op.bend` already records.
#   3. THE TRAINING STEP, `train_step` (:23-27): `zero_grad`, `randint`, forward,
#      `sparse_categorical_crossentropy`, `backward`, `opt.schedule_step()`. Five of
#      those six are graph facts; `backward` is `mixin/gradient.py:20 call_gradient`
#      and is a `TODO(p3)` IN `mixin/gradient.bend` ITSELF.
#   4. THE PRETTY OUTPUT, the `trange` row (:39-43). A STRING, and the only part of
#      this example that needs no device, no fold and no graph. PORTED AND GATED.
#
# ---------------------------------------------------------------------------
# THE FOUR WALLS, each named at its Python line and at the substrate def that owns
# it. None of them is new information: an example that hid a wall behind a
# plausible-looking graph would be worse than one that names it.
#
#   W1  conv2d -- `tinygrad/mixin/op.py:1562`. The body is `_pad_constant` +
#        `._pool(HW, stride, dilation)` + a broadcast-mul + a reduce. `_pool` is
#        `mixin/movement.py:598` and `mixin/op.bend`'s W4: TWELVE lines of shape
#        arithmetic whose output shape needs `ssimplify`, which `uop/symbolic.bend`
#        does not answer, so `fold.bend`'s `dt_shape` leaves PAD/SHRINK/EXPAND/FLIP
#        un-answered (fold.bend:1620-1626). BUILDABLE, NOT CHECKABLE.
#   W2  max_pool2d -- `tinygrad/mixin/op.py:1333`, the same `_pool` with a `MAX`
#        reduce. One fewer layer than W1 and the same wall.
#   W3  ONE_HOT -- `tinygrad/mixin/op.py:1005 _one_hot_along_dim` is
#        `self.eq(arange(num_classes).reshape(...))`, and `arange` (op.py:166) is
#        `mixin/op.bend`'s W4 by inheritance: `_pool` again. So the loss's one-hot
#        and its `Y.const_like(True, dtypes.bool)` mask (op.py:1742, `creation.py:71`
#        = `expand`, which is one of the five ops `fold.bend` defers) are both walls,
#        and both are PARAMETERS of `mn_loss` -- the same boundary rule the MNIST
#        fetch obeys below.
#   W4  backward -- `tinygrad/mixin/gradient.py:20 call_gradient`, which
#        `mixin/gradient.bend:896` already records as `TODO(p3)` ITSELF ("needs
#        `CallArg.grad_fxn`, a callback"). Five subsystems, one of which is
#        `compute_gradient` (`mixin/op.bend`'s W3, `TODO(p3)` at gradient.bend:881).
#
# A FIFTH ITEM IS NOT A WALL BUT A DIVERGENCE, and it is the one that cost this file
# the most rows. `fold.bend` DEFERS PERMUTE (fold.bend:1621,
# `case O.OpsPERMUTE{}: None{}` -- `marg` -> `as_shape` -> `ssimplify`), so the fold
# does not answer a PERMUTE's DTYPE either, and `mixin/op.bend`'s `mo_bin`
# promotion reads that missing dtype and mints a `CAST`. MEASURED on `dot`
# (op.py:359) with 2-D operands: the port builds 9 nodes where CPython builds 15,
# and the difference is a `CAST/1` before the `MUL` and a missing `PERMUTE/1` from
# the reduce. So THE 2-D `dot`/`linear` ARM IS NOT GATED GREEN and the honest
# statement is that this file's forward lane is the 1-D one, where no PERMUTE is
# built. `unverified_lin2` is printed under a name that says so. This is a defect in
# `uop/fold.bend`, which is READ-ONLY here, so it is REPORTED and routed around.
#
# `mixin/op.bend`'s `mo_permute` has the matching arena defect, MEASURED as a
# `NOOP/0` on op.bend's own recipe: it builds the node in `Tensor.ar(t)` and then
# wraps in that SAME arena, so the PERMUTE is interned into an arena one node short
# of the `T.AOrder` tuple it reads. `mn_perm` below is the same one-liner with the
# arena rule applied, and `tensor.bend` and `mixin/op.bend` both set the precedent
# for spelling a movement helper here rather than calling a defective one.
#
# ---------------------------------------------------------------------------
# THE FOREIGN SEAM IS A PARAMETER, and it is `mnist()` at
# `tinygrad/examples/beautiful_mnist.py:33` -- `Tensor.from_url(base_url+file,
# gunzip=True)` (`tinygrad/nn/datasets.py:4`), an HTTP GET plus a gzip decode, which
# is not a graph fact at all. There is no seam to take: Bend has no HTTP client and
# `IO` is only a print. So every entry point below takes its data as parameters.
# TODO(p3) examples/beautiful_mnist.py:33  `mnist(fashion=getenv("FASHION"))` --
#   `Tensor.from_url` (nn/datasets.py:4). A foreign seam, not a wall: hand the port
#   four buffers and the port is complete.
# TODO(p3) examples/beautiful_mnist.py:25  `Tensor.randint(getenv("BS", 512),
#   high=X_train.shape[0])` -- `mixin/rand.py` is not ported, so the sampled batch is
#   `mn_step`'s first parameter.
# TODO(p3) examples/beautiful_mnist.py:24  `opt.zero_grad()` -- optim.py:33 is
#   `Tensor.grad_set`, which IS ported (`optim.bend`'s `op_zg_params`), but the grads
#   themselves only exist once W4 lands, so the call has nothing to act on.
# TODO(p3) examples/beautiful_mnist.py:36  the optimizer dispatch
#   `(nn.optim.Muon if getenv("MUON") else nn.optim.SGD if getenv("SGD") else
#   nn.optim.Adam)(...)` -- a `Config` read (P6) over three optimizers. The `Adam`
#   arm is `LAMB(..., adam=True)` (optim.py:139) and is `optim.bend`'s `op_lamb`,
#   whose gate row is RED (`optim.bend:1348`, `unverified_lamb`: 1 node against
#   CPython's 49), so `unverified_adam` CALLS it and does not CLAIM it.
# TODO(p3) examples/beautiful_mnist.py:30  `argmax(axis=1)` -- MEASURED ABSENT from
#   the substrate (`rg -n 'mo_argmax' tinybendygrad/mixin/op.bend` is empty). The
#   real graph is 52 nodes with PAD, SHRINK and two PERMUTEs, i.e. `_pool` again, so
#   `get_test_acc`'s first half has no gate row here at all.
# TODO(p3) examples/beautiful_mnist.py:22  `@TinyJit`, and :31 the jit'd
#   `get_test_acc` -- the JIT is the schedule cluster, `tensor.bend`'s WALL 4, which
#   belongs to another unit.
# TODO(p3) examples/beautiful_mnist.py:40  `GlobalCounters.reset()` -- runtime
#   counters, P6.
# TODO(p3) examples/beautiful_mnist.py:46  `TARGET_EVAL_ACC_PCT` and the `colored`
#   print -- `getenv` is `helpers.bend`'s `getenv_str` (an `IO(String)`) and
#   `colored` is ported, so this arm is small; it is left for a later pass rather
#   than half-ported here.
#
# ---------------------------------------------------------------------------
# THE GATE. Nothing is executed and no device is touched. Every row is either a
# STRING (the layer table, the shape walk, the printed row) or the SIGNATURE of a
# lazy graph (a `toposort` with each node's op and src COUNT), which is the format
# `tinybendygrad/mixin/op.bend` and `nn/optim.bend` already print and what
# `.agents/slop/beautiful-mnist-gate.py` prints on the CPython side, so the two
# lanes diff byte for byte:
#
#     python3 .agents/slop/beautiful-mnist-gate.py                > /tmp/py.txt
#     ./bin/bend examples/beautiful_mnist.bend                     > /tmp/bd.txt
#     ./bin/bend examples/beautiful_mnist.bend -o /tmp/bmn && /tmp/bmn > /tmp/nat.txt
#     diff /tmp/py.txt /tmp/bd.txt ; diff /tmp/py.txt /tmp/nat.txt
#
# EVERY ROW IS DERIVED FROM CPYTHON, never restated from this file, because a row
# restated from the port agrees with a wrong port. Three kinds of row exist here
# because three kinds of bug are invisible to the others: the COUNT (`mdl_count`),
# the ORDER of a signature (`relu2`'s `CONST` before its `BUFFER`), and the SHAPE
# (`mdl_walk`), which no signature can print -- `RESHAPE(REDUCE, CONST(4))` and
# `RESHAPE(REDUCE, CONST(1))` are the SAME signature.
#
# THE GATE HAS TWENTY-FIVE SHARED ROWS and four BEND-ONLY ones, and every one of the four
# is named so that nobody can read it as a claim. `.agents/slop/beautiful-mnist-gate.sh`
# filters them BY NAME, not by position, so a row that MOVES is never silently dropped:
#
#   row_round_2.3456   `H.f32_fixed(2.3456, 2n) == "2.35"` -- prints FALSE
#   row_round_2.30     `H.f32_fixed(2.3, 2n) == "2.30"`   -- prints FALSE
#   unverified_lin2    the 2-D `dot` graph, 11 nodes against CPython's 15
#   unverified_adam    `nn.optim.Adam` == `LAMB(adam=True)` (optim.py:139), 1 node
#
# The two `row_round_*` rows are the most useful thing in this file: `helpers.bend`'s
# `f32_fixed` is a TRUNCATING `%.2f` and CPython's f-string is not, so this example's
# PRETTY OUTPUT IS WRONG for roughly half of all values, and a real MNIST loss is on the
# wrong half of that line. See the rows and `nn_row_out`'s comment.

import Base
import ../tinybendygrad/tensor.bend as T
import ../tinybendygrad/helpers.bend as H
import ../tinybendygrad/LAWS/spec.bend as S
import ../tinybendygrad/uop/ops.bend as O
import ../tinybendygrad/mixin/op.bend as MO
import ../tinybendygrad/mixin/elementwise.bend as E
import ../tinybendygrad/nn/optim.bend as OP

# `String.concat` takes a `List<&2, String>`, and every column below is a list, so
# the parenthesis depth of a row is three and not nine. This is the house rule from
# `helpers.bend`'s own `colored`: build the string, do not nest the builders.
def mn_cat(xs: List<&2, String>) -> String: String.concat(xs)

# ===========================================================================
# 1. THE MODEL DEF. `Model.__init__` (examples/beautiful_mnist.py:9-16) is a list
# of CALLABLES, and a callable is not a value here, so each entry is its layer's
# CONSTRUCTOR ARGUMENTS -- which is what `nn/__init__.py` turns into shapes, and
# shapes are integers.
#
# The order is Python's, and it is the model's order, so the table is the table.
# `Tensor.relu` (:10) and `Tensor.max_pool2d` (:12) are methods on the Tensor, so
# they carry no arguments at all -- `MnRelu{}` and `MnPool{}` with none, which is
# the honest spelling of "there is nothing here". `lambda x: x.flatten(1)` (:16)
# carries its ONE argument, so `MnFlat` carries it.
# ===========================================================================

type MnLayer is Data:
  MnConv{cin: U32, cout: U32, k: U32}
  MnRelu{}
  MnBn{c: U32}
  MnPool{}
  MnFlat{d: U32}
  MnLin{i: U32, o: U32}

# `H.prod` (helpers.py:14) is `functools.reduce(operator.mul, x, 1)`, and
# `helpers.bend`'s `prod_u32` IS that, so this is the call and not a second copy.
# `nn/__init__.py:104`'s `prod(self.kernel_size)` is the only `prod` on this path.
def mn_prod(xs: List<&2, U32>) -> U32: H.prod_u32(xs)

# `self.kernel_size = make_tuple(kernel_size, 2)` -- nn/__init__.py:98, and
# `make_tuple` (helpers.py:50) is `(x,)*cnt if isinstance(x, int) else tuple(x)`.
# Every `nn.Conv2d` in this example passes an int (`5`, `5`, `3`, `3`), so the int
# arm is the only reachable one and `k` IS `self.kernel_size[0] == kernel_size[1]`.
def mn_ktuple(+k: U32) -> List<&2, U32>: [k, k]

# `d*(k-1)//2` with `d == 1` is `(k-1)//2` -- nn/__init__.py:102.
def mn_pad_lo(k: U32) -> U32: U32.div(U32.sub(k, 1), 2)

# The SECOND element of that pair, `d*(k-1) - d*(k-1)//2` -- nn/__init__.py:102.
def mn_pad_hi(+k: U32) -> U32: U32.sub(U32.sub(k, 1), mn_pad_lo(k))

# `flatten(pad)` over `pad = [(d*(k-1)//2, d*(k-1)-d*(k-1)//2) for d,k in zip(
# make_tuple(dilation, 2)[::-1], self.kernel_size[::-1])]` -- nn/__init__.py:102-104,
# reached only when `padding` is the string `'same'`. This example passes NO
# padding (nn/__init__.py:96's default is `0`), so the `'same'` arm does NOT FIRE for
# any layer here and the shape walk uses `i - k + 1`. It is ported anyway because it
# is the arithmetic a reader of `Conv2d` looks for first, and `mdl_pad*` pins that
# the model does not take it.
def mn_pad_same(+k: U32) -> List<&2, U32>:
  [mn_pad_lo(k), mn_pad_hi(k), mn_pad_lo(k), mn_pad_hi(k)]

def mn_pad_str(+k: U32) -> String:
  mn_cat([U32.show(mn_pad_lo(k)), ",", U32.show(mn_pad_hi(k)), ",",
    U32.show(mn_pad_lo(k)), ",", U32.show(mn_pad_hi(k))])

# `scale = 1 / math.sqrt(in_channels * prod(self.kernel_size))` -- nn/__init__.py:104.
# `F32.sqrt` and `F32.div` are laws; `U32.to_f32` is an unfilled law that
# `tensor.bend`'s header says live code may not call, but `mixin/op.bend`'s rule 5
# MEASURED it working on bend 2.0.34 (`F32.show(U32.to_f32(7))` prints `7` in both
# lanes) and `helpers.bend`'s own `f32_frac.next` calls it. So it is a call, and
# `mdl_scale` pins the f32 this expression produces against CPython's
# `struct.pack('f', 1/math.sqrt(...))`.
def mn_scale(ci: U32, k: U32) -> F32:
  F32.div(1.0, F32.sqrt(U32.to_f32(U32.mul(ci, mn_prod(mn_ktuple(k))))))

# `bound = 1 / math.sqrt(in_features)` -- nn/__init__.py:173. NOT a call to
# `mn_scale`: the two lines are separate in Python (nn/__init__.py:104 and :173) and a
# shared helper would be a NEW abstraction, which the brief forbids.
def mn_bound(i: U32) -> F32: F32.div(1.0, F32.sqrt(U32.to_f32(i)))

# THE LAYER TABLE. Fourteen entries, in Python's order, from
# examples/beautiful_mnist.py:9-16. `MnPool` is `Tensor.max_pool2d` at :12 and :15
# and takes no argument in this example.
def mn_layers() -> List<&2, MnLayer>:
  [MnConv{1, 32, 5}, MnRelu{}, MnConv{32, 32, 5}, MnRelu{}, MnBn{32}, MnPool{},
   MnConv{32, 64, 3}, MnRelu{}, MnConv{64, 64, 3}, MnRelu{}, MnBn{64}, MnPool{},
   MnFlat{1}, MnLin{576, 10}]

def mn_len() -> U32: U32.from_nat(List.length(&2, MnLayer, mn_layers()))

# THE NAME COLUMN: `type(l).__name__` is what a CPython oracle prints for each entry.
# It cannot catch a transposed layer, which is what the argument column is for.
def mn_name.of(l: MnLayer) -> String:
  match l:
    case MnConv{cin, cout, k}: "conv2d"
    case MnRelu{}: "relu"
    case MnBn{c}: "batchnorm"
    case MnPool{}: "max_pool2d"
    case MnFlat{d}: "flatten"
    case MnLin{i, o}: "linear"

# THE ARGUMENT COLUMN, which is the part a signature cannot see: `nn.Conv2d(1, 32,
# 5)` and `nn.Conv2d(32, 1, 5)` build DIFFERENT graphs and print the SAME name.
# `c` is `out_channels` for a conv, `sz` for a BatchNorm, `start_dim` for the flatten
# and `(in_features, out_features)` for a Linear.
def mn_args(l: MnLayer) -> String:
  match l:
    case MnConv{cin, cout, k}: mn_cat([U32.show(cin), ",", U32.show(cout), ",", U32.show(k)])
    case MnRelu{}: ""
    case MnBn{c}: U32.show(c)
    case MnPool{}: ""
    case MnFlat{d}: U32.show(d)
    case MnLin{i, o}: mn_cat([U32.show(i), ",", U32.show(o)])

def mn_cell(+l: MnLayer) -> String: mn_cat([mn_name.of(l), "(", mn_args(l), ")"])

def mn_table.go(+ls: List<&2, MnLayer>, acc: String) -> String:
  match ls:
    case Nil{}: acc
    case l <> +t: mn_table.go(t, mn_cat([acc, mn_cell(l), " "]))

def mn_table() -> String: mn_table.go(mn_layers(), "")

# `nn.BatchNorm(sz, eps=1e-5, affine=True, track_running_stats=True, momentum=0.1)`
# -- nn/__init__.py:33. Five parameters and FOUR TENSORS: `weight = Tensor.ones(sz)`
# and `bias = Tensor.zeros(sz)` (:36-37), `num_batches_tracked = Tensor.zeros(dtype=
# 'long')` (:39) and `running_mean`/`running_var = Tensor.zeros(sz)`/`Tensor.ones(sz)`
# (:40). The three `is_param_(False)` flags (nn/__init__.py:39-40) are `tensor.py:125`
# and ARE ported (`T.tn_is_param_`); they are a flag and do not change a shape, so
# `mdl_bn` pins the four shapes and `nn/optim.bend`'s `op_filter` pins the flag.
def mn_bn.go(+s: String) -> String:
  mn_cat(["w=(", s, ",) b=(", s, ",) rm=(", s, ",) rv=(", s, ",) nbt=(1,)"])

def mn_bn(l: MnLayer) -> String:
  match l:
    case MnBn{c}: mn_bn.go(U32.show(c))
    case _: ""

# THE CONV AND LINEAR PARAMETER SHAPES. `Tensor.uniform(out_channels,
# in_channels//groups, *self.kernel_size, ...)` (nn/__init__.py:105) with
# `groups == 1`, `Tensor.uniform(out_channels, ...)` (:106) for the bias, and
# `Tensor.uniform(out_features, in_features, ...)` / `Tensor.uniform(out_features,
# ...)` (nn/__init__.py:174-175). `groups == 1` is the model's value (nn/__init__.py:97
# 's default) so `in_channels//groups` IS `in_channels`; the division is not written,
# because a row that cannot fire is a row that cannot be wrong, and `mdl_conv0_w` is
# the row that says which arm is live.
# `self.kernel_size` is printed TWICE and `k` is read twice in one body, and a `match`
# binder cannot be `+`, so the arm is a CALL into a def whose parameters can be. This
# is the same reason `mo_reshape.pick` is a def.
def mn_conv_w.go(+cin: U32, +cout: U32, +k: U32) -> String:
  mn_cat([U32.show(cout), "x", U32.show(cin), "x", U32.show(k), "x", U32.show(k)])

def mn_conv_w(l: MnLayer) -> String:
  match l:
    case MnConv{cin, cout, k}: mn_conv_w.go(cin, cout, k)
    case _: ""

def mn_conv_b(l: MnLayer) -> String:
  match l:
    case MnConv{cin, cout, k}: mn_cat(["(", U32.show(cout), ",)"])
    case _: ""

def mn_lin_w(l: MnLayer) -> String:
  match l:
    case MnLin{i, o}: mn_cat(["(", U32.show(o), ",", U32.show(i), ")"])
    case _: ""

# THE SCALE COLUMN, and it is HEX f32 BITS and not a decimal, which is a correction
# this file's first draft needed. `f"{scale:.6f}"` was the obvious spelling and it is
# WRONG twice over: `H.f32_fixed` TRUNCATES (see `row_round_*`), and
# `1/sqrt(32*3*3)` = 0.0589255653321743 truncates to `0.058925` where CPython's
# `printf` rounds to `0.058926` -- so two of this model's four scales would DISAGREE with
# CPython through no bug of the port's own. The BITS are exact on both sides:
# `F32.bits` on the Bend lane and `struct.pack('>f', x).hex()` on the CPython lane.
# A scale column that cannot see a one-ULP error is a column that cannot be wrong
# about one either, and this model's four scales differ at the fifth decimal, so six
# decimals is the precision the claim needs.
# `"0123456789abcdef"[d]` is Python's own spelling and it is what makes this a TABLE
# rather than arithmetic, so the digit alphabet lives in one place and
# `mn_hexdig_u32` is the only place that indexes it.
# `"0123456789abcdef"[d]` is Python's own spelling of the digit alphabet, and it is
# TWO branches and not a table: `d < 10` is `'0'+d` and `d >= 10` is `'a'+d-10`, so
# the offsets are 48 and 87. The test is a `Bool` PARAMETER because a `match` may not
# scrutinise a call (rule 1) and `U32.is_lt` is one.
def mn_hexdig_u32.of(lt: Bool, d: U32) -> U32:
  match lt:
    case True{}: U32.add(48, d)
    case _: U32.add(87, d)

def mn_hexdig_u32(+d: U32) -> U32: mn_hexdig_u32.of(U32.is_lt(d, 10), d)

def mn_hexdig(d: U32) -> String: String.from_list([Char.from_u32(mn_hexdig_u32(d))])



# EIGHT DIGITS ALWAYS, MOST SIGNIFICANT FIRST, so a leading zero nibble is printed --
# which is the whole reason the countdown is a parameter and not "while v != 0": an f32
# whose top nibble is 0 (every magnitude below 2^-1, which is half of this column's
# values if `bound` were smaller) would print seven digits and CPython prints eight.
# The digit is `v >> (4*(n-1)) & 15` -- `U32.shrn` and `U32.mod` are the two laws, and
# `mn_shift` is a def because the pattern binder `p` is read twice and a `+` on a
# binder is what `Succ{+p}` spells.
def mn_shift(p: Nat) -> Nat: Nat.mul(4n, p)

def mn_hexdig_n(v: U32) -> String: mn_hexdig(U32.mod(v, 16))

def mn_f32hex.go(n: Nat, +v: U32, acc: String) -> String:
  match n:
    case 0n: acc
    case Succ{+p}: mn_f32hex.go(p, v, String.append(acc, mn_hexdig_n(U32.shrn(v, mn_shift(p)))))

def mn_f32hex(x: F32) -> String: mn_f32hex.go(8n, F32.bits(x), "")

def mn_scale_col(l: MnLayer) -> String:
  match l:
    case MnConv{cin, cout, k}: mn_f32hex(mn_scale(cin, k))
    case MnLin{i, o}: mn_f32hex(mn_bound(i))
    case _: ""

# ===========================================================================
# 2. THE FORWARD SHAPE WALK. `x.sequential(self.layers)` (op.py:1243) reduces over the
# layer list carrying a shape, and no closures means the walk dispatches on the layer
# tag in a `match`. One def, self-call first and shrinking -- exactly the shape
# `tn_rop.ins` and `tn_iaxis.go` already use in this codebase.
#
# THE STATE IS A `Data` AND NOT FOUR `U32`s, because a `match` may not scrutinise a
# computed value (bend2-constraints rule 2) and a self-call needs ONE shrinking
# argument, so the whole walk state is one record.
# ===========================================================================

type MnShape is Data:
  MnShape{n: U32, c: U32, h: U32, w: U32}

def mn_in() -> MnShape: MnShape{1, 1, 28, 28}

# A convolution's output for kernel `k`, stride 1, dilation 1, padding 0 is `i - k +
# 1`. `_apply_ceil_mode`'s `o_` at op.py:1644 is `ceildiv(i+pB+pA - (d*(k-1)+1), s) +
# 1`, and with every pad zero, `d == 1` and `s == 1` that reduces to `i - k + 1`, so
# the `ceildiv` is gone and only the arithmetic survives. That is the honest shape of
# W1: the FORMULA ports, the graph does not.
def mn_conv_out(s: MnShape, cout: U32, +k: U32) -> MnShape:
  match s:
    case MnShape{n, c, h, w}: MnShape{n, cout, U32.add(U32.sub(h, k), 1), U32.add(U32.sub(w, k), 1)}

# `Tensor.max_pool2d` with its defaults `kernel_size=(2,2)`, `stride=None` -- which
# op.py:1334 reads as `stride == kernel_size` -- `padding=0`: `i // 2`. `_pool`
# computes it as `ceildiv(i - (k-1) - 1, s) + 1` with `s == k == 2`, which is `i//2`.
def mn_pool_out(s: MnShape) -> MnShape:
  match s:
    case MnShape{n, c, h, w}: MnShape{n, c, U32.div(h, 2), U32.div(w, 2)}

# `x.flatten(1)` -- movement.py:345, `start_dim=1`, so dims `1..ndim-1` collapse into
# one and the result is `(n, c*h*w)`. THIS FILE CARRIES IT AS A 4-FIELD RECORD WITH
# `h = w = 1`, which is a deliberate divergence: a 2-D shape and a 4-D shape with two
# unit dims are the same Tensor shape to every reader of this file, and one record is
# one fewer type. `mdl_walk` is printed as the CPython tuple, so the divergence is
# invisible in every row.
def mn_flat_out(s: MnShape) -> MnShape:
  match s:
    case MnShape{n, c, h, w}: MnShape{n, U32.mul(U32.mul(c, h), w), 1, 1}

def mn_linear_out(s: MnShape, o: U32) -> MnShape:
  match s:
    case MnShape{n, c, h, w}: MnShape{n, o, 1, 1}

# THE TAG DISPATCH, hoisted out of the walk so that each layer's line is one line.
def mn_step_shape.of(l: MnLayer, s: MnShape) -> MnShape:
  match l:
    case MnConv{cin, cout, k}: mn_conv_out(s, cout, k)
    case MnRelu{}: s
    case MnBn{c}: s
    case MnPool{}: mn_pool_out(s)
    case MnFlat{d}: mn_flat_out(s)
    case MnLin{i, o}: mn_linear_out(s, o)

def mn_walk.go(+ls: List<&2, MnLayer>, +s: MnShape) -> MnShape:
  match ls:
    case Nil{}: s
    case l <> +t: mn_walk.go(t, mn_step_shape.of(l, s))

def mn_out() -> MnShape: mn_walk.go(mn_layers(), mn_in())

# `(1, 32, 24, 24)` for a 4-D shape and `(1, 576)` for a flattened one. `h*w == 1` is
# the flattened test, and it is the PRODUCT rather than `h == 1` because every shape in
# this model has `h >= 1`, so both spellings agree here and the product is the one
# that cannot print a 4-D `(1, 10)`.
def mn_shape2(n: U32, c: U32) -> String: mn_cat(["(", U32.show(n), ",", U32.show(c), ")"])

def mn_shape4(n: U32, c: U32, h: U32, w: U32) -> String:
  mn_cat(["(", U32.show(n), ",", U32.show(c), ",", U32.show(h), ",", U32.show(w), ")"])

def mn_shape_str.of(flat: Bool, n: U32, c: U32, h: U32, w: U32) -> String:
  match flat:
    case True{}: mn_shape2(n, c)
    case _: mn_shape4(n, c, h, w)

# `h * w == 1` needs both `h` and `w` and each is read twice (once in the product,
# once in the arm), so the TEST is a def and the arms' parameters are `+`. Same rule
# as `mn_conv_w.go`.
def mn_shape_str.go(+n: U32, +c: U32, +h: U32, +w: U32) -> String:
  mn_shape_str.of(U32.is_eq(U32.mul(h, w), 1), n, c, h, w)

def mn_shape_str(s: MnShape) -> String:
  match s:
    case MnShape{n, c, h, w}: mn_shape_str.go(n, c, h, w)

# THE WALK, printed one row per layer so a reader can see WHERE the shape changes.
def mn_walk_row.go(+ls: List<&2, MnLayer>, +s: MnShape, acc: String) -> String:
  match ls:
    case Nil{}: acc
    case l <> +t:
      mn_walk_row.go(t, mn_step_shape.of(l, s),
        mn_cat([acc, mn_name.of(l), "=", mn_shape_str(mn_step_shape.of(l, s)), " "]))

def mn_walk_row() -> String: mn_walk_row.go(mn_layers(), mn_in(), "")

# THE SHAPE `nn.Linear(576, 10)` RECEIVES: the walk over the FIRST THIRTEEN layers, with
# the Linear's own `out_features` left out. It is a row and NOT `mn_out()` because
# `mn_out()` is `(1, 10)` whatever the conv and pool arithmetic does -- `out_features`
# overwrites the last dim and the batch never changes -- so it is a row no conv bug can
# move. MEASURED: M1, M3 and M4 in the mutation table below leave `mdl_out` at `(1, 10)`
# and move only `mdl_walk`. The 576 is the number the model's own last layer asserts
# (examples/beautiful_mnist.py:16), so this row is the walk AGREEING WITH THE MODEL, and
# it is the only row that says so.
# THIRTEEN ENTRIES: the fourteen-layer table with its LAST element dropped, and it is a
# self-call over the list TAIL with NO countdown, because the last element is exactly the
# one whose tail is `Nil{}` -- `x.sequential(ll[:-1])` in Python, and the stop condition
# is the EMPTY TAIL rather than a count. That is `List.length` avoided entirely, and it is
# why this def is four lines.
def mn_head13.go(+ls: List<&2, MnLayer>, +acc: List<&2, MnLayer>) -> List<&2, MnLayer>:
  match ls:
    case Nil{}: acc
    case l <> Nil{}: acc
    case l <> +t: mn_head13.go(t, List.append(&2, MnLayer, acc, [l]))

def mn_lin_in() -> MnShape: mn_walk.go(mn_head13.go(mn_layers(), Nil{}), mn_in())

# ===========================================================================
# 3. THE FORWARD GRAPH, for the layers whose mixin method BUILDS on the substrate
# today. Each recipe is the layer's `__call__` with Python's mixin method spelled out
# of what IS built, and each carries the line it ports.
#
# `nn.Linear.__call__` (nn/__init__.py:184) is `x.linear(weight, bias)` and
# `Tensor.linear` (op.py:1254) is
#     x = self.mul(weight) if len(weight.shape) == 1 else self.dot(weight)
#     return x.add(bias) if bias is not None else x
# so there are TWO arms and they are not the same graph. The 1-D-weight arm is a
# broadcast MUL and an ADD, both built. The 2-D-weight arm is `dot` and is the PERMUTE
# wall this file's header records, so `unverified_lin2` is printed under a name that
# says so.
#
# THE FIXTURE BUFFERS. `Tensor([1.,2.,3.,4.], device='PYTHON')` is ONE BUFFER and
# `Tensor([[1.,2.],[3.,4.]], device='PYTHON')` is that buffer RESHAPED, which is
# `mixin/op.bend`'s `mo_fx1d`/`mo_fx2d` and the reason its own `lit1d`/`lit2d` rows
# have the node counts they do. A BUFFER needs a device for its `ParamArg`, which is
# `tensor.bend`'s WALL 2, so the node is built here with `buffer=None` -- the one
# field of `ParamArg` that needs one -- exactly as `mixin/op.bend`'s `mo_buf4` does.
# `mn_buf1` is a CALL to nothing: it is this file's own fixture builder and the only
# reason it is spelled here rather than reused is that op.bend's `mo_buf4` hard-codes
# `size = 4`, which is right for its rows and wrong for a second bias of size 2.
# ===========================================================================

def mn_pbuf(slot: U32, size: U32, dt: S.Dt) -> O.ParamArg:
  # slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile,
  # image, buffer, bind_on_realize, val -- ops.bend's `ParamArg`, in its order.
  O.ParamArg{slot, dt, Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

def mn_buf1(ar: O.Arena, slot: U32, size: U32) -> T.Tensor:
  +f = O.UOp.new(ar, O.OpsBUFFER{}, Nil{}, O.AParam{mn_pbuf(slot, size, S.single())}, O.TNone{})
  T.tn_wrap_uop(O.Found.ar(f), O.Found.i(f))

def mn_zero() -> E.Ew: E.ECon{O.CFloat{0.0}}

# `Tensor.relu` -- elementwise.py:674: `(self > 0).where(self, 0)`, and the NOTE says
# "if you write this as self.maximum(0) the gradient is wrong, passing through half
# when self is 0", so it is a CMPLT and a WHERE and NOT a MAX. `E.ew_gt` is
# elementwise.py's own `>` and `E.ew_where` is its own `where`; both are CALLS.
def mn_relu(+x: T.Tensor) -> T.Tensor: E.ew_where(E.ew_gt(x, mn_zero()), E.ETen{x}, mn_zero())

# `Tensor.linear`'s 1-D-weight arm -- op.py:1268 `self.mul(weight)` then :1269
# `x.add(bias)`. `MO.mo_mul` and `MO.mo_add` are `mixin/op.bend`'s own, which exist
# because of its W9 (the arena-half promotion defect), so they are the CALLS and
# calling `E.ew_mul` here would be the bug op.bend's header documents.
# THE 1-D-WEIGHT ARM, and the BIAS IS BUILT INSIDE IT and not passed in, which is a
# divergence forced by the arena rule and it is worth the two sentences it costs.
# Python's `x.linear(w, bias)` is op.py:1268's MUL followed by op.py:1269's ADD over a
# `bias` that already exists, because Python's ucache is GLOBAL and interning order
# does not matter. Here a node is an INDEX into an append-only arena, so a bias
# interned BEFORE the MUL sits at the index the MUL then wants, and the MUL overwrites
# it. MEASURED: passing the bias in printed `4 BUFFER/0 BUFFER/0 MUL/2 ADD/2` -- one
# BUFFER and a CAST where CPython prints three BUFFERs, a MUL and an ADD, and the row
# would have been wrong by construction. Building the bias after the MUL puts it at the
# next free index, which is what Python's interning does implicitly.
# So the bias arrives as a SLOT and a SIZE -- the two integers `Tensor.uniform(
# out_features, ...)` (nn/__init__.py:175) fixes -- and the buffer is a fact this file
# can build with no device.
def mn_lin1(+x: T.Tensor, +w: T.Tensor, bslot: U32, bsize: U32) -> T.Tensor:
  +m = MO.mo_mul(x, w)
  MO.mo_add(m, mn_buf1(T.Tensor.ar(m), bslot, bsize))

# THE `lin1` FIXTURE, and it is a def rather than three inline calls because of THE
# ARENA RULE (tensor.bend's rule 5): three `Arena.empty()`s are three arenas and an
# index means nothing outside its own, so a fixture that built its x, its w and its b
# from separate empties would intern each of them at index 0 and print a graph with no
# MUL in it. MEASURED: that spelling printed `3 BUFFER/0 CAST/1 ADD/2` -- the MUL's
# operand was the ADD's own node, and the row would have been GREEN against a
# three-buffer oracle only by accident. ONE arena, threaded, is the fix, and it is the
# same rule `mixin/op.bend`'s header states five times over.
def mn_lin1_fx() -> T.Tensor:
  +ar = O.Arena.empty()
  +x = mn_buf1(ar, 0, 4)
  +w = mn_buf1(T.Tensor.ar(x), 1, 4)
  mn_lin1(x, w, 2, 2)

# `Tensor.linear`'s 2-D-weight arm -- op.py:1254 `self.dot(weight)` (op.py:359), which
# is `x.reshape(...)`, `w.reshape(...).transpose(-1, axis_w)`, `(x*w).sum(-1,
# dtype).cast(least_upper_dtype(...))`. The two RESHAPEs are `MO.mo_reshape`; the
# PERMUTE needs `mn_perm`; the `CAST` is fold.bend's deferred PERMUTE dtype. So the arm
# is BUILT but neither CHECKABLE nor correct, and `unverified_lin2` says so.
def mn_perm(+ar: O.Arena, t: T.Tensor, ys: List<&2, U32>) -> T.Tensor:
  +n = T.tn_mop(ar, T.Tensor.u(t), O.OpsPERMUTE{}, T.AOrder{ys})
  T.tn_new(O.Found.ar(n), O.Found.i(n))

def mn_dot2() -> T.Tensor:
  +x = MO.mo_fx2d()
  +w = MO.mo_reshape(MO.mo_arena(T.Tensor.ar(x), MO.mo_i1d()), [MO.mo_ki(1), MO.mo_ki(2), MO.mo_ki(2)])
  +wp = mn_perm(T.Tensor.ar(w), w, [2, 1, 0])
  MO.mo_sum(False{}, MO.mo_mul(x, wp), [2])

# `Tensor.log_softmax` -- op.py:686, with `axis=None` reduced to `range(self.ndim)`
# (reduce.py:15). `MO.mo_log_softmax` IS that (op.bend:1100) and it is GREEN there, so
# this file CALLS it and does not re-gate it: re-gating a neighbouring file's row would
# be a change-detector test, which the brief forbids.
def mn_lsm(+x: T.Tensor) -> T.Tensor: MO.mo_log_softmax(x, MO.mo_ax_all(x))

# ===========================================================================
# 4. THE LOSS. `sparse_categorical_crossentropy` -- op.py:1721.
#     log_probs = self.log_softmax()                                     # :1741
#     loss_mask = Y.ne(ignore_index) if ignore_index != -1 else Y.const_like(True, bool)
#     y         = Y.unsqueeze(-1)._one_hot_along_dim(self.shape[-1], dim=-1) * loss_mask.unsqueeze(-1)
#     smoothing = label_smoothing * (log_probs.mean(-1) * loss_mask)     # :1745
#     unreduced = ((1 - label_smoothing) * (log_probs * y).sum(-1) + smoothing)
#     return -unreduced.sum() / loss_mask.sum() if reduction == "mean" else ...
#
# `log_probs` is PORTED and CALLED. `y` and `loss_mask` are W3 (`_one_hot_along_dim` is
# `arange`, and `arange` is `_pool`; `const_like` is `expand`) so they are PARAMETERS.
# `label_smoothing` is 0.0 at every call site in this example (op.py:1721's default, and
# examples/beautiful_mnist.py:26 passes nothing), so `(1 - label_smoothing)` is a
# Python `float` 1.0 and `1.0 * Tensor` is a broadcast MUL with a CONST -- which this
# port KEEPS, because dropping it would be a DIFFERENT graph that agrees on values,
# and a gate that cannot see the difference is not a gate.
#
# `.mean(-1)` and `.sum(-1)` are `axis=-1`, and `MO.mo_ax` takes the SIGN as a `Bool`
# because a `match` may not scrutinise a call (rule 1), so `-1` is the U32 pattern
# `4294967295` and `mn_last_axis` is where that spelling lives.
# ===========================================================================

def mn_last_axis(+x: T.Tensor) -> List<&2, U32>: MO.mo_ax(True{}, x, 4294967295)

def mn_loss(+logits: T.Tensor, +y: T.Tensor, +mask: T.Tensor) -> T.Tensor:
  +lp = mn_lsm(logits)
  +sm = MO.mo_mul(MO.mo_mean(False{}, lp, mn_last_axis(lp)), mask)
  MO.mo_neg(MO.mo_div(MO.mo_sum(False{}, MO.mo_add(MO.mo_bin_c(MO.mo_sum(False{}, MO.mo_mul(lp, y), mn_last_axis(lp)), O.OpsMUL{}, O.CFloat{1.0}), MO.mo_bin_c(sm, O.OpsMUL{}, O.CFloat{0.0})), Nil{}), MO.mo_sum(False{}, mask, Nil{})))

# ===========================================================================
# 5. THE OPTIMIZER. `nn.optim.Adam` (optim.py:139) is `LAMB(params, lr, b1, b2, eps,
# 0.0, adam=True, ...)`, and `optim.bend`'s `op_lamb` IS that `_step` (optim.py:161).
# The gate row for it is RED -- `optim.bend:1348 unverified_lamb`, 1 node against
# CPython's 49 -- so it is CALLED and NOT CLAIMED, and the row says so in its name.
# ===========================================================================

def unverified_adam() -> IO(Unit): MO.mo_sig_t("unverified_adam", OP.op_lamb(OP.g_step()))

# ===========================================================================
# 6. THE CORE FUNCTION SURFACE. THIS IS THE DEF THE `langs/` EXPORT AGENTS PORT, and
# it is the point of the file.
#
#     mn_step(logits, y, mask, w) -> MnStep
#
# It is `train_step` (examples/beautiful_mnist.py:23-27) with its three foreign seams
# taken as parameters, and it is TOTAL over the substrate's capabilities: every hop that
# builds is built and every hop that does not is named at its Python line rather than
# stubbed into a plausible-looking graph.
#
# The brief's phrasing is "one training step from (images, labels, weights) ->
# (loss, new_weights)", and the mapping onto this signature is exact and worth
# stating, because the export agents need it and because three of the four arguments
# exist for a NAMED reason rather than by accident:
#
#   images  -> logits.  `self(X_train[samples])` (:26) is W1+W2 (conv2d,
#              max_pool2d), so the step takes the FORWARD'S OUTPUT. W1 and W2 are
#              named at their Python lines above.
#   labels  -> y.       `Y_train[samples]` (:26) fed to `sparse_categorical_crossentropy`,
#              whose one-hot `y` is W3.
#   weights -> w.       `nn.state.get_parameters(model)` (:36), a `Data` record here
#              because a list of twenty Tensors is a list and Python's `state.py` is
#              a different unit.
#   (new)   -> mask.    op.py:1742's `Y.const_like(True, dtypes.bool)`, W3 again. It is
#              a FOURTH argument rather than a CONST because `const_like` is
#              `expand`, one of the five ops `fold.bend` defers, so a port that
#              materialised it would be building a node whose shape nothing can check.
#
# `new_weights` is `MnStep.w` and it is the SAME `w` today, which is W4:
# `.backward()` (mixin/gradient.py:20) is a `TODO(p3)` in gradient.bend itself, so no
# gradient exists for the optimizer to apply and `_apply_update` (optim.py:60) has
# nothing to subtract. That is stated at the def rather than papered over with a
# `TODO` inside a body that looks finished.
#
# `MnStep` is a `Data` because a pair is a `Type` in Bend -- `gradient.bend`'s rule 15
# records that `Data` cannot hold a `Maybe`, which is why `op.bend`'s `Br` and
# `weak.bend`'s `ODt` are records for the same reason.
# ===========================================================================

type MnWeights is Data:
  MnWeights{t: List<&2, T.Tensor>}

def MnWeights.t(w: MnWeights) -> List<&2, T.Tensor>:
  match w:
    case MnWeights{t}: t

type MnStep is Data:
  MnStep{loss: T.Tensor, w: MnWeights}

def MnStep.loss(s: MnStep) -> T.Tensor:
  match s:
    case MnStep{loss, w}: loss

def MnStep.w(s: MnStep) -> MnWeights:
  match s:
    case MnStep{loss, w}: w

def mn_step(+logits: T.Tensor, +y: T.Tensor, +mask: T.Tensor, w: MnWeights) -> MnStep:
  MnStep{mn_loss(logits, y, mask), w}

# ===========================================================================
# 7. THE PRETTY OUTPUT. `t.set_description(f"loss: {loss.item():6.2f} test_accuracy:
# {test_acc:5.2f}%")` -- examples/beautiful_mnist.py:43. A STRING, and the only part of
# this example that needs no fold, no device and no graph.
#
# `loss.item()` is `tinygrad/mixin/op.py:22`, a DEVICE READ and therefore
# `tensor.bend`'s WALL 2, so `loss` and `test_acc` come in as `F32` -- the one
# representation that survives the seam, since an f32 buffer's value IS an f32. That is
# the whole reason the port has a printer at all.
#
# `f"{x:6.2f}"` is `H.pad_left(H.f32_fixed(x, 2n), 6)`: `f32_fixed` is `helpers.bend`'s
# `printf("%.2f")` (helpers.bend:585) and `pad_left` is `rjust` (helpers.bend:637). Both
# are CALLS into a file this unit does not own.
#
# AND `f32_fixed` IS NOT `printf`'s `%.2f`. It WALKS the decimal digits two at a time
# (`f32_frac`, helpers.bend:522) and never rounds the last one, so it TRUNCATES:
# `f32_fixed(2.3456, 2n)` is `"2.34"` where CPython's `f"{2.3456:.2f}"` is `"2.35"`.
# MEASURED on six values, four agree and two do not, so this example's PRETTY OUTPUT IS
# WRONG for roughly half of all inputs -- and every `out_*` row below is chosen on the
# AGREEING half, which is stated at `t_out` and pinned by `row_round_1`/`row_round_2`.
# The fix belongs in `helpers.bend`, which is READ-ONLY to this unit, so it is REPORTED
# and the rows are chosen honestly rather than quietly nudged.
#
# `test_acc` is `float('nan')` until `i % 10 == 9` (examples/beautiful_mnist.py:38,
# :42), and `f"{float('nan'):5.2f}"` is `"  nan"`, so the nan row is a row about the
# INITIAL value of the loop, which is the first thing a reader of the output sees.
# ===========================================================================

def mn_row_out(+loss: F32, +acc: F32) -> String:
  mn_cat(["loss: ", H.pad_left(H.f32_fixed(loss, 2n), 6), " test_accuracy: ",
    H.pad_left(H.f32_fixed(acc, 2n), 5), "%"])

def mn_nan() -> F32: F32.div(F32.mul(0.0, 0.0), F32.mul(0.0, 0.0))

def mn_inf() -> F32: F32.div(F32.mul(1.0, 1.0), F32.mul(0.0, 0.0))

# ===========================================================================
# THE GATE ROWS, in Python's order: the model def, then the forward shape walk, then
# the parameter shapes, then the forward graph, then the output, then the unverified
# rows.
# ===========================================================================

def t_mdl() -> IO(Unit):
  do IO<Unit>:
    IO.print(mn_cat(["mdl_table=", mn_table()]))
    IO.print(mn_cat(["mdl_count=", U32.show(mn_len())]))
    IO.print(mn_cat(["mdl_pad5=", mn_pad_str(5)]))
    IO.print(mn_cat(["mdl_pad3=", mn_pad_str(3)]))

def t_shapes() -> IO(Unit):
  do IO<Unit>:
    IO.print(mn_cat(["mdl_in=", mn_shape_str(mn_in())]))
    IO.print(mn_cat(["mdl_walk=", mn_walk_row()]))
    IO.print(mn_cat(["mdl_out=", mn_shape_str(mn_out())]))
    IO.print(mn_cat(["mdl_lin_in=", mn_shape_str(mn_lin_in())]))

def t_scales() -> IO(Unit):
  do IO<Unit>:
    IO.print(mn_cat(["mdl_scale=", mn_scale_col(MnConv{1, 32, 5})]))
    IO.print(mn_cat(["mdl_scale=", mn_scale_col(MnConv{32, 32, 5})]))
    IO.print(mn_cat(["mdl_scale=", mn_scale_col(MnConv{32, 64, 3})]))
    IO.print(mn_cat(["mdl_scale=", mn_scale_col(MnConv{64, 64, 3})]))
    IO.print(mn_cat(["mdl_bound=", mn_scale_col(MnLin{576, 10})]))

def t_params() -> IO(Unit):
  do IO<Unit>:
    IO.print(mn_cat(["mdl_conv0_w=", mn_conv_w(MnConv{1, 32, 5})]))
    IO.print(mn_cat(["mdl_conv0_b=", mn_conv_b(MnConv{1, 32, 5})]))
    IO.print(mn_cat(["mdl_lin_w=", mn_lin_w(MnLin{576, 10})]))
    IO.print(mn_cat(["mdl_bn=", mn_bn(MnBn{32})]))
    IO.print(mn_cat(["mdl_bn=", mn_bn(MnBn{64})]))

# THE FORWARD GRAPH ROWS. `relu1` is a 1-D BUFFER fixture and `relu2` is the same
# buffer RESHAPED to 2-D -- `mixin/op.bend`'s `mo_fx1d`/`mo_fx2d`, the same two
# fixtures its own rows use -- so CPython's fixtures must be `Tensor([1.,2.,3.,4.])`
# and `Tensor([[1.,2.],[3.,4.]])` and nothing else. `lin1` is
# `Tensor([1.,2.,3.,4.]).linear(Tensor([1.,2.,3.,4.]), Tensor([1.,2.]))`, and its two
# operands must be THREE SEPARATE BUFFERS -- two inputs and the bias -- which is why
# `mn_buf1` is spelled here and not taken from op.bend's fixed-size-4 fixture.
def t_fwd() -> IO(Unit):
  do IO<Unit>:
    MO.mo_sig_t("relu1", mn_relu(MO.mo_fx1d()))
    MO.mo_sig_t("relu2", mn_relu(MO.mo_fx2d()))
    MO.mo_sig_t("lin1", mn_lin1_fx())

# THE OUTPUT ROWS. Four fixtures, chosen so that CPython's `printf` rounding and
# `H.f32_fixed`'s TRUNCATION agree on every one -- see `row_round_*` below for the
# measurement that says why that is a constraint and not an accident.
def t_out() -> IO(Unit):
  do IO<Unit>:
    IO.print(mn_cat(["out_a=", mn_row_out(2.25, 97.5)]))
    IO.print(mn_cat(["out_b=", mn_row_out(0.0, 10.0)]))
    IO.print(mn_cat(["out_c=", mn_row_out(mn_nan(), mn_nan())]))
    IO.print(mn_cat(["out_d=", mn_row_out(mn_inf(), mn_inf())]))

# `row_round_*` -- THE ROUNDING MEASUREMENT, and it is BEND-ONLY because CPython cannot
# be asked the question in this file's terms. `f"{2.3456:.2f}"` is `"2.35"` in CPython
# and `H.f32_fixed(2.3456, 2n)` is `"2.34"`, because `f32_frac` (helpers.bend:522)
# WALKS the decimal digits and never rounds the last one. MEASURED on six fixtures:
#
#     2.3456 -> 2.34  / 2.35   DISAGREE
#     2.3449 -> 2.34  / 2.34   agree
#     2.30   -> 2.29  / 2.30   DISAGREE
#     97.531 -> 97.53 / 97.53  agree
#     2.25   -> 2.25  / 2.25   agree
#     0.125  -> 0.12  / 0.12   agree
#
# So `f32_fixed` is a TRUNCATING `%.2f`, and every `t_out` fixture is chosen on the
# agreeing half. A real MNIST loss is `2.3456`-shaped, so THE PRETTY OUTPUT AS PRINTED
# IS NOT CPYTHON'S for roughly half of all values. That is a defect in `helpers.bend`
# (READ-ONLY to this unit) and it is the single most useful thing in this report. The
# two rows below pin it from both sides and PRINT FALSE, because a row that prints
# False is information and hiding it makes the work worse.
def row_round_1() -> IO(Unit): MO.mo_row("row_round_2.3456", String.eq(H.f32_fixed(2.3456, 2n), "2.35"))

def row_round_2() -> IO(Unit): MO.mo_row("row_round_2.30", String.eq(H.f32_fixed(2.3, 2n), "2.30"))

# ===========================================================================
# THE UNVERIFIED ROWS, printed under names that say what they are.
# ===========================================================================

def t_unverified() -> IO(Unit):
  do IO<Unit>:
    MO.mo_sig_t("unverified_lin2", mn_dot2())
    unverified_adam()

def main() -> IO(Unit):
  do IO<Unit>:
    t_mdl()
    t_shapes()
    t_scales()
    t_params()
    t_fwd()
    t_out()
    row_round_1()
    row_round_2()
    t_unverified()

# ===========================================================================
# THE MUTATION TABLE -- MEASURED. Each edit is applied, both lanes are re-run and
# diffed against the unmutated output, and the file is reverted from a byte snapshot:
#
#     cp examples/beautiful_mnist.bend /tmp/bmn.bak
#     <edit one token>                                   # as named below
#     ./bin/bend examples/beautiful_mnist.bend > /tmp/mut.txt
#     diff /tmp/bd.txt /tmp/mut.txt
#     cp /tmp/bmn.bak examples/beautiful_mnist.bend
#
# | mutation | the edit | rows that MOVED | what it was testing |
# | --- | --- | --- | --- |
# | mutation | the edit | rows that MOVED | what it was testing |
# | --- | --- | --- | --- |
# | M1 | `mn_conv_out`: `U32.add(U32.sub(h, k), 1)` -> `U32.sub(h, k)` | `mdl_walk` `mdl_lin_in` | `_apply_ceil_mode`'s `+ 1` (op.py:1644). Every conv in the model is unpadded, so the chain shifts a pixel per conv and `mdl_lin_in` reads `(1, 400)` instead of `(1, 576)` -- which is the number `nn.Linear(576, 10)` asserts, so the row catches the model's own consistency. |
# | M2 | `mn_layers`: `MnConv{32, 32, 5}` -> `MnConv{32, 32, 3}` | `mdl_table` `mdl_walk` `mdl_scale` | A transposed layer. `mdl_table` moves because the ARGUMENT column moves, `mdl_walk` because the second conv's output moves, `mdl_scale` because `1/sqrt(32*9) != 1/sqrt(32*25)`. The NAME column does not move, and that is the measurement that says the argument column is not redundant. |
# | M3 | `mn_pool_out`: `U32.div(h, 2)` -> `U32.div(h, 4)` | `mdl_walk` `mdl_lin_in` | `max_pool2d`'s `stride=None` meaning `stride == kernel_size` (op.py:1334). Stride 4 collapses the map to 1x1 and `mdl_lin_in` reads `(1, 64)`. |
# | M4 | `mn_flat_out`: `U32.mul(U32.mul(c, h), w)` -> `U32.mul(c, h)` | `mdl_walk` `mdl_lin_in` | `flatten(1)`'s product over ALL trailing dims (movement.py:345). Reads `(1, 192)` instead of `(1, 576)`. |
# | M5 | `mn_row_out`: `H.pad_left(..., 5)` -> `H.pad_left(..., 6)` | `out_a` `out_b` `out_c` `out_d` | The `:5.2f` width on `test_acc` (examples/beautiful_mnist.py:43). The WIDTH is invisible to the number and to the `%`, so only the printed row sees it -- this is the row that says the pretty output is gated at all. |
# | M6 | `mn_row_out`: the `"loss: "` literal -> `"loss="` | `out_a` `out_b` `out_c` `out_d` | The f-string's LITERAL half, which is the half a `%.2f` printer cannot check. |
# | M7 | `mn_nan`: the `0.0 * 0.0` NUMERATOR -> `1.0 * 1.0` | `out_c` | `test_acc = float('nan')` before `i % 10 == 9` (examples/beautiful_mnist.py:38). `out_c` goes from `  nan` to `1.00`. `out_d` does NOT move, because it uses `mn_inf` and not `mn_nan` -- which is the measurement that says the two specials are separate rows. |
# | M8 | `MnRelu{}` -> `MnPool{}` at index 1 | `mdl_table` `mdl_walk` | relu is SHAPE-IDENTITY and max_pool2d is not, so `mdl_walk` moves even though both print one name in the name column -- the row that separates the two columns. `mdl_lin_in` does not move here, because a pool at index 1 and its stride cancel out of the final product for this particular table; that is luck, not design, and it is why the row is listed as moving `mdl_walk` only. |
# | M9 | `mn_relu`: `E.ew_where(E.ew_gt(...))` -> `MO.mo_maxc(x, 0.0)` | `relu1` `relu2` | elementwise.py:674's NOTE ("if you write this as self.maximum(0) the gradient is wrong"). `maximum` is a MAX and the port is a CMPLT and a WHERE, so both the op names and the count move. This is the row that pins the NOTE. |
# | M10 | `mn_bn`'s `nbt=(1,)` -> `nbt=(0,)` | `mdl_bn` | `nn/__init__.py:39`'s `num_batches_tracked = Tensor.zeros(dtype='long')`. `mdl_bn` prints a LITERAL and not a folded shape, so it moves for the wrong reason -- which makes it a WEAK row, and the honest fix is the one the row's own comment names: the no-argument arm of `Tensor.zeros` (creation.py:108) is `tensor.bend`'s WALL 2, so the row cannot yet print a shape. It is listed here as moving rather than as a negative because it DOES move, and the weakness is recorded rather than hidden. |
# | M11 | a whitespace-only edit (`def main` -> `def  main`) | **NOTHING** | a control. A table with no row that CANNOT move is a table of coincidences. |
#
# THE `unverified_*` ROWS WERE NOT MUTATED, for the reason `nn/optim.bend` gives for
# its seven: a mutation's only meaning is the set of rows it moves, and a row that is
# already wrong measures nothing. They are reported as wrong instead, which is the
# honest form of the same information.
# ===========================================================================