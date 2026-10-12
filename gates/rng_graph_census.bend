# rng_graph_census.bend -- A GRAPH CENSUS over `tinybendygrad/schedule/rangeify.bend`'s ELEVEN
# rule tables: every (TABLE, NODE) pair over the port's own 66-node fixture, printed with the
# toposort OP SEQUENCE, the ARG and the TAG of whatever the rewrite ANSWERED.
#
#   .venv/bin/python gates/rng_graph_census-gate.py
#
# THE POPULATION IS DISCOVERED TWICE, ONCE PER LANE, AND THE GATE IS WHAT COMPARES THEM.
# A ROW is a (TABLE, NODE) pair. TABLE ranges over this file's eleven `*_table` defs --
# `rb nic nv aprt sk gs ct fb dg lb ab`, ELEVEN, discovered by `grep -c '^def [a-z]*_table'`
# (MEASURED 11) -- and NODE ranges over `R.g()`'s `G.ix`, whose length is 66 (MEASURED, and it
# is `rangeify.bend`'s own `lay` row, `t_lay` at :1984, which this lane CALLS rather than
# restates). 11 x 66 = 726 PAIRS. A pair is a ROW ON A LANE iff that lane's rewrite ANSWERS a
# node, so the two lanes DISCOVER THE ROW SET INDEPENDENTLY and the diff is over what they
# FOUND, not over a list somebody typed. THAT IS THE POINT: a rule that fires where CPython does
# not, or a graph that differs, is a difference in the ROW SET ITSELF and no pin can hide it.
#
# HOW A REWRITER IS CENSUSED, AND WHY IT IS A DISPATCH-TABLE CENSUS. `rangeify.bend` builds no
# graph of its own -- it REWRITES other people's -- so "this port's toposort op sequence" is the
# sequence of the node a rule ANSWERS, and the population that reaches it is the eleven
# `*_rewrite` defs, each the port of `PatternMatcher.rewrite` (ops.py:1613-1619) over one table.
# This is the shape the `cstyle` census reached CPython's dispatch TABLES through eight ported
# functions: here it is eleven functions over 66 nodes, and the tables fall out.
#
# CPython's lane is `gates/rng_graph_census-oracle.py`, and it calls the REAL
# `PatternMatcher.rewrite` on the REAL module-scope matchers `rangeify.py` builds and hands to
# `graph_rewrite` in `get_kernel_graph` (349-376) -- `pm_remove_bufferize`,
# `pm_no_indexing_calls`, `pm_no_views`, `pm_add_param_range_tags`, `split_kernels`,
# `pm_const_buffer_folding`, `pm_flatten_bufferize`, `to_define_global`, `pm_limit_bufs`,
# `pm_add_buffers`, `pm_gate_substitute`. Nothing on that lane reimplements a fold, a claim test
# or a rule body, and it hands each table the ctx its own body demands (`LocalAddBufferContext`,
# `LimitBufsContext`, an `itertools.count`), because an oracle that reimplemented the dispatch
# would agree with a port that is ITSELF wrong.
#
# `gs` AND `lb` ARE IN BOTH WALKS AND FIRE NOWHERE. That is a MEASUREMENT and not an exclusion.
# `gate_substitute` RAISES `BottomUpGate` (rangeify.py:44), which `graph_rewrite` catches at
# ops.py:1835 and reads as "no rewrite" -- which is exactly the port's `gs_0` answering
# `M.Hop{ar, 0}`; and `_limit_bufs` returns `None` at its second line whenever
# `MAX_KERNEL_BUFFERS` is unset (rangeify.py:177), while the port's `lb_0` is unported behind the
# mutable-`ctx` wall (rangeify.bend:2668). TWO TABLES OF ELEVEN CONTRIBUTING ZERO ROWS is a shape
# a reader should be told about rather than left to infer, and `gs_len=1` / `lb_len=1` in the
# port's OWN `main` say the TABLES are not empty -- the BODIES are what answer nothing. `gs` is
# also the one table with NO `gs_rewrite`: the rule raises rather than returning, so there is no
# `Hop` to write, and `gs_0` IS the rule.
#
# THE FIXTURE IS THE PORT'S OWN `g()` (rangeify.bend:1707-1862) -- ONE arena, 66 nodes, an affine
# chain, every intermediate bound -- and the oracle MIRRORS it index for index, so `R.G.n(g, n)`
# and CPython's `world()[n]` are the SAME node. That is the `ew_graph_census` `world()` shape. A
# fixture of one CONST would exercise nothing, so this one varies op (21 distinct), dtype (int32
# / half / bool / Invalid / weakint), src arity (0..4) and arg (`AParam` with and without a
# device, `ANone`, `ARange`, `AKernel`) across its 66 nodes. IT CARRIES SYMBOLIC DIMS, which
# rangeify cannot be asked about without: `RGD` is a RANGE at `AXIS_DEVICE` and `RGT` its
# `rtag(())` (rangeify.bend:1845-1846), and those two are what stop `renumber_range`'s "rebuild
# the AxisType" and "read the AxisType" from being the SAME FUNCTION over the rest of the fixture
# -- which is why mutation M12 of that file's own table moved nothing until they were added.
#
# `g()` IS REBUILT PER NODE AND NOT HOISTED, and the reason is AFFINITY, not cost. Every
# `*_rewrite` takes `+ar` and a rule that fires GROWS it, so a row must drive the arena it is
# handed; hoisting one `g()` across a walk puts row 7's answer in the arena row 6 left behind,
# which is the stale-arena self-loop bend2-constraints names. 66 hash-consed nodes and
# `Arena.empty()` are cheap, so the SAFE shape is also the cheap one. `g` is `Data`, so
# `R.g_ar(g)` and `R.G.n(g, n)` are TWO READS OF ONE arena and not two arenas -- which is the
# whole difference from the length-based merge `ew_graph_census` measured in `ew_join`.
#
# ONE LEGALITY REPAIR, ORACLE SIDE ONLY, AND IT IS A CPYTHON INVARIANT. `remove_bufferize`
# reads `buf.arg.removable` (rangeify.py:54) and `cleanup_dead_axes` reads `b.arg.removable`
# (:23), so a STAGE with `arg=None` CRASHES the real matcher -- MEASURED,
# `AttributeError: 'NoneType' object has no attribute 'removable'`. Every STAGE in a real
# rangeified graph carries `BufferizeOpts` (`indexing.py:57-60`), so the oracle gives them one.
# THE PORT CANNOT: `ops.bend`'s `Arg` has no `BufferizeOpts` arm, which is the wall
# `rangeify.bend:2683` records. `UOp` does NOT type-check `arg` against `op` (MEASURED, at
# rangeify.bend:1793), which is why the port's fixture builds `ANone` STAGEs without complaint.
# The asymmetry is a WALL and is DECLARED in the gate, not smoothed.
#
# THE SIGNATURE IS `Rng.sig` PLUS AN ARG AND A TAG, because `Rng.sig` (ops.bend:5897) prints
# NEITHER, and for THIS FILE they are most of the answer: `pm_add_param_range_tags` exists to set
# a TAG, `renumber_range` to rewrite a RANGE's arg, `pm_no_views` to hand back a node already in
# the arena. The vocabulary is the port's OWN `sg.ctor` / `sg.tag` (ops.bend:7540, 7534), reused
# rather than restated. THE `arg=` SUFFIX IS THE ANSWER TO THE `Rng.sig`-PREFIX TRAP AND IT IS
# NOT OPTIONAL HERE: `Rng.sig`'s src-op PREFIX makes `ab_45` (CALL carrying a real Kernel arg) and
# `ab_46` (the same CALL with `ANone`) byte-identical without it, and those two rows are the ONLY
# thing that separates "the arg survives `mp_replace`" from "the arg is hardcoded to ANone".
#
# WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `NOOP` IS THE BOTTOM (`Arena.bottom()`), so a node the
# arena does not hold READS as `Ops.NOOP`. This file's OWN tables answer `UOp(Ops.NOOP)`
# DELIBERATELY -- `rb_1` on a self-store (rangeify.py:133), `ab_8` on an invalid write (:268) --
# so a lane CANNOT test for the OP the way `tn_graph_census` does, and saying otherwise would be
# a claim about a shape this file does not have. What a lane CAN test is the node COUNT and the
# src-op sequence BESIDE a `NOOP`, and a `NOOP` where CPython has a real op is a diff. That is
# why this census prints the whole signature and not a verdict.
#
# ELEVEN FOLDS, DELIBERATELY NOT ONE GENERIC ONE, AND THE SHAPE IS FORCED. Bend has no
# first-class function, so `walk(0n, 66n, rb_row)` does not typecheck; and Bend refuses BOTH a
# forward reference and a mutual recursion, so a `go`/`one` pair does not typecheck either. What
# does is ONE SELF-RECURSIVE FOLD PER TABLE carrying a fuel and an accumulator, plus one
# self-recursive printer -- the shape `rangeify.bend` already uses for `noopf_go` (:265) and
# `nic.go` (:455), and its "ELEVEN TABLES, ELEVEN DISPATCHES, and deliberately no generic one"
# one level out.
#
# `M.Hop`'s ZERO IS `None` AND `UOp.is_none` IS `IS_ZERO`, so THE ARMS BELOW ARE NOT
# INTERCHANGEABLE. `hsig.of` answers the SIGNATURE on `False{}` and `"none"` on `True{}`,
# because `hsig` passes `UOp.is_none(hop_ix(h))` -- `True` means NO ANSWER. The first draft of
# this file had them the other way round and printed 42 rows reading `none`, which is what the
# INVERTED `M.hop_self` did -- a bug `movement.bend:69-75` now names as its own history and has
# fixed, so this file uses the def rather than a local copy. A CENSUS THAT PRINTS `none` WHERE IT
# MEANS A GRAPH IS NOT A CARVE-OUT, IT IS A LANE THAT MEASURED NOTHING, and it was caught only
# because the rows were READ rather than trusted to be non-empty.

import Base
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/movement.bend as M
import ./../tinybendygrad/schedule/rangeify.bend as R

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# THE ANSWER'S SIGNATURE, or the refusal token. `match` cannot scrutinise a computed value, so
# `UOp.is_none` gets its own `of` arm; and `h` is `+` because `hop_ix` and `hop_ar` are each read
# more than once.
def hsig.of(fired: Bool, +h: M.Hop) -> String:
  match fired:
    case True{}: "none"
    case False{}: String.concat([O.Rng.sig(M.hop_ar(h), M.hop_ix(h)),
                                 " arg=", O.sg.ctor(M.mp_arg(M.hop_ar(h), M.hop_ix(h))),
                                 " t=", O.sg.tag(M.mp_tag(M.hop_ar(h), M.hop_ix(h)))])

def hsig(+h: M.Hop) -> String:
  hsig.of(O.UOp.is_none(M.hop_ix(h)), h)

def nm(t: String, n: Nat) -> String: String.concat([t, "_", Nat.show(n)])

# THE ROW, WHATEVER IT IS. EVERY ONE OF THE 726 PAIRS IS EMITTED, refusals included, so the two
# lanes carry the SAME row count by construction and no exclusion list is needed to make the
# counts meet -- a lane that filtered its own refusals would let a disagreement about WHICH
# pairs fire hide inside the filter. `hsig`'s refusal token is the literal `none` and the
# oracle's is the same literal, so a refusal is a byte-identical row and a divergence is a line
# a reader can see. `put.of` is a pass-through and `put` passes `True{}`: it is here because the
# first draft FILTERED, and the polarity of that Bool (named for what it DETECTS rather than for
# what it DOES) was wrong twice before the filter went away.
def put.of(keep: Bool, name: String, +s: String) -> List<&2, String>:
  match keep:
    case True{}: [String.concat([name, "=", s])]
    case False{}: Nil{}

def put(name: String, +s: String) -> List<&2, String>:
  put.of(True{}, name, s)

# THE COUNT, read off the FIXTURE rather than typed: this IS `rangeify.bend`'s own `lay` row
# (`t_lay`, :1987), so this walk's fuel and the port's gate row cannot drift apart.
def lay() -> Nat: U32.to_nat(U32.from_nat(List.length(&2, U32, R.G.ix(R.g()))))

# --- rb ---------------------------------------------------------------------------------
# `g()` REBUILT PER NODE: `*_rewrite` takes `+ar`, a rule that fires GROWS it, and an answer read
# from a discarded arena is the stale-arena self-loop. `g` is `Data`, so `R.g_ar(g)` and
# `R.G.n(g, n)` are TWO READS OF ONE arena and not two arenas.
def rb_row(+n: Nat) -> List<&2, String>:
  +g = R.g()
  put(nm("rb", n), hsig(R.rb_rewrite(R.g_ar(g), R.G.n(g, n))))

def rb_go(fuel: Nat, +n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+f: rb_go(f, Nat.add(n, 1n), List.append(&2, String, acc, rb_row(n)))

# --- nic --------------------------------------------------------------------------------
def nic_row(+n: Nat) -> List<&2, String>:
  +g = R.g()
  put(nm("nic", n), hsig(R.nic_rewrite(R.g_ar(g), R.G.n(g, n))))

def nic_go(fuel: Nat, +n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+f: nic_go(f, Nat.add(n, 1n), List.append(&2, String, acc, nic_row(n)))

# --- nv ---------------------------------------------------------------------------------
def nv_row(+n: Nat) -> List<&2, String>:
  +g = R.g()
  put(nm("nv", n), hsig(R.nv_rewrite(R.g_ar(g), R.G.n(g, n))))

def nv_go(fuel: Nat, +n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+f: nv_go(f, Nat.add(n, 1n), List.append(&2, String, acc, nv_row(n)))

# --- aprt -------------------------------------------------------------------------------
def aprt_row(+n: Nat) -> List<&2, String>:
  +g = R.g()
  put(nm("aprt", n), hsig(R.aprt_rewrite(R.G.fx(g), R.g_ar(g), R.G.n(g, n))))

def aprt_go(fuel: Nat, +n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+f: aprt_go(f, Nat.add(n, 1n), List.append(&2, String, acc, aprt_row(n)))

# --- sk ---------------------------------------------------------------------------------
def sk_row(+n: Nat) -> List<&2, String>:
  +g = R.g()
  put(nm("sk", n), hsig(R.sk_rewrite(R.g_ar(g), R.G.n(g, n))))

def sk_go(fuel: Nat, +n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+f: sk_go(f, Nat.add(n, 1n), List.append(&2, String, acc, sk_row(n)))

# --- gs ---------------------------------------------------------------------------------
# `gs` HAS NO `gs_rewrite`, and that is the POINT of the row rather than a gap in it:
# `gate_substitute` RAISES `BottomUpGate` (rangeify.py:44) instead of returning, and a raise is
# not a value, so there is no `Hop` to write (rangeify.bend:854). `gs_0` IS the whole rule
# and it IS what the engine's `except BottomUpGate` (ops.py:1835) means, so driving `gs_0` is
# not reaching past a public entry point -- it is the entry point, one layer below a Hop that
# does not exist. It answers `M.Hop{ar, 0}` on every node, so it contributes zero rows.
def gs_row(+n: Nat) -> List<&2, String>:
  +g = R.g()
  put(nm("gs", n), hsig(R.gs_0(R.g_ar(g), R.G.n(g, n))))

def gs_go(fuel: Nat, +n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+f: gs_go(f, Nat.add(n, 1n), List.append(&2, String, acc, gs_row(n)))

# --- ct ---------------------------------------------------------------------------------
def ct_row(+n: Nat) -> List<&2, String>:
  +g = R.g()
  put(nm("ct", n), hsig(R.ct_rewrite(R.G.fx(g), R.g_ar(g), R.G.n(g, n))))

def ct_go(fuel: Nat, +n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+f: ct_go(f, Nat.add(n, 1n), List.append(&2, String, acc, ct_row(n)))

# --- fb ---------------------------------------------------------------------------------
def fb_row(+n: Nat) -> List<&2, String>:
  +g = R.g()
  put(nm("fb", n), hsig(R.fb_rewrite(R.G.fx(g), R.g_ar(g), R.G.n(g, n))))

def fb_go(fuel: Nat, +n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+f: fb_go(f, Nat.add(n, 1n), List.append(&2, String, acc, fb_row(n)))

# --- dg ---------------------------------------------------------------------------------
def dg_row(+n: Nat) -> List<&2, String>:
  +g = R.g()
  put(nm("dg", n), hsig(R.dg_rewrite(R.G.fx(g), R.g_ar(g), R.G.n(g, n))))

def dg_go(fuel: Nat, +n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+f: dg_go(f, Nat.add(n, 1n), List.append(&2, String, acc, dg_row(n)))

# --- lb ---------------------------------------------------------------------------------
# `lb` is `pm_limit_bufs` and `_limit_bufs` is UNPORTED (rangeify.bend:2668): its `visitor` is a
# closure that both reads and writes `ctx.buf_cache`, and `MAX_KERNEL_BUFFERS` is an env flag.
# `lb_0` answers `M.Hop{ar, 0}`, and CPython answers `None` on all 66 nodes too, so the two agree
# -- but they agree by REFUZAL, and that is worth saying rather than letting 66 `none`s read as
# agreement about a graph.
def lb_row(+n: Nat) -> List<&2, String>:
  +g = R.g()
  put(nm("lb", n), hsig(R.lb_rewrite(R.G.fx(g), R.g_ar(g), R.G.n(g, n))))

def lb_go(fuel: Nat, +n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+f: lb_go(f, Nat.add(n, 1n), List.append(&2, String, acc, lb_row(n)))

# --- ab ---------------------------------------------------------------------------------
def ab_row(+n: Nat) -> List<&2, String>:
  +g = R.g()
  put(nm("ab", n), hsig(R.ab_rewrite(R.G.fx(g), R.g_ar(g), R.G.n(g, n))))

def ab_go(fuel: Nat, +n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+f: ab_go(f, Nat.add(n, 1n), List.append(&2, String, acc, ab_row(n)))

def putl(xs: List<&2, String>) -> IO(Unit):
  match xs:
    case Nil{}: IO.print("")
    case x <> t:
      do IO<Unit>:
        a : Unit <- IO.print(x)
        b : Unit <- putl(t)
        return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- putl(rb_go(lay(), 0n, Nil{}))
    b : Unit <- putl(nic_go(lay(), 0n, Nil{}))
    c : Unit <- putl(nv_go(lay(), 0n, Nil{}))
    d : Unit <- putl(aprt_go(lay(), 0n, Nil{}))
    e : Unit <- putl(sk_go(lay(), 0n, Nil{}))
    f : Unit <- putl(gs_go(lay(), 0n, Nil{}))
    g : Unit <- putl(ct_go(lay(), 0n, Nil{}))
    h : Unit <- putl(fb_go(lay(), 0n, Nil{}))
    i : Unit <- putl(dg_go(lay(), 0n, Nil{}))
    j : Unit <- putl(lb_go(lay(), 0n, Nil{}))
    k : Unit <- putl(ab_go(lay(), 0n, Nil{}))
    return Unit{}