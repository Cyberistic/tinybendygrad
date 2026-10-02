# dtype_oracle.bend -- print every table dtype.bend claims, in a form the Python
# oracle can diff line for line. Not the test itself: the diff IS the test, and
# it lives in .agents/slop/notes/dtype_oracle.py because the oracle is
# tinygrad's own Python, and that is the only implementation whose answers count.
#
# Both lanes must print the same bytes, so the oracle script runs this twice.
#
# Written in dependency order: bend has no forward references, so every def here
# is below everything it calls and the file reads top to bottom.
import Base
import ../dtype.bend as D
import ../helpers.bend as H
import ../LAWS/spec.bend as S

# ===========================================================================
# The twenty dtypes: name, priority, bits, itemsize, the three predicates dtype.py
# asks about, the integer range, and the finite float max.
# ===========================================================================

def range_text(m: Maybe<&1, H.I64>) -> String:
  match m:
    case Some{v}: H.i64_text(v)
    case None{}: "-"

def fmax_text(m: Maybe<&1, F32>) -> String:
  match m:
    case Some{v}: F32.show(v)
    case None{}: "-"

def row(+d: S.Dt) -> String:
  String.concat([
    D.dt_name(d), "\t", U32.show(S.Dt.pri(d)), "\t", U32.show(S.Dt.bits(d)), "\t",
    U32.show(S.Dt.itemsize(d)), "\t", Bool.show(S.Dt.is_int(d)), "\t",
    Bool.show(S.Dt.is_float(d)), "\t", Bool.show(S.Dt.is_unsigned(d)), "\t",
    Bool.show(S.Dt.is_bool(d)), "\t", range_text(D.dt_min(d)), "\t",
    range_text(D.dt_max(d)), "\t", fmax_text(D.fmax(d)), "\n"])

def rows(ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case h <> t: rows(t, String.append(acc, row(h)))

# ===========================================================================
# least_upper over every ordered pair of dtypes.all() -- 17 x 17 = 289 rows.
#
# TWO FOLDS, NOT A Maybe. The first draft carried the outer dtype as a
# `Maybe<&2, S.Dt>` and threaded it through one self-call, which cannot be
# written: the field of a `Maybe` cannot be passed to a reusable (`+`) parameter,
# and `lut_row` must read each dtype twice (`dt_name` and `least_upper.of`), so
# its parameters HAVE to be `+`. Passing the outer dtype as a `+` parameter of
# its own def works instead -- `+a` is passed BARE to every use, and the inner
# fold returns the block so the outer fold can append it whole.
#
# Two measured Bend rules cost the three earlier attempts, and both are in
# bend2-constraints.md at the end of 2026-10-02:
#   * a `+` PARAMETER and a `+` CASE BINDER may only be passed BARE. `use2(+a, b)`
#     fails with "expected: a bound variable / observed: a^-1", and so does
#     `use2(a, +h)` for `case +h`. A PLAIN binder may be passed either way.
#   * a self-call's arguments are read LEFT TO RIGHT, each passed unchanged until
#     one shrinks -- so a value reused in a later argument has to be bound first
#     with `+r = ...`, and a value used by two arms needs `case +h <> +t`.
# ===========================================================================

def lut_row(+a: S.Dt, +b: S.Dt) -> String:
  String.concat([D.dt_name(a), "\t", D.dt_name(b), "\t",
    D.dt_name(D.least_upper.of(a, b)), "\n"])

def lut_rows.go(+a: S.Dt, ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case +h <> t:
      +r = lut_row(a, h)
      lut_rows.go(a, t, String.append(acc, r))

# `all` is the FULL list, carried so every outer row is the full square and not
# the shrinking tail: without it the block is the upper triangle (153 rows), and
# `can_lossless_cast` is NOT symmetric, so that would silently drop half the
# table it is the gate for.
def lut_rows.all(+all: List<&2, S.Dt>, ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case +h <> t:
      +r = lut_rows.go(h, all, "")
      lut_rows.all(all, t, String.append(acc, r))

def lut_rows(+ds: List<&2, S.Dt>) -> String:
  lut_rows.all(ds, ds, "")

# ===========================================================================
# can_lossless_cast over every pair, same shape.
# ===========================================================================

def clc_row(+a: S.Dt, +b: S.Dt) -> String:
  String.concat([D.dt_name(a), "\t", D.dt_name(b), "\t",
    Bool.show(D.can_lossless_cast(a, b)), "\n"])

def clc_rows.go(+a: S.Dt, ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case +h <> t:
      +r = clc_row(a, h)
      clc_rows.go(a, t, String.append(acc, r))

def clc_rows.all(+all: List<&2, S.Dt>, ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case +h <> t:
      +r = clc_rows.go(h, all, "")
      clc_rows.all(all, t, String.append(acc, r))

def clc_rows(+ds: List<&2, S.Dt>) -> String:
  clc_rows.all(ds, ds, "")

# ===========================================================================
# sum_acc_dtype under each SUM_DTYPE tinygrad accepts.
# ===========================================================================

def sum_row(+d: S.Dt, +sum: S.Dt) -> String:
  String.concat([D.dt_name(d), "\t", D.dt_name(sum), "\t",
    D.dt_name(D.sum_acc_dtype(d, sum)), "\n"])

def sum_rows(+sum: S.Dt, ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case h <> t: sum_rows(sum, t, String.append(acc, sum_row(h, sum)))

# ===========================================================================
# finfo over the floats, and "-" for the one dtype dtype.py raises on.
# ===========================================================================

def finfo_text(m: Maybe<&1, D.Finfo>) -> String:
  match m:
    case Some{f}:
      match f:
        case D.Finfo{e, mm}: String.concat([U32.show(e), ",", U32.show(mm)])
    case None{}: "-"

def finfo_row(+d: S.Dt) -> String:
  String.concat([D.dt_name(d), "\t", finfo_text(D.finfo(d)), "\n"])

def finfo_rows(ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case h <> t: finfo_rows(t, String.append(acc, finfo_row(h)))

# ===========================================================================
# commit_int, over every value that lands on a rung boundary and one either side
# of it. The bound values come from the dtypes themselves, so the two sides
# cannot drift: if dt_max moves, the case moves with it.
# ===========================================================================

type Bounds is Data:
  Bounds{lo: H.I64, hi: H.I64, di: S.Dt}

def commit_text(m: Maybe<&1, S.Dt>) -> String:
  match m:
    case Some{d}: D.dt_name(d)
    case None{}: "-"

def commit_row(+lo: H.I64, +hi: H.I64, +di: S.Dt) -> String:
  String.concat([H.i64_text(lo), "\t", H.i64_text(hi), "\t", D.dt_name(di),
    "\t", commit_text(D.commit_int(lo, hi, di)), "\n"])

def commit_go(bs: List<&2, Bounds>, acc: String) -> String:
  match bs:
    case Nil{}: acc
    case b <> t:
      match b:
        case Bounds{lo, hi, di}: commit_go(t, String.append(acc, commit_row(lo, hi, di)))

def commit_rows(bs: List<&2, Bounds>, acc: String) -> String:
  commit_go(bs, acc)

def bounds_of(d: S.Dt, lo: H.I64, hi: H.I64) -> Bounds:
  Bounds{lo, hi, d}

# The cases: every (default_int, lo, hi) where lo and hi are boundary values.
# That is `dtypes.all()` crossed with `edges() x edges()`, and the crossing is a
# fold over the outer list with the inner fold as the accumulator step -- so one
# def per level, and no mutable state.
def commit_bounds.row(+lo: H.I64, his: List<&2, H.I64>, +d: S.Dt, acc: List<&2, Bounds>) ->
  List<&2, Bounds>:
  match his:
    case Nil{}: acc
    case hi <> hrest: commit_bounds.row(lo, hrest, d,
      List.append(&2, Bounds, acc, [bounds_of(d, lo, hi)]))

def commit_bounds.pairs.go(los: List<&2, H.I64>, +his: List<&2, H.I64>, +d: S.Dt,
  acc: List<&2, Bounds>) -> List<&2, Bounds>:
  match los:
    case Nil{}: acc
    case lo <> lrest: commit_bounds.pairs.go(lrest, his, d, commit_bounds.row(lo, his, d, acc))

def commit_bounds.pairs(los: List<&2, H.I64>, his: List<&2, H.I64>, d: S.Dt,
  acc: List<&2, Bounds>) -> List<&2, Bounds>:
  commit_bounds.pairs.go(los, his, d, acc)

def commit_bounds.all(+vs: List<&2, H.I64>, ds: List<&2, S.Dt>, acc: List<&2, Bounds>) ->
  List<&2, Bounds>:
  match ds:
    case Nil{}: acc
    case d <> t: commit_bounds.all(vs, t, commit_bounds.pairs(vs, vs, d, acc))

# default_int is one of the EIGHT INTEGER DTYPES. A float default_int is a real
# port limit, not a fixture choice: CPython's `DType.min` for a float is
# `-self.max` and its `.max` is `+inf`, so `commit_int(0, 0, dtypes.fp8e4m3)`
# answers dtypes.fp8e4m3, while `Cls.sgn` here answers None for anything that is
# not a signed or unsigned int, the bounds come back absent and `commit_int`
# falls through to int32/int64. `bool` is the same shape (CPython's min/max are
# the bools False/True). Group 0 gates all seventeen dtypes including those two;
# this group gates the integer ladder only, and both lanes generate the same
# cases from their own limits.
def commit_bounds(vs: List<&2, H.I64>, ds: List<&2, S.Dt>) -> List<&2, Bounds>:
  commit_bounds.all(vs, List.append(&2, S.Dt, D.dtypes.uints(), D.dtypes.sints()), Nil{})

# a limit and the values either side of it
def near(a: Maybe<&1, H.I64>, acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match a:
    case Some{+v}: List.append(&2, H.I64, acc,
      [H.i64_sub(v, H.i64_of_i32(1)), v, H.i64_add(v, H.i64_of_i32(1))])
    case None{}: acc

def i64_edges(+d: S.Dt) -> List<&2, H.I64>:
  near(D.dt_min(d), near(D.dt_max(d), [H.i64_of_i32(0)]))

def edges.go(ds: List<&2, S.Dt>, acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match ds:
    case Nil{}: acc
    case d <> t: edges.go(t, List.append(&2, H.I64, acc, i64_edges(d)))

# ONLY THE SIX DTYPES WHOSE bitsize IS AT MOST 32 GENERATE EDGES. The I64 is a
# SIGNED pair of U32s, so its range is [-2^63, 2^63-1]: int64's `min - 1` and
# uint64's `max + 1` have no image, and `i64_sub`/`i64_add` SATURATE rather than
# wrapping -- so int64's min-1 would print as 2147483647:4294967295, which is
# +2^63-1, a value the I64 does hold. Two different cases, one row, and the row
# says the wrong thing; uint64's three top edges were 3930 red rows, all of them
# the u64 rung of `commit_int` answering int64 where CPython answers uint64.
#
# What is given up is stated rather than hidden: int64's and uint64's LIMITS are
# still gated, in the `rows` group above, and the u64 row there is the one place
# the signed-pair deviation is reported instead of restated three thousand times.
def edges() -> List<&2, H.I64>:
  edges.go([S.int8(), S.uint8(), S.int16(), S.uint16(), S.int32(), S.uint32()], Nil{})

def main() -> IO(Unit):
  do IO<Unit>:
    +all : List<&2, S.Dt> <- IO.pure(List<&2, S.Dt>, D.dtypes.all())
    bs : List<&2, Bounds> <- IO.pure(List<&2, Bounds>, commit_bounds(edges(), all))
    IO.print(rows(all, ""))
    IO.print(lut_rows(all))
    IO.print(clc_rows(all))
    IO.print(sum_rows(S.single(), all, ""))
    IO.print(sum_rows(S.bfloat16(), all, ""))
    IO.print(sum_rows(S.half(), all, ""))
    IO.print(finfo_rows(D.dtypes.floats(), ""))
    IO.print(commit_rows(bs, ""))
