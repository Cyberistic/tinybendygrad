# T1-WIRE -- which way does an `H.I64` argument actually arrive?
#
# `Dt.i64_trunc` is the identity on a pair, so the SEAM's own contract says the
# answer equals the input. That is the discriminator: it is definitional, so no
# oracle is needed and it cannot pass by accident. See ./t1_wire.c for the two
# readers and the differential.
#
# U32 is linear (LC-3), so each row builds its own pair inline.
import ../../../tinybendygrad/helpers.bend as H

law WIRE_FLAT:
  H.I64 -> IO(H.I64)

def WIRE_FLAT(x):
  import "./t1_wire.c"

law WIRE_BOXED:
  H.I64 -> IO(H.I64)

def WIRE_BOXED(x):
  import "./t1_wire.c"

law WIRE_BOXED_SWAP:
  H.I64 -> IO(H.I64)

def WIRE_BOXED_SWAP(x):
  import "./t1_wire.c"

law WIRE_BOXED_SAME:
  H.I64 -> IO(H.I64)

def WIRE_BOXED_SAME(x):
  import "./t1_wire.c"

# FIXTURES, half of them with EQUAL halves. An ordering bug is invisible on an
# equal-halves row, so a fixture set with none of them cannot fail a swap at all.
# These eight are named in gen_wire.py and the gate reads the names off the rows.

def main() -> IO(Unit):
  do IO<Unit>:
    # ---- rows whose halves DIFFER: 4 fixtures x 4 readers
    a1 : H.I64 <- WIRE_FLAT(H.i64_of_hi_lo(1, 2))
    b1 : H.I64 <- WIRE_BOXED(H.i64_of_hi_lo(1, 2))
    s1 : H.I64 <- WIRE_BOXED_SWAP(H.i64_of_hi_lo(1, 2))
    e1 : H.I64 <- WIRE_BOXED_SAME(H.i64_of_hi_lo(1, 2))
    IO.print("WIRE flat|1|2 = " ++ H.i64_text(a1))
    IO.print("WIRE boxed|1|2 = " ++ H.i64_text(b1))
    IO.print("WIRE swap|1|2 = " ++ H.i64_text(s1))
    IO.print("WIRE same|1|2 = " ++ H.i64_text(e1))
    a2 : H.I64 <- WIRE_FLAT(H.i64_of_hi_lo(123456, 654321))
    b2 : H.I64 <- WIRE_BOXED(H.i64_of_hi_lo(123456, 654321))
    s2 : H.I64 <- WIRE_BOXED_SWAP(H.i64_of_hi_lo(123456, 654321))
    e2 : H.I64 <- WIRE_BOXED_SAME(H.i64_of_hi_lo(123456, 654321))
    IO.print("WIRE flat|123456|654321 = " ++ H.i64_text(a2))
    IO.print("WIRE boxed|123456|654321 = " ++ H.i64_text(b2))
    IO.print("WIRE swap|123456|654321 = " ++ H.i64_text(s2))
    IO.print("WIRE same|123456|654321 = " ++ H.i64_text(e2))
    a3 : H.I64 <- WIRE_FLAT(H.i64_of_hi_lo(0, 7))
    b3 : H.I64 <- WIRE_BOXED(H.i64_of_hi_lo(0, 7))
    s3 : H.I64 <- WIRE_BOXED_SWAP(H.i64_of_hi_lo(0, 7))
    e3 : H.I64 <- WIRE_BOXED_SAME(H.i64_of_hi_lo(0, 7))
    IO.print("WIRE flat|0|7 = " ++ H.i64_text(a3))
    IO.print("WIRE boxed|0|7 = " ++ H.i64_text(b3))
    IO.print("WIRE swap|0|7 = " ++ H.i64_text(s3))
    IO.print("WIRE same|0|7 = " ++ H.i64_text(e3))
    a4 : H.I64 <- WIRE_FLAT(H.i64_of_hi_lo(4000000000, 4000000001))
    b4 : H.I64 <- WIRE_BOXED(H.i64_of_hi_lo(4000000000, 4000000001))
    s4 : H.I64 <- WIRE_BOXED_SWAP(H.i64_of_hi_lo(4000000000, 4000000001))
    e4 : H.I64 <- WIRE_BOXED_SAME(H.i64_of_hi_lo(4000000000, 4000000001))
    IO.print("WIRE flat|4000000000|4000000001 = " ++ H.i64_text(a4))
    IO.print("WIRE boxed|4000000000|4000000001 = " ++ H.i64_text(b4))
    IO.print("WIRE swap|4000000000|4000000001 = " ++ H.i64_text(s4))
    IO.print("WIRE same|4000000000|4000000001 = " ++ H.i64_text(e4))
    # ---- rows whose halves are EQUAL: the negative control
    a5 : H.I64 <- WIRE_FLAT(H.i64_of_hi_lo(0, 0))
    b5 : H.I64 <- WIRE_BOXED(H.i64_of_hi_lo(0, 0))
    s5 : H.I64 <- WIRE_BOXED_SWAP(H.i64_of_hi_lo(0, 0))
    e5 : H.I64 <- WIRE_BOXED_SAME(H.i64_of_hi_lo(0, 0))
    IO.print("WIRE flat|0|0 = " ++ H.i64_text(a5))
    IO.print("WIRE boxed|0|0 = " ++ H.i64_text(b5))
    IO.print("WIRE swap|0|0 = " ++ H.i64_text(s5))
    IO.print("WIRE same|0|0 = " ++ H.i64_text(e5))
    a6 : H.I64 <- WIRE_FLAT(H.i64_of_hi_lo(7, 7))
    b6 : H.I64 <- WIRE_BOXED(H.i64_of_hi_lo(7, 7))
    s6 : H.I64 <- WIRE_BOXED_SWAP(H.i64_of_hi_lo(7, 7))
    e6 : H.I64 <- WIRE_BOXED_SAME(H.i64_of_hi_lo(7, 7))
    IO.print("WIRE flat|7|7 = " ++ H.i64_text(a6))
    IO.print("WIRE boxed|7|7 = " ++ H.i64_text(b6))
    IO.print("WIRE swap|7|7 = " ++ H.i64_text(s6))
    IO.print("WIRE same|7|7 = " ++ H.i64_text(e6))
    a7 : H.I64 <- WIRE_FLAT(H.i64_of_hi_lo(4294967295, 4294967295))
    b7 : H.I64 <- WIRE_BOXED(H.i64_of_hi_lo(4294967295, 4294967295))
    s7 : H.I64 <- WIRE_BOXED_SWAP(H.i64_of_hi_lo(4294967295, 4294967295))
    e7 : H.I64 <- WIRE_BOXED_SAME(H.i64_of_hi_lo(4294967295, 4294967295))
    IO.print("WIRE flat|4294967295|4294967295 = " ++ H.i64_text(a7))
    IO.print("WIRE boxed|4294967295|4294967295 = " ++ H.i64_text(b7))
    IO.print("WIRE swap|4294967295|4294967295 = " ++ H.i64_text(s7))
    IO.print("WIRE same|4294967295|4294967295 = " ++ H.i64_text(e7))
    a8 : H.I64 <- WIRE_FLAT(H.i64_of_hi_lo(2147483648, 2147483648))
    b8 : H.I64 <- WIRE_BOXED(H.i64_of_hi_lo(2147483648, 2147483648))
    s8 : H.I64 <- WIRE_BOXED_SWAP(H.i64_of_hi_lo(2147483648, 2147483648))
    e8 : H.I64 <- WIRE_BOXED_SAME(H.i64_of_hi_lo(2147483648, 2147483648))
    IO.print("WIRE flat|2147483648|2147483648 = " ++ H.i64_text(a8))
    IO.print("WIRE boxed|2147483648|2147483648 = " ++ H.i64_text(b8))
    IO.print("WIRE swap|2147483648|2147483648 = " ++ H.i64_text(s8))
    IO.print("WIRE same|2147483648|2147483648 = " ++ H.i64_text(e8))