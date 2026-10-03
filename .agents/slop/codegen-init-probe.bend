# tinybendygrad/codegen/__init__.bend -- the rows the port's OWN gate throws
# away, in a file of my own so the port's owner is not raced.
#
# WHY THIS FILE EXISTS. `codegen/__init__.bend`'s own header (its lines 46-50)
# says the top-down rule is tried on the REBUILT node, citing upstream
# `tinygrad/uop/ops.py` `walk_rewrite`. The code passes `u`. The port's single
# gate row prints one `OP(slot)->OP(slot)` pair per toposort node, and
# `gr_show.node` renders ANY SINK as the bare string "SINK" -- so upstream's
# REBUILT sink and the port's ORIGINAL sink print identically. The row is
# blind to the one invariant `ops.py:1810` turns on.
#
# THE VALUES HERE ARE CALLED, NOT TYPED. `.agents/slop/codegen-init-oracle.py`
# Q4 runs this same fixture through tinygrad's `walk_rewrite` and prints:
#
#     py.new_sink_is_original = 0
#     py.new_sink_srcs = PARAM(99),PARAM(100),BUFFER
#
# The two rows below are those two facts. Neither is reachable from the port's
# printed row under ANY behaviour.
#
# ROW 3, `gr.n_repl`, IS THE CONTROL: the number of `repl` entries, which is 4
# under every behaviour measured so far. A comment-only edit must leave it
# alone; if a control moves, the baseline moved and every other number in the
# comparison is suspect.
#
# `.agents/slop/unobservable-gr-probe.bend` prints only `gr.sink_srcs` and
# DEFINES `px.is_same` without ever calling it, so the identity fact -- the one
# that separates "returned the original" from "returned a rebuild" -- has no
# row anywhere in the tree. This file is where it gets one.

import Base
import ../../tinybendygrad/uop/ops.bend as O
import ../../tinybendygrad/codegen/__init__.bend as G
import ../../tinybendygrad/uop/render.bend as R
import ../../tinybendygrad/LAWS/spec.bend as S


# `gp.node` reads `u` twice (op, then arg), and a Bend `U32` parameter is
# single-read, so the arena read is threaded through two accessors -- the same
# shape `gr_show.node`/`gr_show.node.op`/`gr_show.node.arg` have in the port.
def gp.node.op(ar: O.Arena, u: U32) -> O.Op:
  O.Arena.op(ar, u)

def gp.node.arg(ar: O.Arena, u: U32) -> O.Arg:
  O.Arena.arg(ar, u)

def gp.node.of(ar: O.Arena, op: O.Op, arg: O.Arg) -> String:
  match arg:
    case O.AParam{pa}: String.concat([O.Ops.name.of(op), "(", U32.show(O.ParamArg.slot(pa)), ")"])
    case _: O.Ops.name.of(op)

def gp.node(+ar: O.Arena, +u: U32) -> String:
  gp.node.of(ar, gp.node.op(ar, u), gp.node.arg(ar, u))

def gp.srcs.go(+ar: O.Arena, t: List<&2, U32>, acc: String) -> String:
  match t:
    case Nil{}: acc
    case v <> rest: gp.srcs.go(ar, rest, String.concat([acc, gp.node(ar, v), ","]))

def gp.srcs.of(+ar: O.Arena, t: List<&2, U32>, first: String) -> String:
  gp.srcs.go(ar, t, String.concat([first, ","]))

def gp.srcs(+ar: O.Arena, srcs: List<&2, U32>) -> String:
  match srcs:
    case Nil{}: "-"
    case s <> t: gp.srcs.of(ar, t, gp.node(ar, s))

# ROW 1, THE IDENTITY. CPython: 0, because `ops.py:1810` mints a new UOp
# whenever a src was rewritten and the SINK's srcs were.
def gp.is_same.of(eq: Bool) -> String:
  match eq:
    case True{}: "1"
    case False{}: "0"

def gp.is_same(sink: U32, new_sink: U32) -> String:
  gp.is_same.of(U32.is_eq(sink, new_sink))

# ROW 2, THE SRCS of the node the engine hands back. CPython:
# PARAM(99),PARAM(100),BUFFER -- the REWRITTEN ones.
def gp.row.srcs(new_sink: U32) -> Maybe<&2, U32>:
  Some{new_sink}

# ROW 3, THE CONTROL. `R` is imported for `R.cu32` only; the count itself is
# the toposort length, which is 4 nodes for this fixture under every measured
# behaviour.
def gp.n(topo: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, topo))

# THE BEND NAMING RULE (R-3): a sub-def is declared BEFORE its caller.
def gp.print.r_same(sink: U32, new_sink: U32) -> IO(Unit):
  IO.print(String.concat(["gr.new_sink_is_original=", gp.is_same(sink, new_sink)]))

def gp.print.r_same.of(sink: U32, r: Maybe<&2, U32>) -> IO(Unit):
  match r:
    case Some{new_sink}: gp.print.r_same(sink, new_sink)
    case None{}: IO.print("gr.new_sink_is_original=NONE")

def gp.print.r_srcs(+ar: O.Arena, r: Maybe<&2, U32>) -> IO(Unit):
  match r:
    case Some{new_sink}: IO.print(String.concat(["gr.new_sink_srcs=", gp.srcs(ar, O.Arena.srcs(ar, new_sink))]))
    case None{}: IO.print("gr.new_sink_srcs=NONE")

def gp.print.r_op(+ar: O.Arena, r: Maybe<&2, U32>) -> IO(Unit):
  match r:
    case Some{new_sink}: IO.print(String.concat(["gr.new_sink_op=", gp.node(ar, new_sink)]))
    case None{}: IO.print("gr.new_sink_op=NONE")

def gp.print.r_n(topo: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat(["gr.n_repl=", U32.show(gp.n(topo))]))

def gp.print.all(+ar: O.Arena, sink: U32, +r: Maybe<&2, U32>, topo: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    gp.print.r_same.of(sink, r)
    gp.print.r_srcs(ar, r)
    gp.print.r_op(ar, r)
    gp.print.r_n(topo)

# `walk_rewrite` hands back the fold's GROWN arena with the sink, and the
# srcs row must be read out of THAT arena: an index is only meaningful in
# the arena that interned it, and `O.Arena.node` is total, so reading the
# rebuilt sink against the starting arena answers `NOOP` rather than failing.
def gp.main(topo: List<&2, U32>, sink: U32, p: (O.Arena & Maybe<&2, U32> & Map<&2, U32>)) -> IO(Unit):
  (ar, (r, _)) = p
  gp.print.all(ar, sink, r, topo)

def gp.main.of(topo: List<&2, U32>, +sink: U32, +ar: O.Arena, pm: O.PMEntrys, ctx: List<&2, U32>) -> IO(Unit):
  gp.main(topo, sink, G.walk_rewrite(ar, sink, pm, ctx))

def main() -> IO(Unit):
  # THE PORT'S OWN FIXTURE, rebuilt here so the probe does not have to reach into
  # another file's `main`: SINK[PARAM{0}, PARAM{1}, ALLOC], ctx =
  # [PARAM99, PARAM100, BUFFER].
  ar0 = O.Arena.empty()
  +p0 = G.test_param(ar0, 0)
  +p1 = G.test_param(O.Found.ar(p0), 1)
  +al = G.test_alloc(O.Found.ar(p1))
  +sk = G.fixture.sink(O.Found.ar(al), O.Found.i(p0), O.Found.i(p1), O.Found.i(al))
  +ca = G.ctx_param(O.Found.ar(sk), 99)
  +cb = G.ctx_param(O.Found.ar(ca), 100)
  +bf = G.test_buffer(O.Found.ar(cb))
  ctx: List<&2, U32> = [O.Found.i(ca), O.Found.i(cb), O.Found.i(bf)]

  gp.main.of(O.UOp.toposort(U32.to_nat(O.Arena.next(O.Found.ar(bf))), O.Found.ar(bf), O.Found.i(sk)),
            O.Found.i(sk), O.Found.ar(bf), G.pm_post_sched_cache(), ctx)
