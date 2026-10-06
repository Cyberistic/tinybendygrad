# render_val_s.bend -- a small driver for `tinybendygrad/renderer/tc_ptx.bend`'s
# `render_val_s`, the SIGNED 32-bit integer printer.
#
#   .venv/bin/python gates/render_val_s-gate.py
#
# EIGHT ROWS, NAMED ONCE. The row NAME is the claim being asked. Both lanes share no
# code: the Bend lane calls the new arm directly, the oracle builds a `v` and asks
# `str(int(v - (1<<32) if v >= (1<<31) else v))`. A row agrees only if the two
# implementations of the property say so.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/renderer/tc_ptx.bend as P
import ./../tinybendygrad/helpers.bend as H

def row.act(ok: Bool, nm: String) -> IO(Unit):
  match ok:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

def row(nm: String, v: String, py: String) -> IO(Unit):
  row.act(String.eq(v, py), nm)

# The seven sign-bearing values. The bit pattern matches CPython's `v` for
# `str(int(v))` after Python's unsigned-to-signed conversion.
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("s_zero", P.render_val_s(0), "0")
    b : Unit <- row("s_one", P.render_val_s(1), "1")
    c : Unit <- row("s_seven", P.render_val_s(7), "7")
    d : Unit <- row("s_neg_one", P.render_val_s(4294967295), "-1")
    e : Unit <- row("s_neg_two", P.render_val_s(4294967294), "-2")
    f : Unit <- row("s_int_min", P.render_val_s(2147483648), "-2147483648")
    g : Unit <- row("s_int_max", P.render_val_s(2147483647), "2147483647")
    h : Unit <- row("s_hundred", P.render_val_s(100), "100")
    return Unit{}
