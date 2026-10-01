import Base
import ./../LAWS/spec.bend as S
import ./../dtype.bend as DT
import ./../helpers.bend as H
import ./../tensor.bend as T
import ./../uop/ops.bend as O

# ===========================================================================
# nn/onnx.bend -- tinygrad/nn/onnx.py (1319 lines).
#
# STAGE 1 -- WHAT IS PORTED, WHAT IS NOT, AND WHICH PYTHON LINES THE REST
# COVERS. Staged on purpose: this file is 40% of what is left to port, and a
# file that TRIES to be complete and is not is worse than one that is honestly
# partial. Every stage leaves the file CHECKING with this header true.
#
# THE STAGES, and WHAT IS LANDED IN EACH. Staged on purpose: this file is 40% of
# what is left to port, and a file that TRIES to be complete and is not is worse
# than one that is honestly partial.
#
#   STAGE 1 -- LANDED, CHECKING, GATED. The three enums and their two-way name
#     tables; the ONNX->tinygrad DTYPE NAME TABLE (:29-37 `OnnxDataType`, all
#     thirteen entries, both directions, plus the four HOLES at codes 0/8/14/15);
#     the ATTRIBUTE NAME TABLE (:20-27 `to_field_name`, all eight, both ways);
#     the WIRE TYPE table (:13-18); the nine `Domain` members (:40-51) and
#     `from_onnx`'s four-way answer; `required_input_python_consts` (:352-359, all
#     thirty-eight); and the four frozen records the parser builds toward
#     (:53-70 `OpSetId`, `OnnxValue`, `OnnxNode`) with the attribute-VALUE sum
#     type `OnnxNode.opts` needs.
#   STAGE 2 -- LANDED, CHECKING, GATED. The op NAME TABLE (:1308-1317, 171 keys
#     and 171 count), the four VERSIONED ops' seven (domain, version, impl) rows,
#     the three-way IMPLEMENTATION IDENTITY, `_select_op`'s version ROUTER
#     (:415-423) with 22 fixtures over all three arms and both Python raises, and
#     the whole pure-integer PADDING block: `_resolve_pool_pads` (:495-500),
#     `_auto_pad` (:491-493), `_onnx_pads_to_tiny_pads` (:481-484) and `_axes`
#     (:479).
#   STAGE 3 -- NOT DONE. The RUNNERS (`OnnxRunner.__init__` :374-376,
#     `_init_from_graph` :378-390, `_from_subgraph` :393-396, `_parse_input`
#     :398-413, `to` :425-430, `_get_python_const` :432-439, `__call__` :441-470)
#     and the protobuf layer they stand on. THE WALL IS NAMED PER ARM below.
#   STAGE 4 -- NOT DONE. The 167 op BODIES (:475-1307), the node-shape arithmetic
#     that goes with them, and the quantization family. THE WALL per family is
#     below.
#
# NOT PORTED, and each is a named wall rather than a TODO-shaped hole.
#
#   * `PBBufferedReader` (:73-119) and all of `OnnxPBParser` (:121-349).
#     WALL: a protobuf reader OVER A TENSOR, so it needs byte-at-a-time reads
#     (`self.read(1)`, `self.read(4)`), `seek`, `tell`, `io.BufferedReader` and
#     `struct.unpack`. Nothing in this port can read a byte out of a tensor --
#     `state.bend`'s `TensorIO.readinto` is the same wall and says so.
#     `read_int64`'s 64-bit varint accumulate (:79-89, :103) is a SECOND,
#     independent wall on top: `H.I64` has add/sub/cmp but the decode needs a
#     64-bit SHIFT, and `Word` is not exported (bend2-constraints' `divandmod`
#     rule 1).
#   * `_to_python_const` (:361-362) -- `t.data().tobytes()` and `t.tolist()` are
#     HOST reads of a realized buffer.
#   * `OnnxRunner.__call__` (:441-470) -- the interpreter loop, and it dispatches
#     into the op table, so it is unreachable before the op bodies exist.
#   * `OnnxRunner._parse_input` (:398-413) -- `is_numpy_ndarray`, `warnings.warn`
#     and a per-dim shape check that raises.
#   * `OnnxRunner.to` (:425-430) -- moves tensors to a device and rebuilds every
#     `OnnxNode`, so it needs `Tensor.to` (runtime) and a device string.
#   * `get_onnx_ops`' 167 op BODIES (:475-1307). Nearly every body is ONE line
#     calling a mixin method that belongs to another file (`x.reshape`,
#     `x.conv2d`, `x.softmax`, `x.pad`, ...). Each is a `# TODO(p3)` naming its
#     line; none is inlined, because inlining a callee would be a second port.
#   * `If`'s branch runner (:547-562) and `Gradient` (:1305-1306) need an
#     `OnnxRunner` VALUE -- this file's own class -- and `Gradient` also needs
#     `.gradient()`.
#   * the quantization family (:1210-1261) needs `x.repeat_interleave`,
#     `x.scatter_reduce`, and `dtypes.is_int`/`is_float` predicates.
#   * `ImageDecoder` (:578-585) needs PIL.
#   * `Attention` (:1011-1099), `EmbedLayerNormalization` (:929-949) and
#     `RotaryEmbedding` (:1106-1130) are three of the largest bodies and are pure
#     mixin chains; their `_select_op` ROUTING is ported and gated, their bodies
#     are not.
#
# THE NODE TYPES LEFT UNPORTED, WITH THE WALL FOR EACH. The brief's list, and the
# honest answer for every one: the PADS and the ROUTING are ported (Stage 2), the
# node that CONSUMES them is not, and the wall is the same for all of them.
#
#   CONV, CONVTRANSPOSE, MAXPOOL, AVGPOOL -- `_resolve_pool_pads` is PORTED and
#     GATED; the bodies (:724-757) then call `x.max_pool2d` / `x.avg_pool2d` /
#     `x.conv2d` / `x.conv_transpose2d`, which reach `mixin/op.bend`'s `_pool`
#     (its W4/W8) and `fold.bend:1620-1626`'s refusal to answer EXPAND/SHRINK/
#     PAD/FLIP. So the padding is decidable and the OUTPUT SHAPE is not, and the
#     file does NOT fake a shape row for them.
#   GATE / BN / LIN / GLOBALPOOL / LEAKYRELU / SCALE -- these are not node types
#     in onnx.py at all; they are the brief's names for `BatchNormalization`
#     (:896-909), `Gemm` (:769-772, the `alpha`/`beta`/`transA`/`transB`
#     parameters), `GlobalAveragePool`/`GlobalMaxPool` (:766-767, whose axes are
#     `tuple(range(2, X.ndim))` -- pure, and the trivial arithmetic of which is
#     the same walk as `_axes`'s), and `LeakyRelu` (:614, a scalar `alpha=0.01`
#     handed to `X.leaky_relu`). Every one of those bodies calls a mixin method,
#     so every one is a `TODO(p3)` at its line.
#   PAD (:706-712) -- the MODE TABLE is pure (`{"edge":"replicate",
#     "wrap":"circular"}` at :712) and the `real_pads` scatter (:710-711) is
#     integer arithmetic, but the body ends in `x.pad(..., mode=...)` and
#     `fold.bend` refuses PAD, so neither the mode table nor the scatter is
#     worth a row on its own and both are Stage 4.
#   RESHAPE / TRANSPOSE / CONCAT / SUM -- one line each (:679-693, :647-649) and
#     all three end in a mixin method.
#
# WHAT THE GATE CANNOT SEE, stated rather than left to be discovered:
#   * every gate row is about a TABLE, a NAME or an INTEGER. There is no row that
#     builds a graph, so nothing here says anything about `x.conv2d`.
#   * `AVal`'s five payload readers are absent (see the wall note above), so
#     `onnx_aval_tags` pins the TAG SET and not a payload.
#   * `onnx_odt_of_dt`'s inverse is well defined ONLY because the thirteen keys
#     land on thirteen distinct dtypes; a fourteenth ONNX type mapping onto one of
#     them would break the bijection and the row would say so.
#
# THE GATE IS THE PART THAT IS WORTH HAVING, and it is this file's reason to
# exist. `OnnxDataType.to_dtype()` is `DTYPES_DICT[self.name.lower()]` (:37), so
# tinygrad maps thirteen ONNX type strings onto its dtypes THROUGH A NAME TABLE,
# and a wrong entry is a silent wrong-dtype kernel rather than a crash.
# `state.bend`'s header records the identical lesson for `safe_dtypes`: a dtype
# claim whose oracle is a COUNT rather than a STRUCTURE is blind. So the gate is a
# ROUND TRIP BOTH WAYS per entry, plus the whole table as one string, diffed
# against CPython's own tables AND against tinygrad's own nested helpers (reached
# by exec-ing `get_onnx_ops`'s body with its final `return {...}` replaced, so the
# oracle is tinygrad's CODE):
#
#     mkdir -p /tmp/onnxgate
#     .venv/bin/python .agents/slop/onnx-gate.py      > /tmp/onnxgate/py.txt
#     ./bin/bend tinybendygrad/nn/onnx.bend           > /tmp/onnxgate/bd.txt
#     ./bin/bend tinybendygrad/nn/onnx.bend -o /tmp/onnxgate/nat
#     /tmp/onnxgate/nat                               > /tmp/onnxgate/nat.txt
#     diff /tmp/onnxgate/py.txt /tmp/onnxgate/bd.txt  # CPython vs interpreted
#     diff /tmp/onnxgate/bd.txt /tmp/onnxgate/nat.txt # the two lanes
#     .venv/bin/python .agents/slop/onnx-mutate.py     # the mutation table
#
# MEASURED 2026-10-02: 123 rows, all three lanes byte-identical.
#
# `--check-only` is PERMANENTLY RED for this file and that redness is NOT evidence
# about the work: `dtype.bend` has fourteen `@extern` F32 seams and
# bend2-constraints' `renderer/__init__` rule 8 measures that `--check-only`
# reports the IMPORT CLOSURE, so a file that never names a seam still goes red.
# `nn/__init__.bend`, `nn/optim.bend` and `nn/state.bend` report the identical
# fourteen. The two lanes printing identically is this project's gate.
# ===========================================================================

# ===========================================================================
# STAGE 1. THE TABLES. Enums first, because everything else is keyed by them.
# ===========================================================================

# ---------------------------------------------------------------------------
# `WireType(enum.IntEnum)` -- onnx.py:13-18. Six members, contiguous 0..5.
# `skip_field` (:112-119) is the only consumer and it is a WALL with
# `PBBufferedReader`; the table itself is the ported part.
#
# THE ARMS ARE IN DESCENDING ORDER AND THAT IS LOAD-BEARING. A `U32` literal
# pattern is a PREFIX match over the successor relation (bend2-constraints'
# `mixin/rand` rule 2), so `case 5:` claims 5,6,7,... and any `case 6:` written
# after it is DEAD CODE that still checks. Listed high-to-low, no arm claims a
# value a later arm wants.
# ---------------------------------------------------------------------------
def onx_wt(c: U32) -> Maybe<&1, String>:
  match c:
    case 5: Some{"FIXED32"}
    case 4: Some{"END_GROUP"}
    case 3: Some{"START_GROUP"}
    case 2: Some{"LENGTH_DELIMITED"}
    case 1: Some{"FIXED64"}
    case 0: Some{"VARINT"}
    case _: None{}

def onx_wt.of(m: Maybe<&1, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "-"

def onx_wt_name(c: U32) -> String: onx_wt.of(onx_wt(c))

# the reverse half of the same table. Python gets it for free from
# `enum.Enum`'s `_value2member_map_`; there is no such thing in Bend, so it is
# written out and it is the half that makes the round trip a round trip.
def onx_wt_rev(nm: String) -> Maybe<&1, U32>:
  match nm:
    case "VARINT": Some{0}
    case "FIXED64": Some{1}
    case "LENGTH_DELIMITED": Some{2}
    case "START_GROUP": Some{3}
    case "END_GROUP": Some{4}
    case "FIXED32": Some{5}
    case _: None{}

def onx_wt_rev.of(m: Maybe<&1, U32>) -> U32:
  match m:
    case Some{c}: c
    case None{}: 0

def onx_wt_code(nm: String) -> U32: onx_wt_rev.of(onx_wt_rev(nm))

# ---------------------------------------------------------------------------
# `AttributeType(enum.IntEnum)` -- onnx.py:20-27, and `to_field_name` (:27),
# `{1:"f", 2:"i", 3:"s", 4:"t", 5:"g", 6:"floats", 7:"ints", 8:"strings"}`.
# `_parse_NodeProto` (:191) reads `AttributeType(attr_dict["type"]).to_field_name()`
# to decide which key of the attribute dict holds the value, so THIS TABLE IS
# THE ATTRIBUTE NAME SPELLING and a wrong entry reads the wrong field of a
# parsed protobuf. It is the eight-letter answer the brief asked for, and it is
# a dictionary literal in Python, which is a `match` ladder here.
# ---------------------------------------------------------------------------
def onx_at_field(t: U32) -> Maybe<&1, String>:
  match t:
    case 8: Some{"strings"}
    case 7: Some{"ints"}
    case 6: Some{"floats"}
    case 5: Some{"g"}
    case 4: Some{"t"}
    case 3: Some{"s"}
    case 2: Some{"i"}
    case 1: Some{"f"}
    case _: None{}

def onx_at_field.of(m: Maybe<&1, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "-"

def onx_at_field_of(t: U32) -> String: onx_at_field.of(onx_at_field(t))

# the enum member NAME, which is the other half of the table and is what
# `to_field_name`'s dictionary is keyed by in Python's source order (1..8).
def onx_at_name(t: U32) -> Maybe<&1, String>:
  match t:
    case 8: Some{"STRINGS"}
    case 7: Some{"INTS"}
    case 6: Some{"FLOATS"}
    case 5: Some{"GRAPH"}
    case 4: Some{"TENSOR"}
    case 3: Some{"STRING"}
    case 2: Some{"INT"}
    case 1: Some{"FLOAT"}
    case _: None{}

def onx_at_name.of(m: Maybe<&1, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "-"

def onx_at_name_of(t: U32) -> String: onx_at_name.of(onx_at_name(t))

def onx_at_rev(f: String) -> Maybe<&1, U32>:
  match f:
    case "f": Some{1}
    case "i": Some{2}
    case "s": Some{3}
    case "t": Some{4}
    case "g": Some{5}
    case "floats": Some{6}
    case "ints": Some{7}
    case "strings": Some{8}
    case _: None{}

def onx_at_rev.of(m: Maybe<&1, U32>) -> U32:
  match m:
    case Some{t}: t
    case None{}: 0

# `to_field_name` inverted. This is the def the gate calls directly, because
# `to_field_name` IS Python's own method and calling it is the oracle.
def onx_at_code(f: String) -> U32: onx_at_rev.of(onx_at_rev(f))

# and the ENUM NAME inverted, which is a SECOND table transcribed from a
# DIFFERENT part of the Python (the member declarations at :25 rather than the
# dictionary at :27). In CPython it is `AttributeType(a.name).value == a.value`
# and it is trivially true, because CPython derives the name lookup from the
# declarations. In the port it is NOT trivial -- the two tables are written out
# by hand from two different sources -- and a transcription slip in either one
# shows up as exactly this row going red. That is bend2-constraints' "two
# independent transcriptions of the same Python table that AGREE is strong
# evidence both are right, and it is cheaper than either mutation table".
def onx_at_name_rev(nm: String) -> Maybe<&1, U32>:
  match nm:
    case "FLOAT": Some{1}
    case "INT": Some{2}
    case "STRING": Some{3}
    case "TENSOR": Some{4}
    case "GRAPH": Some{5}
    case "FLOATS": Some{6}
    case "INTS": Some{7}
    case "STRINGS": Some{8}
    case _: None{}

def onx_at_name_rev.of(m: Maybe<&1, U32>) -> U32:
  match m:
    case Some{t}: t
    case None{}: 0

# ---------------------------------------------------------------------------
# `OnnxDataType(enum.IntEnum)` -- onnx.py:29-37. Thirteen members with FOUR
# holes: 0 (UNDEFINED), 8 (STRING), 14 (COMPLEX64) and 15 (COMPLEX128) are not
# members, so the codes 0..16 are not a dense range and `onx_odt_key(8)` is
# `None`. A dense table would have answered something here, and that is the class
# of bug the `onnx_odt_holes` row exists to make impossible.
#
# `to_dtype()` is `DTYPES_DICT[self.name.lower()]` -- so the LOOKUP KEY is the
# enum member name, lower-cased, and DTYPES_DICT maps most of the thirteen onto a
# name it does not spell itself (`uint8`->uchar, `int8`->char, `int32`->int,
# `int64`->long, `int16`->short, `uint16`->ushort, `uint32`->uint,
# `uint64`->ulong, `float`->float32, `float16`->half, `double`->float64).
# `DT.to_dtype_of` (dtype.bend:450) IS that table, already ported, so it is
# CALLED and not re-spelled -- which is what makes `onx_odt_dt` a real lookup
# through the production path rather than a restatement of it.
# ---------------------------------------------------------------------------
def onx_odt_key(c: U32) -> Maybe<&1, String>:
  match c:
    case 16: Some{"bfloat16"}
    case 13: Some{"uint64"}
    case 12: Some{"uint32"}
    case 11: Some{"double"}
    case 10: Some{"float16"}
    case 9: Some{"bool"}
    case 7: Some{"int64"}
    case 6: Some{"int32"}
    case 5: Some{"int16"}
    case 4: Some{"uint16"}
    case 3: Some{"int8"}
    case 2: Some{"uint8"}
    case 1: Some{"float"}
    case _: None{}

def onx_odt_key.of(m: Maybe<&1, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "-"

def onx_odt_key_of(c: U32) -> String: onx_odt_key.of(onx_odt_key(c))

def onx_odt_name(c: U32) -> Maybe<&1, String>:
  match c:
    case 16: Some{"BFLOAT16"}
    case 13: Some{"UINT64"}
    case 12: Some{"UINT32"}
    case 11: Some{"DOUBLE"}
    case 10: Some{"FLOAT16"}
    case 9: Some{"BOOL"}
    case 7: Some{"INT64"}
    case 6: Some{"INT32"}
    case 5: Some{"INT16"}
    case 4: Some{"UINT16"}
    case 3: Some{"INT8"}
    case 2: Some{"UINT8"}
    case 1: Some{"FLOAT"}
    case _: None{}

def onx_odt_name.of(m: Maybe<&1, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "-"

def onx_odt_name_of(c: U32) -> String: onx_odt_name.of(onx_odt_name(c))

def onx_odt_rev(k: String) -> Maybe<&1, U32>:
  match k:
    case "float": Some{1}
    case "uint8": Some{2}
    case "int8": Some{3}
    case "uint16": Some{4}
    case "int16": Some{5}
    case "int32": Some{6}
    case "int64": Some{7}
    case "bool": Some{9}
    case "float16": Some{10}
    case "double": Some{11}
    case "uint32": Some{12}
    case "uint64": Some{13}
    case "bfloat16": Some{16}
    case _: None{}

def onx_odt_rev.of(m: Maybe<&1, U32>) -> U32:
  match m:
    case Some{c}: c
    case None{}: 0

def onx_odt_code(k: String) -> U32: onx_odt_rev.of(onx_odt_rev(k))

# the enum MEMBER NAME inverted -- the second hand-written transcription of one
# Python table, and the same reasoning as `onx_at_name_rev` above.
def onx_odt_name_rev(nm: String) -> Maybe<&1, U32>:
  match nm:
    case "FLOAT": Some{1}
    case "UINT8": Some{2}
    case "INT8": Some{3}
    case "UINT16": Some{4}
    case "INT16": Some{5}
    case "INT32": Some{6}
    case "INT64": Some{7}
    case "BOOL": Some{9}
    case "FLOAT16": Some{10}
    case "DOUBLE": Some{11}
    case "UINT32": Some{12}
    case "UINT64": Some{13}
    case "BFLOAT16": Some{16}
    case _: None{}

def onx_odt_name_rev.of(m: Maybe<&1, U32>) -> U32:
  match m:
    case Some{c}: c
    case None{}: 0

# `OnnxDataType.to_dtype()` -- onnx.py:37. Two defs, not one, for the reason
# every `.of` split in this port exists: a `match` may not scrutinise a CALL
# (bend2-constraints rule 2), so `onx_odt_dt` cannot match `DT.to_dtype_of(k)`.
# And a `Maybe` cannot be a fold's accumulator nor a `Data` field, so the
# "key AND dtype" answer travels as two parameters.
def onx_odt_dt.of(k: Maybe<&1, String>) -> Maybe<&1, S.Dt>:
  match k:
    case Some{s}: DT.to_dtype_of(s)
    case None{}: None{}

def onx_odt_dt(c: U32) -> Maybe<&1, S.Dt>: onx_odt_dt.of(onx_odt_key(c))

# the total wrapper. Python RAISES `ValueError` on an unknown code, so there is
# no honest total answer; `-` is the "absent" spelling and `onnx_odt_holes` is
# the row that says whether it is right.
def onx_odt_dt_name.of(m: Maybe<&1, S.Dt>) -> String:
  match m:
    case Some{d}: DT.dt_name(d)
    case None{}: "-"

def onx_odt_dt_name(c: U32) -> String: onx_odt_dt_name.of(onx_odt_dt(c))

# THE BACK DIRECTION, `tinygrad dtype -> ONNX code`. It is well defined HERE and
# only here: DTYPES_DICT is many-to-one over all thirty of its keys, but the
# thirteen keys this table uses land on THIRTEEN DISTINCT dtypes (MEASURED --
# `float`, `unsigned char`, `signed char`, `unsigned short`, `short`, `int`,
# `long`, `bool`, `half`, `double`, `unsigned int`, `unsigned long`, `__bf16`),
# so the restriction to this table's own keys is a BIJECTION and the inverse
# exists. That is the strongest claim in this file: a port that made
# `onx_odt_dt(2)` and `onx_odt_dt(3)` answer the same dtype would still pass
# every forward row, and would answer the wrong dtype for a real ONNX model.
#
# `U32` and NOT `Maybe<&1, U32>` for the accumulator, because a `Maybe` cannot
# be a fold's accumulator (bend2-constraints' "A `Maybe` CANNOT BE A FOLD'S
# ACCUMULATOR"). `0` is the absent sentinel and it is SAFE rather than a
# convention: code 0 is not a member, which `onnx_odt_holes_rt` pins.
# "does `onx_odt_dt(c)` answer this dtype". `O.eq_dt` is `ops.bend`'s own
# comparator and it compares all FOUR fields including the name, so it is the
# production test rather than a restatement; `dt_name` alone would be a weaker
# oracle (the name IS unique, but the ROW should not depend on that being so).
def onx_odt_dt_is.go(d: S.Dt, m: Maybe<&1, S.Dt>) -> Bool:
  match m:
    case Some{e}: O.eq_dt(e, d)
    case None{}: False{}

def onx_odt_dt_is(d: S.Dt, c: U32) -> Bool: onx_odt_dt_is.go(d, onx_odt_dt(c))

def onx_odt_of_dt.go(cs: List<&2, U32>, +d: S.Dt, +acc: U32) -> U32:
  match cs:
    case Nil{}: acc
    case +c <> t:
      onx_odt_of_dt.go(t, d, Bool.pick(U32, U32.is_eq(acc, 0),
        Bool.pick(U32, onx_odt_dt_is(d, c), c, 0), acc))

# and the absent half: a dtype this table never produces answers 0. `void` is
# the witness and `S.Dt.is_eq`-free on purpose: `onx_odt_dt_is(void(), 0)` is the
# negative fixture, so the predicate is not true for everything.
def onx_odt_of_dt(cs: List<&2, U32>, d: S.Dt) -> U32: onx_odt_of_dt.go(cs, d, 0)

# ---------------------------------------------------------------------------
# `Domain(enum.Enum)` -- onnx.py:40-51. A `Data` SUM TYPE, not a `U32` tag plus
# two tables, because the enum's whole content is the nine (name, value) pairs
# and `_init_from_graph` (:379) asks a MEMBERSHIP question over two of them --
# `{Domain.AI_ONNX_TRAINING, Domain.AI_ONNX_PREVIEW_TRAINING}` -- which is a
# two-arm `match` on a sum and nothing else. Python writes it as a set over the
# string values; the port makes the constructors the members.
#
# `Domain.from_onnx` (:51) is `ONNX if domain is None or domain == "" else
# Domain(domain)` -- so the EMPTY string and the absent one both land on ONNX,
# and an UNRECOGNISED string is Python's `ValueError`, which this port spells as
# `None` (bend2-constraints reviewer rule 5: a Python raise is a refusal and a
# `None` is a `Maybe`, neither is optional).
# ---------------------------------------------------------------------------
type Dom is Data:
  DomOnnx{}
  DomOnnxMl{}
  DomTrain{}
  DomPrevTrain{}
  DomMsContrib{}
  DomMsNchwc{}
  DomMsExp{}
  DomAten{}
  DomTinygrad{}

def Dom.s(d: Dom) -> String:
  match d:
    case DomOnnx{}: "ai.onnx"
    case DomOnnxMl{}: "ai.onnx.ml"
    case DomTrain{}: "ai.onnx.training"
    case DomPrevTrain{}: "ai.onnx.preview.training"
    case DomMsContrib{}: "com.microsoft"
    case DomMsNchwc{}: "com.microsoft.nchwc"
    case DomMsExp{}: "com.microsoft.experimental"
    case DomAten{}: "org.pytorch.aten"
    case _: "org.tinygrad"

def Dom.n(d: Dom) -> String:
  match d:
    case DomOnnx{}: "ONNX"
    case DomOnnxMl{}: "ONNX_ML"
    case DomTrain{}: "AI_ONNX_TRAINING"
    case DomPrevTrain{}: "AI_ONNX_PREVIEW_TRAINING"
    case DomMsContrib{}: "MICROSOFT_CONTRIB_OPS"
    case DomMsNchwc{}: "MICROSOFT_NCHWC"
    case DomMsExp{}: "MICROSOFT_EXPERIMENTAL"
    case DomAten{}: "PYTORCH_ATEN"
    case _: "TINYGRAD"

# `Domain.from_onnx` -- :51
def onx_dom(s: String) -> Maybe<&1, Dom>:
  match s:
    case "": Some{DomOnnx{}}
    case "ai.onnx": Some{DomOnnx{}}
    case "ai.onnx.ml": Some{DomOnnxMl{}}
    case "ai.onnx.training": Some{DomTrain{}}
    case "ai.onnx.preview.training": Some{DomPrevTrain{}}
    case "com.microsoft": Some{DomMsContrib{}}
    case "com.microsoft.nchwc": Some{DomMsNchwc{}}
    case "com.microsoft.experimental": Some{DomMsExp{}}
    case "org.pytorch.aten": Some{DomAten{}}
    case "org.tinygrad": Some{DomTinygrad{}}
    case _: None{}

def onx_dom.of(m: Maybe<&1, Dom>) -> Dom:
  match m:
    case Some{d}: d
    case None{}: DomOnnx{}

# `_init_from_graph`'s `any(...)` over the two TRAINING domains -- :379. A `match`
# and NOT a fold over a list, because the question is asked once per node and a
# `Maybe` cannot be an accumulator (bend2-constraints' "A `Maybe` CANNOT BE A
# FOLD'S ACCUMULATOR").
def onx_dom_is_training(d: Dom) -> Bool:
  match d:
    case DomTrain{}: True{}
    case DomPrevTrain{}: True{}
    case _: False{}

# ---------------------------------------------------------------------------
# `required_input_python_consts` -- onnx.py:352-359. Thirty-eight keys, and
# thirteen of them are built by two dict COMPREHENSIONS rather than by a
# literal: `{"Reduce"+r: (1,) for r in (...ten names...)}` and
# `{optim: (1,) for optim in ("Adam","Adagrad","Momentum")}`. Python evaluates
# the comprehensions once at import, so the table is THIRTY-EIGHT FLAT ENTRIES
# and this is that, written out, because a comprehension is not a Bend form
# (bend2-constraints rule 31.1) and because the gate has to see thirty-eight.
#
# The lookup is `_get_python_const`'s `required_input_python_consts.get(op, ())`
# -- :435 -- and `()` is the EMPTY LIST, so `onx_pc_ixs` answering `Nil{}` for an
# absent op is exactly right and not a convenience.
# ---------------------------------------------------------------------------
type Pc is Data:
  Pc{nm: String, ix: List<&2, U32>}

def Pc.n(p: Pc) -> String:
  match p:
    case Pc{nm, ix}: nm

def Pc.i(p: Pc) -> List<&2, U32>:
  match p:
    case Pc{nm, ix}: ix

def required_input_python_consts() -> List<&2, Pc>:
  [
    Pc{"Tile", [1]}, Pc{"Range", [0, 1, 2]}, Pc{"Expand", [1]}, Pc{"Reshape", [1]},
    Pc{"Squeeze", [1]}, Pc{"Unsqueeze", [1]}, Pc{"Trilu", [1]}, Pc{"ConstantOfShape", [0]},
    Pc{"CumSum", [1]}, Pc{"TopK", [1]}, Pc{"Pad", [1, 2, 3]}, Pc{"MaxUnpool", [2]},
    Pc{"Dropout", [1, 2]}, Pc{"CenterCropPad", [1]}, Pc{"OneHot", [1]}, Pc{"Compress", [1]},
    Pc{"ImageDecoder", [0]}, Pc{"AffineGrid", [1]}, Pc{"Resize", [1, 2, 3]}, Pc{"Upsample", [1]},
    Pc{"Split", [1]}, Pc{"Slice", [1, 2, 3, 4]}, Pc{"HannWindow", [0]}, Pc{"HammingWindow", [0]},
    Pc{"BlackmanWindow", [0]},
    Pc{"ReduceMax", [1]}, Pc{"ReduceMin", [1]}, Pc{"ReduceSum", [1]}, Pc{"ReduceMean", [1]},
    Pc{"ReduceSumSquare", [1]}, Pc{"ReduceProd", [1]}, Pc{"ReduceL1", [1]}, Pc{"ReduceL2", [1]},
    Pc{"ReduceLogSum", [1]}, Pc{"ReduceLogSumExp", [1]},
    Pc{"Adam", [1]}, Pc{"Adagrad", [1]}, Pc{"Momentum", [1]}
  ]

def onx_mem(xs: List<&2, U32>, +idx: U32) -> Bool:
  match xs:
    case Nil{}: False{}
    case x <> t: Bool.or(U32.is_eq(x, idx), onx_mem(t, idx))

def onx_pc_rev(ps: List<&2, Pc>, +nm: String, hit: Bool, acc: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}: acc
    case +p <> t:
      onx_pc_rev(t, nm, Bool.or(hit, String.eq(Pc.n(p), nm)),
        Bool.pick(List<&2, U32>, String.eq(Pc.n(p), nm), Pc.i(p), acc))

def onx_pc_ixs(ps: List<&2, Pc>, +nm: String) -> List<&2, U32>: onx_pc_rev(ps, nm, False{}, Nil{})

# `_get_python_const`'s `idx not in ... .get(op, ())` -- :435
def onx_pc_has.go(ps: List<&2, Pc>, +nm: String, +idx: U32, hit: Bool) -> Bool:
  match ps:
    case Nil{}: hit
    case +p <> t:
      onx_pc_has.go(t, nm, idx, Bool.or(hit, Bool.and(String.eq(Pc.n(p), nm), onx_mem(Pc.i(p), idx))))

def onx_pc_has(ps: List<&2, Pc>, +nm: String, idx: U32) -> Bool: onx_pc_has.go(ps, nm, idx, False{})

# ===========================================================================
# STAGE 1 (cont). THE FROZEN RECORDS. `OpSetId` (:53), `OnnxValue` (:57),
# `OnnxNode` (:64), and the attribute-VALUE sum type `OnnxNode.opts` needs.
#
# `tuple[str|int, ...]` in `OnnxValue.shape` is a UNION, so it is `Dim` -- a
# `Data` sum with an INT arm and a NAMED arm -- rather than a `U32` with a
# sentinel. A sentinel would make `dim_param` unrepresentable-as-a-name for the
# value 0, which is the parse-don't-validate rule: an ONNX shape genuinely can
# be `[0]` and `[dim_param: "N"]` in the same list, and a `U32` would have to
# invent a third state for it.
# ===========================================================================

type Dim is Data:
  DimI{v: U32}
  DimP{nm: String}

def Dim.v(d: Dim) -> U32:
  match d:
    case DimI{v}: v
    case DimP{nm}: 0

def Dim.isp(d: Dim) -> Bool:
  match d:
    case DimI{v}: False{}
    case DimP{nm}: True{}

# `OpSetId(domain: Domain, version: int)` -- :53
type OpSetId is Data:
  OpSetId{dom: Dom, ver: U32}

def OpSetId.d(o: OpSetId) -> Dom:
  match o:
    case OpSetId{dom, ver}: dom

def OpSetId.v(o: OpSetId) -> U32:
  match o:
    case OpSetId{dom, ver}: ver

# `OnnxValue(shape, dtype, is_optional, is_sequence)` -- :57-62
type OnnxValue is Data:
  OnnxValue{shape: List<&2, Dim>, dtype: S.Dt, opt: Bool, seq: Bool}

def OnnxValue.shape(v: OnnxValue) -> List<&2, Dim>:
  match v:
    case OnnxValue{shape, dtype, opt, seq}: shape

def OnnxValue.dtype(v: OnnxValue) -> S.Dt:
  match v:
    case OnnxValue{shape, dtype, opt, seq}: dtype

def OnnxValue.opt(v: OnnxValue) -> Bool:
  match v:
    case OnnxValue{shape, dtype, opt, seq}: opt

def OnnxValue.seq(v: OnnxValue) -> Bool:
  match v:
    case OnnxValue{shape, dtype, opt, seq}: seq

# THE ATTRIBUTE VALUE. `_parse_AttributeProto` (:252-268) fills nine keys --
# `f`, `i`, `s`, `t`, `g`, `floats`, `ints`, `strings` -- and only the one the
# attribute's own `type` names is present; `to_field_name` (:27) is the selector
# and `onx_at_field_of` is its port. So the value is a SUM over those eight, plus
# the NAME and the type code as two more fields, because `_parse_NodeProto`'s
# `attributes = {attr_dict["name"]: attr_dict[to_field_name(...)]}` (:191) keys
# the dict by name and the parser has to keep all three.
#
# `Ag{}` -- the GRAPH arm -- carries nothing because an `OnnxRunner` is this
# file's own class and `_from_subgraph` (:393) needs `_init_from_graph`, which
# needs `PBBufferedReader`. It is a constructor here so the SUM IS EXHAUSTIVE
# over `to_field_name`'s eight entries, and the gate row `onnx_aval_tags`
# prints the eight tags so an empty `Ag{}` cannot hide behind a missing arm.
#
# `Ai{v: H.I64}` rather than `U32`: `read_int64` (:103) is
# `truncate[dtypes.int64](decode_varint())` and ONNX `AttributeProto.i` is
# SIGNED, so an `i` attribute can be negative. The representation is right; the
# DECODE is the wall named in the header.
type AVal is Data:
  Af{v: F32}
  Ai{v: H.I64}
  As{v: String}
  At{v: T.Tensor}
  Ag{}
  Afloats{v: List<&2, F32>}
  Aints{v: List<&2, H.I64>}
  Astrings{v: List<&2, String>}

# the tag is the AttributeType code, so `AVal.at` and `onx_at_field_of` agree by
# construction and the mutation that breaks one of them is visible in the pair.
def AVal.at(a: AVal) -> U32:
  match a:
    case Af{v}: 1
    case Ai{v}: 2
    case As{v}: 3
    case At{v}: 4
    case Ag{}: 5
    case Afloats{v}: 6
    case Aints{v}: 7
    case _: 8

# NO PAYLOAD READERS, and that is a MEASURED wall rather than an omission.
# bend2-constraints rules 26/27 want one hand-written `Type.field` reader per
# field, and that is done for every `Data` RECORD below (`Pc`, `Att`,
# `OnnxNode`, `OpSetId`, `OnnxValue`, `Dim`). It CANNOT be done for one arm of a
# `Data` UNION: a constructor name is not a type name in a parameter position --
# `def Af.f(a: Af)` is `expected : a defined name / observed : Af` -- so the
# reader must take the WHOLE union and then match all eight arms to stay
# exhaustive, and a nested `match` on the binder is refused on top of that
# (bend2-constraints' `divandmod` rule 1, reached from the other side). Eight
# arms times five payloads is forty lines of ladder with no caller: nothing in
# onnx.py reads an attribute payload back, it only reads the TAG
# (`to_field_name`, :27) to know which key the payload is under. So the tag
# reader is ported and the payload readers are absent, with the measurement here
# so the next reader does not spend a cycle re-deriving it.

# `Att` is one entry of the `dict[str, Any]` that `OnnxNode.opts` is. It is a
# LIST of these and not a `Map`: bend2-constraints' `renderer/cstyle` rule 1
# measures that `Map.put` LOSES KEYS and `Map.get` answers a `Sigma`, and the
# whole tree already spells a string-keyed dict as `List<&2, Ent>`
# (`state.bend`'s `Ent`), which is the convention this file follows.
type Att is Data:
  Att{k: String, code: U32, v: AVal}

def Att.k(a: Att) -> String:
  match a:
    case Att{k, code, v}: k

def Att.code(a: Att) -> U32:
  match a:
    case Att{k, code, v}: code

def Att.v(a: Att) -> AVal:
  match a:
    case Att{k, code, v}: v

# `OnnxNode(op, opset_id, inputs, outputs, opts)` -- :64-70
type OnnxNode is Data:
  OnnxNode{op: String, opset: OpSetId, ins: List<&2, String>, outs: List<&2, String>, opts: List<&2, Att>}

def OnnxNode.op(n: OnnxNode) -> String:
  match n:
    case OnnxNode{op, opset, ins, outs, opts}: op

def OnnxNode.opset(n: OnnxNode) -> OpSetId:
  match n:
    case OnnxNode{op, opset, ins, outs, opts}: opset

def OnnxNode.ins(n: OnnxNode) -> List<&2, String>:
  match n:
    case OnnxNode{op, opset, ins, outs, opts}: ins

def OnnxNode.outs(n: OnnxNode) -> List<&2, String>:
  match n:
    case OnnxNode{op, opset, ins, outs, opts}: outs

def OnnxNode.opts(n: OnnxNode) -> List<&2, Att>:
  match n:
    case OnnxNode{op, opset, ins, outs, opts}: opts

# ===========================================================================
# THE GATE
#
# NO FUNCTION-PARAMETER FOLDS, and that is a MEASURED wall: a fold that takes
# `f: U32 -> String` would want `+f`, and `+` is refused on a function value
# because a function in a datatype field forces `Type` (bend2-constraints'
# `List.sort` note, verbatim). So every table row is an explicit LITERAL list of
# the projections, joined once by `onx_join`, and the ROUND TRIP folds call the
# named defs directly. The cost is that the code appears twice -- once in
# `onx_odt_codes` and once in the row's literal -- and the mutation table has a
# mutation for exactly that.
# ===========================================================================

def onx_row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

# THE PRINT IDIOM, once, and it is bend2-constraints' `mixin/creation` rule 20
# for a reason: build a `List<&2, String>` with `List.append` (which is `xs ++
# ys`, so it PUTS THE PIECE AT THE TAIL, i.e. walk order) and hand it to
# `String.join` ONCE at the end. `String.join` is HEAD-FIRST and has no trailing
# separator. The alternative -- `String.concat([acc, x, ","])` inside the fold --
# is the same order and is spelled below where the pieces are not `String`s.
def onx_join.go(xs: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: onx_join.go(t, List.append(&2, String, acc, [x]))

def onx_join(xs: List<&2, String>) -> String: String.join(onx_join.go(xs, Nil{}), ",")

# the `U32` variant. A COUNT is a weaker oracle than the VALUES (bend2-constraints'
# "any check whose oracle is a COUNT rather than a STRUCTURE" is blind), so every
# table row here prints the cells and not just their number.
def onx_u32s.go(xs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: onx_u32s.go(t, List.append(&2, String, acc, [U32.show(x)]))

def onx_u32s(xs: List<&2, U32>) -> String: String.join(onx_u32s.go(xs, Nil{}), ",")

# THE THREE `OnnxDataType` ORDERINGS. `1..16` with the four holes absent, in the
# order the enum DECLARES them, which is the order CPython's `for m in
# OnnxDataType` iterates and so the order the oracle prints.
def onx_odt_codes() -> List<&2, U32>: [1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 16]
def onx_at_codes() -> List<&2, U32>: [1, 2, 3, 4, 5, 6, 7, 8]
def onx_wt_codes() -> List<&2, U32>: [0, 1, 2, 3, 4, 5]

def onx_odt_n() -> U32: U32.from_nat(List.length(&2, U32, onx_odt_codes()))
def onx_at_n() -> U32: U32.from_nat(List.length(&2, U32, onx_at_codes()))
def onx_wt_n() -> U32: U32.from_nat(List.length(&2, U32, onx_wt_codes()))

# THE TABLE ROWS, one literal per table, in the order above.
def onx_odt_tbl() -> String:
  onx_join([onx_odt_name_of(1), onx_odt_name_of(2), onx_odt_name_of(3), onx_odt_name_of(4),
    onx_odt_name_of(5), onx_odt_name_of(6), onx_odt_name_of(7), onx_odt_name_of(9),
    onx_odt_name_of(10), onx_odt_name_of(11), onx_odt_name_of(12), onx_odt_name_of(13),
    onx_odt_name_of(16)])

# THE DTYPE TABLE, which is the row this file exists for: CPython prints
# `OnnxDataType(c).to_dtype().name` and Bend prints `DT.dt_name(DT.to_dtype_of(k))`.
# `S.Dt.nm` IS `DType.name` -- dtype.bend's `promo_mask` spells "unsigned char"
# and "__bf16" for exactly these -- so the two vocabularies are the same and a
# byte diff is a real test rather than a spelling argument.
def onx_odt_dtbl() -> String:
  onx_join([onx_odt_dt_name(1), onx_odt_dt_name(2), onx_odt_dt_name(3), onx_odt_dt_name(4),
    onx_odt_dt_name(5), onx_odt_dt_name(6), onx_odt_dt_name(7), onx_odt_dt_name(9),
    onx_odt_dt_name(10), onx_odt_dt_name(11), onx_odt_dt_name(12), onx_odt_dt_name(13),
    onx_odt_dt_name(16)])

# and the LOOKUP KEY, which is the other half of `to_dtype` -- the string that
# `DTYPES_DICT[self.name.lower()]` is indexed by, NOT the `DType.name` the answer
# carries. The two rows are DIFFERENT strings for ten of the thirteen and a
# mutation that conflates them moves exactly one of them.
def onx_odt_ktbl() -> String:
  onx_join([onx_odt_key_of(1), onx_odt_key_of(2), onx_odt_key_of(3), onx_odt_key_of(4),
    onx_odt_key_of(5), onx_odt_key_of(6), onx_odt_key_of(7), onx_odt_key_of(9),
    onx_odt_key_of(10), onx_odt_key_of(11), onx_odt_key_of(12), onx_odt_key_of(13),
    onx_odt_key_of(16)])

def onx_at_tbl() -> String:
  onx_join([onx_at_name_of(1), onx_at_field_of(1), onx_at_name_of(2), onx_at_field_of(2),
    onx_at_name_of(3), onx_at_field_of(3), onx_at_name_of(4), onx_at_field_of(4),
    onx_at_name_of(5), onx_at_field_of(5), onx_at_name_of(6), onx_at_field_of(6),
    onx_at_name_of(7), onx_at_field_of(7), onx_at_name_of(8), onx_at_field_of(8)])

def onx_wt_tbl() -> String:
  onx_join([onx_wt_name(0), onx_wt_name(1), onx_wt_name(2), onx_wt_name(3),
    onx_wt_name(4), onx_wt_name(5)])

# THE ROUND TRIP, BOTH DIRECTIONS, ONE ROW PER TABLE AND THE PER-ENTRY FOLDS.
# `code -> name -> code` is the claim. The fold calls the named defs directly
# rather than taking them as parameters, which is the wall at the top of this
# section.
def onx_odt_rt.go(cs: List<&2, U32>, acc: Bool) -> Bool:
  match cs:
    case Nil{}: acc
    case +c <> t:
      onx_odt_rt.go(t, Bool.and(acc, U32.is_eq(onx_odt_name_rev.of(onx_odt_name_rev(onx_odt_name_of(c))), c)))

def onx_odt_rt() -> Bool: onx_odt_rt.go(onx_odt_codes(), True{})

# the SECOND hop, `code -> key -> DTYPES_DICT[key]`, which is the one a silent
# wrong-dtype kernel would come from. `dt_name` answering `-` means the lookup
# MISSED, and that is the failure, so the row is "every code resolves and none
# of them resolves to the absent spelling".
def onx_odt_dt_rt.go(cs: List<&2, U32>, acc: Bool) -> Bool:
  match cs:
    case Nil{}: acc
    case +c <> t:
      onx_odt_dt_rt.go(t, Bool.and(acc, Maybe.is_some(&1, S.Dt, onx_odt_dt(c))))

def onx_odt_dt_rt() -> Bool: onx_odt_dt_rt.go(onx_odt_codes(), True{})

# `name -> code -> name` is the THIRD hop and it is the one that catches a
# reverse table entry pointing at the wrong forward cell -- a defect the first
# two hops cannot see, because both of them are consistent with a permutation.
def onx_odt_rt2.go(cs: List<&2, U32>, acc: Bool) -> Bool:
  match cs:
    case Nil{}: acc
    case +c <> t:
      onx_odt_rt2.go(t, Bool.and(acc,
        Bool.and(U32.is_eq(onx_odt_code(onx_odt_key_of(onx_odt_code(onx_odt_key_of(c)))), c),
                 String.eq(onx_odt_key_of(onx_odt_code(onx_odt_key_of(c))), onx_odt_key_of(c)))))

def onx_odt_rt2() -> Bool: onx_odt_rt2.go(onx_odt_codes(), True{})

def onx_at_rt.go(ts: List<&2, U32>, acc: Bool) -> Bool:
  match ts:
    case Nil{}: acc
    case +t2 <> ts2:
      onx_at_rt.go(ts2, Bool.and(acc,
        U32.is_eq(onx_at_name_rev.of(onx_at_name_rev(onx_at_name_of(t2))), t2)))

def onx_at_rt() -> Bool: onx_at_rt.go(onx_at_codes(), True{})

def onx_at_rt2.go(ts: List<&2, U32>, acc: Bool) -> Bool:
  match ts:
    case Nil{}: acc
    case +t2 <> ts2:
      onx_at_rt2.go(ts2, Bool.and(acc,
        U32.is_eq(onx_at_code(onx_at_field_of(onx_at_code(onx_at_field_of(t2)))), t2)))

def onx_at_rt2() -> Bool: onx_at_rt2.go(onx_at_codes(), True{})

def onx_wt_rt.go(ts: List<&2, U32>, acc: Bool) -> Bool:
  match ts:
    case Nil{}: acc
    case +t2 <> ts2:
      onx_wt_rt.go(ts2, Bool.and(acc, U32.is_eq(onx_wt_code(onx_wt_name(t2)), t2)))

def onx_wt_rt() -> Bool: onx_wt_rt.go(onx_wt_codes(), True{})

# A `Maybe<&1, T>` is read ONCE and cannot be `+` (bend2-constraints'
# `divandmod` rule 1), so "is every code a member" is a fold with a `Bool`
# accumulator and NOT a `Maybe` one -- the recorded
# "A `Maybe` CANNOT BE A FOLD'S ACCUMULATOR" shape.
def onx_odt_all_members.go(cs: List<&2, U32>, acc: Bool) -> Bool:
  match cs:
    case Nil{}: acc
    case +c <> t:
      onx_odt_all_members.go(t, Bool.and(acc, Maybe.is_some(&1, String, onx_odt_name(c))))

def onx_odt_all_members() -> Bool: onx_odt_all_members.go(onx_odt_codes(), True{})

# THE FOUR HOLES. Codes 0, 8, 14 and 15 are not members. CPython raises
# `ValueError: 8 is not a valid OnnxDataType`; the port answers `None`. The row
# prints the FIVE answers -- four holes PLUS code 1 as the positive control --
# so a reader broken into answering `None{}` for everything goes red, which a
# row of four absences could not see.
def onx_hole_codes() -> List<&2, U32>: [0, 1, 8, 14, 15]

def onx_odt_holes() -> String:
  onx_join([onx_odt_key_of(0), onx_odt_key_of(1), onx_odt_key_of(8),
    onx_odt_key_of(14), onx_odt_key_of(15)])

def onx_odt_holes_rt() -> Bool:
  Bool.and(Bool.not(Maybe.is_some(&1, String, onx_odt_key(0))),
  Bool.and(Maybe.is_some(&1, String, onx_odt_key(1)),
  Bool.and(Bool.not(Maybe.is_some(&1, String, onx_odt_key(8))),
  Bool.and(Bool.not(Maybe.is_some(&1, String, onx_odt_key(14))),
           Bool.not(Maybe.is_some(&1, String, onx_odt_key(15)))))))

# the same four holes through the DTYPE path, which is where a dense table would
# have answered a dtype instead of nothing.
def onx_odt_hole_dts() -> String:
  onx_join([onx_odt_dt_name(0), onx_odt_dt_name(1), onx_odt_dt_name(8),
    onx_odt_dt_name(14), onx_odt_dt_name(15)])

# THE INVERSE, TWICE OVER. `onx_odt_inv` is `code -> dtype -> code`, the round
# trip through `DT.to_dtype_of`, and it is the row that says the thirteen keys
# land on thirteen DISTINCT dtypes. `onx_odt_inv_tbl` prints all thirteen answers
# so a collision is visible as two identical cells rather than as a red row, and
# `onx_odt_inv_neg` is the negative fixture -- a dtype the table never produces
# answers 0 -- because a predicate whose fixtures are all POSITIVE is the
# `device.bend` gate lesson restated.
def onx_odt_inv_one.of(m: Maybe<&1, S.Dt>) -> U32:
  match m:
    case Some{d}: onx_odt_of_dt(onx_odt_codes(), d)
    case None{}: 0

def onx_odt_inv_one(c: U32) -> U32: onx_odt_inv_one.of(onx_odt_dt(c))

def onx_odt_inv_real.go(cs: List<&2, U32>, acc: Bool) -> Bool:
  match cs:
    case Nil{}: acc
    case +c <> t:
      onx_odt_inv_real.go(t, Bool.and(acc, U32.is_eq(onx_odt_inv_one(c), c)))

def onx_odt_inv() -> Bool: onx_odt_inv_real.go(onx_odt_codes(), True{})

def onx_odt_inv_tbl.go(cs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}: acc
    case c <> t: onx_odt_inv_tbl.go(t, List.append(&2, String, acc, [U32.show(onx_odt_inv_one(c))]))

def onx_odt_inv_tbl() -> String: String.join(onx_odt_inv_tbl.go(onx_odt_codes(), Nil{}), ",")

def onx_odt_inv_neg() -> Bool: U32.is_eq(onx_odt_of_dt(onx_odt_codes(), DT.dtypes.weakfloat()), 0)

# the `AVal` sum's tag set must be `to_field_name`'s EIGHT codes -- the row that
# says an empty `Ag{}` did not smuggle a ninth constructor past the table.
# the `At` arm's fixture. `T.Tensor` is `Tensor{ar, uop, is_param, grad}` with a
# LIVE `O.Arena` in it, so a constructor literal cannot be written inline -- the
# arena is affine and `O.Arena.empty()` is the substrate's own bottom. One node,
# index 0, and that is all the TENSOR arm needs: the row is about the TAG. It is
# a DEF and not a `let` because a `do` block cannot bind a pure value
# (bend2-constraints' `weak` rule 8) and the row is a fold over a literal list.
def onx_g_tensor() -> T.Tensor: T.tn_new(O.Arena.empty(), 0)

def onx_aval_tags() -> String:
  onx_join([U32.show(AVal.at(Af{0.0})), U32.show(AVal.at(Ai{H.i64_of_i32(0)})),
    U32.show(AVal.at(As{"x"})), U32.show(AVal.at(Afloats{Nil{}})),
    U32.show(AVal.at(At{onx_g_tensor()})), U32.show(AVal.at(Ag{})),
    U32.show(AVal.at(Aints{Nil{}})), U32.show(AVal.at(Astrings{Nil{}}))])

# DOMAIN: the nine (member, value) pairs, walked from the type's own nine
# constructors rather than a hand-typed literal, so a mutation cannot make the
# row disagree with the type.
def onx_dom_tbl.go(ds: List<&2, Dom>, acc: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}: acc
    case +d <> t:
      onx_dom_tbl.go(t, List.append(&2, String, acc, [String.concat([Dom.n(d), "/", Dom.s(d)])]))

def onx_dom_train.go(ds: List<&2, Dom>, acc: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}: acc
    case d <> t:
      onx_dom_train.go(t, List.append(&2, String, acc, [Bool.show(onx_dom_is_training(d))]))

def onx_doms() -> List<&2, Dom>:
  [DomOnnx{}, DomOnnxMl{}, DomTrain{}, DomPrevTrain{}, DomMsContrib{}, DomMsNchwc{},
   DomMsExp{}, DomAten{}, DomTinygrad{}]

def onx_dom_tbl() -> String: String.join(onx_dom_tbl.go(onx_doms(), Nil{}), ",")
def onx_dom_training() -> String: String.join(onx_dom_train.go(onx_doms(), Nil{}), ",")

def onx_dom_n() -> U32: U32.from_nat(List.length(&2, Dom, onx_doms()))

# `from_onnx`'s FOUR-way answer: the empty string and a literal "ai.onnx" both
# land on ONNX, a known non-default domain lands on itself, and an unknown one is
# refused. Four rows and not one, because a one-row version passes with the
# empty-string arm missing -- the `nn/state` gate lesson about an arm with no
# fixture being dead code.
def onx_dom_empty() -> Bool: String.eq(Dom.s(onx_dom.of(onx_dom(""))), "ai.onnx")
def onx_dom_onnx() -> Bool: String.eq(Dom.s(onx_dom.of(onx_dom("ai.onnx"))), "ai.onnx")
def onx_dom_tiny() -> Bool: String.eq(Dom.s(onx_dom.of(onx_dom("org.tinygrad"))), "org.tinygrad")
def onx_dom_ms() -> Bool: String.eq(Dom.s(onx_dom.of(onx_dom("com.microsoft"))), "com.microsoft")
def onx_dom_unknown() -> Bool: Maybe.is_none(&1, Dom, onx_dom("org.example.nope"))
def onx_dom_unknown2() -> Bool: Maybe.is_none(&1, Dom, onx_dom("AI.ONNX"))
def onx_dom_unknown3() -> Bool: Maybe.is_none(&1, Dom, onx_dom("ai.onnx.ml2"))

# the name round trip: `from_onnx(Domain(x).value).value == Domain(x).value`, for
# all nine. Python's `Domain(domain)` IS that lookup, so CPython answers it.
def onx_dom_rt.go(ds: List<&2, Dom>, acc: Bool) -> Bool:
  match ds:
    case Nil{}: acc
    case +d <> t:
      onx_dom_rt.go(t, Bool.and(acc,
        Bool.and(Maybe.is_some(&1, Dom, onx_dom(Dom.s(d))),
                 String.eq(Dom.s(onx_dom.of(onx_dom(Dom.s(d)))), Dom.s(d)))))

def onx_dom_rt() -> Bool: onx_dom_rt.go(onx_doms(), True{})

# required_input_python_consts: the whole table as `name:ix,ix`, plus the lookup
# on a present key, on an absent key (`()` at :435), and the `idx in` test with
# BOTH a hit and two misses so the predicate is not vacuously true.
def onx_pc_tbl.go(ps: List<&2, Pc>, acc: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}: acc
    case +p <> t:
      onx_pc_tbl.go(t, List.append(&2, String, acc,
        [String.concat([Pc.n(p), ":", onx_u32s(Pc.i(p))])]))

def onx_pc_tbl() -> String: String.join(onx_pc_tbl.go(required_input_python_consts(), Nil{}), ",")

def onx_pc_n() -> U32: U32.from_nat(List.length(&2, Pc, required_input_python_consts()))

# the two comprehension-built rungs called out separately, because Python builds
# thirteen of the thirty-eight that way and a mutation that drops one of them
# moves THIS and moves the count row too -- the pair is the claim.
def onx_pc_reduce() -> String: onx_u32s(onx_pc_ixs(required_input_python_consts(), "ReduceLogSumExp"))
def onx_pc_adam() -> String: onx_u32s(onx_pc_ixs(required_input_python_consts(), "Adam"))
def onx_pc_slice() -> String: onx_u32s(onx_pc_ixs(required_input_python_consts(), "Slice"))
def onx_pc_range() -> String: onx_u32s(onx_pc_ixs(required_input_python_consts(), "Range"))
def onx_pc_pad() -> String: onx_u32s(onx_pc_ixs(required_input_python_consts(), "Pad"))
def onx_pc_dropout() -> String: onx_u32s(onx_pc_ixs(required_input_python_consts(), "Dropout"))
def onx_pc_hann() -> String: onx_u32s(onx_pc_ixs(required_input_python_consts(), "HannWindow"))
def onx_pc_absent() -> String: onx_u32s(onx_pc_ixs(required_input_python_consts(), "Conv"))
def onx_pc_absent2() -> String: onx_u32s(onx_pc_ixs(required_input_python_consts(), "Softmax"))

def onx_pc_has_hit() -> Bool: onx_pc_has(required_input_python_consts(), "Pad", 2)
def onx_pc_has_miss() -> Bool: Bool.not(onx_pc_has(required_input_python_consts(), "Pad", 0))
def onx_pc_has_abs() -> Bool: Bool.not(onx_pc_has(required_input_python_consts(), "Conv", 0))
def onx_pc_has_neg() -> Bool: onx_pc_has(required_input_python_consts(), "Slice", 3)


# ===========================================================================
# STAGE 2. THE OP TABLE AND THE PADDING ARITHMETIC.
#
# `get_onnx_ops` (:475-1319) is 845 lines and two different things. ONE HUNDRED
# SEVENTY-ONE of those lines are the names of the operator dictionary the final
# `return {...}` (:1308-1317) assembles, and that dictionary is PURE DATA built
# from two dict comprehensions plus one `locals()` comprehension. The other 574
# are 167 function BODIES, and every one of those bodies is a single line
# calling a mixin method that belongs to another file.
#
# So Stage 2 ports the data half and Stage 4 names the walls for the code half.
# The data half is not a consolation prize: `_select_op` (:415-423) is the
# version ROUTER that decides which of `Softmax`'s two bodies a model gets, and
# its two failure modes (`op not supported`, `not supported for domain D and
# version V`) are what a real load hits when a model is newer than this tree.
# ===========================================================================

# ---------------------------------------------------------------------------
# THE OP NAME TABLE -- `onnx_ops` (:1308-1317), 171 keys.
#
# Python builds it in three pieces and the ORDER is a `dict` insertion order:
#   :1310-1312  thirty-six `getattr(Tensor, op.lower())` entries,
#   :1314       every UPPERCASE local that is a function and not `_`-prefixed,
#   :1316       every local that is a dict (the four versioned ops).
# The port keeps the SET and sorts it, for two reasons that are both facts and
# neither is a convenience: a `locals()` call has no Bend spelling at all (a
# function value in a datatype field forces `Type`, bend2-constraints'
# `divandmod`), and a sorted set is a claim a byte diff can check while a
# hand-maintained declaration order is a claim only a reader can check.
# `List.sort` is stable and its comparator here is `String.is_lt`, a TOTAL order
# -- the recorded failure mode is a comparator that answers False in both
# directions, which sorts in reverse with no diagnostic anywhere.
# `onnx_ops_n` pins the count of `onnx_ops`'s OWN literal, so a dropped or
# duplicated NAME is visible. MEASURED LIMITATION: it does NOT see a dropped table
# ARM elsewhere -- the count and the table are two independent transcriptions of
# one Python list, and M3 in the mutation table deletes `OnnxDataType`'s `BOOL`
# arm and moves `onnx_odt_rt`, `onnx_odt_all` and `onnx_odt_tbl` while
# `onnx_odt_n` stays `True`. A COUNT row pins the number of entries in the
# fixture, not the number of arms in every table the fixture drives.
# ---------------------------------------------------------------------------
def onnx_ops() -> List<&2, String>:
  List.sort(~String, String.is_lt, [
    "Abs", "Acos", "Acosh", "Adagrad", "Adam", "Add", "AffineGrid", "And", "ArgMax", "ArgMin",
    "ArrayFeatureExtractor", "Asin", "Asinh", "Atan", "Atanh", "Attention", "AveragePool",
    "BatchNormalization", "BiasGelu", "Binarizer", "BitwiseAnd", "BitwiseNot", "BitwiseOr",
    "BitwiseXor", "BlackmanWindow", "Cast", "CastLike", "Ceil", "Celu", "CenterCropPad", "Clip",
    "Compress", "Concat", "Constant", "ConstantOfShape", "Contiguous", "Conv", "ConvInteger",
    "ConvTranspose", "Cos", "Cosh", "CumSum", "DepthToSpace", "DequantizeLinear", "Div", "Dropout",
    "DynamicQuantizeLinear", "Einsum", "Elu", "EmbedLayerNormalization", "Equal", "Erf", "Exp",
    "Expand", "EyeLike", "FastGelu", "Flatten", "Floor", "Gather", "GatherElements", "GatherND",
    "Gelu", "Gemm", "GlobalAveragePool", "GlobalMaxPool", "Gradient", "Greater", "GreaterOrEqual",
    "GroupNormalization", "HammingWindow", "HannWindow", "HardSigmoid", "HardSwish", "Hardmax",
    "Identity", "If", "ImageDecoder", "InstanceNormalization", "IsInf", "IsNaN", "LRN",
    "LayerNormalization", "LeakyRelu", "Less", "LessOrEqual", "Log", "LogSoftmax",
    "LpNormalization", "MatMul", "MatMulInteger", "Max", "MaxPool", "MaxUnpool", "Mean",
    "MeanVarianceNormalization", "Min", "Mish", "Mod", "Momentum", "Mul", "Neg",
    "NegativeLogLikelihoodLoss", "NonZero", "Not", "OneHot", "OptionalGetElement",
    "OptionalHasElement", "Or", "PRelu", "Pad", "Pow", "QLinearAdd", "QLinearConv",
    "QLinearGlobalAveragePool", "QLinearMatMul", "QLinearMul", "QuantizeLinear",
    "RMSNormalization", "Range", "Reciprocal", "ReduceL1", "ReduceL2", "ReduceLogSum",
    "ReduceLogSumExp", "ReduceMax", "ReduceMean", "ReduceMin", "ReduceProd", "ReduceSum",
    "ReduceSumSquare", "Relu", "Reshape", "Resize", "RotaryEmbedding", "Round", "Scatter",
    "ScatterElements", "ScatterND", "Selu", "Shape", "Shrink", "Sigmoid", "Sign", "Sin", "Sinh",
    "Size", "SkipLayerNormalization", "Slice", "Softmax", "SoftmaxCrossEntropyLoss", "Softplus",
    "Softsign", "SpaceToDepth", "Split", "Sqrt", "Squeeze", "Sub", "Sum", "Swish", "Tan", "Tanh",
    "TensorScatter", "ThresholdedRelu", "Tile", "TopK", "Transpose", "Trilu", "Unsqueeze",
    "Upsample", "Where", "Xor"])

def onnx_ops_n() -> U32: U32.from_nat(List.length(&2, String, onnx_ops()))

def onx_op_in.go(xs: List<&2, String>, +nm: String, acc: Bool) -> Bool:
  match xs:
    case Nil{}: acc
    case x <> t: onx_op_in.go(t, nm, Bool.or(acc, String.eq(x, nm)))

def onx_op_in(nm: String) -> Bool: onx_op_in.go(onnx_ops(), nm, False{})

# ---------------------------------------------------------------------------
# THE IMPLEMENTATION IDENTITY, which is a THREE-WAY table and not one. Measured
# in CPython: `onnx_ops['Conv'].__name__` is `'Conv'`,
# `onnx_ops['Neg'].__name__` is `'neg'` (it is `getattr(Tensor, 'neg')`, :1310),
# and `onnx_ops['Adam'].__name__` is `'___wrapper'` (the `_onnx_training`
# decorator's inner function, :534). A port that answered every name with itself
# would be right for 128 of 171 and would make the version router name a body
# that does not exist for the other 43.
# ---------------------------------------------------------------------------
def onx_tensor_op(nm: String) -> Maybe<&1, String>:
  match nm:
    case "Neg": Some{"neg"}
    case "Reciprocal": Some{"reciprocal"}
    case "Sqrt": Some{"sqrt"}
    case "Sign": Some{"sign"}
    case "Abs": Some{"abs"}
    case "Exp": Some{"exp"}
    case "Log": Some{"log"}
    case "Mish": Some{"mish"}
    case "Sin": Some{"sin"}
    case "Cos": Some{"cos"}
    case "Tan": Some{"tan"}
    case "Asin": Some{"asin"}
    case "Acos": Some{"acos"}
    case "Atan": Some{"atan"}
    case "Relu": Some{"relu"}
    case "Sigmoid": Some{"sigmoid"}
    case "MatMul": Some{"matmul"}
    case "Floor": Some{"floor"}
    case "Ceil": Some{"ceil"}
    case "IsNaN": Some{"isnan"}
    case "Softplus": Some{"softplus"}
    case "HardSwish": Some{"hardswish"}
    case "Where": Some{"where"}
    case "Mul": Some{"mul"}
    case "Sinh": Some{"sinh"}
    case "Cosh": Some{"cosh"}
    case "Tanh": Some{"tanh"}
    case "Softsign": Some{"softsign"}
    case "Asinh": Some{"asinh"}
    case "Acosh": Some{"acosh"}
    case "Atanh": Some{"atanh"}
    case "Elu": Some{"elu"}
    case "Celu": Some{"celu"}
    case "Selu": Some{"selu"}
    case "Round": Some{"round"}
    case "Erf": Some{"erf"}
    case _: None{}

# `@_onnx_training(...)` wraps the body in `___wrapper` -- :534. Three ops, and
# the DECORATOR is what gives them their `__name__`.
def onx_training_op(nm: String) -> Maybe<&1, String>:
  match nm:
    case "Adagrad": Some{"___wrapper"}
    case "Adam": Some{"___wrapper"}
    case "Momentum": Some{"___wrapper"}
    case _: None{}

# ---------------------------------------------------------------------------
# the four VERSIONED ops, as a flat `Data` list rather than a nested dict. The
# (domain, version) pairs are CPython's `OpSetId` keys and they are the INPUT to
# the router below, so they are data and they are gated.
type Ver is Data:
  Ver{nm: String, dom: Dom, ver: U32, impl: String}

def Ver.n(v: Ver) -> String:
  match v:
    case Ver{nm, dom, ver, impl}: nm

def Ver.d(v: Ver) -> Dom:
  match v:
    case Ver{nm, dom, ver, impl}: dom

def Ver.v(v: Ver) -> U32:
  match v:
    case Ver{nm, dom, ver, impl}: ver

def Ver.i(v: Ver) -> String:
  match v:
    case Ver{nm, dom, ver, impl}: impl

def onnx_ops_ver() -> List<&2, Ver>:
  [Ver{"Attention", DomOnnx{}, 1, "attention_onnx"},
   Ver{"Attention", DomMsContrib{}, 1, "attention_contrib"},
   Ver{"Contiguous", DomTinygrad{}, 1, "contiguous_1"},
   Ver{"Dropout", DomOnnx{}, 6, "dropout_6"},
   Ver{"Dropout", DomOnnx{}, 7, "dropout_7"},
   Ver{"Softmax", DomOnnx{}, 1, "softmax_1"},
   Ver{"Softmax", DomOnnx{}, 13, "softmax_13"}]

def onnx_ops_ver_n() -> U32: U32.from_nat(List.length(&2, Ver, onnx_ops_ver()))

# `isinstance(impl, types.FunctionType)` -- :418. A name with a `Ver` row is a
# dict and everything else in the table is a function.
def onx_op_is_versioned.go(vs: List<&2, Ver>, +nm: String, acc: Bool) -> Bool:
  match vs:
    case Nil{}: acc
    case v <> t: onx_op_is_versioned.go(t, nm, Bool.or(acc, String.eq(Ver.n(v), nm)))

def onx_op_is_versioned(nm: String) -> Bool: onx_op_is_versioned.go(onnx_ops_ver(), nm, False{})

# `if isinstance(impl, self.onnx_ops[op], types.FunctionType): return impl` --
# :418. The domain and version are NOT consulted on this arm, which is the whole
# point of the arm and the reason `Contiguous` works from any opset.
type Sel is Data:
  Sel{hit: Bool, ver: U32, impl: String}

def Sel.hit(s: Sel) -> Bool:
  match s:
    case Sel{hit, ver, impl}: hit

def Sel.ver(s: Sel) -> U32:
  match s:
    case Sel{hit, ver, impl}: ver

def Sel.impl(s: Sel) -> String:
  match s:
    case Sel{hit, ver, impl}: impl

def onx_sel_plain(+nm: String) -> Maybe<&1, String>:
  Bool.pick(Maybe<&1, String>, Maybe.is_some(&1, String, onx_tensor_op(nm)),
    onx_tensor_op(nm),
    Bool.pick(Maybe<&1, String>, Maybe.is_some(&1, String, onx_training_op(nm)),
      Some{"___wrapper"}, Some{nm}))


# `impl_opset.domain == required_opset.domain and impl_opset.version <=
# required_opset.version` -- :421. Nine-and-nine arms because `Dom` is a sum and
# `String.eq(Dom.n(a), Dom.n(b))` would be the same answer written as a
# comparison on a computed string.
def onx_dom_same(a: Dom, b: Dom) -> Bool:
  match a b:
    case DomOnnx{} DomOnnx{}: True{}
    case DomOnnxMl{} DomOnnxMl{}: True{}
    case DomTrain{} DomTrain{}: True{}
    case DomPrevTrain{} DomPrevTrain{}: True{}
    case DomMsContrib{} DomMsContrib{}: True{}
    case DomMsNchwc{} DomMsNchwc{}: True{}
    case DomMsExp{} DomMsExp{}: True{}
    case DomAten{} DomAten{}: True{}
    case DomTinygrad{} DomTinygrad{}: True{}
    case _ _: False{}

# NO `hit` TERM AT ALL, and this was a real bug the gate caught TWICE. The
# eligibility test is a property of ONE `OpSetId` against the required opset and
# nothing else: `impl_opset.domain == required_opset.domain and
# impl_opset.version <= required_opset.version` (:421). The first version AND-ed
# `not hit` in, which made the fold take the FIRST eligible row -- `Softmax` at
# opset 13 answered `softmax_1` where CPython answers `softmax_13`; the repair
# AND-ed `hit` in, which made eligibility require a hit to ALREADY exist and
# answered `ERR` for every versioned op. Python's comprehension at :420-421 KEEPS
# every eligible entry and the max is taken afterwards at :423, so the fold must
# not short-circuit on what it has already found.
def onx_elig(+v: Ver, +dom: Dom, +nm: String, +ver: U32) -> Bool:
  Bool.and(String.eq(Ver.n(v), nm),
    Bool.and(onx_dom_same(Ver.d(v), dom), U32.is_le(Ver.v(v), ver)))


def onx_sel_max.go(vs: List<&2, Ver>, +nm: String, +dom: Dom, +ver: U32, +hit: Bool, +bv: U32, +bi: String) -> Sel:
  match vs:
    case Nil{}: Sel{hit, bv, bi}
    case +v <> t:
      onx_sel_max.go(t, nm, dom, ver,
        Bool.or(hit, onx_elig(v, dom, nm, ver)),
        Bool.pick(U32, onx_elig(v, dom, nm, ver), U32.max(bv, Ver.v(v)), bv),
        Bool.pick(String, onx_elig(v, dom, nm, ver),
          Bool.pick(String, U32.is_gt(Ver.v(v), bv), Ver.i(v), bi), bi))

def onx_sel_max(nm: String, dom: Dom, ver: U32, +hit: Bool, +bv: U32, +bi: String) -> Sel:
  onx_sel_max.go(onnx_ops_ver(), nm, dom, ver, hit, bv, bi)


# THE PLAIN-FUNCTION ARM, in CPython's own order: unknown op (:416), plain
# function (:418), eligible-by-(domain, <= version) (:420-421), the max (:423).
# Four Bool PARAMETERS rather than a nested `Bool.pick`, because `Ap`-style
# dispatch on a computed value is what every `.of` split in this file exists to
# avoid, and because the three rows the gate prints are then three defs the gate
# can call directly.
def onx_sel(+nm: String, +dom: Dom, +ver: U32) -> Maybe<&1, String>:
  Bool.pick(Maybe<&1, String>, Bool.not(onx_op_in(nm)), None{},
    Bool.pick(Maybe<&1, String>, Bool.not(onx_op_is_versioned(nm)),
      onx_sel_plain(nm),
      Bool.pick(Maybe<&1, String>, Bool.not(Sel.hit(onx_sel_max(nm, dom, ver, False{}, 0, ""))), None{},
        Some{Sel.impl(onx_sel_max(nm, dom, ver, False{}, 0, ""))})))

# `{impl_opset.version: impl_fxn for ... if domain == and version <=}` and
# `eligible_ops[max(eligible_ops.keys())]` -- :420-423. `onx_tensor_op` above is
# called TWICE rather than bound once, and that is the recorded escape from "a
# `Maybe` is read once and cannot be `+`": the def is PURE, so the second call
# recomputes the same answer and the repetition is free of state and expensive
# only in time.
#
# The `Maybe` result is likewise recomputed -- `onx_sel_max` is called twice in
# `onx_sel` -- for the same reason. `Sel` is a `Data` record because the
# accumulator is a triple of THREE DIFFERENT types and a `Maybe` cannot be a
# fold's accumulator (bend2-constraints, "A `Maybe` CANNOT BE A FOLD'S
# ACCUMULATOR").
# `U32.max` on the versions, and the name test, are the two halves of
# `eligible_ops[max(eligible_ops.keys())]`. A tie is impossible: Python's dict
# keys are the `OpSetId`s and are unique per domain, so two rows cannot share a
# version inside one domain.
# ---------------------------------------------------------------------------
# THE PADDING ARITHMETIC. `_resolve_pool_pads` (:495-500) and the two helpers
# it calls are the only pure-integer functions in `get_onnx_ops`, and they are
# the ones that decide what `Conv`, `ConvTranspose`, `MaxPool`, `AveragePool`
# and `Pad` actually compute -- so they are the portable core of the op table
# and they are gated against CPython.
#
# WHY THEY ARE INTEGERS AND NOT TENSORS, which is the decision that made this
# stage possible: `_resolve_pool_pads(x, ...)` reads `x.shape` (:497) and
# NOTHING ELSE off `x`. Its output is a padding tuple. So the port takes the
# spatial shape as a `List<&2, U32>` and nothing about it is a weakening.
#
# WHY `H.I64` AND NOT `U32`, which is the trap: `pads` can be NEGATIVE.
# `(o-1)*s + k - i` (:500) is `k - i` whenever the stride exceeds the input
# size, and MEASURED with shape `(1,3,8,8)`, `k=(3,3)`, `s=(8,8)`: `o` is 1,
# so the pad is `3 - 8 = -5`. Python's `//` FLOORS, and the floor of a negative
# is not `U32.div`. That is why `_auto_pad` runs on `H.I64` and why the file
# carries its own `onx_halve`.
# ---------------------------------------------------------------------------

# `AUTO_PAD_OPTIONS = Literal["NOTSET", "SAME_UPPER", "SAME_LOWER", "VALID"]`
# -- :489. A `Data` sum rather than a string, because every arm of both helpers
# is a comparison against one of the four and a `match` on a `Data` value is
# exhaustive by the compiler, while a `String` match is not (bend2-constraints'
# `upat` rule 1: a `match` on a `String` needs a `case _:` and without one the
# error is a PARSE error naming an SCon).
type Ap is Data:
  ApNotset{}
  ApSameUpper{}
  ApSameLower{}
  ApValid{}

def Ap.nm(a: Ap) -> String:
  match a:
    case ApNotset{}: "NOTSET"
    case ApSameUpper{}: "SAME_UPPER"
    case ApSameLower{}: "SAME_LOWER"
    case _: "VALID"

def Ap.isvalid(a: Ap) -> Bool:
  match a:
    case ApValid{}: True{}
    case _: False{}

def Ap.isnotset(a: Ap) -> Bool:
  match a:
    case ApNotset{}: True{}
    case _: False{}

def Ap.isupper(a: Ap) -> Bool:
  match a:
    case ApSameUpper{}: True{}
    case _: False{}

# `floor(x / 2)` for a two's complement 64-bit word. `U32.shrn` is LOGICAL
# (bend2-constraints §2), so the sign has to be put back into bit 31 of the
# high word, and only when the low word's bit 0 was set -- which is the standard
# identity `lo' = (lo >> 1) | ((lo & 1) << 31)`.
# `floor(x/2)` is `(x >> 1) ARITHMETICALLY` on the SIXTY-FOUR-BIT word, and
# `U32.shrn` is LOGICAL (bend2-constraints §2), so the two words each have to be
# reassembled by hand. The correct identities, from "bit i of the result is bit
# i+1 of x":
#     lo' = (lo >>> 1) | ((hi & 1) << 31)      # UNCONDITIONAL -- a bit shuffle
#     hi' = (hi >>> 1) | (sign ? 1<<31 : 0)    # the only SIGN extension
# THREE bugs got this file, all caught by the gate, and the third is the one
# worth writing down:
#   1. THE FILL WAS NOT CONDITIONAL ON THE SIGN, so `floor(3/2)` answered
#      `-2147483647` (`onnx_ap_su33`, where CPython says `[1,1,2,2]`).
#   2. THE LOW WORD'S FILL WAS TAKEN FROM THE LOW WORD'S OWN BIT 0 instead of
#      from `hi & 1`, so `floor(-2/2)` answered `0x7FFFFFFF:0xFFFFFFFF`.
#   3. ... and the HIGH word's fill was taken from the LOW word's bit 0, so the
#      same value came out `0xFFFFFFFF:0x7FFFFFFF`. `-5` (`lo & 1 == 1`) answers
#      CORRECTLY under all three, which is why only the EVEN negative exposed
#      them: `onnx_ap_su_neg2` is the row that saw it, where CPython says
#      `[-1, 0, -1, 1]`.
# THE SIGN IS A `Bool` PARAMETER AND NOT A CALL because a `match` may not
# scrutinise a call (bend2-constraints rule 2), and `H.i64_is_neg` is a call.
def onx_halve_lo(+x: H.I64) -> U32:
  U32.or(U32.shrn(H.lo32(x), 1n), U32.shln(U32.and(H.hi32(x), 1), 31n))

def onx_halve_hi(neg: Bool, +x: H.I64) -> U32:
  match neg:
    case True{}: U32.or(U32.shrn(H.hi32(x), 1n), 2147483648)
    case _: U32.shrn(H.hi32(x), 1n)

def onx_halve.of(+neg: Bool, +x: H.I64) -> H.I64:
  H.i64_of_hi_lo(onx_halve_hi(neg, x), onx_halve_lo(x))

def onx_halve(+x: H.I64) -> H.I64: onx_halve.of(H.i64_is_neg(x), x)

# A CORRECT 64-BIT SUBTRACTION, carried here because `helpers.bend`'s is WRONG.
# MEASURED on `H.i64_sub` (helpers.bend:1241-1243), against CPython:
#     case            CPython          H.i64_sub
#     5 - 7           4294967295:4294967294   0:4294967294      <- no borrow
#     1 - (-1)        0:2             1:2                <- no borrow
#     -5 - 3          4294967295:4294967288   4294967295:4294967288   (ok)
# `i64_of_hi_lo(sub(hi32(a), hi32(b)), sub(lo32(a), lo32(b)))` subtracts the two
# words INDEPENDENTLY and the borrow out of the low word is DISCARDED, so the
# answer is right only when the low words do not borrow. `H.i64_add` (helpers.bend
# :1238-1240) has the same defect with the carry: `(-1) + (-1)` answers
# `4294967294:4294967294` where CPython says `4294967295:4294967294`.
# `helpers.bend` is READ-ONLY to this unit, so the repair is local and the two
# owner lines are named here and in the report. `H.i64_cmp` IS correct -- it
# compares the signs first -- so only the arithmetic is affected.
#
# THE BORROW, which is the whole of the difference:
#     hi' = hi(a) - hi(b) - (1 if lo(a) < lo(b) else 0)
#     lo' = lo(a) - lo(b)                       (U32's wrap is the mod-2^32 part)
def onx_isub.borrow(lt: Bool) -> U32:
  Bool.pick(U32, lt, 1, 0)

def onx_isub.of(lt: Bool, +a: H.I64, +b: H.I64) -> H.I64:
  H.i64_of_hi_lo(U32.sub(U32.sub(H.hi32(a), H.hi32(b)), onx_isub.borrow(lt)),
    U32.sub(H.lo32(a), H.lo32(b)))

def onx_isub(+a: H.I64, +b: H.I64) -> H.I64:
  onx_isub.of(U32.is_lt(H.lo32(a), H.lo32(b)), a, b)

# `onx_i64s` is the ONE place the port converts. Every pad in `onnx.py` is a
# Python int and the negative ones exist, so `_onnx_pads_to_tiny_pads` takes
# `H.I64` throughout and the `U32` callers widen first. One function rather than
# two spellings of the same walk.
def onx_i64s.go(xs: List<&2, U32>, acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match xs:
    case Nil{}: acc
    case x <> t: onx_i64s.go(t, List.append(&2, H.I64, acc, [H.i64_of_i32(x)]))

def onx_i64s(xs: List<&2, U32>) -> List<&2, H.I64>: onx_i64s.go(xs, Nil{})

# A PAIR IS A `Type`, so it cannot be a list element and cannot be spelled
# `(A, B)` here -- bend2-constraints' `movement` rule 1 -- so the two halves are a
# two-field `Data` record, the tree's own answer (`Marg`, `Flags`, `Step`).
type Hal is Data:   # NOT `Pair` -- that is a Base constructor, rule 24's family
  Hal{a: List<&2, H.I64>, b: List<&2, H.I64>}

def Hal.a(p: Hal) -> List<&2, H.I64>:
  match p:
    case Hal{a, b}: a

def Hal.b(p: Hal) -> List<&2, H.I64>:
  match p:
    case Hal{a, b}: b

# TWO LISTS IN ONE WALK. `Tl` is the head of the second list carried as a value,
# because a `match` on two LIST scrutinees is unavailable (bend2-constraints'
# `schedule` rule A: a `match` nested inside a `case h <> t:` LIST arm is
# REFUSED, for a `Bool`, a `U32` and a `List` scrutinee alike) and because
# `List.get` answers a `Maybe`, which would then need a `.of` split at every read.
type Tl is Data:
  Tl{hd: H.I64, tl: List<&2, H.I64>}
  Tn{}

def Tl.of(xs: List<&2, H.I64>) -> Tl:
  match xs:
    case Nil{}: Tn{}
    case h <> t: Tl{h, t}

def Tl.hd(t: Tl) -> H.I64:
  match t:
    case Tl{hd, tl}: hd
    case _: H.i64_of_i32(0)

def Tl.tl(t: Tl) -> List<&2, H.I64>:
  match t:
    case Tl{hd, tl}: tl
    case _: Nil{}

def onx_zip.go(a: List<&2, H.I64>, +b: Tl, +acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match a:
    case Nil{}: acc
    case x <> t:
      onx_zip.go(t, Tl.of(Tl.tl(b)),
        List.append(&2, H.I64, List.append(&2, H.I64, acc, [x]), [Tl.hd(b)]))

def onx_zip(a: List<&2, H.I64>, b: List<&2, H.I64>) -> List<&2, H.I64>:
  onx_zip.go(a, Tl.of(b), Nil{})

# `split at n`, which `onx_p2t` needs. `List.take(xs, 0n)` is `Nil{}` -- the
# recorded trap in bend2-constraints' `mixin/movement` rule 6 -- and for `n == 0`
# both halves must be empty, which is the `Hal{Nil{}, pads}` arm below.
def onx_half.n(+n: U32, +xs: List<&2, H.I64>) -> Hal:
  Hal{List.take(&2, H.I64, xs, U32.to_nat(n)),
    List.take(&2, H.I64, List.drop(&2, H.I64, xs, U32.to_nat(n)), U32.to_nat(n))}

def onx_half(+n: U32, +xs: List<&2, H.I64>) -> Hal:
  Bool.pick(Hal, U32.is_zero(n), Hal{Nil{}, xs}, onx_half.n(n, xs))

# ---------------------------------------------------------------------------
# `_onnx_pads_to_tiny_pads` -- :481-484.
#   n = len(pads) // 2
#   return tuple(x for i in range(n-1, -1, -1) for x in (pads[i], pads[i+n]))
#
# `for i in range(n-1, -1, -1) for x in (pads[i], pads[i+n])` walks BOTH indices
# downwards together, so it is `zip(reversed(first), reversed(second))` where
# `first`/`second` are the two halves -- TWO reversals, not one. The
# "reverse the whole list then zip" reading is a DIFFERENT function, and the
# fixture below is what separates them.
#
# MEASURED, and the fixture that shows why this needs a row of its own:
# `p2t((1,2,3,4)) == (2,4,1,3)` and `p2t((1,1,1,1,1,1)) == (1,1,1,1,1,1)`. The
# second is a CONSTANT input, where the rearrangement is INVISIBLE, so a fixture
# built from a constant pads tuple would pass with the halves in the wrong order.
# `p2t((1,)) == ()` is the `n == 0` arm and it is a real answer.
# ---------------------------------------------------------------------------
# BOTH HALVES ARE REVERSED, and getting that wrong was a real bug this gate
# caught: reversing only the first half gives `(0,0,0,0,0,5)` where CPython gives
# `(0,5,0,0,0,0)` for the input `(0,0,0,0,0,5)`. The reading is
# `zip(reversed(first), reversed(second))`, because `for i in range(n-1, -1, -1)`
# walks BOTH indices downwards at once -- `pads[i]` and `pads[i+n]`.
def onx_p2t.of(+hs: Hal) -> List<&2, H.I64>:
  onx_zip(List.reverse(&2, H.I64, Hal.a(hs)), List.reverse(&2, H.I64, Hal.b(hs)))

def onx_p2t(+pads: List<&2, H.I64>) -> List<&2, H.I64>:
  onx_p2t.of(onx_half(U32.div(U32.from_nat(List.length(&2, H.I64, pads)), 2), pads))

# ---------------------------------------------------------------------------
# `_auto_pad` -- :491-493.
#   first = [p//2 for p in pads] if auto_pad == "SAME_UPPER" else [p - p//2 for p in pads]
#   return first + [p - f for p, f in zip(pads, first)]
#
# The two arms differ ONLY in `first`, and the reversal is one subtraction, so
# the arm is a `Bool` parameter (`up: Bool`) rather than the whole `Ap`: the `Ap`
# is read once, at the call site in `onx_pool_pads`, which is where Python reads
# it too. `Ap.nm` exists for the gate row that prints the four spellings.
#
# MEASURED: `((3,3), SAME_UPPER) -> [1,1,2,2]` and `((3,3), SAME_LOWER) ->
# [2,2,1,1]`. SAME_LOWER is the `[p - p//2]` arm, so `first` is the LARGER half.
# ---------------------------------------------------------------------------
def onx_auto_pad.first.go(+pads: List<&2, H.I64>, +up: Bool, acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match pads:
    case Nil{}: acc
    case p <> t:
      onx_auto_pad.first.go(t, up,
        List.append(&2, H.I64, acc, [Bool.pick(H.I64, up, onx_halve(p), onx_isub(p, onx_halve(p)))]))

def onx_auto_pad.second.go(+pads: List<&2, H.I64>, +first: List<&2, H.I64>, acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match pads:
    case Nil{}: acc
    case p <> t:
      match first:
        case Nil{}: acc
        case f <> ft: onx_auto_pad.second.go(t, ft, List.append(&2, H.I64, acc, [onx_isub(p, f)]))

def onx_auto_pad.cat(+pads: List<&2, H.I64>, +up: Bool, +first: List<&2, H.I64>) -> List<&2, H.I64>:
  List.append(&2, H.I64, first, onx_auto_pad.second.go(pads, first, Nil{}))

def onx_auto_pad(+pads: List<&2, H.I64>, +up: Bool) -> List<&2, H.I64>:
  onx_auto_pad.cat(pads, up, onx_auto_pad.first.go(pads, up, Nil{}))

# ---------------------------------------------------------------------------
# `_resolve_pool_pads` -- :495-500.
#   if auto_pad == "VALID": return [0]*(len(k_)*2)
#   i_ = x.shape[-len(k_):]
#   if auto_pad == "NOTSET": return _onnx_pads_to_tiny_pads(p_ if len(p_)==len(k_)*2 else p_*2)
#   o_ = [((i - 1) // s + 1) for i,s in zip(i_, s_)]
#   return _onnx_pads_to_tiny_pads(_auto_pad([(o-1)*s+k-i for o,i,k,s in zip(o_, i_, k_, s_)], auto_pad))
#
# THREE FACTS THE PORT HAS TO KEEP AND NONE IS OBVIOUS FROM THE SIGNATURE:
#   1. `i_` is `x.shape[-len(k_):]` -- the SPATIAL tail, not the whole shape. The
#      port takes it already sliced, which is the one place this def's signature
#      differs from Python's and the comment says so.
#   2. `s_`, `d_` and `p_` arrive through `make_tuple(x, len(k_)*2)` (:497), so
#      they are `len(k_)*2`-long for a SCALAR argument and AS PASSED for a tuple.
#      `d_` is bound and NEVER USED (:497-498) -- a genuine dead binding in
#      tinygrad, and the port does not carry it.
#   3. `p_ * 2` is Python tuple REPETITION, i.e. concatenation, not a numeric
#      doubling. It is the `NOTSET` arm's way of reading a HALF-length pads list.
# ---------------------------------------------------------------------------
def onx_pool_valid(+k_: List<&2, U32>) -> List<&2, H.I64>:
  List.replicate(H.I64, U32.to_nat(U32.mul(U32.from_nat(List.length(&2, U32, k_)), 2)), H.i64_of_i32(0))

# `len(p_) == len(k_)*2` -- :498. `make_tuple` has already made a SCALAR pads
# argument long enough, so this is the test that distinguishes a HALF-length pads
# LIST from a full one.
def onx_p2t_full(+p_: List<&2, U32>, +k_: List<&2, U32>) -> Bool:
  U32.is_eq(U32.from_nat(List.length(&2, U32, p_)), U32.mul(U32.from_nat(List.length(&2, U32, k_)), 2))

def onx_rep2(+p_: List<&2, U32>) -> List<&2, U32>: List.append(&2, U32, p_, p_)

def onx_pool_notset(+p_: List<&2, U32>, +k_: List<&2, U32>) -> List<&2, H.I64>:
  onx_p2t(onx_i64s(Bool.pick(List<&2, U32>, onx_p2t_full(p_, k_), p_, onx_rep2(p_))))

# `o_ = [((i-1)//s+1)]` then `[(o-1)*s+k-i]` -- :499-500, as ONE walk. `i-1`
# is a `U32` subtraction of a spatial size, which is >= 1 in any real model, and
# `(i-1)//s` is non-negative so `U32.div`'s truncation IS Python's floor. The
# subtraction `... - i` is the only signed step and it is where `H.I64` earns its
# keep.
def onx_pool_total.go(+is_: List<&2, U32>, +k_: List<&2, U32>, +s_: List<&2, U32>, acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match is_:
    case Nil{}: acc
    case i <> it:
      match k_:
        case Nil{}: acc
        case k <> kt:
          match s_:
            case Nil{}: acc
            case s <> st:
              onx_pool_total.go(it, kt, st, List.append(&2, H.I64, acc,
                [onx_isub(H.i64_of_i32(U32.add(U32.mul(U32.div(U32.sub(i, 1), s), s), k)), H.i64_of_i32(i))]))

def onx_pool_total(+is_: List<&2, U32>, +k_: List<&2, U32>, +s_: List<&2, U32>) -> List<&2, H.I64>:
  onx_pool_total.go(is_, k_, s_, Nil{})

def onx_pool_same(+is_: List<&2, U32>, +k_: List<&2, U32>, +s_: List<&2, U32>, a: Ap) -> List<&2, H.I64>:
  onx_p2t(onx_auto_pad(onx_pool_total(is_, k_, s_), Ap.isupper(a)))

# the three arms as three Bool PARAMETERS, which is the shape the whole file uses
# for every choice on a computed value.
def onx_pool_pads(valid: Bool, notset: Bool, +is_: List<&2, U32>, +p_: List<&2, U32>, +k_: List<&2, U32>, +s_: List<&2, U32>, a: Ap) -> List<&2, H.I64>:
  Bool.pick(List<&2, H.I64>, valid, onx_pool_valid(k_),
    Bool.pick(List<&2, H.I64>, notset, onx_pool_notset(p_, k_),
      onx_pool_same(is_, k_, s_, a)))

def onx_pool_pads_of(+is_: List<&2, U32>, +p_: List<&2, U32>, +k_: List<&2, U32>, +s_: List<&2, U32>, +a: Ap) -> List<&2, H.I64>:
  onx_pool_pads(Ap.isvalid(a), Ap.isnotset(a), is_, p_, k_, s_, a)

# ---------------------------------------------------------------------------
# `_axes` -- :479. `axes or ([] if noop_with_empty_axes else None)`, so it has
# THREE answers and the port needs a `Bool` beside the list, because a `Data`
# record cannot hold a `Maybe` (bend2-constraints rule 15) and `None` and `[]`
# mean DIFFERENT things to `data.max(axis=...)`.
# MEASURED: `axes(None,0) is None`, `axes(None,1) == []`, `axes([],0) is None`,
# `axes([1],0) == [1]`. So the falsy test is on the LIST, not on the argument.
# ---------------------------------------------------------------------------
type Axes is Data:
  Axes{none: Bool, xs: List<&2, U32>}

def Axes.n(a: Axes) -> Bool:
  match a:
    case Axes{none, xs}: none

def Axes.x(a: Axes) -> List<&2, U32>:
  match a:
    case Axes{none, xs}: xs

def onx_axes(+xs: List<&2, U32>, noop: Bool) -> Axes:
  Bool.pick(Axes, List.is_empty(&2, U32, xs), Axes{Bool.not(noop), Nil{}}, Axes{False{}, xs})

# ===========================================================================
# STAGE 2 GATE. Every row here is diffed against CPython's own
# `_onnx_pads_to_tiny_pads` / `_auto_pad` / `_resolve_pool_pads` / `_axes`,
# reached by `exec`-ing `get_onnx_ops`'s body with its final `return {...}`
# replaced -- so the oracle is tinygrad's CODE and not a second transcription.
# ===========================================================================

def onx_i64s_str.go(xs: List<&2, H.I64>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: onx_i64s_str.go(t, List.append(&2, String, acc, [H.i64_text(x)]))

# `H.i64_text` is `hi:lo`, which is a DIFFERENT spelling from Python's decimal and
# is what makes a negative pad legible: Python says `-5` and Bend says
# `4294967295:4294967291`. The oracle prints the same pair, so the diff is still
# exact and the row does not ask a reader to do mental arithmetic.
def onx_i64s_str(xs: List<&2, H.I64>) -> String: String.join(onx_i64s_str.go(xs, Nil{}), ",")

def onx_ap_tbl() -> String:
  onx_join([Ap.nm(ApNotset{}), Ap.nm(ApSameUpper{}), Ap.nm(ApSameLower{}), Ap.nm(ApValid{})])

# the seven versioned rows, as `name/domain/version/impl`
def onx_ver_tbl.go(vs: List<&2, Ver>, acc: List<&2, String>) -> List<&2, String>:
  match vs:
    case Nil{}: acc
    case +v <> t:
      onx_ver_tbl.go(t, List.append(&2, String, acc,
        [String.concat([Ver.n(v), "/", Dom.s(Ver.d(v)), "/", U32.show(Ver.v(v)), "/", Ver.i(v)])]))

def onx_ver_tbl() -> String: String.join(onx_ver_tbl.go(onnx_ops_ver(), Nil{}), "|")

# `_select_op` -- :415-423. Twenty-three cases covering all three arms and BOTH
# Python raises: unknown op, eligible-empty (Dropout before 6, Softmax in the MS
# domain, Contiguous in the wrong domain), the `max` pick (12 -> softmax_1,
# 13 -> softmax_13, 20 -> softmax_13) and the plain-function arm (Conv is the same
# body at every opset, and `Contiguous` ignores the opset entirely).
def onx_sel_str.of(m: Maybe<&1, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "ERR"

def onx_sel_str(nm: String, +dom: Dom, +ver: U32) -> String: onx_sel_str.of(onx_sel(nm, dom, ver))

def onx_ops_rows() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- onx_row("onnx_ops_n", U32.is_eq(onnx_ops_n(), 171))
    _ : Unit <- onx_row("onnx_ops_ver_n", U32.is_eq(onnx_ops_ver_n(), 7))
    _ : Unit <- IO.print(String.concat(["onnx_ops_tbl=", onx_join(onnx_ops())]))
    _ : Unit <- IO.print(String.concat(["onnx_ver_tbl=", onx_ver_tbl()]))
    _ : Unit <- IO.print(String.concat(["onnx_ap_tbl=", onx_ap_tbl()]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_conv=", onx_sel_str("Conv", DomOnnx{}, 1)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_conv20=", onx_sel_str("Conv", DomOnnx{}, 20)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_neg=", onx_sel_str("Neg", DomOnnx{}, 1)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_isnan=", onx_sel_str("IsNaN", DomOnnx{}, 1)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_adam=", onx_sel_str("Adam", DomOnnx{}, 1)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_momentum=", onx_sel_str("Momentum", DomOnnx{}, 1)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_sm1=", onx_sel_str("Softmax", DomOnnx{}, 1)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_sm0=", onx_sel_str("Softmax", DomOnnx{}, 0)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_sm12=", onx_sel_str("Softmax", DomOnnx{}, 12)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_sm13=", onx_sel_str("Softmax", DomOnnx{}, 13)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_sm20=", onx_sel_str("Softmax", DomOnnx{}, 20)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_ms_sm=", onx_sel_str("Softmax", DomMsContrib{}, 13)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_dr5=", onx_sel_str("Dropout", DomOnnx{}, 5)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_dr6=", onx_sel_str("Dropout", DomOnnx{}, 6)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_dr99=", onx_sel_str("Dropout", DomOnnx{}, 99)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_at_onnx=", onx_sel_str("Attention", DomOnnx{}, 1)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_at_ms=", onx_sel_str("Attention", DomMsContrib{}, 1)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_at_onnx2=", onx_sel_str("Attention", DomOnnx{}, 2)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_ct_tiny=", onx_sel_str("Contiguous", DomTinygrad{}, 1)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_ct_tiny5=", onx_sel_str("Contiguous", DomTinygrad{}, 5)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_ct_onnx=", onx_sel_str("Contiguous", DomOnnx{}, 1)]))
    _ : Unit <- IO.print(String.concat(["onnx_sel_nope=", onx_sel_str("NoSuchOp", DomOnnx{}, 1)]))
    onx_row("onnx_ops_rows", True{})

def onx_pool_pads_str(is_: List<&2, U32>, p_: List<&2, U32>, k_: List<&2, U32>, s_: List<&2, U32>, a: Ap) -> String:
  onx_i64s_str(onx_pool_pads_of(is_, p_, k_, s_, a))

# `p2t` -- :481-484. Nine fixtures: the 4-pad swap, the 6-pad version, the
# CONSTANT 6-pad (where the swap is invisible and a wrong order would pass), the
# `n == 0` arm on a ONE-element list and on the empty list, a NEGATIVE pad so the
# `H.I64` widening is exercised, the all-zero case, an 8-pad, and an ODD length.
def onx_p2t_rows() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["onnx_p2t_4=", onx_i64s_str(onx_p2t(onx_i64s([1, 2, 3, 4])))]))
    _ : Unit <- IO.print(String.concat(["onnx_p2t_6=", onx_i64s_str(onx_p2t(onx_i64s([1, 2, 3, 4, 5, 6])))]))
    _ : Unit <- IO.print(String.concat(["onnx_p2t_6c=", onx_i64s_str(onx_p2t(onx_i64s([1, 1, 1, 1, 1, 1])))]))
    _ : Unit <- IO.print(String.concat(["onnx_p2t_1=", onx_i64s_str(onx_p2t(onx_i64s([1])))]))
    _ : Unit <- IO.print(String.concat(["onnx_p2t_0=", onx_i64s_str(onx_p2t(Nil{}))]))
    _ : Unit <- IO.print(String.concat(["onnx_p2t_neg=", onx_i64s_str(onx_p2t(onx_i64s([0, 0, 0, 0, 0, 5])))]))
    _ : Unit <- IO.print(String.concat(["onnx_p2t_zero=", onx_i64s_str(onx_p2t(onx_i64s([0, 0, 0, 0])))]))
    _ : Unit <- IO.print(String.concat(["onnx_p2t_8=", onx_i64s_str(onx_p2t(onx_i64s([9, 8, 7, 6, 5, 4, 3, 2])))]))
    _ : Unit <- IO.print(String.concat(["onnx_p2t_odd=", onx_i64s_str(onx_p2t(onx_i64s([1, 2, 3])))]))
    onx_row("onnx_p2t_rows", True{})

# `_auto_pad` -- :491-493. Both arms on the same fixture, the ODD total `(5,)`,
# the three-element case, and NEGATIVES -- because `p // 2` on a negative is where
# a truncating division and a flooring division disagree, and this file's
# `onx_halve` exists for exactly that. MEASURED in CPython:
# `_auto_pad((-5,), SAME_UPPER) == [-3, -2]`, and `-5 // 2` is `-3`, not `-2`.

def onx_ap_rows() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["onnx_ap_ns=", onx_i64s_str(onx_auto_pad(onx_i64s([0, 0]), False{}))]))
    _ : Unit <- IO.print(String.concat(["onnx_ap_su33=", onx_i64s_str(onx_auto_pad(onx_i64s([3, 3]), True{}))]))
    _ : Unit <- IO.print(String.concat(["onnx_ap_sl33=", onx_i64s_str(onx_auto_pad(onx_i64s([3, 3]), False{}))]))
    _ : Unit <- IO.print(String.concat(["onnx_ap_su24=", onx_i64s_str(onx_auto_pad(onx_i64s([2, 4]), True{}))]))
    _ : Unit <- IO.print(String.concat(["onnx_ap_su5=", onx_i64s_str(onx_auto_pad(onx_i64s([5]), True{}))]))
    _ : Unit <- IO.print(String.concat(["onnx_ap_sl5=", onx_i64s_str(onx_auto_pad(onx_i64s([5]), False{}))]))
    _ : Unit <- IO.print(String.concat(["onnx_ap_sl123=", onx_i64s_str(onx_auto_pad(onx_i64s([1, 2, 3]), False{}))]))
    _ : Unit <- IO.print(String.concat(["onnx_ap_su_neg1=", onx_i64s_str(onx_auto_pad(onx_i64s([4294967295]), True{}))]))
    _ : Unit <- IO.print(String.concat(["onnx_ap_sl_neg5=", onx_i64s_str(onx_auto_pad(onx_i64s([4294967291]), False{}))]))
    _ : Unit <- IO.print(String.concat(["onnx_ap_su_neg2=", onx_i64s_str(onx_auto_pad(onx_i64s([4294967294, 1]), True{}))]))
    _ : Unit <- IO.print(String.concat(["onnx_ap_empty=", onx_i64s_str(onx_auto_pad(Nil{}, True{}))]))
    _ : Unit <- IO.print(String.concat(["onnx_ap_odd2=", onx_i64s_str(onx_auto_pad(onx_i64s([0, 1]), True{}))]))
    onx_row("onnx_ap_rows", True{})

# `_resolve_pool_pads` -- :495-500. Seventeen fixtures, one per arm and per edge:
# the `make_tuple` scalar expansion (`p_` of length 1), a FULL pads list, a HALF
# pads list (the `p_*2` repetition), VALID, SAME_UPPER/LOWER at stride 1 and 2,
# a kernel of 5, a stride of 3 (odd output size), the one-dimensional case, the
# three-dimensional case, a 1x1 kernel, and the STRIDE-EXCEEDS-INPUT case whose
# pad is NEGATIVE.

def onx_pool_rows() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["onnx_pool_ns0=", onx_pool_pads_str([32, 32], [0, 0, 0, 0], [3, 3], [1, 1], ApNotset{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_ns1=", onx_pool_pads_str([32, 32], [1, 2, 3, 4], [3, 3], [1, 1], ApNotset{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_ns2=", onx_pool_pads_str([32, 32], [1, 2], [3, 3], [1, 1], ApNotset{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_ns3=", onx_pool_pads_str([32, 32], [0], [3, 3], [1, 1, 1, 1], ApNotset{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_valid=", onx_pool_pads_str([32, 32], [0, 0, 0, 0], [3, 3], [1, 1], ApValid{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_su2=", onx_pool_pads_str([32, 32], [0, 0, 0, 0], [3, 3], [2, 2], ApSameUpper{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_sl2=", onx_pool_pads_str([32, 32], [0, 0, 0, 0], [3, 3], [2, 2], ApSameLower{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_su5=", onx_pool_pads_str([32, 32], [0, 0, 0, 0], [5, 5], [1, 1], ApSameUpper{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_su_dil=", onx_pool_pads_str([32, 32], [0, 0, 0, 0], [3, 3], [2, 2], ApSameUpper{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_su1d=", onx_pool_pads_str([10], [0, 0], [3], [1], ApSameUpper{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_sl3d=", onx_pool_pads_str([7, 7, 7], [0, 0, 0, 0, 0, 0], [3, 3, 3], [1, 1, 1], ApSameLower{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_su_s3=", onx_pool_pads_str([8, 8], [0, 0, 0, 0], [3, 3], [3, 3], ApSameUpper{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_su_neg=", onx_pool_pads_str([8, 8], [0, 0, 0, 0], [3, 3], [8, 8], ApSameUpper{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_su_k1=", onx_pool_pads_str([32, 32], [0, 0, 0, 0], [1, 1], [1, 1], ApSameUpper{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_su_odd=", onx_pool_pads_str([10, 10], [0, 0, 0, 0], [4, 4], [3, 3], ApSameUpper{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_sl_neg=", onx_pool_pads_str([2, 2], [0, 0, 0, 0], [3, 3], [4, 4], ApSameLower{})]))
    _ : Unit <- IO.print(String.concat(["onnx_pool_valid1d=", onx_pool_pads_str([10], [0, 0], [3], [1], ApValid{})]))
    onx_row("onnx_pool_rows", True{})

def onx_axes_str(a: Axes) -> String: Bool.show(Axes.n(a))

# `_axes` -- :479, all four measured cases plus the list echo.
def onx_axes_rows() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print(String.concat(["onnx_axes_a=", onx_axes_str(onx_axes(Nil{}, False{})), "/", onx_u32s(Axes.x(onx_axes(Nil{}, False{})))]))
    _ : Unit <- IO.print(String.concat(["onnx_axes_b=", onx_axes_str(onx_axes(Nil{}, True{})), "/", onx_u32s(Axes.x(onx_axes(Nil{}, True{})))]))
    _ : Unit <- IO.print(String.concat(["onnx_axes_c=", onx_axes_str(onx_axes([1], False{})), "/", onx_u32s(Axes.x(onx_axes([1], False{})))]))
    _ : Unit <- IO.print(String.concat(["onnx_axes_d=", onx_axes_str(onx_axes([0, 2], True{})), "/", onx_u32s(Axes.x(onx_axes([0, 2], True{})))]))
    onx_row("onnx_axes_rows", True{})

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- onx_row("onnx_wt", onx_wt_rt())
    _ : Unit <- onx_row("onnx_wt_n", U32.is_eq(onx_wt_n(), 6))
    _ : Unit <- IO.print(String.concat(["onnx_wt_tbl=", onx_wt_tbl()]))
    _ : Unit <- onx_row("onnx_at", onx_at_rt())
    _ : Unit <- onx_row("onnx_at2", onx_at_rt2())
    _ : Unit <- onx_row("onnx_at_n", U32.is_eq(onx_at_n(), 8))
    _ : Unit <- IO.print(String.concat(["onnx_at_tbl=", onx_at_tbl()]))
    _ : Unit <- onx_row("onnx_odt_rt", onx_odt_rt())
    _ : Unit <- onx_row("onnx_odt_rt2", onx_odt_rt2())
    _ : Unit <- onx_row("onnx_odt_n", U32.is_eq(onx_odt_n(), 13))
    _ : Unit <- onx_row("onnx_odt_dt_rt", onx_odt_dt_rt())
    _ : Unit <- onx_row("onnx_odt_all", onx_odt_all_members())
    _ : Unit <- onx_row("onnx_odt_holes_rt", onx_odt_holes_rt())
    _ : Unit <- onx_row("onnx_odt_inv", onx_odt_inv())
    _ : Unit <- IO.print(String.concat(["onnx_odt_inv_tbl=", onx_odt_inv_tbl()]))
    _ : Unit <- onx_row("onnx_odt_inv_neg", onx_odt_inv_neg())
    _ : Unit <- IO.print(String.concat(["onnx_odt_tbl=", onx_odt_tbl()]))
    _ : Unit <- IO.print(String.concat(["onnx_odt_ktbl=", onx_odt_ktbl()]))
    _ : Unit <- IO.print(String.concat(["onnx_odt_dtbl=", onx_odt_dtbl()]))
    _ : Unit <- IO.print(String.concat(["onnx_odt_holes=", onx_odt_holes()]))
    _ : Unit <- IO.print(String.concat(["onnx_odt_hole_dts=", onx_odt_hole_dts()]))
    _ : Unit <- IO.print(String.concat(["onnx_aval_tags=", onx_aval_tags()]))
    _ : Unit <- IO.print(String.concat(["onnx_dom_tbl=", onx_dom_tbl()]))
    _ : Unit <- onx_row("onnx_dom_n", U32.is_eq(onx_dom_n(), 9))
    _ : Unit <- onx_row("onnx_dom_rt", onx_dom_rt())
    _ : Unit <- onx_row("onnx_dom_empty", onx_dom_empty())
    _ : Unit <- onx_row("onnx_dom_onnx", onx_dom_onnx())
    _ : Unit <- onx_row("onnx_dom_tiny", onx_dom_tiny())
    _ : Unit <- onx_row("onnx_dom_ms", onx_dom_ms())
    _ : Unit <- onx_row("onnx_dom_unknown", onx_dom_unknown())
    _ : Unit <- onx_row("onnx_dom_unknown2", onx_dom_unknown2())
    _ : Unit <- onx_row("onnx_dom_unknown3", onx_dom_unknown3())
    _ : Unit <- IO.print(String.concat(["onnx_dom_training=", onx_dom_training()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_tbl=", onx_pc_tbl()]))
    _ : Unit <- onx_row("onnx_pc_n", U32.is_eq(onx_pc_n(), 38))
    _ : Unit <- IO.print(String.concat(["onnx_pc_reduce=", onx_pc_reduce()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_adam=", onx_pc_adam()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_slice=", onx_pc_slice()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_range=", onx_pc_range()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_pad=", onx_pc_pad()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_dropout=", onx_pc_dropout()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_hann=", onx_pc_hann()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_absent=", onx_pc_absent()]))
    _ : Unit <- IO.print(String.concat(["onnx_pc_absent2=", onx_pc_absent2()]))
    _ : Unit <- onx_row("onnx_pc_has_hit", onx_pc_has_hit())
    _ : Unit <- onx_row("onnx_pc_has_miss", onx_pc_has_miss())
    _ : Unit <- onx_row("onnx_pc_has_abs", onx_pc_has_abs())
    _ : Unit <- onx_row("onnx_pc_has_neg", onx_pc_has_neg())
    _ : Unit <- onx_ops_rows()
    _ : Unit <- onx_p2t_rows()
    _ : Unit <- onx_ap_rows()
    _ : Unit <- onx_pool_rows()
    _ : Unit <- onx_axes_rows()
    onx_row("onnx_stage2", True{})

# ===========================================================================
# THE WALLS, ONE `TODO(p3)` PER PYTHON LINE GROUP. No prose pretending to be
# code: `nn/__init__.bend` says the same thing about its own `__call__`s and the
# reason is the same -- a def with no body is a paragraph pretending to be a def.
# ===========================================================================
# TODO(p3) onnx.py:73   PBBufferedReader -- `io.BufferedReader(TensorIO(tensor))`,
#   `decode_varint`'s 64-bit accumulate, `read_delimited`, `read_string`,
#   `read_bytes`, `read_float`, `read_packed_floats`, `read_int64`,
#   `read_packed_int64s`, `skip_field`. WALL: byte reads out of a tensor.
# TODO(p3) onnx.py:121  OnnxPBParser -- all seventeen `_parse_*` defs and `parse`.
#   WALL: the reader above, and `pathlib`, `enum`-free `struct`, and
#   `Tensor(pathlib.Path)` for the external-data path (:226-232).
# TODO(p3) onnx.py:361  _to_python_const -- `t.data().tobytes()` / `t.tolist()`.
#   WALL: a host read of a realized buffer.
# TODO(p3) onnx.py:367  OnnxRunner.__init__ / _init_from_graph / _from_subgraph /
#   _parse_input / to / _get_python_const / __call__ -- :374-470.
#   WALL: the parser, plus `Device.DEFAULT`, `Context(TRAINING=...)`, `ContextVar`,
#   `warnings.warn`, `RuntimeError`, and the debug/limit getenv pair (:365-366).
# TODO(p3) onnx.py:475  get_onnx_ops -- the 167 bodies. The NAME TABLE and
#   `_select_op` are PORTED (:1067, :1240); everything below is not, and every one
#   of these is a mixin method belonging to another file:
# TODO(p3) onnx.py:543  contiguous_1 / :547 If / :564 Identity / :565 Constant /
#   :575 Range / :578 ImageDecoder / :587 EyeLike / :591 OptionalHasElement /
#   :593 ConstantOfShape / :597 Size / :598 Shape
# TODO(p3) onnx.py:601  Not / Clip / IsInf
# TODO(p3) onnx.py:606  softmax_1 / softmax_13 / HardSigmoid / Gelu / BiasGelu /
#   FastGelu / PRelu / LeakyRelu / ThresholdedRelu / LogSoftmax / Hardmax /
#   Binarizer / Swish -- the Softmax ROUTING is PORTED, its two bodies are not.
# TODO(p3) onnx.py:622  Add / Sub / Div / Pow / Less / LessOrEqual / Greater /
#   GreaterOrEqual / Equal / And / Or / Xor / BitwiseAnd / BitwiseOr /
#   BitwiseXor / BitwiseNot / Mod
# TODO(p3) onnx.py:643  Cast / CastLike -- `OnnxDataType(to).to_dtype()` is
#   PORTED (`onx_odt_dt`), so only `x.cast` is missing.
# TODO(p3) onnx.py:647  Max / Min / Sum / Mean / ReduceMax / ReduceMin /
#   ReduceSum / ReduceMean / ReduceSumSquare / ReduceProd / ReduceL1 / ReduceL2 /
#   ReduceLogSum / ReduceLogSumExp / ArgMax / ArgMin. `_axes` (:479) is PORTED and
#   GATED, so only `x.max`/`x.min`/`x.sum`/`x.mean`/`x.argmax` are missing.
# TODO(p3) onnx.py:679  Reshape / Flatten / Expand / Shrink / Transpose / Squeeze /
#   Unsqueeze / Tile / Concat / Slice / Split / Pad / CenterCropPad
# TODO(p3) onnx.py:724  AveragePool / MaxPool / Conv / ConvTranspose / MaxUnpool /
#   GlobalAveragePool / GlobalMaxPool / Gemm / Einsum / CumSum / Trilu / Resize /
#   Upsample / TopK
# TODO(p3) onnx.py:896  BatchNormalization / GroupNormalization /
#   InstanceNormalization / LayerNormalization / SkipLayerNormalization /
#   EmbedLayerNormalization / MeanVarianceNormalization / LpNormalization / OneHot
# TODO(p3) onnx.py:963  DepthToSpace / SpaceToDepth -- `X.rearrange` is a REWRITE
#   of the whole index expression and has no mixin method of its own.
# TODO(p3) onnx.py:969  dropout_7 / dropout_6 -- legacy `numpy.random.RandomState`,
#   which is a NUMPY seeding requirement the port cannot state.
# TODO(p3) onnx.py:982  _window / HannWindow / HammingWindow / BlackmanWindow /
#   LRN / NegativeLogLikelihoodLoss / SoftmaxCrossEntropyLoss / AffineGrid /
#   attention_contrib / attention_onnx / RMSNormalization / RotaryEmbedding
# TODO(p3) onnx.py:1133 NonZero / ArrayFeatureExtractor / Gather / Scatter /
#   GatherND / ScatterND / TensorScatter / ScatterElements / GatherElements /
#   Compress
# TODO(p3) onnx.py:1211 QuantizeLinear / DynamicQuantizeLinear / DequantizeLinear /
#   QLinearConv / QLinearMatMul / QLinearAdd / QLinearMul /
#   QLinearGlobalAveragePool / ConvInteger / MatMulInteger
# TODO(p3) onnx.py:1265 Adagrad / Adam / Momentum -- the `@_onnx_training`
#   decorator (:532-540) SPLITS a variadic `*inputs` into `groups` slices and
#   `flatten(zip(*ret))`s them, which is a variadic-rest-and-transpose with no
#   Bend spelling; `Adam` additionally needs `opt.m`/`opt.v`/`opt.lr` assignment
#   and a `b1_t`/`b2_t` special case at `T == 0` (:1286-1290). The ROUTING
#   (`___wrapper` for all three) is PORTED and GATED.
# TODO(p3) onnx.py:1305 Gradient -- `intermediate_tensors[y].gradient(*inputs)`.

# ===========================================================================
# THE MUTATION TABLE, MEASURED by `.agents/slop/onnx-mutate.py`, which mutates
# the file in place, re-runs the INTERPRETED lane, reports the rows that MOVE and
# restores the file (it asserts the restore is byte identical). MEASURED
# 2026-10-02. The interpreted lane is the one measured because it is 10 s per run
# against ~90 s to compile, and the 123 gate rows are lane-identical.
#
# | mutation | the edit | rows MOVED | what it was testing |
# | --- | --- | --- | --- |
# | M1 | `OnnxDataType`'s `uint8` KEY becomes `"uchar"` (:37 `self.name.lower()`) | `onnx_odt_rt2` `onnx_odt_ktbl` | **THE MOST IMPORTANT ROW IN THIS TABLE.** `uchar` is ALSO a `DTYPES_DICT` key, so the lookup still answers the RIGHT dtype and `onnx_odt_dtbl` does not move. Only the two rows that print or invert the KEY see it. A gate carrying only the dtype table would be blind to a wrong lookup key, which is exactly the silent wrong-dtype kernel this file exists to prevent. |
# | M2 | the `int64` KEY becomes `"long"` | `onnx_odt_rt2` `onnx_odt_ktbl` | the same hazard on the entry whose `DType.name` is also `long`. M1 and M2 are the SAME defect at two cells, so they are not independent claims about two entries -- they are one claim that the key table is the lower-cased NAME and not the attribute name. |
# | M3 | the `BOOL` arm is deleted from `onx_odt_name` | `onnx_odt_rt` `onnx_odt_all` `onnx_odt_tbl` | a MISSING MEMBER. **`onnx_odt_n` does NOT move**, because it counts `onx_odt_codes()` and not the table's arms: the count and the table are two independent transcriptions of one Python list. This is a measured limit of the count row and it is written into the header rather than left for a reader to find. |
# | M4 | the `bfloat16` reverse-table entry gets an `X` | `onnx_odt_rt2` `onnx_odt_dt_rt` `onnx_odt_inv` `onnx_odt_inv_tbl` `onnx_odt_ktbl` `onnx_odt_dtbl` | SIX rows, the widest blast radius in the table: the reverse table is the one every forward row inverts through, so a single cell there is shared by the whole dtype family. `onnx_odt_inv` moving is the point -- the reverse is a real bijection and breaking one end breaks both. |
# | M5 | `to_field_name`'s `7` becomes `"int"` | `onnx_at2` `onnx_at_tbl` | the ATTRIBUTE SPELLING (:27). `"int"` is not a key `_parse_AttributeProto` writes (:253-267), so a wrong singular is a silent read of an absent key. |
# | M6 | `to_field_name`'s `5` becomes `"graph"` | `onnx_at2` `onnx_at_tbl` | the GRAPH arm, the one whose value is an `OnnxRunner` and therefore has no payload in `AVal`. |
# | M7 | `AI_ONNX_PREVIEW_TRAINING`'s value loses `training` (:46) | `onnx_dom_tbl` `onnx_dom_rt` | the longest of the nine domain strings, and the round trip is the row that notices a value that no longer round-trips through `from_onnx`. |
# | M8 | the TRAINING membership (:379) drops its SECOND member | `onnx_dom_training` | ONE row. `_init_from_graph`'s `any(...)` is the only consumer, and the nine-cell row is the only row that can see half a predicate -- which is the `device.bend` gate lesson (`is_param` dropped from three rules moved nothing until negative fixtures were added). |
# | M9 | `ReduceL2`'s index becomes `0` instead of `1` (:357) | `onnx_pc_tbl` | ONE row. The comprehension-built rungs are thirteen of the thirty-eight and the table string is the only row that prints an INDEX; the count cannot see a changed index at all. |
# | M10 | `Resize`'s index list loses its `3` (:355) | `onnx_pc_tbl` | the same, on a LITERAL rung rather than a comprehension-built one. M9 and M10 are one claim about index lists and they move the same single row. |
# | M11 | the op name `"HardSwish"` is DELETED | `onnx_ops_n` `onnx_ops_tbl` | the count row and the table string together: a dropped name is visible in BOTH, which is the pair the header claims. |
# | M12 | `"Where"` is MISSPELLED as `"Wherf"` | `onnx_ops_tbl` | ONE row, and this is the interesting half of M11/M12: a same-length typo leaves the COUNT green, so the count row alone is not the table claim. |
# | M13 | `IsNaN`'s Tensor method becomes `is_nan` (:1310) | `onnx_sel_isnan` | the ONE `getattr(Tensor, op.lower())` entry whose Tensor method is not simply the lower-cased name (`Tensor.isnan`). One row, localised, and it is the whole reason the 36-entry identity table is written out rather than derived. |
# | M14 | the eligibility test's `<=` becomes `<` (:421) | `onnx_sel_sm1` `onnx_sel_sm13` `onnx_sel_dr6` `onnx_sel_at_onnx` `onnx_sel_at_ms` `onnx_sel_ct_tiny` | SIX rows, and every one of them is a VERSION-1 registration: strict `<` refuses the opset each version was introduced at. An off-by-one in a `<=` is invisible at any opset above the introduction version, which is why the fixtures include opsets 1, 0 and 5 and not only the current ones. |
# | M15 | the versioned router's `bi` pick becomes FIRST-WINS instead of `U32.is_gt`-max (:423) | `onnx_sel_sm1` `onnx_sel_sm12` `onnx_sel_sm13` `onnx_sel_sm20` `onnx_sel_dr6` `onnx_sel_dr99` `onnx_sel_at_onnx` `onnx_sel_at_ms` `onnx_sel_at_onnx2` `onnx_sel_ct_tiny` `onnx_sel_ct_tiny5` | ELEVEN rows, all of them the versioned ops. **This mutation found a real bug in the port**: the first version of `onx_elig` AND-ed `not hit`, which is first-wins, and `Softmax` at opset 13 answered `softmax_1`. |
# | M15b | the sibling edit on the `bv` ACCUMULATOR (`U32.max(bv, …)` -> `bv`) | **NOTHING** | **THE BLIND SPOT, and the reason this table records a null result.** `bv` feeds only the max COMPARISON and the answer is the `bi` string, so `bv` is not load-bearing on its own. The mutation that moves rows is M15, on `bi`. Two claims about one rule, and only one of them is localised. |
# | M16 | `p2t`'s SECOND reversal is dropped (:483) | `onnx_p2t_4` `onnx_p2t_6` `onnx_p2t_neg` `onnx_p2t_8` `onnx_pool_ns1` `onnx_pool_ns2` | SIX rows. Reversing only the first half is a real bug this gate CAUGHT during the port (`onnx_p2t_neg` answered `(0,0,0,0,0,5)` where CPython says `(0,5,0,0,0,0)`). `onnx_p2t_6c` does NOT move, and that is the fixture that was built for it: a CONSTANT pads tuple is invariant under the swap, so a fixture of constants could never have seen this. |
# | M17 | `p2t`'s second half stops being `take(n, drop(n))` | `onnx_p2t_odd` | ONE row, and it is the only ODD-length fixture. `p2t` indexes `pads[i+n]` for `i in range(n)`, which is exactly `n` elements, so a 5-pad tuple drops its last pad. A gate of even-length fixtures would not have a row here at all. |
# | M18 | the 64-bit shift's LOW-word fill comes from the low word's own bit 0 | `onnx_ap_su33` `onnx_ap_sl33` `onnx_ap_su5` `onnx_ap_sl5` `onnx_ap_sl123` `onnx_ap_su_neg2` `onnx_ap_odd2` `onnx_pool_su2` `onnx_pool_sl2` `onnx_pool_su_dil` `onnx_pool_su_s3` `onnx_pool_su_odd` `onnx_pool_sl_neg` | THIRTEEN rows, the widest in the table, and every one of them is a row with a NON-ZERO pad. The correct identity is `lo' = (lo >>> 1) | ((hi & 1) << 31)` -- a bit SHUFFLE, not a sign fill -- and the high word's `hi' = (hi >>> 1) | sign` is the only sign extension. This is the SECOND of the three bugs the gate caught in `onx_halve`, and `-5` answers correctly under all three (its `lo & 1` is 1), which is why only an EVEN negative exposed it. |
# | M19 | a COMMENT-ONLY edit | **NOTHING** | THE CONTROL. A mutation table with no row that CANNOT move is a table of coincidences. |
# | M20 | the WireType table swaps `FIXED32` and `FIXED64` (:18) | `onnx_wt` `onnx_wt_tbl` | the round trip over the six WireType codes. `onnx_wt_n` does NOT move because a swap preserves the count -- the same COUNT-vs-CONTENT lesson as M3, on a different table. |
#
# WHAT THE TABLE DOES NOT COVER, stated rather than left to be discovered:
#   * no mutation of `onx_dom_empty`'s EMPTY-string arm, because `onnx_dom_onnx`
#     is the arm that also lands on ONNX and only those TWO rows can see the
#     difference; that is a MISSING ROW and the fix is a third fixture whose
#     expected value differs from `onnx_dom_onnx`'s.
#   * no mutation of `onx_pc_has`, because `onx_mem` is shared with nothing and
#     `onnx_pc_has_hit`/`has_miss`/`has_abs`/`has_neg` between them pin both
#     directions; a mutation of the predicate BODY would move all four and that
#     is recorded here rather than claimed as a localisation.
#   * nothing here says anything about a graph, a tensor or a device. Every row in
#     this gate is a table, a name or an integer, because that is all this file
#     ports.
