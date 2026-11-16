# gates/kernel-gate.bend -- the gate driver for `tinybendygrad/codegen/kernel.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/codegen/kernel.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# THE FIXTURE IS INTERNED, NOT COUNTED, so a dedup cannot shift a row silently. The
# first version of these rows anchored each one at a literal list position, and one
# `UOp.new` deduplicated the fixture down by one -- so `k_ins` read a LINEAR's SINK
# and answered 0, and `k_al_store` read a STORE's SOURCE and answered NOOP. Both
# looked like rule bugs and neither was: a row that cannot see its own fixture is
# worse than no row.
#
# `k_ops` prints EVERY node's op in order, in ONE row, so a shift is visible rather
# than inferred. `k_pos` is the list length and `k_pos_same` that it equals
# `Arena.next` -- both counts, precisely so a dedup shows up as a disagreement
# rather than as a plausible-looking number.

# `case 0n:` is a PREFIX match (constraint 9) so the walk ends on it, and the
# termination is the LIST not a fuel: `n` is the remaining length of `P.K.ix`.
# THE WALK IS OVER THE LIST, so the list IS the fuel -- no `Nat` and no `U32`/`Nat`
# mixing, and `List.length` never appears in a position type. `i` is the head's
# POSITION and `rest` the tail, and `P.K.at` takes a `Nat`.
# NO COUNTER. The first version threaded an `i` that INCREASED, which the decrease
# check reads left to right and refuses -- so it cannot be a fuel, and the list is
# the fuel. The op names come off `P.kn_op` in list order, which is all this row is.
def k_ops.go(ids: List<&2, U32>, +ar: O.Arena) -> String:
  match ids:
    case Nil{}   : ""
    case v <> t  : String.concat([O.Ops.name.of(P.kn_op(ar, v)), " ", k_ops.go(t, ar)])

def k_ops() -> String:
  +kx = P.kn_fixture()
  k_ops.go(P.K.ix(kx), F.Folded.ar(P.K.fx(kx)))

def k_pos.ar(+kx: P.K) -> U32:
  O.Arena.next(F.Folded.ar(P.K.fx(kx)))

def k_pos() -> U32:
  U32.from_nat(List.length(&2, U32, P.K.ix(P.kn_fixture())))

# WHICH ENTRY IS THE STALE ONE. `k_dup` is the first position whose node is not the
# one the interning order expects: the fixture's ix list is built from `Found.i`
# values, so a dedup makes a later entry REPEAT an earlier index and every position
# from there on reads a node that is one slot behind its name. That is the whole of
# `pos_same=0`.
# which entry is the stale one. `k_dup` is the first position whose node repeats
# the one before it: the ix list is built from `Found.i` values, so a dedup makes a
# later entry REPEAT an earlier index and every position from there on names a node
# that is not the one its comment claims. `at` is a `U32`, not a `Nat`, because the
# only thing built from it is the row's own value and `U32.add` keeps the fuel in one
# type.
def k_dup.at(at: U32) -> U32:
  at

def k_dup.hit(same: Bool, v: U32, at: U32, rest: U32) -> U32:
  match same:
    case True{} : v
    case False{}: rest

def k_dup.go(ids: List<&2, U32>, +prev: U32, +at: U32) -> U32:
  match ids:
    case Nil{}   : 0
    case +v <> t : k_dup.hit(U32.is_eq(v, prev), v, at, k_dup.go(t, v, U32.add(at, 1)))

# THE WHOLE ix LIST, as a string, because `dup` only finds an ADJACENT repeat and a
# dedup three entries apart shifts everything after it without repeating anything
# next to itself. This row is what makes the shift visible.
def k_ix.go(ids: List<&2, U32>) -> String:
  match ids:
    case Nil{}   : ""
    case +v <> t: String.concat([U32.show(v), " ", k_ix.go(t)])

def k_ix() -> String:
  k_ix.go(P.K.ix(P.kn_fixture()))

def k_dup() -> U32:
  +kx = P.kn_fixture()
  k_dup.go(P.K.ix(kx), 0, 0)

def k_pos_same() -> U32:
  +kx = P.kn_fixture()
  P.k2u(U32.is_eq(k_pos(), k_pos.ar(kx)))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("np_len", P.k_np_len())
    b : Unit <- row("cfa_len", P.k_cfa_len())
    c : Unit <- row("al_len", P.k_al_len())
    d : Unit <- row("ib_len", P.k_ib_len())
    e : Unit <- row("ab_len", P.k_ab_len())
    f : Unit <- row("tp_len", P.k_tp_len())
    h : Unit <- row("np_fresh", P.k_np_fresh())
    i : Unit <- row("np_slot", P.k_np_slot())
    j : Unit <- row("np_next", P.k_np_next())
    k : Unit <- row("np_set", P.k_np_set())
    l : Unit <- row("np_twice", P.k_np_twice())
    m : Unit <- row("rm", P.k_rm())
    n : Unit <- row("rm_unroll", P.k_rm_unroll())
    o : Unit <- row("rm_loop", P.k_rm_loop())
    p : Unit <- row("bitcast", P.k_bitcast())
    q : Unit <- row("alu_sqrt", P.k_alu_sqrt())
    r : Unit <- row("alu_sin", P.k_alu_sin())
    s : Unit <- row("alu_add", P.k_alu_add())
    s1 : Unit <- row("alu_recip", P.k_alu_recip())
    t : Unit <- row("ab_grow", P.k_ab_grow())
    u : Unit <- row("ab_nsrc", P.k_ab_nsrc())
    v : Unit <- row("ab_miss", P.k_ab_miss())
    w : Unit <- row("stage_pr1", P.k_stage_pr1())
    x : Unit <- row("stage_pr2", P.k_stage_pr2())
    y : Unit <- row("stage_pr3", P.k_stage_pr3())
    z : Unit <- row("stage_pr4", P.k_stage_pr4())
    c2 : Unit <- row("cfg", P.k_cfg())
    d2 : Unit <- row("cfg_ctx", P.k_cfg_ctx())
    f2 : Unit <- row("lw_miss_nsrc", P.k_lw_miss_nsrc())
    h2 : Unit <- row("lw_find", P.k_lw_find())
    i2 : Unit <- row("lw_hit", P.k_lw_hit())
    j2 : Unit <- row("lw_sub_1", P.k_lw_sub_1())
    a2 : Unit <- row("pos", k_pos())
    a3 : Unit <- row("dup", k_dup())
    a4 : Unit <- row("pos_same", k_pos_same())
    a6 : Unit <- srow("ix", k_ix())
    a5 : Unit <- srow("ops", k_ops())
    srow("ab", P.k_ab())
