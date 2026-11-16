# gates/linearizer-gate.bend -- the gate driver for `tinybendygrad/codegen/late/linearizer.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/codegen/late/linearizer.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/codegen/kernel.bend as KER
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("ix_len", P.lt_ix_len())
    b : Unit <- srow("ix", P.lt_ix())
    c : Unit <- row("po_param", P.lt_po_param())
    d : Unit <- row("po_bufl", P.lt_po_bufl())
    e : Unit <- row("po_bufg", P.lt_po_bufg())
    f : Unit <- row("po_load", P.lt_po_load())
    g : Unit <- row("po_store", P.lt_po_store())
    h : Unit <- row("po_range", P.lt_po_range())
    i : Unit <- row("po_end", P.lt_po_end())
    j : Unit <- row("po_backedge", P.lt_po_backedge())
    k : Unit <- row("po_add", P.lt_po_add())
    l : Unit <- row("rc_nil", P.lt_rc_nil())
    m : Unit <- row("rc_1", P.lt_rc_1())
    n : Unit <- row("rc_2", P.lt_rc_2())
    o : Unit <- row("rc_3", P.lt_rc_3())
    p : Unit <- row("rc_max", P.lt_rc_max())
    q : Unit <- row("rc_big", P.lt_rc_big())
    r : Unit <- srow("lin_srcs", P.lt_lin_srcs())
    s : Unit <- row("lin_n", P.lt_lin_n())
    t : Unit <- srow("lin_vm", P.lt_lin_vm())
    t2 : Unit <- srow("lin_edg", P.lt_lin_edg())
    u : Unit <- srow("lin_nkey", P.lt_lin_nkey())
    v : Unit <- srow("lin_ord", P.lt_srcs(F.Folded.ar(KER.K.fx(P.lt_fix())), P.lt_srt_idx()))
    w : Unit <- P.lt_rows("lin", P.linearize(F.Folded.ar(KER.K.fx(P.lt_fix())), P.lt_lst(), P.lt_vm_lst(), 19),
                        P.lt_srt(), P.lt_fix())
    x : Unit <- row("lin_ties", P.lt_lin_ties())
    y : Unit <- row("lin_exmix", P.lt_lin_exmix())
    p1 : Unit <- srow("linc_srcs", P.lt_linc_srcs())
    p2 : Unit <- row("linc_n", P.lt_linc_n())
    p3 : Unit <- srow("linc_vm", P.lt_linc_vm())
    p3b : Unit <- srow("linc_edg", P.lt_linc_edg())
    p4 : Unit <- srow("linc_nkey", P.lt_linc_nkey())
    p5 : Unit <- srow("linc_ord", P.lt_srcs(F.Folded.ar(KER.K.fx(P.lt_fix())), P.lt_srt_call_idx()))
    p6 : Unit <- P.lt_linc_rows()
    p7 : Unit <- row("linc_ties", P.lt_linc_ties())
    p8 : Unit <- row("linc_exmix", P.lt_linc_exmix())
    q1 : Unit <- srow("cfg_edges", P.cfg_edges_row(P.lt_ar(), P.lt_cfged()))
    q2 : Unit <- row("cfg_edges_n", P.cfg_edges_n(P.lt_cfged()))
    q3 : Unit <- srow("cfg_hits", P.cfg_hits(P.lt_ar(), P.lt_cfged()))
    q4 : Unit <- row("cfg_tbl_len", P.cfg_tbl_len())
    q5 : Unit <- srow("cfg_tbl_ops", P.cfg_tbl_ops())
    r1 : Unit <- srow("se_rngs", P.se_rngs_row(P.se_fix()))
    r2 : Unit <- srow("se_ops", P.se_ops_row(P.se_fix()))
    r3 : Unit <- row("se_len", P.se_len(P.se_se(P.se_fix()), 1))
    r4 : Unit <- row("se_nsrc", P.se_nsrc(P.se_se(P.se_fix())))
    r5 : Unit <- row("se_tbl_len", P.se_tbl_len())
    r6 : Unit <- srow("se_tbl_ops", P.se_tbl_ops())
    r7 : Unit <- row("se_fired", P.se_fired(P.se_ar(), P.se_e(P.se_fix())))
    # THE LAST ROW IS UNBOUND and IS the `do IO<Unit>` block's final
    # expression, so there is no trailing `IO.print("")` and the file ends
    # with the LAST ROW's newline -- what the oracle's `print("\n".join(out))`
    # does. A trailing empty line is a one-line diff a reader must notice.
    row("se_miss", P.se_fired(P.se_ar(), 7))
