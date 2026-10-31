# .agents/slop/browser/arenas.bend -- WHICH ARENA IS `Lin.out` IN?
#
# **⇒ THE QUESTION, AND IT IS ONE ROW.** `kudump.bend` read the scheduler's
# kernel as `STORE(INDEX, PARAM)` -- a COPY, no arithmetic -- while `rr_dump` on
# the RANGEIFIED graph read `STORE:none:INDEX,REDUCE`. **⇒ AND `SCH.schedule`
# CONSUMES THE ARENA AND RETURNS A GROWN ONE** (`Lin{ar, ...}`), so the two
# readings may be of TWO DIFFERENT GRAPHS. **⇒ AND IF THEY ARE, MY OWN
# `fullchain` MEASUREMENT COMPARED THE WRONG PAIR.**
#
# **⇒ SO THIS FILE DUMP THE GRAPH **IN THE SCHEDULER's ARENA**, ROOTED AT THE
# KERNEL THE SCHEDULER SELECTED.** One dump, one arena, no translation.
#
# THREE ROWS, AND THE THIRD IS THE ONE THAT SETTLES IT:
#   A  `rr_dump` of the rangeified graph, in the RANGEIFYING arena  (the OLD one)
#   B  the scheduler's kernel OP and its SRC OPS                     (a fingerprint)
#   C  `rr_dump` of the scheduler's kernel, IN THE SCHEDULER's arena  (the NEW one)
#
# **⇒ AND B AND C ARE THE SAME QUESTION ASKED TWO WAYS, WHICH IS WHAT MAKES
# BOTH CHECKABLE**: if B says `STORE(INDEX,PARAM)` and C says the same, the
# reading is CONSISTENT and there is no cross-arena error. If they differ, the
# fingerprint was read out of the wrong arena and my earlier claim is retracted.
import Base
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/uop/ops.bend as O

def kd_op(+op: O.Op) -> String:
  O.Ops.name.of(op)

def ab_pick(outs: List<&2, U32>, ar: O.Arena) -> O.Found:
  match outs:
    case Nil{}: O.Found{ar, 0}
    case k <> _: O.Found{ar, k}

# (A) THE RANGEIFIED GRAPH, IN THE ARENA `rr_kernel_graph` ANSWERED IN.
def ab_ranged() -> String:
  +q = RZ.rz_built()
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  RR.rr_dump(O.Found.ar(kg), O.Found.i(kg))

# THE KERNEL, AS THE SCHEDULER LEFT IT: the arena that GREW, and the index.
def ab_sched() -> O.Found:
  +q = RZ.rz_built()
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +l = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  ab_pick(SCH.Lin.out(l), SCH.Lin.ar(l))

# (B) A FINGERPRINT: the kernel's op and its srcs' ops, one hop.
def ab_fp.go(+xs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: ab_fp.go(t, ar, List.append(&2, String, acc, [kd_op(SCH.sc_op(ar, x))]))

def ab_fp() -> String:
  +f = ab_sched()
  +ar = O.Found.ar(f)
  +k = O.Found.i(f)
  String.concat(["op=", kd_op(SCH.sc_op(ar, k)), " srcs=[",
                 String.join(ab_fp.go(SCH.sc_srcs(ar, k), ar, Nil{}), ","), "]"])

# (C) THE SAME GRAPH, DUMPED WITH THE PORT's OWN `rr_dump`, IN THE NEW ARENA.
# **⇒ AND `rr_dump` IS `rangify.bend`'s OWN DEF, CALLED UNMODIFIED** -- so this
# is not a second spelling of the dump.
def ab_dump_sched() -> String:
  +f = ab_sched()
  RR.rr_dump(O.Found.ar(f), O.Found.i(f))

# (D) AND THE COUNT: how many nodes each reading holds. A copy-store and a
# reduce-store are the same NODE COUNT, so a count alone cannot settle it --
# **⇒ AND IT IS PRINTED ANYWAY, BECAUSE A DIFFERENT COUNT WOULD SETTLE IT
# IMMEDIATELY.**
def ab_n_ranged() -> String:
  +q = RZ.rz_built()
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  U32.show(U32.from_nat(List.length(&2, U32,
    O.UOp.toposort(O.Arena.budget(O.Found.ar(kg)), O.Found.ar(kg), O.Found.i(kg)))))

def ab_n_sched() -> String:
  +f = ab_sched()
  U32.show(U32.from_nat(List.length(&2, U32,
    O.UOp.toposort(O.Arena.budget(O.Found.ar(f)), O.Found.ar(f), O.Found.i(f)))))

def ab_rows() -> List<&2, String>:
  [String.concat(["A_ranged_n=", ab_n_ranged()]),
   String.concat(["B_sched_n=", ab_n_sched()]),
   String.concat(["B_sched_fp=", ab_fp()]),
   String.concat(["C_sched_dump=", ab_dump_sched()]),
   String.concat(["A_ranged_dump=", ab_ranged()])]

def ab_emit.go(+xs: List<&2, String>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case x <> t:
      do IO<Unit>:
        _ : Unit <- IO.print(x)
        ab_emit.go(t)

def main() -> IO(Unit): ab_emit.go(ab_rows())
