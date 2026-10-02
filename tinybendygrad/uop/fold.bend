# fold.bend -- the derived properties of tinygrad/uop/ops.py, as ONE topological
# fold over the arena.
#
# WHAT THIS FILE IS. `ops.bend` builds the arena: a UOp is a `U32` index into an
# append-only `List<Node>`, so every property read goes through the store. That
# store is what stops the property folds -- a self-call must pass a FIELD of its
# own parameter and the arena's field is a U32 read back out of a store -- and
# mutual recursion is refused, and `dtype_from_uop` <-> `_shape` <->
# `simplify()` -> `graph_rewrite` -> the rules -> `dtype` is a cycle.
#
# THE FIX is the shape `toposort` already has in `ops.bend`: ONE def that walks
# the graph in topological order, so a node is answered only after every node it
# reads is. Python's `recursive_property` (ops.py:218) replaces
# `functools.cached_property` in recursive UOp functions to prevent
# RecursionError; this is the same answer with no recursion at all. The dependency
# graph of the fold is a DAG BY CONSTRUCTION rather than by discipline, and
# `graph_rewrite` is not called, so nothing in the rewrite engine can call back
# into this file.
#
# dtype and shape are answered TOGETHER, as one `DtShape`, because they read each
# other -- `_shape`'s CALL/INS/BITCAST arms read `self.dtype`, and
# `dtype_from_uop`'s INDEX arm reads `b.shape` -- and because a pair is what a
# caller wants. The other properties keep their own `match op`, which is what
# Python has: `device`, `addrspace`, `base` and `ended_ranges` are separate
# properties there and separate defs here. `derived` is the one place they are
# assembled, and it is the only def that knows about all of them.
#
# THE FIVE MOVEMENT ARMS ARE LANDED, and THREE OF THEM WERE NOT BEHIND THE WALL THE
# TODO LIST RECORDED FOR THEM. It said EXPAND, PERMUTE and FLIP wait on
# "`marg` -> `as_shape` -> `ssimplify`", which is TRUE of `marg`'s first two arms and
# FALSE of the other two ops: `marg` for PERMUTE and FLIP is `self.arg` (ops.py:818),
# the arena's `ATuple` of plain indices, so neither reads `as_shape` at all. They were
# answerable from the day the arena existed. `expand_ds`, `pad_ds`, `shrink_ds`,
# `perm_ds` and `flip_ds` are the five arms; UNSHARD still defers, and it defers on
# `vmax` rather than on `ssimplify`.
#
# PAD AND SHRINK ARE ONE WALK WITH A `Bool`, not two arms, because their checks differ
# only in which of the same three numbers is added to which -- `o+s<=sz` against
# `o+sz<=s` -- and both answer the sizes. Mutation M2 exchanges the two and moves five
# rows; that is the measurement that the `Bool` is load-bearing.
#
# THE `ssimplify` WALL IS STILL REAL, in one place, and it is measured rather than
# assumed: `as_shape`'s `s.val if s.op is Ops.CONST else ssimplify(s)` meets a src
# that is not a CONST, and CPython then ANSWERS a shape holding a UOp where the fold
# refuses. `mv_expsym` is that row -- the one line of this file's gate that disagrees
# with CPython, and it disagrees on purpose, with the divergence recorded in the
# oracle rather than smoothed into an agreeing row.
#
# THE ARENA IS A DAG BY CONSTRUCTION -- `UOp.make` only ever names src indices
# already in the list, so every src index is strictly less than its consumer's,
# and the range graph's back-edges are `Ops.BACKEDGE` MARKER nodes naming a range
# built before them -- so `Arena.next(ar) + edges` steps always suffice
# (`Kahn.budget`) and Kahn's incomplete branch is unreachable for any arena this
# file can build. The branch is still there and still total, because a node can
# also fail to be answered by a rule this file does not port (the deferred arms of
# `dt_shape`, at the bottom), and a fold that cannot say "I do not know" is not a
# fold.
#
# WHAT A PYTHON `raise` BECOMES, uniformly: the node is NOT answered. One rule at
# every `raise` in `dtype_from_uop` and `_shape`, and it is why the per-node answer
# is a `Maybe`. Two questions, two types: `None` inside a `Derived` field is "this
# property has no value" (Python's own `None`), and no entry in the table is "this
# fold cannot answer this node".
#
# THE COST, accepted rather than worked around:
#   * READS ARE O(n). The resolved table is a `List`, so a lookup is a fold and the
#     whole fold is O(n^2) in arena size. `Array<T>` would be O(1) and cannot be
#     used: `Array.get` computes `i & (n-1)`, so `Array.set` cannot grow a table.
#     Slow and checkable beats fast and unprovable.
#   * `graph_rewrite` IS NOT HERE and nothing here may call it.
#
# `_min_max` HAS MOVED, AND IT MOVED IN THE ORDER THE TABLE DECIDES.
# The i64 arithmetic landed first, then the WIDTH was settled by measurement (a sign bit
# plus an UNSIGNED 64-bit magnitude, because `uint64.max` = 2**64-1 does not fit a signed
# word and `Nat` refuses past 2**48-1), and that left three pieces. All three are now here,
# in this order:
#
#   1. `int(x).bit_length()` (ops.py:1110) -- SOLVED, NOT ROUTED AROUND. The previous unit
#      recorded it as a structural wall and the reasoning was sound: a zero test cannot be a
#      `match` scrutinee (Bend refuses a call), a growing counter cannot lead a self-call
#      (each argument must pass unchanged until one shrinks, and a `U32` that HALVES does
#      not count), and the test and the step cannot be two defs (mutual recursion refused).
#      Every one of those is a fact about a WALK. **This is not a walk: it is a five-stage
#      binary-search ladder**, and the wall was ADDITIVE COUNTING rather than the language.
#      `bit_length(x)` is the sum of `k` over the literal thresholds `2**16, 2**8, 2**4,
#      2**2, 2**1` that `x` meets, plus one if the residue is nonzero -- so "am I done" is
#      answered by five literal thresholds and NEVER by a test on the value at all. No
#      recursion, no fuel, no accumulator, and the shift amounts are LITERALS, which is what
#      bend2-constraints demands of a bit-packer.
#   2. THE DTYPE LIMITS, hoisted under the same notice as the lattice below.
#   3. THE OP TABLE, `mm.lift`, PURE over `(op, srcs, arg, dtype)` with the src intervals
#      handed IN. That purity is the decision that made the table gateable at all: every
#      fixture in this file's `lf_*` gate has `CONST` srcs, so the table is handed a
#      `List<&2, Bnd2>` it did not have to compute, and CPython builds the same graph and is
#      asked the same question. 127 rows, byte-identical.
#
# THE ORDER WAS RIGHT AND THE PAYOFF IS MEASURABLE: because the table is pure, its 127 rows
# and its 35-entry mutation table came BEFORE any arena was touched, and the gate found
# five defects that no amount of reading would have (the signed order collapsed to two cases;
# SUB's halves uncrossed; the mask width and the masked value exchanged; the shift AMOUNT read
# as a bit WIDTH; and `Ops.AND`'s second arm being unreachable). Two of the five are visible
# in the mutation table at the foot of this file; the other three are in the section headers.
#
# THE LATTICE IS HOISTED, with a notice. `promo_dtype` needs `least_upper_dtype`
# (dtype.py:193), which `./../dtype.bend` already has in a form this file cannot
# reach: that file's fp16/bf16/fp8/i64 conversions are C effects, so importing it
# makes the checker print "14 defs rely on unsafe or foreign code" and exit 1 for
# ANY importer. The lattice is twenty integers and a lowest-set-bit, all of it
# pure, so the four defs it needs are here, under dtype.bend's own masks and its
# own rank order. When dtype.bend becomes importable these go back there and the
# import comes with them; nothing else in this file changes, because `promo_dtype`
# is the only caller.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./ops.bend as O

# ===========================================================================
# THE PROMOTION LATTICE -- tinygrad/dtype.py:180-204, hoisted. See the header.
#
# dtype.py spells `least_upper_dtype` as
# `min(set.intersection(*recursive_parents(d) for d in ds))`. The twenty dtypes
# are totally ordered by dtype.py's own `__lt__` (priority, bitsize, name, fmt),
# so bit i of a mask stands for "rank i is a recursive parent" and the meet is the
# lowest set bit of the two masks ANDed. The masks are `_get_recursive_parents`
# written down and the rank order is dtype.bend's, which is the `__lt__` order
# with void last on an empty mask -- dtype.py raises KeyError there, because void
# is not in its lattice at all.
#
# The twenty dtypes are told apart by LITERAL record patterns, which is why these
# are twenty short arms rather than twenty equality comparisons: a `match` on a
# `Dt` may use its fields directly. `void` is the `case _` arm, and its empty mask
# is the one totalization this makes.
# ===========================================================================

def promo_mask(d: S.Dt) -> U32:
  match d:
    case S.Dt{0, 1, S.CBool{}, _}: 524287
    case S.Dt{0, 800, S.CWeakInt{}, _}: 524286
    case S.Dt{1, 8, S.CSint{}, _}: 523604
    case S.Dt{2, 8, S.CUint{}, _}: 524280
    case S.Dt{3, 16, S.CSint{}, _}: 523600
    case S.Dt{4, 16, S.CUint{}, _}: 524256
    case S.Dt{5, 32, S.CSint{}, _}: 523584
    case S.Dt{6, 32, S.CUint{}, _}: 524160
    case S.Dt{7, 64, S.CSint{}, _}: 523520
    case S.Dt{8, 64, S.CUint{}, _}: 523776
    case S.Dt{9, 800, S.CWeakFloat{}, _}: 523264
    # THE THREE FP8 NAMES ARE `Dt`'s FOURTH FIELD AND NOT ITS PRIORITY: `fp8e4m3` and
    # `fp8e4m3fnuz` are BOTH pri 10, and `fp8e5m2` is pri 11 with `fp8e5m2fnuz`, so the
    # name is the only discriminator and these three arms are the file's ONE dependency on
    # a dtype's SPELLING. Measured: the `float8_e4m3` spelling answered `NInf`/`PInf` on
    # every fp8 row the moment `LAWS/spec.bend` was renamed to `fp8e4m3`, with the whole
    # file still `ALL PROOFS CHECK` -- a NAME match that stops matching is silent, and
    # `case _:` (the `bnd_flt` fall-through) is what absorbed it. `promo_mask` above is
    # the same exposure and it broke in the same commit.
    case S.Dt{10, 8, S.CFloat{}, "fp8e4m3"}: 493568
    case S.Dt{10, 8, S.CFloat{}, "fp8e4m3fnuz"}: 495616
    case S.Dt{11, 8, S.CFloat{}, "fp8e5m2"}: 499712
    case S.Dt{11, 8, S.CFloat{}, "fp8e5m2fnuz"}: 507904
    case S.Dt{12, 16, S.CFloat{}, _}: 425984
    case S.Dt{13, 16, S.CFloat{}, _}: 458752
    case S.Dt{14, 32, S.CFloat{}, _}: 393216
    case S.Dt{15, 64, S.CFloat{}, _}: 262144
    case _: 0

# the rank -> dtype half of the same order
def dt_by_rank(r: Nat) -> S.Dt:
  match r:
    case 0n: S.boolean()
    case 1n: S.weakint()
    case 2n: S.int8()
    case 3n: S.uint8()
    case 4n: S.int16()
    case 5n: S.uint16()
    case 6n: S.int32()
    case 7n: S.uint32()
    case 8n: S.int64()
    case 9n: S.uint64()
    case 10n: S.weakfloat()
    case 11n: S.fp8e4m3()
    case 12n: S.fp8e4m3fnuz()
    case 13n: S.fp8e5m2()
    case 14n: S.fp8e5m2fnuz()
    case 15n: S.half()
    case 16n: S.bfloat16()
    case 17n: S.single()
    case _: S.double()

# the index of the lowest set bit. `m` is never 0 for a non-void dtype, because
# `bool` is a recursive parent of every dtype, so every non-void mask has bit 0.
def lowest(+m: U32) -> Nat:
  U32.log2(U32.and(m, U32.sub(0, m)))

# a zero mask is dtype.py's KeyError, which is what any pair naming `void` gives
def least_upper.pick(ok: Bool, +m: U32) -> Maybe<&1, S.Dt>:
  match ok:
    case True{}: None{}
    case False{}: Some{dt_by_rank(lowest(m))}

def least_upper(+ma: U32, mb: U32) -> Maybe<&1, S.Dt>:
  least_upper.pick(U32.is_zero(ma), U32.and(ma, mb))

# the same meet as a value: `void` is the bottom, so it is also the fold's identity
def least_upper.of(a: S.Dt, b: S.Dt) -> S.Dt:
  Maybe.default(&1, S.Dt, least_upper(promo_mask(a), promo_mask(b)), S.void())

# `min` over an intersection is associative, so the fold and the n-ary call agree
def least_upper_dtypes.go(ds: List<&2, S.Dt>, a: S.Dt) -> S.Dt:
  match ds:
    case Nil{}: a
    case h <> t: least_upper_dtypes.go(t, least_upper.of(a, h))

def least_upper_dtypes(ds: List<&2, S.Dt>) -> S.Dt:
  match ds:
    # dtype.py's `set.intersection()` of nothing is a TypeError. The one
    # reachable call is `promo_dtype(src[1:])` on a WHERE with no operands, and
    # void is the honest total answer for the dtype of nothing.
    case Nil{}: S.void()
    case h <> t: least_upper_dtypes.go(t, h)

# promo_dtype -- ops.py:120. `dts[0] if all_same(dts) else
# least_upper_dtype(*dts)`: when the dtypes agree the lattice's minimum IS
# `dts[0]`, so the `all_same` short-circuit is not a second answer to write.
def promo_dtype(ds: List<&2, S.Dt>) -> S.Dt:
  least_upper_dtypes(ds)

# least_upper_float -- dtype.py:195. `weakfloat if dt is weakint else dt if
# is_float(dt) else least_upper_dtype(dt, default_float)`, and DEFAULT_FLOAT is
# float32, which no ops.py caller of this ever overrides.
def least_upper_float.cls(cls: S.Cls, dt: S.Dt) -> Maybe<&1, S.Dt>:
  match cls:
    case S.CWeakInt{}: Some{S.weakfloat()}
    case S.CFloat{}: Some{dt}
    case _: least_upper(promo_mask(dt), promo_mask(S.single()))

def least_upper_float(+dt: S.Dt) -> S.Dt:
  Maybe.default(&1, S.Dt, least_upper_float.cls(S.Dt.cls(dt), dt), S.void())

def unary_dt.go(bad: Bool, dt: S.Dt) -> S.Dt:
  match bad:
    case True{}: S.boolean()
    case False{}: least_upper_float(dt)

# ===========================================================================
# THE SHAPE ALGEBRA. `sint` is ops.py:1925's `int|UOp` and `ops.bend` already
# spells it as `O.Sint`, so a dim here is `O.Sint` and nothing else: the
# distinction between "the literal 4" and "the uop that may be 4" is exactly what
# `_broadcast_shape`'s `isinstance(s, UOp) or s != 1` filter and `_shape`'s
# `isinstance(ps[-1], int)` both read.
# ===========================================================================

def one_i64() -> H.I64:
  H.i64_of_i32(1)

def bcast_dim.is_uop_or_ne_1(s: O.Sint) -> Bool:
  match s:
    case O.SU{u}: True{}
    case O.SI{i}: Bool.not(O.eq_i64(i, one_i64()))

# a small count as a `sint`. Every count that reaches a shape is a dim or a length,
# so it is under 2^31 and `i64_of_i32`'s sign extension is exact.
def sint_of(+n: U32) -> O.Sint:
  # `ops.bend`'s `SInt.of`, written as its own body: a `Type.of` def does not
  # resolve through a module alias, so the constructor is spelled here.
  O.SI{H.i64_of_i32(n)}

def sint_one() -> O.Sint:
  sint_of(1)

# A COUNT AND THE LIST IT COUNTS, as one value: Bend SPENDS a list when it reads
# it, so a fold step carrying both needs a Data record. `Sized.n` and `Sized.s`
# are accessors because Bend has no projections.
type Sized is Data:
  Sized{n: Nat, s: List<&2, O.Sint>}

def Sized.n(x: Sized) -> Nat:
  match x:
    case Sized{n, s}: n

def Sized.s(x: Sized) -> List<&2, O.Sint>:
  match x:
    case Sized{n, s}: s

# `List.append` is `xs ++ ys` (base.bend:822), so this accumulator is ALREADY in
# input order and the walk ends with no `List.reverse`: the reverse that used to be
# here turned a list already in ops.py's order into its own mirror, which every
# COUNT survived -- `Sized.n` is unaffected -- and every positional read did not.
# Same anti-pattern, same defect, one layer down from `srcs.go`.
def sized.go(s: List<&2, O.Sint>, n: Nat, acc: List<&2, O.Sint>) -> Sized:
  match s:
    case Nil{}: Sized{n, acc}
    case h <> t: sized.go(t, 1n+n, List.append(&2, O.Sint, acc, [h]))

def sized(s: List<&2, O.Sint>) -> Sized:
  sized.go(s, 0n, Nil{})

# `(1,)*(max_dim-len(s))+s`
def ones.go(+n: Nat, acc: List<&2, O.Sint>) -> List<&2, O.Sint>:
  match n:
    case 0n: acc
    case 1n+p: ones.go(p, List.append(&2, O.Sint, acc, [sint_one()]))

# `(1,)*(max_dim-len(s))+s`, and a `Sized` again because the walk hands a length on
def pad_to(+x: Sized, +m: Nat) -> Sized:
  sized(List.append(&2, O.Sint, ones.go(Nat.sub(m, Sized.n(x)), Nil{}), Sized.s(x)))

# THE SHAPES AND THE LONGEST OF THEM, as one value, for the same reason `Sized` is
# one value, so the walk that collects the shapes is the walk that measures them.
type Shapes is Data:
  Shapes{ds: List<&2, Sized>, m: Nat}

def Shapes.ds(sh: Shapes) -> List<&2, Sized>:
  match sh:
    case Shapes{ds, m}: ds

def Shapes.m(sh: Shapes) -> Nat:
  match sh:
    case Shapes{ds, m}: m

def _align_left.go(ss: List<&2, Sized>, +m: Nat, acc: List<&2, Sized>) -> List<&2, Sized>:
  match ss:
    case Nil{}: acc
    case s <> t: _align_left.go(t, m, List.append(&2, Sized, acc, [pad_to(s, m)]))

def _align_left(+sh: Shapes) -> List<&2, Sized>:
  _align_left.go(Shapes.ds(sh), Shapes.m(sh), Nil{})

def param_shape.img(img: O.Img) -> List<&2, O.Sint>:
  match img:
    case O.Img{h, w}: [sint_of(h), sint_of(w), sint_of(4)]

def param_shape.size(m: Maybe<&2, U32>) -> List<&2, O.Sint>:
  match m:
    case Some{n}: [sint_of(n)]
    case None{}: Nil{}

def param_shape.of.img(img: Maybe<&2, O.Img>, size: Maybe<&2, U32>) -> List<&2, O.Sint>:
  match img:
    case Some{i}: param_shape.img(i)
    case None{}: param_shape.size(size)

def param_shape.pa(+pa: O.ParamArg) -> List<&2, O.Sint>:
  param_shape.of.img(O.ParamArg.image(pa), O.ParamArg.size(pa))

def param_shape.of(arg: O.Arg) -> List<&2, O.Sint>:
  match arg:
    case O.AParam{pa}: param_shape.pa(pa)
    case _: Nil{}

def param_shape(arg: O.Arg) -> List<&2, O.Sint>:
  param_shape.of(arg)

# `SInt` equality. A `SU` is an arena index, so the comparison there is the
# identity `UOp.__eq__` has: UOps are hash-consed, so structurally identical UOps
# are the same object and equality can be identity.
def eq_sint(+x: O.Sint, y: O.Sint) -> Bool:
  match x:
    case O.SI{i}:
      match y:
        case O.SI{j}: O.eq_i64(i, j)
        case _: False{}
    case O.SU{u}:
      match y:
        case O.SU{v}: U32.is_eq(u, v)
        case _: False{}

# is_image_shape -- helpers.py:37, `shape is not None and len(shape) == 3 and
# shape[-1] == 4`, over the resolved dims rather than helpers.bend's `Nest`.
# TODO(p3) helpers.py:37 def is_image_shape -- `four` compares against `sint_one()`,
#   so it tests `shape[-1] == 1` and answers False for `(32,32,4)`, which Python says
#   True. MEASURED by `.agents/slop/notes/probe-sized-consumers.bend`; see the mutation
#   table at the bottom of this file. `helpers.bend`'s own `is_image_shape.tail` gets
#   it right (`U32.is_eq(x, 4)`). Wants its own gate row, so this file's `sized` fix
#   keeps moving exactly one row.
def is_image_shape.four(last: Maybe<&2, O.Sint>) -> Bool:
  match last:
    case Some{d}: eq_sint(d, sint_one())
    case None{}: False{}

def is_image_shape.ds(+n: Nat, last: Maybe<&2, O.Sint>) -> Bool:
  match n:
    case 3n: is_image_shape.four(last)
    case _: False{}

def is_image_shape.of(+x: Sized) -> Bool:
  is_image_shape.ds(Sized.n(x), List.last(&2, O.Sint, Sized.s(x)))

def is_image_shape(m: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  match m:
    case None{}: False{}
    case Some{ds}: is_image_shape.of(sized(ds))

def eq_sints(xs: List<&2, O.Sint>, ys: List<&2, O.Sint>) -> Bool:
  match xs ys:
    case Nil{} Nil{}: True{}
    case x <> t y <> u: Bool.and(eq_sint(x, y), eq_sints(t, u))
    case Nil{} _ <> _: False{}
    case _ <> _ Nil{}: False{}

# `xs[n:]` and `xs[:n]` -- `List.drop` and `List.take`
def take_n(xs: List<&2, O.Sint>, +n: Nat) -> List<&2, O.Sint>:
  List.take(&2, O.Sint, xs, n)

# `a.shape[:-1]`, and a `Sized` because WMMA's operands feed the same broadcast walk
# that `_align_left` feeds.
def drop_last(+x: Sized) -> Sized:
  sized(take_n(Sized.s(x), Nat.sub(Sized.n(x), 1n)))

def wmma_shapes.go(ws: List<&2, Sized>, acc: List<&2, Sized>) -> List<&2, Sized>:
  List.foldl(~&2, ~Sized, ~List<&2, Sized>, (a: List<&2, Sized>) => (w: Sized) => List.append(&2, Sized, a, [drop_last(w)]), ws, acc)

def drop_n(xs: List<&2, O.Sint>, +n: Nat) -> List<&2, O.Sint>:
  List.drop(&2, O.Sint, xs, n)

# `len(xs) == 0`, which two arms need as a Bool
def is_empty(xs: List<&2, O.Sint>) -> Bool:
  match xs:
    case Nil{}: True{}
    case _ <> _: False{}

# the `if ok then Some{x} else None` of this file, hoisted. Bend has no `if`, and a
# fold that filters the same way in ten places should say it once.
def some_if(a, -A: Kind(a), ok: Bool, x: A) -> Maybe<a, A>:
  match ok:
    case True{}: Some{x}
    case False{}: None{}

def bitcast_dims.put.of(+n: U32, +out: U32, +x: Sized) -> Maybe<&2, List<&2, O.Sint>>:
  some_if(&2, List<&2, O.Sint>, U32.is_zero(U32.mod(n, out)),
    List.append(&2, O.Sint, Sized.s(drop_last(x)), [sint_of(U32.div(n, out))]))

def bitcast_dims.put(i: U32, out: U32, inp: U32, ps: List<&2, O.Sint>) -> Maybe<&2, List<&2, O.Sint>>:
  bitcast_dims.put.of(U32.mul(i, inp), out, sized(ps))

# `if isinstance(ps[-1], int) and (ps[-1]*input_sz) % output_sz: raise RuntimeError
# ("unsupported size in bitcast")` then `return ps[:-1]+(ssimplify((ps[-1]*input_sz)
# // output_sz),)`. The arithmetic is U32 and is exact here: a dim is a
# non-negative count and an itemsize is 1, 2, 4 or 8, so the product fits a U32.
# (`helpers.bend` has `i64_add` and `i64_sub` but no `i64_mul` or `i64_div`, and a
# dim is not a value this port needs 64-bit arithmetic for.)
def bitcast_dims.scale(d: O.Sint, out: U32, inp: U32, ps: List<&2, O.Sint>) -> Maybe<&2, List<&2, O.Sint>>:
  match d:
    case O.SU{u}: None{}
    case O.SI{i}: bitcast_dims.put(H.lo32(i), out, inp, ps)

def bitcast_dims.last(m: Maybe<&2, O.Sint>, out: U32, inp: U32, ps: List<&2, O.Sint>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case Some{d}: bitcast_dims.scale(d, out, inp, ps)
    case None{}: None{}

def bitcast_dims.res.n(+x: Sized, out: U32, inp: U32, n: Nat) -> Maybe<&2, List<&2, O.Sint>>:
  match n:
    case 0n: Some{Sized.s(x)}
    case 1n+p: bitcast_dims.last(List.last(&2, O.Sint, Sized.s(x)), out, inp, Sized.s(x))

def bitcast_dims.res(ps: List<&2, O.Sint>, out: U32, inp: U32, same: Bool, +n: U32) -> Maybe<&2, List<&2, O.Sint>>:
  match same:
    case True{}: Some{ps}
    case False{}: bitcast_dims.res.n(sized(ps), out, inp, U32.to_nat(n))

def bitcast_dims.res.of(+x: Sized, out: U32, inp: U32, same: Bool) -> Maybe<&2, List<&2, O.Sint>>:
  bitcast_dims.res(Sized.s(x), out, inp, same, U32.from_nat(Sized.n(x)))

def bitcast_dims.go(m: Maybe<&2, List<&2, O.Sint>>, out: U32, inp: U32, same: Bool) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case None{}: None{}
    case Some{ps}: bitcast_dims.res.of(sized(ps), out, inp, same)

# `ps = self.src[0]._shape` / `if ps is None: return None` / `if (output_sz:=
# self.dtype.itemsize) != (input_sz:=self.src[0].dtype.itemsize) and len(ps) > 0`
def bitcast_dims(m: Maybe<&2, List<&2, O.Sint>>, +out: U32, +inp: U32) -> Maybe<&2, List<&2, O.Sint>>:
  bitcast_dims.go(m, out, inp, U32.is_eq(out, inp))

def bcast_dim.rest(+x: O.Sint, t: List<&2, O.Sint>) -> Maybe<&2, O.Sint>:
  match t:
    case Nil{}: Some{x}
    case y <> _: some_if(&2, O.Sint, eq_sint(x, y), x)

# `ret.append(rest[0] if rest else 1)`, and `len(rest) > 1` is the IndexError. A
# PAIR is all this needs -- two kept sizes disagree exactly when they are unequal.
def bcast_dim.pair(ks: List<&2, O.Sint>) -> Maybe<&2, O.Sint>:
  match ks:
    case Nil{}: Some{sint_one()}
    case x <> t: bcast_dim.rest(x, t)

# `num_axes` is a `U32` count, so the `< 0` test cannot fail

# the `if ok then acc+[x] else acc` of this file, hoisted
def add_if(a, -A: Kind(a), ok: Bool, x: A, acc: List<a, A>) -> List<a, A>:
  match ok:
    case True{}: List.append(a, A, acc, [x])
    case False{}: acc

# `[s for s in sizes if isinstance(s, UOp) or s != 1]`
def bcast_dim.kept(+s: O.Sint, acc: List<&2, O.Sint>) -> List<&2, O.Sint>:
  add_if(&2, O.Sint, bcast_dim.is_uop_or_ne_1(s), s, acc)

# per right-aligned dim: sizes of 1 broadcast to the others, which must all agree
def bcast_dim(x: O.Sint, y: O.Sint) -> Maybe<&2, O.Sint>:
  bcast_dim.pair(bcast_dim.kept(y, bcast_dim.kept(x, Nil{})))

def bcast.pair.of(xs: List<&2, O.Sint>, ys: List<&2, O.Sint>, acc: List<&2, O.Sint>) -> Maybe<&2, List<&2, O.Sint>>:
  match xs ys:
    case Nil{} Nil{}: Some{acc}
    case Nil{} _ <> _: Some{acc}
    case _ <> _ Nil{}: Some{acc}
    case x <> xt y <> yt:
      Maybe.bind(&2, O.Sint, List<&2, O.Sint>, bcast_dim(x, y),
        dx => bcast.pair.of(xt, yt, List.append(&2, O.Sint, acc, [dx])))

# the zip's two lists, with the right-aligned shape split out of its `Sized`
def bcast.pair(xs: List<&2, O.Sint>, y: Sized, acc: List<&2, O.Sint>) -> Maybe<&2, List<&2, O.Sint>>:
  bcast.pair.of(xs, Sized.s(y), acc)

def bcast.go(als: List<&2, Sized>, acc: List<&2, O.Sint>) -> Maybe<&2, List<&2, O.Sint>>:
  match als:
    case Nil{}: Some{acc}
    case a <> t:
      Maybe.bind(&2, List<&2, O.Sint>, List<&2, O.Sint>, bcast.pair(acc, a, Nil{}),
        acc2 => bcast.go(t, acc2))

# the zip of the per-dim loop. `acc` is the dims answered so far, so pairing it with
# the next right-aligned shape walks the dims from the left, which is what `zip`
# does. `_align_left` made every shape the same length, so the walk ends together --
# and `zip` truncates at the shorter one anyway, which is what the two ragged arms
# say. The accumulator IS the first column: the first shape seeds it and every later
# shape extends it, and pairing the empty accumulator with the first shape instead
# would drop that shape, which is a broadcast that answers the wrong dims.
def bcast.first(als: List<&2, Sized>) -> Maybe<&2, List<&2, O.Sint>>:
  match als:
    case Nil{}: None{}
    case a <> t: bcast.go(t, Sized.s(a))

def Kahn.seed.keep(deg: U32, k: U32, acc: List<&2, U32>) -> List<&2, U32>:
  add_if(&2, U32, U32.is_zero(deg), k, acc)

# _broadcast_shape -- ops.py:80, the `zip(*_align_left(*shapes))` fold.
#
#   if all_same(shapes): return shapes[0]
#   ret = []
#   for sizes in zip(*_align_left(*shapes)):
#     if len(rest:=dedup([s for s in sizes if isinstance(s, UOp) or s != 1])) > 1:
#       raise IndexError(f"shape mismatch: objects cannot be broadcast to a single shape {shapes}")
#     ret.append(rest[0] if rest else 1)
#   return tuple(ret)
#
# `all_same(shapes): return shapes[0]` is not a fifth rule: right-aligning a set of
# equal shapes and taking the per-dim maximum IS that shape. The IndexError is the
# `None` this reports by not answering, as every other `raise` in the two ladders is.
# So is `all_same(())` on an empty shape list -- `shapes[0]` is then an IndexError --
# which `_shape`'s Broadcastable arm reaches on a zero-operand op, and `None` is the
# same `None`.
def bcast_shape(m: Maybe<&2, Shapes>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case None{}: None{}
    case Some{sh}: bcast.first(_align_left(sh))

# ===========================================================================
# THE ANSWER: one record per resolved node, carrying the six properties that fit
# without `simplify` or the movement shape algebra. `shape` is Python's own
# `tuple[sint, ...]|None`, `dev` its `str|tuple[str, ...]|None`, `addr` its
# `AddrSpace|None`, `base` ops.py:785's node as an index, and `ended`
# ops.py:470's `tuple[UOp, ...]` as a list of indices.
#
# A `Data` record and not six parameters because a Bend `List` is spent when read,
# and `dt_shape` and `ended_of` both want the srcs.
# ===========================================================================

type Derived is Data:
  Derived{dt: S.Dt, shape: Maybe<&2, List<&2, O.Sint>>, dev: Maybe<&2, S.Dev>,
    addr: Maybe<&2, S.Addr>, base: U32, ended: List<&2, U32>}

# `DtShape` is `(DType, tuple[sint, ...]|None)` as a record, which is the whole of
# why dtype and shape are answered together.
type DtShape is Data:
  DtShape{dt: S.Dt, shape: Maybe<&2, List<&2, O.Sint>>}

# The two constructors every arm of the ladder ends in, hoisted: a real shape, and
# a real shape under a condition (Python's `assert` and `raise` arms).
def dt_of(dt: S.Dt, m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, DtShape>:
  match m:
    case Some{ds}: Some{DtShape{dt, Some{ds}}}
    case None{}: None{}

def param_ds.shape(dt: S.Dt, arg: O.Arg) -> Maybe<&2, DtShape>:
  dt_of(dt, Some{param_shape(arg)})

def param_ds.pick(m: Maybe<&1, S.Dt>, arg: O.Arg) -> Maybe<&2, DtShape>:
  match m:
    case Some{dt}: param_ds.shape(dt, arg)
    case None{}: None{}

def bitcast_ds.shape(dt: S.Dt, out: U32, inp: U32, m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, DtShape>:
  Maybe.bind(&2, List<&2, O.Sint>, DtShape, bitcast_dims(m, out, inp), ds => dt_of(dt, Some{ds}))

# a `raise` on `ok` guarding the same pair, so the guard is a whole extra answer and
# not a field of it: `ok` false and `m` None are the same `None`, and the one place
# they differ -- `ok` true with a real shape -- is `dt_of` itself.
def dt_of_if(ok: Bool, dt: S.Dt, m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, DtShape>:
  match ok:
    case True{}: dt_of(dt, m)
    case False{}: None{}

# GETADDR: `return dtypes.uint64` and `case Ops.GETADDR: return ()`
def addr_ds() -> Maybe<&2, DtShape>:
  dt_of(S.uint64(), Some{Nil{}})

def wmma_ds.put(dt: S.Dt, b: Maybe<&2, List<&2, O.Sint>>, last: Maybe<&2, O.Sint>) -> Maybe<&2, DtShape>:
  Maybe.bind(&2, O.Sint, DtShape, last, d => dt_of(dt, Maybe.map(&2, List<&2, O.Sint>, List<&2, O.Sint>, ws => List.append(&2, O.Sint, ws, [d]), b)))

def wmma_ds.of(dt: S.Dt, b: Maybe<&2, List<&2, O.Sint>>, last: Maybe<&2, O.Sint>) -> Maybe<&2, DtShape>:
  Maybe.bind(&2, List<&2, O.Sint>, DtShape, b, ws => wmma_ds.put(dt, Some{ws}, last))

def reduce_ds.go(dt: S.Dt, m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, DtShape>:
  dt_of(dt, m)

def const_ds.pick(m: Maybe<&1, S.Dt>) -> Maybe<&2, DtShape>:
  match m:
    case Some{dt}: dt_of(dt, Some{Nil{}})
    case None{}: None{}

# the `return ()` shape, which RANGE, SPECIAL, GETADDR, CONST, a STACK of no srcs,
# INS and a non-void CALL all answer
def dt_of_nil(dt: S.Dt) -> DtShape:
  DtShape{dt, Some{Nil{}}}

def call_ds.go(+dt: S.Dt, vd: S.Dt) -> Maybe<&2, DtShape>:
  some_if(&2, DtShape, Bool.not(O.eq_dt(dt, vd)), dt_of_nil(dt))

def ins_ds.shape(+dt: S.Dt, vd: S.Dt) -> Maybe<&2, DtShape>:
  some_if(&2, DtShape, Bool.not(O.eq_dt(dt, vd)), dt_of_nil(dt))

def ins_ds.pick(m: Maybe<&1, S.Dt>) -> Maybe<&2, DtShape>:
  match m:
    case Some{dt}: ins_ds.shape(dt, S.void())
    case None{}: None{}

# THE WALK'S TWO RESULTS, as one value, for the same reason as `Table`: the hit is
# read once per src and both the accumulator and the flag need it.
type Gathered is Data:
  Gathered{acc: List<&2, Derived>, ok: Bool}

def Gathered.acc(g: Gathered) -> List<&2, Derived>:
  match g:
    case Gathered{acc, ok}: acc

def Gathered.ok(g: Gathered) -> Bool:
  match g:
    case Gathered{acc, ok}: ok

def Kahn.gather.ok(hit: Maybe<&2, Derived>, ok: Bool) -> Bool:
  match hit:
    case Some{d}: ok
    case None{}: False{}

def Kahn.gather.push(hit: Maybe<&2, Derived>, acc: List<&2, Derived>) -> List<&2, Derived>:
  match hit:
    case Some{d}: List.append(&2, Derived, acc, [d])
    case None{}: acc

def Kahn.gather.done(acc: List<&2, Derived>, ok: Bool) -> Maybe<&2, List<&2, Derived>>:
  match ok:
    case True{}: Some{acc}
    case False{}: None{}

# The dead default for a src lookup. `Kahn.gather` has already refused every node
# with an unresolved src, so a `None` here is unreachable: this is a value, not a
# second gate on every arm.
def Derived.unknown() -> Derived:
  Derived{S.void(), None{}, None{}, None{}, 0, Nil{}}

def Kahn.get.hit(ok: Bool, d: Derived, acc: Maybe<&2, Derived>) -> Maybe<&2, Derived>:
  match ok:
    case True{}: Some{d}
    case _: acc

def Derived.dt(d: Derived) -> S.Dt:
  match d:
    case Derived{dt, shape, dev, addr, base, ended}: dt

# `self.src[k]`, as the fold answered it. Six wrappers over the same `List.get`,
# because every arm reads at most two or three of them and naming the property is
# what makes an arm readable.
def src_dt(k: U32, ss: List<&2, Derived>) -> S.Dt:
  Derived.dt(Maybe.default(&2, Derived, List.get(&2, Derived, ss, U32.to_nat(k)), Derived.unknown()))

# RANGE and SPECIAL: `return ()` in `_shape`, and both take their dtype from src[0]
def rlike(ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of(src_dt(0, ss), Some{Nil{}})

# `[x.dtype for x in src]`
def dts_of.go(ss: List<&2, Derived>, acc: List<&2, S.Dt>) -> List<&2, S.Dt>:
  List.foldl(~&2, ~Derived, ~List<&2, S.Dt>, (a: List<&2, S.Dt>) => (d: Derived) => List.append(&2, S.Dt, a, [Derived.dt(d)]), ss, acc)

def fold.dt.of(m: Maybe<&2, Derived>) -> Maybe<&2, S.Dt>:
  match m:
    case Some{d}: Some{Derived.dt(d)}
    case None{}: None{}

def Derived.shape(d: Derived) -> Maybe<&2, List<&2, O.Sint>>:
  match d:
    case Derived{dt, shape, dev, addr, base, ended}: shape

def src_shape(k: U32, ss: List<&2, Derived>) -> Maybe<&2, List<&2, O.Sint>>:
  Derived.shape(Maybe.default(&2, Derived, List.get(&2, Derived, ss, U32.to_nat(k)), Derived.unknown()))

# THE SRC LIST AND ITS LENGTH, the second count-and-list of this file. `Srcs.tail`
# is `self.src[1:]` and `Srcs.n` is `len(self.src)`, which is what INDEX's
# `self.src[0].shape[len(self.src[1:]):]` needs without a second walk of the arena.
type Srcs is Data:
  Srcs{ss: List<&2, Derived>, n: Nat}

def Srcs.ss(x: Srcs) -> List<&2, Derived>:
  match x:
    case Srcs{ss, n}: ss

def bitcast_ds.shape.of(+dt: S.Dt, +x: Srcs) -> Maybe<&2, DtShape>:
  bitcast_ds.shape(dt, S.Dt.itemsize(dt), S.Dt.itemsize(src_dt(0, Srcs.ss(x))), src_shape(0, Srcs.ss(x)))

def Srcs.n(x: Srcs) -> Nat:
  match x:
    case Srcs{ss, n}: n

def Srcs.tail(x: Srcs) -> List<&2, Derived>:
  List.drop(&2, Derived, Srcs.ss(x), 1n)

# `self.src`, IN ARENA ORDER -- `Arena.src(ar, i, k)` at position k -- because that
# is the order every positional reader in this file (`src_dt(0, ss)`,
# `src_shape(0, ss)`, `Srcs.tail`'s `src[1:]`) reads, and it is the order Python
# reads. `List.append` is `xs ++ ys`, so the accumulator is ALREADY in input order
# and the walk ends with no `List.reverse`: the reverse that used to be here turned
# a list already in arena order into its own mirror, which every whole-list walk
# (`dts_of.go`, `mstack_dev.go`, `ended_of.flat`, `first_dev`) survived by accident
# and every positional read did not. MEASURED, and the measurement is
# `.agents/slop/notes/probe-srcorder.bend`: over `g_resh22`'s RESHAPE
# (`Kahn.gather` is order-correct), `src_dt(0, ...)` reads the int32 BUFFER at pri 5
# before this change and the STACK at pri 0 after it -- src[0] the whole way.
def srcs.go(ss: List<&2, Derived>, n: Nat, acc: List<&2, Derived>) -> Srcs:
  match ss:
    case Nil{}: Srcs{acc, n}
    case d <> t: srcs.go(t, 1n+n, List.append(&2, Derived, acc, [d]))

def srcs(ss: List<&2, Derived>) -> Srcs:
  srcs.go(ss, 0n, Nil{})

def bitcast_ds.pick(m: Maybe<&1, S.Dt>, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match m:
    case Some{dt}: bitcast_ds.shape.of(dt, srcs(ss))
    case None{}: None{}

def stack_ds.ds(dt: S.Dt, ss: List<&2, Derived>, n: U32) -> Maybe<&2, DtShape>:
  Maybe.bind(&2, List<&2, O.Sint>, DtShape, src_shape(0, ss),
    ds => dt_of(dt, Some{List.append(&2, O.Sint, [sint_of(n)], ds)}))

def stack_ds.go(dt: S.Dt, ss: List<&2, Derived>, +n: Nat) -> Maybe<&2, DtShape>:
  match n:
    case 0n: dt_of(dt, Some{Nil{}})
    case 1n+p: stack_ds.ds(dt, ss, U32.from_nat(Nat.add(p, 1n)))

def stack_ds.of(+x: Srcs) -> Maybe<&2, DtShape>:
  stack_ds.go(promo_dtype(dts_of.go(Srcs.ss(x), Nil{})), Srcs.ss(x), Srcs.n(x))

def stack_ds(ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  stack_ds.of(srcs(ss))

# `return self.src[0].dtype` and `return self.src[0]._shape`, which is REDUCE's
# `return ps[num_axes:]` past the axis check
def reduce_dims.put(+x: Sized, +n: U32) -> Maybe<&2, List<&2, O.Sint>>:
  some_if(&2, List<&2, O.Sint>, Bool.not(U32.is_gt(n, U32.from_nat(Sized.n(x)))),
    drop_n(Sized.s(x), U32.to_nat(n)))

def reduce_dims(ss: List<&2, Derived>, +n: U32) -> Maybe<&2, List<&2, O.Sint>>:
  Maybe.bind(&2, List<&2, O.Sint>, List<&2, O.Sint>, src_shape(0, ss),
    ps => reduce_dims.put(sized(ps), n))

# `return self.src[0].dtype` and `return self.src[0]._shape`: the LOAD / UNSHARD /
# REDUCE-after-dtype / AFTER / RANGE-after-shape / CONTIGUOUS_BACKWARD / COPY /
# STAGE-after-shape / DETACH / MSTACK / MSELECT / ALLREDUCE / SPECIAL-after-shape /
# END passthrough arms of the two ladders, plus NEG and TRUNC through the
# `GroupOp.Unary` and `Unary.union({Ops.CAST})` shape arms.
def thru0(+ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of(src_dt(0, ss), src_shape(0, ss))

# STORE: dtype_from_uop's `always void`, `_shape`'s passthrough arm
def store_ds(ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of(S.void(), src_shape(0, ss))

def cast_ds.pick(m: Maybe<&1, S.Dt>, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match m:
    case Some{dt}: dt_of(dt, src_shape(0, ss))
    case None{}: None{}

# `src_shape(k)[-1]`, which is a `Maybe` inside a `Maybe`: a src with no shape has no
# last dim, and `Maybe.bind` is the two questions asked in order.
def src_last(k: U32, ss: List<&2, Derived>) -> Maybe<&2, O.Sint>:
  Maybe.bind(&2, List<&2, O.Sint>, O.Sint, src_shape(k, ss), ds => List.last(&2, O.Sint, ds))

# `x._shape is not None` for every x, which is the `assert` the Broadcastable arm
# and INDEX's index loop both make through `s.shape`.
def all_shaped.go(ss: List<&2, Derived>, ok: Bool) -> Bool:
  match ss:
    case Nil{}: ok
    case d <> t: all_shaped.go(t, Bool.and(ok, Maybe.is_some(&2, List<&2, O.Sint>, Derived.shape(d))))

def all_shaped(ss: List<&2, Derived>) -> Bool:
  all_shaped.go(ss, True{})

# `[x.shape for x in src]` -- the `input_shapes` the Broadcastable arm and WMMA's
# `wmma_b` take. `all_shaped` has already refused a shapeless operand, so the
# `Nil{}` default is the dead one.
def shape_of(d: Derived) -> List<&2, O.Sint>:
  Maybe.default(&2, List<&2, O.Sint>, Derived.shape(d), Nil{})

def shapes_of.put(+x: Sized, +sh: Shapes) -> Shapes:
  Shapes{List.append(&2, Sized, Shapes.ds(sh), [x]), Nat.max(Shapes.m(sh), Sized.n(x))}

def shapes_of.acc(m: Maybe<&2, List<&2, O.Sint>>, acc: Maybe<&2, Shapes>) -> Maybe<&2, Shapes>:
  match m acc:
    case None{} _: None{}
    case Some{ds} None{}: None{}
    case Some{ds} Some{sh}: Some{shapes_of.put(sized(ds), sh)}

# The `assert` and the collection in ONE walk, because `all_shaped` and
# `shapes_of.go` are two reads of the same list and Bend spends a list when it reads
# it. The accumulator is a Maybe and the step is a def, so it is two scrutinees and
# the three cases a Maybe-squared walk can be in.
def shapes_of.acc2(acc: Maybe<&2, Shapes>, d: Derived) -> Maybe<&2, Shapes>:
  shapes_of.acc(Derived.shape(d), acc)

def shapes_of.go(ss: List<&2, Derived>, acc: Maybe<&2, Shapes>) -> Maybe<&2, Shapes>:
  List.foldl(~&2, ~Derived, ~Maybe<&2, Shapes>, shapes_of.acc2, ss, acc)

def all_shapes(ss: List<&2, Derived>) -> Maybe<&2, Shapes>:
  shapes_of.go(ss, Some{Shapes{Nil{}, 0n}})

def where_ds.of(+x: Srcs) -> Maybe<&2, DtShape>:
  dt_of_if(S.Dt.is_bool(src_dt(0, Srcs.ss(x))), promo_dtype(dts_of.go(Srcs.tail(x), Nil{})),
    bcast_shape(all_shapes(Srcs.ss(x))))

# WHERE: `if src[0].dtype != dtypes.bool: raise RuntimeError(f"where cond must be
# bool, got {src[0].dtype}")` then `return promo_dtype(src[1:])`
def where_ds(ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  where_ds.of(srcs(ss))

# The Broadcastable arm: "elementwise ops keep the shape the same. all inputs with
# shape must match" -- `assert len(self.src) > 0 and all(x is not None for x in
# input_shapes), f"None input shape not supported for {self.op}"` then `return
# _broadcast_shape(*input_shapes)`. The DISALLOW_BROADCAST check above it is a
# configuration switch, not a rule, so it is not here. `all_shapes` is the assert
# and `bcast_shape` refuses the empty list, so one call is both.
def alu_ds(dt: S.Dt, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of(dt, bcast_shape(all_shapes(ss)))

# `shp.extend(list(s.shape))`, one index at a time
def dims_of.go(ss: List<&2, Derived>, acc: List<&2, O.Sint>) -> List<&2, O.Sint>:
  List.foldl(~&2, ~Derived, ~List<&2, O.Sint>, (a: List<&2, O.Sint>) => (d: Derived) => List.append(&2, O.Sint, a, shape_of(d)), ss, acc)

def dims_of(ss: List<&2, Derived>) -> List<&2, O.Sint>:
  dims_of.go(ss, Nil{})

def index_shape.put(ar: O.Arena, i: U32, base: List<&2, O.Sint>, +x: Srcs) -> Maybe<&2, List<&2, O.Sint>>:
  some_if(&2, List<&2, O.Sint>, all_shaped(Srcs.tail(x)),
    List.append(&2, O.Sint, dims_of(Srcs.tail(x)),
      drop_n(base, Nat.sub(Srcs.n(x), 1n))))

def index_shape.of(ar: O.Arena, i: U32, +x: Srcs) -> Maybe<&2, List<&2, O.Sint>>:
  Maybe.bind(&2, List<&2, O.Sint>, List<&2, O.Sint>, src_shape(0, Srcs.ss(x)),
    base => index_shape.put(ar, i, base, x))

def fold.shape.of(m: Maybe<&2, Derived>) -> Maybe<&2, Maybe<&2, List<&2, O.Sint>>>:
  match m:
    case Some{d}: Some{Derived.shape(d)}
    case None{}: None{}

def Derived.dev(d: Derived) -> Maybe<&2, S.Dev>:
  match d:
    case Derived{dt, shape, dev, addr, base, ended}: dev

def src_dev(k: U32, ss: List<&2, Derived>) -> Maybe<&2, S.Dev>:
  Derived.dev(Maybe.default(&2, Derived, List.get(&2, Derived, ss, U32.to_nat(k)), Derived.unknown()))

# the `for x in self.src` loop, first non-None wins and src order is the order
def first_dev.acc2(acc: Maybe<&2, S.Dev>, d: Derived) -> Maybe<&2, S.Dev>:
  Maybe.or(&2, S.Dev, acc, Derived.dev(d))

def first_dev.go(ss: List<&2, Derived>, acc: Maybe<&2, S.Dev>) -> Maybe<&2, S.Dev>:
  List.foldl(~&2, ~Derived, ~Maybe<&2, S.Dev>, first_dev.acc2, ss, acc)

def first_dev(ss: List<&2, Derived>) -> Maybe<&2, S.Dev>:
  first_dev.go(ss, None{})

def fold.device.of(m: Maybe<&2, Derived>) -> Maybe<&2, Maybe<&2, S.Dev>>:
  match m:
    case Some{d}: Some{Derived.dev(d)}
    case None{}: None{}

def Derived.addr(d: Derived) -> Maybe<&2, S.Addr>:
  match d:
    case Derived{dt, shape, dev, addr, base, ended}: addr

def src_addr(k: U32, ss: List<&2, Derived>) -> Maybe<&2, S.Addr>:
  Derived.addr(Maybe.default(&2, Derived, List.get(&2, Derived, ss, U32.to_nat(k)), Derived.unknown()))

def fold.addr.of(m: Maybe<&2, Derived>) -> Maybe<&2, Maybe<&2, S.Addr>>:
  match m:
    case Some{d}: Some{Derived.addr(d)}
    case None{}: None{}

def Derived.base(d: Derived) -> U32:
  match d:
    case Derived{dt, shape, dev, addr, base, ended}: base

def src_base(k: U32, ss: List<&2, Derived>) -> U32:
  Derived.base(Maybe.default(&2, Derived, List.get(&2, Derived, ss, U32.to_nat(k)), Derived.unknown()))

def base_of.go(ss: List<&2, Derived>, i: U32, steps: Bool) -> U32:
  match steps:
    case True{}: src_base(0, ss)
    case False{}: i

def fold.base.of(m: Maybe<&2, Derived>) -> Maybe<&1, U32>:
  match m:
    case Some{d}: Some{Derived.base(d)}
    case None{}: None{}

def Derived.ended(d: Derived) -> List<&2, U32>:
  match d:
    case Derived{dt, shape, dev, addr, base, ended}: ended

def src_ended(k: U32, ss: List<&2, Derived>) -> List<&2, U32>:
  Derived.ended(Maybe.default(&2, Derived, List.get(&2, Derived, ss, U32.to_nat(k)), Derived.unknown()))

def ended_of.list(ss: List<&2, Derived>, acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match ss:
    case Nil{}: acc
    case d <> t: ended_of.list(t, List.append(&2, List<&2, U32>, acc, [Derived.ended(d)]))

# `flatten([x.ended_ranges for x in self.src[k:]])`
def ended_of.flat(ss: List<&2, Derived>, k: Nat) -> List<&2, U32>:
  H.flatten_u32(ended_of.list(List.drop(&2, Derived, ss, k), Nil{}))

def fold.ended.of(m: Maybe<&2, Derived>) -> Maybe<&2, List<&2, U32>>:
  match m:
    case Some{d}: Some{Derived.ended(d)}
    case None{}: None{}

# ===========================================================================
# `dtype_from_uop` (ops.py:124) and `UOp._shape` (ops.py:329), together.
#
# The arms are grouped by the RULE they use rather than by declaration order,
# because ops.py's own order is: every op that names its dtype, then every op that
# names its shape, then three `GroupOp` fallbacks. The list of ops is the same and
# it is CLOSED, which is what makes the match total without Python's closing
# `raise RuntimeError(f"no dtype for {op} with arg {arg}")`: the deferred arms at
# the bottom are the only `None`s, and each says which rule it is waiting for.
#
# ops.py's own comments on the arms, kept: "always void", "pass through first",
# "passthrough ops", "some ops init the shape", "late ops don't have shape",
# "derived from the value. order matters: bool is an int subclass, ConstFloat is a
# float subclass", and the note that CMPLT, CMPNE, CMPEQ, WHERE, SHL and SHR are
# handled above rather than by the GroupOp fallbacks.
# ===========================================================================

# `always void` in the dtype ladder and `late ops don't have shape` in `_shape`: the
# same twelve ops in both rules, so one def answers both.
def late() -> Maybe<&2, DtShape>:
  Some{DtShape{S.void(), None{}}}

def noop_ds.go(empty: Bool, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match empty:
    case True{}: late()
    case False{}: dt_of(S.void(), src_shape(0, ss))

# NOOP: `return self.src[0]._shape if len(self.src) >= 1 else None` -- "hacks for
# NOOP" -- and the dtype is in the `always void` set.
def noop_ds(ar: O.Arena, i: U32, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  noop_ds.go(U32.is_zero(O.Arena.nsrc(ar, i)), ss)

def binary_n.of(arg: O.Arg) -> U32:
  match arg:
    case O.ABlob{n}: n
    case _: 0

def binary_n(arg: O.Arg) -> U32:
  binary_n.of(arg)

# BINARY: `return dtypes.uint8` and `return (len(self.arg),)`
def binary_ds(arg: O.Arg) -> Maybe<&2, DtShape>:
  dt_of(S.uint8(), Some{[sint_of(binary_n(arg))]})

def param_dt(arg: O.Arg) -> Maybe<&1, S.Dt>:
  match arg:
    case O.AParam{pa}: Some{O.ParamArg.dtype(pa)}
    case _: None{}      # `assert isinstance(arg, ParamArg), f"{op} must have ParamArg"`

# BUFFER | ALLOC | PARAM: "these don't have a shape input, they have a size in the
# arg: int gives shape (size,), None gives ()" -- and, before that,
# `if (img:=self.arg.image) is not None: return (img[0], img[1], 4)`.
def param_ds(+arg: O.Arg) -> Maybe<&2, DtShape>:
  param_ds.pick(param_dt(arg), arg)

def call_dt(arg: O.Arg) -> S.Dt:
  match arg:
    case O.ACall{ci}: O.CallInfo.dtype(ci)
    case _: S.void()

# CALL: `return arg.dtype if isinstance(arg, CallInfo) else dtypes.void` in the
# dtype ladder, and `return None if self.dtype is dtypes.void else ()` in `_shape`:
# "a void CALL has no shape, the return value of a CALL has the shape of its dtype".
def call_ds(arg: O.Arg) -> Maybe<&2, DtShape>:
  call_ds.go(call_dt(arg), S.void())

def ins_dt(arg: O.Arg) -> Maybe<&1, S.Dt>:
  match arg:
    case O.AInk{ins, dt}: Some{dt}
    case _: None{}      # `assert isinstance(arg, tuple) and len(arg) == 2`

# INS: `arg is (instruction, dtype)`, "a queue command or an asm line is void",
# which the arg's Dt already says, and `if self.dtype is dtypes.void: return None;
# return ()` -- "INS shape is always scalar, vector width is in the instruction
# encoding".
def ins_ds(arg: O.Arg) -> Maybe<&2, DtShape>:
  ins_ds.pick(ins_dt(arg))

def adt_dt(arg: O.Arg) -> Maybe<&1, S.Dt>:
  match arg:
    case O.ADt{dt}: Some{dt}
    case _: None{}      # `assert isinstance(arg, DType), f"CAST/BITCAST arg must be DType"`

# BITCAST: the dtype is `return arg`; the shape rescales the LAST dim by the
# itemsize ratio. `ssimplify` on that arm is the IDENTITY when the last dim is an
# int, which is the only case answerable without simplify: a symbolic last dim
# would need the quotient folded, and this file does not call simplify.
def bitcast_ds(arg: O.Arg, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  bitcast_ds.pick(adt_dt(arg), ss)

# CAST: `return arg`, and with CAST added to the Unary set `return self.src[0]._shape`
def cast_ds(arg: O.Arg, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  cast_ds.pick(adt_dt(arg), ss)

def index_dt.img(img: Bool, b: S.Dt) -> S.Dt:
  match img:
    case True{}: S.single()
    case False{}: b

def index_dt.go(param: Bool, img: Bool, b: S.Dt) -> S.Dt:
  match param:
    case True{}: index_dt.img(img, b)
    case False{}: b

def is_param.of(op: O.Op) -> Bool:
  match op:
    case O.OpsPARAM{}: True{}
    case _: False{}

def is_param(+ar: O.Arena, i: U32) -> Bool:
  is_param.of(O.Arena.op(ar, O.Arena.src0(ar, i)))

def index_dt(ar: O.Arena, i: U32, +ss: List<&2, Derived>) -> S.Dt:
  index_dt.go(is_param(ar, i), is_image_shape(src_shape(0, ss)), src_dt(0, ss))

def index_ds.of(+ar: O.Arena, +i: U32, +x: Srcs) -> Maybe<&2, DtShape>:
  dt_of(index_dt(ar, i, Srcs.ss(x)), index_shape.of(ar, i, x))

# INDEX: `if (b:=src[0]).op is Ops.PARAM and is_image_shape(b.shape): return
# dtypes.float` / `return b.dtype` -- "an image access is always float, no matter
# the storage dtype" (ops.py:144 asks whether there should be a CAST so
# `src[0].dtype` just works) -- and `shp:list[sint] = []` / `for s in self.src[1:]:
# shp.extend(list(s.shape))` / `return tuple(shp) + self.src[0].shape[len(self.src[1:]):]`
def index_ds(ar: O.Arena, i: U32, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  index_ds.of(ar, i, srcs(ss))

# `a.shape[:-1]` for each of the three operands
def wmma_shapes.of(sh: Shapes) -> List<&2, Sized>:
  wmma_shapes.go(Shapes.ds(sh), Nil{})

def wmma_ds.go(dt: S.Dt, ws: Maybe<&2, Shapes>, last: Maybe<&2, O.Sint>) -> Maybe<&2, DtShape>:
  wmma_ds.of(dt, bcast_shape(ws), last)

# WMMA: "wmma output shape = accumulator shape (src[2])", and the dtype is the
# accumulator dtype. `wmma_b = _broadcast_shape(self.src[0].shape[:-1],
# self.src[1].shape[:-1], self.src[2].shape[:-1])` / `return wmma_b +
# (self.src[2].shape[-1],)`
def wmma_ds(+ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  wmma_ds.go(src_dt(2, ss), all_shapes(List.take(&2, Derived, ss, 3n)), src_last(2, ss))

# ===========================================================================
# `marg` -- ops.py:813, RESHAPE's arm of it, and the reason RESHAPE is the one
# movement shape this file ports.
#
#   ops.py:816  `case Ops.RESHAPE | Ops.EXPAND: return self.src[1].as_shape`
#   ops.py:807  `if self.op is Ops.CONST: return (self.val,)`
#               `if self.op is not Ops.STACK: return (ssimplify(self),)`
#               `return tuple(s.val if s.op is Ops.CONST else ssimplify(s) for s in self.src)`
#
# `as_shape` reads `ssimplify` on TWO of its three arms, and BOTH are arms
# `shape_to_shape_arg` (ops.py:106) never builds: it is `UOp.const(x)` over the
# Python ints of `arg`, so `self.src[1]` is a CONST or a STACK of CONSTs and
# `as_shape` never gets past its first arm. The third arm is a symbolic shape,
# which is a RESHAPE over a RESHAPE of a PARAM, and that is the `ssimplify` wall
# -- so it answers None, and None here is a whole NODE unanswered rather than a
# missing value. `movement.bend`'s `as_shape` (ops.py:808) said the same thing
# first, over the same two arms.
#
# THE ANSWER is a `List<&2, O.Sint>` of `SI`s, and that is the point: every dim
# is an `I64` `H.i64_is_neg` can test and `H.lo32` can multiply, which is what
# the two checks need and what no other movement arm has.
# ===========================================================================

# `self.val` for a CONST -- ops.py:259-262, `.val` reads `self.arg` and is only
# for a CONST or a CAST of one. A `CFloat` is not a dim: `shape_to_shape_arg`
# asserts `dtypes.is_int(x.dtype)`, and `True == 1` as dict keys, so a `CBool`
# is the 1 or the 0 it is.
def const_i64.go(a: O.Arg) -> Maybe<&2, H.I64>:
  match a:
    case O.APy{O.CInt{i}}       : Some{i}
    case O.APy{O.CBool{True{}}}: Some{H.i64_of_i32(1)}
    case O.APy{O.CBool{False{}}}: Some{H.i64_of_i32(0)}
    case _                      : None{}

def const_i64(a: O.Arg) -> Maybe<&2, H.I64>:
  const_i64.go(a)

# `return tuple(s.val if s.op is Ops.CONST else ssimplify(s) for s in self.src)` --
# and the `ssimplify` half is the `None`: a STACK built by `shape_to_shape_arg`
# has a CONST in every src. The DIMS and the "is every src a CONST" flag are the
# two halves of one walk, so they are ONE value -- the same `Gathered`/`Sized`
# rule this file already uses, and for the same reason: Bend refuses mutual
# recursion, so a walk that appends and a walk that tests cannot be two defs.
type Marg is Data:
  Marg{ds: List<&2, O.Sint>, ok: Bool}

def Marg.ds(x: Marg) -> List<&2, O.Sint>:
  match x:
    case Marg{ds, ok}: ds

def Marg.ok(x: Marg) -> Bool:
  match x:
    case Marg{ds, ok}: ok

# `marg.done`, so the `Some`/`None` answer has one spelling
def marg.done(+x: Marg) -> Maybe<&2, List<&2, O.Sint>>:
  some_if(&2, List<&2, O.Sint>, Marg.ok(x), Marg.ds(x))

# ONE READ of the src's arg, which is why the CONST VAL and the flag travel
# together: `s.val` is read once and the `ssimplify` else is read once.
def marg.step(v: Maybe<&2, H.I64>, +x: Marg) -> Marg:
  match v:
    case Some{i}: Marg{List.append(&2, O.Sint, Marg.ds(x), [O.SI{i}]), Marg.ok(x)}
    case None{}  : Marg{Marg.ds(x), False{}}

def marg.stack.go(ss: List<&2, U32>, +ar: O.Arena, +x: Marg) -> Maybe<&2, List<&2, O.Sint>>:
  match ss:
    case Nil{}   : marg.done(x)
    case s <> t  : marg.stack.go(t, ar, marg.step(const_i64(O.Arena.arg(ar, s)), x))

# `if self.op is Ops.CONST: return (self.val,)`, the one-element shape
def marg.one(+ar: O.Arena, i: U32) -> Maybe<&2, List<&2, O.Sint>>:
  marg.done(marg.step(const_i64(O.Arena.arg(ar, i)), Marg{Nil{}, True{}}))

# `self.src[1]`, the arg `shape_to_shape_arg` built, and the two arms above
def marg.of(k: O.Op, +ar: O.Arena, i: U32) -> Maybe<&2, List<&2, O.Sint>>:
  match k:
    case O.OpsCONST{}: marg.one(ar, i)
    case O.OpsSTACK{}: marg.stack.go(O.Arena.srcs(ar, i), ar, Marg{Nil{}, True{}})
    case _          : None{}    # `(ssimplify(self),)`: the `ssimplify` wall

# `self.src[1]`, the arg `shape_to_shape_arg` built, and the two arms above. `+s`
# is the shared binding that pays for reading the index once and using it twice.
def marg(+ar: O.Arena, i: U32) -> Maybe<&2, List<&2, O.Sint>>:
  +s = O.Arena.src(ar, i, 1)
  marg.of(O.Arena.op(ar, s), ar, s)

# `xs + ys` for two shape answers, or `None` if either is `None`. The two-`Maybe`
# join the movement arms below need, and it is ONE def because Bend SPENDS a
# `Maybe` when it reads it: `match m n: case Some{g} Some{h}: ... case _ _:` is the
# only spelling that sees both, and `+` CANNOT be spelled on a `Maybe` parameter.
def both(m: Maybe<&2, List<&2, O.Sint>>, n: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m n:
    case Some{g} Some{h}: Some{List.append(&2, O.Sint, g, h)}
    case _ _            : None{}

# `self.src[k].as_shape` for any `k`, because PAD and SHRINK read `src[1]` AND
# `src[2]` (`tuple(zip(self.src[1].as_shape, self.src[2].as_shape))`, ops.py:817)
# and the two are read by the SAME walk, so this is one def with the index as a
# parameter rather than two defs.
def marg.at(k: U32, +ar: O.Arena, i: U32) -> Maybe<&2, List<&2, O.Sint>>:
  +s = O.Arena.src(ar, i, k)
  marg.of(O.Arena.op(ar, s), ar, s)

# `case Ops.EXPAND: return tuple(self.marg) + ps` -- ops.py:414-415. THE ONLY
# MOVEMENT ARM WITH NO CHECK AT ALL, which is why it is first: it reuses `marg`
# verbatim, and the dtype is `GroupOp.Movement`'s `return src[0].dtype` that
# `reshape_ds` already reads. A `Maybe` on either side is `None`, so a symbolic
# marg is the `ssimplify` wall and a shape-less src is ops.py:407's raise.
def expand_ds(+ar: O.Arena, i: U32, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of(src_dt(0, ss), both(marg(ar, i), src_shape(0, ss)))

# ===========================================================================
# PAD AND SHRINK -- ops.py:419-428. THE TWO ARMS ARE ONE WALK.
#
# Both read `marg`, which for them is `tuple(zip(self.src[1].as_shape,
# self.src[2].as_shape))` (ops.py:817) -- a LIST OF PAIRS, offsets then sizes. Both
# check `len(ps) == len(marg)` and one sum per dim, they differ ONLY in which sum and
# in which operand order, and both ANSWER `tuple(sz for _,sz in marg)`. So the pair
# is one walk carrying a `Bool` that picks the arm, which is the same
# "the answer and the flag are one value" rule as `Prod` and `Marg` above.
#
# `pad=True` is PAD's `resolve(o+s<=sz)` and `pad=False` is SHRINK's `resolve(o+sz<=s)`
# -- the SAME three numbers with the other two swapped. Both are U32: a dim and an
# offset are non-negative counts under 2^31 (`sint_of`'s note), so the sum cannot
# overflow and `helpers.bend`'s broken `i64_add` is not needed. That is the reason
# these two arms land while `_min_max` does not.
#
# `resolve` DEFAULTS TO TRUE for a symbolic operand (ops.py:64), so CPython ACCEPTS a
# symbolic offset; the fold cannot read one at all, so it refuses. That is the
# uniform rule from the header -- a rule it cannot run is not a rule that passed --
# and `mv_padsym` is the row that measures the difference.
# ===========================================================================

# A DIM AS A COUNT, or a refusal: an `O.SU` is an arena index and `resolve` needs a
# number, and a negative dim is ops.py's `resolve(sz>=0)` failing. Both are `None`.
def some_u32(ok: Bool, +x: U32) -> Maybe<&1, U32>:
  match ok:
    case True{}: Some{x}
    case False{}: None{}

def count_of.of(+i: H.I64) -> Maybe<&1, U32>:
  some_u32(Bool.not(H.i64_is_neg(i)), H.lo32(i))

def count_of(d: O.Sint) -> Maybe<&1, U32>:
  match d:
    case O.SU{u}: None{}
    case O.SI{i}: count_of.of(i)

# THE THREE HEADS OF ONE DIM -- the source dim `s`, the offset `o`, the size `z` --
# and `None` if any is unreadable. Three `Maybe`s and three defs, because a `Maybe`
# is read once, cannot take `+`, and a `match` may not scrutinise a call.
type Tri is Data:
  Tri{s: U32, o: U32, z: U32}

def Tri.of3(s: U32, o: U32, z: Maybe<&1, U32>) -> Maybe<&1, Tri>:
  match z:
    case Some{c}: Some{Tri{s, o, c}}
    case None{}  : None{}

def Tri.put3(s: U32, o: U32, z: O.Sint) -> Maybe<&1, Tri>:
  Tri.of3(s, o, count_of(z))

def Tri.of2(s: U32, o: Maybe<&1, U32>, z: O.Sint) -> Maybe<&1, Tri>:
  match o:
    case Some{b}: Tri.put3(s, b, z)
    case None{}  : None{}

def Tri.put2(s: U32, o: O.Sint, z: O.Sint) -> Maybe<&1, Tri>:
  Tri.of2(s, count_of(o), z)

def Tri.of1(s: Maybe<&1, U32>, o: O.Sint, z: O.Sint) -> Maybe<&1, Tri>:
  match s:
    case Some{a}: Tri.put2(a, o, z)
    case None{}  : None{}

def Tri.of(s: O.Sint, o: O.Sint, z: O.Sint) -> Maybe<&1, Tri>:
  Tri.of1(count_of(s), o, z)

# `resolve(sz>=0) and resolve(0<=o) and resolve(o+s<=sz)`, whose `sz>=0` and `0<=o`
# are already done by `count_of`'s refusal. PAD is `o+s<=sz`; SHRINK is `o+sz<=s`.
# `+` on the three binders because each is read twice in one expression.
def Tri.le(t: Tri, +pad: Bool) -> Bool:
  match t:
    case Tri{+s, +o, +z}: Bool.pick(Bool, pad, U32.is_le(U32.add(o, s), z), U32.is_le(U32.add(o, z), s))

def tri_ok(t: Maybe<&1, Tri>, +pad: Bool, good: Bool) -> Bool:
  match t:
    case Some{v}: Bool.and(good, Tri.le(v, pad))
    case None{}  : False{}

# THE ANSWER AND THE FLAG, one value, for the reason `Prod` exists.
type Pairs is Data:
  Pairs{szs: List<&2, O.Sint>, ok: Bool}

def Pairs.szs(x: Pairs) -> List<&2, O.Sint>:
  match x:
    case Pairs{szs, ok}: szs

def Pairs.ok(x: Pairs) -> Bool:
  match x:
    case Pairs{szs, ok}: ok

# THE LOCKSTEP WALK over `ps`, the offsets and the sizes -- THREE `Maybe`s, because
# `src[0]._shape`, `src[1].as_shape` and `src[2].as_shape` are all `Maybe` here and
# a `Maybe` is read once, cannot be `+`, and cannot be a scrutinee that a second
# `match` re-reads. So the WALK takes the three of them and does the unpacking itself:
# a three-scrutinee `match` on three `Maybe`s with `_ _ _` as the cover is the only
# spelling that sees all three, and it is the shape `.agents/slop/oracles/
# fold-probe-mvt.bend`'s P1 already measured.
#
# `Nil Nil Nil` is the whole triple consumed, and `_ _ _` is BOTH failures in one
# arm: `len(ps) != len(self.marg)` (ops.py:421/426's first disjunct) and a `None`
# element, which is the `ssimplify` wall. Neither is an early return, because a
# `match` that returns from the middle of a walk is mutual recursion.
# THE LOCKSTEP WALK, AND IT IS **ONE** DEF WITH A THREE-SCRUTINEE `match`.
#
# Four attempts failed before this one and the errors are worth the space:
#   * a `.go`/`.step` pair -- one unpacking two `Maybe`s, one matching the lists --
#     is MUTUAL RECURSION, refused in either declaration order;
#   * a three-scrutinee `match` over (list, `Maybe`, `Maybe`) is refused too, with
#     "expected a constructor of Maybe": the scrutinees must share a shape;
#   * `List.last`/`List.tail` in place of the pattern head satisfies the decrease
#     check but needs a THIRD def for the heads, which is back to two;
#   * folding the `Maybe`s into a `Data` record needs the record read three times,
#     which is `+` on a record and not on the walk.
# What works is the shape `.agents/slop/oracles/fold-probe-mvt2.bend` P6 measured:
# the walk takes THREE PLAIN LISTS and does the three-scrutinee `match` itself, so
# the tails are binders and the self-call decreases in the first parameter it
# forwards. The `Maybe`s are resolved OUTSIDE it, by `pair3` below, which is NOT
# recursive and so is free to be a chain.
#
# `Nil Nil Nil` is the whole triple consumed and `_ _ _` is `len(ps) != len(self.marg)`
# -- ops.py:421/426's first disjunct -- as a cover arm rather than an early return,
# because a `match` returning early from the middle of a walk is the mutual recursion
# just refused. That is why the length check is a `Bool` on the accumulator.
def pad_shrink.go(ps: List<&2, O.Sint>, os: List<&2, O.Sint>, szs: List<&2, O.Sint>, +pad: Bool, +x: Pairs) -> Pairs:
  match ps os szs:
    case p <> pt, o <> ot, +z <> zt : pad_shrink.go(pt, ot, zt, pad,
      Pairs{List.append(&2, O.Sint, Pairs.szs(x), [z]), tri_ok(Tri.of(p, o, z), pad, Pairs.ok(x))})
    case Nil{} Nil{} Nil{}          : x
    case _ _ _                      : Pairs{Pairs.szs(x), False{}}

# THE TWO `as_shape` ANSWERS AS LISTS, and a `None` on either is the `ssimplify`
# wall, which lands on the same refusal as a length mismatch -- so this chain has no
# arm that continues past a `None`. It is three defs because a `Maybe` is read once
# and cannot be `+`; it is NOT a recursion, so nothing is mutual.
def pair3.oz(+pad: Bool, ps: List<&2, O.Sint>, os: List<&2, O.Sint>, szs: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&1, Pairs>:
  match szs:
    case Some{z}: Some{pad_shrink.go(ps, os, z, pad, Pairs{Nil{}, True{}})}
    case None{}  : None{}

def pair3.os(+pad: Bool, ps: List<&2, O.Sint>, os: Maybe<&2, List<&2, O.Sint>>, szs: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&1, Pairs>:
  match os:
    case Some{o}: pair3.oz(pad, ps, o, szs)
    case None{}  : None{}

def pair3.of(+pad: Bool, ps: Maybe<&2, List<&2, O.Sint>>, os: Maybe<&2, List<&2, O.Sint>>, szs: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&1, Pairs>:
  match ps:
    case Some{p}: pair3.os(pad, p, os, szs)
    case None{}  : None{}

# ===========================================================================
# PERMUTE -- ops.py:416-418. `if sorted(self.marg) != list(range(len(ps))): raise`
# then `return tuple(ps[i] for i in self.marg)`.
#
# THE WALL THIS ARM HAD WAS NOT THE ONE ON THE TODO LIST. The header says PERMUTE is
# deferred because "`marg` -> `as_shape` -> `ssimplify`", and that is TRUE OF
# `marg`'s OTHER TWO ARMS and FALSE of this one: `marg` for PERMUTE is `self.arg`
# (ops.py:818) -- the arena's `ATuple`, a `List<&2, U32>` of plain indices -- so no
# `as_shape` and no `ssimplify` is involved at all. `sorted(marg) == range(len(ps))`
# is a PERMUTATION TEST and the answer is a PERMUTATION, so the arm was answerable
# from the day the arena existed. That is the finding this unit retires.
#
# `sorted(ys) == list(range(n))` is tested WITHOUT SORTING, because `List.sort` needs
# a comparator value and a fold is cheaper: the two halves of the statement are
# "every index is in range" and "no index repeats", and together they are exactly
# "the multiset is {0..n-1}". `range(n)` also forces the LENGTH, which is why the
# walk counts rather than merely bounding.
# ===========================================================================

# `sorted(self.marg) != list(range(len(ps)))`, over the walk that also builds the
# answer. `seen` is the multiset-so-far, so "no repeat" is a membership test.
type Perm is Data:
  Perm{ds: List<&2, O.Sint>, seen: List<&2, U32>, ok: Bool}

def Perm.ds(x: Perm) -> List<&2, O.Sint>:
  match x:
    case Perm{ds, seen, ok}: ds

def Perm.seen(x: Perm) -> List<&2, U32>:
  match x:
    case Perm{ds, seen, ok}: seen

def Perm.ok(x: Perm) -> Bool:
  match x:
    case Perm{ds, seen, ok}: ok

def mem_u32(xs: List<&2, U32>, +y: U32) -> Bool:
  match xs:
    case Nil{} : False{}
    case x <> t: Bool.pick(Bool, U32.is_eq(x, y), True{}, mem_u32(t, y))

# ONE STEP: read the index, test the two halves, and append the picked dim. The
# picked dim is `None` when the index is out of range, and `List.get` answers
# they agree rather than covering for one another.
#
# THE WALK, AND IT IS **ONE** DEF. The first attempt was `.go`/`.of`/`.put` -- one
# that matches the arg, one that reads the index, one that appends -- and `.go`/`.of`
# are MUTUAL RECURSION, which Bend refuses in either declaration order. Collapsing
# them is the same fix `pad_shrink` needed, and the `Maybe` from `List.get` is why
# there is nothing left to split: an out-of-range index answers `None`, which is the
# SAME refusal as a failed test, so one `Some`/`None` match carries both.
#
# `n = len(ps)` is threaded so the range test reads the shape's own length rather than
# a re-derived count, and `seen` is the multiset-so-far, so "no repeat" is a
# membership test rather than a sort -- `sorted(marg) != list(range(len(ps)))` is
# "every index in range AND no index repeated", because `range(n)` fixes the length.
# THE STEP, and `d` is the INDEX READ as its own parameter so the `Some`/`None`
# match can live in `perm.add` without the walk calling `.add` and `.add` calling
# the walk: `perm.go` calls `perm.put` once, `perm.put` calls `perm.add` once, and
# `perm.add` calls NOTHING. One recursion, three defs, no cycle.
# AND IT IS **ONE** DEF, WITH THE `Maybe` INSIDE A `Data` RECORD.
#
# The record's field is a `Maybe` on purpose: a `Data` record CAN carry a `Maybe` and
# a `Maybe` PARAMETER cannot be `+`, so this is the one place the two rules compose
# into the answer. The alternatives all failed, and the errors are worth keeping:
#   * `.go`/`.of`/`.put` -- `.go` and `.of` are MUTUAL RECURSION (refused), and
#   * `.go`/`.step`/`.put` -- every split here is, because `.step` needs `.go` to
#     recurse and `.go` needs `.step` to read the index.
# The step is `match ys: case y <> t: f(<a call>)`, and a call in a scrutinee position
# is what forces the split -- so the call's RESULT goes into the record instead.
type Step is Data:
  Step{d: Maybe<&2, O.Sint>, y: U32, t: List<&2, U32>}

# THE INDEX READ. `List.get` answers a `Maybe` and a `Maybe` cannot be `+`, so it
# travels inside `Step` rather than as a parameter, and `Step` is the `Data` that
# makes the "read the index once, use it twice" spelling legal.
def perm_step(+y: U32, +t: List<&2, U32>, +ps: List<&2, O.Sint>) -> Step:
  Step{List.get(&2, O.Sint, ps, U32.to_nat(y)), y, t}

# AND THE TEST. `sorted(marg) != list(range(len(ps)))` is "every index in range AND
# no index repeated", and the FIRST half is `List.get`'s own `None`, so only the
# second is written: the picked dim and the no-repeat test are ONE value, which is
# the `Prod`/`Marg` rule again.
def perm_add.go(d: Maybe<&2, O.Sint>, +y: U32, +t: List<&2, U32>, +x: Perm) -> Perm:
  match d:
    case Some{v}: Perm{List.append(&2, O.Sint, Perm.ds(x), [v]),
      List.append(&2, U32, Perm.seen(x), [y]),
      Bool.and(Perm.ok(x), Bool.not(mem_u32(Perm.seen(x), y)))}
    case None{}  : Perm{Perm.ds(x), Perm.seen(x), False{}}

def perm_add(st: Step, +x: Perm) -> Perm:
  match st:
    case Step{+d, +y, +t}: perm_add.go(d, y, t, x)

# THE WALK, and `n = len(ps)` IS GONE. It was there to test "every index is in
# range", and then the mutation `perm_init` passing `2^32-1` instead of `len(ps)`
# moved NOTHING -- because `List.get(ps, y)` is ALREADY `None` exactly when
# `y >= len(ps)`. The explicit range test was the same fact twice, so it is deleted
# rather than kept and trusted: `List.get` is the range test, and `mv_permlen` is
# the row that says so.
def perm.go(ys: List<&2, U32>, +ps: List<&2, O.Sint>, +x: Perm) -> Perm:
  match ys:
    case Nil{}  : Perm{Perm.ds(x), Perm.seen(x), Perm.ok(x)}
    case y <> +t : perm.go(t, ps, perm_add(perm_step(y, t, ps), x))

# THE SEED, and `ps` IS THE SHAPE -- measured, not reasoned: the first version
# seeded `Nil{}` and `perm` read ABSENT on a VALID (1, 0) as well as on the two
# rejects, because `List.get(Nil, 0)` is `None` and every step took the `None` arm.
def perm_init(ys: List<&2, U32>, +ps: List<&2, O.Sint>) -> Perm:
  perm.go(ys, ps, Perm{Nil{}, Nil{}, True{}})

# THE WALK AND THE ANSWER, and `Perm.ok`/`Perm.ds` read the record ONCE EACH by
# passing it `+` to `perm_ds.of_walk` -- the alternative, writing `perm_init` twice
# in one expression, is legal only because the call is PURE ("`proc(t)` spelled
# twice is two walks, not a shared binding") and it doubles the walk for nothing.
def perm_ds.of_walk(+x: Perm, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of_if(Perm.ok(x), src_dt(0, ss), Some{Perm.ds(x)})

def perm_ds.of(ys: List<&2, U32>, ps: Maybe<&2, List<&2, O.Sint>>, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match ps:
    case Some{+p}: perm_ds.of_walk(perm_init(ys, p), ss)
    case None{}  : None{}

# `self.arg` -- the arena's `ATuple{ys}` -- which is `marg` for PERMUTE and FLIP both.
def order_arg(arg: O.Arg) -> List<&2, U32>:
  match arg:
    case O.ATuple{ys}: ys
    case _           : Nil{}

def perm_ds(+ar: O.Arena, i: U32, arg: O.Arg, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  perm_ds.of(order_arg(arg), src_shape(0, ss), ss)

# ===========================================================================
# FLIP -- ops.py:429-431. `if len(ps) != len(self.marg) or not all(isinstance(x,
# bool) for x in self.marg): raise` then `return ps`.
#
# THE BOOL HALF OF THAT CHECK IS NOT IN THE ARENA, and this is a MEASURED fact about
# CPython rather than a Bend limitation, so it is worth stating carefully:
#   * `movement.py:253` builds `flip_arg = tuple([i in axis_arg for i in
#     range(len(self.shape))])` -- always a tuple of Python bools, one per dim.
#   * The arena spells that arg `ATuple{ys}` with `ys: List<&2, U32>`, which erases
#     `True`/`False` into 1/0. ops.bend is not this unit's file, so the Bool-ness is
#     not recoverable here and is NOT recovered.
#   * MEASURED, and this is the part that matters: CPython's own `all(isinstance(x,
#     bool))` is UNREACHABLE as a rejection. `UOp(Ops.FLIP, src, (1, 0))` raises
#     `bad flip on (4, 3), (1, 0)` -- but only if the int node was interned FIRST.
#     Intern the bool spelling first and `UOp(Ops.FLIP, src, (1, 0))` returns THE
#     BOOL NODE (`b is a` measured True, because the ucache key is
#     `(op, src, arg, tag, type(arg))` and `type(arg)` is `tuple` for both, while
#     `True == 1` as dict keys). So the answer for a given src is whichever spelling
#     the arena saw first, and a Flip built through `movement.py` always answers.
# The length check IS in the arena and IS ported, and it is the reachable one.
# ===========================================================================

def flip_ds.put(ys: List<&2, U32>, +ps: List<&2, O.Sint>, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of_if(Nat.is_eq(List.length(&2, U32, ys), List.length(&2, O.Sint, ps)), src_dt(0, ss), Some{ps})

def flip_ds.of(ys: List<&2, U32>, ps: Maybe<&2, List<&2, O.Sint>>, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match ps:
    case Some{p}: flip_ds.put(ys, p, ss)
    case None{}  : None{}

def flip_ds(+ar: O.Arena, i: U32, arg: O.Arg, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  flip_ds.of(order_arg(arg), src_shape(0, ss), ss)

# `if len(ps) != len(self.marg) or not all(...)` then `return tuple(sz for _,sz in
# marg)` -- the answer and the flag out of ONE walk, and `marg` is
# `zip(as_shape(src[1]), as_shape(src[2]))`, so the sizes ARE the answer.
def pair_ds.put(+pad: Bool, x: Maybe<&1, Pairs>, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match x:
    case Some{+v}: dt_of_if(Pairs.ok(v), src_dt(0, ss), Some{Pairs.szs(v)})
    case None{}  : None{}

def pair_ds.of(+pad: Bool, x: Maybe<&1, Pairs>, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  pair_ds.put(pad, x, ss)

# THE TWO ARMS' ENTRY POINTS, and the ONLY difference between them is the `Bool`:
# PAD's `resolve(o+s<=sz)` and SHRINK's `resolve(o+sz<=s)` are the same three numbers
# with the other two swapped. One `Bool`, two entry points, one walk.
def pad_ds(+ar: O.Arena, +i: U32, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  pair_ds.of(True{}, pair3.of(True{}, src_shape(0, ss), marg.at(1, ar, i), marg.at(2, ar, i)), ss)

def shrink_ds(+ar: O.Arena, +i: U32, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  pair_ds.of(False{}, pair3.of(False{}, src_shape(0, ss), marg.at(1, ar, i), marg.at(2, ar, i)), ss)

# ===========================================================================
# THE TWO CHECKS, ops.py:410-412, and they are ONE walk.
#
#   if not all(x >= 0 for x in self.marg): raise ValueError(...)
#   if resolve(prod(ps) != prod(self.marg), False): raise ValueError(...)
#
# Both read the same `SI`s of the same `marg`, so they are one walk: `marg_prod`
# multiplies them and refuses a negative one, and the refusal is the `>= 0`
# raise. `prod` is U32 because `sint_of` fixes the bound -- "every count that
# reaches a shape is a dim or a length, so it is under 2^31" -- and a product of
# a handful of those fits a U32.
#
# A `SU` ANYWHERE is None, and that is `resolve`'s own `False` default read from
# the side that is safe: `prod` of a `SU` is a uop, `x >= 0` on one is a rewrite,
# so neither check can be RUN, and a check that cannot be run is not a check
# that passed. Python agrees on the marg -- every symbolic fixture in
# `.agents/slop/notes/reshape-oracle.py` prints `bad reshape` -- and on a
# symbolic `ps` `resolve` returns the `False` default, which does not raise, so
# Python would ANSWER there and this fold leaves the node unanswered instead.
# Refusing is this file's uniform rule for a rule it cannot port, and the header
# is explicit that a fold which cannot say "I do not know" is not a fold.
# ===========================================================================

# `prod(xs)` over a `Maybe` shape, in ONE self-recursive def: the product of the
# dims, and `None` for a negative dim (the `all(x >= 0)` raise) or a `SU` dim
# (neither check runnable). The accumulator starts at 1 because
# `functools.reduce(operator.mul, xs, 1)` is what `prod` is, and that is what
# makes `prod(())` 1 -- which is why the GETADDR fixture, whose `ps` is `()`,
# has product 1 and is unequal to a `(2,2)` marg. A `None` shape is the arm's
# OTHER `raise`, `raise RuntimeError(f"movement op {self.op} requires shape,
# ... doesn't have one")` (ops.py:407), and it lands on the same answer.
#
# THE PRODUCT AND THE REFUSAL ARE ONE RECORD, for the reason `Gathered` exists:
# a self-call may not forward-reference, so a walk that multiplies and a walk
# that tests cannot be two defs of a chain, and `bad` is what carries the test
# out of the loop. A negative dim and a `SU` dim are the SAME `bad` -- one is
# Python's `raise`, the other is a check that cannot be run -- so they are one
# flag and not two.
type Prod is Data:
  Prod{n: U32, bad: Bool}

def Prod.n(p: Prod) -> U32:
  match p:
    case Prod{n, bad}: n

def Prod.bad(p: Prod) -> Bool:
  match p:
    case Prod{n, bad}: bad

def marg_prod.mul(+i: H.I64, +p: Prod) -> Prod:
  Prod{U32.mul(Prod.n(p), H.lo32(i)), Bool.or(Prod.bad(p), H.i64_is_neg(i))}

def marg_prod.step(+d: O.Sint, +p: Prod) -> Prod:
  match d:
    case O.SI{i}: marg_prod.mul(i, p)
    case O.SU{u}: Prod{Prod.n(p), True{}}

def marg_prod.done(+p: Prod) -> Maybe<&1, U32>:
  some_if(&1, U32, Bool.not(Prod.bad(p)), Prod.n(p))

def marg_prod.go(ds: List<&2, O.Sint>, +p: Prod) -> Maybe<&1, U32>:
  match ds:
    case Nil{}  : marg_prod.done(p)
    case d <> t : marg_prod.go(t, marg_prod.step(d, p))

def marg_prod1() -> Prod:
  Prod{1, False{}}

def marg_prod(+m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&1, U32>:
  marg_prod.go(Maybe.default(&2, List<&2, O.Sint>, m, Nil{}), marg_prod1())

# `prod(ps) == prod(self.marg)`: equal is the only reading that does not raise,
# and a `None` on either side is "unprovable", which is not an equality
def reshape_ok(a: Maybe<&1, U32>, b: Maybe<&1, U32>) -> Bool:
  match a b:
    case Some{p} Some{q}: U32.is_eq(p, q)
    case _ _             : False{}

# `self.src[0]._shape` -- the `ps` of `resolve(prod(ps) != prod(self.marg), False)`.
#
# `ss` here is `Srcs.ss(srcs(ss))` from `derived`, and it is in ARENA ORDER: `srcs.go`
# used to finish its accumulator with a `List.reverse` over a list `List.append`
# (which is `xs ++ ys`, order preserving) had already built in input order, so the
# list arrived BACKWARDS and `ss[0]` was `self.src[1]`. `srcs.go` no longer reverses,
# so this positional read is `src[0]` as `ops.py:406` spells it. The whole-list walks
# were indifferent to the mirror -- `dts_of.go`, `mstack_dev.go`, `ended_of.flat`,
# `first_dev` -- which is exactly why the gate rows over them stayed green and the
# positional ones did not: their fixtures are order-insensitive.
def reshape_ps(+ss: List<&2, Derived>) -> Maybe<&2, List<&2, O.Sint>>:
  src_shape(0, ss)

# `if self.src[0].op is Ops.NOOP: return self.marg` (ops.py:346, "special
# (terrible) case for RESHAPE on NOOP") skips BOTH checks, because the `if`
# RETURNS before the movement ladder below is reached -- which is what makes
# `g_resh_noop` answer (3,3) over a NOOP whose shape is (4,). The dtype is
# `GroupOp.Movement`'s `return src[0].dtype` either way, and that is void when
# src[0] is a NOOP, because NOOP is in the `always void` set.
def reshape_ds.go(noop: Bool, m: Maybe<&2, List<&2, O.Sint>>, ok: Bool, dt: S.Dt) -> Maybe<&2, DtShape>:
  match noop:
    case True{} : dt_of(dt, m)
    case False{}: dt_of_if(ok, dt, m)

# `marg` is read TWICE because Bend spends a list when it reads it, and this file
# already accepts an O(n) read over an O(n^2) fold (see the header): `marg` is a
# pure def over the arena, so the second read is a second walk and not a second
# borrow. The `Sized`/`Shapes`/`Gathered` records exist for the walks that CANNOT
# be repeated, and this one can.
def reshape_ds.of(noop: Bool, +ar: O.Arena, +i: U32, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  reshape_ds.go(noop, marg(ar, i), reshape_ok(marg_prod(reshape_ps(ss)), marg_prod(marg(ar, i))), src_dt(0, ss))

def is_noop.of(op: O.Op) -> Bool:
  match op:
    case O.OpsNOOP{}: True{}
    case _          : False{}

def reshape_ds(+ar: O.Arena, +i: U32, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  reshape_ds.of(is_noop.of(O.Arena.op(ar, O.Arena.src0(ar, i))), ar, i, ss)

def num_axes(arg: O.Arg) -> U32:
  match arg:
    case O.AReduce{rop, num_axes}: num_axes
    case _: 0

# REDUCE: in `GroupOp.Movement.union({Ops.UNSHARD, Ops.REDUCE})` the dtype is the
# movement pass-through, and `case Ops.REDUCE: num_axes = self.arg[1]` then the axis
# check then `return ps[num_axes:]`
def reduce_ds(arg: O.Arg, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  reduce_ds.go(src_dt(0, ss), reduce_dims(ss, num_axes(arg)))

def cconst_dt.val(v: O.Const) -> Maybe<&1, S.Dt>:
  match v:
    case O.CInvalid{}: Some{S.boolean()}
    case O.CBool{b}: Some{S.boolean()}
    case O.CInt{i}: Some{S.weakint()}
    case O.CFloat{f}: Some{S.weakfloat()}

def cconst_dt(arg: O.Arg) -> Maybe<&1, S.Dt>:
  match arg:
    case O.APy{v}: cconst_dt.val(v)
    case _: None{}

# CONST: the dtype is derived from the value -- `if isinstance(arg, InvalidType):
# return dtypes.bool  # Invalid is always bool, the promo lattice bottom` / `if
# isinstance(arg, bool): return dtypes.bool` / `if isinstance(arg, int): return
# dtypes.weakint` / `if isinstance(arg, float): return dtypes.weakfloat` / `raise
# TypeError(...)` -- and `case Ops.CONST: return ()`.
def const_ds(arg: O.Arg) -> Maybe<&2, DtShape>:
  const_ds.pick(cconst_dt(arg))

def device_of.param(arg: O.Arg) -> Maybe<&2, S.Dev>:
  match arg:
    case O.AParam{pa}: O.ParamArg.device(pa)
    case _: None{}

def device_of.copy(arg: O.Arg) -> Maybe<&2, S.Dev>:
  match arg:
    case O.ADev{dev}: Some{dev}
    case _: None{}

def device_of.allred(arg: O.Arg) -> Maybe<&2, S.Dev>:
  match arg:
    case O.AAllred{rop, dev}: Some{dev}
    case _: None{}

def msel_dev.hit(m: Maybe<&2, U32>) -> Maybe<&2, S.Dev>:
  match m:
    case Some{t}: Some{S.D1{t}}
    case None{}: None{}

def msel_dev.pick(d: Maybe<&2, S.Dev>, k: U32) -> Maybe<&2, S.Dev>:
  match d:
    case Some{S.Dn{tags}}: msel_dev.hit(List.get(&2, U32, tags, U32.to_nat(k)))
    case _: None{}

# `assert isinstance(self.src[0].device, tuple), f"mselect must be on tuple device,
# getting {self.src[0].device}"` then `return self.src[0].device[self.arg]`
def device_of.msel(d: Maybe<&2, S.Dev>, arg: O.Arg) -> Maybe<&2, S.Dev>:
  match arg:
    case O.ATuple{ys}:
      match ys:
        case Nil{}: None{}
        case k <> _: msel_dev.pick(d, k)
    case _: None{}

def mstack_dev.tag.of(acc: Maybe<&2, List<&2, U32>>, tag: U32) -> Maybe<&2, List<&2, U32>>:
  match acc:
    case Some{ts}: Some{List.append(&2, U32, ts, [tag])}
    case None{}: None{}

# One operand of the tuple: `cast(str, x.device)` waves a tuple device through, so
# `S.Dn` is the tags in operand order and a `D1` is the only operand a tuple of
# names can be built from. A `None` device is a refused operand.
def mstack_dev.acc.of(acc: Maybe<&2, List<&2, U32>>, dv: Maybe<&2, S.Dev>) -> Maybe<&2, List<&2, U32>>:
  match dv:
    case Some{S.D1{tag}}: mstack_dev.tag.of(acc, tag)
    case _: None{}

# all four states of (the tags so far, this operand's device), written out
def mstack_dev.acc(d: Derived, acc: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  mstack_dev.acc.of(acc, Derived.dev(d))

# `return tuple(cast(str, x.device) for x in self.src)`. `S.Dn` is that tuple of
# names, so it is the operand tags in order, and an operand with no device is None.
def mstack_dev.go(ss: List<&2, Derived>, acc: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match ss:
    case Nil{}: acc
    case d <> t: mstack_dev.go(t, mstack_dev.acc(d, acc))

def mstack_dev.put(m: Maybe<&2, List<&2, U32>>) -> Maybe<&2, S.Dev>:
  match m:
    case Some{ts}: Some{S.Dn{ts}}
    case None{}: None{}

def mstack_dev(ss: List<&2, Derived>) -> Maybe<&2, S.Dev>:
  mstack_dev.put(mstack_dev.go(ss, Some{Nil{}}))

# ===========================================================================
# `UOp.device` -- ops.py:890. Its own `match op` because Python's is. ops.py's own
# comments, kept: "mselect must be on tuple device".
# ===========================================================================

def device_of(ar: O.Arena, i: U32, op: O.Op, arg: O.Arg, ss: List<&2, Derived>) -> Maybe<&2, S.Dev>:
  match op:
    case O.OpsPARAM{}: device_of.param(arg)
    case O.OpsBUFFER{}: device_of.param(arg)
    case O.OpsALLOC{}: device_of.param(arg)
    # `self.src[0].device if self.arg is None else self.arg.device`, and a STAGE's
    # arg IS None in the arena
    case O.OpsSTAGE{}: src_dev(0, ss)
    case O.OpsAFTER{}: src_dev(0, ss)
    case O.OpsMSELECT{}: device_of.msel(src_dev(0, ss), arg)
    case O.OpsMSTACK{}: mstack_dev(ss)
    case O.OpsCOPY{}: device_of.copy(arg)
    case O.OpsALLREDUCE{}: device_of.allred(arg)
    # `for x in self.src:` / `if x.device is not None: return x.device` / `return None`
    case _: first_dev(ss)

# `if self.op is Ops.PARAM: return self.arg.addrspace` and the same for BUFFER and
# ALLOC
def addrspace_of.param(arg: O.Arg) -> Maybe<&2, S.Addr>:
  match arg:
    case O.AParam{pa}: Some{O.ParamArg.addrspace(pa)}
    case _: None{}

# `ad = [x.addrspace for x in self.src if x.addrspace is not None]` / `if not
# len(ad) or not all_same(ad): return None` / `return ad[0]`
type Uniq is Data:
  Uniq{ad: Maybe<&2, S.Addr>, ok: Bool}

def uniq_cmb(ad: Maybe<&2, S.Addr>, +p: S.Addr, ok: Bool) -> Uniq:
  match ad:
    case None{}: Uniq{Some{p}, ok}
    case Some{q}: Uniq{Some{p}, Bool.and(ok, O.eq_addr(q, p))}

def uniq_add(a: Maybe<&2, S.Addr>, u: Uniq) -> Uniq:
  match a u:
    case Some{p} Uniq{ad, ok}: uniq_cmb(ad, p, ok)
    case None{} _: u

def one_addr.go(ss: List<&2, Derived>, u: Uniq) -> Uniq:
  match ss:
    case Nil{}: u
    case d <> t: one_addr.go(t, uniq_add(Derived.addr(d), u))

def uniq_pick2(ok: Bool, ad: Maybe<&2, S.Addr>) -> Maybe<&2, S.Addr>:
  match ok:
    case True{}: ad
    case False{}: None{}

def uniq_pick(u: Uniq) -> Maybe<&2, S.Addr>:
  match u:
    case Uniq{ad, ok}: uniq_pick2(ok, ad)

def one_addr(ss: List<&2, Derived>) -> Maybe<&2, S.Addr>:
  uniq_pick(one_addr.go(ss, Uniq{None{}, True{}}))

def addrspace_of.ew(ew: Bool, ss: List<&2, Derived>) -> Maybe<&2, S.Addr>:
  match ew:
    case True{}: one_addr(ss)
    case False{}: None{}

def addrspace_of.alu(op: O.Op, ss: List<&2, Derived>) -> Maybe<&2, S.Addr>:
  addrspace_of.ew(O.GroupOp.elementwise(op), ss)

def addrspace_of.mv(mv: Bool, op: O.Op, ss: List<&2, Derived>) -> Maybe<&2, S.Addr>:
  match mv:
    case True{}: src_addr(0, ss)
    case False{}: addrspace_of.alu(op, ss)

def addrspace_of.rest(+op: O.Op, ss: List<&2, Derived>) -> Maybe<&2, S.Addr>:
  addrspace_of.mv(O.GroupOp.movement(op), op, ss)

# ===========================================================================
# `UOp.addrspace` -- ops.py:910. Its own `match op`, and the two group tests.
# ops.py's own comments, kept: "LOAD brings things into the ALU" and the
# `ad`/`all_same` rejection spelled out above.
# ===========================================================================

def addrspace_of(arg: O.Arg, op: O.Op, ss: List<&2, Derived>) -> Maybe<&2, S.Addr>:
  match op:
    case O.OpsPARAM{}: addrspace_of.param(arg)
    case O.OpsBUFFER{}: addrspace_of.param(arg)
    case O.OpsALLOC{}: addrspace_of.param(arg)
    case O.OpsBINARY{}: Some{S.AGlobal{}}
    # LOAD brings things into the ALU
    case O.OpsLOAD{}: Some{S.Aalu{}}
    # `if self.op in {Ops.SPECIAL, Ops.RANGE, Ops.CONST}: return AddrSpace.ALU`
    case O.OpsSPECIAL{}: Some{S.Aalu{}}
    case O.OpsRANGE{}: Some{S.Aalu{}}
    case O.OpsCONST{}: Some{S.Aalu{}}
    # `if self.op in {Ops.INDEX, Ops.CAST, Ops.AFTER, Ops.REDUCE, Ops.STORE,
    # Ops.MSTACK, Ops.MSELECT, Ops.END, Ops.UNSHARD}: return self.src[0].addrspace`
    case O.OpsINDEX{}: src_addr(0, ss)
    case O.OpsCAST{}: src_addr(0, ss)
    case O.OpsAFTER{}: src_addr(0, ss)
    case O.OpsREDUCE{}: src_addr(0, ss)
    case O.OpsSTORE{}: src_addr(0, ss)
    case O.OpsMSTACK{}: src_addr(0, ss)
    case O.OpsMSELECT{}: src_addr(0, ss)
    case O.OpsEND{}: src_addr(0, ss)
    case O.OpsUNSHARD{}: src_addr(0, ss)
    case O.OpsSTACK{}: one_addr(ss)
    case O.OpsWMMA{}: one_addr(ss)
    case O.OpsGROUP{}: one_addr(ss)
    # `if self.op in GroupOp.Movement` and `or GroupOp.Elementwise`
    case _: addrspace_of.rest(op, ss)

def base_of.is_detach(op: O.Op) -> Bool:
  match op:
    case O.OpsDETACH{}: True{}
    case _: False{}

def base_of.steps(+op: O.Op) -> Bool:
  Bool.or(O.GroupOp.movement(op), base_of.is_detach(op))

# ===========================================================================
# `UOp.base` and `UOp.is_invalid` -- ops.py:785 and ops.py:265. `base` is
# `self.src[0].base` for a movement op or for DETACH ("DETACH can't change base")
# and `self` otherwise, so the fold carries the INDEX rather than the walk: a
# node's base is a node before it, so the src's base is already in the table.
# ===========================================================================

def base_of(i: U32, op: O.Op, ss: List<&2, Derived>) -> U32:
  base_of.go(ss, i, base_of.steps(op))

def is_cinvalid.val(v: O.Const) -> Bool:
  match v:
    case O.CInvalid{}: True{}
    case _: False{}

def is_cinvalid(arg: O.Arg) -> Bool:
  match arg:
    case O.APy{v}: is_cinvalid.val(v)
    case _: False{}

def is_invalid.go(op: O.Op, arg: O.Arg) -> Bool:
  match op:
    case O.OpsCONST{}: is_cinvalid(arg)
    case _: False{}

def is_invalid.of(op: O.Op, arg: O.Arg) -> Bool:
  is_invalid.go(op, arg)

# `self.op is Ops.CONST and self.val is Invalid`, on the node's OWN arg, so this
# reader is total where `sp_base` in spec.bend is not
def is_invalid(+ar: O.Arena, +u: U32) -> Bool:
  is_invalid.of(O.Arena.op(ar, u), O.Arena.arg(ar, u))

def unary_dt(ar: O.Arena, +ss: List<&2, Derived>) -> S.Dt:
  unary_dt.go(is_invalid(ar, src_base(0, ss)), src_dt(0, ss))

# SIN | LOG2 | EXP2 | SQRT | RECIPROCAL: `return dtypes.bool if
# src[0].base.is_invalid else least_upper_float(src[0].dtype)`, and `_shape`'s
# `GroupOp.Unary.union({Ops.CAST})` arm `return self.src[0]._shape`
def unary_ds(ar: O.Arena, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of(unary_dt(ar, ss), src_shape(0, ss))

def int_or_invalid(ar: O.Arena, +d: Derived) -> Bool:
  Bool.or(S.Dt.is_int(Derived.dt(d)), is_invalid(ar, Derived.base(d)))

def all_int_or_invalid.go(+ar: O.Arena, ss: List<&2, Derived>, ok: Bool) -> Bool:
  match ss:
    case Nil{}: ok
    case d <> t: all_int_or_invalid.go(ar, t, Bool.and(ok, int_or_invalid(ar, d)))

def all_int_or_invalid(ar: O.Arena, ss: List<&2, Derived>) -> Bool:
  all_int_or_invalid.go(ar, ss, True{})

def shift_ds.of(ar: O.Arena, +x: Srcs) -> Maybe<&2, DtShape>:
  dt_of_if(all_int_or_invalid(ar, Srcs.ss(x)), src_dt(0, Srcs.ss(x)), bcast_shape(all_shapes(Srcs.ss(x))))

# SHL | SHR: the int check, then `return src[0].dtype`; the shape is the
# Broadcastable arm.
def shift_ds(ar: O.Arena, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  shift_ds.of(ar, srcs(ss))

# ===========================================================================
# THE LADDER. `dtype_from_uop` (ops.py:124) and `UOp._shape` (ops.py:329), together:
# here are the dtype production rules, total over all Ops, grouped by the RULE each
# arm uses. See the block above for ops.py's own comments on the arms.
# ===========================================================================

def dt_shape(ar: O.Arena, i: U32, op: O.Op, arg: O.Arg, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match op:
    case O.OpsBUFFER{}: param_ds(arg)
    case O.OpsALLOC{}: param_ds(arg)
    case O.OpsPARAM{}: param_ds(arg)
    case O.OpsCALL{}: call_ds(arg)
    case O.OpsINS{}: ins_ds(arg)
    case O.OpsCAST{}: cast_ds(arg, ss)
    case O.OpsBITCAST{}: bitcast_ds(arg, ss)
    case O.OpsCONST{}: const_ds(arg)
    case O.OpsBINARY{}: binary_ds(arg)
    case O.OpsNOOP{}: noop_ds(ar, i, ss)
    case O.OpsINDEX{}: index_ds(ar, i, ss)
    case O.OpsSTACK{}: stack_ds(ss)
    case O.OpsWMMA{}: wmma_ds(ss)
    case O.OpsREDUCE{}: reduce_ds(arg, ss)
    case O.OpsGETADDR{}: addr_ds()

    # `if op in GroupOp.Movement.union({Ops.UNSHARD, Ops.REDUCE})` -- "movement ops
    # change the shape" -- and the ONE arm of it whose arg `shape_to_shape_arg`
    # builds out of CONSTs, which is the one movement shape this file can derive.
    # `reshape_ds` above: ops.py:346 and ops.py:409.
    case O.OpsRESHAPE{}: reshape_ds(ar, i, ss)
    # `case Ops.EXPAND: return tuple(self.marg) + ps` -- ops.py:414. PORTED: the one
    # movement arm that reads NO CHECK, so the `ssimplify` wall is reachable only
    # through a symbolic marg (`as_shape`'s `ssimplify(s)`), never through a check.
    case O.OpsEXPAND{}: expand_ds(ar, i, ss)
    # `case Ops.PAD` / `case Ops.SHRINK` -- ops.py:419-428. PORTED as ONE walk with a
    # `Bool` that picks the arm: the two differ only in which sum and in the operand
    # order, and both answer the sizes. `pad_shrink` above.
    case O.OpsPAD{}: pad_ds(ar, i, ss)
    case O.OpsSHRINK{}: shrink_ds(ar, i, ss)
    # `case Ops.PERMUTE` / `case Ops.FLIP` -- ops.py:416-431. PORTED, and NOT behind
    # the `ssimplify` wall the header recorded for them: `marg` for both is
    # `self.arg` (ops.py:818), which is the arena's `ATuple` of plain indices, so
    # neither reads `as_shape`. See `perm_ds` and `flip_ds` above.
    case O.OpsPERMUTE{}: perm_ds(ar, i, arg, ss)
    case O.OpsFLIP{}: flip_ds(ar, i, arg, ss)

    # RANGE | SPECIAL: pass through first, then `return ()`
    case O.OpsRANGE{}: rlike(ss)
    case O.OpsSPECIAL{}: rlike(ss)

    # always void, and late ops don't have shape: the same twelve ops in both ladders
    case O.OpsREWRITE_ERROR{}: late()
    case O.OpsPROGRAM{}: late()
    case O.OpsLINEAR{}: late()
    case O.OpsSOURCE{}: late()
    case O.OpsSINK{}: late()
    case O.OpsGROUP{}: late()
    case O.OpsBARRIER{}: late()
    case O.OpsIF{}: late()
    case O.OpsENDIF{}: late()
    case O.OpsBACKEDGE{}: late()
    case O.OpsCUSTOM_FUNCTION{}: late()
    case O.OpsPYLITERAL{}: late()

    # pass through first, then the passthrough ops' `return self.src[0]._shape`
    case O.OpsLOAD{}: thru0(ss)
    case O.OpsAFTER{}: thru0(ss)
    case O.OpsEND{}: thru0(ss)
    case O.OpsDETACH{}: thru0(ss)
    case O.OpsCOPY{}: thru0(ss)
    case O.OpsMSTACK{}: thru0(ss)
    case O.OpsMSELECT{}: thru0(ss)
    case O.OpsCONTIGUOUS_BACKWARD{}: thru0(ss)
    case O.OpsALLREDUCE{}: thru0(ss)
    case O.OpsNEG{}: thru0(ss)
    case O.OpsTRUNC{}: thru0(ss)
    # `always void` in the dtype ladder, passthrough in `_shape`
    case O.OpsSTORE{}: store_ds(ss)

    # `return dtypes.bool if src[0].base.is_invalid else least_upper_float(src[0].dtype)`
    case O.OpsEXP2{}: unary_ds(ar, ss)
    case O.OpsLOG2{}: unary_ds(ar, ss)
    case O.OpsSIN{}: unary_ds(ar, ss)
    case O.OpsSQRT{}: unary_ds(ar, ss)
    case O.OpsRECIPROCAL{}: unary_ds(ar, ss)

    # `return dtypes.bool`, then the Broadcastable arm. NOTE: CMPLT, CMPNE, CMPEQ,
# WHERE, SHL and SHR are handled here rather than by the GroupOp fallbacks.
    case O.OpsCMPLT{}: alu_ds(S.boolean(), ss)
    case O.OpsCMPNE{}: alu_ds(S.boolean(), ss)
    case O.OpsCMPEQ{}: alu_ds(S.boolean(), ss)
    # `least_upper_float(promo_dtype(src))` then the Broadcastable shape arm
    case O.OpsFDIV{}: alu_ds(least_upper_float(promo_dtype(dts_of.go(ss, Nil{}))), ss)
    # `return dtypes.uint64` then the Broadcastable shape arm
    case O.OpsTHREEFRY{}: alu_ds(S.uint64(), ss)
    # the shift int check, then `return src[0].dtype` and the Broadcastable shape
    case O.OpsSHL{}: shift_ds(ar, ss)
    case O.OpsSHR{}: shift_ds(ar, ss)
    # `if src[0].dtype != dtypes.bool: raise` then `promo_dtype(src[1:])`
    case O.OpsWHERE{}: where_ds(ss)

    # `if op in GroupOp.Broadcastable: return promo_dtype(src)` and the
    # Broadcastable shape arm: "elementwise ops keep the shape the same. all inputs
    # with shape must match"
    case O.OpsADD{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsMUL{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsCDIV{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsMAX{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsCMOD{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsXOR{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsOR{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsAND{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsSUB{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsPOW{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsFLOORDIV{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsFLOORMOD{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsMULACC{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)

    # THE DEFERRED OPS, and there are now only THREE of them -- the five movement arms
    # this unit added are `expand_ds`, `pad_ds`, `shrink_ds`, `perm_ds`, `flip_ds`
    # above. Each is an arm `dtype_from_uop` or `_shape` reaches through a rule this
    # file does not port, so the fold does not answer the node. The list is closed:
    # every other op has an arm above, which is what makes the match total without
    # Python's closing `raise RuntimeError(f"no dtype for {op} with arg {arg}")`.
    case O.OpsCUSTOM{}: None{}        # `arg[1]`, and the arena's CUSTOM arg is a str
    case O.OpsCUSTOMI{}: None{}       #   (ops.bend's `Arg`), not the `(str, DType)`
    case O.OpsSTAGE{}: None{}         #   pair. P3: that is a change to `Arg`.
    # "UNSHARD marker has no shape" is the LAST movement wall and it is a DIFFERENT one
    # from the five that landed: the shape is
    # `tuple(s*(int(self.src[1:][self.arg.index(a)].vmax)+1) if a in self.arg else s
    # for a,s in enumerate(ps))`, so it needs `vmax`, which is `_min_max`. `arg.index`
    # is a search over the arg, which the arena's `ATuple` supports, so the wall is
    # `_min_max` alone -- four I64 helpers in helpers.bend and dtype.bend's limits.
    case O.OpsUNSHARD{}: None{}

def ended_of.go(cf: Bool, rest: List<&2, U32>) -> List<&2, U32>:
  match cf:
    case True{}: Nil{}
    case False{}: rest

def is_custom_function.of(op: O.Op) -> Bool:
  match op:
    case O.OpsCUSTOM_FUNCTION{}: True{}
    case _: False{}

def is_custom_function(ar: O.Arena, b: U32) -> Bool:
  is_custom_function.of(O.Arena.op(ar, b))

def ended_of.call(+ar: O.Arena, +i: U32) -> List<&2, U32>:
  ended_of.go(is_custom_function(ar, O.Arena.src0(ar, i)), O.Arena.src_from(ar, i, 1))

# `self.src[1:2]`, which is the one-element list holding src[1]
def ended_of.one(ar: O.Arena, i: U32) -> List<&2, U32>:
  [O.Arena.src(ar, i, 1)]

def is_range.of(op: O.Op) -> Bool:
  match op:
    case O.OpsRANGE{}: True{}
    case _: False{}

def is_range(ar: O.Arena, +s: U32, acc: List<&2, U32>) -> List<&2, U32>:
  add_if(&2, U32, is_range.of(O.Arena.op(ar, s)), s, acc)

# `tuple(r for r in srcs if r.op is Ops.RANGE)`
def ranges_only(+ar: O.Arena, srcs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match srcs:
    case Nil{}: acc
    case s <> t: ranges_only(ar, t, is_range(ar, s, acc))

# ===========================================================================
# `UOp.ended_ranges` -- ops.py:470. It walks DOWN the srcs, so it needs only the
# srcs the fold already answered, and the AFTER/BARRIER arms are exactly
# `H.flatten_u32` over them.
# ===========================================================================

def ended_of(+ar: O.Arena, i: U32, op: O.Op, ss: List<&2, Derived>) -> List<&2, U32>:
  match op:
    # `if self.op is Ops.CALL and self.body.op is Ops.CUSTOM_FUNCTION: return ()`
    # where `body` is `self.src[0]` (ops.py:565). A CALL that is not that falls
    # through to `if self.op in range_start`, and `range_start[CALL]` is 1.
    case O.OpsCALL{}: ended_of.call(ar, i)
    # `if self.op is Ops.END: return tuple(r for r in self.src[1:] if r.op is Ops.RANGE)`
    case O.OpsEND{}: ranges_only(ar, O.Arena.src_from(ar, i, 1), Nil{})
    # `if self.op is Ops.BACKEDGE: return self.src[1:2]  # the condition's other ranges remain live`
    case O.OpsBACKEDGE{}: ended_of.one(ar, i)
    # `if self.op in range_start: return self.src[range_start[self.op]:]`
    case O.OpsSTAGE{}: O.Arena.src_from(ar, i, O.range_start(op))
    case O.OpsREDUCE{}: O.Arena.src_from(ar, i, O.range_start(op))
    case O.OpsLINEAR{}: O.Arena.src_from(ar, i, O.range_start(op))
    # `if self.op is Ops.AFTER: return tuple(flatten([x.ended_ranges for x in self.src[1:]]))`
    case O.OpsAFTER{}: ended_of.flat(ss, 1n)
    # `if self.op is Ops.BARRIER: return tuple(flatten([x.ended_ranges for x in self.src]))`
    case O.OpsBARRIER{}: ended_of.flat(ss, 0n)
    # "UNSHARD ends the DEVICE range: its src is per-device index math, the device
    # axis is carried by the axis metadata"
    case O.OpsUNSHARD{}: O.Arena.src_from(ar, i, 1)
    case _: Nil{}

def derived.put(ds: Maybe<&2, DtShape>, +ar: O.Arena, +i: U32, +op: O.Op, +arg: O.Arg, +x: Srcs) -> Maybe<&2, Derived>:
  match ds:
    case Some{DtShape{dt, shape}}:
      Some{Derived{dt, shape, device_of(ar, i, op, arg, Srcs.ss(x)),
        addrspace_of(arg, op, Srcs.ss(x)), base_of(i, op, Srcs.ss(x)), ended_of(ar, i, op, Srcs.ss(x))}}
    case None{}: None{}

def derived.of(+ar: O.Arena, +i: U32, nd: O.Node, +x: Srcs) -> Maybe<&2, Derived>:
  match nd:
    case O.Node{+op, src, +arg, tag}:
      derived.put(dt_shape(ar, i, op, arg, Srcs.ss(x)), ar, i, op, arg, x)

# ===========================================================================
# THE ASSEMBLY. The one place that knows all six properties, and the one def the
# worklist calls.
# ===========================================================================

def derived(ar: O.Arena, i: U32, nd: O.Node, ss: List<&2, Derived>) -> Maybe<&2, Derived>:
  derived.of(ar, i, nd, srcs(ss))

# ===========================================================================
# THE FOLD: a Kahn worklist over the arena.
#
# THREE LISTS, and each is doing one job:
#   * `pend` is the pending count per node, indexed by node index: how many of a
#     node's srcs the fold has not answered yet. Kahn's in-degree.
#   * `work` is the worklist: the nodes whose count has reached zero.
#   * `out` is the resolved table, in resolution order: a node index and its pair.
#
# The bound is EXACT, not a budget to tune: every node is pushed once for having no
# srcs and once per edge into it, so `Arena.next(ar) + edges` pops always suffice and
# `Kahn.budget` computes it.
#
# A NODE MAY BE QUEUED TWICE, when it is a src of the same node twice (`ADD(x, x)`
# counts two edges and so decrements twice), and it is pushed again after it is
# already resolved. `Kahn.step`'s `Kahn.get` is the visited set, which is what makes
# the worklist a multiset safely. The pending count cannot underflow for the same
# reason: it starts at `nsrc` and is decremented once per edge.
# ===========================================================================

type Kahn is Data:
  Kahn{pend: List<&2, U32>, work: List<&2, U32>, out: Table}

# the resolved table's entry: a node index and its six properties
type Resolved is Data:
  Resolved{i: U32, d: Derived}

# THE TABLE AS A `Data` VALUE. The fold reads the table once per SRC of every node
# it answers, and Bend SPENDS a list when it reads it, so a bare `List` cannot be the
# store: two reads of the same table is already a type error. `Table.es` hands the
# list out.
type Table is Data:
  Table{es: List<&2, Resolved>}

def Table.es(tb: Table) -> List<&2, Resolved>:
  match tb:
    case Table{es}: es

def Table.put(tb: Table, r: Resolved) -> Table:
  match tb:
    case Table{es}: Table{List.append(&2, Resolved, es, [r])}

def Table.len(tb: Table) -> Nat:
  List.length(&2, Resolved, Table.es(tb))

def Res_i(r: Resolved) -> U32:
  match r:
    case Resolved{i, d}: i

def Res_d(r: Resolved) -> Derived:
  match r:
    case Resolved{i, d}: d

# `Kahn.pop`'s visited test puts at most one entry per index in the table, so "the
# last match" and "the only match" are the same entry and the walk needs no
# "already found" flag.
def Kahn.get.step(i: U32, +r: Resolved, acc: Maybe<&2, Derived>) -> Maybe<&2, Derived>:
  Kahn.get.hit(U32.is_eq(i, Res_i(r)), Res_d(r), acc)

def Kahn.new() -> Kahn:
  Kahn{Nil{}, Nil{}, Table{Nil{}}}

def Kahn.out_of(k: Kahn) -> Table:
  match k:
    case Kahn{pend, work, out}: out

def Kahn.pend(k: Kahn) -> List<&2, U32>:
  match k:
    case Kahn{pend, work, out}: pend

def Kahn.work(k: Kahn) -> List<&2, U32>:
  match k:
    case Kahn{pend, work, out}: work

def Kahn.degree(nd: O.Node) -> U32:
  U32.from_nat(List.length(&2, U32, O.Node.src(nd)))

def Kahn.seed.work(ns: List<&2, O.Node>, +k: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match ns:
    case Nil{}: acc
    case nd <> t: Kahn.seed.work(t, U32.add(k, 1), Kahn.seed.keep(Kahn.degree(nd), k, acc))

# THE SEED. `pend[i] = len(srcs(i))` for every node, and the worklist is every node
# with no srcs. Both are folds over the arena's own node list, so the seed is a
# function of the arena and not a number the caller supplies.
def Kahn.seed.pend(ns: List<&2, O.Node>, acc: List<&2, U32>) -> List<&2, U32>:
  match ns:
    case Nil{}: acc
    case nd <> t: Kahn.seed.pend(t, List.append(&2, U32, acc, [Kahn.degree(nd)]))

def Kahn.seed(+ar: O.Arena) -> Kahn:
  Kahn{Kahn.seed.pend(O.Arena.nodes(ar), Nil{}), Kahn.seed.work(O.Arena.nodes(ar), 0, Nil{}), Table{Nil{}}}

def Kahn.edges.f(e: U32, nd: O.Node) -> U32:
  U32.add(e, Kahn.degree(nd))

def Kahn.edges(ar: O.Arena) -> U32:
  List.foldl(&2, O.Node, U32, Kahn.edges.f, O.Arena.nodes(ar), 0)

# `Arena.next(ar) + edges`: one pop per queued entry, and there is one entry per
# zero-src node plus one per edge. EXACT, so the fuel can never cut a fold short.
def Kahn.budget(+ar: O.Arena) -> Nat:
  U32.to_nat(U32.add(O.Arena.next(ar), Kahn.edges(ar)))

# THE DECREMENT AT POSITION `k`, which rebuilds the list. The countdown reads the
# index from the front, so `case 0n` is the element itself and `case 1n+p` is an
# element to keep with `p` to go -- getting that the wrong way round is a fold that
# lowers the wrong element and says nothing, and it is silent in the dangerous
# direction. A count of 0 cannot go below it, per the header, so `U32.sub` never wraps
# here.
def Kahn.dec.go(ps: List<&2, U32>, k: Nat) -> List<&2, U32>:
  match ps k:
    case Nil{} _: Nil{}
    case c <> t 0n: U32.sub(c, 1) <> t
    case c <> t 1n+p: c <> Kahn.dec.go(t, p)

def Kahn.dec(pend: List<&2, U32>, k: U32) -> List<&2, U32>:
  Kahn.dec.go(pend, U32.to_nat(k))

def Kahn.zero(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{0}: True{}
    case _: False{}

# one count down
def Kahn.dec_k(+k: Kahn, s: U32) -> Kahn:
  Kahn{Kahn.dec(Kahn.pend(k), s), Kahn.work(k), Kahn.out_of(k)}

def Kahn.reached.of(zero: Bool, +k: Kahn, s: U32) -> Kahn:
  match zero:
    case True{}: Kahn{Kahn.pend(k), List.append(&2, U32, Kahn.work(k), [s]), Kahn.out_of(k)}
    case _: k

# a src whose count reached zero joins the worklist. A src index past the end of
# `pend` was never interned, so it never becomes ready and its consumer is never
# answered: the same one-directional rule as `Kahn.gather`.
def Kahn.reached(+k: Kahn, +s: U32) -> Kahn:
  Kahn.reached.of(Kahn.zero(List.get(&2, U32, Kahn.pend(k), U32.to_nat(s))), k, s)

# how many TIMES `u` is named by `srcs`, which is the edge count the walk below
# needs. NOT a membership test: `UOp.backedge` builds `src=(self, loop, cond)` and
# `g_cycle` passes `self` and `cond` the same node, so that node has TWO edges into
# it and a Bool loses the second.
def Kahn.src_count.add(same: Bool, n: U32) -> U32:
  match same:
    case True{}: U32.add(n, 1)
    case _: n

def Kahn.src_count.f(s: U32, +u: U32, n: U32) -> U32:
  Kahn.src_count.add(U32.is_eq(s, u), n)

def Kahn.src_count.go(srcs: List<&2, U32>, +u: U32, n: U32) -> U32:
  match srcs:
    case Nil{}: n
    case s <> t: Kahn.src_count.go(t, u, Kahn.src_count.f(s, u, n))

def Kahn.src_count(nd: O.Node, u: U32) -> U32:
  Kahn.src_count.go(O.Node.src(nd), u, 0)

# one count down, and the push when it reaches zero. BOTH LISTS CHANGE IN THE SAME
# TURN and Bend spends a list, so the turn is a whole `Kahn`: `Kahn.dec_k` lowers one
# count and hands the pair on, `Kahn.reached` pushes and hands the pair on.
def Kahn.consumers.dec(+v: U32, +k: Kahn) -> Kahn:
  Kahn.reached(Kahn.dec_k(k, v), v)

# EVERY NODE ANSWERED, which is what "the fold is complete" means.
def Kahn.settled(ar: O.Arena, tb: Table) -> Bool:
  Nat.is_eq(Table.len(tb), U32.to_nat(O.Arena.next(ar)))

def UOp.axis_id.of(arg: O.Arg, op: O.Op) -> Maybe<&2, List<&2, U32>>:
  match arg op:
    case O.ARange{ids, at} O.OpsRANGE{}: Some{ids}
    case _ _: None{}

# `UOp.axis_id` and `UOp.axis_type` -- ops.py:502 and ops.py:507. NOT a fold
# property, and the arena is why: `arg` is the pair `ARange{ids, at}`, so
# `self.arg[0:-1]` and `self.arg[-1]` are the two fields of a value the fold never
# has to compute. Both assert `self.op is Ops.RANGE`, which is the `None` arm.
def UOp.axis_id(+ar: O.Arena, +i: U32) -> Maybe<&2, List<&2, U32>>:
  UOp.axis_id.of(O.Arena.arg(ar, i), O.Arena.op(ar, i))

def UOp.axis_type.of(arg: O.Arg, op: O.Op) -> Maybe<&2, O.AxisType>:
  match arg op:
    case O.ARange{ids, at} O.OpsRANGE{}: Some{at}
    case _ _: None{}

def UOp.axis_type(+ar: O.Arena, +i: U32) -> Maybe<&2, O.AxisType>:
  UOp.axis_type.of(O.Arena.arg(ar, i), O.Arena.op(ar, i))

# ===========================================================================
# THE `_min_max` ARITHMETIC CORE -- the part of ops.py:1104 that is unsigned-64
# magnitude arithmetic plus a sign bit, and the HALF OF THE WALL that
# `mixin/dtype.bend` measured. See the full width argument at the foot of this file,
# and `.agents/slop/mm-gate.py` for the gate whose fixtures and rows are BOTH
# CPython output.
#
# WHY IT IS HERE AND NOT IN helpers.bend. `mixin/dtype.bend`'s header says the wall
# is that `i64_mul`, a shift, `i64_div` and `i64_mod` do not exist -- and that
# div/mod DO exist in `tinybendygrad/dtype.bend` but as `IO(..)` effect seams, which
# a fold cannot call. This section is the same set of operations written PURE, which
# is the only shape `_min_max` can use. It is spelled under the same notice that
# `promo_mask`/`least_upper` carry ("THE LATTICE IS HOISTED"): when helpers.bend grows
# them these defs go there and the callers do not change.
#
# THE WIDTH IS SIGN-PLUS-UNSIGNED-64 and it is MEASURED, not chosen. See
# `.agents/slop/oracles/mm-range.py`: a plain 8x8 matmul has 21 of 232 nodes whose
# bound leaves i64, and the widest bound in 21 real graphs is 96 bits.
# `dtypes.uint64.max` = 2**64-1 does not fit a SIGNED 64-bit word, so the magnitude
# is UNSIGNED and the sign is a separate `Bool`. Bend's only runtime numbers are
# `U32` and `Nat`, and `Nat` refuses past 2**48-1, so this pair is the widest thing
# Bend 2.0.34 can express and `None` -- which every caller turns into `PInf`/`NInf` --
# is the overflow.
#
# THE SIGNS ARE NOT OPTIONAL and five bugs in this section were all silent, each
# producing a plausible number that only a CPython diff found:
#   * `Bool.or(is_zero(lo), is_zero(hi))` reads as "the pair is zero" and is not.
#   * the unsigned subtract's underflow test is `a < b`, and NOT `result < a`.
#   * in a 64x64 product `s` is limb 1 and `u` is limb 2, so the overflow test is
#     `u != 0 or t3.hi != 0` and NOT `t3.hi + (u >> 32) != 0`.
#   * for `k >= 32` the shifted high word comes from `al` and only from `al`.
#   * restoring division subtracts when the remainder REACHED the divisor.
# ===========================================================================

def mm.u64.of(ok: Bool, +hi: U32, +lo: U32) -> Maybe<&2, H.I64>:
  match ok:
    case True{}: Some{H.i64_of_hi_lo(hi, lo)}
    case False{}: None{}

def mm.u64.lt(+eh: U32, el: U32, +fh: U32, fl: U32) -> Bool:
  Bool.or(U32.is_lt(eh, fh), Bool.and(U32.is_eq(eh, fh), U32.is_lt(el, fl)))

def mm.u64.le(+eh: U32, el: U32, +fh: U32, fl: U32) -> Bool:
  Bool.or(U32.is_lt(eh, fh), Bool.and(U32.is_eq(eh, fh), U32.is_le(el, fl)))

def mm.u64.eq(+eh: U32, el: U32, fh: U32, fl: U32) -> Bool:
  Bool.and(U32.is_eq(eh, fh), U32.is_eq(el, fl))

# "this pair is zero", which is what every overflow test asks. IT IS `and`: `or`
# answers true for (0, 5) as well as for (0, 0), and that is how 2**32 came out as a
# product of zero.
def mm.u64.is_zero(+hi: U32, lo: U32) -> Bool:
  Bool.and(U32.is_zero(lo), U32.is_zero(hi))

def mm.u64.is_one(+hi: U32, lo: U32) -> Bool:
  Bool.and(U32.is_zero(hi), U32.is_eq(lo, 1))

# the carry out of `U32.add`, which is its own overflow test
def mm.u32c(+a: U32, b: U32) -> U32:
  Bool.pick(U32, U32.is_lt(U32.add(a, b), a), 1, 0)

def mm.u64.add(+ah: U32, +al: U32, bh: U32, +bl: U32) -> Maybe<&2, H.I64>:
  +lo = U32.add(al, bl)
  +hi = U32.add(U32.add(ah, bh), mm.u32c(al, bl))
  mm.u64.of(Bool.not(mm.u64.lt(hi, lo, ah, al)), hi, lo)

# WRAPPING, because restoring division needs `r - d` mod 2**64 and the borrow there
# is answered by the shift's own carried bit rather than by the subtraction.
def mm.u64w.sub(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> H.I64:
  H.i64_of_hi_lo(U32.sub(ah, U32.add(bh, mm.u32c(bl, U32.sub(al, bl)))), U32.sub(al, bl))

# The underflow test is `a < b`, NOT `result < a`. The second is what an ADD
# overflows on and it is silently the wrong predicate for a subtraction: `0 - 2**32`
# wraps to a value GREATER than `a` and so reads as no underflow at all.
def mm.u64.sub(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<&2, H.I64>:
  +lo = U32.sub(al, bl)
  +hi = U32.sub(ah, U32.add(bh, mm.u32c(bl, U32.sub(al, bl))))
  mm.u64.of(Bool.not(mm.u64.lt(ah, al, bh, bl)), hi, lo)

# ---- MUL ---------------------------------------------------------------------
#
# A 64x64 product is 128 bits, so the answer is the HIGH word and every bit from
# 2**64 up is the overflow.
#
# THE LIMBS ARE 16 WIDE, and that is the whole trick. `U32.mul` wraps, so a 32x32
# product cannot be overflow-tested at all -- `U32.mul(a,b)/a == b` holds for a
# wrapped product of a particular size as readily as for an exact one. A 16x16
# product is BELOW 2**32, so `U32.mul` is exact on it, and the four partials
# accumulate with every column sum under 2**20 -- no wrap test anywhere in this
# section.
def mm.u32x16(+x: U32) -> U32: U32.shrn(x, 16n)

def mm.u32lo16(+x: U32) -> U32: U32.and(x, 65535)

# a*b = p0 + (p1+p2)*2**16 + p3*2**32 over 16-bit halves, which is the statement
# `mm.u32m.wide`'s three `n` lines are.
def mm.u32m.wide(+p0: U32, +p1: U32, +p2: U32, +p3: U32) -> H.I64:
  +n1 = U32.add(U32.add(mm.u32lo16(p1), mm.u32lo16(p2)), mm.u32x16(p0))
  +n2 = U32.add(U32.add(U32.add(mm.u32x16(p1), mm.u32x16(p2)), mm.u32lo16(p3)), mm.u32x16(n1))
  +n3 = U32.add(mm.u32x16(p3), mm.u32x16(n2))
  H.i64_of_hi_lo(U32.or(mm.u32lo16(n2), U32.shln(mm.u32lo16(n3), 16n)),
    U32.or(mm.u32lo16(p0), U32.shln(mm.u32lo16(n1), 16n)))

def mm.u32m(+a: U32, +b: U32) -> H.I64:
  mm.u32m.wide(U32.mul(mm.u32lo16(a), mm.u32lo16(b)), U32.mul(mm.u32lo16(a), mm.u32x16(b)),
    U32.mul(mm.u32x16(a), mm.u32lo16(b)), U32.mul(mm.u32x16(a), mm.u32x16(b)))

# The 64x64 combination is THREE columns wide, so each is under 2**34 and cannot
# wrap either.
def mm.u64.join(+t0: H.I64, +t1: H.I64, +t2: H.I64, +t3: H.I64) -> Maybe<&2, H.I64>:
  +s = U32.add(U32.add(H.hi32(t0), H.lo32(t1)), H.lo32(t2))
  +u = U32.add(U32.add(U32.add(H.hi32(t1), H.hi32(t2)), H.lo32(t3)), U32.shrn(s, 32n))
  # `s` IS LIMB 1 and `u` IS LIMB 2 -- the WORDS, not partial words -- so every bit
  # of `u` is already above 2**64 and the overflow test is `u != 0 or t3.hi != 0`.
  # It is NOT `t3.hi + (u >> 32) != 0`, which wraps a U32 and reads as zero for a
  # product that overflowed. Nor can `u << 32` build the high word: a U32 shift by
  # 32 SATURATES TO 0 (bend2-constraints, the `1 << 34` trap).
  mm.u64.of(Bool.and(mm.u64.is_zero(H.hi32(t3), 0), mm.u64.is_zero(u, 0)),
    U32.or(U32.and(s, 4294967295), U32.shln(U32.and(u, 4294967295), 32n)),
    H.lo32(t0))

def mm.u64.mul(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<&2, H.I64>:
  mm.u64.join(mm.u32m(al, bl), mm.u32m(al, bh), mm.u32m(ah, bl), mm.u32m(ah, bh))

# ---- THE SHIFTS --------------------------------------------------------------
#
# `U32.shl` is a ONE-BIT shift and `U32.shln(x, n)` is the n-bit one, so every shift
# AMOUNT below is a `Nat`. That is the whole of the rule bend2-constraints records:
# a bit-packer whose field positions are runtime values is UNWRITABLE, so the
# amounts here are `Nat` differences and not `U32`s. `Nat.sub` underflows to 0, which
# is what makes the eagerly-evaluated other arm harmless.
# ---- THE BIT COUNT -----------------------------------------------------------
#
# `int(x).bit_length()` is the AND arm's mask width (ops.py:1110) and it is a COUNT,
# so it is a `Nat` and the doubling below is the only way to get one.
# THE ZERO TEST IS A MATCH ON THE TWO WORDS THEMSELVES, not on a computed Bool: Bend
# refuses `match` on a call, and `mm.u64.is_zero(...)` is a call. The words are
# parameters, so `case 0 0:` is a legal scrutinee -- and this is the only place in
# the section where the PATTERN carries the answer instead of a flag.
# OVERFLOW IS DECIDED FROM THE SHIFT AMOUNT AND THE WORDS, NOT FROM A BIT COUNT.
# `bit_length` is the obvious test and it is NOT AVAILABLE: it needs a walk whose
# zero test cannot be a `match` scrutinee (Bend refuses a call), whose growing
# counter cannot lead a self-call, and whose test and step cannot be two defs
# because mutual recursion is refused. So `shl` overflows iff `a >= 2**(64-k)`, which
# is one word and one shift:
#   k <= 32   the bits at position >= 64-k all live in the HIGH word, at 32-k
#   k >  32   they straddle: `ah != 0` already decides it, else `al` at 64-k
def mm.u64.shl.lo(+ah: U32, +al: U32, +k: Nat) -> H.I64:
  H.i64_of_hi_lo(U32.or(U32.shln(ah, k), U32.shrn(al, Nat.sub(32n, k))), U32.shln(al, k))

# FOR `k >= 32` THE HIGH WORD COMES FROM `al` AND ONLY FROM `al`: `a * 2**k` has
# high word `al * 2**(k-32)` plus `ah * 2**k` reduced mod 2**32, and the second term
# is 0 for every k past 31. Reading `ah` here instead drops the low word entirely and
# answers 0 for `1 << 63`, which is `2147483648:0`.
def mm.u64.shl.hi(+ah: U32, +al: U32, +k: Nat) -> H.I64:
  H.i64_of_hi_lo(U32.shln(al, Nat.sub(k, 32n)), 0)

def mm.u64.shl.lo_half(+k: Nat) -> Bool:
  U32.is_lt(U32.from_nat(k), 32)

def mm.u64.shl.put(lo: Bool, +ah: U32, +al: U32, +k: Nat) -> H.I64:
  Bool.pick(H.I64, lo, mm.u64.shl.lo(ah, al, k), mm.u64.shl.hi(ah, al, k))

def mm.u64.shl.under32(+k: Nat) -> Bool:
  U32.is_le(U32.from_nat(k), 32)

def mm.u64.shl.lost32(+k: Nat) -> Nat: Nat.sub(32n, k)

def mm.u64.shl.lost64(+k: Nat) -> Nat: Nat.sub(64n, k)

def mm.u64.shl.lost(+k: Nat) -> Nat:
  Bool.pick(Nat, mm.u64.shl.under32(k), mm.u64.shl.lost32(k), mm.u64.shl.lost64(k))

def mm.u64.shl.ok32(+ah: U32, al: U32, +k: Nat) -> Bool:
  Bool.pick(Bool, U32.is_zero(U32.from_nat(k)), True{},
    U32.is_zero(U32.shrn(ah, mm.u64.shl.lost(k))))

# `and`, NOT `or`: overflow is `ah != 0 OR al's tail is nonzero`, so the FIT test is
# both-zero. `or` fits every divisor-shaped word and answers a value where CPython
# says OVER -- 1 << 64 is the row that notices.
def mm.u64.shl.okhi(+ah: U32, al: U32, +k: Nat) -> Bool:
  Bool.and(U32.is_zero(ah), U32.is_zero(U32.shrn(al, mm.u64.shl.lost(k))))

def mm.u64.shl.ok(+ah: U32, +al: U32, +k: Nat) -> Bool:
  Bool.pick(Bool, mm.u64.shl.under32(k), mm.u64.shl.ok32(ah, al, k), mm.u64.shl.okhi(ah, al, k))

def mm.u64.shl.of(ok: Bool, +ah: U32, +al: U32, +k: Nat) -> Maybe<&2, H.I64>:
  match ok:
    case True{}: Some{mm.u64.shl.put(mm.u64.shl.lo_half(k), ah, al, k)}
    case False{}: None{}

def mm.u64.shl(+ah: U32, +al: U32, +k: Nat) -> Maybe<&2, H.I64>:
  mm.u64.shl.of(mm.u64.shl.ok(ah, al, k), ah, al, k)

def mm.u64.shr.go(+k: Nat, +ah: U32, +al: U32) -> H.I64:
  match k:
    case 0n: H.i64_of_hi_lo(ah, al)
    case 1n+p: mm.u64.shr.go(p, U32.shrn(ah, 1n), U32.or(U32.shrn(al, 1n), U32.shln(U32.and(ah, 1), 31n)))

def mm.u64.shr(+ah: U32, +al: U32, +k: Nat) -> H.I64:
  mm.u64.shr.go(k, ah, al)


# ---- BITWISE, on the two halves ------------------------------------------------
#
# `_min_max` reaches bitwise arithmetic on NON-NEGATIVE bounds only -- the AND arm
# masks with `(1 << bit_length) - 1` and the XOR arm is `~x`, which is `-x - 1` and
# not a bit pattern. So two's-complement sign extension is never needed and is not
# here; a general infinite-width `&` is the one thing this section does NOT have.

def mm.u64.and(ah: U32, al: U32, bh: U32, bl: U32) -> H.I64:
  H.i64_of_hi_lo(U32.and(ah, bh), U32.and(al, bl))

def mm.u64.or(ah: U32, al: U32, bh: U32, bl: U32) -> H.I64:
  H.i64_of_hi_lo(U32.or(ah, bh), U32.or(al, bl))

def mm.u64.xor(ah: U32, al: U32, bh: U32, bl: U32) -> H.I64:
  H.i64_of_hi_lo(U32.xor(ah, bh), U32.xor(al, bl))

def mm.u64.not(ah: U32, al: U32) -> H.I64:
  H.i64_of_hi_lo(U32.not(ah), U32.not(al))
# ---- RESTORING DIVISION --------------------------------------------------------
#
# `helpers.bend` already has `cdiv_i32_go` and `floordiv_i32`, and both are this
# algorithm on a smaller pair: the QUOTIENT is truncated, then stepped DOWN one more
# only when the division was inexact and the two signs differ. So the sign work is
# REUSED and only the 64-step division is new.
#
# `qb` IS THE QUOTIENT BIT FOR THIS STEP, carried because the compare happens before
# the bit is known and restoring division sets a quotient bit exactly when it
# subtracts. Setting it unconditionally answers 1 for every step, which is a
# quotient of all ones and a remainder of the dividend.
type mm.MMSt is Data:
  mm.MMSt{qh: U32, ql: U32, rh: U32, rl: U32, up: Bool, qb: Bool}

def mm.MMSt.qh(x: mm.MMSt) -> U32:
  match x:
    case mm.MMSt{qh, ql, rh, rl, up, qb}: qh

def mm.MMSt.ql(x: mm.MMSt) -> U32:
  match x:
    case mm.MMSt{qh, ql, rh, rl, up, qb}: ql

def mm.MMSt.rh(x: mm.MMSt) -> U32:
  match x:
    case mm.MMSt{qh, ql, rh, rl, up, qb}: rh

def mm.MMSt.rl(x: mm.MMSt) -> U32:
  match x:
    case mm.MMSt{qh, ql, rh, rl, up, qb}: rl

def mm.MMSt.up(x: mm.MMSt) -> Bool:
  match x:
    case mm.MMSt{qh, ql, rh, rl, up, qb}: up

def mm.MMSt.qb(x: mm.MMSt) -> Bool:
  match x:
    case mm.MMSt{qh, ql, rh, rl, up, qb}: qb

# `k < 32` puts bit `k` in the LOW word, so this flag names the LOW half. Both picks
# below read it as "pick the low arm", and getting those two arms the wrong way round
# reads every dividend bit out of the wrong half and the quotient comes out zero.
def mm.dm.low_half(k: Nat) -> Bool:
  U32.is_lt(U32.from_nat(k), 32)

# STEP `k` READS DIVIDEND BIT `k` AND WRITES QUOTIENT BIT `k` -- the same index on
# both sides, which is the whole of restoring division and the reason the walk counts
# DOWN from 63: the first bit processed is the most significant of each.
#
# `U32.shrn(w, j)` is `w >> j` and NOT `(w >> j) & 1`, and the caller ORs the answer
# straight into the low word of the remainder, so both arms mask.
def mm.dm.bit.hi(+bh: U32, +bl: U32, +k: Nat) -> U32:
  U32.and(U32.shrn(bh, Nat.sub(k, 32n)), 1)

def mm.dm.bit.lo(+bh: U32, +bl: U32, +k: Nat) -> U32:
  U32.and(U32.shrn(bl, k), 1)

def mm.dm.bit(+bh: U32, +bl: U32, +k: Nat, low: Bool) -> U32:
  Bool.pick(U32, low, mm.dm.bit.lo(bh, bl, k), mm.dm.bit.hi(bh, bl, k))

def mm.dm.get_bit(+bh: U32, +bl: U32, +k: Nat) -> U32:
  mm.dm.bit(bh, bl, k, mm.dm.low_half(k))

def mm.dm.put(qh: U32, ql: U32, +r: H.I64) -> mm.MMSt:
  match r:
    case H.I64{nh, nl}: mm.MMSt{qh, ql, nh, nl, False{}, True{} }

# `r = 2r + bit`, WITH the 65th bit kept rather than lost: a U32 shift of 1 by 1
# drops the top of the high word, and that bit is the one that decides the compare.
def mm.dm.shift(+s: mm.MMSt, bit: U32) -> mm.MMSt:
  mm.MMSt{mm.MMSt.qh(s), mm.MMSt.ql(s), U32.or(U32.shln(mm.MMSt.rh(s), 1n), U32.shrn(mm.MMSt.rl(s), 31n)),
    U32.or(U32.shln(mm.MMSt.rl(s), 1n), bit), U32.is_eq(U32.shrn(mm.MMSt.rh(s), 31n), 1), False{}}

def mm.dm.drop(+s: mm.MMSt, +dh: U32, +dl: U32) -> mm.MMSt:
  mm.dm.put(mm.MMSt.qh(s), mm.MMSt.ql(s), mm.u64w.sub(mm.MMSt.rh(s), mm.MMSt.rl(s), dh, dl))

# `(up, r) >= d`: ONE subtract is enough, because the invariant is `r < d` before
# the step, so `up` alone already decides the comparison. The compare is `>= d` and
# NOT `<= d`: subtracting on every step where the remainder is merely BELOW the
# divisor answers a quotient of all ones for any dividend smaller than the divisor.
def mm.dm.same(+s: mm.MMSt) -> mm.MMSt:
  mm.MMSt{mm.MMSt.qh(s), mm.MMSt.ql(s), mm.MMSt.rh(s), mm.MMSt.rl(s), mm.MMSt.up(s), False{}}

def mm.dm.cmp(ge: Bool, s: mm.MMSt, +dh: U32, +dl: U32) -> mm.MMSt:
  match ge:
    case True{}: mm.dm.drop(s, dh, dl)
    case False{}: mm.dm.same(s)

def mm.dm.fit(+s: mm.MMSt, +dh: U32, +dl: U32) -> mm.MMSt:
  mm.dm.cmp(Bool.or(mm.MMSt.up(s), Bool.not(mm.u64.lt(mm.MMSt.rh(s), mm.MMSt.rl(s), dh, dl))), s, dh, dl)

# THE QUOTIENT BIT IS AT POSITION `k`, THE SAME INDEX THE DIVIDEND BIT CAME FROM, so
# each arm shifts by exactly what `mm.dm.bit` shifted by.
def mm.dm.qbit.hi(+k: Nat, +s: mm.MMSt) -> mm.MMSt:
  mm.MMSt{U32.or(mm.MMSt.qh(s), U32.shln(1, Nat.sub(k, 32n))), mm.MMSt.ql(s), mm.MMSt.rh(s), mm.MMSt.rl(s), False{}, False{}}

def mm.dm.qbit.lo(+k: Nat, +s: mm.MMSt) -> mm.MMSt:
  mm.MMSt{mm.MMSt.qh(s), U32.or(mm.MMSt.ql(s), U32.shln(1, k)), mm.MMSt.rh(s), mm.MMSt.rl(s), False{}, False{}}

def mm.dm.qbit.at(low: Bool, +k: Nat, set: Bool, +s: mm.MMSt) -> mm.MMSt:
  Bool.pick(mm.MMSt, Bool.not(set), s, Bool.pick(mm.MMSt, low, mm.dm.qbit.lo(k, s), mm.dm.qbit.hi(k, s)))

def mm.dm.step(+k: Nat, +s: mm.MMSt, +bh: U32, +bl: U32, +dh: U32, +dl: U32) -> mm.MMSt:
  +f = mm.dm.fit(mm.dm.shift(s, mm.dm.get_bit(bh, bl, k)), dh, dl)
  mm.dm.qbit.at(mm.dm.low_half(k), k, mm.MMSt.qb(f), f)

# THE COUNTER IS A PARAMETER WITH `+`, not a field of the state: `case 1n+p:` SPENDS
# `p` on the match, so `p` cannot be read twice -- and the fix is `+` on the
# SCRUTINEE, never on the binder (bend2-constraints, the `1n+p` rule 5).
def mm.dm.loop(+k: Nat, +bh: U32, +bl: U32, +dh: U32, +dl: U32, +s: mm.MMSt) -> mm.MMSt:
  match k:
    case 0n: s
    case 1n+p: mm.dm.loop(p, bh, bl, dh, dl, mm.dm.step(p, s, bh, bl, dh, dl))

def mm.dm_run(nh: U32, nl: U32, dh: U32, dl: U32) -> mm.MMSt:
  mm.dm.loop(64n, nh, nl, dh, dl, mm.MMSt{0, 0, 0, 0, False{}, False{}})

def mm.dm_show(+d: mm.MMSt) -> String:
  String.concat(["q=", H.i64_text(H.i64_of_hi_lo(mm.MMSt.qh(d), mm.MMSt.ql(d))), " r=", H.i64_text(H.i64_of_hi_lo(mm.MMSt.rh(d), mm.MMSt.rl(d)))])

def mm_show(m: Maybe<&2, H.I64>) -> String:
  match m:
    case Some{x}: H.i64_text(x)
    case None{}: "OVER"
# ===========================================================================
# `int(x).bit_length()` -- ops.py:1110's mask width. SOLVED, NOT ROUTED AROUND.
#
# THE PREVIOUS UNIT RECORDED THIS AS A STRUCTURAL WALL, and the reasoning was sound:
#   * the zero test cannot be a `match` scrutinee, because Bend refuses a call there;
#   * the growing counter cannot lead a self-call, because each argument must pass
#     unchanged until one shrinks, and a `U32` that *halves* does not count as
#     shrinking;
#   * the test and the step cannot be two defs, because mutual recursion is refused;
#   * and a `List` tail IS a shrink, which is why `toposort` and `dts_of` are walks,
#     though a three-scrutinee `match` over `(List, U32, U32)` refuses repeated `_ _`.
# Every one of those is a fact about a WALK. This is not a walk.
#
# IT IS A BINARY-SEARCH LADDER: FIVE `Bool.pick`s AND A TAIL TEST, all straight-line,
# no recursion, no fuel, no accumulator that leads a call. `bit_length(x)` for a 32-bit
# `x` is the sum of `k` over the thresholds `2**16, 2**8, 2**4, 2**2, 2**1` that `x`
# meets, plus one if the residue is nonzero -- the standard MSD-first narrowing. The
# residue after stage `k` is `x >> k`, so `U32.is_ge(x, 2**k)` IS the test "this bit
# position is set", and the shift amounts are LITERALS, which is what bend2-constraints
# demands ("a bit-packer whose field positions are runtime values is unwritable").
#
# SO WHAT MADE IT POSSIBLE, in one sentence: THE COUNT IS NOT A COUNT. A walk counts
# UP one bit at a time and therefore needs a zero test; this NARROWS, so the "am I
# done" question is answered by the FIVE LITERAL THRESHOLDS and never by an equality
# test on the value at all. The wall was the arithmetic (additive counting), not the
# language. `Nat` is not needed for the shift amounts, and the answer stays a `U32`,
# which is what `mm.u64.shl` wants anyway.
#
# THE COUNT IS THE SAME ANSWER AND NOT A DIFFERENT ONE. `1 << k` needs `k` as a `Nat`
# and the mask is `2**k - 1`, so a bit_length that is one too large gives a mask one
# bit too wide and therefore a DIFFERENT INTEGER, not a different shape -- which is
# why `mm-bl-gate.py` gates the masking rows (`mk_*`) alongside the counts and not
# only the latter.
# ===========================================================================

# `x >= 2**16` picks `x >> 16` and adds 16; the two halves of each stage are separate
# defs only so the ladder reads as a table. `Bool.pick` CHOOSES an arm and both are
# evaluated, which is harmless here: every arm is a total shift or a literal.
def mm.bl32.p16(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 65536), U32.shrn(x, 16n), x)
def mm.bl32.b16(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 65536), 16, 0)
def mm.bl32.p8(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 256), U32.shrn(x, 8n), x)
def mm.bl32.b8(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 256), 8, 0)
def mm.bl32.p4(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 16), U32.shrn(x, 4n), x)
def mm.bl32.b4(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 16), 4, 0)
def mm.bl32.p2(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 4), U32.shrn(x, 2n), x)
def mm.bl32.b2(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 4), 2, 0)
def mm.bl32.p1(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 2), U32.shrn(x, 1n), x)
def mm.bl32.b1(+x: U32) -> U32: Bool.pick(U32, U32.is_ge(x, 2), 1, 0)

# The tail is `e != 0`, i.e. ONE more bit. It is `Bool.pick` and NOT a `match`, which
# is the whole reason this def exists: `U32.is_zero(e)` is a CALL, and a call cannot be
# a `match` scrutinee. `pick` takes a computed `Bool`, so the zero test is legal here and
# was the thing the previous unit's wall turned on.
def mm.bl32.tail(+e: U32) -> U32: Bool.pick(U32, U32.is_zero(e), 0, 1)

# `bit_length(0) == 0` AND `bit_length(1) == 1` fall out of the tail alone: for 0 every
# stage fails and the residue stays 0, so the tail adds nothing; for 1 the tail adds the
# one bit. That pair is `bl_0` and `bl_1` in the gate and it is the row a ladder ending
# on "the residue is nonzero" WITHOUT the zero case gets wrong.
def mm.bl32(+x: U32) -> U32:
  +a = mm.bl32.p16(x)
  +b = mm.bl32.p8(a)
  +c = mm.bl32.p4(b)
  +d = mm.bl32.p2(c)
  +e = mm.bl32.p1(d)
  +s0 = U32.add(mm.bl32.b16(x), mm.bl32.b8(a))
  +s1 = U32.add(s0, mm.bl32.b4(b))
  +s2 = U32.add(s1, mm.bl32.b2(c))
  +s3 = U32.add(s2, mm.bl32.b1(d))
  U32.add(s3, mm.bl32.tail(e))

# THE 64-BIT PICK IS `hi == 0`, NOT `lo != 0`. These two disagree only when `hi == 0` and
# `lo == 0` -- the value 0 -- where `hi == 0` answers `bit_length(0) == 0` and
# `lo != 0` answers 32 + `bit_length(0) == 32`. `bl_max_0` in the gate is that row.
def mm.bl64(+hi: U32, +lo: U32) -> U32:
  Bool.pick(U32, U32.is_zero(hi), mm.bl32(lo), U32.add(32, mm.bl32(hi)))

# The mask `(1 << k) - 1` for a `U32` count `k`, as the AND arm needs it. This is the
# only caller, and it is why the count is a `U32` and not a `Nat`: the mask is a SHIFT of
# all-ones, not a construction from `2**i - 1` blocks.
#
# `2**k - 1` IS ALL ONES SHIFTED DOWN BY (width - k), and that is total over the whole
# range INCLUDING both ends: `k == 0` shifts all ones out of the word and `k == width`
# shifts by nothing. The decomposition I wrote FIRST -- OR the blocks `2**(2**i) - 1` for
# the set bits of `k` -- is WRONG and the CPython diff caught it on the first masked row:
# it gives 3 for `k = 3` where the answer is 7, because those blocks are the ones for
# `2**2**i` and not for `2**i`. `bl_mask_3` in the mutation table is that row.
#
# `Nat.sub` UNDERFLOWS TO 0, which is what makes the eagerly-evaluated other arm harmless
# -- and here it is not even needed: the two words use different word widths, not
# different picks, so each is one expression over its own width.
def mm.mask.lo(+k: U32) -> U32:
  U32.shrn(4294967295, Nat.sub(32n, U32.to_nat(k)))

def mm.mask.hi(+k: U32) -> U32:
  U32.shrn(4294967295, Nat.sub(64n, U32.to_nat(k)))

def mm.mask64(+k: U32) -> H.I64:
  H.i64_of_hi_lo(mm.mask.hi(k), mm.mask.lo(k))

# `mm.u64.and` takes two pairs and returns one, so the AND arm's
# `int(s1_vmax) & ((1 << int(s0_vmax).bit_length()) - 1)` is one call with the mask
# built from the OTHER src's count. This is the row `mk_*` gates.
#
# THE `Maybe` IS WRAPPING AND NOT REAL: `&` of two in-window pairs is in-window, so this
# arm of the AND can never overflow and `mm_show` is reused rather than a second printer
# written. It answers `None` never, and that is a fact about `&` rather than a hope.
def mm_mask64(+s0h: U32, +s0l: U32, s1h: U32, s1l: U32) -> Maybe<&2, H.I64>:
  +mk = mm.mask64(mm.bl64(s0h, s0l))
  Some{mm.u64.and(s1h, s1l, H.hi32(mk), H.lo32(mk))}
# ===========================================================================
# `Bound` -- a bound of `_min_max`, and the dtype limits that end every arm.
#
# FOUR ARMS, AND TWO OF THEM ARE THE OVER-APPROXIMATION. `Int{neg, mag}` is the width
# argument's pair: a SIGN BIT plus an UNSIGNED 64-bit magnitude, covering
# [-2**63, 2**64-1]. `Flt` is the `float` bound Python's `PyConst` allows, and it is
# `F32` because Bend has no `F64` -- which is exact here because the only finite float
# bounds tinygrad has are the fp8 maxima, and every one of them is a small integer
# (-448, -240, -57344) that `F32` holds exactly. `NInf`/`PInf` are the two infinities
# AND the OVER answer: where an intermediate leaves the window, the bound saturates, and
# a saturated bound still answers every question a consumer asks of it (`resolve`'s
# `vmin == vmax`, `shard_shape`'s `int(x)`, `variable`'s `vmin_vmax is not None`).
#
# **`weakint` IS THE ONE DTYPE WHOSE LIMITS LEAVE THE WINDOW, AND IT IS MEASURED.**
# `dtypes.weakint.bitsize == 800`, so `min == -2**799` and `max == 2**799 - 1`, and
# neither is a 64-bit magnitude. So the header's claim that the pair covers "every dtype
# limit tinygrad has" is TRUE for the nine integer dtypes and FALSE for `weakint`, whose
# two limits are `NInf`/`PInf` here. That is not a defect in the representation: CPython
# ANSWERS those numbers and they are what `resolve` sees, but no consumer distinguishes
# them from an unbounded value -- both say "no information" -- so saturating is sound.
# The alternative is an arbitrary-precision integer, which Bend 2.0.34 cannot express
# (`Nat` refuses past 2**48-1) and which no consumer needs.
# ===========================================================================

type Bnd is Data:
  Bnd{inf: U32}
  BndInt{neg: Bool, mag: H.I64}
  BndFlt{v: F32}

# `NInf` and `PInf` as ONE `inf` tag rather than two variants, because the only
# operations on a bound that read the tag are the equality and the "is it finite"
# tests, and neither wants a two-arm match. `0` is `-inf`, `1` is `+inf`.
def bnd_ninf() -> Bnd: Bnd{0}

def bnd_pinf() -> Bnd: Bnd{1}

def bnd_i(neg: Bool, mag: H.I64) -> Bnd: BndInt{neg, mag}

# THE ZERO IS SIGNED POSITIVE, and the constant rather than a computed 0: `+0` and `-0`
# are the same Python int but they are not the same `Bound`, and an AND arm that answers
# `0` for a zero-valued mask must say WHICH zero it is.
def bnd_zero() -> Bnd: BndInt{False{}, H.i64_of_hi_lo(0, 0)}

def bnd_f(v: F32) -> Bnd: BndFlt{v}

# ---- THE DTYPE LIMITS, hoisted out of dtype.bend under the same notice as
# `promo_mask` above. `S.Dt.min`/`S.Dt.max` answer `None` for every width past 32 --
# `int64.min = -2**63` and `uint64.max = 2**64-1` have no U32 image -- and `None` for
# every float and for `bool`/`void`. These twenty rows are the ones the last arm of
# `_min_max` hands back, and they are spelled as ONE match over `S.Dt`'s own fields so
# that a width and a class cannot be read off different arms.
#
# THE EIGHT INTEGER LIMITS ARE COMPUTED AND NOT WRITTEN DOWN, because `2**bits - 1` is
# `mm.mask64(bits)` -- the SAME ladder the AND arm uses, one call, and it is already
# gated. `int64`'s and `uint64`'s two-word answers are therefore consequences of the mask
# rather than a second pair of hand-typed 32-bit hex halves, which is what a written-down
# table would have been. `bl_dt_int64` and `bl_dt_uint64` are the rows that notice.
# ---- THE READER, for the gate only. `show` is not part of the fold: a bound is compared,
# never printed, and every consumer reads the two halves. It exists because the gate has
# to see a sign and a pair to notice a transposition.
def bnd_show(b: Bnd) -> String:
  match b:
    case Bnd{i}: Bool.pick(String, U32.is_zero(i), "NInf", "PInf")
    case BndInt{neg, mag}: String.concat([Bool.pick(String, neg, "-", "+"), H.i64_text(mag)])
    case BndFlt{v}: String.concat(["F", F32.show(v)])

# THE SATURATING PAIR. Every float dtype's limits are `-inf`/`inf` except the three fp8s,
# and every WIDTH PAST 64 integer's are here too, so `bnd_int` reuses it rather than
# naming a second one.
def bnd_flt(top: Bool) -> Bnd: Bool.pick(Bnd, top, bnd_pinf(), bnd_ninf())

# ---- THE EIGHT INTEGER LIMITS, COMPUTED. `2**bits - 1` is `mm.mask64(bits)` -- the same
# ladder the AND arm uses, one call, already gated -- and a signed width's minimum
# magnitude is `2**(bits-1)`, which is `mm.u64.shl(0, 1, bits-1)`. So `int64`'s and
# `uint64`'s two-word answers are CONSEQUENCES of the mask rather than a second pair of
# hand-typed 32-bit hex halves, which is what a written-down table would have been and
# where a transcription would have lived. `bl_dt_int64` and `bl_dt_uint64` are the rows
# that notice.
def bnd.umax(+bits: U32) -> Bnd: BndInt{False{}, mm.mask64(bits)}

def bnd.pw2(+bits: U32) -> Maybe<&2, H.I64>: mm.u64.shl(0, 1, U32.to_nat(U32.sub(bits, 1)))

# THE `Maybe` HAS TO BE A PARAMETER, not a computed value: a `match` cannot scrutinize a
# call. `bnd.pw2.got` is not a helper, it is the only legal shape -- and it is the same
# reason `mm.u64.of` takes its `ok` flag rather than testing one inline.
def bnd.pw2.got(m: Maybe<&2, H.I64>) -> Bnd:
  match m:
    case Some{mag}: BndInt{True{}, mag}
    case None{}: bnd_ninf()

def bnd.smag(+bits: U32) -> Bnd: bnd.pw2.got(bnd.pw2(bits))

def bnd.smax(+bits: U32) -> Bnd: BndInt{False{}, mm.mask64(U32.sub(bits, 1))}

# THE WIDTH GUARD IS ON BOTH SIDES AND NOT JUST THE MINIMUM, and that is a real trap the
# `weakint` row caught. `mm.mask64` does NOT saturate: `U32.shrn(0xFFFFFFFF, Nat.sub(32n,
# 799n))` is `Nat.sub` UNDERFLOWING TO 0, so it answers ALL ONES -- `2**64 - 1` where
# `weakint.max` is `2**799 - 1`. A guard on the signed minimum alone therefore answers
# `NInf, +2**64-1` for `weakint`, which is neither CPython's answer nor a sound
# over-approximation: it claims the maximum is small when it is not, and a consumer asking
# `vmax <= 2**63` would be told yes. The guard is the WIDTH, tested once, on both arms.
def bnd_int(+top: Bool, +sgn: Bool, +bits: U32) -> Bnd:
  Bool.pick(Bnd, U32.is_gt(bits, 64), bnd_flt(top),
    Bool.pick(Bnd, top, Bool.pick(Bnd, sgn, bnd.smax(bits), bnd.umax(bits)),
      Bool.pick(Bnd, sgn, bnd.smag(bits), bnd_zero())))

# THE THREE FP8 MAXIMA, and they are the ONLY finite float bounds in tinygrad: the other
# six float dtypes answer `inf` for max and `-self.max` for min. These three are
# `fp8_to_float(_fp8_cfg[self][5], self)`, and every one is an exact `F32` (448 = 1.75 *
# 2**8, 240 = 1.875 * 2**7, 57344 = 1.75 * 2**15, all with short mantissas). The minimum
# is `-self.max` and NOT `0`: `dtype.py` says `return -self.max`, and answering 0 for the
# minimum of a signed float dtype would be the classic wrong-over-approximation -- a
# bound that is too HIGH is not sound, because it excludes the values in between.
def bnd_fmax(+top: Bool, +m: Nat) -> Bnd:
  Bool.pick(Bnd, top, bnd_f(F32.from_nat(m)), bnd_f(F32.neg(F32.from_nat(m))))

# `bool` AND `void` ANSWER PYTHON'S `False` AND `True`, not a 1-bit integer's limits --
# `dtypes.is_int(bool)` is False, so `dtype.py`'s `if dtypes.is_int(self)` does not fire
# and the last line returns the two bools. They are `+0` and `+1` to every COMPARISON
# Python performs on them, which is why the oracle prints them numerically and why the arm
# is a pair and not `bnd_int(top, ...)`: a 1-bit INTEGER would give 0..1 by the width
# formula and `bnd_int`'s minimum would be `-2**0 = -1`, which is the wrong half.
def bnd_bool(+top: Bool) -> Bnd:
  bnd_i(False{}, Bool.pick(H.I64, top, H.i64_of_hi_lo(0, 1), H.i64_of_hi_lo(0, 0)))

# THE HUNDRED-AND-EIGHTY-BIT WIDTH IS WHY `weakint` SATURATES, and nothing names
# `weakint` here: `dt.bits` is 800, so `bnd_int`'s width guard answers for it, and it is
# the same guard that would answer for any future 128-bit dtype. `weakfloat`'s limits were
# already `inf` so it reaches `bnd_flt` on its own account.
def bnd_lim(+d: S.Dt, top: Bool) -> Bnd:
  match d:
    case S.Dt{0, 1, S.CBool{}, _}: bnd_bool(top)
    case S.Dt{0, 0, S.CVoid{}, _}: bnd_bool(top)
    case S.Dt{0, 800, S.CWeakInt{}, _}: bnd_int(top, True{}, 800)
    case S.Dt{1, 8, S.CSint{}, _}: bnd_int(top, True{}, 8)
    case S.Dt{2, 8, S.CUint{}, _}: bnd_int(top, False{}, 8)
    case S.Dt{3, 16, S.CSint{}, _}: bnd_int(top, True{}, 16)
    case S.Dt{4, 16, S.CUint{}, _}: bnd_int(top, False{}, 16)
    case S.Dt{5, 32, S.CSint{}, _}: bnd_int(top, True{}, 32)
    case S.Dt{6, 32, S.CUint{}, _}: bnd_int(top, False{}, 32)
    case S.Dt{7, 64, S.CSint{}, _}: bnd_int(top, True{}, 64)
    case S.Dt{8, 64, S.CUint{}, _}: bnd_int(top, False{}, 64)
    case S.Dt{9, 800, S.CWeakFloat{}, _}: bnd_flt(top)
    # THE THREE FP8 NAMES ARE `Dt`'s FOURTH FIELD AND NOT ITS PRIORITY: `fp8e4m3` and
    # `fp8e4m3fnuz` are BOTH pri 10, and `fp8e5m2` is pri 11 with `fp8e5m2fnuz`, so the
    # name is the only discriminator and these three arms are the file's ONE dependency on
    # a dtype's SPELLING. Measured: the `float8_e4m3` spelling answered `NInf`/`PInf` on
    # every fp8 row the moment `LAWS/spec.bend` was renamed to `fp8e4m3`, with the whole
    # file still `ALL PROOFS CHECK` -- a NAME match that stops matching is silent, and
    # `case _:` (the `bnd_flt` fall-through) is what absorbed it. `promo_mask` above is
    # the same exposure and it broke in the same commit.
    case S.Dt{10, 8, S.CFloat{}, "fp8e4m3"}: bnd_fmax(top, 448n)
    case S.Dt{10, 8, S.CFloat{}, "fp8e4m3fnuz"}: bnd_fmax(top, 240n)
    case S.Dt{11, 8, S.CFloat{}, "fp8e5m2"}: bnd_flt(top)
    case S.Dt{11, 8, S.CFloat{}, "fp8e5m2fnuz"}: bnd_fmax(top, 57344n)
    case S.Dt{12, 16, S.CFloat{}, _}: bnd_flt(top)
    case S.Dt{13, 16, S.CFloat{}, _}: bnd_flt(top)
    case S.Dt{14, 32, S.CFloat{}, _}: bnd_flt(top)
    case S.Dt{15, 64, S.CFloat{}, _}: bnd_flt(top)
    case _: bnd_flt(top)
# ===========================================================================
# THE OP TABLE -- ops.py:1105-1163. What follows is `_min_max` with the arena taken
# away: `mm.lift` is a PURE function of `(op, srcs, arg, dtype)` where `srcs` is the
# srcs' `(vmin, vmax)` ALREADY ANSWERED, in src order. The walk that produces those is a
# separate def for the reason the foot of this file gives, and splitting the two here is
# what makes the TABLE gateable on its own: `.agents/slop/mm-lift-gate.py` builds a real
# arena, reads CPython's `_min_max` for every node of it, and asks this table for the
# same node from the same srcs -- so a row cannot be right on one side and wrong on the
# other, which is the whole point of generating the expectation rather than typing it.
#
# FOUR RULES THE WHOLE TABLE FOLLOWS, and all four are soundness rather than style:
#
#   1. A `None` out of the binary block means "no arm fired", and Python FALLS THROUGH
#      to WHERE / Defines / RANGE / ... rather than answering. That is `mm.MM2.get`, and
#      it is why the binary block returns a `Maybe` and not a `Bnd2`. A `THREEFRY` on an
#      integer dtype has no arm, so it leaves the block and lands on `(dtype.min,
#      dtype.max)`, exactly as CPython does.
#   2. The block is entered ONLY for `op in GroupOp.Binary and not is_float(dtype)`, so no
#      float ever meets an arithmetic arm. A float-dtype ADD therefore never reaches
#      rule 1 -- it skips the block and lands on the same default.
#   3. ARITHMETIC SATURATES. `mm.u64.*` answers `None` when a result leaves
#      [0, 2**64-1], and that becomes `SNsat{sign}` -> `NInf`/`PInf`: a sound
#      OVER-APPROXIMATION, because a wider interval still answers `vmin == vmax`,
#      `int(x)` and `vmin_vmax is not None`.
#   4. `-0` IS `0`. A negation is `-(m + 1)` on the magnitude, so zero has to be caught
#      BEFORE it or `x - 0` answers `-1` and SUB's lower bound is one too low. Same for
#      `~x = -x - 1` and for the shift-right of a negative, which is a FLOOR and not a
#      truncation.
#
# WHAT IS NOT HERE, one line each, and none of them is a TODO:
#   * `Ops.CAST` -- `truncate` (dtype.py:297) is half a C-effect seam in `dtype.bend` and
#     a pure def cannot call it. The arm is not approximated; it is absent, so a CAST
#     lands on `(dtype.min, dtype.max)`.
#   * the `Ops.LOAD`-from-`Ops.BINARY` arm -- it needs `self.src[0].buf_uop`, a `while`
#     over five ops (ops.py:1053-1071) that mints a node the arena never interned.
#   * `CMOD`/`CDIV`/`FLOORDIV`/`FLOORMOD` need SIGNED division and `mm.dm.*` is an
#     UNSIGNED restoring divider. `mm.sn.div` below is the signed core and it is gated;
#     the four arms that call it are the next block, not this one.
# ===========================================================================

type Bnd2 is Data:
  Bnd2{lo: Bnd, hi: Bnd}

# THE TWO READERS, and they exist only because the gate has to print a bound pair as one
# string: a transposed `min`/`max` and a dropped sign are both visible in that string and
# neither is visible in a node count.
def Bnd2.lo(b: Bnd2) -> Bnd:
  match b:
    case Bnd2{lo, hi}: lo

def Bnd2.hi(b: Bnd2) -> Bnd:
  match b:
    case Bnd2{lo, hi}: hi

def bnd2_show(+b: Bnd2) -> String:
  String.concat(["lo=", bnd_show(Bnd2.lo(b)), " hi=", bnd_show(Bnd2.hi(b))])
# `Maybe` OUT OF THE BINARY BLOCK, and the only place one is consumed for the fall-through.
# It is not a `Maybe.default` because the fallback is a CALL that must be evaluated on the
# answer path too, and `Maybe.default` would evaluate it either way -- which hides which
# half of the ladder fired, and "no arm fired" is the answer for half of the binary ops.
def mm.MM2.get(m: Maybe<&2, Bnd2>, fb: Bnd2) -> Bnd2:
  match m:
    case Some{x}: x
    case None{}: fb

# THE SIGNED INTEGER, as a record rather than a `(Bool, H.I64)` pair: Bend has no tuple,
# and `SNsat` has to CARRY the sign it was heading for, which is exactly the one bit a
# `Maybe` cannot also carry.
type SInt2 is Data:
  SNok{neg: Bool, mag: H.I64}
  SNsat{neg: Bool}

def bnd.sn.zero() -> SInt2: SNok{False{}, H.i64_of_hi_lo(0, 0)}

# `Bool` HAS NO `is_eq` IN BEND 2.0.34, and equality of two `Bool`s is the negation of
# their exclusive-or. Every sign comparison in this section goes through here rather than
# through `==`, which does not exist either.
def bnd.same(a: Bool, b: Bool) -> Bool: Bool.not(Bool.xor(a, b))

# A FLOAT BOUND IS A SIGNED SATURATION, deliberately. `Int` against `Flt` has no exact
# answer in this representation -- `F32` cannot hold a 64-bit magnitude -- and a bound
# that is wrong in the unsound direction is worse than one that is wide. Every fixture
# family in the gate is integer-only or float-only for exactly this reason, and
# `bnd.pad` answers PAD's `0` in `F32` rather than leaning on this.
def bnd.sn.of(b: Bnd) -> SInt2:
  match b:
    case Bnd{i}: SNsat{Bool.pick(Bool, U32.is_zero(i), False{}, True{})}
    case BndInt{neg, +mag}: SNok{neg, mag}
    case BndFlt{v}: SNsat{F32.is_lt(v, 0.0)}

def bnd.sn.out(s: SInt2) -> Bnd:
  match s:
    case SNok{neg, +mag}: BndInt{neg, mag}
    case SNsat{neg}: Bool.pick(Bnd, neg, bnd_ninf(), bnd_pinf())

def bnd.sn.put.sign(neg: Bool, +g: H.I64) -> Bool:
  Bool.pick(Bool, mm.u64.is_zero(H.hi32(g), H.lo32(g)), False{}, neg)

# **THE SIGN IS FORCED TO POSITIVE ON A ZERO MAGNITUDE.** `Int{neg, mag}` has no canonical
# zero without this rule, and `0 * -5` builds `SNok{True, 0}` -- which is `-0`, which is the
# SAME Python int as `0` and a DIFFERENT `Bnd`, so the gate string differs. It is the same
# reason the header calls the zero a constant rather than a computed 0: an interval's
# endpoint is a value, and `-0` and `+0` are one value with two spellings here.
def bnd.sn.put(neg: Bool, m: Maybe<&2, H.I64>) -> SInt2:
  match m:
    case Some{+g}: SNok{bnd.sn.put.sign(neg, g), g}
    case None{}: SNsat{neg}

# `x - y` over unsigned magnitudes. A difference never leaves the window, so this is the
# one arithmetic operation with no saturation at all -- WHICH IS WHY IT IS ALSO THE
# SIGN-DECIDER for a sum of opposite signs.
def bnd.sn.diff(+xh: U32, +xl: U32, +yh: U32, +yl: U32) -> SInt2:
  Bool.pick(SInt2, mm.u64.lt(xh, xl, yh, yl),
    SNok{True{}, mm.u64w.sub(yh, yl, xh, xl)},
    SNok{False{}, mm.u64w.sub(xh, xl, yh, yl)})

# THE SUM. Same signs: the magnitudes add and the overflow becomes THAT sign's infinity,
# so `NInf + NInf = NInf` and `PInf - ... ` cannot happen (a difference is `diff`).
# Opposite signs: the answer is a difference, so the sign is whichever magnitude is
# larger and there is no overflow to ask about. Rule 4's `-0` case lives in `bnd.sn.neg`.
def bnd.sn.add.go(+na: Bool, +ma: H.I64, nb: Bool, +mb: H.I64) -> SInt2:
  Bool.pick(SInt2, bnd.same(na, nb),
    bnd.sn.put(na, mm.u64.add(H.hi32(ma), H.lo32(ma), H.hi32(mb), H.lo32(mb))),
    Bool.pick(SInt2, na,
      bnd.sn.diff(H.hi32(mb), H.lo32(mb), H.hi32(ma), H.lo32(ma)),
      bnd.sn.diff(H.hi32(ma), H.lo32(ma), H.hi32(mb), H.lo32(mb))))

def bnd.sn.add(+a: SInt2, +b: SInt2) -> SInt2:
  match a b:
    case SNsat{na} _: SNsat{na}
    case _ SNsat{nb}: SNsat{nb}
    case SNok{na, ma} SNok{nb, mb}: bnd.sn.add.go(na, ma, nb, mb)

# A NEGATION IS THE SIGN AND NOTHING ELSE -- the magnitude is `|x|` already. The `- 1` that
# `~x` needs belongs in `bnd.not` and NOT here, and measuring showed why: with the `+ 1` in
# this def, `x - y` came out one too low on every SUB row (`3 - 4` answered `-2` and
# `5 - 5` answered `-1`) because a subtraction IS a sum of a negation.
def bnd.sn.neg(s: SInt2) -> SInt2:
  match s:
    case SNsat{neg}: SNsat{Bool.not(neg)}
    case SNok{neg, +mag}: SNok{Bool.not(neg), mag}

def bnd.sn.mul(+a: SInt2, +b: SInt2) -> SInt2:
  match a b:
    case SNsat{na} _: SNsat{na}
    case _ SNsat{nb}: SNsat{nb}
    case SNok{na, ma} SNok{nb, mb}:
      bnd.sn.put(Bool.xor(na, nb), mm.u64.mul(H.hi32(ma), H.lo32(ma), H.hi32(mb), H.lo32(mb)))

def bnd.add(a: Bnd, b: Bnd) -> Bnd: bnd.sn.out(bnd.sn.add(bnd.sn.of(a), bnd.sn.of(b)))

def bnd.sub(a: Bnd, b: Bnd) -> Bnd: bnd.sn.out(bnd.sn.add(bnd.sn.of(a), bnd.sn.neg(bnd.sn.of(b))))

def bnd.mul(a: Bnd, b: Bnd) -> Bnd: bnd.sn.out(bnd.sn.mul(bnd.sn.of(a), bnd.sn.of(b)))

# `~x` IS `-x - 1` AND NOT `-x`, and the row that notices is XOR's arm with `s1 == -1`,
# where the two differ by one on every input.
def bnd.not(a: Bnd) -> Bnd:
  bnd.add(bnd.sn.out(bnd.sn.neg(bnd.sn.of(a))), bnd_i(True{}, H.i64_of_hi_lo(0, 1)))

# A MAGNITUDE NARROWED TO A `U32`, for the two callers whose bound is already at most 64 (a
# mask WIDTH and a shift AMOUNT). It is a def rather than an inline pair so that `U32.to_nat`
# is reached exactly once and so the precondition lives in one comment.
def mm.narrow(+mag: H.I64) -> U32: mm.bl64(H.hi32(mag), H.lo32(mag))

# THE SHIFT AMOUNT IS THE LOW WORD, and that is only the amount because
# `mm.shamt.big` has already refused anything past 64. `mm.narrow` next to it is the OTHER
# narrowing -- a bit WIDTH, which is `bit_length` and not the value -- and the two are one
# line apart on purpose: reading a shift amount as a bit width shifts by `bit_length(k)`,
# which is `1 << 3` answering `4`.
def mm.shamt.lo32(+mag: H.I64) -> U32: H.lo32(mag)

# THE SHIFT AMOUNT, and the two reasons it is a `Maybe`. Python's `x << k` raises on a
# negative `k` and this table answers "the node raises" by leaving the block, and Python's
# `x << k` for `k > 64` is a value past every dtype limit, which is a saturation rather
# than an answer. So the guard is on `k`, not on `x`, and `U32.to_nat` is never reached
# with a value past 64 -- `Nat` refuses past 2**48 and a refusal is not a value.
# THE SHIFT AMOUNT ITSELF, AND IT IS NOT A MASK WIDTH. `bnd.shl.k1` answered `bit_length`
# because that is what the AND arm's mask needs, and the SHL/SHR arms need the VALUE:
# `x << k` shifts by `k` and not by `bit_length(k)`. Measuring that difference: `1 << 3`
# answered `4` on every SHL row, which is `1 << 2`, i.e. the bit length of 3.
#
# Python's `x << k` raises on a negative `k` and gives a value past every dtype limit for a
# `k` past 64, so the guard is on `k` and the `Maybe` is "the node raises". `U32.to_nat` is
# reached only with a value in [0, 64] and `Nat` refuses past 2**48, so a refusal is not.
def bnd.shamt.put(bad: Bool, +mag: H.I64) -> Maybe<&2, Nat>:
  match bad:
    case True{}: None{}
    case False{}: Some{U32.to_nat(mm.shamt.lo32(mag))}

def mm.shamt.big(+mag: H.I64) -> Bool: U32.is_gt(mm.bl64(H.hi32(mag), H.lo32(mag)), 64)

def bnd.shamt(b: Bnd) -> Maybe<&2, Nat>:
  match b:
    case BndInt{neg, +mag}: bnd.shamt.put(Bool.or(neg, mm.shamt.big(mag)), mag)
    case _: None{}

def bnd.sn.shl(s: SInt2, +k: Nat) -> SInt2:
  match s:
    case SNsat{neg}: SNsat{neg}
    case SNok{neg, +mag}: bnd.sn.put(neg, mm.u64.shl(H.hi32(mag), H.lo32(mag), k))

# `x >> k` IS A FLOOR AND NOT A TRUNCATION, and the identity that gets it right without
# ever adding `2**k` is `floor(-m / 2**k) = -(m >> k) - [the low k bits are set]`. The
# obvious spelling, `-(m + 2**k - 1) >> k`, overflows for every `m` above `2**64 - 2**k`
# and would answer `NInf` where CPython answers a small number.
# THE REMAINDER MASK, `2**k - 1`, AS A WORD PAIR. It is `mm.mask64(k)` in one expression
# and this is the two-arm spelling of it, because the caller needs the LOW WORD on its own
# -- and because `mm.mask.hi` is the only one of the two that is right for a `k` past 32:
# `mm.mask.lo(64)` underflows `Nat.sub` to all ones, which is correct, while `mm.mask.hi(0)`
# is all ones and is wrong. A `k` of 0 is not reachable (the gate needs `int` bounds and
# `bnd.shl.k1` refuses a magnitude over 64), but the identity still holds for it.
def mm.shremask(+k: U32) -> H.I64: H.i64_of_hi_lo(mm.mask.hi(k), mm.mask.lo(k))

def bnd.sn.shr.rem(+k: Nat) -> H.I64:
  Bool.pick(H.I64, U32.is_ge(U32.from_nat(k), 32), mm.shremask(U32.from_nat(k)),
    H.i64_of_hi_lo(0, mm.mask.lo(U32.from_nat(k))))

def bnd.sn.shr.neg(+mag: H.I64, +k: Nat) -> SInt2:
  +q = mm.u64.shr(H.hi32(mag), H.lo32(mag), k)
  +mk = bnd.sn.shr.rem(k)
  +r = mm.u64.and(H.hi32(mag), H.lo32(mag), H.hi32(mk), H.lo32(mk))
  bnd.sn.put(True{}, mm.u64.add(H.hi32(q), H.lo32(q), 0, Bool.pick(U32, mm.u64.is_zero(H.hi32(r), H.lo32(r)), 0, 1)))

def bnd.sn.shr.go(neg: Bool, +mag: H.I64, +k: Nat) -> SInt2:
  Bool.pick(SInt2, neg, bnd.sn.shr.neg(mag, k), SNok{False{}, mm.u64.shr(H.hi32(mag), H.lo32(mag), k)})

def bnd.sn.shr(s: SInt2, +k: Nat) -> SInt2:
  match s:
    case SNsat{neg}: SNsat{neg}
    case SNok{neg, +mag}: bnd.sn.shr.go(neg, mag, k)

def bnd.shl(a: Bnd, +k: Nat) -> Bnd: bnd.sn.out(bnd.sn.shl(bnd.sn.of(a), k))

def bnd.shr(a: Bnd, +k: Nat) -> Bnd: bnd.sn.out(bnd.sn.shr(bnd.sn.of(a), k))

# THE COMPARISON, over the whole union, and the three classes ranked `NInf < Int/Flt <
# PInf`. Int against Int is the signed order and Flt against Flt is IEEE, and the eight
# mixed arms are the two infinities against the two finite classes. The ninth pair --
# `Int` against `Flt` -- is the `case _:` and it answers False, which is WRONG in general
# and is why no fixture in the gate mixes the two classes.
# THE SIGNED ORDER IS FOUR CASES AND NOT TWO, and the two-case spelling -- "if `a` is
# negative compare the magnitudes backwards" -- is WRONG for a negative `a` against a
# non-negative `b`, where the answer is always `true` rather than a magnitude comparison.
# Measured: that spelling made `max(-3, 4)` answer `-3` and `cmplt(-3, 4)` answer `False`,
# on 53 of this gate's 123 rows.
def bnd.lt.i(+na: Bool, +ma: H.I64, +nb: Bool, +mb: H.I64) -> Bool:
  Bool.pick(Bool, na,
    Bool.pick(Bool, nb, mm.u64.lt(H.hi32(mb), H.lo32(mb), H.hi32(ma), H.lo32(ma)), True{}),
    Bool.pick(Bool, nb, False{}, mm.u64.lt(H.hi32(ma), H.lo32(ma), H.hi32(mb), H.lo32(mb))))

def bnd.lt(+a: Bnd, +b: Bnd) -> Bool:
  match a b:
    case BndInt{na, ma} BndInt{nb, mb}: bnd.lt.i(na, ma, nb, mb)
    case BndFlt{fa} BndFlt{fb}: F32.is_lt(fa, fb)
    case Bnd{i} BndInt{_, _}: U32.is_zero(i)
    case BndInt{_, _} Bnd{i}: U32.is_zero(i)
    case Bnd{i} BndFlt{_}: U32.is_zero(i)
    case BndFlt{_} Bnd{i}: U32.is_zero(i)
    case Bnd{i} Bnd{j}: Bool.pick(Bool, U32.is_zero(i), True{}, False{})
    case _ _: False{}

def bnd.eq(+a: Bnd, +b: Bnd) -> Bool:
  match a b:
    case Bnd{i} Bnd{j}: U32.is_eq(i, j)
    case BndInt{na, ma} BndInt{nb, mb}:
      Bool.and(bnd.same(na, nb), mm.u64.eq(H.hi32(ma), H.lo32(ma), H.hi32(mb), H.lo32(mb)))
    case BndFlt{fa} BndFlt{fb}: F32.is_eq(fa, fb)
    case _ _: False{}

def bnd.min(+a: Bnd, +b: Bnd) -> Bnd: Bool.pick(Bnd, bnd.lt(a, b), a, b)

def bnd.max(+a: Bnd, +b: Bnd) -> Bnd: Bool.pick(Bnd, bnd.lt(a, b), b, a)

# `bool(v)` AS A BOUND. Python's comparison arms answer `True`/`False`, which are the
# integers 1 and 0 to every reader of a bound, and `bnd_bool`'s top arm is that same
# spelling -- so the two agree by construction rather than by coincidence.
def bnd_tf(c: Bool) -> Bnd: Bool.pick(Bnd, c, bnd_i(False{}, H.i64_of_hi_lo(0, 1)), bnd_i(False{}, H.i64_of_hi_lo(0, 0)))

# ---- an `H.I64` as a `Bnd` ------------------------------------------------------
#
# `CInt` and `PyRange` hold `H.I64`, which is a SIGNED two's-complement pair, and `Bnd` is
# a sign plus an unsigned magnitude. So reading one the other way is a sign test and a
# `-(m+1)` on the negative side, and `H.i64_text` prints the signed value in the gate --
# which is why a transposed `min`/`max` here shows up as a string difference rather than
# as a plausible number.
def mm.i64.is_neg(+i: H.I64) -> Bool: U32.is_eq(U32.shrn(H.hi32(i), 31n), 1)

def mm.i64.mag(+i: H.I64) -> H.I64:
  +c = mm.u64.not(H.hi32(i), H.lo32(i))
  H.i64_of_hi_lo(U32.add(H.hi32(c), mm.u32c(H.lo32(c), 1)), U32.add(H.lo32(c), 1))

def mm.i64.to_bnd(+i: H.I64) -> Bnd:
  Bool.pick(Bnd, mm.i64.is_neg(i), bnd_i(True{}, mm.i64.mag(i)), bnd_i(False{}, i))

# ---- the table's own inputs -----------------------------------------------------
#
# A MISSING SRC IS THE UNBOUNDED INTERVAL rather than a refusal. Python raises
# `IndexError` there, and every consumer of `_min_max` reads a bound, so the answer that
# keeps the fold total is the widest one: an arithmetic arm on it saturates and a
# comparison arm on it is decided by the rank.
def mm.unbound() -> Bnd2: Bnd2{bnd_ninf(), bnd_pinf()}

def mm.src2(+xs: List<&2, Bnd2>, k: U32) -> Bnd2:
  Maybe.default(&2, Bnd2, List.get(&2, Bnd2, xs, U32.to_nat(k)), mm.unbound())

def mm.s0(+xs: List<&2, Bnd2>) -> Bnd2: mm.src2(xs, 0)

def mm.s1(+xs: List<&2, Bnd2>) -> Bnd2: mm.src2(xs, 1)

def mm.s2(+xs: List<&2, Bnd2>) -> Bnd2: mm.src2(xs, 2)

def mm.default(+d: S.Dt) -> Bnd2: Bnd2{bnd_lim(d, False{}), bnd_lim(d, True{})}

# ---- the sixteen binary arms ----------------------------------------------------
#
# IN PYTHON'S ORDER, because the order IS the semantics: `AND`'s integer arm is before
# `MUL`'s, and the `bool`-dtype `OR`/`AND` arms are LAST so they cannot be taken by the
# integer `AND` above them. Every arm reads `s0`/`s1` as `Bnd2` and hands back the pair,
# so the fall-through is the `Maybe` and nothing else has to know about it.
# THE FOUR `dtypes.is_*` PREDICATES, read off `Dt`'s OWN third field. They are defs and
# not matches at the use site because `dtypes.is_float(self.dtype)` is a CALL and a `match`
# may not scrutinise one -- the recorded rule, and the reason `dt_is` exists at all.
def dt_is.not_float(+d: S.Dt) -> Bool:
  match d:
    case S.Dt{_, _, S.CFloat{}, _}: False{}
    case _: True{}

def dt_is.is_int(+d: S.Dt) -> Bool:
  match d:
    case S.Dt{_, _, S.CSint{}, _}: True{}
    case S.Dt{_, _, S.CUint{}, _}: True{}
    case _: False{}

def dt_is.is_bool(+d: S.Dt) -> Bool:
  match d:
    case S.Dt{_, _, S.CBool{}, _}: True{}
    case _: False{}

def dt_is.is_void(+d: S.Dt) -> Bool:
  match d:
    case S.Dt{_, _, S.CVoid{}, _}: True{}
    case _: False{}

def mm.bin.enter(op: O.Op, +d: S.Dt) -> Bool:
  Bool.and(O.GroupOp.binary(op), dt_is.not_float(d))

# `is_int(dtype) and s1_vmin == s1_vmax >= 0`. The `>= 0` is `not s1_vmin.neg`, and the
# `==` is the signed equality, so the gate is exact rather than "non-negative bound".
def bnd_bin.nonneg(b: Bnd) -> Bool:
  match b:
    case BndInt{neg, mag}: Bool.not(neg)
    case _: False{}

def bnd_bin.and_gate(+s1: Bnd2, d: S.Dt) -> Bool:
  Bool.and(dt_is.is_int(d), Bool.and(bnd.eq(Bnd2.lo(s1), Bnd2.hi(s1)), bnd_bin.nonneg(Bnd2.lo(s1))))

# `&` OF TWO IN-WINDOW PAIRS IS IN-WINDOW, so this is `mm.u64.and` and NOT the
# `Maybe`-returning `mm_mask64`: the `Maybe` on THAT def is about `bit_length`'s shift, and
# reusing the reader here would make a table arm depend on a def that can answer `None`.
def mm.and64(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> H.I64: mm.u64.and(ah, al, bh, bl)

# THE MASK WIDTH COMES FROM `s0` AND THE MASKED VALUE IS `s1` -- they are DIFFERENT SRCS, and
# `andint_int32_2147483648_7` is the row that says so: `7 & ((1 << 32) - 1)` is `7`, while
# `2**31 & 7` is `0`. Reading it as one src answering `s0 & mask(s0)` is a plausible wrong
# answer that a fixture with `s0` and `s1` both small cannot see, which is why the family
# carries `2**31` and `2**40` against small masks.
def mm.bin.and_int.mask.go(+ma: H.I64, nc: Bool, +mc: H.I64) -> Bnd:
  +mk = mm.mask64(mm.narrow(ma))
  bnd_i(nc, mm.and64(H.hi32(mk), H.lo32(mk), H.hi32(mc), H.lo32(mc)))

# A `Bnd` HAS NO PROJECTION, so the pair is destructured here rather than read. The
# fallback is `PInf` and it is a bound, not a guess: `bnd.lt(lo, 0)` false means `lo` is
# not `NInf`, so an unbounded bound reaching this arm is a `hi` of `PInf`, and masking an
# unbounded value by any width is unbounded.
def mm.bin.and_int.mask(a: Bnd, c: Bnd) -> Bnd:
  match a c:
    case BndInt{_, +ma} BndInt{nc, +mc}: mm.bin.and_int.mask.go(ma, nc, mc)
    case _ _: bnd_pinf()

# `0, s1_vmax` when the src's minimum is negative, and `min(s0_vmax, s1_vmax & mask)`
# otherwise. The mask is `mm_mask64`, which is the AND arm of `ops.py:1110` verbatim and
# is already gated by the `mk_*` rows -- so this arm has NO arithmetic of its own and
# cannot be one bit off in a direction the `mk_*` rows would not already have caught.
def mm.bin.and_int.go(+s0: Bnd2, +s1: Bnd2) -> Bnd2:
  Bool.pick(Bnd2, bnd.lt(Bnd2.lo(s0), bnd_zero()), Bnd2{bnd_zero(), Bnd2.hi(s1)},
    Bnd2{bnd_zero(), bnd.min(Bnd2.hi(s0), mm.bin.and_int.mask(Bnd2.hi(s0), Bnd2.hi(s1)))})

# Python's `or`/`and` ON INTS, which is NOT `Bool.or`/`Bool.and` (neither of those
# short-circuits) and not a pick between the two values either: `0 or 1` is `1` and
# `1 and 0` is `0`, so each is "the first if it is nonzero, otherwise the second" and
# "the first if it is ZERO, otherwise the second" -- the same test with the roles of the
# arms swapped, which is the only reason these are two defs and not one.
def bnd.nz(b: Bnd) -> Bool:
  match b:
    case BndInt{neg, +mag}: Bool.or(neg, Bool.not(mm.u64.is_zero(H.hi32(mag), H.lo32(mag))))
    case _: True{}

def bnd.and(+a: Bnd, b: Bnd) -> Bnd: Bool.pick(Bnd, bnd.nz(a), b, a)
def mm.bin.and_bool.go(+s0: Bnd2, +s1: Bnd2) -> Bnd2:
  Bnd2{bnd.and(Bnd2.lo(s0), Bnd2.lo(s1)), bnd.and(Bnd2.hi(s0), Bnd2.hi(s1))}

# `Ops.AND` HAS TWO ARMS AND THE SECOND IS REACHED EXACTLY WHEN THE FIRST IS NOT: the
# integer mask and the `bool` dtype's `and`. A `match` takes the FIRST arm that matches, so
# two `case O.OpsAND{}` arms would make the second DEAD and a `case _:` after the first
# would never be reached either -- which is what the gate measured: every `andb_*` row
# answered `bool`'s own limits because the integer arm returned `None` and the block fell
# through to `(dtype.min, dtype.max)`. ONE dispatch over the dtype's class is the fix.
def mm.bin.and_int(gate: Bool, +s0: Bnd2, +s1: Bnd2) -> Maybe<&2, Bnd2>:
  match gate:
    case True{}: Some{mm.bin.and_int.go(s0, s1)}
    case False{}: None{}

def mm.bin.and(bl: Bool, d: S.Dt, +s0: Bnd2, +s1: Bnd2) -> Maybe<&2, Bnd2>:
  match bl:
    case True{}: Some{mm.bin.and_bool.go(s0, s1)}
    case False{}: mm.bin.and_int(bnd_bin.and_gate(s1, d), s0, s1)

def bnd.or(+a: Bnd, b: Bnd) -> Bnd: Bool.pick(Bnd, bnd.nz(a), a, b)

def mm.bin.or_bool(bl: Bool, +s0: Bnd2, +s1: Bnd2) -> Maybe<&2, Bnd2>:
  match bl:
    case True{}: Some{Bnd2{bnd.or(Bnd2.lo(s0), Bnd2.lo(s1)), bnd.or(Bnd2.hi(s0), Bnd2.hi(s1))}}
    case False{}: None{}

# MUL: FOUR PRODUCTS, THE SMALLEST AND THE LARGEST. `min(vals)` over a keyword-argument
# tuple is a fold, and the fold is over FOUR VALUES rather than a list -- which is why it
# is `bnd.min`/`bnd.max` four times and not a `List.foldl`. The products must all be built,
# so they are bound first; a `Bool.pick` chain would drop three of them.
def mm.bin.mul(+s0: Bnd2, +s1: Bnd2) -> Bnd2:
  +p0 = bnd.mul(Bnd2.lo(s0), Bnd2.lo(s1))
  +p1 = bnd.mul(Bnd2.lo(s0), Bnd2.hi(s1))
  +p2 = bnd.mul(Bnd2.hi(s0), Bnd2.lo(s1))
  +p3 = bnd.mul(Bnd2.hi(s0), Bnd2.hi(s1))
  +a = bnd.min(p0, p1)
  +b = bnd.min(p2, p3)
  +c = bnd.max(p0, p1)
  +d = bnd.max(p2, p3)
  Bnd2{bnd.min(a, b), bnd.max(c, d)}

# SHL/SHR ON CONSTS ONLY, and the gate is Python's `all_int(t := (s0_vmin, s0_vmax,
# s1_vmin))` PLUS `s1_vmin == s1_vmax`. `s1_vmax` is NOT tested, so a shift amount that
# is only known to be equal to itself is not enough -- both ends of BOTH source bounds
# and the amount's minimum have to be integers. That is three separate gates and dropping
# the third is the mistake the `shl_*`/`shr_*` rows are built to catch.
def bnd.is_int(b: Bnd) -> Bool:
  match b:
    case BndInt{neg, mag}: True{}
    case _: False{}

def mm.bin.sh.go(+s0: Bnd2, lft: Bool, +k: Nat) -> Bnd2:
  Bool.pick(Bnd2, lft, Bnd2{bnd.shl(Bnd2.lo(s0), k), bnd.shl(Bnd2.hi(s0), k)},
    Bnd2{bnd.shr(Bnd2.lo(s0), k), bnd.shr(Bnd2.hi(s0), k)})

def mm.bin.sh(k: Maybe<&2, Nat>, +s0: Bnd2, lft: Bool) -> Maybe<&2, Bnd2>:
  match k:
    case Some{n}: Some{mm.bin.sh.go(s0, lft, n)}
    case None{}: None{}

def mm.bin.sh.k(ok: Bool, +s0: Bnd2, +s1: Bnd2) -> Maybe<&2, Nat>:
  match ok:
    case True{}: bnd.shamt(Bnd2.lo(s1))
    case False{}: None{}

def mm.bin.sh.ok(+s0: Bnd2, +s1: Bnd2) -> Bool:
  Bool.and(Bool.and(bnd.eq(Bnd2.lo(s1), Bnd2.hi(s1)), bnd.is_int(Bnd2.lo(s0))),
    Bool.and(bnd.is_int(Bnd2.hi(s0)), bnd.is_int(Bnd2.lo(s1))))

# XOR BY AN ALL-ONES CONSTANT IS THE ONLY BITWISE ARM, and it is `~vmax, ~vmin` -- the
# NEGATION OF MONOTONE, so the two halves swap. Reading it as `vmin, vmax` is the mistake
# the `xor_*` row is for.
def mm.bin.xor(gate: Bool, +s0: Bnd2, +s1: Bnd2) -> Maybe<&2, Bnd2>:
  match gate:
    case True{}: Some{Bnd2{bnd.not(Bnd2.hi(s0)), bnd.not(Bnd2.lo(s0))}}
    case False{}: None{}

def bnd_minus_one() -> Bnd: bnd_i(True{}, H.i64_of_hi_lo(0, 1))

def mm.bin.xor.gate(+s1: Bnd2) -> Bool:
  Bool.and(bnd.eq(Bnd2.lo(s1), bnd_minus_one()), bnd.eq(Bnd2.hi(s1), bnd_minus_one()))

def mm.bin.max(+s0: Bnd2, +s1: Bnd2) -> Bnd2:
  Bnd2{bnd.max(Bnd2.lo(s0), Bnd2.lo(s1)), bnd.max(Bnd2.hi(s0), Bnd2.hi(s1))}

# CMPLT AND CMPNE ANSWER BOOLEANS, and a boolean interval's two halves are computed by two
# DIFFERENT predicates: `s0_vmax < s1_vmin` against `s0_vmin < s1_vmax`, where the operands
# are not interchangeable and the direction of the first is the one that is easy to get
# backwards. `bnd.lt` is the signed order over the whole union, so `False` here means
# provably-not-less rather than unknown.
def mm.bin.cmplt(+s0: Bnd2, +s1: Bnd2) -> Bnd2:
  Bnd2{bnd_tf(bnd.lt(Bnd2.hi(s0), Bnd2.lo(s1))), bnd_tf(bnd.lt(Bnd2.lo(s0), Bnd2.hi(s1)))}

def mm.bin.cmpne(+s0: Bnd2, +s1: Bnd2) -> Bnd2:
  Bnd2{bnd_tf(Bool.or(bnd.lt(Bnd2.hi(s0), Bnd2.lo(s1)), bnd.lt(Bnd2.hi(s1), Bnd2.lo(s0)))),
    bnd_tf(Bool.not(Bool.and(bnd.eq(Bnd2.lo(s0), Bnd2.hi(s0)),
      Bool.and(bnd.eq(Bnd2.lo(s1), Bnd2.hi(s1)), bnd.eq(Bnd2.lo(s0), Bnd2.lo(s1))))))}


def mm.bin.add(+s0: Bnd2, +s1: Bnd2) -> Bnd2:
  Bnd2{bnd.add(Bnd2.lo(s0), Bnd2.lo(s1)), bnd.add(Bnd2.hi(s0), Bnd2.hi(s1))}

# SUB'S TWO HALVES CROSS: the LOWER bound subtracts the other's UPPER and the UPPER
# subtracts the other's LOWER, because `x - y` is smallest when x is smallest and y is
# largest. Subtracting `lo` from `lo` is the mistake `sub_*` is for, and it is a real
# answer on every fixture where the bounds happen to agree.
def mm.bin.sub(+s0: Bnd2, +s1: Bnd2) -> Bnd2:
  Bnd2{bnd.sub(Bnd2.lo(s0), Bnd2.hi(s1)), bnd.sub(Bnd2.hi(s0), Bnd2.lo(s1))}

# ---- THE ARM DISPATCH, one match over the op, in Python's order ------------------
def mm.bin.arm(+op: O.Op, +srcs: List<&2, Bnd2>, +d: S.Dt) -> Maybe<&2, Bnd2>:
  match op:
    case O.OpsADD{}: Some{mm.bin.add(mm.s0(srcs), mm.s1(srcs))}
    case O.OpsSUB{}: Some{mm.bin.sub(mm.s0(srcs), mm.s1(srcs))}
    case O.OpsAND{}: mm.bin.and(dt_is.is_bool(d), d, mm.s0(srcs), mm.s1(srcs))
    case O.OpsMUL{}: Some{mm.bin.mul(mm.s0(srcs), mm.s1(srcs))}
    case O.OpsSHL{}: mm.bin.sh(mm.bin.sh.k(mm.bin.sh.ok(mm.s0(srcs), mm.s1(srcs)), mm.s0(srcs), mm.s1(srcs)), mm.s0(srcs), True{})
    case O.OpsSHR{}: mm.bin.sh(mm.bin.sh.k(mm.bin.sh.ok(mm.s0(srcs), mm.s1(srcs)), mm.s0(srcs), mm.s1(srcs)), mm.s0(srcs), False{})
    case O.OpsXOR{}: mm.bin.xor(mm.bin.xor.gate(mm.s1(srcs)), mm.s0(srcs), mm.s1(srcs))
    case O.OpsMAX{}: Some{mm.bin.max(mm.s0(srcs), mm.s1(srcs))}
    case O.OpsCMPLT{}: Some{mm.bin.cmplt(mm.s0(srcs), mm.s1(srcs))}
    case O.OpsCMPNE{}: Some{mm.bin.cmpne(mm.s0(srcs), mm.s1(srcs))}
    case O.OpsOR{}: mm.bin.or_bool(dt_is.is_bool(d), mm.s0(srcs), mm.s1(srcs))
    case _: None{}

def mm.lift.bin(enter: Bool, +op: O.Op, +srcs: List<&2, Bnd2>, d: S.Dt) -> Maybe<&2, Bnd2>:
  match enter:
    case True{}: mm.bin.arm(op, srcs, d)
    case False{}: None{}

# ---- the arms OUTSIDE the binary block, in Python's order -----------------------
#
# WHERE is `min(s1, s2)` on the LOWER bounds and `max(s1, s2)` on the UPPER, which is not
# `min(s0, s1)` for any reading of the indices: the CONDITION's bound is skipped and the
# two arms are the operands.
def mm.where(+srcs: List<&2, Bnd2>) -> Bnd2:
  +a = mm.s1(srcs)
  +b = mm.s2(srcs)
  Bnd2{bnd.min(Bnd2.lo(a), Bnd2.lo(b)), bnd.max(Bnd2.hi(a), Bnd2.hi(b))}

def mm.defines.got(pr: O.PyRange) -> Bnd2:
  match pr:
    case O.PyRange{lo, hi}: Bnd2{mm.i64.to_bnd(lo), mm.i64.to_bnd(hi)}

def mm.defines.range(r: Maybe<&2, O.PyRange>, +d: S.Dt) -> Bnd2:
  match r:
    case Some{pr}: mm.defines.got(pr)
    case None{}: mm.default(d)

# `Defines and arg.vmin_vmax is not None`. A PARAM/BUFFER/ALLOC with no range falls
# through every later arm -- none of them can match a Defines op -- and lands on the
# dtype limits, so the fall-through is spelled here rather than as a second `Maybe`.
def mm.defines.pa(pa: O.ParamArg, +d: S.Dt) -> Bnd2:
  match pa:
    case O.ParamArg{_, _, _, vmin_vmax, _, _, _, _, _, _, _, _, _}: mm.defines.range(vmin_vmax, d)

def mm.defines(arg: O.Arg, +d: S.Dt) -> Bnd2:
  match arg:
    case O.AParam{pa}: mm.defines.pa(pa, d)
    case _: mm.default(d)

def bnd_one() -> Bnd: bnd_i(False{}, H.i64_of_hi_lo(0, 1))

# `RANGE`/`SPECIAL` ANSWER `0, (src[0] - 1).vmax`, and the `(src[0] - 1)` is a REAL UOp:
# a SUB node, whose upper bound is `src[0].vmax - 1`. Reading it as `src[0].vmax` is off
# by one on every RANGE and every SPECIAL, and `range_*` is the row.
def mm.range(vd: Bool, +srcs: List<&2, Bnd2>, +d: S.Dt) -> Bnd2:
  match vd:
    case True{}: mm.default(d)
    case False{}: Bnd2{bnd_zero(), bnd.sub(Bnd2.hi(mm.s0(srcs)), bnd_one())}

# STACK IS A FOLD OVER AN ARBITRARY NUMBER OF SRCS, and `min()`/`max()` over a generator
# is that fold. The seed is the IDENTITY pair rather than a sentinel `0xFFFFFFFF`, which
# is the recorded `max`/`min` sentinel trap: `U32` sentinels win every comparison.
def mm.stack.step.go(+acc: Bnd2, +x: Bnd2) -> Bnd2:
  Bnd2{bnd.min(Bnd2.lo(acc), Bnd2.lo(x)), bnd.max(Bnd2.hi(acc), Bnd2.hi(x))}

# THE `+` S ARE NOT SPELLABLE IN THE CLOSURE'S TYPE, which is the recorded closure-shared-
# arg wall, so the step is a DEF and `mm.stack` passes it as a top-level name rather than a
# lambda. `List.foldl` calls it once per element with a fresh accumulator each time, so the
# `+` is only needed for the two READS inside one step.
def mm.stack.step(acc: Bnd2, x: Bnd2) -> Bnd2: mm.stack.step.go(acc, x)

def mm.stack(+srcs: List<&2, Bnd2>) -> Bnd2:
  List.foldl(~&2, ~Bnd2, ~Bnd2, mm.stack.step, srcs, Bnd2{bnd_pinf(), bnd_ninf()})

def mm.const.f(nan: Bool, +f: F32) -> Maybe<&2, Bnd2>:
  match nan:
    case True{}: Some{Bnd2{bnd_f(f), bnd_f(f)}}
    case False{}: None{}

def mm.const.f.of(+f: F32) -> Maybe<&2, Bnd2>:
  mm.const.f(F32.is_eq(f, f), f)

def mm.i64.same(+i: H.I64) -> Bnd2:
  +b = mm.i64.to_bnd(i)
  Bnd2{b, b}

# A CONST IS `(val, val)` UNLESS it is Invalid or a NaN. The NaN test is IEEE and needs
# no `math.isnan`: `not isnan(v)` IS `v == v`, and `F32.is_eq` is IEEE, so the float arm
# is `F32.is_eq(f, f)` -- a `f != f` spelling would have been the same test and one that
# looks like a bug.
# A `CBool`'s BOUND IS THE BOOL ITSELF, spelled numerically: `False`/`True` are the
# integers 0/1 to every comparison Python performs on a bound, which is what `dt_row` for
# `boolean` and `void` prints and what `bnd_bool`'s top arm already answers.
def mm.const.b(b: Bool) -> Maybe<&2, Bnd2>:
  Bool.pick(Maybe<&2, Bnd2>, b, Some{Bnd2{bnd_tf(True{}), bnd_tf(True{})}}, Some{Bnd2{bnd_tf(False{}), bnd_tf(False{})}})

def mm.const.v(v: O.Const) -> Maybe<&2, Bnd2>:
  match v:
    case O.CBool{b}: mm.const.b(b)
    case O.CInt{i}: Some{mm.i64.same(i)}
    case O.CFloat{f}: mm.const.f.of(f)
    case O.CInvalid{}: None{}

def mm.const.got(v: O.Const, +d: S.Dt) -> Bnd2:
  mm.MM2.get(mm.const.v(v), mm.default(d))

def mm.const(arg: O.Arg, +d: S.Dt) -> Bnd2:
  match arg:
    case O.APy{v}: mm.const.got(v, d)
    case _: mm.default(d)

def bnd.is_flt(b: Bnd) -> Bool:
  match b:
    case BndFlt{v}: True{}
    case _: False{}

def mm.pad.flt.hi(+f: F32) -> Bnd:
  Bool.pick(Bnd, F32.is_lt(0.0, f), bnd_f(f), bnd_zero())

def mm.pad.flt.pick(+f: F32, +hi: Bnd) -> Bnd2:
  Bool.pick(Bnd2, F32.is_lt(f, 0.0), Bnd2{bnd_f(f), bnd_zero()},
    Bnd2{bnd_zero(), mm.pad.flt.hi(f)})

# `PAD ADDS ZEROS` IN `F32`, because a float src bound against the INTEGER zero is the
# one place Python mixes the two classes and it does so exactly: `min(1.5, 0)` is the
# INTEGER `0`, so the answer is `bnd_zero()` and not `0.0`. `max(1.5, 0)` is `1.5`.
def mm.pad.flt(lo: Bnd, hi: Bnd) -> Bnd2:
  match lo:
    case BndFlt{f}: mm.pad.flt.pick(f, hi)
    case _: Bnd2{bnd.min(lo, bnd_zero()), bnd.max(hi, bnd_zero())}

# `PAD ADDS ZEROS`. The zero is compared in `F32` when the source bound is a float,
# because that is the ONE place Python mixes the two classes and it does so exactly:
# `min(1.5, 0)` is the INTEGER `0`, so the answer is `Bnd` zero and not a float zero.
def mm.pad(+srcs: List<&2, Bnd2>) -> Bnd2:
  +s = mm.s0(srcs)
  Bool.pick(Bnd2, bnd.is_flt(Bnd2.lo(s)), mm.pad.flt(Bnd2.lo(s), Bnd2.hi(s)),
    Bnd2{bnd.min(Bnd2.lo(s), bnd_zero()), bnd.max(Bnd2.hi(s), bnd_zero())})

# THE PASSTHROUGH. `GroupOp.Movement | {INDEX, STAGE, AFTER, DETACH, COPY,
# CONTIGUOUS_BACKWARD}` is `self.src[0]._min_max` -- a NO-OP on the interval, which is why
# a RESHAPE (which this file does not answer a SHAPE for) still has an interval. PAD is in
# Movement and does NOT pass through, and Python gets that right by testing PAD first; the
# order here is the same order.
def mm.lift.mv(+srcs: List<&2, Bnd2>) -> Bnd2: mm.s0(srcs)

# ---- THE TABLE -------------------------------------------------------------------
def mm.lift.rest(+op: O.Op, +srcs: List<&2, Bnd2>, arg: O.Arg, +d: S.Dt) -> Bnd2:
  match op:
    case O.OpsWHERE{}: mm.where(srcs)
    case O.OpsPARAM{}: mm.defines(arg, d)
    case O.OpsBUFFER{}: mm.defines(arg, d)
    case O.OpsALLOC{}: mm.defines(arg, d)
    case O.OpsRANGE{}: mm.range(dt_is.is_void(d), srcs, d)
    case O.OpsSPECIAL{}: mm.range(dt_is.is_void(d), srcs, d)
    case O.OpsSTACK{}: mm.stack(srcs)
    case O.OpsCONST{}: mm.const(arg, d)
    case O.OpsPAD{}: mm.pad(srcs)
    case O.OpsRESHAPE{}: mm.lift.mv(srcs)
    case O.OpsEXPAND{}: mm.lift.mv(srcs)
    case O.OpsPERMUTE{}: mm.lift.mv(srcs)
    case O.OpsSHRINK{}: mm.lift.mv(srcs)
    case O.OpsFLIP{}: mm.lift.mv(srcs)
    case O.OpsINDEX{}: mm.lift.mv(srcs)
    case O.OpsSTAGE{}: mm.lift.mv(srcs)
    case O.OpsAFTER{}: mm.lift.mv(srcs)
    case O.OpsDETACH{}: mm.lift.mv(srcs)
    case O.OpsCOPY{}: mm.lift.mv(srcs)
    case O.OpsCONTIGUOUS_BACKWARD{}: mm.lift.mv(srcs)
    case _: mm.default(d)

def mm.lift(+op: O.Op, +srcs: List<&2, Bnd2>, arg: O.Arg, +d: S.Dt) -> Bnd2:
  mm.MM2.get(mm.lift.bin(mm.bin.enter(op, d), op, srcs, d), mm.lift.rest(op, srcs, arg, d))

# ===========================================================================
# THE GATE. `main` builds small arenas with `ops.bend`'s own `g_*` constructors and
# with the `UOp` sugar, folds each, and prints one line per claim. A `False{}`
# anywhere is the failure.
#
#   1. dtype_key   -- the same ucache NOTE, expressed in the fold: two CONSTs whose
#                     args are `True == 1` as dict keys still get different dtypes,
#                     and both are the dtype their Arg says.
#   2. shape_ok    -- `Add(Buffer, Const)` end to end: the BUFFER's shape is its
#                     `ParamArg.size`, the ADD's is `_broadcast_shape((4,), ())`,
#                     and the ADD's dtype is `least_upper_dtype(int32, weakint)`.
#   3. device_ok   -- the same three nodes' devices, and the addrspace disagreement
#                     that `one_addr` answers with None.
#   4. cycle_safe  -- a BACKEDGE over a SPECIAL and a RANGE is the range graph's
#                     shape; the fold must TERMINATE and settle every node, and
#                     the BACKEDGE must carry src[1:2] as its ended range.
#   5. gap_ok      -- a node whose rules are deferred (a RESHAPE) is NOT answered,
#                     and the fold still terminates and says so by leaving it out.
# ===========================================================================

# THE FOLDED ARENA AND ITS TABLE, as one `Data` value, for the same `Data` rule as
# `Sized` and `Srcs`: every claim below reads the table two or three times.
type Folded is Data:
  Folded{ar: O.Arena, tb: Table}

def Folded.ar(x: Folded) -> O.Arena:
  match x:
    case Folded{ar, t}: ar

def Folded.t(x: Folded) -> Table:
  match x:
    case Folded{ar, t}: t

# CONST(3) and CONST(True) in one arena: "a CONST's dtype is the type of its arg,
# and True == 1 as dict keys".
def g_keys() -> O.Found:
  +c3 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(3)})
  O.UOp.const(O.Found.ar(c3), O.CBool{True{}})

# `ParamArg(slot, dtype, size, ...)` for an int32 BUFFER of four elements on device
# tag 0. `dtype.bend` and helpers are not needed for a record literal.
def g_buf() -> O.ParamArg:
  O.ParamArg{0, S.int32(), Some{4}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

# BUFFER(int32, size=4) <- SPECIAL("4", 1) <- CONST(0), then ADD(buffer, CONST(3)).
# The ADD is over a `float` buffer and a `weakint` constant, so its dtype is
# `least_upper_dtype(int32, weakint) = int32` and its shape is `(4,)` by broadcast.
def g_add() -> O.Found:
  +z = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(0)})
  +s = O.UOp.special(O.Found.ar(z), O.Found.i(z), "4")
  +b = O.UOp.new(O.Found.ar(s), O.OpsBUFFER{}, [O.Found.i(s)], O.AParam{g_buf()}, O.TNone{})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(3)})
  O.UOp.alu(O.Found.ar(c), O.OpsADD{}, [O.Found.i(b), O.Found.i(c)])

# `shape_to_shape_arg((2, 2))` -- `UOp(Ops.STACK, src=(CONST(2), CONST(2)))`. The
# two CONSTs HASH-CONS to one node, so the arena is BUFFER, CONST(2), STACK,
# RESHAPE and nothing else -- which is also what CPython's ucache holds, and the
# oracle prints `same node as by-hand: True` for the hand-built and `_mop` nodes.
def g_marg22(ar: O.Arena) -> O.Found:
  +c0 = O.UOp.const(ar, O.CInt{H.i64_of_i32(2)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(2)})
  O.UOp.new(O.Found.ar(c1), O.OpsSTACK{}, [O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})

# `shape_to_shape_arg((2, 3))` -- the marg whose product 6 is not the src's 4
def g_marg23(ar: O.Arena) -> O.Found:
  +c0 = O.UOp.const(ar, O.CInt{H.i64_of_i32(2)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(3)})
  O.UOp.new(O.Found.ar(c1), O.OpsSTACK{}, [O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})

# RESHAPE(BUFFER(4), STACK(2, 2)) -- `Tensor.arange(4).reshape(2, 2)`, and the
# FIRST TWO-DIMENSIONAL SHAPE this repo can build. `_mop` builds it as
# `UOp(op, src=(self,)+UOp.sink(*usrcs).simplify().src)` (ops.py:835).
def g_resh22() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_buf()}, O.TNone{})
  +k = g_marg22(O.Found.ar(b))
  O.UOp.new(O.Found.ar(k), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})

# RESHAPE(BUFFER(4), STACK(2, 3)) -- `raise ValueError(f"bad reshape: {ps} ->
# {self.marg}")` (ops.py:412), which the oracle prints verbatim
def g_resh23() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_buf()}, O.TNone{})
  +k = g_marg23(O.Found.ar(b))
  O.UOp.new(O.Found.ar(k), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})

# RESHAPE(BUFFER(4), CONST(4)) -- the ONE-element marg, a bare CONST, and
# `movement.py:184`'s `return self if ret.shape == self.shape else ret`. The
# oracle prints `identity ret==self: True` for that test.
def g_resh4() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_buf()}, O.TNone{})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(4)})
  O.UOp.new(O.Found.ar(c), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

# RESHAPE(BUFFER(4), CONST(-2)) -- `raise ValueError(f"shape can't contain negative
# numbers {self.marg}")` (ops.py:410), which is a DIFFERENT check from the product
# one. -2 as a two's complement I64 is hi=all-ones and lo=2 below all-ones.
def g_reshneg() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_buf()}, O.TNone{})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_hi_lo(4294967295, 4294967294)})
  O.UOp.new(O.Found.ar(c), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

# RESHAPE(NOOP(BUFFER(4)), STACK(2, 3)) -- the "special (terrible) case for RESHAPE
# on NOOP" (ops.py:346), with a product that is WRONG on purpose: the `if` RETURNS
# before the movement ladder's two checks, so Python answers `(2, 3)` over a `(4,)`
# src, and the dtype is `void` because `GroupOp.Movement` says `return src[0].dtype`
# and a NOOP is in the `always void` set.
def g_reshnoop() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_buf()}, O.TNone{})
  +n = O.UOp.new(O.Found.ar(b), O.OpsNOOP{}, [O.Found.i(b)], O.ANone{}, O.TNone{})
  +k = g_marg23(O.Found.ar(n))
  O.UOp.new(O.Found.ar(k), O.OpsRESHAPE{}, [O.Found.i(n), O.Found.i(k)], O.ANone{}, O.TNone{})

# A RESHAPE over a SYMBOLIC marg -- `STACK(CONST(2), SPECIAL("N"))` -- which is the
# `s.val if s.op is Ops.CONST else ssimplify(s)` half of `as_shape`. The oracle
# prints `bad reshape: (4,) -> (2, UOp(Ops.SPECIAL...))`, so Python raises and the
# fold's `ssimplify` wall answers None too: the row is "NEITHER ANSWERS".
def g_reshsym() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_buf()}, O.TNone{})
  +z = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(0)})
  +n = O.UOp.special(O.Found.ar(z), O.Found.i(z), "N")
  +c = O.UOp.const(O.Found.ar(n), O.CInt{H.i64_of_i32(2)})
  +k = O.UOp.new(O.Found.ar(c), O.OpsSTACK{}, [O.Found.i(c), O.Found.i(n)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(k), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})

def dt_is.pick(m: Maybe<&2, S.Dt>, want: S.Dt) -> Bool:
  match m:
    case Some{d}: O.eq_dt(d, want)
    case None{}: False{}

def shape_is.of(m: Maybe<&2, List<&2, O.Sint>>, want: List<&2, O.Sint>) -> Bool:
  match m:
    case Some{ds}: eq_sints(ds, want)
    case None{}: False{}

def shape_is.go(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>, want: List<&2, O.Sint>) -> Bool:
  match m:
    case Some{sh}: shape_is.of(sh, want)
    case None{}: False{}

def dev_is.of(m: Maybe<&2, S.Dev>, tag: U32) -> Bool:
  match m:
    case Some{S.D1{t}}: U32.is_eq(t, tag)
    case _: False{}

def dev_is.pick(m: Maybe<&2, Maybe<&2, S.Dev>>, tag: U32) -> Bool:
  match m:
    case Some{d}: dev_is.of(d, tag)
    case None{}: False{}

def dev_is(m: Maybe<&2, Maybe<&2, S.Dev>>, tag: U32) -> Bool:
  dev_is.pick(m, tag)

def addr_is.of(got: Maybe<&2, S.Addr>, a: Maybe<&2, S.Addr>) -> Bool:
  match got a:
    case Some{p} Some{q}: O.eq_addr(p, q)
    case None{} None{}: True{}
    case _ _: False{}

def addr_is.pick(m: Maybe<&2, Maybe<&2, S.Addr>>, a: Maybe<&2, S.Addr>) -> Bool:
  match m:
    case Some{got}: addr_is.of(got, a)
    case None{}: False{}

def addr_is(m: Maybe<&2, Maybe<&2, S.Addr>>, a: Maybe<&2, S.Addr>) -> Bool:
  addr_is.pick(m, a)

def axis_is.go(m: Maybe<&2, O.AxisType>, a: O.AxisType) -> Bool:
  match m:
    case Some{t}: O.eq_axis(t, a)
    case None{}: False{}

def axis_at(+x: Folded, i: U32, a: O.AxisType) -> Bool:
  axis_is.go(UOp.axis_type(Folded.ar(x), i), a)

def gap_count.pick(hit: Bool) -> Bool:
  match hit:
    case True{}: False{}
    case False{}: True{}

# CONST(0) <- RESHAPE(ATuple[4]) <- STORE. The STORE's src[0] is the RESHAPE, so
# the deferral propagates to it and the table holds only the CONST.
def g_gap() -> O.Found:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(0)})
  +m = O.UOp.new(O.Found.ar(c), O.OpsRESHAPE{}, [O.Found.i(c)], O.ATuple{[4]}, O.TNone{})
  O.UOp.new(O.Found.ar(m), O.OpsSTORE{}, [O.Found.i(m)], O.ANone{}, O.TNone{})

# `_min_max`'s row is a STRING ANSWER and not a Bool, so `row` cannot print it and
# this is the second printer. Both are `IO(String.concat(...))` and nothing else.
def mm_row(nm: String, got: String) -> IO(Unit):
  IO.print(String.concat(["mm_", nm, " ", got]))

# `bit_length`'s rows print under `bl_` rather than `mm_`, because the oracle's two
# tables are two KINDS of answer -- a COUNT and a masked INTEGER -- and one prefix for
# both would hide which of the two a mutation moved.
def bl_row(nm: String, got: String) -> IO(Unit):
  IO.print(String.concat(["bl_", nm, " ", got]))

# The dtype limits print as a PAIR on one line, so a transposed `min`/`max` and a dropped
# sign are both visible in the same string. Two separate rows would let a swap hide in
# either; one row cannot.
# ===========================================================================
# THE `_min_max` OP-TABLE ROWS. `.agents/slop/mm-lift-gate.py` GENERATES BOTH THE
# FIXTURES AND THESE 123 LINES -- and it generates them from a fixture LIST, so there is
# one copy of the inputs and not a transcription anywhere. Every src in a fixture is a
# `CONST`, so the table is handed a `List<&2, Bnd2>` it did not have to compute: that is
# what makes the TABLE gateable before the WALK exists, which is why the two are separate
# work in this order.
#
# `sat_*` IS A SECOND CLASS OF ROW. CPython's ints are unbounded, so `2**63 + 2**63` is
# `2**64` there and `PInf` here; those four rows print CPython's real pair in brackets, so
# the divergence is IN the row. Same treatment `mv_expsym` gets, and the point is that a
# saturation is a designed answer rather than a wrong one.
# ===========================================================================

def lf_row(nm: String, b: Bnd2) -> IO(Unit):
  IO.print(String.concat(["lf_", nm, " ", bnd2_show(b)]))

# THE SRC LIST BUILDERS, and they exist because a `List<Bnd2>` is the table's input type
# and a row cannot spell one. `lf_c2`/`lf_c3` take the already-`Bnd`-converted value, so
# the integer-to-bound conversion is ONCE per fixture rather than once per read.
def lf_c0() -> List<&2, Bnd2>: Nil{}

def lf_c1(+a: Bnd) -> List<&2, Bnd2>: [Bnd2{a, a}]

def lf_c2(+a: Bnd, +b: Bnd) -> List<&2, Bnd2>: [Bnd2{a, a}, Bnd2{b, b}]

def lf_c3(+a: Bnd, +b: Bnd, +c: Bnd) -> List<&2, Bnd2>: [Bnd2{a, a}, Bnd2{b, b}, Bnd2{c, c}]

# A STACK's SRCS ARE NOT ALL THE SAME VALUE, and it is the one family that needs more than
# two, so `lf_c4` is a fourth arity rather than a fold: a fold would put a `Bnd2` builder
# in a closure's TYPE, where the `+` cannot be spelled (the recorded closure-shared-arg
# wall), for a list of at most four elements. Four arities is less code than the wall.
def lf_c4(+a: Bnd, +b: Bnd, +c: Bnd, +d: Bnd) -> List<&2, Bnd2>:
  [Bnd2{a, a}, Bnd2{b, b}, Bnd2{c, c}, Bnd2{d, d}]

# A PARAM's `vmin_vmax`, and the field is a `Maybe<&2, PyRange>` of a SIGNED pair, which is
# the only place `Bnd`'s sign/magnitude split is read back the other way.
def lf_pa(lo: H.I64, hi: H.I64) -> O.Arg:
  O.AParam{O.ParamArg{0, S.int32(), None{}, Some{O.PyRange{lo, hi}}, None{}, None{}, S.AGlobal{}, None{},
    False{}, None{}, None{}, False{}, None{}}}

def dt_row(nm: String, lo: Bnd, hi: Bnd) -> IO(Unit):
  IO.print(String.concat(["bl_dt_", nm, " lo=", bnd_show(lo), " hi=", bnd_show(hi)]))

def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

# ONE DECREMENT PER OCCURRENCE, one turn each. `c` is a `Nat` because the descent
# check needs the SMALLER COUNT AS A BINDER, and `1n+p` is the only pattern that
# hands one out.
def Kahn.consumers.times(c: Nat, +v: U32, +k: Kahn) -> Kahn:
  match c:
    case 0n: k
    case 1n+p: Kahn.consumers.times(p, v, Kahn.consumers.dec(v, k))

# the node under examination, lowered once per edge into it
def Kahn.consumers.step(nd: O.Node, +u: U32, +v: U32, +k: Kahn) -> Kahn:
  Kahn.consumers.times(U32.to_nat(Kahn.src_count(nd, u)), v, k)

# ONE self-call, so the edge count is a MATCH ARM rather than a second def
def Kahn.consumers.go(ns: List<&2, O.Node>, +u: U32, +v: U32, +k: Kahn) -> Kahn:
  match ns:
    case Nil{}: k
    case +nd <> t: Kahn.consumers.go(t, u, U32.add(v, 1), Kahn.consumers.step(nd, u, v, k))

# THE EDGES OUT OF THE NODE JUST ANSWERED, which is what Kahn's algorithm actually
# decrements, and which a forward arena does not store: `Kahn.consumers` is the walk
# that finds the nodes naming `u` as a src. One O(n) pass over the node list per
# answered node, the price of not building a transpose. `v` is the position in that
# list, which is the node's index, because `Kahn.seed.pend` counts down the same
# list.
def Kahn.consumers(+ar: O.Arena, +u: U32, +k: Kahn) -> Kahn:
  Kahn.consumers.go(O.Arena.nodes(ar), u, 0, k)

# the node the fold CANNOT answer is not in the table, and it propagates nothing:
# its consumers will find it unresolved
def Kahn.ans.of(r: Maybe<&2, Derived>, ar: O.Arena, +i: U32, rest: List<&2, U32>, pend: List<&2, U32>, tb: Table) -> Kahn:
  match r:
    case Some{d}: Kahn.consumers(ar, i, Kahn{pend, rest, Table.put(tb, Resolved{i, d})})
    case None{}: Kahn{pend, rest, tb}

def Kahn.ans(+ar: O.Arena, +i: U32, rest: List<&2, U32>, pend: List<&2, U32>, tb: Table, ss: List<&2, Derived>) -> Kahn:
  Kahn.ans.of(derived(ar, i, O.Arena.node(ar, i), ss), ar, i, rest, pend, tb)

# a src the fold has not answered leaves the node unanswerable
def Kahn.go.of(gs: Maybe<&2, List<&2, Derived>>, ar: O.Arena, i: U32, rest: List<&2, U32>, pend: List<&2, U32>, tb: Table) -> Kahn:
  match gs:
    case Some{ss}: Kahn.ans(ar, i, rest, pend, tb, ss)
    case None{}: Kahn{pend, rest, tb}

def Kahn.get.go(+i: U32, es: List<&2, Resolved>, acc: Maybe<&2, Derived>) -> Maybe<&2, Derived>:
  match es:
    case Nil{}: acc
    case r <> t: Kahn.get.go(i, t, Kahn.get.step(i, r, acc))

# THE TABLE LOOKUP, which is an O(n) SEARCH because the table is a `List` AND is in
# RESOLUTION order rather than index order -- so `List.get(out, i)` would read the
# wrong entry, and this walk is what replaces it.
def Kahn.get(i: U32, tb: Table) -> Maybe<&2, Derived>:
  Kahn.get.go(i, Table.es(tb), None{})

# the RESHAPE is NOT in the table, and neither is the STORE over it
def gap_count(+x: Folded, i: U32) -> Bool:
  gap_count.pick(Maybe.is_some(&2, Derived, Kahn.get(i, Folded.t(x))))

def fold.ended(ar: O.Arena, tb: Table, i: U32) -> Maybe<&2, List<&2, U32>>:
  fold.ended.of(Kahn.get(i, tb))

# `ended_ranges` on a BACKEDGE is `src[1:2]`, so the one range it holds is `src[1]`
# and NOT `src[0]`, and here the two are the SPECIAL and the RANGE
def ended_is.go(m: Maybe<&2, List<&2, U32>>, want: U32) -> Bool:
  match m:
    case Some{w <> Nil{}}: U32.is_eq(w, want)
    case _: False{}

def ended_is(+x: Folded, i: U32, want: U32) -> Bool:
  ended_is.go(fold.ended(Folded.ar(x), Folded.t(x), i), want)

# `UOp.ended_ranges` -- ops.py:470
def UOp.ended_ranges(ar: O.Arena, tb: Table, i: U32) -> Maybe<&2, List<&2, U32>>:
  fold.ended(ar, tb, i)

def fold.base(ar: O.Arena, tb: Table, i: U32) -> Maybe<&1, U32>:
  fold.base.of(Kahn.get(i, tb))

# `UOp.base` -- ops.py:785. The fold carries the index, so this is a table read.
def UOp.base(ar: O.Arena, tb: Table, i: U32) -> Maybe<&1, U32>:
  fold.base(ar, tb, i)

def fold.addr(ar: O.Arena, tb: Table, i: U32) -> Maybe<&2, Maybe<&2, S.Addr>>:
  fold.addr.of(Kahn.get(i, tb))

def UOp.addrspace(ar: O.Arena, tb: Table, i: U32) -> Maybe<&2, Maybe<&2, S.Addr>>:
  fold.addr(ar, tb, i)

def fold.device(ar: O.Arena, tb: Table, i: U32) -> Maybe<&2, Maybe<&2, S.Dev>>:
  fold.device.of(Kahn.get(i, tb))

def UOp.device(ar: O.Arena, tb: Table, i: U32) -> Maybe<&2, Maybe<&2, S.Dev>>:
  fold.device(ar, tb, i)

def fold.shape(ar: O.Arena, tb: Table, i: U32) -> Maybe<&2, Maybe<&2, List<&2, O.Sint>>>:
  fold.shape.of(Kahn.get(i, tb))

def UOp.shape(ar: O.Arena, tb: Table, i: U32) -> Maybe<&2, Maybe<&2, List<&2, O.Sint>>>:
  fold.shape(ar, tb, i)

def fold.dt(ar: O.Arena, tb: Table, i: U32) -> Maybe<&2, S.Dt>:
  fold.dt.of(Kahn.get(i, tb))

def dt_is(+x: Folded, i: U32, want: S.Dt) -> Bool:
  dt_is.pick(fold.dt(Folded.ar(x), Folded.t(x), i), want)

# ===========================================================================
# THE READERS. `UOp.dtype(ar, t, i)` and the rest: a table read, so each is a
# `Maybe` from an index. There is no `UOp.dtype(ar, i)` here, and there cannot be
# one: answering a single node IS the fold, because the fold is what makes the
# answer well-founded. ops.py spells that `recursive_property` (ops.py:218).
# ===========================================================================

def UOp.dtype(ar: O.Arena, tb: Table, i: U32) -> Maybe<&2, S.Dt>:
  fold.dt(ar, tb, i)

# `self.src`, read back out of the RESOLVED TABLE by index. A src the fold has not
# answered makes the consumer unanswerable, which is the same one-directional rule
# as the worklist itself. "has every src been answered" is a THREADED `ok` and not an
# early `None{}`, because an early return from the middle of a self-call would need a
# def that returns to the self-call, and that is mutual recursion. The accumulator
# and the flag travel as one `Gathered` because both need the same `Kahn.get`.
def Kahn.gather.step(hit: Maybe<&2, Derived>, +g: Gathered) -> Gathered:
  match hit:
    case Some{d}: Gathered{List.append(&2, Derived, Gathered.acc(g), [d]), Gathered.ok(g)}
    case None{}: Gathered{Gathered.acc(g), False{}}

def Kahn.gather.go(srcs: List<&2, U32>, +tb: Table, +g: Gathered) -> Maybe<&2, List<&2, Derived>>:
  match srcs:
    case Nil{}: Kahn.gather.done(Gathered.acc(g), Gathered.ok(g))
    case s <> t: Kahn.gather.go(t, tb, Kahn.gather.step(Kahn.get(s, tb), g))

def Kahn.gather(ar: O.Arena, i: U32, tb: Table) -> Maybe<&2, List<&2, Derived>>:
  Kahn.gather.go(O.Arena.srcs(ar, i), tb, Gathered{Nil{}, True{}})

def shape_is(+x: Folded, i: U32, want: List<&2, O.Sint>) -> Bool:
  shape_is.go(fold.shape(Folded.ar(x), Folded.t(x), i), want)

def Kahn.go(+ar: O.Arena, +i: U32, rest: List<&2, U32>, pend: List<&2, U32>, +tb: Table) -> Kahn:
  Kahn.go.of(Kahn.gather(ar, i, tb), ar, i, rest, pend, tb)

# `if i in out: continue` -- a node is queued once per edge into it, so the queue
# holds duplicates, and the resolved table is the visited set
def Kahn.pop.of(ar: O.Arena, hit: Maybe<&2, Derived>, i: U32, rest: List<&2, U32>, pend: List<&2, U32>, tb: Table) -> Kahn:
  match hit:
    case Some{d}: Kahn{pend, rest, tb}
    case None{}: Kahn.go(ar, i, rest, pend, tb)

def Kahn.pop(ar: O.Arena, +i: U32, rest: List<&2, U32>, pend: List<&2, U32>, +tb: Table) -> Kahn:
  Kahn.pop.of(ar, Kahn.get(i, tb), i, rest, pend, tb)

# ONE TURN. `i in out` is the visited test; otherwise the node's srcs' pairs are
# gathered, the node is answered, it enters the table, and each of its srcs' counts
# drops by one.
def Kahn.step(ar: O.Arena, k: Kahn) -> Kahn:
  match k:
    case Kahn{pend, work, out}:
      match work:
        case Nil{}: k
        case i <> rest: Kahn.pop(ar, i, rest, pend, out)

# THE WHILE LOOP, as a fuel countdown. The worklist drains because it is finite
# and every pop removes one entry; the budget is the exact bound above.
def Kahn.run(fuel: Nat, +ar: O.Arena, k: Kahn) -> Table:
  match fuel:
    case 0n: Kahn.out_of(k)
    case 1n+p: Kahn.run(p, ar, Kahn.step(ar, k))

# `UOp.fold(ar)` -- the whole arena, once. A caller builds its arena, folds it, and
# reads with the `UOp.*` readers below. The table is complete exactly when
# `Kahn.settled` is True, and the only way it is not is a rule this file defers:
# see the header on why a cycle cannot make it incomplete.
def UOp.fold(+ar: O.Arena) -> Table:
  Kahn.run(Kahn.budget(ar), ar, Kahn.seed(ar))

def folded(+ar: O.Arena) -> Folded:
  Folded{ar, UOp.fold(ar)}

# ===========================================================================
# THE MOVEMENT FIXTURES AND ROWS: `dt_shape`'s arms for ops.py:414-431's five
# deferred movement ops. Every `g_mv*` is built node for node against
# `.agents/slop/oracles/fold-mvt-oracle.py`, and every row prints the FOUR FACTS
# PLUS THE ANSWER as ONE STRING.
#
# WHY ONE STRING. Four separate rows let a fixture drop one of them, and a PAD or
# SHRINK built with its two shape args SWAPPED leaves the root op, the src count
# and the node count right: that mutation moved exactly TWO of seventy rows in
# `mixin/movement.bend` and only because two rows happened to notice an identity
# test. `n= op= nsrc= srcops=` is the spelling that closes it.
# ===========================================================================

# `ParamArg(slot=0, int32, size=size)` -- `g_buf` spells the size-4 one, and this
# is the same record at an arbitrary size so the 2-D fixtures have a source.
def g_mv_pa(size: U32) -> O.ParamArg:
  O.ParamArg{0, S.int32(), Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

# `shape_to_shape_arg((2, 3))` at a given base arena. The two CONSTs HASH-CONS onto
# whatever the arena already holds, which is what makes the node counts comparable
# with CPython's `toposort()` length rather than with a count of what was built.
def g_mv_st23(ar: O.Arena) -> O.Found:
  +c0 = O.UOp.const(ar, O.CInt{H.i64_of_i32(2)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(3)})
  O.UOp.new(O.Found.ar(c1), O.OpsSTACK{}, [O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})

# RESHAPE(BUFFER(12), STACK(2, 3)), taking the BUFFER's `O.Found` so both indices are
# read from one value -- the "intern once, read twice" rule, and `g_mv_r23`'s reuse.
def g_mv_r23_of(+b: O.Found) -> O.Found:
  +k = g_mv_st23(O.Found.ar(b))
  O.UOp.new(O.Found.ar(k), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})


# RESHAPE(BUFFER(6), STACK(2, 3)) -- shape (2, 3), the PERMUTE and FLIP src. SIX and
# not twelve: the RESHAPE's own product check is `prod(ps) != prod(marg)`, so the
# buffer must hold 2*3 elements. MEASURED, not assumed -- a size-12 buffer answers
# `bad reshape: (12,) -> (2, 3)` in CPython and is refused here, and the first
# version of `g_mv_pad23` had that bug and read ABSENT until it was fixed.
def g_mv_r23() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_mv_pa(6)}, O.TNone{})
  g_mv_r23_of(b)

# EXPAND(BUFFER(4), CONST(2)) -- `n=3 op=EXPAND nsrc=2 srcops=BUFFER|CONST
# shape=(2,4) dtype=int`. `_mop` collapses a ONE-ELEMENT shape arg to a bare CONST
# (`shape_to_shape_arg` returns `src[0]` for a 1-tuple, ops.py:110), which is what
# makes this fixture the `marg.one` arm rather than the `marg.stack` one.
def g_mv_exp1() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_mv_pa(4)}, O.TNone{})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(2)})
  O.UOp.new(O.Found.ar(c), O.OpsEXPAND{}, [O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

# EXPAND(BUFFER(4), STACK(2, 3)) -- `shape=(2,3,4)`, the two-element marg and the
# `marg.stack.go` arm.
def g_mv_exp23() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_mv_pa(4)}, O.TNone{})
  +k = g_mv_st23(O.Found.ar(b))
  O.UOp.new(O.Found.ar(k), O.OpsEXPAND{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})

# EXPAND(NOOP(BUFFER(4)), CONST(2)) -- `shape=(2,4) dtype=void`. The dtype row: the
# shape arm reads `ps` (through the NOOP, ops.py:441's `return self.src[0]._shape`)
# while the dtype is `GroupOp.Movement`'s `return src[0].dtype` and a NOOP is in the
# `always void` set, so the two halves come from DIFFERENT nodes. It is the row that
# says a movement's dtype is not "always void" -- `t_resh_noop` already says it for
# RESHAPE and this says it for EXPAND.
def g_mv_expnoop() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_mv_pa(4)}, O.TNone{})
  +n = O.UOp.new(O.Found.ar(b), O.OpsNOOP{}, [O.Found.i(b)], O.ANone{}, O.TNone{})
  +c = O.UOp.const(O.Found.ar(n), O.CInt{H.i64_of_i32(2)})
  O.UOp.new(O.Found.ar(c), O.OpsEXPAND{}, [O.Found.i(n), O.Found.i(c)], O.ANone{}, O.TNone{})

# EXPAND(BUFFER(4), STACK(2, SPECIAL "N")) -- THE `ssimplify` WALL, one level below
# `marg`: `s.val if s.op is Ops.CONST else ssimplify(s)` meets a src that is not a
# CONST. CPython ANSWERS a shape with a UOp in it (`(2,UOp(Ops.SPECIAL...),4)`); the
# fold refuses, because `marg.of`'s third arm is None and a fold that cannot say "I
# do not know" is not a fold. The row prints `RAISE` and the oracle prints CPython's
# real answer beside it -- see the DIVERGES block in the oracle.
def g_mv_expsym() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_mv_pa(4)}, O.TNone{})
  +z = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(0)})
  +n = O.UOp.special(O.Found.ar(z), O.Found.i(z), "N")
  +c = O.UOp.const(O.Found.ar(n), O.CInt{H.i64_of_i32(2)})
  +k = O.UOp.new(O.Found.ar(c), O.OpsSTACK{}, [O.Found.i(c), O.Found.i(n)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(k), O.OpsEXPAND{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})

# `shape_to_shape_arg` of a ONE-element tuple, which returns `src[0]` (ops.py:110) --
# so a one-dim pad's two shape args are BARE CONSTs and the node is 4 not 5. This is
# the single most common way a PAD fixture is built wrong, and it is the fixture that
# catches it: `mv_pad1` reads `srcops=BUFFER|CONST|CONST` and a STACK there would be
# the wrong graph.
def g_mv_cst(ar: O.Arena, n: U32) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(n)})

# `shape_to_shape_arg` of a TWO-element tuple whose values are NOT the (2, 3) above.
# A fixture that reuses `g_mv_st23` for the offsets builds a graph with FOUR nodes
# where CPython has eight, and the node-count row is what catches it -- measured:
# `mv_pad23` printed `n=6` against CPython's `n=12` until the offsets got their own
# CONSTs. `g_mv_st23` is right for the RESHAPE and wrong for both pad args.
def g_mv_st01(ar: O.Arena) -> O.Found:
  +c0 = O.UOp.const(ar, O.CInt{H.i64_of_i32(0)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(1)})
  O.UOp.new(O.Found.ar(c1), O.OpsSTACK{}, [O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})

def g_mv_st65(ar: O.Arena) -> O.Found:
  +c0 = O.UOp.const(ar, O.CInt{H.i64_of_i32(6)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(5)})
  O.UOp.new(O.Found.ar(c1), O.OpsSTACK{}, [O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})


def g_mv_st21(ar: O.Arena) -> O.Found:
  +c0 = O.UOp.const(ar, O.CInt{H.i64_of_i32(2)})
  +c1 = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(1)})
  O.UOp.new(O.Found.ar(c1), O.OpsSTACK{}, [O.Found.i(c0), O.Found.i(c1)], O.ANone{}, O.TNone{})

# SHRINK over the same (2, 3) source with offsets (0,1) and sizes (2,1) --
# `shape=(2,1)`, `n=10`. The sums are `0+2<=2` and `1+1<=3`, which is SHRINK's
# `o+sz<=s` and NOT PAD's `o+s<=sz`: the first would read `0+2<=2` too, and the second
# reads `1+1<=3` against PAD's order `1+3<=1` which fails. So this row is the one
# that tells the two arms apart on a dim where the operands are not interchangeable.
def g_mv_shr23() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_mv_pa(6)}, O.TNone{})
  +r = g_mv_r23_of(b)
  +o = g_mv_st01(O.Found.ar(r))
  +z = g_mv_st21(O.Found.ar(o))
  O.UOp.new(O.Found.ar(z), O.OpsSHRINK{}, [O.Found.i(r), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# PAD(BUFFER(4), CONST(0), CONST(6)) -- `n=4 op=Ops.PAD nsrc=3
# srcops=Ops.BUFFER|Ops.CONST|Ops.CONST shape=(6) dtype=int`. Offsets 0 and size 6
# over a source dim of 4: `o + s <= sz` is `0+4 <= 6`, and the answer is the SIZE.
def g_mv_pad1() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_mv_pa(4)}, O.TNone{})
  +o = g_mv_cst(O.Found.ar(b), 0)
  +z = g_mv_cst(O.Found.ar(o), 6)
  O.UOp.new(O.Found.ar(z), O.OpsPAD{}, [O.Found.i(b), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# SHRINK(BUFFER(4), CONST(1), CONST(2)) -- `shape=(2)`: `o + sz <= s` is `1+2 <= 4`.
def g_mv_shr1() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_mv_pa(4)}, O.TNone{})
  +o = g_mv_cst(O.Found.ar(b), 1)
  +z = g_mv_cst(O.Found.ar(o), 2)
  O.UOp.new(O.Found.ar(z), O.OpsSHRINK{}, [O.Found.i(b), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# PAD with offsets (0,1) and sizes (6,5) over the (2,3) RESHAPE -- `shape=(6,5)`.
# TWO dims is the row that matters: a one-dim fixture cannot tell `o+s<=sz` from
# `o+sz<=s`, because with one dim the two sums put the same pair on the same side.
def g_mv_pad23() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_mv_pa(6)}, O.TNone{})
  +r = g_mv_r23_of(b)
  +o = g_mv_st01(O.Found.ar(r))
  +z = g_mv_st65(O.Found.ar(o))
  O.UOp.new(O.Found.ar(z), O.OpsPAD{}, [O.Found.i(r), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})


# PAD whose marg is LONGER than ps -- `len(ps) != len(self.marg)`, ops.py:421's first
# disjunct, and the ValueError is `invalid pad ((0, 6), (1, 5)) for (4,)`.
def g_mv_padr() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_mv_pa(4)}, O.TNone{})
  +o = g_mv_st01(O.Found.ar(b))
  +z = g_mv_st65(O.Found.ar(o))
  O.UOp.new(O.Found.ar(z), O.OpsPAD{}, [O.Found.i(b), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# PAD whose sum fails on ONE dim -- offset 1, size 3 over a source dim of 4:
# `o + s <= sz` is `1+4 <= 3`, which is ops.py's `invalid pad ((1, 3),) for (4,)`.
def g_mv_padr2() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_mv_pa(4)}, O.TNone{})
  +o = g_mv_cst(O.Found.ar(b), 1)
  +z = g_mv_cst(O.Found.ar(o), 3)
  O.UOp.new(O.Found.ar(z), O.OpsPAD{}, [O.Found.i(b), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# SHRINK whose sum fails -- offset 1, size 4 over a source dim of 4: `o+sz<=s` is
# `1+4<=4`, which is ops.py's `invalid shrink ((1, 4),) for (4,)`. This is the ONLY
# row that tells PAD's sum from SHRINK's: `g_mv_padr2` is rejected by both, so a port
# that had the two arms swapped would pass every other row.
def g_mv_shrbad() -> O.Found:
  +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{g_mv_pa(4)}, O.TNone{})
  +o = g_mv_cst(O.Found.ar(b), 1)
  +z = g_mv_cst(O.Found.ar(o), 4)
  O.UOp.new(O.Found.ar(z), O.OpsSHRINK{}, [O.Found.i(b), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# PERMUTE(RESHAPE(6), (1, 0)) -- `n=6 op=Ops.PERMUTE nsrc=1 srcops=Ops.RESHAPE
# shape=(3,2) dtype=int`. `marg` is `self.arg`, the arena's `ATuple`, so the node has
# ONE src and the arg is not a src at all -- which is the fourth fact's whole job.
def g_mv_perm(ys: List<&2, U32>) -> O.Found:
  +r = g_mv_r23()
  O.UOp.new(O.Found.ar(r), O.OpsPERMUTE{}, [O.Found.i(r)], O.ATuple{ys}, O.TNone{})

def g_mv_perm10() -> O.Found: g_mv_perm([1, 0])

# PERMUTE with a REPEATED index -- `sorted((0, 0)) != list(range(2))`, ops.py:417.
# A permutation test that only checked "every index in range" would pass this, and
# this is the row that says so.
def g_mv_permrep() -> O.Found: g_mv_perm([0, 0])

# PERMUTE with a LONGER arg than the shape -- `sorted((1, 0, 2)) != range(2)`. This
# is the row that says the LENGTH is part of the test, which is the half of
# `sorted(marg) == list(range(n))` that a bound-only test would miss.
def g_mv_permlen() -> O.Found: g_mv_perm([1, 0, 2])

# FLIP(RESHAPE(6), (1, 0)) -- `shape=(2,3)` UNCHANGED, `n=6 nsrc=1`. The shape is the
# src's, verbatim, which is what ops.py:431's `return ps` says; the row exists so a
# port that accidentally PERMUTED it would move.
def g_mv_flip(ys: List<&2, U32>) -> O.Found:
  +r = g_mv_r23()
  O.UOp.new(O.Found.ar(r), O.OpsFLIP{}, [O.Found.i(r)], O.ATuple{ys}, O.TNone{})

def g_mv_flip10() -> O.Found: g_mv_flip([1, 0])

# FLIP whose arg is SHORTER than the shape -- `len(ps) != len(self.marg)`,
# `bad flip on (4, 3), (True,)`. The length check is the reachable half of that
# `if`; see `flip_ds`'s header for why the `isinstance(x, bool)` half is not here.
def g_mv_fliplen() -> O.Found: g_mv_flip([1])

# ---------------------------------------------------------------------------
# THE PRINTER. `n=` is the `toposort` LENGTH, which is what CPython's oracle counts,
# so the two arenas are compared on the same measure rather than on `Arena.next`.
# ---------------------------------------------------------------------------

def sig_srcops.go(+ar: O.Arena, +ss: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> t: sig_srcops.go(ar, t, List.append(&2, String, acc, [O.Ops.name(O.Arena.op(ar, s))]))

def sig_srcops(+ar: O.Arena, +ss: List<&2, U32>) -> List<&2, String>:
  sig_srcops.go(ar, ss, Nil{})

def sig_count(+ar: O.Arena, +u: U32) -> U32:
  U32.from_nat(List.length(&2, U32, O.UOp.toposort(O.Arena.budget(ar), ar, u)))

# `n=<count> op=<root> nsrc=<n> srcops=<seq>` -- `mxm_sig`'s spelling, reused here
# because the two files' gates are compared against the same oracle shape.
def sig4(+ar: O.Arena, +u: U32) -> String:
  String.concat(["n=", U32.show(sig_count(ar, u)),
                  " op=", O.Ops.name(O.Arena.op(ar, u)),
                  " nsrc=", U32.show(O.Arena.nsrc(ar, u)),
                  " srcops=", String.join(sig_srcops(ar, O.Arena.srcs(ar, u)), "|")])

# A DIM AS CPython PRINTS IT. `H.i64_text` is `hi:lo` on purpose (helpers.bend:1227)
# and a dim is a non-negative count under 2^31 -- `sint_of`'s own note says so -- so
# the LOW WORD is the decimal. `lo32` and not a reader of the whole I64, because a
# dim is exactly the case where the high word is zero.
# A UOp dim renders as a bare `UOp`, with NO index: CPython's arena is numbered
# differently and the fold refuses every row that could print one, so a digit here
# would be a number neither oracle nor port means the same thing by.
def dim_str(d: O.Sint) -> String:
  match d:
    case O.SU{u}: "UOp"
    case O.SI{i}: U32.show(H.lo32(i))

def dims_str.go(ds: List<&2, O.Sint>, acc: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}: acc
    case d <> t: dims_str.go(t, List.append(&2, String, acc, [dim_str(d)]))

def dims_str(ds: List<&2, O.Sint>) -> String:
  String.concat(["(", String.join(dims_str.go(ds, Nil{}), ","), ")"])

# "no entry in the table" is `ABSENT` and "the entry is there and has no shape" is
# `RAISE` -- this file's own two-`None` distinction from the header. NEITHER is
# Python's `raise`: a `raise` and a REFUSAL are the same statement in this file's
# convention, so a diff against CPython cannot tell them apart. The one row where
# they genuinely differ is `mv_expsym` -- CPython answers a shape holding a UOp and
# the fold cannot read that UOp's value -- and it says so in its own name and in the
# oracle's DIVERGES block, rather than being smoothed into an agreeing row.
def shape_str.go(m: Maybe<&2, List<&2, O.Sint>>) -> String:
  match m:
    case Some{ds}: dims_str(ds)
    case None{}  : "RAISE"

def shape_str(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  match m:
    case Some{g}: shape_str.go(g)
    case None{}  : "ABSENT"

# `S.Dt`'s FOURTH FIELD is tinygrad's own `DType.name`; `spec.bend` has no reader for
# it and that file is not this unit's to edit, so it is read here.
def dt_nm(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

def dt_str(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: dt_nm(d)
    case None{}  : "ABSENT"

# ONE FOLD PER ROW, read twice: `+x` and `+u` are what pay for it, and folding twice
# would be two walks of the whole arena for one answer.
def mv_row(nm: String, +x: Folded, +u: U32) -> IO(Unit):
  IO.print(String.concat(["mv_", nm, " ", sig4(Folded.ar(x), u),
                          " shape=", shape_str(UOp.shape(Folded.ar(x), Folded.t(x), u)),
                          " dtype=", dt_str(UOp.dtype(Folded.ar(x), Folded.t(x), u))]))

def mv_of(nm: String, +f: O.Found) -> IO(Unit):
  mv_row(nm, folded(O.Found.ar(f)), O.Found.i(f))

# the ucache NOTE, read out of the fold: CONST(3) is weakint and CONST(True) is
# bool, and they are TWO nodes -- `True == 1` as dict keys, so the key has to
# separate them and the fold has to agree about which is which.
def t_dtype_key() -> Bool:
  +x = folded(O.Found.ar(g_keys()))
  # 0 bottom, 1 CONST(3), 2 CONST(True)
  Bool.and(Bool.and(dt_is(x, 1, S.weakint()), dt_is(x, 2, S.boolean())),
    U32.is_eq(O.Found.i(g_keys()), 2))

# `Add(Buffer, Const)` end to end. The dtype claim is the interesting one: the
# BUFFER is int32 and the CONST is weakint, so the ADD's dtype is
# `least_upper_dtype(int32, weakint)` and NOT the first src's.
def t_shape_ok() -> Bool:
  +x = folded(O.Found.ar(g_add()))
  # 1 CONST(0) (), 2 SPECIAL (), 3 BUFFER (4,), 4 CONST(3) (), 5 ADD (4,)
  Bool.and(Bool.and(shape_is(x, 5, [sint_of(4)]), shape_is(x, 3, [sint_of(4)])),
    Bool.and(shape_is(x, 4, Nil{}), dt_is(x, 5, S.int32())))

# the BUFFER's device and addrspace come from its ParamArg, the ADD's from "the
# first src with a device", and the ADD's addrspace is None because GLOBAL and ALU
# disagree -- which is what `one_addr`'s `not all_same(ad)` arm says.
def t_device_ok() -> Bool:
  +x = folded(O.Found.ar(g_add()))
  Bool.and(Bool.and(Bool.and(dev_is(UOp.device(Folded.ar(x), Folded.t(x), 3), 0), dev_is(UOp.device(Folded.ar(x), Folded.t(x), 5), 0)),
    addr_is(UOp.addrspace(Folded.ar(x), Folded.t(x), 3), Some{S.AGlobal{}})),
    addr_is(UOp.addrspace(Folded.ar(x), Folded.t(x), 5), None{}))

# THE CYCLE. `g_cycle` in ops.bend is a BACKEDGE over a SPECIAL and a RANGE, which is
# the range graph's shape: the back-edge is a MARKER, so the arena is still a DAG and
# the fold must settle every node.
def t_cycle_safe() -> Bool:
  +f = O.g_cycle()
  +x = folded(O.Found.ar(f))
  +be = O.Found.i(f)
  +r = O.Arena.src(Folded.ar(x), be, 1)
  Bool.and(Bool.and(Kahn.settled(Folded.ar(x), Folded.t(x)), dt_is(x, be, S.void())),
    Bool.and(ended_is(x, be, r), axis_at(x, r, O.AXIS_DEVICE{})))

# THE DEFERRED ARM, which is the other way the fold is incomplete. A RESHAPE needs
# `marg` and `marg` needs `ssimplify`, so the fold does not answer it, and its
# consumer STORE is unanswered too: the incompleteness propagates along the graph.
def t_gap_ok() -> Bool:
  +x = folded(O.Found.ar(g_gap()))
  # 1 CONST(0), 2 RESHAPE (deferred), 3 STORE over it (unanswered in turn)
  Bool.and(Bool.not(Kahn.settled(Folded.ar(x), Folded.t(x))), gap_count(x, 2))

# THE 2-D FIXTURE end to end. `g_resh22`'s arena is 1 BUFFER, 2 CONST(2),
# 3 STACK(2,2), 4 RESHAPE, and Python's `_shape` is `(2, 2)` over `int32` -- the
# dtype is `GroupOp.Movement`'s `return src[0].dtype` and NOT `void`, because
# src[0] is a BUFFER here and a NOOP in `resh_noop`.
def t_resh_2d() -> Bool:
  +x = folded(O.Found.ar(g_resh22()))
  Bool.and(shape_is(x, 4, [sint_of(2), sint_of(2)]),
    Bool.and(dt_is(x, 4, S.int32()), shape_is(x, 1, [sint_of(4)])))

# THE IDENTITY TEST of movement.py:184, `return self if ret.shape == self.shape
# else ret`, from one fold: the ONE-element reshape is the no-op (4,) == (4,) and
# `resh_2d` is the (2,2) != (4,) half of the same `if`.
def t_resh_1d() -> Bool:
  +x = folded(O.Found.ar(g_resh4()))
  # 1 BUFFER, 2 CONST(4), 3 RESHAPE
  Bool.and(shape_is(x, 3, [sint_of(4)]), shape_is(x, 1, [sint_of(4)]))

# THE NOOP ARM, the one that must NOT check: `STACK(2, 3)` over a NOOP whose shape
# is (4,), so the products are 6 and 4, and `resh_reject` proves the SAME node is
# rejected when the src is a BUFFER. Python answers (2, 3) and `void`.
def t_resh_noop() -> Bool:
  +x = folded(O.Found.ar(g_reshnoop()))
  # 1 BUFFER, 2 NOOP, 3 CONST(2), 4 CONST(3), 5 STACK(2,3), 6 RESHAPE
  Bool.and(shape_is(x, 6, [sint_of(2), sint_of(3)]), dt_is(x, 6, S.void()))

# ALL THREE `raise`s, as three nodes the fold does NOT answer. `gap_count` is the
# "not in the table" test `t_gap_ok` already uses, and the third is the
# `s.val if s.op is Ops.CONST else ssimplify(s)` half of `as_shape`.
def t_resh_reject() -> Bool:
  +a = folded(O.Found.ar(g_resh23()))
  +b = folded(O.Found.ar(g_reshneg()))
  +c = folded(O.Found.ar(g_reshsym()))
  # the RESHAPE of each: 5 for the product mismatch, 3 for the negative dim, 6 for
  # the symbolic marg
  Bool.and(gap_count(a, 5), Bool.and(gap_count(b, 3), gap_count(c, 6)))

# THE WHOLE TABLE SETTLES, so the 2-D answer is the ARM's answer and not a lucky
# one: the same `Kahn.settled` claim `cycle_safe` makes, over a graph whose top
# node is a movement op instead of a BACKEDGE.
def t_resh_settle() -> Bool:
  +x = folded(O.Found.ar(g_resh22()))
  Kahn.settled(Folded.ar(x), Folded.t(x))

# sized/pad_to walk a shape in ops.py's order, and `pad_to` PREPENDS the ones,
# because `(1,)*(max_dim-len(s))+s` left-aligns to the widest shape. Every
# positional reader below names a dim by index -- `is_image_shape`'s `List.last`,
# `drop_last`'s `take_n`, `bitcast_dims`' last -- so a mirrored `sized` moves the
# answer without moving any count, which is why an order-insensitive fixture
# cannot see it. CPython, measured by `.agents/slop/notes/sized-oracle.py`:
# `sized((2,3))` is `(2,3)` and `pad_to((2,3),3)` is `(1,2,3)`.
def t_sized_order() -> Bool:
  Bool.and(eq_sints(Sized.s(sized([sint_of(2), sint_of(3)])), [sint_of(2), sint_of(3)]),
    eq_sints(Sized.s(pad_to(sized([sint_of(2), sint_of(3)]), 3n)),
      [sint_one(), sint_of(2), sint_of(3)]))

# THE WIDTH IS NOT HARD-CODED TO `weakint`. `bnd_int` is a general statement about the
# representation -- "an integer width past 64 saturates" -- and the twenty dtype rows can
# only reach it at 800, so the GUARD'S OWN boundary (64 vs 65) is exercised here directly.
# Mutation DT1 changes `is_gt(bits, 64)` to `is_gt(bits, 65)` and moves NOTHING on the
# twenty: no tinygrad dtype has a width in (64, 800], so the table cannot see it. These two
# rows are that mutation's FIXTURE, and they are the honest form of it -- the expectation
# is the design decision stated as a literal, not a def of the thing under test.
def dt_w(nm: String, +bits: U32, top: Bool) -> IO(Unit):
  dt_row(nm, bnd_int(False{}, True{}, bits), bnd_int(True{}, False{}, bits))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("dtype_key", t_dtype_key())
    b : Unit <- row("shape_ok", t_shape_ok())
    c : Unit <- row("device_ok", t_device_ok())
    d : Unit <- row("cycle_safe", t_cycle_safe())
    e : Unit <- row("gap_ok", t_gap_ok())
    f : Unit <- row("resh_2d", t_resh_2d())
    g : Unit <- row("resh_1d", t_resh_1d())
    h : Unit <- row("resh_noop", t_resh_noop())
    i : Unit <- row("resh_reject", t_resh_reject())
    j : Unit <- row("resh_settle", t_resh_settle())
    k : Unit <- row("sized_order", t_sized_order())
    # THE MOVEMENT ROWS. Four facts plus the answer, one string each, and the
    # expectations are `.agents/slop/oracles/fold-mvt-oracle.py`'s -- CPython's own
    # `n= op= nsrc= srcops= shape= dtype=`, so `diff` of the two IS the test.
    mv_of("exp1", g_mv_exp1())
    mv_of("exp23", g_mv_exp23())
    mv_of("expnoop", g_mv_expnoop())
    mv_of("expsym", g_mv_expsym())
    mv_of("pad1", g_mv_pad1())
    mv_of("pad23", g_mv_pad23())
    mv_of("padr", g_mv_padr())
    mv_of("padr2", g_mv_padr2())
    mv_of("shr1", g_mv_shr1())
    mv_of("shr23", g_mv_shr23())
    mv_of("shrbad", g_mv_shrbad())
    mv_of("perm", g_mv_perm10())
    mv_of("permrep", g_mv_permrep())
    mv_of("permlen", g_mv_permlen())
    mv_of("flip", g_mv_flip10())
    mv_of("fliplen", g_mv_fliplen())
    lf_row("add_int32_3_4", mm.lift(O.OpsADD{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("add_int32_-3_4", mm.lift(O.OpsADD{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("add_int32_-3_-4", mm.lift(O.OpsADD{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{True{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("add_int32_0_-5", mm.lift(O.OpsADD{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 0)}, BndInt{True{}, H.i64_of_hi_lo(0, 5)}), O.ANone{}, S.int32()))
    lf_row("add_int32_-5_0", mm.lift(O.OpsADD{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 5)}, BndInt{False{}, H.i64_of_hi_lo(0, 0)}), O.ANone{}, S.int32()))
    lf_row("add_int32_2147483648_2147483647", mm.lift(O.OpsADD{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 2147483648)}, BndInt{False{}, H.i64_of_hi_lo(0, 2147483647)}), O.ANone{}, S.int32()))
    lf_row("add_int32_-2147483648_-2147483647", mm.lift(O.OpsADD{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 2147483648)}, BndInt{True{}, H.i64_of_hi_lo(0, 2147483647)}), O.ANone{}, S.int32()))
    lf_row("add_int32_0_0", mm.lift(O.OpsADD{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 0)}, BndInt{False{}, H.i64_of_hi_lo(0, 0)}), O.ANone{}, S.int32()))
    lf_row("add_int32_1099511627776_-1099511627776", mm.lift(O.OpsADD{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(256, 0)}, BndInt{True{}, H.i64_of_hi_lo(256, 0)}), O.ANone{}, S.int32()))
    lf_row("sub_int32_3_4", mm.lift(O.OpsSUB{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("sub_int32_-3_4", mm.lift(O.OpsSUB{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("sub_int32_-3_-4", mm.lift(O.OpsSUB{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{True{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("sub_int32_3_-4", mm.lift(O.OpsSUB{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{True{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("sub_int32_-3_4", mm.lift(O.OpsSUB{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("sub_int32_0_0", mm.lift(O.OpsSUB{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 0)}, BndInt{False{}, H.i64_of_hi_lo(0, 0)}), O.ANone{}, S.int32()))
    lf_row("sub_int32_5_5", mm.lift(O.OpsSUB{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 5)}, BndInt{False{}, H.i64_of_hi_lo(0, 5)}), O.ANone{}, S.int32()))
    lf_row("sub_int32_4_5", mm.lift(O.OpsSUB{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 4)}, BndInt{False{}, H.i64_of_hi_lo(0, 5)}), O.ANone{}, S.int32()))
    lf_row("mul_int32_3_4", mm.lift(O.OpsMUL{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("mul_int32_-3_4", mm.lift(O.OpsMUL{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("mul_int32_-3_-4", mm.lift(O.OpsMUL{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{True{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("mul_int32_0_-5", mm.lift(O.OpsMUL{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 0)}, BndInt{True{}, H.i64_of_hi_lo(0, 5)}), O.ANone{}, S.int32()))
    lf_row("mul_int32_7_-8", mm.lift(O.OpsMUL{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 7)}, BndInt{True{}, H.i64_of_hi_lo(0, 8)}), O.ANone{}, S.int32()))
    lf_row("mul_int32_-2147483648_2", mm.lift(O.OpsMUL{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 2147483648)}, BndInt{False{}, H.i64_of_hi_lo(0, 2)}), O.ANone{}, S.int32()))
    lf_row("mul_int32_2147483648_3", mm.lift(O.OpsMUL{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 2147483648)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("mul_int32_1099511627776_1048576", mm.lift(O.OpsMUL{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(256, 0)}, BndInt{False{}, H.i64_of_hi_lo(0, 1048576)}), O.ANone{}, S.int32()))
    lf_row("max_int32_3_4", mm.lift(O.OpsMAX{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("max_int32_-3_4", mm.lift(O.OpsMAX{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("max_int32_3_-4", mm.lift(O.OpsMAX{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{True{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("max_int32_-3_-4", mm.lift(O.OpsMAX{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{True{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("max_int32_0_0", mm.lift(O.OpsMAX{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 0)}, BndInt{False{}, H.i64_of_hi_lo(0, 0)}), O.ANone{}, S.int32()))
    lf_row("max_int32_1099511627776_-1099511627776", mm.lift(O.OpsMAX{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(256, 0)}, BndInt{True{}, H.i64_of_hi_lo(256, 0)}), O.ANone{}, S.int32()))
    lf_row("cmplt_int32_3_4", mm.lift(O.OpsCMPLT{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("cmplt_int32_-3_4", mm.lift(O.OpsCMPLT{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("cmplt_int32_4_3", mm.lift(O.OpsCMPLT{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 4)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("cmplt_int32_-4_-3", mm.lift(O.OpsCMPLT{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 4)}, BndInt{True{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("cmplt_int32_3_3", mm.lift(O.OpsCMPLT{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("cmplt_int32_-3_-3", mm.lift(O.OpsCMPLT{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{True{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("cmplt_int32_1099511627776_-1099511627776", mm.lift(O.OpsCMPLT{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(256, 0)}, BndInt{True{}, H.i64_of_hi_lo(256, 0)}), O.ANone{}, S.int32()))
    lf_row("cmpne_int32_3_4", mm.lift(O.OpsCMPNE{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("cmpne_int32_-3_4", mm.lift(O.OpsCMPNE{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("cmpne_int32_4_3", mm.lift(O.OpsCMPNE{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 4)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("cmpne_int32_-4_-3", mm.lift(O.OpsCMPNE{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 4)}, BndInt{True{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("cmpne_int32_3_3", mm.lift(O.OpsCMPNE{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("cmpne_int32_-3_-3", mm.lift(O.OpsCMPNE{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{True{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("cmpne_int32_5_5", mm.lift(O.OpsCMPNE{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 5)}, BndInt{False{}, H.i64_of_hi_lo(0, 5)}), O.ANone{}, S.int32()))
    lf_row("andint_int32_5_255", mm.lift(O.OpsAND{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 5)}, BndInt{False{}, H.i64_of_hi_lo(0, 255)}), O.ANone{}, S.int32()))
    lf_row("andint_int32_0_255", mm.lift(O.OpsAND{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 0)}, BndInt{False{}, H.i64_of_hi_lo(0, 255)}), O.ANone{}, S.int32()))
    lf_row("andint_int32_-1_255", mm.lift(O.OpsAND{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 1)}, BndInt{False{}, H.i64_of_hi_lo(0, 255)}), O.ANone{}, S.int32()))
    lf_row("andint_int32_5_0", mm.lift(O.OpsAND{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 5)}, BndInt{False{}, H.i64_of_hi_lo(0, 0)}), O.ANone{}, S.int32()))
    lf_row("andint_int32_2147483648_7", mm.lift(O.OpsAND{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 2147483648)}, BndInt{False{}, H.i64_of_hi_lo(0, 7)}), O.ANone{}, S.int32()))
    lf_row("andint_int32_-2147483648_7", mm.lift(O.OpsAND{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 2147483648)}, BndInt{False{}, H.i64_of_hi_lo(0, 7)}), O.ANone{}, S.int32()))
    lf_row("andint_int32_8_255", mm.lift(O.OpsAND{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 8)}, BndInt{False{}, H.i64_of_hi_lo(0, 255)}), O.ANone{}, S.int32()))
    lf_row("andint_int32_255_8", mm.lift(O.OpsAND{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 255)}, BndInt{False{}, H.i64_of_hi_lo(0, 8)}), O.ANone{}, S.int32()))
    lf_row("andint_int32_1099511627776_1073741824", mm.lift(O.OpsAND{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(256, 0)}, BndInt{False{}, H.i64_of_hi_lo(0, 1073741824)}), O.ANone{}, S.int32()))
    lf_row("xor_int32_5_-1", mm.lift(O.OpsXOR{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 5)}, BndInt{True{}, H.i64_of_hi_lo(0, 1)}), O.ANone{}, S.int32()))
    lf_row("xor_int32_-5_-1", mm.lift(O.OpsXOR{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 5)}, BndInt{True{}, H.i64_of_hi_lo(0, 1)}), O.ANone{}, S.int32()))
    lf_row("xor_int32_0_-1", mm.lift(O.OpsXOR{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 0)}, BndInt{True{}, H.i64_of_hi_lo(0, 1)}), O.ANone{}, S.int32()))
    lf_row("xor_int32_2147483648_-1", mm.lift(O.OpsXOR{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 2147483648)}, BndInt{True{}, H.i64_of_hi_lo(0, 1)}), O.ANone{}, S.int32()))
    lf_row("shl_int32_1_3", mm.lift(O.OpsSHL{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 1)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("shl_int32_-1_3", mm.lift(O.OpsSHL{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 1)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("shl_int32_255_4", mm.lift(O.OpsSHL{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 255)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("shl_int32_-8_2", mm.lift(O.OpsSHL{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 8)}, BndInt{False{}, H.i64_of_hi_lo(0, 2)}), O.ANone{}, S.int32()))
    lf_row("shl_int32_1099511627776_8", mm.lift(O.OpsSHL{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(256, 0)}, BndInt{False{}, H.i64_of_hi_lo(0, 8)}), O.ANone{}, S.int32()))
    lf_row("shl_int32_7_0", mm.lift(O.OpsSHL{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 7)}, BndInt{False{}, H.i64_of_hi_lo(0, 0)}), O.ANone{}, S.int32()))
    lf_row("shr_int32_1_3", mm.lift(O.OpsSHR{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 1)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("shr_int32_-1_3", mm.lift(O.OpsSHR{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 1)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("shr_int32_255_4", mm.lift(O.OpsSHR{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 255)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("shr_int32_-8_2", mm.lift(O.OpsSHR{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 8)}, BndInt{False{}, H.i64_of_hi_lo(0, 2)}), O.ANone{}, S.int32()))
    lf_row("shr_int32_-9_1", mm.lift(O.OpsSHR{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 9)}, BndInt{False{}, H.i64_of_hi_lo(0, 1)}), O.ANone{}, S.int32()))
    lf_row("shr_int32_1099511627776_8", mm.lift(O.OpsSHR{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(256, 0)}, BndInt{False{}, H.i64_of_hi_lo(0, 8)}), O.ANone{}, S.int32()))
    lf_row("shr_int32_7_0", mm.lift(O.OpsSHR{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 7)}, BndInt{False{}, H.i64_of_hi_lo(0, 0)}), O.ANone{}, S.int32()))
    lf_row("orb_True_False", mm.lift(O.OpsOR{}, lf_c2(bnd_tf(True{}), bnd_tf(False{})), O.ANone{}, S.boolean()))
    lf_row("orb_False_True", mm.lift(O.OpsOR{}, lf_c2(bnd_tf(False{}), bnd_tf(True{})), O.ANone{}, S.boolean()))
    lf_row("orb_True_True", mm.lift(O.OpsOR{}, lf_c2(bnd_tf(True{}), bnd_tf(True{})), O.ANone{}, S.boolean()))
    lf_row("orb_False_False", mm.lift(O.OpsOR{}, lf_c2(bnd_tf(False{}), bnd_tf(False{})), O.ANone{}, S.boolean()))
    lf_row("andb_True_False", mm.lift(O.OpsAND{}, lf_c2(bnd_tf(True{}), bnd_tf(False{})), O.ANone{}, S.boolean()))
    lf_row("andb_False_True", mm.lift(O.OpsAND{}, lf_c2(bnd_tf(False{}), bnd_tf(True{})), O.ANone{}, S.boolean()))
    lf_row("andb_True_True", mm.lift(O.OpsAND{}, lf_c2(bnd_tf(True{}), bnd_tf(True{})), O.ANone{}, S.boolean()))
    lf_row("andb_False_False", mm.lift(O.OpsAND{}, lf_c2(bnd_tf(False{}), bnd_tf(False{})), O.ANone{}, S.boolean()))
    lf_row("ft_cmpeq", mm.lift(O.OpsCMPEQ{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 2)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.boolean()))
    lf_row("where1", mm.lift(O.OpsWHERE{}, lf_c3(BndInt{False{}, H.i64_of_hi_lo(0, 1)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{True{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("where2", mm.lift(O.OpsWHERE{}, lf_c3(BndInt{False{}, H.i64_of_hi_lo(0, 1)}, BndInt{True{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("where3", mm.lift(O.OpsWHERE{}, lf_c3(BndInt{False{}, H.i64_of_hi_lo(0, 0)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("padf", mm.lift(O.OpsPAD{}, lf_c3(bnd_f(F32.div(F32.from_nat(3n), F32.from_nat(2n))), BndInt{False{}, H.i64_of_hi_lo(0, 0)}, BndInt{False{}, H.i64_of_hi_lo(0, 1)}), O.ANone{}, S.single()))
    lf_row("padn", mm.lift(O.OpsPAD{}, lf_c3(bnd_f(F32.neg(F32.div(F32.from_nat(3n), F32.from_nat(2n)))), BndInt{False{}, H.i64_of_hi_lo(0, 0)}, BndInt{False{}, H.i64_of_hi_lo(0, 2)}), O.ANone{}, S.single()))
    lf_row("mv_reshape", mm.lift(O.OpsRESHAPE{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("mv_expand", mm.lift(O.OpsEXPAND{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("mv_permute", mm.lift(O.OpsPERMUTE{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("mv_shrink", mm.lift(O.OpsSHRINK{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("mv_flip", mm.lift(O.OpsFLIP{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("mv_index", mm.lift(O.OpsINDEX{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("mv_stage", mm.lift(O.OpsSTAGE{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("mv_after", mm.lift(O.OpsAFTER{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("mv_detach", mm.lift(O.OpsDETACH{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("mv_copy", mm.lift(O.OpsCOPY{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("mv_contiguous_backward", mm.lift(O.OpsCONTIGUOUS_BACKWARD{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("mv_pad", mm.lift(O.OpsPAD{}, lf_c3(BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}, BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("c0", mm.lift(O.OpsCONST{}, lf_c0(), O.APy{O.CInt{H.i64_of_hi_lo(0, 0)}}, S.int32()))
    lf_row("c1", mm.lift(O.OpsCONST{}, lf_c0(), O.APy{O.CInt{H.i64_of_hi_lo(0, 1)}}, S.int32()))
    lf_row("cm1", mm.lift(O.OpsCONST{}, lf_c0(), O.APy{O.CInt{H.i64_of_hi_lo(4294967295, 4294967295)}}, S.int32()))
    lf_row("c31", mm.lift(O.OpsCONST{}, lf_c0(), O.APy{O.CInt{H.i64_of_hi_lo(0, 2147483648)}}, S.int32()))
    lf_row("cf", mm.lift(O.OpsCONST{}, lf_c0(), O.APy{O.CFloat{F32.div(F32.from_nat(3n), F32.from_nat(2n))}}, S.int32()))
    lf_row("cfn", mm.lift(O.OpsCONST{}, lf_c0(), O.APy{O.CFloat{F32.neg(F32.div(F32.from_nat(3n), F32.from_nat(2n)))}}, S.int32()))
    lf_row("cb", mm.lift(O.OpsCONST{}, lf_c0(), O.APy{O.CBool{True{}}}, S.int32()))
    lf_row("cbf", mm.lift(O.OpsCONST{}, lf_c0(), O.APy{O.CBool{False{}}}, S.int32()))
    lf_row("cinv", mm.lift(O.OpsCONST{}, lf_c0(), O.APy{O.CInvalid{}}, S.boolean()))
    lf_row("cnan", mm.lift(O.OpsCONST{}, lf_c0(), O.APy{O.CFloat{F32.div(F32.from_nat(0n), F32.from_nat(0n))}}, S.single()))
    lf_row("range4", mm.lift(O.OpsRANGE{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("spec4", mm.lift(O.OpsSPECIAL{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 4)}), O.ANone{}, S.int32()))
    lf_row("range0", mm.lift(O.OpsRANGE{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 0)}), O.ANone{}, S.int32()))
    lf_row("spec0", mm.lift(O.OpsSPECIAL{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 0)}), O.ANone{}, S.int32()))
    lf_row("rangen3", mm.lift(O.OpsRANGE{}, lf_c1(BndInt{True{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("specn3", mm.lift(O.OpsSPECIAL{}, lf_c1(BndInt{True{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("stack1", mm.lift(O.OpsSTACK{}, lf_c1(BndInt{False{}, H.i64_of_hi_lo(0, 3)}), O.ANone{}, S.int32()))
    lf_row("stack2", mm.lift(O.OpsSTACK{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(0, 1)}, BndInt{True{}, H.i64_of_hi_lo(0, 2)}), O.ANone{}, S.int32()))
    lf_row("stack3", mm.lift(O.OpsSTACK{}, lf_c3(BndInt{False{}, H.i64_of_hi_lo(0, 1)}, BndInt{True{}, H.i64_of_hi_lo(0, 2)}, BndInt{False{}, H.i64_of_hi_lo(0, 5)}), O.ANone{}, S.int32()))
    lf_row("stack4", mm.lift(O.OpsSTACK{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(0, 2147483648)}, BndInt{False{}, H.i64_of_hi_lo(0, 2147483648)}), O.ANone{}, S.int32()))
    lf_row("param0", mm.lift(O.OpsPARAM{}, lf_c0(), lf_pa(H.i64_of_hi_lo(0, 3), H.i64_of_hi_lo(0, 7)), S.int32()))
    lf_row("param0_alloc", mm.lift(O.OpsALLOC{}, lf_c0(), lf_pa(H.i64_of_hi_lo(0, 3), H.i64_of_hi_lo(0, 7)), S.int32()))
    lf_row("param1", mm.lift(O.OpsPARAM{}, lf_c0(), lf_pa(H.i64_of_hi_lo(4294967040, 0), H.i64_of_hi_lo(4294967295, 4294967295)), S.int32()))
    lf_row("param1_alloc", mm.lift(O.OpsALLOC{}, lf_c0(), lf_pa(H.i64_of_hi_lo(4294967040, 0), H.i64_of_hi_lo(4294967295, 4294967295)), S.int32()))
    lf_row("param2", mm.lift(O.OpsPARAM{}, lf_c0(), lf_pa(H.i64_of_hi_lo(0, 0), H.i64_of_hi_lo(0, 0)), S.int32()))
    lf_row("param2_alloc", mm.lift(O.OpsALLOC{}, lf_c0(), lf_pa(H.i64_of_hi_lo(0, 0), H.i64_of_hi_lo(0, 0)), S.int32()))
    lf_row("sat_add", mm.lift(O.OpsADD{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(2147483648, 0)}, BndInt{False{}, H.i64_of_hi_lo(2147483648, 0)}), O.ANone{}, S.int32()))
    lf_row("sat_sub", mm.lift(O.OpsSUB{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(2147483648, 0)}, BndInt{False{}, H.i64_of_hi_lo(2147483648, 0)}), O.ANone{}, S.int32()))
    lf_row("sat_mul", mm.lift(O.OpsMUL{}, lf_c2(BndInt{False{}, H.i64_of_hi_lo(2147483648, 0)}, BndInt{False{}, H.i64_of_hi_lo(0, 2)}), O.ANone{}, S.int32()))
    lf_row("sat_addneg", mm.lift(O.OpsADD{}, lf_c2(BndInt{True{}, H.i64_of_hi_lo(2147483648, 0)}, BndInt{True{}, H.i64_of_hi_lo(2147483648, 0)}), O.ANone{}, S.int32()))

    # THE `_min_max` ARITHMETIC ROWS. `.agents/slop/mm-gate.py` GENERATES BOTH THE
    # FIXTURES AND THESE LINES, so a row cannot be right on one lane and wrong on the
    # other; 72 rows, byte-identical to CPython on the interpreted AND the `-o` lane.
    mm_row("add_zero", mm_show(mm.u64.add(0, 0, 0, 0)))
    mm_row("add_small", mm_show(mm.u64.add(0, 5, 0, 7)))
    mm_row("add_carrylo", mm_show(mm.u64.add(0, 4294967295, 0, 1)))
    mm_row("add_carryhi", mm_show(mm.u64.add(0, 1, 0, 4294967295)))
    mm_row("add_hilo", mm_show(mm.u64.add(1, 0, 0, 4294967295)))
    mm_row("add_over64", mm_show(mm.u64.add(1, 0, 4294967295, 4294967295)))
    mm_row("add_maxmax", mm_show(mm.u64.add(4294967295, 4294967295, 4294967295, 4294967295)))
    mm_row("add_2p31", mm_show(mm.u64.add(0, 2147483648, 0, 2147483648)))
    mm_row("sub_ok", mm_show(mm.u64.sub(0, 7, 0, 5)))
    mm_row("sub_zero", mm_show(mm.u64.sub(0, 5, 0, 5)))
    mm_row("sub_borrow", mm_show(mm.u64.sub(0, 5, 0, 7)))
    mm_row("sub_borrowhi", mm_show(mm.u64.sub(1, 0, 0, 1)))
    mm_row("sub_under64", mm_show(mm.u64.sub(0, 0, 1, 0)))
    mm_row("sub_tomax", mm_show(mm.u64.sub(0, 0, 0, 1)))
    mm_row("sub_maxmax", mm_show(mm.u64.sub(4294967295, 4294967295, 4294967295, 4294967295)))
    mm_row("mul_small", mm_show(mm.u64.mul(0, 100000, 0, 100000)))
    mm_row("mul_16sq", mm_show(mm.u64.mul(0, 65535, 0, 65535)))
    mm_row("mul_31sq", mm_show(mm.u64.mul(0, 2147483647, 0, 2147483647)))
    mm_row("mul_32sq", mm_show(mm.u64.mul(0, 4294967295, 0, 4294967295)))
    mm_row("mul_2p32sq", mm_show(mm.u64.mul(1, 0, 1, 0)))
    mm_row("mul_over64", mm_show(mm.u64.mul(0, 4294967295, 1, 0)))
    mm_row("mul_maxsq", mm_show(mm.u64.mul(4294967295, 4294967295, 4294967295, 4294967295)))
    mm_row("mul_1e12", mm_show(mm.u64.mul(0, 1000000, 0, 1000000)))
    mm_row("mul_6x", mm_show(mm.u64.mul(0, 6, 0, 715827883)))
    mm_row("mul_zero", mm_show(mm.u64.mul(0, 0, 0, 4294967295)))
    mm_row("mul_2p63", mm_show(mm.u64.mul(1, 0, 0, 2147483648)))
    mm_row("mul_2p32m", mm_show(mm.u64.mul(0, 4294967295, 0, 4294967295)))
    mm_row("mul_2p48sq", mm_show(mm.u64.mul(65536, 0, 65536, 0)))
    mm_row("mul_2p47sq", mm_show(mm.u64.mul(32768, 0, 32768, 0)))
    mm_row("shl_0", mm_show(mm.u64.shl(0, 1, 0n)))
    mm_row("shl_1", mm_show(mm.u64.shl(0, 1, 1n)))
    mm_row("shl_31", mm_show(mm.u64.shl(0, 1, 31n)))
    mm_row("shl_32", mm_show(mm.u64.shl(0, 1, 32n)))
    mm_row("shl_63", mm_show(mm.u64.shl(0, 1, 63n)))
    mm_row("shl_64", mm_show(mm.u64.shl(0, 1, 64n)))
    mm_row("shl_hi1", mm_show(mm.u64.shl(1, 0, 1n)))
    mm_row("shl_hi32", mm_show(mm.u64.shl(1, 0, 32n)))
    mm_row("shl_hi63", mm_show(mm.u64.shl(1, 0, 63n)))
    mm_row("shl_over63", mm_show(mm.u64.shl(4294967295, 4294967295, 1n)))
    mm_row("shl_over32", mm_show(mm.u64.shl(4294967295, 4294967295, 32n)))
    mm_row("shl_edge32", mm_show(mm.u64.shl(1, 0, 32n)))
    mm_row("shl_max32", mm_show(mm.u64.shl(0, 4294967295, 32n)))
    mm_row("shl_max31", mm_show(mm.u64.shl(0, 4294967295, 31n)))
    mm_row("shl_max63", mm_show(mm.u64.shl(0, 4294967295, 63n)))
    mm_row("shl_0hi", mm_show(mm.u64.shl(1, 0, 0n)))
    mm_row("shl_bigk", mm_show(mm.u64.shl(1, 0, 100n)))
    mm_row("shr_0", H.i64_text(mm.u64.shr(1, 5, 0n)))
    mm_row("shr_1", H.i64_text(mm.u64.shr(1, 5, 1n)))
    mm_row("shr_31", H.i64_text(mm.u64.shr(0, 4294967295, 31n)))
    mm_row("shr_32", H.i64_text(mm.u64.shr(1, 0, 32n)))
    mm_row("shr_63", H.i64_text(mm.u64.shr(1, 0, 63n)))
    mm_row("shr_64", H.i64_text(mm.u64.shr(1, 0, 64n)))
    mm_row("shr_max", H.i64_text(mm.u64.shr(4294967295, 4294967295, 1n)))
    mm_row("shr_max40", H.i64_text(mm.u64.shr(4294967295, 4294967295, 40n)))
    mm_row("shr_bigk", H.i64_text(mm.u64.shr(4294967295, 4294967295, 100n)))
    mm_row("div_17_5", mm.dm_show(mm.dm_run(0, 17, 0, 5)))
    mm_row("div_17_1", mm.dm_show(mm.dm_run(0, 17, 0, 1)))
    mm_row("div_2p32_3", mm.dm_show(mm.dm_run(1, 0, 0, 3)))
    mm_row("div_7_2p32", mm.dm_show(mm.dm_run(0, 7, 1, 0)))
    mm_row("div_maxmax", mm.dm_show(mm.dm_run(4294967295, 4294967295, 4294967295, 4294967295)))
    mm_row("div_max_2p32m", mm.dm_show(mm.dm_run(4294967295, 4294967295, 0, 4294967295)))
    mm_row("div_2p32m_x", mm.dm_show(mm.dm_run(0, 4294967295, 0, 715827883)))
    mm_row("div_max_2p32", mm.dm_show(mm.dm_run(4294967295, 4294967295, 1, 0)))
    mm_row("div_2p33_7", mm.dm_show(mm.dm_run(1, 5, 0, 7)))
    mm_row("div_max_p1", mm.dm_show(mm.dm_run(4294967295, 4294967295, 0, 1)))
    mm_row("div_100_7", mm.dm_show(mm.dm_run(0, 100, 0, 7)))
    mm_row("div_max_3", mm.dm_show(mm.dm_run(4294967295, 4294967295, 0, 3)))
    mm_row("div_2p32_2p32m", mm.dm_show(mm.dm_run(1, 0, 0, 4294967295)))
    mm_row("div_max_2", mm.dm_show(mm.dm_run(4294967295, 4294967295, 0, 2)))
    mm_row("div_1_2", mm.dm_show(mm.dm_run(0, 1, 0, 2)))
    mm_row("div_2p63_max", mm.dm_show(mm.dm_run(2147483648, 0, 4294967295, 4294967295)))
    mm_row("div_2p63_2p62", mm.dm_show(mm.dm_run(2147483648, 0, 1073741824, 0)))
    # THE `bit_length` ROWS. `.agents/slop/mm-bl-gate.py` GENERATES BOTH THE FIXTURES
    # AND THESE LINES -- 26 counts and 12 masked integers -- so a row cannot be right on
    # one lane and wrong on the other. The `mk_*` rows are the AND arm's answer rather
    # than the counter's, and they are the ones that catch a count that is one too big.
    bl_row("bl_0", U32.show(mm.bl64(0, 0)))
    bl_row("bl_1", U32.show(mm.bl64(0, 1)))
    bl_row("bl_2", U32.show(mm.bl64(0, 2)))
    bl_row("bl_3", U32.show(mm.bl64(0, 3)))
    bl_row("bl_4", U32.show(mm.bl64(0, 4)))
    bl_row("bl_5", U32.show(mm.bl64(0, 5)))
    bl_row("bl_15", U32.show(mm.bl64(0, 15)))
    bl_row("bl_16", U32.show(mm.bl64(0, 16)))
    bl_row("bl_255", U32.show(mm.bl64(0, 255)))
    bl_row("bl_256", U32.show(mm.bl64(0, 256)))
    bl_row("bl_65535", U32.show(mm.bl64(0, 65535)))
    bl_row("bl_65536", U32.show(mm.bl64(0, 65536)))
    bl_row("bl_2p24", U32.show(mm.bl64(0, 16777216)))
    bl_row("bl_2p31", U32.show(mm.bl64(0, 2147483648)))
    bl_row("bl_2p31m1", U32.show(mm.bl64(0, 2147483647)))
    bl_row("bl_2p32", U32.show(mm.bl64(1, 0)))
    bl_row("bl_2p32m1", U32.show(mm.bl64(0, 4294967295)))
    bl_row("bl_2p32p1", U32.show(mm.bl64(1, 1)))
    bl_row("bl_2p48", U32.show(mm.bl64(65536, 0)))
    bl_row("bl_2p48m1", U32.show(mm.bl64(65535, 4294967295)))
    bl_row("bl_2p63", U32.show(mm.bl64(2147483648, 0)))
    bl_row("bl_2p63m1", U32.show(mm.bl64(2147483647, 4294967295)))
    bl_row("bl_max", U32.show(mm.bl64(4294967295, 4294967295)))
    bl_row("bl_maxm1", U32.show(mm.bl64(4294967295, 4294967294)))
    bl_row("bl_1000000", U32.show(mm.bl64(0, 1000000)))
    bl_row("bl_123456789", U32.show(mm.bl64(0, 123456789)))
    bl_row("mk_0_0", mm_show(mm_mask64(0, 0, 0, 0)))
    bl_row("mk_5_255", mm_show(mm_mask64(0, 5, 0, 255)))
    bl_row("mk_255_5", mm_show(mm_mask64(0, 255, 0, 5)))
    bl_row("mk_256_256", mm_show(mm_mask64(0, 256, 0, 256)))
    bl_row("mk_256_m1", mm_show(mm_mask64(0, 256, 4294967295, 4294967295)))
    bl_row("mk_65535_m1", mm_show(mm_mask64(0, 65535, 4294967295, 4294967295)))
    bl_row("mk_65536_m1", mm_show(mm_mask64(0, 65536, 4294967295, 4294967295)))
    bl_row("mk_2p31m1_m1", mm_show(mm_mask64(0, 2147483647, 4294967295, 4294967295)))
    bl_row("mk_2p32_m1", mm_show(mm_mask64(1, 0, 4294967295, 4294967295)))
    bl_row("mk_m1_m1", mm_show(mm_mask64(4294967295, 4294967295, 4294967295, 4294967295)))
    bl_row("mk_m1_2p32", mm_show(mm_mask64(4294967295, 4294967295, 1, 0)))
    bl_row("mk_7_2p63", mm_show(mm_mask64(0, 7, 2147483648, 0)))
    # THE TWENTY DTYPE LIMITS. `.agents/slop/mm-dt-gate.py` reads CPython's own
    # `dtypes.<name>.min`/`.max` for the expectations AND generates these lines, so a
    # limit cannot be right on one lane and wrong on the other. `weakint` is the row that
    # matters most: its width is 800 bits and its two limits are `NInf`/`PInf` here, which
    # is the width argument's ONE designed divergence.
    dt_row("boolean", bnd_lim(S.boolean(), False{}), bnd_lim(S.boolean(), True{}))
    dt_row("weakint", bnd_lim(S.weakint(), False{}), bnd_lim(S.weakint(), True{}))
    dt_row("int8", bnd_lim(S.int8(), False{}), bnd_lim(S.int8(), True{}))
    dt_row("uint8", bnd_lim(S.uint8(), False{}), bnd_lim(S.uint8(), True{}))
    dt_row("int16", bnd_lim(S.int16(), False{}), bnd_lim(S.int16(), True{}))
    dt_row("uint16", bnd_lim(S.uint16(), False{}), bnd_lim(S.uint16(), True{}))
    dt_row("int32", bnd_lim(S.int32(), False{}), bnd_lim(S.int32(), True{}))
    dt_row("uint32", bnd_lim(S.uint32(), False{}), bnd_lim(S.uint32(), True{}))
    dt_row("int64", bnd_lim(S.int64(), False{}), bnd_lim(S.int64(), True{}))
    dt_row("uint64", bnd_lim(S.uint64(), False{}), bnd_lim(S.uint64(), True{}))
    dt_row("weakfloat", bnd_lim(S.weakfloat(), False{}), bnd_lim(S.weakfloat(), True{}))
    dt_row("float8_e4m3", bnd_lim(S.fp8e4m3(), False{}), bnd_lim(S.fp8e4m3(), True{}))
    dt_row("float8_e4m3fnuz", bnd_lim(S.fp8e4m3fnuz(), False{}), bnd_lim(S.fp8e4m3fnuz(), True{}))
    dt_row("float8_e5m2", bnd_lim(S.fp8e5m2(), False{}), bnd_lim(S.fp8e5m2(), True{}))
    dt_row("float8_e5m2fnuz", bnd_lim(S.fp8e5m2fnuz(), False{}), bnd_lim(S.fp8e5m2fnuz(), True{}))
    dt_row("float16", bnd_lim(S.half(), False{}), bnd_lim(S.half(), True{}))
    dt_row("bfloat16", bnd_lim(S.bfloat16(), False{}), bnd_lim(S.bfloat16(), True{}))
    dt_row("float32", bnd_lim(S.single(), False{}), bnd_lim(S.single(), True{}))
    dt_row("float64", bnd_lim(S.double(), False{}), bnd_lim(S.double(), True{}))
    dt_row("void", bnd_lim(S.void(), False{}), bnd_lim(S.void(), True{}))
    dt_w("w65_signed", 65, False{})
    dt_w("w65_unsigned", 65, False{})
    dt_w("w127_signed", 127, False{})
    dt_w("w800_signed", 800, False{})
    # THE `_min_max` ARITHMETIC ROWS. `.agents/slop/mm-gate.py` generates BOTH the
    # fixtures and these lines, so a row cannot be right on one lane and wrong on the
    # other; 72 rows, byte-identical to CPython on both the interpreted and `-o` lanes.

# ===========================================================================
# NOT PORTED, one line each, and the wall each one is behind. The Python line
# numbers are ops.py's, so this list diffs against ops.py line for line and
# `rg "TODO(p3)" tinybendygrad/uop/fold.bend` is the work queue.
#
# THE ONE LINE THAT COVERS MANY: `simplify` (ops.py:513) is `graph_rewrite(self,
# symbolic)`, and `graph_rewrite`'s rules call `dtype` and `shape`, which is what
# makes tinygrad's version cyclic. So `simplify` is P3 and it is the reason the
# movement shapes are deferred rather than ported.
# ===========================================================================
# TODO(p3) ops.py: 95  def sym_infer            -- `exec` of generated source; P3/P6.
# TODO(p3) ops.py:199  __call__ (ucache key)   -- PORTED, as the `dtype_key` gate row:
#   the key must separate nodes of different dtype, a CONST's dtype is the type of
#   its arg, and True == 1 as dict keys.
# TODO(p3) ops.py:218  class recursive_property -- PORTED as the fold itself.
# TODO(p3) ops.py:246  def dtype                -- PORTED, as `UOp.dtype` over a table.
# TODO(p3) ops.py:267  def key                  -- `hashlib.sha256`. Bend has no rotate
#   and no popcount (see the constraints note, section 2), and `key` is P3 with the
#   cache it keys. The parts of `key` that are not the digest ARE here: the dtype
#   it digests (`UOp.dtype`) and the arg it renders (`Arena.arg`).
# TODO(p3) ops.py:278  def backward_slice       -- a `toposort(enter_calls=False)` plus
#   a pop. `ops.bend` has the toposort; the pop is a `Maybe`-carrying fold, P3.
# TODO(p3) ops.py:290  def _bool_slice          -- a `frozenset` union down the srcs. It
#   is a set, and the arena is a `List`; the `dtypes.bool` test it reads is
#   `UOp.dtype`, so the only thing missing is the set algebra, which is P3's.
# TODO(p3) ops.py:322  def tuplize              -- `repr(self.arg)` for the sort, and
#   `_UOpTuple`'s identity equality. A mixed `(U32, String, DType, ...)` sort over
#   a `List` is P3.
# TODO(p3) ops.py:329  def _shape               -- PORTED, with `UOp.shape` over a table.
#   Ten of its arms are deferred, in `dt_shape`, each with the rule it waits for.
#   ops.py's own comments on the arms it DOES port, kept where they load-bear:
#   "late ops don't have shape", "some ops init the shape", "passthrough ops",
#   "pass through first", "always void", "special (terrible) case for RESHAPE on
#   NOOP", "STAGE adds the existing shape to the front, opposite of INDEX", "wmma
#   output shape = accumulator shape (src[2])", and "UNSHARD marker has no shape".
# TODO(p3) ops.py:456  def shape                -- `if (ret:=self._shape) is None: raise`,
#   which is `UOp.shape`'s `Maybe` with the `None` arm the error. One line, and it
#   is not written because a `raise` is not a value here: the fold reports the
#   absence and the caller decides.
# TODO(p3) ops.py:461  def shard_shape          -- `self.device`, `self.axis` and
#   `self.src[1].vmax`; the last is `_min_max`, which is below.
# TODO(p3) ops.py:470  def ended_ranges         -- PORTED, as `UOp.ended_ranges`.
# TODO(p3) ops.py:483  def _ranges              -- the union of the srcs' `ranges` minus
#   the ended ones. A `dict[UOp, None]`, i.e. a set, and the `ended_ranges` arms
#   that recurse (AFTER, BARRIER) need a set union over the srcs' answers. P3 with
#   the set algebra `_bool_slice` also wants.
# TODO(p3) ops.py:497  def ranges               -- `{self:None} | self._ranges`, so it is
#   `_ranges` plus one prepend.
# TODO(p3) ops.py:502  def axis_id              -- PORTED, and NOT a fold property:
#   `self.arg[0:-1]` is the `ids` field of `ARange`, and `ops.bend` already split
#   the Python tuple into the pair. See `UOp.axis_id`.
# TODO(p3) ops.py:507  def axis_type            -- PORTED, same reason. `UOp.axis_type`.
# TODO(p3) ops.py:513  def simplify             -- `graph_rewrite`, see the wall above.
# TODO(p3) ops.py:520  def ssimplify            -- `uop.simplify()`, so the same wall.
#   This is the ONE missing piece behind the deferred movement shapes.
# TODO(p3) ops.py:544  def trace_num            -- replaces the UOps in a tag tuple with
#   their numbers, which `Tag` already holds (`TTuple{xs: List<&2, U32>}`), and
#   builds a `SymDict`. P3 with `symbolic`.
# TODO(p3) ops.py:565  def body                 -- PORTED, inlined into `ended_of.call`:
#   `self.src[0]` for a CALL is the one line, and it is read there.
# TODO(p3) ops.py:668  def get_idx              -- `self.structurally_legal`; P3.
# TODO(p3) ops.py:718  def axis                 -- `self.arg` for a movement op, so it is
#   `marg`-shaped and P3 with `marg`.
# TODO(p3) ops.py:785  def base                 -- PORTED, as `UOp.base` over the table.
# TODO(p3) ops.py:790  def unsharded_base        -- `base` plus UNSHARD, one more arm on
#   `base_of.steps`. P3 with `storage_base`.
# TODO(p3) ops.py:801  def storage_base         -- `base` with UNSHARD, BITCAST and
#   AFTER stripped: a `while` over three ops, which the fold would answer with a
#   seventh `Derived` field. P3.
# TODO(p3) ops.py:808  def as_shape             -- PORTED for CONST and STACK-OF-CONST,
#   which is everything `shape_to_shape_arg` builds (`marg`, `marg.at`). The remaining
#   arm is `(ssimplify(self),)` for a src that is neither, and `ssimplify` is the wall:
#   CPython ANSWERS a shape holding a UOp there and the fold refuses. `mv_expsym` is
#   that row and the only line of the gate that disagrees with CPython. ops.py asks why
#   the cached property here makes external_uop_gc fail; unanswered here too.
# TODO(p3) ops.py:814  def marg                 -- ALL THREE ARMS PORTED, and the second
#   of them was the wall the other six movement shapes were queued behind:
#     RESHAPE | EXPAND -> `src[1].as_shape`      `marg` (already landed with RESHAPE)
#     PAD | SHRINK    -> `zip(src[1], src[2])`   `marg.at(1)`/`marg.at(2)` + `pad_shrink.go`
#     PERMUTE | FLIP  -> `self.arg`              `order_arg` -- NO `as_shape` AT ALL.
#   So the `ssimplify` wall was behind `marg` only for the ops whose marg is a SHAPE,
#   and behind none of the five this unit landed. RESHAPE, EXPAND, PAD, SHRINK, PERMUTE
#   and FLIP all answer now; UNSHARD does not, and its wall is `_min_max`.
# TODO(p3) ops.py:890  def device               -- PORTED, as `UOp.device`.
# TODO(p3) ops.py:905  def is_virtual           -- `self.dtype in dtypes.weaks`, and
#   `dtypes.weaks` is dtype.bend's `weaks()`, which is unreachable (see the header).
#   The `self.device is None` half is `UOp.device`.
# TODO(p3) ops.py:910  def addrspace            -- PORTED, as `UOp.addrspace`.
# TODO(p3) ops.py:1008 def is_realized          -- `has_buffer_identity`, a graph walk
#   with a set. P3.
# TODO(p3) ops.py:1013 def variable             -- `self.op is Ops.PARAM and
#   self.arg.vmin_vmax is not None`, which is a `ParamArg` read and no fold at all.
#   P3 with its four siblings at 1018-1044.
# TODO(p3) ops.py:1047 def variables            -- the `unbind`/`unbind_all` set walk.
#   P3 with the set algebra.
# TODO(p3) ops.py:1058 def const_factor         -- `divides` on a symbolic factor list,
#   and `divides` needs `gcd`, and `gcd` needs a `Counter` fold. P3.
# TODO(p3) ops.py:1100 def vmin                 -- `self._min_max[0]`, and the BOUND
#   AND THE OP TABLE it reads are both LANDED and gated. What is left is the WALK.
# TODO(p3) ops.py:1102 def vmax                 -- `self._min_max[1]`, same.
# TODO(p3) ops.py:1104 def _min_max             -- THE BOUND, THE OP TABLE AND
#   `int(x).bit_length()` ARE LANDED AND GATED (54 + 127 rows byte-identical to CPython,
#   and a 37-entry mutation table below). What is left is the WALK and four
#   signed-division arms. The history of the wall this retires is worth keeping: `mixin/dtype.bend` measured the wall as "four I64
#   arithmetic helpers missing, and the div/mod that DO exist are `IO(..)` effect
#   seams a fold cannot call". Those four are now PURE and gated: `mm.u64.add`,
#   `mm.u64.sub`, `mm.u64.mul`, `mm.u64.shl`/`shr` and `mm.dm.*` (a 64-step
#   restoring division) are above, with 72 rows byte-identical to CPython on both
#   lanes and a 21-entry mutation table of which 20 move rows.
#
#   THE WIDTH IS SETTLED BY MEASUREMENT, and it is not 64 SIGNED bits.
#   `.agents/slop/oracles/mm-range.py` walks 21 real graphs: a plain 8x8 matmul has
#   21 of 232 nodes whose bound leaves i64, the widest bound seen is 96 bits, and the
#   values that leave are `dtypes.uint64.max` = 2**64-1 and `uint64.max << 10`. A
#   signed 64-bit word cannot hold 2**64-1, so the port is a SIGN BIT PLUS AN
#   UNSIGNED 64-BIT MAGNITUDE, covering [-2**63, 2**64-1] -- every dtype limit
#   tinygrad has. Bend's only runtime numbers are `U32` and `Nat`, and `Nat` refuses
#   past 2**48-1, so this pair is the widest thing Bend 2.0.34 can express at all.
#   Where an INTERMEDIATE leaves the window the answer is `PInf`/`NInf`, and that is
#   the ONE designed divergence: it is a sound OVER-APPROXIMATION, and every consumer
#   of `_min_max` asks a question an over-approximation still answers.
#
#   WHAT IS LANDED, and it is the arithmetic plus the TABLE plus `bit_length`:
#     * `mm.bl32`/`mm.bl64`/`mm.mask64` -- `int(x).bit_length()` and `2**k - 1`. The
#       previous unit recorded this as a STRUCTURAL WALL (a zero test that cannot be a
#       `match` scrutinee, a growing counter that cannot lead a self-call, two defs
#       refused as mutual recursion). It is SOLVED AND NOT ROUTED AROUND, by a
#       FIVE-STAGE BINARY-SEARCH LADDER: `bit_length(x)` is the sum of `k` over the
#       literal thresholds `2**16, 2**8, 2**4, 2**2, 2**1` that `x` meets, plus one if
#       the residue is nonzero. The wall was ADDITIVE COUNTING and not the language: a
#       walk counts UP and needs a zero test, and this NARROWS, so "am I done" is
#       answered by five literal thresholds and never by a test on the value at all.
#       See the section header above for the full argument.
#     * `Bnd = NInf | PInf | Int{neg, mag} | Flt` and `bnd_lim`, the twenty DTYPE
#       LIMITS, hoisted out of dtype.bend under the same notice as `promo_mask`.
#     * `mm.lift`, the OP TABLE for ops.py:1105-1163 -- PURE over
#       `(op, srcs, arg, dtype)` with the src intervals handed IN, which is what makes
#       it gateable before there is a walk. Twelve of the sixteen binary arms plus
#       WHERE, Defines+vmin_vmax, RANGE/SPECIAL, STACK, CONST, PAD, the
#       Movement|INDEX passthrough and the `(dtype.min, dtype.max)` default.
#
#   WHAT IS STILL NOT WRITTEN, in the order the walls fall:
#     1. THE WALK. `mm.lift` takes the srcs' intervals as an argument, so what is
#       missing is the Kahn pass that PRODUCES them -- the same `pend`/`work`/`Table`
#       machine the other six properties use with a `Bnd2` row type, and mechanical
#       rather than subtle, which is WHY the table was built first.
#       THE KAHN PASS IS DELIBERATELY NOT A SEVENTH `Derived` FIELD, and that is the one
#       design decision here rather than a consequence. `_min_max` needs NO shape, no
#       device and no addrspace, and a node whose `_shape` this file DEFERS -- every
#       RESHAPE, and UNSHARD -- still HAS an interval. As a seventh field, every deferred
#       RESHAPE would defer its interval too, and `gap_ok` is precisely the row that would
#       have noticed: it is the claim "a node whose rules are deferred is NOT answered".
#       Folding it in would have made that claim FALSE for a property that was never
#       deferred, which is the exact failure mode the other six fields avoid.
#     2. FOUR SIGNED-DIVISION ARMS: `CMOD`, `CDIV`, `FLOORDIV`, `FLOORMOD`. `mm.dm.*` is
#       an UNSIGNED restoring divider, and all four need signed `//` -- a FLOOR and not a
#       truncation -- plus the remainder. `divandmod.bend` is the consumer.
#     3. `Ops.CAST` -- `truncate` (dtype.py:297) is half a C-effect seam in `dtype.bend`
#       and a pure def cannot call it. The arm is ABSENT rather than approximated, so a
#       CAST lands on `(dtype.min, dtype.max)`; that is a sound widening and a divergence.
#     4. `self.src[0].buf_uop` (a `while` over five ops) for the LOAD-from-BINARY arm.
#   So this retires the WALL'S NAMING, its i64 arithmetic, `bit_length`, the dtype limits
#   and the op table -- and leaves the walk, four div/mod arms, CAST and the LOAD arm.
# TODO(p3) ops.py:1166 def _sym_fxn             -- `exec` of generated source. P3/P6.
# TODO(p3) ops.py:1196 def alloc                -- `new_buffer`, which is P6's device
#   memory layer.
# TODO(p3) ops.py:1227 def param                -- P6, same reason.
# TODO(p3) ops.py:1400 def __reduce__           -- pickling; the arena is monotone and
#   has no destruction, so there is nothing to pickle.
# TODO(p3) ops.py:1412 def safe_exp2            -- `math.*` in a table; F32 is native in
#   Bend and `F32.exp` exists, so this is a match ladder over the ALU ops. P3.
# TODO(p3) ops.py:1412 def safe_pow             -- the same.
# TODO(p3) ops.py:1427 def exec_alu             -- its tuple operand case is a
#   vectorised ALIKE branch. P3.
# ===========================================================================
#
# WHAT NEXT, in the order the walls fall. **REORDERED BY THIS UNIT'S MEASUREMENT**:
# the old list put `simplify`/`ssimplify` first because it was "the ONE missing piece
# behind six movement shapes", and five of those six turned out not to need it.
#   1. `UOp._min_max` (P3) -- ITS I64 ARITHMETIC IS LANDED AND GATED (72 rows, 21
#      mutations, 20 of them moving rows), and its WIDTH IS SETTLED BY MEASUREMENT.
#      What is left is the op table, the dtype limits and the walk, in that order.
#      It is still the largest unlock in this file: it is what UNSHARD's shape waits
#      on, and `marg`'s `(ssimplify(self),)` arm. NOTHING ELSE IN THIS LIST HAS MOVED,
#      so the order is unchanged apart from this entry getting shorter.
#   2. `UOp.simplify` / `ssimplify` (P3) is `graph_rewrite`, and what it still unblocks
#      is BITCAST's symbolic arm, `as_shape`'s third arm, `axis`, `shard_shape` and
#      `_min_max`'s float arms -- NOT the movement shapes, which all answer. `mv_expsym`
#      is the one row it would change, and it would change it from ABSENT to a shape
#      holding a UOp.
#   3. `UOp._ranges` and `UOp.bool_slice` (P3) need one set algebra over a `List`,
#      and the three set-valued properties are exactly that.
#   4. `UOp.key` (P3) needs a SHA-256 round, which needs rotate and popcount.
#   5. `dtypes.weaks` unblocks `is_virtual` and it is free the moment dtype.bend
#      becomes importable.
#
# The fold's own history, the five bugs it took to get right and the mutation table
# that measures them, is in .agents/slop/notes/bend2-constraints.md under
# "Writing a Kahn worklist".
#
# ===========================================================================
# THE MUTATION TABLE for the src ORDER fix, MEASURED, run both ways.
#
# | mutation | rows that MOVED | what it is testing |
# | --- | --- | --- |
# | M1 `srcs.go`: `Srcs{acc, n}` -> `Srcs{List.reverse(&2, Derived, acc), n}` (the pre-fix state) | `resh_2d` `resh_1d` `resh_noop` `resh_settle` | `self.src` reaches `dt_shape` in ARENA order, so `ss[0]` is `src[0]`. All four print False under M1 and True without it, and `--check-only` STILL PASSES under M1 -- the defect is total, not partial. |
#
# THE REVERT DOWNSTREAM, same edit over the importing gates, and this is the part
# that was not known when the fix landed: `tensor.bend`'s `tn_rop_gap` and
# `movement.bend`'s `reshape_noop` were BUILT to encode this hole as a designed
# disagreement, and both now AGREE with CPython (see the WALL 5 note in `tensor.bend`
# and the "two DIVERGES" note in `.agents/slop/notes/mop-truth3.py`). They read
# `False`/`0` under M1 and `True`/`6` without it. Both files are owned elsewhere and
# NEITHER has been edited: the rows are REPORTED, and the retirement of
# `tn_rop_gap` (which should be DELETED rather than re-asserted, as its own header
# says) and of `movement.bend`'s `reshape_noop` divergence note is their owners' call.
#
# WHAT M1 DOES NOT CATCH, and the row that would: `sized.go` (line 227) has the
# IDENTICAL anti-pattern -- an accumulator built by `List.append` and then finished
# with a `List.reverse` -- and it is a real defect, MEASURED by
# `.agents/slop/notes/probe-sized2.bend`: `sized([2,3])` answers `head=3 last=2`, and
# `pad_to([2,3],3)` answers `2 1` where Python's `(1,)*(max_dim-len(s))+s` is
# `(1,2,3)`. M1-of-`sized` moves NOTHING in this file, in `tensor.bend` or in
# `movement.bend` -- every consumer of it (`is_image_shape`'s `List.last`,
# `reduce_dims`' `drop_n`, `bitcast_dims`' last) is reached only by order-insensitive
# fixtures, which is the same latent hazard this fix just removed one layer of. It is
# left ALONE and REPORTED rather than fixed blind: a fix that moves no row is a claim
# with no measurement behind it, and `sized` is a SHAPE list where the reversal might
# be compensating for a second one. FIXING IT NEEDS A GATE ROW FIRST.
#
# ===========================================================================
# THE MUTATION TABLE for the `sized` ORDER fix, MEASURED, run both ways.
#
# | mutation | rows that MOVED | what it is testing |
# | --- | --- | --- |
# | M2 `sized.go`: `Sized{n, acc}` -> `Sized{n, List.reverse(&2, O.Sint, acc)}` (the pre-fix state) | `sized_order` | a SHAPE list is walked in ops.py's order, so `Sized.s` is the input list and not its mirror, and `pad_to` PREPENDS the ones. `sized_order` prints False under M2 and True without it; the other ten rows and `--check-only` are UNAFFECTED, so the defect is invisible to every fixture the fold gate happens to reach -- that is exactly why it needed its own row. |
#
# THE DOWNSTREAM REVERT, same edit over the importing gates: `tensor.bend` (33 rows),
# `movement.bend` (26) and `spec.bend` (21) move ZERO rows and `--check-only` passes on
# all three, before and after. That is the SAME blind spot M1 had, one layer down, and
# it is a fact about the FIXTURES rather than about the fix: nothing those gates build
# has a shape whose dims are distinguishable in order.
#
# WHAT M2 DID NOT CATCH, because M2 tests ORDER and this is a CONSTANT: `is_image_shape`
# answers False for `(32,32,4)`, and helpers.py:37 says True. `is_image_shape.four` is
# named for the 4 and its body tests `sint_one()`, so it compares the last dim against
# ONE. This is a SEPARATE defect from the one M2 removes -- `List.last` now reads the
# right dim and the comparison is still the wrong one -- and the two masked each other
# on the `(4,32,32)` fixture `probe-sized2` used: mirrored, `List.last` answered 4, and
# 4 against 1 is False, which agrees with CPython's False for the wrong reason.
# MEASURED by `.agents/slop/notes/probe-sized-consumers.bend`. REPORTED NOT FIXED: it is
# out of this fix's scope and it wants its own row, so that M2 keeps moving exactly one.
# `bitcast_dims`, the other order-sensitive consumer, does agree with CPython now --
# `[2,6]` with itemsize 4 into 8 is `[2,3]`, and `[3]` into 8 is the `RuntimeError` the
# fold reports by not answering.
# ===========================================================================
#
# ===========================================================================
# THE MUTATION TABLE for the FIVE MOVEMENT ARMS, MEASURED, run in BOTH lanes.
# `.agents/slop/oracles/fold-mut.py` applies each edit, re-runs both lanes and diffs
# the rows; the table is its output and nothing here is transcribed by hand.
#
# | # | mutation | rows MOVED | what it is testing |
# |---|---|---|---|
# | M1 | `expand_ds`: `both(marg, ps)` -> `both(ps, marg)` | `mv_exp1` `mv_exp23` `mv_expnoop` (3) | `tuple(self.marg) + ps` puts the MARG FIRST. All three node counts stay RIGHT -- which is the point: a count cannot see an order. |
# | M2 | `Tri.le`: PAD's and SHRINK's sums exchanged | `mv_pad1` `mv_pad23` `mv_padr2` `mv_shr1` `mv_shr23` (5) | `o+s<=sz` vs `o+sz<=s`. This is the ONLY mutation that separates the two arms, and it moves five rows across both -- M2 is the whole reason the arms share one walk with a `Bool`. |
# | M3 | `pad_shrink.go`: the `_ _ _` cover arm returns `x` | `mv_padr` (1) | `len(ps) != len(self.marg)`. A localised row: the ONE fixture with a marg longer than the shape. |
# | M4 | `perm_add.go`: drop the no-repeat half | `mv_permrep` (1) | `sorted(marg) == range(n)` needs BOTH halves; `(0,0)` is in range twice and is not a permutation. |
# | M5 | `perm_init`: seed `ps` with `Nil{}` | `mv_perm` (1) | the walk reads the shape, not an empty list. This is the real state of the FIRST version of this arm, which read ABSENT on a valid `(1,0)`. |
# | M6 | `flip_ds.put`: `Nat.is_eq(...)` -> `True{}` | `mv_fliplen` (1) | `len(ps) != len(self.marg)` -- the one reachable half of FLIP's `if`. |
# | M7 | `perm_add.go`: prepend the picked dim instead of appending | `mv_perm` (1) | `tuple(ps[i] for i in marg)` is in ARG order. `(1,0)` over `(2,3)` reads `(3,2)` and the reversed walk reads `(2,3)` -- a real answer that a node count cannot see. |
# | M8 | `pair_ds.put`: `src_dt(0, ss)` -> `S.void()` | `mv_pad1` `mv_pad23` `mv_shr1` `mv_shr23` (4) | `GroupOp.Movement` is `return src[0].dtype`, and "a movement's dtype is always void" is the plausible wrong answer. |
# | M9 | `count_of`: `case O.SU{u}: None{}` -> `Some{0}` | **NOTHING (0)** | **AN UNREACHABLE STATE, not a gap.** `O.SU` is a shape dim for a SYMBOLIC size, and nothing in this tree can mint one: `ops.bend`'s `ParamArg.size` is `Maybe<&2, U32>` with the comment "always a concrete int (never symbolic)" (ops.bend:698-699), and `param_shape.size` reads it as `sint_of(n)`. `rg 'SInt\.uop'` finds the constructor and NO caller -- the only `O.SU{...}` literal in the tree is `schedule/allreduce.bend:392`'s own fixture. So this arm is defence against a reader that does not exist yet, and no fixture can reach it. |
# | M10 | `pad_ds`: `ps` reads `marg.at(1,...)` -- SOURCE and OFFSETS exchanged | **NOTHING (0)** | **AN ALGEBRAIC EQUIVALENCE, not a gap.** PAD's test is `resolve(o+s<=sz)`, which is SYMMETRIC in `o` and `s`: the swap evaluates the same sum. The answer is the SIZES, untouched; and the length check compares against `len(marg) = min(len(o), len(z))`, which the swap cannot satisfy differently (`padr` has `len(ps)=1` and `len(o)=2`, so both spellings fail it). No fixture can move it -- verified by exhausting the four `(ps,o,sz)` one-dim cases. |
# | M10b | ...the same exchange in `shrink_ds` | `mv_shr1` `mv_shr23` (2) | SHRINK's `o+sz<=s` is NOT symmetric, so the same edit DOES move two rows here. M10 and M10b together are the measurement that M10 is an equivalence of the FORMULA and not a blindness of the gate. |
# | M11 | `pad_ds`: `ps` reads `marg.at(2,...)` -- SOURCE and SIZES exchanged | `mv_pad1` `mv_pad23` (2) | the classic shape-arg swap, the one that "moves one row in 67". It moves two of sixteen here, and the `srcops` field is what keeps the two rows identifiable as the same defect. |
# | M12 | `order_arg`: answer `Nil{}` instead of the `ATuple` | `mv_perm` `mv_permrep` `mv_permlen` `mv_flip` `mv_fliplen` (4) | `marg` for PERMUTE and FLIP is `self.arg`, so reading anything else empties the arg. It moves FIVE rows including both FLIPs, which is the half of `GroupOp.Movement` that is about the ARG and not the srcs. |
# | M13 | `expand_ds`: `src_dt(0, ss)` -> `S.void()` | `mv_exp1` `mv_exp23` (2) | the dtype arm of EXPAND specifically, so M8's four PAD/SHRINK rows plus these two cover all five ops. |
#
# **TWELVE OF FOURTEEN MOVE ROWS, AND BOTH ZERO-MOVERS ARE MEASURED EQUIVALENCES** --
# M9 is a state no reader can produce and M10 is a symmetry of PAD's own formula. That
# is the honest reading: the gate cannot see them because there is nothing to see, and
# neither is closed with a row that would encode the equivalence as a check.
#
# WHAT NO MUTATION COULD REACH, and it is the row the gate is THINNEST on: nothing
# here can detect a movement op whose `ATuple` arg is a bool rather than a 0/1 flag.
# `ops.bend:763` spells that arg `List<&2, U32>`, which erases the distinction, and
# `ops.bend` is not this unit's file. See `flip_ds`'s header: CPython's own
# `isinstance(x, bool)` is measured to be unreachable as a rejection anyway.
# ===========================================================================
# ===========================================================================
# THE MUTATION TABLE for `_min_max`'s OP TABLE, MEASURED.
# `.agents/slop/fold-lift-mutate.py` applies each edit, re-runs, and diffs whole
# `name=value` lines against a baseline captured from the SAME file in the SAME state; the
# table is its output and nothing here is transcribed by hand.
#
# | # | mutation | rows MOVED | what it is testing |
# |---|---|---|---|
# | L1 | a no-op edit (whitespace) | **0** | **THE CONTROL.** A well-formed edit that changes nothing moves nothing, which is what makes the other 0s interpretable. An earlier version of this harness had four "neutral" mutations that were NOT no-ops -- they appended a line to a def body and took 276 rows with them -- and one that referenced an undefined name. All five were REMOVED rather than counted, because a "moved every row" line in a mutation table is a harness bug wearing a result's clothes. |
# | L3 | another no-op edit | **0** | the control, twice, on the block gate itself |
# | L41 | the movement passthrough rewritten as a `src2` spelling of itself | **0** | the control for L29: the same answer reached differently really does move nothing, so L29's 11 rows are the SWAP and not the spelling |
# | L2 | `mm.MM2.get`: the fall-through inverted, so a binary op with no arm answers the dtype limits and one WITH an arm does too | 90 | **THE FALL-THROUGH IS THE WHOLE OF RULE 1.** `Ops.CMPEQ` is binary, is on a non-float dtype, and has NO arm -- so Python falls through to `(dtype.min, dtype.max)` and so must this. Getting it wrong is invisible on every op that HAS an arm, which is 12 of the 13 in the block. |
# | L42 | `bnd.same`: `Bool` equality as exclusive-or rather than its negation | 51 | `Bool` HAS NO `is_eq` IN BEND 2.0.34 and equality is the negation of `xor`. Getting it backwards inverts every sign test in the section at once. |
# | L6 | ADD answered as SUB | 9 | the nine in-window ADD rows; the saturation rows are excluded because saturation makes add and sub agree on them |
# | L8 | the sign of a same-sign SUM negated | 14 | the sign is the ADDENDS' sign, and a sum of two negatives is the case that shows it |
# | L9 | the sign of a DIFFERENCE decided by the wrong comparison | 14 | a difference's sign is decided by WHICH MAGNITUDE IS LARGER, and the pair is `(SNok{True,...}, SNok{False,...})` either way -- the ordering of the two arms is the whole test. `lf_range0`/`lf_range4` are in the list because RANGE subtracts one. |
# | L10 | **the signed order collapsed to two cases** | 9 | **THE BIGGEST SINGLE FINDING IN THE GATE, AND IT WAS FOUND BY THE GATE.** "if `a` is negative compare the magnitudes backwards" is wrong for a negative `a` against a non-negative `b`, where the answer is always less and not a magnitude comparison. This spelling made `max(-3, 4)` answer `-3` and `cmplt(-3, 4)` answer `False` on 53 of the gate's 123 rows before it was found, and it typechecks and terminates throughout. |
# | L11 | `bnd.min` and `bnd.max` exchanged | 14 | the AND arm is `min(s0_vmax, ...)` and STACK is a `min`/`max` fold, so the two are used by four arms and one swap reaches all of them |
# | L12 | the canonical zero tests only the HIGH word | 15 | `0 * -5` builds `SNok{True, 0}` -- `-0`, the same Python int as `0` and a DIFFERENT `Bnd`, so the gate string differs. The `2**31` and `-2**31` addends are in the list because that is where a wide negative magnitude first appears. |
# | L16 | the AND arm's mask WIDTH and masked VALUE exchanged | 3 | width from `s1` and mask on `s0`, which is the plausible reading and gives `2**31 & 7` where CPython gives 7. **Three rows and not one is the measurement that the family needs its `2**31` and `2**40` fixtures**: with both srcs small the two spellings are the same function. |
# | L17 | the AND arm's `min(s0_vmax, ...)` answered as `max` | 6 | an UNSOUND upper bound, which is the direction that matters: a masked value can then exceed the source's own maximum |
# | L20 | SHR's UPPER half answered as a shift LEFT | 6 | both are a shift of the same amount and only the PAIR differs, so a fixture whose two bounds are equal -- which every CONST fixture is -- catches only one of the two |
# | L22 | the `+ 1` for a non-zero remainder lands in the HIGH word | 2 | off by `2**32` on every negative ODD right-shift, which is the recorded "an even fixture hides an odd defect" family: `-8 >> 2` and `255 >> 4` are unmoved and `-9 >> 1` and `-1 >> 3` are not |
# | L24 | the shift AMOUNT read as a bit WIDTH | 6 | `1 << 3` becomes `1 << 2`. This is why `bnd.shamt` is a SEPARATE def from the AND arm's mask reader: they are one line apart and they are different functions. Found by this gate on 22 rows. |
# | L25 | Python's `or` on ints exchanged with `and` | 2 | `0 or 1` is `1` and `1 and 0` is `0`, so the two are a pick each and differ on every pair -- but only two of the four `orb_*` rows move, because `or` is commutative and two of the four fixtures have equal srcs |
# | L27 | the `bool`-dtype AND arm REMOVED | 13 | **THE REACHABILITY DEFECT THIS GATE FOUND.** `Ops.AND` has TWO arms -- the integer mask and the `bool` dtype's `and` -- and the second is reachable exactly when the first is not. Two `case O.OpsAND{}` arms make the second dead, and an integer arm returning `None` skips straight past a `case _:`. Every `andb_*` row answered `bool`'s own limits until the dispatch was moved into ONE def over the dtype's class. L27 is the pre-fix state, measured. |
# | L29 | the movement passthrough reads `src[1]` | 11 | eleven of the twelve Movement/INDEX-family ops all pass `src[0]` through, and reading `src[1]` is a real answer on every one of them. A node count cannot see it and `srcops` cannot either: the src SEQUENCE is unchanged. |
# | L30 | WHERE reads `src[0]`/`src[1]` | 3 | WHERE's operands are `src[1]` and `src[2]` -- the CONDITION is skipped -- so reading from zero puts the condition's own bound into the interval |
# | L31 | RANGE/SPECIAL's `(src[0] - 1).vmax` read as `src[0].vmax` | 6 | the `1` is a REAL UOp -- a SUB node -- and dropping it is off by one on every RANGE and every SPECIAL |
# | L33 | STACK's fold seed exchanged | 4 | `min`/`max` over a generator start from nothing, and the seed is the IDENTITY pair rather than a `U32` sentinel, which is the recorded `max`/`min` sentinel trap: `0xFFFFFFFF` wins every comparison |
# | L34 | the `Invalid` CONST answered as `0` | 1 | `self.val is not Invalid` is the arm's gate and a CONST can hold it |
# | L35 | the NaN test dropped | 1 | `not math.isnan(v)` IS `v == v` and `F32.is_eq` is IEEE, so `F32.is_eq(f, f)` IS the NaN test. The row is the only thing that can see it, because `F32.div(0, 0)` is the one NaN Bend can build and no other fixture contains one. |
# | L36 | PAD over a float source saturates instead of comparing in `F32` | 2 | sound, and wrong for CPython, which is why the float bound is the ONE place the two classes meet: `min(1.5, 0)` is the INTEGER `0`. **These two rows are a FIXTURE THIS UNIT ADDED to close an earlier zero**, and they are the reason `bnd.lt`'s `case _:` -- the mixed Int/Flt arm, which answers `False` and is wrong in general -- is confined to one arm of PAD. |
# | L38 | a dtype WIDTH off by one | 1 | `bl_dt_int32`: the twenty dtype rows see a `2**32 - 1` maximum, and only `int32` moves because the other widths are powers of two where the off-by-one is absorbed |
# | L40 | the `Defines` arm narrowed to PARAM and BUFFER | 3 | `GroupOp.Defines` names PARAM, BUFFER and ALLOC, and the three `*_alloc` rows are a FIXTURE THIS UNIT ADDED to close an earlier zero |
# | L4 | the binary block entered on a NON-BINARY op | **0** | **A THEOREM, with the proof in one sentence: `mm.bin.arm`'s dispatch is a TOTAL match over the op constructors, and every constructor it names is in `GroupOp.binary`.** Entering the block early therefore finds no case to fire and falls through to the same default, so the conjunct is redundant for every op that exists and is defence only against a future one. No fixture can separate it and none should be written. |
# | L7 | SUB's two halves NOT crossed | **0** | **A FIXTURE REQUEST, and the request is not cheap: every fixture in this gate has `CONST` srcs, so `s0.lo == s0.hi` and `s1.lo == s1.hi` and the crossing is invisible.** This is the price of gating the TABLE without a WALK, and it is the same price as L13, L14, L15 and L19. All five need a src whose bounds DIFFER, which is a `WHERE` or an `ADD` node -- i.e. the walk. **This is the single strongest argument for building the walk next.** |
# | L13 | MUL's `min(vals)`/`max(vals)` exchanged | **0** | the four products of two CONSTs are the SAME number, so min and max agree. Fixture request, same reason as L7. |
# | L14 | CMPLT's first half reads `lo` instead of `hi` | **0** | same: `s0_vmax < s1_vmin` and `s0_vmin < s1_vmin` are the same predicate when the srcs are CONSTs. Fixture request. |
# | L15 | CMPNE's second disjunct reads `lo` instead of `hi` | **0** | same, and worse: the intervals touch in the wrong direction only when the two bounds differ. Fixture request. |
# | L19 | XOR's `~vmax, ~vmin` NOT swapped | **0** | same: the negation is monotone so the halves only trade when the src bounds differ. Fixture request. |
# | L18 | the AND gate's `s1_vmax >= 0` dropped | **0** | **NOT A FIXTURE REQUEST -- IT IS UNREACHABLE, and that is the finding.** Measured: `UOp(Ops.AND, src=(CONST(5), CONST(-1)))` has dtype `weakint`, not `int32`, because `promo_dtype` promotes an `int` against a negative `int` past the signed lattice; and `weakint`'s limits are 800 bits, so the answer leaves the window before the gate is consulted. The conjunct is a dtype-promotion artefact: the state it refuses does not exist as an INTEGER, so no integer fixture can reach it and no fixture of any kind can separate it from its absence. |
# | L23 | the shift amount's WIDTH GUARD off by one | **0** | **UNFIXABLE IN THIS REPRESENTATION.** The guard is `bit_length(k) > 64`, i.e. `k >= 2**64`, and a shift amount reaches Bend as a `Nat`, which REFUSES past 2**48-1. So the guard's boundary cannot be expressed as a fixture and never fires. Kept because it is one comparison and it is the honest place for the `Nat` cap to be recorded. |
# | L26 | the `bool`-dtype AND's two srcs swapped | **0** | **A THEOREM: `and` is commutative, and so is the `bool` interval built from it, so the two spellings are the same function over every possible answer.** A test that cannot fail is not a test. (`or_bool`'s srcs are commutative too and that is why no `orb_*` src-swap mutation is even in the table.) |
# | L39 | PAD and CONST arms exchanged | **0** | **A THEOREM: the two arms are keyed on DIFFERENT op constructors, and a `match` cannot reach the second by matching the first.** The ORDER of those two arms is therefore not load-bearing -- unlike PAD's position INSIDE the `GroupOp.Movement` arm, which is, because PAD is reachable by either pattern and Python tests it first. |
#
# **NINE OF THE THIRTY-FIVE MOVE NOTHING, AND EVERY ONE IS CLASSIFIED**: three are the
# harness's own controls (L1, L3, L41), five are FIXTURE REQUESTS that all need a src whose
# bounds differ and therefore the WALK (L7, L13, L14, L15, L19), three are THEOREMS about a
# total dispatch, about commutativity, and about disjoint `match` patterns (L4, L26, L39),
# one is UNREACHABLE by dtype promotion (L18), and one is UNFIXABLE because `Nat` caps a
# shift amount below the guard's boundary (L23). **No zero is closed with a row that would
# encode the equivalence as a check.**
#
# THE FIVE FIXTURE REQUESTS ARE THE HEADLINE FOR THE NEXT UNIT. They are all the same
# request, they are all cheap ONCE A WALK EXISTS, and between them they cover the four
# properties of an INTERVAL -- that a difference's halves cross, that a product's extremes
# are taken over four values and not two, that a comparison reads the far end of one
# interval against the near end of the other, and that a monotone map trades them. An
# all-CONST gate cannot see any of it, because on a CONST interval every one of those
# properties is an identity.
# ===========================================================================
