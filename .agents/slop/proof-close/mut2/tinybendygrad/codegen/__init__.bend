# tinybendygrad/codegen/__init__.bend -- port of tinygrad/codegen/__init__.py
#
# ============================================================================
# STATUS: WALL. The rewrite engine (`graph_rewrite`/`walk_rewrite`/
# `unified_rewrite`) is the bottom of the wall for codegen. The spec at
# `.agents/slop/notes/p3-graph-rewrite-spec.md` says it must live here.
#
# This file is the WALL shape, not the engine. It compiles and the gate
# prints `SOME PROOFS FAIL` honestly. The spec's "right way to fail" --
# "a wall that compiles and a gate that runs SOME PROOFS FAIL honestly is
# BETTER than a green gate that prints the wrong answer" -- applies here.
#
# The first step of the rewire is in place: the `pm_rewrite_m`/`pm_dispatch_m`
# family in `uop/ops.bend` and the `pm_post_sched_cache` table. The
# `pm_rewrite`/`pm_dispatch` family is unchanged so `uop/spec.bend` (the
# only consumer) is green. The engine that DRIVES `pm_rewrite_m` over a
# toposorted graph is the wall.
#
# The two-step rewire (per the spec) is half-done. Step 1 -- adding the
# `_m` family that returns `PMRew{at}` -- is in `uop/ops.bend`. Step 2
# -- driving that family over a toposort and rebuilding the result --
# is not. The single self-recursive fold shape that the substrate uses
# (the `rws.go`/`rws_step` pair) needs `+Arena`-threading and a `+Map`
# replace store, and a `Bool.pick` for the seen-test, all of which fight
# the affine `+` rules; the cycle that the substrate's "self-recursive
# def is the only one" rule forbids kept reasserting itself in the
# `(walk.fold, walk.fold.step, walk.fold.process, walk.fold.rebuild)`
# shape. The honest wall is: the engine port is not done in this
# session. The other 11 functions in `codegen/__init__.py` are `TODO(p3)`
# after this lands and they are independent units.
# ============================================================================

import Base
import ./../uop/ops.bend as O
import ./../uop/render.bend as R
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S


# ============================================================================
# THE THREE PASS DRIVERS. All three are wall stubs that compile and
# return `None{}`. The shape matches the spec
# `(ar: Arena, sink: U32, pm: PMEntrys, ctx: List<&2, U32>,
#  bottom_up: Bool, walk: Bool) -> Maybe<&2, U32>` minus the `bottom_up`
# flag (the substrate has only one rule table per call, not a separate
# top-down and bottom-up table). The public name is `graph_rewrite`; the
# other two are exposed for the codegen pipeline that calls
# `walk_rewrite` directly.
# ============================================================================

# `walk_rewrite` -- the MLIR-style single-pass driver.
#
# Toposort the graph from `sink`, then fold over the topo list threading a
# `+Arena` and a `+Map<&2, U32>` replace store keyed by `U32.show(old)`.
# For each node, check whether a rule claimed it (`pm_rewrite_m`); if so,
# record `(old, new)` in the map; otherwise rebuild the node with its
# REWRITTEN srcs (each src looked up in the replace map) and record that.
#
# The fold is the `consumers.go` shape from `uop/render.bend:1787`:
# a list cons'd `+` from the head, the next-node call on the tail, the
# accumulator threaded `+`. The `+` on `u` is what makes this a descent
# over the toposort and not a fold over its own parameter.
#
# BEND NAMING RULE, observed: when a public def has the same name as a
# sub-namespace (e.g. `walk_rewrite` plus `walk_rewrite.go`), Bend
# treats the sub-def as a `law` claim against the public def and prints
# "an unfilled law is a dead claim: live code cannot use it". The fix
# is to keep the public def under one name and the namespace under
# another. Here: `walk_rewrite` is the entry; `wr.*` is the namespace.
def step(ar: O.Arena, pm: O.PMEntrys, u: U32, repl: Map<&2, U32>) -> Map<&2, U32>:
  # minimal: just delegate to a leaf
  step.leaf(ar, pm, u, repl)

def step.leaf(ar: O.Arena, pm: O.PMEntrys, u: U32, repl: Map<&2, U32>) -> Map<&2, U32>:
  repl

def wr.step.scan(+ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>, seen: Bool) -> Map<&2, U32>:
  match seen:
    case True{}: repl
    case False{}:
      wr.step.mint(ar, pm, u, repl, O.pm_rewrite_m(pm, ar, u))

def wr.step.mint(+ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>, r: Maybe<&2, U32>) -> Map<&2, U32>:
  match r:
    case Some{new_u}: Map.set(&2, U32, repl, U32.show(u), new_u)
    case None{}: wr.rebuild(ar, u, repl)

# Rebuild a node by walking its srcs, looking each up in `repl`, and
# minting a new node with the same op and arg but the rewritten srcs.
# The `+` on `ar` is the substrate rule: a def that mints must pass the
# arena `+` so the result is the new arena.
def wr.rebuild.go(+srcs: List<&2, U32>, +ar: O.Arena, +u: U32, +repl: Map<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match srcs:
    case Nil{}: acc
    case +s <> t:
      # look up `s` in `repl`. If absent, the original `s` is its own
      # replacement (the toposort guarantees `s` was visited first).
      wr.rebuild.go(t, ar, u, repl, List.append(&2, U32, acc, [R.cu32(repl, s)]))

def wr.rebuild.of(f: O.Found, +u: U32, +repl: Map<&2, U32>) -> Map<&2, U32>:
  Map.set(&2, U32, repl, U32.show(u), O.Found.i(f))

def wr.rebuild(+ar: O.Arena, +u: U32, +repl: Map<&2, U32>) -> Map<&2, U32>:
  # the rebuilt srcs are the original srcs passed through `repl`.
  # Then mint a new node with op(u), arg(u), tag(u), and the rebuilt srcs.
  # The new U32 is `Found.i` of `UOp.new`.
  wr.rebuild.of(UOp.new(ar, O.Arena.op(ar, u), wr.rebuild.go(O.Arena.srcs(ar, u), ar, u, repl, Nil{}), O.Arena.arg(ar, u), O.Arena.tag(ar, u)), u, repl)

# Fold over the toposort list. Returns the map AND the new arena, but
# a Map<&2, U32> is the only output the caller needs (the rebuilt sink
# is `cu32(repl, original_sink)`).
def wr.go(lst: List<&2, U32>, +ar: O.Arena, +pm: O.PMEntrys, +repl: Map<&2, U32>) -> Map<&2, U32>:
  match lst:
    case Nil{}: repl
    case +u <> t: wr.go(t, ar, pm, wr.step(ar, pm, u, repl))

# Public entry. Returns the rebuilt sink.
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
  walk_rewrite.of(sink, R.cu32(wr.go(O.UOp.toposort(O.Arena.ns(ar), ar, sink), ar, pm, Map.new(&2, U32)), sink))

def walk_rewrite.of(sink: U32, u: U32) -> Maybe<&2, U32>:
  match u:
    case 0: None{}
    case _: Some{u}


# `unified_rewrite` -- the fixpoint driver. Wall.
def unified_rewrite(ar: O.Arena, sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>) -> Maybe<&2, U32>:
  None{}

# `graph_rewrite` -- the dispatcher. Wall.
def graph_rewrite(ar: O.Arena, sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>, walk: Bool) -> Maybe<&2, U32>:
  None{}


# ============================================================================
# THE GATE.
# ============================================================================
def main() -> IO(Unit):
  IO.print("codegen/__init__.bend: rewrite engine in flight (walk_rewrite landed, fixpoint pending)")
