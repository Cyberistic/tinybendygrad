# dec_check.bend -- `i64_dec` against CPython's `str(int)`, on the edges that matter.
import Base
import ./../../../tinybendygrad/helpers.bend as H

def row(hi: U32, lo: U32) -> IO(Unit):
  IO.print(H.i64_dec(H.i64_of_hi_lo(hi, lo)))

def main() -> IO(Unit):
  do IO<Unit>:
    row(0, 0)
    row(0, 1)
    row(0, 9)
    row(0, 10)
    row(0, 11)
    row(0, 99)
    row(0, 100)
    row(0, 999)
    row(0, 1000)
    row(0, 65535)
    row(0, 2147483647)
    row(0, 2147483648)
    row(0, 4294967295)
    row(1, 0)
    row(1, 1)
    row(0, 1000000000)
    row(2328306436, 2313682944)
    row(2147483647, 4294967295)
    row(4294967295, 4294967295)
    row(4294967295, 4294967294)
    row(4294967295, 0)
    row(4294967295, 4294967246)
    row(12345, 67890)
