#!/usr/bin/env python3
"""Mutation harness for tinybendygrad/renderer/tc_ptx.bend.

Each entry is a (name, old, new) edit that must appear EXACTLY ONCE in the
source. The harness applies it to a scratch copy IN THE SAME DIRECTORY (the file
imports ./../LAWS/spec.bend and ./../uop/ops.bend by relative path), runs the
interpreted lane, and diffs against the unmutated lane. What moves is the
measurement; what does NOT move is the more useful half -- it names what this
gate is blind to.

Usage:
    python3 .agents/slop/tcptx-mutate.py            # run all
    python3 .agents/slop/tcptx-mutate.py M7 M12     # run some
"""

import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REL = "tinybendygrad/renderer/tc_ptx.bend"
BEND = os.path.join(ROOT, "bin", "bend")

MUTATIONS = [
  # ---------------------------------------------------------------- tc.py
  ("M1",
   "def cd(+bit: U32, +ax: U32) -> U32: U32.or(U32.shln(bit, 2n), ax)",
   "def cd(+bit: U32, +ax: U32) -> U32: U32.or(U32.shln(bit, 1n), ax)",
   "the coord PACKING is `(bit << 2) | axis`, not `(bit << 1) | axis`."),
  ("M2",
   "def AX_K() -> U32: 2",
   "def AX_K() -> U32: 3",
   "axis code k=2, not k=3. Three axes, so a wrong code either collides or\n"
   "   falls off the `cd_ax` mask."),
  ("M3",
   "def Tc.used(+t: Tc) -> List<&2, U32>: cc4(Tc.la(t), Tc.ea(t), Tc.lc(t), Tc.ec(t))",
   "def Tc.used(+t: Tc) -> List<&2, U32>: cc4(Tc.la(t), Tc.ea(t), Tc.lb(t), Tc.eb(t))",
   "`base_upcast_axes` reads C's blocks, not B's."),
  ("M4",
   "def Tc.threads(+t: Tc) -> U32: pow2(ln(Tc.lc(t)))",
   "def Tc.threads(+t: Tc) -> U32: pow2(ln(Tc.lb(t)))",
   "`threads` is 2**len(frag_c[0]) -- and it is UNOBSERVABLE which fragment it\n"
   "   reads, because `__post_init__` ASSERTS `len(f[0]) == len(frag_c[0])` for\n"
   "   all three. A, B and C have the same lane count in EVERY legal\n"
   "   TensorCore, so no fixture can separate the three readers. M4b reads\n"
   "   frag_c[1] instead, which the assertion does not cover."),
  ("M4b",
   "def Tc.threads(+t: Tc) -> U32: pow2(ln(Tc.lc(t)))",
   "def Tc.threads(+t: Tc) -> U32: pow2(ln(Tc.ec(t)))",
   "the same question against frag_c's ELEMENT slots, which `__post_init__` does\n"
   "   NOT tie to the lane count -- so this one IS observable, and it is what\n"
   "   makes M4's blindness a property of the assertion and not of the fixture."),
  ("M5",
   "def cacc(+bs: List<&2, U32>, v: U32, +d: U32) -> U32: cacc.go(bs, v, 0, d, 0)",
   "def cacc(+bs: List<&2, U32>, v: U32, +d: U32) -> U32: cacc.go(bs, v, 0, d, 1)",
   "`frag_coords`' accumulator STARTS at 0, not at 1. Seeding it with `v` instead\n"
   "   is the affinity's job, not this mutation's: it is refused at compile time."),
  ("M6",
   "      U32.add(acc, U32.shln(U32.and(U32.shrn(v, U32.to_nat(j)), 1), U32.to_nat(cd_bit(c)))), acc))",
   "      U32.add(acc, U32.shln(U32.and(U32.shrn(v, U32.to_nat(j)), 1), U32.to_nat(cd_ax(c)))), acc))",
   "the bit that goes into a coord is the LANE index shifted by the BIT index\n"
   "   (`cd_bit`), not by the AXIS code (`cd_ax`)."),
  ("M7",
   "def Tc.cover(+t: Tc, la: List<&2, U32>, +ea: List<&2, U32>, ax0: U32, ax1: U32) -> Bool:",
   "def Tc.cover(+t: Tc, la: List<&2, U32>, +ea: List<&2, U32>, ax0: U32, ax1: U32) -> Bool:  # noqa",
   "CONTROL: a comment-only edit, which must move NOTHING."),
  ("M8",
   "def c_mma_lane() -> List<&2, U32>: cd5(nk(1), nk(2), mk(0), mk(1), mk(2))",
   "def c_mma_lane() -> List<&2, U32>: cd5(nk(1), nk(2), mk(0), mk(1), mk(3))",
   "`mma`'s fragment_c lane coords end at m2, not m3 (M=8)."),
  ("M9",
   "def fnv(+s: String) -> U32: fnv.go(s, 2166136261)",
   "def fnv(+s: String) -> U32: fnv.go(s, 2166136260)",
   "FNV-1a's 32-bit OFFSET BASIS. The `frag_coords` rows are DIGESTS, so a wrong\n"
   "   basis is invisible to a sample and loud on every digest row."),
  ("M10",
   "def pow2(n: U32) -> U32: U32.shln(1, U32.to_nat(n))",
   "def pow2(n: U32) -> U32: U32.shln(1, U32.to_nat(U32.add(n, 1)))",
   "every count in the file goes through `pow2`; an off-by-one here is a wall of\n"
   "   wrong `dims`/`threads` rows at once."),

  # ---------------------------------------------------------------- ptx.py
  ("M11",
   "  [O.OpsEXP2{}, O.OpsADD{}, O.OpsMUL{}, O.OpsMAX{}, O.OpsCMPLT{}, O.OpsWHERE{}, O.OpsTRUNC{}]",
   "  [O.OpsEXP2{}, O.OpsADD{}, O.OpsMUL{}, O.OpsMAX{}, O.OpsCMPLT{}, O.OpsWHERE{}, O.OpsSHR{}]",
   "`supports_half` ends in TRUNC, not SHR -- and because the same list feeds\n"
   "   `doesnt_support_half`, ONE wrong name moves BOTH rows."),
  ("M12",
   "  [O.OpsEXP2{}, O.OpsADD{}, O.OpsMUL{}, O.OpsMAX{}, O.OpsCMPLT{}, O.OpsWHERE{}, O.OpsTRUNC{}]",
   "  [O.OpsTRUNC{}, O.OpsEXP2{}, O.OpsADD{}, O.OpsMUL{}, O.OpsMAX{}, O.OpsCMPLT{}, O.OpsWHERE{}]",
   "the tuple's ORDER is the literal's, not the dict's -- moving TRUNC to the\n"
   "   front moves `supports_half` and leaves `doesnt_support_half` alone."),
  ("M13",
   "def dsh.go(+ops: List<&2, O.Op>, +acc: List<&2, O.Op>) -> List<&2, O.Op>:\n"
   "  match ops:\n"
   "    case Nil{}   : acc\n"
   "    case o <> +t :\n"
   "      +rest = dsh.go(t, acc)\n"
   "      Bool.pick(List<&2, O.Op>, in_sh(o), rest, List.append(&2, O.Op, [o], rest))",
   "def dsh.go(+ops: List<&2, O.Op>, +acc: List<&2, O.Op>) -> List<&2, O.Op>:\n"
   "  match ops:\n"
   "    case Nil{}   : acc\n"
   "    case o <> +t :\n"
   "      +rest = dsh.go(t, acc)\n"
   "      Bool.pick(List<&2, O.Op>, in_sh(o), rest, List.append(&2, O.Op, rest, [o]))",
   "the DROP filter keeps the dict's order: the head goes in FRONT\n"
   "   (`[o] ++ rest`), not at the end."),
  ("M14",
   "def dsh_half.go(+ts: List<&2, Tc>, +acc: List<&2, Tc>) -> List<&2, Tc>:\n"
   "  match ts:\n"
   "    case Nil{}   : acc\n"
   "    case t <> +r :\n"
   "      +rest = dsh_half.go(r, acc)\n"
   "      Bool.pick(List<&2, Tc>, dsh_half.keep(t), List.append(&2, Tc, [t], rest), rest)",
   "def dsh_half.go(+ts: List<&2, Tc>, +acc: List<&2, Tc>) -> List<&2, Tc>:\n"
   "  match ts:\n"
   "    case Nil{}   : acc\n"
   "    case t <> +r :\n"
   "      +rest = dsh_half.go(r, acc)\n"
   "      Bool.pick(List<&2, Tc>, dsh_half.keep(t), List.append(&2, Tc, rest, [t]), rest)",
   "same cons-vs-append question for `tensor_cores`, and it REVERSES the whole\n"
   "   five-entry list, so it is the largest single-row movement in the table."),
  ("M15",
   "def sd12.go(+ver: U32, +acc: List<&2, S.Dt>, +ds: List<&2, S.Dt>) -> List<&2, S.Dt>:\n"
   "  match ds:\n"
   "    case Nil{}   : acc\n"
   "    case d <> +t :\n"
   "      +rest = sd12.go(ver, acc, t)\n"
   "      Bool.pick(List<&2, S.Dt>, sd_keep(ver, d), List.append(&2, S.Dt, [d], rest), rest)",
   "def sd12.go(+ver: U32, +acc: List<&2, S.Dt>, +ds: List<&2, S.Dt>) -> List<&2, S.Dt>:\n"
   "  match ds:\n"
   "    case Nil{}   : acc\n"
   "    case d <> +t :\n"
   "      +rest = sd12.go(ver, acc, t)\n"
   "      Bool.pick(List<&2, S.Dt>, sd_keep(ver, d), List.append(&2, S.Dt, rest, [d]), rest)",
   "the same choice for `supported_dtypes` -- and it is a BLIND SPOT, because\n"
   "   that row SORTS the names before printing, so a reversal cannot show."),
  ("M16",
   "def sd_keep(+ver: U32, +dt: S.Dt) -> Bool:\n"
   "  Bool.and(Bool.or(Bool.not(O.eq_dt(dt, S.half())), U32.is_ge(ver, 53)), Bool.not(O.eq_dt(dt, S.bfloat16())))",
   "def sd_keep(+ver: U32, +dt: S.Dt) -> Bool:\n"
   "  Bool.or(Bool.not(O.eq_dt(dt, S.half())), U32.is_ge(ver, 53))",
   "the `not in fp8s + (bfloat16,)` clause is dropped. sm_53 is the fixture\n"
   "   that bites, because it is the only arch where the OTHER conjunct is true."),
  ("M17",
   "def sd_keep(+ver: U32, +dt: S.Dt) -> Bool:\n"
   "  Bool.and(Bool.or(Bool.not(O.eq_dt(dt, S.half())), U32.is_ge(ver, 53)), Bool.not(O.eq_dt(dt, S.bfloat16())))",
   "def sd_keep(+ver: U32, +dt: S.Dt) -> Bool:\n"
   "  Bool.and(Bool.not(O.eq_dt(dt, S.half())), U32.is_ge(ver, 53))",
   "the `int(arch[3:]) >= 53` conjunct is dropped -- half survives below sm_53."),
  ("M18",
   "def dsh_half.keep(+t: Tc) -> Bool: Bool.or(O.eq_dt(Tc.di(t), S.half()), O.eq_dt(Tc.di(t), S.single()))",
   "def dsh_half.keep(+t: Tc) -> Bool: Bool.or(O.eq_dt(Tc.di(t), S.half()), O.eq_dt(Tc.dou(t), S.single()))",
   "`tensor_cores` filters on `dtype_IN`, not `dtype_out` -- the swap is\n"
   "   invisible for half tables and visible on the bf16->float one."),
  ("M19",
   'Bool.and(Dtf.is_int(fa), Dtf.is_float(fb)), ".rzi",',
   'Bool.and(Dtf.is_int(fa), Bool.or(Dtf.is_float(fb), Dtf.is_bool(fb))), ".rzi",',
   "`modifier`'s FIRST clause widens to int->bool, which is what the 9x6 grid\n"
   "   is wide enough to catch."),
  ("M20",
   "  Bool.pick(String, Bool.and(Dtf.is_float(fa), Bool.or(U32.is_lt(S.Dt.itemsize(a), S.Dt.itemsize(b)),\n"
   "      Bool.or(Dtf.is_int(fb), O.eq_dt(b, S.boolean())))), \".rn\", \"\"))",
   "  Bool.pick(String, Bool.and(Dtf.is_float(fa), Bool.or(U32.is_lt(S.Dt.itemsize(a), S.Dt.itemsize(b)),\n"
   "      Dtf.is_int(fb))), \".rn\", \"\"))",
   "the `or b == bool` tail of the SECOND clause: float->bool is `.rn` and the\n"
   "   grid has that pair."),
  ("M21",
   "    case O.OpsSHL{}       : [String.concat([\"shl.b\", String.drop(name, 1n), \" \", d, \", \", a, \", \", b, \";\"])]",
   "    case O.OpsSHL{}       : [String.concat([\"shl.b\", name, \" \", d, \", \", a, \", \", b, \";\"])]",
   "`shl.b{name[1:]}` DROPS the leading char of the type name, so bool gives\n"
   "   `shl.bred`, not `shl.bpred`."),
  ("M22",
   "    case O.OpsXOR{}       : Bool.pick(List<&2, String>, Dtf.is_bool(f), [String.concat([\"xor.pred \", d, \", \", a, \", \", b, \";\"])], [String.concat([\"xor.b\", String.drop(name, 1n), \" \", d, \", \", a, \", \", b, \";\"])])",
   "    case O.OpsXOR{}       : Bool.pick(List<&2, String>, Dtf.is_bool(f), [String.concat([\"xor.pred \", d, \", \", a, \", \", b, \";\"])], [String.concat([\"xor.b\", name, \" \", d, \", \", a, \", \", b, \";\"])])",
   "the same `name[1:]` read on XOR, which has a BOOL arm as well -- so this\n"
   "   one mutation moves both the `pred` and the `b16`/`b32` rows."),
  ("M23",
    '      [String.concat(["selp.", Bool.pick(String, String.eq(name, "f16"), "b16", name), " ", d, ", ", b, ", ", c, ", ", a, ";"])])\n',
    '      [String.concat(["selp.", name, " ", d, ", ", b, ", ", c, ", ", a, ";"])])\n',
   "PTX has no `selp.f16`, so the f16 name becomes `selp.b16`."),
  ("M24",
   "    case O.OpsMUL{}       : [String.concat([Bool.pick(String, Dtf.is_bool(f), \"and\", \"mul\"), Bool.pick(String, Dtf.is_int(f), \".lo\", \"\"), \".\", name, \" \", d, \", \", a, \", \", b, \";\"])]",
   "    case O.OpsMUL{}       : [String.concat([Bool.pick(String, Dtf.is_bool(f), \"and\", \"mul\"), \".\", name, \" \", d, \", \", a, \", \", b, \";\"])]",
   "MUL's `.lo` is there only for INTEGERS, so float MUL has no `.lo`."),
  ("M25",
   "    case O.OpsCMPNE{}     : [String.concat([\"setp.\", Bool.pick(String, Dtf.is_float(f), \"neu\", \"ne\"), \".\", name, \" \", d, \", \", a, \", \", b, \";\"])]",
   "    case O.OpsCMPNE{}     : [String.concat([\"setp.\", Bool.pick(String, Dtf.is_float(f), \"ne\", \"neu\"), \".\", name, \" \", d, \", \", a, \", \", b, \";\"])]",
   "CMPNE's two-argument form is the FLOAT one: `setp.neu` for float, `ne`\n"
   "   for int. Swapping them moves five dtype rows at once."),
  ("M26",
   "    case O.OpsMULACC{}    : [String.concat([Bool.pick(String, Dtf.is_float(f), \"fma.rn.\", \"mad.lo.\"), name, \" \", d, \", \", a, \", \", b, \", \", c, \";\"])]",
   "    case O.OpsMULACC{}    : [String.concat([Bool.pick(String, Dtf.is_int(f), \"fma.rn.\", \"mad.lo.\"), name, \" \", d, \", \", a, \", \", b, \", \", c, \";\"])]",
   "MULACC picks on is_FLOAT, not on is_int -- the two dtypes where they\n"
   "   disagree are exactly the bool rows."),
  ("M27",
   "    case O.OpsTRUNC{}     : [String.concat([\"cvt.rzi.\", name, \".\", name, \" \", d, \", \", a, \";\"])]",
   "    case O.OpsTRUNC{}     : [String.concat([\"cvt.rzi.\", name, \".\", \"s32\", \" \", d, \", \", a, \";\"])]",
   "TRUNC spells the type name TWICE, both from `name`."),
  ("M28",
   "def render_val(is_float: Bool, is_half: Bool, is_unsigned: Bool, +x: F32, +v: U32) -> String:",
   "def render_val(is_float: Bool, is_half: Bool, is_unsigned: Bool, +x: F32, +v: U32) -> String:  # noqa",
   "CONTROL 2: a comment-only edit on a stage-2 def, which must move NOTHING."),
  ("M29",
   '  Bool.pick(String, is_half, String.concat(["0x", hex4(f16bits(x))]), String.concat(["0f", hex8(F32.bits(x))]))',
   '  Bool.pick(String, is_half, String.concat(["0f", hex8(F32.bits(x))]), String.concat(["0x", hex4(f16bits(x))]))',
   "the two spellings are SWAPPED: half re-encodes to `0x` and float reads its\n"
   "   own `F32.bits` as `0f`."),
  ("M30",
   "def render_val_f(+x: F32, is_half: Bool) -> String:",
   "def render_val_f(+x: F32, is_half: Bool) -> String:  # noqa",
   "CONTROL 3: a comment-only edit inside the float arm, which must move\n"
   "   NOTHING."),
  ("M31",
   "def hex4(+x: U32) -> String: String.concat([hex1(U32.shrn(x, 12n)), hex1(U32.shrn(x, 8n)), hex1(U32.shrn(x, 4n)), hex1(x)])",
   "def hex4(+x: U32) -> String: String.concat([hex1(U32.shrn(x, 28n)), hex1(U32.shrn(x, 20n)), hex1(U32.shrn(x, 12n)), hex1(U32.shrn(x, 4n))])",
   "the four hex digits of a half are nibbles 3..0, not 7..4 -- a shift that\n"
   "   keeps the same WIDTH and so keeps the same row length."),
  ("M32",
   "def epr(+dt: S.Dt) -> U32: U32.div(4, S.Dt.itemsize(dt))",
   "def epr(+dt: S.Dt) -> U32: U32.div(2, S.Dt.itemsize(dt))",
   "`4 // itemsize`: 4 elements ride in a 32-bit register, so fp32 packs 1 and\n"
   "   half packs 2. Off by a factor of two the `{a, b}` slices are wrong."),
  ("M33",
   "  String.join(List.take(&2, String, List.drop(&2, String, xs, U32.to_nat(U32.mul(i, 2))), 2n), \", \")",
   "  String.join(List.take(&2, String, List.drop(&2, String, xs, U32.to_nat(U32.mul(i, 2))), 2n), \",\")",
   "the pack join is `', '` -- a SPACE after the comma -- so the register list\n"
   "   reads `{a, b}` and not `{a,b}`."),
  ("M34",
   "def fmt_rep_of(+line: String) -> String: Bool.pick(String, fmt_wide(line), tab(), tab2())",
   "def fmt_rep_of(+line: String) -> String: Bool.pick(String, fmt_wide(line), tab2(), tab())",
   "a mnemonic LONGER than seven characters gets ONE tab and a short one gets\n"
   "   TWO, so `mov.b32` and `shl.b32` bracket the threshold from both sides."),
  ("M35",
   "def fmt_wide(+line: String) -> Bool: U32.is_gt(U32.from_nat(String.length(fmt_head_str(line))), 7)",
   "def fmt_wide(+line: String) -> Bool: U32.is_ge(U32.from_nat(String.length(fmt_head_str(line))), 7)",
   "the threshold is `> 7`, not `>= 7`; a 7-character mnemonic is the row\n"
   "   that separates the two."),
  ("M36",
   "  Bool.pick(String, fmt_israw(line), line, String.concat([tab(), String.from_list(fmt_rep(String.to_list(line), fmt_rep_of(line), Nil{}))]))",
   "  Bool.pick(String, fmt_israw(line), String.concat([tab(), line]), String.concat([tab(), String.from_list(fmt_rep(String.to_list(line), fmt_rep_of(line), Nil{}))]))",
   "a `$` line is INLINED ASM and passes through with no tab at all."),
  ("M37",
   "    case +c <> +t : Bool.pick(List<&2, Char>, U32.is_eq(Char.to_u32(c), 32),\n"
   "      List.concat(&2, Char, [acc, String.to_list(rep), t]),\n"
   "      List.concat(&2, Char, [acc, [c], fmt_rep(t, rep, acc)]))",
   "    case +c <> +t : Bool.pick(List<&2, Char>, U32.is_eq(Char.to_u32(c), 32),\n"
   "      List.concat(&2, Char, [acc, [c], t]),\n"
   "      List.concat(&2, Char, [acc, [c], fmt_rep(t, rep, acc)]))",
   "the `1` on `replace` is LOAD-BEARING: the FIRST space becomes the tab\n"
   "   sequence and every later space is left alone."),
  ("M38",
   "def Pr.text(p: Pr) -> String:\n"
   "  match p:\n"
   "    case Pr{nm, is_glob, dt}: String.concat([\".param .\", Bool.pick(String, is_glob, \"u64\", types_of(dt)), \" \", nm])",
   "def Pr.text(p: Pr) -> String:\n"
   "  match p:\n"
   "    case Pr{nm, is_glob, dt}: String.concat([\".param .\", Bool.pick(String, is_glob, \"u64\", \"s32\"), \" \", nm])",
   "a NON-GLOBAL parameter is the DTYPE's own PTX name, and a hard-coded\n"
   "   \"s32\" would agree with the int32 this fixture used to carry. The k1\n"
   "   fixture is a LOCAL FLOAT now precisely so that the two cannot."),
  ("M39",
   "def rk_head(nm: String) -> List<&2, String>:\n"
   "  [px_p0(), px_p1(), px_p2(), String.concat([px_p3(), \" \", nm, \" (\"])]",
   "def rk_head(nm: String) -> List<&2, String>:\n"
   "  [px_p0(), px_p1(), px_p2(), String.concat([px_p3(), \" (\"])]",
   "the function name goes BETWEEN `.visible .entry` and the open paren."),
  ("M40",
   "  List.concat(&2, String, [[\")\"], [String.concat([\".maxntid \", U32.show(lb)])], [\"{\"], body, [\"}\"]])",
   "  List.concat(&2, String, [[\")\"], [String.concat([\".maxntid \", U32.show(lb)])], [\"{\"], body])",
   "the closing `}` is a LINE of the kernel, so dropping it is a MOVED row\n"
   "   and not a shorter last row."),
  ("M41",
   'def k1_ps() -> List<&2, Pr>: [Pr{"data0", True{}, S.single()}, Pr{"data1", False{}, S.single()}]',
   'def k1_ps() -> List<&2, Pr>: [Pr{"data0", True{}, S.single()}, Pr{"data1", False{}, S.double()}]',
   "a NON-GLOBAL parameter is the DTYPE's own PTX name, and a double is `f64`\n"
   "   where an int32 would have been `s32`. This is M38's other direction: the\n"
   "   fixture that says the name is READ rather than typed."),

  ("M42",
   "def rk_lines(nm: String, lb: U32, +ps: List<&2, Pr>, +body: List<&2, String>) -> List<&2, String>:\n"
   "  List.concat(&2, String, [rk_head(nm), rk_param_lines(ps, Nil{}), rk_close(lb, body)])",
   "def rk_lines(nm: String, lb: U32, +ps: List<&2, Pr>, +body: List<&2, String>) -> List<&2, String>:\n"
   "  List.concat(&2, String, [rk_head(nm), rk_param_lines(ps, Nil{}), body, rk_close(lb, Nil{})])",
   "the body sits BETWEEN the params and the close: the BODY line is 9 of k1\n"
   "   and the closing brace is 10, so swapping them is a MOVED pair of rows."),

  # ------------------------------------------------ the ESCAPE, and the escapes
  ("M43",
   "def btab() -> String: String.concat([bslash(), \"t\"])",
   "def btab() -> String: tab()",
   "the `py=` halves are CPython REPR text, so a TAB there is a backslash and a\n"
   "   `t`; spelling it as a real tab breaks the barrier row and every fmt row\n"
   "   that has one -- and the diff cannot see it, because a tab and a\n"
   "   backslash-t are the same byte count in a terminal and different bytes in a\n"
   "   file, which is the whole reason the gate is a byte diff."),
  ("M44",
   "def q(+s: String) -> String: String.concat([\"'\", esc(s), \"'\"])",
   "def q(+s: String) -> String: String.concat([\"[\", esc(s), \"]\"])",
   "CPython's `repr` of a `str` uses SINGLE quotes, and the row NAME carries the\n"
   "   quotes too -- so the name moves as well as the value."),

  # ------------------------------------------------ the MMA spelling
  ("M45",
   "def sp12() -> String: String.repeat(\" \", 12n)",
   "def sp12() -> String: String.repeat(\" \", 11n)",
   "the twelve SPACES between the mma type list and the operand list are a\n"
   "   `\"\"*12`, and PTX column alignment is load-bearing for a human reader\n"
   "   and invisible to nvcc."),
  ("M46",
   "    \"{\", j(Wmr.wc(w)), \"}, {\", j(Wmr.wa(w)), \"}, {\", j(Wmr.wb(w)), \"}, {\", j(Wmr.wc(w)), \"};\"])",
   "    \"{\", j(Wmr.wc(w)), \"}, {\", j(Wmr.wa(w)), \"}, {\", j(Wmr.wb(w)), \"};\"])",
   "the accumulator is passed TWICE -- once in, once out -- and the third\n"
   "   operand is B's pack, not a repeat of C's."),
  ("M47",
   "def dtmap_out(dt: S.Dt) -> String: Bool.pick(String, O.eq_dt(dt, S.single()), \"f32\", \"f16\")",
   "def dtmap_out(dt: S.Dt) -> String: Bool.pick(String, O.eq_dt(dt, S.single()), \"tf32\", \"f16\")",
   "`dt_map_out[float]` is \"f32\" and `dt_map_in[float]` is \"tf32\"; the two\n"
   "   maps share their KEY and not their value, so the output map is the only\n"
   "   place \"f32\" appears."),

  # ------------------------------------------------ ROW ORDER, which is the diff
  ("M48",
   "  String.concat([r_sd(75, \"bool,double,float,half,int,long,short,signed char,unsigned char,unsigned int,unsigned long,unsigned short\"), r_sd(53,",
   "  String.concat([r_sd(53, \"bool,double,float,half,int,long,short,signed char,unsigned char,unsigned int,unsigned long,unsigned short\"), r_sd(75,",
   "the archs are 75, 53, 80 -- CPython's tuple order, and a `diff` is\n"
   "   POSITIONAL, so two rows with the same text in the wrong order are still a\n"
   "   diff. The oracle walks `(\"sm_75\", \"sm_53\", \"sm_80\")`."),
  ("M49",
   "  String.concat([r_types1(\"signed char\", S.int8(), \"s16\"),",
   "  String.concat([r_types1(\"int\", S.int32(), \"s32\"),",
   "the tables are in `PTXRenderer.types`' OWN order (int8, int16, int32,\n"
   "   int64, uint8, ...), which is a dict order and not a sorted one, and the\n"
   "   gate is POSITIONAL. This edit also DELETES the row it replaces, so the\n"
   "   count is a loss and a move at once."),

  # ------------------------------------------------ the dtype tables
  ("M50",
   "def types_of(+dt: S.Dt) -> String:",
   "def types_of(+dt: S.Dt) -> String:  # noqa",
   "CONTROL 5: a comment-only edit on the dtype table reader, which must move\n"
   "   NOTHING. Together with M7, M28 and M30 that is four controls."),
]


def run_gate(src_path):
  """Run the interpreted lane. Returns (ok, stdout+stderr)."""
  r = subprocess.run([BEND, src_path], cwd=ROOT, capture_output=True, text=True)
  return (r.returncode == 0 and "PROOFS FAIL" not in r.stdout), r.stdout + r.stderr


def main():
  want = [a for a in sys.argv[1:] if a != "--short"]
  short = "--short" in sys.argv
  with open(os.path.join(ROOT, REL)) as f:
    base = f.read()

  ok, baseline = run_gate(os.path.join(ROOT, REL))
  if not ok:
    print("BASELINE DOES NOT RUN:\n" + baseline[:2000])
    return 1
  base_lines = baseline.splitlines()

  results = []
  for mid, old, new, what in MUTATIONS:
    if mid and want and mid not in want:
      continue
    n = base.count(old)
    if n != 1:
      results.append((mid, None, "EDIT MATCHES %d TIMES -- fix the mutation" % n, what))
      continue
    scratch_dir = os.path.join(ROOT, os.path.dirname(REL))
    with tempfile.NamedTemporaryFile("w", suffix=".bend", dir=scratch_dir, delete=False) as tf:
      tf.write(base.replace(old, new))
      tmp = tf.name
    try:
      ok, out = run_gate(tmp)
    finally:
      os.unlink(tmp)
    if not ok:
      # The REASON a mutation fails to compile is the measurement: it says the
      # type system pinned something the text does not.
      first = [x for x in out.splitlines() if x.startswith("- ")][:1]
      results.append((mid, None, "FAIL compile (%s)" % (first[0][2:][:60] if first else "?"), what))
      continue
    mut = out.splitlines()
    moved = [i for i, (a, b) in enumerate(zip(base_lines, mut)) if a != b]
    nmoved = len(mut) - len(base_lines)
    names = []
    for i in moved[:6]:
      names.append(base_lines[i].split("=")[0].strip())
    more = " ..." if len(moved) > 6 else ""
    label = ", ".join(names) or "(none)"
    results.append((mid, moved, "%d row(s): %s%s%s" % (len(moved), label,
                     more, "  %+d lines" % nmoved if nmoved else ""), what))

  width = max(len(r[0]) for r in results) + 2
  for mid, moved, summary, what in results:
    print("%-*s %s" % (width, mid, summary))
    if not short:
      for ln in what.splitlines():
        print("%-*s   %s" % (width, "", ln))
  return 0


if __name__ == "__main__":
  sys.exit(main())
