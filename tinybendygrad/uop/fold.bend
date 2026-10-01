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
    case S.Dt{10, 8, S.CFloat{}, "float8_e4m3"}: 493568
    case S.Dt{10, 8, S.CFloat{}, "float8_e4m3fnuz"}: 495616
    case S.Dt{11, 8, S.CFloat{}, "float8_e5m2"}: 499712
    case S.Dt{11, 8, S.CFloat{}, "float8_e5m2fnuz"}: 507904
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
  match ws:
    case Nil{}: acc
    case w <> t: wmma_shapes.go(t, List.append(&2, Sized, acc, [drop_last(w)]))

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
  match ss:
    case Nil{}: acc
    case d <> t: dts_of.go(t, List.append(&2, S.Dt, acc, [Derived.dt(d)]))

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
def shapes_of.go(ss: List<&2, Derived>, acc: Maybe<&2, Shapes>) -> Maybe<&2, Shapes>:
  match ss:
    case Nil{}: acc
    case d <> t: shapes_of.go(t, shapes_of.acc(Derived.shape(d), acc))

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
  match ss:
    case Nil{}: acc
    case d <> t: dims_of.go(t, List.append(&2, O.Sint, acc, shape_of(d)))

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
def first_dev.go(ss: List<&2, Derived>, acc: Maybe<&2, S.Dev>) -> Maybe<&2, S.Dev>:
  match ss:
    case Nil{}: acc
    case d <> t: first_dev.go(t, Maybe.or(&2, S.Dev, acc, Derived.dev(d)))

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

    # THE DEFERRED OPS. Each is an arm `dtype_from_uop` or `_shape` reaches through
    # a rule this file does not port, so the fold does not answer the node. ops.py
    # has three such comments here: "special (terrible) case for RESHAPE on NOOP",
    # "movement ops change the shape. NOTE: ssimplify is required because the shape
    # needs to be canonical for broadcasting and same shape checking", and "UNSHARD
    # marker has no shape". The list is closed: every other op has an arm above,
    # which is what makes the match total without Python's closing `raise
    # RuntimeError(f"no dtype for {op} with arg {arg}")`.
    case O.OpsCUSTOM{}: None{}        # `arg[1]`, and the arena's CUSTOM arg is a str
    case O.OpsCUSTOMI{}: None{}       #   (ops.bend's `Arg`), not the `(str, DType)`
    case O.OpsSTAGE{}: None{}         #   pair. P3: that is a change to `Arg`.
    case O.OpsPERMUTE{}: None{}       # `marg` -> `as_shape` -> `ssimplify`
    case O.OpsEXPAND{}: None{}        # `marg` -> `as_shape` -> `ssimplify`
    case O.OpsPAD{}: None{}           # `marg` -> `zip` -> `ssimplify`
    case O.OpsSHRINK{}: None{}        # `marg` -> `zip` -> `ssimplify`
    case O.OpsFLIP{}: None{}          # `marg` -> `as_shape` -> `ssimplify`
    case O.OpsUNSHARD{}: None{}       # `self.src[1:][...].vmax`, so `_min_max` too

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
    row("sized_order", t_sized_order())

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
# TODO(p3) ops.py:808  def as_shape             -- CONST and STACK only; a shape made of
#   CONSTs is answerable and a shape made of uops needs `ssimplify`. It is
#   `marg`'s first half. ops.py asks why the cached property here makes
#   external_uop_gc fail; unanswered here too.
# TODO(p3) ops.py:814  def marg                 -- the three arms are `as_shape`,
#   `zip(as_shape, as_shape)` and `self.arg`, and two of the three need `ssimplify`.
#   This is the ONE missing piece behind RESHAPE, EXPAND, PAD, SHRINK, PERMUTE and
#   FLIP.
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
# TODO(p3) ops.py:1100 def vmin                 -- `self._min_max[0]`, so it is `_min_max`.
# TODO(p3) ops.py:1102 def vmax                 -- `self._min_max[1]`, so it is `_min_max`.
# TODO(p3) ops.py:1104 def _min_max             -- the wall is arithmetic, not the fold.
#   It is a fold over the same pair, but PyConst is `int|float|bool|Invalid` and
#   `helpers.bend` has `i64_add`, `i64_sub` and `i64_cmp` and NOT `i64_mul`,
#   `i64_div`, `i64_mod` or an F32 `min`/`max`; and the arms read
#   `self.dtype.min`/`self.dtype.max` (dtype.bend), `truncate` (dtype.py:297, half of
#   which is the C-effect seam) and `self.src[0].buf_uop` (a `while` over five ops).
#   P3, and it is the biggest single piece left in this file's half of ops.py.
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
# WHAT NEXT, in the order the walls fall.
#   1. `UOp.simplify` / `ssimplify` (P3) unblocks six movement shapes, BITCAST's
#      symbolic arm, `marg`, `as_shape`, `axis`, `shard_shape` and `_min_max`'s
#      float arms. It is the largest single unlock in this file.
#   2. `UOp._ranges` and `UOp.bool_slice` (P3) need one set algebra over a `List`,
#      and the three set-valued properties are exactly that.
#   3. `UOp._min_max` (P3) needs four I64 arithmetic helpers in helpers.bend and
#      the dtype limits from dtype.bend.
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
