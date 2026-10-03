# ===========================================================================
# THE PROBE. Is `fold.bend`'s `least_upper.of` COMMUTATIVE?
#
# dtype.py:193-194 spells `least_upper_dtype` as `min(set.intersection(...))`, which
# is order-independent by construction, so `least_upper(a,b) == least_upper(b,a)` for
# every a, b. `fold.bend`'s comment above `least_upper_dtypes.go` says the same --
# "`min` over an intersection is associative, so the fold and the n-ary call agree" --
# and `least_upper.of`'s own says "`void` is the bottom, so it is also the fold's
# identity". Both claims are FALSE if void answers differently on the two sides.
#
# This asks fold.bend's own exported def, so a row cannot be right on one side and
# wrong on the other. CPython answers KeyError on all 39 pairs naming void, which
# `.agents/slop/dtype-pri-oracle.py` measures, so there is no CPython value to diff:
# the property under test is the port's OWN stated one.
# ===========================================================================
import Base
import ../../tinybendygrad/uop/fold.bend as F
import ../../tinybendygrad/LAWS/spec.bend as S

def dts_all() -> List<&2, S.Dt>:
  [S.void(), S.weakint(), S.boolean(), S.int8(), S.uint8(), S.int16(), S.uint16(),
   S.int32(), S.uint32(), S.int64(), S.uint64(), S.weakfloat(), S.fp8e4m3(),
   S.fp8e5m2(), S.fp8e4m3fnuz(), S.fp8e5m2fnuz(), S.half(), S.bfloat16(),
   S.single(), S.double()]

# dtype.bend's dt_name is not importable (14 unfilled laws), so a dtype prints as its
# own table key: the (pri, bits) pair plus the name.
def tag(d: S.Dt) -> String:
  match d:
    case S.Dt{p, b, c, n}: String.concat([U32.show(p), "/", U32.show(b), " ", n])

def rows.go(ds: List<&2, S.Dt>, acc: String) -> String:
  match ds:
    case Nil{}: acc
    case +h <> t:
      rows.go(t, String.append(acc, String.concat([
        tag(h), "\tvoid<>=", tag(F.least_upper.of(S.void(), h)),
        "\t", tag(h), "<>void=", tag(F.least_upper.of(h, S.void())), "\n"])))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(rows.go(dts_all(), ""))