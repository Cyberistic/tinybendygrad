# tinybendygrad/renderer/cstyle.bend -- tinygrad/renderer/cstyle.py.
#
# THE STRING-BUILDING LAYER. `__init__.bend` holds the conventions and the base;
# this file is where a UOp becomes C, OpenCL, Metal, CUDA or HIP TEXT, and it is
# the first renderer file whose output a compiler ever sees. That raises the bar
# on one thing above everything else in the port: `String.concat` drops a
# literal SILENTLY. A dropped ", " typechecks, runs, and emits a kernel that is
# wrong rather than broken. So the gate at the foot of this file is a STRING DIFF
# against live CPython and never a boolean about a string.
#
# ===========================================================================
# THE DEVICE IS A `U32` TAG, NOT A RECORD. `cstyle.py`'s six renderer classes
# differ ONLY in class attributes -- `kernel_typedef`, `type_map`, `barrier`,
# the address-space prefixes, `code_for_op`, `code_for_workitem`, the max tuples
# -- and every one of them is read through a `self` that Python resolves by
# class. There is no `self` here, so a reader takes a `dev: U32` and dispatches
# with a `match`. That is the whole inheritance mechanism, and it is a `match`
# rather than a record because the number of options is large and each is read
# exactly once per emitted line: a record of thirty fields would be read the
# same way but would have to be threaded through every signature, and the tag is
# one `U32`.
#
# WHY A TAG AND NOT A RECORD WITH NULLS. `float4` is `str|None` and
# `global_max` is `tuple|None`, and a `Data` cannot hold a `Maybe`. A `U32` tag
# has neither problem: the base CStyleLanguage is tag 0 and every device
# OVERRIDES rather than extends, so "the base has no `float4`" is a property of
# the tag, not a null to carry. `render.bend`'s device-NAME table reaches the
# same conclusion the same way.
#
# WHAT THE TAG DOES NOT REPLACE, and this is the honest part:
#   * `code_for_op` is `dict[Ops, Callable]`. A callable is not representable, so
#     it is the device TAG plus a `match` -- `code_for_op.of(dev, op, ..)`. The
#     tag is the only per-device information the ALU table needs, and it is
#     MEASURED: the six devices differ on exactly SIX of the twenty-one ops
#     (SQRT, TRUNC, SIN, LOG2, EXP2, RECIPROCAL) plus Clang's FDIV, and every
#     other op's rendering is the base's on all six.
#   * `code_for_workitem` is `dict[Literal["g","l"], Callable]`. Same answer: the
#     workitem id is a `String` argument and the device picks the spelling.
#   * `extra_matcher` is a `PatternMatcher` over UOps. Those are ARENA REWRITES,
#     not strings -- the `create_non_native_float_pats` / `pm_manual_bf16_cast`
#     family -- and they are NOT the same table as `string_rewrite` in the port
#     even though both are `PatternMatcher`s in Python. A string rule returns a
#     `String`; a matcher rule returns a UOp. Two concerns, two shapes.
#
# ===========================================================================
# THE FOUR WALLS UNDER THIS FILE. Three are the substrate's and one is device
# FFI; each is a `TODO(p3)` with its line.
#
#   (a) `Ops.SHRINK` HAS NO DTYPE IN THE FOLD. `uop/fold.bend:1695 symbol=sym_dim.val` defers it with
#       the comment "`marg` -> `zip` -> `ssimplify`", and `Ops.LOAD` is `thru0`
#       off a SHRINK so it inherits the gap. MEASURED on a hand-built arena:
#       `F.fold.dt` answers `None` for SHRINK, LOAD and every ALU above one, so
#       `Kahn.settled` is False for a real kernel. `render_type` needs a dtype on
#       EVERY line, so `_render` cannot be run end to end until that arm lands.
#       `fold.bend`'s to own. The gate below is built so that it is OBVIOUS this
#       is why: every row drives the string functions with EXPLICIT derived
#       values, which is exactly what Python's `_render_dtype(dtype, sz,
#       addrspace, ...)` takes too.
#   (b) `u.max_numel()` is `prod(to_max_shape(shape))` and `to_max_shape` is a
#       SYMBOLIC `vmax` (`TODO(p3) ops.py:1896 symbol=to_max_shape`). `max_numel` below is the
#       product of the CONCRETE dims; a shape carrying a symbolic `SU` is the
#       case it does not have, and `max_numel_sym` is the marker for it.
#   (c) `is_image_shape` is `helpers.bend`'s and takes a `ShapeRes`, while the
#       fold answers `List<&2, O.Sint>`. So the image test is taken as a `Bool`
#       the CALLER computes, which is Python's own signature (`shape=None` is a
#       parameter of `_render_dtype`, not a read of a uop) and is what keeps the
#       wall in one place.
#   (d) EVERY `__init__` IN cstyle.py IS DEVICE FFI: `ClangCompiler`,
#       `NVRTCCompiler`, `HIPCompiler`, `MetalCompiler`, `QCOMCompiler`, `comgr`,
#       `tc.get_cuda` / `tc.get_amd`. None of it is text generation and none of
#       it is this unit's file. What SURVIVES is the shape of the decision those
#       `__init__`s make: HIP picks its `string_rewrite` from `is_cdna(arch)` and
#       `is_cdna4(arch)` (cstyle.py:502-526), and those are two `Bool`s derived
#       from `self.target.arch`, so `is_cdna` and `is_cdna4` are ported as string
#       predicates and the rewrite selection they drive is named below.
# ===========================================================================

import Base
import ./__init__.bend as R
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H
import ./../uop/render.bend as U

# ===========================================================================
# THE DEVICE TAGS. Six renderers plus the abstract `CStyleLanguage`, whose own
# rows are what every subclass overrides and which the gate needs: cstyle.py's
# base class is a real, instantiable renderer (`CStyleLanguage(Target())` works,
# and `_render_dtype` on it is a live row set, not a fiction).
#
# THE ORDER IS THIS FILE'S OWN and no claim is made that it is cstyle.py's. The
# tag is a closed enum and what the differential requires is only that a renderer
# and its rows agree on it. `render.bend` makes the same argument for the device
# NAME table and lands in the same place.
# ===========================================================================

# ===========================================================================
# THE DEVICE TAGS. Six renderers plus the abstract `CStyleLanguage`, whose own
# rows are what every subclass overrides and which the gate needs: cstyle.py's
# base class is a real, instantiable renderer (`CStyleLanguage(Target())` works,
# and `_render_dtype` on it is a live row set, not a fiction).
#
# THE ORDER IS THIS FILE'S OWN and no claim is made that it is cstyle.py's. The
# tag is a closed enum and what the differential requires is only that a renderer
# and its rows agree on it. `render.bend` makes the same argument for the device
# NAME table and lands in the same place.
#
# AND THE NAME IS A ROW LIKE EVERY OTHER OPTION, not a debugging aid: `wgsl.bend`
# reads its device names out of the same closed set and the two files must not be
# able to disagree about which U32 is which, so `devname` is a gated row and not
# a comment.
# ===========================================================================

type Uses is Data:
  Uses{half: Bool, bf16: Bool, fp8: Bool, nonfinite: Bool, special: Bool, half_any: Bool}

type Emit_ is Data:
  Emit_{uses: Uses, vecs: List<&2, String>, ockl: List<&2, String>, ocml: List<&2, String>,
       caller: List<&2, String>, has_prefix: Bool}

type Kv is Data:
  Kv{k: String, v: String, t: Kv}
  KvEnd{}

type KU is Data:
  KU{op: O.Op, dtype: S.Dt, addr: S.Addr, numel: U32, shape: List<&2, U32>,
     arg: KUArg, srcs: List<&2, U32>}

type KUArg is Data:
  KANone{}
  KAConst{v: O.Const}
  KAParam{slot: U32, name: Maybe<&2, String>, volatile_: Bool, bytes: U32}
  KARange{axis: O.AxisType, ids: List<&2, U32>}
  KAIndex{off: U32, is_add: Bool}
  KASink{name: String}
  # `Ops.SPECIAL`'s arg upstream is ONE STRING -- `"lidx0"` -- and cstyle.py:239 binds
  # the NAME from it (`r[u] = u.arg`), :47 reads the axis off `arg[0]` and the index off
  # `arg[-1]`. So all three travel: the axis letter, the index, and the name itself.
  KASpecial{axis: String, n: U32, nm: String}

type St is Data:
  St{r: List<&2, String>, kernel: List<&2, String>, bufs: List<&2, BArg>,
     c: List<&2, U32>, depth: U32, name: String}

type DtN is Data:
  DtN{dt: S.Dt, n: U32}

type BArg is Data:
  BArg{name: String, dtype: S.Dt, addr: S.Addr, mutable: Bool, volatile_: Bool, image: Bool}


# THE READERS. A LOCALLY-DECLARED `Data` RECORD HAS NO PROJECTION SYNTAX AT ALL,
# so `BArg.addr(b)` is "a defined name" until `def BArg.addr` is written by hand.
# MEASURED on 2.0.34 with a three-field record: `BArg.image(b)` and `BArg.name(b)`
# are both refused, and so is a field whose NAME ENDS IN `_` -- which is the
# `volatile` escape of bend2-constraints rule 25 turning out to have no
# projection even after it, so the escape buys the reader and costs nothing else.
# An IMPORTED record's projections DO exist -- `O.Arena.op(ar, i)` and
# `O.ParamArg.slot(pa)` are the whole of `renderer/__init__.bend`'s vocabulary --
# so this is a rule about where the type was DECLARED and not about its kind.
# Each reader is one `match` naming EVERY field, which is convention 6 and is also
# why adding a field to one of these records is a one-line change per reader.
def dev_base() -> U32: 0
def dev_clang() -> U32: 1
def dev_opencl() -> U32: 2
def dev_metal() -> U32: 3
def dev_cuda() -> U32: 4
def dev_hip() -> U32: 5

def dev_name(+dev: U32) -> String:
  match dev:
    case 0: "BASE"
    case 1: "CLANG"
    case 2: "OPENCL"
    case 3: "METAL"
    case 4: "CUDA"
    case 5: "HIP"
    case _: "?"

# ===========================================================================
# THE TWO DERIVED-FACT RECORDS. `render_kernel` reads facts out of a UOp LIST
# (`uops`) and Python gets them by walking; there is no uop list here because
# there is no fold (wall (a)), so they arrive as records the CALLER fills. That
# is not a loosening of the port -- it is the same move `_render_dtype(dtype, sz,
# addrspace, mutable, override_ptr, shape)` already makes, one level up -- and it
# is what keeps the six `render_kernel` OVERRIDES inside the gate.
# ===========================================================================

# `bufs` is `list[tuple[str, tuple[UOp, bool]]]`: a name, a uop and a mutability.
# The uop contributes exactly six things to the emitted string, so those six are
# the fields. `is_alu` is not one of them: it is `u.addrspace == AddrSpace.ALU`,
# which `buftype` reads off `addr` rather than carrying a seventh flag.
def BArg.name(b: BArg) -> String:
  match b:
    case BArg{name, dtype, addr, mutable, volatile_, image}: name

def BArg.addr(b: BArg) -> S.Addr:
  match b:
    case BArg{name, dtype, addr, mutable, volatile_, image}: addr

def BArg.dtype(b: BArg) -> S.Dt:
  match b:
    case BArg{name, dtype, addr, mutable, volatile_, image}: dtype

def BArg.mutable(b: BArg) -> Bool:
  match b:
    case BArg{name, dtype, addr, mutable, volatile_, image}: mutable

def BArg.volatile_(b: BArg) -> Bool:
  match b:
    case BArg{name, dtype, addr, mutable, volatile_, image}: volatile_

def Uses.half(u: Uses) -> Bool:
  match u:
    case Uses{half, bf16, fp8, nonfinite, special, half_any}: half

def Uses.bf16(u: Uses) -> Bool:
  match u:
    case Uses{half, bf16, fp8, nonfinite, special, half_any}: bf16

def Uses.fp8(u: Uses) -> Bool:
  match u:
    case Uses{half, bf16, fp8, nonfinite, special, half_any}: fp8

def Uses.nonfinite(u: Uses) -> Bool:
  match u:
    case Uses{half, bf16, fp8, nonfinite, special, half_any}: nonfinite

def Uses.special(u: Uses) -> Bool:
  match u:
    case Uses{half, bf16, fp8, nonfinite, special, half_any}: special

def Uses.half_any(u: Uses) -> Bool:
  match u:
    case Uses{half, bf16, fp8, nonfinite, special, half_any}: half_any


# EVERYTHING THE PREFIX LAYER NEEDS THAT IS NOT A BUFFER OR THE BODY, in ONE
# record because `render_kernel` would otherwise take twelve arguments. Python's
# own signature is five (`function_name, kernel, bufs, uops, prefix`); the six
# here are this file's substitute for the uop LIST that Python walks, and they
# are grouped rather than spread for that reason and no other.
#
# `caller` and `has_prefix` are the `prefix` ARGUMENT, kept as a pair because
# `prefix=[]` and `prefix=None` are different kernels (cstyle.py:558) and a
# `List` cannot tell them apart. `vecs`, `ockl` and `ocml` are the uop-derived
# lines Python appends to `prefix`; see the `TODO(p3)` at the foot for which of
# them this port produces and which it names.
#
# `cdna4` IS NOT A FIELD, and that is worth saying because it is the one value
# HIP reads that the caller already has: `is_cdna4(self.target.arch)` is a
# property of the TARGET, not of the uop list, so it travels as the `cdna4`
# ARGUMENT of `render_kernel` and stops there. Putting it in the record as well
# would be two spellings of one fact and the gate would only see one of them.
def Emit_.uses(e: Emit_) -> Uses:
  match e:
    case Emit_{uses, vecs, ockl, ocml, caller, has_prefix}: uses

def Emit_.vecs(e: Emit_) -> List<&2, String>:
  match e:
    case Emit_{uses, vecs, ockl, ocml, caller, has_prefix}: vecs

def Emit_.ockl(e: Emit_) -> List<&2, String>:
  match e:
    case Emit_{uses, vecs, ockl, ocml, caller, has_prefix}: ockl

def Emit_.ocml(e: Emit_) -> List<&2, String>:
  match e:
    case Emit_{uses, vecs, ockl, ocml, caller, has_prefix}: ocml

def Emit_.caller(e: Emit_) -> List<&2, String>:
  match e:
    case Emit_{uses, vecs, ockl, ocml, caller, has_prefix}: caller

def Emit_.has_prefix(e: Emit_) -> Bool:
  match e:
    case Emit_{uses, vecs, ockl, ocml, caller, has_prefix}: has_prefix


# `Emit_{uses, vecs, ockl, ocml, caller, has_prefix}` -- the `uops=[]`,
# `prefix=None` case. `emit_of` is the constructor because the gate needs FIVE
# other `Emit_` values and a record literal per row would repeat the five
# `Nil{}`s four times each.
def emit_of(u: Uses, vecs: List<&2, String>, ockl: List<&2, String>, ocml: List<&2, String>, caller: List<&2, String>, has_prefix: Bool) -> Emit_:
  Emit_{u, vecs, ockl, ocml, caller, has_prefix}

# EVERY `uses` BOOL FALSE: no half, no bf16, no fp8, no non-finite CONST, no
# SPECIAL, no vector prefix, which is the configuration in which four of the five
# vendor prefixes are still non-empty.
def uses_off() -> Uses: Uses{False{}, False{}, False{}, False{}, False{}, False{}}

def emit_min() -> Emit_: emit_of(uses_off(), Nil{}, Nil{}, Nil{}, Nil{}, False{})

# ===========================================================================
# THE OPTION TABLES. One `match` per option, six arms plus the base. They sit
# here rather than at first use because `render_kernel` reads nine of them in one
# expression, and a reader reaching past three other defs for `buffer_suffix`
# would be harder to read than the table it replaced.
#
# EVERY STRING IS MEASURED against CPython on this `tinygrad/` tree, and the
# empty ones are as load-bearing as the long ones. `CStyleLanguage.abi` is `""`
# and `ClangRenderer.abi` is `""` on darwin and `"__attribute__((ms_abi)) "` on
# win32 (cstyle.py:300-299, a `sys.platform` branch); the port does not take the
# win32 branch and that is the `TODO(p3)` at the foot.
# ===========================================================================

# `kernel_typedef` -- tinygrad/renderer/cstyle.py:122, :285, :324, :363, :425, :530 -- IS A
# HEAD/TAIL PAIR AROUND THE BOUND, NOT ONE STRING WITH A FIELD IN IT.
#
# Python's spelling is a `{launch_bounds}` FORMAT FIELD and
# `str.format(launch_bounds=..)` substitutes it, and there is no `str.format` in
# base.bend. The first version of this port spelled the brace in the literal and
# substituted it with a split-and-join, and that needed FOUR defs and a threaded
# flag because `String.split` takes one CHAR: splitting on `{` puts the field
# NAME at the HEAD of the following part, and the part is then read twice (once
# for `starts_with`, once for `drop`) and the arm gets a `+` binder for it. Two
# literal halves and one `String.append` is the same answer with no surgery, and
# it is what `str.format` amounts to when the field appears exactly once -- which
# it does in all three typedefs that have it, and in the other three the tail is
# empty. MEASURED: CUDA's is `extern "C" __global__ void __launch_bounds__(N)` and
# HIP's is `extern "C" __attribute__((global)) void
# __attribute__((amdgpu_flat_work_group_size(1, N)))` -- note HIP's bound is
# inside a SECOND attribute, which is why its head ends in `(1, ` and not `(`.
def kernel_typedef_head(+dev: U32) -> String:
  match dev:
    case 2: "__kernel void"
    case 3: "kernel void"
    case 4: "extern \"C\" __global__ void __launch_bounds__("
    case 5: "extern \"C\" __attribute__((global)) void __attribute__((amdgpu_flat_work_group_size(1, "
    case _: "void"

def kernel_typedef_tail(+dev: U32) -> String:
  match dev:
    case 4: ")"
    case 5: ")))"
    case _: ""

# DOES THIS TYPEDEF HAVE THE FIELD AT ALL? Three of the six do and three do not,
# and the head/tail pair ALONE cannot say so: for the three that do not the head
# IS the whole typedef and the tail is empty, so `head ++ lb ++ tail` produced
# `void1` and `__kernel void4`. MEASURED BY THE GATE on all four no-field rows.
# `str.format` on a template with no field is the IDENTITY, and this `Bool` is
# what says which of the two cases each typedef is in -- so it is a third thing
# rather than a comment, and the head/tail pair alone was not enough.
def has_bounds(+dev: U32) -> Bool:
  match dev:
    case 4: True{}
    case 5: True{}
    case _: False{}

# `f"{typedef.format(launch_bounds=lb)}"`. ONE DEF, NOT THREE: the head and the
# tail are each read twice across the two `Bool.pick` arms, which is legal on a
# `+` parameter, so the `.of`/wrapper pairs the tables used to carry were three
# defs of pure indirection. `has_bounds` is a `Bool` PARAMETER of the `match`
# rather than a computed value because a `match` may not scrutinise a call.
def kernel_typedef(+dev: U32, +lb: U32) -> String:
  Bool.pick(String, has_bounds(dev),
    String.concat([kernel_typedef_head(dev), U32.show(lb), kernel_typedef_tail(dev)]), kernel_typedef_head(dev))

# `buffer_prefix` -- tinygrad/renderer/cstyle.py:123, :325, :364. EMPTY on the base, on Clang and
# on both GPU vendors, and that is why a CUDA kernel argument is a plain `float*`.
def buffer_prefix.of(+dev: U32) -> String:
  match dev:
    case 2: "__global "
    case 3: "device "
    case _: ""

# `smem_prefix` -- tinygrad/renderer/cstyle.py:126, :327, :365, :426, :534. HIP'S SPELLING HAS NO
# TRAILING SPACE and `render_buffer` concatenates the prefix straight onto the
# type, so HIP renders `__attribute__((shared, aligned(16)))float L0[1];` with no
# space at all. That is CPython's output, measured, and it is a gate row
# precisely BECAUSE it looks like a typo -- a reader that "fixed" it would
# differ from the oracle on every HIP local.
def smem_prefix.of(+dev: U32) -> String:
  match dev:
    case 2: "__local "
    case 3: "threadgroup __attribute__((aligned(16))) "
    case 4: "__shared__ __align__(16) "
    case 5: "__attribute__((shared, aligned(16)))"
    case _: ""

# `smem_align` -- tinygrad/renderer/cstyle.py:125, :326. Only OpenCL sets it and only
# `render_buffer` reads it, which is why a base device's local buffer and an
# OpenCL one differ by exactly this prefix.
def smem_align.of(+dev: U32) -> String:
  match dev:
    case 2: "__attribute__ ((aligned (16))) "
    case _: ""

# `buffer_suffix` -- tinygrad/renderer/cstyle.py:124, :286. Clang's `restrict` is the ONLY
# non-empty one, and it is the whole difference between a Clang kernel argument
# `float* restrict data0_4` and an OpenCL one, `__global float* data0_4`.
def buffer_suffix.of(+dev: U32) -> String:
  match dev:
    case 1: " restrict"
    case _: ""

# `var_prefix` / `var_suffix` -- tinygrad/renderer/cstyle.py:128-129. THE BASE'S PAIR IS
# EVERY DEVICE'S PAIR: `const ` and `""`. **METAL DOES NOT OVERRIDE EITHER** --
# `MetalRenderer` (cstyle.py:366-372) sets `buffer_prefix`, `extra_args`, the workitem
# table and the type map, and NOTHING ELSE.
# ⇒ AND THIS USED TO ANSWER `constant ` AND `&` FOR METAL, WHICH WAS A PLAUSIBLE
# INVENTION AND A WRONG ONE. MEASURED: the census gate's `opt_varpre_3`/`opt_varsuf_3`
# rows were RED on exactly this (3 of 346 rows, `const `/`""` upstream vs
# `constant `/`&` here), so `constant float& alu0 = ...` was text no kernel in this
# tree ever had.
def var_prefix.of(+dev: U32) -> String: "const "

def var_suffix.of(+dev: U32) -> String: ""

# `infinity` / `nan` -- cstyle.py:140-141, :281-282. Clang's are the two
# `__builtin_` forms and every other device's are the `INFINITY` / `NAN` macros,
# which is why CUDA and HIP each EMIT those two `#define`s in `render_kernel` and
# Clang does not.
def infinity.of(+dev: U32) -> String:
  match dev:
    case 1: "__builtin_inff()"
    case _: "INFINITY"

def nan.of(+dev: U32) -> String:
  match dev:
    case 1: "__builtin_nanf(\"\")"
    case _: "NAN"

# `barrier` -- cstyle.py:133, :285, :328, :368, :428, :536. HIP's is THREE
# statements concatenated with NO separator, which is a fact about the string and
# not about the three fences.
def float4.of(+dev: U32) -> String:
  match dev:
    case 1: "(float4)"
    case 2: "(float4)"
    case 3: "float4"
    case 4: "make_float4"
    case 5: "make_float4"
    case _: "None"

# `float4_style` -- tinygrad/renderer/cstyle.py:134, :277. Clang's is the ONLY pair that is not
# `('(', ')')`, and it is what makes a Clang STACK render `(float4){(a),(b)}`
# where an OpenCL one renders `(float4)((a),(b))`.
def float4_open(+dev: U32) -> String:
  match dev:
    case 1: "{"
    case _: "("

def float4_close(+dev: U32) -> String:
  match dev:
    case 1: "}"
    case _: ")"

# `gep_arr_threshold` -- tinygrad/renderer/cstyle.py:135, :278, :430. Clang's is 0, CUDA's is 8 and
# every other device's is 4, and it is the cut between `buf[i]` and `buf.x` in
# `render_index` -- see there for why 0 is not "never".
def gep_arr_threshold.of(+dev: U32) -> U32:
  match dev:
    case 1: 0
    case 4: 8
    case _: 4

# ===========================================================================
# `type_map: dict[DType, str]` -- tinygrad/renderer/cstyle.py:136, :287, :331, :373, :439, :539.
# The KEY is the dtype's NAME, because two `DType`s with one name are the same
# `dtypes` singleton in Python, so the name IS the identity -- the same argument
# `uop/render.bend` makes for `ctx`'s `U32.show(u)` key.
#
# THE KEYS ARE `S.Dt`'s NAME FIELD AND NOT ITS ATTRIBUTE NAME, and that
# distinction is what this table's five multi-word C VALUES depend on being keyed
# correctly. It used to read "`dtypes.bfloat16.name` is `"__bf16"` and
# `dtypes.int8.name` is `"signed char"`, so a table keyed by attribute name would
# miss every one of them" -- and after tinygrad 793abbb those two facts are
# FALSE: the name field moved to the rust spellings, so `DType.name` is now
# `bf16` and `i8` and it EQUALS the attribute again. The keys below moved with it,
# and the reason to read `dt_name` rather than the constructor is now the fp8
# group, whose names (`fp8e4m3`) are not C names at all.
#
# Read `dt_name`, not the constructor.
#
# THE `.get(dtype, dtype.name)` DEFAULT IS LOAD-BEARING. An unmapped dtype
# renders as ITS OWN C NAME: `float8_e4m3` on CUDA maps to `__nv_fp8_e4m3` but
# `float8_e4m3fnuz` does not map at all and prints as `float8_e4m3fnuz`, which is
# a C identifier and not a type -- and that is exactly what CPython emits. A
# reader that answered "" for an unmapped dtype would be more "correct" and
# would differ from the oracle on five of the sixteen dtype rows.
# ===========================================================================

def dt_name(+d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, s}: s

# `Map.get` ANSWERS A `Sigma`, NOT A `Maybe` -- `Maybe.default(.., Map.get(..))`
# is `expected : Data -- observed : Quant` -- so the lookup is its own def and the
# pair is destructured in a second one. MEASURED, and it is `uop/render.bend`'s
# rule 2 verbatim; the `Sigma` type annotation IS the parameter type.
def tm_get.of(r: Sigma<&1, &1, Map<&2, String>, _ => String>) -> String:
  match r:
    case Tuple{m, v}: v

def tm_get(+m: Map<&2, String>, +nm: String) -> Sigma<&1, &1, Map<&2, String>, _ => String>:
  Map.get(String, nm, m, nm)

# `self.type_map.get(dtype, dtype.name)` -- the DEFAULT IS THE NAME ITSELF, so an
# unmapped dtype prints as itself. That is the row that keeps this honest: CUDA
# maps `fp8e4m3` and does NOT map `fp8e4m3fnuz`, and CPython prints the
# latter as itself.
def type_name(+m: Map<&2, String>, +d: S.Dt) -> String: tm_get.of(tm_get(m, dt_name(d)))

# THE SIX MAPS. Every subclass REPLACES `type_map` rather than updating it, so
# each of these is a whole map and not an overlay -- and an overlay would agree
# with a replace here ONLY because the base is `{}`, which is worth knowing and
# is why the base's `{}` is written out rather than left implicit.
#
# THE ENTRY LIST IS A `Kv` LINKED LIST AND NOT A FLAT `List<&2, String>`, for a
# measured reason: a three-element cons pattern `case k <> v <> t:` is "expected
# : cases for Nil, observed : `{}`", so a flat key/value list has no pattern that
# splits it in the middle. A one-field-per-record list is the shape
# `uop/render.bend` already uses for its `Bind{k, v}` rows, and it reads like the
# Python dict literal it replaces.
# `Kv` IS A `List`-SHAPED `Data` VALUE, NOT A `List` OF `Data`: `case Kv{..}`
# inside a `match` on a `List<&2, Kv>` is "expected : a constructor of List", so
# the cons cell has to BE the value. That is the same lesson `Ops` and `Arg` in
# `uop/ops.bend` carry -- a `match` arm names a constructor of the scrutinee's
# own type, and a `List`'s constructors are `Nil` and `<>` and nothing else.
def Kv.go(ks: Kv, +m: Map<&2, String>) -> Map<&2, String>:
  match ks:
    case KvEnd{}: m
    case Kv{k, v, t}: Kv.go(t, Map.set(&2, String, m, k, v))

def tm(ks: Kv) -> Map<&2, String>: Kv.go(ks, Map.new(&2, String))

# UPSTREAM'S `{**CStyleLanguage.type_map, ...}` IS AN OVERLAY, and this is the
# overlay. The previous version of this port read the base as `{}` and wrote each
# device map as a WHOLE map, which was internally consistent -- `Map.set` over an
# empty map is the map -- and agreed with every `py=` literal, because those
# literals were generated against the same wrong reading. MEASURED at HEAD:
# `CStyleLanguage.type_map` has FOURTEEN entries (cstyle.py:136-139), so a base of
# `{}` is not a base, it is a hole, and every device inherits the hole.
#
# THE fp8 GROUP IS NOT IN THE BASE. `CStyleLanguage.type_map` at cstyle.py:136
# lists void/bool/i8/u8/i16/u16/i32/u32/i64/u64/f16/bf16/f32/f64 and NOTHING
# else; only CUDA (cstyle.py:441) and HIP (cstyle.py:542) add fp8 entries. So
# `type_map[dtypes.fp8e4m3]` is a `KeyError` on four of the six devices and that
# is the truth, not a gap in this table.
#
# EVERY KEY BELOW IS A `DType.name`, NOT A `dtypes.*` ATTRIBUTE. tinygrad 793abbb
# moved `DType.name` onto the rust spellings, so the keys moved with it and the
# old C spellings ("signed char", "unsigned char", "__bf16", "half") are the
# LEGACY ATTRIBUTE names, not the name field, and never were -- which is why the
# comment this file used to carry at :477 is now wrong rather than merely stale.
def type_map.base() -> Map<&2, String>:
  tm(Kv{"bool", "bool", Kv{"i8", "signed char", Kv{"u8", "unsigned char",
    Kv{"i16", "short", Kv{"u16", "unsigned short", Kv{"i32", "int",
    Kv{"u32", "unsigned int", Kv{"i64", "long", Kv{"u64", "unsigned long",
    Kv{"f16", "half", Kv{"bf16", "__bf16", Kv{"f32", "float",
    Kv{"f64", "double", Kv{"void", "void", KvEnd{}}}}}}}}}}}}}}})

# `Kv.go` IS AN OVERLAY ALREADY -- it folds the tail into the map it is handed --
# so the device maps take the base as their seed and there is no second fold.
def type_map_over(ks: Kv) -> Map<&2, String>: Kv.go(ks, type_map.base())

# `{dtypes.bool: "_Bool", dtypes.f16: "__fp16"}` -- cstyle.py:290. TWO entries.
def type_map.clang() -> Map<&2, String>:
  type_map_over(Kv{"bool", "_Bool", Kv{"f16", "__fp16", KvEnd{}}})

# cstyle.py:334. SIX entries, and the fp8 group is ABSENT -- so all four fp8
# dtypes print as themselves on OpenCL, which is a gate row.
def type_map.opencl() -> Map<&2, String>:
  type_map_over(Kv{"i8", "char", Kv{"u8", "uchar", Kv{"u32", "uint",
    Kv{"u16", "ushort", Kv{"u64", "ulong", Kv{"bf16", "ushort", KvEnd{}}}}}}})

# cstyle.py:376. TWO entries.
def type_map.metal() -> Map<&2, String>:
  type_map_over(Kv{"u32", "uint", Kv{"bf16", "bfloat", KvEnd{}}})

# cstyle.py:441. FOUR entries -- and the two FNUZ fp8 dtypes are NOT among them,
# so on CUDA `fp8e4m3fnuz` prints as itself while `fp8e4m3` does not.
# THE CHAIN IS BACKWARDS AND THAT IS DELIBERATE. `Kv` is a cons list folded into
# a `Map`, so entry order is not observable -- `Map.set` is order free and
# `type_map.get` reads by key. MEASURED on Bend 2.0.34: this table spelled in
# the source order (`u32`, `bf16`, `fp8e4m3`, `fp8e5m2`) is REFUSED by the parser
# with "expected : a term, observed ')'" pointing at this line, one line or two,
# and the identical table spelled innermost-first parses. It is a compiler
# hazard and not a data one, and the only thing it costs is that the table does
# not read like cstyle.py's dict literal.
def type_map.cuda() -> Map<&2, String>:
  type_map_over(Kv{"fp8e5m2", "__nv_fp8_e5m2", Kv{"fp8e4m3", "__nv_fp8_e4m3", Kv{"bf16", "nv_bfloat16", Kv{"u32", "uint", KvEnd{}}}}})

# cstyle.py:520-522. `{**CStyleLanguage.type_map, **{d: ("hip_fp8","hip_bf8")[fp8_index(d)] for d in fp8s}}`
# -- and `fp8_index(d) = fp8s.index(d) % 2` with `fp8s` in dtype.py's order
# (e4m3, e5m2, e4m3fnuz, e5m2fnuz), so the OCP pair and the FNUZ pair are THE
# SAME pair. That is measured: HIP maps both e4m3 variants to `hip_fp8` and both
# e5m2 variants to `hip_bf8`, and the duplication is upstream's rather than a
# port artefact. FOUR entries, then -- **AND NOT `bf16`**: an earlier revision of
# this table answered `hip_bfloat16` for bfloat16 on the strength of a comment that
# said `cstyle.py:542` did, and it does not. MEASURED: the census gate's `rd_5_11`
# row read `__bf16` upstream against `hip_bfloat16` here, and this was the LAST red
# row of 346.
def type_map.hip() -> Map<&2, String>:
  type_map_over(Kv{"fp8e4m3", "hip_fp8", Kv{"fp8e5m2", "hip_bf8",
    Kv{"fp8e4m3fnuz", "hip_fp8", Kv{"fp8e5m2fnuz", "hip_bf8", KvEnd{}}}}})

# THE MAP A DEVICE ANSWERS. Six arms and a `_`, and the `_` is the base rather
# than a hole: every tag below 6 is a real device and the base is the right
# default for an unknown one because it is a real fourteen-entry dict.
def type_map.of(+dev: U32) -> Map<&2, String>:
  match dev:
    case 1: type_map.clang()
    case 2: type_map.opencl()
    case 3: type_map.metal()
    case 4: type_map.cuda()
    case 5: type_map.hip()
    case _: type_map.base()

# ===========================================================================
# `.replace(" ", "_")` -- cstyle.py:189, and it is on the `sz > 1` branch ONLY.
# A scalar `signed char` prints WITH the space and a vector `signed_char4` does
# not; both are gate rows, because a reader that underscored unconditionally
# would print `signed_char` for the scalar and differ from CPython on four
# dtypes x six devices.
#
# `String.replace` IS A WALL (`String.split` splits on ONE CHAR, so a
# multi-character substring replace has no primitive -- render.bend gap (b)).
# What the C names actually need is small and closed: FIVE of `DType.name`'s
# values contain a space and each becomes the same string with the space turned
# into an underscore. So the port SPLITS on ' ' and rejoins with '_', which is
# exact for every name in the table rather than a first-occurrence guess, and
# the gate's `under_*` rows are what says so.
# ===========================================================================

def under_split(nm: String) -> List<&2, String>: String.split(nm, ' ')

# ONE SELF-CALL, and the underscore goes in FRONT of every part after the first.
# The two-def split (`under_tail` / `under_rest`) would be mutual recursion,
# because each calls the other on the tail; folding them into one def with a
# threaded `seen` flag is the shape that terminates, and it is the same move
# `render.bend`'s `strip_binary_parens` makes with `has_precedence`.
# The prefix is INLINED into the arm rather than a helper, because a helper would
# have to be declared ABOVE this def and would then be a second `def` between the
# reader and its own recursion for the sake of one `Bool.pick`. `Bool.pick`'s
# order is the one the whole port uses: THIRD argument when the test is true.
def under_tail.go(parts: List<&2, String>, seen: Bool) -> String:
  match parts:
    case Nil{}: ""
    case h <> t: String.concat([Bool.pick(String, seen, "_", ""), h, under_tail.go(t, True{})])

def under(nm: String) -> String: under_tail.go(under_split(nm), False{})

def has_space.of(parts: List<&2, String>) -> Bool:
  match parts:
    case Nil{}: False{}
    case _ <> _: True{}

def has_space(nm: String) -> Bool: has_space.of(under_split(nm))

# ===========================================================================
# `_render_dtype` -- cstyle.py:180-190. THE most-read def in the file: it
# decides the type of every kernel argument, every local, every cast and every
# pointer, so a dropped character here is a kernel that does not compile and a
# diagnostic that points nowhere.
#
#     def _render_dtype(self, dtype, sz=1, addrspace=AddrSpace.ALU, mutable=True,
#                       override_ptr=False, shape=None):
#       if is_image_shape(shape): return f"{'write_only' if mutable else 'read_only'} image2d_t"
#       prefix, suffix = "", ""
#       if addrspace in (AddrSpace.LOCAL, AddrSpace.GLOBAL):
#         if addrspace == AddrSpace.LOCAL and self.smem_prefix_for_cast: prefix = self.smem_prefix
#         if addrspace == AddrSpace.GLOBAL: prefix = self.buffer_prefix
#       if addrspace in (AddrSpace.LOCAL, AddrSpace.GLOBAL) or override_ptr: suffix = "*"
#       if sz > 1: return prefix + self.type_map.get(dtype, dtype.name).replace(" ", "_") + str(sz) + suffix
#       return prefix + self.type_map.get(dtype, dtype.name) + suffix
#
# THE ARGS ARE PYTHON'S OWN. `dtype, sz, addrspace, mutable, override_ptr` are
# `_render_dtype`'s parameters in Python, and `shape` is the sixth -- reduced here
# to the `Bool` `is_image_shape(shape)` already computed, because the fold
# answers `List<&2, O.Sint>` and `is_image_shape` wants a `ShapeRes` (wall (c)).
# That reduction is why the string layer below is fully gateable even while wall
# (a) makes `_render` unreachable: every argument is a value the caller supplies,
# exactly as in Python, so the oracle is a direct method call.
#
# FIVE THINGS ARE LOAD-BEARING AND ALL FIVE ARE QUIET WHEN WRONG:
#   * the `type_map.get(.., dtype.name)` default;
#   * the underscore on the `sz > 1` branch ONLY;
#   * `str(sz)` appended only when `sz > 1`, so `sz == 0` would print the bare
#     name -- unreachable, since `sz` is `max_numel` and `prod(()) == 1`;
#   * `smem_prefix_for_cast`, False on CUDA and HIP and True on the other four,
#     which is the whole difference between `__shared__ __align__(16) float*` and
#     `threadgroup __attribute__((aligned(16))) float*` for the same space;
#   * `is_image_shape` BEATS EVERYTHING, INCLUDING the address space -- an image
#     in GLOBAL space is `read_only image2d_t` and not `__global read_only
#     image2d_t`. So the image arm is FIRST and returns whole.
# ===========================================================================

def is_global(+a: S.Addr) -> Bool:
  match a:
    case S.AGlobal{}: True{}
    case _: False{}

def is_local(+a: S.Addr) -> Bool:
  match a:
    case S.ALocal{}: True{}
    case _: False{}

# `addrspace in (AddrSpace.LOCAL, AddrSpace.GLOBAL)` -- the SAME set twice in
# `_render_dtype` (once for the prefix, once for the `*`), so it is one def read
# by both rather than two spellings that could drift.
def is_mem_addr(+a: S.Addr) -> Bool: Bool.or(is_local(a), is_global(a))

# `prefix` -- cstyle.py:183-185. LOCAL contributes `smem_prefix` and only when
# `smem_prefix_for_cast`; GLOBAL contributes `buffer_prefix`; ALU and REG
# contribute nothing.
def smem_prefix_for_cast(+dev: U32) -> Bool:
  match dev:
    case 4: False{}
    case 5: False{}
    case _: True{}

def rd_prefix.of(+dev: U32, +a: S.Addr, forcast: Bool) -> String:
  match a:
    case S.ALocal{}: Bool.pick(String, forcast, smem_prefix.of(dev), "")
    case S.AGlobal{}: buffer_prefix.of(dev)
    case _: ""

def rd_prefix(+dev: U32, +a: S.Addr) -> String:
  rd_prefix.of(dev, a, smem_prefix_for_cast(dev))

# `suffix` -- cstyle.py:186-187.
def rd_suffix(+a: S.Addr, override_ptr: Bool) -> String:
  Bool.pick(String, Bool.or(is_mem_addr(a), override_ptr), "*", "")

# THE NAME, with the `sz > 1` underscore. `Bool.and(vect, has_space(..))` is
# exactly Python's `if sz > 1: ..replace(" ", "_")` because the replace is a
# no-op for a name with no space -- so the conjunction is the same answer and not
# an approximation of it.
def rd_name.of(vect: Bool, unders: String, plain: String) -> String:
  Bool.pick(String, vect, unders, plain)
def rd_base_name(+dev: U32, +d: S.Dt) -> String: type_name(type_map.of(dev), d)


def rd_name(+dev: U32, +d: S.Dt, vect: Bool) -> String:
  rd_name.of(Bool.and(vect, has_space(rd_base_name(dev, d))), under(rd_base_name(dev, d)), rd_base_name(dev, d))

# `Bool.pick(-A, c, a, b)` ANSWERS `a` WHEN `c` IS TRUE -- so the UNDERSCORED
# spelling is the `b` arm and the plain one is the `a` arm. This line had them the
# other way round for one compile cycle, which underscored the four SCALAR
# columns and left the two `sz > 1` columns alone: `rd BASE unsigned char` came
# back `unsigned_char*|...|unsigned char4` where CPython says
# `unsigned char*|...|unsigned_char4`. NO `float` ROW COULD SEE IT -- a name with
# no space renders the same either way -- which is exactly why the gate carries a
# `signed char`-shaped row, and it is the same trap `render.bend` hit on
# `acall_tail` and that `bend2-constraints.md` rule 7 already records.



def rd_body(+dev: U32, +d: S.Dt, +sz: U32) -> String:
  Bool.pick(String, U32.is_gt(sz, 1),
    String.concat([rd_name(dev, d, True{}), U32.show(sz)]), rd_name(dev, d, False{}))

# `is_image_shape(shape)` -- wall (c), so the test arrives as a `Bool`.
def rd_image(mutable: Bool) -> String:
  Bool.pick(String, mutable, "write_only image2d_t", "read_only image2d_t")

# THE WHOLE DEF. Seven parameters because Python's has six plus a `self`, and
# the `sz > 1` test lives in `rd_body` rather than here so the image arm can
# return before any of it is computed.
def is_index(op: O.Op) -> Bool:
  match op:
    case O.OpsINDEX{}: True{}
    case _: False{}

def is_reg(+a: S.Addr) -> Bool:
  match a:
    case S.AReg{}: True{}
    case _: False{}

def is_cast(op: O.Op) -> Bool:
  match op:
    case O.OpsCAST{}: True{}
    case _: False{}

def is_const(op: O.Op) -> Bool:
  match op:
    case O.OpsCONST{}: True{}
    case _: False{}

def is_alu_addr(+a: S.Addr) -> Bool:
  match a:
    case S.Aalu{}: True{}
    case _: False{}

# `idx.op is Ops.CAST and idx.src[0].op is Ops.CONST` -- the CONST-INDEX test,
# and it is two arena reads. It guards BOTH ALU sub-branches, so it is one def
# rather than two spellings that could drift.
def idx_is_const_idx(+ar: O.Arena, +idx: U32) -> Bool:
  Bool.and(is_cast(O.Arena.op(ar, idx)), is_const(O.Arena.op(ar, O.Arena.src0(ar, idx))))

# `'xyzwabcd'[val]`. The literal is INLINED rather than named for two measured
# reasons: a method call on a call result -- `letters().get(n)` -- is a parse
# error ("expected : 'def', 'type' or 'law', observed : '.'", because a `def` body
# is a TERM and a term may not be a method call); and `String.get(s, n)` answers
# a `Maybe<&2, Char>`, not a `String`, so the character has to be read out of a
# list anyway. `String.to_list` + `List.get` + `Maybe.default` is the shape the
# substrate has, and the default is the FIRST letter -- see the wall note above.
# `Char.to_string` DOES NOT EXIST on 2.0.34 -- "expected : a defined name" -- so
# a `Char` becomes a one-element `String` the only way the substrate allows:
# `String.from_list` over the list holding it. `Char.to_u32` is the other half
# of the pair and is what `helpers.bend` uses for the same purpose.
def swizzle_char.of(m: Maybe<&2, Char>) -> String:
  match m:
    case Some{c}: String.from_list([c])
    case _: "x"

def swizzle_char(n: Nat) -> String: swizzle_char.of(List.get(&2, Char, String.to_list("xyzwabcd"), n))

def swizzle_val.of(+a: O.Arg) -> U32:
  match a:
    case O.APy{O.CInt{i}}: H.lo32(i)
    case _: 0

# `idx.src[0].val` -- the CONST under the CAST. `H.lo32` is exact on a value that
# fits 32 bits, which a swizzle index always does.
def swizzle_val(+ar: O.Arena, +idx: U32) -> U32: swizzle_val.of(O.Arena.arg(ar, O.Arena.src0(ar, idx)))

def swizzle_letter(+ar: O.Arena, +idx: U32) -> String:
  String.concat([".", swizzle_char(U32.to_nat(swizzle_val(ar, idx)))])

# `f"[{idx.src[0].val}]"` -- the array form, over the SAME CONST.
def const_idx_str(+ar: O.Arena, +idx: U32) -> String:
  String.concat(["[", U32.show(swizzle_val(ar, idx)), "]"])

# `buf.max_numel() > self.gep_arr_threshold`
def gep_uses_idx(+dev: U32, numel: U32) -> Bool: U32.is_gt(numel, gep_arr_threshold.of(dev))

def is_add(op: O.Op) -> Bool:
  match op:
    case O.OpsADD{}: True{}
    case _: False{}

# `idx.arg == Ops.ADD` IS A TEST AGAINST A LITERAL OP AND NOT AGAINST A REDUCE. MEASURED:
#
#   UOp(Ops.REDUCE, arg=Ops.ADD).arg is Ops.ADD            -> True   (the arg IS the enum)
#   UOp(Ops.REDUCE, arg=(Ops.ADD, 0)).arg == Ops.ADD       -> False  (a TUPLE never equals it)
#
# and `UOp.reduce`'s sugar sets the TUPLE, so a real REDUCE never strips. THE PORT MATCHED THE
# TUPLE FORM (`AReduce{ADD,0}`) AND SO STRIPPED ON EVERY REAL REDUCE:
#
#   ri_add_0   CPython (buf1+(a+b))   port (buf1+a+b)
#
# A TUPLE CANNOT EQUAL AN OP, so "the arg is `AReduce`" is not the test -- and the arena's
# CLOSED `Arg` spells "the arg IS an op" as `AOpLit`, which is the arm that can match. The old
# comment claimed the `AReduce` arm was "the only way an index node's arg is an op"; the
# measurement above is what says otherwise.
#
# AND THIS BRANCH HAD NO ROW UNTIL A MUTATION SAID SO. Fixing the defect changed what this
# matches from `AReduce` to `AOpLit`, and the census drove ONE fixture -- `arg=(Ops.ADD, 0)` --
# on which BOTH tests are false, so both lanes took the do-not-strip arm, agreed, and the strip
# had no row anywhere. `gates/cstyle_render_census-mutate.py`'s M8 ("render_index never strips
# parens") moved 0 of 358 rows, which is how the gap was found; `ri_lit_*` now drives
# `AOpLit{OpsADD{}}` -- the shape `upat.py:26`'s `UOp(Ops.PYLITERAL, arg=self.op[0])` builds --
# and M8 moves 3. A fix that makes a branch UNREACHED is indistinguishable from a fix that
# makes it unreachable, and only a mutation tells them apart.
def idx_arg_is_add(+a: O.Arg) -> Bool:
  match a:
    case O.AOpLit{op}: is_add(op)
    case _: False{}

# THE ALU BRANCH. `lane` is the "not a CONST index" test, threaded in because it
# is the one test that needs `idx`'s own src and the gate's fixtures set `idx`
# up differently per branch.
def render_index.alu(+ar: O.Arena, +dev: U32, +bname: String, +iname: String, +idx: U32, bnumel: U32, lane: Bool) -> String:
  Bool.pick(String, lane, String.concat(["(", bname, ")[", iname, "]"]),
    String.concat([bname, Bool.pick(String, gep_uses_idx(dev, bnumel), const_idx_str(ar, idx), swizzle_letter(ar, idx))]))

def render_index.alu2(ok: Bool, +ar: O.Arena, +dev: U32, +bname: String, +iname: String, +idx: U32, bnumel: U32, lane: Bool) -> String:
  Bool.pick(String, ok, render_index.alu(ar, dev, bname, iname, idx, bnumel, lane),
    String.concat(["(", bname, "+", Bool.pick(String, idx_arg_is_add(O.Arena.arg(ar, idx)), H.strip_parens(iname), iname), ")"]))

# THE WHOLE DEF. Python takes `x, buf, idx` and reads `x` for nothing at all --
# it is in the signature so the `base_rewrite` arm can pass `**kwargs` -- and it
# reads `buf` for its ADDRESS SPACE, its NAME and its ELEMENT COUNT, all three of
# which the port takes as parameters. What is left of `buf` is nothing, and what
# is left of the signature is the INDEX node alone -- which is why the third
# parameter is `idx` and not `bidx`: the name `bidx` claimed to be the buffer
# index and the buffer is not in this def at all.
def render_index(+ar: O.Arena, +dev: U32, idx: U32, baddr: S.Addr, bname: String, iname: String, bnumel: U32, lane: Bool) -> String:
  render_index.alu2(is_alu_addr(baddr), ar, dev, bname, iname, idx, bnumel, lane)

# ===========================================================================
# `render_buffer` -- cstyle.py:175-178, the `Ops.BUFFER` arm of `base_rewrite`.
#
#     prefix = f"{self.smem_align}{self.smem_prefix}" if x.addrspace == AddrSpace.LOCAL else ""
#     suffix = f"[{x.max_numel()}]"
#     return f"{prefix}{self._render_dtype(x.dtype)} {self[x]}{suffix};"
#
# FOUR THINGS, and the first produces the row that LOOKS wrong:
#   * the prefix is `smem_align` FOLLOWED BY `smem_prefix`, and HIP's
#     `smem_prefix` has no trailing space, so the two concatenate into
#     `__attribute__((shared, aligned(16)))float` with NO space before the type.
#     Measured, and a gate row precisely because a reader would "fix" it.
#   * `_render_dtype(x.dtype)` is the DEFAULT ARGUMENT SHAPE -- `sz=1`,
#     `addrspace=ALU` -- so a LOCAL buffer's type carries NO `*` even though a
#     LOCAL POINTER does. The address space is consumed by the PREFIX here, not
#     by the type. That is why the type argument is `S.Aalu{}` and not `a`.
#   * `x.max_numel()` is a BUFFER's element count, which is `ParamArg.size`: a
#     concrete int, so wall (b) does not apply here.
#   * the trailing `;` lives in `render_buffer` and NOT in the `Ops.BUFFER` rule,
#     because the rule's string is also the DECLARATION `_render` emits.
# ===========================================================================

def rb_prefix.of(+dev: U32, +a: S.Addr) -> String:
  match a:
    case S.ALocal{}: String.concat([smem_align.of(dev), smem_prefix.of(dev)])
    case _: ""

def rb_prefix(+dev: U32, +a: S.Addr) -> String: rb_prefix.of(dev, a)

def render_buffer(+dev: U32, +d: S.Dt, numel: U32, +a: S.Addr, name: String) -> String:
  String.concat([rb_prefix(dev, a), rd_base_name(dev, d), " ", name, "[", U32.show(numel), "];"])

# ===========================================================================
# `code_for_op` -- cstyle.py:142-150, and the per-device overrides at :288-291,
# :376, :432-438 and :532-533. `dict[Ops, Callable]`, so the ARM is a match on the
# op and the DEVICE is the tag -- there is no closure to store.
#
# TWO SHAPES IN THE PYTHON AND BOTH MATTER:
#   * UNARY (`x, dtype`) and BINARY (`a, b, dtype`) and TERNARY (`a, b, c,
#     dtype`). `Ops.WHERE` is the only ternary, and it is the only arm whose
#     arity differs, so a reader that threaded one argument list would emit
#     `(a?b)` for WHERE. The `xs` parameter is the whole src list and the arms
#     pick from it, so the arity is visible in the arm.
#   * the `dtype` argument is READ by exactly six ops on CUDA (`h`/`htrunc`/
#     `hsin`/`hlog2`/`hexp2`/`hsqrt`/`hrcp` for half and bfloat16) and by Clang's
#     `SQRT`/`TRUNC`/`FDIV` (the `f64` variants). Everywhere else it is ignored,
#     so it is a parameter of the def rather than a per-arm read.
#
# THE DEVICE SPLIT IS MEASURED AND IT IS SMALL: Clang DROPS `EXP2`, `SIN`, `LOG2`
# and `RECIPROCAL` entirely (they become libcalls the compiler lowers, cstyle.py:
# :288) and adds `FDIV`; CUDA and HIP keep all twenty-one and override six; Metal
# overrides one (`SIN` -> `precise::sin`); OpenCL and QCOM change nothing. A
# dropped op is a `KeyError` in Python, so the dropped arm is a gate row.
# ===========================================================================

def cfo_unary(nm: String, +x: String) -> String: String.concat([nm, "(", x, ")"])

# `f"(1/{x})"` and `f"-{x}"` are NEITHER of them the unary `f"{nm}({x})"` shape,
# so they are their own defs rather than a "prefix" helper with an empty name.
# `cfo_prefixed("", x)` would be `f"-{x}"` by accident and `cfo_prefixed("1/", x)`
# would be `f"-1/({x})"` -- the unary template has the parens INSIDE, so neither
# spelling of a prefix template reaches these two. MEASURED by the oracle:
# RECIPROCAL is `(1/X)` and NEG is `-X`.
def cfo_recip(+x: String) -> String: String.concat(["(1/", x, ")"])

def cfo_neg(+x: String) -> String: String.concat(["-", x])

def cfo_bin(+a: String, sym: String, b: String) -> String: String.concat(["(", a, sym, b, ")"])

def cfo_tern(+a: String, b: String, c: String) -> String: String.concat(["(", a, "?", b, ":", c, ")"])

# A DROPPED ARM IS CPython's `code_for_op[x.op]` AND THAT RAISES. Bend is total and cannot
# raise, so the answer has to be a STRING, and `""` is the one string that is BOTH a silent
# wrong answer and a spelling no C compiler accepts silently: `base_rewrite`'s ALU arm wraps
# the answer in `f"..."` at the operator's own precedence, so an empty one deletes the
# operand and leaves a kernel that is wrong rather than broken -- the exact shape this file's
# own header names as the dangerous one. So the refusal NAMES ITS CAUSE, and it is
# `wgsl.bend`'s spelling and not a new one: `renderer/wgsl.bend:473 symbol=code_for_op.of` answers `UNHANDLED(Ops.X)` for
# the same `KeyError` on the same twenty inherited arms, and `THE PORT's `renderer/wgsl.bend` HEADER` says those arms
# MOVE HERE when cstyle lands. Two spellings of one refusal is FINDING 2 in `wgsl_render_census-gate.py`,
# which is why this reuses the sibling's token instead of inventing a third.
def cfo_unhandled(op: O.Op) -> String: String.concat(["UNHANDLED(Ops.", O.Ops.name.of(op), ")"])

# `xs` is the src-name list, `xs0`/`xs1`/`xs2` its three positional reads. `nd` is
# the number of srcs, which is the arity test: WHERE has three and everything
# else has two or one, and `head`/`nth` on an empty list is the BOTTOM of the
# list rather than a crash -- so an op reached with the wrong arity renders a
# visibly wrong string instead of a wrong type.
def xs_at(xs: List<&2, String>, n: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, n), "?")

def cfo_xs1(xs: List<&2, String>) -> String: xs_at(xs, 0n)

def cfo_xs2(xs: List<&2, String>) -> String: xs_at(xs, 1n)

def cfo_xs3(xs: List<&2, String>) -> String: xs_at(xs, 2n)

# THE BASE TABLE. `Ops.WHERE` is the ternary and it is matched FIRST because the
# op match is a single `match` and Python's dict has no arity to distinguish it.
# THE BASE TABLE HAS NO `Ops.FDIV` ARM AND THAT IS CORRECT, NOT AN OMISSION:
# cstyle.py:142-150 is a dict literal of TWENTY-ONE keys and `FDIV` is not one of
# them -- Clang ADDS it (cstyle.py:291) and no other device has it. A reader that
# gave the base an `FDIV` arm would answer `(X/Y)` where CPython raises
# `KeyError`, and the `_` arm is that raise, totalised by `cfo_unhandled`. MEASURED BY THE
# GATE: with an `FDIV` arm in the base, the mutation "delete Clang's explicit FDIV arm" moved NO
# ROW, because Clang then fell through to a base arm that should not have been
# there. Removing it makes the Clang arm load-bearing, which is what it is.
def code_for_base.of(op: O.Op, +xs: List<&2, String>) -> String:
  match op:
    case O.OpsSQRT{}: cfo_unary("sqrt", cfo_xs1(xs))
    case O.OpsRECIPROCAL{}: cfo_recip(cfo_xs1(xs))
    case O.OpsNEG{}: cfo_neg(cfo_xs1(xs))
    case O.OpsEXP2{}: cfo_unary("exp2", cfo_xs1(xs))
    case O.OpsLOG2{}: cfo_unary("log2", cfo_xs1(xs))
    case O.OpsSIN{}: cfo_unary("sin", cfo_xs1(xs))
    case O.OpsTRUNC{}: cfo_unary("trunc", cfo_xs1(xs))
    case O.OpsAND{}: cfo_bin(cfo_xs1(xs), "&", cfo_xs2(xs))
    case O.OpsXOR{}: cfo_bin(cfo_xs1(xs), "^", cfo_xs2(xs))
    case O.OpsOR{}: cfo_bin(cfo_xs1(xs), "|", cfo_xs2(xs))
    case O.OpsADD{}: cfo_bin(cfo_xs1(xs), "+", cfo_xs2(xs))
    case O.OpsSUB{}: cfo_bin(cfo_xs1(xs), "-", cfo_xs2(xs))
    case O.OpsMUL{}: cfo_bin(cfo_xs1(xs), "*", cfo_xs2(xs))
    case O.OpsCMOD{}: cfo_bin(cfo_xs1(xs), "%", cfo_xs2(xs))
    case O.OpsCDIV{}: cfo_bin(cfo_xs1(xs), "/", cfo_xs2(xs))
    case O.OpsCMPNE{}: cfo_bin(cfo_xs1(xs), "!=", cfo_xs2(xs))
    case O.OpsSHR{}: cfo_bin(cfo_xs1(xs), ">>", cfo_xs2(xs))
    case O.OpsSHL{}: cfo_bin(cfo_xs1(xs), "<<", cfo_xs2(xs))
    case O.OpsCMPLT{}: cfo_bin(cfo_xs1(xs), "<", cfo_xs2(xs))
    case O.OpsWHERE{}: cfo_tern(cfo_xs1(xs), cfo_xs2(xs), cfo_xs3(xs))
    case O.OpsCMPEQ{}: cfo_bin(cfo_xs1(xs), "==", cfo_xs2(xs))
    case _: cfo_unhandled(op)

# ===========================================================================
# THE PER-DEVICE ALU OVERRIDES. Six ops on CUDA, five on HIP, one on Metal, two
# on Clang, and the FIVE THAT ARE DROPPED. `is_half` is the `dtype in (half,
# bfloat16)` test, and it is a `Bool` PARAMETER rather than a dtype so the
# override tables do not each re-derive it.
# ===========================================================================

def is_half(+d: S.Dt) -> Bool:
  Bool.or(O.eq_dt(d, S.half()), O.eq_dt(d, S.bfloat16()))

def is_f64(+d: S.Dt) -> Bool: O.eq_dt(d, S.double())

# THERE IS NO `is_f32`, and the absence is load-bearing rather than an omission:
# Clang's suffix rule is `f` UNLESS f64 (cstyle.py:288-289) and HIP's `_ocml` map
# is `{half:16, double:64}.get(dtype, 32)` with 32 as the DEFAULT -- so `float`
# reaches both by falling through, and a third predicate would be a fourth way to
# spell "not one of those two".

# CLANG: `SQRT` and `TRUNC` pick the `f64` spelling by dtype, `FDIV` is ADDED,
# and `EXP2`/`SIN`/`LOG2`/`RECIPROCAL` are DELETED (cstyle.py:288-291). The
# comprehension is `{k:v for k,v in base.items() if k not in [EXP2, SIN, LOG2,
# TRUNC, RECIPROCAL]}` and then TRUNC and FDIV and SQRT are re-set, so TRUNC
# SURVIVES and the other three do not. The deletion is the load-bearing half and
# `cfo_unhandled` is its answer -- a `KeyError` in Python, and here a token that names
# the op and cannot compile. THOSE FOUR ARMS STAY EXPLICIT even though all four now
# answer the same thing, because they are the only thing standing between Clang and the
# base's `exp2`/`sin`/`log2`/`(1/x)` arms; deleting them renders four ALU ops upstream
# refuses to render. MEASURED: the mutation that deletes all four moves 4 rows.
#
# THE SUFFIX IS `f` UNLESS THE DTYPE IS f64, and there is no separate f32 case:
# Clang emits `__builtin_sqrtf(X)` for float AND for half and
# `__builtin_sqrt(X)` for double. MEASURED, all three.
def ocml_or(+base: String, suf: String, f64: Bool) -> String:
  Bool.pick(String, f64, base, String.concat([base, suf]))

def code_for_clang.of(op: O.Op, +xs: List<&2, String>, +d: S.Dt) -> String:
  match op:
    case O.OpsSQRT{}: cfo_unary(ocml_or("__builtin_sqrt", "f", is_f64(d)), cfo_xs1(xs))
    case O.OpsTRUNC{}: cfo_unary(ocml_or("__builtin_trunc", "f", is_f64(d)), cfo_xs1(xs))
    case O.OpsFDIV{}: cfo_bin(cfo_xs1(xs), "/", cfo_xs2(xs))
    case O.OpsEXP2{}: cfo_unhandled(op)
    case O.OpsSIN{}: cfo_unhandled(op)
    case O.OpsLOG2{}: cfo_unhandled(op)
    case O.OpsRECIPROCAL{}: cfo_unhandled(op)
    case _: code_for_base.of(op, xs)

# METAL: `SIN` is the ONLY override and it is `precise::sin` for every dtype
# (cstyle.py:376).
def code_for_metal.of(op: O.Op, +xs: List<&2, String>, +d: S.Dt) -> String:
  match op:
    case O.OpsSIN{}: cfo_unary("precise::sin", cfo_xs1(xs))
    case _: code_for_base.of(op, xs)

# CUDA: `htrunc`/`hsin`/`hlog2`/`hexp2`/`hsqrt`/`hrcp` for half and bfloat16, and
# the PLAIN form otherwise (cstyle.py:432-438). Six ops, one `Bool`.
def cuda_pick(half: Bool, hnm: String, nm: String, +x: String) -> String:
  Bool.pick(String, half, cfo_unary(hnm, x), cfo_unary(nm, x))

# HIP: `_ocml(op)` is `f"__ocml_{op}_f{ {half:16, double:64}.get(dtype, 32)}({x})"`
# (cstyle.py:493) -- the WIDTH, not a dtype name, and 32 is the default for
# everything else including f32. So the map is a two-entry lookup with a 32
# fallback and the `f` is always there.
def ocml_bits(+d: S.Dt) -> U32:
  Bool.pick(U32, O.eq_dt(d, S.half()), 16, Bool.pick(U32, is_f64(d), 64, 32))

def ocml_name(op: String, +d: S.Dt) -> String:
  String.concat(["__ocml_", op, "_f", U32.show(ocml_bits(d))])

def code_for_hip.of(op: O.Op, +xs: List<&2, String>, +d: S.Dt) -> String:
  match op:
    case O.OpsTRUNC{}: cfo_unary(ocml_name("trunc", d), cfo_xs1(xs))
    case O.OpsSIN{}: cfo_unary(ocml_name("sin", d), cfo_xs1(xs))
    case O.OpsLOG2{}: cfo_unary(ocml_name("log2", d), cfo_xs1(xs))
    case O.OpsEXP2{}: cfo_unary(ocml_name("exp2", d), cfo_xs1(xs))
    case O.OpsSQRT{}: cfo_unary(ocml_name("sqrt", d), cfo_xs1(xs))
    case _: code_for_base.of(op, xs)

def code_for_cuda.of(op: O.Op, +xs: List<&2, String>, +d: S.Dt) -> String:
  match op:
    case O.OpsTRUNC{}: cuda_pick(is_half(d), "htrunc", "trunc", cfo_xs1(xs))
    case O.OpsSIN{}: cuda_pick(is_half(d), "hsin", "sin", cfo_xs1(xs))
    case O.OpsLOG2{}: cuda_pick(is_half(d), "hlog2", "log2", cfo_xs1(xs))
    case O.OpsEXP2{}: cuda_pick(is_half(d), "hexp2", "exp2", cfo_xs1(xs))
    case O.OpsSQRT{}: cuda_pick(is_half(d), "hsqrt", "sqrt", cfo_xs1(xs))
    case O.OpsRECIPROCAL{}: Bool.pick(String, is_half(d), cfo_unary("hrcp", cfo_xs1(xs)), cfo_recip(cfo_xs1(xs)))
    case _: code_for_base.of(op, xs)

# THE DISPATCH. Five devices and the base, and OpenCL and QCOM are the BASE --
# measured: neither overrides a single ALU op, and the gate's `cfo` rows are
# what says so rather than a comment.
def code_for_op.of(+dev: U32, op: O.Op, xs: List<&2, String>, +d: S.Dt) -> String:
  match dev:
    case 1: code_for_clang.of(op, xs, d)
    case 3: code_for_metal.of(op, xs, d)
    case 4: code_for_cuda.of(op, xs, d)
    case 5: code_for_hip.of(op, xs, d)
    case _: code_for_base.of(op, xs)

# ===========================================================================
# `code_for_workitem` -- tinygrad/renderer/cstyle.py:131, :330, :370, :431, :531. Five devices
# spell the workitem id and the BASE and Clang have an EMPTY dict, so a SPECIAL on
# either is a `KeyError` in Python -- MEASURED, `CStyleLanguage.code_for_workitem` and
# `ClangRenderer.code_for_workitem` are both `{}`, and `code_for_workitem["g"]` raises
# `KeyError('g')` on both. The refusal NAMES THE MISSING KEY, which is what CPython's
# `KeyError` argument is, and it is not reachable for a real kernel: every GPU renderer
# defines both entries.
#
# `""` was the port's marker until this arm was made loud, and it was the worst of the
# three: `base_rewrite`'s SPECIAL arm is `f"{...}; /* ... */"`, so `""` emits a bare `;`
# -- a statement that computes NOTHING and compiles. `cfw_0_g` and `cfw_0_l` were also
# byte-identical to each other, which is a row whose `k` argument could not move it.
#
# THE THREE SPELLINGS, and the third is the interesting one: Metal and CUDA
# INDEX A MEMBER BY ASCII -- `chr(120 + int(x))` on a STRING argument, so `x` is
# the workitem index as a decimal string and `int(x)` is 0, 1 or 2. HIP and
# OpenCL pass the string STRAIGHT INTO the builtin, so `get_group_id(0)` is
# literally that. The port keeps the `U32` and formats it, which is the same
# answer for 0..2 and is stated because `int("07")` in Python is 7 and
# `U32.show(7)` is `"7"`.
# ===========================================================================

def witem_xyz(n: U32) -> String: String.from_list([Char.from_u32(U32.add(120, n))])

def witem_miss(+k: String) -> String: String.concat(["UNHANDLED(code_for_workitem[", k, "])"])

def code_for_workitem.g(+dev: U32, +k: String, n: U32) -> String:
  match dev:
    case 2: String.concat([Bool.pick(String, String.eq(k, "g"), "get_group_id(", "get_local_id("), U32.show(n), ")"])
    case 3: String.concat([Bool.pick(String, String.eq(k, "g"), "gid.", "lid."), witem_xyz(n)])
    case 4: String.concat([Bool.pick(String, String.eq(k, "g"), "blockIdx.", "threadIdx."), witem_xyz(n)])
    case 5: String.concat([Bool.pick(String, String.eq(k, "g"), "__ockl_get_group_id(", "__ockl_get_local_id("), U32.show(n), ")"])
    case _: witem_miss(k)

# ===========================================================================
# `_wmma_name` -- cstyle.py:113-117, and the one place a NAME is built from a
# dtype and sanitised.
#
#     return f"WMMA_{'_'.join(map(str, u.arg[0]))}_{u.arg[1].name}_{u.dtype.name}".replace(" ", "_")
#
# THE SANITISE IS THE WHOLE POINT and it is NOT conditional: `int8.name` is
# `"signed char"`, so without the replace the name is
# `WMMA_16_16_16_signed char_float`, which is not a C identifier. With it, the
# name is `WMMA_16_16_16_signed_char_float`. The same replace machinery as
# `_render_dtype` serves both, and the gate's `wmma_*` rows pin the space case
# specifically -- an implementation that reused the C NAME spelling but dropped
# the replace would produce a name no compiler accepts.
#
# `u.dtype` is the OUTPUT dtype and `u.arg[1].name` the INPUT, and they are
# spelled from different places, so a reader that used one for both would be right
# on the three fixtures where they coincide and wrong on the rest.
# ===========================================================================

def wmma_dims_go(ds: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}: acc
    case h <> t: wmma_dims_go(t, List.append(&2, String, acc, [U32.show(h)]))

def wmma_dims(ds: List<&2, U32>) -> String: String.join(wmma_dims_go(ds, Nil{}), "_")

# `'_'.join(map(str, u.arg[0]))` -- the arg is `AWmma{dims, dt, threads, tc}`.
def wmma_dims.of(+a: O.Arg) -> String:
  match a:
    case O.AWmma{dims, dt, threads, tc}: wmma_dims(dims)
    case _: ""

# `u.arg[1].name` -- the INPUT dtype.
def wmma_in.of(+a: O.Arg) -> String:
  match a:
    case O.AWmma{dims, dt, threads, tc}: dt_name(dt)
    case _: ""

# `f"WMMA_{dims}_{in}_{out}".replace(" ", "_")` -- the replace is UNCONDITIONAL,
# unlike `_render_dtype`'s.
def wmma_name_of(dims: String, din: String, dout: String) -> String:
  under(String.concat(["WMMA_", dims, "_", din, "_", dout]))

def KU.op(k: KU) -> O.Op:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs}: op

def KU.dtype(k: KU) -> S.Dt:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs}: dtype

def KU.addr(k: KU) -> S.Addr:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs}: addr

def KU.numel(k: KU) -> U32:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs}: numel

def KU.shape(k: KU) -> List<&2, U32>:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs}: shape

def KU.arg(k: KU) -> KUArg:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs}: arg

def KU.srcs(k: KU) -> List<&2, U32>:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs}: srcs

def KU.nsrc(k: KU) -> U32:
  U32.from_nat(List.length(&2, U32, KU.srcs(k)))

def KU.src0(k: KU) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, KU.srcs(k), 0n), 0)

def KU.src1(k: KU) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, KU.srcs(k), 1n), 0)

def KU.src2(k: KU) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, KU.srcs(k), 2n), 0)

def KUArg.is_const(a: KUArg) -> Bool:
  match a:
    case KAConst{v}: True{}
    case _: False{}

def ku_const_int(c: O.Const) -> Maybe<&1, H.I64>:
  match c:
    case O.CInt{i}: Some{i}
    case _: None{}

def ku_const_float(c: O.Const) -> Maybe<&1, F32>:
  match c:
    case O.CFloat{f}: Some{f}
    case _: None{}

def KUArg.const_int(a: KUArg) -> Maybe<&1, H.I64>:
  match a:
    case KAConst{v}: ku_const_int(v)
    case _: None{}

def KUArg.const_float(a: KUArg) -> Maybe<&1, F32>:
  match a:
    case KAConst{v}: ku_const_float(v)
    case _: None{}

def KUArg.param_slot(a: KUArg) -> U32:
  match a:
    case KAParam{slot, name, volatile_, bytes}: slot
    case _: 0

def KUArg.param_name(a: KUArg) -> Maybe<&2, String>:
  match a:
    case KAParam{slot, name, volatile_, bytes}: name
    case _: None{}

def KUArg.param_volatile(a: KUArg) -> Bool:
  match a:
    case KAParam{slot, name, volatile_, bytes}: volatile_
    case _: False{}

def KUArg.param_bytes(a: KUArg) -> U32:
  match a:
    case KAParam{slot, name, volatile_, bytes}: bytes
    case _: 0

def KUArg.range_axis(a: KUArg) -> O.AxisType:
  match a:
    case KARange{axis, ids}: axis
    case _: O.AXIS_WEAK{}

def KUArg.range_ids(a: KUArg) -> List<&2, U32>:
  match a:
    case KARange{axis, ids}: ids
    case _: Nil{}

def KUArg.index_off(a: KUArg) -> U32:
  match a:
    case KAIndex{off, is_add}: off
    case _: 0

# `idx.arg == Ops.ADD` (cstyle.py:174) -- the INDEX's OWN arg is the `Ops` enum
# `Ops.ADD`, and that is the ONLY test that decides whether the index's parens
# are stripped. It is `AOpLit{OpsADD{}}` in the port's arena spelling.
def KUArg.index_is_add(a: KUArg) -> Bool:
  match a:
    case KAIndex{off, is_add}: is_add
    case _: False{}

def KUArg.sink_name(a: KUArg) -> String:
  match a:
    case KASink{name}: name
    case _: "test"

def KUArg.special_axis(a: KUArg) -> String:
  match a:
    case KASpecial{axis, n, nm}: axis
    case _: "l"

def KUArg.special_n(a: KUArg) -> U32:
  match a:
    case KASpecial{axis, n, nm}: n
    case _: 0

def KUArg.special_nm(a: KUArg) -> String:
  match a:
    case KASpecial{axis, n, nm}: nm
    case _: "lidx0"

# ===========================================================================
# THE PREFIX TABLE. Upstream's `cstyle.py:242-244`:
#
#     prefix = {Ops.WMMA: "wmma", Ops.BUFFER: "buf", Ops.CAST: "cast", Ops.BITCAST: "cast",
#               Ops.STACK: "cast", Ops.INDEX: "bidx", Ops.LOAD: "val"}.get(u.op, "alu")
#     r[u] = f"{prefix}{c[prefix]}"
#
# SIX PREFIXES, SO SIX COUNTERS, AND THE COUNTER IS A LIST INDEXED BY THE
# PREFIX'S NUMBER -- not a `Map`, because the key set is CLOSED and a number is
# a number. `c[prefix]` IS THE COUNTER AND IT IS ONLY INCREMENTED WHEN THE
# UOP BECAME A STATEMENT (`cstyle.py:261`: `if prefix: c[prefix] += 1`), which
# is why an INLINED uop does NOT BURN A NUMBER.
# ===========================================================================
def ku_pfx_ix(op: O.Op) -> U32:
  match op:
    case O.OpsWMMA{}: 5
    case O.OpsBUFFER{}: 4
    case O.OpsCAST{}: 2
    case O.OpsBITCAST{}: 2
    case O.OpsSTACK{}: 2
    case O.OpsINDEX{}: 3
    case O.OpsLOAD{}: 1
    case _: 0

def ku_pfx(ix: U32) -> String:
  match ix:
    case 5: "wmma"
    case 4: "buf"
    case 2: "cast"
    case 3: "bidx"
    case 1: "val"
    case _: "alu"

# `axis_letters` -- tinygrad/uop/ops.py:50:
#   {AxisType.DEVICE: "d", AxisType.GLOBAL: "g", AxisType.LOCAL: "l",
#    AxisType.WARP: "w", AxisType.WEAK: "L", AxisType.UPCAST: "u", ...}
def range_str.go(+ids: List<&2, U32>, +acc: String) -> String:
  match ids:
    case Nil{}: acc
    case h <> t:
      range_str.go(t, Bool.pick(String, U32.is_eq(h, 2147483648),
        String.concat([acc, Bool.pick(String, String.is_empty(acc), "", "_"), "m", U32.show(U32.sub(0, h))]),
        String.concat([acc, Bool.pick(String, String.is_empty(acc), "", "_"), U32.show(h)])))
def range_str(+ids: List<&2, U32>) -> String:
  range_str.go(ids, "")

def rt(r: List<&2, String>, i: U32) -> String:
  Maybe.default(&2, String, List.get(&2, String, r, U32.to_nat(i)), "")

def ku_at(+kus: List<&2, KU>, i: U32) -> Maybe<&2, KU>:
  List.get(&2, KU, kus, U32.to_nat(i))

# EVERY `match` IN THIS BLOCK HAS A PARAMETER FOR ITS SCRUTINEE, because Bend
# REFUSES A COMPUTED VALUE: `match ku_at(kus, i):` IS REFUSED ("a match cannot
# scrutinize a computed value"), AND SO IS A NESTED `match` ON A CALL. THE
# `.go` SHAPE IS THEREFORE THE HOUSE STYLE HERE: THE HELPER TAKES THE `Maybe`
# AS A PARAMETER AND THE CALLER PASSES THE CALL.
def ku_op_at.go(m: Maybe<&2, KU>) -> O.Op:
  match m:
    case Some{k}: KU.op(k)
    case None{}: O.OpsNOOP{}

def ku_op_at(+kus: List<&2, KU>, i: U32) -> O.Op: ku_op_at.go(ku_at(kus, i))  def ku_is_const_at.go(m: Maybe<&2, KU>) -> Bool:
  match m:
    case Some{k}: KUArg.is_const(KU.arg(k))
    case None{}: False{}

def ku_is_const_at(+kus: List<&2, KU>, +i: U32) -> Bool: ku_is_const_at.go(ku_at(kus, i))  def ku_is_cast_at.go(m: Maybe<&2, KU>) -> Bool:
  match m:
    case Some{k}: O.eq_op(KU.op(k), O.OpsCAST{})
    case None{}: False{}

def ku_is_cast_at(+kus: List<&2, KU>, +i: U32) -> Bool: ku_is_cast_at.go(ku_at(kus, i))  def ku_src0_at.go(m: Maybe<&2, KU>) -> U32:
  match m:
    case Some{k}: KU.src0(k)
    case None{}: 0

def ku_src0_at(+kus: List<&2, KU>, i: U32) -> U32: ku_src0_at.go(ku_at(kus, i))  def ku_const_int_at.go(m: Maybe<&2, KU>) -> Maybe<&1, H.I64>:
  match m:
    case Some{k}: KUArg.const_int(KU.arg(k))
    case None{}: None{}

def ku_const_int_at(+kus: List<&2, KU>, i: U32) -> Maybe<&1, H.I64>:
  ku_const_int_at.go(ku_at(kus, i))

def ku_const_float_at.go(m: Maybe<&2, KU>) -> Maybe<&1, F32>:
  match m:
    case Some{k}: KUArg.const_float(KU.arg(k))
    case None{}: None{}

def ku_const_float_at(+kus: List<&2, KU>, i: U32) -> Maybe<&1, F32>:
  ku_const_float_at.go(ku_at(kus, i))

def ku_const_val.go(m: Maybe<&1, H.I64>) -> U32:
  match m:
    case Some{v}: H.lo32(v)
    case None{}: 0

def ku_swizzle(n: U32) -> String:
  match n:
    case 0: "x"
    case 1: "y"
    case 2: "z"
    case 3: "w"
    case 4: "a"
    case 5: "b"
    case 6: "c"
    case _: "d"

def ku_index_is_const_cast(+kus: List<&2, KU>, +idx: U32) -> Bool:
  Bool.and(ku_is_cast_at(kus, idx), ku_is_const_at(kus, ku_src0_at(kus, idx)))

def ku_render_index.global(dev: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  String.concat(["(", rt(r, KU.src0(k)), "+",
    Bool.pick(String, KUArg.index_is_add(KU.arg(k)), H.strip_parens(rt(r, KU.src1(k))), rt(r, KU.src1(k))), ")"])

# ===========================================================================
# THE TEXT OF ONE UOP -- the port of `base_rewrite` (cstyle.py:11-77), FOR THE
# OPS THE CPU LANE NEEDS. THE ORDER IS UPSTREAM'S ORDER, AND THE ORDER IS THE
# RULE: the CONST arms come BEFORE the generic CAST arm.
# ===========================================================================
def ku_text_if(dev: U32, k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  String.concat(["if (", rt(r, KU.src0(k)), ") {"])

# `  if (!({ctx[c]})) {\n break;\n}\n}` -- cstyle.py:20.
def ku_text_backedge(dev: U32, k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  String.concat(["  if (!(", rt(r, KU.src0(k)), ")) {\n break;\n}\n}"])

def ku_text_buffer(dev: U32, i: U32, +k: KU, +r: List<&2, String>) -> String:
  render_buffer(dev, KU.dtype(k), KU.numel(k), KU.addr(k), rt(r, i))

# `f"__{_wmma_name(x)}({ctx[x.src[0]]}, {ctx[x.src[1]]}, {ctx[x.src[2]]})"` -- cstyle.py:63.
def ku_text_wmma(dev: U32, +k: KU, +r: List<&2, String>) -> String:
  String.concat(["__wmma(", rt(r, KU.src0(k)), ", ", rt(r, KU.src1(k)), ", ", rt(r, KU.src2(k)), ")"])

# THE ALU ARM -- cstyle.py:64-65:
#   `ctx.code_for_op[x.op](*([strip_parens(ctx[v]) if v.op == x.op and x.op in {ADD, MUL, XOR, OR, AND} else ctx[v] for v in x.src]), x.dtype)`
# THE STRIP IS THE SAME-OP TEST AND IT IS NOT COSMETIC: it is what makes
# `((x)+(y))` AND `((x)+(y)+(z))` COMPOSE.
def ku_strips(+op: O.Op) -> Bool:
  Bool.or(Bool.or(O.eq_op(op, O.OpsADD{}), O.eq_op(op, O.OpsMUL{})),
    Bool.or(O.eq_op(op, O.OpsXOR{}), Bool.or(O.eq_op(op, O.OpsOR{}), O.eq_op(op, O.OpsAND{}))))

# ===========================================================================
# THE WALK -- the port of `cstyle.py:208-266`'s BODY. THE STATE IS SIX THINGS
# AND THEY ARE SIX THINGS BECAUSE BEND HAS NO MUTABLE MAP: `r` (the name/text
# map, INDEXED BY THE UOP'S POSITION), `kernel` (the emitted lines), `bufs` (the
# kernel's arguments), `c` (the six prefix counters), `depth` (the indent) and
# `name` (the kernel's name, from the SINK).
# ===========================================================================
def St.r(s: St) -> List<&2, String>:
  match s:
    case St{r, kernel, bufs, c, depth, name}: r

def St.kernel(s: St) -> List<&2, String>:
  match s:
    case St{r, kernel, bufs, c, depth, name}: kernel

def St.bufs(s: St) -> List<&2, BArg>:
  match s:
    case St{r, kernel, bufs, c, depth, name}: bufs

def St.c(s: St) -> List<&2, U32>:
  match s:
    case St{r, kernel, bufs, c, depth, name}: c

def St.depth(s: St) -> U32:
  match s:
    case St{r, kernel, bufs, c, depth, name}: depth

def St.name(s: St) -> String:
  match s:
    case St{r, kernel, bufs, c, depth, name}: name

def St.of(+r: List<&2, String>, +kernel: List<&2, String>, +bufs: List<&2, BArg>,
          +c: List<&2, U32>, depth: U32, name: String) -> St: St{r, kernel, bufs, c, depth, name}

# `r` GROWS BY ONE ENTRY PER UOP, INCLUDING THE SKIPPED ONES, because `r` IS
# INDEXED BY THE UOP'S POSITION AND THE POSITIONS OF THE LATER UOPS MUST NOT
# MOVE.
def st_put(+st: St, x: String) -> St:
  St.of(List.append(&2, String, St.r(st), [x]), St.kernel(st), St.bufs(st), St.c(st), St.depth(st), St.name(st))

def st_set(+st: St, i: U32, x: String) -> St:
  St.of(List.set(&2, String, St.r(st), U32.to_nat(i), x), St.kernel(st), St.bufs(st), St.c(st), St.depth(st), St.name(st))

def st_kernel(+st: St, x: String) -> St:
  St.of(St.r(st), List.append(&2, String, St.kernel(st), [x]), St.bufs(st), St.c(st), St.depth(st), St.name(st))

def st_bufs(+st: St, x: BArg) -> St:
  St.of(St.r(st), St.kernel(st), List.append(&2, BArg, St.bufs(st), [x]), St.c(st), St.depth(st), St.name(st))

def st_c(+st: St, +ix: U32) -> St:
  St.of(St.r(st), St.kernel(st), St.bufs(st),
    List.set(&2, U32, St.c(st), U32.to_nat(ix),
      U32.add(Maybe.default(&2, U32, List.get(&2, U32, St.c(st), U32.to_nat(ix)), 0), 1)), St.depth(st), St.name(st))

def st_depth(+st: St, d: U32) -> St:
  St.of(St.r(st), St.kernel(st), St.bufs(st), St.c(st), d, St.name(st))

def st_name(+st: St, nm: String) -> St:
  St.of(St.r(st), St.kernel(st), St.bufs(st), St.c(st), St.depth(st), nm)

# THE INDENT: `"  "*depth` (cstyle.py:260).
def ku_indent.go(depth: Nat, acc: String) -> String:
  match depth:
    case 0n: acc
    case 1n+p: ku_indent.go(p, String.concat([acc, "  "]))

# THE CHILD COUNT -- cstyle.py:212:
#   `child_count = Counter(v for ru in uops for v in ru.src)`
# IT IS THE HISTOGRAM OF "HOW MANY TIMES IS THIS UOP A SOURCE", AND IT IS THE
# WHOLE OF THE INLINE-vs-STATEMENT DECISION.
def ku_indent(depth: U32) -> String:
  ku_indent.go(U32.to_nat(depth), "")

def cc_one.go(+ss: List<&2, U32>, +cc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: cc
    case h <> t: cc_one.go(t, List.set(&2, U32, cc, U32.to_nat(h),
      U32.add(Maybe.default(&2, U32, List.get(&2, U32, cc, U32.to_nat(h)), 0), 1)))

def cc_one(k: KU, +cc: List<&2, U32>) -> List<&2, U32>:
  cc_one.go(KU.srcs(k), cc)

def ku_inline2a(+op: O.Op, k: KU, +kus: List<&2, KU>) -> Bool:
  Bool.or(Bool.and(O.eq_op(op, O.OpsCAST{}), ku_is_const_at(kus, KU.src0(k))),
    Bool.or(O.eq_op(op, O.OpsINDEX{}), O.eq_op(op, O.OpsSHRINK{})))

# `(u.op is Ops.LOAD and u.src[0].addrspace == AddrSpace.REG and child_count[u] == 1)`
def ku_inline2b2a(+op: O.Op, +k: KU) -> Bool:
  Bool.and(Bool.or(O.eq_op(op, O.OpsCAST{}), O.eq_op(op, O.OpsBITCAST{})),
    Bool.or(is_global(KU.addr(k)), is_local(KU.addr(k))))

# `(u.op in {Ops.STACK, *(GroupOp.ALU-{Ops.WHERE}), Ops.CAST, Ops.BITCAST} and child_count[u] == 1)`
def cc_at(+cc: List<&2, U32>, i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, cc, U32.to_nat(i)), 0)

def ku_src_is_reg.go(m: Maybe<&2, KU>) -> Bool:
  match m:
    case Some{s}: is_reg(KU.addr(s))
    case None{}: False{}

def ku_src_is_reg(+kus: List<&2, KU>, k: KU) -> Bool:
  ku_src_is_reg.go(ku_at(kus, KU.src0(k)))

def ku_is_alu_ex_where(+op: O.Op) -> Bool:
  Bool.and(R.is_alu(op), Bool.not(O.eq_op(op, O.OpsWHERE{})))

# ===========================================================================
# THE WALK, ONE UOP AT A TIME. cstyle.py:221-262.
# ===========================================================================
def ku_param_base.go(m: Maybe<&2, String>, arg: KUArg) -> String:
  match m:
    case Some{nm}: String.join(String.split(nm, ':'), "_")
    case None{}: String.concat(["data", U32.show(KUArg.param_slot(arg))])

def ku_param_base(+arg: KUArg) -> String: ku_param_base.go(KUArg.param_name(arg), arg)

def ku_shape_str.go(+ss: List<&2, U32>, +acc: String) -> String:
  match ss:
    case Nil{}: acc
    case h <> t: ku_shape_str.go(t, String.concat([acc, Bool.pick(String, String.is_empty(acc), "", "_"), U32.show(h)]))

def ku_shape_str(+ss: List<&2, U32>) -> String:
  ku_shape_str.go(ss, "")

def ku_not_stmt_op(+op: O.Op) -> Bool:
  Bool.not(Bool.or(Bool.or(O.eq_op(op, O.OpsRANGE{}), O.eq_op(op, O.OpsBUFFER{})),
    O.eq_op(op, O.OpsBINARY{})))

def _render.pop(+st: St, +k: KU) -> St:
  Bool.pick(St, Bool.or(O.eq_op(KU.op(k), O.OpsENDIF{}),
    Bool.or(O.eq_op(KU.op(k), O.OpsEND{}), O.eq_op(KU.op(k), O.OpsBACKEDGE{}))),
    st_depth(st, U32.sub(St.depth(st), 1)), st)

def _render.push(+st: St, +k: KU) -> St:
  Bool.pick(St, Bool.or(O.eq_op(KU.op(k), O.OpsIF{}), O.eq_op(KU.op(k), O.OpsRANGE{})),
    st_depth(st, U32.add(St.depth(st), 1)), st)
def DtN.dt(x: DtN) -> S.Dt:
  match x:
    case DtN{dt, n}: dt

def DtN.n(x: DtN) -> U32:
  match x:
    case DtN{dt, n}: n

def uops_to_dtypes.has(+x: DtN, +acc: List<&2, DtN>) -> Bool:
  match acc:
    case Nil{}: False{}
    case h <> t:
      Bool.or(Bool.and(O.eq_dt(DtN.dt(h), DtN.dt(x)), U32.is_eq(DtN.n(h), DtN.n(x))),
        uops_to_dtypes.has(x, t))

# `render_vector_prefix` -- cstyle.py:302-306:
#   `alignment = dt.itemsize if self.target.device == "CPU" else (...)`
#   `vec = self._render_dtype(dt, count, AddrSpace.REG)`
#   `return f"typedef {self.render_dtype(dt)} {vec} __attribute__((aligned({alignment}),ext_vector_type({count})));"`
def ku_align(cpu: Bool, +dt: S.Dt) -> U32:
  Bool.pick(U32, cpu, S.Dt.itemsize(dt), 4)

# `_render_defines` -- cstyle.py:308.
def axis_letter(a: O.AxisType) -> String:
  match a:
    case O.AXIS_DEVICE{}: "d"
    case O.AXIS_GLOBAL{}: "g"
    case O.AXIS_LOCAL{}: "l"
    case O.AXIS_WARP{}: "w"
    case O.AXIS_WEAK{}: "L"
    case O.AXIS_UPCAST{}: "u"
    case _: "L"

# `range_str(u)` -- tinygrad/uop/ops.py:97-99:
#   `'_'.join([str(x) if x >= 0 else "m"+str(-x) for x in u.axis_id])`
# `axis_id` IS `u.arg[1:]` (ops.py:486), so it is the RANGE's ids.
def ku_range_name(+arg: KUArg) -> String:
  String.concat([axis_letter(KUArg.range_axis(arg)), "idx", range_str(KUArg.range_ids(arg))])

# ===========================================================================
# THE TEXT OF ONE UOP -- the port of `base_rewrite` (cstyle.py:11-77), FOR THE
# OPS THE CPU LANE NEEDS. THE ORDER IS UPSTREAM'S ORDER, AND THE ORDER IS THE
# RULE: the CONST arms come BEFORE the generic CAST arm, and that is what
# decides `56` AND NOT `(int)(56)`.
#
# `r` IS THE NAME/TEXT MAP AND IT IS INDEXED BY THE UOP'S POSITION, because the
# uop list is POST-ORDER. `rt` READS IT.
# ===========================================================================
def ku_alu_srcs.go(+op: O.Op, k: KU, +kus: List<&2, KU>, +r: List<&2, String>,                    +ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case h <> t:
      ku_alu_srcs.go(op, k, kus, r, t, List.append(&2, String, acc,
        [Bool.pick(String, Bool.and(O.eq_op(ku_op_at(kus, h), op), ku_strips(op)),
          H.strip_parens(rt(r, h)), rt(r, h))]))

def ku_alu_srcs(op: O.Op, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> List<&2, String>:
  ku_alu_srcs.go(op, k, kus, r, KU.srcs(k), Nil{})

def ku_inline2b1(+op: O.Op, +k: KU, +kus: List<&2, KU>, +cc: List<&2, U32>, +i: U32) -> Bool:
  Bool.and(O.eq_op(op, O.OpsLOAD{}),
    Bool.and(ku_src_is_reg(kus, k), U32.is_eq(cc_at(cc, i), 1)))
def ku_inline_op_set(+op: O.Op) -> Bool:
  Bool.or(O.eq_op(op, O.OpsSTACK{}),
    Bool.or(ku_is_alu_ex_where(op),
      Bool.or(O.eq_op(op, O.OpsCAST{}), O.eq_op(op, O.OpsBITCAST{}))))

def ku_inline2b2b(+op: O.Op, +cc: List<&2, U32>, +i: U32) -> Bool:
  Bool.and(ku_inline_op_set(op), U32.is_eq(cc_at(cc, i), 1))

def ku_param_name(+k: KU) -> String:
  String.concat([ku_param_base(KU.arg(k)), "_", ku_shape_str(KU.shape(k))])

def ku_is_decl(+k: KU) -> Bool:
  Bool.and(ku_not_stmt_op(KU.op(k)), Bool.not(O.eq_dt(KU.dtype(k), S.void())))

def _render.plain(dev: U32, i: U32, +k: KU, kus: List<&2, KU>, cc: List<&2, U32>,
                  +st: St, +l: String, nm: String, ix: U32) -> St:
  +st0 = _render.pop(st, k)
  +st1 = Bool.pick(St, O.eq_op(KU.op(k), O.OpsCAST{}),
    st_kernel(st0, String.concat([ku_indent(St.depth(st0)), l, ";"])),
    st_kernel(st0, String.concat([ku_indent(St.depth(st0)), l])))
  +st2 = st_c(st1, ix)
  _render.push(st2, k)
def uops_to_dtypes.put(+x: DtN, +acc: List<&2, DtN>) -> List<&2, DtN>:
  Bool.pick(List<&2, DtN>, uops_to_dtypes.has(x, acc),
    acc, List.append(&2, DtN, acc, [x]))

def ku_text_alu(dev: U32, +op: O.Op, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  code_for_op.of(dev, op, ku_alu_srcs(op, k, kus, r), KU.dtype(k))
def ku_inline2b2(+op: O.Op, k: KU, +cc: List<&2, U32>, +i: U32) -> Bool:
  Bool.or(ku_inline2b2a(op, k), ku_inline2b2b(op, cc, i))

def uops_to_dtypes.one(+k: KU, +acc: List<&2, DtN>) -> List<&2, DtN>:
  Bool.pick(List<&2, DtN>,
    Bool.and(is_alu_addr(KU.addr(k)), Bool.not(O.eq_dt(KU.dtype(k), S.void()))),
    uops_to_dtypes.put(DtN{KU.dtype(k), KU.numel(k)}, acc), acc)

def ku_inline2b(+op: O.Op, +k: KU, +kus: List<&2, KU>, +cc: List<&2, U32>, +i: U32) -> Bool:
  Bool.or(ku_inline2b1(op, k, kus, cc, i), ku_inline2b2(op, k, cc, i))
def ku_inline2(+op: O.Op, +k: KU, +kus: List<&2, KU>, +cc: List<&2, U32>, +i: U32) -> Bool:
  Bool.or(ku_inline2a(op, k, kus), ku_inline2b(op, k, kus, cc, i))

# `(u.op is Ops.CAST and u.src[0].op is Ops.CONST) or u.op in {Ops.INDEX, Ops.SHRINK, Ops.CUSTOMI}`
def ku_inline(+op: O.Op, +k: KU, +kus: List<&2, KU>, +cc: List<&2, U32>, +i: U32) -> Bool:
  Bool.and(Bool.or(Bool.not(O.eq_op(op, O.OpsCAST{})), U32.is_eq(KU.numel(k), 1)),
    ku_inline2(op, k, kus, cc, i))

def BArg.image(b: BArg) -> Bool:
  match b:
    case BArg{name, dtype, addr, mutable, volatile_, image}: image


# `uops_to_dtypes(uops)` and the four `any(...)` scans in the six `render_kernel`
# overrides, each reduced to the Bool it is tested for. `nonfinite` is the CAST
# of a non-finite CONST (cstyle.py:559) and `special` is `any(Ops.SPECIAL)`
# (cstyle.py:561) -- both are one `any` in Python and one `Bool` here.
#
# `half_any` IS A SECOND HALF FLAG AND NOT A TYPO. OpenCL tests
# `any(uop.dtype == dtypes.f16 for uop in uops)` over EVERY uop (cstyle.py:349)
# while CUDA and HIP test the ALU-FILTERED `used_dtypes` (cstyle.py:458, :558) --
# and `uops_to_dtypes` drops anything that is not `AddrSpace.ALU`
# (cstyle.py:113). MEASURED: a kernel whose only half is a half BUFFER gets
# OpenCL's `#pragma` and NOT CUDA's `#include <cuda_fp16.h>`. One Bool would have
# to be wrong for one of them, and `kern2H` is the row that says which.
def barrier.of(+dev: U32) -> String:
  match dev:
    case 1: "__atomic_thread_fence(__ATOMIC_SEQ_CST);"
    case 2: "barrier(CLK_LOCAL_MEM_FENCE);"
    case 3: "threadgroup_barrier(mem_flags::mem_threadgroup);"
    case 4: "__syncthreads();"
    case 5: "__builtin_amdgcn_fence(__ATOMIC_RELEASE, \"workgroup\");__builtin_amdgcn_s_barrier();__builtin_amdgcn_fence(__ATOMIC_ACQUIRE, \"workgroup\");"
    case _: ""

# `float4` -- cstyle.py:136, :276, :329, :369, :429, :538. THE BASE IS `None`,
# AND `""` IS NOT `None`: the `Ops.STACK` rule (cstyle.py:55-56) does
# `self.float4.replace('float4', render_type(x))`, so `None` there is an
# `AttributeError` and `""` would emit a bare `float4{...}` with no constructor.
# THE ANSWER IS THE STRING `"None"`, and that is `dsl.bend`'s standing rule for an
# ABSENT value rather than a refusal -- `_variant_suffix` answers a suffix or `None`,
# and `dsl.bend:2066-2069` records that "an empty string is NOT the same answer, so the
# port prints `None`". CPython prints `None` too (`str(None)`), so this row now AGREES
# instead of being a declared divergence.
#
# WHAT IT STILL DOES NOT BUY: the STACK arm is not ported, so nothing reads it yet, and
# `"None"` is still a string rather than an absence -- `.replace` on it is a no-op where
# CPython raises `AttributeError`. That gap is named rather than papered over with a
# `has_float4` Bool that nothing reads.
#   TODO(p3) cstyle.py:55-56  `base_rewrite`'s `Ops.STACK` arm. It needs
#   `float4` to be `None`-distinguishable, which is the one place a `Data` cannot
#   carry the answer and a device TAG cannot either: the base is the only `None`
#   and the tag already says it. Unblocked when the arena rewrite lands.
def render_dtype(+dev: U32, +d: S.Dt, sz: U32, +a: S.Addr, mutable: Bool, override_ptr: Bool, img: Bool) -> String:
  Bool.pick(String, img, rd_image(mutable),
    String.concat([rd_prefix(dev, a), rd_body(dev, d, sz), rd_suffix(a, override_ptr)]))

# `render_dtype(dt, mutable=True)` -- cstyle.py:203, marked `# LEGACY`. It is
# `_render_dtype(dt, 1, AddrSpace.REG)`, so the REG address space is the load-
# bearing argument: it is what makes the answer carry no `*` and no prefix, and
# `render_cast`'s `({render_type(u)})({val})` depends on that.
def render_dtype_legacy(+dev: U32, +d: S.Dt) -> String:
  render_dtype(dev, d, 1, S.AReg{}, True{}, False{}, False{})

# ===========================================================================
# `render_type` / `render_ptr` / `render_access` / `render_cast` -- cstyle.py:
# 192-200. Four defs, and together they are the pointer/cast vocabulary every
# load and store is written in.
#
#     def render_type(self, u): return self._render_dtype(u.dtype, u.max_numel(), u.addrspace,
#         shape=u._shape, override_ptr=u.op is Ops.INDEX and u.addrspace is AddrSpace.REG)
#     def render_ptr(self, u):
#       if u.max_numel() > 1 or u.dtype != u.src[0].dtype:
#         return f"(({self._render_dtype(u.dtype, u.max_numel(), u.addrspace, override_ptr=True, shape=u._shape)})({self[u]}))"
#       else: return f"{self[u]}"
#     def render_access(self, u): return f"*{self.render_ptr(u)}"
#     def render_cast(self, u, val): return f"({self.render_type(u)})({val})"
#
# `render_type` is the one that needs the FOLD (dtype, addrspace, shape, op) and
# so it is where wall (a) bites; it is ported with those as PARAMETERS, which is
# the same argument as `_render_dtype` and for the same reason. The Python
# signature takes a `u`, and the values Python reads off it are exactly these
# four, so the port's signature is the same set of facts with the read moved to
# the caller -- which is where the fold lives.
#
# `override_ptr=u.op is Ops.INDEX and u.addrspace is AddrSpace.REG` is the one to
# watch: a REG-space INDEX is a VECTOR REGISTER and renders as a pointer, so
# `render_type` of a REG INDEX is `float4*` and not `float4`. That is measured
# and it is a gate row on its own.
# ===========================================================================

def render_type(+dev: U32, +d: S.Dt, +numel: U32, +a: S.Addr, op: O.Op, img: Bool) -> String:
  render_dtype(dev, d, numel, a, True{}, Bool.and(is_index(op), is_reg(a)), img)

# `render_ptr`. The `dtype != u.src[0].dtype` half is a DTYPE COMPARISON between
# the access and its buffer, and it is the half that decides whether a load goes
# through a cast pointer: a `float4` read of a `float` buffer is
# `((float4*)(buf))` and a `float` read of the same buffer is `buf`. `vec` is the
# `max_numel() > 1` half and `diff` the dtype half, kept apart so the gate can
# pin each: `ptr stack4` is the `vec` arm and `ptr bitcast` the `diff` arm.
def render_ptr(+dev: U32, +d: S.Dt, +numel: U32, +a: S.Addr, sdt: S.Dt, +name: String, op: O.Op, img: Bool) -> String:
  Bool.pick(String, Bool.or(U32.is_gt(numel, 1), Bool.not(O.eq_dt(d, sdt))),
    String.concat(["((", render_dtype(dev, d, numel, a, True{}, True{}, img), ")(", name, "))"]), name)

def render_access(+dev: U32, +d: S.Dt, numel: U32, +a: S.Addr, +sdt: S.Dt, +name: String, op: O.Op, img: Bool) -> String:
  String.concat(["*", render_ptr(dev, d, numel, a, sdt, name, op, img)])

def render_cast(+dev: U32, +d: S.Dt, numel: U32, +a: S.Addr, op: O.Op, img: Bool, val: String) -> String:
  String.concat(["(", render_type(dev, d, numel, a, op, img), ")(", val, ")"])

# ===========================================================================
# `render_index` -- cstyle.py:168-173. SIX branches in Python and they reduce to
# TWO, and the reduction is the interesting part of this def:
#
#     if buf.addrspace == AddrSpace.ALU:
#       if not (idx.op is Ops.CAST and idx.src[0].op is Ops.CONST): return f"({self[buf]})[{self[idx]}]"
#       return self[buf]+(f"[{idx.src[0].val}]" if buf.max_numel() > self.gep_arr_threshold
#                         else f".{'xyzwabcd'[idx.src[0].val]}")
#     return f"({self[buf]}+{strip_parens(self[idx]) if idx.arg == Ops.ADD else self[idx]})"
#
# THE ALU BRANCH HAS THREE OUTCOMES, NOT TWO. The "this is lane access in C"
# comment above it covers the array form, but a CONST index BELOW the threshold
# is rendered as a SWIZZLE -- `buf.x` -- and that is neither `buf[i]` nor
# `buf[0]`. `gep_arr_threshold` decides which, and it is read in the direction
# that is easy to get backwards: above it, index; at or below it, swizzle. So
# Clang's 0 means a ONE-ELEMENT buffer still gets `.x` (0 > 0 is false) and
# CUDA's 8 means an EIGHT-ELEMENT buffer still gets `[0]` (8 > 8 is false). Both
# are measured and both are gate rows.
#
# `'xyzwabcd'[val]` IS A STRING INDEX and a CONST's value is a `U32`. A value of
# 8 or more is an `IndexError` in Python; the port's `String.get` is total with a
# default, and the default is the FIRST letter. Stated because it is a
# difference, not because it is reachable -- tinygrad never swizzles past `d`.
# ===========================================================================

def wmma_name(+a: O.Arg, dout: S.Dt) -> String:
  wmma_name_of(wmma_dims.of(a), wmma_in.of(a), dt_name(dout))

# ===========================================================================
# `uops_to_dtypes` -- cstyle.py:112-113.
#
#     return dedup((u.dtype, u.max_numel()) for u in uops if u.addrspace in (AddrSpace.ALU, None) and u.dtype != dtypes.void and u._shape is not None)
#
# THREE FILTERS AND THEY ARE NOT INDEPENDENT. `addrspace in (ALU, None)` is the
# one that keeps a REGISTER value out (a `val0` on a GPU is ALU, a `gid` is
# REG), `dtype != void` drops a SINK, and `_shape is not None` drops a node the
# fold could not shape. The port's `addr` is `S.Addr` and Python's `None` is not
# one of its four values -- it is what `fold.addr` answers for a node whose
# sources disagree -- so the port's filter is `ALU` alone and the `None` arm is
# the `TODO(p3)` at the foot.
#
# `dedup` RETAINS LIST ORDER (helpers.py:23, `list(dict.fromkeys(x))`) and the
# order is the gate, because the RESULT FEEDS `ClangRenderer._render_defines`
# and the `typedef`s come out in it.
# ===========================================================================

# `uops_to_dtypes` ITSELF IS NOT HERE, and the two filters it applies are not
# separate defs either: both are already one Bool each in the `Uses` record
# above (`is_alu_addr` is the ALU filter and `is_void` is `dtype != dtypes.void`),
# so a def per filter would be a second spelling of a field.
#   TODO(p3) cstyle.py:110-113  `uops_to_dtypes`. Needs the fold (wall (a)); its
#   result ORDER feeds `ClangRenderer._render_defines`, so it is not a set.

# ===========================================================================
# `render_kernel` -- cstyle.py:154-166. THE function that assembles a whole
# kernel, and the only place in this file that reads nine options at once.
#
#     buftypes = [(name, ("volatile_ " if u.arg.volatile_ else "")+
#                    (self.var_prefix if u.addrspace == AddrSpace.ALU else "")+
#                    self._render_dtype(u.dtype, sz=1, addrspace=u.addrspace, mutable=mutable, shape=u._shape)+
#                    (self.var_suffix if u.addrspace == AddrSpace.ALU else self.buffer_suffix))
#                for name,(u,mutable) in bufs]
#     local_dims = [u.src[0] for u in uops if u.op is Ops.SPECIAL and u.arg[0] == "l"]
#     launch_bounds = prod([d.vmax for d in local_dims])
#     prg = ''.join([f"{self.kernel_typedef.format(launch_bounds=launch_bounds)} {function_name}(",] +
#               [', '.join([f'{t} {name}' for name,t in buftypes] + self.extra_args)] +
#               [") {\n" + tmp] + ['\n'.join(kernel), "\n}"])
#     return prg if prefix is None else "\n".join(prefix)+f"\n{prg}"
#
# FIVE THINGS, AND THE THIRD IS THE ONE THAT SAYS A DROPPED LITERAL IS A DROPPED
# LITERAL RATHER THAN A COMPILE ERROR:
#   * `launch_bounds = prod([d.vmax for d in local_dims])` and `prod(())` is 1 --
#     so a kernel with NO local SPECIAL gets `__launch_bounds__(1)`, not 0. The
#     gate's `kern nolocal` row is exactly that case, and a reader that started
#     the accumulator at 0 would emit `(0)`.
#   * `prefix is None` is the WHOLE BRANCH, and `[]` is not `None`: an empty
#     prefix list must NOT gain a leading newline. Metal's prefix is
#     non-empty and CUDA's is four lines, so the two cases both occur.
#   * `extra_args` is Metal's THREE lines (cstyle.py:372) and it is appended to
#     the SAME `', '.join` as the buffer types, so Metal's kernel signature is
#     `kernel void E_4(device float* data0_4, constant args_t& args
#     [[buffer(0)]], uint3 gid [[...]], uint3 lid [[...]])`. The port takes
#     `extra_args` as a `List<&2, String>` and joins it into the same list.
#   * `launch_bounds` comes from `d.vmax` -- a SYMBOLIC maximum, and the
#     `TODO(p3) ops.py:1092 symbol=UOp.vmax` wall again. It is a `U32` PARAMETER here, and the
#     SPECIAL's `vmax` on a linearized kernel is its CONST end.
#   * `kernel_typedef.format(launch_bounds=..)` is a `str.format`, and there is no
#     `format` in base.bend, so the `{launch_bounds}` FIELD is substituted by a
#     split on the literal and a join -- `render.bend`'s shape for a Python
#     f-string the port cannot evaluate.
# ===========================================================================

# `local_dims = [u.src[0] for u in uops if u.op is Ops.SPECIAL and u.arg[0]=="l"]`
# and then `prod([d.vmax ...])`: `launch_bounds` is a `U32` PARAMETER above, and
# this is where it would be computed. NEITHER HALF IS PORTED and the reason is
# the same on both sides: the fold (wall (a)) owns the uop list, and `d.vmax` is
# the SYMBOLIC maximum that is `TODO(p3) ops.py:1092 symbol=UOp.vmax`. The SPECIAL filter itself
# is one string test on the arg -- `arg[0]` of `("l", 0, "lidx0", "l")` is `"l"`
# -- so it is a `head_char` over an `AStr` once the arena is walkable, and the
# gate's `kern lb 1` rows are the no-local case it has to agree with.
#   TODO(p3) cstyle.py:162 symbol=render_kernel, :163 -- BLOCKED. needs `local_dims` (py:162) and `launch_bounds` (py:163) -- two kernel-shape helpers: MEASURED, both NO DEF under `cstyle.bend` (comments excluded). They are the last two `TODO` markers left in this file's wall list.
#
# ===========================================================================
# LANDED 2026-10-27. `_render` AND `render_kernel` ARE HERE. WHAT FOLLOWS IS
# THE PORT, AND THE TWO PARAGRAPHS THAT SAY WHAT IT IS.
#
# ===========================================================================
# WHAT `_render` DOES UPSTREAM -- `tinygrad/renderer/cstyle.py:208-266`.
#
#     def _render(self, uops:list[UOp]) -> tuple[str, list[str], list[tuple[str,tuple[UOp,bool]]]]:
#
# IT IS THE UOP LIST -> C BODY RENDERER. It takes the uop list and answers
# THREE THINGS: the kernel's NAME, the kernel BODY as a list of source LINES,
# and the BUFFER list -- the kernel's ARGUMENT LIST. It is ONE left-to-right
# walk (`for u in uops:`, :221) and per uop it does four things:
#
#   * it SKIPS the uops that render to nothing (:222-223): `NOOP`, `CONST`,
#     `CUSTOM_FUNCTION`, and an empty `STACK`;
#   * it ALIASES `AFTER` onto its first source (:224-227): `r[u] = r[u.src[0]]`;
#   * it NAMES the uop (:238-244): a `SPECIAL` names itself, a `RANGE` names
#     itself `f"{axis_letters[u.axis_type]}idx{range_str(u)}"`, and everything
#     else takes a PREFIX out of `{WMMA:"wmma", BUFFER:"buf", CAST:"cast",
#     BITCAST:"cast", STACK:"cast", INDEX:"bidx", LOAD:"val"}` and otherwise
#     `"alu"`, with a PER-PREFIX COUNTER, so the second ALU is `alu1`;
#   * and it RENDERS it with the `base_rewrite` matcher (:11-77), deciding
#     INLINE vs STATEMENT by a `child_count` HISTOGRAM (:212,
#     `Counter(v for ru in uops for v in ru.src)`): a uop used EXACTLY ONCE is
#     INLINED into its consumer, and a uop used TWICE OR MORE becomes a
#     STATEMENT `"{type} {name} = {text};"` at the current INDENT DEPTH
#     (:249-262). The depth is a counter: `IF` and `RANGE` push a level,
#     `ENDIF`/`END`/`BACKEDGE` pop one (:249, :262), and every emitted line is
#     prefixed with `"  "*depth` (:260).
#
# THE `r` MAP IS ONE MAP WITH TWO JOBS, and that is the load-bearing detail:
# `r[u]` is the NAME before the rewrite and the TEXT after it, but only in the
# INLINE case (:255). In the STATEMENT case `r[u]` STAYS THE NAME, so a later
# uop that reads `r[u]` reads `"alu0"`, not the text. The PORT's `r` IS A LIST
# INDEXED BY THE UOP'S POSITION, because the list is POST-ORDER (every uop's
# srcs sit at a lower index) -- which is the same property
# `.agents/slop/cpuseam/`'s oracle relies on.
#
# ===========================================================================
# WHAT `render_kernel` DOES UPSTREAM -- `tinygrad/renderer/cstyle.py:155-167`.
#
#     def render_kernel(self, function_name:str, kernel:list[str], bufs:list[tuple[str,tuple[UOp,bool]]], uops:list[UOp], prefix=None) -> str:
#
# IT IS THE KERNEL-BODY ASSEMBLER: it takes the three things `_render`
# answered and emits the C FUNCTION. It builds each buffer's TYPE from the
# device's `var_prefix`/`buffer_prefix`/`buffer_suffix` and `_render_dtype`
# (:159-161), computes `launch_bounds = prod([d.vmax for d in local_dims])`
# where the `local_dims` are the `SPECIAL`s with axis `"l"` (:162-163) -- and
# `prod(())` is 1, NOT 0 (:1338-1341) -- and writes
# `f"{kernel_typedef} {function_name}({', '.join(buf_types + extra_args)}) {{\n{tmp}\n{body}\n}}"`
# (:164-166), prefixing the whole thing with `prefix` when `prefix` is not
# `None` -- and `[]` is not `None`, so an EMPTY prefix list must NOT gain a
# leading newline (:167).
#
# AND `ClangRenderer` OVERRIDES IT (:312-314): the C it emits carries the
# VECTOR TYPEDEFS (`typedef float float2 __attribute__((aligned(4),
# ext_vector_type(2)));`) BEFORE the function, and they come from
# `_render_defines` (:308) -> `uops_to_dtypes` (:110-111) ->
# `render_vector_prefix` (:302-306). `uops_to_dtypes` KEEPS ITS LIST ORDER
# (`dedup` is `list(dict.fromkeys(x))`, helpers.py:23) and the ORDER IS THE
# GATE, because the typedefs come out in it.
#
# ===========================================================================
# WHAT THEY MUST DO HERE. THE SAME TWO FUNCTIONS, OVER THE PORT's OWN UOP
# REPRESENTATION. AND THE DERIVED FACTS TRAVEL WITH THE UOP, WHICH IS WHAT
# `BArg` ALREADY DOES FOR THE BUFFER ARGUMENTS (this file's :131-146: "they
# arrive as records the CALLER fills"). THE FOLD CANNOT SUPPLY THEM: wall
# (a) (this file's :49-54) says `F.fold.dt` answers `None` for `Ops.SHRINK`,
# `Ops.LOAD` and every ALU above one, so `render_type` cannot be run end to end
# on a REAL kernel, and the REAL kernels are what `render_kernel` is FOR.
#
# ⇒ THE SPELLINGS REUSED, BY NAME: `render_dtype` (:780), `render_type`
# (:828), `render_ptr` (:837), `render_access` (:841), `render_cast` (:844),
# `render_buffer` (:1013), `code_for_op.of` (:1206), `code_for_workitem.g`
# (:1241), `type_map.of` (:620), `kernel_typedef.of` (:346),
# `buffer_prefix.of` (:352), `buffer_suffix.of` (:383), `var_prefix.of` (:391),
# `var_suffix.of` (:396), `smem_prefix.of` (:364), `smem_align.of` (:375),
# `float4.of` (:445), `gep_arr_threshold.of` (:470), `infinity.of` (:405),
# `nan.of` (:410), `barrier.of` (:418), `H.strip_parens`.
# ===========================================================================
def ku_const_val(+kus: List<&2, KU>, i: U32) -> U32: ku_const_val.go(ku_const_int_at(kus, i))  # =========================================================================== # THE CONST-OF-A-CONST CAST -- cstyle.py:25-37. THE ARMS, IN ORDER:
#   1. a FLOAT dtype and a NON-FINITE value -> `(INFINITY)` / `(NAN)` / `(-INFINITY)`
#   2. f32 -> `{val}f`
#   3. i64 -> `{val}l`
#   4. u64 -> `{truncate}ul`
#   5. u32 -> `{truncate}u`
#   6. bool -> `1` / `0`
#   7. fp8/bf16/f16 -> `({render_cast(x, "{val}f")})`
#   8. u8/u16 -> `({render_cast(x, "{val}u")})`
#   9. i8/i16 -> `({render_cast(x, "{val}")})`
#  10. EVERYTHING ELSE -> `{val}`
# ARM 1 IS A `None` FOR A FINITE FLOAT, so arm 2 takes it, and arm 10 takes
# every INTEGER: THAT is why the port's `i32` const renders as `56` AND NOT
# `(int)(56)`, and it is the FIRST thing a port gets wrong.
#
# MEASURED 2026-10-27: THE FIVE UPSTREAM CPU KERNELS HAVE **NO FLOAT CONST AT
# ALL** (the census is over `.agents/slop/cpuseam/uops/*.rows`: 100 `const`
# rows, 0 with a `.` in the value), so the FLOAT ARMS ARE NOT EXERCISED BY
# THE ORACLE AND ARE NAMED AS A GAP RATHER THAN CLAIMED.
def ku_cast_wrapped(dev: U32, d: S.Dt, v: String) -> String:
  String.concat(["(", render_cast(dev, d, 1, S.Aalu{}, O.OpsCAST{}, False{}, v), ")"])

def ku_const_cast_int(+dt: S.Dt, +dev: U32, k: KU, +i: H.I64) -> String:
  match dt:
    case d:
      Bool.pick(String, O.eq_dt(d, S.int64()), String.concat([H.i64_dec(i), "l"]),
        Bool.pick(String, O.eq_dt(d, S.uint64()), String.concat([H.i64_dec(i), "ul"]),
          Bool.pick(String, O.eq_dt(d, S.uint32()), String.concat([H.i64_dec(i), "u"]),
            Bool.pick(String, O.eq_dt(d, S.boolean()), Bool.pick(String, H.i64_is_neg(i), "0", "1"),
              Bool.pick(String, O.eq_dt(d, S.uint8()), ku_cast_wrapped(dev, d, H.i64_dec(i)),
                Bool.pick(String, O.eq_dt(d, S.uint16()), ku_cast_wrapped(dev, d, H.i64_dec(i)),
                  Bool.pick(String, O.eq_dt(d, S.int8()), ku_cast_wrapped(dev, d, H.i64_dec(i)),
                    Bool.pick(String, O.eq_dt(d, S.int16()), ku_cast_wrapped(dev, d, H.i64_dec(i)),
                      H.i64_dec(i)))))))))

def ku_const_cast_f32(+dt: S.Dt, +dev: U32, k: KU, +f: F32) -> String:
  match dt:
    case d:
      Bool.pick(String, O.eq_dt(d, S.single()), String.concat([U.f32_repr(f), "f"]),
        Bool.pick(String, O.eq_dt(d, S.half()), ku_cast_wrapped(dev, d, String.concat([U.f32_repr(f), "f"])),
          Bool.pick(String, O.eq_dt(d, S.bfloat16()), ku_cast_wrapped(dev, d, String.concat([U.f32_repr(f), "f"])),
            ku_cast_wrapped(dev, d, U.f32_repr(f)))))

# THE GENERIC CAST: `f"({ctx.render_cast(x, ctx[x.src[0]])})"` (cstyle.py:40).
def ku_cast_generic(dev: U32, +k: KU, +r: List<&2, String>) -> String:
  String.concat(["(", render_cast(dev, KU.dtype(k), KU.numel(k), KU.addr(k), O.OpsCAST{}, False{}, rt(r, KU.src0(k))), ")"])

# ===========================================================================
# `render_index` -- cstyle.py:169-174. THE `KU`-WORLD TWIN OF THIS FILE'S
# `render_index` (:982), AND THE DIFFERENCE IS THE INPUT: the arena-bound one
# reads the INDEX's arg and its CONST index OUT OF AN `O.Arena`, and the `KU`
# LIST CARRIES BOTH. The TEXT is the same, arm for arm.
#
#     def render_index(self, x:UOp, buf:UOp, idx:UOp):
#       if buf.addrspace == AddrSpace.ALU:
#         if not (idx.op is Ops.CAST and idx.src[0].op is Ops.CONST): return f"({self[buf]})[{self[idx]}]"
#         return self[buf]+(f"[{idx.src[0].val}]" if buf.max_numel() > self.gep_arr_threshold else f".{'xyzwabcd'[idx.src[0].val]}")
#       return f"({self[buf]}+{strip_parens(self[idx]) if idx.arg == Ops.ADD else self[idx]})"
#
# THREE ARMS AND THE FIRST IS THE ONE THAT DECIDES `val1[0]`:
#   * the ALU arm with a CONST-cast index is `buf[idx]`, and `buf[idx]` NOT
#     `buf.x` ONLY because CLANG's `gep_arr_threshold` is 0 (cstyle.py:283) and
#     the buffer's element count is 2, so `2 > 0`;
#   * the ALU arm with any OTHER index is `(buf)[idx]`;
#   * the GLOBAL arm is `(buf+idx)`, and the index's parens are stripped ONLY
#     when the index's OWN arg is `Ops.ADD`.
# ===========================================================================
def ku_const_cast_flt.go(m: Maybe<&1, F32>, dev: U32, +k: KU, +r: List<&2, String>) -> String:
  match m:
    case Some{f}: ku_const_cast_f32(KU.dtype(k), dev, k, f)
    case None{}: ku_cast_generic(dev, k, r)

def ku_const_cast_flt(dev: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  ku_const_cast_flt.go(ku_const_float_at(kus, KU.src0(k)), dev, k, r)

def ku_const_cast2.go(m: Maybe<&1, H.I64>, dev: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  match m:
    case Some{i}: ku_const_cast_int(KU.dtype(k), dev, k, i)
    case None{}: ku_const_cast_flt(dev, k, kus, r)

def ku_const_cast2(dev: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  ku_const_cast2.go(ku_const_int_at(kus, KU.src0(k)), dev, k, kus, r)

def ku_const_cast(+dev: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  Bool.pick(String, ku_is_const_at(kus, KU.src0(k)),
    ku_const_cast2(dev, k, kus, r), ku_cast_generic(dev, k, r))

def ku_render_index.aluconst.go(m: Maybe<&2, KU>, dev: U32, +k: KU, +kus: List<&2, KU>,                                  +r: List<&2, String>) -> String:
  match m:
    case Some{b}:
      Bool.pick(String, U32.is_gt(KU.numel(b), gep_arr_threshold.of(dev)),
        String.concat([rt(r, KU.src0(k)), "[", U32.show(ku_const_val(kus, ku_src0_at(kus, KU.src1(k)))), "]"]),
        String.concat([rt(r, KU.src0(k)), ".", ku_swizzle(ku_const_val(kus, ku_src0_at(kus, KU.src1(k))))]))
    case None{}: ""

def ku_render_index.aluconst(dev: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  ku_render_index.aluconst.go(ku_at(kus, KU.src0(k)), dev, k, kus, r)

def ku_render_index.aluarm.go(m: Maybe<&2, KU>, dev: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  match m:
    case Some{b}:
      Bool.pick(String, ku_index_is_const_cast(kus, KU.src1(k)),
        ku_render_index.aluconst(dev, k, kus, r),
        String.concat(["(", rt(r, KU.src0(k)), ")[", rt(r, KU.src1(k)), ")"]))
    case None{}: ""
def ku_render_index.aluarm(dev: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  ku_render_index.aluarm.go(ku_at(kus, KU.src0(k)), dev, k, kus, r)

def ku_render_index(+dev: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  Bool.pick(String, is_alu_addr(KU.addr(k)), ku_render_index.aluarm(dev, k, kus, r),
    ku_render_index.global(dev, k, kus, r))

def ku_text_range(dev: U32, +i: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  Bool.pick(String, O.eq_dt(KU.dtype(k), S.void()), "for (;;) {",
    String.concat(["for (", render_dtype(dev, KU.dtype(k), 1, S.Aalu{}, True{}, False{}, False{}), " ",
      rt(r, i), " = 0; ", rt(r, i), " < ", rt(r, KU.src0(k)), "; ", rt(r, i), "++) {"]))

def ku_text_cast(+dev: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  Bool.pick(String, ku_is_const_at(kus, KU.src0(k)),
    ku_const_cast(dev, k, kus, r), ku_cast_generic(dev, k, r))

# `f"({ctx.render_access(bidx)})"` (cstyle.py:57) AND
# `f"({ctx[gate]}?{ctx.render_access(bidx)}:{ctx[var]})"` (cstyle.py:58-59).
def ku_ptr.go(m: Maybe<&2, KU>, dev: U32, +ai: U32, +b: KU, kus: List<&2, KU>, +r: List<&2, String>) -> String:
  match m:
    case Some{s}:
      Bool.pick(String, Bool.or(U32.is_gt(KU.numel(b), 1), Bool.not(O.eq_dt(KU.dtype(b), KU.dtype(s)))),
        String.concat(["((", render_dtype(dev, KU.dtype(b), KU.numel(b), KU.addr(b), True{}, True{}, False{}), ")(",
          rt(r, ai), "))"]),
        rt(r, ai))
    case None{}: ""
def ku_ptr(dev: U32, +ai: U32, +b: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  ku_ptr.go(ku_at(kus, KU.src0(b)), dev, ai, b, kus, r)
def ku_access.go(m: Maybe<&2, KU>, dev: U32, +ai: U32, k: KU, kus: List<&2, KU>, +r: List<&2, String>) -> String:
  match m:
    case Some{b}: String.concat(["*", ku_ptr(dev, ai, b, kus, r)])
    case None{}: "*"
def ku_access(dev: U32, +ai: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  ku_access.go(ku_at(kus, KU.src0(k)), dev, ai, k, kus, r)
def ku_text_load(+dev: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  Bool.pick(String, U32.is_eq(KU.nsrc(k), 3),
    String.concat(["(", rt(r, KU.src2(k)), "?", ku_access(dev, KU.src0(k), k, kus, r), ":", rt(r, KU.src1(k)), ")"]),
    String.concat(["(", ku_access(dev, KU.src0(k), k, kus, r), ")"]))
def ku_text_store(dev: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  String.concat([ku_access(dev, KU.src0(k), k, kus, r), " = ", rt(r, KU.src1(k)), ";"])
def ku_stack_srcs.go(+ss: List<&2, U32>, +kus: List<&2, KU>, +r: List<&2, String>,
                    acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case h <> t: ku_stack_srcs.go(t, kus, r, List.append(&2, String, acc, [rt(r, h)]))

def ku_stack_srcs(+k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> List<&2, String>:
  ku_stack_srcs.go(KU.srcs(k), kus, r, Nil{})

def ku_text_stack(+dev: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  String.concat([float4.of(dev), float4_open(dev),
    String.join(ku_stack_srcs(k, kus, r), ","), float4_close(dev)])

def ku_text.go(op: O.Op, dev: U32, i: U32, k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  match op:
    case O.OpsRANGE{}: ku_text_range(dev, i, k, kus, r)
    case O.OpsEND{}: "}"
    case O.OpsENDIF{}: "}"
    case O.OpsIF{}: ku_text_if(dev, k, kus, r)
    case O.OpsBACKEDGE{}: ku_text_backedge(dev, k, kus, r)
    case O.OpsCAST{}: ku_text_cast(dev, k, kus, r)
    case O.OpsBARRIER{}: barrier.of(dev)
    case O.OpsINDEX{}: ku_render_index(dev, k, kus, r)
    case O.OpsSHRINK{}: ku_render_index(dev, k, kus, r)
    case O.OpsLOAD{}: ku_text_load(dev, k, kus, r)
    case O.OpsSTORE{}: ku_text_store(dev, k, kus, r)
    case O.OpsBUFFER{}: ku_text_buffer(dev, i, k, r)
    case O.OpsWMMA{}: ku_text_wmma(dev, k, r)
    case O.OpsSTACK{}: ku_text_stack(dev, k, kus, r)
    case op2: ku_text_alu(dev, op2, k, kus, r)

# `for (;;) {` FOR A VOID RANGE AND `for ({dt} {name} = 0; {name} < {src0}; {name}++) {`
# OTHERWISE -- cstyle.py:17-19.
# `UPat(Ops.STACK, name="x")` -- cstyle.py:52-54:
#   `f"{ctx.float4.replace('float4', ctx.render_type(x))}" + f"{ctx.float4_style[0]}{','.join([ctx[y] for y in x.src])}{ctx.float4_style[1]}"`

# cstyle.py:47 -- `f"{ctx.code_for_workitem[x.arg[0]](x.arg[-1])}; /* {(x.src[0]).render()} */"`.
# IT IS A STATEMENT, not an expression: the workitem id, a `;`, and a comment holding the
# SPECIAL's SOURCE's rendered text (`/* 32 */`). `code_for_workitem.g` already answers the
# id and already refuses base/Clang, which is what CPython's empty dict does.
def ku_text_special(+dev: U32, +k: KU, +r: List<&2, String>) -> String:
  String.concat([code_for_workitem.g(dev, KUArg.special_axis(KU.arg(k)), KUArg.special_n(KU.arg(k))),
    "; /* ", rt(r, KU.src0(k)), " */"])

def ku_text(dev: U32, i: U32, +k: KU, +kus: List<&2, KU>, +r: List<&2, String>) -> String:
  ku_text.go(KU.op(k), dev, i, k, kus, r)

def cc_go.go(+kus: List<&2, KU>, cc: List<&2, U32>) -> List<&2, U32>:
  match kus:
    case Nil{}: cc
    case h <> t: cc_go.go(t, cc_one(h, cc))
def cc_go(kus: List<&2, KU>, cc: List<&2, U32>) -> List<&2, U32>:
  cc_go.go(kus, cc)

def child_count(+kus: List<&2, KU>) -> List<&2, U32>:
  cc_go(kus, List.replicate(U32, List.length(&2, KU, kus), 0))

# THE WRITABLE PARAMS -- cstyle.py:214-215:
#   `writable_params = {u for u in UOp.sink(*[u.src[0] for u in uops if u.op is Ops.STORE]).toposort(...) if u.op is Ops.PARAM}`
# I.E. THE PARAMS A STORE REACHES. THE PORT WALKS BACKWARD FROM EACH STORE'S
# BUFFER THROUGH THE INDEXING OPS, WHICH IS THE SAME SET.
def ku_is_writable(kus: List<&2, KU>, k: KU) -> Bool: False{}
def _render.param(dev: U32, +k: KU, +kus: List<&2, KU>, st: St) -> St:
  +nm = ku_param_name(k)
  st_bufs(st_put(st, nm), BArg{nm, KU.dtype(k), KU.addr(k), ku_is_writable(kus, k),
    KUArg.param_volatile(KU.arg(k)), False{}})

# `mutable` IS `u in writable_params` UPSTREAM (cstyle.py:214-215), AND
# `mutable` IS READ BY `_render_dtype` FOR AN **IMAGE** ONLY (cstyle.py:182:
# `if is_image_shape(shape): return f"{'write_only' if mutable else 'read_only'} image2d_t"`).
# NO CPU KERNEL IS AN IMAGE, SO THE FLAG IS NOT READ BY THE C THE PORT EMITS --
# AND THE PORT SAYS SO INSTEAD OF GUESSING A BACKWARD WALK.
def _render.decl(dev: U32, i: U32, +k: KU, kus: List<&2, KU>, cc: List<&2, U32>,
                 +st: St, +l: String, nm: String, ix: U32, +semi: Bool) -> St:
  +st0 = _render.pop(st, k)
  +st1 = st_kernel(st0, String.concat([ku_indent(St.depth(st0)), render_type(dev, KU.dtype(k),
    KU.numel(k), KU.addr(k), KU.op(k), False{}), " ", nm, " = ", l, Bool.pick(String, semi, ";", "")]))
  +st2 = st_c(st1, ix)
  _render.push(st2, k)
def _render.stmt(+dev: U32, +i: U32, +k: KU, +kus: List<&2, KU>, +cc: List<&2, U32>,                  +st: St, +l: String, +nm: String, +ix: U32, +semi: Bool) -> St:
  Bool.pick(St, ku_is_decl(k),
    _render.decl(dev, i, k, kus, cc, st, l, nm, ix, semi),
    _render.plain(dev, i, k, kus, cc, st, l, nm, ix))

# `if u.op not in {Ops.RANGE, Ops.BUFFER, Ops.BINARY} and u.dtype != dtypes.void:`
# -- cstyle.py:257. IT IS THE TEST FOR "IS THIS A DECLARATION", AND THE
# DECLARATION IS `"{type} {name} = {text};"`.
def _render.emit(dev: U32, +i: U32, +k: KU, +kus: List<&2, KU>, +cc: List<&2, U32>,                  +st: St, +l: String, nm: String, ix: U32, +semi: Bool) -> St:
  Bool.pick(St, ku_inline(KU.op(k), k, kus, cc, i),
    st_set(st, i, l),
    _render.stmt(dev, i, k, kus, cc, st, l, nm, ix, semi))

# THE STATEMENT -- cstyle.py:256-261.
def _render.range(+dev: U32, +i: U32, +k: KU, +kus: List<&2, KU>, cc: List<&2, U32>, st: St) -> St:
  +nm = ku_range_name(KU.arg(k))
  +st1 = st_put(st, nm)
  +l = ku_text(dev, i, k, kus, St.r(st1))
  _render.emit(dev, i, k, kus, cc, st1, l, nm, 255, True{})

# cstyle.py:239 -- `if u.op is Ops.SPECIAL: r[u] = u.arg`. THE NAME IS THE ARG, and
# it burns no prefix counter (cstyle.py:261 increments only on the prefix path), so
# `_render.decl` is called with `semi = False` and `st_c` is not reached.
def _render.special(+dev: U32, +i: U32, +k: KU, +kus: List<&2, KU>, cc: List<&2, U32>, +st: St) -> St:
  +nm = KUArg.special_nm(KU.arg(k))
  +st1 = st_put(st, nm)
  _render.decl(dev, i, k, kus, cc, st1, ku_text_special(dev, k, St.r(st1)), nm, 255, False{})

def _render.named(+dev: U32, +i: U32, +k: KU, +kus: List<&2, KU>, cc: List<&2, U32>, +st: St) -> St:
  +ix = ku_pfx_ix(KU.op(k))
  +nm = String.concat([ku_pfx(ix), U32.show(cc_at(St.c(st), ix))])
  +st1 = st_put(st, nm)
  +l = ku_text(dev, i, k, kus, St.r(st1))
  _render.emit(dev, i, k, kus, cc, st1, l, nm, ix, True{})
def _render.one.go(op: O.Op, dev: U32, i: U32, +k: KU, +kus: List<&2, KU>, +cc: List<&2, U32>, +st: St) -> St:
  match op:
    case O.OpsNOOP{}: st_put(st, "")
    case O.OpsCONST{}: st_put(st, "")
    case O.OpsCUSTOM_FUNCTION{}: st_put(st, "")
    case O.OpsSINK{}: st_put(st_name(st, KUArg.sink_name(KU.arg(k))), "")
    case O.OpsSTACK{}: Bool.pick(St, U32.is_eq(KU.nsrc(k), 0), st_put(st, ""),
      _render.named(dev, i, k, kus, cc, st))
    case O.OpsAFTER{}: st_put(st, rt(St.r(st), KU.src0(k)))
    case O.OpsPARAM{}: _render.param(dev, k, kus, st)
    case O.OpsRANGE{}: _render.range(dev, i, k, kus, cc, st)
    case O.OpsSPECIAL{}: _render.special(dev, i, k, kus, cc, st)
    case op2: _render.named(dev, i, k, kus, cc, st)

# THE PARAM -- cstyle.py:231-235. THE NAME IS
# `(arg.name or "data{slot}") + "_" + "_".join(shape)` AND THE PARAM BECOMES
# ONE OF THE KERNEL'S ARGUMENTS.
def _render.one(dev: U32, i: U32, +k: KU, +kus: List<&2, KU>, +cc: List<&2, U32>, st: St) -> St:
  _render.one.go(KU.op(k), dev, i, k, kus, cc, st)

def _render.go(+kus: List<&2, KU>, +all: List<&2, KU>, +dev: U32, +i: U32, +cc: List<&2, U32>, +st: St) -> St:
  match kus:
    case Nil{}: st
    case h <> t: _render.go(t, all, dev, U32.add(i, 1), cc, _render.one(dev, i, h, all, cc, st))
def _render(dev: U32, +kus: List<&2, KU>) -> St:
  _render.go(kus, kus, dev, 0, child_count(kus), St.of(Nil{}, Nil{}, Nil{},
    List.replicate(U32, 6n, 0), 1, "test"))
def uops_to_dtypes.go(+kus: List<&2, KU>, acc: List<&2, DtN>) -> List<&2, DtN>:
  match kus:
    case Nil{}: acc
    case h <> t: uops_to_dtypes.go(t, uops_to_dtypes.one(h, acc))
def uops_to_dtypes(kus: List<&2, KU>) -> List<&2, DtN>:
  uops_to_dtypes.go(kus, Nil{})
def render_vector_prefix(+dev: U32, cpu: Bool, +dt: S.Dt, +count: U32) -> String:
  String.concat(["typedef ", render_dtype(dev, dt, 1, S.Aalu{}, True{}, False{}, False{}), " ",
    render_dtype(dev, dt, count, S.AReg{}, True{}, False{}, False{}),
    " __attribute__((aligned(", U32.show(ku_align(cpu, dt)), "),ext_vector_type(", U32.show(count), ")));"])

def _render_defines.go(+xs: List<&2, DtN>, +dev: U32, +cpu: Bool, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t:
      Bool.pick(List<&2, String>, U32.is_gt(DtN.n(h), 1),
        _render_defines.go(t, dev, cpu, List.append(&2, String, acc,
          [render_vector_prefix(dev, cpu, DtN.dt(h), DtN.n(h))])),
        _render_defines.go(t, dev, cpu, acc))

# ===========================================================================
# `render_kernel` -- cstyle.py:155-167 (THE BODY) AND cstyle.py:312-314 (THE
# CLANG OVERRIDE). TWO FUNCTIONS, BECAUSE UPSTREAM HAS TWO.
#
# THE BODY: the buffer TYPES, the function SIGNATURE, and the braces.
# THE CLANG OVERRIDE: the VECTOR TYPEDEFS BEFORE IT AND THE ENTRY AFTER IT.
# ===========================================================================
def _render_defines(dev: U32, cpu: Bool, +kus: List<&2, KU>) -> List<&2, String>:
  _render_defines.go(uops_to_dtypes(kus), dev, cpu, Nil{})

def ku_buftype(+dev: U32, +b: BArg) -> String:
  String.concat([Bool.pick(String, BArg.volatile_(b), "volatile ", ""),
    Bool.pick(String, is_alu_addr(BArg.addr(b)), var_prefix.of(dev), ""),
    render_dtype(dev, BArg.dtype(b), 1, BArg.addr(b), BArg.mutable(b), False{}, BArg.image(b)),
    Bool.pick(String, is_alu_addr(BArg.addr(b)), var_suffix.of(dev), buffer_suffix.of(dev))])

def ku_args.go(+bs: List<&2, BArg>, +dev: U32, +acc: List<&2, String>) -> List<&2, String>:
  match bs:
    case Nil{}: acc
    case h <> t: ku_args.go(t, dev, List.append(&2, String, acc,
      [String.concat([ku_buftype(dev, h), " ", BArg.name(h)])]))

# THE BODY -- cstyle.py:155-167.
def ku_args(dev: U32, +bufs: List<&2, BArg>) -> List<&2, String>:
  ku_args.go(bufs, dev, Nil{})

def render_kernel_body(+dev: U32, +fn: String, +kernel: List<&2, String>,
                       +args: List<&2, String>, +lb: U32) -> String:
  String.concat([kernel_typedef(dev, lb), " ", fn, "(", String.join(args, ", "), ") {\n",
    String.join(kernel, "\n"), "\n}"])

# ===========================================================================
# METAL'S KERNEL SIGNATURE -- cstyle.py:366-372 AND :390-403. Metal is the one
# device whose buffers do NOT become parameters: `MetalRenderer.render_kernel`
# prepends the stdlib preamble, appends one `__WMMA_<name>` helper per WMMA op,
# builds `struct args_t { <type> <name>; ... }` from the buffer list, and calls
# upstream's base `render_kernel` with `bufs = []` and the UNPACKING LINE in
# front of the body, so the signature is `extra_args` alone:
#
#     kernel void r(constant args_t& args [[buffer(0)]],
#                   uint3 gid [[threadgroup_position_in_grid]],
#                   uint3 lid [[thread_position_in_threadgroup]]) {
#       device float* data0_1024 = args.data0_1024; ...
#
# ⇒ AND NOTHING DOWNSTREAM OF THE SIGNATURE CAN MATCH UNTIL THIS DOES, which is
# why it is ported before the WMMA helper: every line after it is indented text
# that differs only by what the signature put there.
# ===========================================================================
def metal_extra_args() -> List<&2, String>:
  ["constant args_t& args [[buffer(0)]]", "uint3 gid [[threadgroup_position_in_grid]]",
   "uint3 lid [[thread_position_in_threadgroup]]"]

def metal_fields(+bs: List<&2, BArg>, acc: List<&2, String>) -> List<&2, String>:
  match bs:
    case Nil{}: acc
    case h <> t: metal_fields(t, List.append(&2, String, acc,
      [String.concat([ku_buftype(3, h), " ", BArg.name(h), ";"])]))

def metal_args(+bs: List<&2, BArg>) -> List<&2, String>:
  match bs:
    case Nil{}: Nil{}
    case h <> t: String.concat([ku_buftype(3, h), " ", BArg.name(h), " = args.", BArg.name(h), ";"]) <> metal_args(t)

# `"  " + " ".join(f"{t} {n} = args.{n};" for n, t in args)`, prepended to the body
def metal_unpack(+bs: List<&2, BArg>) -> String:
  String.concat(["  ", String.join(metal_args(bs), " ")])

def metal_prefix(+bs: List<&2, BArg>) -> List<&2, String>:
  List.append(&2, String,
    ["#include <metal_stdlib>", "using namespace metal;"],
    [String.concat(["struct args_t { ", String.join(metal_fields(bs, Nil{}), " "), " };"])])

# cstyle.py:312-314 IS THE CLANG OVERRIDE: it emits the vector typedefs. METAL DOES
# NOT -- `MetalRenderer.render_kernel` calls the BASE, which has no `_render_defines`
# at all, which is why upstream's Metal text has native `float2` and no `typedef`.
def render_kernel(+dev: U32, cpu: Bool, +fn: String, +kernel: List<&2, String>,
                  +bufs: List<&2, BArg>, +kus: List<&2, KU>, +lb: U32) -> String:
  Bool.pick(String, U32.is_eq(dev, 3),
    String.concat([String.join(metal_prefix(bufs), "\n"), "\n",
      render_kernel_body(3, fn, metal_unpack(bufs) <> kernel, metal_extra_args(), lb)]),
    String.concat([String.join(_render_defines(dev, cpu, kus), "\n"), "\n",
      render_kernel_body(dev, fn, kernel, ku_args(dev, bufs), lb)]))

# THE WHOLE KERNEL, FROM THE UOP LIST -- cstyle.py:268-278's `render`, FOR THE
# ONE-LINE CASE (NO LINEAR BODIES, NO EXTERN DECLARATIONS).
def render(+dev: U32, cpu: Bool, +kus: List<&2, KU>) -> String:
  +st = _render(dev, kus)
  render_kernel(dev, cpu, St.name(st), St.kernel(st), St.bufs(st), kus, 1)

# THE NAME/TEXT MAP, EXPOSED -- the walk's `r`, so a harness can read one slot.

# THE NAME/TEXT MAP, EXPOSED -- the walk's `r`, so a harness can read one slot.
def render_r(dev: U32, kus: List<&2, KU>) -> List<&2, String>:
  St.r(_render(dev, kus))

