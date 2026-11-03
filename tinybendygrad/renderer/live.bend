# live.bend -- RENDER A KERNEL FROM TEXT, so the renderer is COMPILED ONCE and fed kernels at runtime.
#
# WHY THIS EXISTS. `cstyle.bend`'s `render` takes a `List<KU>` -- a Bend VALUE -- so `.agents/slop/cpuseam/
# portc.py` used to compile the kernel INTO the driver as a literal, one `bin/bend` build per kernel. What
# that build pays for is the TYPECHECK OF THE CLOSURE, not the kernel: MEASURED 2026-11-03, a driver holding
# ONE kernel builds in 941 ms and a driver holding SIX in 967 ms. So a caller that renders K distinct
# kernels paid ~1 s x K, and an actual program does exactly that -- it asks for one kernel at a time, in the
# order the scheduler needs them.
#
# WITH THIS FILE the renderer is built ONCE (its JS output is cached by `portc.py` against the sources that
# can change the C) and every later kernel is a `bun` RUN: `~40 ms` of start-up plus the parse below,
# instead of a second of typechecking.
#
# THE DIVISION OF LABOUR IS THE WHOLE DESIGN: PYTHON DECODES, BEND CONSTRUCTS.
#   * a CONST's value arrives as EXACT BITS -- `hi~lo` for an integer, the f32 bit pattern for a float,
#     `0`/`1` for a bool -- because parsing `1e999`, `inf`, `-0.0` and `-1.44` out of TEXT is where this
#     renderer's predecessor had four separate defects (`gen_kus.py`'s `const_arg` records each one).
#     `F32.from_bits` cannot disagree with `struct.pack('<f', ...)` about a value, and `i64_of_hi_lo`
#     cannot truncate a 64-bit constant the way `i64_of_i32` did.
#   * the ARG's own tag rides in the `kind` field (`range_GLOBAL`, `wmma_f32`, ...), so this file never has
#     to SLICE a payload: Bend refuses `match` on a computed value and on a value bound after a parameter,
#     and every slicing design ended in one of those two.
#   * so every field below is a NAME matched by `match`, or an unsigned decimal read by `U32.read`. There
#     is no float parser, no sign parser, and no substring surgery here.
#
# THE OP TABLE IS NOT RETYPED: `runtime/ops_python.bend`'s `op_of(String)` is the executor's own name ->
# `Op` mapping, and it is IMPORTED, so a name the executor runs and a name this file renders cannot drift
# apart. It covers 46 of the enum's 75 members because the EXECUTOR only runs what it ports; the other 29
# are added in `extra_op` below, and `P.op_of` still answers first.
#
# THE WIRE, one kernel = newline-separated uop lines, each EIGHT space-separated fields:
#
#   op dt addr shape numel kind payload srcs
#
#   shape    `-` or `4~4`
#   kind     one of the tags listed in `arg_of` below
#   payload  `~`-separated; `-` when the op carries nothing
#   srcs     `-` or `0~1~2`   (ZERO-based: the decoder has already done the `- 1`)
import Base
import ./cstyle.bend as C
import ./../uop/ops.bend as O
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H
import ./../base.bend as F
import ./../runtime/ops_python.bend as P

def nlch() -> Char: Maybe.default(&2, Char, String.get("\n", 0n), ' ')

def fld(ws: List<&2, String>, i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, ws, i), "")

def u32(s: String) -> U32: Maybe.default(&2, U32, U32.read(s), 0)

def ysplit(s: String) -> List<&2, String>: String.split(s, '~')

def field(p: String, i: Nat) -> String: fld(ysplit(p), i)

def flag(s: String) -> Bool: String.eq(s, "1")

def truth(s: String) -> Bool:
  match s:
    case "1": True{}
    case _: False{}

def maybe_name(nm: String) -> Maybe<&2, String>:
  match nm:
    case "-": None{}
    case _: Some{nm}

# ---------------------------------------------------------------- names -> the port's own values
def dt_of(nm: String) -> S.Dt:
  match nm:
    case "f32": S.single()
    case "i32": S.int32()
    case "u32": S.uint32()
    case "i64": S.int64()
    case "u64": S.uint64()
    case "u8": S.uint8()
    case "i8": S.int8()
    case "u16": S.uint16()
    case "i16": S.int16()
    case "bool": S.boolean()
    case "void": S.void()
    case "weakint": S.weakint()
    case "weakfloat": S.weakfloat()
    case "f16": S.half()
    case "bf16": S.bfloat16()
    case "f64": S.double()
    case _: S.void()

def addr_of(nm: String) -> S.Addr:
  match nm:
    case "GLOBAL": S.AGlobal{}
    case "LOCAL": S.ALocal{}
    case "REG": S.AReg{}
    case _: S.Aalu{}

# **`P.op_of` IS THE EXECUTOR's TABLE AND IT COVERS 46 OF THE ENUM's 75 MEMBERS, BECAUSE THE EXECUTOR ONLY
# RUNS WHAT IT PORTS.** A renderer sees every op a program lowers to, so the missing 29 are added here and
# `P.op_of` still answers first -- one table for the ops both need, one addition for the rest. MEASURED what
# a gap costs: `PAD` and `MSELECT` fell to the default and the kernel rendered `(float4){,,,}`, a plausible
# line that compiled and was wrong.
def extra_op(nm: String) -> O.Op:
  match nm:
    case "ALLOC": O.OpsALLOC{}
    case "ALLREDUCE": O.OpsALLREDUCE{}
    case "BINARY": O.OpsBINARY{}
    case "CALL": O.OpsCALL{}
    case "CONTIGUOUS_BACKWARD": O.OpsCONTIGUOUS_BACKWARD{}
    case "COPY": O.OpsCOPY{}
    case "CUSTOM": O.OpsCUSTOM{}
    case "CUSTOMI": O.OpsCUSTOMI{}
    case "CUSTOM_FUNCTION": O.OpsCUSTOM_FUNCTION{}
    case "DETACH": O.OpsDETACH{}
    case "EXPAND": O.OpsEXPAND{}
    case "FDIV": O.OpsFDIV{}
    case "GETADDR": O.OpsGETADDR{}
    case "INS": O.OpsINS{}
    case "LINEAR": O.OpsLINEAR{}
    case "MSELECT": O.OpsMSELECT{}
    case "MSTACK": O.OpsMSTACK{}
    case "PAD": O.OpsPAD{}
    case "PERMUTE": O.OpsPERMUTE{}
    case "PROGRAM": O.OpsPROGRAM{}
    case "PYLITERAL": O.OpsPYLITERAL{}
    case "REDUCE": O.OpsREDUCE{}
    case "RESHAPE": O.OpsRESHAPE{}
    case "REWRITE_ERROR": O.OpsREWRITE_ERROR{}
    case "SOURCE": O.OpsSOURCE{}
    case "STAGE": O.OpsSTAGE{}
    case "THREEFRY": O.OpsTHREEFRY{}
    case "UNSHARD": O.OpsUNSHARD{}
    case "WMMA": O.OpsWMMA{}
    case _: O.OpsCONST{}

def op_of(+nm: String) -> O.Op: Maybe.default(&1, O.Op, P.op_of(nm), extra_op(nm))

# ---------------------------------------------------------------- numbers
# **NO `List.reverse` HERE, AND THAT IS MEASURED, NOT STYLE.** `List.append(&2, A, acc, [h])` APPENDS, so
# building with it already preserves order and a closing `List.reverse` INVERTS the list. MEASURED on this
# exact function: `nums("0~1~2")` answered `2,1,0` -- which rendered every binary op with its operands
# swapped and shifted every `srcs` index by one, i.e. a plausible-looking kernel that was wrong.
def nums_go(+xs: List<&2, String>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case h <> t: nums_go(t, List.append(&2, U32, acc, [u32(h)]))

def nums(s: String) -> List<&2, U32>:
  match s:
    case "-": Nil{}
    case _: nums_go(ysplit(s), Nil{})

# ---------------------------------------------------------------- the arg, tagged by `kind`
# THE TAG CARRIES WHAT WOULD OTHERWISE NEED SLICING: `range_GLOBAL` is an axis AND an arg kind, and
# `wmma_f32` is an input dtype AND an arg kind, so the payload is always the plain list of numbers.
def arg_of(kind: String, +p: String) -> C.KUArg:
  match kind:
    case "const_int": C.KAConst{O.CInt{H.i64_of_hi_lo(u32(field(p, 0n)), u32(field(p, 1n)))}}
    case "const_float": C.KAConst{O.CFloat{F.F32.from_bits(u32(p))}}
    case "const_bool": C.KAConst{O.CBool{truth(p)}}
    case "param": C.KAParam{u32(field(p, 0n)), maybe_name(field(p, 1n)), flag(field(p, 2n)),
                            u32(field(p, 3n))}
    case "range_WEAK": C.KARange{O.AXIS_WEAK{}, nums(p)}
    case "range_GLOBAL": C.KARange{O.AXIS_GLOBAL{}, nums(p)}
    case "range_LOCAL": C.KARange{O.AXIS_LOCAL{}, nums(p)}
    case "range_DEVICE": C.KARange{O.AXIS_DEVICE{}, nums(p)}
    case "range_UPCAST": C.KARange{O.AXIS_UPCAST{}, nums(p)}
    case "range_WARP": C.KARange{O.AXIS_WARP{}, nums(p)}
    case "range_LOOP": C.KARange{O.AXIS_LOOP{}, nums(p)}
    case "range_PLACEHOLDER": C.KARange{O.AXIS_PLACEHOLDER{}, nums(p)}
    case "index": C.KAIndex{u32(p), False{}}
    case "sink": C.KASink{p}
    case "special": C.KASpecial{field(p, 0n), u32(field(p, 1n)), field(p, 2n)}
    case "wmma_f32": C.KAWmma{nums(p), S.single()}
    case "wmma_f16": C.KAWmma{nums(p), S.half()}
    case "wmma_bf16": C.KAWmma{nums(p), S.bfloat16()}
    case _: C.KANone{}

# ---------------------------------------------------------------- one uop line -> one KU
def ku_ws(+ws: List<&2, String>) -> C.KU:
  C.KU{op_of(fld(ws, 0n)), dt_of(fld(ws, 1n)), addr_of(fld(ws, 2n)), u32(fld(ws, 4n)),
       nums(fld(ws, 3n)), arg_of(fld(ws, 5n), fld(ws, 6n)), nums(fld(ws, 7n))}

def ku_of(l: String) -> C.KU: ku_ws(String.split(l, ' '))

# **THE WALK IS TAIL-RECURSIVE, AND THAT IS WHAT KEEPS ITS DEPTH AT ONE.** MEASURED in the runtime's own
# JS (`langs/js/core.js`): a tail-recursive def compiles to a `for(;;)` loop (`$List$reverse$go$`), while a
# non-tail one builds a frame per element (`$List$append$`). So the accumulator is PREPENDED
# (`List.append([h], acc)`, which recurses over the ONE-element list) and the recursive call is the last
# thing in the arm. MEASURED on this parser: with one frame per uop, 900 lines decoded and 1500 did not,
# while the LITERAL path rendered 1500 KUs fine -- the ceiling was this walk, not the renderer.
def ku_all(+xs: List<&2, String>, +acc: List<&2, C.KU>) -> List<&2, C.KU>:
  match xs:
    case Nil{}: acc
    case h <> t: ku_all(t, List.append(&2, C.KU, [ku_of(h)], acc))

# ---------------------------------------------------------------- the runtime entry point
# **`IO.args()`'s INDEX 0 IS THE PROGRAM, NOT THE FIRST ARGUMENT** -- MEASURED with two probes under
# `bun out.js WIRE`: index 0 answered `/private/tmp/p0.js` and index 1 answered `WIRE`. `runtime/ops_bend.bend`
# reads its lane from index 1 for the same reason, so this is the tree's convention and not a new one.
#
# **AND THE KERNEL ARRIVES IN CHUNKS, BECAUSE `String.split` IS RECURSIVE PER CHARACTER.** MEASURED against
# the runtime's own JS (`langs/js/core.js:357`, `$String$split$` recursing on `_t_0`): one call handles
# ~28 KB and then answers `RangeError` -> "the machine stack overflowed". A 1063-uop kernel is 31 KB, which
# is ORDINARY, so the caller splits the wire at LINE boundaries into pieces well under the cliff and passes
# them as successive arguments. Each chunk is split on its own, so no single call sees more than ~20 KB.
def skip_first(as: List<&1, String>) -> List<&1, String>:
  match as:
    case Nil{}: Nil{}
    case _ <> t: t

def walk(as: List<&1, String>, +acc: List<&2, C.KU>) -> IO(List<&2, C.KU>):
  match as:
    case Nil{}: IO.pure(List<&2, C.KU>, acc)
    case h <> t: walk(t, ku_all(String.split(h, nlch()), acc))

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    ks : List<&2, C.KU> <- walk(skip_first(as), Nil{})
    IO.print(C.render(C.dev_clang(), True{}, List.reverse(&2, C.KU, ks)))
