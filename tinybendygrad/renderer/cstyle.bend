# tinybendygrad/renderer/cstyle.bend -- the STRING-BUILDING LAYER: a UOp becomes
# C, OpenCL, Metal, CUDA or HIP TEXT.
#
# `String.concat` DROPS A LITERAL SILENTLY, SO A DROPPED ", " TYPECHECKS, RUNS,
# AND EMITS A KERNEL THAT IS WRONG RATHER THAN BROKEN.  THAT IS WHY THE GATE AT

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
# why a tag and not a record with nulls. `float4` is `str|None` and
# `global_max` is `tuple|None`, and a `Data` cannot hold a `Maybe`. A `U32` tag
# has neither problem: the base CStyleLanguage is tag 0 and every device
# OVERRIDES rather than extends, so "the base has no `float4`" is a property of
# the tag, not a null to carry. `render.bend`'s device-NAME table reaches the
# same conclusion the same way.
#
# what the tag does not replace, and this is the honest part:
#   * `code_for_op` is `dict[Ops, Callable]`. A callable is not representable, so
#     it is the device TAG plus a `match` -- `code_for_op.of(dev, op, ..)`. The
#     tag is the only per-device information the ALU table needs, and it is
#     MEASURED: the six devices differ on exactly SIX of the twenty-one ops

import Base
import ./__init__.bend as R
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H
import ./../uop/render.bend as U

# THE DEVICE TAGS. Six renderers plus the abstract `CStyleLanguage`, whose own

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

# `r` is the rendered text of every uop, stored newest-first behind its own length.
# cstyle.py keeps it as a dict keyed by UOp, which is O(1) in both directions; a `List` charges the
# ABSOLUTE INDEX for a lookup and THE WHOLE PREFIX for an append or a set (MEASURED: `rt` 233,235 of the
type Rows is Data:
  Rows{ts: List<&2, List<&2, List<&2, String>>>, n: U32}

def Rows.ts(x: Rows) -> List<&2, List<&2, List<&2, String>>>:
  match x:
    case Rows{ts, n}: ts

def Rows.n(x: Rows) -> U32:
  match x:
    case Rows{ts, n}: n

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

# the readers. a locally-declared `Data` record has no projection syntax at all,
# so `BArg.addr(b)` is "a defined name" until `def BArg.addr` is written by hand.
# MEASURED on 2.0.34 with a three-field record: `BArg.image(b)` and `BArg.name(b)`
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

# the two derived-fact records.  `render_kernel` READS FACTS OUT OF A UOP LIST
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

# everything the prefix layer needs that is not a BUFFER or the body, in one
# record because `render_kernel` would otherwise take twelve arguments. Python's
# own signature is five (`function_name, kernel, bufs, uops, prefix`); the six
# here are this file's substitute for the uop LIST that Python walks, and they
# are grouped rather than spread for that reason and no other.
#
# `caller` and `has_prefix` are the `prefix` ARGUMENT, kept as a pair because
# `prefix=[]` and `prefix=None` are different kernels (cstyle.py:558) and a
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
# `prefix=None` case.  `emit_of` IS THE CONSTRUCTOR BECAUSE THE GATE NEEDS FIVE
# OTHER `Emit_` VALUES.
def emit_of(u: Uses, vecs: List<&2, String>, ockl: List<&2, String>, ocml: List<&2, String>, caller: List<&2, String>, has_prefix: Bool) -> Emit_:
  Emit_{u, vecs, ockl, ocml, caller, has_prefix}

# EVERY `uses` BOOL FALSE: no half, no bf16, no fp8, no non-finite CONST, no
# SPECIAL, no vector prefix, which is the configuration in which four of the five
# vendor prefixes are still non-empty.
def uses_off() -> Uses: Uses{False{}, False{}, False{}, False{}, False{}, False{}}

def emit_min() -> Emit_: emit_of(uses_off(), Nil{}, Nil{}, Nil{}, Nil{}, False{})

# THE OPTION TABLES. One `match` per option, six arms plus the base. They sit
# here rather than at first use because `render_kernel` reads nine of them in one
# expression, and a reader reaching past three other defs for `buffer_suffix`
# would be harder to read than the table it replaced.
#
# EVERY STRING IS MEASURED against CPython on this `tinygrad/` tree, and the
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

# does this typedef have the field at all? Three of the six do and three do not,
# and the head/tail pair ALONE cannot say so: for the three that do not the head
# IS the whole typedef and the tail is empty, so `head ++ lb ++ tail` produced
# `void1` and `__kernel void4`. MEASURED BY THE GATE on all four no-field rows.
def has_bounds(+dev: U32) -> Bool:
  match dev:
    case 4: True{}
    case 5: True{}
    case _: False{}

# `f"{typedef.format(launch_bounds=lb)}"`. ONE DEF, NOT THREE: the head and the
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
# every device's pair: `const ` and `""`. metal does not override either --
# `MetalRenderer` (cstyle.py:366-372) sets `buffer_prefix`, `extra_args`, the workitem
# table and the type map, and NOTHING ELSE.
# - and this used to answer `constant ` and `&` for metal, which was a plausible
# INVENTION AND A WRONG ONE. MEASURED: the census gate's `opt_varpre_3`/`opt_varsuf_3`
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

# `type_map: dict[DType, str]` -- tinygrad/renderer/cstyle.py:136, :287, :331, :373, :439, :539.

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
# with a replace here ONLY because the base is `{}`.
#
# THE ENTRY LIST IS A `Kv` LINKED LIST AND NOT A FLAT `List<&2, String>`, FOR A
def Kv.go(ks: Kv, +m: Map<&2, String>) -> Map<&2, String>:
  match ks:
    case KvEnd{}: m
    case Kv{k, v, t}: Kv.go(t, Map.set(&2, String, m, k, v))

def tm(ks: Kv) -> Map<&2, String>: Kv.go(ks, Map.new(&2, String))

# UPSTREAM'S `{CStyleLanguage.type_map, ...}` IS AN OVERLAY, and this is the
# overlay. The previous version of this port read the base as `{}` and wrote each
# device map as a WHOLE map, which was internally consistent -- `Map.set` over an
# empty map is the map -- and agreed with every `py=` literal, because those
# literals were generated against the same wrong reading. MEASURED at HEAD:
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
# the chain is backwards and that is deliberate. `Kv` is a cons list folded into
# a `Map`, so entry order is not observable -- `Map.set` is order free and
# `type_map.get` reads by key. MEASURED on Bend 2.0.34: this table spelled in
def type_map.cuda() -> Map<&2, String>:
  type_map_over(Kv{"fp8e5m2", "__nv_fp8_e5m2", Kv{"fp8e4m3", "__nv_fp8_e4m3", Kv{"bf16", "nv_bfloat16", Kv{"u32", "uint", KvEnd{}}}}})

# cstyle.py:520-522. `{CStyleLanguage.type_map, {d: ("hip_fp8","hip_bf8")[fp8_index(d)] for d in fp8s}}`
def type_map.hip() -> Map<&2, String>:
  type_map_over(Kv{"fp8e4m3", "hip_fp8", Kv{"fp8e5m2", "hip_bf8",
    Kv{"fp8e4m3fnuz", "hip_fp8", Kv{"fp8e5m2fnuz", "hip_bf8", KvEnd{}}}}})

# THE MAP A DEVICE ANSWERS. Six arms and a `_`, and the `_` IS THE BASE RATHER
# THAN A HOLE: THE BASE IS A REAL FOURTEEN-ENTRY DICT.
def type_map.of(+dev: U32) -> Map<&2, String>:
  match dev:
    case 1: type_map.clang()
    case 2: type_map.opencl()
    case 3: type_map.metal()
    case 4: type_map.cuda()
    case 5: type_map.hip()
    case _: type_map.base()

# `.replace(" ", "_")` -- cstyle.py:189, and it is on the `sz > 1` branch ONLY.
def under_split(nm: String) -> List<&2, String>: String.split(nm, ' ')

# ONE SELF-CALL, and the underscore goes in FRONT of every part after the first.
def under_tail.go(parts: List<&2, String>, seen: Bool) -> String:
  match parts:
    case Nil{}: ""
    case h <> t: String.concat([Bool.pick(String, seen, "_", ""), h, under_tail.go(t, True{})])

def under_general(nm: String) -> String: under_tail.go(under_split(nm), False{})

def under(nm: String) -> String: under_general(nm)

# `_render_dtype` -- cstyle.py:180-190. THE most-read def in the file: it

def is_global(+a: S.Addr) -> Bool:
  match a:
    case S.AGlobal{}: True{}
    case _: False{}

def is_local(+a: S.Addr) -> Bool:
  match a:
    case S.ALocal{}: True{}
    case _: False{}

# `addrspace in (AddrSpace.LOCAL, AddrSpace.GLOBAL)` -- THE SAME SET TWICE IN
# `_render_dtype` (ONCE FOR THE PREFIX, ONCE FOR THE `*`), SO IT IS ONE DEF READ
# BY BOTH RATHER THAN TWO SPELLINGS THAT COULD DRIFT.
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

def under_code_opencl(dev: U32, plain: String, opencl: String) -> String:
  match dev:
    case 2: opencl
    case _: plain

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

# `rd_base_name` is computed once, and that is a measured change. `type_map.of(dev)` builds the device's
# type map on every call -- a `Map` whose keys are Strings, so each insert hashes a string -- and this line
# called `rd_base_name` THREE times, while `rd_body` below called `rd_name` in both arms of a `Bool.pick`,
# i.e. SIX map builds to render ONE dtype. MEASURED with `bun --cpu-prof` on a 405-uop kernel: `render_dtype`
def rd_base_name(+dev: U32, +d: S.Dt) -> String: rd_base_dev(dev, dt_name(d))

# `Bool.pick` evaluates both arms, and that is measured. `Bool.pick` is a `match` in the prelude, but
# the COMPILER turns it into a FUNCTION CALL, so its two arms are JS ARGUMENTS and both are built before
# the call. MEASURED on the 642-uop wire: `rd_body_at` 100 calls, `rd_name_at` 200 calls --
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
# THE `sz > 1` TEST IS A BRANCH, NOT A `Bool.pick`. `Bool.pick`'s arms are eager (see `rd_name_at`),
# so the old line built the vector spelling AND the scalar spelling for EVERY body. MEASURED: `rd_body_at`
def rd_body_at(+dev: U32, +d: S.Dt, +sz: U32, vect: Bool) -> String:
  match vect:
    case True{}: String.concat([rd_name_at(dev, d, True{}), U32.show(sz)])
    case False{}: rd_name_at(dev, d, False{})

def rd_body(+dev: U32, +d: S.Dt, +sz: U32) -> String:
  rd_body_at(dev, d, sz, U32.is_gt(sz, 1))

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
# and it is two arena reads.  IT GUARDS BOTH ALU SUB-BRANCHES, SO IT IS ONE DEF
# RATHER THAN TWO SPELLINGS THAT COULD DRIFT.
def idx_is_const_idx(+ar: O.Arena, +idx: U32) -> Bool:
  Bool.and(is_cast(O.Arena.op(ar, idx)), is_const(O.Arena.op(ar, O.Arena.src0(ar, idx))))

# `'xyzwabcd'[val]`. THE LITERAL IS INLINED RATHER THAN NAMED FOR TWO MEASURED
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

def const_idx_str(+ar: O.Arena, +idx: U32) -> String:
  String.concat(["[", U32.show(swizzle_val(ar, idx)), "]"])

def gep_uses_idx(+dev: U32, numel: U32) -> Bool: U32.is_gt(numel, gep_arr_threshold.of(dev))

def is_add(op: O.Op) -> Bool:
  match op:
    case O.OpsADD{}: True{}
    case _: False{}

# `idx.arg == Ops.ADD` is a test against a literal op and not against a reduce. measured:
#
#   UOp(Ops.REDUCE, arg=Ops.ADD).arg is Ops.ADD            -> True   (the arg IS the enum)
#   UOp(Ops.REDUCE, arg=(Ops.ADD, 0)).arg == Ops.ADD       -> False  (a TUPLE never equals it)
#
# and `UOp.reduce`'s sugar sets the tuple, so a real reduce never strips. the port matched the
# tuple form (`AReduce{ADD,0}`) and so stripped on every real reduce:
#
#   ri_add_0   CPython (buf1+(a+b))   port (buf1+a+b)
#
# A TUPLE CANNOT EQUAL AN OP, so "the arg is `AReduce`" is not the test -- and the arena's
# CLOSED `Arg` spells "the arg IS an op" as `AOpLit`, which is the arm that can match. The old
# comment claimed the `AReduce` arm was "the only way an index node's arg is an op"; the
# measurement above is what says otherwise.
#
# and this branch had no row until a mutation said so. Fixing the defect changed what this
# matches from `AReduce` to `AOpLit`, and the census drove ONE fixture -- `arg=(Ops.ADD, 0)` --
# on which BOTH tests are false, so both lanes took the do-not-strip arm, agreed, and the strip
# had no row anywhere. `gates/cstyle_render_census-mutate.py`'s M8 ("render_index never strips
# parens") moved 0 of 358 rows, which is how the gap was found; `ri_lit_*` now drives
# `AOpLit{OpsADD{}}` -- the shape `upat.py:26`'s `UOp(Ops.PYLITERAL, arg=self.op[0])` builds --
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

# THE WHOLE DEF. PYTHON TAKES `x, buf, idx` AND READS `x` FOR NOTHING AT ALL
# -- IT IS IN THE SIGNATURE SO THE `base_rewrite` ARM CAN PASS `kwargs` -- AND
# IT READS `buf` FOR ITS ADDRESS SPACE, ITS NAME AND ITS ELEMENT COUNT, ALL
# THREE OF WHICH THE PORT TAKES AS PARAMETERS.  WHAT IS LEFT OF THE SIGNATURE
# IS THE INDEX NODE ALONE, WHICH IS WHY THE THIRD PARAMETER IS `idx` AND NOT
def render_index(+ar: O.Arena, +dev: U32, idx: U32, baddr: S.Addr, bname: String, iname: String, bnumel: U32, lane: Bool) -> String:
  render_index.alu2(is_alu_addr(baddr), ar, dev, bname, iname, idx, bnumel, lane)

# `render_buffer` -- cstyle.py:175-178, the `Ops.BUFFER` arm of `base_rewrite`.

def rb_prefix.of(+dev: U32, +a: S.Addr) -> String:
  match a:
    case S.ALocal{}: String.concat([smem_align.of(dev), smem_prefix.of(dev)])
    case _: ""

def rb_prefix(+dev: U32, +a: S.Addr) -> String: rb_prefix.of(dev, a)

def render_buffer(+dev: U32, +d: S.Dt, numel: U32, +a: S.Addr, name: String) -> String:
  String.concat([rb_prefix(dev, a), rd_base_name(dev, d), " ", name, "[", U32.show(numel), "];"])

# `code_for_op` -- cstyle.py:142-150, and the per-device overrides at :288-291,

def cfo_unary(nm: String, +x: List<&2, String>) -> List<&2, String>: List.concat(&2, String, [[nm, "("], x, [")"]])

# `f"(1/{x})"` and `f"-{x}"` are NEITHER of them the unary `f"{nm}({x})"` shape,
# so they are their own defs rather than a "prefix" helper with an empty name.
# `cfo_prefixed("", x)` would be `f"-{x}"` by accident and `cfo_prefixed("1/", x)`
# would be `f"-1/({x})"` -- the unary template has the parens INSIDE, so neither
# spelling of a prefix template reaches these two. MEASURED by the oracle:
def cfo_recip(+x: List<&2, String>) -> List<&2, String>: List.concat(&2, String, [["(1/"], x, [")"]])

def cfo_neg(+x: List<&2, String>) -> List<&2, String>: List.concat(&2, String, [["-"], x])

def cfo_bin(+a: List<&2, String>, sym: String, +b: List<&2, String>) -> List<&2, String>: List.concat(&2, String, [["(", ], a, [sym], b, [")"]])

def cfo_tern(+a: List<&2, String>, +b: List<&2, String>, +c: List<&2, String>) -> List<&2, String>: List.concat(&2, String, [["("], a, ["?"], b, [":"], c, [")"]])

# A DROPPED ARM IS CPython's `code_for_op[x.op]` AND THAT RAISES.  BEND IS
# TOTAL AND CANNOT RAISE, SO THE ANSWER HAS TO BE A STRING, AND `""` IS THE ONE
# STRING THAT IS BOTH A SILENT WRONG ANSWER AND A SPELLING NO C COMPILER
def cfo_unhandled(op: O.Op) -> List<&2, String>: [String.concat(["UNHANDLED(Ops.", O.Ops.name.of(op), ")"])]

# `xs` is the src-name list, `xs0`/`xs1`/`xs2` its three positional reads. `nd` is
def xs_at(xs: List<&2, List<&2, String>>, n: Nat) -> List<&2, String>:
  Maybe.default(&2, List<&2, String>, List.get(&2, List<&2, String>, xs, n), ["?"])

def cfo_xs1(xs: List<&2, List<&2, String>>) -> List<&2, String>: xs_at(xs, 0n)

def cfo_xs2(xs: List<&2, List<&2, String>>) -> List<&2, String>: xs_at(xs, 1n)

def cfo_xs3(xs: List<&2, List<&2, String>>) -> List<&2, String>: xs_at(xs, 2n)

# THE BASE TABLE. `Ops.WHERE` is the ternary and it is matched FIRST because the
# op match is a single `match` and Python's dict has no arity to distinguish it.
# the base table has no `Ops.FDIV` arm and that is correct, not an omission:
# cstyle.py:142-150 is a dict literal of TWENTY-ONE keys and `FDIV` is not one of
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

# the per-device alu overrides. Six ops on CUDA, five on hip, one on Metal, two
# on Clang, and the FIVE THAT ARE DROPPED. `is_half` is the `dtype in (half,
# bfloat16)` test, and it is a `Bool` PARAMETER rather than a dtype so the
# override tables do not each re-derive it.
#
# WHY SIX OF THE ARMS ABOVE ARE SPECIAL, AND IT IS NOT ABOUT THE ALU:
# "C promotes uchar and ushort to int, WGSL holds them in u32 and PTX holds
# uchar in u16, so the ops that wrap compute in uint and narrow after"
# -- cstyle.py:85, upstream's comment ON `pm_narrow_uint`. THE THREE

def is_half(+d: S.Dt) -> Bool:
  Bool.or(O.eq_dt(d, S.half()), O.eq_dt(d, S.bfloat16()))

def is_f64(+d: S.Dt) -> Bool: O.eq_dt(d, S.double())

# THERE IS NO `is_f32`, and the absence is load-bearing rather than an omission:
# Clang's suffix rule is `f` UNLESS f64 (cstyle.py:288-289) and HIP's `_ocml` map
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

# THE DISPATCH. Five devices and the base, and OpenCL and QCOM ARE THE BASE --
# MEASURED: NEITHER OVERRIDES A SINGLE ALU OP, AND THE GATE's `cfo` ROWS ARE
# WHAT SAYS SO RATHER THAN A COMMENT.
def code_for_op.of(+dev: U32, op: O.Op, xs: List<&2, List<&2, String>>, +d: S.Dt) -> List<&2, String>:
  match dev:
    case 1: code_for_clang.of(op, xs, d)
    case 3: code_for_metal.of(op, xs, d)
    case 4: code_for_cuda.of(op, xs, d)
    case 5: code_for_hip.of(op, xs, d)
    case _: code_for_base.of(op, xs)

# `code_for_workitem` -- tinygrad/renderer/cstyle.py:131, :330, :370, :431, :531. Five devices

def witem_xyz(n: U32) -> String: String.from_list([Char.from_u32(U32.add(120, n))])

def witem_miss(+k: String) -> String: String.concat(["UNHANDLED(code_for_workitem[", k, "])"])

def code_for_workitem.g(+dev: U32, +k: String, n: U32) -> String:
  match dev:
    case 2: String.concat([Bool.pick(String, String.eq(k, "g"), "get_group_id(", "get_local_id("), U32.show(n), ")"])
    case 3: String.concat([Bool.pick(String, String.eq(k, "g"), "gid.", "lid."), witem_xyz(n)])
    case 4: String.concat([Bool.pick(String, String.eq(k, "g"), "blockIdx.", "threadIdx."), witem_xyz(n)])
    case 5: String.concat([Bool.pick(String, String.eq(k, "g"), "__ockl_get_group_id(", "__ockl_get_local_id("), U32.show(n), ")"])
    case _: witem_miss(k)

# `_wmma_name` -- cstyle.py:113-117, and the one place a NAME is built from a

def wmma_dims_go(ds: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}: acc
    case h <> t: wmma_dims_go(t, List.append(&2, String, acc, [U32.show(h)]))

def wmma_dims(ds: List<&2, U32>) -> String: String.join(wmma_dims_go(ds, Nil{}), "_")

def wmma_dims.of(+a: O.Arg) -> String:
  match a:
    case O.AWmma{dims, dt, threads, tc}: wmma_dims(dims)
    case _: ""

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

# A BOOL CONST IS AN INT CONST. The `boolean()` arm of `ku_const_cast_int` was ALREADY WRITTEN
# (`"0"`/`"1"`, which is cstyle.py:31's `lambda ctx,c: "1" if c.val else "0"`), but nothing could reach
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

# THE PREFIX TABLE. Upstream's `cstyle.py:242-244`:

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

# stripping the outer parentheses of pieces costs no characters. `cfo_bin` emits `(` and `)` as their
# OWN pieces, so a source with the parent's op is `["(", ...inner..., ")"]` and the strip is dropping those
# two pieces -- the same answer as `H.strip_parens` on the joined string, without joining it (§95.1).
# a 16-way blocked view, because `List.get` is o(INDEX) and this list is indexed 1,915 times per
# RENDER. `ku_at` was 292,722 of the 805,127 list steps a 405-uop render took (MEASURED, `PARITY.md` §76).
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

# every `match` in this block has a parameter for its scrutinee, because Bend
def ku_op_at.go(m: Maybe<&2, KU>) -> O.Op:
  match m:
    case Some{k}: KU.op(k)
    case None{}: O.OpsNOOP{}

def ku_op_at(+kus: List<&2, List<&2, KU>>, i: U32) -> O.Op: ku_op_at.go(ku_at(kus, i))  def ku_is_const_at.go(m: Maybe<&2, KU>) -> Bool:
  match m:
    case Some{k}: KUArg.is_const(KU.arg(k))
    case None{}: False{}
# - and the op equality is a match on the two tags, not a comparison of two numbers. measured
# (`PARITY.md` §138): `O.eq_op` IS `U32.is_eq(Ops.value(x), Ops.value(y))`, - AND `Ops.value`
# compiles to a 76-arm `===` chain on the tag (the generated code is `if (_op_0.$ ===
# "OpsSPECIAL") ... else if (_op_0.$ === "OpsBUFFER")`), - SO `O.eq_op` WAS ~152 STRING
# comparisons. measured on the 782-uop wire: 30,640 `Ops.value` calls and 15,320 `O.eq_op` calls a
# render (~40 and ~20 a uop), - and every single `Ops.value` call came from `O.eq_op` (30,640 =
# 2 x 15,320). - and the profile puts them at `uop_ops_Ops_value` 0.293 ms and `uop_ops_eq_op`
# 0.193 ms A TURN -- A THIRD OF THE PORT's 1.412 ms.
#
# - and the port already spells variant equality this way (`ops.bend`'s own `eq_opt_u32`,
# `eq_opt_str`, `eq_optbool` and `eq_optarg` all use `match x y:` with one arm per variant) -- - and
# a match on two scrutinees compiles to nested tag comparisons (measured in the generated code:
# `if (_x_0.$ === "OpsA") { if (_y_0.$ === "OpsA") ... }`), - SO THE AVERAGE COST IS TWO
# COMPARISONS INSTEAD OF 152.
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

# the text of one uop -- the port of `base_rewrite` (cstyle.py:11-77), for the
# ops the CPU lane needs. the order is upstream's order, and the order is the
# RULE: the CONST arms come BEFORE the generic CAST arm.

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
# the strip is the same-op test and it is not cosmetic: it is what makes
# `((x)+(y))` AND `((x)+(y)+(z))` COMPOSE.
def ku_strips(+op: O.Op) -> Bool:
  Bool.or(Bool.or(is_add(op), is_mul(op)),
    Bool.or(is_xor(op), Bool.or(is_or(op), is_and(op))))

# the walk -- the port of `cstyle.py:208-266`'s body. the state is six things

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

# `r` GROWS BY ONE ENTRY PER UOP, INCLUDING THE SKIPPED ONES, BECAUSE `r` IS
# INDEXED BY THE UOP's POSITION AND THE POSITIONS OF THE LATER UOPS MUST NOT
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

# - and the kernel's lines are prepended, and reversed once at the read. measured
# (`PARITY.md` §137): `List.append(xs, ys)` IN BEND COPIES `xs`, SO `List.append(acc, [x])` IS O(n)
# and `List.append([x], acc)` is o(1). - and `st_kernel` was the o(n) form, and it is called once
# per emitted line. measured, the census of the `List.append` entry calls (the recursion excluded):
# `st_kernel` 407 CALLS COPYING 82,039 ELEMENTS (MAX 404), `chunk_close` 49/1,176, `List_concat`
def st_kernel(+st: St, x: String) -> St:
  St.of(St.r(st), List.append(&2, String, [x], St.kernel(st)), St.bufs(st), St.c(st), St.depth(st), St.name(st))

def st_bufs(+st: St, x: BArg) -> St:
  St.of(St.r(st), St.kernel(st), List.append(&2, BArg, St.bufs(st), [x]), St.c(st), St.depth(st), St.name(st))

# "NOTE: this relies on bufs dict preserving order" -- cstyle.py:275,
# upstream's comment ON THE `bufs` HAND-BACK, AND IT IS A GOTCHA ABOUT
# PYTHON'S DICT THAT THE PORT DOES NOT HAVE AND MUST NOT INHERIT BLINDLY.
#
# UPSTREAM'S `bufs` IS A `dict[UOp, tuple[str, tuple[UOp, bool]]]` AND
# `_render` RETURNS `list(bufs.values())` -- AND THE ORDER OF THAT LIST IS
# THE ORDER THE KERNEL'S ARGUMENTS ARE DECLARED IN. PYTHON 3.7+ DICTS
# PRESERVE INSERTION ORDER, SO THE ORDER IS THE ORDER THE `Ops.PARAM` NODES
# APPEAR IN THE WALK, AND THE WALK IS TOPOLOGICAL. UPSTREAM'S NOTE IS
# SAYING: THIS ORDER IS NOT AN ACCIDENT AND NOT A SORT -- IT IS THE
# INSERTION ORDER, AND THE EMITTED FUNCTION SIGNATURE DEPENDS ON IT.
#
# THE PORT'S `st_bufs` APPENDS, SO IT HAS THE SAME PROPERTY AND IT HAS IT
# FOR THE SAME REASON: `List.append` PUTS THE NEW `BArg` AT THE END, SO THE
# PORT'S `St.bufs` IS IN THE ORDER THE PARAMS WERE SEEN. THE PORT SAYS SO
# HERE BECAUSE THE PROPERTY IS INVISIBLE IN A SINGLE-BUFFER KERNEL AND A
# REVERSED ORDER WOULD STILL COMPILE.
#
# AND THE PORT'S ORDER IS NOT QUITE UPSTREAM'S, WHICH IS STATED RATHER THAN
# PAPERED OVER: UPSTREAM'S LIST IS IN WALK ORDER, AND THE PORT'S WALK IS
# ALSO TOPOLOGICAL, BUT THE PORT'S `_render` VISITS A `Params` ARM THROUGH
# `_render.go`'s CHUNKED WALK, AND THE PARAM ARM IS REACHED IN WALK ORDER --
# SO THE TWO AGREE, AND THE ROW THAT WOULD SEE IT IS THE KERNEL SIGNATURE
# ROW, WHICH IS A STRING AND NOT A COUNT.

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
def ku_indent(depth: U32) -> String:
  ku_indent.go(U32.to_nat(depth), "")

def ku_inline2a(+op: O.Op, k: KU, +kus: List<&2, List<&2, KU>>) -> Bool:
  Bool.or(Bool.and(is_cast(op), ku_is_const_at(kus, KU.src0(k))),
    Bool.or(Bool.or(is_index(op), is_shrink(op)),
      Bool.or(is_customi(op), is_refparam(op))))

def ku_inline2b2a(+op: O.Op, +k: KU) -> Bool:
  Bool.and(Bool.or(is_cast(op), is_bitcast(op)),
    Bool.or(is_global(KU.addr(k)), is_local(KU.addr(k))))

def cc_at(k: KU) -> U32: KU.cc(k)

def ku_src_is_reg.go(m: Maybe<&2, KU>) -> Bool:
  match m:
    case Some{s}: is_reg(KU.addr(s))
    case None{}: False{}

def ku_src_is_reg(+kus: List<&2, List<&2, KU>>, k: KU) -> Bool:
  ku_src_is_reg.go(ku_at(kus, KU.src0(k)))

def ku_is_alu_ex_where(+op: O.Op) -> Bool:
  Bool.and(R.is_alu(op), Bool.not(is_where(op)))

# THE WALK, ONE UOP AT A TIME. cstyle.py:221-262.

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
def ku_align(cpu: Bool, +dt: S.Dt, +count: U32) -> U32:
  Bool.pick(U32, cpu, S.Dt.itemsize(dt),
    Bool.pick(U32, S.Dt.is_bool(dt), 1, U32.shln(1, U32.log2(U32.mul(S.Dt.itemsize(dt), count)))))

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

# the text of one uop -- the port of `base_rewrite` (cstyle.py:11-77), for the
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
  # the semicolon is the whole difference, so it is chosen as a string (two literals,
  # free) and the line is assembled ONCE.  THE PREVIOUS SPELLING BUILT TWO
  # `st_kernel` CALLS AND DISCARDED ONE.
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

# `numel > 1` is applied here, not only at emit time, and the bytes are unchanged because the list has
# ONE CONSUMER. `_render_defines.go` asks `U32.is_gt(DtN.n(h), 1)` and emits nothing for the rest, so a
# pair with `n == 1` was collected, deduped and scanned to produce nothing. MEASURED (`PARITY.md` §117): the
def uops_to_dtypes.one(+k: KU, +acc: List<&2, DtN>) -> List<&2, DtN>:
  Bool.pick(List<&2, DtN>,
    Bool.and(Bool.and(is_alu_addr(KU.addr(k)), Bool.not(O.eq_dt(KU.dtype(k), S.void()))),
      U32.is_gt(KU.numel(k), 1)),
    uops_to_dtypes.put(DtN{KU.dtype(k), KU.numel(k)}, acc), acc)

def ku_inline2b(+op: O.Op, +k: KU, +kus: List<&2, List<&2, KU>>) -> Bool:
  Bool.or(ku_inline2b1(op, k, kus), ku_inline2b2(op, k))
def ku_inline2(+op: O.Op, +k: KU, +kus: List<&2, List<&2, KU>>) -> Bool:
  Bool.or(ku_inline2a(op, k, kus), ku_inline2b(op, k, kus))

def ku_inline(+op: O.Op, +k: KU, +kus: List<&2, List<&2, KU>>) -> Bool:
  Bool.and(Bool.or(Bool.not(is_cast(op)), U32.is_eq(KU.numel(k), 1)),
    ku_inline2(op, k, kus))

def BArg.image(b: BArg) -> Bool:
  match b:
    case BArg{name, dtype, addr, mutable, volatile_, image}: image

# `uops_to_dtypes(uops)` and the four `any(...)` scans in the six `render_kernel`
# overrides, each reduced to the Bool it is tested for. `nonfinite` is the CAST
# of a non-finite CONST (cstyle.py:559) and `special` is `any(Ops.SPECIAL)`
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
# and `dsl.bend:1553-1555` records that "an empty string is NOT the same answer, so the
# port prints `None`". CPython prints `None` too (`str(None)`), so this row now AGREES
# instead of being a declared divergence.
#
# what it still does not buy: the stack arm is not ported, so nothing reads it yet, and
# `"None"` is still a string rather than an absence -- `.replace` on it is a no-op where
# CPython raises `AttributeError`. That gap is named rather than papered over with a
# `has_float4` Bool that nothing reads.
#   TODO(p3) cstyle.py:55-56  `base_rewrite`'s `Ops.STACK` arm. It needs
def render_dtype(+dev: U32, +d: S.Dt, sz: U32, +a: S.Addr, mutable: Bool, override_ptr: Bool, img: Bool) -> String:
  Bool.pick(String, img, rd_image(mutable),
    String.concat([rd_prefix(dev, a), rd_body(dev, d, sz), rd_suffix(a, override_ptr)]))

# `render_dtype(dt, mutable=True)` -- cstyle.py:203, marked `# LEGACY`. It is
# `_render_dtype(dt, 1, AddrSpace.REG)`, so the REG address space is the load-
# bearing argument: it is what makes the answer carry no `*` and no prefix, and
# `render_cast`'s `({render_type(u)})({val})` depends on that.
def render_dtype_legacy(+dev: U32, +d: S.Dt) -> String:
  render_dtype(dev, d, 1, S.AReg{}, True{}, False{}, False{})

# `render_type` / `render_ptr` / `render_access` / `render_cast` -- cstyle.py:
# 192-200.  Four defs, and together they are the pointer/cast vocabulary every
# load and store is written in.
#
#     def render_type(self, u): return self._render_dtype(u.dtype, u.max_numel(), u.addrspace,
#         shape=u._shape, override_ptr=u.op is Ops.INDEX and u.addrspace is AddrSpace.REG)
#     def render_ptr(self, u):
#
# `render_type` IS THE ONE THAT NEEDS THE FOLD (dtype, addrspace, shape, op) AND
# SO IT IS WHERE WALL (a) BITES; IT IS PORTED WITH THOSE AS PARAMETERS, WHICH IS
# THE SAME ARGUMENT AS `_render_dtype` AND FOR THE SAME REASON.  THE PYTHON
# SIGNATURE TAKES A `u` AND THE VALUES PYTHON READS OFF IT ARE EXACTLY THESE
# FOUR, SO THE PORT's SIGNATURE IS THE SAME SET OF FACTS WITH THE READ MOVED TO
# THE CALLER -- WHICH IS WHERE THE FOLD LIVES.
#
# `override_ptr=u.op is Ops.INDEX and u.addrspace is AddrSpace.REG` IS THE ONE TO
# WATCH: A REG-SPACE INDEX IS A VECTOR REGISTER AND RENDERS AS A POINTER, SO
# `render_type` OF A REG INDEX IS `float4*` AND NOT `float4`.  THAT IS MEASURED

def render_type(+dev: U32, +d: S.Dt, +numel: U32, +a: S.Addr, op: O.Op, img: Bool) -> String:
  render_dtype(dev, d, numel, a, True{}, Bool.and(is_index(op), is_reg(a)), img)

# `render_ptr`. The `dtype != u.src[0].dtype` half is a DTYPE COMPARISON between
# the access and its buffer, and it is the half that decides whether a load goes
# through a cast pointer: a `float4` read of a `float` buffer is
# `((float4*)(buf))` and a `float` read of the same buffer is `buf`. `vec` is the
# `max_numel() > 1` half and `diff` the dtype half, kept apart so the gate can
# pin each: `ptr stack4` is the `vec` arm and `ptr bitcast` the `diff` arm.
#
# UPSTREAM'S ONE-LINE FRAMING OF THE SAME THING -- "the address of an access,
# vector-cast if the access reads/writes more lanes than the pointer's scalar
# type" (cstyle.py:206) -- IS WORTH THE PORT'S ATTENTION BECAUSE IT SAYS
def render_ptr(+dev: U32, +d: S.Dt, +numel: U32, +a: S.Addr, sdt: S.Dt, +name: String, op: O.Op, img: Bool) -> String:
  Bool.pick(String, Bool.or(U32.is_gt(numel, 1), Bool.not(O.eq_dt(d, sdt))),
    String.concat(["((", render_dtype(dev, d, numel, a, True{}, True{}, img), ")(", name, "))"]), name)

def render_access(+dev: U32, +d: S.Dt, numel: U32, +a: S.Addr, +sdt: S.Dt, +name: String, op: O.Op, img: Bool) -> String:
  String.concat(["*", render_ptr(dev, d, numel, a, sdt, name, op, img)])

def render_cast(+dev: U32, +d: S.Dt, numel: U32, +a: S.Addr, op: O.Op, img: Bool, val: String) -> String:
  String.concat(["(", render_type(dev, d, numel, a, op, img), ")(", val, ")"])

def render_cast_p(+dev: U32, +d: S.Dt, numel: U32, +a: S.Addr, op: O.Op, img: Bool, +val: List<&2, String>) -> List<&2, String>:
  List.concat(&2, String, [[String.concat(["(", render_type(dev, d, numel, a, op, img), ")("])], val, [")"]])

# `render_index` -- cstyle.py:168-173. SIX branches in Python and they reduce to

def wmma_name(+a: O.Arg, dout: S.Dt) -> String:
  wmma_name_of(wmma_dims.of(a), wmma_in.of(a), dt_name(dout))

# `uops_to_dtypes` -- cstyle.py:112-113.

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
def ku_cast_wrapped(dev: U32, d: S.Dt, v: String) -> String:
  String.concat(["(", render_cast(dev, d, 1, S.Aalu{}, O.OpsCAST{}, False{}, v), ")"])

# the CAST is computed once too, and for the same reason as the decimal above. `ku_cast_wrapped` is in
# FOUR arms of the chain below and `Bool.pick` evaluates every arm, so the port was rendering the same cast
# four times per integer constant and using one -- and a cast render is a `render_cast` -> `render_dtype`,
# i.e. a whole dtype render each time. MEASURED in `PARITY.md` §34.
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

# the decimal is computed once and passed in, and that is a measured change. `Bool.pick` is strict here,
# so every arm of the chain below is EVALUATED and one is chosen: this def used to call `H.i64_dec(i)` SEVEN
# times per integer constant, six of whose results were discarded. MEASURED on the shipped path
def ku_const_cast_int(+dt: S.Dt, +dev: U32, k: KU, +i: H.I64) -> String:
  ku_const_cast_int_at(H.i64_dec(i), dt, dev, k, i)

# A NON-FINITE FLOAT IS NOT `repr(v) + "f"`. `cstyle.py:26` spells the const as
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
              # THE FALLBACK IS BARE, NOT CAST-WRAPPED. cstyle.py:39 is
              U.f32_repr(f)))))

# THE GENERIC CAST: `f"({ctx.render_cast(x, ctx[x.src[0]])})"` (cstyle.py:40).
def ku_cast_generic(dev: U32, +k: KU, +r: Rows) -> List<&2, String>:
  List.concat(&2, String, [["("], render_cast_p(dev, KU.dtype(k), KU.numel(k), KU.addr(k), O.OpsCAST{},
    False{}, rtp(r, KU.src0(k))), [")"]])

# `render_index` -- cstyle.py:169-174. THE `KU`-WORLD TWIN OF THIS FILE'S

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

# this was a duplicate of `ku_const_cast`, and `Bool.pick` being strict made it pay twice. The two defs
# held the SAME conditional -- `Bool.pick(ku_is_const_at(src0), const-path, generic-path)` -- and the CAST arm
# of `ku_text_go` called the outer one, which called the inner one, so a CAST line evaluated
# `ku_is_const_at` twice and BOTH arms twice: `ku_const_cast2` and `ku_cast_generic` each ran twice and one of
# each was thrown away. MEASURED in `PARITY.md` §38. One call, byte-identical.
def ku_text_cast(+dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  ku_const_cast(dev, k, kus, r)

# `BITCAST` -- cstyle.py:41-43 (the BASE's two rules), :338 (OpenCL `as_<dt>`), :386
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

# TWO PARENS, NOT THREE. upstream cstyle.py:42-43 is `f"(({_render_dtype(x.dtype, addrspace=x.addrspace)})({ctx[x.src[0]]}))"`
# and `_render_dtype` returns a bare spelling like `unsigned long*` (cstyle.py:191-202 adds only a prefix and a
# `*`), so the cast text is `((unsigned long*)(args_24))`. MEASURED: the port carried a third `(` here and it was
# INVISIBLE until the packed-args ABI made a GLOBAL BITCAST appear in every kernel (PARITY.md §116).
def bitcast_text(+dev: U32, +a: S.Addr, +d: S.Dt, +sd: S.Dt, +s: String) -> String:
  match a:
    case S.AGlobal{}: String.concat(["((", render_dtype(dev, d, 1, a, False{}, False{}, False{}), ")(", s, "))"])
    case S.ALocal{}: String.concat(["((", render_dtype(dev, d, 1, a, False{}, False{}, False{}), ")(", s, "))"])
    case _: bitcast_named(dev, d, sd, s)

# `f"(({ctx.param_type(x)})({ctx[x.src[1]]}))"` (cstyle.py:44), where `param_type` is
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
# the whole point and it was missing: the device's maker is spelled with the literal
# `float4`, and the STACK's OWN type replaces it, so a two-lane STACK is `float2(...)` and
# NOT `float4(...)`. MEASURED: without it the port's WMMA call read
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

# A BARE CONST -- `UPat.cvar("c").cast()` WITH NO DTYPE CHANGE, cstyle.py:33's last const
# arm: `{c.val}`. `ku_text.go` had no CONST arm, so a bare CONST fell through to the ALU
# path and printed NOTHING. MEASURED: the RESHAPE's modulus divisor is a bare CONST whose
# value is right (20/12/15) and whose row was empty, so the C read `...%` with no divisor.
def ku_const_repr(v: O.Const) -> String:
  match v:
    case O.CInt{i}: H.i64_dec(i)
    case _: ""

def ku_const_repr.of(a: KUArg) -> String:
  match a:
    case KAConst{v}: ku_const_repr(v)
    case _: ""

def ku_text_const(+k: KU) -> List<&2, String>:
  [ku_const_repr.of(KU.arg(k))]

def ku_text.go(op: O.Op, dev: U32, i: U32, k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  match op:
    case O.OpsCONST{}: ku_text_const(k)
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
def ku_text_special(+dev: U32, +k: KU, +r: Rows) -> String:
  String.concat([code_for_workitem.g(dev, KUArg.special_axis(KU.arg(k)), KUArg.special_n(KU.arg(k))),
    "; /* ", rt(r, KU.src0(k)), " */"])

def ku_text(dev: U32, i: U32, +k: KU, +kus: List<&2, List<&2, KU>>, +r: Rows) -> List<&2, String>:
  ku_text.go(KU.op(k), dev, i, k, kus, r)

# THE WRITABLE PARAMS -- cstyle.py:214-215:
def ku_is_writable(kus: List<&2, List<&2, KU>>, k: KU) -> Bool: False{}
def _render.param(dev: U32, +k: KU, +kus: List<&2, List<&2, KU>>, st: St) -> St:
  +nm = ku_param_name(k)
  st_bufs(st_put(st, nm), BArg{nm, KU.dtype(k), KU.addr(k), ku_is_writable(kus, k),
    KUArg.param_volatile(KU.arg(k)), False{}})

# `mutable` IS `u in writable_params` UPSTREAM (cstyle.py:214-215), AND
# `mutable` IS READ BY `_render_dtype` FOR AN IMAGE ONLY (cstyle.py:182:
def _render.decl(dev: U32, i: U32, +k: KU, kus: List<&2, List<&2, KU>>,
                 +st: St, +l: List<&2, String>, nm: String, ix: U32, +semi: Bool) -> St:
  +st0 = _render.pop(st, k)
  +st1 = st_kernel(st0, String.concat([ku_indent(St.depth(st0)), render_type(dev, KU.dtype(k),
    KU.numel(k), KU.addr(k), KU.op(k), False{}), " ", nm, " = ", String.join(l, ""),
    Bool.pick(String, semi, ";", "")]))
  +st2 = st_c(st1, ix)
  _render.push(st2, k)
# `match` on a BOOL parameter is the cure for the whole `Bool.pick` class, and this is why it is needed
# HERE. `Bool.pick(St, is_decl, decl(...), plain(...))` is STRICT: it assembles the DECLARATION and the
# PLAIN statement both -- each with `_render.pop`, `st_kernel`, a `String.concat` and `st_c` -- and throws one
# away. `match` cannot scrutinize a computed value ("a match cannot scrutinize a computed value: give it its
# own def"), but it CAN scrutinize a PARAMETER, so the bool is passed in and only the chosen arm runs.
# MEASURED in `PARITY.md` §39.
def _render.stmt_by(b: Bool, +dev: U32, +i: U32, +k: KU, +kus: List<&2, List<&2, KU>>,                  +st: St, +l: List<&2, String>, +nm: String, +ix: U32, +semi: Bool) -> St:
  match b:
    case True{}: _render.decl(dev, i, k, kus, st, l, nm, ix, semi)
    case False{}: _render.plain(dev, i, k, kus, st, l, nm, ix)

# `if u.op not in {Ops.RANGE, Ops.BUFFER, Ops.BINARY} and u.dtype != dtypes.void:`
# -- cstyle.py:257. it is the test for "is this a declaration", and the
# DECLARATION IS `"{type} {name} = {text};"`.
def _render.stmt(+dev: U32, +i: U32, +k: KU, +kus: List<&2, List<&2, KU>>,                  +st: St, +l: List<&2, String>, +nm: String, +ix: U32, +semi: Bool) -> St:
  _render.stmt_by(ku_is_decl(k), dev, i, k, kus, st, l, nm, ix, semi)

# `_render.stmt` used to run for every uop, inlined or not. The `Bool.pick` below is strict, so even when
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
    " __attribute__((aligned(", U32.show(ku_align(cpu, dt, count)), "),ext_vector_type(", U32.show(count), ")));"])

def _render_defines.go(+xs: List<&2, DtN>, +dev: U32, +cpu: Bool, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t:
      Bool.pick(List<&2, String>, U32.is_gt(DtN.n(h), 1),
        _render_defines.go(t, dev, cpu, List.append(&2, String, acc,
          [render_vector_prefix(dev, cpu, DtN.dt(h), DtN.n(h))])),
        _render_defines.go(t, dev, cpu, acc))

# `render_kernel` -- cstyle.py:155-167 (THE BODY) AND cstyle.py:312-314 (THE

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

# METAL'S KERNEL SIGNATURE -- cstyle.py:366-372 AND :390-403. Metal is the one

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

# => and the op test is a match on a parameter, not a `Bool.pick`, and the recursion
# IS OUTSIDE IT. Two mistakes were measured here and both are the same class:
#   * `Bool.pick(..., recurse(t, acc+[helper]), recurse(t, acc))` made TWO recursive
#     calls per uop -- the kept one AND the discarded one -- which is 2^n. MEASURED: it
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

# the whole kernel, from the uop list -- cstyle.py:268-278's `render`, for the
# one-line case (no linear bodies, no extern declarations).
def render(+dev: U32, cpu: Bool, +kus: List<&2, KU>) -> String:
  +st = _render(dev, kus)
  # - and the reverse happens here, once, because `st_kernel` prepends.  the other
  # readers of `St.kernel` COPY the list through unchanged, so they are not affected.
  render_kernel(dev, cpu, St.name(st), List.reverse(&2, String, St.kernel(st)), St.bufs(st), kus, 1)

# THE NAME/TEXT MAP, EXPOSED -- the walk's `r`, so a harness can read one slot.
def joins(+ps: List<&2, List<&2, String>>, +acc: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}: acc
    case h <> t: joins(t, List.append(&2, String, acc, [String.join(h, "")]))

# the name/text map, exposed -- the walk's `r`, so a harness can read one slot. with the blocked view the
# map is a list of blocks, so this reads every block's pieces and joins them.
def flat_rows(+bs: List<&2, List<&2, List<&2, String>>>) -> List<&2, List<&2, String>>:
  match bs:
    case Nil{}: Nil{}
    case b <> t: List.append(&2, List<&2, String>, flat_rows(t), b)

def render_r(dev: U32, kus: List<&2, KU>) -> List<&2, String>:
  joins(flat_rows(Rows.ts(St.r(_render(dev, kus)))), Nil{})
