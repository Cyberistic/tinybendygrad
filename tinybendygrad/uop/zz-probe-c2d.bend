# -- PROBE, staged beside the real file so `./ops.bend` and `./../helpers.bend` resolve.
# NOT a deliverable. Answers ONE question, and the brief's answer to it was wrong:
# `s5.selrow` (ops.bend:7021) calls `UOp.copy_to_device(ar, 4, Some{1}, s5.dn(2))`, and
# `s5.devrows` is handed `s5.ga.arena()` (ops.bend:7095) -- NOT `s5.arena()`. So what is
# index 4 of the arena the call actually receives, and index 2?
import ./ops.bend as O

def dump(+nm: String, +ar: O.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print(String.concat([nm, "_budget=", U32.show(U32.from_nat(O.Arena.budget(ar)))]))
    b : Unit <- IO.print(String.concat([nm, "_op_1=", O.Ops.name(O.Arena.op(ar, 1))]))
    c : Unit <- IO.print(String.concat([nm, "_op_2=", O.Ops.name(O.Arena.op(ar, 2))]))
    d : Unit <- IO.print(String.concat([nm, "_op_3=", O.Ops.name(O.Arena.op(ar, 3))]))
    e : Unit <- IO.print(String.concat([nm, "_op_4=", O.Ops.name(O.Arena.op(ar, 4))]))
    f : Unit <- IO.print(String.concat([nm, "_nsrc_4=", U32.show(O.Arena.nsrc(ar, 4))]))
    IO.print(String.concat([nm, "_src_4_0=", O.Ops.name(O.Arena.op(ar, O.Arena.src(ar, 4, 0)))]))

def main() -> IO(Unit):
  do IO<Unit>:
    dump("probe_ga", O.s5.ga.arena())
    dump("probe_s5", O.s5.arena())
    IO.print("done")