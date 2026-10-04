# sweep.bend -- ONE CHUNK of the F32.from_bits round-trip census.
#
# WHY IT IS CHUNKED AND WHY IT IS DRIVEN BY THE ENVIRONMENT. Bend has no tail
# call, so a recursion's depth IS its iteration count, and BOTH the compiler and
# the runtime have a stack ceiling: MEASURED on 2.0.34, `go(1m, Word.zero(1m))`
# overflows the compiler while *generating* C, and 40000 overflows the JS runtime
# (20000 is the last depth that ran). So one invocation does at most FB_COUNT
# patterns and the Python harness walks the range in chunks, taking FB_START.
#
# The counters, all modulo 2^32 because `U32.add` is `Word.add`:
#
#   tried      patterns stepped. Equals FB_COUNT unless the driver is wrong, and
#              Python compares it against what it asked for.
#   sum_in     SUM of the INPUT patterns. Python computes the same number from
#              the range alone, so a silent skip cannot hide: it would move
#              sum_in whether or not it moved `mismatch`. LANE-INDEPENDENT --
#              this is the anti-skip proof, and it is why it is over the inputs
#              and not over the round-tripped values.
#   mismatch   patterns where F32.bits(F32.from_bits(p)) != p.
#   nan_in     input patterns that are a NaN (exponent all ones, mantissa != 0).
#   nan_kept   of those, the ones that came back byte-identical.
#
# The NaN counters are the whole point: a from_bits that collapsed the payload
# would still answer every finite value correctly, and `mismatch` counts NaNs
# too -- but `nan_kept / nan_in` is the number the brief asks for, as a
# denominator rather than a yes.
import Base
import ../../../tinybendygrad/base.bend as F
import ../../../tinybendygrad/helpers.bend as H

type Cen is Data:
  Cen{tried: U32, sum_in: U32, mismatch: U32, nan_in: U32, nan_kept: U32}

def Cen.zero() -> Cen:
  Cen{0, 0, 0, 0, 0}

# Is p a NaN pattern? exponent all ones AND mantissa nonzero.
def is_nan(+p: U32) -> Bool:
  Bool.and(U32.is_eq(U32.and(p, 2139095040), 2139095040),
           U32.is_ne(U32.and(p, 8388607), 0))

def count_one(+p: U32, c: Cen) -> Cen:
  match c:
    case Cen{t, s, m, ni, nk}:
      +rt = F32.bits(F.F32.from_bits(p))
      +nan = is_nan(p)
      Cen{U32.add(t, 1), U32.add(s, p),
          U32.add(m, Bool.to_u32(U32.is_ne(rt, p))),
          U32.add(ni, Bool.to_u32(nan)),
          U32.add(nk, Bool.to_u32(Bool.and(nan, U32.is_eq(rt, p))))}

def sweep(m: Nat, fuel: Word(m), +start: U32, +i: U32, c: Cen) -> Cen:
  match m fuel:
    case 0n WNil{}:
      c
    case 1n+p WCon{b, rest}:
      i2 = U32.add(i, 1)
      sweep(p, rest, start, i2, count_one(U32.add(start, i), c))

def show(c: Cen, start: U32) -> String:
  match c:
    case Cen{t, s, m, ni, nk}:
      String.concat(["FB ", U32.show(start), " ", U32.show(t), " ", U32.show(s),
                     " ", U32.show(m), " ", U32.show(ni), " ", U32.show(nk)])

def run(+st: U32, cn: U32) -> String:
  +count = U32.to_nat(cn)
  show(sweep(count, Word.zero(count), st, 0, Cen.zero()), st)

def main() -> IO(Unit):
  do IO<Unit>:
    st : U32 <- H.getenv_int("FB_START", 0)
    cn : U32 <- H.getenv_int("FB_COUNT", 0)
    p : Unit <- IO.print(run(st, cn))
    return p
