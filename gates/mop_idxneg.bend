# mop_idxneg.bend -- the PORT lane of the negative-STACK-index parity gate.
#
#   .venv/bin/python gates/mop_idxneg-gate.py
#
# WHAT IT MEASURES. `tinygrad/uop/movement.py`'s `mop_cleanup` rule 6 and
# `tinygrad/uop/ops.py`'s `UOp.index` both index a STACK's srcs with a CONST's VALUE:
#
#   `a.src[i.val] if len(idx.src) <= 2 else a.src[i.val].index(*idx.src[2:])` -- tinygrad/uop/movement.py:22
#   `return self.src[new_srcs[0].val]` -- tinygrad/uop/ops.py:561
#
# `a.src[v]` is PYTHON'S LIST INDEX, so a NEGATIVE `v` reads from the END: `a.src[-1]` is
# the LAST element. THE PORT READ EVERY INDEX AS A `U32`, so a negative `v` became a huge
# `U32` and the answer was the FIRST element.
#
# MEASURED 2026-10-30, against CPython at the pin:
#
#     UOp(Ops.INDEX, src=(STACK(CONST 3, CONST 5, CONST 7), CONST(-1)))
#       upstream `mop_cleanup`  -> CONST 7
#       the port before the fix  -> CONST 3
#
# EIGHT ROWS PER LANE, and they are the two call sites over the same four indices:
# `-1`, `-2`, `-3` and `-4` for `mop_cleanup`, and `-1`, `-2`, `-3`, `-4` for `UOp.index`,
# plus `0`, `1`, `2` and `3` so a fix that broke the POSITIVE case would be caught by the
# same rows rather than by a separate fixture. The out-of-range rows are the `-4` and the
# `3`: upstream RAISES `IndexError` and the port has no exception form, so the port's
# answer is "no rewrite", and the ORACLE prints `none` for it.
#
# THE ROW IS THE ANSWER'S VALUE, not the answer's KIND: a CONST's ARG. `none` is
# upstream's `IndexError` and the port's "no rewrite" in ONE spelling, so the two lanes
# compare the same thing. A row that printed the OP would say `CONST` on both sides for
# the wrong index and would not move.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/uop/movement.bend as M

def row(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def const(ar: O.Arena, v: H.I64) -> O.Found:
  O.UOp.const(ar, O.CInt{v})

# STACK(CONST 3, CONST 5, CONST 7) -- THREE elements, so `-1` is the LAST and `-3` is the
# FIRST, and `-4` is out of range on both ends.
def stk() -> O.Found:
  +a = const(O.Arena.empty(), H.i64_of_i32(3))
  +b = const(O.Found.ar(a), H.i64_of_i32(5))
  +c = const(O.Found.ar(b), H.i64_of_i32(7))
  O.UOp.new(O.Found.ar(c), O.OpsSTACK{}, [O.Found.i(a), O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

# INDEX(STACK, CONST k) -- the node `mop_cleanup` rule 6 rewrites.
def idx(k: H.I64) -> O.Found:
  +s = stk()
  +i = const(O.Found.ar(s), k)
  O.UOp.new(O.Found.ar(i), O.OpsINDEX{}, [O.Found.i(s), O.Found.i(i)], O.ANone{}, O.TNone{})

# `UOp.index(k)` -- `return self.src[new_srcs[0].val]` -- tinygrad/uop/ops.py:561 -- which
# is the port's `M.mp_index`.
def idx_of(k: H.I64) -> M.Hop:
  +s = stk()
  +i = const(O.Found.ar(s), k)
  M.mp_index(O.Found.ar(i), O.Found.i(s), [O.Found.i(i)])

# THE ANSWER'S VALUE, or "none" when there is no answer. `Hop`'s index 0 is the arena's
# bottom and is Python's `None` -- `M.mop_cleanup` answers it when no rule fired.
#
# THE VALUE IS THE LOW WORD of the I64, and every value here is a small non-negative
# count -- a STACK of three CONSTs -- so `H.i64_text`'s `hi:lo` spelling would print
# `0:7` against the oracle's `7` and the two lanes would differ in SPELLING. The high
# word is zero for every value in range, so the low word IS the value.
def val_of.at(none: Bool, har: O.Arena, ix: U32) -> String:
  match none:
    case True{}: "none"
    case False{}: U32.show(H.lo32(M.mp_const_val(har, ix)))

def val_of(h: M.Hop) -> String:
  match h:
    case M.Hop{har, ix}:
      +i = ix
      val_of.at(O.UOp.is_none(i), har, i)

def mcl(k: H.I64) -> String:
  +f = idx(k)
  +ar = O.Found.ar(f)
  val_of(M.mop_cleanup(F.folded(ar), O.Found.i(f)))

def uidx(k: H.I64) -> String:
  val_of(idx_of(k))

def main() -> IO(Unit):
  do IO<Unit>:
    row("mcl_neg1", mcl(H.i64_of_i32(4294967295)))
    row("mcl_neg2", mcl(H.i64_of_i32(4294967294)))
    row("mcl_neg3", mcl(H.i64_of_i32(4294967293)))
    row("mcl_neg4", mcl(H.i64_of_i32(4294967292)))
    row("mcl_pos0", mcl(H.i64_of_i32(0)))
    row("mcl_pos1", mcl(H.i64_of_i32(1)))
    row("mcl_pos2", mcl(H.i64_of_i32(2)))
    row("mcl_pos3", mcl(H.i64_of_i32(3)))
    row("uidx_neg1", uidx(H.i64_of_i32(4294967295)))
    row("uidx_neg2", uidx(H.i64_of_i32(4294967294)))
    row("uidx_neg3", uidx(H.i64_of_i32(4294967293)))
    row("uidx_neg4", uidx(H.i64_of_i32(4294967292)))
    row("uidx_pos0", uidx(H.i64_of_i32(0)))
    row("uidx_pos1", uidx(H.i64_of_i32(1)))
    row("uidx_pos2", uidx(H.i64_of_i32(2)))
    row("uidx_pos3", uidx(H.i64_of_i32(3)))
