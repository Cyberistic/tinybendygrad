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

# The UOp repr. CPython's `UOp.__repr__` (ops.py:273) is `pretty_print(self)`, and
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
# TODO(p3) tinybendygrad/LAWS/spec.bend:75  Dt.nm -- BLOCKED. needs a `dt_nm` / `nm_of(Dt)` reader for the `nm: String` field of `Dt{pri, bits, cls, nm}` (`LAWS/spec.bend:77`). MEASURED, no `def dt_nm` / `nm_of` / `nm` exists; the port's `dn_gate` (`LAWS/spec.bend:853`) is an unrelated debug gate. The field is THERE, the reader is NOT.