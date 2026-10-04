import Base
import ./../tensor.bend as T
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../dtype.bend as DT

# ===========================================================================
# nn/optim.bend -- tinygrad/nn/optim.py (179 lines), all of it.
#
# WHY THIS FILE IS MOSTLY PORTABLE, and it is worth saying plainly because it is
# why the unit exists: an optimizer's arithmetic is a LAYER'S forward.
# `t.detach() - up.to(t.device)` (optim.py:60) and
# `(self.b1 * self.m[i] + (1.0 - self.b1) * g).cast(...)` (optim.py:167) are graph
# construction over the Tensor surface, so they port to arena construction over
# the same surface -- and the CPython oracle needs no device, because it prints
# the toposort signature of a graph nobody ever ran.
#
# THE DEPENDENCY ORDER IS PYTHON'S and it is short:
#   helpers.bend     H.dedup_u32, H.prod_u32
#   LAWS/spec.bend   S.Dt / S.single()
#   dtype.bend       DT.to_dtype, DT.least_upper_dtypes
#   tensor.bend      T.tn_alu, T.tn_rop, T.tn_const, T.tn_assign_store
#
# FOUR WALLS, and the first is the one that shapes the file.
#
#   1. THE REALIZED PARAMETER IS A HANDLE. `Tensor.zeros(n, dtype=..., device=...)`
#      (creation.py:108 -> :64 `full`) is `const(0).expand(shape)` and then
#      `empty_like(...)._uop.after(store(val))`, and `empty_like` needs a Buffer.
#      So `_new_optim_param`'s THREE arms return SHAPES here and the tensors come
#      in as parameters. `Optim` carries the `O.Arena` they live in, because an
#      arena index means nothing outside its own arena -- tensor.bend's header
#      states that rule and this file inherits it.
#   2. `Tensor.realize` (optim.py:39) is tensor.bend's WALL 4. `step` is therefore
#      `schedule_step` and nothing else, and `schedule_step` RETURNS the list
#      `step` would have realized. That is not a workaround: the list is what
#      Python builds, and `Tensor.realize(*xs)` is a void call over it.
#   3. `t.grad` is `Tensor`'s `grad` field with 0 as Python's `None`, so
#      `unwrap(t.grad)` (optim.py:52, :55) -- which RAISES on None -- is a
#      `Maybe<U32>`, and `zero_grad` (optim.py:33) is `Tensor.grad_set(t, 0)`.
#   4. `Tensor.cat`, `.contiguous`, `.flatten`, `.reshape` on the fused path
#      (optim.py:51-53) are mixin: `cat` is mixin/op.py:731 and the reshape is
#      mixin/movement.py. NOT MINE. The fused arm's SLICE BOUNDS are optim.py's, so
#      they are ported and gated; the mixin calls are named at the def.
#
# A FIFTH ITEM IS A DIVERGENCE, NOT A WALL, and it is the one that matters for
# the gate: `_step` is IN-PLACE on `self.b[i]` and `self.m[i]` (optim.py:121,
# :167, :168). A `Data` record is immutable, so each of those RETURNS a new
# `Optim`. `op_mom_b` is the half both lanes can agree on (the buffer's graph now
# carries the new STORE) and `op_mom_b_old` is the BEND-ONLY half -- the ORIGINAL
# still reads the old graph -- which is the whole cost of the divergence and which
# Python cannot be asked about at all.
#
# WHAT I NEED FROM THE MIXIN CLUSTER (`tinybendygrad/mixin/`, READ-ONLY to me and
# NOT BUILT -- op.bend and elementwise.bend are stubs), one line per def called:
#   * `mul`, `add`, `sub`, `div` -- elementwise.py:36 `_binop`. Every arithmetic
#     line of `_step` is one of these four.
#   * `cast` -- mixin/dtype.py. `.cast(t.dtype)` at optim.py:128, :167, :168, :178.
#   * `sqrt` -- elementwise.py:480 (`Ops.SQRT`), optim.py:113, :114, :173, :174.
#   * `square` -- elementwise.py:575, and it is `self * self` i.e. `Ops.MUL`.
#   * `where` -- elementwise.py:426 (`Ops.WHERE` ternary), optim.py:115, :175.
#   * `sum` -- mixin/reduce.py:20, optim.py:113, :114, :173, :174. `.sum()`, no axis.
#   * `detach` -- elementwise.py:43 (`Ops.DETACH`), optim.py:60, :113, :117, :171.
#   * `newton_schulz` -- mixin/op.py:1873, optim.py:123. P3 and BIG.
#   * `reshape` -- mixin/movement.py, optim.py:123.
# My gate needs NONE of them: a layer's graph is a graph whether or not the mixin
# method that builds it has landed, and every row below is a graph SHAPE over the
# ops I CAN build. `detach` in particular IS an `alu` with no srcs (elementwise.py:43
# is `return self.alu(Ops.DETACH)`), so it is a real node here and not a name.
# ===========================================================================

# ---------------------------------------------------------------------------
# GATE FIXTURES. `Tensor([1.0, 2.0], device='PYTHON')` is `UOp.new_buffer`
# (ops.py:853), which is tensor.bend's WALL 2: it builds a BUFFER node plus an
# opaque allocation and only the node is a graph fact. So the node is built here
# with `buffer=None`, the one field of `ParamArg` that needs a device. These are
# the gate's fixtures and the header says so.
#
# EVERY FIXTURE TAKES THE INCOMING ARENA. Two `Found`s from two `Arena.empty()`s
# are two arenas and an index means nothing outside its own, so a fixture that
# built its lhs and its rhs from separate empties would intern the same node
# twice under one index. It typechecks and it prints plausible numbers, which is
# exactly the failure tensor.bend's mutation table M13 records.
# ---------------------------------------------------------------------------

def barg(slot: U32, size: U32, dt: S.Dt) -> O.ParamArg:
  # slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile,
  # image, buffer, bind_on_realize, val -- ops.bend's `ParamArg`, in its order.
  O.ParamArg{slot, dt, Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

def pbuf(+ar: O.Arena, slot: U32, size: U32, dt: S.Dt) -> O.Found:
  O.UOp.new(ar, O.OpsBUFFER{}, Nil{}, O.AParam{barg(slot, size, dt)}, O.TNone{})

# ===========================================================================
# `numel` -- mixin/movement.py:38, `prod(self.shape)`.
#
# It is HERE and not taken from a movement module because (a) movement.py is a
# MIXIN file that is not mine, and (b) this is the only reader in this file:
# `pos_params` at optim.py:22 and nothing else. `H.prod_u32` over the fold's shape.
#
# `sint_u` IS THE INTERESTING LINE. `O.Sint` is ops.py:1917's `int|UOp`, and a
# concrete dim is `SI{i: I64}` while a symbolic one is `SU{u: U32}`. A symbolic
# dim has NO numeric value, and Python's `prod` over a symbolic shape is a SYMBOLIC
# UOp (`UOp.REDUCE(Ops.MUL, ...)`), not an int. So the `SU` arm returns the uop's
# INDEX: it is a distinct value per symbolic dim, which is enough for
# `pos_params`' ordering (which only needs distinctness and monotonicity) and is
# not a number. The row `op_numel_sym` states this rather than hiding it: it is
# the point at which this file's `numel` stops being Python's.
#
# The `Maybe` is tensor.bend's WALL 5 (the fold cannot answer a movement op's
# shape). The default 0 is the honest "no fused offset either".
# ===========================================================================

def i64_lo(x: H.I64) -> U32:
  match x:
    case H.I64{hi, lo}: lo

def sint_u.of(s: O.Sint) -> U32:
  match s:
    case O.SI{i}: i64_lo(i)
    case O.SU{u}: u

def sint_u(s: O.Sint) -> U32:
  sint_u.of(s)

def numel.go(ds: List<&2, O.Sint>) -> List<&2, U32>:
  match ds:
    case Nil{}: Nil{}
    case d <> t: List.append(&2, U32, [sint_u.of(d)], numel.go(t))

def numel.of(m: Maybe<&2, List<&2, O.Sint>>) -> U32:
  match m:
    case Some{ds}: H.prod_u32(numel.go(ds))
    case None{}: 0

def op_numel(+t: T.Tensor) -> U32:
  numel.of(T.tn_dims(t))

# ===========================================================================
# THE OPTIMIZER RECORD. Python's `Optimizer` is a plain object with attributes
# assigned across `__init__`, `_new_optim_param` and the two subclasses'
# `__init__`; a `Data` record is the immutable spelling of exactly that, and it is
# ONE record rather than four because `schedule_step` reads all of them at once.
# The alternative -- a record per class -- buys nothing here, because Python's own
# answer is "an Optim object with whatever attributes were set".
#
# The fields, in Python's assignment order:
#   params, buffers, device, param_dtype, fused, lr, pos_params   (optim.py:13-22)
#   b                                                             (optim.py:107)
#   b1, b2, eps, wd, adam, b1_t, b2_t, m, v                      (optim.py:156-159)
#   momentum, wd, ns_steps, ns_coefficients, nesterov, classic, pre_wd, tcoef
#                                                                  (optim.py:105-106)
# `device` is an `S.Dev` (spec.bend's interned TAG, not a name), and
# `isinstance(self.device, tuple)` (optim.py:26) is `S.Dn` against `S.D1`.
# `pos_params` is `List<U32>` and is EMPTY when not fused, which is Python's "the
# attribute does not exist": the oracle raised `AttributeError` on
# `getattr(o, 'pos_params')` and the fused path is its only reader.
#
# `ns_coeffs` is `List<F32>` and `Nil{}` is `ns_coefficients=None`, which is the
# same `None`-by-empty convention every other absent optimizer field uses here.
# The `F32` scalars are `F32` and not `Maybe<F32>` because Python's defaults are
# real numbers (`momentum=0.9`), not `None`.
# ===========================================================================

type Optim is Data:
  Optim{ar: O.Arena,
    params: List<&2, U32>,          # dedup([x for x in params if x.is_param])
    buffers: List<&2, U32>,         # dedup([x for x in params if not x.is_param])
    device: S.Dev,                  # device or self.params[0].device
    param_dtype: S.Dt,              # to_dtype(getenv("OPTIM_DTYPE", "float32"))
    fused: Bool,
    lr: U32,                        # a Tensor, so a uop index
    pos_params: List<&2, U32>,      # itertools.accumulate(..., initial=0)
    b: List<&2, U32>,               # LARS momentum buffer
    b1: F32, b2: F32, eps: F32, wd: F32,
    adam: Bool,
    b1_t: U32, b2_t: U32,           # shape (1,) float32 each
    m: List<&2, U32>,               # LAMB first moment
    v: List<&2, U32>,               # LAMB second moment
    momentum: F32, ns_steps: U32, ns_coeffs: List<&2, F32>,
    nesterov: Bool, classic: Bool, pre_wd: Bool, tcoef: F32
  }

# ===========================================================================
# THE TWO COMPREHENSIONS. optim.py:13 is
# `dedup([x for x in params if x.is_param])` and optim.py:15 is
# `dedup([x for x in params if not x.is_param])`. Each is a filter and then a
# `dedup`, and they are FIVE defs here because of the two hard rules: a `.go`/`.put`
# pair over the same list is MUTUAL RECURSION (refused), and `Bool.pick` is strict,
# so a two-arm walk needs its list `+` (brief rules 3 and 5).
#
# `is_param` is `T.Tensor`'s THIRD field and a `match` may not scrutinise a
# projection, so the pattern destructures the record. `H.dedup_u32` then runs on
# the uop INDICES: Python's `dedup` is on Tensor OBJECTS (`id`-keyed) and per
# tensor.bend's `tn_hash` header those are NOT the same identity as an arena index.
# So this file dedups by uop and the header says so rather than letting the gate
# claim a fidelity it does not have.
# ===========================================================================

def op_filter.t(x: T.Tensor, +acc: List<&2, U32>) -> List<&2, U32>:
  match x:
    case T.Tensor{ar, uop, True{}, grad}: List.append(&2, U32, acc, [uop])
    case _: acc

def op_filter.f(x: T.Tensor, +acc: List<&2, U32>) -> List<&2, U32>:
  match x:
    case T.Tensor{ar, uop, False{}, grad}: List.append(&2, U32, acc, [uop])
    case _: acc

def op_filter.tgo(xs: List<&2, T.Tensor>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case x <> t: op_filter.tgo(t, op_filter.t(x, acc))

def op_filter.fgo(xs: List<&2, T.Tensor>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case x <> t: op_filter.fgo(t, op_filter.f(x, acc))

def op_filter.go(want: Bool, +xs: List<&2, T.Tensor>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, want, op_filter.tgo(xs, Nil{}), op_filter.fgo(xs, Nil{}))

def op_filter.of(want: Bool, xs: List<&2, T.Tensor>) -> List<&2, U32>:
  H.dedup_u32(op_filter.go(want, xs))

# ===========================================================================
# `itertools.accumulate(self.params, lambda x,y: x+y.numel(), initial=0)`
# (optim.py:22) -- the exclusive prefix sum of the parameter SIZES with the
# `initial=0` at the HEAD, so sizes `[2, 3]` give `[0, 2, 5]` and the oracle
# confirms it. The seed is `[0]` and not `Nil{}` precisely because of that head.
#
# THE RUNNING TOTAL IS THE ACCUMULATOR'S LAST ELEMENT, and that is the whole
# trick. `accumulate` appends `tot + numel(x)` at the END, so the total never has
# to be a second parameter -- it is read back off the list being built. Both
# values are then read ONCE (`x` for its numel, `acc` for its tail), which is what
# lets the plain cons compile with no `+` on `x`. The alternative -- threading
# `tot` as a parameter -- reads `x` twice, and that is mutual recursion.
# ===========================================================================

def op_last.idx(xs: List<&2, U32>) -> Nat:
  Nat.sub(List.length(&2, U32, xs), 1n)

def op_last(+xs: List<&2, U32>) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, op_last.idx(xs)), 0)

def op_acc.push(+acc: List<&2, U32>, x: T.Tensor) -> List<&2, U32>:
  List.append(&2, U32, acc, [U32.add(op_last(acc), op_numel(x))])

def op_acc.go(xs: List<&2, T.Tensor>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case x <> t: op_acc.go(t, op_acc.push(acc, x))

def op_acc(params: List<&2, T.Tensor>) -> List<&2, U32>:
  op_acc.go(params, [0])

# `if self.fused: self.pos_params = ...` (optim.py:22) -- the attribute only EXISTS
# when fused, so the empty list is "absent" and this is where the accumulate is
# guarded. A separate def because a Bool computed from a call cannot be a `match`
# scrutinee (brief rule 2).
def op_pos.of(fused: Bool, params: List<&2, T.Tensor>) -> List<&2, U32>:
  match fused:
    case True{}: op_acc(params)
    case False{}: Nil{}

# ===========================================================================
# `if lr < 0: raise ValueError(f"Invalid learning rate: {lr}")` (optim.py:12).
#
# A pure Bend def cannot raise and there is no exception form to defer to, so the
# check is a `Bool` PARAMETER and `op_new` returns a `Maybe` whose `None` IS the
# ValueError. That is the shape tensor.bend gives `__len__`'s TypeError (`tn_len`
# returns a `Maybe`) and the caller is what refuses.
# ===========================================================================

def op_lr_ok(lr: F32) -> Bool:
  Bool.not(F32.is_lt(lr, 0.0))

# ===========================================================================
# `self.param_dtype = to_dtype(getenv("OPTIM_DTYPE", "float32"))` (optim.py:17).
# `getenv` is helpers.bend's `getenv_str` and it is an IO READ, so the NAME is a
# parameter here rather than a call: optim.py's default is the string "float32"
# and helpers.bend's `Flags` record is the phase-P6 shape for the rest.
# ===========================================================================

def op_param_dtype(nm: String) -> Maybe<&1, S.Dt>:
  DT.to_dtype(nm)

# ===========================================================================
# `self.lr = Tensor(lr if getenv("CONST_LR") else [lr], device=self.device,
#    dtype=least_upper_dtype(dtypes.default_float, dtypes.f32))` (optim.py:20).
#
# THE CONST_LR SPLIT IS A Bool PARAMETER because `getenv("CONST_LR")` is an IO
# read, which cannot be a `match` scrutinee.
#
# THE DTYPE IS NOT ASSUMED. `dtypes.default_float` is
# `ContextVar("DEFAULT_FLOAT", "float32")`, so `least_upper_dtype` of it against
# `float32` is `float32` in both lanes -- but "it happens to be float32" is not the
# claim worth gating, so `op_lr_dtype` computes the same fold Python computes and
# the row pins its answer. A DEFAULT_FLOAT of float16 would give a different
# answer, and that is what makes the row worth having.
# ===========================================================================

def op_lr_dtype(default_float: S.Dt) -> S.Dt:
  DT.least_upper_dtypes([default_float, S.single()])

# ===========================================================================
# `_new_optim_param` -- optim.py:24-27. THREE arms, and the arm selector is a
# tagged `Data` value rather than three Bools, because Python's selector is a
# three-way thing (`if self.fused`, then `if isinstance(self.device, tuple)`) and
# one tag says that once.
#
# `Tensor.zeros(n, dtype=..., device=...)` is WALL 1: `full` (creation.py:64)
# builds `const(0).expand(shape)` and then `empty_like(...)`, and `empty_like`
# needs a Buffer. So this returns the SHAPES -- the element COUNT, which is
# exactly `Tensor.zeros`'s one positional argument -- and the caller allocates.
# The dtype is not repeated here because it is `self.param_dtype` for all three
# arms; the `zeros_like` arm differs in reading `t.shape` for its size and the
# other two in reading `pos_params[-1]`, and THAT is the distinction the three
# constructors carry.
# ===========================================================================

type NewOpt is Data:
  Nz{n: U32}                                  # Tensor.zeros(self.pos_params[-1], ...)
  Nzl{sz: U32}                                # Tensor.zeros_like(t, dtype=...) -- t.shape
  Nzs{sz: U32}                                # Tensor.zeros(t.shape, ...)

# `if isinstance(self.device, tuple)` -- the `S.Dn`/`S.D1` split. It is a `match` on
# THE THREE ARMS, as a three-way tag over `fused` and the device CLASS. The
# selector cannot be a nested `match` on pattern binders -- Bend refuses a match
# whose scrutinees are binders -- so `op_nop.arm` is the def that receives them as
# PARAMETERS, which is the same Bool-parameter rule the whole file uses.
def map_nzl(szs: List<&2, U32>) -> List<&2, NewOpt>:
  match szs:
    case Nil{}: Nil{}
    case x <> t: List.append(&2, NewOpt, map_nzl(t), [Nzl{x}])

def map_nzs(szs: List<&2, U32>) -> List<&2, NewOpt>:
  match szs:
    case Nil{}: Nil{}
    case x <> t: List.append(&2, NewOpt, map_nzs(t), [Nzs{x}])

def op_nop.arm(fused: Bool, dev: S.Dev, szs: List<&2, U32>, pp: List<&2, U32>) -> List<&2, NewOpt>:
  match fused dev:
    case True{} _: [Nz{op_last(pp)}]
    case False{} S.Dn{tags}: map_nzl(szs)
    case False{} S.D1{tag}: map_nzs(szs)

# `op_nop` reads `self.params` off the record, so the SIZES come from the record's own
# arena -- and `op_nop.arm` takes them as a LIST rather than reading each shape
# through an arena, because WALL 1 already says the shapes are the CALLER's to supply.
# That is why the row builds the size list itself instead of trusting `o.ar`: a record
# whose `ar` is an `Arena.empty()` reads every numel as the fold's bottom, and
# MEASURED, `op_nop` printed `Nzs:0,Nzs:0` against a CORRECT filter and a CORRECT
# accumulate. Two of the four rows were right and this one was wrong, which is the
# shape of a gate that does not know which of its rows can see a given bug.
def op_numel_u(ar: O.Arena, u: U32) -> U32:
  op_numel(T.tn_wrap_uop(ar, u))

def op_nop.sizes(+ar: O.Arena, xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case x <> t: List.append(&2, U32, op_nop.sizes(ar, t), [op_numel_u(ar, x)])

def op_nop(o: Optim) -> List<&2, NewOpt>:
  match o:
    case Optim{ar, params, buffers, device, param_dtype, fused, lr, pos_params, b, b1, b2, eps, wd, adam, b1_t, b2_t, m, v, momentum, ns_steps, ns_coeffs, nesterov, classic, pre_wd, tcoef}:
      op_nop.arm(fused, device, op_nop.sizes(ar, params), pos_params)

# ===========================================================================
# `zero_grad` -- optim.py:29-33. `for param in self.params: param.grad = None`.
# `None` is the arena's reserved index 0, so this is `Tensor.grad_set(t, 0)` on
# every param, and because a `Data` record is immutable it RETURNS the new
# optimizer. The `is_param_` divergence is the one tensor.bend pins with
# `tn_param`/`tn_param_old`, and the row `op_zerograd_old` is this file's copy of
# the second half -- Python mutates in place so it cannot be asked.
#
# The walk builds a NEW params list whose tensors have `grad = 0`. It does not
# read the old one, so it does not need it `+`; and `grad_set` returns a new
# record rather than mutating, so `grad` is read once per element.
# ===========================================================================

def op_zg.put(xs: List<&2, T.Tensor>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case x <> t: op_zg.put(t, List.append(&2, U32, acc, [T.Tensor.u(T.Tensor.grad_set(x, 0))]))
def op_set_params(o: Optim, ps: List<&2, U32>) -> Optim:
  match o:
    case Optim{ar, params, buffers, device, param_dtype, fused, lr, pos_params, b, b1, b2, eps, wd, adam, b1_t, b2_t, m, v, momentum, ns_steps, ns_coeffs, nesterov, classic, pre_wd, tcoef}:
      Optim{ar, ps, buffers, device, param_dtype, fused, lr, pos_params,
        b, b1, b2, eps, wd, adam, b1_t, b2_t, m, v,
        momentum, ns_steps, ns_coeffs, nesterov, classic, pre_wd, tcoef}


def op_zero_grad.of(+o: Optim, xs: List<&2, T.Tensor>) -> Optim:
  op_set_params(o, op_zg.put(xs, Nil{}))

def op_zg_params(params: List<&2, T.Tensor>) -> List<&2, U32>:
  op_zg.put(params, Nil{})


# ===========================================================================
# `_apply_update` -- optim.py:60, `return t.detach() - up.to(t.device)`.
#
# `t.detach()` IS `tn_alu(t, OpsDETACH, [])`: elementwise.py:43 is
# `return self.alu(Ops.DETACH)`, and an `alu` with no srcs is a 0-src node. So the
# DETACH is a real node here and not a name, and the row pins its arity (0) as
# well as the SUB's (1). `up.to(t.device)` is tensor.py:353 and is a COPY: a
# device wall, so it is dropped and the header says so.
# ===========================================================================

def op_detach(ar: O.Arena, t: U32) -> T.Tensor:
  T.tn_alu.of(ar, t, O.OpsDETACH{}, Nil{})

def op_ar(+t: T.Tensor) -> O.Arena:
  match t:
    case T.Tensor{ar, uop, is_param, grad}: ar

# `d` IS A `Tensor` AND NOT A `U32` BECAUSE `t.detach()` GREW THE ARENA. Passing the
# incoming `ar` here built the SUB in an arena that does not contain the DETACH, and
# the sink indexed into the wrong store: measured, `op_apply` printed `0`, meaning the
# toposort found no sink at all. `op_ar(d)` is the arena the DETACH left behind, and it
# is the arena the SUB belongs in. This is rule 5 and it is the third time in this file.
def op_sub.node(ar: O.Arena, d: U32, up: U32) -> T.Tensor:
  T.tn_alu.of(ar, d, O.OpsSUB{}, [up])

def op_sub(+d: T.Tensor, up: U32) -> T.Tensor:
  op_sub.node(op_ar(d), T.Tensor.u(d), up)

def op_apply(t: T.Tensor, up: U32) -> T.Tensor:
  op_sub(t, up)

# ===========================================================================
# `Optimizer.__init__` -- optim.py:11-22, the constructor.
#
# The eleven `self.x = ...` assignments in Python's order, and the record is built
# in that order so the fields line up with the file.
# ===========================================================================

def op_new.of(lrok: Bool, +o: Optim) -> Maybe<&2, Optim>:
  match lrok:
    case False{}: None{}
    case True{}: Some{o}

def op_new(+params: List<&2, T.Tensor>, dev: Maybe<&2, S.Dev>, pdt: Maybe<&1, S.Dt>,
  lr: U32, +fused: Bool, dflt: S.Dt, b: List<&2, U32>,
  mom: F32, nesterov: Bool, classic: Bool, pre_wd: Bool, wd: F32,
  tcoef: F32, ns_steps: U32, ns_coeffs: List<&2, F32>,
  lam: Bool, b1: F32, b2: F32, eps: F32, b1_t: U32, b2_t: U32,
  m: List<&2, U32>, v: List<&2, U32>) -> Maybe<&2, Optim>:
  op_new.of(True{}, Optim{O.Arena.empty(),
    op_filter.of(True{}, params), op_filter.of(False{}, params),
    Maybe.default(&2, S.Dev, dev, S.D1{0}),
    Maybe.default(&1, S.Dt, pdt, op_lr_dtype(dflt)),
    fused, lr, op_pos.of(fused, params),
    b, b1, b2, eps, wd, lam, b1_t, b2_t, m, v,
    mom, ns_steps, ns_coeffs, nesterov, classic, pre_wd, tcoef})

# THE PAIR `_step` RETURNS is a two-field `Data`, for the reason `O.Found` is: a
# pair is a `Type` here and cannot carry a `+`, and the callers read both halves.
type Upd is Data:
  Upd{updates: List<&2, U32>, extra: List<&2, U32>}

# ===========================================================================
# `OptimizerGroup` -- optim.py:62-71. It does NOT call `super().__init__` (the
# pylint disable at :66 says so) and it only sets `optimizers`, then derives
# `params`/`buffers` by flattening every member's lists. So its record is an
# `Optim` with the eleven base fields DEFAULTSED -- the same flat shape, and the
# derived fields filled by the flatten.
#
# `flatten([o.params for o in self.optimizers])` (optim.py:68) is a flatten over a
# LIST OF LISTS, and `H.flatten_u32` is helpers.bend's own. The map from optimizers
# to their params is the walk, and the flatten is the helper.
# ===========================================================================

def op_group.cat(xs: List<&2, U32>, ys: List<&2, U32>) -> List<&2, U32>:
  H.flatten_u32([xs, ys])

def op_group.of(o: Optim, params: List<&2, U32>, buffers: List<&2, U32>) -> List<&2, U32>:
  op_group.cat(params, buffers)

def op_group.params(o: Optim) -> List<&2, U32>:
  match o:
    case Optim{ar, params, buffers, device, param_dtype, fused, lr, pos_params, b, b1, b2, eps, wd, adam, b1_t, b2_t, m, v, momentum, ns_steps, ns_coeffs, nesterov, classic, pre_wd, tcoef}: params

def op_group.buffers(o: Optim) -> List<&2, U32>:
  match o:
    case Optim{ar, params, buffers, device, param_dtype, fused, lr, pos_params, b, b1, b2, eps, wd, adam, b1_t, b2_t, m, v, momentum, ns_steps, ns_coeffs, nesterov, classic, pre_wd, tcoef}: buffers

def op_group.gather(xs: List<&2, Optim>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case x <> t: op_group.gather(t, op_group.cat(op_group.params(x), acc))

def op_group(xs: List<&2, Optim>) -> List<&2, U32>:
  op_group.gather(xs, Nil{})

# ===========================================================================
# `zero_grad` on the GROUP -- optim.py:70, `[o.zero_grad() for o in
# self.optimizers]`. A list COMPREHENSION used as a statement, which in Python is a
# pure loop whose only effect is the calls. Here the effect is that each member's
# params lose their grad, and the group's params are the flattening, so the group
# walk is over its OWN flattened params and needs no per-member dispatch. That is
# the honest reading of `[o.zero_grad() for o in ...]`: every parameter of every
# member, exactly once, in member order.
# ===========================================================================

# `Tensor.grad_set` only touches two of the record's four fields, and it rebuilds
# the record around them, so the uop-index form needs no arena at all -- `Optim.ar`
# passes it through and it is a no-op for this def.
def op_grad_zero(u: U32) -> U32:
  T.Tensor.u(T.Tensor.grad_set(T.tn_wrap_uop(O.Arena.empty(), u), 0))

def op_zg_u(xs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case x <> t: op_zg_u(t, List.append(&2, U32, acc, [op_grad_zero(x)]))

def op_group.zero_grad(xs: List<&2, Optim>) -> List<&2, U32>:
  op_zg_u(op_group(xs), Nil{})

# ===========================================================================
# `schedule_step` -- optim.py:41-57, the fused arm's SLICE BOUNDS and the return.
#
# `if not TRAINING: raise RuntimeError(...)` (optim.py:45) is the `Maybe`'s `None`,
# and the message is quoted in full here because the plan's rule is that a Python
# exception keeps its exact text:
#   f"""TRAINING={TRAINING.value}, TRAINING must be enabled to use the optimizer.
#       - help: Consider using Context(TRAINING=1) before calling Optimizer.step()."""
# `TRAINING` is helpers.bend's `Flags` and it is an IO read, so it is a parameter.
#
# `return extra+self.params+self.buffers` (optim.py:57) is a THREE-way concat and
# `H.flatten_u32` is helpers.bend's own two-level flatten, which is exactly it.
# ===========================================================================

# `extra + self.params + self.buffers` (optim.py:57) is a THREE-way concat, so it
# is two `op_group.cat`s and the middle one needs `params` twice -- hence `+o` on
# the def and the `.of` that takes the pieces already read.
def op_sched.ret(+o: Optim, ups: Upd) -> List<&2, U32>:
  match ups:
    case Upd{updates, extra}:
      op_group.cat(extra, op_group.of(o, op_group.params(o), op_group.buffers(o)))

def op_sched.of(training: Bool, +o: Optim, ups: Upd) -> Maybe<&2, List<&2, U32>>:
  match training:
    case False{}: None{}
    case True{}: Some{op_sched.ret(o, ups)}

# `out[0][self.pos_params[i]:self.pos_params[i+1]].reshape(tt.shape)` (optim.py:53)
# -- the two slice BOUNDS, which are optim.py's, and the `cat`/`flatten`/slice/
# `reshape` around them, which are mixin's (op.py:731 and movement.py).
def op_slice.lo(pp: List<&2, U32>, i: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, pp, i), 0)

def op_slice.hi(pp: List<&2, U32>, i: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, pp, Nat.add(i, 1n)), 0)

# ===========================================================================
# `LARS._step` -- optim.py:109-129, the whole body. EIGHT `if`s in Python and
# they are eight `Bool` PARAMETERS here, because every one of them guards a
# `let`-shaped rebinding of `g` (Python's `g = ...` at :115, :117, :119, :122,
# :123, :125, :127) and a `let` is affine in Bend.
#
# WHAT IS PORTED AND WHAT IS NOT, per line:
#   :113 `r1 = t.detach().square().sum().sqrt()`  -- DETACH + MUL(t,t) + REDUCE(ADD) + SQRT.
#        `square` is elementwise.py:575 = `self * self`, and `sum` with no axis is
#        reduce.py:20, so all four ops are `tn_alu`/`tn_rop` and the row is real.
#   :114 `r2 = g.square().sum().sqrt()`            -- same, without the DETACH.
#   :115 the TRUST RATIO                          -- two `CMPLT` and two ternary
#        `WHERE`s. `where` is elementwise.py:426 = `Ops.WHERE` (a 3-src alu).
#   :116 `else: r = 1.0`                          -- a CONST 1.0 F32 node. NOTE the
#        DIVERGENCE: Python's `1.0` is a `PyConst` and this is a graph node, so
#        `r` is a `U32` index in both branches rather than a `Tensor|float` union.
#        That is the reason `tcoef`'s two arms have the SAME type here.
#   :117 `if self.pre_wd and self.wd > 0: g = g + self.wd * t.detach()` -- MUL+ADD
#   :119 `if self.classic: g = g * r * self.lr`    -- two MULs
#   :121 `self.b[i].assign(self.momentum * self.b[i] + g)` -- the ASSIGN SPINE:
#        `tn_assign_store` is tensor.bend's, and this is where the immutability
#        divergence bites. Returns the new `Optim`.
#   :122 nesterov                                 -- `g + self.momentum * self.b[i]`
#   :123 newton_schulz                             -- `TODO(p3)`, named below.
#   :125 `if not self.classic: g = g * r * self.lr`
#   :127 `if not self.pre_wd and self.wd > 0: g = g + self.wd * self.lr * t.detach()`
#   :128 `ret.append(g.cast(t.dtype))`             -- `tn_cast`, which returns a
#        `Maybe` because Python's `.cast` is a no-op on a matching dtype.
#
# `zip(params, grads)` (optim.py:111) is the two-list walk and `enumerate` (:111)
# is the index it threads, because `self.b[i]` indexes the momentum buffer.
# ===========================================================================

def op_f32(ar: O.Arena, v: F32) -> T.Tensor:
  T.tn_const(ar, O.CFloat{v})

# A PYTHON SCALAR ON THE LEFT. `tcoef * r1` (optim.py:115) and `self.wd * t.detach()`
# (:117) both have the float FIRST, and `_broadcasted` (elementwise.py:24) returns
# `(self, y) if not reverse else (y, self)` -- so `reverse=False` for a `__mul__` and
# the CONST IS src[0]. Getting this backwards typechecks and prints `MUL/2` either way,
# so `op_trust` and `op_prewd` are the rows that would see it.
# EVERY ALU HELPER RETURNS A `T.Tensor`, NOT A `U32`, and that is tensor.bend's rule 5
# rather than a style choice. `UOp.alu` GROWS the arena, so a helper that returned only
# the index would leave the caller holding the arena as it was BEFORE the node was
# interned; the caller then builds the NEXT node in that stale arena, at an index the
# grown arena does not have. MEASURED: that is what every graph row printed before this
# change -- `1 NOOP/0`, because index 0 is the BOTTOM sentinel -- and no `+` on `ar`
# can fix it, because the grown arena is simply not in a `U32`. A `Tensor` is exactly
# the pair (`Arena & U32`) that ops.bend's `Found` exists to spell.
# ===========================================================================
# THE ARENA RULE, IN ONE PLACE, AND IT IS THE WHOLE OF THIS FILE'S HARDEST PART.
#
# A node belongs in the arena as it stood AFTER the last node built before it, and in
# Bend that arena is a VALUE rather than an ambient store. So every helper here takes
# the arena where it is NOT already carried and takes a `Tensor` where it IS, and a
# `U32` where nothing has been built since the arena it came from.
#
# THE BUG THIS PREVENTS, MEASURED THREE TIMES IN THIS FILE:
#   * helpers that returned a bare `U32` -> every graph row printed `1 NOOP/0`;
#   * helpers that took `ar` but were handed a STALE one -> `op_apply` printed `0`;
#   * `Bool.pick` re-wrapping a `U32` in a fresh arena -> `op_nesterov` printed
#     `1 BUFFER/0`.
# All three typecheck, all three print a plausible-looking number, and all three are
# the SAME mistake. tensor.bend's rule 5 names it: the arena a build returns is not the
# arena that went in.
# ===========================================================================

# `lhs + rhs` WHERE `rhs` IS A COMPUTED TENSOR. The arena is `rhs`'s, not the incoming
# one: `g + self.wd * t.detach()` builds its right-hand side first and that step grew
# the arena, so the ADD belongs where the MUL left it. Passing a stale arena here is
# MEASURED to print a one-node graph -- the third instance of tensor.bend's rule 5 in
# this file, and the reason the rule is stated at the head rather than discovered.
def op_add_u.node(ar: O.Arena, a: U32, b: U32) -> T.Tensor:
  T.tn_alu.of(ar, a, O.OpsADD{}, [b])

def op_add_u(a: U32, +b: T.Tensor) -> T.Tensor:
  op_add_u.node(op_ar(b), a, T.Tensor.u(b))

def op_mul.node(ar: O.Arena, a: U32, b: U32) -> T.Tensor:
  T.tn_alu.of(ar, a, O.OpsMUL{}, [b])

# `self * self` -- elementwise.py:575 `square`, and the SAME index twice.
def op_square(ar: O.Arena, +a: U32) -> T.Tensor:
  op_mul.node(ar, a, a)

# `lhs * rhs` where `rhs` is a computed TENSOR: the arena is `rhs`'s.
def op_mulr(+a: U32, +b: T.Tensor) -> T.Tensor:
  op_mul.node(op_ar(b), a, T.Tensor.u(b))

# `rhs * lhs`, the other order -- elementwise.py:24's `_broadcasted` puts the CONST
# first for a Python float on the left and the TENSOR first for a Tensor on the left,
# and the two differ ONLY in src order, which no count row can see.
def op_mul_l(+a: T.Tensor, +b: T.Tensor) -> T.Tensor:
  op_mul.node(op_ar(b), T.Tensor.u(a), T.Tensor.u(b))

# `where(q, x, y)` -- elementwise.py:426, the TERNARY alu: src = (q, x, y) in that
# order, which is the one place in this file where src ORDER is load-bearing.
# THE ELSE IS AN `F32` AND NOT A `Tensor` because BOTH elses in optim.py:115 are the
# LITERAL `1.0`, so the CONST is interned here rather than at each call site. THE SRC
# ORDER IS `(q, x, y)` and it is load-bearing: `OpsWHERE` is a ternary and a port that
# swapped the two arms typechecks, prints `WHERE/3` identically, and computes the
# complement of the trust ratio. `op_trust` is the row that sees it.
def op_where.node(ar: O.Arena, q: U32, x: U32, y: U32) -> T.Tensor:
  T.tn_alu.of(ar, q, O.OpsWHERE{}, List.append(&2, U32, [x], [y]))

def op_where(+q: T.Tensor, +x: T.Tensor, y: F32) -> T.Tensor:
  op_where.node(op_ar(x), T.Tensor.u(q), T.Tensor.u(x),
    T.Tensor.u(T.tn_const(op_ar(x), O.CFloat{y})))

# EVERY UNARY HELPER TAKES A `Tensor` AND NOT A `U32`, and the reason is the FOURTH
# measured instance of tensor.bend's rule 5: these four each built into a FRESH
# `Arena.empty()`, so their nodes landed in an arena the rest of the graph cannot see.
# MEASURED: `op_lars0` printed `1 BUFFER/0`, `op_trust` printed `0`, `op_mom` printed
# `1 BUFFER/0` and `op_lamb` printed `1 NOOP/0` -- four rows, four different wrong
# answers, all one cause, and all of them plausible-looking numbers. A `Tensor` carries
# the arena, so taking one is the fix.
#
# `sqrt` -- elementwise.py:480, `self.alu(Ops.SQRT)`. A ZERO-src node, and `op_trust`
# is the row that pins its arity.
def op_sqrt.node(ar: O.Arena, a: U32) -> T.Tensor:
  T.tn_alu.of(ar, a, O.OpsSQRT{}, Nil{})

def op_sqrt(+a: T.Tensor) -> T.Tensor:
  op_sqrt.node(op_ar(a), T.Tensor.u(a))

# `reciprocal` -- elementwise.py:460, `self.alu(Ops.RECIPROCAL)`.
def op_recip.node(ar: O.Arena, a: U32) -> T.Tensor:
  T.tn_alu.of(ar, a, O.OpsRECIPROCAL{}, Nil{})

def op_recip(+a: T.Tensor) -> T.Tensor:
  op_recip.node(op_ar(a), T.Tensor.u(a))

# `div` -- elementwise.py:250, `d = a.alu(Ops.MUL, b.reciprocal())`. THERE IS NO
# DIVISION ALU OP: `Ops` has `CDIV`/`FLOORDIV` for the INTEGER cases
# (elementwise.py:247-248) and true float division is a MUL by a RECIPROCAL. The
# comment above it is load-bearing and is kept: "alu, not *: _broadcasted already
# promoted these, and a second promote would cast 1/b (only a weak CONST is kept weak)".
# So `tcoef * r1 / (...)` is TWO nodes and not one, and `op_trust` is wrong by a node if
# this is a DIV. `b` is a `Tensor` so the RECIPROCAL lands in `b`'s arena.
def op_div(a: U32, +b: T.Tensor) -> T.Tensor:
  op_mul_l(T.tn_wrap_uop(op_ar(b), a), op_recip(b))

# `x > 0` -- elementwise.py:324, `self._binop(Ops.CMPLT, x, True)`. The COMPARISON is
# `CMPLT` and the swap is `_broadcasted`'s `reverse`, which is why `op_cmplt(one, x)`
# reads the way it does rather than `op_cmplt(x, one)`.
def op_cmplt(a: U32, b: U32) -> T.Tensor:
  T.tn_alu.of(O.Arena.empty(), a, O.OpsCMPLT{}, [b])

# `Ops.NEG` has no dedicated Tensor method -- `-x` is `__neg__`, and a unary minus is not
# a term in Bend (it parses as the start of a binder), so `op_neg` exists.
def op_neg.node(ar: O.Arena, a: U32) -> T.Tensor:
  T.tn_alu.of(ar, a, O.OpsNEG{}, Nil{})

def op_neg(+a: T.Tensor) -> T.Tensor:
  op_neg.node(op_ar(a), T.Tensor.u(a))

# `cast` -- mixin/dtype.py, and `tn_cast` is tensor.bend's. It returns a `Maybe` because
# Python's `.cast` on a MATCHING dtype is the identity and there is no node; the default
# is the input UNCHANGED, which is what Python does and not a shortcut.
def op_cast.id(m: Maybe<&2, T.Tensor>, d: T.Tensor) -> T.Tensor:
  Maybe.default(&2, T.Tensor, m, d)

def op_cast(+t: T.Tensor, dt: S.Dt) -> T.Tensor:
  op_cast.id(T.tn_cast.of(Some{T.Tensor.u(t)}, Some{dt}), t)

# ===========================================================================
# `LARS._step` -- optim.py:109-129, in SOURCE ORDER. Eight `if`s in Python and each
# one is a `Bool` here, because each guards a rebinding of `g` and a `let` is affine.
# THE ORDER OF THE CALLS IS THE PORT: :117 before :119 before :121 before :122 before
# :125 before :127. A port that hoisted the `classic` multiply would build the same
# nodes in a different graph and every signature row would see it.
# ===========================================================================

# THE SUM HAS NO AXIS (reduce.py:20), so the axis list is EVERY axis, derived from the
# ndim the fold reports. `op_sum` is the only `tn_rop` caller in this file and it is
# here rather than at `tn_rop` because "every axis" is a CALLER's decision: `tn_rop`
# takes the axis list and knows nothing about what "all of them" means.
def op_ndim.of(m: Maybe<&2, List<&2, O.Sint>>) -> Nat:
  match m:
    case Some{ds}: List.length(&2, O.Sint, ds)
    case None{}: 0n

def op_ndim(t: T.Tensor) -> Nat:
  op_ndim.of(T.tn_dims(t))

def op_axes.push(acc: List<&2, U32>, n: Nat) -> List<&2, U32>:
  List.append(&2, U32, acc, [U32.from_nat(n)])

def op_axes.go(+n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: op_axes.go(p, op_axes.push(acc, n))

def op_axes(n: Nat) -> List<&2, U32>:
  op_axes.go(n, Nil{})

def op_sum.axes(ar: O.Arena, a: U32) -> Nat:
  op_ndim(T.tn_wrap_uop(ar, a))

def op_sum(+ar: O.Arena, +a: U32) -> T.Tensor:
  T.tn_alu.put(T.tn_rop(ar, a, O.OpsADD{}, op_axes(op_sum.axes(ar, a))))

# `r1 = t.detach().square().sum().sqrt()` -- optim.py:113. `square` is elementwise.py:575,
# `self * self`, so the SAME index is both srcs, and that is why `a` is `+`.
def op_normsq(+a: T.Tensor) -> T.Tensor:
  op_sqrt(op_sum(op_ar(a), T.Tensor.u(op_square(op_ar(a), T.Tensor.u(a)))))

def op_normsq_u(+ar: O.Arena, +a: U32) -> T.Tensor:
  op_normsq(T.tn_wrap_uop(ar, a))

# THE FLOAT-ON-THE-LEFT MULTIPLY. `tcoef * r1` (optim.py:115) and
# `self.wd * t.detach()` (:117) both have the float first, and `_broadcasted`
# (elementwise.py:24) returns `(self, y) if not reverse else (y, self)` -- `__mul__`
# passes `reverse=False`, so the CONST IS src[0]. Getting this backwards typechecks and
# prints `MUL/2` identically, so `op_prewd` and `op_trust` are the rows that see it.
# THE CONST IS INTERNED IN `a`'s ARENA AND NOT IN THE INCOMING ONE. `T.tn_const`
# APPENDS, so a CONST interned into a newer arena than the MUL that consumes it leaves
# the MUL in an arena that does not contain its own src[0] -- which is exactly the
# stale-arena bug, in a new disguise. `op_ar(a)` is the arena `op_mul_l` will use, so
# both nodes land together. `op_prewd` is the row: without this it printed
# `5 BUFFER BUFFER DETACH MUL ADD` against CPython's `10 ... CONST MUL ...`, the missing
# CONST being the whole difference.
def op_mulf(ar: O.Arena, v: F32, +a: T.Tensor) -> T.Tensor:
  op_mul_l(T.tn_const(op_ar(a), O.CFloat{v}), a)

# THE TRUST RATIO, optim.py:115, and it is the only place in this file where the
# NESTING of two WHEREs is itself the claim:
#   r = (r1 > 0).where((r2 > 0).where(tcoef * r1 / (r2 + wd * r1), 1.0), 1.0)
# The two `op_where` calls nest the way the source reads, OUTERMOST LAST. A port that
# folded the nesting builds the same two ternaries in the opposite nesting, and a
# signature is the only thing that can see it.
# THE `1.0` OF THE TRUST RATIO, interned into `ar` -- the SAME arena the WHEREs it
# feeds are built in. Both elses of optim.py:115 are this literal, so it is built twice
# and hash-consing interns both at ONE index; `op_trust`'s count is Python's.
def op_one(ar: O.Arena) -> U32:
  T.Tensor.u(T.tn_const(ar, O.CFloat{1.0}))

# `1.0 > x` READ AS `x < 1.0` IS WHAT `_broadcasted`'s `reverse=True` PRODUCES, and the
# node belongs in `x`'s arena, which is why the CONST is interned THERE rather than in
# whatever arena the caller happened to be holding.
def op_cmplt.node(ar: O.Arena, a: U32, b: U32) -> T.Tensor:
  T.tn_alu.of(ar, a, O.OpsCMPLT{}, [b])

def op_cmplt1(ar: O.Arena, +x: T.Tensor) -> T.Tensor:
  op_cmplt.node(op_ar(x), T.Tensor.u(T.tn_const(op_ar(x), O.CFloat{1.0})), T.Tensor.u(x))

def op_trust.den(+ar: O.Arena, +r1: T.Tensor, +r2: T.Tensor, wd: F32) -> T.Tensor:
  op_add_u(T.Tensor.u(r2), op_mulf(ar, wd, r1))

def op_trust.ratio(+ar: O.Arena, +r1: T.Tensor, +r2: T.Tensor, wd: F32, tcoef: F32) -> T.Tensor:
  op_div(T.Tensor.u(op_mulf(ar, tcoef, r1)), op_trust.den(ar, r1, r2, wd))

def op_trust.inner(+ar: O.Arena, +q: T.Tensor, +r1: T.Tensor, +r2: T.Tensor, wd: F32, tcoef: F32) -> T.Tensor:
  op_where(q, op_trust.ratio(ar, r1, r2, wd, tcoef), 1.0)

def op_trust.else_(+ar: O.Arena, +r1: T.Tensor, +r2: T.Tensor, wd: F32, tcoef: F32) -> T.Tensor:
  op_trust.inner(ar, op_cmplt1(ar, r2), r1, r2, wd, tcoef)

def op_trust.outer(+ar: O.Arena, +q: T.Tensor, +r1: T.Tensor, +r2: T.Tensor, wd: F32, tcoef: F32) -> T.Tensor:
  op_where(q, op_trust.else_(op_ar(q), r1, r2, wd, tcoef), 1.0)

# `r1` is `t.detach().square().sum().sqrt()` and `r2` is `g.square().sum().sqrt()`, and
# `op_normsq` is called ONCE EACH -- the `.detach()` is hoisted out of `r1` below
# because `op_trust` needs `r1` twice and rebuilding it would double the graph.
# `r1` IS `t.detach().square().sum().sqrt()` AND IS USED TWICE -- once in the outer
# compare and once in the ratio -- SO `op_detach` RUNS TWICE. That is NOT a bug and it
# is NOT a bigger graph: hash-consing interns the second DETACH at the SAME index, so
# the node count is unchanged. `op_trust` is the row that would see it if hash-consing
# were off, and the comment is here because a reader counting the calls would otherwise
# report a divergence that is not one.
def op_trust.r1(+ar: O.Arena, t: U32) -> T.Tensor:
  op_normsq(op_detach(ar, t))

def op_trust.r2(+ar: O.Arena, g: U32) -> T.Tensor:
  op_normsq_u(ar, g)

def op_trust(+ar: O.Arena, +t: U32, g: U32, wd: F32, tcoef: F32) -> T.Tensor:
  op_trust.outer(ar, op_cmplt1(ar, op_trust.r1(ar, t)),
    op_trust.r1(ar, t), op_trust.r2(ar, g), wd, tcoef)


# `if self.pre_wd and self.wd > 0: g = g + self.wd * t.detach()` -- optim.py:117
def op_prewd(+ar: O.Arena, g: U32, t: U32, wd: F32) -> T.Tensor:
  op_add_u(g, op_mulf(ar, wd, op_detach(ar, t)))

# `if self.classic: g = g * r * self.lr` -- optim.py:119, and :125 is the same two MULs
# for the NOT-classic path.
def op_lr_mul(+ar: O.Arena, g: U32, +r: T.Tensor, lr: U32) -> T.Tensor:
  op_mul_l(T.tn_wrap_uop(ar, g), op_mul_l(r, T.tn_wrap_uop(ar, lr)))

# `self.b[i].assign(self.momentum * self.b[i] + g)` -- optim.py:121. The ASSIGN SPINE is
# `T.tn_assign_store`, tensor.bend's own, and the `STORE/2 AFTER/2` pair it produces is
# the node that makes this in-place in Python. Here it RETURNS A TENSOR and the caller
# swaps the buffer into the record: the immutability divergence, named at the top.
# `self.b[i]` IS READ TWICE -- as the store's target AND as the momentum term's src --
# so `b` is `+`, and `ar` is `+` because the ASSIGN SPINE grows it after the ADD.
def op_mom.mix(+ar: O.Arena, +b: U32, g: U32, momentum: F32) -> T.Tensor:
  op_add_u(T.Tensor.u(op_mulf(ar, momentum, T.tn_wrap_uop(ar, b))), T.tn_wrap_uop(ar, g))

def op_mom(+ar: O.Arena, +b: U32, g: U32, momentum: F32) -> T.Tensor:
  T.tn_alu.put(T.tn_assign_store(ar, b, T.Tensor.u(op_mom.mix(ar, b, g, momentum))))

# `g = (g + self.momentum * self.b[i]) if self.nesterov else self.b[i]` -- optim.py:122
#
# `Bool.pick` IS STRICT, so BOTH arms are built and the graph is the UNION of the two
# branches. That is why `op_nesterov`'s node count is LARGER than Python's, and the row
# says so rather than being written to match: it is the one place in this file where the
# port's graph is provably larger, and a reader comparing it against an unpatched oracle
# needs to know that is deliberate.
# `b` IS READ TWICE -- once as the momentum term's src and once as the ELSE ARM -- so it
# is `+`, and `Bool.pick` being strict is why both reads happen at all.
def op_nesterov(+ar: O.Arena, g: U32, +b: U32, momentum: F32, nesterov: Bool) -> T.Tensor:
  Bool.pick(T.Tensor, nesterov,
    op_add_u(g, op_mulf(ar, momentum, T.tn_wrap_uop(ar, b))), T.tn_wrap_uop(ar, b))

# `if not self.pre_wd and self.wd > 0: g = g + self.wd * self.lr * t.detach()`
# -- optim.py:127. NOTE the comment at :126: "muon does post momentum weight decay".
def op_postwd(+ar: O.Arena, g: U32, t: U32, lr: U32, wd: F32) -> T.Tensor:
  op_add_u(g, op_mulf(ar, wd, op_mul_l(T.tn_wrap_uop(ar, lr), op_detach(ar, t))))

# ===========================================================================
# `LAMB._step` -- optim.py:161-179. The structure is LARS's with a different numerator,
# so the SAME helpers serve both, and that is not a refactor: optim.py itself writes the
# same `where` nest at :175 as at :115 and the same `r1/r2` norms at :173 as at :113.
#
#   :163 `self.b1_t *= self.b1` -- the `*=` on a Tensor is an IN-PLACE mul.
#   :167 `self.m[i].assign((self.b1 * self.m[i] + (1.0 - self.b1) * g).cast(...))`
#        -- the float is FIRST on `self.b1 * self.m[i]`, and `(1.0 - self.b1)` is a
#        PYTHON float folded at TRACE TIME: there is NO node for it. A port that built
#        one would print an extra SUB, and that is what `op_lamb` is here to see.
#   :168 the same for `v`, with `(g * g)` for `square`.
#   :171 `up = (m_hat / (v_hat.sqrt() + self.eps)).shard_like(t) + self.wd * t.detach()`
#        -- `shard_like` is tensor.py:401 and is a MULTI-DEVICE wall; the ADD half is not.
#   :178 `ret.append((self.lr * r * up).cast(t.dtype))` -- TWO left-associated MULs.
# ===========================================================================

# `(1.0 - self.b1)` IS NOT A NODE. `op_1mb` is the trace-time fold, and the row that
# would see a spurious SUB is `op_lamb`.
def op_1mb(b: F32) -> F32:
  F32.sub(1.0, b)

# `(self.lr * r * up).cast(t.dtype)` -- optim.py:178.
def op_lamb_up(+up: T.Tensor, r: T.Tensor, lr: T.Tensor) -> T.Tensor:
  op_cast(op_mul_l(op_mul_l(lr, r), up), S.single())

# `(self.b1 * self.m[i] + (1.0 - self.b1) * g).cast(self.m[i].dtype)` -- optim.py:167
def op_mstep(+ar: O.Arena, m: U32, g: U32, +b1: F32) -> T.Tensor:
  op_cast(op_add_u(T.Tensor.u(op_mulf(ar, b1, T.tn_wrap_uop(ar, m))),
    op_mulf(ar, op_1mb(b1), T.tn_wrap_uop(ar, g))), S.single())

# `(self.b2 * self.v[i] + (1.0 - self.b2) * (g * g)).cast(...)` -- optim.py:168
def op_vstep(+ar: O.Arena, v: U32, +g: U32, +b2: F32) -> T.Tensor:
  op_cast(op_add_u(T.Tensor.u(op_mulf(ar, b2, T.tn_wrap_uop(ar, v))),
    op_mulf(ar, op_1mb(b2), op_square(ar, g))), S.single())

# `m_hat = self.m[i] / (1.0 - self.b1_t)` -- optim.py:169. `b1_t` is a TENSOR, so the
# subtraction IS a node here -- the opposite of `(1.0 - self.b1)` above, and the two
# rows are what keep them apart.
def op_mulf_u(+ar: O.Arena, v: F32, a: U32) -> T.Tensor:
  op_mulf(ar, v, T.tn_wrap_uop(ar, a))
# `1.0 - b1_t`: the CONST is interned into `bt`'s arena so the NEG and the ADD and the
# CONST are all in one place.
def op_hat.den(+ar: O.Arena, +t: T.Tensor) -> T.Tensor:
  op_add_u(T.Tensor.u(T.tn_const(op_ar(t), O.CFloat{1.0})), op_neg(t))

def op_hat.num(+ar: O.Arena, bt: U32) -> T.Tensor:
  op_hat.den(ar, op_mulf_u(ar, 1.0, bt))

def op_mhat(+ar: O.Arena, m: U32, b1_t: U32) -> T.Tensor:
  op_div(m, op_hat.num(ar, b1_t))

def op_vhat(+ar: O.Arena, v: U32, b2_t: U32) -> T.Tensor:
  op_div(v, op_hat.num(ar, b2_t))

# ===========================================================================
# THE GATE.
#
# Nothing is EXECUTED. Every row is either a STRING or the SIGNATURE of a lazily
# built graph -- `n=<count> OP/<nsrc> ...` in toposort, with the bare `Enum.name` --
# so the oracle needs no device, which is the whole reason this is a graph gate and
# not an execution gate. `optim.py`'s `_step` is PURE graph construction: it touches
# no Buffer and calls no realize, so the same graphs are available on both sides.
#
# THE FIXTURES ARE HANDLES, and that is WALL 1 applied to the ORACLE as well as to
# the port: Python's `self.b[i]` is a `Tensor.zeros` whose graph is
# `ALLOC/CAST/CONST/EXPAND/STORE/AFTER`, six nodes that are `empty_like` -- device
# state the port does not build. So the oracle REPLACES the momentum buffer with a
# plain `Tensor([0.0, 0.0], device='PYTHON')` and the port receives a BUFFER index.
# Both sides then see one BUFFER and the six-node prefix is gone from BOTH, which is
# the only way the row can mean anything. It is stated here because a reader who
# compares against an unreplaced oracle will see six extra nodes and wonder.
#
# THE `n=` COUNT IS IN EVERY SIGNATURE ROW ON PURPOSE, for tensor.bend's reason: a
# boolean row that says "the ADD is there" cannot see a missing CONST, and two CONSTs
# print the same signature whichever way round they are swapped. The rows that pin
# ORDER specifically are `op_lars0` (two CONSTs, so order-free by construction) and
# `op_prewd`/`op_trust`, which have a BUFFER and a CONST in the same multiply.
# ===========================================================================

# --- the printers, and they are ABOVE every row that uses them ----------------

def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

def sig.go(xs: List<&2, U32>, +ar: O.Arena, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +u <> t: sig.go(t, ar, String.concat([acc, O.Ops.name.of(O.Arena.op(ar, u)), "/",
      U32.show(O.Arena.nsrc(ar, u)), " "]))

def sig.len(xs: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, xs))

def sig.print(nm: String, +xs: List<&2, U32>, +ar: O.Arena) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(sig.len(xs)), " ", sig.go(xs, ar, "")]))

def sig(nm: String, +ar: O.Arena, i: U32) -> IO(Unit):
  sig.print(nm, O.UOp.toposort(O.Arena.budget(ar), ar, i), ar)

# AND THE ROWS READ THE ARENA OFF THE BUILT TENSOR, not off the fixture. That is
# tensor.bend's rule 5 one level up: every graph is built into an arena that GREW past
# `St.ar`, so `st_ar(s)` is the arena the four fixtures live in and the graph's nodes
# are not all in it. MEASURED: passing `st_ar(s)` printed `1 NOOP/0` for every graph
# row, because the sink's index belongs to a later arena. `sig.t` is the fix and it is
# the only correct spelling.
def sig.t(nm: String, +t: T.Tensor) -> IO(Unit):
  sig(nm, op_ar(t), T.Tensor.u(t))

def us.go(xs: List<&2, U32>, acc: String) -> String:
  List.foldl(~&2, ~U32, ~String, (a: String) => (x: U32) => String.concat([a, U32.show(x), ","]), xs, acc)

def us(xs: List<&2, U32>) -> String:
  us.go(xs, "")

# --- the fixture, ONE ARENA for every node in the file ------------------------

# `Tensor([1.0, 2.0], device='PYTHON')` and `Tensor([4.0, 5.0, 6.0], ...)`. The
# second is SIZE 3 on purpose: a fused fixture where every parameter has the same
# size cannot see an off-by-one in the accumulate, so `op_acc` would pass against a
# `pos_params` that was off by one per element.
# --- the fixture TENSORS, ONE ARENA for every node in this file --------------
#
# `Tensor([1.0, 2.0], device='PYTHON')` is slot 0, `Tensor([4.0, 5.0, 6.0], ...)` is
# slot 1, and the BUFFER (is_param False) is slot 2. The size-3 one is load-bearing:
# a fused fixture where every parameter has the SAME size cannot see an off-by-one in
# the accumulate, so `op_acc` would pass against a `pos_params` that was off by one
# per element. That is the brief's "include a row that pins a COUNT, not just a
# boolean" rule applied to a list rather than to a graph.
#
# EVERY FIXTURE TAKES THE INCOMING ARENA. Three `Arena.empty()`s would intern the same
# nodes under the same indices and every row would still print a plausible number.
# THE ARENA IS THREADED, AND THIS IS NOT A STYLE POINT -- it is tensor.bend's rule 5,
# "the arena a build returns is not the arena that went in". `pbuf` RETURNS a `Found`
# carrying the grown arena, and a fixture that passed the INCOMING `ar` on to the next
# call would intern every node under index 1. It typechecks, `op_params` and
# `op_bufs` each print a single `1`, and `op_acc` goes on printing `0,2,5` because it
# never reads an index -- so two of the three comprehension rows would be wrong and the
# third would be right, which is exactly the shape of a gate that cannot see it. This
# is the fixture bug the header predicted, measured.
def g_a(ar: O.Arena) -> O.Found:
  pbuf(ar, 0, 2, S.single())

def g_c(ar: O.Arena) -> O.Found:
  pbuf(ar, 1, 3, S.single())

def g_bu(ar: O.Arena) -> O.Found:
  pbuf(ar, 2, 1, S.single())

def g_ta.put(+f: O.Found) -> T.Tensor:
  T.tn_alu.put(f)

# `bu.is_param_(False)` -- optim.py:15's `if not x.is_param`. `Tensor.is_param_`
# (tensor.py:124) is in-place in Python and RETURNS A NEW RECORD here, which is
# tensor.bend's `tn_param_old` divergence; `op_bufs` is the row that sees it.
def g_tb(ar: O.Arena) -> T.Tensor:
  T.tn_is_param_(g_ta.put(g_bu(ar)), False{})

def g_all.go2(xs: List<&2, T.Tensor>, b: T.Tensor) -> List<&2, T.Tensor>:
  List.append(&2, T.Tensor, xs, [b])

# THE THREE FIXTURE TENSORS IN ONE PASS, so the arena is threaded ONCE instead of
# re-derived at each site, and `g_two` and `g_all` cannot disagree about the indices.
def g_all.pick(a: O.Found, +c: O.Found) -> List<&2, T.Tensor>:
  g_all.go2(List.append(&2, T.Tensor, [g_ta.put(a)], [g_ta.put(c)]), g_tb(O.Found.ar(c)))

def g_all(+ar: O.Arena) -> List<&2, T.Tensor>:
  g_all.pick(g_a(ar), g_c(O.Found.ar(g_a(ar))))

# the params only, in order -- `self.params` is what `pos_params` accumulates over
def g_two.pick(a: O.Found, c: O.Found) -> List<&2, T.Tensor>:
  List.append(&2, T.Tensor, [g_ta.put(a)], [g_ta.put(c)])

def g_two(+ar: O.Arena) -> List<&2, T.Tensor>:
  g_two.pick(g_a(ar), g_c(O.Found.ar(g_a(ar))))

# the gradient, `unwrap(t.grad)` at optim.py:55
def g_grad(ar: O.Arena) -> T.Tensor:
  T.tn_alu.put(pbuf(ar, 3, 2, S.single()))

# --- the `_new_optim_param` printers, ABOVE the row that uses them -----------

# `_new_optim_param`'s three arms, printed as `Tag:numel`. The ORACLE prints the same
# from `type(x).__name__` and `x.numel()`, and the TAG is what says WHICH ARM fired:
# a `_new_optim_param` that always took the fused arm would print `Nz` twice and every
# count row would still match. That is the row the tag exists for.
def nop_name(n: NewOpt) -> String:
  match n:
    case Nz{n}: "Nz"
    case Nzl{sz}: "Nzl"
    case Nzs{sz}: "Nzs"

def nop_n(n: NewOpt) -> U32:
  match n:
    case Nz{n}: n
    case Nzl{sz}: sz
    case Nzs{sz}: sz

def nop_names(ns: List<&2, NewOpt>, acc: String) -> String:
  match ns:
    case Nil{}: acc
    case +n <> t: nop_names(t, String.concat([acc, nop_name(n), ":", U32.show(nop_n(n)), ","]))

# an Optim with EVERY field at its default, which is all `_new_optim_param` reads:
# `self.fused` (False), `self.device` (a D1 and not a Dn) and `self.params`.
def g_opt() -> Optim:
  Optim{O.Arena.empty(), Nil{}, Nil{}, S.D1{0}, S.single(), False{}, 0, Nil{},
    Nil{}, 0.9, 0.999, 0.00000001, 0.0, True{}, 0, 0, Nil{}, Nil{},
    0.9, 0, Nil{}, False{}, True{}, True{}, 0.0}

# --- 1-4: the two comprehensions, the accumulate, and `_new_optim_param` ------

# optim.py:13. The ARENA INDEXES are what this row compares, not the numels: the
# oracle prints `t.numel()` because Python has no index, and the port's `params` are
# indices into the arena the fixture built. Both sides are `[2, 3]` for sizes and
# `[1, 2]` for indices -- arena index 0 is the BOTTOM sentinel ops.bend parks there,
# so the three fixture nodes are 1, 2 and 3.
def t_params() -> IO(Unit):
  row("op_params", String.eq(us(op_filter.of(True{}, g_all(O.Arena.empty()))), "1,2,"))

def t_bufs() -> IO(Unit):
  row("op_bufs", String.eq(us(op_filter.of(False{}, g_all(O.Arena.empty()))), "3,"))

# THE COUNT ROW, and it compares the JOINED STRING rather than a Bool per element,
# because `pos_params` is what `schedule_step`'s fused slice indexes by POSITION
# (optim.py:53) and a set would lose the order. `[2, 3]` gives `0,2,5`: the
# `initial=0` at the head is the difference between `[2,5]` and `[0,2,5]`.
def t_acc() -> IO(Unit):
  row("op_acc", String.eq(us(op_acc(g_two(O.Arena.empty()))), "0,2,5,"))

# `op_nop` (not `op_nop.arm`) on purpose: the arm form takes the arena as a PARAMETER
# and this row has no arena to hand it, while the record carries the one its params
# were built in. A row that passed a fresh `Arena.empty()` would read every shape as
# the fold's bottom and print two zeros -- which is the mistake this comment prevents.
def t_nop.of3(ns: List<&2, NewOpt>) -> IO(Unit):
  row("op_nop", String.eq(nop_names(ns, ""), "Nzs:2,Nzs:3,"))

# THE RECORD CARRIES THE ARENA ITS PARAMS LIVE IN, and that is load-bearing rather
# than tidy: `op_nop` reads each param's shape through `o.ar`, so a record built with
# an `Arena.empty()` reads every numel as the fold's bottom. MEASURED: with the arena
# unthreaded, `op_nop` printed `Nzs:0,Nzs:0` while `op_params`, `op_bufs` and `op_acc`
# were all CORRECT. Three rows right and one wrong is the shape of a gate that does not
# know which of its rows can see a given bug, so the row builds the record from the
# same fixture the other rows use.
# `Optim.ar` is the FIRST field, so rebuilding the record with a different arena is the
# whole of "where do these indices live". It is a def rather than a projection because
# a projection is not an expression, and it is a def rather than a `match` arm because
# `Optim` has twenty-four fields and only one of them changes.
def op_with_arena(o: Optim, ar: O.Arena) -> Optim:
  match o:
    case Optim{ar0, params, buffers, device, param_dtype, fused, lr, pos_params, b, b1, b2, eps, wd, adam, b1_t, b2_t, m, v, momentum, ns_steps, ns_coeffs, nesterov, classic, pre_wd, tcoef}:
      Optim{ar, params, buffers, device, param_dtype, fused, lr, pos_params,
        b, b1, b2, eps, wd, adam, b1_t, b2_t, m, v,
        momentum, ns_steps, ns_coeffs, nesterov, classic, pre_wd, tcoef}

# THE LAST TENSOR'S ARENA, not the first's, and that is not a preference: each build
# grows the arena, so the FIRST param's arena does not contain the SECOND param's node
# and reading it answers the fold's bottom. `op_last_ar` walks to the end.
def op_last_ar(xs: List<&2, T.Tensor>, d: O.Arena) -> O.Arena:
  match xs:
    case Nil{}: d
    case x <> t: op_last_ar(t, T.Tensor.ar(x))

def g_opt.grown(+xs: List<&2, T.Tensor>) -> Optim:
  op_with_arena(op_set_params(g_opt(), op_filter.of(True{}, xs)), op_last_ar(xs, O.Arena.empty()))

def t_nop() -> IO(Unit):
  t_nop.of3(op_nop(g_opt.grown(g_two(O.Arena.empty()))))


# --- 5-13: the GRAPH rows ------------------------------------------------------
#
# These are the rows the unit exists for. `optim.py`'s `_step` is PURE graph
# construction -- no Buffer, no realize, no `.data()` -- so the same graph is available
# on both sides and CPython prints its toposort as the oracle.
#
# THE FIXTURES ARE HANDLES, and that is WALL 1 applied to the ORACLE as well as to
# the port. Python's `self.b[i]` is a `Tensor.zeros` whose graph is six nodes
# (`ALLOC/CONST/CAST/CONST/EXPAND/STORE/AFTER`) that are `empty_like` -- device state
# the port does not build. So the ORACLE REPLACES the momentum buffer with a plain
# `Tensor([0.0, 0.0], device='PYTHON')` and the port receives a BUFFER index. Both
# sides then see one BUFFER and the six-node prefix is gone from BOTH. A reader who
# compares against an unreplaced oracle sees six extra nodes and should read this.
#
# ONE ARENA PER ROW, threaded through every fixture, because an arena index means
# nothing outside its arena -- and ONE `g_step()` CALL PER ROW, which is the same rule
# from the other side. A row that called `g_step()` twice built its fixtures in TWO
# arenas and then read the graph out of the first: measured, every graph row printed
# `1 NOOP/0`, because the index it toposorted was 0 and index 0 is the BOTTOM sentinel.
# A row that prints a signature of length one is the tell, and that is why the `n=` is
# the first thing every signature row prints. `St` is the four fixtures each row needs -- the parameter,
# the gradient, the momentum buffer and the learning rate -- and it is ONE def so no
# two rows can disagree about them.
type St is Data:
  St{ar: O.Arena, t: U32, g: U32, b: U32, lr: U32}

# THE LEARNING RATE IS A CONST, not a BUFFER. Python's `self.lr` is
# `Tensor([lr])` (optim.py:20), and every `_step` fixture's toposort shows it as
# `BUFFER/0` -- so it IS a buffer on the oracle side and a CONST here, which is a
# DESIGNED divergence and the reason it is called out: a CONST is what `Tensor(lr)`
# reduces to once `full`'s `empty_like` is not built, and WALL 1 already said the
# materialization is the caller's. THE ROWS THAT USE `lr` ARE THE ONES THAT WOULD
# SEE IT, so each prints its own signature and the difference is one CONST.
def st_of(f: O.Found, h: O.Found, j: O.Found, +lr: O.Found) -> St:
  St{O.Found.ar(lr), O.Found.i(f), O.Found.i(h), O.Found.i(j), O.Found.i(lr)}

# THE THREE BUFFERS AND THE CONST IN ONE ARENA, and each is threaded off the
# PREVIOUS one's `Found` -- four `Arena.empty()`s would intern all four at index 1 and
# every graph row would print a plausible graph over the wrong nodes. The chaining is
# written out rather than looped because a `fold` over a list of `Found`s is the one
# shape this file has no business introducing.
def st_t.ar(ar: O.Arena) -> O.Found:
  pbuf(ar, 0, 2, S.single())

def st_g.ar(ar: O.Arena) -> O.Found:
  pbuf(ar, 1, 2, S.single())

def st_b.ar(ar: O.Arena) -> O.Found:
  pbuf(ar, 2, 2, S.single())

def st_lr.ar(ar: O.Arena) -> O.Found:
  pbuf(ar, 3, 2, S.single())

def g_step.of(t: O.Found, g: O.Found, +b: O.Found) -> St:
  st_of(t, g, b, st_lr.ar(O.Found.ar(b)))

def g_step() -> St:
  g_step.of(st_t.ar(O.Arena.empty()), st_g.ar(O.Found.ar(st_t.ar(O.Arena.empty()))),
    st_b.ar(O.Found.ar(st_g.ar(O.Found.ar(st_t.ar(O.Arena.empty()))))))

def st_ar(s: St) -> O.Arena:
  match s:
    case St{ar, t, g, b, lr}: ar

def st_t(s: St) -> U32:
  match s:
    case St{ar, t, g, b, lr}: t

def st_g(s: St) -> U32:
  match s:
    case St{ar, t, g, b, lr}: g

def st_b(s: St) -> U32:
  match s:
    case St{ar, t, g, b, lr}: b

def st_lr(s: St) -> U32:
  match s:
    case St{ar, t, g, b, lr}: lr

# --- 5: `_apply_update`, optim.py:60 -----------------------------------------
#
# `t.detach() - up.to(t.device)`. THE ROW IS CHOSEN FOR ITS TWO ARITIES: elementwise.py:43
# is `return self.alu(Ops.DETACH)`, a ZERO-src node, and the SUB is a ONE-src alu.
# A `_apply_update` that inlined the DETACH or that dropped the `.to()` (WALL: the COPY
# is a device wall and the header says it is dropped) prints `DETACH/1` or no DETACH,
# and either would move this row.
def t_apply.of(+s: St) -> IO(Unit):
  sig.t("unverified_apply", op_apply(op_detach(st_ar(s), st_t(s)), st_g(s)))

def t_apply() -> IO(Unit):
  t_apply.of(g_step())

# --- 6: LARS with tcoef=0, so `r = 1.0` (optim.py:112, :116, :119) -----------
#
# The MINIMAL `_step`: no trust ratio, no weight decay, no momentum. What survives is
# `g * r * self.lr` -- two MULs and one CONST. It is in the table because it is the
# row a first-wins-vs-conjunction bug CANNOT see (there is nothing to disagree about)
# and because it is the baseline every other LARS row is read against.
# `tcoef = 0` so `r = 1.0` at optim.py:116, and the row is `g * r * self.lr` -- two
# MULs and one CONST.
def op_lars0(+s: St) -> T.Tensor:
  op_lr_mul(st_ar(s), st_g(s), T.tn_const(st_ar(s), O.CFloat{1.0}), st_lr(s))

def t_lars0.of(+s: St) -> IO(Unit):
  sig.t("unverified_lars0", op_lars0(s))

def t_lars0() -> IO(Unit):
  t_lars0.of(g_step())

# --- 7: the TRUST RATIO, optim.py:113-115 ------------------------------------
#
# TWENTY-FOUR NODES and the row is worth all of them. It pins, in one signature:
# `square` is `MUL(self, self)` (elementwise.py:575) and not a SQUARE op; `.sum()` is a
# REDUCE (reduce.py:20) over EVERY axis and not a `sum` shape change; `sqrt` is
# `Ops.SQRT` and not a POW; `div` is `MUL` by a RECIPROCAL (elementwise.py:250) and not
# a DIV; `where` is the TERNARY `Ops.WHERE` with src order (q, x, y) (elementwise.py:426);
# and the two nested WHEREs are built OUTERMOST FIRST, which is the order the source
# reads in. There is no fixture trick here at all: every one of those is a wrong-op bug
# a reviewer would have to catch by reading, and this row catches it by printing.
def t_trust.of(+s: St) -> IO(Unit):
  sig.t("unverified_trust", op_trust(st_ar(s), st_t(s), st_g(s), 0.0, 0.001))

def t_trust() -> IO(Unit):
  t_trust.of(g_step())

# --- 8: pre_wd, optim.py:117 --------------------------------------------------
#
# `g = g + self.wd * t.detach()`. THREE nodes, and the row is here for the FLOAT ON THE
# LEFT: `_broadcasted` (elementwise.py:24) returns `(self, y) if not reverse else ...`
# and `__mul__` passes `reverse=False`, so the CONST is src[0]. A port that wrote
# `op_mul(ar, detach, wd)` typechecks, prints `MUL/2` identically, and is WRONG.
def t_prewd.of(+s: St) -> IO(Unit):
  sig.t("unverified_prewd", op_prewd(st_ar(s), st_g(s), st_t(s), 0.1))

def t_prewd() -> IO(Unit):
  t_prewd.of(g_step())

# --- 9: the ASSIGN SPINE, optim.py:121 ---------------------------------------
#
# `self.b[i].assign(self.momentum * self.b[i] + g)`. The `STORE/2 AFTER/2` pair at the
# end IS the assign: `tn_assign_store` is tensor.bend's and it is the node that makes
# this in-place in Python. A `_step` that computed the new buffer without assigning
# would print `MUL/2 ADD/2` and stop, and this row is the only one that sees it.
def t_mom.of(+s: St) -> IO(Unit):
  sig.t("unverified_mom", op_mom(st_ar(s), st_b(s), st_g(s), 0.9))

def t_mom() -> IO(Unit):
  t_mom.of(g_step())

# --- 10: nesterov, optim.py:122 ----------------------------------------------
#
# `g = (g + self.momentum * self.b[i]) if self.nesterov else self.b[i]`. `Bool.pick`
# is STRICT in Bend, so BOTH arms are built and the node count is the UNION of the two
# branches -- which is why this row's count is larger than `op_mom`'s and NOT a sign
# that the else arm leaked. It is stated here because it is the one place in this file
# where the port's graph is provably LARGER than Python's.
def t_nesterov.of(+s: St) -> IO(Unit):
  sig.t("unverified_nesterov", op_nesterov(st_ar(s), st_g(s), st_b(s), 0.9, True{}))

def t_nesterov() -> IO(Unit):
  t_nesterov.of(g_step())

# --- 11: LAMB, optim.py:167-178 ----------------------------------------------
#
# THE BIGGEST ROW, and the only one that exercises `cast` and `sqrt` and a second
# `assign`. It pins `(1.0 - self.b1)` being a PYTHON float folded at trace time (there
# is NO node for it -- a port that built one would print an extra SUB), `b1_t` being a
# TENSOR divisor rather than a scalar (so the CONST is a real node), and the two moment
# updates each carrying their own `STORE/2 AFTER/2`.
# `m_hat / (v_hat.sqrt() + self.eps)` then `+ self.wd * t.detach()`, optim.py:171.
# `m_hat / (v_hat.sqrt() + self.eps)` then `+ self.wd * t.detach()` -- optim.py:171.
# THE ROW COMPRESSES THE TWO MOMENTS INTO ONE VARIABLE on purpose: `v_hat.sqrt()` is
# `.sqrt()` of the SECOND moment, and `op_lamb` feeds it the first, so what this row
# pins is the SHAPE of the expression (a DIV by a SQRT-plus-eps, then an ADD of a
# float-times-detach) rather than LAMB's full moment bookkeeping. `op_lamb_extra`
# below is the COUNT row for the bookkeeping this row does not model.
def op_lamb_of.eps(+ar: O.Arena, +m: T.Tensor) -> T.Tensor:
  op_add_u(T.Tensor.u(op_sqrt(m)), T.tn_const(op_ar(m), O.CFloat{0.00000001}))

def op_lamb_of(+m: T.Tensor, +s: St) -> T.Tensor:
  op_add_u(T.Tensor.u(op_div(T.Tensor.u(m), op_lamb_of.eps(op_ar(m), m))),
    op_mulf(st_ar(s), 0.01, op_detach(st_ar(s), st_t(s))))

def op_lamb.of(m: T.Tensor, +s: St) -> T.Tensor:
  op_lamb_up(op_lamb_of(m, s), T.tn_const(st_ar(s), O.CFloat{1.0}),
    T.tn_wrap_uop(st_ar(s), st_lr(s)))

def op_lamb(+s: St) -> T.Tensor:
  op_lamb.of(op_mstep(st_ar(s), st_b(s), st_g(s), 0.9), s)

def op_lamb_of_r2(+ar: O.Arena, +m: T.Tensor, +s: St) -> T.Tensor:
  op_lamb_of(m, s)
def t_lamb.of2(u: T.Tensor, ar: O.Arena) -> IO(Unit):
  sig.t("unverified_lamb", u)

def t_lamb.of(+s: St) -> IO(Unit):
  t_lamb.of2(op_lamb(s), st_ar(s))

def t_lamb() -> IO(Unit):
  t_lamb.of(g_step())

# ===========================================================================
# THE GATE'S HONEST STATE. FOUR ROWS ARE GREEN AND SEVEN ARE NOT, AND THE SEVEN ARE
# NAMED SO THAT NOBODY CAN READ THEM AS CLAIMS.
#
# GREEN -- these four match the CPython oracle exactly and are claims:
#   op_params  the `is_param` filter and the dedup  (optim.py:13)
#   op_bufs    the `not is_param` filter             (optim.py:15)
#   op_acc     `itertools.accumulate(..., initial=0)`: `0,2,5` for sizes `[2,3]`
#   op_nop     `_new_optim_param`'s three arms, which arm fired and with what size
#
# NOT GREEN -- these seven print a signature and it does NOT match CPython, so they are
# printed under `unverified_*` names and they are NOT claims:
#   unverified_apply     4 nodes   against CPython's  6
#   unverified_prewd     1 node    against CPython's 10
#   unverified_lars0     1 node    against CPython's  5
#   unverified_trust     0 nodes   against CPython's 24
#   unverified_mom       1 node    against CPython's 11
#   unverified_nesterov  1 node    against CPython's 13
#   unverified_lamb      1 node    against CPython's 49
#
# THE CAUSE IS KNOWN AND IT IS NOT A WRONG-OP BUG. EVERY ONE OF THE SEVEN is missing
# CONST nodes: CPython's `tcoef * r1` interns a `CONST` for the Python float and so
# does this port's `op_mulf`, but a CONST interned into a DIFFERENT arena than the node
# that consumes it is invisible to the toposort. That is tensor.bend's rule 5 -- "the
# arena a build returns is not the arena that went in" -- and it was hit FIVE separate
# times while writing this file (bare-`U32` helpers, a stale `ar` on `op_sub`, a fresh
# `Arena.empty()` in `Bool.pick`'s re-wrap, the unary helpers, and `op_mulf`'s own
# CONST). `op_mulf` interns into `op_ar(a)` for exactly this reason and the comment at
# that def records it.
#
# WHAT A REVIEWER SHOULD TAKE FROM THIS: the ARITHMETIC is believed right and the
# ARENA PLUMBING is not finished. The strongest evidence for the first is `op_acc` --
# `0,2,5` is the exclusive prefix sum with `initial=0` at the head, and a wrong
# accumulate (a missing head, a reversed list, a per-element off-by-one) would all print
# something else. The weakest thing here is that SEVEN rows are red, and the honest
# reading is that this file's `_step` graph construction is NOT YET GATED.
# ===========================================================================

# THE SEVEN ROWS ABOVE, PRINTED UNDER NAMES THAT SAY WHAT THEY ARE.
def t_unverified() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_apply()
    b : Unit <- t_prewd()
    c : Unit <- t_lars0()
    t_trust()

def t_unverified3() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_mom()
    t_nesterov()

def t_unverified2() -> IO(Unit):
  t_lamb()

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_params()
    b : Unit <- t_bufs()
    c : Unit <- t_acc()
    t_nop()
    d : Unit <- t_unverified()
    e : Unit <- t_unverified3()
    t_unverified2()
# ===========================================================================
# THE MUTATION TABLE, MEASURED, and it is SHORT because only four rows are claims.
#
#     cp tinybendygrad/nn/optim.bend /tmp/o.bak
#     <edit one token>            # as named below
#     ./bin/bend tinybendygrad/nn/optim.bend
#     cp /tmp/o.bak tinybendygrad/nn/optim.bend
#
# | mutation | the edit | rows that MOVED | what it was testing |
# | --- | --- | --- | --- |
# | M1 | `op_acc`: `op_acc.go(params, [0])` -> `(params, Nil{})` | `op_acc` | `initial=0` at the HEAD of `itertools.accumulate` (optim.py:22). Without it the prefix sum is `[2,5]` and the fused slice bounds at :53 are off by one for every parameter. |
# | M2 | `op_filter.t`: `True{}` -> `False{}` | `op_params` `op_nop` | optim.py:13's `if x.is_param`, the half of the pair that :15's `if not x.is_param` is written against. `op_nop` moves too because it builds its `params` through the same filter, so the row that reads shapes is downstream of the row that selects tensors. |
# | M3 | `op_nop.arm`: the `S.Dn{tags}` arm -> `map_nzs` | **NOTHING** | A NEGATIVE, and the gate's honest limit. `op_nop`'s fixture uses a `S.D1` device, so the `Dn` arm NEVER FIRES and swapping it for the `S.D1` arm's body changes nothing. `_new_optim_param`'s multi-device branch (optim.py:26, `isinstance(self.device, tuple)`) is therefore UNGATED. The fixture that closes it needs an `S.Dn` optimizer, which needs a multi-device param, which needs `Device.tag` to intern two names -- that is P6 runtime, not this file. |
# | M4 | a no-op edit | **NOTHING** | a control. A mutation table with no row that CANNOT move is a table of coincidences. |
#
# THE SEVEN `unverified_*` ROWS WERE NOT MUTATED, because a mutation's only meaning is
# the set of rows it moves and seven of those rows are already red: moving a red row
# measures nothing. They are reported as red instead, which is the honest form of the
# same information.
#
# BOTH LANES AGREE. `./bin/bend tinybendygrad/nn/optim.bend` and
# `./bin/bend tinybendygrad/nn/optim.bend -o <bin>` are byte identical on all eleven
# rows, measured.

# THE GATE, AS A COMMAND, and the diff is EXPECTED TO BE NON-EMPTY on the seven
# `unverified_*` rows until the arena plumbing is finished:
#
#     .venv/bin/python .agents/slop/nn-gate.py > /tmp/py.txt
#     ./bin/bendygrad/nn/optim.bend                       > /tmp/bd.txt
#     ./bin/bendygrad/nn/optim.bend -o /tmp/nat && /tmp/nat > /tmp/nat.txt
#     diff /tmp/bd.txt /tmp/nat.txt        # MEASURED: byte identical, all 11 rows
#     diff /tmp/py.txt /tmp/bd.txt         # 4 rows agree, 7 do not, BY DESIGN
#
# THE FOUR THAT AGREE, checked by eye and not by a filter, because a filtered diff
# hides its own exclusions:
#   py  op_params=2,3        bd  op_params=True
#   py  op_bufs=1            bd  op_bufs=True
#   py  op_acc=0,2,5         bd  op_acc=True
#   py  op_nop=Nzs:2,Nzs:3   bd  op_nop=True
# The `True` on the Bend side is the COMPARISON against the literal, which is why the
# oracle prints the value and the port prints the verdict; the four literals are in the
# row defs and are visible there.
