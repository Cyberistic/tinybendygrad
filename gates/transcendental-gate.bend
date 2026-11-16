# gates/transcendental-gate.bend -- the gate driver for `tinybendygrad/codegen/decomp/transcendental.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/codegen/decomp/transcendental.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
def row(+nm: String, +v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def rows(+nm: String, +v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# A window is MANY rows and it prints itself, prefix and all, so `rows` would
# only add a stray `a_tag=` above the first node.
def win(+nm: String, +v: String) -> IO(Unit):
  IO.print(v)

# ONE TABLE, THREE KINDS OF ROW: `n_<tag>` and then one `e_<tag><i>` per entry.
# The `i` is IN the tag, so a rule added or removed early renumbers every later
# row -- which is the point: a table whose SIZE is right and whose CONTENTS are
# wrong still moves `e_`, and a table whose size is wrong moves `n_`.
#
# ONE SELF-CALL AND NO `IO` IN AN ARM. Printing an entry and then recursing needs
# a `do` block inside a `match` arm, and arm-printing plus a helper is MUTUAL
# RECURSION, which Bend refuses; so the rows are built as one String and printed
# once, exactly as `P.tx_win` does for a node window.
# the entry count is the Nat fuel and it is the first parameter, because Bend
# wants a decreasing self-call read left to right and `i` only ever goes up.
def tx_tab_go.e(+k: Nat, +nm: String, +t: O.PMEntrys, +i: U32) -> String:
  match k:
    case 0n: ""
    case 1n+p: String.concat(["\ne_", nm, U32.show(i), "=", P.tx_tab.row(t, i),
                              tx_tab_go.e(p, nm, t, U32.add(i, 1))])

# THE SEPARATOR LEADS, so the string has no trailing newline and `IO.print`'s own
# newline is the last one. A trailing one prints a blank line per table and four
# of those lines are a diff against the oracle for no reason at all.
def tx_tab_head.go(+nm: String, +t: O.PMEntrys, +n: U32) -> String:
  String.concat(["n_", nm, "=", U32.show(n), tx_tab_go.e(U32.to_nat(n), nm, t, 0)])

def tx_tab_head(+nm: String, +t: O.PMEntrys) -> String:
  tx_tab_head.go(nm, t, P.tx_tab.n(t))

def gate() -> IO(Unit):
  do IO<Unit>:
    row("mt_f16", P.mantissa_bits(S.half()))
    row("eb_f16", P.exponent_bias(S.half()))
    row("em_f16", P.exponent_mask(S.half()))
    row("mt_f32", P.mantissa_bits(S.single()))
    row("eb_f32", P.exponent_bias(S.single()))
    row("em_f32", P.exponent_mask(S.single()))
    row("mt_f64", P.mantissa_bits(S.double()))
    row("eb_f64", P.exponent_bias(S.double()))
    row("em_f64", P.exponent_mask(S.double()))
    row("n_rintk", P.tx_n(P.w_rintk()))
    win("a_rintk", P.tx_win("rintk", P.w_rintk()))
    row("n_pow2if", P.tx_n(P.w_pow2if()))
    win("a_pow2if", P.tx_win("pow2if", P.w_pow2if()))
    row("n_ilogb", P.tx_n(P.w_ilogb()))
    win("a_ilogb", P.tx_win("ilogb", P.w_ilogb()))
    row("n_ldexp3", P.tx_n(P.w_ldexp3()))
    win("a_ldexp3", P.tx_win("ldexp3", P.w_ldexp3()))
    row("n_ldexp2", P.tx_n(P.w_ldexp2()))
    win("a_ldexp2", P.tx_win("ldexp2", P.w_ldexp2()))
    row("n_frexp", P.tx_n(P.w_frexp()))
    win("a_frexp", P.tx_win("frexp", P.w_frexp()))
    row("n_cw", P.tx_n(P.w_cw()))
    win("a_cw", P.tx_win("cw", P.w_cw()))
    row("n_ph", P.tx_n(P.w_ph()))
    win("a_ph", P.tx_win("ph", P.w_ph()))
    row("n_sp", P.tx_n(P.w_sp()))
    win("a_sp", P.tx_win("sp", P.w_sp()))
    row("n_sps", P.tx_n(P.w_sps()))
    win("a_sps", P.tx_win("sps", P.w_sps()))
    row("n_spl", P.tx_n(P.w_spl()))
    win("a_spl", P.tx_win("spl", P.w_spl()))
    row("n_xsinf", P.tx_n(P.w_xsinf()))
    win("a_xsinf", P.tx_win("xsinf", P.w_xsinf()))
    row("n_xsin", P.tx_n(P.w_xsin()))
    win("a_xsin", P.tx_win("xsin", P.w_xsin()))
    row("n_xexp2", P.tx_n(P.w_xexp2()))
    win("a_xexp2", P.tx_win("xexp2", P.w_xexp2()))
    row("n_xlog2", P.tx_n(P.w_xlog2()))
    win("a_xlog2", P.tx_win("xlog2", P.w_xlog2()))
    row("n_xpow", P.tx_n(P.w_xpow()))
    win("a_xpow", P.tx_win("xpow", P.w_xpow()))
    # THE TABLE, for the FIVE (ops, force) PAIRS the oracle sweeps. `non` is
    # "every op except the three transcendentals, no force", `force` is the same
    # with force, `nosq` is "every op except SQRT", `empty` is no ops at all and
    # `all` is every op -- the last is the ONE THAT MUST BE EMPTY and is why the
    # table cannot be a constant.
    rows("sw30", P.tx_carg(P.w_xsin(), 157))
    rows("sw7", P.tx_carg(P.w_xsin7(), 157))
    IO.print(tx_tab_head("non", P.tx_tab(False{}, False{}, False{}, True{}, False{})))
    IO.print(tx_tab_head("force", P.tx_tab(False{}, False{}, False{}, True{}, True{})))
    IO.print(tx_tab_head("nosq", P.tx_tab(True{}, True{}, True{}, False{}, False{})))
    IO.print(tx_tab_head("empty", P.tx_tab(False{}, False{}, False{}, False{}, False{})))
    IO.print(tx_tab_head("all", P.tx_tab(True{}, True{}, True{}, True{}, False{})))

def main() -> IO(Unit):
  gate()

# THE MUTATION TABLE. MEASURED, one hand edit at a time, by
# `.agents/slop/tools/tx-mut.py` -- which re-checks the file, runs the
# interpreted lane, and diffs it against `.agents/slop/tx-arena.txt` keyed on
# `<tag>#<slot>`. A POSITIONAL diff reports every row after an insertion as moved,
# which is noise; a `<tag>`-only key collapses all 205 `a_xsin` rows into one.
# Every mutation below still says `checks`, so none of them is a compile-time
# mistake caught for free -- which is the point: the gate has to see them.
#
# | mutation | rows moved | what it catches |
# | --- | --- | --- |
# | `P.EXP232`'s second coefficient, last digit | `a_xexp2#32` and nothing else | a coefficient is ONE row, and only the windows that use that TABLE move. A coefficient table with a typo is invisible to every count row |
# | `P.mantissa_bits(float32)` 23 -> 24 | `a_frexp#10`, `a_ilogb#10`, `a_ldexp2#12`, `a_ldexp3#11`, `a_ph#10`, `a_pow2if#11`, `mt_f32`, ... (+4) | the `dtypes.finfo` TABLE, read by six different defs; `mt_f32` is the row that says the value itself moved |
# | `polyN`'s seed `0.0` -> `1.0` | `a_sp#10`, `a_sp#24`..`#26`, `a_spl#17`..`#31`, `a_sps#10`.., `a_xexp2#27`.., `a_xlog2#46`.., `a_xsin#159`.., ... (+74) and `n_sp`, `n_sps`, `n_xsin` | header note 6: the seed is a real `MUL(C(0.0), x)`. A port that starts the Horner at `c[0]` is indistinguishable from this one except in these rows |
# | `P._ifand`'s `.ne(0)` reads a float CONST instead of the int one | `a_spl#10`.., `a_sps#29`, `a_xsin#176`, `a_xsin#197`, ... (+31) | `_broadcasted` does NOT re-mint when both sides are already int. MINTING THE PAIR is not "safer", it is wrong |
# | `P.xsin`: build `cody_waite` BEFORE `payne_hanek` | `a_xsin#100`..`#205`, `a_xsinf`-unaffected, `n_xsin`, `sw30`, `sw7` (+176) | Python evaluates the reductions as STATEMENTS, so payne-hanek is interned first even though `P.sin_poly_small` reads the cody-waite values. Reading the source order swaps 105 nodes |
# | `P.xpow`: `base.ne(-inf)` reads `-inf` instead of `ret` | `a_xpow#31` and nothing else | `where(x, y)` builds the receiver, then `x`, then `y`; one row sees it and no COUNT row does, which is why `n_` rows are not enough on their own |
# | `P.tx_tab.sqrt` ignores `force` | `e_force6`, `n_force` | `force` is `TRANSCENDENTAL` and it is the ONLY difference between the `non` and `force` tables; `n_non` does not move |
# | the `name="x"` half of every pair loses its name | `e_empty1`, `e_empty3`, `e_empty5`, `e_force1`, `e_force3`, `e_force5`, `e_non1`, `e_non3`, `e_non5` | a rule table whose SIZE and SHAPE are right and whose `name=` is wrong. Only a per-entry row sees this |
# | `P.rintk`'s `d.const_like(-0.5)` -> `+0.5` | `a_rintk#11`, `a_cw#19`.., `a_xsinf#35`, `a_xsin#140`, ... (+187) and `n_rintk`, `n_cw`, `n_xexp2`, `n_xsin`, `n_xsinf`, `sw30`, `sw7` | the sign of the rounding bias, which is `round away from 0` and not `round half up`. Every expansion that rounds moves |
# | `P.ldexp2k`: `shr(e, 1)` -> `shr(e, 2)` | `a_ldexp2#10`..`#22`, `a_xexp2#49`.., ... (+37) and `n_ldexp2`, `n_xexp2` | header note 1: `shr` by a Python int is a `DIV` by `2y`, and `y` is 1 |
# | `payne_hanek`: `shl(p, 62)` -> `shl(p, 63)` | `a_ph#99`, `a_xsin#115` and nothing else | the `2**62` CONST is one node and one reader in each window; `n_ph` does not move because the node is still there |
# | `P.xpow`: `ret.const_like(1)` -> `2.0` | `a_xpow#38`, `a_xpow#39`, `a_xpow#40`, `n_xpow` | `x  0 = 1`, and the CONST is the last node of the window |
# | `P.xsin`'s `switch_over` hard-coded at 30.0 | `sw7` and nothing else | `switch_over` is a PARAMETER. This is the only mutation `sw30`/`sw7` exists to see, and it is why both rows are read at the SAME SLOT: the shape does not depend on the value |
#
# A row that ONE mutation moves is a LOCALISED row, and there are four of those:
# `a_xexp2#32`, `a_xpow#31`, `a_ph#99` and `sw7`. They are worth keeping for
# exactly that reason -- each one is the only witness for a fact that has no other
# witness in the gate.
#

# WHAT IS NOT DONE. Stated, not hidden.
#
# 1. the float16 and float64 windows are not gated. The whole gate is float32,
#    because the oracle's fixture is. `xsin`'s `switch_over` is the only
#    non-structural parameter with two gated values. All THREE of
#    `P.cody_waite_reduction`'s arms are WRITTEN -- `P.cw_quadrant.d64` subtracts
#    `qdh`, `P.cody_waite_reduction.reduce` takes `d64` AND `f16` as two separate
#    Bools, and `P.tx_cw16.chain` recurses into the float32 chain and casts back --
#    but the float16 and float64 arms have no row:
#      - `P.cody_waite_reduction`'s float64 arm, including `cw_quadrant.d64`'s
#        `d * m_1_pi - qdh` (header note 4's dead-`qdh` case is the float32 one,
#        not this), and `P.tx_cw64`'s six `PI_A..PI_D` terms.
#        `# TODO(p3) transcendental.py:126  P.cody_waite_reduction f64 arm`
#      - `P.cody_waite_reduction`'s float16 arm -- `_reduce_d` RECURSES into float32
#        and casts back (header note 2), so `P.tx_cw16.chain` is a real second
#        entry point into `P.tx_cw32`, and the quadrant is `short` so the final
#        `quadrant.cast(dtypes.i32)` does NOT elide.
#        `# TODO(p3) transcendental.py:135  P.cody_waite_reduction f16 arm`
#      - `P.payne_hanek_reduction`'s float16 arm, for the same reason plus the
#        `intermediate_dtype` CAST that float16 is the only dtype to need.
#        `# TODO(p3) transcendental.py:79  payne_hanek intermediate_dtype`
#      - the float64 CONSTANTS (`P.frexp`'s 64-bit masks, `_reduce_d`'s six
#        `PI_A..PI_D` terms, `P.EXP264`, `P.LOG264`, `P.SIN64`) are spelled as full
#        decimals that were CHECKED against `struct.pack('<f')` for the f32
#        windows, but the f64 windows are not gated and the f64 coefficient
#        literals are NOT independently verified.
#      - `P.exponent_bias`'s fp8_fnuz arm (`P.tx_is_fnuz`) is exercised only by the
#        table's `match_dtype` strings, not by a window.
# 2. `ops.bend`'s `eq_const.CFloat` uses `F32.is_eq`, which IEEE says is TRUE of
#    `+0.0` and `-0.0`, and tinygrad keeps them apart (MEASURED:
#    `UOp.const(-0.0) is UOp.const(0.0)` is False). `P.tx_cf_neg0` pushes the node
#    the way `intern.put` does, which is a WORKAROUND for a defect in a read-only
#    file, and it is correct only because `-0.0` is used ONCE here. REPORTED, NOT
#    FIXED: `ops.bend:1406`.
# 3. `P.xsin`'s `fast` arm is gated at `fast=True` (`n_xsinf`) but the `switch_over`
#    parameter is only read on the `fast=False` path, which is Python's own dead
#    arm -- `switch_over` is unused when `fast` is true. The port keeps the
#    parameter and does not model the deadness.
# 4. the table's `dtype=` conjuncts live in the rule body, not in `PMEntry`,
#    because `O.PMEntry` has no dtype field. `P.tx_tab.md` therefore DERIVES the
#    dtype string from the tag's parity and the entry's op rather than reading it
#    off the rule. That is decomp.bend's arrangement and this file follows it, but
#    it means a rule whose `dtype=` and whose `tag` disagree would still print the
#    right string -- the gate cannot see a rule body.
# 5. `PatternMatcher` itself is NOT ported. `get_transcendental_patterns` returns
#    a `Data` table of `O.PMEntry`, which is the shape ops.bend uses, but nothing
#    here runs `pm_scan` over it: the gate is about the table's CONTENT and the
#    EXPANSIONS' shapes, and `decomp.bend` owns the scan.
