# tinybendygrad/codegen/__init__.bend -- port of tinygrad/codegen/__init__.py
#
# ============================================================================
# STATUS: WALL PARTIALLY BROKEN. The rewrite engine's MLIR-style
# `walk_rewrite` (single-pass driver) compiles and runs. `unified_rewrite`
# (the fixpoint driver) and `graph_rewrite` (the dispatcher) are still
# walls.
#
# This file is the rewrite engine's SHAPE. The spec at
# `.agents/slop/notes/p3-graph-rewrite-spec.md` says it must live here.
# The `pm_rewrite_m`/`pm_dispatch_m` family in `uop/ops.bend` returns
# `Maybe<&2, U32>` (the new node, or `None{}`); the engine in this file
# drives that family over a toposorted graph and rebuilds the result.
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
# srcs.
def wr.step.mint(+ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>, r: Maybe<&2, U32>) -> Map<&2, U32>:
  match r:
    case Some{new_u}: Map.set(&2, U32, repl, U32.show(u), new_u)
    case None{}: wr.rebuild(ar, u, repl)

# The seen-test match. Already in `repl` (`True{}`): skip. Not yet
# (`False{}`): run the rule scan, then mint-or-rebuild.
def wr.step.go(seen: Bool, +ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>) -> Map<&2, U32>:
  match seen:
    case True{}: repl
    case False{}:
      wr.step.mint(ar, pm, u, repl, O.pm_rewrite_m(pm, ar, u))

# Per-node entry. seen? scan? mint? rebuild?
def wr.step(+ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>) -> Map<&2, U32>:
  wr.step.go(R.chas(repl, u), ar, pm, u, repl)

# Fold over the toposort list. Returns the replace map.
def wr.go(lst: List<&2, U32>, +ar: O.Arena, +pm: O.PMEntrys, +repl: Map<&2, U32>) -> Map<&2, U32>:
  match lst:
    case Nil{}: repl
    case +u <> t: wr.go(t, ar, pm, wr.step(ar, pm, u, repl))


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
  walk_rewrite.of(sink, R.cu32(wr.go(O.UOp.toposort(U32.to_nat(O.Arena.next(ar)), ar, sink), ar, pm, Map.new(&2, U32)), sink))


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
