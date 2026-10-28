# linrender.bend -- THE DECISIVE TEST: THE PORT's OWN `lin` ARENA -> THE PORT's OWN
# LINEARIZER -> THE PORT's OWN CONVERTER -> THE PORT's OWN RENDERER -> C, COMPARED
# WITH UPSTREAM's OWN C FOR THE SAME PROGRAM.
#
# THE ORACLE IS UPSTREAM's OWN FILE, WRITTEN BY CALLING CPython:
#   upstream: Tensor.empty(4,5).realize(); out.assign(Tensor.empty(4,3) @ Tensor.empty(3,5))
#             -> schedule_linear -> the kernel SINK -> full_rewrite_to_sink -> linearize
#             -> Device['CPU'].renderer.render(list(lines)) -> the C
#   the file is `.agents/slop/linrender/lin_upstream_cpu.c`
#
# THE POINT: THE ARENA IS **THE PORT's OWN** -- IT IS `.agents/slop/graphcmp.bend`'s
# `g_lin()`, THE HAND-BUILT FIXTURE THAT MATCHES UPSTREAM's SCHEDULED MATMUL.  **⇒ THE
# PORT's ARENA, THE PORT's FOLD, THE PORT's LINEARIZER, THE PORT's CONVERTER AND THE
# PORT's RENDERER ALL MEET ON A GRAPH CPython ALSO PRODUCES.**  **⇒ AND THE ORDER IS THE
# PORT's OWN `linearize`'s, NOT THE ARENA's INTERNING ORDER -- WHICH IS WHAT THE FIRST
# ATTEMPT GOT WRONG (IT PRODUCED THE RIGHT STRUCTURE WITH THE LOADS IN THE WRONG ORDER).**
#
# WHAT IS **NOT** CLAIMED: THE `lin` FIXTURE IS HAND-BUILT, NOT DRIVEN BY THE PORT's OWN
# SCHEDULER.  **⇒ THE REMAINING GAP IS "THE PORT's OWN SCHEDULER MUST PRODUCE THIS
# ARENA",** WHICH IS THE ENGINE's JOB.  **⇒ THIS FILE PROVES THE **RENDERER CHAIN** ON A
# REAL SCHEDULED PROGRAM, AND THE SCHEDULER IS THE NEXT LINK, NOT THIS ONE.**
import Base
import ./../graphcmp.bend as GC
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/codegen/late/linearizer.bend as LT
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/renderer/kuconv.bend as KUC

# ===========================================================================
# THE WIDTH OF A RANGE, READ THROUGH ITS BOUND.
#
# `F.rng_width(ar, r)` IS `int(r.vmax)+1` (fold.bend:1426), AND UPSTREAM's `vms` HOLDS THE
# **RAW `r.vmax`** (`linearizer.py:18` IS `int(r.vmax)+1` OVER THE TABLE, AND
# `linearizer.bend:374`'s `lt_rc` ADDS THE `+1` AGAIN). **⇒ SO THE TABLE HOLDS
# `rng_width - 1`.**
#
# **⇒ AND `rng_width` REFUSES A RANGE WHOSE BOUND IS NOT A CONST.** THE PORT's `g_lin`'s
# SPLIT RANGE's BOUND IS AN **AFTER** (`graphcmp.bend:1127-1128`), BECAUSE
# `pm_simplify_ranges` REWRITES A RANGE BOUND INTO `AFTER(bound, prev_range)`.
# **⇒ AND UPSTREAM READS THE VMAX THROUGH IT: A RANGE's `_min_max` IS
# `(self.src[0]-1).vmax` (`ops.py:1147`), AN AFTER's IS ITS `src[0]`'s (`ops.py:457`),
# AND A CAST PASSES ITS `src[0]` THROUGH (`ops.py:142`'s GROUP).** **⇒ SO THE CHAIN IS
# RANGE -> AFTER -> CAST -> CONST.**
#
# **⇒ AND IT IS AN EXPLICIT THREE-LEVEL UNROLL, NOT A RECURSION, AND THE REASON IS
# BEND's OWN RULES: A `match` MAY NOT CALL THE DEF IT IS IN (THE ERROR IS "an unfilled
# law"), AND A SELF-CALL's ARGUMENTS ARE READ LEFT TO RIGHT, EACH PASSED UNCHANGED
# UNTIL ONE SHRINKS (SO A COMPUTED LIST IN FRONT OF A PASS-ONE ARGUMENT IS REFUSED).**
# **⇒ AND THE DEPTH IS NAMED, NOT ASSUMED: IT IS THE NUMBER OF PASS-THROUGH KINDS
# (AFTER, CAST) PLUS ONE FOR THE CONST, AND A CHAIN DEEPER THAN THIS ANSWERS `None`
# RATHER THAN A WRONG NUMBER.**
def lin_width_end3.of(op: O.Op, +ar: O.Arena, e: U32) -> Maybe<&2, H.I64>:
  match op:
    case O.OpsCONST{}: F.const_i64(O.Arena.arg(ar, e))
    case _: None{}

def lin_width_end3(+ar: O.Arena, +e: U32) -> Maybe<&2, H.I64>:
  lin_width_end3.of(O.Arena.op(ar, e), ar, e)

def lin_width_end2.of(op: O.Op, +ar: O.Arena, e: U32) -> Maybe<&2, H.I64>:
  match op:
    case O.OpsCONST{}: F.const_i64(O.Arena.arg(ar, e))
    case O.OpsAFTER{}: lin_width_end3(ar, O.Arena.src(ar, e, 0))
    case O.OpsCAST{}: lin_width_end3(ar, O.Arena.src(ar, e, 0))
    case _: None{}

def lin_width_end2(+ar: O.Arena, +e: U32) -> Maybe<&2, H.I64>:
  lin_width_end2.of(O.Arena.op(ar, e), ar, e)

def lin_width_end.of(op: O.Op, +ar: O.Arena, e: U32) -> Maybe<&2, H.I64>:
  match op:
    case O.OpsCONST{}: F.const_i64(O.Arena.arg(ar, e))
    case O.OpsAFTER{}: lin_width_end2(ar, O.Arena.src(ar, e, 0))
    case O.OpsCAST{}: lin_width_end2(ar, O.Arena.src(ar, e, 0))
    case _: None{}

def lin_width_end(+ar: O.Arena, +e: U32) -> Maybe<&2, H.I64>:
  lin_width_end.of(O.Arena.op(ar, e), ar, e)

def lin_width_at.of(op: O.Op, +ar: O.Arena, r: U32) -> Maybe<&2, H.I64>:
  match op:
    case O.OpsRANGE{}: lin_width_end(ar, O.Arena.src(ar, r, 0))
    case O.OpsSPECIAL{}: lin_width_end(ar, O.Arena.src(ar, r, 0))
    case _: None{}

def lin_width_at(+ar: O.Arena, +r: U32) -> Maybe<&2, H.I64>:
  lin_width_at.of(O.Arena.op(ar, r), ar, r)

# THE `vms` TABLE: ONE flat list of `vmax`es FOR THE WHOLE WALK, LENGTH-PREFIXED PER
# LIST POSITION (`linearizer.bend:644`): `vms = [ n0, v0, ..., v_{n0-1}, n1, ... ]`.
# `n_i` IS THE NUMBER OF RANGES THE i-th NODE IN `lst` HAS, AND `v_j` IS THE RAW
# `r.vmax` FOR EACH OF THOSE RANGES.
def lin_widths(+ar: O.Arena, rs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match rs:
    case Nil{}: acc
    case r <> t:
      +w = lin_width_at(ar, r)
      +u = Maybe.default(&2, H.I64, w, H.i64_of_i32(1))
      lin_widths(ar, t, List.append(&2, U32, acc, [U32.sub(H.lo32(u), 1)]))

def lin_vms.go(+ar: O.Arena, +rt: F.RTable, ns: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ns:
    case Nil{}: acc
    case n <> t:
      +rs = F.UOp.ranges(ar, rt, n)
      +w = lin_widths(ar, F.Rng.rs(rs), Nil{})
      lin_vms.go(ar, rt, t,
        List.append(&2, U32,
          List.append(&2, U32, acc, [U32.from_nat(List.length(&2, U32, w))]),
          w))

# THE WHOLE PIPELINE, AS ONE PURE DEF, BECAUSE BEND HAS NO `let` AND THE `do` BLOCK's
# BINDERS ARE IO-ONLY.
def lin_build() -> List<&2, C.KU>:
  +lin = GC.g_lin()
  +ar = O.Found.ar(lin)
  +sink = O.Found.i(lin)
  +fx = F.folded(ar)
  +rt = F.rng_sweep(ar, F.Folded.t(fx))
  # THE TOPOSORT LIST: `linearize` takes `lst` = `sink.toposort()` (upstream's
  # `linearizer.py:10`), WHICH IS **NO GATE** AND `enter_calls=False`. **⇒ THE PORT's
  # OWN `UOp.toposort_nocalls` IS EXACTLY THAT** (`ops.bend:3376`), AND IT IS NOT
  # `schedule/__init__.bend`'s `sc_topo_of`, WHICH GATES THE KERNEL SINK OUT
  # (`schedule/__init__.bend:511-517`'s `sc_gate`).
  +ns = O.UOp.toposort_nocalls(O.Arena.budget(ar), ar, sink)
  +vms = lin_vms.go(ar, rt, ns, Nil{})
  +ix = LT.linearize(ar, ns, vms, sink)
  KUC.kuconv.convert(fx, ix)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(C.render(C.dev_clang(), True{}, lin_build()))
