import Base
# I64DIV gate header. Every def under test is reached THROUGH H, i.e. through the
# real tinybendygrad/helpers.bend. This file defines NO i64 arithmetic of its own,
# so a mutation of helpers.bend moves these rows.
import ./../../../tinybendygrad/helpers.bend as H

def drow(nm: String, ah: U32, al: U32, bh: U32, bl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["d_", nm, "=",
      H.i64_text(H.i64_div(H.i64_of_hi_lo(ah, al), H.i64_of_hi_lo(bh, bl)))]))

def mrow(nm: String, ah: U32, al: U32, bh: U32, bl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["m_", nm, "=",
      H.i64_text(H.i64_mod(H.i64_of_hi_lo(ah, al), H.i64_of_hi_lo(bh, bl)))]))

def crow(nm: String, ah: U32, al: U32, bh: U32, bl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["c_", nm, "=",
      H.i64_text(H.cdiv_i64(H.i64_of_hi_lo(ah, al), H.i64_of_hi_lo(bh, bl)))]))

def krow(nm: String, ah: U32, al: U32, bh: U32, bl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["k_", nm, "=",
      H.i64_text(H.cmod_i64(H.i64_of_hi_lo(ah, al), H.i64_of_hi_lo(bh, bl)))]))

def grow(nm: String, ah: U32, al: U32, bh: U32, bl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["g_", nm, "=",
      H.i64_text(H.gcd(H.i64_of_hi_lo(ah, al), H.i64_of_hi_lo(bh, bl)))]))

def trow(nm: String, ah: U32, al: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["t_", nm, "=", H.i64_dec(H.i64_of_hi_lo(ah, al))]))

def main() -> IO(Unit):
  do IO<Unit>:
    drow("q54", 2147483647, 4294967294, 4294967295, 4294967295)
    mrow("q54", 2147483647, 4294967294, 4294967295, 4294967295)
    crow("q54", 2147483647, 4294967294, 4294967295, 4294967295)
    krow("q54", 2147483647, 4294967294, 4294967295, 4294967295)
    grow("q54", 2147483647, 4294967294, 4294967295, 4294967295)
    drow("q55", 4294967295, 4294967295, 0, 3)
    mrow("q55", 4294967295, 4294967295, 0, 3)
    crow("q55", 4294967295, 4294967295, 0, 3)
    krow("q55", 4294967295, 4294967295, 0, 3)
    grow("q55", 4294967295, 4294967295, 0, 3)
    drow("q56", 2147483647, 4294967295, 0, 2)
    mrow("q56", 2147483647, 4294967295, 0, 2)
    crow("q56", 2147483647, 4294967295, 0, 2)
    krow("q56", 2147483647, 4294967295, 0, 2)
    grow("q56", 2147483647, 4294967295, 0, 2)
    drow("q57", 2147483647, 4294967295, 0, 1)
    mrow("q57", 2147483647, 4294967295, 0, 1)
    crow("q57", 2147483647, 4294967295, 0, 1)
    krow("q57", 2147483647, 4294967295, 0, 1)
    grow("q57", 2147483647, 4294967295, 0, 1)
    drow("q58", 4294967295, 4294967295, 0, 2)
    mrow("q58", 4294967295, 4294967295, 0, 2)
    crow("q58", 4294967295, 4294967295, 0, 2)
    krow("q58", 4294967295, 4294967295, 0, 2)
    grow("q58", 4294967295, 4294967295, 0, 2)
    drow("q59", 2147483647, 4294967295, 0, 3)
    mrow("q59", 2147483647, 4294967295, 0, 3)
    crow("q59", 2147483647, 4294967295, 0, 3)
    krow("q59", 2147483647, 4294967295, 0, 3)
    grow("q59", 2147483647, 4294967295, 0, 3)
