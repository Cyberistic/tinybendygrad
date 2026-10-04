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
    drow("s_1_1", 0, 1, 0, 1)
    mrow("s_1_1", 0, 1, 0, 1)
    crow("s_1_1", 0, 1, 0, 1)
    krow("s_1_1", 0, 1, 0, 1)
    grow("s_1_1", 0, 1, 0, 1)
    drow("s_1_-1", 0, 1, 4294967295, 4294967295)
    mrow("s_1_-1", 0, 1, 4294967295, 4294967295)
    crow("s_1_-1", 0, 1, 4294967295, 4294967295)
    krow("s_1_-1", 0, 1, 4294967295, 4294967295)
    grow("s_1_-1", 0, 1, 4294967295, 4294967295)
    drow("s_1_2", 0, 1, 0, 2)
    mrow("s_1_2", 0, 1, 0, 2)
    crow("s_1_2", 0, 1, 0, 2)
    krow("s_1_2", 0, 1, 0, 2)
    grow("s_1_2", 0, 1, 0, 2)
    drow("s_1_-2", 0, 1, 4294967295, 4294967294)
    mrow("s_1_-2", 0, 1, 4294967295, 4294967294)
    crow("s_1_-2", 0, 1, 4294967295, 4294967294)
    krow("s_1_-2", 0, 1, 4294967295, 4294967294)
    grow("s_1_-2", 0, 1, 4294967295, 4294967294)
    drow("s_1_3", 0, 1, 0, 3)
    mrow("s_1_3", 0, 1, 0, 3)
    crow("s_1_3", 0, 1, 0, 3)
    krow("s_1_3", 0, 1, 0, 3)
    grow("s_1_3", 0, 1, 0, 3)
    drow("s_1_-3", 0, 1, 4294967295, 4294967293)
    mrow("s_1_-3", 0, 1, 4294967295, 4294967293)
    crow("s_1_-3", 0, 1, 4294967295, 4294967293)
    krow("s_1_-3", 0, 1, 4294967295, 4294967293)
    grow("s_1_-3", 0, 1, 4294967295, 4294967293)
    drow("s_1_4", 0, 1, 0, 4)
    mrow("s_1_4", 0, 1, 0, 4)
    crow("s_1_4", 0, 1, 0, 4)
    krow("s_1_4", 0, 1, 0, 4)
    grow("s_1_4", 0, 1, 0, 4)
    drow("s_1_-4", 0, 1, 4294967295, 4294967292)
    mrow("s_1_-4", 0, 1, 4294967295, 4294967292)
    crow("s_1_-4", 0, 1, 4294967295, 4294967292)
    krow("s_1_-4", 0, 1, 4294967295, 4294967292)
    grow("s_1_-4", 0, 1, 4294967295, 4294967292)
    drow("s_1_5", 0, 1, 0, 5)
    mrow("s_1_5", 0, 1, 0, 5)
    crow("s_1_5", 0, 1, 0, 5)
    krow("s_1_5", 0, 1, 0, 5)
    grow("s_1_5", 0, 1, 0, 5)
    drow("s_1_-5", 0, 1, 4294967295, 4294967291)
    mrow("s_1_-5", 0, 1, 4294967295, 4294967291)
    crow("s_1_-5", 0, 1, 4294967295, 4294967291)
    krow("s_1_-5", 0, 1, 4294967295, 4294967291)
    grow("s_1_-5", 0, 1, 4294967295, 4294967291)
    drow("s_1_7", 0, 1, 0, 7)
    mrow("s_1_7", 0, 1, 0, 7)
    crow("s_1_7", 0, 1, 0, 7)
    krow("s_1_7", 0, 1, 0, 7)
    grow("s_1_7", 0, 1, 0, 7)
    drow("s_1_-7", 0, 1, 4294967295, 4294967289)
    mrow("s_1_-7", 0, 1, 4294967295, 4294967289)
    crow("s_1_-7", 0, 1, 4294967295, 4294967289)
    krow("s_1_-7", 0, 1, 4294967295, 4294967289)
    grow("s_1_-7", 0, 1, 4294967295, 4294967289)
    drow("s_1_8", 0, 1, 0, 8)
    mrow("s_1_8", 0, 1, 0, 8)
    crow("s_1_8", 0, 1, 0, 8)
    krow("s_1_8", 0, 1, 0, 8)
    grow("s_1_8", 0, 1, 0, 8)
    drow("s_1_-8", 0, 1, 4294967295, 4294967288)
    mrow("s_1_-8", 0, 1, 4294967295, 4294967288)
    crow("s_1_-8", 0, 1, 4294967295, 4294967288)
    krow("s_1_-8", 0, 1, 4294967295, 4294967288)
    grow("s_1_-8", 0, 1, 4294967295, 4294967288)
    drow("s_1_9", 0, 1, 0, 9)
    mrow("s_1_9", 0, 1, 0, 9)
    crow("s_1_9", 0, 1, 0, 9)
    krow("s_1_9", 0, 1, 0, 9)
    grow("s_1_9", 0, 1, 0, 9)
    drow("s_1_8", 0, 1, 0, 8)
    mrow("s_1_8", 0, 1, 0, 8)
    crow("s_1_8", 0, 1, 0, 8)
    krow("s_1_8", 0, 1, 0, 8)
    grow("s_1_8", 0, 1, 0, 8)
    drow("s_1_65536", 0, 1, 0, 65536)
    mrow("s_1_65536", 0, 1, 0, 65536)
    crow("s_1_65536", 0, 1, 0, 65536)
    krow("s_1_65536", 0, 1, 0, 65536)
    grow("s_1_65536", 0, 1, 0, 65536)
    drow("s_1_2147483648", 0, 1, 0, 2147483648)
    mrow("s_1_2147483648", 0, 1, 0, 2147483648)
    crow("s_1_2147483648", 0, 1, 0, 2147483648)
    krow("s_1_2147483648", 0, 1, 0, 2147483648)
    grow("s_1_2147483648", 0, 1, 0, 2147483648)
    drow("s_1_2147483647", 0, 1, 0, 2147483647)
    mrow("s_1_2147483647", 0, 1, 0, 2147483647)
    crow("s_1_2147483647", 0, 1, 0, 2147483647)
    krow("s_1_2147483647", 0, 1, 0, 2147483647)
    grow("s_1_2147483647", 0, 1, 0, 2147483647)
    drow("s_1_4294967296", 0, 1, 1, 0)
    mrow("s_1_4294967296", 0, 1, 1, 0)
    crow("s_1_4294967296", 0, 1, 1, 0)
    krow("s_1_4294967296", 0, 1, 1, 0)
    grow("s_1_4294967296", 0, 1, 1, 0)
