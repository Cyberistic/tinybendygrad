# patir graph from `_get_clause(UPat(Ops.ADD), CUSTOMI('uop'))` -- 4 nodes, ops CUSTOMI PYLITERAL CUSTOM AND
# node id mapping (toposort order, which is what `emit_py` numbers by):
#    1 CUSTOMI      nsrc=0 arg=('uop', dtypes.void) dtype=dtypes.void tag=None
#    2 PYLITERAL    nsrc=0 arg=Ops.ADD dtype=dtypes.void tag=None
#    3 CUSTOM       nsrc=2 arg=('{0}.op is {1}', dtypes.void) dtype=dtypes.void tag=None
#    4 AND          nsrc=1 arg=None dtype=dtypes.void tag=None

# ---- W0 RuntimeError (LIVE) ----
  2:i1 7:CUSTOMI 4:void 1:R 2:i0 1:N 13:n(suop,Dvoid) 3:n()
  2:i2 9:PYLITERAL 4:void 1:R 2:i0 1:N 4:OADD 3:n()
  2:i3 6:CUSTOM 4:void 1:R 2:i0 1:N 23:n(s{0}.op is {1},Dvoid) 8:n(i1,i2)
  !! EMITTER DIED: AssertionError: None input shape not supported for Ops.AND

# ---- W1 +AssertionError ----
  2:i1 7:CUSTOMI 4:void 1:R 2:i0 1:N 13:n(suop,Dvoid) 3:n()
  2:i2 9:PYLITERAL 4:void 1:R 2:i0 1:N 4:OADD 3:n()
  2:i3 6:CUSTOM 4:void 1:R 2:i0 1:N 23:n(s{0}.op is {1},Dvoid) 8:n(i1,i2)
  2:i4 3:AND 4:void 1:R 2:i0 1:N 1:N 5:n(i3)
#   rows CHANGED vs W0: 1 of 4
#     W0 !! EMITTER DIED: AssertionError: None input shape not supported for Ops.AND
#     W1 2:i4 3:AND 4:void 1:R 2:i0 1:N 1:N 5:n(i3)

# ---- W4 bare Exception ----
  2:i1 7:CUSTOMI 4:void 1:R 2:i0 1:N 13:n(suop,Dvoid) 3:n()
  2:i2 9:PYLITERAL 4:void 1:R 2:i0 1:N 4:OADD 3:n()
  2:i3 6:CUSTOM 4:void 1:R 2:i0 1:N 23:n(s{0}.op is {1},Dvoid) 8:n(i1,i2)
  2:i4 3:AND 4:void 1:R 2:i0 1:N 1:N 5:n(i3)
#   rows CHANGED vs W0: 1 of 4
#     W0 !! EMITTER DIED: AssertionError: None input shape not supported for Ops.AND
#     W4 2:i4 3:AND 4:void 1:R 2:i0 1:N 1:N 5:n(i3)
