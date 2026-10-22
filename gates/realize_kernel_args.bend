# realize_kernel_args.bend -- THE PORT's `get_call_kernel_args` OVER ITS PLANT FIXTURE.
#
#   ./bin/bend gates/realize_kernel_args.bend
#
# NINETEEN ROWS, IN THE ORACLE's ORDER, IN THE PORT's OWN SPELLING. THE READERS ARE NOT
# COPIED HERE: THEY ARE `tinybendygrad/engine/realize.bend`'s OWN `t_ka_*` DEFS, OVER
# ITS OWN `plants_arena()`. THIS FILE IS A DRIVER AND NOT A SECOND IMPLEMENTATION, AND
# THAT IS WHY IT IS SIXTEEN LINES LONG.
#
# **WHY THE BIG CENSUS's `var` DRIVER IS NOT THIS.** THE PIN's `get_call_kernel_args`
# READS `s.is_bound_var`, AND `ops.py:1011`'s `is_variable` READS `self._shape`, WHICH
# FOR A PARAM IS `self.src[0].as_shape` -- SO A PARAM WITH NO `src` RAISES IndexError.
# THE BIG CENSUS's FIXTURE MIRRORS THE PORT's `main_arena`, WHOSE PARAMS HAVE NO `src`,
# SO ITS `var` ROWS ARE A DECLARED DIVERGENCE INSTEAD OF A COMPARISON. THE PLANT FIXTURE
# BUILDS ITS PARAMS WITH `UOp.param` AND GIVES EVERY PROGRAM THE PIN's COMPILED SHAPE
# `src=(sink, linear)`, BECAUSE THE PIN's `UOp.kernel_params` READS `self.src[1].src`.
#
# **THE DEVICE IS NOT IN THESE ROWS, AND THAT IS STATED, NOT HIDDEN.** THE PIN TAKES A
# DEVICE TUPLE AND THE PORT TAKES ONE `S.Dev`; THE BRIDGE IS THE CALL's OWN DEVICE, AND
# EVERY PLANT HERE IS ON "CPU", SO THE ORACLE PASSES `("CPU",)` AND THE PORT PASSES
# `cpu_dev()`. A WRONG DEVICE IS INVISIBLE HERE BECAUSE NEITHER LANE PRINTS IT. IT IS
# COMPARED IN THE BIG CENSUS, WHERE THE DEVICE's COUNT IS IN THE GETADDR's PAYLOAD.
import Base
import ./../tinybendygrad/engine/realize.bend as RZ

def main() -> IO(Unit):
  +p = RZ.plants_arena()
  do IO<Unit>:
    IO.print(String.concat(["ka_none_len=", U32.show(RZ.t_ka_len(p, 0))]))
    IO.print(String.concat(["ka_none_addr=", U32.show(RZ.t_ka_addr(p, 0, 0))]))
    IO.print(String.concat(["ka_zero_len=", U32.show(RZ.t_ka_len(p, 1))]))
    IO.print(String.concat(["ka_zero_cast=", U32.show(RZ.t_ka_cast(p, 1, 0))]))
    IO.print(String.concat(["ka_unb_len=", U32.show(RZ.t_ka_len(p, 2))]))
    IO.print(String.concat(["ka_unb_param=", U32.show(RZ.t_ka_param(p, 2, 0))]))
    IO.print(String.concat(["ka_unb_slotless=", U32.show(RZ.t_ka_slotless(p, 2, 0))]))
    IO.print(String.concat(["ka_unb_arglen=", U32.show(RZ.t_ka_arglen(p, 2))]))
    IO.print(String.concat(["ka_af_len=", U32.show(RZ.t_ka_len(p, 3))]))
    IO.print(String.concat(["ka_af_p0=", U32.show(RZ.t_ka_param(p, 3, 0))]))
    IO.print(String.concat(["ka_af_a1=", U32.show(RZ.t_ka_addr(p, 3, 1))]))
    IO.print(String.concat(["ka_af_slotless=", U32.show(RZ.t_ka_slotless(p, 3, 0))]))
    IO.print(String.concat(["ka_bf_len=", U32.show(RZ.t_ka_len(p, 4))]))
    IO.print(String.concat(["ka_bf_a0=", U32.show(RZ.t_ka_addr(p, 4, 0))]))
    IO.print(String.concat(["ka_bf_p1=", U32.show(RZ.t_ka_param(p, 4, 1))]))
    IO.print(String.concat(["ka_bf_slotless=", U32.show(RZ.t_ka_slotless(p, 4, 1))]))
    IO.print(String.concat(["ka_sh_len=", U32.show(RZ.t_ka_len(p, 5))]))
    IO.print(String.concat(["ka_sh_cast=", U32.show(RZ.t_ka_cast(p, 5, 1))]))
    IO.print(String.concat(["ka_sh_a0=", U32.show(RZ.t_ka_addr(p, 5, 0))]))
