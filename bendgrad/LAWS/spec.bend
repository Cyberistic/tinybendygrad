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
# PORTING.md section 6.
#
# TERMINATION IS EXPLICIT FUEL, not @unsafe. Each derived property takes a `fuel:
# Nat` and spends one per level of the tree it descends, so the decrease check
# can see the descent and the def needs no escape hatch. The fuel is an upper
# bound on depth, and a caller that under-counts gets None -- the honest answer
# for "past this depth the property is unknown" -- not a wrong shape. One fuel
# parameter covers all five properties at once: the tree is finite and the two
# folds walk it in lockstep.
#
# WHY ONE RECURSIVE DEF AND NOT SEVERAL. The shape fold has to recurse two ways:
# into a child node, and across a list (Index's index list, Stack's operand
# list). Two functions means mutual recursion, and mutual recursion means calling
# a def declared below, which only @unsafe can do. So both cases live in one
# `Item`, one datatype, one recursive def: `One` is a node, `Many` is a list.
# Then every recursive call is a self-call on `fuel` and the whole file has no
# @unsafe in it at all.
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

def drop_n(ds: List<&2, Sdim>, n: Nat) -> List<&2, Sdim>:
  match ds:
    case Nil{}:
      Nil{}
    case _ <> r:
      match n:
        case 0n: r
        case 1n+p: drop_n(r, p)

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
  match a:
    case Nil{}: Nil{}
    case x <> xs:
      match b:
        case Nil{}: [x]
        case y <> ys: Shape.max_dim(x, y) <> zip_max(xs, ys)

def dim_of(d: Sdim) -> Nat:
  match d:
    case SN{v}: v
    case SS{x}: 0n      # a symbolic dim counts as 0 until it is folded

def prod(ds: List<&2, Sdim>) -> Nat:
  match ds:
    case Nil{}: 1n
    case d <> r: Nat.mul(dim_of(d), prod(r))

# The element count of a shape: the product of its dims.
def Sp.shape.index(pre: Maybe<&2, Shape>, bt: Maybe<&2, Shape>) -> Maybe<&2, Shape>:
  match pre:
    case Some{+p}:
      match bt:
        case Some{b}: Some{Shape.of(List.append(&2, Sdim, Shape.to_dims(p), drop_n(Shape.to_dims(b), Shape.ndim(p))))}
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

def fuel(n: Nat) -> Nat:
  # spend one unit of fuel: past the end, a fold reports None
  match n:
    case 0n: 0n
    case 1n+p: p

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

def Sp.shape.stack.at(head: Maybe<&2, Shape>, k: Nat) -> Maybe<&2, Shape>:
  on_shape(head, sh => Some{Shape.prepend(SN{k}, sh)})

def Sp.shape.reduce.at(m: Maybe<&2, Shape>, k: Nat) -> Maybe<&2, Shape>:
  on_shape(m, sh => Some{Shape.drop(sh, k)})

# The shape and dtype folds recurse two ways -- into a child node, and across a
# list, for Index's index list and Stack's operand list. Bend has no mutual
# recursion, so both are one `Item` and one def each.
type Item is Data:
  One{s: Sp}
  Many{xs: List<&2, Sp>}

# ===========================================================================
# Derived property: shape -- tinyspec's shape column, op by op.
#
# ONE recursive def, no @unsafe, fuel is explicit. Three facts about Bend 2's
# termination check drive the shape of this def, each measured against 2.0.34
# rather than read off the guide:
#
#   1. `fuel` is the FIRST parameter. The check reads arguments left to right
#      and stops at the first that is a strict subterm of its parameter, so the
#      shrinking one goes first.
#   2. `case 2n+p:` yields TWO independent strict subterms, which is how ONE arm
#      makes TWO decreasing calls -- the list fold needs the head and the tail.
#      `p` and `n` are not interchangeable with `+`: marking a binder reusable
#      stops it counting as a subterm and the check fails. Two calls, two
#      ordinary binders.
#   3. The checker only honours `2n+p` when a `1n+p` sibling is also present.
#      So odd fuel burns one unit and re-enters: fuel is counted in PAIRS, and
#      a caller with an odd budget is rounded down rather than told a lie.
#
# A caller supplies `2 * depth + 1`, where depth is the tree's height. Too
# little fuel reports None, which is the honest answer for "past this depth the
# property is unknown" -- never a wrong shape.
# ===========================================================================

def Sp.shape.item(fuel: Nat, i: Item) -> Maybe<&2, Shape>:
  match fuel:
    case 0n: None{}
    case 1n+p:
      # an odd budget cannot pay for a pair, so round down and re-enter
      Sp.shape.item(p, i)
    case 2n+p:
      match i:
        case Many{xs}:
          match xs:
            case Nil{}: Some{Shape.empty()}
            case x <> rest:
              Sp.shape.index(Sp.shape.item(n, One{x}), Sp.shape.item(p, Many{rest}))
        case One{s}:
          match s:
            # -- source ops
            case SpBuffer{size, dt, dev, addr}: Some{Shape.of([SN{size}])}
            case SpAlloc{size, dt, dev, addr}: Some{Shape.of([SN{size}])}
            case SpParam{size, dt, dev}: Some{Shape.of([SN{size}])}
            case SpConst{v, dt}: Some{Shape.empty()}    # "A scalar constant with shape ()"
            case SpBinary{size}: Some{Shape.of([SN{size}])}

            # -- movement ops: all but these pass src[0].shape through
            case SpPermute{t, order}: Sp.shape.item(n, One{t})
            case SpFlip{t, flags}: Sp.shape.item(n, One{t})
            case SpReshape{t, src, dst}: Some{Shape.of(dst)}
            case SpExpand{t, pre, total}: Some{Shape.of(total)}
            case SpPad{t, off, size}: Some{Shape.of(size)}
            case SpShrink{t, off, size}: Some{Shape.of(size)}
            case SpIndex{t, idx}: Sp.shape.item(n, Many{idx})
            case SpStack{ts}: Sp.shape.stack(n, ts)
            # Bitcast rescales the LAST dim by the itemsize ratio and Unshard
            # multiplies each named axis by its Range, so neither passes
            # through. TODO: both are stubs; see .agents/TODO.md.
            case SpBitcast{t, dt}: Sp.shape.item(n, One{t})
            case SpUnshard{t, ranges, axes}: Sp.shape.item(n, One{t})

            # -- reduce op: remove the first k axes
            case SpReduce{t, ranges, op, k}: Sp.shape.reduce(n, p, t, k)

            # -- load ops
            case SpLoad{buf, alt, gate}: Sp.shape.item(n, One{buf})
            case SpCopy{buf, dev}: Sp.shape.item(n, One{buf})

            # -- store op: "Output is void"
            case SpStore{buf, val, gate}: None{}

            # -- ordering ops
            case SpRange{bound}: Some{Shape.empty()}
            case SpEnd{body, ranges}: None{}
            case SpBackedge{body, rng, cond}: None{}
            case SpAfter{buf, deps}: Sp.shape.item(n, One{buf})
            case SpGroup{us}: None{}
            case SpSink{ss}: None{}
            case SpLinear{uops}: None{}

            # -- elementwise ops: all inputs same shape, output same shape
            case SpRecip{a}: Sp.shape.item(n, One{a})
            case SpTrunc{a}: Sp.shape.item(n, One{a})
            case SpCast{a, dt}: Sp.shape.item(n, One{a})
            case SpAdd{a, b}: Sp.shape.alu(n, p, a, b)
            case SpMul{a, b}: Sp.shape.alu(n, p, a, b)
            case SpMax{a, b}: Sp.shape.alu(n, p, a, b)
            case SpMod{a, b}: Sp.shape.alu(n, p, a, b)
            case SpIdiv{a, b}: Sp.shape.alu(n, p, a, b)
            case SpCmpLt{a, b}: Sp.shape.alu(n, p, a, b)
            case SpCmpNe{a, b}: Sp.shape.alu(n, p, a, b)
            case SpXor{a, b}: Sp.shape.alu(n, p, a, b)
            case SpOr{a, b}: Sp.shape.alu(n, p, a, b)
            case SpAnd{a, b}: Sp.shape.alu(n, p, a, b)
            case SpShr{a, b}: Sp.shape.alu(n, p, a, b)
            case SpShl{a, b}: Sp.shape.alu(n, p, a, b)
            # Where: the dtype column says src[1].dtype, so the shape follows `b`
            case SpWhere{q, a, b}: Sp.shape.alu(n, p, a, b)

            # -- marker ops: "identity on data"
            case SpContiguousBackward{a}: Sp.shape.item(n, One{a})
            case SpDetach{a}: Sp.shape.item(n, One{a})

            # -- Call: "A value Call is void"
            case SpCall{body, args}: None{}

            case SpInvalid{}: Some{Shape.empty()}

# Broadcast: right-align the two shapes and take the element-wise max.
def Sp.shape.alu(a: Nat, b: Nat, x: Sp, y: Sp) -> Maybe<&2, Shape>:
  dims_zip_max(Sp.shape.item(a, One{x}), Sp.shape.item(b, One{y}))

# Stack adds a LEADING axis of the operand count; an empty Stack has no shape.
def Sp.shape.stack(+fuel: Nat, +ts: List<&2, Sp>) -> Maybe<&2, Shape>:
  Sp.shape.stack.at(Sp.shape.item(fuel, Many{ts}), List.length(&2, Sp, ts))

# Reduce drops the first k axes of the operand's shape.
def Sp.shape.reduce(a: Nat, b: Nat, t: Sp, k: Nat) -> Maybe<&2, Shape>:
  Sp.shape.reduce.at(Sp.shape.item(a, One{t}), k)

# The public entry point. The caller supplies the depth bound; the arena knows
# the node count, and twice that is the honest upper bound on the height.
def Sp.shape(s: Sp, depth: Nat) -> Maybe<&2, Shape>:
  Sp.shape.item(Nat.add(Nat.mul(depth, 2n), 1n), One{s})

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
# Derived property: dtype -- tinyspec's dtype column, op by op. Same fuel
# discipline as the shape fold. Stack takes the head's dtype, which needs only
# one descent, so it fits the single-call shape of the list arm.
# ===========================================================================

def Sp.dtype.item(fuel: Nat, i: Item) -> Maybe<&2, Dt>:
  match fuel:
    case 0n: None{}
    case 1n+p: Sp.dtype.item(p, i)
    case 2n+p:
      match i:
        case Many{xs}:
          match xs:
            case Nil{}: None{}
            case x <> _:
              # "All shapes must match", so the head carries the result dtype
              Sp.dtype.item(n, One{x})
        case One{s}:
          match s:
            case SpBuffer{size, dt, dev, addr}: Some{dt}          # "from arg"
            case SpAlloc{size, dt, dev, addr}: Some{dt}
            case SpParam{size, dt, dev}: Some{dt}
            case SpConst{v, dt}: Some{dt}
            case SpBinary{size}: Some{uint8()}                    # "has dtype uint8"

            # -- movement ops: src[0].dtype
            case SpPermute{t, order}: Sp.dtype.item(n, One{t})
            case SpFlip{t, flags}: Sp.dtype.item(n, One{t})
            case SpReshape{t, src, dst}: Sp.dtype.item(n, One{t})
            case SpExpand{t, pre, total}: Sp.dtype.item(n, One{t})
            case SpPad{t, off, size}: Sp.dtype.item(n, One{t})
            case SpShrink{t, off, size}: Sp.dtype.item(n, One{t})
            case SpIndex{t, idx}: Sp.dtype.item(n, One{t})
            case SpStack{ts}: Sp.dtype.item(n, Many{ts})
            case SpBitcast{t, dt}: Some{dt}                       # "from arg"
            case SpUnshard{t, ranges, axes}: Sp.dtype.item(n, One{t})

            case SpReduce{t, ranges, op, k}: Sp.dtype.item(n, One{t})
            case SpLoad{buf, alt, gate}: Sp.dtype.item(n, One{buf})
            case SpCopy{buf, dev}: Sp.dtype.item(n, One{buf})
            case SpStore{buf, val, gate}: None{}                  # void

            case SpRange{bound}: Some{index()}                    # "index"
            case SpEnd{body, ranges}: None{}
            case SpBackedge{body, rng, cond}: None{}
            case SpAfter{buf, deps}: Sp.dtype.item(n, One{buf})
            case SpGroup{us}: None{}
            case SpSink{ss}: None{}
            case SpLinear{uops}: None{}

            case SpRecip{a}: Sp.dtype.item(n, One{a})
            case SpTrunc{a}: Sp.dtype.item(n, One{a})
            case SpCast{a, dt}: Some{dt}                           # "from arg"
            case SpAdd{a, b}: Sp.dtype.item(n, One{a})
            case SpMul{a, b}: Sp.dtype.item(n, One{a})
            case SpMax{a, b}: Sp.dtype.item(n, One{a})
            case SpMod{a, b}: Sp.dtype.item(n, One{a})
            case SpIdiv{a, b}: Sp.dtype.item(n, One{a})
            case SpCmpLt{a, b}: Some{boolean()}                   # bool
            case SpCmpNe{a, b}: Some{boolean()}
            case SpXor{a, b}: Sp.dtype.item(n, One{a})
            case SpOr{a, b}: Sp.dtype.item(n, One{a})
            case SpAnd{a, b}: Sp.dtype.item(n, One{a})
            case SpShr{a, b}: Sp.dtype.item(n, One{a})
            case SpShl{a, b}: Sp.dtype.item(n, One{a})
            case SpWhere{q, a, b}: Sp.dtype.item(n, One{b})       # src[1].dtype

            case SpContiguousBackward{a}: Sp.dtype.item(n, One{a})
            case SpDetach{a}: Sp.dtype.item(n, One{a})
            case SpCall{body, args}: None{}                        # void
            case SpInvalid{}: Some{boolean()}

def Sp.dtype(s: Sp, depth: Nat) -> Maybe<&2, Dt>:
  Sp.dtype.item(Nat.add(Nat.mul(depth, 2n), 1n), One{s})
