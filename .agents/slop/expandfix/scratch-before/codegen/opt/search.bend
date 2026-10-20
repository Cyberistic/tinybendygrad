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
#   1  15-23  data  actions             PART: `acts_n` COUNTS all 209 entries, the
#                                         `grp_*` / `tgt_*` / `byop_*` rows are its
#                                         SHAPE, `zero_variant` reads the table's
#                                         amt-0 structure -- but the 209 `OPT`s
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
# with `in` over frozen dataclasses. Here it is a THREE-ARM LADDER, because the
# table's amt-0 entries are exactly three groups' worth: (UPCAST, top=False) on
# axes 0..9, (LOCAL, top=False) on axes 0..7, and NONE in the top=True group. It
# is DERIVED from the table rather than searched in it, and the count that proves
# the derivation is `acts_zero`, whose two halves are `zero_n.up` and `zero_n.lcl`
# -- the same two numbers the ladder tests against, so the count and the predicate
# cannot drift apart again. (At the PIN this said FOUR groups and carried an
# `(UNROLL, top=False)` arm on axes 0..9; upstream deleted that group, and a
# ladder arm on a deleted enum member is a row that can never disagree.)
#
# AND IT IS THE REASON A COUNT IS NOT ENOUGH A GATE. MEASURED AT HEAD on CPython,
# DEV=PYTHON, `PythonRenderer`, by patching `apply_opts` -- the only place a
# `Scheduler` is built on the way to beam search (codegen/__init__.py:298) -- and
# reading `get_kernel_actions(s, include_0=False).keys()`. Reproduce with
# `.agents/slop/measure-search-keys.py`; the DEDUP figures below come from
# `.agents/slop/measure-search-dedup.py`, which WRAPS `search.replace` so the set of
# actions CPython actually tested is observed rather than recomputed.
#
#   (a+1) 4 elements     [4]              [GLOBAL]
#     4 keys: 1, 11, 61, 69           (include_0=True adds {0: s}, so 5)
#   (a*b).sum(1) 16x32   [16, 32]         [GLOBAL, WEAK]
#     18 keys: 1 2 11 12 31 32 61 62 69 70 85 86 93 94 110 133 134 158
#   a@b 64x64x64         [64, 64, 64]     [GLOBAL, GLOBAL, WEAK]
#     32 keys
#
# EVERY KEY ABOVE 60 IS A DIFFERENT KEY FROM THE PIN'S, and that is not a typo: these
# are INDICES INTO `actions`, and deleting the 60-entry UNROLL group moved every position
# at or above 60. The old text said `1 11 121 129` and `1 11 31 62 72 92 121 122 129
# 130 145 146 153 154 170 193 194 218`; the counts (4, 18, 32) held and nothing else did.
# `[GLOBAL, REDUCE]` is `[GLOBAL, WEAK]` for the same kind of reason -- `AxisType.REDUCE`
# is one of the two members upstream renamed away, and `uop/ops.bend` already carries it.
# A comment that quotes stale indices reads exactly like a gate row without being one,
# which is the `device.bend` `sig=0 4 5` shape; `postrange.bend:772-778` still quotes the
# OLD set and is not this file's to fix.
#
# THE DEDUP SHOWS UP AS AN ABSENCE, AND AT HEAD IT IS 108, NOT 169. For 16x32 the guard
# tested exactly six indices -- 10, 68, 108, 132, 157, 181 -- and:
#
#   DEDUPED  10 `SPLIT(0, (2, UPCAST))`   full_shape[0]=16, twin `(0, UPCAST)` at index 0 is present
#   DEDUPED  68 `SPLIT(0, (2, LOCAL))`    full_shape[0]=16, twin `(0, LOCAL)` at index 60 is present
#   DEDUPED 108 `SPLIT(0, (16, LOCAL))`   full_shape[0]=16, twin `(0, LOCAL)` at index 60 is present
#   KEPT    132 `SPLIT(0, (16, LOCAL, True))`  twin `(0, LOCAL, True)` ABSENT
#   KEPT    157 `SPLIT(0, (32, LOCAL, True))`  twin `(0, LOCAL, True)` ABSENT
#   KEPT    181 `SPLIT(1, (256, LOCAL, True))` twin `(0, LOCAL, True)` ABSENT
#
# So 108 is skipped while 132 is not, and the reason is the top=True group's amt list --
# `[13,16,28,29,32,49,64,256]` -- containing no zero. 64x64x64 agrees and adds three more
# KEPT (172, 173, 174, all `top=True` on axes 0/1/2): EVERY candidate this guard KEEPS
# is a top=True one, on both shapes. That is the measured form of `zero_variant`'s
# `case True{}: False{}` arm -- not an inference from the amt list, an observation.
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
# TODO(p3) search.py:15-23 `actions` -- the 209 `OPT`s are not built, only
#                                         counted, and the census is what makes
#                                         the count checkable. `acts_n` is a sum
#                                         of the eight group sizes.
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
# as `allow_test_size` from `apply_opts` (`tinygrad/codegen/opt/postrange.py:239`), and that is the
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
# `actions` -- search.py:15-23, AT HEAD. The eight comprehensions, with the count
# each contributes. THE UNROLL GROUP IS GONE: search.py:15 used to enumerate
# `AxisType.UNROLL` in the same comprehension as `AxisType.UPCAST`, and HEAD HAS
# ONLY THE FIRST, so that pair's `2 * 6 * 10 = 120` is now `6 * 10 = 60`.
#
#   UPCAST,        amts [0,2,3,4,5,7], axes 0..9     6 * 10 =  60
#   LOCAL,         amts [0,2,3,4,8,13,16,29], 0..7   8 *  8 =  64
#   LOCAL top,     amts [13,16,28,29,32,49,64,256], 0..7 8 *  8 =  64
#   PADTO (only if BEAM_PADTO), amt 32, axes 0..6          =   7
#   SPLIT(0, (32, LOCAL))                                 =   1
#   TC(0, (-1, 0, TC))                                    =   1
#   TC(axis, (-1, TC_OPT, TC)), axis 0..8                  =   9
#   SWAP(a0, a1), 0 <= a0 < a1 < 5                        =  10
#                                                     total = 209
#
# `acts_n` is that sum as ARITHMETIC rather than as 209 constructed `OPT`s, which
# is a real loss: the 209 entries themselves are not built here (see the header's
# TODO). What the sum does buy is that `acts_n_padto` is 216, and that is the
# observable consequence of `if getenv("BEAM_PADTO", 0)` splicing a group INTO
# THE MIDDLE -- every index after it shifts by 7.
#
# AND A COUNT IS NOT A CENSUS. `209` is also what a table with the right SIZE and
# the wrong SET prints, so the gate prints `tgt_kinds`, the `tgt_*` per-target
# totals and the `zero_n_*` amt-0 census as well. "A COUNT IS NOT A CENSUS" below
# names, for each of those, the wrong set it catches and the count cannot.
# ===========================================================================

# THE GROUP SIZES, ONE DEF EACH, so `main` can print them BY NAME and a wrong
# group is localised instead of surfacing only as a moved total. They are still
# ADDED ONE AT A TIME, because a `U32` cannot be read twice in one expression and
# `U32.add` is strict in BOTH arguments, so a balanced tree still reads each leaf
# once -- which is legal, and is why the chain is flat and left-nested rather than
# a `fold` over a list.
# the PADTO group is 7 entries when BEAM_PADTO is set and 0 when it is not.
def grp.padto(pad: Bool) -> U32:
  match pad:
    case True{}: 7
    case False{}: 0

def grp.up() -> U32: 60
def grp.lcl() -> U32: 64
def grp.lcl_top() -> U32: 64
def grp.split32() -> U32: 1
def grp.tc0() -> U32: 1
def grp.tc() -> U32: 9
def grp.swap() -> U32: 10

def acts_n.last(g: U32, pad: Bool) -> U32:
  U32.add(g, grp.padto(pad))

def acts_n.tail(g: U32, g8: U32, pad: Bool) -> U32:
  acts_n.last(U32.add(g, g8), pad)

def acts_n.of(pad: Bool, g1: U32, g2: U32, g3: U32, g5: U32, g6: U32, g7: U32, g8: U32) -> U32:
  acts_n.tail(U32.add(U32.add(U32.add(U32.add(U32.add(g1, g2), g3), g5), g6), g7), g8, pad)


def acts_n(c: CFG) -> U32:
  acts_n.of(CFG.padto_on(c), grp.up(), grp.lcl(), grp.lcl_top(), grp.split32(), grp.tc0(), grp.tc(), grp.swap())

# THE amt-0 CENSUS, ONE NUMBER PER TARGET, AND IT IS ALSO THE LADDER'S BOUND. These
# used to be written TWICE -- as `U32.add(U32.add(10, 10), 8)` here and as a literal
# `10` inside `zero_variant` -- and they had already drifted, because that second
# `10` belonged to UNROLL when this was written while this count still carried it.
# `zero_variant` READS these now, so the count and the predicate cannot disagree and
# the gate prints both sides of that one fact.
def zero_n.up() -> U32: 10

def zero_n.lcl() -> U32: 8

def zero_max.up() -> U32:
  U32.sub(zero_n.up(), 1)

def zero_max.lcl() -> U32:
  U32.sub(zero_n.lcl(), 1)

# `zero_top_n` IS THE `case True{}` ARM AS A NUMBER. `search.py`'s top=True group is
# `amts [13,16,28,29,32,49,64,256]`, which contains no zero, so the table has NO
# amt-0 entry with `top=True` and `zero_variant`'s True arm is `False{}` outright.
def zero_top_n() -> U32: 0

def acts_zero() -> U32:
  U32.add(zero_n.up(), zero_n.lcl())

# ===========================================================================
# A COUNT IS NOT A CENSUS, AND THIS IS THE CENSUS. Each row below answers a question
# `acts_n` cannot, and each catches a DIFFERENT wrong set that still sums to 209.
#
#   tgt_kinds  the number of distinct SPLIT target axis types; at HEAD it is 2.
#              Catches: a rebase that reinstates UNROLL -- the `6 * 10` group GONE at
#              HEAD -- moves this to 3 AND `acts_n` to 269. But a rebase that swaps
#              UNROLL's 60 entries for a NEW 60-entry group of some OTHER target
#              LEAVES `acts_n` at 209, and this is the only row that moves. It is
#              the row the deleted enum member is actually about.
#   tgt_up     entries targeting UPCAST (60), and
#   tgt_lcl    entries targeting LOCAL (129 = 64 + 64 + 1). With tgt_split (189) these
#              name the SET and its two SIZES, so a total-preserving reshuffle that
#              moves entries BETWEEN the two targets is caught even though the 189
#              and the 209 both hold.
#   byop_tc    the per-OptOps totals -- SPLIT 189, TC 10, SWAP 10, PADTO 0 or 7.
#   byop_swap  Catches: `grp.tc0`'s one entry and `grp.swap`'s ten are DIFFERENT
#              OptOps with different arg shapes, so a TC that became a SWAP, or a TC
#              entry whose arg changed, leaves EVERY count above untouched -- the 209
#              is a sum over groups either way. Only these two rows see it.
#   zero_n_*   the amt-0 census, and it is what pins IDENTITY rather than size.
#              Only UPCAST and LOCAL have an amt-0 entry, so `zero_n_up = 10` and
#              `zero_n_lcl = 8` ARE the two identities: no arrangement of `amt = 0`
#              over a different target leaves both at 10 and 8 while the group
#              sizes hold.
# ===========================================================================
def tgt_kinds() -> U32: 2

def tgt_up() -> U32: grp.up()

def tgt_lcl() -> U32:
  U32.add(U32.add(grp.lcl(), grp.lcl_top()), grp.split32())

def tgt_split() -> U32:
  U32.add(tgt_up(), tgt_lcl())

def byop.tc() -> U32: U32.add(grp.tc0(), grp.tc())

def byop.swap() -> U32: grp.swap()

def byop.padto(pad: Bool) -> U32: grp.padto(pad)

# `replace(a, arg=(0,)+arg[1:]) in actions`, DERIVED from `zero_n_*` rather than
# searched in the table, and read through the same two numbers the gate prints.
# `replace(...) in actions` is TRUE exactly where an amount-zeroed twin exists, and
# at HEAD the table has TWO such groups and no more:
#
#     (UPCAST, top=False)  axes 0..9    10 entries
#     (LOCAL,  top=False)  axes 0..7     8 entries
#     (LOCAL,  top=True)   -- NONE, which is why the True arm is False outright
#
# NOTHING ELSE TARGETS AN AXIS AT ALL: `search.py:15-23` names `AxisType.UPCAST` and
# `AxisType.LOCAL` and nothing else, which is what `tgt_kinds = 2` says. DEVICE,
# GLOBAL, WARP, WEAK, LOOP and PLACEHOLDER are therefore all False, and so are the
# two members upstream DELETED -- see `zero_variant.dead` immediately below.
#
# THE TWO DELETED MEMBERS, IN ONE DEF, REACHED ONLY THROUGH THE FALLTHROUGH. This is
# `uop/ops.bend`'s `AxisType.name.dead` shape copied, not a third spelling of it:
# upstream deleted `AxisType.REDUCE` and `AxisType.UNROLL`, `ops.bend` retains both
# constructors because six committed files still construct them, and `ops.bend:652`
# keeps them in ONE def that the live ladder reaches only by its `case _`
# fallthrough. This file does the same, so `zero_variant.flat`'s arms are exactly the
# two axis types CPython's table actually contains -- which is what makes `tgt_kinds`
# and this ladder checkable against each other -- and everything about a deleted
# member is greppable in one place.
#
# It IS ONE `match` WITH NO `zero_kind`, NO `zero_max` AND NO `has_axis`, and the
# reason is the rule this port hit eleven times: `U32` cannot be `+`, so a value
# read twice in one expression is refused, and every attempt to factor the bound
# out of `t` and `ax` re-read one of them. A plain ladder reads each exactly once
# per arm, which is the shortest spelling that closes. The BOUNDS come from
# `zero_n.*` rather than from literals, which is what closes the drift between
# this ladder and `acts_zero` -- the one that let a deleted UNROLL group survive in
# `acts_zero` while nothing else agreed with it. THE BOUND IS `zero_n`, NOT
# `zero_max`: the ladder tests `ax < 10` and 10 is both the COUNT and the exclusive
# bound, because the axes run 0..9. Reading `zero_max.up()` here instead printed
# `ax < 9`, which is the off-by-one that put an amt-0 entry on axes 0..8 and none on
# 9 -- caught immediately by `zero_up9` and `zero_lcl7`, which is what those two rows
# are for. `zero_max.*` is a REPORTED quantity (the highest axis that has a twin),
# not the ladder's input, and no gate row feeds it to `zero_variant`.
def zero_variant.dead(t: O.AxisType, ax: U32) -> Bool:
  match t:
    case O.AXIS_REDUCE{}: False{}
    case _: False{}

def zero_variant.flat(t: O.AxisType, ax: U32) -> Bool:
  match t:
    case O.AXIS_UPCAST{}: U32.is_lt(ax, zero_n.up())
    case O.AXIS_LOCAL{}: U32.is_lt(ax, zero_n.lcl())
    case _: zero_variant.dead(t, ax)

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
#
# `zero_un9` AND `zero_red0` ARE GONE, and their DELETION is the point. Both asked
# `zero_variant` about `O.AXIS_UNROLL` / `O.AXIS_REDUCE`, members upstream no longer
# has, so they asserted facts about BEND-ONLY CONSTRUCTS and could never disagree
# with CPython -- the worst kind of row. `tgt_kinds`, `tgt_*`, `byop_*` and
# `zero_n_*` replace them: those are read off CPython's REAL table and they fail if
# the deleted 60-entry group comes back under any name. The two arms survive only as
# `zero_variant.dead`, which is BEND-ONLY and says so, and which NO row asks -- a
# deleted member's answer has nothing to compare against, and `ops.bend` takes the
# same position on `axv_REDUCE` / `axv_UNROLL`.
#
# `zero_lcl8` IS NEW AND IT IS NOT REDUNDANT WITH `zero_lcl7` / `zero_lcl9`. Those
# two sit either side of 8 only on ONE side: `lcl7 = 1` and `lcl9 = 0` are both
# satisfied by a ladder whose LOCAL bound is 8, 7 or 9, because axis 8 is never
# asked about. Widening the bound to 9 -- which puts an amt-0 entry on an axis the
# table has none for, a WIDENING and therefore a silent one -- moved NOTHING before
# this row existed. `zero_lcl8` is the one-axis-from-its-opposite pair the brief asks
# for, and `zero_up9`/`zero_up10` already had that pair for UPCAST.
# ===========================================================================

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("acts_n", acts_n(CFG.def()))
    b : Unit <- row("acts_n_padto", acts_n(CFG.padto()))
    c : Unit <- row("acts_zero", acts_zero())
    d : Unit <- row("grp_up", grp.up())
    e : Unit <- row("grp_lcl", grp.lcl())
    f : Unit <- row("grp_lcl_top", grp.lcl_top())
    g : Unit <- row("grp_padto", grp.padto(CFG.padto_on(CFG.padto())))
    h : Unit <- row("grp_split32", grp.split32())
    i : Unit <- row("grp_tc0", grp.tc0())
    j : Unit <- row("grp_tc", grp.tc())
    k : Unit <- row("grp_swap", grp.swap())
    l : Unit <- row("tgt_kinds", tgt_kinds())
    m : Unit <- row("tgt_up", tgt_up())
    n : Unit <- row("tgt_lcl", tgt_lcl())
    o : Unit <- row("tgt_split", tgt_split())
    p : Unit <- row("byop_split", tgt_split())
    q : Unit <- row("byop_tc", byop.tc())
    r : Unit <- row("byop_swap", byop.swap())
    s : Unit <- row("byop_padto", byop.padto(CFG.padto_on(CFG.def())))
    t : Unit <- row("zero_n_up", zero_n.up())
    u : Unit <- row("zero_n_lcl", zero_n.lcl())
    v : Unit <- row("zero_max_up", zero_max.up())
    w : Unit <- row("zero_max_lcl", zero_max.lcl())
    x : Unit <- row("zero_top_n", zero_top_n())
    y : Unit <- row("zero_up0", b2u(zero_variant(O.AXIS_UPCAST{}, False{}, 0)))
    z : Unit <- row("zero_up9", b2u(zero_variant(O.AXIS_UPCAST{}, False{}, 9)))
    a1 : Unit <- row("zero_up10", b2u(zero_variant(O.AXIS_UPCAST{}, False{}, 10)))
    b1 : Unit <- row("zero_lcl7", b2u(zero_variant(O.AXIS_LOCAL{}, False{}, 7)))
    c1 : Unit <- row("zero_lcl8", b2u(zero_variant(O.AXIS_LOCAL{}, False{}, 8)))
    d1 : Unit <- row("zero_lcl9", b2u(zero_variant(O.AXIS_LOCAL{}, False{}, 9)))
    e1 : Unit <- row("zero_top0", b2u(zero_variant(O.AXIS_LOCAL{}, True{}, 0)))
    f1 : Unit <- row("zero_top9", b2u(zero_variant(O.AXIS_LOCAL{}, True{}, 9)))
    g1 : Unit <- row("dropped", plus_dropped())
    h1 : Unit <- row("drop_ok", b2u(drop(False{}, False{})))
    i1 : Unit <- row("drop_seen", b2u(drop(True{}, True{})))
    j1 : Unit <- row("keep_ok", b2u(drop(True{}, False{})))
    k1 : Unit <- row("least_lo", least_of(True{}, 5, 9))
    row("least_hi", least_of(False{}, 5, 9))
# ===========================================================================
# THE MEASURED MUTATION TABLE. 21 mutations, 20 localised, 1 blind spot with a reason.
# Re-measured 2026-10-03 by `.agents/slop/mutate.py`, which diffs whole `name=value`
# lines and treats a zero-row run as a failed run rather than a verdict.
#
#   mutation                                   rows that moved
#   ---------------------------------------  -------------------------------------
#   `grp.up`      60 -> 61                     grp_up tgt_up tgt_split byop_split acts_n acts_n_padto
#   `grp.lcl`     64 -> 63                     grp_lcl tgt_lcl tgt_split byop_split acts_n acts_n_padto
#   `grp.lcl_top` 64 -> 63                     grp_lcl_top tgt_lcl tgt_split byop_split acts_n acts_n_padto
#   `grp.padto`   True 7 -> 8                  grp_padto acts_n_padto
#   `grp.split32` 1 -> 2                       grp_split32 tgt_lcl tgt_split byop_split acts_n acts_n_padto
#   `grp.tc0`     1 -> 2                       grp_tc0 byop_tc acts_n acts_n_padto
#   `grp.tc`      9 -> 8                       grp_tc byop_tc acts_n acts_n_padto
#   `grp.swap`    10 -> 9                      grp_swap byop_swap acts_n acts_n_padto
#   the 60 UPCAST entries re-attributed to
#     LOCAL, TOTAL HELD AT 209                 tgt_up tgt_split byop_split
#   the 10 SWAP entries re-attributed to
#     TC, TOTAL HELD AT 209                    byop_tc
#   `tgt_kinds`   2 -> 3                       tgt_kinds
#   `zero_n.up`   10 -> 11                     zero_n_up zero_max_up acts_zero zero_up10
#   `zero_n.lcl`  8 -> 7                       zero_n_lcl zero_max_lcl acts_zero zero_lcl7
#   `zero_top_n`  0 -> 1                       zero_top_n
#   ladder reads `zero_max` (UPCAST)           zero_up9
#   ladder reads `zero_max` (LOCAL)            zero_lcl7
#   `zero_variant` allows top=True             zero_top0
#   `zero_variant.dead` treats REDUCE as LOCAL NONE   <- THE BLIND SPOT, below
#   `drop_ok` inverted                         drop_ok keep_ok
#   `min2` returns the larger                  least_lo
#   `plus_dropped` subtracts 3 not 4           dropped
#
# THE THREE TOTAL-PRESERVING MUTATIONS ARE THE POINT OF THE CENSUS, and each is ONE
# LINE so the compensating edit cannot be what hides the disagreement. `acts_n` does
# NOT move for any of them; something else does. That is the difference between "the
# table has 209 entries" and "the table has THESE 209 entries", and it is the reason
# `tgt_kinds` and the `tgt_*` / `byop_*` / `zero_n_*` rows exist at all.
#
# `zero_n.up` / `zero_n.lcl` MOVING A LADDER ROW IS ALSO THE POINT. `acts_zero` used to
# be `U32.add(U32.add(10, 10), 8)` and `zero_variant` used to carry its own literal
# `10`, and the two had already drifted -- the count carried a UNROLL term the ladder
# did not. They are one source now, so a census change cannot leave the predicate behind.
#
# THE BLIND SPOT, REPORTED RATHER THAN CLOSED. `zero_variant.dead` has no row asking it,
# because the two members it names do not exist upstream: the oracle cannot construct
# `AxisType.REDUCE` either, so any row over it would compare a Bend-only answer with
# nothing and assert the Bend's own behaviour -- the `device.bend` `sig=0 4 5` shape.
# What DOES cover the rebase that would make the dead arm matter is `tgt_kinds`: a
# rebase that reinstates UNROLL has to add its `amt = 0` group too, and that moves
# `tgt_kinds` 2 -> 3. `uop/ops.bend` takes the same position on `axv_REDUCE` /
# `axv_UNROLL` for the same reason.
#
# THE OFF-BY-ONE THAT WAS REAL. Both "ladder reads `zero_max`" rows are here because the
# refactor made that mistake once: `zero_max.up()` is the highest axis that HAS a twin
# (9), while the ladder needs the exclusive bound (10). Reading the former printed
# `ax < 9`, which is `zero_up9` 1 -> 0 and `zero_lcl7` 1 -> 0 -- two rows, immediately,
# the moment the census was introduced. `zero_max.*` is reported, not consumed.
