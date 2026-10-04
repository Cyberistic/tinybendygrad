# gate_dtype.bend -- the six laws retired in dtype.bend, one row per law per
# PATTERN, swept over a contiguous range in ONE invocation.
#
# WHY A SWEEP AND NOT ONE PROCESS PER CASE. A per-case harness needs two Python
# processes per case (expectations + driver), and at 2576 cases that did not
# finish in two minutes. This driver takes FB_START / FB_COUNT the way
# `sweep.bend` does and answers four rows per pattern:
#
#   bf16_<p>=<pattern>          F32.bits(float_to_bf16(from_bits(p)))
#   fp16_<p>=<pattern>          F32.bits(float_to_fp16(from_bits(p)))
#   fp8_<k>_<c>=<pattern>       F32.bits(fp8_to_float(c, kind k)), c = p & 255
#
# so one invocation covers FB_COUNT patterns x four laws, and the fp8 codes it
# exercises are `p & 255` -- all 256 of them, repeatedly, in any block of 256.
#
# THE JS-LANE EXCLUSION IS NOT IN HERE. A row whose expected ANSWER is a NaN
# pattern cannot be checked in the JS lane, because `F32.bits` there collapses
# every NaN onto 0x7FC00000 (comp.ts:539) and a correct port reads back a
# different pattern -- a false red, not a bug. `gate_dtype.py` decides that from
# the ORACLE's answer, not from the driver's, and prints the skipped count.
import Base
import ../../../tinybendygrad/base.bend as F
import ../../../tinybendygrad/dtype.bend as D
import ../../../tinybendygrad/helpers.bend as H

def r1(p: U32, b: U32) -> String:
  String.concat(["bf16_", U32.show(p), "=", U32.show(F32.bits(D.Dt.bf16(b))),
                 " "])

def r16(p: U32, b: U32) -> String:
  String.concat(["fp16_", U32.show(p), "=",
                 U32.show(F32.bits(D.Dt.fp16(F.F32.from_bits(b)))), " "])

def r8(+p: U32, k: U32, kind: U32) -> String:
  String.concat(["fp8_", U32.show(k), "_", U32.show(U32.and(p, 255)), "=",
                 U32.show(F32.bits(D.Dt.fp8_to(U32.and(p, 255), kind))), " "])

def one(+p: U32) -> List<&2, String>:
  [r1(p, p), r16(p, p), r8(p, 0, 0), r8(p, 1, 1), r8(p, 2, 2), r8(p, 3, 3)]

# TWO quadratic traps, both in the OUTPUT path, and both were found by TIMING
# rather than by a row. JavaScript's rope strings make both of them free, so the
# JS lane ran this driver over 463360 rows without noticing either -- which is
# the whole reason a green JS run is not evidence about the C lane.
#
#   1. a linear String accumulator carried down the recursion is REBUILT at every
#      step. MEASURED in C: 1024 patterns 2.0s, 2048 7.6s, 4096 30s, 8192 did
#      not finish.
#   2. so is `String.concat([acc, row])`, for the same reason -- so the fix is
#      not "use a list" but "concatenate ONCE, at the end".
#
# So the accumulator is a LIST and the whole output is one `String.concat` pass.
# Rows come out REVERSED: each pattern's six rows are consed onto the front and
# the accumulator is reversed ONCE. `List.append` gives that for free -- it walks
# its first argument, six elements -- and agent-core records it reversing the
# order its arguments were WRITTEN in, which is the trap, not the feature.
def sweep(m: Nat, fuel: Word(m), +start: U32, +i: U32,
          acc: List<&2, String>) -> List<&2, String>:
  match m fuel:
    case 0n WNil{}:
      List.reverse(&2, String, acc)
    case 1n+p WCon{b, rest}:
      pat = U32.add(start, i)
      sweep(p, rest, start, U32.add(i, 1),
            List.append(&2, String, one(pat), acc))

def run(start: U32, cn: U32) -> String:
  +count = U32.to_nat(cn)
  String.concat(sweep(count, Word.zero(count), start, 0, Nil{}))

def main() -> IO(Unit):
  do IO<Unit>:
    st : U32 <- H.getenv_int("FB_START", 0)
    cn : U32 <- H.getenv_int("FB_COUNT", 0)
    p : Unit <- IO.print(run(st, cn))
    return p
