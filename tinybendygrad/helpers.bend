# helpers.bend -- tinygrad/helpers.py, the pure and I/O-reachable half.
#
# SCOPE. tinygrad/helpers.py is 646 lines and three of them are this port:
#   - the pure list/string/number helpers (prod, dedup, argsort, ceildiv, ...)
#   - the ContextVar/Context flag machinery, as an immutable `Flags` record
#   - the two things that need the host: `lines` (a file) and `Timing` (a clock)
# The rest is I/O or dynamic Python and is listed, with a one-line reason each,
# in the NOT PORTED block at the end of this file.
#
# `truncate` is not one of helpers.py's: it is dtype.py:296, it needs `dtypes`,
# and it lives in ./dtype.bend. See dtype.bend `def truncate`.

import Base

# ===========================================================================
# Flags -- the pure port of ContextVar / Context
#
# helpers.py's ContextVar is a mutable cell keyed by string, and Context is a
# context manager that swaps a group of them and restores on exit. Bend has no
# global mutable state, so the cell becomes a field of an immutable record and
# the manager becomes "thread a different record through" -- which is what
# `Context(DEFAULT_FLOAT=...)` means. `Flags.defaults` is the module import;
# `Flags.from_env` is the `ContextVar.__init__` `getenv(key, default)`.
#
# The values stay `String` because that is what the ContextVars hold:
# `ContextVar("DEFAULT_FLOAT", "float32")` stores the string "float32" and
# `dtypes.default_float` calls `to_dtype` on it, so the dependency direction is
# the same as Python's (dtype imports helpers).
#
# The variable list is the subset these two files read. The full list is ~40
# ContextVars and belongs to phase P6, where one `Flags` record replaces this
# one and every def that takes a `Flags` keeps its shape.
# ===========================================================================

type Flags is Data:
  Flags{no_color: Bool, default_float: String, default_int: String, sum_dtype: String}

def Flags.defaults() -> Flags:
  Flags{False{}, "float32", "int32", "float32"}

# ContextVar("NO_COLOR", 0): getenv coerces through `type(default)` and
# `__bool__` is `bool(self.value)`, so any text at all is truthy -- NO_COLOR=0
# does NOT switch colour off, and this reproduces that.
def no_color_of.go(ise: Bool) -> Bool:
  match ise:
    case True{}: False{}
    case False{}: True{}

def no_color_of(v: String) -> Bool:
  no_color_of.go(String.is_empty(v))

def getenv_str.go(v: Result<&1, &1, U32 & String, String>, d: String) -> String:
  match v:
    case Done{value}: value
    case Fail{error}: d

def getenv_str(k: String, d: String) -> IO(String):
  do IO<String>:
    v : Result<&1, &1, U32 & String, String> <- IO.get_env(k)
    return getenv_str.go(v, d)

def Flags.of(nc: String, df: String, di: String, sd: String) -> Flags:
  Flags{no_color_of(nc), df, di, sd}

def Flags.from_env() -> IO(Flags):
  do IO<Flags>:
    nc : String <- getenv_str("NO_COLOR", "")
    df : String <- getenv_str("DEFAULT_FLOAT", "float32")
    di : String <- getenv_str("DEFAULT_INT", "int32")
    sd : String <- getenv_str("SUM_DTYPE", "float32")
    return Flags.of(nc, df, di, sd)

# ===========================================================================
# prod -- functools.reduce(operator.mul, x, 1). NOTE the Python comment: it
# returns int 1 if x is empty regardless of the type of x. `List.foldl` wants a
# closure, so this is its own recursive def.
# ===========================================================================

def prod_u32(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}:
      1
    case h <> t:
      (U32.mul(h, prod_u32(t)) : U32)

def prod_nat(xs: List<&2, Nat>) -> Nat:
  match xs:
    case Nil{}:
      1n
    case h <> t:
      Nat.mul(h, prod_nat(t))

# ===========================================================================
# dedup -- list(dict.fromkeys(x)): first occurrence wins, retains list order.
# Bend's Map is string-keyed only, so the set is a linear scan.
# ===========================================================================

def dedup_u32.put(seen: Bool, h: U32, r: List<&2, U32>) -> List<&2, U32>:
  match seen:
    case True{}: r
    case False{}: h <> r

def dedup_u32.go(+x: U32, +r: List<&2, U32>) -> List<&2, U32>:
  dedup_u32.put(List.contains(U32, U32.is_eq, r, x), x, r)

def dedup_u32(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: dedup_u32.go(h, dedup_u32(t))

def dedup_str.put(seen: Bool, h: String, r: List<&2, String>) -> List<&2, String>:
  match seen:
    case True{}: r
    case False{}: h <> r

def dedup_str.go(+x: String, +r: List<&2, String>) -> List<&2, String>:
  dedup_str.put(List.contains(String, String.eq, r, x), x, r)

def dedup_str(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: dedup_str.go(h, dedup_str(t))

# ===========================================================================
# argfix -- `def argfix(*x)`. Bend has no variadics and no tuple type, so the
# Python shapes become three defs:
#   argfix([a,b])         -> argfix_seq([a,b])   (x[0] is a tuple or list)
#   argfix(a)             -> argfix1(a)          (one non-sequence argument)
#   argfix(a, b)          -> argfix2(a, b)
# Python raises ValueError when a sequence arrives alongside other arguments;
# `argfix_bad` is that ValueError, answered as a Maybe so a caller can branch.
# The two-argument `argfix` that tinygrad actually calls everywhere is
# argfix2/argfix_seq, so no third arm is missing in practice.
# ===========================================================================

def argfix_bad(sequence_with_others: Bool) -> Maybe<&1, U32>:
  match sequence_with_others:
    case True{}: Some{0}
    case False{}: None{}

def argfix1(a: U32) -> List<&2, U32>:
  [a]

def argfix2(a: U32, b: U32) -> List<&2, U32>:
  [a, b]

def argfix_seq(xs: List<&2, U32>) -> List<&2, U32>:
  xs

# ===========================================================================
# argsort -- `type(x)(sorted(range(len(x)), key=x.__getitem__))`.
# https://stackoverflow.com/questions/3382352/equivalent-of-numpy-argsort-in-basic-python
# Python's sort is stable, so the index breaks ties by position: compare
# (value, index). `List.sort` wants a closure, so the comparison is a top-level
# def over an (index, value) pair.
# ===========================================================================

type Ix is Data:
  Ix{i: U32, v: U32}

def ix_le.tie(same: Bool, i: U32, j: U32) -> Bool:
  match same:
    case True{}: U32.is_le(i, j)
    case False{}: True{}

def ix_le.cmp(le: Bool, v: U32, w: U32, i: U32, j: U32) -> Bool:
  match le:
    case True{}: ix_le.tie(U32.is_eq(v, w), i, j)
    case False{}: False{}

def ix_le(a: Ix, b: Ix) -> Bool:
  match a b:
    case Ix{i, +v} Ix{j, +w}: ix_le.cmp(U32.is_le(v, w), v, w, i, j)

# the list is field 1 so the recursive call's first argument is the shrinking one
def ix_of.go(xs: List<&2, U32>, +i: U32) -> List<&2, Ix>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: Ix{i, h} <> ix_of.go(t, U32.add(i, 1))

def ix_of(xs: List<&2, U32>) -> List<&2, Ix>:
  ix_of.go(xs, 0)

# `List.map` takes its element closure by template, and the template wants a
# List<&1, A> while `List.sort` hands back a List<&2, A>, so the projection is
# written out here rather than fought over.
def ix_index(i: Ix) -> U32:
  match i:
    case Ix{k, v}: k

def ix_map(l: List<&2, Ix>) -> List<&2, U32>:
  match l:
    case Nil{}: Nil{}
    case i <> t: ix_index(i) <> ix_map(t)

def argsort_u32(xs: List<&2, U32>) -> List<&2, U32>:
  ix_map(List.sort(Ix, ix_le, ix_of(xs)))

# ===========================================================================
# all_same -- `all(x == items[0] for x in items)`, which works for empty input.
# The head is peeled once and every other element is compared against it.
# ===========================================================================

def all_same_u32.go(xs: List<&2, U32>, +head: U32) -> Bool:
  match xs:
    case Nil{}: True{}
    case h <> t: Bool.and(U32.is_eq(h, head), all_same_u32.go(t, head))

def all_same_u32(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: True{}
    case h <> t: all_same_u32.go(t, h)

def all_same_str.go(xs: List<&2, String>, +head: String) -> Bool:
  match xs:
    case Nil{}: True{}
    case h <> t: Bool.and(String.eq(h, head), all_same_str.go(t, head))

def all_same_str(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: True{}
    case h <> t: all_same_str.go(t, h)

# ===========================================================================
# get_shape -- `def get_shape(x) -> tuple[int, ...]`
#
# DEVIATION, stated: Python walks any object with `__len__` and `__getitem__`,
# and NOTE `str` is special because iterating it still yields strs. Bend has no
# duck typing, so the input is the `Nest` tree below: `Ns` is a scalar, `Nl` is
# a sequence -- the same information Python reads off the object, made explicit
# at the boundary.
#
# Python returns () for a scalar, for a string, and for an object whose `.shape`
# is (); it raises ValueError for an inhomogeneous shape. Those are three
# outcomes, so they are three constructors and none of them is a silent None. A
# sequence of scalars is NOT (): get_shape([1,2]) is (2,) and get_shape([]) is
# (0,).
# ===========================================================================

type ShapeRes is Data:
  SNoShape{}                      # Python: ()
  SShape{dims: List<&2, U32>}     # Python: a tuple of ints, possibly ()
  SBad{why: String}               # Python: ValueError("inhomogeneous shape")

def u32_list_eq(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case h <> t h2 <> t2: Bool.and(U32.is_eq(h, h2), u32_list_eq(t, t2))
    case _ _: False{}

type Nest is Data:
  Ns{v: U32}
  Nl{ss: List<&2, Nest>}

# `ShapeRes.of` is Python's `if not all_same(subs): raise; (len(subs),) +
# subs[0]`, so a sequence of scalars has shape (n,), not (), and an empty
# sequence has shape (0,). The all_same walk is ONE def carrying the state
# Python's generator carries: `ref` is the first non-() child's dims and `bad`
# is "a () met a non()". The child list is the FIRST argument so the recursion
# decreases structurally and the rest of the state is free.
#
# The three rules are Python's `all_same`:
#   all ()        -> (n,)            every child is a scalar
#   all equal d   -> (n,) + d        the homogeneous case
#   anything else -> SBad            Python's ValueError
#
# the first child sets the reference: a scalar leaves it None, a shape sets it
def ShapeRes.dims.head(s0: ShapeRes) -> Maybe<&2, List<&2, U32>>:
  match s0:
    case SShape{d}: Some{d}
    case SNoShape{}: None{}
    case SBad{why}: None{}

# has a shaped child disagreed with the reference so far?
def ShapeRes.dims.same(ref: Maybe<&2, List<&2, U32>>, d2: List<&2, U32>) -> Bool:
  match ref:
    case None{}: False{}
    case Some{d}: Bool.not(u32_list_eq(d, d2))

def ShapeRes.dims.ref.put(ref: Maybe<&2, List<&2, U32>>, d2: List<&2, U32>) ->
  Maybe<&2, List<&2, U32>>:
  match ref:
    case None{}: Some{d2}
    case Some{d}: ref

def ShapeRes.dims.ans(ref: Maybe<&2, List<&2, U32>>, n: U32) -> ShapeRes:
  match ref:
    case None{}: SShape{[n]}
    case Some{d}: SShape{n <> d}

# Python's three-way all_same is the inner match: a child that is itself SBad
# poisons, a scalar child means the shape is (n,) so a shaped sibling is
# inhomogeneous, and a shaped child must agree with the reference.
def ShapeRes.dims(r: List<&2, ShapeRes>, bad: Bool, +ref: Maybe<&2, List<&2, U32>>,
  n: U32) -> ShapeRes:
  match r bad:
    case Nil{} True{}: SBad{"inhomogeneous shape"}
    case Nil{} False{}: ShapeRes.dims.ans(ref, n)
    case SBad{why} <> _ True{}: SBad{why}
    case SBad{why} <> _ False{}: SBad{why}
    case SNoShape{} <> _ False{}: SBad{"inhomogeneous shape"}
    case SNoShape{} <> _ True{}: SBad{"inhomogeneous shape"}
    case SShape{+d2} <> t True{}: SBad{"inhomogeneous shape"}
    case SShape{+d2} <> t False{}:
      ShapeRes.dims(t, ShapeRes.dims.same(ref, d2), ShapeRes.dims.ref.put(ref, d2), n)

def ShapeRes.of.walk(ss: List<&2, ShapeRes>, n: U32) -> ShapeRes:
  match ss:
    case Nil{}: SShape{Nil{}}
    case s0 <> r: ShapeRes.dims(r, False{}, ShapeRes.dims.head(s0), n)

def ShapeRes.of(+ss: List<&2, ShapeRes>) -> ShapeRes:
  ShapeRes.of.walk(ss, U32.from_nat(List.length(&2, ShapeRes, ss)))

# `get_shape` in Python is a mutual recursion: a node's shape is built from its
# children's shapes, and computing a child's shape recurses. Bend has no mutual
# recursion, so the walk below carries a STACK of open groups, each holding the
# children's shapes seen so far. A list of lists cannot be consed in one term
# (the `<>` operator infers a single element type), so both levels are records.
type Frame is Data:
  Frame{v: List<&2, ShapeRes>}

type Stk is Data:
  Stk{fs: List<&2, Frame>}

def stk.init() -> Stk:
  Stk{Nil{}}

# append a child's shape to the innermost open group
def stk.grow(fv: List<&2, ShapeRes>, t: List<&2, Frame>, v: ShapeRes) -> List<&2, Frame>:
  g = {Frame{List.append(&2, ShapeRes, fv, [v])} : Frame}
  g <> t

def stk.push(xs: List<&2, Frame>, v: ShapeRes) -> List<&2, Frame>:
  match xs:
    case Nil{}: [Frame{[v]}]
    case f <> t:
      match f:
        case Frame{fv}: stk.grow(fv, t, v)

def stk.push2(s: Stk, v: ShapeRes) -> Stk:
  match s:
    case Stk{fs}: Stk{stk.push(fs, v)}

# open a new (empty) frame on top of the current one
def stk.open(s: Stk) -> Stk:
  match s:
    case Stk{fs}: Stk{Frame{Nil{}} <> fs}

def stk.peek(s: Stk) -> List<&2, ShapeRes>:
  match s:
    case Stk{fs}:
      match fs:
        case Nil{}: Nil{}
        case f <> _:
          match f:
            case Frame{fv}: fv

# push a child's shape onto the frame BELOW the top one, and drop the top: this
# is what closing a group does, once its own shape has been computed from it
def stk.unpush(xs: List<&2, Frame>, v: ShapeRes) -> List<&2, Frame>:
  match xs:
    case Nil{}: [Frame{[v]}]
    case g <> t:
      match g:
        case Frame{gv}: stk.grow(gv, t, v)

# a node's children go in front of the pending work, with a GC after them
def st.splice(ss: List<&2, Nest>, t: List<&2, GIn>) -> List<&2, GIn>:
  match ss:
    case Nil{}: t
    case n <> r: GN{n} <> st.splice(r, t)

# the same splice for a list that stays a list of Nests (fully_flatten)
def st.spread(ss: List<&2, Nest>, t: List<&2, Nest>) -> List<&2, Nest>:
  match ss:
    case Nil{}: t
    case n <> r: n <> st.spread(r, t)

# The work list: GN opens a node, GC closes the group it opened.
type GIn is Data:
  GN{n: Nest}
  GC{}

# ONE def, ONE recursion, everything inlined. Python's get_shape is a mutual
# recursion (a node's shape is built from its children's shapes, and computing a
# child's shape recurses); Bend has no mutual recursion, so the children go on
# an explicit work list and the open groups on an explicit stack, which unties
# the knot into a single self-call. `k` is the FIRST parameter so `match k` then
# `match ws` then `match st` follows binder order, and every recursive call
# passes `p` in the first slot. The fuel is a backstop: the work list is finite
# by construction, and running out answers SBad rather than hanging.
#
# The three outcomes are Python's all_same over the children, computed in
# ShapeRes.of when a GC pops a frame:
#   all ()        -> (n,)
#   all equal d   -> (n,) + d
#   anything else -> SBad (Python's ValueError)
def get_shape.go(k: Nat, ws: List<&2, GIn>, st: Stk) -> ShapeRes:
  match k:
    case 0n: SBad{"shape nested too deeply"}
    case Succ{p}:
      match ws:
        case Nil{}: ShapeRes.of(stk.peek(st))
        case GC{} <> t:
          match st:
            case Stk{fs}:
              match fs:
                case Nil{}: get_shape.go(p, t, Stk{Nil{}})
                case f <> rest:
                  match f:
                    case Frame{fv}: get_shape.go(p, t, Stk{stk.unpush(rest, ShapeRes.of(fv))})
        case GN{n} <> t:
          match n:
            case Ns{v}: get_shape.go(p, t, stk.push2(st, SNoShape{}))
            case Nl{ss}: get_shape.go(p, st.splice(ss, {GC{} : GIn} <> t), stk.open(st))

# The backstop fuel, a fixed budget rather than the tree's exact node count (that
# would itself be a mutual recursion). BACKSTOP only: every node is opened once
# (one GN) and closed once (one GC), so the walk always terminates on its own.
def nest_nodes() -> Nat:
  1000000n

# a scalar is (), so a leaf root is answered before the walk starts
def get_shape.root(n: Nest, k: Nat) -> ShapeRes:
  match n:
    case Ns{v}: SNoShape{}
    case Nl{ss}: get_shape.go(k, [GN{n}], stk.init())

def get_shape(n: Nest) -> ShapeRes:
  get_shape.root(n, nest_nodes())

# is_image_shape -- `shape is not None and len(shape) == 3 and shape[-1] == 4`.
# Python's None is the "not a shape" answer, which is SNoShape or SBad here.
def is_image_shape.tail(last: Maybe<&2, U32>) -> Bool:
  match last:
    case Some{x}: U32.is_eq(x, 4)
    case None{}: False{}

def is_image_shape.dims(three: Bool, d: List<&2, U32>) -> Bool:
  match three:
    case True{}: is_image_shape.tail(List.last(&2, U32, d))
    case False{}: False{}

def is_image_shape.rank(r: ShapeRes) -> List<&2, U32>:
  match r:
    case SNoShape{}: Nil{}
    case SBad{why}: Nil{}
    case SShape{d}: d

def is_image_shape.go(+d: List<&2, U32>) -> Bool:
  match d:
    case Nil{}: False{}
    case _: is_image_shape.dims(U32.is_eq(U32.from_nat(List.length(&2, U32, d)), 3), d)

def is_image_shape(r: ShapeRes) -> Bool:
  is_image_shape.go(is_image_shape.rank(r))

# all_int -- True when every element is a Python int. On a `Nest` that is exactly
# "no Nl node anywhere": an Nl node is a sequence by construction and a sequence
# is not an int. If the ROOT is an Nl the answer is already False and if it is an
# Ns there is nothing below it, so this checks the root alone.
def all_int_nest(n: Nest) -> Bool:
  match n:
    case Ns{v}: True{}
    case Nl{ss}: False{}

# fully_flatten -- `[x for li in l for x in fully_flatten(li)]` over the same
# Nest tree, with Python's guard that a non-sequence (and a string) is `[l]`.
# ONE def over a work list with a `Nat` fuel in the first slot, because splicing
# children in front of the pending work GROWS the list. Leaves accumulate in
# `acc` and are reversed at the end, so the document order is the tree's
# preorder.
def fully_flatten.go(k: Nat, ws: List<&2, Nest>, acc: List<&2, Nest>) -> List<&2, Nest>:
  match k:
    case 0n: List.reverse(&2, Nest, acc)
    case Succ{p}:
      match ws:
        case Nil{}: List.reverse(&2, Nest, acc)
        case Ns{v} <> t: fully_flatten.go(p, t, Ns{v} <> acc)
        case Nl{ss} <> t: fully_flatten.go(p, st.spread(ss, t), acc)

def fully_flatten_nest(n: Nest) -> List<&2, Nest>:
  match n:
    case Ns{v}: [n]
    case Nl{ss}: fully_flatten.go(nest_nodes(), ss, Nil{})

# flatten -- `[item for sublist in l for item in sublist]`
def flatten_u32(l: List<&2, List<&2, U32>>) -> List<&2, U32>:
  List.concat(&2, U32, l)

# ===========================================================================
# F32 text
#
# `F32.show` is a law with no body -- it is an axiom -- and so is every other F32
# law, so the port needs its own F32 formatter. `f"{x:.2f}"` (time_to_str,
# size_to_str, colorize_float) has no base equivalent either. `f32_fixed` walks
# the decimal expansion of the f32 two digits at a time, which is printf's
# `%.2f` on a value that came out of an f32.
# ===========================================================================

# 0x7F800000 is the f32 exponent field; all ones means inf or nan, and the
# mantissa being non-zero distinguishes nan from inf
def f32_exp_all_ones(+x: F32) -> Bool:
  U32.is_eq(U32.and(F32.bits(x), 2139095040), 2139095040)

def f32_is_nan(+x: F32) -> Bool:
  Bool.and(f32_exp_all_ones(x), Bool.not(U32.is_zero(U32.and(F32.bits(x), 8388607))))

def f32_is_finite(+x: F32) -> Bool:
  Bool.not(f32_exp_all_ones(x))

def f32_is_neg(+x: F32) -> Bool:
  U32.is_ge(F32.bits(x), 2147483648)

# The decimal digits after the point. The state is a `Frac` record (remainder,
# digits so far) advanced by a top-level step, so the recursion is one structural
# descent on the digit count.
type Frac is Data:
  Frac{f: F32, acc: String}

def f32_frac.next(+f: F32) -> F32:
  F32.sub(F32.mul(f, 10.0), U32.to_f32(F32.to_u32(F32.mul(f, 10.0))))

def f32_frac.digit(+f: F32) -> Char:
  Char.from_u32(U32.add(48, F32.to_u32(F32.mul(f, 10.0))))

def f32_frac.step(+f: F32, acc: String) -> Frac:
  Frac{f32_frac.next(f), String.append(acc, String.from_list([f32_frac.digit(f)]))}

def f32_frac.put(fr: Frac) -> String:
  match fr:
    case Frac{f, acc}: acc

def f32_frac.go(n: Nat, fr: Frac) -> String:
  match n:
    case 0n: f32_frac.put(fr)
    case Succ{p}:
      match fr:
        case Frac{f, acc}: f32_frac.go(p, f32_frac.step(f, acc))

def f32_fixed.put(neg: Bool, s: String) -> String:
  match neg:
    case True{}: String.append("-", s)
    case False{}: s

# `f"{x:.2f}"` on a value that came out of an f32: the integer part, a point,
# and `dp` digits walked off the remainder.
def f32_fixed.text3(neg: Bool, ip: U32, dp: Nat, frac: Frac) -> String:
  f32_fixed.put(neg, String.append(String.append(U32.show(ip), "."),
    f32_frac.go(dp, frac)))

def f32_fixed.text2(neg: Bool, dp: Nat, m: F32, +ip: U32) -> String:
  f32_fixed.text3(neg, ip, dp, Frac{F32.sub(m, U32.to_f32(ip)), ""})

def f32_fixed.text1(+m: F32, dp: Nat, neg: Bool) -> String:
  f32_fixed.text2(neg, dp, m, F32.to_u32(F32.trunc(m)))

def f32_fixed.text(x: F32, dp: Nat, m: F32) -> String:
  f32_fixed.text1(m, dp, f32_is_neg(x))

def f32_fixed.body(+x: F32, dp: Nat) -> String:
  f32_fixed.text1(F32.abs(x), dp, f32_is_neg(x))

def f32_fixed.special.inf(neg: Bool) -> Maybe<&1, String>:
  match neg:
    case True{}: Some{"-inf"}
    case False{}: Some{"inf"}

def f32_fixed.special.fin(fin: Bool, neg: Bool) -> Maybe<&1, String>:
  match fin:
    case True{}: None{}
    case False{}: f32_fixed.special.inf(neg)

def f32_fixed.special(nan: Bool, fin: Bool, neg: Bool) -> Maybe<&1, String>:
  match nan:
    case True{}: Some{"nan"}
    case False{}: f32_fixed.special.fin(fin, neg)

def f32_fixed.go(special: Maybe<&1, String>, x: F32, dp: Nat) -> String:
  match special:
    case Some{s}: s
    case None{}: f32_fixed.body(x, dp)

def f32_fixed(+x: F32, dp: Nat) -> String:
  f32_fixed.go(f32_fixed.special(f32_is_nan(x), f32_is_finite(x), f32_is_neg(x)), x, dp)

def f32_is_int_valued(fin: Bool, +x: F32) -> Bool:
  match fin:
    case False{}: False{}
    case True{}: F32.is_eq(F32.floor(x), x)

# The shortest decimal that reads back, the way Python's repr does. |x| >= 2^32
# is out of range for U32.to_u32 and prints as its low word; that is the F32
# boundary and no f64 port of this formatter can do better in a U32.
def f32_show.put2(iv: Bool, x: F32, neg: Bool) -> String:
  match iv:
    case True{}: f32_fixed.put(neg, U32.show(F32.to_u32(F32.abs(x))))
    case False{}: f32_fixed.body(x, 6n)

def f32_show.put(+iv: Bool, +x: F32) -> String:
  f32_show.put2(iv, x, f32_is_neg(x))

def f32_show.special(nan: Bool, fin: Bool, neg: Bool) -> Maybe<&1, String>:
  match nan:
    case True{}: Some{"nan"}
    case False{}:
      match fin:
        case True{}: None{}
        case False{}:
          match neg:
            case True{}: Some{"-inf"}
            case False{}: Some{"inf"}

def f32_show.go2(s: Maybe<&1, String>, +x: F32) -> String:
  match s:
    case Some{t}: t
    case None{}: f32_show.put(f32_is_int_valued(f32_is_finite(x), x), x)

def f32_show.go(x: F32, s: Maybe<&1, String>) -> String:
  f32_show.go2(s, x)

def f32_show(+x: F32) -> String:
  f32_show.go(x, f32_show.special(f32_is_nan(x), f32_is_finite(x), f32_is_neg(x)))

# Python's f-string field width is a right-justified minimum width: s.rjust(w)
def pad.n.go(gt: Bool, w: U32, n: U32) -> U32:
  match gt:
    case True{}: U32.sub(w, n)
    case False{}: 0

def pad.n(+w: U32, +n: U32) -> U32:
  pad.n.go(U32.is_gt(w, n), w, n)

def pad_left.blank(s: String, w: U32) -> String:
  String.repeat(" ", U32.to_nat(pad.n(w, U32.from_nat(String.length(s)))))

def pad_left(+s: String, w: U32) -> String:
  String.append(pad_left.blank(s, w), s)

def pad_right(+s: String, w: U32) -> String:
  String.append(s, pad_left.blank(s, w))

# ===========================================================================
# colored -- `f"\u001b[{10*background+60*(color.upper()==color)+30+index}m{st}
# \u001b[0m"`, which replaces the termcolor library. The colour is a U32 index
# into ['black','red','green','yellow','blue','magenta','cyan','white']; Python
# raises ValueError on a name outside it, so `colored` takes `Maybe<&1, U32>` and
# None is Python's `color is None`, which returns the plain string. NO_COLOR is a
# ContextVar, so it arrives inside the `Flags` record.
# ===========================================================================

def color_code(ci: U32, background: Bool) -> U32:
  (U32.add(U32.add(U32.mul(Bool.to_u32(background), 10), 30), ci) : U32)

def esc(u: U32) -> String:
  String.from_list([Char.from_u32(27), Char.from_u32(91), Char.from_u32(u), Char.from_u32(109)])

def color_of(s: String) -> Maybe<&1, U32>:
  match s:
    case "black": Some{0}
    case "red": Some{1}
    case "green": Some{2}
    case "yellow": Some{3}
    case "blue": Some{4}
    case "magenta": Some{5}
    case "cyan": Some{6}
    case "white": Some{7}
    case _: None{}

def colored.put(color: Maybe<&1, U32>, st: String, background: Bool) -> String:
  match color:
    case None{}: st
    case Some{ci}: String.append(String.append(esc(color_code(ci, background)), st), "\u{1b}[0m")

def colored.flag(nc: Bool, st: String, color: Maybe<&1, U32>, background: Bool) -> String:
  match nc:
    case True{}: st
    case False{}: colored.put(color, st, background)

def colored.go(f: Flags, st: String, color: Maybe<&1, U32>, background: Bool) -> String:
  match f:
    case Flags{nc, df, di, sd}: colored.flag(nc, st, color, background)

def colored(f: Flags, st: String, color: Maybe<&1, U32>, background: Bool) -> String:
  colored.go(f, st, color, background)

# colorize_float -- f"{x:7.2f}x", green below 0.75, red above 1.15, else yellow
def colorize_float.hi(gt: Bool) -> Maybe<&1, U32>:
  match gt:
    case True{}: Some{1}
    case False{}: Some{3}

def colorize_float.pick(lt: Bool, gt: Bool) -> Maybe<&1, U32>:
  match lt:
    case True{}: Some{2}
    case False{}: colorize_float.hi(gt)

def colorize_float(f: Flags, +x: F32) -> String:
  colored(f, String.append(pad_left(f32_fixed(x, 2n), 7), "x"),
    colorize_float.pick(F32.is_lt(x, 0.75), F32.is_gt(x, 1.15)), False{})

# ===========================================================================
# time_to_str -- `next((f"{t*d:{w}.2f}{pr}" for d,pr in [(1,"s "),(1e3,"ms")]
# if t > 10/d), f"{t*1e6:{w}.2f}us")`: seconds above 10, milliseconds above
# 0.01, microseconds below. The generator is the fold a match replaces.
# ===========================================================================

def time_to_str.ms(t: F32, w: U32) -> String:
  String.append(pad_left(f32_fixed(F32.mul(t, 1000.0), 2n), w), "ms")

def time_to_str.us(t: F32, w: U32) -> String:
  String.append(pad_left(f32_fixed(F32.mul(t, 1000000.0), 2n), w), "us")

def time_to_str.pick(gt10: Bool, gt001: Bool, t: F32, w: U32) -> String:
  match gt10:
    case True{}: String.append(pad_left(f32_fixed(t, 2n), w), "s ")
    case False{}:
      match gt001:
        case True{}: time_to_str.ms(t, w)
        case False{}: time_to_str.us(t, w)

def time_to_str(+t: F32, w: U32) -> String:
  time_to_str.pick(F32.is_gt(t, 10.0), F32.is_gt(t, 0.01), t, w)

# size_to_str -- the first of GB/MB/KB that s reaches, else "<s> B". Python
# divides by a power of two with `/`, so the quotient is an f32.
def size_to_str.mb(s: U32) -> String:
  String.append(f32_fixed(F32.div(U32.to_f32(s), 1048576.0), 2n), " MB")

def size_to_str.kb(s: U32) -> String:
  String.append(f32_fixed(F32.div(U32.to_f32(s), 1024.0), 2n), " KB")

def size_to_str.pick(gb: Bool, mb: Bool, kb: Bool, s: U32) -> String:
  match gb:
    case True{}: String.append(f32_fixed(F32.div(U32.to_f32(s), 1073741824.0), 2n), " GB")
    case False{}:
      match mb:
        case True{}: size_to_str.mb(s)
        case False{}:
          match kb:
            case True{}: size_to_str.kb(s)
            case False{}: String.append(U32.show(s), " B")

def size_to_str(+s: U32) -> String:
  size_to_str.pick(U32.is_ge(s, 1073741824), U32.is_ge(s, 1048576), U32.is_ge(s, 1024), s)

# ===========================================================================
# ansistrip -- re.sub('\x1b\[(K|.*?m)', '', s). The regex is an ESC, '[', then
# either the single letter K or the SHORTEST run of characters ending in 'm',
# so the state is a mode plus the output so far and the escape body so far:
#   0n -- normal: an ESC opens an escape, anything else is output
#   1n -- just after an ESC: a '[' opens a sequence, anything else keeps the ESC
#   2n -- inside a sequence: 'K' or 'm' closes it, anything else is body
# An unterminated run does not match, so its ESC, '[' and body stay in the
# output; that is what `done` does for modes 1n and 2n.
# ===========================================================================

type Ast is Data:
  Ast{c: U32, m: Nat, acc: List<&2, Char>, pend: List<&2, Char>}

# the unterminated prefix: an ESC alone, or an ESC '[' and the run's body
def ansistrip.done4(pend: List<&2, Char>, acc: List<&2, Char>) -> List<&2, Char>:
  List.append(&2, Char, List.append(&2, Char, [Char.from_u32(27)], [Char.from_u32(91)]), List.append(&2, Char, pend, acc))

def ansistrip.done3(m: Nat, acc: List<&2, Char>, pend: List<&2, Char>) -> List<&2, Char>:
  match m:
    case 0n: acc
    case Succ{q}: List.append(&2, Char, [Char.from_u32(27)], acc)
    case Succ{Succ{p}}: ansistrip.done4(pend, acc)

def ansistrip.done2(c: U32, m: Nat, acc: List<&2, Char>, pend: List<&2, Char>) -> List<&2, Char>:
  match m:
    case 0n: List.reverse(&2, Char, acc)
    case Succ{q}: ansistrip.done3(1n, List.reverse(&2, Char, acc), List.reverse(&2, Char, pend))
    case Succ{Succ{p}}: ansistrip.done3(2n, List.reverse(&2, Char, acc), List.reverse(&2, Char, pend))

def ansistrip.done(st: Ast) -> List<&2, Char>:
  match st:
    case Ast{c, m, acc, pend}: ansistrip.done2(c, m, acc, pend)

# the ESC that did not open a sequence stays in the output
def ansistrip.go.esc(h: Char, acc: List<&2, Char>) -> List<&2, Char>:
  List.append(&2, Char, [Char.from_u32(27)], List.append(&2, Char, [h], acc))

# ONE def, ONE recursion: the char list shrinks on every call. The state carries
# the previous char's code so the transition table is a two-scrutinee match on
# two fields of the same record, in binder order.
def ansistrip.go(cs: List<&2, Char>, st: Ast) -> List<&2, Char>:
  match cs:
    case Nil{}: ansistrip.done(st)
    case +h <> t:
      match st:
        case Ast{c, m, acc, pend}:
          match c m:
            case 27 0n: ansistrip.go(t, Ast{Char.to_u32(h), 1n, acc, pend})
            case 27 Succ{q}: ansistrip.go(t, Ast{Char.to_u32(h), Succ{q}, acc, h <> pend})
            case 91 0n: ansistrip.go(t, Ast{Char.to_u32(h), 1n, acc, pend})
            case 91 Succ{q}: ansistrip.go(t, Ast{Char.to_u32(h), Succ{q}, acc, Nil{}})
            case 75 0n: ansistrip.go(t, Ast{Char.to_u32(h), 0n, acc, pend})
            case 75 Succ{q}: ansistrip.go(t, Ast{Char.to_u32(h), 0n, acc, pend})
            case 109 0n: ansistrip.go(t, Ast{Char.to_u32(h), 0n, acc, pend})
            case 109 Succ{q}: ansistrip.go(t, Ast{Char.to_u32(h), 0n, acc, pend})
            case _ 0n: ansistrip.go(t, Ast{Char.to_u32(h), 0n, h <> acc, pend})
            case _ Succ{q}: ansistrip.go(t, Ast{Char.to_u32(h), 0n,
              ansistrip.go.esc(h, acc), pend})

# the ESC that did not open a sequence stays in the output
def ansistrip(s: String) -> String:
  String.from_list(ansistrip.go(String.to_list(s), Ast{0, 0n, Nil{}, Nil{}}))

def ansilen(s: String) -> Nat:
  String.length(ansistrip(s))

def ansipad(+s: String, w: U32) -> String:
  String.append(s, String.repeat(" ", U32.to_nat(pad.n(w, U32.from_nat(ansilen(s))))))

# ===========================================================================
# make_tuple -- `(x,)*cnt` when x is an int, else `tuple(x)`. Two arms, two
# defs: the int arm repeats, the sequence arm is the identity.
# ===========================================================================

def make_tuple_rep.go(n: Nat, +x: U32) -> List<&2, U32>:
  match n:
    case 0n: Nil{}
    case Succ{p}: x <> make_tuple_rep.go(p, x)

def make_tuple_rep(x: U32, cnt: U32) -> List<&2, U32>:
  make_tuple_rep.go(U32.to_nat(cnt), x)

def make_tuple_of(x: U32) -> List<&2, U32>:
  [x]

# to_tuple -- `x if isinstance(x, tuple) else (x,)`. A List is already the
# sequence form, so the only work is wrapping a scalar.
def to_tuple_u32(x: U32) -> List<&2, U32>:
  [x]

def to_tuple_seq(xs: List<&2, U32>) -> List<&2, U32>:
  xs

# ===========================================================================
# flat_to_grouped
# `(padding_left, padding_right, padding_top, padding_bottom, ...)` ->
# `(..., (padding_top, padding_bottom), (padding_left, padding_right))`, i.e.
# `tuple(zip(padding[-2::-2], padding[::-2]))`: pair the elements up from the END,
# so [a,b,c,d] -> [(c,d),(a,b)] and [a,b,c] -> [(b,c)] and [a,b] -> [(a,b)] and
# [a] -> []. The pairs, read FORWARD, are the consecutive pairs starting at index
# (n mod 2), and the answer is that list reversed.
# ===========================================================================

def fg_pairs(p: List<&2, U32>) -> List<&2, List<&2, U32>>:
  match p:
    case h <> t:
      match t:
        case g <> r: [h, g] <> fg_pairs(r)
        case Nil{}: Nil{}
    case Nil{}: Nil{}

def fg_skip(n: Nat, xs: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: xs
    case Succ{p}:
      match xs:
        case Nil{}: Nil{}
        case _ <> t: fg_skip(p, t)

def flat_to_grouped(+padding: List<&2, U32>) -> List<&2, List<&2, U32>>:
  List.reverse(&2, List<&2, U32>, fg_pairs(fg_skip(List.length(&2, U32, padding), padding)))

# ===========================================================================
# resolve_pool_pads -- int -> [p] * 2*dims; a sequence of 2*dims -> as is; a
# sequence of dims -> `[p for p in padding for _ in range(2)][::-1]`. Python
# raises ValueError on any other length, and that is the Maybe.
# ===========================================================================

def resolve_pool_pads_int.go(n: Nat, +p: U32) -> List<&2, U32>:
  match n:
    case 0n: Nil{}
    case Succ{q}: p <> resolve_pool_pads_int.go(q, p)

def resolve_pool_pads_int(p: U32, dims: U32) -> List<&2, U32>:
  resolve_pool_pads_int.go(U32.to_nat(U32.mul(2, dims)), p)

def pool_pads_dup.go(ps: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}: List.reverse(&2, U32, acc)
    case +h <> t: pool_pads_dup.go(t, List.append(&2, U32, acc, [h, h]))

def pool_pads_dup(p: List<&2, U32>) -> List<&2, U32>:
  pool_pads_dup.go(p, Nil{})

def resolve_pool_pads.pick(isdims: Bool, p: List<&2, U32>) -> Maybe<&1, List<&2, U32>>:
  match isdims:
    case True{}: Some{pool_pads_dup(p)}
    case False{}: None{}

def resolve_pool_pads.step(istwodims: Bool, isdims: Bool, p: List<&2, U32>, dims: U32) ->
  Maybe<&1, List<&2, U32>>:
  match istwodims:
    case True{}: Some{p}
    case False{}: resolve_pool_pads.pick(isdims, p)

def resolve_pool_pads.n(two: Bool, dims: Bool, p: List<&2, U32>, dims2: U32) ->
  Maybe<&1, List<&2, U32>>:
  resolve_pool_pads.step(two, dims, p, dims2)

def resolve_pool_pads(+p: List<&2, U32>, +dims: U32) -> Maybe<&1, List<&2, U32>>:
  resolve_pool_pads.n(U32.is_eq(U32.from_nat(List.length(&2, U32, p)), U32.mul(2, dims)),
    U32.is_eq(U32.from_nat(List.length(&2, U32, p)), dims), p, dims)

# ===========================================================================
# _is_balanced / strip_parens
# `_is_balanced(s)` is "no prefix closes more than it opens, and the depths end
# at zero". The depth is a U32, so underflow is the wrap past 2^31. `s[1:-1]` and
# `fst[:1]` / `fst[-1:]` are String.drop and String.take.
# ===========================================================================

def bal.next.step(c: U32, d: U32) -> U32:
  match c:
    case 40: U32.add(d, 1)
    case 41: U32.sub(d, 1)
    case _: d

def bal.next(h: Char, d: U32) -> U32:
  bal.next.step(Char.to_u32(h), d)

def bal.under(nd: U32) -> Bool:
  U32.is_ge(nd, 2147483648)

# the walk carries its depth as a record rather than as two parameters: the depth
# has to be matched (for the end test) while the char list is matched for the walk
type Depth is Data:
  Depth{d: U32, under: Bool}

def bal.depth(st: Depth) -> U32:
  match st:
    case Depth{d, under}: d

def bal.spilled(st: Depth) -> Bool:
  match st:
    case Depth{d, under}: under

def bal.step(spilled: Bool, +nd: U32) -> Depth:
  match spilled:
    case True{}: Depth{nd, True{}}
    case False{}: Depth{nd, bal.under(nd)}

def bal.end(st: Depth) -> Bool:
  match st:
    case Depth{d, under}:
      match under:
        case True{}: False{}
        case False{}: U32.is_zero(d)

def bal.walk(cs: List<&2, Char>, +st: Depth) -> Bool:
  match cs:
    case Nil{}: bal.end(st)
    case +h <> t: bal.walk(t, bal.step(bal.spilled(st), bal.next(h, bal.depth(st))))

def is_balanced(s: String) -> Bool:
  bal.walk(String.to_list(s), Depth{0, False{}})

def strip_parens.inner(+fst: String) -> String:
  String.take(String.drop(fst, 1n), Nat.sub(String.length(fst), 2n))

def is_wrapped.both(starts: Bool, ends: Bool, +fst: String) -> Bool:
  match starts:
    case True{}:
      match ends:
        case True{}: is_balanced(strip_parens.inner(fst))
        case False{}: False{}
    case False{}: False{}

def is_wrapped(+fst: String) -> Bool:
  is_wrapped.both(String.starts_with(fst, "("), String.ends_with(fst, ")"), fst)

def strip_parens.go(wrapped: Bool, +fst: String) -> String:
  match wrapped:
    case True{}: strip_parens.inner(fst)
    case False{}: fst

def strip_parens(+fst: String) -> String:
  strip_parens.go(is_wrapped(fst), fst)

# ===========================================================================
# Signed 32-bit arithmetic on a U32 bit pattern
#
# Bend has no signed integers, so a signed value is its two's complement bit
# pattern and every comparison is a sign test.
# ===========================================================================

def i32_is_neg(x: U32) -> Bool:
  U32.is_ge(x, 2147483648)

def i32_neg(x: U32) -> U32:
  U32.sub(0, x)

# asr -- Bend's two shifts are both LOGICAL, so a negative value needs its top
# `m` bits put back after the shift. The fill is the whole WORD 0xFFFFFFFF and
# NOT the sign bit: shifting the sign bit right answers 1 rather than a run of
# ones. The count is clamped to 31, and that is not a workaround but the WHOLE
# answer past 31: floor(v/2^n) is -1 when v < 0 and 0 when v >= 0 once n reaches
# 32, and the clamped form is exactly that number.
def asr(+v: U32, n: Nat) -> U32:
  +m = Nat.min(n, 31n)
  U32.or(U32.shrn(v, m), U32.shln(i32_neg(U32.shrn(v, 31n)), Nat.sub(32n, m)))

def i32_abs(neg: Bool, x: U32) -> U32:
  match neg:
    case True{}: i32_neg(x)
    case False{}: x

# cdiv and floordiv both need "the two signs differ". Python gets it from `x*y<0`;
# multiplying first would overflow in 32 bits and could flip the answer, so the XOR
# of the two sign bits is used.
def cdiv_sign(x: U32, y: U32) -> Bool:
  Bool.xor(i32_is_neg(x), i32_is_neg(y))

# python floor div and mod: `x//y if y != 0 else 0`
def floordiv_i32.exact(ax: U32, ay: U32) -> Bool:
  U32.is_zero(U32.mod(ax, ay))

def floordiv_i32.trunc.put(neg: Bool, q: U32) -> U32:
  match neg:
    case True{}: i32_neg(q)
    case False{}: q

# floordiv -- `x//y if y != 0 else 0`: truncate toward zero, and step DOWN one
# more only when the division was inexact AND the two signs DIFFER. For a
# same-sign division the truncation already IS the floor, so the step belongs to
# the opposite-sign case alone.
def floordiv_i32.trunc.exact(exact: Bool, neg: Bool, q: U32) -> U32:
  match exact:
    case True{}: floordiv_i32.trunc.put(neg, q)
    case False{}:
      match neg:
        case True{}: floordiv_i32.trunc.put(neg, U32.add(q, 1))
        case False{}: q

def floordiv_i32.trunc(neg: Bool, exact: Bool, q: U32) -> U32:
  floordiv_i32.trunc.exact(exact, neg, q)

def floordiv_i32.pick(zero: Bool, neg: Bool, exact: Bool, ax: U32, ay: U32) -> U32:
  match zero:
    case True{}: 0
    case False{}: floordiv_i32.trunc(neg, exact, U32.div(ax, ay))

def floordiv_i32(+x: U32, +y: U32) -> U32:
  floordiv_i32.pick(U32.is_zero(y), cdiv_sign(x, y),
    floordiv_i32.exact(i32_abs(i32_is_neg(x), x), i32_abs(i32_is_neg(y), y)),
    i32_abs(i32_is_neg(x), x), i32_abs(i32_is_neg(y), y))

# ===========================================================================
# WHICH OF THE TWO PAIRS IS WHICH. `cdiv_i32_go`/`cmod_i32` TRUNCATE toward zero
# (helpers.py:73-74, C semantics, `-7 // 4` is `-1`) and
# `floordiv_i32`/`floormod_i32` FLOOR (helpers.py:76-77, Python's `//` and `%`,
# `-7 // 4` is `-2`). Both are correct, both are exported, and they are NOT
# duplicates: `ceildiv` is `-(num // -amt)` and `round_up` is
# `(num+amt-1)//amt*amt`, and BOTH are floors, so neither can be spelled with a
# truncating division. Picking the wrong pair is a wrong answer, not a slower
# right one.
# ===========================================================================

# cstyle div and mod: `abs(x)//abs(y)*(1,-1)[x*y<0] if y != 0 else 0`
def cdiv_i32.put(neg: Bool, q: U32) -> U32:
  match neg:
    case True{}: i32_neg(q)
    case False{}: q

def cdiv_i32(zero: Bool, neg: Bool, q: U32) -> U32:
  match zero:
    case True{}: 0
    case False{}: cdiv_i32.put(neg, q)

def cdiv_i32_go(+x: U32, +y: U32) -> U32:
  cdiv_i32(U32.is_zero(y), cdiv_sign(x, y),
    U32.div(i32_abs(i32_is_neg(x), x), i32_abs(i32_is_neg(y), y)))

def cmod_i32(+x: U32, +y: U32) -> U32:
  U32.sub(x, U32.mul(cdiv_i32_go(x, y), y))

def floormod_i32(+x: U32, +y: U32) -> U32:
  U32.sub(x, U32.mul(floordiv_i32(x, y), y))

# The unsigned readings of the same four. Python's // and % on a non-negative
# int are U32.div and U32.mod, and U32.div(a, 0) = 0 / U32.mod(a, 0) = a is
# exactly tinygrad's zero-divisor branch.
def floordiv_u32(x: U32, y: U32) -> U32:
  U32.div(x, y)

def floormod_u32(+x: U32, +y: U32) -> U32:
  U32.sub(x, U32.mul(U32.div(x, y), y))

def cdiv_u32(x: U32, y: U32) -> U32:
  U32.div(x, y)

def cmod_u32(+x: U32, +y: U32) -> U32:
  U32.sub(x, U32.mul(cdiv_u32(x, y), y))

# ===========================================================================
# ceildiv / round_up / round_down / next_power2
#
# ceildiv -- `if hasattr(num,'vmin') and num.vmin >= 0 and amt > 0: (num+amt-1)//
# amt`, else `-(num // -amt)`. The first arm is there to avoid C/Python division
# mismatch, and it duck-types on a UOp; there is no UOp in this phase, and the
# two arms agree on ints, so the integer port is the second one, which is total
# over negatives as well. It spells `-(num // -amt)`: the DIVISOR is negated, the
# dividend is not. SYMBOLIC CASE, LATER PHASE (P3, uop/symbolic.bend): it needs
# `vmin`, the bound a Variable carries in the arena, and comes back as
# `ceildiv_uop(num: UOp, amt: UOp)`.
# ===========================================================================

def ceildiv_i32(num: U32, amt: U32) -> U32:
  i32_neg(floordiv_i32(num, i32_neg(amt)))

# div0 -- Python raises ZeroDivisionError for x//0; tinygrad guards floordiv and
# cdiv with `if y != 0 else 0` but NOT ceildiv or round_up, which raise. Bend is
# total, so the guarded reading (0) is the one every zero-divisor def here answers.
def div0(zero: Bool, v: U32) -> U32:
  match zero:
    case True{}: 0
    case False{}: v

def ceildiv_u32(num: U32, +amt: U32) -> U32:
  div0(U32.is_zero(amt), U32.div(U32.add(U32.add(num, amt), 4294967295), amt))

def round_up_i32(num: U32, +amt: U32) -> U32:
  U32.mul(floordiv_i32(U32.add(U32.add(num, amt), 4294967295), amt), amt)

def round_down_i32(num: U32, amt: U32) -> U32:
  i32_neg(round_up_i32(i32_neg(num), amt))

def round_up_u32(num: U32, +amt: U32) -> U32:
  U32.mul(ceildiv_u32(num, amt), amt)

def round_down_u32(num: U32, amt: U32) -> U32:
  i32_neg(round_up_u32(i32_neg(num), amt))

# `1 if x == 0 else 1 << (x-1).bit_length()`: the smallest power of two that is
# >= x, with 0 answering 1. The fold needs a fuel because p grows rather than
# shrinks; 33 steps cover every x a U32 holds. x > 2^31 has no representable
# answer (Python answers 2^32) and is documented as such.
def next_power2.go(k: Nat, lt: Bool, +x: U32, +p: U32) -> U32:
  match k:
    case 0n: p
    case Succ{q}:
      match lt:
        case True{}: next_power2.go(q, U32.is_lt(U32.add(p, p), x), x, U32.add(p, p))
        case False{}: p

def next_power2(+x: U32) -> U32:
  next_power2.go(33n, U32.is_lt(1, x), x, 1)

# ===========================================================================
# 64-bit words
#
# helpers.py's lo32 / hi32 / data64 / data64_le all say "Any is sint", so the
# value they take is a signed 64-bit int. Bend has no 64-bit word, so it is the
# pair of halves in two's complement. Build one with i64_of_i32 (sign-extends)
# or i64_of_hi_lo.
# ===========================================================================

type I64 is Data:
  I64{hi: U32, lo: U32}

def match_hi(neg: Bool) -> U32:
  match neg:
    case True{}: 4294967295
    case False{}: 0

def i64_of_i32(+x: U32) -> I64:
  I64{match_hi(i32_is_neg(x)), x}

def i64_of_hi_lo(hi: U32, lo: U32) -> I64:
  I64{hi, lo}

def lo32(x: I64) -> U32:
  match x:
    case I64{hi, lo}: lo

def hi32(x: I64) -> U32:
  match x:
    case I64{hi, lo}: hi

# A signed comparison of two's complement pairs. Two's complement compares
# correctly as UNSIGNED words whenever the signs agree, so the only case that
# needs the sign is when they differ -- and then it is decided outright. `U32.cmp`
# answers a Cmp and Cmp is a datatype, so the head comparison arrives as the two
# Bools it decides and the low word only matters when the high words are equal.
def i64_cmp.lt(lt: Bool) -> Cmp:
  match lt:
    case True{}: LT{}
    case False{}: GT{}

def i64_cmp.mag(eq: Bool, lt: Bool, eql: Bool, ltl: Bool) -> Cmp:
  match eq:
    case True{}:
      match eql:
        case True{}: EQ{}
        case False{}: i64_cmp.lt(ltl)
    case False{}: i64_cmp.lt(lt)

def i64_cmp.sgn(an: Bool, +ah: U32, +al: U32, bn: Bool, +bh: U32, +bl: U32) -> Cmp:
  match an bn:
    case True{} False{}: LT{}
    case False{} True{}: GT{}
    case True{} True{}: i64_cmp.mag(U32.is_eq(ah, bh), U32.is_lt(ah, bh),
      U32.is_eq(al, bl), U32.is_lt(al, bl))
    case False{} False{}: i64_cmp.mag(U32.is_eq(ah, bh), U32.is_lt(ah, bh),
      U32.is_eq(al, bl), U32.is_lt(al, bl))

def i64_cmp(+a: I64, +b: I64) -> Cmp:
  i64_cmp.sgn(i32_is_neg(hi32(a)), hi32(a), lo32(a),
    i32_is_neg(hi32(b)), hi32(b), lo32(b))

def i64_is_neg(x: I64) -> Bool:
  i32_is_neg(hi32(x))

def i64_le(a: I64, b: I64) -> Bool:
  Cmp.is_le(i64_cmp(a, b))

# An I64 prints as its two words, so a value never has to leave U32 to be read.
# `hi:lo` rather than a decimal because 2^63 has no U32 image, and a dump the
# oracle can diff line for line is worth more here than a prettier one.
def i64_show(hi: U32, lo: U32) -> String:
  String.concat([U32.show(hi), ":", U32.show(lo)])

def i64_text(+x: I64) -> String:
  i64_show(hi32(x), lo32(x))

# 64-bit add and subtract, so a boundary generator can step either side of a
# limit without an effect. Carrying into the high word is all either has to get
# right, and U32's wrap does that for free.
def i64_add(+a: I64, +b: I64) -> I64:
  i64_of_hi_lo(U32.add(hi32(a), hi32(b)), U32.add(lo32(a), lo32(b)))

def i64_sub(+a: I64, +b: I64) -> I64:
  i64_of_hi_lo(U32.sub(hi32(a), hi32(b)), U32.sub(lo32(a), lo32(b)))

# data64 -- `(data >> 32, data & 0xFFFFFFFF)`; data64_le swaps it. Python's >> is
# arithmetic and the high half of a two's complement 64-bit word IS the
# arithmetic shift, so the pair already comes out in that order.
def data64_hi(r: U32 & U32) -> U32:
  (hi, lo) = r
  hi

def data64_lo(r: U32 & U32) -> U32:
  (hi, lo) = r
  lo

def data64(x: I64) -> U32 & U32:
  match x:
    case I64{hi, lo}: (hi, lo)

def data64_le(x: I64) -> U32 & U32:
  match x:
    case I64{hi, lo}: (lo, hi)

def to_be32(+val: U32) -> U32:
  U32.or(U32.or(U32.shln(U32.and(val, 255), 24n), U32.shln(U32.and(U32.shrn(val, 8n), 255), 16n)),
    U32.or(U32.shln(U32.and(U32.shrn(val, 16n), 255), 8n), U32.and(U32.shrn(val, 24n), 255)))

# to_be64 -- `to_be32(val >> 32) | (to_be32(val & 0xFFFFFFFF) << 32)`, so the
# high word is the byte swap of the LOW word and the low word of the HIGH one.
def to_be64(val: I64) -> I64:
  match val:
    case I64{hi, lo}: I64{to_be32(lo), to_be32(hi)}

# getbits -- `(value >> start) & ((1 << (end - start + 1)) - 1)`. U32.shln
# saturates to 0 past 31, so a 32-wide mask is 0 - 1 = 0xFFFFFFFF, which is the
# right answer; a width over 32 saturates too and is documented.
def bit_mask(w: Nat) -> U32:
  U32.sub(U32.shln(1, w), 1)

def getbits(value: U32, +start: Nat, end: Nat) -> U32:
  U32.and(U32.shrn(value, start), bit_mask(Nat.add(Nat.sub(end, start), 1n)))

# i2u -- `value if value >= 0 else (1 << bits) + value`
def i2u(neg: Bool, bits: Nat, value: U32) -> U32:
  match neg:
    case True{}: U32.add(U32.shln(1, bits), value)
    case False{}: value

# ===========================================================================
# merge_dicts
#
# `{k:v for d in ds for k,v in d.items()}` after checking that no key carries two
# values. Bend's `Map` is string-keyed with an awkward `Map.get`, so a list of
# pairs is the honest representation: it is what `d.items()` yields, it keeps
# insertion order, and the conflict scan is a fold. `None` is Python's RuntimeError
# "contains different values for the same key".
# ===========================================================================

type KV is Data:
  KV{k: String, v: U32}

def kv_key(kv: KV) -> String:
  match kv:
    case KV{k, v}: k

def kv_val(kv: KV) -> U32:
  match kv:
    case KV{k, v}: v

def kv_find.hit(same: Bool, kv: KV) -> Maybe<&1, U32>:
  match same:
    case True{}: Some{kv_val(kv)}
    case False{}: None{}

def kv_find.pick(found: Maybe<&1, U32>, same: Bool, kv: KV) -> Maybe<&1, U32>:
  match found:
    case Some{v}: Some{v}
    case None{}: kv_find.hit(same, kv)

# the scan folds rather than returning early, because first match wins and `pick`
# keeps whatever `found` already holds
def kv_find.go(l: List<&2, KV>, +k: String, found: Maybe<&1, U32>) -> Maybe<&1, U32>:
  match l:
    case Nil{}: found
    case +kv <> t: kv_find.go(t, k, kv_find.pick(found, String.eq(kv_key(kv), k), kv))

def kv_find(l: List<&2, KV>, k: String) -> Maybe<&1, U32>:
  kv_find.go(l, k, None{})

def kv_conflict.pick(found: Maybe<&1, U32>, kv: KV) -> Bool:
  match found:
    case None{}: False{}
    case Some{v}: U32.is_ne(v, kv_val(kv))

# a repeat of the SAME value is not a conflict; Python dedups the pair set first
def kv_conflict(seen: List<&2, KV>, +kv: KV) -> Bool:
  kv_conflict.pick(kv_find(seen, kv_key(kv)), kv)

# The flag rides in the accumulator, not beside the list, so the walk is one call
type Merged is Data:
  Merged{bad: Bool, seen: List<&2, KV>}

def merged_seen(m: Merged) -> List<&2, KV>:
  match m:
    case Merged{bad, seen}: seen

def merged_bad(m: Merged) -> Bool:
  match m:
    case Merged{bad, seen}: bad

def merged_of(bad: Bool, seen: List<&2, KV>) -> Merged:
  Merged{bad, seen}

def merge_dicts.add(conflict: Bool, kv: KV, +m: Merged) -> Merged:
  match conflict:
    case True{}: merged_of(True{}, merged_seen(m))
    case False{}: merged_of(merged_bad(m), List.append(&2, KV, merged_seen(m), [kv]))

def merge_dicts.go(l: List<&2, KV>, +m: Merged) -> Merged:
  match l:
    case Nil{}: m
    case +kv <> t:
      merge_dicts.go(t, merge_dicts.add(kv_conflict(merged_seen(m), kv), kv, m))

# None is Python's RuntimeError: a key carried two different values
def merge_dicts.pick(m: Merged) -> Maybe<&1, List<&2, KV>>:
  match m:
    case Merged{bad, seen}:
      match bad:
        case True{}: None{}
        case False{}: Some{seen}

def merge_dicts(ds: List<&2, List<&2, KV>>) -> Maybe<&1, List<&2, KV>>:
  match ds:
    case Nil{}: Some{Nil{}}
    case d0 <> r: merge_dicts.pick(merge_dicts.go(List.concat(&2, KV, r), merged_of(False{}, d0)))

# ===========================================================================
# partition -- `for s in itr: (ret[0] if fxn(s) else ret[1]).append(s)`.
# `fxn` is a Python callback and a Bend closure cannot be stored, so the predicate
# is a `Sel` tag and each tag is a top-level def. part_test's tags:
# 0 = x > 0, 1 = x < 0, 2 = x == 0, 3 = x is even, anything else = keep all.
# The accumulator is a record so the recursion never needs a `+` on a list;
# `partition` still answers Python's (kept, dropped) pair.
# ===========================================================================

type Parted is Data:
  Parted{yes: List<&2, U32>, no: List<&2, U32>}

# binder order: p is field 1, keep is field 2
def part_put(p: Parted, keep: Bool, h: U32) -> Parted:
  match p:
    case Parted{yes, no}:
      match keep:
        case True{}: Parted{h <> yes, no}
        case False{}: Parted{yes, h <> no}

def part_test(sel: U32, x: U32) -> Bool:
  match sel:
    case 0: U32.is_gt(x, 0)
    case 1: U32.is_lt(x, 0)
    case 2: U32.is_zero(x)
    case 3: U32.is_even(x)
    case _: True{}

def part_go(xs: List<&2, U32>, +sel: U32, p: Parted) -> Parted:
  match xs:
    case Nil{}: p
    case +h <> t: part_go(t, sel, part_put(p, part_test(sel, h), h))

def part_out(p: Parted) -> List<&2, U32> & List<&2, U32>:
  match p:
    case Parted{yes, no}: (yes, no)

def part_yes(r: List<&2, U32> & List<&2, U32>) -> List<&2, U32>:
  (a, b) = r
  a

def part_no(r: List<&2, U32> & List<&2, U32>) -> List<&2, U32>:
  (a, b) = r
  b

def partition(sel: U32, itr: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  part_out(part_go(itr, sel, Parted{Nil{}, Nil{}}))

# ===========================================================================
# unwrap / get_single_element
#
# Both Python functions are `assert`s, and an assertion is not a value, so a
# total def cannot say "the caller promised". The faithful total form therefore
# takes the fallback the caller would have died for. `get_single(xs)` answers
# None when the length is not 1, the only case Python's assert rejects.
# ===========================================================================

def unwrap_or(m: Maybe<&1, U32>, d: U32) -> U32:
  match m:
    case Some{v}: v
    case None{}: d

def get_single(xs: List<&2, U32>) -> Maybe<&1, U32>:
  match xs:
    case Nil{}: None{}
    case h <> t:
      match t:
        case Nil{}: Some{h}
        case _: None{}

# ===========================================================================
# Timing
#
# `class Timing(contextlib.ContextDecorator)`: __enter__ stamps
# time.perf_counter_ns(), __exit__ prints f"{prefix}{et*1e-6:6.2f} ms". A `with`
# is not a term, so the shape becomes a stamp and a report and the caller keeps
# the two calls adjacent.
# ===========================================================================

def Timing.now() -> IO(Nat):
  IO.now()

def Timing.report.text(prefix: String, st: Nat, en: Nat) -> String:
  String.append(String.append(prefix,
    pad_left(f32_fixed(F32.div(U32.to_f32(U32.from_nat(Nat.sub(en, st))), 1000000.0), 2n), 6)), " ms")

def Timing.report.go(enabled: Bool, s: String) -> IO(Unit):
  match enabled:
    case True{}: IO.print(s)
    case False{}: IO.pure(Unit, Unit{})

def Timing.report(enabled: Bool, prefix: String, st: Nat, en: Nat) -> IO(Unit):
  Timing.report.go(enabled, Timing.report.text(prefix, st, en))

# ===========================================================================
# lines / printable
#
# `lines(fn)` opens a file and readlines()s it, answering [] on FileNotFound or
# OSError; Bend's File.read answers a Result and [] is the Fail arm.
# `printable(loc)` is lines(loc[0])[loc[1]-1].strip() with IndexError ->
# "<missing>".
# ===========================================================================

def lines.done(f: File, value: String) -> IO(List<&2, String>):
  IO.bind(Unit, List<&2, String>, File.close(f),
    u => IO.pure(List<&2, String>, String.lines(value)))

def lines.close(f: File) -> IO(List<&2, String>):
  IO.bind(Unit, List<&2, String>, File.close(f), u => IO.pure(List<&2, String>, Nil{}))

def lines.split(r: File & Result<&1, &1, U32 & String, String>) -> IO(List<&2, String>):
  match r:
    case (f, Done{value}): lines.done(f, value)
    case (f, Fail{error}): lines.close(f)

def lines.read(f: File, max: U32) -> IO(List<&2, String>):
  IO.bind(File & Result<&1, &1, U32 & String, String>, List<&2, String>,
    File.read(f, max), r => lines.split(r))

def lines.go(r: Result<&1, &1, U32 & String, File>) -> IO(List<&2, String>):
  match r:
    case Done{value}: lines.read(value, 33554432)
    case Fail{error}: IO.pure(List<&2, String>, Nil{})

def lines(path: String) -> IO(List<&2, String>):
  IO.bind(Result<&1, &1, U32 & String, File>, List<&2, String>,
    File.open(path, "r"), r => lines.go(r))

def printable.go(got: Maybe<&2, String>) -> String:
  match got:
    case Some{s}: String.trim(s)
    case None{}: "<missing>"

def printable.pick(line: U32, ls: IO(List<&2, String>)) -> IO(String):
  do IO<String>:
    got : List<&2, String> <- ls
    return printable.go(List.get(&2, String, got, Nat.sub(U32.to_nat(line), 1n)))

def printable(path: String, line: U32) -> IO(String):
  printable.pick(line, lines(path))

# ===========================================================================
# NOT PORTED -- tinygrad/helpers.py, and why
#
# The 64-bit signed div/mod (ceildiv64, cdiv64, cmod64, floordiv64, floormod64)
# and the 64-bit integer truncation are C effects, not pure defs: a signed
# 64-bit quotient and a 2^64-1 bound have no U32 encoding. They are declared in
# ./dtype.bend next to the runtime/dtype.c that implements them.
#
# The ContextVar variable list is 3 of ~40. The rest (DEBUG, BEAM, NOOPT, DEV,
# CACHELEVEL, ...) is phase P6: they need a process-wide store with save and
# restore, which is exactly the mutable global Bend does not have.
#
# `Target` and `Target.parse` are phase P6 too: they exist to parse DEV, and DEV
# only exists once there is a device to point at.
# `classproperty` is a descriptor: it makes an attribute read as a function.
# Bend has no descriptors, no class of methods and no `getattr`, and every
# ported def here is a top-level function, so there is nothing for it to
# attach to.
# `fromimport(mod, frm)` is a dynamic import. The set of modules is not known
# until the whole port exists, and Bend's imports are leading lines resolved
# before any def runs, so this becomes a compile-time import in the file that
# needs the name.
# `canonicalize_strides` and `strides_for_shape` are `functools.cache`d over
# tuples and belong to shape.bend, which owns the layout IR.
# `getenv` is ported here as `getenv_str` because Flags and the dtype defaults
# need it; it keeps Python's `type(default)(os.getenv(key, default))` shape only
# for the string defaults these two files use.
# `get_child`, `word_wrap`, `pad_bytes`, `pluralize`, `polyN`,
# `to_function_name`, `select_by_name`, `select_first_inited`,
# `suppress_finalizing`, `panic`, `stderr_log` and `temp` are string, regex and
# reflection helpers for the interpreter-facing surfaces (viz, the object
# dumper, the error printer). They are ported with the module that uses them.
# `is_numpy_ndarray` is a type-identity test against numpy, and numpy is a C
# effect; it is a predicate on the interop layer, not on a Bend value.
# The sqlite disk cache (cache_dir, CACHEDB, db_connection, diskcache_clear,
# diskcache_get, diskcache_put, diskcache, _db_tables, _db_connection, VERSION)
# is a persistent object store with pickle values. Bend has no pickle and no
# object graph to store, so the cache becomes the C-effect arena of P6 and this
# is replaced rather than ported.
# The HTTP machinery (fetch, fetch_fw, _ensure_downloads_dir) is urllib plus a
# temp file plus an atomic rename. It is I/O of exactly the kind the master
# plan puts in runtime/, and its only callers are the weight downloaders.
# The ctypes helpers (from_mv, to_mv, mv_address, to_char_p_p, flat_mv) wrap a
# Python address into a memoryview. Bend's `Array<T>` is already a reference-
# counted buffer, so the arena in P6 owns the memory and these become the
# arena's accessors rather than a port of the casts.
# `tqdm` and `trange` are a terminal progress bar: ANSI redraw, a width from
# shutil.get_terminal_size and a rate heuristic. It is pure presentation over a
# loop the caller already owns; the port prints a line per kernel instead
# (viz.bend, P8).
# `copyreg.pickle(types.CodeType/ModuleType)`, `_serialize_code`,
# `_reconstruct_code` and `_serialize_module` make Python objects picklable.
# Bend has no code objects and no modules to pickle.
# The cProfile-backed `Profiling`, `perf_counter_us`, `TracingKey`,
# `ProfileEvent`, `ProfileRangeEvent`, `ProfilePointEvent`, `cpu_events`,
# `cpu_profile`, `profile_marker` and `_format_fcn` are the Python profiler.
# The events are real behaviour (viz.bend asserts on them) but the data source
# is CPython's own frame stack, which does not exist in Bend; they are rebuilt
# in P8 on the IO.now clock, which is why `Timing` above is ported and
# `Profiling` is not.
# `GlobalCounters` is a mutable class with ClassVar state. It becomes the
# engine's counter record in P4, threaded like the arena, not a global.
# `disable_gc` and the DEBUG_GC `gc.callbacks` hook control CPython's collector.
# Bend's collector is the reference count in the runtime, which no def can
# switch off, so these have no meaning here.
# `count` and `Metadata` are tiny value helpers with no caller in the two files
# this phase ports: `Metadata` rides on UOp (P3) and `count` is Python's own
# itertools.count spelled out.
