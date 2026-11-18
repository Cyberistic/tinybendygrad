<!-- FROM: tinybendygrad/codegen/kernel.bend:940 -->
# BLOCK:
# THE GATE. Every row is DERIVED FROM PYTHON by
# `.agents/slop/notes/kn-truth.py`, which prints its rows in THIS ORDER and with
# THIS SPELLING, so
# `diff <(python3 kn-truth.py) <(./bin/bend tinybendygrad/codegen/kernel.bend)` is
# the acceptance test and NEITHER side can be nudged to match the other.
#
# THE FIXTURE. `K.ix` is `[0]` then the interning order, so `K.at(k, n)` is a LIST
# POSITION. One `+` per node, because Bend has no store.
#
#   0 bottom  1 C0  2 C1  3 C4   4 SPECIAL   5 BUF(slot 7)  6 BUF(slot 3)
#   7 PRM(-1)  8 R_U=RANGE(C4,UNROLL)  9 R_L=RANGE(C4,LOOP)
#  10 SQ1=SQRT(C0)  11 ST1=STORE(C0, C1)
#  12 AL1=ALLOC(C1)  13 RD1=REDUCE(SQ1, R_U)
#  14 PR1=PROGRAM(SINK(SQ1))  15 PR2=PROGRAM(SINK(SQ1), LINEAR(ST1))
#  16 INS0=INS()  17 PR3=PROGRAM(SINK(SQ1), LINEAR(INS0))
#  18 PR4=PROGRAM(SINK(SQ1), LINEAR(ST1), SOURCE)
#
# `ix` prints the whole list and `pos_same` compares its length to `Arena.next`,
# and both exist because `PR3` was once built from `Found.ar(pr2)` -- a STALE
# arena, `INS0` having already been interned in it -- so `PR3` came back at index 17
# and every position after it named the node one slot behind its comment. That read
# as two rule bugs (`ins` answering 0, `al_store` answering NOOP) and was neither.
# A fixture whose rows cannot see the fixture is worse than no fixture.
# END BLOCK

# THE GATE. Every row is DERIVED FROM PYTHON by
# `.agents/slop/notes/kn-truth.py`, which prints its rows in THIS ORDER and with
# THIS SPELLING, so
# `diff <(python3 kn-truth.py) <(./bin/bend tinybendygrad/codegen/kernel.bend)` is
# the acceptance test and NEITHER side can be nudged to match the other.
#
# THE FIXTURE. `K.ix` is `[0]` then the interning order, so `K.at(k, n)` is a LIST
# POSITION. One `+` per node, because Bend has no store.
#
#   0 bottom  1 C0  2 C1  3 C4   4 SPECIAL   5 BUF(slot 7)  6 BUF(slot 3)
#   7 PRM(-1)  8 R_U=RANGE(C4,UNROLL)  9 R_L=RANGE(C4,LOOP)
#  10 SQ1=SQRT(C0)  11 ST1=STORE(C0, C1)
#  12 AL1=ALLOC(C1)  13 RD1=REDUCE(SQ1, R_U)
#  14 PR1=PROGRAM(SINK(SQ1))  15 PR2=PROGRAM(SINK(SQ1), LINEAR(ST1))
#  16 INS0=INS()  17 PR3=PROGRAM(SINK(SQ1), LINEAR(INS0))
#  18 PR4=PROGRAM(SINK(SQ1), LINEAR(ST1), SOURCE)
#
# `ix` prints the whole list and `pos_same` compares its length to `Arena.next`,
# and both exist because `PR3` was once built from `Found.ar(pr2)` -- a STALE
# arena, `INS0` having already been interned in it -- so `PR3` came back at index 17
# and every position after it named the node one slot behind its comment. That read
# as two rule bugs (`ins` answering 0, `al_store` answering NOOP) and was neither.
# A fixture whose rows cannot see the fixture is worse than no fixture.
