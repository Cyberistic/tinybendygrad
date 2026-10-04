"""The CPython lane for the ops.py 501-1928 unit of `tinybendygrad/uop/ops.bend`.

    sh .agents/slop/ops-501-gate.sh

Every row is printed by CALLING CPython. Nothing here is transcribed: no op name,
no arena index, no arg order and no table entry in this file is written by hand.
The only list that IS written here is the FIXTURE list, and the fixtures are named
after the thing each one separates rather than after its shape -- the same names
`ops.bend`'s `s5.arena` uses, so a fixture cannot drift between the two lanes
without a row moving.

`TG_TREE` picks the tree, so the same script diffs the port against the pin and
against upstream:

    TG_TREE=.                                  the vendored pin
    TG_TREE=.agents/slop/opstree               upstream master
"""
import os
import sys

TG_TREE = os.environ.get('TG_TREE', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'opstree'))
sys.path.insert(0, TG_TREE)

from tinygrad.uop.ops import UOp, Ops, AxisType, ParamArg, KernelInfo, gate_kernel_sink  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402

rows = []


def row(k, v):
  rows.append(f"{k}={v}")


def bs(b: bool) -> str:
  """`Bool.show` -- the port's `row` prints a `Bool` as `True`/`False`."""
  return "True" if b else "False"


def nm(u: UOp) -> str:
  """`Ops.name(u.op)` -- the PORT prints the `Ops.` prefix because `str(FastEnum)`
  is `"Ops.MEMBER"`, and the row is `Ops.name` not the bare member name."""
  return f"Ops.{u.op.name}"


def sig(u: UOp) -> str:
  """Op name plus the SRC OP SEQUENCE, as one string.

  The port's `UOp.base` and its five siblings answer an arena INDEX, and an index
  is meaningless outside the arena that produced it, so what is comparable is what
  the index POINTS AT. That is the op name -- and the src sequence as well, because
  a walk that got the op right and the src order wrong answers one string either
  way, which is the same reason `Rng.sig` exists for this file's other graph rows.
  """
  return nm(u) if not u.src else nm(u) + "/" + " ".join(nm(s) for s in u.src)


# ---------------------------------------------------------------------------
# THE FIXTURES, in the arena order `ops.bend`'s `s5.arena` writes them.
# ---------------------------------------------------------------------------
c = UOp.const(3)                                                  # s5.c  a CONST: nothing peels
b = UOp(Ops.BUFFER, arg=ParamArg(1, dtypes.int32, 9))            # s5.b  the walk's terminal
p = UOp(Ops.PARAM, arg=ParamArg(2, dtypes.int32, 4))             # s5.p
al = UOp(Ops.ALLOC, arg=ParamArg(3, dtypes.int32, 4))             # s5.a
rng = UOp.range(2, 0, AxisType.DEVICE)                            # s5.us's second src
r1 = b.reshape((3, 3))                                           # s5.r1 one movement deep
r2 = r1.reshape((9,))                                            # s5.r2 two deep
us = UOp(Ops.UNSHARD, src=(b, rng), arg=(0,))                    # s5.us
bc = UOp(Ops.BITCAST, src=(b,), arg=dtypes.float32)              # s5.bc
af = UOp(Ops.AFTER, src=(b,))                                    # s5.af
dt = UOp(Ops.DETACH, src=(b,))                                  # s5.detach, the `base` peel's DETACH arm
ks = UOp(Ops.SINK, src=(b,), arg=KernelInfo())                   # s5.gate_kernel
lin = UOp(Ops.LINEAR, src=(b,), arg=())                          # s5.gate_linear

# s5_idx -- the fixture OP NAMES in arena order. A miscount in either lane's index
# arithmetic shows up here rather than as nine silently re-labelled rows.
row("s5_idx", ",".join(nm(u) for u in (c, b, p, al, r1, r2, us, bc, af)))

# ---------------------------------------------------------------------------
# THE BASE FAMILY. Six walks, six op sets, and the rows are the op name each walk
# LANDS ON. The sets are the whole difference between the defs and the fixtures
# are chosen so each set boundary has a node on it:
#   dt  a DETACH: `base` peels it and `without_after` does NOT, so the pair is the
#       difference between the two sets. It was MISSING at first -- the
#       `base_drops_detach` mutation moved no row, which is the hole a mutation
#       exists to find, and adding the node is what closed it.
#   us  `base` does not strip UNSHARD, `unsharded_base` does
#   bc  neither strips BITCAST, `storage_base` does
#   af  only `has_buffer_identity(after_ok=True)` strips it, and that is the only
#       pair in the whole family the `after_ok` parameter moves
#   r1  one deep, so a walk that tested once instead of repeating would answer
#       RESHAPE; `r2` is two deep and is the row that says it repeats
#   c   nothing peels, so the FUEL is the only thing that can move a row
# ---------------------------------------------------------------------------
for k, u in (('c', c), ('b', b), ('p', p), ('a', al), ('r1', r1), ('r2', r2), ('us', us), ('bc', bc), ('af', af), ('detach', dt)):
  row(f"s5_base_{k}", nm(u.base))

for k, u in (('c', c), ('b', b), ('p', p), ('a', al), ('r1', r1), ('r2', r2), ('us', us), ('bc', bc), ('af', af), ('detach', dt)):
  row(f"s5_unsharded_base_{k}", nm(u.unsharded_base))

for k, u in (('c', c), ('b', b), ('p', p), ('a', al), ('r1', r1), ('r2', r2), ('us', us), ('bc', bc), ('af', af), ('detach', dt)):
  row(f"s5_storage_base_{k}", nm(u.storage_base))

# `without_after` strips AFTER and nothing else, so `us` is UNSHARD here while
# `unsharded_base_us` is BUFFER -- one op, two answers, both rows.
for k, u in (('c', c), ('b', b), ('r1', r1), ('us', us), ('af', af), ('detach', dt)):
  row(f"s5_wo_after_{k}", nm(u.without_after))

# `buf_uop` walks PAST a non-buffer to reach the one under it, so `r1` is BUFFER
# and not RESHAPE. That is the row a peel-shaped reading would get wrong.
for k, u in (('c', c), ('b', b), ('p', p), ('r1', r1), ('r2', r2), ('bc', bc), ('af', af), ('detach', dt)):
  row(f"s5_buf_uop_{k}", nm(u.buf_uop))

# `has_buffer_identity` answers a Bool and BOTH values of `after_ok` are rows. The
# two differ on exactly one fixture, so a port that dropped the parameter would
# agree on the other eight and be wrong on the ninth.
# The nine `after_ok=False` rows, then the nine `after_ok=True` rows, and the
# gate is a BYTE diff -- so the ORDER is part of the contract and it is grouped
# rather than interleaved, which is also the only order a reader can check: the
# two blocks sit next to each other and the one row that differs is visible.
HBI = (('c', c), ('b', b), ('p', p), ('a', al), ('r1', r1), ('r2', r2), ('us', us), ('bc', bc), ('af', af), ('detach', dt))
# `Bool.show`, which is what the port's `row` prints -- `0`/`1` would be the gate
# for a different predicate and the two renderings are not interchangeable.
for k, u in HBI:
  row(f"s5_hbi_{k}", bs(u.has_buffer_identity(False)))
for k, u in HBI:
  row(f"s5_hbi_after_{k}", bs(u.has_buffer_identity(True)))

# ---------------------------------------------------------------------------
# `split_uop` -- the SEQUENCE and not a count, because a fold that appended at the
# back answers the same length and the REVERSED order. The middle fixture is the
# one that matters: `nest` is ADD[ADD[CONST,CONST],CONST], so front-push answers
# three CONSTs and back-push answers `CONST CONST ADD`, both length three.
# ---------------------------------------------------------------------------
def split(u: UOp, sep: Ops) -> str:
  """`UOp.split_uop` (ops.py:682) CALLED, not re-spelled.

  This was a Python worklist that reproduced the generator by hand, which made six
  `s5_split_*` expectations a TRANSCRIPTION of the thing under test -- the one failure
  agent-core.md names twice, and the one `device.bend` shipped at `sig=0 4 5` beside
  CPython's `0 4 8`. `split_uop` is an `Iterator`, so the row is `list(...)`.
  """
  return " ".join(nm(n) for n in u.split_uop(sep))


add2 = UOp(Ops.ADD, src=(c, c))
mulu = UOp(Ops.MUL, src=(c, add2))
nest = UOp(Ops.ADD, src=(add2, mulu))
left = UOp(Ops.ADD, src=(mulu, c))
row("s5_split_const", split(c, Ops.ADD))
row("s5_split_add", split(add2, Ops.ADD))
row("s5_split_nest", split(nest, Ops.ADD))
row("s5_split_diamond", split(mulu, Ops.MUL))
row("s5_split_mismatch", split(left, Ops.MUL))
row("s5_split_left", split(mulu, Ops.ADD))


# ---------------------------------------------------------------------------
# THE MOVERS. Each row is the minted node's op and its SRC OP SEQUENCE, so a mint
# with the op right and the src order wrong is visible.
# ---------------------------------------------------------------------------
row("s5_barrier", sig(b.barrier()))
row("s5_bufferize", sig(b.bufferize()))
row("s5_bufferize_arg", sig(b.bufferize(c)))
multi = UOp(Ops.ALLOC, arg=ParamArg(3, dtypes.int32, 4, device=("PYTHON", "PYTHON")))
row("s5_allreduce", f"{nm(multi.allreduce(Ops.ADD, ('PYTHON', 'PYTHON')))}/{nm(multi)}")
row("s5_mselect", f"{nm(UOp(Ops.MSELECT, src=(b,), arg=0))}/{nm(b)}")
row("s5_sharding_us", " ".join(f"{a}:{nm(r)}" for a, r in us.sharding))
row("s5_sharding_none", " ".join(f"{a}:{nm(r)}" for a, r in r1.sharding))
# `sint_to_uop(4, weakint)` IS `UOp.const(4, weakint)`, so the node is a CONST and
# the row is its op name. A row that printed the RANGE it feeds would be gating
# `UOp.range` instead of the def.
row("s5_sint_const", nm(UOp.const(4, dtypes.weakint)))

# ---------------------------------------------------------------------------
# THE MOVERS, ROUND TWO -- ops.py:761 `copy_to_device`, :844 `getaddr`, :849
# `device_range_src`. Every value below is printed by CALLING CPython; the only
# things written by hand are the FIXTURE list and the row names, and the fixture
# names are the ones `ops.bend`'s `s5.ga.arena` uses at the same positions.
# ---------------------------------------------------------------------------

# `H.i64_text` is `f"{hi}:{lo}"` and it is how the port prints a RANGE's END,
# because the port's RANGE `end` is `sint_to_uop(len(device))` -- a CONST whose
# value IS the count. Printing `Ops.name` alone would read `Ops.RANGE` for one tag
# and for two, so `len(device)` would be ungated.
def i64_text(v: int) -> str:
  return f"{(v >> 32) & 0xFFFFFFFF}:{v & 0xFFFFFFFF}"


# `-` for the empty list is `s5.dr`'s `Nil{}` arm. It is a character and not `""`
# so the row is visible in a diff: an empty right-hand side is a row a byte diff
# cannot see move.
def devrange(dev) -> str:
  rs = UOp.device_range_src(dev)
  if not rs:
    return "-"
  return " ".join(f"{nm(r)}:{i64_text(int(r.src[0].arg))}" for r in rs)


row("s5_devrange_single", devrange("PYTHON"))
row("s5_devrange_one", devrange(("PYTHON",)))
row("s5_devrange_two", devrange(("PYTHON", "PYTHON")))
row("s5_copy_single", sig(b.copy_to_device("PYTHON")))
row("s5_copy_multi", sig(b.copy_to_device(("PYTHON", "PYTHON"))))
# The `arg` is the MSELECT's shard index, and `assert arg is None or isinstance
# (self.device, tuple)` is why the subject here is `multi` and not `b`. The two
# `raise`s `copy_to_device` also has -- `is_disk_device` and the weak-dtype test --
# are NOT PORTED (they need `fold.device` and the dtype fold) and no row pretends
# otherwise: what is gated here is the node.
row("s5_copy_sel", sig(multi.copy_to_device(("PYTHON", "PYTHON"), 1)))

# THE `getaddr` FIXTURES: one per op in the nine-op set, then four that are not --
# a leaf, a movement op, the AFTER that `without_after` strips, and an ALU op.
# `src=(b,)` throughout because the port's fixtures are `src=[1]` and the row
# prints the ANSWER's src sequence. The answer is either the fixture itself or
# `GETADDR[fixture]`, so the only fixtures whose OWN srcs reach the row are the
# CONST (none), the RESHAPE (`(b, shape)`) and the ADD (`(b, b)`) -- and those
# three match the port's literal. Everything else is never descended into.
# `device="PYTHON"` is passed so every fixture takes the same path: the default
# reads `self.device`, and `MSELECT` asserts it is a tuple.
GA = (
  ('buffer', b),
  ('alloc', al),
  ('param', p),
  ('shrink', UOp(Ops.SHRINK, src=(b, c, c), arg=((0, 9), (0, 9)))),
  ('bitcast', bc),
  ('binary', UOp(Ops.BINARY, src=(b, c), arg=Ops.ADD)),
  ('mstack', UOp(Ops.MSTACK, src=(b, b))),
  ('mselect', UOp(Ops.MSELECT, src=(multi,), arg=0)),
  ('linear', lin),
  ('const', c),
  ('reshape', r1),
  ('after', af),
  ('add', UOp(Ops.ADD, src=(b, b))),
)
for k, u in GA:
  row(f"s5_ga_{k}", sig(u.getaddr("PYTHON")))

# `gate_kernel_sink` is one row per ARM: the two negative tests and the default.
# A port that collapsed the negatives would answer 1 on one of the first two and
# the third row would not see it.
#
# ops.py:1909 CALLED, not re-spelled. This block used to be a hand-written copy of those
# three lines, so all three rows asserted a TRANSCRIPTION of the thing under test --
# the failure agent-core.md names as the one that shipped `device.bend` at `sig=0 4 5`
# beside CPython's `0 4 8` and stayed green. The copy was byte-identical to upstream on
# this pin AND on `.agents/slop/opstree`, so calling the real one moves NO row, which is
# the point: a transcription that happens to be right is indistinguishable from one that
# is wrong until it is wrong.
row("s5_gate_linear", bs(gate_kernel_sink(lin)))
row("s5_gate_kernel", bs(gate_kernel_sink(ks)))
row("s5_gate_plain", bs(gate_kernel_sink(b)))

if __name__ == '__main__':
  for r in rows:
    print(r)
