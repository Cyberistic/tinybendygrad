# decomp_graph_census.bend -- A GRAPH CENSUS over the graph-BUILDING half of
# `tinybendygrad/codegen/decomp/dtype.bend`: `l2i`, `unpack32` and `f2f`, each driven ONCE
# over the port's OWN 24-node word pool, printed as the DEEP CONE of whatever it answers.
#
#   .venv/bin/python gates/decomp_graph_census-gate.py
#
# THE POPULATION, AND WHY IT IS NOT THE `*_table` RULE. `gates/rng_graph_census.bend`'s row
# is a (TABLE, NODE) pair and its TABLE axis is `grep -c '^def [a-z]*_table'`. MEASURED:
# that count is **0** in all four files of `tinybendygrad/codegen/decomp/` -- `op.bend`,
# `dtype.bend`, `transcendental.bend` and `transcendental_f32.bend`. decomp is not a
# REWRITER, it is a graph BUILDER, so it has no dispatch tables to range over and the rng
# rule has nothing to discover. The substitute axis is the FIXTURE, and the fixture
# population is the port's OWN: `l2i.pick` (:2780, thirty-three arms), `dd_cmx.pick`
# (:2931, eight) and `f2f.pick` (:3053, seven). Thirty of `l2i.pick`'s arms read the word
# pool and three mint a CONST (`l2i.const`), and `dd_cmx.pick`'s eight print a scalar, so
# the population is 30 `l2i` + 3 `l2i.const` + 2 `unpack32` + 7 `f2f` = **42**. Both bend
# lanes emit every row including a refusal, so the counts agree BY CONSTRUCTION and no
# exclusion list is needed to make them meet.
#
# `l2i.const`'s THREE ARE HERE BECAUSE A POOL-FED RULE CANNOT SEE THEM. `l2i.pick`'s cases
# 28/29/30 mint the CONST at `xdt` and hand it in, so they read no word of `dd_wpool`, and
# "ARMS THAT READ THE WORD POOL" is exactly the kind of population rule that misses them --
# `amd_dsl_census`'s `VOP2_FIELDS` having no `src2` is the same defect. MEASURED, all three
# are EXACT MATCHES against the real dtype.py.
#
# THE PRINTER IS THE PORT'S OWN, AND IT IS DEEPER THAN `Rng.sig`. `Rng.sig` prints a toposort
# COUNT, the TOP op and a 3-op src PREFIX -- `gates/rng_graph_census.bend`'s own header
# records the trap, and `md_graph_census` answered it with an ` arg=` suffix. This lane uses
# `dd_cone`/`dd_esig` (:2355,:2358): the answer's ENTIRE cone in DFS pre-order, parent
# before child, src[0] first, each arena node ONCE. That is the answer to the brief's
# second blind spot -- a deep node swap cannot hide behind a 3-op prefix -- and CONST VALUES
# are in no node shape at all, which is why the census compares the cone and not the tree.
#
# ONE ARENA PER ROW. `l2i` GROWS the arena it is handed, so a row that read its answer out
# of a discarded arena is the stale-arena self-loop `bend2-constraints` names. `fixtures()`
# is rebuilt inside every row for that reason and for no other: 24 hash-consed PARAMs are
# cheap and the SAFE shape is also the cheap one.
#
# DEF ORDER IS THE BEND TRAP, not a style note: a def must be defined BEFORE its caller, so
# the printers come first and the fixtures come last.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/codegen/decomp/op.bend as P
import ./../tinybendygrad/codegen/decomp/dtype.bend as D

# ---------------------------------------------------------------- the printers

def dc_put(+nm: String, +s: String) -> List<&2, String>:
  [String.concat([nm, "=", s])]

# `OP/NSRC`, AND `OP/NSRC[TARGET]` WHEN THE NODE'S ARG IS A `Dt`. MEASURED ON THE BASE
# LANES AT `d1c1e3a`: 453 `CAST/1` and 33 `BITCAST/1` tokens on the port lane and 741 and 34
# on CPython's, and NOT ONE carried an argument -- `D.dd_sig1` (dtype.bend:2249) prints the
# op and the arity and stops, because a node's DTYPE is in no node shape. So the 282 casts
# `classes_hold` deletes were counted but never READ, a `bool->u32` promotion and a
# `f32->i32` narrowing were the same token, and `witnesses()` could not separate `lg1`'s
# `CAST(i32->i64)` at index 1 from its `CAST(weakint->i32)` at index 2. `dc_tok` is the same
# walk with `dd_sig1` replaced; `P.dc_opname` is the ONE place a bare op name is spelled
# (op.bend:1508), and `O.dt_name` the ONE place a dtype's name is (ops.bend:5956).
def dc_tok.plain(+a: O.Arena, +u: U32) -> String:
  String.concat([P.dc_opname(O.Arena.op(a, u)), "/", U32.show(O.Arena.nsrc(a, u))])

def dc_tok.cast(a: O.Arena, u: U32, d: S.Dt) -> String:
  String.concat([dc_tok.plain(a, u), "[", O.dt_name(d), "]"])

# `Arena.arg` IS A CALL and `match` neither scrutinises a computed value nor a local binder,
# so the ARG IS A PARAMETER of the arm-selecting def and the `match` heads that one. The
# same measured constraint that fixes `crp_graph_census.bend`'s `tok.arg` (driver:155-159).
def dc_tok(a: O.Arena, u: U32, g: O.Arg) -> String:
  match g:
    case O.ADt{d}: dc_tok.cast(a, u, d)
    case _:        dc_tok.plain(a, u)

def dc_tok.at(+a: O.Arena, +u: U32) -> String: dc_tok(a, u, O.Arena.arg(a, u))

# `D.dd_esig` with `D.dd_sig1` swapped for `dc_tok.at`. The CONE AND THE JOIN are the port's
# and are not re-derived: a census that walked its own cone would be comparing its walk.
def dc_esig(+ar: O.Arena, f: Nat, +xs: List<&2, U32>, +first: Bool, +acc: String) -> String:
  match f:
    case 0n: acc
    case 1n+q:
      match xs:
        case Nil{}: acc
        case u <> t:
          s = D.dd_join.add(first, acc, dc_tok.at(ar, u))
          dc_esig(ar, q, t, False{}, s)

# `l2i` answers `Maybe<W2>`; `W2.hi == 0` IS "ONE NODE" (dtype.bend:2698), which is how a
# one-word arm is rooted at `lo` alone -- four of dtype.py's eighteen arms answer one UOp.
def dc_roots(two: Bool, lo: U32, hi: U32) -> List<&2, U32>:
  match two:
    case True{}: [lo, hi]
    case False{}: [lo]

def dc_sig.put(+ar: O.Arena, two: Bool, +lo: U32, +hi: U32) -> String:
  +f = D.dd_fuel(ar)
  dc_esig(ar, f, D.dd_cone(f, ar, dc_roots(two, lo, hi)), True{}, "")

def dc_sig.w2(+ar: O.Arena, w: D.W2) -> String:
  match w:
    case D.W2{a, +lo, +hi}: dc_sig.put(a, U32.is_ne(hi, 0), lo, hi)

def dc_sig.of(m: Maybe<&2, D.W2>, +ar: O.Arena) -> String:
  match m:
    case Some{w}: dc_sig.w2(ar, w)
    case None{}: "refused:unported"

# `f2f` answers ONE node, so its cone is rooted at that node alone.
def dc_sig1(+ar: O.Arena, +u: U32) -> String:
  +f = D.dd_fuel(ar)
  dc_esig(ar, f, D.dd_cone(f, ar, [u]), True{}, "")

# ------------------------------------------------------------- the `l2i` fixtures

# ONE `l2i` ROW. `fixtures()` is rebuilt per row and `dd_ws` reads the pool off THAT arena.
def dc_l2i1(+nm: String, +op: O.Op, +dt: S.Dt, +xdt: S.Dt, base: Nat, nw: U32) -> List<&2, String>:
  +ga = D.fixtures()
  +ws = D.dd_ws(ga, base, nw)
  +r = D.l2i(D.Ga.ar(ga), op, dt, xdt, ws)
  dc_put(nm, dc_sig.of(r, D.Ga.ar(ga)))

# dtype.bend:2780-2834 `l2i.pick`, its pool-fed arms in the port's own order.
def dc_l2i_pick(+i: U32) -> List<&2, String>:
  match i:
    case 0: dc_l2i1("lg1", O.OpsNEG{}, S.int32(), S.uint32(), 9n, 2)
    case 1: dc_l2i1("lg2", O.OpsCAST{}, S.int64(), S.int32(), 4n, 2)
    case 2: dc_l2i1("lg3", O.OpsCAST{}, S.int64(), S.uint32(), 9n, 2)
    case 3: dc_l2i1("lg4", O.OpsCAST{}, S.int64(), S.boolean(), 14n, 2)
    case 4: dc_l2i1("lg5", O.OpsCAST{}, S.int64(), S.single(), 19n, 2)
    case 5: dc_l2i1("lg6", O.OpsCAST{}, S.uint64(), S.int32(), 4n, 2)
    case 6: dc_l2i1("lg7", O.OpsCAST{}, S.int32(), S.uint32(), 9n, 2)
    case 7: dc_l2i1("lg8", O.OpsBITCAST{}, S.int64(), S.uint32(), 9n, 2)
    case 8: dc_l2i1("lg9", O.OpsSHL{}, S.int32(), S.uint32(), 9n, 3)
    case 9: dc_l2i1("lga", O.OpsSHR{}, S.int32(), S.uint32(), 9n, 3)
    case 10: dc_l2i1("lgb", O.OpsSHR{}, S.uint32(), S.uint32(), 9n, 3)
    case 11: dc_l2i1("lgc", O.OpsADD{}, S.int32(), S.uint32(), 9n, 4)
    case 12: dc_l2i1("lgd", O.OpsSUB{}, S.int32(), S.uint32(), 9n, 4)
    case 13: dc_l2i1("lge", O.OpsMUL{}, S.int32(), S.uint32(), 9n, 4)
    case 14: dc_l2i1("lgf", O.OpsCMPLT{}, S.int32(), S.uint32(), 9n, 4)
    case 15: dc_l2i1("lgg", O.OpsCMPEQ{}, S.int32(), S.uint32(), 9n, 4)
    case 16: dc_l2i1("lgh", O.OpsCMPNE{}, S.int32(), S.uint32(), 9n, 4)
    case 17: dc_l2i1("lgi", O.OpsXOR{}, S.int32(), S.uint32(), 9n, 4)
    case 18: dc_l2i1("lgj", O.OpsOR{}, S.int32(), S.uint32(), 9n, 4)
    case 19: dc_l2i1("lgk", O.OpsAND{}, S.int32(), S.uint32(), 9n, 4)
    case 20: dc_l2i1("lgl", O.OpsWHERE{}, S.int32(), S.uint32(), 9n, 5)
    case 21: dc_l2i1("lgm", O.OpsMAX{}, S.int32(), S.uint32(), 9n, 4)
    case 22: dc_l2i1("lgn", O.OpsFLOORDIV{}, S.int32(), S.uint32(), 9n, 4)
    case 23: dc_l2i1("lgo", O.OpsCAST{}, S.int64(), S.uint32(), 9n, 1)
    case 24: dc_l2i1("lgq", O.OpsCDIV{}, S.int32(), S.uint32(), 9n, 4)
    case 25: dc_l2i1("lgr", O.OpsCMOD{}, S.int32(), S.uint32(), 9n, 4)
    case 26: dc_l2i1("lgs", O.OpsCDIV{}, S.uint32(), S.uint32(), 9n, 4)
    case 27: dc_l2i1("lgt", O.OpsCMOD{}, S.uint32(), S.uint32(), 9n, 4)
    case 28: dc_l2i1("lgu", O.OpsCAST{}, S.single(), S.single(), 19n, 2)
    case _: dc_l2i1("lgy", O.OpsCAST{}, S.int32(), S.int32(), 4n, 2)

def dc_l2i_go(fuel: Nat, +i: U32, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+p: dc_l2i_go(p, U32.add(i, 1), List.append(&2, String, acc, dc_l2i_pick(i)))

# --------------------------------------------------- `l2i.const`'s three arms

# `l2i.const` (dtype.bend:2773) MINTS ITS CONST OUTSIDE `l2i` -- at `xdt`, by `dd_const.int`
# (:333) -- and hands the word in, so these three arms read NO word of the pool. A population
# rule keyed on "ARMS THAT READ THE WORD POOL" therefore cannot see them, which is the same
# class as `amd_dsl_census`'s `VOP2_FIELDS` having no `src2`, and `l2i.pick`'s cases 28/29/30
# are exactly these three.
#
# THE `de` SHAPE AGAIN, AND FOR THE OPPOSITE REASON TO `uq`. Here the CONST is already at
# `xdt`, so `dd_const.int`'s CAST is NOT folded and the row carries `CAST/1[u32]` -- a target
# that equals its source, which `uq`'s does not. `lgw` is the row where CPython's own cast
# FOLDS (`l2i_dt[ulong]` is `uint`, so `uops[0].cast(l2i_dt[dt])` is the const itself,
# `mixin/dtype.py:36`) and `lgx` is the ORDER-SENSITIVE neighbour of `lgw`: same words, and
# a different cone order, so the pair is what distinguishes a walker that keeps order from one
# that keeps the multiset.
def dc_lc.put(+nm: String, +dt: S.Dt, +xdt: S.Dt, +c: O.Found) -> List<&2, String>:
  match c:
    case O.Found{+ar, +i}: dc_put(nm, dc_sig.of(D.l2i(ar, O.OpsCAST{}, dt, xdt, [i]), ar))

def dc_lc1(+nm: String, +v: U32, +dt: S.Dt, +xdt: S.Dt) -> List<&2, String>:
  +ga = D.fixtures()
  dc_lc.put(nm, dt, xdt, D.dd_const.int(D.Ga.ar(ga), H.i64_of_i32(v), xdt))

def dc_lc_pick(+i: U32) -> List<&2, String>:
  match i:
    case 0: dc_lc1("lgv", 0, S.int64(), S.uint32())
    case 1: dc_lc1("lgw", 0, S.uint64(), S.uint32())
    case _: dc_lc1("lgx", 1, S.uint64(), S.uint32())

def dc_lc_go(fuel: Nat, +i: U32, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+p: dc_lc_go(p, U32.add(i, 1), List.append(&2, String, acc, dc_lc_pick(i)))

# ------------------------------------------------------- `unpack32` and the `f2f`s

# `unpack32` (dtype.py:13) over the pool's u32 word at offset 9 -- dtype.bend:2850. `match`
# cannot scrutinise a LOCAL BINDER, so `W2` is destructured in its own def.
def dc_up.sig(w: D.W2) -> String:
  match w:
    case D.W2{+ar, +lo, +hi}: dc_sig.put(ar, U32.is_ne(hi, 0), lo, hi)

def dc_up() -> List<&2, String>:
  +ga = D.fixtures()
  +r = D.unpack32(D.Ga.ar(ga), D.Ga.pool(ga, 9n), S.uint32())
  dc_put("up", dc_up.sig(r))

# THE SECOND `unpack32` FIXTURE, AND IT IS THE ONE THAT MAKES A BITCAST'S `ADt` LOAD-BEARING.
# `up` reads the pool's `u32` word at offset 9 and passes `xdt = u32`, so
# `unpack32.bc`'s fold (`dtype.bend:591`, `O.eq_dt(xdt, S.uint32())`) FIRES and the row
# carries NO BITCAST AT ALL: MEASURED, `up` is `AND/2,PARAM/0,CONST/0,FLOORDIV/2,CONST/0` and
# `gates/decomp_graph_census-mutate.py` A13 -- which breaks ONLY that arm's `ADt` -- moved
# 0 of 38 rows and 0 under the bare printer. So the BITCAST `ops.py:13` builds was in no row,
# which is the same coverage hole `dtype.bend:2824-2830` records for `l2i_cast3.bitc`'s False
# arm and calls "live code with zero coverage".
#
# `uq` READS THE POOL'S `i32` WORD AT OFFSET 4 and passes `xdt = int32`, so the fold does not
# fire and the BITCAST is minted with `ADt{u32}` -- a target that differs from its SOURCE, so
# the token says WHICH bitcast it is and not merely that one happened. It is the `de` SHAPE in
# this file's own vocabulary: a REQUESTED dtype that is not the receiver's, so the fold test
# is false and the argument is read. CPython's `unpack32` takes no dtype and bitcasts
# unconditionally (ops.py:13), so the same two fixtures select the same two graphs.
def dc_up2() -> List<&2, String>:
  +ga = D.fixtures()
  +r = D.unpack32(D.Ga.ar(ga), D.Ga.pool(ga, 4n), S.int32())
  dc_put("uq", dc_up.sig(r))

# THE ANSWER'S OWN ARENA, NOT THE ONE HANDED IN. `f2f` GROWS the arena, so a cone read off
# `O.Found.ar(p)` -- the arena BEFORE the call -- indexes past its end and `Arena.node`
# answers `NOOP`, the BOTTOM. MEASURED: this file's first run printed `NOOP/0` for q1..q5
# and q7, six rows reading the bottom, for exactly this reason. That is defect class (a),
# the stale-arena self-loop, in the CENSUS and not in the port; the corrected templates are
# `mixin/op.bend`'s `mo_bin` and `tensor.bend`'s `tn_binop`, and `tn_binop` merges with
# `O.Arena.merge` -- a CONTENT merge -- because a LENGTH merge silently loses a node when two
# operands are equal-length siblings.
def dc_f2f_some(nm: String, +f: O.Found) -> List<&2, String>:
  dc_put(nm, dc_sig1(O.Found.ar(f), O.Found.i(f)))

def dc_f2f_put(nm: String, m: Maybe<&2, O.Found>) -> List<&2, String>:
  match m:
    case Some{f}: dc_f2f_some(nm, f)
    case None{}: dc_put(nm, "refused:unported")

def dc_f2f1(+nm: String, +fr: S.Dt, +to: S.Dt) -> List<&2, String>:
  +ga = D.fixtures()
  +p = D.dd_par(D.Ga.ar(ga), nm, D.f2f.udt(fr))
  +r = D.f2f(O.Found.ar(p), O.Found.i(p), fr, to, True{})
  dc_f2f_put(nm, r)

def dc_f2f_pick(+i: U32) -> List<&2, String>:
  match i:
    case 0: dc_f2f1("q1", S.fp8e4m3(), S.single())
    case 1: dc_f2f1("q2", S.single(), S.fp8e4m3())
    case 2: dc_f2f1("q3", S.single(), S.fp8e5m2())
    case 3: dc_f2f1("q4", S.fp8e4m3fnuz(), S.single())
    case 4: dc_f2f1("q5", S.single(), S.fp8e5m2fnuz())
    case 5: dc_f2f1("q6", S.half(), S.bfloat16())
    case _: dc_f2f1("q7", S.single(), S.double())

def dc_f2f_go(fuel: Nat, +i: U32, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+p: dc_f2f_go(p, U32.add(i, 1), List.append(&2, String, acc, dc_f2f_pick(i)))

# ----------------------------------------------------------------------- the fold

# `l2i.pick`'s pool-fed arms are the thirty `case`s above, `l2i.const`'s are the three in
# `dc_lc_pick`, and `f2f.pick`'s are the seven. All are counted where the header states them,
# so a reader checks them against `dtype.bend` rather than taking this file's word for it.
# `uq` is the second `unpack32` fixture and is counted in neither count above, because
# `unpack32` is ONE def the header counts ONCE and this file drives it TWICE -- on purpose,
# and `dc_up2` says why.
def L2I_N() -> Nat: 30n
def LC_N() -> Nat: 3n
def F2F_N() -> Nat: 7n

def dc_putl(xs: List<&2, String>) -> IO(Unit):
  match xs:
    case Nil{}: IO.print("")
    case x <> t:
      do IO<Unit>:
        a : Unit <- IO.print(x)
        b : Unit <- dc_putl(t)
        return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- dc_putl(dc_l2i_go(L2I_N(), 0, Nil{}))
    b : Unit <- dc_putl(dc_lc_go(LC_N(), 0, Nil{}))
    c : Unit <- dc_putl(dc_up())
    d : Unit <- dc_putl(dc_up2())
    e : Unit <- dc_putl(dc_f2f_go(F2F_N(), 0, Nil{}))
    return Unit{}