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
# THE WIRE IS 32.5 BYTES PER UOP AND SCANNING IT COSTS 0.15 us A CHARACTER (`PARITY.md` §48), so the dtype,
# the address space and the arg kind travel as ONE CHARACTER each. `kind` is the biggest saving -- the string
# `range_PLACEHOLDER` was 17 bytes for one fact. The op NAME stays textual: coding it needs a 75-arm table
# whose only guard is a coverage check, and the win here is already 44% of the wire.
def dt_of(nm: String) -> S.Dt:
  match nm:
    case "1": S.single()
    case "2": S.int32()
    case "3": S.uint32()
    case "4": S.int64()
    case "5": S.uint64()
    case "6": S.uint8()
    case "7": S.int8()
    case "8": S.uint16()
    case "9": S.int16()
    case "b": S.boolean()
    case "v": S.void()
    case "w": S.weakint()
    case "W": S.weakfloat()
    case "h": S.half()
    case "B": S.bfloat16()
    case "d": S.double()
    case _: S.void()

def addr_of(nm: String) -> S.Addr:
  match nm:
    case "g": S.AGlobal{}
    case "l": S.ALocal{}
    case "r": S.AReg{}
    case _: S.Aalu{}

# ENUM-PIN 56feedfd5ba184a9
# **THE ARMS ARE ORDERED BY MEASURED FREQUENCY, NOT BY THE ENUM.** `match` is a linear chain of string
# comparisons, so an arm costs (its position) compares -- at enum order that averages ~38 per uop over 75
# members. MEASURED over the 5 fixture kernels (782 uops): eight op names cover
# 86% of every uop rendered. The MAPPING is unchanged -- only the order of the comparisons -- so the C
# cannot move, and `ksweep` and the corpus are the proof.
#
# **AND THE ARM KEY IS A `U32`, NOT A STRING, AND THAT IS THE THIRD MEASURED CHANGE.** The key used to be
# the enum index as a DECIMAL STRING, and a `match` on a String in Bend COMPILES TO A CHARACTER TRIE --
# MEASURED on the 642-uop wire: `op_by_idx` compiled to **84** `slice`s and **84** `char_len` calls, and
# cost **2,560** `char_len` calls a render, THE LARGEST SINGLE TERM LEFT IN THE TURN. A `match` on a
# `U32` COMPILES TO INTEGER COMPARES (`PARITY.md` §133) and a runtime `U32` IS A PLAIN JS NUMBER, so the
# arm costs ONE integer compare and no slice at all. **⇒ SO THE OP INDEX RIDES IN THE WIRE's NUMBERS**
# (`wire.js`'s `wire_numbers`), where the JS side has it as a number for free, and the strings row is
# FOUR fields wide (dt, addr, kind, payload).
def op_by_idx(nm: U32) -> O.Op:
  match nm:
    case 30: O.OpsADD{}
    case 16: O.OpsINDEX{}
    case 57: O.OpsCONST{}
    case 21: O.OpsCAST{}
    case 31: O.OpsMUL{}
    case 18: O.OpsLOAD{}
    case 37: O.OpsCMPLT{}
    case 19: O.OpsSTORE{}
    case 13: O.OpsAFTER{}
    case 5: O.OpsPARAM{}
    case 49: O.OpsWHERE{}
    case 52: O.OpsRANGE{}
    case 54: O.OpsEND{}
    case 17: O.OpsSHRINK{}
    case 42: O.OpsAND{}
    case 32: O.OpsSHL{}
    case 12: O.OpsSINK{}
    case 14: O.OpsSTACK{}
    case 1: O.OpsBUFFER{}
    case 0: O.OpsSPECIAL{}
    case 2: O.OpsALLOC{}
    case 3: O.OpsNOOP{}
    case 4: O.OpsREWRITE_ERROR{}
    case 7: O.OpsCALL{}
    case 8: O.OpsPROGRAM{}
    case 9: O.OpsLINEAR{}
    case 10: O.OpsSOURCE{}
    case 11: O.OpsBINARY{}
    case 15: O.OpsGETADDR{}
    case 20: O.OpsWMMA{}
    case 22: O.OpsBITCAST{}
    case 23: O.OpsEXP2{}
    case 24: O.OpsLOG2{}
    case 25: O.OpsSIN{}
    case 26: O.OpsSQRT{}
    case 27: O.OpsRECIP{}
    case 28: O.OpsNEG{}
    case 29: O.OpsTRUNC{}
    case 33: O.OpsSHR{}
    case 34: O.OpsTRUNCDIV{}
    case 35: O.OpsMAX{}
    case 36: O.OpsTRUNCMOD{}
    case 38: O.OpsCMPNE{}
    case 39: O.OpsCMPEQ{}
    case 40: O.OpsXOR{}
    case 41: O.OpsOR{}
    case 43: O.OpsTHREEFRY{}
    case 44: O.OpsSUB{}
    case 45: O.OpsFDIV{}
    case 46: O.OpsPOW{}
    case 47: O.OpsDIV{}
    case 48: O.OpsMOD{}
    case 50: O.OpsMULACC{}
    case 51: O.OpsBARRIER{}
    case 53: O.OpsIF{}
    case 55: O.OpsENDIF{}
    case 56: O.OpsBACKEDGE{}
    case 58: O.OpsCUSTOM{}
    case 59: O.OpsCUSTOMI{}
    case 60: O.OpsINS{}
    case 61: O.OpsCONTIGUOUS_BACKWARD{}
    case 62: O.OpsDETACH{}
    case 63: O.OpsSTAGE{}
    case 64: O.OpsCOPY{}
    case 65: O.OpsMSELECT{}
    case 66: O.OpsMSTACK{}
    case 67: O.OpsCUSTOM_FUNCTION{}
    case 68: O.OpsRESHAPE{}
    case 69: O.OpsPERMUTE{}
    case 70: O.OpsEXPAND{}
    case 71: O.OpsPAD{}
    case 72: O.OpsUNSHARD{}
    case 73: O.OpsREDUCE{}
    case 74: O.OpsALLREDUCE{}
    case 75: O.OpsPYLITERAL{}
    case 6: O.OpsREFPARAM{}
    case _: O.OpsCONST{}

def op_of(+nm: U32) -> O.Op: op_by_idx(nm)

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
    case "i": C.KAConst{O.CInt{H.i64_of_hi_lo(u32(field(p, 0n)), u32(field(p, 1n)))}}
    case "f": C.KAConst{O.CFloat{F.F32.from_bits(u32(p))}}
    case "t": C.KAConst{O.CBool{truth(p)}}
    case "p": C.KAParam{u32(field(p, 0n)), maybe_name(field(p, 1n)), flag(field(p, 2n)),
                            u32(field(p, 3n))}
    case "RW": C.KARange{O.AXIS_WEAK{}, nums(p)}
    case "RG": C.KARange{O.AXIS_GLOBAL{}, nums(p)}
    case "RL": C.KARange{O.AXIS_LOCAL{}, nums(p)}
    case "RD": C.KARange{O.AXIS_DEVICE{}, nums(p)}
    case "RU": C.KARange{O.AXIS_UPCAST{}, nums(p)}
    case "RR": C.KARange{O.AXIS_WARP{}, nums(p)}
    case "RO": C.KARange{O.AXIS_LOOP{}, nums(p)}
    case "RP": C.KARange{O.AXIS_PLACEHOLDER{}, nums(p)}
    case "x": C.KAIndex{u32(p), False{}}
    case "s": C.KASink{p}
    case "q": C.KASpecial{field(p, 0n), u32(field(p, 1n)), field(p, 2n)}
    case "M1": C.KAWmma{nums(p), S.single()}
    case "M2": C.KAWmma{nums(p), S.half()}
    case "M3": C.KAWmma{nums(p), S.bfloat16()}
    case _: C.KANone{}

# ---------------------------------------------------------------- one uop line -> one KU
# **THE NINE FIELDS ARE BOUND BY NINE NAMES, NOT READ BY INDEX.** `fld` is `List.get`, so it walks `i+1`
# conses: nine reads of a nine-element list cost 45 steps, and MEASURED (`PARITY.md` §121) the decoder makes
# 5,870 `fld` calls a render -- the single largest group in the decode, and every one of them walks.
# `ku_ws.r` takes the list newest-first (which is how `ku_all` collects it) and binds the nine fields in
# ONE walk of nine conses. §110.2 measured the same shape in `cstyle.bend` at 0.9796 and reverted it; the
# decoder is a different call site with 4x the count, so the shape is re-measured here.

# **THE TOKEN PATH's OP IS A STRING AND THE EFFECT PATH's IS A NUMBER, AND ONE READER SERVES BOTH.**
# `ku_ws` reads the wire's NINE tokens, so its op is the enum index as a DECIMAL STRING; the effect path
# reads a `U32` straight from the wire's numbers. `op_of` takes the NUMBER, so the token path parses the
# string here -- and `U32.read` is the prelude's character-at-a-time fold, which is why the effect path
# exists at all (`PARITY.md` §131/§132).
def op_of_str(+nm: String) -> U32: Maybe.default(&2, U32, U32.read(nm), 0)

def ku_ws.of(a: String, b: String, c: String, d: String, e: String, f: String,
             g: String, h: String, i: String) -> C.KU:
  C.KU{op_of(op_of_str(a)), dt_of(b), addr_of(c), u32(e), nums(d), arg_of(f, g), nums(h), u32(i)}

def ku_ws.bad() -> C.KU:
  ku_ws.of("", "", "", "", "", "", "", "", "")

def ku_ws.r(+ws: List<&2, String>) -> C.KU:
  match ws:
    case a <> t1:
      match t1:
        case b <> t2:
          match t2:
            case c <> t3:
              match t3:
                case d <> t4:
                  match t4:
                    case e <> t5:
                      match t5:
                        case f <> t6:
                          match t6:
                            case g <> t7:
                              match t7:
                                case h <> t8:
                                  match t8:
                                    case i <> _: ku_ws.of(a, b, c, d, e, f, g, h, i)
                                    case Nil{}: ku_ws.bad()
                                case Nil{}: ku_ws.bad()
                            case Nil{}: ku_ws.bad()
                        case Nil{}: ku_ws.bad()
                    case Nil{}: ku_ws.bad()
                case Nil{}: ku_ws.bad()
            case Nil{}: ku_ws.bad()
        case Nil{}: ku_ws.bad()
    case Nil{}: ku_ws.bad()

def ku_ws(+ws: List<&2, String>) -> C.KU:
  ku_ws.r(ws)




def ku_of(l: String) -> C.KU: ku_ws(String.split(l, ' '))

# **THE WALK IS TAIL-RECURSIVE, AND THAT IS WHAT KEEPS ITS DEPTH AT ONE.** MEASURED in the runtime's own
# JS (`langs/js/core.js`): a tail-recursive def compiles to a `for(;;)` loop (`$List$reverse$go$`), while a
# non-tail one builds a frame per element (`$List$append$`). So the accumulator is PREPENDED
# (`List.append([h], acc)`, which recurses over the ONE-element list) and the recursive call is the last
# thing in the arm. MEASURED on this parser: with one frame per uop, 900 lines decoded and 1500 did not,
# while the LITERAL path rendered 1500 KUs fine -- the ceiling was this walk, not the renderer.
# **THE WIRE IS ONE FLAT SPACE-SEPARATED TOKEN STREAM AND NINE TOKENS ARE ONE UOP, BECAUSE A SECOND
# SPLIT PASS COSTS A SECOND SCAN OF EVERY BYTE.** The wire used to be lines of fields, so decoding split it
# once on '\n' (8 700 characters) and again per line on ' ' (8 526) -- MEASURED in `PARITY.md` §78, that first
# pass alone is **0.89 ms of a 2.17 ms decode**. Nine tokens per row is the same shape, one separator, one
# pass. `take9` peels them with a counter and a CONS (O(1) each) rather than `fld`'s `List.get` per field.
# **NINE TOKENS ARE ONE UOP AND THE STATE LIVES IN THIS ONE DEF, BECAUSE BEND REFUSES MUTUAL RECURSION.**
# `skip` is how many fields the row still needs (1 = the token arriving now completes it); `fields` holds
# the ones already collected, REVERSED, so each costs a CONS. `take9`/`drop` would need a second recursive
# def calling back into this one, which the compiler refuses ("expected a filled definition").
def ku_all(+xs: List<&2, String>, skip: Nat, +fields: List<&2, String>, +acc: List<&2, C.KU>) -> List<&2, C.KU>:
  match xs:
    case Nil{}:
      match fields:
        case Nil{}: acc
        case _ <> _: List.append(&2, C.KU, [ku_ws(List.reverse(&2, String, fields))], acc)
    case h <> t:
      match skip:
        case 1n: ku_all(t, 0n, Nil{}, List.append(&2, C.KU,
          [ku_ws(List.reverse(&2, String, List.append(&2, String, [h], fields)))], acc))
        case 0n: ku_all(t, 8n, List.append(&2, String, [h], Nil{}), acc)
        case 2n+k: ku_all(t, Nat.add(k, 1n), List.append(&2, String, [h], fields), acc)

# **THE SPLIT IS AN EFFECT, BECAUSE THE PRELUDE'S SPLIT IS ONE RECURSION PER CHARACTER.** MEASURED
# (`PARITY.md` §125): on a 15,346-character wire the prelude's split is **5.16 ms of a 5.58 ms daemon turn
# -- 92.6%** -- and everything else in the turn is 0.42 ms. The prelude does two `slice`s and a TOKEN
# CONCATENATION per character (`String.split.push` is `_c_0 + _h_0`), and the interpreter charges ~18 ns a
# call, so the port pays ~30x what the SAME ALGORITHM costs in JS (0.72 ms there, 5.16 ms here).
#
# `Wire.split` calls JS's native `String.prototype.split` -- ONE call -- and the JS half builds the list
# in JS. MEASURED (`PARITY.md` §126): 0.136 ms a turn.
#
# **AND THE PURE PART STAYS PURE:** `kus_bytes` is the decoder over a token list and never touches the
# effect, so the LITERAL path (`gen_kus.py`'s generated `kus()`, which builds the KUs in bend) is unaffected.
@unsafe
def Wire.split(s: String) -> IO(List<&2, String>):
  import "./wire.c"
  import "./wire.js"

# **THE WIRE'S TWO LISTS, IN TWO EFFECTS.** BEND'S LIST IS MONOMORPHIC, SO A ROW CANNOT HOLD BOTH STRINGS
# AND NUMBERS, AND A ROW CANNOT BE A PAIR OF LISTS OF DIFFERENT KINDS -- SO THE EFFECT GIVES ONE LIST PER
# KIND AND THE PORT WALKS THEM IN STEP.
#
# `Wire.strings` RETURNS, PER UOP, THE FIVE STRINGS (op, dt, addr, kind, payload).
# `Wire.numbers` RETURNS, PER UOP, THE NUMBERS (numel, cc, shapeCount, srcsCount, shape..., srcs...).
#
# WHY THE NUMBERS AT ALL: the port's `U32.read` is the PRELUDE's character-at-a-time fold, and at runtime a
# string is a JS string, so the compiler emits `slice(0, char_len(s))` AND `slice(char_len(s))` PER CHARACTER.
# MEASURED (`PARITY.md` §131): the wire's 2,814 numbers cost 21,294 `char_len` calls and ~42,000 string
# allocations a render, where the SAME ALGORITHM IN JS IS 0.015-0.025 ms -- forty times faster.
@unsafe
def Wire.strings(s: String) -> IO(List<&2, List<&2, String>>):
  import "./wire.c"
  import "./wire.js"

@unsafe
def Wire.numbers(s: String) -> IO(List<&2, List<&2, U32>>):
  import "./wire.c"
  import "./wire.js"

def kus_bytes(xs: List<&2, String>) -> List<&2, C.KU>:
  List.reverse(&2, C.KU, ku_all(xs, 0n, Nil{}, Nil{}))

def take(n: U32, xs: List<&2, U32>) -> List<&2, U32>:
  List.take(&2, U32, xs, U32.to_nat(n))

def skip(n: U32, xs: List<&2, U32>) -> List<&2, U32>:
  List.drop(&2, U32, xs, U32.to_nat(n))

# **THE ROW IS FOUR STRINGS AND THE OP INDEX IS A NUMBER.** The effect's strings row is (dt, addr, kind,
# payload) -- the op index LEFT the strings because a `match` on a String is a character trie and a
# `match` on a `U32` is an integer compare (see `op_by_idx`). So the numbers row is
# [opIndex, numel, cc, shapeCount, srcsCount, shape..., srcs...] and `ku_row.n` binds the op index FIRST.
def ku_row.of(op: U32, a: String, b: String, c: String, d: String, numel: U32, cc: U32,
              +sc: U32, +gc: U32, +rest: List<&2, U32>) -> C.KU:
  +sh = take(sc, rest)
  +sr = take(gc, skip(sc, rest))
  C.KU{op_of(op), dt_of(a), addr_of(b), numel, sh, arg_of(c, d), sr, cc}

def ku_row.n(+nums: List<&2, U32>, a: String, b: String, c: String, d: String) -> C.KU:
  match nums:
    case op <> t1:
      match t1:
        case n0 <> t2:
          match t2:
            case n1 <> t3:
              match t3:
                case n2 <> t4:
                  match t4:
                    case n3 <> t5: ku_row.of(op, a, b, c, d, n0, n1, n2, n3, t5)
                    case Nil{}: ku_ws.bad()
                case Nil{}: ku_ws.bad()
            case Nil{}: ku_ws.bad()
        case Nil{}: ku_ws.bad()
    case Nil{}: ku_ws.bad()

# **THE ROW IS EXACTLY FOUR STRINGS, AND THAT IS MEASURED.** The effect's row is (dt, addr, kind,
# payload) and NOTHING ELSE, so the fourth's tail is Nil -- and the fifth arm (`case _ <> _`) is the
# MALFORMED case, not the good one. (`ku_ws.r`, the token path's reader, binds NINE fields and wants a
# tenth, because the token path's row is nine tokens plus the next row's first token; the two readers
# are NOT the same shape and must not be copied from one another.)
def ku_row.s(+strs: List<&2, String>, +nums: List<&2, U32>) -> C.KU:
  match strs:
    case a <> s1:
      match s1:
        case b <> s2:
          match s2:
            case c <> s3:
              match s3:
                case d <> s4:
                  match s4:
                    case Nil{}: ku_row.n(nums, a, b, c, d)
                    case _ <> _: ku_ws.bad()
                case Nil{}: ku_ws.bad()
            case Nil{}: ku_ws.bad()
        case Nil{}: ku_ws.bad()
    case Nil{}: ku_ws.bad()

def ku_row(+s: List<&2, String>, +n: List<&2, U32>) -> C.KU:
  ku_row.s(s, n)

def kus_rows.go(+ss: List<&2, List<&2, String>>, +ns: List<&2, List<&2, U32>>, +acc: List<&2, C.KU>) -> List<&2, C.KU>:
  match ss:
    case Nil{}: acc
    case s <> st:
      match ns:
        case Nil{}: acc
        case n <> nt: kus_rows.go(st, nt, List.append(&2, C.KU, [ku_row(s, n)], acc))

# **THE ROWS ARE IN WIRE ORDER, AND THAT IS MEASURED.** The JS walks the tokens from the LAST row to the
# first and PREPENDS each one, so the FIRST row ends up at the head -- the same order the token path
# produces (`ku_all` reads the tokens in reverse and `ku_ws` reverses each row back). So the walk here
# PREPENDS each KU (which is O(1): `List.append(xs, ys)` COPIES `xs`, so `List.append([x], acc)` is the
# cheap form and `List.append(acc, [x])` is the O(n) one -- MEASURED: the O(n) form cost +91,096
# `List.append` calls a render and was a REGRESSION) and the list is REVERSED ONCE at the end, which is
# O(n).
def kus_rows(+ss: List<&2, List<&2, String>>, +ns: List<&2, List<&2, U32>>) -> List<&2, C.KU>:
  List.reverse(&2, C.KU, kus_rows.go(ss, ns, Nil{}))

# **THE TWO EFFECTS, BOUND IN STEP.** `Wire.strings` GIVES THE FIVE CODES AND THE PAYLOAD PER UOP AND
# `Wire.numbers` GIVES THE NUMBERS PER UOP, AND THE PORT WALKS THE TWO LISTS TOGETHER.
def kus_rows.io(+ss: List<&2, List<&2, String>>, +ns: List<&2, List<&2, U32>>) -> IO(List<&2, C.KU>):
  IO.pure(List<&2, C.KU>, kus_rows(ss, ns))

def kus.io(+text: String) -> IO(List<&2, C.KU>):
  IO.bind(List<&2, List<&2, String>>, List<&2, C.KU>, Wire.strings(text), ss =>
    IO.bind(List<&2, List<&2, U32>>, List<&2, C.KU>, Wire.numbers(text), ns =>
      kus_rows.io(ss, ns)))

def kus(+text: String) -> IO(List<&2, C.KU>):
  kus.io(text)

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

def walk.go(as: List<&1, String>, +acc: List<&2, C.KU>) -> IO(List<&2, C.KU>):
  match as:
    case Nil{}: IO.pure(List<&2, C.KU>, acc)
    case h <> t:
      IO.bind(List<&2, C.KU>, List<&2, C.KU>, kus(h), ks =>
        walk.go(t, List.append(&2, C.KU, acc, ks)))

def walk(as: List<&1, String>, +acc: List<&2, C.KU>) -> IO(List<&2, C.KU>):
  walk.go(as, acc)

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    ks : List<&2, C.KU> <- walk(skip_first(as), Nil{})
    IO.print(C.render(C.dev_clang(), True{}, List.reverse(&2, C.KU, ks)))
