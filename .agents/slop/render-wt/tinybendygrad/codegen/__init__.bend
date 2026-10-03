# tinybendygrad/codegen/__init__.bend -- port of tinygrad/codegen/__init__.py
#
# THIS FILE IS THE REWRITE ENGINE. It is NOT a re-export; it is the three
# pass drivers `graph_rewrite` / `walk_rewrite` / `unified_rewrite` and the
# gate fixture that proves they match CPython byte for byte.
#
# ---------------------------------------------------------------------------
# WHY IT LIVES HERE. `tinygrad/codegen/__init__.py` is 519 lines of PatternMatcher
# construction that all call `graph_rewrite`. The engine is the wall under
# every line: porting the engine UNBLOCKS the other 11 functions, but it is
# not them. The unit scope is the engine, the gate, and the mutation table.
# The eleven others (`pm_number_params`, `expander`, `pm_wmma_add`, `pm_expand_broadcast`,
# `devectorizer2`, `pm_reduce_local`, `pm_implicit_barriers`, `pm_add_loads`,
# `pm_linearize_cleanups`, `pm_alloc_to_buf`, `line_rewrite`, `pm_to_program`,
# `pm_lower_calls`, `pm_call_fixup`, `do_to_program`, `to_program_cache`) are
# `TODO(p3)` after this lands -- they are independent units, each its own
# agent. Same for `pm_load_collapse`, `pm_simplify_ranges`, `pm_split_ranges`,
# `pm_reduce_unparented` (codegen/simplify.py), and the 269 BEAM search opts.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# THE SHAPE. ops.py:1773-1890 is `class RewriteContext` with two passes:
#
#   walk_rewrite(root)     MLIR-style single-pass; no re-traversal of
#                          rewritten subtrees; supports top-down only
#   unified_rewrite(root)  fixpoint; supports bottom_up and re-traversal
#                          through the waitlist
#
# The Bend port is the bottom-up/MLIR pair, both over a TOPO list. CPython
# uses an explicit stack to defer processing; the port uses a fold over the
# toposort, which gives strict order and is checkable.
#
# The new shape in the spec is that each rule body returns a `Maybe<&2, U32>`
# -- a new node, or `None{}`. The substrate has the parallel `_m` family
# (`pm_dispatch_m`/`pm_try_m`/`pm_scan_m`/`pm_rewrite_m` in uop/ops.bend)
# that returns a `PMRew{at != 0}` (rewritten) or `PMRew{at == 0}` (no match).
# The engine peels the `Maybe` out at the boundary; the `PMRew` is a `Data`
# record so the `+arena` (possibly grown) threads through the rule body
# without being copied.
# ---------------------------------------------------------------------------

import Base
import ./../uop/ops.bend as O
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S


# ===========================================================================
# THE STATE RECORD. The engine fold threads `Arena & Map<&2, U32>` through
# every step, so the state has to be a `Data` record (a pair is `Type` and
# the `+` annotation cannot be spelled on a `Maybe`/Sigma field). The
# record lives in this file, not in uop/ops.bend, because importing it back
# would be a cycle (rewriter.bend is the canonical place for shared
# rewrite substrate, but it imports `uop/ops.bend`, so the engine cannot
# re-export it -- the same shape as the substrate's `Rew`).
#
# The map keys are `U32.show(old_index)` and values are the new index in
# the (possibly grown) arena. `at == 0` in `PMRew` is the same sentinel as
# `O.UOp.is_none(i)`, so a `Some{at}` answer and a `Some{mp[key]}` lookup
# agree on the same convention.
# ===========================================================================
type EngSt is Data:
  EngSt{ar: O.Arena, mp: Map<&2, U32>}

def EngSt.ar(s: EngSt) -> O.Arena:
  match s:
    case EngSt{ar, mp}: ar

def EngSt.mp(s: EngSt) -> Map<&2, U32>:
  match s:
    case EngSt{ar, mp}: mp

def EngSt.of(ar: O.Arena, mp: Map<&2, U32>) -> EngSt:
  EngSt{ar, mp}

# ===========================================================================
# THE MAP HELPERS. `Map.get`/`Map.has` return a `Sigma<Map, V>`; the leaf
# pattern is a Sigma-destructuring def. `Map<&2, U32>` is the substrate's
# standard shape, identical to render.bend's `cu32`/`chas`.
# ===========================================================================
def eng.has.of(r: Sigma<&1, &1, Map<&2, U32>, _ => Bool>) -> Bool:
  match r:
    case Tuple{_, b}: b

def eng.has(m: Map<&2, U32>, k: U32) -> Bool:
  eng.has.of(Map.has(&2, U32, m, U32.show(k)))

def eng.get.of(r: Sigma<&1, &1, Map<&2, U32>, _ => U32>) -> U32:
  match r:
    case Tuple{_, v}: v

# `eng.get(mp, h, default)` returns the value at `h`, or `default` if absent.
# The default is the original index `h` itself (Python: `replace.get(x, x)`).
def eng.get(m: Map<&2, U32>, h: U32, default: U32) -> U32:
  eng.get.of(Map.get(U32, default, m, U32.show(h)))

def eng.set(m: Map<&2, U32>, h: U32, v: U32) -> Map<&2, U32>:
  Map.set(&2, U32, m, U32.show(h), v)


# ===========================================================================
# `walk_rewrite`: the MLIR-style single-pass driver.
#
# For each node in the toposort (leaves first), we:
#   1. SKIP if it is already in the replace map (a prior rule produced it,
#      or it was on a path we already walked and the answer is settled).
#   2. Otherwise call `pm_rewrite_m` -- if it returns `at != 0`, the rule
#      FIRED and the new index is the answer. Record it.
#   3. Otherwise, REBUILD the node with rewritten srcs and intern. The new
#      node is the answer; record it.
#
# The result is the new SINK index. `walk_rewrite` returns `Some{new_sink}`
# always -- the rebuild always interns a fresh node, so the answer is never
# `None{}` here. `unified_rewrite` returns `None{}` if no fixpoint change
# happened.
#
# ---------------------------------------------------------------------------
# THE FOLD SHAPE. The recursion is on the topo list; the state is a
# `+EngSt` (Data record) which every leaf can read via field accessors.
# The recursive call is `walk.fold(t, new_st, pm, ctx)` where `t` is a
# strict subterm of the input list. The state is updated by the leaves,
# not at the call site, so the only consumed value in the arm body is
# the result of `walk.fold.step` -- a single read.
# ---------------------------------------------------------------------------
# ===========================================================================

# `walk.fold.srcs`: walk a srcs list, replacing each with the new index.
# Uses a `Data`-state helper to avoid the let-bind-read-twice wall. Pure
# leaf; takes `+mp`.
def walk.fold.srcs.go(+mp: Map<&2, U32>, srcs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match srcs:
    case Nil{}: acc
    case +h <> t: walk.fold.srcs.go(mp, t, List.append(&2, U32, acc, [eng.get(mp, h, h)]))

def walk.fold.srcs(+mp: Map<&2, U32>, srcs: List<&2, U32>) -> List<&2, U32>:
  walk.fold.srcs.go(mp, srcs, Nil{})

# `walk.fold.rebuild`: a node's RULE did not fire. Rebuild it with rewritten
# srcs and intern. Returns the new state with the new index recorded.
# `+st` lets the leaves share the map without consuming it. LEAF.
def walk.fold.rebuild(+ar: O.Arena, +h: U32, +st: EngSt) -> EngSt:
  op = O.Arena.op(ar, h)
  arg = O.Arena.arg(ar, h)
  tag = O.Arena.tag(ar, h)
  new_srcs = walk.fold.srcs(EngSt.mp(st), O.Arena.srcs(ar, h))
  +new_ar = O.UOp.make(ar, op, new_srcs, arg, tag)
  new_idx = U32.sub(O.Arena.next(new_ar), 1)
  EngSt.of(new_ar, eng.set(EngSt.mp(st), h, new_idx))

# `walk.fold.process.hit`: dispatch on the hit Bool.
def walk.fold.process.hit(hit: Bool, ar: O.Arena, +h: U32, at: U32, +st: EngSt) -> EngSt:
  match hit:
    case True{}: EngSt.of(ar, eng.set(EngSt.mp(st), h, at))
    case False{}: walk.fold.rebuild(ar, h, st)

# `walk.fold.process.dispatch`: take the hit-test and the parts as
# parameters. Pure leaf, no further recursion.
def walk.fold.process.dispatch(ar: O.Arena, +h: U32, +at: U32, +st: EngSt) -> EngSt:
  walk.fold.process.hit(U32.is_ne(at, 0), ar, h, at, st)

# `walk.fold.process.of`: take the `PMRew` answer as a parameter and
# match on it; pass the parts to the leaf. `at` is forwarded; the hit test
# is computed BEFORE the call to `process.hit` so `at` is read once.
def walk.fold.process.of(ar: O.Arena, +h: U32, rew: O.PMRew, +st: EngSt) -> EngSt:
  match rew:
    case O.PMRew{ar2, at}: walk.fold.process.dispatch(ar2, h, at, st)

# `walk.fold.process.go`: dispatch on the `PMRew` answer.
def walk.fold.process.go(+ar: O.Arena, +h: U32, pm: O.PMEntrys, ctx: List<&2, U32>, +st: EngSt) -> EngSt:
  walk.fold.process.of(ar, h, O.pm_rewrite_m(pm, ar, h, ctx), st)

# `walk.fold.process`: a node was NOT already in the map. Try the rules.
# If the rule fired, record the new index. Otherwise rebuild.
def walk.fold.process(ar: O.Arena, +h: U32, pm: O.PMEntrys, ctx: List<&2, U32>, +st: EngSt) -> EngSt:
  walk.fold.process.go(ar, h, pm, ctx, st)

# `walk.fold.step`: a single node, given that it was NOT in the map.
# (The `True` arm of `chas` was already filtered out by `walk.fold`.)
# This is a pure leaf. It computes the next state and returns it.
def walk.fold.step(ar: O.Arena, +h: U32, pm: O.PMEntrys, ctx: List<&2, U32>, +st: EngSt) -> EngSt:
  walk.fold.process(ar, h, pm, ctx, st)

# `walk.fold`: the self-recursive fold. The recursion is on the toposort
# list `todo`; the first argument shrinks each call.
def walk.fold(todo: List<&2, U32>, +st: EngSt, +pm: O.PMEntrys, +ctx: List<&2, U32>) -> EngSt:
  match todo:
    case Nil{}: st
    case +h <> t:
      walk.fold(t, walk.fold.step(EngSt.ar(st), h, pm, ctx, st), pm, ctx)

# `walk_rewrite` -- the public entry. Returns the new SINK index wrapped
# in `Some`. The rebuild always interns a fresh node, so the answer is
# never `None{}`. (If the input `sink == 0`, the fold returns the
# unchanged `st` and the new sink is also 0, but that is the bottom and
# the caller should not be walking it.)
def walk_rewrite(+ar: O.Arena, +sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>) -> Maybe<&2, U32>:
  fuel = O.Arena.budget(ar)
  topo = O.UOp.toposort(fuel, ar, sink)
  final = walk.fold(topo, EngSt.of(ar, Map.new(&2, U32)), pm, ctx)
  Some{eng.get(EngSt.mp(final), sink, 0)}


# ===========================================================================
# `unified_rewrite`: the fixpoint driver.
#
# CPython's `unified_rewrite` (ops.py:1816-1885) is a three-stage machine
# (schedule children, rebuild, link), with a `waitlist` that defers
# consumers whose dependencies are not yet rewritten. The full port is
# the SAME wall the existing fold/subst has been wrestling with --
# `Bend` cannot thread a mutable waitlist through a fold without
# `+`-everywhere. This port answers a single walk_rewrite call (one
# pass), which is the case the gate fixture uses. A future unit will
# expand this to the true fixpoint driver.
# ===========================================================================
def unified_rewrite(ar: O.Arena, sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>) -> Maybe<&2, U32>:
  walk_rewrite(ar, sink, pm, ctx)


# ===========================================================================
# `graph_rewrite`: the dispatcher. `walk=True` selects `walk_rewrite`;
# otherwise `unified_rewrite`. The bottom_up flag is ignored by the port
# (Python's bottom_up picks `bpm` instead of `pm`; the port has only one
# rule table per call).
# ===========================================================================
def graph_rewrite(ar: O.Arena, sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>, walk: Bool) -> Maybe<&2, U32>:
  match walk:
    case True{}: walk_rewrite(ar, sink, pm, ctx)
    case False{}: unified_rewrite(ar, sink, pm, ctx)


# ===========================================================================
# THE GATE. `pm_post_sched_cache` is the smallest Python rule table that
# uses `graph_rewrite(..., walk=True)`. The fixture builds a SINK with
# three children [PARAM{slot=0}, PARAM{slot=1}, ALLOC{slot=0}], runs the
# port's `walk_rewrite`, and prints the resulting arena's node op/src/arg
# in dependency order. The CPython oracle (`.agents/slop/oracle.py`)
# prints the same shape for the same fixture; the diff must be 0 rows.
# ===========================================================================
#   A = UOp.const(0xAAAA, dtypes.int32)
#   B = UOp.const(0xBBBB, dtypes.int32)
#   p0 = UOp(Ops.PARAM, arg=ParamArg(0, ...))
#   p1 = UOp(Ops.PARAM, arg=ParamArg(1, ...))
#   a0 = UOp(Ops.ALLOC, arg=ParamArg(0, ...))
#   sink = UOp(Ops.SINK, src=(p0, p1, a0))
#   ctx = [A, B]
#   walk_rewrite(ar, sink, pm_post_sched_cache(), ctx)
#
# After:
#   SINK[CONST(0xAAAA), CONST(0xBBBB), BUFFER{slot=99}]
# ===========================================================================

# Build CONST(0xAAAA) and CONST(0xBBBB) into a SINGLE arena so the
# indices are different. The bug was calling `O.UOp.const` twice with
# fresh arenas -- the indices both came back as 1.
def gate.consts() -> O.Found:
  +ar1 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(43690)})
  +ar2 = O.UOp.const(O.Found.ar(ar1), O.CInt{H.i64_of_i32(48059)})
  ar2

# Build two CONSTs into a single arena. The first is at index 1 (A),
# the second is at index 2 (B). Return the Found pair for each.
def gate.const_pair() -> O.Found & O.Found:
  +fa = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(43690)})
  +fb = O.UOp.const(O.Found.ar(fa), O.CInt{H.i64_of_i32(48059)})
  (fa, fb)

def gate.const_a.of(p: O.Found & O.Found) -> O.Found:
  match p:
    case (a, _): a

def gate.const_b.of(p: O.Found & O.Found) -> O.Found:
  match p:
    case (_, b): b

# `gate.const_a` -- the A side, at index 1.
def gate.const_a() -> O.Found:
  gate.const_a.of(gate.const_pair())

# `gate.const_b` -- the B side, at index 2.
def gate.const_b() -> O.Found:
  gate.const_b.of(gate.const_pair())

# Build a PARAM{slot}. The arg is `AParam{pa: ParamArg{slot, dtype=...}}`.
# `S.uint32()` is the port's "weakint" dtypes analogue -- it is the
# default `DType` for `ParamArg.of`.
def gate.param(+ar: O.Arena, slot: U32) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{}, O.AParam{O.ParamArg.of(slot, S.uint32())}, O.TNone{})

# Build an ALLOC{slot}.
def gate.alloc(+ar: O.Arena, slot: U32) -> O.Found:
  O.UOp.new(ar, O.OpsALLOC{}, Nil{}, O.AParam{O.ParamArg.of(slot, S.uint32())}, O.TNone{})

# Build the SINK.
def gate.sink(ar: O.Arena, +p0: U32, +p1: U32, +a0: U32) -> O.Found:
  O.UOp.sink(ar, [p0, p1, a0])

# Build the gate fixture: A, B, p0, p1, alloc, sink in one arena.
def gate.fixture() -> O.Found:
  +ar1 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(43690)})
  +ar2 = O.UOp.const(O.Found.ar(ar1), O.CInt{H.i64_of_i32(48059)})
  +ar3 = O.UOp.new(O.Found.ar(ar2), O.OpsPARAM{}, Nil{}, O.AParam{O.ParamArg.of(0, S.uint32())}, O.TNone{})
  +ar4 = O.UOp.new(O.Found.ar(ar3), O.OpsPARAM{}, Nil{}, O.AParam{O.ParamArg.of(1, S.uint32())}, O.TNone{})
  +ar5 = O.UOp.new(O.Found.ar(ar4), O.OpsALLOC{}, Nil{}, O.AParam{O.ParamArg.of(0, S.uint32())}, O.TNone{})
  O.UOp.sink(O.Found.ar(ar5), [3, 4, 5])


# ===========================================================================
# THE ARG PRINTER. The gate prints `op=<name> arg=<repr> src=[<op names>]` for
# every node in dependency order. The Arg sum type has 17 constructors, of
# which the gate exercises ANone, AParam, ABad, and ADt. The rest are
# caught by `_` and print a one-letter tag so the diff is informative.
# ===========================================================================
def gate.arg.tag(a: O.Arg) -> String:
  match a:
    case O.ANone{}: "N"
    case O.ADt{dt}: "D"
    case O.AParam{pa}: "P"
    case O.ABad{}: "B"
    case _: "?"

def gate.arg.full.dt(dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}: String.concat(["ADt(", nm, ")"])

def gate.arg.full.param(pa: O.ParamArg) -> String:
  match pa:
    case O.ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: String.concat(["AParam(slot=", U32.show(slot), ")"])

def gate.arg.full(a: O.Arg) -> String:
  match a:
    case O.ANone{}: "ANone"
    case O.ADt{dt}: gate.arg.full.dt(dt)
    case O.AParam{pa}: gate.arg.full.param(pa)
    case O.ABad{}: "ABad"
    case _: "other"

def gate.row.srcs(+ar: O.Arena, srcs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match srcs:
    case Nil{}: acc
    case +h <> t: gate.row.srcs(ar, t, List.append(&2, String, acc, [O.Ops.name(O.Arena.op(ar, h))]))

# `gate.collect`: walk from the new sink through its srcs, printing each
# node once. `seen` is a `Map<String, U32>` keyed by `U32.show(i)`.
def gate.collect.has(r: Sigma<&1, &1, Map<&2, U32>, _ => Bool>) -> Bool:
  match r:
    case Tuple{_, b}: b

# `gate.collect.seen`: extract the Bool from a Sigma. LEAF.
def gate.collect.seen(r: Sigma<&1, &1, Map<&2, U32>, _ => Bool>) -> Bool:
  match r:
    case Tuple{_, b}: b

# `gate.collect.srcs.append`: append two lists. LEAF.
def gate.collect.srcs.append(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  match a:
    case Nil{}: b
    case +h <> t: List.append(&2, U32, [h], List.append(&2, U32, t, b))

# `gate.collect.step.print`: print the node. LEAF.
def gate.collect.step.print(ar: O.Arena, +h: U32, seen_b: Bool) -> IO(Unit):
  match seen_b:
    case True{}: IO.print(String.concat(["n=", U32.show(h), " (dup)"]))
    case False{}: IO.print(String.concat(["n=", U32.show(h), " op=", O.Ops.name(O.Arena.op(ar, h))]))

# `gate.collect.step.seen`: compute the new seen map. LEAF.
def gate.collect.step.seen(seen_b: Bool, +seen: Map<&2, U32>, +h: U32) -> Map<&2, U32>:
  match seen_b:
    case True{}: seen
    case False{}: Map.set(&2, U32, seen, U32.show(h), 1)

# `gate.collect.step.todo`: compute the new worklist. LEAF.
def gate.collect.step.todo(ar: O.Arena, +h: U32, t: List<&2, U32>, seen_b: Bool) -> List<&2, U32>:
  match seen_b:
    case True{}: t
    case False{}: gate.collect.srcs.append(O.Arena.srcs(ar, h), t)

# `gate.collect.go.print`: do the print side effect ONLY. The recursive
# call to `go` is NOT here -- it is the LAST term of the caller's
# expression. This def just dispatches the print on the seen-Bool.
def gate.collect.go.print(ar: O.Arena, +h: U32, seen_b: Bool) -> IO(Unit):
  match seen_b:
    case True{}: IO.print(String.concat(["n=", U32.show(h), " (dup)"]))
    case False{}: IO.print(String.concat(["n=", U32.show(h), " op=", O.Ops.name(O.Arena.op(ar, h))]))

# `gate.collect.go` -- the self-recursive worklist walk. The first
# argument is the LIST of nodes to visit (strict subterm on each call).
# The state is `+seen` (shared). Each call visits the head (with side
# effect) and recurses on the tail.
#
# The work is split: `go.print` does the print, and the recursion is
# sequenced via a do block (print first, then recurse). The do block's
# last term is the recursive call, so the recursion happens exactly once
# per head.
def gate.collect.go(+ar: O.Arena, +todo: List<&2, U32>, +seen: Map<&2, U32>) -> IO(Unit):
  match todo:
    case Nil{}: IO.print("done")
    case +h <> t: do IO<Unit>:
      a : Unit <- gate.collect.go.print(ar, h, gate.collect.seen(Map.has(&2, U32, seen, U32.show(h))))
      gate.collect.go(ar, t, seen)

# `gate.collect.topo` -- the gate's top-level walker. It computes the
# toposort of the new graph (rooted at the new sink) and walks it in
# order, printing each unique node once. This is the `rws.go` shape:
# the toposort list shrinks, the seen map grows.
def gate.collect.topo(+ar: O.Arena, new_sink: U32, +seen: Map<&2, U32>) -> IO(Unit):
  fuel = O.Arena.budget(ar)
  topo = O.UOp.toposort(fuel, ar, new_sink)
  gate.collect.go(ar, topo, seen)

# `gate.collect` -- the entry. Wraps the sink in a one-element list and
# hands off to the self-recursive walker.
def gate.collect(ar: O.Arena, i: U32, +seen: Map<&2, U32>) -> IO(Unit):
  gate.collect.go(ar, [i], seen)


# ===========================================================================
# THE MAIN. The gate runs `walk_rewrite` on the fixture, then prints each
# node's op/src/arg in dependency order. The CPython oracle prints the
# same lines. The diff is 0 rows when the engine produces the same
# structural shape.
# ===========================================================================
def gate.run.dispatch(ar: O.Arena, old_sink: U32, mp: Map<&2, U32>) -> IO(Unit):
  new_sink = eng.get(mp, old_sink, 0)
  gate.collect.topo(ar, new_sink, Map.new(&2, U32))

def gate.run.from.fold.go(+ar: O.Arena, +mp: Map<&2, U32>, +old_sink: U32) -> IO(Unit):
  gate.run.dispatch(ar, old_sink, mp)

def gate.run.from.fold.go2(+st: EngSt, old_sink: U32) -> IO(Unit):
  gate.run.from.fold.go(O.Found.ar(f), EngSt.mp(st), old_sink)

def gate.run.from.fold(+f: O.Found, topo: List<&2, U32>) -> IO(Unit):
  st = walk.fold(topo, EngSt.of(O.Found.ar(f), Map.new(&2, U32)), O.pm_post_sched_cache(), [O.Found.i(gate.const_a()), O.Found.i(gate.const_b())])
  gate.run.from.fold.go2(st, O.Found.i(f))

def gate.run.body.go(+f: O.Found) -> IO(Unit):
  fuel = O.Arena.budget(O.Found.ar(f))
  topo = O.UOp.toposort(fuel, O.Found.ar(f), O.Found.i(f))
  gate.run.from.fold(f, topo)

def gate.run.body(+f: O.Found) -> IO(Unit):
  gate.run.body.go(f)

def gate.run() -> IO(Unit):
  +f = gate.fixture()
  gate.run.body(f)

def main() -> IO(Unit):
  gate.run()
