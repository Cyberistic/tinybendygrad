#!/usr/bin/env python3
"""Append the `i64_dec` rows to the helpers gate, from ONE table.

    .venv/bin/python .agents/slop/i64-dec-rows.py

The bend driver and the CPython oracle must agree on the FIXTURE, and a fixture
transcribed twice is a fixture that can be wrong and green. So the word pairs live
here once and both files are generated from them.

Each row prints TWO lines: `*_x` is the fixture read back through `H.i64_text`, the
two halves, and `*_d` is `H.i64_dec`, the claim. The first line is the input and the
second is the output, so a table that drifts shows up as a diff on the input rather
than as a diff nobody can explain -- which is the convention the 64-bit pair block
already set with its `_a` / `_b` rows.

THE VALUES ARE CHOSEN, NOT SAMPLED. Each is here because one of these is false for
it:

  0, 1, 9, 10      the digits, and the first place an off-by-one loop shows
  100, 1000        powers of ten, where a loop that tests the QUOTIENT instead of
                    the MAGNITUDE emits a surplus zero -- `0:10` is the row that
                    pins the difference
  42, 12345        a run of digits, and 12345 is 5 digits so the trim has to keep
                    all five
  0:2147483647     int32.max, the last value whose LOW WORD alone is the number
  0:2147483648     one past it, so the 32-bit boundary is crossed with hi == 0
  0:4294967295     uint32.max, the widest value hi == 0 can still spell
  1:0              2**32 -- the FIRST row with a non-zero HIGH WORD, and the one
                    that reaches the high-half carries the small rows cannot
  232:3567587328   a 13-digit value, to reach a third fuel iteration
  2147483647:4294967295  int64.max, nineteen digits, the widest the fuel covers
  4294967295:4294967295  -1
  4294967295:4294967286  -10, and the row where the sign and the magnitude disagree
                    in their last digit
  4294967295:4294967254  -42
  4294967295:3294967296  -1e9, a negative value whose magnitude is ten digits
  2147483648:0    int64.min -- THE LIMIT ROW. |int64.min| is 2**63, which Bend's
                    I64 cannot hold, so `i64_dec` answers the `hi:lo` bit pattern
                    (the same fallback `dec_of` takes in viz/serve.bend). The row
                    is here so that fallback is PINNED rather than implied: if the
                    range ever widens, or the guard is deleted, this row changes.
"""
import pathlib

# (name, hi, lo). Written as decimal words because that is how the driver reads them.
ROWS = [
    ("d_zero", 0, 0),
    ("d_one", 0, 1),
    ("d_nine", 0, 9),
    ("d_ten", 0, 10),
    ("d_hundred", 0, 100),
    ("d_thousand", 0, 1000),
    ("d_42", 0, 42),
    ("d_12345", 0, 12345),
    ("d_i32max", 0, 2147483647),
    ("d_i32p1", 0, 2147483648),
    ("d_u32max", 0, 4294967295),
    ("d_2p32", 1, 0),
    ("d_1e12", 232, 3567587328),
    ("d_i64max", 2147483647, 4294967295),
    ("d_neg1", 4294967295, 4294967295),
    ("d_neg10", 4294967295, 4294967286),
    ("d_neg42", 4294967295, 4294967254),
    ("d_neg1e9", 4294967295, 3294967296),
    ("d_i64min", 2147483648, 0),
]

BEND_DRIVER = pathlib.Path(".agents/slop/helpers-tc.bend")
ORACLE = pathlib.Path(".agents/slop/helpers-oracle.py")

GO_DEF = '''
# `i64_dec`: Python's `str(int)`, a SIGNED DECIMAL. Two rows per fixture -- `*_x` is
# the fixture read back as two halves and `*_d` is the claim -- and both come from the
# SAME word pair, so nothing is transcribed twice. The fuel fold's surplus digits are
# the reason `d_ten` is here: a loop that tested the quotient instead of the
# magnitude would print `10` and this row is what says otherwise.
def dec_go(+nm: String, xh: U32, xl: U32) -> IO(Unit):
  +x = lit64(xh, xl)
  do IO<Unit>:
    p64(String.concat([nm, "_x"]), x)
    p(String.concat([nm, "_d"]), H.i64_dec(x))
'''


def main():
  bd = BEND_DRIVER.read_text()
  assert "def dec_go(" not in bd, "the i64_dec rows are already in the driver"
  lines = "\n".join(f'    dec_go("{n}", {h}, {l})' for n, h, l in ROWS)
  # the row group goes just above `def main`, and its call just inside `do IO<Unit>:`
  anchor = "def main() -> IO(Unit):"
  call_anchor = bd.index(anchor)
  body_start = bd.index("do IO<Unit>:", call_anchor) + len("do IO<Unit>:")
  bd = bd[:call_anchor] + GO_DEF + "\n" + bd[call_anchor:]
  body_start = bd.index("do IO<Unit>:", bd.index(anchor)) + len("do IO<Unit>:")
  bd = bd[:body_start] + "\n" + lines + "\n" + bd[body_start:]
  BEND_DRIVER.write_text(bd)

  py = ORACLE.read_text()
  assert "d_i64min" not in py, "the i64_dec rows are already in the oracle"
  body = ["""
# ------------------------------------------------------- `i64_dec`, a signed decimal
# `str(val)` is what `print_uops` (tinygrad/uop/render.py:18) prints for a CONST src,
# and the port's `H.i64_text` cannot answer it: on 4 it says `0:4`. This is the
# CPython side of that claim, and it is `str` itself rather than a reimplementation.
#
# THE FIXTURE IS A PAIR OF WORDS, not a decimal, for the reason the 64-bit block above
# states: a decimal would have to be transcribed on one side and derived on the other,
# and a transcription is exactly the constant that is wrong and green. Each row prints
# the fixture back as `hi:lo` AND the decimal, so the input and the output are both in
# the diff.
#
# `d_i64min` IS A LIMIT AND NOT A CLAIM. CPython's `str(-2**63)` is
# `-9223372036854775808`, and the port answers `2147483648:0` -- the bit pattern --
# because Bend's `I64` cannot hold the magnitude 2**63. So this row is the ONE whose
# two lanes are EXPECTED to differ, and it is emitted here through the same `fallback`
# the port uses rather than skipped, so the disagreement is visible in the diff instead
# of living in a comment.
DEC_ROWS = [
"""]
  for n, h, l in ROWS:
    body.append(f'    ("{n}", {h}, {l}),\n')
  body.append("""]


def dec_limit(x: int) -> bool:
  \"\"\"True where the port cannot hold |x| and answers the bit pattern instead.\"\"\"
  return x == -(1 << 63)


def dec_rows():
  for nm, hi, lo in DEC_ROWS:
    v = signed(hi, lo)
    print(f"{nm}_x={words(v)}")
    print(f"{nm}_d={words(v) if dec_limit(v) else v}")
""")
  py = py.rstrip('\n') + '\n' + ''.join(body) + '\n\ndec_rows()\n'
  ORACLE.write_text(py)
  print(f"driver: {len(ROWS)} rows, oracle: {len(ROWS)} rows")


if __name__ == "__main__":
  main()
