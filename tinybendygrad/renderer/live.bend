# live.bend -- render a kernel from text, so the renderer is compiled once and fed kernels at runtime.
#
# WHY THIS EXISTS. `cstyle.bend`'s `render` takes a `List<KU>` -- a Bend VALUE -- so `.agents/slop/cpuseam/
# portc.py` used to compile the kernel INTO the driver as a literal, one `bin/bend` build per kernel. What
# that build pays for is the TYPECHECK OF THE CLOSURE, not the kernel: MEASURED 2026-11-03, a driver holding
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

# THE PAYLOAD'S FIELDS, AND THE SPLIT IS ONCE PER ROW. MEASURED (`PARITY.md` §138):

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
# the wire is 32.5 bytes per uop and scanning it costs 0.15 us a character (`PARITY.md` §48), so the dtype,
# the address space and the arg kind travel as ONE CHARACTER each. `kind` is the biggest saving -- the string
# `range_PLACEHOLDER` was 17 bytes for one fact. The op NAME stays textual: coding it needs a 75-arm table
# whose only guard is a coverage check, and the win here is already 44% of the wire.
#
# - and the three codes are matched as numbers, and that is a measured change. a `match` on a String
# in Bend COMPILES TO A CHARACTER TRIE: the generated code slices the first character
# (`slice(0, char_len(s))`) and slices the rest (`slice(char_len(s))`) to test the length -- two slices
# and two `char_len` per call -- and these three cost 2,873 `char_len` calls a render (measured:
# `dt_of` 1,284, `arg_of` 898, `addr_of` 691). A `match` on a `U32` COMPILES TO INTEGER COMPARES (one
# per arm, no slice, no `char_len`), and `charCodeAt` is free in js -- so the codes ride in the wire's
# numbers (`wire.js`'s `wire_numbers`) and the port matches them as numbers.
#
# - and the arm keys are the char codes, with the literal they replace beside them. a computed arm
# key IS REFUSED ("expected : a pattern"), so the table cannot derive its own keys, and this is the
# second source of truth in the tree -- - and it is checked by a probe, not by reading: the probe
# calls the COMPILED `dt_of` / `addr_of` / `arg_of` over EVERY code and compares against the port's own
# string table. MEASURED: 38 of 38 (`PARITY.md` §134).
def dt_of(nm: U32) -> S.Dt:
  match nm:
    case 49: S.single()      # "1"
    case 50: S.int32()       # "2"
    case 51: S.uint32()      # "3"
    case 52: S.int64()       # "4"
    case 53: S.uint64()      # "5"
    case 54: S.uint8()       # "6"
    case 55: S.int8()        # "7"
    case 56: S.uint16()      # "8"
    case 57: S.int16()       # "9"
    case 98: S.boolean()     # "b"
    case 118: S.void()       # "v"
    case 119: S.weakint()    # "w"
    case 87: S.weakfloat()   # "W"
    case 104: S.half()       # "h"
    case 66: S.bfloat16()    # "B"
    case 100: S.double()     # "d"
    case _: S.void()

def addr_of(nm: U32) -> S.Addr:
  match nm:
    case 103: S.AGlobal{}    # "g"
    case 108: S.ALocal{}     # "l"
    case 114: S.AReg{}       # "r"
    case _: S.Aalu{}

# ENUM-PIN 56feedfd5ba184a9
# the arms are ordered by measured frequency, not by the enum. `match` is a linear chain of string
# comparisons, so an arm costs (its position) compares -- at enum order that averages ~38 per uop over 75
# members. MEASURED over the 5 fixture kernels (782 uops): eight op names cover
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
# no `List.reverse` here, and that is measured, not style. `List.append(&2, A, acc, [h])` appends, so
# building with it already preserves order and a closing `List.reverse` INVERTS the list. MEASURED on this
# exact function: `nums("0~1~2")` answered `2,1,0` -- which rendered every binary op with its operands
def nums_go(+xs: List<&2, String>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case h <> t: nums_go(t, List.append(&2, U32, acc, [u32(h)]))

def nums(s: String) -> List<&2, U32>:
  match s:
    case "-": Nil{}
    case _: nums_go(ysplit(s), Nil{})

# ---------------------------------------------------------------- the arg, tagged by `kind`
# the tag carries what would otherwise need slicing: `range_GLOBAL` is an axis and an arg kind, and
# `wmma_f32` is an input dtype AND an arg kind, so the payload is always the plain list of numbers.
#
# - and the kind is two numbers, and the match is on the first. Eleven of the nineteen kinds are
# TWO CHARACTERS ("RW", "M1") and eight are one, so the first character's code separates the two
# groups and the second picks inside the two-character group. MEASURED: the port's `match` on the
def arg_of.range(kind1: U32, +p: String) -> C.KUArg:
  match kind1:
    case 87: C.KARange{O.AXIS_WEAK{}, nums(p)}         # "RW"
    case 71: C.KARange{O.AXIS_GLOBAL{}, nums(p)}       # "RG"
    case 76: C.KARange{O.AXIS_LOCAL{}, nums(p)}        # "RL"
    case 68: C.KARange{O.AXIS_DEVICE{}, nums(p)}       # "RD"
    case 85: C.KARange{O.AXIS_UPCAST{}, nums(p)}       # "RU"
    case 82: C.KARange{O.AXIS_WARP{}, nums(p)}         # "RR"
    case 79: C.KARange{O.AXIS_LOOP{}, nums(p)}         # "RO"
    case 80: C.KARange{O.AXIS_PLACEHOLDER{}, nums(p)}  # "RP"
    case _: C.KANone{}

# the three wmma's: "M1" "M2" "M3" -- and the second character is the input dtype.
def arg_of.wmma(kind1: U32, +p: String) -> C.KUArg:
  match kind1:
    case 49: C.KAWmma{nums(p), S.single()}    # "M1"
    case 50: C.KAWmma{nums(p), S.half()}      # "M2"
    case 51: C.KAWmma{nums(p), S.bfloat16()}  # "M3"
    case _: C.KANone{}

# THE `i` ARM'S TWO FIELDS, FROM ONE SPLIT. THE `i` PAYLOAD IS ALWAYS TWO FIELDS
# (MEASURED: 97 OF 97).
def const_int.of(+fs: List<&2, String>) -> C.KUArg:
  C.KAConst{O.CInt{H.i64_of_hi_lo(u32(fld(fs, 0n)), u32(fld(fs, 1n)))}}

# THE `p` ARM'S FOUR FIELDS, FROM ONE SPLIT. THE `p` PAYLOAD IS ALWAYS FOUR FIELDS
# (MEASURED: 16 OF 16).
def param_of(+fs: List<&2, String>) -> C.KUArg:
  C.KAParam{u32(fld(fs, 0n)), maybe_name(fld(fs, 1n)), flag(fld(fs, 2n)), u32(fld(fs, 3n))}

# THE `q` ARM'S THREE FIELDS, FROM ONE SPLIT.
def special_of(+fs: List<&2, String>) -> C.KUArg:
  C.KASpecial{fld(fs, 0n), u32(fld(fs, 1n)), fld(fs, 2n)}

def arg_of(kind0: U32, kind1: U32, +p: String) -> C.KUArg:
  match kind0:
    case 105: const_int.of(ysplit(p))                                                  # "i"
    case 102: C.KAConst{O.CFloat{F.F32.from_bits(u32(p))}}                             # "f"
    case 116: C.KAConst{O.CBool{truth(p)}}                                            # "t"
    case 112: param_of(ysplit(p))                                                      # "p"
    case 120: C.KAIndex{u32(p), False{}}                                              # "x"
    case 115: C.KASink{p}                                                              # "s"
    case 113: special_of(ysplit(p))                                                   # "q"
    case 82: arg_of.range(kind1, p)                                                    # "R*"
    case 77: arg_of.wmma(kind1, p)                                                     # "M*"
    case _: C.KANone{}

# ---------------------------------------------------------------- one uop line -> one KU
# the nine fields are bound by nine names, not read by INDEX. `fld` is `List.get`, so it walks `i+1`
# conses: nine reads of a nine-element list cost 45 steps, and MEASURED (`PARITY.md` §121) the decoder makes
def op_of_str(+nm: String) -> U32: Maybe.default(&2, U32, U32.read(nm), 0)

# - and the token path's three codes are strings and the effect path's are numbers, for the same
def code_of.get(nm: String) -> Maybe<&2, Char>: String.get(nm, 0n)
def code_of.at(nm: String, n: Nat) -> Maybe<&2, Char>: String.get(nm, n)

def code_of.of(c: Maybe<&2, Char>) -> U32:
  match c:
    case Some{ch}: Char.to_u32(ch)
    case _: 0

def code_of(nm: String) -> U32: code_of.of(code_of.get(nm))

def code1_of(nm: String) -> U32: code_of.of(code_of.at(nm, 1n))

def ku_ws.of(a: String, b: String, c: String, d: String, e: String, f: String,
             g: String, h: String, i: String) -> C.KU:
  # - the kind is read twice, so it is bound once. a consumed parameter can only be read once
  # ("consumed more than once"), and the kind's FIRST and SECOND characters are two reads -- so the
  # kind is BOUND to a local first, and the local is read twice.
  +kind = f
  +k0 = code_of(kind)
  +k1 = code1_of(kind)
  C.KU{op_of(op_of_str(a)), dt_of(code_of(b)), addr_of(code_of(c)), u32(e), nums(d),
       arg_of(k0, k1, g), nums(h), u32(i)}

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

# the walk is tail-recursive, and that is what keeps its depth at one. measured in the runtime's own
# JS (`langs/js/core.js`): a tail-recursive def compiles to a `for(;;)` loop (`$List$reverse$go$`), while a
# non-tail one builds a frame per element (`$List$append$`). So the accumulator is PREPENDED
# (`List.append([h], acc)`, which recurses over the ONE-element list) and the recursive call is the last
# thing in the arm. MEASURED on this parser: with one frame per uop, 900 lines decoded and 1500 did not,
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

# the split is an effect, because the prelude's split is one recursion per character. measured
# (`PARITY.md` §125): on a 15,346-character wire the prelude's split is 5.16 ms of a 5.58 ms daemon turn
# -- 92.6% -- and everything else in the turn is 0.42 ms. The prelude does two `slice`s and a TOKEN
# CONCATENATION per character (`String.split.push` is `_c_0 + _h_0`), and the interpreter charges ~18 ns a
# call, so the port pays ~30x what the SAME ALGORITHM costs in JS (0.72 ms there, 5.16 ms here).
#
# `Wire.split` calls JS's native `String.prototype.split` -- ONE call -- and the JS half builds the list
# in JS. MEASURED (`PARITY.md` §126): 0.136 ms a turn.
@unsafe
def Wire.split(s: String) -> IO(List<&2, String>):
  import "./wire.c"
  import "./wire.js"

# THE WIRE's TWO LISTS, IN ONE EFFECT.
#
# BEND's list is monomorphic, so a row cannot hold both strings and numbers, and a row cannot be a
# pair of lists of different kinds -- so the port needs one list per kind and walks them in step.
# `Wire.both` RETURNS BOTH: THE STRINGS ROW (THE PAYLOAD, PER UOP) AND THE NUMBERS ROW
# ([opIndex, dtCode, addrCode, kindC0, kindC1, numel, cc, shapeCount, srcsCount, shape..., srcs...]).
#
# WHY THE NUMBERS AT ALL: the port's `U32.read` is the PRELUDE's character-at-a-time fold, and at runtime a
# string is a JS string, so the compiler emits `slice(0, char_len(s))` AND `slice(char_len(s))` PER CHARACTER.
# MEASURED (`PARITY.md` §131): the wire's 2,814 numbers cost 21,294 `char_len` calls and ~42,000 string
type Wire.Both is Data:
  Wire.Both{ss: List<&2, List<&2, String>>, ns: List<&2, List<&2, U32>>}

@unsafe
def Wire.both(s: String) -> IO(Wire.Both):
  import "./wire.c"
  import "./wire.js"

def kus_bytes(xs: List<&2, String>) -> List<&2, C.KU>:
  List.reverse(&2, C.KU, ku_all(xs, 0n, Nil{}, Nil{}))

def take(n: U32, xs: List<&2, U32>) -> List<&2, U32>:
  List.take(&2, U32, xs, U32.to_nat(n))

def skip(n: U32, xs: List<&2, U32>) -> List<&2, U32>:
  List.drop(&2, U32, xs, U32.to_nat(n))

# the row is one string and everything ELSE is a number. The effect's strings row is just the
def ku_row.of(op: U32, dt: U32, addr: U32, k0: U32, k1: U32, numel: U32, cc: U32,
              +sc: U32, +gc: U32, +rest: List<&2, U32>, +payload: String) -> C.KU:
  +sh = take(sc, rest)
  +sr = take(gc, skip(sc, rest))
  C.KU{op_of(op), dt_of(dt), addr_of(addr), numel, sh, arg_of(k0, k1, payload), sr, cc}

def ku_row.n(+nums: List<&2, U32>, +payload: String) -> C.KU:
  match nums:
    case op <> t1:
      match t1:
        case dt <> t2:
          match t2:
            case addr <> t3:
              match t3:
                case k0 <> t4:
                  match t4:
                    case k1 <> t5:
                      match t5:
                        case numel <> t6:
                          match t6:
                            case cc <> t7:
                              match t7:
                                case sc <> t8:
                                  match t8:
                                    case gc <> t9: ku_row.of(op, dt, addr, k0, k1, numel, cc, sc, gc, t9, payload)
                                    case Nil{}: ku_ws.bad()
                                case Nil{}: ku_ws.bad()
                            case Nil{}: ku_ws.bad()
                          case Nil{}: ku_ws.bad()
                        case Nil{}: ku_ws.bad()
                      case Nil{}: ku_ws.bad()
                    case Nil{}: ku_ws.bad()
                  case Nil{}: ku_ws.bad()
                case Nil{}: ku_ws.bad()
              case Nil{}: ku_ws.bad()
            case Nil{}: ku_ws.bad()
          case Nil{}: ku_ws.bad()
        case Nil{}: ku_ws.bad()
      case Nil{}: ku_ws.bad()
    case Nil{}: ku_ws.bad()

# the row is exactly one string, and that is measured. The effect's row is the payload and nothing
def ku_row.s(+strs: List<&2, String>, +nums: List<&2, U32>) -> C.KU:
  match strs:
    case payload <> s1:
      match s1:
        case Nil{}: ku_row.n(nums, payload)
        case _ <> _: ku_ws.bad()
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

# the rows are in wire order, and that is measured. The js walks the tokens from the last row to the
# first and PREPENDS each one, so the FIRST row ends up at the head -- the same order the token path
# produces (`ku_all` reads the tokens in reverse and `ku_ws` reverses each row back). So the walk here
# PREPENDS each KU (which is O(1): `List.append(xs, ys)` COPIES `xs`, so `List.append([x], acc)` is the
# cheap form and `List.append(acc, [x])` is the O(n) one -- MEASURED: the O(n) form cost +91,096
def kus_rows(+ss: List<&2, List<&2, String>>, +ns: List<&2, List<&2, U32>>) -> List<&2, C.KU>:
  List.reverse(&2, C.KU, kus_rows.go(ss, ns, Nil{}))

def kus_rows.io(+ss: List<&2, List<&2, String>>, +ns: List<&2, List<&2, U32>>) -> IO(List<&2, C.KU>):
  IO.pure(List<&2, C.KU>, kus_rows(ss, ns))

# the ONE effect, and the row walk. `Wire.both` gives the strings row and the numbers row from
# ONE split, and the port walks the two lists together.
#
# AND THE READER IS ITS OWN `def` WITH A BARE PARAMETER (`wire_rows`), BECAUSE A `match`
# CANNOT SCRUTINIZE A COMPUTED VALUE AND CANNOT SCRUTINIZE A BOUND BINDER INSIDE THE
# CONTINUATION (MEASURED: "`b` can't be matched in this position"), AND THAT IS THE TREE's
def wire_rows(b: Wire.Both) -> List<&2, C.KU>:
  match b:
    case Wire.Both{ss, ns}: kus_rows(ss, ns)

def kus.io(+text: String) -> IO(List<&2, C.KU>):
  IO.bind(Wire.Both, List<&2, C.KU>, Wire.both(text), b =>
    IO.pure(List<&2, C.KU>, wire_rows(b)))

def kus(+text: String) -> IO(List<&2, C.KU>):
  kus.io(text)

# ---------------------------------------------------------------- the runtime entry point
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
