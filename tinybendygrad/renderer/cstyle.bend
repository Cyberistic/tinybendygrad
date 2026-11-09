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
#     (SQRT, TRUNC, SIN, LOG2, EXP2, RECIP) plus Clang's FDIV, and every
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
     arg: KUArg, srcs: List<&2, U32>, cc: U32}

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
  # `Ops.WMMA`'s arg upstream is `(dims, dtype_in, ...)` and cstyle.py:114 builds the
  # helper's NAME from both: `WMMA_{'_'.join(dims)}_{dt_in.name}_{dt_out.name}`.
  KAWmma{dims: List<&2, U32>, dt_in: S.Dt}

# `r` IS THE RENDERED TEXT OF EVERY UOP, STORED NEWEST-FIRST BEHIND ITS OWN LENGTH.
# cstyle.py keeps it as a dict keyed by UOp, which is O(1) in both directions; a `List` charges the
# ABSOLUTE INDEX for a lookup and THE WHOLE PREFIX for an append or a set (MEASURED: `rt` 233,235 of the
# 292,446 list steps a 405-uop render still took after §76, `List_set` another 0.64 ms a turn). Reversed,
# `st_put` is a CONS, `st_set` on the current uop is index 0, and `rt`'s index is the SRC-TO-CURRENT
# DISTANCE -- MEASURED on the wire, 72.9 mean against 168.5 absolute. `PARITY.md` §77.
# **THE RENDERED TEXT OF A UOP IS A LIST OF PIECES, NOT A STRING.** MEASURED (`PARITY.md` §93): the renderer
# fed 77,500 characters to `String.concat` to emit 4,426 -- a 17.5x amplification -- because every expression
# materialised its text and every parent COPIED it again. Pieces are Consed instead, and the one
# `String.join` happens at the statement, so a character is copied once (§95 for the design).
# **A 16-WAY BLOCKED VIEW, WITH THE VARIABLE FIRST BLOCK MEASURED RATHER THAN ASSUMED.** `rtp` is called
# 941 times a render and each call walked the source map to the uop's position -- MEASURED (`PARITY.md`
# §124): a mean index of 70.8, i.e. ~66,600 cons steps a render for 941 lookups. `ku_at`'s view is
# block-16 (`§76`), and the source map is APPEND-AT-FRONT (`st_put` prepends), so **block 0 holds the newest
# entries and its length VARIES**: it is `((n-1) & 15) + 1`, and every block after it holds sixteen.
#
# **§120 BUILT THIS VIEW AND REVERTED IT AT 0.9978/0.9883 -- WITH A BUG IN IT**: the first version used
# `block = d / 16`, which is WRONG for a variable first block, and the note records the correction
# without a re-measurement. THIS IS THE CORRECTED VERSION.
type Rows is Data:
  Rows{ts: List<&2, List<&2, List<&2, String>>>, n: U32}

def Rows.ts(x: Rows) -> List<&2, List<&2, List<&2, String>>>:
  match x:
    case Rows{ts, n}: ts



def Rows.n(x: Rows) -> U32:
  match x:
    case Rows{ts, n}: n

# BLOCK 0'S LENGTH: THE NEWEST `((n-1) & 15) + 1` ENTRIES, AND EVERY BLOCK AFTER IT HOLDS SIXTEEN.
def Rows.b0(+r: Rows) -> U32:
  +n = Rows.n(r)
  Bool.pick(U32, U32.is_zero(n), 0, U32.add(U32.and(U32.sub(n, 1), 15), 1))

def Rows.bi(+r: Rows, +d: U32) -> U32:
  +b = Rows.b0(r)
  Bool.pick(U32, U32.is_gt(b, d), 0, U32.add(1, U32.shrn(U32.sub(d, b), 4n)))

def Rows.off(+r: Rows, +d: U32) -> U32:
  +b = Rows.b0(r)
  Bool.pick(U32, U32.is_gt(b, d), d, U32.and(U32.sub(d, b), 15))

def Rows.blk(+r: Rows, bi: U32) -> List<&2, List<&2, String>>:
  Maybe.default(&2, List<&2, List<&2, String>>,
    List.get(&2, List<&2, List<&2, String>>, Rows.ts(r), U32.to_nat(bi)), Nil{})

def Rows.get(+r: Rows, +d: U32) -> List<&2, String>:
  +b = Rows.blk(r, Rows.bi(r, d))
  Maybe.default(&2, List<&2, String>,
    List.get(&2, List<&2, String>, b, U32.to_nat(Rows.off(r, d))), Nil{})

type St is Data:
  St{r: Rows, kernel: List<&2, String>, bufs: List<&2, BArg>,
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
# into an underscore.
#
# **AND THE FIVE ARE A `match`, NOT A SPLIT, AND THAT IS A MEASURED CHANGE.** The port used to SPLIT
# the name on ' ' and rejoin it with '_', which is exact -- but the prelude's `String.split` is ONE
# RECURSION PER CHARACTER, so each split costs two `slice`s and a token concatenation per character.
# MEASURED on the 642-uop wire: `under_split` **400** times a render, which is **2,620** recursive
# `String.split` calls and **13,853** `char_len` calls -- the largest remaining term in the turn.
#
# **THE NAME IS FROM A CLOSED SET, AND THAT IS THE PORT'S OWN FACT.** `rd_base_name` reads
# `rd_base_dev`, which is a `match` on the device over a `match` on the dtype's SHORT CODE, so every
# name it can produce is one of the twenty-six literals in `rd_base_plain` / `rd_base_clang` /
# `rd_base_opencl` / `rd_base_metal` / `rd_base_cuda` / `rd_base_hip` -- plus the short code itself,
# which is the `_` arm's passthrough. **EXACTLY FIVE OF THOSE CONTAIN A SPACE** (`signed char`,
# `unsigned char`, `unsigned int`, `unsigned long`, `unsigned short`), and the port's own comment
# above says so. So the split is a `match` on five literals, and the `_` arm is `nm` UNCHANGED --
# which is exact, because no other name in the set contains a space.
#
# ===========================================================================

# **THE FIVE, AND THE UNDERSCORED FORM IS A LITERAL.** `cstyle.py:189` is
# `name.replace(" ", "_") if sz > 1 else name` -- the replace is UNCONDITIONAL on the `sz > 1` branch,
# and there is NO "has a space" test upstream. The port had one (`has_space`) because the port's
# `under` was the general replace and the port wanted to avoid it for a name with no space -- and that
# test cost a split. **⇒ THE FIVE ARE A `match` AND THE `_` ARM IS THE NAME UNCHANGED, WHICH IS THE
# ANSWER FOR EVERY OTHER NAME IN THE SET.** So `has_space` IS GONE: a name with no space IS its own
# underscored form, and the underscored form is what the dtype path needs.
#
# **AND THE MATCH IS ON THE SHORT CODE, NOT ON THE C NAME, AND THAT IS THE SECOND MEASURED CHANGE.**
# A `match` on a String in Bend COMPILES TO PER-CHARACTER COMPARES WITH A `slice` PER CHARACTER
# (`PARITY.md` §122), so matching the eleven-character C name `"signed char"` costs eleven slices --
# which is the same per-character cost the split paid, and MEASURED: the first cut of this change
# replaced 400 splits with 200 five-arm string matches and the CPU clock read 0.9938, i.e. NOTHING.
# **THE SHORT CODE IS TWO TO FOUR CHARACTERS** (`i8`, `u8`, `u16`, `u32`, `u64`, `f32`, ...) and it is
# what `rd_base_dev` ALREADY matches on, so matching the code is the cheap half of the comparison.
#
# THE SET IS CLOSED, AND THAT IS THE PORT'S OWN FACT: `rd_base_name` reads `rd_base_dev`, which is a
# `match` on the device over a `match` on the dtype's SHORT CODE, so every name it can produce is one of
# the twenty-six literals in `rd_base_plain` / `rd_base_clang` / `rd_base_opencl` / `rd_base_metal` /
# `rd_base_cuda` / `rd_base_hip` -- plus the short code itself, which is the `_` arm's passthrough.
# **EXACTLY FIVE OF THOSE CONTAIN A SPACE** (`signed char`, `unsigned char`, `unsigned int`,
# `unsigned long`, `unsigned short`), and the port's own comment above says so.
#
# **⇒ AND THE DEVICE MATTERS ONLY WHERE IT OVERRIDES A SPACED CODE.** MEASURED over the six devices:
# OpenCL overrides ALL FIVE (`i8`->`char`, `u8`->`uchar`, `u16`->`ushort`, `u32`->`uint`, `u64`->`ulong`),
# Metal and CUDA override `u32` (->`uint`), and Clang, HIP and the base override NONE. So the
# underscored form is the plain one for every device but OpenCL, Metal and CUDA's `u32` -- and THAT is
# what `under_code` answers, in a match on the short code.
#
# **⇒ AND THE TABLE WAS CHECKED OVER EVERY (DEVICE, CODE) PAIR, NOT BY READING IT.** The first cut
# forgot OpenCL's `u32` -- OpenCL maps `u32` to `uint`, which has NO SPACE, so its underscored form is
# `uint` and not `unsigned_int` -- and the probe over all 120 pairs found it. MEASURED: the probe calls
# the COMPILED `under_code` and `rd_base_dev` over six devices and twenty codes and compares against a
# table computed from the port's OWN `rd_base_*` matches; the fixed table is **120 of 120**.
# **THE GENERAL REPLACE, FOR THE ONE CALL THAT NEEDS IT.** `wmma_name_of` is
# `f"WMMA_{dims}_{in}_{out}".replace(" ", "_")` -- UNCONDITIONAL, and its parts are `U32.show` and the
# dtype's SHORT CODE, so they carry no space today -- but "today" is not a proof, and this def is the
# general one. MEASURED: it is called ONCE a render (the WMMA path), so the general replace is not on
# the hot path.
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

def under_general(nm: String) -> String: under_tail.go(under_split(nm), False{})

def under(nm: String) -> String: under_general(nm)

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

# THE NAME, with the `sz > 1` underscore. `cstyle.py:189` is
# `name.replace(" ", "_") if sz > 1 else name`, and there is NO "has a space" test upstream -- the
# replace is unconditional on the `sz > 1` branch. `under_code` IS that replace (see its own comment),
# so `rd_name_at(dev, d, True{})` IS the replace and `rd_name_at(dev, d, False{})` IS the plain name.
# **THE TYPE NAME IS A MATCH, NOT A MAP, AND THAT IS A MEASURED CHANGE.** `type_map.of(dev)` BUILDS the
# device's fourteen-to-sixteen-entry `Map` on every call, its keys are `String`s, and the port's `Map` is a
# hashed trie: a profile of the SHIPPED path (`.agents/slop/cpuseam/out/live-*.js`, the artifact the daemon
# loads) put `nat_divmod` at 17.5% and `char_len` at 7.2%, reached through `Map_bit` / `Map_bit_go` /
# `Map_seek` / `Map_diff` -- i.e. hashing a dtype name and walking trie levels, once per dtype render.
#
# The six maps are the transcription of upstream's six dicts, each an OVERLAY on the base, and the lookup's
# default is THE NAME ITSELF (`cstyle.py`'s `type_map.get(dtype, dtype.name)`). That is exactly a `match`
# with a `_` arm, so the transcription survives -- it is just no longer a data structure that has to be
# built before it can be read. THE SIX ARMS BELOW ARE THE SIX DICTS, entry for entry; the comments that
# pin each one (the fp8 group ABSENT on OpenCL, `bf16` NOT remapped on HIP, the FNUZ pair on CUDA) live on
# `type_map.*` above, which is kept as the transcription of record.

def rd_base_plain(nm: String) -> String:
  match nm:
    case "i8": "signed char"
    case "u8": "unsigned char"
    case "i16": "short"
    case "u16": "unsigned short"
    case "i32": "int"
    case "u32": "unsigned int"
    case "i64": "long"
    case "u64": "unsigned long"
    case "f16": "half"
    case "bf16": "__bf16"
    case "f32": "float"
    case "f64": "double"
    case _: nm

def rd_base_clang(nm: String) -> String:
  match nm:
    case "bool": "_Bool"
    case "f16": "__fp16"
    case _: rd_base_plain(nm)

def rd_base_opencl(nm: String) -> String:
  match nm:
    case "i8": "char"
    case "u8": "uchar"
    case "u16": "ushort"
    case "u32": "uint"
    case "u64": "ulong"
    case "bf16": "ushort"
    case _: rd_base_plain(nm)

def rd_base_metal(nm: String) -> String:
  match nm:
    case "u32": "uint"
    case "bf16": "bfloat"
    case _: rd_base_plain(nm)

def rd_base_cuda(nm: String) -> String:
  match nm:
    case "fp8e5m2": "__nv_fp8_e5m2"
    case "fp8e4m3": "__nv_fp8_e4m3"
    case "bf16": "nv_bfloat16"
    case "u32": "uint"
    case _: rd_base_plain(nm)

def rd_base_hip(nm: String) -> String:
  match nm:
    case "fp8e4m3": "hip_fp8"
    case "fp8e5m2": "hip_bf8"
    case "fp8e4m3fnuz": "hip_fp8"
    case "fp8e5m2fnuz": "hip_bf8"
    case _: rd_base_plain(nm)

def rd_base_dev(dev: U32, nm: String) -> String:
  match dev:
    case 1: rd_base_clang(nm)
    case 2: rd_base_opencl(nm)
    case 3: rd_base_metal(nm)
    case 4: rd_base_cuda(nm)
    case 5: rd_base_hip(nm)
    case _: rd_base_plain(nm)


# OPENCL OVERRIDES ALL FIVE SPACED CODES, SO ITS UNDERSCORED FORM IS THE OVERRIDE'S.
def under_code_opencl(dev: U32, plain: String, opencl: String) -> String:
  match dev:
    case 2: opencl
    case _: plain

# OPENCL, METAL AND CUDA OVERRIDE `u32` ALONE, AND THE OTHERS DO NOT.
def under_code_u32(dev: U32, plain: String) -> String:
  match dev:
    case 2: "uint"
    case 3: "uint"
    case 4: "uint"
    case _: plain

def under_code(dev: U32, nm: String) -> String:
  match nm:
    case "i8": under_code_opencl(dev, "signed_char", "char")
    case "u8": under_code_opencl(dev, "unsigned_char", "uchar")
    case "u16": under_code_opencl(dev, "unsigned_short", "ushort")
    case "u32": under_code_u32(dev, "unsigned_int")
    case "u64": under_code_opencl(dev, "unsigned_long", "ulong")
    case _: rd_base_dev(dev, nm)

# **`rd_base_name` IS COMPUTED ONCE, AND THAT IS A MEASURED CHANGE.** `type_map.of(dev)` BUILDS the device's
# type map on every call -- a `Map` whose keys are Strings, so each insert hashes a string -- and this line
# called `rd_base_name` THREE times, while `rd_body` below called `rd_name` in both arms of a `Bool.pick`,
# i.e. SIX map builds to render ONE dtype. MEASURED with `bun --cpu-prof` on a 405-uop kernel: `render_dtype`
# was 58% of the whole render and `Map_set` inside `type_map_clang` was 53%, with `char_len` 15% (String-key
# hashing walks the key a character at a time). Nothing about the answer changes: the same name is looked up
# once instead of six times.
def rd_base_name(+dev: U32, +d: S.Dt) -> String: rd_base_dev(dev, dt_name(d))

# **`Bool.pick` EVALUATES BOTH ARMS, AND THAT IS MEASURED.** `Bool.pick` is a `match` in the prelude, but
# the COMPILER turns it into a FUNCTION CALL, so its two arms are JS ARGUMENTS and both are built before
# the call. MEASURED on the 642-uop wire: `rd_body_at` **100** calls, `rd_name_at` **200** calls --
# TWICE the number of bodies -- and every one of them built BOTH the underscored name and the plain one.
# With the split-based `under` that was **400** `under_split` calls a render.
#
# **⇒ SO THE ARMS ARE CHOSEN WITH A `match`, WHICH THE COMPILER MAKES A REAL `if`.** A `match` on a
# `Bool` is a branch, and only the taken arm runs.
#
# **⇒ AND THE UNDERSCORED ARM TAKES THE DEVICE AND THE SHORT CODE, NOT THE C NAME.** The C name is up to
# thirteen characters (`"unsigned short"`) and a `match` on it is a per-character compare with a `slice`
# per character; the SHORT CODE is two to four (`u16`) and it is what `rd_base_dev` already matches on.
# So the underscored arm reads the code and the device -- MEASURED: `under_code` **83** calls a render
# and the whole underscored arm costs a handful of slices each.
def rd_name_at(+dev: U32, +d: S.Dt, vect: Bool) -> String:
  match vect:
    case True{}: under_code(dev, dt_name(d))
    case False{}: rd_base_name(dev, d)

def rd_name(+dev: U32, +d: S.Dt, vect: Bool) -> String: rd_name_at(dev, d, vect)

# `Bool.pick(-A, c, a, b)` ANSWERS `a` WHEN `c` IS TRUE -- so the UNDERSCORED
# spelling is the `b` arm and the plain one is the `a` arm. This line had them the
# other way round for one compile cycle, which underscored the four SCALAR
# columns and left the two `sz > 1` columns alone: `rd BASE unsigned char` came
# back `unsigned_char*|...|unsigned char4` where CPython says
# `unsigned char*|...|unsigned_char4`. NO `float` ROW COULD SEE IT -- a name with
# no space renders the same either way -- which is exactly why the gate carries a
# `signed char`-shaped row, and it is the same trap `render.bend` hit on
# `acall_tail` and that `bend2-constraints.md` rule 7 already records.



# **THE `sz > 1` TEST IS A BRANCH, NOT A `Bool.pick`.** `Bool.pick`'s arms are eager (see `rd_name_at`),
# so the old line built the vector spelling AND the scalar spelling for EVERY body. MEASURED: `rd_body_at`
# 100 calls and `rd_name_at` 200 -- twice the number of bodies. A `match` on the test runs one arm.
def rd_body_at(+dev: U32, +d: S.Dt, +sz: U32, vect: Bool) -> String:
  match vect:
    case True{}: String.concat([rd_name_at(dev, d, True{}), U32.show(sz)])
    case False{}: rd_name_at(dev, d, False{})

def rd_body(+dev: U32, +d: S.Dt, +sz: U32) -> String:
  rd_body_at(dev, d, sz, U32.is_gt(sz, 1))

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
# and `RECIP` entirely (they become libcalls the compiler lowers, cstyle.py:
# :288) and adds `FDIV`; CUDA and HIP keep all twenty-one and override six; Metal
# overrides one (`SIN` -> `precise::sin`); OpenCL and QCOM change nothing. A
# dropped op is a `KeyError` in Python, so the dropped arm is a gate row.
# ===========================================================================

def cfo_unary(nm: String, +x: List<&2, String>) -> List<&2, String>: List.concat(&2, String, [[nm, "("], x, [")"]])

# `f"(1/{x})"` and `f"-{x}"` are NEITHER of them the unary `f"{nm}({x})"` shape,
# so they are their own defs rather than a "prefix" helper with an empty name.
# `cfo_prefixed("", x)` would be `f"-{x}"` by accident and `cfo_prefixed("1/", x)`
# would be `f"-1/({x})"` -- the unary template has the parens INSIDE, so neither
# spelling of a prefix template reaches these two. MEASURED by the oracle:
# RECIP is `(1/X)` and NEG is `-X`.
def cfo_recip(+x: List<&2, String>) -> List<&2, String>: List.concat(&2, String, [["(1/"], x, [")"]])

def cfo_neg(+x: List<&2, String>) -> List<&2, String>: List.concat(&2, String, [["-"], x])

def cfo_bin(+a: List<&2, String>, sym: String, +b: List<&2, String>) -> List<&2, String>: List.concat(&2, String, [["(", ], a, [sym], b, [")"]])

def cfo_tern(+a: List<&2, String>, +b: List<&2, String>, +c: List<&2, String>) -> List<&2, String>: List.concat(&2, String, [["("], a, ["?"], b, [":"], c, [")"]])

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
def cfo_unhandled(op: O.Op) -> List<&2, String>: [String.concat(["UNHANDLED(Ops.", O.Ops.name.of(op), ")"])]

# `xs` is the src-name list, `xs0`/`xs1`/`xs2` its three positional reads. `nd` is
# the number of srcs, which is the arity test: WHERE has three and everything
# else has two or one, and `head`/`nth` on an empty list is the BOTTOM of the
# list rather than a crash -- so an op reached with the wrong arity renders a
# visibly wrong string instead of a wrong type.
def xs_at(xs: List<&2, List<&2, String>>, n: Nat) -> List<&2, String>:
  Maybe.default(&2, List<&2, String>, List.get(&2, List<&2, String>, xs, n), ["?"])

def cfo_xs1(xs: List<&2, List<&2, String>>) -> List<&2, String>: xs_at(xs, 0n)

def cfo_xs2(xs: List<&2, List<&2, String>>) -> List<&2, String>: xs_at(xs, 1n)

def cfo_xs3(xs: List<&2, List<&2, String>>) -> List<&2, String>: xs_at(xs, 2n)

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
def code_for_base.of(op: O.Op, +xs: List<&2, List<&2, String>>) -> List<&2, String>:
  match op:
    case O.OpsSQRT{}: cfo_unary("sqrt", cfo_xs1(xs))
    case O.OpsRECIP{}: cfo_recip(cfo_xs1(xs))
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
    case O.OpsTRUNCMOD{}: cfo_bin(cfo_xs1(xs), "%", cfo_xs2(xs))
    case O.OpsTRUNCDIV{}: cfo_bin(cfo_xs1(xs), "/", cfo_xs2(xs))
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
# and `EXP2`/`SIN`/`LOG2`/`RECIP` are DELETED (cstyle.py:288-291). The
# comprehension is `{k:v for k,v in base.items() if k not in [EXP2, SIN, LOG2,
# TRUNC, RECIP]}` and then TRUNC and FDIV and SQRT are re-set, so TRUNC
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

def code_for_clang.of(op: O.Op, +xs: List<&2, List<&2, String>>, +d: S.Dt) -> List<&2, String>:
  match op:
    case O.OpsSQRT{}: cfo_unary(ocml_or("__builtin_sqrt", "f", is_f64(d)), cfo_xs1(xs))
    case O.OpsTRUNC{}: cfo_unary(ocml_or("__builtin_trunc", "f", is_f64(d)), cfo_xs1(xs))
    case O.OpsFDIV{}: cfo_bin(cfo_xs1(xs), "/", cfo_xs2(xs))
    case O.OpsEXP2{}: cfo_unhandled(op)
    case O.OpsSIN{}: cfo_unhandled(op)
    case O.OpsLOG2{}: cfo_unhandled(op)
    case O.OpsRECIP{}: cfo_unhandled(op)
    case _: code_for_base.of(op, xs)

# METAL: `SIN` is the ONLY override and it is `precise::sin` for every dtype
# (cstyle.py:376).
def code_for_metal.of(op: O.Op, +xs: List<&2, List<&2, String>>, +d: S.Dt) -> List<&2, String>:
  match op:
    case O.OpsSIN{}: cfo_unary("precise::sin", cfo_xs1(xs))
    case _: code_for_base.of(op, xs)

# CUDA: `htrunc`/`hsin`/`hlog2`/`hexp2`/`hsqrt`/`hrcp` for half and bfloat16, and
# the PLAIN form otherwise (cstyle.py:432-438). Six ops, one `Bool`.
def cuda_pick.go(b: Bool, hnm: String, nm: String, +x: List<&2, String>) -> List<&2, String>:
  match b:
    case True{}: cfo_unary(hnm, x)
    case False{}: cfo_unary(nm, x)

def cuda_pick(half: Bool, hnm: String, nm: String, +x: List<&2, String>) -> List<&2, String>:
  cuda_pick.go(half, hnm, nm, x)

# HIP: `_ocml(op)` is `f"__ocml_{op}_f{ {half:16, double:64}.get(dtype, 32)}({x})"`
# (cstyle.py:493) -- the WIDTH, not a dtype name, and 32 is the default for
# everything else including f32. So the map is a two-entry lookup with a 32
# fallback and the `f` is always there.
def ocml_bits(+d: S.Dt) -> U32:
  Bool.pick(U32, O.eq_dt(d, S.half()), 16, Bool.pick(U32, is_f64(d), 64, 32))

def ocml_name(op: String, +d: S.Dt) -> String:
  String.concat(["__ocml_", op, "_f", U32.show(ocml_bits(d))])

def code_for_hip.of(op: O.Op, +xs: List<&2, List<&2, String>>, +d: S.Dt) -> List<&2, String>:
  match op:
    case O.OpsTRUNC{}: cfo_unary(ocml_name("trunc", d), cfo_xs1(xs))
    case O.OpsSIN{}: cfo_unary(ocml_name("sin", d), cfo_xs1(xs))
    case O.OpsLOG2{}: cfo_unary(ocml_name("log2", d), cfo_xs1(xs))
    case O.OpsEXP2{}: cfo_unary(ocml_name("exp2", d), cfo_xs1(xs))
    case O.OpsSQRT{}: cfo_unary(ocml_name("sqrt", d), cfo_xs1(xs))
    case _: code_for_base.of(op, xs)

def cuda_rcp.go(b: Bool, +x: List<&2, String>) -> List<&2, String>:
  match b:
    case True{}: cfo_unary("hrcp", x)
    case False{}: cfo_recip(x)

def cuda_rcp(b: Bool, +x: List<&2, String>) -> List<&2, String>: cuda_rcp.go(b, x)

def code_for_cuda.of(op: O.Op, +xs: List<&2, List<&2, String>>, +d: S.Dt) -> List<&2, String>:
  match op:
    case O.OpsTRUNC{}: cuda_pick(is_half(d), "htrunc", "trunc", cfo_xs1(xs))
    case O.OpsSIN{}: cuda_pick(is_half(d), "hsin", "sin", cfo_xs1(xs))
    case O.OpsLOG2{}: cuda_pick(is_half(d), "hlog2", "log2", cfo_xs1(xs))
    case O.OpsEXP2{}: cuda_pick(is_half(d), "hexp2", "exp2", cfo_xs1(xs))
    case O.OpsSQRT{}: cuda_pick(is_half(d), "hsqrt", "sqrt", cfo_xs1(xs))
    case O.OpsRECIP{}: cuda_rcp(is_half(d), cfo_xs1(xs))
    case _: code_for_base.of(op, xs)

# THE DISPATCH. Five devices and the base, and OpenCL and QCOM are the BASE --
# measured: neither overrides a single ALU op, and the gate's `cfo` rows are
# what says so rather than a comment.
def code_for_op.of(+dev: U32, op: O.Op, xs: List<&2, List<&2, String>>, +d: S.Dt) -> List<&2, String>:
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
    case KU{op, dtype, addr, numel, shape, arg, srcs, cc}: op

def KU.dtype(k: KU) -> S.Dt:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs, cc}: dtype

def KU.addr(k: KU) -> S.Addr:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs, cc}: addr

def KU.numel(k: KU) -> U32:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs, cc}: numel

def KU.shape(k: KU) -> List<&2, U32>:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs, cc}: shape

def KU.arg(k: KU) -> KUArg:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs, cc}: arg

def KU.srcs(k: KU) -> List<&2, U32>:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs, cc}: srcs

def KU.cc(k: KU) -> U32:
  match k:
    case KU{op, dtype, addr, numel, shape, arg, srcs, cc}: cc

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

# **A BOOL CONST IS AN INT CONST.** The `boolean()` arm of `ku_const_cast_int` was ALREADY WRITTEN
# (`"0"`/`"1"`, which is cstyle.py:31's `lambda ctx,c: "1" if c.val else "0"`), but nothing could reach
# it: this only matched `CInt`, so a `CBool` fell through const_int -> const_float -> the GENERIC cast
# and rendered as `((_Bool)())` -- an EMPTY expression. MEASURED 2026-11-03: `exp` is the only kernel in
# the 31-case battery that still diverged, and its C was `3782 B` against upstream's `3742 B` on exactly
# two lines, each `!=((_Bool)())` where upstream has `!=1`.
def ku_const_int(c: O.Const) -> Maybe<&1, H.I64>:
  match c:
    case O.CInt{i}: Some{i}
    case O.CBool{b}: Some{H.i64_of_i32(Bool.to_u32(b))}
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

def KUArg.wmma_dims(a: KUArg) -> List<&2, U32>:
  match a:
    case KAWmma{dims, dt_in}: dims
    case _: Nil{}

def KUArg.wmma_dt_in(a: KUArg) -> S.Dt:
  match a:
    case KAWmma{dims, dt_in}: dt_in
    case _: S.single()

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

def rtp(+r: Rows, +i: U32) -> List<&2, String>:
  Rows.get(r, U32.sub(U32.sub(Rows.n(r), 1), i))

def rt(+r: Rows, +i: U32) -> String: String.join(rtp(r, i), "")

# **STRIPPING THE OUTER PARENTHESES OF PIECES COSTS NO CHARACTERS.** `cfo_bin` emits `(` and `)` as their
# OWN pieces, so a source with the parent's op is `["(", ...inner..., ")"]` and the strip is dropping those
# two pieces -- the same answer as `H.strip_parens` on the joined string, without joining it (§95.1).
# **A 16-WAY BLOCKED VIEW, BECAUSE `List.get` IS O(INDEX) AND THIS LIST IS INDEXED 1,915 TIMES PER
# RENDER.** `ku_at` was 292,722 of the 805,127 list steps a 405-uop render took (MEASURED, `PARITY.md` §76).
# Sixteen is the block that minimises `i/16 + i%16` at this length: MEASURED off the wire, the mean source
# index costs 168.5 steps flat and 17.9 blocked. `chunks_of` builds it in one forward pass.
def chunk_close(+cur: List<&2, KU>, +done: List<&2, List<&2, KU>>) -> List<&2, List<&2, KU>>:
  match cur:
    case Nil{}: done
    case _ <> _: List.append(&2, List<&2, KU>, done, [List.reverse(&2, KU, cur)])

def chunks_of.go(+xs: List<&2, KU>, +cur: List<&2, KU>, +done: List<&2, List<&2, KU>>, fuel: Nat) -> List<&2, List<&2, KU>>:
  match xs:
    case Nil{}: chunk_close(cur, done)
    case h <> t:
      match fuel:
        case 0n: chunks_of.go(t, [h], chunk_close(cur, done), 15n)
        case 1n+k: chunks_of.go(t, List.append(&2, KU, [h], cur), done, k)

def chunks_of(+kus: List<&2, KU>) -> List<&2, List<&2, KU>>:
  chunks_of.go(kus, Nil{}, Nil{}, 16n)

def ku_at.go(m: Maybe<&2, List<&2, KU>>, off: Nat) -> Maybe<&2, KU>:
  match m:
    case Some{c}: List.get(&2, KU, c, off)
    case None{}: None{}

def ku_at(+kus: List<&2, List<&2, KU>>, +i: U32) -> Maybe<&2, KU>:
  ku_at.go(List.get(&2, List<&2, KU>, kus, U32.to_nat(U32.shrn(i, 4n))), U32.to_nat(U32.and(i, 15)))

# EVERY `match` IN THIS BLOCK HAS A PARAMETER FOR ITS SCRUTINEE, because Bend
# REFUSES A COMPUTED VALUE: `match ku_at(kus, i):` IS REFUSED ("a match cannot
# scrutinize a computed value"), AND SO IS A NESTED `match` ON A CALL. THE
# `.go` SHAPE IS THEREFORE THE HOUSE STYLE HERE: THE HELPER TAKES THE `Maybe`
# AS A PARAMETER AND THE CALLER PASSES THE CALL.
def ku_op_at.go(m: Maybe<&2, KU>) -> O.Op:
  match m:
    case Some{k}: KU.op(k)
    case None{}: O.OpsNOOP{}

def ku_op_at(+kus: List<&2, List<&2, KU>>, i: U32) -> O.Op: ku_op_at.go(ku_at(kus, i))  def ku_is_const_at.go(m: Maybe<&2, KU>) -> Bool:
  match m:
    case Some{k}: KUArg.is_const(KU.arg(k))
    case None{}: False{}
# **⇒ AND THE OP EQUALITY IS A MATCH ON THE TWO TAGS, NOT A COMPARISON OF TWO NUMBERS.** MEASURED
# (`PARITY.md` §138): `O.eq_op` IS `U32.is_eq(Ops.value(x), Ops.value(y))`, **⇒ AND `Ops.value`
# COMPILES TO A **76-ARM `===` CHAIN ON THE TAG** (THE GENERATED CODE IS `if (_op_0.$ ===
# "OpsSPECIAL") ... else if (_op_0.$ === "OpsBUFFER")`), **⇒ SO `O.eq_op` WAS ~152 STRING
# COMPARISONS.** MEASURED ON THE 782-UOP WIRE: **30,640 `Ops.value` CALLS AND 15,320 `O.eq_op` CALLS A
# RENDER** (~40 AND ~20 A UOP), **⇒ AND EVERY SINGLE `Ops.value` CALL CAME FROM `O.eq_op`** (30,640 =
# 2 x 15,320). **⇒ AND THE PROFILE PUTS THEM AT `uop_ops_Ops_value` 0.293 ms AND `uop_ops_eq_op`
# 0.193 ms A TURN -- A THIRD OF THE PORT's 1.412 ms.**
#
# **⇒ AND THE PORT ALREADY SPELLS VARIANT EQUALITY THIS WAY** (`ops.bend`'s OWN `eq_opt_u32`,
# `eq_opt_str`, `eq_optbool` AND `eq_optarg` ALL USE `match x y:` WITH ONE ARM PER VARIANT) -- **⇒ AND
# A MATCH ON TWO SCRUTINEES COMPILES TO NESTED TAG COMPARISONS** (MEASURED IN THE GENERATED CODE:
# `if (_x_0.$ === "OpsA") { if (_y_0.$ === "OpsA") ... }`), **⇒ SO THE AVERAGE COST IS TWO
# COMPARISONS INSTEAD OF 152.**
#
# **⇒ AND THIS IS A LOCAL SPELLING BECAUSE `ops.bend`'s OWN `eq_op` IS NOT MINE TO CHANGE** (ANOTHER
# UNIT HAS AN UNCOMMITTED EDIT IN IT), **⇒ AND THE 24 CALL SITES IN THIS FILE ARE.**
#
# **⇒⇒⇒ THE OP PREDICATES, **ONE PER LITERAL**, AND **EACH IS **ONE** COMPARISON**.
#
# ⇒⇒⇒ **WHY THEY EXIST, AND IT IS MEASURED.** `eq_op` IS **A MATCH ON TWO SCRUTINEES**, AND A
# MATCH IN THIS LANGUAGE IS **A LINEAR CHAIN OF TAG COMPARISONS** -- **75 ARMS** -- ⇒⇒⇒ ⇒⇒⇒ SO
# `eq_op(op, O.OpsADD{})` PAYS **THE CHAIN POSITION OF `OpsADD`** COMPARES, WHICH IS **30** AT
# THE ENUM's ORDER. ⇒⇒⇒ ⇒⇒⇒ AND AT **18 OF THE 19** CALL SITES THE SECOND ARGUMENT IS **A
# LITERAL**, ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ SO THE QUESTION IS *IS THIS OP's TAG THE CONSTANT `OpsADD`?* -- WHICH IS
# **ONE** COMPARISON WHEN IT IS WRITTEN AS A MATCH **ON THE VARIABLE** WITH THE LITERAL AS THE
# **ONLY** ARM, WHICH IS WHAT `is_add(op)` IS.
#
# ⇒⇒⇒ ⇒⇒⇒ MEASURED, IN ONE PROGRAM, ON THE SAME WORKLOAD (THE ELEVEN OPS THE RENDER SEES, EACH
# COMPARED AGAINST ELEVEN LITERALS), BY **CPU TIME**: `eq_op` **1537 us** AND THE PREDICATES
# **293 us** -- **A RATIO OF 0.1906**, SO THE PREDICATES COST **80.9% LESS**. ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ AND
# THE TWO FORMS' ANSWERS **AGREE** (MEASURED, `same T`), SO THIS IS NOT A SEMANTIC CHANGE.
#
# ⇒⇒⇒ ⇒⇒⇒ AND WHY A GENERIC HELPER IS NOT THE SHAPE: A `match` CANNOT SCRUTINIZE A **COMPUTED
# VALUE** ("give it its own def"), AND A NESTED `match` ON A CALL IS REFUSED TOO -- ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒
# SO THE LITERAL MUST BE ITS OWN ARM, WHICH IS WHY THERE IS **ONE PREDICATE PER LITERAL** AND NOT
# **ONE** HELPER.
#
# ⇒⇒⇒ ⇒⇒⇒ AND **FOUR OF THEM ALREADY EXIST** (`is_index`, `is_cast`, `is_const`, `is_add`), SO
# THIS IS THE **HOUSE PATTERN** AND NOT A NEW ONE -- ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ AND `eq_op` IS THE
# **LEFTOVER** THAT NONE OF THEM REPLACED.
def is_and(op: O.Op) -> Bool:
  match op:
    case O.OpsAND{}: True{}
    case _: False{}
def is_backedge(op: O.Op) -> Bool:
  match op:
    case O.OpsBACKEDGE{}: True{}
    case _: False{}
def is_binary(op: O.Op) -> Bool:
  match op:
    case O.OpsBINARY{}: True{}
    case _: False{}
def is_bitcast(op: O.Op) -> Bool:
  match op:
    case O.OpsBITCAST{}: True{}
    case _: False{}
def is_buffer(op: O.Op) -> Bool:
  match op:
    case O.OpsBUFFER{}: True{}
    case _: False{}
def is_customi(op: O.Op) -> Bool:
  match op:
    case O.OpsCUSTOMI{}: True{}
    case _: False{}
def is_end(op: O.Op) -> Bool:
  match op:
    case O.OpsEND{}: True{}
    case _: False{}
def is_endif(op: O.Op) -> Bool:
  match op:
    case O.OpsENDIF{}: True{}
    case _: False{}
def is_if(op: O.Op) -> Bool:
  match op:
    case O.OpsIF{}: True{}
    case _: False{}
def is_load(op: O.Op) -> Bool:
  match op:
    case O.OpsLOAD{}: True{}
    case _: False{}
def is_mul(op: O.Op) -> Bool:
  match op:
    case O.OpsMUL{}: True{}
    case _: False{}
def is_or(op: O.Op) -> Bool:
  match op:
    case O.OpsOR{}: True{}
    case _: False{}
def is_range(op: O.Op) -> Bool:
  match op:
    case O.OpsRANGE{}: True{}
    case _: False{}
def is_refparam(op: O.Op) -> Bool:
  match op:
    case O.OpsREFPARAM{}: True{}
    case _: False{}
def is_shrink(op: O.Op) -> Bool:
  match op:
    case O.OpsSHRINK{}: True{}
    case _: False{}
def is_stack(op: O.Op) -> Bool:
  match op:
    case O.OpsSTACK{}: True{}
    case _: False{}
def is_where(op: O.Op) -> Bool:
  match op:
    case O.OpsWHERE{}: True{}
    case _: False{}
def is_xor(op: O.Op) -> Bool:
  match op:
    case O.OpsXOR{}: True{}
    case _: False{}

def eq_op(x: O.Op, y: O.Op) -> Bool:
  match x y:
    case O.OpsSPECIAL{} O.OpsSPECIAL{}: True{}
    case O.OpsBUFFER{} O.OpsBUFFER{}: True{}
    case O.OpsALLOC{} O.OpsALLOC{}: True{}
    case O.OpsNOOP{} O.OpsNOOP{}: True{}
    case O.OpsREWRITE_ERROR{} O.OpsREWRITE_ERROR{}: True{}
    case O.OpsPARAM{} O.OpsPARAM{}: True{}
    case O.OpsREFPARAM{} O.OpsREFPARAM{}: True{}
    case O.OpsCALL{} O.OpsCALL{}: True{}
    case O.OpsPROGRAM{} O.OpsPROGRAM{}: True{}
    case O.OpsLINEAR{} O.OpsLINEAR{}: True{}
    case O.OpsSOURCE{} O.OpsSOURCE{}: True{}
    case O.OpsBINARY{} O.OpsBINARY{}: True{}
    case O.OpsSINK{} O.OpsSINK{}: True{}
    case O.OpsAFTER{} O.OpsAFTER{}: True{}
    case O.OpsSTACK{} O.OpsSTACK{}: True{}
    case O.OpsGETADDR{} O.OpsGETADDR{}: True{}
    case O.OpsINDEX{} O.OpsINDEX{}: True{}
    case O.OpsSHRINK{} O.OpsSHRINK{}: True{}
    case O.OpsLOAD{} O.OpsLOAD{}: True{}
    case O.OpsSTORE{} O.OpsSTORE{}: True{}
    case O.OpsWMMA{} O.OpsWMMA{}: True{}
    case O.OpsCAST{} O.OpsCAST{}: True{}
    case O.OpsBITCAST{} O.OpsBITCAST{}: True{}
    case O.OpsEXP2{} O.OpsEXP2{}: True{}
    case O.OpsLOG2{} O.OpsLOG2{}: True{}
    case O.OpsSIN{} O.OpsSIN{}: True{}
    case O.OpsSQRT{} O.OpsSQRT{}: True{}
    case O.OpsRECIP{} O.OpsRECIP{}: True{}
    case O.OpsNEG{} O.OpsNEG{}: True{}
    case O.OpsTRUNC{} O.OpsTRUNC{}: True{}
    case O.OpsADD{} O.OpsADD{}: True{}
    case O.OpsMUL{} O.OpsMUL{}: True{}
    case O.OpsSHL{} O.OpsSHL{}: True{}
    case O.OpsSHR{} O.OpsSHR{}: True{}
    case O.OpsTRUNCDIV{} O.OpsTRUNCDIV{}: True{}
    case O.OpsMAX{} O.OpsMAX{}: True{}
    case O.OpsTRUNCMOD{} O.OpsTRUNCMOD{}: True{}
    case O.OpsCMPLT{} O.OpsCMPLT{}: True{}
    case O.OpsCMPNE{} O.OpsCMPNE{}: True{}
    case O.OpsCMPEQ{} O.OpsCMPEQ{}: True{}
    case O.OpsXOR{} O.OpsXOR{}: True{}
    case O.OpsOR{} O.OpsOR{}: True{}
    case O.OpsAND{} O.OpsAND{}: True{}
    case O.OpsTHREEFRY{} O.OpsTHREEFRY{}: True{}
    case O.OpsSUB{} O.OpsSUB{}: True{}
    case O.OpsFDIV{} O.OpsFDIV{}: True{}
    case O.OpsPOW{} O.OpsPOW{}: True{}
    case O.OpsDIV{} O.OpsDIV{}: True{}
    case O.OpsMOD{} O.OpsMOD{}: True{}
    case O.OpsWHERE{} O.OpsWHERE{}: True{}
    case O.OpsMULACC{} O.OpsMULACC{}: True{}
    case O.OpsBARRIER{} O.OpsBARRIER{}: True{}
    case O.OpsRANGE{} O.OpsRANGE{}: True{}
    case O.OpsIF{} O.OpsIF{}: True{}
    case O.OpsEND{} O.OpsEND{}: True{}
    case O.OpsENDIF{} O.OpsENDIF{}: True{}
    case O.OpsBACKEDGE{} O.OpsBACKEDGE{}: True{}
    case O.OpsCONST{} O.OpsCONST{}: True{}
    case O.OpsCUSTOM{} O.OpsCUSTOM{}: True{}
    case O.OpsCUSTOMI{} O.OpsCUSTOMI{}: True{}
    case O.OpsINS{} O.OpsINS{}: True{}
    case O.OpsCONTIGUOUS_BACKWARD{} O.OpsCONTIGUOUS_BACKWARD{}: True{}
    case O.OpsDETACH{} O.OpsDETACH{}: True{}
    case O.OpsSTAGE{} O.OpsSTAGE{}: True{}
    case O.OpsCOPY{} O.OpsCOPY{}: True{}
    case O.OpsMSELECT{} O.OpsMSELECT{}: True{}
    case O.OpsMSTACK{} O.OpsMSTACK{}: True{}
    case O.OpsCUSTOM_FUNCTION{} O.OpsCUSTOM_FUNCTION{}: True{}
    case O.OpsRESHAPE{} O.OpsRESHAPE{}: True{}
    case O.OpsPERMUTE{} O.OpsPERMUTE{}: True{}
    case O.OpsEXPAND{} O.OpsEXPAND{}: True{}
    case O.OpsPAD{} O.OpsPAD{}: True{}
    case O.OpsUNSHARD{} O.OpsUNSHARD{}: True{}
    case O.OpsREDUCE{} O.OpsREDUCE{}: True{}
    case O.OpsALLREDUCE{} O.OpsALLREDUCE{}: True{}
    case O.OpsPYLITERAL{} O.OpsPYLITERAL{}: True{}
    case _ _: False{}


def ku_is_const_at(+kus: List<&2, List<&2, KU>>, +i: U32) -> Bool: ku_is_const_at.go(ku_at(kus, i))  def ku_is_cast_at.go(m: Maybe<&2, KU>) -> Bool:
  match m:
    case Some{k}: is_cast(KU.op(k))
    case None{}: False{}

def ku_is_cast_at(+kus: List<&2, List<&2, KU>>, +i: U32) -> Bool: ku_is_cast_at.go(ku_at(kus, i))  def ku_src0_at.go(m: Maybe<&2, KU>) -> U32:
  match m:
    case Some{k}: KU.src0(k)
    case None{}: 0

def ku_src0_at(+kus: List<&2, List<&2, KU>>, i: U32) -> U32: ku_src0_at.go(ku_at(kus, i))  def ku_const_int_at.go(m: Maybe<&2, KU>) -> Maybe<&1, H.I64>:
  match m:
    case Some{k}: KUArg.const_int(KU.arg(k))
    case None{}: None{}

def ku_const_int_at(+kus: List<&2, List<&2, KU>>, i: U32) -> Maybe<&1, H.I64>:
  ku_const_int_at.go(ku_at(kus, i))

def ku_const_float_at.go(m: Maybe<&2, KU>) -> Maybe<&1, F32>:
  match m:
    case Some{k}: KUArg.const_float(KU.arg(k))
    case None{}: None{}

def ku_const_float_at(+kus: List<&2, List<&2, KU>>, i: U32) -> Maybe<&1, F32>:
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

def ku_index_is_const_cast(+kus: List<&2, List<&2, KU>>, +idx: U32) -> Bool:
  Bool.and(ku_is_cast_at(kus, idx), ku_is_const_at(kus, ku_src0_at(kus, idx)))

def drop_last(+ps: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}: List.reverse(&2, String, acc)
    case h <> t:
      match t:
        case Nil{}: List.reverse(&2, String, acc)
        case _ <> _: drop_last(t, List.append(&2, String, [h], acc))

def strip_pieces.go(b: Bool, +t: List<&2, String>, +ps: List<&2, String>) -> List<&2, String>:
  match b:
    case True{}: drop_last(t, Nil{})
    case False{}: ps

def strip_pieces(+ps: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}: Nil{}
    case h <> t: strip_pieces.go(String.eq(h, "("), t, ps)

def ku_src_pieces(b: Bool, +ps: List<&2, String>) -> List<&2, String>:
  match b:
    case True{}: strip_pieces(ps)
    case False{}: ps

def ku_render_index.global(dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  +ps = rtp(r, KU.src1(k))
  List.concat(&2, String, [["("], rtp(r, KU.src0(k)), ["+"],
    ku_src_pieces(KUArg.index_is_add(KU.arg(k)), ps), [")"]])

# ===========================================================================
# THE TEXT OF ONE UOP -- the port of `base_rewrite` (cstyle.py:11-77), FOR THE
# OPS THE CPU LANE NEEDS. THE ORDER IS UPSTREAM'S ORDER, AND THE ORDER IS THE
# RULE: the CONST arms come BEFORE the generic CAST arm.
# ===========================================================================
def ku_text_if(dev: U32, k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> String:
  String.concat(["if (", rt(r, KU.src0(k)), ") {"])

# `  if (!({ctx[c]})) {\n break;\n}\n}` -- cstyle.py:20.
def ku_text_backedge(dev: U32, k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> String:
  String.concat(["  if (!(", rt(r, KU.src0(k)), ")) {\n break;\n}\n}"])

def ku_text_buffer(dev: U32, i: U32, +k: KU, +r: Rows) -> String:
  render_buffer(dev, KU.dtype(k), KU.numel(k), KU.addr(k), rt(r, i))

# `f"__{_wmma_name(x)}({ctx[x.src[0]]}, {ctx[x.src[1]]}, {ctx[x.src[2]]})"` -- cstyle.py:63.
# cstyle.py:63 -- the CALL is `__{_wmma_name(x)}({s0}, {s1}, {s2})`, and the name is the
# ALREADY-PORTED `wmma_name_of(dims, din, dout)` (:1194) fed from the KU's own arg.
def ku_wmma_name(+k: KU) -> String:
  wmma_name_of(wmma_dims(KUArg.wmma_dims(KU.arg(k))), dt_name(KUArg.wmma_dt_in(KU.arg(k))),
    dt_name(KU.dtype(k)))

def ku_text_wmma(dev: U32, +k: KU, +r: Rows) -> String:
  String.concat(["__", ku_wmma_name(k), "(", rt(r, KU.src0(k)), ", ", rt(r, KU.src1(k)), ", ",
    rt(r, KU.src2(k)), ")"])

# THE ALU ARM -- cstyle.py:64-65:
#   `ctx.code_for_op[x.op](*([strip_parens(ctx[v]) if v.op == x.op and x.op in {ADD, MUL, XOR, OR, AND} else ctx[v] for v in x.src]), x.dtype)`
# THE STRIP IS THE SAME-OP TEST AND IT IS NOT COSMETIC: it is what makes
# `((x)+(y))` AND `((x)+(y)+(z))` COMPOSE.
def ku_strips(+op: O.Op) -> Bool:
  Bool.or(Bool.or(is_add(op), is_mul(op)),
    Bool.or(is_xor(op), Bool.or(is_or(op), is_and(op))))

# ===========================================================================
# THE WALK -- the port of `cstyle.py:208-266`'s BODY. THE STATE IS SIX THINGS
# AND THEY ARE SIX THINGS BECAUSE BEND HAS NO MUTABLE MAP: `r` (the name/text
# map, INDEXED BY THE UOP'S POSITION), `kernel` (the emitted lines), `bufs` (the
# kernel's arguments), `c` (the six prefix counters), `depth` (the indent) and
# `name` (the kernel's name, from the SINK).
# ===========================================================================
def St.r(s: St) -> Rows:
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

def St.of(+r: Rows, +kernel: List<&2, String>, +bufs: List<&2, BArg>,
          +c: List<&2, U32>, depth: U32, name: String) -> St: St{r, kernel, bufs, c, depth, name}

# `r` GROWS BY ONE ENTRY PER UOP, INCLUDING THE SKIPPED ONES, because `r` IS
# INDEXED BY THE UOP'S POSITION AND THE POSITIONS OF THE LATER UOPS MUST NOT
# MOVE.
def st_put.r(+ps: List<&2, String>, n: U32, mode: Nat, +st: St) -> St:
  match mode:
    case 0n:
      St.of(Rows{[[ps]], 1}, St.kernel(st), St.bufs(st), St.c(st), St.depth(st), St.name(st))
    case 2n:
      St.of(Rows{List.append(&2, List<&2, List<&2, String>>, [[ps]], Rows.ts(St.r(st))), U32.add(n, 1)},
        St.kernel(st), St.bufs(st), St.c(st), St.depth(st), St.name(st))
    case _:
      +r = St.r(st)
      St.of(Rows{List.set(&2, List<&2, List<&2, String>>, Rows.ts(r), 0n,
        List.append(&2, List<&2, String>, [ps], Rows.blk(r, 0))), U32.add(n, 1)},
        St.kernel(st), St.bufs(st), St.c(st), St.depth(st), St.name(st))

def st_put.p(+ps: List<&2, String>, +st: St) -> St:
  +r = St.r(st)
  +n = Rows.n(r)
  st_put.r(ps, n, Bool.pick(Nat, U32.is_zero(n), 0n,
    Bool.pick(Nat, U32.is_zero(U32.and(n, 15)), 2n, 1n)), st)
def st_put(+st: St, x: String) -> St: st_put.p([x], st)

def st_set.r(+ps: List<&2, String>, +bi: U32, +off: U32, +st: St) -> St:
  +r = St.r(st)
  St.of(Rows{List.set(&2, List<&2, List<&2, String>>, Rows.ts(r), U32.to_nat(bi),
    List.set(&2, List<&2, String>, Rows.blk(r, bi), U32.to_nat(off), ps)), Rows.n(r)},
    St.kernel(st), St.bufs(st), St.c(st), St.depth(st), St.name(st))

def st_set.p(+st: St, i: U32, +ps: List<&2, String>) -> St:
  +r = St.r(st)
  +d = U32.sub(U32.sub(Rows.n(r), 1), i)
  st_set.r(ps, Rows.bi(r, d), Rows.off(r, d), st)
def st_set(+st: St, i: U32, x: String) -> St: st_set.p(st, i, [x])

# **⇒ AND THE KERNEL's LINES ARE **PREPENDED**, AND REVERSED ONCE AT THE READ.** MEASURED
# (`PARITY.md` §137): `List.append(xs, ys)` IN BEND **COPIES `xs`**, SO `List.append(acc, [x])` IS O(n)
# AND `List.append([x], acc)` IS O(1). **⇒ AND `st_kernel` WAS THE O(n) FORM, AND IT IS CALLED ONCE
# PER EMITTED LINE.** MEASURED, THE CENSUS OF THE `List.append` ENTRY CALLS (THE RECURSION EXCLUDED):
# `st_kernel` **407 CALLS COPYING 82,039 ELEMENTS (MAX 404)**, `chunk_close` 49/1,176, `List_concat`
# 2,897/3,890, AND EVERY OTHER SITE UNDER 1,000. **⇒ SO `st_kernel` IS 90% OF THE ~91,000 ELEMENTS
# COPIED A RENDER, AND `$List_append`'s SELF TIME IS 0.979 ms A TURN -- HALF THE PORT's 1.99 ms.**
# **⇒ AND THE PREPENDED LIST IS REVERSED ONCE, AT THE ONE READER THAT CARES ABOUT THE ORDER** (`:2983`).
def st_kernel(+st: St, x: String) -> St:
  St.of(St.r(st), List.append(&2, String, [x], St.kernel(st)), St.bufs(st), St.c(st), St.depth(st), St.name(st))

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
#
# **IT IS COUNTED ON THE WIRE, NOT HERE.** `List.get` is O(index) and `List.set` rebuilds the prefix, so
# computing this list cost 104,946 list steps per 405-uop render and reading it back another 154,915 --
# 32% of every `List.get` step the renderer takes (MEASURED, `PARITY.md` §75). It is a pure function of
# `srcs`, Python has an array, and `KU.cc` makes the read a field access.
def ku_indent(depth: U32) -> String:
  ku_indent.go(U32.to_nat(depth), "")

def ku_inline2a(+op: O.Op, k: KU, +kus: List<&2, List<&2, KU>>) -> Bool:
  Bool.or(Bool.and(is_cast(op), ku_is_const_at(kus, KU.src0(k))),
    Bool.or(Bool.or(is_index(op), is_shrink(op)),
      Bool.or(is_customi(op), is_refparam(op))))

# `(u.op is Ops.LOAD and u.src[0].addrspace == AddrSpace.REG and child_count[u] == 1)`
def ku_inline2b2a(+op: O.Op, +k: KU) -> Bool:
  Bool.and(Bool.or(is_cast(op), is_bitcast(op)),
    Bool.or(is_global(KU.addr(k)), is_local(KU.addr(k))))

# `(u.op in {Ops.STACK, *(GroupOp.ALU-{Ops.WHERE}), Ops.CAST, Ops.BITCAST} and child_count[u] == 1)`
def cc_at(k: KU) -> U32: KU.cc(k)

def ku_src_is_reg.go(m: Maybe<&2, KU>) -> Bool:
  match m:
    case Some{s}: is_reg(KU.addr(s))
    case None{}: False{}

def ku_src_is_reg(+kus: List<&2, List<&2, KU>>, k: KU) -> Bool:
  ku_src_is_reg.go(ku_at(kus, KU.src0(k)))

def ku_is_alu_ex_where(+op: O.Op) -> Bool:
  Bool.and(R.is_alu(op), Bool.not(is_where(op)))

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
  Bool.not(Bool.or(Bool.or(is_range(op), is_buffer(op)),
    is_binary(op)))

def _render.pop(+st: St, +k: KU) -> St:
  Bool.pick(St, Bool.or(is_endif(KU.op(k)),
    Bool.or(is_end(KU.op(k)), is_backedge(KU.op(k)))),
    st_depth(st, U32.sub(St.depth(st), 1)), st)

def _render.push(+st: St, +k: KU) -> St:
  Bool.pick(St, Bool.or(is_if(KU.op(k)), is_range(KU.op(k))),
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
# **ONE `rt` AND ONE `strip_parens`, NOT TWO OF EACH.** The old spelling was
# `Bool.pick(String, cond, strip_parens(rt(r, h)), rt(r, h))`: STRICT, so `rt` ran twice -- and `rt` is a
# `List.get` by src-to-current distance -- and `strip_parens` scanned the source even when its result was
# discarded. The bool as a parameter means the scan happens only on the branch that keeps it (§39's cure).
# MEASURED: the ALU catch-all is 0.55 ms of the render (`PARITY.md` §89) and this is its per-operand work.
def ku_alu_srcs.go(+op: O.Op, k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows,                    +ss: List<&2, U32>, +acc: List<&2, List<&2, String>>) -> List<&2, List<&2, String>>:
  match ss:
    case Nil{}: acc
    case h <> t:
      +ps = rtp(r, h)
      ku_alu_srcs.go(op, k, kus, r, t, List.append(&2, List<&2, String>, acc,
        [ku_src_pieces(Bool.and(eq_op(ku_op_at(kus, h), op), ku_strips(op)), ps)]))

def ku_alu_srcs(op: O.Op, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, List<&2, String>>:
  ku_alu_srcs.go(op, k, kus, r, KU.srcs(k), Nil{})

def ku_inline2b1(+op: O.Op, +k: KU, +kus: List<&2, List<&2, KU>>) -> Bool:
  Bool.and(is_load(op),
    Bool.and(ku_src_is_reg(kus, k), U32.is_eq(cc_at(k), 1)))
def ku_inline_op_set(+op: O.Op) -> Bool:
  Bool.or(is_stack(op),
    Bool.or(ku_is_alu_ex_where(op),
      Bool.or(is_cast(op), is_bitcast(op))))

def ku_inline2b2b(+op: O.Op, +k: KU) -> Bool:
  Bool.and(ku_inline_op_set(op), U32.is_eq(cc_at(k), 1))

def ku_param_name(+k: KU) -> String:
  String.concat([ku_param_base(KU.arg(k)), "_", ku_shape_str(KU.shape(k))])

def ku_is_decl(+k: KU) -> Bool:
  Bool.and(ku_not_stmt_op(KU.op(k)), Bool.not(O.eq_dt(KU.dtype(k), S.void())))

def _render.plain(dev: U32, i: U32, +k: KU, kus: List<&2, List<&2, KU>>,
                  +st: St, +l: List<&2, String>, nm: String, ix: U32) -> St:
  +st0 = _render.pop(st, k)
  # THE SEMICOLON IS THE WHOLE DIFFERENCE, so it is chosen as a STRING (two literals, free) and the line is
  # assembled ONCE. The previous spelling built two `st_kernel` calls and discarded one.
  +st1 = st_kernel(st0, String.concat([ku_indent(St.depth(st0)), String.join(l, ""),
    Bool.pick(String, is_cast(KU.op(k)), ";", "")]))
  +st2 = st_c(st1, ix)
  _render.push(st2, k)
def uops_to_dtypes.put(+x: DtN, +acc: List<&2, DtN>) -> List<&2, DtN>:
  Bool.pick(List<&2, DtN>, uops_to_dtypes.has(x, acc),
    acc, List.append(&2, DtN, acc, [x]))

def ku_text_alu(dev: U32, +op: O.Op, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  code_for_op.of(dev, op, ku_alu_srcs(op, k, kus, r), KU.dtype(k))
def ku_inline2b2(+op: O.Op, +k: KU) -> Bool:
  Bool.or(ku_inline2b2a(op, k), ku_inline2b2b(op, k))

# **`numel > 1` IS APPLIED HERE, NOT ONLY AT EMIT TIME, AND THE BYTES ARE UNCHANGED BECAUSE THE LIST HAS
# ONE CONSUMER.** `_render_defines.go` asks `U32.is_gt(DtN.n(h), 1)` and emits nothing for the rest, so a
# pair with `n == 1` was collected, deduped and scanned to produce nothing. MEASURED (`PARITY.md` §117): the
# shipped 405-uop kernel has 315 ALU-addr uops of which ONE has `numel > 1`, and the pass still spent 2,559
# `has` calls and ~8,800 `DtN` accessor calls -- 18% of every call in the walk -- to emit ONE typedef row.
def uops_to_dtypes.one(+k: KU, +acc: List<&2, DtN>) -> List<&2, DtN>:
  Bool.pick(List<&2, DtN>,
    Bool.and(Bool.and(is_alu_addr(KU.addr(k)), Bool.not(O.eq_dt(KU.dtype(k), S.void()))),
      U32.is_gt(KU.numel(k), 1)),
    uops_to_dtypes.put(DtN{KU.dtype(k), KU.numel(k)}, acc), acc)

def ku_inline2b(+op: O.Op, +k: KU, +kus: List<&2, List<&2, KU>>) -> Bool:
  Bool.or(ku_inline2b1(op, k, kus), ku_inline2b2(op, k))
def ku_inline2(+op: O.Op, +k: KU, +kus: List<&2, List<&2, KU>>) -> Bool:
  Bool.or(ku_inline2a(op, k, kus), ku_inline2b(op, k, kus))

# `(u.op is Ops.CAST and u.src[0].op is Ops.CONST) or u.op in {Ops.INDEX, Ops.SHRINK, Ops.CUSTOMI, Ops.REFPARAM}`
def ku_inline(+op: O.Op, +k: KU, +kus: List<&2, List<&2, KU>>) -> Bool:
  Bool.and(Bool.or(Bool.not(is_cast(op)), U32.is_eq(KU.numel(k), 1)),
    ku_inline2(op, k, kus))

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

def render_cast_p(+dev: U32, +d: S.Dt, numel: U32, +a: S.Addr, op: O.Op, img: Bool, +val: List<&2, String>) -> List<&2, String>:
  List.concat(&2, String, [[String.concat(["(", render_type(dev, d, numel, a, op, img), ")("])], val, [")"]])

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
def ku_const_val(+kus: List<&2, List<&2, KU>>, i: U32) -> U32: ku_const_val.go(ku_const_int_at(kus, i))  # =========================================================================== # THE CONST-OF-A-CONST CAST -- cstyle.py:25-37. THE ARMS, IN ORDER:
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

# **THE CAST IS COMPUTED ONCE TOO, AND FOR THE SAME REASON AS THE DECIMAL ABOVE.** `ku_cast_wrapped` is in
# FOUR arms of the chain below and `Bool.pick` evaluates every arm, so the port was rendering the same cast
# four times per integer constant and using one -- and a cast render is a `render_cast` -> `render_dtype`,
# i.e. a whole dtype render each time. MEASURED in `PARITY.md` §34.
# **ONE ARM BUILDS ONE STRING; THE CHAIN BUILT NINE AND THREW EIGHT AWAY.** `Bool.pick` is STRICT, so the
# old spelling evaluated `s + "l"`, `s + "ul"`, `U32.show(lo) + "u"` and `ku_cast_wrapped` for EVERY integer
# constant and kept one. MEASURED (`PARITY.md` §98): CAST is the renderer's most expensive class at 0.89 ms
# of a 4.7 ms turn, 19%, and this is its per-constant work. A Nat code answers the dispatch and `match` runs
# exactly one arm -- §39's cure, on the arm that runs.
def dtw(+d: S.Dt) -> Nat:
  Bool.pick(Nat, O.eq_dt(d, S.int64()), 0n,
    Bool.pick(Nat, O.eq_dt(d, S.uint64()), 1n,
      Bool.pick(Nat, O.eq_dt(d, S.uint32()), 2n,
        Bool.pick(Nat, O.eq_dt(d, S.boolean()), 3n,
          Bool.pick(Nat, O.eq_dt(d, S.uint8()), 4n,
            Bool.pick(Nat, O.eq_dt(d, S.uint16()), 5n,
              Bool.pick(Nat, O.eq_dt(d, S.int8()), 6n,
                Bool.pick(Nat, O.eq_dt(d, S.int16()), 7n, 8n))))))))

def ku_ccw.at(ix: Nat, +s: String, +d: S.Dt, +dev: U32, +i: H.I64) -> String:
  match ix:
    case 0n: String.concat([s, "l"])
    case 1n: String.concat([H.i64_udec(i), "ul"])
    case 2n: String.concat([U32.show(H.lo32(i)), "u"])
    # `"1" if c.val else "0"` (cstyle.py:29) is a test of ZERO, not of the SIGN: the port asked
    # `i64_is_neg`, which answers "0" only for a negative constant, so a bool constant `False` rendered
    # `1`. MEASURED against the oracle (`PARITY.md` §116): every `exp` kernel diverged on `==1` vs `==0`.
    case 3n: Bool.pick(String, H.i64_is_zero(i), "0", "1")
    # `f"({ctx.render_cast(x, f'{c.val}u')})"` (cstyle.py:33, the uint8/uint16 arm): the SUFFIX is part of
    # the text, so `(unsigned char)(127)` is wrong where upstream says `(unsigned char)(127u)`.
    case 4n: ku_cast_wrapped(dev, d, String.concat([s, "u"]))
    case 5n: ku_cast_wrapped(dev, d, String.concat([s, "u"]))
    case 8n: s
    case _: ku_cast_wrapped(dev, d, s)

def ku_const_cast_int_w(+s: String, +d: S.Dt, +dev: U32, +i: H.I64) -> String:
  ku_ccw.at(dtw(d), s, d, dev, i)

def ku_const_cast_int_at(+s: String, +dt: S.Dt, +dev: U32, k: KU, +i: H.I64) -> String:
  match dt:
    case d: ku_const_cast_int_w(s, d, dev, i)

# **THE DECIMAL IS COMPUTED ONCE AND PASSED IN, AND THAT IS A MEASURED CHANGE.** `Bool.pick` is STRICT here,
# so every arm of the chain below is EVALUATED and one is chosen: this def used to call `H.i64_dec(i)` SEVEN
# times per integer constant, six of whose results were discarded. MEASURED on the shipped path
# (`PARITY.md` §33): with the decimal hoisted the 405-uop render drops by the amount in §33, and the C is
# byte-identical because the four redundant conversions were computing the same string.
def ku_const_cast_int(+dt: S.Dt, +dev: U32, k: KU, +i: H.I64) -> String:
  ku_const_cast_int_at(H.i64_dec(i), dt, dev, k, i)

# **A NON-FINITE FLOAT IS NOT `repr(v) + "f"`.** `cstyle.py:26` spells the const as
# `f"({ctx.render_cast(x, ctx.nan if math.isnan(v) else ctx.infinity if v > 0 else f'-{ctx.infinity}')})"`,
# so upstream emits `((float)(__builtin_inff()))` / `((float)(-__builtin_inff()))` /
# `((float)(__builtin_nanf("")))`. The port emitted `U.f32_repr(f) ++ "f"`, which is `inff` and
# `-inff` -- UNDECLARED IDENTIFIERS. MEASURED 2026-11-03: `exp`, `log2` and `sin` fail to COMPILE on
# `use of undeclared identifier 'inff'`, and the rendered C is 3406 B against upstream's 3742 B.
# `infinity.of` / `nan.of` (line 419) already carry the two `__builtin_` spellings, so this reuses them.
def f32_nonfinite(+f: F32) -> Bool: U32.is_eq(U32.and(F32.bits(f), 2139095040), 2139095040)
def f32_is_nan(+f: F32) -> Bool:
  Bool.and(f32_nonfinite(f), Bool.not(U32.is_eq(U32.and(F32.bits(f), 8388607), 0)))

def ku_flt_nonfinite(+dev: U32, +d: S.Dt, +f: F32) -> String:
  Bool.pick(String, f32_is_nan(f), ku_cast_wrapped(dev, d, nan.of(dev)),
    Bool.pick(String, F32.is_lt(f, 0.0),
      ku_cast_wrapped(dev, d, String.concat(["-", infinity.of(dev)])),
      ku_cast_wrapped(dev, d, infinity.of(dev))))

def ku_const_cast_f32(+dt: S.Dt, +dev: U32, k: KU, +f: F32) -> String:
  match dt:
    case d:
      Bool.pick(String, f32_nonfinite(f), ku_flt_nonfinite(dev, dt, f),
        Bool.pick(String, O.eq_dt(d, S.single()), String.concat([U.f32_repr(f), "f"]),
          Bool.pick(String, O.eq_dt(d, S.half()), ku_cast_wrapped(dev, d, String.concat([U.f32_repr(f), "f"])),
            Bool.pick(String, O.eq_dt(d, S.bfloat16()), ku_cast_wrapped(dev, d, String.concat([U.f32_repr(f), "f"])),
              # **THE FALLBACK IS BARE, NOT CAST-WRAPPED.** cstyle.py:39 is
              # `(UPat.cvar("c").cast(), lambda ctx,c: str(c.val))` -- the DEFAULT arm writes the value
              # with no cast at all. MEASURED 2026-11-03, found by extending ksweep to f64: upstream emits
              # `((double)(val0[0]))*2.0` and the port emitted `*((double)(2.0))`, one divergence in 37
              # kernels. `double` is the only dtype that reaches this arm (f32 -> `f`, half/bf16 -> a
              # cast of `{val}f`, fp8 -> the same), which is why nothing caught it before.
              U.f32_repr(f)))))

# THE GENERIC CAST: `f"({ctx.render_cast(x, ctx[x.src[0]])})"` (cstyle.py:40).
def ku_cast_generic(dev: U32, +k: KU, +r: Rows) -> List<&2, String>:
  List.concat(&2, String, [["("], render_cast_p(dev, KU.dtype(k), KU.numel(k), KU.addr(k), O.OpsCAST{},
    False{}, rtp(r, KU.src0(k))), [")"]])

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
def ku_const_cast_flt.go(m: Maybe<&1, F32>, dev: U32, +k: KU, +r: Rows) -> List<&2, String>:
  match m:
    case Some{f}: [ku_const_cast_f32(KU.dtype(k), dev, k, f)]
    case None{}: ku_cast_generic(dev, k, r)

def ku_const_cast_flt(dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  ku_const_cast_flt.go(ku_const_float_at(kus, KU.src0(k)), dev, k, r)

def ku_const_cast2.go(m: Maybe<&1, H.I64>, dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  match m:
    case Some{i}: [ku_const_cast_int(KU.dtype(k), dev, k, i)]
    case None{}: ku_const_cast_flt(dev, k, kus, r)

def ku_const_cast2(dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  ku_const_cast2.go(ku_const_int_at(kus, KU.src0(k)), dev, k, kus, r)

def ku_const_cast_by(b: Bool, +dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  match b:
    case True{}: ku_const_cast2(dev, k, kus, r)
    case False{}: ku_cast_generic(dev, k, r)

def ku_const_cast(+dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  ku_const_cast_by(ku_is_const_at(kus, KU.src0(k)), dev, k, kus, r)

def ku_render_index.aluconst.pick(b: Bool, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows, +ix: U32) -> List<&2, String>:
  match b:
    case True{}: List.concat(&2, String, [rtp(r, KU.src0(k)), ["["], [U32.show(ix)], ["]"]])
    case False{}: List.concat(&2, String, [rtp(r, KU.src0(k)), ["."], [ku_swizzle(ix)]])

def ku_render_index.aluconst.go(m: Maybe<&2, KU>, dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>,                                  +r: Rows) -> List<&2, String>:
  match m:
    case Some{b}:
      ku_render_index.aluconst.pick(U32.is_gt(KU.numel(b), gep_arr_threshold.of(dev)), k, kus, r,
        ku_const_val(kus, ku_src0_at(kus, KU.src1(k))))
    case None{}: [""]

def ku_render_index.aluconst(dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  ku_render_index.aluconst.go(ku_at(kus, KU.src0(k)), dev, k, kus, r)

def ku_render_index.aluarm.pick(b: Bool, dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  match b:
    case True{}: ku_render_index.aluconst(dev, k, kus, r)
    case False{}: List.concat(&2, String, [["("], rtp(r, KU.src0(k)), [")["], rtp(r, KU.src1(k)), [")"]])

def ku_render_index.aluarm.go(m: Maybe<&2, KU>, dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  match m:
    case Some{b}: ku_render_index.aluarm.pick(ku_index_is_const_cast(kus, KU.src1(k)), dev, k, kus, r)
    case None{}: [""]
def ku_render_index.aluarm(dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  ku_render_index.aluarm.go(ku_at(kus, KU.src0(k)), dev, k, kus, r)

def ku_render_index.by(b: Bool, dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  match b:
    case True{}: ku_render_index.aluarm(dev, k, kus, r)
    case False{}: ku_render_index.global(dev, k, kus, r)

def ku_render_index(+dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  ku_render_index.by(is_alu_addr(KU.addr(k)), dev, k, kus, r)

def ku_text_range(dev: U32, +i: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> String:
  Bool.pick(String, O.eq_dt(KU.dtype(k), S.void()), "for (;;) {",
    String.concat(["for (", render_dtype(dev, KU.dtype(k), 1, S.Aalu{}, True{}, False{}, False{}), " ",
      rt(r, i), " = 0; ", rt(r, i), " < ", rt(r, KU.src0(k)), "; ", rt(r, i), "++) {"]))

# **THIS WAS A DUPLICATE OF `ku_const_cast`, AND `Bool.pick` BEING STRICT MADE IT PAY TWICE.** The two defs
# held the SAME conditional -- `Bool.pick(ku_is_const_at(src0), const-path, generic-path)` -- and the CAST arm
# of `ku_text_go` called the outer one, which called the inner one, so a CAST line evaluated
# `ku_is_const_at` twice and BOTH arms twice: `ku_const_cast2` and `ku_cast_generic` each ran twice and one of
# each was thrown away. MEASURED in `PARITY.md` §38. One call, byte-identical.
def ku_text_cast(+dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  ku_const_cast(dev, k, kus, r)

# ===========================================================================
# `BITCAST` -- cstyle.py:41-43 (the BASE's two rules), :338 (OpenCL `as_<dt>`), :386
# (Metal `as_type<dt>`) and :445 (HIP `tg_bitcast<dt>`). FOUR SPELLINGS OF ONE OP, and the
# three device ones are `string_rewrite` arms, which is why they win over `base_rewrite`; each
# returns None for a GLOBAL/LOCAL addrspace, and THAT is what falls through to the base's first
# rule, `(({_render_dtype(dtype, addrspace)})({val}))`.
#
# THE KU RENDERER HAD NO ARM AT ALL and therefore fell to the ALU catch-all, which never saw an
# ALU spelling for the op and answered `UNHANDLED(Ops.BITCAST)`. MEASURED on `bitcast(a)+1`:
# CPython renders `as_type<float>((uint)((as_type<uint>((float)(val0.x))+1u)))` and the port
# rendered nothing that compiles. The op is already on the INLINE lists (:1573, :1686), so this
# arm only has to say what the text is.
def ku_dt_at.go(m: Maybe<&2, KU>) -> S.Dt:
  match m:
    case Some{k}: KU.dtype(k)
    case None{}: S.void()

def ku_dt_at(+kus: List<&2, List<&2, KU>>, i: U32) -> S.Dt: ku_dt_at.go(ku_at(kus, i))

def bitcast_head(+dev: U32, +d: S.Dt) -> String:
  match dev:
    case 2: String.concat(["as_", render_dtype_legacy(dev, d)])
    case 3: String.concat(["as_type<", render_dtype_legacy(dev, d), ">"])
    case 5: String.concat(["tg_bitcast<", render_dtype_legacy(dev, d), ">"])
    case _: String.concat(["__builtin_bit_cast(", render_dtype_legacy(dev, d)])

# the base's second rule is the only one whose TWO arguments are comma-separated and whose type
# comes from `render_type` rather than `_render_dtype`; the three device rules are `head + "((S)(v))"`.
def bitcast_named(+dev: U32, +d: S.Dt, +sd: S.Dt, +s: String) -> String:
  match dev:
    case 0: String.concat([bitcast_head(dev, d), ", (", render_dtype_legacy(dev, sd), ")(", s, "))"])
    case 1: String.concat([bitcast_head(dev, d), ", (", render_dtype_legacy(dev, sd), ")(", s, "))"])
    case 4: String.concat([bitcast_head(dev, d), ", (", render_dtype_legacy(dev, sd), ")(", s, "))"])
    case _: String.concat([bitcast_head(dev, d), "((", render_dtype_legacy(dev, sd), ")(", s, "))"])

# **TWO PARENS, NOT THREE.** upstream cstyle.py:42-43 is `f"(({_render_dtype(x.dtype, addrspace=x.addrspace)})({ctx[x.src[0]]}))"`
# and `_render_dtype` returns a bare spelling like `unsigned long*` (cstyle.py:191-202 adds only a prefix and a
# `*`), so the cast text is `((unsigned long*)(args_24))`. MEASURED: the port carried a third `(` here and it was
# INVISIBLE until the packed-args ABI made a GLOBAL BITCAST appear in every kernel (PARITY.md §116).
def bitcast_text(+dev: U32, +a: S.Addr, +d: S.Dt, +sd: S.Dt, +s: String) -> String:
  match a:
    case S.AGlobal{}: String.concat(["((", render_dtype(dev, d, 1, a, False{}, False{}, False{}), ")(", s, "))"])
    case S.ALocal{}: String.concat(["((", render_dtype(dev, d, 1, a, False{}, False{}, False{}), ")(", s, "))"])
    case _: bitcast_named(dev, d, sd, s)

# `f"(({ctx.param_type(x)})({ctx[x.src[1]]}))"` (cstyle.py:44), where `param_type` is
# `_render_dtype(x.dtype, 1, x.addrspace, mutable=True, override_ptr=x.addrspace != ALU)` (cstyle.py:277):
# the pointer spelling comes from the ADDRSPACE, never from a buffer. REFPARAM exists only since the
# packed-args ABI (`codegen/__init__.py:422-427`), which rewrites every non-ALU param read to
# `REFPARAM(p.src[0], <load from args>)`.
def ku_text_refparam(+dev: U32, +k: KU, +r: Rows) -> String:
  String.concat(["((", render_dtype(dev, KU.dtype(k), 1, KU.addr(k), True{}, Bool.not(is_alu_addr(KU.addr(k))), False{}),
    ")(", String.join(rtp(r, KU.src1(k)), ""), "))"])

def ku_text_bitcast(+dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  [bitcast_text(dev, KU.addr(k), KU.dtype(k), ku_dt_at(kus, KU.src0(k)), String.join(rtp(r, KU.src0(k)), ""))]

# `f"({ctx.render_access(bidx)})"` (cstyle.py:57) AND
# `f"({ctx[gate]}?{ctx.render_access(bidx)}:{ctx[var]})"` (cstyle.py:58-59).
def ku_ptr.go(m: Maybe<&2, KU>, dev: U32, +ai: U32, +b: KU, kus: List<&2, List<&2, KU>>, +r: Rows) -> String:
  match m:
    case Some{s}:
      Bool.pick(String, Bool.or(U32.is_gt(KU.numel(b), 1), Bool.not(O.eq_dt(KU.dtype(b), KU.dtype(s)))),
        String.concat(["((", render_dtype(dev, KU.dtype(b), KU.numel(b), KU.addr(b), True{}, True{}, False{}), ")(",
          rt(r, ai), "))"]),
        rt(r, ai))
    case None{}: ""
def ku_ptr(dev: U32, +ai: U32, +b: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> String:
  ku_ptr.go(ku_at(kus, KU.src0(b)), dev, ai, b, kus, r)
def ku_access.go(m: Maybe<&2, KU>, dev: U32, +ai: U32, k: KU, kus: List<&2, List<&2, KU>>, +r: Rows) -> String:
  match m:
    case Some{b}: String.concat(["*", ku_ptr(dev, ai, b, kus, r)])
    case None{}: "*"
def ku_access(dev: U32, +ai: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> String:
  ku_access.go(ku_at(kus, KU.src0(k)), dev, ai, k, kus, r)
def ku_text_load.by(b: Bool, dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  match b:
    case True{}: List.concat(&2, String, [["("], rtp(r, KU.src2(k)), ["?"],
      [ku_access(dev, KU.src0(k), k, kus, r)], [":"], rtp(r, KU.src1(k)), [")"]])
    case False{}: List.concat(&2, String, [["("], [ku_access(dev, KU.src0(k), k, kus, r)], [")"]])

def ku_text_load(+dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  ku_text_load.by(U32.is_eq(KU.nsrc(k), 3), dev, k, kus, r)
def ku_text_store(dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  List.concat(&2, String, [[ku_access(dev, KU.src0(k), k, kus, r)], [" = "], rtp(r, KU.src1(k)), [";"]])
def ku_stack_srcs.go(+ss: List<&2, U32>, +kus: List<&2, List<&2, KU>>, +r: Rows,
                    acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case h <> t: ku_stack_srcs.go(t, kus, r, List.append(&2, String, acc, [rt(r, h)]))

def ku_stack_srcs(+k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  ku_stack_srcs.go(KU.srcs(k), kus, r, Nil{})

# cstyle.py:52-54 -- `f"{ctx.float4.replace('float4', ctx.render_type(x))}"`. THE REPLACE IS
# THE WHOLE POINT AND IT WAS MISSING: the device's maker is spelled with the literal
# `float4`, and the STACK's OWN type replaces it, so a two-lane STACK is `float2(...)` and
# NOT `float4(...)`. MEASURED: without it the port's WMMA call read
# `__WMMA_8_8_8_f32_f32(val0, val4, float4(...))` against upstream's `float2(...)` -- one
# token, sixteen lines, the last difference in the kernel.
# `String.replace` is a wall here (`String.split` splits on ONE CHAR), so the five device
# spellings in `float4.of` are answered directly; each contains exactly one `float4`
# token, in the position below, which is why this is the same answer and not a rewriting
# of it. The `_` arm is `float4.of`'s `"None"`, which holds no token to replace.
def float4_with(+dev: U32, +t: String) -> String:
  match dev:
    case 1: String.concat(["(", t, ")"])
    case 2: String.concat(["(", t, ")"])
    case 4: String.concat(["make_", t])
    case 5: String.concat(["make_", t])
    case 3: t
    # `float4.of`'s own `_` answer, NOT a second copy of the literal: the census gate's
    # M4 plant anchors on `case _: "None"` and a second copy makes that anchor ambiguous,
    # which is how this line was found. The anchor is a WITNESS and duplicating it blinds it.
    case _: float4.of(dev)

def ku_text_stack(+dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> String:
  String.concat([float4_with(dev, render_type(dev, KU.dtype(k), KU.numel(k), KU.addr(k), KU.op(k), False{})),
    float4_open(dev), String.join(ku_stack_srcs(k, kus, r), ","), float4_close(dev)])

def ku_text.go(op: O.Op, dev: U32, i: U32, k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  match op:
    case O.OpsRANGE{}: [ku_text_range(dev, i, k, kus, r)]
    case O.OpsEND{}: ["}"]
    case O.OpsENDIF{}: ["}"]
    case O.OpsIF{}: [ku_text_if(dev, k, kus, r)]
    case O.OpsBACKEDGE{}: [ku_text_backedge(dev, k, kus, r)]
    case O.OpsCAST{}: ku_text_cast(dev, k, kus, r)
    case O.OpsBITCAST{}: ku_text_bitcast(dev, k, kus, r)
    case O.OpsREFPARAM{}: [ku_text_refparam(dev, k, r)]
    case O.OpsBARRIER{}: [barrier.of(dev)]
    case O.OpsINDEX{}: ku_render_index(dev, k, kus, r)
    case O.OpsSHRINK{}: ku_render_index(dev, k, kus, r)
    case O.OpsLOAD{}: ku_text_load(dev, k, kus, r)
    case O.OpsSTORE{}: ku_text_store(dev, k, kus, r)
    case O.OpsBUFFER{}: [ku_text_buffer(dev, i, k, r)]
    case O.OpsWMMA{}: [ku_text_wmma(dev, k, r)]
    case O.OpsSTACK{}: [ku_text_stack(dev, k, kus, r)]
    case op2: ku_text_alu(dev, op2, k, kus, r)

# `for (;;) {` FOR A VOID RANGE AND `for ({dt} {name} = 0; {name} < {src0}; {name}++) {`
# OTHERWISE -- cstyle.py:17-19.
# `UPat(Ops.STACK, name="x")` -- cstyle.py:52-54:
#   `f"{ctx.float4.replace('float4', ctx.render_type(x))}" + f"{ctx.float4_style[0]}{','.join([ctx[y] for y in x.src])}{ctx.float4_style[1]}"`

# cstyle.py:47 -- `f"{ctx.code_for_workitem[x.arg[0]](x.arg[-1])}; /* {(x.src[0]).render()} */"`.
# IT IS A STATEMENT, not an expression: the workitem id, a `;`, and a comment holding the
# SPECIAL's SOURCE's rendered text (`/* 32 */`). `code_for_workitem.g` already answers the
# id and already refuses base/Clang, which is what CPython's empty dict does.
def ku_text_special(+dev: U32, +k: KU, +r: Rows) -> String:
  String.concat([code_for_workitem.g(dev, KUArg.special_axis(KU.arg(k)), KUArg.special_n(KU.arg(k))),
    "; /* ", rt(r, KU.src0(k)), " */"])

def ku_text(dev: U32, i: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  ku_text.go(KU.op(k), dev, i, k, kus, r)

# THE WRITABLE PARAMS -- cstyle.py:214-215:
#   `writable_params = {u for u in UOp.sink(*[u.src[0] for u in uops if u.op is Ops.STORE]).toposort(...) if u.op is Ops.PARAM}`
# I.E. THE PARAMS A STORE REACHES. THE PORT WALKS BACKWARD FROM EACH STORE'S
# BUFFER THROUGH THE INDEXING OPS, WHICH IS THE SAME SET.
def ku_is_writable(kus: List<&2, List<&2, KU>>, k: KU) -> Bool: False{}
def _render.param(dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, st: St) -> St:
  +nm = ku_param_name(k)
  st_bufs(st_put(st, nm), BArg{nm, KU.dtype(k), KU.addr(k), ku_is_writable(kus, k),
    KUArg.param_volatile(KU.arg(k)), False{}})

# `mutable` IS `u in writable_params` UPSTREAM (cstyle.py:214-215), AND
# `mutable` IS READ BY `_render_dtype` FOR AN **IMAGE** ONLY (cstyle.py:182:
# `if is_image_shape(shape): return f"{'write_only' if mutable else 'read_only'} image2d_t"`).
# NO CPU KERNEL IS AN IMAGE, SO THE FLAG IS NOT READ BY THE C THE PORT EMITS --
# AND THE PORT SAYS SO INSTEAD OF GUESSING A BACKWARD WALK.
def _render.decl(dev: U32, i: U32, +k: KU, kus: List<&2, List<&2, KU>>,
                 +st: St, +l: List<&2, String>, nm: String, ix: U32, +semi: Bool) -> St:
  +st0 = _render.pop(st, k)
  +st1 = st_kernel(st0, String.concat([ku_indent(St.depth(st0)), render_type(dev, KU.dtype(k),
    KU.numel(k), KU.addr(k), KU.op(k), False{}), " ", nm, " = ", String.join(l, ""),
    Bool.pick(String, semi, ";", "")]))
  +st2 = st_c(st1, ix)
  _render.push(st2, k)
# **`match` ON A BOOL PARAMETER IS THE CURE FOR THE WHOLE `Bool.pick` CLASS, AND THIS IS WHY IT IS NEEDED
# HERE.** `Bool.pick(St, is_decl, decl(...), plain(...))` is STRICT: it assembles the DECLARATION and the
# PLAIN statement both -- each with `_render.pop`, `st_kernel`, a `String.concat` and `st_c` -- and throws one
# away. `match` cannot scrutinize a computed value ("a match cannot scrutinize a computed value: give it its
# own def"), but it CAN scrutinize a PARAMETER, so the bool is passed in and only the chosen arm runs.
# MEASURED in `PARITY.md` §39.
def _render.stmt_by(b: Bool, +dev: U32, +i: U32, +k: KU, +kus: List<&2, List<&2, KU>>,                  +st: St, +l: List<&2, String>, +nm: String, +ix: U32, +semi: Bool) -> St:
  match b:
    case True{}: _render.decl(dev, i, k, kus, st, l, nm, ix, semi)
    case False{}: _render.plain(dev, i, k, kus, st, l, nm, ix)

# `if u.op not in {Ops.RANGE, Ops.BUFFER, Ops.BINARY} and u.dtype != dtypes.void:`
# -- cstyle.py:257. IT IS THE TEST FOR "IS THIS A DECLARATION", AND THE
# DECLARATION IS `"{type} {name} = {text};"`.
def _render.stmt(+dev: U32, +i: U32, +k: KU, +kus: List<&2, List<&2, KU>>,                  +st: St, +l: List<&2, String>, +nm: String, +ix: U32, +semi: Bool) -> St:
  _render.stmt_by(ku_is_decl(k), dev, i, k, kus, st, l, nm, ix, semi)

# **`_render.stmt` USED TO RUN FOR EVERY UOP, INLINED OR NOT.** The `Bool.pick` below is strict, so even when
# a uop is INLINED -- which is the common case for casts and indexes -- the full statement was assembled
# (`_render.pop`, `render_type`, a `String.concat`, `st_c`) and thrown away. Same cure as `_render.stmt`:
# the bool goes in as a PARAMETER and `match` runs one arm. MEASURED in `PARITY.md` §39.
def _render.emit_by(b: Bool, dev: U32, +i: U32, +k: KU, +kus: List<&2, List<&2, KU>>,                  +st: St, +l: List<&2, String>, nm: String, ix: U32, +semi: Bool) -> St:
  match b:
    case True{}: st_set.p(st, i, l)
    case False{}: _render.stmt(dev, i, k, kus, st, l, nm, ix, semi)

def _render.emit(dev: U32, +i: U32, +k: KU, +kus: List<&2, List<&2, KU>>,                  +st: St, +l: List<&2, String>, nm: String, ix: U32, +semi: Bool) -> St:
  _render.emit_by(ku_inline(KU.op(k), k, kus), dev, i, k, kus, st, l, nm, ix, semi)

# THE STATEMENT -- cstyle.py:256-261.
def _render.range(+dev: U32, +i: U32, +k: KU, +kus: List<&2, List<&2, KU>>, st: St) -> St:
  +nm = ku_range_name(KU.arg(k))
  +st1 = st_put(st, nm)
  +l = ku_text(dev, i, k, kus, St.r(st1))
  _render.emit(dev, i, k, kus, st1, l, nm, 255, True{})

# cstyle.py:239 -- `if u.op is Ops.SPECIAL: r[u] = u.arg`. THE NAME IS THE ARG, and
# it burns no prefix counter (cstyle.py:261 increments only on the prefix path), so
# `_render.decl` is called with `semi = False` and `st_c` is not reached.
def _render.special(+dev: U32, +i: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +st: St) -> St:
  +nm = KUArg.special_nm(KU.arg(k))
  +st1 = st_put(st, nm)
  _render.decl(dev, i, k, kus, st1, [ku_text_special(dev, k, St.r(st1))], nm, 255, False{})

def pfx_count(+cc: List<&2, U32>, ix: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, cc, U32.to_nat(ix)), 0)

def _render.named(+dev: U32, +i: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +st: St) -> St:
  +ix = ku_pfx_ix(KU.op(k))
  +nm = String.concat([ku_pfx(ix), U32.show(pfx_count(St.c(st), ix))])
  +st1 = st_put(st, nm)
  +l = ku_text(dev, i, k, kus, St.r(st1))
  _render.emit(dev, i, k, kus, st1, l, nm, ix, True{})
def _render.one.go(op: O.Op, dev: U32, i: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +st: St) -> St:
  match op:
    case O.OpsNOOP{}: st_put(st, "")
    case O.OpsCONST{}: st_put(st, "")
    case O.OpsCUSTOM_FUNCTION{}: st_put(st, "")
    case O.OpsSINK{}: st_put(st_name(st, KUArg.sink_name(KU.arg(k))), "")
    case O.OpsSTACK{}: Bool.pick(St, U32.is_eq(KU.nsrc(k), 0), st_put(st, ""),
      _render.named(dev, i, k, kus, st))
    case O.OpsAFTER{}: st_put(st, rt(St.r(st), KU.src0(k)))
    case O.OpsPARAM{}: _render.param(dev, k, kus, st)
    case O.OpsRANGE{}: _render.range(dev, i, k, kus, st)
    case O.OpsSPECIAL{}: _render.special(dev, i, k, kus, st)
    case op2: _render.named(dev, i, k, kus, st)

# THE PARAM -- cstyle.py:231-235. THE NAME IS
# `(arg.name or "data{slot}") + "_" + "_".join(shape)` AND THE PARAM BECOMES
# ONE OF THE KERNEL'S ARGUMENTS.
def _render.one(dev: U32, i: U32, +k: KU, +kus: List<&2, List<&2, KU>>, st: St) -> St:
  _render.one.go(KU.op(k), dev, i, k, kus, st)

def _render.go(+walk: List<&2, KU>, +all: List<&2, List<&2, KU>>, +dev: U32, +i: U32, +st: St) -> St:
  match walk:
    case Nil{}: st
    case h <> t: _render.go(t, all, dev, U32.add(i, 1), _render.one(dev, i, h, all, st))
def _render(dev: U32, +kus: List<&2, KU>) -> St:
  _render.go(kus, chunks_of(kus), dev, 0, St.of(Rows{Nil{}, 0}, Nil{}, Nil{},
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

# cstyle.py:392-401, ONE PER WMMA OP: the {dt_out}2/{dt_in}2 signature, the two
# `simdgroup_...8x8` sets, the two `thread_elements()` loads, the multiply-accumulate and
# the two-lane return. `render_dtype(...)` with no size is the LEGACY width-1 spelling
# (`float`), and the pair with count 2 is `float2`.
def wmma_helper(+dt_in: S.Dt, +dt_out: S.Dt, +nm: String) -> String:
  +din2 = render_dtype_legacy(3, dt_in)
  +dout2 = render_dtype_legacy(3, dt_out)
  +vin2 = render_dtype(3, dt_in, 2, S.AReg{}, True{}, False{}, False{})
  +vout2 = render_dtype(3, dt_out, 2, S.AReg{}, True{}, False{}, False{})
  String.concat([vout2, " __", nm, "(", vin2, " a, ", vin2, " b, ", vout2, " c){\n",
    "  simdgroup_", din2, "8x8 mat_a, mat_b; simdgroup_", dout2, "8x8 mat_c;\n",
    "  mat_a.thread_elements()[0] = a[0]; mat_b.thread_elements()[0] = b[0]; mat_c.thread_elements()[0] = c[0];\n",
    "  mat_a.thread_elements()[1] = a[1]; mat_b.thread_elements()[1] = b[1]; mat_c.thread_elements()[1] = c[1];\n",
    "  simdgroup_multiply_accumulate(mat_c, mat_a, mat_b, mat_c);\n",
    "  return ", vout2, "(mat_c.thread_elements()[0], mat_c.thread_elements()[1]);\n}"])

# **=> AND THE OP TEST IS A MATCH ON A PARAMETER, NOT A `Bool.pick`, AND THE RECURSION
# IS OUTSIDE IT.** Two mistakes were measured here and both are the same class:
#   * `Bool.pick(..., recurse(t, acc+[helper]), recurse(t, acc))` made TWO recursive
#     calls per uop -- the kept one AND the discarded one -- which is 2^n. MEASURED: it
#     hung the Metal render for over 90 s on a 510-uop kernel with no output.
#   * splitting it into `one`/`go` made them MUTUALLY recursive, which Bend refuses.
# ⇒ SO THE FOLD RECURSES ONCE AND THE BRANCH LIVES IN `add`, whose scrutinee is the op
# PARAMETER. One call per uop, and no forward reference.
# AND THE HELPERS ARE DEDUPED, which `wmma_args` does upstream (`dedup(...)`,
# cstyle.py:118): sixteen WMMA uops with the same dims and dtypes are ONE helper, and
# without this the block was emitted sixteen times (MEASURED: 13 063 bytes against
# upstream's 6 012). Deduping on the TEXT is the same test as on the name, because the
# name is inside the text.
def wmma_has(+t: String, +xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: False{}
    case h <> u: Bool.pick(Bool, String.eq(t, h), True{}, wmma_has(t, u))

def wmma_add(+t: String, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, wmma_has(t, acc), acc, List.append(&2, String, acc, [t]))

def wmma_helpers.add(+op: O.Op, +h: KU, +acc: List<&2, String>) -> List<&2, String>:
  match op:
    case O.OpsWMMA{}: wmma_add(wmma_helper(KUArg.wmma_dt_in(KU.arg(h)), KU.dtype(h), ku_wmma_name(h)), acc)
    case _: acc

def wmma_helpers.go(+kus: List<&2, KU>, +acc: List<&2, String>) -> List<&2, String>:
  match kus:
    case Nil{}: acc
    case h <> t: wmma_helpers.go(t, wmma_helpers.add(KU.op(h), h, acc))

def metal_prefix(+bs: List<&2, BArg>, +kus: List<&2, KU>) -> List<&2, String>:
  List.append(&2, String,
    List.append(&2, String,
      ["#include <metal_stdlib>", "using namespace metal;"], wmma_helpers.go(kus, Nil{})),
    [String.concat(["struct args_t { ", String.join(metal_fields(bs, Nil{}), " "), " };"])])

# cstyle.py:312-314 IS THE CLANG OVERRIDE: it emits the vector typedefs. METAL DOES
# NOT -- `MetalRenderer.render_kernel` calls the BASE, which has no `_render_defines`
# at all, which is why upstream's Metal text has native `float2` and no `typedef`.
# **`Bool.pick` IS STRICT, SO THIS USED TO BUILD THE METAL PREFIX ON THE CLANG LANE AND THROW IT AWAY**
# -- `metal_prefix` walks every uop (`wmma_helpers.go`) and `metal_unpack`/`metal_args` build a string per
# buffer. The arm is now chosen by a `match` on a Bool PARAMETER, which is the only form Bend evaluates
# lazily (a `match` cannot scrutinize a computed value). MEASURED, `PARITY.md` §112.
def render_kernel.go(m: Bool, +dev: U32, cpu: Bool, +fn: String, +kernel: List<&2, String>,
                     +bufs: List<&2, BArg>, +kus: List<&2, KU>, +lb: U32) -> String:
  match m:
    case True{}:
      String.concat([String.join(metal_prefix(bufs, kus), "\n"), "\n",
        render_kernel_body(3, fn, metal_unpack(bufs) <> kernel, metal_extra_args(), lb)])
    case False{}:
      String.concat([String.join(_render_defines(dev, cpu, kus), "\n"), "\n",
        render_kernel_body(dev, fn, kernel, ku_args(dev, bufs), lb)])

def render_kernel(+dev: U32, +cpu: Bool, +fn: String, +kernel: List<&2, String>,
                  +bufs: List<&2, BArg>, +kus: List<&2, KU>, +lb: U32) -> String:
  render_kernel.go(U32.is_eq(dev, 3), dev, cpu, fn, kernel, bufs, kus, lb)

# THE WHOLE KERNEL, FROM THE UOP LIST -- cstyle.py:268-278's `render`, FOR THE
# ONE-LINE CASE (NO LINEAR BODIES, NO EXTERN DECLARATIONS).
def render(+dev: U32, cpu: Bool, +kus: List<&2, KU>) -> String:
  +st = _render(dev, kus)
  # **⇒ AND THE REVERSE HAPPENS HERE, ONCE, BECAUSE `st_kernel` PREPENDS.** THE OTHER READERS OF
  # `St.kernel` COPY THE LIST THROUGH UNCHANGED, SO THEY ARE NOT AFFECTED.
  render_kernel(dev, cpu, St.name(st), List.reverse(&2, String, St.kernel(st)), St.bufs(st), kus, 1)

# THE NAME/TEXT MAP, EXPOSED -- the walk's `r`, so a harness can read one slot.

# THE NAME/TEXT MAP, EXPOSED -- the walk's `r`, so a harness can read one slot.
def joins(+ps: List<&2, List<&2, String>>, +acc: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}: acc
    case h <> t: joins(t, List.append(&2, String, acc, [String.join(h, "")]))

# THE NAME/TEXT MAP, EXPOSED -- the walk's `r`, so a harness can read one slot. WITH THE BLOCKED VIEW THE
# MAP IS A LIST OF BLOCKS, SO THIS READS EVERY BLOCK'S PIECES AND JOINS THEM.
def flat_rows(+bs: List<&2, List<&2, List<&2, String>>>) -> List<&2, List<&2, String>>:
  match bs:
    case Nil{}: Nil{}
    case b <> t: List.append(&2, List<&2, String>, flat_rows(t), b)

def render_r(dev: U32, kus: List<&2, KU>) -> List<&2, String>:
  joins(flat_rows(Rows.ts(St.r(_render(dev, kus)))), Nil{})


