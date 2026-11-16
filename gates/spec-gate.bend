# gates/spec-gate.bend -- the gate driver for `tinybendygrad/uop/spec.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/uop/spec.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("sh_len", P.t_sh_len())
    b : Unit <- row("te_len", P.t_te_len())
    c : Unit <- row("pr_len", P.t_pr_len())
    d : Unit <- row("hq_len", P.t_hq_len())
    e : Unit <- row("fu_len", P.t_fu_len())
    f : Unit <- row("kg_len", P.t_kg_len())
    g : Unit <- row("tag_const", P.t_tag_const())
    h : Unit <- row("tag_rej", P.t_tag_rej())
    i : Unit <- row("sink_ok", P.t_sink_ok())
    j : Unit <- row("noop_ok", P.t_noop_ok())
    k : Unit <- row("noop_kg", P.t_noop_kg())
    l : Unit <- row("const_ok", P.t_const_ok())
    m : Unit <- row("stack_dt", P.t_stack_dt())
    n : Unit <- row("shl_wins", P.t_shl_wins())
    o : Unit <- row("shl_ok", P.t_shl_ok())
    p : Unit <- row("cf_arg_ok", P.t_cf_arg_ok())
    q : Unit <- row("cf_arg_str", P.t_cf_arg_str())
    r : Unit <- row("cf_arg_after", P.t_cf_arg_after())
    r2 : Unit <- row("cf_arg_noop", P.t_cf_arg_noop())
    r3 : Unit <- row("backedge_ok", P.t_backedge_ok())
    s : Unit <- row("prog4_ok", P.t_prog4_ok())
    t : Unit <- row("hcq_plain", P.t_hcq_plain())
    u : Unit <- row("hcq_after", P.t_hcq_after())
    row("multidev_ok", P.t_multidev_ok())
    row("multidev_bad", P.t_multidev_bad())
