# gpudims.bend -- tinygrad/codegen/gpudims.py: the GPU-dimension rules -- a DEVICE
# axis lowered to `_device_num`, one SINK-wide grouping pass, and HEAD's NEW
# `pm_range_to_special`.
#
# ---------------------------------------------------------------------------
# ONE OF THREE. `codegen/rewriter.bend` was ONE file for `simplify.py` +
# `late/coalesce.py` + `gpudims.py`; the 1:1 ruling -- one `.bend` per upstream
# `.py`, AT THE SAME PATH, no merging and no prefixes standing in for a directory
# -- made it three, and this is `gpudims.py`'s. The 54 rows the merged file printed
# CONCATENATE IN PYTHON'S ORDER (`simplify.bend`, `late/coalesce.bend`, then this)
# to exactly those 54, and `.agents/slop/codegen3-gate.sh` is that invariant
# against the pre-split snapshot. The cut itself is
# `.agents/slop/split-codegen3.py`, which moved every body by LINE RANGE.
#
# THE SHARED SUBSTRATE IS IMPORTED, NOT COPIED. `Rew` (the rule's answer), the
# `rw_*` node readers and `G` (the fixture's index map) live in
# `codegen/rewriter.bend` and every use here is `RW.<name>`. A TYPE MENTION needs
# the alias as well as a call -- an unqualified imported `type` name is not in
# scope -- so it is `RW.Rew` and `RW.Rew.ar`, never `Rew.ar`. A def is in the
# substrate iff at least TWO of the three files used it; every def only this file
# used came here.
#
# ---------------------------------------------------------------------------
# THE INVENTORY, def by def, against gpudims.py's 106 lines. Every `PY` range is
# re-derived from the file as it stands.
#
#   #  PY            KIND    STATE

#  29  7-8    fold   _dim_max                  NOT CLAIMED: `isinstance` + `vmax`
#  30  9-17   fold   _group_dims               PORTED for literal dims
#  31  18-27  fold   _split_dims               PORTED for literal dims
#  32  28-43  fold   get_grouped_dims          WALL: ssimplify, `_min_max`
#  33  44-90  fold   group_gpudims             WALL: dicts + ssimplify + ctx
#  34  93     fold   -- (pm_device_to_var r1)  WALL: UOp.variable
#  35  96     fold   -- (pm_device_to_var r2)  PORTED
#  36  101-102 table pm_group_gpudims          1 of 1 (1 + pm_device_to_var)
#  37  103-106 table pm_range_to_special       1 of 1 (+ pm_split_ends)
#
# Rows 34 and 35 are the two RULES of `pm_device_to_var`, gpudims.py:91-100,
# inventoried as one def. Of the eight: two are wholly PORTED as TABLES (36, 37),
# two are wholly a WALL (32, 33), one is MIXED (the device_to_var pair, one rule
# walled beside one ported) and three are NOT CLAIMED or ported only for literal
# dims (29, 30, 31).
#
# THE NAME CORRESPONDENCE: `pm_device_to_var` (gpudims.py:91), `pm_group_gpudims`
# (:101) and `pm_range_to_special` (:103) -- three of the eight, and the three
# that ARE tables upstream. The merged file called them `dv_table`, `gd_table` and
# `rs_table`, so this is THREE renames, all inside this file, all applied in ONE
# single-pass token rewrite by `.agents/slop/split-codegen3.py`, whose `--check`
# undoes them and finds the original bytes. The rule of `pm_range_to_special` is
# `rs_rule`/`rs_new`/`rs_at`/`rs_ids`/`rs_claimed`/`rs_name`/`rs_idlast`: upstream
# it is ONE lambda, so those are port-local and the naming rule does not apply.
#
# ---------------------------------------------------------------------------
# `t_se_len` IS LINEARIZER'S, and it is here anyway, because the ONLY rows that
# read it are this file's: `pm_range_to_special` is `PatternMatcher([RANGE rule]) +
# pm_split_ends`, and `pm_split_ends` is `late/linearizer.py`'s ONE `Ops.END` rule
# (`codegen/late/linearizer.bend` owns the body). So `pm_range_to_special`'s own
# length, `pm_split_ends`'s length and their difference are three numbers about
# one table, and they belong with the table. `linearizer.bend` and `gpudims.bend`
# therefore both know the number 1 and neither owns it -- REPORTED HERE so the
# duplication is visible rather than silent.
#
# ---------------------------------------------------------------------------
# THE GATE. Every row is DERIVED FROM PYTHON by `.agents/slop/notes/rw-truth.py`,
# which prints these rows in THIS ORDER and with THIS SPELLING. The other 30 rows
# of the old merged file are `simplify.bend`'s and `late/coalesce.bend`'s.
#
# ---------------------------------------------------------------------------
# THREE REDS BELONG TO ANOTHER UNIT. `rs_claim_warp`, `rs_claim_loop`,
# `rs_rewrite_warp` and `rs_rewrite_loop` were introduced by the rebase batch of
# 2026-10-03 and are KNOWN RED against HEAD: `AxisType.UNROLL` and
# `AxisType.REDUCE` were DELETED upstream, `x.axis_id` became `arg[1:]` and
# `r.axis_id[-1]` became `arg[0]`, and the four rows are green against the PIN and
# wrong at HEAD. This split does not fix them and does not mask them.
# `.agents/slop/codegen3-gate.sh` prints their before and after side by side and
# `split-codegen3.py --check` prints them too; if any MOVED, that is a finding for
# the unit that owns them, not something to absorb here.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./rewriter.bend as RW

#   -- gpudims.py ----------------------------------------------------------
#  29  7-8    fold   _dim_max                  NOT CLAIMED: `isinstance` + `vmax`
#  30  9-17   fold   _group_dims               PORTED for literal dims
#  31  18-27  fold   _split_dims               PORTED for literal dims
#  32  28-43  fold   get_grouped_dims          WALL: ssimplify, `_min_max`
#  33  44-90  fold   group_gpudims             WALL: dicts + ssimplify + ctx
#  34  93     fold   -- (pm_device_to_var r1)  WALL: UOp.variable
#  35  96     fold   -- (pm_device_to_var r2)  PORTED
#  36  101-102 table pm_group_gpudims          1 of 1 (1 + pm_device_to_var)
#  37  103-106 table pm_range_to_special       1 of 1 (+ pm_split_ends)

# ===========================================================================
# THE GPUDIMS TABLES, RE-DERIVED AT HEAD. `78d482262` RENAMED `add_gpudims` to
# `group_gpudims`, renamed `pm_add_gpudims` to `pm_group_gpudims`, and ADDED a
# second table `pm_range_to_special`. Two of the three are a RENAME and one is an
# ADDITION, and they need different work, which is why this is not one edit.
#
# THE RENAME IS NOT A LENGTH CHANGE, and that is the measured result that matters:
# `len(pm_add_gpudims.patterns) == 3` at the pin and `len(pm_group_gpudims.patterns)
# == 3` at HEAD (`.agents/slop/xd1/rw-oracle.py` rows `gd_pinname` / `gd_headname`,
# one tree each), with the SAME `ops` in the same order --
# `(Ops.SINK,), (Ops.RANGE,), (Ops.END,)`. So `gd_len` is 3 at BOTH ends and the
# existing row does not move. Re-pointing the NAME is the whole of the port for
# this table.
#
# AND THE BODY DID CHANGE UNDER THE NAME, which is the `hcq2.bend` rename lesson
# (`pm_hoist_links` / `pm_lift`) applied to `group_gpudims`. Five measured moves,
# all inside a def this file marks WALL:
#   * `all_ranges = {x.axis_id: x ...}`    -> `{x.arg: x ...}`   (the axis_id
#     property is now `arg[1:]`; upstream stopped calling it)
#   * `local_dims = sorted([...])`         -> `sorted(..., key=lambda x:
#     (x.axis_type is not AxisType.WARP, x.axis_id))`, so WARP first
#   * `if u.op is Ops.SPECIAL`             -> `if u.op is Ops.RANGE`
#   * `subs[idx] = idx.replace(...)`       -> `masks[idx] = ...`, a SECOND dict
#   * `return s.substitute(subs)`          -> `s.substitute(masks).substitute(subs,
#     walk=True)` -- two passes, the second walking
# and `get_grouped_dims` changed `UOp.special(s, f"{prefix}{i}")` to
# `UOp.range(s, i, GLOBAL or LOCAL)`. None of it is ported (`group_gpudims` is WALL:
# dicts + ssimplify + ctx), so the port's obligation is to RECORD it and not to
# pretend the rename was the whole change.
#
# THE ADDITION IS PORTABLE AND WAS NOT PORTED. `pm_range_to_special` is one rule
# plus `pm_split_ends`'s one, and the rule is pure: a RANGE whose `axis_type` is
# GLOBAL or LOCAL is REPLACED by a SPECIAL named `gidx{id}` / `lidx{id}`. Nothing
# in it needs `ssimplify`, a dict, or `ctx`, so the WALL that stops
# `group_gpudims` does not reach it.
# ===========================================================================
def pm_device_to_var() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsRANGE{}], Nil{}},                 # gpudims.py:93 RANGE axis DEVICE -> variable
   O.PMEntry{1, [O.OpsEND{}], [O.OpsPARAM{}]}]          # gpudims.py:96 END closes _device_num

def pm_group_gpudims() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsSINK{}], Nil{}},                  # gpudims.py:101 SINK group_gpudims, run ONCE
   O.PMEntry{1, [O.OpsRANGE{}], Nil{}},                 # gpudims.py:93 (pm_device_to_var)
   O.PMEntry{2, [O.OpsEND{}], [O.OpsPARAM{}]}]          # gpudims.py:96 (pm_device_to_var)

# `pm_range_to_special` -- HEAD's NEW table, gpudims.py:103-106. Two entries
# because it is `PatternMatcher([RANGE rule]) + pm_split_ends`, and `pm_split_ends`
# is linearizer.py's ONE `Ops.END` rule. `linearizer.py` is NOT MINE (see the
# header), so only the LENGTH and the `ops` are claimed here -- the END rule's BODY
# is linearizer's, and saying so is what keeps the inventory honest.
def pm_range_to_special() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsRANGE{}], Nil{}},                 # gpudims.py:105 RANGE GLOBAL/LOCAL -> SPECIAL
   O.PMEntry{1, [O.OpsEND{}], Nil{}}]                    # linearizer.py:95 do_split_ends (pm_split_ends)

# ===========================================================================
# `pm_range_to_special`'s ONE RULE, PORTED. gpudims.py:104-106:
#
#   (UPat(Ops.RANGE, name="r"), lambda r: r.replace(op=Ops.SPECIAL,
#      arg=f"{'g' if r.axis_type is AxisType.GLOBAL else 'l'}idx{r.axis_id[-1]}")
#    if r.axis_type in (AxisType.GLOBAL, AxisType.LOCAL) else None)
#
# IT IS PORTABLE, and that is why it is here rather than in the WALL list: there
# is no `ssimplify`, no dict, no `ctx` and no graph_rewrite in it. It is a GUARD
# and a REBUILD -- the guard reads `axis_type`, the rebuild replaces the op with
# `Ops.SPECIAL` and the arg with the name string, keeping the srcs and the tag.
#
# TWO SPELLINGS UPSTREAM USES AND THIS PORT READS BY NAME. `r.axis_type` and
# `r.axis_id` are PROPERTIES in Python (ops.py:499-509) and `78d482262` changed
# both BODIES -- `arg[0:-1]`/`arg[-1]` became `arg[1:]`/`arg[0]`. So the arg tuple
# is read through the properties and never by position, which is the same
# discipline `uop/render.bend`'s `range_ids` / `range_at` follow and the reason
# neither file moved when the tuple flipped. It is the ONE thing about the flip
# that is free.
#
# `r.replace(op=..., arg=...)` is `UOp.new` with a different op -- ops.bend has no
# `UOp.replace` (grep: `def UOp.replace` is ABSENT) and `UOp.new` is the same
# interning call, so this is the whole of the port. The TAG rides along: CPython's
# `replace` preserves it and `UOp.new` is handed `rw_tag(ar, r)`.
# ===========================================================================
def rs_at.of(a: O.Arg) -> O.AxisType:
  match a:
    case O.ARange{ids, at}: at
    case _: O.AXIS_LOOP{}

def rs_at(ar: O.Arena, +i: U32) -> O.AxisType: rs_at.of(RW.rw_arg(ar, i))

def rs_ids.of(a: O.Arg) -> List<&2, U32>:
  match a:
    case O.ARange{ids, at}: ids
    case _: Nil{}

def rs_ids(ar: O.Arena, +i: U32) -> List<&2, U32>: rs_ids.of(RW.rw_arg(ar, i))

# `r.axis_type in (AxisType.GLOBAL, AxisType.LOCAL)` -- TWO members, and the
# negative case matters: WARP, LOOP, WEAK, DEVICE and the two dead members all
# MISS, and a one-armed test would claim them. `rs_claim_*` below are those.
def rs_claimed(+at: O.AxisType) -> Bool:
  Bool.or(O.eq_axis(at, O.AXIS_GLOBAL{}), Bool.and(False{}, False{}))

def rs_name(+at: O.AxisType, id: U32) -> String:
  String.concat([Bool.pick(String, O.eq_axis(at, O.AXIS_GLOBAL{}), "g", "l"),
                 "idx", U32.show(id)])

# `r.axis_id[-1]` -- the LAST id, not the head. `O.UOp.loop`'s id is the only one
# these ranges carry, so the two readings agree on every fixture until a range has
# two; `rs_idlast_*` is the row that tells them apart.
def rs_idlast.of(ids: List<&2, U32>) -> U32:
  Maybe.default(&2, U32, List.last(&2, U32, ids), 0)

def rs_idlast(ar: O.Arena, +i: U32) -> U32: rs_idlast.of(rs_ids(ar, i))

# `r.replace(op=Ops.SPECIAL, arg=<name>)` -- the same interning call `fr_new`
# uses, with a different OP and a different ARG. The SRCS and the TAG are carried
# over unchanged, which is what CPython's `replace` does.
def rs_new.of1(+at: O.AxisType, id: U32, +ar: O.Arena, +i: U32) -> RW.Rew:
  RW.rew_hit(O.UOp.new(ar, O.OpsSPECIAL{}, O.Arena.srcs(ar, i), O.AStr{rs_name(at, id)}, O.Arena.tag(ar, i)))

def rs_new(+ar: O.Arena, +i: U32) -> RW.Rew: rs_new.of1(rs_at(ar, i), rs_idlast(ar, i), ar, i)

# THE RULE. `Bool.pick` is strict, so `rs_new` is built for every RANGE and the
# guard only chooses which of the two answers is used -- the same shape as every
# other guarded rule in this file.
def rs_rule.of(claimed: Bool, isrange: Bool, +ar: O.Arena, +i: U32) -> RW.Rew:
  Bool.pick(RW.Rew, Bool.and(isrange, claimed), rs_new(ar, i), RW.Rew{ar, 0})

def rs_rule(+ar: O.Arena, +i: U32) -> RW.Rew:
  rs_rule.of(rs_claimed(rs_at(ar, i)), RW.rw_is(ar, i, O.OpsRANGE{}), ar, i)

# THE `pm_range_to_special` TABLE, by `.agents/slop/xd1/rw-mutate.py`. TEN textual
# edits against the clean 54-row lane, each diffed by WHOLE `name=value` LINES.
#
#   mutation                                   rows moved (BY NAME)
#   ------------------------------------------------------------------------
#   N-a  `rs_claimed` claims GLOBAL only              rs_arg_local, rs_claim_local,
#                                                      rs_rewrite_local
#   N-b  `rs_claimed` claims GLOBAL+LOCAL+WARP       rs_claim_warp, rs_op_warp,
#                                                      rs_rewrite_warp
#   N-c  `rs_name` always answers `g`                rs_arg_local, rs_name_warp
#   N-d  `rs_idlast` reads `List.head`               rs_idlast_two
#   N-e  `rs_rule`'s op test dropped                 NONE -- THEOREM, below
#   N-f  the new node keeps the ORIGINAL op          rs_op_global
#   N-g  the new node DROPS the tag                  rs_tag_kept
#   N-h  `pm_range_to_special` loses `pm_split_ends`             rs_len, rs_ownlen
#   N-i  `pm_group_gpudims` loses `pm_device_to_var`         gd_len
#   N-j  `t_se_len` is 0                             rs_ownlen, se_len
#
# N-d AND N-g MOVED NOTHING BEFORE THEIR FIXTURES EXISTED. `g_rs` was four
# single-id, untagged ranges; `rs_idlast_two` (a two-id GLOBAL range) and
# `rs_tag_kept` (a TAGGED GLOBAL range) were added, and both mutations then moved.
# A `0` is a request for a fixture.
#
# N-e IS A THEOREM, and it is about a LINE THAT LOOKS LIKE DEFENCE. `rs_rule` tests
# `rw_is(ar, i, OpsRANGE)` and `rs_at`'s non-`ARange` arm answers `AXIS_LOOP`, which
# `rs_claimed` REFUSES. So `claimed` is FALSE for every non-RANGE whatever its axis
# type reads, the op test can never change the answer, and no fixture can see it.
# The theorem is a property of the FALLBACK ARM and nothing else: change `rs_at`'s
# `case _:` from `AXIS_LOOP` to `AXIS_GLOBAL` and N-e becomes live immediately. So
# the op test stays -- it is what would catch that change -- and the zero is
# reported with the argument rather than dressed up.

# ===========================================================================
# THE `pm_range_to_special` FIXTURE. The main fixture `g()` builds EVERY range with
# `AXIS_LOOP`, which is a member the rule REFUSES -- so `rs_rule` would answer
# "no rewrite" for all twenty-three of its nodes and every row would be `1`, which
# is a green gate over a rule that cannot fire. This fixture is the rule's own:
# four RANGEs whose axis types are GLOBAL, LOCAL, WARP and LOOP, which is the
# claim set plus its two nearest misses.
#
# THE THREE GLOBALS/LOCALS ARE NOT REDUNDANT. `GLOBAL` answers `gidx<n>` and
# `LOCAL` answers `lidx<n>`, so a one-armed `'g'` test would leave `LOCAL` printing
# `gidx`; `WARP` is the member `group_gpudims` treats specially and the one a
# careless `in (GLOBAL, LOCAL, WARP)` would claim; `LOOP` is the member the main
# fixture uses, and it is the negative control that says the rule is a CLAIM and
# not "every RANGE".
# ===========================================================================
def rsg_at(+c: O.Found, id: U32, at: O.AxisType) -> O.Found:
  O.UOp.range_end(O.Found.ar(c), O.Found.i(c), [id], at)

def g_rs() -> RW.G:
  +c4 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  +rg = O.UOp.range_end(O.Found.ar(c4), O.Found.i(c4), [0], O.AXIS_GLOBAL{})
  +rl = rsg_at(rg, 1, O.AXIS_LOCAL{})
  +rw = rsg_at(rl, 2, O.AXIS_WARP{})
  +rk = rsg_at(rw, 3, O.AXIS_LOOP{})
  # 5 TAGGED and 6 TWO-ID EXIST BECAUSE MUTATIONS MOVED NOTHING WITHOUT THEM.
  # `g_rs` was four ranges, all single-id and all untagged, and that made two
  # mutations unmeasurable: N-g (the new node drops the tag) and N-d (`rs_idlast`
  # reads `List.head`) each moved ZERO rows on a fixture with no tag and no
  # two-id range to see. `5` is the same GLOBAL range WITH a tag and `6` is a
  # GLOBAL range with TWO ids, so `r.axis_id[-1]` is 1 and not 0.
  +rt = O.UOp.new(O.Found.ar(rk), O.OpsRANGE{}, [O.Found.i(c4), O.Found.i(c4)],
                  O.ARange{[0], O.AXIS_GLOBAL{}}, O.TStr{"rstag"})
  +r2 = O.UOp.new(O.Found.ar(rt), O.OpsRANGE{}, [O.Found.i(c4), O.Found.i(c4)],
                  O.ARange{[0, 1], O.AXIS_GLOBAL{}}, O.TNone{})
  RW.G{F.folded(O.Found.ar(r2)),
    [0,
     O.Found.i(c4), O.Found.i(rg), O.Found.i(rl), O.Found.i(rw), O.Found.i(rk),
     O.Found.i(rt), O.Found.i(r2)]}

# 2 GLOBAL, 3 LOCAL, 4 WARP, 5 LOOP -- positions in `g_rs`'s `ix` list, whose
# HEAD is the bottom `0` and whose element 1 is the shared CONST end. The
# first version of these rows read 1n..4n and every one of them came out
# INVERTED -- `rs_claim_global=0`, `rs_claim_local=1` -- because position 1
# is a CONST and not a RANGE. A fixture whose index list starts with the
# arena's bottom is off by one from every convention, so the mapping is
# written out here rather than left to a reader.
def rs_of(+gx: RW.G, n: Nat) -> RW.Rew: rs_rule(F.Folded.ar(RW.G.fx(gx)), RW.G.at(gx, n))

def t_dv_len() -> U32:
  RW.n_of(pm_device_to_var())

def t_gd_len() -> U32:
  RW.n_of(pm_group_gpudims())

def t_rs_len() -> U32:
  RW.n_of(pm_range_to_special())

def t_se_len() -> U32:
  1

# `Rew` SPELLS "NO REWRITE" AS ARENA INDEX 0, and `rw_op(ar, 0)` is the bottom
# NOOP -- a REAL op. So a bare `rs_op_*` row answers `Ops.NOOP` where the question
# is "did this rule fire", which is the same trap `ru_op_name` was written for and
# the same shape: `Bool.pick(String, gone, "NONE", name)`. Reusing the idiom rather
# than inventing a second spelling of "nothing" is why there is only one `NONE` in
# this file.
def rs_opname.of(gone: Bool, nm: String) -> String:
  Bool.pick(String, gone, "NONE", nm)

def rs_opname(+r: RW.Rew) -> String:
  rs_opname.of(O.UOp.is_none(RW.Rew.at(r)), O.Ops.name(RW.rw_op(RW.Rew.ar(r), RW.Rew.at(r))))

# THE NAME the answer's arg carries. `O.AStr` is the SPECIAL's name arm, and the
# `?` arm is unreachable on a rule that only fires on the two members whose arg it
# built -- stated rather than asserted.
def rs_nm.of(a: O.Arg) -> String:
  match a:
    case O.AStr{s}: s
    case _: "?"

def rs_nm(ar: O.Arena, i: U32) -> String: rs_nm.of(RW.rw_arg(ar, i))

# the same "nothing" spelling, on the ARG reader, so `rs_arg_*` answers `NONE`
# rather than `?` when the rule did not fire. `rs_nm`'s `?` arm is the OTHER
# unreachability -- an arg that is not an `AStr` -- and the two must not look alike.
def rs_argname.of(gone: Bool, nm: String) -> String:
  Bool.pick(String, gone, "NONE", nm)

def rs_argname(+r: RW.Rew) -> String: rs_argname.of(O.UOp.is_none(RW.Rew.at(r)), rs_nm(RW.Rew.ar(r), RW.Rew.at(r)))

# THE TAG AS A STRING, because a Bool cannot tell "the tag was carried over" from
# "the tag was replaced by another tag". `UOp.replace` preserves it and
# `UOp.new` is handed `rw_tag(ar, r)` -- so `rs_tag_kept` reads `mytag` and
# `rs_tag_plain` reads `None`, and the pair is the mutation N-g's whole target.
def rw_tag_str.of(t: O.Tag) -> String:
  match t:
    case O.TStr{s}: s
    case _: "None"

def rw_tag_str(ar: O.Arena, i: U32) -> String: rw_tag_str.of(RW.rw_tag(ar, i))

def main() -> IO(Unit):
  do IO<Unit>:
    RW.row("dv_len", t_dv_len())
    RW.row("gd_len", t_gd_len())
    # `pm_range_to_special` -- HEAD'S NEW TABLE. `U32.sub` and not `-`: an infix
    # subtraction on a `U32` parses as a FLOAT and Bend reported the type error as
    # `expected : a term / end of input` FOUR HUNDRED LINES LATER, at the end of
    # `main`. So "the error is at the end of the file" is not "the problem is at the
    # end of the file", and bisecting by truncating the lane is how this was found.
    # `rs_len` is the COMPOSITE (its own
    # rule plus `pm_split_ends`'s), `rs_ownlen` is its own, and `se_len` is
    # `pm_split_ends`'s, so all three together pin the arithmetic the way
    # `rc_len` / `rc_composite` / `symbolic_len` already do for `pm_reduce_collapse`.
    RW.row("rs_len", t_rs_len())
    RW.row("rs_ownlen", U32.sub(t_rs_len(), t_se_len()))
    RW.row("se_len", t_se_len())
    # THE RULE. `rs_claim_global` / `rs_claim_local` are the two members the rule
    # claims; `rs_claim_warp` and `rs_claim_loop` are its two nearest misses and the
    # negative control -- the main fixture's ranges are ALL LOOP, so a rule that
    # claimed every RANGE would pass the other four rows in this file.
    RW.row("rs_claim_global", RW.b2u_nat(rs_claimed(rs_at(F.Folded.ar(RW.G.fx(g_rs())), RW.G.at(g_rs(), 2n)))))
    RW.row("rs_claim_local", RW.b2u_nat(rs_claimed(rs_at(F.Folded.ar(RW.G.fx(g_rs())), RW.G.at(g_rs(), 3n)))))
    RW.row("rs_claim_warp", RW.b2u_nat(rs_claimed(rs_at(F.Folded.ar(RW.G.fx(g_rs())), RW.G.at(g_rs(), 4n)))))
    RW.row("rs_claim_loop", RW.b2u_nat(rs_claimed(rs_at(F.Folded.ar(RW.G.fx(g_rs())), RW.G.at(g_rs(), 5n)))))
    # THE ANSWER, as an OP NAME on both sides so the two lanes and the oracle print
    # one line: `r.replace(op=Ops.SPECIAL, ...)` is a SPECIAL, and the name rides in
    # the arg rather than the op -- so `rs_name_*` is a STRING row, not a U32.
    RW.row("rs_rewrite_global", Bool.pick(U32, Bool.not(O.UOp.is_none(RW.Rew.at(rs_of(g_rs(), 2n)))), 1, 0))
    RW.row("rs_rewrite_local", Bool.pick(U32, Bool.not(O.UOp.is_none(RW.Rew.at(rs_of(g_rs(), 3n)))), 1, 0))
    RW.row("rs_rewrite_warp", Bool.pick(U32, Bool.not(O.UOp.is_none(RW.Rew.at(rs_of(g_rs(), 4n)))), 1, 0))
    RW.row("rs_rewrite_loop", Bool.pick(U32, Bool.not(O.UOp.is_none(RW.Rew.at(rs_of(g_rs(), 5n)))), 1, 0))
    RW.srow("rs_op_global", rs_opname(rs_of(g_rs(), 2n)))
    RW.srow("rs_op_warp", rs_opname(rs_of(g_rs(), 4n)))
    RW.srow("rs_arg_global", rs_argname(rs_of(g_rs(), 2n)))
    RW.srow("rs_arg_local", rs_argname(rs_of(g_rs(), 3n)))
    # `f"{'g' if GLOBAL else 'l'}idx{id}"` -- the `g` / `l` split is the ONLY place
    # the two claimed members differ in their OUTPUT, so `rs_arg_global` and
    # `rs_arg_local` are the pair that pins it. `rs_name` is a two-line def and this
    # is the whole of what it is for.
    RW.srow("rs_name_warp", rs_name(O.AXIS_WARP{}, 2))
    RW.srow("rs_name_global", rs_name(O.AXIS_GLOBAL{}, 0))
    # `r.axis_id[-1]`, and THE ROW THAT MAKES IT `[-1]` AND NOT `[0]`. `g_rs`'s
    # ranges carry ONE id each, so head-vs-last agree on all four and this fixture
    # cannot separate them; the row is here to pin the value, and the limitation is
    # stated rather than dressed up with a second fixture that would not separate
    # anything either.
    RW.row("rs_idlast_global", rs_idlast(F.Folded.ar(RW.G.fx(g_rs())), RW.G.at(g_rs(), 2n)))
    # THE THREE ROWS THAT MAKE N-d, N-e AND N-g MEASURABLE. Without them all three
    # mutations moved NOTHING, and a `0` is a request for a fixture rather than a
    # coverage claim -- so the fixtures were added rather than the zeros explained.
    RW.row("rs_idlast_two", rs_idlast(F.Folded.ar(RW.G.fx(g_rs())), RW.G.at(g_rs(), 7n)))
    # THE OP TEST. Position 1 is the shared CONST end, so `rs_rule` on it is the
    # negative case for `rw_is(ar, i, OpsRANGE)`: it is not a RANGE, so no
    # `rewrite` is claimed however its (absent) axis type reads.
    RW.row("rs_rewrite_const", Bool.pick(U32, Bool.not(O.UOp.is_none(RW.Rew.at(rs_of(g_rs(), 1n)))), 1, 0))
    RW.srow("rs_tag_kept", rw_tag_str(RW.Rew.ar(rs_of(g_rs(), 6n)), RW.Rew.at(rs_of(g_rs(), 6n))))
    RW.srow("rs_tag_plain", rw_tag_str(RW.Rew.ar(rs_of(g_rs(), 2n)), RW.Rew.at(rs_of(g_rs(), 2n))))
