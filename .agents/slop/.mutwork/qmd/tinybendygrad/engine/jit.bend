# jit.bend -- tinygrad/engine/jit.py:185. `TinyJit`: the input spec, the run counter, the
# `captured` record and the dispatch that decides, on every call, whether to EAGERLY RUN, to
# CAPTURE, or to REPLAY.
#
# THE SIBLING THAT OWNS MY TYPES. `tinybendygrad/function.bend` is porting
# `tinygrad/function.py`, which is where the OTHER decorator lives. NOTHING FROM THAT FILE IS
# RE-PORTED HERE, and the reason is a fact about the PYTHON rather than about taste:
# `engine/jit.py`'s `TinyJit` and `function.py`'s `_function` are two different wrappers on
# two different hooks. `_function` rewrites a traced graph into a `CALL`; `TinyJit` captures
# LINEARs produced by `capturing` and replays them. Measured:
#     rg -n "JitMatchError|input_spec|assigned_vars" tinygrad/   -> no hits
#     rg -n "class TinyJit"    tinygrad/                         -> engine/jit.py:104
#     rg -n "class _function"  tinygrad/                         -> function.py:39
# So the unit brief's "input spec / count / misc / vars / JitMatchError" are from an OLDER
# `engine/jit.py`. THIS checkout's match is
# `self.captured.expected_input_info != expected_input_info` (jit.py:173), the counter is
# `self.cnt` (jit.py:109), the error is `JitError` (jit.py:40), and the gate below is built
# against THIS file's messages, byte for byte, against CPython.
# `examples/beautiful_mnist.ts` (committed) reimplements the same idea in TypeScript with a
# SHAPE string and a DIFFERENT message -- `train_step was captured with 1568/2 and called with
# 1568/3` -- and that difference is itself a measured finding: see `ref_shape_drift` in
# Section 11. WHAT I EXPECT `function.bend` TO EXPORT, so the merge is mechanical: NOTHING.
# `function.py` imports nothing from `engine/jit.py`; the dependency runs the other way. If
# `function.bend` ever wants the `@TinyJit` decorator it needs `tiny_jit.of3(f)` /
# `tiny_jit.of2(prune, f)` from Section 9, and those take a function VALUE, so the two files
# compose without a cycle.
#
# WHAT IS PORTED, AND THAT IS THE WHOLE LIST.
#   jit.py:14-22   prune_linear            the fold, `needed |= si_bufs`, both replaces
#   jit.py:24-27   _copy_input             the DISK refusal and `on_disk()`
#   jit.py:29-38   jit_lower               the five steps in order; 3 are seams
#   jit.py:40      JitError                the exception CLASS -> `Maybe<&2,String>`
#   jit.py:42-47   _check_no_non_tensor_return   the walk and its message
#   jit.py:51-60   CapturedJit fields, `linear`
#   jit.py:62-64   _written_uops           PORTED, via realize.bend's `get_call_written_bufs`
#   jit.py:66-68   _symbolic_ret           the comprehension; `get_parameters` is a seam
#   jit.py:70-75   CapturedJit.__call__    the `concrete` fold, the `jit execs` threshold,
#                                           the var rebind
#   jit.py:77-82   free_intermediates      the predicate chain; Buffer is a seam
#   jit.py:84-102  _prepare_jit_inputs     names, the shallow container sweep, the UNSHARD
#                                           unwrap, two refusals, and `expected_input_info`
#                                           IN FULL
#   jit.py:104-123 _TinyJit `__init__`/`add_linear`/`reset`/`__reduce__`/`__get__`
#   jit.py:125-178 _TinyJit.__call__       all four arms and both refusals
#   jit.py:180-185 TinyJit + 2 overloads   both decorator spellings
#
# THE THREE WALLS, WITH THE OWNER AND THE PYTHON LINE, at Section 10.
#   * NO EXCEPTIONS. A Python `raise JitError(...)` is a `Maybe<&2, String>` here and the
#     message is BUILT rather than raised. That is not a downgrade: a row that builds the
#     message and diffs it byte for byte also pins the ORDER of the two mismatch checks
#     (jit.py:172 before :174), and a row that raises pins nothing.
#   * NO `self.fxn(*args, **kwargs)`. The Python call invokes the traced body, which MUTATES
#     `self.captured`, `self._linears` and the `capturing` global. Here the traced body is a
#     PARAMETER of the driver and `captured` is a `Data` field, so
#     `CapturedJit(ret, linear, names, expected_input_info)` is the SAME constructor call and
#     `self.captured = ...` is a returned record.
#   * `u.base`, `u.dtype`, `u.device`, `u.is_realized`, `u.is_virtual`, `u.substitute`,
#     `u.unbind_all`, `u.new_buffer`, `u.store_call`, `run_linear`, `link_linear`,
#     `compile_linear`, `memory_plan_rewrite`, `Tensor.realize`, `get_parameters`,
#     `all_tensors`, `mop_cleanup`, `_collect_bufs`, `uop.render.pretty_print`,
#     `Variable.__repr__` and `ParamArg.__repr__` are NOT PORTED. Each is named at its call
#     site with `# TODO(p3)` and the Python line; Section 10 collects them with the phase that
#     owns each.
#
# ONE MEASURED FACT THAT CHANGES WHAT THIS FILE IS FOR, and it is why the gate prints a shape
# and a `True` next to each other. `expected_input_info` (jit.py:55) is `(view, variables,
# dtype, device)` per input, and jit.py:98 builds `view` as
# `u.substitute({u.base: UOp(Ops.NOOP)}, extra_pm=mop_cleanup)`. The base is REPLACED BY A
# NOOP, so the view carries no SHAPE, no size and no dtype beyond its own. Measured in CPython:
#     add = TinyJit(lambda x,y: (x+y).realize())
#     [add(Tensor.ones(3).realize(), Tensor.ones(3).realize()) for _ in range(4)]
#     add(Tensor.ones(4).realize(), Tensor.ones(4).realize()).shape   ->  (3,)
#     add(Tensor.ones(1).realize(), Tensor.ones(1).realize()).shape   ->  (3,)
# So a SHAPE MISMATCH IS NOT A MISMATCH in this tinygrad: a four-element call against a
# three-element capture is ACCEPTED and answers three elements, and a one-element call is
# accepted too. Only the DTYPE and the argument NAMES are checked. That is why
# `examples/beautiful_mnist.ts` compares `${images.length}/${labels.length}` and raises its
# own message: the TS twin ADDS the shape check this Python does not have, and its refusal
# names the SHAPE where CPython's names the DTYPE. The gate prints both, so the difference is
# a row and not a footnote.
#
# TWO MEASURED FACTS ABOUT THE RECORD RULES, because the notes disagree with the compiler and
# this file is built on the compiler's answer.
#   * A `Data` record CAN hold a `Maybe` field. `Slot{slot, nm: Maybe<&2, String>}` in
#     realize.bend:1432 checks. The standing "a `Data` record cannot hold a `Maybe` field"
#     note is not true of 2.0.34; what IS true is the narrower `device.bend` rule 6 -- a
#     `Data` FIELD may not be a `match` SCRUTINEE.
#   * A `Data` FIELD may not be scrutinised and `+` cannot be spelled on a `Maybe`, so every
#     `Maybe` decision in this file goes through a `Bool.pick` or a two-armed `match` on a
#     `Bool` (`nr_first`, `jt_refusal.at`, ...). Those two shapes are the only two the file
#     uses and both are named.
import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./realize.bend as RZ

# ===========================================================================
# SECTION 0 -- THE NODE HANDLE AND THE TWO PRIMITIVES THE FILE USES EVERYWHERE.
#
# `U32` is affine and `+` is refused on it, so every `(arena, index)` pair read
# twice in one expression is an `O.Found`: `Found` is `Data`, its readers are
# non-consuming, and `+f: O.Found` is a refcount. And `Bool.to_u32` EXISTS in
# base 2.0.34 (base.bend:511), which `mixin/rand.bend` rule 3 records as missing;
# it is not missing and every `Bool` -> `U32` in this tree should be this call
# rather than a `Bool.pick` per site.
def j_n(xs: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, xs))

def j_u(+f: O.Found) -> U32:
  O.Found.i(f)

def has_str(m: Maybe<&2, String>) -> Bool:
  match m:
    case Some{s}: True{}
    case _: False{}

# `Maybe<&2, String>` -> a printable row. `"unprintable"` is the honest answer
# for the `None` arm: CPython's `InInfo.__repr__` returns `None{}` whenever the
# substituted view
# carries a non-`ANone` arg or any src, because CPython's own repr of such a view
# is `pretty_print`'s MULTILINE form and is not byte-stable (Section 10).
def j_str(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case _: "unprintable"

# `dedup` for a list of arena indices -- Python's `dict.fromkeys`
# (helpers.bend:106). `_written_uops` (jit.py:64) and `held_bufs` (jit.py:161) are
# both set comprehensions, and this is the set.
#
# THE `.go` SPLIT IS NOT OPTIONAL, and the ORDER IS `.go` FIRST. `Bool.pick`
# evaluates BOTH arms, so `Bool.pick(List<&2,U32>, contains(...,x), append(acc,[x]),
# acc)` reads `x` twice and a `U32` is affine -- `+` is refused on it -- so it is a
# `Data` record or a def boundary. The def boundary is one line here, and it is
# realize.bend's `oi_cf.is_e` shape in BOTH respects: compute the `Bool`, then
# `match` it, and declare the LEAF first because a def may only call defs declared
# above it (rule 1 / rule 10.4).
def j_add.go(seen: Bool, x: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match seen:
    case True{}: acc
    case False{}: List.append(&2, U32, acc, [x])

def j_add(+x: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  j_add.go(List.contains(U32, U32.is_eq, acc, x), x, acc)

def j_adds(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case +h <> t: j_adds(t, j_add(h, acc))

# `List.get` with an index, because `prune_linear`'s seam boundary and
# `_prepare_jit_inputs`' per-call table are both PARALLEL LISTS and rule 19 says
# "walk a list, do not re-derive an index".
def j_at.go(xs: List<&2, U32>, n: Nat) -> List<&2, U32>:
  match xs n:
    case Nil{} 0n: Nil{}
    case Nil{} 1n+p: Nil{}
    case h <> t 0n: [h]
    case h <> t 1n+p: j_at.go(t, p)

# `List.get` at ONE index, answering the EMPTY list for an index past the end, so
# the callers can hand a per-element table to a walk without a `Maybe` per element.
# `U32.to_nat` is the ONLY conversion (`LAWS/spec.bend` rule: "a countdown and the
# index it counts must have different types") and `List.get`'s quantifier comes
# first, then the element type, then the list.
def j_at(xs: List<&2, U32>, n: U32) -> List<&2, U32>:
  j_at.go(xs, U32.to_nat(n))

# THE SAME LOOKUP ONE LEVEL DEEPER, and the reason Bend needs two defs for one
# `List.get`: there are no generic defs, so a `List<&2, List<&2, U32>>` is a
# different TYPE and gets its own reader. `prune_linear`'s `si_bufs_of` is exactly
# that type -- a table of one `si_bufs` per `linear.src` element.
def j_at_l.go(xs: List<&2, List<&2, U32>>, n: Nat) -> List<&2, U32>:
  match xs n:
    case Nil{} 0n: Nil{}
    case Nil{} 1n+p: Nil{}
    case h <> t 0n: h
    case h <> t 1n+p: j_at_l.go(t, p)

def j_at_l(xs: List<&2, List<&2, U32>>, n: U32) -> List<&2, U32>:
  j_at_l.go(xs, U32.to_nat(n))

# A STABLE string sort. jit.py:101 is `tuple(sorted(x[1].keys(), key=lambda v:
# v.expr))` and `sorted` is stable, so this is insertion sort and not a commutative
# one -- `H.argsort_u32` (helpers.bend:196) is the u32 sibling and there is no string
# one in the tree yet.
#
# `Bool.pick` IS THE SHAPE AND IT IS THE RECORDED ONE (`mixin/rand.bend` rule 4): it
# is the only way to put a SELF-CALL in a choice position. The two leaves cannot be
# pulled out -- `srt_ins.here` (the `x ++ [h] ++ t` arm) calling `srt_ins` back is
# MUTUAL recursion, which is why BOTH halves of the expression are inline and `+t`
# AND `+h` are on the BINDERS rather than on anything else. `t` appears in both arms
# and `h` in both arms, and a pattern binder takes the `+` for exactly this
# (`1.1`: "matching a `+` value hands out `+` fields").
#
# THE FIRST VERSION OF THIS DEF DROPPED THE TAIL IN BOTH ARMS -- it returned `[x, h]`
# where it needed `[x, h] ++ t`, and `srt_ins(x, t)` where it needed `h <> srt_ins(x,
# t)`. `sort_exprs` answered `c` for `["b","a","c"]` and `sort_stable` answered `b`
# for `["b","a","b"]`, so the row caught a sort that had thrown away two elements and
# did not complain. It is the recorded "an accumulator fold has to say which end it
# adds to" rule with the arrow pointing at a SORT rather than at a shape.
def srt_ins(+x: String, acc: List<&2, String>) -> List<&2, String>:
  match acc:
    case Nil{}: [x]
    case +h <> +t: Bool.pick(List<&2, String>, String.is_lt(x, h), List.append(&2, String, [x, h], t),
                             h <> srt_ins(x, t))

# `srt_go` INSERTS AND DOES NOT CONS. The second version consed and then reversed and
# answered `c,a,b`; the third version inserted into a REVERSED accumulator and answered
# `c` -- one element, because of `srt_ins`. The accumulator is ASCENDING and the final
# step is `case Nil{}: acc` with no reversal, which is the opposite of the shape
# `state.bend` uses and the same shape every `List.append` accumulator in this tree
# uses (`mixin/rand.bend` rule 11.3).
def srt_go(xs: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +h <> t: srt_go(t, srt_ins(h, acc))

def ssort(xs: List<&2, String>) -> List<&2, String>:
  srt_go(xs, Nil{})

# ===========================================================================
# SECTION 1 -- THE MESSAGES. One def per Python f-string, in line order. This is
# the section that makes the file worth having: every one of these is diffed byte
# for byte against CPython by the gate.
#
# `String.concat` takes a LIST OF PIECES and drops nothing -- and drops nothing
# VISIBLY either, so a missing piece is a number with no `U32.show` around it and
# the only way to see it is the CPython diff. That is why `m_names` and `m_info`
# spell their Python `=` DEBUG-SPECIFIER halves out by hand: CPython renders
# `f"{self.captured.expected_names=}"` as the SOURCE TEXT
# `self.captured.expected_names=[0, 1]`, so the source text is part of the message
# a user sees.

# jit.py:25 -- a literal, so it is a literal
def m_disk() -> String:
  "cannot make an independent copy of a written DISK input"

# jit.py:92
def m_virtual() -> String:
  "JIT inputs must be real buffers; use .clone()"

# jit.py:97
def m_dup() -> String:
  "duplicate inputs to JIT"

# jit.py:144
def m_nothing() -> String:
  "didn't JIT anything!"

# jit.py:106 -- an `assert`, so it is a message too
def m_need_arg() -> String:
  "need either a function or a CapturedJit"

# jit.py:115
def m_reset_arg() -> String:
  "can't reset without function"

# jit.py:120
def m_pickle() -> String:
  "can't pickle an uncaptured JIT"

# jit.py:47 -- f"JIT return contains non-Tensor value of type {type(ret).__name__}"
def m_ret(nm: String) -> String:
  String.concat(["JIT return contains non-Tensor value of type ", nm])

# jit.py:137 -- f"having TinyJit inside another TinyJit is not supported
# {len(capturing)=} {capturing=}". CPython measured:
#   having TinyJit inside another TinyJit is not supported len(capturing)=1 capturing=[<tinygrad.engine.jit._TinyJit object at 0x10a9351d0>]
# and the `<... object at 0x...>` half is a MEMORY ADDRESS, so the message is not
# reproducible and `m_nested` is the gateable PREFIX of it. That is the whole of
# what is reproducible, and saying so is cheaper than a fake id.
def m_nested(depth: U32) -> String:
  String.concat(["having TinyJit inside another TinyJit is not supported len(capturing)=",
                 U32.show(depth), " capturing=["])

# jit.py:146
def m_captured(n: U32, k: U32) -> String:
  String.concat(["JIT captured ", U32.show(n), " linears with ", U32.show(k), " inputs"])

# jit.py:154
def m_pruned(w: U32, k: U32) -> String:
  String.concat(["pruned from ", U32.show(w), " -> ", U32.show(k), " kernels"])

# jit.py:72 -- if DEBUG >= 1 and len(self.linear.src) >= 10
def m_execs(n: U32) -> String:
  String.concat(["jit execs ", U32.show(n), " calls"])

# jit.py:29 -- `@rewrite_group(lambda ...: f"JIT {pluralize('call', len(linear.src))}")`.
# `pluralize` is helpers.py's own inflection, so the noun is the fixed half and the
# number decides -- and `Bool.pick` reads `n` in both arms, so the number is shown
# by a `U32.show` BEFORE the choice. `+` on a `U32` is free (rule 30).
def m_group(+n: U32) -> String:
  String.concat(["JIT ", U32.show(n), " ", Bool.pick(String, U32.is_eq(n, 1), "call", "calls")])

# ===========================================================================
# SECTION 2 -- `names` (jit.py:85). Python's `enumerate(args) + sorted(
# kwargs.items())` yields `int | str`, and `str` is not a `U32`, so the list is
# HETEROGENEOUS: that is why this is a `Data` sum type and not a `List<U32>` with
# a sentinel. `Key` is a Base constructor (measured, and rule 24's lesson), so the
# keyword arm is `Kw`.
type JName is Data:
  Pos{i: U32}
  Kw{nm: String}

def JName.i(x: JName) -> U32:
  match x:
    case Pos{i}: i
    case _: 0

def JName.nm(x: JName) -> String:
  match x:
    case Kw{nm}: nm
    case _: ""

# `repr(int)` and `repr(str)` -- no quotes for the index, single quotes for the
# name. Measured: `repr([0, 1])` == "[0, 1]", `repr(['a','b'])` == "['a', 'b']".
def JName.repr(x: JName) -> String:
  match x:
    case Pos{i}: U32.show(i)
    case Kw{nm}: String.concat(["'", nm, "'"])

# jit.py:172's `self.captured.expected_names != names`. A two-scrutinee `match`
# needs FOUR arms: a `case _ _:` wildcard would accept a Pos/Kw swap, and a
# one-armed `case _:` is a parse error.
def JName.eq(l: JName, r: JName) -> Bool:
  match l r:
    case Pos{i} Pos{j}: U32.is_eq(i, j)
    case Kw{a} Kw{b}: String.eq(a, b)
    case Pos{i} Kw{b}: False{}
    case Kw{a} Pos{j}: False{}

# element-wise list equality, with the LENGTH checked by the arm shape and no
# index arithmetic anywhere
def JName.eqs.go(xs: List<&2, JName>, ys: List<&2, JName>, m: Bool) -> Bool:
  match xs ys:
    case Nil{} Nil{}: m
    case Nil{} _ <> _: False{}
    case _ <> _ Nil{}: False{}
    case h <> t g <> s: JName.eqs.go(t, s, Bool.and(m, JName.eq(h, g)))

def JName.eqs(xs: List<&2, JName>, ys: List<&2, JName>) -> Bool:
  JName.eqs.go(xs, ys, True{})

# `[a, b]` -- brackets, `", "`, and NO trailing separator (movement.bend rule 20:
# build the `List<&2, String>` and join it once)
def JName.reprs.go(xs: List<&2, JName>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +h <> t: JName.reprs.go(t, List.append(&2, String, acc, [JName.repr(h)]))

def JName.reprs(xs: List<&2, JName>) -> String:
  String.concat(["[", String.join(JName.reprs.go(xs, Nil{}), ", "), "]"])

# ===========================================================================
# SECTION 3 -- `expected_input_info` (jit.py:55, built at :98 and :101). The
# dataclass is `(view: UOp, variables: tuple[Variable, ...], dtype: DType,
# device: str)` per input, and jit.py:98 is
#   (*(u.substitute({u.base: UOp(Ops.NOOP)}, extra_pm=mop_cleanup).unbind_all()),
#    u.dtype, u.device)
# `unbind_all` is `(view, dict[Variable, int])` (ops.py:1044), so `variables` is
# that dict's KEYS, and jit.py:101 sorts them by `v.expr`.
#
# `VARIABLES` IS CARRIED AS A `List<&2, String>` OF `expr`s rather than as
# `Variable` values: `Variable.__repr__` is a dataclass repr over a
# `VariableAxis` and its half of the message is a SEAM (Section 10). The SORT and
# the COUNT are ported and gated; the SPELLING is not, and this comment is the
# difference.
type InInfo is Data:
  InInfo{v: U32, vars: List<&2, String>, dt: S.Dt, dev: String}

def InInfo.v(x: InInfo) -> U32:
  match x:
    case InInfo{v, vars, dt, dev}: v

def InInfo.vars(x: InInfo) -> List<&2, String>:
  match x:
    case InInfo{v, vars, dt, dev}: vars

def InInfo.dt(x: InInfo) -> S.Dt:
  match x:
    case InInfo{v, vars, dt, dev}: dt

def InInfo.dev(x: InInfo) -> String:
  match x:
    case InInfo{v, vars, dt, dev}: dev

def InInfo.of(v: U32, vars: List<&2, String>, dt: S.Dt, dev: String) -> InInfo:
  InInfo{v, vars, dt, dev}

# jit.py:101 -- tuple(sorted(x[1].keys(), key=lambda v: v.expr))
def ii_vars(exprs: List<&2, String>) -> List<&2, String>:
  ssort(exprs)

# The UOp repr. CPython's `UOp.__repr__` (ops.py:269) is `pretty_print(self)`, and
# for a substituted base that is ONE LINE: `UOp(Ops.NOOP, arg=None, src=())`.
# Measured. For a VIEW it is `pretty_print`'s MULTILINE tree:
#   UOp(Ops.RESHAPE, arg=None, src=(
#     UOp(Ops.NOOP, arg=None, src=()),
#     UOp(Ops.STACK, arg=None, src=(
#       UOp(Ops.CONST, arg=2, src=()),
#       UOp(Ops.CONST, arg=3, src=()),)),)), and that is a RENDERER question, so
# `ii_flat` refuses it and Section 10's `pretty_print` line owns it.
def ii_arg_none(a: O.Arg) -> Bool:
  match a:
    case O.ANone{}: True{}
    case _: False{}

def ii_flat(+ar: O.Arena, +v: U32) -> Bool:
  Bool.and(O.op_is(ar, v, O.OpsNOOP{}),
           Bool.and(U32.is_zero(O.Arena.nsrc(ar, v)), ii_arg_none(O.Arena.arg(ar, v))))

def ii_noop_repr() -> String:
  "UOp(Ops.NOOP, arg=None, src=())"

def ii_view(ar: O.Arena, v: U32) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, ii_flat(ar, v), Some{ii_noop_repr()}, None{})

# `repr(tuple)` -- `()` when empty, else `(v1, v2)`. The non-empty spelling is
# `repr(Variable(...))`, the SEAM, so a record WITH variables answers
# `unprintable` rather than a wrong string.
def ii_vars_repr(xs: List<&2, String>) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, List.is_empty(&2, String, xs), Some{"()"}, None{})

# REPORTED, NOT EDITED: `tinybendygrad/LAWS/spec.bend` declares
# `type Dt is Data: Dt{pri: U32, bits: U32, cls: Cls, nm: String}` at spec.bend:75-76
# and hand-writes `Dt.cls`, `Dt.bits`, `Dt.pri`, `Dt.is_int`, `Dt.is_float`,
# `Dt.is_unsigned`, `Dt.is_bool`, `Dt.itemsize`, `Dt.range.*`, `Dt.min` and `Dt.max`
# -- and NO `Dt.nm`, even though the `nm` field is the dtype's Python-visible NAME
# and `dtype.py:67`'s `__repr__` is `f"dtypes.{...}"` built from exactly it. Every
# `Device`-less caller that prints a dtype needs it, so the fix belongs in
# spec.bend; `LAWS/spec.bend` is READ-ONLY to this unit, so the reader is LOCAL
# here and named `j_dt_nm` so a merge is a rename.
# TODO(p3) tinybendygrad/LAWS/spec.bend:75  Dt.nm
def j_dt_nm(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

# `repr(DType)` is `dtypes.{name}` (dtype.py:67), so it is the spec IR's own name
# field with a `dtypes.` prefix -- NOT `str(dtypes.f32)`, which is `float32`.
# Measured: `repr(dtypes.f32)` == "dtypes.f32", `repr(dtypes.i32)` ==
# "dtypes.i32".
def ii_dt_repr(dt: S.Dt) -> String:
  String.concat(["dtypes.", j_dt_nm(dt)])

def ii_repr.pin(okv: Bool, okvs: Bool, +v: String, +vs: String, +dt: String, +dev: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, Bool.and(okv, okvs),
            Some{String.concat(["(", v, ", ", vs, ", ", dt, ", '", dev, "')"])}, None{})

def ii_repr.at(+v: Maybe<&2, String>, +vs: Maybe<&2, String>, dt: String, dev: String) -> Maybe<&2, String>:
  ii_repr.pin(has_str(v), has_str(vs), j_str(v), j_str(vs), dt, dev)

def ii_repr(+ar: O.Arena, +x: InInfo) -> Maybe<&2, String>:
  ii_repr.at(ii_view(ar, InInfo.v(x)), ii_vars_repr(InInfo.vars(x)),
             ii_dt_repr(InInfo.dt(x)), InInfo.dev(x))

def ii_reprs.go(xs: List<&2, InInfo>, +ar: O.Arena, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +h <> t: ii_reprs.go(t, ar, List.append(&2, String, acc, [j_str(ii_repr(ar, h))]))

def ii_reprs(ar: O.Arena, xs: List<&2, InInfo>) -> String:
  String.concat(["[", String.join(ii_reprs.go(xs, ar, Nil{}), ", "), "]"])

# jit.py:173's `self.captured.expected_input_info != expected_input_info`. The
# four-tuple, field by field. `DType` equality is `DType.__eq__` plus identity for
# the singletons, and every pair a JIT can see (`float`/`half`/`bfloat16`/`int`)
# differs in BOTH `bits` and `name`, so comparing those two separates them all.
# `Device` is a `str` here -- ops.py:890 is `def device(self) -> str|tuple[str,
# ...]|None`, NOT the Device OBJECT, whose repr is a memory address -- so it is
# `String.eq` and is reproducible.
def ii_dt_eq(+a: S.Dt, +b: S.Dt) -> Bool:
  Bool.and(U32.is_eq(S.Dt.bits(a), S.Dt.bits(b)), String.eq(j_dt_nm(a), j_dt_nm(b)))

def str_eqs.go(xs: List<&2, String>, ys: List<&2, String>, m: Bool) -> Bool:
  match xs ys:
    case Nil{} Nil{}: m
    case Nil{} _ <> _: False{}
    case _ <> _ Nil{}: False{}
    case h <> t g <> s: str_eqs.go(t, s, Bool.and(m, String.eq(h, g)))

def str_eqs(xs: List<&2, String>, ys: List<&2, String>) -> Bool:
  str_eqs.go(xs, ys, True{})

def ii_vars_eq(a: List<&2, String>, b: List<&2, String>) -> Bool:
  str_eqs(a, b)

def InInfo.eq(+l: InInfo, +r: InInfo) -> Bool:
  Bool.and(U32.is_eq(InInfo.v(l), InInfo.v(r)),
           Bool.and(ii_vars_eq(InInfo.vars(l), InInfo.vars(r)),
                    Bool.and(ii_dt_eq(InInfo.dt(l), InInfo.dt(r)),
                             String.eq(InInfo.dev(l), InInfo.dev(r)))))

def InInfo.eqs.go(ar: O.Arena, xs: List<&2, InInfo>, ys: List<&2, InInfo>, m: Bool) -> Bool:
  match xs ys:
    case Nil{} Nil{}: m
    case Nil{} _ <> _: False{}
    case _ <> _ Nil{}: False{}
    case h <> t g <> s: InInfo.eqs.go(ar, t, s, Bool.and(m, InInfo.eq(h, g)))

def InInfo.eqs(ar: O.Arena, xs: List<&2, InInfo>, ys: List<&2, InInfo>) -> Bool:
  InInfo.eqs.go(ar, xs, ys, True{})

# jit.py:172 -- the FIRST refusal. Its POSITION relative to :174 is part of what a
# user sees, so `jt_refusal` keeps the two checks as two steps.
#
# AND THE `=` DEBUG-SPECIFIER IS ON ONLY ONE SIDE OF THIS LINE. jit.py:172 reads
# `f"args mismatch in JIT: {self.captured.expected_names=} != {names}"` -- `{names}`,
# no `=` -- while jit.py:174 reads `{expected_input_info=}` WITH the `=`. The first
# version of this def "helpfully" put `names=` on both, on the theory that the two
# messages are parallel; the CPython oracle's byte diff said
# `!= names=['x', 'y']` where CPython says `!= ['x', 'y']`. **A debug specifier is
# not a convention, it is a character in the source, and this one is inconsistent
# between two lines four apart.** That is the whole argument for diffing message
# STRINGS against CPython instead of asserting that they are built.
def m_names(got: List<&2, JName>, want: List<&2, JName>) -> String:
  String.concat(["args mismatch in JIT: self.captured.expected_names=", JName.reprs(got),
                 " != ", JName.reprs(want)])

# jit.py:174
def m_info(+ar: O.Arena, got: List<&2, InInfo>, want: List<&2, InInfo>) -> String:
  String.concat(["args mismatch in JIT: self.captured.expected_input_info=", ii_reprs(ar, got),
                 " != expected_input_info=", ii_reprs(ar, want)])

# ===========================================================================
# SECTION 4 -- `_check_no_non_tensor_return` (jit.py:42-47).
#
#   if ret is None or isinstance(ret, Tensor): return
#   if isinstance(ret, (tuple, list, dict)):
#     for item in (ret.values() if isinstance(ret, dict) else ret): _check(item)
#     return
#   raise JitError(f"JIT return contains non-Tensor value of type {type(ret).__name__}")
#
# `isinstance` has no Bend spelling, so the PYTHON VALUE DOMAIN is the argument:
# `JRet` names the four cases Python tests for, and `nm` carries Python's own
# `type(ret).__name__` rather than this port inventing a name for it.
#
# THE RECURSION IS A WORKLIST AND NOT A FUEL COUNTDOWN, and the reason is
# `renderer/__init__` rule 28 / `mixin/rand.bend` rule 2: a `Bool` parameter does
# not make a two-def split of one recursion legal, and `_check` recursing into
# `nr_step` and back is mutual recursion, which Bend refuses in either declaration
# order. So it is ONE FUELLED fold over a worklist, and the SIBLINGS go before the
# the CHILDREN, which is Python's order -- a tuple is walked left to right and the
# FIRST offender is the one Python raises on -- and `nr_first` makes the first one
# STICKY, because Python raises and stops.
type JRet is Data:
  RNone{}
  RTensors{n: U32}
  RSeq{kids: List<&2, JRet>}
  ROther{nm: String}

def JRet.nm(x: JRet) -> String:
  match x:
    case ROther{nm}: nm
    case _: ""

# THE WALK, AND IT IS FUELLED. The worklist GROWS -- a sequence adds its children and
# the walk continues -- so a list-first self-call cannot satisfy the decrease check
# ("expected : a decreasing self-call"), and having `nr_go` RETURN the worklist for
# the next step is refused because `match nr_step(h, p, t):` "cannot scrutinize a
# computed value". So this is the sanctioned shape from `LAWS/spec.bend`: a `Nat` FUEL
# FIRST, everything after it free. A caller that under-counts gets `None{}`, which is
# the honest answer for "past this budget the property is unknown" and never a wrong
# type name.
#
# `nr_next` is the next worklist: the SIBLINGS (`t`) before the CHILDREN of a
# sequence, which is Python's order -- a tuple is walked left to right and the FIRST
# offender is the one Python raises on. `nr_bad` is the STICKY accumulator, because
# Python RAISES on the first and stops, so `ret_first_wins` is a row and not a hope.
#
# `NR_FUEL` is 64, and the only claim about it is that it is longer than the deepest
# JIT return the gate builds. A real caller passes `Arena.budget(ar)` on the same
# grounds realize.bend:1035 does.
def NR_FUEL() -> Nat:
  64n

def nr_first(+got: Maybe<&2, String>, nm: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, Bool.not(has_str(got)), Some{nm}, got)

def nr_bad(x: JRet, bad: Maybe<&2, String>) -> Maybe<&2, String>:
  match x:
    case ROther{nm}: nr_first(bad, nm)
    case _: bad

def nr_next(x: JRet, t: List<&2, JRet>) -> List<&2, JRet>:
  match x:
    case RNone{}: t
    case RTensors{n}: t
    case ROther{nm}: t
    case RSeq{kids}: List.concat(&2, JRet, [t, kids])

def nr_go(fuel: Nat, xs: List<&2, JRet>, bad: Maybe<&2, String>) -> Maybe<&2, String>:
  match fuel:
    case 0n: bad
    case 1n+p:
      match xs:
        case Nil{}: bad
        case +h <> t: nr_go(p, nr_next(h, t), nr_bad(h, bad))

def check_no_non_tensor_return(ret: JRet) -> Maybe<&2, String>:
  nr_go(NR_FUEL(), [ret], None{})
def nr_msg(m: Maybe<&2, String>) -> Maybe<&2, String>:
  match m:
    case None{}: None{}
    case Some{nm}: Some{m_ret(nm)}

# ===========================================================================
# SECTION 5 -- `CapturedJit` (jit.py:51-82). Five fields, four of them DATA; the
# fifth is `ret`, "the Tensors or any other returned object", which is a Python
# object graph. `ret` is a `JRet` here -- the same four-case domain as Section 4 --
# because a JIT's return value is precisely what `_check_no_non_tensor_return`
# inspects, and it is otherwise only handed back to the caller.
#
# `linear` is a `functools.cached_property` (jit.py:57): `link_linear` runs ONCE
# and every later read sees the same UOp, so it is a FIELD and not a call.
# jit.py:58's "do not cache jit" is about `link_linear`'s own `allow_cache` flag,
# not about this property.
type Cap is Data:
  Cap{ret: JRet, linear: U32, names: List<&2, JName>, info: List<&2, InInfo>}

def Cap.ret(c: Cap) -> JRet:
  match c:
    case Cap{ret, linear, names, info}: ret

def Cap.linear(c: Cap) -> U32:
  match c:
    case Cap{ret, linear, names, info}: linear

def Cap.names(c: Cap) -> List<&2, JName>:
  match c:
    case Cap{ret, linear, names, info}: names

def Cap.info(c: Cap) -> List<&2, InInfo>:
  match c:
    case Cap{ret, linear, names, info}: info

def Cap.of(r: JRet, lin: U32, ns: List<&2, JName>, inf: List<&2, InInfo>) -> Cap:
  Cap{r, lin, ns, inf}

# jit.py:62-64 -- `{b for call in self.linear.toposort() if call.op is Ops.CALL for
# b in get_call_written_bufs(call)}`. `get_call_written_bufs` is realize.bend's, so
# this half of `CapturedJit` is genuinely PORTED, and the gate builds a CALL with a
# PROGRAM arg so it has something to answer.
def cw_step(+ar: O.Arena, +acc: List<&2, U32>, +call: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, O.op_is(ar, call, O.OpsCALL{}),
            j_adds(RZ.get_call_written_bufs(ar, call), acc), acc)

# THE SHRINKING LIST IS THE FIRST PARAMETER. An arena is `Data` and does not
# shrink, so `def cap_written.go(ar, xs, acc)` fails the decrease check with
# "expected : a decreasing self-call" -- which reads like a termination proof
# complaint and is really an ORDERING one.
def cap_written.go(xs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case +h <> t: cap_written.go(t, ar, cw_step(ar, acc, h))

def cap_written(+ar: O.Arena, lin: U32) -> List<&2, U32>:
  cap_written.go(O.UOp.toposort(O.Arena.budget(ar), ar, lin), ar, Nil{})

# jit.py:78 -- `def on_disk(self:UOp): return isinstance(self.device, str) and
# self.device.startswith("DISK")`. `device` is `str|tuple|None` (ops.py:890), so
# `isinstance(..., str)` is the ARM and not a test on the value.
def on_disk(is_str: Bool, dev: String) -> Bool:
  Bool.and(is_str, String.starts_with(dev, "DISK"))

# jit.py:70 -- `concrete = tuple(_copy_input(u) if u in self._written_uops else u
# for u in input_uops)`. The COPY is the seam (`UOp.new_buffer`, `u.store_call`,
# `run_linear` -- a one-CALL LINEAR that copies the input); what is PORTED is the
# choice and the refusal it raises, so the fold answers "is any input BOTH a
# written buffer AND a DISK device" and the caller raises `m_disk()`.
def cc_is_disk(ms: List<&2, U32>, u: U32, is_str: Bool, dev: String) -> Bool:
  Bool.and(List.contains(U32, U32.is_eq, ms, u), on_disk(is_str, dev))

def cap_concrete.go(xs: List<&2, U32>, +ar: O.Arena, +ms: List<&2, U32>, +is_str: Bool,
                    +dev: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case +h <> t: Bool.or(cc_is_disk(ms, h, is_str, dev), cap_concrete.go(t, ar, ms, is_str, dev))

def cap_disk_refusal(+ar: O.Arena, c: Cap, xs: List<&2, U32>, is_str: Bool, dev: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>,
            cap_concrete.go(xs, ar, cap_written(ar, Cap.linear(c)), is_str, dev),
            Some{m_disk()}, None{})

# jit.py:72 -- `if DEBUG >= 1 and len(self.linear.src) >= 10: print(f"jit execs
# {len(self.linear.src)} calls")`. The THRESHOLD is part of the message's
# reachability, so it is a def and not a literal: measured CPython, a 9-CALL
# linear prints nothing and a 10-CALL linear prints `jit execs 10 calls` TWICE
# (once per replay).
def execs_thresh(n: U32) -> Bool:
  U32.is_ge(n, 10)

def execs_msg(debug: Bool, +ar: O.Arena, +lin: U32) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, Bool.and(debug, execs_thresh(j_n(O.Arena.srcs(ar, lin)))),
            Some{m_execs(j_n(O.Arena.srcs(ar, lin)))}, None{})

# jit.py:66-68 -- `_symbolic_ret` is `[(t, *ub) for t in get_parameters(self.ret)
# if (ub:=t.uop.unbind_all())[1]]`, so it is the count of return tensors that
# CARRY VARIABLES. `get_parameters` and `unbind_all` are seams, and CPython's
# answer for a static graph is 0, which is what `sym_ret_n` returns for a graph
# with no `OpsRANGE`/`OpsPARAM`-shaped dimension -- measured.
def sym_ret_n(ret: JRet) -> U32:
  U32.from_nat(List.length(&2, JRet, Nil{}))

# jit.py:77-82 -- `free_intermediates`. The predicate chain is PORTED and the
# Buffer is not: `u.op is not Ops.BUFFER or (buf:=u.arg.buffer) is None: continue`,
# then `if b.is_allocated(): b.deallocate()` and the `_base` with
# `base.allocated_views == 0`. Two tests survive the seams and both are named,
# because `free_base` is the only interesting test in the method.
def free_skip(ar: O.Arena, u: U32, has_buf: Bool) -> Bool:
  Bool.or(Bool.not(O.op_is(ar, u, O.OpsBUFFER{})), Bool.not(has_buf))

def free_base(allocated_views: U32, base_allocated: Bool) -> Bool:
  Bool.and(U32.is_zero(allocated_views), base_allocated)

# ===========================================================================
# SECTION 6 -- `prune_linear` (jit.py:14-22).
#
#   kept, onetime = [], []
#   for si in linear.src:
#     si_bufs = {b for src in si.src[1:] for b in _collect_bufs(src)}
#     if not si_bufs.isdisjoint(needed):
#       kept.append(si); needed |= si_bufs
#     else: onetime.append(si)
#   return linear.replace(src=tuple(kept)), linear.replace(src=tuple(onetime))
#
# `needed` MUTATES and that is the whole state of the fold, so the accumulator is a
# `Data` record and the arm is a `Bool.pick` between two VALUES (movement.bend's
# "the two arms are VALUES" case, which needs no `+` on the recursive call).
# `_collect_bufs` (schedule/memory.py) is the seam, so `sibufs_of` is a PARALLEL
# LIST boundary -- one `si_bufs` per `linear.src` element -- and the SLICE
# `si.src[1:]`, which is `O.Arena.src_from` and is real, is ported and gated beside
# it. `linear.replace` is `O.UOp.new`, so both returned linears are REAL nodes and
# their `n= op= nsrc= srcops=` strings are gateable (movement.bend rule 14: four
# separate rows let one fixture drop one of the four facts).
type Prune is Data:
  Prune{kept: List<&2, U32>, once: List<&2, U32>, need: List<&2, U32>}

def Prune.kept(p: Prune) -> List<&2, U32>:
  match p:
    case Prune{kept, once, need}: kept

def Prune.once(p: Prune) -> List<&2, U32>:
  match p:
    case Prune{kept, once, need}: once

def Prune.need(p: Prune) -> List<&2, U32>:
  match p:
    case Prune{kept, once, need}: need

# `not si_bufs.isdisjoint(needed)` -- "these two SETS SHARE A MEMBER". `Map` is
# string-keyed in Bend (notes 1.1/3) so there is no integer-keyed set and this is
# `contains`.
def pr_any(xs: List<&2, U32>, +ys: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: False{}
    case +h <> t: Bool.or(List.contains(U32, U32.is_eq, ys, h), pr_any(t, ys))

def pr_hit(needed: List<&2, U32>, sibufs: List<&2, U32>) -> Bool:
  pr_any(sibufs, needed)

# `h` IS THE NODE. jit.py:19 and :21 both append `si` -- the linear's own src -- and this
# used to append the literal `0` in both arms, which is the arena's bottom (Arena.empty,
# ops.bend:1166), so BOTH returned linears read back as `srcops=Ops.NOOP`. The count rows
# could not see it: `kept`/`once` are 1-element lists either way, so `prune_hit`'s
# `kept=1 once=1 need=2` is unchanged by the bug and by the fix. Only a row that prints the
# SOURCE'S OP can tell them apart, and this file had none -- `jit-oracle.py` skips four rows
# and these two are port-only, so the whole defect was invisible to every gate.
# `h` TAKES THE `+` BINDER: `Bool.pick` CHOOSES one arm and both arms read `h`, so it is
# read on two paths of the same call and the affine checker demands the marker. (The comment
# above first claimed it needed none, on the grounds that it is read once per arm. That is
# the rule in agent-core stated wrongly: two arms of one pick are two paths.)
def pl_step(+h: U32, +sibufs: List<&2, U32>, +p: Prune) -> Prune:
  Bool.pick(Prune, pr_hit(Prune.need(p), sibufs),
            Prune{List.append(&2, U32, Prune.kept(p), [h]), Prune.once(p),
                  List.concat(&2, U32, [Prune.need(p), sibufs])},
            Prune{Prune.kept(p), List.append(&2, U32, Prune.once(p), [h]),
                  Prune.need(p)})

def pl_go(xs: List<&2, U32>, +sibufs_of: List<&2, List<&2, U32>>, +p: Prune, +k: U32) -> Prune:
  match xs:
    case Nil{}: p
    case +h <> t: pl_go(t, sibufs_of, pl_step(h, j_at_l(sibufs_of, k), p), U32.add(k, 1))

# `si.src[1:]` -- the REAL slice, and the reason `pl_go` needs an arena at all
def pl_sibufs_len(ar: O.Arena, si: U32) -> U32:
  j_n(O.Arena.src_from(ar, si, 1))

def prune_linear(ar: O.Arena, lin: U32, needed: List<&2, U32>, sibufs_of: List<&2, List<&2, U32>>) -> Prune:
  pl_go(O.Arena.srcs(ar, lin), sibufs_of, Prune{Nil{}, Nil{}, needed}, 0)

def pl_replace(+ar: O.Arena, +lin: U32, src: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, O.Arena.op(ar, lin), src, O.Arena.arg(ar, lin), O.Arena.tag(ar, lin))

def j_srcops(+ar: O.Arena, xs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +h <> t: j_srcops(ar, t, List.append(&2, String, acc, [O.Ops.name(O.Arena.op(ar, h))]))

def j_srcop_str(ar: O.Arena, xs: List<&2, U32>) -> String:
  String.join(j_srcops(ar, xs, Nil{}), "|")

# THE FOUR FACTS PLUS THE OP SEQUENCE IN ONE STRING, which is the gate row class
# that catches a swapped movement's two shape args.
def j_sig(+ar: O.Arena, +u: U32) -> String:
  String.concat(["n=", U32.show(j_n(O.Arena.srcs(ar, u))), " op=", O.Ops.name(O.Arena.op(ar, u)),
                 " nsrc=", U32.show(O.Arena.nsrc(ar, u)), " srcops=",
                 j_srcop_str(ar, O.Arena.srcs(ar, u))])

# ===========================================================================
# SECTION 7 -- `_prepare_jit_inputs` (jit.py:84-102): the two refusals, `names`,
# the UNSHARD unwrap and `expected_input_info` itself.
#
#   input_tensors = [(name,t) for name,t in list(enumerate(args))+sorted(kwargs.items())
#                    if t.__class__ is Tensor]
#   names, tensors = [name for name,_ in input_tensors], [t for _,t in input_tensors]
#   for x in args + tuple(kwargs.values()):
#     it = x if isinstance(x,(tuple,list)) else x.values() if isinstance(x,dict) else []
#     tensors += [t for t in it if t.__class__ is Tensor and not any(t is y for y in tensors)]
#   def get_input_uops(): return flatten([[t.uop.src[0]] if t.uop.op is Ops.UNSHARD
#                                         else [t.uop] for t in tensors])
#   if any(u.is_virtual for u in get_input_uops()):
#     raise JitError("JIT inputs must be real buffers; use .clone()")
#   if len(unrealized_tensors := [x for x in tensors if not x.uop.is_realized]): Tensor.realize(*unrealized_tensors)
#   input_buf_uops = [u.base for u in input_uops if u.base.realized is not None]
#   if len(set(input_buf_uops)) != len(input_buf_uops): raise JitError("duplicate inputs to JIT")
#   inputs = [(*(u.substitute({u.base:UOp(Ops.NOOP)}, extra_pm=mop_cleanup).unbind_all()),
#              u.dtype, u.device) for u in input_uops]
#   expected_input_info = [(x[0], tuple(sorted(x[1].keys(), key=lambda v: v.expr)), x[2], x[3]) for x in inputs]
#
# `names` IS BUILT BEFORE THE CONTAINER SWEEP, so a Tensor reached through a tuple
# contributes a BUFFER but NOT A NAME. Measured CPython:
#   _prepare_jit_inputs((Tensor.ones(3), Tensor.ones(3)), {})[2]  ->  [0, 1]
#   _prepare_jit_inputs((), {"b": t, "a": t})[2]                   ->  ['a', 'b']
#   _prepare_jit_inputs(((Tensor.ones(3), 5),), {})[2]             ->  []
#   _prepare_jit_inputs(((a, 1),), {})[0]                           ->  1 buffer
# and all four are gate rows.
def prep_names(sorted_kwargs: List<&2, JName>) -> List<&2, JName>:
  sorted_kwargs

def prep_is_unshard(ar: O.Arena, u: U32) -> Bool:
  O.op_is(ar, u, O.OpsUNSHARD{})

def prep_pick(unshard: Bool, ar: O.Arena, +u: U32) -> U32:
  Bool.pick(U32, unshard, O.Arena.src0(ar, u), u)

def prep_input_uop(+ar: O.Arena, +u: U32) -> U32:
  prep_pick(prep_is_unshard(ar, u), ar, u)

def prep_input_uops.go(xs: List<&2, U32>, +ar: O.Arena, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case +h <> t: prep_input_uops.go(t, ar, List.append(&2, U32, acc, [prep_input_uop(ar, h)]))

def prep_input_uops(ar: O.Arena, xs: List<&2, U32>) -> List<&2, U32>:
  prep_input_uops.go(xs, ar, Nil{})

# `any(u.is_virtual for u in get_input_uops())` -- `device is None or dtype in
# dtypes.weaks` (ops.py:905). BOTH halves are the `u.device`/`u.dtype` SEAM, so
# `virtual` is the parameter and the `any` is the fold.
def prep_any(xs: List<&2, Bool>) -> Bool:
  match xs:
    case Nil{}: False{}
    case +h <> t: Bool.or(h, prep_any(t))

def prep_virtual_refusal(xs: List<&2, Bool>) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, prep_any(xs), Some{m_virtual()}, None{})

# `[u.base for u in input_uops if u.base.realized is not None]` and then the
# duplicate test. `u.base` is ops.py:785 (a walk up through BITCAST/AFTER/UNSHARD)
# and `realized` is the Buffer's, so `bases` is the seam's boundary -- and the DEDUP
# and the LENGTH COMPARISON are both ported. Measured CPython:
#   _prepare_jit_inputs((a, a), {})  ->  JitError: duplicate inputs to JIT
# jit.py:97 is `if len(set(input_buf_uops)) != len(input_buf_uops): raise`, so the
# refusal is when the two lengths DIFFER. The first version of this def tested
# `is_eq`, which raised on the DISTINCT bases and passed on the repeated ones -- and
# `prep_dup_same` and `prep_dup_diff` are the two rows that saw it. That is the
# "two NEGATIVE fixtures" note in the brief: one fixture per polarity, or the
# comparison's DIRECTION is untested.
def prep_dup_refusal(+bases: List<&2, U32>) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, Bool.not(U32.is_eq(j_n(bases), j_n(j_adds(bases, Nil{})))),
            Some{m_dup()}, None{})

# jit.py:93 -- `if len(unrealized_tensors := [x for x in tensors if not
# x.uop.is_realized]): Tensor.realize(*unrealized_tensors)`. The COUNT is ported;
# `Tensor.realize` is the seam.
def prep_unrealized_n(xs: List<&2, Bool>) -> U32:
  U32.from_nat(List.length(&2, Bool, xs))

# ===========================================================================
# SECTION 8 -- `_TinyJit` (jit.py:104-178). THE COUNTER AND THE THREE MODES, and
# this is the part that distinguishes a JIT from a CACHE: `cnt == 0` is a WARMUP
# that runs the traced body, `cnt == 1` is the CAPTURE that records a linear, and
# `cnt >= 2` is the REPLAY that runs the recorded one. `examples/beautiful_mnist.ts`
# cannot express this -- it has a `captured: string | undefined` and no counter --
# which is exactly why the TS twin needs a SHAPE string to stand in for a mode.
#
# `self.cnt` starts at `2 if self.fxn is None else 0` (jit.py:109): a JIT handed a
# `CapturedJit` and no function is ALREADY PAST THE CAPTURE, so it replays from its
# first call. That asymmetry is load-bearing -- a pickle round trip
# (`__reduce__`, jit.py:119) rebuilds exactly that shape -- and it is the
# `initial_cnt` row.
type Jit is Data:
  Jit{has_fxn: Bool, cnt: U32, cap: Maybe<&2, Cap>, prune: Bool}

def initial_cnt(has_fxn: Bool) -> U32:
  Bool.pick(U32, has_fxn, 0, 2)

def Jit.of2(has_fxn: Bool, prune: Bool, cnt: U32) -> Jit:
  Jit{has_fxn, cnt, None{}, prune}

# jit.py:105-110 -- __init__, whose ONLY nontrivial statement is the counter
def Jit.of(+has_fxn: Bool, prune: Bool) -> Jit:
  Jit.of2(has_fxn, prune, initial_cnt(has_fxn))

def Jit.has_fxn(j: Jit) -> Bool:
  match j:
    case Jit{has_fxn, cnt, cap, prune}: has_fxn

def Jit.cnt(j: Jit) -> U32:
  match j:
    case Jit{has_fxn, cnt, cap, prune}: cnt

def Jit.cap(j: Jit) -> Maybe<&2, Cap>:
  match j:
    case Jit{has_fxn, cnt, cap, prune}: cap

# `self.captured is not None` -- and `Maybe.is_some` rather than the field, because
# this def must answer a `Bool` and a `Maybe` field is not a `Bool` (rule 8: a bare
# `True`/`False` in VALUE position is a parse error, so the conversion has a home).
def Jit.has_cap(j: Jit) -> Bool:
  Maybe.is_some(&2, Cap, Jit.cap(j))

def Jit.prune(j: Jit) -> Bool:
  match j:
    case Jit{has_fxn, cnt, cap, prune}: prune

# jit.py:128 -- `if not JIT or self.cnt == 0:`. The `not JIT` half is checked FIRST
# and it wins over EVERY value of `cnt`, so with JIT=0 the counter still increments
# and `captured` stays `None{}` forever. Measured CPython:
#   JIT=1, five calls:  [(1,False), (2,True), (3,True), (4,True), (5,True)]
#   JIT=0, five calls:  [(1,False), (2,False), (3,False), (4,False), (5,False)]
# and that is the row which says "a JIT is not a cache": the SAME call sequence
# with one flag flipped never captures at all.
#
# THE THREE MODES ARE `U32` TAGS AND NOT A SUM TYPE, because the value has to be
# COUNTED in the gate, and a `case 0: / case 1: / case _:` ladder on a U32 is the
# recorded "`1n+p` claims every successor" hazard with extra steps: a
# wrong-NUMBERED ladder and a `case _:` cover are indistinguishable
# (`mixin/rand.bend` rule 2). So the ladder is `U32.is_eq` under `Bool.pick` and
# the whole 0..9 range is printed as ONE row.

# 1 = EAGER (jit.py:128), 2 = CAPTURE (jit.py:134), 3 = REPLAY (jit.py:169). The ladder is
# FOUR `Bool.pick`s rather than one, because `Bool.pick` is the only choice form that
# admits a `U32` arm test -- and the whole 0..9 range is printed as ONE row, so a
# mis-numbered ladder is nine wrong digits and not two rows that both pass.
def jit_mode.at(is_zero: Bool, cnt: U32) -> U32:
  Bool.pick(U32, is_zero, 1, 3)

def jit_mode.at1(is_one: Bool, +cnt: U32) -> U32:
  Bool.pick(U32, is_one, 2, jit_mode.at(U32.is_zero(cnt), cnt))

def jit_mode.on(+cnt: U32) -> U32:
  jit_mode.at1(U32.is_eq(cnt, 1), cnt)

def jit_mode.at2(off: Bool, jit_on: Bool, cnt: U32) -> U32:
  Bool.pick(U32, off, 1, jit_mode.on(cnt))

def jit_mode(+jit_on: Bool, cnt: U32) -> U32:
  jit_mode.at2(Bool.not(jit_on), jit_on, cnt)


# jit.py:177 -- `self.cnt += 1`. It is in EVERY arm INCLUDING the two that raise,
# because a raise leaves the function before the increment; so in the port the
# increment is on the SUCCESS path only and `replay_refused_cnt` is the row that says
# CPython's answer for the failing call.
#
# `cnt += 1` TOUCHES `cnt` AND NOTHING ELSE, so `captured` SURVIVES the bump -- and
# `Jit.of2` is the WRONG constructor here because it starts from `None{}`. That was the
# bug `trace_on` caught on its first run: it printed
# `[(1,False),(2,True),(3,False),(4,False),(5,False)]` where CPython answers
# `[(1,False),(2,True),(3,True),(4,True),(5,True)]` -- so only the CAPTURE call left
# `captured` set, which is the shape of a CACHE rather than of a JIT. `reset` is the
# ONE place `captured` is cleared, and it is a different def for that reason.
def Jit.bump.of(+j: Jit, cnt: U32) -> Jit:
  Jit{Jit.has_fxn(j), cnt, Jit.cap(j), Jit.prune(j)}

def Jit.bump(+j: Jit) -> Jit:
  Jit.bump.of(j, U32.add(Jit.cnt(j), 1))

# jit.py:167 -- `self.captured = CapturedJit(ret, linear, names, expected_input_info)`
def Jit.set_cap(+j: Jit, c: Cap) -> Jit:
  Jit{Jit.has_fxn(j), Jit.cnt(j), Some{c}, Jit.prune(j)}


# jit.py:112 -- `add_linear`, which only appends to `self._linears`
def j_linears_n(xs: List<&2, U32>) -> U32:
  j_n(xs)

# jit.py:114-117 -- `reset()`: `assert self.fxn is not None`, then `cnt = 0` and
# `captured = None`. BOTH fields move and nothing else does; measured CPython
# `(cnt, captured is not None)` goes to `(0, False)`.
def Jit.reset(+j: Jit) -> Jit:
  Jit.of2(Jit.has_fxn(j), Jit.prune(j), 0)

def Jit.reset_refusal(j: Jit) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, Jit.has_fxn(j), None{}, Some{m_reset_arg()})

# jit.py:105-106 -- `assert fxn or captured, "need either a function or a CapturedJit"`
def Jit.init_refusal(+j: Jit) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, Bool.or(Jit.has_fxn(j), Jit.has_cap(j)), None{}, Some{m_need_arg()})

# jit.py:119-121 -- `__reduce__`: `assert self.captured is not None, "can't pickle an
# uncaptured JIT"`, and the payload is `(None, self.captured)`, which IS the
# `initial_cnt(False) == 2` shape.
def Jit.pickle_refusal(j: Jit) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, Jit.has_cap(j), None{}, Some{m_pickle()})

# THE REPLAY ARM'S REFUSALS (jit.py:172 then :174, IN THAT ORDER). The order is
# observable -- a call differing in BOTH names and dtypes raises the
# `expected_names` one -- so `jt_refusal` keeps them as two steps and the gate has
# an `order_names_first` row.
def jt_names_refusal(+c: Cap, +names: List<&2, JName>) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, JName.eqs(Cap.names(c), names), None{},
            Some{m_names(Cap.names(c), names)})

def jt_info_refusal(+ar: O.Arena, +c: Cap, +info: List<&2, InInfo>) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, InInfo.eqs(ar, Cap.info(c), info), None{},
            Some{m_info(ar, Cap.info(c), info)})

def jt_refusal.at(+r: Maybe<&2, String>, ar: O.Arena, c: Cap, info: List<&2, InInfo>) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, Bool.not(has_str(r)), jt_info_refusal(ar, c, info), r)

def jt_refusal(ar: O.Arena, +c: Cap, names: List<&2, JName>, info: List<&2, InInfo>) -> Maybe<&2, String>:
  jt_refusal.at(jt_names_refusal(c, names), ar, c, info)

# jit.py:144 then :145 -- `if not len(self._linears): raise JitError("didn't JIT
# anything!")` comes BEFORE `_check_no_non_tensor_return(ret)`. Measured CPython:
#   TinyJit(lambda a: None)        x3 -> JitError: didn't JIT anything!
#   TinyJit(lambda a: {"k": 5})    x3 -> JitError: didn't JIT anything!
#   TinyJit(lambda a: (a+1.0, 5))  x3 -> JitError: JIT return contains non-Tensor value of type int
# So a function that REALIZES nothing says "didn't JIT anything" and never reaches
# the return check, and `jt_capture_refusal` is that ordering rather than a choice.
def jt_capture_refusal(n_linears: U32, ret: JRet) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, U32.is_zero(n_linears), Some{m_nothing()},
            nr_msg(nr_go(NR_FUEL(), [ret], None{})))

# jit.py:137 -- `if capturing: raise RuntimeError(...)`. The depth is
# `len(capturing)`, and `capturing` is the SEAM (realize.bend lists it as group
# [b]), so the depth is a parameter.
def jt_nesting_refusal(+depth: U32) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, U32.is_zero(depth), None{}, Some{m_nested(depth)})

# ===========================================================================
# SECTION 9 -- `jit_lower` (jit.py:29-38) and the `TinyJit` factory
# (jit.py:180-185). All FIVE steps of `jit_lower` are named and THREE are seams;
# the two VIZ guards are ported because they are the only `if`s in the function.
#
#   @rewrite_group(lambda linear,held_bufs,input_uops,ret=(): f"JIT {pluralize('call', len(linear.src))}")
#   def jit_lower(linear, held_bufs, input_uops):
#     if VIZ: graph_rewrite(linear, PatternMatcher([]), name="View captured linear")
#     linear = linear.substitute({u: UOp.param(i, u.dtype, u.max_numel(), u.device)
#                                for i,u in enumerate(input_uops)}, walk=True)
#     linear = memory_plan_rewrite(linear, held_bufs)
#     linear = compile_linear(linear, beam=getenv("JITBEAM", BEAM.value),
#                             input_uops=input_uops, cache=False)
#     if VIZ: graph_rewrite(linear, PatternMatcher([]), name="View compiled linear")
#     return linear
#
# `@rewrite_group` REGISTERS the function under a name that the rewriter then
# applies it with; `ops.bend`'s `graph_rewrite` has no group parameter, so the
# registration is the seam and `m_group` is the NAME it would register.
def jl_viz(viz: Bool, ar: O.Arena, +lin: U32) -> U32:
  Bool.pick(U32, viz, lin, lin)

# jit.py:180-185 -- two `@overload`s and one body, and the body is a TWO-ARM CHOICE
# on `fxn is None`:
#   def TinyJit(fxn=None, **kwargs): return (lambda f: _TinyJit(f, **kwargs)) if fxn is None else _TinyJit(fxn, **kwargs)
# `@TinyJit` and `@TinyJit(prune=True)` are the same call with one extra argument and
# both arms return a `_TinyJit`. Bend has no decorator syntax, so a decorator IS a
# call at the use site and these are what it calls.
def tiny_jit.of2(prune: Bool, f: U32) -> Jit:
  Jit.of(True{}, prune)

def tiny_jit.of3(f: U32) -> Jit:
  Jit.of(True{}, False{})

# ===========================================================================
# SECTION 10 -- THE SEAMS, each with the owner, the Python line and what the port
# takes instead. A `# TODO(p3)` in the tree means "a phase owns this", not "nobody
# knows".
#
# jit.py:26   `UOp.new_buffer`, `u.store_call`, `run_linear`  -- `_copy_input` runs a
#            one-CALL LINEAR that copies the input. THE PORT keeps the DISK refusal
#            (`m_disk`) and the "is it a written buffer" test
#            (`cap_concrete.go`); the copy itself is the seam.
# jit.py:34   `linear.substitute(..., walk=True)`             -- ops.py:532. THE PORT
#            takes the rewritten LINEAR as a parameter; `jit_lower`'s ORDER is
#            ported (`jl_viz` guards and all).
# jit.py:35   `memory_plan_rewrite`                             -- schedule/memory.py,
#            group [b] in realize.bend's list. Named, not called.
# jit.py:36   `compile_linear`, `getenv("JITBEAM", BEAM.value)`  -- realize.bend lists
#            `compile_linear` as group [b]; `BEAM` is not in `helpers.bend`'s
#            `Flags` (which has four fields: NO_COLOR, DEFAULT_FLOAT, DEFAULT_INT,
#            SUM_DTYPE), so it is a parameter.
# jit.py:57   `link_linear(self._linear, allow_cache=False)`    -- realize.bend group
#            [b]. THE PORT takes `linear` as a FIELD of `Cap`, which is what a
#            `cached_property` means.
# jit.py:66   `get_parameters`, `t.uop.unbind_all()`             -- nn/state.py,
#            ops.py:1044. THE PORT counts symbolic outputs; `sym_ret_n` is the shape
#            with the count at CPython's answer for a static graph, 0.
# jit.py:69   `all_tensors`, `Buffer.is_allocated`, `MultiBuffer` -- device.py. THE
#            PORT keeps `free_skip` and `free_base`, the two tests that are not
#            `Buffer` calls.
# jit.py:81   `b.deallocate()`, `b._base`, `base.allocated_views`  -- device.py.
# jit.py:93   `Tensor.realize(*unrealized_tensors)`              -- tensor.py. THE PORT
#            counts them (`prep_unrealized_n`).
# jit.py:96   `u.base` and `u.base.realized`                     -- ops.py:785 and the
#            Buffer's. THE PORT takes `bases` and gates the DEDUP.
# jit.py:98   `u.substitute({u.base: UOp(Ops.NOOP)}, extra_pm=mop_cleanup)`,
#            `u.unbind_all()`, `u.dtype`, `u.device`             -- ops.py:532, ops.py:1044,
#            mixin/movement.py `mop_cleanup`, ops.py:890.
# jit.py:99   `merge_dicts` IS PORTED in helpers.bend:1372; the
#            `dict(v.unbind() for v in ... if isinstance(v, UOp))` half is the seam
#            and `var_vals` is a `Map` because Bend's `Map` is string-keyed.
# jit.py:137  `capturing`                                       -- realize.bend group [b].
# jit.py:145  `_check_no_non_tensor_return` IS PORTED, and so is the ORDER of
#            jit.py:144 before it, which is observable.
# jit.py:161  `_buf_or_none`, `all_tensors`, `held_bufs`        -- device.py.
# jit.py:123  `__get__` -> `functools.partial(self.__call__, obj)` -- instance-method
#            support; a `def` in Bend is already a method on its record.
# ops.py:269  `UOp.__repr__` = `uop.render.pretty_print`         -- `ii_flat` answers
#            the FLAT case exactly (`UOp(Ops.NOOP, arg=None, src=())`) and the rest
#            is `None{}`, because CPython's own answer for a view is MULTILINE and
#            two-space-indented and is a RENDERER question.
# ops.py:41   `ParamArg.__repr__`                               -- an `Arg` repr; the
#            `ii_arg_none` test is how this port says "this message is not
#            reproducible for a non-`ANone` arg".
# ops.py      `Variable.__repr__`                               -- a dataclass repr over
#            a `VariableAxis`; `ii_vars_repr` answers `()` and `None{}`.
# jit.py:116  `reset` asserts `fxn is not None`; the assert's MESSAGE is ported
#            (`m_reset_arg`) and the assert itself is the port's `Maybe`.
# jit.py:185  `**kwargs`                                        -- `prune` is the only
#            keyword, and `tiny_jit.of2(prune, f)` is the spelling.
# jit.py:149  `del self._linears`, `del big_linear, held_bufs`   -- Python's GC hints
#            for the pre-planning graph. In Bend an arena is AFFINE and dropping the
#            last reference frees it, so the `del`s are the absence of a use and
#            there is nothing to port.
# ===========================================================================
# SECTION 11 -- THE GATE.
#
# Both lanes print these rows and they must be byte-identical. The CPython oracle
# is `.agents/slop/probe/jit_o3.py` plus the measurements quoted in the header;
# every row either has an oracle or is named BEND-ONLY in the list at the foot.
#
# THE FIXTURE. One arena, interned in order, holding everything the rows read: a
# NOOP (what `u.substitute({u.base: UOp(Ops.NOOP)})` leaves behind), three BUFFERs,
# a PROGRAM whose `ProgramInfo` names slot 0 as an OUT and slot 1 as an IN, a CALL
# over them, an UNSHARD over one of them, and THREE linears over the same CALL --
# 2, 9 and 10 srcs -- because jit.py:72's threshold is `>= 10` and a fixture with
# only a PASSING case cannot see a threshold that is off by one. `execs9` is the
# row that says 9 is not enough and `execs10` is the row that says 10 is.
type Fx is Data:
  Fx{ar: O.Arena, noop: U32, b0: U32, b1: U32, call: U32, uns: U32,
     lin2: U32, lin9: U32, lin10: U32}

def Fx.ar(x: Fx) -> O.Arena:
  match x:
    case Fx{ar, noop, b0, b1, call, uns, lin2, lin9, lin10}: ar

def Fx.noop(x: Fx) -> U32:
  match x:
    case Fx{ar, noop, b0, b1, call, uns, lin2, lin9, lin10}: noop

def Fx.b0(x: Fx) -> U32:
  match x:
    case Fx{ar, noop, b0, b1, call, uns, lin2, lin9, lin10}: b0

def Fx.b1(x: Fx) -> U32:
  match x:
    case Fx{ar, noop, b0, b1, call, uns, lin2, lin9, lin10}: b1

def Fx.call(x: Fx) -> U32:
  match x:
    case Fx{ar, noop, b0, b1, call, uns, lin2, lin9, lin10}: call

def Fx.uns(x: Fx) -> U32:
  match x:
    case Fx{ar, noop, b0, b1, call, uns, lin2, lin9, lin10}: uns

def Fx.lin2(x: Fx) -> U32:
  match x:
    case Fx{ar, noop, b0, b1, call, uns, lin2, lin9, lin10}: lin2

def Fx.lin9(x: Fx) -> U32:
  match x:
    case Fx{ar, noop, b0, b1, call, uns, lin2, lin9, lin10}: lin9

def Fx.lin10(x: Fx) -> U32:
  match x:
    case Fx{ar, noop, b0, b1, call, uns, lin2, lin9, lin10}: lin10

# nine and ten copies of the CALL, so the two threshold linears have DIFFERENT src
# counts from one another AND from `lin2`. Rule 15: an accumulator fold over a list
# has to say which end it adds to, in a comment, because the type cannot see it --
# and here the COUNT IS the point, so this reads up and APPENDS.
def fx_pad(fuel: Nat, +call: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: acc
    case 1n+p: fx_pad(p, call, List.append(&2, U32, acc, [call]))

# `ParamArg` field for field -- 13 fields, and the device is `S.D1{0}` because
# `UOp.device` is `str|None` (ops.py:890) and "PYTHON" is device 0 in this gate.
def fx_pa(slot: U32, dt: S.Dt, size: U32) -> O.ParamArg:
  O.ParamArg{slot, dt, Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
             False{}, None{}, None{}, False{}, None{}}

def fx_sizes() -> List<&2, H.I64>:
  [H.i64_of_i32(1), H.i64_of_i32(1), H.i64_of_i32(1)]

# `ProgramInfo`'s two size lists are `List<&2, H.I64>` and a LITERAL `[a, b, c]`
# infers `&1`, so the arity has to be in the helper's return type. That is the
# recorded `List.map` arity trap in its rawest form: `&1` and `&2` are DIFFERENT
# types, there is no conversion between them, and the error names the field type
# rather than the arity.
def fx_prog_arg(outs: List<&2, U32>, ins: List<&2, U32>) -> O.Arg:
  O.AProgram{O.ProgramInfo{fx_sizes(), fx_sizes(), Nil{}, Nil{}, outs, ins}}

# THE ARENA. Every `+f = O.UOp.new(O.Found.ar(f), ...)` rebases on the previous
# `Found`, which is `mixin/rand.bend` rule 1: a def that may mint takes the arena as
# an ARGUMENT. A stale arena answers `Arena.bottom()` for an index it does not have
# -- a MISSING node, not a wrong one (movement.bend rule 16) -- and the only symptom
# is a `toposort` of one node, which looks like a bug in the printer.
def fx_make() -> Fx:
  +ar = O.Arena.empty()
  +f0 = O.UOp.new(ar, O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})
  +f1 = O.UOp.new(O.Found.ar(f0), O.OpsBUFFER{}, Nil{}, O.AParam{fx_pa(0, S.single(), 3)}, O.TNone{})
  +f2 = O.UOp.new(O.Found.ar(f1), O.OpsBUFFER{}, Nil{}, O.AParam{fx_pa(1, S.single(), 3)}, O.TNone{})
  +f3 = O.UOp.new(O.Found.ar(f2), O.OpsBUFFER{}, Nil{}, O.AParam{fx_pa(2, S.single(), 4)}, O.TNone{})
  +f4 = O.UOp.new(O.Found.ar(f3), O.OpsPROGRAM{}, Nil{}, fx_prog_arg([0], [1]), O.TNone{})
  +f5 = O.UOp.new(O.Found.ar(f4), O.OpsCALL{}, [O.Found.i(f4), O.Found.i(f1), O.Found.i(f2)],
                  O.ACall{O.CallInfo{None{}, False{}, False{}, S.void()}}, O.TNone{})
  +f6 = O.UOp.new(O.Found.ar(f5), O.OpsUNSHARD{}, [O.Found.i(f1)], O.ANone{}, O.TNone{})
  +f7 = O.UOp.new(O.Found.ar(f6), O.OpsLINEAR{}, [O.Found.i(f5), O.Found.i(f2)], O.ANone{}, O.TNone{})
  +f8 = O.UOp.new(O.Found.ar(f7), O.OpsLINEAR{}, fx_pad(9n, O.Found.i(f5), Nil{}), O.ANone{}, O.TNone{})
  +f9 = O.UOp.new(O.Found.ar(f8), O.OpsLINEAR{}, fx_pad(10n, O.Found.i(f5), Nil{}), O.ANone{}, O.TNone{})
  Fx{O.Found.ar(f9), O.Found.i(f0), O.Found.i(f1), O.Found.i(f2), O.Found.i(f5), O.Found.i(f6),
     O.Found.i(f7), O.Found.i(f8), O.Found.i(f9)}

# --- the specs every replay row compares against. `fx_f32_2` is CPython's
# `expected_input_info` for two float32 tensors on PYTHON, and `fx_i32_2` is the
# same call with int32 arguments, which is the dtype-mismatch oracle at jit.py:174.
def fx_f32_2(+x: Fx) -> List<&2, InInfo>:
  [InInfo.of(Fx.noop(x), Nil{}, S.single(), "PYTHON"), InInfo.of(Fx.noop(x), Nil{}, S.single(), "PYTHON")]

def fx_i32_2(+x: Fx) -> List<&2, InInfo>:
  [InInfo.of(Fx.noop(x), Nil{}, S.int32(), "PYTHON"), InInfo.of(Fx.noop(x), Nil{}, S.int32(), "PYTHON")]

def fx_metal_1(x: Fx) -> List<&2, InInfo>:
  [InInfo.of(Fx.noop(x), Nil{}, S.single(), "METAL")]

def fx_one_view(x: Fx) -> List<&2, InInfo>:
  [InInfo.of(Fx.b1(x), Nil{}, S.single(), "PYTHON")]

# THE DEVICE FIXTURE, TWO ELEMENTS LONG. `fx_metal_1` differs from `fx_f32_2` in
# LENGTH as well as in device, so `info_eq_dev` saw the length first and the device
# comparison was never reached -- mutation M15 (the device dropped from `InInfo.eq`)
# moved NOTHING. One fixture per COMPARED FIELD, not per differing value.
def fx_f32_metal_2(+x: Fx) -> List<&2, InInfo>:
  [InInfo.of(Fx.noop(x), Nil{}, S.single(), "METAL"), InInfo.of(Fx.noop(x), Nil{}, S.single(), "METAL")]

def fx_names_pos() -> List<&2, JName>:
  [Pos{0}, Pos{1}]

def fx_names_kw() -> List<&2, JName>:
  [Kw{"a"}, Kw{"b"}]

def fx_names_xy() -> List<&2, JName>:
  [Kw{"x"}, Kw{"y"}]

def fx_cap(+x: Fx) -> Cap:
  Cap.of(RTensors{1}, Fx.lin2(x), fx_names_pos(), fx_f32_2(x))

def fx_jit(x: Fx) -> Jit:
  Jit.of(True{}, False{})

# --- row helpers. `IO.print` takes a `String` and a `do IO<Unit>` block can only
# BIND an `IO`, so every row is a def and `main` is a list of calls (movement.bend
# rule 5).
def row(k: String, v: String) -> IO(Unit):
  IO.print(String.concat([k, "=", v]))

def row_b(k: String, b: Bool) -> IO(Unit):
  row(k, Bool.show(b))

def row_u(k: String, n: U32) -> IO(Unit):
  row(k, U32.show(n))

def row_m(k: String, m: Maybe<&2, String>) -> IO(Unit):
  row(k, j_str(m))

def fx_sig(x: Fx, u: U32) -> String:
  j_sig(Fx.ar(x), u)

# `pl_replace` GROWS the arena, so its signature must be read off the RETURNED one. A
# gate row that reads it off the fixture's arena answers `Ops.NOOP` -- the arena's
# bottom, because `Arena.node` is total -- and looks like a bug in `prune_linear`
# rather than one in the row. `mixin/rand.bend` rule 1 reached from the reader's side,
# and `movement.bend` rule 16's "a stale arena gives an EMPTY answer not a wrong one".
def fx_sig2(+f: O.Found) -> String:
  j_sig(O.Found.ar(f), O.Found.i(f))

def fx_srcn(x: Fx, u: U32) -> U32:
  j_n(O.Arena.srcs(Fx.ar(x), u))

# THE WHOLE 0..9 MODE LADDER AS ONE STRING. A `case 1:` arm that claims its
# successor, or a ladder switched on the wrong number with a `case _:` cover, is
# invisible to two Bool rows and obvious in nine digits
# (`mixin/rand.bend` rule 2).
def row_modes.go(fuel: Nat, +jit_on: Bool, +n: U32, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+p: row_modes.go(p, jit_on, U32.add(n, 1),
                            List.append(&2, String, acc, [U32.show(jit_mode(jit_on, n))]))

def row_modes(jit_on: Bool) -> String:
  String.join(row_modes.go(10n, jit_on, 0, Nil{}), " ")

# ONE call of the port's `_TinyJit.__call__`, with a MATCHING spec -- the only
# case that reaches jit.py:177's `self.cnt += 1`. `step` is where the WARMUP and
# the CAPTURE are decided and it is three lines because `jit_mode` is three.
def step.set(+j: Jit, c: Cap, refused: Bool, +mode: U32) -> Jit:
  Bool.pick(Jit, Bool.or(refused, U32.is_eq(mode, 1)), j,
            Bool.pick(Jit, U32.is_eq(mode, 2), Jit.set_cap(j, c), j))

def step.of(j: Jit, c: Cap, refused: Bool, mode: U32) -> Jit:
  step.set(Jit.bump(j), c, refused, mode)

# THE FLAG IS A PARAMETER AND NOT A LITERAL. With `JIT=0` CPython NEVER captures
# (measured: `[(1,False),(2,False),(3,False),(4,False),(5,False)]`), and a `step` that
# hardcodes `True{}` makes `trace_off` a byte-copy of `trace_on` -- which is exactly
# what it did on its first run. The byte diff between the two rows is the only thing
# that sees it, because every other row is identical between the two modes.
def step(jit_on: Bool, +j: Jit, c: Cap, refused: Bool) -> Jit:
  step.of(j, c, refused, jit_mode(jit_on, Jit.cnt(j)))

def run.go(fuel: Nat, +jit_on: Bool, j: Jit, +c: Cap) -> Jit:
  match fuel:
    case 0n: j
    case 1n+p: run.go(p, jit_on, step(jit_on, j, c, False{}), c)

def run(jit_on: Bool, j: Jit, +c: Cap, n: U32) -> Jit:
  run.go(U32.to_nat(n), jit_on, j, c)

# THE (cnt, captured) TRACE CPython PRINTS FOR FIVE CALLS. This is the row that
# says a JIT IS NOT A CACHE: the first call is a WARMUP that runs the traced body
# and captures nothing, the second is the CAPTURE, and only the third onwards
# replays. `examples/beautiful_mnist.ts` cannot express this -- it has a
# `captured: string | undefined` and no counter -- which is why the TS twin needs a
# SHAPE string to stand in for a mode.
def trace.one(+k: Jit) -> String:
  String.concat(["(", U32.show(Jit.cnt(k)), ", ", Bool.show(Jit.has_cap(k)), ")"])

def trace.go(fuel: Nat, +jit_on: Bool, j: Jit, +c: Cap, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+p:
      # `+k` is a `let`, not a parameter, and it is the SAME fact: a `let` is affine
      # (`rule 1.1`: "a `let` is affine too"), so handing the walked-forward JIT to
      # both the printer and the self-call needs the `+` on the binder.
      +k: Jit = step(jit_on, j, c, False{})
      trace.go(p, jit_on, k, c, List.append(&2, String, acc, [trace.one(k)]))

def trace(jit_on: Bool, j: Jit, +c: Cap, n: Nat) -> String:
  String.concat(["[", String.join(trace.go(n, jit_on, j, c, Nil{}), ", "), "]"])

# `Prune`'s three answers as one string, so a reversal in one of the two lists and
# not the other is visible as a digit rather than as a count that happens to match.
def prune_row.of(x: Fx, +p: Prune) -> String:
  String.concat(["kept=", U32.show(j_n(Prune.kept(p))), " once=", U32.show(j_n(Prune.once(p))),
                 " need=", U32.show(j_n(Prune.need(p)))])

def prune_row(+x: Fx, lin: U32, needed: List<&2, U32>, sibufs: List<&2, List<&2, U32>>) -> String:
  prune_row.of(x, prune_linear(Fx.ar(x), lin, needed, sibufs))

def j_empty(xs: List<&2, String>) -> Bool:
  List.is_empty(&2, String, xs)

# jit.py:98 replaces the base with `UOp(Ops.NOOP)` and NOTHING else, so the
# substituted view carries no srcs, no arg and therefore no shape. That is the
# STRUCTURAL reason a shape mismatch is not a mismatch here, and it is the whole of
# `ref_shape_is_invisible`. The CPython-ONLY rows beside it are `ref_shape_4elem` and
# `ref_shape_1elem`, both `(3,)`: a four-element call against a three-element capture
# is ACCEPTED and answers three elements, and a one-element call is accepted too. The
# row is named for the claim and not for the number CPython prints, because the port
# has no shape to print.
def ref_shape_drift(+x: Fx) -> Bool:
  Bool.and(ii_flat(Fx.ar(x), Fx.noop(x)), U32.is_zero(fx_srcn(x, Fx.noop(x))))

# `examples/beautiful_mnist.ts:221` -- `${key} was captured with ${captured} and
# called with ${shape}`. THAT is the TS twin's JitError, and it is a DIFFERENT
# message from jit.py:172's: it names the METHOD and the SHAPE where CPython names
# the source text and the argument names. Printed here so the two are one diff.
def ts_shape_msg(key: String, got: String, want: String) -> String:
  String.concat([key, " was captured with ", got, " and called with ", want])

def main() -> IO(Unit):
  +x = fx_make()
  +c = fx_cap(x)
  +j = fx_jit(x)
  do IO<Unit>:
    # ---- 1. THE MESSAGES, byte-exact against CPython
    row("msg_names_pos", JName.reprs(fx_names_pos()))
    row("msg_names_kw", JName.reprs(fx_names_kw()))
    row("msg_names_mismatch", m_names(fx_names_pos(), fx_names_xy()))
    row("msg_dtype_mismatch", m_info(Fx.ar(x), fx_f32_2(x), fx_i32_2(x)))
    row("msg_disk", m_disk())
    row("msg_virtual", m_virtual())
    row("msg_dup", m_dup())
    row("msg_nothing", m_nothing())
    row("msg_nontensor", m_ret("int"))
    row("msg_nested", m_nested(1))
    row("msg_execs10", m_execs(10))
    row("msg_captured", m_captured(12, 1))
    row("msg_pruned", m_pruned(12, 12))
    row("msg_need_arg", m_need_arg())
    row("msg_reset", m_reset_arg())
    row("msg_pickle", m_pickle())
    row("msg_group1", m_group(1))
    row("msg_group2", m_group(2))
    # ---- 2. THE SPEC AND ITS REPR
    row("info_repr_flat", ii_reprs(Fx.ar(x), fx_f32_2(x)))
    row("info_reprs_view", ii_reprs(Fx.ar(x), [InInfo.of(Fx.uns(x), Nil{}, S.single(), "PYTHON")]))
    row("info_one_view", j_str(ii_repr(Fx.ar(x), InInfo.of(Fx.uns(x), Nil{}, S.single(), "PYTHON"))))
    row("info_repr_vars", j_str(ii_repr(Fx.ar(x), InInfo.of(Fx.noop(x), ["n"], S.single(), "PYTHON"))))
    row("dt_repr_f32", ii_dt_repr(S.single()))
    row("dt_repr_i32", ii_dt_repr(S.int32()))
    row("dt_repr_h", ii_dt_repr(S.half()))
    row_b("flat_noop", ii_flat(Fx.ar(x), Fx.noop(x)))
    row_b("flat_view", ii_flat(Fx.ar(x), Fx.uns(x)))
    # ---- 3. SPEC EQUALITY, the half of jit.py:172/:173 that decides whether
    # there is a refusal at all
    row_b("names_eq_pos", JName.eqs(fx_names_pos(), fx_names_pos()))
    row_b("names_eq_kw", JName.eqs(fx_names_kw(), fx_names_kw()))
    row_b("names_eq_len", JName.eqs(fx_names_pos(), [Pos{0}]))
    row_b("names_eq_cross", JName.eqs([Pos{0}], [Kw{"0"}]))
    # THE SAME PAIR WITH THE ARMS SWAPPED. `JName.eq` has TWO cross arms and M14
    # inverted one of them; a fixture that only pins `Pos` on the left is blind to
    # `Kw` on the left. This is the "one fixture per polarity" lesson from
    # `device.bend` applied to a TWO-SCRUTINEE match.
    row_b("names_eq_cross_rev", JName.eqs([Kw{"0"}], [Pos{0}]))
    row_b("names_eq_order", JName.eqs([Pos{0}, Pos{1}], [Pos{1}, Pos{0}]))
    row_b("info_eq_same", InInfo.eqs(Fx.ar(x), fx_f32_2(x), fx_f32_2(x)))
    row_b("info_eq_dt", InInfo.eqs(Fx.ar(x), fx_f32_2(x), fx_i32_2(x)))
    row_b("info_eq_dev", InInfo.eqs(Fx.ar(x), fx_f32_2(x), fx_metal_1(x)))
    row_b("info_eq_dev_only", InInfo.eqs(Fx.ar(x), fx_f32_2(x), fx_f32_metal_2(x)))
    row_b("info_eq_len", InInfo.eqs(Fx.ar(x), fx_f32_2(x), fx_one_view(x)))
    row_b("info_eq_vars", InInfo.eqs(Fx.ar(x), fx_f32_2(x),
      [InInfo.of(Fx.noop(x), ["n"], S.single(), "PYTHON"), InInfo.of(Fx.noop(x), Nil{}, S.single(), "PYTHON")]))
    row_b("info_eq_v", InInfo.eqs(Fx.ar(x), fx_f32_2(x),
      [InInfo.of(Fx.uns(x), Nil{}, S.single(), "PYTHON"), InInfo.of(Fx.noop(x), Nil{}, S.single(), "PYTHON")]))
    # ---- 4. THE REFUSALS, AND THE ORDER OF THE TWO CHECKS
    row_m("replay_ok", jt_refusal(Fx.ar(x), c, fx_names_pos(), fx_f32_2(x)))
    row_m("replay_names_bad", jt_refusal(Fx.ar(x), c, fx_names_xy(), fx_f32_2(x)))
    row_m("replay_dtype_bad", jt_refusal(Fx.ar(x), c, fx_names_pos(), fx_i32_2(x)))
    row_m("order_names_first", jt_refusal(Fx.ar(x), c, fx_names_xy(), fx_i32_2(x)))
    row_u("replay_ok_cnt", Jit.cnt(step(True{}, j, c, False{})))
    row_b("replay_refused_cnt", U32.is_eq(Jit.cnt(step(True{}, j, c, True{})), Jit.cnt(j)))
    row_b("replay_refused_nocap", Bool.not(Jit.has_cap(step(True{}, j, c, True{}))))
    # ---- 5. THE COUNTER AND THE THREE MODES. `modes_on`/`modes_off` are the two
    # halves of the measured CPython pair, `trace_on`/`trace_off` are the two
    # `(cnt, captured)` lists, and `init_*` are jit.py:109's `2 if fxn is None`.
    row_u("init_fxn", initial_cnt(True{}))
    row_u("init_captured", initial_cnt(False{}))
    row("modes_on", row_modes(True{}))
    row("modes_off", row_modes(False{}))
    row("trace_on", trace(True{}, j, c, 5n))
    row("trace_off", trace(False{}, Jit.of(True{}, False{}), c, 5n))
    row_u("reset_cnt", Jit.cnt(Jit.reset(run(True{}, Jit.set_cap(run(True{}, j, c, 3), c), c, 1))))
    row_b("reset_nocap", Bool.not(Jit.has_cap(Jit.reset(run(True{}, j, c, 3)))))
    row_m("reset_refusal", Jit.reset_refusal(Jit.of2(False{}, False{}, 0)))
    row_m("init_refusal", Jit.init_refusal(Jit.of2(False{}, False{}, 0)))
    row_m("pickle_refusal", Jit.pickle_refusal(Jit.of(True{}, False{})))
    row_m("pickle_ok", Jit.pickle_refusal(Jit.set_cap(Jit.of(True{}, False{}), c)))
    row_m("nesting_1", jt_nesting_refusal(1))
    row_m("nesting_0", jt_nesting_refusal(0))
    # ---- 6. THE CAPTURE ARM'S ORDER: jit.py:144 BEFORE jit.py:145
    row_m("capture_zero", jt_capture_refusal(0, RTensors{1}))
    row_m("capture_nontensor", jt_capture_refusal(1, RSeq{[RTensors{1}, ROther{"int"}]}))
    row_m("capture_ok", jt_capture_refusal(1, RTensors{1}))
    # ---- 7. `_check_no_non_tensor_return` (jit.py:42-47)
    row_m("ret_none", nr_msg(nr_go(NR_FUEL(), [RNone{}], None{})))
    row_m("ret_tensors", nr_msg(nr_go(NR_FUEL(), [RTensors{3}], None{})))
    row_m("ret_int", nr_msg(nr_go(NR_FUEL(), [ROther{"int"}], None{})))
    row_m("ret_tuple", nr_msg(nr_go(NR_FUEL(), [RSeq{[RTensors{1}, ROther{"int"}]}], None{})))
    row_m("ret_dict", nr_msg(nr_go(NR_FUEL(), [RSeq{[ROther{"int"}]}], None{})))
    row_m("ret_deep", nr_msg(nr_go(NR_FUEL(), [RSeq{[RTensors{1}, RSeq{[RTensors{1}, ROther{"float"}]}]}], None{})))
    row_m("ret_first_wins", nr_msg(nr_go(NR_FUEL(), [RSeq{[ROther{"int"}, ROther{"float"}]}], None{})))
    # THE ORDER FIXTURE: a sequence with a LATER SIBLING and a CHILD that both offend.
    # Siblings-first (Python's `for item in ret`) answers `int`; children-first answers
    # `float`. A tree with ONE child per node cannot tell the two apart, which is why
    # mutation M10 (the children/siblings swap) moved NOTHING until this row existed.
    row_m("ret_siblings_first", nr_msg(nr_go(NR_FUEL(),
      [RSeq{[ROther{"int"}, RSeq{[ROther{"float"}]}]}], None{})))
    row_m("ret_nested_first", nr_msg(nr_go(NR_FUEL(),
      [RSeq{[RSeq{[ROther{"float"}]}, ROther{"int"}]}], None{})))
    # ---- 8. `_written_uops` (jit.py:62-64), via realize.bend
    row_u("written_n", j_n(cap_written(Fx.ar(x), Fx.lin2(x))))
    row_u("written_n10", j_n(cap_written(Fx.ar(x), Fx.lin10(x))))
    row_b("written_is_b0", Bool.and(U32.is_eq(j_n(cap_written(Fx.ar(x), Fx.lin2(x))), 1),
                                    U32.is_eq(Fx.b0(x),
                                              Maybe.default(&2, U32, List.get(&2, U32, cap_written(Fx.ar(x), Fx.lin2(x)), 0n), 0))))
    # ---- 9. `_copy_input`'s DISK refusal (jit.py:24-27) and `on_disk` (jit.py:78)
    row_b("ondisk_METAL", on_disk(True{}, "METAL"))
    row_b("ondisk_DISK", on_disk(True{}, "DISK:1"))
    row_b("ondisk_tuple", on_disk(False{}, "METAL"))
    row_m("disk_refusal_yes", cap_disk_refusal(Fx.ar(x), c, [Fx.b0(x)], True{}, "DISK:1"))
    row_m("disk_refusal_dev", cap_disk_refusal(Fx.ar(x), c, [Fx.b0(x)], True{}, "METAL"))
    row_m("disk_refusal_unwritten", cap_disk_refusal(Fx.ar(x), c, [Fx.noop(x)], True{}, "DISK:1"))
    row_m("disk_refusal_tuple", cap_disk_refusal(Fx.ar(x), c, [Fx.b0(x)], False{}, "DISK:1"))
    # ---- 10. THE `jit execs` THRESHOLD (jit.py:72) -- 9 is not enough, 10 is, and
    # DEBUG=0 says nothing at either
    row_m("execs9", execs_msg(True{}, Fx.ar(x), Fx.lin9(x)))
    row_m("execs10", execs_msg(True{}, Fx.ar(x), Fx.lin10(x)))
    row_m("execs2", execs_msg(True{}, Fx.ar(x), Fx.lin2(x)))
    row_m("execs10_debug0", execs_msg(False{}, Fx.ar(x), Fx.lin10(x)))
    # ---- 11. `prune_linear` (jit.py:14-22). `prune_hit` keeps the two calls that
    # reach slot 0, `prune_all` keeps nothing, `prune_sl` gates the `si.src[1:]`
    # SLICE on a real CALL (3 srcs -> 2), and `prune_sig_*` are the two returned
    # linears with `n= op= nsrc= srcops=` in ONE string.
    row("prune_hit", prune_row(x, Fx.lin2(x), [Fx.b1(x)], [[Fx.b1(x)], Nil{}]))
    row("prune_miss", prune_row(x, Fx.lin2(x), [Fx.b0(x)], [[Fx.b1(x)], Nil{}]))
    row("prune_all", prune_row(x, Fx.lin2(x), Nil{}, [[Fx.b1(x)], Nil{}]))
    row("prune_none", prune_row(x, Fx.lin2(x), Nil{}, [Nil{}, Nil{}]))
    row_u("prune_sl", pl_sibufs_len(Fx.ar(x), Fx.call(x)))
    row_u("prune_sl_buf", pl_sibufs_len(Fx.ar(x), Fx.b0(x)))
    row("prune_sig_kept", fx_sig2(pl_replace(Fx.ar(x), Fx.lin2(x), Prune.kept(prune_linear(Fx.ar(x), Fx.lin2(x), [Fx.b1(x)], [[Fx.b1(x)], Nil{}])))))
    row("prune_sig_once", fx_sig2(pl_replace(Fx.ar(x), Fx.lin2(x), Prune.once(prune_linear(Fx.ar(x), Fx.lin2(x), [Fx.b1(x)], [[Fx.b1(x)], Nil{}])))))
    # ---- 12. `_prepare_jit_inputs` (jit.py:84-102)
    row_u("prep_unshard_ix", prep_input_uop(Fx.ar(x), Fx.uns(x)))
    row_u("prep_b0_ix", Fx.b0(x))
    row_b("prep_unshard_is_src0", U32.is_eq(prep_input_uop(Fx.ar(x), Fx.uns(x)), Fx.b0(x)))
    row_b("prep_plain_identity", U32.is_eq(prep_input_uop(Fx.ar(x), Fx.b0(x)), Fx.b0(x)))
    row_b("prep_any_none", Bool.not(prep_any(Nil{})))
    row_b("prep_any_some", prep_any([False{}, True{}]))
    row_m("prep_virtual_none", prep_virtual_refusal([False{}, False{}]))
    row_m("prep_virtual_some", prep_virtual_refusal([False{}, True{}]))
    row_m("prep_dup_same", prep_dup_refusal([Fx.b0(x), Fx.b0(x)]))
    row_m("prep_dup_diff", prep_dup_refusal([Fx.b0(x), Fx.b1(x)]))
    row_u("prep_unrealized", prep_unrealized_n([True{}, False{}]))
    # ---- 13. jit.py:101's `sorted(..., key=lambda v: v.expr)` -- the ORDER is the
    # gate, and EQUAL keys keeping their input order is what makes it `sorted` and
    # not a set
    row("sort_exprs", String.join(ii_vars(["b", "a", "c"]), ","))
    row("sort_stable", String.join(ii_vars(["b", "a", "b"]), ","))
    row("sort_empty", String.join(ii_vars(Nil{}), ","))
    # ---- 14. `free_intermediates` (jit.py:77-82)
    row_b("free_skip_buf", free_skip(Fx.ar(x), Fx.b0(x), False{}))
    row_b("free_skip_noop", free_skip(Fx.ar(x), Fx.noop(x), True{}))
    row_b("free_skip_base", free_skip(Fx.ar(x), Fx.b0(x), True{}))
    row_b("free_base_free", free_base(0, True{}))
    row_b("free_base_live", free_base(1, True{}))
    row_b("free_base_unalloc", free_base(0, False{}))
    # ---- 15. THE FIXTURE'S OWN SIGNATURE, the four facts plus the src op SEQUENCE
    # in one string (movement.bend rule 14). SWAPPING a movement's two shape args
    # leaves op, nsrc and the src sequence alone, so a gate carrying a count and a
    # root op cannot see it.
    row("sig_call", fx_sig(x, Fx.call(x)))
    row("sig_lin2", fx_sig(x, Fx.lin2(x)))
    row("sig_lin9", fx_sig(x, Fx.lin9(x)))
    row("sig_lin10", fx_sig(x, Fx.lin10(x)))
    row("sig_uns", fx_sig(x, Fx.uns(x)))
    row("srcops_call", j_srcop_str(Fx.ar(x), O.Arena.srcs(Fx.ar(x), Fx.call(x))))
    # ---- 16. THE MEASURED FACT THE HEADER PROMISES. A SHAPE MISMATCH IS NOT A
    # MISMATCH in this tinygrad, and the REASON is a structural fact about the
    # substituted view: it is a bare NOOP with ZERO srcs, so there is nowhere a
    # shape could survive into `expected_input_info`. `ref_shape_drift` is that
    # fact; `ts_shape_msg` is the TS twin's DIFFERENT message for the same
    # situation, printed so the two are visibly different and the difference is a
    # row rather than a footnote.
    row_b("ref_shape_is_invisible", ref_shape_drift(x))
    row_b("ref_view_is_bare", U32.is_zero(fx_srcn(x, Fx.noop(x))))
    row("ts_shape_msg", ts_shape_msg("train_step", "1568/2", "1568/3"))
    # ---- 17. THE COUNTER IS INCREMENTED PER REAL CALL, INCLUDING THE WARMUP
    row_u("cnt_after_1", Jit.cnt(run(True{}, j, c, 1)))
    row_u("cnt_after_2", Jit.cnt(run(True{}, j, c, 2)))
    row_u("cnt_after_5", Jit.cnt(run(True{}, j, c, 5)))
    row_u("cnt_after_0", Jit.cnt(run(True{}, j, c, 0)))
    row_u("linears_n", j_linears_n(Nil{}))
    row_u("sym_ret_n", sym_ret_n(RTensors{1}))
    row_b("jl_viz_id", U32.is_eq(jl_viz(True{}, Fx.ar(x), Fx.lin2(x)), Fx.lin2(x)))
    row_b("prune_hit_t", pr_hit([Fx.b0(x)], [Fx.b0(x)]))
    row_b("prune_hit_f", pr_hit([Fx.b0(x)], [Fx.b1(x)]))
    row_b("ii_vars_eq_t", ii_vars_eq(["n"], ["n"]))
    row_b("ii_vars_eq_f", ii_vars_eq(["n"], ["m"]))
    row_b("ii_dt_eq_f", ii_dt_eq(S.single(), S.half()))
    row_b("ii_vars_empty", j_empty(Nil{}))

# ===========================================================================
# THE MEASURED MUTATION TABLE. Reproduce with
#     python3 .agents/slop/probe/mutate.py jit
# which applies each substitution below to a COPY, re-runs `--check-only` AND the
# interpreted lane, and diffs the rows against this file's output. 23 mutations, 137
# rows, and the two lanes agree at every one of them.
#
# WHAT EACH COLUMN IS. `rows` is the SET of printed rows whose value changed, so a
# localised mutation names its own row and a mutation three fixtures deep names three.
# The table is not one-row-per-bug and it is not a coverage claim.
#
#   M1  jt_refusal: the `expected_names` check dropped           2  order_names_first replay_names_bad
#   M2  jt_refusal: the `expected_input_info` check dropped      1  replay_dtype_bad
#   M3  jit_mode: `cnt == 1` arms the EAGER branch                2  modes_on trace_on
#   M4  jit_mode: the `not JIT` guard loses to `cnt`              2  modes_off trace_off
#   M5  Jit.bump: `captured` dropped (THE CACHE BUG)             1  trace_on
#   M6  initial_cnt: `2 if fxn is None else 0` flipped           9  init_fxn init_captured cnt_after_*
#                                                                          replay_ok_cnt trace_on trace_off
#   M7  execs_thresh: `>= 10` becomes `>= 11`                     1  execs10
#   M8  on_disk: the `DISK` prefix test inverted                 4  ondisk_DISK ondisk_METAL disk_refusal_*
#   M9  prep_dup_refusal: the comparison inverted                2  prep_dup_same prep_dup_diff
#   M10 nr_next: the CHILDREN go before the siblings             1  ret_nested_first
#   M11 nr_first: the first offender does not stick              3  ret_first_wins ret_siblings_first ret_nested_first
#   M12 srt_ins: `is_lt` becomes `is_le`                        0  <-- BLIND, and BY CONSTRUCTION
#   M13 ii_dt_eq: the dtype NAME dropped                        2  info_eq_dt replay_dtype_bad
#   M14 JName.eq: `Kw == Pos` accepted                           1  names_eq_cross_rev
#   M15 InInfo.eq: the DEVICE dropped                            1  info_eq_dev_only
#   M16 cw_step: the `Ops.CALL` filter dropped                  4  written_n written_n10 written_is_b0 disk_refusal_yes
#   M17 pl_step: `needed |= si_bufs` removed                     1  prune_hit
#   M18 pl_step: the two arms swapped (kept <-> once)            4  prune_hit prune_miss prune_all prune_none
#   M19 prep_pick: the UNSHARD unwrap removed                    2  prep_unshard_ix prep_unshard_is_src0
#   M21 free_base: `allocated_views == 0` becomes `!= 0`         2  free_base_free free_base_live
#   M22 free_skip: the `not Ops.BUFFER` arm inverted             2  free_skip_noop free_skip_base
#   M23 m_names: the `=` specifier ADDED to `names`              3  msg_names_mismatch replay_names_bad order_names_first
#   M24 m_group: the plural space dropped                        2  msg_group1 msg_group2
#
# ---------------------------------------------------------------------------
# THE ONE BLIND SPOT, and it is a STRUCTURAL one rather than a missing fixture, so the
# honest response is to say so rather than to go looking for a row.
#
# M12 flips `String.is_lt` to `String.is_le` in the insertion sort, which is the ONE
# character that makes the sort STABLE. It moves nothing, and it could not move
# anything: stability is a property of the ORDER OF EQUAL KEYS, and two equal `String`s
# are the same string, so `List<&2, String>` has no observation that distinguishes a
# stable sort from an unstable one. Every fixture of the right length answers the same
# list either way. The sort's callers are `Variable.expr` strings, which are DISTINCT,
# and for distinct keys `is_lt` and `is_le` agree -- so the mutation is not merely
# unobserved, it is INERT for this port's data. Making it observable needs a value type
# with observable identity (an `Arg` index, a `U32`), and `ii_vars` has none. Recorded
# rather than papered over, and `sort_stable` is still a row because it pins the ANSWER
# even though it cannot pin the property that produced it.
#
# ---------------------------------------------------------------------------
# FOUR BUGS THIS GATE CAUGHT ON ITS OWN FIRST RUN, which is the number the table is
# really for. Each one compiled, printed, and was WRONG:
#
#   * `Jit.bump` went through `Jit.of2`, which starts from `None{}`, so `captured` did
#     not survive `self.cnt += 1`. `trace_on` printed
#     `[(1,False),(2,True),(3,False),(4,False),(5,False)]` against CPython's
#     `[(1,False),(2,True),(3,True),(4,True),(5,True)]` -- the shape of a CACHE, not a
#     JIT. That is M5, and it is the mutation this table exists to keep dead.
#   * `prep_dup_refusal` tested `is_eq` where jit.py:97 tests `!=`, so it raised on the
#     DISTINCT bases and passed on the repeated ones. `prep_dup_same` and
#     `prep_dup_diff` are two fixtures for one comparison, which is
#     `device.bend`'s "a mutation that moves nothing is information about the GATE"
#     with the polarity written down.
#   * `srt_ins` dropped the list TAIL in both arms, so `ssort(["b","a","c"])` answered
#     `c`. One element survived out of three and nothing said so. The row that saw it
#     was the one that prints the ANSWER, not a boolean.
#   * `m_names` spelled `!= names=` where jit.py:172 spells `!= {names}`. The CPython
#     byte diff caught it and no Bend-level row could: `=` DEBUG SPECIFIERS ARE NOT A
#     CONVENTION, and this file's two mismatch messages are INCONSISTENT with each
#     other four lines apart. That is the argument for the third lane in one sentence.
#
# ---------------------------------------------------------------------------
# THE CPYTHON LANE, and what it is worth. `.agents/slop/probe/jit_oracle.py jit` prints
# 34 rows; 22 of them are also rows here and all 22 are GREEN
# (`python3 .agents/slop/probe/oracle_diff.py /tmp/jit_i.txt x jit` ->
# `SHARED=22 GREEN=22 RED=0`). The remaining 115 rows are BEND-ONLY and they are the
# rows about the substrate: arena signatures, the `O.Arena` fixture, `prune_linear`'s
# partition, the `_written_uops` walk, the spec-EQUALITY matrix, the `Maybe`-rendering
# rows and the `ii_repr` seams. They are listed here rather than filtered, because
# `mixin/creation.bend` rule 8's rule is "a row with no oracle is a BEND-ONLY row and
# it belongs in a NAMED LIST, not in a silent filter", and the list is:
#
#   THE FOUR FACTS AND THE SIGNATURES (motion.bend rule 14 -- `n= op= nsrc= srcops=`
#   in ONE string, because a gate carrying a count and a root op cannot see a swapped
#   movement's two shape args):  sig_call sig_lin2 sig_lin9 sig_lin10 sig_uns
#   srcops_call
#   THE SPEC EQUALITY MATRIX (one row per COMPARED FIELD, which is what M13/M14/M15
#   asked for and did not have):     names_eq_pos names_eq_kw names_eq_len
#   names_eq_cross names_eq_cross_rev names_eq_order info_eq_same info_eq_dt info_eq_dev
#   info_eq_dev_only info_eq_len info_eq_vars info_eq_v
#   THE MESSAGE BUILDERS CPython CANNOT REPRODUCE (an `assert`'s text, a seam's
#   spelling):  msg_disk msg_virtual msg_dup msg_nothing msg_nontensor msg_execs10
#   msg_need_arg msg_reset msg_pickle
#   THE `Maybe`-RENDERED ROWS (all of which print `unprintable` when the answer is
#   absent, which is the shared-value hole `creation.bend` rule 8 generalises to):
#   replay_ok pickle_ok nesting_0 capture_ok ret_none ret_tensors execs9 execs2
#   execs10_debug0 prep_virtual_none prep_dup_diff ondisk_tuple disk_refusal_dev
#   disk_refusal_unwritten disk_refusal_tuple info_one_view info_repr_vars
#   info_reprs_view
#   THE COUNTS AND PREDICATES:  written_n written_n10 init_fxn init_captured modes_on
#   modes_off reset_cnt reset_nocap reset_refusal init_refusal nesting_1 cnt_after_0
#   cnt_after_1 cnt_after_2 cnt_after_5 linears_n sym_ret_n jl_viz_id prune_hit_t
#   prune_hit_f ii_vars_eq_t ii_vars_eq_f ii_dt_eq_f ii_vars_empty ref_shape_is_invisible
#   ref_view_is_bare ts_shape_msg flat_noop flat_view
#   THE `prune_linear` PARTITION AND ITS TWO REPLACED LINEARS:  prune_hit prune_miss
#   prune_all prune_none prune_sl prune_sl_buf prune_sig_kept prune_sig_once
#   THE `_prepare_jit_inputs` PREDICATES:  prep_unshard_ix prep_b0_ix
#   prep_unshard_is_src0 prep_plain_identity prep_any_none prep_any_some
#   prep_virtual_some prep_unrealized
#   THE SORT:  sort_exprs sort_stable sort_empty
#   `free_intermediates`:  free_skip_buf free_skip_noop free_skip_base free_base_free
#   free_base_live free_base_unalloc
#   THE RET WALK:  ret_int ret_tuple ret_dict ret_deep ret_first_wins ret_siblings_first
#   ret_nested_first
#   THE CAPTURE-ARM ORDER:  capture_zero capture_nontensor
