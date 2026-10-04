#!/usr/bin/env python3
# mm-walk-gate.py -- the CPython oracle for `_min_max`'s WALK, ops.py:1104. The table
# (`mm.lift`) has its own gate; this one is for the part that was missing, the sweep that
# PRODUCES the `List<&2, Bnd2>` the table is handed.
#
#     .venv/bin/python .agents/slop/mm-walk-gate.py | grep '^mmk_' > mm-walk-py.txt
#     ./bin/bend tinybendygrad/uop/fold.bend      | grep '^mmk_' > mm-walk-bend.txt
#     diff mm-walk-py.txt mm-walk-bend.txt
#
# EVERY ROW CARRIES THE GRAPH IT IS ABOUT, not only the answer. `op=` and `srcops=` are
# CPython's own, so a bend fixture built with a wrong op or a swapped pair of srcs fails
# the diff on the SIGNATURE instead of producing a plausible interval that agrees by
# luck. That is the difference between a gate on the walk and a gate on a constant.
#
# THE `mmkx_` ROWS ARE THE DIVERGENCE AND THEY ARE NOT GATED FOR EQUALITY. The sweep's
# dtype comes from the main fold's table, so a node the dtype/shape ladder DEFERS has no
# dtype here and therefore no interval, where CPython answers one. Same treatment
# `rg_absent` and `mv_expsym` get: the port prints `ABSENT`, and the oracle records its
# real answer in a DIVERGES block rather than smoothing the two into an agreeing row.
import sys
sys.path.insert(0, '/private/tmp/wt-p3-minmax')
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.uop.ops import AxisType
from tinygrad.dtype import dtypes, AddrSpace


def pa(size=None, vmm=None, dt=dtypes.int32):
  return ParamArg(0, dt, size, vmm, None, None, AddrSpace.GLOBAL, None, False,
                  None, None, False, None)


def sig(u):
  # `Ops.`-prefixed, because the fold prints `O.Ops.name` and a diff of two spellings of
  # one name is noise on every row rather than a signal on one.
  return (f"n={len(u.toposort())} op=Ops.{u.op.name} nsrc={len(u.src)} srcops="
          + "|".join(f"Ops.{s.op.name}" for s in u.src))


def bnd(v):
  """one CPython `_min_max` endpoint in the port's `bnd_show` spelling."""
  if isinstance(v, float) and v == float('-inf'): return "NInf"
  if isinstance(v, float) and v == float('inf'): return "PInf"
  if v is True or v is False: return "+0:1" if v else "+0:0"
  if isinstance(v, float): return "F" + (f"{v:g}" if v.is_integer() else repr(v))
  return ("-" if v < 0 else "+") + str(abs(v) >> 32) + ":" + str(abs(v) & 0xFFFFFFFF)


def pair(u):
  lo, hi = u._min_max
  return f"lo={bnd(lo)} hi={bnd(hi)}"


def c(v): return UOp(Ops.CONST, (), v)

# ---- the fixtures, one list, so both lanes name the same rows ---------------------
# THE ORDER ROWS. `SUB` is the only non-commutative binary arm the table has, and
# `SUB(3,4)` is `(-1,-1)` against `SUB(4,3)`'s `(1,1)`, so a sweep that hands the table
# a REVERSED src list is caught by the pair and not by either row alone.
b4 = UOp(Ops.BUFFER, (), pa(4))
b4i64 = UOp(Ops.BUFFER, (), pa(4, None, dtypes.int64))
F = [
  ("sub34", UOp(Ops.SUB, (c(3), c(4)))),
  ("sub43", UOp(Ops.SUB, (c(4), c(3)))),
  # the sweep is TRANSITIVE, not one level: `MUL` is at depth 1 and `SUB` at depth 2.
  ("nested", UOp(Ops.ADD, (UOp(Ops.MUL, (c(3), c(4))),
                           UOp(Ops.SUB, (c(10), c(3)))))),
  # RANGE/SPECIAL read `src[0].vmax - 1`, so they are the rows that say the interval
  # arrives FROM the sweep rather than being written into the table.
  ("range5", UOp(Ops.RANGE, (c(5),), (0,), AxisType.LOOP)),
  ("special4", UOp(Ops.SPECIAL, (c(4),), "N")),
  # STACK reads ALL its srcs, so heterogeneous values are the fixture; `min`/`max` over
  # one value per src cannot tell a walk that read src[0] from one that read them all.
  ("stack", UOp(Ops.STACK, (c(1), c(-2), c(5)))),
  # PAD IS IN `GroupOp.Movement` AND DOES NOT PASS THROUGH -- Python tests PAD before the
  # passthrough, and the fold's order is the same order. The row needs a src whose
  # interval is STRICTLY POSITIVE, because a passthrough of a full `int32` window is the
  # same pair either way. A CONST has the interval and no shape and the port's `pad_ds`
  # refuses an empty `ps`; a `ParamArg` with BOTH `size` and `vmin_vmax` is the one
  # fixture that has each. A passthrough would answer `(5,9)` and this answers `(0,9)`.
  ("pad5", UOp(Ops.PAD, (UOp(Ops.PARAM, (), pa(4, (5, 9))), c(0), c(11)))),
  # the Defines arm reads `arg.vmin_vmax`, not a src: a PARAM with no srcs.
  ("param", UOp(Ops.PARAM, (), pa(4, (-3, 7)))),
  # THE TWO WINDOW ROWS, and the reason `weak.bend` waits: `2**64-1` does not fit a
  # signed word, so these are the rows the sign-plus-unsigned-magnitude pair exists for.
  # `THREEFRY` is in `GroupOp.Binary` and has no arm in the block, so it falls through to
  # the default arm with `uint64`; the BUFFER has no `vmin_vmax` and reaches the same arm
  # with `int64`.
  ("threefry", UOp(Ops.THREEFRY, (c(0), c(0), c(0)))),
  ("buf_i64", b4i64),
  # a void dtype's default arm, which is the ONE place `bnd_lim`'s void arm is load-bearing
  # through a walk rather than through a hand-built `lf` row.
  ("noop", UOp(Ops.NOOP, (b4,))),
]

# ---- the divergence, and every entry of it is a node `dt_shape` DEFERS ------------
# THE SET IS SMALLER THAN IT LOOKS, and the measurement is what removed three names from
# it: the twelve `late()` marker ops are NOT in it. `dt_shape`'s `late()` hands them
# `void` with no shape, so their DTYPE is known and the default arm answers `(False, True)`
# -- which is why the BACKEDGE below is an agreeing row and not a refusal.
sp = UOp(Ops.SPECIAL, (c(4),), "N")
rg = UOp(Ops.RANGE, (c(5),), (0,), AxisType.LOOP)
back = UOp(Ops.BACKEDGE, (sp, rg, sp))

# THE PER-NODE ROW, and it is the one a whole-table flag cannot pass. The STAGE is
# unanswerable and this unrelated `ADD` shares its arena, so a sweep that gave up at the
# first gap answers `ABSENT` for both. CPython answers the ADD and the STAGE alike. It is
# built AFTER the STAGE so the two lanes index the arena the same way.
D = [("stage", UOp(Ops.STAGE, (c(0),)))]
F.append(("sibling", UOp(Ops.ADD, (c(2), c(5)))))

# THE BACKEDGE'S OWN SRCS ARE ANSWERED and it is the ORDERING row: `src[0]` is the node
# the marker was built from, so it is below the marker in index order and a forward sweep
# reads it. This is the one case where a sweep by arena index could read too little.
F.append(("backedge", back))
F.append(("backedge_sp", back.src[0]))
F.append(("backedge_rg", back.src[1]))

# a RESHAPE over a symbolic marg: the `ssimplify` wall, and `mv_expsym`'s own fixture.
# The interval is a passthrough of an `int32` BUFFER, so CPython's answer is the whole
# `int32` window.
D.append(("reshape", UOp(Ops.RESHAPE, (b4,), (sp,))))

out = []
for name, u in F:
  out.append(f"mmk_{name} {sig(u)} {pair(u)}")
out.append(f"mmk_vmin {sig(b4i64)} {bnd(b4i64._min_max[0])}")
out.append(f"mmk_vmax {sig(b4i64)} {bnd(b4i64._min_max[1])}")

sys.stdout.write("\n".join(out) + "\n")
sys.stdout.write("\n# DIVERGES -- the port prints ABSENT for every node below, because the\n"
                 "# sweep's dtype comes from the main fold's table and `dt_shape` defers\n"
                 "# each of these ops. CPython's real answers, for the record:\n")
for name, u in D:
  sys.stdout.write(f"# mmkx_{name} {sig(u)} {pair(u)}\n")
sys.stdout.write(f"# mmkx_sibling_stage shares one arena with mmk_sibling, which IS answered, so\n"
                 f"# the gap is per NODE and not a whole-sweep flag: {pair(D[0][1])}\n")
