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
    Kv{"f64", "double", Kv{"void", "void", KvEnd{}}}}}}}}}}}}}})

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

def is_index(op: O.Op) -> Bool:
  match op:
    case O.OpsINDEX{}: True{}
    case _: False{}

def is_reg(+a: S.Addr) -> Bool:
  match a:
    case S.AReg{}: True{}
    case _: False{}

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

# `idx.arg == Ops.ADD` -- and the arena's `Arg` is CLOSED, so this is a two-arm
# match. A RANGE's arg is `ARange` and is therefore the `_`; the `AReduce` arm is
# the REDUCE node whose reduce op is ADD with zero axes, which is the shape
# `UOp.reduce` sugar builds and the only way an index node's arg is an op.
def idx_arg_is_add(+a: O.Arg) -> Bool:
  match a:
    case O.AReduce{rop, num_axes}: Bool.and(is_add(rop), U32.is_zero(num_axes))
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
# `KeyError`, and the `_` arm answers `""` here. MEASURED BY THE GATE: with an
# `FDIV` arm in the base, the mutation "delete Clang's explicit FDIV arm" moved NO
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
    case _: ""

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
# `""` is its answer -- a `KeyError` in Python, an empty string here, and the
# difference is a visible gate row rather than a crash.
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
    case O.OpsEXP2{}: ""
    case O.OpsSIN{}: ""
    case O.OpsLOG2{}: ""
    case O.OpsRECIPROCAL{}: ""
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
# `code_for_workitem` -- cstyle.py:134, :330, :370, :431, :531. Five devices
# spell the workitem id and the BASE has an EMPTY dict, so a SPECIAL on the base
# CStyleLanguage is a `KeyError` in Python. `""` is the port's marker and it is
# NOT reachable for a real kernel: every GPU renderer defines both entries.
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

def code_for_workitem.g(+dev: U32, +k: String, n: U32) -> String:
  match dev:
    case 2: String.concat([Bool.pick(String, String.eq(k, "g"), "get_group_id(", "get_local_id("), U32.show(n), ")"])
    case 3: String.concat([Bool.pick(String, String.eq(k, "g"), "gid.", "lid."), witem_xyz(n)])
    case 4: String.concat([Bool.pick(String, String.eq(k, "g"), "blockIdx.", "threadIdx."), witem_xyz(n)])
    case 5: String.concat([Bool.pick(String, String.eq(k, "g"), "__ockl_get_group_id(", "__ockl_get_local_id("), U32.show(n), ")"])
    case _: ""

# ===========================================================================
# `_wmma_name` -- cstyle.py:115-117, and the one place a NAME is built from a
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
#   TODO(p3) cstyle.py:112-113  `uops_to_dtypes`. Needs the fold (wall (a)); its
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
#     `TODO(p3) ops.py:1886` wall again. It is a `U32` PARAMETER here, and the
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
# the SYMBOLIC maximum that is `TODO(p3) ops.py:1886`. The SPECIAL filter itself
# is one string test on the arg -- `arg[0]` of `("l", 0, "lidx0", "l")` is `"l"`
# -- so it is a `head_char` over an `AStr` once the arena is walkable, and the
# gate's `kern lb=1` rows are the no-local case it has to agree with.
#   TODO(p3) cstyle.py:157, :160  `local_dims` and `launch_bounds`.

# `case p <> t` on a `String` gives the first CHARACTER (measured, render.bend
# rule 12) and that is exactly `arg[0]`.

# THE SIGNATURE. `f'{t} {name}'` for each buffer, then `extra_args`, joined with
# ", ". `args` is the ALREADY-FORMATTED `t name` list, so `render_kernel` does the
# formatting and this def only joins -- which is what makes the two halves
# separately gateable.
#
# `extra_args` -- cstyle.py:372, and ONLY Metal sets it. Three lines appended to
# the SAME `", ".join` as the buffer types, which is why a Metal kernel signature
# carries `constant args_t& args [[buffer(0)]]` between the buffers and the two
# `uint3` position attributes.
def extra_args.dev(dev: U32) -> List<&2, String>:
  match dev:
    case 3: ["constant args_t& args [[buffer(0)]]", "uint3 gid [[threadgroup_position_in_grid]]", "uint3 lid [[thread_position_in_threadgroup]]"]
    case _: Nil{}

# `f'{t} {name}'` for one buffer -- cstyle.py:158-160, the `buftypes` element.
# `volatile_` rides in FRONT when the ParamArg says so and `var_prefix` /
# `var_suffix` REPLACE `buffer_suffix` for an ALU buffer, which is a different
# condition and not an addition.
#
# THE LITERAL IS `"volatile "` AND NOT `"volatile_ "` -- the FIELD is spelled
# `volatile_` because `volatile` is a RESERVED WORD (bend2-constraints rule 25),
# but the EMITTED C is upstream's `volatile` with a space, and the escape is on
# the Bend name only. MEASURED: the `buf3 volatile` row, which is the only row
# with a volatile buffer; a reader that echoed the field name emits an identifier
# no C compiler accepts.
def bt_prefix.of(volatile_: Bool, varp: String, +is_alu: Bool) -> String:
  String.concat([Bool.pick(String, volatile_, "volatile ", ""), Bool.pick(String, is_alu, varp, "")])

def bt_suffix.of(+is_alu: Bool, vars: String, bufs: String) -> String:
  Bool.pick(String, is_alu, vars, bufs)

# `u.addrspace == AddrSpace.ALU` -- AND IT IS `is_alu_addr` AGAIN, not a second
# spelling. Two defs matching `S.Aalu{}` would be two places for the ALU test to
# drift, and `render_index` already needs it.
def buftype(+dev: U32, +b: BArg) -> String:
  String.concat([bt_prefix.of(BArg.volatile_(b), var_prefix.of(dev), is_alu_addr(BArg.addr(b))),
    render_dtype(dev, BArg.dtype(b), 1, BArg.addr(b), BArg.mutable(b), False{}, BArg.image(b)),
    bt_suffix.of(is_alu_addr(BArg.addr(b)), var_suffix.of(dev), buffer_suffix.of(dev)), " ", BArg.name(b)])

def buftypes.go(+dev: U32, bs: List<&2, BArg>, acc: List<&2, String>) -> List<&2, String>:
  match bs:
    case Nil{}: acc
    case h <> t: buftypes.go(dev, t, List.append(&2, String, acc, [buftype(dev, h)]))

def buftypes(+dev: U32, +bs: List<&2, BArg>) -> List<&2, String>: buftypes.go(dev, bs, Nil{})

# ===========================================================================
# THE SIX `render_kernel` OVERRIDES. cstyle.py:310 (Clang), :348 (OpenCL), :390
# (Metal), :454 (CUDA), :555 (HIP); the base has none. Every one of them builds a
# `prefix` LIST and then calls `super().render_kernel` -- except Clang, which
# builds a `defines` string and a trailing newline instead. Four things are
# load-bearing about that and all four are gate rows, because the failure mode is
# a kernel that COMPILES:
#
#   * `prefix=[]` IS NOT `prefix=None`. cstyle.py:166 is `prg if prefix is None
#     else "\n".join(prefix)+f"\n{prg}"`, so an empty list puts a LEADING NEWLINE
#     in the output. CUDA and HIP hit this on EVERY kernel: their overrides
#     ASSIGN a prefix, and the assignment is `prefix = [...]` or `prefix, ockl =
#     [], []` -- never `None`. MEASURED, `kern2 HIP` begins with a newline and
#     `kern2 OPENCL` does not.
#   * THREE OF THE SIX DISCARD THE CALLER'S PREFIX. CUDA, HIP and Metal all
#     assign `prefix` before calling super, so a `#pragma` the caller passed in
#     is dropped. MEASURED, `render_kernel(..., prefix=[two lines])` on CUDA and
#     HIP returns BYTE-IDENTICAL output to `prefix=None`.
#   * OPENCL IS THE ONE THAT PREPENDS, and it prepends onto the CALLER's list,
#     not onto its own: `["#pragma ..."] + (prefix or [])` (cstyle.py:349).
#   * CLANG IS NOT A PREFIX AT ALL. cstyle.py:310-312 is
#     `defines + "\n" + body + "\n" + entry`, so Clang is the ONLY renderer whose
#     output gains BOTH a leading and a trailing newline, and `_render_entry` is
#     `""` on every path (cstyle.py:308) so the trailing one is unconditional.
#
# THE FIRST VERSION OF THIS FILE GOT ALL FOUR WRONG for Clang, HIP and Metal and
# every gate row passed anyway, because those rows were the only ones whose text
# spanned more than one line and a row-keyed diff cannot see a row it does not
# parse. `esc_row` below is the fix and the reason a row is one line is written
# down at its definition.
# ===========================================================================

# `prefix += xs` (cstyle.py:459-463, :567-579). Named because four of the five
# overrides are `prefix = a` then `prefix += b`, and a reader that wrote `a + b`
# as a STRING concatenation would join with the wrong separator.
def add(a: List<&2, String>, b: List<&2, String>) -> List<&2, String>: List.append(&2, String, a, b)

# `prefix.append(x) if <test>` -- the shape of nine of the eleven `if`s in the
# two vendor overrides. `inc_if` is the whole conditional-append idiom.
def inc_if(on: Bool, s: String) -> List<&2, String>: Bool.pick(List<&2, String>, on, [s], Nil{})

# CUDA's four unconditional lines (cstyle.py:456-457). `tg_bitcast` is one line
# in the source and one line in the output, which is why it is a single string
# here rather than a def: nothing in it varies with the device or the kernel.
def cuda_static() -> List<&2, String>:
  ["typedef unsigned int uint;", "#define INFINITY (__int_as_float(0x7f800000))",
   "#define NAN (__int_as_float(0x7fffffff))",
   "template <class T, class F> __device__ __forceinline__ T tg_bitcast(F v) { union U { F f; T t; }; U u; u.f = v; return u.t; }"]

# HIP's `ockl` -- cstyle.py:563. Three externs in declaration order, and the
# order is the order `code_for_workitem` reads them back (`__ockl_get_local_id`
# is the `l` form and `__ockl_get_group_id` the `g` one).
def ockl_extern(nm: String) -> String:
  String.concat(["extern \"C\" __attribute__((device, const)) size_t __ockl_get_", nm, "(unsigned int);"])

def hip_ockl() -> List<&2, String>: [ockl_extern("local_id"), ockl_extern("group_id"), ockl_extern("local_size")]

# HIP's `ocml` extern (cstyle.py:564-566, :578). `ocml_ops[op]` is a PAIR --
# (`"sqrt"`, `"const"`) -- and the second element's EMPTY case is the one that
# matters, because SIN and TRUNC are the only two rows that produce
# `__attribute__((device))` with no comma in it. The width is `ocml_bits`, the
# same def `code_for_op` reads, so the f16/f32/f64 spelling is computed once.
#
# `ocml_ops`' first element is the C NAME (`sqrt`), not `Ops.SQRT.name` (`SQRT`),
# and it is its OWN def rather than a table lookup inside `ocml_extern` so that
# `code_for_op`'s five HIP arms and the extern cannot disagree: `SQRT` -> `sqrt`
# and `""` -> `""` is the identity that makes both work. It is declared ABOVE
# `ocml_extern` because a def may only call defs above it, which is the whole
# mechanical cost of not having first-class functions.
def op_of_cname(op: String) -> String:
  match op:
    case "SQRT": "sqrt"
    case "TRUNC": "trunc"
    case "SIN": "sin"
    case "LOG2": "log2"
    case "EXP2": "exp2"
    case _: ""

def ocml_atr.of(op: String) -> String:
  match op:
    case "SQRT": "const"
    case "EXP2": "pure"
    case "LOG2": "pure"
    case _: ""

# `f'extern "C" __attribute__((device{f", {atr}" if atr else ""})) {dto} {meth}({dti});'`
# -- cstyle.py:578. THE COMMA IS PART OF THE ATTRIBUTE AND NOT OF THE SPELLING,
# so the `""` case is `__attribute__((device))` with NO trailing space: a reader
# that writes `"(device, "` unconditionally emits `__attribute__((device, ))` on
# SIN and TRUNC, which HIP accepts and no other compiler does, and the `hipocml`
# row is the only thing that can see it.
def ocml_extern(+op: String, +d: S.Dt) -> String:
  String.concat(["extern \"C\" __attribute__((device", Bool.pick(String, String.eq(ocml_atr.of(op), ""), "", ", "), ocml_atr.of(op), ")) ", dt_name(d), " ",
    ocml_name(op_of_cname(op), d), "(", dt_name(d), ");"])

# THE ORDER OF THE PREFIX IS DATA. CUDA emits five clauses and HIP eight, in the
# order `prefix +=` fixes, and the emitted order IS the call order -- "fp8 before
# fp16 before bf16" and "size_t before hip_bfloat16 before half" are facts about
# the generated header and not about formatting. A fold over an integer index is
# the shortest expression of that: the order becomes a RANGE, so reordering the
# clauses means changing which number each clause sits at, which is visible.
def prefix_clauses.of(+dev: U32) -> U32:
  match dev:
    case 4: 5
    case 5: 8
    case _: 0

def prefix_clause.of(+dev: U32, +u: Uses, +vecs: List<&2, String>, +ockl: List<&2, String>, +ocml: List<&2, String>, cdna4: Bool, k: U32) -> List<&2, String>:
  match dev:
    case 4:
      match k:
        case 0: cuda_static()
        case 1: inc_if(Uses.fp8(u), "#include <cuda_fp8.h>")
        case 2: inc_if(Uses.half(u), "#include <cuda_fp16.h>")
        case 3: inc_if(Uses.bf16(u), "#include <cuda_bf16.h>")
        case _: vecs
    case 5:
      match k:
        case 0: inc_if(Uses.nonfinite(u), "#define INFINITY (__builtin_inff())")
        case 1: inc_if(Uses.nonfinite(u), "#define NAN (__builtin_nanf(\"\"))")
        case 2: inc_if(Uses.special(u), "typedef long unsigned int size_t;")
        case 3: inc_if(Uses.bf16(u), String.concat(["typedef ", Bool.pick(String, cdna4, "__bf16", "unsigned short"), " hip_bfloat16;"]))
        case 4: inc_if(Uses.half(u), "#define half _Float16")
        case 5: add(inc_if(Uses.fp8(u), "typedef unsigned char hip_bf8;"), inc_if(Uses.fp8(u), "typedef unsigned char hip_fp8;"))
        case 6: add(Bool.pick(List<&2, String>, Uses.special(u), ockl, Nil{}), ocml)
        case _: vecs
    case _: Nil{}

# ONE SELF-RECURSIVE DEF WITH A COUNTDOWN, AND THE PREVIOUS TWO-DEF SHAPE IS
# WHY. The obvious `go`/`at` pair -- `go` computes `same = k == count` and calls
# `at`, `at` matches on it and calls `go` -- is MUTUAL RECURSION, which Bend
# refuses, and the error only appears once the ordering is fixed ("expected : a
# filled definition"). Introducing the `same` PARAMETER was necessary (a `match`
# may not scrutinise `U32.is_eq(k, ...)`) and it is not sufficient: convention 9
# says the self-call must live in the def that owns the `match`, so the match and
# the call collapse into one def and the countdown IS the match.
#
# THE COUNTDOWN IS THE REMAINING CLAUSE COUNT, NOT `k`, and that is the whole
# shape: `k` only GROWS and the decrease checker wants the first argument to be a
# strict subterm, so `rem` is first, is a `Nat`, and hands down `m`. `rem == 0` is
# the base and the port's other devices' `_` arm -- a base with no prefix is an
# EMPTY list, not the base's empty string.
#
# `k` IS `+` FOR THE OBVIOUS REASON AND IT IS NOT AFFECTED BY THE `rem` DEGREE
# CHECK: the `+` is on the SEVENTH argument and the decrease is the FIRST one.
def dev_prefix.go(rem: Nat, +dev: U32, +u: Uses, +vecs: List<&2, String>, +ockl: List<&2, String>,
  +ocml: List<&2, String>, +cdna4: Bool, +k: U32, acc: List<&2, String>) -> List<&2, String>:
  match rem:
    case 0n: acc
    case 1n+m: dev_prefix.go(m, dev, u, vecs, ockl, ocml, cdna4, U32.add(k, 1),
      add(acc, prefix_clause.of(dev, u, vecs, ockl, ocml, cdna4, k)))

def dev_prefix(+dev: U32, +u: Uses, +vecs: List<&2, String>, +ockl: List<&2, String>, +ocml: List<&2, String>, cdna4: Bool) -> List<&2, String>:
  dev_prefix.go(U32.to_nat(prefix_clauses.of(dev)), dev, u, vecs, ockl, ocml, cdna4, 0, Nil{})

# OPENCL'S ONE PREFIX -- cstyle.py:349. It PREPENDS onto the caller's list, which
# is the only place in the six where the caller's lines survive alongside the
# device's, and it is conditional on a half dtype being USED (an ALU uop of that
# dtype, not a buffer of it -- `uops_to_dtypes` filters to `AddrSpace.ALU`).
def opencl_prefix(+u: Uses) -> List<&2, String>: inc_if(Uses.half(u), "#pragma OPENCL EXTENSION cl_khr_fp16 : enable")

# METAL'S `args_t` INDIRECTION -- cstyle.py:400-403. Metal passes `bufs=[]` to
# `super()` and prepends ONE line that unpacks the struct, so a Metal kernel
# carries the buffer NAMES in its body and not in its signature, and the
# signature has the three `extra_args` alone.
#
# ONE WALK AND ONE ELEMENT BECAUSE THE ELEMENT IS READ TWICE WITH ONE DIFFERENCE.
# Python builds `args` once (cstyle.py:401) and reads it twice:
#
#     "struct args_t { " + " ".join(f"{t} {n};" for n, t in args) + " };"
#     ["  " + " ".join(f"{t} {n} = args.{n};" for n, t in args)] + kernel
#
# The difference is a MIDDLE, not a suffix: the body spelling repeats the buffer
# NAME (`data0_4 = args.data0_4`) and so has TWO names where the struct has ONE,
# and the `;` is inside the element in BOTH readings. So `mid` is `""` for the
# struct and `" = args."` for the body, and the SECOND name rides `mid`'s
# non-emptiness -- which is the whole test. The first version emitted the name
# unconditionally and produced `struct args_t { device float* data0_4data0_4; }`,
# and a version that put the `;` after the JOIN produced
# `device float* data0_4 = args. device float* data1_4 = args.;`.
def metal_field.of(+dev: U32, +b: BArg, +mid: String) -> String:
  String.concat([render_dtype(dev, BArg.dtype(b), 1, BArg.addr(b), True{}, False{}, False{}),
    " ", BArg.name(b), mid, Bool.pick(String, String.eq(mid, ""), "", BArg.name(b)), ";"])

def metal_fields.go(+dev: U32, bs: List<&2, BArg>, +mid: String, acc: List<&2, String>) -> List<&2, String>:
  match bs:
    case Nil{}: acc
    case h <> t: metal_fields.go(dev, t, mid, List.append(&2, String, acc, [metal_field.of(dev, h, mid)]))

def metal_fields(+dev: U32, +bs: List<&2, BArg>, +mid: String) -> List<&2, String>:
  metal_fields.go(dev, bs, mid, Nil{})

def metal_prefix(+dev: U32, +bs: List<&2, BArg>) -> List<&2, String>:
  ["#include <metal_stdlib>", "using namespace metal;",
   String.concat(["struct args_t { ", String.join(metal_fields(dev, bs, ""), " "), " };"])]

# THE ARGS LINE GOES IN FRONT OF THE KERNEL. `["  " + ...] + kernel` PREPENDS, and
# a version that appended it put the unpacking line after the kernel body -- a
# kernel that reads its arguments after it has already used them. `add` is
# `a ++ b` and `List.append` is the sanctioned spelling (brief rule 6).
def metal_body(+dev: U32, +bs: List<&2, BArg>, +kernel: List<&2, String>) -> List<&2, String>:
  add([String.concat(["  ", String.join(metal_fields(dev, bs, " = args."), " ")])], kernel)

# WHAT EACH OVERRIDE HANDS TO `super().render_kernel`: the prefix LIST, WHETHER
# THERE IS ONE, and the bufs and body it rewrote. `pref` and `has` are separate
# fields because `prefix=[]` is a present-but-empty prefix, and a reader that
# derived one from the other would emit a leading newline on the base and drop one
# on CUDA. Metal is the only override that changes `bufs` or `body`.
type RkIn is Data:
  RkIn{pref: List<&2, String>, has: Bool, bufs: List<&2, BArg>, body: List<&2, String>}

def RkIn.pref(i: RkIn) -> List<&2, String>:
  match i:
    case RkIn{pref, has, bufs, body}: pref

def RkIn.has(i: RkIn) -> Bool:
  match i:
    case RkIn{pref, has, bufs, body}: has

def RkIn.bufs(i: RkIn) -> List<&2, BArg>:
  match i:
    case RkIn{pref, has, bufs, body}: bufs

def RkIn.body(i: RkIn) -> List<&2, String>:
  match i:
    case RkIn{pref, has, bufs, body}: body


def rk_in.of(+dev: U32, +bs: List<&2, BArg>, +kernel: List<&2, String>, +e: Emit_, cdna4: Bool) -> RkIn:
  match dev:
    case 3: RkIn{metal_prefix(dev, bs), True{}, Nil{}, metal_body(dev, bs, kernel)}
    case 4: RkIn{dev_prefix(dev, Emit_.uses(e), Emit_.vecs(e), Emit_.ockl(e), Emit_.ocml(e), cdna4), True{}, bs, kernel}
    case 5: RkIn{dev_prefix(dev, Emit_.uses(e), Emit_.vecs(e), Emit_.ockl(e), Emit_.ocml(e), cdna4), True{}, bs, kernel}
    case 2: RkIn{add(opencl_prefix(Emit_.uses(e)), Emit_.caller(e)), Bool.or(Emit_.has_prefix(e), Uses.half_any(Emit_.uses(e))), bs, kernel}
    case _: RkIn{Emit_.caller(e), Emit_.has_prefix(e), bs, kernel}

# `") {\n" + tmp` ++ `'\n'.join(kernel)` ++ `"\n}"` -- cstyle.py:165. `tmp` is the
# OpenCL image `sampler_t` line (cstyle.py:156-157), which is `""` unless a
# buffer is an image shape, and the gate's `is_image` flag is where that lives.
def rk_tail(+open: String, +args: String, kernel: List<&2, String>) -> String:
  String.concat([open, args, ") {\n", String.join(kernel, "\n"), "\n}"])

# `return prg if prefix is None else "\n".join(prefix)+f"\n{prg}"`.
def rk_prefix.of(+has_prefix: Bool, +prg: String, pref: List<&2, String>) -> String:
  Bool.pick(String, has_prefix, String.concat([String.join(pref, "\n"), "\n", prg]), prg)

def sig_open(+dev: U32, +lb: U32, fname: String) -> String:
  String.concat([kernel_typedef(dev, lb), " ", fname, "("])

def sig_args(args: List<&2, String>, extra: List<&2, String>) -> String:
  String.join(add(args, extra), ", ")

# CLANG'S WRAPPER -- cstyle.py:310-312. `defines` is `'\n'.join(_render_defines(uops))`
# and `entry` is `""` (cstyle.py:308), so on an empty uop list this is exactly
# `"\n" + body + "\n"` and NOTHING ELSE is different about Clang's framing.
def rk_wrap.of(+dev: U32, +vecs: List<&2, String>, +body: String) -> String:
  match dev:
    case 1: String.concat([String.join(vecs, "\n"), "\n", body, "\n"])
    case _: body

def rk_body.of(+i: RkIn, +dev: U32, +lb: U32, fname: String) -> String:
  rk_prefix.of(RkIn.has(i),
    rk_tail(sig_open(dev, lb, fname), sig_args(buftypes(dev, RkIn.bufs(i)), extra_args.dev(dev)), RkIn.body(i)), RkIn.pref(i))

# THE WHOLE THING. Six arguments where Python has five: `emit` stands in for the
# uop LIST, which is wall (a) -- there is no fold to walk -- and `cdna4` is
# `is_cdna4(self.target.arch)`, which Python reads off the target and which is a
# `Bool` here for the same reason `has_prefix` is (see the header).
def render_kernel(+dev: U32, +fname: String, lb: U32, +bs: List<&2, BArg>, +kernel: List<&2, String>, +e: Emit_, cdna4: Bool) -> String:
  rk_wrap.of(dev, Emit_.vecs(e), rk_body.of(rk_in.of(dev, bs, kernel, e, cdna4), dev, lb, fname))



# ===========================================================================
# THE GATE. Every `py=` string is CPython's own answer on this `tinygrad/` tree,
# measured with a script that constructs the RENDERER WITH `__new__` and sets
# `target` by hand -- because a real `ClangRenderer(Target(...))` runs
# `ClangCompiler` and a real `HIPRenderer` runs `comgr`, and this unit's rows are
# about STRING GENERATION, not about compilers. The `Bare<cls>(arch, dev)` trick
# is a measurement harness and nothing else; it is how the oracle was taken.
#
# THE ROWS ARE GROUPED BY WHAT THEY CAN BREAK, and each group has at least one
# row that a mutation in ANOTHER group cannot move:
#   * `tmap_*`  -- the six `type_map`s and the `.get(dtype, dtype.name)` default.
#     Sixteen dtypes x six devices is 96 cells, so they are printed as ONE row
#     per device with all sixteen joined; a single dropped entry moves the string.
#   * `rd_*`    -- `_render_dtype` over the addrspace/sz/override/image axes. This
#     is where the underscore-on-`sz>1` and the image-beats-everything live.
#   * `witem_*` -- `code_for_workitem`, including the base's empty dict.
#   * `cfo_*`   -- the ALU table, per device, including Clang's FIVE DELETIONS.
#   * `kern_*`  -- `kernel_typedef` with the bound, and the no-local case.
#
# `_render_dtype`'s ARGS ARE PYTHON'S OWN, so the oracle is a direct method call
# with the same values -- which is why this gate is complete for the string layer
# even while `_render` is blocked on the fold's deferred SHRINK.
# ===========================================================================

# THE SIXTEEN `dtypes.all` MEMBERS, in dtype.py's order, so the joined string is
# the same on both sides. `__init__.bend` already pins this list; reusing ITS
# def here is what stops the two files drifting on WHICH dtypes they iterate
# rather than only on what they render as.
def g_dtypes() -> List<&2, S.Dt>: R.dtypes_all()

# `type_map.get(dtype, dtype.name)` -- so this walks the RENDERED NAME, not
# `dt_name`. The first version of this row printed the dtype's own name and every
# device came back IDENTICAL, which is exactly what a `type_map` of `{}` looks
# like on every device: a row that reads the wrong COLUMN and a row that reads
# the right one both typecheck and both pass `--check-only`. `rd CLANG half`
# (which prints `__fp16`) is what caught it, because the same fact printed two
# ways disagreed.
def g_tmap_names.go(+dev: U32, ds: List<&2, S.Dt>, +acc: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}: acc
    case h <> t: g_tmap_names.go(dev, t, List.append(&2, String, acc, [rd_base_name(dev, h)]))

# Ninety-six cells in six rows. The DEFAULT is the load-bearing half and this is
# where a reader that answered "" for an unmapped dtype would be caught -- and
# CUDA's row is the one that PROVES the default works, because `float8_e4m3fnuz`
# is NOT in CUDA's map and prints as itself while `float8_e4m3` prints as
# `__nv_fp8_e4m3`. HIP's row proves the same for four dtypes at once.
def tmap_row(nm: String, py: String, dev: U32) -> IO(Unit):
  IO.print(String.concat([nm, " = [", String.join(g_tmap_names.go(dev, g_dtypes(), Nil{}), ","), "]   py=[", py, "]"]))

# SEVEN `_render_dtype` CALLS IN ONE STRING, and the seven are the SEVEN COLUMNS
# of the oracle: GLOBAL, LOCAL, ALU, REG, sz=4, override_ptr, and the image shape
# (read_only). Joining them into one row per (device, dtype) is what makes the
# gate affordable, and a single dropped character in any cell moves its row.
def rd_cells(+dev: U32, +d: S.Dt) -> String:
  String.concat([render_dtype(dev, d, 1, S.AGlobal{}, True{}, False{}, False{}), "|",
    render_dtype(dev, d, 1, S.ALocal{}, True{}, False{}, False{}), "|",
    render_dtype(dev, d, 1, S.Aalu{}, True{}, False{}, False{}), "|",
    render_dtype(dev, d, 1, S.AReg{}, True{}, False{}, False{}), "|",
    render_dtype(dev, d, 4, S.Aalu{}, True{}, False{}, False{}), "|",
    render_dtype(dev, d, 2, S.AReg{}, True{}, True{}, False{}), "|",
    render_dtype(dev, d, 1, S.AGlobal{}, False{}, False{}, True{})])

def rd_row(nm: String, py: String, +dev: U32, +d: S.Dt) -> IO(Unit):
  IO.print(String.concat([nm, " ", dt_name(d), " = [", rd_cells(dev, d), "]   py=[", py, "]"]))

# `render_buffer`. THE HIP ROW IS THE ONE THAT MATTERS: HIP's `smem_prefix` has
# no trailing space, so the type is glued to the attribute and the string reads
# `__attribute__((shared, aligned(16)))float L0[1];`. A reader that added the
# space would produce prettier output and a diff.
# The NAME IS A PARAMETER and not the literal "L0", because a global buffer is
# named `G` in the oracle: `ctx[u]` is the uop's own rendered name and a global
# buffer and a local one do not share one. The first version hardcoded "L0" and
# the three `GLOB` rows printed a LOCAL declaration under a global label -- a
# mismatch the gate caught on the NAME alone, with the type and the address space
# both right.
def buf_row(nm: String, py: String, +dev: U32, a: S.Addr, bufname: String) -> IO(Unit):
  IO.print(String.concat([nm, " = [", render_buffer(dev, S.single(), 1, a, bufname), "]   py=[", py, "]"]))

# `render_buffer` with a real element count, which is `ParamArg.size` and not
# `max_numel` -- the row that says the two are different questions.
def buf_sz_row(nm: String, py: String, +dev: U32) -> IO(Unit):
  IO.print(String.concat([nm, " = [", render_buffer(dev, S.half(), 16, S.ALocal{}, "L0"), "]   py=[", py, "]"]))

# `code_for_workitem` -- the base's EMPTY dict is a row of its own, because a base
# that answered `get_group_id(0)` would be plausible and wrong.
def witem_row(nm: String, py: String, +dev: U32) -> IO(Unit):
  IO.print(String.concat([nm, " = [", code_for_workitem.g(dev, "g", 0), " / ", code_for_workitem.g(dev, "l", 0), "]   py=[", py, "]"]))

# `code_for_op` for one op and one device. `xs` is the src-NAME list, which is
# what a `code_for_op` lambda receives after `ctx[y] for y in x.src`.
#
# THE LABEL CARRIES THE OP AND THE DTYPE TAG, and `O.Ops.name.of` supplies the op
# rather than a second literal: a `cfo` label that named only the DEVICE made
# twenty-three rows share one name, and a row-keyed diff over twenty-three
# same-named rows is twenty-two invisible comparisons. The tag is a `String`
# PARAMETER for the same reason the dtype is elsewhere -- `dt_name` would print
# `float` where the rows say `f32` and `half` where they say `f16`.
def cfo_row(nm: String, py: String, dev: U32, +op: O.Op, dtag: String, +d: S.Dt) -> IO(Unit):
  IO.print(String.concat([nm, " ", O.Ops.name.of(op), " ", dtag, " = [", code_for_op.of(dev, op, ["X", "Y", "Z"], d), "]   py=[", py, "]"]))

# The unary and the binary and the TERNARY are three different arities and WHERE
# is the only ternary, so a reader that threaded one argument list would emit
# `(X?Y)` for it. The three rows are what says so.
def cfo_where_row(nm: String, py: String, dev: U32) -> IO(Unit):
  IO.print(String.concat([nm, " = [", code_for_op.of(dev, O.OpsWHERE{}, ["X", "Y", "Z"], S.single()), "]   py=[", py, "]"]))

# `kernel_typedef` with the bound, INCLUDING the no-local case: `prod([])` is 1,
# so a kernel with no local SPECIAL gets `__launch_bounds__(1)` and not 0.
def kern_row(nm: String, py: String, dev: U32, +lb: U32) -> IO(Unit):
  IO.print(String.concat([nm, " lb=", U32.show(lb), " = [", kernel_typedef(dev, lb), "]   py=[", py, "]"]))

# `_wmma_name`, ON AN `AWmma` ARG AND NOT ON FOUR PARAMETERS. The first version of
# this row called `wmma_name_of(wmma_dims(dims), ...)` -- which is the INSIDE of
# `_wmma_name` and leaves the arena read untested, so a reader that took `u.arg[1]`
# where upstream takes `u.arg[0]` would have been green on all four rows. Reading
# the arg is what the row is for.
# THE SPACE CASE IS THE POINT: `int8.name` is `"signed char"`, so without the
# unconditional replace the name would be `WMMA_16_16_16_signed char_signed char`.
def wmma_row(nm: String, py: String, a: O.Arg, dout: S.Dt) -> IO(Unit):
  IO.print(String.concat([nm, " = [", wmma_name(a, dout), "]   py=[", py, "]"]))

# `under` -- the `.replace(" ", "_")` that `_render_dtype` uses on the `sz > 1`
# branch and `_wmma_name` uses UNCONDITIONALLY. Three rows: a name with no space
# (the no-op), a two-word name, and a three-part one.
def under_row(nm: String, py: String, s: String) -> IO(Unit):
  IO.print(String.concat([nm, " = [", under(s), "]   py=[", py, "]"]))

# `is_image_shape(shape)` -- BOTH mutabilities. The `rd` rows pin `read_only` and
# this one pins `write_only`, which is the half the `rd` cells could not see: the
# image column of every `rd` row passes `mutable=False`. An image buffer's
# mutability is the ONLY thing the two spellings differ on and it decides whether
# the kernel can write it.
def img_row(nm: String, py: String, mutable: Bool) -> IO(Unit):
  IO.print(String.concat([nm, " = [", render_dtype(dev_base(), S.single(), 1, S.AGlobal{}, mutable, False{}, True{}), "]   py=[", py, "]"]))

# A ROW IS ONE LINE. Every gate row prints `name = [bend]   py=[python]` and the
# DIFF is a line-keyed one, so a row whose text contains a newline is invisible:
# the parser never sees its `]   py=[` because that lands on line two. `esc_row`
# is what stops that -- it turns every `\n` into the two characters `\` and `n`,
# on BOTH sides, so the oracle in the source can stay a readable Python-style
# literal and the comparison stays textual.
#
# This is not a hypothetical: the `kern2` rows are the only multi-line rows in
# this file and they hid a Clang/HIP/Metal `render_kernel` that dropped the device
# prefix on every kernel. `wgsl.bend` has the same convention in `one_line` and
# needs the same guard for any row whose value can contain a newline.
def esc_row(s: String) -> String: String.join(String.split(s, '\n'), "\\n")

# THE OPTION TABLES, SIX CELLS IN ONE ROW. `barrier`, `float4` and `infinity`/`nan`
# are class attributes that `render_kernel` NEVER reads, so no `kern2` row can
# move them and a gate that does not diff them is a gate that cannot see a reader
# that swapped HIP's `smem_prefix` for CUDA's. One row per option, all six
# devices, joined: same trick as `tmap`, and `wgsl.bend`'s `global_max`/`local_max`
# rows are the same shape.
def opt_row(nm: String, py: String, six: List<&2, String>) -> IO(Unit):
  IO.print(String.concat([nm, " = [", String.join(six, "|"), "]   py=[", py, "]"]))

def opt_f4(+dev: U32) -> String:
  String.concat([float4.of(dev), float4_open(dev), float4_close(dev)])

def opt_inf(+dev: U32) -> String: String.concat([infinity.of(dev), "/", nan.of(dev)])

# `render_access` -- `f"*{render_ptr(u)}"`, and `kern2`'s fixture BODY spells it
# out by hand, so without this row the def and the fixture could disagree and
# every `kern2` row would still be green.
def acc_row(nm: String, py: String, dev: U32, +d: S.Dt, numel: U32, +sdt: S.Dt, nm2: String) -> IO(Unit):
  IO.print(String.concat([nm, " = [", render_access(dev, d, numel, S.Aalu{}, sdt, nm2, O.OpsINDEX{}, False{}), "]   py=[", py, "]"]))

# HIP's TWO EXTERN FAMILIES. `kern2 HIP ockl` emits the `ockl` three, and the
# `ocml` table has FIVE ops x THREE widths that no single kernel reaches at once
# -- and the half that matters is `__attribute__((device))` with NO comma, which a
# reader that always writes `, ` produces for the wrong two rows.
def hipockl_row(nm: String, py: String) -> IO(Unit):
  IO.print(String.concat([nm, " = [", esc_row(String.join(hip_ockl(), "\\n")), "]   py=[", esc_row(py), "]"]))

# `ocml_ops`' ORDER is upstream's dict order (EXP2, LOG2, SQRT, SIN, TRUNC,
# cstyle.py:565) and the widths are `half, float, double`, which is also upstream's
# filter order (`dt in (dtypes.f16, dtypes.f32, dtypes.f64)`).
def hipocml_cells() -> List<&2, String>:
  [ocml_extern("EXP2", S.half()), ocml_extern("EXP2", S.single()), ocml_extern("EXP2", S.double()),
   ocml_extern("LOG2", S.half()), ocml_extern("LOG2", S.single()), ocml_extern("LOG2", S.double()),
   ocml_extern("SQRT", S.half()), ocml_extern("SQRT", S.single()), ocml_extern("SQRT", S.double()),
   ocml_extern("SIN", S.half()), ocml_extern("SIN", S.single()), ocml_extern("SIN", S.double()),
   ocml_extern("TRUNC", S.half()), ocml_extern("TRUNC", S.single()), ocml_extern("TRUNC", S.double())]

def hipocml_row(nm: String, py: String) -> IO(Unit):
  IO.print(String.concat([nm, " = [", esc_row(String.join(hipocml_cells(), "\\n")), "]   py=[", esc_row(py), "]"]))

# THE `ockl`/`ocml` LISTS FOR THE `kern2 HIP ockl` ROW, and they are the FIXTURE
# rather than a derivation: upstream's list is `dedup((u.op, u.dtype) for u in
# uops)` filtered, so its ORDER is the uop walk's and the port's `Emit_` carries
# the finished list. This fixture is `SQRT(half)` then `SQRT(float)`, in that
# order -- and reversing it is a mutation, because two externs with different
# widths are not interchangeable in a header.
def hip_ocml() -> List<&2, String>: [ocml_extern("SQRT", S.half()), ocml_extern("SQRT", S.single())]

# `render_kernel` end to end -- the ONE place `buffer_prefix`, `buffer_suffix`,
# `var_prefix`, `var_suffix`, `extra_args`, `kernel_typedef` and the device's own
# `prefix` are all read together, so it is the only row that can see a break in
# any of them. `bs` is built from `BArg` rather than passed as a list of strings,
# because Python builds the `buftypes` list itself and a literal would have made
# `buffer_suffix` and `buftype` unreachable from the gate.
def g_bs(+d: S.Dt) -> List<&2, BArg>:
  [BArg{"data0_4", d, S.AGlobal{}, True{}, False{}, False{}}, BArg{"data1_4", d, S.AGlobal{}, True{}, False{}, False{}}]

# ONE BUFFER AND THE OTHER NOT, which is the only way `buftype`'s `volatile`
# prefix reaches the gate: the two `kern2 vol` rows differ from `kern2 BASE` in
# one argument and in one word, and a reader that dropped `volatile` would make
# the first of them identical to the second.
def g_bs_vol() -> List<&2, BArg>:
  [BArg{"data0_4", S.single(), S.AGlobal{}, True{}, True{}, False{}}, BArg{"data1_4", S.single(), S.AGlobal{}, True{}, False{}, False{}}]

# THE KERNEL BODY, two lines, verbatim from the oracle. `emit_min()` is
# `uops=[]`: no half, no bf16, no fp8, no non-finite CONST, no SPECIAL and no
# vector prefix, which is the configuration in which four of the five vendor
# prefixes are still non-empty.
def g_kernel() -> List<&2, String>:
  ["  float4 val0 = (*((float4*)((data1_4+0))));", "  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};"]

# THE CALLER'S PREFIX -- the two lines `RenderKernel.render_kernel` in
# `renderer/__init__.py` passes down. Their text is a fixture, not a product, and
# the rows that use them exist for one reason: CUDA, HIP and Metal DROP them.
def g_caller() -> List<&2, String>: ["// generated by tinybendygrad", "#pragma OPENCL EXTENSION cl_khr_fp16 : enable"]

# ONE `render_kernel` PER DEVICE, AND THE ONE ROW THAT SEES A NEWLINE. Every
# other row's value is one line; this one's is five or nine, so `esc_row` is
# applied to BOTH sides (see its comment) and the multi-line hazard is the reason
# the very first version of these rows passed while dropping three devices'
# prefixes entirely.
def kern2_row(nm: String, py: String, +dev: U32, +lb: U32, +bs: List<&2, BArg>, +e: Emit_, cdna4: Bool) -> IO(Unit):
  IO.print(String.concat([nm, " = [", esc_row(render_kernel(dev, "E_4", lb, bs, g_kernel(), e, cdna4)), "]   py=[", esc_row(py), "]"]))

# `render_index`. The ALU SWIZZLE rows are the ones a reader gets wrong, and the
# threshold direction is the thing: Clang's 0 means a one-element buffer STILL
# gets `.x` and CUDA's 8 means an eight-element buffer STILL gets `[0]`. The
# `bnumel` is a parameter so the same row covers both sides of each cut.
# THE SWIZZLE FIXTURE IS AN ARENA, NOT A LITERAL. The first version of this row
# passed `idx = 0` into an EMPTY arena, so `swizzle_val` read the bottom node's
# `ABad` and every letter came back `x` -- which made the `k=1` rows
# indistinguishable from the `k=0` rows. A row that cannot see the difference
# between two of the values it claims to pin is not pinning them.
#
# `UOp(Ops.CAST, (UOp.const(k),), dtypes.i32)` is the node `render_index` is
# documented to test for (`idx.op is CAST and idx.src[0].op is CONST`), so the
# fixture is that node and the letter is the CONST's value.
def g_cidx(+k: U32) -> O.Found:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(k)})
  O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{S.int32()}, O.TNone{})

# THE SAME NODE WITH AN `Ops.ADD` ARG. `idx.arg == Ops.ADD` is the OTHER half of
# the non-ALU branch -- it is what decides between `(buf+idx)` and
# `(buf+strip_parens(idx))` -- and `UOp.reduce(..., Ops.ADD)` with zero axes is
# the shape `Ops.INDEX`'s sugar builds when the index is a sum, so an `AReduce`
# with `num_axes = 0` is the arg the arm is written for. Without this fixture
# `strip_parens` is unreachable from the gate and the arm is never seen.
def g_cidx_add(+k: U32) -> O.Found:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(k)})
  O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.AReduce{O.OpsADD{}, 0}, O.TNone{})

# AN INDEX THAT IS NOT A CONST INDEX. `idx.op is CAST` fails, which is the whole
# lane test, so the op is the one an `Ops.INDEX` sugar actually builds rather
# than a CONST -- the previous version passed `lane = True` as a `Bool` and the
# two-op test `idx_is_const_idx` was never executed at all.
def g_lane() -> O.Found:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(0)})
  O.UOp.new(O.Found.ar(c), O.OpsINDEX{}, [O.Found.i(c)], O.ADt{S.int32()}, O.TNone{})

# `k` is the CONST's value and comes out of the FIXTURE, not a `Bool` parameter:
# `lane` is `not (idx.op is CAST and idx.src[0].op is CONST)` read off the same
# arena, so a row that passed `lane` by hand would be testing a Bool rather than
# the two-op test `render_index` is documented to make. `baddr` is the BUFFER's
# address space and it is what picks the ALU arm over the `(buf+idx)` one.
#
# `iname` IS THE INDEX'S OWN TEXT AND IT IS A PARAMETER because the `strip_parens`
# half is invisible on a bare name: `(B+R)` is what BOTH the ADD and the non-ADD
# arm print when the index renders as `R`, so the two rows would be the same row
# twice. `(R)` is what an ALU index really renders as, and it is what makes the
# half visible.
def idx_row(nm: String, py: String, dev: U32, baddr: S.Addr, bnumel: U32, iname: String, +f: O.Found) -> IO(Unit):
  IO.print(String.concat([nm, " = [",
    render_index(O.Found.ar(f), dev, O.Found.i(f), baddr, "B", iname, bnumel,
      Bool.not(idx_is_const_idx(O.Found.ar(f), O.Found.i(f)))),
    "]   py=[", py, "]"]))

# `render_type` and `render_ptr` and `render_cast`. `ptr stk4` is the
# `max_numel > 1` arm and `ptr bitcast` is the `dtype != src.dtype` arm, and
# `type regidx` is the `override_ptr` arm -- a REG-space INDEX is a vector
# register and renders as a POINTER.
def type_row(nm: String, py: String, dev: U32, +d: S.Dt, numel: U32, a: S.Addr, op: O.Op) -> IO(Unit):
  IO.print(String.concat([nm, " = [", render_type(dev, d, numel, a, op, False{}), "]   py=[", py, "]"]))

def ptr_row(nm: String, py: String, dev: U32, +d: S.Dt, numel: U32, sdt: S.Dt, nm2: String) -> IO(Unit):
  IO.print(String.concat([nm, " = [", render_ptr(dev, d, numel, S.Aalu{}, sdt, nm2, O.OpsINDEX{}, False{}), "]   py=[", py, "]"]))

def cast_row(nm: String, py: String, dev: U32, +d: S.Dt) -> IO(Unit):
  IO.print(String.concat([nm, " = [", render_cast(dev, d, 1, S.Aalu{}, O.OpsCAST{}, False{}, "V"), "]   py=[", py, "]"]))

def legacy_row(nm: String, py: String, dev: U32, +d: S.Dt) -> IO(Unit):
  IO.print(String.concat([nm, " ", dt_name(d), " = [", render_dtype_legacy(dev, d), "]   py=[", py, "]"]))

# ===========================================================================























# ===========================================================================
# THE GATE FIXTURES that are not single expressions. Each is named after the
# CLAUSE it switches on rather than after the `Uses` booleans it sets, because
# `emit_of(uses_of(False{},False{},False{},False{},True{},False{}), ...)` at a
# call site says nothing and `emit_hip_spec()` says which of HIP's eight clauses
# the row is about. The BOOLEAN ORDER of `uses_of` is the field order of `Uses` and
# nothing else decides it.
# ===========================================================================

def uses_of(half: Bool, bf16: Bool, fp8: Bool, nf: Bool, spec: Bool, ha: Bool) -> Uses:
  Uses{half, bf16, fp8, nf, spec, ha}

# `prefix=<two lines>` -- the caller's prefix, which ONLY the base and OpenCL keep.
def emit_caller(+pfx: List<&2, String>) -> Emit_: emit_of(uses_off(), Nil{}, Nil{}, Nil{}, pfx, True{})

# `prefix=[]` -- a PRESENT BUT EMPTY prefix, which is not `None` and which is the
# case that must still gain a leading newline (cstyle.py:166).
def emit_prefixed() -> Emit_: emit_of(uses_off(), Nil{}, Nil{}, Nil{}, Nil{}, True{})

# OpenCL's `#pragma`, which is conditional on a HALF UOP over the whole list
# (`any(uop.dtype == dtypes.f16 for uop in uops)`, cstyle.py:349) and PREPENDS
# onto the caller's list -- so `half_any` is a different Bool from CUDA's `half`
# and it is the reason `Uses` has six fields.
def emit_ocl_half(+pfx: List<&2, String>) -> Emit_:
  emit_of(uses_of(True{}, False{}, False{}, False{}, False{}, True{}), Nil{}, Nil{}, Nil{}, pfx, True{})

# HIP's prefix clauses, one fixture each. `cdna4` is NOT a `Uses` field: it is
# `is_cdna4(self.target.arch)`, a property of the TARGET, and it travels as
# `render_kernel`'s own parameter. `kern2 HIP bf16` and `kern2 HIP cdna4` are the
# same fixture with that one Bool flipped, and their diff IS that Bool.
def emit_hip_spec() -> Emit_:
  emit_of(uses_of(False{}, False{}, False{}, False{}, True{}, False{}), Nil{}, hip_ockl(), Nil{}, Nil{}, False{})

def emit_hip_half() -> Emit_:
  emit_of(uses_of(True{}, False{}, False{}, False{}, True{}, False{}), Nil{}, hip_ockl(), Nil{}, Nil{}, False{})

def emit_hip_ocml() -> Emit_:
  emit_of(uses_of(True{}, False{}, False{}, False{}, True{}, False{}), Nil{}, hip_ockl(), hip_ocml(), Nil{}, False{})

def emit_hip_bf16() -> Emit_:
  emit_of(uses_of(False{}, True{}, False{}, False{}, True{}, False{}), Nil{}, hip_ockl(), Nil{}, Nil{}, False{})

# `hip_bfloat16` AND `half` TOGETHER, which is the only configuration in which
# `prefix_clause`'s HIP ORDER is visible: with one or the other the two clauses sit
# alone and swapping them moves nothing. `emit_hip_bf16` is the cdna4 pair and this
# is the ordering pair, and they are different fixtures for that reason.
def emit_hip_bf16_half() -> Emit_:
  emit_of(uses_of(True{}, True{}, False{}, False{}, True{}, False{}), Nil{}, hip_ockl(), Nil{}, Nil{}, False{})

def emit_hip_inf() -> Emit_:
  emit_of(uses_of(False{}, False{}, False{}, True{}, True{}, False{}), Nil{}, hip_ockl(), Nil{}, Nil{}, False{})

# CUDA's ONE clause shape: four static lines and then one `#include` per used
# dtype, so the whole device differs by the three `uses_of` booleans.
def emit_cuda(u: Uses) -> Emit_: emit_of(u, Nil{}, Nil{}, Nil{}, Nil{}, False{})

# THE VECTOR-PREFIX LINES ARE UPSTREAM'S OWN TEXT, AND THE TWO VENDORS SPELL THEM
# DIFFERENTLY: CUDA emits a `struct __align__(8) ...; __device__ half4 make_half4`
# on ONE line and HIP a `typedef ...;` then a `static inline ...` on TWO. So the
# two fixtures are separate lists rather than one shared `vecs`, and the two rows
# are what says a vendor prefix cannot be shared between them.
#   TODO(p3) cstyle.py:448, :550  `render_vector_prefix` itself. It needs the fold
#   (`uops_to_dtypes`), so `vecs` arrives as a finished `List<&2, String>`.
def g_cuda_vecs() -> List<&2, String>:
  ["struct __align__(8) half4 { half x, y, z, w; }; __device__ half4 make_half4(half x, half y, half z, half w) { half4 r={x, y, z, w}; return r; }"]

def g_hip_vecs() -> List<&2, String>:
  ["typedef half half4 __attribute__((ext_vector_type(4)));\\nstatic inline __attribute__((device)) half4 make_half4(half x, half y, half z, half w) { return { x, y, z, w }; }"]

# `half` IS SET IN BOTH because upstream's `used_dtypes` is what produces BOTH the
# `#include <cuda_fp16.h>` / `#define half _Float16` line AND the `vecs` line, so a
# fixture with `vecs` set and `half` clear is a configuration upstream never emits
# and the row would be a green claim about nothing.
def emit_vecs(+vecs: List<&2, String>) -> Emit_:
  emit_of(uses_of(True{}, False{}, False{}, False{}, False{}, False{}), vecs, Nil{}, Nil{}, Nil{}, False{})

def emit_hip_vecs(+vecs: List<&2, String>) -> Emit_:
  emit_of(uses_of(True{}, False{}, False{}, False{}, True{}, False{}), vecs, hip_ockl(), Nil{}, Nil{}, False{})

# AN ALU-SPACE BUFFER ARGUMENT, for `buftype`'s `var_prefix`/`var_suffix` arm. A
# kernel argument is never ALU in practice, so this is the only way the two `var_*`
# tables get gated at all: the mutation `var_prefix: Metal -> const` moved NOTHING
# before these three rows existed.
def g_bs_alu() -> List<&2, BArg>:
  [BArg{"alu0_1", S.single(), S.Aalu{}, True{}, False{}, False{}}, BArg{"alu1_1", S.single(), S.Aalu{}, True{}, False{}, False{}}]

# THE FIVE `buftype` CELLS OF ONE DEVICE, joined: an ALU buffer plain and volatile,
# a GLOBAL buffer plain and volatile, and a LOCAL one. This row exists because
# METAL'S `var_prefix` AND `var_suffix` ARE UNREACHABLE THROUGH `render_kernel` --
# `MetalRenderer.render_kernel` calls `super()` with `bufs=[]`, so `buftypes` is
# empty and the class attributes are read by NOTHING upstream. They are ported
# because they are class attributes of cstyle.py, and the only honest way to gate
# them is to evaluate upstream's `buftypes` expression with this renderer as
# `self` -- which is what the oracle does.
def buft_row(nm: String, py: String, +dev: U32) -> IO(Unit):
  IO.print(String.concat([nm, " = [", String.join([buftype(dev, BArg{"v0", S.single(), S.Aalu{}, True{}, False{}, False{}}),
    buftype(dev, BArg{"v0", S.single(), S.Aalu{}, True{}, True{}, False{}}),
    buftype(dev, BArg{"v0", S.single(), S.AGlobal{}, True{}, False{}, False{}}),
    buftype(dev, BArg{"v0", S.single(), S.AGlobal{}, True{}, True{}, False{}}),
    buftype(dev, BArg{"v0", S.single(), S.ALocal{}, True{}, False{}, False{}})], "|"), "]   py=[", py, "]"]))

# THE FOUR `AWmma` ARGS, one per `_wmma_name` row. `(dims, dtype_in, threads,
# tc)` is the whole arg and `dout` is the NODE's dtype rather than part of it --
# upstream's `_wmma_name` reads `u.arg[1].name` for the input and `u.dtype.name`
# for the output, so the two come from different places and a reader that used one
# for both would be right on the three fixtures where they coincide.
def wmma_arg(ds: List<&2, U32>, din: S.Dt) -> O.Arg: O.AWmma{ds, din, 32, Nil{}}

# THE SIX-CELL OPTION ROWS. One def per option rather than a fold over a device
# list, because each option's per-device expression is a different function and a
# closure is not a value a parameter can hold.
def dev_names() -> List<&2, String>:
  [dev_name(dev_base()), dev_name(dev_clang()), dev_name(dev_opencl()), dev_name(dev_metal()), dev_name(dev_cuda()), dev_name(dev_hip())]

def barriers() -> List<&2, String>:
  [barrier.of(dev_base()), barrier.of(dev_clang()), barrier.of(dev_opencl()), barrier.of(dev_metal()), barrier.of(dev_cuda()), barrier.of(dev_hip())]

def f4s() -> List<&2, String>:
  [opt_f4(dev_clang()), opt_f4(dev_opencl()), opt_f4(dev_metal()), opt_f4(dev_cuda()), opt_f4(dev_hip())]

def infs() -> List<&2, String>:
  [opt_inf(dev_base()), opt_inf(dev_clang()), opt_inf(dev_opencl()), opt_inf(dev_metal()), opt_inf(dev_cuda()), opt_inf(dev_hip())]

# THE `Ops.ADD`-ARG INDEX FIXTURE. `g_cidx` itself lives above with the other arena
# fixtures and the three swizzle letters the gate pins are `g_cidx(0)`, `g_cidx(1)`
# and `g_cidx(3)` -- spelled at the CALL SITE, because a one-line alias per letter
# is three defs that say less than the letter does.
def g_cadd0() -> O.Found: g_cidx_add(0)

# ===========================================================================
# `main`. 227 ROWS, every one of them a STRING DIFF against CPython, in ten
# groups. The order is the group order and the groups are chosen so that a
# mutation in one CANNOT move a row in another unless it really is shared --
# which is what makes the mutation table at the foot mean something.
#
#   tmap_*   x6   the six `type_map`s (96 dtype cells)
#   rd_*     x42  `_render_dtype` over 7 dtypes x 6 devices (294 cells)
#   witem_*  x6   `code_for_workitem`, including the base's EMPTY dict
#   cfo_*    x74  the ALU table per device, incl. Clang's FIVE DELETIONS
#   kern_*   x8   `kernel_typedef` with the bound, incl. the no-local case
#   idx_*    x20  `render_index`: the swizzle/array cut on BOTH sides of each
#                device's `gep_arr_threshold`, the lane form, and the non-ALU
#                `(buf+idx)` arm with and without `idx.arg is Ops.ADD`
#   opt_*    x4   the six-cell option tables `render_kernel` never reads
#   type/ptr/acc/cast/leg/buf2  the four pointer/cast vocabulary defs
#   wmma_*   x4   `_wmma_name`, including `signed char` -> `signed_char`
#   under_*  x3   the `.replace(" ", "_")` both callers share
#   img_*    x3   the image arm, which BEATS the address space
#   hipockl / hipocml  the two extern families in full
#   kern2_*  x23  `render_kernel` end to end, one per device per prefix clause
#
# THE `py=` LITERALS ARE GENERATED BY CALLING CPython, NOT TYPED. The generator
# is `.agents/slop/wip/gen_main.py`; it builds this whole table from live
# `tinygrad` and writes both the row call and its oracle. A `py=` string that was
# transcribed by hand is a claim about CPython rather than a measurement of it,
# and the first version of this file had 215 of the second kind.
# ===========================================================================

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- tmap_row("tmap BASE ", "float8_e4m3,float8_e5m2,float8_e4m3fnuz,float8_e5m2fnuz,half,__bf16,float,double,unsigned char,unsigned short,unsigned int,unsigned long,signed char,short,int,long,bool", dev_base())
    _ : Unit <- tmap_row("tmap CLANG", "float8_e4m3,float8_e5m2,float8_e4m3fnuz,float8_e5m2fnuz,__fp16,__bf16,float,double,unsigned char,unsigned short,unsigned int,unsigned long,signed char,short,int,long,_Bool", dev_clang())
    _ : Unit <- tmap_row("tmap OPENCL", "float8_e4m3,float8_e5m2,float8_e4m3fnuz,float8_e5m2fnuz,half,ushort,float,double,uchar,ushort,uint,ulong,char,short,int,long,bool", dev_opencl())
    _ : Unit <- tmap_row("tmap METAL", "float8_e4m3,float8_e5m2,float8_e4m3fnuz,float8_e5m2fnuz,half,bfloat,float,double,unsigned char,unsigned short,uint,unsigned long,signed char,short,int,long,bool", dev_metal())
    _ : Unit <- tmap_row("tmap CUDA ", "__nv_fp8_e4m3,__nv_fp8_e5m2,float8_e4m3fnuz,float8_e5m2fnuz,half,nv_bfloat16,float,double,unsigned char,unsigned short,uint,unsigned long,signed char,short,int,long,bool", dev_cuda())
    _ : Unit <- tmap_row("tmap HIP  ", "hip_fp8,hip_bf8,hip_fp8,hip_bf8,half,hip_bfloat16,float,double,unsigned char,unsigned short,unsigned int,unsigned long,signed char,short,int,long,bool", dev_hip())
    _ : Unit <- rd_row("rd BASE ", "float*|float*|float|float|float4|float2*|read_only image2d_t", dev_base(), S.single())
    _ : Unit <- rd_row("rd CLANG", "float*|float*|float|float|float4|float2*|read_only image2d_t", dev_clang(), S.single())
    _ : Unit <- rd_row("rd OPENCL", "__global float*|__local float*|float|float|float4|float2*|read_only image2d_t", dev_opencl(), S.single())
    _ : Unit <- rd_row("rd METAL", "device float*|threadgroup __attribute__((aligned(16))) float*|float|float|float4|float2*|read_only image2d_t", dev_metal(), S.single())
    _ : Unit <- rd_row("rd CUDA ", "float*|float*|float|float|float4|float2*|read_only image2d_t", dev_cuda(), S.single())
    _ : Unit <- rd_row("rd HIP  ", "float*|float*|float|float|float4|float2*|read_only image2d_t", dev_hip(), S.single())
    _ : Unit <- rd_row("rd BASE ", "half*|half*|half|half|half4|half2*|read_only image2d_t", dev_base(), S.half())
    _ : Unit <- rd_row("rd CLANG", "__fp16*|__fp16*|__fp16|__fp16|__fp164|__fp162*|read_only image2d_t", dev_clang(), S.half())
    _ : Unit <- rd_row("rd OPENCL", "__global half*|__local half*|half|half|half4|half2*|read_only image2d_t", dev_opencl(), S.half())
    _ : Unit <- rd_row("rd METAL", "device half*|threadgroup __attribute__((aligned(16))) half*|half|half|half4|half2*|read_only image2d_t", dev_metal(), S.half())
    _ : Unit <- rd_row("rd CUDA ", "half*|half*|half|half|half4|half2*|read_only image2d_t", dev_cuda(), S.half())
    _ : Unit <- rd_row("rd HIP  ", "half*|half*|half|half|half4|half2*|read_only image2d_t", dev_hip(), S.half())
    _ : Unit <- rd_row("rd BASE ", "__bf16*|__bf16*|__bf16|__bf16|__bf164|__bf162*|read_only image2d_t", dev_base(), S.bfloat16())
    _ : Unit <- rd_row("rd CLANG", "__bf16*|__bf16*|__bf16|__bf16|__bf164|__bf162*|read_only image2d_t", dev_clang(), S.bfloat16())
    _ : Unit <- rd_row("rd OPENCL", "__global ushort*|__local ushort*|ushort|ushort|ushort4|ushort2*|read_only image2d_t", dev_opencl(), S.bfloat16())
    _ : Unit <- rd_row("rd METAL", "device bfloat*|threadgroup __attribute__((aligned(16))) bfloat*|bfloat|bfloat|bfloat4|bfloat2*|read_only image2d_t", dev_metal(), S.bfloat16())
    _ : Unit <- rd_row("rd CUDA ", "nv_bfloat16*|nv_bfloat16*|nv_bfloat16|nv_bfloat16|nv_bfloat164|nv_bfloat162*|read_only image2d_t", dev_cuda(), S.bfloat16())
    _ : Unit <- rd_row("rd HIP  ", "hip_bfloat16*|hip_bfloat16*|hip_bfloat16|hip_bfloat16|hip_bfloat164|hip_bfloat162*|read_only image2d_t", dev_hip(), S.bfloat16())
    _ : Unit <- rd_row("rd BASE ", "bool*|bool*|bool|bool|bool4|bool2*|read_only image2d_t", dev_base(), S.boolean())
    _ : Unit <- rd_row("rd CLANG", "_Bool*|_Bool*|_Bool|_Bool|_Bool4|_Bool2*|read_only image2d_t", dev_clang(), S.boolean())
    _ : Unit <- rd_row("rd OPENCL", "__global bool*|__local bool*|bool|bool|bool4|bool2*|read_only image2d_t", dev_opencl(), S.boolean())
    _ : Unit <- rd_row("rd METAL", "device bool*|threadgroup __attribute__((aligned(16))) bool*|bool|bool|bool4|bool2*|read_only image2d_t", dev_metal(), S.boolean())
    _ : Unit <- rd_row("rd CUDA ", "bool*|bool*|bool|bool|bool4|bool2*|read_only image2d_t", dev_cuda(), S.boolean())
    _ : Unit <- rd_row("rd HIP  ", "bool*|bool*|bool|bool|bool4|bool2*|read_only image2d_t", dev_hip(), S.boolean())
    _ : Unit <- rd_row("rd BASE ", "unsigned char*|unsigned char*|unsigned char|unsigned char|unsigned_char4|unsigned_char2*|read_only image2d_t", dev_base(), S.uint8())
    _ : Unit <- rd_row("rd CLANG", "unsigned char*|unsigned char*|unsigned char|unsigned char|unsigned_char4|unsigned_char2*|read_only image2d_t", dev_clang(), S.uint8())
    _ : Unit <- rd_row("rd OPENCL", "__global uchar*|__local uchar*|uchar|uchar|uchar4|uchar2*|read_only image2d_t", dev_opencl(), S.uint8())
    _ : Unit <- rd_row("rd METAL", "device unsigned char*|threadgroup __attribute__((aligned(16))) unsigned char*|unsigned char|unsigned char|unsigned_char4|unsigned_char2*|read_only image2d_t", dev_metal(), S.uint8())
    _ : Unit <- rd_row("rd CUDA ", "unsigned char*|unsigned char*|unsigned char|unsigned char|unsigned_char4|unsigned_char2*|read_only image2d_t", dev_cuda(), S.uint8())
    _ : Unit <- rd_row("rd HIP  ", "unsigned char*|unsigned char*|unsigned char|unsigned char|unsigned_char4|unsigned_char2*|read_only image2d_t", dev_hip(), S.uint8())
    _ : Unit <- rd_row("rd BASE ", "float8_e4m3*|float8_e4m3*|float8_e4m3|float8_e4m3|float8_e4m34|float8_e4m32*|read_only image2d_t", dev_base(), S.fp8e4m3())
    _ : Unit <- rd_row("rd CLANG", "float8_e4m3*|float8_e4m3*|float8_e4m3|float8_e4m3|float8_e4m34|float8_e4m32*|read_only image2d_t", dev_clang(), S.fp8e4m3())
    _ : Unit <- rd_row("rd OPENCL", "__global float8_e4m3*|__local float8_e4m3*|float8_e4m3|float8_e4m3|float8_e4m34|float8_e4m32*|read_only image2d_t", dev_opencl(), S.fp8e4m3())
    _ : Unit <- rd_row("rd METAL", "device float8_e4m3*|threadgroup __attribute__((aligned(16))) float8_e4m3*|float8_e4m3|float8_e4m3|float8_e4m34|float8_e4m32*|read_only image2d_t", dev_metal(), S.fp8e4m3())
    _ : Unit <- rd_row("rd CUDA ", "__nv_fp8_e4m3*|__nv_fp8_e4m3*|__nv_fp8_e4m3|__nv_fp8_e4m3|__nv_fp8_e4m34|__nv_fp8_e4m32*|read_only image2d_t", dev_cuda(), S.fp8e4m3())
    _ : Unit <- rd_row("rd HIP  ", "hip_fp8*|hip_fp8*|hip_fp8|hip_fp8|hip_fp84|hip_fp82*|read_only image2d_t", dev_hip(), S.fp8e4m3())
    _ : Unit <- rd_row("rd BASE ", "int*|int*|int|int|int4|int2*|read_only image2d_t", dev_base(), S.int32())
    _ : Unit <- rd_row("rd CLANG", "int*|int*|int|int|int4|int2*|read_only image2d_t", dev_clang(), S.int32())
    _ : Unit <- rd_row("rd OPENCL", "__global int*|__local int*|int|int|int4|int2*|read_only image2d_t", dev_opencl(), S.int32())
    _ : Unit <- rd_row("rd METAL", "device int*|threadgroup __attribute__((aligned(16))) int*|int|int|int4|int2*|read_only image2d_t", dev_metal(), S.int32())
    _ : Unit <- rd_row("rd CUDA ", "int*|int*|int|int|int4|int2*|read_only image2d_t", dev_cuda(), S.int32())
    _ : Unit <- rd_row("rd HIP  ", "int*|int*|int|int|int4|int2*|read_only image2d_t", dev_hip(), S.int32())
    _ : Unit <- witem_row("witem BASE ", " / ", dev_base())
    _ : Unit <- witem_row("witem CLANG", " / ", dev_clang())
    _ : Unit <- witem_row("witem OPENCL", "get_group_id(0) / get_local_id(0)", dev_opencl())
    _ : Unit <- witem_row("witem METAL", "gid.x / lid.x", dev_metal())
    _ : Unit <- witem_row("witem CUDA ", "blockIdx.x / threadIdx.x", dev_cuda())
    _ : Unit <- witem_row("witem HIP  ", "__ockl_get_group_id(0) / __ockl_get_local_id(0)", dev_hip())
    _ : Unit <- cfo_row("cfo BASE ", "sqrt(X)", dev_base(), O.OpsSQRT{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "sqrt(X)", dev_base(), O.OpsSQRT{}, "f16", S.half())
    _ : Unit <- cfo_row("cfo BASE ", "sqrt(X)", dev_base(), O.OpsSQRT{}, "f64", S.double())
    _ : Unit <- cfo_row("cfo BASE ", "-X", dev_base(), O.OpsNEG{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(1/X)", dev_base(), O.OpsRECIPROCAL{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(1/X)", dev_base(), O.OpsRECIPROCAL{}, "f16", S.half())
    _ : Unit <- cfo_row("cfo BASE ", "exp2(X)", dev_base(), O.OpsEXP2{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "log2(X)", dev_base(), O.OpsLOG2{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "sin(X)", dev_base(), O.OpsSIN{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "trunc(X)", dev_base(), O.OpsTRUNC{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(X+Y)", dev_base(), O.OpsADD{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(X-Y)", dev_base(), O.OpsSUB{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(X*Y)", dev_base(), O.OpsMUL{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(X/Y)", dev_base(), O.OpsCDIV{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(X%Y)", dev_base(), O.OpsCMOD{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(X>>Y)", dev_base(), O.OpsSHR{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(X<<Y)", dev_base(), O.OpsSHL{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(X<Y)", dev_base(), O.OpsCMPLT{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(X==Y)", dev_base(), O.OpsCMPEQ{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(X!=Y)", dev_base(), O.OpsCMPNE{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(X&Y)", dev_base(), O.OpsAND{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(X|Y)", dev_base(), O.OpsOR{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "(X^Y)", dev_base(), O.OpsXOR{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo BASE ", "", dev_base(), O.OpsFDIV{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo CLANG", "__builtin_sqrtf(X)", dev_clang(), O.OpsSQRT{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo CLANG", "__builtin_sqrtf(X)", dev_clang(), O.OpsSQRT{}, "f16", S.half())
    _ : Unit <- cfo_row("cfo CLANG", "__builtin_sqrt(X)", dev_clang(), O.OpsSQRT{}, "f64", S.double())
    _ : Unit <- cfo_row("cfo CLANG", "__builtin_truncf(X)", dev_clang(), O.OpsTRUNC{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo CLANG", "__builtin_trunc(X)", dev_clang(), O.OpsTRUNC{}, "f64", S.double())
    _ : Unit <- cfo_row("cfo CLANG", "(X/Y)", dev_clang(), O.OpsFDIV{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo CLANG", "", dev_clang(), O.OpsEXP2{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo CLANG", "", dev_clang(), O.OpsLOG2{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo CLANG", "", dev_clang(), O.OpsSIN{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo CLANG", "", dev_clang(), O.OpsRECIPROCAL{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo CLANG", "(X+Y)", dev_clang(), O.OpsADD{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo METAL", "precise::sin(X)", dev_metal(), O.OpsSIN{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo METAL", "precise::sin(X)", dev_metal(), O.OpsSIN{}, "f16", S.half())
    _ : Unit <- cfo_row("cfo METAL", "sqrt(X)", dev_metal(), O.OpsSQRT{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo METAL", "", dev_metal(), O.OpsFDIV{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo CUDA ", "hsqrt(X)", dev_cuda(), O.OpsSQRT{}, "f16", S.half())
    _ : Unit <- cfo_row("cfo CUDA ", "sqrt(X)", dev_cuda(), O.OpsSQRT{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo CUDA ", "htrunc(X)", dev_cuda(), O.OpsTRUNC{}, "f16", S.half())
    _ : Unit <- cfo_row("cfo CUDA ", "trunc(X)", dev_cuda(), O.OpsTRUNC{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo CUDA ", "hsin(X)", dev_cuda(), O.OpsSIN{}, "f16", S.half())
    _ : Unit <- cfo_row("cfo CUDA ", "hlog2(X)", dev_cuda(), O.OpsLOG2{}, "f16", S.half())
    _ : Unit <- cfo_row("cfo CUDA ", "hexp2(X)", dev_cuda(), O.OpsEXP2{}, "f16", S.half())
    _ : Unit <- cfo_row("cfo CUDA ", "hrcp(X)", dev_cuda(), O.OpsRECIPROCAL{}, "f16", S.half())
    _ : Unit <- cfo_row("cfo CUDA ", "(1/X)", dev_cuda(), O.OpsRECIPROCAL{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo CUDA ", "sqrt(X)", dev_cuda(), O.OpsSQRT{}, "f64", S.double())
    _ : Unit <- cfo_row("cfo CUDA ", "hsqrt(X)", dev_cuda(), O.OpsSQRT{}, "bf16", S.bfloat16())
    _ : Unit <- cfo_row("cfo CUDA ", "hsin(X)", dev_cuda(), O.OpsSIN{}, "bf16", S.bfloat16())
    _ : Unit <- cfo_row("cfo CUDA ", "htrunc(X)", dev_cuda(), O.OpsTRUNC{}, "bf16", S.bfloat16())
    _ : Unit <- cfo_row("cfo CUDA ", "hlog2(X)", dev_cuda(), O.OpsLOG2{}, "bf16", S.bfloat16())
    _ : Unit <- cfo_row("cfo CUDA ", "hexp2(X)", dev_cuda(), O.OpsEXP2{}, "bf16", S.bfloat16())
    _ : Unit <- cfo_row("cfo CUDA ", "hrcp(X)", dev_cuda(), O.OpsRECIPROCAL{}, "bf16", S.bfloat16())
    _ : Unit <- cfo_row("cfo CUDA ", "", dev_cuda(), O.OpsFDIV{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo HIP  ", "__ocml_sqrt_f16(X)", dev_hip(), O.OpsSQRT{}, "f16", S.half())
    _ : Unit <- cfo_row("cfo HIP  ", "__ocml_sqrt_f32(X)", dev_hip(), O.OpsSQRT{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo HIP  ", "__ocml_sqrt_f64(X)", dev_hip(), O.OpsSQRT{}, "f64", S.double())
    _ : Unit <- cfo_row("cfo HIP  ", "__ocml_trunc_f16(X)", dev_hip(), O.OpsTRUNC{}, "f16", S.half())
    _ : Unit <- cfo_row("cfo HIP  ", "__ocml_sin_f32(X)", dev_hip(), O.OpsSIN{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo HIP  ", "__ocml_log2_f32(X)", dev_hip(), O.OpsLOG2{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo HIP  ", "__ocml_exp2_f16(X)", dev_hip(), O.OpsEXP2{}, "f16", S.half())
    _ : Unit <- cfo_row("cfo HIP  ", "(1/X)", dev_hip(), O.OpsRECIPROCAL{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo HIP  ", "__ocml_sqrt_f32(X)", dev_hip(), O.OpsSQRT{}, "bf16", S.bfloat16())
    _ : Unit <- cfo_row("cfo HIP  ", "__ocml_trunc_f32(X)", dev_hip(), O.OpsTRUNC{}, "bf16", S.bfloat16())
    _ : Unit <- cfo_row("cfo OPENCL", "sin(X)", dev_opencl(), O.OpsSIN{}, "f32", S.single())
    _ : Unit <- cfo_row("cfo OPENCL", "sqrt(X)", dev_opencl(), O.OpsSQRT{}, "f16", S.half())
    _ : Unit <- cfo_where_row("cfo BASE ", "(X?Y:Z)", dev_base())
    _ : Unit <- cfo_where_row("cfo CLANG", "(X?Y:Z)", dev_clang())
    _ : Unit <- kern_row("kern BASE ", "void", dev_base(), 1)
    _ : Unit <- kern_row("kern CLANG", "void", dev_clang(), 4)
    _ : Unit <- kern_row("kern OPENCL", "__kernel void", dev_opencl(), 1)
    _ : Unit <- kern_row("kern METAL", "kernel void", dev_metal(), 1)
    _ : Unit <- kern_row("kern CUDA ", "extern \"C\" __global__ void __launch_bounds__(1)", dev_cuda(), 1)
    _ : Unit <- kern_row("kern CUDA ", "extern \"C\" __global__ void __launch_bounds__(4)", dev_cuda(), 4)
    _ : Unit <- kern_row("kern HIP  ", "extern \"C\" __attribute__((global)) void __attribute__((amdgpu_flat_work_group_size(1, 1)))", dev_hip(), 1)
    _ : Unit <- kern_row("kern HIP  ", "extern \"C\" __attribute__((global)) void __attribute__((amdgpu_flat_work_group_size(1, 4)))", dev_hip(), 4)
    _ : Unit <- idx_row("idx BASE  sz1 k0 ", "B.x", dev_base(), S.Aalu{}, 1, "R", g_cidx(0))
    _ : Unit <- idx_row("idx BASE  sz8 k0 ", "B[0]", dev_base(), S.Aalu{}, 8, "R", g_cidx(0))
    _ : Unit <- idx_row("idx BASE  sz1 k1 ", "B.y", dev_base(), S.Aalu{}, 1, "R", g_cidx(1))
    _ : Unit <- idx_row("idx BASE  sz1 k3 ", "B.w", dev_base(), S.Aalu{}, 1, "R", g_cidx(3))
    _ : Unit <- idx_row("idx CLANG sz1 k0 ", "B[0]", dev_clang(), S.Aalu{}, 1, "R", g_cidx(0))
    _ : Unit <- idx_row("idx CLANG sz8 k0 ", "B[0]", dev_clang(), S.Aalu{}, 8, "R", g_cidx(0))
    _ : Unit <- idx_row("idx OPENCLsz1 k0 ", "B.x", dev_opencl(), S.Aalu{}, 1, "R", g_cidx(0))
    _ : Unit <- idx_row("idx OPENCLsz8 k0 ", "B[0]", dev_opencl(), S.Aalu{}, 8, "R", g_cidx(0))
    _ : Unit <- idx_row("idx CUDA  sz8 k0 ", "B.x", dev_cuda(), S.Aalu{}, 8, "R", g_cidx(0))
    _ : Unit <- idx_row("idx CUDA  sz16k0", "B[0]", dev_cuda(), S.Aalu{}, 16, "R", g_cidx(0))
    _ : Unit <- idx_row("idx CUDA  sz8 k1 ", "B.y", dev_cuda(), S.Aalu{}, 8, "R", g_cidx(1))
    _ : Unit <- idx_row("idx CUDA  sz8 k3 ", "B.w", dev_cuda(), S.Aalu{}, 8, "R", g_cidx(3))
    _ : Unit <- idx_row("idx HIP   sz1 k0 ", "B.x", dev_hip(), S.Aalu{}, 1, "R", g_cidx(0))
    _ : Unit <- idx_row("idx METAL sz1 k0 ", "B.x", dev_metal(), S.Aalu{}, 1, "R", g_cidx(0))
    _ : Unit <- idx_row("idx BASE  lane   ", "(B)[R]", dev_base(), S.Aalu{}, 1, "R", g_lane())
    _ : Unit <- idx_row("idx CLANG lane   ", "(B)[R]", dev_clang(), S.Aalu{}, 16, "R", g_lane())
    _ : Unit <- idx_row("idx HIP   lane   ", "(B)[R]", dev_hip(), S.Aalu{}, 16, "R", g_lane())
    _ : Unit <- idx_row("idx BASE  regadd ", "(B+R)", dev_base(), S.AReg{}, 1, "(R)", g_cadd0())
    _ : Unit <- idx_row("idx BASE  regnoad", "(B+(R))", dev_base(), S.AReg{}, 1, "(R)", g_cidx(0))
    _ : Unit <- idx_row("idx HIP   regadd ", "(B+R)", dev_hip(), S.AReg{}, 1, "(R)", g_cadd0())
    _ : Unit <- type_row("type BASE  stk4  ", "float4", dev_base(), S.single(), 4, S.Aalu{}, O.OpsSTACK{})
    _ : Unit <- type_row("type BASE  regidx", "float*", dev_base(), S.single(), 1, S.AReg{}, O.OpsINDEX{})
    _ : Unit <- type_row("type BASE  scalar", "float", dev_base(), S.single(), 1, S.Aalu{}, O.OpsCAST{})
    _ : Unit <- type_row("type OPENCLglob ", "__global float*", dev_opencl(), S.single(), 1, S.AGlobal{}, O.OpsINDEX{})
    _ : Unit <- type_row("type METAL glob ", "device float*", dev_metal(), S.single(), 1, S.AGlobal{}, O.OpsINDEX{})
    _ : Unit <- ptr_row("ptr  BASE  stk4  ", "((float4*)(S))", dev_base(), S.single(), 4, S.single(), "S")
    _ : Unit <- ptr_row("ptr  BASE  bitcast", "((int*)(V))", dev_base(), S.int32(), 1, S.single(), "V")
    _ : Unit <- acc_row("acc  BASE  stk4  ", "*((float4*)(S))", dev_base(), S.single(), 4, S.single(), "S")
    _ : Unit <- acc_row("acc  BASE  plain ", "*V", dev_base(), S.single(), 1, S.single(), "V")
    _ : Unit <- cast_row("cast BASE  half  ", "(half)(V)", dev_base(), S.half())
    _ : Unit <- cast_row("cast CLANG half  ", "(__fp16)(V)", dev_clang(), S.half())
    _ : Unit <- legacy_row("leg  BASE  ", "float", dev_base(), S.single())
    _ : Unit <- legacy_row("leg  CLANG ", "__fp16", dev_clang(), S.half())
    _ : Unit <- legacy_row("leg  CLANG ", "_Bool", dev_clang(), S.boolean())
    _ : Unit <- buf_row("buf2 BASE  LOC   ", "float L0[1];", dev_base(), S.ALocal{}, "L0")
    _ : Unit <- buf_row("buf2 OPENCLLOC   ", "__attribute__ ((aligned (16))) __local float L0[1];", dev_opencl(), S.ALocal{}, "L0")
    _ : Unit <- buf_row("buf2 CUDA  LOC   ", "__shared__ __align__(16) float L0[1];", dev_cuda(), S.ALocal{}, "L0")
    _ : Unit <- buf_row("buf2 HIP   LOC   ", "__attribute__((shared, aligned(16)))float L0[1];", dev_hip(), S.ALocal{}, "L0")
    _ : Unit <- buf_row("buf2 METAL LOC   ", "threadgroup __attribute__((aligned(16))) float L0[1];", dev_metal(), S.ALocal{}, "L0")
    _ : Unit <- buf_row("buf2 OPENCLGLOB  ", "float G[1];", dev_opencl(), S.AGlobal{}, "G")
    _ : Unit <- buf_row("buf2 CUDA  GLOB  ", "float G[1];", dev_cuda(), S.AGlobal{}, "G")
    _ : Unit <- buf_row("buf2 METAL GLOB  ", "float G[1];", dev_metal(), S.AGlobal{}, "G")
    _ : Unit <- buf_sz_row("buf2 HIP   sz16  ", "__attribute__((shared, aligned(16)))half L0[16];", dev_hip())
    _ : Unit <- wmma_row("wmma 16_16_16 half ", "WMMA_16_16_16_half_half", wmma_arg([16, 16, 16], S.half()), S.half())
    _ : Unit <- wmma_row("wmma 16_16_16 i8   ", "WMMA_16_16_16_signed_char_signed_char", wmma_arg([16, 16, 16], S.int8()), S.int8())
    _ : Unit <- wmma_row("wmma 8_8_32   bf16 ", "WMMA_8_8_32___bf16___bf16", wmma_arg([8, 8, 32], S.bfloat16()), S.bfloat16())
    _ : Unit <- wmma_row("wmma 16_16_128 fp8 ", "WMMA_16_16_128_float8_e4m3_float8_e4m3", wmma_arg([16, 16, 128], S.fp8e4m3()), S.fp8e4m3())
    _ : Unit <- under_row("under float       ", "float", "float")
    _ : Unit <- under_row("under signed char ", "signed_char", "signed char")
    _ : Unit <- under_row("under unsigned lon", "unsigned_long", "unsigned long")
    _ : Unit <- img_row("img BASE  write   ", "write_only image2d_t", True{})
    _ : Unit <- img_row("img BASE  read    ", "read_only image2d_t", False{})
    _ : Unit <- img_row("img OPENCLwrite   ", "write_only image2d_t", True{})
    _ : Unit <- buft_row("buft BASE ", "const float v0|volatile const float v0|float* v0|volatile float* v0|float* v0", dev_base())
    _ : Unit <- buft_row("buft CLANG", "const float v0|volatile const float v0|float* restrict v0|volatile float* restrict v0|float* restrict v0", dev_clang())
    _ : Unit <- buft_row("buft OPENCL", "const float v0|volatile const float v0|__global float* v0|volatile __global float* v0|__local float* v0", dev_opencl())
    _ : Unit <- buft_row("buft METAL", "constant float& v0|volatile constant float& v0|device float* v0|volatile device float* v0|threadgroup __attribute__((aligned(16))) float* v0", dev_metal())
    _ : Unit <- buft_row("buft CUDA ", "const float v0|volatile const float v0|float* v0|volatile float* v0|float* v0", dev_cuda())
    _ : Unit <- buft_row("buft HIP  ", "const float v0|volatile const float v0|float* v0|volatile float* v0|float* v0", dev_hip())
    _ : Unit <- opt_row("opt devname", "BASE|CLANG|OPENCL|METAL|CUDA|HIP", dev_names())
    _ : Unit <- opt_row("opt barrier", "|__atomic_thread_fence(__ATOMIC_SEQ_CST);|barrier(CLK_LOCAL_MEM_FENCE);|threadgroup_barrier(mem_flags::mem_threadgroup);|__syncthreads();|__builtin_amdgcn_fence(__ATOMIC_RELEASE, \"workgroup\");__builtin_amdgcn_s_barrier();__builtin_amdgcn_fence(__ATOMIC_ACQUIRE, \"workgroup\");", barriers())
    _ : Unit <- opt_row("opt f4style", "(float4){}|(float4)()|float4()|make_float4()|make_float4()", f4s())
    _ : Unit <- opt_row("opt infnan", "INFINITY/NAN|__builtin_inff()/__builtin_nanf(\"\")|INFINITY/NAN|INFINITY/NAN|INFINITY/NAN|INFINITY/NAN", infs())
    _ : Unit <- hipockl_row("hipockl", "extern \"C\" __attribute__((device, const)) size_t __ockl_get_local_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_group_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_size(unsigned int);", )
    _ : Unit <- hipocml_row("hipocml", "extern \"C\" __attribute__((device, pure)) half __ocml_exp2_f16(half);\nextern \"C\" __attribute__((device, pure)) float __ocml_exp2_f32(float);\nextern \"C\" __attribute__((device, pure)) double __ocml_exp2_f64(double);\nextern \"C\" __attribute__((device, pure)) half __ocml_log2_f16(half);\nextern \"C\" __attribute__((device, pure)) float __ocml_log2_f32(float);\nextern \"C\" __attribute__((device, pure)) double __ocml_log2_f64(double);\nextern \"C\" __attribute__((device, const)) half __ocml_sqrt_f16(half);\nextern \"C\" __attribute__((device, const)) float __ocml_sqrt_f32(float);\nextern \"C\" __attribute__((device, const)) double __ocml_sqrt_f64(double);\nextern \"C\" __attribute__((device)) half __ocml_sin_f16(half);\nextern \"C\" __attribute__((device)) float __ocml_sin_f32(float);\nextern \"C\" __attribute__((device)) double __ocml_sin_f64(double);\nextern \"C\" __attribute__((device)) half __ocml_trunc_f16(half);\nextern \"C\" __attribute__((device)) float __ocml_trunc_f32(float);\nextern \"C\" __attribute__((device)) double __ocml_trunc_f64(double);", )
    _ : Unit <- kern2_row("kern2 BASE       ", "void E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_base(), 1, g_bs(S.single()), emit_min(), False{})
    _ : Unit <- kern2_row("kern2 CLANG      ", "\nvoid E_4(float* restrict data0_4, float* restrict data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}\n", dev_clang(), 1, g_bs(S.single()), emit_min(), False{})
    _ : Unit <- kern2_row("kern2 OPENCL     ", "__kernel void E_4(__global float* data0_4, __global float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_opencl(), 1, g_bs(S.single()), emit_min(), False{})
    _ : Unit <- kern2_row("kern2 HIP        ", "\nextern \"C\" __attribute__((global)) void __attribute__((amdgpu_flat_work_group_size(1, 1))) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_hip(), 1, g_bs(S.single()), emit_min(), False{})
    _ : Unit <- kern2_row("kern2 METAL      ", "#include <metal_stdlib>\nusing namespace metal;\nstruct args_t { device float* data0_4; device float* data1_4; };\nkernel void E_4(constant args_t& args [[buffer(0)]], uint3 gid [[threadgroup_position_in_grid]], uint3 lid [[thread_position_in_threadgroup]]) {\n  device float* data0_4 = args.data0_4; device float* data1_4 = args.data1_4;\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_metal(), 1, g_bs(S.single()), emit_min(), False{})
    _ : Unit <- kern2_row("kern2 BASE  pref2", "// generated by tinybendygrad\n#pragma OPENCL EXTENSION cl_khr_fp16 : enable\nvoid E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_base(), 1, g_bs(S.single()), emit_caller(g_caller()), False{})
    _ : Unit <- kern2_row("kern2 BASE  pref0", "\nvoid E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_base(), 1, g_bs(S.single()), emit_prefixed(), False{})
    _ : Unit <- kern2_row("kern2 OPENCL pref2", "// generated by tinybendygrad\n#pragma OPENCL EXTENSION cl_khr_fp16 : enable\n__kernel void E_4(__global float* data0_4, __global float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_opencl(), 1, g_bs(S.single()), emit_caller(g_caller()), False{})
    _ : Unit <- kern2_row("kern2 CUDA  pref2", "typedef unsigned int uint;\n#define INFINITY (__int_as_float(0x7f800000))\n#define NAN (__int_as_float(0x7fffffff))\ntemplate <class T, class F> __device__ __forceinline__ T tg_bitcast(F v) { union U { F f; T t; }; U u; u.f = v; return u.t; }\nextern \"C\" __global__ void __launch_bounds__(1) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_cuda(), 1, g_bs(S.single()), emit_caller(g_caller()), False{})
    _ : Unit <- kern2_row("kern2 HIP   pref2", "\nextern \"C\" __attribute__((global)) void __attribute__((amdgpu_flat_work_group_size(1, 1))) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_hip(), 1, g_bs(S.single()), emit_caller(g_caller()), False{})
    _ : Unit <- kern2_row("kern2 METAL pref2", "#include <metal_stdlib>\nusing namespace metal;\nstruct args_t { device float* data0_4; device float* data1_4; };\nkernel void E_4(constant args_t& args [[buffer(0)]], uint3 gid [[threadgroup_position_in_grid]], uint3 lid [[thread_position_in_threadgroup]]) {\n  device float* data0_4 = args.data0_4; device float* data1_4 = args.data1_4;\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_metal(), 1, g_bs(S.single()), emit_caller(g_caller()), False{})
    _ : Unit <- kern2_row("kern2 OPENCL f16 ", "#pragma OPENCL EXTENSION cl_khr_fp16 : enable\n// generated by tinybendygrad\n#pragma OPENCL EXTENSION cl_khr_fp16 : enable\n__kernel void E_4(__global float* data0_4, __global float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_opencl(), 1, g_bs(S.single()), emit_ocl_half(g_caller()), False{})
    _ : Unit <- kern2_row("kern2 BASE  vol  ", "void E_4(volatile float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_base(), 1, g_bs_vol(), emit_min(), False{})
    _ : Unit <- kern2_row("kern2 CLANG vol  ", "\nvoid E_4(volatile float* restrict data0_4, float* restrict data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}\n", dev_clang(), 1, g_bs_vol(), emit_min(), False{})
    _ : Unit <- kern2_row("kern2 HIP   spec ", "typedef long unsigned int size_t;\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_group_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_size(unsigned int);\nextern \"C\" __attribute__((global)) void __attribute__((amdgpu_flat_work_group_size(1, 1))) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_hip(), 1, g_bs(S.single()), emit_hip_spec(), False{})
    _ : Unit <- kern2_row("kern2 HIP   ockl ", "typedef long unsigned int size_t;\n#define half _Float16\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_group_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_size(unsigned int);\nextern \"C\" __attribute__((device, const)) half __ocml_sqrt_f16(half);\nextern \"C\" __attribute__((device, const)) float __ocml_sqrt_f32(float);\nextern \"C\" __attribute__((global)) void __attribute__((amdgpu_flat_work_group_size(1, 1))) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_hip(), 1, g_bs(S.single()), emit_hip_ocml(), False{})
    _ : Unit <- kern2_row("kern2 HIP   half ", "typedef long unsigned int size_t;\n#define half _Float16\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_group_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_size(unsigned int);\nextern \"C\" __attribute__((global)) void __attribute__((amdgpu_flat_work_group_size(1, 1))) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_hip(), 1, g_bs(S.single()), emit_hip_half(), False{})
    _ : Unit <- kern2_row("kern2 HIP   bf16 ", "typedef long unsigned int size_t;\ntypedef unsigned short hip_bfloat16;\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_group_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_size(unsigned int);\nextern \"C\" __attribute__((global)) void __attribute__((amdgpu_flat_work_group_size(1, 1))) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_hip(), 1, g_bs(S.single()), emit_hip_bf16(), False{})
    _ : Unit <- kern2_row("kern2 HIP   bf16h ", "typedef long unsigned int size_t;\ntypedef unsigned short hip_bfloat16;\n#define half _Float16\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_group_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_size(unsigned int);\nextern \"C\" __attribute__((global)) void __attribute__((amdgpu_flat_work_group_size(1, 1))) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_hip(), 1, g_bs(S.single()), emit_hip_bf16_half(), False{})
    _ : Unit <- kern2_row("kern2 HIP   cdna4", "typedef long unsigned int size_t;\ntypedef __bf16 hip_bfloat16;\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_group_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_size(unsigned int);\nextern \"C\" __attribute__((global)) void __attribute__((amdgpu_flat_work_group_size(1, 1))) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_hip(), 1, g_bs(S.single()), emit_hip_bf16(), True{})
    _ : Unit <- kern2_row("kern2 HIP   inf  ", "#define INFINITY (__builtin_inff())\n#define NAN (__builtin_nanf(\"\"))\ntypedef long unsigned int size_t;\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_group_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_size(unsigned int);\nextern \"C\" __attribute__((global)) void __attribute__((amdgpu_flat_work_group_size(1, 1))) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_hip(), 1, g_bs(S.single()), emit_hip_inf(), False{})
    _ : Unit <- kern2_row("kern2 CUDA  half ", "typedef unsigned int uint;\n#define INFINITY (__int_as_float(0x7f800000))\n#define NAN (__int_as_float(0x7fffffff))\ntemplate <class T, class F> __device__ __forceinline__ T tg_bitcast(F v) { union U { F f; T t; }; U u; u.f = v; return u.t; }\n#include <cuda_fp16.h>\nextern \"C\" __global__ void __launch_bounds__(1) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_cuda(), 1, g_bs(S.single()), emit_cuda(uses_of(True{}, False{}, False{}, False{}, False{}, False{})), False{})
    _ : Unit <- kern2_row("kern2 CUDA  bf16 ", "typedef unsigned int uint;\n#define INFINITY (__int_as_float(0x7f800000))\n#define NAN (__int_as_float(0x7fffffff))\ntemplate <class T, class F> __device__ __forceinline__ T tg_bitcast(F v) { union U { F f; T t; }; U u; u.f = v; return u.t; }\n#include <cuda_bf16.h>\nextern \"C\" __global__ void __launch_bounds__(1) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_cuda(), 1, g_bs(S.single()), emit_cuda(uses_of(False{}, True{}, False{}, False{}, False{}, False{})), False{})
    _ : Unit <- kern2_row("kern2 CUDA  fp8  ", "typedef unsigned int uint;\n#define INFINITY (__int_as_float(0x7f800000))\n#define NAN (__int_as_float(0x7fffffff))\ntemplate <class T, class F> __device__ __forceinline__ T tg_bitcast(F v) { union U { F f; T t; }; U u; u.f = v; return u.t; }\n#include <cuda_fp8.h>\nextern \"C\" __global__ void __launch_bounds__(1) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_cuda(), 1, g_bs(S.single()), emit_cuda(uses_of(False{}, False{}, True{}, False{}, False{}, False{})), False{})
    _ : Unit <- kern2_row("kern2 BASE  alu  ", "void E_4(const float alu0_1, const float alu1_1) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_base(), 1, g_bs_alu(), emit_min(), False{})
    _ : Unit <- kern2_row("kern2 CLANG alu  ", "\nvoid E_4(const float alu0_1, const float alu1_1) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}\n", dev_clang(), 1, g_bs_alu(), emit_min(), False{})
    _ : Unit <- kern2_row("kern2 METAL alu  ", "#include <metal_stdlib>\nusing namespace metal;\nstruct args_t { float alu0_1; float alu1_1; };\nkernel void E_4(constant args_t& args [[buffer(0)]], uint3 gid [[threadgroup_position_in_grid]], uint3 lid [[thread_position_in_threadgroup]]) {\n  float alu0_1 = args.alu0_1; float alu1_1 = args.alu1_1;\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_metal(), 1, g_bs_alu(), emit_min(), False{})
    _ : Unit <- kern2_row("kern2 CUDA  vecs ", "typedef unsigned int uint;\n#define INFINITY (__int_as_float(0x7f800000))\n#define NAN (__int_as_float(0x7fffffff))\ntemplate <class T, class F> __device__ __forceinline__ T tg_bitcast(F v) { union U { F f; T t; }; U u; u.f = v; return u.t; }\n#include <cuda_fp16.h>\nstruct __align__(8) half4 { half x, y, z, w; }; __device__ half4 make_half4(half x, half y, half z, half w) { half4 r={x, y, z, w}; return r; }\nextern \"C\" __global__ void __launch_bounds__(1) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_cuda(), 1, g_bs(S.single()), emit_vecs(g_cuda_vecs()), False{})
    _ : Unit <- kern2_row("kern2 HIP   vecs ", "typedef long unsigned int size_t;\n#define half _Float16\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_group_id(unsigned int);\nextern \"C\" __attribute__((device, const)) size_t __ockl_get_local_size(unsigned int);\ntypedef half half4 __attribute__((ext_vector_type(4)));\nstatic inline __attribute__((device)) half4 make_half4(half x, half y, half z, half w) { return { x, y, z, w }; }\nextern \"C\" __attribute__((global)) void __attribute__((amdgpu_flat_work_group_size(1, 1))) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_hip(), 1, g_bs(S.single()), emit_hip_vecs(g_hip_vecs()), False{})
    _ : Unit <- kern2_row("kern2 CUDA  all  ", "typedef unsigned int uint;\n#define INFINITY (__int_as_float(0x7f800000))\n#define NAN (__int_as_float(0x7fffffff))\ntemplate <class T, class F> __device__ __forceinline__ T tg_bitcast(F v) { union U { F f; T t; }; U u; u.f = v; return u.t; }\n#include <cuda_fp8.h>\n#include <cuda_fp16.h>\n#include <cuda_bf16.h>\nextern \"C\" __global__ void __launch_bounds__(1) E_4(float* data0_4, float* data1_4) {\n  float4 val0 = (*((float4*)((data1_4+0))));\n  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};\n}", dev_cuda(), 1, g_bs(S.single()), emit_cuda(uses_of(True{}, True{}, True{}, False{}, False{}, False{})), False{})
    IO.print("")
