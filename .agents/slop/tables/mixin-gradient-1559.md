<!-- FROM: tinybendygrad/mixin/gradient.bend:1559 -->
# BLOCK:
# THE NODE LIST, in binding order. The comment on each line says what the node is and
# WHICH TAG claims it -- and for three of them, what ELSE claims it.
#
#   0 bottom          the arena's spent slot, and tinygrad's `None`
#   1 CONST 1.0       the seed ctx of every rule call
#   2 CONST 0.5       POW's base
#   3 CAST(1.0,int)   CAST's ret.src[0], whose dtype the rule reads
#   4 RECIP(1)   tag 1
#   5 SIN(1)          tag 2
#   6 LOG2(1)         tag 3
#   7 EXP2(1)         tag 4
#   8 SQRT(1)         tag 5
#   9 TRUNC(1)        tag 6
#  10 CMPLT(1,1)      tag 7 -- the ALL-HOLES answer
#  11 ADD(1,1)        tag 9 -- ctx in BOTH slots
#  12 POW(.5,1)       tag 10
#  13 MAX(1,1)        tag 11 -- a TIE, so the ctx*0.5 branch is live
#  14 MUL(1,1)        tag 12 -- a SQUARE, so interning makes both slots one node
#  15 WHERE(1,1,1)    tag 13
#  16 STAGE(1)        tag 16
#  17 EXPAND(1)       tag 18
#  18 RESHAPE(1,3)    tag 17 -- TWO srcs, so its 2-slot answer is EXACT here
#  19 SINK(1,.5)      tag 26 -- ctx.src is the answer
#  20 CAST(1,int)     tag 0 -- INT, not float: an identity cast FOLDS in `gcast`
#  21 BITCAST(3,float) tag 32 -- ONE hole for a ONE-src node
#  22 STORE(1,.5)     tag 31
#  23 BUFFER slot 0   no rule claims a BUFFER
#  24 BUFFER slot 1
#  25 STORE(A,1)      tag 29's STORE: dest is bufA, and so is the AFTER's src[0]
#  26 AFTER(A, 25)    tag 29 FIRES -- the identity holds. tag 28 and 30 also CLAIM it.
#  27 STORE(A,.5)     tag 29's STORE again, for the ordering-only AFTER
#  28 AFTER(B, 27)    tag 28's shape: dest is bufB, stored into bufA, so the identity
#                     FAILS and tag 29 must NOT fire.
#
