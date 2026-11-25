# `_broadcast_to` -- movement.py:141-162 -- AS ONE UOp-LEVEL DANCE.
#
# THE DANCE IS CPYTHON'S, MEASURED 2026-11-25:
#   `Tensor.ones(1,1,49).expand(1,10,49)` is `PERMUTE(EXPAND(x'), STACK(perm))` with
#   `EXPAND(x').shape == (10,1,49)` and `x'.shape == (1,49)`. The EXPAND takes the NEW
#   dims ONLY and a PERMUTE reorders; the fold reads an EXPAND as `marg ++ src.shape`
#   (`uop/fold.bend`'s `expand_ds`), so an EXPAND carrying the FULL target carries
#   `len(dst) + len(src)` dims -- rank 6 and rank 12, which CPython never mints.
#
# WHY THIS FILE EXISTS AT ALL, and it is the same reason `LAWS/PROOF.bend` is one book:
# `movement.bend`'s `mxw_bcast` IS this dance, at the tensor level, and `gradient.bend`
# needed it and cannot import it (`movement -> tensor -> gradient`, the cycle this
# repository keeps paying for). The dance lives HERE, at the UOp level, and BOTH callers
# delegate -- `mxw_bcast` passes the movement-aware `mxw_dims_of` read, `gbcast` passes
# the fold's, and neither keeps a second copy of the walk. A copy is the class this
# tree already measured: `checks/differ.py`'s `WANT` table, `LIVE_UNITS`, `REF`.
#
# EVERY `match` IS ON A PARAMETER (`.of`/`.pick`), because Bend refuses a computed
# scrutinee; every list parameter is `+`, because the walks read each list more than
# once and a `+` is the duplicable form (`cg_edge.axes` uses the same).
import Base
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../schedule/indexing.bend as IX

# `self.shape` -- the fold's CONCRETE dims. A caller with a MOVEMENT-aware read passes
# its own dims to `bcast.of`, which is why the dims are a parameter and not a call.
def bc_dims(+ar: O.Arena, +u: U32) -> List<&2, U32>:
  IX.rr_dims(ar, F.Folded.t(F.folded(ar)), u)

def bc_range.go(fuel: Nat, +i: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: acc
    case 1n+p: bc_range.go(p, U32.add(i, 1), List.append(&2, U32, acc, [i]))

# `tuple(range(n))`. `op.bend`'s `mo_range` is the tensor-side twin and is why this is
# five lines here rather than an import: `op.bend` imports `tensor.bend`.
def bc_range(n: Nat) -> List<&2, U32>: bc_range.go(n, 0, Nil{})

# `s == 1 and d != 1` -- movement.py:139's expand test, the one predicate the three
# walks (`mg`, `sq`, `perm`) share.
def bc_exp(s: U32, d: U32) -> Bool: Bool.and(U32.is_eq(s, 1), Bool.not(U32.is_eq(d, 1)))

# THE MARG'S TAIL: `tuple(new_shape[n_left+i] for i in expand_at)`.
def bc_mg.go(+ss: List<&2, U32>, +dd: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss dd:
    case s <> st d <> dt:
      bc_mg.go(st, dt, Bool.pick(List<&2, U32>, bc_exp(s, d),
        List.append(&2, U32, acc, [d]), acc))
    case _ _: acc

def bc_mg(+ss: List<&2, U32>, +dd: List<&2, U32>) -> List<&2, U32>: bc_mg.go(ss, dd, Nil{})

# THE SQUEEZED DIMS: `tuple(self.shape[i] for i in kept)`.
def bc_sq.go(+ss: List<&2, U32>, +dd: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss dd:
    case s <> st d <> dt:
      bc_sq.go(st, dt, Bool.pick(List<&2, U32>, bc_exp(s, d),
        acc, List.append(&2, U32, acc, [s])))
    case _ _: acc

def bc_sq(+ss: List<&2, U32>, +dd: List<&2, U32>) -> List<&2, U32>: bc_sq.go(ss, dd, Nil{})

# THE PERMUTE WALK'S STATE. `ex` and `kp` are COUNTERS WHOSE LENGTHS ARE THE SLOTS --
# seeded so CPython's `.index` calls fall out of them and neither constant appears.
type BcPm is Data:
  BcPm{acc: List<&2, U32>, ex: List<&2, U32>, kp: List<&2, U32>}

def BcPm.acc(m: BcPm) -> List<&2, U32>:
  match m:
    case BcPm{acc, ex, kp}: acc

# `perm = tuple(range(n_left)) + tuple(n_left + (expand_at.index(i) if i in expand_at
# else len(expand_at) + kept.index(i)) for i in range(len(self.shape)))`
# (movement.py:141-143).
def bc_perm.go(+ss: List<&2, U32>, +dd: List<&2, U32>, +r: BcPm) -> BcPm:
  match ss dd r:
    case s <> st d <> dt BcPm{a, e, k}:
      bc_perm.go(st, dt, Bool.pick(BcPm, bc_exp(s, d),
        BcPm{List.append(&2, U32, a, [U32.from_nat(List.length(&2, U32, e))]),
             List.append(&2, U32, e, [0]), k},
        BcPm{List.append(&2, U32, a, [U32.from_nat(List.length(&2, U32, k))]),
             e, List.append(&2, U32, k, [0])}))
    case _ _ _: r

def bc_perm(+ss: List<&2, U32>, +dd: List<&2, U32>, +r: BcPm) -> BcPm: bc_perm.go(ss, dd, r)

# THE THREE MINTS, EACH WITH THE IDENTITY TEST ITS WRAPPER HAS. An empty EXPAND marg
# builds NO node (`tn_mop`'s EMPTY-arg NOOP, ops.py:823), and an identity PERMUTE or
# RESHAPE builds nothing (`movement.py:185`), so `bcast` over an equal shape is `x`.
def bc_same(+ar: O.Arena, +x: U32, +ds: List<&2, U32>) -> Bool:
  O.eq_u32(bc_dims(ar, x), ds)

def bc_reshape.pick(same: Bool, +ar: O.Arena, +x: U32, +ds: List<&2, U32>) -> O.Found:
  match same:
    case True{}: O.Found{ar, x}
    case _:
      +sk = O.shape_arg_found(ar, ds)
      O.UOp.new(O.Found.ar(sk), O.OpsRESHAPE{}, [x, O.Found.i(sk)], O.ANone{}, O.TNone{})

def bc_reshape(+ar: O.Arena, +x: U32, +ds: List<&2, U32>) -> O.Found:
  bc_reshape.pick(bc_same(ar, x, ds), ar, x, ds)

def bc_expand.pick(empty: Bool, +ar: O.Arena, +x: U32, +ds: List<&2, U32>) -> O.Found:
  match empty:
    case True{}: O.Found{ar, x}
    case _:
      +sk = O.shape_arg_found(ar, ds)
      O.UOp.new(O.Found.ar(sk), O.OpsEXPAND{}, [x, O.Found.i(sk)], O.ANone{}, O.TNone{})

def bc_expand(+ar: O.Arena, +x: U32, +ds: List<&2, U32>) -> O.Found:
  bc_expand.pick(U32.is_zero(U32.from_nat(List.length(&2, U32, ds))), ar, x, ds)

def bc_permute.pick(same: Bool, +ar: O.Arena, +x: U32, +ys: List<&2, U32>) -> O.Found:
  match same:
    case True{}: O.Found{ar, x}
    case _:
      +sk = O.shape_arg_found(ar, ys)
      O.UOp.new(O.Found.ar(sk), O.OpsPERMUTE{}, [x, O.Found.i(sk)], O.ANone{}, O.TNone{})

def bc_permute(+ar: O.Arena, +x: U32, +ys: List<&2, U32>) -> O.Found:
  bc_permute.pick(O.eq_u32(ys, bc_range(List.length(&2, U32, ys))), ar, x, ys)

# THE WHOLE DANCE, WITH THE SOURCE'S DIMS GIVEN. `base` IS NOT NEGATIVE at any caller --
# an expand onto a narrower shape is CPython's `ValueError` (movement.py:131) -- and
# `Nat.sub` answers 0 rather than a negative, which is the same named divergence the
# gradient lane records elsewhere: the port cannot raise.
def bcast.of(+ar: O.Arena, +x: U32, +src: List<&2, U32>, +dst: List<&2, U32>) -> O.Found:
  +bs = bc_range(Nat.sub(List.length(&2, U32, dst), List.length(&2, U32, src)))
  +tail = List.drop(&2, U32, dst, List.length(&2, U32, bs))
  +mg = bc_mg(src, tail)
  +pm = bc_perm(src, tail,
                BcPm{Nil{}, bs,
                     bc_range(Nat.add(List.length(&2, U32, bs),
                                      U32.to_nat(U32.from_nat(List.length(&2, U32, mg)))))})
  +perm = List.append(&2, U32, bs, BcPm.acc(pm))
  +marg = List.append(&2, U32, List.take(&2, U32, dst, List.length(&2, U32, bs)), mg)
  +sqt = bc_reshape(ar, x, bc_sq(src, tail))
  +ex = bc_expand(O.Found.ar(sqt), O.Found.i(sqt), marg)
  bc_permute(O.Found.ar(ex), O.Found.i(ex), perm)

def bcast(+ar: O.Arena, +x: U32, +ds: List<&2, U32>) -> O.Found:
  bcast.of(ar, x, bc_dims(ar, x), ds)
