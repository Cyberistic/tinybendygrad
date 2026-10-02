# multi.bend -- tinygrad/schedule/multi.py. Multi-device scheduling: the
# UNSHARD-splitting rules, the device-group COPY rules, and the MSELECT/MSTACK
# rewrites that pull a multi op apart into per-device work.
#
# WHAT THIS FILE IS. `multi.py` is 311 lines and THIRTY defs, and almost none of
# it is arithmetic. Two thirds of the defs are GRAPH BUILDERS -- `.unshard`,
# `.alu`, `.mselect`, `.copy_to_device`, `._shard`, `.cat`, `.store`, `.replace`,
# `UOp(Ops.STACK, ...)` -- and not one of those builders is ported (ops.py:614
# through :853, every one a `TODO(p3)` in `ops.bend`). What IS here is the
# DECISION and the INDEX ARITHMETIC each of those thirty defs makes before it
# reaches for a builder, and that is the whole algorithm:
#
#   * which sharded axes a REDUCE consumes (`reduce_multi`),
#   * where a RESHAPE's shard boundary lands (`reshape_multi`),
#   * which axis a PERMUTE sends a shard to, and which it FLIPs
#     (`permute_multi`, `flip_multi`),
#   * whether a shrink resolves its own UNSHARD, keeps it, or takes the legacy
#     single-partition path (`shrink_multi`),
#   * whether an INDEX is contiguously or strided owned (`index_multi`),
#   * and the three-way per-source decision in `shard_srcs`, which is the
#     function the resharding fallbacks all call.
#
# THE ONE WALL THAT CUTS ACROSS EVERY LINE: `UOp._min_max` (ops.py:1104), which
# `int(rng.vmax)+1` needs in `shard_srcs`, `shrink_multi`, `reshape_multi` and
# `copy_multi`. `fold.bend` lists it as `TODO(p3) ops.py:1104` and it is not a
# fold at all -- it is arithmetic over the srcs. What `mu_count` ports is the
# NARROW case that is exact and load-bearing: a RANGE over a CONST end, where
# ops.py:1135 reads `(self.src[0]-1).vmax` and so `int(rng.vmax)+1 == src[0]`.
# That is the DEVICE range `UOp.range(len(devices[0]), -1, AxisType.DEVICE)`
# that every `unshard` builds, and it is the whole of the shard count a real
# multi graph ever has. A RANGE over a SYMBOLIC end answers `mu_sym_count()`,
# the named wall, and every caller that must not silently get it says so.
#
# ---------------------------------------------------------------------------
# DEPENDENCY ON SIBLINGS, both named here because both are call sites this file
# does not make.
#
# * `schedule/allreduce.bend` -- `replace_allreduce`'s `_early_allreduce` arm
#   (multi.py:48) is `(UPat(Ops.ALLREDUCE, src=(UPat.var("buf"),), name="red"),
#   handle_allreduce)`, and `handle_allreduce` is that file's whole subject.
#   The BODY of that one rule is `allreduce.bend`'s, not this file's, and the
#   rule here dispatches to `mu_ea_0` which says so. `reduce_multi`'s
#   ALLREDUCE_CAST arm (multi.py:116-118) builds
#   `local.cast(orig).allreduce(op, dev).cast(local.dtype)` and the two
#   `.cast`s and the `.allreduce` are the same wall.
# * `schedule/__init__.bend` -- the planner runs `multi_pm` and owns the
#   `MULTI` flag that selects it. See WHAT THE OTHER FILES NEED at the foot.
# ---------------------------------------------------------------------------
# THE FLAGS ARE PARAMETERS, and that is the one convention shared with
# `allreduce.bend`. `LATE_ALLREDUCE` (multi.py:50) and `ALLREDUCE_CAST`
# (multi.py:116) are `ContextVar`s and Bend has no `Config` and no process
# environment, so they are fields of a `Cfg` record threaded to the two rules
# that read one. `MULTI` is not read anywhere in this checkout's `multi.py` --
# it is `__init__.py`'s -- so it is named in the foot and not a field here.
# `RING`, `ALL2ALL` and `RING_ALLREDUCE_THRESHOLD` are `allreduce.bend`'s.
#
# ---------------------------------------------------------------------------
# THE THREE TABLES, and there are three because Python has three objects.
# `PatternMatcher.__add__` (ops.py:1603) is `self.patterns+more.patterns`, so
# `multi_pm` is NINETEEN own rules with `replace_allreduce`'s SIX APPENDED, and
# `replace_allreduce` is `_early_allreduce`'s ONE prepended when
# `LATE_ALLREDUCE` is off. That composition is not cosmetic: it moves every tag
# after the prefix, so `mu_table` CONCATENATES rather than counts, and
# `mt_own_n`, `mt_ra_n`, `mt_ea_n`, `mt_pm_n` and `mt_late_n` are rows that pin
# the result. `ops.bend` cannot call a def in this file and a rule table must be
# a top-level `Data` value because there are no closures, so this file has its
# own dispatch/try/scan -- the same duplication `uop/spec.bend` does six times
# and `schedule/rangeify.bend` eleven times. There is no generic dispatch here
# and this file does not try to build one.
#
# `PMEntry.rej` is `early_reject` and it is a NECESSARY CONDITION despite the
# name (ops.py:1609 is `if not early_reject.issubset(ler): continue`): the rule
# FIRES when its op set IS a subset of the node's src ops, and the empty set is
# a subset of everything. `mt_rej_sum` in the gate is the row for the whole
# inventory, and the per-node claim counts below are what say the sets are right.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F

# ===========================================================================
# THE RECORDS.
#
# `Cfg` is the two flags, as parameters (see the header). `late` is a `Bool`
# because Python reads it as `not getenv(...)`, and the composition at :50 is
# the only thing that consults it.
# ===========================================================================
type Cfg is Data:
  Cfg{late: Bool, cast: Bool}

def Cfg.late(c: Cfg) -> Bool:
  match c:
    case Cfg{late, cast}: late

def Cfg.cast(c: Cfg) -> Bool:
  match c:
    case Cfg{late, cast}: cast

# `Sh` is ONE `(axis, RANGE)` pair of `multi.sharding` (ops.py:707), with the
# RANGE replaced by its SHARD COUNT `int(rng.vmax)+1`. The count is what every
# reader of a sharding in multi.py actually wants -- `shard_srcs`'s
# `range(len(devices[0]), -1, DEVICE)`, `shrink_multi`'s
# `range(int(rng.vmax)+1)`, `reshape_multi`'s `count`, `copy_multi`'s
# `part_bounds` -- and it is the half of the pair that `_min_max` produces.
# The other half, the RANGE node itself, is threaded as `shard_srcs`'s
# `sharding_rng` and is the one thing this file cannot rebuild, so it is a
# PARAMETER of the defs that pass it on rather than a value.
type Sh is Data:
  Sh{ax: U32, n: U32}

def Sh.ax(s: Sh) -> U32:
  match s:
    case Sh{ax, n}: ax

def Sh.n(s: Sh) -> U32:
  match s:
    case Sh{ax, n}: n

# `Nd` is the slice of a source that `multi.py` reads and no more: its OP, its
# `axis` (with `has_ax` for Python's `None`, because `Bool` cannot carry one
# and an U32 sentinel would collide with axis 0 -- and axis 0 IS a real sharded
# axis, see `rs_head`), whether it is a SCALAR, and its `sharding`.
# It is a record rather than six parameters because `shard_subview`,
# `alu_multi` and `shard_srcs` each read three of the six on one source.
type Nd is Data:
  Nd{op: O.Op, ax: U32, has_ax: Bool, sc: Bool, sh: List<&2, Sh>}

def Nd.op(n: Nd) -> O.Op:
  match n:
    case Nd{op, ax, has_ax, sc, sh}: op

def Nd.ax(n: Nd) -> U32:
  match n:
    case Nd{op, ax, has_ax, sc, sh}: ax

def Nd.has_ax(n: Nd) -> Bool:
  match n:
    case Nd{op, ax, has_ax, sc, sh}: has_ax

def Nd.sc(n: Nd) -> Bool:
  match n:
    case Nd{op, ax, has_ax, sc, sh}: sc

def Nd.sh(n: Nd) -> List<&2, Sh>:
  match n:
    case Nd{op, ax, has_ax, sc, sh}: sh

# `Cfg` values, named because the gate builds several and the row set below is
# what says `LATE_ALLREDUCE` changes the TABLE and not just the behaviour.
def mu_c_late() -> Cfg: Cfg{False{}, True{}}
def mu_c_early() -> Cfg: Cfg{True{}, True{}}
def mu_c_nocast() -> Cfg: Cfg{True{}, False{}}

# ===========================================================================
# THE SHARD COUNT -- `int(rng.vmax)+1`, and `UOp._min_max` (ops.py:1104) is the
# wall. The RANGE arm is ops.py:1135:
#
#     if self.op in (Ops.RANGE, Ops.SPECIAL) and self.dtype is not dtypes.void:
#       return 0, (self.src[0]-1).vmax
#
# so for a RANGE whose end is a CONST the count IS that constant, and the CONST
# arm is ops.py:1144 (`return self.val, self.val`). Those two arms compose to
# `src[0].val`, and they are what `UOp.range(len(devices[0]), -1, DEVICE)`
# always is: `len(devices[0])` is a Python int. That is why this is ported and
# not left as a wall.
#
# `mu_sym_count` is the honest spelling of the rest: a RANGE over a SYMBOLIC end
# is the LOCAL-thread-range case `shard_srcs`'s comment names, and the count is
# `int(rng.vmax)+1` on an interval the port cannot bound. 0 is the wall's
# marker and every row that must not silently get it passes `mu_sym_count()` to
# the rule, which turns the rule into "no answer" -- the same move
# `rangeify.bend`'s `rf_ranges_miss` makes for `UOp.ranges`.
# ===========================================================================
def mu_sym_count() -> U32: 0

# `a CONST uop's val` -- ops.py:1144. `O.APy` is Python's `arg.val`, and
# `CInt` is a concrete int; a `CPy` would be a symbolic marker and is the wall.
def mu_const_int.go(a: O.Arg) -> U32:
  match a:
    case O.APy{O.CInt{i}}: H.lo32(i)
    case _: mu_sym_count()

def mu_const_int(ar: O.Arena, +self: U32) -> U32:
  mu_const_int.go(O.Arena.arg(ar, self))

# `int(rng.vmax)+1` -- the two ops.py arms composed, and 0 (the wall) for
# anything that is not a RANGE over a CONST end. `is_range` is the RANGE test
# of :1135 and the `dst[0]` is the `(self.src[0]-1)` of the same line.
def mu_count.is(ok: Bool, v: U32) -> U32:
  match ok:
    case True{}: v
    case False{}: mu_sym_count()

def mu_count(+ar: O.Arena, +rng: U32) -> U32:
  mu_count.is(Bool.and(O.op_is(ar, rng, O.OpsRANGE{}), Bool.not(U32.is_zero(O.Arena.nsrc(ar, rng)))),
              mu_const_int(ar, O.Arena.src0(ar, rng)))

# ===========================================================================
# THE SHARDING -- `UOp.sharding` (ops.py:707), which is two lines:
#
#     return tuple(zip(self.arg, self.src[1:])) if self.op is Ops.UNSHARD else ()
#
# The axes are `arg`, an `ATuple` of them (ops.py:748, `tuple[int, ...]`), and
# the ranges are `src[1:]`, so the pairing is a zip of a node's own arg against
# a node's own srcs. `mu_shard.zip` is that zip with the range turned into its
# count by `mu_count`.
# ===========================================================================# the axes, `self.arg` -- ops.py:748 spells an UNSHARD's arg `tuple[int, ...]`,
# which `ops.bend` has already split into `ATuple{ys}`.
def mu_axes.go(a: O.Arg) -> List<&2, U32>:
  match a:
    case O.ATuple{ys}: ys
    case _: Nil{}

def mu_axes(ar: O.Arena, +self: U32) -> List<&2, U32>:
  mu_axes.go(O.Arena.arg(ar, self))

# the counts, one per `src[1:]`, so the zip below is POSITIONAL and never a
# search. `zip` truncates to the shorter side in Python and so does this: a
# missing count ends the list.
def mu_counts.acc(+ar: O.Arena, rs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match rs:
    case Nil{}: acc
    case r <> t: mu_counts.acc(ar, t, List.append(&2, U32, acc, [mu_count(ar, r)]))

def mu_counts(+ar: O.Arena, +self: U32) -> List<&2, U32>:
  mu_counts.acc(ar, O.Arena.src_from(ar, self, 1), Nil{})

def mu_shard.go(axs: List<&2, U32>, ns: List<&2, U32>, acc: List<&2, Sh>) -> List<&2, Sh>:
  match axs ns:
    case a <> at n <> nt: mu_shard.go(at, nt, List.append(&2, Sh, acc, [Sh{a, n}]))
    case _ _: acc

# `if self.op is Ops.UNSHARD else ()` -- the outer guard of ops.py:707, and it is
# a GUARD and not a filter: a non-UNSHARD has an EMPTY sharding, and that is
# what makes every `if m.sharding:` in multi.py a UNSHARD test.
def mu_shard.zip.go(unsh: Bool, +ar: O.Arena, +self: U32) -> List<&2, Sh>:
  match unsh:
    case True{}: mu_shard.go(mu_axes(ar, self), mu_counts(ar, self), Nil{})
    case False{}: Nil{}

def mu_shard.zip(+ar: O.Arena, +self: U32) -> List<&2, Sh>:
  mu_shard.zip.go(O.op_is(ar, self, O.OpsUNSHARD{}), ar, self)

# THE SHARDING LENGTH, and it is a COUNT the gate pins rather than a Bool.
# `len(multi.sharding)` decides `shrink_multi`'s legacy branch
# (`len(multi.sharding) != 1`, multi.py:176), so a sharding that lost an axis
# would take the legacy path on a two-axis shard.
def mu_nshard(sh: List<&2, Sh>) -> Nat:
  List.length(&2, Sh, sh)

# `arg[0]` of a U32 list. 0 is this file's spelling of Python's IndexError, the
# same spelling `allreduce.bend`'s `red_head` uses.
def mu_head32(m: Maybe<&2, U32>) -> U32:
  Maybe.default(&2, U32, m, 0)

# `UOp.axis` (ops.py:717-726) on the two ops multi.py reads it on:
#
#     if self.op is Ops.COPY: return None
#     if self.op is Ops.UNSHARD:
#       if len(self.arg) != 1: raise RuntimeError(...)
#       return self.arg[0]
#     if self.op is Ops.PARAM: return None
#
# So a UNSHARD has an axis ONLY when it is sharded on exactly one, and the
# two-axis case RAISES. `mu_axis` answers "no axis" there rather than picking
# one: `shard_srcs` asks `mlb.axis == src_axis` (multi.py:69) and a port that
# answered 0 would silently copy through on a two-axis shard.
def mu_axis.go(ok: Bool, v: U32) -> Maybe<&2, U32>:
  match ok:
    case True{}: Some{v}
    case False{}: None{}

def mu_axis(+ar: O.Arena, +self: U32) -> Maybe<&2, U32>:
  mu_axis.go(Bool.and(O.op_is(ar, self, O.OpsUNSHARD{}),
                      U32.is_eq(U32.from_nat(mu_nshard(mu_shard.zip(ar, self))), 1)),
             mu_head32(List.head(&2, U32, mu_axes(ar, self))))

def mu_axis_is(a: Maybe<&2, U32>, w: U32) -> Bool:
  match a:
    case Some{v}: U32.is_eq(v, w)
    case _: False{}

def mu_has_axis(a: Maybe<&2, U32>) -> Bool:
  match a:
    case Some{v}: True{}
    case _: False{}

# ===========================================================================
# THE TABLES. `PatternMatcher.__add__` (ops.py:1603) is
# `self.patterns+more.patterns`, so the composition is a LIST CONCATENATION and
# the tag of a rule is its INDEX. That is why `mu_own` and `mu_ra` are separate
# tables concatenated rather than one table with holes, and why
# `mu_ra.of` renumbers: prepending `_early_allreduce` shifts all six
# `replace_allreduce` tags by one.
# ===========================================================================
# `GroupOp.ALU` -- ops.py's twenty-eight members, in ops.bend's DECLARATION order
# (which is `Ops.value` order, which is what the Python print above sorts to).
# This is `alu_multi`'s pdict key and it is the largest op set in the file, and
# it is the one rule in `multi_pm` whose pattern carries NO src test at all --
# `custom_early_reject=set([Ops.UNSHARD])` is its whole shape. `mt_alu_n` is 28.
def mu_alu_ops() -> List<&2, O.Op>:
  [O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIPROCAL{}, O.OpsNEG{}, O.OpsTRUNC{},
   O.OpsADD{}, O.OpsMUL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsCDIV{}, O.OpsMAX{}, O.OpsCMOD{}, O.OpsCMPLT{},
   O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsOR{}, O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{},
   O.OpsFDIV{}, O.OpsPOW{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsWHERE{}, O.OpsMULACC{}]

# `GroupOp.Movement` -- six members, and it is `ra_4`'s pdict key
# (`UPat(GroupOp.Movement, src=(UPat.var("s"),), name="v")`, multi.py:41).
def mu_move_ops() -> List<&2, O.Op>:
  [O.OpsSHRINK{}, O.OpsRESHAPE{}, O.OpsPERMUTE{}, O.OpsEXPAND{}, O.OpsPAD{}, O.OpsFLIP{}]

# the FIVE of multi.py:305 -- `(Ops.CAST, Ops.BITCAST, Ops.STAGE, Ops.DETACH,
# Ops.CONTIGUOUS_BACKWARD)`, all of `passthrough_multi`. It is written out rather
# than built from `mu_move_ops` because it is not a GroupOp and shares only
# RESHAPE-adjacency with one.
def mu_pass_ops() -> List<&2, O.Op>:
  [O.OpsCAST{}, O.OpsBITCAST{}, O.OpsSTAGE{}, O.OpsDETACH{}, O.OpsCONTIGUOUS_BACKWARD{}]

# `_early_allreduce` (multi.py:48) -- ONE rule, and its body is
# `allreduce.bend`'s `handle_allreduce`.
def mu_ea_ops() -> List<&2, O.Op>: [O.OpsALLREDUCE{}]

# THE REJECT SETS, named so a MISSPELLING is a visible one-word change.
def mu_rej_uns() -> List<&2, O.Op>: [O.OpsUNSHARD{}]
def mu_rej_ms() -> List<&2, O.Op>: [O.OpsMSTACK{}]
def mu_rej_su() -> List<&2, O.Op>: [O.OpsSTORE{}, O.OpsUNSHARD{}]
def mu_rej_nil() -> List<&2, O.Op>: Nil{}

# ---------------------------------------------------------------------------
# `multi_pm` (multi.py:281-311), NINETEEN own rules, tags 0..18. The line comment
# on each is Python's own.
# ---------------------------------------------------------------------------
def mu_own() -> List<&2, O.PMEntry>:
  [O.PMEntry{0,  mu_alu_ops(),                       mu_rej_uns()},  # 282  ALU -> alu_multi
   O.PMEntry{1,  [O.OpsREDUCE{}],                     mu_rej_uns()},  # 283  REDUCE(UNSHARD)
   O.PMEntry{2,  [O.OpsRESHAPE{}],                    mu_rej_uns()},  # 284
   O.PMEntry{3,  [O.OpsEXPAND{}],                     mu_rej_uns()},  # 285
   O.PMEntry{4,  [O.OpsPAD{}],                        mu_rej_uns()},  # 286
   O.PMEntry{5,  [O.OpsSHRINK{}],                     mu_rej_uns()},  # 287
   O.PMEntry{6,  [O.OpsPERMUTE{}],                    mu_rej_uns()},  # 288
   O.PMEntry{7,  [O.OpsFLIP{}],                       mu_rej_uns()},  # 289
   O.PMEntry{8,  [O.OpsSTACK{}],                      mu_rej_uns()},  # 290
   O.PMEntry{9,  [O.OpsINDEX{}],                      mu_rej_uns()},  # 291
   O.PMEntry{10, [O.OpsAFTER{}],                      mu_rej_su()},   # 292  AFTER(STORE(UNSHARD,UNSHARD))
   O.PMEntry{11, [O.OpsCOPY{}],                       mu_rej_uns()},  # 294  COPY of a sharded value
   O.PMEntry{12, [O.OpsALLREDUCE{}],                  mu_rej_uns()},  # 295
   O.PMEntry{13, [O.OpsCALL{}],                       mu_rej_nil()},  # 300  CALL -> rewrite_into_function
   O.PMEntry{14, [O.OpsAFTER{}, O.OpsCALL{}],         mu_rej_uns()},  # 301  passthrough_multi
   O.PMEntry{15, [O.OpsCALL{}],                       mu_rej_uns()},  # 303  a void CALL: strip UNSHARD
   O.PMEntry{16, mu_pass_ops(),                       mu_rej_uns()},  # 305  passthrough_multi
   O.PMEntry{17, [O.OpsSTORE{}],                      mu_rej_uns()},  # 308  STORE into a WHOLE dest
   O.PMEntry{18, [O.OpsSTORE{}],                      mu_rej_uns()}]  # 310  STORE into a SHARDED dest

# ---------------------------------------------------------------------------
# `replace_allreduce` (multi.py:29-45), SIX rules. Its tags in `multi_pm` are
# 19..24, and 19..25 when `LATE_ALLREDUCE` is off.
# ---------------------------------------------------------------------------
def mu_ra0() -> O.PMEntry: O.PMEntry{0, [O.OpsCOPY{}],    mu_rej_nil()}   # 31  BROADCAST copy -> MSTACK
def mu_ra1() -> O.PMEntry: O.PMEntry{1, [O.OpsCOPY{}],    mu_rej_nil()}   # 33  multidev -> one: MSELECT 0
def mu_ra2() -> O.PMEntry: O.PMEntry{2, [O.OpsMSELECT{}], mu_rej_ms()}    # 37  MSELECT(MSTACK) -> the piece
def mu_ra3() -> O.PMEntry: O.PMEntry{3, [O.OpsSHRINK{}],  mu_rej_ms()}    # 39  SHRINK(MSTACK) -> move it in
def mu_ra4() -> O.PMEntry: O.PMEntry{4, [O.OpsMSELECT{}], mu_rej_nil()}    # 41  MSELECT before a Movement
def mu_ra5() -> O.PMEntry: O.PMEntry{5, [O.OpsMSELECT{}], mu_rej_nil()}    # 43  MSELECT before an ALU

def mu_ra_base() -> List<&2, O.PMEntry>: [mu_ra0(), mu_ra1(), mu_ra2(), mu_ra3(), mu_ra4(), mu_ra5()]

# `_early_allreduce` (multi.py:47-49) -- ONE rule, tag 0 IN ITS OWN TABLE.
def mu_ea0() -> O.PMEntry: O.PMEntry{0, mu_ea_ops(), mu_rej_nil()}

# THE SHIFT. `_early_allreduce + replace_allreduce` (multi.py:50) puts the
# ALLREDUCE rule FIRST, so the six COPY/MSELECT/SHRINK rules move from 19..24 to
# 20..25 and `multi_pm` grows from 25 to 26. `ra_sh1` and `ra_sh0` are the rows
# that say the flag renumbers the table and does not merely append a row.
def mu_ra_put(off: U32, +e: O.PMEntry) -> O.PMEntry:
  O.PMEntry{U32.add(O.PMEntry.tag(e), off), O.PMEntry.ops(e), O.PMEntry.rej(e)}

def mu_ra_shift(+off: U32, es: List<&2, O.PMEntry>, acc: List<&2, O.PMEntry>) -> List<&2, O.PMEntry>:
  match es:
    case Nil{}: acc
    case +e <> t: mu_ra_shift(off, t, List.append(&2, O.PMEntry, acc, [mu_ra_put(off, e)]))

def mu_ra_cfg.go(late: Bool, acc: List<&2, O.PMEntry>) -> List<&2, O.PMEntry>:
  match late:
    case True{} : mu_ra_shift(19, mu_ra_base(), acc)
    case False{}: mu_ra_shift(20, mu_ra_base(), List.append(&2, O.PMEntry, acc, [mu_ea0()]))

def mu_ra_cfg(cfg: Cfg) -> List<&2, O.PMEntry>: mu_ra_cfg.go(Cfg.late(cfg), Nil{})

# `multi_pm` -- the nineteen own rules THEN `replace_allreduce`, in Python's
# order. The concatenation is the ACCUMULATOR's job and not a separate `++`:
# `replace_allreduce` is itself built by appending, so `mu_ra_cfg` takes the
# accumulator it starts from and `mu_own()` IS `multi_pm`'s first half. One
# def shorter than a `List.concat` and the order is the order of the appends.
def mu_ra_cfg.of(cfg: Cfg, acc: List<&2, O.PMEntry>) -> List<&2, O.PMEntry>:
  mu_ra_cfg.go(Cfg.late(cfg), acc)

def mu_table(cfg: Cfg) -> List<&2, O.PMEntry>:
  mu_ra_cfg.of(cfg, mu_own())

# ===========================================================================
# THE SHAPES. Every decision in multi.py that reads a shape reads it as an
# INTEGER -- `prod(shape[:ax])`, `shape[ax] % count`, `len(out_shape)`,
# `len(mlb.shape)` -- so a shape here is `List<&2, U32>` and the dims are
# concrete. A SYMBOLIC dim is the wall: `ssimplify` (ops.py:520) is not ported
# and `reshape_multi`'s `arg_acc` and `prod(multi.shape[:ax])` both need it.
# `mu_sym_dim()` is the marker and it is 0, the same convention
# `LAWS/spec.bend`'s `dim_of` uses for an `SS{..}` and `allreduce.bend`'s
# `red_dim` uses for the same case.
# ===========================================================================
def mu_sym_dim() -> U32: 0

# `and`/`or`/`not` as LEAVES, and they are here for a measured reason: a `match`
# may only scrutinise a PARAMETER or a field binder, so a `match` on
# `Bool.and(a, b)` is refused (brief-port.md, rule 2) and every conjoined test in
# this file needs this form. MEASURED: `match Bool.and(x, y): case True{}: ...`
# is `a parameter or field scrutinee`, and `sk_raise.any` is the row that found
# it. Three leaves rather than one because `Bool.and` has no three-argument form.
def mu_and2(a: Bool, b: Bool) -> Bool:
  match a:
    case True{} : b
    case False{}: False{}

def mu_or2(a: Bool, b: Bool) -> Bool:
  match a:
    case True{} : True{}
    case False{}: b

def mu_and3(a: Bool, b: Bool, c: Bool) -> Bool:
  mu_and2(a, mu_and2(b, c))

def mu_or3(a: Bool, b: Bool, c: Bool) -> Bool:
  mu_or2(a, mu_or2(b, c))

# `a if cond else b` for a `U32` answer -- `Bool.pick` (base.bend:504) with the
# arguments in Python's order rather than base's. This is the ONE def that
# conjoined conditions are allowed to feed, because inside it the scrutinee is a
# PARAMETER: MEASURED, `match mu_and2(a, b):` is still refused
# (`a parameter or field scrutinee`), so a conjoined test must be an ARGUMENT to
# a `match`, never its subject. Every ladder in this file that tests more than
# one thing at a time is spelled with this.
def mu_pick(cond: Bool, a: U32, b: U32) -> U32:
  match cond:
    case True{} : a
    case False{}: b

# `shape[ax]`, and `ax` out of range is Python's IndexError. 0 is the marker,
# and `mu_sym_dim` is 0, so a symbolic dim and a missing dim are
# INDISTINGUISHABLE here -- which is the honest state of the port and is why
# every caller that could act on the difference says which it is.
def mu_at(xs: List<&2, U32>, i: Nat) -> U32:
  mu_head32(List.get(&2, U32, xs, i))

def mu_len(xs: List<&2, U32>) -> Nat:
  List.length(&2, U32, xs)

# `prod(shape[:ax])` -- `helpers.prod` over a PREFIX. `index_of` is the fold
# that reads the first `n` elements; the accumulator is the running product, so
# this is `reshape_multi`'s `target` (multi.py:133) and it is a COUNT the gate
# pins.
# The folds come BEFORE their entry points: a def may only call defs declared
# above it, and the entry point is a wrapper. That is the same
# declaration-order problem `red_factor`/`red_factor_of` and
# `noopf_go`/`rf_is_noop_after_dep` solve, and the recursion is on the list TAIL
# so no fuel is needed -- the tail IS the subterm.
def mu_prod(xs: List<&2, U32>) -> U32:
  List.foldl(~&2, ~U32, ~U32, (acc: U32) => (x: U32) => U32.mul(acc, x), xs, 1)

def mu_take.go(n: Nat, xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n xs:
    case 0n _      : acc
    case 1n+p x <> t: mu_take.go(p, t, List.append(&2, U32, acc, [x]))
    case _ _      : acc

def mu_take(xs: List<&2, U32>, n: Nat) -> List<&2, U32>:
  mu_take.go(n, xs, Nil{})

def mu_prod_upto(xs: List<&2, U32>, n: Nat) -> U32:
  mu_prod(mu_take(xs, n))

# `shape == ()` -- the scalar test, which `alu_multi`'s `can_handle` and
# `shard_subview`'s EXPAND arm both ask. A COUNT, not a Bool, and both are
# one-element reads of the same def.
def mu_scalar(xs: List<&2, U32>) -> Bool:
  List.is_empty(&2, U32, xs)

# `tuple(x.shape) == tuple(multi.shape)` -- multi.py:81 and :96 and :265. It is
# a SHAPE COMPARISON, so it is a fold over two lists and not a length test:
# two shapes of the same length can differ, and `can_handle` turns on it.
# THE TWO-CONS ARM COMES FIRST. `case _ _: False{}` in second position SWALLOWS
# the cons-cons case and every non-empty comparison answers False -- MEASURED, it
# moved `t_sv_eq`, `t_sv_ne`, `t_sv_rank` and `t_al_full` all at once. The rule is
# that the SPECIFIC constructor pair precedes the catch-all, which is the same
# reason `mu_shard.go` puts `a <> at n <> nt` first.
def mu_shape_eq(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case x <> xt y <> yt: mu_and2(U32.is_eq(x, y), mu_shape_eq(xt, yt))
    case Nil{} Nil{}: True{}
    case _ _: False{}

# ===========================================================================
# `broadcast_axes` (ops.py:89) -- the out axes that are ADDED or EXPANDED:
#
#     nleft = len(out_shape) - len(src_shape)
#     return tuple(range(nleft)) + tuple(nleft+i for i,s in enumerate(src_shape)
#                                       if resolve(s == 1, default=False) and
#                                          resolve(out_shape[nleft+i] != 1))
#
# `shard_srcs` asks `axis in broadcast_axes(mlb.shape, out_shape)` (multi.py:75)
# and the answer is "leave this src WHOLE" or "shard it", so the SET IS THE WHOLE
# DECISION and it is gateable -- `bx_*` in the truth script is ten cases of
# Python's own `broadcast_axes`. `resolve` is symbolic (ops.py:1078,
# `tinygrad/uop/symbolic.py`), so with CONCRETE dims it is `s == 1` and
# `out != 1`, which is what `mu_ones` and `mu_not_one` are; the symbolic arm is
# the wall named in the header.
#
# The result is a `List<&2, U32>` of axis ids, not a set: `tuple(range(nleft))`
# is already sorted and unique, and membership is a scan. The two halves are
# APPENDED in Python's order -- the added axes first -- so a fixture that
# distinguishes "which half" can.
# ===========================================================================
def mu_ones(s: U32) -> Bool:
  U32.is_eq(s, 1)

def mu_not_one(s: U32) -> Bool:
  Bool.not(mu_ones(s))

# `tuple(range(n))`, ascending, which is `range(nleft)` and also the
# `enumerate` index set. Walking UP and appending keeps the order.
def mu_range_u32.go(n: Nat, +k: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: mu_range_u32.go(p, U32.add(k, 1), List.append(&2, U32, acc, [k]))

def mu_range_u32(n: Nat) -> List<&2, U32>:
  mu_range_u32.go(n, 0, Nil{})

# the EXPANDED half. `i` is the src index and the emitted axis is `nleft + i`,
# so both ride in the call; recovering `nleft` from `ax - i` would be a
# subtraction and a `to_nat` per step to save one parameter.
# the `s == 1` half and the `out_shape[nleft+i] != 1` half, as ONE Bool, because
# `Bool.and` of two calls cannot be a `match` scrutinee and this is the only
# thing the step decides.
def mu_exp_keep(s: U32, out: List<&2, U32>, +nleft: U32, +i: Nat) -> Bool:
  Bool.and(mu_ones(s), mu_not_one(mu_at(out, U32.to_nat(U32.add(nleft, U32.from_nat(i))))))

# `keep ? [ax] : []` appended -- the conditional append, which is what
# `Bool.pick` is for but is spelled as a def because `acc` is `+` here.
def mu_exp_add(keep: Bool, ax: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match keep:
    case True{} : List.append(&2, U32, acc, [ax])
    case False{}: acc

# ONE recursive def for the whole walk: the step is `put` and `next` folded in,
# because `mu_exp` calling back into `mu_exp.go` would be MUTUAL recursion and
# is refused, and the declaration rule means a helper above cannot call a def
# below it. The two helpers above are leaves, so this stays a single self-call.
# THE LIST IS THE FIRST PARAMETER because the self-call must be DECREASING AND
# READ LEFT TO RIGHT, so the subterm has to come first -- the shape `red_factor`
# and `red_bounds` use. `nleft` and `i` ride at the end and are never both read
# before the shrink.
def mu_exp.go(src: List<&2, U32>, +out: List<&2, U32>, acc: List<&2, U32>,
              +nleft: U32, +i: Nat) -> List<&2, U32>:
  match src:
    case Nil{}: acc
    case s <> t: mu_exp.go(t, out, mu_exp_add(mu_exp_keep(s, out, nleft, i),
                                              U32.add(nleft, U32.from_nat(i)), acc),
                           nleft, Nat.add(i, 1n))

def mu_exp(nleft: U32, src: List<&2, U32>, out: List<&2, U32>) -> List<&2, U32>:
  mu_exp.go(src, out, Nil{}, nleft, 0n)

# THE CALL. `nleft < 0` is Python's RuntimeError -- `cannot broadcast src into
# out` -- and there is no out axis to name, so it is `None{}`: the same "the
# port does not answer" that `allreduce.bend`'s IndexError spellings use.
def mu_baxes.of(ok: Bool, +nleft: U32, +src: List<&2, U32>, +out: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match ok:
    case True{} : Some{List.append(&2, U32, mu_range_u32(U32.to_nat(nleft)), mu_exp(nleft, src, out))}
    case False{}: None{}

def mu_baxes(+src: List<&2, U32>, +out: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  mu_baxes.of(U32.is_ge(U32.from_nat(mu_len(out)), U32.from_nat(mu_len(src))),
              U32.sub(U32.from_nat(mu_len(out)), U32.from_nat(mu_len(src))), src, out)

# `axis in broadcast_axes(...)` -- multi.py:75. A scan, and the answer IS the
# branch: True leaves the src WHOLE, False shards it.
def mu_in_go(xs: List<&2, U32>, +w: U32, acc: Bool) -> Bool:
  match xs:
    case Nil{}: acc
    case x <> t: mu_in_go(t, w, Bool.or(acc, U32.is_eq(x, w)))

def mu_in(xs: List<&2, U32>, w: U32) -> Bool:
  mu_in_go(xs, w, False{})

# ===========================================================================
# THE TWO WITNESS TYPES, and they are the reason this file is mostly index
# arithmetic. Every Python rule body ends in a BUILDER -- `.unshard(...)`,
# `.alu(...)`, `.mselect(i)`, `UOp(Ops.STACK, ...)`, `._mop(...)` -- and every
# one of those is a `TODO(p3)` in `ops.bend`. What is left is the part a rewrite
# has to get RIGHT before it may reach for a builder, and that part is a set of
# integers:
#
#   * which axes the rewrite acts on,
#   * which shard COUNT divides which dim,
#   * which src of the rewritten node comes from where,
#   * and whether the rule fires at all.
#
# So a "decision" below is a `Data` record of those integers and a `Hop`-shaped
# answer that is `0` because no node can be built. The `Nd` record is the read
# side; the decision records are the write side.
# ===========================================================================
# `Bd` is one `(start, length)` pair. A SHRINK's `marg` is `tuple[(int,sint)]`
# (multi.py:166) and a PAD's is `tuple[(int,sint)]` too (multi.py:151), and both
# are read by `shrink_multi` and `pad_multi` respectively, so one record serves
# both and the two are named at the call sites.
type Bd is Data:
  Bd{s: U32, l: U32}

def Bd.s(b: Bd) -> U32:
  match b:
    case Bd{s, l}: s

def Bd.l(b: Bd) -> U32:
  match b:
    case Bd{s, l}: l

# THE MARG, as a list of pairs, and the FOLD that builds one. A marg is read at
# `marg[ax]` in four places (multi.py:149, 166, 169, 172) and iterated in two, so
# it is a list and not a fixed arity.
# `marg[ax]` -- Python's IndexError out of range, and 0 is the marker. The
# `Ss` and `Sk` records carry the axis that was asked for, so a caller that must
# not silently get 0 has it.
def mu_bd_at(ms: List<&2, Bd>, ax: Nat) -> Bd:
  Maybe.default(&2, Bd, List.get(&2, Bd, ms, ax), Bd{0, 0})

# `mu_marg_put(ax, pair, ms)` -- `local_marg[ax] = (0, shard_sz)` at
# multi.py:168 and :172. The SET, and not an append, and the two are different
# functions: `List.set` replaces by index.
def mu_marg_put(ax: Nat, b: Bd, ms: List<&2, Bd>) -> List<&2, Bd>:
  List.set(&2, Bd, ms, ax, b)

# THE `(0, shard_sz)` pair that appears three times (multi.py:168, :172, :178)
# and `Bd{0, 0}` is not it -- `Bd{0, shard_sz}` is, and naming it once is how a
# port says "this is the shard-local full extent, not an absent pair".
def mu_local_extent(shard_sz: U32) -> Bd:
  Bd{0, shard_sz}

# ===========================================================================
# `_apply_shrink` (multi.py:9-12). NOT PORTED, and the reason is `x.ranges`:
#
#     drng = [r for r in x.ranges if r.axis_type is AxisType.DEVICE]
#     ... x.substitute({drng[0]: drng[0].const_like(i)}) ...
#     return s._mop(Ops.SHRINK, tuple(new_arg))
#
# `UOp.ranges` (ops.py:497) is the recursive property `rangeify.bend` names as
# its biggest wall (`rf_ranges_miss`, ops.py:497) -- `_ranges` is
# `union(s.ranges for s in self.src)` minus every range an `ended_ranges` carries
# and it is memoised on the node in Python, which Bend has neither mutable state
# nor a memo for. So the substitution cannot be built here.
#
# WHAT IS PORTED is the SHAPE of the predicate, because it is a decision the
# caller makes per src and it is the reason `mstack_early_shrink` treats some srcs
# differently from others: `mu_src_has_dev` is `x.ranges` carrying a DEVICE
# range, and the port answers it from a PARAMETER so the branch is still a branch
# and not a constant. `mu_dev_miss()` is the honest empty answer and the gate
# pins it.
# ===========================================================================
def mu_dev_miss() -> Bool: False{}

# `any(r.axis_type is AxisType.DEVICE for r in x.ranges)` -- the predicate, with
# the range SET a parameter. The set is `List<&2, U32>` of arena indices and the
# test is `rf_axis_is` on each, which `fold.bend` has as `F.UOp.axis_type`.
# THE AXIS-TYPE READ, and it reads the NODE'S OWN ARG rather than going through
# `fold.bend`, which is deliberate. `F.axis_at` is the fold's spelling and it
# works -- but it drags `F.folded(ar)` in, and that build currently reaches
# `fold.bend:1053` `const_i64.go`, whose wildcard arm is `case _ _:` for a
# ONE-scrutinee `match` and is a compile error. That is a bug in a READ-ONLY
# sibling, REPORTED NOT FIXED (see the foot), and this def is the local spelling
# so this file does not depend on it: `UOp.axis_type` (ops.py:507) is a RANGE's
# arg, `ARange{ids, at}`, and `at` IS the AxisType.
def mu_at_of.go(a: O.Arg) -> Maybe<&2, O.AxisType>:
  match a:
    case O.ARange{ids, at}: Some{at}
    case _: None{}

def mu_at_of(ar: O.Arena, self: U32) -> Maybe<&2, O.AxisType>:
  mu_at_of.go(O.Arena.arg(ar, self))

def mu_is_dev.go(m: Maybe<&2, O.AxisType>) -> Bool:
  match m:
    case Some{a}: O.eq_axis(a, O.AXIS_DEVICE{})
    case _: False{}

def mu_is_dev(+ar: O.Arena, self: U32) -> Bool:
  mu_is_dev.go(mu_at_of(ar, self))

def mu_has_dev.go(+ar: O.Arena, rs: List<&2, U32>, acc: Bool) -> Bool:
  match rs:
    case Nil{}: acc
    case r <> t: mu_has_dev.go(ar, t, Bool.or(acc, mu_is_dev(ar, r)))

def mu_src_has_dev(+ar: O.Arena, ranges: List<&2, U32>) -> Bool:
  mu_has_dev.go(ar, ranges, False{})

# `mstack_early_shrink` (multi.py:14-22) -- the per-src decision, which is the
# part that is not a builder:
#
#     if x.op is Ops.COPY:  src = _apply_shrink(shrink.marg, x.src[0], i)
#                           ret = src.contiguous() if src.device == x.device else src.copy_to_device(...)
#     else:                 ret = _apply_shrink(shrink.marg, x, i).contiguous()
#
# So there are THREE outcomes per src and the choice is `(is_copy, same_device)`.
# `mstack_early_shrink`'s `_apply_shrink` itself is the wall above; what is here
# is `mu_mstack_branch`, and `ms_*` in the gate are its rows.
#
# 0 is COPY-and-same-device (`.contiguous()`), 1 is COPY-and-different-device
# (`.copy_to_device`), 2 is not-COPY (`.contiguous()`). The NUMBERING IS
# Python's: the `if x.op is Ops.COPY` test comes FIRST, so COPY is the outer arm
# and the device test is the inner one.
# the device half comes FIRST because a def may only call defs declared above
# it, and `.of` needs `.copy`. Python writes it the other way round -- the `if
# x.op is Ops.COPY` is the outer test -- and the two arms below say so, so the
# reordering is visible rather than silent.
def mu_mstack_branch.copy(same_dev: Bool) -> U32:
  match same_dev:
    case True{}: 0
    case False{}: 1

def mu_mstack_branch.of(is_copy: Bool, same_dev: Bool) -> U32:
  match is_copy:
    case True{}: mu_mstack_branch.copy(same_dev)
    case False{}: 2

def mu_mstack_branch(is_copy: Bool, same_dev: Bool) -> U32:
  mu_mstack_branch.of(is_copy, same_dev)

# ===========================================================================
# `shard_srcs` (multi.py:54-76). THE CENTRAL DECISION, and the function three
# resharding fallbacks call (`alu_multi` :104, `stack_multi` :200). It is the
# most arithmetically dense body in multi.py and none of it is a builder, so all
# of it is here:
#
#     devices = [x.device for x in msrcs if x.device is not None]
#     assert all_same(devices)
#     if len(devices): sharding_rng = UOp.range(len(devices[0]), -1, DEVICE)
#     else:            sharding_rng = next(m.src[1] for m in msrcs if m.op is UNSHARD)
#     out_shape = _broadcast_shape(*[x.shape for x in msrcs])
#     for mlb in msrcs:
#       src_axis = axis - (len(out_shape) - len(mlb.shape))
#       if mlb.axis == src_axis:                       srcs.append(mlb.src[0])
#       else:
#         full = mlb if mlb.axis is None else copy_multi(mlb, mlb.device)
#         srcs.append(full if axis in broadcast_axes(mlb.shape, out_shape)
#                     else full._shard(src_axis, sharding_rng))
#
# FOUR decisions, and they are four defs because they are four answers:
#   `mu_ss_rng`    WHICH sharding range -- a fresh DEVICE range over the devices,
#                  or the UNSHARD's own `src[1]` (a LOCAL thread range, per the
#                  comment at multi.py:58-59).
#   `mu_ss_out`    the broadcast shape.
#   `mu_ss_axis`   `src_axis`, the RIGHT-ALIGNMENT.
#   `mu_ss_kind`   the three-way per-src branch: copy through / whole / shard.
#
# `_broadcast_shape` is `fold.bend`'s `bcast_shape` (ops.py:80) and it is not
# re-derived here -- reuse, not duplication. What IS here is `mu_bs_*`, the
# `IsNone` test on its answer, because a shape MISMATCH is an IndexError in
# Python (ops.py:85) and a `None` here, and every caller must be able to ask.
# ===========================================================================
def mu_bs_none(m: Maybe<&2, List<&2, O.Sint>>) -> Bool:
  Maybe.is_none(&2, List<&2, O.Sint>, m)

# `out_shape = _broadcast_shape(*[x.shape for x in msrcs])` (multi.py:65). The
# shapes are a list of `List<Sint>`, so they need `fold.bend`'s `Shapes` -- a
# list of `Sized` with the LONGEST length beside it, which is `Shapes.m`, and
# `F.shapes_of` is the walk that builds it from `List<Derived>`. This file does
# NOT have a `Derived` list (that is the fold's own bookkeeping), so the two
# shapes go in one at a time through `F.shapes_of.put` and the `None` answer is
# `F.bcast_shape`'s.
#
# `F.bcast_shape` is REUSED, not re-derived: it is ops.py:80 verbatim and it
# refuses a mismatch with `None`, which is ops.py:85's IndexError.
def mu_sh_put(sh: Maybe<&2, F.Shapes>, x: List<&2, O.Sint>) -> Maybe<&2, F.Shapes>:
  match sh:
    case Some{v}: Some{F.shapes_of.put(F.sized(x), v)}
    case _: None{}

def mu_out_shape.sh(shapes: List<&2, List<&2, O.Sint>>, acc: Maybe<&2, F.Shapes>) -> Maybe<&2, F.Shapes>:
  match shapes:
    case Nil{}: acc
    case x <> t: mu_out_shape.sh(t, mu_sh_put(acc, x))

def mu_out_shape(shapes: List<&2, List<&2, O.Sint>>) -> Maybe<&2, List<&2, O.Sint>>:
  F.bcast_shape(mu_out_shape.sh(shapes, Some{F.Shapes{Nil{}, 0n}}))

# `src_axis = axis - (len(out_shape) - len(mlb.shape))` (multi.py:68). THE
# RIGHT-ALIGNMENT, and it is one subtraction of two RANKS. A rank out of range is
# Python's IndexError and `U32.sub` wraps, so the gate rows are all in-range and
# `ss_ax_*` says which: `ss_ax_1_0` is a rank-2 src against a rank-2 out, which
# is the case that LOOKS like it should shift and does not.
def mu_ss_axis(axis: U32, out_n: Nat, src_n: Nat) -> U32:
  U32.sub(axis, U32.from_nat(Nat.sub(out_n, src_n)))

# `sharding_rng` (multi.py:60-63) -- WHICH of the two sources, and it is a
# genuine either/or:
#
#     if len(devices): sharding_rng = UOp.range(len(devices[0]), -1, DEVICE)
#     else:
#       sharding_rng = next((m.src[1] for m in msrcs if m.op is Ops.UNSHARD), None)
#       assert sharding_rng is not None, "shard_srcs requires a device or a sharding range"
#
# The comment above it is upstream's own and it is the reason the else branch
# exists: "without devices the sharding range comes from the UNSHARD itself
# (e.g. a LOCAL thread range); device shards range over the devices instead".
# So the two cases are not "device or no device" but "shard over the DEVICES or
# shard over a RANGE", and a LOCAL range's COUNT is a thread count, not a device
# count -- which is why `mu_count`'s DEVICE-range arm does not apply to it and
# why the two branches of this def are different `Ss` constructions.
#
# `Ss` is the sharding source: `n` is the shard COUNT (`len(devices[0])`, or the
# UNSHARD's own `src[1]` range's count), and `from_unshard` says which branch
# chose it. The RANGE NODE is not carried, because `shard_srcs` only ever passes
# it to `_shard`, which is a builder -- the wall -- and the count is the half
# that every reader in this file wants.
type Ss is Data:
  Ss{n: U32, from_unshard: Bool}

def Ss.n(s: Ss) -> U32:
  match s:
    case Ss{n, from_unshard}: n

def Ss.from_unshard(s: Ss) -> Bool:
  match s:
    case Ss{n, from_unshard}: from_unshard

# `len(devices)` -- the FIRST conjunct of `if len(devices):`. `ndev` is the
# device COUNT, which is `Ss.n` in the DEVICE branch and is not the shard count
# in the other one, so it is a parameter rather than a read.
# the `no_dev` Bool is a PARAMETER of `.of` rather than `U32.is_zero(ndev)`
# computed in the wrapper, because a `match` may not scrutinise a call
# (brief-port.md, rule 2). The wrapper is one line and the ladder is the other.
def mu_ss_rng.of(no_dev: Bool, ndev: U32, unshard_n: U32) -> Ss:
  match no_dev:
    case True{} : Ss{unshard_n, True{}}
    case False{}: Ss{ndev, False{}}

def mu_ss_rng(+ndev: U32, unshard_n: U32) -> Ss:
  mu_ss_rng.of(U32.is_zero(ndev), ndev, unshard_n)

# the `assert sharding_rng is not None`, which is a RAISE in Python (multi.py:63)
# and the message names the two legal cases. It is `mu_ss_none`: no devices and
# no UNSHARD in `msrcs`. Both of those are zeros here -- `Ss{0, True{}}` -- so the
# raise is the one case where a shard count of 0 is NOT also the wall marker, and
# saying so is the reason this def exists at all.
def mu_ss_none(+s: Ss) -> Bool:
  Bool.and(Ss.from_unshard(s), U32.is_zero(Ss.n(s)))

# `all_same(devices)` (multi.py:57) -- the ASSERT, and it is the whole content of
# `shard_srcs`'s first three lines besides the device list. It is a scan over the
# device NAMES, and a name here is a `U32` tag, so the comparison is
# `U32.is_eq`. `H.all_same_u32` is `helpers.all_same` and it is reused rather than
# written again: it is the same fold over the same question.
def mu_ss_same(devs: List<&2, U32>) -> Bool:
  H.all_same_u32(devs)

# THE PER-SRC BRANCH (multi.py:68-75), and it is the densest decision in the
# file. Written out in full, because the port needs all four of it:
#
#     src_axis = axis - (len(out_shape) - len(mlb.shape))
#     if mlb.axis == src_axis:            srcs.append(mlb.src[0])        # COPY THROUGH
#     else:
#       full = mlb if mlb.axis is None else copy_multi(mlb, mlb.device)  # whole, or a copy
#       srcs.append(full if axis in broadcast_axes(mlb.shape, out_shape) # WHOLE, or SHARDED
#                   else full._shard(src_axis, sharding_rng))
#
# Four outcomes, and the ORDER of the tests is load-bearing because the arms are
# not disjoint in an obvious way:
#   0 COPY THROUGH -- `mlb.axis == src_axis`
#   1 WHOLE        -- no axis at all (`mlb.axis is None`)
#   2 BROADCAST    -- `axis in broadcast_axes(mlb.shape, out_shape)`
#   3 SHARDED      -- everything else
# `1` and `2` both "append the whole src" but for different reasons and they need
# different BUILDERS (`copy_multi` vs not), which is why they are two numbers.
# `ml_ss_*` in the gate are one row per outcome, and `ml_kind_*` are the two
# inputs that choose between them.
type Sk is Data:
  Sk{kind: U32, sa: U32}

def Sk.kind(s: Sk) -> U32:
  match s:
    case Sk{kind, sa}: kind

def Sk.sa(s: Sk) -> U32:
  match s:
    case Sk{kind, sa}: sa

# `if mlb.axis == src_axis` -- the OUTER test, and it is `None == src_axis` for
# a src with no axis, which is False, so a scalar src never copies through. That
# is load-bearing: `mu_axis_is` on a `None` answers False and Python's
# `mlb.axis == src_axis` does too, so the two agree, and `ss_ax` rows with a
# scalar src are what say it.
def ml_through(mlb_ax: Maybe<&2, U32>, sa: U32) -> Bool:
  mu_axis_is(mlb_ax, sa)

# `mlb.axis is None` -> the WHOLE outcome.
def ml_whole(mlb_ax: Maybe<&2, U32>) -> Bool:
  Bool.not(mu_has_axis(mlb_ax))

# `axis in broadcast_axes(mlb.shape, out_shape)` -> the BROADCAST outcome. `None`
# (a shape mismatch, ops.py:85) is False: Python would have raised, and the safe
# direction is "not broadcast", which is SHARD -- the third outcome, and the
# `_shard` that the whole function exists to compute.
def ml_bcast.go(m: Maybe<&2, List<&2, U32>>, axis: U32) -> Bool:
  match m:
    case Some{x}: mu_in(x, axis)
    case _: False{}

def ml_bcast(src: List<&2, U32>, out: List<&2, U32>, axis: U32) -> Bool:
  ml_bcast.go(mu_baxes(src, out), axis)

# THE BRANCH. `through` is the outer `if`, `whole` is `mlb.axis is None`, `bcast`
# is the broadcast_axes membership, and the order is Python's: `through` first
# (so a src already on the right axis copies through whatever else it is), then
# `whole`, then `bcast`.
# BOTTOM UP, because a def may only call defs declared ABOVE it (brief-port.md,
# rule 1) and this ladder is three `match`es. Python writes it as one `if/elif`
# chain; here it is three nested defs and the names say which Python test each
# one is: `.bc` is the broadcast_axes test, `.rest` adds `mlb.axis is None`, and
# `.of` adds `mlb.axis == src_axis` FIRST because Python's outer `if` is that
# one.
def ml_kind.bc(bcast: Bool) -> U32:
  match bcast:
    case True{}: 2
    case False{}: 3

def ml_kind.rest(whole: Bool, bcast: Bool) -> U32:
  match whole:
    case True{}: 1
    case False{}: ml_kind.bc(bcast)

def ml_kind.of(through: Bool, whole: Bool, bcast: Bool) -> U32:
  match through:
    case True{}: 0
    case False{}: ml_kind.rest(whole, bcast)

def ml_kind(+mlb_ax: Maybe<&2, U32>, +sa: U32, +src: List<&2, U32>, +out: List<&2, U32>, axis: U32) -> Sk:
  Sk{ml_kind.of(ml_through(mlb_ax, sa), ml_whole(mlb_ax),
                ml_bcast(src, out, axis)), sa}

# `full = mlb if mlb.axis is None else copy_multi(mlb, mlb.device)` (multi.py:74).
# The decision is the `is None` test and the outcome is a builder, so what is here
# is the test. `ml_whole` IS that test; the point of naming it twice would be
# nothing, so `copy_multi`'s arm is the `else` of a `Bool` and is its own row.
def ml_needs_copy(mlb_ax: Maybe<&2, U32>) -> Bool:
  Bool.not(ml_whole(mlb_ax))

# ===========================================================================
# `shard_subview` (multi.py:78-85). THREE steps and two of them are builders:
#
#     assert tuple(full.shape) == tuple(multi.shape)
#     if full.op is Ops.EXPAND and full.src[0].shape == (): return full.src[0].expand(multi.src[0].shape)
#     for ax, rng in multi.sharding: full = full._shard(ax, rng)
#     return full
#
# The ASSERT is `mu_shape_eq` on two shapes and it is a real gate: multi.py:81's
# message names both shapes, and a rewrite that sub-viewed a differently-shaped
# dest would corrupt a STORE rather than raise. `ss_eq_*` in the gate is its two
# sides.
#
# The EXPAND arm is the interesting one and upstream explains it: "an EXPAND of a
# scalar over the full shape is the same broadcast on every shard: re-expand over
# the shard shape". The test has TWO conjuncts and both are gateable, and the
# second one -- `full.src[0].shape == ()` -- is `mu_scalar` on src[0]'s shape.
# The outcome is `expand(multi.src[0].shape)`, a builder.
def sv_expand.of(is_expand: Bool, inner_sc: Bool) -> Bool:
  Bool.and(is_expand, inner_sc)

def sv_expand(full_op: O.Op, inner_sc: Bool) -> Bool:
  sv_expand.of(O.eq_op(full_op, O.OpsEXPAND{}), inner_sc)

# the sharding loop, `for ax, rng in multi.sharding` -- a COUNT and a fold. The
# fold itself is `full._shard(ax, rng)` per axis, a builder; what is ported is
# how many `_shard` calls there are and on WHICH axes, and `_shard` divides the
# dim by the shard count, so the per-axis size is arithmetic and is here.
def sv_nshard(sh: List<&2, Sh>) -> Nat:
  mu_nshard(sh)

def sv_axes(sh: List<&2, Sh>) -> List<&2, U32>:
  List.foldl(~&2, ~Sh, ~List<&2, U32>, (acc: List<&2, U32>) => (s: Sh) => List.append(&2, U32, acc, [Sh.ax(s)]), sh, Nil{})

# `_shard` (ops.py:751-756):
#
#     dcount = int(rng.vmax)+1
#     if self.shape[axis] % dcount != 0: raise RuntimeError("multi axis uneven")
#     sz = self.shape[axis] // dcount
#     return self.shrink(tuple((0,s) if i != axis else (rng*sz, rng*sz+sz) for i,s in enumerate(self.shape)))
#
# THE ARITHMETIC, and it is two of the three lines: the DIVISIBILITY test, which
# is a raise in Python and a Bool here, and `sz`, the per-shard extent.
# `sv_div_*` and `sv_sz_*` are the rows, and `sv_div` is 0 for a shard count of
# 0 -- `U32.mod(_, 0)` is refused rather than 0, so the guard comes first and the
# 0 case is the wall, not an answer.
def sv_divides.of(nonzero: Bool, ok: Bool) -> Bool:
  Bool.and(nonzero, ok)

def sv_divides(+n: U32, dim: U32) -> Bool:
  sv_divides.of(Bool.not(U32.is_zero(n)), U32.is_zero(U32.mod(dim, n)))

def sv_div(dim: U32, n: U32) -> Bool:
  sv_divides(n, dim)

# the DIVIDES test and the DIVISION, guarded by it, in that order because
# `U32.mod(x, 0)` is refused rather than 0 -- so an uneven dim raises in Python
# and answers the wall marker here rather than dividing by zero.
def sv_sz.of(ok: Bool, dim: U32, n: U32) -> U32:
  match ok:
    case True{}: U32.div(dim, n)
    case False{}: mu_sym_dim()

def sv_sz(+dim: U32, +n: U32) -> U32:
  sv_sz.of(sv_div(dim, n), dim, n)

# ===========================================================================
# `alu_multi` (multi.py:87-105). The `can_handle` closure is the whole body of
# the decision and it is three lines:
#
#     def can_handle(m):
#       if m.sharding: return m.sharding == sharding
#       return m.shape == () or tuple(m.shape) == tuple(target.shape)
#     if all(can_handle(m) for m in root.src): ... per-shard path
#     ... resharding fallback
#
# So the decision is a PER-SRC classification into three classes and a
# conjunction over them, and the sharding EQUALITY is the load-bearing part:
# `sharding` is a tuple of `(axis, RANGE)` pairs, so comparing two of them means
# comparing both the axes AND the counts, and a comparison that looked only at
# the axes would accept two sharding ranges with DIFFERENT device counts.
# `al_eq_*` is the row that says the count is compared.
# the fold FIRST, for the declaration rule, and it is the `+`-free version: the
# accumulator carries "every pair so far was equal" and the ragged arms carry the
# answer Python's tuple `==` gives for a length mismatch, which is False.
# THE TWO-CONS ARM FIRST, for the same reason `mu_shape_eq` does: a catch-all in
# second position swallows it. `al_eq` and `al_eq_two` were 0 until it moved.
# the PAIR comparison as a leaf, because `mu_and3` would read the second `Sh` three
# times and bend2 spends a parameter on its first use -- MEASURED, that is
# `expected : y, observed : y (consumed more than once)`.
def al_pair(+x: Sh, +y: Sh) -> Bool:
  mu_and2(U32.is_eq(Sh.ax(x), Sh.ax(y)), U32.is_eq(Sh.n(x), Sh.n(y)))

def al_sh_eq.go(a: List<&2, Sh>, b: List<&2, Sh>, acc: Bool) -> Bool:
  match a b:
    case x <> xt y <> yt: al_sh_eq.go(xt, yt, mu_and2(acc, al_pair(x, y)))
    case Nil{} Nil{}: acc
    case _ _: False{}

def al_sh_eq(a: List<&2, Sh>, b: List<&2, Sh>) -> Bool:
  al_sh_eq.go(a, b, True{})

# `m.shape == ()` -- a scalar, which broadcasts and needs no sub-view.
def al_scalar(m_sc: Bool) -> Bool:
  m_sc

# `tuple(m.shape) == tuple(target.shape)` -- a whole value of the FULL TILE shape,
# which takes its per-shard sub-view instead. Comment kept: "or a whole unsharded
# value of the full tile shape (takes its per-shard sub-view), or a broadcast
# scalar".
def al_full(m_sc: Bool, m_shape: List<&2, U32>, tgt: List<&2, U32>) -> Bool:
  Bool.and(Bool.not(m_sc), mu_shape_eq(m_shape, tgt))

# `can_handle(m)` -- `if m.sharding: return m.sharding == sharding` first, and
# that is a GUARD: a sharded src is judged ONLY by its sharding and the two
# scalar/full tests never run for it. `al_handle` is that ladder.
# `can_handle(m)` -- `if m.sharding: return m.sharding == sharding` first, and
# that is a GUARD and not a filter: a SHARDED src is judged ONLY by its sharding
# and neither the scalar test nor the full-shape test ever runs for it. That is
# why `have_sh` short-circuits the other two, and `al_handle` is the ladder.
def al_handle.of(have_sh: Bool, same_sh: Bool, +m_sc: Bool,
                 m_shape: List<&2, U32>, tgt: List<&2, U32>) -> Bool:
  match have_sh:
    case True{} : same_sh
    case False{}: Bool.or(al_scalar(m_sc), al_full(m_sc, m_shape, tgt))

def al_handle(have_sh: Bool, same_sh: Bool, +m_sc: Bool,
             m_shape: List<&2, U32>, tgt: List<&2, U32>) -> Bool:
  al_handle.of(have_sh, same_sh, m_sc, m_shape, tgt)


def al_nmultis(shs: List<&2, Sh>) -> Nat:
  List.length(&2, Sh, shs)

# `al_none` matches the Nat DIRECTLY rather than through `List.is_empty`: it is a
# `match` on a PARAMETER, which is what that rule allows (brief-port.md, rule 2),
# and the length is already a `Nat`.
def al_none(n: Nat) -> Bool:
  match n:
    case 0n: True{}
    case _: False{}

# ===========================================================================
# `reduce_multi` (multi.py:107-123). The decision is the SPLIT of the sharding by
# `num_axes`, and it is four lines of Python over two comprehensions:
#
#     op, num_axes = root.arg
#     reduced   = [(ax, rng) for ax, rng in sharding if ax <  num_axes]
#     remaining = [(ax, rng) for ax, rng in sharding if ax >= num_axes]
#     local = multi.src[0]._rop(op, tuple(range(num_axes)))
#     if reduced:
#       assert not remaining, "partial allreduce not supported for multi-axis sharding"
#       if ALLREDUCE_CAST and multi.src[0].op is Ops.CAST and multi.src[0].src[0].dtype in (bf16, half): ...
#       return local.allreduce(op, multi.device)
#     new_axes = tuple(ax - num_axes for ax, _ in remaining)   # PIECEWISE
#     return local.unshard(new_axes, new_rngs)
#
# `op` and `num_axes` are `root.arg`, which is `AReduce{rop, num_axes}`
# (ops.py:752) -- already split in `ops.bend`, so both are direct reads.
# `reduced` and `remaining` are exhaustive and DISJOINT by construction (`<` and
# `>=`), so a sharding of length n gives `len(reduced) + len(remaining) == n`
# ALWAYS; `rd_*_n` and `rd_sum_n` in the gate are that row, and it is the one
# that would catch a partition that dropped or duplicated an axis.
#
# The `remaining` AXES ARE REBASED by `num_axes` (multi.py:121) and that is the
# arithmetic `off` carries -- it is why a REDUCE over two of three sharded axes
# unshards on axis 0 and not axis 2.
type Rd is Data:
  Rd{red: List<&2, U32>, rem: List<&2, U32>, off: List<&2, U32>}

def Rd.red(r: Rd) -> List<&2, U32>:
  match r:
    case Rd{red, rem, off}: red

def Rd.rem(r: Rd) -> List<&2, U32>:
  match r:
    case Rd{red, rem, off}: rem

def Rd.off(r: Rd) -> List<&2, U32>:
  match r:
    case Rd{red, rem, off}: off

# the two comprehensions, as three folds over one sharding. `off` walks the
# `remaining` half, so it takes that half as its OWN list rather than re-testing.
def rd_red.put(keep: Bool, ax: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match keep:
    case True{} : List.append(&2, U32, acc, [ax])
    case False{}: acc

def rd_red.go(sh: List<&2, Sh>, +na: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match sh:
    case Nil{}: acc
    case +s <> t: rd_red.go(t, na, rd_red.put(U32.is_lt(Sh.ax(s), na), Sh.ax(s), acc))

def rd_red(sh: List<&2, Sh>, na: U32) -> List<&2, U32>:
  rd_red.go(sh, na, Nil{})

def rd_rem.put(keep: Bool, ax: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match keep:
    case True{} : List.append(&2, U32, acc, [ax])
    case False{}: acc

def rd_rem.go(sh: List<&2, Sh>, +na: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match sh:
    case Nil{}: acc
    case +s <> t: rd_rem.go(t, na, rd_rem.put(U32.is_ge(Sh.ax(s), na), Sh.ax(s), acc))

def rd_rem(sh: List<&2, Sh>, na: U32) -> List<&2, U32>:
  rd_rem.go(sh, na, Nil{})

def rd_off.go(xs: List<&2, U32>, +na: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case +x <> t: rd_off.go(t, na, List.append(&2, U32, acc, [U32.sub(x, na)]))

def rd_off(xs: List<&2, U32>, na: U32) -> List<&2, U32>:
  rd_off.go(xs, na, Nil{})

def rd_split(+sh: List<&2, Sh>, +na: U32) -> Rd:
  Rd{rd_red(sh, na), rd_rem(sh, na), rd_off(rd_rem(sh, na), na)}

# `if reduced:` -- Python's truthiness of a tuple. A LIST is the truth here and
# `rd_any` is its emptiness, so a sharding with NO reduced axis is the PIECEWISE
# arm and `rd_piece` is the row.
def rd_any(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{} : False{}
    case _ <> _: True{}

# `assert not remaining` (multi.py:114) -- the PARTIAL allreduce raise, and it
# only applies on the full-allreduce arm, which is why it is `not remaining` AND
# `reduced`. `rd_bad` is the honest spelling: a sharding that straddles
# `num_axes` is one Python refuses, and `rd_mix_bad` is the row.
def rd_bad(+r: Rd) -> Bool:
  Bool.and(rd_any(Rd.red(r)), rd_any(Rd.rem(r)))

def rd_fires(+r: Rd) -> Bool:
  Bool.and(rd_any(Rd.red(r)), Bool.not(rd_any(Rd.rem(r))))

# the ALLREDUCE_CAST arm (multi.py:116-118), and it is THREE conjuncts:
#
#     if ALLREDUCE_CAST and multi.src[0].op is Ops.CAST and multi.src[0].src[0].dtype in (dtypes.bf16, dtypes.f16):
#       orig_dtype = multi.src[0].src[0].dtype
#       return local.cast(orig_dtype).allreduce(op, multi.device).cast(local.dtype)
#
# The flag is the `Cfg.cast` PARAMETER (the header's convention). The dtype test
# is `in (bfloat16, half)` -- TWO dtypes and not one, and `S.Dt` is a `Data`
# record so the comparison is `S.bfloat16()` / `S.half()` by value. The graph is
# the wall (`allreduce.bend`'s, plus two `.cast`s).
# `S.Dt` is a `Data` record {pri, bits, cls, nm} (spec.bend:75) so equality is
# NOT structural -- `O.eq_dt` is what `ops.bend` itself uses for a dtype
# comparison (ops.bend:3707) and it compares the RANK (`pri`), which is
# `dtype.py`'s declaration order and is unique per dtype.
def rd_low_dt(+dt: S.Dt) -> Bool:
  Bool.or(O.eq_dt(dt, S.bfloat16()), O.eq_dt(dt, S.half()))

def rd_cast(cfg: Cfg, src0_op: O.Op, inner_dt: S.Dt) -> Bool:
  Bool.and(Cfg.cast(cfg), Bool.and(O.eq_op(src0_op, O.OpsCAST{}), rd_low_dt(inner_dt)))

# ===========================================================================
# `reshape_multi` (multi.py:125-140). The whole body is ARITHMETIC and none of
# it is a builder, which makes this the most completely ported function in the
# file:
#
#     if prod(multi.shape) != prod(new_shape := root.marg): raise
#     arg_acc = [1] ... accumulate(mul, initial=1) over new_shape
#     for ax, rng in multi.sharding:
#       count  = int(rng.vmax) + 1
#       target = ssimplify(prod(multi.shape[:ax]))
#       if target not in arg_acc: raise RuntimeError("moved items between shards")
#       new_ax = len(arg_acc) - arg_acc[::-1].index(target) - 1
#       if new_shape[new_ax] % count != 0: raise RuntimeError(same)
#       new_shardings.append((new_ax, rng))
#     new_shape = tuple(s // (int(rng.vmax)+1) if a in new_axs else s for a,s in enumerate(new_shape))
#
# FOUR pieces of arithmetic and THREE raises, and the three raises are three
# distinct failure modes:
#   1. `prod(multi.shape) != prod(new_shape)` -- the reshape is not a reshape.
#   2. `target not in arg_acc` -- the shard boundary does not survive the
#      reshape, so items would move between shards.
#   3. `new_shape[new_ax] % count != 0` -- the boundary survives but does not
#      divide evenly.
# `Rs` carries all three as ONE `ok`, because Python raises on the FIRST and
# the three are alternatives, so a port that answered all three independently
# would have to invent an order it does not have. `rs_*_ok` are the rows.
#
# `new_ax = len(arg_acc) - arg_acc[::-1].index(target) - 1` is the LAST index
# whose running product is `target` -- `rs_rev_index` counts from the END and
# `rs_new_ax` converts. It is a REVERSED search and that is load-bearing: two
# entries of `arg_acc` can be equal (when a dim of `new_shape` is 1), and
# `.index` on the REVERSED list takes the LAST one, i.e. the LARGEST axis that
# preserves the boundary. `rs_tie_*` in the gate is the row for it.
# ===========================================================================
type Rs is Data:
  Rs{ok: Bool, ax: U32, acc: List<&2, U32>}

def Rs.ok(r: Rs) -> Bool:
  match r:
    case Rs{ok, ax, acc}: ok

def Rs.ax(r: Rs) -> U32:
  match r:
    case Rs{ok, ax, acc}: ax

def Rs.acc(r: Rs) -> List<&2, U32>:
  match r:
    case Rs{ok, ax, acc}: acc

# `arg_acc = [1] + accumulate(new_shape, mul)` (multi.py:128-129). The running
# product, and it STARTS AT 1 -- so `arg_acc` has `len(new_shape) + 1` entries
# and `rs_acc_n` in the gate is that +1, which is the row that says the initial
# 1 is there.
# EVERY STEP APPENDS ITS RUNNING PRODUCT, not only the last one. Appending only at
# the end gives `[1, prod]` -- MEASURED, that made every `rsa*` row wrong and
# `rsa_n` short by `len(new_shape)`.
def rs_acc.go(xs: List<&2, U32>, +acc: U32, out: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: List.append(&2, U32, out, [acc])
    case x <> +t: rs_acc.go(t, U32.mul(acc, x), List.append(&2, U32, out, [acc]))

# THE INITIAL 1 IS THE FIRST APPEND, because `itertools.accumulate(..., initial=1)`
# (multi.py:129) puts it at the HEAD: the seed is the running product BEFORE any dim
# and every step appends its own. MEASURED both ways -- leaving the seed out made
# `rs_acc_n` short by one, and seeding the OUTPUT as well made it long by one.
def rs_acc(xs: List<&2, U32>) -> List<&2, U32>:
  rs_acc.go(xs, 1, Nil{})

# `target in arg_acc` -- a scan over a U32 list, so `mu_in` is reused rather than
# written again.
def rs_has(+acc: List<&2, U32>, target: U32) -> Bool:
  mu_in(acc, target)

# `arg_acc[::-1].index(target)` -- the position from the END, and the reason the
# `.index` is on the REVERSED list is that two entries of `arg_acc` can be EQUAL
# (a `new_shape` dim of 1 repeats the running product) and Python takes the
# FIRST of the reversed list, i.e. the LAST of the forward one. So the fold is a
# FORWARD walk that keeps the most recent hit, and `rs_tie_*` in the gate is the
# row that says "most recent" and not "first".
#
# The accumulator is `last` and the hit test is a separate leaf, because a
# `match` may not scrutinise a call (brief-port.md, rule 2). `no` is the
# not-found marker and is `n`, one past the last index, so it is distinguishable
# from index 0 by construction -- 0 is a REAL index here and `rs_head_*` uses it.
def rs_hit.put(hit: Bool, i: Nat, last: Nat) -> Nat:
  match hit:
    case True{} : i
    case False{}: last

def rs_hit.go(xs: List<&2, U32>, +w: U32, +i: Nat, last: Nat) -> Nat:
  match xs:
    case Nil{}: last
    case x <> t: rs_hit.go(t, w, Nat.add(i, 1n), rs_hit.put(U32.is_eq(x, w), i, last))

def rs_hit(xs: List<&2, U32>, w: U32, n: Nat) -> Nat:
  rs_hit.go(xs, w, 0n, n)

# the reversed index: `len(acc) - 1 - last`. `rs_rev` is a separate def so the
# subtraction is visible and the gate can pin each side.
def rs_rev.of(found: Bool, n: Nat, last: Nat) -> Maybe<&2, Nat>:
  match found:
    case True{} : Some{Nat.sub(Nat.sub(n, 1n), last)}
    case False{}: None{}

def rs_rev(+acc: List<&2, U32>, +w: U32) -> Maybe<&2, Nat>:
  rs_rev.of(rs_has(acc, w), mu_len(acc), rs_hit(acc, w, mu_len(acc)))

# `new_ax = len(arg_acc) - arg_acc[::-1].index(target) - 1`. `None` is the
# `target not in arg_acc` RAISE, and the port answers 0 with `ok = False`, which
# is `rs_*_ok` and `rs_*_ax` together in the gate.
def rs_new_ax.of(found: Maybe<&2, Nat>, n: Nat) -> Rs:
  match found:
    case Some{i}: Rs{True{}, U32.from_nat(Nat.sub(Nat.sub(n, i), 1n)), Nil{}}
    case _       : Rs{False{}, 0, Nil{}}

def rs_new_ax(+acc: List<&2, U32>, w: U32) -> Rs:
  rs_new_ax.of(rs_rev(acc, w), mu_len(acc))

# `new_shape[new_ax] % count != 0` -- the SECOND raise, and it is the
# divisibility of the BOUNDARY dim, which is `new_shape[rs_new_ax]`, NOT the
# source dim. `rs_div` is False for a count of 0 (`U32.mod(_, 0)` is refused) and
# that is `mu_count`'s wall arriving here.
def rs_div.of(nonzero: Bool, ok: Bool) -> Bool:
  Bool.and(nonzero, ok)

def rs_div(+count: U32, dim: U32) -> Bool:
  rs_div.of(Bool.not(U32.is_zero(count)), U32.is_zero(U32.mod(dim, count)))

# THE PER-AXIS DECISION, both raises folded into one `ok`. Python's order is the
# `target in arg_acc` raise FIRST and the divisibility raise second, so a target
# that is absent answers `ok = False` without ever asking about divisibility --
# and that ordering is what `rs_axis.of` writes down.
def rs_axis.of.ok(ok: Bool, +r: Rs) -> Rs:
  match ok:
    case True{} : r
    case False{}: Rs{False{}, Rs.ax(r), Rs.acc(r)}

def rs_axis.of(+r: Rs, div: Bool) -> Rs:
  rs_axis.of.ok(Bool.and(Rs.ok(r), div), r)

# `new_shape[ax]` with `rs_at`'s marker of 0 for an out-of-range axis, which is
# what makes `rs_div(count, 0)` True and the decision fall through to the raise.
def rs_bd(ax: U32, new_n: List<&2, U32>) -> U32:
  mu_at(new_n, U32.to_nat(ax))

# The boundary dim is `new_shape[rs_new_ax]`, so `new_n` is the WHOLE new shape
# and the axis is indexed out of it. Passing a length and reading `dim 0` instead
# would make the divisibility test constant, and `rs_*_div` in the gate is the
# row for it: `rs_same` has boundary dim 4 and count 2 (divides) while `rs_tie`
# has boundary dim 3 and count 2 (does not), and a constant would answer both the
# same way.
def rs_axis.dim(r: Rs, +new_n: List<&2, U32>) -> U32:
  rs_bd(Rs.ax(r), new_n)

def rs_axis.all(+r: Rs, new_n: List<&2, U32>, count: U32) -> Rs:
  rs_axis.of(r, rs_div(count, rs_axis.dim(r, new_n)))

def rs_axis(+acc: List<&2, U32>, +target: U32, count: U32, new_n: List<&2, U32>) -> Rs:
  rs_axis.all(rs_new_ax(acc, target), new_n, count)

# `new_shape = tuple(s // (int(rng.vmax)+1) if a in new_axs else s for a,s in enumerate(new_shape))`
# (multi.py:139). The LOCAL shape: every axis the reshape re-sharded is divided
# by its count, every other axis is untouched. `Ns` carries the three lists that
# walk together -- `new_shape`, the new shard AXES, and their counts -- because
# `rs_local` reads all three per axis and a `Data` record is how three lists
# travel as one value.
#
# The sharding AXES here are the `new_ax`s of the loop above, not the original
# `arg`, and that is the load-bearing part: a reshape from (4,6) sharded on 0 to
# (24,) re-shards on axis 0 again, but from (4,6) to (2,12) has `target` 4 absent
# from `[1,2,24]` and RAISES.
type Ns is Data:
  Ns{dims: List<&2, U32>, axes: List<&2, U32>, counts: List<&2, U32>}

def Ns.dims(n: Ns) -> List<&2, U32>:
  match n:
    case Ns{dims, axes, counts}: dims

def Ns.axes(n: Ns) -> List<&2, U32>:
  match n:
    case Ns{dims, axes, counts}: axes

def Ns.counts(n: Ns) -> List<&2, U32>:
  match n:
    case Ns{dims, axes, counts}: counts

# `a in new_axs` -- multi.py:139's set membership, which is `mu_in` on the axis
# list. It is a LIST and not a set because `new_axs` is built by a comprehension
# over the sharding and `sharding` has distinct axes, so a scan is exact.
# `a` is fine as a NAME here but `as` is not a name at all (it is the `case x
# as y` binding), so the axis argument is `ax` throughout this block.
def ns_sharded(n: Ns, ax: U32) -> Bool:
  mu_in(Ns.axes(n), ax)

# `as` is a BEND KEYWORD (the `case x as y` binding), so the axis list is `aa`.
# The count for an axis is a SCAN and not a `List.get`, because `Ns` carries the
# counts as a parallel list and an axis is not an index into it.
def ns_count.hit(hit: Bool, c: U32, acc: U32) -> U32:
  match hit:
    case True{} : c
    case False{}: acc

# THE LISTS COME FIRST because the self-call must be DECREASING AND READ LEFT TO
# RIGHT (brief-port.md, rule 5): the axes are the subterm and they come first.
def ns_count.go(aa: List<&2, U32>, cs: List<&2, U32>, +ax: U32, acc: U32) -> U32:
  match aa cs:
    case x <> xt c <> ct: ns_count.go(xt, ct, ax, ns_count.hit(U32.is_eq(x, ax), c, acc))
    case _ _: acc

# the count for axis `ax`, or 0 -- 0 means "not sharded on this axis", and
# `rs_local` divides only when `ns_sharded` said yes, so the 0 is never a
# divisor.
def ns_count(+n: Ns, ax: U32) -> U32:
  ns_count.go(Ns.axes(n), Ns.counts(n), ax, 0)

# the PER-DIM step, above the fold that uses it, because a def may only call defs
# declared ABOVE it (brief-port.md, rule 1). The two conjuncts of
# `s // count if a in new_axs else s` are kept in `rs_local.one.ok` so `n` is read
# twice and not four times, and the ORDER is Python's: membership first, then
# divisibility.
# THREE-WAY, and the middle case was wrong: `not sharded` must KEEP `d` and only an
# UNEVEN sharded axis is the wall marker. MEASURED, returning the marker for the
# unsharded arm made `rs_loc1` and `rs_loc_none` 0 -- the whole local shape was the
# right length and full of zeros.
def rs_local.one.div(div: Bool, +d: U32, c: U32) -> U32:
  mu_pick(div, U32.div(d, c), mu_sym_dim())

def rs_local.one.of(sharded: Bool, div: Bool, +d: U32, c: U32) -> U32:
  mu_pick(sharded, rs_local.one.div(div, d, c), d)

def rs_local.one.ok(sharded: Bool, legal: Bool) -> Bool:
  Bool.and(sharded, legal)

def rs_local.one(+n: Ns, +ax: U32, +d: U32) -> U32:
  rs_local.one.of(ns_sharded(n, ax), rs_div(ns_count(n, ax), d), d, ns_count(n, ax))

# THE FOLD: `s // count if a in axes else s`, walking `new_shape` with the axis
# INDEX beside it. `List.append` puts each dim at the tail, so the order is
# `new_shape`'s.
#
# THE DIM LIST IS THE FIRST PARAMETER, for the same reason `ns_count.go` is: the
# self-call must be decreasing and read left to right, so the shrinking list is
# first and the `Ns` and the counter ride at the end.
def rs_local.go(dims: List<&2, U32>, +n: Ns, +a: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match dims:
    case Nil{}: acc
    case d <> t: rs_local.go(t, n, Nat.add(a, 1n),
                             List.append(&2, U32, acc, [rs_local.one(n, U32.from_nat(a), d)]))

def rs_local(+n: Ns) -> List<&2, U32>:
  rs_local.go(Ns.dims(n), n, 0n, Nil{})

# `prod(multi.shape) != prod(new_shape)` -- the FIRST raise (multi.py:126). Both
# products are `mu_prod` and the message names both, so the port compares them.
def rs_prods.of(a: U32, b: U32) -> Bool:
  U32.is_eq(a, b)

def rs_prods(+shape: List<&2, U32>, +new_n: List<&2, U32>) -> Bool:
  rs_prods.of(mu_prod(shape), mu_prod(new_n))

# `local = multi.src[0].reshape(new_shape)` -- the builder, and `new_shape` is
# `rs_local`'s answer. `rs_reshape` is the def that would carry it; the graph is
# the wall named in the header.

# ===========================================================================
# `expand_multi` (multi.py:142-145) -- the shortest fully-portable body in the
# file:
#
#     shift = len(root.marg)
#     return multi.src[0]._mop(Ops.EXPAND, arg=root.marg).unshard(
#                tuple(ax+shift for ax,_ in multi.sharding), tuple(r for _,r in multi.sharding))
#
# An EXPAND ADDS `len(marg)` axes at the FRONT (ops.py:816's `as_shape` on
# `src[1]`), so every sharded axis moves UP by `shift` and the count is unchanged.
# That is the whole decision: one addition per axis. "all permutes supported!",
# upstream's comment at :155, is the same claim one operation later.
# `ex_*` in the gate are the shifted axes and the UNCHANGED count, and
# `ex_count_*` is what says an EXPAND does not reshard.
# ===========================================================================
def ex_shift(marg_n: Nat) -> U32:
  U32.from_nat(marg_n)

# `ax + shift` over the sharding, and the count is `mu_nshard` unchanged.
def ex_axes.go(sh: List<&2, Sh>, +shift: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match sh:
    case Nil{}: acc
    case +s <> t: ex_axes.go(t, shift, List.append(&2, U32, acc, [U32.add(Sh.ax(s), shift)]))

def ex_axes(sh: List<&2, Sh>, shift: U32) -> List<&2, U32>:
  ex_axes.go(sh, shift, Nil{})

def ex_rngs.go(sh: List<&2, Sh>, acc: List<&2, U32>) -> List<&2, U32>:
  List.foldl(~&2, ~Sh, ~List<&2, U32>, (a: List<&2, U32>) => (s: Sh) => List.append(&2, U32, a, [Sh.n(s)]), sh, acc)

def ex_rngs(sh: List<&2, Sh>) -> List<&2, U32>:
  ex_rngs.go(sh, Nil{})

# ===========================================================================
# `permute_multi` (multi.py:154-157) -- also short, and also pure:
#
#     return multi.src[0].permute(root.marg).unshard(
#                tuple(root.marg.index(ax) for ax,_ in multi.sharding), ...)
#
# `tuple.index(ax)` is the index OF the axis IN the permutation, and it is a
# SEARCH and not an identity: `permute((1,0))` sends axis 0 to 1. `pm_*` in the
# gate is exactly `tuple.index`, so `pm_sw` (axis 0 under `(1,0)`) is 1 and
# `pm_id` is 0. An axis not in the permutation is Python's ValueError and is
# `None` here.
# ===========================================================================
# `tuple.index` as a FOLD over a RECORD, not a `Maybe` that the walk carries. The
# reason is MEASURED and it is a bend2 rule and not a style choice: a step that
# calls back into the walk (`.step` -> `.go`) is MUTUAL RECURSION and is refused,
# and the declaration rule means a helper above cannot call a def below it. `Pi`
# is the walk's state -- the index and whether it was found -- and it is one
# value so the fold has one accumulator.
type Pi is Data:
  Pi{idx: Nat, found: Bool}

def Pi.idx(p: Pi) -> Nat:
  match p:
    case Pi{idx, found}: idx

def Pi.found(p: Pi) -> Bool:
  match p:
    case Pi{idx, found}: found

def pi_step.go(p: Pi, hit: Bool, i: Nat) -> Pi:
  match hit:
    case True{} : Pi{i, True{}}
    case False{}: p

# the step: a hit overwrites the index and the `found` flag, a miss keeps both.
# `found` does not stop the walk, and it must not: the caller asked for `.index`
# and not `.rindex`, so an early exit would be a different function.
def pi_step(p: Pi, hit: Bool, i: Nat) -> Pi:
  match hit:
    case True{} : Pi{i, True{}}
    case False{}: p

def pm_index.go(xs: List<&2, U32>, +w: U32, +i: Nat, p: Pi) -> Pi:
  match xs:
    case Nil{}: p
    case x <> t: pm_index.go(t, w, Nat.add(i, 1n), pi_step(p, U32.is_eq(x, w), i))

# `None` when the axis is not in the permutation -- Python's ValueError from
# `tuple.index` -- and `Some{i}` when it is.
def pm_index.of(found: Bool, idx: Nat) -> Maybe<&2, Nat>:
  match found:
    case True{} : Some{idx}
    case False{}: None{}

def pm_index.ans(+p: Pi) -> Maybe<&2, Nat>:
  pm_index.of(Pi.found(p), Pi.idx(p))

def pm_index(+marg: List<&2, U32>, w: U32) -> Maybe<&2, Nat>:
  pm_index.ans(pm_index.go(marg, w, 0n, Pi{0n, False{}}))

# `permute_multi` indexes with `tuple.index(ax)` and the answer is used as an AXIS,
# so it is a `Nat` on the way out and a `U32` on the way in. The `Maybe` is kept
# through `pm_of` -- a missing axis is Python's ValueError -- and 0 is the marker
# at the ONE place a bare axis is needed.
# `mu_head32` is the `U32` spelling; `tuple.index` answers an INDEX and this fold
# keeps it a `Nat` throughout, so the default is the `Nat` one and the conversion
# to an axis is here at the single place it happens.
def mu_head_nat(m: Maybe<&2, Nat>) -> Nat:
  Maybe.default(&2, Nat, m, 0n)

def pm_ax(+marg: List<&2, U32>, w: U32) -> U32:
  U32.from_nat(mu_head_nat(pm_index(marg, w)))

# `tuple(root.marg.index(ax) for ax,_ in multi.sharding)` -- the fold.
def pm_of.go(sh: List<&2, Sh>, +marg: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match sh:
    case Nil{}: acc
    case +s <> t: pm_of.go(t, marg, List.append(&2, U32, acc, [pm_ax(marg, Sh.ax(s))]))

def pm_of(+sh: List<&2, Sh>, marg: List<&2, U32>) -> List<&2, U32>:
  pm_of.go(sh, marg, Nil{})

# ===========================================================================
# `flip_multi` (multi.py:183-186) -- a CHECK and a list:
#
#     for ax, _ in multi.sharding:
#       if root.marg[ax]: raise RuntimeError(f"flipping not supported on sharded axis {ax}")
#     return multi.src[0].flip([i for i,x in enumerate(root.marg) if x]).unshard(...)
#
# So there is one RAISE per sharded axis -- flipping MOVES data across the shard
# boundary and cannot be made per-shard -- and one list of the NON-ZERO marg
# indices. A FLIP's marg is a per-axis BOOL (ops.py:812's `if self.op is Ops.FLIP:
# return src[1:]`), so the dim is a `U32` 0/1 here and the LIST IS THE ANSWER:
# `fl_none` is empty, `fl_all` is every axis, `fl_mid` skips the zeros. `flip_*`
# in the gate are both the raise test and the list length.
# ===========================================================================
def fl_any(marg: List<&2, U32>, ax: Nat) -> Bool:
  Bool.not(U32.is_zero(mu_at(marg, ax)))

# `for ax,_ in multi.sharding: if root.marg[ax]: raise` -- a SCAN for "any
# sharded axis is flipped", because Python raises on the first one it finds and
# the answer the port needs is only WHETHER one exists.
def fl_bad.go(sh: List<&2, Sh>, +marg: List<&2, U32>, acc: Bool) -> Bool:
  match sh:
    case Nil{}: acc
    case +s <> t: fl_bad.go(t, marg, Bool.or(acc, fl_any(marg, U32.to_nat(Sh.ax(s)))))

def fl_bad(sh: List<&2, Sh>, marg: List<&2, U32>) -> Bool:
  fl_bad.go(sh, marg, False{})

# `[i for i,x in enumerate(root.marg) if x]` -- the non-zero indices, in order.
def fl_of.put(zero: Bool, i: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match zero:
    case True{} : acc
    case False{}: List.append(&2, U32, acc, [U32.from_nat(i)])

def fl_of.go(marg: List<&2, U32>, +i: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match marg:
    case Nil{}: acc
    case x <> t: fl_of.go(t, Nat.add(i, 1n), fl_of.put(U32.is_zero(x), i, acc))

def fl_of(+marg: List<&2, U32>) -> List<&2, U32>:
  fl_of.go(marg, 0n, Nil{})

# ===========================================================================
# `pad_multi` (multi.py:147-152) -- one ASSERT over the sharded axes and a
# per-axis extent:
#
#     for ax, _ in multi.sharding:
#       assert root.marg[ax] == (0, multi.shape[ax]), "padding not supported"
#     counts = {a for a,_ in multi.sharding}
#     local_pad = tuple((0, multi.src[0].shape[a]) if a in counts else s for a,s in enumerate(root.marg))
#     return multi.src[0]._mop(Ops.PAD, local_pad).unshard(...)
#
# THE ASSERT IS NOT A COSMETIC GUARD: a PAD on a sharded axis would have to be
# replicated per shard with the sharded dim UNPADDED, and Python refuses it
# because the local pad it would compute is not the shard's extent. The port
# keeps the test and `pd_*_bad` in the gate is the row that says the test fires.
# The local pad is then the same shape of expression as `reshape_multi`'s
# `rs_local`: divide-or-keep per axis.
# ===========================================================================
# `marg[ax]` is read twice -- once for `s` and once for `l` -- so `mu_bd_at` is
# the shared read and the two projections ride out of one call. Python's
# `root.marg[ax] == (0, multi.shape[ax])` is a tuple comparison and this is its
# two components: the START is 0 and the LENGTH is the shard's full extent.
# THREE READS OF ONE AXIS -- `marg[ax]` twice and `shape[ax]` once. `ax` is a `Nat`
# and bend2 spends a parameter on its FIRST use, so the three answers travel as one
# record: the marg ENTRY and the shape DIM beside it. `Pd` holds the `Bd` itself
# rather than its two projections, because a `let` is affine too and the entry is
# read twice.
type Pd is Data:
  Pd{b: Bd, dim: U32}

def Pd.b(p: Pd) -> Bd:
  match p:
    case Pd{b, dim}: b

def Pd.dim(p: Pd) -> U32:
  match p:
    case Pd{b, dim}: dim

def Pd.at(+marg: List<&2, Bd>, +shape: List<&2, U32>, +ax: Nat) -> Pd:
  Pd{mu_bd_at(marg, ax), mu_at(shape, ax)}

def pd_ok.go(+p: Pd) -> Bool:
  Bool.and(U32.is_zero(Bd.s(Pd.b(p))), U32.is_eq(Bd.l(Pd.b(p)), Pd.dim(p)))

def pd_ok(+marg: List<&2, Bd>, +shape: List<&2, U32>, +ax: Nat) -> Bool:
  pd_ok.go(Pd.at(marg, shape, ax))

def pd_bad.go(sh: List<&2, Sh>, +marg: List<&2, Bd>, +shape: List<&2, U32>, acc: Bool) -> Bool:
  match sh:
    case Nil{}: acc
    case +s <> t: pd_bad.go(t, marg, shape, Bool.or(acc, Bool.not(pd_ok(marg, shape, U32.to_nat(Sh.ax(s))))))

def pd_bad(sh: List<&2, Sh>, marg: List<&2, Bd>, shape: List<&2, U32>) -> Bool:
  pd_bad.go(sh, marg, shape, False{})

# `local_pad = tuple((0, multi.src[0].shape[a]) if a in counts else s for a,s in enumerate(root.marg))`
# (multi.py:151). The same divide-or-keep shape as `rs_local`, but with a PAIR per
# axis, so it is a fold over the marg building `Bd`s.
#
# `counts = {a for a,_ in multi.sharding}` is a SET of the sharded axes, and the
# sharding's axes are distinct (`UOp.unshard` asserts `len(set(axis)) ==
# len(axis)`, ops.py:699), so membership in it is `mu_in` over a list. That list is
# a PARAMETER rather than a re-walk: `pd_bad` already walked the same sharding and
# Python rebuilds the set only because it is written as a comprehension.
# THE HEAD PAIR IS A PARAMETER AND NOT A RE-READ OF THE LIST, and that is the whole
# of `pd_one.step`. MEASURED both ways: the version that reached back into the full
# marg (`pd_one(marg, ax, axs)`) came back with the DEFAULT `Bd{0, 0}` for every
# entry after the first -- whatever the `+` marks were and whether the counter was a
# `Nat` or an `Ax` record -- while `blen` still said 2, so the COUNT row could not
# see it. `rs_local.go` has the same shape and works, and the difference is that its
# step takes the head element too.
# THE FOLD. The marg list is FIRST for the decreasing self-call, as everywhere else
# in this file, so the counter and the axis list ride at the end.
#
# THE STEP, and IT TAKES THE HEAD `Bd` AS A PARAMETER -- which is `rs_local.go`'s
# shape and the reason it works. MEASURED: a fold that reaches back into the full
# list for the head (`pd_one(marg, ax, axs)`) returned the DEFAULT pair for every
# entry after the first, whatever the `+` marks were, and the head-as-parameter form
# returns the marg's own entry. The head binder is spent by the pattern, so passing
# it on is the only way to read it.
# `(0, local.shape[a]) if a in counts else s` -- the one arm, and it is
# `mu_local_extent(Bd.l(d))` because Python REBUILDS the pair from the marg's own
# length rather than keeping it: for a sharded axis the local pad's extent is the
# SHARD's, not whatever the shrink said.
def pd_one.of(sharded: Bool, l: U32, d: Bd) -> Bd:
  match sharded:
    case True{} : mu_local_extent(l)
    case False{}: d

def pd_one.step(marg: List<&2, Bd>, axs: List<&2, U32>, ax: Nat, +d: Bd) -> Bd:
  pd_one.of(mu_in(axs, U32.from_nat(ax)), Bd.l(d), d)

def pd_of.go(marg: List<&2, Bd>, +axs: List<&2, U32>, +ax: Nat, acc: List<&2, Bd>) -> List<&2, Bd>:
  match marg:
    case Nil{}: acc
    case +d <> +t: pd_of.go(t, axs, Nat.add(ax, 1n),
                           List.append(&2, Bd, acc, [pd_one.step(marg, axs, ax, d)]))

def pd_of(+marg: List<&2, Bd>, +axs: List<&2, U32>) -> List<&2, Bd>:
  pd_of.go(marg, axs, 0n, Nil{})

# ===========================================================================
# `shrink_multi` (multi.py:159-181) -- THE LONGEST BODY IN THE FILE and the one
# with the most DECISION in it. Written out first, because the port needs all of
# it and the three outcomes are not a single expression:
#
#     local_marg, remaining = list(root.marg), list(multi.sharding)
#     for ax, rng in multi.sharding:
#       shard_sz = multi.src[0].shape[ax]
#       s, l = root.marg[ax]
#       if sint_to_uop(l).ssimplify() == shard_sz and (sint_to_uop(s)-rng*shard_sz).ssimplify() == 0:
#         local_marg[ax] = (0, shard_sz); remaining.remove((ax, rng)); continue
#       part_bounds = tuple((i*shard_sz, shard_sz) for i in range(int(rng.vmax)+1))
#       if (s, l) == (0, multi.shape[ax]): local_marg[ax] = (0, shard_sz)
#       else:
#         if len(multi.sharding) != 1 or not isinstance(multi.device, tuple) or (s, l) not in part_bounds:
#           raise RuntimeError("shrinking not supported")
#         non_shard_shrink = tuple((0, shard_sz) if i == ax else t for i, t in enumerate(root.marg))
#         return multi.src[0].copy_to_device(multi.device, arg=part_bounds.index((s, l)))._mop(Ops.SHRINK, non_shard_shrink)
#     val = multi.src[0]._mop(Ops.SHRINK, tuple(local_marg))
#     return val if not remaining else val.unshard(...)
#
# FOUR per-axis outcomes, and the ORDER is the whole function:
#   0 OWN      -- the shrink IS this range's own shard, so the UNSHARD RESOLVES and
#                 the axis leaves `remaining`. "a fragment indexed by its LOCAL
#                 thread range becomes that thread's REG shard, no copy needed".
#   1 WHOLE    -- the axis is not shrunk at all (`(s,l) == (0, shape[ax])`), so it
#                 stays sharded and only the OTHER axes shrink locally.
#   2 PARTITION -- the LEGACY device path: one partition copied to all devices,
#                 which multi.py:174-175 explicitly deprecates ("only allowed on
#                 the legacy device path, selecting a single partition (which is
#                 copied to all the devices and optimized out later)").
#   3 RAISE    -- `shrinking not supported`.
#
# The OWN test has TWO conjuncts and both are load-bearing: the LENGTH must equal
# the shard size (so the shrink covers this shard exactly) and the START must be
# `rng * shard_sz` (so it starts where this shard starts). A port that tested only
# the length would resolve an UNSHARD for a shrink of the WRONG half.
#
# `part_bounds` is `((i*shard_sz, shard_sz) for i in range(count))` -- the
# PARTITION boundaries, and it is pure arithmetic over two integers, so it is
# fully ported and gated: `pb_*` in the gate is CPython's own.
# ===========================================================================

# `shard_sz = multi.src[0].shape[ax]` (multi.py:165) -- the LOCAL shape, i.e.
# `multi.src[0]`, NOT `multi.shape`. That distinction is the whole of the OWN test:
# `l` is compared against the SHARD's extent and against `multi.shape[ax]` on the
# very next line, and they are different numbers whenever the axis is sharded.
# `part_bounds = tuple((i*shard_sz, shard_sz) for i in range(int(rng.vmax)+1))`
# THE COUNTDOWN IS FIRST because a self-call must be decreasing and read left to
# right: `n` is the fuel and `p` is its subterm, so it leads. `shard_sz` and the
# counter `k` ride after and are never both read before the shrink.
def sk_pb.go(n: Nat, +shard_sz: U32, +k: Nat, acc: List<&2, Bd>) -> List<&2, Bd>:
  match n:
    case 0n: acc
    case 1n+p: sk_pb.go(p, shard_sz, Nat.add(k, 1n),
                        List.append(&2, Bd, acc, [Bd{U32.mul(U32.from_nat(k), shard_sz), shard_sz}]))

def sk_pb(shard_sz: U32, n: U32) -> List<&2, Bd>:
  sk_pb.go(U32.to_nat(n), shard_sz, 0n, Nil{})

# `sk_eq` is the pair comparison both readers of `part_bounds` need -- the
# membership at multi.py:176 and the `.index` on the next line -- so it is one
# def and it is the two components of `Bd` compared.
# BOTH `Bd`s TRAVEL AS ONE RECORD. Two `Bd` parameters read twice each is four
# `+` markers and bend2 still counts the SECOND use of the outer parameter --
# MEASURED: `sk_eq(+a, b)` is `expected : b, observed : b (consumed more than
# once)` because `a` is spent by `Bd.s(a)` and `Bd.l(a)` before `b`'s first read.
# One `Data` parameter and a field pattern is the shape that works, and it is what
# `Nd`, `Sk` and `Rd` above are all doing.
type B2 is Data:
  B2{a: Bd, b: Bd}

def B2.a(t: B2) -> Bd:
  match t:
    case B2{a, b}: a

def B2.b(t: B2) -> Bd:
  match t:
    case B2{a, b}: b

def sk_eq.s(+t: B2) -> Bool:
  U32.is_eq(Bd.s(B2.a(t)), Bd.s(B2.b(t)))

def sk_eq.l(+t: B2) -> Bool:
  U32.is_eq(Bd.l(B2.a(t)), Bd.l(B2.b(t)))

def sk_eq(+t: B2) -> Bool:
  mu_and2(sk_eq.s(t), sk_eq.l(t))

# `(s, l) in part_bounds` -- multi.py:176's membership, and a scan over `Bd`s that
# reuses `sk_eq`.
def sk_in_go(pb: List<&2, Bd>, +b: Bd, acc: Bool) -> Bool:
  match pb:
    case Nil{}: acc
    case +x <> +t: sk_in_go(t, b, Bool.or(acc, sk_eq(B2{x, b})))

# `part_bounds.index((s, l))` -- WHICH PARTITION. The starts are DISTINCT (they are
# `i*shard_sz`), so first and last agree and a "keep the first hit" walk is the
# same as `.index`; `0` is the marker for "not present", which is the Python
# `ValueError` case and the one the caller must not use as a partition.
# A FOLD WITH AN ACCUMULATOR, because the walk cannot STOP: `.index` returns at the
# first hit and a `match` has no early exit, so `acc` carries "found at" and the
# counter carries "still looking". MEASURED: without the accumulator the walk
# returned the wall marker for every entry whose `s` did not match, and 1 for every
# entry that did, so `sk_at2` and `sk_at3` were 0.
def sk_at.step(found: Bool, hit: Bool, acc: U32, i: U32) -> U32:
  mu_pick(mu_and2(Bool.not(found), hit), i, acc)

def sk_at.next(i: U32) -> U32:
  U32.add(i, 1)

def sk_at.go(pb: List<&2, Bd>, +b: Bd, +i: U32, +acc: U32) -> U32:
  match pb:
    case Nil{}: acc
    case +x <> +t: sk_at.go(t, b, sk_at.next(i),
                           sk_at.step(U32.is_ne(acc, 4294967295), sk_eq(B2{x, b}), acc, i))

def sk_at(pb: List<&2, Bd>, b: Bd) -> U32:
  sk_at.go(pb, b, 0, 4294967295)

def sk_in(pb: List<&2, Bd>, b: Bd) -> Bool:
  sk_in_go(pb, b, False{})

# THE OWN TEST (multi.py:167), the two conjuncts, and BOTH are load-bearing:
#
#     sint_to_uop(l).ssimplify() == shard_sz   and
#     (sint_to_uop(s) - rng*shard_sz).ssimplify() == 0
#
# The first says the shrink's LENGTH is this shard's whole extent; the second says
# its START is where this shard starts. `sint_to_uop` and `ssimplify` (ops.py:520)
# are not ported, and for a CONCRETE marg both are the identity -- `sint_to_uop(4)`
# is a CONST and `ssimplify` of a CONST is itself -- so the port reads the concrete
# `U32` directly and the symbolic arm is the wall in the header.
#
# `rng` is a RANGE, so `rng*shard_sz` is SYMBOLIC in general and the second
# conjunct is NOT decidable in general. What is decidable and is what the port
# answers: the LENGTH half, and the start being exactly the partition start
# `i*shard_sz` -- which is `part_bounds`, the same table the legacy path needs.
# `sk_own_len` and `sk_own_start` are the two rows and `sk_own` is their
# conjunction.
def sk_len_eq(+marg: List<&2, Bd>, shard_sz: U32, +ax: Nat) -> Bool:
  U32.is_eq(Bd.l(mu_bd_at(marg, ax)), shard_sz)

# `(s, l) == (0, multi.shape[ax])` -- the WHOLE-axis test at multi.py:172, and it
# compares against `multi.shape` (the FULL shape) not the local one.
# `Pd` REUSED rather than a second record: it is exactly `(marg[ax], shape[ax])`
# and `pd_ok` is exactly this test with `multi.src[0].shape` where this wants
# `multi.shape`. The difference is WHICH shape, so it is a parameter and the test
# is `pd_ok` -- one comparison in the file rather than two.
def sk_whole_eq(+marg: List<&2, Bd>, +full: List<&2, U32>, +ax: Nat) -> Bool:
  pd_ok(marg, full, ax)

# THE FOUR-WAY PER-AXIS OUTCOME. Python's order is:
#
#   OWN        -- `l == shard_sz and s == rng*shard_sz`: the UNSHARD RESOLVES and
#                 the axis leaves `remaining` ("a fragment indexed by its LOCAL
#                 thread range becomes that thread's REG shard, no copy needed").
#   WHOLE      -- `(s,l) == (0, multi.shape[ax])`: the axis is not shrunk at all,
#                 so it stays sharded and only the OTHER axes shrink locally.
#   PARTITION  -- the LEGACY device path, `part_bounds.index((s,l))`. multi.py:174-175
#                 deprecates it explicitly: "only allowed on the legacy device path,
#                 selecting a single partition (which is copied to all the devices
#                 and optimized out later)".
#   RAISE      -- `shrinking not supported`, from the conjunctive test at :176:
#                 `len(multi.sharding) != 1 or not isinstance(multi.device, tuple)
#                 or (s,l) not in part_bounds`.
#
# IT IS ONE `mu_pick` CHAIN, not a ladder of `match`es, because a `match` may not
# scrutinise a call and every rung here tests a CONJUNCTION. `sk_raise2` is split
# out because its three conjuncts are a fact about the WHOLE shrink (they do not
# depend on the axis) and `sk_raise` exists for the same reason `rd_bad` does.
# THE RAISE IS THE `or` OF THE THREE FAILURES (multi.py:176): `len(sharding) != 1
# or not isinstance(device, tuple) or (s,l) not in part_bounds`. MEASURED, reading
# the two device/pb terms as POSITIVE (`bad_n or (one_dev and in_pb)`) answers
# PARTITION whenever the shape is legal, and `t_sk_r_n`, `t_sk_r_dev` and
# `t_sk_r_pb` were all 0 until the two `not`s went in.
def sk_raise2(bad_n: Bool, one_dev: Bool, in_pb: Bool) -> U32:
  mu_pick(mu_or3(bad_n, Bool.not(one_dev), Bool.not(in_pb)), 3, 2)

# the OUTER two outcomes, which skip the raise entirely because Python's
# `if own: ... continue` never reaches the `else`.
def sk_lift(own: Bool, whole: Bool, hi: U32) -> U32:
  mu_pick(own, 0, mu_pick(whole, 1, hi))

def sk_kind(own: Bool, whole: Bool, bad_n: Bool, one_dev: Bool, in_pb: Bool) -> U32:
  sk_lift(own, whole, sk_raise2(bad_n, one_dev, in_pb))


# `remaining.remove((ax, rng))` (multi.py:169) -- the OWN arm drops the axis from
# the sharding that the result carries. `List.drop` is not it: `remove` removes
# the ELEMENT, not a prefix, and a shard index is not a prefix index. It is a
# filter, and `sk_keep` is that filter with the equality `sk_eq` already has.
# ONE self-call per fold, and the equality is a separate LEAF because a def may
# not call a def declared below it and `sk_mem` recurses.
# `Sh` IS A `Data` RECORD AND `al_sh_eq` ALREADY COMPARES TWO OF THEM, so this is
# `al_sh_eq` under a second name rather than a fourth copy of the same fold.
def sk_same(a: Sh, b: Sh) -> Bool:
  al_sh_eq([a], [b])

def sk_mem(sh: List<&2, Sh>, +s: Sh) -> Bool:
  match sh:
    case Nil{}: False{}
    case +x <> +t: Bool.or(sk_same(x, s), sk_mem(t, s))

# AN AXIS THAT IS IN `drop` LEAVES THE SHARDING, so the KEEP test is the NEGATION of
# the membership. MEASURED, without the negation the fold kept the dropped axis and
# dropped a kept one: `sk_keep` was 1 where Python's `remaining` is 1 long AFTER
# removing one of two, and `t_sk_keep0` printed the wrong axis.
def sk_keep.put(keep: Bool, s: Sh, acc: List<&2, Sh>) -> List<&2, Sh>:
  match keep:
    case True{} : List.append(&2, Sh, acc, [s])
    case False{}: acc

def sk_keep.go(sh: List<&2, Sh>, +drop: List<&2, Sh>, acc: List<&2, Sh>) -> List<&2, Sh>:
  match sh:
    case Nil{}: acc
    case +s <> +t: sk_keep.go(t, drop, sk_keep.put(Bool.not(sk_mem(drop, s)), s, acc))

def sk_keep(sh: List<&2, Sh>, drop: List<&2, Sh>) -> List<&2, Sh>:
  sk_keep.go(sh, drop, Nil{})

# `non_shard_shrink = tuple((0, shard_sz) if i == ax else t for i, t in enumerate(root.marg))`
# (multi.py:178) -- the PARTITION arm's shrink. Every axis but the sharded one
# keeps its marg entry and the sharded one becomes the whole local extent, because
# the partition was already SELECTED by `copy_to_device(arg=...)` and the shrink
# must not cut it again.
def Bd.pick(cond: Bool, a: Bd, b: Bd) -> Bd:
  match cond:
    case True{} : a
    case False{}: b

# `non_shard_shrink = tuple((0, shard_sz) if i == ax else t for i, t in enumerate(root.marg))`
# (multi.py:178) -- the PARTITION arm's shrink, per axis: the sharded axis becomes
# the whole local extent and every other axis keeps its marg entry, because the
# partition was already SELECTED by `copy_to_device(arg=...)` and the shrink must
# not cut it again. The fold over `enumerate` is `pd_of`'s shape with the
# predicate inverted, and it is the same `List.append` at the tail.
def pd_nonshard(+marg: List<&2, Bd>, shard_sz: U32, is_ax: Bool, +ax: Nat) -> Bd:
  Bd.pick(is_ax, mu_local_extent(shard_sz), mu_bd_at(marg, ax))

def pd_nonshard.go2(marg: List<&2, Bd>, +sh: Sh, +ax: Nat, acc: List<&2, Bd>) -> List<&2, Bd>:
  match marg:
    case Nil{}: acc
    case +_ <> +t: pd_nonshard.go2(t, sh, Nat.add(ax, 1n),
                                   List.append(&2, Bd, acc,
                                               [pd_nonshard(marg, Sh.n(sh), U32.is_eq(U32.from_nat(ax), Sh.ax(sh)), ax)]))

# `shard_sz = multi.src[0].shape[ax]` for the ONE sharded axis, as a parameter of
# this fold: it is `Sk` data and reading it per axis would be a walk per axis.
# ===========================================================================
# `stack_multi` (multi.py:188-200). STACK ADDS A LEADING AXIS, so the srcs are
# sharded one axis BELOW the output and every sharded axis moves UP by one:
#
#     multis = [m for m in root.src if m.op is Ops.UNSHARD]
#     if not multis: return None
#     if all(m.sharding == sharding for m in multis):
#       new_sharding = tuple((ax+1, rng) for ax, rng in sharding)
#       return UOp(Ops.STACK, src=srcs).unshard(new_axes, new_rngs)
#     axis = root.axis ; assert axis is not None
#     return UOp(Ops.STACK, src=tuple(shard_srcs(root.src, axis-1))).unshard(axis, ...)
#
# So `stack_multi` is `expand_multi`'s shift with a constant of 1 and a
# resharding fallback. The shift is `ax + 1`, and the fallback's axis is
# `root.axis - 1` -- the SAME -1 that `shard_srcs` gets, because the STACK's
# output has one more axis than its srcs. `st_*` in the gate are the shifted axes
# and `st_off_*` is the fallback axis, and `st_off` reuses `ex_shift` on a `0n`
# because the shift is the only arithmetic in both.
# ===========================================================================
def st_shift.go(sh: List<&2, Sh>, acc: List<&2, U32>) -> List<&2, U32>:
  List.foldl(~&2, ~Sh, ~List<&2, U32>, (a: List<&2, U32>) => (s: Sh) => List.append(&2, U32, a, [U32.add(Sh.ax(s), 1)]), sh, acc)

def st_shift(sh: List<&2, Sh>) -> List<&2, U32>:
  st_shift.go(sh, Nil{})

# `axis - 1` for the resharding fallback, and `U32.sub` would WRAP for `axis == 0`
# rather than raise, so the guard is `axis > 0` and the 0 answer is the wall.
def st_off.of(zero: Bool, axis: U32) -> U32:
  match zero:
    case True{} : mu_sym_dim()
    case False{}: U32.sub(axis, 1)

def st_off(+axis: U32) -> U32:
  st_off.of(U32.is_zero(axis), axis)

def st_none(n: Nat) -> Bool:
  al_none(n)

# ===========================================================================
# `index_multi` (multi.py:202-222). THE TWO OWNERSHIP PATTERNS, and they are the
# only place in multi.py where `_min_max` is not just a shard COUNT:
#
#     idxs = list(root.src[1:])
#     for ax, rng in multi.sharding:
#       shard_sz = multi.src[0].shape[ax]
#       local = (idxs[ax] - rng*shard_sz).simplify()
#       if local.vmin >= 0 and local.vmax < shard_sz: idxs[ax] = local; continue
#       diff = (idxs[ax] - rng).simplify()
#       if (mod := (diff % shard_sz).simplify()).op is Ops.CONST and mod.val == 0:
#         local = (diff // shard_sz).simplify()
#         if local.vmin >= 0 and local.vmax < shard_sz: idxs[ax] = local; continue
#       raise RuntimeError("index_multi: cannot shard index ...")
#
#   contiguous: idx = rng*shard_sz + local   (thread rng owns [rng*sz, ...))
#   strided:    idx = rng + ir*shard_sz      (thread rng owns {rng, rng+sz, ...})
#
# So the same `vmin`/`vmax` window `[0, shard_sz)` is tested TWICE, once per
# pattern, and the two patterns differ in what is subtracted and in what is
# divided. That is the whole decision and it is two windows and a modulus.
#
# `vmin`/`vmax` are `UOp._min_max` (ops.py:1100-1104) and that is the wall; with a
# CONCRETE index the window is `0 <= x < shard_sz` and the port answers that.
# `ix_*` in the gate is CPython's own arithmetic for both patterns.
# ===========================================================================
# the window `0 <= x < shard_sz`, which is `local.vmin >= 0 and local.vmax < shard_sz`
# for a concrete `local`. `ix_in` is the row for both patterns.
# the window is `0 <= x < shard_sz`; `x` is a `U32` so the `vmin >= 0` half is
# TRUE BY CONSTRUCTION (an unsigned value has no negative) and only the upper
# bound survives. THAT is the one thing `_min_max` buys here, and it is stated
# rather than hidden: a SIGNED symbolic index would need the other half, and the
# wall in the header says so.
def ix_in(x: U32, shard_sz: U32) -> Bool:
  U32.is_lt(x, shard_sz)

# `idxs[ax] - rng*shard_sz` -- the CONTIGUOUS pattern's local index. The `rng` is
# a RANGE, so `rng*shard_sz` is symbolic; the concrete form the gate checks is
# `idx - i*shard_sz` and `ix_contig_*` is CPython's own.
def ix_contig(idx: U32, i: U32, shard_sz: U32) -> U32:
  U32.sub(idx, U32.mul(i, shard_sz))

# `diff = idxs[ax] - rng` and `local = diff // shard_sz` -- the STRIDED pattern.
def ix_strid(idx: U32, i: U32) -> U32:
  U32.sub(idx, i)

# NO ZERO GUARD, and that is a MEASURED fact rather than an omission:
# `U32.div(x, 0)` is 0 and `U32.mod(x, 0)` is `x` (base.bend:1501 and :1506, both
# `U32.div.if`/`U32.mod.if` take `U32.is_zero(b)` and short-circuit), so neither
# traps. A `shard_sz` of 0 is `mu_sym_dim`'s wall marker, and `U32.div(_, 0)` is
# already 0 -- the same value -- so the guard `rs_div`/`sv_divides` need above is
# about Python's RAISE and not about bend2's arithmetic. `ix_*_0` in the gate is
# the row that pins it.
def ix_mod(diff: U32, shard_sz: U32) -> U32:
  U32.mod(diff, shard_sz)

def ix_div(diff: U32, shard_sz: U32) -> U32:
  U32.div(diff, shard_sz)

# `(mod := (diff % shard_sz).simplify()).op is Ops.CONST and mod.val == 0` -- the
# strided pattern's ENTRY test, and with a concrete `diff` it is `mod == 0`. It
# is `ix_strid_ok` and it is a separate row because a strided fixture whose `diff`
# is not a multiple of `shard_sz` must NOT fire.
def ix_strid_ok(diff: U32, shard_sz: U32) -> Bool:
  U32.is_zero(ix_mod(diff, shard_sz))

# THE THREE-WAY OUTCOME per sharded axis: 0 CONTIGUOUS, 1 STRIDED, 2 RAISE. It is
# `mu_pick` twice because the strided arm has its OWN window and the raise is the
# fall-through of both.
# `ix_w` turns the strided window into the OUTCOME NUMBER, so `mu_pick` can select
# on it: 1 is STRIDED and 2 is the raise.
def ix_w(win: Bool) -> U32:
  mu_pick(win, 1, 2)

def ix_kind(contig: Bool, strid_mod: Bool, strid_win: Bool) -> U32:
  mu_pick(contig, 0, mu_pick(strid_mod, ix_w(strid_win), 2))

# ===========================================================================
# `_shard_idx` (multi.py:224-226):
#
#     drngs = [r for r in rng.ranges if r.axis_type is AxisType.DEVICE]
#     return 0 if not drngs else int(rng.substitute({drngs[0]: drngs[0].const_like(dev_idx)}).ssimplify())
#
# So it is 0 unless the range carries a DEVICE range, and then it is the DEVICE
# INDEX itself for a plain DEVICE range -- which is `copy_multi`'s
# `idxs = tuple(_shard_idx(r, i) for _, r in sharding)` when the sharding ranges
# ARE device ranges, i.e. every real multi tensor.
# ===========================================================================
def sx_idx(has_dev: Bool, dev_idx: U32) -> U32:
  mu_pick(has_dev, dev_idx, 0)

# ===========================================================================
# `copy_multi` (multi.py:228-252). The `str` branch is the one that runs: it
# reconstructs a multi-device value by CONCATENATING along each sharded axis, last
# to first.
#
#     piece_info = [(tuple(_shard_idx(r, i) for _, r in sharding),
#                    multi.src[0].mselect(i).copy_to_device(device)) for i in range(len(multi.device))]
#     for j in range(len(sharding)-1, -1, -1):
#       ax, rng = sharding[j]
#       groups = defaultdict(list)
#       for idxs, p in piece_info: groups.setdefault(idxs[:j]+idxs[j+1:], []).append((idxs[j], p))
#       piece_info = [(key, sorted(groups[key], key=lambda x: x[0])[0][1].cat(*..., dim=ax)) for key in sorted(groups)]
#     return piece_info[0][1]
#
# THE GROUP KEY IS THE DECISION: `idxs[:j] + idxs[j+1:]` is the tuple with the
# j-th element DELETED, and it is what makes the pieces group by "everything
# except this axis". Deleting the j-th index is not the same as zeroing it, and
# `cx_key_*` in the gate is Python's own `idxs[:j]+idxs[j+1:]` for the cases where
# the two differ -- which is every case with a repeated index, i.e. every
# multi-axis shard.
# ===========================================================================
# `cx_del` FIRST, because `cx_key` is a wrapper and a def may only call defs
# above it. THE LIST IS FIRST for the decreasing self-call, as everywhere else in
# this file, so the counter `j` rides last.
def cx_put.go(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  List.foldl(~&2, ~U32, ~List<&2, U32>, (a: List<&2, U32>) => (x: U32) => List.append(&2, U32, a, [x]), xs, acc)

def cx_put(acc: List<&2, U32>, xs: List<&2, U32>) -> List<&2, U32>:
  cx_put.go(xs, acc)

# `idxs[:j] + idxs[j+1:]` DELETES the j-th element and KEEPS every other one. The
# `0n` arm is the one that was wrong at first: it returned the accumulator EMPTY and
# so dropped the whole tail, which made `cx_key` a TRUNCATION rather than a
# deletion -- MEASURED, `cx_j0` and `cx_j0b` were 0 until it appended `xs`.
def cx_del(xs: List<&2, U32>, +j: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match xs j:
    case x <> t 0n  : cx_put(acc, t)
    case _ 0n        : acc
    case x <> t 1n+p: cx_del(t, p, List.append(&2, U32, acc, [x]))
    case _ _         : acc

def cx_key(+idxs: List<&2, U32>, j: Nat) -> List<&2, U32>:
  cx_del(idxs, j, Nil{})

# THE LENGTH IS `len(idxs) - 1`, and it is the COUNT that says the key dropped
# exactly one element -- `cx_key_n` in the gate is that row, and a key that
# dropped none (or two) would group pieces that belong to different shards.
def cx_key_n(k: List<&2, U32>) -> Nat:
  mu_len(k)

# ===========================================================================
# `replace_allreduce`'s FIVE rule bodies, and what is in each of them.
#
# Every one is a graph builder, and what is here is the DECISION each one makes
# before it builds -- and two of them make a decision worth gating on their own.
# ===========================================================================
# `lower_broadcast_copy` (multi.py:24-27):
#
#     if not (isinstance(c.device, tuple) and isinstance(x.device, str)): return None
#     if (sx := x.simplify()).device is None: return UOp(Ops.MSTACK, src=(sx,)*len(c.device))
#     return UOp(Ops.MSTACK, src=tuple(x.pad_to(x.max_shape).contiguous().copy_to_device(d) for d in c.device)).shrink_to(c.shape)
#
# TWO tests, and the first is a `return None` that is NOT a raise: a COPY whose
# source is not single-device, or whose dest is not multi-device, is simply not
# this rule's. So `lb_*` has a `none` row -- the rule does not fire -- which is
# the honest reading of `return None` and NOT of a raise, and the two are kept
# apart because `rangeify.bend`'s gate relies on exactly that distinction.
#
# `(sx,)*len(c.device)` -- the MULTISTACK REPLICATION COUNT, and it is
# `len(c.device)`, i.e. the number of devices on the dest. `lb_reps` is that
# number and it is a COUNT row.
def lb_fires(c_multi: Bool, x_single: Bool) -> Bool:
  mu_and2(c_multi, x_single)

def lb_reps(ndev: U32) -> U32:
  ndev

# `sx.device is None` picks the `(sx,)*ndev` arm; otherwise the pad/copy/shrink
# arm. `lb_none` reads the FIRST arm's condition, so the two arms are named.
def lb_none(sx_dev_none: Bool) -> Bool:
  sx_dev_none

# `copy_to_one` (multi.py:33-35) -- the SECOND COPY rule, and its guard is the
# MIRROR of the first one's: `isinstance(c.device, str) and isinstance(x.device,
# tuple)`. The two rules claim the SAME op set with the SAME (empty) reject set,
# so this is the two-rules-one-node fixture the brief asks for, and `claim_copy`
# in the gate is the row that says both claim it.
def co_fires(c_single: Bool, x_multi: Bool) -> Bool:
  mu_and2(c_single, x_multi)

# `m.mselect(0)` then `m.copy_to_device(c.device)` unless the devices already
# match: `(m if m.device == c.device else m.copy_to_device(c.device))`. The
# decision is the device EQUALITY and `co_same` is its row.
def co_same(same: Bool) -> Bool:
  same

# `MSELECT on MSTACK` (multi.py:37): `lambda mstack, ms: mstack.src[ms.arg]` --
# the answer is `MSTACK.src[ms.arg]`, so the decision is the INDEX and the bounds
# test. `ms.arg` is a `U32` and `mstack.src` has some length; out of range is
# Python's IndexError and is the 0 marker here.
def ms_arg_ok(arg: U32, nsrc: U32) -> Bool:
  U32.is_lt(arg, nsrc)

def ms_arg.of(ok: Bool, arg: U32) -> U32:
  match ok:
    case True{} : arg
    case False{}: mu_sym_dim()

def ms_arg(+arg: U32, nsrc: U32) -> U32:
  ms_arg.of(ms_arg_ok(arg, nsrc), arg)

# MSELECT BEFORE MOVEMENT (multi.py:41-42) and BEFORE ALU (multi.py:43-44). Both
# are "move the MSELECT inside", both are builders, and what differs is whether
# the src is checked for a TUPLE device: the ALU arm is
# `s.mselect(ms.arg) if isinstance(s.device, tuple) else s`, the movement arm is
# unconditional (`v.replace(src=(s.mselect(ms.arg),)+v.src[1:])`). That difference
# is the decision and `mv_none`/`al_none_src` are its two rows.
def mv_all(c: Bool) -> Bool:
  c

def mv_pick(dev_is_tuple: Bool) -> U32:
  mu_pick(dev_is_tuple, 1, 0)

# `store_after_multi` (multi.py:254), `store_value_multi` (:256-258),
# `store_dest_multi` (:260-266) and `passthrough_multi` (:268-270). All four are
# pure builders over `root.src`, and all four share ONE decision: which src gets
# the UNSHARD peeled. `st_pick` is that per-src decision, and it is THREE-way:
#
#     x.src[0]          if x.op is Ops.UNSHARD      -- PEEL
#     shard_subview(x)  if x.shape == multi.shape  -- SUB-VIEW
#     x                                          -- WHOLE
#
# `store_dest_multi`'s comment says why the middle arm exists and it is kept:
# "UNSHARD srcs peel, full-shape values take their per-shard sub-view (scalars
# arrive EXPANDed to the full shape by UOp.store's const_like, so they sub-view
# like everything else)". `store_dest_multi` is the only rule whose body is a
# comprehension over `root.src[1:]` (multi.py:264-265), so its arm order is
# UNSHARD, then full-shape, then whole -- NOT the scalar case.
def st_pick(is_unshard: Bool, full: Bool) -> U32:
  mu_pick(is_unshard, 0, mu_pick(full, 1, 2))

# `store_value_multi`'s two srcs are `shard_subview(dest, multi)` and
# `multi.src[0]` -- a fixed pair, and the decision is `sv_expand`'s.
# `rewrite_into_function` (multi.py:272-278) is NOT PORTED and it is the deepest
# wall in the file: it is `graph_rewrite(call.body, multi_pm, name="subcall")`, a
# RECURSIVE call into the very matcher that is calling it. `ops.bend` cannot call
# into this file and bend2 refuses mutual recursion outright (brief-port.md,
# rule 5), so the sub-call would have to be a def that calls back into the pass.
# `rw_miss()` is the named wall and `rw_none` is its row.
def rw_miss() -> Bool: True{}
def rw_none() -> Bool: rw_miss()

# ===========================================================================
# THE PASS. `ops.bend` cannot call a def in this file and a rule table must be a
# top-level `Data` value because there are no closures, so this file has its own
# `mu_claimed`, its own dispatch and its own scan -- the same ~15 lines
# `uop/spec.bend` writes six times and `schedule/rangeify.bend` writes eleven
# times. There is NO generic dispatch and this file does not try to build one.
#
# THE VERDICT IS A TAG, NOT A NODE, and that is the one departure from
# `movement.bend`'s `Hop`. Not one of multi.py's thirty bodies can intern a node
# (every builder is a `TODO(p3)` in `ops.bend`), so a rule here cannot answer a
# node index and there is nothing for `Hop{ar, at}` to carry. What a scan CAN
# return, and what is a Python fact, is WHICH rule would fire: the first claiming
# entry in table order. `mu_first` is that tag, `0` for "none claimed", and the
# gate reads it for a node two rules claim -- which is the row the brief asks for.
# ===========================================================================
def mu_early.go(+have: List<&2, O.Op>, rej: List<&2, O.Op>) -> Bool:
  match rej:
    case Nil{}: True{}
    case o <> t: mu_and2(O.op_in(have, o), mu_early.go(have, t))

# `early_reject` is a NECESSARY CONDITION despite the name (ops.py:1609 is
# `if not early_reject.issubset(ler): continue`): the rule FIRES when its op set
# IS a subset of the node's src ops, and the empty set is a subset of everything.
def mu_early(+ar: O.Arena, self: U32, rej: List<&2, O.Op>) -> Bool:
  mu_early.go(O.pm_ler(ar, self), rej)

# THE OP-SET CLAIM: `pdict.get(uop.op, [])` membership, i.e. "is the node's op one
# of this pattern's ops". `O.pm_claimed` is ops.bend's own reader of the node.
def mu_claimed(+ar: O.Arena, +self: U32, ops: List<&2, O.Op>, rej: List<&2, O.Op>) -> Bool:
  mu_and2(O.pm_claimed(ops, ar, self), mu_early(ar, self, rej))

# THE SRC TEST, PER TAG. `PMEntry.ops` is `pdict`'s KEY -- the ROOT op and nothing
# else -- so an op-set count alone cannot separate a rule whose pattern also
# tests its srcs. Every tag whose pattern has NO src test answers `True{}` and the
# name says so; the twenty-five entries are read off CPython's own patterns by
# `.agents/slop/multi-rows.py` and are in the gate as `mtA_*`.
#
# The five shapes are: src[0] is UNSHARD, src[0] is MSTACK, src[0] is a Movement,
# src[0] is an ALU, src[1] is UNSHARD, and "anything".
def mu_src_un.go(has: Bool, +ar: O.Arena, +self: U32, n: U32) -> Bool:
  match has:
    case True{} : O.src_op(ar, self, n, O.OpsUNSHARD{})
    case False{}: False{}

# `src[n].op is Ops.UNSHARD`, for the two tags whose first src is UNSHARD and the
# two whose SECOND src is. `O.src_op` is ops.bend's own reader and it is a bare
# value, not a `Maybe`. The `nsrc > n` guard is Python's IndexError.
def mu_src_un(+ar: O.Arena, +self: U32, +n: U32) -> Bool:
  mu_src_un.go(U32.is_gt(O.Arena.nsrc(ar, self), n), ar, self, n)

# `src[0].op is Ops.MSTACK` -- `replace_allreduce`'s rules 2 and 3.
def mu_src_ms(+ar: O.Arena, +self: U32) -> Bool:
  O.src_op(ar, self, 0, O.OpsMSTACK{})

# `isinstance` membership on the NODE'S OP, for the two GroupOp src tests (the
# ALU arm of the `replace_allreduce` MSELECT rule and the Movement arm). It is
# `O.pm_claimed` with a nil reject set, which is the same function the rule scan
# uses, so there is one membership test in the file.
def mu_src_one(nsrc: U32, n: U32) -> Bool:
  U32.is_eq(nsrc, n)

# THE PER-TAG SRC TEST. It is a dispatch because there are no closures, and the
# twenty-six arms are one line each. The line comment on each arm is the Python
# pattern it comes from.
def mu_src_src.of(tag: U32, unsh0: Bool, unsh1: Bool, ms0: Bool, mov0: Bool, alu0: Bool,
                  ex2: Bool) -> Bool:
  match tag:
    case 1  : ex2
    case 2  : ex2
    case 3  : ex2
    case 4  : ex2
    case 5  : ex2
    case 6  : ex2
    case 7  : ex2
    case 8  : unsh0
    case 9  : unsh0
    case 11 : unsh0
    case 12 : ex2
    case 14 : unsh0
    case 15 : unsh0
    case 16 : ex2
    case 17 : unsh1
    case 18 : unsh0
    case 21 : ms0
    case 22 : ms0
    case 23 : mov0
    case 24 : alu0
    case _: True{}

def mu_src_src(tag: U32, +ar: O.Arena, +self: U32) -> Bool:
  mu_src_src.of(tag, mu_src_un(ar, self, 0), mu_src_un(ar, self, 1), mu_src_ms(ar, self),
                O.pm_claimed(mu_move_ops(), ar, O.Arena.src0(ar, self)),
                O.pm_claimed(mu_alu_ops(), ar, O.Arena.src0(ar, self)),
                mu_src_one(O.Arena.nsrc(ar, self), 1))

# THE DISPATCH. A missing `case` is not an error here, it is a `0` -- "this tag
# has no rule" -- because the table is `Data` and the tag space is dense, so a
# gap would be a port bug rather than a Python one. `mu_dispatch` is the FIRST-WINS
# fold and `mu_claim_n` is the count, and they are two defs over the same table
# because a scan stops at the first answer and a count must not: that difference is
# the only reason a first-wins bug is visible to a gate at all.
def mu_claim.one(ok: Bool, acc: U32) -> U32:
  match ok:
    case True{} : U32.add(acc, 1)
    case False{}: acc

def mu_claim.go(rs: List<&2, O.PMEntry>, +ar: O.Arena, +self: U32, acc: U32) -> U32:
  match rs:
    case Nil{}: acc
    case +e <> +t: mu_claim.go(t, ar, self,
                               mu_claim.one(mu_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)), acc))

# THE OP-SET CLAIM COUNT -- "how many patterns of the table have this node's OP as
# their pdict key", which is a statement about `pdict` and NOT about matching.
# `claim_copy` in the gate is 3 for a COPY and `claim_store` is 2 for a STORE, and
# both are Python's own: a COPY is the key of tags 11, 19(ra_0), 20(ra_1) and a
# STORE of tags 17 and 18.
def mu_claim_n(ts: List<&2, O.PMEntry>, ar: O.Arena, self: U32) -> U32:
  mu_claim.go(ts, ar, self, 0)

# THE FULL CLAIM -- the op set AND that tag's src test. It is what separates the
# two STORE rules (17 wants `src[1]` to be the UNSHARD, 18 wants `src[0]`), and it
# is the second half of the two-rules-one-node row.
def mu_claim_full.go(rs: List<&2, O.PMEntry>, +ar: O.Arena, +self: U32, acc: U32) -> U32:
  match rs:
    case Nil{}: acc
    case +e <> +t: mu_claim_full.go(t, ar, self,
                                    mu_claim.one(mu_and2(mu_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)),
                                                         mu_src_src(O.PMEntry.tag(e), ar, self)), acc))

def mu_claim_full(ts: List<&2, O.PMEntry>, ar: O.Arena, self: U32) -> U32:
  mu_claim_full.go(ts, ar, self, 0)

# THE FIRST CLAIMING TAG -- the rewrite `PatternMatcher.rewrite` would take, as a
# NUMBER, because it is the FIRST non-None and a scan that keeps overwriting is
# last-wins. `0` is "no rule claimed it", which for `multi_pm` with the builders
# unported is ALSO the answer every node gets -- and the two are kept apart:
# `mu_first` is what the TABLE says, and `mu_answers` (below) is what the port can
# actually produce.
# the "keep the earlier tag" test, and it is a leaf so the walk reads `held` once
# per step
def mu_first.take(have: Bool, held: U32, tag: U32) -> U32:
  match have:
    case True{} : held
    case False{}: tag

# only a rule that CLAIMS its tag enters the accumulator at all, so the fold is
# "the first claiming tag", which is `PatternMatcher.rewrite`'s "first non-None"
# with every answer being 0.
# A SENTINEL, NOT 0. Tag 0 IS a real tag (`alu_multi`), so `0` cannot mean "no
# rule claimed it" -- MEASURED, with `0` as the seed the ALU rule's own tag read as
# "nothing found" and `t_first_ad` was 0. 4294967295 is `U32`'s all-ones and it is
# the same convention `sk_at` uses.
def mu_first.go(rs: List<&2, O.PMEntry>, +ar: O.Arena, +self: U32, +held: U32) -> U32:
  match rs:
    case Nil{}: held
    case +e <> +t: mu_first.go(t, ar, self,
                              mu_first.take(Bool.not(mu_and2(U32.is_eq(held, 4294967295),
                                                    mu_claimed(ar, self, O.PMEntry.ops(e), O.PMEntry.rej(e)))),
                                            held, O.PMEntry.tag(e)))

def mu_first(ts: List<&2, O.PMEntry>, ar: O.Arena, self: U32) -> U32:
  mu_first.go(ts, ar, self, 4294967295)

# ===========================================================================
# THE GATE. Every number is CPython's: `.agents/slop/multi-rows.py` runs
# `multi.py`'s own expressions -- the tables' pdict keys and reject sets from
# `UPat.early_reject`, `broadcast_axes`, `_broadcast_shape`, the reduce split,
# the reshape `arg_acc`, `part_bounds`, `tuple.index`, the flip list, the expand
# shift and `LATE_ALLREDUCE`'s tag shift -- and prints them. Nothing here is
# restated from this file.
#
# `1` is True, `0` is False, and a COUNT row prints the count.
# ===========================================================================
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def yes(b: Bool) -> U32:
  match b:
    case True{} : 1
    case False{}: 0

def eq(a: U32, b: U32) -> U32:
  yes(U32.is_eq(a, b))

# the table LENGTHS -- the composition rows. `mt_own_n`, `mt_ra_n`, `mt_ea_n`,
# `mt_pm_n` and `mt_late_n` are `multi.py:281-311` and `multi.py:50` read as
# integers, and they are the rows that say `multi_pm` is nineteen own rules with
# SIX appended and that `LATE_ALLREDUCE` PREPENDS rather than appends.
def mt_n(ts: List<&2, O.PMEntry>) -> U32:
  U32.from_nat(List.length(&2, O.PMEntry, ts))

def mt_tag(ts: List<&2, O.PMEntry>, i: Nat) -> U32:
  O.PMEntry.tag(Maybe.default(&2, O.PMEntry, List.get(&2, O.PMEntry, ts, i), O.PMEntry{999, Nil{}, Nil{}}))

# the TOTAL number of reject-set entries in a table -- a COUNT, and the row for
# the whole reject inventory at once. Every entry's set is empty or a singleton
# (measured: `max(len(rej)) == 1` over all twenty-six), so `mt_rej_n` is also the
# number of rules that HAVE one.
def mt_rej.acc(rs: List<&2, O.PMEntry>, acc: U32) -> U32:
  match rs:
    case Nil{}: acc
    case e <> t: mt_rej.acc(t, U32.add(acc, U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(e)))))

def mt_rej_n(ts: List<&2, O.PMEntry>) -> U32:
  mt_rej.acc(ts, 0)

# THE TOTAL number of op-set entries -- the other COUNT, and the row for the pdict
# key inventory. It is `28 + 25*1` for the ALU set plus twenty-five singletons,
# minus nothing: every other pattern has exactly one op except tag 14 (CALL and
# AFTER) and tag 16 (the five passthrough ops).
def mt_ops.acc(rs: List<&2, O.PMEntry>, acc: U32) -> U32:
  match rs:
    case Nil{}: acc
    case e <> t: mt_ops.acc(t, U32.add(acc, U32.from_nat(List.length(&2, O.Op, O.PMEntry.ops(e)))))

def mt_ops_n(ts: List<&2, O.PMEntry>) -> U32:
  mt_ops.acc(ts, 0)

# ---------------------------------------------------------------------------
# THE FIXTURE. One `Data` record holding the ARENA and the node indices, built in
# a single `+`-chained chain because `Arena` is affine and every intermediate is a
# value. The nodes are the ones the TABLES turn on, not a random graph:
#
#   RD  a DEVICE RANGE over four devices -- the exact node `mu_count` reads
#   M0  UNSHARD of a buffer on axis 0     -- one sharded axis
#   M1  UNSHARD of a buffer on axis 1     -- one sharded axis, different axis
#   MA  UNSHARD on axes 0 AND 1           -- the two-axis case `mu_axis` refuses
#   AD  ADD(M0, M0)                       -- the ALU rule's claim
#   CP  COPY(M0)                          -- a COPY three rules claim
#   CQ  COPY(B8)                          -- a COPY of a WHOLE buffer
#   ST  STORE(B8, M0)                     -- a STORE two rules claim, src1 UNSHARD
#   SU  STORE(M0, M0)                     -- the same, src0 UNSHARD
#   MS  MSELECT(MSTACK(B8,B24))           -- the MSELECT-on-MSTACK rule
#   MS2 MSELECT(ADD(M0,M0))               -- the MSELECT-on-ALU rule
#   MT  MSTACK(MS, MS2)                   -- a Movement src[0] is NOT MSTACK here
# ---------------------------------------------------------------------------
type G is Data:
  G{ar: O.Arena, ix: List<&2, U32>}

def G.ar(g: G) -> O.Arena:
  match g:
    case G{ar, ix}: ar

def G.ix(g: G) -> List<&2, U32>:
  match g:
    case G{ar, ix}: ix

def g_n(g: G, i: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, G.ix(g), i), 0)

def g_psize(slot: U32, n: U32) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), Some{n}, None{}, None{}, None{}, S.AGlobal{}, None{}, False{},
             None{}, None{}, False{}, None{}}

# an UNSHARD's arg is the sharded AXES (ops.py:748), which is `ATuple{ys}`
def g_u(sh: List<&2, U32>) -> O.Arg:
  O.ATuple{sh}

def g_rd(g: G) -> U32: g_n(g, 0n)
def g_b8(g: G) -> U32: g_n(g, 1n)
def g_m0(g: G) -> U32: g_n(g, 3n)
def g_m1(g: G) -> U32: g_n(g, 4n)
def g_ma(g: G) -> U32: g_n(g, 5n)
def g_ad(g: G) -> U32: g_n(g, 6n)
def g_cp(g: G) -> U32: g_n(g, 7n)
def g_cq(g: G) -> U32: g_n(g, 8n)
def g_st(g: G) -> U32: g_n(g, 12n)
def g_su(g: G) -> U32: g_n(g, 13n)
def g_ms(g: G) -> U32: g_n(g, 9n)
def g() -> G:
  +c4 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  +c8 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(8)})
  +c24 = O.UOp.const(O.Found.ar(c8), O.CInt{H.i64_of_i32(24)})
  # UOp.range(len(devices), -1, AxisType.DEVICE) -- multi.py:60's sharding_rng
  +rd = O.UOp.range_end(O.Found.ar(c24), O.Found.i(c4), [4294967295], O.AXIS_DEVICE{})
  +rd2 = O.UOp.range_end(O.Found.ar(rd), O.Found.i(c8), [4294967294], O.AXIS_DEVICE{})
  +b8 = O.UOp.new(O.Found.ar(rd2), O.OpsBUFFER{}, [O.Found.i(c24)],
                  O.AParam{g_psize(0, 8)}, O.TNone{})
  +b24 = O.UOp.new(O.Found.ar(b8), O.OpsBUFFER{}, [O.Found.i(c24)],
                   O.AParam{g_psize(1, 24)}, O.TNone{})
  +m0 = O.UOp.new(O.Found.ar(b24), O.OpsUNSHARD{}, [O.Found.i(b8), O.Found.i(rd)],
                  g_u([0]), O.TNone{})
  +m1 = O.UOp.new(O.Found.ar(m0), O.OpsUNSHARD{}, [O.Found.i(b24), O.Found.i(rd)],
                  g_u([1]), O.TNone{})
  +ma = O.UOp.new(O.Found.ar(m1), O.OpsUNSHARD{}, [O.Found.i(b24), O.Found.i(rd), O.Found.i(rd2)],
                  g_u([0, 1]), O.TNone{})
  +ad = O.UOp.new(O.Found.ar(ma), O.OpsADD{}, [O.Found.i(m0), O.Found.i(m0)],
                  O.ANone{}, O.TNone{})
  +cp = O.UOp.new(O.Found.ar(ad), O.OpsCOPY{}, [O.Found.i(m0)], O.ADev{S.D1{1}}, O.TNone{})
  +cq = O.UOp.new(O.Found.ar(cp), O.OpsCOPY{}, [O.Found.i(b8)], O.ADev{S.D1{1}}, O.TNone{})
  +mst = O.UOp.new(O.Found.ar(cq), O.OpsMSTACK{}, [O.Found.i(b8), O.Found.i(b24)],
                   O.ANone{}, O.TNone{})
  +ms = O.UOp.new(O.Found.ar(mst), O.OpsMSELECT{}, [O.Found.i(mst)], O.APy{O.CInt{H.i64_of_i32(0)}}, O.TNone{})
  +ms2 = O.UOp.new(O.Found.ar(ms), O.OpsMSELECT{}, [O.Found.i(ad)], O.APy{O.CInt{H.i64_of_i32(1)}}, O.TNone{})
  +mt = O.UOp.new(O.Found.ar(ms2), O.OpsMSTACK{}, [O.Found.i(ms), O.Found.i(ms2)],
                  O.ANone{}, O.TNone{})
  +st = O.UOp.new(O.Found.ar(mt), O.OpsSTORE{}, [O.Found.i(b8), O.Found.i(m0)],
                  O.ANone{}, O.TNone{})
  +su = O.UOp.new(O.Found.ar(st), O.OpsSTORE{}, [O.Found.i(m0), O.Found.i(m0)],
                  O.ANone{}, O.TNone{})
  G{O.Found.ar(su),
    [O.Found.i(rd), O.Found.i(b8), O.Found.i(b24), O.Found.i(m0), O.Found.i(m1),
     O.Found.i(ma), O.Found.i(ad), O.Found.i(cp), O.Found.i(cq), O.Found.i(ms),
     O.Found.i(ms2), O.Found.i(mt), O.Found.i(st), O.Found.i(su)]}

# ---------------------------------------------------------------------------
# THE TABLE ROWS. `LATE_ALLREDUCE=1` is the default, so `mu_c_early` is the
# 25-entry table and `mu_c_late` the 26-entry one.
# ---------------------------------------------------------------------------
def t_own_n() -> U32: mt_n(mu_own())
def t_ra_n() -> U32: mt_n(mu_ra_base())
def t_ea_n() -> U32: mt_n([mu_ea0()])
def t_pm_n() -> U32: mt_n(mu_table(mu_c_early()))
def t_late_n() -> U32: mt_n(mu_table(mu_c_late()))

# THE TAG SHIFT. With `LATE_ALLREDUCE` off, `_early_allreduce`'s ALLREDUCE rule is
# tag 19 and `replace_allreduce`'s first COPY rule moves to 20 -- so `t_t19` is
# `ALLREDUCE` with the flag on AND with it off, while `t_t20` is `COPY` on and
# `MSELECT` off. The tag is the op VALUE (`Ops.value`, ops.bend:382), so these are
# numbers and not names, and `t_t20` off is 74+... which is why the row prints the
# tag of the ENTRY rather than comparing two op values here.
def ALLREDUCE() -> U32: O.Ops.value(O.OpsALLREDUCE{})
def COPY() -> U32: O.Ops.value(O.OpsCOPY{})
def MSELECT() -> U32: O.Ops.value(O.OpsMSELECT{})

# THE TAG IS AN INDEX and the ROWS COMPARE THE OP THE TAG CLAIMS, which is the
# Python fact: `pdict`'s key for tag 19 is COPY when `LATE_ALLREDUCE` is on and
# ALLREDUCE when it is off. `mt_tag` (the index itself) is a separate row below.
def mt_op.head.go(os: List<&2, O.Op>) -> U32:
  match os:
    case Nil{}: 4294967295
    case +o <> +_: O.Ops.value(o)

def mt_op.head(os: List<&2, O.Op>) -> U32:
  mt_op.head.go(os)

def mt_op.of(os: List<&2, O.Op>) -> U32:
  mt_op.head(os)

def mt_entry(ts: List<&2, O.PMEntry>, i: Nat) -> O.PMEntry:
  Maybe.default(&2, O.PMEntry, List.get(&2, O.PMEntry, ts, i), O.PMEntry{999, Nil{}, Nil{}})

def mt_op(ts: List<&2, O.PMEntry>, i: Nat) -> U32:
  mt_op.of(O.PMEntry.ops(mt_entry(ts, i)))

def t_t19_on() -> U32: eq(mt_op(mu_table(mu_c_early()), 19n), COPY())
def t_t20_on() -> U32: eq(mt_op(mu_table(mu_c_early()), 20n), COPY())
def t_t19_off() -> U32: eq(mt_op(mu_table(mu_c_late()), 19n), ALLREDUCE())
def t_t24_off() -> U32: eq(mt_op(mu_table(mu_c_late()), 24n), MSELECT())
def t_t25_off() -> U32: eq(mt_op(mu_table(mu_c_late()), 25n), MSELECT())
def t_t20_off() -> U32: eq(mt_op(mu_table(mu_c_late()), 20n), COPY())
def SHRINKV() -> U32: O.Ops.value(O.OpsSHRINK{})
def t_t23_off() -> U32: eq(mt_op(mu_table(mu_c_late()), 23n), SHRINKV())
def t_tag19() -> U32: eq(mt_tag(mu_table(mu_c_early()), 19n), 19)
def t_tag25() -> U32: eq(mt_tag(mu_table(mu_c_late()), 25n), 25)

# THE INVENTORY COUNTS.
def t_rej_n() -> U32: eq(mt_rej_n(mu_table(mu_c_early())), 21)
def t_rej_late() -> U32: eq(mt_rej_n(mu_table(mu_c_late())), 21)
def t_ops_n() -> U32: eq(mt_ops_n(mu_table(mu_c_early())), 57)
def t_alu_n() -> U32: eq(mt_ops_n([O.PMEntry{0, mu_alu_ops(), mu_rej_nil()}]), 28)
def t_pass_n() -> U32: eq(mt_ops_n([O.PMEntry{16, mu_pass_ops(), mu_rej_nil()}]), 5)
def t_mov_n() -> U32: eq(mt_ops_n([O.PMEntry{23, mu_move_ops(), mu_rej_nil()}]), 6)

# ---------------------------------------------------------------------------
# THE CLAIM ROWS -- the brief's two-rules-one-node fixture. `CP` is a COPY, and
# three of the twenty-five patterns have COPY as their pdict key: tag 11 (COPY of
# a sharded value), tag 19 (`lower_broadcast_copy`) and tag 20 (`copy_to_one`).
# Two of them have an EMPTY reject set and no src test at all, so the OP-SET
# CLAIM count is 3.
# `ST` is a STORE whose `src[1]` is the UNSHARD: tags 17 and 18 both key on STORE,
# tag 17 wants `src[1]` UNSHARD and tag 18 wants `src[0]` UNSHARD, and only tag 17
# fires the FULL claim. `SU` is a STORE whose `src[0]` IS the UNSHARD, and both
# fire. That is the discriminating pair and it is why both are rows.
# ---------------------------------------------------------------------------
def t_claim_cp() -> U32: eq(mu_claim_n(mu_table(mu_c_early()), G.ar(g()), g_cp(g())), 3)
# a COPY of a WHOLE buffer is claimed by TWO, not three: tag 11's reject set is
# {UNSHARD} and the node's `ler` is {BUFFER}, so its NECESSARY CONDITION FAILS. That
# is `early_reject` doing its job and `t_claim_cp` (3) against `t_claim_cq` (2) is
# the pair that says so.
def t_claim_cq() -> U32: eq(mu_claim_n(mu_table(mu_c_early()), G.ar(g()), g_cq(g())), 2)
def t_claim_st() -> U32: eq(mu_claim_n(mu_table(mu_c_early()), G.ar(g()), g_st(g())), 2)
def t_claim_su() -> U32: eq(mu_claim_n(mu_table(mu_c_early()), G.ar(g()), g_su(g())), 2)
def t_claim_ad() -> U32: eq(mu_claim_n(mu_table(mu_c_early()), G.ar(g()), g_ad(g())), 1)
def t_claim_ms() -> U32: eq(mu_claim_n(mu_table(mu_c_early()), G.ar(g()), g_ms(g())), 3)

# THE FULL CLAIM: the op set AND that tag's src test. Two rules claim one node and
# they DISAGREE, which is what a first-wins -> conjunction mutation would move.
def t_full_st() -> U32: eq(mu_claim_full(mu_table(mu_c_early()), G.ar(g()), g_st(g())), 1)
def t_full_su() -> U32: eq(mu_claim_full(mu_table(mu_c_early()), G.ar(g()), g_su(g())), 2)
def t_full_cp() -> U32: eq(mu_claim_full(mu_table(mu_c_early()), G.ar(g()), g_cp(g())), 3)
def t_full_ad() -> U32: eq(mu_claim_full(mu_table(mu_c_early()), G.ar(g()), g_ad(g())), 1)

# THE FIRST CLAIMING TAG. `0` means "no rule claimed it" and a non-zero tag is the
# rule a rewrite WOULD take. `AD` (an ADD whose srcs are both UNSHARD) is claimed
# by tag 0 -- the ALU rule -- and by nothing else, because no other pattern keys
# on an ALU op.
# `AD` is an ADD over two UNSHARDs, so tag 0 (`alu_multi`) claims it and nothing
# else does: no other pattern keys on an ALU op. The tag is 0, which is WHY
# `mu_first` needed a sentinel -- 0 is both "tag 0" and "nothing", and with a `0`
# seed this row could not tell them apart.
def t_first_ad() -> U32: eq(mu_first(mu_table(mu_c_early()), G.ar(g()), g_ad(g())), 0)
def t_first_st() -> U32: eq(mu_first(mu_table(mu_c_early()), G.ar(g()), g_st(g())), 17)
def t_first_su() -> U32: eq(mu_first(mu_table(mu_c_early()), G.ar(g()), g_su(g())), 17)
def t_first_m0() -> U32: mu_first(mu_table(mu_c_early()), G.ar(g()), g_m0(g()))

def mu_head_sh(sh: List<&2, Sh>) -> Sh:
  Maybe.default(&2, Sh, List.head(&2, Sh, sh), Sh{0, 0})

def mu_at_sh(sh: List<&2, Sh>, i: Nat) -> Sh:
  Maybe.default(&2, Sh, List.get(&2, Sh, sh, i), Sh{0, 0})

# ---------------------------------------------------------------------------
# THE SHARDING ROWS -- `UOp.sharding` (ops.py:707) and `UOp.axis` (:717-726) read
# off REAL nodes, and `mu_count` is the `_min_max` RANGE arm on a real DEVICE
# range. `sh_ma_ax` is the row that says a TWO-axis UNSHARD has NO axis, because
# `mu_axis` returns `None` there and Python RAISES.
# ---------------------------------------------------------------------------
def t_sh0_n() -> U32: eq(U32.from_nat(mu_nshard(mu_shard.zip(G.ar(g()), g_m0(g())))), 1)
def t_sh1_n() -> U32: eq(U32.from_nat(mu_nshard(mu_shard.zip(G.ar(g()), g_m1(g())))), 1)
def t_sha_n() -> U32: eq(U32.from_nat(mu_nshard(mu_shard.zip(G.ar(g()), g_ma(g())))), 2)
def t_shbuf_n() -> U32: eq(U32.from_nat(mu_nshard(mu_shard.zip(G.ar(g()), g_b8(g())))), 0)
def t_sh0_ax() -> U32: eq(Sh.ax(mu_head_sh(mu_shard.zip(G.ar(g()), g_m0(g())))), 0)
def t_sh1_ax() -> U32: eq(Sh.ax(mu_head_sh(mu_shard.zip(G.ar(g()), g_m1(g())))), 1)
def t_sh0_c() -> U32: eq(Sh.n(mu_head_sh(mu_shard.zip(G.ar(g()), g_m0(g())))), 4)
def t_sha1_ax() -> U32: eq(Sh.ax(mu_at_sh(mu_shard.zip(G.ar(g()), g_ma(g())), 1n)), 1)
def t_sha1_n() -> U32: eq(Sh.n(mu_at_sh(mu_shard.zip(G.ar(g()), g_ma(g())), 1n)), 8)

# `int(rng.vmax)+1` on a real DEVICE RANGE over four devices is 4.
def t_cnt_rd() -> U32: eq(mu_count(G.ar(g()), g_rd(g())), 4)
# and it is 0 -- the wall -- for a node that is not a RANGE.
def t_cnt_b8() -> U32: eq(mu_count(G.ar(g()), g_b8(g())), 0)
# `UOp.axis`: Some(0) for a one-axis UNSHARD, None for a two-axis one (Python
# raises) and None for a non-UNSHARD.
def t_ax_m0() -> U32: eq(mu_head32(mu_axis(G.ar(g()), g_m0(g()))), 0)
def t_ax_ma() -> U32: eq(yes(mu_has_axis(mu_axis(G.ar(g()), g_ma(g())))), 0)
def t_ax_b8() -> U32: eq(yes(mu_has_axis(mu_axis(G.ar(g()), g_b8(g())))), 0)
def t_ax_m1() -> U32: eq(mu_head32(mu_axis(G.ar(g()), g_m1(g()))), 1)

# ---------------------------------------------------------------------------
# `shard_srcs` ROWS. CPython's own `_broadcast_shape`, `broadcast_axes`,
# `src_axis = axis - (len(out_shape) - len(mlb.shape))` and the three-way branch.
# `ss_bcast_bad` and `ss_bcast_23` are the IndexError CASES (ops.py:85) and they
# print the ABSENCE -- 1 means "refused", which is the direction Python raises.
# ---------------------------------------------------------------------------
def s1(n: U32) -> List<&2, U32>: [n]
def s2(a: U32, b: U32) -> List<&2, U32>: [a, b]
def s3(a: U32, b: U32, c: U32) -> List<&2, U32>: [a, b, c]
def nil32() -> List<&2, U32>: Nil{}

# `ss_bcast_*` -- `_broadcast_shape` over the Sint shapes, and it is
# `F.bcast_shape` doing the work, so the row is the fold and not a restatement.
def sh(a: U32) -> List<&2, O.Sint>: [F.sint_of(a)]
def bs2(a: List<&2, O.Sint>, b: List<&2, O.Sint>) -> Maybe<&2, List<&2, O.Sint>>:
  mu_out_shape([a, b])

def bs3(a: List<&2, O.Sint>, b: List<&2, O.Sint>, c: List<&2, O.Sint>) -> Maybe<&2, List<&2, O.Sint>>:
  mu_out_shape([a, b, c])

# the four readers of a `Maybe<List<...>>`, TWO of them because the two element
# types are different: `bs2`/`bs3` answer `List<Sint>` (the shapes) and `mu_baxes`
# answers `List<U32>` (the axis ids). A default of `Nil{}` is "the port does not
# answer" and a refused count of 0 is the IndexError case, so `bsn`/`refu` (the
# absence as a row) is kept separate from `bsn2`/`bslen` (the length).
def defs(m: Maybe<&2, List<&2, O.Sint>>) -> List<&2, O.Sint>:
  Maybe.default(&2, List<&2, O.Sint>, m, Nil{})

def defu(m: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  Maybe.default(&2, List<&2, U32>, m, Nil{})

def slen(xs: List<&2, O.Sint>) -> U32:
  U32.from_nat(List.length(&2, O.Sint, xs))

# `bsn` is 0 FOR A REFUSED SHAPE and the LENGTH otherwise, and the two are separate
# arms because `mu_bs_none` cannot be a `match` subject (it is a call).
def bsn.go(refused: Bool, m: Maybe<&2, List<&2, O.Sint>>) -> U32:
  match refused:
    case True{} : 0
    case False{}: slen(defs(m))

def bsn(+m: Maybe<&2, List<&2, O.Sint>>) -> U32:
  bsn.go(mu_bs_none(m), m)

def bsn2(m: Maybe<&2, List<&2, U32>>) -> U32:
  U32.from_nat(mu_len(defu(m)))

def refu(m: Maybe<&2, List<&2, U32>>) -> U32:
  yes(Maybe.is_none(&2, List<&2, U32>, m))

# `src_axis = axis - (len(out_shape) - len(mlb.shape))` -- the RIGHT-ALIGNMENT.
def t_ss_ax00() -> U32: eq(mu_ss_axis(0, 1n, 1n), 0)
def t_ss_ax11() -> U32: eq(mu_ss_axis(1, 2n, 2n), 1)
# a rank-1 src against a rank-2 out SHIFTS the axis by one: Python ss_ax_1_0 = 0
def t_ss_ax10() -> U32: eq(mu_ss_axis(1, 2n, 1n), 0)
def t_ss_ax22() -> U32: eq(mu_ss_axis(2, 3n, 3n), 2)
def t_ss_ax02() -> U32: eq(mu_ss_axis(0, 3n, 3n), 0)
# and it WRAPS for a src LONGER than the out shape, which Python's `len(out) -
# len(src)` never does -- `broadcast_axes` refuses it and this row says so.
# `Nat.sub` SATURATES at 0 where Python's `len(out) - len(src)` would be negative and
# `broadcast_axes` would raise -- MEASURED, the port answers 0 rather than wrapping.
# `t_bx_bad` is the row that says the CALL refuses it.
def t_ss_axneg() -> U32: eq(mu_ss_axis(0, 1n, 3n), 0)

# `sharding_rng`: devices present -> a DEVICE range over `len(devices[0])`; no
# devices -> the UNSHARD's own `src[1]`.
def t_ss_rng_dev() -> U32: eq(Ss.n(mu_ss_rng(4, 9)), 4)
def t_ss_rng_unsh() -> U32: eq(Ss.n(mu_ss_rng(0, 9)), 9)
def t_ss_rng_src() -> U32: eq(yes(Ss.from_unshard(mu_ss_rng(0, 9))), 1)
def t_ss_rng_src2() -> U32: eq(yes(Ss.from_unshard(mu_ss_rng(4, 9))), 0)
# the assert: no devices AND no UNSHARD.
def t_ss_none() -> U32: eq(yes(mu_ss_none(mu_ss_rng(0, 0))), 1)
def t_ss_not_none() -> U32: eq(yes(mu_ss_none(mu_ss_rng(4, 0))), 0)
def t_ss_same() -> U32: eq(yes(mu_ss_same(s2(1, 1))), 1)
def t_ss_same_bad() -> U32: eq(yes(mu_ss_same(s2(1, 2))), 0)

# `broadcast_axes` -- ten of Python's own. `bx_*` prints the COUNT of the returned
# axes, and `bx_*_a0` prints its FIRST element, because the count alone cannot tell
# `range(nleft)` from `range(nleft) + (0,)`.
# `broadcast_axes` rows. The COUNT is printed and the FIRST element is printed
# separately, because the count alone cannot tell `range(nleft)` from
# `range(nleft) + (0,)` -- and `bx_pad` (a leading axis ADDED) and `bx_exp` (a 1
# EXPANDED) both have count 1, so only the element separates them.
def bx_n(m: Maybe<&2, List<&2, U32>>) -> U32:
  bsn2(m)

def bx_a0(m: Maybe<&2, List<&2, U32>>) -> U32:
  mu_at(defu(m), 0n)

def t_bx_none() -> U32: eq(bx_n(mu_baxes(s2(2, 3), s2(2, 3))), 0)
def t_bx_pad() -> U32: eq(bx_a0(mu_baxes(s1(3), s2(2, 3))), 0)
def t_bx_exp() -> U32: eq(bx_a0(mu_baxes(s2(1, 3), s2(2, 3))), 0)
def t_bx_exp_n() -> U32: eq(bx_n(mu_baxes(s2(1, 3), s2(2, 3))), 1)
def t_bx_both() -> U32: eq(bx_n(mu_baxes(s1(1), s2(2, 3))), 2)
def t_bx_noop() -> U32: eq(bx_n(mu_baxes(s1(2), s2(2, 3))), 1)
def t_bx_scalar() -> U32: eq(bx_n(mu_baxes(nil32(), s2(2, 3))), 2)
def t_bx_1out() -> U32: eq(bx_n(mu_baxes(s1(2), s2(1, 2))), 1)
def t_bx_11() -> U32: eq(bx_n(mu_baxes(s1(1), s1(1))), 0)
def t_bx_1_2() -> U32: eq(bx_a0(mu_baxes(s1(1), s1(2))), 0)
def t_bx_1_2n() -> U32: eq(bx_n(mu_baxes(s1(1), s1(2))), 1)
def t_bx_rank1() -> U32: eq(bx_n(mu_baxes(s1(3), s1(3))), 0)
# `nleft < 0` is Python's RuntimeError and the port's `None{}`.
def t_bx_bad() -> U32: eq(refu(mu_baxes(s2(2, 2), s1(2))), 1)

# THE BRANCH (multi.py:68-75). `ml_kind` is the four-way decision and `ml_*` is
# one row per outcome: COPY THROUGH (0), WHOLE (1), BROADCAST (2), SHARDED (3).
# `ml_src0` is the src with NO axis, which is what makes `ml_whole` fire.
def ml_none() -> Maybe<&2, U32>: None{}
def ml_some(n: U32) -> Maybe<&2, U32>: Some{n}

def t_ml_thru() -> U32: eq(Sk.kind(ml_kind(ml_some(1), 1, s2(2, 3), s2(2, 3), 1)), 0)
def t_ml_whole() -> U32: eq(Sk.kind(ml_kind(ml_none(), 1, nil32(), s2(2, 3), 1)), 1)
def t_ml_bcast() -> U32: eq(Sk.kind(ml_kind(ml_some(2), 1, s1(1), s2(2, 3), 0)), 2)
def t_ml_shard() -> U32: eq(Sk.kind(ml_kind(ml_some(2), 1, s2(2, 3), s2(2, 3), 0)), 3)
# and the src_axis rides out of the same record.
def t_ml_sa() -> U32: eq(Sk.sa(ml_kind(ml_some(2), 0, s2(2, 3), s2(2, 3), 0)), 0)
# `mlb.axis == src_axis` is False for a src with no axis, so a SCALAR never copies
# through -- the row that says `mu_axis_is` on `None` is False.
def t_ml_none_thru() -> U32: eq(yes(ml_through(ml_none(), 0)), 0)
def t_ml_copy() -> U32: eq(yes(ml_needs_copy(ml_some(1))), 1)
def t_ml_nocopy() -> U32: eq(yes(ml_needs_copy(ml_none())), 0)

# ---------------------------------------------------------------------------
# `shard_subview` ROWS -- the shape assert, the EXPAND-of-a-scalar arm and `_shard`'s
# two arithmetic lines (ops.py:751-756).
# ---------------------------------------------------------------------------
def t_sv_eq() -> U32: eq(yes(mu_shape_eq(s2(2, 3), s2(2, 3))), 1)
def t_sv_ne() -> U32: eq(yes(mu_shape_eq(s2(2, 3), s2(2, 4))), 0)
def t_sv_rank() -> U32: eq(yes(mu_shape_eq(s2(2, 3), s1(3))), 0)
def t_sv_sc() -> U32: eq(yes(mu_scalar(nil32())), 1)
def t_sv_nsc() -> U32: eq(yes(mu_scalar(s1(1))), 0)
# the EXPAND arm has TWO conjuncts and both are gateable: an EXPAND of a NON-scalar
# is not this arm, and a non-EXPAND is not this arm.
def t_sv_exp() -> U32: eq(yes(sv_expand(O.OpsEXPAND{}, True{})), 1)
def t_sv_exp_nosc() -> U32: eq(yes(sv_expand(O.OpsEXPAND{}, False{})), 0)
def t_sv_exp_no() -> U32: eq(yes(sv_expand(O.OpsADD{}, True{})), 0)
# `_shard`: the divisibility test and the per-shard extent.
def t_sv_div4() -> U32: eq(yes(sv_div(8, 2)), 1)
def t_sv_div5() -> U32: eq(yes(sv_div(5, 2)), 0)
def t_sv_div0() -> U32: eq(yes(sv_div(8, 0)), 0)
def t_sv_sz8() -> U32: eq(sv_sz(8, 2), 4)
def t_sv_sz6() -> U32: eq(sv_sz(6, 2), 3)
# an UNEVEN dim is Python's "multi axis uneven" raise and the port answers the wall
# marker rather than a truncated extent.
def t_sv_sz5() -> U32: eq(sv_sz(5, 2), 0)
def t_sv_nsh() -> U32: eq(U32.from_nat(sv_nshard(mu_shard.zip(G.ar(g()), g_ma(g())))), 2)
def t_sv_ax0() -> U32: eq(mu_at(sv_axes(mu_shard.zip(G.ar(g()), g_ma(g()))), 0n), 0)
def t_sv_ax1() -> U32: eq(mu_at(sv_axes(mu_shard.zip(G.ar(g()), g_ma(g()))), 1n), 1)
def t_sv_ax_n() -> U32: eq(U32.from_nat(mu_len(sv_axes(mu_shard.zip(G.ar(g()), g_ma(g()))))), 2)

# ---------------------------------------------------------------------------
# `alu_multi` ROWS -- `can_handle` and the resharding precondition.
# ---------------------------------------------------------------------------
def one_sh(ax: U32, n: U32) -> List<&2, Sh>: [Sh{ax, n}]
def two_sh(ax: U32, n: U32, bx: U32, m: U32) -> List<&2, Sh>: [Sh{ax, n}, Sh{bx, m}]

# the sharding EQUALITY compares BOTH the axis and the COUNT, and `al_eq_n` is
# the row for the count: two shardings on the same axis with different device
# counts are NOT the same sharding, and a comparison that looked only at the axis
# would accept them and produce a per-shard ALU over shards of the wrong size.
def t_al_eq() -> U32: eq(yes(al_sh_eq(one_sh(0, 4), one_sh(0, 4))), 1)
def t_al_eq_n() -> U32: eq(yes(al_sh_eq(one_sh(0, 4), one_sh(0, 2))), 0)
def t_al_eq_ax() -> U32: eq(yes(al_sh_eq(one_sh(0, 4), one_sh(1, 4))), 0)
def t_al_eq_len() -> U32: eq(yes(al_sh_eq(one_sh(0, 4), two_sh(0, 4, 1, 4))), 0)
def t_al_eq_two() -> U32: eq(yes(al_sh_eq(two_sh(0, 4, 1, 2), two_sh(0, 4, 1, 2))), 1)

# `can_handle`: a SHARDED src is judged only by its sharding (the guard), a scalar
# and a full-shape value are the other two.
def t_al_sh_ok() -> U32: eq(yes(al_handle(True{}, True{}, False{}, s2(2, 3), s2(2, 3))), 1)
def t_al_sh_no() -> U32: eq(yes(al_handle(True{}, False{}, False{}, s2(2, 3), s2(2, 3))), 0)
# a sharded src whose sharding DIFFERS is refused even though it is neither a
# scalar nor of the target shape.
def t_al_sh_guard() -> U32: eq(yes(al_handle(True{}, False{}, False{}, s1(4), s2(2, 3))), 0)
def t_al_sc() -> U32: eq(yes(al_handle(False{}, True{}, True{}, nil32(), s2(2, 3))), 1)
def t_al_full() -> U32: eq(yes(al_handle(False{}, True{}, False{}, s2(2, 3), s2(2, 3))), 1)
def t_al_neither() -> U32: eq(yes(al_handle(False{}, True{}, False{}, s2(4, 6), s2(2, 3))), 0)
# `if not multis: return None`
def t_al_none0() -> U32: eq(yes(al_none(0n)), 1)
def t_al_none1() -> U32: eq(yes(al_none(1n)), 0)
def t_al_nmultis() -> U32: eq(U32.from_nat(al_nmultis(two_sh(0, 4, 1, 4))), 2)

# ---------------------------------------------------------------------------
# `reduce_multi` ROWS -- the split of the sharding by `num_axes`, the two asserts
# and the `num_axes` REBASE of the remaining axes. `rd_sum_n` is the partition
# row: `len(reduced) + len(remaining) == len(sharding)` ALWAYS, because `<` and
# `>=` are complementary.
# ---------------------------------------------------------------------------
def shrd(sh: List<&2, Sh>, na: U32) -> Rd:
  rd_split(sh, na)

def t_rd_any_empty() -> U32: eq(yes(rd_any(Nil{})), 0)
def t_rd_all_red() -> U32: eq(U32.from_nat(mu_len(Rd.red(shrd(two_sh(0, 4, 1, 4), 1)))), 1)
def t_rd_all_rem() -> U32: eq(U32.from_nat(mu_len(Rd.rem(shrd(two_sh(0, 4, 1, 4), 1)))), 1)
def t_rd_some_red() -> U32: eq(U32.from_nat(mu_len(Rd.red(shrd(two_sh(1, 4, 2, 4), 1)))), 0)
def t_rd_some_rem() -> U32: eq(U32.from_nat(mu_len(Rd.rem(shrd(two_sh(1, 4, 2, 4), 1)))), 2)
def t_rd_none_red() -> U32: eq(U32.from_nat(mu_len(Rd.red(shrd(two_sh(2, 4, 3, 4), 1)))), 0)
def t_rd_two_red() -> U32: eq(U32.from_nat(mu_len(Rd.red(shrd(two_sh(0, 4, 1, 4), 2)))), 2)
def t_rd_zero_red() -> U32: eq(U32.from_nat(mu_len(Rd.red(shrd(two_sh(0, 4, 1, 4), 0)))), 0)
# THE PARTITION: `len(red) + len(rem) == len(sharding)` for every `num_axes`.
def t_rd_sum0() -> U32: eq(U32.add(U32.from_nat(mu_len(Rd.red(shrd(two_sh(0, 4, 1, 4), 0)))),
                                  U32.from_nat(mu_len(Rd.rem(shrd(two_sh(0, 4, 1, 4), 0))))), 2)
def t_rd_sum1() -> U32: eq(U32.add(U32.from_nat(mu_len(Rd.red(shrd(two_sh(0, 4, 1, 4), 1)))),
                                  U32.from_nat(mu_len(Rd.rem(shrd(two_sh(0, 4, 1, 4), 1))))), 2)
def t_rd_sum2() -> U32: eq(U32.add(U32.from_nat(mu_len(Rd.red(shrd(two_sh(0, 4, 1, 4), 2)))),
                                  U32.from_nat(mu_len(Rd.rem(shrd(two_sh(0, 4, 1, 4), 2))))), 2)
# THE REBASE: `new_axes = tuple(ax - num_axes for ax,_ in remaining)`. Printed as
# `ax0.ax1` -- the ELEMENTS and not the list -- because `eq` compares `U32` and a
# list comparison would be a second equality function for the same question.
def rdo0(r: Rd) -> U32: mu_at(Rd.off(r), 0n)
def rdo1(r: Rd) -> U32: mu_at(Rd.off(r), 1n)
def rdo_n(r: Rd) -> U32: U32.from_nat(mu_len(Rd.off(r)))

def t_rd_off0() -> U32: eq(rdo0(shrd(two_sh(0, 4, 1, 4), 0)), 0)
def t_rd_off0b() -> U32: eq(rdo1(shrd(two_sh(0, 4, 1, 4), 0)), 1)
def t_rd_off1() -> U32: eq(rdo0(shrd(two_sh(1, 4, 2, 4), 1)), 0)
def t_rd_off2() -> U32: eq(rdo0(shrd(two_sh(2, 4, 3, 4), 1)), 1)
def t_rd_off2b() -> U32: eq(rdo1(shrd(two_sh(2, 4, 3, 4), 1)), 2)
def t_rd_off3() -> U32: eq(rdo0(shrd(two_sh(1, 4, 4, 4), 3)), 1)
def t_rd_off_n() -> U32: eq(rdo_n(shrd(two_sh(1, 4, 4, 4), 3)), 1)
def t_rd_off_none() -> U32: eq(rdo_n(shrd(two_sh(0, 4, 1, 4), 2)), 0)
# THE TWO ASSERTS. `rd_bad` is the partial-allreduce raise and it needs BOTH a
# reduced axis and a remaining one; `rd_fires` is the full-allreduce arm.
def t_rd_bad() -> U32: eq(yes(rd_bad(shrd(two_sh(0, 4, 1, 4), 1))), 1)
def t_rd_bad_none() -> U32: eq(yes(rd_bad(shrd(two_sh(1, 4, 2, 4), 1))), 0)
def t_rd_bad_all() -> U32: eq(yes(rd_bad(shrd(two_sh(0, 4, 1, 4), 2))), 0)
# a sharding that STRADDLES num_axes is Python's partial-allreduce RAISE, so
# `rd_fires` is 0 and `rd_bad` is 1 -- the pair is the whole of multi.py:113-114.
def t_rd_fires() -> U32: eq(yes(rd_fires(shrd(two_sh(0, 4, 1, 4), 1))), 0)
def t_rd_fires_none() -> U32: eq(yes(rd_fires(shrd(two_sh(1, 4, 2, 4), 1))), 0)
def t_rd_piece() -> U32: eq(yes(rd_any(Rd.red(shrd(two_sh(1, 4, 2, 4), 1)))), 0)

# THE ALLREDUCE_CAST ARM -- three conjuncts and each one is a row, because
# dropping the flag or the dtype test would silently change WHICH dtype is cast.
def t_rd_cast() -> U32: eq(yes(rd_cast(mu_c_early(), O.OpsCAST{}, S.bfloat16())), 1)
def t_rd_cast_half() -> U32: eq(yes(rd_cast(mu_c_early(), O.OpsCAST{}, S.half())), 1)
def t_rd_cast_f32() -> U32: eq(yes(rd_cast(mu_c_early(), O.OpsCAST{}, S.single())), 0)
def t_rd_cast_noop() -> U32: eq(yes(rd_cast(mu_c_early(), O.OpsADD{}, S.bfloat16())), 0)
def t_rd_cast_off() -> U32: eq(yes(rd_cast(mu_c_nocast(), O.OpsCAST{}, S.bfloat16())), 0)

# ---------------------------------------------------------------------------
# `reshape_multi` ROWS -- `arg_acc`, the REVERSED `.index`, and the two raises.
# `rs_*_acc` is the running product and `rs_*_ax` is the new axis;
# `rs_*_ok = 0` is a raise.
# ---------------------------------------------------------------------------
def rsa(xs: List<&2, U32>) -> List<&2, U32>: rs_acc(xs)
def rsa1(xs: List<&2, U32>) -> U32: mu_at(rs_acc(xs), 1n)
def rsa2(xs: List<&2, U32>) -> U32: mu_at(rs_acc(xs), 2n)
def rsa3(xs: List<&2, U32>) -> U32: mu_at(rs_acc(xs), 3n)
def rsa_n(xs: List<&2, U32>) -> U32: U32.from_nat(mu_len(rs_acc(xs)))

def t_rs_acc_n4() -> U32: eq(rsa_n(s2(4, 6)), 3)
def t_rs_acc_n1() -> U32: eq(rsa_n(s1(24)), 2)
def t_rs_acc_n0() -> U32: eq(rsa_n(nil32()), 1)
def t_rs_acc1_4() -> U32: eq(rsa1(s2(4, 6)), 4)
def t_rs_acc2_4() -> U32: eq(rsa2(s2(4, 6)), 24)
# (4,6) -> (2,3,4): the running product passes THROUGH 4 at index 2.
def t_rs_acc3_1() -> U32: eq(rsa1(s3(2, 3, 4)), 2)
def t_rs_acc3_2() -> U32: eq(rsa2(s3(2, 3, 4)), 6)
def t_rs_acc3_3() -> U32: eq(rsa3(s3(2, 3, 4)), 24)

# `target = prod(shape[:ax])` and `target in arg_acc`.
def t_rs_tgt0() -> U32: eq(mu_prod_upto(s2(4, 6), 0n), 1)
def t_rs_tgt1() -> U32: eq(mu_prod_upto(s2(4, 6), 1n), 4)
def t_rs_tgt2() -> U32: eq(mu_prod_upto(s2(4, 6), 2n), 24)
def t_rs_tgt3() -> U32: eq(mu_prod_upto(s3(2, 3, 4), 3n), 24)

# THE RAISES. `rs_same` is (4,6)->(4,6) sharded on 0: target 1, arg_acc
# [1,4,24], reversed index 2, new_ax = 3-2-1 = 0, and 4 % 2 == 0 so it FIRES.
def t_rs_same() -> U32: eq(Rs.ax(rs_axis(rs_acc(s2(4, 6)), 1, 2, s2(4, 6))), 0)
def t_rs_same_ok() -> U32: eq(yes(Rs.ok(rs_axis(rs_acc(s2(4, 6)), 1, 2, s2(4, 6)))), 1)
# `rs_mid` is (4,6)->(2,12): target 4 is NOT in [1,2,24], so Python RAISES.
def t_rs_mid_ok() -> U32: eq(yes(Rs.ok(rs_axis(rs_acc(s2(2, 12)), 4, 2, s2(2, 12)))), 0)
# `rs_head` is (4,6)->(24,) sharded on 0: target 1, acc [1,24], new_ax 0.
def t_rs_head() -> U32: eq(Rs.ax(rs_axis(rs_acc(s1(24)), 1, 2, s1(24))), 0)
# `rs_thr0` is (2,3,4)->(2,3,4) sharded on 2: target 6, acc [1,2,6,24],
# reversed index 1, new_ax = 4-1-1 = 2.
def t_rs_thr0() -> U32: eq(Rs.ax(rs_axis(rs_acc(s3(2, 3, 4)), 6, 2, s3(2, 3, 4))), 2)
def t_rs_thr0_ok() -> U32: eq(yes(Rs.ok(rs_axis(rs_acc(s3(2, 3, 4)), 6, 2, s3(2, 3, 4)))), 1)
# THE SECOND RAISE: the boundary dim 3 is not divisible by count 2.
def t_rs_thr1_ok() -> U32: eq(yes(Rs.ok(rs_axis(rs_acc(s3(2, 3, 4)), 2, 2, s3(2, 3, 4)))), 0)
# `rs_thr1` new_ax is 1 and the boundary dim is 3, so the SAME target with the same
# count is refused -- the row that says the divisibility test is on
# `new_shape[new_ax]` and not on the target.
def t_rs_thr1_ax() -> U32: eq(Rs.ax(rs_axis(rs_acc(s3(2, 3, 4)), 2, 2, s3(2, 3, 4))), 1)
# the first raise: `prod(multi.shape) != prod(new_shape)`.
def t_rs_prod() -> U32: eq(yes(rs_prods(s2(4, 6), s2(4, 6))), 1)
def t_rs_prod_bad() -> U32: eq(yes(rs_prods(s2(4, 6), s2(5, 5))), 0)

# THE REVERSED `.index` -- the "most recent hit" row. `rs_hit_tie` uses
# arg_acc = [1, 2, 2, 6] (a `new_shape` with a dim of 1) so 2 appears twice and the
# REVERSED index takes the LAST one: 2, not 1.
# THE TIE. `arg_acc` for `new_shape = (2, 1, 2)` is `[1, 2, 2, 6]`, so the target 2
# appears TWICE and `.index` on the REVERSED list takes the LAST one: the reversed
# index is 2, not 1. `rs_tie_ax` is the consequence -- the new axis is 4-2-1 = 1 and
# not 2 -- and it is the row that says the search counts from the END.
def t_rs_tie_hit() -> U32: eq(U32.from_nat(mu_head_nat(rs_rev(rs_acc(s3(2, 1, 2)), 2))), 1)
def t_rs_tie_hit_f() -> U32: eq(U32.from_nat(mu_head_nat(rs_rev(rs_acc(s3(2, 1, 2)), 6))), 0)
def t_rs_tie_axb() -> U32: eq(Rs.ax(rs_new_ax(rs_acc(s3(2, 1, 2)), 2)), 2)
def t_rs_tie_ax() -> U32: eq(Rs.ax(rs_new_ax(rs_acc(s3(2, 1, 2)), 2)), 2)
def t_rs_tie_ax0() -> U32: eq(Rs.ax(rs_new_ax(rs_acc(s3(2, 1, 2)), 1)), 0)
def mu_bs_none2(m: Maybe<&2, Nat>) -> Bool:
  Maybe.is_none(&2, Nat, m)

def t_rs_none() -> U32: eq(yes(mu_bs_none2(rs_rev(rs_acc(s2(4, 6)), 7))), 1)

# THE LOCAL SHAPE -- `s // count if a in new_axs else s` (multi.py:139). `Ns`
# carries the three parallel lists and `rs_local` divides a sharded axis and keeps
# an unsharded one.
def ns2(dims: List<&2, U32>, axes: List<&2, U32>, cs: List<&2, U32>) -> Ns:
  Ns{dims, axes, cs}

def t_rs_loc0() -> U32: eq(mu_at(rs_local(ns2(s2(4, 6), s1(0), s1(2))), 0n), 2)
def t_rs_loc1() -> U32: eq(mu_at(rs_local(ns2(s2(4, 6), s1(0), s1(2))), 1n), 6)
def t_rs_loc_both() -> U32: eq(mu_at(rs_local(ns2(s2(4, 6), s2(0, 1), s2(2, 3))), 1n), 2)
def t_rs_loc_n() -> U32: eq(U32.from_nat(mu_len(rs_local(ns2(s2(4, 6), s1(0), s1(2))))), 2)
def t_rs_loc_none() -> U32: eq(mu_at(rs_local(ns2(s2(4, 6), nil32(), nil32())), 0n), 4)
# an UNEVEN sharded dim is the wall marker and NOT a truncated extent.
def t_rs_loc_bad() -> U32: eq(mu_at(rs_local(ns2(s2(4, 5), s1(1), s1(2))), 1n), 0)

# ---------------------------------------------------------------------------
# `expand_multi`, `permute_multi`, `flip_multi`, `pad_multi` ROWS.
# ---------------------------------------------------------------------------
# `shift = len(root.marg)` -- an EXPAND ADDS axes, it does not reshard.
def t_ex0() -> U32: eq(ex_shift(0n), 0)
def t_ex1() -> U32: eq(ex_shift(1n), 1)
def t_ex2() -> U32: eq(ex_shift(2n), 2)
def t_ex3() -> U32: eq(ex_shift(3n), 3)
def t_ex_ax0() -> U32: eq(mu_at(ex_axes(one_sh(0, 4), 1), 0n), 1)
def t_ex_ax2() -> U32: eq(mu_at(ex_axes(one_sh(2, 4), 3), 0n), 5)
def t_ex_axn() -> U32: eq(U32.from_nat(mu_len(ex_axes(two_sh(0, 4, 1, 4), 2))), 2)
def t_ex_rng() -> U32: eq(mu_at(ex_rngs(one_sh(3, 4), ), 0n), 4)

# `tuple(root.marg.index(ax))` -- a SEARCH, so `permute((1,0))` sends axis 0 to 1.
def t_pm_id() -> U32: eq(U32.from_nat(mu_head_nat(pm_index(s2(0, 1), 0))), 0)
def t_pm_id1() -> U32: eq(U32.from_nat(mu_head_nat(pm_index(s2(0, 1), 1))), 1)
def t_pm_sw() -> U32: eq(U32.from_nat(mu_head_nat(pm_index(s2(1, 0), 0))), 1)
def t_pm_sw1() -> U32: eq(U32.from_nat(mu_head_nat(pm_index(s2(1, 0), 1))), 0)
def t_pm_cyc() -> U32: eq(U32.from_nat(mu_head_nat(pm_index(s3(2, 0, 1), 1))), 2)
def t_pm_cyc0() -> U32: eq(U32.from_nat(mu_head_nat(pm_index(s3(2, 0, 1), 0))), 1)
def t_pm_rev() -> U32: eq(U32.from_nat(mu_head_nat(pm_index(s3(2, 1, 0), 2))), 0)
def t_pm_mid() -> U32: eq(U32.from_nat(mu_head_nat(pm_index(s3(0, 2, 1), 2))), 1)
# an axis not IN the permutation is Python's ValueError.
def t_pm_missing() -> U32: eq(yes(mu_bs_none2(pm_index(s2(0, 1), 2))), 1)
def t_pm_of() -> U32: eq(mu_at(pm_of(one_sh(1, 4), s2(1, 0)), 0n), 0)

# `[i for i,x in enumerate(root.marg) if x]` -- the FLIP axis list.
def t_fl_none() -> U32: eq(U32.from_nat(mu_len(fl_of(s2(0, 0)))), 0)
def t_fl_one() -> U32: eq(U32.from_nat(mu_len(fl_of(s2(0, 4)))), 1)
def t_fl_one0() -> U32: eq(mu_at(fl_of(s2(0, 4)), 0n), 1)
def t_fl_two() -> U32: eq(U32.from_nat(mu_len(fl_of(s2(3, 4)))), 2)
def t_fl_two1() -> U32: eq(mu_at(fl_of(s2(3, 4)), 1n), 1)
def t_fl_first() -> U32: eq(mu_at(fl_of(s2(2, 0)), 0n), 0)
def t_fl_all() -> U32: eq(U32.from_nat(mu_len(fl_of(s2(1, 1)))), 2)
def t_fl_mid() -> U32: eq(mu_at(fl_of(s3(0, 1, 0)), 0n), 1)
def t_fl_mid_n() -> U32: eq(U32.from_nat(mu_len(fl_of(s3(0, 1, 0)))), 1)
# THE RAISE -- flipping a SHARDED axis moves data across the shard boundary.
def t_fl_bad() -> U32: eq(yes(fl_bad(two_sh(0, 4, 1, 4), s2(0, 4))), 1)
def t_fl_bad2() -> U32: eq(yes(fl_bad(two_sh(0, 4, 1, 4), s2(1, 4))), 1)
def t_fl_bad_none() -> U32: eq(yes(fl_bad(one_sh(0, 4), s2(0, 4))), 0)

# `pad_multi`'s ASSERT -- `root.marg[ax] == (0, multi.shape[ax])` over the
# sharded axes.
def marg1(s: U32, l: U32) -> List<&2, Bd>: [Bd{s, l}]
def marg2(s: U32, l: U32, t: U32, m: U32) -> List<&2, Bd>: [Bd{s, l}, Bd{t, m}]

def t_pd_ok() -> U32: eq(yes(pd_bad(one_sh(0, 4), marg1(0, 8), s1(8))), 0)
def t_pd_bad_s() -> U32: eq(yes(pd_bad(one_sh(0, 4), marg1(1, 8), s1(8))), 1)
def t_pd_bad_l() -> U32: eq(yes(pd_bad(one_sh(0, 4), marg1(0, 4), s1(8))), 1)
def t_pd_ok2() -> U32: eq(yes(pd_bad(two_sh(0, 4, 1, 4), marg2(0, 8, 0, 24), s2(8, 24))), 0)
def t_pd_bad2() -> U32: eq(yes(pd_bad(two_sh(0, 4, 1, 4), marg2(0, 8, 0, 8), s2(8, 24))), 1)
# the LOCAL PAD -- `(0, local.shape[a])` on a sharded axis, `s` verbatim elsewhere.
def pd_head(ms: List<&2, Bd>) -> Bd:
  Maybe.default(&2, Bd, List.head(&2, Bd, ms), Bd{0, 0})

def pd_at(ms: List<&2, Bd>, i: Nat) -> Bd:
  mu_bd_at(ms, i)

def pd_l0(ms: List<&2, Bd>) -> U32: Bd.l(pd_head(ms))
def pd_s0(ms: List<&2, Bd>) -> U32: Bd.s(pd_head(ms))
def pd_l1(ms: List<&2, Bd>) -> U32: Bd.l(pd_at(ms, 1n))
# axis 0 IS sharded, so the pair becomes `(0, 8)` -- the shard's own extent -- and
# axis 1 is NOT, so it keeps its marg entry verbatim.
def t_pd_one0() -> U32: eq(pd_s0(pd_of(marg2(0, 8, 0, 3), s1(0))), 0)
def t_pd_one1() -> U32: eq(pd_l0(pd_of(marg2(0, 8, 0, 3), s1(0))), 8)
def t_pd_kp1() -> U32: eq(pd_l1(pd_of(marg2(0, 8, 1, 3), Nil{})), 3)
def t_pd_kp0() -> U32: eq(pd_s0(pd_of(marg2(1, 8, 0, 3), nil32())), 1)
def t_pd_kp0b() -> U32: eq(pd_l0(pd_of(marg2(1, 8, 0, 3), nil32())), 8)
def blen(xs: List<&2, Bd>) -> U32:
  U32.from_nat(List.length(&2, Bd, xs))

def t_pd_n() -> U32: eq(blen(pd_of(marg2(0, 8, 0, 3), s1(0))), 2)

# ---------------------------------------------------------------------------
# `shrink_multi` ROWS -- `part_bounds`, the OWN test's length half, the WHOLE test
# and the four-way outcome.
# ---------------------------------------------------------------------------
def pb0(pb: List<&2, Bd>) -> U32: Bd.s(pd_head(pb))
def pbl0(pb: List<&2, Bd>) -> U32: Bd.l(pd_head(pb))
def pbat(pb: List<&2, Bd>, i: Nat) -> U32: Bd.s(mu_bd_at(pb, i))
def pbn(pb: List<&2, Bd>) -> U32: U32.from_nat(List.length(&2, Bd, pb))

# `part_bounds = tuple((i*shard_sz, shard_sz) for i in range(count))` for
# shard_sz 4 over 2, 3, 4 and 1 devices -- all of CPython's own.
def t_pb42_n() -> U32: eq(pbn(sk_pb(4, 2)), 2)
def t_pb42_s0() -> U32: eq(pb0(sk_pb(4, 2)), 0)
def t_pb42_l0() -> U32: eq(pbl0(sk_pb(4, 2)), 4)
def t_pb42_s1() -> U32: eq(pbat(sk_pb(4, 2), 1n), 4)
def t_pb43_n() -> U32: eq(pbn(sk_pb(4, 3)), 3)
def t_pb43_s1() -> U32: eq(pbat(sk_pb(4, 3), 1n), 4)
def t_pb43_s2() -> U32: eq(pbat(sk_pb(4, 3), 2n), 8)
def t_pb62_n() -> U32: eq(pbn(sk_pb(6, 2)), 2)
def t_pb62_l0() -> U32: eq(pbl0(sk_pb(6, 2)), 6)
def t_pb84_n() -> U32: eq(pbn(sk_pb(8, 4)), 4)
def t_pb84_sm() -> U32: eq(pbat(sk_pb(8, 4), 2n), 16)
def t_pb84_sl() -> U32: eq(pbat(sk_pb(8, 4), 3n), 24)
def t_pb41_n() -> U32: eq(pbn(sk_pb(4, 1)), 1)

# `.index((s, l))` -- WHICH PARTITION, and a miss is the wall marker.
def t_sk_at0() -> U32: eq(sk_at(sk_pb(4, 4), Bd{0, 4}), 0)
def t_sk_at2() -> U32: eq(sk_at(sk_pb(4, 4), Bd{8, 4}), 2)
def t_sk_at3() -> U32: eq(sk_at(sk_pb(4, 4), Bd{12, 4}), 3)
# a MISS is the SENTINEL, not 0: index 0 is a real partition. MEASURED, the walk
# returned 0 for a miss while `sk_at0` also returned 0, so the two were
# indistinguishable.
def t_sk_at_miss() -> U32: eq(sk_at(sk_pb(4, 4), Bd{13, 4}), 4294967295)
def t_sk_in() -> U32: eq(yes(sk_in(sk_pb(4, 4), Bd{8, 4})), 1)
def t_sk_in_no() -> U32: eq(yes(sk_in(sk_pb(4, 4), Bd{13, 4})), 0)

# THE OWN TEST's length half -- `l == shard_sz`.
def t_sk_len_ok() -> U32: eq(yes(sk_len_eq(marg1(0, 4), 4, 0n)), 1)
def t_sk_len_no() -> U32: eq(yes(sk_len_eq(marg1(0, 8), 4, 0n)), 0)
# THE WHOLE test -- `(s,l) == (0, multi.shape[ax])`.
def t_sk_w_ok() -> U32: eq(yes(sk_whole_eq(marg1(0, 8), s1(8), 0n)), 1)
def t_sk_w_no() -> U32: eq(yes(sk_whole_eq(marg1(0, 4), s1(8), 0n)), 0)
def t_sk_w_s() -> U32: eq(yes(sk_whole_eq(marg1(1, 8), s1(8), 0n)), 0)

# THE FOUR-WAY OUTCOME: 0 OWN, 1 WHOLE, 2 PARTITION, 3 RAISE.
def t_sk_own() -> U32: eq(sk_kind(True{}, True{}, False{}, True{}, True{}), 0)
def t_sk_whole() -> U32: eq(sk_kind(False{}, True{}, False{}, True{}, True{}), 1)
def t_sk_part() -> U32: eq(sk_kind(False{}, False{}, False{}, True{}, True{}), 2)
def t_sk_raise() -> U32: eq(sk_kind(False{}, False{}, False{}, True{}, False{}), 3)
# THE THREE CONJUNCTS of the raise, one row each -- they are `or`-ed, so each one
# alone is enough to raise and that is what the rows show.
# `len(sharding) != 1` ALONE is the raise, and `t_sk_r_pb` and `t_sk_r_dev` are the
# other two conjuncts. MEASURED, the original `sk_raise2` read the two device/pb
# terms as POSITIVE (`bad_n or (one_dev and in_pb)`) and answered PARTITION for all
# three; every one of these rows was 0 until it was `not`.
def t_sk_r_n() -> U32: eq(sk_kind(False{}, False{}, True{}, True{}, True{}), 3)
def t_sk_r_dev() -> U32: eq(sk_kind(False{}, False{}, False{}, False{}, True{}), 3)
def t_sk_r_pb() -> U32: eq(sk_kind(False{}, False{}, False{}, True{}, False{}), 3)
# the OWN arm SKIPS the raise entirely: a two-axis sharding resolves its own shard
# even though `len(sharding) != 1`.
def t_sk_own2() -> U32: eq(sk_kind(True{}, True{}, True{}, False{}, False{}), 0)
# `remaining.remove((ax, rng))` -- the pair equality, and it compares the COUNT.
def t_sk_keep() -> U32: eq(U32.from_nat(mu_nshard(sk_keep(two_sh(0, 4, 1, 4), one_sh(0, 4)))), 1)
def t_sk_keep0() -> U32: eq(mu_at(sv_axes(sk_keep(two_sh(0, 4, 1, 4), one_sh(0, 4))), 0n), 1)
def t_sk_keep_all() -> U32: eq(U32.from_nat(mu_nshard(sk_keep(two_sh(0, 4, 1, 4), Nil{}))), 2)
def t_sk_keep_n() -> U32: eq(U32.from_nat(mu_nshard(sk_keep(two_sh(0, 4, 1, 4), one_sh(0, 2)))), 2)

# ---------------------------------------------------------------------------
# `stack_multi` ROWS -- the `ax+1` shift and the `axis-1` fallback.
# ---------------------------------------------------------------------------
def t_st_ax0() -> U32: eq(mu_at(st_shift(one_sh(0, 4)), 0n), 1)
def t_st_ax2() -> U32: eq(mu_at(st_shift(one_sh(2, 4)), 0n), 3)
def t_st_n() -> U32: eq(U32.from_nat(mu_len(st_shift(two_sh(0, 4, 1, 4)))), 2)
def t_st_off0() -> U32: eq(st_off(1), 0)
def t_st_off1() -> U32: eq(st_off(2), 1)
# `axis - 1` at axis 0 would WRAP in `U32`, and Python's `root.axis` is 0 there, so
# the guard is `axis > 0` and 0 is the wall.
def t_st_off_nil() -> U32: eq(st_off(0), 0)
def t_st_none() -> U32: eq(yes(st_none(0n)), 1)
def t_st_not_none() -> U32: eq(yes(st_none(2n)), 0)


# ---------------------------------------------------------------------------
# `index_multi` ROWS -- both ownership patterns, and the window is tested TWICE.
# shard_sz 4: contiguous locals are 0..3 and the strided diff must be a multiple.
# ---------------------------------------------------------------------------
def t_ix_c0() -> U32: eq(ix_contig(0, 0, 4), 0)
def t_ix_c1() -> U32: eq(ix_contig(3, 0, 4), 3)
def t_ix_c2() -> U32: eq(ix_contig(4, 1, 4), 0)
def t_ix_c3() -> U32: eq(ix_contig(7, 1, 4), 3)
def t_ix_c_oob() -> U32: eq(yes(ix_in(ix_contig(8, 1, 4), 4)), 0)
def t_ix_c_in() -> U32: eq(yes(ix_in(ix_contig(3, 0, 4), 4)), 1)
def t_ix_c_win0() -> U32: eq(yes(ix_in(0, 4)), 1)
def t_ix_c_win4() -> U32: eq(yes(ix_in(4, 4)), 0)
def t_ix_s0() -> U32: eq(ix_strid(0, 0), 0)
def t_ix_s1() -> U32: eq(ix_strid(1, 0), 1)
def t_ix_s4() -> U32: eq(ix_strid(4, 0), 4)
def t_ix_mod0() -> U32: eq(ix_mod(ix_strid(4, 0), 4), 0)
def t_ix_mod1() -> U32: eq(ix_mod(ix_strid(5, 0), 4), 1)
def t_ix_mod0b() -> U32: eq(ix_mod(ix_strid(12, 0), 4), 0)
def t_ix_ok() -> U32: eq(yes(ix_strid_ok(ix_strid(12, 0), 4)), 1)
def t_ix_bad() -> U32: eq(yes(ix_strid_ok(ix_strid(5, 0), 4)), 0)
def t_ix_div() -> U32: eq(ix_div(ix_strid(12, 0), 4), 3)
def t_ix_div0() -> U32: eq(ix_div(ix_strid(4, 0), 4), 1)
def t_ix_kind_c() -> U32: eq(ix_kind(True{}, False{}, False{}), 0)
def t_ix_kind_s() -> U32: eq(ix_kind(False{}, True{}, True{}), 1)
def t_ix_kind_r() -> U32: eq(ix_kind(False{}, False{}, False{}), 2)
def t_ix_kind_r2() -> U32: eq(ix_kind(False{}, True{}, False{}), 2)
def t_ix_kind0() -> U32: eq(ix_mod(4, 0), 4)
def t_ix_kind00() -> U32: eq(ix_div(4, 0), 0)

# ---------------------------------------------------------------------------
# `copy_multi` / `_shard_idx` ROWS -- the GROUP KEY `idxs[:j] + idxs[j+1:]`, which
# DELETES the j-th index. Deleting is not zeroing, and on a repeated index (which
# is every multi-axis shard) the two differ.
# ---------------------------------------------------------------------------
def cxn(k: List<&2, U32>) -> U32: U32.from_nat(mu_len(k))

def t_cx_j0() -> U32: eq(cxn(cx_key(s2(0, 1), 0n)), 1)
def t_cx_j1() -> U32: eq(cxn(cx_key(s2(0, 1), 1n)), 1)
def t_cx_j2() -> U32: eq(cxn(cx_key(s3(0, 1, 2), 2n)), 2)
def t_cx_j3() -> U32: eq(cxn(cx_key(s3(0, 1, 2), 0n)), 2)
def t_cx_j0b() -> U32: eq(mu_at(cx_key(s2(0, 1), 0n), 0n), 1)
def t_cx_j1b() -> U32: eq(mu_at(cx_key(s2(0, 1), 1n), 0n), 0)
def t_cx_same() -> U32: eq(mu_at(cx_key(s2(3, 3), 0n), 0n), 3)
def t_cx_rep() -> U32: eq(mu_at(cx_key(s2(3, 3), 1n), 0n), 3)
def t_cx_j0n() -> U32: eq(U32.from_nat(cx_key_n(cx_key(s2(0, 1), 0n))), 1)
def t_sx0() -> U32: eq(sx_idx(False{}, 3), 0)
def t_sx1() -> U32: eq(sx_idx(True{}, 3), 3)
def t_sx2() -> U32: eq(sx_idx(True{}, 0), 0)

# ---------------------------------------------------------------------------
# `replace_allreduce`'s rule bodies and the STORE family.
# ---------------------------------------------------------------------------
def t_lb_fires() -> U32: eq(yes(lb_fires(True{}, True{})), 1)
def t_lb_no() -> U32: eq(yes(lb_fires(False{}, True{})), 0)
def t_lb_no2() -> U32: eq(yes(lb_fires(True{}, False{})), 0)
def t_lb_reps() -> U32: eq(lb_reps(4), 4)
def t_lb_none() -> U32: eq(yes(lb_none(True{})), 1)
def t_lb_not_none() -> U32: eq(yes(lb_none(False{})), 0)
def t_co_fires() -> U32: eq(yes(co_fires(True{}, True{})), 1)
def t_co_no() -> U32: eq(yes(co_fires(False{}, True{})), 0)
def t_co_same() -> U32: eq(yes(co_same(True{})), 1)
def t_co_copy() -> U32: eq(yes(co_same(False{})), 0)
# `mstack.src[ms.arg]` -- the INDEX and its bounds test.
def t_ms_arg() -> U32: eq(ms_arg(1, 4), 1)
def t_ms_arg_bad() -> U32: eq(ms_arg(4, 4), 0)
def t_ms_ok() -> U32: eq(yes(ms_arg_ok(3, 4)), 1)
# the MSELECT arms: movement is UNCONDITIONAL, ALU is device-gated.
# the MOVEMENT arm is UNCONDITIONAL (`v.replace(src=(s.mselect(ms.arg),)+...)`) and
# the ALU arm is device-gated, so `mv_pick` is the ALU arm's test and the movement
# arm's is `mv_all`. 1 is "the MSELECT moved inside".
def t_mv() -> U32: eq(yes(mv_all(True{})), 1)
def t_mv_alu() -> U32: eq(mv_pick(True{}), 1)
def t_mv_alu_no() -> U32: eq(mv_pick(False{}), 0)
# the STORE family -- 0 PEEL, 1 SUB-VIEW, 2 WHOLE.
def t_stp_peel() -> U32: eq(st_pick(True{}, True{}), 0)
def t_stp_view() -> U32: eq(st_pick(False{}, True{}), 1)
def t_stp_whole() -> U32: eq(st_pick(False{}, False{}), 2)
# `rewrite_into_function` is the recursion wall.
def t_rw() -> U32: eq(yes(rw_none()), 1)




def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- row("t_own_n", t_own_n())
    _ : Unit <- row("t_ra_n", t_ra_n())
    _ : Unit <- row("t_ea_n", t_ea_n())
    _ : Unit <- row("t_pm_n", t_pm_n())
    _ : Unit <- row("t_late_n", t_late_n())
    _ : Unit <- row("t_t19_on", t_t19_on())
    _ : Unit <- row("t_t20_on", t_t20_on())
    _ : Unit <- row("t_t19_off", t_t19_off())
    _ : Unit <- row("t_t24_off", t_t24_off())
    _ : Unit <- row("t_t25_off", t_t25_off())
    _ : Unit <- row("t_t20_off", t_t20_off())
    _ : Unit <- row("t_t23_off", t_t23_off())
    _ : Unit <- row("t_tag19", t_tag19())
    _ : Unit <- row("t_tag25", t_tag25())
    _ : Unit <- row("t_rej_n", t_rej_n())
    _ : Unit <- row("t_rej_late", t_rej_late())
    _ : Unit <- row("t_ops_n", t_ops_n())
    _ : Unit <- row("t_alu_n", t_alu_n())
    _ : Unit <- row("t_pass_n", t_pass_n())
    _ : Unit <- row("t_mov_n", t_mov_n())
    _ : Unit <- row("t_claim_cp", t_claim_cp())
    _ : Unit <- row("t_claim_cq", t_claim_cq())
    _ : Unit <- row("t_claim_st", t_claim_st())
    _ : Unit <- row("t_claim_su", t_claim_su())
    _ : Unit <- row("t_claim_ad", t_claim_ad())
    _ : Unit <- row("t_claim_ms", t_claim_ms())
    _ : Unit <- row("t_full_st", t_full_st())
    _ : Unit <- row("t_full_su", t_full_su())
    _ : Unit <- row("t_full_cp", t_full_cp())
    _ : Unit <- row("t_full_ad", t_full_ad())
    _ : Unit <- row("t_first_ad", t_first_ad())
    _ : Unit <- row("t_first_st", t_first_st())
    _ : Unit <- row("t_first_su", t_first_su())
    _ : Unit <- row("t_first_m0", t_first_m0())
    _ : Unit <- row("t_sh0_n", t_sh0_n())
    _ : Unit <- row("t_sh1_n", t_sh1_n())
    _ : Unit <- row("t_sha_n", t_sha_n())
    _ : Unit <- row("t_shbuf_n", t_shbuf_n())
    _ : Unit <- row("t_sh0_ax", t_sh0_ax())
    _ : Unit <- row("t_sh1_ax", t_sh1_ax())
    _ : Unit <- row("t_sh0_c", t_sh0_c())
    _ : Unit <- row("t_sha1_ax", t_sha1_ax())
    _ : Unit <- row("t_sha1_n", t_sha1_n())
    _ : Unit <- row("t_cnt_rd", t_cnt_rd())
    _ : Unit <- row("t_cnt_b8", t_cnt_b8())
    _ : Unit <- row("t_ax_m0", t_ax_m0())
    _ : Unit <- row("t_ax_ma", t_ax_ma())
    _ : Unit <- row("t_ax_b8", t_ax_b8())
    _ : Unit <- row("t_ax_m1", t_ax_m1())
    _ : Unit <- row("t_ss_ax00", t_ss_ax00())
    _ : Unit <- row("t_ss_ax11", t_ss_ax11())
    _ : Unit <- row("t_ss_ax10", t_ss_ax10())
    _ : Unit <- row("t_ss_ax22", t_ss_ax22())
    _ : Unit <- row("t_ss_ax02", t_ss_ax02())
    _ : Unit <- row("t_ss_axneg", t_ss_axneg())
    _ : Unit <- row("t_ss_rng_dev", t_ss_rng_dev())
    _ : Unit <- row("t_ss_rng_unsh", t_ss_rng_unsh())
    _ : Unit <- row("t_ss_rng_src", t_ss_rng_src())
    _ : Unit <- row("t_ss_rng_src2", t_ss_rng_src2())
    _ : Unit <- row("t_ss_none", t_ss_none())
    _ : Unit <- row("t_ss_not_none", t_ss_not_none())
    _ : Unit <- row("t_ss_same", t_ss_same())
    _ : Unit <- row("t_ss_same_bad", t_ss_same_bad())
    _ : Unit <- row("t_bx_none", t_bx_none())
    _ : Unit <- row("t_bx_pad", t_bx_pad())
    _ : Unit <- row("t_bx_exp", t_bx_exp())
    _ : Unit <- row("t_bx_exp_n", t_bx_exp_n())
    _ : Unit <- row("t_bx_both", t_bx_both())
    _ : Unit <- row("t_bx_noop", t_bx_noop())
    _ : Unit <- row("t_bx_scalar", t_bx_scalar())
    _ : Unit <- row("t_bx_1out", t_bx_1out())
    _ : Unit <- row("t_bx_11", t_bx_11())
    _ : Unit <- row("t_bx_1_2", t_bx_1_2())
    _ : Unit <- row("t_bx_1_2n", t_bx_1_2n())
    _ : Unit <- row("t_bx_rank1", t_bx_rank1())
    _ : Unit <- row("t_bx_bad", t_bx_bad())
    _ : Unit <- row("t_ml_thru", t_ml_thru())
    _ : Unit <- row("t_ml_whole", t_ml_whole())
    _ : Unit <- row("t_ml_bcast", t_ml_bcast())
    _ : Unit <- row("t_ml_shard", t_ml_shard())
    _ : Unit <- row("t_ml_sa", t_ml_sa())
    _ : Unit <- row("t_ml_none_thru", t_ml_none_thru())
    _ : Unit <- row("t_ml_copy", t_ml_copy())
    _ : Unit <- row("t_ml_nocopy", t_ml_nocopy())
    _ : Unit <- row("t_sv_eq", t_sv_eq())
    _ : Unit <- row("t_sv_ne", t_sv_ne())
    _ : Unit <- row("t_sv_rank", t_sv_rank())
    _ : Unit <- row("t_sv_sc", t_sv_sc())
    _ : Unit <- row("t_sv_nsc", t_sv_nsc())
    _ : Unit <- row("t_sv_exp", t_sv_exp())
    _ : Unit <- row("t_sv_exp_nosc", t_sv_exp_nosc())
    _ : Unit <- row("t_sv_exp_no", t_sv_exp_no())
    _ : Unit <- row("t_sv_div4", t_sv_div4())
    _ : Unit <- row("t_sv_div5", t_sv_div5())
    _ : Unit <- row("t_sv_div0", t_sv_div0())
    _ : Unit <- row("t_sv_sz8", t_sv_sz8())
    _ : Unit <- row("t_sv_sz6", t_sv_sz6())
    _ : Unit <- row("t_sv_sz5", t_sv_sz5())
    _ : Unit <- row("t_sv_nsh", t_sv_nsh())
    _ : Unit <- row("t_sv_ax0", t_sv_ax0())
    _ : Unit <- row("t_sv_ax1", t_sv_ax1())
    _ : Unit <- row("t_sv_ax_n", t_sv_ax_n())
    _ : Unit <- row("t_al_eq", t_al_eq())
    _ : Unit <- row("t_al_eq_n", t_al_eq_n())
    _ : Unit <- row("t_al_eq_ax", t_al_eq_ax())
    _ : Unit <- row("t_al_eq_len", t_al_eq_len())
    _ : Unit <- row("t_al_eq_two", t_al_eq_two())
    _ : Unit <- row("t_al_sh_ok", t_al_sh_ok())
    _ : Unit <- row("t_al_sh_no", t_al_sh_no())
    _ : Unit <- row("t_al_sh_guard", t_al_sh_guard())
    _ : Unit <- row("t_al_sc", t_al_sc())
    _ : Unit <- row("t_al_full", t_al_full())
    _ : Unit <- row("t_al_neither", t_al_neither())
    _ : Unit <- row("t_al_none0", t_al_none0())
    _ : Unit <- row("t_al_none1", t_al_none1())
    _ : Unit <- row("t_al_nmultis", t_al_nmultis())
    _ : Unit <- row("t_rd_any_empty", t_rd_any_empty())
    _ : Unit <- row("t_rd_all_red", t_rd_all_red())
    _ : Unit <- row("t_rd_all_rem", t_rd_all_rem())
    _ : Unit <- row("t_rd_some_red", t_rd_some_red())
    _ : Unit <- row("t_rd_some_rem", t_rd_some_rem())
    _ : Unit <- row("t_rd_none_red", t_rd_none_red())
    _ : Unit <- row("t_rd_two_red", t_rd_two_red())
    _ : Unit <- row("t_rd_zero_red", t_rd_zero_red())
    _ : Unit <- row("t_rd_sum0", t_rd_sum0())
    _ : Unit <- row("t_rd_sum1", t_rd_sum1())
    _ : Unit <- row("t_rd_sum2", t_rd_sum2())
    _ : Unit <- row("t_rd_off0", t_rd_off0())
    _ : Unit <- row("t_rd_off0b", t_rd_off0b())
    _ : Unit <- row("t_rd_off1", t_rd_off1())
    _ : Unit <- row("t_rd_off2", t_rd_off2())
    _ : Unit <- row("t_rd_off2b", t_rd_off2b())
    _ : Unit <- row("t_rd_off3", t_rd_off3())
    _ : Unit <- row("t_rd_off_n", t_rd_off_n())
    _ : Unit <- row("t_rd_off_none", t_rd_off_none())
    _ : Unit <- row("t_rd_bad", t_rd_bad())
    _ : Unit <- row("t_rd_bad_none", t_rd_bad_none())
    _ : Unit <- row("t_rd_bad_all", t_rd_bad_all())
    _ : Unit <- row("t_rd_fires", t_rd_fires())
    _ : Unit <- row("t_rd_fires_none", t_rd_fires_none())
    _ : Unit <- row("t_rd_piece", t_rd_piece())
    _ : Unit <- row("t_rd_cast", t_rd_cast())
    _ : Unit <- row("t_rd_cast_half", t_rd_cast_half())
    _ : Unit <- row("t_rd_cast_f32", t_rd_cast_f32())
    _ : Unit <- row("t_rd_cast_noop", t_rd_cast_noop())
    _ : Unit <- row("t_rd_cast_off", t_rd_cast_off())
    _ : Unit <- row("t_rs_acc_n4", t_rs_acc_n4())
    _ : Unit <- row("t_rs_acc_n1", t_rs_acc_n1())
    _ : Unit <- row("t_rs_acc_n0", t_rs_acc_n0())
    _ : Unit <- row("t_rs_acc1_4", t_rs_acc1_4())
    _ : Unit <- row("t_rs_acc2_4", t_rs_acc2_4())
    _ : Unit <- row("t_rs_acc3_1", t_rs_acc3_1())
    _ : Unit <- row("t_rs_acc3_2", t_rs_acc3_2())
    _ : Unit <- row("t_rs_acc3_3", t_rs_acc3_3())
    _ : Unit <- row("t_rs_tgt0", t_rs_tgt0())
    _ : Unit <- row("t_rs_tgt1", t_rs_tgt1())
    _ : Unit <- row("t_rs_tgt2", t_rs_tgt2())
    _ : Unit <- row("t_rs_tgt3", t_rs_tgt3())
    _ : Unit <- row("t_rs_same", t_rs_same())
    _ : Unit <- row("t_rs_same_ok", t_rs_same_ok())
    _ : Unit <- row("t_rs_mid_ok", t_rs_mid_ok())
    _ : Unit <- row("t_rs_head", t_rs_head())
    _ : Unit <- row("t_rs_thr0", t_rs_thr0())
    _ : Unit <- row("t_rs_thr0_ok", t_rs_thr0_ok())
    _ : Unit <- row("t_rs_thr1_ok", t_rs_thr1_ok())
    _ : Unit <- row("t_rs_thr1_ax", t_rs_thr1_ax())
    _ : Unit <- row("t_rs_prod", t_rs_prod())
    _ : Unit <- row("t_rs_prod_bad", t_rs_prod_bad())
    _ : Unit <- row("t_rs_tie_hit", t_rs_tie_hit())
    _ : Unit <- row("t_rs_tie_hit_f", t_rs_tie_hit_f())
    _ : Unit <- row("t_rs_tie_axb", t_rs_tie_axb())
    _ : Unit <- row("t_rs_tie_ax", t_rs_tie_ax())
    _ : Unit <- row("t_rs_tie_ax0", t_rs_tie_ax0())
    _ : Unit <- row("t_rs_none", t_rs_none())
    _ : Unit <- row("t_rs_loc0", t_rs_loc0())
    _ : Unit <- row("t_rs_loc1", t_rs_loc1())
    _ : Unit <- row("t_rs_loc_both", t_rs_loc_both())
    _ : Unit <- row("t_rs_loc_n", t_rs_loc_n())
    _ : Unit <- row("t_rs_loc_none", t_rs_loc_none())
    _ : Unit <- row("t_rs_loc_bad", t_rs_loc_bad())
    _ : Unit <- row("t_ex0", t_ex0())
    _ : Unit <- row("t_ex1", t_ex1())
    _ : Unit <- row("t_ex2", t_ex2())
    _ : Unit <- row("t_ex3", t_ex3())
    _ : Unit <- row("t_ex_ax0", t_ex_ax0())
    _ : Unit <- row("t_ex_ax2", t_ex_ax2())
    _ : Unit <- row("t_ex_axn", t_ex_axn())
    _ : Unit <- row("t_ex_rng", t_ex_rng())
    _ : Unit <- row("t_pm_id", t_pm_id())
    _ : Unit <- row("t_pm_id1", t_pm_id1())
    _ : Unit <- row("t_pm_sw", t_pm_sw())
    _ : Unit <- row("t_pm_sw1", t_pm_sw1())
    _ : Unit <- row("t_pm_cyc", t_pm_cyc())
    _ : Unit <- row("t_pm_cyc0", t_pm_cyc0())
    _ : Unit <- row("t_pm_rev", t_pm_rev())
    _ : Unit <- row("t_pm_mid", t_pm_mid())
    _ : Unit <- row("t_pm_missing", t_pm_missing())
    _ : Unit <- row("t_pm_of", t_pm_of())
    _ : Unit <- row("t_fl_none", t_fl_none())
    _ : Unit <- row("t_fl_one", t_fl_one())
    _ : Unit <- row("t_fl_one0", t_fl_one0())
    _ : Unit <- row("t_fl_two", t_fl_two())
    _ : Unit <- row("t_fl_two1", t_fl_two1())
    _ : Unit <- row("t_fl_first", t_fl_first())
    _ : Unit <- row("t_fl_all", t_fl_all())
    _ : Unit <- row("t_fl_mid", t_fl_mid())
    _ : Unit <- row("t_fl_mid_n", t_fl_mid_n())
    _ : Unit <- row("t_fl_bad", t_fl_bad())
    _ : Unit <- row("t_fl_bad2", t_fl_bad2())
    _ : Unit <- row("t_fl_bad_none", t_fl_bad_none())
    _ : Unit <- row("t_pd_ok", t_pd_ok())
    _ : Unit <- row("t_pd_bad_s", t_pd_bad_s())
    _ : Unit <- row("t_pd_bad_l", t_pd_bad_l())
    _ : Unit <- row("t_pd_ok2", t_pd_ok2())
    _ : Unit <- row("t_pd_bad2", t_pd_bad2())
    _ : Unit <- row("t_pd_one0", t_pd_one0())
    _ : Unit <- row("t_pd_one1", t_pd_one1())
    _ : Unit <- row("t_pd_kp1", t_pd_kp1())
    _ : Unit <- row("t_pd_kp0", t_pd_kp0())
    _ : Unit <- row("t_pd_kp0b", t_pd_kp0b())
    _ : Unit <- row("t_pd_n", t_pd_n())
    _ : Unit <- row("t_pb42_n", t_pb42_n())
    _ : Unit <- row("t_pb42_s0", t_pb42_s0())
    _ : Unit <- row("t_pb42_l0", t_pb42_l0())
    _ : Unit <- row("t_pb42_s1", t_pb42_s1())
    _ : Unit <- row("t_pb43_n", t_pb43_n())
    _ : Unit <- row("t_pb43_s1", t_pb43_s1())
    _ : Unit <- row("t_pb43_s2", t_pb43_s2())
    _ : Unit <- row("t_pb62_n", t_pb62_n())
    _ : Unit <- row("t_pb62_l0", t_pb62_l0())
    _ : Unit <- row("t_pb84_n", t_pb84_n())
    _ : Unit <- row("t_pb84_sm", t_pb84_sm())
    _ : Unit <- row("t_pb84_sl", t_pb84_sl())
    _ : Unit <- row("t_pb41_n", t_pb41_n())
    _ : Unit <- row("t_sk_at0", t_sk_at0())
    _ : Unit <- row("t_sk_at2", t_sk_at2())
    _ : Unit <- row("t_sk_at3", t_sk_at3())
    _ : Unit <- row("t_sk_at_miss", t_sk_at_miss())
    _ : Unit <- row("t_sk_in", t_sk_in())
    _ : Unit <- row("t_sk_in_no", t_sk_in_no())
    _ : Unit <- row("t_sk_len_ok", t_sk_len_ok())
    _ : Unit <- row("t_sk_len_no", t_sk_len_no())
    _ : Unit <- row("t_sk_w_ok", t_sk_w_ok())
    _ : Unit <- row("t_sk_w_no", t_sk_w_no())
    _ : Unit <- row("t_sk_w_s", t_sk_w_s())
    _ : Unit <- row("t_sk_own", t_sk_own())
    _ : Unit <- row("t_sk_whole", t_sk_whole())
    _ : Unit <- row("t_sk_part", t_sk_part())
    _ : Unit <- row("t_sk_raise", t_sk_raise())
    _ : Unit <- row("t_sk_r_n", t_sk_r_n())
    _ : Unit <- row("t_sk_r_dev", t_sk_r_dev())
    _ : Unit <- row("t_sk_r_pb", t_sk_r_pb())
    _ : Unit <- row("t_sk_own2", t_sk_own2())
    _ : Unit <- row("t_sk_keep", t_sk_keep())
    _ : Unit <- row("t_sk_keep0", t_sk_keep0())
    _ : Unit <- row("t_sk_keep_all", t_sk_keep_all())
    _ : Unit <- row("t_sk_keep_n", t_sk_keep_n())
    _ : Unit <- row("t_st_ax0", t_st_ax0())
    _ : Unit <- row("t_st_ax2", t_st_ax2())
    _ : Unit <- row("t_st_n", t_st_n())
    _ : Unit <- row("t_st_off0", t_st_off0())
    _ : Unit <- row("t_st_off1", t_st_off1())
    _ : Unit <- row("t_st_off_nil", t_st_off_nil())
    _ : Unit <- row("t_st_none", t_st_none())
    _ : Unit <- row("t_st_not_none", t_st_not_none())
    _ : Unit <- row("t_ix_c0", t_ix_c0())
    _ : Unit <- row("t_ix_c1", t_ix_c1())
    _ : Unit <- row("t_ix_c2", t_ix_c2())
    _ : Unit <- row("t_ix_c3", t_ix_c3())
    _ : Unit <- row("t_ix_c_oob", t_ix_c_oob())
    _ : Unit <- row("t_ix_c_in", t_ix_c_in())
    _ : Unit <- row("t_ix_c_win0", t_ix_c_win0())
    _ : Unit <- row("t_ix_c_win4", t_ix_c_win4())
    _ : Unit <- row("t_ix_s0", t_ix_s0())
    _ : Unit <- row("t_ix_s1", t_ix_s1())
    _ : Unit <- row("t_ix_s4", t_ix_s4())
    _ : Unit <- row("t_ix_mod0", t_ix_mod0())
    _ : Unit <- row("t_ix_mod1", t_ix_mod1())
    _ : Unit <- row("t_ix_mod0b", t_ix_mod0b())
    _ : Unit <- row("t_ix_ok", t_ix_ok())
    _ : Unit <- row("t_ix_bad", t_ix_bad())
    _ : Unit <- row("t_ix_div", t_ix_div())
    _ : Unit <- row("t_ix_div0", t_ix_div0())
    _ : Unit <- row("t_ix_kind_c", t_ix_kind_c())
    _ : Unit <- row("t_ix_kind_s", t_ix_kind_s())
    _ : Unit <- row("t_ix_kind_r", t_ix_kind_r())
    _ : Unit <- row("t_ix_kind_r2", t_ix_kind_r2())
    _ : Unit <- row("t_ix_kind0", t_ix_kind0())
    _ : Unit <- row("t_ix_kind00", t_ix_kind00())
    _ : Unit <- row("t_cx_j0", t_cx_j0())
    _ : Unit <- row("t_cx_j1", t_cx_j1())
    _ : Unit <- row("t_cx_j2", t_cx_j2())
    _ : Unit <- row("t_cx_j3", t_cx_j3())
    _ : Unit <- row("t_cx_j0b", t_cx_j0b())
    _ : Unit <- row("t_cx_j1b", t_cx_j1b())
    _ : Unit <- row("t_cx_same", t_cx_same())
    _ : Unit <- row("t_cx_rep", t_cx_rep())
    _ : Unit <- row("t_cx_j0n", t_cx_j0n())
    _ : Unit <- row("t_sx0", t_sx0())
    _ : Unit <- row("t_sx1", t_sx1())
    _ : Unit <- row("t_sx2", t_sx2())
    _ : Unit <- row("t_lb_fires", t_lb_fires())
    _ : Unit <- row("t_lb_no", t_lb_no())
    _ : Unit <- row("t_lb_no2", t_lb_no2())
    _ : Unit <- row("t_lb_reps", t_lb_reps())
    _ : Unit <- row("t_lb_none", t_lb_none())
    _ : Unit <- row("t_lb_not_none", t_lb_not_none())
    _ : Unit <- row("t_co_fires", t_co_fires())
    _ : Unit <- row("t_co_no", t_co_no())
    _ : Unit <- row("t_co_same", t_co_same())
    _ : Unit <- row("t_co_copy", t_co_copy())
    _ : Unit <- row("t_ms_arg", t_ms_arg())
    _ : Unit <- row("t_ms_arg_bad", t_ms_arg_bad())
    _ : Unit <- row("t_ms_ok", t_ms_ok())
    _ : Unit <- row("t_mv", t_mv())
    _ : Unit <- row("t_mv_alu", t_mv_alu())
    _ : Unit <- row("t_mv_alu_no", t_mv_alu_no())
    _ : Unit <- row("t_stp_peel", t_stp_peel())
    _ : Unit <- row("t_stp_view", t_stp_view())
    _ : Unit <- row("t_stp_whole", t_stp_whole())
    _ : Unit <- row("t_rw", t_rw())
    IO.print("")
    IO.print("")

# ===========================================================================
# THE MUTATION TABLE.
#
# WHY IT IS HERE. 321 rows that all read 1 prove the rows are non-degenerate;
# they do not prove they WATCH anything. Each row below is a change to ONE
# decision this file makes, run through the whole gate, and the count is how
# many rows answered differently. Two properties are wanted and both are
# measured: no mutation may leave the file uncompilable (a mutation that fails
# to build says nothing about the gate, so every one of these changes a DECISION
# and not a type), and no mutation may be invisible (a row-shape hole).
#
# Driven by `.agents/slop/multi-mutate.py`, which reverts the file after every
# one. Baseline is the interpreted lane; the native lane was diffed clean against
# it, so every count below holds in both.
#
#   id    def               mutation                                  rows
#   ----  ----------------  -----------------------------------------  ----
#   M01   rs_local.one.of   drop the sharding test: divide EVERY axis     2
#   M02   pi_step           tuple.index first-wins -> last-wins           2
#   M03   mu_ss_axis        drop the RIGHT-ALIGNMENT shift               1
#   M04   ml_kind.rest      WHOLE answers BCAST: never copy_multi         1
#   M05   ix_div            strided pattern divides by the residue       3
#   M06   mu_claimed        drop the necessary condition                 1
#   M07   rd_low_dt         drop `half` from the (bfloat16, half) pair    1
#   M08   st_off.of         drop the axis > 0 guard: U32.sub WRAPS       1
#   M09   mu_baxes          len(out) >= len(src) -> >                     2
#   M10   mu_ra_cfg.go      swap the LATE_ALLREDUCE tag shift 19 <-> 20   3
#   M11   mu_exp_keep       drop the out[nleft+i] != 1 conjunct          1
#   M12   fl_of.put         the non-zero filter keeps the ZERO indices     8
#
# THE ROWS EACH ONE MOVED, which is the part that names the coverage:
#
#   M01  t_rs_loc1 t_rs_loc_none
#   M02  t_pm_cyc0 t_pm_mid
#   M03  t_ss_ax10
#   M04  t_ml_whole
#   M05  t_ix_div t_ix_div0 t_ix_kind00
#   M06  t_claim_cq
#   M07  t_rd_cast_half
#   M08  t_st_off_nil
#   M09  t_bx_1_2n t_bx_exp_n
#   M10  t_full_cp t_tag19 t_tag25
#   M11  t_bx_11
#   M12  t_fl_all t_fl_first t_fl_mid t_fl_mid_n t_fl_none t_fl_one0
#        t_fl_two t_fl_two1
#
# TWELVE OF TWELVE CAUGHT, 25 DISTINCT ROWS. Three of these carry more than the
# arithmetic and are worth naming:
#
# * M06 is the ONLY witness for the conjunctive claim. `t_claim_cq` (2 against
#   `t_claim_cp`'s 3) is the sole row that says `early_reject` is a NECESSARY
#   CONDITION rather than a FILTER, and M06 is what proves it is watched. It is
#   also the mutation `t_full_st`/`t_full_su`/`t_full_cp` were written for --
#   those two rules claim one node and disagree -- but the op-set count catches
#   it first, so the honest statement is that `t_claim_cq` is the witness and the
#   `t_full_*` rows are the second one.
# * M10 moves `t_tag19` and `t_tag25`, the two rows that pin the table's COMPOSITION
#   rather than a decision inside one rule. It is the cheapest way to break the
#   `PatternMatcher.__add__` arithmetic and the rows catch it immediately.
# * M12 moves eight rows and is the widest blast radius in the table: `fl_of`
#   feeds `pd_ok` and the whole `Bd` inventory, so one inverted filter there is
#   the closest thing this gate has to a keystone.
#
# WHAT THIS DOES NOT SAY. Twelve mutations is not a coverage argument. The
# builders -- every `TODO` in the foot below -- are not in this table because
# they are not in the file, so nothing here tests whether a rule reaches for the
# RIGHT builder.
# ===========================================================================

# ===========================================================================
# NOT PORTED. Every line is a `TODO(p3)` whose OWNING FILE is named, and every
# one is a builder or an arithmetic helper the port cannot reach without it.
# Nothing below is a decision that multi.py makes and this file declined: the
# decision is present and gateable in every case, and what is missing is the
# node it would have produced.
#
# THE GRAPH BUILDERS, one line per call site.
#
#   `_mop` (ops.py:614..:653) -- every `.arg`-carrying rewrite is a `_mop`.
#   TODO(p3) ops.py:646 multi.py:12   `_apply_shrink`, SHRINK
#   TODO(p3) ops.py:646 multi.py:144  `expand_multi`, EXPAND
#   TODO(p3) ops.py:646 multi.py:152  `pad_multi`, PAD
#   TODO(p3) ops.py:646 multi.py:179  `shrink_multi`, non-shard SHRINK
#   TODO(p3) ops.py:646 multi.py:180  `shrink_multi`, local SHRINK
#
#   `mselect` (ops.py:700) -- the MSELECT side of `replace_allreduce`.
#   TODO(p3) ops.py:700 multi.py:34   COPY_TO_ONE, `x.mselect(0)`
#   TODO(p3) ops.py:700 multi.py:37   MSELECT-on-MSTACK, `mstack.src[ms.arg]`
#   TODO(p3) ops.py:700 multi.py:42   MSELECT-before-Movement, `s.mselect(ms.arg)`
#   TODO(p3) ops.py:700 multi.py:44   MSELECT-before-ALU, `s.mselect(ms.arg)`
#   TODO(p3) ops.py:700 multi.py:235  `copy_multi`, `multi.src[0].mselect(i)`
#
#   `unshard` (ops.py:723) -- every rule's own conclusion, NINETEEN call sites.
#   TODO(p3) ops.py:723 multi.py:100  `alu_multi`, the per-shard arm
#   TODO(p3) ops.py:723 multi.py:105  `alu_multi`, the resharding fallback
#   TODO(p3) ops.py:723 multi.py:123  `reduce_multi`, the piecewise arm
#   TODO(p3) ops.py:723 multi.py:140  `reshape_multi`
#   TODO(p3) ops.py:723 multi.py:145  `expand_multi`
#   TODO(p3) ops.py:723 multi.py:152  `pad_multi`
#   TODO(p3) ops.py:723 multi.py:157  `permute_multi`
#   TODO(p3) ops.py:723 multi.py:181  `shrink_multi`, keeps `remaining`
#   TODO(p3) ops.py:723 multi.py:186  `flip_multi`
#   TODO(p3) ops.py:723 multi.py:196  `stack_multi`, the same-sharding arm
#   TODO(p3) ops.py:723 multi.py:200  `stack_multi`, the resharding fallback
#   TODO(p3) ops.py:723 multi.py:254  `store_after_multi`
#   TODO(p3) ops.py:723 multi.py:270  `passthrough_multi`, the two rules
#   TODO(p3) ops.py:723 multi.py:296  the ALLREDUCE rule
#
#   THE REST, one line each, owner named by the method.
#   TODO(p3) ops.py:612 multi.py:19   `mstack_early_shrink`, `.contiguous()`
#   TODO(p3) ops.py:612 multi.py:19   `mstack_early_shrink`, `.copy_to_device`
#   TODO(p3) ops.py:617 multi.py:22   `mstack_early_shrink`, `ms.replace`
#   TODO(p3) ops.py:600 multi.py:26   `lower_broadcast_copy`, `UOp(Ops.MSTACK, ...)`
#   TODO(p3) ops.py:790 multi.py:27   `lower_broadcast_copy`, `.pad_to`
#   TODO(p3) ops.py:790 multi.py:27   `lower_broadcast_copy`, `.shrink_to`
#   TODO(p3) ops.py:640 multi.py:69   `shard_srcs`, `.copy_multi`
#   TODO(p3) ops.py:660 multi.py:75   `shard_srcs`, `full._shard(src_axis, rng)`
#   TODO(p3) ops.py:640 multi.py:83   `shard_subview`, `.expand`
#   TODO(p3) ops.py:660 multi.py:84   `shard_subview`, `full._shard(ax, rng)`
#   TODO(p3) ops.py:606 multi.py:100  `alu_multi`, `srcs[0].alu(...)`
#   TODO(p3) ops.py:612 multi.py:112  `reduce_multi`, `multi.src[0]._rop(op, ...)`
#   TODO(p3) ops.py:712 multi.py:140  `reshape_multi`, `.reshape(new_shape)`
#   TODO(p3) ops.py:826 multi.py:156  `permute_multi`, `.permute(root.marg)`
#   TODO(p3) ops.py:800 multi.py:179  `shrink_multi`, `.copy_to_device(..., arg=)`
#   TODO(p3) ops.py:826 multi.py:186  `flip_multi`, `.flip([i for i,x ...])`
#   TODO(p3) ops.py:600 multi.py:196  `stack_multi`, `UOp(Ops.STACK, ...)`
#   TODO(p3) ops.py:600 multi.py:200  `stack_multi`, the fallback's STACK
#   TODO(p3) ops.py:660 multi.py:222  `index_multi`, `multi.src[0].index(*idxs)`
#   TODO(p3) ops.py:612 multi.py:235  `copy_multi`, `.copy_to_device(device)`
#   TODO(p3) ops.py:670 multi.py:245  `copy_multi`, `grp[0][1].cat(...)`
#   TODO(p3) ops.py:800 multi.py:251  `copy_multi`, `val.pad(...)`
#   TODO(p3) ops.py:600 multi.py:254  `store_after_multi`, `UOp.after`
#   TODO(p3) ops.py:680 multi.py:258  `store_value_multi`, `.store(multi.src[0])`
#   TODO(p3) ops.py:600 multi.py:266  `store_dest_multi`, `UOp(root.op, src=, arg=)`
#   TODO(p3) ops.py:600 multi.py:270  `passthrough_multi`, `UOp(root.op, src=, arg=)`
#   TODO(p3) ops.py:600 multi.py:278  `rewrite_into_function`, `call.replace`
#   TODO(p3) ops.py:600 multi.py:296  the ALLREDUCE rule, `UOp.allreduce(*red.arg)`
#   TODO(p3) ops.py:600 multi.py:304  the void-CALL rule, `UOp(root.op, src=, arg=)`
#
# THE TWO ARITHMETIC WALLS, which are not builders and so are a different kind
# of gap: they are needed by the DECISION, and every caller that must not
# silently receive them says which one it got.
#
#   TODO(p3) ops.py:1104 `_min_max` -- `int(rng.vmax)+1`. `fold.bend` lists it and
#   it is not a fold: it is arithmetic over the srcs. The NARROW case is ported
#   (`mu_count`, a RANGE over a CONST end) because it is the DEVICE range every
#   `unshard` builds; a SYMBOLIC end answers `mu_sym_count()` and the four
#   callers that must not have it say so.
#   TODO(p3) ops.py:520  `ssimplify` -- every symbolic step. `mu_sym_dim()` is the
#   marker and it is 0, the convention `LAWS/spec.bend`'s `dim_of` and
#   `allreduce.bend`'s `red_dim` already use.
#
# TWO MORE THAT ARE NOT THE PORT'S TO CLOSE.
#
#   `UOp.device` as a VALUE. `shard_srcs`'s `x.device is not None` (:56),
#   `lower_broadcast_copy`'s `isinstance(c.device, tuple)` (:25) and `shard_srcs`'s
#   `assert all_same(devices)` (:57) all read a DEVICE, and `ops.bend`'s node is an
#   arena INDEX with no device beside it. The two rules' DECISIONS are ported --
#   `t_lb_*` is `lower_broadcast_copy`'s predicate and `t_co_*` is COPY_TO_ONE's --
#   on the arena nodes that stand in for the device. The device TEST is not, and
#   `Ops.DEVICE`/`Ops.MULTI` tags in `spec.bend` are where it would have to be
#   spelled.
#   `graph_rewrite` (ops.py:1611) and the recursive CALL rule. `rewrite_into_function`
#   (:272) calls `multi_pm` ON ITSELF, and bend2 refuses mutual recursion and has
#   no first-class def values, so the recursion a Bend `multi_pm` needs is the
#   planner's problem and not this file's. `t_rw` in the gate is the rule's
#   DECISION -- is this a value-producing CALL -- and its body is the wall.
# ===========================================================================

# ===========================================================================
# WHAT THE OTHER FILES NEED.
#
# Three call sites this file makes on siblings, each with what the sibling has to
# supply. None of them is a wish; each is a line this file would otherwise have
# written itself.
#
# `schedule/allreduce.bend` -- ONE symbol.
#
#   `handle_allreduce`, for the `_early_allreduce` arm. `multi.py:48` is
#   `(UPat(Ops.ALLREDUCE, src=(UPat.var("buf"),), name="red"), handle_allreduce)`
#   and `multi_pm` prepends it when `LATE_ALLREDUCE` is off -- which is why this
#   file's table is a CONCATENATION and not a count, and why the tag shift is 19
#   or 20 rather than a constant. `allreduce.bend` already has the body; this
#   file needs a way to NAME it. It is `mu_ea_0`, and today it is a dispatch
#   arm that reports the body as another file's.
#
# `uop/fold.bend` -- ONE symbol, and it is why this file reads `ARange` raw.
#
#   `F.axis_at` / `F.folded`, the readers of a fold's per-axis info. This file
#   needs `{ids, at}` off an `ARange` and reaches for `mu_at_of` instead, which
#   reads `ARange{ids, at}` as a `Data` pattern. That works and it is honest,
#   but it pins this file to `ARange`'s FIELD NAMES. If `ARange` is renamed or
#   its shape changes, `mu_at_of` is the single place that has to move -- which
#   is the right shape for the coupling and the reason it is named once.
#
# `schedule/__init__.bend` -- TWO things, and neither is a symbol.
#
#   * `MULTI`. The header says it and it belongs here: `multi.py` in this
#     checkout never reads it, but `__init__.py` does, and the two flags this
#     file DOES port are `getenv` reads in `multi.py` itself. If `MULTI` moves
#     into this file it belongs in `Cfg` beside `late` and `cast`, and the
#     `Cfg` field count goes from two to three.
#   * THE RUN. `multi_pm` here is a VALUE (`mu_table`) and a scan
#     (`mu_claim_full` / `mu_first`); `__init__.bend` owns calling it over a graph
#     and rewriting until fixpoint. `graph_rewrite` (ops.py:1611) is the wall, and
#     it is the same wall `rewrite_into_function` hits from the other side.
#
# WHAT NONE OF THEM NEED FROM THIS FILE, stated because it is the boundary: no
# builder is defined here, so nothing in these three files can call into this one
# to build a node. What it exports is arithmetic and a table, and that is what
# `mu_first` is for -- it hands the planner a TAG, and the planner's own rules
# turn a tag into a rewrite.
# ===========================================================================
