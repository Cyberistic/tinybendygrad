# .agents/slop/browser/d1probe.bend -- DOES D1 ALONE FIX D2?
#
# **⇒ THE HYPOTHESIS CAME FROM A MEASUREMENT, NOT FROM READING.**
#
# `arenas.bend` dumped the SAME graph in the arena it lives in:
#
#   A (rangeified)  22 nodes  STORE:none:INDEX,REDUCE   <- the arithmetic IS there
#   C (scheduled)   10 nodes  STORE:none:INDEX,PARAM    <- it is GONE
#
# Upstream `schedule/__init__.py:68-71`:
#
#     k = rk.src[0] if rk.op is Ops.END else rk
#     assert k.op is Ops.CALL, f"unexpected op in queue: {k.op}"
#     buf_uops = tuple(_unwrap_src(s).buf_uop for s in k.src[1:] if not s.is_bound_var)
#     linearized.append(k.replace(src=(k.body, *buf_uops)))
#
# **⇒ `k.replace(src=(k.body, *buf_uops))` IS A **CALL** OPERATION**: `src[0]` is
# the BODY and `src[1:]` are the SHADOWS, each replaced by ITS BUFFER-UOP.
# **⇒ AND BEND HAS NO `raise`, SO THE `assert` BECAME NOTHING**, and the port's
# `replace` (`schedule/__init__.bend:1063`) ran on a **STORE**: `src[0]` = the
# INDEX (kept), `src[1:]` = `[REDUCE]` -> `sc_buf_uop(unwrap(REDUCE))` = a
# **PARAM**. **⇒ SO THE STORE's VALUE BECAME A BUFFER, WHICH IS EXACTLY THE
# `10 NODES / STORE(INDEX,PARAM)` MEASURED.**
#
# **⇒ ⇒ ⇒ SO D2 IS **NOT** A `kuconv` FIELD BUG. IT IS D1's CASCADE**, AND MY OWN
# REPORT'S ATTRIBUTION WAS WRONG. THIS FILE PROVES IT BY BUILDING THE `CALL` THAT
# `split_kernels` OWES AND SEEING WHETHER `replace` THEN KEEPS THE BODY.
#
# WHAT THIS PROBE DOES **NOT** DO: upstream's `split_store` also runs
# `graph_rewrite(x, to_define_global+pm_flatten_range)`. **⇒ AND IT SKIPS THAT
# ON PURPOSE**, because the question here is ONE: **does `replace` behave once
# its subject is a `CALL`?** A probe that did both would not say which half
# mattered.
#
# **⇒ AND THE DEFS ARE IN DEPENDENCY ORDER, WHICH BEND REQUIRES**: "a def may
# call only a def declared ABOVE it" (`.agents/slop/imagenet2/REPORT.md`).
import Base
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/uop/ops.bend as O

def d1_op(+op: O.Op) -> String:
  O.Ops.name.of(op)

def d1_srcs.go(+xs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: d1_srcs.go(t, ar, List.append(&2, String, acc, [d1_op(SCH.sc_op(ar, x))]))

def d1_srcs(+ar: O.Arena, +n: U32) -> String:
  String.join(d1_srcs.go(SCH.sc_srcs(ar, n), ar, Nil{}), ",")

def d1_sig(+ar: O.Arena, +n: U32) -> String:
  String.concat([d1_op(SCH.sc_op(ar, n)), "(", d1_srcs(ar, n), ")"])

# THE STORE THAT `kernel()` SELECTS FROM THE RANGEIFIED GRAPH -- the node
# upstream's `split_store` would have wrapped in a CALL.
#
# **⇒ AND THE WALK IS SPELLED, NOT GUESSED**: `SINK(AFTER(PARAM, END))`, so the
# STORE is `sink.src0.src1.src0`. **⇒ AND THE FIRST VERSION OF THIS DEF STOPPED
# AT `sink.src0` AND ANSWERED `AFTER(PARAM,END)`** -- a row that NAMED a store
# and MEASURED an after, which is the class this tree calls "a row that cannot
# go red" one level down. The `D1_a_store_before=` row is what exposed it.
def d1_store() -> O.Found:
  +q = RZ.rz_built()
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +r = RR.rr_run_rangeify(O.Found.ar(kg), O.Found.i(kg))
  +ar = O.Found.ar(r)
  +sink = O.Found.i(r)
  +aft = SCH.sc_src0(ar, sink)
  +end = SCH.sc_src(ar, aft, 1)
  O.Found{ar, SCH.sc_src0(ar, end)}

# (1) WHAT `replace` DOES TO A **STORE** -- the defect, reproduced.
def d1_replace_store() -> String:
  +f = d1_store()
  +ar = O.Found.ar(f)
  +st = O.Found.i(f)
  +rep = SCH.replace(ar, st)
  +a2 = O.Found.ar(rep)
  String.concat(["store_before=", d1_sig(ar, st),
                 " store_after_replace=", d1_sig(a2, O.Found.i(rep))])

# (2) WHAT `replace` DOES TO A **CALL** WHOSE SHADOWS ARE THE STORE's SRCS -- the
# shape upstream guarantees. **⇒ AND THE CALL's `src[0]` IS THE STORE ITSELF**,
# so `replace` keeps the whole body and only rewrites the shadows.
def d1_replace_call() -> String:
  +f = d1_store()
  +ar = O.Found.ar(f)
  +st = O.Found.i(f)
  # the shadow: exactly what `bu_step` would mint, so the comparison is of the
  # SAME buffer uop and not of two different guesses.
  +sh = SCH.sc_buf_uop(ar, SCH.sc_unwrap(ar, SCH.sc_src(ar, st, 1)))
  +call = O.UOp.new(ar, O.OpsCALL{}, [st, sh], O.ACall{O.CallInfo.of()}, O.TNone{})
  +ca = O.Found.ar(call)
  +ci = O.Found.i(call)
  +rep = SCH.replace(ca, ci)
  +a2 = O.Found.ar(rep)
  String.concat(["call_before=", d1_sig(ca, ci),
                 " call_after_replace=", d1_sig(a2, O.Found.i(rep))])

def d1_rows() -> List<&2, String>:
  [String.concat(["D1_a_", d1_replace_store()]),
   String.concat(["D1_b_", d1_replace_call()])]

def d1_emit.go(+xs: List<&2, String>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case x <> t:
      do IO<Unit>:
        _ : Unit <- IO.print(x)
        d1_emit.go(t)

def main() -> IO(Unit): d1_emit.go(d1_rows())
