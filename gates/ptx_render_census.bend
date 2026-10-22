# ptx_render_census.bend -- A RENDER CENSUS over `tinybendygrad/renderer/ptx.bend`.
#
#   .venv/bin/python gates/ptx_render_census-gate.py
#
# THE FOURTH RENDER CENSUS. `cstyle` diffs a rendered STRING; `wgsl` diffs a whole shader
# MODULE; `amd_dsl` diffs a TRIPLE. `ptx.py` returns a WHOLE PTX MODULE too -- and that
# fact is the whole design of this file, because the module's BODY comes from TWENTY-THREE
# `string_rewrite` rules of which the port has NONE (`grep -c 'string_rewrite' -w
# tinybendygrad/renderer/tc_ptx.bend` is 0 -- MEASURED; the single hit is a comment at
# `tc_ptx.bend:272`). So:
#
#   * EVERY ROW BOTH LANES CAN PRODUCE IS COMPARED, and the value is the WHOLE answer in
#     its own canonical text with TAB and LF spelled `\t` and `\n` by `TP.esc`, the SAME
#     escaper the port already uses. Never a prefix, never a length, never a hash.
#   * THE MODULE IS ONE ROW PER FIXTURE, `<f>.mod`, AND IT IS A DECLARED DIVERGENCE.
#     The port answers `ABSENT:string_rewrite(23) not ported`. An oracle that answered
#     `""` there would AGREE with a port that answers `""`, which is the shape
#     `wgsl_render_census` called out as the reason refusals are LOUD.
#
# THE POPULATION IS BUILT BY RUNNING BOTH SIDES, NOT BY A REGEX OVER THIS FILE.
# `gates/ptx_render_census-gate.py` asserts the two row-NAME lists are EQUAL AND IN THE
# SAME ORDER, and separately re-derives the FIXTURE axis out of THIS file's text and out
# of `ptx_render_census_axis.bend` and compares those too. A regex over this file cannot
# see a row built by a recursion over a list, and every row here is one.
#
# THE FIXTURE AXIS IS GENERATED FROM CPYTHON'S OWN GRAPHS
# (`gates/ptx_render_census-gen.py`), so `op`, `dtype`, `addrspace`, `max_numel`, `arg`,
# the src indices, the CONST subscript and the CONST-of-CAST flag are READ, not typed.
# `ptx.bend`'s OWN twenty-five fixtures are a HAND transcription of graphs of the same
# shape, and the oracle that checked them (`.agents/slop/ptx-s3-oracle.py`) and the script
# that wrote their pins (`.agents/slop/ptx-s3-gen.py`) are BOTH DELETED -- so that
# transcription has had no instrument against it since. This axis does not repeat it.
#
# WHAT IS CONSUMED AND NOT COPIED. `P.wk_all`, `P.wal0`, `P.Wal.r`, `P.r_go`,
# `P.reg_block`, `P.Wal.nm`, `P.Wal.ref`, `P.pf.ty_of` and `P.fn_name` are `ptx.bend`'s
# OWN defs, called; `TP.types_of`/`TP.mem_types_of`/`TP.cast_types_of`/`TP.fmt`/`TP.esc`/
# `TP.px_pline` are `tc_ptx.bend`'s, and that is the SEAM -- a census that skipped the
# five helpers `ptx.bend` IMPORTS would be a census of a file nothing uses. `dt_of` is the
# only thing written here, and the gate asserts it against the oracle's own dtype axis.
#
# WHAT THIS CENSUS CANNOT SEE, NAMED RATHER THAN LEFT TO BE DISCOVERED:
#   * `string_rewrite`'s TWENTY-THREE rules -- the instructions. That is `<f>.mod`.
#   * `ptx_matcher`'s EIGHT graph REWRITES (ptx.py:40-57, MEASURED by
#     `len(ptx_matcher.patterns)`). They change the GRAPH before the walk, so no row here
#     can see them.
#   * `Ops.WMMA`, `Ops.IF`, `Ops.ENDIF`, `Ops.BACKEDGE` and the `Ops.RANGE` loop trio:
#     they need fragment register banks and a RangeDef, which this axis does not fabricate.
#   * `.maxntid` and the `.param` lines. `render_kernel` builds them from
#     `prod([d.vmax for d in local_dims])` and from `bufs`, and `Wk` carries NO `vmax` and
#     no slot -- so `f09b_launch` and `f13_param` have a row for the ENTRY NAME and none
#     for the launch bound, and that gap is in the fixture TYPE, not in the comparison.

import Base
import ./ptx_render_census_axis.bend as AX
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/renderer/ptx.bend as P
import ./../tinybendygrad/renderer/tc_ptx.bend as TP
import ./../tinybendygrad/renderer/tc.bend as T

# ===========================================================================
# THE ONE ROW PRINTER. A `do IO(Unit)` block takes BINDINGS, so every call below is
# `r : Unit <- pr(...)`. MEASURED: a bare `pr(...)` there is a parse error, and the
# error names the SECOND call rather than the first.
# ===========================================================================
def pr(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def nil() -> IO(Unit): IO.print("")

# ---- 1. `to_function_name`, reached by CPython through `KernelInfo.name` -----
# THE AXIS. The port's own thirteen, PLUS seven boundary characters its own constants
# sweep says were missing: `126`/`47`/`58` sit just OUTSIDE the letter and digit ranges
# and `48`/`95` are their LOW bounds. A compare written `or(ge(48), le(57))` -- "at least
# 48 OR at most 57" -- matches EVERY character and makes `to_function_name` the identity;
# `~`, `/`, `Z`, `_`, ` `, `0` and backtick are what separate that from the truth.
def fn_ax() -> List<&2, String>:
  ["test", "my kernel", "MyKernel", "a-b", "x$y.z", "  lead", "trail  ", "a b c", "a~b", "a/b",
   "a:b", "a0b", "a_b", "~", "/", "Z", "_", " ", "0", "`"]

def fn_go(+xs: List<&2, String>, +i: U32) -> IO(Unit):
  match xs:
    case Nil{}    : nil()
    case x <> +t :
      do IO<Unit>:
        r : Unit <- pr(String.concat(["tfn_", U32.show(i)]), P.fn_name(x))
        fn_go(t, U32.add(i, 1))
        return Unit{}

# ===========================================================================
# 2. THE THREE DTYPE TABLES -- the SEAM. `ptx.bend`'s `pf.ty_of` is
# `Bool.pick(String, String.is_empty(ty), P.types_of(dt), ty)`, so EVERY register name in
# EVERY row below ends in a string these three produce, and a register name is what a PTX
# assembler reads.
#
# `void`, `bfloat16`, `weakint`, `weakfloat` and the four fp8s are in `S.Dt` and in NO
# table. CPython answers `KeyError`; the port answers a STRING, and for five of the
# eighteen the string is `""`. That is the PTX form of the `amd_dsl` `U32.shln` finding and
# it is pinned row by row in the gate's DIVERGES -- see the FINDING block at the foot.
# ===========================================================================
def dt_of(+i: U32) -> S.Dt:
  match i:
    case 0:  S.void()
    case 1:  S.boolean()
    case 2:  S.int8()
    case 3:  S.uint8()
    case 4:  S.int16()
    case 5:  S.uint16()
    case 6:  S.int32()
    case 7:  S.uint32()
    case 8:  S.int64()
    case 9:  S.uint64()
    case 10: S.half()
    case 11: S.bfloat16()
    case 12: S.single()
    case 13: S.double()
    case 14: S.fp8e4m3()
    case 15: S.fp8e5m2()
    case 16: S.fp8e4m3fnuz()
    case _:  S.fp8e5m2fnuz()

def dts() -> List<&2, U32>: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]

def tabs_go(+xs: List<&2, U32>) -> IO(Unit):
  match xs:
    case Nil{}   : nil()
    case i <> +t:
      do IO<Unit>:
        a : Unit <- pr(String.concat(["tyo_", U32.show(i)]), P.pf.ty_of("", dt_of(i)))
        b : Unit <- pr(String.concat(["mto_", U32.show(i)]), TP.mem_types_of(dt_of(i)))
        c : Unit <- pr(String.concat(["cto_", U32.show(i)]), TP.cast_types_of(dt_of(i)))
        tabs_go(t)
        return Unit{}

# ===========================================================================
# 3. `fmt` -- ptx.py:164, a CLOSURE with no name to call. Its whole rule is
# `"\t" + line.replace(" ", TAB if len(first token) > 7 else TABTAB, 1)`, so the axis is
# ptx.py's OWN mnemonics and the interesting pairs straddle seven characters: `mov.b32` is
# 7 and gets two tabs, `selp.f32` is 8 and gets one. `$RAW` is the shape with NO SPACE
# AT ALL: it gets the leading TAB and there is no first space to replace. IT WAS ONCE
# THE `line[0] == "$"` EARLY RETURN -- upstream `96397341d` ("dead code cleanups [PR]
# (#18593)", 2026-10-03) DELETED that branch as dead code, so at the pin a `$` line is
# INDENTED like every other and this row is a COMPARED row, not a declared divergence.
# ===========================================================================
# EVERY ENTRY BUT ONE CARRIES A SPACE, and that is the correction: the first draft's axis
# was bare mnemonics, `mov.b32` and `add.f32` with no operands, so `line.replace(" ", ...)`
# had nothing to replace and `fmt`'s SEVEN-CHARACTER RULE NEVER FIRED. MEASURED: the port
# answered `\tmov.b32` and CPython answered `\tmov.b32` -- twenty-one agreeing rows that
# agreed on a branch neither of them had taken. `claims_hold()` caught it, because its
# expected value said TWO tabs. The pairs that straddle the boundary are `add.f32` (7, two
# tabs) against `selp.f32` (8, one tab) and `rem.u32` (7) against `setp.eq.s32` (10).
def fmt_ax() -> List<&2, String>:
  ["mov.b32 %d, %a;", "selp.f32 %d, %b, %c, %a;", "add.f32 %d, %a, %b;", "and.pred %d, %a, %b;",
   "or.pred %d, %a, %b;", "xor.pred %d, %a, %b;", "mad.lo.s64 %d, %a, %b, %c;",
   "mul.lo.s16 %d, %a, %b;", "div.s32 %d, %a, %b;", "rem.u32 %d, %a, %b;",
   "setp.eq.s32 %d, %a, %b;", "setp.neu.f32 %d, %a, %b;", "max.s32 %d, %a, %b;",
   "cvt.rzi.s32.s32 %d, %a;", "rcp.approx.f32 %d, %a;", "shl.b32 %d, %a, %b;",
   "shr.u32 %d, %a, %b;", "bar.sync\t0;", "$RAW", "fma.rn.f32 %d, %a, %b, %c;",
   "mma.sync.aligned.m8n8k4.row.col.f32.tf32.tf32.f32 {{{d0}, {d1}}}, {{{a0}, {a1}}}, {{{b0}, {b1}}}, {{{c0}, {c1}}};"]

def fmt_go(+xs: List<&2, String>, +i: U32) -> IO(Unit):
  match xs:
    case Nil{}    : nil()
    case x <> +t :
      do IO<Unit>:
        r : Unit <- pr(String.concat(["fmt_", U32.show(i)]), TP.esc(TP.fmt(x)))
        fmt_go(t, U32.add(i, 1))
        return Unit{}

# ===========================================================================
# 4. THE MODULE HEADER, the three fixed limits, the suffix and the barrier.
# `px_pline` is `tc_ptx.bend`'s OWN index into `kernel_prefix`, and `ptx.bend` CONSUMES
# index 3 for the `.entry` line below, so it is a seam row and not a neighbour's.
# `T.ushow` is `tc.bend`'s own `U32` list printer and `TC`s own gate already uses it on
# `px_gmax`, so it is consumed rather than written a third time.
# ===========================================================================
def head_rows() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- pr("kpf_0", TP.esc(TP.px_pline(0)))
    b : Unit <- pr("kpf_1", TP.esc(TP.px_pline(1)))
    c : Unit <- pr("kpf_2", TP.esc(TP.px_pline(2)))
    d : Unit <- pr("kpf_3", TP.esc(TP.px_pline(3)))
    e : Unit <- pr("gmax", T.ushow(TP.px_gmax()))
    f : Unit <- pr("lmax", T.ushow(TP.px_lmax()))
    g : Unit <- pr("smax", U32.show(TP.px_smax()))
    h : Unit <- pr("suffix", TP.px_suffix())
    i : Unit <- pr("barrier", TP.esc(TP.px_barrier()))
    return Unit{}

# ===========================================================================
# 5. THE WALK. `P.wk_all` IS ptx.bend's own fold, `P.r_go` its own row walker and
# `P.reg_block` its own `.reg` block. Nothing here re-derives a register name.
#
# THE MODULE ROW. THREE distinct, deterministic answers, all three PINNED, because one
# string for all three cases would say the same thing whether or not the port rendered:
#   `ABSENT:string_rewrite(23) not ported` -- CPython rendered and the port cannot
#   `PORT-REFUSED:<op>`                    -- BOTH refused (ptx.py:204's raise)
#   `PORT-ANSWERED`                         -- CPython REFUSED and the port did NOT.
# The third is the finding: a refusal CPython raises becomes a register the port
# allocates, and `PORT-ANSWERED` is the string that says so in one word.
# ===========================================================================
def entry_of(+w: P.Wal) -> String:
  String.concat([TP.px_pline(3), " ", P.Wal.nm(w), " ("])

def mod_of(+w: P.Wal, refuses: Bool) -> String:
  +r = P.Wal.ref(w)
  Bool.pick(String, String.is_empty(r),
    Bool.pick(String, refuses, "PORT-ANSWERED", "ABSENT:string_rewrite(23) not ported"),
    String.concat(["PORT-REFUSED:", r]))

# `+pre` AND `+xs` ARE BOTH NEEDED AND ONLY ONE OF THEM CAN BE BOUND: MEASURED, `pre` used
# twice wants `+` and then wants it again at the recursive call, which is legal because the
# recursive call is the LAST use -- the error "consumed more than once" is the checker
# being strict about a param, and binding a local copy is the shape that satisfies it.
# `TP.esc` IS APPLIED HERE AND NOT IN `P.r_go`: a `.reg` line carries REAL TABS, and an
# unescaped row is invisible to a diff that reads them as whitespace. MEASURED: with 26 of
# the `.reg0` rows and 25 of the `.reg1` rows diverging on the two characters `\t` versus
# a tab, which is a byte diff over 51 rows and says nothing about registers.
def numbered(+pre: String, +xs: List<&2, String>, +i: U32) -> IO(Unit):
  match xs:
    case Nil{}    : nil()
    case x <> +t  :
      do IO<Unit>:
        r : Unit <- pr(String.concat([pre, U32.show(i)]), TP.esc(x))
        numbered(pre, t, U32.add(i, 1))
        return Unit{}

# THE ROW INDEX IS THE STEP INDEX, AND `P.r_go` IS NOT THE RIGHT WALKER FOR IT.
# `P.r_go` SKIPS a step that allocated nothing -- that is what `r_go.put` returning `Nil{}`
# means -- so it RENUMBERS, and `f01_alu`'s three register rows come out `0,1,2` where
# CPython's own `self.r` keys them `1,3,4` (the CONSTs at steps 0 and 2 are skipped at
# ptx.py:187). MEASURED, and it is the `gr_10` trap in another costume: two lanes that agree
# on a LIST whose ELEMENTS are mislabelled agree perfectly. So this walks `P.Wal.r` -- which
# has one `Rg` per STEP, empties included, because that is what ptx.bend's `Wal.rput`
# guarantees -- and asks `ptx.bend`'s OWN `r_go.put` whether a step produced a row.
#
# `P.r_go.put` and `P.rgl.of` and `P.rg_at` are `ptx.bend`'s defs. Nothing here re-derives
# a register name; this only decides WHICH step each answer belongs to.
# `step_one` TAKES `r_go.put`'s ANSWER AS A PARAMETER because a Bend `match` may only
# scrutinise a parameter or a field, never a computed value -- MEASURED, `match
# P.r_go.put(...)` answers "a parameter or field scrutinee". `ptx.bend`'s OWN `r_go.put`
# still decides whether the step produced a row; this only hands its answer somewhere a
# `match` can look at it.
# ONE ROW PER STEP, `NONE` when the step allocated nothing -- the same population rule as
# the oracle's. `ptx.bend`'s own `r_go.put` decides whether a step produced a value; this
# only chooses the WORD for the empty case, and `NONE` is the word both sides spell.
def step_one(rr: List<&2, String>, +nm: String, +i: U32) -> IO(Unit):
  match rr:
    case Nil{}    :
      do IO<Unit>:
        a : Unit <- pr(String.concat([nm, ".r", U32.show(i)]), "NONE")
        return Unit{}
    case _ <> +t :
      do IO<Unit>:
        a : Unit <- pr(String.concat([nm, ".r", U32.show(i)]),
                       Maybe.default(&2, String, List.get(&2, String, rr, 0n), ""))
        return Unit{}

def step_go(+ss: List<&2, P.Wk>, +rs: List<&2, P.Rg>, +i: U32, +nm: String) -> IO(Unit):
  match ss:
    case Nil{}    : nil()
    case s <> +t  :
      do IO<Unit>:
        a : Unit <- step_one(P.r_go.put(P.rg_at.maybe(List.get(&2, P.Rg, rs, U32.to_nat(i))),
                                        i, s), nm, i)
        step_go(t, rs, U32.add(i, 1), nm)
        return Unit{}

# `walk_rows` TAKES THE `r` ROWS AND THE `.reg` BLOCK AS ARGUMENTS rather than the step
# list. MEASURED, and it is not a style choice: `ss` is needed twice -- once by
# `P.wk_all` (which takes it `+`) and once by `P.r_go` -- and a linear parameter cannot be
# consumed twice, so the second use has to happen HERE and the result handed down.
def walk_rows(+nm: String, +ss: List<&2, P.Wk>, +w: P.Wal, +rb: List<&2, String>,
              ent: String) -> IO(Unit):
  # (the REFUSAL SPLIT now lives in `one_at`, which is where the `match` can go first), and it dispatches on the ONE thing the census declares rather than
  # on a computed value -- `refuses` is a Bool PARAMETER, which is the only thing a Bend
  # `match` may scrutinise. MEASURED twice: a local statement BEFORE the `match` makes Bend
  # answer "`refuses` can't be matched in this position", and `Bool.pick` over two
  # `IO(Unit)` arms answers "an unfilled law is a dead claim" and names an arm that is
  # perfectly well defined.
  # THE `.r` ROWS ARE EMITTED FOR A REFUSAL AND THE `.reg`/`.entry` ROWS ARE NOT, and the
  # asymmetry is a FACT about `render` rather than a policy: ptx.py:209 assigns `r[u]`
  # BEFORE ptx.py:223 can raise, so a refusal at 223 leaves the register map complete, while
  # `.reg` and `.entry` live in the MODULE `render_kernel` builds and there is no module.
  # MEASURED: the first draft returned early on a refusal and threw away the rows that pin
  # ptx.py:209 -- which is exactly why `ptx_render_census-mutate.py`'s M1 moved zero of 515
  # rows and the census had no vector LOAD to move.
  do IO<Unit>:
    a : Unit <- step_go(ss, P.Wal.r(w), 0, nm)
    return Unit{}

def walk_regs(+nm: String, +rb: List<&2, String>, ent: String) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- pr(String.concat([nm, ".regn"]),
                   U32.show(U32.from_nat(List.length(&2, String, rb))))
    b : Unit <- numbered(String.concat([nm, ".reg"]), rb, 0)
    c : Unit <- pr(String.concat([nm, ".entry"]), ent)
    return Unit{}

def walk_regless() -> IO(Unit): nil()

# `ss` IS READ TWICE -- `P.wk_all` takes it `+` and `P.r_go` walks it -- so the fold is
# run on ONE read and `r_go` on ANOTHER. MEASURED: a plain `ss` parameter used at both
# answers "consumed more than once", because a `+` parameter CONSUMES the value it is
# given. `+ss2 = ss` MOVES rather than copies, so it does not help either; the axis def is
# a FUNCTION, and calling it twice is the only way to have two lists, which is also the
# honest statement: the two lanes read the SAME axis because the axis is a function of the
# fixture, not a stored value.
# ONE DISPATCH over the axis INDEX, so `one` never names an `ax` def and the index list
# lives in exactly one place. The `match` is on a PARAMETER, which is the only thing a
# Bend `match` may scrutinise.
def ax(+i: U32) -> List<&2, P.Wk>:
  match i:
    case 0:  AX.ax00()
    case 1:  AX.ax01()
    case 2:  AX.ax02()
    case 3:  AX.ax03()
    case 4:  AX.ax04()
    case 5:  AX.ax05()
    case 6:  AX.ax06()
    case 7:  AX.ax07()
    case 8:  AX.ax08()
    case 9:  AX.ax09()
    case 10: AX.ax10()
    case 11: AX.ax11()
    case 12: AX.ax12()
    case 13: AX.ax13()
    case 14: AX.ax14()
    case 15: AX.ax15()
    case 16: AX.ax16()
    case 17: AX.ax17()
    case 18: AX.ax18()
    case 19: AX.ax19()
    case 20: AX.ax20()
    case 21: AX.ax21()
    case 22: AX.ax22()
    case 23: AX.ax23()
    case 24: AX.ax24()
    case 25: AX.ax25()
    case 26: AX.ax26()
    case 27: AX.ax27()
    case 28: AX.ax28()
    case 29: AX.ax29()
    case 30: AX.ax30()
    case 31: AX.ax31()
    case 32: AX.ax32()
    case 33: AX.ax33()
    case _:  AX.ax34()

def one_at(+nm: String, +refuses: Bool, +i: U32) -> IO(Unit):
  +w = P.wk_all(ax(i), P.wal0())
  do IO<Unit>:
    a : Unit <- walk_rows(nm, ax(i), w, P.reg_block(w), entry_of(w))
    b : Unit <- Bool.pick(IO(Unit), refuses, walk_regless(), walk_regs(nm, P.reg_block(w),
                                                                     entry_of(w)))
    c : Unit <- pr(String.concat([nm, ".mod"]), mod_of(w, refuses))
    return Unit{}

def fixtures() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- one_at("f01_alu", False{}, 0)
    b : Unit <- one_at("f02_counter", False{}, 1)
    c : Unit <- one_at("f03_cast5", False{}, 2)
    d : Unit <- one_at("f04_end", False{}, 3)
    e : Unit <- one_at("f05_regbuf4", False{}, 4)
    f : Unit <- one_at("f06_regbuf1", False{}, 5)
    g : Unit <- one_at("f07_reuse", False{}, 6)
    h : Unit <- one_at("f08_refuse", True{}, 7)
    i : Unit <- one_at("f09_special", False{}, 8)
    j : Unit <- one_at("f09b_launch", False{}, 9)
    k : Unit <- one_at("f10_loads", False{}, 10)
    l : Unit <- one_at("f11_stack", False{}, 11)
    m : Unit <- one_at("f12_after", False{}, 12)
    n : Unit <- one_at("f13_param", False{}, 13)
    o : Unit <- one_at("f14_skips", False{}, 14)
    p : Unit <- one_at("f15_bidx", False{}, 15)
    q : Unit <- one_at("f16_bitcast", False{}, 16)
    r : Unit <- one_at("f17_u64", False{}, 17)
    s : Unit <- one_at("f19_mixed", False{}, 18)
    t : Unit <- one_at("f23_load1", False{}, 19)
    u : Unit <- one_at("f24_range", False{}, 20)
    v : Unit <- one_at("f25_rangevoid", False{}, 21)
    w : Unit <- one_at("f26_store", False{}, 22)
    x : Unit <- one_at("f27_loadbool", False{}, 23)
    y : Unit <- one_at("f28_name", False{}, 24)
    z : Unit <- one_at("f29_name2", False{}, 25)
    aa : Unit <- one_at("f30_noparam", False{}, 26)
    ab : Unit <- one_at("f31_weakint", True{}, 27)
    ac : Unit <- one_at("f32_weakfloat", True{}, 28)
    ad : Unit <- one_at("f33_bf16cast", True{}, 29)
    ae : Unit <- one_at("f34_boolalu", True{}, 30)
    af : Unit <- one_at("f35_loadvec", True{}, 31)
    ag : Unit <- one_at("f36_regstore", False{}, 32)
    ah : Unit <- one_at("f37_twobufs", False{}, 33)
    ai : Unit <- one_at("f38_regload", False{}, 34)
    return Unit{}

# ===========================================================================
# main: THE ROW SEQUENCE, in the oracle's order. A census whose row ORDER differs between
# lanes is a gate that compares POSITIONALLY, so the order is part of the claim and
# `ptx_render_census-gate.py` asserts it rather than trusting it.
#
# THE REFUSAL COLUMN IS THE CENSUS'S OWN DECLARATION and it is checked three times: the
# gate reads it out of THIS file, compares it to the generator's `# REFUSES` line in
# `ptx_render_census_axis.bend`, and compares it to the oracle's own `.mod=REFUSE:` rows.
# Three witnesses, one of which is CPython.
# ===========================================================================
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- fn_go(fn_ax(), 0)
    b : Unit <- tabs_go(dts())
    c : Unit <- fmt_go(fmt_ax(), 0)
    d : Unit <- head_rows()
    e : Unit <- fixtures()
    return Unit{}

# ===========================================================================
# FINDING 1 -- THE PTX FORM OF `amd_dsl`'s `Res{v: U32}` + `U32.shln`: A FIELD THAT IS
# SILENTLY EMPTIED WHERE CPYTHON REFUSES.
#
# `tc_ptx.bend`'s `types_pri` is a dispatch on `S.Dt.pri`, and its `case _` arm is `""`.
# CPython's `PTXRenderer.types` is a `dict[DType, str]` and a MISSING dtype is a
# `KeyError` at ptx.py:181. MEASURED, both sides: the port names TWENTY dtypes --
# `dtypes.all()` is SEVENTEEN and `void`, `weakint` and `weakfloat` are the other three --
# and CPython's `types` dict has TWELVE keys, so EIGHT dtypes raise. THE PORT EMPTIES SIX
# OF THE EIGHT -- `void`, `bfloat16` and the four fp8s -- and that is EIGHTEEN ROWS, three
# tables each. THE TWO IT DOES NOT EMPTY ARE `weakint` AND `weakfloat`, and they are the
# REACHABLE ones, which is why they are the first two rows:
#
#     weakint     port "s32"    mem "s32"  cast "s32"     CPython KeyError(weakint)
#     weakfloat   port "f32"    mem "f32"  cast "f32"     CPython KeyError(weakfloat)
#     void        port ""        mem ""     cast ""        CPython KeyError(void)
#     bfloat16    port ""        mem ""     cast ""        CPython KeyError(bfloat16)
#     fp8e4m3     port ""        mem ""     cast ""        CPython KeyError(fp8e4m3)
#
# THE EMPTIED FIELD IS THE SIX THAT ANSWER `""` -- `void`, `bfloat16` and the four fp8s --
# AND NOT weakint and weakfloat. MEASURED, both sides: `tc_ptx.bend`'s three tables
# DISPATCH `CWeakInt` and `CWeakFloat` BEFORE their `case _` arms, so `weakint` answers
# the DEFAULT INT's `"s32"` and `weakfloat` the DEFAULT FLOAT's `"f32"` -- REAL PTX
# types -- while the six that answer `""` answer it with an EMPTY TYPE where a real PTX
# type belongs: a register named `%alu__0` and a `.reg\t\t. %alu__<1>;`.
#
# AND IT IS REACHABLE, which is the part that makes it a defect and not a table curiosity.
# MEASURED: `UOp.range(4, 0)` DEFAULTS to `dtype=dtypes.weakint`, ptx.py:217 gives it
# prefix `ridx`, ptx.py:181 raises `KeyError: dtypes.weakint` -- and the port answers
# `%ridx_s32_0`. `UOp.const(3.0) + UOp.const(4.0)` is an ADD whose dtype is
# `dtypes.weakfloat` and which is NOT a CONST, so ptx.py:187 does not skip it, and
# ptx.py:181 raises `KeyError: dtypes.weakfloat` -- and the port answers `%alu_f32_0`.
# Four fixtures (`f31_weakint`, `f32_weakfloat`, `f33_bf16cast`, `f34_boolalu`) exist
# to pin this, and their `<f>.mod` rows are the port's `PORT-ANSWERED`.
#
# "A U32 SHIFT IS NOT AN ERROR, IT IS A SMALLER NUMBER" -- and an empty type field is not
# an error either, it is a KERNEL PTXAS REJECTS, emitted silently by a total function
# whose `case _` arm was written for the fp8 dtypes and now also catches bfloat16, and
# whose `CVoid` arm answers the same empty string for `void`.
#
# ===========================================================================
# FINDING 2 -- `ptx.py` ITSELF REFUSES FOUR SHAPES A REAL KERNEL HAS, AND NONE OF THEM
# IS A PORT DEFECT. They are here because a census that only prints what works reports a
# renderer as more capable than it is.
#
#   f31/f32/f33  `KeyError` from `self.types[...]` -- the table is twelve entries wide and
#                weakint, weakfloat and bfloat16 are not in it (above).
#   f34_boolalu  `KeyError` on `ctx.r[CONST]`. ptx.py:187 SKIPS a CONST without setting
#                `r[u]`, and ptx.py:92 reads `r[v]` for EVERY src of an ALU -- so an ALU
#                whose operand is a bare CONST raises `KeyError: UOp(Ops.CONST, arg=True,
#                src=())`. The bool arms of `asm_for_op` (`or`/`and`/`xor.pred`) are
#                therefore reachable only through a CAST of a CONST, never directly.
#   f08_refuse   ptx.py:204's own raise, and the ONE refusal the walk declares.
# ===========================================================================