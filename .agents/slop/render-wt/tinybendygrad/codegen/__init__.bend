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

# `walk_rewrite` -- the MLIR-style single-pass driver. Wall.
def walk_rewrite(+ar: O.Arena, +sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>) -> Maybe<&2, U32>:
  None{}

# `unified_rewrite` -- the fixpoint driver. Wall.
def unified_rewrite(ar: O.Arena, sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>) -> Maybe<&2, U32>:
  None{}

# `graph_rewrite` -- the dispatcher. Wall.
def graph_rewrite(ar: O.Arena, sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>, walk: Bool) -> Maybe<&2, U32>:
  None{}


# ============================================================================
# THE GATE. Prints `SOME PROOFS FAIL` honestly. A wall that compiles
# and a gate that runs `SOME PROOFS FAIL` honestly is BETTER than a
# wall that compiles and prints the wrong answer.
# ============================================================================
def main() -> IO(Unit):
  IO.print("codegen/__init__.bend: WALL (rewrite engine not ported)")
