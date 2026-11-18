# postrange.bend -- tinygrad/codegen/opt/__init__.py + codegen/opt/postrange.py.
#
# TWO PYTHON FILES IN ONE, because `opt/__init__.py` IS 19 lines that hold the
# datatype every other opt file constructs: `Opt`, `OptOps`, `KernelOptError`,
# `check`. `search.py` and `heuristic.py` both `from tinygrad.codegen.opt import
# Opt, OptOps, KernelOptError`, so `__init__.py` is the bottom of the opt
# package and this file is where that bottom lives. `postrange.py` is the only
# opt file that DEFINES it (`search.py` never constructs an `Opt`; it consumes
# the `actions` table from its own module scope), so this is also the shortest
# honest split.
#

# THE INVENTORY, def by def, against the two Python files' 296 lines.
#
#   #  PY            KIND    STATE
#   -- opt/__init__.py -----------------------------------------------------
#   1  6-8   type   OptOps           PORTED (4 arms + value ladder)
#   2  8     def   OptOps.__lt__     NOT PORTED: no call site sorts OptOps
#   3  10-15 type   Opt              PORTED, `arg: int|tuple|None` split out
#   4  15    def   Opt.__repr__     NOT PORTED: BEAM_DEBUG only
#   5  10    type   (order=True)     NOT PORTED: nothing sorts a list of Opts
#   6  17    type   KernelOptError   PORTED as `Bool` (see THE WALL below)
#   7  18-19 def   check             PORTED as `opt_ok`/inline predicates
#   -- postrange.py --------------------------------------------------------
#   8  14-15 data  split_targets     PORTED
#   9  18-21 ctor  Scheduler.__init__ PORTED as `Sched.of`, minus rngs<-arena
#  10  23-27 prop  Scheduler.rngs    PORTED as an INPUT field; the arena walk
#                                      that fills it is WALL #1
#  11  29    prop  shape_len         PORTED
#  12  30    prop  full_shape        PORTED (as `List<U32>`; `ssimplify` is a wall)
#  13  32    prop  axis_types        PORTED
#  14  35-38 def   copy              PORTED (trivially: Data is copyable)
#  15  40-48 def   get_optimized_ast WALL #2: graph_rewrite + color strings
#  16  50-51 def   _output_rngs      WALL #1 (`UOp.ranges`, deferred to fold)
#  17  52-58 def   _globalizable_rngs WALL #1
#  18  60-66 def   convert_loop_to_global WALL #1 (it substitutes into the AST)
#  19  68-76 def   colors            WALL #3: ANSI strings, debug only
#  20  77    def   colored_shape     WALL #3
#  21  79-87 def   shift_to          SPLIT PORTED (the rng bookkeeping),
#                                      the `ast.substitute` is WALL #2
#  22  89    def   ranges_of         PORTED
#  23  90    def   axes_of           PORTED (`*axis_type` becomes a List)
#  24  92-95 prop  reduce_axes       WALL #1
#  25  97    def   upcast_size       PORTED
#  26  99-101 prop upcastable_dims   PORTED
#  27  102-104 prop unrollable_dims  PORTED
#  28  106-174 def apply_opt         CHECK LAYER PORTED (`opt_ok`), PADTO/SWAP
#                                      rng bookkeeping PORTED, the AST writes
#                                      are WALL #2, `_apply_tc_opt` is WALL #4
#  29  176-242 def _apply_tc_opt     WALL #4: TensorCore.relabel + WMMA build
#  30  245-246 prop reduceops        WALL #1
#  31  247-248 prop reduceop         WALL #1
#  32  249-250 prop bufs             WALL #1
#  33  251-252 prop upcasted         PORTED
#  34  253-254 prop group_for_reduces PORTED as `group_for_reduces` (uses axes)
#  35  256-258 def args_from_ast     WALL #5: `ast.variables()` + Buffer alloc
#  36  260-277 def apply_opts        PORTED as the dispatcher; the three arms
#                                      that need `rawbufs`/`var_vals` are WALL #5
#

# THE WALLS, five, and they are ONE wall wearing five hats. `apply_opt` MUTATES
# `self.ast` (`self.ast = self.ast.substitute(...)`), and Bend has no mutable
# field. But it has DATA, so the mutation is a def that RETURNS the new
# `Sched` and the caller binds it. That is why `Sched` carries `rngs` as a
# FIELD and not as a reader: the axes are the only part of a Scheduler that
# `apply_opt` can be ported over, and they must travel with it.
#
# WHAT IS ACTUALLY PORTED OF `apply_opt`, and it is the part that decides
# BEAM: every `check(...)` in the SPLIT arm and in the SWAP/PADTO arms, plus
# every `check` in `shift_to` EXCEPT the substitution, plus `get_kernel_actions`
# `'s `up`/`lcl` accumulation. Those are the RULES, and a rule that cannot be
# evaluated is a rule that cannot be scored, so this is not the easy half.
# `get_kernel_actions` counts candidates by calling `apply_opt` and catching
# `KernelOptError`; `opt_ok` is that verdict as a `Bool`.
#
# `KernelOptError` IS A `Bool`, not a datatype. Python raises and the caller
# catches in a `try`; Bend has no exceptions, so `opt_ok` returns False and the
# message is dropped. The message is the only thing lost, and every message in
# these two files is a `check` string that never reaches a user.
#

# WHAT `Sched` DOES NOT CARRY, and why that is not an omission:
#   * `ren` is a field of `Sched`, not a parameter, because `apply_opt` reads
#     `ren.has_local` and `ren.target.device` at four separate sites and
#     threading it is four more parameters at every call site.
#   * `Renderer` here is `Ren`, a SIX-FIELD record, not `renderer/__init__.bend`'s
#     full renderer. That file is a sibling and mid-flight; `Ren` carries
#     exactly the four fields `apply_opt` and `heuristic.py` read (`dev`,
#     `has_local`, `has_shared`, `shared_max`) plus `n_tc` for
#     `len(self.ren.tensor_cores)`. MERGE POINT: delete `Ren` and read the
#     sibling's `Renderer`, keeping the field names.
#   * `n_tc` is a COUNT, not a list of `TensorCore`. `apply_opt` only asks
#     `-1 <= tc_select < len(self.ren.tensor_cores)`, and the arms inside
#     `_apply_tc_opt` that read `tc.dims`/`tc.relabel` are WALL #4.
#

# THE `tc_select = -1` ENCODING. `check(-1 <= tc_select < len(tensor_cores))` is
# a CHAINED comparison, so for `tc_select == -1` it is `(-1 <= -1) and (-1 < 0)`
# -- which is TRUE for any length, including 0. Bend has no signed integer, so
# `OA_TC.any` IS `tc_select == -1` and the whole check collapses to
# `any or sel < n_tc`. MEASURED: on a PYTHON device (`tensor_cores == []`) the
# TC action reports "no tensor core available", which is the arm AFTER the
# bound check, which is what proves the chain passed.
#

# THE `full_shape` IS `List<U32>`, NOT `List<Sint>`. `full_shape` is
# `[ssimplify(x.src[0]) for x in self.rngs]`, and `ssimplify` of a symbolic
# `VLEN` is not a U32. Two of the three gates below use kernels whose shapes are
# CONST, so the U32 is exact there, and `search.py`'s `sym_infer(sz, var_vals)`
# on the same list is WALL #6. `opt_ok`'s `fs[axis] % amt` is the divisibility
# test Python gets from `rng.src[0].divides(amount)`, which is the same test on
# a CONST bound.

import Base
import ./../../helpers.bend as H
import ./../../uop/ops.bend as O

# opt/__init__.py -- `OptOps`, `Opt` and `Opt.arg` live in `uop/ops.bend` now
# (this file imports that one, and `KernelInfo` carries an `Opt`, so the types
# had to move to the bottom). `O.OPT` / `O.OPTOPS` are the spellings; the three
# readers below stay here with the `Sched` that uses them.

# the only thing that ever reads `arg` is the `match opt.arg is ...` ladder in
# `apply_opt`, so the ladder destructures the record directly.
# A `Data` FIELD IS READ BY DESTRUCTURING, NEVER BY PROJECTION. `s.amt` on a
# pattern binder is a NAME lookup and fails, so every reader of a nested record
# is a nested pattern -- `case OA_SPLIT{SPL{amt, t, top}}` -- which is also
# ops.bend's `case AParam{pa}: match pa:` shape written on one line.
# `top` is `Maybe` because the arg can be a 2- or 3-tuple; `opt_top` answers its
# resolved value, which is what `apply_opt`'s `(*opt.arg, False)[0:3]` does.
def opt_amt(a: O.OPTARG) -> U32:
  match a:
    case O.OA_SPLIT{O.SPL{amt, t, top}}: amt
    case O.OA_INT{i}: i
    case O.OA_TC{O.TC{any, sel, lvl, use}}: sel
    case _: 0

def opt_top(a: O.OPTARG) -> Bool:
  match a:
    case O.OA_SPLIT{O.SPL{amt, t, top}}:
      match top:
        case Some{b}: b
        case _: False{}
    case _: False{}

def opt_target(a: O.OPTARG) -> O.AxisType:
  match a:
    case O.OA_SPLIT{O.SPL{amt, t, top}}: t
    case _: O.AXIS_LOOP{}

# postrange.py: split_targets, the Renderer slice, the Scheduler

# `split_targets` is a dict keyed by the TARGET of a split. `shift_to` reads it
# as `rng.axis_type in split_targets[new_type]` -- so it is a MEMBERSHIP test on
# a three-element list, and `List.contains(O.AxisType, O.eq_axis, ...)` is it.
def split_targets(nt: O.AxisType) -> List<&2, O.AxisType>:
  match nt:
    case O.AXIS_UPCAST{}: [O.AXIS_GLOBAL{}, O.AXIS_LOCAL{}, O.AXIS_WEAK{}]
    case O.AXIS_UNROLL{}: [O.AXIS_REDUCE{}, O.AXIS_LOCAL{}]
    case O.AXIS_LOCAL{}: [O.AXIS_GLOBAL{}, O.AXIS_WEAK{}, O.AXIS_REDUCE{}]
    case _: Nil{}

type DEV is Data:
  DEV_PYTHON{}
  DEV_CUDA{}
  DEV_NV{}
  DEV_QCOM{}
  DEV_DSP{}
  DEV_OTHER{}

# MERGE POINT with `renderer/__init__.bend`: it has no `Renderer` record yet.
# These five fields are the only ones `postrange.py` and `heuristic.py` read.
type REN is Data:
  REN{dev: DEV, has_local: Bool, has_shared: Bool, shared_max: U32, n_tc: U32}

# `Renderer`'s class defaults, and the device's own overrides, for
# `PythonRenderer` -- MEASURED from CPython: `has_local True`, `has_shared True`,
# `shared_max 32768`, `tensor_cores []`.
def REN.python() -> REN:
  REN{DEV_PYTHON{}, True{}, True{}, 32768, 0}

# `ClangRenderer.has_local = False` (cstyle.py:279), MEASURED. The gate needs it
# because `ck_local`'s False arm is the only way to reach `check(has_local)`.
def REN.nolocal() -> REN:
  REN{DEV_PYTHON{}, False{}, True{}, 32768, 0}

# the DSP exemption of `ck_upcast`: `check(self.ren.target.device == "DSP" or
# amt <= 16, ...)`, so a DSP kernel may upcast by 128 and a Python one may not.
def REN.dsp() -> REN:
  REN{DEV_DSP{}, True{}, True{}, 32768, 0}

def REN.dev(x: REN) -> DEV:
  match x:
    case REN{dev, has_local, has_shared, shared_max, n_tc}: dev

def REN.has_local(x: REN) -> Bool:
  match x:
    case REN{dev, has_local, has_shared, shared_max, n_tc}: has_local

# `RNG` is one entry of `Scheduler.rngs`: a RANGE reduced to the three fields
# `postrange.py` and `heuristic.py` read. `id` is `axis_id[0]`; a multi-component
# `axis_id` compares elementwise in Python's sort key and does not fit a U32,
# so that case is WALL #1 with the rest of the arena walk.
type RNG is Data:
  RNG{id: U32, t: O.AxisType, sz: U32}

def RNG.id(x: RNG) -> U32:
  match x:
    case RNG{id, t, sz}: id

def RNG.t(x: RNG) -> O.AxisType:
  match x:
    case RNG{id, t, sz}: t

def RNG.sz(x: RNG) -> U32:
  match x:
    case RNG{id, t, sz}: sz

# `axis_to_pos` collapsed to the SORT ORDER. Python's key is
# `(axis_to_pos[axis_type],) + axis_id` and `axis_to_pos` is DEVICE -2, WEAK/LOOP
# -1, then GLOBAL 0 .. UNROLL 5. The negative ranks are exactly the ones that
# sort BEFORE everything else, and the rest are strictly increasing, so mapping
# the nine arms onto 0..7 is order-isomorphic to the two-part key -- and it is
# the only place the sign flag has to be reasoned about at all.
# PLACEHOLDER has no `axis_to_pos` arm (Python raises KeyError); ops.bend's
# `case _` gives it `Pos{False, 0}`, i.e. GLOBAL's rank, and that is what
# `pos_key` answers. WALL #3: PLACEHOLDER is excluded from `rngs` anyway.
def pos_key(a: O.AxisType) -> U32:
  match a:
    case O.AXIS_DEVICE{}: 0
    case O.AXIS_WEAK{}: 1
    case O.AXIS_LOOP{}: 1
    case O.AXIS_GLOBAL{}: 2
    case O.AXIS_WARP{}: 3
    case O.AXIS_LOCAL{}: 4
    case O.AXIS_UPCAST{}: 5
    case O.AXIS_REDUCE{}: 6
    case _: 7

# `List.sort`'s comparator is `A -> A -> Bool` and Python's is a total order, so
# `<=` and NOT `<` -- a comparator that is false in both directions sorts in
# reverse (helpers.bend measures this).
def rng_le.k(same: Bool, ka: U32, ia: U32, kb: U32, ib: U32) -> Bool:
  match same:
    case True{}: U32.is_le(ia, ib)
    case False{}: U32.is_lt(ka, kb)

def rng_le(a: RNG, b: RNG) -> Bool:
  match a b:
    case RNG{id, +t, sz} RNG{j, +u, w}: rng_le.k(U32.is_eq(pos_key(t), pos_key(u)), pos_key(t), id, pos_key(u), j)

type Sched is Data:
  Sched{ren: REN, rngs: List<&2, RNG>, opts: List<&2, O.OPT>}

def Sched.ren(x: Sched) -> REN:
  match x:
    case Sched{ren, rngs, opts}: ren

def Sched.rngs(x: Sched) -> List<&2, RNG>:
  match x:
    case Sched{ren, rngs, opts}: rngs

def Sched.opts(x: Sched) -> List<&2, O.OPT>:
  match x:
    case Sched{ren, rngs, opts}: opts

# `Scheduler.copy` -- `Data` is shareable ACROSS defs, so this is the identity.
# It is ported anyway because `heuristic.py` calls it before every mutation and
# the call site is what documents that the port is MUTATION-FREE rather than
# accidentally aliasing.
def Sched.copy(x : Sched) -> Sched:
  match x:
    case Sched{ren, rngs, opts}: Sched{ren, rngs, opts}

def Sched.of(ren: REN, rngs: List<&2, RNG>) -> Sched:
  Sched{ren, List.sort(RNG, rng_le, rngs), Nil{}}

def Sched.shape_len(x : Sched) -> U32:
  U32.from_nat(List.length(&2, RNG, Sched.rngs(x)))

# `self.rngs[self.shape_len]` for an out-of-range axis, so `opt_ok` can read
# `fs[axis]` without threading a Maybe. `RNG{0, DEVICE, 1}` is inert: DEVICE is
# `pos_key` 0 and it is never a legal split target, so it poisons nothing.
def Sched.at(x: Sched, i: U32) -> RNG:
  Maybe.default(&2, RNG, List.get(&2, RNG, Sched.rngs(x), U32.to_nat(i)), RNG{0, O.AXIS_DEVICE{}, 1})

def shape_go(rs: List<&2, RNG>, acc: List<&2, U32>) -> List<&2, U32>:
  match rs:
    case Nil{}: acc
    case h <> t: shape_go(t, List.append(&2, U32, acc, [RNG.sz(h)]))

# `full_shape` -- WALL #6 on a symbolic bound, exact on a CONST one.
def Sched.full_shape(x : Sched) -> List<&2, U32>:
  shape_go(Sched.rngs(x), Nil{})

def types_go(rs: List<&2, RNG>, acc: List<&2, O.AxisType>) -> List<&2, O.AxisType>:
  match rs:
    case Nil{}: acc
    case h <> t: types_go(t, List.append(&2, O.AxisType, acc, [RNG.t(h)]))

# `axis_types`
def Sched.axis_types(x : Sched) -> List<&2, O.AxisType>:
  types_go(Sched.rngs(x), Nil{})

# the FOLD shape, and it is the same four times.
#
# `match rs hit:` with `hit` as a fifth parameter is the shape the constraints
# notes recommend for a `find`-style walk, and it is WRONG for a FILTER, because
# `hit` in the body is the verdict about the element the CALLER saw: the arms
# consume `h` and hand the NEXT call the CURRENT `hit`. MEASURED: both arms
# appended unconditionally and `axes_of(REDUCE_FIXTURE, [GLOBAL])` answered 2 for
# a kernel with ONE global axis, while `count_bools([True,True,True,True])`
# answered 3 -- one short, because the seed `False{}` swallowed the head.
#
# The fix is a `_put` HELPER that takes the element and the accumulator and
# answers the next accumulator, with the verdict as its own `Bool` PARAMETER so
# the `match` head is a parameter. `_hit` is the identity on a `Bool` and exists
# only to satisfy "a `match` may only scrutinise a parameter" for the
# `List.contains` call; `rng_le.k` above is the same `.z` idiom.

def hit(b: Bool) -> Bool:
  b

def sel(ts: List<&2, O.AxisType>, h: RNG) -> Bool:
  hit(List.contains(O.AxisType, O.eq_axis, ts, RNG.t(h)))

# the index IS the accumulator's length, which is why these walks need no counter
def sel_put(keep: Bool, +acc: List<&2, U32>) -> List<&2, U32>:
  match keep:
    case True{}: List.append(&2, U32, acc, [U32.from_nat(List.length(&2, U32, acc))])
    case False{}: acc

def axes_put(acc: List<&2, U32>, +ts: List<&2, O.AxisType>, h: RNG) -> List<&2, U32>:
  sel_put(sel(ts, h), acc)

def axes_go(rs: List<&2, RNG>, +ts: List<&2, O.AxisType>, +acc: List<&2, U32>) -> List<&2, U32>:
  match rs:
    case Nil{}: acc
    case +h <> t: axes_go(t, ts, axes_put(acc, ts, h))

# `axes_of(*axis_type)` -- Python's varargs become a LIST, because a `match` may
# only scrutinise a parameter and `*axis_type` is not one thing. `eq_axis` is
# ops.bend's `AxisType` equality, so the membership test is the Python `in`.
def Sched.axes_of(x: Sched, ts: List<&2, O.AxisType>) -> List<&2, U32>:
  axes_go(Sched.rngs(x), ts, Nil{})

def ranges_put(keep: Bool, acc: List<&2, RNG>, h: RNG) -> List<&2, RNG>:
  match keep:
    case True{}: List.append(&2, RNG, acc, [h])
    case False{}: acc

def ranges_go(rs: List<&2, RNG>, +ts: List<&2, O.AxisType>, +acc: List<&2, RNG>) -> List<&2, RNG>:
  match rs:
    case Nil{}: acc
    case +h <> t: ranges_go(t, ts, ranges_put(sel(ts, h), acc, h))

# `ranges_of`
def Sched.ranges_of(x: Sched, ts: List<&2, O.AxisType>) -> List<&2, RNG>:
  ranges_go(Sched.rngs(x), ts, Nil{})

# THE DIMENSION READERS. `upcastable_dims` and `unrollable_dims` are the same
# fold -- "indices whose axis type is in SET and whose CONST size is > 1" -- so
# they share `dim_go`, and Python writes them out because they are two
# properties. `unrollable_dims` additionally filters `self.reduce_axes`, which is
# WALL #1 (`UOp.ranges` over the REDUCE srcs); the assumption stated on
# `Sched.unrollable_dims` is that every REDUCE-typed axis came off a reduce,
# which is true of every Scheduler `postrange.py` builds.

# `isinstance(s:=self.full_shape[i], int) and s > 1`, the value half.
def gt1(sz: U32) -> Bool:
  Bool.not(U32.is_le(sz, 1))

def dim_both(hit: Bool, big: Bool) -> Bool:
  Bool.and(hit, big)

# `t in axis_types and s > 1`
def dim_sel(+ts: List<&2, O.AxisType>, +h: RNG) -> Bool:
  hit(dim_both(List.contains(O.AxisType, O.eq_axis, ts, RNG.t(h)), gt1(RNG.sz(h))))

def dim_put(acc: List<&2, U32>, +ts: List<&2, O.AxisType>, h: RNG) -> List<&2, U32>:
  sel_put(dim_sel(ts, h), acc)

def dim_go(rs: List<&2, RNG>, +ts: List<&2, O.AxisType>, +acc: List<&2, U32>) -> List<&2, U32>:
  match rs:
    case Nil{}: acc
    case +h <> t: dim_go(t, ts, dim_put(acc, ts, h))

# `upcastable_dims` -- GLOBAL/LOCAL/WEAK with size > 1.
def Sched.upcastable_dims(x : Sched) -> List<&2, U32>:
  dim_go(Sched.rngs(x), [O.AXIS_GLOBAL{}, O.AXIS_LOCAL{}, O.AXIS_WEAK{}], Nil{})

# `unrollable_dims` -- LOCAL/REDUCE with size > 1.
def Sched.unrollable_dims(x : Sched) -> List<&2, U32>:
  dim_go(Sched.rngs(x), [O.AXIS_LOCAL{}, O.AXIS_REDUCE{}], Nil{})

# `upcasted` -- `len(self.axes_of(UPCAST, UNROLL))`.
def Sched.upcasted(x : Sched) -> U32:
  U32.from_nat(List.length(&2, U32, Sched.axes_of(x, [O.AXIS_UPCAST{}, O.AXIS_UNROLL{}])))

# `group_for_reduces` -- `len([i for i in self.reduce_axes if axis_types[i] in
# (WARP, LOCAL)])`, i.e. the WARP/LOCAL axes that came off a reduce.
def Sched.group_for_reduces(x : Sched) -> U32:
  U32.from_nat(List.length(&2, U32, Sched.axes_of(x, [O.AXIS_WARP{}, O.AXIS_LOCAL{}])))

# `get_kernel_actions`' `up`/`lcl`, search.py:94-98, which are also `upcast_size`
# and the first half of `group_for_reduces`. `up` is
# `prod(full_shape[i] for i, t in zip(full_shape, axis_types) if t in (UPCAST,
# UNROLL))`; `lcl` is the same walk with `(WARP, LOCAL)`. It lives HERE and not
# in `search.bend` because it is `prod` over `Sched`'s two parallel readers and
# because it is what makes `opt_ok` + `Sched.split` a COMPLETE candidate filter.
#
# THE ZIP IS NOT A ZIP. `axes_of` returns absolute indices, so the Python reads
# as `full_shape[a] for a in axes`, and a `match rs ixs:` walk cannot say that:
# `case 0n:` is a PREFIX match that claims its successors, so the `1n+p` arm
# after it is dead and Bend refuses the match as "already matched". Folding once
# with the type test inline is the same product, and `axes_go`'s accumulator is
# already the index if a caller needs the positions.

def up_step(acc: U32, sz: U32, t: O.AxisType) -> U32:
  match t:
    case O.AXIS_UPCAST{}: U32.mul(acc, sz)
    case O.AXIS_UNROLL{}: U32.mul(acc, sz)
    case _: acc

def up_go(rs: List<&2, RNG>, acc: U32) -> U32:
  match rs:
    case Nil{}: acc
    case +h <> t: up_go(t, up_step(acc, RNG.sz(h), RNG.t(h)))

def lcl_step(acc: U32, sz: U32, t: O.AxisType) -> U32:
  match t:
    case O.AXIS_WARP{}: U32.mul(acc, sz)
    case O.AXIS_LOCAL{}: U32.mul(acc, sz)
    case _: acc

def lcl_go(rs: List<&2, RNG>, acc: U32) -> U32:
  match rs:
    case Nil{}: acc
    case +h <> t: lcl_go(t, lcl_step(acc, RNG.sz(h), RNG.t(h)))

# `upcast_size` -- `prod(self.full_shape[a] for a in self.axes_of(UPCAST, UNROLL))`.
def Sched.upcast_size(x : Sched) -> U32:
  up_go(Sched.rngs(x), 1)

# `if up//tc_up > max_up or lcl > max_lcl: continue` -- search.py:98.
def ul_ok(up: U32, lcl: U32, tc_up: U32, max_up: U32, max_lcl: U32) -> Bool:
  Bool.and(U32.is_le(U32.div(up, tc_up), max_up), U32.is_le(lcl, max_lcl))

# `apply_opt`'s SPLIT arm, and the rng bookkeeping of `shift_to`. This is the
# whole reason `Sched` carries fields rather than computing them.
#
# `shift_to` renames ONE rng and ADDS one: `replaced_rng` KEEPS `axis_id` and
# takes `new_type` with size `old_sz`, and `new_rng` is `UOp.range(amount,
# next(self.opt_range), new_type)` -- a FRESH id from a counter seeded above
# every id in the AST, which is `max(id) + 1`. `top` chooses which of the two is
# the fast axis of `sub_axis`, and `sub_axis` is WALL #2; the two rngs are not,
# because both are functions of `(old_sz, amount, new_type)` alone.

# THE RUNNING MAXIMUM IS A `Data` RECORD, not a `U32`. `max(m, i)` needs `i`
# in the comparison AND in the answer, and `U32` cannot be `+`, so the fold
# would be unreadable as `max(m, i)` and unwritable as two `U32` parameters. A
# record is shareable, so one `MAXA` parameter carries both roles.
type MAXA is Data:
  MAXA{m: U32}

def MAXA.m(a: MAXA) -> U32:
  match a:
    case MAXA{m}: m

def max_step(gt: Bool, +a: MAXA, i: U32) -> MAXA:
  match gt:
    case True{}: MAXA{i}
    case False{}: a

def max_id.go(rs: List<&2, RNG>, +a: MAXA) -> U32:
  match rs:
    case Nil{}: MAXA.m(a)
    case +h <> t: max_id.go(t, max_step(U32.is_lt(MAXA.m(a), RNG.id(h)), a, RNG.id(h)))

def Sched.max_id(x : Sched) -> U32:
  max_id.go(Sched.rngs(x), MAXA{0})

# `rngs[at] = rep`, then the `rngs` PROPERTY re-sorts. The new pair therefore
# lands wherever `(pos_key, id)` puts it, NOT at the end, and `full_shape` and
# `axis_types` are read off THAT list -- so a LOCAL split of axis 0 of a
# `[GLOBAL, REDUCE]` kernel moves that axis from index 0 to index 1.
# `Sched.split` -- the rng bookkeeping of `apply_opt(SPLIT)` + `shift_to`.
# `amt` is ALREADY resolved: `apply_opt` turns `amt == 0` into `int(rng.vmax+1)`
# before `shift_to` ever runs, and `Sched.at` answers an inert DEVICE rng for an
# out-of-range axis so every read here is total.
# the opt is the carrier, which is also python's signature.
# `def apply_opt(self, opt: Opt, append_opt: bool = True)` takes ONE argument,
# and this is the reason `Sched.split` does too. The alternative -- `axis: U32,
# amt: U32, nt: AxisType` -- is unwritable: `axis` is read twice, `amt` is read
# twice, and `U32` cannot be `+`. `OPT` is `Data`, so `+o` licenses every read
# and the pair `{axis, arg}` travels the way it travels in Python.
def opt_spl(a: O.OPTARG) -> O.SPL:
  match a:
    case O.OA_SPLIT{O.SPL{amt, t, top}}: O.SPL{amt, t, top}
    case _: O.SPL{0, O.AXIS_LOOP{}, None{}}

# `replaced_rng` -- same `axis_id`, `new_type`, size `old_sz`.
def rep_rng(+r: RNG, a: O.SPL) -> RNG:
  match a:
    case O.SPL{amt, t, top}: RNG{RNG.id(r), t, U32.div(RNG.sz(r), amt)}

# `new_rng` -- `UOp.range(amount, next(self.opt_range), new_type)`. The id is
# `max(id) + 1`, which is what `opt_range`'s `count(start=max+1)` hands out.
def new_rng(mid: U32, a: O.SPL) -> RNG:
  match a:
    case O.SPL{amt, t, top}: RNG{mid, t, amt}

def split_new(x: Sched, a: O.SPL) -> List<&2, RNG>:
  [new_rng(U32.add(Sched.max_id(x), 1), a)]

# `rngs[at] = replaced_rng`, then the `rngs` PROPERTY re-sorts. The new pair
# therefore lands wherever `(pos_key, id)` puts it, NOT at the end, and
# `full_shape` and `axis_types` are read off THAT list -- so a LOCAL split of
# axis 0 of a `[GLOBAL, REDUCE]` kernel moves that axis from index 0 to index 1.
# `U32.is_eq(List.length(acc), OPT.axis(o))` is `i == axis` for the element the
# walk is ON, because `acc` already holds exactly the elements before it.
def at_it(acc: List<&2, RNG>, o: O.OPT) -> Bool:
  U32.is_eq(U32.from_nat(List.length(&2, RNG, acc)), O.OPT.axis(o))

def put_at.at(here: Bool, acc: List<&2, RNG>, +o: O.OPT, h: RNG) -> List<&2, RNG>:
  match here:
    case True{}: List.append(&2, RNG, acc, [rep_rng(h, opt_spl(O.OPT.arg(o)))])
    case False{}: List.append(&2, RNG, acc, [h])

def put_at(+acc: List<&2, RNG>, +o: O.OPT, h: RNG) -> List<&2, RNG>:
  put_at.at(at_it(acc, o), acc, o, h)

def put_go(rs: List<&2, RNG>, +o: O.OPT, +acc: List<&2, RNG>) -> List<&2, RNG>:
  match rs:
    case Nil{}: acc
    case +h <> t: put_go(t, o, put_at(acc, o, h))

def split_rngs(+x: Sched, +o: O.OPT) -> List<&2, RNG>:
  List.sort(RNG, rng_le, List.append(&2, RNG, put_go(Sched.rngs(x), o, Nil{}), split_new(x, opt_spl(O.OPT.arg(o)))))

# `Sched.split` -- the rng bookkeeping of `apply_opt(SPLIT)` + `shift_to`. `amt`
# is ALREADY resolved: `apply_opt` turns `amt == 0` into `int(rng.vmax+1)` before
# `shift_to` runs. `top` is carried and IGNORED -- it picks which of the two is
# the fast axis of `sub_axis`, and `sub_axis` is WALL #2.
def SPLIT_OPT(axis: U32, amt: U32, t: O.AxisType, top: Bool) -> O.OPT:
  O.OPT{O.OPS_SPLIT{}, axis, O.OA_SPLIT{O.SPL{amt, t, Some{top}}}}

def Sched.split(+x: Sched, +o: O.OPT) -> Sched:
  Sched{Sched.ren(x), split_rngs(x, o), List.append(&2, O.OPT, Sched.opts(x), [o])}

# THE TABLE IS IN `.agents/slop/tables/codegen-opt-postrange-551.md` -- `opt_ok` -- EVERY `check` in `apply_opt`'s SPLIT, PADTO and SWAP arms, plus

# `is` on two `DEV`s -- `Data` types are nominal, so this is identity.
def dev_is(d: DEV, w: DEV) -> Bool:
  match d w:
    case DEV_DSP{} DEV_DSP{}: True{}
    case DEV_QCOM{} DEV_QCOM{}: True{}
    case DEV_CUDA{} DEV_CUDA{}: True{}
    case DEV_NV{} DEV_NV{}: True{}
    case DEV_PYTHON{} DEV_PYTHON{}: True{}
    case _ _: False{}

# `apply_opt`'s entry check, `check(type(opt.axis) is int and 0 <= opt.axis <
# self.shape_len)`. It runs for SPLIT, PADTO and SWAP alike -- TC gets
# `UOp(Ops.NOOP)` instead, which is why `opt_ok.tc` does not call it.
def opt_axis_ok(x: Sched, axis: U32) -> Bool:
  U32.is_lt(axis, Sched.shape_len(x))

# `top` is accepted and IGNORED: `apply_opt` validates it
# (`isinstance(top, bool)`) and `OPTARG`'s constructor IS the type test, so the
# check has no content here. It is a parameter so the call site reads like
# `Opt(SPLIT, axis, (amt, atype, top))`.
#
# the six conjuncts are six defs. `Bool.and` is a plain 2-argument function, and
# a comment INSIDE its argument list stops the parser from seeing it as applied
# (`expected : Bool, observed : @b:Bool -> Bool`), so the nesting carries no
# commentary. Six named predicates also give the gate six LOCALISED rows: each
# has a fixture that fails only it.
def ck_tgt(x: Sched, axis: U32, nt: O.AxisType) -> Bool:
  # `check(rng.axis_type in split_targets[new_type])` -- shift_to:80
  List.contains(O.AxisType, O.eq_axis, split_targets(nt), RNG.t(Sched.at(x, axis)))

# `amt == 0 or amt > 1` IS `amt != 1`. Python writes the disjunction because it
# is the shape `apply_opt` documents, and a `U32` cannot be read twice in one
# expression, so the disjunction is unspellable. On `U32`, which has no negative,
# the two agree at every value: 0 is `!= 1` and not `> 1`; 1 is neither; `>= 2` is
# both. It is an equivalence, not an approximation, and `ck_amt_*` are its rows.
def ck_amt(amt: U32) -> Bool:
  Bool.not(U32.is_eq(amt, 1))

def ck_local(x: Sched, nt: O.AxisType) -> Bool:
  # `if new_type is AxisType.LOCAL: check(self.ren.has_local, "locals needed for opt")`
  Bool.or(Bool.not(O.eq_axis(nt, O.AXIS_LOCAL{})), REN.has_local(Sched.ren(x)))

def ck_unroll(nt: O.AxisType, amt: U32) -> Bool:
  # `if new_type is AxisType.UNROLL: check(amt <= 32, "don't unroll more than 32")`
  Bool.or(Bool.not(O.eq_axis(nt, O.AXIS_UNROLL{})), U32.is_le(amt, 32))

def ck_upcast.dsp(x: Sched, amt: U32) -> Bool:
  Bool.or(dev_is(REN.dev(Sched.ren(x)), DEV_DSP{}), U32.is_le(amt, 16))

def ck_upcast(x: Sched, nt: O.AxisType, amt: U32) -> Bool:
  # `if new_type is AxisType.UPCAST: check(self.ren.target.device == "DSP" or
  # amt <= 16, "don't upcast more than 16")`
  Bool.or(Bool.not(O.eq_axis(nt, O.AXIS_UPCAST{})), ck_upcast.dsp(x, amt))

def ck_div(x: Sched, axis: U32, amt: U32) -> Bool:
  # `(old_sz := rng.src[0].divides(amount)) is None` -> KernelOptError. `divides`
  # is None unless `amount` divides the bound; on a CONST bound that is `%`.
  # `U32.mod(_, 0)` is the dividend, and `amt` is 0 only if a caller skipped
  # `apply_opt`'s `if amt == 0` resolution, which `opt_ok.at` never is.
  U32.is_zero(U32.mod(RNG.sz(Sched.at(x, axis)), amt))

# A NEWLINE AFTER `Bool.and(` LEAVES IT UNAPPLIED: the parser reads the
# following `Bool.and(...)` line as the FIRST ARGUMENT and the whole nest as a
# single function value, which is what `expected : Bool, observed :
# @b:Bool -> Bool` is. So the head and its first argument share a line. MEASURED,
# and it is the same trap as `case 0n:` claiming its successors: one construct,
# two unrelated-looking errors.
# THE RESOLVED OPT AS A RECORD. `apply_opt` unpacks `(amt, new_type, top)` once
# and then reads all three at four separate `check`s, which is unspellable with
# three `U32`/`AxisType` parameters -- each is read two or three times and none
# can be `+`. So the unpacking Python does with `(*opt.arg, False)[0:3]` happens
# ONCE, into `Q`, and the six predicates take the record. `+` on the destructured
# `U32` binders is what licenses the second and third reads.
type Q is Data:
  Q{axis: U32, amt: U32, nt: O.AxisType}

def Q.of(axis: U32, amt: U32, nt: O.AxisType) -> Q:
  Q{axis, amt, nt}

def opt_ok.at(+x: Sched, q: Q) -> Bool:
  match q:
    case Q{+axis, +amt, +nt}:
      Bool.and(ck_tgt(x, axis, nt),
      Bool.and(ck_amt(amt),
      Bool.and(ck_local(x, nt),
      Bool.and(ck_unroll(nt, amt),
      Bool.and(ck_upcast(x, nt, amt),
      ck_div(x, axis, amt))))))

def REN.n_tc(x: REN) -> U32:
  match x:
    case REN{dev, has_local, has_shared, shared_max, n_tc}: n_tc

# `no_opts` is `len(self.applied_opts)`, passed in so the `match` on `a: TC` is
# the ONLY scrutinee in the def -- `match a x:` would be a two-scrutinee match
# over a 4-field record and a `Sched`.
def n_opts(x: Sched) -> U32:
  U32.from_nat(List.length(&2, O.OPT, Sched.opts(x)))

# `opt_ok.tc` -- `apply_opt`'s TC arm, all four `check`s.
# `check(0 < use_tensor_cores <= 2, "use_tensor_cores value is not valid")` --
# BOTH bounds. `ok_tc_use` is the row for the upper one: a port that keeps only
# `> 0` passes the fixture and rejects nothing.
# `0 < use <= 2` IS `use - 1 <= 1`, ON U32. The disjunction is unspellable --
# `use` cannot be read twice in one expression -- and the subtraction uses
# `U32`'s WRAP, which is what makes it an equivalence rather than a guess:
# `use = 0` wraps to 2^32-1 (not <= 1, correctly rejected), 1 and 2 give 0 and 1
# (both accepted), 3 gives 2 (rejected), and every larger value gives >= 2.
# `ok_tc_use` is the row, and it is the row a mutation that keeps only `> 0`
# moves.
def ck_use(use: U32) -> Bool:
  U32.is_le(U32.sub(use, 1), 1)

def opt_ok.tc(a: O.TC, +x: Sched, no_opts: U32) -> Bool:
  match a:
    case O.TC{any, sel, lvl, use}:
      # `check(0 <= tc_opt <= 2)` and `check(0 < use_tensor_cores <= 2)`
      Bool.and(
        Bool.and(U32.is_le(lvl, 2),
        Bool.and(ck_use(use),
        # `-1 <= tc_select < len(tensor_cores)` is a CHAINED compare, so `sel ==
        # -1` passes for EVERY length including 0. See the header.
        Bool.or(any, U32.is_lt(sel, REN.n_tc(Sched.ren(x)))))),
        # `check(len(self.applied_opts) == 0, "tensor core opts must be first")`
        U32.is_zero(no_opts))

# `tc_up` -- `next((prod(u.arg[0])//u.arg[2] for u in s2.ast.backward_slice if
# u.op is Ops.WMMA), 1)`. `0` is the "no WMMA" answer; the scan is WALL #4.
def Sched.tc_up(x : Sched) -> U32:
  1

# THE GATE. `main` prints one row per claim; the interpreter and the native
# binary must print the same rows. Rows are DERIVED FROM CPython, so a row can
# actually be wrong:
#
#   CPython, DEV=PYTHON, `PythonRenderer` (has_local True, has_shared True,
#   shared_max 32768, tensor_cores []), captured by patching `apply_opts`:
#
#     (a+1) on a 4-element tensor          full_shape [4]   axis_types [GLOBAL]
#       get_kernel_actions(include_0=True)  -> 5 keys, {1, 11, 121, 129} + {0}
#       get_kernel_actions(include_0=False) -> 4 keys: 1, 11, 121, 129
#       BEAM=1, DEBUG=2: "from 1 -> 1 actions", "4 -> 4 actions", "2 -> 2"
#
#     (a*b).sum(1) on 16x32                 full_shape [16,32] [GLOBAL, REDUCE]
#       get_kernel_actions(include_0=False) -> 18 keys:
#         1 11 31 62 72 92 121 122 129 130 145 146 153 154 170 193 194 218
#       BEAM=1, DEBUG=2: "18 -> 18 actions", "13 -> 13 actions", "2 -> 2"
#
#     a@b on 64x64x64                      [64,64,64] [GLOBAL, GLOBAL, REDUCE]
#       get_kernel_actions(include_0=False) -> 32
#
#   The candidate indices are reproduced ONE BY ONE by the gate, because a count
#   row that only says "4" cannot tell "the axis guard fired" from "the
#   divisibility check fired".
#
#   `ok_local_red` is the row that is allowed to be False knowledge: it is the
#   `reduces` conjunct `opt_ok` drops, and it pins that the drop is a drop.

def plus_sched() -> Sched:
  Sched.of(REN.python(), [RNG{0, O.AXIS_GLOBAL{}, 4}])

def reduce_sched() -> Sched:
  Sched.of(REN.python(), [RNG{0, O.AXIS_GLOBAL{}, 16}, RNG{0, O.AXIS_REDUCE{}, 32}])

def matmul_sched() -> Sched:
  Sched.of(REN.python(), [RNG{0, O.AXIS_GLOBAL{}, 64}, RNG{0, O.AXIS_GLOBAL{}, 64}, RNG{0, O.AXIS_REDUCE{}, 64}])

def b2u(b: Bool) -> U32:
  Bool.pick(U32, b, 1, 0)

# THE GATE MOVED TO `gates/postrange-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Every expectation in the driver is generated by calling CPython, so no row
# there is typed by hand.
