# realize.bend -- tinygrad/engine/realize.py.
#
# THE REALIZATION DRIVER, and the first unit in the port whose subject is not a
# rewrite. `realize.py` answers one question -- "a scheduled LINEAR is lowered,
# compiled and executed; what is the PLAN for each CALL in it?" -- and it answers
# it in two halves a reader can easily mistake for one file:
#
#   * the DATA FLOW: which nodes of a CALL are arguments, which are outputs and
#     which are inputs, which buffers a call writes, how a runtime symbol is
#     resolved against the input uops, which calls still need lowering, and the
#     shape of the per-execution context. Pure function of the arena. PORTED.
#   * the FOREIGN EFFECTS: `Device[device].runtime(ast.to_elf())`, the
#     allocator's `_transfer`/`_copyin`/`_copyout`, `Device.synchronize()`,
#     `GlobalCounters`, `perf_counter_us`, tqdm, the worker pool, and
#     `hcq_compile`/`hcq_link`. NOT ported: there is no device and no driver
#     here, so the port takes the handles as PARAMETERS and says what it would
#     do with them.
#
# THE UNIT BRIEF FOR THIS FILE NAMES `run_schedule`, `lower_schedule` and an
# `ExecItem`. NONE OF THEM EXISTS in this checkout. `realize.py` is 296 lines and
# its driver entry points are `compile_linear`, `link_linear`, `run_linear` and
# `time_call`; the type that plays `ExecItem`'s role is the `ExecContext`
# dataclass at realize.py:118. REPORTED, NOT GUESSED AT: the port follows the
# file in front of it. (An older tinygrad had `ExecItem`; this one replaced it
# with the `ExecContext` record, which is why the line count still matched.)
#
# ---------------------------------------------------------------------------
# THE TWO GROUPS, INVENTORIED. `[a]` is ported, `[b]` is the foreign-effect seam.
#
# [a] realize.py:16   get_call_arg_uops     -- `call.src[1:]`, minus VARIABLES
# [a] realize.py:17   get_call_kernel_args  -- ONE ENTRY PER KERNEL PARAM, IN SLOT ORDER
# [a] realize.py:21   get_call_outs_ins     -- (outs, ins) per body op
# [a] realize.py:29   get_call_written_bufs -- outs \ ins, BUFFERs only, deduped
# [a] realize.py:35   get_call_kernels      -- the device list (non-HCQ half)
# [a] realize.py:43   get_call_name         -- the PROGRAM arm
# [a] realize.py:55   estimate_uop          -- the DISPATCH and the byte count
# [a] realize.py:118  ExecContext           -- the dataclass, field for field
# [a] realize.py:128  _resolve              -- PARAM slot lookup, view recursion
# [a] realize.py:132  resolve_params        -- `_resolve` over `get_call_arg_uops`
# [a] realize.py:139  unwrap_multi's `has_dnum` -- the DEVICE-axis toposort fold
# [a] realize.py:204  pm_flatten_linear     -- a RULE
# [a] realize.py:209  pm_validate / _validate -- the rule TABLE and the claim
# [a] realize.py:217  pm_beam               -- a RULE, body fully ported
# [a] realize.py:227  _get_call_to_compile  -- the predicate
# [a] realize.py:237  lower_and_compile's collection -- `toposort` + filter
# [a] realize.py:264  pm_exec               -- the rule TABLE and the dispatch
# [a] realize.py:271  compile_linear        -- the STAGE ORDER
#
# [b] realize.py:57   the HCQInfo arms      -- `call.arg.aux` is DROPPED from
#                                             `CallInfo` in ops.bend
# [b] realize.py:58   Estimates             -- renderer/__init__.py:16, P5
# [b] realize.py:63   first_run_cache       -- a process-global `set[bytes]`
# [b] realize.py:64   track_stats           -- GlobalCounters, DEBUG, PROFILE,
#                                             cpu_events, print, synchronize
# [b] realize.py:107  runtime_cache         -- a process-global dict
# [b] realize.py:108  get_runtime           -- `Device[d].runtime(ast.to_elf())`
# [b] realize.py:116  capturing             -- a process-global list of classes
# [b] realize.py:135  unwrap_multi's bufs   -- `UOp.buffer` needs a REALIZED buffer
# [b] realize.py:141  unwrap_multi's lanes  -- `MultiBuffer`, device.py
# [b] realize.py:145  exec_copy             -- allocators, `_transfer`, `host[:]`
# [b] realize.py:160  exec_kernel           -- the runtime call, `launch_dims`
# [b] realize.py:172  exec_validate         -- a CPU runtime + numpy
# [b] realize.py:183  exec_hcq              -- HCQInfo, timelines, ProfileGraphEntry
# [b] realize.py:224  _compile_kernel       -- `Context(**x[2])`, `to_program`
# [b] realize.py:240  to_program_key / to_program_cache -- codegen, P5
# [b] realize.py:245  the worker pool and tqdm -- a subprocess pool and a bar
# [b] realize.py:259  `linear.substitute`   -- ops.py:532
# [b] realize.py:275  hcq_compile           -- `runtime/support/hcq2.py`, not ported
# [b] realize.py:279  hcq_link              -- same
# [b] realize.py:285  run_linear            -- perf_counter_us, the dispatch loop
# [b] realize.py:287  time_call             -- invalidate_caches, Tensor.ones
#
# ---------------------------------------------------------------------------
# THE FOUR RULE TABLES, AND WHY THERE ARE FOUR DISPATCHES.
#
# `realize.py` builds FOUR `PatternMatcher`s -- `pm_flatten_linear`,
# `pm_validate`, `pm_beam` and `pm_exec` -- and `ops.bend` cannot call a def in
# this file, so each gets its own table and its own scan. `uop/spec.bend` says
# the same in its own header and does it six times. `pm_validate` is Python's
# `PatternMatcher([...]) + pm_flatten_linear`, so its table is the validate rule
# at tag 0 and the SAME flatten body at tag 1, and `va_1` really is `fl_0`.
#
# A GENERIC SCAN IS NOT AVAILABLE, and the reason is worth writing down because
# it is why every scan in the port is copied rather than factored: a shared scan
# would have to hold the rule BODIES, a body is a function value, a function
# value in a datatype field forces `Type` rather than `Data`, and a `Type` table
# is affine so one pass consumes it and the next pass rebuilds it. There are four
# passes here and `graph_rewrite` calls each many times. So the driver per table
# is duplicated. That is the price of not having first-class functions, and
# `uop/spec.bend` pays it too.
#
# THE ESCAPE IS AN ARGUMENT, and this file now uses it. A body cannot live in the
# TABLE, but it can be BUILT BY THE CALLER and handed to the scan as a `Verdict`
# value -- `rz_fire(claim, body)`. So the table keeps what is data (the op set and
# the reject set), `rz_claim` reads the claim off it with `ops.bend`'s own already
# correct `pm_claimed`/`pm_early`, and the one scan is shared. `O.pm_rewrite`
# cannot be that scan, because its `pm_dispatch` is `ops.bend`'s own tag-to-body
# table; see the paragraph at `rz_claim`.
#
# `early_reject` IS A VETO HERE, and that is a DIFFERENCE FROM `spec.bend`, so it
# gets a paragraph. `spec.bend`'s six tables carry four non-empty reject sets and
# all four are implied by their own src-op test, so there the subset test decides
# nothing. Here `pm_flatten_linear` carries `custom_early_reject={Ops.LINEAR}`
# (realize.py:205) and that set is the WHOLE of the rule's claim beyond the op: a
# LINEAR with no LINEAR child is REJECTED and `rewrite` answers `None`, while a
# LINEAR with one fires. `lin_none` and `lin_fired` below are the two rows that
# pin it, and `lin_none` is `9` rather than `1` because `show_v` spells Python's
# `None` as `VSkip`.
#
# THE REJECT SET IS READ OFF `ops.bend`'s `pm_ler`, which folds over EVERY src.
# `spec.bend` reported the two-src version as a real bug there (`te_22`'s four-op
# reject set could never fire); that is fixed upstream of here, so this file has no
# `rz_ler` of its own and nothing to keep in step.
#
# DEF ORDER IS THE OTHER COST, and it is the one Bend imposes that Python does
# not: `def f.b(...)` must be declared BEFORE `def f.a(...)` that calls it, so
# every dotted helper is above the dotted entry point that calls it. Python's
# order is kept everywhere else.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# *** READ THIS BEFORE WRITING A `Bool` SELECTOR IN THIS FILE. ***
#
# `case _:` IS A WILDCARD AND IT DOES NOT DISCRIMINATE. One arm answers for BOTH
# values of the scrutinee, and so -- this is the part that surprised us -- does a
# PAIR of them: `case _:` / `case _:` answers its FIRST arm for both values. A
# `Bool` choice therefore needs its tags named, `case True{}:` and `case False{}:`,
# and so does any other scrutinee that has a tag worth testing (`Some{n}` and not
# `Some{_}`, `Nil{}` and not `_`). A `case _:` is a correct LAST arm, and that is
# the only place one belongs.
#
# This file HAD THAT DEFECT EVERYWHERE: `bl_u.go` and `bl_t.go` were one-armed and
# so returned `f` for both values, and about a dozen entry points (`oi_cf.go2`,
# `gcc_pick.of`, `gk_is_v.g`, `rz_wbuf.take`, `rz_prod.go`, `rz_find.got.hit`,
# `ExecContext.has_timeout.of`, `oi_store.go`, `rz_expr_s.some`, the five `has_*`
# predicates) were ladders written AROUND it -- a chain of one-armed selectors,
# each of which is itself a constant, which is why fixing only `bl_u` turned the
# cascade inside out and made the gate memory-fault partway through `main`.
#
# The wave is converted and the ladder is gone: 21 of the 50 rows moved onto
# CPython's own answers and `--check-only` is green with both lanes identical. Two
# of those 21 were NOT the `Bool` cascade and are recorded at their own defs --
# `pa_bound.of` (a dispatch that answered `None{}` for every `Arg`, so the bound
# map was always empty) and `rz_beam_sink` (a bare index returned from an arena it
# had grown, so the index pointed into an arena its caller did not hold).
#
# What is left as a constant is a constant ON PURPOSE: `rz_isdt.go`,
# `rz_nbytes.mul`, `rz_shape.go` and `rz_nbytes_of0` are the `None` halves of
# sibling matches, reached only from a sibling's `None` arm.
#
# `gate_count` is the row that keeps this honest -- it is the number of rows
# printed, so a row that stops printing cannot pass unnoticed.
# ---------------------------------------------------------------------------
import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
# `M` IS ONE IMPORT LINE AND IT IS THE ONLY REASON `rz_fire` IS NOT THE SITE of
# ops.py:1618's `ret is not uop`: `movement.bend`'s `hop_self` is that clause, it was
# INVERTED once and is fixed now (MEASURED today: `ret_self=1`, `ret_new=0`), and
# `rangeify.bend:2700-2708` is the post-mortem for the local copy that was deleted
# rather than kept. `uop/` does not import `engine/`, so this edge points one way.
import ./../uop/movement.bend as M
def has_cst(m: Maybe<&2, O.Const>) -> Bool:
  match m:
    case Some{_}: True{}
    case _: False{}

def has_str(m: Maybe<&2, String>) -> Bool:
  match m:
    case Some{_}: True{}
    case _: False{}

def has_dev(m: Maybe<&2, S.Dev>) -> Bool:
  match m:
    case Some{_}: True{}
    case _: False{}

def has_u32(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{_}: True{}
    case _: False{}

def has_range(m: Maybe<&2, O.PyRange>) -> Bool:
  match m:
    case Some{_}: True{}
    case _: False{}
# THE TWO SELECTORS every `if` in this file needs, because a `match` may
# scrutinise a PARAMETER and `Bool.and(...)` is a call. `bl_u` picks between two
# U32s; `bl_t` picks between two LISTS, which have to be BUILT before the choice
# because Bend evaluates an argument before the callee branches.
#
# BOTH TAGS ARE NAMED AND THAT IS THE WHOLE TRICK. `case _:` is a WILDCARD and
# matches every value of the scrutinee without discriminating: one arm gives one
# answer for both values, and TWO `case _:` arms give the FIRST arm for both
# values. So a `Bool` choice needs `case True{}:` and `case False{}:`, spelled
# out, and every selector in this file that is written any other way is a
# CONSTANT that folds to its first arm. (Measured: `one(True,7,3)` and
# `one(False,7,3)` both answer 3, and so do both arms of `case _:` / `case _:`;
# `case True{}` / `case False{}` answers 7 and 3.) Every other choice a `Bool`
# makes here is spelled out the same way, at its own entry point.
def bl_u.go(b: Bool, t: U32, f: U32) -> U32:
  match b:
    case True{}: t
    case False{}: f

def bl_u(b: Bool, t: U32, f: U32) -> U32:
  bl_u.go(b, t, f)

def bl_t.go(b: Bool, t: List<&2, U32>, f: List<&2, U32>) -> List<&2, U32>:
  match b:
    case True{}: t
    case False{}: f

def bl_t(b: Bool, t: List<&2, U32>, f: List<&2, U32>) -> List<&2, U32>:
  bl_t.go(b, t, f)

# ===========================================================================
# **************** Helpers ****************
# ===========================================================================
# `call.body` -- ops.py:565, which realize.py reads on lines 22, 39, 48, 58, 76,
# 82, 140, 163, 174 and 289. It is `src[0]` for a CALL and it RAISES otherwise,
# so it is `src[0]` unconditionally here: every caller below already holds a
# CALL, because they all dispatch on `Ops.CALL` or read `call.src[1]`.
type PArg is Data:
  PArg{is_pv: Bool, has_val: Bool, is_alu: Bool, has_vm: Bool, slot: U32, nm: Maybe<&2, String>, dev: Maybe<&2, S.Dev>}

def PArg.of.p(pa: O.ParamArg) -> PArg:
  match pa:
    case O.ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
      PArg{True{}, has_cst(val), O.eq_addr(addrspace, S.Aalu{}), has_range(vmin_vmax), slot, name, device}

def PArg.of(a: O.Arg) -> PArg:
  match a:
    case O.AParam{pa}: PArg.of.p(pa)
    case _: PArg{False{}, False{}, False{}, False{}, 0, None{}, None{}}

# ---------------------------------------------------------------------------
# `PArg` -- THE FACTS OFF A `ParamArg`. `is_bound_var` (ops.py:1023) asks
# `arg.val is not None`; `is_variable` (ops.py:1022) asks `vmin_vmax is not
# None`, `addrspace is ALU` and `_shape == ()`. A `Maybe` is Bend's affine
# handler and can be READ ONCE, so the facts travel in ONE record instead of
# being re-derived from the thirteen-field `ParamArg` at each of the four places
# that need one of them.
# ---------------------------------------------------------------------------
def PArg.is_alu(p: PArg) -> Bool:
  match p:
    case PArg{is_pv, has_val, is_alu, has_vm, slot, nm, dev}: is_alu

def PArg.has_vm(p: PArg) -> Bool:
  match p:
    case PArg{is_pv, has_val, is_alu, has_vm, slot, nm, dev}: has_vm

def PArg.slot(p: PArg) -> U32:
  match p:
    case PArg{is_pv, has_val, is_alu, has_vm, slot, nm, dev}: slot

def PArg.nm(p: PArg) -> Maybe<&2, String>:
  match p:
    case PArg{is_pv, has_val, is_alu, has_vm, slot, nm, dev}: nm

def PArg.dev(p: PArg) -> Maybe<&2, S.Dev>:
  match p:
    case PArg{is_pv, has_val, is_alu, has_vm, slot, nm, dev}: dev

# `x.op is Ops.PARAM and isinstance(x.arg, ParamArg) and x.arg.val is not None`
# -- realize.py:15's filter. The FOURTH conjunct of `is_variable`, `_shape == ()`
# (ops.py:1022, via `marg` and `as_shape`), is NOT PORTED, and `fold.bend`
# already records `marg` as P3 behind `ssimplify`. WALL: `marg`. It is the one
# missing conjunct, and it cannot change the answer for a node that passes the
# other three, because `addrspace is ALU` with a `vmin_vmax` is already the shape
# of a kernel-graph variable.
def PArg.has_val(p: PArg) -> Bool:
  match p:
    case PArg{is_pv, has_val, is_alu, has_vm, slot, nm, dev}: has_val

def PArg.is_pv(p: PArg) -> Bool:
  match p:
    case PArg{is_pv, has_val, is_alu, has_vm, slot, nm, dev}: is_pv

def rz_bound_var.go(ar: O.Arena, self: U32, +p: PArg) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsPARAM{}), Bool.and(PArg.is_pv(p), PArg.has_val(p)))

def rz_bound_var(+ar: O.Arena, +self: U32) -> Bool:
  rz_bound_var.go(ar, self, PArg.of(O.Arena.arg(ar, self)))

# `s.is_variable` -- ops.py:1009: `self.op is Ops.PARAM and self.arg.vmin_vmax is not
# None and self.arg.addrspace is AddrSpace.ALU and self._shape == ()`.
#
# THE PIN's `get_call_arg_uops` FILTERS ON THIS AND NOT ON `is_bound_var`, AND THAT IS
# A CHANGE OF SUBSTANCE AND NOT OF SPELLING: `is_bound_var` IS `is_variable AND
# arg.val is not None`, SO THE OLD FILTER DROPPED ONLY THE BOUND VARIABLES AND LEFT
# AN UNBOUND ONE IN THE ARGUMENT LIST, WHERE `unwrap_multi`'s `bufs = [b.buffer for b
# in resolved]` WOULD THEN ASK A VARIABLE FOR ITS BUFFER.
#
# THE FOURTH CONJUNCT IS NOT PORTED AND THE REASON IS THE SAME ONE THE `is_bound_var`
# PARAGRAPH GIVES: `_shape` IS `marg` (ops.py:353) AND `fold.bend` RECORDS `marg` AS
# P3 BEHIND `ssimplify`. WALL: `marg`. IT CANNOT CHANGE THE ANSWER FOR A NODE THAT
# PASSES THE OTHER THREE, BECAUSE `addrspace is ALU` WITH A `vmin_vmax` IS ALREADY THE
# SHAPE OF A KERNEL-GRAPH VARIABLE.
def rz_is_var.go(ar: O.Arena, self: U32, +p: PArg) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsPARAM{}),
           Bool.and(PArg.is_pv(p), Bool.and(PArg.has_vm(p), PArg.is_alu(p))))

def rz_is_var(+ar: O.Arena, +self: U32) -> Bool:
  rz_is_var.go(ar, self, PArg.of(O.Arena.arg(ar, self)))

# `tuple(s for s in call.src[1:] if not s.is_variable)` -- realize.py:16 AT THE PIN
# `5c2bf39d6c4b`. THE SLICE IS
# UNCONDITIONAL, and it was `Arena.src_without_body`, which is `src[1:]` FOR A CALL AND
# `src` FOR EVERYTHING ELSE. So the port answered one EXTRA entry -- `src[0]` itself, at the
# HEAD -- over every non-CALL. MEASURED on the census fixture: 52 rows of the 974, on 26
# of the 41 non-CALL nodes, and `get_call_arg_uops` is the ONLY thing that moved them.
#
# `Arena.src_from` IS THE SLICE (`ops.bend:1392`), and it is not a new computation: the
# `rz_res` view rebuild at :980 and the `pm_beam` rebuild at :1232 already call it for the
# same `src[1:]` off a CALL. Every caller in this file passes a CALL -- `rz_oi_*`,
# `rz_wbuf`, `resolve_params`, and the file's own `arg_len`/`arg_len_b` rows -- so the two
# spellings agreed everywhere the port is ever RUN, which is why 30 of the 82 candidate
# rows agreed anyway and the other 52 were invisible until a driver asked.
#
# `src_without_body` IS STILL RIGHT for `UOp.src_without_body`'s own readers (the fold in
# `ops.bend`), and it STAYS in `ops.bend` for its six other users. It was simply the wrong
# helper for a function whose body is a slice and not a fold.
def rz_keep.arg(bound: Bool, +s: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  bl_t(bound, acc, List.append(&2, U32, acc, [s]))

def rz_arg_uops.go(+ar: O.Arena, todo: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match todo:
    case Nil{}: acc
    case +s <> t: rz_arg_uops.go(ar, t, rz_keep.arg(rz_is_var(ar, s), s, acc))

def get_call_arg_uops(+ar: O.Arena, call: U32) -> List<&2, U32>:
  rz_arg_uops.go(ar, O.Arena.src_from(ar, call, 1), Nil{})

def rz_body(ar: O.Arena, call: U32) -> U32:
  O.Arena.src(ar, call, 0)

# `nargs` is the one number `get_call_outs_ins`'s `encdec` arm is a function of:
# `tuple(range(1, len(get_call_arg_uops(call))))` -- realize.py:26. It is the length
# of the FILTERED list, NOT of `call.src[1:]`, and the difference is OBSERVABLE: the
# gate's `encdec` call carries a bound var, so the two numbers differ, and the
# `nargs_srcs`/`n_arg_uops` pair is what pins it. Reading the raw src count is the
# bug the first version of this file had; `oi_enc` and `oi_none` are the rows.
def rz_nargs(args: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, args))

# `tuple(range(lo, lo + n))`. A `Nat` countdown is the only countdown a `U32`
# loop gets and the first argument of a self-call has to shrink, so the countdown
# is FIRST and the U32 pair follows it.
def rz_to(+n: Nat, +lo: U32) -> List<&2, U32>:
  match n:
    case 0n: Nil{}
    case 1n+p: lo <> rz_to(p, (U32.add(lo, 1) : U32))

def rz_to_from(n: U32, lo: U32) -> List<&2, U32>:
  rz_to(U32.to_nat(n), lo)

# `x.expr` -- ops.py:1026, `unwrap(self.arg.name)`, read only off a PARAM or a
# BUFFER, and both carry an `AParam`. A missing name answers the empty string,
# which is a distinct key and so makes Python's `bound.get(v.expr, v)` MISS --
# the same answer, because Python's `unwrap(None)` is itself the `None` that can
# never be a bound key.
def rz_expr_s.some(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case _: ""

def rz_expr_s(m: Maybe<&2, String>) -> String:
  rz_expr_s.some(m)

def rz_expr(ar: O.Arena, self: U32) -> String:
  rz_expr_s(PArg.nm(PArg.of(O.Arena.arg(ar, self))))

# `Bnd` is one entry of Python's `bound` dict -- `{s.expr: UOp.const(s.arg.val)
# for s in call.src[1:] if s.is_bound_var}`, realize.py:18. The VALUE is kept as
# the raw `Const` and the CONST NODE is minted at LOOKUP time, so building the
# map does not grow the arena and `Bnd` is a `Data` record that can be threaded
# and read as often as the lookup wants.
type Bnd is Data:
  Bnd{nm: String, cv: O.Const}

def Bnd.nm(b: Bnd) -> String:
  match b:
    case Bnd{nm, cv}: nm

def Bnd.cv(b: Bnd) -> O.Const:
  match b:
    case Bnd{nm, cv}: cv

# Both fields are needed, so both `Maybe`s are read in ONE two-scrutinee match.
# `case _ _ :` is the two-scrutinee wildcard; a single `_` is a parse error here.
def pa_bound.mk(nm: Maybe<&2, String>, val: Maybe<&2, O.Const>, +ar: O.Arena) -> Maybe<&2, Bnd>:
  match nm val:
    case Some{n} Some{v}: Some{Bnd{n, v}}
    case _ _ : None{}

# `O.AParam{pa}` is the only `Arg` constructor carrying a `ParamArg`, and
# `ops.bend` already has `ParamArg.name` and `ParamArg.val` -- so this reads them
# rather than destructuring the thirteen fields a second time. The arm is NAMED
# (`case O.AParam{pa}:`) because a wildcard binds nothing to hand on, and it is
# the ONLY arm there is: every other `Arg` has no `ParamArg` and contributes no
# entry, which is realize.py:18's `s.is_bound_var` filter answering False.
def pa_bound.of(a: O.Arg, +ar: O.Arena) -> Maybe<&2, Bnd>:
  match a:
    case O.AParam{+pa}: pa_bound.mk(O.ParamArg.name(pa), O.ParamArg.val(pa), ar)
    case _: None{}

# `bound` is built by CONSING onto the accumulator and the walk runs over
# `call.src[1:]` -- realize.py:18. A `Maybe` is read ONCE, so the "is there an
# entry" question and the "push it" answer are two defs.
def rz_bound.put(m: Maybe<&2, Bnd>, acc: List<&2, Bnd>) -> List<&2, Bnd>:
  match m:
    case Some{b}: b <> acc
    case _: acc

def rz_bound.go(m: Maybe<&2, Bnd>, acc: List<&2, Bnd>) -> List<&2, Bnd>:
  rz_bound.put(m, acc)

def rz_bound.walk(+ar: O.Arena, todo: List<&2, U32>, acc: List<&2, Bnd>) -> List<&2, Bnd>:
  match todo:
    case Nil{}: acc
    case +s <> t: rz_bound.walk(ar, t, rz_bound.go(pa_bound.of(O.Arena.arg(ar, s), ar), acc))

# `RList` -- `(arena, xs)` as a two-field `Data` record. A pair is a `Type` and
# cannot carry a `+`, and both `get_call_kernel_args` and `_resolve` GROW the arena
# while building their answer, so the answer has to carry the grown arena with it
# or the caller would be holding indices into an arena it does not have. This is
# the same move `ops.bend`'s `Found` makes for a single index.
type RList is Data:
  RList{ar: O.Arena, xs: List<&2, U32>}

def RList.ar(r: RList) -> O.Arena:
  match r:
    case RList{ar, xs}: ar

def RList.xs(r: RList) -> List<&2, U32>:
  match r:
    case RList{ar, xs}: xs

def RList.len(r: RList) -> U32:
  U32.from_nat(List.length(&2, U32, RList.xs(r)))

def RList.at(r: RList, n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, RList.xs(r), U32.to_nat(n)), 99)

# THESE TWO READ THROUGH THE ANSWER'S OWN ARENA and that is the point of them.
# `get_call_kernel_args` MINTS a CONST and `resolve_params` rebuilds a view, so an
# `RList` can hold an index the fixture's arena has never heard of: a gate row that
# pairs such an index with `Land.ar` is reading out of bounds, which is a
# memory fault rather than a wrong number and is not something `--check-only`
# can see. `var_is_const` and `res_slot0` are the rows that would notice.
def RList.is_op(+r: RList, n: U32, want: O.Op) -> Bool:
  O.op_is(RList.ar(r), RList.at(r, n), want)

def RList.is_at(+r: RList, n: U32, dflt: U32) -> Bool:
  U32.is_eq(RList.at(r, n), dflt)

# `x.replace(src=...)` -- ops.py's `replace` keeps op, arg and tag, so this is
# `UOp.new` with the node's OWN three and a new src list.
def rz_replace(+ar: O.Arena, +self: U32, src: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, O.Arena.op(ar, self), src, O.Arena.arg(ar, self), O.Arena.tag(ar, self))

def rz_replace_arg(+ar: O.Arena, +self: U32, arg: O.Arg) -> O.Found:
  O.UOp.new(ar, O.Arena.op(ar, self), O.Arena.srcs(ar, self), arg, O.Arena.tag(ar, self))

# THE LOOKUP FINDS THE ENTRY, AND THE CONST IS MINTED ONCE BY THE CALLER.
# `bound.get(p.expr, ...)` -- realize.py:18 AT THE PIN. Python's `dict.get` returns the
# DEFAULT on a miss and the default IS `v`, so the miss arm is `v`. A LINEAR SCAN
# is the dict: `Map` is Bend's one mutable collection and `bnds` is affine, so it
# is threaded beside the walk rather than stored inside it.
#
# IT RETURNS THE `Bnd` AND NOT THE CONST NODE, and that is load-bearing rather than
# taste. `UOp.const` GROWS the arena and answers an `O.Found`, so a `Bnd` minted
# inside the walk would leave its index pointing into an arena the walk then threw
# away -- a live index into a dead arena, and the gate's next reader of it is an
# out-of-bounds `Arena` access. The walk therefore PURELY selects and
# `rz_find.mint` is the one place the arena grows, and its `O.Found` carries the
# grown arena all the way out.
#
# THE HEAD WINS OVER THE REST, which is what makes the scan first-wins; Python's
# dict keeps the LAST of two equal keys, but the keys are `expr` names and a
# program cannot bind one name twice, so the two agree on every reachable graph.
def rz_find.got(hit: Bool, b: Bnd, acc: Maybe<&2, Bnd>) -> Maybe<&2, Bnd>:
  match hit:
    case True{}: Some{b}
    case False{}: acc

def rz_find.walk(+nm: String, t: List<&2, Bnd>, acc: Maybe<&2, Bnd>) -> Maybe<&2, Bnd>:
  match t:
    case Nil{}: acc
    case +b <> u: rz_find.walk(nm, u, rz_find.got(String.eq(Bnd.nm(b), nm), b, acc))

# `UOp.const(s.arg.val)` -- realize.py:18, minted at the one moment the map is
# USED so that building the map stays a pure fold over the arena.
def rz_find.mint(b: Bnd, +ar: O.Arena) -> O.Found:
  O.UOp.const(ar, Bnd.cv(b))

def rz_find.found(+ar: O.Arena, dflt: U32, m: Maybe<&2, Bnd>) -> O.Found:
  match m:
    case Some{b}: rz_find.mint(b, ar)
    case _: O.Found{ar, dflt}

# `bound.get(name, default)` -- THE PIN'S DICT GET. The bound map is threaded BESIDE
# the walk rather than inside it: it is affine, and a `Data` field cannot carry a
# `List`. The RESULT is an `RList` and not a `List` because the lookup grows the
# arena, so the answer has to carry the arena it was read from -- the same reason
# `rz_res` answers a `Found`.
def rz_find(bnds: List<&2, Bnd>, +ar: O.Arena, nm: String, dflt: U32) -> O.Found:
  rz_find.found(ar, dflt, rz_find.walk(nm, bnds, None{}))

# `self.arg.params` -- THE PIN'S `ProgramInfo.params`, WHICH IS `ops.py:1346`'s THIRD
# FIELD. IT HOLDS **EVERY** PARAM OF THE KERNEL AND NOT ONLY THE ALU ONES: upstream
# `a6addc2d4` CHANGED `if u.op is Ops.PARAM and u.addrspace == AddrSpace.ALU` to
# `if u.op is Ops.PARAM`, RENAMED THE FIELD `vars` -> `params`, AND DELETED
# `ProgramInfo.vals`. `ProgramInfo.from_sink` (ops.py:1358) IS PORTED (`d87143780`), SO
# THE FIELD HOLDS WHAT THE PIN HOLDS: EVERY PARAM, SORTED BY SLOT.
#
# **THE QUESTION THIS DEF ANSWERS IS "EVERY PARAM", AND IT IS NOT A FILTER.** ITS ONE
# CALLER IS `kernel_params` BELOW -- THE PORT OF THE PIN's `UOp.kernel_params`
# (ops.py:1305-1310), WHICH READS `self.arg.params` **IN FULL** -- AND THE PIN's
# `get_call_kernel_args` (realize.py:21-22) HAS A **BUFFER ARM** OVER THAT LIST
# (`call.src[1+p.arg.slot].getaddr(devs)`), SO AN ALU-ONLY LIST HERE WOULD DELETE THE
# ADDRESSES OUT OF THE ANSWER AND LEAVE THE ARM DEAD. THE ALU-NESS IS ASKED **PER
# PARAM**, AT `ka_is_alu` BELOW, OFF THE PARAM's OWN `ParamArg.addrspace` -- WHICH IS
# UPSTREAM's `p.addrspace is AddrSpace.ALU` (realize.py:21). THE OLD UPSTREAM's ALU-ONLY
# `vars` WAS READ BY THE METHOD UPSTREAM DELETED, AND THE PORT OF THAT METHOD IS
# `ops.bend`'s `ProgramInfo.vals`, WHICH READS THE ALU SUBSET (`vals.alu.go`).
#
# **MEASURED, AND THE OPPOSITE OF WHAT A REPORT SAID.** READING THE ALU SUBSET HERE
# MOVES **11 OF THE 19** ROWS OF `gates/realize_kernel_args-gate.py` -- `ka_none_len`
# 1->0, `ka_af_len` 2->1, `ka_bf_len` 2->1, `ka_sh_len` 2->1, AND THEIR COMPANIONS --
# AND CPython ANSWERS THE **BEFORE** VALUES: THE BUFFER ARM IS A `GETADDR` AND THE ALU
# ARM IS THE SLOTLESS `PARAM` (`.agents/slop/rzpvars/oracle.py`, WHICH MIRRORS THE PLANT
# FIXTURE NODE FOR NODE AND INCLUDES THREE PROGRAMS WITH A **BUFFER PARAM AND AN ALU
# PARAM AT ONCE**). A PROOF WITH ONLY ALU PARAMS PROVES THE THING THAT WAS NEVER
# BROKEN.
#
# `prg` IS THE PROGRAM NODE PASSED IN, NOT THE CALL's ARG, AND `AProgram` IS THE ONLY
# `Arg` CONSTRUCTOR CARRYING IT.
def rz_pvars.go(a: O.Arg) -> List<&2, U32>:
  match a:
    case O.AProgram{pi}: O.ProgramInfo.params(pi)
    case _: Nil{}

def rz_pvars(ar: O.Arena, prg: U32) -> List<&2, U32>:
  rz_pvars.go(O.Arena.arg(ar, prg))

# realize.py:18 is the SAME UNCONDITIONAL `call.src[1:]` as :15, so it is the same slice
# for the same reason. There is no census row here -- `var` is a CALL-only driver -- which
# is the reason this line is worth naming rather than leaving as a copy of :271's mistake.
def rz_bound_map(+ar: O.Arena, call: U32) -> List<&2, Bnd>:
  rz_bound.walk(ar, O.Arena.src_from(ar, call, 1), Nil{})

# ---------------------------------------------------------------------------
# THE PIN'S VARIABLE-BINDING PATH.
#
# `realize.py:16` AT `186fbba2a` WAS `get_call_var_uops`:
#
#     bound = {s.expr: UOp.const(s.arg.val) for s in call.src[1:] if s.is_bound_var}
#     return [bound.get(v.expr, v) for v in prg.arg.vars]
#
# upstream `a6addc2d4` ("buffers and args in any input order", 2026-10-14) REPLACED IT
# WITH `get_call_kernel_args` (`realize.py:17` AT THE PIN `5c2bf39d6c4b`):
#
#     bound = {s.expr: UOp.const(s.arg.val) for s in call.src[1:] if s.is_bound_var}
#     return [bound.get(p.expr, p.replace(arg=replace(p.arg, slot=-1))).ccast(p.dtype)
#             if p.addrspace is AddrSpace.ALU else
#             call.src[1+p.arg.slot].getaddr(devs) for p in prg.kernel_params]
#
# THE TWO ARE NOT THE SAME FUNCTION UNDER TWO NAMES. THE OLD ONE ANSWERED ONE ENTRY
# PER VARIABLE, OUT OF `ProgramInfo.vars` -- THE ALU PARAMS ONLY -- AND A BOUND ONE
# BECAME A CONST AND AN UNBOUND ONE STAYED ITSELF. THE NEW ONE ANSWERS ONE ENTRY PER
# KERNEL PARAM, IN SLOT ORDER, AND A PARAM MAY BE A BUFFER, IN WHICH CASE THE ENTRY IS
# THE ADDRESS OF THE CALL's ARGUMENT AT THAT SLOT.
#
# THE ORDER IS THE SLOT ORDER, AND THAT IS THE WHOLE OF "buffers and args in any input
# order": `call.src[1+p.arg.slot]` IS THE CALL's ARGUMENT **AT THAT SLOT**, WHATEVER
# ORDER THE CALLER PASSED THE ARGUMENTS IN. THE OLD `exec_kernel` READ `resolved[i]`
# -- THE `i`th ENTRY OF THE FILTERED LIST -- WHERE `i` CAME FROM `arg.globals`, WHICH
# ARE SLOTS, SO A BUFFER BEHIND A DROPPED ARGUMENT WAS READ AT THE WRONG INDEX.
# ---------------------------------------------------------------------------

# `self.src[1].src` -- THE LINEAR'S CHILDREN. THE PIN RAISES IndexError ON A PROGRAM
# WITH FEWER THAN TWO SRCS AND THE PORT ANSWERS WITH THE `ProgramInfo` HALF ALONE:
# WALL, and it is a REAL one, because the pin only ever calls this on a COMPILED
# program (`codegen/__init__.py:503`'s `pm_to_program` gives a PROGRAM four srcs) and
# a COMPILED PROGRAM's LINEAR CARRIES NO PARAM CHILDREN UNLESS THE KERNEL IS AN IMAGE
# ONE (`ops.py:1307`'s own comment). THE PLANT FIXTURE BELOW GIVES EVERY PROGRAM IT
# EXERCISES THE PIN's TWO-SRC SHAPE, SO THE PIN ANSWERS THERE AND THE TWO AGREE.
def kp_lin_srcs.go(one: Bool, +ar: O.Arena, prg: U32) -> List<&2, U32>:
  match one:
    case True{}: Nil{}
    case False{}: O.Arena.srcs(ar, O.Arena.src(ar, prg, 1))

def kp_lin_srcs(+ar: O.Arena, +prg: U32) -> List<&2, U32>:
  kp_lin_srcs.go(U32.is_le(O.Arena.nsrc(ar, prg), 1), ar, prg)

# `u.op is Ops.PARAM`
def kp_is_param(ar: O.Arena, x: U32) -> Bool:
  O.op_is(ar, x, O.OpsPARAM{})

def kp_keep_param(ar: O.Arena, +x: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  bl_t(kp_is_param(ar, x), List.append(&2, U32, acc, [x]), acc)

def kp_lin_params.go(+ar: O.Arena, todo: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match todo:
    case Nil{}: acc
    case +x <> t: kp_lin_params.go(ar, t, kp_keep_param(ar, x, acc))

def kp_lin_params(+ar: O.Arena, +prg: U32) -> List<&2, U32>:
  kp_lin_params.go(ar, kp_lin_srcs(ar, prg), Nil{})

# `p.arg.slot` -- THE PIN'S SORT KEY AND ITS LOOKUP KEY.
def kp_slot(ar: O.Arena, x: U32) -> U32:
  PArg.slot(PArg.of(O.Arena.arg(ar, x)))

# `{u.arg.slot for u in params}` -- THE SLOTS THE LINEAR'S PARAMS ALREADY COVER.
def kp_covers(+ar: O.Arena, todo: List<&2, U32>, +s: U32) -> Bool:
  match todo:
    case Nil{}: False{}
    case +h <> t: Bool.or(U32.is_eq(kp_slot(ar, h), s), kp_covers(ar, t, s))

# `params += [p for p in self.arg.params if p.arg.slot not in {u.arg.slot for u in params}]`
def kp_keep_info(keep: Bool, +acc: List<&2, U32>, x: U32) -> List<&2, U32>:
  bl_t(keep, List.append(&2, U32, acc, [x]), acc)

def kp_uncovered.go(+ar: O.Arena, +lin: List<&2, U32>, todo: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match todo:
    case Nil{}: acc
    case +x <> t:
      s = kp_slot(ar, x)
      kp_uncovered.go(ar, lin, t, kp_keep_info(Bool.not(kp_covers(ar, lin, s)), acc, x))

def kp_uncovered(+ar: O.Arena, +lin: List<&2, U32>, info: List<&2, U32>) -> List<&2, U32>:
  kp_uncovered.go(ar, lin, info, Nil{})

# `params = [u for u in self.src[1].src if u.op is Ops.PARAM]` AND THEN THE
# `ProgramInfo` HALF, CONCATENATED IN THAT ORDER.
def kp_merge.go(lin: List<&2, U32>, todo: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match todo:
    case Nil{}: acc
    case +x <> t: kp_merge.go(lin, t, List.append(&2, U32, acc, [x]))

def kp_merge(+lin: List<&2, U32>, unc: List<&2, U32>) -> List<&2, U32>:
  kp_merge.go(lin, unc, lin)

# `sorted(params, key=lambda p: p.arg.slot)` -- A STABLE INSERTION SORT. PYTHON's
# `sorted` IS STABLE AND THE PIN's ORDER IS THE SLOT ORDER, AND THE STABILITY IS
# LOAD-BEARING FOR THE ONE CASE WHERE TWO PARAMS SHARE A SLOT (`ops.py:1307`: "the
# LINEAR keeps two IMAGE params of one slot in order"). AN ENTRY GOES AFTER EVERY
# ENTRY WHOSE SLOT IS <= ITS OWN, WHICH IS WHAT "STABLE" MEANS.
# THE HEAD's SLOT AGAINST `sx`. AN EMPTY LIST SAYS `False`, WHICH IS RIGHT: THERE IS
# NO HEAD TO GO BEFORE, SO THE ENTRY IS APPENDED.
def kp_le(ar: O.Arena, todo: List<&2, U32>, sx: U32) -> Bool:
  match todo:
    case Nil{}: False{}
    case +h <> _: U32.is_le(kp_slot(ar, h), sx)

def kp_insert(todo: List<&2, U32>, +acc: List<&2, U32>, le: Bool, +ar: O.Arena, +sx: U32, +x: U32) -> List<&2, U32>:
  match todo:
    case Nil{}: List.append(&2, U32, acc, [x])
    case +h <> +t:
      match le:
        case True{}: kp_insert(t, List.append(&2, U32, acc, [h]), kp_le(ar, t, sx), ar, sx, x)
        case False{}: List.append(&2, U32, List.append(&2, U32, acc, [x]), h <> t)

def kp_sort.go(todo: List<&2, U32>, +acc: List<&2, U32>, +ar: O.Arena) -> List<&2, U32>:
  match todo:
    case Nil{}: acc
    case +x <> t: kp_sort.go(t, kp_insert(acc, Nil{}, kp_le(ar, acc, kp_slot(ar, x)), ar, kp_slot(ar, x), x), ar)

# `prg.kernel_params` -- ops.py:1305-1310 AT THE PIN.
#
# WHAT IT NEEDS FROM `ProgramInfo.from_sink`, **WHICH IS PORTED** (`d87143780`): THE
# `params` FIELD MUST HOLD **EVERY** PARAM OF THE KERNEL, NOT ONLY THE ALU ONES, AND
# SORTED BY SLOT. THE PORT SORTS ANYWAY, SO THE SECOND HALF IS NOT A REQUIREMENT, AND
# THE FIRST IS MET: `from_sink` FILLS `params` WITH `if u.op is Ops.PARAM: _params.append(u)`
# (ops.py:1366) -- EVERY PARAM -- AND `rz_pvars` ABOVE READS THE LIST IN FULL. **SO THE
# DEBT THIS BLOCK RECORDED IS PAID, AND `kernel_params` IS NOW THE PIN's FUNCTION.**
def kernel_params(+ar: O.Arena, +prg: U32) -> List<&2, U32>:
  +lin = kp_lin_params(ar, prg)
  kp_sort.go(kp_merge(lin, kp_uncovered(ar, lin, rz_pvars(ar, prg))), Nil{}, ar)

# `p.replace(arg=replace(p.arg, slot=-1))` -- THE SLOTLESS VAR READ. THE PIN SPELLS IT
# `slot=-1` AND THE PORT's `ParamArg.slot` IS A `U32`, SO THE PORT SPELLS IT
# `ops.bend`'s OWN `ParamArg.no_slot()` -- WHICH IS THE SAME VALUE, AND WHICH
# `ops.bend:1447` SAYS ONCE FOR THE WHOLE TREE.
def ka_slotless.pa(+ar: O.Arena, +self: U32, +pa: O.ParamArg) -> O.Found:
  match pa:
    case O.ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
      O.UOp.new(ar, O.Arena.op(ar, self), O.Arena.srcs(ar, self),
                O.AParam{O.ParamArg{O.ParamArg.no_slot(), dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}},
                O.Arena.tag(ar, self))

def ka_slotless.go(+ar: O.Arena, +self: U32, a: O.Arg) -> O.Found:
  match a:
    case O.AParam{+pa}: ka_slotless.pa(ar, self, pa)
    case _: O.Found{ar, self}

def ka_slotless(+ar: O.Arena, +self: U32) -> O.Found:
  ka_slotless.go(ar, self, O.Arena.arg(ar, self))

# `p.dtype` -- THE PARAM's DTYPE. A FRESH READ: `ParamArg` IS AFFINE, SO THE
# SLOTLESS REBUILD AND THIS CANNOT BOTH READ THE SAME `ParamArg`.
def ka_dtype.go(a: O.Arg) -> S.Dt:
  match a:
    case O.AParam{pa}: O.ParamArg.dtype(pa)
    case _: S.void()

def ka_dtype(+ar: O.Arena, +p: U32) -> S.Dt:
  ka_dtype.go(O.Arena.arg(ar, p))

# `p.addrspace is AddrSpace.ALU`
def ka_is_alu(+ar: O.Arena, +p: U32) -> Bool:
  PArg.is_alu(PArg.of(O.Arena.arg(ar, p)))

# THE ALU ARM: `bound.get(p.expr, p.replace(arg=replace(p.arg, slot=-1))).ccast(p.dtype)`
#
# THE `.ccast(p.dtype)` IS NOT A NO-OP ON THE BOUND ARM. THE BOUND VALUE IS A CONST
# WHOSE DTYPE IS THE DEFAULT (`dtypes.from_py`), AND `ccast` REBUILDS IT AT THE
# PARAM's DTYPE: `UOp.const(val, int32)` IS `CAST/1<-CONST/1`, BECAUSE THE `.cast`
# INSIDE `UOp.const` FOLDS AWAY ONLY AT THE WEAK DTYPES. ON THE UNBOUND ARM IT IS A
# NO-OP, BECAUSE `p.dtype == p.dtype` AND `cast` RETURNS `self`.
#
# THE HIT AND THE MISS ARE TOLD APART BY THE OP: THE HIT IS THE CONST `rz_find`
# MINTS AND THE MISS IS THE SLOTLESS PARAM. A PARAM IS NEVER A CONST.
def ka_alu.go(is_const: Bool, +ar3: O.Arena, +hit: O.Found, +p: U32) -> O.Found:
  match is_const:
    case True{}: O.UOp.cast(ar3, O.Found.i(hit), ka_dtype(ar3, p))
    case False{}: hit

def ka_alu(+ar: O.Arena, bnds: List<&2, Bnd>, +p: U32) -> O.Found:
  +slotless = ka_slotless(ar, p)
  +ar2 = O.Found.ar(slotless)
  +hit = rz_find(bnds, ar2, rz_expr(ar2, p), O.Found.i(slotless))
  +ar3 = O.Found.ar(hit)
  ka_alu.go(O.op_is(ar3, O.Found.i(hit), O.OpsCONST{}), ar3, hit, p)

# THE BUFFER ARM: `call.src[1+p.arg.slot].getaddr(devs)`. THE SLOT IS THE LOOKUP KEY
# AND NOT THE POSITION, AND THAT IS THE WHOLE OF "buffers and args in any input
# order": `call.src[1+slot]` IS THE CALL's ARGUMENT AT THAT SLOT.
def ka_buf(+ar: O.Arena, +call: U32, +p: U32, +dev: S.Dev) -> O.Found:
  +s = O.Arena.src(ar, call, U32.add(1, kp_slot(ar, p)))
  O.UOp.getaddr(O.Arena.budget(ar), ar, s, dev)

def ka_step.go(is_alu: Bool, +ar: O.Arena, bnds: List<&2, Bnd>, +call: U32, +dev: S.Dev, +p: U32) -> O.Found:
  match is_alu:
    case True{}: ka_alu(ar, bnds, p)
    case False{}: ka_buf(ar, call, p, dev)

def ka_step(+ar: O.Arena, bnds: List<&2, Bnd>, +call: U32, +dev: S.Dev, +p: U32) -> O.Found:
  ka_step.go(ka_is_alu(ar, p), ar, bnds, call, dev, p)

def ka_put(+r: RList, +f: O.Found) -> RList:
  RList{O.Found.ar(f), List.append(&2, U32, RList.xs(r), [O.Found.i(f)])}

def ka_step2(+r: RList, +bnds: List<&2, Bnd>, +call: U32, +dev: S.Dev, +p: U32) -> RList:
  ka_put(r, ka_step(RList.ar(r), bnds, call, dev, p))

def ka_go(todo: List<&2, U32>, +r: RList, +bnds: List<&2, Bnd>, +call: U32, +dev: S.Dev) -> RList:
  match todo:
    case Nil{}: r
    case +p <> t: ka_go(t, ka_step2(r, bnds, call, dev, p), bnds, call, dev)

# THE PIN's FUNCTION, `realize.py:17` AT `5c2bf39d6c4b`. THE DEVICE IS A PARAMETER
# BECAUSE THE PIN TAKES `devs` AND THE PORT's `S.Dev` IS ONE DEVICE: `ops.bend`'s
# `ADev` HOLDS A SINGLE `S.Dev` AND THERE IS NO TUPLE SPELLING IN IT.
def get_call_kernel_args(+ar: O.Arena, +call: U32, +prg: U32, +dev: S.Dev) -> RList:
  +bnds = rz_bound_map(ar, call)
  ka_go(kernel_params(ar, prg), RList{ar, Nil{}}, bnds, call, dev)

# `(outs, ins)` -- realize.py:31-27. A pair is a `Type` and every reader would
# have to match a computed value, so it is a two-field `Data` record.
type OutsIns is Data:
  OutsIns{outs: List<&2, U32>, ins: List<&2, U32>}

def OutsIns.outs(o: OutsIns) -> List<&2, U32>:
  match o:
    case OutsIns{outs, ins}: outs

def OutsIns.ins(o: OutsIns) -> List<&2, U32>:
  match o:
    case OutsIns{outs, ins}: ins

def OutsIns.n_out(o: OutsIns) -> U32:
  U32.from_nat(List.length(&2, U32, OutsIns.outs(o)))

def OutsIns.n_in(o: OutsIns) -> U32:
  U32.from_nat(List.length(&2, U32, OutsIns.ins(o)))

def OutsIns.at_out(o: OutsIns, n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, OutsIns.outs(o), U32.to_nat(n)), 99)

def OutsIns.at_in(o: OutsIns, n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, OutsIns.ins(o), U32.to_nat(n)), 99)

def oi_nil() -> OutsIns:
  OutsIns{Nil{}, Nil{}}

# `ast.arg == "encdec"` -- realize.py:26 in `get_call_outs_ins` and realize.py:60 in
# `estimate_uop`, the SAME string test read twice, so it is ONE def here.
def arg_is_encdec(a: O.Arg) -> Bool:
  match a:
    case O.AStr{s}: String.eq(s, "encdec")
    case _: False{}

# `ast.arg.outs, ast.arg.ins` -- realize.py:24, off a PROGRAM's `AProgram`.
def oi_prog(a: O.Arg, n: U32) -> OutsIns:
  match a:
    case O.AProgram{+pi}: OutsIns{O.ProgramInfo.outs(pi), O.ProgramInfo.ins(pi)}
    case _: oi_nil()

# the ONLY arm of `get_call_outs_ins` that computes anything: `(0,)` and
# `range(1, len(get_call_arg_uops(call)))`.
#
# THE CHOICE IS THE ENTRY POINT'S JOB AND BOTH `Bool`s ARE NAMED. `case _:` is a
# wildcard: it answers for BOTH values of the scrutinee, and so does a PAIR of
# them, so the two answers are arms of ONE `match` tagged `True{}` and `False{}`
# -- not two one-armed selectors and not two wildcards.
def oi_cf.is_e(is_e: Bool, n: U32) -> OutsIns:
  match is_e:
    case True{}: OutsIns{[0], rz_to_from((U32.sub(n, 1) : U32), 1)}
    case False{}: oi_nil()

def oi_cf(a: O.Arg, +n: U32) -> OutsIns:
  oi_cf.is_e(arg_is_encdec(a), n)

# `(0,), (1,)` -- realize.py:25.
def oi_store() -> OutsIns:
  OutsIns{[0], [1]}

# realize.py:22-27 in Python's order. The `isinstance(call.arg.aux, HCQInfo)` test
# on line 23 is GONE: `ops.bend` DROPS `CallInfo.aux`, so there is no
# `isinstance` left to write and no arm to take.
def oi_body(op: O.Op, a: O.Arg, n: U32) -> OutsIns:
  match op:
    case O.OpsPROGRAM{}: oi_prog(a, n)
    case O.OpsSTORE{}: oi_store()
    case O.OpsCUSTOM_FUNCTION{}: oi_cf(a, n)
    case _: oi_nil()

def get_call_outs_ins(+ar: O.Arena, +call: U32) -> OutsIns:
  oi_body(O.Arena.op(ar, rz_body(ar, call)), O.Arena.arg(ar, rz_body(ar, call)),
          rz_nargs(get_call_arg_uops(ar, call)))

# realize.py:32 -- `[b.src[0].storage_base if (b := arg_uops[k].storage_base).op is
# Ops.MSELECT else b for k in outs if k not in ins]`. The MSELECT half is the
# WALL: `storage_base` (ops.py:801) is a `while` over BITCAST/AFTER/UNSHARD, and
# `uop/spec.bend` already defers it for the same reason. The arg uop is taken as
# it stands and the re-base is recorded rather than faked. A CALL argument is a
# PARAM or a BUFFER, never an MSELECT, so the arm Python would take is this one.
def rz_at(+args: List<&2, U32>, k: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, args, U32.to_nat(k)), 0)

def rz_wbuf.put(is_buf: Bool, +b: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  bl_t(is_buf, List.append(&2, U32, acc, [b]), acc)

# realize.py:32's `if k not in ins` and realize.py:33's `if b.op is Ops.BUFFER`,
# in ONE two-armed `match`: the OUT slot is skipped, and what survives must be a
# BUFFER. `wbuf_p` (PARAM args) and `wbuf_buf` (BUFFER args) are the two rows, and
# the pair is what says both tests ran.
def rz_wbuf.take(skip: Bool, +ar: O.Arena, +b: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match skip:
    case True{}: acc
    case False{}: rz_wbuf.put(O.op_is(ar, b, O.OpsBUFFER{}), b, acc)

def rz_wbuf.step(skip: Bool, +ar: O.Arena, +args: List<&2, U32>, k: U32, acc: List<&2, U32>) -> List<&2, U32>:
  rz_wbuf.take(skip, ar, rz_at(args, k), acc)

# realize.py:33 -- `dedup([b for b in bufs if b.op is Ops.BUFFER])`, so the
# DEDUP is the fold's terminal step and not a separate pass.
def rz_wbuf.walk(+ar: O.Arena, +args: List<&2, U32>, +ins: List<&2, U32>, todo: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match todo:
    case Nil{}: H.dedup_u32(acc)
    case +k <> t: rz_wbuf.walk(ar, args, ins, t, rz_wbuf.step(List.contains(U32, U32.is_eq, ins, k), ar, args, k, acc))

def rz_oi_ins(+ar: O.Arena, +call: U32) -> List<&2, U32>:
  OutsIns.ins(get_call_outs_ins(ar, call))

def rz_oi_outs(+ar: O.Arena, +call: U32) -> List<&2, U32>:
  OutsIns.outs(get_call_outs_ins(ar, call))

def get_call_written_bufs(+ar: O.Arena, +call: U32) -> List<&2, U32>:
  rz_wbuf.walk(ar, get_call_arg_uops(ar, call), rz_oi_ins(ar, call), rz_oi_outs(ar, call), Nil{})

# realize.py:40 -- `if ast.op is Ops.CUSTOM_FUNCTION and ast.arg == "validate":
# return []`, i.e. a validate call enqueues no kernel. The HCQInfo arm ABOVE it
# (realize.py:37-38) is group [b]: `Device[call.arg.aux.device[0]].host` and a
# list comprehension over `call.arg.aux.kernels`, and `aux` is not in `CallInfo`.
def arg_is_validate(a: O.Arg) -> Bool:
  match a:
    case O.AStr{s}: String.eq(s, "validate")
    case _: False{}

# `to_tuple(buf.device)` -- helpers.py, on a `S.Dev`: a `D1` is a one-element
# tuple and a `Dn` is the list. The NAME behind each tag is `helpers.bend`'s DEV
# parse (P6), so what is derivable here is the COUNT and the `D1`/`Dn` shape.
def dev_tags(d: S.Dev) -> List<&2, U32>:
  match d:
    case S.D1{tag}: [tag]
    case S.Dn{tags}: tags

# `to_tuple` of the device is the LIST, and `None` is the empty tuple, so the
# `Maybe` IS the choice and there is no flag to thread.
def gk_dev(m: Maybe<&2, S.Dev>) -> List<&2, U32>:
  match m:
    case Some{d}: dev_tags(d)
    case _: Nil{}

# `[(d, call, None) for d in to_tuple(call.src[1].device)]` -- realize.py:41, the
# non-HCQ half. `uop.device` is a FOLD, but `src[1]` of a CALL is a PARAM or a
# BUFFER, and for those the fold's PARAM arm IS `arg.device` (fold.bend:1045), so
# reading the arg is the same answer with one less store threaded.
def gk_dev.of(src1: U32, +ar: O.Arena) -> List<&2, U32>:
  gk_dev(PArg.dev(PArg.of(O.Arena.arg(ar, src1))))

def gk_body.cf(is_v: Bool, src1: U32, +ar: O.Arena) -> List<&2, U32>:
  match is_v:
    case True{}: Nil{}
    case False{}: gk_dev.of(src1, ar)

def gk_body(op: O.Op, a: O.Arg, src1: U32, +ar: O.Arena) -> List<&2, U32>:
  match op:
    case O.OpsCUSTOM_FUNCTION{}: gk_body.cf(arg_is_validate(a), src1, ar)
    case _: gk_dev.of(src1, ar)

def get_call_kernels(+ar: O.Arena, +call: U32) -> List<&2, U32>:
  gk_body(O.Arena.op(ar, rz_body(ar, call)), O.Arena.arg(ar, rz_body(ar, call)), O.Arena.src(ar, call, 1), ar)

# realize.py:48 -- `if ast.op is Ops.PROGRAM: return ast.src[0].arg.name`. `KernelInfo.name`
# IS ported (ops.bend:1114).
def gn_kernel.go(a: O.Arg) -> Maybe<&2, String>:
  match a:
    case O.AKernel{ki}: Some{O.KernelInfo.name(ki)}
    case _: None{}

def gn_kernel(+ar: O.Arena, +prog: U32) -> Maybe<&2, String>:
  gn_kernel.go(O.Arena.arg(ar, O.Arena.src(ar, prog, 0)))


# ===========================================================================
# **************** Stat ****************
#
# `estimate_uop` (realize.py:55) RETURNS `tinygrad.renderer.Estimates`, and
# `ops.bend`'s `KernelInfo` block already records that field as NOT PORTED for
# the right reason: "Estimates is `tinygrad.renderer`'s cost model, P5. A field
# the port cannot read is a field that would silently always be None." This file
# does not reopen that. What IS ported is the DISPATCH, because the arm chosen is
# a function of the arena and it is what `track_stats` multiplies by the kernel
# count:
#
#   realize.py:57  isinstance(call.arg.aux, HCQInfo)   -> `aux` is DROPPED
#   realize.py:58  PROGRAM -> ast.src[0].arg.estimates -> the field is DROPPED
#   realize.py:59  STORE / encdec -> Estimates(lds=n, mem=n), n = prod(shape) *
#                  call.src[1].dtype.itemsize              -> `rz_nbytes`
#   realize.py:61  otherwise Estimates()                 -> `rz_est_is_copy` False
#
# `rz_est_is_copy` is the SELECTOR `track_stats` needs and the gate pins it: True
# for a copy, False for a kernel, and no `Estimates` value is built anywhere.
# realize.py:60, `if ast.op is Ops.STORE or ast.arg == "encdec"`, as one `match`
# on the op with the arg test only in the arm that leaves the op undecided. The
# `encdec` half is `arg_is_encdec`, the same def `get_call_outs_ins` uses.
def rz_est_is_copy(op: O.Op, a: O.Arg) -> Bool:
  match op:
    case O.OpsSTORE{}: True{}
    case _: arg_is_encdec(a)

def rz_est_of(+ar: O.Arena, +call: U32) -> Bool:
  rz_est_is_copy(O.Arena.op(ar, rz_body(ar, call)), O.Arena.arg(ar, rz_body(ar, call)))

# `prod(call.src[1].shape) * call.src[1].dtype.itemsize` -- realize.py:60. A
# SYMBOLIC dim makes the product a symbol and the whole byte count a `None`:
# `prod` of a symbolic shape is not a number, and answering 0 there would be a
# plausible wrong value rather than a missing one. `Sint` is `SI` (a concrete
# `H.I64`) or `SU` (a uop), so `SU` is the symbolic half and multiplies by the low
# word of `i` when it is `SI{i}`.
#
# THE ACCUMULATOR IS THE ANSWER AND THERE IS NO FLAG. `rz_prod` starts at
# `Some{1}` and every step either multiplies by a concrete dim or answers `None`,
# and `rz_prod.mul` reads the `None` through to the end -- so a symbolic dim IS
# its own propagation and the walk is ONE self-call on ONE decreasing argument,
# the list tail.
#
# A "have I seen a symbolic dim" `Bool` beside the product cannot be: the arm that
# consumes the flag has to call the recursion and the arm that recurses has to
# test the flag, so `step` and `go` are MUTUAL and Bend refuses mutual recursion
# outright. Carrying the answer instead of a flag is what makes the one call site
# possible.
def rz_prod.mul(p: Maybe<&2, U32>, k: U32) -> Maybe<&2, U32>:
  match p:
    case Some{v}: Some{(U32.mul(v, k) : U32)}
    case _: None{}

# `SU` is the symbolic half of `Sint` and answers no number at all; `SI` is a
# concrete `H.I64` and multiplies by its low word.
def rz_prod.dim(h: O.Sint, p: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match h:
    case O.SI{i}: rz_prod.mul(p, H.lo32(i))
    case _: None{}

# THE SHRINKING ARGUMENT IS FIRST. Bend reads a self-call's arguments left to
# right and stops at the first that shrinks, so the list tail has to lead or the
# call reads as not decreasing -- the same rule `rz_to` and `rz_rp` follow.
def rz_prod.fold(+ss: List<&2, O.Sint>, p: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match ss:
    case Nil{}: p
    case h <> t: rz_prod.fold(t, rz_prod.dim(h, p))

def rz_prod_of(m: Maybe<&2, List<&2, O.Sint>>) -> Maybe<&2, U32>:
  match m:
    case Some{ss}: rz_prod.fold(ss, Some{1})
    case _: None{}

def rz_isdt.go(m: Maybe<&2, S.Dt>) -> U32:
  match m:
    case _: 0

def rz_isdt(m: Maybe<&2, S.Dt>) -> U32:
  match m:
    case Some{d}: S.Dt.itemsize(d)
    case _: rz_isdt.go(m)

def rz_nbytes.mul(p: Maybe<&2, U32>, isz: U32) -> Maybe<&1, U32>:
  match p:
    case _: None{}

def rz_nbytes.bytes(p: Maybe<&2, U32>, isz: U32) -> Maybe<&1, U32>:
  match p:
    case Some{v}: Some{(U32.mul(v, isz) : U32)}
    case _: rz_nbytes.mul(p, isz)

def rz_nbytes.it(shp: Maybe<&2, List<&2, O.Sint>>, isz: U32) -> Maybe<&1, U32>:
  match shp:
    case _: rz_nbytes.bytes(rz_prod_of(shp), isz)

# `fold.shape` is a DOUBLE `Maybe`: the outer is "the table has no entry", the
# inner is ops.py's `_shape` returning `None` for a node that has no shape at
# all. `rz_shape` collapses it, because `prod` of "no shape" and `prod` of "no
# entry" are the same answer here: no number.
def rz_shape.go(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case _: None{}

def rz_shape.hit(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case _: rz_shape.go(m)

def rz_shape.some(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case _: rz_shape.hit(m)

def rz_shape.got(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  match m:
    case Some{s}: s
    case _: rz_shape.some(m)

def rz_shape(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> Maybe<&2, List<&2, O.Sint>>:
  rz_shape.got(m)

def rz_nbytes.shp(+fx: F.Folded, self: U32) -> Maybe<&2, List<&2, O.Sint>>:
  rz_shape(F.fold.shape(F.Folded.ar(fx), F.Folded.t(fx), self))

def rz_nbytes(+fx: F.Folded, +self: U32) -> Maybe<&1, U32>:
  rz_nbytes.it(rz_nbytes.shp(fx, self), rz_isdt(F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), self)))

def rz_nbytes_of0(m: Maybe<&1, U32>) -> U32:
  match m:
    case _: 0

def rz_nbytes_or0(m: Maybe<&1, U32>) -> U32:
  match m:
    case Some{v}: v
    case _: rz_nbytes_of0(m)

def rz_nbytes_of(+ar: O.Arena, +call: U32) -> U32:
  rz_nbytes_or0(rz_nbytes(F.folded(ar), O.Arena.src(ar, call, 1)))

# realize.py:50 -- `if ast.op is Ops.CUSTOM_FUNCTION and ast.arg.name == "encdec":
# return colored(f"enc/dec {_uop_sz_to_str(arg_uops[0])}", "yellow")`.
#
# `sym_infer` IS NOT THE DEPENDENCY HERE, AND THE REASON THIS FILE GAVE FOR LEAVING
# THE ARM OUT WAS WRONG. `sym_infer(u, vv)` is `u.sym_infer(vv) if isinstance(u, UOp)
# else u` (ops.py:93), and `prod(uop.shape) * uop.dtype.itemsize` is an INT for a
# concrete shape, so the symbolic half NEVER RUNS. MEASURED on the census's own
# `encdec` node: shape `(16,)`, dtype `i32`, product `64`, an `int` -- so
# `sym_infer(64, {})` is the `else` branch and `_sym_fxn`'s `exec` (ops.py:1168-1179)
# is never reached. What the arm needs is `size_to_str` and `colored`, and BOTH ARE
# PORTED (`helpers.bend:1143` and `helpers.bend:1083`).
#
# `rz_nbytes` IS ALREADY THE `sym_infer` ANSWER AND WAS ALREADY IN THIS FILE: `rz_prod.dim`
# answers `None` for a SYMBOLIC dim, and CPython's `sym_infer` on a symbolic node with
# `var_vals or {}` = `{}` raises `NameError`, so `None` IS the faithful absence and this
# arm needs NO failure channel. That is the whole `sym_infer` story for `get_call_name`.
#
# `arg_uops[0]` IS THE HEAD OF THE FILTERED LIST and NOT `call.src[1]`: `get_call_arg_uops`
# drops bound vars, and MEASURED, the census's `encdec` call carries one, so `src[1]` and
# `arg_uops[0]` are DIFFERENT nodes there. Reading `src[1]` would be a plausible wrong
# size, which is why this goes through `get_call_arg_uops`.
def gn_sz(m: Maybe<&1, U32>) -> Maybe<&2, String>:
  match m:
    case Some{n}: Some{H.colored(H.Flags.defaults(), String.concat(["enc/dec ", H.size_to_str(n)]),
                                H.color_of("yellow"), False{})}
    case _: None{}

# `args[0]`, and an EMPTY list is CPython's `IndexError` -- a shape `None` already is.
def gn_arg0(args: List<&2, U32>) -> Maybe<&2, U32>:
  match args:
    case Nil{}: None{}
    case a <> t: Some{a}

def gn_encdec.sz(m: Maybe<&2, U32>, +ar: O.Arena, +call: U32) -> Maybe<&2, String>:
  match m:
    case Some{a}: gn_sz(rz_nbytes(F.folded(ar), a))
    case _: None{}

def gn_encdec(+ar: O.Arena, +call: U32) -> Maybe<&2, String>:
  gn_encdec.sz(gn_arg0(get_call_arg_uops(ar, call)), ar, call)

def gn_cf.is_e(is_e: Bool, +ar: O.Arena, +call: U32) -> Maybe<&2, String>:
  match is_e:
    case True{}: gn_encdec(ar, call)
    case False{}: None{}

def gn_cf(a: O.Arg, +ar: O.Arena, +call: U32) -> Maybe<&2, String>:
  gn_cf.is_e(arg_is_encdec(a), ar, call)

# realize.py:48/49/50 in Python's order, and the fallthrough is its `raise`, which here
# is `None` -- a STORE answers `None` because `_dev_str` reads a device NAME, and the
# NAME behind a `U32` tag needs a `U32 -> String` table this port has to MINT (P6):
# CPython has no `str -> int` device index to mirror, so there is nothing to inherit
# here either (`device_vocab_holds` measures all six of those facts every run; see
# `uop/spec.bend`'s `is_device` note). WITH THE CENSUS'S `bufs=[]` CPython raises
# `IndexError` at `bufs[0]` before any name is read, and THAT is pinned:
# `realize_graph_census-pins.rows`'s `name_18=raise=IndexError` against `name_18=none`.
def gn_body(op: O.Op, a: O.Arg, +ar: O.Arena, +call: U32) -> Maybe<&2, String>:
  match op:
    case O.OpsPROGRAM{}: gn_kernel(ar, rz_body(ar, call))
    case O.OpsCUSTOM_FUNCTION{}: gn_cf(a, ar, call)
    case _: None{}

def get_call_name(+ar: O.Arena, +call: U32) -> Maybe<&2, String>:
  gn_body(O.Arena.op(ar, rz_body(ar, call)), O.Arena.arg(ar, rz_body(ar, call)), ar, call)

# ===========================================================================
# **************** runtime cache ****************
#
# TODO(p3) realize.py:107  runtime_cache -- a module-level `dict[tuple[bytes,str],
#   Any]`. WALL: there is no `Device` to build a value for it and a Bend program
#   has no process-global mutable store; the arena is the one global this port
#   has and it holds nodes, not ELF runtimes. P6.
# TODO(p3) realize.py:108  get_runtime -- `Device[device].runtime(ast.to_elf())`.
#   WALL: two missing primitives, `Device[...]` and `UOp.to_elf` (ops.py:1316,
#   which ops.bend already lists as P3). The port's version of this call takes
#   the runtime handle as a PARAMETER, which is what `rz_exec` below says about
#   it. P6.
# ===========================================================================

# ===========================================================================
# **************** run linear ****************
#
# TODO(p3) realize.py:116  capturing -- a module-level list of Python CLASSES
#   with an `add_linear` method, commented "put classes with an add_linear method
#   in here". WALL: no first-class type values at all (a function value forces a
#   `Type` field, and a CLASS value has no representation whatsoever), no
#   process-global mutable store, and the code that appends to it (the jit) is
#   P6. P6.
# ===========================================================================
# `ExecContext` -- realize.py:118-126, the dataclass field for field, and the
# thing this file's unit brief calls `ExecItem`. It is a `Type` and not a `Data`
# because `var_vals` is a `dict[str,int]` and a `Map` is Bend's one mutable
# collection: Python's dict FIELD is the same affine object, and `exec_hcq`'s
# `replace(ctx, var_vals={...})` (realize.py:187) is a mutation Python gets for
# free and here has to thread.
type ExecContext is Type:
  ExecContext{var_vals: Map<&1, H.I64>, input_uops: List<&1, U32>, update_stats: Bool, jit: Bool, wait: Bool,
              timeout: Maybe<&1, U32>, cache: Bool}

def ExecContext.of() -> ExecContext:
  ExecContext{Map.new(&1, H.I64), Nil{}, True{}, False{}, False{}, None{}, True{}}

# realize.py:288 -- `ExecContext(var_vals or {}, update_stats=False, wait=True,
# timeout=timeout, cache=False)`, `time_call`'s four overrides in Python's order.
def ExecContext.of_time(update_stats: Bool, wait: Bool, timeout: Maybe<&1, U32>, cache: Bool) -> ExecContext:
  ExecContext{Map.new(&1, H.I64), Nil{}, update_stats, False{}, wait, timeout, cache}

# realize.py:284 -- `ExecContext(var_vals or {}, tuple(inputs), update_stats, jit,
# wait or DEBUG>=2)`: five POSITIONAL arguments, so the two-flag disjunction is
# its own constructor rather than a default.
def ExecContext.of_run(var_vals: Map<&1, H.I64>, inputs: List<&1, U32>, update_stats: Bool, jit: Bool, wait: Bool) -> ExecContext:
  ExecContext{var_vals, inputs, update_stats, jit, wait, None{}, True{}}

def ExecContext.update_stats(c: ExecContext) -> Bool:
  match c:
    case ExecContext{var_vals, input_uops, update_stats, jit, wait, timeout, cache}: update_stats

def ExecContext.jit(c: ExecContext) -> Bool:
  match c:
    case ExecContext{var_vals, input_uops, update_stats, jit, wait, timeout, cache}: jit

def ExecContext.wait(c: ExecContext) -> Bool:
  match c:
    case ExecContext{var_vals, input_uops, update_stats, jit, wait, timeout, cache}: wait

def ExecContext.cache(c: ExecContext) -> Bool:
  match c:
    case ExecContext{var_vals, input_uops, update_stats, jit, wait, timeout, cache}: cache

def ExecContext.timeout(c: ExecContext) -> Maybe<&1, U32>:
  match c:
    case ExecContext{var_vals, input_uops, update_stats, jit, wait, timeout, cache}: timeout

def ExecContext.input_uops(c: ExecContext) -> List<&1, U32>:
  match c:
    case ExecContext{var_vals, input_uops, update_stats, jit, wait, timeout, cache}: input_uops

def ExecContext.n_input(c: ExecContext) -> U32:
  U32.from_nat(List.length(&1, U32, ExecContext.input_uops(c)))

# The `Maybe` IS the choice: `None` is not a timeout and is not zero, so one
# two-armed `match` on it answers both questions and no flag is threaded. This is
# what makes `ctx_timeout` a row about `of()`'s default rather than about the
# reader -- and the reader had been answering False for a `Some` too.
def ExecContext.has_timeout.m(m: Maybe<&1, U32>) -> Bool:
  match m:
    case Some{_}: True{}
    case _: False{}

def ExecContext.has_timeout(c: ExecContext) -> Bool:
  ExecContext.has_timeout.m(ExecContext.timeout(c))

def ExecContext.timeout_or0.m(m: Maybe<&1, U32>) -> U32:
  match m:
    case Some{v}: v
    case _: 0

def ExecContext.timeout_or0(c: ExecContext) -> U32:
  ExecContext.timeout_or0.m(ExecContext.timeout(c))

# ---------------------------------------------------------------------------
# `_resolve` -- realize.py:128-131, as ONE self-recursive def with a NESTED
# `match`.
#
#     if b.op in (Ops.MSELECT, Ops.SHRINK, Ops.BITCAST):
#       return b.replace(src=(_resolve(b.src[0], inputs), *b.src[1:]))
#     if b.op is Ops.MSTACK:
#       return b.replace(src=tuple(_resolve(x, inputs) for x in b.src))
#     return inputs[b.arg.slot] if b.op is Ops.PARAM else b
#
# THE NESTED MATCH IS LOAD-BEARING and this is the first file in the port that
# needed it. Splitting the arm dispatch into a helper is MUTUAL RECURSION -- the
# helper must call `rz_res` to recurse and `rz_res` must call the helper to
# dispatch -- and Bend refuses that outright. Keeping the arm `match` INSIDE the
# fuel `match` leaves exactly ONE call site, so the only recursion left is the
# self-call. `uop/spec.bend`'s drivers never need this because they do not recurse
# into the arena.
#
# The fuel is a `Nat` and comes FIRST because a self-call reads its arguments LEFT
# TO RIGHT and stops at the first that shrinks, so the fuel is what makes the call
# decreasing and everything after it is free. `case 0n` answers the node UNCHANGED,
# so too small a fuel is a MISS and never a wrong value. `rz_res_fuel` is the exact
# bound and it is `Arena.budget`.
#
# ARM 1 (`Ops.MSTACK`) IS NOT PORTED, and the wall is the SAME mutual recursion one
# level up. The arm applies `_resolve` to EVERY src, so it needs a WALK over a
# list, and the walk calls `_resolve` on each element while `_resolve`'s MSTACK arm
# calls the walk. Two shapes were measured and both refused:
#
#   * a `rz_res.ms(todo, ...)` beside `rz_res` -- mutual recursion, refused;
#   * ONE def carrying `(fuel, pending, accumulator, arena, inputs)` -- a self-call
#     must pass a SUBTERM of its own parameter, and the pending list is REBUILT by
#     the step rather than being one, so the check refuses it too.
#
# ONE OF THOSE TWO REFUTATIONS IS NOW MEASURED AND IS WRONG, and the rule behind it
# is stated wrong: a self-call does not need a subterm of its own parameter, it
# needs ONE ARGUMENT THAT SHRINKS, and it reads them LEFT TO RIGHT and stops at the
# first one, so the shrinking argument has to LEAD. `rz_prod.fold` and
# `ka_go` both put the list tail first and both are accepted; with the tail
# last they are refused with "expected a decreasing self-call". So the worklist
# shape the header guessed at -- a LIST TAIL -- is the right answer, and the
# "rebuilt rather than a subterm" objection does not apply to it.
#
# SO WHAT IS LEFT, and it is not the shape, is the ARENA. The walk has to call
# `rz_res` per src, `rz_res` GROWS the arena on a view arm, and each growth has to
# reach the next element and the answer -- which is the same defect just fixed in
# `rz_find` and `rz_beam_sink`, where a bare index was returned from an arena the
# caller did not hold. Here the accumulator is `rz_res`'s OWN parameter and a
# self-call may not rewrite an argument, so the queue needs its own record the way
# `RList` is its own record above. That, plus a fixture: `main_arena` has no MSTACK
# node, so the arm could not be ROWED without adding one, and adding one moves
# `arena_n` and every index after it. Not worth doing inside a fix for the Bool
# selectors.
#
# SO `rz_res` answers an MSTACK UNCHANGED and the gate row is `res_ms_same`: not a
# wrong value, a MISSING one. That direction is the safe one -- an unresolved MSTACK
# leaves the argument pointing at the node the caller already had -- and
# `res_ms_same` is what makes the omission VISIBLE instead of silent.
def rz_res.v(+f: O.Found, +b: U32, +ar: O.Arena) -> O.Found:
  rz_replace(O.Found.ar(f), b, O.Found.i(f) <> O.Arena.src_from(ar, b, 1))

def rz_arm(op: O.Op) -> U32:
  match op:
    case O.OpsMSELECT{}: 0
    case O.OpsSHRINK{}: 0
    case O.OpsBITCAST{}: 0
    case O.OpsMSTACK{}: 1
    case O.OpsPARAM{}: 2
    case _: 3

# `[_resolve(b, inputs) for b in get_call_arg_uops(call)]` -- realize.py:132. It
# walks the FILTERED list, so a bound variable is never resolved; `res_len` is the
# row, and it is what a raw `call.src[1:]` walk gets wrong.
#
# ONE self-call and no `let`, and both are load-bearing. `_resolve` GROWS the arena
# when it rebuilds a view, so the answer is an `RList` and the arena travels with
# it: an index into an arena the caller does not hold is not an answer. And a `let`
# binding the intermediate `Found` would make the append and the arena read TWO
# reads of one affine `let`, so the append is its own def.
def rz_res.at(+inputs: List<&2, U32>, k: U32, dflt: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, inputs, U32.to_nat(k)), dflt)

def rz_res.slot(ar: O.Arena, b: U32) -> U32:
  PArg.slot(PArg.of(O.Arena.arg(ar, b)))

# The op test as a TAG, because `O.Arena.op(ar, b)` is a CALL and a `match` may
# only scrutinise a parameter or a pattern binder.
def rz_res(fuel: Nat, arm: U32, +ar: O.Arena, +inputs: List<&2, U32>, +b: U32) -> O.Found:
  match fuel:
    case 0n: O.Found{ar, b}
    case 1n+p:
      match arm:
        case 0: rz_res.v(rz_res(p, rz_arm(O.Arena.op(ar, O.Arena.src(ar, b, 0))), ar, inputs, O.Arena.src(ar, b, 0)), b, ar)
        case 1: O.Found{ar, b}
        case 2: O.Found{ar, rz_res.at(inputs, rz_res.slot(ar, b), b)}
        case _: O.Found{ar, b}

def rz_rp.put(+r: RList, +inputs: List<&2, U32>, +h: U32, +f: O.Found) -> RList:
  RList{O.Found.ar(f), List.append(&2, U32, RList.xs(r), [O.Found.i(f)])}

def rz_rp.step(fuel: Nat, +r: RList, +inputs: List<&2, U32>, +h: U32) -> RList:
  rz_rp.put(r, inputs, h, rz_res(fuel, rz_arm(O.Arena.op(RList.ar(r), h)), RList.ar(r), inputs, h))

# `+fuel` IS LOAD-BEARING HERE: the arm reads `fuel` twice -- once as the `match`
# scrutinee and once as `rz_rp.step`'s argument -- and the self-call takes `p`.
# Passing `p` to both is refused ("consumed more than once"), and a `let` is not
# available, so `fuel` is the shared one and `p` is the single use.
def rz_rp(+fuel: Nat, +r: RList, +inputs: List<&2, U32>, todo: List<&2, U32>) -> RList:
  match fuel:
    case 0n: r
    case 1n+p:
      match todo:
        case Nil{}: r
        case +h <> t: rz_rp(p, rz_rp.step(fuel, r, inputs, h), inputs, t)

def resolve_params(fuel: Nat, +ar: O.Arena, +call: U32, +inputs: List<&2, U32>) -> RList:
  rz_rp(fuel, RList{ar, Nil{}}, inputs, get_call_arg_uops(ar, call))

# The fuel is `Arena.budget`, which ops.bend derives as `next(ar) + edges(ar)`: one
# turn per node plus one per edge into it, which bounds BOTH walks here exactly.
def rz_res_fuel(ar: O.Arena) -> Nat:
  O.Arena.budget(ar)

# ===========================================================================
# **************** the four rule tables ****************
# ===========================================================================
# THE TABLES ARE `ops.bend`'s SHAPE, AND THE CLAIM IS `ops.bend`'s CODE. The four
# tables below are `PMEntrys` LITERALS and the per-rule bodies are four `Verdict`
# defs -- which is what makes this file shorter than the first draft of it by about
# a hundred lines -- and `rz_claim` reads `op in ops` and `early_reject.issubset`
# off a table entry with `ops.bend`'s own `pm_claimed` and `pm_early`.
#
# WHAT IS NOT `ops.bend`'s IS THE DISPATCH, and it was the last thing standing
# between these four rules and their rows. `O.pm_rewrite` scans a `PMEntrys` and
# then calls `pm_dispatch`, which is `ops.bend`'s OWN tag-to-body table, so it can
# only ever reach `pm_r_sink`, `pm_r_noop` and `pm_r_cast`. The claim was therefore
# computed and then thrown away, and `fl_0`, `va_0`, `va_1` and `beam_0` were dead:
# `lin_fired` and `beam_fired` printed `9` for a rule that fires. The scan is
# `rz_claim` + `rz_fire` and the body travels as an ARGUMENT, which is the escape
# the header's paragraph on first-class functions describes. The paragraph at
# `rz_claim` has the measurement.
#
# `rz_ler` IS NOT NEEDED EITHER. `ops.bend`'s `pm_ler` has already been FIXED to
# fold over EVERY src (`pm_ler.fold` over `List.range(nsrc)`), so the bug
# `uop/spec.bend` reported there -- `te_22`'s four-op reject set could never fire --
# does not apply to the reader these tables use. The header's earlier claim that
# this file needed its own `rz_ler` is WITHDRAWN as of the `pm_ler` fix; the
# mutation table's `pm_ler` row is in `uop/spec.bend`, not here.
#
# `early_reject` IS A VETO HERE, and that is a DIFFERENCE FROM `spec.bend`.
# `spec.bend`'s six tables carry four non-empty reject sets and all four are
# implied by their own src-op test, so there the subset test decides nothing. Here
# `pm_flatten_linear` carries `custom_early_reject={Ops.LINEAR}` (realize.py:204)
# and that set is the WHOLE of the rule's claim beyond the op: a LINEAR with NO
# LINEAR child is REJECTED and `rewrite` answers `None`, while a LINEAR with one
# fires. `lin_none` and `lin_fired` are the two rows that pin it.

# ---------------------------------------------------------------------------
# THE SCAN IS THIS FILE'S, BECAUSE THE BODY IS THIS FILE'S. `O.pm_rewrite` cannot
# be used here: `pm_rewrite` calls `pm_dispatch`, which is `ops.bend`'s OWN
# tag-to-body table -- tag 0 is its SINK rule, tag 1 its NOOP rule, tag 2 its
# CAST rule -- so a `PMEntrys` built in THIS file can only ever reach those three
# bodies, and `fl_0`, `va_0`, `va_1` and `beam_0` are unreachable through it.
# Measured: `O.pm_dispatch(0, ar, <a LINEAR>)` answers `VSkip`, and so does
# `O.pm_rewrite(flatten_table(), ar, <a LINEAR>)`, which is why `lin_fired` and
# `beam_fired` were stuck at `9` for a rule that fires.
#
# WHAT IS REUSABLE IS THE CLAIM. `O.pm_claimed` (`op in ops`) and `O.pm_early`
# (`early_reject.issubset(ler)`) both take a TABLE ENTRY and are already correct,
# so the local scan is those two over one entry plus the `Verdict` the caller has
# already built -- and the body is a value, so it does not have to be held in a
# table at all.
#
# ONE ENTRY IS READ, which is all `flatten_table` and `beam_table` have.
# `validate_table` has two and has no `rewrite` -- `validate_table()` is read by
# `t_va_len` alone -- so nothing here is asked to scan past the first entry.
def rz_tab_ops.go(es: List<&2, O.PMEntry>) -> List<&2, O.Op>:
  match es:
    case e <> _: O.PMEntry.ops(e)
    case _: Nil{}

def rz_tab_ops(ts: O.PMEntrys) -> List<&2, O.Op>:
  rz_tab_ops.go(O.PMEntrys.es(ts))

def rz_tab_rej.go(es: List<&2, O.PMEntry>) -> List<&2, O.Op>:
  match es:
    case e <> _: O.PMEntry.rej(e)
    case _: Nil{}

def rz_tab_rej(ts: O.PMEntrys) -> List<&2, O.Op>:
  rz_tab_rej.go(O.PMEntrys.es(ts))

# Every parameter is read twice -- the table by both field readers, the arena and
# the node by both conjuncts -- so all three are `+`.
def rz_claim(+ts: O.PMEntrys, +ar: O.Arena, +self: U32) -> Bool:
  Bool.and(O.pm_claimed(rz_tab_ops(ts), ar, self), O.pm_early(ts, ar, self, rz_tab_rej(ts)))

def rz_fire(claim: Bool, v: O.Verdict) -> O.Verdict:
  match claim:
    case True{}: v
    case False{}: O.VSkip{}

# ---------------------------------------------------------------------------
# pm_flatten_linear -- realize.py:204-207.
#
#     UPat(Ops.LINEAR, custom_early_reject={Ops.LINEAR}, name="lin"),
#     lambda lin: lin.replace(src=tuple(flatten(c.src if c.op is Ops.LINEAR
#                                              else (c,) for c in lin.src)))
#
# The BODY is a fold over `lin.src` that SPLICES a LINEAR child's children in place
# of the child. It is folded with the same `Nat`-countdown shape as everything else.
# ---------------------------------------------------------------------------
# ONE CHILD'S CONTRIBUTION: `flatten(c.src if c.op is Ops.LINEAR else (c,) for c
# in lin.src)`, realize.py:206. Both candidates are BUILT before the choice,
# because Bend evaluates an argument before the callee branches and
# `O.Arena.srcs(ar, c)` is a call.
def rz_lin.contrib(is_lin: Bool, +ar: O.Arena, +c: U32) -> List<&2, U32>:
  bl_t(is_lin, O.Arena.srcs(ar, c), [c])

def rz_lin.step(is_lin: Bool, +ar: O.Arena, +c: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, acc, rz_lin.contrib(is_lin, ar, c))

def rz_lin.go(todo: List<&2, U32>, +ar: O.Arena, acc: List<&2, U32>) -> List<&2, U32>:
  match todo:
    case Nil{}: acc
    case +c <> t: rz_lin.go(t, ar, rz_lin.step(O.op_is(ar, c, O.OpsLINEAR{}), ar, c, acc))

# THE REWRITTEN NODE, which is what the gate's `lin_nsrc` row measures.
def rz_lin_new(+ar: O.Arena, +self: U32) -> O.Found:
  rz_replace(ar, self, rz_lin.go(O.Arena.srcs(ar, self), ar, Nil{}))

def fl_0(+ar: O.Arena, +self: U32) -> O.Verdict:
  O.pm_when(O.op_is(ar, self, O.OpsLINEAR{}), O.VTrue{})

def flatten_table() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{0, [O.OpsLINEAR{}], [O.OpsLINEAR{}]}]}

# `ar` and `self` are each read by both the claim and the body.
def flatten_rewrite(+ar: O.Arena, +self: U32) -> O.Verdict:
  rz_fire(rz_claim(flatten_table(), ar, self), fl_0(ar, self))

# ---------------------------------------------------------------------------
# pm_validate -- realize.py:209-214. The table is TWO entries because Python's is
# `PatternMatcher([...]) + pm_flatten_linear`, so tag 1 IS tag 0 of the other table.
# The BODY is group [b] and the CLAIM is group [a]: `_validate` mints one shadow
# BUFFER per arg (`UOp.new_buffer`) and one STORE per shadow (`store_call`), and
# both are `TODO(p3)` in ops.bend. `va_claim` is what the pattern actually asserts
# -- a CALL whose `src[0]` is a SINK -- and it is the row that keeps the table
# honest, because a table whose rule is never claimed is indistinguishable from a
# table whose rule fires.
def va_claim(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsCALL{}), O.op_is(ar, O.Arena.src(ar, self, 0), O.OpsSINK{}))

def va_0(+ar: O.Arena, +self: U32) -> O.Verdict:
  O.pm_when(va_claim(ar, self), O.VTrue{})

# `va_1` really is `fl_0`: the SAME flatten body, reached through the second table.
def va_1(+ar: O.Arena, +self: U32) -> O.Verdict:
  fl_0(ar, self)

def validate_table() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{0, [O.OpsCALL{}], Nil{}}, O.PMEntry{1, [O.OpsLINEAR{}], [O.OpsLINEAR{}]}]}

# ---------------------------------------------------------------------------
# pm_beam -- realize.py:217-220, THE ONLY RULE HERE WITH A FULLY PORTED BODY.
#
#     lambda ctx,call,sink: call.replace(src=(sink.replace(arg=replace(sink.arg,
#                                     beam=ctx)), *call.src[1:])) if sink.arg.beam == 0
#                            else None
#
# TWO tests decide it and BOTH are load-bearing, which is what `beam_prog` and
# `beam_skip` in the gate are for: the claim is on `src[0]`'s op being a SINK, and
# the body fires only when that SINK's `beam` is 0. A CALL over a PROGRAM is not
# claimed at all (`beam_prog` -- measured, `want_beam_prog = True`), and a SINK
# that already carries a beam is left alone.
def bm_claim(+ar: O.Arena, +self: U32) -> Bool:
  Bool.and(O.op_is(ar, self, O.OpsCALL{}), O.op_is(ar, O.Arena.src(ar, self, 0), O.OpsSINK{}))

def rz_kernel_beam(a: O.Arg) -> U32:
  match a:
    case O.AKernel{+ki}: O.KernelInfo.beam(ki)
    case _: 0

# `replace(sink.arg, beam=ctx)` -- a `KernelInfo` is four fields and only one moves.
def rz_beam_arg.of(+ki: O.KernelInfo, ctx: U32) -> O.Arg:
  O.AKernel{O.KernelInfo{O.KernelInfo.name(ki), O.KernelInfo.applied_opts(ki),
                          O.KernelInfo.opts_to_apply(ki), ctx}}

# `sink.replace(arg=replace(sink.arg, beam=ctx))`, then
# `call.replace(src=(that, *call.src[1:]))` -- realize.py:219.
def rz_beam_arg(ki: O.KernelInfo, ctx: U32) -> O.Arg:
  rz_beam_arg.of(ki, ctx)

# THE REWRITTEN SINK IS AN `O.Found`, NOT A BARE INDEX, and that is the whole
# reason this arm is written this way. `rz_replace_arg` GROWS the arena and
# answers an `O.Found`; handing back only its index left `bm_new` building the
# new CALL against a DIFFERENT copy of the same arena, one without the new SINK
# in it, so the CALL's `src[0]` pointed at whatever sits at that number in the
# stale arena. `bmnew_src0` is the probe that measured it, and `beam_new` is the
# row it moved.
def rz_beam_sink.go(sink: U32, a: O.Arg, ctx: U32, ar: O.Arena) -> O.Found:
  match a:
    case O.AKernel{+ki}: rz_replace_arg(ar, sink, rz_beam_arg(ki, ctx))
    case _: O.Found{ar, sink}

def rz_beam_sink(+ar: O.Arena, +call: U32, ctx: U32) -> O.Found:
  rz_beam_sink.go(O.Arena.src(ar, call, 0), O.Arena.arg(ar, O.Arena.src(ar, call, 0)), ctx, ar)

def bm_new.call(+sink: O.Found, +call: U32, ctx: U32) -> O.Found:
  rz_replace(O.Found.ar(sink), call,
             List.append(&2, U32, [O.Found.i(rz_beam_sink(O.Found.ar(sink), call, ctx))],
                        O.Arena.src_from(O.Found.ar(sink), call, 1)))

# `ret is not uop` -- ops.py:1618 -- IS `M.hop_self`, APPLIED TO THE ANSWER, and this
# is the site rather than `rz_fire` for TWO reasons both measured. First, the OTHER half
# of the clause (`ret is not None`) IS ALREADY `rz_fire`'s `claim`: a false claim answers
# `VSkip`, and `beam_0`'s `pm_when` answers `VSkip` when `bm_zero` is false, so "absent"
# is dropped today. Second, `rz_fire` HOLDS A `Verdict` AND NO INDEX, and the clause is an
# INDEX COMPARISON -- so it cannot be given to `rz_fire` at all, and the three other tables
# whose bodies are judge-only (`fl_0`, `va_0`, `va_1`, all of which answer `VTrue`/`VFalse`)
# have no answer to compare. `rangeify.bend` says the same thing about where the clause
# belongs -- inside `rewrite`, around `match`, applied ONCE PER TABLE so a body cannot
# forget it -- and `movement.bend`'s `hop_self` is the ONE copy, after its own inversion
# was fixed (MEASURED today: `./bin/bend tinybendygrad/uop/movement.bend` answers
# `ret_self=1` and `ret_new=0`, and `ret_new` is the row that read 1 while the bug was in
# place). `rangeify.bend:2700-2708` is the post-mortem for the local copy that is GONE.
#
# `Hop{ar, ix}` and `O.Found{ar, ix}` ARE THE SAME PAIR under two names, so the clause is
# the shared one with two conversions either side rather than a second `is_eq`.
def bm_hop.of(+f: O.Found) -> M.Hop:
  M.Hop{O.Found.ar(f), O.Found.i(f)}

def bm_hop.back(+h: M.Hop) -> O.Found:
  O.Found{M.hop_ar(h), M.hop_ix(h)}

def bm_hop_self(+f: O.Found, self: U32) -> O.Found:
  bm_hop.back(M.hop_self(bm_hop.of(f), self))

# `call` and `ctx` are each read twice -- once to find the sink and once to
# rebuild the node -- and a parameter Bend allows to be read twice is a `+`.
#
# AND THE CLAUSE IS INSIDE `bm_new` RATHER THAN AROUND IT, because in realize.bend
# `beam_rewrite` is a JUDGE (realize.bend:1657) and `bm_new` is the BODY, so `bm_new` is
# the `rewrite` this table's driver would otherwise be. THE DEFECT THIS FIXES IS
# MEASURED: `pm_beam`'s body is `call.replace(src=(sink.replace(arg=replace(sink.arg,
# beam=ctx)), *call.src[1:]))`, and at `ctx == 0` over a SINK whose `beam` is already 0
# EVERY replacement is the identity, `UOp.new` HASH-CONSES, and the answer IS the input
# node -- which `ops.py:1618` drops and this file did not. `gates/realize_graph_census`
# drove `pm_beam` at ctx 0 AND ctx 7 precisely so the clause has a row; before the fix
# CPython answered `0` and the port answered `1:<the input's own cone>`.
def bm_new(+ar: O.Arena, +call: U32, +ctx: U32) -> O.Found:
  bm_hop_self(bm_new.call(rz_beam_sink(ar, call, ctx), call, ctx), call)

# `# ctx is beam value` -- realize.py:215 -- and the CLAIM. The body additionally
# fires only when `sink.arg.beam == 0`; `bm_zero` is that test and `bm_new` is the
# rewrite, so `beam_fired` is "the claim held AND the beam was 0".
def bm_zero(+ar: O.Arena, +self: U32) -> Bool:
  U32.is_eq(rz_kernel_beam(O.Arena.arg(ar, rz_body(ar, self))), 0)

def beam_0(+ar: O.Arena, +self: U32) -> O.Verdict:
  O.pm_when(Bool.and(bm_claim(ar, self), bm_zero(ar, self)), O.VTrue{})

def beam_table() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{0, [O.OpsCALL{}], Nil{}}]}

# ---------------------------------------------------------------------------
# `_get_call_to_compile` -- realize.py:226-233. The PREDICATE is group [a] and the
# Renderer it returns is group [b], so this answers the ast or `None`.
#
#     if (ast.op is Ops.SINK and isinstance(ast.arg, KernelInfo)) or \
#        (ast.op is Ops.PROGRAM and not (isinstance(ast.arg, ProgramInfo) and
#                                        ast.src[-1].op is Ops.BINARY)):
#       return ast, Device[...].renderer
#     return None
#
# The `isinstance(ast.arg, ProgramInfo)` conjunct is DROPPED: `ops.bend` DROPS
# `ProgramInfo.target`, so a PROGRAM's arg is always an `AProgram` here and the
# test would be vacuously true -- which is the safe direction, because the arm it
# guards only ever REJECTS a PROGRAM whose last src is a BINARY. `gcc_bin` in the
# gate is the row that pins the rejection, and it is a real one.
def gcc_sink.go(op: O.Op, a: O.Arg) -> Bool:
  match op a:
    case O.OpsSINK{} O.AKernel{ki}: True{}
    case _ _: False{}

def gcc_sink(+ar: O.Arena, +ast: U32) -> Bool:
  gcc_sink.go(O.Arena.op(ar, ast), O.Arena.arg(ar, ast))

# `ast.src[-1].op is Ops.BINARY` -- realize.py:230. `nsrc` is 0 for a srcless node
# and then there IS no `src[-1]`, so the empty case answers False rather than
# reading the arena's bottom.
def gcc_prog_bin.of(n: U32, +ast: U32, +ar: O.Arena) -> Bool:
  match n:
    case 0: False{}
    case _: O.op_is(ar, O.Arena.src(ar, ast, (U32.sub(n, 1) : U32)), O.OpsBINARY{})

def gcc_prog_bin(+ar: O.Arena, +ast: U32) -> Bool:
  gcc_prog_bin.of(O.Arena.nsrc(ar, ast), ast, ar)

# THE SECOND DISJUNCT of realize.py:228-230, on the AST and not on the CALL, so
# `not (isinstance(arg, ProgramInfo) and src[-1].op is Ops.BINARY)` is asked
# exactly once and of one node. `gcc_c` (a PROGRAM whose last src IS a BINARY) and
# `gcc_s` (a body that is neither a SINK nor a PROGRAM) are the two rows that make
# BOTH tests load-bearing.
def gcc_pick.bin.go(is_bin: Bool, +ast: U32) -> Maybe<&2, U32>:
  match is_bin:
    case True{}: None{}
    case False{}: Some{ast}

def gcc_pick.bin(+ar: O.Arena, +ast: U32) -> Maybe<&2, U32>:
  gcc_pick.bin.go(gcc_prog_bin(ar, ast), ast)

def gcc_pick.prog.go(op: O.Op, +ar: O.Arena, +ast: U32) -> Maybe<&2, U32>:
  match op:
    case O.OpsPROGRAM{}: gcc_pick.bin(ar, ast)
    case _: None{}

def gcc_pick.prog(+ar: O.Arena, +ast: U32) -> Maybe<&2, U32>:
  gcc_pick.prog.go(O.Arena.op(ar, ast), ar, ast)

def gcc_pick(+ar: O.Arena, +call: U32, is_sink: Bool) -> Maybe<&2, U32>:
  match is_sink:
    case True{}: Some{rz_body(ar, call)}
    case False{}: gcc_pick.prog(ar, rz_body(ar, call))

def _get_call_to_compile(+ar: O.Arena, +call: U32) -> Maybe<&2, U32>:
  gcc_pick(ar, call, gcc_sink(ar, rz_body(ar, call)))

# ===========================================================================
# **************** unwrap_multi ****************
# realize.py:134-143. The MultiBuffer half is group [b]: a `MultiBuffer` is a
# `device.py` type, so "split one argument into its per-device buffers" has
# nothing to ask. The `has_dnum` half is NOT, and it is the half that decides
# whether a lane gets a `_device_num` variable at all:
#
#     has_dnum = any((x.op is Ops.RANGE and x.axis_type is AxisType.DEVICE) or
#                    (x.op is Ops.PARAM and x.arg.name == '_device_num')
#                    for x in call.body.toposort())
#
# THE PIN's FULL EXPRESSION HAS A SECOND CONJUNCT, AND THIS FILE DOES NOT PORT IT:
#
#     has_dnum = ((isinstance(call.body.arg, ProgramInfo) and
#                  any(p.arg.name == '_device_num' for p in call.body.kernel_params)) or
#                 any(... for x in call.body.toposort()))
#
# `a6addc2d4` CHANGED THAT CONJUNCT's READER FROM `call.body.arg.vars` TO
# `call.body.kernel_params`, SO IT IS THE SAME VARIABLE-BINDING PATH AS EVERYTHING ELSE
# ABOVE -- AND `kernel_params` READS `ProgramInfo.params` **IN FULL**, WHICH IS WHAT
# `rz_pvars` ANSWERS (SEE THE BLOCK ABOVE). IT IS NOT PORTED HERE, AND THE REASON IS
# MEASURED RATHER THAN ASSUMED: THE PIN's `UOp.kernel_params` READS `self.src[1].src`,
# AND `call.body` IS AN UNCOMPILED PROGRAM IN EVERY GRAPH THE `dnum_*` ROWS READ, SO THE
# PIN RAISES IndexError THERE. **`ProgramInfo.from_sink` IS PORTED NOW (`d87143780`) AND
# THIS FILE HAS A COMPILED PROGRAM (`main_arena`'s NODE 39, AND `callC` CALLS IT), SO
# THE CONJUNCT IS PORTABLE AND WHAT IS LEFT IS THE ROW: THE FIXTURE's ONLY COMPILED
# PROGRAM CARRIES NO `_device_num` PARAM, AND ADDING ONE MEANS ADDING A NODE TO
# `main_arena`, WHOSE INDEX MAP IS LOAD-BEARING FOR THE CENSUS.** THE ROWS
# `dnum_p`/`dnum_d`/`dnum_n` ARE THE TOPOSORT HALF, AND THEY AGREE WITH
# `gates/realize_graph_census-oracle.py`'s OWN `dnum_sig`, WHICH IS A TRANSCRIPTION OF
# THE SAME HALF -- SO A FAITHFUL PORT OF THE CONJUNCT WOULD NEED THAT ORACLE RE-DERIVED.
#
# TODO(p3) realize.py:135  unwrap_multi's `bufs = [b.buffer for b in resolved]` --
#   `UOp.buffer` ASSERTS `arg.buffer is not None`, i.e. the buffer is REALIZED, and
#   realization is the allocator. WALL: no allocator. P6.
# TODO(p3) realize.py:141  unwrap_multi's `lanes` -- `max(len(b.bufs) for b in bufs
#   if isinstance(b, MultiBuffer))` and the `zip(*per_lane)` transposing. WALL:
#   `MultiBuffer` is `device.py`, P6, and `zip` truncates where a `List.get`
#   answers `None`. P6.
# ===========================================================================
def rz_pa_name.go(pa: O.ParamArg) -> Maybe<&2, String>:
  O.ParamArg.name(pa)

def rz_pa_name(a: O.Arg) -> Maybe<&2, String>:
  match a:
    case O.AParam{pa}: rz_pa_name.go(pa)
    case _: None{}

def rz_is_dnum.got(m: Maybe<&2, String>) -> Bool:
  match m:
    case Some{s}: String.eq(s, "_device_num")
    case _: False{}

def rz_is_devnum(a: O.Arg) -> Bool:
  rz_is_dnum.got(rz_pa_name(a))

def rz_is_devrng.ax(a: O.Arg) -> Bool:
  match a:
    case O.ARange{ids, at}: O.eq_axis(at, O.AXIS_DEVICE{})
    case _: False{}

def rz_dnum_x.rng(op: O.Op, a: O.Arg) -> Bool:
  match op:
    case O.OpsRANGE{}: rz_is_devrng.ax(a)
    case _: False{}

def rz_dnum_x.num(op: O.Op, a: O.Arg) -> Bool:
  match op:
    case O.OpsPARAM{}: rz_is_devnum(a)
    case _: False{}

def rz_dnum_x.any(+op: O.Op, +a: O.Arg) -> Bool:
  Bool.or(rz_dnum_x.rng(op, a), rz_dnum_x.num(op, a))

def rz_dnum_x(+ar: O.Arena, +x: U32) -> Bool:
  rz_dnum_x.any(O.Arena.op(ar, x), O.Arena.arg(ar, x))

def rz_dnum.go(+ar: O.Arena, todo: List<&2, U32>, acc: Bool) -> Bool:
  match todo:
    case Nil{}: acc
    case +x <> t: rz_dnum.go(ar, t, Bool.or(acc, rz_dnum_x(ar, x)))

def has_dnum(+ar: O.Arena, +call: U32) -> Bool:
  rz_dnum.go(ar, O.UOp.toposort(rz_res_fuel(ar), ar, rz_body(ar, call)), False{})

# ===========================================================================
# THE FIXTURE. 42 nodes, and the INDEX of each is spelled out below because
# `Arena.empty` spends slot 0 on the bottom, so node k is at index k and the whole
# map is "the order of the `UOp.new` calls". `Land` holds the arena plus the eight
# indices the gate reads; everything else is reached from those.
#
#   0  bottom          1  CONST(3)      2  PARAM g0 slot 0    3  PARAM g1 slot 1
#   4  PARAM n slot 2 (unbound)           5  PARAM n slot 2 (BOUND, val 4)
#   6  PARAM m slot 3 (unbound)           7  SINK "k1" (beam 0)
#   8  SINK "k2" (beam 2)                 9  BUFFER g0        10  BUFFER g1
#  11  PROGRAM k1, globals (0,1) outs (0,) ins (1,)
#  12  PROGRAM k1, vars (n,), globals (0,1) outs (0,) ins (1,)
#  13  PROGRAM k1, vars (m,), globals (0,1) outs (0,) ins (1,)
#  14  STORE (g0,g1), globals (0,) outs (0,) ins (1,)
#  15  CUSTOM_FUNCTION "validate" (k1)    16  CUSTOM_FUNCTION "encdec" (k1)
#  17  CALL (11, g0, g1)     f    -- a kernel      18  CALL (14, g0, g1)  g  copy
#  19  CALL (12, g0, nbnd)   h    -- a bound var    20  CALL (13, g0, m)    i
#  21  CALL (15, g0, g1)     j    -- validate      22  CALL (16, g0, g1, n) k encdec
#  23  CALL (7, g0)          l    -- beam 0         24  CALL (8, g0)      m  beam 2
#  25  CALL (11, b0, b1)     o    -- BUFFER args   26  LINEAR (17)
#  27  LINEAR (26, 18)                     <- nested, so `pm_flatten_linear` fires
#  28  RANGE (CONST(2), AXIS_DEVICE)       29  SINK (28) "kd"
#  30  PROGRAM (29) globals (0,1)          31  CALL (30, g0, g1)   z
#  32  PARAM "_device_num" slot 9          33  SINK (32) "kp"
#  34  PROGRAM (33) globals (0,1)          35  CALL (34, g0, g1)   y
#  36  LINEAR (7)                          37  SOURCE "y"
#  38  BINARY 1 byte                       39  PROGRAM (7, 36, 37, 38) -- COMPILED
#  40  CALL (39, g0, g1)     p    -- already compiled, so `_get_call_to_compile` says None
#  41  BITCAST (PARAM slot 1)              <- a view, so `_resolve`'s arm 0 fires
# ===========================================================================

def cpu_dev() -> S.Dev:
  S.D1{0}

def zero_four() -> O.PyRange:
  O.PyRange{H.i64_of_i32(0), H.i64_of_i32(4)}

def gs3(a: U32, b: U32, c: U32) -> List<&2, H.I64>:
  [H.i64_of_i32(a), H.i64_of_i32(b), H.i64_of_i32(c)]

# THE SEVENTH FIELD IS `target: Target` -- upstream's `ops.py:1349` -- AND IT IS NOT
# READ BY ANY READER IN THIS FILE, SO IT IS THE DEFAULT (`helpers.bend`'s
# `Target.of()`, WHICH IS FIVE EMPTY STRINGS). `ProgramInfo.from_sink` -- WHICH TAKES
# THE TARGET AS AN ARGUMENT -- IS PORTED (`d87143780`); THIS IS THE SYNTHETIC BUILDER
# AND IT NAMES NO TARGET.
def pi(params: List<&2, U32>, globals: List<&2, U32>, outs: List<&2, U32>, ins: List<&2, U32>) -> O.ProgramInfo:
  O.ProgramInfo{gs3(4, 1, 1), [H.i64_of_i32(1), H.i64_of_i32(1), H.i64_of_i32(1)], params, globals, outs, ins, H.Target.of()}

def call_info(nm: String) -> O.CallInfo:
  O.CallInfo{Some{nm}, False{}, False{}, S.void()}

def kernel_info(nm: String, beam: U32) -> O.KernelInfo:
  O.KernelInfo{nm, Nil{}, None{}, beam}

# THE LIFETIME IS `&2` AND THAT IS NOT COSMETIC. A `ParamArg` FIELD is
# `Maybe<&2, String>`, so a `Maybe<String>` parameter that is STORED into one must
# itself be at `&2` -- and it then cannot be read a second time, which is why the
# slot and the name travel TOGETHER in a `Data` record rather than as two
# parameters. `Maybe<&1, ...>` gives "expected: Maybe<&2, String>", and passing
# the thirteen fields inline gives the far more misleading "expected:
# uop/ops.ParamArg with 13 fields", which names the RECORD rather than the
# lifetime. Both were measured; the second is the worst message in this file.
type Slot is Data:
  Slot{slot: U32, nm: Maybe<&2, String>}

def Slot.of(slot: U32, nm: String) -> Slot: Slot{slot, Some{nm}}

def Slot.nm(s: Slot) -> Maybe<&2, String>:
  match s:
    case Slot{slot, nm}: nm

def Slot.slot(s: Slot) -> U32:
  match s:
    case Slot{slot, nm}: slot

# A BUFFER PARAM. `buffer` is `Some{0}` -- the REALIZED shape `spec.bend`'s
# `buf_param` uses -- and `is_bound_var` reads `val` only, so the difference is
# invisible to this file's readers and no row depends on it.
def buf_arg(+w: Slot) -> O.ParamArg:
  O.ParamArg{Slot.slot(w), S.int32(), None{}, None{}, Slot.nm(w), S.AGlobal{},
             Some{cpu_dev()}, False{}, None{}, Some{0}, False{}, None{}}

# A kernel-graph VARIABLE: `size=None`, `addrspace=ALU`, a `vmin_vmax`, and
# `val=None` -- which is exactly what makes `is_bound_var` FALSE (ops.py:1025).
def var_arg(+w: Slot) -> O.ParamArg:
  O.ParamArg{Slot.slot(w), S.int32(), Some{zero_four()}, Some{1}, Slot.nm(w), S.Aalu{},
             None{}, False{}, None{}, Some{0}, False{}, None{}}

# The SAME shape with `val` set: the one field `is_bound_var` tests, and the reason
# realize.py:15's filter drops this node from `get_call_arg_uops`.
def bnd_arg(+w: Slot) -> O.ParamArg:
  O.ParamArg{Slot.slot(w), S.int32(), Some{zero_four()}, Some{1}, Slot.nm(w), S.Aalu{},
             None{}, False{}, None{}, Some{0}, False{}, Some{O.CInt{H.i64_of_i32(4)}}}

# `Land` is the fixture: the arena plus the indices the gate reads. The FULL index
# map is in the comment above this def; the fields are the eight the rows need and
# everything else is reached through them.
type Land is Data:
  Land{ar: O.Arena, fx: F.Folded, k: U32, g0: U32, g1: U32, callP: U32, callS: U32, callV: U32,
       callE: U32, callK0: U32, lin: U32, lin2: U32, progV: U32, progM: U32, nbnd: U32,
       varM: U32, g2: U32, callBuf: U32, callD: U32, callN: U32, callC: U32, bc: U32, callH: U32, callM: U32, callK2: U32}

def Land.ar(l: Land) -> O.Arena:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: ar

def Land.fx(l: Land) -> F.Folded:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: fx

def Land.k(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: k

def Land.g0(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: g0

def Land.g1(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: g1

def Land.callP(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: callP

def Land.callS(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: callS

def Land.callV(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: callV

def Land.callE(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: callE

def Land.callK0(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: callK0

def Land.lin(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: lin

def Land.lin2(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: lin2

def Land.progV(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: progV

def Land.progM(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: progM

def Land.nbnd(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: nbnd

def Land.varM(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: varM

def Land.g2(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: g2

def Land.callBuf(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: callBuf

def Land.callD(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: callD

def Land.callN(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: callN

def Land.callC(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: callC

def Land.bc(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: bc

def Land.callK2(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: callK2

def Land.callM(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: callM

def Land.callH(l: Land) -> U32:
  match l:
    case Land{ar, fx, k, g0, g1, callP, callS, callV, callE, callK0, lin, lin2, progV, progM, nbnd,
              varM, g2, callBuf, callD, callN, callC, bc, callH, callM, callK2}: callH

def main_arena() -> Land:
  +a0 = O.Arena.empty()
  +n1 = O.UOp.const(a0, O.CInt{H.i64_of_i32(3)})
  +n2 = O.UOp.new.param(O.Found.ar(n1), O.OpsPARAM{}, Some{16}, O.AParam{buf_arg(Slot.of(0, "g0"))}, O.TNone{})
  +n3 = O.UOp.new.param(O.Found.ar(n2), O.OpsPARAM{}, Some{16}, O.AParam{buf_arg(Slot.of(1, "g1"))}, O.TNone{})
  +n4 = O.UOp.new(O.Found.ar(n3), O.OpsPARAM{}, Nil{}, O.AParam{var_arg(Slot.of(2, "n"))}, O.TNone{})
  +n5 = O.UOp.new(O.Found.ar(n4), O.OpsPARAM{}, Nil{}, O.AParam{bnd_arg(Slot.of(2, "n"))}, O.TNone{})
  +n6 = O.UOp.new(O.Found.ar(n5), O.OpsPARAM{}, Nil{}, O.AParam{var_arg(Slot.of(3, "m"))}, O.TNone{})
  +n7 = O.UOp.new(O.Found.ar(n6), O.OpsSINK{}, Nil{}, O.AKernel{kernel_info("k1", 0)}, O.TNone{})
  +n8 = O.UOp.new(O.Found.ar(n7), O.OpsSINK{}, Nil{}, O.AKernel{kernel_info("k2", 2)}, O.TNone{})
  +n9 = O.UOp.new.param(O.Found.ar(n8), O.OpsBUFFER{}, Some{16}, O.AParam{buf_arg(Slot.of(0, "g0"))}, O.TNone{})
  +n10 = O.UOp.new.param(O.Found.ar(n9), O.OpsBUFFER{}, Some{16}, O.AParam{buf_arg(Slot.of(1, "g1"))}, O.TNone{})
  +n11 = O.UOp.new(O.Found.ar(n10), O.OpsPROGRAM{}, [O.Found.i(n7)], O.AProgram{pi(Nil{}, [0, 1], [0], [1])}, O.TNone{})
  +n12 = O.UOp.new(O.Found.ar(n11), O.OpsPROGRAM{}, [O.Found.i(n7)], O.AProgram{pi([O.Found.i(n4)], [0, 1], [0], [1])}, O.TNone{})
  +n13 = O.UOp.new(O.Found.ar(n12), O.OpsPROGRAM{}, [O.Found.i(n7)], O.AProgram{pi([O.Found.i(n6)], [0, 1], [0], [1])}, O.TNone{})
  +n14 = O.UOp.new(O.Found.ar(n13), O.OpsSTORE{}, [O.Found.i(n2), O.Found.i(n3)], O.AProgram{pi(Nil{}, [0], [0], [1])}, O.TNone{})
  +n15 = O.UOp.new(O.Found.ar(n14), O.OpsCUSTOM_FUNCTION{}, [O.Found.i(n7)], O.AStr{"validate"}, O.TNone{})
  +n16 = O.UOp.new(O.Found.ar(n15), O.OpsCUSTOM_FUNCTION{}, [O.Found.i(n7)], O.AStr{"encdec"}, O.TNone{})
  +n17 = O.UOp.new(O.Found.ar(n16), O.OpsCALL{}, [O.Found.i(n11), O.Found.i(n2), O.Found.i(n3)], O.ACall{call_info("f")}, O.TNone{})
  +n18 = O.UOp.new(O.Found.ar(n17), O.OpsCALL{}, [O.Found.i(n14), O.Found.i(n2), O.Found.i(n3)], O.ACall{call_info("g")}, O.TNone{})
  +n19 = O.UOp.new(O.Found.ar(n18), O.OpsCALL{}, [O.Found.i(n12), O.Found.i(n2), O.Found.i(n5)], O.ACall{call_info("h")}, O.TNone{})
  +n20 = O.UOp.new(O.Found.ar(n19), O.OpsCALL{}, [O.Found.i(n13), O.Found.i(n2), O.Found.i(n6)], O.ACall{call_info("i")}, O.TNone{})
  +n21 = O.UOp.new(O.Found.ar(n20), O.OpsCALL{}, [O.Found.i(n15), O.Found.i(n2), O.Found.i(n3)], O.ACall{call_info("j")}, O.TNone{})
  +n22 = O.UOp.new(O.Found.ar(n21), O.OpsCALL{}, [O.Found.i(n16), O.Found.i(n2), O.Found.i(n3), O.Found.i(n4)], O.ACall{call_info("k")}, O.TNone{})
  +n23 = O.UOp.new(O.Found.ar(n22), O.OpsCALL{}, [O.Found.i(n7), O.Found.i(n2)], O.ACall{call_info("l")}, O.TNone{})
  +n24 = O.UOp.new(O.Found.ar(n23), O.OpsCALL{}, [O.Found.i(n8), O.Found.i(n2)], O.ACall{call_info("m")}, O.TNone{})
  +n25 = O.UOp.new(O.Found.ar(n24), O.OpsCALL{}, [O.Found.i(n11), O.Found.i(n9), O.Found.i(n10)], O.ACall{call_info("o")}, O.TNone{})
  +n26 = O.UOp.new(O.Found.ar(n25), O.OpsLINEAR{}, [O.Found.i(n17)], O.ANone{}, O.TNone{})
  +n27 = O.UOp.new(O.Found.ar(n26), O.OpsLINEAR{}, [O.Found.i(n26), O.Found.i(n18)], O.ANone{}, O.TNone{})
  +n28 = O.UOp.new(O.Found.ar(n27), O.OpsRANGE{}, [O.Found.i(n1)], O.ARange{[0], O.AXIS_DEVICE{}}, O.TNone{})
  +n29 = O.UOp.new(O.Found.ar(n28), O.OpsSINK{}, [O.Found.i(n28)], O.AKernel{kernel_info("kd", 0)}, O.TNone{})
  +n30 = O.UOp.new(O.Found.ar(n29), O.OpsPROGRAM{}, [O.Found.i(n29)], O.AProgram{pi(Nil{}, [0, 1], [0], [1])}, O.TNone{})
  +n31 = O.UOp.new(O.Found.ar(n30), O.OpsCALL{}, [O.Found.i(n30), O.Found.i(n2), O.Found.i(n3)], O.ACall{call_info("z")}, O.TNone{})
  +n32 = O.UOp.new(O.Found.ar(n31), O.OpsPARAM{}, Nil{}, O.AParam{var_arg(Slot.of(9, "_device_num"))}, O.TNone{})
  +n33 = O.UOp.new(O.Found.ar(n32), O.OpsSINK{}, [O.Found.i(n32)], O.AKernel{kernel_info("kp", 0)}, O.TNone{})
  +n34 = O.UOp.new(O.Found.ar(n33), O.OpsPROGRAM{}, [O.Found.i(n33)], O.AProgram{pi(Nil{}, [0, 1], [0], [1])}, O.TNone{})
  +n35 = O.UOp.new(O.Found.ar(n34), O.OpsCALL{}, [O.Found.i(n34), O.Found.i(n2), O.Found.i(n3)], O.ACall{call_info("y")}, O.TNone{})
  +n36 = O.UOp.new(O.Found.ar(n35), O.OpsLINEAR{}, [O.Found.i(n7)], O.ANone{}, O.TNone{})
  +n37 = O.UOp.new(O.Found.ar(n36), O.OpsSOURCE{}, Nil{}, O.AStr{"y"}, O.TNone{})
  # the BINARY whose arg is `b"a"`: `ABlob` holds the BYTES, because ops.py:201's key
  # holds the `bytes` object and compares its content. Only the LENGTH is ever read
  # (`binary_n`), and it is still 1.
  +n38 = O.UOp.new(O.Found.ar(n37), O.OpsBINARY{}, Nil{}, O.ABlob{[97]}, O.TNone{})
  +n39 = O.UOp.new(O.Found.ar(n38), O.OpsPROGRAM{}, [O.Found.i(n7), O.Found.i(n36), O.Found.i(n37), O.Found.i(n38)], O.AProgram{pi(Nil{}, [0, 1], [0], [1])}, O.TNone{})
  +n40 = O.UOp.new(O.Found.ar(n39), O.OpsCALL{}, [O.Found.i(n39), O.Found.i(n2), O.Found.i(n3)], O.ACall{call_info("p")}, O.TNone{})
  +n41 = O.UOp.new(O.Found.ar(n40), O.OpsBITCAST{}, [O.Found.i(n3)], O.ADt{S.int32()}, O.TNone{})
  Land{O.Found.ar(n41), F.folded(O.Found.ar(n41)), O.Found.i(n1), O.Found.i(n2), O.Found.i(n3),
       O.Found.i(n17), O.Found.i(n18), O.Found.i(n21), O.Found.i(n22), O.Found.i(n23),
       O.Found.i(n26), O.Found.i(n27), O.Found.i(n12), O.Found.i(n13), O.Found.i(n5),
       O.Found.i(n6), O.Found.i(n9), O.Found.i(n25), O.Found.i(n31), O.Found.i(n35),
       O.Found.i(n40), O.Found.i(n41), O.Found.i(n19), O.Found.i(n20), O.Found.i(n24)}

# ===========================================================================
# THE PLANT FIXTURE. ITS OWN ARENA, AND THE REASON IS THAT THE MAIN FIXTURE's INDEX
# MAP IS LOAD BEARING: `gates/realize_graph_census-gate.py`'s CALL_NODES LIST IS READ
# OFF `main_arena`'s COMMENT, SO A PLANT THAT MOVED A MAIN-FIXTURE INDEX WOULD MOVE
# EVERY ROW OF A GATE THAT HAS NOTHING TO DO WITH THIS FILE.
#
# EVERY PROGRAM HERE HAS THE PIN's COMPILED SHAPE -- `src=(sink, linear)` -- BECAUSE
# THE PIN's `UOp.kernel_params` READS `self.src[1].src` AND A ONE-SRC PROGRAM RAISES
# IndexError THERE. `codegen/__init__.py:503`'s `pm_to_program` GIVES A COMPILED
# PROGRAM FOUR SRCS; TWO IS ENOUGH FOR THE READER, AND THE LINEAR HERE CARRIES NO
# PARAM CHILDREN -- WHICH IS WHAT AN ASSEMBLED ONE CARRIES (`do_assemble` REPLACES THE
# LINEAR's SRCS WITH `Ops.INS` NODES).
#
# THE PLANTS, AND WHAT EACH ONE IS FOR:
#   cNone      A PROGRAM WITH NO VARIABLE AT ALL. THE ANSWER IS ONE ADDRESS PER
#              BUFFER PARAM AND NOTHING ELSE.
#   cZero      A VARIABLE BOUND TO ZERO. THE BOUND VALUE IS A CONST 0 AND THE
#              LOOKUP MUST NOT READ 0 AS "ABSENT".
#   cUnb       AN UNBOUND VARIABLE. THE ANSWER IS THE SLOTLESS VAR READ, AND THE
#              ARGUMENT LIST DROPS IT (`get_call_arg_uops` FILTERS `is_variable`).
#   cArgFirst  AN ARG PRECEDES A BUFFER: THE KERNEL's PARAMS ARE (VAR SLOT 0,
#              BUFFER SLOT 1) AND THE ANSWER MUST BE IN THAT ORDER.
#   cBufFirst  THE MIRROR -- (BUFFER SLOT 0, VAR SLOT 1) -- AND THE ANSWER MUST BE
#              THE OTHER WAY ROUND. THE PAIR IS WHAT SAYS THE ORDER IS THE SLOT
#              ORDER AND NOT "THE BUFFERS FIRST", WHICH IS WHAT THE PRE-PIN
#              `exec_kernel` DID: `rt(*[b.get_buf(device) for b in prg_bufs], ...,
#              vals=vals)` PUT THE BUFFERS FIRST AND THE VALUES AFTER THEM.
#   cShadow    A VARIABLE WHOSE NAME IS A GLOBAL's NAME. `bound` IS KEYED ON THE
#              NAME, SO THE LOOKUP MUST STILL ANSWER THE VARIABLE's OWN VALUE AND
#              NOT THE GLOBAL's.
# ===========================================================================
type Pl is Data:
  Pl{ar: O.Arena, cNone: U32, cZero: U32, cUnb: U32, cArgFirst: U32, cBufFirst: U32, cShadow: U32}

def Pl.ar(p: Pl) -> O.Arena:
  match p:
    case Pl{ar, cNone, cZero, cUnb, cArgFirst, cBufFirst, cShadow}: ar

def Pl.call.go(n: U32, a: U32, b: U32, c: U32, d: U32, e: U32, f: U32) -> U32:
  match n:
    case 0: a
    case 1: b
    case 2: c
    case 3: d
    case 4: e
    case _: f

def Pl.call(p: Pl, n: U32) -> U32:
  match p:
    case Pl{ar, cNone, cZero, cUnb, cArgFirst, cBufFirst, cShadow}:
      Pl.call.go(n, cNone, cZero, cUnb, cArgFirst, cBufFirst, cShadow)

# THE VARIABLE BOUND TO ZERO. `bnd_arg` IS THE SAME SHAPE WITH FOUR IN IT, AND THE
# VALUE IS INSIDE A `Some`, SO ZERO IS NOT "ABSENT": `PArg.has_val` ASKS
# `val is not None` AND NOT WHETHER THE VALUE IS TRUTHY.
def bnd_arg0(+w: Slot) -> O.ParamArg:
  O.ParamArg{Slot.slot(w), S.int32(), Some{zero_four()}, Some{1}, Slot.nm(w), S.Aalu{},
             None{}, False{}, None{}, Some{0}, False{}, Some{O.CInt{H.i64_of_i32(0)}}}

def plants_arena() -> Pl:
  +a0 = O.Arena.empty()
  +n1 = O.UOp.const(a0, O.CInt{H.i64_of_i32(3)})
  +n2 = O.UOp.new.param(O.Found.ar(n1), O.OpsPARAM{}, Some{16}, O.AParam{buf_arg(Slot.of(0, "g0"))}, O.TNone{})
  +n3 = O.UOp.new(O.Found.ar(n2), O.OpsPARAM{}, Nil{}, O.AParam{var_arg(Slot.of(0, "a0"))}, O.TNone{})
  +n4 = O.UOp.new(O.Found.ar(n3), O.OpsPARAM{}, Nil{}, O.AParam{var_arg(Slot.of(1, "a1"))}, O.TNone{})
  +n5 = O.UOp.new(O.Found.ar(n4), O.OpsPARAM{}, Nil{}, O.AParam{bnd_arg0(Slot.of(0, "z0"))}, O.TNone{})
  +n6 = O.UOp.new(O.Found.ar(n5), O.OpsPARAM{}, Nil{}, O.AParam{bnd_arg(Slot.of(1, "g0"))}, O.TNone{})
  +n7 = O.UOp.new(O.Found.ar(n6), O.OpsSINK{}, Nil{}, O.AKernel{kernel_info("kp", 0)}, O.TNone{})
  +n8 = O.UOp.new(O.Found.ar(n7), O.OpsLINEAR{}, Nil{}, O.ANone{}, O.TNone{})
  +n9 = O.UOp.new(O.Found.ar(n8), O.OpsPROGRAM{}, [O.Found.i(n7), O.Found.i(n8)], O.AProgram{pi([O.Found.i(n2)], [0], [0], [])}, O.TNone{})
  +n10 = O.UOp.new(O.Found.ar(n9), O.OpsCALL{}, [O.Found.i(n9), O.Found.i(n2)], O.ACall{call_info("pn")}, O.TNone{})
  +n11 = O.UOp.new(O.Found.ar(n10), O.OpsPROGRAM{}, [O.Found.i(n7), O.Found.i(n8)], O.AProgram{pi([O.Found.i(n5)], [0], [0], [])}, O.TNone{})
  +n12 = O.UOp.new(O.Found.ar(n11), O.OpsCALL{}, [O.Found.i(n11), O.Found.i(n5)], O.ACall{call_info("pz")}, O.TNone{})
  +n13 = O.UOp.new(O.Found.ar(n12), O.OpsPROGRAM{}, [O.Found.i(n7), O.Found.i(n8)], O.AProgram{pi([O.Found.i(n3)], [0], [0], [])}, O.TNone{})
  +n14 = O.UOp.new(O.Found.ar(n13), O.OpsCALL{}, [O.Found.i(n13), O.Found.i(n3)], O.ACall{call_info("pu")}, O.TNone{})
  +n15 = O.UOp.new(O.Found.ar(n14), O.OpsPROGRAM{}, [O.Found.i(n7), O.Found.i(n8)], O.AProgram{pi([O.Found.i(n3), O.Found.i(n2)], [1], [1], [])}, O.TNone{})
  +n16 = O.UOp.new(O.Found.ar(n15), O.OpsCALL{}, [O.Found.i(n15), O.Found.i(n3), O.Found.i(n2)], O.ACall{call_info("pa")}, O.TNone{})
  +n17 = O.UOp.new(O.Found.ar(n16), O.OpsPROGRAM{}, [O.Found.i(n7), O.Found.i(n8)], O.AProgram{pi([O.Found.i(n2), O.Found.i(n4)], [0], [0], [])}, O.TNone{})
  +n18 = O.UOp.new(O.Found.ar(n17), O.OpsCALL{}, [O.Found.i(n17), O.Found.i(n2), O.Found.i(n4)], O.ACall{call_info("pb")}, O.TNone{})
  +n19 = O.UOp.new(O.Found.ar(n18), O.OpsPROGRAM{}, [O.Found.i(n7), O.Found.i(n8)], O.AProgram{pi([O.Found.i(n2), O.Found.i(n6)], [0], [0], [])}, O.TNone{})
  +n20 = O.UOp.new(O.Found.ar(n19), O.OpsCALL{}, [O.Found.i(n19), O.Found.i(n2), O.Found.i(n6)], O.ACall{call_info("ps")}, O.TNone{})
  Pl{O.Found.ar(n20), O.Found.i(n10), O.Found.i(n12), O.Found.i(n14), O.Found.i(n16), O.Found.i(n18), O.Found.i(n20)}

# `1` is `VTrue`, `0` is `VFalse`, `9` is `VSkip` -- `uop/spec.bend`'s spelling, and
# a `VSkip` is a REAL ANSWER and not a failure: it is what a rule says when the
# pattern does not apply, and `rewrite` answering `None` is the same thing.
def show_v(v: O.Verdict) -> U32:
  match v:
    case O.VTrue{}: 1
    case O.VFalse{}: 0
    case _: 9

# `pm_beam`'s driver -- the rule body rewrites the node, so this file needs its own
# two-line `rewrite` rather than the `Verdict` shape the three judge-only tables use.
def beam_rewrite(+ar: O.Arena, +self: U32) -> O.Verdict:
  rz_fire(rz_claim(beam_table(), ar, self), beam_0(ar, self))

# ===========================================================================
# THE ROWS. Every value is DERIVABLE from `realize.py` on the arena above, and
# the Python line that fixes each one is in the table at the foot of this file.
# Bend has no assertion form, so the gate is that BOTH LANES print these.
# ===========================================================================
# `1 if b else 0` -- `uop/spec.bend` spells this `if_b`. Here the FALSE arm has to
# be a separate def because the ladder is bottom-up, and `bl_u` is the same
# function with its arms already at hand.
def bl_of(b: Bool) -> U32:
  bl_u(b, 1, 0)

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def row_s(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# --- the COUNTS, which are the rows a MISSING rule or a MISSING fixture shows.
def t_arena_n(+l: Land) -> U32:
  U32.from_nat(List.length(&2, O.Node, O.Arena.nodes(Land.ar(l))))

def tlen(ts: O.PMEntrys) -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, O.PMEntrys.es(ts)))

def t_flat_len() -> U32: tlen(flatten_table())

def t_va_len() -> U32: tlen(validate_table())

def t_beam_len() -> U32: tlen(beam_table())

# --- realize.py:15 `get_call_arg_uops`
def t_arg_len(+l: Land) -> U32:
  U32.from_nat(List.length(&2, U32, get_call_arg_uops(Land.ar(l), Land.callP(l))))

# THE BOUND VARIABLE IS DROPPED. realize.py:16 AT THE PIN FILTERS `if not
# s.is_variable`, WHICH IS TRUE OF A BOUND VARIABLE TOO, and node 19 (`CALL (12, g0,
# nbnd)`) is the fixture that has one: `arg_len_b` is 1 where `arg_len` is 2, and the
# pair is what a walk over the RAW `src[1:]` gets wrong. The two rows are also a
# first-wins control -- a filter that kept everything would move `arg_len_b` and not
# `arg_len`. `arg_len_var` IS THE SAME FILTER ON AN **UNBOUND** VARIABLE, AND THE
# PRE-PIN FILTER (`is_bound_var`) KEPT THOSE.
def t_arg_len_b(+l: Land) -> U32:
  U32.from_nat(List.length(&2, U32, get_call_arg_uops(Land.ar(l), Land.callH(l))))

# --- realize.py:21 `get_call_outs_ins`, per body op
def t_oi_out_p(+l: Land) -> U32:
  OutsIns.n_out(get_call_outs_ins(Land.ar(l), Land.callP(l)))

def t_oi_out_s(+l: Land) -> U32:
  OutsIns.n_out(get_call_outs_ins(Land.ar(l), Land.callS(l)))

def t_oi_in_p(+l: Land) -> U32:
  OutsIns.n_in(get_call_outs_ins(Land.ar(l), Land.callP(l)))

def t_oi_in_e(+l: Land) -> U32:
  OutsIns.n_in(get_call_outs_ins(Land.ar(l), Land.callE(l)))

# a CUSTOM_FUNCTION with an arg other than `encdec` gets `(), ()` -- realize.py:27
def t_oi_out_v(+l: Land) -> U32:
  OutsIns.n_out(get_call_outs_ins(Land.ar(l), Land.callV(l)))

def t_oi_in_v(+l: Land) -> U32:
  OutsIns.n_in(get_call_outs_ins(Land.ar(l), Land.callV(l)))

# --- realize.py:29 `get_call_written_bufs`. A PARAM argument is not a BUFFER, so
# the answer is empty; a BUFFER argument is kept. TWO rows, because one would not
# notice a filter that dropped everything.
def t_wbuf_p(+l: Land) -> U32:
  U32.from_nat(List.length(&2, U32, get_call_written_bufs(Land.ar(l), Land.callP(l))))

def t_wbuf_buf(+l: Land) -> U32:
  U32.from_nat(List.length(&2, U32, get_call_written_bufs(Land.ar(l), Land.callBuf(l))))

# --- realize.py:35 `get_call_kernels`: one device for a kernel, ZERO for a
# validate call, and the latter is the row that catches a filter that always fires.
def t_kern_p(+l: Land) -> U32:
  U32.from_nat(List.length(&2, U32, get_call_kernels(Land.ar(l), Land.callP(l))))

def t_kern_v(+l: Land) -> U32:
  U32.from_nat(List.length(&2, U32, get_call_kernels(Land.ar(l), Land.callV(l))))

# --- realize.py:16 AT THE PIN: `get_call_arg_uops` FILTERS `is_variable` AND NOT
# `is_bound_var`, SO AN **UNBOUND** VARIABLE IS DROPPED FROM THE ARGUMENT LIST. The
# fixture's CALL 20 passes the UNBOUND `m` and `g0`, so the answer is ONE argument
# where the pre-pin filter said TWO. THE ROW IS THE FILTER: A FILTER THAT DROPPED
# NOTHING WOULD ANSWER 2 HERE AND 2 AT `arg_len` TOO.
def t_arg_len_var(+l: Land) -> U32:
  U32.from_nat(List.length(&2, U32, get_call_arg_uops(Land.ar(l), Land.callM(l))))

# --- realize.py:17 AT THE PIN: `get_call_kernel_args`. ONE ENTRY PER KERNEL PARAM,
# IN SLOT ORDER. THE ANSWER IS TAKEN OVER THE PLANT FIXTURE, BECAUSE THE PIN's
# `UOp.kernel_params` READS `self.src[1].src` AND THE MAIN FIXTURE's PROGRAMs HAVE
# ONE SRC AND NO `src[1]`.
def ka_of(+l: Pl, n: U32) -> RList:
  +c = Pl.call(l, n)
  +ar = Pl.ar(l)
  get_call_kernel_args(ar, c, rz_body(ar, c), cpu_dev())

def t_ka_len(+l: Pl, n: U32) -> U32:
  RList.len(ka_of(l, n))

# THE BUFFER ARM: `call.src[1+p.arg.slot].getaddr(devs)` IS A `GETADDR`.
def t_ka_addr(+l: Pl, n: U32, i: U32) -> U32:
  bl_of(RList.is_op(ka_of(l, n), i, O.OpsGETADDR{}))

# THE ALU ARM, UNBOUND: `p.replace(arg=replace(p.arg, slot=-1))` IS A `PARAM`.
def t_ka_param(+l: Pl, n: U32, i: U32) -> U32:
  bl_of(RList.is_op(ka_of(l, n), i, O.OpsPARAM{}))

# THE ALU ARM, BOUND: `.ccast(p.dtype)` MAKES THE CONST A `CAST`.
def t_ka_cast(+l: Pl, n: U32, i: U32) -> U32:
  bl_of(RList.is_op(ka_of(l, n), i, O.OpsCAST{}))

# THE SLOTLESS READ: THE ENTRY's SLOT IS THE PIN's `-1`, WHICH THE PORT SPELLS
# `ops.bend`'s OWN `ParamArg.no_slot()`.
def t_ka_slotless(+l: Pl, n: U32, i: U32) -> U32:
  +r = ka_of(l, n)
  bl_of(U32.is_eq(kp_slot(RList.ar(r), RList.at(r, i)), O.ParamArg.no_slot()))

# THE PIN's `get_call_arg_uops` OVER A PLANT: AN UNBOUND VARIABLE IS DROPPED, SO A
# CALL THAT PASSES ONLY A VARIABLE HAS NO ARGUMENT UOPS AT ALL.
def t_ka_arglen(+l: Pl, n: U32) -> U32:
  +c = Pl.call(l, n)
  U32.from_nat(List.length(&2, U32, get_call_arg_uops(Pl.ar(l), c)))

# --- realize.py:43 `get_call_name`: the PROGRAM arm is `ast.src[0].arg.name`, so
# the answer is the KERNEL NAME and not the CALL name. `name_p` is a STRING row on
# purpose: it is the one row that a wrong `arg` reads would turn into a number.
def t_name_p(+l: Land) -> Maybe<&2, String>:
  get_call_name(Land.ar(l), Land.callP(l))

# --- realize.py:128 `_resolve` / :132 `resolve_params`
def t_res_len(+l: Land) -> U32:
  RList.len(resolve_params(rz_res_fuel(Land.ar(l)), Land.ar(l), Land.callP(l), []))

# THE SWAP IS THE ROW. `inputs` is `(g1, g0)`, so `resolve_params` must answer
# `(g1, g0)` for a call whose args are `(g0, g1)`: `res_slot0=1` says the first
# resolved arg IS `g1`, which is a slot lookup and not an identity. A port that
# returned the arg uops unchanged would answer 0 here.
def t_res_slot0(+l: Land) -> U32:
  bl_of(RList.is_at(resolve_params(rz_res_fuel(Land.ar(l)), Land.ar(l), Land.callP(l), [Land.g1(l), Land.g0(l)]), 0, Land.g1(l)))

def t_res_slot1(+l: Land) -> U32:
  bl_of(RList.is_at(resolve_params(rz_res_fuel(Land.ar(l)), Land.ar(l), Land.callP(l), [Land.g1(l), Land.g0(l)]), 1, Land.g0(l)))

# the MSTACK WALL, made visible: `_resolve`'s arm 1 answers the node unchanged, so
# `res_ms_same` is 1. A row that PRINTS A MISSING VALUE rather than hiding it.
def t_res_ms_same(+l: Land) -> U32:
  bl_of(U32.is_eq(rz_arm(O.Arena.op(Land.ar(l), Land.bc(l))), 0))

# --- realize.py:139 `has_dnum`: false for a plain kernel, TRUE for a DEVICE-axis
# RANGE and for a `_device_num` PARAM. Three rows and two different code paths.
def t_dnum_p(+l: Land) -> U32:
  bl_of(has_dnum(Land.ar(l), Land.callP(l)))

def t_dnum_d(+l: Land) -> U32:
  bl_of(has_dnum(Land.ar(l), Land.callD(l)))

def t_dnum_n(+l: Land) -> U32:
  bl_of(has_dnum(Land.ar(l), Land.callN(l)))

# --- realize.py:226 `_get_call_to_compile`. `gcc_P` is a kernel that still needs
# lowering; `gcc_C` is a PROGRAM whose last src is a BINARY, i.e. ALREADY compiled,
# and the pair is what makes the `src[-1]` test load-bearing rather than decorative.
def t_gcc_p(+l: Land) -> U32:
  bl_of(has_u32(_get_call_to_compile(Land.ar(l), Land.callP(l))))

def t_gcc_c(+l: Land) -> U32:
  bl_of(has_u32(_get_call_to_compile(Land.ar(l), Land.callC(l))))

def t_gcc_s(+l: Land) -> U32:
  bl_of(has_u32(_get_call_to_compile(Land.ar(l), Land.callS(l))))

def t_gcc_k(+l: Land) -> U32:
  bl_of(has_u32(_get_call_to_compile(Land.ar(l), Land.callK0(l))))

# --- realize.py:55 `estimate_uop`'s dispatch: True for a copy, False for a kernel.
def t_est_copy_s(+l: Land) -> U32:
  bl_of(rz_est_of(Land.ar(l), Land.callS(l)))

def t_est_copy_p(+l: Land) -> U32:
  bl_of(rz_est_of(Land.ar(l), Land.callP(l)))

# --- realize.py:289 `ExecContext`'s defaults.
def t_ctx_stats() -> U32: bl_of(ExecContext.update_stats(ExecContext.of()))

def t_ctx_jit() -> U32: bl_of(ExecContext.jit(ExecContext.of()))

def t_ctx_wait() -> U32: bl_of(ExecContext.wait(ExecContext.of()))

def t_ctx_cache() -> U32: bl_of(ExecContext.cache(ExecContext.of()))

def t_ctx_timeout() -> U32: bl_of(ExecContext.has_timeout(ExecContext.of()))

def t_ctx_inputs() -> U32: ExecContext.n_input(ExecContext.of())

# `time_call`'s overrides -- realize.py:288.
def t_ctx_time() -> U32: bl_of(ExecContext.wait(ExecContext.of_time(False{}, True{}, None{}, False{})))

def t_ctx_time_cache() -> U32: bl_of(ExecContext.cache(ExecContext.of_time(False{}, True{}, None{}, False{})))

# ===========================================================================
# THE GATE, and what each row is FOR.
#
#   arena_n=42    the fixture is 42 nodes, so a MISSING fixture node moves this
#                 and every row that reads a later index.
#   flat_len=1    realize.py:204 is ONE rule.
#   va_len=2      realize.py:214 is `PatternMatcher([...]) + pm_flatten_linear`, so
#                 TWO entries -- and the second is the FIRST table's rule.
#   beam_len=1    realize.py:217 is ONE rule.
#   arg_len=2     realize.py:15 over `(prog, g0, g1)` is two arg uops.
#   arg_len_b=1   ... and ONE after the bound variable is dropped.
#   arg_len_var=1 realize.py:16 AT THE PIN FILTERS `is_variable`, SO AN **UNBOUND**
#                 variable is dropped too: the fixture's CALL 20 passes `(g0, m)`
#                 and the answer is ONE. THE PRE-PIN FILTER SAID TWO, AND THAT IS
#                 THE WHOLE OF THE FILTER CHANGE.
#   oi_out_p=1    realize.py:24, a PROGRAM's `arg.outs` is `(0,)`.
#   oi_out_s=1    realize.py:25, a STORE is `(0,)`.
#   oi_in_p=1     realize.py:24, a PROGRAM's `arg.ins` is `(1,)`.
#   oi_in_e=1     realize.py:26, `encdec` is `range(1, 2)` for a 2-arg call, AND THE
#                 SECOND ARGUMENT IS THE UNBOUND `n` WHICH THE PIN's FILTER DROPS.
#                 THE PRE-PIN ANSWER WAS `range(1, 3)` AND `2`.
#   oi_out_v=0    realize.py:27, `validate` is NOT `encdec`, so `(), ()`.
#   oi_in_v=0     ... the second half of that pair.
#   wbuf_p=0      realize.py:33 keeps only `Ops.BUFFER`, and a PARAM is not one.
#   wbuf_buf=1    ... and a BUFFER argument IS one. Two rows, because a filter that
#                 dropped everything would move only `wbuf_p`.
#   kern_p=1      realize.py:41, one device.
#   kern_v=0      realize.py:40, a `validate` call enqueues no kernel.
#   ka_none_len=1   realize.py:17 AT THE PIN: A PROGRAM WITH NO VARIABLE ANSWERS ONE
#                   ENTRY, AND IT IS THE BUFFER's ADDRESS.
#   ka_none_addr=1  ... and it is a `GETADDR`.
#   ka_zero_len=1   A VARIABLE BOUND TO ZERO IS STILL A VARIABLE.
#   ka_zero_cast=1  ... and its value is a `CAST` over the CONST 0, NOT A MISS.
#   ka_unb_len=1    AN UNBOUND VARIABLE IS ONE ENTRY.
#   ka_unb_param=1  ... and it is a `PARAM`.
#   ka_unb_slotless=1 ... AND ITS SLOT IS THE PIN's `-1`: THE SLOTLESS VAR READ.
#   ka_unb_arglen=0  AND `get_call_arg_uops` DROPS IT, SO THE CALL HAS NO ARGS.
#   ka_af_len=2      AN ARG PRECEDES A BUFFER: TWO ENTRIES.
#   ka_af_p0=1       ... AND THE ARG IS ENTRY ZERO.
#   ka_af_a1=1       ... AND THE BUFFER's ADDRESS IS ENTRY ONE. THE ORDER IS THE
#                    SLOT ORDER, NOT "THE BUFFERS FIRST".
#   ka_af_slotless=1 ... AND THE ARG's SLOT IS `-1`.
#   ka_bf_len=2      THE MIRROR: A BUFFER PRECEDES AN ARG.
#   ka_bf_a0=1       ... AND THE BUFFER's ADDRESS IS ENTRY ZERO.
#   ka_bf_p1=1       ... AND THE ARG IS ENTRY ONE.
#   ka_bf_slotless=1 ... AND THE ARG's SLOT IS `-1`.
#   ka_sh_len=2      A VARIABLE THAT SHADOWS A GLOBAL's NAME.
#   ka_sh_cast=1     ... AND THE VARIABLE's OWN VALUE IS A `CAST`, NOT THE
#                    GLOBAL's ADDRESS.
#   ka_sh_a0=1       ... AND THE GLOBAL's ADDRESS IS STILL ENTRY ZERO.
#   name_p=k1     realize.py:48 reads `ast.src[0].arg.name`, the KERNEL name and not
#                 the call's. A STRING row, because this is the one reader where a
#                 wrong `arg` would give a plausible wrong STRING.
#   res_len=2     realize.py:132, one resolved entry per arg uop.
#   res_slot0=1   THE SWAP: `inputs=(g1,g0)` answers `g1` for slot 0.
#   res_slot1=1   ... and `g0` for slot 1.
#   res_ms_same=1 the `_resolve` MSTACK WALL, printed rather than hidden: arm 0 is
#                 the VIEW arm and a BITCAST is a view, so the wall is real.
#   dnum_p=0      realize.py:139, no DEVICE axis and no `_device_num`.
#   dnum_d=1      ... a DEVICE-axis RANGE.
#   dnum_n=1      ... a `_device_num` PARAM. Two code paths, two rows.
#   gcc_p=1       realize.py:227, an uncompiled kernel still needs lowering.
#   gcc_c=0       ... a PROGRAM whose `src[-1]` is a BINARY is ALREADY compiled.
#   gcc_s=0       ... a STORE body is not a PROGRAM and not a SINK.
#   gcc_k=1       ... a SINK body with a `KernelInfo` IS.
#   est_copy_s=1  realize.py:59, a copy carries a byte count.
#   est_copy_p=0  ... and a kernel does not.
#   ctx_stats=1   realize.py:120, `update_stats` defaults True.
#   ctx_jit=0     realize.py:122, `jit` defaults False.
#   ctx_wait=0    realize.py:123, `wait` defaults False.
#   ctx_cache=1   realize.py:126, `cache` defaults True.
#   ctx_timeout=0 realize.py:125, `timeout` defaults None.
#   ctx_inputs=0  realize.py:121, `input_uops` defaults `()`.
#   ctx_time=1    realize.py:288, `time_call`'s `wait=True`.
#   ctx_time_cache=0  ... and its `cache=False`. Two rows on ONE constructor.
#   lin_fired=1   realize.py:206, a nested LINEAR IS spliced.
#   lin_len=2     ... and the result has TWO srcs where the input had two as well --
#                 the count is what says the CHILDREN moved, and `lin_first_is_call`
#                 is the row that says WHICH.
#   lin_first=1   the first src of the rewritten LINEAR is the inner CALL, i.e. the
#                 nested LINEAR was INLINED rather than kept.
#   lin_none=9    and a LINEAR with NO nested child is REJECTED by
#                 `custom_early_reject`, so `rewrite` answers `VSkip`, which
#                 `show_v` spells `9` and Python spells `None`. This is the row
#                 that makes `early_reject` load-bearing HERE, which it is not in
#                 `spec.bend`: drop the reject set and this becomes `1`.
#   beam_fired=1  realize.py:219, `sink.arg.beam == 0` so the body fires.
#   beam_new=7    ... and the rewritten sink's `KernelInfo.beam` IS the ctx value.
#   beam_skip=9   a sink that already carries a beam is left alone, so `rewrite`
#                 answers `VSkip` where `beam_fired` answers `VTrue`. This is the
#                 row that makes `sink.arg.beam == 0` load-bearing: drop that
#                 conjunct and this becomes `1`.
#   ex_copy=0     realize.py:265, a CALL over a STORE is `exec_copy`, tag 0.
#   ex_prog=1     realize.py:266, a CALL over a PROGRAM is tag 1.
#   ex_valid=2    realize.py:268, a CALL over `validate` is tag 2.
#   ex_encdec=9   realize.py:269's rule carries `arg="validate"`, so an `encdec`
#                 body is claimed by NO rule: `9` is Python's `None`.
#   ex_none=9     a LINEAR is not a CALL at all.
# ===========================================================================
def t_lin_fired(+l: Land) -> U32:
  show_v(flatten_rewrite(Land.ar(l), Land.lin2(l)))

def t_lin_none(+l: Land) -> U32:
  show_v(flatten_rewrite(Land.ar(l), Land.lin(l)))

# `O.Arena.nsrc` is `(arena, index)`, so the rewritten node's index has to travel
# with its arena -- which is what `O.Found` is for. An index into an arena the
# caller does not hold is not an answer.
def t_lin_len(+l: Land) -> U32:
  O.Arena.nsrc(O.Found.ar(rz_lin_new(Land.ar(l), Land.lin2(l))), O.Found.i(rz_lin_new(Land.ar(l), Land.lin2(l))))

def t_lin_first(+l: Land) -> U32:
  bl_of(O.op_is(O.Found.ar(rz_lin_new(Land.ar(l), Land.lin2(l))), O.Arena.src(O.Found.ar(rz_lin_new(Land.ar(l), Land.lin2(l))), O.Found.i(rz_lin_new(Land.ar(l), Land.lin2(l))), 0), O.OpsCALL{}))

def t_beam_fired(+l: Land) -> U32:
  show_v(beam_rewrite(Land.ar(l), Land.callK0(l)))

def t_beam_skip(+l: Land) -> U32:
  show_v(beam_rewrite(Land.ar(l), Land.callK2(l)))

def t_beam_new.of(l: Land, +f: O.Found) -> U32:
  rz_kernel_beam(O.Arena.arg(O.Found.ar(f), O.Arena.src(O.Found.ar(f), O.Found.i(f), 0)))

def t_beam_new(+l: Land) -> U32:
  t_beam_new.of(l, bm_new(Land.ar(l), Land.callK0(l), 7))
# ===========================================================================
# THE GATE. One printed row per claim, and a COUNT row that is the check on the
# gate ITSELF: `gate_count` is the number of rows printed, so a row that silently
# stopped being printed cannot pass unnoticed, and `arena_n` is the size of the
# fixture, so a fixture that lost a node cannot pass unnoticed either.
#
# EVERY `want_*` BELOW IS CPYTHON'S OWN OUTPUT, read out of a live run of
# `tinygrad/engine/realize.py` -- `gates/realize_graph_census-oracle.py`, run as
#   .venv/bin/python gates/realize_graph_census-oracle.py
# MEASURED 2026-10-16: rc=0, 1004 rows. **RETARGETED.** This read
# `.agents/slop/notes/rz-oracle.py`, deleted by the sweep of 2026-10-05 (blob e853efc4b,
# 11868 B) and RED when recovered: it dies `AttributeError: 'str' object has no attribute
# 'name'` inside the live `tinygrad/engine/realize.py:26`, whose `ast.arg.name == "encdec"`
# now expects a UOp where the old fixture passed a plain string. Its replacement calls the
# same twelve functions of the same module over a fixture that mirrors `main_arena`.
#
# -- so the expectations are the interpreter and not a transcription of this
# file's own reading of it. Where the port DEVIATES from Python on purpose, the
# row says so in its name and the reason is at the def.
#
# THE ORACLE FIXTURE AND THIS ONE ARE THE SAME SHAPE: a program CALL over a
# global BUFFER and a bound PARAM, a STORE call, an `encdec` call, a `validate`
# call, a LINEAR nest, a SINK-body CALL with `beam` 0 and with `beam` 2, and a
# PROGRAM with a BINARY last src. `main_arena`'s comment numbers every node.
#
# The rows that are NOT direct CPython numbers, and why:
#   * `*_len`, `gate_count`, `arena_n`  -- structural COUNTS, not values.
#   * `res_ms_same`                     -- the MSTACK WALL: this file answers an
#                                         MSTACK unchanged, so the row asserts the
#                                         omission rather than hiding it.
#   * `lin_len`, `lin_first`            -- the REWRITE's shape. CPython's fixture
#                                         inner LINEAR has TWO srcs, so flattening
#                                         gives `want_lin_nsrc = 3`; this fixture's
#                                         has one, so 2 is right HERE.
#   * `arg_len`                         -- `want_args_len = 1`, because the
#                                         oracle's call passes a BOUND variable.
#                                         This fixture's `callP` passes two UNBOUND
#                                         PARAMs, so 2 is right here; `arg_len_b` is
#                                         the row shaped like the oracle's and is 1.
#   * `oi_in_e`                         -- `want_oi_enc` is `((0,), ())`, because
#                                         the oracle's `encdec` call also carries a
#                                         bound variable and drops to one arg uop.
#                                         This fixture's does not.
#   * `beam_new`                        -- `want_beam_val = 3`; the port passes
#                                         `ctx = 7`, and the row is that the
#                                         rewritten sink's `KernelInfo.beam` IS the
#                                         ctx value.
#   * `lin_none`, `beam_skip`           -- spelled `9`, not `0`. Both are
#                                         `rewrite` answering `None`, which is
#                                         `VSkip`, which `show_v` spells `9`; the
#                                         oracle prints `want_lin_none = True` and
#                                         `want_beam_skip = True` for "is None".
#                                         The two rows were documented as `1` and
#                                         `0` here, which was a MISPELLING of the
#                                         same answer and is corrected above.
# ===========================================================================
# `get_call_name` answers a `Maybe<String>`, so its gate row prints the string
# itself and answers `"None"` for the miss -- which is `str(None)` in Python, so
# the row is comparable with what the oracle prints for a None answer.
def row_s2(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case _: "None"

def gate_count() -> U32: 66

def main() -> IO(Unit):
  +l = main_arena()
  +p = plants_arena()
  do IO<Unit>:
    IO.print(String.concat(["arena_n=", U32.show(t_arena_n(l))]))
    IO.print(String.concat(["gate_count=", U32.show(gate_count())]))
    IO.print(String.concat(["flat_len=", U32.show(t_flat_len())]))
    IO.print(String.concat(["va_len=", U32.show(t_va_len())]))
    IO.print(String.concat(["beam_len=", U32.show(t_beam_len())]))
    IO.print(String.concat(["arg_len=", U32.show(t_arg_len(l))]))
    IO.print(String.concat(["arg_len_b=", U32.show(t_arg_len_b(l))]))
    IO.print(String.concat(["arg_len_var=", U32.show(t_arg_len_var(l))]))
    IO.print(String.concat(["oi_out_p=", U32.show(t_oi_out_p(l))]))
    IO.print(String.concat(["oi_out_s=", U32.show(t_oi_out_s(l))]))
    IO.print(String.concat(["oi_in_p=", U32.show(t_oi_in_p(l))]))
    IO.print(String.concat(["oi_in_e=", U32.show(t_oi_in_e(l))]))
    IO.print(String.concat(["oi_out_v=", U32.show(t_oi_out_v(l))]))
    IO.print(String.concat(["oi_in_v=", U32.show(t_oi_in_v(l))]))
    IO.print(String.concat(["wbuf_p=", U32.show(t_wbuf_p(l))]))
    IO.print(String.concat(["wbuf_buf=", U32.show(t_wbuf_buf(l))]))
    IO.print(String.concat(["kern_p=", U32.show(t_kern_p(l))]))
    IO.print(String.concat(["kern_v=", U32.show(t_kern_v(l))]))
    IO.print(String.concat(["ka_none_len=", U32.show(t_ka_len(p, 0))]))
    IO.print(String.concat(["ka_none_addr=", U32.show(t_ka_addr(p, 0, 0))]))
    IO.print(String.concat(["ka_zero_len=", U32.show(t_ka_len(p, 1))]))
    IO.print(String.concat(["ka_zero_cast=", U32.show(t_ka_cast(p, 1, 0))]))
    IO.print(String.concat(["ka_unb_len=", U32.show(t_ka_len(p, 2))]))
    IO.print(String.concat(["ka_unb_param=", U32.show(t_ka_param(p, 2, 0))]))
    IO.print(String.concat(["ka_unb_slotless=", U32.show(t_ka_slotless(p, 2, 0))]))
    IO.print(String.concat(["ka_unb_arglen=", U32.show(t_ka_arglen(p, 2))]))
    IO.print(String.concat(["ka_af_len=", U32.show(t_ka_len(p, 3))]))
    IO.print(String.concat(["ka_af_p0=", U32.show(t_ka_param(p, 3, 0))]))
    IO.print(String.concat(["ka_af_a1=", U32.show(t_ka_addr(p, 3, 1))]))
    IO.print(String.concat(["ka_af_slotless=", U32.show(t_ka_slotless(p, 3, 0))]))
    IO.print(String.concat(["ka_bf_len=", U32.show(t_ka_len(p, 4))]))
    IO.print(String.concat(["ka_bf_a0=", U32.show(t_ka_addr(p, 4, 0))]))
    IO.print(String.concat(["ka_bf_p1=", U32.show(t_ka_param(p, 4, 1))]))
    IO.print(String.concat(["ka_bf_slotless=", U32.show(t_ka_slotless(p, 4, 1))]))
    IO.print(String.concat(["ka_sh_len=", U32.show(t_ka_len(p, 5))]))
    IO.print(String.concat(["ka_sh_cast=", U32.show(t_ka_cast(p, 5, 1))]))
    IO.print(String.concat(["ka_sh_a0=", U32.show(t_ka_addr(p, 5, 0))]))
    IO.print(String.concat(["name_p=", row_s2(t_name_p(l))]))
    IO.print(String.concat(["res_len=", U32.show(t_res_len(l))]))
    IO.print(String.concat(["res_slot0=", U32.show(t_res_slot0(l))]))
    IO.print(String.concat(["res_slot1=", U32.show(t_res_slot1(l))]))
    IO.print(String.concat(["res_ms_same=", U32.show(t_res_ms_same(l))]))
    IO.print(String.concat(["dnum_p=", U32.show(t_dnum_p(l))]))
    IO.print(String.concat(["dnum_d=", U32.show(t_dnum_d(l))]))
    IO.print(String.concat(["dnum_n=", U32.show(t_dnum_n(l))]))
    IO.print(String.concat(["gcc_p=", U32.show(t_gcc_p(l))]))
    IO.print(String.concat(["gcc_c=", U32.show(t_gcc_c(l))]))
    IO.print(String.concat(["gcc_s=", U32.show(t_gcc_s(l))]))
    IO.print(String.concat(["gcc_k=", U32.show(t_gcc_k(l))]))
    IO.print(String.concat(["est_copy_s=", U32.show(t_est_copy_s(l))]))
    IO.print(String.concat(["est_copy_p=", U32.show(t_est_copy_p(l))]))
    IO.print(String.concat(["ctx_stats=", U32.show(t_ctx_stats())]))
    IO.print(String.concat(["ctx_jit=", U32.show(t_ctx_jit())]))
    IO.print(String.concat(["ctx_wait=", U32.show(t_ctx_wait())]))
    IO.print(String.concat(["ctx_cache=", U32.show(t_ctx_cache())]))
    IO.print(String.concat(["ctx_timeout=", U32.show(t_ctx_timeout())]))
    IO.print(String.concat(["ctx_inputs=", U32.show(t_ctx_inputs())]))
    IO.print(String.concat(["ctx_time=", U32.show(t_ctx_time())]))
    IO.print(String.concat(["ctx_time_cache=", U32.show(t_ctx_time_cache())]))
    IO.print(String.concat(["lin_fired=", U32.show(t_lin_fired(l))]))
    IO.print(String.concat(["lin_none=", U32.show(t_lin_none(l))]))
    IO.print(String.concat(["lin_len=", U32.show(t_lin_len(l))]))
    IO.print(String.concat(["lin_first=", U32.show(t_lin_first(l))]))
    IO.print(String.concat(["beam_fired=", U32.show(t_beam_fired(l))]))
    IO.print(String.concat(["beam_skip=", U32.show(t_beam_skip(l))]))
    IO.print(String.concat(["beam_new=", U32.show(t_beam_new(l))]))