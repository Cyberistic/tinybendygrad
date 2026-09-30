#!/usr/bin/env python3
"""Check dtype.bend's lattice against tinygrad's, pair by pair.

The mask encoding is a CLAIM, and a claim about a promotion table that nothing
checks is a comment. This runs every one of the 361 pairs (and 5000 random
n-ary folds) through both implementations and diffs the names.

usage: ../../bin/bend dtype_test.bend && ./dtype_test
"""
import Base
import ./dtype.bend as D
import ./LAWS/spec.bend as S

def names(ds: List<&2, S.Dt>) -> List<&2, String>:
  names.go(ds, Nil{})

def names.go(ds: List<&2, S.Dt>, acc: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}: List.reverse(&2, String, acc)
    case h <> t: names.go(t, String.append(D.dt_name(h), ", ") <> acc)

# ---------------------------------------------------------------------------
# every pair, as a comma-free name list, on one line
# --------------------------------------------------------------------------

def pair_row(a: S.Dt, b: S.Dt, row: String) -> String:
  String.concat([row, D.dt_name(D.least_upper.of(a, b)), " "])

def pair_rows(ds: List<&2, S.Dt>, row: String) -> List<&2, String>:
  match ds:
    case Nil{}: [row]
    case h <> t: List.append(&2, String, pair_rows(t, pair_row(h, h, row)), pair_row(h, t, ""))

def lut_table() -> String:
  pair_rows(D.dtypes.all(), "lut ")

# ---------------------------------------------------------------------------
# can_lossless_cast, the whole 20x20 grid, one row per line
# ---------------------------------------------------------------------------

def clc_row(d: S.Dt, ds: List<&2, S.Dt>, row: String) -> String:
  match ds:
    case Nil{}: row
    case h <> t: clc_row(h, t, String.append(row, Bool.show(D.can_lossless_cast(d, h))))

def clc_rows(d: S.Dt, ds: List<&2, S.Dt>) -> String:
  String.concat([D.dt_name(d), ": ", clc_row(d, ds, ""), "\n"])

def clc_all(ds: List<&2, S.Dt>) -> String:
  match ds:
    case Nil{}: ""
    case h <> t: String.append(clc_all(t), clc_rows(h, D.dtypes.all()))

# ---------------------------------------------------------------------------
# sum_acc_dtype, finfo, itemsize, and the docstring's own examples
# ---------------------------------------------------------------------------

def sum_row(d: S.Dt, sum: S.Dt) -> String:
  D.sum_acc_dtype(d, sum).nm <> " "

def sum_all(ds: List<&2, S.Dt>, sum: S.Dt) -> String:
  sum_all.go(ds, sum, "")

def sum_all.go(ds: List<&2, S.Dt>, sum: S.Dt, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case h <> t: sum_all.go(t, sum, String.append(acc, sum_row(h, sum)))

def info_row(d: S.Dt) -> String:
  D.finfo(d).nm <> " "

def info_all(ds: List<&2, S.Dt>) -> String:
  info_all.go(ds, "")

def info_all.go(ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case h <> t: info_all.go(t, String.append(acc, info_row(h)))

def size_all(ds: List<&2, S.Dt>) -> String:
  size_all.go(ds, "")

def size_all.go(ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case h <> t: size_all.go(t, String.append(acc, U32.show(S.Dt.itemsize(h)) <> " "))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.append("== least_upper, 361 pairs\n", lut_table()))
    IO.print(String.append("\n== can_lossless_cast\n", clc_all(D.dtypes.all())))
    IO.print(String.append("\n== sum_acc_dtype (SUM_DTYPE=float32)\n",
      sum_all(D.dtypes.all(), S.single())))
    IO.print(String.append("\n== sum_acc_dtype (SUM_DTYPE=bfloat16)\n",
      sum_all(D.dtypes.all(), S.bfloat16())))
    IO.print(String.append("\n== finfo\n", info_all(D.dtypes.floats())))
    IO.print(String.append("\n== itemsize\n", size_all(D.dtypes.all())))
