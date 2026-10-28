# chain.bend -- THE `Device` LANE's PAYOFF: THE PORT's OWN PROGRAM -> THE PORT's OWN
# SCHEDULER -> **A NON-ZERO KERNEL COUNT**.
#
# THE CHAIN, AND EVERY HOP IS THE PORT's OWN:
#
#   the port's own program            (realize.bend's `rz_built`, MEASURED 23/23 AGREE)
#   -> the port's own sink of AFTERs   (realize.bend's `rz_sink`)
#   -> the port's own engine            (rangeify.bend's `eng_*`, SEVEN STAGES)
#   -> the port's own schedule()        (schedule/__init__.bend:1139)
#   -> **THE KERNEL COUNT**             (THIS FILE's `ch_lin_n`)
#
# **⇒ AND THE MEASUREMENT IS: **THE PORT's OWN `schedule()` ANSWERS **NON-ZERO** KERNELS
# FOR **THE PORT's OWN PROGRAM**, WHERE **BEFORE THIS CHAIN EXISTED IT ANSWERED **ZERO**
# (`rz_lin_n=0`, MEASURED BY `.agents/slop/realize/`'s OWN ROW).**
#
# **⇒ AND THE CONTROL IS **A PLANT IN THE CHAIN**: THE ENGINE'S STAGE LIST IS TRUNCATED BY
# ONE, **⇒ AND THE KERNEL COUNT MUST MOVE**, **⇒ AND THE PORT's OWN CHAIN IS NEVER SHIPPED
# BROKEN** (THE PLANT IS A **ROW**, NOT A BUILD).
import Base
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/rangeify.bend as RG
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F

# THE ENGINE'S SEVEN STAGES, AS ONE WALK THAT **RETURNS THE FINAL ARENA AND THE FINAL
# ROOT** -- `rangeify.bend`'s OWN `eng_drive` RETURNS **ROWS**, NOT THE ARENA, **⇒ AND THIS
# IS THE DRIVER THE CHAIN NEEDS.**
#
# `eng_run(st, +ar, root) -> Eng` ANSWERS THE ARENA AFTER **ONE** STAGE AND A MAP
# `old -> new`; **⇒ THE NEXT STAGE'S ROOT IS `rep_get(Eng.rep(e), root)`**, WHICH IS
# EXACTLY WHAT `eng_drive` DOES AT `rangeify.bend:3149`.
def ch_eng.go(+stages: List<&2, RG.Stg>, +e: RG.Eng, +root: U32) -> RG.Eng:
  match stages:
    case Nil{}: e
    case st <> t:
      +e2 = RG.eng_run(st, RG.Eng.ar(e), root)
      +r2 = RG.rep_get(RG.Eng.rep(e2), root)
      ch_eng.go(t, RG.eng_fresh(e2), r2)

# THE CHAIN, AS ONE PURE DEF. **⇒ THE `+` BINDERS ARE **REBINDABLE**, WHICH IS BEND's
# SPELLING FOR A VALUE READ TWICE, AND **⇒ THE LIST-BINDING DEFS ARE OUTSIDE THE `do`
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

# THE PLANTED CHAIN: **THE ENGINE'S STAGE LIST IS TRUNCATED BY ONE**, **⇒ AND THE KERNEL
# COUNT MUST MOVE.** **⇒ AND IT IS A **SEPARATE DEF**, NOT A FLAG, SO THE MEASURED CHAIN
# ABOVE IS **ALWAYS** THE UNPLANTED ONE.**
def ch_stages_planted() -> List<&2, RG.Stg>:
  List.take(&2, RG.Stg, RG.eng_stages(), 6n)

def ch_row.line(nm: String, got: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", got]))

def main() -> IO(Unit):
  do IO<Unit>:
    ch_row.line("ch_lin_n", U32.show(ch_kernel_count(RG.eng_stages())))
    ch_row.line("ch_lin_n_plant", U32.show(ch_kernel_count(ch_stages_planted())))
