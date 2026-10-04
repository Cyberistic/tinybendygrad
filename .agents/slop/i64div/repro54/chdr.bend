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
