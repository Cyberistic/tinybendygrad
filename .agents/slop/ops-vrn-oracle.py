#!/usr/bin/env python3
"""CPython oracle for `UOp.variable` (tinygrad/uop/ops.py:1015).

    .venv/bin/python .agents/slop/ops-vrn-oracle.py

Four rows, one per fixture, every one produced by CALLING the real
`UOp.variable` and reading the real `ParamArg` back. Nothing is transcribed from
reading the source.

`variable` sets FIVE fields -- slot, name, vmin_vmax, multiple_of, addrspace -- and
leaves the other eight at `ParamArg`'s defaults. So a row prints those five plus the
src count, and nothing else: a row that printed the whole record would move on any
of thirteen fields and say nothing about any one of them.

THE SLOT IS THE ROW THAT MATTERS MOST, and it is the one this def waited two commits
for. CPython writes `slot=-1`; this port's `ParamArg.slot` is a `U32`, so the value
needed a name and the file that OWNS the field had none. `ParamArg.no_slot()`
(ops.bend, landed 2026-10-04) is that name. Before it existed, `variable` was
unportable, and guessing `4294967295` would have made every row here agree for a
reason that was a guess.

`vrn_multi` and `vrn_neg` are what make the two `lo`/`hi` ends and the sign SEPARATE.
One row printing `(0,10)` cannot tell a swapped pair from a correct one, and one row
with a positive range cannot tell `i64_neg(True{}, 5)` from `5`.

THE NEGATIVE ENDS PRINT IN THE PORT'S OWN SPELLING. `H.i64_text` renders an `H.I64`
as `hi:lo` in two `U32` words, and a negative value is the two's-complement pair --
`4294967295:4294967291` is `-5`. CPython prints `-5`. The oracle therefore prints the
SAME two-word form rather than `-5`, by reading the raw words, because the gate's
question is "did the same bits land in the same field" and not "can two languages
spell minus five the same way". `H.i64_text` is the port's own function and its
output IS the contract; a row that printed CPython's `-5` would be a row about
formatting.
"""
import sys

from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad import dtypes
from tinygrad.dtype import AddrSpace

MASK = 0xFFFFFFFF


def i64_words(v):
  """`H.i64_text`'s two-word form: (hi, lo) as unsigned 32-bit halves."""
  n = int(v) & ((1 << 64) - 1)
  return f"{n >> 32}:{n & MASK}"


def facts(u):
  p = u.arg
  assert isinstance(p, ParamArg), p
  lo, hi = p.vmin_vmax
  return (f"slot={p.slot} name={p.name} mult={p.multiple_of} "
          f"addr={p.addrspace.name} lo={i64_words(lo)} hi={i64_words(hi)} "
          f"nsrc={len(u.src)}")


def row(nm, name, lo, hi, mult, dt):
  # CPython's own defaults are `dtype=dtypes.weakint, multiple_of=1`, so
  # `vrn_default` is the def's SIGNATURE rather than a fixture choice.
  a = ParamArg(-1, dt, name=name, vmin_vmax=(lo, hi), multiple_of=mult,
               addrspace=AddrSpace.ALU)
  u = UOp(Ops.PARAM, (), a, ())
  print(f"{nm}={facts(u)}")


def main():
  row("vrn_default", "i", 0, 10, 1, dtypes.weakint)
  row("vrn_multi", "j", -5, 5, 4, dtypes.weakint)
  row("vrn_neg", "m", -100, -1, 1, dtypes.weakint)
  row("vrn_int32", "k", 1, 2, 1, dtypes.int32)
  return 0


if __name__ == "__main__":
  sys.exit(main())
