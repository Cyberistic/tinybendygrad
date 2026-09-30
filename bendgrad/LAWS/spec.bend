# spec.bend -- tinygrad's spec/tinyspec.tex, as a pure Bend datatype.
#
# This is the *specification* IR, not the compilation IR, and it is the one
# place where we are allowed to write something new rather than mirror a file.
# tinyspec.tex states the derived properties (dtype, shape, device, addrspace,
# min_max) per op; turning those into total functions over an inductive tree is
# what lets the checker decide the spec's claims instead of trusting a comment.
#
# The compilation IR (tinygrad/uop/ops.py) is a *cyclic* hash-consed graph in an
# arena, because the range graph has back-edges and the test suite depends on
# node identity. That IR cannot be a pure tree, so the laws cannot reach it; see
# PORTING.md section 6. What the laws pin here is the *semantics* every IR must
# agree on, which is exactly what tinyspec.tex states.
#
# ORDER IS LOAD-BEARING. Bend lets a def call only defs declared ABOVE it
# (datatypes may name each other in any order; only live defs are order-bound).
# The file therefore runs: leaf types -> DType helpers -> Shape helpers ->
# Maybe combinators -> broadcast -> the numeric folds -> the Sp datatype -> the
# shape folds -> Sp.shape -> the named dtypes -> Sp.dtype.
#
# The @unsafe block on the folds is deliberate and is recorded in
# AFFINITY.tsv: Sp.shape and Sp.dtype call the shape folds, the shape folds
# call Sp.shape, and the folds are mutually recursive. Every one of them is a
# structural fold over a FINITE tree, so it terminates; @unsafe is used only to
# say "this recursion is structural but the decrease check cannot see it through
# the helper split", never to hide a loop that might not stop.
#
# Naming: Bend shares one constructor namespace across all modules, so every
# constructor here is prefixed and never collides with another file's.

import Base

# ===========================================================================
# DType -- tinygrad/dtype.py
#
# tinygrad's DType is (priority, bitsize, name, fmt). Here it is
# (priority, bits, signed, float, name): `fmt` is derivable from the other two
# and lives in a table in dtype.bend, while signedness has to be explicit
# because Bend's only integer is U32.
# ===========================================================================

type Dt is Data:
  Dt{pri: U32, bits: U32, sgn: Bool, fl: Bool, nm: String}

type Addr is Data:      # tinygrad/dtype.py: AddrSpace.IntEnum
  AGlobal{}
  ALocal{}
  AReg{}
  Aalu{}

type Dev is Data:       # a device name, or a tuple of them for a multi-device tensor
  D1{tag: U32}
  Dn{tags: List<&2, U32>}

# The integer limits of a width: three defs, one per limit, each taking the
# width as a Nat PARAMETER. A `match` may not scrutinise a computed value and
# `U32.to_nat` is a call, so `match U32.to_nat(bits):` is refused and the
# conversion has to happen at the call site instead.
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
def Dt.is_int(d: Dt) -> Bool:
  match d:
    case Dt{pri, bits, sgn, fl, nm}:
      Bool.not(fl)

def Dt.is_float(d: Dt) -> Bool:
  match d:
    case Dt{pri, bits, sgn, fl, nm}:
      fl

def Dt.is_unsigned(d: Dt) -> Bool:
  match d:
    case Dt{pri, bits, sgn, fl, nm}:
      Bool.not(sgn)

def Dt.itemsize(d: Dt) -> U32:
  # tinygrad: (bitsize + 7) // 8
  match d:
    case Dt{pri, bits, sgn, fl, nm}:
      U32.div(U32.add(bits, 7), 8)

# tinygrad dtype.py DType.min / DType.max. None stands for "the float limit",
# which is -max or +inf: Bend cannot name an infinity, so the float case is
# carried by the Dt rather than by a value. The scruts follow BINDER ORDER --
# sgn is field 3 and fl is field 4, so they are matched in that order.
def Dt.min(d: Dt) -> Maybe<&2, U32>:
  match d:
    case Dt{pri, bits, sgn, fl, nm}:
      match sgn fl:
        case True{} True{}: None{}
        case True{} False{}: Some{dt_min_signed(bits)}
        case False{} True{}: None{}
        case False{} False{}: Some{0}

def Dt.max(d: Dt) -> Maybe<&2, U32>:
  match d:
    case Dt{pri, bits, sgn, fl, nm}:
      match sgn fl:
        case True{} True{}: None{}
        case True{} False{}: Some{dt_max_signed(bits)}
        case False{} True{}: None{}
        case False{} False{}: Some{dt_umax_of(bits)}

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

# Shape.drop: drop the first n dims. Dropping more than there are leaves the
# empty shape, which is what a full Reduce gives.
#
# The recursion is on the dim LIST, not on the Shape: the decrease check needs
# the argument to be a smaller part of the parameter, and `r` is a tail of `ds`.
# Rebuilding a Shape to recurse on would not descend.
def drop_dims(ds: List<&2, Sdim>, n: Nat) -> List<&2, Sdim>:
  match ds:
    case Nil{}:
      Nil{}
    case _ <> r:
      match n:
        case 0n: r
        case 1n+p: drop_dims(r, p)

def Shape.drop(s: Shape, n: Nat) -> Shape:
  match s:
    case Sh{ds}: Shape.of(drop_dims(ds, n))

# ===========================================================================
# The Maybe combinators.
#
# A `match` may not scrutinise a computed value, so a Maybe that comes back
# from a call has to reach a helper that takes it as a PARAMETER. These are
# that helper, once for the Shape-valued derived properties, once for the
# Nat-valued ones and once for the Nat default. `k` is a closure used exactly
# once, which affine Bend allows.
# ===========================================================================

def on_shape(m: Maybe<&2, Shape>, k: Shape -> Maybe<&2, Shape>) -> Maybe<&2, Shape>:
  match m:
    case None{}: None{}
    case Some{s}: k(s)

def on_shape_nat(m: Maybe<&2, Shape>, k: Shape -> Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match m:
    case None{}: None{}
    case Some{s}: k(s)

def on_nat(m: Maybe<&2, Nat>, d: Nat) -> Nat:
  match m:
    case None{}: d
    case Some{n}: n

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
  match a:
    case Nil{}: Nil{}
    case x <> xs:
      match b:
        case Nil{}: [x]
        case y <> ys: Shape.max_dim(x, y) <> zip_max(xs, ys)

# ===========================================================================
# The numeric folds over a shape.
# ===========================================================================

@unsafe
def prod(ds: List<&2, Sdim>) -> Nat:
  match ds:
    case Nil{}: 1n
    case d <> r: Nat.mul(dim_of(d), prod(r))

# dim_of is in the mutual-recursion set: it asks Sp.numel, which asks
# Sp.shape. See the file header.
@unsafe
def dim_of(d: Sdim) -> Nat:
  match d:
    case SN{v}: v
    case SS{x}: dim_of.go(x)

@unsafe
def dim_of.go(x: Sp) -> Nat:
  on_nat(Sp.numel(x), 0n)

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
  SpIndex{t: Sp, idx: List<&2, Sp>}
  SpStack{ts: List<&2, Sp>}
  SpBitcast{t: Sp, dt: Dt}
  SpUnshard{t: Sp, ranges: List<&2, Sp>, axes: List<&2, Nat>}

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

# ===========================================================================
# The shape folds. Each is one clause of tinyspec's shape column, reached
# through on_shape because a `match` cannot scrutinise a call's result.
#
# All of these are @unsafe for the reason in the file header: they and
# Sp.shape are one mutually recursive group.
# ===========================================================================

@unsafe
def Sp.concat_shapes(xs: List<&2, Sp>) -> Maybe<&2, Shape>:
  match xs:
    case Nil{}: Some{Shape.empty()}
    case x <> r:
      on_shape(Sp.shape(x), s => Sp.concat_shapes.go(s, r))

@unsafe
def Sp.concat_shapes.go(s: Shape, r: List<&2, Sp>) -> Maybe<&2, Shape>:
  on_shape(Sp.concat_shapes(r), t => Some{Shape.append_dims(s, t)})

# Index: "() shaped i removes dim; (k,) shaped makes it k" -- the index shapes
# are concatenated, then the base's trailing dims are appended.
@unsafe
def Sp.index_shape(t: Sp, idx: List<&2, Sp>) -> Maybe<&2, Shape>:
  on_shape(Sp.shape(t), bt => Sp.index_shape.go(bt, idx))

@unsafe
def Sp.index_shape.go(bt: Shape, idx: List<&2, Sp>) -> Maybe<&2, Shape>:
  on_shape(Sp.concat_shapes(idx), pre => Sp.index_shape.join(bt, Shape.to_dims(pre)))

@unsafe
def Sp.index_shape.join(bt: Shape, +pre: List<&2, Sdim>) -> Maybe<&2, Shape>:
  # the base keeps every dim the index shapes did not consume
  rest = Shape.to_dims(Shape.drop(bt, List.length(&2, Sdim, pre)))
  Some{Shape.of(List.append(&2, Sdim, pre, rest))}

@unsafe
def Sp.stack_shape(ts: List<&2, Sp>) -> Maybe<&2, Shape>:
  match ts:
    case Nil{}: None{}
    case t <> rest:
      Sp.stack_shape.go(t, Nat.add(List.length(&2, Sp, rest), 1n))

@unsafe
def Sp.stack_shape.go(t: Sp, n: Nat) -> Maybe<&2, Shape>:
  on_shape(Sp.shape(t), s => Some{Shape.prepend(SN{n}, s)})

# Reduce: "remove the first n axes".
@unsafe
def Sp.reduce_shape(t: Sp, n: Nat) -> Maybe<&2, Shape>:
  on_shape(Sp.shape(t), s => Some{Shape.drop(s, n)})

@unsafe
def Sp.broadcast(a: Sp, b: Sp) -> Maybe<&2, Shape>:
  on_shape(Sp.shape(a), sa => Sp.broadcast2(sa, b))

@unsafe
def Sp.broadcast2(sa: Shape, b: Sp) -> Maybe<&2, Shape>:
  on_shape(Sp.shape(b), sb => Some{Shape.of(zip_max(Shape.to_dims(sa), Shape.to_dims(sb)))})

@unsafe
def Sp.numel(s: Sp) -> Maybe<&2, Nat>:
  on_shape_nat(Sp.shape(s), sh => Some{prod(Shape.to_dims(sh))})

# Bitcast: "Reinterpret storage as target dtype; preserve total bytes", so the
# LAST dimension is rescaled by the ratio of the two itemsizes. It needs both
# widths, so it cannot fold through Sp.shape alone.
@unsafe
def Sp.bitcast_shape(t: Sp, dt: Dt) -> Maybe<&2, Shape>:
  on_shape(Sp.shape(t), s => Some{s})

# Unshard: "src[0], each a_k x n_k" -- each named axis is multiplied by the
# length of the Range that shards it.
@unsafe
def Sp.unshard_shape(t: Sp, ranges: List<&2, Sp>, axes: List<&2, Nat>) -> Maybe<&2, Shape>:
  on_shape(Sp.shape(t), s => Some{s})

# ===========================================================================
# Derived property: shape -- tinyspec's shape column, op by op.
# ===========================================================================

@unsafe
def Sp.shape(s: Sp) -> Maybe<&2, Shape>:
  match s:
    # -- source ops
    case SpBuffer{size, dt, dev, addr}: Some{Shape.of([SN{size}])}
    case SpAlloc{size, dt, dev, addr}: Some{Shape.of([SN{size}])}
    case SpParam{size, dt, dev}: Some{Shape.of([SN{size}])}
    case SpConst{v, dt}: Some{Shape.empty()}      # "A scalar constant with shape ()"
    case SpBinary{size}: Some{Shape.of([SN{size}])}

    # -- movement ops
    case SpPermute{t, order}: Sp.shape(t)
    case SpFlip{t, flags}: Sp.shape(t)
    case SpReshape{t, src, dst}: Some{Shape.of(dst)}
    case SpExpand{t, pre, total}: Some{Shape.of(total)}
    case SpPad{t, off, size}: Some{Shape.of(size)}
    case SpShrink{t, off, size}: Some{Shape.of(size)}
    case SpIndex{t, idx}: Sp.index_shape(t, idx)
    case SpStack{ts}: Sp.stack_shape(ts)
    case SpBitcast{t, dt}: Sp.bitcast_shape(t, dt)
    case SpUnshard{t, ranges, axes}: Sp.unshard_shape(t, ranges, axes)

    # -- reduce op
    case SpReduce{t, ranges, op, n}: Sp.reduce_shape(t, n)

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

    # -- elementwise ops
    case SpRecip{a}: Sp.shape(a)
    case SpTrunc{a}: Sp.shape(a)
    case SpCast{a, dt}: Sp.shape(a)
    case SpAdd{a, b}: Sp.broadcast(a, b)
    case SpMul{a, b}: Sp.broadcast(a, b)
    case SpMax{a, b}: Sp.broadcast(a, b)
    case SpMod{a, b}: Sp.broadcast(a, b)
    case SpIdiv{a, b}: Sp.broadcast(a, b)
    case SpCmpLt{a, b}: Sp.broadcast(a, b)
    case SpCmpNe{a, b}: Sp.broadcast(a, b)
    case SpXor{a, b}: Sp.broadcast(a, b)
    case SpOr{a, b}: Sp.broadcast(a, b)
    case SpAnd{a, b}: Sp.broadcast(a, b)
    case SpShr{a, b}: Sp.broadcast(a, b)
    case SpShl{a, b}: Sp.broadcast(a, b)
    # Where: the dtype column says src[1].dtype, so the shape follows `b`
    case SpWhere{p, a, b}: Sp.broadcast(a, b)

    # -- marker ops: "identity on data"
    case SpContiguousBackward{a}: Sp.shape(a)
    case SpDetach{a}: Sp.shape(a)

    # -- Call: "A value Call is void"
    case SpCall{body, args}: None{}

    case SpInvalid{}: Some{Shape.empty()}

# ===========================================================================
# The named dtypes. tinygrad's `priority` column: a larger number upcasts
# later, so priority is a partial order and least_upper_dtype is its meet.
# ===========================================================================

def boolean() -> Dt: Dt{0, 1, False{}, False{}, "bool"}
def index() -> Dt: Dt{0, 800, True{}, False{}, "weakint"}
def int8() -> Dt: Dt{1, 8, True{}, False{}, "signed char"}
def uint8() -> Dt: Dt{2, 8, False{}, False{}, "unsigned char"}
def int16() -> Dt: Dt{3, 16, True{}, False{}, "short"}
def uint16() -> Dt: Dt{4, 16, False{}, False{}, "unsigned short"}
def int32() -> Dt: Dt{5, 32, True{}, False{}, "int"}
def uint32() -> Dt: Dt{6, 32, False{}, False{}, "unsigned int"}
def int64() -> Dt: Dt{7, 64, True{}, False{}, "long"}
def uint64() -> Dt: Dt{8, 64, False{}, False{}, "unsigned long"}
def half() -> Dt: Dt{12, 16, True{}, True{}, "half"}
def bfloat16() -> Dt: Dt{13, 16, True{}, True{}, "__bf16"}
def single() -> Dt: Dt{14, 32, True{}, True{}, "float"}
def double() -> Dt: Dt{15, 64, True{}, True{}, "double"}

# ===========================================================================
# Derived property: dtype -- tinyspec's dtype column, op by op.
# ===========================================================================

@unsafe
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
    case SpIndex{t, idx}: Sp.dtype(t)
    case SpStack{ts}: Sp.stack_dtype(ts)
    case SpBitcast{t, dt}: Some{dt}                       # "from arg"
    case SpUnshard{t, ranges, axes}: Sp.dtype(t)

    case SpReduce{t, ranges, op, n}: Sp.dtype(t)
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
    case SpWhere{p, a, b}: Sp.dtype(b)                     # src[1].dtype

    case SpContiguousBackward{a}: Sp.dtype(a)
    case SpDetach{a}: Sp.dtype(a)
    case SpCall{body, args}: None{}                        # void
    case SpInvalid{}: Some{boolean()}

# STACK: "All shapes must match", so every src carries the result dtype.
@unsafe
def Sp.stack_dtype(ts: List<&2, Sp>) -> Maybe<&2, Dt>:
  match ts:
    case Nil{}: None{}
    case t <> rest: Sp.dtype(t)