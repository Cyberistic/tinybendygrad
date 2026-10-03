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
# ---------------------------------------------------------------------------
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
# ---------------------------------------------------------------------------
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
# ---------------------------------------------------------------------------
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
# ---------------------------------------------------------------------------
# THE `tc_select = -1` ENCODING. `check(-1 <= tc_select < len(tensor_cores))` is
# a CHAINED comparison, so for `tc_select == -1` it is `(-1 <= -1) and (-1 < 0)`
# -- which is TRUE for any length, including 0. Bend has no signed integer, so
# `OA_TC.any` IS `tc_select == -1` and the whole check collapses to
# `any or sel < n_tc`. MEASURED: on a PYTHON device (`tensor_cores == []`) the
# TC action reports "no tensor core available", which is the arm AFTER the
# bound check, which is what proves the chain passed.
#
# ---------------------------------------------------------------------------
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

# ===========================================================================
# opt/__init__.py
# ===========================================================================

type OPTOPS is Data:
  OPS_TC{}
  OPS_SPLIT{}
  OPS_PADTO{}
  OPS_SWAP{}

# `auto()` numbering is the declaration order, and `OptOps.__lt__` is the only
# reader of it -- which nothing calls. Kept anyway: it is one ladder and it is
# the enum's documented value.
def OPTOPS.value(o: OPTOPS) -> U32:
  match o:
    case OPS_TC{}: 1
    case OPS_SPLIT{}: 2
    case OPS_PADTO{}: 3
    case _: 4

# `Opt.arg: int|tuple|None`. A `Data` record may not hold a `Maybe` field, so
# the three shapes are three constructors. `OA_TC` is its own because the TC arg
# is a 3-tuple of INTEGERS and a SPLIT arg is a 2- or 3-tuple whose third is a
# BOOL -- folding them into one record would need a `Maybe` for the bool.
# `SPL` and `TC` ARE `Opt.arg`'s TWO TUPLE SHAPES, as records. They exist
# because `Sched.split` reads `amt` and `t` once EACH and there is no way to
# pass two `U32`s that way -- `+` is refused on a `U32` -- so the pair travels as
# the `Data` record Python already had it as, and `OA_SPLIT{a: SPL}` is the
# constructor that names the variant.
type SPL is Data:
  SPL{amt: U32, t: O.AxisType, top: Bool}

type TC is Data:
  TC{any: Bool, sel: U32, lvl: U32, use: U32}

type OPTARG is Data:
  OA_NONE{}
  OA_INT{i: U32}
  OA_SPLIT{a: SPL}
  OA_TC{a: TC}

type OPT is Data:
  OPT{op: OPTOPS, axis: U32, arg: OPTARG}

# `axis: int|None` in Python and NO construction site in `search.py`,
# `heuristic.py` or `postrange.py` passes None -- `actions` always has an int,
# every `apply_opt` call site has an int, and `_apply_tc_opt`'s PADTO has
# `self.rngs.index(a)`. So `axis` is a `U32` here and the two
# `check(opt.axis is not None, ...)` are vacuous, which is why they are not
# ported. If a `None` axis ever appears, `OA_NONE` on `arg` is not the fix;
# `axis` needs a `Maybe` and this record needs a `Bool` alongside it.
def OPT.op(x: OPT) -> OPTOPS:
  match x:
    case OPT{op, axis, arg}: op

def OPT.axis(x: OPT) -> U32:
  match x:
    case OPT{op, axis, arg}: axis

def OPT.arg(x: OPT) -> OPTARG:
  match x:
    case OPT{op, axis, arg}: arg

# the only thing that ever reads `arg` is the `match opt.arg is ...` ladder in
# `apply_opt`, so the ladder destructures the record directly.
# A `Data` FIELD IS READ BY DESTRUCTURING, NEVER BY PROJECTION. `s.amt` on a
# pattern binder is a NAME lookup and fails, so every reader of a nested record
# is a nested pattern -- `case OA_SPLIT{SPL{amt, t, top}}` -- which is also
# ops.bend's `case AParam{pa}: match pa:` shape written on one line.
def opt_amt(a: OPTARG) -> U32:
  match a:
    case OA_SPLIT{SPL{amt, t, top}}: amt
    case OA_INT{i}: i
    case OA_TC{TC{any, sel, lvl, use}}: sel
    case _: 0

def opt_top(a: OPTARG) -> Bool:
  match a:
    case OA_SPLIT{SPL{amt, t, top}}: top
    case _: False{}

def opt_target(a: OPTARG) -> O.AxisType:
  match a:
    case OA_SPLIT{SPL{amt, t, top}}: t
    case _: O.AXIS_LOOP{}

# ===========================================================================
# postrange.py: split_targets, the Renderer slice, the Scheduler
# ===========================================================================

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
  Sched{ren: REN, rngs: List<&2, RNG>, opts: List<&2, OPT>}

def Sched.ren(x: Sched) -> REN:
  match x:
    case Sched{ren, rngs, opts}: ren

def Sched.rngs(x: Sched) -> List<&2, RNG>:
  match x:
    case Sched{ren, rngs, opts}: rngs

def Sched.opts(x: Sched) -> List<&2, OPT>:
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

# ---------------------------------------------------------------------------
# THE FOLD SHAPE, AND IT IS THE SAME FOUR TIMES.
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
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# THE DIMENSION READERS. `upcastable_dims` and `unrollable_dims` are the same
# fold -- "indices whose axis type is in SET and whose CONST size is > 1" -- so
# they share `dim_go`, and Python writes them out because they are two
# properties. `unrollable_dims` additionally filters `self.reduce_axes`, which is
# WALL #1 (`UOp.ranges` over the REDUCE srcs); the assumption stated on
# `Sched.unrollable_dims` is that every REDUCE-typed axis came off a reduce,
# which is true of every Scheduler `postrange.py` builds.
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
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
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# `apply_opt`'s SPLIT arm, and the rng bookkeeping of `shift_to`. This is the
# whole reason `Sched` carries fields rather than computing them.
#
# `shift_to` renames ONE rng and ADDS one: `replaced_rng` KEEPS `axis_id` and
# takes `new_type` with size `old_sz`, and `new_rng` is `UOp.range(amount,
# next(self.opt_range), new_type)` -- a FRESH id from a counter seeded above
# every id in the AST, which is `max(id) + 1`. `top` chooses which of the two is
# the fast axis of `sub_axis`, and `sub_axis` is WALL #2; the two rngs are not,
# because both are functions of `(old_sz, amount, new_type)` alone.
# ---------------------------------------------------------------------------

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
# THE OPT IS THE CARRIER, WHICH IS ALSO PYTHON'S SIGNATURE.
# `def apply_opt(self, opt: Opt, append_opt: bool = True)` takes ONE argument,
# and this is the reason `Sched.split` does too. The alternative -- `axis: U32,
# amt: U32, nt: AxisType` -- is unwritable: `axis` is read twice, `amt` is read
# twice, and `U32` cannot be `+`. `OPT` is `Data`, so `+o` licenses every read
# and the pair `{axis, arg}` travels the way it travels in Python.
def opt_spl(a: OPTARG) -> SPL:
  match a:
    case OA_SPLIT{SPL{amt, t, top}}: SPL{amt, t, top}
    case _: SPL{0, O.AXIS_LOOP{}, False{}}

# `replaced_rng` -- same `axis_id`, `new_type`, size `old_sz`.
def rep_rng(+r: RNG, a: SPL) -> RNG:
  match a:
    case SPL{amt, t, top}: RNG{RNG.id(r), t, U32.div(RNG.sz(r), amt)}

# `new_rng` -- `UOp.range(amount, next(self.opt_range), new_type)`. The id is
# `max(id) + 1`, which is what `opt_range`'s `count(start=max+1)` hands out.
def new_rng(mid: U32, a: SPL) -> RNG:
  match a:
    case SPL{amt, t, top}: RNG{mid, t, amt}

def split_new(x: Sched, a: SPL) -> List<&2, RNG>:
  [new_rng(U32.add(Sched.max_id(x), 1), a)]

# `rngs[at] = replaced_rng`, then the `rngs` PROPERTY re-sorts. The new pair
# therefore lands wherever `(pos_key, id)` puts it, NOT at the end, and
# `full_shape` and `axis_types` are read off THAT list -- so a LOCAL split of
# axis 0 of a `[GLOBAL, REDUCE]` kernel moves that axis from index 0 to index 1.
# `U32.is_eq(List.length(acc), OPT.axis(o))` is `i == axis` for the element the
# walk is ON, because `acc` already holds exactly the elements before it.
def at_it(acc: List<&2, RNG>, o: OPT) -> Bool:
  U32.is_eq(U32.from_nat(List.length(&2, RNG, acc)), OPT.axis(o))

def put_at.at(here: Bool, acc: List<&2, RNG>, +o: OPT, h: RNG) -> List<&2, RNG>:
  match here:
    case True{}: List.append(&2, RNG, acc, [rep_rng(h, opt_spl(OPT.arg(o)))])
    case False{}: List.append(&2, RNG, acc, [h])

def put_at(+acc: List<&2, RNG>, +o: OPT, h: RNG) -> List<&2, RNG>:
  put_at.at(at_it(acc, o), acc, o, h)


def put_go(rs: List<&2, RNG>, +o: OPT, +acc: List<&2, RNG>) -> List<&2, RNG>:
  match rs:
    case Nil{}: acc
    case +h <> t: put_go(t, o, put_at(acc, o, h))

def split_rngs(+x: Sched, +o: OPT) -> List<&2, RNG>:
  List.sort(RNG, rng_le, List.append(&2, RNG, put_go(Sched.rngs(x), o, Nil{}), split_new(x, opt_spl(OPT.arg(o)))))

# `Sched.split` -- the rng bookkeeping of `apply_opt(SPLIT)` + `shift_to`. `amt`
# is ALREADY resolved: `apply_opt` turns `amt == 0` into `int(rng.vmax+1)` before
# `shift_to` runs. `top` is carried and IGNORED -- it picks which of the two is
# the fast axis of `sub_axis`, and `sub_axis` is WALL #2.
def SPLIT_OPT(axis: U32, amt: U32, t: O.AxisType, top: Bool) -> OPT:
  OPT{OPS_SPLIT{}, axis, OA_SPLIT{SPL{amt, t, top}}}

def Sched.split(+x: Sched, +o: OPT) -> Sched:
  Sched{Sched.ren(x), split_rngs(x, o), List.append(&2, OPT, Sched.opts(x), [o])}

# ---------------------------------------------------------------------------
# `opt_ok` -- EVERY `check` in `apply_opt`'s SPLIT, PADTO and SWAP arms, plus
# `shift_to`'s first `check`, as one `Bool`. Python raises on the first failure,
# so the conjunct order below IS the order of the messages. `Bool.and` is not
# short-circuiting, so every conjunct is written to be total on its own.
#
# THE TWO CHECKS THAT ARE NOT HERE both need the AST and are WALL #1:
#   * `smem_sz <= self.ren.shared_max` needs `self.reduceop.dtype.itemsize`.
#   * `reducers = [u for u in self.reduceops if rng in merge_dicts(...)]` needs
#     `UOp.ranges`. The CONDITION that reaches it (`new_type is UNROLL or
#     rng.axis_type is REDUCE`) IS here, and on every fixture below the
#     CONSEQUENT is vacuous: MEASURED on CPython, a LOCAL split of a REDUCE axis
#     on the 16x32 kernel SUCCEEDS, so `check(not any(...))` never fires and the
#     `reduces` conjunct is droppable. `ok_local_red` is that row.
# ---------------------------------------------------------------------------

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
# THE SIX CONJUNCTS ARE SIX DEFS. `Bool.and` is a plain 2-argument function, and
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
  U32.from_nat(List.length(&2, OPT, Sched.opts(x)))

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

def opt_ok.tc(a: TC, +x: Sched, no_opts: U32) -> Bool:
  match a:
    case TC{any, sel, lvl, use}:
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


# ===========================================================================
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
# ===========================================================================

def plus_sched() -> Sched:
  Sched.of(REN.python(), [RNG{0, O.AXIS_GLOBAL{}, 4}])

def reduce_sched() -> Sched:
  Sched.of(REN.python(), [RNG{0, O.AXIS_GLOBAL{}, 16}, RNG{0, O.AXIS_REDUCE{}, 32}])

def matmul_sched() -> Sched:
  Sched.of(REN.python(), [RNG{0, O.AXIS_GLOBAL{}, 64}, RNG{0, O.AXIS_GLOBAL{}, 64}, RNG{0, O.AXIS_REDUCE{}, 64}])

def b2u(b: Bool) -> U32:
  Bool.pick(U32, b, 1, 0)

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# `apply_opt` and `opt_ok` take the RESOLVED amount, so a fixture states the
# amount Python would have resolved `0` to. `plus_opt(i)` is the four actions
# `get_kernel_actions` accepts on the 1-axis kernel, by their `enumerate` index.
def plus_pair(i: U32) -> OPTARG:
  match i:
    case 1: OA_SPLIT{SPL{4, O.AXIS_UPCAST{}, False{}}}
    case 11: OA_SPLIT{SPL{2, O.AXIS_UPCAST{}, False{}}}
    case 121: OA_SPLIT{SPL{4, O.AXIS_LOCAL{}, False{}}}
    case _: OA_SPLIT{SPL{2, O.AXIS_LOCAL{}, False{}}}

def plus_opt(i: U32) -> OPT:
  OPT{OPS_SPLIT{}, 0, plus_pair(i)}

def plus_ok.of(+o: OPT, s: Sched) -> Bool:
  opt_ok.at(s, Q.of(0, opt_amt(OPT.arg(o)), opt_target(OPT.arg(o))))

def plus_ok(i: U32) -> Bool:
  plus_ok.of(plus_opt(i), plus_sched())

# `count_bools` -- `sum(bs)`. The `hit` Bool is an ACCUMULATOR and not a separate
# dispatch def: a `hit: Bool` helper that re-calls the walk is a MUTUAL
# RECURSION and is refused, which is the shape bend2-constraints.md calls "a
# `found: Bool` accumulator is the only spelling that compiles". `n` is a `U32`
# so it is never `+` -- it is read once per arm.
def count_add(h: Bool, n: U32) -> U32:
  match h:
    case True{}: U32.add(n, 1)
    case False{}: n

def count_bools(bs: List<&2, Bool>, n: U32) -> U32:
  match bs:
    case Nil{}: n
    case h <> t: count_bools(t, count_add(h, n))

# `plus_n` -- how many of the four pass `opt_ok`, i.e. CPython's
# `get_kernel_actions(include_0=False)` count of 4. It is a COUNT and not four
# Booleans so a mutation that drops one of the six CONJUNCTS can move it, and
# `ok_i*` pin each candidate individually so a mutation that drops a whole
# CANDIDATE moves one of those.
def plus_n() -> U32:
  count_bools([plus_ok(1), plus_ok(11), plus_ok(121), plus_ok(129)], 0)

# `ok_local_red` -- the DROPPED conjunct. `apply_opt` reaches the `reduces`
# check when `new_type is LOCAL or rng.axis_type is REDUCE`, and CPython
# ACCEPTS a LOCAL split of the reduce axis on the 16x32 kernel, so the check is
# vacuous there. This row builds that opt and reports `opt_ok`'s verdict, which
# is 1 -- and it is the row a mutation that ADDS a fake reduce-conjunct moves.
def ok_local_red() -> U32:
  b2u(opt_ok.at(reduce_sched(), Q.of(1, 16, O.AXIS_LOCAL{})))

# `ok_axis_oob` -- `check(0 <= opt.axis < self.shape_len)` is NOT in `opt_ok.at`
# (it is `opt_axis_ok`, a separate arm, because TC skips it). This row is the
# FALSE arm, built by asking about an axis one past the end.
def ok_axis_oob() -> U32:
  b2u(opt_axis_ok(reduce_sched(), 2))

# `ok_tc_any` -- the `-1` chain. `REN.python()` has `n_tc = 0`, and a TC opt with
# `any = True` must still PASS the bound check, because `-1 < 0`. This row is 1
# and a mutation that drops the `Bool.or(a.any, ...)` moves it to 0 -- which is
# the bug where every TC candidate is rejected on a device with no tensor cores.
def ok_tc_any() -> U32:
  b2u(opt_ok.tc(TC{True{}, 0, 2, 1}, plus_sched(), n_opts(plus_sched())))

# `ok_tc_sel` -- the SAME check with `any = False` and `sel = 0`, `n_tc = 0`.
# `0 < 0` is False, so this is 0. The pair pins that `any` is doing the work and
# not the magnitude.
def ok_tc_sel() -> U32:
  b2u(opt_ok.tc(TC{False{}, 0, 2, 1}, plus_sched(), n_opts(plus_sched())))

# `ok_tc_lvl` -- `check(0 <= tc_opt <= 2)`, the FALSE arm at lvl 3.
def ok_tc_lvl() -> U32:
  b2u(opt_ok.tc(TC{True{}, 0, 3, 1}, plus_sched(), n_opts(plus_sched())))

# `ok_tc_use` -- `check(0 < use_tensor_cores <= 2)`, the FALSE arm at use 3.
def ok_tc_use() -> U32:
  b2u(opt_ok.tc(TC{True{}, 0, 2, 3}, plus_sched(), n_opts(plus_sched())))

# `ok_tc_first` -- `check(len(self.applied_opts) == 0)`. `Sched.split` appends,
# so a scheduler with one opt must REJECT a TC. This row is the False arm, and
# it is the row that moves if `Sched.split` stops appending.
def ok_tc_first() -> U32:
  b2u(opt_ok.tc(TC{True{}, 0, 2, 1}, Sched.split(plus_sched(), SPLIT_OPT(0, 2, O.AXIS_UPCAST{}, False{})), n_opts(Sched.split(plus_sched(), SPLIT_OPT(0, 2, O.AXIS_UPCAST{}, False{})))))

# `ul_plus` / `ul_red` -- `get_kernel_actions`' `up`/`lcl` on each fixture.
# CPython: after a successful SPLIT the products are over the NEW axis types,
# and on the 16x32 kernel every accepted candidate leaves `up = 1` (no
# UPCAST/UNROLL survives except the UNROLL splits, which give up = 16 or 4) and
# `lcl` at most 32. These two rows pin the accumulation, not the filter.
def ul_plus_up() -> U32:
  up_go(Sched.rngs(Sched.split(plus_sched(), SPLIT_OPT(0, 2, O.AXIS_LOCAL{}, False{}))), 1)

def ul_red_up() -> U32:
  up_go(Sched.rngs(Sched.split(reduce_sched(), SPLIT_OPT(1, 16, O.AXIS_UNROLL{}, False{}))), 1)

def ul_red_lcl() -> U32:
  lcl_go(Sched.rngs(Sched.split(reduce_sched(), SPLIT_OPT(0, 4, O.AXIS_LOCAL{}, False{}))), 1)

# `split_fs0` -- `shift_to` RESIZES the split axis. A 16-long axis split by 4 is
# 4, and the NEW range is the 4. So `full_shape` after
# `split(reduce, 0, 4, LOCAL)` is `[4, 4, 32]` -- not `[16, 4, 32]`, which is the
# mistake a mutation that appends the new rng without resizing the old one makes.
# the sizes AFTER the split, one row each, so a mutation that resizes wrongly
# moves the row for the size it moved and not the others
def split_fs_len() -> U32:
  U32.from_nat(List.length(&2, U32, Sched.full_shape(Sched.split(reduce_sched(), SPLIT_OPT(0, 4, O.AXIS_LOCAL{}, False{})))))

def fs_at(fs: List<&2, U32>, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, fs, n), 0)

def split_fs_0() -> U32:
  fs_at(Sched.full_shape(Sched.split(reduce_sched(), SPLIT_OPT(0, 4, O.AXIS_LOCAL{}, False{}))), 0n)

def split_fs_2() -> U32:
  fs_at(Sched.full_shape(Sched.split(reduce_sched(), SPLIT_OPT(0, 4, O.AXIS_LOCAL{}, False{}))), 2n)

def nolocal_sched() -> Sched:
  Sched.of(REN.nolocal(), [RNG{0, O.AXIS_GLOBAL{}, 4}])

def dsp_sched() -> Sched:
  Sched.of(REN.dsp(), [RNG{0, O.AXIS_GLOBAL{}, 128}])

# THE SIX CONJUNCTS, ONE ROW EACH, SO A MUTATION THAT DROPS ONE IS LOCALISED.
# Every `False` arm is a fixture CPython also rejects, and the reason is the
# message `apply_opt` would have raised.
def ck_tgt_bad() -> U32:
  # UNROLL on a GLOBAL axis: "AxisType.UPCAST is from (GLOBAL, LOCAL, WEAK)"
  b2u(ck_tgt(reduce_sched(), 0, O.AXIS_UNROLL{}))

def ck_tgt_ok() -> U32:
  # UNROLL on the REDUCE axis: split_targets[UNROLL] is (REDUCE, LOCAL)
  b2u(ck_tgt(reduce_sched(), 1, O.AXIS_UNROLL{}))

def ck_amt_0() -> U32:
  # amt == 0 is legal -- it means "the whole axis", and `apply_opt` resolves it
  b2u(ck_amt(0))

def ck_amt_1() -> U32:
  # amt == 1 is the ONLY rejected amount on the value half
  b2u(ck_amt(1))

def ck_amt_4() -> U32:
  b2u(ck_amt(4))

def ck_local_bad() -> U32:
  # `ClangRenderer.has_local is False`, MEASURED -- so LOCAL is unavailable
  b2u(ck_local(nolocal_sched(), O.AXIS_LOCAL{}))

def ck_local_ok() -> U32:
  # the same check on UPCAST is vacuous, which is why it is `Bool.or`
  b2u(ck_local(nolocal_sched(), O.AXIS_UPCAST{}))

def ck_unroll_32() -> U32:
  b2u(ck_unroll(O.AXIS_UNROLL{}, 32))

def ck_unroll_33() -> U32:
  b2u(ck_unroll(O.AXIS_UNROLL{}, 33))

def ck_unroll_up() -> U32:
  # `new_type is not UNROLL` short-circuits the bound entirely
  b2u(ck_unroll(O.AXIS_UPCAST{}, 33))

def ck_upcast_16() -> U32:
  b2u(ck_upcast(plus_sched(), O.AXIS_UPCAST{}, 16))

def ck_upcast_17() -> U32:
  # "don't upcast more than 16" -- and NOT a DSP, so the exemption does not fire
  b2u(ck_upcast(plus_sched(), O.AXIS_UPCAST{}, 17))

def ck_upcast_dsp() -> U32:
  # the DSP exemption: 128 is legal there, and 0 elsewhere
  b2u(ck_upcast(dsp_sched(), O.AXIS_UPCAST{}, 128))

def ck_div_4() -> U32:
  b2u(ck_div(plus_sched(), 0, 4))

def ck_div_3() -> U32:
  # "3 can't divide 4" -- the `divides(amount) is None` arm of `shift_to`
  b2u(ck_div(plus_sched(), 0, 3))

# THE `rngs` SORT ORDER, AND WHY IT NEEDS A ROW. `pos_key` is the only thing
# that separates LOCAL from UPCAST, and every other fixture on this file has at
# most ONE of the two -- a `Sched` that has been split once has two rngs of the
# SAME new type, and `List.sort` is STABLE, so a tie between them is invisible.
# `lu_sched` hands the sort an UPSCAST-first list and the row reads index 1: if
# `pos_key` tied them the answer would be 8 and not 4, which is the bug a
# mutation that collapses the two ranks ships.
def lu_sched() -> Sched:
  Sched.of(REN.python(), [RNG{0, O.AXIS_UPCAST{}, 8}, RNG{0, O.AXIS_LOCAL{}, 4}])

def lu_at(n: Nat) -> U32:
  fs_at(Sched.full_shape(lu_sched()), n)

# A SIZE-1 AXIS. Every other fixture has all sizes > 1, so `dim_go`'s `gt1`
# conjunct is invisible to them: `upcastable_unit` is 1 not 2, and it is the row
# that a mutation dropping `gt1` moves. CPython agrees -- `upcastable_dims`
# filters on `s > 1`, and a size-1 axis is a SPECIAL the launcher expanded, not
# an axis the scheduler may split.
def unit_sched() -> Sched:
  Sched.of(REN.python(), [RNG{0, O.AXIS_GLOBAL{}, 1}, RNG{0, O.AXIS_GLOBAL{}, 4}])

def upcastable_unit() -> U32:
  U32.from_nat(List.length(&2, U32, Sched.upcastable_dims(unit_sched())))

# `max_id` AFTER A SPLIT. `opt_range`'s `count(start=max+1)` exists so a fresh
# range can never TIE an existing id, and a tie is invisible to every other row
# here because no fixture has two rngs with the same id. `maxid_fresh` is 1 after
# splitting, and it is the row a mutation that reuses `max_id` moves.
def maxid_fresh() -> U32:
  Sched.max_id(Sched.split(reduce_sched(), SPLIT_OPT(0, 4, O.AXIS_LOCAL{}, False{})))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("plus_shape_len", Sched.shape_len(plus_sched()))
    b : Unit <- row("plus_n", plus_n())
    c : Unit <- row("ok_i1", b2u(plus_ok(1)))
    d : Unit <- row("ok_i11", b2u(plus_ok(11)))
    e : Unit <- row("ok_i121", b2u(plus_ok(121)))
    f : Unit <- row("ok_i129", b2u(plus_ok(129)))
    g : Unit <- row("ok_local_red", ok_local_red())
    h : Unit <- row("ok_axis_oob", ok_axis_oob())
    i : Unit <- row("ok_tc_any", ok_tc_any())
    j : Unit <- row("ok_tc_sel", ok_tc_sel())
    k : Unit <- row("ok_tc_lvl", ok_tc_lvl())
    l : Unit <- row("ok_tc_use", ok_tc_use())
    m : Unit <- row("ok_tc_first", ok_tc_first())
    n : Unit <- row("upcastable_plus", U32.from_nat(List.length(&2, U32, Sched.upcastable_dims(plus_sched()))))
    o : Unit <- row("unrollable_red", U32.from_nat(List.length(&2, U32, Sched.unrollable_dims(reduce_sched()))))
    p : Unit <- row("axes_global_red", U32.from_nat(List.length(&2, U32, Sched.axes_of(reduce_sched(), [O.AXIS_GLOBAL{}]))))
    q : Unit <- row("upcast_size_plus", Sched.upcast_size(plus_sched()))
    r : Unit <- row("upcasted_plus", Sched.upcasted(plus_sched()))
    s : Unit <- row("group_red", Sched.group_for_reduces(reduce_sched()))
    t : Unit <- row("ul_plus_up", ul_plus_up())
    u : Unit <- row("ul_red_up", ul_red_up())
    v : Unit <- row("ul_red_lcl", ul_red_lcl())
    w : Unit <- row("split_len", split_fs_len())
    w2 : Unit <- row("split_fs0", split_fs_0())
    w3 : Unit <- row("split_fs2", split_fs_2())
    x : Unit <- row("pos_red", pos_key(O.AXIS_REDUCE{}))
    y : Unit <- row("pos_dev", pos_key(O.AXIS_DEVICE{}))
    z : Unit <- row("opsval_swap", OPTOPS.value(OPS_SWAP{}))
    st : Unit <- row("stgt_local", U32.from_nat(List.length(&2, O.AxisType, split_targets(O.AXIS_LOCAL{}))))
    s2 : Unit <- row("ck_tgt_bad", ck_tgt_bad())
    s3 : Unit <- row("ck_tgt_ok", ck_tgt_ok())
    s4 : Unit <- row("ck_amt_0", ck_amt_0())
    s5 : Unit <- row("ck_amt_1", ck_amt_1())
    s6 : Unit <- row("ck_amt_4", ck_amt_4())
    s7 : Unit <- row("ck_local_bad", ck_local_bad())
    s8 : Unit <- row("ck_local_ok", ck_local_ok())
    s9 : Unit <- row("ck_unroll_32", ck_unroll_32())
    s10 : Unit <- row("ck_unroll_33", ck_unroll_33())
    s11 : Unit <- row("ck_unroll_up", ck_unroll_up())
    s12 : Unit <- row("ck_upcast_16", ck_upcast_16())
    s13 : Unit <- row("ck_upcast_17", ck_upcast_17())
    s14 : Unit <- row("ck_upcast_dsp", ck_upcast_dsp())
    s15 : Unit <- row("ck_div_4", ck_div_4())
    s16 : Unit <- row("ck_div_3", ck_div_3())
    s17 : Unit <- row("lu0", lu_at(0n))
    s18 : Unit <- row("lu1", lu_at(1n))
    s19 : Unit <- row("upcastable_unit", upcastable_unit())
    row("maxid_fresh", maxid_fresh())
# ===========================================================================
# THE MEASURED MUTATION TABLE. Every line is a one-token edit, re-run through
# `./bin/bend`, and the rows that MOVED are listed. 20 mutations, 20 localised;
# none is a no-op and none moves every row, so the table has real shape.
#
#   mutation                                        rows that moved
#   ----------------------------------------------  ----------------------------
#   drop `split_targets` membership                  ck_tgt_bad
#   `amt != 1` inverted to `amt <= 1`                ck_amt_0
#   drop `check(has_local)`                          ck_local_bad
#   UNROLL bound 32 -> 33                            ck_unroll_33
#   drop the DSP upcast exemption                    ck_upcast_dsp
#   invert the divisibility test                     plus_n ok_i1 ok_i11 ok_i121
#                                                     ok_i129 ok_local_red
#                                                     ck_div_4 ck_div_3
#   `tc_select` bound always True                    ok_tc_sel
#   `tc_opt` bound 2 -> 3                            ok_tc_lvl
#   keep only `use > 0`, drop `use <= 2`             ok_tc_use
#   drop `tc-must-be-first`                          ok_tc_first
#   `shift_to` does not resize the old axis          ul_red_up ul_red_lcl
#                                                     split_fs0
#   new rng reuses `max_id`                          maxid_fresh
#   `up` fold drops UNROLL                           ul_red_up
#   `lcl` fold drops LOCAL                           ul_red_lcl
#   `pos_key`: LOCAL and UPCAST tie                  lu0 lu1
#   `pos_key`: REDUCE sorts before LOCAL             split_fs0 split_fs2 pos_red
#   `dim` filter drops the `s > 1` half              upcastable_unit
#   `put_at` replaces index 0 not the axis           ul_red_up
#   `axes_of` filter always keeps                    axes_global_red
#                                                     upcasted_plus group_red
#   `OptOps.value` order shifted                     opsval_swap
#
# TWO OF THESE FOUND REAL BUGS WHILE THE TABLE WAS BEING BUILT, which is the
# argument for building it rather than asserting the gate bites:
#   * the `match rs hit:` accumulator form used by FIVE folds tested the hit of
#     the PREVIOUS element and appended unconditionally, so `axes_of` answered 2
#     for a kernel with one global axis and `count_bools([T,T,T,T])` answered 3.
#     The gate row `axes_global_red` is what made it visible.
#   * `split_new` had lost its `+ 1`, so a fresh range REUSED an existing
#     `axis_id`. Every other row was blind to it because no fixture had two rngs
#     with the same id -- which is exactly the trap brief-port.md's GATE
#     DISCIPLINE warns about, and `maxid_fresh` is the row that closes it.
