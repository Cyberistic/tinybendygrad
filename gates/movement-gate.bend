# gates/movement-gate.bend -- the gate driver for `tinybendygrad/uop/movement.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/uop/movement.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("mop_len", P.t_mop_len())
    b : Unit <- row("shrink1_ns", P.t_shrink1_ns())
    c : Unit <- row("shrink1_marg", P.t_shrink1_marg())
    d : Unit <- row("shrink2", P.t_shrink2())
    e : Unit <- row("shrink2_marg", P.t_shrink2_marg())
    f : Unit <- row("marg_n1", P.t_marg_n1())
    h : Unit <- row("marg_n2", P.t_marg_n2())
    i : Unit <- row("reshape_pick", P.t_reshape_pick())
    j : Unit <- row("reshape_noop", P.t_reshape_noop())
    k : Unit <- row("permute_merge", P.t_permute_merge())
    l : Unit <- row("permute_noop", P.t_permute_noop())
    m : Unit <- row("stack_idx", P.t_stack_idx())
    n : Unit <- row("const_idx2", P.t_const_idx2())
    o : Unit <- row("const_idx3", P.t_const_idx3())
    p : Unit <- row("const_idx5", P.t_const_idx5())
    q : Unit <- row("idx_idx", P.t_idx_idx())
    r : Unit <- row("idx_pick", P.t_idx_pick())
    s : Unit <- row("idx_shaped", P.t_idx_shaped())
    t : Unit <- row("idx_shaped_bad", P.t_idx_shaped_bad())
    u : Unit <- row("unclaimed", P.t_unclaimed())
    v : Unit <- row("rej_pair", P.t_rej_pair())
    w : Unit <- row("grow_new", P.t_grow_new())
    x : Unit <- row("grow_same", P.t_grow_same())
    y : Unit <- row("twice", P.t_twice())
    row("ret_self", P.t_ret_self())
    row("ret_new", P.t_ret_new())
