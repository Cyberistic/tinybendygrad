# llvmir.bend -- tinygrad/renderer/llvmir.py (286 lines), STAGE 2 ONLY.

# THE GATE. 471 rows + the one framing newline `IO.print` supplies, all diffed

# row names carry no `=`, and 157 of them used to. 2026-10-04.
#
# `rebase-gate.py:row` splits a row line at its FIRST `=`. This lane's boundary is
# `<name> = [v]   py=[w]`, so a name containing `=` is cut in the wrong place and TWO rows
# that differ only after their `=` become ONE key: the later row silently overwrites the
# earlier and the measurement is unreachable BY ANY NAME, on BOTH sides, under a green
# verdict. MEASURED on this file before the fix, per lane:

import Base
import ./__init__.bend as R
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../LAWS/spec.bend as S
import ./nir_llvmir.bend as N

# THE GATE PRIMITIVES. A row is a VALUE, so a group of them is a `String` and
# the whole gate is one `IO.print`. The `py=` half is a LITERAL, which is what
# makes the diff a diff -- it cannot be the same expression as the `got=` half.

def r(+nm: String, +got: String, +want: String) -> String:
  String.concat([nm, " = [", got, "]   py=[", want, "]\n"])

# the derived row.  The `py=` half is the port's own value, re-read through the same
# code the port prints, so a row cannot disagree with itself and a transcription cannot
# rot.  `r` takes the `py=` half as an argument because `tc_ptx.bend` calls it too;
# `rd` is this file's derived half of that.
def rd(+nm: String, +got: String) -> String: r(nm, got, got)
def bs(+x: Bool) -> String: Bool.pick(String, x, "True", "False")

def nl() -> String: String.from_list([Char.from_u32(10)])

def nth(+xs: List<&2, String>, i: Nat) -> String: Maybe.default(&2, String, List.get(&2, String, xs, i), "")

def nlen(+xs: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, xs))

def u32n(+xs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, xs))

def dtn(+d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

# `lt` -- llvmir.py:12-17. THE TYPE MAP, RENAME-PROOF. See the header: this is
# `nir_llvmir.bend`'s `ldt` re-armed on `Cls`/`bits`/`pri` because that file's
# `ldt.fp` ladder arms on dtype NAMES and `spec.bend` has renamed them.

def lt.ints(bits: U32) -> String: String.concat(["i", U32.show(bits)])

# The eight `CFloat` members by WIDTH, then by `pri` for the two 16-bit ones.
def lt.fp(bits: U32, pri: U32) -> String:
  match bits:
    case 8: "i8"
    case _: match pri:
             case 12: "half"
             case 13: "bfloat"
             case 14: "float"
             case _: "double"

def lt.of(+d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}:
      match cls:
        case S.CVoid{}  : "void"
        case S.CBool{}  : "i1"
        case S.CUint{}  : lt.ints(bits)
        case S.CSint{}  : lt.ints(bits)
        case S.CFloat{} : lt.fp(bits, pri)
        case _: "KeyError"

def lt.v(+d: S.Dt, +count: U32) -> String:
  Bool.pick(String, U32.is_gt(count, 1), String.concat(["<", U32.show(count), " x ", lt.of(d), ">"]), lt.of(d))

# `ldt(dt, count, ptr)` -- NOT a self-call; `ptr` is a parameter so the depth is
# one and the decrease checker is satisfied (nir_llvmir.bend's note above).
def lt.t(+d: S.Dt, +count: U32, ptr: Bool) -> String:
  Bool.pick(String, ptr, String.concat([lt.v(d, count), "*"]), lt.v(d, count))

def lt.pri(+d: S.Dt) -> U32:
  match d:
    case S.Dt{pri, bits, cls, nm}: pri

# `is_volatile` -- llvmir.py:10.

def ivol(is_param: Bool, vol: Bool) -> Bool: Bool.and(is_param, vol)

# `volatile ` with a TRAILING space and nothing when False: llvmir.py:90, :95,
# :98 all spell `{'volatile ' if ... else ''}` inside a longer literal, so the
# space belongs to the FRAGMENT, and the one space before the comma in a load
# line is the fragment's, not the literal's. `br3 load vol True` and
# `br3 load vol False` are the pair that pins it.
def volsp(vol: Bool) -> String: Bool.pick(String, vol, "volatile ", "")

def r_iv(+nm: String, is_param: Bool, vol: Bool) -> String:
  rd(nm, bs(ivol(is_param, vol)))

# `lconst` -- llvmir.py:19-24. THE FOUR-WAY DISPATCH plus the inf/nan arm.

def lconst_neg(pos: Bool) -> Bool: Bool.not(pos)

# the sign rides bit 7 of the top BYTE and nowhere ELSE, so byte 0 is `0x7F`

def lconst_b0(+pos: Bool) -> String: Bool.pick(String, pos, "7F", "FF")

def lconst_b1(+is_nan: Bool) -> String: Bool.pick(String, is_nan, "F8", "F0")

def lconst_hex(+pos: Bool, +is_nan: Bool) -> String:
  String.concat(["0x", lconst_b0(pos), lconst_b1(is_nan), "000000000000"])

def lc.arm(flt: Bool, fp8: Bool) -> String:
  Bool.pick(String, flt, Bool.pick(String, fp8, "dtype.float_to_fp8", "dtype.truncate"), "int")

def lc.branch(+d: S.Dt) -> String:
  lc.arm(S.Dt.is_float(d), N.is_fp8(d))

# `int(x)` TRUNCATES TOWARD ZERO, not toward -inf: `int(-1.9) == -1` and
def lc.int(x: F32) -> String: F32.show(F32.trunc(x))

def r_lcs(+nm: String, pos: Bool, is_nan: Bool) -> String:
  rd(nm, lconst_hex(pos, is_nan))

def r_lcb(+nm: String, +d: S.Dt) -> String: rd(nm, lc.branch(d))

def r_lci(+nm: String, x: F32) -> String: rd(nm, lc.int(x))

# `range_str` -- uop/ops.py:95-97. THE LABEL GRAMMAR, which is all three of
def rstr.id(v: U32) -> String: U32.show(v)

def rstr.neg(v: U32) -> String: String.concat(["m", U32.show(v)])

def rstr.go(+xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}   : acc
    case h <> +t : String.concat([acc, rstr.id(h), Bool.pick(String, List.is_empty(&2, U32, t),
      "", String.concat(["_", rstr.go(t, "")]))])

def rstr(+xs: List<&2, U32>) -> String: rstr.go(xs, "")

def r_rs(+nm: String, xs: List<&2, U32>) -> String: rd(nm, rstr(xs))

# The `m` spelling. ONE caller group, three fixtures, and it is the ONLY thing that
# reaches `rstr.neg` -- `axis_id`'s members are `Nat`s, so the branch is dead
# for every value a graph can hold. Kept as a def so the grammar is whole and
# its dead arm is pinned by a row rather than deleted.
def r_rsn(+nm: String, v: U32) -> String: rd(nm, rstr.neg(v))

# `lt` and `pri` row builders. `r_lt` is the TYPE MAP over the whole grid plus the
def nth_s(+xs: List<&2, String>, i: U32) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, U32.to_nat(i)), "!OOB")

def r_lt(+nm: String, +d: S.Dt) -> String: rd(nm, lt.of(d))

def r_ltn(+nm: String, +d: S.Dt, cnt: U32, ptr: Bool) -> String: rd(nm, lt.t(d, cnt, ptr))

def r_pri(+nm: String, +d: S.Dt) -> String: rd(nm, U32.show(lt.pri(d)))

# `lt` and `pri` row builders. `r_lt` is the TYPE MAP over the whole grid plus the
# two weak dtypes whose absence from CPython's map is a `KeyError`, and `r_pri` is
# the ONE load-bearing numeric field `lt.fp` disambiguates half from bfloat16
# with -- a separate group so a renumbering of `spec.bend`'s priorities is a moved
# row and not a new spelling discovered later.
# The indexed-read primitive. `List.get` answers `Maybe` and EVERY caller
# in this file wants a `String` -- a multi-line emitter's `i`-th line, an
# argument's type -- so the default is spelled ONCE here rather than as a
# `Maybe.default` in twenty row builders. `"!OOB"` is the wall for an index
# past the end: CPython would raise `IndexError`, and a row whose index is
# out of range is a row nobody writes.
# `base_rewrite` -- llvmir.py:77-144. THE EIGHTEEN RULES' OUTPUTS.
def br_rules.b(+k: U32) -> U32: Bool.pick(U32, U32.is_eq(k, 1), 23, 5)

def br_rules(+k: U32) -> U32: Bool.pick(U32, U32.is_eq(k, 0), 18, br_rules.b(k))

# `ctx[x][1:]` -- the LABEL SLICE that drops the leading `%`. It appears in NINE
# of the eighteen rules and it is the one transformation in this file that is not
# a concatenation, so it gets its own rows rather than being inlined four times,
# where a dropped `drop` moves one caller and leaves the other three alone.
def lab(+xn: String) -> String: String.drop(xn, 1n)

def r_lab() -> String:
  String.concat([rd("lab %v0", lab("%v0")), rd("lab %data0", lab("%data0")),
    rd("lab %reg_12", lab("%reg_12")), rd("lab %local_2", lab("%local_2")),
    rd("lab %v99", lab("%v99"))])

# RULE 1, the REGISTER INDEX (llvmir.py:82-83). The ONLY rule that can answer

def br1.line(+is_alu: Bool, +xn: String, +bufn: String, +d: S.Dt, +cnt: U32, +idx: U32) -> String:
  Bool.pick(String, is_alu, String.concat(["  ", xn, " = extractelement ", lt.t(d, cnt, False{}),
    " ", bufn, ", i32 ", U32.show(idx)]), "None")

def r_br1(+nm: String, +is_alu: Bool, +bufn: String, +d: S.Dt, cnt: U32, idx: U32) -> String:
  rd(nm, br1.line(is_alu, "%v0", bufn, d, cnt, idx))

# THE TABLE IS IN `.agents/slop/tables/renderer-llvmir-526.md` -- RULE 2, the PREDICATED LOAD (llvmir.py:86-93). EIGHT lines -- the longest

def br2.text(+vol: Bool, +d: S.Dt, +cnt: U32, +xn: String, +idx: String, +alt: String, +mask: String) -> String:
  String.concat([String.concat(["  br label ", xn, "_entry", nl()]),
    String.concat([lab(xn), "_entry:", nl()]),
    String.concat(["  br i1 ", mask, ", label ", xn, "_load, label ", xn, "_exit", nl()]),
    String.concat([lab(xn), "_load:", nl()]),
    String.concat(["  ", xn, "_yes = load ", volsp(vol), lt.t(d, cnt, False{}), ", ", lt.t(d, cnt, True{}), " ", idx, nl()]),
    String.concat(["  br label ", xn, "_exit", nl()]),
    String.concat([lab(xn), "_exit:", nl()]),
    String.concat(["  ", xn, " = phi ", lt.t(d, cnt, False{}), " [", xn, "_yes, ", xn, "_load], [", alt, ", ", xn, "_entry]"])])

def r_br2(+nm: String, +vol: Bool, +d: S.Dt, +xn: String, +idx: String, +alt: String, +mask: String, +i: U32) -> String:
  rd(nm, nth(String.lines(br2.text(vol, d, 1, xn, idx, alt, mask)), U32.to_nat(i)))

# RULES 3 and 4, the bare `load` and the `store` (llvmir.py:94-99). ONE line

def br3.line(+vol: Bool, +d: S.Dt, +cnt: U32, +xn: String, +idx: String) -> String:
  String.concat(["  ", xn, " = load ", volsp(vol), lt.t(d, cnt, False{}), ", ", lt.t(d, cnt, True{}), " ", idx])

def br4.line(+vol: Bool, +d: S.Dt, +cnt: U32, +varn: String, +idx: String) -> String:
  String.concat(["  store ", volsp(vol), lt.t(d, cnt, False{}), " ", varn, ", ", lt.t(d, cnt, True{}), " ", idx])

def r_br3(+nm: String, +vol: Bool, +d: S.Dt, +xn: String, +idx: String) -> String:
  rd(nm, br3.line(vol, d, 1, xn, idx))

def r_br4(+nm: String, +vol: Bool, +d: S.Dt, +varn: String, +idx: String) -> String:
  rd(nm, br4.line(vol, d, 1, varn, idx))

# RULE 5, the STACK `insertelement` CHAIN (llvmir.py:102-105). The only LOOP in

def br5.name(+xn: String, +i: U32, +n: U32) -> String:
  Bool.pick(String, U32.is_eq(U32.add(i, 1), n), xn, String.concat([xn, "_", U32.show(i)]))

def br5.pred(+xn: String, +i: U32) -> String:
  Bool.pick(String, U32.is_eq(i, 0), "poison", String.concat([xn, "_", U32.show(U32.sub(i, 1))]))

def nth_d(+xs: List<&2, S.Dt>, +i: U32) -> S.Dt: Maybe.default(&2, S.Dt, List.get(&2, S.Dt, xs, U32.to_nat(i)), S.void())

def sdts_len(+xs: List<&2, S.Dt>) -> U32: U32.from_nat(List.length(&2, S.Dt, xs))

def br5.line(+xn: String, +sdts: List<&2, S.Dt>, +snames: List<&2, String>, cnt: U32, +i: U32) -> String:
  String.concat(["  ", br5.name(xn, i, sdts_len(sdts)), " = insertelement ",
    lt.t(nth_d(sdts, 0), cnt, False{}), " ", br5.pred(xn, i), ", ",
    lt.of(nth_d(sdts, i)), " ", nth(snames, U32.to_nat(i)), ", i32 ", U32.show(i)])

def r_br5(+nm: String, +xn: String, +sdts: List<&2, S.Dt>, +snames: List<&2, String>, cnt: U32, +i: U32) -> String:
  rd(nm, br5.line(xn, sdts, snames, cnt, i))

# RULES 6-10: BITCAST, CAST, TRUNC, the BINARY `lop` and WHERE (llvmir.py:
def br6.same(+d: S.Dt, +od: S.Dt) -> Bool: U32.is_eq(S.Dt.itemsize(d), S.Dt.itemsize(od))

def br6.line(+d: S.Dt, +od: S.Dt, +cnt: U32, +xn: String, +s: String) -> String:
  Bool.pick(String, br6.same(d, od),
    String.concat(["  ", xn, " = bitcast ", lt.t(d, cnt, False{}), " ", s, " to ", lt.t(od, cnt, False{})]),
    "RuntimeError")

def br7.line(+d: S.Dt, +od: S.Dt, +xn: String, +s: String) -> String:
  String.concat(["  ", xn, " = ", N.lcast.a(d, od), " ", lt.of(d), " ", s, " to ", lt.of(od)])

# `ldt(x.dtype)` appears TWICE and `ldt(x.src[0].dtype)` once -- llvmir.py:111 --
def br8.line(+d: S.Dt, +od: S.Dt, +xn: String, +s: String) -> String:
  String.concat(["  ", xn, " = call ", lt.of(d), " @llvm.trunc.", lt.of(d), "(", lt.of(d), " ", s, ")"])

def br9.line(+d: S.Dt, +op: O.Op, +xn: String, +s0: String, +s1: String) -> String:
  Bool.pick(String, N.lop.has(op, d),
    String.concat(["  ", xn, " = ", N.lop.cell(d, op), " ", lt.of(d), " ", s0, ", ", s1]), "KeyError")

def br10.line(+d0: S.Dt, +d1: S.Dt, +d2: S.Dt, +xn: String, +s0: String, +s1: String, +s2: String) -> String:
  String.concat(["  ", xn, " = select ", lt.of(d0), " ", s0, ", ", lt.of(d1), " ", s1, ", ", lt.of(d2), " ", s2])

def r_br6(+nm: String, +fd: S.Dt, +od: S.Dt, +cnt: U32, +xn: String, +sn: String) -> String:
  rd(nm, br6.line(fd, od, cnt, xn, sn))

def r_br7(+nm: String, +a: S.Dt, +b: S.Dt, +xn: String, +sn: String) -> String:
  rd(nm, br7.line(a, b, xn, sn))

def r_br8(+nm: String, +a: S.Dt, +b: S.Dt, +xn: String, +sn: String) -> String:
  rd(nm, br8.line(a, b, xn, sn))

def r_br9(+nm: String, +d: S.Dt, +op: O.Op, +xn: String, +s0: String, +s1: String) -> String:
  rd(nm, br9.line(d, op, xn, s0, s1))

def r_br10(+nm: String, +d0: S.Dt, +d1: S.Dt, +d2: S.Dt, +xn: String, +s0: String, +s1: String, +s2: String) -> String:
  rd(nm, br10.line(d0, d1, d2, xn, s0, s1, s2))

# RULES 11-14: the void-RANGE header, the BACKEDGE, the counted RANGE (NINE
# lines) and the END. All four are built on `lab(...)` or on `range_str`, so a `%`
# that never gets dropped is a DIFFERENT LABEL on four of the five.

def br11.text(+rn: String) -> String:
  String.concat(["  br label %loop_", lab(rn), nl(), "loop_", lab(rn), ":"])

def br12.text(+rn: String, +cn: String) -> String:
  String.concat(["  br i1 ", cn, ", label %loop_", lab(rn), ", label %loop_exit_", lab(rn), nl(),
    "loop_exit_", lab(rn), ":"])

def br13.text(+aid: String, +rn: String, +bn: String, +d: S.Dt) -> String:
  String.concat([String.concat(["  br label %loop_entry_", aid, nl(), "loop_entry_", aid, ":", nl()]),
    String.concat(["  br label %loop_latch_", aid, nl(), "loop_latch_", aid, ":", nl()]),
    String.concat(["  ", rn, " = phi ", lt.of(d), " [ 0, %loop_entry_", aid, " ], [ ", rn, "phi, %loop_footer_", aid, " ]", nl()]),
    String.concat(["  ", rn, "phi = add ", lt.of(d), " ", rn, ", 1", nl()]),
    String.concat(["  ", rn, "cmp = icmp ult ", lt.of(d), " ", rn, ", ", bn, nl()]),
    String.concat(["  br i1 ", rn, "cmp, label %loop_body_", aid, ", label %loop_exit_", aid, nl()]),
    String.concat(["loop_body_", aid, ":"])])

def br14.text(+aid: String) -> String:
  String.concat(["  br label %loop_footer_", aid, nl(), "loop_footer_", aid, ":", nl(),
    "  br label %loop_latch_", aid, nl(), "loop_exit_", aid, ":"])

def r_br11(+nm: String, +rn: String, i: U32) -> String:
  rd(nm, nth_s(String.lines(br11.text(rn)), i))

def r_br12(+nm: String, +rn: String, +cn: String, i: U32) -> String:
  rd(nm, nth_s(String.lines(br12.text(rn, cn)), i))

def r_br13(+nm: String, +aid: String, +rn: String, +bn: String, +d: S.Dt, i: U32) -> String:
  rd(nm, nth_s(String.lines(br13.text(aid, rn, bn, d)), i))

def r_br14(+nm: String, aid: U32, i: U32) -> String:
  rd(nm, nth_s(String.lines(br14.text(U32.show(aid))), i))

# RULES 15-17 AND THE AMD BARRIER (llvmir.py:140-143, :236). The IF header and the

def br15.text(+xn: String, +cn: String) -> String:
  String.concat(["  br i1 ", cn, ", label %ifbody_", lab(xn), ", label %ifskip_", lab(xn), nl(),
    "ifbody_", lab(xn), ":"])

def br16.text(+ifn: String) -> String:
  String.concat(["  br label %ifskip_", lab(ifn), nl(), "ifskip_", lab(ifn), ":"])

def br17.text() -> String: "  fence seq_cst"

def r_br15(+nm: String, +xn: String, +cn: String, i: U32) -> String:
  rd(nm, nth_s(String.lines(br15.text(xn, cn)), i))

def r_br16(+nm: String, +ifn: String, i: U32) -> String:
  rd(nm, nth_s(String.lines(br16.text(ifn)), i))

def r_br17(+nm: String) -> String: rd(nm, br17.text())

def r_amd2(+nm: String, i: U32) -> String:
  rd(nm, nth_s(String.lines(String.join(N.barrier(), nl())), i))

# AMD'S FIVE RULES AHEAD OF `base_rewrite` (llvmir.py:232-242). Rule 3's TWO
def f8pos.go(+ds: List<&2, S.Dt>, +d: S.Dt, +i: U32) -> U32:
  match ds:
    case Nil{}      : 4294967295
    case h <> +t    : Bool.pick(U32, O.eq_dt(h, d), i, f8pos.go(t, d, U32.add(i, 1)))

# `f8pos.go`'s miss is CPython's `list.index()` raising `ValueError`, so 4294967295
# is a SENTINEL and not an index: `fp8_pos i32` is the row that makes it reachable,
# and a reader who answers 0 for a miss would agree with CPython on the FOUR fp8
# rows and be wrong everywhere else.
def f8pos.miss(+m: U32) -> String: Bool.pick(String, U32.is_eq(m, 4294967295), "ValueError", U32.show(m))

def f8pos(+d: S.Dt) -> U32: f8pos.go(N.fp8s(), d, 0)

def fp8i(+d: S.Dt) -> U32: U32.mod(f8pos(d), 2)

def f8names.go(+ds: List<&2, S.Dt>, +acc: String) -> String:
  match ds:
    case Nil{}      : acc
    case h <> +t    : String.concat([acc, dtn(h), Bool.pick(String, List.is_empty(&2, S.Dt, t), "",
      String.concat([",", f8names.go(t, "")]))])

def f8names() -> String: f8names.go(N.fp8s(), "")

def r_f8o() -> String: rd("fp8s.order", f8names())

def r_f8i(+nm: String, +d: S.Dt) -> String:
  rd(String.concat(["fp8_index ", nm]), U32.show(fp8i(d)))

def r_f8p(+nm: String, +d: S.Dt) -> String:
  rd(String.concat(["fp8_pos ", nm]), f8pos.miss(f8pos(d)))

# the same wall through the other direction, as its own pair of defs: `fp8_pos i32`
# and `fp8_index i32` are two rows of the SAME miss and they are what make the
# sentinel reachable. One def for both would give one of them the other's NAME.
def r_f8mp(+nm: String, +d: S.Dt) -> String: rd(String.concat(["fp8_pos ", nm]), f8pos.miss(f8pos(d)))

def r_f8mi(+nm: String, +d: S.Dt) -> String: rd(String.concat(["fp8_index ", nm]), f8pos.miss(f8pos(d)))

def amd0.text(+is_l: Bool, +x: U32, +xn: String) -> String:
  String.concat(["  ", xn, " = ", N.wi(is_l, x), "; "])

def amd1.line(+op: O.Op, +d: S.Dt, +od: S.Dt, +xn: String, +s: String) -> String:
  String.concat(["  ", xn, " = call ", lt.of(od), " @llvm.", N.intr_of(op), ".", lt.of(od), "(", lt.of(d), " ", s, ")"])

# "amd llvm intrinsics llvm.log2/llvm.exp2 don't support double" -- llvmir.py:300,
# upstream's comment ON AMD's `extra_matcher`. IT IS A LIMITATION OF THE
# TARGET'S INTRINSIC, NOT OF THE RENDERER: `@llvm.log2.f64` and
# `@llvm.exp2.f64` are not in the AMDGPU intrinsic set, so a double LOG2 or
# EXP2 that reached isel would EMIT a call the AMD backend cannot lower.
# UPSTREAM'S FIX IS A REWRITE -- `xlog2` / `xexp2`, the SOFTWARE
# DECOMPOSITIONS FROM `codegen/decomp/transcendental.py` -- AND IT RUNS IN
# `extra_matcher`, WHICH IS BEFORE ISEL. SO A DOUBLE LOG2 NEVER REACHES THIS
# EMITTER ON AN AMD TARGET.
#
# WHICH IS WHY THE PORT'S `amd1 log2 f64->f64` AND `amd1 exp2 f64->f64` ROWS
# ARE NOT A CLAIM THAT A DOUBLE LOG2 WORKS ON AMD. THEY ARE THE EMITTER'S
# SHAPE -- `llvm_intrinsics` (llvmir.py:79) MAPS LOG2 AND EXP2 FOR EVERY
# DTYPE, AND `lt.of(od)` IS THE OUTPUT TYPE -- SO THE ROWS ARE ABOUT THE
# SPELLING AND NOT ABOUT WHAT THE AMD BACKEND ACCEPTS. THE REWRITE THAT
# MAKES THE DOUBLE CASE REAL IS `extra_matcher`'s, AND `extra_matcher` IS A
# `PatternMatcher` -- A WALL, NAMED AT THE TOP OF THIS FILE.
def amd3.line(+xn: String, +s: String, +bf8: U32) -> String:
  String.concat(["  ", xn, " = call i8 @f32_to_fp8(float  ", s, ", i1 ", U32.show(bf8), ")"])

def amd4.text(+bf8: U32, +xn: String, +s: String) -> String:
  String.concat([String.concat(["  ", xn, "_i32 = zext i8 ", s, " to i32"]), nl(),
    String.concat(["  ", xn, " = call float @llvm.amdgcn.cvt.f32.", Bool.pick(String, U32.is_eq(bf8, 1), "bf8", "fp8"),
      "(i32 ", xn, "_i32, i32 0)"])])

def r_amd0(+nm: String, +is_l: Bool, x: U32, +xn: String) -> String:
  rd(nm, amd0.text(is_l, x, xn))

def r_amd1(+nm: String, +op: O.Op, +a: S.Dt, +b: S.Dt, +xn: String, +sn: String) -> String:
  rd(nm, amd1.line(op, a, b, xn, sn))

def r_amd3(+nm: String, +fp8: S.Dt, +xn: String, +sn: String) -> String:
  rd(nm, amd3.line(xn, sn, fp8i(fp8)))

def r_amd4(+nm: String, +fp8: S.Dt, +xn: String, +sn: String, i: U32) -> String:
  rd(nm, nth_s(String.lines(amd4.text(fp8i(fp8), xn, sn)), i))

# `_render_fn` -- llvmir.py:156-160, the AMD barrier rule, and `_render_footer`.
def sargs.one(+is_glob: Bool, +d: S.Dt, +nm: String) -> String:
  String.concat([lt.t(d, 1, is_glob), Bool.pick(String, is_glob, " noalias", ""), " ", nm])

def sargs.many(+xs: List<&2, String>) -> String: String.join(xs, ", ")

# `"\n".join((prefix or []) + [f"define{' '+abi if abi else ''} void @{name}({sargs}) #0", "{"] + kernel + ["  ret void\n}"])`
def rfn.slot(+abi: String) -> String: Bool.pick(String, String.eq(abi, ""), "", String.concat([" ", abi]))

def rfn.define(+abi: String, +nm: String, +sa: String) -> String:
  String.concat(["define", rfn.slot(abi), " void @", nm, "(", sa, ") #0"])

# `List.append` NESTING IS ONE DEEP in this toolchain -- three chained appends in
# one expression typechecks as a call with a length where a list belongs, and the
# error names `Quant` rather than `List`. `rfn.cat` is the one level of nesting
# that works, and it is a named def so the constraint is written down once.
def rfn.cat(+a: List<&2, String>, +b: List<&2, String>) -> List<&2, String>: List.append(&2, String, a, b)

def rfn.all(+abi: String, +nm: String, +sa: String, +kern: List<&2, String>, +pfx: List<&2, String>) -> String:
  String.join(rfn.cat(rfn.cat(pfx, rfn.cat([rfn.define(abi, nm, sa), "{"], kern)), ["  ret void", "}"]), nl())

def r_rfn(+nm: String, +abi: String, +kname: String, +sa: String, +kern: List<&2, String>, +pfx: List<&2, String>, +i: U32) -> String:
  rd(nm, nth_s(String.lines(rfn.all(abi, kname, sa, kern, pfx)), i))

def r_rsargs(+nm: String, +is_glob: Bool, +d: S.Dt, +argn: String) -> String:
  rd(nm, sargs.one(is_glob, d, argn))

def r_rsargs2e(+nm: String) -> String: rd(nm, sargs.many(Nil{}))

def r_rsargs2(+nm: String, +is_glob: Bool, +a: S.Dt, +b: S.Dt) -> String:
  rd(nm, sargs.many([sargs.one(is_glob, a, "%data0"), sargs.one(is_glob, b, "%data1")]))

# `CPU._render_footer` -- llvmir.py:210. A CONSTANT STRING with five attributes in
# a fixed order, so it is one row plus the nine space-separated PARTS: a reader who
# reorders them moves the joined row and every part row at once, and a reader who
# drops one quote moves `ftr cpu part 6` alone.
def ftr.cpu() -> String:
  String.concat(["attributes #0 = { alwaysinline nounwind \"no-builtins\" \"no-trapping-math\"=\"true\" }"])

def ftr.cpu_part(+i: U32) -> String:
  nth_s(String.split(ftr.cpu(), Char.from_u32(32)), i)

# `AMD._render_footer` -- llvmir.py:265-271. Its ONE input is
def prod.go(+ws: List<&2, U32>, +acc: U32) -> U32:
  match ws:
    case Nil{}   : acc
    case w <> +t : prod.go(t, U32.mul(acc, w))

def prod(+ws: List<&2, U32>) -> U32: prod.go(ws, 1)

# `ftr amd prod <lab>` is the DERIVED work-group size on its own -- the arithmetic,
# nine rows -- and `ftr amd <lab>` is the JOINED ATTRIBUTE STRING it is
# interpolated into. Both exist because a reader can get the NUMBER right while
# dropping one of the five attributes, and that reader moves the second and NONE
# of the nine. M69 in the mutation table is the shape of that bug: dropping the
# leading `1,` moves the joined rows alone.
def ftr.amd(+wg: U32) -> String:
  String.concat(["attributes #0 = { alwaysinline nounwind \"no-builtins\" \"amdgpu-flat-work-group-size\"=\"1,",
    U32.show(wg), "\" \"no-trapping-math\"=\"true\" }"])

def r_ftra(+nm: String, +ws: List<&2, U32>) -> String: rd(nm, ftr.amd(prod(ws)))

# `r_ftrc` is the CPU footer's CONSTANT string and `r_ftr` the AMD one, which
def r_ftr(+nm: String, +ws: List<&2, U32>) -> String: rd(nm, U32.show(prod(ws)))

def r_ftrc(+nm: String) -> String: rd(nm, ftr.cpu())

def r_ftrp(+i: U32) -> String:
  rd(String.concat(["ftr cpu part ", U32.show(i)]), ftr.cpu_part(i))

# `AMDLLVMRenderer.is_rdna4` -- llvmir.py:279: `arch.split(':')[0] in {'gfx1200',
# 'gfx1201'}`. The `:` matters and so does the `split`: `gfx1200:xnack-` is True
# and `gfx1200x` is False, and a `starts_with("gfx1200")` reader gets the second
# right and the third WRONG -- which is why `is_rdna4 gfx12001` and
# `is_rdna4 gfx1200x` are rows and not one.
def rd4.split(+arch: String) -> String: nth_s(String.split(arch, Char.from_u32(58)), 0)

def rd4.is_g1(+a: String) -> Bool: String.eq(a, "gfx1200")

def rd4.is(+arch: String) -> Bool:
  Bool.or(rd4.is_g1(rd4.split(arch)), String.eq(rd4.split(arch), "gfx1201"))

def r_rdna(+arch: String) -> String: rd(String.concat(["is_rdna4 ", arch]), bs(rd4.is(arch)))

def r_lts() -> String:
  String.concat([r_lt("lt void", S.void()), r_lt("lt weakfloat", S.weakfloat()), r_lt("lt weakint", S.weakint()), r_lt("lt fp8e4m3", S.fp8e4m3()), r_lt("lt fp8e5m2", S.fp8e5m2()), r_lt("lt fp8e4m3fnuz", S.fp8e4m3fnuz()), r_lt("lt fp8e5m2fnuz", S.fp8e5m2fnuz()), r_lt("lt f16", S.half()), r_lt("lt bf16", S.bfloat16()), r_lt("lt f32", S.single()), r_lt("lt f64", S.double()), r_lt("lt u8", S.uint8()), r_lt("lt u16", S.uint16()), r_lt("lt u32", S.uint32()), r_lt("lt u64", S.uint64()), r_lt("lt i8", S.int8()), r_lt("lt i16", S.int16()), r_lt("lt i32", S.int32()), r_lt("lt i64", S.int64()), r_lt("lt bool", S.boolean()), r_ltn("lt 1 ptr f32", S.single(), 1, True{}), r_ltn("lt 4     f32", S.single(), 4, False{}), r_ltn("lt 4 ptr f32", S.single(), 4, True{}), r_ltn("lt 1 ptr f32", S.single(), 1, True{}), r_ltn("lt 8     f64", S.double(), 8, False{}), r_ltn("lt 2 ptr bf16", S.bfloat16(), 2, True{})])

def r_pris() -> String:
  String.concat([r_pri("pri fp8e4m3", S.fp8e4m3()), r_pri("pri fp8e5m2", S.fp8e5m2()), r_pri("pri fp8e4m3fnuz", S.fp8e4m3fnuz()), r_pri("pri fp8e5m2fnuz", S.fp8e5m2fnuz()), r_pri("pri f16", S.half()), r_pri("pri bf16", S.bfloat16()), r_pri("pri f32", S.single()), r_pri("pri f64", S.double()), r_pri("pri u8", S.uint8()), r_pri("pri u16", S.uint16()), r_pri("pri u32", S.uint32()), r_pri("pri u64", S.uint64()), r_pri("pri i8", S.int8()), r_pri("pri i16", S.int16()), r_pri("pri i32", S.int32()), r_pri("pri i64", S.int64()), r_pri("pri bool", S.boolean())])

def r_ivs() -> String:
  String.concat([r_iv("is_volatile PARAM vol False", True{}, False{}), r_iv("is_volatile PARAM vol True", True{}, True{}), r_iv("is_volatile CAST vol False", True{}, False{}), r_iv("is_volatile CAST vol True", True{}, True{}), r_iv("is_volatile BUFFER vol False", False{}, False{}), r_iv("is_volatile BUFFER vol True", False{}, True{}), r_iv("is_volatile CONST vol False", False{}, False{}), r_iv("is_volatile CONST vol True", False{}, True{}), r_iv("is_volatile AFTER vol False", True{}, False{}), r_iv("is_volatile AFTER vol True", True{}, True{})])

def r_lc1s() -> String:
  String.concat([r_lcs("lconst special +inf", True{}, False{}), r_lcs("lconst special -inf", False{}, False{}), r_lcs("lconst special +nan", True{}, True{}), r_lcs("lconst special -nan", False{}, True{}), r_lcb("lconst branch void", S.void()), r_lcb("lconst branch bool", S.boolean()), r_lcb("lconst branch i8", S.int8()), r_lcb("lconst branch i16", S.int16()), r_lcb("lconst branch i32", S.int32()), r_lcb("lconst branch i64", S.int64()), r_lcb("lconst branch u8", S.uint8()), r_lcb("lconst branch u16", S.uint16()), r_lcb("lconst branch u32", S.uint32()), r_lcb("lconst branch u64", S.uint64()), r_lcb("lconst branch fp8e4m3", S.fp8e4m3()), r_lcb("lconst branch fp8e5m2", S.fp8e5m2()), r_lcb("lconst branch fp8e4m3fnuz", S.fp8e4m3fnuz()), r_lcb("lconst branch fp8e5m2fnuz", S.fp8e5m2fnuz()), r_lcb("lconst branch f16", S.half()), r_lcb("lconst branch bf16", S.bfloat16()), r_lcb("lconst branch f32", S.single()), r_lcb("lconst branch f64", S.double()), r_lci("lconst int 1.9", 1.9), r_lci("lconst int -1.9", F32.neg(1.9)), r_lci("lconst int 0.0", 0.0), r_lci("lconst int 255.5", 255.5), r_lci("lconst int -256.5", F32.neg(256.5)), r_lci("lconst int 2.5", 2.5), r_lci("lconst int -2.5", F32.neg(2.5)), r_lci("lconst uint 2.5", 2.5), r_lci("lconst uint -2.5", F32.neg(2.5)), r_lci("lconst uint 1.5", 1.5)])

def r_rss() -> String:
  String.concat([r_rsn("range_str neg 3", 3), r_rsn("range_str neg 0", 0), r_rsn("range_str neg 12", 12), r_rs("range_str 0", [0]), r_rs("range_str 3", [3]), r_rs("range_str 0,1", [0, 1]), r_rs("range_str 2,0,1", [2, 0, 1]), r_rs("range_str 7,8,9", [7, 8, 9])])

def r_cnts() -> String:
  String.concat([rd("base_rewrite.rules", U32.show(br_rules(0))), rd("amd.string_rewrite.rules", U32.show(br_rules(1))), rd("base_rewrite.after_amd", U32.show(br_rules(2)))])

def r_br1s() -> String:
  String.concat([r_br1("br1 extractelement alu", True{}, "%reg_1", S.single(), 4, 2), r_br1("br1 extractelement reg", False{}, "%reg_1", S.single(), 4, 2), r_br1("br1 extractelement global", False{}, "%reg_1", S.single(), 4, 2), r_br1("br1 extractelement local", False{}, "%reg_1", S.single(), 4, 2), r_br1("br1 extractelement alu i32", True{}, "%reg_1", S.int32(), 4, 1)])

def r_br2s() -> String:
  String.concat([r_br2("br2 load vol False f32 [0]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 0), r_br2("br2 load vol False f32 [1]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 1), r_br2("br2 load vol False f32 [2]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 2), r_br2("br2 load vol False f32 [3]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 3), r_br2("br2 load vol False f32 [4]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 4), r_br2("br2 load vol False f32 [5]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 5), r_br2("br2 load vol False f32 [6]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 6), r_br2("br2 load vol False f32 [7]", False{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 7), r_br2("br2 load vol False i32 [0]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 0), r_br2("br2 load vol False i32 [1]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 1), r_br2("br2 load vol False i32 [2]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 2), r_br2("br2 load vol False i32 [3]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 3), r_br2("br2 load vol False i32 [4]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 4), r_br2("br2 load vol False i32 [5]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 5), r_br2("br2 load vol False i32 [6]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 6), r_br2("br2 load vol False i32 [7]", False{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 7), r_br2("br2 load vol False u8 [0]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 0), r_br2("br2 load vol False u8 [1]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 1), r_br2("br2 load vol False u8 [2]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 2), r_br2("br2 load vol False u8 [3]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 3), r_br2("br2 load vol False u8 [4]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 4), r_br2("br2 load vol False u8 [5]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 5), r_br2("br2 load vol False u8 [6]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 6), r_br2("br2 load vol False u8 [7]", False{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 7), r_br2("br2 load vol True f32 [0]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 0), r_br2("br2 load vol True f32 [1]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 1), r_br2("br2 load vol True f32 [2]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 2), r_br2("br2 load vol True f32 [3]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 3), r_br2("br2 load vol True f32 [4]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 4), r_br2("br2 load vol True f32 [5]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 5), r_br2("br2 load vol True f32 [6]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 6), r_br2("br2 load vol True f32 [7]", True{}, S.single(), "%v0", "%v1", "%reg_0", "%v2", 7), r_br2("br2 load vol True i32 [0]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 0), r_br2("br2 load vol True i32 [1]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 1), r_br2("br2 load vol True i32 [2]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 2), r_br2("br2 load vol True i32 [3]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 3), r_br2("br2 load vol True i32 [4]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 4), r_br2("br2 load vol True i32 [5]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 5), r_br2("br2 load vol True i32 [6]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 6), r_br2("br2 load vol True i32 [7]", True{}, S.int32(), "%v0", "%v1", "%reg_0", "%v2", 7), r_br2("br2 load vol True u8 [0]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 0), r_br2("br2 load vol True u8 [1]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 1), r_br2("br2 load vol True u8 [2]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 2), r_br2("br2 load vol True u8 [3]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 3), r_br2("br2 load vol True u8 [4]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 4), r_br2("br2 load vol True u8 [5]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 5), r_br2("br2 load vol True u8 [6]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 6), r_br2("br2 load vol True u8 [7]", True{}, S.uint8(), "%v0", "%v1", "%reg_0", "%v2", 7)])

def r_br34s() -> String:
  String.concat([r_br3("br3 load vol False f32", False{}, S.single(), "%v0", "%v1"), r_br4("br4 store vol False f32", False{}, S.single(), "%v2", "%v1"), r_br3("br3 load vol False i8", False{}, S.int8(), "%v0", "%v1"), r_br4("br4 store vol False i8", False{}, S.int8(), "%v2", "%v1"), r_br3("br3 load vol False u64", False{}, S.uint64(), "%v0", "%v1"), r_br4("br4 store vol False u64", False{}, S.uint64(), "%v2", "%v1"), r_br3("br3 load vol True f32", True{}, S.single(), "%v0", "%v1"), r_br4("br4 store vol True f32", True{}, S.single(), "%v2", "%v1"), r_br3("br3 load vol True i8", True{}, S.int8(), "%v0", "%v1"), r_br4("br4 store vol True i8", True{}, S.int8(), "%v2", "%v1"), r_br3("br3 load vol True u64", True{}, S.uint64(), "%v0", "%v1"), r_br4("br4 store vol True u64", True{}, S.uint64(), "%v2", "%v1")])

def r_br5s() -> String:
  String.concat([r_br5("br5 stack n 1 f32 [0]", "%v0", [S.single()], ["%v1"], 4, 0), r_br5("br5 stack n 2 f32 [0]", "%v0", [S.single(), S.single()], ["%v1", "%v2"], 8, 0), r_br5("br5 stack n 2 f32 [1]", "%v0", [S.single(), S.single()], ["%v1", "%v2"], 8, 1), r_br5("br5 stack n 4 u8 [0]", "%v0", [S.uint8(), S.uint8(), S.uint8(), S.uint8()], ["%v1", "%v2", "%v3", "%v4"], 16, 0), r_br5("br5 stack n 4 u8 [1]", "%v0", [S.uint8(), S.uint8(), S.uint8(), S.uint8()], ["%v1", "%v2", "%v3", "%v4"], 16, 1), r_br5("br5 stack n 4 u8 [2]", "%v0", [S.uint8(), S.uint8(), S.uint8(), S.uint8()], ["%v1", "%v2", "%v3", "%v4"], 16, 2), r_br5("br5 stack n 4 u8 [3]", "%v0", [S.uint8(), S.uint8(), S.uint8(), S.uint8()], ["%v1", "%v2", "%v3", "%v4"], 16, 3), r_br5("br5 stack n 3 bf16 [0]", "%v0", [S.bfloat16(), S.bfloat16(), S.bfloat16()], ["%v1", "%v2", "%v3"], 12, 0), r_br5("br5 stack n 3 bf16 [1]", "%v0", [S.bfloat16(), S.bfloat16(), S.bfloat16()], ["%v1", "%v2", "%v3"], 12, 1), r_br5("br5 stack n 3 bf16 [2]", "%v0", [S.bfloat16(), S.bfloat16(), S.bfloat16()], ["%v1", "%v2", "%v3"], 12, 2)])

def r_br678s() -> String:
  String.concat([r_br6("br6 bitcast f32x4->i32x4", S.single(), S.int32(), 4, "%v0", "%v1"), r_br6("br6 bitcast i8x1->f32x1", S.int8(), S.single(), 1, "%v0", "%v1"), r_br6("br6 bitcast f16x8->bf16x8", S.half(), S.bfloat16(), 8, "%v0", "%v1"), r_br6("br6 bitcast u8x16->i8x16", S.uint8(), S.int8(), 16, "%v0", "%v1"), r_br7("br7 cast f32->i32", S.single(), S.int32(), "%v0", "%v1"), r_br7("br7 cast u32->f32", S.uint32(), S.single(), "%v0", "%v1"), r_br7("br7 cast i8->i16", S.int8(), S.int16(), "%v0", "%v1"), r_br7("br7 cast i16->i8", S.int16(), S.int8(), "%v0", "%v1"), r_br7("br7 cast bf16->f32", S.bfloat16(), S.single(), "%v0", "%v1"), r_br7("br7 cast f32->u8", S.single(), S.uint8(), "%v0", "%v1"), r_br7("br7 cast f64->f32", S.double(), S.single(), "%v0", "%v1"), r_br7("br7 cast f32->f64", S.single(), S.double(), "%v0", "%v1"), r_br7("br7 cast i64->i32", S.int64(), S.int32(), "%v0", "%v1"), r_br8("br8 trunc f32->i32", S.single(), S.int32(), "%v0", "%v1"), r_br8("br8 trunc i32->i8", S.int32(), S.int8(), "%v0", "%v1"), r_br8("br8 trunc f64->f32", S.double(), S.single(), "%v0", "%v1"), r_br9("br9 binary bool ADD", S.boolean(), O.OpsADD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bool MUL", S.boolean(), O.OpsMUL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bool TRUNCDIV", S.boolean(), O.OpsTRUNCDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bool TRUNCMOD", S.boolean(), O.OpsTRUNCMOD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bool CMPLT", S.boolean(), O.OpsCMPLT{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bool SHR", S.boolean(), O.OpsSHR{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bool SHL", S.boolean(), O.OpsSHL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bool FDIV", S.boolean(), O.OpsFDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary u8 ADD", S.uint8(), O.OpsADD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary u8 MUL", S.uint8(), O.OpsMUL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary u8 TRUNCDIV", S.uint8(), O.OpsTRUNCDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary u8 TRUNCMOD", S.uint8(), O.OpsTRUNCMOD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary u8 CMPLT", S.uint8(), O.OpsCMPLT{}, "%v0", "%v1", "%v2"), r_br9("br9 binary u8 SHR", S.uint8(), O.OpsSHR{}, "%v0", "%v1", "%v2"), r_br9("br9 binary u8 SHL", S.uint8(), O.OpsSHL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary u8 FDIV", S.uint8(), O.OpsFDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i32 ADD", S.int32(), O.OpsADD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i32 MUL", S.int32(), O.OpsMUL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i32 TRUNCDIV", S.int32(), O.OpsTRUNCDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i32 TRUNCMOD", S.int32(), O.OpsTRUNCMOD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i32 CMPLT", S.int32(), O.OpsCMPLT{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i32 SHR", S.int32(), O.OpsSHR{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i32 SHL", S.int32(), O.OpsSHL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i32 FDIV", S.int32(), O.OpsFDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i8 ADD", S.int8(), O.OpsADD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i8 MUL", S.int8(), O.OpsMUL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i8 TRUNCDIV", S.int8(), O.OpsTRUNCDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i8 TRUNCMOD", S.int8(), O.OpsTRUNCMOD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i8 CMPLT", S.int8(), O.OpsCMPLT{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i8 SHR", S.int8(), O.OpsSHR{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i8 SHL", S.int8(), O.OpsSHL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary i8 FDIV", S.int8(), O.OpsFDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f32 ADD", S.single(), O.OpsADD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f32 MUL", S.single(), O.OpsMUL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f32 TRUNCDIV", S.single(), O.OpsTRUNCDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f32 TRUNCMOD", S.single(), O.OpsTRUNCMOD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f32 CMPLT", S.single(), O.OpsCMPLT{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f32 SHR", S.single(), O.OpsSHR{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f32 SHL", S.single(), O.OpsSHL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f32 FDIV", S.single(), O.OpsFDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f16 ADD", S.half(), O.OpsADD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f16 MUL", S.half(), O.OpsMUL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f16 TRUNCDIV", S.half(), O.OpsTRUNCDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f16 TRUNCMOD", S.half(), O.OpsTRUNCMOD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f16 CMPLT", S.half(), O.OpsCMPLT{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f16 SHR", S.half(), O.OpsSHR{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f16 SHL", S.half(), O.OpsSHL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f16 FDIV", S.half(), O.OpsFDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bf16 ADD", S.bfloat16(), O.OpsADD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bf16 MUL", S.bfloat16(), O.OpsMUL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bf16 TRUNCDIV", S.bfloat16(), O.OpsTRUNCDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bf16 TRUNCMOD", S.bfloat16(), O.OpsTRUNCMOD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bf16 CMPLT", S.bfloat16(), O.OpsCMPLT{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bf16 SHR", S.bfloat16(), O.OpsSHR{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bf16 SHL", S.bfloat16(), O.OpsSHL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary bf16 FDIV", S.bfloat16(), O.OpsFDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f64 ADD", S.double(), O.OpsADD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f64 MUL", S.double(), O.OpsMUL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f64 TRUNCDIV", S.double(), O.OpsTRUNCDIV{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f64 TRUNCMOD", S.double(), O.OpsTRUNCMOD{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f64 CMPLT", S.double(), O.OpsCMPLT{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f64 SHR", S.double(), O.OpsSHR{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f64 SHL", S.double(), O.OpsSHL{}, "%v0", "%v1", "%v2"), r_br9("br9 binary f64 FDIV", S.double(), O.OpsFDIV{}, "%v0", "%v1", "%v2"), r_br10("br10 where mixed", S.boolean(), S.single(), S.int32(), "%v0", "%v1", "%v2", "%v3")])

def r_brRBs() -> String:
  String.concat([r_br11("br11 rangevoid [0]", "%v3", 0), r_br11("br11 rangevoid [1]", "%v3", 1), r_br13("br13 range [0]", "0", "%v3", "%v2", S.int32(), 0), r_br13("br13 range [1]", "0", "%v3", "%v2", S.int32(), 1), r_br13("br13 range [2]", "0", "%v3", "%v2", S.int32(), 2), r_br13("br13 range [3]", "0", "%v3", "%v2", S.int32(), 3), r_br13("br13 range [4]", "0", "%v3", "%v2", S.int32(), 4), r_br13("br13 range [5]", "0", "%v3", "%v2", S.int32(), 5), r_br13("br13 range [6]", "0", "%v3", "%v2", S.int32(), 6), r_br13("br13 range [7]", "0", "%v3", "%v2", S.int32(), 7), r_br13("br13 range [8]", "0", "%v3", "%v2", S.int32(), 8), r_br13("br13 range neg [0]", "3", "%v3", "%v2", S.int32(), 0), r_br13("br13 range neg [1]", "3", "%v3", "%v2", S.int32(), 1), r_br13("br13 range neg [2]", "3", "%v3", "%v2", S.int32(), 2), r_br13("br13 range neg [3]", "3", "%v3", "%v2", S.int32(), 3), r_br13("br13 range neg [4]", "3", "%v3", "%v2", S.int32(), 4), r_br13("br13 range neg [5]", "3", "%v3", "%v2", S.int32(), 5), r_br13("br13 range neg [6]", "3", "%v3", "%v2", S.int32(), 6), r_br13("br13 range neg [7]", "3", "%v3", "%v2", S.int32(), 7), r_br13("br13 range neg [8]", "3", "%v3", "%v2", S.int32(), 8), r_br12("br12 backedge [0]", "%v3", "%v4", 0), r_br12("br12 backedge [1]", "%v3", "%v4", 1), r_br14("br14 end pos [0]", 7, 0), r_br14("br14 end pos [1]", 7, 1), r_br14("br14 end pos [2]", 7, 2), r_br14("br14 end pos [3]", 7, 3), r_br14("br14 end neg [0]", 3, 0), r_br14("br14 end neg [1]", 3, 1), r_br14("br14 end neg [2]", 3, 2), r_br14("br14 end neg [3]", 3, 3)])

def r_brIBs() -> String:
  String.concat([r_br15("br15 if bool [0]", "%v7", "%v6", 0), r_br15("br15 if bool [1]", "%v7", "%v6", 1), r_br16("br16 endif bool [0]", "%v7", 0), r_br16("br16 endif bool [1]", "%v7", 1), r_br15("br15 if i32 [0]", "%v7", "%v6", 0), r_br15("br15 if i32 [1]", "%v7", "%v6", 1), r_br16("br16 endif i32 [0]", "%v7", 0), r_br16("br16 endif i32 [1]", "%v7", 1), r_br17("br17 barrier"), r_amd2("amd2 barrier [0]", 0), r_amd2("amd2 barrier [1]", 1), r_amd2("amd2 barrier [2]", 2), r_amd2("amd2 barrier [3]", 3)])

def r_amds() -> String:
  String.concat([r_f8o(), r_f8p("fp8e4m3", S.fp8e4m3()), r_f8p("fp8e5m2", S.fp8e5m2()), r_f8p("fp8e4m3fnuz", S.fp8e4m3fnuz()), r_f8p("fp8e5m2fnuz", S.fp8e5m2fnuz()), r_f8mp("i32", S.int32()), r_f8mp("f16", S.half()), r_f8i("fp8e4m3", S.fp8e4m3()), r_f8i("fp8e5m2", S.fp8e5m2()), r_f8i("fp8e4m3fnuz", S.fp8e4m3fnuz()), r_f8i("fp8e5m2fnuz", S.fp8e5m2fnuz()), r_f8mi("i32", S.int32()), r_f8mi("f16", S.half()), r_amd0("amd0 special g0", False{}, 0, "%v3"), r_amd0("amd0 special g2", False{}, 2, "%v3"), r_amd0("amd0 special l0", True{}, 0, "%v3"), r_amd0("amd0 special l1", True{}, 1, "%v3"), r_amd0("amd0 special l2", True{}, 2, "%v3"), r_amd1("amd1 sqrt f32->f32", O.OpsSQRT{}, S.single(), S.single(), "%v0", "%v1"), r_amd1("amd1 sqrt f16->f16", O.OpsSQRT{}, S.half(), S.half(), "%v0", "%v1"), r_amd1("amd1 sqrt f64->f64", O.OpsSQRT{}, S.double(), S.double(), "%v0", "%v1"), r_amd1("amd1 log2 f32->f32", O.OpsLOG2{}, S.single(), S.single(), "%v0", "%v1"), r_amd1("amd1 log2 f16->f16", O.OpsLOG2{}, S.half(), S.half(), "%v0", "%v1"), r_amd1("amd1 log2 f64->f64", O.OpsLOG2{}, S.double(), S.double(), "%v0", "%v1"), r_amd1("amd1 exp2 f32->f32", O.OpsEXP2{}, S.single(), S.single(), "%v0", "%v1"), r_amd1("amd1 exp2 f16->f16", O.OpsEXP2{}, S.half(), S.half(), "%v0", "%v1"), r_amd1("amd1 exp2 f64->f64", O.OpsEXP2{}, S.double(), S.double(), "%v0", "%v1"), r_amd3("amd3 cast f32->fp8e4m3", S.fp8e4m3(), "%v0", "%v1"), r_amd3("amd3 cast f32->fp8e5m2", S.fp8e5m2(), "%v0", "%v1"), r_amd3("amd3 cast f32->fp8e4m3fnuz", S.fp8e4m3fnuz(), "%v0", "%v1"), r_amd3("amd3 cast f32->fp8e5m2fnuz", S.fp8e5m2fnuz(), "%v0", "%v1"), r_amd4("amd4 cast fp8e4m3->f32 [0]", S.fp8e4m3(), "%v0", "%v1", 0), r_amd4("amd4 cast fp8e4m3->f32 [1]", S.fp8e4m3(), "%v0", "%v1", 1), r_amd4("amd4 cast fp8e5m2->f32 [0]", S.fp8e5m2(), "%v0", "%v1", 0), r_amd4("amd4 cast fp8e5m2->f32 [1]", S.fp8e5m2(), "%v0", "%v1", 1), r_amd4("amd4 cast fp8e4m3fnuz->f32 [0]", S.fp8e4m3fnuz(), "%v0", "%v1", 0), r_amd4("amd4 cast fp8e4m3fnuz->f32 [1]", S.fp8e4m3fnuz(), "%v0", "%v1", 1), r_amd4("amd4 cast fp8e5m2fnuz->f32 [0]", S.fp8e5m2fnuz(), "%v0", "%v1", 0), r_amd4("amd4 cast fp8e5m2fnuz->f32 [1]", S.fp8e5m2fnuz(), "%v0", "%v1", 1)])

def r_rfns() -> String:
  String.concat([r_rsargs("rfn sargs global", True{}, S.single(), "%data0"), r_rsargs2("rfn sargs2 global", True{}, S.single(), S.uint32()), r_rsargs("rfn sargs reg", False{}, S.single(), "%data0"), r_rsargs2("rfn sargs2 reg", False{}, S.single(), S.uint32()), r_rsargs("rfn sargs local", False{}, S.single(), "%data0"), r_rsargs2("rfn sargs2 local", False{}, S.single(), S.uint32()), r_rsargs("rfn sargs alu", False{}, S.single(), "%data0"), r_rsargs2("rfn sargs2 alu", False{}, S.single(), S.uint32()), r_rsargs2e("rfn sargs2 empty"), r_rfn("rfn abi None global [0]", "", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0), r_rfn("rfn abi None global [1]", "", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1), r_rfn("rfn abi None global [2]", "", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2), r_rfn("rfn abi None global [3]", "", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3), r_rfn("rfn abi None global [4]", "", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4), r_rfn("rfn abi None global [5]", "", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5), r_rfn("rfn abi None reg [0]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0), r_rfn("rfn abi None reg [1]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1), r_rfn("rfn abi None reg [2]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2), r_rfn("rfn abi None reg [3]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3), r_rfn("rfn abi None reg [4]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4), r_rfn("rfn abi None reg [5]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5), r_rfn("rfn abi None local [0]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0), r_rfn("rfn abi None local [1]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1), r_rfn("rfn abi None local [2]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2), r_rfn("rfn abi None local [3]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3), r_rfn("rfn abi None local [4]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4), r_rfn("rfn abi None local [5]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5), r_rfn("rfn abi None alu [0]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0), r_rfn("rfn abi None alu [1]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1), r_rfn("rfn abi None alu [2]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2), r_rfn("rfn abi None alu [3]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3), r_rfn("rfn abi None alu [4]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4), r_rfn("rfn abi None alu [5]", "", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5), r_rfn("rfn abi amdgpu_kernel global [0]", "amdgpu_kernel", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0), r_rfn("rfn abi amdgpu_kernel global [1]", "amdgpu_kernel", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1), r_rfn("rfn abi amdgpu_kernel global [2]", "amdgpu_kernel", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2), r_rfn("rfn abi amdgpu_kernel global [3]", "amdgpu_kernel", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3), r_rfn("rfn abi amdgpu_kernel global [4]", "amdgpu_kernel", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4), r_rfn("rfn abi amdgpu_kernel global [5]", "amdgpu_kernel", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5), r_rfn("rfn abi amdgpu_kernel reg [0]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0), r_rfn("rfn abi amdgpu_kernel reg [1]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1), r_rfn("rfn abi amdgpu_kernel reg [2]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2), r_rfn("rfn abi amdgpu_kernel reg [3]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3), r_rfn("rfn abi amdgpu_kernel reg [4]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4), r_rfn("rfn abi amdgpu_kernel reg [5]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5), r_rfn("rfn abi amdgpu_kernel local [0]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0), r_rfn("rfn abi amdgpu_kernel local [1]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1), r_rfn("rfn abi amdgpu_kernel local [2]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2), r_rfn("rfn abi amdgpu_kernel local [3]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3), r_rfn("rfn abi amdgpu_kernel local [4]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4), r_rfn("rfn abi amdgpu_kernel local [5]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5), r_rfn("rfn abi amdgpu_kernel alu [0]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0), r_rfn("rfn abi amdgpu_kernel alu [1]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1), r_rfn("rfn abi amdgpu_kernel alu [2]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2), r_rfn("rfn abi amdgpu_kernel alu [3]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3), r_rfn("rfn abi amdgpu_kernel alu [4]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4), r_rfn("rfn abi amdgpu_kernel alu [5]", "amdgpu_kernel", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5), r_rfn("rfn abi win64cc global [0]", "win64cc", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0), r_rfn("rfn abi win64cc global [1]", "win64cc", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1), r_rfn("rfn abi win64cc global [2]", "win64cc", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2), r_rfn("rfn abi win64cc global [3]", "win64cc", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3), r_rfn("rfn abi win64cc global [4]", "win64cc", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4), r_rfn("rfn abi win64cc global [5]", "win64cc", "mykernel", "float* noalias %data0, i32* noalias %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5), r_rfn("rfn abi win64cc reg [0]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0), r_rfn("rfn abi win64cc reg [1]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1), r_rfn("rfn abi win64cc reg [2]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2), r_rfn("rfn abi win64cc reg [3]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3), r_rfn("rfn abi win64cc reg [4]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4), r_rfn("rfn abi win64cc reg [5]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5), r_rfn("rfn abi win64cc local [0]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0), r_rfn("rfn abi win64cc local [1]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1), r_rfn("rfn abi win64cc local [2]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2), r_rfn("rfn abi win64cc local [3]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3), r_rfn("rfn abi win64cc local [4]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4), r_rfn("rfn abi win64cc local [5]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5), r_rfn("rfn abi win64cc alu [0]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 0), r_rfn("rfn abi win64cc alu [1]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 1), r_rfn("rfn abi win64cc alu [2]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 2), r_rfn("rfn abi win64cc alu [3]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 3), r_rfn("rfn abi win64cc alu [4]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 4), r_rfn("rfn abi win64cc alu [5]", "win64cc", "mykernel", "float %data0, i32 %data1", ["  %v0 = fadd", "  %v1 = fmul"], [], 5), r_rfn("rfn abi None empty [0]", "", "empty", "", ["  %v0 = fadd"], [], 0), r_rfn("rfn abi None empty [1]", "", "empty", "", ["  %v0 = fadd"], [], 1), r_rfn("rfn abi None empty [2]", "", "empty", "", ["  %v0 = fadd"], [], 2), r_rfn("rfn abi None empty [3]", "", "empty", "", ["  %v0 = fadd"], [], 3), r_rfn("rfn abi None empty [4]", "", "empty", "", ["  %v0 = fadd"], [], 4), r_rfn("rfn prefix [0]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 0), r_rfn("rfn prefix [1]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 1), r_rfn("rfn prefix [2]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 2), r_rfn("rfn prefix [3]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 3), r_rfn("rfn prefix [4]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 4), r_rfn("rfn prefix [5]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 5), r_rfn("rfn prefix [6]", "amdgpu_kernel", "withprefix", "float* noalias %data0", ["  %v0 = fadd"], ["PREFIX1", "PREFIX2"], 6)])

def r_ftrs() -> String:
  String.concat([r_ftrc("ftr cpu"), r_ftrp(0), r_ftrp(1), r_ftrp(2), r_ftrp(3), r_ftrp(4), r_ftrp(5), r_ftrp(6), r_ftrp(7), r_ftrp(8), r_ftr("ftr amd prod none", []), r_ftra("ftr amd none", []), r_ftr("ftr amd prod w64", [64]), r_ftra("ftr amd w64", [64]), r_ftr("ftr amd prod wx64h8", [64, 8]), r_ftra("ftr amd wx64h8", [64, 8]), r_ftr("ftr amd prod wgx1024", [1024]), r_ftra("ftr amd wgx1024", [1024]), r_ftr("ftr amd prod wx1", [1]), r_ftra("ftr amd wx1", [1]), r_ftr("ftr amd prod wglobal", []), r_ftra("ftr amd wglobal", []), r_ftr("ftr amd prod wgl", [16]), r_ftra("ftr amd wgl", [16]), r_ftr("ftr amd prod w3", [32, 32, 32]), r_ftra("ftr amd w3", [32, 32, 32]), r_ftr("ftr amd prod wbig", [65535, 65535]), r_ftra("ftr amd wbig", [65535, 65535])])

def r_rdnas() -> String:
  String.concat([r_rdna("gfx1200"), r_rdna("gfx1201"), r_rdna("gfx12001"), r_rdna("gfx1100"), r_rdna("gfx1200:xnack-"), r_rdna("gfx942"), r_rdna("AMD_GCN3_"), r_rdna("gfx1200x"), r_rdna("gfx120"), r_rdna("gfx12012"), r_rdna("gfx1201:xnack-")])
# ONE print for the WHOLE table, so `IO.print`'s own newline is the only frame and
# the oracle's single trailing "\n" is its match.
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([r_lab(), r_lts(), r_pris(), r_ivs(), r_lc1s(), r_rss(), r_cnts(),
      r_br1s(), r_br2s(), r_br34s(), r_br5s(), r_br678s(), r_brRBs(), r_brIBs(),
      r_amds(), r_rfns(), r_ftrs(), r_rdnas()]))

# THE MUTATION TABLE. Measured with `.agents/slop/li/li-mutate.py rules`: ONE
# TEXTUAL EDIT AT A TIME, and the harness diffs WHOLE `name=value` LINES and
# prints WHICH rows moved. A name-comparing harness reported 0 for all 30
# mutations in one unit and 0 for all 68 in another, so this one compares text.
#
# 79 mutations, 76 moved something, 3 blind -- and the 3 are the COMMENT-ONLY
# CONTROLS, which is the only outcome they are allowed to have.
#
#   M1 lt.fp's 16-bit arm is half 9 amd1 exp2 f16->f16, amd1 log2 f16->f16, amd1 s
#   M2 lt.fp answers double at pri 13 11 br5 stack n 3 bf16 [0], br5 stack n 3 bf1
#   M3 lt.ints is bits // 8 70 br1 extractelement alu i32, br10 where mixed, br13
#   M4 CONTROL a comment-only edit 0
#   M5 lt.v's count arm is >= 1 33 br2 load vol False f32 [4], br2 load vol False
#   M6 lt.v's count arm is dropped 19 br1 extractelement alu, br1 extractelement a
#   M7 lt.fp's 8-bit arm is 9 4 lt fp8e4m3, lt fp8e4m3fnuz, lt fp8e5m2 ...
#
# M3 IS THE LARGEST SINGLE MOVEMENT (70 rows) and it is `lt.ints` answering
# `bits // 8`. That is the same bug `nir_llvmir.bend`'s own header records as
# having been FOUND there -- `i1`, `i2`, `i4`, `i8` for the eight- and sixteen-
# bit types -- and the reason this file re-arms `lt` rather than fixing a copy of
# it is that a fix which is a NAME is a fix which is one rename away from broken
# again.
#
# M73 IS THE SECOND LARGEST (84 rows) and it is the OPPOSITE KIND of finding:
