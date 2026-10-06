# mixin/creation.bend -- tinygrad/mixin/creation.py, all 165 lines. `CreationMixin`,
# which is ALSO `UOp.empty` / `UOp.empty_like` / `UOp.const_like` (ops.py:864, :603,
# MEASURED: `UOp.empty.__qualname__ == "CreationMixin.empty"`).
#
# ---------------------------------------------------------------------------
# THE SCOPE IS SMALLER THAN MY UNIT BRIEF'S INVENTORY, and that is a FINDING, not a
# shortfall. The brief lists `eye`, `arange`, `linspace`, `tril`/`triu`, `rand`,
# `randn`, `uniform`, `normal`. None of them is in this file. MEASURED:
# `grep -rn "def arange\|def eye\|def linspace\|def tril\|def triu\|def rand\b\|def
# randn\|def normal\|def uniform" tinygrad/` names `mixin/op.py:166/215/198/236/259`
# and `mixin/rand.py:50/106/141/158` and NOTHING else -- and `tinybendygrad/mixin/
# op.bend` already owns op.py's half. So the WHOLE of creation.py is eleven bodies
# plus one `raise NotImplementedError`, and they are the ones `examples/
# beautiful_mnist.bend`'s W3 wall is built FROM: `full` is the ONLY `expand` in
# `creation.py` (creation.py:84) and `zeros`/`ones`/`*_like` are all `full`.
#
# ---------------------------------------------------------------------------
# THE WALLS. W1 AND W2 ARE MINE; W3 AND W4 ARE OTHER FILES' AND NAMED TWICE BECAUSE
# THIS FILE REACHES BOTH.
#
#   W1 mixin/creation.py:41 `empty` -- `canonicalize_device` is `tinygrad/device.py`,
#      which is a C-effect module (the boundary `bend2-constraints` section 4 draws),
#      so `dev: S.Dev` is a PARAMETER here. `UOp.device_range_src` (ops.py:849) is `()`
#      unless the device is a TUPLE, and the tuple case is W2, so every ALLOC in this
#      file has NO srcs -- `row_empty23_g` (`ALLOC/0`) is the row that says so.
#   W2 mixin/creation.py:16 `_multi_like` -- `fxn` is a Python CALLBACK and the body
#      needs `shard`/`unshard`/`mstack`/`shard_shape`/`axis` (ops.py:461/692/757/773),
#      none of which is ported. `_multi_like` is the whole reason `full_like` has a
#      device-tuple arm, so `cr_full_like` is single-device and the tuple arm is a
#      `TODO(p3)`.
#   W3 mixin/dtype.py:16 `commit_dtype` -- reached TWICE, by `full`'s
#      `None if dt in dtypes.weaks else dt` (creation.py:86) and by `empty_like`'s
#      `self.commit_dtype()` (ops.py:867). It reads `UOp._min_max` (ops.py:1104), and
#      `mixin/dtype.bend`'s OWN header names that as its wall. This file does not
#      re-implement `commit_int`, `strong_dtype` or `_min_max`; it calls
#      `D.commit_dtype` and passes the two bounds in.
#      WHAT IT DOES PASS IS `fill_value` ITSELF, and that is exact rather than a
#      substitute: Python's graph here is `EXPAND(CONST v)` and `_min_max` on that is
#      the CONST arm `(self.val, self.val)` (ops.py:1160). `fill_value` IS that
#      `val`, so the bound is `cr_bounds(v)` and the fold is not needed.
#      TODO(p3) mixin/creation.py:83  `full` with a `fill_value` that is a UOp -- then
#        `dt` is `fill_value.dtype` and the bounds really are `UOp._min_max` over an
#        arbitrary graph. `cr_bounds` refuses it, and a refusal here is a
#        `void`-typed ALLOC rather than a wrong int width, which is what
#        `ref_commit_none` states.
#   W4 mixin/movement.py:149 `expand` -- `_broadcast_to` (movement.py:128) calls
#      `broadcast_axes` (ops.py:89), which calls `resolve` on a `Sint`. That is
#      `mixin/op.bend`'s W3 wall reached from a THIRD direction (op.bend already names
#      it under W7, `normalize` -> `_broadcast_to`), and the same todo.
#      WHAT IS PORTED IS THE SPECIAL CASE, AND IT IS THE ONLY CASE `creation.py`
#      REACHES. `full`'s source is ALWAYS a 0-dim CONST, so `self.shape` is `()`,
#      `_align_left` gives all 1s, `broadcast_axes((), ds)` is `range(len(ds))`, so
#      `n_left == len(ds)` and every added axis is `< n_left`, so `expand_at` is EMPTY,
#      `kept` is empty, `squeezed = self.reshape(())` is `self` (its shape already
#      matches, movement.py:187), `perm` is `range(len(ds))`, and `permute` returns
#      `self` on an identity order (movement.py:229). ONE `_mop(Ops.EXPAND, ds)` and
#      nothing else. `row_full_nobuf_g` and `row_full4i7_g` are what say so, and the
#      `_broadcast_to` they skip is named here so nobody reads the one line as the
#      whole of `expand`.
#      TODO(p3) mixin/movement.py:128  `_broadcast_to` for a source that is NOT
#        0-dim. Note `const_like` is NOT one of them: it reads `self._shape`
#        (ops.py:605) directly and never goes through `_broadcast_to`.
#
# ---------------------------------------------------------------------------
# FIVE BEND FACTS THIS FILE LEARNS, each of which cost a cycle or a wrong answer.
#
#   1. THE ARENA IS THE PORT'S `UOpMetaClass.ucache`, AND THE INTERNING GATE IS THE
#      ONLY THING THAT CAN SEE IT. Python interns on `(op, src, arg, tag, type(arg))`
#      against a process-wide dict, so a second `Tensor.full((2,3), 42)` re-uses the
#      CONST, the STACK and the EXPAND and mints ONLY the ALLOC/RESHAPE/STORE/AFTER
#      (the ALLOC's slot moved). Both graphs have a NINE-node toposort, so every
#      `row_*` row is blind to it; `int_full_new=4` is the row, and M4 is the mutation
#      that moves it.
#   2. `UOp.const(b, dtype)` (ops.py:632-638) IS A CONST PLUS A CAST THAT FOLDS AT
#      EXACTLY THREE DTYPES. `UOp(Ops.CONST, arg=dtype.const(b))` derives the CONST's
#      dtype from the VALUE (`dtype_from_uop`, ops.py:183-189), so `half.const(42)` is
#      the float `42.0` and the CONST is weakfloat and `.cast(half)` is a real CAST;
#      `weakint.const(42)` is the int `42`, the CONST is weakint, and `.cast(weakint)`
#      folds. So `full(shape, 42)` is 9 nodes and `full(shape, 42, dtype=half)` is 10,
#      and the ONLY difference is one CAST -- same root op, same nsrc, same srcs.
#      `weak.bend`'s `wk_const_at` (weak.bend:401) spells the CAST UNCONDITIONALLY and
#      is the wrong shape here, and `wk_ccast` is the other wrong shape: it rebuilds
#      the CONST and loses the CAST entirely. `cr_cast` is `DTypeMixin.cast`
#      (dtype.py:36) with the fold, which is the only one of the three that is right.
#   3. `full(shape, 0.0, dtype=int32)` CONSTS AN INT, NOT A FLOAT. `DType.const`
#      (dtype.py:79-84) truncates, `int(truncate[int32](0.0))` is `0`, an `int`, and
#      `from_py` reads the VALUE -- so `zeros(2,3,dtype=int32)` has an INT CONST cast
#      to int32 (10 nodes) where `zeros(2,3)` has a FLOAT CONST (9). The truncation
#      is P3 (dtype.py:84, and ops.bend's own `UOp.const` TODO), so `cr_full`'s
#      `fill_value` is the ALREADY-TRUNCATED `O.Const` and `cr_zeros_i` passes
#      `MO.mo_ki(0)`. That is CPython's own answer, which is why `row_zeros23i_g` is a
#      row and not a restatement.
#      TODO(p3) dtype.py:84  `DType.const`'s `truncate`.
#   4. `u.reshape(max_shape).shrink_to(new_shape)` (creation.py:42) IS AN ALLOC AND A
#      CONDITIONAL RESHAPE, and `shrink_to` CONTRIBUTES NOTHING. `reshape`'s identity
#      test is `ret.shape == self.shape` (movement.py:187) and an ALLOC's shape is
#      `(size,)` (ops.py:362; fold.bend's `param_ds`), so the test is
#      `max_shape == [size]`: FALSE for two or more dims, TRUE for `(4,)`. That is why
#      `row_empty4_g` is ONE node and `row_empty23_g` is five. After the reshape
#      `u.shape` IS `new_shape`, `shrink_to` builds `_mop(SHRINK, ((0,n0),(0,n1)))`
#      and then returns `self` because `ret.shape == self.shape` (movement.py:204).
#      Spelling it would add a SHRINK node to every `empty` row and CPython has none.
#   5. A `Maybe` IS AFFINE, SO IT CANNOT BE A FOLD'S ACCUMULATOR -- and the FIELD half of
#      the old claim was FALSE. MEASURED: 20 in-tree `type ... is Data` records carry 38
#      `Maybe` fields (`LAWS/spec.bend`'s `Sp` has three), so a `Data` record holds a
#      `Maybe` fine and the note it cites says only ACCUMULATOR. Whether `+` can be spelled
#      on a `Maybe` FIELD is not tested either way here -- the accumulator rule does not
#      decide it. What survives is the affinity, so the
#      `dtype=None` that threads `full` -> `empty_like` -> `commit_dtype` crosses as
#      its RESOLVED `S.Dt` plus the two `Maybe` bounds SEPARATELY (`cr_committed`).
#      `D.commit_dtype`'s own signature already wants them separately, so this costs
#      nothing and is not a workaround.
#   6. `argfix(*shape)` (helpers.py:24) COLLAPSES `empty(2,3)` and `empty((2,3))` into
#      one shape and REJECTS `empty((2,3),4)`. So the shape is ONE `List<&2, U32>` in
#      this port and the "one or many args" split is gone; the reject has no Bend form
#      and is a caller's problem, which is stated rather than faked.
#
# ---------------------------------------------------------------------------
# THE GATE. `main` prints one row per claim and NOTHING IS EXECUTED: every row is the
# signature of the lazy graph, which needs no device. ONE COMMAND, THREE LANES, and it
# runs `--check-only` first because that is the fastest way to find a proof failure:
#
#   sh $ORACLE_DIR/cr-gate.sh      # ALL PROOFS CHECK + 66 shared rows + 3 lanes identical
#
# The oracle is `$ORACLE_DIR/cr-truth.py` and the mutation driver is
# `$ORACLE_DIR/cr-mutate.py`; `$ORACLE_DIR` is outside the tree because the brief makes
# `.agents/` append-only for this unit and nothing else in it mine.
#
#   .venv/bin/python $ORACLE_DIR/cr-truth.py                     > /tmp/py.txt
#   ./bin/bend tinybendygrad/mixin/creation.bend                 > /tmp/bd.txt
#   ./bin/bend tinybendygrad/mixin/creation.bend -o /tmp/bn && /tmp/bn > /tmp/bn.txt
#   diff /tmp/py.txt /tmp/bd.txt && diff /tmp/py.txt /tmp/bn.txt
#
# SIX KINDS OF ROW, because six kinds of bug are invisible to the others.
#
#   <n>_g  THE FOUR FACTS IN ONE STRING -- node count, root op, root nsrc and the
#          ROOT'S SRC OP SEQUENCE -- and then the whole toposort. The sequence is the
#          load-bearing part and `cr_srcops` is a SEPARATE walk from the toposort for
#          exactly that. MEASURED, and it is the table's headline: mutation M1 reverses
#          the STORE's two srcs and moves EXACTLY ONE of 67 rows, because the root op,
#          the nsrc, the root's src op SEQUENCE and the toposort all print identically
#          either way. `int_full_expand` is the row that sees it and the only row in
#          this file that is about an INDEX rather than a shape or a count.
#   <n>_d  shape and dtype, read off the FOLD (`F.fold.shape` / `F.fold.dt`), not off
#          the construction. AFTER is `thru0` (fold.bend:1565) and RESHAPE is
#          `reshape_ds`, so every `full`'s shape comes back THROUGH THE AFTER even
#          though its EXPAND is unanswerable (fold.bend:1629).
#   <n>_t  THE DTYPE HALF ONLY, for the two EXPAND-rooted fixtures. `GroupOp.Movement`
#          gives `src[0].dtype`, so the dtype is answerable; the SHAPE is the EXPAND's
#          own arg and fold.bend:1629 answers `None{}` for it. The shape of an
#          EXPAND-rooted tensor is W3's wall and is NOT GATED, and saying so is the
#          point of the row name.
#   int_*  THE INTERNING ROWS: how many of the SECOND equal call's nodes are not the
#          FIRST's, and whether the node that must be shared IS. The only rows that can
#          see rule 1 of the header, and the only rows that would notice M4.
#   ref_*  `empty` raises on a weak dtype (creation.py:37) and a pure Bend def cannot
#          raise, so the row is `dt in dtypes.weaks` -- creation.py:37's own guard, and
#          CPython's oracle is asked that predicate rather than this port's behaviour.
#          `ref_commit_none` is the ONE BEND-ONLY row (the port refuses a weakint node
#          with no bounds and CPython answers it, because Python has `UOp._min_max` and
#          this port does not) and `cr-gate.sh` filters it BY NAME.
#   alloc_*  A ParamArg's `bind_on_realize` and `addrspace`, read off `RESHAPE.src[0]`.
#          They exist because mutation M5 moved NOTHING before they did, and their
#          expectations are CPython's own.
#   ctrl_* A CONTROL: the same fixture built twice. It must be byte-identical to the
#          first, which is what makes the lane diff a diff rather than a comparison.
#
# THE MUTATION TABLE is at the FOOT of this file, with the five things it says that
# "67 green rows" does not.
# ===========================================================================

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../tensor.bend as T
import ./dtype.bend as D
import ./op.bend as MO

# ===========================================================================
# THE CONST HELPERS -- `dtypes.from_py` (dtype.py:100) and `UOp.const` (ops.py:632).
# ===========================================================================

# `dtypes.from_py(x)` for the four py CONST values this file builds: `InvalidType` and
# `bool` are bool, `float` is weakfloat, `int` is weakint -- "order matters: bool is an
# int subclass" (ops.py:184). The list/tuple arm (dtype.py:106) is `UOp.stack`
# (ops.py:635) and no constructor in this file reaches it.
def cr_from_py(v: O.Const) -> S.Dt:
  match v:
    case O.CInvalid{}: S.boolean()
    case O.CBool{b}:   S.boolean()
    case O.CFloat{f}:  S.weakfloat()
    case _:            S.weakint()

# `(self._uop.vmin, self._uop.vmax)` for the graph `full` builds, which is one CONST
# and one EXPAND: ops.py's CONST arm is `(self.val, self.val)` (ops.py:1160) and the
# EXPAND is `src[0]._min_max` (ops.py:1166). `None` for the other three values, which
# is `commit_dtype`'s own refusal (dtype.bend's `commit_dtype.weak`) and which is
# unreachable in `full`'s weak arm: a weakint `dt` forces a `CInt` value (fact 3), and
# a weakfloat `dt` never reaches `commit_int`. See the header's W3.
def cr_bounds(v: O.Const) -> Maybe<&1, H.I64>:
  match v:
    case O.CInt{i}: Some{i}
    case _:         None{}

# `DTypeMixin.cast` -- dtype.py:36, `self if self.dtype == (dt := to_dtype(dtype)) else
# self._uop.alu(Ops.CAST, arg=dt)`. `O.UOp.alu` takes no arg (ops.bend:2072), so the
# CAST is spelled with `UOp.new` and the `ADt` arg -- `mixin/dtype.bend`'s `cast_at`
# (dtype.bend:309) and `weak.bend`'s `wk_cast_at` (weak.bend:391) use the same SPELLING
# for a different REASON: both of those read the source dtype off a FOLD, and
# `UOp.const`'s `.cast` reads it off the value it just built, which `cr_from_py` has
# already answered. Same one line, two sources for the `same` test.
def cr_cast(same: Bool, +t: T.Tensor, +dt: S.Dt) -> T.Tensor:
  match same:
    case True{}: t
    case _: +f = O.UOp.new(T.Tensor.ar(t), O.OpsCAST{}, [T.Tensor.u(t)], O.ADt{dt}, O.TNone{})
             T.tn_new(O.Found.ar(f), O.Found.i(f))

# `UOp.const` -- ops.py:632-638, `UOp(Ops.CONST, arg=dtype.const(b), src=()).cast(dtype)`.
# `dtype.const`'s truncation is P3 (fact 3 of the header), so `v` is the value AFTER it.
def cr_const_of(+ar: O.Arena, +v: O.Const, +dt: S.Dt) -> T.Tensor:
  +c0 = cr_from_py(v)
  cr_cast(D.md_dt_eq(c0, dt), T.tn_const(ar, v), dt)

# `shape_to_shape_arg`'s `UOp.const(x)` per dim (tinygrad/uop/ops.py:105). `T.tn_mop`'s `ADims{ds}`
# takes the CONSTS rather than the ints, and `tn_mop.dims` interns them in the arena it
# then builds the node in -- so the order is CONST-then-node, which is what CPython's
# own toposort prints.
def cr_cdims.go(ds: List<&2, U32>, acc: List<&2, O.Const>) -> List<&2, O.Const>:
  List.foldl(~&2, ~U32, ~List<&2, O.Const>, (a: List<&2, O.Const>) => (d: U32) => List.append(&2, O.Const, a, [MO.mo_ki(d)]), ds, acc)

def cr_cdims(ds: List<&2, U32>) -> List<&2, O.Const>: cr_cdims.go(ds, Nil{})

# `UOp._mop(Ops.RESHAPE|Ops.EXPAND, arg)` -- ops.py:826-827 + :835 -- for the ONE arg
# shape (`src_args = [arg]`), which is the only movement op this file builds.
def cr_mop(+t: T.Tensor, +op: O.Op, ds: List<&2, U32>) -> T.Tensor:
  T.tn_alu.put(T.tn_mop(T.Tensor.ar(t), T.Tensor.u(t), op, T.ADims{cr_cdims(ds)}))

# `expand` -- movement.py:149 -- for `full`'s 0-dim source; see the header's W4 for the
# whole reduction. `T.tn_mop` supplies ops.py:823's early NOOP (`if op is Ops.EXPAND
# and len(arg) == 0: return self`), so `full((), 42, buffer=False)` is the bare CONST,
# which is CPython's own answer.
def cr_expand(+t: T.Tensor, ds: List<&2, U32>) -> T.Tensor: cr_mop(t, O.OpsEXPAND{}, ds)

# `ret._uop.after(ret._uop.store(val._uop))` -- creation.py:87. `store` is
# `UOp(Ops.STORE, src=(self,)+src)` (ops.py:616) and `after` is
# `UOp(Ops.AFTER, src=(self,)+src)` (ops.py:621). THE STORE IS INTERNED INTO A `let`
# FIRST: an argument is evaluated before the callee branches, so spelling the STORE
# inline inside the AFTER's src list interns it into a COPY and the AFTER names the
# node the STORE is about to occupy. That is movement.bend's rule 11 and it is silent.
def cr_after(+r: T.Tensor, +v: T.Tensor) -> T.Tensor:
  +s = O.UOp.new(T.Tensor.ar(r), O.OpsSTORE{}, [T.Tensor.u(r), T.Tensor.u(v)], O.ANone{}, O.TNone{})
  T.tn_alu.put(O.UOp.new(O.Found.ar(s), O.OpsAFTER{}, [T.Tensor.u(r), O.Found.i(s)], O.ANone{}, O.TNone{}))

# ===========================================================================
# creation.py:12 `const` is a `raise NotImplementedError` and is NOT a def here; see
# the TODO in the header. creation.py:23 `empty` is the first body.
# ===========================================================================

# `ParamArg(next(UOp.unique_num), dt, prod(max_shape), device=dev,
# bind_on_realize=True)` -- creation.py:41. The thirteen fields are `ops.bend`'s
# `ParamArg` in ITS order (ops.bend:696-712), which is NOT the prose order: `addrspace`
# is the eighth field and `device` the ninth. `bind_on_realize` is the ALLOC's one
# difference from a BUFFER (creation.py:41 vs ops.py:852) and it is `True`.
def cr_alloc.arg(slot: U32, +dt: S.Dt, size: U32, dev: S.Dev) -> O.ParamArg:
  O.ParamArg{slot, dt, Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{dev},
    False{}, None{}, None{}, True{}, None{}}

# `next(UOp.unique_num)` -- ops.py:1208 -- is a MONOTONE slot counter that "must never be
# reset", and `ops.bend:940` says the arena's length IS that counter. `Arena.next` on
# the arena the ALLOC is about to be interned into is therefore this port's
# `next(UOp.unique_num)`, and it is WHAT MAKES TWO `full`s NOT SHARE AN ALLOC. CPython
# says so (`int_full_new=4`) and no `row_*` row can see it, because both graphs are
# nine nodes. It is also why `Arena.next` is not a containment test
# (movement.bend, "arena.next is NOT a containment test"): it is a NAME, and here the
# name is only ever compared for EQUALITY.
def cr_alloc(+ar: O.Arena, +dt: S.Dt, size: U32, dev: S.Dev) -> T.Tensor:
  T.tn_alu.put(O.UOp.new(ar, O.OpsALLOC{}, Nil{}, O.AParam{cr_alloc.arg(O.Arena.next(ar), dt, size, dev)}, O.TNone{}))

# `ret.shape == self.shape` for the `reshape(max_shape)` of creation.py:42, where
# `ret.shape` is `max_shape` and an ALLOC's shape is `(size,)` -- `param_ds`,
# ops.py:362, which fold.bend ports. So the test is `ds == [size]`, and it is the only
# guard `empty`'s reshape has.
def cr_resh.same.of(ds: List<&2, U32>, size: U32) -> Bool:
  match ds:
    case Nil{}: False{}
    case d <> t: Bool.and(U32.is_eq(d, size), List.is_empty(&2, U32, t))

def cr_resh.same(+ds: List<&2, U32>, size: U32) -> Bool: cr_resh.same.of(ds, size)

# `u.reshape(max_shape).shrink_to(new_shape)` -- creation.py:42 -- and the SECOND HALF
# CONTRIBUTES NOTHING; fact 4 of the header has the derivation. Spelling it would add a
# SHRINK node to every `empty` row and CPython has none.
def cr_resh(keep: Bool, +t: T.Tensor, ds: List<&2, U32>) -> T.Tensor:
  match keep:
    case True{}: t
    case _: cr_mop(t, O.OpsRESHAPE{}, ds)

# `empty` -- creation.py:23-43. `dt` is ALREADY `to_dtype(dtype) if dtype is not None
# else dtypes.default_float` (creation.py:36) and `max_shape` is already
# `to_max_shape(new_shape)` (creation.py:39), which for a concrete shape is the shape.
# The weak-dtype refusal (creation.py:37) is NOT HERE: a pure Bend def cannot raise, so
# `cr_empty` is never GIVEN the option -- `ref_empty_weak` states the refusal and W1's
# neighbour names it. `ar` is threaded rather than `O.Arena.empty()`ed because the
# arena IS the port's `UOpMetaClass.ucache` (rule 1 of the header): Python's `empty`
# interns against every UOp ever built, and `int_empty_new=5` is the row that says the
# port's does too.
def cr_empty(+ar: O.Arena, dt: Maybe<&1, S.Dt>, +ds: List<&2, U32>, dev: S.Dev) -> T.Tensor:
  +a = cr_alloc(ar, Maybe.default(&1, S.Dt, dt, S.void()), H.prod_u32(ds), dev)
  cr_resh(cr_resh.same(ds, H.prod_u32(ds)), a, ds)

# ===========================================================================
# creation.py:14 `const_like`.
# ===========================================================================

# `self._wrap_uop(self._uop.const_like(b, dtype))` -- creation.py:14 -- which is
# ops.py:603-605:
#
#   ret = UOp.const(b, dtype or self.dtype)
#   return ret._mop(Ops.EXPAND, arg=self._shape) if self._shape and ret._shape != self._shape else ret
#
# `ret._shape` is `()` for a CONST (ops.py:361) and for a CAST of a CONST (ops.py:439),
# so `ret._shape != self._shape` IS `bool(self._shape)` and the whole two-part condition
# is ONE test: is `self`'s shape non-empty. `self._shape` is the dim LIST, so this is
# the SAME `_mop(Ops.EXPAND, ...)` `full` makes -- which is why `row_constlike2d_g`
# and `row_full_nobuf_g` differ by exactly one CAST and nothing else, and why there is
# no `_broadcast_to` on this path at all.
# THE `.of` SPLIT IS NOT OPTIONAL: `+c` is bound before the `match` and a `match` kills
# every name bound earlier in the same body, parameters and binders both (upat.bend
# rule 5). So the CONST is built by the caller and the CHOICE heads its own def.
def cr_const_like.of(nz: Bool, +c: T.Tensor, ds: List<&2, U32>) -> T.Tensor:
  match nz:
    case True{}: cr_expand(c, ds)
    case _: c

def cr_const_like(nz: Bool, +ar: O.Arena, +v: O.Const, +dt: S.Dt, +ds: List<&2, U32>) -> T.Tensor:
  cr_const_like.of(nz, cr_const_of(ar, v, dt), ds)

# ===========================================================================
# creation.py:45 `empty_like`.
# ===========================================================================

# `self.commit_dtype() if dtype is None else dtype` -- ops.py:867 -- as a
# `Maybe<&1, S.Dt>`, because that is Python's `None` and `commit_dtype` (dtype.py:16)
# ANSWERS one. `commit_int`, `strong_dtype` and `commit_dtype` are `mixin/dtype.bend`'s
# and are CALLED. `given` is `dtype is not None`, `self_dt` is `self.dtype` for the
# commit, and `m`/`m2` are `self.vmin`/`self.vmax` -- W3's wall, as two `Maybe`s.
def cr_committed.of(given: Bool, +dt: S.Dt, +self_dt: S.Dt, m: Maybe<&1, H.I64>, m2: Maybe<&1, H.I64>) -> Maybe<&1, S.Dt>:
  match given:
    case True{}: Some{dt}
    case _:      D.commit_dtype(self_dt, m, m2, S.int32())

def cr_committed(given: Bool, +dt: S.Dt, +self_dt: S.Dt, m: Maybe<&1, H.I64>, m2: Maybe<&1, H.I64>) -> Maybe<&1, S.Dt>:
  cr_committed.of(given, dt, self_dt, m, m2)

# `self._uop.empty_like(dtype, device)` -- creation.py:50, which is ops.py:864-869:
# `axis` is `None` for a single device, so it answers `UOp.empty(self.shape, dtype=
# self.commit_dtype() if dtype is None else dtype, device=device)` -- and `UOp.empty`
# IS `CreationMixin.empty`. So `cr_empty_like` is `cr_empty` with the dtype resolved
# and the two are one def.
def cr_empty_like(+ar: O.Arena, given: Bool, +dt: S.Dt, +self_dt: S.Dt, m: Maybe<&1, H.I64>, m2: Maybe<&1, H.I64>, +ds: List<&2, U32>, dev: S.Dev) -> T.Tensor:
  cr_empty(ar, cr_committed.of(given, dt, self_dt, m, m2), ds, dev)

# ===========================================================================
# creation.py:64 `full`. IT IS BEFORE `invalids` IN PYTHON AND AFTER IT HERE, and
# that is the ONLY reordering in this file: a def may only call a def declared ABOVE it
# (`bend2-constraints` 1.1) and `invalids` IS `full` (creation.py:61). `cr_invalids`
# therefore sits one def below its own caller, which is the same reorder op.bend makes
# for `_mop` and `_reduce`.
# ===========================================================================

def cr_full.of(buf: Bool, +val: T.Tensor, +e: T.Tensor) -> T.Tensor:
  match buf:
    case True{}: cr_after(e, val)
    case _: val

# `full` -- creation.py:64-87, the def the CE loss and every `zeros`/`ones` are built
# FROM. `dt` is already resolved (creation.py:83: `to_dtype(dtype)` if given, else
# `fill_value.dtype` for a UOp, else `dtypes.from_py(fill_value)` -- and the last is
# `cr_from_py`, which is why `cr_zeros`/`cr_ones` do not name it). `v` is `fill_value`
# after `dtype.const`'s truncation (fact 3). `buf` is `buffer` (creation.py:65).
# THE `dt in dtypes.weaks` TEST (creation.py:86) LIVES HERE, as `Bool.not(D.md_weak(dt))`
# handed to `cr_empty_like`, because a `match` may not scrutinise a call.
# `cr_empty_like` IS HANDED `Tensor.ar(val)` AND NOT `ar`, and that is the arena rule
# (elementwise.bend's header, "two builds from the same base produce SIBLING arenas"):
# `val` is built first and its arena is the one that must contain the ALLOC. Passing
# `ar` on would intern the ALLOC into a store with no CONST, no STACK and no EXPAND, and
# every `int_full_new` row would move.
def cr_full(buf: Bool, +ar: O.Arena, +v: O.Const, +dt: S.Dt, +ds: List<&2, U32>, dev: S.Dev) -> T.Tensor:
  +c0 = cr_from_py(v)
  +val = cr_expand(cr_const_of(ar, v, dt), ds)
  cr_full.of(buf, val, cr_empty_like(T.Tensor.ar(val), Bool.not(D.md_weak(dt)), dt, c0,
    cr_bounds(v), cr_bounds(v), ds, dev))

# `cls.full(argfix(*shape), Invalid, dtype=dtype, device=device)` -- creation.py:61 --
# and `dtypes.from_py(Invalid)` is bool (dtype.py:102, ops.py:185), so
# `Tensor.invalids(2,3)` is the `full` of a bool CONST and `invalids23_d=dtypes.bool`
# says so. `Invalid` IS an `O.CInvalid` here, which `cr_from_py` gives bool.
def cr_invalids(+ar: O.Arena, +ds: List<&2, U32>, dev: S.Dev) -> T.Tensor:
  cr_full(True{}, ar, O.CInvalid{}, S.boolean(), ds, dev)

# ===========================================================================
# creation.py:89 `full_like`, creation.py:108 `zeros`, :124 `zeros_like`, :138 `ones`,
# :154 `ones_like`. FOUR DEFS AND NO NEW LOGIC: `full_like` is `full` on `self.shape`
# with `dtype or self.dtype` (creation.py:105) and `zeros`/`ones` are `full` with a
# literal (creation.py:122/152), and both `*_like` are `full_like` with a literal
# (creation.py:135/165).
# ===========================================================================

# `type(self).full(self.shape, fill_value, dtype=dtype or self.dtype, device=..., buffer=
# buffer)` -- creation.py:105. The device-tuple arm is W2 and is a `TODO(p3)` in the
# header.
# TODO(p3) mixin/creation.py:102-104  full_like's multi-device arm -- `_multi_like` (W2).
def cr_full_like(+ar: O.Arena, +v: O.Const, +dt: S.Dt, buf: Bool, +ds: List<&2, U32>, dev: S.Dev) -> T.Tensor:
  cr_full(buf, ar, v, dt, ds, dev)

# `cls.full(argfix(*shape), 0.0, **kwargs)` -- creation.py:122.
def cr_zeros(+ar: O.Arena, v: O.Const, +dt: S.Dt, +ds: List<&2, U32>, dev: S.Dev) -> T.Tensor:
  cr_full(True{}, ar, v, dt, ds, dev)

# `self.full_like(0, **kwargs)` -- creation.py:135. `dtype or self.dtype` with `dtype`
# unset is `self.dtype`, so `dt` IS the tensor's own dtype and a float32 receiver gets
# a CONST int CAST to float32 -- `row_zeros_like2d_g` is 9 nodes with that CAST, and
# `row_zeros23_g` is 9 nodes with a float CONST, so the two look alike in COUNT and are
# not alike in the source sequence. That is why both are rows.
def cr_zeros_like(+ar: O.Arena, +self_dt: S.Dt, +ds: List<&2, U32>, dev: S.Dev) -> T.Tensor:
  cr_full_like(ar, MO.mo_ki(0), self_dt, True{}, ds, dev)

# `cls.full(argfix(*shape), 1.0, **kwargs)` -- creation.py:152.
def cr_ones(+ar: O.Arena, v: O.Const, +dt: S.Dt, +ds: List<&2, U32>, dev: S.Dev) -> T.Tensor:
  cr_full(True{}, ar, v, dt, ds, dev)

# `self.full_like(1, **kwargs)` -- creation.py:165.
def cr_ones_like(+ar: O.Arena, +self_dt: S.Dt, +ds: List<&2, U32>, dev: S.Dev) -> T.Tensor:
  cr_full_like(ar, MO.mo_ki(1), self_dt, True{}, ds, dev)

# ===========================================================================
# THE GATE PRINTERS.
# ===========================================================================

# A NODE INDEX THAT IS READ MORE THAN ONCE GOES IN A `Data` RECORD. `cr_g.of` reads its
# index four times and a `U32` is affine and cannot take a `+` as a parameter
# (device.bend's rule 3: the operands of a two-read `U32` expression go in a record),
# and `CU.u` is a reader so the record itself is read any number of times. THE SAME
# RECORD THEN SOLVES THREE PROBLEMS AT ONCE: the index here, `cr_new`'s node being
# counted, and `cr_store_val`'s `AFTER -> STORE -> val` descent.
type CU is Data:
  CU{u: U32}

def CU.u(c: CU) -> U32:
  match c:
    case CU{u}: u

# The ROOT's src op sequence, as `A|B|C`. THE WALK IS OVER `Arena.srcs` AND NOT OVER A
# COUNTDOWN: the first version threaded `U32.to_nat(Arena.nsrc(...))` as a `Nat` and
# read `Arena.src(ar, u, 0)` on every level, so every row printed `ALLOC|ALLOC|` for a
# two-src root. That is the `mxm_as_shape.go` class of bug -- a walk that compiles and
# reads the same slot twice -- and the FOUR-FACTS row is the only thing that sees it,
# because `nsrc=2` and the count were correct throughout.
def cr_srcops.go(+ar: O.Arena, xs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:  acc
    case v <> t: cr_srcops.go(ar, t, List.append(&2, String, acc, [O.Ops.name.of(O.Arena.op(ar, v))]))

def cr_srcops.of(+ar: O.Arena, u: U32) -> String:
  String.join(cr_srcops.go(ar, O.Arena.srcs(ar, u), Nil{}), "|")

def cr_srcops(+ar: O.Arena, u: U32) -> String: cr_srcops.of(ar, u)

# `str(self.shape)`, as Python's tuple repr: `()`, `(4)`, `(2,3)`. `MO.mo_dim_u32` is
# op.bend's decimal and is CALLED -- `T.sint_text` is `H.i64_text`, which is a `hi:lo`
# HEX PAIR and printed `0:20:3` for `(2,3)`. The join is `String.join` because the first
# version appended the separator to the TAIL's accumulator and printed `(2,3,)`, and a
# gate row whose formatting is one character off is a gate row the oracle cannot match.
# A `None` shape is fold.bend's "this fold cannot answer this node" and prints `()`,
# which is a 0-dim shape's own answer too.
def cr_dims.go(ds: List<&2, O.Sint>, acc: List<&2, String>) -> List<&2, String>:
  List.foldl(~&2, ~O.Sint, ~List<&2, String>, (a: List<&2, String>) => (d: O.Sint) => List.append(&2, String, a, [U32.show(MO.mo_dim_u32(d))]), ds, acc)

def cr_dims(ds: List<&2, O.Sint>) -> String: String.concat(["(", String.join(cr_dims.go(ds, Nil{}), ","), ")"])

# The toposort's own half, `OP/n OP/n ...`. IT IS NOT `MO.mo_sig.go` AND THE REASON IS
# A TRAILING SPACE. That shared printer emits `" "` after every node, so a row built from
# it ends in a space, and the CPython oracle then has to `rstrip()` to match -- a
# formatting asymmetry in a byte-diffed gate is exactly the sort of thing that hides a
# real difference on the day somebody changes one side. Four lines and the row is
# readable.
def cr_one.of(ar: O.Arena, nm: String, n: String) -> String: String.concat([nm, "/", n])

def cr_one(+ar: O.Arena, +c: CU) -> String:
  cr_one.of(ar, O.Ops.name.of(O.Arena.op(ar, CU.u(c))), U32.show(O.Arena.nsrc(ar, CU.u(c))))

def cr_topo.go(xs: List<&2, U32>, +ar: O.Arena, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:  acc
    case u <> t: cr_topo.go(t, ar, List.append(&2, String, acc, [cr_one(ar, CU{u})]))

def cr_topo(xs: List<&2, U32>, +ar: O.Arena) -> String:
  String.join(cr_topo.go(xs, ar, Nil{}), " ")

# `<n>_g=<count> op=<ROOT> nsrc=<k> srcops=<a|b|c> topo=<OP/n OP/n ...>` -- FOUR FACTS
# IN ONE STRING, THEN THE TOPOSORT. One walk of the srcs and one of the graph.
def cr_g.of(nm: String, +ar: O.Arena, +c: CU, +xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(U32.from_nat(List.length(&2, U32, xs))), " op=",
    O.Ops.name.of(O.Arena.op(ar, CU.u(c))), " nsrc=", U32.show(O.Arena.nsrc(ar, CU.u(c))),
    " srcops=", cr_srcops(ar, CU.u(c)), " topo=", cr_topo(xs, ar)]))

# `full`'s root is an AFTER, AND THE FOLD CANNOT ANSWER AN AFTER WHOSE GRAPH CONTAINS
# AN EXPAND. MEASURED, `probe_fold.bend` over `full((2,3),42)`: nodes 1..6 (ALLOC,
# CONST, CONST, STACK, RESHAPE, CONST) resolve for both dtype and shape, node 7 (EXPAND)
# resolves for NEITHER, and 8 (STORE) and 9 (AFTER) resolve for NEITHER either --
# fold.bend:1629's `Ops.EXPAND` arm answers `None{}`, and an unresolved node never
# releases its consumers in the Kahn worklist. That is W3's wall (the EXPAND's `marg`
# needs `ssimplify`) and it is the SAME one op.bend names.
# SO THE `_d` ROW READS `AFTER.src[0]`, which is exactly what `thru0` (fold.bend:726)
# would have returned for the AFTER -- `dt_of(src_dt(0), src_shape(0))` -- and is the
# node the fold DOES answer. `full`'s shape and dtype are therefore gated, and the only
# part that is not gated is whether the AFTER passes src[0] through, which is a line of
# fold.bend and not of this file.
def cr_d_root.of(+ar: O.Arena, +c: CU, after: Bool) -> CU:
  match after:
    case True{}: CU{O.Arena.src(ar, CU.u(c), 0)}
    case _: c

def cr_d_root(+ar: O.Arena, +c: CU) -> CU:
  cr_d_root.of(ar, c, O.eq_op(O.Arena.op(ar, CU.u(c)), O.OpsAFTER{}))

# `<n>_d=shape=(2,3) dtype=<name>` off the FOLD. `MO.mo_dims` is `F.fold.shape` unwrapped
# and `T.tn_repr.dt` is `F.fold.dt` unwrapped; both are CALLED, and this is the row that
# catches a shape arg built in the wrong direction (movement.bend's rule 15: `STACK(8,8,4,1)`
# for `[1,4,8,8]` had the right COUNT, the right root op and the right nsrc).
def cr_d.put(nm: String, sh: String, dt: String) -> IO(Unit):
  IO.print(String.concat([nm, "=shape=", sh, " dtype=", dt]))

def cr_d.of(nm: String, +ar: O.Arena, +c: CU) -> IO(Unit):
  cr_d.put(nm, cr_dims(MO.mo_dims(F.folded(ar), CU.u(cr_d_root(ar, c)))),
    T.dt_name(T.tn_repr.dt(T.tn_new(ar, CU.u(cr_d_root(ar, c))))))

# `<n>_t=dtype=<name>` -- THE DTYPE HALF ONLY, AND IT EXISTS BECAUSE OF W3.
#
# `GroupOp.Movement` gives `src[0].dtype`, so an EXPAND-rooted tensor's DTYPE is its
# source's and the fold answers it. Its SHAPE is not `src[0].shape` -- it is the EXPAND's
# own arg -- and fold.bend:1629 answers `None{}` for it, so the shape half is NOT GATED
# for `full(..., buffer=False)` or for `const_like` on a non-empty shape. Those rows say
# so rather than printing a shape fold.bend cannot produce.
def cr_t_root.of(+ar: O.Arena, +c: CU, after: Bool, exp: Bool) -> CU:
  match after exp:
    case True{}  _       : CU{O.Arena.src(ar, CU.u(c), 0)}
    case False{} True{}  : CU{O.Arena.src(ar, CU.u(c), 0)}
    case False{} False{} : c

def cr_t_root(+ar: O.Arena, +c: CU) -> CU:
  cr_t_root.of(ar, c, O.eq_op(O.Arena.op(ar, CU.u(c)), O.OpsAFTER{}),
    O.eq_op(O.Arena.op(ar, CU.u(c)), O.OpsEXPAND{}))

def cr_t.of(nm: String, +ar: O.Arena, +c: CU) -> IO(Unit):
  IO.print(String.concat([nm, "=dtype=", T.dt_name(T.tn_repr.dt(T.tn_new(ar, CU.u(cr_t_root(ar, c)))))]))

# One toposort, two rows -- or three, for the EXPAND-rooted fixtures, whose shape the
# fold cannot reach. The fixture builders are one line each and this is the only place a
# graph is walked.
def cr_row.of(+nm: String, +ar: O.Arena, +c: CU, +xs: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    cr_g.of(String.concat([nm, "_g"]), ar, c, xs)
    cr_d.of(String.concat([nm, "_d"]), ar, c)

def cr_row(nm: String, +t: T.Tensor) -> IO(Unit):
  cr_row.of(nm, T.Tensor.ar(t), CU{T.Tensor.u(t)},
    O.UOp.toposort(O.Arena.budget(T.Tensor.ar(t)), T.Tensor.ar(t), T.Tensor.u(t)))

def cr_rowt.of(+nm: String, +ar: O.Arena, +c: CU, +xs: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    cr_g.of(String.concat([nm, "_g"]), ar, c, xs)
    cr_t.of(String.concat([nm, "_t"]), ar, c)

def cr_rowt(nm: String, +t: T.Tensor) -> IO(Unit):
  cr_rowt.of(nm, T.Tensor.ar(t), CU{T.Tensor.u(t)},
    O.UOp.toposort(O.Arena.budget(T.Tensor.ar(t)), T.Tensor.ar(t), T.Tensor.u(t)))

# ===========================================================================
# THE INTERNING ROWS. `u is v` in CPython is `U32.is_eq(u, v)` here, because a UOp IS
# an arena index and ops.bend:940 says the index is the identity. `cr_in` is the walk
# `any(u is v for v in a)`, and `CU` is the record the header's `cr_srcops.go` needed.
# ===========================================================================
def cr_in.go(+ar: O.Arena, +c: CU, xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:  False{}
    case v <> t: Bool.or(U32.is_eq(CU.u(c), v), cr_in.go(ar, c, t))

def cr_in(+ar: O.Arena, u: U32, xs: List<&2, U32>) -> Bool: cr_in.go(ar, CU{u}, xs)

def cr_new.go(+ar: O.Arena, +c: CU, xs: List<&2, U32>, +a: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case u <> t: cr_new.go(ar, c, t, a, U32.add(acc, Bool.pick(U32, Bool.not(cr_in(ar, u, a)), 1, 0)))

# `int_<nm>=<nodes b minted that a did not>` -- "how many did the SECOND equal call
# add". `sum(1 for u in b.toposort() if not any(u is v for v in a.toposort()))`.
def cr_new(+ar: O.Arena, +b: T.Tensor, +a: T.Tensor) -> U32:
  cr_new.go(T.Tensor.ar(b), CU{T.Tensor.u(b)},
    O.UOp.toposort(O.Arena.budget(T.Tensor.ar(b)), T.Tensor.ar(b), T.Tensor.u(b)),
    O.UOp.toposort(O.Arena.budget(T.Tensor.ar(a)), T.Tensor.ar(a), T.Tensor.u(a)), 0)

# `full`'s root is `AFTER(ret, STORE(ret, val))`, so the STORED value -- the CONST and
# its EXPAND -- is `AFTER.src[1].src[1]`, and THAT is the node two equal `full`s must
# share. `int_full_expand` asks the question directly instead of inferring it from a
# count.
def cr_store_val.of(+ar: O.Arena, c: CU) -> U32: O.Arena.src(ar, O.Arena.src(ar, CU.u(c), 1), 1)

# ===========================================================================
# THE FIXTURES. Every one is CPython's OWN call, listed beside it.
#
#   `cr_fx2d` is `Tensor([[1.,2.],[3.,4.]])`, which in CPython is
#   `BUFFER CONST STACK/2 RESHAPE/2` (`mo_fx2d` is op.bend's, MEASURED against
#   CPython's `toposort` in op.bend's `t_lit2d`, and it is CALLED rather than copied).
#   The DEVICE is `S.D1{0}` throughout, which is W1's parameter; CPython's default
#   device name is not printed by any row because `canonicalize_device` cannot change a
#   signature (it only reaches `ParamArg.device` and `device_range_src`).
# ===========================================================================
def cr_fx2d() -> T.Tensor: MO.mo_fx2d()

# --- empty (creation.py:23) and empty_like (:45)
def t_empty23() -> IO(Unit): cr_row("empty23", cr_empty(O.Arena.empty(), Some{S.single()}, [2, 3], S.D1{0}))
def t_empty23h() -> IO(Unit): cr_row("empty23h", cr_empty(O.Arena.empty(), Some{S.half()}, [2, 3], S.D1{0}))
def t_empty23i() -> IO(Unit): cr_row("empty23i", cr_empty(O.Arena.empty(), Some{S.int32()}, [2, 3], S.D1{0}))
def t_empty4() -> IO(Unit): cr_row("empty4", cr_empty(O.Arena.empty(), Some{S.single()}, [4], S.D1{0}))
def t_empty0() -> IO(Unit): cr_row("empty0", cr_empty(O.Arena.empty(), Some{S.single()}, [], S.D1{0}))
def t_emptylike2d() -> IO(Unit):
  +f = cr_fx2d()
  cr_row("emptylike2d", cr_empty_like(T.Tensor.ar(f), False{}, S.half(), S.single(), None{}, None{}, [2, 2], S.D1{0}))
def t_emptylike2dh() -> IO(Unit):
  +f = cr_fx2d()
  cr_row("emptylike2dh", cr_empty_like(T.Tensor.ar(f), True{}, S.half(), S.single(), None{}, None{}, [2, 2], S.D1{0}))

# --- invalids (creation.py:53)
def t_invalids23() -> IO(Unit): cr_row("invalids23", cr_invalids(O.Arena.empty(), [2, 3], S.D1{0}))

# --- full (creation.py:64). `42` is an int CONST at weakint, `42.0` a float at
# weakfloat, `True` a bool, and `dtype=half`/`int64` force the CAST of fact 2.
def t_full23i42() -> IO(Unit): cr_row("full23i42", cr_full(True{}, O.Arena.empty(), MO.mo_ki(42), S.weakint(), [2, 3], S.D1{0}))
def t_full23f42() -> IO(Unit): cr_row("full23f42", cr_full(True{}, O.Arena.empty(), O.CFloat{42.0}, S.weakfloat(), [2, 3], S.D1{0}))
def t_full23b() -> IO(Unit): cr_row("full23b", cr_full(True{}, O.Arena.empty(), O.CBool{True{}}, S.boolean(), [2, 3], S.D1{0}))
def t_full23h42() -> IO(Unit): cr_row("full23h42", cr_full(True{}, O.Arena.empty(), MO.mo_ki(42), S.half(), [2, 3], S.D1{0}))
def t_full23l42() -> IO(Unit): cr_row("full23l42", cr_full(True{}, O.Arena.empty(), MO.mo_ki(42), S.int64(), [2, 3], S.D1{0}))
def t_full23big() -> IO(Unit): cr_row("full23big", cr_full(True{}, O.Arena.empty(), MO.mo_ki(1048576), S.weakint(), [2, 3], S.D1{0}))
def t_full_nobuf() -> IO(Unit): cr_rowt("full_nobuf", cr_full(False{}, O.Arena.empty(), MO.mo_ki(42), S.weakint(), [2, 3], S.D1{0}))
def t_full_nobuf0() -> IO(Unit): cr_row("full_nobuf0", cr_full(False{}, O.Arena.empty(), MO.mo_ki(42), S.weakint(), [], S.D1{0}))
def t_full4i7() -> IO(Unit): cr_row("full4i7", cr_full(True{}, O.Arena.empty(), MO.mo_ki(7), S.weakint(), [4], S.D1{0}))

# --- const_like (creation.py:14) -- `nz` is "self's shape is non-empty" (ops.py:605),
# and the 0-dim half of that test needs a fixture or the arm is dead code.
def t_constlike2d() -> IO(Unit):
  +f = cr_fx2d()
  cr_rowt("constlike2d", cr_const_like(True{}, T.Tensor.ar(f), MO.mo_ki(0), S.single(), [2, 2]))
def t_constlike0d() -> IO(Unit):
  +f = cr_fx2d()
  cr_row("constlike0d", cr_const_like(False{}, T.Tensor.ar(f), O.CFloat{0.0}, S.weakfloat(), []))

# --- full_like (creation.py:89) and zeros/ones (:108/:138)
def t_full_like2d() -> IO(Unit):
  +f = cr_fx2d()
  cr_row("full_like2d", cr_full_like(T.Tensor.ar(f), MO.mo_ki(9), S.single(), True{}, [2, 2], S.D1{0}))
def t_full_like2dh() -> IO(Unit):
  +f = cr_fx2d()
  cr_row("full_like2dh", cr_full_like(T.Tensor.ar(f), O.CFloat{9.0}, S.half(), True{}, [2, 2], S.D1{0}))
def t_zeros23() -> IO(Unit): cr_row("zeros23", cr_zeros(O.Arena.empty(), O.CFloat{0.0}, S.weakfloat(), [2, 3], S.D1{0}))
def t_zeros23i() -> IO(Unit): cr_row("zeros23i", cr_zeros(O.Arena.empty(), MO.mo_ki(0), S.int32(), [2, 3], S.D1{0}))
def t_ones23() -> IO(Unit): cr_row("ones23", cr_ones(O.Arena.empty(), O.CFloat{1.0}, S.weakfloat(), [2, 3], S.D1{0}))
def t_ones23i() -> IO(Unit): cr_row("ones23i", cr_ones(O.Arena.empty(), MO.mo_ki(1), S.int32(), [2, 3], S.D1{0}))
def t_zeros_like2d() -> IO(Unit):
  +f = cr_fx2d()
  cr_row("zeros_like2d", cr_zeros_like(T.Tensor.ar(f), S.single(), [2, 2], S.D1{0}))
def t_ones_like2d() -> IO(Unit):
  +f = cr_fx2d()
  cr_row("ones_like2d", cr_ones_like(T.Tensor.ar(f), S.single(), [2, 2], S.D1{0}))

# ===========================================================================
# THE INTERNING AND REFUSAL ROWS. All in ONE arena each, which is the point: Python's
# ucache is process-wide, so `Tensor.full` twice in a row shares nodes.
# ===========================================================================
def t_intern_full() -> IO(Unit):
  +ar = O.Arena.empty()
  +a = cr_full(True{}, ar, MO.mo_ki(42), S.weakint(), [2, 3], S.D1{0})
  +b = cr_full(True{}, T.Tensor.ar(a), MO.mo_ki(42), S.weakint(), [2, 3], S.D1{0})
  +e = cr_store_val.of(T.Tensor.ar(b), CU{T.Tensor.u(b)})
  +f = cr_store_val.of(T.Tensor.ar(a), CU{T.Tensor.u(a)})
  do IO<Unit>:
    IO.print(String.concat(["int_full_new=", U32.show(cr_new(T.Tensor.ar(b), b, a))]))
    IO.print(String.concat(["int_full_expand=", Bool.show(U32.is_eq(e, f))]))

def t_intern_empty() -> IO(Unit):
  +ar = O.Arena.empty()
  +a = cr_empty(ar, Some{S.single()}, [2, 3], S.D1{0})
  +b = cr_empty(T.Tensor.ar(a), Some{S.single()}, [2, 3], S.D1{0})
  IO.print(String.concat(["int_empty_new=", U32.show(cr_new(T.Tensor.ar(b), b, a))]))

def t_intern_diff() -> IO(Unit):
  +ar = O.Arena.empty()
  +a = cr_zeros(ar, O.CFloat{0.0}, S.weakfloat(), [2, 3], S.D1{0})
  +b = cr_ones(T.Tensor.ar(a), O.CFloat{1.0}, S.weakfloat(), [2, 3], S.D1{0})
  IO.print(String.concat(["int_ones_new=", U32.show(cr_new(T.Tensor.ar(b), b, a))]))

# ===========================================================================
# THE `ALLOC` FIELD ROWS. THEY EXIST BECAUSE MUTATION M5 MOVED NOTHING.
#
# `cr_g`'s row prints op and nsrc and `cr_d`'s prints shape and dtype, and between them
# they read a ParamArg's `dtype` and `size` -- and NOTHING ELSE. M5 (`bind_on_realize`
# cleared) passed `--check-only`, ran, and moved ZERO of the 64 rows, which is wgsl.bend's
# lesson in its purest form: a field with no row is a field no mutation can find. These
# two rows read the fields off the arena, and their EXPECTATIONS ARE CPYTHON'S --
# `ParamArg(..., bind_on_realize=True)` at creation.py:41, and `addrspace` defaulting to
# `AddrSpace.GLOBAL` because `CreationMixin.empty` does not pass one -- so neither of
# them encodes the mutation that exposed the hole.
def cr_alloc_pa.of(a: O.Arg) -> O.ParamArg:
  match a:
    case O.AParam{pa}: pa
    case _: O.ParamArg.of(0, S.void())

def cr_alloc_pa(+ar: O.Arena, n: U32) -> O.ParamArg: cr_alloc_pa.of(O.Arena.arg(ar, n))

def cr_bl(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))

# `c` is the ALLOC's index, which the caller reaches as `RESHAPE.src[0]` -- `empty`'s
# root IS the reshape over the alloc (creation.py:42) whenever the reshape was not a
# no-op, and `empty4` is the row that says when it is.
def cr_alloc_rows(+ar: O.Arena, +c: CU) -> IO(Unit):
  do IO<Unit>:
    cr_bl("alloc_bind", O.ParamArg.bind_on_realize(cr_alloc_pa(ar, CU.u(c))))
    cr_bl("alloc_addr", O.eq_addr(O.ParamArg.addrspace(cr_alloc_pa(ar, CU.u(c))), S.AGlobal{}))

# THE `ref_*` ROWS ASK CPython's OWN PREDICATES, NOT THIS PORT'S ANSWERS, so all four
# are shared rows rather than BEND-ONLY ones:
#
#   ref_empty_weak{,int}   `dt in dtypes.weaks` -- creation.py:37's own guard. The port's
#                          `cr_empty` is NOT GIVEN the option (a pure Bend def cannot
#                          raise), so the row is the guard and CPython's is the raise.
#   ref_commit_float       a weakfloat node's `commit_dtype` needs NO bounds, because it
#                          takes `strong_dtype`'s arm -- dtype.py:16. CPython agrees, and
#                          the row is `Tensor.full((2,3),42.0).dtype == dtypes.f32`.
#   ref_commit_i32         a weakint node's DOES, and (42,42) walks dtype.py:173's ladder
#                          to int32.
#
#   ref_commit_none        BEND-ONLY. The port refuses a weakint node with no bounds and
#                          CPython answers it, because Python HAS `UOp._min_max` and this
#                          port does not (W3). That is a real divergence between the two
#                          lanes and it is filtered BY NAME, the way op.bend's
#                          `rop_gap`/`exp_cast`/`commit_weak`/`bin_promote` are -- see
#                          `cr-gate.sh`.
def t_ref_empty_weak() -> IO(Unit): cr_bl("ref_empty_weak", D.md_weak(S.weakfloat()))
def t_ref_empty_weakint() -> IO(Unit): cr_bl("ref_empty_weakint", D.md_weak(S.weakint()))
def t_ref_commit_float() -> IO(Unit):
  cr_bl("ref_commit_float", D.md_dt_eq(Maybe.default(&1, S.Dt, D.commit_dtype(S.weakfloat(), None{}, None{}, S.int32()), S.void()), S.single()))
def t_ref_commit_none() -> IO(Unit):
  cr_bl("ref_commit_none", Maybe.is_none(&1, S.Dt, cr_committed.of(False{}, S.weakint(), S.weakint(), None{}, None{})))
def t_ref_commit_i32() -> IO(Unit):
  cr_bl("ref_commit_i32", D.md_dt_eq(Maybe.default(&1, S.Dt, cr_committed.of(False{}, S.weakint(), S.weakint(), Some{H.i64_of_i32(42)}, Some{H.i64_of_i32(42)}), S.void()), S.int32()))


# THE ALLOC'S OWN FIELDS, read off `RESHAPE.src[0]`. See `cr_alloc_rows`'s comment.
def t_alloc23() -> IO(Unit):
  +t = cr_empty(O.Arena.empty(), Some{S.single()}, [2, 3], S.D1{0})
  +c: CU = CU{O.Arena.src(T.Tensor.ar(t), T.Tensor.u(t), 0)}
  cr_alloc_rows(T.Tensor.ar(t), c)

# THE CONTROL. The same fixture as `empty23`, built from the same call, and the diff
# against the Python oracle is only a diff if a repeated row is byte-identical.
def t_ctrl_empty23() -> IO(Unit): cr_row("ctrl_empty23", cr_empty(O.Arena.empty(), Some{S.single()}, [2, 3], S.D1{0}))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_empty23()
    b : Unit <- t_empty23h()
    c : Unit <- t_empty23i()
    d : Unit <- t_empty4()
    e : Unit <- t_empty0()
    f : Unit <- t_emptylike2d()
    g : Unit <- t_emptylike2dh()
    h : Unit <- t_invalids23()
    i : Unit <- t_full23i42()
    j : Unit <- t_full23f42()
    k : Unit <- t_full23b()
    l : Unit <- t_full23h42()
    m : Unit <- t_full23l42()
    n : Unit <- t_full23big()
    o : Unit <- t_full_nobuf()
    p : Unit <- t_full_nobuf0()
    q : Unit <- t_full4i7()
    r : Unit <- t_constlike2d()
    s : Unit <- t_constlike0d()
    t : Unit <- t_full_like2d()
    u : Unit <- t_full_like2dh()
    v : Unit <- t_zeros23()
    w : Unit <- t_zeros23i()
    x : Unit <- t_ones23()
    y : Unit <- t_ones23i()
    z : Unit <- t_zeros_like2d()
    aa : Unit <- t_ones_like2d()
    ab : Unit <- t_intern_full()
    ac : Unit <- t_intern_empty()
    ad : Unit <- t_intern_diff()
    ae : Unit <- t_ref_empty_weak()
    af2 : Unit <- t_ref_empty_weakint()
    af : Unit <- t_ref_commit_float()
    ag : Unit <- t_ref_commit_none()
    ah : Unit <- t_ref_commit_i32()
    ai : Unit <- t_alloc23()
    t_ctrl_empty23()
# ===========================================================================
# THE MEASURED MUTATION TABLE. Twenty-three one-token edits, each applied, each run
# through the interpreted lane AND `--check-only`, each diffed against the unmutated
# output, each reverted from a byte snapshot:
#
#   .venv/bin/python cr-mutate.py          # the table below, regenerated
#   .venv/bin/python cr-mutate.py M4       # one mutation, left applied, for inspection
#
# EVERY MUTATION EXCEPT THE CONTROL MOVES AT LEAST ONE ROW, and that is the claim this
# table exists to make. `moved == 0` on a mutation of live code is a MISSING ROW (see
# wgsl.bend's gate lesson), so the two entries marked HISTORY below are reported rather
# than dropped.
#
#  #   mutation                                            rows moved   what moved
#  --  -------------------------------------------------  -----------  -------------------------
#  M1  `cr_after`'s STORE srcs reversed                     1           `int_full_expand`
#  M2  `cr_after`'s AFTER srcs reversed                    32           almost everything
#  M3  `cr_const_of`'s cast fold guard dropped             12           the 10-node rows and more
#  M4  `cr_alloc`'s slot pinned to 0 instead of `next(ar)`  3           `int_{full,empty,ones}_new`
#  M5  `bind_on_realize` cleared            [HISTORY: 0]   1           `alloc_bind`
#  M6  `cr_expand` builds a RESHAPE                        21           every `_g` with an EXPAND
#  M7  `empty`'s reshape identity test dropped              2           `empty4_g`, `full4i7_g`
#  M8  `empty`'s reshape becomes a SHRINK                  44           every row
#  M9  `cr_bounds` answers `None` for an int CONST         3           `full23i42_d`, `full23big_d`, `full4i7_d`
#  M10 `cr_from_py` makes a float CONST weakint            8           the float rows + `int_ones_new`
#  M11 `cr_committed`'s arms swapped                        7           the seven non-weak-dtype `_d` rows
#  M12 the `dt in dtypes.weaks` test inverted              12           the weaks/non-weaks split
#  M13 shape dims PREPENDED instead of appended            15           `STACK(3,2)` for `(2,3)`
#  M14 `buffer=False`'s arm inverted                       38           every `_g`
#  M15 `full`'s ALLOC built in `ar`, not in `val`'s arena  18           the whole `full` family
#  M16 `cr_new` counts every node, not the new ones         3           the three `int_*_new`
#  M17 `Invalid` becomes weakint                            1           `invalids23_g`
#  M18 shape dims NOT interned at all                      46           every row
#  M19 the `_d` row forgets the AFTER unwrap               16           every `full` `_d`
#  M21 `bind_on_realize` cleared, re-measured after the row 1           `alloc_bind`
#  M22 `addrspace` becomes `ALocal`                         1           `alloc_addr`
#  M23 `cr_srcops`'s separator becomes `:`                 25           every multi-src `_g`
#  M20 CONTROL: a comment                                   0           nothing, which is the point
#
# FIVE THINGS THIS TABLE SAYS THAT "67 GREEN ROWS" DOES NOT.
#
#   * M1 IS THE WHOLE ARGUMENT FOR THE FOUR-FACTS ROW, MEASURED. Reversing the STORE's
#     two srcs moves EXACTLY ONE row out of 67. The root op is unchanged, the root nsrc
#     is unchanged, the root's src op SEQUENCE is unchanged (`RESHAPE|STORE` -- both
#     orders print the same names), the toposort is unchanged, and every `_d` row reads
#     `AFTER.src[0]` which the mutation does not touch. A gate with `op` and `nsrc` and a
#     node count and nothing else is blind to it entirely. `int_full_expand` exists
#     because this measurement produced it, and it is the only row in the file that is
#     about an INDEX rather than a shape or a count.
#   * M5 MOVED NOTHING THE FIRST TIME IT WAS RUN, and the reason was not subtle: the
#     suite reads a ParamArg's `dtype` and `size` and NOTHING ELSE, so a whole
#     thirteen-field record had a field nobody looked at. `alloc_bind` and `alloc_addr`
#     were added, their expectations are CPython's own (`ParamArg(...,
#     bind_on_realize=True)` at creation.py:41 and `addrspace` defaulting to GLOBAL),
#     and M5 now moves `alloc_bind` and M22 moves `alloc_addr`. The header's M5/M21
#     entries are the same edit measured before and after the fix, which is the
#     wgsl.bend/device.bend lesson stated as a pair of table rows.
#   * M9 IS LOCALISED TO THE THREE weakint ROWS, and that is the correct blast radius:
#     `cr_bounds` is read only by `commit_int`, `commit_int` only on the weakint arm, and
#     only `full(.., 42)`, `full(.., 2**20)` and `full(4, 7)` have a weakint `dt`. A
#     localised row is a claim that the predicate is reachable from exactly where it
#     should be -- `full23f42_d` and `full23b_d` staying put IS the assertion that the
#     weakfloat and bool arms do not reach `commit_int`.
#   * M11 AND M3 MOVE DISJOINT SETS AND NEITHER IS A SUBSET OF THE OTHER. M3 drops the
#     `.cast` fold (a CONST that should be bare gets a CAST) and M11 swaps
#     `dtype if dtype is not None else self.commit_dtype()`'s arms (a node that should
#     commit does not). Both are "the wrong number of CASTs" to a reader and they are
#     not the same defect, which is the answer to "are these two rows one row".
#   * M16 IS THE ROW TESTING THE ROWS. `cr_new` is the only thing that can see rule 1 of
#     the header, and M16 makes it count every node instead of the new ones, which moves
#     all three `int_*_new` and nothing else -- so the three interning rows are pinned to
#     ONE predicate rather than to each other. Had `cr_new` been the shared predicate for
#     all three and wrong, one mutation would have moved three rows that are supposed to
#     be independent measurements.
# ===========================================================================
