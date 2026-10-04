import Base
# cmod/cdiv gate against the LANDED helpers.bend, reached through H.
# FOUR `..` AND NOT THREE: this copy of the previous unit's generator lives one
# directory deeper than `.agents/slop/i64mul/`, and a relative import that does not
# resolve fails with `no such file:` -- which the batched runner silently turns
# into `rows_present=0` and `852 rows changed`. Same class as the `$TMPDIR`
# relative-import trap in agent-core.md.
import ./../../../../tinybendygrad/helpers.bend as H

def cdiv_i64.h(+x: H.I64, +y: H.I64) -> H.I64:
  H.cdiv_i64(x, y)

def cmod_i64.h(+x: H.I64, +y: H.I64) -> H.I64:
  H.cmod_i64(x, y)

def cdrow(nm: String, xh: U32, xl: U32, yh: U32, yl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["cd_", nm, "=",
      H.i64_text(H.cdiv_i64(H.i64_of_hi_lo(xh, xl), H.i64_of_hi_lo(yh, yl)))]))

def cmrow(nm: String, xh: U32, xl: U32, yh: U32, yl: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["cm_", nm, "=",
      H.i64_text(H.cmod_i64(H.i64_of_hi_lo(xh, xl), H.i64_of_hi_lo(yh, yl)))]))

def main() -> IO(Unit):
  do IO<Unit>:
    cdrow("c_p0_0", 0, 1, 0, 3)
    cmrow("c_p0_0", 0, 1, 0, 3)
    cdrow("c_p0_1", 0, 2, 0, 4)
    cmrow("c_p0_1", 0, 2, 0, 4)
    cdrow("c_p1_-1", 0, 1, 0, 4)
    cmrow("c_p1_-1", 0, 1, 0, 4)
    cdrow("c_p1_0", 0, 2, 0, 3)
    cmrow("c_p1_0", 0, 2, 0, 3)
    cdrow("c_p1_1", 0, 3, 0, 4)
    cmrow("c_p1_1", 0, 3, 0, 4)
    cdrow("c_p8_-1", 0, 255, 0, 4)
    cmrow("c_p8_-1", 0, 255, 0, 4)
    cdrow("c_p8_0", 0, 256, 0, 3)
    cmrow("c_p8_0", 0, 256, 0, 3)
    cdrow("c_p8_1", 0, 257, 0, 4)
    cmrow("c_p8_1", 0, 257, 0, 4)
    cdrow("c_p16_-1", 0, 65535, 0, 4)
    cmrow("c_p16_-1", 0, 65535, 0, 4)
    cdrow("c_p16_0", 0, 65536, 0, 3)
    cmrow("c_p16_0", 0, 65536, 0, 3)
    cdrow("c_p16_1", 0, 65537, 0, 4)
    cmrow("c_p16_1", 0, 65537, 0, 4)
    cdrow("c_p31_-1", 0, 2147483647, 0, 4)
    cmrow("c_p31_-1", 0, 2147483647, 0, 4)
    cdrow("c_p31_0", 0, 2147483648, 0, 3)
    cmrow("c_p31_0", 0, 2147483648, 0, 3)
    cdrow("c_p31_1", 0, 2147483649, 0, 4)
    cmrow("c_p31_1", 0, 2147483649, 0, 4)
    cdrow("c_p32_-1", 0, 4294967295, 0, 4)
    cmrow("c_p32_-1", 0, 4294967295, 0, 4)
    cdrow("c_p32_0", 1, 0, 0, 3)
    cmrow("c_p32_0", 1, 0, 0, 3)
    cdrow("c_p32_1", 1, 1, 0, 4)
    cmrow("c_p32_1", 1, 1, 0, 4)
    cdrow("c_p62_-1", 1073741823, 4294967295, 0, 4)
    cmrow("c_p62_-1", 1073741823, 4294967295, 0, 4)
    cdrow("c_p62_0", 1073741824, 0, 0, 3)
    cmrow("c_p62_0", 1073741824, 0, 0, 3)
    cdrow("c_p62_1", 1073741824, 1, 0, 4)
    cmrow("c_p62_1", 1073741824, 1, 0, 4)
    cdrow("c_p63_-1", 2147483647, 4294967295, 0, 4)
    cmrow("c_p63_-1", 2147483647, 4294967295, 0, 4)
    cdrow("c_r0", 1923567076, 1390851128, 648258640, 1695753998)
    cmrow("c_r0", 1923567076, 1390851128, 648258640, 1695753998)
    cdrow("c_r1", 2308526296, 922121676, 3943519387, 1862494042)
    cmrow("c_r1", 2308526296, 922121676, 3943519387, 1862494042)
    cdrow("c_r2", 1922895273, 2503952625, 367397621, 2478638287)
    cmrow("c_r2", 1922895273, 2503952625, 367397621, 2478638287)
    cdrow("c_r3", 2045500108, 212984476, 3391346070, 571981485)
    cmrow("c_r3", 2045500108, 212984476, 3391346070, 571981485)
