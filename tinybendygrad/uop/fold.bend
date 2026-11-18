# fold.bend -- the derived properties of tinygrad/uop/ops.py, as ONE topological fold over
# `ops.bend` builds the arena: a UOp is a `U32` index into an append-only `List<Node>`, so
# THE FIX is the shape `toposort` already has in `ops.bend`: ONE def that walks the graph in
# topological order, so a node is answered only after every node it reads is. Python's
# `recursive_property` (ops.py:211) replaces `functools.cached_property` in recursive UOp
# dtype and shape are answered TOGETHER, as one `DtShape`, because they read each other --
# `marg` for PERMUTE is `self.arg` (ops.py:236 symbol=arg), the arena's `ATuple` of plain
# pad and shrink are one walk with a `Bool`, not two arms, because their checks differ only in
# THE `ssimplify` WALL IS CLOSED, and it was TWO defects and not one. `as_shape`'s
# WHAT IS LEFT, NAMED, because a closed wall with an unnamed remainder is a lie: a PARAM or
# SPECIAL whose interval is EMPTY (`vmin > vmax`) or NEGATIVE is refused -- ops.py:407's
# THE ARENA IS A DAG BY CONSTRUCTION -- `UOp.make` only ever names src indices already in the
# WHAT A PYTHON `raise` BECOMES, uniformly: the node is NOT answered. One rule at every
# THE COST, accepted rather than worked around:
# `_min_max` has moved. The i64 arithmetic landed first, then the WIDTH was settled by
# measurement (a sign bit plus an UNSIGNED 64-bit magnitude, because `uint64.max` = 2**64-1
# does not fit a signed word and `Nat` refuses past 2**48-1), and that left three pieces:
#   1. `int(x).bit_length()` (ops.py:1111) -- SOLVED, NOT ROUTED AROUND. A zero test cannot
# what the walk's price is, measured rather than assumed. Its dtype comes from the MAIN
# THE LATTICE IS HOISTED, with a notice. `promo_dtype` needs `least_upper_dtype`
# (tinygrad/dtype.py:193), which `./../dtype.bend` already has in a form this file cannot
# `ranges` need "one set algebra over a `List`", as though the algebra were the wall. It is
# `is_image_shape` IS FIXED, and the fix is a CONSTANT. It compared the last dim against

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./ops.bend as O

# THE PROMOTION LATTICE -- tinygrad/dtype.py:180-204, hoisted. See the header.
# dtype.py spells `least_upper_dtype` as
# The twenty dtypes are told apart by LITERAL record patterns, which is why these

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
    # the three FP8 names are `Dt`'s fourth field and not its priority: `fp8e4m3` and
    case S.Dt{10, 8, S.CFloat{}, "fp8e4m3"}: 493568
    case S.Dt{10, 8, S.CFloat{}, "fp8e4m3fnuz"}: 495616
    case S.Dt{11, 8, S.CFloat{}, "fp8e5m2"}: 499712
    case S.Dt{11, 8, S.CFloat{}, "fp8e5m2fnuz"}: 507904
    case S.Dt{12, 16, S.CFloat{}, _}: 425984
    case S.Dt{13, 16, S.CFloat{}, _}: 458752
    case S.Dt{14, 32, S.CFloat{}, _}: 393216
    case S.Dt{15, 64, S.CFloat{}, _}: 262144
    case _: 0

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

# the index of the lowest set bit. `m` is never 0 for a non-void dtype.
# THE OLD COMMENT HERE CLAIMED "every non-void mask has bit 0" and was FALSE: it does
# not, and `promo_lattice` says why. `_get_recursive_parents(bool)` is ALL NINETEEN,
# but `_get_recursive_parents(d)` for every OTHER d is that set MINUS bool, because
# bool is nobody's child -- `promo_lattice` (dtype.py:180-187) has `bool: [weakint]`
def lowest(+m: U32) -> Nat:
  U32.log2(U32.and(m, U32.sub(0, m)))

def least_upper.pick(ok: Bool, +m: U32) -> Maybe<&1, S.Dt>:
  match ok:
    case True{}: None{}
    case False{}: Some{dt_by_rank(lowest(m))}

# ... ANY pair, so the test is on BOTH masks. It was on `ma` alone until 2026-10-03,
# which made the meet NON-COMMUTATIVE: `least_upper.of(void, x)` answered `void` while
# `least_upper.of(x, void)` answered `bool`, because a zero mask on the RIGHT decodes
# as `lowest(0) = U32.log2(0) = 0` and `dt_by_rank(0)` is `bool`. dtype.py:194 is
def least_upper(+ma: U32, +mb: U32) -> Maybe<&1, S.Dt>:
  least_upper.pick(Bool.or(U32.is_zero(ma), U32.is_zero(mb)), U32.and(ma, mb))

def least_upper.of(a: S.Dt, b: S.Dt) -> S.Dt:
  Maybe.default(&1, S.Dt, least_upper(promo_mask(a), promo_mask(b)), S.void())

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
# the `CWeakFloat` arm is missing here, and it was a real defect.  CPython's
# `is_float` is `dt.kind == 'f'` and a WEAK FLOAT's kind is 'f', so
# `least_upper_float(weakfloat)` IS `weakfloat` -- but the `CFloat` arm here is the
# STRONG float class, so a weakfloat fell through to the `case _` arm and came back
# `float32`.  MEASURED, 2026-10-22: `mixin/elementwise.bend`'s `asin` built
def least_upper_float.cls(cls: S.Cls, dt: S.Dt) -> Maybe<&1, S.Dt>:
  match cls:
    case S.CWeakInt{}: Some{S.weakfloat()}
    case S.CFloat{}: Some{dt}
    case S.CWeakFloat{}: Some{dt}
    case _: least_upper(promo_mask(dt), promo_mask(S.single()))

def least_upper_float(+dt: S.Dt) -> S.Dt:
  Maybe.default(&1, S.Dt, least_upper_float.cls(S.Dt.cls(dt), dt), S.void())

def unary_dt.go(bad: Bool, dt: S.Dt) -> S.Dt:
  match bad:
    case True{}: S.boolean()
    case False{}: least_upper_float(dt)

# THE SHAPE ALGEBRA. `sint` is ops.py:1925's `int|UOp` and `ops.bend` already

def one_i64() -> H.I64:
  H.i64_of_i32(1)

def bcast_dim.is_uop_or_ne_1(s: O.Sint) -> Bool:
  match s:
    case O.SU{u}: True{}
    case O.SI{i}: Bool.not(O.eq_i64(i, one_i64()))

# a small count as a `sint`. Every count that reaches a shape is a dim or a length, so it
# is under 2^31 and `i64_of_i32`'s sign extension is exact.
def sint_of(+n: U32) -> O.Sint:
# `ops.bend`'s `SInt.of`, written as its own body: a `Type.of` def does not resolve
# through a module alias, so the constructor is spelled here.
  O.SI{H.i64_of_i32(n)}

def sint_one() -> O.Sint:
  sint_of(1)

# a count and the list it counts, as one value: Bend spends a list when it reads it, so a
# fold step carrying both needs a Data record. `Sized.n` and `Sized.s` are accessors
# because Bend has no projections.
type Sized is Data:
  Sized{n: Nat, s: List<&2, O.Sint>}

def Sized.n(x: Sized) -> Nat:
  match x:
    case Sized{n, s}: n

def Sized.s(x: Sized) -> List<&2, O.Sint>:
  match x:
    case Sized{n, s}: s

# `List.append` is `xs ++ ys` (base.bend:931), so this accumulator is ALREADY in here turned
# a list already in ops.py's order into its own mirror, which every COUNT survived --
# `Sized.n` is unaffected -- and every positional read did not. Same anti-pattern, same
# defect, one layer down from `srcs.go`.
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

def pad_to(+x: Sized, +m: Nat) -> Sized:
  sized(List.append(&2, O.Sint, ones.go(Nat.sub(m, Sized.n(x)), Nil{}), Sized.s(x)))

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

# `_shape` (ops.py:353-357). `image` wins, exactly as upstream's
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

def param_shape.pa(+pa: O.ParamArg, size: Maybe<&2, U32>) -> List<&2, O.Sint>:
  param_shape.of.img(O.ParamArg.image(pa), size)

def param_shape.of(arg: O.Arg, size: Maybe<&2, U32>) -> List<&2, O.Sint>:
  match arg:
    case O.AParam{pa}: param_shape.pa(pa, size)
    case _: Nil{}

def param_shape(+ar: O.Arena, self: U32, arg: O.Arg) -> List<&2, O.Sint>:
  param_shape.of(arg, O.ParamArg.size(ar, self))

# `SInt` equality. A `SU` is an arena index, so the comparison there is the identity
# `UOp.__eq__` has: UOps are hash-consed, so structurally identical UOps are the same
# object and equality can be identity.
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
def is_image_shape.four(last: Maybe<&2, O.Sint>) -> Bool:
  match last:
    case Some{d}: eq_sint(d, sint_of(4))
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

def take_n(xs: List<&2, O.Sint>, +n: Nat) -> List<&2, O.Sint>:
  List.take(&2, O.Sint, xs, n)

def drop_last(+x: Sized) -> Sized:
  sized(take_n(Sized.s(x), Nat.sub(Sized.n(x), 1n)))

def wmma_shapes.go(ws: List<&2, Sized>, acc: List<&2, Sized>) -> List<&2, Sized>:
  List.foldl(~&2, ~Sized, ~List<&2, Sized>, (a: List<&2, Sized>) => (w: Sized) => List.append(&2, Sized, a, [drop_last(w)]), ws, acc)

def drop_n(xs: List<&2, O.Sint>, +n: Nat) -> List<&2, O.Sint>:
  List.drop(&2, O.Sint, xs, n)

def is_empty(xs: List<&2, O.Sint>) -> Bool:
  match xs:
    case Nil{}: True{}
    case _ <> _: False{}

# the `if ok then Some{x} else None` of this file, hoisted. Bend has no `if`, and a fold
# that filters the same way in ten places should say it once.
def some_if(a, -A: Kind(a), ok: Bool, x: A) -> Maybe<a, A>:
  match ok:
    case True{}: Some{x}
    case False{}: None{}

# THE THREE ARITHMETIC DEFS, IN I64, and the product is what makes it exact. `n` is the
# THE QUOTIENT IS `O.SI{H.i64_div(...)}` AND NOT `sint_of(...)`, and that is the THIRD
def bitcast_dims.put.of(+n: H.I64, +out: U32, +x: Sized) -> Maybe<&2, List<&2, O.Sint>>:
  some_if(&2, List<&2, O.Sint>, H.i64_is_zero(H.i64_mod(n, H.i64_of_i32(out))),
    List.append(&2, O.Sint, Sized.s(drop_last(x)), [O.SI{H.i64_div(n, H.i64_of_i32(out))}]))

def bitcast_dims.put(i: H.I64, out: U32, inp: U32, ps: List<&2, O.Sint>) -> Maybe<&2, List<&2, O.Sint>>:
  bitcast_dims.put.of(H.i64_mul(i, H.i64_of_i32(inp)), out, sized(ps))

# `if isinstance(ps[-1], int) and (ps[-1]*input_sz) % output_sz: raise RuntimeError
# fixed (2026-10-05). the port truncated to U32 *three* times, not once, and the
# THREE HAVE DIFFERENT BOUNDARIES, so the single threshold `dim*inp < 2**32` that used
#   L1  `H.lo32(i)`      the DIM ITSELF.      wrong from `dim >= 2**32`.
# L3 was not in the previous census at all. `.agents/slop/trigger/bc-oracle.py` modelled
# THE NEW WINDOW IS `dim*inp < 2**63`, NOT `2**64`, and that is `helpers.bend`'s own
# a negative dim is not part of this gap: upstream refuses to build one at all ("shape
def bitcast_dims.scale(d: O.Sint, out: U32, inp: U32, ps: List<&2, O.Sint>) -> Maybe<&2, List<&2, O.Sint>>:
  match d:
    case O.SU{u}: None{}
    case O.SI{i}: bitcast_dims.put(i, out, inp, ps)

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

def bitcast_dims(m: Maybe<&2, List<&2, O.Sint>>, +out: U32, +inp: U32) -> Maybe<&2, List<&2, O.Sint>>:
  bitcast_dims.go(m, out, inp, U32.is_eq(out, inp))

def bcast_dim.rest(+x: O.Sint, t: List<&2, O.Sint>) -> Maybe<&2, O.Sint>:
  match t:
    case Nil{}: Some{x}
    case y <> _: some_if(&2, O.Sint, eq_sint(x, y), x)

# `ret.append(rest[0] if rest else 1)`, and `len(rest) > 1` is the IndexError. A PAIR is all
# this needs -- two kept sizes disagree exactly when they are unequal.
def bcast_dim.pair(ks: List<&2, O.Sint>) -> Maybe<&2, O.Sint>:
  match ks:
    case Nil{}: Some{sint_one()}
    case x <> t: bcast_dim.rest(x, t)

def add_if(a, -A: Kind(a), ok: Bool, x: A, acc: List<a, A>) -> List<a, A>:
  match ok:
    case True{}: List.append(a, A, acc, [x])
    case False{}: acc

def bcast_dim.kept(+s: O.Sint, acc: List<&2, O.Sint>) -> List<&2, O.Sint>:
  add_if(&2, O.Sint, bcast_dim.is_uop_or_ne_1(s), s, acc)

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

def bcast.pair(xs: List<&2, O.Sint>, y: Sized, acc: List<&2, O.Sint>) -> Maybe<&2, List<&2, O.Sint>>:
  bcast.pair.of(xs, Sized.s(y), acc)

def bcast.go(als: List<&2, Sized>, acc: List<&2, O.Sint>) -> Maybe<&2, List<&2, O.Sint>>:
  match als:
    case Nil{}: Some{acc}
    case a <> t:
      Maybe.bind(&2, List<&2, O.Sint>, List<&2, O.Sint>, bcast.pair(acc, a, Nil{}),
        acc2 => bcast.go(t, acc2))

# the zip of the per-dim loop. `acc` is the dims answered so far, so pairing it with
def bcast.first(als: List<&2, Sized>) -> Maybe<&2, List<&2, O.Sint>>:
  match als:
    case Nil{}: None{}
    case a <> t: bcast.go(t, Sized.s(a))

def Kahn.seed.keep(deg: U32, k: U32, acc: List<&2, U32>) -> List<&2, U32>:
  add_if(&2, U32, U32.is_zero(deg), k, acc)

# _broadcast_shape -- ops.py:80, the `zip(*_align_left(*shapes))` fold.
#   if all_same(shapes): return shapes[0]
# `all_same(shapes): return shapes[0]` is not a fifth rule: right-aligning a set of
def bcast_shape(m: Maybe<&2, Shapes>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case None{}: None{}
    case Some{sh}: bcast.first(_align_left(sh))

# THE ANSWER: one record per resolved node, carrying the six properties that fit
# without `simplify` or the movement shape algebra. `shape` is Python's own
# `tuple[sint, ...]|None`, `dev` its `str|tuple[str, ...]|None`, `addr` its
# `AddrSpace|None`, `base` ops.py:785's node as an index, and `ended`
# A `Data` record and not six parameters because a Bend `List` is spent when read,

type Derived is Data:
  Derived{dt: S.Dt, shape: Maybe<&2, List<&2, O.Sint>>, dev: Maybe<&2, S.Dev>,
    addr: Maybe<&2, S.Addr>, base: U32, unbase: U32, sbase: U32, ended: List<&2, U32>}

# `DtShape` is `(DType, tuple[sint, ...]|None)` as a record, which is the whole of why
# dtype and shape are answered together.
type DtShape is Data:
  DtShape{dt: S.Dt, shape: Maybe<&2, List<&2, O.Sint>>}

# The two constructors every arm of the ladder ends in, hoisted: a real shape, and
# the `None` arm answers `(dt, None)`, and that is the whole fix. `dt_of` builds the pair
# upstream's two ladders answer together, and `(dtype, None)` is a real pair: `_shape`'s
# passthrough is `return self.src[0]._shape` (ops.py:377) and NOOP's is
# it was the outer `None`, and the outer `None` is port-only: `derived.put` passes it on
# and `Kahn.ans.of` turns it into A MISSING TABLE ENTRY, so the node reads `?` in BOTH
# columns -- a hole CPython cannot print -- rather than reading `R`. `late()` below is this
# same pair spelled once, for the dtype that is void by name.
# MEASURED 2026-10-18, `graphcmp.py diff --graph loop`: `?=32` (16 nodes) -> 0, because
def dt_of(dt: S.Dt, m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, DtShape>:
  match m:
    case Some{ds}: Some{DtShape{dt, Some{ds}}}
    case None{}: Some{DtShape{dt, None{}}}

def param_ds.shape(dt: S.Dt, arg: O.Arg, size: Maybe<&2, U32>) -> Maybe<&2, DtShape>:
  dt_of(dt, Some{param_shape.of(arg, size)})

def param_ds.pick(m: Maybe<&1, S.Dt>, arg: O.Arg, size: Maybe<&2, U32>) -> Maybe<&2, DtShape>:
  match m:
    case Some{dt}: param_ds.shape(dt, arg, size)
    case None{}: None{}

def bitcast_ds.shape(dt: S.Dt, out: U32, inp: U32, m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, DtShape>:
  Maybe.bind(&2, List<&2, O.Sint>, DtShape, bitcast_dims(m, out, inp), ds => dt_of(dt, Some{ds}))

# a `raise` on `ok` guarding the same pair, so the guard is a whole extra answer and
def dt_of_if(ok: Bool, dt: S.Dt, m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, DtShape>:
  match ok:
    case True{}: dt_of(dt, m)
    case False{}: None{}

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

# the `return ()` shape, which RANGE, SPECIAL, GETADDR, CONST, a STACK of no srcs, INS and
# a non-void CALL all answer
def dt_of_nil(dt: S.Dt) -> DtShape:
  DtShape{dt, Some{Nil{}}}

# THE WALK'S TWO RESULTS, as one value, for the same reason as `Table`: the hit is read
# once per src and both the accumulator and the flag need it.
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
  Derived{S.void(), None{}, None{}, None{}, 0, 0, 0, Nil{}}

def Kahn.get.hit(ok: Bool, d: Derived, acc: Maybe<&2, Derived>) -> Maybe<&2, Derived>:
  match ok:
    case True{}: Some{d}
    case _: acc

def Derived.dt(d: Derived) -> S.Dt:
  match d:
    case Derived{dt, shape, dev, addr, base, unbase, sbase, ended}: dt

# `self.src[k]`, as the fold answered it. Six wrappers over the same `List.get`, because
# every arm reads at most two or three of them and naming the property is what makes an
# arm readable.
def src_dt(k: U32, ss: List<&2, Derived>) -> S.Dt:
  Derived.dt(Maybe.default(&2, Derived, List.get(&2, Derived, ss, U32.to_nat(k)), Derived.unknown()))

def rlike(ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of(src_dt(0, ss), Some{Nil{}})

def dts_of.go(ss: List<&2, Derived>, acc: List<&2, S.Dt>) -> List<&2, S.Dt>:
  List.foldl(~&2, ~Derived, ~List<&2, S.Dt>, (a: List<&2, S.Dt>) => (d: Derived) => List.append(&2, S.Dt, a, [Derived.dt(d)]), ss, acc)

def fold.dt.of(m: Maybe<&2, Derived>) -> Maybe<&2, S.Dt>:
  match m:
    case Some{d}: Some{Derived.dt(d)}
    case None{}: None{}

def Derived.shape(d: Derived) -> Maybe<&2, List<&2, O.Sint>>:
  match d:
    case Derived{dt, shape, dev, addr, base, unbase, sbase, ended}: shape

def src_shape(k: U32, ss: List<&2, Derived>) -> Maybe<&2, List<&2, O.Sint>>:
  Derived.shape(Maybe.default(&2, Derived, List.get(&2, Derived, ss, U32.to_nat(k)), Derived.unknown()))

# THE SRC LIST AND ITS LENGTH, the second count-and-list of this file. `Srcs.tail` is
# `self.src[1:]` and `Srcs.n` is `len(self.src)`, which is what INDEX's
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
# a list already in arena order into its own mirror, which every whole-list walk
# (`dts_of.go`, `mstack_dev.go`, `ended_of.flat`, `first_dev`) survived by accident
# and every positional read did not. MEASURED, and the measurement is
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
def thru0(+ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of(src_dt(0, ss), src_shape(0, ss))

def store_ds(ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of(S.void(), src_shape(0, ss))

def cast_ds.pick(m: Maybe<&1, S.Dt>, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match m:
    case Some{dt}: dt_of(dt, src_shape(0, ss))
    case None{}: None{}

# `src_shape(k)[-1]`, which is a `Maybe` inside a `Maybe`: a src with no shape has no last
# dim, and `Maybe.bind` is the two questions asked in order.
def src_last(k: U32, ss: List<&2, Derived>) -> Maybe<&2, O.Sint>:
  Maybe.bind(&2, List<&2, O.Sint>, O.Sint, src_shape(k, ss), ds => List.last(&2, O.Sint, ds))

# `x._shape is not None` for every x, which is the `assert` the Broadcastable arm and
# INDEX's index loop both make through `s.shape`.
def all_shaped.go(ss: List<&2, Derived>, ok: Bool) -> Bool:
  match ss:
    case Nil{}: ok
    case d <> t: all_shaped.go(t, Bool.and(ok, Maybe.is_some(&2, List<&2, O.Sint>, Derived.shape(d))))

def all_shaped(ss: List<&2, Derived>) -> Bool:
  all_shaped.go(ss, True{})

# `[x.shape for x in src]` -- the `input_shapes` the Broadcastable arm and WMMA's
# `wmma_b` take. `all_shaped` has already refused a shapeless operand, so the `Nil{}`
# default is the dead one.
def shape_of(d: Derived) -> List<&2, O.Sint>:
  Maybe.default(&2, List<&2, O.Sint>, Derived.shape(d), Nil{})

def shapes_of.put(+x: Sized, +sh: Shapes) -> Shapes:
  Shapes{List.append(&2, Sized, Shapes.ds(sh), [x]), Nat.max(Shapes.m(sh), Sized.n(x))}

def shapes_of.acc(m: Maybe<&2, List<&2, O.Sint>>, acc: Maybe<&2, Shapes>) -> Maybe<&2, Shapes>:
  match m acc:
    case None{} _: None{}
    case Some{ds} None{}: None{}
    case Some{ds} Some{sh}: Some{shapes_of.put(sized(ds), sh)}

# The `assert` and the collection in ONE walk, because `all_shaped` and `shapes_of.go`
# are two reads of the same list and Bend spends a list when it reads it. The accumulator
# is a Maybe and the step is a def, so it is two scrutinees and the three cases a
# Maybe-squared walk can be in.
def shapes_of.acc2(acc: Maybe<&2, Shapes>, d: Derived) -> Maybe<&2, Shapes>:
  shapes_of.acc(Derived.shape(d), acc)

def shapes_of.go(ss: List<&2, Derived>, acc: Maybe<&2, Shapes>) -> Maybe<&2, Shapes>:
  List.foldl(~&2, ~Derived, ~Maybe<&2, Shapes>, shapes_of.acc2, ss, acc)

def all_shapes(ss: List<&2, Derived>) -> Maybe<&2, Shapes>:
  shapes_of.go(ss, Some{Shapes{Nil{}, 0n}})

# `input_shapes = [x._shape for x in self.src if x._shape is not None]` -- ops.py:372,
def some_shapes.put(+ds: List<&2, O.Sint>, +acc: Maybe<&2, Shapes>) -> Maybe<&2, Shapes>:
  match acc:
    case None{}: None{}
    case Some{sh}: Some{shapes_of.put(sized(ds), sh)}

def some_shapes.acc2(+acc: Maybe<&2, Shapes>, m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, Shapes>:
  match m:
    case None{}: acc
    case Some{ds}: some_shapes.put(ds, acc)

def some_shapes.go(ss: List<&2, Derived>, +acc: Maybe<&2, Shapes>) -> Maybe<&2, Shapes>:
  match ss:
    case Nil{}: acc
    case d <> t: some_shapes.go(t, some_shapes.acc2(acc, Derived.shape(d)))

def some_shapes(+ss: List<&2, Derived>) -> Maybe<&2, Shapes>:
  some_shapes.go(ss, Some{Shapes{Nil{}, 0n}})

def where_ds.of(+x: Srcs) -> Maybe<&2, DtShape>:
  dt_of_if(S.Dt.is_bool(src_dt(0, Srcs.ss(x))), promo_dtype(dts_of.go(Srcs.tail(x), Nil{})),
    bcast_shape(all_shapes(Srcs.ss(x))))

# WHERE: `if src[0].dtype != dtypes.bool: raise RuntimeError(f"where cond must be bool,
# got {src[0].dtype}")` then `return promo_dtype(src[1:])`
def where_ds(ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  where_ds.of(srcs(ss))

# The Broadcastable arm: "elementwise ops keep the shape the same. all inputs with
def alu_ds(dt: S.Dt, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of(dt, bcast_shape(all_shapes(ss)))

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
    case Derived{dt, shape, dev, addr, base, unbase, sbase, ended}: dev

def src_dev(k: U32, ss: List<&2, Derived>) -> Maybe<&2, S.Dev>:
  Derived.dev(Maybe.default(&2, Derived, List.get(&2, Derived, ss, U32.to_nat(k)), Derived.unknown()))

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
    case Derived{dt, shape, dev, addr, base, unbase, sbase, ended}: addr

def src_addr(k: U32, ss: List<&2, Derived>) -> Maybe<&2, S.Addr>:
  Derived.addr(Maybe.default(&2, Derived, List.get(&2, Derived, ss, U32.to_nat(k)), Derived.unknown()))

def fold.addr.of(m: Maybe<&2, Derived>) -> Maybe<&2, Maybe<&2, S.Addr>>:
  match m:
    case Some{d}: Some{Derived.addr(d)}
    case None{}: None{}

def Derived.base(d: Derived) -> U32:
  match d:
    case Derived{dt, shape, dev, addr, base, unbase, sbase, ended}: base

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

# `UOp.unsharded_base` -- ops.py:769 -- and `UOp.storage_base` -- ops.py:782. BOTH
# are the fold's INDEX rather than a walk, for `base`'s reason: a node's answer is a
# node before it, so the src's answer is already in the table.
def Derived.unbase(d: Derived) -> U32:
  match d:
    case Derived{dt, shape, dev, addr, base, unbase, sbase, ended}: unbase

def Derived.sbase(d: Derived) -> U32:
  match d:
    case Derived{dt, shape, dev, addr, base, unbase, sbase, ended}: sbase

def src_sbase(k: U32, ss: List<&2, Derived>) -> U32:
  Derived.sbase(Maybe.default(&2, Derived, List.get(&2, Derived, ss, U32.to_nat(k)), Derived.unknown()))

def fold.unbase.of(m: Maybe<&2, Derived>) -> Maybe<&1, U32>:
  match m:
    case Some{d}: Some{Derived.unbase(d)}
    case None{}: None{}

def fold.sbase.of(m: Maybe<&2, Derived>) -> Maybe<&1, U32>:
  match m:
    case Some{d}: Some{Derived.sbase(d)}
    case None{}: None{}

def Derived.ended(d: Derived) -> List<&2, U32>:
  match d:
    case Derived{dt, shape, dev, addr, base, unbase, sbase, ended}: ended

def src_ended(k: U32, ss: List<&2, Derived>) -> List<&2, U32>:
  Derived.ended(Maybe.default(&2, Derived, List.get(&2, Derived, ss, U32.to_nat(k)), Derived.unknown()))

def ended_of.list(ss: List<&2, Derived>, acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match ss:
    case Nil{}: acc
    case d <> t: ended_of.list(t, List.append(&2, List<&2, U32>, acc, [Derived.ended(d)]))

def ended_of.flat(ss: List<&2, Derived>, k: Nat) -> List<&2, U32>:
  H.flatten_u32(ended_of.list(List.drop(&2, Derived, ss, k), Nil{}))

def fold.ended.of(m: Maybe<&2, Derived>) -> Maybe<&2, List<&2, U32>>:
  match m:
    case Some{d}: Some{Derived.ended(d)}
    case None{}: None{}

# `dtype_from_uop` (ops.py:124) and `UOp._shape` (ops.py:329), together.
# The arms are grouped by the RULE they use rather than by declaration order,
# ops.py's own comments on the arms, kept: "always void", "pass through first",
def late() -> Maybe<&2, DtShape>:
  Some{DtShape{S.void(), None{}}}

# the `() ` rule, and one DEF for three ops because upstream writes it three times:
# `Ops.INS` (ops.py:339-341), `Ops.CUSTOM_FUNCTION` (ops.py:374) and `Ops.CALL`
# IT SITS HERE, BESIDE `late()`, and not up beside `dt_of_nil` with the other `_ds` arms,
# because bend REFUSES A FORWARD REFERENCE -- MEASURED, a def calling a later def answers
def nil_ds.shape(+dt: S.Dt) -> Maybe<&2, DtShape>:
  match dt:
    case S.Dt{_, _, S.CVoid{}, _}: late()
    case _: Some{dt_of_nil(dt)}

def noop_ds.go(empty: Bool, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match empty:
    case True{}: late()
    case False{}: dt_of(S.void(), src_shape(0, ss))

# NOOP: `return self.src[0]._shape if len(self.src) >= 1 else None` -- "hacks for NOOP" --
# and the dtype is in the `always void` set.
def noop_ds(ar: O.Arena, i: U32, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  noop_ds.go(U32.is_zero(O.Arena.nsrc(ar, i)), ss)

# `len(self.arg)` (ops.py:365). `ABlob` now holds the BYTES -- ops.py:201's key holds
# the `bytes` object -- so the length is the list's, not a stored field.
def binary_n.of(arg: O.Arg) -> U32:
  match arg:
    case O.ABlob{bs}: U32.from_nat(List.length(&2, U32, bs))
    case _: 0

def binary_n(arg: O.Arg) -> U32:
  binary_n.of(arg)

def binary_ds(arg: O.Arg) -> Maybe<&2, DtShape>:
  dt_of(S.uint8(), Some{[sint_of(binary_n(arg))]})

def param_dt(arg: O.Arg) -> Maybe<&1, S.Dt>:
  match arg:
    case O.AParam{pa}: Some{O.ParamArg.dtype(pa)}
    case _: None{}      # `assert isinstance(arg, ParamArg), f"{op} must have ParamArg"`

# BUFFER | ALLOC | PARAM: "if (img:=self.arg.image) is not None: return (img[0],
# img[1], 4)" and otherwise `self.src[0].as_shape` (ops.py:353-357). The quoted
def param_ds(+arg: O.Arg, size: Maybe<&2, U32>) -> Maybe<&2, DtShape>:
  param_ds.pick(param_dt(arg), arg, size)

def call_dt(arg: O.Arg) -> S.Dt:
  match arg:
    case O.ACall{ci}: O.CallInfo.dtype(ci)
    case _: S.void()

# CALL: `return arg.dtype if isinstance(arg, CallInfo) else dtypes.void` in the
# that second half is a line this comment quoted and ops.py does not carry. measured at
# ops.py:386-388: `Ops.CALL` is in the PASSTHROUGH arm, `return self.src[0]._shape`, and
def call_ds(arg: O.Arg) -> Maybe<&2, DtShape>:
  nil_ds.shape(call_dt(arg))

def ins_dt(arg: O.Arg) -> Maybe<&1, S.Dt>:
  match arg:
    case O.AInk{ins, dt}: Some{dt}
    case _: None{}      # `assert isinstance(arg, tuple) and len(arg) == 2`

# INS: `arg is (instruction, dtype)`, "a queue command or an asm line is void",
# which the arg's Dt already says, and `if self.dtype is dtypes.void: return None;
# return ()` -- "INS shape is always scalar, vector width is in the instruction
# encoding". MEASURED, ops.py:339-341: that IS the line, so this arm states the rule.
def ins_ds.pick(m: Maybe<&1, S.Dt>) -> Maybe<&2, DtShape>:
  match m:
    case Some{dt}: nil_ds.shape(dt)
    case None{}: None{}

def ins_ds(arg: O.Arg) -> Maybe<&2, DtShape>:
  ins_ds.pick(ins_dt(arg))

# CUSTOM_FUNCTION -- ops.py:133-135 `return arg.dtype` and ops.py:374 `return None
# if self.dtype is dtypes.void else ()`. It is NOT one of the always-void ops: ops.py
# gives it its OWN arm in `dtype_from_uop` because the dtype is in the ARG.
def cfun_ds(arg: O.Arg) -> Maybe<&2, DtShape>:
  match arg:
    case O.ACustom{cf}: nil_ds.shape(O.CustomFunction.dtype(cf))
    case _: None{}      # `return arg.dtype` -- only a CustomFunction has a `.dtype`

# CUSTOM | CUSTOMI -- ops.py:136-138 for the dtype and ops.py:370-372 for the shape:
# WHAT THIS IS NOT, and it is the defect this arm carried until 2026-10-05: the outer
# the other two copies of that same void arm -- `call_ds.go` and `ins_ds.shape`, two
# BYTE-identical bodies -- carried it too and survived the fix. 2026-10-06 they are gone:
# CALL, INS and CUSTOM_FUNCTION now all read ONE def, `nil_ds.shape`, so there is no
# fourth copy to be left behind again. MEASURED on `--graph loop`, the graph that carried
def custom_ds.of(+dt: S.Dt, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match dt:
    case S.Dt{_, _, S.CVoid{}, _}: late()
    case _: Some{DtShape{dt, bcast_shape(some_shapes(ss))}}

def custom_ds.pick(m: Maybe<&1, S.Dt>, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match m:
    case Some{dt}: custom_ds.of(dt, ss)
    # `assert isinstance(arg, tuple) and len(arg) == 2 and isinstance(arg[1], DType)`
    # (ops.py:137) -- a WRONG FIXTURE rather than a shapeless op, so this stays a refusal
    # and does not join the void/broadcast answer. `uop/spec.bend` gates CUSTOM and
    # CUSTOMI on `AInk` for the same reason.
    case None{}: None{}

def custom_ds(arg: O.Arg, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  custom_ds.pick(ins_dt(arg), ss)

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
def index_ds(ar: O.Arena, i: U32, ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  index_ds.of(ar, i, srcs(ss))

# `a.shape[:-1]` for each of the three operands. The foldl walks `ds` with `acc` as
def wmma_shapes.put.step(+a: Shapes, +d: Sized) -> Shapes:
  Shapes{List.append(&2, Sized, Shapes.ds(a), [d]), Nat.max(Shapes.m(a), Sized.n(d))}

def wmma_shapes.put(ds: List<&2, Sized>, acc: Shapes) -> Shapes:
  List.foldl(~&2, ~Sized, ~Shapes,
    (a: Shapes) => (d: Sized) => wmma_shapes.put.step(a, d),
    ds, acc)

# `a.shape[:-1]` per operand, AS A `Shapes` -- NOT as the full shapes. The broadcast
def wmma_shapes.of(sh: Shapes) -> Shapes:
  wmma_shapes.put(wmma_shapes.go(Shapes.ds(sh), Nil{}), Shapes{Nil{}, 0n})

def wmma_ds.go(dt: S.Dt, ws: Maybe<&2, Shapes>, last: Maybe<&2, O.Sint>) -> Maybe<&2, DtShape>:
  wmma_ds.of(dt, bcast_shape(Maybe.map(&2, Shapes, Shapes, wmma_shapes.of, ws)), last)

# WMMA: "wmma output shape = accumulator shape (src[2])", and the dtype is the
# accumulator dtype. `wmma_b = _broadcast_shape(self.src[0].shape[:-1],
# self.src[1].shape[:-1], self.src[2].shape[:-1])` / `return wmma_b +
# (self.src[2].shape[-1],)`
def wmma_ds(+ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  wmma_ds.go(src_dt(2, ss), all_shapes(List.take(&2, Derived, ss, 3n)), src_last(2, ss))

# `marg` -- ops.py:813, RESHAPE's arm of it, and the reason RESHAPE is the one
#   ops.py:816  `case Ops.RESHAPE | Ops.EXPAND: return self.src[1].as_shape`
# `as_shape` reads `ssimplify` on TWO of its three arms, and BOTH are arms
# `shape_to_shape_arg` (ops.py:105-108) never builds FOR A CONCRETE SHAPE: it is
# THE ANSWER is a `List<&2, O.Sint>`, and a dim is an `SI` or a `SU`: an `SI` is an
# `I64` that `H.i64_is_neg` can test and `H.lo32` can multiply, which is what the two
# checks need, and a `SU` is the arena index of the node the dim IS, which is what
# makes two different symbolic dims two different answers.
# `self.val` for a CONST -- ops.py:259-262, `.val` reads `self.arg` and is only
def const_i64.go(v: O.Const) -> Maybe<&2, H.I64>:
  match v:
    case O.CInt{i}       : Some{i}
    case O.CBool{True{}} : Some{H.i64_of_i32(1)}
    case O.CBool{False{}}: Some{H.i64_of_i32(0)}
    case _               : None{}

def const_i64(a: O.Arg) -> Maybe<&2, H.I64>:
  match a:
    case O.APy{v}: const_i64.go(v)
    case _       : None{}

# the RANGE width -- `int(r.vmax)+1`, the one quantity unshard and stage both read
# (ops.py:430 and ops.py:378). This is the block `dt_shape`'s two deferred arms were
# WHAT UPSTREAM COMPUTES. ops.py:1147 answers a RANGE/SPECIAL `0, (self.src[0]-1).vmax`,
# MEASURED, `.agents/slop/twopass/probe.bend` over graphcmp.py's `g_unshard`: it prints
# WHY A READER AND NOT `mm.sweep`, which is the OTHER way to get this number, and which
# the chain, and it is the defect this reader had, measured 2026-10-28.
# - UPSTREAM'S RANGE ARM IS `0, (self.src[0]-1).vmax` (`ops.py:1147`), AND `vmax` OF A
# - measured, calling CPython on the `lin` matmul's own kernel (`full_rewrite_to_sink` OF
# - and the after bound is not a rarity: `pm_simplify_ranges` rewrites a RANGE's bound into
# - and the `CAST` is the same story: `ops.py:142`'s group puts `Ops.CAST` in the
# - - so the chain is `RANGE/SPECIAL -> (AFTER | CAST)* -> CONST`, and the reader descends
# `rng_width.end` CALLS NOBODY, so `begin` calling `end` is NOT mutual recursion: the walk
# is `of` alone, descending the RANGE/special `src[0]` and then the pass-through chain,
# which is the whole descent ops.py:1147 performs. It is not a general interval walk and
def rng_width.const(op: O.Op, +ar: O.Arena, e: U32) -> Maybe<&2, H.I64>:
  match op:
    case O.OpsCONST{}: const_i64(O.Arena.arg(ar, e))
    case _: None{}

def rng_width.passes(op: O.Op) -> Bool:
  match op:
    case O.OpsAFTER{}: True{}
    case O.OpsCAST{}: True{}
    case _: False{}

def rng_width.end3(op: O.Op, +ar: O.Arena, +e: U32) -> Maybe<&2, H.I64>:
  match op:
    case O.OpsCONST{}: const_i64(O.Arena.arg(ar, e))
    case _: None{}

def rng_width.end2(op: O.Op, +ar: O.Arena, +e: U32) -> Maybe<&2, H.I64>:
  match op:
    case O.OpsCONST{}: const_i64(O.Arena.arg(ar, e))
    case O.OpsAFTER{}: rng_width.end3(O.Arena.op(ar, O.Arena.src(ar, e, 0)), ar, O.Arena.src(ar, e, 0))
    case O.OpsCAST{}: rng_width.end3(O.Arena.op(ar, O.Arena.src(ar, e, 0)), ar, O.Arena.src(ar, e, 0))
    case _: None{}

def rng_width.end(op: O.Op, +ar: O.Arena, +e: U32) -> Maybe<&2, H.I64>:
  match op:
    case O.OpsCONST{}: const_i64(O.Arena.arg(ar, e))
    case O.OpsAFTER{}: rng_width.end2(O.Arena.op(ar, O.Arena.src(ar, e, 0)), ar, O.Arena.src(ar, e, 0))
    case O.OpsCAST{}: rng_width.end2(O.Arena.op(ar, O.Arena.src(ar, e, 0)), ar, O.Arena.src(ar, e, 0))
    case _: None{}

def rng_width.at(op: O.Op, +ar: O.Arena, +r: U32) -> Maybe<&2, H.I64>:
  match op:
    case O.OpsRANGE{}: rng_width.end(O.Arena.op(ar, O.Arena.src(ar, r, 0)), ar, O.Arena.src(ar, r, 0))
    case O.OpsSPECIAL{}: rng_width.end(O.Arena.op(ar, O.Arena.src(ar, r, 0)), ar, O.Arena.src(ar, r, 0))
    case _: None{}

def rng_width.of(+ar: O.Arena, +r: U32) -> Maybe<&2, H.I64>:
  rng_width.at(O.Arena.op(ar, r), ar, r)

def rng_width(+ar: O.Arena, r: U32) -> Maybe<&2, H.I64>:
  rng_width.of(ar, r)

# `arg.index(a)`: the index of the FIRST `a`. ONE walk and not two -- the "stop at the
# first hit" is the ACCUMULATOR, because a second def to return to the first is mutual
# recursion and Bend refuses that (GUIDE.md, same paragraph).
def idx_u32.hit(acc: Maybe<&2, U32>, x: U32, y: U32, k: U32) -> Maybe<&2, U32>:
  match acc:
    case Some{z}: Some{z}
    case None{}: Bool.pick(Maybe<&2, U32>, U32.is_eq(x, y), Some{k}, None{})

def idx_u32.go(xs: List<&2, U32>, +y: U32, +k: U32, +acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match xs:
    case Nil{}: acc
    case x <> tl: idx_u32.go(tl, y, U32.add(k, 1), idx_u32.hit(acc, x, y, k))

def idx_u32(xs: List<&2, U32>, +y: U32) -> Maybe<&2, U32>:
  idx_u32.go(xs, y, 0, None{})

# STAGE: "STAGE adds the existing shape to the front, opposite of INDEX" -- the dtype
# passes through `src[0]` (ops.py:147-152 puts STAGE in the pass-through group) and the
def stage_shape.one(c: H.I64, acc: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, List<&2, O.Sint>>:
  match acc:
    case Some{xs}: Some{List.append(&2, O.Sint, xs, [O.SI{c}])}
    case None{}: None{}

def stage_shape.put(w: Maybe<&2, H.I64>, acc: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, List<&2, O.Sint>>:
  match w:
    case Some{c}: stage_shape.one(c, acc)
    case None{}: None{}

# the list is the first argument and that is the termination, not a style choice: bend
# reads a self-call's arguments left to right and each must pass unchanged until one
# shrinks, and `k` is recomputed, so it has to come AFTER the shrinking list
# (GUIDE.md, "Parallelism"/termination -- same paragraph as the order rule).
def stage_widths.go(tail: List<&2, U32>, +ar: O.Arena, +i: U32, +k: U32,
    +acc: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, List<&2, O.Sint>>:
  match tail:
    case Nil{}: acc
    case _ <> tl: stage_widths.go(tl, ar, i, U32.add(k, 1),
      stage_shape.put(rng_width(ar, O.Arena.src(ar, i, k)), acc))

def stage_widths(+ar: O.Arena, +i: U32) -> Maybe<&2, List<&2, O.Sint>>:
  stage_widths.go(O.Arena.src_from(ar, i, 1), ar, i, 1, Some{Nil{}})

# `pre + tail`, and `tail` is the `Maybe<&2, ...>` `src_shape` answers, so a src[0] with no
# shape refuses the whole thing rather than answering the prepend alone.
def pre_all.go(tail: List<&2, O.Sint>, +pre: List<&2, O.Sint>) -> List<&2, O.Sint>:
  match tail:
    case Nil{}: pre
    case x <> tl: pre_all.go(tl, List.append(&2, O.Sint, pre, [x]))

def pre_all(pre: List<&2, O.Sint>, m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case Some{tail}: Some{pre_all.go(tail, pre)}
    case None{}: None{}

def stage_shape.of(pre: Maybe<&2, List<&2, O.Sint>>, +ss: List<&2, Derived>) -> Maybe<&2, List<&2, O.Sint>>:
  match pre:
    case Some{xs}: pre_all(xs, src_shape(0, ss))
    case None{}: None{}

def stage_shape(+ar: O.Arena, +i: U32, +ss: List<&2, Derived>) -> Maybe<&2, List<&2, O.Sint>>:
  stage_shape.of(stage_widths(ar, i), ss)

def stage_ds(+ar: O.Arena, +i: U32, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of(src_dt(0, ss), stage_shape(ar, i, ss))

# `sym_dim` -- THE `ssimplify` WALL, CLOSED. `as_shape`'s two arms (ops.py:807-808)
# WHAT `ssimplify` IS (ops.py:92, ops.py:518-520): `u.simplify()` -- a
#   (UPat({Ops.CMPLT, Ops.CMPNE, Ops.DIV, Ops.MOD, Ops.PARAM, Ops.AFTER,
# and that it is the ONLY one: MEASURED, `rg 'Ops\.PARAM|Ops\.SPECIAL'
# MEASURED, calling CPython, over nine PARAM/SPECIALs (`.agents/slop/margsym-probe2.py`):
# SO: `SU{s}` is right for a PARAM or a SPECIAL whose interval is not a point, and
# it is a DISTINCT answer per dim because `s` IS the node. That is what the
# `U` shape column cannot carry and `dim_str` below now does.
# A dim this file can answer `x >= 0` about (ops.py:408's `all(...)`), which is a
def sym_dim.signable(+lo: H.I64, +hi: H.I64) -> Bool:
  Bool.and(Bool.not(H.i64_is_neg(lo)), H.i64_le(lo, hi))

# ops.py:1146 `GroupOp.Defines and arg.vmin_vmax is not None`, and ops.py:1147's
def sym_dim.range(r: Maybe<&2, O.PyRange>, s: U32) -> Maybe<&1, O.Sint>:
  match r:
    case Some{O.PyRange{+lo, +hi}}:
      Bool.pick(Maybe<&1, O.Sint>, O.eq_i64(lo, hi),
        Some{O.SI{lo}}, Bool.pick(Maybe<&1, O.Sint>, sym_dim.signable(lo, hi),
        Some{O.SU{s}}, None{}))
    case None{}: None{}

def sym_dim.pa(pa: O.ParamArg, s: U32) -> Maybe<&1, O.Sint>:
  sym_dim.range(O.ParamArg.vmin_vmax(pa), s)

# A SPECIAL's interval is `[0, end-1]`, so `vmin == vmax` is `end == 1` and
# `vmin > vmax` is `end == 0` -- THREE CASES AND NO ARITHMETIC, which is why this
# does not need `H.i64_sub` and does not need the end's own interval read back.
def sym_dim.spec(e: Maybe<&2, H.I64>, s: U32) -> Maybe<&1, O.Sint>:
  match e:
    case Some{+v}: Bool.pick(Maybe<&1, O.Sint>, O.eq_i64(v, H.i64_of_i32(1)),
                Some{sint_of(0)}, Bool.pick(Maybe<&1, O.Sint>, O.eq_i64(v, H.i64_of_i32(0)),
                None{}, Some{O.SU{s}}))
    case None{} : None{}

# `O.UOp.special` always names its end in src[0] and every caller builds it a CONST,
# so a symbolic end is the refusal rather than the answer.
def sym_dim.end(+ss: List<&2, U32>, +ar: O.Arena, i: U32) -> Maybe<&1, O.Sint>:
  match ss:
    case e <> _: sym_dim.spec(const_i64(O.Arena.arg(ar, e)), i)
    case Nil{}  : None{}

# `s.val` for a CONST and nothing else, and `const_i64.go`'s answer is the whole of
def sym_dim.val(i: Maybe<&2, H.I64>) -> Maybe<&1, O.Sint>:
  match i:
    case Some{v}: Some{O.SI{v}}
    case None{}  : None{}

# The `APy` arm is `s.val` and the other two are `ssimplify(s)`, so the CONST and
# the symbolic element are ONE reader. `AStr` is a SPECIAL and nothing else:
# `Arg`'s other string-bearing variants are `AKernel`/`AProgram`/`AInk`, none of
# which is a shape dim.
def sym_dim.of(a: O.Arg, +i: U32, +ar: O.Arena) -> Maybe<&1, O.Sint>:
  match a:
    case O.APy{v}    : sym_dim.val(const_i64.go(v))
    case O.AParam{pa}: sym_dim.pa(pa, i)
    case O.AStr{s}   : sym_dim.end(O.Arena.srcs(ar, i), ar, i)
    case _            : None{}

def sym_dim(+ar: O.Arena, +i: U32) -> Maybe<&1, O.Sint>:
  sym_dim.of(O.Arena.arg(ar, i), i, ar)

# `return tuple(s.val if s.op is Ops.CONST else ssimplify(s) for s in self.src)` --
# `sym_dim` BELOW is the `ssimplify` half, and it is the whole of the fix: the
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

# ONE READ of the element's node, which is why the DIM and the flag travel
# together: `s.val if s.op is Ops.CONST else ssimplify(s)` is one read of `s`.
def marg.step(d: Maybe<&1, O.Sint>, +x: Marg) -> Marg:
  match d:
    case Some{v}: Marg{List.append(&2, O.Sint, Marg.ds(x), [v]), Marg.ok(x)}
    case None{}  : Marg{Marg.ds(x), False{}}

# `marg.step(sym_dim(ar, s))` -- a CONST element reads `s.val` and a symbolic one
# reads `ssimplify`, both through `sym_dim`'s own CONST arm, so there is ONE element
# reader and not two.
def marg.stack.go(ss: List<&2, U32>, +ar: O.Arena, +x: Marg) -> Maybe<&2, List<&2, O.Sint>>:
  match ss:
    case Nil{}   : marg.done(x)
    case s <> t  : marg.stack.go(t, ar, marg.step(sym_dim(ar, s), x))

# `if self.op is Ops.CONST: return (self.val,)`, the one-element shape
def marg.one(+ar: O.Arena, i: U32) -> Maybe<&2, List<&2, O.Sint>>:
  marg.done(marg.step(sym_dim(ar, i), Marg{Nil{}, True{}}))

# `self.src[1]`, the arg `shape_to_shape_arg` built. THE CONST ARM AND THE
# `not STACK` ARM ARE THE SAME DEF: `if self.op is Ops.CONST: return (self.val,)`
# (ops.py:806) and `if self.op is not Ops.STACK: return (ssimplify(self),)`
def marg.of(k: O.Op, +ar: O.Arena, i: U32) -> Maybe<&2, List<&2, O.Sint>>:
  match k:
    case O.OpsSTACK{}: marg.stack.go(O.Arena.srcs(ar, i), ar, Marg{Nil{}, True{}})
    case _           : marg.one(ar, i)

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
def expand_ds(+ar: O.Arena, i: U32, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of(src_dt(0, ss), both(marg(ar, i), src_shape(0, ss)))

# pad and shrink -- ops.py:419-428. the two arms are one walk.
# Both read `marg`, which for them is `tuple(zip(self.src[1].as_shape,
# self.src[2].as_shape))` (ops.py:817) -- a LIST OF PAIRS, offsets then sizes. Both
# `pad=True` is PAD's `resolve(o+s<=sz)` and `pad=False` is SHRINK's `resolve(o+sz<=s)`
# `resolve` DEFAULTS TO TRUE for a symbolic operand (ops.py:64), so CPython ACCEPTS a
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
# `Nil Nil Nil` is the whole triple consumed, and `_ _ _` is BOTH failures in one
# arm: `len(ps) != len(self.marg)` (ops.py:421/426's first disjunct) and a `None`
# Four attempts failed before this one and the errors are worth the space:
# `Nil Nil Nil` is the whole triple consumed and `_ _ _` is `len(ps) != len(self.marg)`
# -- ops.py:419/424's first disjunct -- as a cover arm rather than an early return,
# a symbolic dim is an `O.SU` -- so `_ _ _` is the length check and the length check
def pad_shrink.go(ps: List<&2, O.Sint>, os: List<&2, O.Sint>, szs: List<&2, O.Sint>, +pad: Bool, +x: Pairs) -> Pairs:
  match ps os szs:
    case p <> pt, o <> ot, +z <> zt : pad_shrink.go(pt, ot, zt, pad,
      Pairs{List.append(&2, O.Sint, Pairs.szs(x), [z]), tri_ok(Tri.of(p, o, z), pad, Pairs.ok(x))})
    case Nil{} Nil{} Nil{}          : x
    case _ _ _                      : Pairs{Pairs.szs(x), False{}}

# THE TWO `as_shape` ANSWERS AS LISTS, and a `None` on either is `marg`'s own
# refusal -- an interval `sym_dim` will not read -- so this chain has no arm that
# continues past a `None`. It is three defs because a `Maybe` is read once and cannot
# be `+`; it is NOT a recursion, so nothing is mutual.
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

# PERMUTE -- ops.py:416-418. `if sorted(self.marg) != list(range(len(ps))): raise`
# deferred because "`marg` -> `as_shape` -> `ssimplify`", and that is TRUE OF
# `marg`'s OTHER TWO ARMS and FALSE of this one: `marg` for PERMUTE is `self.arg`
# (ops.py:818) -- the arena's `ATuple`, a `List<&2, U32>` of plain indices -- so no
# `sorted(ys) == list(range(n))` is tested WITHOUT SORTING, because `List.sort` needs
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

# ONE STEP: read the index, test the two halves, and append the picked dim. The picked
# THE WALK, AND IT IS ONE DEF. The first attempt was `.go`/`.of`/`.put` and `.go`/`.of`
# `n = len(ps)` is threaded so the range test reads the shape's own length rather than a
# THE STEP, and `d` is the INDEX READ as its own parameter so the `Some`/`None` match can
# The record's field is a `Maybe` on purpose: a `Data` record CAN carry a `Maybe` and a
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
def perm.go(ys: List<&2, U32>, +ps: List<&2, O.Sint>, +x: Perm) -> Perm:
  match ys:
    case Nil{}  : Perm{Perm.ds(x), Perm.seen(x), Perm.ok(x)}
    case y <> +t : perm.go(t, ps, perm_add(perm_step(y, t, ps), x))

# THE SEED, and `ps` IS THE SHAPE -- measured, not reasoned: the first version
# seeded `Nil{}` and `perm` read ABSENT on a VALID (1, 0) as well as on the two
# rejects, because `List.get(Nil, 0)` is `None` and every step took the `None` arm.
def perm_init(ys: List<&2, U32>, +ps: List<&2, O.Sint>) -> Perm:
  perm.go(ys, ps, Perm{Nil{}, Nil{}, True{}})

# the walk and the answer, and `Perm.ok`/`Perm.ds` read the record once each by
# passing it `+` to `perm_ds.of_walk` -- the alternative, writing `perm_init` twice
# in one expression, is legal only because the call is PURE ("`proc(t)` spelled
# twice is two walks, not a shared binding") and it doubles the walk for nothing.
def perm_ds.of_walk(+x: Perm, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  dt_of_if(Perm.ok(x), src_dt(0, ss), Some{Perm.ds(x)})

# THE ORDER IS A `Maybe` NOW -- BECAUSE `marg` RETURNS ONE -- AND
# THE `None` ARM IS THE EMPTY ORDER, WHICH IS WHAT UPSTREAM's
# `as_shape` ON A MISSING SHAPE ANSWERS.
def perm_ds.of(ys: List<&2, U32>, ps: Maybe<&2, List<&2, O.Sint>>, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match ps:
    case Some{p}: perm_ds.of_walk(perm_init(ys, p), ss)
    case None{}  : None{}

# THE PERMUTE's ORDER IS `src[1]`, AND THAT IS THE SAME READER
# THE RESHAPE USES -- MEASURED 2026-11-10:
# AND THE PORT's `marg` (`fold.bend:1751`) ALREADY READS `src[1]` AND
def order_srcs.const(+ar: O.Arena, s: U32) -> U32:
  H.lo32(Maybe.default(&2, H.I64, const_i64(O.Arena.arg(ar, s)), H.i64_of_i32(0)))

def order_srcs.go(+ar: O.Arena, ss: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}   : acc
    case s <> t  : order_srcs.go(ar, t, List.append(&2, U32, acc, [order_srcs.const(ar, s)]))

# THE `srcs` ARE READ IN A DEF THAT COMES FIRST, BECAUSE
def order_srcs.srcs(+ar: O.Arena, s: U32) -> List<&2, U32>:
  order_srcs.go(ar, O.Arena.srcs(ar, s), Nil{})

# THE OP IS TAKEN AS A VALUE AND THE INDEX IS TAKEN AS
def order_srcs.op(k: O.Op, +ar: O.Arena, s: U32) -> List<&2, U32>:
  match k:
    case O.OpsSTACK{}: order_srcs.srcs(ar, s)
    case _: Nil{}

def order_srcs.of(k: O.Op, +ar: O.Arena, s: U32) -> List<&2, U32>:
  order_srcs.op(k, ar, s)

# THE PERMUTE's SHAPE READER -- AND IT NEEDS TWO THINGS: THE
# AND THE SOURCE's DIMS ARE NOT `marg` -- MEASURED 2026-11-11 ON THE
# AND UPSTREAM's `_shape` (`ops.py:394-396`) IS `tuple(ps[i] for i in
# AND BEND SPENDS A BINDER WHEN IT READS IT ("consumed more than
def perm_ds(+ar: O.Arena, i: U32, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  +s = O.Arena.src(ar, i, 1)
  perm_ds.of(order_srcs.of(O.Arena.op(ar, s), ar, s), src_shape(0, ss), ss)

# THERE IS NO FLIP ARM HERE, and there is no FLIP in upstream either: `900880433`
# ("remove Ops.FLIP [pr] (#18729)", 2026-10-11) DELETED the member. Upstream's
# `GroupOp.Movement` is FIVE ops -- `tinygrad/uop/__init__.py:117 symbol=Movement`
# WHAT UPSTREAM DOES INSTEAD: `Tensor.flip` is a COMPOSITION -- upstream's
# `tinygrad/mixin/movement.py:233 symbol=flip` -- of `_mop(Ops.PAD, ...)`,
# the surviving construct this block used to point at is `case Ops.PERMUTE:` --
# ops.py:402-404 symbol=_shape -- `if sorted(self.marg) != list(range(len(ps))):

def pair_ds.put(+pad: Bool, x: Maybe<&1, Pairs>, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match x:
    case Some{+v}: dt_of_if(Pairs.ok(v), src_dt(0, ss), Some{Pairs.szs(v)})
    case None{}  : None{}

def pair_ds.of(+pad: Bool, x: Maybe<&1, Pairs>, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  pair_ds.put(pad, x, ss)

# the two arms' entry points, and the only difference between them is the `Bool`:
# PAD's `resolve(o+s<=sz)` and SHRINK's `resolve(o+sz<=s)` are the same three numbers
# with the other two swapped. One `Bool`, two entry points, one walk.
def pad_ds(+ar: O.Arena, +i: U32, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  pair_ds.of(True{}, pair3.of(True{}, src_shape(0, ss), marg.at(1, ar, i), marg.at(2, ar, i)), ss)

def shrink_ds(+ar: O.Arena, +i: U32, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  pair_ds.of(False{}, pair3.of(False{}, src_shape(0, ss), marg.at(1, ar, i), marg.at(2, ar, i)), ss)

# THE TWO CHECKS, ops.py:408-410, and they are ONE walk.
#   if not all(x >= 0 for x in self.marg): raise ValueError(...)
# Both read the same dims of the same `marg`, so they are one walk: `marg_prod`
# two flags and not one, and that is the fix: the old `bad` conflated a negative dim
# with a SYMBOLIC one, and upstream's two checks then read the SAME flag as opposite
# things. `all(x >= 0)` RAISES on a negative dim (ops.py:408). `resolve` has a `False`
# THE RESIDUAL, NAMED, because it is what `sym_dim`'s `signable` does NOT buy: `resolve`
# is `bool(sx.vmin) if sx.vmin == sx.vmax else False` (ops.py:66), so it is DECIDABLE --
# `prod(xs)` over a `Maybe` shape, in ONE self-recursive def: the product of the
# CONCRETE dims, whether any dim was provably negative (ops.py:408's raise), and whether
# the product and the two flags are one record, for the reason `Gathered` exists: a
type Prod is Data:
  Prod{n: U32, neg: Bool, sym: Bool}

def Prod.n(p: Prod) -> U32:
  match p:
    case Prod{n, neg, sym}: n

def Prod.neg(p: Prod) -> Bool:
  match p:
    case Prod{n, neg, sym}: neg

def Prod.sym(p: Prod) -> Bool:
  match p:
    case Prod{n, neg, sym}: sym

def marg_prod.mul(+i: H.I64, +p: Prod) -> Prod:
  Prod{U32.mul(Prod.n(p), H.lo32(i)), Bool.or(Prod.neg(p), H.i64_is_neg(i)), Prod.sym(p)}

def marg_prod.step(+d: O.Sint, +p: Prod) -> Prod:
  match d:
    case O.SI{i}: marg_prod.mul(i, p)
    case O.SU{u}: Prod{Prod.n(p), Prod.neg(p), True{}}

def marg_prod.go(ds: List<&2, O.Sint>, +p: Prod) -> Prod:
  match ds:
    case Nil{}  : p
    case d <> t : marg_prod.go(t, marg_prod.step(d, p))

def marg_prod1() -> Prod:
  Prod{1, False{}, False{}}

def marg_prod(+m: Maybe<&2, List<&2, O.Sint>>) -> Prod:
  marg_prod.go(Maybe.default(&2, List<&2, O.Sint>, m, Nil{}), marg_prod1())

# `if not all(x >= 0 for x in self.marg)` and `if resolve(prod(ps) !=
# prod(self.marg), False)`: the FIRST is `not Prod.neg(m)` and raises on its own,
# the SECOND is `resolve`'s DEFAULT, so an unprovable product does NOT raise. The
# `sym` arm is the whole reason `Prod` grew a second flag -- see the block above.
def reshape_ok(+ps: Prod, +m: Prod) -> Bool:
  Bool.and(Bool.not(Prod.neg(m)),
    Bool.pick(Bool, Bool.or(Prod.sym(ps), Prod.sym(m)), True{},
      U32.is_eq(Prod.n(ps), Prod.n(m))))

# `self.src[0]._shape` -- the `ps` of `resolve(prod(ps) != prod(self.marg), False)`.
# `ss` here is `Srcs.ss(srcs(ss))` from `derived`, and it is in ARENA ORDER: `srcs.go`
# used to finish its accumulator with a `List.reverse` over a list `List.append`
# (which is `xs ++ ys`, order preserving) had already built in input order, so the
# so this positional read is `src[0]` as `ops.py:406` spells it. The whole-list walks
def reshape_ps(+ss: List<&2, Derived>) -> Maybe<&2, List<&2, O.Sint>>:
  src_shape(0, ss)

# `if self.src[0].op is Ops.NOOP: return self.marg` (ops.py:346, "special
def reshape_ds.go(noop: Bool, m: Maybe<&2, List<&2, O.Sint>>, ok: Bool, dt: S.Dt) -> Maybe<&2, DtShape>:
  match noop:
    case True{} : dt_of(dt, m)
    case False{}: dt_of_if(ok, dt, m)

# `marg` is read TWICE because Bend spends a list when it reads it, and this file
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

# `UOp.device` -- ops.py:890. Its own `match op` because Python's is. ops.py's own
# comments, kept: "mselect must be on tuple device".

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

# `UOp.addrspace` -- ops.py:910. Its own `match op`, and the two group tests.
# ops.py's own comments, kept: "LOAD brings things into the ALU" and the
# `ad`/`all_same` rejection spelled out above.

def addrspace_of(arg: O.Arg, op: O.Op, ss: List<&2, Derived>) -> Maybe<&2, S.Addr>:
  match op:
    case O.OpsPARAM{}: addrspace_of.param(arg)
    case O.OpsREFPARAM{}: addrspace_of.param(arg)
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
    # `if self.op in GroupOp.Movement` and `or GroupOp.Elementwise`
    case _: addrspace_of.rest(op, ss)

def base_of.is_detach(op: O.Op) -> Bool:
  match op:
    case O.OpsDETACH{}: True{}
    case _: False{}

def base_of.steps(+op: O.Op) -> Bool:
  Bool.or(O.GroupOp.movement(op), base_of.is_detach(op))

# `UOp.base` and `UOp.is_invalid` -- ops.py:785 and ops.py:265. `base` is
# `self.src[0].base` for a movement op or for DETACH ("DETACH can't change base")
# and `self` otherwise, so the fold carries the INDEX rather than the walk: a
# node's base is a node before it, so the src's base is already in the table.

def base_of(i: U32, op: O.Op, ss: List<&2, Derived>) -> U32:
  base_of.go(ss, i, base_of.steps(op))

# `UOp.unsharded_base` -- ops.py:769 -- and `UOp.storage_base` -- ops.py:782. The
#     def base(self):          if self.op in GroupOp.Movement: return self.src[0].base
# `unsharded_base` steps ONCE into `base` -- the src's BASE, not the src's own
def base_of.is_unshard(op: O.Op) -> Bool:
  match op:
    case O.OpsUNSHARD{}: True{}
    case _: False{}

def base_of.is_bitcast(op: O.Op) -> Bool:
  match op:
    case O.OpsBITCAST{}: True{}
    case _: False{}

def base_of.is_after(op: O.Op) -> Bool:
  match op:
    case O.OpsAFTER{}: True{}
    case _: False{}

# `unsharded_base`'s step set is `base`'s PLUS UNSHARD, and the step reads the
# src's BASE -- so it is `base_of.go` with a wider set and NOT a recursion.
def unbase_of.steps(+op: O.Op) -> Bool:
  Bool.or(base_of.steps(op), base_of.is_unshard(op))

def unbase_of(i: U32, op: O.Op, ss: List<&2, Derived>) -> U32:
  base_of.go(ss, i, unbase_of.steps(op))

# `storage_base`'s step set is `unsharded_base`'s PLUS BITCAST and AFTER, and the
# step reads the src's STORAGE base, so the chain is its own.
def sbase_of.steps(+op: O.Op) -> Bool:
  Bool.or(Bool.or(unbase_of.steps(op), base_of.is_bitcast(op)), base_of.is_after(op))

def sbase_of.go(ss: List<&2, Derived>, i: U32, steps: Bool) -> U32:
  match steps:
    case True{}: src_sbase(0, ss)
    case False{}: i

def sbase_of(i: U32, op: O.Op, ss: List<&2, Derived>) -> U32:
  sbase_of.go(ss, i, sbase_of.steps(op))

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

# SIN | LOG2 | EXP2 | SQRT | RECIP: `return dtypes.bool if
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

# UNSHARD: "UNSHARD marker has no shape" was the LAST movement wall, and the wall was
# `_min_max` alone. ops.py:430 is
# `SU` refuses, and it is a refusal rather than a default: `s*w` on a symbolic dim is a
def unshard_axis.of(arg: O.Arg) -> List<&2, U32>:
  match arg:
    case O.ATuple{ys}: ys
    case _: Nil{}

def unshard_scaled(i: H.I64, w: Maybe<&2, H.I64>) -> Maybe<&2, O.Sint>:
  match w:
    case Some{x}: Some{O.SI{H.i64_mul(i, x)}}
    case None{}: None{}

def unshard_dim.mul(w: Maybe<&2, H.I64>, s: O.Sint) -> Maybe<&2, O.Sint>:
  match s:
    case O.SI{i}: unshard_scaled(i, w)
    case O.SU{u}: None{}

# A `match` ON `mem` AND NOT `Bool.pick`, because `Bool.pick` EVALUATES BOTH ARMS and
# `s` is a linear `Sint` -- the same reason `mm.MM2.get` is a `match` and not a default
# (fold.bend, the `Maybe` OUT OF THE BINARY BLOCK comment).
def unshard_dim.put(mem: Bool, w: Maybe<&2, H.I64>, s: O.Sint) -> Maybe<&2, O.Sint>:
  match mem:
    case True{}: unshard_dim.mul(w, s)
    case False{}: Some{s}

def unshard_dim.of(mem: Bool, w: Maybe<&2, H.I64>, s: O.Sint) -> Maybe<&2, O.Sint>:
  unshard_dim.put(mem, w, s)

# `rng_width` for axis `a`, which is `src[1:][arg.index(a)]` -- `Arena.src` is
# `(arena, node, POSITION)`, so the node index `i` and the src position `arg.index(a)` are
# different numbers and the `+ 1` is `src[0]`. `None` when `a` is absent from `arg`, which
# `unshard_dim.of` has already excluded by the membership test.
def unshard_w.at(m: Maybe<&2, U32>, +ar: O.Arena, +i: U32) -> Maybe<&2, H.I64>:
  match m:
    case Some{p}: rng_width(ar, O.Arena.src(ar, i, U32.add(1, p)))
    case None{}: None{}

def unshard_w.of(+ar: O.Arena, +i: U32, axis: List<&2, U32>, +a: U32) -> Maybe<&2, H.I64>:
  unshard_w.at(idx_u32(axis, a), ar, i)

def unshard_one(s: O.Sint, acc: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, List<&2, O.Sint>>:
  match acc:
    case Some{xs}: Some{List.append(&2, O.Sint, xs, [s])}
    case None{}: None{}

def unshard_put(d: Maybe<&2, O.Sint>, acc: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, List<&2, O.Sint>>:
  match d:
    case Some{s}: unshard_one(s, acc)
    case None{}: None{}

def unshard_ds.go(ps: List<&2, O.Sint>, +ar: O.Arena, +i: U32, +axis: List<&2, U32>, +a: U32,
    +acc: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, List<&2, O.Sint>>:
  match ps:
    case Nil{}: acc
    case s <> tl: unshard_ds.go(tl, ar, i, axis, U32.add(a, 1),
      unshard_put(unshard_dim.of(mem_u32(axis, a), unshard_w.of(ar, i, axis, a), s), acc))

def unshard_ds.of(axis: List<&2, U32>, +ar: O.Arena, +i: U32, ps: Maybe<&2, List<&2, O.Sint>>,
    +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match ps:
    case Some{ds}: dt_of(src_dt(0, ss), unshard_ds.go(ds, ar, i, axis, 0, Some{Nil{}}))
    case None{}: None{}

def unshard_ds(+ar: O.Arena, +i: U32, arg: O.Arg, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  unshard_ds.of(unshard_axis.of(arg), ar, i, src_shape(0, ss), ss)

# THE LADDER. `dtype_from_uop` (ops.py:124) and `UOp._shape` (ops.py:329), together:
# here are the dtype production rules, total over all Ops, grouped by the RULE each
# arm uses. See the block above for ops.py's own comments on the arms.

def dt_shape(ar: O.Arena, i: U32, op: O.Op, arg: O.Arg, +ss: List<&2, Derived>) -> Maybe<&2, DtShape>:
  match op:
    case O.OpsBUFFER{}: param_ds(arg, O.ParamArg.size(ar, i))
    case O.OpsALLOC{}: param_ds(arg, O.ParamArg.size(ar, i))
    case O.OpsPARAM{}: param_ds(arg, O.ParamArg.size(ar, i))
    case O.OpsREFPARAM{}: param_ds(arg, O.ParamArg.size(ar, i))
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
    # `case Ops.EXPAND: return tuple(self.marg) + ps` -- ops.py:412. PORTED: the one
    # movement arm that reads NO CHECK, so `marg_expsym_pos` answers a symbolic marg
    # here and `mv_expsym_pos` is the row.
    case O.OpsEXPAND{}: expand_ds(ar, i, ss)
    # `case Ops.PAD` / `case Ops.SHRINK` -- ops.py:419-428. PORTED as ONE walk with a
    # `Bool` that picks the arm: the two differ only in which sum and in the operand
    # order, and both answer the sizes. `pad_shrink` above.
    case O.OpsPAD{}: pad_ds(ar, i, ss)
    case O.OpsSHRINK{}: shrink_ds(ar, i, ss)
    # `case Ops.PERMUTE:` -- ops.py:402-404 symbol=_shape. AND NOW IT IS THE
    case O.OpsPERMUTE{}: perm_ds(ar, i, ss)

    # RANGE | SPECIAL: pass through first, then `return ()`
    case O.OpsRANGE{}: rlike(ss)
    case O.OpsSPECIAL{}: rlike(ss)

    # always void, and late ops don't have shape: the same twelve ops in both ladders
    case O.OpsREWRITE_ERROR{}: late()
    case O.OpsPROGRAM{}: late()
    case O.OpsLINEAR{}: late()
    case O.OpsSOURCE{}: late()
    case O.OpsSINK{}: late()
    case O.OpsBARRIER{}: late()
    case O.OpsIF{}: late()
    case O.OpsENDIF{}: late()
    case O.OpsBACKEDGE{}: late()
    # NOT one of the always-void ops. ops.py:133 gives CUSTOM_FUNCTION its OWN arm in
    case O.OpsCUSTOM_FUNCTION{}: cfun_ds(arg)
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
    case O.OpsRECIP{}: unary_ds(ar, ss)

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
    case O.OpsTRUNCDIV{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsMAX{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsTRUNCMOD{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsXOR{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsOR{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsAND{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsSUB{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsPOW{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsDIV{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsMOD{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)
    case O.OpsMULACC{}: alu_ds(promo_dtype(dts_of.go(ss, Nil{})), ss)

    # THE DEFERRED OPS, and there are now only TWO of them -- the five movement arms
    # this unit added are `reshape_ds`, `expand_ds`, `pad_ds`, `shrink_ds`, `perm_ds`
    # above, and CUSTOM/CUSTOMI left on 2026-10-05 (see `custom_ds`). Each is an arm
    # `dtype_from_uop` or `_shape` reaches through a rule this
    # file does not port, so the fold does not answer the node. The list is closed:
    # every other op has an arm above, which is what makes the match total without
    # Python's closing `raise RuntimeError(f"no dtype for {op} with arg {arg}")`.
    # and the second correction is 2026-10-05. The first said "the arena's CUSTOM arg is
    # a str (ops.bend's `Arg`), not the `(str, DType)` pair. P3: that is a change to
    # `Arg`." BOTH halves are false:
    #   * ops.py:137 ASSERTS the pair -- `isinstance(arg, tuple) and len(arg) == 2 and
    case O.OpsCUSTOM{}: custom_ds(arg, ss)
    case O.OpsCUSTOMI{}: custom_ds(arg, ss)
    case O.OpsSTAGE{}: stage_ds(ar, i, ss)
    # "UNSHARD marker has no shape" was the LAST movement wall. The shape is
    # `tuple(s*(int(self.src[1:][self.arg.index(a)].vmax)+1) if a in self.arg else s
    # for a,s in enumerate(ps))` (ops.py:430), and the `vmax` is `rng_width` above --
    # the `SU` refusal, and for why `mm.sweep` is not the reader.
    case O.OpsUNSHARD{}: unshard_ds(ar, i, arg, ss)

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

# `UOp.ended_ranges` -- ops.py:470. It walks DOWN the srcs, so it needs only the
# srcs the fold already answered, and the AFTER/BARRIER arms are exactly
# `H.flatten_u32` over them.

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
        addrspace_of(arg, op, Srcs.ss(x)), base_of(i, op, Srcs.ss(x)),
        unbase_of(i, op, Srcs.ss(x)), sbase_of(i, op, Srcs.ss(x)),
        ended_of(ar, i, op, Srcs.ss(x))}}
    case None{}: None{}

def derived.of(+ar: O.Arena, +i: U32, nd: O.Node, +x: Srcs) -> Maybe<&2, Derived>:
  match nd:
    case O.Node{+op, src, +arg, tag}:
      derived.put(dt_shape(ar, i, op, arg, Srcs.ss(x)), ar, i, op, arg, x)

# THE ASSEMBLY. The one place that knows all six properties, and the one def the
# worklist calls.

def derived(ar: O.Arena, i: U32, nd: O.Node, ss: List<&2, Derived>) -> Maybe<&2, Derived>:
  derived.of(ar, i, nd, srcs(ss))

# THE FOLD: a Kahn worklist over the arena.
# THREE LISTS, and each is doing one job:
# The bound is EXACT, not a budget to tune: every node is pushed once for having no
# A NODE MAY BE QUEUED TWICE, when it is a src of the same node twice (`ADD(x, x)`

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

# THE `_min_max` ARITHMETIC CORE -- the part of ops.py:1104 that is unsigned-64
# why it is here and not in helpers.bend. `helpers.bend` already owns the UNSIGNED
# PRIMITIVES this block reimplements -- `i64_of_hi_lo`, `u64_lt`, `u64_divmod`,
# `u64_mul_parts` -- and `mm.u64.mul` IS `u64_mul_parts` plus one thing: `mm.u64.of` answers
# `None` and THAT `None` IS the unsigned overflow, which every caller turns into
# `PInf`/`NInf`. `i64_mul` and `u64_mul` wrap mod 2**64 and cannot report it. the contract
# is different, so this is not DUPLICATED LOGIC AND NOT A MOVE. What `helpers.bend` lacks is
# the width is sign-plus-unsigned-64 and it is measured, not chosen. See
# THE SIGNS ARE NOT OPTIONAL and five bugs in this section were all silent, each producing
# a plausible number that only a CPython diff found:
#   * `Bool.or(is_zero(lo), is_zero(hi))` reads as "the pair is zero" and is not.
#   * the unsigned subtract's underflow test is `a < b`, and NOT `result < a`.
#   * in a 64x64 product `s` is limb 1 and `u` is limb 2, so the overflow test is
#     `u != 0 or t3.hi != 0` and NOT `t3.hi + (u >> 32) != 0`.
#   * for `k >= 32` the shifted high word comes from `al` and only from `al`.
#   * restoring division subtracts when the remainder REACHED the divisor.
# `UOp.is_variable` / `UOp.variables` -- ops.py:1009 and :1037, AND THE TWO NAMES
# `is_variable` is FOUR conjuncts and the FOURTH is the one that needs care:
# the shape conjunct is a constructor test and not a count, for the reason
# `cfun_shape_is` records three hundred lines up: `fold.shape` answers a Maybe OF a
# Maybe, the outer is "is the shape known" and the inner is Python's `None` versus `()`.
# So `Some{Some{Nil{}}}` is `()`, `Some{None{}}` is a shape that is not concrete, and
# anything else is not scalar. THE COUNT WOULD BE WRONG THREE WAYS AT ONCE.

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
# A 64x64 product is 128 bits, so the answer is the HIGH word and every bit from
# THE LIMBS ARE 16 WIDE, and that is the whole trick. `U32.mul` wraps, so a 32x32
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
  mm.u64.of(Bool.and(mm.u64.is_zero(H.hi32(t3), 0), mm.u64.is_zero(u, 0)),
    U32.or(U32.and(s, 4294967295), U32.shln(U32.and(u, 4294967295), 32n)),
    H.lo32(t0))

def mm.u64.mul(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<&2, H.I64>:
  mm.u64.join(mm.u32m(al, bl), mm.u32m(al, bh), mm.u32m(ah, bl), mm.u32m(ah, bh))

# ---- THE SHIFTS --------------------------------------------------------------
# `U32.shl` is a ONE-BIT shift and `U32.shln(x, n)` is the n-bit one, so every shift
# `int(x).bit_length()` is the AND arm's mask width (ops.py:1110) and it is a COUNT,
def mm.u64.shl.lo(+ah: U32, +al: U32, +k: Nat) -> H.I64:
  H.i64_of_hi_lo(U32.or(U32.shln(ah, k), U32.shrn(al, Nat.sub(32n, k))), U32.shln(al, k))

# for `k >= 32` the high WORD comes from `al` and only from `al`: `a * 2k` has
# high word `al * 2(k-32)` plus `ah * 2k` reduced mod 2**32, and the second term
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

def mm.u64.and(ah: U32, al: U32, bh: U32, bl: U32) -> H.I64:
  H.i64_of_hi_lo(U32.and(ah, bh), U32.and(al, bl))

def mm.u64.or(ah: U32, al: U32, bh: U32, bl: U32) -> H.I64:
  H.i64_of_hi_lo(U32.or(ah, bh), U32.or(al, bl))

def mm.u64.xor(ah: U32, al: U32, bh: U32, bl: U32) -> H.I64:
  H.i64_of_hi_lo(U32.xor(ah, bh), U32.xor(al, bl))

def mm.u64.not(ah: U32, al: U32) -> H.I64:
  H.i64_of_hi_lo(U32.not(ah), U32.not(al))
# ---- RESTORING DIVISION --------------------------------------------------------
# `helpers.bend` already has `cdiv_i32_go` and `floordiv_i32`, and both are this
# `qb` is the quotient bit for this step, carried because the compare happens before
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

# step `k` reads dividend bit `k` and writes quotient bit `k` -- the same index on
# `U32.shrn(w, j)` is `w >> j` and NOT `(w >> j) & 1`, and the caller ORs the answer
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

# the quotient bit is at position `k`, the same INDEX the dividend bit came from, so
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

# `int(x).bit_length()` -- ops.py:1110's mask width. SOLVED, NOT ROUTED AROUND.
# the previous unit recorded this as a structural wall, and the reasoning was sound:
# it is a binary-search ladder: five `Bool.pick`s and a tail test, all straight-line,
# so what made it possible, in one sentence: the count is not a count. a walk counts
# the count is the same answer and not a different one. `1 << k` needs `k` as a `Nat`
# and the mask is `2k - 1`, so a bit_length that is one too large gives a mask one
# bit too wide and therefore a DIFFERENT INTEGER, not a different shape -- which is
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
# `2k - 1` IS ALL ONES SHIFTED DOWN BY (width - k), and that is total over the whole
# range INCLUDING both ends: `k == 0` shifts all ones out of the word and `k == width`
# shifts by nothing. The decomposition I wrote FIRST -- OR the blocks `2(2i) - 1` for
# the set bits of `k` -- is WRONG and the CPython diff caught it on the first masked row:
# `Nat.sub` UNDERFLOWS TO 0, which is what makes the eagerly-evaluated other arm harmless
def mm.mask.lo(+k: U32) -> U32:
  U32.shrn(4294967295, Nat.sub(32n, U32.to_nat(k)))

def mm.mask.hi(+k: U32) -> U32:
  U32.shrn(4294967295, Nat.sub(64n, U32.to_nat(k)))

def mm.mask64(+k: U32) -> H.I64:
  H.i64_of_hi_lo(mm.mask.hi(k), mm.mask.lo(k))

# `mm.u64.and` takes two pairs and returns one, so the AND arm's
# THE `Maybe` IS WRAPPING AND NOT REAL: `&` of two in-window pairs is in-window, so this
def mm_mask64(+s0h: U32, +s0l: U32, s1h: U32, s1l: U32) -> Maybe<&2, H.I64>:
  +mk = mm.mask64(mm.bl64(s0h, s0l))
  Some{mm.u64.and(s1h, s1l, H.hi32(mk), H.lo32(mk))}

# `Bound` -- a bound of `_min_max`, and the dtype limits that end every arm.
# four arms, and two of them are the over-approximation. `Int{neg, mag}` is the width
# `weakint` is the one dtype whose limits leave the window, and it is measured.

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
# the eight integer limits are computed and not written down, because `2bits - 1` is
def bnd_show(b: Bnd) -> String:
  match b:
    case Bnd{i}: Bool.pick(String, U32.is_zero(i), "NInf", "PInf")
    case BndInt{neg, mag}: String.concat([Bool.pick(String, neg, "-", "+"), H.i64_text(mag)])
    case BndFlt{v}: String.concat(["F", F32.show(v)])

# THE SATURATING PAIR. Every float dtype's limits are `-inf`/`inf` except the three fp8s,
# and every WIDTH PAST 64 integer's are here too, so `bnd_int` reuses it rather than
# naming a second one.
def bnd_flt(top: Bool) -> Bnd: Bool.pick(Bnd, top, bnd_pinf(), bnd_ninf())

# ---- THE EIGHT INTEGER LIMITS, COMPUTED. `2bits - 1` is `mm.mask64(bits)` -- the same
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

# the width guard is on both sides and not just the minimum, and that is a real trap the
def bnd_int(+top: Bool, +sgn: Bool, +bits: U32) -> Bnd:
  Bool.pick(Bnd, U32.is_gt(bits, 64), bnd_flt(top),
    Bool.pick(Bnd, top, Bool.pick(Bnd, sgn, bnd.smax(bits), bnd.umax(bits)),
      Bool.pick(Bnd, sgn, bnd.smag(bits), bnd_zero())))

# THE THREE FP8 MAXIMA, and they are the ONLY finite float bounds in tinygrad: the other
def bnd_fmax(+top: Bool, +m: Nat) -> Bnd:
  Bool.pick(Bnd, top, bnd_f(F32.from_nat(m)), bnd_f(F32.neg(F32.from_nat(m))))

# `bool` AND `void` ANSWER PYTHON'S `False` AND `True`, not a 1-bit integer's limits --
def bnd_bool(+top: Bool) -> Bnd:
  bnd_i(False{}, Bool.pick(H.I64, top, H.i64_of_hi_lo(0, 1), H.i64_of_hi_lo(0, 0)))

# the hundred-and-eighty-bit width is why `weakint` saturates, and nothing names
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
    # the three FP8 names are `Dt`'s fourth field and not its priority: `fp8e4m3` and
    case S.Dt{10, 8, S.CFloat{}, "fp8e4m3"}: bnd_fmax(top, 448n)
    case S.Dt{10, 8, S.CFloat{}, "fp8e4m3fnuz"}: bnd_fmax(top, 240n)
    case S.Dt{11, 8, S.CFloat{}, "fp8e5m2"}: bnd_flt(top)
    case S.Dt{11, 8, S.CFloat{}, "fp8e5m2fnuz"}: bnd_fmax(top, 57344n)
    case S.Dt{12, 16, S.CFloat{}, _}: bnd_flt(top)
    case S.Dt{13, 16, S.CFloat{}, _}: bnd_flt(top)
    case S.Dt{14, 32, S.CFloat{}, _}: bnd_flt(top)
    case S.Dt{15, 64, S.CFloat{}, _}: bnd_flt(top)
    case _: bnd_flt(top)

# THE OP TABLE -- ops.py:1105-1163. What follows is `_min_max` with the arena taken
# four rules the whole table follows, and all four are soundness rather than style:
#   1. A `None` out of the binary block means "no arm fired", and Python FALLS THROUGH to
# WHAT IS NOT HERE, one line each, and none of them is a TODO:
#   * `Ops.CAST` -- `truncate` (dtype.py:297) is half a C-effect seam in `dtype.bend` and

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

# the sign is forced to positive on a zero magnitude. `Int{neg, mag}` has no canonical
# zero without this rule, and `0 * -5` builds `SNok{True, 0}` -- which is `-0`, which is the
# SAME Python int as `0` and a DIFFERENT `Bnd`, so the gate string differs. It is the same
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
def mm.shamt.lo32(+mag: H.I64) -> U32: H.lo32(mag)

# THE SHIFT AMOUNT, and the two reasons it is a `Maybe`. Python's `x << k` raises on a
# Python's `x << k` raises on a negative `k` and gives a value past every dtype limit for a
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
def mm.i64.is_neg(+i: H.I64) -> Bool: U32.is_eq(U32.shrn(H.hi32(i), 31n), 1)

def mm.i64.mag(+i: H.I64) -> H.I64:
  +c = mm.u64.not(H.hi32(i), H.lo32(i))
  H.i64_of_hi_lo(U32.add(H.hi32(c), mm.u32c(H.lo32(c), 1)), U32.add(H.lo32(c), 1))

def mm.i64.to_bnd(+i: H.I64) -> Bnd:
  Bool.pick(Bnd, mm.i64.is_neg(i), bnd_i(True{}, mm.i64.mag(i)), bnd_i(False{}, i))

# ---- the table's own inputs -----------------------------------------------------
#
# A MISSING SRC IS THE UNBOUNDED INTERVAL rather than a refusal. Python raises
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

# `dtypes.weaks` -- dtype.py:160 -- is `(weakint, weakfloat)`, and `S.Cls` names the
def dt_is.is_weak(+d: S.Dt) -> Bool:
  match d:
    case S.Dt{_, _, S.CWeakInt{}, _}: True{}
    case S.Dt{_, _, S.CWeakFloat{}, _}: True{}
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

# the mask width comes from `s0` and the masked value is `s1` -- they are different srcs, and
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
def bnd.nz(b: Bnd) -> Bool:
  match b:
    case BndInt{neg, +mag}: Bool.or(neg, Bool.not(mm.u64.is_zero(H.hi32(mag), H.lo32(mag))))
    case _: True{}

def bnd.and(+a: Bnd, b: Bnd) -> Bnd: Bool.pick(Bnd, bnd.nz(a), b, a)
def mm.bin.and_bool.go(+s0: Bnd2, +s1: Bnd2) -> Bnd2:
  Bnd2{bnd.and(Bnd2.lo(s0), Bnd2.lo(s1)), bnd.and(Bnd2.hi(s0), Bnd2.hi(s1))}

# `Ops.AND` has two arms and the second is reached exactly when the first is not: the
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

# MUL: four products, the smallest and the largest. `min(vals)` over a keyword-argument
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

# xor by an all-ones constant is the only bitwise arm, and it is `~vmax, ~vmin` -- the
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
def mm.bin.cmplt(+s0: Bnd2, +s1: Bnd2) -> Bnd2:
  Bnd2{bnd_tf(bnd.lt(Bnd2.hi(s0), Bnd2.lo(s1))), bnd_tf(bnd.lt(Bnd2.lo(s0), Bnd2.hi(s1)))}

def mm.bin.cmpne(+s0: Bnd2, +s1: Bnd2) -> Bnd2:
  Bnd2{bnd_tf(Bool.or(bnd.lt(Bnd2.hi(s0), Bnd2.lo(s1)), bnd.lt(Bnd2.hi(s1), Bnd2.lo(s0)))),
    bnd_tf(Bool.not(Bool.and(bnd.eq(Bnd2.lo(s0), Bnd2.hi(s0)),
      Bool.and(bnd.eq(Bnd2.lo(s1), Bnd2.hi(s1)), bnd.eq(Bnd2.lo(s0), Bnd2.lo(s1))))))}

def mm.bin.add(+s0: Bnd2, +s1: Bnd2) -> Bnd2:
  Bnd2{bnd.add(Bnd2.lo(s0), Bnd2.lo(s1)), bnd.add(Bnd2.hi(s0), Bnd2.hi(s1))}

# SUB's two halves cross: the lower bound subtracts the other's upper and the upper
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
# WHERE is `min(s1, s2)` on the LOWER bounds and `max(s1, s2)` on the UPPER, which is not
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
    case O.ParamArg{_, _, vmin_vmax, _, _, _, _, _, _, _, _, _}: mm.defines.range(vmin_vmax, d)

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

# the `+` s are not spellable in the closure's TYPE, which is the recorded closure-shared-
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
    case O.OpsINDEX{}: mm.lift.mv(srcs)
    case O.OpsSTAGE{}: mm.lift.mv(srcs)
    case O.OpsAFTER{}: mm.lift.mv(srcs)
    case O.OpsDETACH{}: mm.lift.mv(srcs)
    case O.OpsCOPY{}: mm.lift.mv(srcs)
    case O.OpsCONTIGUOUS_BACKWARD{}: mm.lift.mv(srcs)
    case O.OpsCAST{}: mm.lift.mv(srcs)
    case _: mm.default(d)

def mm.lift(+op: O.Op, +srcs: List<&2, Bnd2>, arg: O.Arg, +d: S.Dt) -> Bnd2:
  mm.MM2.get(mm.lift.bin(mm.bin.enter(op, d), op, srcs, d), mm.lift.rest(op, srcs, arg, d))

# THE GATE. `main` builds small arenas with `ops.bend`'s own `g_*` constructors and
#   1. dtype_key   -- the same ucache NOTE, expressed in the fold: two CONSTs whose
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
  O.ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

# BUFFER(int32, size=4) <- SPECIAL("4", 1) <- CONST(0), then ADD(buffer, CONST(3)).
# The ADD is over a `float` buffer and a `weakint` constant, so its dtype is
# `least_upper_dtype(int32, weakint) = int32` and its shape is `(4,)` by broadcast.
def g_add() -> O.Found:
  +z = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(0)})
  +s = O.UOp.special(O.Found.ar(z), O.Found.i(z), "4")
  +b = O.UOp.new.param(O.Found.ar(s), O.OpsBUFFER{}, Some{4}, O.AParam{g_buf()}, O.TNone{})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(3)})
  O.UOp.alu(O.Found.ar(c), O.OpsADD{}, [O.Found.i(b), O.Found.i(c)])

# `shape_to_shape_arg((2, 2))` -- `UOp(Ops.STACK, src=(CONST(2), CONST(2)))`. The
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
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_buf()}, O.TNone{})
  +k = g_marg22(O.Found.ar(b))
  O.UOp.new(O.Found.ar(k), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})

# RESHAPE(BUFFER(4), STACK(2, 3)) -- `raise ValueError(f"bad reshape: {ps} ->
# {self.marg}")` (ops.py:412), which the oracle prints verbatim
def g_resh23() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_buf()}, O.TNone{})
  +k = g_marg23(O.Found.ar(b))
  O.UOp.new(O.Found.ar(k), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})

# RESHAPE(BUFFER(4), CONST(4)) -- the ONE-element marg, a bare CONST, and
# `movement.py:184`'s `return self if ret.shape == self.shape else ret`. The
# oracle prints `identity ret==self: True` for that test.
def g_resh4() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_buf()}, O.TNone{})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(4)})
  O.UOp.new(O.Found.ar(c), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

# RESHAPE(BUFFER(4), CONST(-2)) -- `raise ValueError(f"shape can't contain negative
# numbers {self.marg}")` (ops.py:410), which is a DIFFERENT check from the product
# one. -2 as a two's complement I64 is hi=all-ones and lo=2 below all-ones.
def g_reshneg() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_buf()}, O.TNone{})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_hi_lo(4294967295, 4294967294)})
  O.UOp.new(O.Found.ar(c), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

# RESHAPE(NOOP(BUFFER(4)), STACK(2, 3)) -- the "special (terrible) case for RESHAPE
# on NOOP" (ops.py:346), with a product that is WRONG on purpose: the `if` RETURNS
def g_reshnoop() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_buf()}, O.TNone{})
  +n = O.UOp.new(O.Found.ar(b), O.OpsNOOP{}, [O.Found.i(b)], O.ANone{}, O.TNone{})
  +k = g_marg23(O.Found.ar(n))
  O.UOp.new(O.Found.ar(k), O.OpsRESHAPE{}, [O.Found.i(n), O.Found.i(k)], O.ANone{}, O.TNone{})

# a reshape over a symbolic marg -- `STACK(CONST(2), SPECIAL("N") OVER END 0)` --
# which is the `s.val if s.op is Ops.CONST else ssimplify(s)` half of `as_shape`. The
# oracle prints `bad reshape: (4,) -> (2, UOp(Ops.SPECIAL...))`, so Python raises, and
# the fold refuses too -- but for a DIFFERENT and now-named reason: the SPECIAL's
def g_reshsym() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_buf()}, O.TNone{})
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
# the `_min_max` op-table rows. `.agents/slop/mm-lift-gate.py` generates both the
# FIXTURES AND THESE 123 LINES -- and it generates them from a fixture LIST, so there is
# `sat_*` IS A SECOND CLASS OF ROW. CPython's ints are unbounded, so `2**63 + 2**63` is

def lf_row(nm: String, b: Bnd2) -> IO(Unit):
  IO.print(String.concat(["lf_", nm, " ", bnd2_show(b)]))

# THE SRC LIST BUILDERS, and they exist because a `List<Bnd2>` is the table's input type
# and a row cannot spell one. `lf_c2`/`lf_c3` take the already-`Bnd`-converted value, so
# the integer-to-bound conversion is ONCE per fixture rather than once per read.
def lf_c0() -> List<&2, Bnd2>: Nil{}

def lf_c1(+a: Bnd) -> List<&2, Bnd2>: [Bnd2{a, a}]

def lf_c2(+a: Bnd, +b: Bnd) -> List<&2, Bnd2>: [Bnd2{a, a}, Bnd2{b, b}]

def lf_c3(+a: Bnd, +b: Bnd, +c: Bnd) -> List<&2, Bnd2>: [Bnd2{a, a}, Bnd2{b, b}, Bnd2{c, c}]

# a stack's srcs are not all the same value, and it is the one family that needs more than
# two, so `lf_c4` is a fourth arity rather than a fold: a fold would put a `Bnd2` builder
# in a closure's TYPE, where the `+` cannot be spelled (the recorded closure-shared-arg
# wall), for a list of at most four elements. Four arities is less code than the wall.
def lf_c4(+a: Bnd, +b: Bnd, +c: Bnd, +d: Bnd) -> List<&2, Bnd2>:
  [Bnd2{a, a}, Bnd2{b, b}, Bnd2{c, c}, Bnd2{d, d}]

# A PARAM's `vmin_vmax`, and the field is a `Maybe<&2, PyRange>` of a SIGNED pair, which is
# the only place `Bnd`'s sign/magnitude split is read back the other way.
def lf_pa(lo: H.I64, hi: H.I64) -> O.Arg:
  O.AParam{O.ParamArg{0, S.int32(), Some{O.PyRange{lo, hi}}, None{}, None{}, S.AGlobal{}, None{},
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

# the edges out of the node just answered, which is what Kahn's algorithm actually
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

# `UOp.unsharded_base` -- ops.py:769 -- and `UOp.storage_base` -- ops.py:782. The
# fold carries the index, so each is a table read, and they are SEPARATE reads
# because upstream's two properties are separate answers on one graph.
def fold.unbase(ar: O.Arena, tb: Table, i: U32) -> Maybe<&1, U32>:
  fold.unbase.of(Kahn.get(i, tb))

def UOp.unsharded_base(ar: O.Arena, tb: Table, i: U32) -> Maybe<&1, U32>:
  fold.unbase(ar, tb, i)

def fold.sbase(ar: O.Arena, tb: Table, i: U32) -> Maybe<&1, U32>:
  fold.sbase.of(Kahn.get(i, tb))

def UOp.storage_base(ar: O.Arena, tb: Table, i: U32) -> Maybe<&1, U32>:
  fold.sbase(ar, tb, i)

# `UOp.is_virtual` -- ops.py:891. `self.device is None or self.dtype in dtypes.weaks`
# -- TWO claims, and the fold answers both: `dev` is `Maybe<Dev>` and `None{}` is
# upstream's `None`, and `dt` is the node's own dtype.
def dev_none(m: Maybe<&2, S.Dev>) -> Bool:
  match m:
    case None{}: True{}
    case _: False{}

def is_virtual.go(d: Derived) -> Bool:
  match d:
    case Derived{dt, shape, dev, addr, base, unbase, sbase, ended}:
      Bool.or(dev_none(dev), dt_is.is_weak(dt))

def is_virtual.of(m: Maybe<&2, Derived>) -> Maybe<&1, Bool>:
  match m:
    case Some{d}: Some{is_virtual.go(d)}
    case None{}: None{}

def fold.is_virtual(ar: O.Arena, tb: Table, i: U32) -> Maybe<&1, Bool>:
  is_virtual.of(Kahn.get(i, tb))

def UOp.is_virtual(ar: O.Arena, tb: Table, i: U32) -> Maybe<&1, Bool>:
  fold.is_virtual(ar, tb, i)

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

def is_unit_shape(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>, unit: Bool) -> Bool:
  match m:
    case Some{Some{Nil{}}}: unit
    case _: Bool.not(unit)

# the two conjuncts of `is_variable` that are read off the ARG, and they are
# SHARED: `schedule/__init__.bend`'s `sc_var.pa` asks the same question about
# the same two fields, and two copies of a conjunction is how one of them
# silently loses a term. THE THIRD CONJUNCT IS NOT HERE and cannot be: the two
# callers reach the shape by DIFFERENT ROADS -- this file through the FOLD TABLE,
def isvar_arg(+vv: Maybe<&2, O.PyRange>, +ad: S.Addr) -> Bool:
  match vv ad:
    case Some{_} S.Aalu{}: True{}
    case _ _: False{}

def isvar_pa(+pa: O.ParamArg, +sh: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Bool:
  Bool.and(isvar_arg(O.ParamArg.vmin_vmax(pa), O.ParamArg.addrspace(pa)), is_unit_shape(sh, True{}))

def UOp.is_variable.of(+arg: O.Arg, +op: O.Op, +sh: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Bool:
  match arg op:
    case O.AParam{pa} O.OpsPARAM{}: isvar_pa(pa, sh)
    case _ _: False{}

# two defs, and not for tidiness: a `match` may not scrutinise a computed value
# ("give it its own def", bend2-constraints), so `vmin_vmax(pa)` and
# `addrspace(pa)` cannot be matched where they are read. They are PARAMETERS of
# this def instead, which is the one shape the compiler accepts.
def UOp.is_variable(+ar: O.Arena, +tb: Table, +i: U32) -> Bool:
  UOp.is_variable.of(O.Arena.arg(ar, i), O.Arena.op(ar, i), fold.shape(ar, tb, i))

# `UOp.unbound` -- ops.py:1027. `self.replace(arg=replace(self.arg, val=None),
def UOp.unbound.arg(+x: O.ParamArg) -> O.ParamArg:
  match x:
    case O.ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, _val}:
      O.ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer,
                 bind_on_realize, None{}}

def UOp.unbound.of(+arg: O.Arg, +ar: O.Arena, +i: U32) -> O.Found:
  match arg:
    case O.AParam{pa}: O.UOp.new(ar, O.Arena.op(ar, i), O.Arena.srcs(ar, i), O.AParam{UOp.unbound.arg(pa)}, O.TNone{})
    case _: O.Found{ar, i}

def UOp.unbound(+ar: O.Arena, +i: U32) -> O.Found:
  UOp.unbound.of(O.Arena.arg(ar, i), ar, i)

def UOp.shape(ar: O.Arena, tb: Table, i: U32) -> Maybe<&2, Maybe<&2, List<&2, O.Sint>>>:
  fold.shape(ar, tb, i)

def fold.dt(ar: O.Arena, tb: Table, i: U32) -> Maybe<&2, S.Dt>:
  fold.dt.of(Kahn.get(i, tb))

def dt_is(+x: Folded, i: U32, want: S.Dt) -> Bool:
  dt_is.pick(fold.dt(Folded.ar(x), Folded.t(x), i), want)

# THE READERS. `UOp.dtype(ar, t, i)` and the rest: a table read, so each is a
# `Maybe` from an index. There is no `UOp.dtype(ar, i)` here, and there cannot be
# one: answering a single node IS the fold, because the fold is what makes the
# answer well-founded. ops.py spells that `recursive_property` (ops.py:218).

def UOp.dtype(ar: O.Arena, tb: Table, i: U32) -> Maybe<&2, S.Dt>:
  fold.dt(ar, tb, i)

# `UOp.variables` -- ops.py:1037, THE NAME `schedule/__init__.bend`'s
# two arms and they are different shapes, which is why this cannot be a filter:
# The first arm is upstream's own distinction between a Variable and any other ALU
# the second arm is why the answer is a `Maybe`. `x.vmax` for a RANGE is `end - 1`,
# A `variables` that DROPPED a DEVICE range whose end it could not read would hand
# `resolve_linear_call` a parameter set missing a device index -- a schedule that
# looks plausible and is wrong. So that case is `None{}` and not a shorter list.
# the PARAM arm cannot fail; only the RANGE arm can.
# the arena is threaded through the accumulator and that is not tidiness.
# `UOp.variable` and `UOp.unbound` MINT, and `UOp.new` APPENDS: it answers a
# `Found` whose arena is GROWN. A `variables` returning bare indices would answer
# indices into an arena the caller never receives, and `Arena.arg` on the
# caller's copy would not find them. MEASURED: the first draft answered
type VarR is Data:
  VarR{ar: O.Arena, xs: List<&2, U32>}

def VarR.ar(x: VarR) -> O.Arena:
  match x:
    case VarR{ar, xs}: ar

def VarR.xs(x: VarR) -> List<&2, U32>:
  match x:
    case VarR{ar, xs}: xs

def UOp.vpush.add(+u: U32, +r: VarR) -> VarR:
  VarR{VarR.ar(r), Bool.pick(List<&2, U32>, List.contains(U32, U32.is_eq, VarR.xs(r), u), VarR.xs(r), List.append(&2, U32, VarR.xs(r), [u]))}

def UOp.vpush.one(+tb: Table, +x: U32, +r: VarR) -> VarR:
  +f = UOp.unbound(VarR.ar(r), x)
  UOp.vpush.add(Bool.pick(U32, UOp.is_variable(VarR.ar(r), tb, x), O.Found.i(f), x), VarR{O.Found.ar(f), VarR.xs(r)})

def UOp.vpush.mint(+hi: H.I64, +d: S.Dt, +r: VarR) -> VarR:
  +f = O.UOp.variable(VarR.ar(r), "_device_num", H.i64_zero(), hi, 1, d)
  UOp.vpush.add(O.Found.i(f), VarR{O.Found.ar(f), VarR.xs(r)})

def UOp.variables.pa(+tb: Table, +x: U32, +ad: S.Addr, +r: VarR) -> Maybe<&2, VarR>:
  match ad:
    case S.Aalu{}: Some{UOp.vpush.one(tb, x, r)}
    case _: Some{r}

def UOp.variables.mint.of(+e: Maybe<&2, H.I64>, +d: Maybe<&2, S.Dt>, +r: VarR) -> Maybe<&2, VarR>:
  match e d:
    case Some{end} Some{dt}: Some{UOp.vpush.mint(H.i64_sub(end, H.i64_one()), dt, r)}
    case _ _: None{}

def UOp.variables.at(+tb: Table, +x: U32, +at: O.AxisType, +r: VarR) -> Maybe<&2, VarR>:
  match at:
    case O.AXIS_DEVICE{}: UOp.variables.mint.of(rng_width.of(VarR.ar(r), x), UOp.dtype(VarR.ar(r), tb, x), r)
    case _: Some{r}

def UOp.variables.step.of(+acc: Maybe<&2, VarR>, +op: O.Op, +arg: O.Arg, +tb: Table, +x: U32) -> Maybe<&2, VarR>:
  match acc op arg:
    case None{} _ _: None{}
    case Some{r} O.OpsPARAM{} O.AParam{pa}: UOp.variables.pa(tb, x, O.ParamArg.addrspace(pa), r)
    case Some{r} O.OpsRANGE{} O.ARange{ids, at}: UOp.variables.at(tb, x, at, r)
    case Some{_} _ _: acc

# `xs` LEADS the parameters because the termination checker reads arguments left
# to right and needs to see one shrink before any other changes: `acc` is computed
# from `x`, so an `acc`-first signature is a self-call the checker cannot justify.
def UOp.variables.go(+xs: List<&2, U32>, fuel: Nat, +tb: Table, +acc: Maybe<&2, VarR>) -> Maybe<&2, VarR>:
  match xs acc:
    case Nil{} _: acc
    case _ None{}: None{}
    case x <> t Some{r}: UOp.variables.go(t, fuel, tb, UOp.variables.step.of(acc, O.Arena.op(VarR.ar(r), x), O.Arena.arg(VarR.ar(r), x), tb, x))

def UOp.variables(+ar: O.Arena, +tb: Table, +i: U32, +fuel: Nat) -> Maybe<&2, VarR>:
  UOp.variables.go(O.UOp.backward_slice_with_self(fuel, ar, i), fuel, tb, Some{VarR{ar, Nil{}}})

# `self.src`, read back out of the RESOLVED TABLE by index. A src the fold has not
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

# THE RANGES FOLD -- ops.py:483 `UOp._ranges` and ops.py:497 `UOp.ranges`. This is the
# A `dict[UOp, None]` IS A SET here, because the arena interns (ops.bend's
# why a second pass and not a seventh `Derived` field. `_ranges` reads `er.ranges` for an
# IT REUSES THE MAIN TABLE FOR `ended_ranges` rather than recomputing it, and THAT is the
type Rng is Data:
  Rng{i: U32, rs: List<&2, U32>, ok: Bool}

def Rng.i(r: Rng) -> U32:
  match r:
    case Rng{i, rs, ok}: i

def Rng.rs(r: Rng) -> List<&2, U32>:
  match r:
    case Rng{i, rs, ok}: rs

def Rng.ok(r: Rng) -> Bool:
  match r:
    case Rng{i, rs, ok}: ok

# `ret.update(other)`: the elements of `ys` that `acc` does not already hold, APPENDED, so
def set_union.go(ys: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ys:
    case Nil{}: acc
    case +y <> t: set_union.go(t, Bool.pick(List<&2, U32>, mem_u32(acc, y), acc, List.append(&2, U32, acc, [y])))

def set_union(+xs: List<&2, U32>, ys: List<&2, U32>) -> List<&2, U32>:
  set_union.go(ys, xs)

# `ret.pop(s, None)` for every `s` in `ds`, which KEEPS the order of what survives --
# a Python dict's order is its insertion order and a pop does not reorder.
def set_del(xs: List<&2, U32>, +ds: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case +x <> t: set_del(t, ds, Bool.pick(List<&2, U32>, mem_u32(ds, x), acc, List.append(&2, U32, acc, [x])))

type RTable is Data:
  RTable{es: List<&2, Rng>}

def RTable.es(t: RTable) -> List<&2, Rng>:
  match t:
    case RTable{es}: es

def RTable.put(t: RTable, r: Rng) -> RTable:
  match t:
    case RTable{es}: RTable{List.append(&2, Rng, es, [r])}

def RTable.get.step(i: U32, +r: Rng, acc: Rng) -> Rng:
  Bool.pick(Rng, U32.is_eq(i, Rng.i(r)), r, acc)

# The same O(n) SEARCH `Kahn.get` is, and for the same reason: the table is in
# SWEEP order, which for a forward sweep IS index order, so the search stops at the row.
def RTable.get.go(+i: U32, rs: List<&2, Rng>, acc: Rng) -> Rng:
  match rs:
    case Nil{}: acc
    case r <> t: RTable.get.go(i, t, RTable.get.step(i, r, acc))

# "no row yet" and "the fold does not know" are the SAME row, which is why the default
# is `ok: False{}` and not an empty set: an absent row must not read as "no ranges".
def RTable.get(t: RTable, +i: U32) -> Rng:
  RTable.get.go(i, RTable.es(t), Rng{i, Nil{}, False{}})

# `UOp.ranges` -- ops.py:497. The ONLY difference from `_ranges` is this prepend, and a
# prepend is why the union cannot use the raw table rows: `for s in self.src` reads
# `s.ranges`, which for a RANGE src is the src ITSELF.
def rng_of.put(i: U32, pre: Bool, +r: Rng) -> Rng:
  Rng{i, Bool.pick(List<&2, U32>, pre, List.append(&2, U32, [Rng.i(r)], Rng.rs(r)), Rng.rs(r)), Rng.ok(r)}

def rng_of(+ar: O.Arena, t: RTable, +i: U32) -> Rng:
  rng_of.put(i, is_range.of(O.Arena.op(ar, i)), RTable.get(t, i))

# `for s in self.src: ret.update(s.ranges)` -- the union, in src order, and the flag
def rng_union.put(+acc: Rng, +s: Rng) -> Rng:
  Rng{Rng.i(acc), Bool.pick(List<&2, U32>, Rng.ok(s), set_union(Rng.rs(acc), Rng.rs(s)), Rng.rs(acc)),
      Bool.and(Rng.ok(acc), Rng.ok(s))}

def rng_union.go(+ar: O.Arena, +t: RTable, ss: List<&2, U32>, +acc: Rng) -> Rng:
  match ss:
    case Nil{}: acc
    case s <> tl: rng_union.go(ar, t, tl, rng_union.put(acc, rng_of(ar, t, s)))

def rng_union(+ar: O.Arena, +t: RTable, ss: List<&2, U32>, i: U32) -> Rng:
  rng_union.go(ar, t, ss, Rng{i, Nil{}, True{}})

# the `for er in self.ended_ranges` pops, as ONE delete set: a pop is idempotent, so
# `Del` is its own record and not an `Rng` because a delete set has no node index, and
type Del is Data:
  Del{ds: List<&2, U32>, ok: Bool}

def Del.ds(d: Del) -> List<&2, U32>:
  match d:
    case Del{ds, ok}: ds

def Del.ok(d: Del) -> Bool:
  match d:
    case Del{ds, ok}: ok

def del_un(+a: Del, +b: Del) -> Del:
  Del{set_union(Del.ds(a), Del.ds(b)), Bool.and(Del.ok(a), Del.ok(b))}

# `er`'s own live set, as a delete set. `RTable.get` already answers `ok: False{}` for
# an absent row, so the refusal needs no arm of its own.
def del_of.row(+r: Rng) -> Del:
  Del{Rng.rs(r), Rng.ok(r)}

# THE ONE CONDITIONAL, and it is the whole `if er.op is Ops.RANGE ... else ...`: a RANGE
# `er` deletes ITSELF and anything else deletes its own live set. `Bool.pick` is strict,
# so the `RTable.get` runs on both arms -- it is a search over a table this sweep has
# already filled, and `er < i` is the sweep's whole ordering argument.
def del_of.er(+ar: O.Arena, +t: RTable, +er: U32) -> Del:
  Bool.pick(Del, is_range.of(O.Arena.op(ar, er)), Del{[er], True{}}, del_of.row(RTable.get(t, er)))

def rng_dels.go(+ar: O.Arena, +t: RTable, ers: List<&2, U32>, +acc: Del) -> Del:
  match ers:
    case Nil{}: acc
    case +er <> tl: rng_dels.go(ar, t, tl, del_un(acc, del_of.er(ar, t, er)))

# "no `ended` list" and "an empty one" are the same delete set and differ only in the
# flag, which is the whole of the `Derived`-field refusal this fold inherits.
def rng_dels.m(ar: O.Arena, t: RTable, m: Maybe<&2, List<&2, U32>>) -> Del:
  match m:
    case Some{ers}: rng_dels.go(ar, t, ers, Del{Nil{}, True{}})
    case None{}: Del{Nil{}, False{}}

def rng_dels(+ar: O.Arena, +t: RTable, m: Maybe<&2, List<&2, U32>>) -> Del:
  rng_dels.m(ar, t, m)

def rng_del.put(+acc: Rng, +d: Del) -> Rng:
  Rng{Rng.i(acc), set_del(Rng.rs(acc), Del.ds(d), Nil{}), Bool.and(Rng.ok(acc), Del.ok(d))}

# ONE NODE, and it is `_ranges` and not `ranges`: the union, then the pops, and the
# `{self:None} |` prepend is the READER's (`rng_of` above), because the table holds
# `_ranges` and a RANGE's own row is what the union needs to see.
def rng_of.got(+ar: O.Arena, +t: RTable, +i: U32, d: Del) -> Rng:
  rng_del.put(rng_union(ar, t, O.Arena.srcs(ar, i), i), d)

def rng_of.node(+ar: O.Arena, +main: Table, +t: RTable, +i: U32) -> Rng:
  rng_of.got(ar, t, i, rng_dels(ar, t, fold.ended(ar, main, i)))

# THE SWEEP. `k` is the arena INDEX and it is a parameter rather than `List.length`,
# because the node list IS the index space: `Kahn.seed` numbers it the same way.
def rng_sweep.go(+ar: O.Arena, +main: Table, ns: List<&2, O.Node>, +k: U32, +t: RTable) -> RTable:
  match ns:
    case Nil{}: t
    case _ <> tl: rng_sweep.go(ar, main, tl, U32.add(k, 1), RTable.put(t, rng_of.node(ar, main, t, k)))

def rng_sweep(+ar: O.Arena, +main: Table) -> RTable:
  rng_sweep.go(ar, main, O.Arena.nodes(ar), 0, RTable{Nil{}})

# THE READER. `UOp.ranges(ar, rt, i)` is a sweep read, and there is no
# `UOp.ranges(ar, i)` here for the reason the header gives for `UOp.dtype`: answering one
# node IS the sweep. It does not take the main `Table` because the sweep closed over it.
def UOp.ranges(ar: O.Arena, rt: RTable, i: U32) -> Rng:
  rng_of(ar, rt, i)

# The main fold ONCE, then the sweep over the FINISHED table. That order is the whole
type Ranged is Data:
  Ranged{ar: O.Arena, rt: RTable}

def Ranged.ar(x: Ranged) -> O.Arena:
  match x:
    case Ranged{ar, rt}: ar

def Ranged.rt(x: Ranged) -> RTable:
  match x:
    case Ranged{ar, rt}: rt

def Ranged.of(+ar: O.Arena, +tb: Table) -> Ranged:
  Ranged{ar, rng_sweep(ar, tb)}

def ranged(+ar: O.Arena) -> Ranged:
  Ranged.of(ar, UOp.fold(ar))

# THE `_min_max` WALK -- ops.py:1104's fold, and the last of the three pieces the foot of
# why a sweep and not a seventh `Derived` field, which is the one decision here rather
# the price, stated rather than assumed away: the dtype is read from the MAIN table, so a

type MBr is Data:
  MBr{i: U32, b: Maybe<&2, Bnd2>}

type BTable is Data:
  BTable{es: List<&2, MBr>}

def BTable.es(t: BTable) -> List<&2, MBr>:
  match t:
    case BTable{es}: es

def BTable.put(t: BTable, r: MBr) -> BTable:
  match t:
    case BTable{es}: BTable{List.append(&2, MBr, es, [r])}

def MBr.i(r: MBr) -> U32:
  match r:
    case MBr{i, b}: i

def MBr.b(r: MBr) -> Maybe<&2, Bnd2>:
  match r:
    case MBr{i, b}: b

def BTable.get.step(i: U32, +r: MBr, acc: MBr) -> MBr:
  Bool.pick(MBr, U32.is_eq(i, MBr.i(r)), r, acc)

# THE SAME O(n) SEARCH `Kahn.get` IS, and the default is a REFUSAL rather than an
# interval: `mm.src2`'s `mm.unbound()` is for a src index past the END of a list, and a
# node this sweep has not reached is a different thing, so the two must not read alike.
def BTable.get.go(+i: U32, es: List<&2, MBr>, acc: MBr) -> MBr:
  match es:
    case Nil{}: acc
    case r <> t: BTable.get.go(i, t, BTable.get.step(i, r, acc))

def BTable.get(t: BTable, +i: U32) -> MBr:
  BTable.get.go(i, BTable.es(t), MBr{i, None{}})

# THE SRCS' INTERVALS, IN SRC ORDER, and the order is the whole of `SUB`'s arm: a walk
# that appended to the front, or built the list from the node list rather than from
# `Arena.srcs`, hands the table a reversed pair and `mmk_sub34` moves.
def mm.gather.step(hit: Maybe<&2, Bnd2>, acc: Maybe<&2, List<&2, Bnd2>>) -> Maybe<&2, List<&2, Bnd2>>:
  Maybe.bind(&2, Bnd2, List<&2, Bnd2>, hit,
    b => Maybe.bind(&2, List<&2, Bnd2>, List<&2, Bnd2>, acc, xs => Some{List.append(&2, Bnd2, xs, [b])}))

def mm.gather.go(+t: BTable, ss: List<&2, U32>, acc: Maybe<&2, List<&2, Bnd2>>) -> Maybe<&2, List<&2, Bnd2>>:
  match ss:
    case Nil{}: acc
    case s <> tl: mm.gather.go(t, tl, mm.gather.step(MBr.b(BTable.get(t, s)), acc))

def mm.gather(+t: BTable, ss: List<&2, U32>) -> Maybe<&2, List<&2, Bnd2>>:
  mm.gather.go(t, ss, Some{Nil{}})

# ONE NODE. A src this sweep could not answer, or a dtype the main fold could not, leaves
# the node unanswered -- the same one-directional rule as `Kahn.gather`, and the two are
# the same rule: the reader is a table read and an absent row is a refusal.
def mm.node.of(d: Maybe<&2, S.Dt>, +ar: O.Arena, +i: U32, ss: Maybe<&2, List<&2, Bnd2>>) -> MBr:
  match d ss:
    case Some{dt} Some{xs}: MBr{i, Some{mm.lift(O.Arena.op(ar, i), xs, O.Arena.arg(ar, i), dt)}}
    case _ _: MBr{i, None{}}

def mm.node(+ar: O.Arena, +main: Table, +t: BTable, +i: U32) -> MBr:
  mm.node.of(fold.dt(ar, main, i), ar, i, mm.gather(t, O.Arena.srcs(ar, i)))

# THE SWEEP. `k` is the arena INDEX and a parameter rather than `List.length`, for
# `rng_sweep`'s reason: the node list IS the index space, `Kahn.seed` numbers it the
# same way, and index 0 is the bottom, which gets a row like any other.
def mm.sweep.go(+ar: O.Arena, +main: Table, ns: List<&2, O.Node>, +k: U32, +t: BTable) -> BTable:
  match ns:
    case Nil{}: t
    case _ <> tl: mm.sweep.go(ar, main, tl, U32.add(k, 1), BTable.put(t, mm.node(ar, main, t, k)))

def mm.sweep(+ar: O.Arena, +main: Table) -> BTable:
  mm.sweep.go(ar, main, O.Arena.nodes(ar), 0, BTable{Nil{}})

# THE READERS. `UOp.min_max(ar, bt, i)` and not `UOp.min_max(ar, i)`, for the reason the
# header gives for `UOp.dtype`: answering one node IS the sweep.
def UOp.min_max(ar: O.Arena, bt: BTable, i: U32) -> Maybe<&2, Bnd2>:
  MBr.b(BTable.get(bt, i))

# `vmin` and `vmax` -- ops.py:1100 and ops.py:1102, the two halves by name. They are
# readers and not arithmetic, so each is `Bnd2.lo`/`Bnd2.hi` and nothing else, and
# `mmk_vmin`/`mmk_vmax` are the rows that notice a transposition the pair would hide.
def UOp.vmin(ar: O.Arena, bt: BTable, i: U32) -> Maybe<&2, Bnd>:
  Maybe.map(&2, Bnd2, Bnd, Bnd2.lo, UOp.min_max(ar, bt, i))

def UOp.vmax(ar: O.Arena, bt: BTable, i: U32) -> Maybe<&2, Bnd>:
  Maybe.map(&2, Bnd2, Bnd, Bnd2.hi, UOp.min_max(ar, bt, i))

# `overflows` -- ops.py:661: `self.vmin < dtype.min or dtype.max < self.vmax`.
#
# FOUR ANSWERS AND EACH IS A MEASUREMENT:
def ovf.mag(k: U32) -> H.I64: H.i64_shl(H.i64_of_i32(1), U32.to_nat(k))

def ovf.min_b(signed: Bool, bits: U32) -> Bnd:
  match signed:
    case True{} : BndInt{True{}, ovf.mag(U32.sub(bits, 1))}
    case False{}: BndInt{False{}, H.i64_of_i32(0)}

def ovf.max_b(signed: Bool, bits: U32) -> Bnd:
  match signed:
    case True{} : BndInt{False{}, H.i64_sub(ovf.mag(U32.sub(bits, 1)), H.i64_of_i32(1))}
    case False{}: BndInt{False{}, H.i64_sub(ovf.mag(bits), H.i64_of_i32(1))}

def ovf.lt_min(signed: Bool, bits: U32, +v: Bnd) -> Bool:
  match signed:
    case True{} : bnd.lt(v, ovf.min_b(True{}, bits))
    case False{}: bnd.lt(v, ovf.min_b(False{}, bits))

def ovf.gt_max(signed: Bool, bits: U32, +v: Bnd) -> Bool:
  match signed:
    case True{} : bnd.lt(ovf.max_b(True{}, bits), v)
    case False{}: bnd.lt(ovf.max_b(False{}, bits), v)

def ovf.wide(n: Bool, +signed: Bool, +bits: U32, +vmin: Bnd, +vmax: Bnd) -> Bool:
  match n:
    case True{} : False{}
    case False{}: Bool.or(ovf.lt_min(signed, bits, vmin), ovf.gt_max(signed, bits, vmax))

def ovf.hi(+a: Bnd, hi: Maybe<&2, Bnd>, signed: Bool, +bits: U32, wide: Bool) -> Bool:
  match hi:
    case Some{+b}: ovf.wide(wide, signed, bits, a, b)
    case None{}  : True{}

def ovf.lo(lo: Maybe<&2, Bnd>, hi: Maybe<&2, Bnd>, signed: Bool, +bits: U32, wide: Bool) -> Bool:
  match lo:
    case Some{+a}: ovf.hi(a, hi, signed, bits, wide)
    case None{}  : True{}

def ovf.f(+ar: O.Arena, +bt: BTable, +i: U32, w: Bool, sgn: Maybe<&1, Bool>, +bits: U32) -> Bool:
  match w:
    case True{} : False{}
    case False{}: ovf.lo(UOp.vmin(ar, bt, i), UOp.vmax(ar, bt, i), Maybe.default(&1, Bool, sgn, False{}), bits, U32.is_gt(bits, 63))

def ovf.cls(ar: O.Arena, bt: BTable, i: U32, +cls: S.Cls, +bits: U32) -> Bool:
  match cls:
    case S.CFloat{}    : False{}
    case S.CWeakFloat{}: False{}
    case _             : ovf.f(ar, bt, i, False{}, S.Cls.sgn(cls), bits)

def UOp.overflows(ar: O.Arena, bt: BTable, i: U32, +dt: S.Dt) -> Bool:
  ovf.cls(ar, bt, i, S.Dt.cls(dt), S.Dt.bits(dt))

# `UOp.bool_slice` -- ops.py:284-287:
# the set is not materialised, and this is the measured reason: the only consumer in the whole of
# `tinygrad/` is a MEMBERSHIP TEST -- `symbolic.py:235`, `cond not in t.bool_slice and cond not in
# so the answer is `want` is BOOL and `want` is reachable through `src` edges, which for a
def bs.dt(+ar: O.Arena, +bt: BTable, i: U32) -> Bool:
  dt_is(folded(ar), i, S.boolean())

def UOp.bs_reach(fuel: Nat, +ar: O.Arena, todo: List<&2, U32>, +want: U32) -> Bool:
  match fuel todo:
    case 0n Nil{}: False{}
    case 1n+p Nil{}: False{}
    case 0n +h <> rest: False{}
    case 1n+p +h <> rest:
      Bool.or(U32.is_eq(h, want), UOp.bs_reach(p, ar, List.concat(&2, U32, [O.Arena.srcs(ar, h), rest]), want))

def UOp.bool_slice_has(fuel: Nat, +ar: O.Arena, +bt: BTable, root: U32, +want: U32) -> Bool:
  Bool.and(bs.dt(ar, bt, want), UOp.bs_reach(fuel, ar, [root], want))

# The main fold ONCE, then the sweep over the FINISHED table, for `Ranged`'s reason: the
# sweep reads dtypes, and only a complete main table answers one everywhere. The main
# `Table` is not a field -- the sweep closed over it.
type MMed is Data:
  MMed{ar: O.Arena, bt: BTable}

def MMed.ar(x: MMed) -> O.Arena:
  match x:
    case MMed{ar, bt}: ar

def MMed.bt(x: MMed) -> BTable:
  match x:
    case MMed{ar, bt}: bt

def MMed.of(+ar: O.Arena, +tb: Table) -> MMed:
  MMed{ar, mm.sweep(ar, tb)}

def min_maxed(+ar: O.Arena) -> MMed:
  MMed.of(ar, UOp.fold(ar))

# THE RANGES ROWS. `oracles/fold-rng-oracle.py` builds the same twelve
def rg_rng(ar: O.Arena, end: U32, axis: U32) -> O.Found:
  O.UOp.range_end(ar, end, [axis], O.AXIS_LOOP{})

def rg_c(ar: O.Arena, n: U32) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(n)})

def rg_st(ar: O.Arena, a: O.Found, b: O.Found) -> O.Found:
  O.UOp.new(ar, O.OpsSTACK{}, [O.Found.i(a), O.Found.i(b)], O.ANone{}, O.TNone{})

def rg_cf(ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsCUSTOM_FUNCTION{}, Nil{}, O.ACustom{O.CustomFunction{"myext", S.void()}}, O.TNone{})

# NO RANGE ANYWHERE: the empty set, and the same `Nil` the union's seed carries.
def rg_f_none() -> O.Found:
  rg_c(O.Arena.empty(), 4)

# A RANGE AS THE ROOT: the `{self:None} | _ranges` PREPEND, and a prepend is invisible
# from anywhere else.
def rg_f_self() -> O.Found:
  +c = rg_c(O.Arena.empty(), 4)
  rg_rng(O.Found.ar(c), O.Found.i(c), 0)

# THE UNION, BOTH SRC ORDERS. `dict.update` keeps a key's FIRST position, so these two
# graphs have the same SET and two different rows -- and a union that forgot its order
# could not tell them apart.
def rg_f_two() -> O.Found:
  +c = rg_c(O.Arena.empty(), 4)
  +r0 = rg_rng(O.Found.ar(c), O.Found.i(c), 0)
  +r1 = rg_rng(O.Found.ar(r0), O.Found.i(c), 1)
  rg_st(O.Found.ar(r1), r0, r1)

def rg_f_rev() -> O.Found:
  +c = rg_c(O.Arena.empty(), 4)
  +r0 = rg_rng(O.Found.ar(c), O.Found.i(c), 0)
  +r1 = rg_rng(O.Found.ar(r0), O.Found.i(c), 1)
  rg_st(O.Found.ar(r1), r1, r0)

# THE SAME RANGE TWICE. `ADD(r0, r0)` names it twice, so a MULTISET answer prints it
# twice. This is bend2-constraints.md's "membership where the count is wanted" family,
# on the set side.
def rg_f_dup() -> O.Found:
  +c = rg_c(O.Arena.empty(), 4)
  +r0 = rg_rng(O.Found.ar(c), O.Found.i(c), 0)
  O.UOp.new(O.Found.ar(r0), O.OpsADD{}, [O.Found.i(r0), O.Found.i(r0)], O.ANone{}, O.TNone{})

# `END`'s OWN ARM -- `tuple(r for r in src[1:] if r.op is Ops.RANGE)`, and NOT
# `range_start[END]`. Two of the three end and the one at src[0] does not, so a reading
# that pops src[0] as well answers `[]` where CPython answers `[R(0)]`.
def rg_f_end() -> O.Found:
  +c = rg_c(O.Arena.empty(), 4)
  +r0 = rg_rng(O.Found.ar(c), O.Found.i(c), 0)
  +r1 = rg_rng(O.Found.ar(r0), O.Found.i(c), 1)
  +r2 = rg_rng(O.Found.ar(r1), O.Found.i(c), 2)
  O.UOp.end(O.Found.ar(r2), O.Found.i(r0), [O.Found.i(r1), O.Found.i(r2)])

# `AFTER`'s arm is the flatten of its srcs' ended lists, not `src[1:]`: the end at
# src[1] is what ends `r1` here, and reading `src[1:]` as the delete list would end the
# END and not `r1`.
def rg_f_after() -> O.Found:
  +c = rg_c(O.Arena.empty(), 4)
  +r0 = rg_rng(O.Found.ar(c), O.Found.i(c), 0)
  +r1 = rg_rng(O.Found.ar(r0), O.Found.i(c), 1)
  +e = O.UOp.end(O.Found.ar(r1), O.Found.i(r0), [O.Found.i(r1)])
  O.UOp.after(O.Found.ar(e), O.Found.i(c), [O.Found.i(e)])

# `BARRIER` flattens over ALL ITS SRCS, so `r1` arrives twice -- once under the END and
# once inside it -- and is popped once, while `r2` stays and stays in union order.
def rg_f_barrier() -> O.Found:
  +c = rg_c(O.Arena.empty(), 4)
  +r0 = rg_rng(O.Found.ar(c), O.Found.i(c), 0)
  +r1 = rg_rng(O.Found.ar(r0), O.Found.i(c), 1)
  +r2 = rg_rng(O.Found.ar(r1), O.Found.i(c), 2)
  +e = O.UOp.end(O.Found.ar(r2), O.Found.i(r0), [O.Found.i(r1)])
  O.UOp.new(O.Found.ar(e), O.OpsBARRIER{}, [O.Found.i(e), O.Found.i(r2)], O.ANone{}, O.TNone{})

# THE `else` BRANCH, and the one that needs `er.ranges`. `BACKEDGE`'s ended list is
# `src[1:2]`, so the STACK at src[1] is the `er`, and `er` is NOT a RANGE: the delete set
# is `STACK(r1,r1).ranges` = {R(1)} and not {STACK}. `r0` at src[0] is the `self` and
# does NOT end, so this row is also the `src[1:2]` off-by-one.
def rg_f_er() -> O.Found:
  +c = rg_c(O.Arena.empty(), 4)
  +r0 = rg_rng(O.Found.ar(c), O.Found.i(c), 0)
  +r1 = rg_rng(O.Found.ar(r0), O.Found.i(c), 1)
  +st = rg_st(O.Found.ar(r1), r1, r1)
  O.UOp.backedge(O.Found.ar(st), O.Found.i(r0), O.Found.i(st), O.Found.i(c))

# `CALL`'s ONE CONDITIONAL, twice: a CUSTOM_FUNCTION body ends nothing and a CONST body
# the `CallInfo` dtype is `src[0]`'s dtype, per candidate, and that is the whole reason
# IT IS A PARAMETER NOW. The old fixture put `S.int32()` in the field of both rows and its
# comment said the non-void was NECESSARY: `call_ds.go` was `some_if(not dt is void, ...)`,
# and both rows read ABSENT. That reason died on 2026-10-06 with `call_ds.go` itself,
# so a non-void kept in place would have been a probe passing for a reason its own comment
# had disowned. MEASURED, `.agents/slop/loopfix/callprobe.out`: CPython reads a CALL's
def rg_call(ar: O.Arena, body: U32, a: U32, b: U32, dt: S.Dt) -> O.Found:
  O.UOp.new(ar, O.OpsCALL{}, [body, a, b],
    O.ACall{O.CallInfo{None{}, False{}, False{}, dt}}, O.TNone{})

def rg_f_call_cf() -> O.Found:
  +c = rg_c(O.Arena.empty(), 4)
  +r0 = rg_rng(O.Found.ar(c), O.Found.i(c), 0)
  +r1 = rg_rng(O.Found.ar(r0), O.Found.i(c), 1)
  +cf = rg_cf(O.Found.ar(r1))
  rg_call(O.Found.ar(cf), O.Found.i(cf), O.Found.i(r0), O.Found.i(r1), S.void())

def rg_f_call_c() -> O.Found:
  +c = rg_c(O.Arena.empty(), 4)
  +r0 = rg_rng(O.Found.ar(c), O.Found.i(c), 0)
  +r1 = rg_rng(O.Found.ar(r0), O.Found.i(c), 1)
  rg_call(O.Found.ar(r1), O.Found.i(c), O.Found.i(r0), O.Found.i(r1), S.weakint())

# THE REFUSAL, and it is the divergence the header names: `STAGE` is a DEFERRED op in
# `dt_shape`, so `ended_ranges` is not in the main table and neither is the set. CPython
# has no such limit, so the oracle records its answer in a DIVERGES block rather than
# printing a row the two lanes could agree on.
def rg_f_absent() -> O.Found:
  +c = rg_c(O.Arena.empty(), 4)
  +r0 = rg_rng(O.Found.ar(c), O.Found.i(c), 0)
  +r1 = rg_rng(O.Found.ar(r0), O.Found.i(c), 1)
  +st = rg_st(O.Found.ar(r1), r0, r1)
  O.UOp.new(O.Found.ar(st), O.OpsSTAGE{}, [O.Found.i(c), O.Found.i(st)], O.ANone{}, O.TNone{})

def ids_str.go(xs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: ids_str.go(t, List.append(&2, String, acc, [U32.show(x)]))

def ids_str(xs: List<&2, U32>) -> String:
  String.concat(["(", String.join(ids_str.go(xs, Nil{}), ","), ")"])

def rng_lab.of(+ar: O.Arena, i: U32) -> String:
  String.concat(["R", ids_str(Maybe.default(&2, List<&2, U32>, UOp.axis_id(ar, i), Nil{}))])

def rng_lab.go(+ar: O.Arena, rs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case x <> t: rng_lab.go(ar, t, List.append(&2, String, acc, [rng_lab.of(ar, x)]))

# `ABSENT` is this file's "this fold cannot answer", and it is the same word the other
# readers use, so a refused set is not mistakable for an empty one.
def rng_str(+ar: O.Arena, r: Rng) -> String:
  match r:
    case Rng{i, rs, True{}}: String.concat(["[", String.join(rng_lab.go(ar, rs, Nil{}), ","), "]"])
    case Rng{i, rs, False{}}: "ABSENT"

def rng_of_row(nm: String, +f: O.Found) -> IO(Unit):
  +x = ranged(O.Found.ar(f))
  IO.print(String.concat(["rg_", nm, " ranges=",
    rng_str(Ranged.ar(x), UOp.ranges(Ranged.ar(x), Ranged.rt(x), O.Found.i(f)))]))

# THE MOVEMENT FIXTURES AND ROWS: `dt_shape`'s arms for ops.py:414-431's five
# WHY ONE STRING. Four separate rows let a fixture drop one of them, and a PAD or
def g_mv_pa() -> O.ParamArg:
  O.ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
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

# RESHAPE(BUFFER(6), STACK(2, 3)) -- shape (2, 3), the PERMUTE src. SIX and
# not twelve: the RESHAPE's own product check is `prod(ps) != prod(marg)`, so the
# buffer must hold 2*3 elements. MEASURED, not assumed -- a size-12 buffer answers
# `bad reshape: (12,) -> (2, 3)` in CPython and is refused here, and the first
def g_mv_r23() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{6}, O.AParam{g_mv_pa()}, O.TNone{})
  g_mv_r23_of(b)

# EXPAND(BUFFER(4), CONST(2)) -- `n=3 op=EXPAND nsrc=2 srcops=BUFFER|CONST
# shape=(2,4) dtype=int`. `_mop` collapses a ONE-ELEMENT shape arg to a bare CONST
# (`shape_to_shape_arg` returns `src[0]` for a 1-tuple, ops.py:110), which is what
# makes this fixture the `marg.one` arm rather than the `marg.stack` one.
def g_mv_exp1() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(2)})
  O.UOp.new(O.Found.ar(c), O.OpsEXPAND{}, [O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

# EXPAND(BUFFER(4), STACK(2, 3)) -- `shape=(2,3,4)`, the two-element marg and the
# `marg.stack.go` arm.
def g_mv_exp23() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +k = g_mv_st23(O.Found.ar(b))
  O.UOp.new(O.Found.ar(k), O.OpsEXPAND{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})

# EXPAND(NOOP(BUFFER(4)), CONST(2)) -- `shape=(2,4) dtype=void`. The dtype row: the
# shape arm reads `ps` (through the NOOP, ops.py:441's `return self.src[0]._shape`)
def g_mv_expnoop() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +n = O.UOp.new(O.Found.ar(b), O.OpsNOOP{}, [O.Found.i(b)], O.ANone{}, O.TNone{})
  +c = O.UOp.const(O.Found.ar(n), O.CInt{H.i64_of_i32(2)})
  O.UOp.new(O.Found.ar(c), O.OpsEXPAND{}, [O.Found.i(n), O.Found.i(c)], O.ANone{}, O.TNone{})

# expand(BUFFER(4), stack(2, special "n")) over an end of zero -- the only `ssimplify`
# DIVERGE left, and its cause is now the interval rather than the op. `SPECIAL 'N'`
# over end 0 is `[0, -1]`: `vmin > vmax`, so the value does not exist, and then
# ops.py:408's `all(x >= 0)` is DECIDABLE while `sym_dim` is not, so it refuses.
def g_mv_expsym() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +z = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(0)})
  +n = O.UOp.special(O.Found.ar(z), O.Found.i(z), "N")
  +c = O.UOp.const(O.Found.ar(n), O.CInt{H.i64_of_i32(2)})
  +k = O.UOp.new(O.Found.ar(c), O.OpsSTACK{}, [O.Found.i(c), O.Found.i(n)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(k), O.OpsEXPAND{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})

# `UOp.variable(name, lo, hi)` -- ops.py:1015-1018 -- is `ParamArg(slot, weakint,
def g_mv_var(ar: O.Arena, lo: H.I64, hi: H.I64, nm: String) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{},
    O.AParam{O.ParamArg{0, S.weakint(), Some{O.PyRange{lo, hi}}, Some{1}, Some{nm},
      S.Aalu{}, None{}, False{}, None{}, None{}, False{}, None{}}}, O.TNone{})

# THE WINDOW `UOp.variable` defaults to when a caller names one: `(0, 0xFFFFFF)`.
# MEASURED off CPython's own default, not typed.
def g_mv_var_n(ar: O.Arena, nm: String) -> O.Found:
  g_mv_var(ar, H.i64_of_i32(0), H.i64_of_i32(16777215), nm)

# reshape(BUFFER(4), stack(n, m)) -- the row that separates "simplified" from
# "flattened". TWO DIFFERENT symbolic dims in ONE shape, and CPython keeps them apart
def g_mv_reshsym_nm() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +n = g_mv_var_n(O.Found.ar(b), "n")
  +m = g_mv_var_n(O.Found.ar(n), "m")
  +k = O.UOp.new(O.Found.ar(m), O.OpsSTACK{}, [O.Found.i(n), O.Found.i(m)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(k), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})

# RESHAPE(BUFFER(3), STACK(p, 1)) with `p = variable("p", 3, 3)` -- THE OTHER
# DIRECTION, and it is the half a "just return SU" fix gets wrong. `vmin == vmax`, so
# symbolic.py:269 fires and `ssimplify` hands back the INT 3: the shape is `(3,1)`
def g_mv_reshsym_pt() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{3}, O.AParam{g_mv_pa()}, O.TNone{})
  +p = g_mv_var(O.Found.ar(b), H.i64_of_i32(3), H.i64_of_i32(3), "p")
  +c = O.UOp.const(O.Found.ar(p), O.CInt{H.i64_of_i32(1)})
  +k = O.UOp.new(O.Found.ar(c), O.OpsSTACK{}, [O.Found.i(p), O.Found.i(c)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(k), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})

# EXPAND(BUFFER(4), STACK(2, SPECIAL 'N' end 99)) -- `g_mv_expsym`'s op with a REAL
# end, so the interval is `[0, 98]`: not a point, not empty, `vmin >= 0`. It answers
# `(2,U(SPECIAL:N),4)` on both lanes, and it is the row that separates "symbolic dims
# are refusals" (which was true until `sym_dim`) from "symbolic dims are SU".
def g_mv_expsym_pos() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +e = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(99)})
  +n = O.UOp.special(O.Found.ar(e), O.Found.i(e), "N")
  +c = O.UOp.const(O.Found.ar(n), O.CInt{H.i64_of_i32(2)})
  +k = O.UOp.new(O.Found.ar(c), O.OpsSTACK{}, [O.Found.i(c), O.Found.i(n)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(k), O.OpsEXPAND{}, [O.Found.i(b), O.Found.i(k)], O.ANone{}, O.TNone{})

# RESHAPE(BUFFER(4), n) -- `shape_to_shape_arg` of a ONE-element tuple returns
# `src[0]` ITSELF (ops.py:108), so `as_shape` takes its THIRD arm,
def g_mv_reshbare_n() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +n = g_mv_var_n(O.Found.ar(b), "n")
  O.UOp.new(O.Found.ar(n), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(n)], O.ANone{}, O.TNone{})

# the same third arm with a point: `q = variable("q", 4, 4)` folds to the int 4, the
# products are 4 and 4, and the shape is `(4)` -- an AGREEING row with no `U` in it,
# which is what says the bare-PARAM arm is answered and not merely refused.
def g_mv_reshbare_q() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +q = g_mv_var(O.Found.ar(b), H.i64_of_i32(4), H.i64_of_i32(4), "q")
  O.UOp.new(O.Found.ar(q), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(q)], O.ANone{}, O.TNone{})

# THE RESIDUAL, AND IT IS A PLANNED DIVERGE. `resolve(x, False)` is
# `bool(sx.vmin) if sx.vmin == sx.vmax else False` (ops.py:66), so it is DECIDABLE --
def g_mv_reshbare_w() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +w = g_mv_var(O.Found.ar(b), H.i64_of_i32(0), H.i64_of_i32(3), "w")
  O.UOp.new(O.Found.ar(w), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(w)], O.ANone{}, O.TNone{})

# `shape_to_shape_arg` of a ONE-element tuple, which returns `src[0]` (ops.py:110) --
def g_mv_cst(ar: O.Arena, n: U32) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(n)})

# `shape_to_shape_arg` of a TWO-element tuple whose values are NOT the (2, 3) above.
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
def g_mv_shr23() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{6}, O.AParam{g_mv_pa()}, O.TNone{})
  +r = g_mv_r23_of(b)
  +o = g_mv_st01(O.Found.ar(r))
  +z = g_mv_st21(O.Found.ar(o))
  O.UOp.new(O.Found.ar(z), O.OpsSHRINK{}, [O.Found.i(r), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# PAD(BUFFER(4), CONST(0), CONST(6)) -- `n=4 op=Ops.PAD nsrc=3
# srcops=Ops.BUFFER|Ops.CONST|Ops.CONST shape=(6) dtype=int`. Offsets 0 and size 6
# over a source dim of 4: `o + s <= sz` is `0+4 <= 6`, and the answer is the SIZE.
def g_mv_pad1() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +o = g_mv_cst(O.Found.ar(b), 0)
  +z = g_mv_cst(O.Found.ar(o), 6)
  O.UOp.new(O.Found.ar(z), O.OpsPAD{}, [O.Found.i(b), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# SHRINK(BUFFER(4), CONST(1), CONST(2)) -- `shape=(2)`: `o + sz <= s` is `1+2 <= 4`.
def g_mv_shr1() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +o = g_mv_cst(O.Found.ar(b), 1)
  +z = g_mv_cst(O.Found.ar(o), 2)
  O.UOp.new(O.Found.ar(z), O.OpsSHRINK{}, [O.Found.i(b), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# PAD with offsets (0,1) and sizes (6,5) over the (2,3) RESHAPE -- `shape=(6,5)`.
# TWO dims is the row that matters: a one-dim fixture cannot tell `o+s<=sz` from
# `o+sz<=s`, because with one dim the two sums put the same pair on the same side.
def g_mv_pad23() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{6}, O.AParam{g_mv_pa()}, O.TNone{})
  +r = g_mv_r23_of(b)
  +o = g_mv_st01(O.Found.ar(r))
  +z = g_mv_st65(O.Found.ar(o))
  O.UOp.new(O.Found.ar(z), O.OpsPAD{}, [O.Found.i(r), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# PAD whose marg is LONGER than ps -- `len(ps) != len(self.marg)`, ops.py:421's first
# disjunct, and the ValueError is `invalid pad ((0, 6), (1, 5)) for (4,)`.
def g_mv_padr() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +o = g_mv_st01(O.Found.ar(b))
  +z = g_mv_st65(O.Found.ar(o))
  O.UOp.new(O.Found.ar(z), O.OpsPAD{}, [O.Found.i(b), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# PAD whose sum fails on ONE dim -- offset 1, size 3 over a source dim of 4:
# `o + s <= sz` is `1+4 <= 3`, which is ops.py's `invalid pad ((1, 3),) for (4,)`.
def g_mv_padr2() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +o = g_mv_cst(O.Found.ar(b), 1)
  +z = g_mv_cst(O.Found.ar(o), 3)
  O.UOp.new(O.Found.ar(z), O.OpsPAD{}, [O.Found.i(b), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# SHRINK whose sum fails -- offset 1, size 4 over a source dim of 4: `o+sz<=s` is
# `1+4<=4`, which is ops.py's `invalid shrink ((1, 4),) for (4,)`. This is the ONLY
# row that tells PAD's sum from SHRINK's: `g_mv_padr2` is rejected by both, so a port
# that had the two arms swapped would pass every other row.
def g_mv_shrbad() -> O.Found:
  +b = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{g_mv_pa()}, O.TNone{})
  +o = g_mv_cst(O.Found.ar(b), 1)
  +z = g_mv_cst(O.Found.ar(o), 4)
  O.UOp.new(O.Found.ar(z), O.OpsSHRINK{}, [O.Found.i(b), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# PERMUTE(RESHAPE(6), (1, 0)) -- `n=6 op=Ops.PERMUTE nsrc=1 srcops=Ops.RESHAPE
# shape=(3,2) dtype=int`. AND THE ORDER IS IN `src[1]`, AND THE NODE
# HAS TWO SRCS -- UPSTREAM's `_mop` (`ops.py:784,790-791`) BUILDS IT AS
def g_mv_perm(ys: List<&2, U32>) -> O.Found:
  +r = g_mv_r23()
  +sk = O.shape_arg_found(O.Found.ar(r), ys)
  O.UOp.new(O.Found.ar(sk), O.OpsPERMUTE{}, [O.Found.i(r), O.Found.i(sk)], O.ANone{}, O.TNone{})

def g_mv_perm10() -> O.Found: g_mv_perm([1, 0])

# PERMUTE with a REPEATED index -- `sorted((0, 0)) != list(range(2))`, ops.py:417.
# A permutation test that only checked "every index in range" would pass this, and
# this is the row that says so.
def g_mv_permrep() -> O.Found: g_mv_perm([0, 0])

# PERMUTE with a LONGER arg than the shape -- `sorted((1, 0, 2)) != range(2)`. This
# is the row that says the LENGTH is part of the test, which is the half of
# `sorted(marg) == list(range(n))` that a bound-only test would miss.
def g_mv_permlen() -> O.Found: g_mv_perm([1, 0, 2])

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

# THE `_min_max` WALK ROWS. `.agents/slop/mm-walk-gate.py` builds the same graphs node
# every row carries the graph it is about, not only the answer, and that is why `sig4` is
# THE PREFIX IS A PARAMETER and not a constant because the `mmkx_` rows are the
#     .venv/bin/python .agents/slop/mm-walk-gate.py | grep '^mmk_' > mm-walk-py.txt
# The `^mmk_` is what excludes the `mmkx_` rows from BOTH sides, which is the same
# every row carries the graph it is about, not only the answer, and that is why `sig4` is
# THE PREFIX IS A PARAMETER and not a constant because the `mmkx_` rows are the
#     .venv/bin/python .agents/slop/mm-walk-gate.py | grep '^mmk_' > mm-walk-py.txt
# The `^mmk_` is what excludes the `mmkx_` rows from BOTH sides, which is the same
# THE MUTATION TABLE, MEASURED by `.agents/slop/mm-walk-mutate.py`, which edits, runs,
#   | mutation                                 | rows moved                        |
# MW2 IS THE INTERESTING ONE and it is this unit's own recorded trap in miniature: it
# MW6 moves nothing, and it is not a hole in the gate -- it is a difference of shape from
def mmk_str(m: Maybe<&2, Bnd2>) -> String:
  match m:
    case Some{b}: bnd2_show(b)
    case None{}  : "ABSENT"

def mmk_end(m: Maybe<&2, Bnd>) -> String:
  match m:
    case Some{b}: bnd_show(b)
    case None{}  : "ABSENT"

def mmk_row(pfx: String, nm: String, +x: MMed, +u: U32) -> IO(Unit):
  IO.print(String.concat([pfx, nm, " ", sig4(MMed.ar(x), u), " ",
                          mmk_str(UOp.min_max(MMed.ar(x), MMed.bt(x), u))]))

def mmk_of(pfx: String, nm: String, +f: O.Found) -> IO(Unit):
  mmk_row(pfx, nm, min_maxed(O.Found.ar(f)), O.Found.i(f))

# ---- the fixtures -----------------------------------------------------------------
def mw_c(ar: O.Arena, n: U32) -> O.Found:
  O.UOp.const(ar, O.CInt{H.i64_of_i32(n)})

# THE `ParamArg` BUILDER, for all three uses -- the plain int32 BUFFER, the int64 one and
# the bounded PARAM -- so no row spells a thirteen-field record and no two rows can
# disagree about its order. `vmm` is the `vmin_vmax`, which is the field the Defines arm
# reads and the only way a fixture gives a node a shape and a non-negative interval at once.
def mw_pa(dt: S.Dt, vmm: Maybe<&2, O.PyRange>) -> O.ParamArg:
  O.ParamArg{0, dt, vmm, None{}, None{}, S.AGlobal{}, None{},
    False{}, None{}, None{}, False{}, None{}}

def mw_b(+ar: O.Arena) -> O.Found:
  O.UOp.new.param(ar, O.OpsBUFFER{}, Some{4}, O.AParam{mw_pa(S.int32(), None{})}, O.TNone{})

# A BINARY OP OVER TWO CONSTs, as ONE builder for the order pair. `SUB(3,4)` is `(-1,-1)`
# and `SUB(4,3)` is `(1,1)`, so the two rows differ only in the ARGUMENT ORDER here, and a
# gather that reversed the list would swap their answers rather than break one of them.
def mw_bin(op: O.Op, a: U32, b: U32) -> O.Found:
  +x = mw_c(O.Arena.empty(), a)
  +y = mw_c(O.Found.ar(x), b)
  O.UOp.new(O.Found.ar(y), op, [O.Found.i(x), O.Found.i(y)], O.ANone{}, O.TNone{})

# THE TRANSITIVE ROW. `MUL` is at depth 1 and `SUB` at depth 2 under the `ADD`, so a
# sweep that answered one level and stopped reads `ABSENT` for the root rather than `19`.
def mw_nested() -> O.Found:
  +a = mw_c(O.Arena.empty(), 3)
  +b = mw_c(O.Found.ar(a), 4)
  +m = O.UOp.new(O.Found.ar(b), O.OpsMUL{}, [O.Found.i(a), O.Found.i(b)], O.ANone{}, O.TNone{})
  +d = mw_c(O.Found.ar(m), 10)
  +e = mw_c(O.Found.ar(d), 3)
  +s = O.UOp.new(O.Found.ar(e), O.OpsSUB{}, [O.Found.i(d), O.Found.i(e)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(s), O.OpsADD{}, [O.Found.i(m), O.Found.i(s)], O.ANone{}, O.TNone{})

# RANGE AND SPECIAL, one builder each, because `UOp.range_end` and `UOp.special` are
# sugar over an `ARange` and a bare name and a row cannot spell either.
def mw_rng(end: U32) -> O.Found:
  +c = mw_c(O.Arena.empty(), end)
  O.UOp.range_end(O.Found.ar(c), O.Found.i(c), [0], O.AXIS_LOOP{})

def mw_spec(end: U32) -> O.Found:
  +c = mw_c(O.Arena.empty(), end)
  O.UOp.special(O.Found.ar(c), O.Found.i(c), "N")

# A STACK OF THREE DIFFERENT VALUES, so `min`/`max` over the srcs cannot be answered by
# reading src[0] alone.
def mw_stack() -> O.Found:
  +a = mw_c(O.Arena.empty(), 1)
  +b = mw_c(O.Found.ar(a), 4294967294)
  +c = mw_c(O.Found.ar(b), 5)
  O.UOp.new(O.Found.ar(c), O.OpsSTACK{}, [O.Found.i(a), O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

# pad is in `GroupOp.Movement` and does not pass through, and the row that separates those
def mw_pad() -> O.Found:
  +p = O.UOp.new.param(O.Arena.empty(), O.OpsPARAM{}, Some{4}, O.AParam{mw_pa(S.int32(), Some{O.PyRange{H.i64_of_i32(5), H.i64_of_i32(9)}})}, O.TNone{})

  +o = mw_c(O.Found.ar(p), 0)
  +z = mw_c(O.Found.ar(o), 11)
  O.UOp.new(O.Found.ar(z), O.OpsPAD{}, [O.Found.i(p), O.Found.i(o), O.Found.i(z)], O.ANone{}, O.TNone{})

# A PARAM WITH `vmin_vmax`, so the Defines arm is reached with NO SRCS at all and the
# answer can only have come from the arg. The bound is `(-3,7)` because a positive-only
# pair is the same pair the PAD row needs, and two rows that cannot tell each other apart
# are one row twice.
def mw_param() -> O.Found:
  O.UOp.new.param(O.Arena.empty(), O.OpsPARAM{}, Some{4}, O.AParam{mw_pa(S.int32(), Some{O.PyRange{H.i64_of_i32(4294967293), H.i64_of_i32(7)}})}, O.TNone{})

# THE TWO WINDOW ROWS, and the reason `weak.bend` waits on this def: `2**64-1` does not
def mw_threefry() -> O.Found:
  +a = mw_c(O.Arena.empty(), 0)
  +b = mw_c(O.Found.ar(a), 0)
  +c = mw_c(O.Found.ar(b), 0)
  O.UOp.new(O.Found.ar(c), O.OpsTHREEFRY{}, [O.Found.i(a), O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

def mw_buf_i64() -> O.Found:
  O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{mw_pa(S.int64(), None{})}, O.TNone{})

# a void dtype's default arm, so `bnd_lim`'s one void arm is reached through the sweep and
# not only through a hand-built `lf` row.
def mw_noop() -> O.Found:
  +b = mw_b(O.Arena.empty())
  O.UOp.new(O.Found.ar(b), O.OpsNOOP{}, [O.Found.i(b)], O.ANone{}, O.TNone{})

# A STAGE over a CONST, with NO range src. `dt_shape`'s arm passes the dtype through
# `src[0]` and, the prepend being empty, answers `src[0].shape -- so this node SETTLES.
# The refusal case is a STAGE that CARRIES a range src (`stage_ds`), where the shape needs
# `int(r.vmax+1)` and `dt_shape` has no `BTable`; this fixture is now the ANSWERED half.
def mw_stage() -> O.Found:
  +a = mw_c(O.Arena.empty(), 0)
  O.UOp.new(O.Found.ar(a), O.OpsSTAGE{}, [O.Found.i(a)], O.ANone{}, O.TNone{})

# THE PER-NODE ROW, and the one a whole-sweep flag cannot pass. This `ADD` is built ON TOP
def mw_sibling(st: O.Found) -> O.Found:
  +b = mw_c(O.Found.ar(st), 2)
  +c = mw_c(O.Found.ar(b), 5)
  O.UOp.new(O.Found.ar(c), O.OpsADD{}, [O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

# THE BACKEDGE, three rows from ONE arena, and the ORDERING CLAIM. `src[0]` is the node
def mw_backedge() -> O.Found:
  +c4 = mw_c(O.Arena.empty(), 4)
  +sp = O.UOp.special(O.Found.ar(c4), O.Found.i(c4), "N")
  +c5 = mw_c(O.Found.ar(sp), 5)
  +rg = O.UOp.range_end(O.Found.ar(c5), O.Found.i(c5), [0], O.AXIS_LOOP{})
  O.UOp.backedge(O.Found.ar(rg), O.Found.i(sp), O.Found.i(rg), O.Found.i(sp))

# A RESHAPE OVER A SYMBOLIC MARG, which is `mv_expsym`'s own wall seen from this side: the
# interval is a PASSTHROUGH of the BUFFER's, so CPython answers the whole `int32` window
# and the fold cannot reach the node at all.
def mw_reshape() -> O.Found:
  +b = mw_b(O.Arena.empty())
  +c = mw_c(O.Found.ar(b), 4)
  +sp = O.UOp.special(O.Found.ar(c), O.Found.i(c), "N")
  O.UOp.new(O.Found.ar(sp), O.OpsRESHAPE{}, [O.Found.i(b)], O.ATuple{[O.Found.i(sp)]}, O.TNone{})

# `vmin` AND `vmax` AS TWO ROWS on the ONE node whose bounds are 63 bits apart. A pair in
# one string cannot see them exchanged, and exchanging them is the failure these two
# readers exist to make impossible -- `commit_int` reads them as two arguments. `mw_buf_i64`
# spends index 0 on the arena's bottom, so the BUFFER is at 1.
def mw_vmin() -> IO(Unit):
  +x = min_maxed(O.Found.ar(mw_buf_i64()))
  IO.print(String.concat(["mmk_vmin ", sig4(MMed.ar(x), 1), " ",
                          mmk_end(UOp.vmin(MMed.ar(x), MMed.bt(x), 1))]))

def mw_vmax() -> IO(Unit):
  +x = min_maxed(O.Found.ar(mw_buf_i64()))
  IO.print(String.concat(["mmk_vmax ", sig4(MMed.ar(x), 1), " ",
                          mmk_end(UOp.vmax(MMed.ar(x), MMed.bt(x), 1))]))

# TWO ROWS OUT OF ONE SWEEP, which is what makes the ordering claim a claim at all. A
# `do IO<Unit>` block can only BIND an `IO`, so the fold and its indices are bound ABOVE
# it and the block is the prints -- and one fold is what makes them one sweep.
def mmk_backedge() -> IO(Unit):
  +f = mw_backedge()
  +x = min_maxed(O.Found.ar(f))
  +be = O.Found.i(f)
  do IO<Unit>:
    mmk_row("mmk_", "backedge", x, be)
    mmk_row("mmk_", "backedge_sp", x, O.Arena.src(MMed.ar(x), be, 0))
    mmk_row("mmk_", "backedge_rg", x, O.Arena.src(MMed.ar(x), be, 1))

# THE SIBLING, and both nodes come out of ONE sweep with the STAGE at the lower index, so
# `lo=+0:7` beside a `mmkx_sibling_stage` reading `ABSENT` is the per-node claim in one
# row pair rather than two independent claims.
def mmk_sibling() -> IO(Unit):
  +st = mw_stage()
  +f = mw_sibling(st)
  +x = min_maxed(O.Found.ar(f))
  do IO<Unit>:
    mmk_row("mmkx_", "sibling_stage", x, O.Found.i(st))
    mmk_row("mmk_", "sibling", x, O.Found.i(f))

# A DIM AS CPython PRINTS IT. `H.i64_text` is `hi:lo` on purpose (helpers.bend:1672)
# a symbolic dim is `U(<OP>:<arg>)` and that is a fix, not cosmetics. It used to print
def dim_str.name.go(n: Maybe<&2, String>) -> String:
  match n:
    case Some{s}: s
    case None{}  : "?"

def dim_str.name(a: O.Arg) -> String:
  match a:
    case O.AParam{pa}: dim_str.name.go(O.ParamArg.name(pa))
    case O.AStr{s}   : s
    case _            : "?"

def dim_str(+ar: O.Arena, d: O.Sint) -> String:
  match d:
    case O.SU{+u}: String.concat(["U(", O.Ops.name(O.Arena.op(ar, u)), ":", dim_str.name(O.Arena.arg(ar, u)), ")"])
    case O.SI{i}: U32.show(H.lo32(i))

def dims_str.go(+ar: O.Arena, ds: List<&2, O.Sint>, acc: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}: acc
    case d <> t: dims_str.go(ar, t, List.append(&2, String, acc, [dim_str(ar, d)]))

def dims_str(+ar: O.Arena, ds: List<&2, O.Sint>) -> String:
  String.concat(["(", String.join(dims_str.go(ar, ds, Nil{}), ","), ")"])

# "no entry in the table" is `ABSENT` and "the entry is there and has no shape" is
# `RAISE` -- this file's own two-`None` distinction from the header. NEITHER is
# Python's `raise`: a `raise` and a REFUSAL are the same statement in this file's
# convention, so a diff against CPython cannot tell them apart. The rows where they
# genuinely differ are `mv_expsym` -- a SPECIAL `'N'` over an END OF ZERO, whose
# interval `[0,-1]` is EMPTY, which `sym_dim` refuses because ops.py:408's
def shape_str.go(+ar: O.Arena, m: Maybe<&2, List<&2, O.Sint>>) -> String:
  match m:
    case Some{ds}: dims_str(ar, ds)
    case None{}  : "RAISE"

def shape_str(+ar: O.Arena, m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  match m:
    case Some{g}: shape_str.go(ar, g)
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

# ONE FOLD PER ROW, read three times: `+x` and `+u` are what pay for it, and folding
# twice would be two walks of the whole arena for one answer. The arena is also
# `dim_str`'s, which is why a symbolic dim's own arg reaches the shape column.
def mv_row(nm: String, +x: Folded, +u: U32) -> IO(Unit):
  IO.print(String.concat(["mv_", nm, " ", sig4(Folded.ar(x), u),
                          " shape=", shape_str(Folded.ar(x), UOp.shape(Folded.ar(x), Folded.t(x), u)),
                          " dtype=", dt_str(UOp.dtype(Folded.ar(x), Folded.t(x), u))]))

def mv_of(nm: String, +f: O.Found) -> IO(Unit):
  mv_row(nm, folded(O.Found.ar(f)), O.Found.i(f))

# the fixture that no row read, and it is the one the defect lived in.
# - `rng_width` read a RANGE's bound, and until 2026-10-28 it refused a bound that
# - - and the fixture below is that shape: `RANGE(AFTER(CAST(CONST(5))))`, with
# a CONST bound alongside it, - so the row reads both and the difference is the
# CHAIN AND NOT THE NUMBER.
# - AND THE CONST BOUND IS A CAST'S CONST, BECAUSE UPSTREAM's `UOp.const(b, dt)`
# is `const.cast(dt)` (`ops.py:631`) and the port's `O.UOp.const` interns the bare CONST
def g_rng_after() -> O.Found:
  +c5 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(5)})
  +c5i = O.UOp.new(O.Found.ar(c5), O.OpsCAST{}, [O.Found.i(c5)], O.ADt{S.int32()}, O.TNone{})
  +af = O.UOp.new(O.Found.ar(c5i), O.OpsAFTER{}, [O.Found.i(c5i)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(af), O.OpsRANGE{}, [O.Found.i(af)], O.ARange{[0], O.AXIS_WEAK{}}, O.TNone{})

# THE ROW. `rng_width` IS `int(r.vmax)+1` (`fold.bend:1415`), - SO THE AFTER-BOUND
# RANGE must answer 5 and the CONST-bound one 4. - and the port's `rng_width`
# answered `None{}` for the first before 2026-10-28, which is a width that was refused
# AND NOT A WIDTH OF ZERO.
def t_rng_after() -> Bool:
  +ar = O.Found.ar(g_rng_after())
  +r = O.Found.i(g_rng_after())
  +w = rng_width(ar, r)
  +u = Maybe.default(&2, U32, Maybe.map(&2, H.I64, U32, H.lo32, w), 0)
  U32.is_eq(u, 5)

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
  # 1 CONST(0) (), 2 SPECIAL (), 3 CONST(4) () , 4 BUFFER (4,), 5 CONST(3) (), 6 ADD (4,)
  # RE-DERIVED, NOT NUDGED. The layout this row used to carry named 3 BUFFER, 4 CONST(3),
  # 5 ADD, which is the arena WITHOUT the size node. `UOp.new.param` interns the size node
  # FIRST (`ops.bend:3034`), so `CONST(4)` takes index 3 and every later node shifts up by
  # one. The layout above is the MEASURED one, not the recalled one: see
  Bool.and(Bool.and(shape_is(x, 6, [sint_of(4)]), shape_is(x, 4, [sint_of(4)])),
    Bool.and(shape_is(x, 5, Nil{}), dt_is(x, 6, S.int32())))

# the BUFFER's device and addrspace come from its ParamArg, the ADD's from "the
def t_device_ok() -> Bool:
  +x = folded(O.Found.ar(g_add()))
  Bool.and(Bool.and(Bool.and(dev_is(UOp.device(Folded.ar(x), Folded.t(x), 4), 0), dev_is(UOp.device(Folded.ar(x), Folded.t(x), 6), 0)),
    addr_is(UOp.addrspace(Folded.ar(x), Folded.t(x), 4), Some{S.AGlobal{}})),
    addr_is(UOp.addrspace(Folded.ar(x), Folded.t(x), 6), None{}))

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

# THE DEFERRED ARM, which is the other way the fold is incomplete. `g_gap` is a RESHAPE
def t_gap_ok() -> Bool:
  +x = folded(O.Found.ar(g_gap()))
  # 1 CONST(0), 2 RESHAPE (deferred), 3 STORE over it (unanswered in turn)
  Bool.and(Bool.not(Kahn.settled(Folded.ar(x), Folded.t(x))), gap_count(x, 2))

# THE 2-D FIXTURE end to end. `g_resh22`'s arena is 1 CONST(4), 2 BUFFER,
def t_resh_2d() -> Bool:
  +x = folded(O.Found.ar(g_resh22()))
  Bool.and(shape_is(x, 5, [sint_of(2), sint_of(2)]),
    Bool.and(dt_is(x, 5, S.int32()), shape_is(x, 2, [sint_of(4)])))

# THE IDENTITY TEST of movement.py:184, `return self if ret.shape == self.shape
# else ret`, from one fold: the ONE-element reshape is the no-op (4,) == (4,) and
# `resh_2d` is the (2,2) != (4,) half of the same `if`.
def t_resh_1d() -> Bool:
  +x = folded(O.Found.ar(g_resh4()))
  # 1 CONST(4) (the size node), 2 BUFFER, 3 RESHAPE -- CONST(4) hash-conses to 1
  Bool.and(shape_is(x, 3, [sint_of(4)]), shape_is(x, 2, [sint_of(4)]))

# the noop arm, the one that must not check: `STACK(2, 3)` over a noop whose shape
# is (4,), so the products are 6 and 4, and `resh_reject` proves the SAME node is
# rejected when the src is a BUFFER. Python answers (2, 3) and `void`.
def t_resh_noop() -> Bool:
  +x = folded(O.Found.ar(g_reshnoop()))
  # 1 CONST(4) (the size node), 2 BUFFER, 3 NOOP, 4 CONST(2), 5 CONST(3),
  # 6 STACK(2,3), 7 RESHAPE
  Bool.and(shape_is(x, 7, [sint_of(2), sint_of(3)]), dt_is(x, 7, S.void()))

# ALL THREE `raise`s, as three nodes the fold does NOT answer. `gap_count` is the
def t_resh_reject() -> Bool:
  +a = folded(O.Found.ar(g_resh23()))
  +b = folded(O.Found.ar(g_reshneg()))
  +c = folded(O.Found.ar(g_reshsym()))
  # the RESHAPE of each: 6 for the product mismatch, 4 for the negative dim, 7 for
  # the EMPTY interval -- each arena gained 1 CONST(4), the size node, interned
  # ahead of the BUFFER
  Bool.and(gap_count(a, 6), Bool.and(gap_count(b, 4), gap_count(c, 7)))

# THE WHOLE TABLE SETTLES, so the 2-D answer is the ARM's answer and not a lucky
# one: the same `Kahn.settled` claim `cycle_safe` makes, over a graph whose top
# node is a movement op instead of a BACKEDGE.
def t_resh_settle() -> Bool:
  +x = folded(O.Found.ar(g_resh22()))
  Kahn.settled(Folded.ar(x), Folded.t(x))

# sized/pad_to walk a shape in ops.py's order, and `pad_to` PREPENDS the ones,
def t_sized_order() -> Bool:
  Bool.and(eq_sints(Sized.s(sized([sint_of(2), sint_of(3)])), [sint_of(2), sint_of(3)]),
    eq_sints(Sized.s(pad_to(sized([sint_of(2), sint_of(3)]), 3n)),
      [sint_one(), sint_of(2), sint_of(3)]))

# THE IMAGE-SHAPE ROW, and the one M2's note asked for. `shape[-1] == 4` is a
# CONSTANT and the pre-fix body compared against `sint_one()`, so all six cases are one
# row: the constant either side, the LENGTH either side of three, the last dim in the
# wrong place, no shape at all, and a UOp dim leading a shape CPython also accepts. The
# expectations are helpers.py:37's own predicate, written as literals -- a def of the
def img_case(m: Maybe<&2, List<&2, O.Sint>>, want: Bool) -> Bool:
  bnd.same(is_image_shape(m), want)

def t_img() -> Bool:
  Bool.and(
    img_case(Some{[sint_of(32), sint_of(32), sint_of(4)]}, True{}),
    Bool.and(
      img_case(Some{[sint_of(32), sint_of(32), sint_of(3)]}, False{}),
      Bool.and(
        img_case(Some{[sint_of(4), sint_of(32), sint_of(32)]}, False{}),
        Bool.and(
          img_case(Some{[sint_of(32), sint_of(32)]}, False{}),
          Bool.and(
            img_case(None{}, False{}),
            img_case(Some{[O.SU{0}, sint_of(4), sint_of(4)]}, True{}))))))

# THE WIDTH IS NOT HARD-CODED TO `weakint`. `bnd_int` is a general statement about the
def dt_w(nm: String, +bits: U32, top: Bool) -> IO(Unit):
  dt_row(nm, bnd_int(False{}, True{}, bits), bnd_int(True{}, False{}, bits))

# `CustomFunction`: the dtype is in the ARG (ops.py:133-135, 374). Filed among the
# The rows are the (dtype, shape) PAIR and they DISAGREE, which is the only thing
#     CustomFunction('void',  dtypes.void) -> dtype=void  shape=None
# `fold.shape` is a Maybe OF a Maybe and the inner Maybe is exactly ops.py's `None`

def g_cfun(dt: S.Dt) -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsCUSTOM_FUNCTION{}, Nil{},
    O.ACustom{O.CustomFunction{"myext", dt}}, O.TNone{})

def cfun_shape_is.of(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>, empty: Bool) -> Bool:
  match m:
    case Some{Some{Nil{}}}: empty
    case Some{None{}}: Bool.not(empty)
    case _: False{}

def cfun_shape_is(+x: Folded, i: U32, empty: Bool) -> Bool:
  cfun_shape_is.of(fold.shape(Folded.ar(x), Folded.t(x), i), empty)

def t_cfun(+dt: S.Dt, empty: Bool) -> Bool:
  +f = g_cfun(dt)
  +x = folded(O.Found.ar(f))
  +i = O.Found.i(f)
  Bool.and(dt_is(x, i, dt), cfun_shape_is(x, i, empty))

# `void`'s PRIORITY, and why `Dt.pri` is 0 and not the -1 of dtype.py:118.
# `DType.priority` has exactly ONE reader in all of tinygrad -- `__lt__`, dtype.py:68,
#   * `sorted(ALL 20)` is IDENTICAL for void at pri -1, 0, 1 and 7. bitsize 0 is below
# So `-1` is UNOBSERVABLE and a `U32` cannot hold it. `pri` is a TAG in this port, not
# The three dtypes that SHARE `pri 0` -- void, weakint, bool -- are three distinct
# values of `Dt`, because `eq_dt` compares all four fields. That is why the collision
# has never been observable, and why the port keeps `pri 0` rather than inventing a
# signed encoding `U32` cannot hold.
# dtype.bend's `dtypes.all()` is SEVENTEEN -- `dtype.py:161` is
def dts_all() -> List<&2, S.Dt>:
  [S.void(), S.weakint(), S.boolean(), S.int8(), S.uint8(), S.int16(), S.uint16(),
   S.int32(), S.uint32(), S.int64(), S.uint64(), S.weakfloat(), S.fp8e4m3(),
   S.fp8e5m2(), S.fp8e4m3fnuz(), S.fp8e5m2fnuz(), S.half(), S.bfloat16(),
   S.single(), S.double()]

# three distinct `Dt`s that all carry `pri 0`, so the collision is NOT an equality
def t_pri_three_way() -> Bool:
  Bool.and(Bool.and(Bool.not(O.eq_dt(S.void(), S.weakint())),
      Bool.not(O.eq_dt(S.void(), S.boolean()))),
    Bool.and(Bool.and(U32.is_eq(S.Dt.pri(S.void()), 0),
        U32.is_eq(S.Dt.pri(S.weakint()), 0)),
      U32.is_eq(S.Dt.pri(S.boolean()), 0)))

# the totalisation: dtype.py REFUSES any pair naming void (a KeyError on 39 of 400)
def promo_is_bottom.of(+x: S.Dt, left: Bool) -> Bool:
  match left:
    case True{}: O.eq_dt(least_upper.of(S.void(), x), S.void())
    case False{}: O.eq_dt(least_upper.of(x, S.void()), S.void())

def promo_is_bottom.go(ds: List<&2, S.Dt>, ok: Bool, +left: Bool) -> Bool:
  match ds:
    case Nil{}: ok
    case +h <> t: promo_is_bottom.go(t, Bool.and(ok, promo_is_bottom.of(h, left)), left)

def t_promo_void_left() -> Bool: promo_is_bottom.go(dts_all(), True{}, True{})
def t_promo_void_right() -> Bool: promo_is_bottom.go(dts_all(), True{}, False{})

# M7's FIXTURE. `least_upper` ANDs the two masks; replacing `ma & mb` with `ma` alone
def t_meet_and() -> Bool:
  Bool.and(O.eq_dt(least_upper.of(S.boolean(), S.weakint()), S.weakint()),
    O.eq_dt(least_upper.of(S.weakint(), S.boolean()), S.weakint()))

# `bnd_lim`'s ONE void arm is `case S.Dt{0, 0, S.CVoid{}, _}: bnd_bool(top)`, and
def t_bnd_void_is_bool() -> Bool:
  Bool.and(Bool.and(String.eq(bnd_show(bnd_lim(S.void(), False{})),
      bnd_show(bnd_lim(S.boolean(), False{}))),
      String.eq(bnd_show(bnd_lim(S.void(), True{})), bnd_show(bnd_lim(S.boolean(), True{})))),
    Bool.not(String.eq(bnd_show(bnd_lim(S.void(), True{})), bnd_show(bnd_flt(True{})))))

# THE `vb_` ROWS -- `unsharded_base`, `storage_base` and `is_virtual`, the
# ONE GRAPH, THREE ANSWERS, and the fixtures are chosen so that the three
# answers are DIFFERENT somewhere. A port that answered `base` three times
#   fixture  root             base      unbase     sbase      is_virtual
# `vb_us` is the row the family exists for: upstream's `unsharded_base` steps
# `vb_cst` and `vb_cast` are the two halves of `is_virtual` and they are not
def vb_pa() -> O.ParamArg:
  O.ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

def vb_buf() -> O.Found:
  O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{4}, O.AParam{vb_pa()}, O.TNone{})

# ADD(BUFFER, CONST(3)) -- the root is NOT a step op for any of the three, so
# all three answers are the node itself.
def vb_add() -> O.Found:
  +b = vb_buf()
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(3)})
  O.UOp.new(O.Found.ar(c), O.OpsADD{}, [O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

# EXPAND(BUFFER, CONST(2)) -- a movement op, so all three step to the BUFFER.
def vb_mv() -> O.Found:
  +b = vb_buf()
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(2)})
  O.UOp.new(O.Found.ar(c), O.OpsEXPAND{}, [O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

# UNSHARD(BUFFER, RANGE(4, DEVICE)) -- the arg is the tuple of SHARDED AXES
# (upstream's `unshard` passes `arg=axis`), and the srcs are the value and one
# range per sharded axis.
def vb_us() -> O.Found:
  +b = vb_buf()
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(4)})
  +r = O.UOp.range_end(O.Found.ar(c), O.Found.i(c), [0], O.AXIS_DEVICE{})
  O.UOp.new(O.Found.ar(r), O.OpsUNSHARD{}, [O.Found.i(b), O.Found.i(r)], O.ATuple{[0]}, O.TNone{})

# AFTER(BITCAST(BUFFER)) -- BITCAST is in the storage set and NOT in the
# unsharded one, so `storage_base` goes past it and `unsharded_base` does not.
def vb_abc() -> O.Found:
  +b = vb_buf()
  +c = O.UOp.new(O.Found.ar(b), O.OpsBITCAST{}, [O.Found.i(b)], O.ADt{S.int32()}, O.TNone{})
  O.UOp.new(O.Found.ar(c), O.OpsAFTER{}, [O.Found.i(c)], O.ANone{}, O.TNone{})

# CONST(3) -- weakint, so the WEAK half of `is_virtual` fires.
def vb_cst() -> O.Found:
  O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(3)})

# CAST(CONST(3), int32) -- a STRONG dtype and NO device, so the DEVICE half
# fires on its own.
def vb_cast() -> O.Found:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(3)})
  O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{S.int32()}, O.TNone{})

# CAST(BUFFER, weakint) -- a WEAK dtype ON A DEVICE, so the WEAK half fires on
# its own. It is the only way to separate the two halves: a weak node is
# otherwise device-less, so `vb_cst` has BOTH halves firing and `vb_cast` has
# only the device one.
def vb_wc() -> O.Found:
  +b = vb_buf()
  O.UOp.new(O.Found.ar(b), O.OpsCAST{}, [O.Found.i(b)], O.ADt{S.weakint()}, O.TNone{})

# CAST(BUFFER, weakfloat) -- the OTHER weak dtype, so a `weaks` test that
# dropped `weakfloat` would move this row and not `vb_wc`.
def vb_wf() -> O.Found:
  +b = vb_buf()
  O.UOp.new(O.Found.ar(b), O.OpsCAST{}, [O.Found.i(b)], O.ADt{S.weakfloat()}, O.TNone{})

# EXPAND(UNSHARD(BUFFER, RANGE), CONST(2)) -- a movement op OVER an UNSHARD, and
# the row the `unsharded_base` PLANT is measured on. `unsharded_base` steps
# ONCE into `base`, so it stops AT the UNSHARD; a port that read the src's own
# `unsharded_base` would go PAST it and answer BUFFER.
def vb_eus() -> O.Found:
  +b = vb_buf()
  +c = O.UOp.const(O.Found.ar(b), O.CInt{H.i64_of_i32(4)})
  +r = O.UOp.range_end(O.Found.ar(c), O.Found.i(c), [0], O.AXIS_DEVICE{})
  +u = O.UOp.new(O.Found.ar(r), O.OpsUNSHARD{}, [O.Found.i(b), O.Found.i(r)], O.ATuple{[0]}, O.TNone{})
  +e = O.UOp.const(O.Found.ar(u), O.CInt{H.i64_of_i32(2)})
  O.UOp.new(O.Found.ar(e), O.OpsEXPAND{}, [O.Found.i(u), O.Found.i(e)], O.ANone{}, O.TNone{})

# the answer's op name, and WHETHER THE ANSWER IS THE NODE -- the pair, because
# an op name alone cannot tell "the base is an ADD" from "the base is THIS ADD".
def vb_name(m: Maybe<&1, U32>, +ar: O.Arena) -> String:
  match m:
    case Some{u}: O.Ops.name(O.Arena.op(ar, u))
    case None{}: "ABSENT"

def vb_self(m: Maybe<&1, U32>, u: U32) -> Bool:
  match m:
    case Some{v}: U32.is_eq(v, u)
    case None{}: False{}

def vb_virt(m: Maybe<&1, Bool>) -> String:
  match m:
    case Some{b}: Bool.show(b)
    case None{}: "ABSENT"

# ONE ROW PER FIXTURE, and the row carries the graph it is about (`op=` and
# `nsrc=`) because a fixture built with the wrong op hands the table a
# different graph and a plausible answer that happens to agree is the failure
# mode this file's header records four times over.
def vb_row(nm: String, +f: O.Found) -> IO(Unit):
  +x = folded(O.Found.ar(f))
  +u = O.Found.i(f)
  +ar = Folded.ar(x)
  +tb = Folded.t(x)
  IO.print(String.concat(["vb_", nm,
    " op=", O.Ops.name(O.Arena.op(ar, u)),
    " nsrc=", U32.show(O.Arena.nsrc(ar, u)),
    " base=", vb_name(UOp.base(ar, tb, u), ar),
    " bself=", Bool.show(vb_self(UOp.base(ar, tb, u), u)),
    " unbase=", vb_name(UOp.unsharded_base(ar, tb, u), ar),
    " uself=", Bool.show(vb_self(UOp.unsharded_base(ar, tb, u), u)),
    " sbase=", vb_name(UOp.storage_base(ar, tb, u), ar),
    " sself=", Bool.show(vb_self(UOp.storage_base(ar, tb, u), u)),
    " virt=", vb_virt(UOp.is_virtual(ar, tb, u))]))

# THE `vb_` PLANT, MEASURED. `gates/fold-vbase-mutate.py` applies each
#     .venv/bin/python gates/fold-vbase-mutate.py
# THE ORACLE, and the diff that IS the test:
#     .venv/bin/python gates/fold-vbase-oracle.py > /tmp/vb_py.txt
# nine rows, and the oracle's nine are BYTE-identical to the port's nine.
# | # | mutation | rows MOVED | what it is testing |
# nine of ten MOVE rows and the one zero is the control. There is no

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("dtype_key", t_dtype_key())
    z : Unit <- row("rng_after", t_rng_after())
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
    im : Unit <- row("img_shape", t_img())
    # THE TWO CustomFunction ROWS, which DISAGREE with each other on purpose.
    cu : Unit <- row("cfun_void", t_cfun(S.void(), False{}))
    cv : Unit <- row("cfun_u64", t_cfun(S.uint64(), True{}))
    # `void`'s priority: the representation, the collision, the totalisation that
    # replaces dtype.py's KeyError, and the one reader that would answer differently
    # if `pri` moved. `promo_void_left` and `promo_void_right` are one row per side on
    # purpose -- they disagree under the asymmetry `least_upper` had until today.
    pw : Unit <- row("pri_three_way", t_pri_three_way())
    pb : Unit <- row("promo_void_left", t_promo_void_left())
    pc : Unit <- row("promo_void_right", t_promo_void_right())
    me : Unit <- row("meet_and", t_meet_and())
    bv : Unit <- row("bnd_void_is_bool", t_bnd_void_is_bool())
    # THE `vb_` ROWS -- `unsharded_base`, `storage_base` and `is_virtual`. The
    # expectations are `gates/fold-vbase-oracle.py`'s -- CPython's own
    # `base`/`unsharded_base`/`storage_base`/`is_virtual` on the SAME graphs --
    # so `diff` of the two lanes IS the test.
    vb_row("add", vb_add())
    vb_row("mv", vb_mv())
    vb_row("us", vb_us())
    vb_row("eus", vb_eus())
    vb_row("abc", vb_abc())
    vb_row("cst", vb_cst())
    vb_row("cast", vb_cast())
    vb_row("wc", vb_wc())
    vb_row("wf", vb_wf())
    # THE MOVEMENT ROWS. Four facts plus the answer, one string each, and the
    # expectations are `oracles/fold-mvt-oracle.py`'s -- CPython's own
    # `n= op= nsrc= srcops= shape= dtype=`, so `diff` of the two IS the test.
    mv_of("exp1", g_mv_exp1())
    mv_of("exp23", g_mv_exp23())
    mv_of("expnoop", g_mv_expnoop())
    mv_of("expsym", g_mv_expsym())
    # THE SYMBOLIC-DIM ROWS. `sym_dim` is what answers them, and the set is one per
    # answer it has: TWO DIFFERENT dims, a POINT, a SPECIAL over a real end, and the
    # BARE-PARAM third arm of `as_shape` -- twice, once symbolic and once a point.
    mv_of("reshsym_nm", g_mv_reshsym_nm())
    mv_of("reshsym_pt", g_mv_reshsym_pt())
    mv_of("expsym_pos", g_mv_expsym_pos())
    mv_of("reshbare", g_mv_reshbare_n())
    mv_of("reshbare_pt", g_mv_reshbare_q())
    # THE PLANNED DIVERGE, printed on this lane so the file says which way it is
    # wrong: this fold answers where CPython raises. See the oracle's DIVERGES.
    mv_of("reshbare_dis", g_mv_reshbare_w())
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
    # THE RANGES ROWS, in the oracle's order: `diff` of the two lanes is the test.
    rng_of_row("none", rg_f_none())
    rng_of_row("self", rg_f_self())
    rng_of_row("two", rg_f_two())
    rng_of_row("rev", rg_f_rev())
    rng_of_row("dup", rg_f_dup())
    rng_of_row("end", rg_f_end())
    rng_of_row("after", rg_f_after())
    rng_of_row("barrier", rg_f_barrier())
    rng_of_row("er", rg_f_er())
    rng_of_row("call_cf", rg_f_call_cf())
    rng_of_row("call_c", rg_f_call_c())
    rng_of_row("absent", rg_f_absent())
    # THE `_min_max` WALK ROWS. The exact gate command is in the section header; the
    # `mmkx_` rows are the DIVERGENCE and the oracle prints their real answers in a
    # DIVERGES block rather than in the diffed set.
    mmk_of("mmk_", "sub34", mw_bin(O.OpsSUB{}, 3, 4))
    mmk_of("mmk_", "sub43", mw_bin(O.OpsSUB{}, 4, 3))
    mmk_of("mmk_", "nested", mw_nested())
    mmk_of("mmk_", "range5", mw_rng(5))
    mmk_of("mmk_", "special4", mw_spec(4))
    mmk_of("mmk_", "stack", mw_stack())
    mmk_of("mmk_", "pad5", mw_pad())
    mmk_of("mmk_", "param", mw_param())
    mmk_of("mmk_", "threefry", mw_threefry())
    mmk_of("mmk_", "buf_i64", mw_buf_i64())
    mmk_of("mmk_", "noop", mw_noop())
    mmk_sibling()
    mmk_backedge()
    mmk_of("mmkx_", "stage", mw_stage())
    mmk_of("mmkx_", "reshape", mw_reshape())
    mw_vmin()
    mw_vmax()
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

    # the `_min_max` arithmetic rows. `.agents/slop/mm-gate.py` generates both the
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
    # the `bit_length` rows. `.agents/slop/mm-bl-gate.py` generates both the fixtures
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
# FIFTEEN OF TWENTY MOVE ROWS. The five non-movers are `M6`, whose subject went with the
# the one line that covers many: `simplify` (ops.py:495) is `graph_rewrite(self, symbolic)`,
# the five fixture requests are all the same request, they are all cheap ONCE A WALK EXISTS,
# and between them they cover the four properties of an INTERVAL -- that a difference's
# halves cross, that a product's extremes are taken over four values and not two, that a
# comparison reads the far end of one interval against the near end of the other, and that a
# monotone map trades them. An all-CONST gate cannot see any of it, because on a CONST
# interval every one of those properties is an identity.
# sixteen of nineteen MOVE rows, and all three zeros are the harness's own controls
# (R1, R2b, R11). No zero is closed with a row that would encode the equivalence as a
# check.
# the mutation table for the five movement arms, measured, run in both lanes.
# `oracles/fold-mut.py` applies each edit, re-runs both lanes and diffs the rows; the table
# is its output and nothing here is transcribed by hand. RE-TAKEN 2026-10-25.
# what M2 did not catch, because M2 tests order and this is a constant: `is_image_shape`
# answered False for `(32,32,4)`, and helpers.py:37 says True. `is_image_shape.four` is
