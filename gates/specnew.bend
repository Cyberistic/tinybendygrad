# specnew.bend -- the two node shapes that upstream's `spec.py:104` and `spec.py:125`
# decide, read in the PORT.
#
#   checks/bounded.py --mb 2048 -- bin/bend gates/specnew.bend
#
# WHY A SECOND PROBE AND NOT TWO MORE FIXTURES IN `gates/specreach.bend`. The map there
# has THREE fixtures and EIGHTEEN cells, and the task this probe answers is not the
# map's: it is "DO THE TWO NEW RULES CHANGE ANY ANSWER". The answer is YES for four of
# the six tables and NO for the other two, and the reason is the map's denominator:
# `spec_full`'s OWN first four rules already claim every AFTER (`spec.py:246`) and every
# LOAD/STORE (`spec.py:249`), so in `spec_full` the two new rules are SHADOWED and the
# `sf` row cannot move. `sh`, `te`, `sp` and `hq` are the four tables that carry
# `spec_shared` WITHOUT `spec_full`'s shadow, and those are the rows that move.
#
# THE TWO FIXTURES, and each one is a shape the port REJECTED before 2026-10-22:
#
#   after_alu  `AFTER(ADD(1, 2))` -- upstream's `spec.py:104` ACCEPTS it (the AFTER's
#              src[0] is an ALU and its shape is `()`), and `spec.py:99`'s movement rule
#              does not claim it because an ADD is not a movement op. The port had no
#              rule for it, so `spec_shared` answered `None` -- and `type_verify` fails
#              on anything that is not `True`.
#   store_bad  `STORE(BUFFER(int32), CONST(int64))` -- the value's dtype does NOT match
#              the target's, so upstream's `spec.py:125` says `False`. The port had no
#              rule for it, so `spec_shared` answered `None` where upstream answers
#              `False`: the same rejection for a different reason, and the later rules
#              ran when upstream's never did.
#
# `1` is VTrue, `0` is VFalse, `9` is VSkip -- the port's `Sp.show_v` spelling, and
# `gates/specnew-oracle.py` prints the same six numbers from CPython's own matchers.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/uop/spec.bend as Sp

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# ONE FIXTURE, ALL SIX VERDICTS. `fu_rewrite`/`kg_rewrite` take their `PMEntrys` by
# `+`, and a table is affine: it is spent on use, so the tables are RE-BUILT per use.
def probe(+nm: String, +i: U32, +fx: F.Folded) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row(String.concat([nm, "_sh"]), Sp.show_v(Sp.shared_rewrite(fx, i)))
    b : Unit <- row(String.concat([nm, "_te"]), Sp.show_v(Sp.tensor_rewrite(fx, i)))
    c : Unit <- row(String.concat([nm, "_sp"]), Sp.show_v(Sp.program_rewrite(fx, i)))
    d : Unit <- row(String.concat([nm, "_hq"]), Sp.show_v(Sp.hcq_rewrite(fx, i)))
    e : Unit <- row(String.concat([nm, "_sk"]), Sp.show_v(Sp.kg_rewrite(Sp.kernel_graph_table(), fx, i)))
    f : Unit <- row(String.concat([nm, "_sf"]), Sp.show_v(Sp.fu_rewrite(Sp.full_table(), fx, i)))
    return Unit{}

# FIXTURE ONE. `UOp.alu` is the port's spelling of an ALU node and it derives the dtype
# from its srcs, so `ADD(CONST(1), CONST(2))` is int64 and SCALAR -- and the shape is
# what `spec.py:104` asks about.
def after_alu() -> O.Found:
  +c1 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +c2 = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(2)})
  +add = O.UOp.alu(O.Found.ar(c2), O.OpsADD{}, [O.Found.i(c1), O.Found.i(c2)])
  O.UOp.new(O.Found.ar(add), O.OpsAFTER{}, [O.Found.i(add)], O.ANone{}, O.TNone{})

# FIXTURE TWO. `buf_param()` is a GLOBAL BUFFER of int32, and the value is an int64
# CONST -- a plain `CInt` is WEAKINT in this port (upstream's `UOp.const(1)` is
# `dtypes.weakint` too), and `weak_dtype(int32)` is weakint, so a weak value would
# MATCH the target and the rule would have nothing to say. The CAST is how a
# non-weak int is spelled here, and `int64 != weakint` is the mismatch.
def store_bad() -> O.Found:
  +buf = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{Sp.buf_param()}, O.TNone{})
  +c = O.UOp.const(O.Found.ar(buf), O.CInt{H.i64_of_i32(1)})
  +val = O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{S.int64()}, O.TNone{})
  O.UOp.store(O.Found.ar(val), O.Found.i(buf), O.Found.i(val), None{})

def after_alu_rows() -> IO(Unit):
  +n = after_alu()
  probe("after_alu", O.Found.i(n), F.folded(O.Found.ar(n)))

def store_bad_rows() -> IO(Unit):
  +n = store_bad()
  probe("store_bad", O.Found.i(n), F.folded(O.Found.ar(n)))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- after_alu_rows()
    b : Unit <- store_bad_rows()
    return Unit{}
