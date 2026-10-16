# graphcmp-dbg.bend -- THE PORT SIDE OF THE DEBUG-LEVEL COMPARISON.
#
# WHAT THIS IS. `.agents/slop/graphcmp.py dbg --levels 0,1,2` runs THIS file once per
# level, with `DEBUG` the only difference between the runs, and diffs the emitted rows
# with the SAME differ that diffs two graphs. A difference in what the port PRINTS at
# level 1 against level 2 is then a first-class diff naming a row, instead of something a
# reader compares by eye across two dumps.
#
# THE ONE RULE THAT MAKES THE COMPARISON MEANINGFUL, and it is why the graph is built
# HERE and not by the caller: `DEBUG` CHANGES CONTROL FLOW. Every one of the seven gated
# sites is `if DEBUG >= N: print(...)`, so asking for a graph at level 2 and a DIFFERENT
# graph at level 0 would be comparing two different programs and calling the delta a
# defect. So this file builds ONE graph -- `GC.matmul_of`, the SAME def
# `graphcmp.py diff --graph matmul` reaches, IMPORTED rather than copied, because a
# second copy of a graph builder is a second thing to keep in step and a drift between
# the two would be invisible -- and the only thing that varies is `H.debug()`.
#
# AND IT IS CHECKED, NOT PROMISED. Every run prints the graph's OWN eight-field node rows
# ahead of the trace rows, and `graphcmp.py` DIGESTS them per level and refuses to
# compare (exit 2 -- a FAILURE, never a verdict) if two levels' digests differ. A guard
# nobody can see fire is a guard that does not work; this one is a printed digest the
# caller recomputes on every run.
#
# WHY THE TRACE IS EMITTED AS ROWS RATHER THAN PRINTED. The seven sites print free text.
# A free-text dump across two levels is exactly the "read it by eye" comparison this
# replaces, and it has no denominator: nobody can say how many lines were compared. Here
# each site is ONE row with a NAME, so the report can name it AND count it.
#
# THE SEVEN SITES, every one reached THROUGH THE REAL PORT FILE. `rg '^def
# (mem_dbg|red_dbg|sd_dbg|am_dbg)'` over this file must find nothing -- gating a copy of
# the thing under test is how one unit's mutation table reported 0 for all 30 of its
# entries.
#   1 memory.py:59      `DEBUG >= 1`  M.mem_dbg  -- THE ONLY LEVEL-1 SITE
#   2 allreduce.py:16   `DEBUG >= 2`  A.red_dbg
#   3 state.py:260      `DEBUG >= 2`  St.sd_dbg
#   4 amdev.py:185      `DEBUG >= 2`  AM.am_dbg_malformed_of
#   5 amdev.py:225      `DEBUG >= 2`  AM.am_dbg_boot_of
#   6 amdev.py:251      `DEBUG >= 2`  AM.am_dbg_ip_of
#   7 amdev.py:254      `DEBUG >= 2`  AM.am_dbg_final_of
# `thr_mem=1` against six `=2` is MEASURED, not typed: `.agents/slop/debug-gate.bend`'s
# `thr_rows()` computes each threshold by CALLING its own site, and a real run reads
# `thr_mem=1` at `.agents/slop/debug-gate-out.0.bd:51`. It is repeated as the trace rows'
# `depth` column here so the level-1 site is distinguishable from the six level-2 sites by
# the diff itself.
import Base
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/uop/fold.bend as F
import ./../../tinybendygrad/helpers.bend as H
import ./../../tinybendygrad/LAWS/spec.bend as S
import ./../../tinybendygrad/schedule/allreduce.bend as A
import ./../../tinybendygrad/schedule/memory.bend as M
import ./../../tinybendygrad/nn/state.bend as St
import ./../../tinybendygrad/runtime/support/am/amdev.bend as AM
import ./graphcmp.bend as GC

# ===========================================================================
# THE GRAPH'S OWN ROWS. `GC.rows.of` is the printer `graphcmp.py diff` reads, so the
# digest the caller computes here is a digest of THE SAME TEXT the graph diff compares --
# not of a second rendering that could differ from it.
# ===========================================================================
# THE `+` ON `x` IS LOAD-BEARING AND MEASURED. `F.Folded.ar(x)` and `F.Folded.t(x)` are
# two reads of one binder, and a bare `do IO` bind is single-use: MEASURED, dropping the
# `+` is "expected : x / observed : x (consumed more than once)". It is the same spelling
# `graphcmp.bend`'s own `main` uses, which is why it is written here rather than invented.
def graph_rows(+r: O.Found) -> IO(Unit):
  do IO<Unit>:
    +x : F.Folded <- IO.pure(F.Folded, F.folded(O.Found.ar(r)))
    _ : Unit <- GC.rows.of(F.Folded.ar(x), F.Folded.t(x), r)
    IO.print("")

# ===========================================================================
# A TRACE ROW, in the same eight-chunk wire as a node row, so the SAME reader and the
# SAME differ take it:
#
#   <id> SITE N N <depth=threshold> N <arg=s<site>|<text at this level>> n()
#
# `id` is the site POSITION in the emission order and the walk carries it, so there is no
# "find this name's index" def at all. The first version had one and it cost three
# compile cycles for a measured reason worth recording: `Bool.pick(T, c, k, f(k))` reads
# `k` TWICE ("consumed more than once") even though `Bool.pick` chooses an arm, and a
# `match` cannot scrutinise a local binder ("give it its own def"), so the natural
# spellings are both refused. Carrying the counter needs neither.
#
# `depth` is the site's THRESHOLD and it is level-INDEPENDENT, which is the point: it is
# part of the row that must NOT move, so a row whose only difference is its `arg` is a row
# whose GATE moved and not a row whose FIXTURE did -- and `thr_mem=1` against six `i2`s
# is what separates the one level-1 site from the six level-2 sites inside the diff
# itself. `dtype`/`shape`/`tag` are `N` because a printed line has none, and emitting
# anything else there would be a value with no reader.
#
# `src` IS `n()` AND NOT AN EDGE TO THE GRAPH'S ROOT, and the reason is worth recording
# because the edge was tried first. An edge `n(<root>)` names a node that lives in the
# OTHER row set -- the graph rows -- so the trace row set is not a CLOSED graph, and
# `build` rightly refuses a dangling child: MEASURED, the DEBUG lane died with "DEBUG0:
# node 1 names an unknown child 18". The graph-to-trace binding is therefore the printed
# DIGEST over the graph rows, which `graphcmp.py` recomputes per level and refuses to
# compare on (exit 2). A digest the reader can check beats an edge the reader has to
# resolve through two row sets.
# ===========================================================================
def trow(ix: U32, nm: String, thr: U32, txt: String) -> IO(Unit):
  IO.print(String.concat([GC.chunk(GC.i(ix)), " ", GC.chunk("SITE"), " ", GC.chunk("N"), " ",
    GC.chunk("N"), " ", GC.chunk(GC.i(thr)), " ", GC.chunk("N"), " ",
    GC.chunk(String.concat(["s", nm, "|", txt])), " ", GC.chunk("n()")]))

# ===========================================================================
# THE SEVEN SITES, one def each, in the order the report numbers them. The fixtures are
# `.agents/slop/debug-gate.bend`'s, which are the ones CPython was asked the same
# questions about (its `laneA_*` oracles) -- so a level-2 text here and a level-2 text
# there are two implementations of ONE printed line rather than two fixtures.
# ===========================================================================
def s_mem(d: U32) -> String: M.mem_dbg(d, M.mem_plan(M.proj_of()))
def s_ar(d: U32) -> String: A.red_dbg(d, A.red_sel(A.red_sh1(300000), 4, A.Cfg{1, 0, 256000, 0, True{}}), 4, 300000, S.single())
def s_st(d: U32) -> String: St.sd_dbg(d, "posixpath", "join")
def s_am185(d: U32) -> String: AM.am_dbg_malformed_of(d, "0000:01:00.0")
def s_am225(d: U32) -> String: AM.am_dbg_boot_of(d, "0000:01:00.0")
def s_am251(d: U32) -> String: AM.am_dbg_ip_of(d, "0000:01:00.0", "AM_GFX")
def s_am254(d: U32) -> String: AM.am_dbg_final_of(d, "0000:01:00.0")

# ONE WALK over four parallel lists, rather than seven `IO.print` lines: seven prints is
# seven chances to write the site name in one column and the threshold in another, and the
# whole point of the row is that the name and the threshold travel TOGETHER. `k` is the
# emission-order index and `n` the remaining count; both are read once per arm, which is
# the shape Bend accepts (see `trow`'s note on `Bool.pick` reading an argument twice).
# `ns` COMES FIRST IN THE SIGNATURE and the ORDER IS LOAD-BEARING, measured: a self-call's
# arguments are read LEFT TO RIGHT and each must be passed UNCHANGED until one SHRINKS.
# `ix` GROWS, so with `ix` first the call is refused as "expected : a decreasing self-call";
# putting `ns` first makes its own tail `ns2` the first shrink and every later argument is
# then free to change. The three `Nil{}` arms are the termination and there is no fuel
# counter: a second bound that must agree with the lists is a second thing that can be
# wrong, and MEASURED bend will not let a nested `match` re-scrutinise the parameter the
# enclosing `match` was written over ("this name is a def or a consumed binder") anyway.
def s_sites.go(ns: List<&2, String>, thrs: List<&2, U32>, txts: List<&2, String>,
               +ix: U32) -> IO(Unit):
  match ns thrs txts:
    case Nil{} _ _: IO.pure(Unit, Unit{})
    case _ Nil{} _: IO.pure(Unit, Unit{})
    case _ _ Nil{}: IO.pure(Unit, Unit{})
    case n1 <> ns2 t <> ts2 x <> xs2:
      do IO<Unit>:
        _ : Unit <- trow(ix, n1, t, x)
        s_sites.go(ns2, ts2, xs2, U32.add(ix, 1))

def s_sites(+d: U32) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- s_sites.go(["mem", "ar", "st", "am185", "am225", "am251", "am254"],
      [1, 2, 2, 2, 2, 2, 2],
      [s_mem(d), s_ar(d), s_st(d), s_am185(d), s_am225(d), s_am251(d), s_am254(d)], 1)
    IO.print("")

# `H.debug()` IS `IO(U32)` (helpers.bend:307), so it is BOUND in the `do` and not called
# as an argument: passing it as one is "expected : U32 / observed : ... -> IO.OP<R>". And
# it must be a bare `d : U32 <-` bind, not `+d` -- MEASURED in debug-gate.bend's own
# header, `+d <- H.debug()` is refused with "expected : a bound variable". It is read
# ONCE, which is what makes the level a property of the ENVIRONMENT rather than of a
# parameter, so the only thing that differs between two runs is what the caller set.
def main() -> IO(Unit):
  +r = GC.matmul_of(O.Arena.empty())
  do IO<Unit>:
    d : U32 <- H.debug()
    _ : Unit <- graph_rows(r)
    _ : Unit <- s_sites(d)
    IO.print("")