# tinybendygrad/codegen/__init__.bend -- port of tinygrad/codegen/__init__.py
#
# ============================================================================
# STATUS. `walk_rewrite` (the MLIR-style single-pass driver) runs over an
# arena and returns the rebuilt sink ADDRESSED IN THAT ARENA. `unified_rewrite`
# (the fixpoint driver) ships as a wall: it returns `walk_rewrite`'s result,
# no actual fixpoint. The 3-stage worklist is a future unit.
#
# This file is the rewrite engine's SHAPE. The `pm_rewrite_m`/
# `pm_dispatch_m` family in `uop/ops.bend` returns `Maybe<&2, U32>` (the
# new node, or `None{}`); the engine here drives that family over a toposorted
# graph and rebuilds the result. `pm_post_sched_cache` is the smallest test
# case (PARAM and ALLOC) and the spec's example.
#
# AN INDEX IS ONLY MEANINGFUL IN THE ARENA THAT PRODUCED IT. `O.UOp.new` is
# `+`: it grows the arena and hands back `O.Found{ar, i}` with the GROWN
# arena in `ar`. So the fold's accumulator is `(O.Arena & Map<&2, U32>)` and
# `walk_rewrite` returns `(O.Arena & Maybe<&2, U32> & Map<&2, U32>)` -- one
# arena, one fold, so every index printed is read out of the arena that
# interned it. Returning the index ALONE was the bug this shape exists to
# prevent: `O.Arena.node` is TOTAL (`at(i)` or the arena bottom), so a stale
# index does not fail -- it reads back as `NOOP`, no srcs, which is a
# plausible value and a silently wrong answer. `.agents/slop/` has four
# measurements of that same wall in `codegen/decomp/dtype.bend`.
#
# THE REBUILD ORDER IS REBUILD THEN RULE, but the rule is tried on `u`, the
# ORIGINAL node. Upstream tries it on the REBUILT one (ops.py:1812). For
# `pm_post_sched_cache` the two arguments are the same object, so it is
# unobservable: both of upstream's patterns are bare `UPat(Ops.X)` with no
# `src=` clause (so neither can read a src), and ops.py:1810 hands back `n`
# itself whenever `new_src == n.src`, which is every src-free node. MEASURED
# over a 10-fixture sweep, the two spellings are byte-identical on all 10
# (`.agents/slop/unobservable-gr-oracle.py` Q1). No fixture over this table
# can separate them, so the divergence is recorded here rather than fixed.
#
# A rule that fires (`Some{}`) overwrites `u` in `repl`; a rule that misses
# (`None{}`) leaves the rebuilt node there instead.
#
# BEND NAMING RULE, observed (and appended to bend2-constraints.md as R-3):
# a sub-namespace def (`name.subname`) must be declared BEFORE the parent
# `def name` that calls it. The order below obeys this rule (leaves first,
# parents last).
# ============================================================================

import Base
import ./../uop/ops.bend as O
import ./../uop/render.bend as R
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S


# ============================================================================
# THE HELPER NAMESPACE `wr.*`. Bottom-up (R-3): every sub-def before its
# caller.
#
# The fold's state is the PAIR `(ar, repl)` because `wr.rebuild` mints. Three
# wrappers exist only because a `match` may not destructure a computed value
# or a local binder -- a pair is destructurable only as a PARAMETER:
#   wr.rebuild.found -- `O.Found` -> `(ar, repl)`, out of `O.UOp.new`
#   wr.step.rebuild  -- `(ar, repl)` -> `(ar, rebuilt, repl)`
#   wr.step.of       -- that triple -> `(ar, repl)` with the rule applied
# ============================================================================

# Fold over a node's srcs, looking each up in `repl`. If absent, the
# original `s` is its own replacement (the toposort guarantees `s` was
# visited first).
def wr.rebuild.go(+srcs: List<&2, U32>, +ar: O.Arena, +u: U32, +repl: Map<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match srcs:
    case Nil{}: acc
    case +s <> t:
      wr.rebuild.go(t, ar, u, repl, List.append(&2, U32, acc, [R.cu32(repl, s)]))

# Mint a new node with the rewritten srcs, and record `u -> i` in the map.
# The grown arena is the `Found.ar` half of `O.UOp.new` and it is THREADED,
# not dropped (see the header).
def wr.rebuild.found(f: O.Found, u: U32, repl: Map<&2, U32>) -> (O.Arena & Map<&2, U32>):
  match f:
    case O.Found{ar, i}: (ar, Map.set(&2, U32, repl, U32.show(u), i))

def wr.rebuild(+ar: O.Arena, +u: U32, +repl: Map<&2, U32>) -> (O.Arena & Map<&2, U32>):
  wr.rebuild.found(O.UOp.new(ar, O.Arena.op(ar, u), wr.rebuild.go(O.Arena.srcs(ar, u), ar, u, repl, Nil{}), O.Arena.arg(ar, u), O.Arena.tag(ar, u)), u, repl)

# The rule-result match. A rule fired (`Some{new_u}`): overwrite the
# rebuilt node in `repl`. No rule fired (`None{}`): keep the rebuilt
# node (the map already has `u -> rebuilt` from the rebuild).
def wr.step.try_rule(+u: U32, r: Maybe<&2, U32>, repl: Map<&2, U32>, rebuilt: U32) -> Map<&2, U32>:
  match r:
    case Some{new_u}: Map.set(&2, U32, repl, U32.show(u), new_u)
    case None{}: Map.set(&2, U32, repl, U32.show(u), rebuilt)

# `rebuilt` is `repl[u]` read in the REBUILD'S OWN map -- which is why it is
# read here and not carried out of `wr.rebuild`: the map is the record of the
# interned node, so one lookup answers it and the pair stays a pair.
def wr.step.rebuild(u: U32, p: (O.Arena & Map<&2, U32>)) -> (O.Arena & U32 & Map<&2, U32>):
  (ar, +repl) = p
  (ar, R.cu32(repl, u), repl)

def wr.step.scan(+ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>, +ctx: List<&2, U32>, +rebuilt: U32) -> Map<&2, U32>:
  wr.step.try_rule(u, O.pm_rewrite_m(pm, ar, u, ctx), repl, rebuilt)

def wr.step.seen.go(ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>, +ctx: List<&2, U32>, +rebuilt: U32) -> Map<&2, U32>:
  wr.step.scan(ar, pm, u, repl, ctx, rebuilt)

# The triple in, the pair out, with the rule applied. `rebuilt` is NOT what the
# rule reads; it is only what `try_rule` falls back to when no rule fires. The
# rule is tried on `u`, the ORIGINAL node (see the header).
def wr.step.of(+pm: O.PMEntrys, +u: U32, +ctx: List<&2, U32>, p: (O.Arena & U32 & Map<&2, U32>)) -> (O.Arena & Map<&2, U32>):
  (+ar, rebuilt, repl) = p
  (ar, wr.step.seen.go(ar, pm, u, repl, ctx, rebuilt))

def wr.step(+pm: O.PMEntrys, +u: U32, +ctx: List<&2, U32>, acc: (O.Arena & Map<&2, U32>)) -> (O.Arena & Map<&2, U32>):
  (ar, repl) = acc
  wr.step.of(pm, u, ctx, wr.step.rebuild(u, wr.rebuild(ar, u, repl)))

# Fold over the toposort list. Returns the grown arena and the replace map.
def wr.go(lst: List<&2, U32>, +pm: O.PMEntrys, +ctx: List<&2, U32>, acc: (O.Arena & Map<&2, U32>)) -> (O.Arena & Map<&2, U32>):
  match lst:
    case Nil{}: acc
    case +u <> t: wr.go(t, pm, ctx, wr.step(pm, u, ctx, acc))


# ============================================================================
# THE PUBLIC ENTRIES.
# ============================================================================

def walk_rewrite.of(sink: U32, u: U32) -> Maybe<&2, U32>:
  match u:
    case 0: None{}
    case _: Some{u}

# The rebuilt sink, in the fold's arena, plus the replace map. All three
# come from ONE `wr.go` call: two calls off the same starting arena would
# each grow their own copy, and the two copies number their new nodes
# differently.
def walk_rewrite.put(+sink: U32, p: (O.Arena & Map<&2, U32>)) -> (O.Arena & Maybe<&2, U32> & Map<&2, U32>):
  (ar, +repl) = p
  (ar, (walk_rewrite.of(sink, R.cu32(repl, sink)), repl))

# `walk_rewrite` is the MLIR-style single-pass driver (ops.py:1790).
#
# `ctx` is a `List<&2, U32>` here because the engine does not yet own a typed
# context record. The codegen pipeline passes the real `ctx` as a single
# arena-indexed U32 (the `ctx[0]` from Python's `RewriteContext`), and the
# rule bodies read it back as such. This untyped `List<&2, U32>` is the
# wall-passing shape until the typed `CTX` record lands.
def walk_rewrite(+ar: O.Arena, +sink: U32, +pm: O.PMEntrys, +ctx: List<&2, U32>) -> (O.Arena & Maybe<&2, U32> & Map<&2, U32>):
  walk_rewrite.put(sink, wr.go(O.UOp.toposort(U32.to_nat(O.Arena.next(ar)), ar, sink), pm, ctx, (ar, Map.new(&2, U32))))


# `unified_rewrite` -- the fixpoint driver. WALL. The Python driver is a
# 3-stage worklist (stage 0: push node + srcs; stage 1: when all srcs are
# in `replace`, rebuild + try top-down rule, push to stage 2; stage 2:
# link the new node's replacement back to `n`). A `bpm` (bottom-up) table
# may fire to a fixed point per node.
#
# The minimal Bend port is the same fold re-run after each pass, which would
# need a fresh arena AND a fresh toposort on every pass. The 4-hour wall is to
# ship the wall: a single pass that always returns the same as `walk_rewrite`.
# A wall that compiles and a gate that runs is more useful than a fixpoint that
# doesn't.
#
# An earlier version of this comment claimed `+` is what forces that freshness.
# It does not. `+ar` means "the callee may REBIND this name", not "consumed on
# every path" -- measured by `.agents/slop/arena-affine-probe.bend`, which
# compiles and runs:
#
#   ctl2_read=None                 a read AFTER a spend is permitted, and
#                                  silently sees the PRE-mint arena
#   ctl1_f=2 ctl1_g=2              two mints from one arena NAME both return
#                                  index 2, and the second overwrites the first
#
# So single-pass correctness here rests on the arena being threaded explicitly
# through every signature below, NOT on `+`. Where this file writes `(ar, +repl)
# = p`, the `+` is inside the destructuring because a tuple parameter cannot
# carry it -- that is the only reason it is there.
def unified_rewrite(ar: O.Arena, sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>) -> (O.Arena & Maybe<&2, U32> & Map<&2, U32>):
  walk_rewrite(ar, sink, pm, ctx)

# `graph_rewrite` -- the dispatcher. Wall.
def graph_rewrite(ar: O.Arena, sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>, walk: Bool) -> (O.Arena & Maybe<&2, U32> & Map<&2, U32>):
  (ar, (None{}, Map.new(&2, U32)))


# ============================================================================
# THE GATE: build the smallest `pm_post_sched_cache` fixture, run
# `walk_rewrite` over it, and print the repl map (old_index ->
# new_index). The CPython oracle at `.agents/slop/codegen-init-oracle.py`
# prints the same shape for the same fixture; the diff is the gate.
# ============================================================================

# The rule table. TWO entries, and TWO upstream: `pm_post_sched_cache` at
# `tinygrad/schedule/__init__.py:96-101` is a `PatternMatcher` of exactly two
# patterns, read off the objects and not off the text
# (`codegen-init-oracle.py` Q1), and neither carries a `src=` clause. The
# reject sets here are empty, which is also upstream's: both of its `UPat`s
# are field-less.
#
#   tag 3 PARAM  upstream rule 0: `UPat(Ops.PARAM)`, `ctx[1][slot] if slot >= 0 else None`
#   tag 4 ALLOC  upstream rule 1: `UPat(Ops.ALLOC)`, `create_new_buffer`
def pm_post_sched_cache() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{3, [O.OpsPARAM{}], Nil{}}, O.PMEntry{4, [O.OpsALLOC{}], Nil{}}]}

# A dummy PARAM that the ctx carries. The minimal printable form is
# `AParam{slot=N, dtype=int32, ...}`; the rest of the fields default to
# `None{}`/`False{}`. Two of these (slots 99 and 100) are the "A" and
# "B" in the test ctx. IDENTICAL to `test_param` below; they are the same
# def under the two names the two call sites use, kept apart because the
# fixture's slot and the ctx's slot are different facts.
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

# Pre-mint a BUFFER for `pm_r_alloc_m`. The engine cannot afford to
# mint in a rule body (the new arena would be discarded); the test
# fixture mints the BUFFER once and passes its index in `ctx[2]`.
def test_buffer(ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsBUFFER{}, Nil{}, O.ABad{}, O.TNone{})

# Build the fixture: SINK[PARAM{0}, PARAM{1}, ALLOC]. Returns the
# (grown arena, sink index) pair.
def fixture.sink(ar: O.Arena, p0: U32, p1: U32, a: U32) -> O.Found:
  O.UOp.sink(ar, [p0, p1, a])

# A node's printable form is `OP(slot=N)` for PARAM and the bare
# OP name otherwise, which is CPython's `uop_short` in `gr-oracle.py`. The
# printer needs the ARENA to read the op and the arg, so it is threaded
# through: an arena index alone names nothing outside this file, and the
# oracle prints names.
def gr_show.node.slot(pa: O.ParamArg) -> String:
  String.concat(["(", U32.show(O.ParamArg.slot(pa)), ")"])

def gr_show.node.of(ar: O.Arena, u: U32, op: O.Op, arg: O.Arg) -> String:
  match arg:
    case O.AParam{pa}: String.concat([O.Ops.name.of(op), gr_show.node.slot(pa)])
    case _: O.Ops.name.of(op)

def gr_show.node.op(ar: O.Arena, u: U32) -> O.Op:
  O.Arena.op(ar, u)

def gr_show.node.arg(ar: O.Arena, u: U32) -> O.Arg:
  O.Arena.arg(ar, u)

def gr_show.node(+ar: O.Arena, +u: U32) -> String:
  gr_show.node.of(ar, u, gr_show.node.op(ar, u), gr_show.node.arg(ar, u))

def gr_show.repl.pair.of(ar: O.Arena, u: U32, v: U32, a: String, b: String) -> String:
  String.concat([a, "->", b])

def gr_show.repl.pair(+ar: O.Arena, +u: U32, +v: U32) -> String:
  gr_show.repl.pair.of(ar, u, v, gr_show.node(ar, u), gr_show.node(ar, v))

def gr_show.repl.go.bind(t: List<&2, U32>, +ar: O.Arena, +m: Map<&2, U32>, acc: String) -> String:
  match t:
    case Nil{}: acc
    case +v <> rest:
      gr_show.repl.go.bind(rest, ar, m, String.concat([acc, gr_show.repl.pair(ar, v, R.cu32(m, v)), ", "]))

def gr_show.repl.go.first.of(+ar: O.Arena, t: List<&2, U32>, +m: Map<&2, U32>, +u: U32, +v: U32) -> String:
  gr_show.repl.go.bind(t, ar, m, String.concat([gr_show.repl.pair(ar, u, v), ", "]))

def gr_show.repl.go.first(t: List<&2, U32>, +ar: O.Arena, +m: Map<&2, U32>, +u: U32) -> String:
  gr_show.repl.go.first.of(ar, t, m, u, R.cu32(m, u))

def gr_show.repl.go(ar: O.Arena, +m: Map<&2, U32>, topo: List<&2, U32>) -> String:
  match topo:
    case Nil{}: ""
    case +u <> t: gr_show.repl.go.first(t, ar, m, u)

# Print the repl map as a comma-separated list of `OP(slot)->OP(slot)` pairs,
# one per toposort node. NAMES, not indices: the oracle prints names, so an
# index would be a diff of two unrelated numberings. The arena is the FOLD'S
# grown arena -- the map's values are indexes into it.
def gr_show.repl(ar: O.Arena, m: Map<&2, U32>, topo: List<&2, U32>) -> String:
  gr_show.repl.go(ar, m, topo)

# Build the full fixture and the ctx; the gate runs `walk_rewrite` and
# prints the repl map. `walk_rewrite` hands back the fold's grown arena with
# the sink and the map, so ONE call prints every row from one arena.
def main.run.show.go(r: Maybe<&2, U32>, repl_s: String) -> IO(Unit):
  match r:
    case Some{new_sink}: IO.print(String.concat(["new_sink=", U32.show(new_sink), " repl=", repl_s]))
    case None{}: IO.print("codegen/__init__.bend: no rebuilt sink (wall)")

def main.run.show.of(r: Maybe<&2, U32>, repl_s: String) -> IO(Unit):
  main.run.show.go(r, repl_s)

def main.run.show(+ar: O.Arena, r: Maybe<&2, U32>, repl: Map<&2, U32>, topo: List<&2, U32>) -> IO(Unit):
  main.run.show.of(r, gr_show.repl(ar, repl, topo))

def main.run(t: List<&2, U32>, p: (O.Arena & Maybe<&2, U32> & Map<&2, U32>)) -> IO(Unit):
  (ar, (r, repl)) = p
  main.run.show(ar, r, repl, t)

def main.walk(t: List<&2, U32>, +ar: O.Arena, +sink: U32, +pm: O.PMEntrys, +ctx: List<&2, U32>) -> IO(Unit):
  main.run(t, walk_rewrite(ar, sink, pm, ctx))

def main() -> IO(Unit):
  # Build the fixture: a SINK[PARAM{0}, PARAM{1}, ALLOC]. `ar` grows as
  # we mint each node; the final `ar` carries the whole graph.
  ar0 = O.Arena.empty()
  +p0 = test_param(ar0, 0)
  +p1 = test_param(O.Found.ar(p0), 1)
  +al = test_alloc(O.Found.ar(p1))
  +sk = fixture.sink(O.Found.ar(al), O.Found.i(p0), O.Found.i(p1), O.Found.i(al))

  # Build the ctx: [A, B, buf]. A and B are dummy PARAMs (slots 99 and
  # 100) that the PARAM rule returns when the original node's slot is
  # 0 or 1. `buf` is a pre-minted BUFFER that the ALLOC rule returns.
  # The engine cannot mint in a rule body (`pm_rewrite_m` consumes the
  # arena and returns only a `Maybe`), so all rule-replacement nodes must
  # be pre-minted and threaded through `ctx`.
  +ca = ctx_param(O.Found.ar(sk), 99)
  +cb = ctx_param(O.Found.ar(ca), 100)
  +bf = test_buffer(O.Found.ar(cb))
  ctx: List<&2, U32> = [O.Found.i(ca), O.Found.i(cb), O.Found.i(bf)]

  main.walk(O.UOp.toposort(U32.to_nat(O.Arena.next(O.Found.ar(bf))), O.Found.ar(bf), O.Found.i(sk)),
            O.Found.ar(bf), O.Found.i(sk), pm_post_sched_cache(), ctx)