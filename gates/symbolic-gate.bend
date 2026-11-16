# gates/symbolic-gate.bend -- the gate driver for `tinybendygrad/uop/symbolic.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/uop/symbolic.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/uop/render.bend as R
import ./../tinybendygrad/dtype.bend as D
import ./../tinybendygrad/uop/weak.bend as W
import ./../tinybendygrad/uop/movement.bend as M
import ./../tinybendygrad/codegen/decomp/transcendental.bend as T
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def fz.gate() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("lay", P.t_lay())
    b : Unit <- row("len_sym", P.t_len_sym())
    c : Unit <- row("len_rm", P.t_len_rm())
    d : Unit <- row("total_sym", P.t_total())
    e : Unit <- row("skip", P.t_skip())
    f : Unit <- row("rej", P.t_rej())
    g : Unit <- row("alu", P.t_alu())
    h : Unit <- row("alu_rule", P.t_alu_rule())
    i : Unit <- row("alu_i32", P.t_alu_i32())
    j : Unit <- row("alu_big", P.t_alu_big())
    k : Unit <- row("alu_f32", P.t_alu_f32())
    m : Unit <- row("fdiv", P.t_fdiv())
    n : Unit <- row("fdiv_i", P.t_fdiv_i())
    o : Unit <- row("cdiv_i", P.t_cdiv_i())
    row("max_i", P.t_max_i())
    p : Unit <- row("cdiv_neg", P.t_cdiv_neg())
    q : Unit <- row("inval", P.t_inval())
    r : Unit <- row("inval_st", P.t_inval_st())
    s : Unit <- row("inval_n", P.t_inval_n())
    u : Unit <- row("selfadd", P.t_selfadd())
    v : Unit <- row("rebind", P.t_rebind())
    w : Unit <- row("rebind0", P.t_rebind0())
    y : Unit <- row("sink", P.t_sink())
    z : Unit <- row("rm_where", P.t_rm_where())
    row("rm_stack", P.t_rm_stack())
    row("xorb", P.t_xorb())
    row("xorb0", P.t_xorb0())
    row("bcast", P.t_bcast())
    row("sinkgrp", P.t_sinkgrp())
    row("sinkgrp0", P.t_sinkgrp0())
    row("promo", P.t_promo())
    row("modb", P.t_modb())
    row("modb0", P.t_modb0())
    row("ne0", P.t_ne0())
    row("ne1", P.t_ne1())
    row("ne2", P.t_ne2())
    row("ne0r", P.t_ne0r())
    row("trunc", P.t_trunc())
    row("trunc0", P.t_trunc0())
    row("shr", P.t_shr())
    row("shr0", P.t_shr0())
    row("fdivm", P.t_fdivm())
    row("fdivm0", P.t_fdivm0())
    row("promo_c", P.t_promo_c())
    row("promo_c0", P.t_promo_c0())
    row("tflo", P.t_tflo())
    row("tfhi", P.t_tfhi())
    row("tfhi_cast", P.t_tfhi_cast())
    row("recip3", P.t_recip3())
    row("recip3x", P.t_recip3x())
    row("recipc", P.t_recipc())
    row("recipc0", P.t_recipc0())
    row("ints_n", P.t_ints_n())
    row("intish_n", P.t_intish_n())
    row("intweak_n", P.t_intweak_n())
    row("bin3f_n", P.t_bin3f_n())
    row("len_dec", P.t_len_dec())
    row("len_dec_rm", P.t_len_dec_rm())
    row("ig87_src2", P.t_ig_src2())

# THE FUZZ DRIVER. `main` with NO argument is the gate above, byte for byte; with
# ONE argument it reads that case file, builds the arena out of the s-expr the case
# format IS, runs `P.sym` and `P.pm_remove_invalid` over the root, and prints ONE
# canonical line. The case format and the canonical form are the SAME s-expr, so the
# oracle and the driver can both print `sh(u)` and diff.
#
# THE FORMAT, and the leaves are the whole vocabulary:
#   (add c7 c0)             an ALU over two weakint CONSTs
#   (cast:int c7)           a CAST naming its dtype after a colon
#   (xor (xor c5 c7) c7)    a name bound twice, which is the rebind check
#   c7 c0 n7 bt bf bad      a CONST: non-negative, negative, bool true, bool
#                           false, and `Invalid`
#   x xb xf P.xi              a PARAM (`UOp.variable`) at weakint, bool, weakfloat
#                           and int32
# Anything the port cannot state is NOT in the vocabulary, and the exclusions are
# in the harness rather than discovered: no float CONST (`F32.bits` has no
# inverse, so a canonical float spelling is not expressible), no CONST outside
# int32 (`P.exec_alu`'s integer lane is int32, and its value is an I64), and no
# op behind `vmin`/`vmax`/`const_factor`/`tuplize`/`gcd`/`ranges`, all of which
# are `TODO(p3)` in the block above.
#
# why the scan is one DEF with a mode: a token scan that dispatches on the class of
# the character it is looking at cannot be two mutually recursive defs. It is one
# def, `m` selects "at a boundary" from "inside a word", `wm` says WHICH word, and
# every edge spends a Nat of fuel.


# THE DRIVER'S OWN ENTRY. The port's `fz.gate()` is a LANE -- it is defined and
# nothing in the port calls it, because the port is a LIBRARY and its rows are
# the census of the symbolic tables.
def main() -> IO(Unit):
  do IO<Unit>:
    fz.gate()
