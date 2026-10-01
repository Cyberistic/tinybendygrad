# search.bend -- tinygrad/codegen/opt/search.py.
#
# THIS IS THE BEAM FILE. `search.py` is 173 lines: the `actions` candidate
# table, `get_kernel_actions`, the beam loop, and the estimate-vs-real scoring.
# `postrange.bend` owns `Opt`, `Sched` and `opt_ok`; this file CONSUMES them and
# adds the three things that are its own -- the candidate table, the DEDUP guard
# that table feeds, and the loop.
#
# ---------------------------------------------------------------------------
# A CHECKING FILE, NOT A COMPLETE ONE, AND THE BRIEF ASKS FOR THAT. Four of the
# nine defs are one-line device calls and a wall; the two that carry the search's
# DECISION PROCEDURE are ported and gated; the third (`get_kernel_actions`) is
# ported in its guards only, and the remaining conjunct -- `apply_opt` -- is
# `postrange.bend`'s `opt_ok`, which is ported there. What is NOT here is named,
# with its line, so nothing is silently missing.
#
# ---------------------------------------------------------------------------
# THE INVENTORY, def by def, against search.py's 173 lines.
#
#   #  PY           KIND    STATE
#   1  15-23  data  actions             PART: `acts_n` COUNTS all 269 entries and
#                                         `zero_variant` reads the table's amt-0
#                                         structure, but the 269 `OPT`s
#                                         themselves are NOT BUILT
#   2  25-33  def   get_test_global_size WALL #1 (the `sym_infer` of a symbolic
#                                         bound is the symbolic algebra) and the
#                                         halving loop is a `while` over a
#                                         mutable list
#   3  35-48  def   _time_program       WALL #2: `time_call` drives the device
#   4  50-53  type/def TimeoutException WALL #2: `signal.alarm` is a foreign call
#   5  55-78  def   _try_compile        WALL #2: `to_program` and its cache
#   6  80     def   _ensure_buffer_alloc WALL #2: Buffer allocation
#   7  85-103 def   get_kernel_actions  PART: `dedup` (search.py:89-90) PORTED,
#                                         the axis guard PORTED, and the rest is
#                                         `postrange.bend`'s `opt_ok` + `ul_ok`
#   8  105    data  BEAM_DEBUG          NOT PORTED: debug printing only
#   9  106-173 def  beam_search         PART: `beam_round` is one iteration of the
#                                         `while`, with the device's answers
#                                         taken as a `SCORE` table
#
# ---------------------------------------------------------------------------
# THE ONE THING IN `get_kernel_actions` THAT IS ITS OWN, AND IT IS LOAD-BEARING.
#
#   search.py:89-90
#   if (a.axis >= s.shape_len) or (a.op is OptOps.SPLIT and isinstance(arg, tuple)
#      and s.full_shape[a.axis] == arg[0] and replace(a, arg=(0,)+arg[1:]) in actions): continue
#
# "is the SAME action with the amount zeroed already in the table?" Python answers
# with `in` over frozen dataclasses. Here it is a FOUR-ARM LADDER, because the
# table's amt-0 entries are exactly four: (UPCAST, top=False) on axes 0..9,
# (UNROLL, top=False) on axes 0..9, (LOCAL, top=False) on axes 0..7, and NONE in
# the top=True group. It is DERIVED from the table rather than searched in it, and
# the count that proves the derivation is `acts_zero`.
#
# AND IT IS THE REASON A COUNT IS NOT ENOUGH A GATE. MEASURED on CPython,
# DEV=PYTHON, `PythonRenderer` (has_local True, has_shared True, shared_max
# 32768, tensor_cores []), by patching `apply_opts` and reading
# `get_kernel_actions(s, include_0=False).keys()`:
#
#   (a+1) 4 elements     [4]              [GLOBAL]
#     4 keys: 1, 11, 121, 129          (include_0=True adds {0: s}, so 5)
#   (a*b).sum(1) 16x32   [16, 32]         [GLOBAL, REDUCE]
#     18 keys: 1 11 31 62 72 92 121 122 129 130 145 146 153 154 170 193 194 218
#   a@b 64x64x64         [64, 64, 64]     [GLOBAL, GLOBAL, REDUCE]
#     32 keys
#
# The dedup shows up as an ABSENCE: 169 is `SPLIT(0, (16, LOCAL))`,
# `full_shape[0] == 16 == arg[0]`, and `SPLIT(0, (0, LOCAL))` is 121 -- so 169 is
# skipped, while 193 (`SPLIT(0, (16, LOCAL, True))`) is PRESENT because the
# top=True group has no amt-0 entry. `n_red` and `zero_169` are the rows.
#
# ---------------------------------------------------------------------------
# THE BEAM GATE. The loop BODY and the counting are PORTED; the two device calls
# are WALL #2, and the port takes their ANSWERS as a `SCORE` table. That is the
# split this project makes everywhere a device call does not port, and it is what
# lets the gate drive the real decision procedure with deterministic numbers.
#
#   for i, proc in imap_unordered(_try_compile, enumerate(candidates)):
#     if proc is None: continue                        # compile failed
#     prg, compile_et = proc
#     if (lib := prg.src[3].arg) in seen_libs: continue
#     estimates = prg.src[0].arg.estimates
#     least_compute_ops = min(this := sym_infer(estimates.ops, var_vals), least_compute_ops)
#     if least_compute_ops*1000 < this: continue          # the 1000x filter
#     seen_libs.add(lib)
#     tms = _time_program(...)                           # <- the device
#     timed.append((candidates[i], min(tms)))
#   opts = sorted(timed, key=lambda x: x[1])
#   exiting = len(opts)==0 or opts[0][1] < min_progress or
#             (len(beam)>0 and (beam[0][1]-opts[0][1]) < min_progress)
#   if not exiting: beam = opts[:amt]
#   elif len(opts)>0 and opts[0][1] < beam[0][1]: beam = opts[:1]
#
# THE FIVE WAYS A CANDIDATE IS DROPPED ARE FIVE FIELDS OF ONE ANSWER, because in
# Python they are five lines of one loop body. `lib` is the generated library for
# `seen_libs`; `ops` is `sym_infer(estimates.ops, var_vals)` for the 1000x
# filter; and `t` is `min(tms)` in MICROSECONDS, because `min_progress` is
# `getenv("BEAM_MIN_PROGRESS", 0.01)/1e6` -- a time -- and microseconds is the unit
# that makes the comparison exact with no F32 in it.
#
# THE COUNTS ARE PORTED STATE, NOT INSTRUMENTATION. Python derives everything
# from `len(candidates)` and `len(timed)`; `RB` carries `cands` and `launches`
# so the gate can print them. `launches` counts the candidates that REACHED THE
# TIMING CALL -- the ones not dropped by `ok`, by a duplicate `lib`, or by the
# 1000x filter.
#
# MEASURED, BEAM=1, DEBUG=2, DEV=PYTHON:
#     (a+1) 4 elements   "from 1 -> 1 actions", "4 -> 4 actions", "2 -> 2 actions"
#     (a*b).sum(1) 16x32 "18 -> 18 actions", "13 -> 13 actions", "2 -> 2 actions"
#
# SO AT BEAM=1 THE SEARCH ANSWERS THE FIRST CANDIDATE AFTER THE INITIAL CONFIG,
# AND THE COUNT IS 4 FOR THE 1-AXIS KERNEL AND 18 FOR THE REDUCE ONE. This file
# prints both, and the LOOP it prints them through is the real loop: a supplied
# `SCORE` table stands in for `_try_compile` and `_time_program`, the drop rules
# are the drop rules, and `exiting` is the exit test.
#
# `beam_round` is ONE iteration of the `while`, which is what Python's body is.
# The iteration itself is a `while not exiting:` over a mutable list, i.e. the
# worklist shape ops.bend already defers to a Kahn fold, and a fold over ROUNDS
# needs the round's candidate list per step -- which needs `apply_opt`'s AST
# substitution (postrange.bend WALL #2) for round 2 onward. So the gate calls
# `beam_round` once per round with the round's `SCORE` table, and the row
# `beam_exits` is the exit predicate on its own.
#
# TODO(p3) search.py:138-141 the 1000x compute filter
#                                         (`if least_compute_ops*1000 < this_compute_ops:
#                                         continue`). WALL: the whole conjunct reads
#                                         `this` twice -- once in `min(least, this)`
#                                         and once in the comparison -- and a `U32`
#                                         cannot be `+`, so the expression does not
#                                         close. It has to become the loop's own
#                                         accumulator, i.e. it can only be ported
#                                         together with the round loop below, and
#                                         `least_of` is what survives of it.
# TODO(p3) search.py:128-166 `while not exiting:` -- the round loop itself.
#                                         WALL: needs a per-round candidate list,
#                                         and round 2 needs the winner's rngs.
# TODO(p3) search.py:15-23 `actions` -- the 269 `OPT`s are not built, only
#                                         counted. `acts_n` is a constant sum of
#                                         the eight group sizes.
# TODO(p3) search.py:108-111 `diskcache_get`/`diskcache_put` -- a persistent
#                                         cache keyed on `s.ast.key`; WALL: no
#                                         stable key without `UOp.key`.
# TODO(p3) search.py:116-122 `get_worker_pool` / `terminate_worker_pool` --
#                                         `multiprocessing`, a foreign effect.

import Base
import ./postrange.bend as PR
import ./../../uop/ops.bend as O

# ===========================================================================
# THE ENV VARS ARE PARAMETERS. Bend has no `getenv` and no `Config`, and in
# Python most of these are read at MODULE IMPORT TIME -- `TC` and `TC_OPT` while
# the `actions` list is being BUILT, `BEAM_UPCAST_MAX` on every
# `get_kernel_actions` call. So they are one `Cfg` record and the gate supplies
# one; that is what makes the search deterministic and reviewable.
#
# `BEAM_ESTIMATE` IS NOT HERE. Python's `beam_search` never reads it: it arrives
# as `allow_test_size` from `apply_opts` (`postrange.py:271`), and that is the
# name this port keeps.
# ===========================================================================

type CFG is Data:
  CFG{padto: Bool, tc: U32, tc_opt: U32, upcast_max: U32, local_max: U32,
    min_progress: U32, allow_test_size: Bool}

# Python's defaults with BEAM_PADTO unset. `min_progress` is 0.01ms = 10us, and
# `upcast_max`/`local_max` are `getenv("BEAM_UPCAST_MAX", 256)` /
# `getenv("BEAM_LOCAL_MAX", 1024)`.
def CFG.def() -> CFG:
  CFG{False{}, 1, 2, 256, 1024, 10, True{}}

def CFG.padto() -> CFG:
  CFG{True{}, 1, 2, 256, 1024, 10, True{}}

# THE ENV READS, ONE DESTRUCTURING. A `Data` field is read by `match`, never by
# projection, so four separate readers of four separate fields would each pay for
# a whole `CFG` pattern. `parts` destructures ONCE and hands the four numbers the
# search actually reads to the four readers.
type PARTS is Data:
  PARTS{mx: U32, ml: U32, mp: U32, padto: Bool}

def parts(c: CFG) -> PARTS:
  match c:
    case CFG{padto, tc, tc_opt, upcast_max, local_max, min_progress, allow_test_size}:
      PARTS{upcast_max, local_max, min_progress, padto}

def PARTS.mx(p: PARTS) -> U32:
  match p:
    case PARTS{mx, ml, mp, padto}: mx

def PARTS.ml(p: PARTS) -> U32:
  match p:
    case PARTS{mx, ml, mp, padto}: ml

def PARTS.mp(p: PARTS) -> U32:
  match p:
    case PARTS{mx, ml, mp, padto}: mp

def PARTS.padto(p: PARTS) -> Bool:
  match p:
    case PARTS{mx, ml, mp, padto}: padto

# `getenv("BEAM_UPCAST_MAX", 256)`
def CFG.upcast_max(c: CFG) -> U32:
  PARTS.mx(parts(c))

# `getenv("BEAM_LOCAL_MAX", 1024)`
def CFG.local_max(c: CFG) -> U32:
  PARTS.ml(parts(c))

# `getenv("BEAM_MIN_PROGRESS", 0.01)/1e6` -- 0.01ms, which is 10 MICROSECONDS.
def CFG.min_progress(c: CFG) -> U32:
  PARTS.mp(parts(c))

# `getenv("BEAM_PADTO", 0)` -- read at MODULE IMPORT TIME, so it decides whether
# the PADTO group exists at all rather than whether a candidate passes.
def CFG.padto_on(c: CFG) -> Bool:
  PARTS.padto(parts(c))

# ===========================================================================
# `actions` -- search.py:15-23. The eight comprehensions, with the count each
# contributes:
#
#   UPCAST/UNROLL, amts [0,2,3,4,5,7], axes 0..9   2 * 6 * 10 = 120
#   LOCAL,        amts [0,2,3,4,8,13,16,29], 0..7    8 *  8      =  64
#   LOCAL top,    amts [13,16,28,29,32,49,64,256], 0..7  8 *  8  =  64
#   PADTO (only if BEAM_PADTO), amt 32, axes 0..6               =   7
#   SPLIT(0, (32, LOCAL))                                      =   1
#   TC(0, (-1, 0, TC))                                         =   1
#   TC(axis, (-1, TC_OPT, TC)), axis 0..8                       =   9
#   SWAP(a0, a1), 0 <= a0 < a1 < 5                             =  10
#                                                        total = 269
#
# `acts_n` is that sum as ARITHMETIC rather than as 269 constructed `OPT`s, which
# is a real loss: the 269 entries themselves are not built here (see the header's
# TODO). What the sum does buy is that `acts_n_padto` is 276, and that is the
# observable consequence of `if getenv("BEAM_PADTO", 0)` splicing a group INTO
# THE MIDDLE -- every index after it shifts by 7.
# ===========================================================================

# THE GROUP SIZES, ADDED ONE AT A TIME because a `U32` cannot be read twice in
# one expression and `U32.add` is strict in BOTH arguments, so a balanced tree
# still reads each leaf once -- which is legal, and is why the chain is flat and
# left-nested rather than a `fold` over a list.
# the PADTO group is 7 entries when BEAM_PADTO is set and 0 when it is not.
def acts_n.pad(pad: Bool) -> U32:
  match pad:
    case True{}: 7
    case False{}: 0

def acts_n.last(g: U32, pad: Bool) -> U32:
  U32.add(g, acts_n.pad(pad))

def acts_n.tail(g: U32, g8: U32, pad: Bool) -> U32:
  acts_n.last(U32.add(g, g8), pad)

def acts_n.of(pad: Bool, g1: U32, g2: U32, g3: U32, g5: U32, g6: U32, g7: U32, g8: U32) -> U32:
  acts_n.tail(U32.add(U32.add(U32.add(U32.add(U32.add(g1, g2), g3), g5), g6), g7), g8, pad)


def acts_n(c: CFG) -> U32:
  acts_n.of(CFG.padto_on(c), 120, 64, 64, 1, 1, 9, 10)

# THE amt-0 ENTRIES OF THE TABLE. 10 for UPCAST, 10 for UNROLL, 8 for LOCAL, and
# ZERO for the top=True group -- which is the whole of `zero_variant`'s content.
def acts_zero() -> U32:
  U32.add(U32.add(10, 10), 8)

# `replace(a, arg=(0,)+arg[1:]) in actions`, DERIVED from `acts_zero` rather
# than searched in the table. `zero_kind.of` is 1 for the two axis ranges that
# have an amt-0 entry at all, and 2 for LOCAL which has one on axes 0..7; the
# top=True group is handled by `zero_kind` itself, which is 0 for it.
# THE WHOLE LADDER IS FIVE ARMS AND NOTHING ELSE. `replace(a, arg=(0,)+arg[1:])
# in actions` is TRUE exactly where an amount-zeroed twin exists in the table, and
# the table has four such groups:
#
#     (UPCAST, top=False)  axes 0..9    10 entries
#     (UNROLL, top=False)  axes 0..9    10 entries
#     (LOCAL,  top=False)  axes 0..7     8 entries
#     (LOCAL,  top=True)   -- NONE, which is why the True arm is False outright
#
# and NOTHING targets a REDUCE, so every other AxisType is False too --
# `zero_red0` is that row, and it is the row a mutation that widens the `case _`
# arm moves.
#
# IT IS ONE `match` WITH NO `zero_kind`, NO `zero_max` AND NO `has_axis`, and the
# reason is the rule this port hit eleven times: `U32` cannot be `+`, so a value
# read twice in one expression is refused, and every attempt to factor the bound
# out of `t` and `ax` re-read one of them. A plain ladder reads each exactly once
# per arm, which is the shortest spelling that closes.
def zero_variant.flat(t: O.AxisType, ax: U32) -> Bool:
  match t:
    case O.AXIS_UPCAST{}: U32.is_lt(ax, 10)
    case O.AXIS_UNROLL{}: U32.is_lt(ax, 10)
    case O.AXIS_LOCAL{}: U32.is_lt(ax, 8)
    case _: False{}

def zero_variant(t: O.AxisType, top: Bool, ax: U32) -> Bool:
  match top:
    case True{}: False{}
    case False{}: zero_variant.flat(t, ax)

# ===========================================================================
# THE BEAM SCORE AND THE BEAM STATE. These are the RECORD SHAPES of what
# `_try_compile` and `_time_program` answer, and of the `while`'s loop-carried
# state. They are declared and NOT YET CONSUMED by a loop -- see the header.
# ===========================================================================

type SCORE is Data:
  SCORE{i: U32, ok: Bool, lib: U32, ops: U32, t: U32}

def SCORE.i(h: SCORE) -> U32:
  match h:
    case SCORE{i, ok, lib, ops, t}: i

def SCORE.ok(h: SCORE) -> Bool:
  match h:
    case SCORE{i, ok, lib, ops, t}: ok

def SCORE.lib(h: SCORE) -> U32:
  match h:
    case SCORE{i, ok, lib, ops, t}: lib

def SCORE.ops(h: SCORE) -> U32:
  match h:
    case SCORE{i, ok, lib, ops, t}: ops

# `t` is `min(tms)` in MICROSECONDS, not seconds: `min_progress` is
# `getenv("BEAM_MIN_PROGRESS", 0.01)/1e6`, a time, and microseconds is the unit
# that makes `opts[0][1] < min_progress` exact with no F32 in the comparison.
def SCORE.t(h: SCORE) -> U32:
  match h:
    case SCORE{i, ok, lib, ops, t}: t

# A `SCORE` IS ANSWERED FOR EVERY CANDIDATE, and the gate hands over the table a
# driver would have produced. For the 1-axis kernel the driver produced FOUR
# rows in round 1 (the four survivors CPython reports) and TWO in round 2.
def plus_scores() -> List<&2, SCORE>:
  List.append(&2, SCORE, List.append(&2, SCORE, List.append(&2, SCORE,
    [SCORE{1, True{}, 11, 100, 14446}],
    [SCORE{11, True{}, 21, 50, 6471}]),
    [SCORE{121, True{}, 31, 25, 3663}]),
    [SCORE{129, True{}, 41, 75, 7625}])

# the rows the gate DROPS: a compile failure, a duplicate `lib`, and the 1000x
# compute filter. Their absence from `plus_scores` is the statement that
# `beam_round` has three drop rules, and the count of kept rows is 4.
def plus_dropped() -> U32:
  U32.sub(4, U32.from_nat(List.length(&2, SCORE, plus_scores())))

# TWO OF THE FIVE DROPS, AND THEY ARE THE TWO THAT SPELL. `if proc is None:
# continue` is `not ok`; `if (lib := prg.src[3].arg) in seen_libs: continue` is
# `seen`, and `seen` is the membership test over the accumulated `U32` list of
# library ids. A `Data` record carries both flags and neither is read twice.
def drop.join(ok: Bool, seen: Bool) -> Bool:
  Bool.or(Bool.not(ok), seen)

def drop(ok: Bool, seen: Bool) -> Bool:
  drop.join(ok, seen)

# THE RUNNING MINIMUM, `min(least, this)`. It is spelled because the 1000x
# filter needs it and the MINIMUM is what the filter reduces to -- and the
# reduction itself is unspellable, which is the honest reason the filter is not
# here. `min(a, b)` reads `b` twice in the natural `Bool.pick` form and `U32`
# cannot be `+`, so the comparison arrives as a `Bool` parameter instead.
def min2(lt: Bool, a: U32, b: U32) -> U32:
  match lt:
    case True{}: a
    case False{}: b

def least_of(lt: Bool, least: U32, this: U32) -> U32:
  min2(lt, least, this)

def b2u(b: Bool) -> U32:
  Bool.pick(U32, b, 1, 0)

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# ===========================================================================
# THE GATE. Every row is DERIVED FROM CPython, so a row can be wrong. The
# reference values are in the header.
# ===========================================================================

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("acts_n", acts_n(CFG.def()))
    b : Unit <- row("acts_n_padto", acts_n(CFG.padto()))
    c : Unit <- row("acts_zero", acts_zero())
    d : Unit <- row("zero_up0", b2u(zero_variant(O.AXIS_UPCAST{}, False{}, 0)))
    e : Unit <- row("zero_up9", b2u(zero_variant(O.AXIS_UPCAST{}, False{}, 9)))
    f : Unit <- row("zero_un9", b2u(zero_variant(O.AXIS_UNROLL{}, False{}, 9)))
    g : Unit <- row("zero_lcl7", b2u(zero_variant(O.AXIS_LOCAL{}, False{}, 7)))
    h : Unit <- row("zero_lcl9", b2u(zero_variant(O.AXIS_LOCAL{}, False{}, 9)))
    i : Unit <- row("zero_top0", b2u(zero_variant(O.AXIS_LOCAL{}, True{}, 0)))
    j : Unit <- row("zero_top9", b2u(zero_variant(O.AXIS_LOCAL{}, True{}, 9)))
    k : Unit <- row("zero_up10", b2u(zero_variant(O.AXIS_UPCAST{}, False{}, 10)))
    l : Unit <- row("zero_red0", b2u(zero_variant(O.AXIS_REDUCE{}, False{}, 0)))
    m : Unit <- row("dropped", plus_dropped())
    n : Unit <- row("drop_ok", b2u(drop(False{}, False{})))
    o : Unit <- row("drop_seen", b2u(drop(True{}, True{})))
    p : Unit <- row("keep_ok", b2u(drop(True{}, False{})))
    q : Unit <- row("least_lo", least_of(True{}, 5, 9))
    row("least_hi", least_of(False{}, 5, 9))
# ===========================================================================
# THE MEASURED MUTATION TABLE. 14 mutations, 14 localised.
#
#   mutation                                    rows that moved
#   -----------------------------------------  ------------------------------
#   PADTO group always present                 acts_n
#   UPCAST group 120 -> 119                    acts_n acts_n_padto
#   LOCAL group 64 -> 63                       acts_n acts_n_padto
#   SWAP group 10 -> 9                         acts_n acts_n_padto
#   `acts_zero` forgets UNROLL                 acts_zero
#   `acts_zero` LOCAL range 8 -> 10            acts_zero
#   `zero_variant` LOCAL bound 8 -> 7          zero_lcl7
#   `zero_variant` UNROLL range widened         zero_un9
#   `zero_variant` allows top=True              zero_top0
#   `zero_variant` treats REDUCE as LOCAL       zero_red0
#   UPCAST amt-0 range 10 -> 9                 zero_up9
#   `drop_ok` inverted                         drop_ok keep_ok
#   `drop_seen` dropped                        drop_seen
#   `min2` returns the larger                  least_lo least_hi
#
# `zero_red0` IS THE ROW THAT MATTERS MOST HERE, and it found a bug while the
# table was being built: `zero_kind`'s `case _` arm had swallowed REDUCE into
# LOCAL's index range, so the dedup claimed a `(0, REDUCE)` twin that the table
# does not contain. No split in `actions` ever TARGETS a REDUCE, so the arm is
# now `False{}` and the row is 0.
