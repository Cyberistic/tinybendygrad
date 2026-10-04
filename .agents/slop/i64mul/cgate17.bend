import Base
# cmod/cdiv gate against the LANDED helpers.bend, reached through H.
import ./../../../tinybendygrad/helpers.bend as H

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
    cdrow("c_r79", 4270016772, 4229379224, 2769189684, 2762606516)
    cmrow("c_r79", 4270016772, 4229379224, 2769189684, 2762606516)
