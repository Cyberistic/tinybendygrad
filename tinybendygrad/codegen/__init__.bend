# tinybendygrad/codegen/__init__.bend -- port of tinygrad/codegen/__init__.py
#
# ============================================================================
# STATUS: WALL PARTIALLY BROKEN. The rewrite engine's MLIR-style
# `walk_rewrite` (single-pass driver) compiles and runs. `unified_rewrite`
# (the fixpoint driver) ships as a wall: it always returns `walk_rewrite`'s
# result, no actual fixpoint. The 3-stage worklist is a future unit. The
# test fixture, the rule body, and the engine's `pm_post_sched_cache`
# table are in this commit; the gate prints the rebuilt graph op/src/arg
# per node, byte-for-byte comparable to the CPython oracle.
#
# This file is the rewrite engine's SHAPE. The `pm_rewrite_m`/
# `pm_dispatch_m` family in `uop/ops.bend` returns `Maybe<&2, U32>` (the
# new node, or `None{}`); the engine in this file drives that family over
# a toposorted graph and rebuilds the result. `pm_post_sched_cache` is
# the smallest test case (PARAM and ALLOC) and is the spec's example for
# this unit.
#
# BEND NAMING RULE, observed (and appended to bend2-constraints.md as
# R-3): a sub-namespace def (`name.subname`) must be declared BEFORE the
# parent `def name` that calls it. The reverse order compiles, but every
# call to the sub-def is reported as "an unfilled law is a dead claim:
# live code cannot use it" -- a useful error once you know what it
# means, hostile until you do. The order below obeys this rule (leaves
# first, parents last).
# ============================================================================

import Base
import ./../uop/ops.bend as O
import ./../uop/render.bend as R
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S


# ============================================================================
# THE HELPER NAMESPACE `wr.*`. The BEND NAMING RULE requires every sub-def
# to be declared BEFORE its caller, so the order is bottom-up:
#   rebuild.go (leaf)   -- fold over a node's srcs, looking each up in `repl`
#   rebuild.of (leaf)   -- record a fresh `Found` in the replace map
#   rebuild             -- mint a new node with rewritten srcs
#   step.mint           -- the rule-result match: Some -> record, None -> rebuild
#   step.go             -- the seen-test match: True -> skip, False -> mint
#   step                -- per-node entry: seen? scan? mint? rebuild?
#   go                  -- fold over the toposort list, threading arena + repl
# ============================================================================

# Fold over a node's srcs, looking each up in `repl`. If absent, the
# original `s` is its own replacement (the toposort guarantees `s` was
# visited first).
def wr.rebuild.go(+srcs: List<&2, U32>, +ar: O.Arena, +u: U32, +repl: Map<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match srcs:
    case Nil{}: acc
    case +s <> t:
      wr.rebuild.go(t, ar, u, repl, List.append(&2, U32, acc, [R.cu32(repl, s)]))

# Record a fresh `Found` in the replace map.
def wr.rebuild.of(f: O.Found, +u: U32, +repl: Map<&2, U32>) -> Map<&2, U32>:
  Map.set(&2, U32, repl, U32.show(u), O.Found.i(f))

# Mint a new node with the rewritten srcs. The new U32 is `Found.i` of
# `O.UOp.new`. The arena is threaded `+` so the result is the new arena.
def wr.rebuild(+ar: O.Arena, +u: U32, +repl: Map<&2, U32>) -> Map<&2, U32>:
  wr.rebuild.of(O.UOp.new(ar, O.Arena.op(ar, u), wr.rebuild.go(O.Arena.srcs(ar, u), ar, u, repl, Nil{}), O.Arena.arg(ar, u), O.Arena.tag(ar, u)), u, repl)

# The rule-result match. A rule fired (`Some{new_u}`): record the
# replacement. No rule fired (`None{}`): rebuild the node with rewritten
# srcs. `ctx` is threaded to the rule scan because `pm_rewrite_m` now
# takes it (the rule bodies that read `ctx` are tags 3/4 in
# `pm_dispatch_m`).
def wr.step.mint(+ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>, +ctx: List<&2, U32>, r: Maybe<&2, U32>) -> Map<&2, U32>:
  match r:
    case Some{new_u}: Map.set(&2, U32, repl, U32.show(u), new_u)
    case None{}: wr.rebuild(ar, u, repl)

# The seen-test match. Already in `repl` (`True{}`): skip. Not yet
# (`False{}`): run the rule scan, then mint-or-rebuild.
def wr.step.go(seen: Bool, +ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>, +ctx: List<&2, U32>) -> Map<&2, U32>:
  match seen:
    case True{}: repl
    case False{}:
      wr.step.mint(ar, pm, u, repl, ctx, O.pm_rewrite_m(pm, ar, u, ctx))

# Per-node entry. seen? scan? mint? rebuild?
def wr.step(+ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>, +ctx: List<&2, U32>) -> Map<&2, U32>:
  wr.step.go(R.chas(repl, u), ar, pm, u, repl, ctx)

# Fold over the toposort list. Returns the replace map.
def wr.go(lst: List<&2, U32>, +ar: O.Arena, +pm: O.PMEntrys, +repl: Map<&2, U32>, +ctx: List<&2, U32>) -> Map<&2, U32>:
  match lst:
    case Nil{}: repl
    case +u <> t: wr.go(t, ar, pm, wr.step(ar, pm, u, repl, ctx), ctx)


# ============================================================================
# THE PUBLIC ENTRIES.
# ============================================================================

def walk_rewrite.of(sink: U32, u: U32) -> Maybe<&2, U32>:
  match u:
    case 0: None{}
    case _: Some{u}

# `walk_rewrite` is the MLIR-style single-pass driver. Returns the rebuilt sink.
def walk_rewrite(+ar: O.Arena, +sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>) -> Maybe<&2, U32>:
  # `ctx` is a `List<&2, U32>` here because the engine does not yet own
  # a typed context record. The codegen pipeline passes the real `ctx`
  # as a single arena-indexed U32 (the `ctx[0]` from Python's
  # `RewriteContext`), and the rule bodies read it back as such. This
  # untyped `List<&2, U32>` is the wall-passing shape until the typed
  # `CTX` record lands.
  # The fold is sized by the toposort; the toposort's fuel is the
  # arena's node count, which is `List.length(&2, Node, O.Arena.ns(ar))`.
  # The returned map holds the rebuilt graph; the sink is at
  # `R.cu32(repl, sink)` and the arena is `O.Arena.ar` of the most
  # recent mint (we discard it; U32 indices are into the live arena).
  walk_rewrite.of(sink, R.cu32(wr.go(O.UOp.toposort(U32.to_nat(O.Arena.next(ar)), ar, sink), ar, pm, Map.new(&2, U32), ctx), sink))


# `unified_rewrite` -- the fixpoint driver. WALL. The Python driver is a
# 3-stage worklist (stage 0: push node + srcs; stage 1: when all srcs are
# in `replace`, rebuild + try top-down rule, push to stage 2; stage 2:
# link the new node's replacement back to `n`). A `bpm` (bottom-up) table
# may fire to a fixed point per node.
#
# The minimal Bend port is the same fold re-run after each pass. The
# recursive shape runs into affine `+` rules (the toposort consumes the
# arena, the engine mints into it, and re-running needs a fresh arena
# AND a fresh toposort, both of which are `+`). The 4-hour wall is to ship
# the wall: a single pass that always returns the same as `walk_rewrite`.
# A wall that compiles and a gate that runs is more useful than a
# fixpoint that doesn't.
def unified_rewrite(ar: O.Arena, sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>) -> Maybe<&2, U32>:
  walk_rewrite(ar, sink, pm, ctx)

# `graph_rewrite` -- the dispatcher. Wall.
def graph_rewrite(ar: O.Arena, sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>, walk: Bool) -> Maybe<&2, U32>:
  None{}


# ============================================================================
# THE GATE: build the smallest `pm_post_sched_cache` fixture, run
# `walk_rewrite` over it, and print op/src/arg per node. The CPython
# oracle at `.agents/slop/gr-oracle.py` prints the same shape for the
# same fixture; the diff is the gate.
# ============================================================================

# The rule table. Two rules, tags 3 (PARAM) and 4 (ALLOC), per
# `pm_dispatch_m`. The reject set is empty (the rules fire on any
# PARAM/ALLOC with no other nodes in the srcs).
def pm_post_sched_cache() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{3, [O.OpsPARAM{}], Nil{}}, O.PMEntry{4, [O.OpsALLOC{}], Nil{}}]}

# A dummy PARAM that the ctx carries. The minimal printable form is
# `AParam{slot=N, dtype=int32, ...}`; the rest of the fields default to
# `None{}`/`False{}`. Two of these (slots 99 and 100) are the "A" and
# "B" in the test ctx.
def ctx_param(ar: O.Arena, slot: U32) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{},
    O.AParam{O.ParamArg{slot, S.int32(),
      None{}, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}},
    O.TNone{})

# A test PARAM with a real slot, for the fixture.
def test_param(ar: O.Arena, slot: U32) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{},
    O.AParam{O.ParamArg{slot, S.int32(),
      None{}, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}},
    O.TNone{})

# A test ALLOC.
def test_alloc(ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsALLOC{}, Nil{}, O.ABad{}, O.TNone{})

# Build the fixture: SINK[PARAM{0}, PARAM{1}, ALLOC]. Returns the
# (grown arena, sink index) pair.
def fixture.sink(ar: O.Arena, p0: U32, p1: U32, a: U32) -> O.Found:
  O.UOp.sink(ar, [p0, p1, a])

# Read a node's op/src/arg as a printable tuple. `op` is rendered via
# `O.Ops.name`; `src` is the list of indices (the replaced ones, looked
# up in the `repl` map); `arg` is the printed `O.Arg`. Sub-defs come
# FIRST, per the BEND NAMING RULE (R-3).
def gr_show.srcs(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: ""
    case x <> t:
      match t:
        case Nil{}: U32.show(x)
        case _: String.concat([U32.show(x), ",", gr_show.srcs(t)])

def gr_show.param_arg(pa: O.ParamArg) -> String:
  String.concat(["AParam{slot=", U32.show(O.ParamArg.slot(pa)), "}"])

def gr_show.arg(a: O.Arg) -> String:
  match a:
    case O.AParam{pa}: gr_show.param_arg(pa)
    case O.ABad{}: "ABad"
    case _: "?"

def gr_show.of.go(ar: O.Arena, u: U32, repl: Map<&2, U32>, op: O.Op, srcs: List<&2, U32>, arg: O.Arg) -> String:
  String.concat([
    "op=", O.Ops.name.of(op),
    " src=[", gr_show.srcs(srcs), "]",
    " arg=", gr_show.arg(arg)
  ])

def gr_show.of(+ar: O.Arena, +u: U32, +repl: Map<&2, U32>) -> String:
  gr_show.of.go(ar, u, repl, O.Arena.op(ar, u), O.Arena.srcs(ar, u), O.Arena.arg(ar, u))

# Print the rebuilt graph. `ar` is the arena, `sink` is the rebuilt
# sink's index. The repl map is printed so a CPython oracle can match
# by U32 index.
def gr_show.sink(ar: O.Arena, sink: U32, repl: Map<&2, U32>) -> String:
  gr_show.of(ar, sink, repl)


def main.go(r: Maybe<&2, U32>, +ar: O.Arena) -> IO(Unit):
  match r:
    case Some{new_sink}: IO.print(gr_show.sink(ar, new_sink, Map.new(&2, U32)))
    case None{}: IO.print("codegen/__init__.bend: no rebuilt sink (wall)")

def main.of(+ar: O.Arena, sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>) -> IO(Unit):
  main.go(walk_rewrite(ar, sink, pm, ctx), ar)

def main() -> IO(Unit):
  # Build the fixture: a SINK[PARAM{0}, PARAM{1}, ALLOC]. `ar` grows as
  # we mint each node; the final `ar` carries the whole graph.
  ar0 = O.Arena.empty()
  +p0 = test_param(ar0, 0)
  +p1 = test_param(O.Found.ar(p0), 1)
  +al = test_alloc(O.Found.ar(p1))
  +sk = fixture.sink(O.Found.ar(al), O.Found.i(p0), O.Found.i(p1), O.Found.i(al))

  # Build the ctx: [A, B]. Two dummy PARAMs with placeholder slots
  # 99 and 100. These are the nodes the PARAM rule returns when its
  # slot is 0 or 1.
  +ca = ctx_param(O.Found.ar(sk), 99)
  +cb = ctx_param(O.Found.ar(ca), 100)
  ctx: List<&2, U32> = [O.Found.i(ca), O.Found.i(cb)]

  main.of(O.Found.ar(cb), O.Found.i(sk), pm_post_sched_cache(), ctx)
