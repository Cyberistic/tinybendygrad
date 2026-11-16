# codegen/late/linearizer.bend -- port of tinygrad/codegen/late/linearizer.py
#
# one BEND file per upstream .py, at the same path. This was `codegen/late.bend`
# until the 1:1 ruling; `codegen/late/regalloc.bend` and `codegen/late/gater.bend` are
# the other two slices, the rows are the SAME rows, and 128 before the split is 128
# across the three after it.
#
# this file also carries the shared substrate. `linearizer.py` needs an assoc list
# (`out_degree`, `priorities`, `nkey`, `CFGContext.deps`, `CFGContext.nesting`) and so
# does every other table in the lowerer, and Bend's `Map` is string-keyed only while
# all seven of regalloc's dicts are `U32`-keyed -- so ONE `RaTb` serves them all. It
# has no upstream counterpart, so it lives in the FIRST of the three files in Python's
# order and `regalloc.bend` imports it as `LT`. `gater.bend` needs none of it.
#
# the DEF-by-DEF map for all three files follows, whole; each of the other two points
# back at it rather than repeating it.
#
# `regalloc.py:69`'s `assert` -- bend has no assert form and no row can see an assert
# fire. two values are also not carried and both are named below: `Register.size`
# (W5, unobservable because `Register.__repr__` is the name) and the three renderer
# hooks' own bodies (`assign_spill_slot`, `fill`, `spill`), which are
# `NotImplementedError` in tinygrad's own base class and which the ORACLE supplies.
#
#   tinygrad/codegen/late/linearizer.py    96 lines   -> lt_*, lt_cfg_*, se_*   96/96
#   tinygrad/codegen/late/regalloc.py     118 lines   -> ra_*, rw_*          117/118
#   tinygrad/codegen/late/gater.py         29 lines   -> gt_*                    29/29
#
# THE DEF-BY-DEF MAP, and every row names the Python line it is a row for:
#
#   linearizer.py:8-51    linearize            lt_linearize            lin_u<i> x19
#   linearizer.py:11,16-17 out_degree          lt_deg                  (via lin_u<i>)
#   linearizer.py:20      run_count=prod(...)  lt_rc                    rc_* x6
#   linearizer.py:24-32   the priority ladder  lt_po / lt_po_op         po_* x9
#   linearizer.py:26      extra=u.arg.slot     -- NOT A FIELD            lin_exmix
#   linearizer.py:36      nkey / the sort      LtKey, lt_srt, lt_key    lin_nkey, lin_ord
#   linearizer.py:39-46   the heap loop        lt_hp.*, lt_hq.*         lin_u<i> x19
#   linearizer.py:46      newlst[::-1]         -- elided, see the header
#   linearizer.py:48-50   DEBUG_LINEARIZE      DROPPED (env-gated)
#   linearizer.py:53-81   CFGContext           cfg_ctx, cfg_sib, cfg_ed cfg_* x5
#   linearizer.py:68      the nesting scan     cfg_nest.*               (via cfg_*)
#   linearizer.py:77      the zipped dispatch  cfg_bucket               (via cfg_*)
#   linearizer.py:80      the assert           W3                       --
#   linearizer.py:83-85   pm_add_control_flow  cfg_tbl, cfg_rewrite     cfg_hits, cfg_tbl_*
#   linearizer.py:87-91   do_split_ends        se_rngs_of, se_split     se_rngs, se_ops,
#                                                                        se_len, se_nsrc
#   linearizer.py:90      the `else s.ranges`  W1                       --
#   linearizer.py:93-96   pm_split_ends        se_tbl, se_fired         se_tbl_*, se_fired,
#                                                                        se_miss
#   regalloc.py:8         PSEUDO_OPS           ra_is_pseudo, ra_pseudo_n rw_pseudo_n
#   regalloc.py:10-12     vdef                 ra_at, ra_rdef            (via ra<t>_lr)
#   regalloc.py:13-21     the ctor             ra_st0, RaSt.*            --
#   regalloc.py:22-29     live_range + loops   ra_lr.*, ra_hi, ra_lastuse ra<t>_lr
#   regalloc.py:32-37     the five dicts       RaSt (7 tables + in)      ra<t>_spills,
#                                                                        ra<t>_before
#   regalloc.py:39-45     alloc                ra_dist, ra_linv,         ra<t>_a<i>,
#                         (first-wins max)     ra_alloc.*, ra_del        ra1_a7 v ra0_a7
#   regalloc.py:48-53     fill                 ra_fill.*, ra_slot        ra<t>_spills,
#                                                                        ra<t>_before
#   regalloc.py:55-63     the uses             ra_use.*, ra_uses.*       ra<t>_a<i>
#   regalloc.py:64-77     the defs             ra_def.*, ra_k, ra_tw     ra<t>_a<i>,
#                                                                        ra1_a7
#   regalloc.py:80-90     the RANGE prologue   ra_pro.*, Su, su_le,      ra2_*
#                                                ra_blk, ra_w.*
#   regalloc.py:93-97     the END epilogue     ra_epi.*, ra_head, ra_pop ra2_spills,
#                                                                        ra2_before
#   regalloc.py:99-114    regalloc_rewrite     rw_*                      rw_none
#   regalloc.py:116-118   pm_regalloc_rewrite  ra_tbl, ra_tbl_len,      rw_tbl_len,
#                         (the TABLE)          ra_tbl_ops               rw_tbl_ops
#   gater.py:5-7          move_where_load      gt_w.*, gt_mwl.*         gt_mwl_* x4
#   gater.py:6-7          the dtype predicates W4                       --
#   gater.py:9-29         pm_move_gates_       gt_tbl, gt_ops           gt_tbl_len,
#                         from_index                                     gt_ops0..5
#
# why this unit is the tail of the lowerer, and what that buys it. `linearizer`
# folds the axis structure, `regalloc` assigns registers and `gater` decides
# which branches survive. All three are pure functions of the kernel's uop list,
# so a CPython oracle can be handed the same inputs and the two lanes diffed row
# for row -- there is no device, no driver and no codegen cache in the way.
# `regalloc`'s two renderer hooks are the exception and are named below.
#
# THE INTERFACE, CONSUMED NOT INVENTED. `codegen/kernel.bend` already owns
# `pm_to_program`, whose table carries a PROGRAM gaining a LINEAR, a SOURCE and a
# BINARY one `graph_rewrite` at a time (codegen/kernel.bend:804 symbol=pm_to_program), and whose stage
# dispatch is keyed on ARITY with the INS read only to discriminate the two
# two-src rules (kernel.bend:791-853). This file owns what those rules CALL:
#     :429 do_linearize         -> linearize(sink)        -> lt_linearize
#     :436 LinearScanRegallocContext(lin_ctx, lst, ctx)     -> ra_run
#     :376 pm_add_control_flow  -> CFGContext(sink)        -> lt_cfg / lt_acf
#     :366 pm_split_ends        -> do_split_ends           -> lt_se / lt_pm_se
# and `ops.bend`'s arena readers (`Arena.op/src/srcs/nsrc/arg/tag`,
# `Arena.src_without_body`, `UOp.new`) rather than a parallel shape. Every record
# field below is read by a HAND-WRITTEN reader def (constraint 27), because there
# is no `value.field` and no generated projection.
#
# THE FOUR WALLS, each at the file and line that owns it. W1 and W3 are the SAME
# lowerer wall the coordinator named -- `itertools.product` over a shape plus
# `permute`/`reshape`/`reduce`, which `uop/fold.bend` cannot answer for
# PAD/SHRINK/EXPAND/FLIP (`fold.bend:1606-1612`) -- arriving from two more
# directions. Nothing here answers them and nothing here pretends to.
#
#  W1 `u.ranges` and `r.vmax`  -- linearizer.py:20, :89
#     `run_count = prod([int(r.vmax)+1 for r in u.ranges])`. `u.ranges` is not in
#     `fold.bend` at all (`fold.bend`'s TODO at :2480-2482 is `vmin`/`vmax`/
#     `_min_max`), and `vmax` needs `_min_max`, whose wall is ARITHMETIC:
#     `helpers.bend` has `i64_add/sub/cmp` and NOT `i64_mul/div/mod`. So `lt_rc`
#     IS ported -- it is `prod` over a list of `vmax`es -- and the CALLER that
#     produces the list is the wall. The `lin_vm` row hands `lt_rc` the lists and
#     the `lin_u<i>` rows carry its answers, so the FOLD is gated and the WALL is
#     named. `rc_*` are five more, because on `lin` it only ever sees `[]`, `[3]`
#     and `[15]` -- three cases that cannot tell a product from a sum.
#
#  W2 `x.tuplize` -- linearizer.py:36
#     `sorted(lst, key=lambda x: priorities[x]+(x.tuplize if TUPLE_ORDER else ()))`
#     and `tuplize` is `(self.op.value, repr(self.arg), self.dtype,
#     *src.tuplize)` recursively (ops.py:322-324) -- a structural key holding a
#     `repr` of an arbitrary arg and a dtype value. `TUPLE_ORDER` is a real
#     ContextVar (helpers.py:280, default 1) and setting it 0 makes the key the
#     STABLE `(run_count, priority)` pair, which is exactly `List.sort` with `<=`,
#     measured stable. So this file ports the `TUPLE_ORDER=0` lane exactly and
#     names the `=1` lane W2. `lin_ties=47` of 171 pairs is how much W2 decides
#     on the fixture, and it is a ROW rather than a claim because the whole
#     `TUPLE_ORDER=1` order rests on it.
#
#  W3 `x.backward_slice_with_self` -- linearizer.py:80
#     `assert y.src[1] not in x.backward_slice_with_self`, a backward reachability
#     walk over `src` with a set. It is the ONLY use and the line above it is the
#     `TODO: this can happen! it causes infinite loop in shufflenet` -- so the
#     assert guards exactly the cycle this arena cannot represent (ops.bend's
#     header: the range graph HAS back-edges). `lt_cfg` computes the edges WITHOUT
#     it: the edge COUNT and the edge PAIR are both gated, and the missing check
#     is recorded here instead of being silently satisfied.
#
#  W4 a dtype and an addrspace as VALUES -- linearizer.py:27, gater.py:6-7,25-28
#     `u.addrspace == AddrSpace.LOCAL` is a `Maybe<&2, S.Addr>` out of
#     `F.fold.addr`, and `a.src[0].dtype == l.dtype` compares two `Maybe<&2,
#     S.Dt>`. bend 2.0.34 mis-parses `Maybe<&2, S.Dt>` in a def signature at the
#     position a helper would need it (the notes' "Maybe<&2, S.Dt> in a def
#     signature is position-sensitive"), so a dtype cannot be CARRIED and
#     therefore cannot be compared. Every rule below takes its predicate as a
#     `Bool` PARAMETER, which is the shape the notes prescribe, and the predicate
#     itself is W4.
#
# THE GATE. Every row is DERIVED FROM PYTHON by the oracle named at the foot; the
# interpreted lane, the native lane and CPython must print the same rows in the
# same order, so
#   diff <(.venv/bin/python gates/linearizer_census-oracle.py) <(./bin/bend tinybendygrad/codegen/late/linearizer.bend)
# is the acceptance test and NEITHER side can be nudged to match the other.
# both sides of that line were wrong and the oracle is now named. It read
# `python3 /tmp/opencode/late-oracle.py`, which has never existed, against
# `tinybendygrad/codegen/late.bend`, which the port moved INTO `late/` as this file --
# MEASURED 2026-10-16: `late-oracle.py` is absent at every path on every ref
# (`git rev-list --all --objects` names it zero times) and `tinybendygrad/codegen/late.bend`
# was `D` in this tree's history. The oracle that replaced it is
# `gates/linearizer_census-oracle.py`, which is 71 rows, RUNS (rc=0), and READS THIS FILE.
# `oracles/tinybendygrad_codegen_late.bend.rows` is ALSO in HEAD at 128 rows and is NOT in
# `differ.declared()` and has NO CODE READER -- a snapshot with neither a generator nor a
# consumer, reported rather than deleted, because deleting it is not this unit's call.
# The per-UOP gate shape and the two identity rows are described here; regalloc's
# half of the same paragraph is in `regalloc.bend`'s header.
#
import Base
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../uop/ops.bend as O
import ./../../uop/fold.bend as F
import ./../kernel.bend as KER

# one assoc list for every table in the file. `v` is a scalar answer and `vs` a
# list answer, and a FLAT PAIR LIST for the two `dict[int, dict[Register,
# Register]]` tables (regalloc.py:34-35) where `[v,r,v,r,...]` is the inner dict.
#
# ONE type rather than seven, and NOT a generic container: the seven Python dicts
# are all "key is a U32", and Bend's `Map` is string-keyed only (constraints,
# section 3) so a `List` of records is the substrate's own answer. A `Data`
# wrapper is the recurring Bend shape for a table a walk reads while walking.

type RaTb is Data:
  RaTb{es: List<&2, RaEn>}

type RaEn is Data:
  RaEn{k: U32, v: U32, vs: List<&2, U32>}

def RaTb.es(t: RaTb) -> List<&2, RaEn>:
  match t:
    case RaTb{es}: es

def RaEn.k(e: RaEn) -> U32:
  match e:
    case RaEn{k, v, vs}: k

def RaEn.v(e: RaEn) -> U32:
  match e:
    case RaEn{k, v, vs}: v

def RaEn.vs(e: RaEn) -> List<&2, U32>:
  match e:
    case RaEn{k, v, vs}: vs

# `dict.get(k, default)`. `defaultdict(int)` reads as 0, `live_inv.get(r)` as
# `None` and `ctx.edges.get(x)` as `None`, and index 0 is this file's `None`
# exactly as `UOp.is_none` says it is.
def tb_get.hit(hit: Bool, v: U32, rest: U32) -> U32:
  Bool.pick(U32, hit, v, rest)

def tb_get.go(+k: U32, rest: List<&2, RaEn>) -> U32:
  match rest:
    case Nil{}   : 0
    case +e <> r : tb_get.hit(U32.is_eq(RaEn.k(e), k), RaEn.v(e), tb_get.go(k, r))

def tb_get(+t: RaTb, k: U32) -> U32:
  tb_get.go(k, RaTb.es(t))

def tb_has.hit(hit: Bool, rest: Bool) -> Bool:
  Bool.pick(Bool, hit, True{}, rest)

def tb_has.go(+k: U32, rest: List<&2, RaEn>) -> Bool:
  match rest:
    case Nil{}   : False{}
    case +e <> r : tb_has.hit(U32.is_eq(RaEn.k(e), k), tb_has.go(k, r))

def tb_has(+t: RaTb, k: U32) -> Bool:
  tb_has.go(k, RaTb.es(t))

# THE LIST VALUE, because `lr[v]` and `reals[i]` and `insert_before[i]` are LISTS
# and `tb_get` cannot hand one back.
def tb_vs.hit(hit: Bool, vs: List<&2, U32>, rest: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, hit, vs, rest)

def tb_vs.go(+k: U32, rest: List<&2, RaEn>) -> List<&2, U32>:
  match rest:
    case Nil{}   : Nil{}
    case +e <> r : tb_vs.hit(U32.is_eq(RaEn.k(e), k), RaEn.vs(e), tb_vs.go(k, r))

def tb_vs(+t: RaTb, k: U32) -> List<&2, U32>:
  tb_vs.go(k, RaTb.es(t))

# `es.setdefault(k, [...]).insert(0, x)` and `.append(x)` are ONE def with a Bool
# arm, because the two DIRECTIONS are the difference between a live range in
# index order and one in reverse (regalloc.py:26 and :28) and spelling them apart
# is the whole content of those two lines.
def tb_ins.cat(pre: Bool, +old: List<&2, U32>, +vs: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, pre, List.append(&2, U32, vs, old), List.append(&2, U32, old, vs))

# the miss arm appends and the hit arm rewrites in place, which is what keeps a
# key at its first-insertion position; and the miss arm MUST carry the whole
# walked prefix, not the tail. Returning the tail is a `del` -- and a silent one,
# because the table still answers `1` for the key that survived and only the keys
# before the miss are gone, so the row that counts a lookup still passes. So the
# walk CONSES the head instead of recursing past it. `Bool.pick` is strict, so
# both arms run and every value they share is `+` (droppable, therefore duplicable
# -- a bare binder is Lone and a second read is refused).
def tb_ins.go(+pre: Bool, +k: U32, +v: U32, +vs: List<&2, U32>, rest: List<&2, RaEn>) -> List<&2, RaEn>:
  match rest:
    case Nil{}  : List.append(&2, RaEn, [RaEn{k, v, vs}], rest)
    case +e <> +r : Bool.pick(List<&2, RaEn>, U32.is_eq(RaEn.k(e), k),
                   List.append(&2, RaEn, [RaEn{k, v, tb_ins.cat(pre, RaEn.vs(e), vs)}], r),
                   List.append(&2, RaEn, [e], tb_ins.go(pre, k, v, vs, r)))

def tb_ins(pre: Bool, t: RaTb, k: U32, v: U32, vs: List<&2, U32>) -> RaTb:
  RaTb{tb_ins.go(pre, k, v, vs, RaTb.es(t))}

def tb_put(t: RaTb, k: U32, v: U32, vs: List<&2, U32>) -> RaTb:
  tb_ins(False{}, t, k, v, vs)

# `k` is a REGISTER INDEX, so the pair list is a `U32` list at stride two and
# `tb_put`'s `vs` field is the whole answer. `dict[k] = v` is REPLACE-or-APPEND
# and it is `tb_ins.go` with the pair as the unit, down to the cons and the `+`.
# `case _ <> _` is the CONS cover and it MUST BE LAST: it is the only cover bend
# accepts for the one-element list, since `case _ <>` cannot cover `Nil{}` (rule
# 7). A pair list is EVEN by construction, so the arm is unreachable and its
# answer is Python's `KeyError` default.
def tb_pget.go(vs: List<&2, U32>, +k: U32) -> U32:
  match vs:
    case Nil{}       : 0
    case +x <> y <> r : Bool.pick(U32, U32.is_eq(x, k), y, tb_pget.go(r, k))
    case _ <> _      : 0

def tb_pget(vs: List<&2, U32>, k: U32) -> U32:
  tb_pget.go(vs, k)

def tb_pput.go(+k: U32, +r: U32, vs: List<&2, U32>) -> List<&2, U32>:
  match vs:
    case Nil{}         : List.append(&2, U32, [k, r], vs)
    case +x <> y <> +q  : Bool.pick(List<&2, U32>, U32.is_eq(x, k),
                       List.append(&2, U32, [x, r], q),
                       List.append(&2, U32, [x, y], tb_pput.go(k, r, q)))
    case _ <> _       : List.append(&2, U32, [k, r], vs)

def tb_pput(vs: List<&2, U32>, k: U32, r: U32) -> List<&2, U32>:
  tb_pput.go(k, r, vs)

# `reals.setdefault(i, {})[v] = live[v]`: append-or-replace inside one bucket.
# `dict[b] = vs` -- REPLACE a bucket's list. `tb_put` is the APPEND primitive and
# this table needs BOTH: `insert_before.setdefault(i, []).append(...)` (:35, :52)
# appends and `reals.setdefault(i, {})[v] = live[v]` (:34, :63, :77) REPLACES.
# Written with `tb_put` the second one answers `old ++ new`, so a bucket written
# three times carries five pairs and `ra<t>_a<i>` prints the same virtual three
# times -- a row with the right LENGTH and the wrong GRAPH.
def tb_vput.go(+t: RaTb, +b: U32, +vs: List<&2, U32>, rest: List<&2, RaEn>) -> List<&2, RaEn>:
  match rest:
    case Nil{}   : List.append(&2, RaEn, [RaEn{b, 0, vs}], rest)
    case +e <> +r : Bool.pick(List<&2, RaEn>, U32.is_eq(RaEn.k(e), b),
                   List.append(&2, RaEn, [RaEn{b, 0, vs}], r),
                   List.append(&2, RaEn, [e], tb_vput.go(t, b, vs, r)))

def tb_vput(+t: RaTb, b: U32, vs: List<&2, U32>) -> RaTb:
  RaTb{tb_vput.go(t, b, vs, RaTb.es(t))}

def tb_pset.put(t: RaTb, +b: U32, vs: List<&2, U32>, k: U32, r: U32) -> RaTb:
  tb_vput(t, b, tb_pput(vs, k, r))

def tb_pset(+t: RaTb, +b: U32, k: U32, r: U32) -> RaTb:
  tb_pset.put(t, b, tb_vs(t, b), k, r)

def tb_keys.go(rest: List<&2, RaEn>, +acc: List<&2, U32>) -> List<&2, U32>:
  match rest:
    case Nil{}   : acc
    case e <> r  : tb_keys.go(r, List.append(&2, U32, acc, [RaEn.k(e)]))

def tb_keys(+t: RaTb) -> List<&2, U32>:
  tb_keys.go(RaTb.es(t), Nil{})

def tb_new() -> RaTb:
  RaTb{Nil{}}

# `List.append(a, A, xs, ys)` is `xs ++ ys`. TWO shapes with OPPOSITE results,
# and both are in this file, which is why both are named at their call sites:
# with the accumulator as a PARAMETER it appends in WALK ORDER (`lt_deg`, and the
# `ra` table walks), and with the TAIL'S ANSWER as the first argument the head
# lands LAST. Measured: `rc_*` rows, `lt_emit`'s `newlst`, and `lt_se`'s END chain.
# `u32_none()` IS Python's `None` for this port, and it is the same convention
# kernel.bend uses: `UOp.is_none` is index 0 and every "unset" here is 0xFFFFFFFF,
# which is a value no table in this file ever stores as a KEY. Same value as
# INDEPENDENT second copy of kernel.bend's, which is the shape of bug where two
# files agree until one of them is edited.
def u32_none() -> U32:
  O.ParamArg.no_slot()

def b2u(+b: Bool) -> U32:
  Bool.pick(U32, b, 1, 0)

def at(xs: List<&2, U32>, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, n), 0)

def nlen(xs: List<&2, U32>) -> Nat:
  List.length(&2, U32, xs)

def range_tuple.go(fuel: Nat, +k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n   : acc
    case 1n+p : range_tuple.go(p, U32.add(k, 1), List.append(&2, U32, acc, [k]))

def u32s(t: Nat) -> List<&2, U32>:
  range_tuple.go(t, 0, Nil{})

# `lt_rc` -- `run_count = prod([int(r.vmax)+1 for r in u.ranges])`, linearizer.py:20.
# PORTED as a fold over the vmax LIST. W1 is the CALLER.
# `rc_max` = 65536 is the row that pins the composite key's 26-bit range, since
# `lt_key` is `run_count * 64 + priority_offset` and the offset is 0..25.

def lt_rc.go(vmaxs: List<&2, U32>, +acc: U32) -> U32:
  match vmaxs:
    case Nil{}    : acc
    case v <> +t : lt_rc.go(t, U32.mul(acc, U32.add(v, 1)))

def lt_rc(vmaxs: List<&2, U32>) -> U32:
  lt_rc.go(vmaxs, 1)

# THE PRIORITY LADDER, linearizer.py:24-32. PORTED IN FULL, all eight arms.
#
#     match u.op:
#       case Ops.PARAM: priority, extra = -20, u.arg.slot
#       case Ops.BUFFER | Ops.ALLOC: priority = -17 if u.addrspace == AddrSpace.LOCAL else -18
#       case Ops.LOAD: priority = -1    # place loads early
#       case Ops.STORE: priority = 1    # place stores late
#       case Ops.RANGE: priority = 5    # placing RANGE is good
#       case Ops.END | Ops.BACKEDGE: priority = -5     # placing loop exits is bad
#       case _: priority = 0            # everything else has priority 0
#
# EVERY PRIORITY IS NEGATIVE and Bend has no signed `U32`, so this returns
# `priority + 20`: the OFFSET, on 0..25, order-isomorphic to the priority. The
# `po=` column of every `lin_u<i>` row is that offset and not the priority.
#
# `extra` -- `u.arg.slot` for a PARAM, `None` for everything else -- is NOT a
# field here, and that is a claim rather than an omission: `extra` is only ever
# REACHED when `run_count` AND `priority` are equal, and priority -20 is the
# PARAM's alone, so any two entries that meet at `extra` are both PARAMs and both
# slots. Python would raise `TypeError` comparing `None` with an `int` if that
# were not true, and `lin_exmix=0` is the row that checks it on the fixture.
# `lin_exmix` COUNTS the pairs that tie on (run_count, priority) and disagree on
# whether `extra` is None -- so it is a gate, not a comment.
#
# `# TODO(p3) linearizer.py:50  symbol=linearize  the DEBUG_LINEARIZE print reads `extra` -- the one
# place Python reads the field, and env-gated.`
#
# W4: the BUFFER/ALLOC arm's `u.addrspace == AddrSpace.LOCAL` is a PARAMETER. The
# arm is `lt_po.w1(local, is_bufalloc)`; `lt_po_glob`/`lt_po_loc` are the two rows.
# THE OP PREDICATES, LEAF FIRST. Seven arms of the ladder would be seven
# two-armed `match`es if each were written out, and each gets ITS OWN row (`po_*`)
# so that a mutation dropping one arm moves exactly that row -- the `k_alu_recip`
# lesson from kernel.bend's mutation table.
def lt_op_is(op: O.Op, want: O.Op) -> Bool:
  O.eq_op(op, want)

def lt_is_param(op: O.Op) -> Bool:
  lt_op_is(op, O.OpsPARAM{})

def lt_is_store(op: O.Op) -> Bool:
  lt_op_is(op, O.OpsSTORE{})

def lt_is_load(op: O.Op) -> Bool:
  lt_op_is(op, O.OpsLOAD{})

def lt_is_range(op: O.Op) -> Bool:
  lt_op_is(op, O.OpsRANGE{})

# THE TWO-ARMED PREDICATES, and `case _:` must be LAST: an arm after a `case _:`
# is DEAD CODE and bend 2.0.34 does not say so.
def lt_is_bufalloc(op: O.Op) -> Bool:
  match op:
    case O.OpsBUFFER{}: True{}
    case O.OpsALLOC{} : True{}
    case _: False{}

def lt_is_exit(op: O.Op) -> Bool:
  match op:
    case O.OpsEND{}     : True{}
    case O.OpsBACKEDGE{}: True{}
    case _: False{}

# W4. `u.addrspace` is `F.fold.addr`'s `Maybe<&2, S.Addr>` and it cannot be
# carried in a signature; so the decision is a `Bool` parameter and THIS is the
# predicate. The half that reads `ParamArg.addrspace` is PORTED -- `S.Addr` is a
# VALUE, not a `Maybe` -- and what is NOT is the `Arg` dispatch for a node whose
# arg is not a `ParamArg`, which `fold.addr` would answer.
def lt_addr_same(ad: S.Addr) -> Bool:
  match ad:
    case S.ALocal{}: True{}
    case _: False{}

def lt_addr_pa(pa: O.ParamArg) -> Bool:
  lt_addr_same(O.ParamArg.addrspace(pa))

def lt_addr_of(a: O.Arg, not_found: Bool) -> Bool:
  match a:
    case O.AParam{pa}: lt_addr_pa(pa)
    case _: not_found

# THE LADDER, five `Bool.pick`s deep because `match` may not scrutinise a CALL.
# The order is PYTHON'S ORDER of the `match u.op:` arms and it is load-bearing:
# `Bool.pick` is strict so every predicate runs on every arm, and the RESULT is
# the first arm that fires. `po_*` rows are one per arm, and `po_add` is the
# default because the ladder's `case _:` arm is priority 0 -> offset 20.
def lt_po.w5(local: Bool, buf: Bool) -> U32:
  Bool.pick(U32, buf, Bool.pick(U32, local, 3, 2), 20)

def lt_po.w4(local: Bool, buf: Bool, store: Bool) -> U32:
  Bool.pick(U32, store, 21, lt_po.w5(local, buf))

def lt_po.w3(local: Bool, buf: Bool, store: Bool, load: Bool) -> U32:
  Bool.pick(U32, load, 19, lt_po.w4(local, buf, store))

def lt_po.w2(local: Bool, buf: Bool, store: Bool, load: Bool, param: Bool) -> U32:
  Bool.pick(U32, param, 0, lt_po.w3(local, buf, store, load))

def lt_po.w1(local: Bool, buf: Bool, store: Bool, load: Bool, param: Bool, range: Bool, exit: Bool) -> U32:
  Bool.pick(U32, range, 25, Bool.pick(U32, exit, 15, lt_po.w2(local, buf, store, load, param)))

def lt_po.of(+a: O.Arena, +i: U32, +op: O.Op, local: Bool) -> U32:
  lt_po.w1(local, lt_is_bufalloc(op), lt_is_store(op), lt_is_load(op), lt_is_param(op), lt_is_range(op), lt_is_exit(op))

def lt_po(+a: O.Arena, +i: U32) -> U32:
  lt_po.of(a, i, O.Arena.op(a, i), lt_addr_of(O.Arena.arg(a, i), False{}))

# `lt_po` is the VALUE `O.Arena`/`O.Arena.arg` is read for, so `local` and `op`
# are parameters of `.of` rather than calls in the argument list: `lt_po.of(a, i,
# O.Arena.op(a, i), lt_addr_of(O.Arena.arg(a, i), False{}))` reads `a` twice and
# `i` twice and both `+`, and bend evaluates arguments left to right so the
# arena's reads are ordered. Named here so the gate's `po_*` rows can call the
# `.of` form with a FIXED op and vary one predicate at a time.
def lt_po_op(+op: O.Op) -> U32:
  lt_po.w1(False{}, lt_is_bufalloc(op), lt_is_store(op), lt_is_load(op),
           lt_is_param(op), lt_is_range(op), lt_is_exit(op))

# `extra` -- `u.arg.slot` for a PARAM and `None` for everything else
# (linearizer.py:26). `u32_none()` is this port's `None`, the same convention as
# `UOp.is_none`, and it is a VALUE rather than an `Option` because the field is
# only ever compared for `is None`.
def lt_extra.slot.of(arg: O.Arg) -> U32:
  match arg:
    case O.AParam{pa}: O.ParamArg.slot(pa)
    case _: u32_none()

def lt_extra.slot(arg: O.Arg) -> U32:
  lt_extra.slot.of(arg)

def lt_extra.of2(isp: Bool, arg: O.Arg) -> U32:
  Bool.pick(U32, isp, lt_extra.slot(arg), u32_none())

def lt_extra.of(isp: Bool, +a: O.Arena, +i: U32) -> U32:
  lt_extra.of2(isp, O.Arena.arg(a, i))

def lt_extra(+a: O.Arena, +i: U32) -> U32:
  lt_extra.of(lt_is_param(O.Arena.op(a, i)), a, i)

# `lt_key` -- `priorities[x]` as ONE `U32`. `rc * 64 + offset` is order-isomorphic
# to the LEXICOGRAPHIC order on `(run_count, priority)` for `rc < 2^26`, because
# the offset is 0..25 < 64. That is what lets `List.sort`'s comparator -- whose
# parameter type is `A -> A -> Bool` with `+` REFUSED, so one field read per
# element -- be a single `U32.is_le`.
def lt_key(rc: U32, po: U32) -> U32:
  U32.add(U32.mul(rc, 64), po)

# `out_degree` -- linearizer.py:11, :16-17. A COUNT OF OCCURRENCES, not a set
# membership: Python's `out_degree[s] += 1` runs once per (consumer, src) PAIR,
# and a node an operator names twice has two edges into it.
# `for u in reversed(lst): for s in u.src_without_body: out_degree[s] += 1`
#
# `reversed(lst)` is `List.reverse` -- the counts are order-independent, but
# transcribing `reversed` is one call and keeps the diff against :17 readable.
# `List.foldl` IS THE SRC LOOP. The inner `for s in u.src_without_body` is a
# 2-ary fold with a top-level step, so it is ONE call and there is no mutual
# recursion -- which is why the outer walk is one def and the inner is a builtin.
def lt_deg.bump.put(+acc: RaTb, n: U32, +s: U32) -> RaTb:
  tb_put(acc, s, U32.add(n, 1), Nil{})

def lt_deg.bump(+acc: RaTb, +s: U32) -> RaTb:
  lt_deg.bump.put(acc, tb_get(acc, s), s)

# `out_degree[v] -= 1`, the heap loop's SECOND use of the same table and the only
# one that DECREMENTS. ONE read of the degree and the `-1` in `.put`, which is why
# it does not need the `.of` split `lt_deg.bump` does not either.
def lt_deg.dec.put(+tb: RaTb, n: U32, v: U32) -> RaTb:
  tb_put(tb, v, U32.sub(n, 1), Nil{})

def lt_deg.dec(+tb: RaTb, +v: U32) -> RaTb:
  lt_deg.dec.put(tb, tb_get(tb, v), v)

# NOT `List.foldl`, and the reason is worth recording: `List.foldl`'s step has
# type `B -> A -> B` with `+` REFUSED on its parameters (measured, and the same
# restriction as `List.sort`'s comparator), while `out_degree[s] += 1` needs BOTH
# of `acc` and `s` twice. A step with `+` cannot be a fold step, so the inner
# loop is its own self-recursive def -- and because that def does not call back,
# it is not a mutual recursion, it is just declared FIRST.
def lt_deg.srcs(ss: List<&2, U32>, +acc: RaTb, ar: O.Arena) -> RaTb:
  match ss:
    case Nil{}   : acc
    case s <> +r : lt_deg.srcs(r, lt_deg.bump(acc, s), ar)

# THE TABLE'S KEY ORDER IS PYTHON'S. `tb_ins.go` rewrites in place and appends on
# a miss, so `out_degree` comes out in first-seen order -- and that is free, not
# incidental: a live range (`regalloc.py:26-28`) IS a per-key list whose order is
# the gate, so a table whose key order is unobservable here is a table that gets
# checked there.
def lt_deg.go(+ar: O.Arena, rest: List<&2, U32>, +acc: RaTb) -> RaTb:
  match rest:
    case Nil{}  : acc
    case u <> +t : lt_deg.go(ar, t, lt_deg.srcs(O.Arena.src_without_body(ar, u), acc, ar))

def lt_deg(ar: O.Arena, lst: List<&2, U32>) -> RaTb:
  lt_deg.go(ar, List.reverse(&2, U32, lst), tb_new())

# THE SORT ELEMENT. `LtKey{k: U32, i: U32}`: the composite key and the node it
# belongs to. ONE field is read by the comparator and the other is never read
# there, which is the whole reason a two-part key is legal at all.
type LtKey is Data:
  LtKey{k: U32, i: U32, rc: U32, ex: U32}

def LtKey.k(x: LtKey) -> U32:
  match x:
    case LtKey{k, i, rc, ex}: k

def LtKey.i(x: LtKey) -> U32:
  match x:
    case LtKey{k, i, rc, ex}: i

# `ex` IS PYTHON'S `extra` -- the PARAM's slot, `u32_none()` for everything else --
# carried ONLY so `lin_exmix` can be computed in the port rather than asserted.
# `+` on a `U32` is free (the notes' rule 30), so a fourth field costs nothing and
# buys the row that says dropping `extra` is sound.
def LtKey.ex(x: LtKey) -> U32:
  match x:
    case LtKey{k, i, rc, ex}: ex

# `rc` RIDES ALONG rather than being re-read from the `vms` table at print time.
# The alternative -- a positional walk over the length-prefixed list -- needs a
# self-call whose first argument is a COMPUTED `List.drop`, and the decrease check
# refuses that ("a self-call may not pass a computed argument in front of the
# tail"). Carrying it is also what makes the comparator's "one field read" free:
# the comparator reads `k` and the printer reads `i` and `rc`.
def LtKey.rc(x: LtKey) -> U32:
  match x:
    case LtKey{k, i, rc, ex}: rc

# THE IDEAL ORDER -- `nkey = {u: i for i, u in enumerate(sorted(lst, key=...))}`,
# linearizer.py:36. So `nkey` IS the POSITION in the sorted list and the whole
# table is the sorted list: `lt_nkey` searches it.
#
# THE SORT KEY IS ONE `U32` (`lt_key`), which is what makes the comparator legal:
# `List.sort`'s comparator type is `A -> A -> Bool` with `+` REFUSED on its
# parameters, so each element may be read exactly ONCE -- and `LtKey` has two
# fields, of which only `k` is read. A two-field comparison key would have to be
# a two-scrutinee `match` over two RECORDS, which is four arms of nothing.
#
# `List.sort` is STABLE and `le` is `<=` (base's `List.merge.step` takes `x`,
# the FIRST run's head, whenever `le(x, y)`), and Python's `sorted` is stable
# too, so TIES fall back to the toposort order in both. That is the whole of the
# `TUPLE_ORDER=0` lane and W2 is the rest.

def lt_kle(x: LtKey, y: LtKey) -> Bool:
  U32.is_le(LtKey.k(x), LtKey.k(y))

def lt_sorted(ks: List<&2, LtKey>) -> List<&2, LtKey>:
  List.sort(LtKey, lt_kle, ks)

def lt_nkey.hit(hit: Bool, +i: U32, rest: U32) -> U32:
  Bool.pick(U32, hit, i, rest)

def lt_nkey.go(srt: List<&2, LtKey>, +i: U32, +u: U32) -> U32:
  match srt:
    case Nil{}       : 0
    case +e <> r     : lt_nkey.hit(U32.is_eq(LtKey.i(e), u), i, lt_nkey.go(r, U32.add(i, 1), u))

def lt_nkey(srt: List<&2, LtKey>, u: U32) -> U32:
  lt_nkey.go(srt, 0, u)

# W1 again, and this time it is the pass's own caller. `vms` is one flat list of
# `vmax`es for the WHOLE walk, LENGTH-PREFIXED per list position:
#
#     vms = [ n0, v0, ..., v_{n0-1}, n1, v0, ..., ... ]
#
# A `List<&2, List<&2, U32>>` is not available -- `List` is a `Type` and cannot be
# a list ELEMENT (the notes' FOUR MORE GENERAL RULES, item 1) -- and a bare flat
# list with no prefix would pair a node with ANOTHER node's ranges whenever the
# lengths differ, which is a plausible wrong `rc` everywhere and no error at all.
# `lin_vm` is the row that prints the whole table in the oracle's `;`-separated
# spelling, and `lin_u<i>` carries every `rc` computed from it.
type VM is Data:
  VM{vs: List<&2, U32>, rest: List<&2, U32>}

def VM.vs(x: VM) -> List<&2, U32>:
  match x:
    case VM{vs, rest}: vs

def VM.rest(x: VM) -> List<&2, U32>:
  match x:
    case VM{vs, rest}: rest

def lt_vm.take2(vs: List<&2, U32>, rest: List<&2, U32>) -> VM:
  VM{vs, rest}

def lt_vm.take(+r: List<&2, U32>, +n: Nat) -> VM:
  lt_vm.take2(List.take(&2, U32, r, n), List.drop(&2, U32, r, n))

def lt_vm.go(vms: List<&2, U32>) -> VM:
  match vms:
    case Nil{}    : VM{Nil{}, Nil{}}
    case n <> +r  : lt_vm.take(r, U32.to_nat(n))

# `lt_po` reads `Arena.op` and `Arena.arg` and NOT `fold.addr`: `ParamArg`'s
# addrspace is a `S.Addr` VALUE (ops.bend:705), so W4's "a dtype cannot be
# carried" does not bite the BUFFER/ALLOC arm after all and the predicate is
# PORTED. What W4 still blocks is the `Arg` dispatch for a node whose arg is not
# a `ParamArg`, which `fold.addr` would answer -- `lt_addr_of`'s `case _:` arm.
def lt_keys.put(+acc: List<&2, LtKey>, +u: U32, +ar: O.Arena, +vm: VM) -> List<&2, LtKey>:
  List.append(&2, LtKey, acc, [LtKey{lt_key(lt_rc(VM.vs(vm)), lt_po(ar, u)), u, lt_rc(VM.vs(vm)), lt_extra(ar, u)}])

def lt_keys.go(+ar: O.Arena, lst: List<&2, U32>, +vms: List<&2, U32>, +acc: List<&2, LtKey>) -> List<&2, LtKey>:
  match lst:
    case Nil{}    : acc
    case u <> +t  : lt_keys.go(ar, t, VM.rest(lt_vm.go(vms)),
                              lt_keys.put(acc, u, ar, lt_vm.go(vms)))

def lt_keys(+ar: O.Arena, lst: List<&2, U32>, vms: List<&2, U32>) -> List<&2, LtKey>:
  lt_keys.go(ar, lst, vms, Nil{})

# THE HEAP LOOP, linearizer.py:39-46. PORTED, and `heapq` is a SORTED LIST.
#
#     heap = [(-nkey[sink], sink)];  newlst = []
#     while heap:
#       newlst.append(u := heapq.heappop(heap)[1])
#       for v in u.src_without_body:
#         out_degree[v] -= 1
#         if out_degree[v] == 0: heapq.heappush(heap, (-nkey[v], v))
#     newlst = newlst[::-1]
#
# `nkey` is a BIJECTION onto 0..n-1 (`enumerate(sorted(lst, ...))`), so two heap
# entries never tie and `heapq.heappop` -- the SMALLEST tuple, and the tuple is
# `(-nkey, v)` -- returns the node with the LARGEST `nkey`. So the pop order is
# descending in `nkey` AMONG THE AVAILABLE, and `newlst[::-1]` reverses it.
# `heappush` on a sorted list is a re-sort and `heappop` is taking the head, which
# is the whole port of `heapq`.
#
# READING `-nkey` AS "SMALLEST nkey" IS THE MISTAKE, and it produces a plausible
# list of the right LENGTH with every position wrong -- which is what the first
# version of this file did and what `lin_u<i>` is the row class for.
#
# AND THE ORDER IS NOT A COUNTDOWN, which is the thing worth writing down: a
# descending walk over `nkey` that SKIPS a node whose degree is not yet 0 is not
# the heap, because the heap COMES BACK to it. `nkey` is the IDEAL order, not a
# topological order, so a node can have a SMALLER `nkey` than its consumer: node 2
# (nkey 6) is a src of node 13 (nkey 1) and is released only by popping node 13,
# long after step 6. A countdown version emitted 16 of the 19 nodes and every one
# of them was in the right relative order. That is the worst shape of bug --
# right prefixes, wrong count, no error.
#
# so the queue is the state and the fuel is the queue's length, which is why
# `rem` is `List.length(HP.heap(h))` and not a bound: the `0n` arm IS the `while
# heap:` test. A queue that GROWS cannot be a Bend self-call's shrinking first
# argument, so it travels inside a `Data` record and only `rem` decreases.
type HP is Data:
  HP{heap: List<&2, LtKey>, tb: RaTb}

def HP.heap(h: HP) -> List<&2, LtKey>:
  match h:
    case HP{heap, tb}: heap

def HP.tb(h: HP) -> RaTb:
  match h:
    case HP{heap, tb}: tb

# `heapq.heappush(heap, (-nkey[v], v))` -- the entry is `LtKey{nkey[v], v, 0, 0}`
# because the heap is held SORTED BY `nkey` ASCENDING and `heappop` takes the
# HEAD, which is the LAST. `rc` and `ex` are 0 because the heap never reads them.
# DESCENDING, and stability is irrelevant here (unlike `lt_sorted`, where it is
# load-bearing): every heap entry is a DISTINCT node and `nkey` is a bijection, so
# no two entries tie. The sort is descending so the HEAD is the largest `nkey`,
# which is what `heappop` on `(-nkey, v)` returns.
def lt_hp.kle(x: LtKey, y: LtKey) -> Bool:
  U32.is_ge(LtKey.k(x), LtKey.k(y))

def lt_hp.push(q: List<&2, LtKey>, e: LtKey) -> List<&2, LtKey>:
  List.sort(LtKey, lt_hp.kle, List.append(&2, LtKey, q, [e]))

# THE HEAD'S NODE, which is `enumerate`'s value read at position 0. `lt_srt_node`
# is the general form -- the node at POSITION k -- and it is also `lt_nkey`'s
# inverse, so `lt_srt_node(lt_srt(), k)` is the identity `nkey[at(k)] == k`.
def lt_srt_node(srt: List<&2, LtKey>, +pos: U32) -> U32:
  match srt:
    case Nil{}     : 0
    case +e <> +r  : Bool.pick(U32, U32.is_zero(pos), LtKey.i(e), lt_srt_node(r, U32.sub(pos, 1)))

def lt_hq.head2(+q: List<&2, LtKey>) -> U32:
  lt_srt_node(q, 0)

def lt_hq.head(+h: HP) -> U32:
  lt_hq.head2(HP.heap(h))

# `out_degree[v] -= 1; if out_degree[v] == 0: heappush(...)`. The test reads the
# DECREMENTED table, so `.dec2` is the table and `.hit` the push -- and the push is
# a VALUE, which is what makes `Bool.pick` legal here (it is strict, so the push is
# computed and discarded when `zero` is False, and computing it is total).
def lt_hp.hit(zero: Bool, +s: U32, +h: HP, +srt: List<&2, LtKey>) -> HP:
  Bool.pick(HP, zero, HP{lt_hp.push(HP.heap(h), LtKey{lt_nkey(srt, s), s, 0, 0}), HP.tb(h)}, h)

def lt_hp.dec2(+tb: RaTb, +s: U32, heap: List<&2, LtKey>, +srt: List<&2, LtKey>) -> HP:
  lt_hp.hit(U32.is_zero(tb_get(tb, s)), s, HP{heap, tb}, srt)

def lt_hp.dec(+s: U32, +tb: RaTb, heap: List<&2, LtKey>, +srt: List<&2, LtKey>) -> HP:
  lt_hp.dec2(lt_deg.dec(tb, s), s, heap, srt)

# `for v in u.src_without_body:` -- the queue and the table BOTH change, so the
# accumulator is the `HP` record and the self-call's first argument is the tail.
def lt_hp.ss(ss: List<&2, U32>, +h: HP, +srt: List<&2, LtKey>) -> HP:
  match ss:
    case Nil{}   : h
    case s <> +r : lt_hp.ss(r, lt_hp.dec(s, HP.tb(h), HP.heap(h), srt), srt)

# ONE POP: take the head off the queue, then release its srcs.
def lt_hp.pop(v: U32, +h: HP, +srt: List<&2, LtKey>, ar: O.Arena) -> HP:
  lt_hp.ss(O.Arena.src_without_body(ar, v), HP{List.tail(&2, LtKey, HP.heap(h)), HP.tb(h)}, srt)

# THE STEP'S TWO ANSWERS -- the popped node and the new queue -- which is why `PS`
# exists: `lt_hp.pop` is PURE, so calling it twice would be correct and wasteful,
# and a record is one line.
type PS is Data:
  PS{hp: HP, v: U32}

def PS.hp(p: PS) -> HP:
  match p:
    case PS{hp, v}: hp

def PS.v(p: PS) -> U32:
  match p:
    case PS{hp, v}: v

def lt_hq.step(+h: HP, +srt: List<&2, LtKey>, ar: O.Arena) -> PS:
  PS{lt_hp.pop(lt_hq.head(h), h, srt, ar), lt_hq.head(h)}
# THE STEP IS CALLED TWICE and that is FINE and not an oversight: `lt_hp.pop` is
# PURE, so the second call returns the same `PS`. A `.go` split would be a mutual
# recursion (the step's answer IS the self-call's first argument), which Bend
# refuses, and this is the documented alternative -- "call the pure function twice"
# from the notes' movement.bend entry 13.
# `rem` IS THE REMAINING NUMBER OF POPS and not the queue's length: every node is
# popped EXACTLY ONCE, so `n - pops` reaches 0 exactly when the queue empties, and
# it DECREASES BY ONE per step even when the queue grows -- which the queue's own
# length does not. It is the first parameter because the decrease check reads left
# to right (the notes' rule 5), and the second argument is computed, which is free
# once the first has shrunk.
def lt_hq.go(rem: Nat, +h: HP, +srt: List<&2, LtKey>, +ar: O.Arena, +acc: List<&2, U32>) -> List<&2, U32>:
  match rem:
    case 0n   : acc
    case 1n+p : lt_hq.go(p, PS.hp(lt_hq.step(h, srt, ar)), srt, ar,
                         List.append(&2, U32, acc, [PS.v(lt_hq.step(h, srt, ar))]))

# THE PASS. `linearize(sink)` is `lst` in, `newlst` out, and `lst` is a PARAMETER
# because `sink.toposort(enter_calls=False)` is ops.py:1378 -- a graph walk with a
# visited flag, not a list operation, and the file this unit owns does not own it.
# `out_degree` is fed `lst` and NOT the sorted list even though the counts are
# order-independent: the sorted list would make the KEY ORDER observable, and
# `lt_deg`'s own comment says it is not.
def lt_emit(+ar: O.Arena, lst: List<&2, U32>, +srt: List<&2, LtKey>, +sink: U32) -> List<&2, U32>:
  List.reverse(&2, U32, lt_hq.go(List.length(&2, LtKey, srt),
                                HP{lt_hp.push(Nil{}, LtKey{lt_nkey(srt, sink), sink, 0, 0}),
                                   lt_deg(ar, lst)}, srt, ar, Nil{}))

# `linearize` -- linearizer.py:8-51, with the DEBUG print (:48-50) dropped: it is
# env-gated, it prints `multirange_str` (a `UOp.ranges` reader, W1) and it reads
# the `extra` field W2. `# TODO(p3) linearizer.py:48-50  getenv("DEBUG_LINEARIZE")`
def linearize(+ar: O.Arena, +lst: List<&2, U32>, vms: List<&2, U32>, +sink: U32) -> List<&2, U32>:
  lt_emit(ar, lst, lt_sorted(lt_keys(ar, lst, vms)), sink)

# THE GATE FIXTURE. Twenty-two arena indices built in the interning order the
# oracle uses, so `ix` can be diffed row by row and a row that reads the wrong
# index is a DIFFERENT NUMBER rather than a plausible one.
#
# A CONST of int32 is a PAIR in CPython (`UOp.const(b, dt)` is `const.cast(dt)`,
# ops.py:631) and `ops.bend`'s `UOp.const` interns the BARE CONST only, so the
# CAST is built EXPLICITLY here: one node there is two here and every index after
# it is off by one. That is ops.bend's own recorded divergence, and this file
# pays the second node to keep the gate's indices equal to the oracle's.
#
#   1 C1a 2 C1 3 C4a 4 C4 5 C16a 6 C16 7 SP 8 BUFL 9 PRM 10 R_U 11 ADD
#  12 ST 13 ALG 14 EN 15 R_B 16 ADD2 17 ST2 18 EN2 19 SK 20 CALL 21 SK2
#
# `BUFL` is a LOCAL BUFFER and `ALG` a GLOBAL one, because `linearizer.py:27`
# reads `u.addrspace` and the two differ by exactly one unit of offset (3 against
# 2) -- and `lin_u3` and `lin_u5` are the two rows that see it.
#
# `SP` HAS A SRC, like every real kernel (`SPECIAL ['CAST']` in dbg7's dump): a
# src-less SPECIAL makes `_min_max` answer `self.src[0]-1` and raise, so the
# oracle cannot even build a fixture without one.
#
# `R_B`'s SECOND SRC IS `EN`, which is the shape `CFGContext` needs to reach `EN`
# from the SINK. A SINK with a single END child yields NO edges, because
# `zipped` is `zip(order, order[1:])` and `order` then has length one -- measured
# on a real `(a*b+3).relu().sum()` kernel, which is the fixture the first
# version of this file lacked.

def lt_pa(slot: U32, dt: S.Dt, ad: S.Addr) -> O.ParamArg:
  O.ParamArg{slot, dt, None{}, None{}, None{}, ad, None{}, False{}, None{},
             None{}, False{}, None{}}

def lt_i32.go(+made: O.Found, ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsCAST{}, [O.Found.i(made)], O.ADt{S.int32()}, O.TNone{})

def lt_i32(c: U32, +ar: O.Arena) -> O.Found:
  lt_i32.go(O.UOp.const(ar, O.CInt{H.i64_of_i32(c)}), ar)

def lt_fix() -> KER.K:
  +c1a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +c1 = lt_i32(1, O.Found.ar(c1a))
  +c4a = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(4)})
  +c4 = lt_i32(4, O.Found.ar(c4a))
  +c16a = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(16)})
  +c16 = lt_i32(16, O.Found.ar(c16a))
  +sp = O.UOp.new(O.Found.ar(c16), O.OpsSPECIAL{}, [O.Found.i(c1)], O.AStr{"0"}, O.TNone{})
  +bufl = O.UOp.new(O.Found.ar(sp), O.OpsBUFFER{}, [O.Found.i(sp)],
                    O.AParam{lt_pa(7, S.single(), S.ALocal{})}, O.TNone{})
  +prm = O.UOp.new(O.Found.ar(bufl), O.OpsPARAM{}, Nil{},
                   O.AParam{lt_pa(0, S.single(), S.AGlobal{})}, O.TNone{})
  +r_u = O.UOp.range_end(O.Found.ar(prm), O.Found.i(c4), [0], O.AXIS_UNROLL{})
  +ad = O.UOp.new(O.Found.ar(r_u), O.OpsADD{}, [O.Found.i(prm), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +st = O.UOp.new(O.Found.ar(ad), O.OpsSTORE{}, [O.Found.i(bufl), O.Found.i(ad), O.Found.i(sp)],
                  O.ANone{}, O.TNone{})
  +al = O.UOp.new(O.Found.ar(st), O.OpsALLOC{}, [O.Found.i(c1)],
                  O.AParam{lt_pa(0, S.single(), S.AGlobal{})}, O.TNone{})
  +en = O.UOp.new(O.Found.ar(al), O.OpsEND{}, [O.Found.i(st), O.Found.i(r_u)], O.ANone{}, O.TNone{})
  +r_b = O.UOp.new(O.Found.ar(en), O.OpsRANGE{}, [O.Found.i(c16), O.Found.i(en)],
                   O.ARange{[1], O.AXIS_LOOP{}}, O.TNone{})
  +ad2 = O.UOp.new(O.Found.ar(r_b), O.OpsADD{}, [O.Found.i(prm), O.Found.i(c16)], O.ANone{}, O.TNone{})
  +st2 = O.UOp.new(O.Found.ar(ad2), O.OpsSTORE{}, [O.Found.i(bufl), O.Found.i(ad2), O.Found.i(sp)],
                   O.ANone{}, O.TNone{})
  +en2 = O.UOp.new(O.Found.ar(st2), O.OpsEND{}, [O.Found.i(st2), O.Found.i(r_b)], O.ANone{}, O.TNone{})
  +sk = O.UOp.new(O.Found.ar(en2), O.OpsSINK{},
                  [O.Found.i(st), O.Found.i(st2), O.Found.i(en2), O.Found.i(al)],
                  O.AKernel{O.KernelInfo.of()}, O.TNone{})
  +cll = O.UOp.new(O.Found.ar(sk), O.OpsCALL{}, [O.Found.i(st), O.Found.i(ad)],
                   O.ACall{O.CallInfo.of()}, O.TNone{})
  +sk2 = O.UOp.new(O.Found.ar(cll), O.OpsSINK{}, [O.Found.i(cll)],
                   O.AKernel{O.KernelInfo.of()}, O.TNone{})
  KER.K{F.folded(O.Found.ar(sk2)),
    [0, O.Found.i(c1a), O.Found.i(c1), O.Found.i(c4a), O.Found.i(c4),
     O.Found.i(c16a), O.Found.i(c16), O.Found.i(sp), O.Found.i(bufl), O.Found.i(prm),
     O.Found.i(r_u), O.Found.i(ad), O.Found.i(st), O.Found.i(al), O.Found.i(en),
     O.Found.i(r_b), O.Found.i(ad2), O.Found.i(st2), O.Found.i(en2), O.Found.i(sk),
     O.Found.i(cll), O.Found.i(sk2)]}

# THE TOPOSORT, as `ops.py:1378`'s `toposort(enter_calls=False)` returns it. It is
# a LITERAL and not a walk because the walk is ops.py's and not this file's, and
# a literal that disagrees with the oracle is a GATE ROW (`lin_srcs`) rather than
# a silent difference in every row below it. Read off `lin_srcs`:
#   CONST CAST SPECIAL BUFFER PARAM ADD STORE CONST CAST ADD STORE CONST CAST
#   RANGE:0 END RANGE:1 END ALLOC SINK
def lt_lst() -> List<&2, U32>:
  [1, 2, 7, 8, 9, 11, 12, 5, 6, 16, 17, 3, 4, 10, 14, 15, 18, 13, 19]

# the identity sink's toposort: `SINK(CALL(STORE, ADD))` under
# `enter_calls=False`, so the CALL's `src[0]` is NOT walked and the STORE and the
# PARAM are absent. Six nodes, all rc=1, and the sort is already in nkey order --
# so the heap loop must emit it unchanged. It is also the ONLY test of
# `Arena.src_without_body` in the gate.
def lt_lst_call() -> List<&2, U32>:
  [9, 1, 2, 11, 20, 21]

# W1'S INPUT, length-prefixed (`lt_vm`), read off `lin_vm`.
def lt_vm_lst() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 0, 1, 15, 0, 0, 0]

def lt_vm_call() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0]

# the gate, part one: the linearizer. Every row is derived from python by
# /tmp/opencode/late-oracle.py, which drives tinygrad/codegen/late/linearizer.py
# over this exact fixture and prints its rows in THIS ORDER and with THIS
# SPELLING, so
#   diff <(.venv/bin/python gates/linearizer_census-oracle.py) <(./bin/bend tinybendygrad/codegen/late/linearizer.bend)
# is the acceptance test and NEITHER side can be nudged to match the other.
# both sides of that line were wrong and the oracle is now named. It read
# `python3 /tmp/opencode/late-oracle.py`, which has never existed, against
# `tinybendygrad/codegen/late.bend`, which the port moved INTO `late/` as this file --
# MEASURED 2026-10-16: `late-oracle.py` is absent at every path on every ref
# (`git rev-list --all --objects` names it zero times) and `tinybendygrad/codegen/late.bend`
# was `D` in this tree's history. The oracle that replaced it is
# `gates/linearizer_census-oracle.py`, which is 71 rows, RUNS (rc=0), and READS THIS FILE.
# `oracles/tinybendygrad_codegen_late.bend.rows` is ALSO in HEAD at 128 rows and is NOT in
# `differ.declared()` and has NO CODE READER -- a snapshot with neither a generator nor a
# consumer, reported rather than deleted, because deleting it is not this unit's call.
#
# THE PRINTERS, LEAF FIRST, and there are two because two row classes need two
# alphabets: a `U32` list (`ix`, `lin_nkey`) and a `String` list (`lin_srcs`). A
# shared printer is a shared FORMAT CONTRACT (the notes' rule 22) -- a mutation in
# one invalidates a quarter of the suite, which is the right trade, and it is why
# `lt_u32s` is written once and not three times.
# THE GATE MOVED TO `gates/linearizer-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the census this file prints, and `gates/<name>-gate.bend` is the
# driver that prints them.
