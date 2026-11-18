<!-- FROM: tinybendygrad/schedule/multi.bend:2305 -->
# BLOCK:
# THE FIXTURE. One `Data` record holding the ARENA and the node indices, built in a single
# `+`-chained chain because `Arena` is affine and every intermediate is a value. The nodes
# are the ones the TABLES turn on, not a random graph:
#  RD  a DEVICE RANGE over four devices -- the exact node `mu_count` reads
#  M0  UNSHARD of a buffer on axis 0     -- one sharded axis
#  M1  UNSHARD of a buffer on axis 1     -- one sharded axis, different axis
#  MA  UNSHARD on axes 0 AND 1           -- the two-axis case `mu_axis` refuses
#  AD  ADD(M0, M0)                       -- the ALU rule's claim
#  CP  COPY(M0)                          -- a COPY three rules claim
#  CQ  COPY(B8)                          -- a COPY of a WHOLE buffer
#  ST  STORE(B8, M0)                     -- a STORE two rules claim, src1 UNSHARD
#  SU  STORE(M0, M0)                     -- the same, src0 UNSHARD
#  MS  MSELECT(MSTACK(B8,B24))           -- the MSELECT-on-MSTACK rule
#  MS2 MSELECT(ADD(M0,M0))               -- the MSELECT-on-ALU rule
#  MT  MSTACK(MS, MS2)                   -- a Movement src[0] is NOT MSTACK here
# END BLOCK

# THE FIXTURE. One `Data` record holding the ARENA and the node indices, built in a single
# `+`-chained chain because `Arena` is affine and every intermediate is a value. The nodes
# are the ones the TABLES turn on, not a random graph:
#  RD  a DEVICE RANGE over four devices -- the exact node `mu_count` reads
#  M0  UNSHARD of a buffer on axis 0     -- one sharded axis
#  M1  UNSHARD of a buffer on axis 1     -- one sharded axis, different axis
#  MA  UNSHARD on axes 0 AND 1           -- the two-axis case `mu_axis` refuses
#  AD  ADD(M0, M0)                       -- the ALU rule's claim
#  CP  COPY(M0)                          -- a COPY three rules claim
#  CQ  COPY(B8)                          -- a COPY of a WHOLE buffer
#  ST  STORE(B8, M0)                     -- a STORE two rules claim, src1 UNSHARD
#  SU  STORE(M0, M0)                     -- the same, src0 UNSHARD
#  MS  MSELECT(MSTACK(B8,B24))           -- the MSELECT-on-MSTACK rule
#  MS2 MSELECT(ADD(M0,M0))               -- the MSELECT-on-ALU rule
#  MT  MSTACK(MS, MS2)                   -- a Movement src[0] is NOT MSTACK here
