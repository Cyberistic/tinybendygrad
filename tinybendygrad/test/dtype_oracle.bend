# dtype_oracle.bend -- print every table dtype.bend claims, in a form the Python
# oracle can diff line for line. Not the test itself: the diff IS the test, and
# it lives in .agents/slop/notes/dtype_oracle.py because the oracle is
# tinygrad's own Python, which is the only implementation whose answers count.
#
# Both lanes must print the same bytes, so the oracle script runs this twice.
import Base
import ../dtype.bend as D
import ../helpers.bend as H
import ../LAWS/spec.bend as S

def range_text(m: Maybe<&1, H.I64>) -> String:
  match m:
    case Some{v}: H.i64_text(v)
    case None{}: "-"

def fmax_text(m: Maybe<&1, F32>) -> String:
  match m:
    case Some{v}: F32.show(v)
    case None{}: "-"

# ---- the twenty dtypes: name, pri, bits, itemsize, the three predicates, range
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

# ---- least_upper over every pair
def lut_row(+a: S.Dt, +b: S.Dt) -> String:
  String.concat([D.dt_name(a), "\t", D.dt_name(b), "\t",
    D.dt_name(D.least_upper.of(a, b)), "\n"])

def lut_rows(ds: List<&2, S.Dt>, +a: S.Dt, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case h <> t: lut_rows(t, a, String.append(acc, lut_row(a, h)))

# ---- can_lossless_cast over every pair
def clc_row(+a: S.Dt, +b: S.Dt) -> String:
  String.concat([D.dt_name(a), "\t", D.dt_name(b), "\t",
    Bool.show(D.can_lossless_cast(a, b)), "\n"])

def clc_rows(ds: List<&2, S.Dt>, +a: S.Dt, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case h <> t: clc_rows(t, a, String.append(acc, clc_row(a, h)))

# ---- sum_acc_dtype under each SUM_DTYPE tinygrad accepts
def sum_row(+d: S.Dt, +sum: S.Dt) -> String:
  String.concat([D.dt_name(d), "\t", D.dt_name(sum), "\t",
    D.dt_name(D.sum_acc_dtype(d, sum)), "\n"])

def sum_rows(+sum: S.Dt, ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case h <> t: sum_rows(sum, t, String.append(acc, sum_row(h, sum)))

# ---- finfo over the floats
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

# ---- commit_int over the boundaries that decide a rung
type Bounds is Data:
  Bounds{lo: H.I64, hi: H.I64, di: S.Dt}

def commit_text(m: Maybe<&1, S.Dt>) -> String:
  match m:
    case Some{d}: D.dt_name(d)
    case None{}: "-"

def commit_go(bs: List<&2, Bounds>, acc: String) -> String:
  match bs:
    case Nil{}: acc
    case b <> t:
      match b:
        case Bounds{lo, hi, di}:
          commit_go(t, String.append(acc, commit_row(lo, hi, di)))

def commit_row(lo: H.I64, hi: H.I64, di: S.Dt) -> String:
  String.concat([H.i64_text(lo), "\t", H.i64_text(hi), "\t", D.dt_name(di),
    "\t", commit_text(D.commit_int(lo, hi, di)), "\n"])

def commit_rows(bs: List<&2, Bounds>, acc: String) -> String:
  commit_go(bs, acc)

def bounds_of(d: S.Dt, lo: H.I64, hi: H.I64) -> Bounds:
  Bounds{lo, hi, d}

def commit_bounds(lo: H.I64, hi: H.I64, ds: List<&2, S.Dt>, acc: List<&2, Bounds>) ->
  List<&2, Bounds>:
  match ds:
    case Nil{}: acc
    case d <> t: commit_bounds(lo, hi, t,
      List.append(&2, Bounds, acc, [bounds_of(d, lo, hi)]))

# every (lo, hi) pair that lands on a rung boundary, for each default_int
def edge_pairs() -> List<&2, Bounds>:
  edge_pairs.put(edges(), S.int32())

def edges() -> List<&2, H.I64>:
  List.append(&2, H.I64, List.concat(&2, H.I64,
    List.map(H.I64, H.I64, i64_edges, [S.int8(), S.uint8(), S.int16(), S.uint16(),
      S.int32(), S.uint32(), S.int64(), S.uint64()])), pairs())

# a value and the one either side of it: v-1, v, v+1 for each limit
def i64_edges(d: S.Dt) -> List<&2, H.I64>:
  near(D.dt_min(d), near(D.dt_max(d)))

def near(a: Maybe<&1, H.I64>, b: List<&2, H.I64>) -> List<&2, H.I64>:
  match a:
    case Some{v}: List.append(&2, H.I64, b, [v, H.i64_sub(v, H.i64_of_i32(1)),
      H.i64_add(v, H.i64_of_i32(1))])
    case None{}: b

def pairs() -> List<&2, H.I64>:
  pairs.go(H.i64_of_i32(0), 10n, Nil{})

def pairs.go(v: H.I64, k: Nat, acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match k:
    case 0n: acc
    case 1n+j: pairs.go(H.i64_add(v, H.i64_of_i32(1)), j, [v] <> acc)

def main() -> IO(Unit):
  do IO<Unit>:
    all : List<&2, S.Dt> <- IO.pure(List<&2, S.Dt>, D.dtypes.all())
    IO.print(rows(all, ""))
    IO.print(lut_rows(all, all, ""))
    IO.print(clc_rows(all, all, ""))
    IO.print(sum_rows(S.single(), all, ""))
    IO.print(sum_rows(S.bfloat16(), all, ""))
    IO.print(sum_rows(S.half(), all, ""))
    IO.print(finfo_rows(D.dtypes.floats(), ""))
    IO.print(commit_rows(commit_bounds(H.i64_of_i32(0), H.i64_of_i32(0),
      all, edge_pairs()), ""))
