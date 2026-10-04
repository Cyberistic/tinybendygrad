# ==== P1's BLAST RADIUS ON THE LIVE CORPUS, WHOLE LINE ====
# live py rows moved by the ONE arm: 0  (0 means the widening is inert)
#   inert on the corpus and it is also the CORRECT answer: no live graph holds a
#   CUSTOM/CUSTOMI arg, because the pattern compiler IR is not in `GRAPHS`.

# ==== THE VERDICT, P0 (no arm) vs P1 (the one arm) ====
  P0 node 1 CUSTOMI    MISMATCH arg
#       arg    py=n(suop,Dvoid)   bend=in(suop,Dvoid)
  P0 node 2 PYLITERAL  MISMATCH arg
#       arg    py=OADD   bend=rd(OADD,i0)
  P0 node 3 CUSTOM     MISMATCH arg
#       arg    py=n(s{0}.op is {1},Dvoid)   bend=in(s{0}.op is {1},Dvoid)
  P0 node 4 AND        MISMATCH dtype, shape
#       dtype  py=void   bend=?
#       shape  py=R   bend=?
# VERDICT P0: 5 field mismatches of 24; 19 agree
  P1 node 1 CUSTOMI    AGREE
  P1 node 2 PYLITERAL  MISMATCH arg
#       arg    py=OADD   bend=rd(OADD,i0)
  P1 node 3 CUSTOM     AGREE
  P1 node 4 AND        MISMATCH dtype, shape
#       dtype  py=void   bend=?
#       shape  py=R   bend=?
# VERDICT P1: 3 field mismatches of 24; 21 agree

# WHAT P1 DOES NOT FIX, and it is the other half of item 2:
#   node 2's `arg` is `OADD` vs `rd(OADD,i0)` and NO arm in `carg` can fix that,
#   because the bend side has no `Arg` constructor holding a bare `Op` at all --
#   `ns-oparg.bend` fails to compile with `expected : O.Arg / observed : O.Op`.
#   That is a TYPE CHANGE in uop/ops.bend, not a spelling change.
