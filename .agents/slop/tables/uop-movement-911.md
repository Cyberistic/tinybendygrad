<!-- FROM: tinybendygrad/uop/movement.bend:900 at ba3f52b0a^; ba3f52b0a REPLACED the block -->

# THE GATE. Every row is DERIVED FROM PYTHON, via
# `.agents/slop/notes/mop-truth3.py`, which prints its rows in THIS ORDER and with THIS
# SPELLING, so `diff <(python3 mop-truth3.py | grep '=') <(./bin/bend movement.bend)` is the
# acceptance test and neither side can be nudged to match the other. A row here can be
# WRONG rather than merely restate this file. `mop-truth.py` is the earlier, partial
# oracle; `mop-truth3.py` is the one that covers the rows.
#
# THE FIXTURE, and the node indices it fixes. `G.ix` is `[0]` then the interning order
# MINUS `ki`, which `g()` builds and never lists -- so `G.at(g, n)` is a LIST POSITION and
# the last two positions are one below the arena index they hold. `mop-truth3.py` prints
# the whole map. Naming the nodes makes the result-index rows readable, since "the rewrite
# of P2 IS P3" is a Python fact.
#
#   0 bottom  1 C0   2 C1   3 C2   4 C4    5 SPECIAL   6 b4(size 4)
#   7 b0(none)  8 B24(img 2x4)   9 bimg(img 2x7)   10 o1(size 2)  11 o2(size 7)
#  12 S1=SHRINK(b4,C2,C2)      13 S2=SHRINK(S1,C1,C1)      rank 1
#  14 st2=STACK(C0,C1)  15 st11=STACK(C1,C1)  16 S3  17 S4 rank 2
#  18 st4=STACK(C4)  19 R1=RESHAPE(b4,C4)  20 R2=RESHAPE(R1,st4)  21 R3=RESHAPE(b4,st4)
#  22 P1=PERMUTE(B24,(1,0))  23 P2=PERMUTE(P1,(1,0))  24 P3=PERMUTE(B24,(0,1))
#  25 SS=STACK(C0,C1,C2)  26 E0=INDEX(bimg,C0)  27 E1=INDEX(bimg,C1)  28 STK
#  29 IX2=INDEX(SS,C1)  30 IX3=INDEX(SS,C1,C0)  31 IX5=INDEX(SS,C0,C0,C1)
#  32 J1=INDEX(b4,C0)  33 J2=INDEX(J1,C1)  34 J3=INDEX(IX2)
#  35 K1=INDEX(B24,o1)  36 K2=INDEX(K1,o2)  37 K3=INDEX(INDEX(B24,STK),o2)
#  38 ADD(C0,C1)
