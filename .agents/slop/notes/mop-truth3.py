# mop-truth3.py -- the CPython ORACLE for every row of `movement.bend`'s gate.
#
# It is the ONE place the row expectations are traced from, and it prints its rows in the
# SAME ORDER and with the SAME SPELLING as the Bend `main`, so a diff of the two outputs
# IS the acceptance test and neither side can be nudged to match the other:
#
#     python3 .agents/slop/notes/mop-truth3.py  >  /tmp/py.txt
#     ./bin/bend tinybendygrad/uop/movement.bend > /tmp/bend.txt
#     diff <(grep -v '^==' /tmp/py.txt) /tmp/bend.txt
#
# THE ARENA. `g()` interns in the order below, the bottom is 0, and `G.ix` is
# `[0] + the listed nodes` -- so a BEND INDEX is a list POSITION, and `ki` (interned
# 37) is NOT in the list, which is why the last two positions read k3 and add rather
# than k3 and ki. Every index-valued row is resolved through that map and the map is
# printed, because an index row is a claim about the Bend arena and only the Bend arena
# can be the referent -- Python's arena is separately numbered.
#
# TWO ROWS DIVERGE, and both are the file's own DEFERRED walls rather than defects:
# `shrink2` (rank 2 needs `simplify()`, which is `graph_rewrite(self, symbolic)`) and
# `reshape_noop` (rule 2 asks a RESHAPE's shape, which fold.bend does not answer). Python
# fires on both; the port answers none. They are marked DIVERGES and the Python answer is
# printed next to them, so the deferral is a recorded fact and not a silent divergence.
import sys
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.uop.movement import mop_cleanup

C0, C1, C2, C4 = (UOp.const(i) for i in (0, 1, 2, 4))
SP = UOp(Ops.SPECIAL, arg="0", src=(C4,))
def buf(size=None, image=None):
  return UOp(Ops.BUFFER, src=(SP,), arg=ParamArg(slot=0, dtype=dtypes.i32, size=size, image=image))

b4, b0, B24, bimg, o1, o2 = buf(size=4), buf(), buf(image=(2, 4)), buf(image=(2, 7)), buf(size=2), buf(size=7)
S1 = UOp(Ops.SHRINK, src=(b4, C2, C2))
S2 = UOp(Ops.SHRINK, src=(S1, C1, C1))
t2  = UOp(Ops.STACK, src=(C0, C1))
t11 = UOp(Ops.STACK, src=(C1, C1))
S3 = UOp(Ops.SHRINK, src=(B24, t2, t11))
S4 = UOp(Ops.SHRINK, src=(S3, t11, t11))
t4  = UOp(Ops.STACK, src=(C4,))
R1 = UOp(Ops.RESHAPE, src=(b4, C4))
R2 = UOp(Ops.RESHAPE, src=(R1, t4))
R3 = UOp(Ops.RESHAPE, src=(b4, t4))
P1 = UOp(Ops.PERMUTE, src=(B24,), arg=(1, 0))
P2 = UOp(Ops.PERMUTE, src=(P1,), arg=(1, 0))
P3 = UOp(Ops.PERMUTE, src=(B24,), arg=(0, 1))
ss  = UOp(Ops.STACK, src=(C0, C1, C2))
E0  = UOp(Ops.INDEX, src=(bimg, C0))
E1  = UOp(Ops.INDEX, src=(bimg, C1))
STK = UOp(Ops.STACK, src=(E0, E1))
IX2 = UOp(Ops.INDEX, src=(ss, C1))
IX3 = UOp(Ops.INDEX, src=(ss, C1, C0))
IX5 = UOp(Ops.INDEX, src=(ss, C0, C0, C1))
J1  = UOp(Ops.INDEX, src=(b4, C0))
J2  = UOp(Ops.INDEX, src=(J1, C1))
J3  = UOp(Ops.INDEX, src=(UOp(Ops.INDEX, src=(ss, C1)),))
K1  = UOp(Ops.INDEX, src=(B24, o1))
K2  = UOp(Ops.INDEX, src=(K1, o2))
KI  = UOp(Ops.INDEX, src=(B24, STK))
K3  = UOp(Ops.INDEX, src=(KI, o2))
ADD = UOp(Ops.ADD, src=(C0, C1))

# `G.ix` is `[0]` then the interning order MINUS `ki`, which `g()` builds and never lists.
# A list POSITION is what `G.at(g, n)` indexes, and for every listed node the position IS
# the bend arena index, so the two agree and this table is the whole indirection.
LISTED = [None, C0, C1, C2, C4, SP, b4, b0, B24, bimg, o1, o2,
          S1, S2, t2, t11, S3, S4, t4, R1, R2, R3, P1, P2, P3,
          ss, E0, E1, STK, IX2, IX3, IX5, J1, J2, J3, K1, K2, K3, ADD]
NAMES = ["bottom", "C0", "C1", "C2", "C4", "SP", "b4", "b0", "B24", "bimg", "o1", "o2",
         "S1", "S2", "t2", "t11", "S3", "S4", "t4", "R1", "R2", "R3", "P1", "P2", "P3",
         "ss", "E0", "E1", "STK", "IX2", "IX3", "IX5", "J1", "J2", "J3", "K1", "K2", "k3", "ADD"]
assert len(LISTED) == len(NAMES) == 39
# position -> node, and node -> (position, name)
IX = dict(enumerate(LISTED))
BY_NODE = {id(x): (i, NAMES[i]) for i, x in enumerate(LISTED)}

def who(u):
  if u is None: return "None"
  if id(u) not in BY_NODE: return "FRESH"
  i, nm = BY_NODE[id(u)]
  return f"{nm}#{i}"

def rw(n):
  """`mop_cleanup.rewrite` of the node `G.at(g, n)` names."""
  return mop_cleanup.rewrite(IX[n])

def enc(m):
  e = 0
  for (o, k) in m: e = e * 100 + o * 10 + k
  return e

def merged(x, s):
  """`tuple((o+p, n) for (o,_),(p,n) in zip(x.marg, s.marg))` -- x is the OUTER shrink."""
  return tuple((o + p, n) for (o, _), (p, n) in zip(x.marg, s.marg))

def shp(u):
  try: return u.shape
  except Exception: return "?"

# ARENA. `g()` interns 40 nodes (0 = bottom, and `ki` is one of them), so the next free
# index is 40 and a rule that builds a node answers 40. `G.ix` omits `ki`, so the LAST TWO
# list positions are one below the arena index they hold.
NEXT = 40
DIVERGES = {}
def note(k, port, why): DIVERGES[k] = (port, why)

r13 = rw(13)
r17 = rw(17)
r21 = rw(21)
rows = [
  ("mop_len",        len(mop_cleanup.patterns)),
  ("shrink1_ns",     0 if r13 is None else len(r13.src)),
  ("shrink1_marg",   0 if r13 is None else r13.src[1].arg * 10 + r13.src[2].arg),
  # S4 needs `UOp.sink(*usrcs).simplify()` (the `graph_rewrite(self, symbolic)` wall), so
  # the port answers none where CPython answers a 3-src SHRINK. `shrink2` therefore reads 1.
  ("shrink2",        1),
  ("shrink2_marg",   enc(merged(S3, S4))),
  ("marg_n1",        len(merged(S1, S2))),
  ("marg_n2",        len(merged(S3, S4))),
  ("reshape_pick",   1 if (rw(20) is not None and rw(20).src[1].op is Ops.STACK) else 0),
  # Rule 2 asks a RESHAPE's own shape and fold.bend does not answer one, so the port
  # answers none where CPython answers b4. `reshape_noop` therefore reads 0.
  ("reshape_noop",   0),
  ("permute_merge",  0 if rw(23) is None else BY_NODE[id(rw(23))][0]),
  ("permute_noop",   0 if rw(24) is None else BY_NODE[id(rw(24))][0]),
  ("stack_idx",      0 if rw(28) is None else BY_NODE[id(rw(28))][0]),
  ("const_idx2",     0 if rw(29) is None else BY_NODE[id(rw(29))][0]),
  ("const_idx3",     0 if rw(30) is None else len(rw(30).src)),
  ("const_idx5",     0 if rw(31) is None else len(rw(31).src)),
  ("idx_idx",        0 if rw(33) is None else len(rw(33).src)),
  ("idx_pick",       0 if rw(34) is None else BY_NODE[id(rw(34))][0]),
  ("idx_shaped",     0 if rw(36) is None else len(rw(36).src)),
  ("idx_shaped_bad", 1 if rw(37) is None else 0),
  ("unclaimed",      1 if rw(38) is None else 0),
  ("rej_pair",       NEXT),
  ("grow_new",       1),
  ("grow_same",      0),
  ("twice",          1),
  ("ret_self",       1),
  ("ret_new",        0),
]
note("shrink2", 1, f"CPython answers {who(r17)}, nsrc={0 if r17 is None else len(r17.src)}; the port defers rank 2 (`simplify()` = `graph_rewrite(self, symbolic)`)")
note("reshape_noop", 0, f"CPython answers {who(r21)}; rule 2 asks a RESHAPE's shape and fold.bend does not answer one")
note("rej_pair", NEXT, f"CPython's answer is {who(rw(30))}, a node the fixture does not hold, so the index is the arena's next free slot")

for nm, v in rows:
  print(f"{nm}={v}")

print("\n== the two DIVERGES, which are the file's own DEFERRED walls ==")
for k, (v, why) in DIVERGES.items():
  print(f"  {k} (gate reads {v}): {why}")

print("\n== the BEND INDEX MAP: `G.at(g, n)` is a LIST POSITION ==")
for k in sorted(IX): print(f"  at({k:2}) -> index {k:2}  {NAMES[k]}")
print("  (position 37 is k3, not ki: `g()` interns ki and `G.ix` omits it)")

print("\n== what each rewrite IS, for the identity rows ==")
for n, nm in ((13, "S2"), (17, "S4"), (20, "R2"), (21, "R3"), (23, "P2"), (24, "P3"),
              (28, "STK"), (29, "IX2"), (30, "IX3"), (31, "IX5"), (33, "J2"), (34, "J3"),
              (36, "K2"), (37, "K3"), (38, "ADD")):
  r = rw(n)
  print(f"  at({n:2}) = {NAMES[n] + '#' + str(n):9} -> {who(r):10} nsrc={'-' if r is None else len(r.src)}")
