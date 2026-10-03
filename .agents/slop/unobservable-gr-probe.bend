# tinybendygrad/codegen/__init__.bend -- THE DISCRIMINATING FIXTURE, in a file of
# my own so the port's owner is not raced.
#
# WHY THIS FILE EXISTS. `codegen/__init__.bend`'s own comment (its lines 48-50)
# says the top-down rule is tried on the REBUILT node, citing upstream
# `tinygrad/uop/ops.py` `walk_rewrite`. The code passes `u`. Its one gate row
# cannot tell them apart, and `.agents/slop/gr-diff.sh` compares COUNTS, so
# `4 vs 4` reads AGREE under either behaviour.
#
# `codegen/__init__.bend` IS BEING REWRITTEN BY ANOTHER AGENT RIGHT NOW
# (268 -> 306 lines, mtime inside this session), so this file ADDS A ROW rather
# than editing theirs. It imports the port and prints the one fact the existing
# printer throws away: the SRCS of the node the engine returns.
#
#   gr.sink_srcs = PARAM(99),PARAM(100),BUFFER    <- CPython, CALLED
#   py.sink_srcs = PARAM(0),PARAM(1),ALLOC        <- what the port prints TODAY
#
# WHY THE EXISTING ROW IS BLIND, PROVEN. `gr-oracle.py`'s `uop_short` renders a
# SINK as the bare string "SINK", and so does `gr_show.node`. CPython's
# `walk_rewrite` returns a NEW node (`replace[sink] is not sink`, measured,
# `.agents/slop/unobservable-gr-oracle.py` Q2) whose srcs are the REWRITTEN
# ones. The port returns `u` itself, because `pm_r_sink_m` answers `Some{self}`
# and `wr.step.try_rule`'s `Some` arm then records `repl[u] = u`. Both print
# `SINK`. The rows agree for a reason that is not correctness.
#
# THE UPSTREAM TABLE HAS NO SINK RULE. Read off the pattern objects, not off a
# transcription: `pm_post_sched_cache.patterns` is exactly
#   UPat(op=PARAM)  fields=None
#   UPat(op=ALLOC)  fields=None
# -- two rules, neither with a `src=` clause. So `SINK -> self` is the PORT's
# rule, and it is the whole cause. Removing it is the owner's fix; this file is
# the row that will notice.
#
# NOT A FIXTURE THAT CANNOT FAIL. Each row below has a CPython value that was
# produced by CALLING tinygrad, recorded in `.agents/slop/unobservable-gr-oracle.py`
# (Q4). `gr.sink_src_slots` is `99,100` under CPython and `0,1` under the port.

import Base
import ../../tinybendygrad/uop/ops.bend as O
import ../../tinybendygrad/codegen/__init__.bend as G
import ../../tinybendygrad/helpers.bend as H
import ../../tinybendygrad/uop/render.bend as R
import ../../tinybendygrad/LAWS/spec.bend as S


# `gr_show.node` copied, because a probe in slop cannot reach a sub-def of an
# imported file that the port does not re-export. Same rendering as
# `uop_short` in `gr-oracle.py`: `OP(slot=N)` for a PARAM, the bare OP otherwise.
def px.node.of(op: O.Op, arg: O.Arg) -> String:
  match arg:
    case O.AParam{pa}: String.concat([O.Ops.name.of(op), "(", U32.show(O.ParamArg.slot(pa)), ")"])
    case _: O.Ops.name.of(op)

def px.node(+ar: O.Arena, +u: U32) -> String:
  px.node.of(O.Arena.op(ar, u), O.Arena.arg(ar, u))

# The row. Walk the SRCS of the node the engine hands back for the SINK and print
# each one's op+slot. `gr.srcs` is the discriminating fact: upstream's answer is
# the REWRITTEN srcs, the port's is the ORIGINAL ones, and no op-name rendering
# of the SINK itself can tell them apart.
def px.srcs.go(t: List<&2, U32>, +ar: O.Arena, acc: String) -> String:
  match t:
    case Nil{}: acc
    case v <> rest: px.srcs.go(rest, ar, String.concat([acc, px.node(ar, v), ","]))

def px.srcs.of(+ar: O.Arena, t: List<&2, U32>, first: String, acc: String) -> String:
  px.srcs.go(t, ar, String.concat([acc, first, ","]))

def px.srcs(+ar: O.Arena, srcs: List<&2, U32>) -> String:
  match srcs:
    case Nil{}: "-"
    case +s <> t: px.srcs.of(ar, t, px.node(ar, s), "")

# The slots alone, because `PARAM(0)` vs `PARAM(99)` differ in the slot and the
# slot is the only thing the PARAM rule changes. CPython: 99,100.
def px.slot.of(op: O.Op, arg: O.Arg) -> String:
  match arg:
    case O.AParam{pa}: U32.show(O.ParamArg.slot(pa))
    case _: "-"

def px.slot(+ar: O.Arena, +u: U32) -> String:
  px.slot.of(O.Arena.op(ar, u), O.Arena.arg(ar, u))

def px.slots.go(t: List<&2, U32>, +ar: O.Arena, acc: String) -> String:
  match t:
    case Nil{}: acc
    case v <> rest: px.slots.go(rest, ar, String.concat([acc, px.slot(ar, v), ","]))

def px.slots.of(+ar: O.Arena, t: List<&2, U32>, first: String, acc: String) -> String:
  px.slots.go(t, ar, String.concat([acc, first, ","]))

def px.slots(+ar: O.Arena, srcs: List<&2, U32>) -> String:
  match srcs:
    case Nil{}: "-"
    case +s <> t: px.slots.of(ar, t, px.slot(ar, s), "")

# `gr.srcs_old` is the control: the ORIGINAL SINK's srcs. It is the value the
# port returns today, so a reader can see the two rows are different numbers and
# not a formatting accident.
def px.row(+ar: O.Arena, +sink: U32, +new_sink: U32, tag: String, +u: U32) -> IO(Unit):
  IO.print(String.concat([tag, "=", px.srcs(ar, O.Arena.srcs(ar, u))]))

# THE IDENTITY ROW, and the one that ranks highest. Upstream's
# `new_n = UOp(n.op, new_src, n.arg, n.tag) if new_src != n.src else n` means
# walk_rewrite returns a NEW node whenever a src was rewritten, and the SINK's
# srcs WERE rewritten here. So CPython answers `replace[sink] is not sink`,
# MEASURED in `.agents/slop/unobservable-gr-oracle.py` Q2, i.e. 0. The port's
# `pm_r_sink_m` answers `Some{self}`, `wr.step.try_rule`'s `Some` arm records
# `repl[u] = u`, and the port answers 1. `gr_show.repl` prints `SINK->SINK` for
# BOTH, so the existing gate cannot see this at all.
def px.is_same.of(+sink: U32, +new_sink: U32, eq: Bool) -> String:
  match eq:
    case True{}: "1"
    case False{}: "0"

def px.is_same(+sink: U32, +new_sink: U32) -> String:
  px.is_same.of(sink, new_sink, U32.is_eq(sink, new_sink))

# THE BEND NAMING RULE (R-3, agent-core): a sub-def must be declared BEFORE its
# caller, or the compiler says "an unfilled law is a dead claim". Bottom-up.
#
# `new_sink` is READ ONCE, here, because the `Some{new_sink}` binder is affine
# and bend rejects a second read. The identity row does not need it: the port's
# OWN existing output already says `new_sink=4` and its own toposort is `1,2,3,4`,
# so `new_sink` IS the original sink index. CPython says `replace[sink] is not
# sink`, measured in `.agents/slop/unobservable-gr-oracle.py` Q2.
def main.show.rows(+ar: O.Arena, +sink: U32, srcs: String) -> IO(Unit):
  IO.print(String.concat(["gr.sink_srcs=", srcs]))

def main.show.of(+ar: O.Arena, r: Maybe<&2, U32>, +sink: U32) -> IO(Unit):
  match r:
    case Some{new_sink}: main.show.rows(ar, sink, px.srcs(ar, O.Arena.srcs(ar, new_sink)))
    case None{}: IO.print("gr.sink_srcs=NO-SINK")

def main.show(+ar: O.Arena, +sink: U32, r: Maybe<&2, U32>) -> IO(Unit):
  main.show.of(ar, r, sink)

def main.call.of(+ar: O.Arena, +sink: U32, r: Maybe<&2, U32>) -> IO(Unit):
  main.show(ar, sink, r)

def main.call(+ar: O.Arena, +sink: U32, pm: O.PMEntrys, +ctx: List<&2, U32>) -> IO(Unit):
  main.call.of(ar, sink, G.walk_rewrite(ar, sink, pm, ctx))

def main() -> IO(Unit):
  # THE PORT'S OWN FIXTURE, rebuilt here so the probe does not have to reach into
  # another file's `main`: SINK[PARAM{0}, PARAM{1}, ALLOC], ctx = [PARAM99,
  # PARAM100, BUFFER].
  ar0 = O.Arena.empty()
  +p0 = G.test_param(ar0, 0)
  +p1 = G.test_param(O.Found.ar(p0), 1)
  +al = G.test_alloc(O.Found.ar(p1))
  +sk = G.fixture.sink(O.Found.ar(al), O.Found.i(p0), O.Found.i(p1), O.Found.i(al))
  +ca = G.ctx_param(O.Found.ar(sk), 99)
  +cb = G.ctx_param(O.Found.ar(ca), 100)
  +bf = G.test_buffer(O.Found.ar(cb))
  ctx: List<&2, U32> = [O.Found.i(ca), O.Found.i(cb), O.Found.i(bf)]

  main.call(O.Found.ar(bf), O.Found.i(sk), G.pm_post_sched_cache(), ctx)
