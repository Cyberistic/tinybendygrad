# spec.bend -- tinygrad's spec/tinyspec.tex, as a pure Bend datatype.
#
# This is the *specification* IR, not the compilation IR, and it is the one
# place where we are allowed to write something new rather than mirror a file.
# tinyspec.tex states the derived properties (dtype, shape, device, addrspace,
# min_max) per op; turning those into total functions over an inductive tree is
# what lets the checker decide the spec's claims instead of trusting a comment.
#
# The compilation IR (tinygrad/uop/ops.py) is a cyclic hash-consed graph in an
# arena, because the range graph has back-edges and the test suite depends on
# node identity. That IR cannot be a pure tree, so the laws cannot reach it; see
# `.agents/slop/notes/bend2-constraints.md` section 6 (line 454). The
# `PORTING.md` cited here before DOES NOT EXIST in this repo.
#
# TERMINATION IS STRUCTURAL: one def per property, no mutual recursion, and
# every descent passes a FIELD of its own parameter. No @unsafe, and no fuel
# budget either -- so a law over these folds is a real claim about a total
# function, not a comparison of two budget-limited `None`s.
#
# Four measured facts about bend 2.0.34 decide the shape of what follows:
#
#   1. A def may call only defs declared ABOVE it, and mutual recursion is
#      refused outright. So each property is ONE def over `Sp`, and a helper
#      that would have to self-call it -- the broadcast of two operands -- cannot
#      be factored out. Every ALU arm therefore binds its two operand shapes to
#      locals and calls `dims_zip_max` itself. That is why the broadcast arms
#      below are three lines each; it is the checker, not sloppiness.
#   2. A recursive call must be a tail expression, or bound to a local on its
#      own line. Hence `x = Sp.shape(a)` then `y = Sp.shape(b)`.
#   3. A recursive call must pass a field of its own parameter, bare or
#      re-wrapped in the same constructor. A list HEAD binder counts; a list
#      TAIL does not, in any constructor.
#   4. So a fold that MAPPS a recursive function over a `List` and COMBINES the
#      results cannot be written at all: the head and the tail come out of one
#      destructured list, the tail is unusable by (3), and giving the tail a
#      field of its own needs a second mutually recursive def, refused by (1).
#      The two ops that would have needed that fold do not have one. `Stack`'s
#      shape needs only its HEAD plus the operand count, so it keeps its list.
#      `Index`'s shape needs EVERY index shape, so its index list cannot stay and
#      `Index` is bounded-arity instead -- see `SpIdx1` below.
#
# ORDER IS LOAD-BEARING otherwise: a def may call only defs declared ABOVE it,
# and every datatype in this file may name another in any order.
#
# Naming: Bend shares one constructor namespace across all modules, so every
# constructor here is prefixed and never collides with another file's.

import Base

# ===========================================================================
# DType -- tinygrad/dtype.py
#
# tinygrad's DType is (priority, bitsize, name, fmt). Here it is
# (priority, bits, cls, name): `fmt` is derivable from cls and lives in a table
# in dtype.bend, and the class is an explicit tag because Bend's only integer
# is U32 so signedness cannot be read off a width.
#
# ONE DATATYPE, NOT TWO. dtype.py's port reuses this `Dt`; it does not declare a
# competing dtype of its own. The tag is `Cls` rather than a signed/float pair of
# Bools because dtype.py has seven classes, not two: `void` is neither and
# `bool` is neither an integer nor a float, and with two Bools both would have
# to be spelled wrong. tinygrad asks the same three questions
# (is_int/is_float/is_unsigned) and each has a different answer per class, so the
# tag names the seven answers instead of the two that fit U32.
# ===========================================================================

type Cls is Data:
  CVoid{}
  CWeakInt{}
  CBool{}
  CUint{}
  CSint{}
  CFloat{}
  CWeakFloat{}

type Dt is Data:
  Dt{pri: U32, bits: U32, cls: Cls, nm: String}

type Addr is Data:      # tinygrad/dtype.py: AddrSpace.IntEnum
  AGlobal{}
  ALocal{}
  AReg{}
  Aalu{}

type Dev is Data:       # a device name, or a tuple of them for a multi-device tensor
  D1{tag: U32}
  Dn{tags: List<&2, U32>}

# The integer limits of a width: one def per limit, each taking the width as a
# Nat PARAMETER. A `match` may not scrutinise a computed value and `U32.to_nat`
# is a call, so `match U32.to_nat(bits):` is refused and the conversion happens
# at the call site instead.
def dt_smax(w: Nat) -> U32:
  match w:
    case 8n: 127
    case 16n: 32767
    case _: 2147483647

# the magnitude of the two's complement minimum, 2^(bits-1)
def dt_smag(w: Nat) -> U32:
  match w:
    case 8n: 128
    case 16n: 32768
    case _: 2147483648

def dt_umax(w: Nat) -> U32:
  match w:
    case 8n: 255
    case 16n: 65535
    case _: 4294967295

def dt_min_signed(bits: U32) -> U32:
  # Bend's U32 has no sign, so min_max carries the magnitude of the minimum.
  dt_smag(U32.to_nat(bits))

def dt_max_signed(bits: U32) -> U32:
  dt_smax(U32.to_nat(bits))

def dt_umax_of(bits: U32) -> U32:
  # 2^bits - 1: all ones. Past 32 bits the value does not fit a U32, and the
  # arena carries the width in `bits` with two words.
  dt_umax(U32.to_nat(bits))

# A `match` inspects a parameter, never a projection, so every helper that
# branches on a field destructures its parameter first. That is the whole
# idiom for "if on a struct field" in Bend.
def Cls.is_int(c: Cls) -> Bool:
  match c:
    case CWeakInt{}: True{}
    case CUint{}: True{}
    case CSint{}: True{}
    case _: False{}

def Cls.is_float(c: Cls) -> Bool:
  match c:
    case CFloat{}: True{}
    case CWeakFloat{}: True{}
    case _: False{}

# tinygrad: is_unsigned is `x in dtypes.uints`, which is the four CUint widths.
# bool and void are NOT unsigned despite holding no sign bit.
def Cls.is_unsigned(c: Cls) -> Bool:
  match c:
    case CUint{}: True{}
    case _: False{}

def Cls.is_bool(c: Cls) -> Bool:
  match c:
    case CBool{}: True{}
    case _: False{}

def Dt.cls(d: Dt) -> Cls:
  match d:
    case Dt{pri, bits, cls, nm}: cls

def Dt.bits(d: Dt) -> U32:
  match d:
    case Dt{pri, bits, cls, nm}: bits

def Dt.pri(d: Dt) -> U32:
  match d:
    case Dt{pri, bits, cls, nm}: pri

def Dt.is_int(d: Dt) -> Bool:
  Cls.is_int(Dt.cls(d))

def Dt.is_float(d: Dt) -> Bool:
  Cls.is_float(Dt.cls(d))

def Dt.is_unsigned(d: Dt) -> Bool:
  Cls.is_unsigned(Dt.cls(d))

def Dt.is_bool(d: Dt) -> Bool:
  Cls.is_bool(Dt.cls(d))

def Dt.itemsize(d: Dt) -> U32:
  # tinygrad: (bitsize + 7) // 8
  match d:
    case Dt{pri, bits, cls, nm}:
      U32.div(U32.add(bits, 7), 8)

# tinygrad dtype.py DType.min / DType.max. None stands for "no U32 limit":
# every float (the bound is -inf or +inf), `void` and `bool` (False/True are
# not numbers here), and any width past 32 (2^64-1 does not fit). dtype.bend
# carries the 64-bit limits as an I64 pair.
#
# ONE FOLD FOR BOTH LIMITS. `top` picks max over min; the four answers per class
# collapse to two per class, and a def per case arm would be eight defs saying
# the same thing.
def Cls.sgn(c: Cls) -> Maybe<&1, Bool>:
  match c:
    case CSint{}: Some{True{}}
    case CUint{}: Some{False{}}
    case _: None{}

def Dt.range.smag(top: Bool, bits: U32) -> U32:
  match top:
    case True{}: dt_max_signed(bits)
    case False{}: dt_min_signed(bits)

def Dt.range.lim(sgn: Bool, top: Bool, bits: U32) -> Maybe<&2, U32>:
  match sgn:
    case True{}: Some{Dt.range.smag(top, bits)}
    case False{}: Some{dt_umax_of(bits)}

def Dt.range.wide(sgn: Bool, top: Bool, wide: Bool, bits: U32) -> Maybe<&2, U32>:
  match wide:
    case True{}: None{}
    case False{}: Dt.range.lim(sgn, top, bits)

def Dt.range(sgn: Maybe<&1, Bool>, top: Bool, wide: Bool, bits: U32) -> Maybe<&2, U32>:
  match sgn:
    case None{}: None{}
    case Some{t}: Dt.range.wide(t, top, wide, bits)

def Dt.min(d: Dt) -> Maybe<&2, U32>:
  match d:
    case Dt{pri, +bits, cls, nm}:
      Dt.range(Cls.sgn(cls), False{}, U32.is_gt(bits, 32), bits)

def Dt.max(d: Dt) -> Maybe<&2, U32>:
  match d:
    case Dt{pri, +bits, cls, nm}:
      Dt.range(Cls.sgn(cls), True{}, U32.is_gt(bits, 32), bits)

# ===========================================================================
# Shape -- tinyspec's shape is a tuple of ints; a dimension may be symbolic,
# so a dim is either a literal or an Sp that evaluates to one.
# ===========================================================================

type Sdim is Data:
  SN{v: Nat}
  SS{x: Sp}

type Shape is Data:
  Sh{dims: List<&2, Sdim>}

def Shape.of(+xs: List<&2, Sdim>) -> Shape:
  Sh{xs}

# The rank is a fold, not a stored field: storing it would read the dim list
# twice, and `+` on a list costs a reference count for no gain here.
def Shape.ndim(s: Shape) -> Nat:
  match s:
    case Sh{ds}: List.length(&2, Sdim, ds)

def Shape.empty() -> Shape:
  Sh{Nil{}}

def Shape.to_dims(s: Shape) -> List<&2, Sdim>:
  match s:
    case Sh{ds}: ds

def Shape.append(s: Shape, +d: Sdim) -> Shape:
  match s:
    case Sh{ds}: Sh{List.append(&2, Sdim, ds, d <> Nil{})}

def Shape.append_dims(a: Shape, b: Shape) -> Shape:
  match a:
    case Sh{ds}:
      match b:
        case Sh{es}: Sh{List.append(&2, Sdim, ds, es)}

def Shape.prepend(d: Sdim, s: Shape) -> Shape:
  match s:
    case Sh{ds}: Sh{d <> ds}

# Base `List.drop`: `n=0` keeps the head. The match this replaced returned
# the tail at `case 0n`, so it dropped `n + 1`.
def drop_n(ds: List<&2, Sdim>, n: Nat) -> List<&2, Sdim>:
  List.drop(&2, Sdim, ds, n)

def Shape.drop(s: Shape, n: Nat) -> Shape:
  match s:
    case Sh{ds}: Shape.of(drop_n(ds, n))

# ===========================================================================
# Broadcast -- tinyspec: "right-align shapes, element-wise max; each axis must
# be equal or 1". `zip_max` IS the right-align: when one list runs out the
# other continues, so the shorter shape keeps its axes.
# ===========================================================================

def Shape.max_dim(a: Sdim, b: Sdim) -> Sdim:
  match a:
    case SN{va}:
      match b:
        case SN{vb}: SN{Nat.max(va, vb)}
        case SS{p}: SS{p}
    case SS{p}:
      match b:
        case SN{vb}: SS{p}
        case SS{q}: SS{p}

def zip_max(a: List<&2, Sdim>, b: List<&2, Sdim>) -> List<&2, Sdim>:
  # Right-alignment: the SHORTER shape keeps its own axes, so whichever list
  # runs out first hands the remainder back untouched. That is what makes
  # (2,) broadcast with (2,2) to (2,2) rather than truncating to (2,).
  match a:
    case Nil{}: b
    case x <> xs:
      match b:
        case Nil{}: a
        case y <> ys: Shape.max_dim(x, y) <> zip_max(xs, ys)

def dim_of(d: Sdim) -> Nat:
  match d:
    case SN{v}: v
    case SS{x}: 0n      # a symbolic dim counts as 0 until it is folded

def prod(ds: List<&2, Sdim>) -> Nat:
  match ds:
    case Nil{}: 1n
    case d <> r: Nat.mul(dim_of(d), prod(r))

# The shape of an Index: the index shapes in order, then the base's trailing
# dims. `k` is the number of indices, and it is the count of dims the base
# loses -- one per index, which is `UOp._shape` at tinygrad/uop/ops.py:353:
#
#     shp:list[sint] = []
#     for s in self.src[1:]: shp.extend(list(s.shape))
#     return tuple(shp) + self.src[0].shape[len(self.src[1:]):]
#
# `k` is a parameter rather than `Shape.ndim(pre)` because the two differ as
# soon as there are two indices: `Index(T, ())` removes one dim even though its
# own shape is empty, so the drop is driven by the arity and not by the rank of
# the concatenation.
def Sp.shape.index(pre: Maybe<&2, Shape>, bt: Maybe<&2, Shape>, k: Nat) -> Maybe<&2, Shape>:
  match pre:
    case Some{+p}:
      match bt:
        case Some{b}: Some{Shape.of(List.append(&2, Sdim, Shape.to_dims(p), drop_n(Shape.to_dims(b), k)))}
        case None{}: None{}
    case None{}: None{}

def dims_prod(s: Maybe<&2, Shape>) -> Nat:
  match s:
    case Some{sh}: prod(Shape.to_dims(sh))
    case None{}: 0n

def dims_zip_max(a: Maybe<&2, Shape>, b: Maybe<&2, Shape>) -> Maybe<&2, Shape>:
  match a:
    case Some{sa}:
      match b:
        case Some{sb}: Some{Shape.of(zip_max(Shape.to_dims(sa), Shape.to_dims(sb)))}
        case None{}: None{}
    case None{}: None{}

def dims_append(a: Maybe<&2, Shape>, b: Maybe<&2, Shape>) -> Maybe<&2, Shape>:
  match a:
    case Some{sa}:
      match b:
        case Some{sb}: Some{Shape.append_dims(sa, sb)}
        case None{}: None{}
    case None{}: None{}

# ===========================================================================
# The Maybe combinators.
#
# A `match` may not scrutinise a computed value, so a Maybe that comes back
# from a call has to reach a helper that takes it as a PARAMETER. `k` is a
# closure used exactly once, which affine Bend allows.
# ===========================================================================

def on_shape(m: Maybe<&2, Shape>, k: Shape -> Maybe<&2, Shape>) -> Maybe<&2, Shape>:
  match m:
    case None{}: None{}
    case Some{s}: k(s)

# ===========================================================================
# The op catalogue -- one constructor per op in tinyspec.tex. The 20 Codegen
# Ops are not here: tinyspec says of them "these ops are not part of the core
# specification and are subject to change".
#
# `src` is a list, so an op's arity is the length of that list and is checked
# by the pattern match rather than stored twice.
# ===========================================================================

type Sp is Data:
  # -- source ops (leaves) -------------------------------------------------
  SpBuffer{size: Nat, dt: Dt, dev: Dev, addr: Addr}
  SpAlloc{size: Nat, dt: Dt, dev: Dev, addr: Addr}
  SpParam{size: Nat, dt: Dt, dev: Dev}
  SpConst{v: Sp, dt: Dt}
  SpBinary{size: Nat}

  # -- call ops ------------------------------------------------------------
  SpCall{body: Sp, args: List<&2, Sp>}

  # -- movement ops --------------------------------------------------------
  SpPermute{t: Sp, order: List<&2, Nat>}
  SpFlip{t: Sp, flags: List<&2, Bool>}
  SpReshape{t: Sp, src: Sp, dst: List<&2, Sdim>}
  SpExpand{t: Sp, pre: List<&2, Sdim>, total: List<&2, Sdim>}
  SpPad{t: Sp, off: List<&2, Sdim>, size: List<&2, Sdim>}
  SpShrink{t: Sp, off: List<&2, Sdim>, size: List<&2, Sdim>}
  SpStack{ts: List<&2, Sp>}
  SpBitcast{t: Sp, dt: Dt}
  SpUnshard{t: Sp, ranges: List<&2, Sp>, axes: List<&2, Nat>}

  # -- Index, at BOUNDED ARITY. --------------------------------------------
  # tinyspec: "Index from left. ()-shaped i removes dim; (k,)-shaped makes it
  # k" -- the shape is the index shapes in order, then the base's trailing dims,
  # so it needs EVERY index's shape, not just the head. The index list cannot
  # stay a List: the shape fold has no way to map itself over one (header fact
  # 4), and an Index of arity k is exactly what makes a fold necessary, because
  # each index contributes a differently-shaped piece.
  #
  # THE BOUND IS FOUR, and the evidence is in tinygrad:
  #
  #   * An Index's arity is a USER-LEVEL index tuple, bounded by the base's rank.
  #     `mixin/movement.py:_normalize_indices` raises `too many indices` above
  #     `ndim` and otherwise pads the tuple to exactly `ndim` entries, so the
  #     arity of `x[i0, ..., ik]` is `x.ndim`.
  #   * Every `.index(...)` written out in tinygrad/ passes at most THREE
  #     operands: a scan of all 209 static call sites gives 185 with one, 23 with
  #     two and 1 with three (`renderer/nir.py:141`).
  #   * The arity that actually dominates a real model is FOUR: instrumenting
  #     `UOp.index` over a `beautiful_mnist` train step (forward, backward and an
  #     Adam step) gives 2008 calls at arity 1 and 308 at arity 4.
  #
  # WHAT THE BOUND DOES NOT COVER, stated plainly: the schedule builds Index
  # nodes by SPLAYING a range list -- `schedule/rangeify.py:195` `index(
  # *orig_ranges)` and `schedule/indexing.py:93` `index(*src_rngs)` -- so the
  # arity there is a kernel's axis count, and the same instrumented run reaches
  # 8 (and 0, via `schedule/prepare.py:68`). No finite bound covers that, and
  # none claims to: those nodes live in the compilation arena, which this file
  # does not model. What the bound covers is tinyspec's own `Index(T, i_0, ...)`
  # as a source-level construct, and a rank-4 tensor is the common case.
  # Raising the bound is mechanical: one constructor, one arm, one `dims_append`.
  SpIdx0{t: Sp}
  SpIdx1{t: Sp, a: Sp}
  SpIdx2{t: Sp, a: Sp, b: Sp}
  SpIdx3{t: Sp, a: Sp, b: Sp, c: Sp}
  SpIdx4{t: Sp, a: Sp, b: Sp, c: Sp, d: Sp}

  # -- reduce ops ----------------------------------------------------------
  SpReduce{t: Sp, ranges: List<&2, Sp>, op: Sp, n: Nat}

  # -- load ops ------------------------------------------------------------
  SpLoad{buf: Sp, alt: Maybe<&2, Sp>, gate: Maybe<&2, Sp>}
  SpCopy{buf: Sp, dev: Dev}

  # -- store ops -----------------------------------------------------------
  SpStore{buf: Sp, val: Sp, gate: Maybe<&2, Sp>}

  # -- ordering ops --------------------------------------------------------
  SpRange{bound: Sp}
  SpEnd{body: Sp, ranges: List<&2, Sp>}
  SpBackedge{body: Sp, rng: Sp, cond: Sp}
  SpAfter{buf: Sp, deps: List<&2, Sp>}
  SpGroup{us: List<&2, Sp>}
  SpSink{ss: List<&2, Sp>}
  SpLinear{uops: List<&2, Sp>}

  # -- elementwise ops -----------------------------------------------------
  SpRecip{a: Sp}
  SpTrunc{a: Sp}
  SpCast{a: Sp, dt: Dt}
  SpAdd{a: Sp, b: Sp}
  SpMul{a: Sp, b: Sp}
  SpMax{a: Sp, b: Sp}
  SpMod{a: Sp, b: Sp}
  SpIdiv{a: Sp, b: Sp}
  SpCmpLt{a: Sp, b: Sp}
  SpCmpNe{a: Sp, b: Sp}
  SpXor{a: Sp, b: Sp}
  SpOr{a: Sp, b: Sp}
  SpAnd{a: Sp, b: Sp}
  SpShr{a: Sp, b: Sp}
  SpShl{a: Sp, b: Sp}
  SpWhere{p: Sp, a: Sp, b: Sp}

  # -- marker ops: "identity on data" --------------------------------------
  SpContiguousBackward{a: Sp}
  SpDetach{a: Sp}

  # Invalid: tinyspec's Pad fills with it and it rides inside a Const's value
  SpInvalid{}

# tinyspec Stack: "Join along a newly created leading axis", so the shape is a
# NEW leading axis of the operand count followed by the head operand's shape.
# Only the head is needed, which is a legal descent (a list head binder is a
# field); the count is read off the tail, which no self-call ever touches.
def Sp.shape.stack(head: Maybe<&2, Shape>, k: Nat) -> Maybe<&2, Shape>:
  on_shape(head, sh => Some{Shape.prepend(SN{k}, sh)})

# tinyspec Reduce: "Reduce the first n axes of T", so the shape drops n.
def Sp.shape.reduce(m: Maybe<&2, Shape>, k: Nat) -> Maybe<&2, Shape>:
  on_shape(m, sh => Some{Shape.drop(sh, k)})

# ===========================================================================
# Derived property: shape -- tinyspec's shape column, op by arm.
#
# ONE recursive def, no @unsafe, no fuel. Every arm binds each operand's shape
# to its own local and every self-call passes a distinct field of `s`, so the
# termination check sees a descent in every call and there is nothing for a
# caller to get wrong. The broadcast arms are three lines each because their
# shared helper would have to self-call this def, which is mutual recursion; see
# header fact 1.
# ===========================================================================

def Sp.shape(s: Sp) -> Maybe<&2, Shape>:
  match s:
    # -- source ops
    case SpBuffer{size, dt, dev, addr}: Some{Shape.of([SN{size}])}
    case SpAlloc{size, dt, dev, addr}: Some{Shape.of([SN{size}])}
    case SpParam{size, dt, dev}: Some{Shape.of([SN{size}])}
    case SpConst{v, dt}: Some{Shape.empty()}    # "A scalar constant with shape ()"
    case SpBinary{size}: Some{Shape.of([SN{size}])}

    # -- movement ops: all but these pass src[0].shape through
    case SpPermute{t, order}: Sp.shape(t)
    case SpFlip{t, flags}: Sp.shape(t)
    case SpReshape{t, src, dst}: Some{Shape.of(dst)}
    case SpExpand{t, pre, total}: Some{Shape.of(total)}
    case SpPad{t, off, size}: Some{Shape.of(size)}
    case SpShrink{t, off, size}: Some{Shape.of(size)}
    # Index: every index shape in order, then the base's trailing dims. Each
    # index is a distinct field, so each of these is its own descent.
    case SpIdx0{t}:
      # an index of no operands drops no dims and keeps the base shape whole.
      # tinygrad builds these (77 per train step, from schedule/prepare.py:68),
      # so the family starts at zero rather than assuming arity 1.
      Sp.shape(t)
    case SpIdx1{t, a}:
      p = Sp.shape(a)
      bt = Sp.shape(t)
      Sp.shape.index(p, bt, 1n)
    case SpIdx2{t, a, b}:
      p1 = Sp.shape(a)
      p2 = Sp.shape(b)
      bt = Sp.shape(t)
      Sp.shape.index(dims_append(p1, p2), bt, 2n)
    case SpIdx3{t, a, b, c}:
      p1 = Sp.shape(a)
      p2 = Sp.shape(b)
      p3 = Sp.shape(c)
      bt = Sp.shape(t)
      pre = dims_append(dims_append(p1, p2), p3)
      Sp.shape.index(pre, bt, 3n)
    case SpIdx4{t, a, b, c, d}:
      p1 = Sp.shape(a)
      p2 = Sp.shape(b)
      p3 = Sp.shape(c)
      p4 = Sp.shape(d)
      bt = Sp.shape(t)
      pre = dims_append(dims_append(dims_append(p1, p2), p3), p4)
      Sp.shape.index(pre, bt, 4n)
    # Stack: a new leading axis of the operand count, then the head's shape.
    # The count comes off the tail, which no self-call touches; "All shapes must
    # match" is why the head alone carries it, and an empty Stack has no shape.
    case SpStack{ts}:
      match ts:
        case Nil{}: None{}
        case t <> rest:
          m = Sp.shape(t)
          n = List.length(&2, Sp, rest)
          Sp.shape.stack(m, Nat.add(n, 1n))
    # Bitcast rescales the LAST dim by the itemsize ratio and Unshard
    # multiplies each named axis by its Range, so neither passes
    # through. TODO: both are stubs; see .agents/TODO.md.
    case SpBitcast{t, dt}: Sp.shape(t)
    case SpUnshard{t, ranges, axes}: Sp.shape(t)

    # -- reduce op: remove the first k axes
    case SpReduce{t, ranges, op, k}:
      m = Sp.shape(t)
      Sp.shape.reduce(m, k)

    # -- load ops
    case SpLoad{buf, alt, gate}: Sp.shape(buf)
    case SpCopy{buf, dev}: Sp.shape(buf)

    # -- store op: "Output is void"
    case SpStore{buf, val, gate}: None{}

    # -- ordering ops
    case SpRange{bound}: Some{Shape.empty()}
    case SpEnd{body, ranges}: None{}
    case SpBackedge{body, rng, cond}: None{}
    case SpAfter{buf, deps}: Sp.shape(buf)
    case SpGroup{us}: None{}
    case SpSink{ss}: None{}
    case SpLinear{uops}: None{}

    # -- elementwise ops: "all inputs same shape, output same shape", so each
    # binary arm is the broadcast of its two operand shapes. The helper cannot
    # be factored out (header fact 1), hence three lines per arm.
    case SpRecip{a}: Sp.shape(a)
    case SpTrunc{a}: Sp.shape(a)
    case SpCast{a, dt}: Sp.shape(a)
    case SpAdd{a, b}:
      sa = Sp.shape(a)
      sb = Sp.shape(b)
      dims_zip_max(sa, sb)
    case SpMul{a, b}:
      sa = Sp.shape(a)
      sb = Sp.shape(b)
      dims_zip_max(sa, sb)
    case SpMax{a, b}:
      sa = Sp.shape(a)
      sb = Sp.shape(b)
      dims_zip_max(sa, sb)
    case SpMod{a, b}:
      sa = Sp.shape(a)
      sb = Sp.shape(b)
      dims_zip_max(sa, sb)
    case SpIdiv{a, b}:
      sa = Sp.shape(a)
      sb = Sp.shape(b)
      dims_zip_max(sa, sb)
    case SpCmpLt{a, b}:
      sa = Sp.shape(a)
      sb = Sp.shape(b)
      dims_zip_max(sa, sb)
    case SpCmpNe{a, b}:
      sa = Sp.shape(a)
      sb = Sp.shape(b)
      dims_zip_max(sa, sb)
    case SpXor{a, b}:
      sa = Sp.shape(a)
      sb = Sp.shape(b)
      dims_zip_max(sa, sb)
    case SpOr{a, b}:
      sa = Sp.shape(a)
      sb = Sp.shape(b)
      dims_zip_max(sa, sb)
    case SpAnd{a, b}:
      sa = Sp.shape(a)
      sb = Sp.shape(b)
      dims_zip_max(sa, sb)
    case SpShr{a, b}:
      sa = Sp.shape(a)
      sb = Sp.shape(b)
      dims_zip_max(sa, sb)
    case SpShl{a, b}:
      sa = Sp.shape(a)
      sb = Sp.shape(b)
      dims_zip_max(sa, sb)
    # Where: the dtype column says src[1].dtype, so the shape follows `b`
    case SpWhere{q, a, b}:
      sa = Sp.shape(a)
      sb = Sp.shape(b)
      dims_zip_max(sa, sb)

    # -- marker ops: "identity on data"
    case SpContiguousBackward{a}: Sp.shape(a)
    case SpDetach{a}: Sp.shape(a)

    # -- Call: "A value Call is void"
    case SpCall{body, args}: None{}

    case SpInvalid{}: Some{Shape.empty()}

# ===========================================================================
# The named dtypes -- every one of tinygrad's twenty, in dtype.py's own order.
#
# tinygrad's `priority` column: a larger number upcasts later, so priority is a
# partial order and least_upper_dtype is its meet. The names are dtype.py's
# `name` field, which is what `repr` prints; dtype.bend aliases them to the
# attribute names tinygrad code uses (float32 for "f32" and so on).
#
# THE NAMES ARE THE RUST NAMES. tinygrad 793abbb ("modernize tinygrad's dtype to
# match rust") moved `DType.name` off the C spellings -- "signed char", "half",
# "__bf16", "float", "double", "float8_e4m3" -- and onto i8/u8/i16/u16/i32/u32/
# i64/u64/f16/bf16/f32/f64/fp8e4m3/fp8e5m2/..., keeping the OLD ATTRIBUTE names
# only as a block upstream labels `# legacy dtype aliases`. `DType.__repr__` was
# `f"dtypes.{INVERSE_DTYPES_DICT[self.name]}"` and is now `f"dtypes.{self.name}"`,
# so repr used to print the ALIAS ("dtypes.float") and now prints the name
# ("dtypes.f32"), and INVERSE_DTYPES_DICT is gone. Only the `name` FIELD moved:
# priority, bitsize and the char code are untouched, so every table keyed on
# those is still right and only the name keys below are new.
# ===========================================================================

def void() -> Dt: Dt{0, 0, CVoid{}, "void"}
def weakint() -> Dt: Dt{0, 800, CWeakInt{}, "weakint"}

# tinyspec's IR name for weakint: the dtype an index is carried in. Same value,
# the spec's word for it.
def index() -> Dt: weakint()
def boolean() -> Dt: Dt{0, 1, CBool{}, "bool"}
def int8() -> Dt: Dt{1, 8, CSint{}, "i8"}
def uint8() -> Dt: Dt{2, 8, CUint{}, "u8"}
def int16() -> Dt: Dt{3, 16, CSint{}, "i16"}
def uint16() -> Dt: Dt{4, 16, CUint{}, "u16"}
def int32() -> Dt: Dt{5, 32, CSint{}, "i32"}
def uint32() -> Dt: Dt{6, 32, CUint{}, "u32"}
def int64() -> Dt: Dt{7, 64, CSint{}, "i64"}
def uint64() -> Dt: Dt{8, 64, CUint{}, "u64"}
def weakfloat() -> Dt: Dt{9, 800, CWeakFloat{}, "weakfloat"}
def fp8e4m3() -> Dt: Dt{10, 8, CFloat{}, "fp8e4m3"}
def fp8e4m3fnuz() -> Dt: Dt{10, 8, CFloat{}, "fp8e4m3fnuz"}
def fp8e5m2() -> Dt: Dt{11, 8, CFloat{}, "fp8e5m2"}
def fp8e5m2fnuz() -> Dt: Dt{11, 8, CFloat{}, "fp8e5m2fnuz"}
def half() -> Dt: Dt{12, 16, CFloat{}, "f16"}
def bfloat16() -> Dt: Dt{13, 16, CFloat{}, "bf16"}
def single() -> Dt: Dt{14, 32, CFloat{}, "f32"}
def double() -> Dt: Dt{15, 64, CFloat{}, "f64"}

# ===========================================================================
# Derived property: dtype -- tinyspec's dtype column, op by arm. Same
# discipline as the shape fold: one def, no @unsafe, no fuel, every descent a
# field of `s`. A dtype arm reads at most one operand, so no arm needs a local.
# ===========================================================================

def Sp.dtype(s: Sp) -> Maybe<&2, Dt>:
  match s:
    case SpBuffer{size, dt, dev, addr}: Some{dt}          # "from arg"
    case SpAlloc{size, dt, dev, addr}: Some{dt}
    case SpParam{size, dt, dev}: Some{dt}
    case SpConst{v, dt}: Some{dt}
    case SpBinary{size}: Some{uint8()}                    # "has dtype uint8"

    # -- movement ops: src[0].dtype
    case SpPermute{t, order}: Sp.dtype(t)
    case SpFlip{t, flags}: Sp.dtype(t)
    case SpReshape{t, src, dst}: Sp.dtype(t)
    case SpExpand{t, pre, total}: Sp.dtype(t)
    case SpPad{t, off, size}: Sp.dtype(t)
    case SpShrink{t, off, size}: Sp.dtype(t)
    case SpIdx0{t}: Sp.dtype(t)
    case SpIdx1{t, a}: Sp.dtype(t)
    case SpIdx2{t, a, b}: Sp.dtype(t)
    case SpIdx3{t, a, b, c}: Sp.dtype(t)
    case SpIdx4{t, a, b, c, d}: Sp.dtype(t)
    # "All shapes must match", so Stack's dtype is the head's; one descent.
    case SpStack{ts}:
      match ts:
        case Nil{}: None{}
        case t <> _: Sp.dtype(t)
    case SpBitcast{t, dt}: Some{dt}                       # "from arg"
    case SpUnshard{t, ranges, axes}: Sp.dtype(t)

    case SpReduce{t, ranges, op, k}: Sp.dtype(t)
    case SpLoad{buf, alt, gate}: Sp.dtype(buf)
    case SpCopy{buf, dev}: Sp.dtype(buf)
    case SpStore{buf, val, gate}: None{}                  # void

    case SpRange{bound}: Some{index()}                    # "index"
    case SpEnd{body, ranges}: None{}
    case SpBackedge{body, rng, cond}: None{}
    case SpAfter{buf, deps}: Sp.dtype(buf)
    case SpGroup{us}: None{}
    case SpSink{ss}: None{}
    case SpLinear{uops}: None{}

    case SpRecip{a}: Sp.dtype(a)
    case SpTrunc{a}: Sp.dtype(a)
    case SpCast{a, dt}: Some{dt}                           # "from arg"
    case SpAdd{a, b}: Sp.dtype(a)
    case SpMul{a, b}: Sp.dtype(a)
    case SpMax{a, b}: Sp.dtype(a)
    case SpMod{a, b}: Sp.dtype(a)
    case SpIdiv{a, b}: Sp.dtype(a)
    case SpCmpLt{a, b}: Some{boolean()}                   # bool
    case SpCmpNe{a, b}: Some{boolean()}
    case SpXor{a, b}: Sp.dtype(a)
    case SpOr{a, b}: Sp.dtype(a)
    case SpAnd{a, b}: Sp.dtype(a)
    case SpShr{a, b}: Sp.dtype(a)
    case SpShl{a, b}: Sp.dtype(a)
    case SpWhere{q, a, b}: Sp.dtype(b)                     # src[1].dtype

    case SpContiguousBackward{a}: Sp.dtype(a)
    case SpDetach{a}: Sp.dtype(a)
    case SpCall{body, args}: None{}                        # void
    case SpInvalid{}: Some{boolean()}

# Gate. No CPython `drop_n`. The literals are tinygrad's `_shape` from
# `.agents/slop/ind/dropn-oracle.py`: Reduce n=0 is (4,5,6); Reduce n=1 and
# an arity-1 scalar Index are (5,6), rank 2. The old `case 0n: r` prints
# 5,6 / 6 / rank 1, so none of these rows pass under both behaviours.

def dn_dim(d: Sdim) -> String:
  match d:
    case SN{v}: Nat.show(v)
    case SS{_}: "SS"

def dn_dims(ds: List<&2, Sdim>) -> String:
  match ds:
    case Nil{}: ""
    case d <> r:
      match r:
        case Nil{}: dn_dim(d)
        case _ <> _: dn_dim(d) ++ "," ++ dn_dims(r)

def dn_of(m: Maybe<&2, Shape>) -> List<&2, Sdim>:
  match m:
    case Some{sh}: Shape.to_dims(sh)
    case None{}: Nil{}

def dn_rank(m: Maybe<&2, Shape>) -> Nat:
  match m:
    case Some{sh}: Shape.ndim(sh)
    case None{}: 0n

def dn_456() -> List<&2, Sdim>:
  [SN{4n}, SN{5n}, SN{6n}]

def dn_base() -> Sp:
  SpReshape{SpInvalid{}, SpInvalid{}, dn_456()}

def dn_idx1() -> Sp:
  SpIdx1{dn_base(), SpRange{SpInvalid{}}}

def dn_red(n: Nat) -> Sp:
  SpReduce{dn_base(), Nil{}, SpInvalid{}, n}

def dn_gate(+nm: String, +got: String, +exp: String) -> IO(Unit):
  do IO<Unit>:
    IO.print(nm ++ "=" ++ got)
    IO.print(nm ++ "_ok=" ++ Bool.show(String.eq(got, exp)))

def main() -> IO(Unit):
  do IO<Unit>:
    dn_gate("drop_n_456_0", dn_dims(drop_n(dn_456(), 0n)), "4,5,6")
    dn_gate("drop_n_456_1", dn_dims(drop_n(dn_456(), 1n)), "5,6")
    dn_gate("idx1_rank3", Nat.show(dn_rank(Sp.shape(dn_idx1()))), "2")
    dn_gate("idx1_456", dn_dims(dn_of(Sp.shape(dn_idx1()))), "5,6")
    dn_gate("red0_456", dn_dims(dn_of(Sp.shape(dn_red(0n)))), "4,5,6")
    dn_gate("red1_456", dn_dims(dn_of(Sp.shape(dn_red(1n)))), "5,6")
