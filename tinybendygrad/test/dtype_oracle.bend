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
# least_upper over every pair of the twenty.
#
# One fold, not two nested ones: bend cannot mark a list tail reusable (a List is
# a Type, not Data), so the outer dtype rides as a Maybe and the shape is
# `a is None` until the first row opens. Each row is one line: the outer name,
# then one tab-separated answer per dtype in `dtypes.all()` order.
# ===========================================================================

def lut_row(+a: S.Dt, +b: S.Dt) -> String:
  String.concat([D.dt_name(a), "\t", D.dt_name(b), "\t",
    D.dt_name(D.least_upper.of(a, b)), "\t"])

def lut_rows.all(ds: List<&2, S.Dt>, a: Maybe<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case h <> t:
      match a:
        case Some{+left}: lut_rows.all(t, a, String.append(acc, lut_row(+left, h)))
        case None{}: lut_rows.all(t, Some{h}, String.append(acc, D.dt_name(h) <> "\t"))

def lut_rows.open(ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case h <> t: lut_rows.all(t, Some{h}, String.append(acc, D.dt_name(h) <> "\t"))

def lut_rows(ds: List<&2, S.Dt>) -> String:
  lut_rows.open(ds, "")

# ===========================================================================
# can_lossless_cast over every pair, same shape.
# ===========================================================================

def clc_row(+a: S.Dt, +b: S.Dt) -> String:
  String.concat([D.dt_name(a), "\t", D.dt_name(b), "\t",
    Bool.show(D.can_lossless_cast(a, b)), "\t"])

def clc_rows.all(ds: List<&2, S.Dt>, a: Maybe<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case h <> t:
      match a:
        case Some{left}: clc_rows.all(t, a, String.append(acc, clc_row(left, h)))
        case None{}: clc_rows.all(t, Some{h}, String.append(acc, D.dt_name(h) <> "\t"))

def clc_rows.open(ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case h <> t: clc_rows.all(t, Some{h}, String.append(acc, D.dt_name(h) <> "\t"))

def clc_rows(ds: List<&2, S.Dt>) -> String:
  clc_rows.open(ds, "")

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

def commit_bounds(vs: List<&2, H.I64>, ds: List<&2, S.Dt>) -> List<&2, Bounds>:
  commit_bounds.all(vs, ds, Nil{})

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

def edges() -> List<&2, H.I64>:
  edges.go([S.int8(), S.uint8(), S.int16(), S.uint16(), S.int32(), S.uint32(),
    S.int64(), S.uint64()], Nil{})

def main() -> IO(Unit):
  do IO<Unit>:
    all : List<&2, S.Dt> <- IO.pure(List<&2, S.Dt>, D.dtypes.all())
    bs : List<&2, Bounds> <- IO.pure(List<&2, Bounds>, commit_bounds(edges(), all))
    IO.print(rows(all, ""))
    IO.print(lut_rows(all))
    IO.print(clc_rows(all))
    IO.print(sum_rows(S.single(), all, ""))
    IO.print(sum_rows(S.bfloat16(), all, ""))
    IO.print(sum_rows(S.half(), all, ""))
    IO.print(finfo_rows(D.dtypes.floats(), ""))
    IO.print(commit_rows(bs, ""))
