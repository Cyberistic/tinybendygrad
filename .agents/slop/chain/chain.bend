# chain.bend -- THE `Device` LANE's PAYOFF: THE PORT's OWN PROGRAM -> THE PORT's OWN
# SCHEDULER -> THE KERNEL COUNT.
#
# THE CHAIN, AND EVERY HOP IS THE PORT's OWN:
#
#   the port's own program            (realize.bend's `rz_built`, MEASURED 23/23 AGREE)
#   -> the port's own sink of AFTERs   (realize.bend's `rz_sink`)
#   -> the port's own engine            (rangeify.bend's `eng_*`, SEVEN STAGES)
#   -> the port's own schedule()        (schedule/__init__.bend:1295)
#   -> **THE KERNEL COUNT**             (THIS FILE's `ch_lin_n`)
#
# **MEASURED 2026-11-19, AND IT CONTRADICTS THIS HEADER AS IT STOOD: `ch_lin_n=0` AND
# `ch_lin_n_plant=0`.**  THE HEADER USED TO SAY "NON-ZERO", AND BOTH ROWS ARE ZERO.
# THE CAUSE IS NAMED AND NOT GUESSED: `eng_stages()`'s STAGE 1 IS `Stg{0, Nil{}}` (an EMPTY
# TABLE), so this chain never RANGEIFIES and `schedule()` gets a sink whose second src is a
# STORE rather than an `END`/`CALL`. `rangify.bend`'s `rr_kernel_graph` DOES rangeify, and
# MEASURED it moves the same count 0 -> 1 (`.agents/slop/pipelinecensus/probe_kg.bend`).
#
# **AND THE PLANT IS A LABEL HERE: IT DROPS THE LAST STAGE (`List.take(..., 6n)`) AND MOVES
# NOTHING -- WHICH IS WHAT A COUNT OF ZERO DOES TO EVERY PLANT BELOW IT. IT WILL BITE ONCE
# STAGE 1 IS WIRED, AND NOT BEFORE. Kept because it is the evidence for the paragraph above.
import Base
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/rangeify.bend as RG
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F

# THE ENGINE'S SEVEN STAGES, AS ONE WALK THAT **RETURNS THE FINAL ARENA AND THE FINAL
# ROOT** -- `rangeify.bend`'s OWN `eng_drive` RETURNS **ROWS**, NOT THE ARENA, **AND THIS
# IS THE DRIVER THE CHAIN NEEDS.**
#
# `eng_run(st, +ar, root) -> Eng` ANSWERS THE ARENA AFTER **ONE** STAGE AND A MAP
# `old -> new`; **THE NEXT STAGE'S ROOT IS `rep_get(Eng.rep(e), root)`**, WHICH IS
# EXACTLY WHAT `eng_drive` DOES AT `rangeify.bend:3149`.
def ch_eng.go(+stages: List<&2, RG.Stg>, +e: RG.Eng, +root: U32) -> RG.Eng:
  match stages:
    case Nil{}: e
    case st <> t:
      +e2 = RG.eng_run(st, RG.Eng.ar(e), root)
      +r2 = RG.rep_get(RG.Eng.rep(e2), root)
      ch_eng.go(t, RG.eng_fresh(e2), r2)

# THE CHAIN, AS ONE PURE DEF. **THE `+` BINDERS ARE **REBINDABLE**, WHICH IS BEND's
# SPELLING FOR A VALUE READ TWICE, AND **THE LIST-BINDING DEFS ARE OUTSIDE THE `do`
# BLOCK BECAUSE A `do` BLOCK's BINDERS ARE IO-ONLY.**
def ch_kernel_count(stages: List<&2, RG.Stg>) -> U32:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +e = ch_eng.go(stages, RG.eng_fresh(RG.Eng{ar, Nil{}}), sink)
  +ar2 = RG.Eng.ar(e)
  +root = RG.rep_get(RG.Eng.rep(e), sink)
  +l = SCH.schedule(ar2, root)
  U32.from_nat(List.length(&2, U32, SCH.Lin.out(l)))

# THE PLANTED CHAIN: **THE ENGINE'S STAGE LIST IS TRUNCATED BY ONE**, **AND THE KERNEL
# COUNT MUST MOVE.** **AND IT IS A **SEPARATE DEF**, NOT A FLAG, SO THE MEASURED CHAIN
# ABOVE IS **ALWAYS** THE UNPLANTED ONE.**
def ch_stages_planted() -> List<&2, RG.Stg>:
  List.take(&2, RG.Stg, RG.eng_stages(), 6n)

def ch_row.line(nm: String, got: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", got]))

def main() -> IO(Unit):
  do IO<Unit>:
    ch_row.line("ch_lin_n", U32.show(ch_kernel_count(RG.eng_stages())))
    ch_row.line("ch_lin_n_plant", U32.show(ch_kernel_count(ch_stages_planted())))
