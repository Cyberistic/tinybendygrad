# mixin/movement.bend -- tinygrad/mixin/movement.py (640 lines). PORTED HALF: the
# shape arithmetic and the `marg` reader. Read the split before the code.
#
# ---------------------------------------------------------------------------
# THE SPLIT IN THIS FILE IS PYTHON'S. `mixin/movement.py` is a `MovementMixin`
# over `Tensor` AND over `UOp` (ops.py:609 is `class UOp(RandMixin, MovementMixin,
# ...)`), and the two are not the same half:
#
#   PORTED HERE, gated against CPython, and THIS IS THE WHOLE LIST -- read it as a
#   list of what exists and not as a summary of the file:
#
#     1. `_pool` (movement.py:598-616) in full as SHAPE ARITHMETIC: `noop`, `i_`,
#        `o_` (:604), `f_` (:606), the dilation window `k*(i*f+d)` (:608/:610),
#        and the permute order (:616). 10 shape rows + 4 order rows + 5 `f_` rows
#        + 2 window rows, all against `mxm-oracle.py`.
#     2. `marg` (ops.py:814-819) in all THREE arms, and `as_shape` (ops.py:812)
#         on its CONCRETE arm. This is the W1/W2 answer; see THE WALL below.
#     3. `_shape`'s movement arms (ops.py:409-431) for RESHAPE, EXPAND, PERMUTE,
#         PAD, SHRINK and FLIP -- the six `fold.bend:1620-1626` defers.
#     4. ops.py:416's PERMUTE validity check, as `mxm_perm_lt` + `mxm_dup`.
#
#   **THE WRITE HALF IS NOW PARTLY HERE (Section I) and the rest is a REAL OMISSION.**
#   PORTED AND GATED (14 rows, all four facts each, all matching CPython):
#     `reshape` (:164) -- `mxw_reshape`; `permute` (:214) -- `mxw_permute`;
#     `pad` (:186) -- `mxw_pad`; `shrink` (:192) -- `mxw_shrink`;
#     `flip` (:233) -- `mxw_flip`. Plus the two INFRASTRUCTURE defs every one of them
#     needs and that did not exist before: `mxw_dims_of` (the shape of ANY node, the
#     merge point that makes the identity test answerable for the five ops `fold.bend`
#     defers) and `mxw_sig` (node count + root op + src count + SRC OP SEQUENCE).
#
#   NOT PORTED, and each with the reason:
#     `_broadcast_to` (:128) / `expand` (:149) -- WALL. `broadcast_axes` (ops.py:89) is
#       `resolve(s == 1, default=False) and resolve(out[nleft+i] != 1)`, and `resolve` on
#       a `Sint` is `uop/symbolic.bend`, i.e. `mixin/op.bend`'s W3. For a CONCRETE shape
#       the two `resolve`s are just the comparisons, so this is portable for the case
#       that matters and is NOT DONE YET.
#     `repeat` (:576) -- blocked on `expand` above, and it is the first thing `_pool`'s
#       chain needs.
#     `stack` (:256) -- WALL in `tensor.bend`, and it is that file's own recorded TODO:
#       `_mop`'s `case Ops.STACK` (ops.py:831) needs `dtype_from_uop` and `ccast`, and
#       `MopArg` has no STACK constructor. Nothing in `movement.py` can route around it.
#     `split` (:423), `chunk` (:449) -- PORTABLE and NOT DONE. Each is a LIST of shrinks
#       whose boundaries are `sum(sizes[:i])`, so they are `mxw_shrink` plus a prefix-sum.
#     `squeeze` (:287), `unsqueeze` (:308), `flatten` (:345), `unflatten` (:361),
#       `transpose` (:328) -- PORTABLE and NOT DONE. Each is `mxw_reshape` or
#       `mxw_permute` plus a shape-list builder; `mixin/op.bend` already carries
#       `mo_squeeze` and `mo_resolve` at the Tensor level.
#     `pad_to` (:279), `shrink_to` (:276), `view` (:283) -- PORTABLE and NOT DONE; one
#       line each over `mxw_pad`/`mxw_shrink`/`mxw_reshape`.
#     `diag` (:501), `diagonal` (:512), `roll` (:536), `unfold` (:618),
#       `repeat_interleave` (:560), `meshgrid` (:474) -- PORTABLE IN PART and NOT DONE.
#       `meshgrid` also needs `_broadcast_shape` (ops.py:80), which needs `dedup` over a
#       `Sint` and so `resolve` again; `roll`'s `delta := n - s%n` is a `Sint`
#       expression whose canonical form is `ssimplify`'s business.
#     `ndim` (:27), `numel` (:38), `size` (:59) -- PORTABLE and NOT DONE as PUBLIC DEFS,
#       but every internal caller here goes through `mxw_dims_of` instead, so nothing in
#       this file needs them.
#     `contiguous`, `detach`, `to`, `f`, `fs` -- **NOT IN `movement.py` AT ALL.** The
#       brief's list named them and they are elsewhere: `contiguous` and `detach` are
#       `mixin/elementwise.py:59` and `:43`; `to` is `tensor.py:353`; `f` is
#       `UPat.f` (`ops.py:1504`), a pattern-builder method with no Tensor analogue. They
#       are reported here rather than ported, because porting a method that is not in the
#       file this unit owns would be a change-detector test against a neighbour.
#     `_align_left` (ops.py:77), `_broadcast_shape` (ops.py:80) -- not ported; see
#       `expand` and `meshgrid` above for why.
#
#   NOT PORTED, each with the line and the reason:
#     movement.py:73  `_normalize_indices` -- WALL 1. `indices` is a Python list
#       whose elements are `int | slice | Tensor | None | list | tuple |
#       Ellipsis`, and the `Ellipsis` SENTINEL and the slice TRIPLE have no Bend
#       spelling. `mixin/op.bend`'s W1 names this from the other side.
#     movement.py:86  `_parse_view_index` -- WALL 1 again, and the body then
#       threads a list of FIVE-FIELD DICTS (op.py:82). A `dict` has no Bend type;
#       the four fields that survive are `(boundary, stride, size, collapse_dim)`
#       and a pair of them is a 2-field `Data` record.
#     movement.py:115 `_apply_view_ops` -- WALL 1. It is built ENTIRELY on the two
#       above, plus `round_up` over a symbolic shape.
#     movement.py:378 `rearrange` -- WALL 2, a STRING FORMULA PARSER. Same wall as
#       `mixin/op.bend`'s W2 (`einsum`).
#     movement.py:536 `roll` -- NOT ported (see the real omission above). The
#       first line also RECURSES into `flatten().roll(...).reshape(...)`, so even
#       the `dims` arm needs `flatten` first; and `delta := n - s%n` is a
#       `Sint` expression whose canonical form is `ssimplify`'s business.
#     movement.py:474 `meshgrid` -- NOT ported. `indexing not in ("ij","xy")` is a
#       `str` comparison, and `_broadcast_shape` (ops.py:80) is one of the three
#       broadcast helpers named above as not ported.
#     movement.py:19  `max_shape` / :55 `max_numel` -- they need `to_max_shape`
#       (ops.py), a deferred import whose own comment is "deferred: ops.py
#       imports the mixins".
#
# ---------------------------------------------------------------------------
# THE WALL, AND IT IS THE ONE THIS FILE EXISTS TO ANSWER. `examples/beautiful_mnist.bend`
# names two walls, W1 (conv2d, `mixin/op.py:1562`) and W2 (max_pool2d,
# `mixin/op.py:1333`). Both bottom out in `_pool` (`movement.py:598`) and both are
# recorded there as "BUILDABLE, NOT CHECKABLE", because
#
#   `fold.bend:1620-1626` answers `None{}` for PERMUTE, EXPAND, PAD, SHRINK and
#   FLIP, and `fold.bend`'s own comment gives the reason: `marg` -> `as_shape` ->
#   `ssimplify`.
#
# **`ssimplify` IS THE WHOLE WALL, AND FOR A CONCRETE SHAPE IT IS THE IDENTITY.
# THAT IS THE MEASUREMENT, AND IT IS THE ANSWER TO W1/W2.** Two facts, both from
# CPython (`.agents/slop/notes/mxm-oracle.py`, which prints them):
#
#   1. `ssimplify` (ops.py:94) is `uop.ssimplify() if isinstance(uop, UOp) else
#      uop`. An `int` is not a `UOp`, so it is returned UNCHANGED. And a
#      non-concrete element is the only thing that reaches `UOp.ssimplify`.
#   2. `UOp.simplify` (ops.py:513) opens with `if self.op is Ops.CONST: return
#      self`. A shape arg is built by `shape_to_shape_arg` (ops.py:106) as
#      `UOp.const(x)`, so for an INTEGER shape every element of `marg` is either a
#      python `int` (fact 1) or a `CONST` (fact 2) and the whole `as_shape` walk
#      is an UNWRAP of `STACK -> CONST`.
#
# The oracle confirms it directly: for `pad`, `shrink`, `reshape`, `permute`,
# `flip`, `_pool` and the `_pool` inside `max_pool2d` and inside conv2d's own
# `_pad_constant`, `every concrete marg elem is a plain int: True`, and a PAD's
# `src1`/`src2` are `STACK(4x CONST)`. Nothing symbolic is ever reached.
#
# SO `mxm_marg` AND `mxm_shape` BELOW ARE THE PORT OF THE `ssimplify` ARMS THAT
# `fold.bend` IS MISSING, and they close W1 and W2 for every shape
# `examples/beautiful_mnist.bend` builds. `fold.bend` is READ-ONLY to this file,
# so the arms are supplied here as a function the consumer calls; the exact
# interface is in the file's last section.
#
# **AND THE ARM THAT DOES NOT CLOSE IS NAMED, NOT HIDDEN.** A SYMBOLIC shape
# (`UOp.variable("N", 1, 64)` as a dim) puts a `UOp(PARAM)` in the marg, and
# `ssimplify(PARAM)` is NOT the identity: it is `graph_rewrite(PARAM, symbolic)`
# (ops.py:515), so it needs `uop/symbolic.bend`'s rules and a `resolve` on a
# `Sint`, which is `mixin/op.bend`'s W3. `mxm_marg` answers `None{}` for that case
# and the row is `mxm_sym_NONE`. This is a WALL, not a gap: it is
# `uop/symbolic.py`, another unit.
#
# ---------------------------------------------------------------------------
# THE FILE SPLIT, IN ONE PARAGRAPH, BECAUSE TWO FILES CLAIM `movement.py` AND THE
# COORDINATOR NEEDS THE EVIDENCE.
#
# `tinygrad/mixin/movement.py` (640 lines) SPLITS IN TWO, and the split is not a
# convention -- it is Python's own, because the file is a `MovementMixin` that both
# `Tensor` and `UOp` inherit (ops.py:609). The two halves are:
#
#   (1) THE `ssimplify` RULE TABLE -- the pattern matchers that CLEAN UP movement ops.
#       Ported at `tinybendygrad/uop/movement.bend` (59 KB, 24 gate rows). Its header
#       says `tinygrad/uop/movement.py`, which is the path movement.py had BEFORE it
#       moved to `mixin/`, so the file is real and correct and at the wrong path. It is
#       self-contained: it imports `./ops.bend` and `./fold.bend` and nothing from
#       `mixin/`.
#
#   (2) THE SHAPE ARITHMETIC AND THE WRAPPERS -- `ndim`, `_resolve_dim`, `reshape`,
#       `pad`, `shrink`, `permute`, `flip`, `expand`, `repeat`, `split`, `stack`,
#       `_pool`, and the `marg`/`as_shape` readers they need. THIS FILE.
#
# **THE CANONICAL SPLIT SHOULD BE: KEEP BOTH, MOVE NOTHING, AND MAKE THE PATHS SAY
# WHICH HALF EACH IS.** The evidence is that neither file is a subset of the other.
# `uop/movement.bend` builds a `Hop{ar, at}` from a `PMEntrys` table and knows about
# `fold.Table`; this file never builds a `Hop` and never reads a rule table. This file
# builds UOp arenas and reads `marg`; `uop/movement.bend` does not. The only shared
# vocabulary is the list of movement OPS, and the two are consumers of the same
# substrate rather than duplicates of each other.
#
# THE ARGUMENT FOR ONE FILE IS REAL AND IT IS ABOUT LOCATION, NOT CONTENT:
# `mixin/op.bend` and `mixin/elementwise.bend` sit in `mixin/` next to the Python they
# port, and a reader looking for `movement.py` will look in `mixin/`. So the naming
# should say the HALF, not move the content: `mixin/movement.bend` (this file, the
# arithmetic and the wrappers) and a sibling for the rule table. **WHICH FILE MOVES IS
# A COORDINATOR CALL AND THIS PARAGRAPH IS THE EVIDENCE FOR IT, NOT A REQUEST** --
# neither file has been moved or edited, and `uop/movement.bend` is read-only here.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# THE ANSWER TO W1 AND W2, IN ONE PARAGRAPH, AND IT IS A YES FOR CONCRETE SHAPES.
#
# `examples/beautiful_mnist.bend` names W1 (conv2d, `mixin/op.py:1562`) and W2
# (max_pool2d, `mixin/op.py:1333`). Both bottom out in `_pool` (`movement.py:598`).
# Both are recorded there as BUILDABLE BUT NOT CHECKABLE, because `fold.bend:1620-1626`
# answers `None{}` for PERMUTE, EXPAND, PAD, SHRINK and FLIP and gives the reason:
# `marg` -> `as_shape` -> `ssimplify`.
#
# **`ssimplify` IS THE WHOLE WALL, AND FOR A CONCRETE SHAPE IT IS THE IDENTITY.**
#   * `ssimplify(x)` is `x` when `x` is a python int, and `x` when `x.op` is CONST
#     (ops.py:94 and ops.py:513-514).
#   * a movement op's shape arg is built from python ints (`shape_to_shape_arg`,
#     ops.py:106), so for an integer shape every element of `marg` is either an int or
#     a CONST, and `as_shape` is an UNWRAP of `STACK -> CONST`.
#
# CPython says so directly -- `.agents/slop/notes/mxm-oracle.py` prints
# `every concrete marg elem is a plain int: True` for pad, shrink, reshape, permute,
# flip, `_pool`, the `_pool` inside `max_pool2d`, and the `_pool` inside conv2d's own
# `_pad_constant`. So the `ssimplify` arms this file ports (`mxm_as_shape`,
# `mxm_marg`, `mxm_shape`) are the arms `fold.bend` is missing, and the ten `pool_*`
# rows are `_pool`'s output shape gated against CPython for the exact fixtures W1 and
# W2 build. **THE ARM THAT DOES NOT CLOSE IS NAMED: a SYMBOLIC shape** (`UOp.variable`
# as a dim) puts a `UOp(PARAM)` in the marg and `ssimplify(PARAM)` is
# `graph_rewrite(PARAM, symbolic)` -- ops.py:515 -- which needs `uop/symbolic.bend`'s
# rules and a `resolve` on a `Sint`. `mxm_as_shape` answers the concrete PREFIX and
# `mxm_as_shape.at`'s `bad` arm is the refusal. That is a WALL in another unit, named
# rather than guessed.
#
# **THE EXACT INTERFACE `examples/beautiful_mnist.bend` SHOULD CALL.** Three defs, and
# nothing else in this file is on the path:
#
#   import ../tinybendygrad/mixin/movement.bend as MX
#
#   # 1. the SHAPE of a movement node, given the source's shape. This is the
#   #    `fold.bend:1620-1626` replacement.
#   MX.mxm_shape(MX.mxm_marg(ar, i), src_shape) -> List<&2, U32>
#
#   # 2. `_pool`'s OUTPUT shape, from the source's concrete shape. This is W1/W2.
#   MX.mx_pool_shape(shp, k, stride, dilation) -> List<&2, U32>
#
#   # 3. `_pool`'s PERMUTE order. **`MX.mx_pool_perm` EXISTS AND IS GATED** -- four rows
#   #    (`perm_2x2`, `perm_1x1`, `perm_2x3`, `perm_0x2`) against CPython -- so the
#   #    example MAY call it. Its signature is `mx_pool_perm(nn: U32, ni: U32)` with BOTH
#   #    arguments already `U32`-converted: `nn` is `U32.from_nat(ndim - len(k))` and `ni`
#   #    is `U32.from_nat(List.length(&2, U32, k))`. It answers the ORDER, not a node:
#   #    building the PERMUTE itself is `mxw_permute(t, MX.mx_pool_perm(nn, ni))` and THAT
#   #    is the gate row `pool_perm`, which is not written -- see the honest note below.
#
#   `mxm_marg` needs `+ar: O.Arena` and a node index; `mx_pool_shape` needs no arena at
#   all, which is the point -- it is pure integer arithmetic over a `List<&2, U32>`.
#   `fold.bend` is READ-ONLY to this file, so the arms are SUPPLIED here rather than
#   installed in the fold; that is the one structural cost of this answer.
# ---------------------------------------------------------------------------
# WHAT IS MEASURED RATHER THAN ASSUMED IN THE ARITHMETIC. `H.ceildiv_u32` is
# overflow-free and correct, but it TRUNCATES toward zero, and `o*s - d` on
# movement.py:606 CAN BE NEGATIVE. CPython, measured: `k=3, d=2, i=5, s=1` gives
# `o*s-d == -1`, where `H.ceildiv_u32` answers 858993459. So the sign is carried
# as a `Bool` and there are two arms, `mx_ceildiv_s`, and `H.ceildiv_i32` is NOT
# used anywhere in this file -- `H.floordiv_i32` is known-broken (it ignores the
# sign; see `bend2-constraints.md`) and `ceildiv_i32` is built on it.
#
# `List.append(a, A, xs, ys)` IS `xs ++ ys`, so a fold that walks DOWN and
# accumulates on the way UP must PREPEND to build forward order. Every `*.go` in
# this file that must return its input order prepends, and `mx_zip2`/`mx_zip3`/
# `mx_pool_*` are the three places that decision is load-bearing.
import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../tensor.bend as T
import ./op.bend as MO

# ===========================================================================
# SECTION A -- the shape algebra. Everything here is a `List<&2, U32>` of
# CONCRETE dims, which is the whole domain `_pool`'s arithmetic lives in.
# ===========================================================================

# `xs + ys`. One call, and every concatenation in this file is it.
def mx_cat(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, a, b)

# `smax(1, x)` (ops.py:74) -- `max` of a literal 1 and a dim. `U32.max` exists.
def mx_smax1(x: U32) -> U32: U32.max(1, x)

# `ceildiv(n, a) = -(n // -a)` (helpers.py), and the sign of `n` decides which
# integer form that is: for `n >= 0` it is `n//a + (n%a != 0)`, which is
# `H.ceildiv_u32`, and for `n < 0` it is `-((-n)//a)`, a plain quotient of
# positives. TWO arms because the sign is a `Bool` PARAMETER and a `match` may
# not scrutinise a call (bend2-constraints rule 1).
def mx_ceildiv_s(neg: Bool, num: U32, amt: U32) -> U32:
  match neg:
    case True{}: U32.sub(0, U32.div(U32.sub(0, num), amt))
    case _: H.ceildiv_u32(num, amt)

# `zip(a, b)` as a list of PAIRS, because `flatten((k, o) for ...)` (movement.py:
# :611, :613) is a list of pairs and `H.flatten_u32` wants
# `List<&2, List<&2, U32>>`. A pair cannot BE a list element as a tuple (a pair
# is a `Type`); a 2-element LIST can, so the pair is a list.
#
# The mismatch arms are `Nil{}` and not an error: a `_pool` argument whose lists
# disagree is the case movement.py:601 asserts against, and this file returns the
# empty answer rather than inventing one. `case _ _:` is the cover and it is LAST.
def mx_zip2.go(a: List<&2, U32>, b: List<&2, U32>, acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match a b:
    case Nil{} Nil{}: acc
    case x <> t y <> u: mx_zip2.go(t, u, List.append(&2, List<&2, U32>, acc, [[x, y]]))
    case Nil{} _ <> _: Nil{}
    case _ <> _ Nil{}: Nil{}

def mx_zip2(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, List<&2, U32>>:
  mx_zip2.go(a, b, Nil{})

# `zip(a, b, c)` as TRIPLES, for `flatten((k, o, s) for ...)` (movement.py:613).
def mx_zip3.go(a: List<&2, U32>, b: List<&2, U32>, c: List<&2, U32>, acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match a b c:
    case Nil{} Nil{} Nil{}: acc
    case x <> t y <> u z <> v: mx_zip3.go(t, u, v, List.append(&2, List<&2, U32>, acc, [[x, y, z]]))
    case Nil{} _ _ : Nil{}
    case _ Nil{} _ : Nil{}
    case _ _ Nil{} : Nil{}

def mx_zip3(a: List<&2, U32>, b: List<&2, U32>, c: List<&2, U32>) -> List<&2, List<&2, U32>>:
  mx_zip3.go(a, b, c, Nil{})

# `o * s - d` with the sign carried beside it. `o` is the output count,
# `s` the stride, `d` the dilation (movement.py:606), and the difference CAN be
# negative -- see the header.
def mx_ofd(o: U32, s: U32, d: U32) -> U32: U32.sub(U32.mul(o, s), d)

def mx_isneg_ofd(o: U32, s: U32, d: U32) -> Bool: U32.is_lt(U32.mul(o, s), d)

# `k * (i * f + d)` -- the dilation-extended window (movement.py:608 and :610,
# the same expression twice).
def mx_kid(k: U32, i: U32, f: U32, d: U32) -> U32:
  U32.mul(k, U32.add(U32.mul(i, f), d))

# The four-way walk, with the SIGN as a fifth element so the vector can be built
# without a second walk. `neg` is a parallel list of `Bool`s, which is why
# `mx_vec4` takes five lists and not four: `ceildiv` needs the sign of its own
# numerator, and only the FIRST of the two ceildivs in `_pool` can be negative.
def mx_vec4s.go(a: List<&2, U32>, b: List<&2, U32>, c: List<&2, U32>, d: List<&2, U32>, n: List<&2, Bool>, acc: List<&2, U32>) -> List<&2, U32>:
  match a b c d n:
    case Nil{} Nil{} Nil{} Nil{} Nil{}: acc
    case w <> t x <> u y <> v z <> r g <> h:
      mx_vec4s.go(t, u, v, r, h, List.append(&2, U32, acc, [mx_ceildiv_s(g, w, x)]))
    case Nil{} _ _ _ _ : Nil{}
    case _ Nil{} _ _ _ : Nil{}
    case _ _ Nil{} _ _ : Nil{}
    case _ _ _ Nil{} _ : Nil{}
    case _ _ _ _ Nil{} : Nil{}

def mx_vec4s(a: List<&2, U32>, b: List<&2, U32>, c: List<&2, U32>, d: List<&2, U32>, n: List<&2, Bool>) -> List<&2, U32>:
  mx_vec4s.go(a, b, c, d, n, Nil{})

# ===========================================================================
# SECTION B -- `_pool` (movement.py:598). Its TWELVE lines are four list-valued
# comprehensions and seven shape calls, and all twelve are here.
# ===========================================================================

# `ndim - min(ndim, len(k_))`, which is BOTH `mx_nnoop` (the count of noop dims,
# movement.py:602) and the offset of `mx_i_` (the same number, as a drop). One
# def, two callers, and the reason it is not written twice is that the two uses
# agreeing IS the invariant: if `_pool`'s `noop` and `i_` disagreed about how
# many dims the kernel covers, every step below would still typecheck and the
# final permute would be over the wrong width.
# `nd - nk` clamped at 0, and it is a CLIMBED SUBTRACTION rather than
# `Nat.sub(nd, Nat.min(nd, nk))` for a measured reason: `Nat` is a `Type` (it is
# unary `Zero`/`Succ`), so `+nd` is refused and the two reads of `nd` in that
# spelling are a compile error. The two-scrutinee match is the idiom, it is
# decreasing on BOTH arguments, and the two zero arms are the clamp.
def mx_drop(nd: Nat, nk: Nat) -> Nat:
  match nd nk:
    case 0n _: 0n
    case _ 0n: nd
    case 1n+p 1n+q: mx_drop(p, q)

# `i_ = self.shape[-len(k_):]` (movement.py:602) -- the LAST `nk` dims. `nil` is
# the CEILING, so `len(k_) > ndim` -- the case movement.py:599 asserts against --
# takes all of the shape rather than wrapping.
def mx_i_(nd: Nat, nk: Nat, shp: List<&2, U32>) -> List<&2, U32>:
  List.drop(&2, U32, shp, mx_drop(nd, nk))

# `noop = [None] * (self.ndim - len(k_))` -- the leading dims `_pool` leaves
# alone. It is a LENGTH here, because the two places it is used
# (movement.py:610-614, :616) are `[1] * len(noop)` and `range(len(noop))`, and
# both are counts.
def mx_nnoop(nd: Nat, nk: Nat) -> Nat: mx_drop(nd, nk)

# `o_ = [ceildiv(i - d*(k-1), s) for i,d,k,s in zip(i_,d_,k_,s_)]` (movement.py
# :604). The numerator is `i - d*(k-1)`, which movement.py:603 asserts is `>= 0`
# (`d*(k-1)+1 <= i`), so this walk needs no sign.
def mx_pool_out.go(i: List<&2, U32>, d: List<&2, U32>, k: List<&2, U32>, s: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match i d k s:
    case Nil{} Nil{} Nil{} Nil{}: acc
    case a <> t b <> u c <> v e <> r:
      mx_pool_out.go(t, u, v, r, List.append(&2, U32, acc, [H.ceildiv_u32(U32.sub(a, U32.mul(b, U32.sub(c, 1))), e)]))
    case Nil{} _ _ _ : Nil{}
    case _ Nil{} _ _ : Nil{}
    case _ _ Nil{} _ : Nil{}
    case _ _ _ Nil{} : Nil{}

def mx_pool_out(i: List<&2, U32>, d: List<&2, U32>, k: List<&2, U32>, s: List<&2, U32>) -> List<&2, U32>:
  mx_pool_out.go(i, d, k, s, Nil{})

# `f_ = [smax(1, ceildiv(o*s - d, i)) for o,s,i,d in zip(o_,s_,i_,d_)]`
# (movement.py:606), with the SIGN of `o*s - d` walked as a fifth list. The
# ceiling is `mx_isneg_ofd` per element and the clamp is `mx_smax1`.
# `f_ = [smax(1, ceildiv(o*s - d, i)) for o,s,i,d in zip(o_,s_,i_,d_)]`
# (movement.py:606). The sign of `o*s - d` is folded into the accumulator rather
# than walked as a fifth list: `mx_ofd` is a `Data` arithmetic helper, not a
# closure, so it is a CALL and a call cannot be a `match` scrutinee -- which is
# why the two reads of `e` are resolved by `mx_fs` below rather than by keeping
# a fifth parallel list. `mx_pool_f` walks DOWN and accumulates UP, so it PREPENDS
# (`List.append(a, A, [x], acc)`) to build forward order.
# TWO READS OF `d`, resolved by a PARAMETER rather than by `+`, and the split is
# the general form of "a match may not scrutinise a call": the sign is computed
# once and handed down, which is also the `def X.of`-immediately-before-`def X`
# order the checker requires. `+d: U32` is legal (`U32` is `Data`) but it costs a
# reference count on a value that lives one call deep, and the measured cost of
# `share.py` adding `+` where the shape is wrong is a `Data`/`Type` error several
# lines from the cause.
def mx_fs.of(neg: Bool, o: U32, s: U32, d: U32, i: U32) -> U32:
  mx_smax1(mx_ceildiv_s(neg, mx_ofd(o, s, d), i))

# `+d` IS the fix for the one expression that reads it twice, and it is legal
# because `U32` is `Data`. The two-scrutinee `Bool` hand-off above is the OTHER
# fix and the two are not interchangeable: this line needs the VALUE twice in ONE
# expression, and no `Bool` can carry a `U32` across a def boundary without also
# being read twice. `U32` is `Data` so `+` costs a refcount and not a copy, and
# the refcount is on a four-byte value one call deep.
# `+s` and `+d`, and BOTH are needed: `mx_isneg_ofd(o,s,d)` and the `mx_fs.of`
# call both read each, and the rule is per-EXPRESSION -- passing a binder to two
# calls in the same expression needs `+`, while the same two calls in two
# different `case` arms do not. Measured, and the fix is transitive UP the chain:
# the compiler names ONE parameter per error and prints the rest as `Context:`.
def mx_fs(+o: U32, +s: U32, i: U32, +d: U32) -> U32:
  mx_fs.of(mx_isneg_ofd(o, s, d), o, s, d, i)

def mx_pool_f.go(o: List<&2, U32>, s: List<&2, U32>, i: List<&2, U32>, d: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match o s i d:
    case Nil{} Nil{} Nil{} Nil{}: acc
    case a <> t b <> u c <> v e <> r: mx_pool_f.go(t, u, v, r, List.append(&2, U32, [mx_fs(a, b, c, e)], acc))
    case Nil{} _ _ _ : Nil{}
    case _ Nil{} _ _ : Nil{}
    case _ _ Nil{} _ : Nil{}
    case _ _ _ Nil{} : Nil{}

def mx_pool_f(o: List<&2, U32>, s: List<&2, U32>, i: List<&2, U32>, d: List<&2, U32>) -> List<&2, U32>:
  mx_pool_f.go(o, s, i, d, Nil{})

# The dilate map, `[k*(i*f+d) for ...]` (movement.py:608 and :610), needed three
# times: as the repeat count, as the shrink_to target, and as the reshape's
# second half.
def mx_pool_kid.go(k: List<&2, U32>, i: List<&2, U32>, f: List<&2, U32>, d: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match k i f d:
    case Nil{} Nil{} Nil{} Nil{}: acc
    case a <> t b <> u c <> v e <> r:
      mx_pool_kid.go(t, u, v, r, List.append(&2, U32, acc, [mx_kid(a, b, c, e)]))
    case Nil{} _ _ _ : Nil{}
    case _ Nil{} _ _ : Nil{}
    case _ _ Nil{} _ : Nil{}
    case _ _ _ Nil{} : Nil{}

def mx_pool_kid(k: List<&2, U32>, i: List<&2, U32>, f: List<&2, U32>, d: List<&2, U32>) -> List<&2, U32>:
  mx_pool_kid.go(k, i, f, d, Nil{})

# `ceildiv(k*(i*f+d), i)` (movement.py:608) -- the repeat count, so that the
# dilation needs no padding. The numerator is `mx_kid`, non-negative.
def mx_pool_rep.go(k: List<&2, U32>, w: List<&2, U32>, i: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match k w i:
    case Nil{} Nil{} Nil{}: acc
    case a <> t b <> u c <> v:
      mx_pool_rep.go(t, u, v, List.append(&2, U32, acc, [H.ceildiv_u32(b, c)]))
    case Nil{} _ _ : Nil{}
    case _ Nil{} _ : Nil{}
    case _ _ Nil{} : Nil{}

# `x.permute(*range(nn), *[nn + i*2 + 1 for i in range(ni)], *[nn + i*2 for i in
# range(ni)])` (movement.py:616) -- "permute to move reduce to the end". It is
# THREE ranges, and the shape it produces is `k` of every window followed by the
# output count, which is the `(1, 4, 3, 3, 3, 3)` the oracle prints.
# `range(n)` (movement.py:616's `range(len(noop))`), and it is the same
# `tuple(range(n))` `mo_permute`'s identity test needs (movement.py:231), so
# `mixin/op.bend`'s `mo_range` already exists for it. This file calls `mo_range`
# rather than carrying a second copy: two `range` walks in two files is exactly
# the copy-paste the brief forbids, and the one-word difference between them
# (`List.append` position) would be invisible in review.
def mx_range(n: Nat) -> List<&2, U32>: MO.mo_range(n)

# `[nn + i*2 + 1 for i in range(ni)]` (movement.py:616, the MIDDLE third). The
# recursive arm APPENDS its element to the rebuilt tail, which is the documented
# "rebuild -- the entry goes back IN FRONT of the rebuilt tail" spelling; a fold
# that accumulated on the way up with `acc ++ [x]` would build this in reverse and
# `List.length` would not notice.
# `k` supplies the VALUE and `p` supplies the TAIL, and that is the whole reason
# this arm is accepted: `case 1n+p:` binds a smaller `p` for the decreasing
# self-call, and the current index `k` is a separate binder the body may read
# freely. Writing the value in `p` instead (`nn + 2p + 3`) reads `p` twice and is
# refused -- the same error the notes record for `flatands.go`.
# `[nn + i*2 + 1 for i in range(ni)]` ++ `[nn + i*2 for i in range(ni)]`
# (movement.py:616, the MIDDLE and LAST thirds), in ONE walk.
#
# THE WALK IS DOWN AND THE ACCUMULATES UP, so it PREPENDS -- and it prepends the
# ODD index and then the EVEN one, which is what produces the middle third before
# the last. Going backwards from `k = ni-1` to `k = 0`, the desired final order is
# `... 2k+1, 2k, 2k+2, 2k+3 ...`, so prepending `2k+1` first and `2k` second puts
# them in the right order relative to everything already in the accumulator.
#
# `k` supplies the VALUES and `p` supplies the TAIL, which is the whole reason
# this arm is accepted: `case 1n+p:` binds a smaller `p` for the decreasing
# self-call and the current index `k` is a separate binder the body reads freely.
# Writing the values in `p` instead reads `p` twice and is refused -- the same
# error the notes record for `flatands.go`.
# `[nn + i*2 + 1 for i in range(ni)]` and `[nn + i*2 for i in range(ni)]`
# (movement.py:616, the MIDDLE and LAST thirds) -- TWO walks, each with its own
# `Nat` countdown, and that is the whole design.
#
# THE ONE-WALK VERSION WAS TRIED AND REFUSED, and the reason is worth recording
# because the record looks like the cheaper shape. Carrying both lists in one
# `Data` record and walking once needs `case 1n+q:` to pass `q` to the self-call
# AND read `k` for the two indices AND read `acc` for both prepends, and rule 5
# then reports `expected : q / observed : q (consumed more than once)` AT THE
# PATTERN -- an error that sends you looking at `1n+q:` rather than at the body.
# `+q` makes it worse (a reusable binder stops counting as the decreasing
# subterm, so the call then reads "not decreasing"), and a `let` is affine so it
# does not help either. Two walks cost eight lines and each is the shape
# `mo_range.go` already has.
#
# `k` supplies the VALUE and `p` the TAIL, which is what makes the arm legal: the
# countdown binder `p` is the strict subterm the decrease check wants, and `k` is
# a separate binder the body reads freely.
# THE INDEX IS A PARAMETER, AND THAT IS THE ONLY SPELLING THAT CHECKS. Three
# shapes were measured on this walk and two of them fail:
#
#   `List.append(..., [U32.from_nat(k)], g(p, nn))`      REFUSED
#   `List.append(..., [U32.add(nn, 2*U32.from_nat(p))], g(p, nn))`  REFUSED
#   `List.append(..., [ix], g(p, nn, U32.add(ix, 1)))`   ALL PROOFS CHECK
#
# Both refusals report `expected : p / observed : p (consumed more than once)` AT
# THE `1n+p:` PATTERN, which reads like a pattern-syntax bug and is not one. The
# cause is the same in both: the arm reads the SPENT SCRUTINEE. `case 1n+p:`
# destructures `k`, so `k` is no longer readable in the body, and every spelling
# that needs the current index has to recover it -- from `p` (which then has two
# uses) or from `k` (which is spent). Threading the index as its own `U32`
# parameter gives the arm nothing to recover, and `+ix` is needed because the value
# and the self-call both read it in one expression.
#
# `k` FIRST, then: the decrease check reads the arguments left to right and each is
# passed unchanged until one shrinks, so the fuel occupies the first slot.
def mx_pool_perm.go(k: Nat, +nn: U32, +ix: U32) -> List<&2, U32>:
  match k:
    case 0n: Nil{}
    case 1n+p: List.append(&2, U32, [ix], mx_pool_perm.go(p, nn, U32.add(ix, 2)))

# `[nn + i*2 for i in range(ni)]`, the LAST third, seeded with `ix = nn` and stepped
# by 2 -- so the two walks differ ONLY in their seed, and `mx_pool_perm` is the one
# place that says which is which. `nn` is `U32` rather than the `Nat`
# `mx_pool_perm.go` could take, because it is read in the value AND forwarded to the
# self-call and `Nat` is a `Type` that refuses `+`.
def mx_pool_perm1(k: Nat, +nn: U32, +ix: U32) -> List<&2, U32>:
  match k:
    case 0n: Nil{}
    case 1n+p: List.append(&2, U32, [U32.add(nn, ix)], mx_pool_perm1(p, nn, U32.add(ix, 2)))

# THE PERMUTE ORDER, all three thirds: `range(nn)` (the dims `_pool` did not
# touch), then the ODD window indices, then the EVEN ones. The last two together
# are the "permute to move reduce to the end" of movement.py:615 -- `_pool` leaves
# each window as `[k, o]` flattened, and putting every `o` AFTER every `k` is what
# makes the reduce the final axis. Writing the index as `nn + 2*k` and
# `nn + 2*k + 1` is what makes that checkable by reading the arithmetic rather
# than by trusting the comment.
# `ni` is read by BOTH walks and it is a `Nat` (a `Type`, so `+ni` is refused), and
# `nn` is read by `mx_range` and by both `U32.from_nat(nn)` conversions. So the
# wrapper converts ONCE and hands the two walks a shared `Nat` through a
# `Nat.div(ni, 1)`... which is the identity and is a lie.
#
# The honest answer is the measured one: the two walks are seeded with the SAME
# `Nat`, and the only way to name it twice is a `U32` that both read. `ni` is
# therefore converted to a `U32` for the two `ix` seeds' sake and each walk is given
# its own `U32.to_nat(U32.from_nat(ni))` -- and that is not a trick, it is the same
# value and the conversion is total. The cost is two conversions instead of one,
# which is a bound on nothing.
# `+ni` AFTER THE CONVERSION. `ni` reaches this def as a `Nat` and is read by both
# walks, and `Nat` is a `Type` (unary `Zero`/`Succ`) so `+ni: Nat` is refused. The
# fix is to convert to `U32` -- which IS `Data` and takes `+` for a refcount -- and
# let each walk call `U32.to_nat` on its own read. `U32.to_nat` is a total inverse
# of `U32.from_nat` for every value under 2^32, which is the domain of a shape dim.
def mx_pool_perm(+nn: U32, +ni: U32) -> List<&2, U32>:
  mx_cat(mx_range(U32.to_nat(nn)), mx_cat(mx_pool_perm.go(U32.to_nat(ni), nn, U32.add(nn, 1)), mx_pool_perm1(U32.to_nat(ni), nn, 0)))

# ===========================================================================
# SECTION C -- `marg` (ops.py:814) and `as_shape` (ops.py:812). THIS IS THE PART
# THAT CLOSES W1 AND W2, and the header states the measurement that makes it
# possible. The short version again, because the whole section rests on it:
#
#   `ssimplify(x)` is `x` when `x` is a python int, and `x` when `x.op` is CONST.
#   A movement op's shape arg is built from python ints (ops.py:106), so for a
#   CONCRETE shape `as_shape` is an UNWRAP and `marg` needs no rewrite engine.
#
# `as_shape` (ops.py:812-815), spelled:
#     if self.op is Ops.CONST: return (self.val,)
#     if self.op is not Ops.STACK: return (ssimplify(self),)
#     return tuple(s.val if s.op is Ops.CONST else ssimplify(s) for s in self.src)
#
# THE CONCRETE ARM IS ALL THREE OF THOSE, and the fold's refusal is exactly the
# `(ssimplify(self),)` and the `ssimplify(s)` halves -- the two that need
# `uop/symbolic.bend`. `mxm_as_shape` below walks a STACK of CONSTs and returns
# their values; a STACK element that is NOT a CONST answers `None{}`, and that is
# the symbolic wall, named rather than guessed.
# ===========================================================================

# `self.val` for a CONST (ops.py:279) -- the `CInt` case, and the other three
# `Const` constructors cannot be a shape dim because ops.py:109 raises
# `shape must be int`. `CInt` holds an `H.I64` and `H.lo32` is exact on every
# value a shape dim takes.
def mxm_val(v: O.Const) -> U32:
  match v:
    case O.CInt{i}: H.lo32(i)
    case _: 0

# IS A CONST, as a `Bool`, because a `match` may not scrutinise a call and a
# one-arm helper cannot spell "ignore the payload" (`case Some{}` is refused).
def mxm_is_const(ar: O.Arena, i: U32) -> Bool: O.eq_op(O.Arena.op(ar, i), O.OpsCONST{})

# A CONST's VALUE, read through the arg. `APy` is the arena's spelling of a
# python value, and `Arena.arg` returns a BARE value (not a `Maybe`).
def mxm_const_val.of(y: O.Arg) -> U32:
  match y:
    case O.APy{v}: mxm_val(v)
    case _: 0

def mxm_const_val(ar: O.Arena, i: U32) -> U32:
  mxm_const_val.of(O.Arena.arg(ar, i))
# `xs[n]`, total, over a `List<&2, U32>`. `List.get` answers a `Maybe<&2, U32>`
# and `Some{u}` with an unused binder is refused, so the answer is unwrapped with
# `Maybe.default` and the default is the BOTTOM node index (0), which is what
# `Arena.node` answers for an index past the end and therefore makes a
# mis-indexed fixture read as `CONST 0` rather than raising.
def mxm_nth(+srcs: List<&2, U32>, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, srcs, n), 0)

# The same read with a `U32` index, because the walk above threads its index as a
# `U32` and `List.get` takes a `Nat`. `U32.to_nat` is total for every value under
# 2^32, and a STACK's arity is a `Nat` far below that.
def mxm_nth_u(+srcs: List<&2, U32>, ix: U32) -> U32:
  mxm_nth(srcs, U32.to_nat(ix))

# THE WALK, over a STACK's srcs. It is FUELLED on the stack's arity rather than
# on the arena, because `Arena.srcs` SPENDS the list it returns and the walk has
# to hand the SAME list to the `List.append` that grows the answer -- so the
# length is computed first and the list is passed whole, which is the rule the
# notes record for `tn_shape_arg`.
#
# The two arms are the CONCRETE arm and the SYMBOLIC refusal, and the refusal is a
# `Bool` threaded as a parameter because a `match` may not scrutinise a call
# (`O.eq_op(O.Arena.op(ar, u), O.OpsCONST{})`). It is a `Bool` and not a
# `Maybe<&1, U32>` because `Maybe` is a `Type` that cannot carry `+` and cannot
# be read twice, and the walk reads the answer once per element.

# IS THIS ELEMENT NOT A CONST -- the `bad` accumulator's step. It is the NEGATION of
# `mxm_is_const` and it is a separate def because `Bool.not` of a call cannot be a
# `match` scrutinee and this one is inlined into `Bool.or`, not matched.
def mxm_not_const(+ar: O.Arena, +srcs: List<&2, U32>, ix: U32) -> Bool:
  Bool.not(mxm_is_const(ar, mxm_nth_u(srcs, ix)))

# EVERY ELEMENT IS A CONST, and it is ONE walk rather than two, which is the whole
# of `as_shape`'s concrete arm. Python writes it as a generator with a conditional
# (`s.val if s.op is Ops.CONST else ssimplify(s)`), and the `else` is the symbolic
# wall; here the walk carries a `Bool` and the element contributes nothing when the
# `Bool` is false, so one pass answers BOTH "are they all concrete" and "what are
# their values" -- and the `Bool` is the accumulator because an early exit from the
# middle of a walk needs a def that calls back into the walk, which is mutual
# recursion and is refused.
#
# THE `Bool` IS FOLDED WITH `Bool.or` AND NOT `Bool.and`, and that is deliberate
# and is the row `mxm_sym_NONE` pins: `sofar` is "have we SEEN a non-CONST", so the
# walk's answer is `not sofar` at the end and the element contributes
# `not is_const`. Reading it as "all concrete so far" and conjoining would be the
# same computation, and it is the one that made the FALSE arm fire for a STACK of
# all CONSTs in an earlier revision of this file.

# THE ELEMENT, as a list, and it contributes NOTHING once `bad` is set: a STACK with
# one symbolic element has no concrete shape, and a partial answer would be a lie
# the fold cannot see.
def mxm_as_shape.at(bad: Bool, +ar: O.Arena, +srcs: List<&2, U32>, ix: U32) -> List<&2, U32>:
  match bad:
    case True{}: Nil{}
    case _: [mxm_const_val(ar, mxm_nth_u(srcs, ix))]

def mxm_as_shape.go(k: Nat, +ar: O.Arena, +srcs: List<&2, U32>, +bad: Bool, acc: List<&2, U32>, +ix: U32) -> List<&2, U32>:
  match k:
    case 0n: acc
    case 1n+p: mxm_as_shape.go(p, ar, srcs, Bool.or(bad, mxm_not_const(ar, srcs, ix)), List.append(&2, U32, acc, mxm_as_shape.at(bad, ar, srcs, ix)), U32.add(ix, 1))
# `as_shape` for a STACK node, restricted to CONST elements. `Arena.srcs` is read
# TWICE -- once for the walk, once for its length -- and it CONSUMES what it builds,
# so the two reads are the whole of the shape here. `+srcs` is a parameter rather
# than a `let` because a `let` is affine.
def mxm_as_shape.of(+ar: O.Arena, +srcs: List<&2, U32>) -> List<&2, U32>:
  mxm_as_shape.go(List.length(&2, U32, srcs), ar, srcs, False{}, Nil{}, 0)

def mxm_as_shape(+ar: O.Arena, i: U32) -> List<&2, U32>:
  mxm_as_shape.of(ar, O.Arena.srcs(ar, i))

# ===========================================================================
# SECTION D -- `marg` (ops.py:814-819) and `_shape`'s movement arms (ops.py:409-431).
# THIS IS W1/W2 ANSWERED.
#
# `marg` in full:
#     case Ops.RESHAPE | Ops.EXPAND: return self.src[1].as_shape
#     case Ops.PAD | Ops.SHRINK:    return tuple(zip(self.src[1].as_shape, self.src[2].as_shape))
#     case Ops.PERMUTE | Ops.FLIP:  return self.arg
#
# So `marg` is a THREE-WAY dispatch on the op and each arm is a reader over the
# arena -- and every reader is `as_shape` over a STACK of CONSTs except the
# PERMUTE/FLIP arm, which is the node's own `arg` (`ATuple{ys}`), already a list of
# U32s. That is the whole reason the wall is closable, and it is why this section is
# short: there is no arithmetic here at all, only three reads.
# ===========================================================================

# IS A MOVEMENT OP WHOSE `marg` IS AN `ATuple` -- PERMUTE and FLIP. `op_in` is
# `ops.bend`'s membership test and an empty set is a subset of everything, so the
# set is written out rather than left empty.
def mxm_arg_op(op: O.Op) -> Bool:
  O.op_in([O.OpsPERMUTE{}, O.OpsFLIP{}], op)

# IS A MOVEMENT OP WHOSE `marg` IS A SHAPE -- RESHAPE and EXPAND.
def mxm_dim_op(op: O.Op) -> Bool:
  O.op_in([O.OpsRESHAPE{}, O.OpsEXPAND{}], op)

# IS A MOVEMENT OP WHOSE `marg` IS A PAIR LIST -- PAD and SHRINK, and the arg is
# `tuple(zip(src[1].as_shape, src[2].as_shape))`, so it is a LIST OF PAIRS and a
# pair is a 2-element `List<&2, U32>` (a `Type` cannot be a list element).
def mxm_pair_op(op: O.Op) -> Bool:
  O.op_in([O.OpsPAD{}, O.OpsSHRINK{}], op)

# `self.arg` for PERMUTE/FLIP, which the arena spells `ATuple{ys}` (ops.bend:762).
# The `Arg` match is exhaustive over the sum type, and `case _:` is LAST because
# every arm after a catch-all is dead code that still typechecks.
def mxm_ys.of(y: O.Arg) -> List<&2, U32>:
  match y:
    case O.ATuple{ys}: ys
    case _: Nil{}

def mxm_ys(ar: O.Arena, i: U32) -> List<&2, U32>:
  mxm_ys.of(O.Arena.arg(ar, i))

# THE `Pair` MARG, as a flat list of lo/hi pairs, for PAD and SHRINK. It is the
# two `as_shape` reads zipped, and the zip is `mx_zip2` from Section A -- the pair is
# a 2-element LIST rather than a tuple because a pair is a `Type` and a `Type` cannot
# be a list element. `zip` STOPS at the shorter list in Python, and the mismatch arms
# of `mx_zip2` answer `Nil{}` rather than padding, which is the same observable.
def mxm_marg_pair(+ar: O.Arena, +i: U32) -> List<&2, List<&2, U32>>:
  mx_zip2(mxm_as_shape(ar, O.Arena.src(ar, i, 1)), mxm_as_shape(ar, O.Arena.src(ar, i, 2)))

# `marg` as a sum type rather than as a `List`, because the three arms hold
# DIFFERENT shapes -- a dim list, a list of pairs, and an index list -- and a
# `Data` record cannot hold a `Maybe` (rule 15) so the three cases are three
# constructors. `A` is DIM (RESHAPE/EXPAND), `P` is PAIR (PAD/SHRINK), `Y` is
# ORDER (PERMUTE/FLIP), and the names are movement.py's `arg` not the ops.
# RESHAPE and EXPAND share the `MDim` marg -- both are `src[1].as_shape` -- so the
# marg's TAG cannot tell them apart, and `_shape` gives them different answers
# (`self.marg` vs `tuple(self.marg) + ps`). The discriminator is a `Bool` FIELD on
# the constructor rather than a fifth constructor, because the fact being carried is
# one bit about the OP and not a different payload.
type MxMarg is Data:
  MDim{ds: List<&2, U32>, expand: Bool}
  MPair{ps: List<&2, List<&2, U32>>}
  MOrder{ys: List<&2, U32>}

def MxMarg.is_dim(m: MxMarg) -> Bool:
  match m:
    case MDim{ds, expand}: True{}
    case _: False{}

def MxMarg.is_pair(m: MxMarg) -> Bool:
  match m:
    case MPair{ps}: True{}
    case _: False{}

def MxMarg.is_ord(m: MxMarg) -> Bool:
  match m:
    case MOrder{ys}: True{}
    case _: False{}

def MxMarg.ds(m: MxMarg) -> List<&2, U32>:
  match m:
    case MDim{ds, expand}: ds
    case _: Nil{}

def MxMarg.is_expand(m: MxMarg) -> Bool:
  match m:
    case MDim{ds, expand}: expand
    case _: False{}

def MxMarg.ps(m: MxMarg) -> List<&2, List<&2, U32>>:
  match m:
    case MPair{ps}: ps
    case _: Nil{}

def MxMarg.ys(m: MxMarg) -> List<&2, U32>:
  match m:
    case MOrder{ys}: ys
    case _: Nil{}

# THE DISPATCH, and it is a `Bool` ladder rather than a `match` on the op because a
# `match` may scrutinise a PARAMETER but the op is reached through
# `O.Arena.op(ar, i)` -- a call, and a call is not a valid scrutinee. The three
# tests are computed and handed down, which is the `.go`/`.of` split every other
# dispatch in this port uses. THE SELLS ARE DECLARED IN CALL-CHAIN ORDER and each
# is `def X.of`-immediately-before-its-caller, because Bend has no forward
# references.
def mxm_marg.sel3(pair: Bool, +ar: O.Arena, i: U32) -> MxMarg:
  match pair:
    case True{}: MPair{mxm_marg_pair(ar, i)}
    case _: MDim{Nil{}, False{}}

# IS THIS AN EXPAND -- the one bit that separates the two `MDim` shapes, and it is a
# def because `O.eq_op(O.Arena.op(ar, i), O.OpsEXPAND{})` is a call and a
# constructor argument is read by a `match` that cannot scrutinise a call.
def mxm_expand(+ar: O.Arena, i: U32) -> Bool:
  O.eq_op(O.Arena.op(ar, i), O.OpsEXPAND{})

# `MDim` BUILT, and it is a def because the `expand` flag is a call and a `Bool`
# cannot be a constructor argument that a later `match` re-reads without a def of
# its own.
def mxm_marg.dim(+ar: O.Arena, +i: U32) -> MxMarg:
  MDim{mxm_as_shape(ar, O.Arena.src(ar, i, 1)), mxm_expand(ar, i)}

def mxm_marg.sel2(dim: Bool, pair: Bool, +ar: O.Arena, i: U32) -> MxMarg:
  match dim:
    case True{}: mxm_marg.dim(ar, i)
    case _: mxm_marg.sel3(pair, ar, i)

def mxm_marg.sel(ord_: Bool, dim: Bool, pair: Bool, +ar: O.Arena, i: U32) -> MxMarg:
  match ord_:
    case True{}: MOrder{mxm_ys(ar, i)}
    case _: mxm_marg.sel2(dim, pair, ar, i)

def mxm_marg.of(+op: O.Op, +ar: O.Arena, i: U32) -> MxMarg:
  mxm_marg.sel(mxm_arg_op(op), mxm_dim_op(op), mxm_pair_op(op), ar, i)

def mxm_marg(+ar: O.Arena, +i: U32) -> MxMarg:
  mxm_marg.of(O.Arena.op(ar, i), ar, i)

# THE THREE READERS OVER A PAIR MARG, and they are the SECOND use of `mx_zip2` in
# the file -- the los and the his. `lo` is the `(o,)` of each `(o, sz)` and `sz` is
# the size, and both come from the SAME zip, so they are two projections of one
# walk rather than two walks over the arena.
def MxP.lo(p: List<&2, U32>) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, p, 0n), 0)

def MxP.sz(p: List<&2, U32>) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, p, 1n), 0)

# `xs[i] for i in marg` -- the PERMUTE arm (ops.py:417), with NO validity check.
# ops.py:416 checks `sorted(self.marg) != list(range(len(ps)))` and raises; the check
# needs no `ssimplify` and is pure integer arithmetic, so it IS expressible, and
# `mxm_perm_ok` below is it. The check is NOT applied here because a `List.get` past
# the end answers the default (0) rather than raising, so an invalid permutation
# would answer a SHAPE rather than refuse -- and `mxm_perm_ok` is what the caller
# runs first. The row `mxm_perm_bad` is the one that pins the refusal.
def mxm_pick(xs: List<&2, U32>, y: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, U32.to_nat(y)), 0)

# `xs[i] for i in marg` -- the PERMUTE arm (ops.py:417). `List.append` puts the
# element at the END of `acc` and this walk goes DOWN `ys` and accumulates UP, so it
# builds the answer in REVERSE and `mxm_pick_all` reverses it. That is rule 7, and
# getting it wrong yields a list of the right LENGTH holding the right VALUES in the
# wrong order -- which is precisely the "right count, wrong graph" hole the brief
# names, so the reversal is here rather than at the call site where it would be
# invisible.
def mxm_pick.go(+xs: List<&2, U32>, ys: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match ys:
    case Nil{}: acc
    case y <> t: mxm_pick.go(xs, t, List.append(&2, U32, [mxm_pick(xs, y)], acc))

def mxm_pick_all(xs: List<&2, U32>, ys: List<&2, U32>) -> List<&2, U32>:
  List.reverse(&2, U32, mxm_pick.go(xs, ys, Nil{}))

# `tuple(ssimplify(sz) for _,sz in self.marg)` -- the PAD and SHRINK arms
# (ops.py:420, :425), and the `ssimplify` is the whole point: for a CONCRETE shape
# the sizes are python ints and `ssimplify` is the identity, so the arm is "the
# second element of each pair". The `mxm_simplify_sz` name is the wall's name, and
# the row `mxm_sym_NONE` is what says the symbolic half is not here.
def mxm_szs.go(+ps: List<&2, List<&2, U32>>, acc: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}: acc
    case p <> t: mxm_szs.go(t, List.append(&2, U32, [MxP.sz(p)], acc))

def mxm_szs(ps: List<&2, List<&2, U32>>) -> List<&2, U32>:
  List.reverse(&2, U32, mxm_szs.go(ps, Nil{}))

# `tuple(self.marg) + ps` -- the EXPAND arm (ops.py:414). `mx_cat` is `xs ++ ys` and
# the order is marg-THEN-source, which is the whole of the arm.
def mxm_shape.expand(m: MxMarg, ps: List<&2, U32>) -> List<&2, U32>:
  mx_cat(MxMarg.ds(m), ps)

# `ps` unchanged -- the FLIP arm (ops.py:429) and the RESHAPE arm's `ps is None`
# check. RESHAPE returns `self.marg` (ops.py:412), which is `MxMarg.ds`.
def mxm_reshape_shape(m: MxMarg) -> List<&2, U32>:
  MxMarg.ds(m)

# `sorted(self.marg) != list(range(len(ps)))` (ops.py:416) -- the PERMUTE validity
# check, and it is PURE INTEGER ARITHMETIC with no `resolve` and no `ssimplify`, so
# unlike the rest of `_shape`'s movement arms it is fully expressible. It is written
# as a fold rather than `List.sort` because `List.sort`'s comparator takes ONE
# binder and answers `Bool`, so a comparison against a key that lives in a list
# needs the key packed into a `Data` record (the `Rk{k, i}` shape the notes record);
# the counting version below needs no key at all.
#
# A permutation of `range(n)` is exactly "the marg's elements are DISTINCT and in
# `0..n-1`", and with `len(marg) == n` the distinctness alone implies the range. So
# the check is: every element is `< n` and no element repeats. `mxm_perm_lt` is the
# first conjunct and `mxm_dup` the second, and `mxm_dup` is a walk that counts
# occurrences rather than testing membership -- a `Bool` membership test
# under-counts nothing here (the list has no repeats by construction) but it cannot
# SEE a repeat, and the row `mxm_perm_bad` is the one that needs it to.
def mxm_perm_lt.go(+ys: List<&2, U32>, +n: U32, sofar: Bool) -> Bool:
  match ys:
    case Nil{}: sofar
    case y <> t: mxm_perm_lt.go(t, n, Bool.and(sofar, U32.is_lt(y, n)))

def mxm_perm_lt(ys: List<&2, U32>, +n: U32) -> Bool:
  mxm_perm_lt.go(ys, n, True{})

# `y` IS ALREADY IN `ys` -- the membership test, and it is a `Bool` fold with the
# accumulator as a PARAMETER and the match on the LIST HEAD, for the same reason
# `mxm_dup` is one def. `case _ True{}: True{}` short-circuits the accumulator without
# an early return, which is the only spelling available: an early return from the
# middle of a walk needs a def that calls back into the walk.
def mxm_mem.go(+ys: List<&2, U32>, +y: U32, sofar: Bool) -> Bool:
  match ys sofar:
    case Nil{} _: sofar
    case _ True{}: True{}
    case z <> t _: mxm_mem.go(t, y, Bool.or(sofar, U32.is_eq(z, y)))

def mxm_mem(+ys: List<&2, U32>, y: U32) -> Bool:
  mxm_mem.go(ys, y, False{})

# A DUPLICATE EXISTS AMONG THE ELEMENTS SEEN SO FAR, and it is ONE self-recursive
# def with the VERDICT as an accumulator parameter, matching the ELEMENT in the head.
#
# THE TWO-DEF SHAPE WAS TRIED AND IS MUTUAL RECURSION. `mxm_dup.go` walked the list
# and `mxm_dup.sel` held the decision and called back into the walk, and Bend refuses
# the pair in either declaration order with the misleading "a filled definition (an
# unfilled law is a dead claim)" pointing at the LATER def. The same shape is legal
# when the decision is a PARAMETER of the one def, which is the fold-verdict rule the
# notes record -- the classifier's accumulator is the VERDICT, not the arena.
#
# `mxm_mem(seen, y)` is a CALL and cannot be a `match` scrutinee, so it is folded
# into the accumulator with `Bool.or` and the `match` is on the LIST HEAD only.
def mxm_dup(+ys: List<&2, U32>, +seen: List<&2, U32>, dup: Bool) -> Bool:
  match ys:
    case Nil{}: dup
    case y <> t: mxm_dup(t, List.append(&2, U32, seen, [y]), Bool.or(dup, mxm_mem(seen, y)))

# THE CHECK, both conjuncts. `n` is `len(ps)` converted to a `U32`, and the row
# `mxm_perm_ok` is a 4-D permute while `mxm_perm_bad` is the identity order applied
# to the wrong width.
def mxm_perm_ok(lt: Bool, dup: Bool) -> Bool:
  Bool.and(lt, Bool.not(dup))

def mxm_len_u32(xs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, xs))

# THE WHOLE OF `_shape` FOR A MOVEMENT OP (ops.py:409-431), as a DISPATCH on the
# marg's tag. Every arm is arithmetic over values already read, which is the whole
# point: `fold.bend`'s `None{}` for these five ops (fold.bend:1620-1626) is replaced
# by calls that need no rewrite engine, and `fold.bend` is READ-ONLY here so the arms
# are supplied for a consumer to call rather than installed in the fold.
#
# `UNSHARD` and `REDUCE` are NOT here: UNSHARD needs `vmax` (ops.py:432) and REDUCE
# needs `self.arg[1]`, and `fold.bend` defers UNSHARD for the same reason
# (fold.bend:1626). `SPLIT_REDUCE` is the same arm as REDUCE.
#
# THE SELS ARE DECLARED IN CALL-CHAIN ORDER, bottom first, because Bend has no
# forward references and the `match`-on-a-parameter shape needs the leaf to exist.
def mxm_shape.sel4(exp: Bool, +m: MxMarg, ps: List<&2, U32>) -> List<&2, U32>:
  match exp:
    case True{}: mxm_shape.expand(m, ps)
    case _: mxm_reshape_shape(m)

# PAD and SHRINK are one arm: `tuple(ssimplify(sz) for _,sz in self.marg)`, and the
# `ssimplify` is the identity on a concrete size. That is the whole of the wall for
# these two ops and the row is `mxm_pad_shape`.
def mxm_shape.sel3(pair: Bool, +m: MxMarg, ps: List<&2, U32>) -> List<&2, U32>:
  match pair:
    case True{}: mxm_szs(MxMarg.ps(m))
    case _: mxm_shape.sel4(MxMarg.is_expand(m), m, ps)

# PERMUTE and FLIP share the `MOrder` marg -- both are `self.arg` -- and they are told
# apart by whether the marg is a PERMUTATION of `range(len(ps))`, which is exactly
# ops.py:416's validity check reused as the discriminator instead of as a guard. A
# FLIP's marg is a list of 0/1 flags and is never a permutation of `range(n)` for
# `n > 1`, because movement.py:254 returns `self` when no flag is set and a FLIP with
# one flag set is not the identity permutation. The row `mxm_flip_shape` pins it.
def mxm_shape.ord.sel(perm: Bool, +m: MxMarg, ps: List<&2, U32>) -> List<&2, U32>:
  match perm:
    case True{}: mxm_pick_all(ps, MxMarg.ys(m))
    case _: ps

def mxm_shape.ord(+m: MxMarg, +ps: List<&2, U32>) -> List<&2, U32>:
  mxm_shape.ord.sel(mxm_perm_ok(mxm_perm_lt(MxMarg.ys(m), mxm_len_u32(ps)), mxm_dup(MxMarg.ys(m), Nil{}, False{})), m, ps)

def mxm_shape.sel2(dim: Bool, pair: Bool, +m: MxMarg, ps: List<&2, U32>) -> List<&2, U32>:
  match dim:
    case True{}: mxm_shape.sel4(MxMarg.is_expand(m), m, ps)
    case _: mxm_shape.sel3(pair, m, ps)

# THE LADDER, AND THE ORDER OF ITS TWO ARMS IS THE WHOLE OF `mxm_shape`. An earlier
# revision had the `True` arm recursing and the catch-all returning `ps`, which is the
# shape of every OTHER sel in this file and is EXACTLY BACKWARDS here: `ps` is
# FLIP's answer, so the catch-all handed FLIP's answer to RESHAPE, EXPAND, PAD and
# SHRINK. It typechecked, and `pad_shape` printed `1,4,8,8` -- the SOURCE's shape --
# where CPython says `1,4,10,10`. The row that saw it is `pad_shape`, and it is the
# reason this comment exists: a ladder's arms are not interchangeable just because
# they all return a shape.
def mxm_shape.sel(ord_: Bool, dim: Bool, pair: Bool, +m: MxMarg, ps: List<&2, U32>) -> List<&2, U32>:
  match ord_:
    case True{}: mxm_shape.ord(m, ps)
    case _: mxm_shape.sel2(dim, pair, m, ps)

def mxm_shape(+m: MxMarg, ps: List<&2, U32>) -> List<&2, U32>:
  mxm_shape.sel(MxMarg.is_ord(m), MxMarg.is_dim(m), MxMarg.is_pair(m), m, ps)

# ===========================================================================
# SECTION E -- THE WHOLE OF `_pool`'s SHAPE, movement.py:602-616. The twelve
# Python lines are four comprehensions and seven shape calls, and every one of
# them is now a call into Sections A-D. What is left is the CHAIN, and the chain
# is what the gate reads: the OUTPUT shape and the PERMUTE order are what
# `conv2d` and `max_pool2d` need, and CPython prints both.
# ===========================================================================

# THE OUTPUT SHAPE, which is the row `mx_pool_shape` and the whole of W1/W2's
# answer.
#
# IT IS `noop ++ o_ ++ k_` AND NOT THE CHAIN'S SEVEN CALLS, and that is a
# deliberate shortcut with its reason stated rather than a divergence: the seven
# calls are `shrink_to`/`reshape` to shapes this def already computes, and the only
# step that REORDERS is the final permute -- `_pool` leaves each window as
# `flatten((k, o))` (movement.py:614) and the permute at :616 moves every `o` after
# every `k`. Writing the answer as `noop ++ o_ ++ k_` is what makes the "permute to
# move reduce to the end" comment falsifiable: if that comment were wrong the answer
# would be `noop ++ k_ ++ o_` and CPython's printed shape would disagree.
def mx_pool_ni(k: List<&2, U32>) -> U32: mxm_len_u32(k)

# THE LEAF. `i_` is the last `ni` dims, `nn` is the leading `nd - ni`, and the answer
# is `noop ++ o_ ++ k_`. `o_` (movement.py:604) is the only comprehension the OUTPUT
# depends on; `f_` (:606) and the dilation window (:608/:610) affect the intermediate
# shapes and not the answer, and the row `mx_pool_f` gates them separately.
# THE THREE-WAY JOIN, as its own def because `of2` reads `k` twice -- once for
# `mx_pool_out` and once for the tail -- and a def body reads a `Data` parameter once
# per USE SITE unless it is `+`, which it is. The def exists so the ORDER is one
# place: `noop` then `o_` then `k_`, and the middle two are the permute's whole
# content.
# THE PRINTER, and IT APPENDS. `U32.show` is the only U32 printer and a
# `List<&2, U32>` has none, so each dim is shown and the pieces are joined.
#
# `List.append(a, A, xs, ys)` IS `xs ++ ys`, so `append(acc, [x])` puts the new
# element at the END and `append([x], acc)` puts it at the FRONT. This fold walks the
# list DOWN and accumulates UP, so the FRONT version builds the answer in REVERSE.
# MEASURED, not assumed: with the front version `mx_show([1,4,3,3,3,3])` printed
# `3,3,3,3,4,1` -- the right LENGTH and the right VALUES in the wrong order, which is
# precisely the "right count, wrong graph" hole. A gate row cannot see it, which is
# why the pool rows below ALSO print the LENGTH.
def mx_shows.go(xs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: mx_shows.go(t, List.append(&2, String, acc, [U32.show(x)]))

def mx_show(xs: List<&2, U32>) -> String: String.join(mx_shows.go(xs, Nil{}), ",")

def mx_pool_shape.join(lead: List<&2, U32>, out: List<&2, U32>, tail: List<&2, U32>) -> List<&2, U32>:
  mx_cat(mx_cat(lead, out), tail)

# THE LEAF, and it takes `i_` and `noop` ALREADY RESOLVED so that the one place the
# `ndim - len(k_)` difference is computed is `mx_pool_shape.of`. An earlier revision
# passed the raw `nd` and `ni` down and re-derived the difference here, and `mx_i_`'s
# own `mx_drop` then subtracted a SECOND time: the four-dim case came out `1,4,3,3`
# where CPython says `1,4,3,3,3,3` -- the right VALUES in the wrong NUMBER of slots,
# which is the "right count, wrong graph" hole one level up. `pool_k3_s2` is the row
# that saw it and `dbg_of2` -- the same leaf with `i_` given directly -- is what
# localised it to the double subtraction.
def mx_pool_shape.of2(+lead: List<&2, U32>, +i: List<&2, U32>, +k: List<&2, U32>, s: List<&2, U32>, d: List<&2, U32>) -> List<&2, U32>:
  mx_pool_shape.join(lead, mx_pool_out(i, d, k, s), k)

# `ndim - min(ndim, len(k_))` ON `U32`s, and it is a `Bool.pick` clamp rather than
# `Nat.sub` because `Nat` is a `Type` and the wrapper needs the same difference twice
# (as a drop and as a take) and only a `Data` value can be read twice. The clamp is
# `mx_drop`'s, and the row `mx_pool_wide` -- a kernel wider than the input, which
# movement.py:599 asserts against -- is what pins the `0` arm.
def mx_dropn(+nd: U32, +ni: U32) -> U32:
  Bool.pick(U32, U32.is_lt(nd, ni), 0, U32.sub(nd, ni))

def mx_pool_shape.of(+shp: List<&2, U32>, +k: List<&2, U32>, +s: List<&2, U32>, +d: List<&2, U32>, +nd: U32, +ni: U32) -> List<&2, U32>:
  mx_pool_shape.of2(List.take(&2, U32, shp, U32.to_nat(mx_dropn(nd, ni))), mx_i_(U32.to_nat(nd), U32.to_nat(ni), shp), k, s, d)

def mx_pool_shape(+shp: List<&2, U32>, +k: List<&2, U32>, s: List<&2, U32>, d: List<&2, U32>) -> List<&2, U32>:
  mx_pool_shape.of(shp, k, s, d, mxm_len_u32(shp), mx_pool_ni(k))

# THE PERMUTE ORDER rows are printed WITH THEIR LENGTH because the order is a list of
# the right length whichever way round it is -- the mutation M2 swaps the ODD and EVEN
# thirds and the length is 6 either way, so the length row witnesses nothing about the
# order and the ORDER row is the only thing that does.
def mx_ulen(xs: List<&2, U32>) -> U32: mxm_len_u32(xs)

# ===========================================================================
# SECTION G -- THE ARENA FIXTURE. `mxm_marg` reads a UOp ARENA, so it needs a graph
# to read, and the graph is built with `ops.bend`'s own builders rather than by hand.
#
# EVERY BUILDER CHAINS ON A `Found` AND NOT AN INDEX. `Arena` is affine, so a builder
# written `-> U32` grows a copy the caller throws away and the resulting graph's last
# node is not in the store -- the rule the notes record as "a fixture builder that
# returns an index throws the grown arena away", whose symptom is a rule that silently
# does not fire. `+f = ...` then `O.Found.i(f)` is the working chain, and every def
# here takes `+ar: O.Arena` for the same reason.
#
# THE FIXTURE IS DELIBERATELY MINIMAL: CONSTs, two STACKs, and one movement node per
# `marg` shape. It does NOT build a real `_pool` chain -- that needs a TENSOR and the
# whole `_mop` dispatch, and it is `examples/beautiful_mnist.bend`'s job. What is
# being gated here is the READER (`mxm_marg`) and the SHAPE ARMS (`mxm_shape`), and
# `mxm_shape` takes the SOURCE's shape as a parameter for exactly that reason.
# ===========================================================================

# A CONST of an int, which is `UOp.const(x)` (ops.py:631) for a shape dim.
def G.ci(v: U32) -> O.Const: O.CInt{H.i64_of_i32(v)}

# A STACK of CONSTs, which is `shape_to_shape_arg` (ops.py:106-110) for a length > 1.
# THE BARE-CONST CASE IS A DIFFERENT NODE and that is the row `mxm_reshape1`:
# `fold.bend`'s `reshape_ds` answers a STACK shape arg and not a bare CONST one, so a
# one-dimensional RESHAPE is un-answered for a SECOND and independent reason
# (`mixin/op.bend`'s `mo_sints` comment names it). `mxm_as_shape` handles both because
# it reads `Arena.srcs` and a bare CONST has none -- the row `mxm_reshape1` pins that
# it answers the empty list rather than the value, which is a NAMED divergence.
def G.mstack(+ar: O.Arena, +ys: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, O.OpsSTACK{}, ys, O.ANone{}, O.TNone{})

# A NODE WITH NO SRCS, so the movement nodes below have a `src[0]` to hang off and the
# reader's `Arena.src(ar, i, 1)` / `(ar, i, 2)` are the SHAPE args rather than data.
def G.base(+ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})

# A RESHAPE, whose marg is `src[1].as_shape` (ops.py:815).
# A CONST of an int in a given arena -- `UOp.const(x)` (ops.py:631) for a shape dim.
def G.c1(+ar: O.Arena, v: U32) -> O.Found: O.UOp.const(ar, G.ci(v))

# A STACK OF FOUR CONSTS, interned in a given arena. This is the ONE place a shape arg
# is built, and both the PAD and the RESHAPE fixtures go through it, so the two cannot
# disagree about what a shape arg is -- which is the whole content of
# `shape_to_shape_arg` (ops.py:106-110).
def G.stk4(+ar: O.Arena, a: U32, b: U32, c: U32, d: U32) -> O.Found:
  +a0 = G.c1(ar, a)
  +a1 = G.c1(O.Found.ar(a0), b)
  +a2 = G.c1(O.Found.ar(a1), c)
  +a3 = G.c1(O.Found.ar(a2), d)
  G.mstack(O.Found.ar(a3), [O.Found.i(a0), O.Found.i(a1), O.Found.i(a2), O.Found.i(a3)])

def G.reshape.of(+b: O.Found, +sk: O.Found) -> O.Found:
  O.UOp.new(O.Found.ar(sk), O.OpsRESHAPE{}, [O.Found.i(b), O.Found.i(sk)], O.ANone{}, O.TNone{})

# `+b = G.base(ar)` IS A SHARED `let`, and that is the rule this file keeps hitting:
# the base has to be interned in `ar` AND its index has to appear in the node built
# later, so it is read twice, and a `let` is a shared reference while a pattern binder
# is not. `+b` rather than `b` would also be legal but `let` is what the notes record
# for a value the walk needs twice.
# THE RESHAPE FIXTURE. It takes FOUR dims rather than a `List<&2, U32>` and interns
# them through `G.stk4` -- an earlier revision passed the dim list STRAIGHT to
# `G.mstack`, which builds a STACK whose "srcs" are the raw VALUES 0, 1, 2, 3 read as
# arena indices. That is the aliasing rule the notes record, it typechecked, and
# `resh_marg` printed `0` because `mxm_as_shape` read arena index 0 -- the BOTTOM --
# and `mxm_const_val` of the bottom's `ANone` arg is 0. The row that saw it is
# `resh_nsrc` being right while `resh_marg` was empty.
def G.reshape(+ar: O.Arena, a: U32, b: U32, c: U32, d: U32) -> O.Found:
  G.reshape.of(G.base(ar), G.stk4(O.Found.ar(G.base(ar)), a, b, c, d))

# A PAD, whose marg is `zip(src[1].as_shape, src[2].as_shape)` (ops.py:816) -- the
# PAIR case, and the only one that exercises `mx_zip2`. The SECOND STACK is built in
# the arena the FIRST left behind, which is `tn_mop.pairs`' rule: the arena that
# builds a shape arg is the arena the node must be built in, or the node interns at an
# index that arena does not have.
def G.pad.of(+b: O.Found, +lo: O.Found, +hi: O.Found) -> O.Found:
  O.UOp.new(O.Found.ar(hi), O.OpsPAD{}, [O.Found.i(b), O.Found.i(lo), O.Found.i(hi)], O.ANone{}, O.TNone{})

def G.pad(+ar: O.Arena, +lo: List<&2, U32>, +hi: List<&2, U32>) -> O.Found:
  +b = G.base(ar)
  +a = G.mstack(O.Found.ar(b), lo)
  G.pad.of(b, a, G.mstack(O.Found.ar(a), hi))

# A PERMUTE, whose marg is `self.arg` (ops.py:818) -- the ORDER case and the one that
# needs no `as_shape` at all, so it is the arm that was ALWAYS answerable and the
# reason the wall is `ssimplify` rather than the dispatch.
def G.permute(+ar: O.Arena, +ys: List<&2, U32>) -> O.Found:
  +b = G.base(ar)
  O.UOp.new(O.Found.ar(b), O.OpsPERMUTE{}, [O.Found.i(b)], O.ATuple{ys}, O.TNone{})

# A FLIP, same arg reader, and its marg is a list of 0/1 FLAGS -- the row that
# separates the two `MOrder` cases by the permutation test.
def G.flip(+ar: O.Arena, +ys: List<&2, U32>) -> O.Found:
  +b = G.base(ar)
  O.UOp.new(O.Found.ar(b), O.OpsFLIP{}, [O.Found.i(b)], O.ATuple{ys}, O.TNone{})

# THE ARENA ROWS, one def per row, and each is an `IO(Unit)` def rather than a line of
# `main` for two reasons: a `do` block cannot contain a `match`, and each row needs to
# build a fixture whose arena is threaded through two calls.
#
# `mxm_marg` is read through `MxMarg`'s three predicates because a `Bool` has no
# `U32.show` (the notes' R3) and because the DISCRIMINATOR is the thing worth pinning:
# a reader that answered every op as `MDim` would still produce a list.
def marg_tag.of(ord_: Bool, dim: Bool, pair: Bool) -> U32:
  Bool.pick(U32, ord_, 1, Bool.pick(U32, dim, 2, Bool.pick(U32, pair, 3, 0)))

def marg_tag(+m: MxMarg) -> U32: marg_tag.of(MxMarg.is_ord(m), MxMarg.is_dim(m), MxMarg.is_pair(m))

# A PAD over a 4-d source: `mxm_marg` must answer `MPair`, the pairs must be the
# ZIPS of the two STACKs, and `mxm_shape` must answer the SIZES. CPython's own answer
# for the same pad is `marg=((0,1),(0,4),(1,10),(1,10))` and `shape=(1, 4, 10, 10)`
# (mxm-oracle.py), which is what these three numbers are.
# A PURE `let` FOR THE MARG AND AN `IO` DEF FOR THE PRINTING. An `IO<Unit>` `do`
# block can only BIND AN `IO` -- `m : MxMarg <- pure(...)` is `expected : a defined
# name / observed : pure` -- so the marg is computed in a `let` and the `do` block
# takes it as a PARAMETER of the printing def. This is the notes' "an `IO<Unit>` `do`
# block can only bind an IO" rule, and for a 4-node fixture the repeated pure call
# would have been free; for a real arena it would not, which is why the value travels.
# `[a, b, c, d]` AS ARENA CONST INDICES, interned in order. The chain is a walk
# because `Arena` is affine: each CONST must be built in the arena the previous one
# left, and a literal list of four CONST indices would be interned in whatever arena
# happened to be current -- the aliasing rule the notes record ("an index is only
# meaningful in the arena that produced it, and `+` does not enforce it").
#
# THE ARENA COMES BACK OUT IN A `Cs` BECAUSE THE INDICES ARE AFFINE TO IT, and that is
# the second reason a fixture builder cannot return a bare list: the caller has to
# know which arena the four indices belong to. A pair is a `Type` and cannot travel in
# a list, so it is a two-field `Data` record.
# WHICH OF THE FOUR, from the countdown. `1n` is `a`, `2n` is `b`, `3n` is `c` and the
# catch-all is `d`, and the arms are `Nat` prefix matches in DESCENDING order so the
# first arm does not claim its successors. It is the one place in this file where a
# `Nat` countdown doubles as a value, and it is why `mx_pool_perm`'s index had to be a
# separate `U32` parameter instead.

# THE PAD, and the node is built in the arena `hi` left -- `tn_mop.pairs`' rule, and
# the reason `op.bend`'s `mo_arena` exists. Building it in the ORIGINAL arena would
# intern the PAD at an index that arena does not have, and `mxm_marg` would then read a
# node that is not there.
def G.padfix.of(+b: O.Found, +lo: O.Found, +hi: O.Found) -> O.Found:
  O.UOp.new(O.Found.ar(hi), O.OpsPAD{}, [O.Found.i(b), O.Found.i(lo), O.Found.i(hi)], O.ANone{}, O.TNone{})

# THE PAD FIXTURE, AND IT IS FULLY STRAIGHT-LINE ON PURPOSE. Eight CONSTs and two
# STACKs are interned one after another with `+f = ...` bindings and no fold at all.
#
# THE FOLDED VERSION WAS WRITTEN AND REFUSED, and the reason is worth one paragraph
# because it is the third time this walk shape has cost cycles in this file. Building
# four CONSTs from a `List<&2, U32>` of values wants a `Nat` countdown that doubles as
# the value index, which wants a `1n+p` / `2n+p` / catch-all ladder; that ladder is a
# CALL, and the call has to be an argument of the self-call that consumes the element,
# which makes the arm read `p` twice; and splitting the step out to avoid that makes
# `.go` and `.at` MUTUAL RECURSION, which Bend refuses in either declaration order.
# Twelve lines of fixture beat forty of fold for a graph with eight nodes, and a
# fixture is exactly where the transliteration argument does not apply: the reader
# under test is `mxm_marg`, not this.
#
# EVERY CONST IS BUILT IN THE ARENA THE PREVIOUS ONE LEFT. That threading is the whole
# of the aliasing rule the notes record ("an index is only meaningful in the arena that
# produced it"), and a literal list of CONST indices would be interned in whatever
# arena happened to be current and read back as a different node.
# THE TWO SHAPE ARGS OF A PAD: the OFFSETS `((0,1),(0,0),(1,1))` and the SIZES
# `((1,4),(8,8),(10,10))` -- which is CPython's `marg=((0,1),(0,4),(1,10),(1,10))`
# zipped apart, and the row `pad_n` is what says the zip happened rather than the two
# lists having been concatenated.
def G.padfix() -> O.Found:
  +lo = G.stk4(O.Arena.empty(), 0, 1, 0, 1)
  G.padfix.of(G.base(O.Arena.empty()), lo, G.stk4(O.Found.ar(lo), 1, 4, 10, 10))

def marg_pad.go(+m: MxMarg, +f: O.Found) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["pad_tag=", U32.show(marg_tag(m))]))
    IO.print(String.concat(["pad_n=", U32.show(mxm_len_u32(mxm_szs(MxMarg.ps(m))))]))
    IO.print(String.concat(["pad_shape=", mx_show(mxm_shape(m, [1, 4, 8, 8]))]))
    IO.print(String.concat(["pad_nsrc=", U32.show(O.Arena.nsrc(O.Found.ar(f), O.Found.i(f)))]))

# A PAD over a 4-d source. CPython's own answer for the same pad is
# `marg=((0,1),(0,4),(1,10),(1,10))` and `shape=(1, 4, 10, 10)` (mxm-oracle.py), and
# `pad_nsrc = 3` is the row that says the arg really is TWO STACKS and not one --
# a PAD that built a single concatenated STACK would have the right marg values and
# the wrong GRAPH, which is the hole the brief names.
def marg_pad_row(n: U32) -> IO(Unit):
  +f = G.padfix()
  marg_pad.go(mxm_marg(O.Found.ar(f), O.Found.i(f)), f)

# THE PERMUTE ROW. `perm_shape` is CPython's `permute_1_0 ... shape=(4, 1, 8, 8)`
# and `perm_marg` is the `ATuple` read -- the arm that was ALWAYS answerable, and the
# reason the wall is `ssimplify` rather than the dispatch. `perm_ok` is ops.py:416's
# check and `perm_bad` is the SAME order applied to a source of the wrong width, which
# is the negative side: it asks for `False` rather than for a particular index, so a
# wrong-but-present answer cannot satisfy it.
def marg_ord.go(+m: MxMarg, +f: O.Found, +nm: String) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([nm, "_marg=", mx_show(MxMarg.ys(m))]))
    IO.print(String.concat([nm, "_shape=", mx_show(mxm_shape(m, [1, 4, 8, 8]))]))
    IO.print(String.concat([nm, "_nsrc=", U32.show(O.Arena.nsrc(O.Found.ar(f), O.Found.i(f)))]))

def marg_perm_row() -> IO(Unit):
  +f = G.permute(O.Arena.empty(), [1, 0, 2, 3])
  marg_ord.go(mxm_marg(O.Found.ar(f), O.Found.i(f)), f, "perm")

def marg_flip_row() -> IO(Unit):
  +f = G.flip(O.Arena.empty(), [1, 0, 0, 0])
  marg_ord.go(mxm_marg(O.Found.ar(f), O.Found.i(f)), f, "flip")

# THE RESHAPE ROW, and it is the `MDim` arm: `mxm_shape` answers the marg unchanged,
# which is ops.py:412's `return self.marg`. CPython's `reshape_2_8_16 ... marg=(1,2,8,16)`.
def marg_dim.go(+m: MxMarg, +f: O.Found, +nm: String) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([nm, "_marg=", mx_show(MxMarg.ds(m))]))
    IO.print(String.concat([nm, "_shape=", mx_show(mxm_shape(m, [1, 4, 8, 8]))]))
    IO.print(String.concat([nm, "_nsrc=", U32.show(O.Arena.nsrc(O.Found.ar(f), O.Found.i(f)))]))

def marg_reshape_row() -> IO(Unit):
  +f = G.reshape(O.Arena.empty(), 1, 2, 8, 16)
  marg_dim.go(mxm_marg(O.Found.ar(f), O.Found.i(f)), f, "resh")

# THE PERMUTE VALIDITY CHECK, both sides, and they are the pair the notes call for:
# a positive row alone cannot see the identity check disappear. `perm_ok` is a real
# permutation of `range(4)`; `perm_bad` is `[0, 0, 2, 3]`, which has a REPEAT and is
# therefore not a permutation -- and it is the row that sees `mxm_dup` at all, since
# every other fixture in this file has a distinct marg.
# ONE ROW, THREE FIXTURES, and they are the THREE WAYS ops.py:416's check can fail:
# a real permutation, a REPEAT, and an index past the end. The repeat case is the one
# that matters -- `mxm_perm_lt` alone accepts `[0, 0, 2, 3]`, so without `mxm_dup` the
# check would pass a marg that is not a permutation and `mxm_pick_all` would then
# answer a shape of the right length holding the wrong dims. That is the whole
# argument for having the row at all.
# `mxm_perm_ok` TAKES TWO `Bool`s and not the marg and the source, because the two
# conjuncts are computed at the call site -- `mxm_perm_lt` needs the source's LENGTH and
# `mxm_dup` needs the marg, and a `List<&2, U32>` is a `Type` that cannot carry both.
# `Bool` HAS NO `U32.show` (the notes' R3), so every gate row pays this conversion and
# it is hoisted here rather than written at each call site. There is no `Bool.match` in
# `base.bend` -- `Bool.pick` is the only branch -- so the two arms are spelled out.
def mxm_b2u(b: Bool) -> U32:
  Bool.pick(U32, b, 1, 0)

def mx_perm_is(lt: Bool, dup: Bool) -> Bool: mxm_perm_ok(lt, dup)
def marg_permchk.go(+nm: String, +ys: List<&2, U32>, n: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(mxm_b2u(mx_perm_is(mxm_perm_lt(ys, n), mxm_dup(ys, Nil{}, False{}))))]))

def marg_permchk_row() -> IO(Unit):
  do IO<Unit>:
    marg_permchk.go("perm_ok", [1, 0, 2, 3], 4)
    marg_permchk.go("perm_bad", [0, 0, 2, 3], 4)
    marg_permchk.go("perm_oob", [1, 0, 2, 9], 4)


# ===========================================================================
# SECTION H -- THE THREE ROWS THAT CLOSE THE MEASURED BLIND SPOTS. Each of these
# was added because the mutation table said a rule was untested, and each names the
# mutation that found it. A row added for that reason is a row with a job.
# ===========================================================================

# M5'S ROW. `f_ = smax(1, ceildiv(o*s - d, i))` (movement.py:606) and the clamp is
# load-bearing for exactly ONE family: `k=3, d=2, i=5, s=1`, where `o = 1` and
# `o*s - d = -1`, so `ceildiv(-1, 5) == 0` and the clamp is the whole answer. Every
# OTHER fixture in this file has `f_ = 1` for the uninteresting reason that the
# numerator is positive, so dropping the clamp moved NOTHING -- a blind spot measured,
# not guessed. CPython, for the same case: `o = 1`, `f = 1`; without the clamp `0`.
def f_neg_row() -> IO(Unit):
  IO.print(String.concat(["f_neg=", mx_show(mx_pool_f(mx_pool_out([5], [2], [3], [1]), [1], [5], [2]))]))

# M8'S ROW. `mxm_marg`'s catch-all answers `MDim{Nil{}, False{}}`, and with only PAD,
# RESHAPE, PERMUTE and FLIP in the gate the catch-all is DEAD CODE -- a dead arm that
# typechecks, which the notes record as its own hazard ("an arm after a `case _:` is
# dead code and Bend does not say so", stated the other way round: a catch-all with no
# fixture is equally invisible). A NON-MOVEMENT op is the fixture, and its marg must be
# the empty `MDim`, so `add_tag = 2`. Python RAISES here
# (`RuntimeError(f"{self.op} is not a MovementOp")`, ops.py:819) and so has no answer to
# match; the port answers the catch-all rather than refusing, and `2` is that answer.
# M8 changes the catch-all to `MPair` and moves this row, which is the point: the arm
# has a fixture.
def marg_other.go(+f: O.Found) -> IO(Unit):
  IO.print(String.concat(["add_tag=", U32.show(marg_tag(mxm_marg(O.Found.ar(f), O.Found.i(f))))]))

def G.addfix() -> O.Found:
  +b = G.base(O.Arena.empty())
  +c = G.c1(O.Found.ar(b), 7)
  O.UOp.new(O.Found.ar(c), O.OpsADD{}, [O.Found.i(b), O.Found.i(c)], O.ANone{}, O.TNone{})

def marg_other_row() -> IO(Unit):
  marg_other.go(G.addfix())

# M12'S ROW. `mx_dropn` clamps `ndim - len(k_)` at 0, and the only fixture that reached
# it had `ndim >= len(k_)` -- an EQUAL pair does not exercise a `<` -- so the clamp was
# dead. `pool_wide` is a 3-wide kernel on a 2-D input, which movement.py:599 ASSERTS
# against, so CPython raises and the port has no answer to match. What the row pins is
# therefore the PORT's answer -- `noop = 0` and the whole shape as `i_` -- and the
# `o_` it prints is meaningless arithmetic on an input the kernel does not fit. That is
# stated here rather than hidden: this row exists to make M12 move, and a row whose
# VALUES are not CPython's is a row about the CLAMP and not about `_pool`.
def pool_wide_row() -> IO(Unit):
  IO.print(String.concat(["pool_wide=", mx_show(mx_pool_shape([1, 4], [3, 3, 3], [1, 1, 1], [1, 1, 1]))]))

# ===========================================================================
# SECTION I -- THE WRITE HALF. `mixin/movement.py`'s WRAPPERS, in Python's order.
#
# Sections A-H are the READ half: `_pool`'s shape arithmetic and the `ssimplify`-on-
# CONCRETE arm (`mxm_marg`, `mxm_shape`) that close W1/W2. This section is the twenty-
# four wrappers that call `_mop`, and the reason it is a separate section is the
# IDENTITY TEST: every one of them ends `return self if ret.shape == self.shape else
# ret` (movement.py:185, :190, :194, :231, :254), so the wrapper needs the shape of the
# node it JUST BUILT -- and `fold.bend:1620-1626` does not answer that for PAD, SHRINK,
# EXPAND, FLIP or PERMUTE.
#
# **THE MERGE POINT, and it is the reason this section is buildable at all.** The
# wrappers use `MX.mxm_shape(MX.mxm_marg(ar, made), src_shape)` for that test rather
# than `mixin/op.bend`'s `mo_reshape`/`mo_permute`, whose `mo_sints` comparison is the
# one that has to work around the gap. `op.bend` is READ-ONLY here, so the gap is
# ROUTED AROUND rather than fixed, and the routing is one function: `mxw_same`.
#
# EVERY WRAPPER IS GATED ON FOUR NUMBERS, not one: node count, root op, src count, and
# the SRC OP SEQUENCE. The sequence is the one that matters and it is the one this
# project has been bitten by -- a movement that swaps two srcs has the right count and
# the wrong graph. `mxw_sig` prints all four as one string so no row can quietly drop
# one of them.
# ===========================================================================

# --- THE GRAPH INSPECTOR -----------------------------------------------------

# THE PARAM ARG, in `ops.bend`'s field order. It is a COPY and not a call into
# `op.bend` because `mo_buf4` hard-codes `size = 4` and the fixtures here need several
# sizes; `mn_buf1` in `examples/beautiful_mnist.bend` is the same copy and the reason
# is the same, which is a duplication three files now carry and which a shared
# `ops.bend` builder would delete.
def mxw_pbuf(slot: U32, size: U32) -> O.ParamArg:
  O.ParamArg{slot, S.single(), Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
             False{}, None{}, None{}, False{}, None{}}

# A BUFFER, which is the bottom of every movement graph and the only node in one whose
# op the fold does not need to answer. It is a `.of` split because the `O.UOp.new` is a
# CALL and its `Found` has to be handed to `T.tn_wrap_uop` by name.
def mxw_buf.of(+ar: O.Arena, +f: O.Found) -> T.Tensor:
  T.tn_wrap_uop(O.Found.ar(f), O.Found.i(f))

def mxw_buf(+ar: O.Arena, slot: U32, size: U32) -> T.Tensor:
  mxw_buf.of(ar, O.UOp.new(ar, O.OpsBUFFER{}, Nil{}, O.AParam{mxw_pbuf(slot, size)}, O.TNone{}))

# A SHAPE ARG of ARBITRARY LENGTH, interned as a STACK of CONSTs. It walks the VALUE
# LIST rather than a `Nat` countdown, which is what makes it one def: the list tail `t`
# is a strict subterm of `vs`, so the decrease check is satisfied by the FIRST argument
# and there is no fuel to thread. The `1n+p` spelling of the same walk would need the
# current value AND the tail, and the current value is exactly what the spent scrutinee
# will not give (see the notes' rule 1).
# `G.c1(ar, v)` IS CALLED TWICE -- once for the arena, once for the index -- and the
# obvious "fix" of a `+f = ...` let makes the pair MUTUALLY RECURSIVE, because the let
# needs a def boundary and the def boundary closes the cycle the walk just opened. So the
# double call STAYS, and it is CORRECT rather than lucky: `G.c1` is
# `O.UOp.const(ar, ...)` with no srcs and no dependence on `ar` beyond the intern table,
# so both calls intern the same node and answer the same index. The cost is one wasted
# intern-table lookup per dim.
#
# THIS IS THE GENERAL SHAPE OF THE TRAP IN THIS FILE: the fix that reads obviously right
# (intern once, read the `Found` twice) is the fix that needs a def, and in a WALK the
# def is mutual recursion. The workable forms are a straight-line fixture (`G.stk4`),
# a `Data` record carrying the accumulator, or -- what is done here -- a pure call made
# twice.
#
# **AND IT PREPENDED, WHICH WAS THE ACTUAL BUG, MEASURED NOT GUESSED.** The walk goes
# DOWN `vs` and accumulates UP, and `List.append(a, A, [i], acc)` puts the new index at
# the FRONT, so the STACK came out as `STACK(8, 8, 4, 1)` for a target of `[1, 4, 8, 8]`.
# `dbg_sk_marg` is the row that saw it and it exists for exactly this reason: the shape
# came back EMPTY (`dbg_made_shape=` with nothing after it) because `mxm_as_shape` saw
# a first element of 8 where the fold's own base had 1, and the identity test could not
# match. This is the SECOND time in this file that a prepend/append slip produced the
# right LENGTH and the wrong VALUES -- the first was `mx_shows.go`, and M11 measures it
# at 22 of 42 rows. The lesson generalises past this file: **an accumulator fold over a
# list of DIMENSIONS must say which end it adds to, in a comment, because the mistake is
# invisible in the type and in the count.**
def mxw_stk(+vs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, U32>) -> O.Found:
  match vs:
    case Nil{}: G.mstack(ar, acc)
    case v <> t: mxw_stk(t, O.Found.ar(G.c1(ar, v)), List.append(&2, U32, acc, [O.Found.i(G.c1(ar, v))]))

# IS A MOVEMENT OP -- the three marg shapes plus the FLIP sibling, which is
# `mxm_arg_op` union `mxm_dim_op` union `mxm_pair_op`. It is a def and not a `List`
# membership because `O.op_in` wants a list of ops and building one per call is the
# copy the brief forbids.
def mxw_mv(op: O.Op) -> Bool:
  O.op_in([O.OpsRESHAPE{}, O.OpsEXPAND{}, O.OpsPAD{}, O.OpsSHRINK{}, O.OpsPERMUTE{}, O.OpsFLIP{}], op)

# THE FOLD'S ANSWER AS `U32`s, for the nodes `mxm_marg` does not claim. A movement op
# never reaches it -- that is the whole split -- and a dim the fold holds symbolically
# (`O.SU`) becomes 0, which is the same answer `mo_dim_u32` gives and for the same
# reason: a symbolic dim is not a number and pretending otherwise is the failure mode
# this file is guarding against.
# `F.folded(ar)` BUILDS THE WHOLE FOLD and it is the expensive half of this section.
# That is `mixin/op.bend`'s rule stated the other way round -- "a def that BUILDS takes
# `+t` and NOT a caller-supplied `+fx`, and reads `F.folded(...)` itself" -- and it is
# CORRECT here for the reason it is correct there: a `Folded` handed in from outside WILL
# disagree with the arena the moment anything between the two grows it, and every wrapper
# here grows the arena before the next read. The cost is one Kahn fold per non-movement
# shape read; the alternative is a stale table and a wrong answer.
def mxw_dims(+ar: O.Arena, u: U32) -> List<&2, O.Sint>:
  MO.mo_dims(F.folded(ar), u)

def mxw_fold_shape.go(+ds: List<&2, O.Sint>, acc: List<&2, U32>) -> List<&2, U32>:
  match ds:
    case Nil{}: acc
    case d <> t: mxw_fold_shape.go(t, List.append(&2, U32, acc, [MO.mo_dim_u32(d)]))

def mxw_fold_shape(ar: O.Arena, u: U32) -> List<&2, U32>:
  mxw_fold_shape.go(mxw_dims(ar, u), Nil{})

# **THE MERGE POINT.** The shape of ANY node: `mxm_shape` for the six movement ops that
# `fold.bend:1620-1626` defers, and the fold for everything else. Every wrapper's
# identity test goes through here, and it is ONE def rather than six call sites because
# the six would each have to re-derive the op test and each of them is a chance to
# disagree about which ops are movement ops.
# THE MOVEMENT HALF, and IT IS ONE SELF-RECURSIVE DEF with a TWO-SCRUTINEE match.
#
# THE THREE-DEF SHAPE (`go` -> `at` -> `of`, each calling the one below) IS A MUTUAL
# RECURSION and Bend refuses it in every declaration order, with the misleading "a filled
# definition (an unfilled law is a dead claim)" naming the LAST def in the cycle. The
# working shape is ONE def matching `fuel mv` together, which is legal precisely because
# the `False` arm is a CALL and not a recursion -- so `mxw_fold_shape` is NOT evaluated
# on a movement node, which matters because it runs a whole Kahn fold and doing it
# wastefully on every movement node would cost a fold per wrapper step.
#
# `mv` IS A PARAMETER AND NOT A `match` INSIDE THE ARM because `mxw_mv(O.Arena.op(...))`
# is a CALL, and a call cannot be a scrutinee. It is recomputed for the SOURCE on every
# step, which is the right place: the source is a different node with a different op.
def mxw_shape_of(fuel: Nat, mv: Bool, +ar: O.Arena, +u: U32) -> List<&2, U32>:
  match fuel mv:
    case 0n _: Nil{}
    case _ False{}: mxw_fold_shape(ar, u)
    case 1n+p True{}: mxm_shape(mxm_marg(ar, u), mxw_shape_of(p, mxw_mv(O.Arena.op(ar, O.Arena.src0(ar, u))), ar, O.Arena.src0(ar, u)))

# **THE MERGE POINT.** The shape of ANY node: `mxm_shape` for the six movement ops that
# `fold.bend:1620-1626` defers, and the fold for everything else. Every wrapper's
# identity test goes through here, and it is ONE def rather than six call sites because
# the six would each have to re-derive the op test and each of them is a chance to
# disagree about which ops are movement ops.
def mxw_dims_of(+ar: O.Arena, +u: U32) -> List<&2, U32>:
  mxw_shape_of(O.Arena.budget(ar), mxw_mv(O.Arena.op(ar, u)), ar, u)

# THE IDENTITY TEST, `return self if ret.shape == self.shape else ret`
# (movement.py:185/:190/:194/:231/:254). It asks for ABSENCE of a difference rather than
# for a particular index, which is the notes' rule: `eq(m, 0)` is satisfied by any
# wrong-but-present answer. `O.eq_u32` is `ops.bend`'s list equality and is used rather
# than a second hand-written walk.
# THE LENGTH AS A `Nat`, for `MO.mo_range`, and it is a separate def because
# `mxm_len_u32` and `List.length` are two conversions and the permute wrapper wants the
# `Nat` one. Naming it once means the two cannot be confused -- a `U32` length passed
# to `MO.mo_range` is a type error rather than a silently different order.
def mxw_len_nat(xs: List<&2, U32>) -> Nat: List.length(&2, U32, xs)

def mxw_same(+ar: O.Arena, +ret: U32, +self: U32) -> Bool:
  O.eq_u32(mxw_dims_of(ar, ret), mxw_dims_of(ar, self))

# --- THE GRAPH INSPECTOR, part two: the numbers and the base ---------------
#
# NODE COUNT, and the fuel is `Arena.budget` (ops.bend:2295) = `next + edges`, which is
# the worklist bound the notes record. A cheaper fuel HANGS rather than answering short
# and `toposort` on a fuel that runs out returns a PARTIAL list -- so a wrong fuel is a
# wrong node count that looks like a plausible number, which is the failure mode a count
# row always has.
def mxw_count(+ar: O.Arena, +u: U32) -> U32:
  U32.from_nat(List.length(&2, U32, O.UOp.toposort(O.Arena.budget(ar), ar, u)))

# THE SRC OP SEQUENCE. It is a fold from `List<&2, U32>` to `List<&2, String>` and it
# PREPENDS -- down the list, up the accumulator -- the same direction as `mx_show` and for
# the same reason. Printing the SEQUENCE rather than a set of op names is the whole
# point: `mx_pool_perm`'s M3 swaps two thirds and a set would not see it.
def mxw_srcops.go(+ar: O.Arena, +ss: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> t: mxw_srcops.go(ar, t, List.append(&2, String, acc, [O.Ops.name(O.Arena.op(ar, s))]))

def mxw_srcops(+ar: O.Arena, +ss: List<&2, U32>) -> List<&2, String>:
  mxw_srcops.go(ar, ss, Nil{})

# THE WHOLE SIGNATURE AS ONE STRING: `n=<count> op=<root> nsrc=<n> srcops=<seq>`.
#
# IT IS ONE STRING AND NOT FOUR ROWS ON PURPOSE. Four separate rows let a fixture drop
# one of them, and a PAD built with ONE STACK instead of two has the right root op and
# the right node count, so a gate carrying only those two is green on a wrong graph.
# `pad_nsrc` in Section H exists for the same reason and this is the generalisation.
def mxw_sig(+ar: O.Arena, +u: U32) -> String:
  String.concat(["n=", U32.show(mxw_count(ar, u)),
                  " op=", O.Ops.name(O.Arena.op(ar, u)),
                  " nsrc=", U32.show(O.Arena.nsrc(ar, u)),
                  " srcops=", String.join(mxw_srcops(ar, O.Arena.srcs(ar, u)), "|")])

# ===========================================================================
# SECTION I1 -- THE SIX CORE WRAPPERS. Python's order is `_broadcast_to`, `expand`,
# `reshape`, `pad`, `shrink`, `permute`, `flip` (movement.py:128-254) and this file
# follows it.
#
# THE SHAPE OF EVERY ONE IS THE SAME FOUR STEPS, and that is worth saying once:
#   1. build the arg as a `List<&2, U32>` of python ints (the `List` algebra);
#   2. intern it as a STACK of CONSTs (`mxw_stk`), in the arena it grows;
#   3. build the movement node in THAT arena (never the caller's);
#   4. the identity test against the SOURCE's shape (`mxw_same`).
# Steps 2 and 3 are the arena rule and step 4 is the merge point with Section A-H.
#
# `+made = ...` IS A SHARED `let` AND IT IS LOAD-BEARING. The node is needed by the
# identity test AND by the `pick`, and a `let` is affine, so an unshared one is a
# compile error and a re-CALL is a second node with a second arena. The rule is
# `+x = ...` for a shared local, which is the notes' `+q = p` shape.
# ===========================================================================

# THE PICK, and `Bool.pick` is not used here because both arms are Tensors and the
# `+` on two of them is noisier than a `match`. movement.py:185 is
# `return self if ret.shape == self.shape else ret`, so `True` answers `t`.
def mxw_pick(same: Bool, +t: T.Tensor, +made: T.Tensor) -> T.Tensor:
  match same:
    case True{}: t
    case _: made

# --- reshape (movement.py:164-184) -----------------------------------------
# The `-1` inference and BOTH `raise`s are NOT PORTED: `new_shape.count(-1)` is a
# Python-int sentinel over a `Sint` shape and `raise ValueError` has no Bend form, so
# a wrong-size `reshape` here builds a RESHAPE that Python would have refused. The row
# is `mxw_resh_wrong` and it says the port is PERMISSIVE, not that the check is gone.
def mxw_reshape.put(+t: T.Tensor, +n: O.Found) -> T.Tensor:
  T.tn_new(O.Found.ar(n), O.Found.i(n))

def mxw_reshape.of(+t: T.Tensor, +sk: O.Found) -> T.Tensor:
  mxw_reshape.put(t, O.UOp.new(O.Found.ar(sk), O.OpsRESHAPE{},
                              List.append(&2, U32, [T.Tensor.u(t)], [O.Found.i(sk)]), O.ANone{}, O.TNone{}))

def mxw_reshape.go(+t: T.Tensor, +ds: List<&2, U32>) -> T.Tensor:
  mxw_reshape.of(t, mxw_stk(ds, T.Tensor.ar(t), Nil{}))

# **THE ARENA IS `made`'s.** `mxw_same(T.Tensor.ar(t), ...)` is the same aliasing slip as
# `dbg_made_shape` one function away, and it is MEASURED here: `resh_noop` built a
# RESHAPE where CPython returns `self`, because the identity test read the base's arena
# with the made node's index, the index was past the end, and `mxw_same` compared the
# BOTTOM's shape against the base's and answered False. **THE RULE THAT ACTUALLY BITES
# IS: read the arena off the node whose INDEX you are about to read**, and a node that
# grows another node's arena is the one case where the two differ.
def mxw_reshape(+t: T.Tensor, +ds: List<&2, U32>) -> T.Tensor:
  +made = mxw_reshape.go(t, ds)
  mxw_pick(mxw_same(T.Tensor.ar(made), T.Tensor.u(made), T.Tensor.u(t)), t, made)

# --- permute (movement.py:214-231) ------------------------------------------
# `order_arg = tuple(self._resolve_dim(x) for x in argfix(order, *args))` and the
# `sorted(order_arg) != list(range(self.ndim))` check is NOT PORTED -- the same
# Python-int `sorted` over a `Nat` -- so `mxw_perm_bad` is the row that says a bad
# order is built rather than refused. `return self._mop(Ops.PERMUTE, arg=order_arg) if
# order_arg != tuple(range(self.ndim)) else self`: the identity test here is the arg
# against `range(ndim)`, NOT a shape comparison, and that is why this wrapper needs no
# fold at all.
def mxw_perm_of(+t: T.Tensor, +n: O.Found) -> T.Tensor:
  T.tn_new(O.Found.ar(n), O.Found.i(n))

def mxw_permute.go(+t: T.Tensor, +ys: List<&2, U32>) -> T.Tensor:
  mxw_perm_of(t, O.UOp.new(T.Tensor.ar(t), O.OpsPERMUTE{}, [T.Tensor.u(t)], O.ATuple{ys}, O.TNone{}))

def mxw_permute(+t: T.Tensor, +ys: List<&2, U32>) -> T.Tensor:
  mxw_pick(O.eq_u32(ys, MO.mo_range(mxw_len_nat(mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t))))),
           t, mxw_permute.go(t, ys))

# --- pad / shrink (movement.py:186-212) ------------------------------------
# BOTH ARE THE SAME NODE SHAPE: `UOp(op, src=(self, STACK_a, STACK_b))`, because
# `_mop`'s `case Ops.PAD | Ops.SHRINK: src_args = list(zip(*arg))` (ops.py:829) is a
# TRANSPOSE into two lists and the node has THREE srcs. The rows that say so are
# `pad` and `shrink` and both print `nsrc=3 srcops=<op>|Ops.STACK|Ops.STACK`.
#
# THE TWO STACKS ARE BUILT IN SEQUENCE AND THE SECOND IN THE FIRST'S ARENA. That is
# `tn_mop.pairs`' rule restated, and it is load-bearing twice over: an index means
# nothing outside its own arena, and the NODE must be interned in the arena that
# contains the shape args -- an arena one node short of them interns the node at an
# index that arena does not have.
# --- THE WRAPPER SHAPE, ONCE. Every wrapper below is: intern the args, build the node
# in the last arena, then `mxw_same` against the SOURCE. The three steps are three
# lines here and they are three lines in each wrapper, because a def cannot both branch
# on a call and branch on a value and there is no higher-order way to say "and then
# apply the identity test". The duplication is six lines per wrapper and it is the
# honest cost of no closures.
def mxw_finish(same: Bool, +t: T.Tensor, +made: T.Tensor) -> T.Tensor:
  mxw_pick(same, t, made)

# THE PAIR NODE: `UOp(op, src=(self, STACK_a, STACK_b))` for PAD and SHRINK. It is
# written out rather than calling `T.tn_mop` with `T.APairs` because `tn_mop.pairs`
# already exists and does exactly this -- so this def is `tn_mop.pairs` with the shape
# args already interned, and the reason it is spelled again is that `tn_mop` takes a
# `MopArg` whose `APairs` arm is `List<&2, O.Const>` (CONST VALUES) while the wrappers
# here carry `List<&2, U32>` (Python ints) and intern them themselves. Two spellings of
# the same arg is a real duplication and it is named rather than hidden.
# THE NODE, AND IT IS CALLED TWICE ON PURPOSE -- the same shape as `mxw_stk` and for
# the same reason. `O.UOp.new` is PURE given its arena and its arguments (the arena
# carries the intern table, so the second call finds the node the first one added and
# answers the same index), and the alternative -- a `let` carrying the `Found` -- needs
# a def boundary, and every def boundary here closes a cycle the walk just opened.
# This is the second time this file has made that trade and the comment is the point.
def mxw_pairs_new(+ar: O.Arena, +op: O.Op, +t: T.Tensor, +a: O.Found, +b: O.Found) -> O.Found:
  O.UOp.new(ar, op, [T.Tensor.u(t), O.Found.i(a), O.Found.i(b)], O.ANone{}, O.TNone{})

def mxw_pairs_node2(+ar: O.Arena, +t: T.Tensor, +op: O.Op, +a: O.Found, +b: O.Found) -> T.Tensor:
  T.tn_new(O.Found.ar(mxw_pairs_new(ar, op, t, a, b)), O.Found.i(mxw_pairs_new(ar, op, t, a, b)))

def mxw_pairs_node(+t: T.Tensor, +op: O.Op, +a: O.Found, +b: O.Found) -> T.Tensor:
  mxw_pairs_node2(O.Found.ar(b), t, op, a, b)

# --- a NON-MOVEMENT node, for W7's row --------------------------------------
# `x + 3` is `ADD(RESHAPE, CONST)` and `fold.bend` answers an ADD's shape by inheriting
# it from its src (fold.bend:1596-1606, the Broadcastable arm). It exists ONLY to give
# `mxw_shape_of`'s non-movement arm a fixture; no wrapper below calls it.
def mxw_add_new2(+c: O.Found, +t: T.Tensor) -> O.Found:
  O.UOp.new(O.Found.ar(c), O.OpsADD{}, [T.Tensor.u(t), O.Found.i(c)], O.ANone{}, O.TNone{})

# **THE CONST IS INTERNED FIRST, IN ITS OWN `let`, AND THAT IS THE WHOLE FIX.**
# `O.UOp.new(ar, ..., [T.Tensor.u(t), O.Found.i(G.c1(ar, v))], ...)` typechecked and
# produced `add=n=6 op=Ops.ADD nsrc=2 srcops=Ops.RESHAPE|Ops.ADD` -- the ADD names ITSELF
# as its second src. The cause is Bend's STRICT evaluation: an argument is evaluated
# before the callee branches, so `G.c1(T.Tensor.ar(t), v)` interned into a COPY of the
# arena and the index it returned is the slot the ADD was about to take. This is the
# notes' "BEND IS STRICT: an argument is evaluated before the callee branches" and the
# symptom is a self-edge, which is the one the notes also call the hardest to spot.
def mxw_add_new(+t: T.Tensor, +v: U32) -> O.Found:
  mxw_add_new2(G.c1(T.Tensor.ar(t), v), t)

def mxw_add(+t: T.Tensor, +v: U32) -> T.Tensor:
  T.tn_new(O.Found.ar(mxw_add_new(t, v)), O.Found.i(mxw_add_new(t, v)))

# --- pad (movement.py:186-190) ----------------------------------------------
# `ret = self._mop(Ops.PAD, tuple((x[0], s+x[0]+x[1]) if x is not None else (0, s)
# for x, s in zip(arg, self.shape)))` and `return self if ret.shape == self.shape else
# ret`. The `(0, s)` DEFAULT for a `None` entry is what `mxw_pad0` tests: padding nothing
# on every axis gives back `self`, and that is a CPython row
# (`pad_0_0_noop nodes=6 op=Ops.RESHAPE`).
def mxw_pad.put(+t: T.Tensor, +op: O.Op, +a: O.Found, +his: List<&2, U32>) -> T.Tensor:
  mxw_pairs_node(t, op, a, mxw_stk(his, O.Found.ar(a), Nil{}))

def mxw_pad.go(+t: T.Tensor, +los: List<&2, U32>, +his: List<&2, U32>) -> T.Tensor:
  mxw_pad.put(t, O.OpsPAD{}, mxw_stk(los, T.Tensor.ar(t), Nil{}), his)

def mxw_pad(+t: T.Tensor, +los: List<&2, U32>, +his: List<&2, U32>) -> T.Tensor:
  +made = mxw_pad.go(t, los, his)
  mxw_pick(mxw_same(T.Tensor.ar(made), T.Tensor.u(made), T.Tensor.u(t)), t, made)

# --- shrink (movement.py:192-212) -------------------------------------------
# `ret = self._mop(Ops.SHRINK, arg=[(x[0], x[1]-x[0]) if x is not None else (0, s) for
# x, s in zip(arg, self.shape)])` -- note the SUBTRACTION, so `shrink`'s arg is
# (offset, SIZE) where `pad`'s is (offset, END). That asymmetry is the whole difference
# between the two arms of `_shape` and getting it backwards makes a SHRINK's answer the
# offset instead of the size. `mxm_szs` reads the second element, so the row `shrink` is
# what proves the order.
def mxw_shrink.put(+t: T.Tensor, +op: O.Op, +a: O.Found, +sizes: List<&2, U32>) -> T.Tensor:
  mxw_pairs_node(t, op, a, mxw_stk(sizes, O.Found.ar(a), Nil{}))

def mxw_shrink.go(+t: T.Tensor, +offs: List<&2, U32>, +sizes: List<&2, U32>) -> T.Tensor:
  mxw_shrink.put(t, O.OpsSHRINK{}, mxw_stk(offs, T.Tensor.ar(t), Nil{}), sizes)

def mxw_shrink(+t: T.Tensor, +offs: List<&2, U32>, +sizes: List<&2, U32>) -> T.Tensor:
  +made = mxw_shrink.go(t, offs, sizes)
  mxw_pick(mxw_same(T.Tensor.ar(made), T.Tensor.u(made), T.Tensor.u(t)), t, made)

# --- flip (movement.py:233-254) ---------------------------------------------
# `flip_arg = tuple([i in axis_arg for i in range(len(self.shape))])` and
# `return self._mop(Ops.FLIP, arg=flip_arg) if any(flip_arg) else self`. FLIP's arg is
# the FLAG LIST in the `ATuple`, not a STACK of CONSTs, so the node has ONE src -- the
# row `flip` prints `nsrc=1 srcops=<the op above>` and a two-src flip would be a
# different op.
def mxw_flip_new(+t: T.Tensor, +flags: List<&2, U32>) -> O.Found:
  O.UOp.new(T.Tensor.ar(t), O.OpsFLIP{}, [T.Tensor.u(t)], O.ATuple{flags}, O.TNone{})

# `+t` BECAUSE `mxw_flip_new(t, flags)` IS CALLED TWICE and `T.Tensor` is a `Data`
# record so `+` is a refcount rather than a copy. `O.UOp.new` is pure given its arena
# (the arena carries the intern table) so the two calls find the same node -- the same
# trade as `mxw_stk` and `mxw_pairs_node2`, and the third time in this file.
def mxw_flip.put(+t: T.Tensor, +flags: List<&2, U32>) -> T.Tensor:
  T.tn_new(O.Found.ar(mxw_flip_new(t, flags)), O.Found.i(mxw_flip_new(t, flags)))

# `any(flip_arg)` IS `not (every flag is 0)`, and it is the identity test here -- there
# is NO shape comparison, because a FLIP does not change the shape. That is worth saying
# because it is the one movement wrapper whose identity test is not `mxw_same`, and a
# gate that assumed otherwise would not see a FLIP dropped.
#
# `sofar` IS "have we SEEN a non-zero flag" and it is a PARAMETER with the `match` on the
# list head -- the fold-verdict shape. The `case _ True{}: True{}` arm short-circuits
# without an early return, which is the only spelling available: an early return from the
# middle of a walk needs a def that calls back into the walk, and that is mutual
# recursion.
def mxw_any.go(flags: List<&2, U32>, sofar: Bool) -> Bool:
  match flags sofar:
    case Nil{} _: sofar
    case _ True{}: True{}
    case f <> t _: mxw_any.go(t, Bool.or(sofar, Bool.not(U32.is_zero(f))))

def mxw_any(flags: List<&2, U32>) -> Bool:
  mxw_any.go(flags, False{})

def mxw_flip(+t: T.Tensor, +flags: List<&2, U32>) -> T.Tensor:
  mxw_pick(Bool.not(mxw_any(flags)), t, mxw_flip.put(t, flags))

# THE BASE TENSOR: `Tensor.empty(1, 4, 8, 8)`, which CPython builds as
# `RESHAPE(BUFFER, STACK(4x CONST))` -- `mxm-oracle.py` prints
# `base op=Ops.RESHAPE nsrc=2 srcops=Ops.ALLOC,Ops.STACK` for the ALLOC case and this
# file's BUFFER is the same shape of graph. A BUFFER ALONE would be UNUSABLE here,
# because `fold.shape` does not answer a BUFFER and every wrapper's identity test needs
# the source's shape.
def mxw_base.of(+b: T.Tensor, a: U32, c: U32, d: U32, e: U32) -> T.Tensor:
  mxw_reshape.of(b, G.stk4(T.Tensor.ar(b), a, c, d, e))

def mxw_base() -> T.Tensor:
  mxw_base.of(mxw_buf(O.Arena.empty(), 0, 256), 1, 4, 8, 8)

# ===========================================================================
# SECTION I2 -- THE GATE ROWS FOR THE WRITE HALF. Every row is `mxw_sig` (Section I):
# node count, root op, src count, src OP SEQUENCE, in one string, so no row can drop
# one of the four. The expectations are CPython's, from `mxm-oracle.py`.
#
# THE `+t = mxw_base()` SHARED LET appears in every row and it is the arena rule made
# visible: `mxw_base()` builds a BUFFER AND A RESHAPE, so the base is a 2-node graph and
# every wrapper's node count is the BASE'S COUNT PLUS THE WRAPPER'S. An index means
# nothing outside its own arena, so a row that rebuilt the base per call would intern
# each node at index 0 and print a graph with no movement op in it.
# ===========================================================================

def mxw_row(+nm: String, +t: T.Tensor) -> IO(Unit):
  IO.print(String.concat([nm, "=", mxw_sig(T.Tensor.ar(t), T.Tensor.u(t))]))

# A `do` BLOCK HAS NO SHARED `let`, so the base is bound by the DEF and the rows take it
# as a PARAMETER -- the same shape as `marg_pad.go`. Building the base once per row would
# also be correct here (each row has its own arena) but the rows are meant to be READ as
# a sequence, and one arena for the whole sequence is what makes the counts comparable.
# **THE ARENA IS `made`'s AND NOT `t`'s, and that cost a cycle.** The row that first
# printed the made node's shape read `mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(made))` --
# the BASE's arena with the MADE node's index. `Arena.node` answers the BOTTOM for an
# index past the end, so `mxw_mv` read the bottom's op, the node was "not a movement
# op", and `mxw_fold_shape` on a node that is not there answered the EMPTY list. The
# symptom is a shape that is empty rather than wrong, which is why it is worth writing
# down: the aliasing rule's usual symptom is a WRONG node, and here it was a MISSING
# one. This file's own header names the rule three times and the third reading is the
# one that bites.
def mxw_dbg_shape() -> IO(Unit):
  +t = mxw_base()
  +made = mxw_reshape.go(t, [1, 4, 8, 8])
  IO.print(String.concat(["dbg_made_shape=", mx_show(mxw_dims_of(T.Tensor.ar(made), T.Tensor.u(made)))]))

def mxw_dbg(+t: T.Tensor) -> IO(Unit):
  +made = mxw_reshape.go(t, [1, 4, 8, 8])
  do IO<Unit>:
    IO.print(String.concat(["dbg_made_u=", U32.show(T.Tensor.u(made))]))
    IO.print(String.concat(["dbg_made_tag=", U32.show(marg_tag(mxm_marg(T.Tensor.ar(made), T.Tensor.u(made))))]))
    IO.print(String.concat(["dbg_sk_op=", O.Ops.name(O.Arena.op(T.Tensor.ar(made), O.Arena.src(T.Tensor.ar(made), T.Tensor.u(made), 1)))]))
    IO.print(String.concat(["dbg_sk_nsrc=", U32.show(O.Arena.nsrc(T.Tensor.ar(made), O.Arena.src(T.Tensor.ar(made), T.Tensor.u(made), 1)))]))
    IO.print(String.concat(["dbg_sk_marg=", mx_show(MxMarg.ds(mxm_marg(T.Tensor.ar(made), T.Tensor.u(made))))]))
    IO.print(String.concat(["dbg_mv=", U32.show(mxm_b2u(mxw_mv(O.Arena.op(T.Tensor.ar(made), T.Tensor.u(made)))))]))
    IO.print(String.concat(["dbg_len=", Nat.show(mxw_len_nat(mxw_dims_of(T.Tensor.ar(made), T.Tensor.u(made))))]))
    IO.print(String.concat(["dbg_budget=", Nat.show(O.Arena.budget(T.Tensor.ar(made)))]))
    IO.print(String.concat(["dbg_same=", U32.show(mxm_b2u(mxw_same(T.Tensor.ar(made), T.Tensor.u(made), T.Tensor.u(t))))]))
    IO.print(String.concat(["dbg_noop_same=", U32.show(mxm_b2u(mxw_same(T.Tensor.ar(mxw_reshape.go(t, [1, 4, 8, 8])), T.Tensor.u(mxw_reshape.go(t, [1, 4, 8, 8])), T.Tensor.u(t))))]))

def mxw_resh_row(+t: T.Tensor) -> IO(Unit):
  do IO<Unit>:
    mxw_row("base", t)
    mxw_row("resh", mxw_reshape(t, [1, 2, 8, 16]))
    mxw_row("resh1", mxw_reshape(t, [1, 4, 64]))
    mxw_row("resh_noop", mxw_reshape(t, [1, 4, 8, 8]))
    mxw_row("perm", mxw_permute(t, [1, 0, 2, 3]))
    mxw_row("perm3120", mxw_permute(t, [3, 1, 2, 0]))
    mxw_row("perm_noop", mxw_permute(t, [0, 1, 2, 3]))
    # `pad`'s SECOND list is the ABSOLUTE END, not the pad amount: movement.py:189 is
    # `(x[0], s+x[0]+x[1])`, so `pad(((0,0),(0,0),(1,1),(1,1)))` has the marg
    # `((0,1),(0,4),(1,10),(1,10))` and the `hi` list is `[1,4,10,10]`. MEASURED: the
    # first version of this row passed the pad AMOUNTS as `hi` and `pad_noop` built a PAD
    # whose shape was all zeros instead of returning `self`, which is the "right op, wrong
    # graph" hole the `srcops` field exists to catch -- the op and nsrc were both right.
    mxw_row("pad", mxw_pad(t, [0, 0, 1, 1], [1, 4, 10, 10]))
    mxw_row("pad_noop", mxw_pad(t, [0, 0, 0, 0], [1, 4, 8, 8]))
    mxw_row("shrink", mxw_shrink(t, [0, 0, 1, 1], [1, 4, 4, 4]))
    mxw_row("shrink_noop", mxw_shrink(t, [0, 0, 0, 0], [1, 4, 8, 8]))
    mxw_row("flip0", mxw_flip(t, [1, 0, 0, 0]))
    mxw_row("flip01", mxw_flip(t, [1, 1, 0, 0]))
    mxw_row("flip_noop", mxw_flip(t, [0, 0, 0, 0]))
    # W7'S ROW. `mxw_shape_of`'s `case _ False{}` arm -- the one that answers a NON-
    # movement op from the FOLD -- had NO fixture, so answering `Nil{}` there moved
    # nothing. Every node in the rows above is a movement op, and the one non-movement
    # node they reach (the BUFFER under the base RESHAPE) is a node `fold.bend` does not
    # answer, so its answer is the empty list EITHER WAY. An `ADD` over the base is the
    # fixture: it is not a movement op, and the fold DOES answer it (it inherits the
    # shape of its src), so the row separates the two arms. This row exists because a
    # mutation measured it, not because the arm looked untested.
    mxw_row("add", mxw_add(t, 3))
    IO.print(String.concat(["add_shape=", mx_show(mxw_dims_of(T.Tensor.ar(mxw_add(t, 3)), T.Tensor.u(mxw_add(t, 3))))]))
    IO.print(String.concat(["dbg_base_shape=", mx_show(mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t)))]))
    mxw_dbg_shape()
    mxw_dbg(t)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["pool_k3_s2=", mx_show(mx_pool_shape([1, 4, 8, 8], [3, 3], [2, 2], [1, 1]))]))
    IO.print(String.concat(["pool_k2_s2=", mx_show(mx_pool_shape([1, 4, 8, 8], [2, 2], [2, 2], [1, 1]))]))
    IO.print(String.concat(["pool_k3_s1=", mx_show(mx_pool_shape([1, 4, 8, 8], [3, 3], [1, 1], [1, 1]))]))
    IO.print(String.concat(["pool_k3_s2_d2=", mx_show(mx_pool_shape([1, 4, 8, 8], [3, 3], [2, 2], [2, 2]))]))
    IO.print(String.concat(["pool_k1_s1=", mx_show(mx_pool_shape([1, 4, 8, 8], [1, 1], [1, 1], [1, 1]))]))
    IO.print(String.concat(["pool_k2_s3=", mx_show(mx_pool_shape([1, 4, 8, 8], [2, 2], [3, 3], [1, 1]))]))
    IO.print(String.concat(["pool_k3_s4=", mx_show(mx_pool_shape([1, 4, 8, 8], [3, 3], [4, 4], [1, 1]))]))
    IO.print(String.concat(["pool_1d=", mx_show(mx_pool_shape([1, 4, 8], [3], [2], [1]))]))
    IO.print(String.concat(["pool_3d=", mx_show(mx_pool_shape([1, 4, 4, 4, 4], [2, 2, 2], [2, 2, 2], [1, 1, 1]))]))
    IO.print(String.concat(["pool_odd=", mx_show(mx_pool_shape([1, 4, 7, 7], [3, 3], [2, 2], [1, 1]))]))
    IO.print(String.concat(["perm_2x2=", mx_show(mx_pool_perm(2, 2)), " len=", U32.show(mx_ulen(mx_pool_perm(2, 2)))]))
    IO.print(String.concat(["perm_1x1=", mx_show(mx_pool_perm(3, 1)), " len=", U32.show(mx_ulen(mx_pool_perm(3, 1)))]))
    IO.print(String.concat(["perm_2x3=", mx_show(mx_pool_perm(2, 3)), " len=", U32.show(mx_ulen(mx_pool_perm(2, 3)))]))
    IO.print(String.concat(["perm_0x2=", mx_show(mx_pool_perm(0, 2)), " len=", U32.show(mx_ulen(mx_pool_perm(0, 2)))]))
    IO.print(String.concat(["f_k3s2=", mx_show(mx_pool_f(mx_pool_out([8,8],[1,1],[3,3],[2,2]), [2,2], [8,8], [1,1]))]))
    IO.print(String.concat(["f_k1s1=", mx_show(mx_pool_f(mx_pool_out([8,8],[1,1],[1,1],[1,1]), [1,1], [8,8], [1,1]))]))
    IO.print(String.concat(["f_k3s1=", mx_show(mx_pool_f(mx_pool_out([8,8],[1,1],[3,3],[1,1]), [1,1], [8,8], [1,1]))]))
    IO.print(String.concat(["f_k2s3=", mx_show(mx_pool_f(mx_pool_out([8,8],[1,1],[2,2],[3,3]), [3,3], [8,8], [1,1]))]))
    IO.print(String.concat(["f_d2=", mx_show(mx_pool_f(mx_pool_out([8,8],[2,2],[3,3],[2,2]), [2,2], [8,8], [2,2]))]))
    IO.print(String.concat(["kid_1=", mx_show(mx_pool_kid([3,3],[8,8],[1,1],[1,1]))]))
    IO.print(String.concat(["kid_2=", mx_show(mx_pool_kid([3,3],[8,8],[2,2],[2,2]))]))
    IO.print(String.concat(["drop=", mx_show(mx_i_(4n, 2n, [1,4,8,8])), " nn=", Nat.show(mx_nnoop(4n, 2n))]))
    IO.print(String.concat(["drop_wide=", mx_show(mx_i_(2n, 4n, [1,4])), " nn=", Nat.show(mx_nnoop(2n, 4n))]))
    marg_pad_row(1)
    marg_reshape_row()
    marg_perm_row()
    marg_flip_row()
    marg_permchk_row()
    f_neg_row()
    marg_other_row()
    pool_wide_row()
    mxw_resh_row(mxw_base())

# ===========================================================================
# THE MEASURED MUTATION TABLE. Twenty-seven mutations: sixteen on the READ half
# (Sections A-H) and eleven on the WRITE half (Section I). Driver:
# `.agents/slop/notes/mxm-mutate.py`. THE COPY IT MUTATES MUST LIVE BESIDE THIS FILE
# because the imports are relative -- a copy in /tmp cannot resolve `./../helpers.bend`
# and every mutation reads REFUSED, which is itself a measured fact.
#
#   READ HALF
#   M1  mx_pool_out: drop the (k-1)                          8   f_neg pool_3d pool_k1_s1
#                                                               pool_k2_s2 pool_k2_s3
#                                                               pool_k3_s1 pool_k3_s2_d2
#                                                               pool_odd
#   M2  mx_pool_shape.of2: swap o_ and k_                    6   pool_k1_s1 pool_k2_s2
#                                                               pool_k2_s3 pool_k3_s1
#                                                               pool_k3_s2_d2 pool_k3_s4
#   M3  mx_pool_perm: swap the ODD and EVEN thirds           4   perm_0x2 perm_1x1
#                                                               perm_2x2 perm_2x3
#   M4  mx_pool_perm.go: step +2 -> +1                        3   perm_0x2 perm_2x2 perm_2x3
#   M5  mx_pool_f: drop the smax(1,.) clamp                  1   f_neg
#   M6  mxm_as_shape.at: invert the symbolic refusal         13   incl. pad/resh/perm_noop
#   M7  mxm_szs: read the OFFSET instead of the SIZE           3   pad_noop pad_shape
#                                                               shrink_noop
#   M8  mxm_marg.sel3: the catch-all answers MPair           1   add_tag
#   M9  mx_perm_is: drop the mxm_dup conjunct               1   perm_bad
#   M10 mxm_pick_all: drop the List.reverse                  1   perm_shape
#   M11 mx_shows.go: prepend instead of append               25   25 rows -- see below
#   M12 mx_dropn: drop the ndim>=ni clamp                    1   pool_wide
#   M13 mx_pool_out: truncate instead of ceildiv              5   pool_3d pool_k2_s2
#                                                               pool_k2_s3 pool_k3_s4
#                                                               pool_odd
#   M14 mx_pool_kid: i*f + d -> i*f                           2   kid_1 kid_2
#   M15 mxm_shape.sel: the ladder's arms the other way round 12   flip_shape pad_shape
#                                                               perm_shape resh_shape +8
#   M16 mxm_ys: read src[0]'s arg, not the node's own          -   REFUSED, no compile
#
#   WRITE HALF
#   W1  mxw_stk: PREPEND the CONST index                     9   resh_noop pad_noop
#                                                               shrink_noop + dbg rows
#   W2  mxw_pairs_node2: SWAP the two shape args             2   pad_noop shrink_noop
#   W3  mxw_reshape: invert the identity test                3   resh resh1 resh_noop
#   W4  mxw_permute: invert the order test                    -   REFUSED, no compile
#   W5  mxw_any: ALL-ZERO instead of SOME-NON-ZERO           1   flip_noop
#   W6  mxw_flip_new: give FLIP a SECOND src                  2   flip0 flip01
#   W7  mxw_shape_of: the False arm answers Nil               1   add_shape
#   W8  mxw_dims_of: fuel 0 instead of Arena.budget           9   pad perm_noop resh +6
#   W9  mxw_stk: build the STACK in a FRESH arena           14   pad resh shrink +11
#   W10 mxw_count: count the ROOT, not the toposort          15   every `n=` row
#   W11 mxw_reshape: the test reads the BASE's arena          1   resh_noop
#
# **NO MUTATION MOVES NOTHING, AND FOUR BLIND SPOTS WERE FOUND AND CLOSED.** The first
# run had three (M5, M8, M12) and the write half added a fourth, W7, whose
# `case _ False{}` arm -- the one that answers a NON-movement op from the fold -- had no
# fixture at all, because every node in the rows was a movement op and the one
# non-movement node they reached (the BUFFER under the base RESHAPE) is a node
# `fold.bend` does not answer, so the arm's answer was the empty list EITHER WAY. The
# four rows that closed them are `f_neg`, `add_tag`, `pool_wide` and `add_shape`, and
# each names the mutation that found it. A rule no mutation can reach is not gated.
#
# **M11 AND W10 ARE THE GATE'S TWO LOAD-BEARING WEAKNESSES, AND THEY ARE THE SAME KIND
# OF WEAKNESS.** M11 is the printer's own append direction and it moves 25 of 70 rows; W10
# replaces the toposort count with `1` and it moves all 15 `n=` rows. Together they say
# that a 70-row gate here is NOT seventy independent witnesses: the printer is one shared
# component, and the `n=` field is one shared component. A mutation in EITHER invalidates
# a quarter of the suite, and neither is a rule under test.
#
# **W2 IS THE ROW THIS PROJECT NEEDED AND DID NOT HAVE.** Swapping a PAD's two shape
# args -- `self|a|b` to `self|b|a` -- leaves the ROOT OP, the SRC COUNT and (mostly) the
# NODE COUNT alone, and it moves only `pad_noop` and `shrink_noop`, the two rows where
# the identity test fires. A gate carrying `op` and `nsrc` but not the src OP SEQUENCE
# would be completely blind to it. That is the "right count, wrong graph" hole the brief
# names, MEASURED in this file, and `mxw_sig` prints all four facts in one string
# precisely so a fixture cannot drop one of them.
#
# **W11 IS THE ALIASING RULE'S THIRD SYMPTOM, and it is the quietest one.** The identity
# test reading the BASE's arena with the MADE node's index returned False for a no-op
# reshape, so `resh_noop` built a RESHAPE where CPython returns `self`. The usual
# symptom of the rule is a WRONG node; this one is a MISSING node, because
# `Arena.node` answers the BOTTOM for an index past the end. One row (`resh_noop`) sees
# it and nothing else would.
#
# **W4 IS A COMPILE ERROR AND THAT IS THE FINDING.** Inverting `mxw_permute`'s order test
# is refused before it runs, so the PERMUTE wrapper's identity direction is owned by the
# type checker rather than by the gate -- the same situation as M16, and the two together
# are the only rules in this file the checker defends.
#
# **WHAT THE TABLE STILL DOES NOT COVER, and it is most of the write half.** Every row is
# a node signature or a shape. Nothing here builds `_pool`'s CHAIN, so nothing sees the
# seven `shrink_to`/`reshape` calls, the `repeat`, or the permute that closes it -- those
# wrappers are listed as NOT PORTED in Section I. Nor does anything here build a whole
# conv2d: `examples/beautiful_mnist.bend` is the consumer and its W1/W2 rows are the ones
# that would catch it.
