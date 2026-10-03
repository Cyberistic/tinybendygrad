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
#   (a) `Ops.SHRINK` HAS NO DTYPE IN THE FOLD. `fold.bend:1631` defers it with
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
#       SYMBOLIC `vmax` (`TODO(p3) ops.py:1886`). `max_numel` below is the
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
def BArg.name(b: BArg) -> String:
  match b:
    case BArg{name, dtype, addr, mutable, volatile_, image}: name

def BArg.dtype(b: BArg) -> S.Dt:
  match b:
    case BArg{name, dtype, addr, mutable, volatile_, image}: dtype

def BArg.addr(b: BArg) -> S.Addr:
  match b:
    case BArg{name, dtype, addr, mutable, volatile_, image}: addr

def BArg.mutable(b: BArg) -> Bool:
  match b:
    case BArg{name, dtype, addr, mutable, volatile_, image}: mutable

def BArg.volatile_(b: BArg) -> Bool:
  match b:
    case BArg{name, dtype, addr, mutable, volatile_, image}: volatile_

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
type Uses is Data:
  Uses{half: Bool, bf16: Bool, fp8: Bool, nonfinite: Bool, special: Bool, half_any: Bool}

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
# `prefix=[]` and `prefix=None` are different kernels (cstyle.py:166) and a
# `List` cannot tell them apart. `vecs`, `ockl` and `ocml` are the uop-derived
# lines Python appends to `prefix`; see the `TODO(p3)` at the foot for which of
# them this port produces and which it names.
#
# `cdna4` IS NOT A FIELD, and that is worth saying because it is the one value
# HIP reads that the caller already has: `is_cdna4(self.target.arch)` is a
# property of the TARGET, not of the uop list, so it travels as the `cdna4`
# ARGUMENT of `render_kernel` and stops there. Putting it in the record as well
# would be two spellings of one fact and the gate would only see one of them.
type Emit_ is Data:
  Emit_{uses: Uses, vecs: List<&2, String>, ockl: List<&2, String>, ocml: List<&2, String>,
       caller: List<&2, String>, has_prefix: Bool}

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
# win32 (cstyle.py:297-299, a `sys.platform` branch); the port does not take the
# win32 branch and that is the `TODO(p3)` at the foot.
# ===========================================================================

# `kernel_typedef` -- cstyle.py:125, :285, :324, :363, :425, :530 -- IS A
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

# `buffer_prefix` -- cstyle.py:126, :325, :364. EMPTY on the base, on Clang and
# on both GPU vendors, and that is why a CUDA kernel argument is a plain `float*`.
def buffer_prefix.of(+dev: U32) -> String:
  match dev:
    case 2: "__global "
    case 3: "device "
    case _: ""

# `smem_prefix` -- cstyle.py:129, :327, :365, :426, :534. HIP'S SPELLING HAS NO
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

# `smem_align` -- cstyle.py:128, :326. Only OpenCL sets it and only
# `render_buffer` reads it, which is why a base device's local buffer and an
# OpenCL one differ by exactly this prefix.
def smem_align.of(+dev: U32) -> String:
  match dev:
    case 2: "__attribute__ ((aligned (16))) "
    case _: ""

# `buffer_suffix` -- cstyle.py:127, :286. Clang's `restrict` is the ONLY
# non-empty one, and it is the whole difference between a Clang kernel argument
# `float* restrict data0_4` and an OpenCL one, `__global float* data0_4`.
def buffer_suffix.of(+dev: U32) -> String:
  match dev:
    case 1: " restrict"
    case _: ""

# `var_prefix` / `var_suffix` -- cstyle.py:131-132, :366-367. METAL'S PAIR IS THE
# INTERESTING ONE: `constant ` and `&`, so a Metal ALU value is
# `constant float& alu0 = ...` where every other device says `const float alu0`.
def var_prefix.of(+dev: U32) -> String:
  match dev:
    case 3: "constant "
    case _: "const "

def var_suffix.of(+dev: U32) -> String:
  match dev:
    case 3: "&"
    case _: ""

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
def barrier.of(+dev: U32) -> String:
  match dev:
    case 1: "__atomic_thread_fence(__ATOMIC_SEQ_CST);"
    case 2: "barrier(CLK_LOCAL_MEM_FENCE);"
    case 3: "threadgroup_barrier(mem_flags::mem_threadgroup);"
    case 4: "__syncthreads();"
    case 5: "__builtin_amdgcn_fence(__ATOMIC_RELEASE, \"workgroup\");__builtin_amdgcn_s_barrier();__builtin_amdgcn_fence(__ATOMIC_ACQUIRE, \"workgroup\");"
    case _: ""

# `float4` -- cstyle.py:136, :276, :329, :369, :429, :538. THE BASE IS `None`,
# AND `""` IS NOT `None`: the `Ops.STACK` rule (cstyle.py:56) does
# `self.float4.replace('float4', render_type(x))`, so `None` there is an
# `AttributeError` and `""` would emit a bare `float4{...}` with no constructor.
# `float4` answers `""` for the base AND THE STACK ARM IS NOT PORTED, which is
# the whole cost of that answer -- so it is written down here rather than papered
# over with a `has_float4` Bool that nothing reads.
#   TODO(p3) cstyle.py:55-56  `base_rewrite`'s `Ops.STACK` arm. It needs
#   `float4` to be `None`-distinguishable, which is the one place a `Data` cannot
#   carry the answer and a device TAG cannot either: the base is the only `None`
#   and the tag already says it. Unblocked when the arena rewrite lands.
def float4.of(+dev: U32) -> String:
  match dev:
    case 1: "(float4)"
    case 2: "(float4)"
    case 3: "float4"
    case 4: "make_float4"
    case 5: "make_float4"
    case _: ""

# `float4_style` -- cstyle.py:137, :277. Clang's is the ONLY pair that is not
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

# `gep_arr_threshold` -- cstyle.py:138, :278, :430. Clang's is 0, CUDA's is 8 and
# every other device's is 4, and it is the cut between `buf[i]` and `buf.x` in
# `render_index` -- see there for why 0 is not "never".
def gep_arr_threshold.of(+dev: U32) -> U32:
  match dev:
    case 1: 0
    case 4: 8
    case _: 4

# ===========================================================================
# `type_map: dict[DType, str]` -- cstyle.py:139, :287, :331, :373, :439, :539.
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
type Kv is Data:
  Kv{k: String, v: String, t: Kv}
  KvEnd{}

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
def type_map.cuda() -> Map<&2, String>:
  type_map_over(Kv{"u32", "uint", Kv{"bf16", "nv_bfloat16",
    Kv{"fp8e4m3", "__nv_fp8_e4m3", Kv{"fp8e5m2", "__nv_fp8_e5m2", KvEnd{}}}})

# cstyle.py:542. `{bfloat16: "hip_bfloat16", **{d: ("hip_fp8","hip_bf8")[fp8_index(d)] for d in fp8s}}`
# -- and `fp8_index(d) = fp8s.index(d) % 2` with `fp8s` in dtype.py's order
# (e4m3, e5m2, e4m3fnuz, e5m2fnuz), so the OCP pair and the FNUZ pair are THE
# SAME pair. That is measured: HIP maps both e4m3 variants to `hip_fp8` and both
# e5m2 variants to `hip_bf8`, and the duplication is upstream's rather than a
# port artefact. FIVE entries, then.
def type_map.hip() -> Map<&2, String>:
  type_map_over(Kv{"bf16", "hip_bfloat16", Kv{"fp8e4m3", "hip_fp8", Kv{"fp8e5m2", "hip_bf8",
    Kv{"fp8e4m3fnuz", "hip_fp8", Kv{"fp8e5m2fnuz", "hip_bf8", KvEnd{}}}}}})

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
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(1))
