# nn/item.bend -- tinygrad/mixin/op.py:22 `Tensor.item`.
#
# THE LAST STEP OF AN EVAL. Forward pass -> logits on device -> argmax -> `item`
# -> compare with the label. Without it there is NO eval output at all, and
# `examples/test_pkl_imagenet.bend:17` names it as the wall in front of the
# ImageNet milestone ("`p.to('cpu').argmax().item()`").
#
# ===========================================================================
# UPSTREAM, QUOTED. `tinygrad/mixin/op.py:22-33`:
#
#     def item(self) -> PyConst:
#       """
#       Returns the value of this tensor as a standard Python number.
#       ...
#       """
#       assert self.numel() == 1, "must have one element for item"
#       return self.data()[(0,) * len(self.shape)]
#
# THREE THINGS ARE IN THAT, and only the first and the third are portable
# here:
#
#   1. THE PRECONDITION. `self.numel() == 1` -- `prod(self.shape)`
#      (`tinygrad/mixin/movement.py:38-46`, `numel`) -- or an `AssertionError` whose
#      MESSAGE is a literal in the source. THE PORT HAS THIS: the shape is
#      `fold.shape` (`uop/fold.bend`) and the product is `H.prod_u32`
#      (`helpers.bend:485`). This is the half that decides whether a
#      multi-element tensor is an ERROR or a silent "first element", and
#      upstream says ERROR.
#
#   2. THE READ. `self.data()` (`tinygrad/tensor.py:285-301`) is
#        `self.contiguous().realize().uop.buffer` -> `as_memoryview()` ->
#        `.cast(self.dtype.fmt, self.shape)`, and `data()` FIRST casts a weak
#      dtype to its commit dtype:
#        `if self.dtype in dtypes.weaks: return self.cast(self.commit_dtype()).data()`.
#      So `item` needs (a) an ALLOCATED DEVICE BUFFER, (b) a DEVICE-TO-HOST
#      COPY, and (c) the dtype's FORMAT, which is where the dtype's BYTE WIDTH
#      enters: `fmt` is the struct code for the dtype and `cast(fmt, shape)`
#      reads `dtype.itemsize` BYTES per element.
#
#   3. THE INDEX. `[(0,) * len(self.shape)]` -- the FIRST element, in a
#      one-element tensor, which is the only element there is.
#
# ===========================================================================
# WHAT THE PORT HAS, AND WHAT IT DOES NOT.
#
# IT HAS THE DTYPE HALF. `S.Dt.itemsize` (`LAWS/spec.bend:176-181`) is
# `(bitsize + 7) // 8`, exactly `tinygrad/dtype.py:63`. `MD.commit_dtype`
# (`mixin/dtype.bend:326-328`) IS `commit_dtype` (`tinygrad/mixin/dtype.py:16-17`)
# and `MD.commit_int` (`mixin/dtype.bend:273-275`) IS `commit_int`
# (`tinygrad/dtype.py:171-174`, `commit_int`), so the weak-dtype branch of `data()` -- the
# one that decides int32-vs-int64 and float32 -- is PORTED.
#
# IT DOES NOT HAVE THE BUFFER HALF, and this is the port's WALL, measured not
# guessed:
#   * `tinybendygrad/uop/ops.bend:5296` -- "NO LIVE `Buffer` -- there is no
#     `type Buffer is Data` anywhere in the port and ZERO `Buffer{`
#     constructors". MEASURED: `grep -rn "type Buffer is Data" tinybendygrad/`
#     answers ONE line and it is that COMMENT; `grep -rn "Buffer{" tinybendygrad/`
#     answers `SpBuffer{` (the SPEC datatype, `LAWS/spec.bend:424`), the
#     WEBGPU `CreateBuffer{`/`CopyBuffer{` wire constructors
#     (`runtime/webgpu_call.bend:204-252`) and the comment above. NONE of them
#     is an allocated buffer with contents.
#   * `tinybendygrad/engine/realize.bend` -- the FOREIGN-EFFECT list, [b]:
#     "realize.py:148 exec_copy -- allocators, `_transfer`, `host[:]`". The
#     device-to-host copy that `data()` needs is EXACTLY that line, and it is
#     NOT PORTED.
#   * `tinybendygrad/nn/onnx.bend:49` -- the port's own words: "Nothing in
#     this port can read a byte out of a tensor".
#
# SO THE PORT'S `item` READS A VALUE FROM THE ONE PLACE A VALUE EXISTS, and
# REFUSES, BY NAME, EVERYWHERE ELSE. The one place is a CONST node: its arg is
# `APy{v}` (`uop/ops.bend:1222`) and `v` is an `O.Const`
# (`uop/ops.bend:799-803`) -- `CBool`/`CInt`/`CFloat`. That is the port's
# `PyConst`, which is exactly what upstream's `item` returns.
#
# THE DOMAIN IS THEREFORE SMALLER THAN UPSTREAM'S, AND THE DIFFERENCE IS
# NAMED IN EVERY ANSWER:
#   * a one-element CONST -- READ, and the value is upstream's value.
#   * a multi-element tensor -- REFUSED, with upstream's own message.
#   * anything else -- REFUSED, with the wall named.
#
# ===========================================================================
# THE ORCHESTRATOR'S THREE PRIMITIVES, AND WHAT EACH ONE ACTUALLY IS. They
# were briefed as "a buffer element read", "the dtype's byte width" and "a
# tensor index", and TWO OF THE THREE ARE SOMETHING ELSE. The measurements:
#
#   * `Buf.at` -- `tinybendygrad/runtime/ops_python.bend:836`:
#         def Buf.at(fs: List<&2, Buf>, +b: U32) -> Buf:
#           Maybe.default(&2, Buf, List.get(&2, Buf, fs, U32.to_nat(b)), Buf{0, 4, 0})
#     It answers THE `b`-th BUFFER IN A LIST OF BUFFERS -- the PYTHON
#     backend's kernel-argument binding -- and it answers a `Buf`, NOT a
#     scalar. It is NOT an element read of a buffer's CONTENTS. MEASURED: the
#     ONLY `def X.at(` whose receiver is `Buf` in the whole port is this one
#     (`grep -rn "^def [A-Za-z_0-9]*\\.at(" tinybendygrad/`); the other `Buf`
#     receivers (`runtime/ops_webgpu.bend:930,939`, `runtime/ops_cl.bend:776,780`)
#     are `size`/`id`, and `renderer/wgsl.bend:707-719` is a renderer's own
#     `Buf` with `dt`/`addr`/`numel`/`name`.
#   * `Dt.itemsize` -- `tinybendygrad/LAWS/spec.bend:176-181`. IT IS WHAT IT
#     SAYS: `(bitsize + 7) // 8`.
#   * `mo_at` -- `tinybendygrad/mixin/op.bend:316-317`:
#         def mo_at(+ds: List<&2, O.Sint>, +t: List<&2, O.Sint>) -> U32:
#           U32.from_nat(List.length(&2, O.Sint, t))
#     It is the INDEX OF A HEAD ELEMENT of a SHAPE -- `enumerate(self.shape)`'s
#     `i` -- NOT an index into a tensor. Its three call sites
#     (`mixin/op.bend:696,779,874`) all pass a SHAPE list.
#
# ===========================================================================
# THE RESULT IS A SUM TYPE, NOT A `Maybe`, because the three outcomes are
# THREE different things and a `None` would flatten a refusal into a value.
# `Itm` is the name (not `Item`: `viz/cli.bend:97` already owns that
# constructor, and Bend has ONE constructor namespace across modules).
#
#   ItmVal{dt, v}     -- the scalar, read, under the dtype it was read under.
#   ItmNotOne{n}      -- upstream's `AssertionError`: `n` elements, not one.
#   ItmNoRead{at}     -- the port's wall, named.
#
# `dt` IS CARRIED BECAUSE UPSTREAM CARRIES IT TOO: `data()` casts a weak
# dtype to its commit dtype BEFORE reading, so `Tensor(3.5).item()` is a
# float32 read and `Tensor(7).item()` is an int32 read, and a caller that
# wants to know which it got has to be told.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../tensor.bend as T
import ./../mixin/op.bend as M
import ./../mixin/movement.bend as MX
import ./../mixin/dtype.bend as MD

# ===========================================================================
# THE RESULT.
# ===========================================================================

type Itm is Data:
  ItmVal{dt: S.Dt, v: O.Const}
  ItmNotOne{n: U32}
  ItmNoRead{at: String}

# THE WALL, IN ONE STRING, WITH ITS TWO MEASUREMENTS IN IT. It is a `def` and
# not a literal at each use site so that the string is ONE string.
def nn_item_wall() -> String:
  String.concat([
    "NO-READ: no live Buffer in the port (uop/ops.bend:5296); realize.py:145",
    " exec_copy -- the device-to-host _copyout -- is a foreign effect (engine/realize.bend:60 [b])"])

# ===========================================================================
# 1. THE PRECONDITION. `prod(self.shape)` -- upstream's `numel()`
# (`tinygrad/mixin/movement.py:38-46`).
#
# THE DIMS COME FROM THE FOLD (`M.mo_dims`, `mixin/op.bend:284`) AND THE
# PRODUCT IS `H.prod_u32` (`helpers.bend:486`). `M.mo_reduced` IS **NOT** THE
# PRODUCT DEF: it is `prod([si for si, so in zip(shape, sum.shape) if
# resolve(si != so)])` (`mixin/op.bend:876`), which is the product of the
# dims the REDUCTION TOUCHED, so `mo_reduced(t, Nil{})` is the EMPTY product
# and answers 1 for EVERY TENSOR. MEASURED: it answered 1 for a (2,)-shaped
# and for a (8,)-shaped tensor alike, and the first version of this file's
# `item_multi` row therefore read a multi-element tensor as a ONE-element one
# and answered the wall instead of upstream's `AssertionError`.
#
# THE PROJECTION IS `M.mo_dim_u32` (`mixin/op.bend:297-300`), which answers 0
# for a SYMBOLIC dim -- and 0, not 1, because "a symbolic dim that silently
# became 1 would be a WRONG shape rather than a missing one". A symbolic
# shape therefore reads as numel 0 here, which is the same refusal upstream
# makes (`tensor.py:297`, "no data if shape is symbolic").
# ===========================================================================

def nn_item_dims.go(+ds: List<&2, O.Sint>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ds:
    case Nil{}: acc
    case d <> t: nn_item_dims.go(t, List.append(&2, U32, acc, [M.mo_dim_u32(d)]))

def nn_item_dims(+ds: List<&2, O.Sint>) -> List<&2, U32>: nn_item_dims.go(ds, Nil{})

def nn_item_numel(+t: T.Tensor) -> U32:
  H.prod_u32(nn_item_dims(M.mo_dims(F.folded(T.Tensor.ar(t)), T.Tensor.u(t))))

# ===========================================================================
# 2. THE VALUE. A CONST node's arg is `APy{v}` (`uop/ops.bend:1222`) and `v`
# is an `O.Const` (`uop/ops.bend:799-803`).
#
# `match` MAY NOT SCRUTINISE A COMPUTED VALUE, AND NOT A LET-BOUND ONE
# EITHER (bend 2.0.38 refuses both, RE-MEASURED 2026-10-23 AFTER THE UPGRADE: "a match cannot scrutinize a
# computed value" and "a match cannot scrutinize a local binder: give it its
# own def"), so the OP and the ARG are read first and handed to a def that
# matches on its own PARAMETERS.
# ===========================================================================

def nn_item_py(a: O.Arg) -> Maybe<&2, O.Const>:
  match a:
    case O.APy{v}: Some{v}
    case _: None{}

def nn_item_const.of(op: O.Op, a: O.Arg) -> Maybe<&2, O.Const>:
  match op:
    case O.OpsCONST{}: nn_item_py(a)
    case _: None{}

def nn_item_const(+t: T.Tensor) -> Maybe<&2, O.Const>:
  nn_item_const.of(O.Arena.op(T.Tensor.ar(t), T.Tensor.u(t)),
    O.Arena.arg(T.Tensor.ar(t), T.Tensor.u(t)))

# ===========================================================================
# 3. THE DTYPE. `data()`'s weak branch:
#
#     if self.dtype in dtypes.weaks: return self.cast(self.commit_dtype()).data()
#
# `MD.md_weak` (`mixin/dtype.bend:124`) IS `dtype in dtypes.weaks`, and
# `MD.commit_dtype` (`mixin/dtype.bend:326-328`) IS `commit_dtype`
# (`tinygrad/mixin/dtype.py:16-17`). For a weakint the commit is
# `commit_int(vmin, vmax, default_int)` -- the ladder
# `(default_int, int, long, ulong)` -- and for a weakfloat it is
# `strong_dtype(weakfloat)` = float32.
#
# THE BOUNDS ARE THE CONST'S OWN VALUE, because for a CONST `vmin == vmax ==
# the value` (`tinygrad/uop/ops.py:259-262` reads `self.arg` for a CONST).
# `F.const_i64` (`uop/fold.bend:1420-1420`) is that read, and it answers
# `None{}` for a `CFloat` -- which is FINE, because the weakfloat branch of
# `commit_dtype` ignores the bounds and takes `strong_dtype`.
#
# THE ONE THING THIS FILE ADDS IS THE QUANTITY HOP. `F.const_i64.go`
# answers `Maybe<&2, H.I64>` (a `Data` payload, so the `Maybe` is a `Data`
# too) and `MD.commit_dtype` takes `Maybe<&1, H.I64>`. A `&2` payload USED
# ONCE is inside a `&1` budget, so the hop is one `match` and NOT a second
# copy of the value.
# ===========================================================================

def nn_item_bounds.of(m: Maybe<&2, H.I64>) -> Maybe<&1, H.I64>:
  match m:
    case Some{i}: Some{i}
    case None{}: None{}

def nn_item_bounds(v: O.Const) -> Maybe<&1, H.I64>: nn_item_bounds.of(F.const_i64.go(v))

# THE WEAK TEST IS A PARAMETER AND NOT A CALL IN THE SCRUTINEE POSITION, for
# the reason in section 2.
def nn_item_dt.p(weak: Bool, +dt: S.Dt, +v: O.Const) -> S.Dt:
  match weak:
    case True{}:
      MD.dtnm_b(MD.commit_dtype(dt, nn_item_bounds(v), nn_item_bounds(v),
        MD.md_default_int()))
    case False{}: dt

def nn_item_dt(+dt: S.Dt, +v: O.Const) -> S.Dt: nn_item_dt.p(MD.md_weak(dt), dt, v)

# ===========================================================================
# 4. THE ANSWER. The order is UPSTREAM'S ORDER: the precondition is checked
# FIRST, so a multi-element tensor is an AssertionError and NOT a read
# refusal -- which is what upstream does, because the `assert` is the first
# line of `item` and `data()` is never reached.
# ===========================================================================

def nn_item_read.dt(d: Maybe<&2, S.Dt>, +v: O.Const) -> Itm:
  match d:
    case Some{dt}: ItmVal{nn_item_dt(dt, v), v}
    case None{}: ItmNoRead{nn_item_wall()}

def nn_item_read.c(c: Maybe<&2, O.Const>, +t: T.Tensor) -> Itm:
  match c:
    case Some{v}: nn_item_read.dt(T.tn_dtype(t), v)
    case None{}: ItmNoRead{nn_item_wall()}

def nn_item_read(+t: T.Tensor) -> Itm: nn_item_read.c(nn_item_const(t), t)

def nn_item.of.p(one: Bool, +n: U32, +t: T.Tensor) -> Itm:
  match one:
    case True{}: nn_item_read(t)
    case False{}: ItmNotOne{n}

def nn_item.of(+n: U32, +t: T.Tensor) -> Itm: nn_item.of.p(U32.is_eq(n, 1), n, t)

def nn_item(+t: T.Tensor) -> Itm: nn_item.of(nn_item_numel(t), t)

# ===========================================================================
# THE PRINTING.
#
# `nn_item_show` IS UPSTREAM'S OWN TEXT WHERE UPSTREAM HAS TEXT: the
# multi-element refusal prints `AssertionError: must have one element for
# item` -- `tinygrad/mixin/op.py:32` VERBATIM, with nothing added, so the
# row's `want` IS the upstream literal.
#
# THE VALUE IS A PYTHON NUMBER, AND THE PORT SPELLS IT THE WAY PYTHON DOES
# WHERE IT CAN:
#   * `H.i64_dec` (`helpers.bend:2180`) is the SIGNED DECIMAL -- `str(int)` in
#     Python -- and NOT `H.i64_text` (`helpers.bend:1713`), which is the
#     `hi:lo` bit pattern and would print `0:7` where Python prints `7`.
#   * `Bool.show` is `str(bool)`.
#   * `H.f32_show` (`helpers.bend:1030`) is NOT Python's `repr`: it prints an
#     integer-valued float as an integer and every other float with SIX
#     decimals (`helpers.bend:1001-1006`), where Python prints the shortest
#     decimal that reads back. `helpers.bend:999` CLAIMS it is "the shortest
#     decimal that reads back, the way Python's repr does" and the code under
#     that comment does six decimals. SO THE FLOAT ROWS ARE TWO: one spells
#     the value (`3.500000`) and one spells its EXACT float32 BIT PATTERN
#     (`1080033280`), which is what CPython's `struct.pack('<f', 3.5)` says
#     and which no rounding can move.
# ===========================================================================

def nn_item_show.v(v: O.Const) -> String:
  match v:
    case O.CFloat{f}: H.f32_show(f)
    case O.CInt{i}: H.i64_dec(i)
    case O.CBool{b}: Bool.show(b)
    # `CInvalid` IS THE PORT'S POISON (`uop/ops.bend:803`) and Python CANNOT
    # BUILD ONE -- `dtypes.invalid` only exists inside the compiler -- so
    # upstream has NO answer for `item()` on it. The port says so by name
    # rather than printing a number it does not have.
    case O.CInvalid{}: "INVALID"

def nn_item_show(it: Itm) -> String:
  match it:
    case ItmVal{dt, v}: nn_item_show.v(v)
    case ItmNotOne{n}: "AssertionError: must have one element for item"
    case ItmNoRead{at}: at

# THE EXACT float32 BIT PATTERN of the value read. CPython's
# `struct.unpack('<I', struct.pack('<f', 3.5))[0]` is 1080033280, and so is
# `F32.bits(3.5)`.
def nn_item_bits.v(v: O.Const) -> String:
  match v:
    case O.CFloat{f}: U32.show(F32.bits(f))
    case _: "NONE"

def nn_item_bits(it: Itm) -> String:
  match it:
    case ItmVal{dt, v}: nn_item_bits.v(v)
    case _: "NONE"

# THE DTYPE THE VALUE WAS READ UNDER, and its BYTE WIDTH -- upstream's
# `dtype.itemsize`, which is how many bytes `data()`'s `cast(fmt, shape)`
# reads per element. `S.Dt.itemsize` is `LAWS/spec.bend:176-181`.
def nn_item_size(it: Itm) -> String:
  match it:
    case ItmVal{dt, v}: U32.show(S.Dt.itemsize(dt))
    case _: "NONE"

# ===========================================================================
# THE ROWS.
#
# EVERY `want` BELOW IS AN ANSWER MEASURED IN CPython IN THIS REPO'S `.venv`
# ON 2026-10-22, AGAINST `tinygrad`'s own `Tensor`, AND NOT COPIED FROM THE
# PORT'S OUTPUT. The commands and the raw answers are in
# `.agents/slop/nnitem/REPORT.md`. IN SHORT:
#
#   Tensor(3.5).item()        -> 3.5     (float; f32 bits 1080033280)
#   dtypes.float32.itemsize   -> 4
#   Tensor(7).item()          -> 7       (int; read under int32)
#   dtypes.int32.itemsize     -> 4
#   Tensor(True).item()       -> True    (bool)
#   dtypes.bool.itemsize      -> 1
#   Tensor([1.0,2.0]).numel() -> 2
#   Tensor([1.0,2.0]).item()  -> AssertionError: must have one element for item
#   Tensor([3.5]).item()      -> 3.5     (the ONE-ELEMENT BUFFER case)
#
# THE ROW PRINTER. `nn/layers.bend:971-972` has
#     def nn_row.line(nm: String, got: String, want: String) -> IO(Unit):
#       IO.print(String.concat([nm, " got=", got, " want=", want]))
# and this file does NOT import it: `layers.bend` is owned by another unit
# RIGHT NOW, and a file that imports a file being rewritten is a file that
# breaks when the other unit lands. The line is one line and it is reprinted
# here rather than depended upon.
# ===========================================================================

def nn_item_line(nm: String, got: String, want: String) -> IO(Unit):
  IO.print(String.concat([nm, " got=", got, " want=", want]))

# THE FIXTURES.
#
# A CONST TENSOR. `M.mo_const_t` (`mixin/op.bend:370-370`) is the port's
# `UOp.const` in a tensor's arena: it interns a CONST node and wraps it. The
# BASE is `MX.mxw_buf` (`mixin/movement.bend:1231-1232`), a BUFFER node, and
# it is there only to give the arena something to hold the CONST next to; the
# CONST's own SHAPE is `()` (`uop/fold.bend:2219`, `const_ds`), so its `numel`
# is 1 -- which is upstream's `Tensor(3.5).shape == ()`.
def nn_item_const_t(v: O.Const) -> T.Tensor:
  M.mo_const_t(MX.mxw_buf(O.Arena.empty(), 0, 4), v)

# A TWO-ELEMENT TENSOR: a BUFFER OF SIZE 2. MEASURED: a BUFFER's shape is the
# one dim `(size,)`, and it is CONCRETE (`fold.param_ds`,
# `uop/fold.bend:1197`), so `numel` is 2. A RESHAPE is not used here
# because a ONE-element shape arg is a bare CONST rather than a STACK
# (`mixin/movement.bend:1267-1270`) and `fold.shape` does not read it -- so
# `mo_dims` answers the EMPTY list for `mxw_reshape(buf, [2])` and the
# numel would read as 1.
def nn_item_multi_t() -> T.Tensor: MX.mxw_buf(O.Arena.empty(), 0, 2)

# A ONE-ELEMENT DEVICE BUFFER: the port's stand-in for `Tensor([3.5])`, a
# ONE-ELEMENT DEVICE BUFFER. Its CONTENTS do not exist in the port -- that is
# the wall -- so `item` refuses on it.
def nn_item_buf_t() -> T.Tensor: MX.mxw_buf(O.Arena.empty(), 0, 1)

# --- ROW 1: a one-element float32 ------------------------------------------
# `Tensor(3.5)` IS a weakfloat const in the port, and `data()` casts it to
# float32 (`strong_dtype(weakfloat)`) before reading, so the value read is
# float32(3.5) = 3.5.
def nn_item_row_f32() -> IO(Unit):
  +t = nn_item_const_t(O.CFloat{F32.div(F32.from_nat(7n), F32.from_nat(2n))})
  +it = nn_item(t)
  do IO<Unit>:
    nn_item_line("item_f32", nn_item_show(it), "3.500000")
    nn_item_line("item_f32_bits", nn_item_bits(it), "1080033280")
    nn_item_line("item_f32_size", nn_item_size(it), "4")

# --- ROW 2: a one-element int32 --------------------------------------------
# `Tensor(7)` IS a weakint const, and `commit_int(7, 7)` picks int32.
def nn_item_row_i32() -> IO(Unit):
  +t = nn_item_const_t(O.CInt{H.i64_of_i32(7)})
  +it = nn_item(t)
  do IO<Unit>:
    nn_item_line("item_i32", nn_item_show(it), "7")
    nn_item_line("item_i32_size", nn_item_size(it), "4")

# --- ROW 3: a one-element bool ---------------------------------------------
# `Tensor(True)` IS a boolean const, and `boolean` is NOT weak, so `data()`
# reads it as it is.
def nn_item_row_bool() -> IO(Unit):
  +t = nn_item_const_t(O.CBool{True{}})
  +it = nn_item(t)
  do IO<Unit>:
    nn_item_line("item_bool", nn_item_show(it), "True")
    nn_item_line("item_bool_size", nn_item_size(it), "1")

# --- ROW 4: two elements ----------------------------------------------------
# UPSTREAM RAISES. The message is upstream's own literal
# (`tinygrad/mixin/op.py:32`) and the port's answer IS that literal.
def nn_item_row_multi() -> IO(Unit):
  +t = nn_item_multi_t()
  +it = nn_item(t)
  do IO<Unit>:
    nn_item_line("item_multi", nn_item_show(it), "AssertionError: must have one element for item")
    nn_item_line("item_multi_numel", U32.show(nn_item_numel(t)), "2")

# --- ROW 5: a one-element DEVICE BUFFER ------------------------------------
# THIS ROW IS RED BY DESIGN. It is THE DIVERGENCE, and it is the only red
# row in the file. Upstream reads the buffer's element: CPython answers 3.5
# for `Tensor([3.5]).item()`. THE PORT HAS NO BUFFER TO READ, so it refuses.
# THE `want` IS UPSTREAM'S ANSWER, NOT THE PORT'S, so the row CAN go red and
# DOES.
def nn_item_row_buf() -> IO(Unit):
  +t = nn_item_buf_t()
  nn_item_line("item_buffer_divergence", nn_item_show(nn_item(t)), "3.5")

def nn_item_rows() -> IO(Unit):
  do IO<Unit>:
    nn_item_row_f32()
    nn_item_row_i32()
    nn_item_row_bool()
    nn_item_row_multi()
    nn_item_row_buf()

def main() -> IO(Unit):
  do IO<Unit>:
    nn_item_rows()
