# THE THREE GRAPHS, RECOVERED VERBATIM FROM COMMIT db95da7bf -- NOT REWRITTEN.
#
# `db95da7bf` (2026-10-04, "portexec: ...") added `"allred": g_allred, "cdiv": g_cdiv,
# "late": g_late` to `graphcmp.GRAPHS` and is **NOT an ancestor of HEAD**; a rebase line dropped
# them, which is why the figure fell from 61 to 53. This file is `git show
# db95da7bf:.agents/slop/graphcmp.py` lines 1479-1573, EXCEPT the three comments were
# trimmed to the ones that carry the claim. It is exec'd into `graphcmp`'s own namespace by
# `union.py`, so these bind the same `Tensor`/`dtypes`/`UOp`/`Ops` the 22 live graphs bind.
#

# `graphcmp.py:2789` binds a graph NAME to a generator; these are the same shape.
def g_allred():
  """`Tensor.empty(4,3,f32).uop.copy_to_device(('CPU','CPU')).allreduce(Ops.ADD, ('CPU','CPU'))`
  -- 9 nodes, and it reaches TWO of the 18 ops the corpus did not reach: `ALLREDUCE` and
  `COPY`. MEASURED census:
      ALLOC=1 CONST=3 STACK=1 RESHAPE=1 RANGE=1 COPY=1 ALLREDUCE=1

  WHY THIS ONE AND NOT A HAND-WRITTEN `UOp(Ops.ALLREDUCE, (r,), (Ops.ADD, ('CPU','CPU')))`.
  `UOp.allreduce` (ops.py:678) ASSERTS `isinstance(self.device, tuple)`, so the only way
  to get one is to have a genuinely multi-device UOp, and `UOp.copy_to_device`
  (ops.py:765) is what mints it -- and it appends the DEVICE RANGE itself
  (`UOp.device_range_src`, ops.py:766, which is `UOp.range(len(device), 0, AxisType.DEVICE)`
  at ops.py:846-847). So the `RANGE` in this graph is not a fixture choice, it is what
  `spec.py:31-34` `valid_device_range` REQUIRES of a multi-device COPY: exactly one src,
  a DEVICE-axis RANGE, and `int(rng.vmax)+1 == len(device)`. MEASURED, and the graph would
  fail spec without it.

  `('CPU','CPU')` IS NOT A FAKE MULTI-DEVICE SETUP IN THE SENSE THAT MATTERS: it is a TUPLE,
  which is all `valid_device_range` and `Ops.allreduce` test. `Device.default` is CPU here,
  so this graph is byte-identical on any host and needs no second device to exist.

  MEASURED, and this is why the graph is in the corpus at all: before it, `COPY` and
  `ALLREDUCE` were two of the eighteen ops `.agents/slop/DENOMINATOR.md` reports as
  expressible but unreached. Both are minted ONLY by multi-device or copy paths
  (`ops.py:765` is the only `UOp(Ops.COPY` site; `ops.py:679` the only `UOp(Ops.ALLREDUCE`
  site), and no eager graph in the corpus crosses a device boundary -- `g_cdiv` and `g_late`
  are `Tensor.empty` on one device, whose ALLOCs need no COPY."""
  from tinygrad import Tensor
  a = Tensor.empty(4, 3, dtype=dtypes.float)
  return a.uop.copy_to_device(("CPU", "CPU")).allreduce(Ops.ADD, ("CPU", "CPU"))


def g_cdiv():
  from tinygrad import Tensor
  a = Tensor.empty(4, 3, dtype=dtypes.int)
  b = Tensor.empty(4, 3, dtype=dtypes.int)
  return UOp.group(a.fmod(b).uop, a.div(b, rounding_mode="trunc").uop)


# `SUB` / `NEG` / `CMPEQ` / `FDIV` -- THE FOUR OPS THAT ARE **NOT** IN AN EAGER GRAPH AT ALL.
# `UOp.group(a-b, a.neg(), a.eq(b), a/b)` over TWO `Tensor.empty(4,3, float)`, run through
# upstream's OWN late rewrite -- MEASURED at 12 nodes after the rewrite, census
# `ALLOC=2 CMPEQ=1 CONST=2 FDIV=1 GROUP=1 NEG=1 RESHAPE=2 STACK=1 SUB=1`. FOUR NEW OPS.
#
# **THE FINDING THIS GRAPH RECORDS IS THAT FOUR OF THE SIX ARITHMETIC OPS ARE REWRITE-ONLY IN
# THIS TREE**, and each one's EAGER SPELLING IS EXACTLY THE LEFT-HAND SIDE OF THE REWRITE THAT
# MINTS IT. MEASURED, by CALLING CPython and reading the emitted rows (not by reading `Ops`):
#
#     op      eager construction                        eager census            upstream's rule
#     SUB     a - b        (elementwise.py:123)          ADD=1 MUL=1 CONST=3     op.py:106
#     NEG     a.neg()      (elementwise.py:74)           MUL=1 CONST=3            op.py:105
#     CMPEQ   a.eq(b)      (elementwise.py:337)          CMPNE=2 CONST=3         op.py:117
#     FDIV    a.reciprocal()(elementwise.py:468)          RECIPROCAL=1            op.py:124
#
# so `a - b` is `ADD(a, NEG(b))` spelled `ADD(a, MUL(b, CONST -1))`, `a.neg()` is
# `MUL(a, CONST -1)`, `a.eq(b)` is `CMPNE(a, b).logical_not()`, and `a / b` is
# `MUL(a, reciprocal(b))` -- which is why `g_commute`'s docstring could say CMPEQ is
# "NOT reachable from an eager graph at all" without having tried the REWRITE route, which is
# the route that reaches it. FOUR rules, and each one fires on its own eager spelling.
#
# **`supported_ops` IS THE DEVICE'S OWN TABLE AND NOT A LIST I CHOSE.** It is read exactly as
# `codegen/__init__.py:350` reads it -- `tuple(renderer.code_for_op.keys())` on
# `Device.default.renderer`, which follows `DEV`, which `--dev` sets -- and
# `disable_fast_idiv` is upstream's own `bool(DISABLE_FAST_IDIV)` (helpers.py:250, default 1).
# So WHICH four of the six this graph reaches is a property of the backend, and it is measured
# per backend rather than asserted: MEASURED, CPU's `ClangRenderer` wants all four
# (SUB NEG CMPEQ FDIV all in `code_for_op`) and `NullRenderer` wants only THREE of them --
# FDIV is absent -- so under `DEV=NULL` the same eager graph emits 13 nodes with
# `MUL(a, RECIPROCAL(b))` where the CPU run emits 12 with `FDIV(a, b)`. The first version of
# this comment said the census "says so", i.e. that `diff --dev NULL` would report it, and that
# is FALSE: the differ refuses that run outright. `diff --graph late --dev NULL` exits 2 with
# `# devices py=['sNULL'] bend=['sCPU'] -- NOT WELL-POSED`, because the port's fixture is
# pinned at arena tag 0 = `sCPU` (graphcmp.py:2869's precondition), so a `sNULL` py graph
# would cascade `src` differences with the cause in none of them. The backend dependence is
# therefore measured on the EMISSION, not on a verdict, and the four ops are reached on the one
# device the differ can compare.
#
# WHAT THE PORT IS AND IS NOT BEING ASKED HERE, because it is the easy thing to overstate:
# the PY side is upstream's rewrite applied to upstream's eager graph. The PORT side builds
# the REWRITTEN graph directly in its arena; it does NOT implement `get_late_rewrite_patterns`
# and this graph says nothing about whether it could. The same shape as `g_gate`, which takes
# `pm_linearize_cleanups`' output and never runs the matcher. The claim is that the port's op
# surface, dtype rules and arena reproduce upstream's rewritten graph -- NOT that the port
# can rewrite.
def g_late():
  from tinygrad import Tensor
  from tinygrad.device import Device
  from tinygrad.helpers import DISABLE_FAST_IDIV
  from tinygrad.uop.ops import graph_rewrite
  from tinygrad.codegen.decomp.op import get_late_rewrite_patterns
  a = Tensor.empty(4, 3, dtype=dtypes.float)
  b = Tensor.empty(4, 3, dtype=dtypes.float)
  eager = UOp.group((a - b).uop, a.neg().uop, a.eq(b).uop, (a / b).uop)
  pm = get_late_rewrite_patterns(tuple(Device.default.renderer.code_for_op.keys()),
                                 bool(DISABLE_FAST_IDIV))
  return graph_rewrite(eager, pm, name="arith/late")
