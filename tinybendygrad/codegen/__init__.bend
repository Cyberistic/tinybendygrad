# tinybendygrad/codegen/__init__.bend -- port of tinygrad/codegen/__init__.py
#
# ============================================================================
# STATUS. `walk_rewrite` (the MLIR-style single-pass driver) runs over an
# arena and returns the rebuilt sink ADDRESSED IN THAT ARENA. `unified_rewrite`
# is a REAL FIXPOINT: it re-runs the fold until the sink index stops moving and
# reports HOW MANY PASSES it took and whether it stopped because the graph
# settled or because the pass bound ran out. `graph_rewrite` (the dispatcher,
# ops.py:1888-1890) picks between them on one Bool.
#
# WHAT IS STILL A WALL is named at `unified_rewrite` and not here, because a
# wall listed in a header is a wall nobody re-reads: upstream's `bottom_up` /
# `bpm` TABLE SELECTION (ops.py:1889) has no second table in `uop/ops.bend`,
# and neither driver honours `enter_calls` (ops.py:1833/1841).
#
# This file is the rewrite engine's SHAPE. The `pm_rewrite_m`/
# `pm_dispatch_m` family in `uop/ops.bend` returns `Maybe<&2, U32>` (the
# new node, or `None{}`); the engine here drives that family over a toposorted
# graph and rebuilds the result. `pm_post_sched_cache` is the smallest test
# case (PARAM and ALLOC) and the spec's example.
#
# AN INDEX IS ONLY MEANINGFUL IN THE ARENA THAT PRODUCED IT. `O.UOp.new` is
# `+`: it grows the arena and hands back `O.Found{ar, i}` with the GROWN
# arena in `ar`. So the fold's accumulator is `(O.Arena & Map<&2, U32>)`,
# `walk_rewrite` returns that same 3-tuple, and the two DRIVERS' answers are
# `Rewritten` records carrying it -- one arena, one fold, so every index
# printed is read out of the arena that interned it. Returning the index ALONE
# was the bug this shape exists to prevent: `O.Arena.node` is TOTAL (`at(i)` or
# the arena bottom), so a stale index does not fail -- it reads back as `NOOP`,
# no srcs, which is a plausible value and a silently wrong answer.
# `.agents/slop/` has four measurements of that same wall in
# `codegen/decomp/dtype.bend`, and the fixpoint arm's repl row is a fifth: read
# over the WRONG toposort it answers `NOOP` for every key, which is why
# `grw_rows.fix` takes its toposort from the answer's own arena.
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

# THE PASS BOUND. `REWRITE_STACK_LIMIT = 250000` upstream (ops.py:1622) bounds a
# WORKLIST's depth; this port's driver is the same fold re-run, so the
# equivalent is a number of PASSES. It must be >= 2: the loop enters with one
# already spent, because a fixpoint has to CONFIRM convergence and "the sink did
# not move" is a statement about a pass that ran.
def FIXPOINT_PASSES() -> Nat:
  8n

# THE ANSWER, as a record rather than the 3-tuple these defs used to return.
# `passes` and `capped` are NAMED because the three outcomes are a fuel bound, a
# cycle and a fixpoint, and a positional tuple says nothing about which is which.
type Rewritten is Data: Rewritten{ar: O.Arena, sink: Maybe<&2, U32>, repl: Map<&2, U32>, passes: U32, capped: Bool}

def Rewritten.ar(w: Rewritten) -> O.Arena: match w: case Rewritten{ar, sink, repl, passes, capped}: ar
def Rewritten.sink(w: Rewritten) -> Maybe<&2, U32>: match w: case Rewritten{ar, sink, repl, passes, capped}: sink
def Rewritten.repl(w: Rewritten) -> Map<&2, U32>: match w: case Rewritten{ar, sink, repl, passes, capped}: repl
def Rewritten.passes(w: Rewritten) -> U32: match w: case Rewritten{ar, sink, repl, passes, capped}: passes
def Rewritten.capped(w: Rewritten) -> Bool: match w: case Rewritten{ar, sink, repl, passes, capped}: capped

# The drivers' `Maybe` is `None{}` exactly when `repl[sink]` is the arena bottom
# (`walk_rewrite.of`), which a SINK can never intern to because the bottom holds
# `OpsNOOP` (`uop/ops.bend:1167`). So this total read is not a fallback.
def Rewritten.index(w: Rewritten, fallback: U32) -> U32: Maybe.default(&2, U32, Rewritten.sink(w), fallback)

# THE TWO OUTCOMES. Both rebuild the record from the pass's own fields, so the
# repl map is never re-read and never copied.
#
# THE PARAMETER IS `n` AND NOT `passes`, and that is the whole content of this
# comment. A record binder SHADOWS a same-named PARAMETER and nothing says so --
# agent-core.md names the trap -- so `Rewritten.cap(w, passes)` with
# `case Rewritten{ar, sink, repl, passes, capped}` compiles, answers `passes=1`
# for EVERY value of `done` the loop reaches, and the loop's counter is a
# constant. MEASURED, not read: with the parameter named `passes`,
# `unified_rewrite.go(0n, 5, 0, ...)` answered `passes=1`, and with it named `n`
# the same call answers `passes=5`. The gate could not see it either -- `capped`
# was correct and `passes` was not -- which is why a counter that a shadow
# swallowed still looked green.
def Rewritten.hit(w: Rewritten, n: U32) -> Rewritten: match w: case Rewritten{ar, sink, repl, passes, capped}: Rewritten{ar, sink, repl, n, False{}}
def Rewritten.cap(w: Rewritten, n: U32) -> Rewritten: match w: case Rewritten{ar, sink, repl, passes, capped}: Rewritten{ar, sink, repl, n, True{}}

# One pass, lifted from the driver's 3-tuple. The lift is its own def because a
# destructuring may not scrutinise a COMPUTED value -- `walk_rewrite.put` and
# `wr.rebuild.found` in this file are the same shape, and
# `.agents/slop/grw-loop-probe.bend` measures the refusal.
def walk_rewrite.lift(p: (O.Arena & Maybe<&2, U32> & Map<&2, U32>)) -> Rewritten:
  (ar, r, repl) = p
  Rewritten{ar, r, repl, 1, False{}}

# `walk_rewrite` as the dispatcher reports it: ONE pass, never capped. Upstream
# caps nothing on the walk path, because `walk_rewrite` is not a loop.
def walk_rewrite.counted(+ar: O.Arena, +sink: U32, +pm: O.PMEntrys, +ctx: List<&2, U32>) -> Rewritten:
  walk_rewrite.lift(walk_rewrite(ar, sink, pm, ctx))

def walk_rewrite.pass(+sink: U32, +pm: O.PMEntrys, +ctx: List<&2, U32>, +w: Rewritten) -> Rewritten:
  walk_rewrite.lift(walk_rewrite(Rewritten.ar(w), sink, pm, ctx))

# ---------------------------------------------------------------------------
# THE FIXPOINT, ops.py:1777-1885.
#
# Upstream's `unified_rewrite` is a THREE-STAGE WORKLIST: stage 0 pushes a node
# and its srcs (running a bottom-up table to a per-node fixed point first),
# stage 1 rebuilds once every src is in `replace` and runs the top-down table,
# stage 2 links the rebuilt node's replacement back to `n`. It carries a
# `waitlist` for a src that is not ready and an `on_stack` set.
#
# The port's is THE SAME FOLD RE-RUN, which is what makes it a FIXPOINT rather
# than the single pass `unified_rewrite` used to be. What is NOT ported is named
# here rather than left implied:
#
#   * `bottom_up` / `bpm`. Upstream puts `pm` in `self.bpm` and `None` in
#     `self.pm` when `bottom_up=True`, and BOTH drivers then run only the
#     bottom-up table. `uop/ops.bend` -- which this file must not edit -- has
#     no `bpm` and no per-entry bottom-up marker, so there is no second table
#     for the dispatcher's other half to select. `pm_post_sched_cache` is
#     top-down in both ports, so this is INVISIBLE on the fixture and it is a
#     wall upstream, not a silent difference. ops.py:1889.
#   * `enter_calls`. Both drivers skip `n.src[1:]` of a CALL, so the two
#     upstream call sites that pass `enter_calls=True`
#     (`schedule/__init__.py:276`, `codegen/__init__.py:492`) are wrong here.
#     ops.py:1833/1841.
#   * The per-node `seen` set and `BottomUpGate`, which bound the BOTTOM-UP loop
#     the port does not have.
#
# ---------------------------------------------------------------------------
# THE STOP IS "the sink index did not move", AND IT IS SOUND BECAUSE THE ARENA
# INTERNS. `uop/ops.bend:2212 UOp.make` calls `intern.find` and a HIT returns the
# arena UNTOUCHED, so two passes handing back the same sink INDEX handed back the
# same `Node{op, src, arg, tag}`. The reachable graph is identical,
# `pm_rewrite_m` is a pure function of that graph and of `ctx`, and the next pass
# rebuilds nothing. Index equality here is the interning invariant, not a
# coincidence.
#
# A cap and a fixpoint ARE DISTINGUISHABLE here, and `capped` says which.
# Upstream raises for both -- `REWRITE_STACK_LIMIT` at ops.py:1821 and the
# stalled waitlist at :1883 -- and a Bend def returns a value, so both raise
# sites become one Bool. **`capped=True` IS NOT A FIXPOINT and must never be read
# as one.** What it does NOT separate is a genuine rewrite CYCLE (R(n)=m,
# R(m)=n) from a chain that merely needs more passes: both are "the sink was
# still moving when the bound ran out", and the port cannot tell them apart
# because it has no `seen` set. So `capped=True` means NOT-CONVERGED and nothing
# finer. The `grw_cap_*` rows REACH the flag, so it is not merely asserted.
#
# WHY ONE DEF AND NOT TWO. The stop test is a Bool and the bound is a Nat, and
# Bend refuses a `match` after any other statement, refuses a `match` on a
# computed value, and refuses a TWO-DEF cycle -- all three measured in
# `grw-loop-probe.bend`. So the `Nat` match is the body's first statement and the
# `Bool.pick` sits inside its two arms. `f` is the shrinking self-call argument,
# so it comes first and every computed argument follows it. `w` is the pass
# result as a `+` RECORD parameter: a TUPLE may be read exactly once (and `+` on
# one is refused outright), while a record parameter reads as many times as the
# arms need.
def unified_rewrite.same(+prev: U32, w: Rewritten) -> Bool: U32.is_eq(prev, Rewritten.index(w, prev))

def unified_rewrite.go(fuel: Nat, +done: U32, +prev: U32, +w: Rewritten, +pm: O.PMEntrys, +ctx: List<&2, U32>) -> Rewritten:
  match fuel:
    case 0n: Bool.pick(Rewritten, unified_rewrite.same(prev, w), Rewritten.hit(w, done), Rewritten.cap(w, done))
    case 1n+f: Bool.pick(Rewritten, unified_rewrite.same(prev, w), Rewritten.hit(w, done), unified_rewrite.go(f, U32.add(done, 1), Rewritten.index(w, prev), walk_rewrite.pass(Rewritten.index(w, prev), pm, ctx, w), pm, ctx))

# `prev = 0` is the arena BOTTOM, so the FIRST pass always counts as a MOVE: a
# fixpoint has to be CONFIRMED by a pass that changed nothing, and `prev` is the
# sink as it was BEFORE the pass in `w`.
#
# `done` COUNTS THE PASS IN `w`, WHICH HAS ALREADY RUN, so BOTH arms report `done`
# and the increment belongs to the self-call alone. An earlier version reported
# `done + 1` on the `1n+f` arm, and the fixture's fixpoint answered `passes=3`
# where the graph reached its fixed point on pass 2 -- a counter that grows by one
# on the arm that happened to stop the loop, which is a counter of WHICH ARM
# STOPPED rather than of PASSES RUN.
def unified_rewrite(+ar: O.Arena, +sink: U32, +pm: O.PMEntrys, +ctx: List<&2, U32>) -> Rewritten:
  unified_rewrite.go(Nat.sub(FIXPOINT_PASSES(), 1n), 1, 0, walk_rewrite.lift(walk_rewrite(ar, sink, pm, ctx)), pm, ctx)

# `graph_rewrite` -- the dispatcher, ops.py:1888-1890. Upstream's body is two
# statements and only the SECOND is the dispatch:
#
#   rewrite_ctx = RewriteContext(pm if not bottom_up else None, pm if bottom_up else bpm, ctx, enter_calls)
#   return rewrite_ctx.walk_rewrite(sink) if walk else rewrite_ctx.unified_rewrite(sink)
#
# The first is TABLE SELECTION and it is the `bottom_up` wall named in
# `unified_rewrite`'s header: the port has ONE table and both drivers read it
# top-down, so `bottom_up=True` is not expressible and this signature does not
# carry it. The second is a ternary on one Bool, and THAT is what is ported.
def graph_rewrite(+ar: O.Arena, +sink: U32, +pm: O.PMEntrys, +ctx: List<&2, U32>, walk: Bool) -> Rewritten:
  Bool.pick(Rewritten, walk, walk_rewrite.counted(ar, sink, pm, ctx), unified_rewrite(ar, sink, pm, ctx))

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

# ---------------------------------------------------------------------------
# THE FIXPOINT GATE. Every row below calls `graph_rewrite` ITSELF, never a
# caller of it and never a driver directly -- a row that gates `walk_rewrite`
# cannot see the dispatcher's ternary, and a mutation there would move nothing.
# The fixture's fixpoint takes TWO passes: the first moves the sink from 4 to 8
# and the second confirms it, so `passes=2` is a statement about the LOOP and not
# about the fold.
#
# `grw_cap_*` reaches `capped=True` on purpose. A cap flag no row can reach is a
# claim, not a measurement, and this row is what makes "a fuel bound and a
# fixpoint are two outcomes" a checked statement instead of a comment.
#
# Each arm's repl map is printed as a STRING over that arm's OWN toposort,
# because the fixpoint's map is keyed by the FINAL graph's indices and not the
# original's: read over the original toposort it answers `NOOP` for every key,
# which is `O.Arena.node` being TOTAL on a stale index (this file's header names
# that hazard, and `.agents/slop/` has four measurements of it).
# ---------------------------------------------------------------------------
def grw_row.go(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# One row name from a fixture prefix, an arm and a field: `grw_f2_fix_repl`.
def grw_row.nm(pfx: String, arm: String, field: String) -> String: String.concat(["grw_", pfx, "_", arm, "_", field])

def grw_row.sink(nm: String, r: Maybe<&2, U32>) -> IO(Unit):
  match r:
    case Some{s}: grw_row.go(nm, U32.show(s))
    case None{}: grw_row.go(nm, "NONE")

# The repl string for one answer, over a NAMED toposort. The walk arm's map is
# keyed by the ORIGINAL graph's indices and the fixpoint arm's by the FINAL
# graph's, so each row names its own toposort rather than letting one def guess.
def grw_row.repl(nm: String, +ar: O.Arena, +m: Map<&2, U32>, topo: List<&2, U32>) -> IO(Unit):
  grw_row.go(nm, gr_show.repl(ar, m, topo))

# The SIZE OF THE ANSWER GRAPH -- the node count of the toposort the repl row is
# printed over. Both sides can answer it (CPython as `len(out.toposort())`), so
# it is compared.
def grw_row.n(nm: String, topo: List<&2, U32>) -> IO(Unit): grw_row.go(nm, U32.show(U32.from_nat(List.length(&2, U32, topo))))

# The repl map's SIZE, which is NOT the same question and is NOT compared.
# Upstream's worklist keys `replace` with every node it touched, INTERMEDIATE
# rebuilds included, and so records 4 nodes for F2 where the port's last pass --
# which starts from an empty map -- records 2. MEASURED: CPython
# `len(rc.replace)` is 4 and the port's `Map.size` is 2, on the same final graph
# whose repl string the two sides print BYTE-IDENTICALLY. The row is kept so the
# disagreement is visible instead of absent, and `grw-gate.sh` names it as a
# declared divergence rather than comparing it.
def grw_row.mapn(nm: String, m: Map<&2, U32>) -> IO(Unit): grw_row.go(nm, U32.show(U32.from_nat(Map.size(&2, U32, m))))

# `graph_rewrite(..., walk=True)` -- the one-pass arm. Its map is keyed by the
# ORIGINAL graph, so the toposort is taken in the arena the call was GIVEN.
def grw_rows.walk(+pfx: String, +ar: O.Arena, +sink: U32, +pm: O.PMEntrys, +ctx: List<&2, U32>) -> IO(Unit):
  +w = graph_rewrite(ar, sink, pm, ctx, True{})
  +topo = O.UOp.toposort(U32.to_nat(O.Arena.next(ar)), ar, sink)
  do IO<Unit>:
    grw_row.go(grw_row.nm(pfx, "walk", "passes"), U32.show(Rewritten.passes(w)))
    grw_row.go(grw_row.nm(pfx, "walk", "capped"), U32.show(Bool.to_u32(Rewritten.capped(w))))
    grw_row.sink(grw_row.nm(pfx, "walk", "sink"), Rewritten.sink(w))
    grw_row.n(grw_row.nm(pfx, "walk", "n"), topo)
    grw_row.mapn(grw_row.nm(pfx, "walk", "mapn"), Rewritten.repl(w))
    grw_row.repl(grw_row.nm(pfx, "walk", "repl"), Rewritten.ar(w), Rewritten.repl(w), topo)

# `graph_rewrite(..., walk=False)` -- the fixpoint arm. Its map is keyed by the
# FINAL graph, so the toposort is taken in the answer's own arena and over the
# sink IT handed back. Reading it over the original toposort would answer `NOOP`
# for every key: `O.Arena.node` is TOTAL on a stale index, which is the hazard
# this file's header names.
def grw_rows.fix(+pfx: String, +ar: O.Arena, +sink: U32, +pm: O.PMEntrys, +ctx: List<&2, U32>) -> IO(Unit):
  +w = graph_rewrite(ar, sink, pm, ctx, False{})
  +ar2 = Rewritten.ar(w)
  +topo = O.UOp.toposort(U32.to_nat(O.Arena.next(ar2)), ar2, Rewritten.index(w, 0))
  do IO<Unit>:
    grw_row.go(grw_row.nm(pfx, "fix", "passes"), U32.show(Rewritten.passes(w)))
    grw_row.go(grw_row.nm(pfx, "fix", "capped"), U32.show(Bool.to_u32(Rewritten.capped(w))))
    grw_row.sink(grw_row.nm(pfx, "fix", "sink"), Rewritten.sink(w))
    grw_row.n(grw_row.nm(pfx, "fix", "n"), topo)
    grw_row.mapn(grw_row.nm(pfx, "fix", "mapn"), Rewritten.repl(w))
    grw_row.repl(grw_row.nm(pfx, "fix", "repl"), ar2, Rewritten.repl(w), topo)

# THE BOUND, REACHED. `unified_rewrite.go` is entered with zero fuel and a `prev`
# of 0, so the pass it runs cannot confirm anything and `cap` is the arm taken.
# This is the row that makes `capped` load-bearing.
def grw_rows.cap(+ar: O.Arena, +sink: U32, +pm: O.PMEntrys, +ctx: List<&2, U32>) -> IO(Unit):
  +w = unified_rewrite.go(0n, 1, 0, walk_rewrite.lift(walk_rewrite(ar, sink, pm, ctx)), pm, ctx)
  do IO<Unit>:
    grw_row.go("grw_cap_passes", U32.show(Rewritten.passes(w)))
    grw_row.go("grw_cap_capped", U32.show(Bool.to_u32(Rewritten.capped(w))))
    grw_row.sink("grw_cap_sink", Rewritten.sink(w))

# The fixture, its sink and its ctx as ONE value. The arena is append-only, so a
# reader that recovered the sink as `next - 4` would encode the fixture's node
# COUNT rather than its sink; carrying all three makes the offsets the builder's
# business and leaves the gate reading names.
type Fx is Data: Fx{ar: O.Arena, sink: U32, ctx: List<&2, U32>}

# Build the fixture: a SINK[PARAM{0}, PARAM{1}, ALLOC]. `ar` grows as we mint each
# node; the final `ar` carries the whole graph. `ctx` is [A, B, buf]: A and B are
# dummy PARAMs (slots 99 and 100) that the PARAM rule returns when the original
# node's slot is 0 or 1, and `buf` is a pre-minted BUFFER that the ALLOC rule
# returns. The engine cannot mint in a rule body (`pm_rewrite_m` consumes the
# arena and returns only a `Maybe`), so every rule replacement must be pre-minted
# and threaded through `ctx`. ONE build, because the arena is append-only: a
# second build would number the same nodes differently.
def fixture.graph() -> Fx:
  ar0 = O.Arena.empty()
  +p0 = test_param(ar0, 0)
  +p1 = test_param(O.Found.ar(p0), 1)
  +al = test_alloc(O.Found.ar(p1))
  +sk = fixture.sink(O.Found.ar(al), O.Found.i(p0), O.Found.i(p1), O.Found.i(al))
  +ca = ctx_param(O.Found.ar(sk), 99)
  +cb = ctx_param(O.Found.ar(ca), 100)
  +bf = test_buffer(O.Found.ar(cb))
  Fx{O.Found.ar(bf), O.Found.i(sk), [O.Found.i(ca), O.Found.i(cb), O.Found.i(bf)]}

def Fx.ar(f: Fx) -> O.Arena: match f: case Fx{ar, sink, ctx}: ar
def Fx.sink(f: Fx) -> U32: match f: case Fx{ar, sink, ctx}: sink
def Fx.ctx(f: Fx) -> List<&2, U32>: match f: case Fx{ar, sink, ctx}: ctx

# F2's rule table: the ALLOC rule of `pm_post_sched_cache` ALONE. It exists
# because CPython's `unified_rewrite` RAISES on F1 (IndexError at
# schedule/__init__.py:98, measured by `grw-oracle.py`), so without F2 the
# fixpoint arm would have no CPython expectation at all.
def pm_alloc_only() -> O.PMEntrys: O.PMEntrys{[O.PMEntry{4, [O.OpsALLOC{}], Nil{}}]}

# F2's sink: SINK[ALLOC]. One src, so `fixture.sink` (three) cannot build it.
def fixture.sink1(ar: O.Arena, a: U32) -> O.Found: O.UOp.sink(ar, [a])

# The ctx is [buf, buf, buf] and NOT [buf], because `pm_r_alloc_m` reads
# `ctx[2]` (`uop/ops.bend`, the arena-growth workaround this file's header
# records). A one-element ctx makes the rule answer `None{}` -- silently, with
# no error -- and the row then reads `ALLOC->ALLOC`, which is the shape of a
# rule that did not fire.
def fixture.alloc_only() -> Fx:
  ar0 = O.Arena.empty()
  +al = test_alloc(ar0)
  +sk = fixture.sink1(O.Found.ar(al), O.Found.i(al))
  +bf = test_buffer(O.Found.ar(sk))
  Fx{O.Found.ar(bf), O.Found.i(sk), [O.Found.i(bf), O.Found.i(bf), O.Found.i(bf)]}

def main.go(+f1: Fx, +f2: Fx) -> IO(Unit):
  do IO<Unit>:
    grw_rows.walk("f1", Fx.ar(f1), Fx.sink(f1), pm_post_sched_cache(), Fx.ctx(f1))
    grw_rows.fix("f1", Fx.ar(f1), Fx.sink(f1), pm_post_sched_cache(), Fx.ctx(f1))
    grw_rows.walk("f2", Fx.ar(f2), Fx.sink(f2), pm_alloc_only(), Fx.ctx(f2))
    grw_rows.fix("f2", Fx.ar(f2), Fx.sink(f2), pm_alloc_only(), Fx.ctx(f2))
    grw_rows.cap(Fx.ar(f1), Fx.sink(f1), pm_post_sched_cache(), Fx.ctx(f1))

def main() -> IO(Unit): main.go(fixture.graph(), fixture.alloc_only())
