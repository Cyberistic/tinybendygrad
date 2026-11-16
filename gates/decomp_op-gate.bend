# gates/decomp_op-gate.bend -- the gate driver for `tinybendygrad/codegen/decomp/op.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/codegen/decomp/op.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
def row(+nm: String,+v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def rows(+nm: String,+v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# WHICH rule fired. `tag_*` is the row that makes first-wins observable and not
# just on/off: rules 3 and 4 both claim `TRUNCDIV(x, 2y)` and answer differently, and
# the `out_` row says which answer while the `tag_` row says it was the EARLIER
# rule. 0 means "nothing fired", which is unambiguous because the scan never
# reaches tag 0 without rule 0 firing.
def gate() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("nrules_s", P.t_nrules_s())
    b : Unit <- row("nrules_l", P.t_nrules_l())
    c : Unit <- row("nrules_l_noidiv", P.t_nrules_noidiv())
    d : Unit <- row("nrules_s_no3f", P.t_nrules_s3f())
    e : Unit <- row("nroots", P.nroots(P.fixtures()))
    g : Unit <- rows("tf_split", P.tf_split_str(P.Gate.ar(P.fixtures()), 13))
    h : Unit <- row("on_s9", P.t_tf_on())
    i : Unit <- rows("out_s9", P.t_tf_out())
    row("grown_s9", P.t_tf_grown())
    # the four SIMPLIFYING reject sets and the eighteen LATE ones
    j : Unit <- rows("rejs0", P.t_rejs(0))
    k : Unit <- rows("rejs1", P.t_rejs(1))
    l : Unit <- rows("rejs2", P.t_rejs(2))
    m : Unit <- rows("rejs3", P.t_rejs(3))
    n : Unit <- rows("rejl0", P.t_rej(0))
    o : Unit <- rows("rejl1", P.t_rej(1))
    p : Unit <- rows("rejl2", P.t_rej(2))
    q : Unit <- rows("rejl3", P.t_rej(3))
    r : Unit <- rows("rejl4", P.t_rej(4))
    s : Unit <- rows("rejl5", P.t_rej(5))
    t : Unit <- rows("rejl6", P.t_rej(6))
    u : Unit <- rows("rejl7", P.t_rej(7))
    v : Unit <- rows("rejl8", P.t_rej(8))
    w : Unit <- rows("rejl9", P.t_rej(9))
    x : Unit <- rows("rejl10", P.t_rej(10))
    y : Unit <- rows("rejl11", P.t_rej(11))
    z : Unit <- rows("rejl12", P.t_rej(12))
    a1 : Unit <- rows("rejl13", P.t_rej(13))
    b1 : Unit <- rows("rejl14", P.t_rej(14))
    c1 : Unit <- rows("rejl15", P.t_rej(15))
    d1 : Unit <- rows("rejl16", P.t_rej(16))
    e1 : Unit <- rows("rejl17", P.t_rej(17))
    # the SIMPLIFYING P.fixtures s0..s8
    f1 : Unit <- row("on_s0", P.t_on(0))
    g1 : Unit <- rows("out_s0", P.t_out(0))
    h1 : Unit <- rows("tag_s0", P.t_tg_off(0))
    i1 : Unit <- row("on_s1", P.t_on(1))
    j1 : Unit <- rows("out_s1", P.t_out(1))
    k1 : Unit <- rows("tag_s1", P.t_tg_off(1))
    l1 : Unit <- row("on_s2", P.t_on(2))
    m1 : Unit <- rows("out_s2", P.t_out(2))
    n1 : Unit <- rows("tag_s2", P.t_tg_off(2))
    o1 : Unit <- row("on_s3", P.t_on(3))
    p1 : Unit <- rows("out_s3", P.t_out(3))
    q1 : Unit <- rows("tag_s3", P.t_tg_off(3))
    r1 : Unit <- row("on_s4", P.t_on(4))
    s1 : Unit <- rows("out_s4", P.t_out(4))
    t1 : Unit <- rows("tag_s4", P.t_tg_off(4))
    u1 : Unit <- row("on_s5", P.t_on(5))
    v1 : Unit <- rows("out_s5", P.t_out(5))
    w1 : Unit <- rows("tag_s5", P.t_tg_off(5))
    x1 : Unit <- row("on_s6", P.t_on(6))
    y1 : Unit <- rows("out_s6", P.t_out(6))
    z1 : Unit <- rows("tag_s6", P.t_tg_off(6))
    a2 : Unit <- row("on_s7", P.t_on(7))
    b2 : Unit <- rows("out_s7", P.t_out(7))
    c2 : Unit <- rows("tag_s7", P.t_tg_off(7))
    d2 : Unit <- row("on_s8", P.t_on(8))
    rows("out_s8", P.t_out(8))
    # the LATE P.fixtures l0..l29
    row("on_l0", P.t_on(9))
    rows("out_l0", P.t_out(9))
    rows("tag_l0", P.t_tg_off(9))
    row("on_l1", P.t_on(10))
    rows("out_l1", P.t_out(10))
    rows("tag_l1", P.t_tg_off(10))
    row("on_l2", P.t_on(11))
    rows("out_l2", P.t_out(11))
    rows("tag_l2", P.t_tg_off(11))
    row("on_l3", P.t_on(12))
    rows("out_l3", P.t_out(12))
    rows("tag_l3", P.t_tg_off(12))
    row("on_l4", P.t_on(13))
    rows("out_l4", P.t_out(13))
    row("on_l5", P.t_on(14))
    rows("out_l5", P.t_out(14))
    row("on_l6", P.t_on(15))
    rows("out_l6", P.t_out(15))
    rows("tag_l6", P.t_tg_off(15))
    row("on_l7", P.t_on(16))
    rows("out_l7", P.t_out(16))
    rows("tag_l7", P.t_tg_off(16))
    row("on_l8", P.t_on(17))
    rows("out_l8", P.t_out(17))
    rows("tag_l8", P.t_tg_off(17))
    row("on_l9", P.t_on(18))
    rows("out_l9", P.t_out(18))
    rows("tag_l9", P.t_tg_off(18))
    row("on_l10", P.t_on(19))
    rows("out_l10", P.t_out(19))
    rows("tag_l10", P.t_tg_off(19))
    row("on_l11", P.t_on(20))
    rows("out_l11", P.t_out(20))
    rows("tag_l11", P.t_tg_off(20))
    row("on_l12", P.t_on(21))
    rows("out_l12", P.t_out(21))
    rows("tag_l12", P.t_tg_off(21))
    row("on_l13", P.t_on(22))
    rows("out_l13", P.t_out(22))
    rows("tag_l13", P.t_tg_off(22))
    row("on_l14", P.t_on(23))
    rows("out_l14", P.t_out(23))
    rows("tag_l14", P.t_tg_off(23))
    row("on_l15", P.t_on(24))
    rows("out_l15", P.t_out(24))
    rows("tag_l15", P.t_tg_off(24))
    row("on_l16", P.t_on(25))
    rows("out_l16", P.t_out(25))
    rows("tag_l16", P.t_tg_off(25))
    row("on_l17", P.t_on(26))
    rows("out_l17", P.t_out(26))
    row("on_l18", P.t_on(27))
    rows("out_l18", P.t_out(27))
    rows("tag_l18", P.t_tg_off(27))
    row("on_l19", P.t_on(28))
    rows("out_l19", P.t_out(28))
    rows("tag_l19", P.t_tg_off(28))
    row("on_l20", P.t_on(29))
    rows("out_l20", P.t_out(29))
    rows("tag_l20", P.t_tg_off(29))
    row("on_l21", P.t_on(30))
    rows("out_l21", P.t_out(30))
    rows("tag_l21", P.t_tg_off(30))
    row("on_l22", P.t_on(31))
    rows("out_l22", P.t_out(31))
    rows("tag_l22", P.t_tg_off(31))
    row("on_l23", P.t_on(32))
    rows("out_l23", P.t_out(32))
    rows("tag_l23", P.t_tg_off(32))
    row("on_l24", P.t_on(33))
    rows("out_l24", P.t_out(33))
    row("on_l25", P.t_on(34))
    rows("out_l25", P.t_out(34))
    rows("tag_l25", P.t_tg_off(34))
    row("on_l26", P.t_on(35))
    rows("out_l26", P.t_out(35))
    rows("tag_l26", P.t_tg_off(35))
    row("on_l27", P.t_on(36))
    rows("out_l27", P.t_out(36))
    rows("tag_l27", P.t_tg_off(36))
    row("on_l28", P.t_on(37))
    rows("out_l28", P.t_out(37))
    row("on_l29", P.t_on(38))
    rows("out_l29", P.t_out(38))
    # the GROWTH counts, which are the numeric discriminators
    row("grown_s0", P.t_grown(0))
    row("grown_s1", P.t_grown(1))
    row("grown_s7", P.t_grown(16))
    row("grown_l19", P.t_grown(28))
    row("grown_l27", P.t_grown(36))

def main() -> IO(Unit):
  P.gate()

# the mutation table and what is not done. Both are measured, and the second
# one is the honest half of the P.gate.
#
# THE MUTATIONS, by hand, one edit at a time, diffing the interpreted lane
# against `.agents/slop/dc-oracle.py`. A row only ONE mutation moves is a
# LOCALISED row; say so, because the table is not one-row-per-bug.
#
# | mutation | rows moved | what it catches |
# | --- | --- | --- |
# | `P.dc_s_fold.go` / `P.dc_l_fold.go`: first-wins -> last-wins | `tag_s0..s8`, `tag_l1`, `tag_l3`, `tag_l6..l8`, `tag_l11..l15`, `tag_l18..l23`, `tag_l25`, `tag_l27`, and every `out_` that follows one of those | `PatternMatcher.rewrite` returns the FIRST non-`None` (ops.py:1606). Keying the fold on the NEW verdict instead of the ACCUMULATOR is the classic wrong answer and `l7`/`l8`/`l9` are the P.fixtures that see it |
# | `P.dc_side.go`'s three arms -> the first two only | every `tag_` and `out_` of a commutative rule | header note 2: `UPat.alu` (ops.py:1533) is an `is_any` over BOTH orders for an op in `GroupOp.Commutative` |
# | `P.dc_cval` <- `P.dc_cval_s` on rules 1/6 (or drop `P.dc_cval_s`) | `on_l25`, `out_l25` | the commutative read: `MUL(C(4), i)` has the CONST on src0 and `P.dc_cval` reads src1 |
# | `P.dc_s2.pat`: `P.dc_is_pow2(P.dc_cval(...))` | `on_s5`, `out_s5` | op.py:64 read as a VALUE (`0`, and `1 -> 0` is falsy) rather than a MEMBERSHIP test |
# | `P.dc_s0.pat`: drop the `U32.is_ne(P.dc_cval(...), 0)` conjunct | `on_s2`, `out_s2` | the other half of the same pair: `x // 1` is NOT rewritten |
# | `P.dc_s0.pat` / `P.dc_s1`: drop the `dtypes.ints` conjunct | `on_s7`, `out_s7` | `dtypes.ints` is the four SIGNED widths and is NOT weakint, so `Cls.is_int` is the wrong test |
# | `P.dc_fd.gen` / `P.dc_fm.gen`: drop the `O.OpsAND{}` | `out_s1`, `out_s2`, `out_s4`, `out_s6` | op.py:56 ANDs `a.alu(TRUNCMOD,b).ne(0)` with `(a<0).ne(b<0)`; without the `&` the tree is a CMPNE of two CMPNEs |
# | `P.dc_sub` -> a real `SUB` node | `out_s1`, `out_s2`, `out_s4`, `out_s6`, `out_l10` | divergence B: `__sub__` is `self + (other * -1)` |
# | `P.dc_lnot`: re-insert the `cast(bool)` | `on_l0`, `out_l0`, `on_l18`, `out_l18` | `mixin/dtype.py:19` elides the CAST on a bool, and the port's `logical_not` must too or rule 13 cannot see its own pattern |
# | `P.dc_l8.leg` / `P.dc_l9.leg`: swap the two sides | `on_l12`, `out_l12`, `on_l13`, `out_l13` | `x < c` puts `x` on src0 and `c < x` puts it on src1; the two rules differ only there |
# | `P.dc_l15.c` -> `P.dc_l14.c` | `out_l21` | rule 15's addend is the non-SHL side and `P.dc_l14.c` keys on a MUL |
# | `P.dc_l12.same` -> `True{}` | `on_l16`, `out_l16` | THE IDENTITY CHECK. `l16` binds `x` once and `l17` binds it to two nodes; without the check the rule matches `l17` too and answers `y.eq(c1+1)` |
# | `P.dc_l12.val` -> `True{}` | `on_l16`, `out_l16` | `c1.val+1 == c2.val-1`; `l24` is the negative |
# | `P.dc_l0.x2` -> the second `src0` (re-read the `CAST`) | `on_l0`, `tag_l0`, `out_l0` | THE CAST-SKIP: `UPat.cast` (ops.py:1512) drops the node when the pattern already says `dtypes.bool` and `mixin/dtype.py:19` elides it on a bool, so the scrutinee of `logical_not` is ONE hop out. Two hops reads `src0` of a PARAM -- the bottom NOOP -- and `P.dc_dt` of that is not bool |
# | `P.dc_l0.x`/`P.dc_l0.y` -> the third `src0` | `out_l0` only | the same walk-off-the-end, and this is the row that SHOWS it: `out_l0` becomes `CMPNE(OR(NOOP,Pb),C(1))` while `on_l0` and `tag_l0` stay put, because the wrong node is only visible in the ANSWER |
# | `P.dc_l12.c1` -> the third `src0` | `on_l16`, `tag_l16`, `out_l16` | `c2` is two hops from the AND and `c1` is the same distance; the third `src0` read `src0` of a CONST, `P.dc_val` answered `None`, and `P.dc_ival` of that is 0 -- so the claim check compared `0 + 1 == c2.val - 1` |
# | `P.dc_l10.val` -> `P.dc_hit_m` on the `y*c` side | `on_l26`, `tag_l26`, `out_l26` | `UPat.var("y", ...)*UPat.cvar("c")` is an `is_any` over BOTH orders, so the `cvar` is not always `src1`; `P.dc_hit_s` reads `P.dc_const_side` and `l14` is the negative row (`out_l26` prints `CMPLT(MUL(Pj,MUL),Pi)`, both MULs in Python's own order) |
# | `P.dc_cval`/`P.dc_cminus1`: the log where the value is wanted | `out_s3` | `x & (c.val-1)` is `c.val - 1` and not `log2(c) - 1` |
# | `P.dc_sfx1.put`/`P.dc_sfx2.put`: two arms instead of three | `out_l3`, `out_l19`, `out_l20`, `out_l21` | a ONE-src node's `src1` is the arena's BOTTOM NOOP and printing it puts `NOOP` in every unary rewrite |
# | `P.dc_arity1`: `min(nsrc,3)` without the `- 1` | `out_l3`, `out_l19`, `out_l20`, `out_l21`, `out_s9` | the arity test itself |
# | `P.dc_entry_l` -> `P.dc_l_tab(True{})` | `rejl6..rejl17` | `disable_fast_idiv` renumbers the tags, so the reject rows must be read from the EIGHTEEN-rule table |
# | `P.dc_rejstr.first`: length 1 instead of 0 | every `rejs`/`rejl` row | the join's leading-comma bug |
# | `P.dc_tfg.pick`: always the `a` list | `grown_s9` only | `rotations[i % 2]` -- the list alternates, and the tree's SIZE is the only thing that sees it, because `out_s9` prints two levels of a 153-node tree |
# | `P.dc_tfr`: the OLD `xr[1]` on the right of the XOR | `grown_s9` | Python evaluates the whole right-hand tuple before the assignment |
# | `P.dc_tfg.step`: `i` instead of `i + 1` in the `ks` read | `grown_s9` | `ks[i%3]` and `ks[(i+1)%3]` are the two different entries |
# | `P.threefry2x32`: swap the two `P.dc_tf_half` calls | `P.tf_split`, `grown_s9` | `x.cast(u32)` is the LOW word and `x >> 32` the HIGH one |
#
# SEVEN ROWS DIFFER FROM PYTHON. Grouped by cause, and the causes are two:
#
# a. six rows are the `magicgu` wall, and they are supposed to differ:
#      on_l9 tag_l9 out_l9   Python: SHR(MUL(Pz,C(43)),C(7))
#      on_l10 tag_l10 out_l10 Python: ADD(Pz,MUL(MUL,C(-1)))
#    The port prints `none` because op.py:23 is P3. `P.dc_idiv` answers the three
#    guards that ARE ported -- `d <= 0` (`l28`), `x.vmin < 0` (`l29`) and
#    `vmax < d` (`l27`, which the port rewrites to `C(0)` and Python does too) --
#    and reports the fourth. This is `divandmod.bend`'s reading of Python's
#    `raise`: the condition is REPORTED and the ladder treats it as a skip.
#
# B. ONE ROW IS A PRINTER ARTEFACT and the port is RIGHT:
#      out_s9  bend OR(SHL(CAST,C(32)),CAST(ADD))  python OR(SHL(ADD,C(32)),ADD(ADD,XOR))
#    The oracle's `uncast` erases EVERY CAST whose arg differs from its src's
#    dtype, and `P.dc_tf_join`'s `cast(xr1, uint64)` is exactly such a CAST and is
#    NOT a promotion. The oracle's erasure rule is too coarse; the port's tree
#    is Python's tree. FIXING IT IS AN ORACLE FIX, not a port fix.
#

# the three rules that did not fire, now diagnosed. Nine rows, three readers,
# and ONE shape of mistake: a reader that steps one hop further than the tree is
# deep, or a predicate that reads a FIXED side where the op is commutative. Both
# land on the arena's bottom NOOP -- index 0, a node with no srcs and no dtype
# -- and both are invisible until a reader has to NAME a node, because every
# predicate before them still says TRUE. Each was bisected with a scratch probe
# printing the rule's own conjuncts one at a time; the decisive reading is
# named in each paragraph and the rows each fix moves are in the mutation table.
# Two of the three fixes are a `src0` DELETED and one is a reader swapped for the
# commutative one -- which is why the "which side is the CONST" machinery that
# the contradiction pointed at (`P.dc_cside`, `P.dc_const_side`, `P.dc_pick_side`) was
# right all along and had exactly one caller that did not use it.
#
#   rule 0  (op.py:85-86)  `P.dc_l0.x2` read a `CAST` that is in NEITHER the
#     pattern nor the tree. `UPat.cast` (ops.py:1512) returns `self` when the
#     pattern already says `dtypes.bool`, and `mixin/dtype.py:19` elides it on a
#     bool `x`, so `!x` is `CMPNE(x, C(True))` and the scrutinee is ONE hop.
#     Reading two hops gave `src0` of a PARAM -- the bottom NOOP -- so
#     `P.dc_dt(fx, noop, 2)` was False and `P.dc_l0.pat` was False. The same extra
#     hop was in `P.dc_l0.x`/`P.dc_l0.y`, and it is visible on its own: restoring it
#     leaves `on_l0` at 1 and prints `CMPNE(OR(NOOP,Pb),C(1))`. A reader that
#     walks off the end of a tree is the whole failure mode.
#   rule 12 (op.py:114-115)  `P.dc_l12.c1` had a THIRD `src0` where its sibling
#     `P.dc_l12.c2` has two. Both CONSTs are two steps from the AND, so the third
#     `src0` read `src0` of a CONST -- again the bottom NOOP -- `P.dc_val` of it
#     is `None`, `P.dc_ival` of `None` is 0, and `P.dc_l12.val` compared
#     `0 + 1 == c2.val - 1`, which is false. `P.dc_l12.pat` was TRUE throughout:
#     the rule was refused by its CLAIM CHECK, not its shape, which is why the
#     shape was never the suspect.
#   rule 10 (op.py:112)  `P.dc_l10.val`'s `y*c` conjunct was `P.dc_hit_m`, which
#     reads `src1`. `UPat.var("y", ...)*UPat.cvar("c")` is an `is_any` over both
#     orders, so `l26` (`C(3) * y`, CONST on src0) has no CONST on src1 and the
#     rule was refused. `P.dc_hit_s` reads `P.dc_const_side` and answers both sides.
#     THE CONTRADICTION THAT PINNED IT was `l1`/`l25` (rule 1, CONST either
#     side) firing through `P.dc_cval_s` and `l14`/`l26` (rule 10, CONST either
#     side) not: `P.dc_cside` and `P.dc_pick_side` were never wrong, only the one
#     rule that did not USE them. `l25` and `l26` are still the commutativity
#     rows from header note 2, and both now answer.
#
# WHAT NEXT, in the order the walls fall.
#   1. `i64_mul` / `i64_div` / `i64_mod` / `i64_shl` and an UNSIGNED 64-bit
#      compare in `helpers.bend` -- the `magicgu` block's five items. Nothing in
#      this file changes when they land: that block is already the only caller.
#   2. `UOp._min_max` (ops.py:1104) -- it does NOT bite here (see `P.dc_vmin`), and
#      finding that out was worth the three lines it took.
#   3. `Renderer.supported_dtypes()` (renderer/__init__.py:85) -- op.py:32, and
#      there is no `renderer` in the port at all.
#
# CLOSED. Item 4 was the three unfired rules; they are diagnosed and fixed above,
# and `P.nroots`-addressed rows `l0`/`l16`/`l26` now answer what Python answers.
# The lesson worth carrying to the next unit: a predicate chain that ends on a
# NODE READ is only as deep as the tree, and reading one hop too far lands on
# the bottom NOOP rather than on an error -- so the conjunct that refuses a
# fixture is the LAST one, not the first, and `out_*` printing a NOOP is the
# only honest witness.
