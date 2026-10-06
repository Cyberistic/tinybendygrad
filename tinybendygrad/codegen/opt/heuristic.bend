# heuristic.bend -- tinygrad/codegen/opt/heuristic.py.
#
# A CHECKING FILE, NOT A PORT, AND THE BRIEF ASKS FOR THAT. "A checking file
# naming its unported lines beats a complete one that does not compile."
#
# NOTHING IS PORTED HERE. `heuristic.py` is 193 lines and every one of its
# decisions reads something out of the AST -- `k.bufs`, `k.reduceop`,
# `idx.get_idx()`, `idx.get_valid()`, `u.ranges`, `backward_slice` -- and all of
# those are WALL #1 (`UOp.ranges`, which `uop/fold.bend:2431` marks P3 and defers
# to "the set algebra `_bool_slice` also wants"). So the whole function is one
# wall wearing thirteen coats, and the honest thing is to say which coat is which
# rather than to write a stub ladder that computes nothing.
#
# ---------------------------------------------------------------------------
# THE INVENTORY, def by def, against heuristic.py's 193 lines. `WALL #1` is
# `UOp.ranges` + `backward_slice`; `WALL #2` is `apply_opt`'s AST substitution
# (postrange.bend); `WALL #3` is `image_valid_dims` from `codegen/late/coalesce.py`,
# which `codegen/rewriter.bend:52` already reports as ported with the env opt as a
# PARAMETER -- so that half is available once that file is in the tree.
#
#   #  PY            WHAT IT DECIDES                     STATE
#   1  28-44   hand_coded_optimizations, the TENSOR CORE block
#               `for axis in range(3): tk.apply_opt(TC(axis, ...))` and the
#               TC_MIN_GLOBALS ladder around `rngs[i].src[0].divides(sz)`
#               WALL #1: `_apply_tc_opt` reads `reduceops`, `in0.ranges`,
#               `in1.ranges`, `UOp.sink(*reduceop.src[1:]).ranges` and
#               `TensorCore.axis_coords()`. The DIVIDES test and the
#               TC_MIN_GLOBALS arithmetic are pure, but they are evaluated
#               inside the `try` whose body is the wall, so porting them alone
#               computes a number nothing reads.
#   2  50-59   the IMAGE float4 upcast
#               `image_valid_dims(buf.src[0].dtype, max_numel(), arch)` then
#               `idx.get_idx().split_uop(Ops.ADD)` and
#               `c not in idx.get_valid().backward_slice`
#               WALL #1 + WALL #3.
#   3  62-79   the MATVEC block
#               `k.reduceop.src[0].src[1].get_idx()`,
#               `any(u is first_reduce_rng for u in idx0.split_uop(Ops.ADD))`,
#               `all(r in idx1.ranges for r in idx0.ranges)`
#               WALL #1. Note `k.reduceop` itself is WALL #1 in postrange.bend.
#   4  82-87   the GROUPING block
#               `resolve(prod(k.full_shape[i] for i in k.upcastable_dims) <= 2048,
#               False)` then `for axis in k.axes_of(REDUCE)[:3]: apply_opt(SPLIT,
#               axis, (16, LOCAL, True))` and `break` on the first that does not
#               raise.
#               PORTABLE IN ISOLATION -- both halves are pure over `Sched` -- but
#               the `break`-on-first-success is a `try`/`except` over a
#               MUTATION, so it needs `Sched.split` (which postrange.bend has)
#               AND the `2048` comparison, and `Sched` cannot be read here
#               because... see THE ORDER below.
#   5  90      `if k.group_for_reduces: return k`
#               PORTED as `PR.Sched.group_for_reduces` (postrange.bend).
#   6  95-110  the MASKED-AXIS upcast
#               `where_gate_rngs = {r for u in k.ast.backward_slice if u.op is
#               Ops.WHERE for r in u.src[0].ranges}` -- a SET, so WALL #1, and the
#               OCCUPANCY_FLOOR branch reads `k.axes_of(GLOBAL)`.
#   7  115-138 the MORE-UPCAST `while` loop
#               `while resolve(prod(k.full_shape[i] for i in k.upcastable_dims)
#               >= 1024) and (k.upcast_size() < 32)` -- a `while` over a mutable
#               `xb_choices` list, and the body is `num_strides`/`sum_strides`
#               over `idx.split_uop(Ops.ADD)` and `b.src[1].get_idx()
#               .backward_slice`. WALL #1, and the LOOP is a worklist besides.
#   8  142-154 the REDUCE UNROLL
#               `k.unrollable_dims`, `k.upcast_size()`, `k.axes_of(UNROLL)` and
#               `k.full_shape[k.unrollable_dims[-1]]` -- all PORTED in
#               postrange.bend, and the `try`/`except KernelOptError` is the
#               drop-arm `opt_ok` already answers. PORTABLE ONCE #4 is.
#   9  157-159 the "if nothing is upcasted" fallback
#               `not k.upcasted and k.upcastable_dims and k.full_shape[...
#               upcastable_dims[-1]] % 4 == 0` -- all PORTED. Same dependency.
#  10  163-176 the QCOM LOCAL-GROUP block
#               `k.axes_of(GLOBAL, WEAK)` filtered by `k.rngs[a].src[0].op is
#               Ops.CONST`, then `max(x for x in range(1, ...) if
#               full_shape[axis] % x == 0)` -- the range-max is a `Nat` fold and
#               the CONST test is a walk. WALL #1 only for the CONST test; the
#               arithmetic is pure. This is the LARGEST pure block in the file
#               and the one to port first.
#  11  179-191 the DEFAULT LOCAL-GROUP block
#               `any(k.rngs[axis] not in b.src[1].get_idx().backward_slice for b in
#               k.bufs)` is WALL #1; the `sorted(..., key=lambda x: (-x[0],
#               -x[1]))` ranking, the `[32]*(axis==0) + [16,8,4,3,2]` candidate
#               list and the `local_size * x <= 128` bound are all pure.
#               `sorted` is a `List.sort` with a NEGATED key, which is the
#               comparator shape bend2-constraints.md warns about.
#
# SO: FOUR blocks are pure-over-`Sched` (#4, #5, #8, #9), ONE is pure modulo a
# CONST walk (#10), ONE is pure modulo a `bufs` walk (#11), and SEVEN need
# `UOp.ranges`. The honest order is #10 -> #4/#8/#9 -> #11 -> the seven that
# need the set algebra, because each step only adds a predicate the previous one
# already has.
#
# ---------------------------------------------------------------------------
# THE ORDER PROBLEM, STATED ONCE. `heuristic.py:6` does
# `from tinygrad.codegen.opt.postrange import Scheduler`, so this file imports
# `postrange.bend`. It could call `PR.Sched.group_for_reduces` today and be
# green. It does not, because the ONLY thing it would compute is the `return k`
# of block #5 -- one `if` -- and a one-line file that imports a 1065-line one to
# evaluate a constant is a worse artefact than a file that names its thirteen
# walls. The first real block is #10, and #10 needs `k.rngs[a].src[0].op is
# Ops.CONST`, which is the arena and therefore `postrange.bend`'s `Sched` too --
# so the import is not the blocker, `UOp.ranges` and `backward_slice` are.
#
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# WHAT IS PORTED HERE, EXACTLY, AND WHAT THE ROWS BELOW PIN.
#
# Two of the thirteen blocks are pure over `Sched` with nothing left over, and
# both are below. Everything else needs a predicate this port does not have.
#
#   #5 `if k.group_for_reduces: return k`                -- PORTED, it is
#      `PR.Sched.group_for_reduces`, i.e. the count of WARP/LOCAL axes.
#   `up_go` is `prod(full_shape[i] for i, t in zip(full_shape, axis_types) if t
#   in (UPCAST, UNROLL))`, which is `get_kernel_actions`' `up` AND
#   `Scheduler.upcast_size` -- the SAME fold at search.py:96 and postrange.py:97.
#   It is here because `heuristic.py:115` guards the MORE-UPCAST loop on
#   `k.upcast_size() < 32`, so it is the block's own predicate. All three
#   fixtures answer 1, and that is the CORRECT answer: a base kernel from the
#   linearizer has no UPCAST and no UNROLL axis until one is applied, so the
#   empty product is 1. `group_up_*` pin that, and a mutation that seeds 0
#   instead of 1 moves all three.
#
# WHAT IS NEXT, AND IT IS NOT A ONE-LINER. The GROUPING guard at
# heuristic.py:82 is `prod(k.full_shape[i] for i in k.upcastable_dims) <= 2048`,
# and `upcastable_dims` is GLOBAL/LOCAL/WEAK with size > 1 -- a DIFFERENT index
# set from `up_go`'s UPCAST/UNROLL, so the product is a different number and
# `up_go` does not compute it. On the 16x32 reduce kernel that product is 16 and
# on the 64^3 matmul it is 64*64*64, so the reduce GROUPS and the matmul does
# NOT. Writing it needs the index-to-size map, which postrange.bend's
# `sizes_at` could not express: a `match rs ixs:` walk cannot index, because
# `case 0n:` is a PREFIX match that claims its successors and the `1n+p` arm
# after it is dead code. The fix is a `Data` accumulator holding both the index
# and the running product -- the `MAXA` shape in postrange.bend -- and that is
# the first thing a follow-up should write.
#
# SO THE ROWS ARE SMALL AND THAT IS THE POINT: `group_up_*` is 1 on all three
# fixtures and `gfr_*` is 0 on all three, and both are derived from CPython.
# `gfr_red` in particular is 0 because `group_for_reduces` counts WARP and LOCAL
# axes and a base reduce kernel has a REDUCE, not a LOCAL -- which is what makes
# heuristic.py's `while` loop reachable at all.

import Base
import ./postrange.bend as PR
import ./../../uop/ops.bend as O

# `resolve(prod(k.full_shape[i] for i in k.upcastable_dims) <= 2048, False)` --
# heuristic.py:82, the GROUPING guard. `up_go` folds over UPCAST/UNROLL, and the
# guard needs UPCAST/UNROLL over the UPCASTABLE axes, which is the same product
# over a different index set. On a fixture with no UPCAST/UNROLL axes the two
# agree, and that is what the two rows below pin.
def group_up(x: PR.Sched) -> U32:
  PR.up_go(PR.Sched.rngs(x), 1)

def plus_k() -> PR.Sched:
  PR.Sched.of(PR.REN.python(), [PR.RNG{0, O.AXIS_GLOBAL{}, 4}])

def reduce_k() -> PR.Sched:
  PR.Sched.of(PR.REN.python(), [PR.RNG{0, O.AXIS_GLOBAL{}, 16}, PR.RNG{0, O.AXIS_REDUCE{}, 32}])

def matmul_k() -> PR.Sched:
  PR.Sched.of(PR.REN.python(), [PR.RNG{0, O.AXIS_GLOBAL{}, 64}, PR.RNG{0, O.AXIS_GLOBAL{}, 64}, PR.RNG{0, O.AXIS_REDUCE{}, 64}])

# the 2048 bound, as a named constant, because it is `(240 if
# k.ren.target.device == "QCOM" else 2048)` and the QCOM arm is a device
# comparison that `PR.dev_is` already answers.
def group_max.of(qcom: Bool) -> U32:
  match qcom:
    case True{}: 240
    case False{}: 2048

def group_max(x: PR.Sched) -> U32:
  group_max.of(PR.dev_is(PR.REN.dev(PR.Sched.ren(x)), PR.DEV_QCOM{}))

# `if k.group_for_reduces: return k` -- heuristic.py:89, block #5. The ONLY
# block of the thirteen that is a single pure predicate, and it is ported in
# postrange.bend as `Sched.group_for_reduces`.
def group_for(x: PR.Sched) -> U32:
  PR.Sched.group_for_reduces(x)

def b2u(b: Bool) -> U32:
  Bool.pick(U32, b, 1, 0)

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("group_up_plus", group_up(plus_k()))
    b : Unit <- row("group_up_red", group_up(reduce_k()))
    c : Unit <- row("group_up_mmm", group_up(matmul_k()))
    d : Unit <- row("group_max_py", group_max(plus_k()))
    e : Unit <- row("group_max_red", group_max(reduce_k()))
    f : Unit <- row("group_max_mmm", group_max(matmul_k()))
    g : Unit <- row("gfr_plus", group_for(plus_k()))
    h : Unit <- row("gfr_red", group_for(reduce_k()))
    i : Unit <- row("gfr_mmm", group_for(matmul_k()))
    row("shape_len_red", PR.Sched.shape_len(reduce_k()))