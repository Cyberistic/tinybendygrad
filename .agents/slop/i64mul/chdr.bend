import Base
# cmod/cdiv gate against the LANDED helpers.bend, reached through H.
import ./../../../tinybendygrad/helpers.bend as H

def cdiv_i64.h(+x: H.I64, +y: H.I64) -> H.I64:
  H.cdiv_i64(x, y)

def cmod_i64.h(+x: H.I64, +y: H.I64) -> H.I64:
  H.cmod_i64(x, y)

